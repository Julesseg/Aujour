import Foundation

/// What changing the Path Template would do to the Entries already in the
/// folder: every file that moves, where it goes, and which days find
/// something already sitting at the path they were going to.
///
/// A value rather than an operation, because it is shown to the user before
/// any of it happens — a migration is skippable (ADR 0002), and what is being
/// skipped has to be sayable.
///
/// The moves are **ordered**, and the order is the safety: walked from the
/// front, no move in a plan ever lands on a file that is there. That is what
/// lets the migration be carried out with a store operation that refuses to
/// overwrite, rather than with one that would and a check beforehand.
public struct MigrationPlan: Hashable, Sendable {
    /// One file, and where it is going.
    public struct Move: Hashable, Sendable {
        /// The Journal Day whose Entry this is — under the *old* template,
        /// which is what makes it an Entry at all until the change is made.
        public let day: JournalDay

        /// Where the file is now, relative to the Journal Root.
        public let from: String

        /// Where it is going, relative to the Journal Root.
        public let to: String

        public let destination: Destination

        public init(day: JournalDay, from: String, to: String, destination: Destination) {
            self.day = day
            self.from = from
            self.to = to
            self.destination = destination
        }
    }

    /// What the path a file is moving to *is* — the three reasons a migration
    /// moves anything.
    public enum Destination: Hashable, Sendable {
        /// The day's Entry path under the new template. After this move that
        /// day is journaled again, at the place the new template names.
        case theDaysNewPath

        /// A name of its own, held while the Entry that is on this day's new
        /// path moves off it. A second move brings the file the rest of the
        /// way; nothing is ever left here.
        case asideWhileThePathClears

        /// Beside the file that already holds the day's new path — carrying
        /// that file's own path, which stays where it is as that day's Entry
        /// (ADR 0002).
        ///
        /// This is a collision, and the only outcome Aujour will not decide
        /// on its own: two files claim one day, neither is Aujour's to merge
        /// or discard, so the incoming one is parked adjacent under the first
        /// free `_1`, `_2`, … suffix and the user is asked first.
        case besideTheFileAlreadyThere(String)
    }

    /// Every move the change comes to, in an order in which none of them
    /// overwrites anything.
    public let moves: [Move]

    public init(moves: [Move]) {
        self.moves = moves
    }

    /// The moves that land beside a file already claiming the day — what the
    /// user is asked about before any of the plan is carried out.
    public var collisions: [Move] {
        moves.filter {
            if case .besideTheFileAlreadyThere = $0.destination { true } else { false }
        }
    }

    /// How many Entries the change is about. Days rather than moves: one that
    /// waits at a name of its own on the way is still one Entry moved.
    public var entryCount: Int {
        Set(moves.map(\.day)).count
    }

    /// Whether the change leaves the folder exactly as it is — a new template
    /// over a folder holding no Entries, or one that names every day the same
    /// path the old one did. There is nothing to offer, and nothing to skip.
    public var isEmpty: Bool { moves.isEmpty }
}

extension MigrationPlan.Move {
    /// What the file will be called once this move is made — the name the
    /// user would go looking for it under in Obsidian or in the Files app,
    /// which is the only part of a path worth putting in a sentence.
    public var name: String { fileName(of: to) }
}

/// The file's own name: the last component of a path relative to the Journal
/// Root, extension and all.
///
/// A path this is asked about has always come from somewhere that already
/// checked it — a `PathTemplate`'s rendering, or a name derived from one — so
/// a path with no components at all answers itself rather than trapping.
func fileName(of path: String) -> String {
    path.split(separator: "/").last.map(String.init) ?? path
}

/// Works out what changing the Path Template would do to a folder of files.
///
/// Pure, and deliberately: a template change is the one operation in Aujour
/// that moves somebody's whole journal at once, and the decisions in it —
/// which files are Entries, where each one goes, which paths are already
/// taken, what order keeps every move from landing on something — are all
/// arithmetic on strings. Kept here, they are tested exhaustively against a
/// listing; kept in the App layer, they would be tested against a folder, one
/// slow case at a time.
///
/// Three things it decides, in order:
///
/// - **What moves.** A file is an Entry exactly when the *old* template
///   renders its path for some day (ADR 0002), so a vault's own notes, its
///   attachments and its Parked Files are not in the plan and are never
///   touched. A day the new template puts where it already is does not move
///   either.
/// - **Where a day goes whose new path is taken.** Taken by something that
///   stays, that is: an Entry on its way out of that path is nobody's
///   collision. A real collision is parked beside the file that is there,
///   under `ConflictPolicy`'s naming — the same `_1`, `_2`, … rule a
///   divergence parks by, because they are the same promise (nothing is
///   overwritten, both versions stay, adjacent so the user meets them).
/// - **What order.** A move is only made once its destination is empty. Where
///   two days swap paths — the month and the day the other way round in a
///   file name, which is a change people really make — no order does that, so
///   one file is moved aside to a name of its own first and brought on
///   afterwards.
public struct MigrationPlanner: Sendable {
    private let policy = ConflictPolicy()

    public init() {}

    /// The plan for changing the Path Template over this folder.
    ///
    /// - Parameters:
    ///   - filesInTheFolder: everything under the Journal Root, as paths
    ///     relative to it — the whole folder and not just its Entries, since
    ///     what is *not* an Entry is what a moving Entry can collide with.
    ///   - oldTemplate: the template in force now, which says which of those
    ///     files are Entries.
    ///   - newTemplate: the template being changed to, which says where each
    ///     of them belongs.
    public func plan(
        for filesInTheFolder: [String],
        changingFrom oldTemplate: PathTemplate,
        to newTemplate: PathTemplate
    ) -> MigrationPlan {
        // By day, so that a plan for one folder reads the same way twice and
        // a user watching it move sees their journal in order.
        var entries: [(day: JournalDay, from: String, to: String)] = []
        for path in filesInTheFolder {
            guard let day = oldTemplate.match(path) else { continue }
            let destination = newTemplate.render(day)
            guard destination != path else { continue }
            entries.append((day: day, from: path, to: destination))
        }
        entries.sort { $0.day < $1.day }

        // The paths that will be empty by the end. A file moving onto one of
        // them is waiting for a move, not colliding with a file.
        let vacated = Set(entries.map(\.from))

        var occupied = Set(filesInTheFolder)
        // Every path the plan has spoken for, so that no two moves are ever
        // sent to one name — a folder's files, the parked names chosen below,
        // and the names files wait at on the way.
        var spokenFor = occupied

        var pending: [MigrationPlan.Move] = []
        for entry in entries {
            guard occupied.contains(entry.to), !vacated.contains(entry.to) else {
                pending.append(
                    MigrationPlan.Move(
                        day: entry.day,
                        from: entry.from,
                        to: entry.to,
                        destination: .theDaysNewPath
                    )
                )
                continue
            }

            let parked = parkedPath(beside: entry.to, avoiding: spokenFor)
            spokenFor.insert(parked)
            pending.append(
                MigrationPlan.Move(
                    day: entry.day,
                    from: entry.from,
                    to: parked,
                    destination: .besideTheFileAlreadyThere(entry.to)
                )
            )
        }

        return MigrationPlan(moves: order(pending, over: &occupied, avoiding: &spokenFor))
    }

    /// Puts the moves in an order in which each one's destination is empty by
    /// the time it is made — and breaks the rings where no such order exists.
    ///
    /// A move waits on at most one other (the templates are each a rule
    /// mapping one day to one path, so a path is wanted by one day and left
    /// by one day), which makes the waiting a set of chains and rings. Chains
    /// come out by taking whichever move is ready; a ring has no move that is
    /// ready, and is opened by sending one file aside to a name of its own —
    /// after which the file behind it can move, and the one sent aside is
    /// brought on when its own path clears.
    ///
    /// Terminates: every turn either makes a move (there are finitely many)
    /// or opens one ring for good (there are finitely many of those too).
    private func order(
        _ moves: [MigrationPlan.Move],
        over occupied: inout Set<String>,
        avoiding spokenFor: inout Set<String>
    ) -> [MigrationPlan.Move] {
        var pending = moves
        var ordered: [MigrationPlan.Move] = []

        while !pending.isEmpty {
            if let next = pending.firstIndex(where: { !occupied.contains($0.to) }) {
                let move = pending.remove(at: next)
                occupied.remove(move.from)
                occupied.insert(move.to)
                ordered.append(move)
                continue
            }

            // Nothing can move: every remaining destination is held by a file
            // that is itself waiting. One of them steps aside.
            let blocked = pending.removeFirst()
            let aside = parkedPath(beside: blocked.to, avoiding: spokenFor)
            spokenFor.insert(aside)
            ordered.append(
                MigrationPlan.Move(
                    day: blocked.day,
                    from: blocked.from,
                    to: aside,
                    destination: .asideWhileThePathClears
                )
            )
            occupied.remove(blocked.from)
            occupied.insert(aside)
            // Still to be made, from where it is waiting — and now the file
            // that wanted this one's old path can be moved.
            pending.append(
                MigrationPlan.Move(
                    day: blocked.day,
                    from: aside,
                    to: blocked.to,
                    destination: blocked.destination
                )
            )
        }

        return ordered
    }

    /// A free name beside a path, by the rule a divergence parks under: the
    /// file's own name with the first `_1`, `_2`, … suffix nothing has taken.
    ///
    /// Traps on a path no folder could hold, which is unreachable here and
    /// said rather than handled: these paths come from a `PathTemplate`, and
    /// a template that could render one is refused when it is built. A
    /// migration that silently skipped a file instead would be a day of
    /// somebody's journal left behind without a word.
    private func parkedPath(beside path: String, avoiding taken: Set<String>) -> String {
        guard let parked = try? policy.parkedPath(for: path, avoiding: taken) else {
            preconditionFailure("A Path Template rendered '\(path)', which no folder could hold")
        }
        return parked
    }
}
