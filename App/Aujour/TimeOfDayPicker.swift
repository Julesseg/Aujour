import SwiftUI
import AujourCore

/// The control that says when — a clock face to set, in the system's own
/// picker.
///
/// Here rather than beside either screen because two screens offer the
/// reminder, the welcome and the journal sheet, and they are offering one
/// setting: a picker built twice is a picker that can be built two different
/// ways, and the two ways it can go wrong are both silent. A `DatePicker`
/// draws and reads its `Date` in whatever zone it is standing in, and a
/// ``TimeOfDay`` is written off a day with no daylight saving in it
/// (``TimeOfDay/clockFaceZone``) — so a picker left in the device's zone shows
/// an evening the user never chose, and hands back an hour that was never set.
///
/// The label is asked for rather than assumed: on the sheet the row says
/// "Time" beside it, and the welcome hides it entirely.
struct TimeOfDayPicker: View {
    let label: String

    @Binding var time: TimeOfDay

    var body: some View {
        DatePicker(
            label,
            selection: $time.clockFace,
            displayedComponents: .hourAndMinute
        )
        .environment(\.timeZone, TimeOfDay.clockFaceZone)
    }
}

extension Binding where Value == TimeOfDay {
    /// The same setting seen as the instant a `DatePicker` moves around.
    var clockFace: Binding<Date> {
        Binding<Date>(
            get: { wrappedValue.clockFace },
            set: { wrappedValue = TimeOfDay(clockFace: $0) }
        )
    }
}
