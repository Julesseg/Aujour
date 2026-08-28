import AujourCore

/// A day open in front of the user: the one the date pill picked, or the one
/// a search result led to.
///
/// Identified by its day, because that is an Entry's identity — the editor
/// over March 1st is the same thing on screen however often the list or the
/// grid it was reached from redraws underneath it.
struct OpenedDay: Hashable {
    let day: JournalDay
    let editor: EntryEditor

    static func == (lhs: OpenedDay, rhs: OpenedDay) -> Bool { lhs.day == rhs.day }

    func hash(into hasher: inout Hasher) { hasher.combine(day) }
}
