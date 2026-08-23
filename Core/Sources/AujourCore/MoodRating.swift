import Foundation

/// How a day's mood is asked for, and what it becomes once it is answered: one
/// of five marks, and the sentence that goes in the file in place of the
/// `{{mood}}` token.
///
/// The half of the mood widget that needs no screen. Which stretches of an
/// Entry are an unanswered question, and that answering one rewrites those
/// characters, is ``InteractivePlaceholder``'s and is the same for every
/// placeholder. What is *here* is the part that is mood's alone and that the
/// folder keeps: the scale the widget offers, and the words a rating is
/// written down as.
///
/// It is here rather than in the app because the sentence outlives the widget
/// (ADR 0001). What a tap leaves behind is a line of somebody's journal, read
/// next year in Obsidian by something that has never heard of Aujour — so it
/// is a plain English sentence, and it is decided and tested where the rest of
/// the file's shape is.
///
/// ## Why "Today's"
///
/// Because a day's Entry is that day writing. A Monday backfilled on Tuesday
/// says "Today's mood" too, and means Monday's — the same way `{{date}}`
/// resolves to the Journal Day rather than the day somebody was at the
/// keyboard. The word belongs to the file it is in, not to the clock.
///
/// ## Why not a number written on its own
///
/// A bare `4/5` in the middle of a journal is a fraction with no subject. The
/// sentence says what was rated, which is what makes the line readable by a
/// person, greppable by a tool, and no worse than what a hand would have typed.
public struct MoodRating: Equatable, Sendable {
    /// The marks the widget puts up. Five, and deliberately fixed: a scale the
    /// user could change is a journal whose old entries mean something else
    /// than they say, since nothing but the sentence itself records which
    /// scale a day was rated on. A named scale of the user's own is
    /// `{{scale:Name}}`, which is roadmap and not v1.
    public static let scale: ClosedRange<Int> = 1...5

    /// Every rating, in the order the widget offers them — worst first, so the
    /// marks read left to right as they are drawn.
    public static let all: [MoodRating] = scale.compactMap(MoodRating.init)

    /// Where on the scale, which is always within it.
    public let value: Int

    /// A rating, or `nil` for a number that is not one of the marks offered.
    ///
    /// Failable rather than clamping, because a mood nobody chose is not a
    /// mood: an out-of-range number reaching here is a bug in whatever is
    /// putting the marks up, and rounding it into range would write a day's
    /// mood into the journal that nobody said.
    public init?(_ value: Int) {
        guard MoodRating.scale.contains(value) else { return nil }
        self.value = value
    }

    /// The plain markdown that takes the token's place — what a tap on the
    /// widget writes into the day, handed to
    /// ``EntryMarkdown/answering(_:in:with:)`` as the answer.
    public var answer: String {
        "Today's mood: \(value)/\(MoodRating.scale.upperBound)"
    }
}
