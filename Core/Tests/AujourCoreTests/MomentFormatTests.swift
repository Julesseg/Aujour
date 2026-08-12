import Foundation
import Testing
@testable import AujourCore

// The reference instant for every render test: Sunday 1 March 2026, 14:05:09
// in Paris (CET, UTC+1). Chosen because it exercises the awkward tokens —
// a Sunday (weekday index 0 in Moment, 7 in ISO), day-of-year 60, and a week
// number that differs between the locale week (10) and the ISO week (9).
private let paris = TimeZone(identifier: "Europe/Paris")!
private let english = Locale(identifier: "en_US_POSIX")

private let reference: Date = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = paris
    var components = DateComponents()
    components.year = 2026
    components.month = 3
    components.day = 1
    components.hour = 14
    components.minute = 5
    components.second = 9
    return calendar.date(from: components)!
}()

private func render(_ pattern: String, _ date: Date = reference) -> String {
    MomentFormat(pattern).render(date, timeZone: paris, locale: english)
}

@Suite("MomentFormat date and time tokens")
struct MomentFormatTokenTests {
    @Test("the Obsidian daily-note default renders the calendar date")
    func obsidianDefaultFormat() {
        #expect(render("YYYY-MM-DD") == "2026-03-01")
    }

    @Test("year, month and day tokens render at every width")
    func calendarDateTokens() {
        #expect(render("YYYY") == "2026")
        #expect(render("YY") == "26")
        #expect(render("MMMM") == "March")
        #expect(render("MMM") == "Mar")
        #expect(render("MM") == "03")
        #expect(render("M") == "3")
        #expect(render("Mo") == "3rd")
        #expect(render("DD") == "01")
        #expect(render("D") == "1")
        #expect(render("Do") == "1st")
    }

    @Test("weekday tokens name the day the entry falls on")
    func weekdayTokens() {
        #expect(render("dddd") == "Sunday")
        #expect(render("ddd") == "Sun")
        #expect(render("dd") == "Su")
        #expect(render("d") == "0")
        #expect(render("E") == "7")
    }

    @Test("day-of-year and quarter tokens")
    func ordinalDayAndQuarter() {
        #expect(render("DDDD") == "060")
        #expect(render("DDD") == "60")
        #expect(render("DDDo") == "60th")
        #expect(render("Q") == "1")
        #expect(render("Qo") == "1st")
    }

    // Moment's `w` counts weeks the locale's way (US weeks start on Sunday and
    // week 1 is whichever week holds 1 January), while `W` is always ISO —
    // Monday-start, week 1 holds the first Thursday. On 1 March 2026 the two
    // disagree, which is exactly why both tokens exist.
    @Test("locale weeks and ISO weeks are numbered separately")
    func weekTokens() {
        #expect(render("w") == "10")
        #expect(render("ww") == "10")
        #expect(render("wo") == "10th")
        #expect(render("W") == "9")
        #expect(render("WW") == "09")
        #expect(render("gggg") == "2026")
        #expect(render("GGGG") == "2026")
    }

    @Test("clock tokens render 24-hour, 12-hour and meridiem forms")
    func clockTokens() {
        #expect(render("HH:mm:ss") == "14:05:09")
        #expect(render("H:m:s") == "14:5:9")
        #expect(render("h:mm A") == "2:05 PM")
        #expect(render("h:mm a") == "2:05 pm")
        #expect(render("kk") == "14")
    }

    @Test("midnight is 12 AM on a 12-hour clock and hour 24 on Moment's k")
    func midnightOnTheTwelveHourClock() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = paris
        let midnight = calendar.startOfDay(for: reference)

        #expect(MomentFormat("h:mm A").render(midnight, timeZone: paris, locale: english) == "12:00 AM")
        #expect(MomentFormat("HH").render(midnight, timeZone: paris, locale: english) == "00")
        #expect(MomentFormat("k").render(midnight, timeZone: paris, locale: english) == "24")
    }

    @Test("the UTC offset renders in both Moment spellings")
    func timeZoneOffsetTokens() {
        #expect(render("Z") == "+01:00")
        #expect(render("ZZ") == "+0100")
    }

    @Test("unix timestamp tokens count from the epoch")
    func unixTimestampTokens() {
        #expect(render("X") == String(Int(reference.timeIntervalSince1970)))
        #expect(render("x") == String(Int(reference.timeIntervalSince1970 * 1000)))
    }

    @Test("a format renders against the time zone it is given, not the device's")
    func rendersInTheGivenTimeZone() {
        let utc = TimeZone(secondsFromGMT: 0)!

        #expect(MomentFormat("YYYY-MM-DD HH:mm").render(reference, timeZone: utc, locale: english)
            == "2026-03-01 13:05")
    }
}

@Suite("MomentFormat literal text")
struct MomentFormatLiteralTests {
    @Test("bracketed text is literal, so [Week] W reads as prose")
    func bracketedLiteralsSurviveVerbatim() {
        #expect(render("[Week] W, YYYY") == "Week 9, 2026")
    }

    @Test("brackets can hold characters that would otherwise be tokens")
    func bracketsEscapeTokenLetters() {
        #expect(render("[Day D of] YYYY") == "Day D of 2026")
    }

    @Test("a backslash escapes a single token letter")
    func backslashEscapesOneCharacter() {
        #expect(render("\\Y YYYY") == "Y 2026")
    }

    // Moment has no recovery for a half-typed literal either: the bracket is
    // just a bracket and the tokens after it keep resolving. What matters is
    // that the render still happens.
    @Test("an unclosed bracket is ordinary text and never breaks the render")
    func unclosedBracketIsHarmless() {
        #expect(render("[") == "[")
        #expect(render("YYYY[MM") == "2026[03")
    }

    @Test("punctuation and unknown letters pass through untouched")
    func unknownCharactersPassThrough() {
        #expect(render("YYYY/MM/YYYY-MM-DD") == "2026/03/2026-03-01")
        #expect(render("") == "")
    }

    @Test("a longer run of a token letter consumes the longest token first")
    func longestTokenWins() {
        // Moment reads `MMMMM` as `MMMM` + `M`, not as five separate `M`s.
        #expect(render("MMMMM") == "March3")
    }
}
