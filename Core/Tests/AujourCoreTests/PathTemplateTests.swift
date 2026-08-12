import Foundation
import Testing
@testable import AujourCore

extension JournalDay {
    fileprivate static let marchFirst = JournalDay(year: 2026, month: 3, day: 1)
}

@Suite("Path Template rendering")
struct PathTemplateRenderingTests {
    @Test("the default template nests the Entry in year and month folders")
    func defaultTemplateRendersTheDocumentedPath() {
        let template = PathTemplate.default

        #expect(template.render(JournalDay(year: 2026, month: 3, day: 1)) == "2026/03/2026-03-01.md")
    }

    @Test("numeric tokens are zero-padded, so paths sort chronologically")
    func singleDigitMonthsAndDaysArePadded() throws {
        let template = try PathTemplate("YYYY-MM-DD")

        #expect(template.render(JournalDay(year: 2026, month: 1, day: 9)) == "2026-01-09.md")
    }

    @Test("bracketed text is copied through verbatim, letters and all")
    func bracketedLiteralsSurviveRendering() throws {
        let template = try PathTemplate("[Daily Notes]/YYYY/[day ]DD-MM-YYYY")

        #expect(
            template.render(JournalDay(year: 2026, month: 3, day: 1))
                == "Daily Notes/2026/day 01-03-2026.md"
        )
    }

    @Test("Obsidian daily-notes formats inside the subset paste over verbatim")
    func obsidianFormatsProduceObsidiansFiles() throws {
        // Formats taken from Obsidian's daily-notes settings, rendered for
        // 2026-03-01 exactly as Obsidian would write them.
        let obsidianFormats = [
            "YYYY-MM-DD": "2026-03-01.md",
            "DD-MM-YYYY": "01-03-2026.md",
            "YYYY/MM/DD": "2026/03/01.md",
            "[Journal]/YYYY/[Q]MM/YYYY-MM-DD": "Journal/2026/Q03/2026-03-01.md",
            "YYYY-MM-DD [Daily Note]": "2026-03-01 Daily Note.md",
        ]

        for (format, expected) in obsidianFormats {
            #expect(try PathTemplate(format).render(.marchFirst) == expected)
        }
    }
}

@Suite("Attachment Path Template")
struct AttachmentPathTemplateTests {
    @Test("the default attachment folder is the documented one")
    func attachmentDefaultRendersTheDocumentedFolder() {
        let template = AttachmentPathTemplate.default

        #expect(template.render(JournalDay(year: 2026, month: 3, day: 1)) == "attachments/2026/03")
    }

    @Test("an attachment folder needs no day, and never gets an extension")
    func attachmentTemplatesAddressFoldersNotFiles() throws {
        // `[attachments]` alone — everything in one folder — is a legitimate
        // choice, and so is a folder that does name the day.
        #expect(try AttachmentPathTemplate("[attachments]").render(.marchFirst) == "attachments")
        #expect(try AttachmentPathTemplate("YYYY/MM/DD").render(.marchFirst) == "2026/03/01")
    }

    @Test("attachment folders are held to the same subset and the same path rules")
    func attachmentTemplatesShareTheSameValidation() {
        #expect(throws: PathTemplateError.unsupportedToken("MMMM")) {
            try AttachmentPathTemplate("[attachments]/MMMM")
        }
        #expect(throws: PathTemplateError.relativePathComponent("..")) {
            try AttachmentPathTemplate("../[attachments]")
        }
        #expect(throws: PathTemplateError.emptyFormat) {
            try AttachmentPathTemplate("")
        }
    }
}

@Suite("Path Template validation")
struct PathTemplateValidationTests {
    @Test("tokens outside the unambiguous subset are refused by name")
    func ambiguousMomentTokensAreRejected() {
        // Month and weekday names, unpadded numbers, two-digit years, week
        // numbers: all render or read back ambiguously.
        for token in ["MMMM", "MMM", "D", "M", "YY", "ddd", "dddd", "DDD", "ww", "YYYYY"] {
            #expect(throws: PathTemplateError.unsupportedToken(token)) {
                try PathTemplate("YYYY-MM-DD-\(token)")
            }
        }

        // Tokens are read as runs of one letter, so Moment's `Do` is refused
        // as `D` — still by name, still before it can reach a path.
        #expect(throws: PathTemplateError.unsupportedToken("D")) {
            try PathTemplate("YYYY-MM-DD-Do")
        }
    }

    @Test("an unbalanced bracket is refused rather than half-read")
    func unterminatedLiteralIsRejected() {
        #expect(throws: PathTemplateError.unterminatedLiteral) {
            try PathTemplate("[journal/YYYY-MM-DD")
        }
    }

    @Test("an empty template is refused")
    func emptyFormatIsRejected() {
        #expect(throws: PathTemplateError.emptyFormat) { try PathTemplate("") }
        #expect(throws: PathTemplateError.emptyFormat) { try PathTemplate("   ") }
    }

    @Test("an Entry template that cannot name a single day is refused")
    func incompleteDatesAreRejected() {
        #expect(throws: PathTemplateError.missingDateTokens(["DD"])) {
            try PathTemplate("YYYY/MM")
        }
        #expect(throws: PathTemplateError.missingDateTokens(["YYYY", "MM"])) {
            try PathTemplate("[day]DD")
        }
    }

    @Test("templates that would escape or confuse the Journal Root are refused")
    func unsafePathShapesAreRejected() {
        #expect(throws: PathTemplateError.relativePathComponent("..")) {
            try PathTemplate("../YYYY-MM-DD")
        }
        #expect(throws: PathTemplateError.relativePathComponent(".")) {
            try PathTemplate("[.]/YYYY-MM-DD")
        }
        #expect(throws: PathTemplateError.emptyPathComponent) {
            try PathTemplate("/YYYY/MM/YYYY-MM-DD")
        }
        #expect(throws: PathTemplateError.emptyPathComponent) {
            try PathTemplate("YYYY//YYYY-MM-DD")
        }
        #expect(throws: PathTemplateError.emptyPathComponent) {
            try PathTemplate("YYYY/MM/YYYY-MM-DD/")
        }
    }

    @Test("spelling out .md is refused, since it is appended automatically")
    func redundantExtensionIsRejected() {
        #expect(throws: PathTemplateError.redundantMarkdownExtension) {
            try PathTemplate("YYYY-MM-DD.md")
        }
        #expect(throws: PathTemplateError.redundantMarkdownExtension) {
            try PathTemplate("YYYY-MM-DD[.MD]")
        }
    }

    @Test("every rejection can be shown to the user as a sentence")
    func errorsExplainThemselves() {
        #expect(
            PathTemplateError.unsupportedToken("MMMM").description.contains("MMMM")
        )
        #expect(PathTemplateError.missingDateTokens(["DD"]).description.contains("DD"))
        #expect(PathTemplateError.emptyFormat.description.hasSuffix("."))
    }
}

@Suite("Path Template matching")
struct PathTemplateMatchingTests {
    @Test("a rendered path reads back as the day it was rendered for")
    func matchInvertsRenderForEveryDay() throws {
        let templates = [
            PathTemplate.default,
            try PathTemplate("YYYY-MM-DD"),
            try PathTemplate("YYYYMMDD"),
            try PathTemplate("[journal]/DD.MM.YYYY"),
        ]

        // Four consecutive years, day by day: leap day, month lengths and
        // year boundaries all fall out of the walk.
        var journalDay = JournalDay(year: 2023, month: 1, day: 1)
        let end = JournalDay(year: 2027, month: 1, day: 1)
        while journalDay < end {
            for template in templates {
                #expect(template.match(template.render(journalDay)) == journalDay)
            }
            journalDay = journalDay.adding(days: 1)
        }
    }

    @Test("the round trip holds at the far ends of the four-digit year")
    func matchInvertsRenderAtTheEdgesOfTheRange() {
        let template = PathTemplate.default

        for journalDay in [
            JournalDay(year: 1, month: 1, day: 1),
            JournalDay(year: 1582, month: 10, day: 5),  // a day the Gregorian cutover eats
            JournalDay(year: 1900, month: 2, day: 28),  // not a leap year, despite the /4
            JournalDay(year: 2000, month: 2, day: 29),  // but this one is
            JournalDay(year: 9999, month: 12, day: 31),
        ] {
            #expect(template.match(template.render(journalDay)) == journalDay)
        }
    }

    @Test("a year that does not fit four digits is outside what paths can address")
    func yearsWiderThanTheTokenAreNotEntries() {
        let template = PathTemplate.default

        #expect(template.match("10000/03/10000-03-01.md") == nil)
    }

    @Test("a Parked File beside an Entry is not itself an Entry")
    func parkedFilesNeverMatch() {
        let template = PathTemplate.default

        #expect(template.match("2026/03/2026-03-01_1.md") == nil)
    }

    @Test("ordinary vault notes are never misread as Entries")
    func nonEntryVaultFilesNeverMatch() {
        let template = PathTemplate.default

        for path in [
            "Meetings/Standup.md",
            "2026/03/Ideas.md",
            "2026/03/2026-03-01.markdown",
            "2026/03/2026-03-01",
            "/2026/03/2026-03-01.md",
            "2026/03/01/2026-03-01.md",
            "2026/2026-03-01.md",
            "attachments/2026/03/photo.jpg",
        ] {
            #expect(template.match(path) == nil, "\(path) should not be an Entry")
        }
    }

    @Test("a path whose repeated tokens disagree is not an Entry")
    func inconsistentDatesNeverMatch() {
        let template = PathTemplate.default

        // The month folder says March, the filename says April: no single day
        // renders to this path, so no Entry lives here.
        #expect(template.match("2026/03/2026-04-01.md") == nil)
    }

    @Test("a path spelling a day that never existed is not an Entry")
    func impossibleDatesNeverMatch() {
        let template = PathTemplate.default

        #expect(template.match("2026/02/2026-02-30.md") == nil)
        #expect(template.match("2026/02/2026-02-29.md") == nil)  // 2026 is not a leap year
        #expect(template.match("2024/02/2024-02-29.md") != nil)  // 2024 is
        #expect(template.match("2026/13/2026-13-01.md") == nil)
        #expect(template.match("2026/00/2026-00-10.md") == nil)
    }

    @Test("digits are ASCII digits, not merely numeric-looking characters")
    func nonASCIIDigitsNeverMatch() throws {
        let template = try PathTemplate("YYYY-MM-DD")

        #expect(template.match("٢٠٢٦-٠٣-٠١.md") == nil)
    }
}
