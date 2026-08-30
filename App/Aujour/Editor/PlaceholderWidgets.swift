import AujourCore
import SwiftUI

/// The half of an interactive placeholder that needs a screen: what its widget
/// says while the question is open, and what answering it asks.
///
/// Which stretches of an Entry are a widget, and what answering one writes, is
/// ``AujourCore/InteractivePlaceholder``'s — decided from the text alone and
/// unit-tested against it. What is left is what no amount of reading the text
/// can say, and it is all here: a name, a symbol, and the thing that comes up
/// when a finger lands on the pill.
///
/// Every one of them is a `switch` over the enum with no `default` in it, so
/// registering a placeholder in Core stops the compiler here until it has been
/// given a face. That is the whole of what adding one costs.
extension InteractivePlaceholder {
    /// What the chip says. A word, because it stands in the middle of a
    /// sentence somebody is writing.
    var title: String {
        switch self {
        case .mood: "Mood"
        case .location: "Location"
        }
    }

    /// The symbol beside it.
    var symbol: String {
        switch self {
        case .mood: "face.smiling"
        case .location: "mappin.and.ellipse"
        }
    }
}

/// A widget the user tapped, and the way back into the Entry it stands in.
///
/// The tap happens in a text view and the answer is asked for in a sheet,
/// which are two different worlds — so what crosses between them is this: the
/// placeholder being asked, and a closure that puts the answer where the token
/// is. Nothing about the Entry, the file or the cursor travels with it, and
/// the closure is the editor's own so that answering goes in through the same
/// door a ticked box does — one edit, one undo step, saved as typing is.
struct PlaceholderQuestion: Identifiable {
    /// New for every tap, so that asking the same question twice puts the
    /// sheet up twice.
    let id = UUID()

    let placeholder: InteractivePlaceholder

    /// Writes the answer into the Entry in place of the token — or leaves the
    /// Entry exactly as it is, for an answer with nothing in it, and for a
    /// token that has stopped being there while the sheet was up.
    let answered: (String) -> Void
}

/// The sheet a tapped widget puts up.
///
/// The chrome is the same for every placeholder — a title, a way out, and a
/// way to answer — and what fills it is the placeholder's own. Cancelling
/// writes nothing at all, which leaves the token where it stands: a question
/// nobody answered is still a question, and it will be a widget again the next
/// time the day is opened.
struct PlaceholderAnswerSheet: View {
    let question: PlaceholderQuestion

    /// Where the device says it is, for the one placeholder that asks — the
    /// device's own, unless a test or a preview says otherwise.
    ///
    /// Handed to the sheet rather than reached for inside it, like every other
    /// seam in the app: a UI test may not have the device's, and a widget that
    /// went looking for one itself would put a system alert in the middle of
    /// one.
    let places: (any Places)?

    /// Where the day's photographs are read from, for the same placeholder and
    /// on the same terms — the positions they carry are the other half of what
    /// it offers.
    let library: (any PhotoLibrary)?

    /// The Journal Day the Entry is about, which is the day whose photographs
    /// are read: a Monday filled in on Friday is offered Monday's.
    let day: JournalDay?

    @Environment(\.dismiss) private var dismiss

    init(
        question: PlaceholderQuestion,
        from places: (any Places)? = nil,
        photographsFrom library: (any PhotoLibrary)? = nil,
        for day: JournalDay? = nil
    ) {
        self.question = question
        self.places = places
        self.library = library
        self.day = day
    }

    var body: some View {
        NavigationStack {
            answering
                .navigationTitle(question.placeholder.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .accessibilityIdentifier("cancelPlaceholder")
                    }
                }
        }
        // Half the screen to begin with, and draggable to all of it: the
        // place widget's list of somewhere-you-might-be is longer than a
        // rating is, and a sheet that could only ever be half is one nobody
        // can read the bottom of.
        .presentationDetents([.medium, .large])
        // The identity's own paper for a sheet, which is a hair off the page's
        // so that a sheet over a screen reads as being in front of it. Both
        // arms sit on it: the place widget's list hides the system's grouped
        // ground and puts its rows on the identity's card, so that one sheet
        // is one sheet whichever question it came up to ask.
        //
        // Nothing here tints anything. The way out is already the accent this
        // device chose, because `AujourApp` tints the whole app with it and a
        // sheet inherits the environment of the view that put it up.
        .presentationBackground(Palette.sheetColor)
        .accessibilityIdentifier("placeholderAnswer")
    }

    @ViewBuilder private var answering: some View {
        switch question.placeholder {
        // Both of v1's placeholders are drawn their own way. There is no
        // fallback arm and no `default:`, so a placeholder registered later
        // does not compile until somebody has decided what answering it looks
        // like — which is the one thing no amount of reading the text can say.
        case .mood: MoodAnsweredByRating(question: question)
        case .location:
            PlaceholderAnsweredWithAPlace(
                question: question, from: places, photographsFrom: library, for: day
            )
        }
    }
}

/// Answering {{mood}} by rating the day.
///
/// One tap and the question is gone. The marks are the whole of the form —
/// there is no second field to fill and nothing to check over — so a
/// confirmation button would be a press that could only ever repeat the one
/// before it. That is the same bargain a task's box makes, and it is undone the
/// same way: the answer is an edit in the Entry's own undo stack, so a mark
/// pressed by mistake is taken back the way a line typed by mistake is.
///
/// What each mark writes is ``AujourCore/MoodRating``'s, and it lives in Core
/// rather than here because the sentence outlives the sheet: what a tap leaves
/// behind is a line of the user's journal, read afterwards by everything that
/// has never heard of this screen (ADR 0001).
///
/// ## Why the five marks are here and not in the Entry
///
/// The design files draw unanswered {{mood}} as five dots sitting in the
/// sentence, each tappable, answered without a sheet ever coming up. That is
/// the one place the aesthetic and the model disagree, and the model wins: it
/// would be a second interaction for one placeholder out of the set, hit-tested
/// inside a painted glyph, and {{location}} could never use it. So the Entry
/// draws one chip over the whole token like every other placeholder, and the
/// dots move here — which is where answering already happens, and where the
/// design's styling is a genuine improvement on a row of numbered circles.
private struct MoodAnsweredByRating: View {
    let question: PlaceholderQuestion

    @Environment(\.dismiss) private var dismiss
    @Environment(\.editorLook) private var look

    /// The mark under the finger, while there is a finger on the scale.
    ///
    /// The whole of what makes five identical dots a scale rather than five
    /// buttons: nothing on screen says which end is which until somebody's
    /// thumb is on it, and then the marks fill up to it and the reading under
    /// them says what it would write. It is the design's own middle state, and
    /// it costs a press to see because a press is the only moment there is —
    /// one tap answers and the sheet goes.
    @State private var pressing: MoodRating?

    /// How big a mark is, before Dynamic Type has it.
    ///
    /// Bounded above, which almost nothing in this app is. A scale somebody
    /// cannot see all of at once is not a scale, and at the largest
    /// accessibility size this would be three times over — 93 points a mark,
    /// 465 of them before a single gap, on a phone 320 wide. So the marks grow
    /// with the reader's text size until they fill the touch target they
    /// already have, and stop there; the reading under them is words, and goes
    /// on growing.
    @ScaledMetric(relativeTo: .body) private var markAtThisTextSize: CGFloat = 30

    /// The mark, and its halo, inside the touch target it already has — so
    /// the glow under the one being pressed never reaches the mark beside it.
    private var mark: CGFloat { min(markAtThisTextSize, touchable - halo * 2) }

    /// The smallest thing a finger is asked to land on.
    private let touchable: CGFloat = 44

    /// The outline of a mark nobody has reached — the design's `1.3px` border,
    /// at the nearest thing a screen can actually draw.
    ///
    /// A number rather than a role because the identity has none for a stroke:
    /// `Rounding` is corners and `Spacing` is gaps, and the one other hairline
    /// in the app is a rule measured in device pixels rather than points.
    private let outline: CGFloat = 1.5

    /// How far the glow under the mark being pressed reaches past it — the
    /// design's `0 0 0 3px`, on the identity's tightest step.
    private let halo = Spacing.tight

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the marks fill with. Nothing at all for a reader who asked for
    /// less movement — the fill is what says which mark the finger is on, so
    /// it still happens, it just stops travelling to get there.
    private var filling: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.12)
    }

    var body: some View {
        VStack(spacing: Spacing.apart) {
            Text("How was the day?")
                .lettering(.pageVoice)
                .foregroundStyle(Palette.inkMutedColor)

            HStack(spacing: Spacing.tight) {
                ForEach(MoodRating.all, id: \.value) { rating in
                    Button { answer(rating) } label: { face(of: rating) }
                        .buttonStyle(MarkUnderTheFinger(rating: rating, pressing: $pressing))
                        // The marks are numbers to VoiceOver whatever they are
                        // on screen, because the sentence they write is one:
                        // nothing here claims to know what a 4 felt like.
                        .accessibilityLabel(
                            "\(rating.value) out of \(MoodRating.scale.upperBound)"
                        )
                        .accessibilityIdentifier("moodRating\(rating.value)")
                }
            }
            .padding(.horizontal, Spacing.comfortable)
            .padding(.vertical, Spacing.tight)
            .background(look.accent.soft, in: Capsule())

            // The mark under the finger, spelled the way the file spells one —
            // "4/5" and not "4", because the scale travels with the number
            // (``AujourCore/MoodRating``). Not the whole line the Entry will
            // end up holding: what words a rating is the token's format's, and
            // a sheet that promised a sentence would be promising one the
            // template may not have asked for.
            //
            // Always laid out and only sometimes visible, so that the scale
            // does not jump the moment a thumb lands on it.
            Text(pressing?.answer ?? MoodRating.all.first?.answer ?? "")
                .lettering(.chipLabel)
                .foregroundStyle(look.accent.color)
                .opacity(pressing == nil ? 0 : 1)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.apart)
    }

    /// One mark: an outline until the finger reaches it, the accent once it
    /// has, and the design's halo under the one being pressed.
    private func face(of rating: MoodRating) -> some View {
        let reached = rating.value <= (pressing?.value ?? 0)
        return ZStack {
            Circle()
                .fill(look.accent.color)
                .opacity(reached ? 1 : 0)
            Circle()
                .strokeBorder(Palette.inkFaintColor, lineWidth: outline)
                .opacity(reached ? 0 : 1)
        }
        .frame(width: mark, height: mark)
        .background {
            Circle()
                .fill(look.accent.softer)
                .padding(-halo)
                .opacity(pressing == rating ? 1 : 0)
        }
        .animation(filling, value: pressing)
        // A mark is smaller than a finger. What answers one is not.
        .frame(minWidth: touchable, minHeight: touchable)
        .contentShape(Rectangle())
    }

    private func answer(_ rating: MoodRating) {
        question.answered(rating.answer)
        dismiss()
    }
}

/// Says which mark is under the finger, so the marks before it can fill.
///
/// A button style because a press is a button's own business and there is no
/// other way to be told about one — a gesture over the row would have to work
/// out which mark a point landed on, which is the layout's arithmetic done
/// twice and got wrong once. Each mark reports itself, and only takes the
/// report back if it is still the one holding it.
private struct MarkUnderTheFinger: ButtonStyle {
    let rating: MoodRating

    @Binding var pressing: MoodRating?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    pressing = rating
                } else if pressing == rating {
                    pressing = nil
                }
            }
    }
}

#Preview("Answering one") {
    Color.clear.sheet(
        item: .constant(PlaceholderQuestion(placeholder: .mood, answered: { _ in }))
    ) { question in
        PlaceholderAnswerSheet(question: question)
    }
}
