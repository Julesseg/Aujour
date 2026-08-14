import Foundation
import Testing

@testable import AujourCore

// Two devices wrote the same day without knowing about each other, and iCloud
// has brought both versions down. Neither is Aujour's to merge or to throw
// away (ADR 0001): the newest keeps the Entry path, and every other version is
// set aside beside it as a Parked File, where the user will come across it in
// Obsidian or in the Files app.
//
// All of that decision is arithmetic on dates and names, which is why it is
// here — the folder work it turns into is the App layer's, over versions only
// iCloud can produce.

/// The Entry two devices both wrote.
private let entry = "2026/03/2026-03-01.md"

/// A folder holding that Entry and nothing else in its way.
private let folder: Set<String> = [entry]

private let morning = instant(2026, 3, 1, 9, in: paris)
private let afternoon = instant(2026, 3, 1, 15, in: paris)
private let evening = instant(2026, 3, 1, 21, in: paris)

@Suite("Which version keeps the Entry path")
struct ConflictSurvivorTests {
    @Test("the version written last keeps the Entry path")
    func theNewestVersionWins() throws {
        let resolution = try ConflictPolicy().resolve(
            entry,
            writtenAt: morning,
            against: [evening, afternoon],
            beside: folder
        )

        #expect(resolution.keepsTheEntryPath == .another(0))
    }

    @Test("the file already there keeps the Entry path when nothing newer arrived")
    func theFileThereWinsWhenItIsTheNewest() throws {
        let resolution = try ConflictPolicy().resolve(
            entry,
            writtenAt: evening,
            against: [morning, afternoon],
            beside: folder
        )

        #expect(resolution.keepsTheEntryPath == .theFileThere)
    }

    @Test("a day nobody else wrote has nothing to park")
    func noOtherVersionIsNoDivergence() throws {
        let resolution = try ConflictPolicy().resolve(
            entry,
            writtenAt: morning,
            against: [],
            beside: folder
        )

        #expect(resolution.keepsTheEntryPath == .theFileThere)
        #expect(resolution.parked.isEmpty)
    }

    @Test("two versions written at the same moment leave the file where it is")
    func aTieLeavesTheFileWhereItIs() throws {
        // Nothing is newer, so nothing has to move — and a version that has to
        // be parked either way is parked either way. Moving the file for a
        // tie would rewrite an Entry to say what it already said.
        let resolution = try ConflictPolicy().resolve(
            entry,
            writtenAt: afternoon,
            against: [afternoon],
            beside: folder
        )

        #expect(resolution.keepsTheEntryPath == .theFileThere)
        #expect(resolution.parked.map(\.version) == [.another(0)])
    }

    @Test("a version nobody dated never takes the Entry path from one that is dated")
    func anUndatedVersionCannotWin() throws {
        // A version whose modification date the system cannot say is not
        // thereby the newest. It is still kept — it is simply not the one to
        // put in front of the user.
        let arrived = try ConflictPolicy().resolve(
            entry,
            writtenAt: morning,
            against: [nil],
            beside: folder
        )
        #expect(arrived.keepsTheEntryPath == .theFileThere)

        let onDisk = try ConflictPolicy().resolve(
            entry,
            writtenAt: nil,
            against: [morning],
            beside: folder
        )
        #expect(onDisk.keepsTheEntryPath == .another(0))
    }

    @Test("when nothing is dated at all the file stays where it is")
    func nothingDatedLeavesTheFileWhereItIs() throws {
        let resolution = try ConflictPolicy().resolve(
            entry,
            writtenAt: nil,
            against: [nil, nil],
            beside: folder
        )

        #expect(resolution.keepsTheEntryPath == .theFileThere)
        #expect(resolution.parked.map(\.version) == [.another(0), .another(1)])
    }
}

@Suite("Where the version that lost is parked")
struct ParkedFileNamingTests {
    @Test("the version that lost is parked beside the Entry, as _1")
    func theLoserIsParkedAdjacently() throws {
        let resolution = try ConflictPolicy().resolve(
            entry,
            writtenAt: evening,
            against: [morning],
            beside: folder
        )

        // Beside it, and not in a folder of Aujour's own: the whole point is
        // that the user comes across it next to the day it belongs to.
        #expect(resolution.parked == [.init(version: .another(0), path: "2026/03/2026-03-01_1.md")])
    }

    @Test("the file that lost the Entry path is parked too")
    func theFileThereIsParkedWhenItLoses() throws {
        let resolution = try ConflictPolicy().resolve(
            entry,
            writtenAt: morning,
            against: [evening],
            beside: folder
        )

        #expect(resolution.keepsTheEntryPath == .another(0))
        #expect(resolution.parked == [.init(version: .theFileThere, path: "2026/03/2026-03-01_1.md")])
    }

    @Test("the suffix goes before the extension, so a Parked File is still markdown")
    func theSuffixGoesBeforeTheExtension() throws {
        let parked = try ConflictPolicy().parkedPath(for: entry, avoiding: folder)

        #expect(parked.hasSuffix(".md"))
        #expect(parked == "2026/03/2026-03-01_1.md")
    }

    @Test("a suffix the folder already holds is skipped for the first free one")
    func theFirstFreeSuffixIsTaken() throws {
        // `_1` is there from an earlier divergence, or from a migration
        // collision (ADR 0002) — either way it is somebody's words, and the
        // one thing that must not happen to it is being written over.
        let parked = try ConflictPolicy().parkedPath(
            for: entry,
            avoiding: [entry, "2026/03/2026-03-01_1.md", "2026/03/2026-03-01_2.md"]
        )

        #expect(parked == "2026/03/2026-03-01_3.md")
    }

    @Test("three versions park as _1 and _2, in the order they were given")
    func severalVersionsParkInOrder() throws {
        let resolution = try ConflictPolicy().resolve(
            entry,
            writtenAt: evening,
            against: [afternoon, morning],
            beside: folder
        )

        #expect(
            resolution.parked == [
                .init(version: .another(0), path: "2026/03/2026-03-01_1.md"),
                .init(version: .another(1), path: "2026/03/2026-03-01_2.md"),
            ]
        )
    }

    @Test("a path no folder could hold is refused rather than parked")
    func anImpossiblePathIsRefused() throws {
        // The same refusal a Journal Store makes, said here because this is
        // where the name is derived: `..` resolved against a folder inside
        // somebody's vault parks a version somewhere they never pointed
        // Aujour at.
        for impossible in ["", "../2026-03-01.md", "/2026/2026-03-01.md", "2026//2026-03-01.md"] {
            #expect(throws: JournalStoreError.invalidPath(impossible)) {
                try ConflictPolicy().parkedPath(for: impossible, avoiding: [])
            }
            #expect(throws: JournalStoreError.invalidPath(impossible)) {
                try ConflictPolicy().resolve(
                    impossible,
                    writtenAt: morning,
                    against: [evening],
                    beside: []
                )
            }
        }
    }
}

@Suite("Parking never loses a version")
struct ParkingLosesNothingTests {
    /// Every shape a divergence can arrive in: how many versions, in what
    /// order, and with what the system could not say a date for.
    private let divergences: [(theFileThere: Date?, others: [Date?])] = [
        (morning, [evening]),
        (evening, [morning]),
        (afternoon, [afternoon]),
        (morning, [evening, afternoon]),
        (evening, [morning, afternoon]),
        (afternoon, [morning, evening]),
        (nil, [morning, evening]),
        (morning, [nil, evening]),
        (nil, [nil, nil]),
    ]

    @Test("parking never loses either version")
    func parkingLosesNothing() throws {
        // The claim the whole ticket is for. Whatever the dates say, every
        // version that went in comes out exactly once — one of them at the
        // Entry path and the rest at paths of their own, none of which is a
        // file the folder already holds. There is no arrangement of dates that
        // drops one, doubles one up, or writes two of them to one path.
        let occupied: Set<String> = [entry, "2026/03/2026-03-01_1.md"]

        for divergence in divergences {
            let resolution = try ConflictPolicy().resolve(
                entry,
                writtenAt: divergence.theFileThere,
                against: divergence.others,
                beside: occupied
            )

            let everyVersion: [ConflictPolicy.Version] =
                [.theFileThere] + divergence.others.indices.map(ConflictPolicy.Version.another)
            let accountedFor = [resolution.keepsTheEntryPath] + resolution.parked.map(\.version)

            #expect(
                Set(accountedFor) == Set(everyVersion),
                "a version went missing resolving \(divergence)"
            )
            #expect(
                accountedFor.count == everyVersion.count,
                "a version was accounted for twice resolving \(divergence)"
            )

            let landsOn = [entry] + resolution.parked.map(\.path)
            #expect(
                Set(landsOn).count == landsOn.count,
                "two versions were sent to one path resolving \(divergence)"
            )
            #expect(
                resolution.parked.allSatisfy { !occupied.contains($0.path) },
                "a version was parked on top of a file the folder already held, resolving \(divergence)"
            )
        }
    }
}

@Suite("A Parked File is never an Entry")
struct ParkedFilesAreNotEntriesTests {
    @Test("no name the policy parks under reads back as an Entry")
    func parkedFilesDoNotMatchTheTemplate() throws {
        // The other half of the promise: a Parked File sits beside the Entry
        // so the user notices it, and must never itself be taken for the day's
        // Entry — which would put a version they have not merged in front of
        // them as if it were their journal (ADR 0002).
        //
        // It holds because every path a template renders is the same length,
        // and a parked name is that name plus a suffix.
        let templates = [
            "YYYY/MM/YYYY-MM-DD",
            "YYYY-MM-DD",
            "[journal]/YYYY/MM/DD",
            "DD-MM-YYYY",
            "YYYY/MM/DD[ entry]",
        ]
        let days = [
            JournalDay(year: 2026, month: 3, day: 1),
            JournalDay(year: 2026, month: 12, day: 31),
            JournalDay(year: 1999, month: 1, day: 9),
        ]

        for format in templates {
            let template = try PathTemplate(format)
            for day in days {
                let entryPath = template.render(day)
                var taken: Set<String> = [entryPath]
                // Far enough for the suffix to reach two digits, which is
                // where a name could start to look like a date field again.
                for _ in 1...12 {
                    let parked = try ConflictPolicy().parkedPath(for: entryPath, avoiding: taken)
                    #expect(
                        template.match(parked) == nil,
                        "\(parked) reads back as an Entry under \(format)"
                    )
                    taken.insert(parked)
                }
            }
        }
    }
}
