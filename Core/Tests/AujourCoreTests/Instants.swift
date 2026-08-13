import Foundation

// Instants are written as wall-clock readings in a named zone, because that
// is how the domain talks about them: "1 AM on March 2nd in Paris".
func instant(
    _ year: Int, _ month: Int, _ day: Int,
    _ hour: Int, _ minute: Int = 0, _ second: Int = 0,
    in timeZone: TimeZone
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return calendar.date(from: components)!
}

// Paris for the ordinary cases and its DST transitions; UTC where a test needs
// a zone with no rules of its own to get in the way.
let paris = TimeZone(identifier: "Europe/Paris")!
let utc = TimeZone(secondsFromGMT: 0)!
