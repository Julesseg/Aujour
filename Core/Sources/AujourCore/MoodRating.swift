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
/// ## Why the scale is carried, and not just the number
///
/// A bare `4` in a journal is a number with no scale, and the scale is stored
/// nowhere else — so the line would stop meaning anything the moment anybody
/// wondered whether it was out of five or out of ten. `4/5` answers that on
/// its own, wherever a format puts it.
///
/// What the rating does *not* carry is its subject: a fraction in the middle
/// of a journal is still a fraction about nothing. That is the format's to
/// supply — "Today's mood: " by default, or whatever the template worded — and
/// it is why the default format is a sentence rather than a slot on its own.
///
/// ## Why "Today's" in the default
///
/// Because a day's Entry is that day writing. A Monday backfilled on Tuesday
/// says "Today's mood" too, and means Monday's — the same way `{{date}}`
/// resolves to the Journal Day rather than the day somebody was at the
/// keyboard. The word belongs to the file it is in, not to the clock.
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

    /// The rating as the file spells it — what a tap on the widget hands to
    /// ``EntryMarkdown/answering(_:in:with:)``, and what the token's format
    /// then puts its slot's worth of words around.
    ///
    /// The bare answer and not a sentence, because the sentence is the token's:
    /// `{{mood}}` words this "Today's mood: 4/5" and
    /// `{{mood:Woke up feeling {value}}}` words it "Woke up feeling 4/5", and
    /// neither of those is a rating's business.
    public var answer: String {
        "\(value)/\(MoodRating.scale.upperBound)"
    }
}
