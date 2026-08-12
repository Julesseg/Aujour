import Foundation
import Testing
@testable import AujourCore

private let paris = TimeZone(identifier: "Europe/Paris")!
private let english = Locale(identifier: "en_US_POSIX")

private func instant(
    _ year: Int, _ month: Int, _ day: Int,
    _ hour: Int, _ minute: Int = 0, _ second: Int = 0
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = paris
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return calendar.date(from: components)!
}

// A backfill: the Entry is Sunday 1 March, but it is being written on
// Wednesday 4 March at 14:05. Every test uses this split so that "which
// moment does this placeholder describe?" is always an answerable question.
private let spawn = SpawnContext(
    day: JournalDay(year: 2026, month: 3, day: 1),
    instant: instant(2026, 3, 4, 14, 5, 9),
    title: "2026-03-01",
    timeZone: paris,
    locale: english
)

private func render(_ source: String, in context: SpawnContext = spawn) -> String {
    ContentTemplate(source).render(at: context)
}

@Suite("ContentTemplate core placeholders")
struct ContentTemplateCorePlaceholderTests {
    @Test("bare {{date}} and {{time}} use Obsidian's default formats")
    func bareCorePlaceholderDefaults() {
        #expect(render("{{date}}") == "2026-03-01")
        #expect(render("{{time}}") == "14:05")
    }

    @Test("{{title}} is the Entry's title")
    func titlePlaceholder() {
        #expect(render("# {{title}}") == "# 2026-03-01")
    }

    @Test("{{date:FORMAT}} renders the Entry's day in the given Moment format")
    func dateWithExplicitFormat() {
        #expect(render("{{date:dddd, MMMM Do YYYY}}") == "Sunday, March 1st 2026")
        #expect(render("{{date:YYYY/MM/DD}}") == "2026/03/01")
    }

    @Test("{{time:FORMAT}} renders the wall clock at spawn")
    func timeWithExplicitFormat() {
        #expect(render("{{time:h:mm a}}") == "2:05 pm")
        #expect(render("{{time:HH:mm:ss}}") == "14:05:09")
    }

    // Obsidian resolves {{date:…}} against the note's date carrying *today's*
    // clock time, which is why {{date:HH:mm}} is a live clock and not 00:00.
    // Backfilling 1 March on 4 March has to reproduce that exactly.
    @Test("{{date:FORMAT}} carries the Entry's day but the current time of day")
    func dateCarriesTheCurrentClockTime() {
        #expect(render("{{date:YYYY-MM-DD HH:mm}}") == "2026-03-01 14:05")
    }

    @Test("placeholder names are case-insensitive and tolerate inner spaces")
    func namesAreForgiving() {
        #expect(render("{{DATE}}") == "2026-03-01")
        #expect(render("{{ date }}") == "2026-03-01")
        #expect(render("{{ Date : YYYY }}") == "2026")
        #expect(render("{{TITLE}}") == "2026-03-01")
    }
}

@Suite("ContentTemplate date offsets")
struct ContentTemplateOffsetTests {
    @Test("{{date±Nunit}} shifts the Entry's day before formatting")
    func offsetsShiftTheAnchor() {
        #expect(render("{{date-1d:YYYY-MM-DD}}") == "2026-02-28")
        #expect(render("{{date+1d:YYYY-MM-DD}}") == "2026-03-02")
        #expect(render("{{date+1M:YYYY-MM-DD}}") == "2026-04-01")
        #expect(render("{{date-1y:YYYY-MM-DD}}") == "2025-03-01")
        #expect(render("{{date+2w:YYYY-MM-DD}}") == "2026-03-15")
        #expect(render("{{date-1Q:YYYY-MM-DD}}") == "2025-12-01")
        #expect(render("{{time-30s:HH:mm:ss}}") == "14:04:39")
        #expect(render("{{time+3h:HH:mm}}") == "17:05")
    }

    // Moment reads `M` as months and `m` as minutes; the offset unit is the
    // one place in the syntax where case changes the meaning.
    @Test("the offset unit distinguishes months from minutes by case")
    func offsetUnitsAreCaseSensitive() {
        #expect(render("{{time+90m:HH:mm}}") == "15:35")
        #expect(render("{{date+2M:YYYY-MM}}") == "2026-05")
    }

    @Test("{{yesterday}} and {{tomorrow}} bracket the Entry's day")
    func yesterdayAndTomorrow() {
        #expect(render("[[{{yesterday}}]] · [[{{tomorrow}}]]")
            == "[[2026-02-28]] · [[2026-03-02]]")
    }

    @Test("an offset without a format still uses the default date format")
    func offsetWithoutFormat() {
        #expect(render("{{date-1d}}") == "2026-02-28")
    }
}

@Suite("ContentTemplate placeholder kinds")
struct ContentTemplatePlaceholderKindTests {
    @Test("interactive placeholders pass through as literal text for the editor")
    func interactivePlaceholdersSurviveVerbatim() {
        #expect(render("Mood: {{mood}}") == "Mood: {{mood}}")
        #expect(render("At {{location}}.") == "At {{location}}.")
    }

    @Test("an interactive placeholder is re-emitted exactly as it was written")
    func interactivePassThroughIsByteForByte() {
        #expect(render("{{ MOOD }}") == "{{ MOOD }}")
    }

    @Test("unknown placeholders render empty")
    func unknownPlaceholdersRenderEmpty() {
        #expect(render("a{{nonsense}}b") == "ab")
        // Data placeholders have no providers yet, so they are unknown today.
        #expect(render("{{events}}{{reminders}}") == "")
    }

    @Test("the registered interactive set is what decides pass-through")
    func interactiveRegistryIsInjectable() {
        var context = spawn
        context.interactivePlaceholders = ["weather"]

        #expect(render("{{weather}}", in: context) == "{{weather}}")
        #expect(render("{{mood}}", in: context) == "")
    }
}

@Suite("ContentTemplate malformed input")
struct ContentTemplateMalformedInputTests {
    @Test("an unclosed placeholder stays ordinary text")
    func unclosedBracesAreText() {
        #expect(render("{{date") == "{{date")
        #expect(render("a {{ b") == "a {{ b")
        #expect(render("}}{{") == "}}{{")
    }

    @Test("empty and unparseable braces stay ordinary text")
    func unparseableBracesAreText() {
        #expect(render("{{}}") == "{{}}")
        #expect(render("{{ }}") == "{{ }}")
        #expect(render("{{da te}}") == "{{da te}}")
        #expect(render("{{date+}}") == "{{date+}}")
        #expect(render("{{date+1}}") == "{{date+1}}")
    }

    @Test("a stray extra brace leaves the placeholder inside it working")
    func extraBracesDoNotSwallowThePlaceholder() {
        #expect(render("{{{date}}") == "{2026-03-01")
        #expect(render("{{a {{date}}") == "{{a 2026-03-01")
    }

    @Test("a template with no placeholders is returned unchanged")
    func plainMarkdownIsUntouched() {
        let markdown = "# Notes\n\n- [ ] one\n- [ ] two\n\n$100 {of stuff}\n"

        #expect(render(markdown) == markdown)
    }
}

@Suite("ContentTemplate against a real Obsidian template")
struct ContentTemplateObsidianParityTests {
    // The acceptance criterion in prose: an Obsidian daily-note template
    // pasted into Aujour spawns content indistinguishable from Obsidian's.
    @Test("a pasted Obsidian daily-note template spawns identical content")
    func obsidianDailyNoteTemplatePastesOverUnchanged() {
        let template = """
            # {{title}}

            Created {{date:dddd, MMMM Do YYYY}} at {{time}}.

            << [[{{date-1d:YYYY-MM-DD}}]] | [[{{date+1d:YYYY-MM-DD}}]] >>

            ## Log

            ## Tasks
            - [ ]
            """

        let expected = """
            # 2026-03-01

            Created Sunday, March 1st 2026 at 14:05.

            << [[2026-02-28]] | [[2026-03-02]] >>

            ## Log

            ## Tasks
            - [ ]
            """

        #expect(render(template) == expected)
    }

    @Test("the default date format is the Journal's, not a hard-coded one")
    func defaultDateFormatIsInjectable() {
        var context = spawn
        context.dateFormat = MomentFormat("DD/MM/YYYY")

        #expect(render("{{date}} / {{yesterday}}", in: context) == "01/03/2026 / 28/02/2026")
    }
}
