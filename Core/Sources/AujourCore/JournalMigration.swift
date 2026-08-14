import Foundation

/// A Path Template change, made over the folder: what it would do, and then
/// doing it.
///
/// The two are separate on purpose, and the gap between them is where the
/// user is. Changing the template changes what an Entry *is* (ADR 0002), so
/// Aujour offers to move the files that were Entries under the old rule —
/// and the offer has to say how many, and name the days whose new path
/// already holds somebody else's file, before a single thing moves. So this
/// plans, shows its work, and only then carries it out.
///
/// The thinking is all in `MigrationPlanner`, which is pure; what is left
/// here is the folder work — a listing, and the moves in the order the plan
/// puts them in. Every move goes through the Journal Store, whose `move`
/// refuses an occupied destination rather than replacing it, so "nothing is
/// ever overwritten" is a property of the seam and not of a check made here.
public struct JournalMigration: Sendable {
    private let store: any JournalStore
    private let planner = MigrationPlanner()

    /// - Parameter store: the folder the Entries are in and stay in — a
    ///   migration reshapes a Journal Root, it never moves out of one.
    public init(over store: any JournalStore) {
        self.store = store
    }

    /// What changing the Path Template would do to the folder as it is right
    /// now.
    ///
    /// Read afresh each time it is asked, because it is what the user is
    /// shown and then asked to agree to: a plan made at launch and offered an
    /// hour later would be about a folder that has since had a day written in
    /// it.
    public func plan(
        changingFrom oldTemplate: PathTemplate,
        to newTemplate: PathTemplate
    ) async throws -> MigrationPlan {
        planner.plan(
            for: try await store.listFiles(),
            changingFrom: oldTemplate,
            to: newTemplate
        )
    }

    /// Makes the plan's moves, in the order it puts them in, and answers what
    /// became of each day.
    ///
    /// Does not throw, and deliberately: a folder shared with iCloud and with
    /// Obsidian can refuse one file — not brought down yet, or something
    /// arrived at a path that was free when the plan was made — and stopping
    /// a journal's migration halfway on account of one day would leave the
    /// user with no way to tell which days had moved. So every refusal is
    /// carried in the outcome instead, next to what did move; the file it is
    /// about is exactly where it was, and asking again is safe.
    ///
    /// A day that could not make one of its moves is not chased through the
    /// rest of them. The moves for one day are a sequence — aside, and then
    /// on — and the second of them over a file that never left is a refusal
    /// about a file that is not the one the user needs telling about.
    public func carryOut(_ plan: MigrationPlan) async -> MigrationOutcome {
        var moved: [JournalDay] = []
        var parked: [MigrationOutcome.ParkedFile] = []
        var leftBehind: [MigrationOutcome.LeftBehind] = []
        var givenUpOn: Set<JournalDay> = []

        for move in plan.moves {
            guard !givenUpOn.contains(move.day) else { continue }
            do {
                try await store.move(from: move.from, to: move.to)
                switch move.destination {
                case .theDaysNewPath:
                    moved.append(move.day)
                case .besideTheFileAlreadyThere:
                    parked.append(
                        MigrationOutcome.ParkedFile(day: move.day, path: move.to)
                    )
                case .asideWhileThePathClears:
                    // Not there yet: the move that brings it the rest of the
                    // way is what this day is counted by.
                    break
                }
            } catch {
                givenUpOn.insert(move.day)
                leftBehind.append(
                    MigrationOutcome.LeftBehind(day: move.day, path: move.from, problem: error)
                )
            }
        }

        return MigrationOutcome(moved: moved, parked: parked, leftBehind: leftBehind)
    }
}

/// What a migration did: the days that moved, the ones kept beside a file
/// that already claimed them, and the ones the folder would not move.
///
/// Three lists rather than a success or a failure, because a migration is
/// rarely all of one. What matters to the user is which of their days are
/// where, and every day in the plan is in exactly one of these.
public struct MigrationOutcome: Sendable {
    /// A version kept beside the file that already held its day's new path —
    /// a Parked File, and so not an Entry, whatever it was before the
    /// template changed (ADR 0002).
    public struct ParkedFile: Hashable, Sendable {
        /// The Journal Day it is a version of, under the template that has
        /// just stopped being in force.
        public let day: JournalDay

        /// Where it is now, relative to the Journal Root.
        public let path: String

        public init(day: JournalDay, path: String) {
            self.day = day
            self.path = path
        }

        /// What the user will see the file called in Obsidian or in the Files
        /// app — which is the whole reason it was put beside the Entry.
        public var name: String { fileName(of: path) }
    }

    /// A day the folder would not move, and where its file still is.
    public struct LeftBehind: Sendable {
        public let day: JournalDay

        /// Where the file is — which is where it was, since a move that is
        /// refused is a move that did not happen.
        public let path: String

        public let problem: any Error

        public init(day: JournalDay, path: String, problem: any Error) {
            self.day = day
            self.path = path
            self.problem = problem
        }
    }

    /// The days now at the path the new template names for them.
    public let moved: [JournalDay]

    /// The days whose new path was already taken, and where each was kept.
    public let parked: [ParkedFile]

    /// The days that could not be moved. Nothing about them was lost — their
    /// files are untouched, and changing the template again, or trying again,
    /// starts from what the folder actually holds.
    public let leftBehind: [LeftBehind]

    public init(
        moved: [JournalDay],
        parked: [ParkedFile],
        leftBehind: [LeftBehind]
    ) {
        self.moved = moved
        self.parked = parked
        self.leftBehind = leftBehind
    }

    /// Whether every day the plan was about ended up where the plan said.
    public var wentThrough: Bool { leftBehind.isEmpty }
}
