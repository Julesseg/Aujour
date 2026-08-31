import AujourCore
import Testing
import UIKit

@testable import Aujour

// What the banner over a day written twice says, and what it is drawn in.
//
// Both halves matter and neither needs a screen. The words are the only place
// the user learns the name of the file they will go looking for, and the
// colours are the promise that nothing went wrong: two versions of a day are
// two people's worth of somebody's words, both still there, and an app that
// coloured that like a failure would be telling them otherwise.

private let march1 = JournalDay(year: 2026, month: 3, day: 1)

private func kept(_ names: String...) -> [ParkedFile] {
    names.map { ParkedFile(path: "2026/03/\($0)", day: march1) }
}

@MainActor
private func notice(about files: [ParkedFile], in accent: Accent = .clay) -> ParkedFilesNotice {
    ParkedFilesNotice(files: files, accent: accent, show: { _ in }, acknowledge: {})
}

@MainActor
@Suite("What a day written twice says for itself")
struct ParkedFileNoticeTests {
    @Test("the banner names the file the other version was kept as")
    func itNamesTheFile() {
        let said = notice(about: kept("2026-03-01_1.md"))

        #expect(said.sentence == "Another version of this day was kept as 2026-03-01_1.md")
    }

    /// The name and not the path: what the user is being told is what they
    /// will see the file called when they meet it in Obsidian or in Files,
    /// which is the whole reason it was put beside the Entry.
    @Test("every version kept is named, however many there are")
    func itNamesEveryFile() {
        let said = notice(about: kept("2026-03-01_1.md", "2026-03-01_2.md"))

        #expect(
            said.sentence
                == "Other versions of this day were kept, as 2026-03-01_1.md and 2026-03-01_2.md"
        )
    }

    /// The sentence the whole banner exists to say. Nothing went wrong, and
    /// the app has not decided anything about either version's contents
    /// (ADR 0001).
    @Test("it says plainly that nothing was lost")
    func itSaysNothingWasLost() {
        #expect(notice(about: kept("2026-03-01_1.md")).reassurance == "Nothing was lost.")
    }

    /// Never an error colour, and that is what this holds: every colour the
    /// banner draws with is one of the identity's own — the reader's accent
    /// and the two inks — and the identity has no error colour in it at all.
    /// A banner that had reached for `.systemRed`, or for anything else off
    /// the palette, fails here rather than on somebody's screen.
    ///
    /// Asked of all nine accents, because the banner is tinted by whichever
    /// one the reader chose and a fixed colour would pass on one of them.
    @Test("the banner is drawn in the reader's accent, never in a warning", arguments: Accent.allCases)
    func theBannerIsTheAccentsAndNeverAWarning(accent: Accent) {
        let said = notice(about: kept("2026-03-01_1.md"), in: accent)

        // A shape takes the accent and a word takes its ink shade — the rule
        // the whole palette rests on (`Accent.inkColor`).
        #expect(said.mark == accent.uiColor)
        #expect(said.actionInk == accent.inkColor)
        #expect(said.sentenceInk == Palette.ink)
        #expect(said.reassuranceInk == Palette.inkMuted)
        #expect(said.dismissInk == Palette.inkFaint)
    }

    /// The design file's "Compare" had no handler and no referent in the
    /// model. Aujour forms no opinion about two files' contents, so the one
    /// thing it offers is where the other one lies (`CONTEXT.md`, Parked
    /// File; `v1-decisions.md`).
    @Test("its one action is to show the file, not to compare the two")
    func itsOneActionIsToShowTheFile() {
        #expect(ParkedFilesNotice.action == "Show in Files")
    }
}
