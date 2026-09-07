import AujourCore
import SwiftUI

/// The Frontmatter above the day: its Properties, each with the input its
/// kind deserves, or its source — and, over a day with none, the small
/// control that adds a first one (`CONTEXT.md`, *Frontmatter*, *Property*).
///
/// Hosted inside the text view, above the first line (``MarkdownTextView``),
/// and drawn in the grouped inset look the settings screens have: one rounded
/// card, a row per Property, system controls in the rows.
///
/// The view holds no rules. What the block says, what a control's write does
/// to it, when a block typed by hand is lifted and what leaving the source
/// finds are all ``AujourCore/CutEntry``'s, and every change here is one
/// call on it through the binding — which is what carries the new text to
/// the Entry Editor, so a toggle is saved exactly as a keystroke is.
///
/// One piece of state is the screen's own: the row for a Property that has
/// been asked for and not yet named. Nothing is written until it has a name
/// (`CONTEXT.md`), so until then it is a row here and nowhere in the file —
/// and an abandoned one goes without a trace.
struct FrontmatterSection: View {
    @Binding var cut: CutEntry

    /// The kind of the Property being added, while its name is being typed,
    /// and `nil` the rest of the time.
    @Binding var pending: Property.Kind?

    /// The Journal Day the Entry is for: what a date Property starts as.
    let day: JournalDay

    /// Asks a Placeholder's question, because a finger landed on its chip
    /// in a row — put up by the screen the day is on, as the editor's own
    /// widgets are.
    let asks: (PlaceholderQuestion) -> Void

    /// The one colour a control here is drawn in: the device's own accent,
    /// handed in because a view hosted inside a text view inherits nothing
    /// from the screen around it.
    let accent: Color

    /// What decides this view's height, folded into one number: the block,
    /// which view of it is up, and whether a row is being named. The body
    /// under the block is not in it, so a keystroke there is not a reason
    /// to measure the section again (``MarkdownTextView``).
    var layoutFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(cut.frontmatter)
        hasher.combine(cut.isShowingSource)
        hasher.combine(cut.source)
        hasher.combine(pending)
        return hasher.finalize()
    }

    var body: some View {
        Group {
            if cut.frontmatter != nil || pending != nil {
                PropertiesCard(cut: $cut, pending: $pending, day: day, asks: asks)
            } else {
                AddTheFirstProperty(pending: $pending)
            }
        }
        .tint(accent)
    }
}

// MARK: - The section

/// The card over a day that has a block: its Properties or its source, and
/// under it the two small controls — one that adds a Property, one that
/// switches between the two views.
private struct PropertiesCard: View {
    @Binding var cut: CutEntry
    @Binding var pending: Property.Kind?
    let day: JournalDay
    let asks: (PlaceholderQuestion) -> Void

    /// Which Property's calendar is up, by its name, and `nil` while none is.
    ///
    /// The card's and not the pill's, for the two things a pill cannot say on
    /// its own: that opening one calendar closes another, and that the card
    /// underneath an open one is not to be pressed (``body``).
    @State private var dayBeingPicked: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: Spacing.tight) {
            VStack(spacing: 0) {
                if cut.isShowingSource {
                    SourceField(cut: $cut)
                } else {
                    ForEach(Array(cut.properties.enumerated()), id: \.element.key) { index, property in
                        if index > 0 { Hairline().padding(.leading, Spacing.comfortable) }
                        PropertyRow(
                            property: property,
                            cut: $cut,
                            asks: asks,
                            dayBeingPicked: $dayBeingPicked
                        )
                    }
                    if let kind = pending {
                        if !cut.properties.isEmpty {
                            Hairline().padding(.leading, Spacing.comfortable)
                        }
                        NewPropertyRow(kind: kind, cut: $cut, pending: $pending, day: day)
                    }
                }
            }
            .background(Palette.cardColor, in: RoundedRectangle(cornerRadius: Rounding.card))
            .overlay(
                RoundedRectangle(cornerRadius: Rounding.card)
                    .strokeBorder(Palette.ruleColor, lineWidth: 1)
            )

            HStack(spacing: Spacing.tight) {
                if !cut.isShowingSource, cut.offersSource || cut.frontmatter == nil {
                    AddPropertyChip(pending: $pending)
                }
                // Only for a block that is understood: one that is not has no
                // Properties to come back to, and opens on its source with no
                // other way offered.
                if cut.offersSource {
                    Button {
                        if cut.isShowingSource { cut.showProperties() } else { cut.showSource() }
                    } label: {
                        Image(systemName: cut.isShowingSource ? "list.bullet" : "square.and.pencil")
                            .lettering(.marker)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .accessibilityLabel(cut.isShowingSource ? "Properties" : "Source")
                    .accessibilityIdentifier("frontmatterSourceToggle")
                    .accessibilityValue(cut.isShowingSource ? "Source" : "Properties")
                }
            }
        }
        .padding(.horizontal, Spacing.comfortable)
        .padding(.top, Spacing.comfortable)
        // Nothing here is to be pressed while a calendar is up over it. A
        // popover dismisses on a touch outside itself and the touch is meant
        // to be spent doing that, but this card is inside the view the
        // calendar is anchored to and the touch was reaching both — putting
        // the month away and pressing whatever was under it in the same
        // movement. The hour picker in particular never recovered: it had
        // been touched while it could not answer, and it did not open again.
        .allowsHitTesting(dayBeingPicked == nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("frontmatterSection")
    }
}

// MARK: - One Property

/// One row: the key, tapped to rename it, and the value in the input its
/// kind deserves. Swiped to delete it.
private struct PropertyRow: View {
    let property: Property
    @Binding var cut: CutEntry
    let asks: (PlaceholderQuestion) -> Void

    /// Which Property's calendar is up, which is the card's to hold
    /// (``PropertiesCard/dayBeingPicked``).
    @Binding var dayBeingPicked: String?

    var body: some View {
        PropertyRowLayout(valueIsIndivisible: property.value.isIndivisible) {
            KeyField(key: property.key) { newKey in cut.rename(property.key, to: newKey) }
            ValueControl(
                property: property,
                cut: $cut,
                asks: asks,
                dayBeingPicked: $dayBeingPicked
            )
        }
        .padding(.horizontal, Spacing.comfortable)
        .padding(.vertical, Spacing.close)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .swipeToDelete(identifier: "deleteProperty-\(property.key)") { cut.delete(property.key) }
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) { cut.delete(property.key) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("property-\(property.key)")
        .accessibilityAction(named: "Delete") { cut.delete(property.key) }
    }
}

/// The name and the value of one Property, laid out so that the value is
/// never the one that gives.
///
/// A row that hands the name a column of its own and the value whatever is
/// left is a row that crops the value the first time the two do not both fit
/// — and a cropped date is not a shorter date, it is a date with its year cut
/// off. Which happens on nobody's exotic device: a compact date-and-time
/// picker asks for more room every step the reader turns their text up, and
/// the Entry it sits over is set to a measure rather than to the window, so
/// the room it is asking out of does not grow with the screen.
///
/// So the name is what yields. It is ``key`` wide wherever the row can afford
/// it, because a column of names that line up is what makes a stack of rows
/// read as a table; down to ``narrowestKey`` where it cannot, which is still
/// a word and still a target for the finger that renames it; and under that
/// the row is two lines, the name on one and the value under it against the
/// same trailing edge it sits at when they share a line. A value wider than
/// the whole row even then is the value's own business — a date picker at the
/// accessibility sizes breaks its date over the two lines itself.
///
/// All of which is only for the values it is true of, which is why the row is
/// told which it has: a date squeezed loses its year, a sentence squeezed is
/// still the sentence and scrolls in its field. A row whose value is words
/// divides exactly as it always did — the name's column, and the rest.
struct PropertyRowLayout: Layout {
    /// Whether the value is read whole or not at all, and so is measured
    /// before the name is handed its column.
    var valueIsIndivisible = false

    /// How wide the name column is when the row can afford it.
    static let key: CGFloat = 110

    /// And the narrowest it is squeezed to before the value goes underneath
    /// instead. A name is held as typed and committed on leaving, so a field
    /// this wide with more in it than fits is a field that scrolls under the
    /// caret rather than a name that has lost its end.
    static let narrowestKey: CGFloat = 56

    /// Between the name and the value beside it.
    var spacing: CGFloat = Spacing.comfortable

    /// And between the name and the value under it, which is closer than
    /// that: two lines that are one row.
    var stackedSpacing: CGFloat = Spacing.tight

    /// How a row this wide divides between a name and a value that wants this
    /// much of it.
    struct Division: Equatable {
        var key: CGFloat
        var value: CGFloat
        /// Whether the value is under the name rather than beside it.
        var isStacked: Bool
    }

    /// The whole rule, in the one place both the measuring and the placing
    /// read it from — two passes that divided a row differently would draw a
    /// value over a name.
    ///
    /// - Parameters:
    ///   - width: how wide the row is.
    ///   - wanted: how wide the value would be if nothing were pressing on
    ///     it, which is the number this is all in aid of.
    static func division(of width: CGFloat, forAValueWanting wanted: CGFloat, spacing: CGFloat)
        -> Division
    {
        let beside = width - spacing
        if beside - key >= wanted {
            return Division(key: key, value: beside - key, isStacked: false)
        }
        if beside - narrowestKey >= wanted {
            return Division(key: beside - wanted, value: wanted, isStacked: false)
        }
        return Division(key: width, value: width, isStacked: true)
    }

    /// How much of the row the value is asking for: what it would come out
    /// at with nothing pressing on it, or nothing at all when it is words —
    /// which is a value with no claim on the room, and a row divided the way
    /// it always was.
    private func widthWanted(by subviews: Subviews) -> CGFloat {
        valueIsIndivisible ? subviews[1].sizeThatFits(.unspecified).width : 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let wanted = widthWanted(by: subviews)
        // Asked with no width — which is how a row is asked what it would
        // like to be — the row would like the name beside the whole value.
        let width = proposal.width ?? Self.key + spacing + wanted
        let division = Self.division(of: width, forAValueWanting: wanted, spacing: spacing)
        let key = subviews[0].sizeThatFits(ProposedViewSize(width: division.key, height: nil))
        let value = subviews[1].sizeThatFits(ProposedViewSize(width: division.value, height: nil))
        return CGSize(
            width: width,
            height: division.isStacked
                ? key.height + stackedSpacing + value.height
                : max(key.height, value.height)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let wanted = widthWanted(by: subviews)
        let division = Self.division(of: bounds.width, forAValueWanting: wanted, spacing: spacing)
        let key = ProposedViewSize(width: division.key, height: nil)
        let value = ProposedViewSize(width: division.value, height: nil)

        guard division.isStacked else {
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: key
            )
            subviews[1].place(
                at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: value
            )
            return
        }
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading, proposal: key
        )
        subviews[1].place(
            at: CGPoint(
                x: bounds.minX,
                y: bounds.minY + subviews[0].sizeThatFits(key).height + stackedSpacing
            ),
            anchor: .topLeading,
            proposal: value
        )
    }
}

extension Property.Value {
    /// Whether a squeeze takes something off this value rather than out of
    /// the middle of it — which is what decides whether the row hands it its
    /// width before the name's (``PropertyRowLayout``).
    ///
    /// A date and a time are read whole: a picker with a hundred points to
    /// draw them in shows a day and a month and no year, which is not a
    /// shorter date but the wrong one. Words, numbers and chips are not — a
    /// field of them scrolls under the caret, and a list wraps onto as many
    /// lines as it costs.
    fileprivate var isIndivisible: Bool {
        switch kind {
        case .date, .dateTime: true
        case .text, .number, .checkbox, .list: false
        }
    }
}

/// A Property's name, in a field so that a tap on it is a rename.
///
/// Held as typed until it is submitted or left, because a key is what a row
/// is known by: renaming as each letter lands would move the row out from
/// under the keyboard. A name that is refused — a colon in it, or one the
/// block already has — is put back to what it was.
private struct KeyField: View {
    let key: String
    let rename: (String) -> Bool

    @State private var draft = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        TextField("Name", text: $draft)
            .lettering(.rowValue)
            .foregroundStyle(Palette.inkMutedColor)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            .focused($isEditing)
            .onAppear { draft = key }
            .onChange(of: key) { draft = key }
            .onSubmit { commit() }
            .onChange(of: isEditing) { if !isEditing { commit() } }
            .accessibilityIdentifier("propertyKey-\(key)")
    }

    private func commit() {
        guard draft != key else { return }
        if !rename(draft) { draft = key }
    }
}

/// The input a Property's kind deserves.
private struct ValueControl: View {
    let property: Property
    @Binding var cut: CutEntry
    let asks: (PlaceholderQuestion) -> Void

    /// Which Property's calendar is up (``PropertiesCard/dayBeingPicked``).
    @Binding var dayBeingPicked: String?

    var body: some View {
        switch property.value {
        case .text where property.value.placeholder != nil:
            PlaceholderChip(token: property.value.placeholder!, asks: asks) { answer in
                guard let token = cut.properties.first(where: { $0.key == property.key })?
                    .value.placeholder
                else { return }
                cut.set(property.key, to: .text(Property.answer(token, with: answer)))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("propertyPlaceholder-\(property.key)")

        case .text(let text):
            TextField(
                "",
                text: Binding(get: { text }, set: { cut.set(property.key, to: .text($0)) })
            )
            .lettering(.rowLabel)
            .multilineTextAlignment(.trailing)
            .autocorrectionDisabled()
            .accessibilityIdentifier("propertyText-\(property.key)")

        case .number(let number):
            NumberField(key: property.key, number: number) { cut.set(property.key, to: .number($0)) }

        case .checkbox(let on):
            Toggle(
                "",
                isOn: Binding(get: { on }, set: { cut.set(property.key, to: .checkbox($0)) })
            )
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("propertyToggle-\(property.key)")

        case .date:
            theDay(writing: { .date(of: $0, in: .current) })
                .frame(maxWidth: .infinity, alignment: .trailing)

        case .dateTime:
            // The day and the hour separately, and never the one control that
            // shows both: it sizes the day for a date it is not going to draw
            // — 04/09/2025 in a pill it measured for a shorter month-name one
            // — and cuts the year off wherever the reader's date is written in
            // numbers. Each of these says one thing and comes out the width of
            // what it says.
            //
            // Both write the whole moment, so the day is set by the one and
            // the hour by the other and neither loses the other's half.
            //
            // Side by side while the row can hold them both, and the hour
            // under the day where it cannot — which is what the control that
            // draws them together did at the accessibility sizes, and what two
            // pills of their own would otherwise run off the screen rather
            // than do.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.close) {
                    theDay(writing: { .dateTime(of: $0, in: .current) })
                    theHour
                }
                VStack(alignment: .trailing, spacing: Spacing.tight) {
                    theDay(writing: { .dateTime(of: $0, in: .current) })
                    theHour
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

        case .list(let items):
            ListField(key: property.key, items: items) { cut.set(property.key, to: .list($0)) }
        }
    }

    /// The day of a date Property, said in words and opened as a calendar.
    ///
    /// - Parameter writing: what a day picked out of it makes of the value —
    ///   a date for a date Property, a moment for a date-and-time one.
    private func theDay(writing value: @escaping (Date) -> Property.Value) -> some View {
        DayPill(
            moment: theMoment(writing: value),
            key: property.key,
            dayBeingPicked: $dayBeingPicked
        )
    }

    /// And the hour of a date-and-time one, in the system's own picker: an
    /// hour is digits and a colon in every language, so there is nothing here
    /// for a control to spell one way and measure another.
    private var theHour: some View {
        DatePicker(
            "",
            selection: theMoment(writing: { .dateTime(of: $0, in: .current) }),
            displayedComponents: .hourAndMinute
        )
        .labelsHidden()
        .foregroundStyle(.tint)
        .accessibilityIdentifier("propertyTime-\(property.key)")
    }

    /// The moment the value names, as the controls over it read and write it:
    /// either of them hands back the whole moment, its own half changed and
    /// the other half as it was given.
    private func theMoment(writing value: @escaping (Date) -> Property.Value) -> Binding<Date> {
        Binding(
            get: { property.value.moment(in: .current) ?? Date() },
            set: { cut.set(property.key, to: value($0)) }
        )
    }
}

/// A day, said in words and opened as a calendar.
///
/// The words are the app's own (``AujourCore/JournalDay/named(at:withYear:in:locale:)``)
/// rather than the ones a compact date picker draws, which are whatever it
/// decides will fit: a month spelled out where it has room and `04/09/2025`
/// where it has not, and the two swapping between them as a row changes width
/// or a reader changes language. A journal is read back years later and a date
/// in it should be the same shape every time — and the shape is the one nobody
/// has to decode, which is the month in letters.
///
/// The reader's own wording of it, and the reader's own order: whether the day
/// or the month comes first is the device's business and not this app's. Only
/// the calendar behind it is the system's control, because picking a day out
/// of a month is a thing iOS already does well.
extension Locale {
    /// The reader's own language, which is not the app's.
    ///
    /// Aujour is written in English and nothing else, so a French device runs
    /// it in English and `Locale.current` comes back English with a French
    /// region — English words in the French order. Which is fine for a label
    /// the app wrote, and wrong for a date: the system's own controls say the
    /// months in French on that device, and a date this app spells itself
    /// would be the one thing on the screen arguing with them.
    ///
    /// So the device's own first language, and its region with it, falling
    /// back to what the app was given where a device has said nothing.
    static var asTheDeviceIsSet: Locale {
        preferredLanguages.first.map(Locale.init(identifier:)) ?? .current
    }
}

private struct DayPill: View {
    @Binding var moment: Date

    /// The name of the Property this is the day of — which is how the card
    /// knows whose calendar is up.
    let key: String

    /// Which Property's calendar is up (``PropertiesCard/dayBeingPicked``).
    @Binding var dayBeingPicked: String?

    /// The same, as this pill's own answer to whether it is showing one.
    private var isPicking: Binding<Bool> {
        Binding(
            get: { dayBeingPicked == key },
            set: { dayBeingPicked = $0 ? key : nil }
        )
    }

    /// How wide a month of days comes to at the reader's text size — seven
    /// columns and the padding round them, which is what the system's own
    /// calendar takes at the usual size.
    @ScaledMetric(relativeTo: .body) private var monthWide: CGFloat = 320

    var body: some View {
        Button {
            dayBeingPicked = key
        } label: {
            Text(theDay.named(at: .dayAndMonth, withYear: true, locale: .asTheDeviceIsSet))
                .lettering(.rowLabel)
                .foregroundStyle(Palette.inkColor)
                .padding(.horizontal, Spacing.close)
                .padding(.vertical, Spacing.tight)
                .background(Palette.fieldStrongColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("propertyDate-\(key)")
        .accessibilityValue(theDay.named(at: .spelledOut, withYear: true, locale: .asTheDeviceIsSet))
        // A popover on the phone too, and not the sheet a popover becomes
        // there: this is the calendar the pill beside it puts up, and a month
        // to pick a day out of is not a screenful of anything.
        .popover(isPresented: isPicking) {
            DatePicker("", selection: $moment, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(Spacing.close)
                // Told how wide a month is, because a popover offers its
                // content the width of the thing it hangs off: hung off a
                // pill, the calendar came up one weekday wide with the rest
                // of the month cut off it. A floor and not a width, and one
                // that grows with the reader's text, so that a month asking
                // for more room than seven columns of digits is given it.
                .frame(minWidth: min(monthWide, 420))
                .presentationCompactAdaptation(.popover)
                .accessibilityIdentifier("propertyCalendar")
                // A day picked is the whole of what this was opened for, so
                // it closes on one — which is what the system's own pill does
                // and what stops the month sitting over the day it just
                // changed.
                .onChange(of: moment) { dayBeingPicked = nil }
        }
    }

    /// The day the moment falls on, in the reader's own zone — which is the
    /// zone the value was written in and is read back in.
    private var theDay: JournalDay {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: moment)
        return JournalDay(year: parts.year ?? 1, month: parts.month ?? 1, day: parts.day ?? 1)
    }
}

/// A Placeholder standing alone as a value, drawn as the chip the editor
/// draws over its token: tapped, it asks its question, and the answer is
/// the value (`CONTEXT.md`, *Property*).
///
/// The chip carries the way back into the Entry, and reads the token again
/// when the answer arrives rather than trusting the one it was drawn for —
/// a sheet is up while the Entry goes on living, and a value that stopped
/// being a question while it was up is left alone.
private struct PlaceholderChip: View {
    let token: InteractivePlaceholder.Token
    let asks: (PlaceholderQuestion) -> Void
    let answered: (String) -> Void

    var body: some View {
        Button {
            asks(PlaceholderQuestion(placeholder: token.placeholder) { answer in
                guard !answer.isEmpty else { return }
                answered(answer)
            })
        } label: {
            Label(token.placeholder.title, systemImage: token.placeholder.symbol)
                .lettering(.chipLabel)
                .padding(.horizontal, Spacing.close)
                .padding(.vertical, Spacing.tight)
                .foregroundStyle(.tint)
                .background(.tint.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A number, typed on the decimal pad.
///
/// Held as typed rather than bound straight to the block, because a number
/// half-typed is not a number: a field emptied on the way to `8` would
/// otherwise write nothing back, and then snap back to `7` under the thumb.
/// Only a whole number reaches the block; an empty field left is put back
/// to what the block says.
private struct NumberField: View {
    let key: String
    let number: Double
    let write: (Double) -> Void

    @State private var draft = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        TextField("", text: $draft)
            .lettering(.rowLabel)
            .multilineTextAlignment(.trailing)
            .keyboardType(.decimalPad)
            .focused($isEditing)
            .onAppear { draft = Property.Value.number(number).spelledOut }
            .onChange(of: number) { if !isEditing { draft = Property.Value.number(number).spelledOut } }
            .onChange(of: draft) {
                guard let typed = Property.number(typed: draft), typed != number else { return }
                write(typed)
            }
            .onChange(of: isEditing) {
                if !isEditing, Property.number(typed: draft) == nil {
                    draft = Property.Value.number(number).spelledOut
                }
            }
            .accessibilityIdentifier("propertyNumber-\(key)")
    }
}

/// A list as chips, each with the way to take it off, and a field that adds
/// one on return.
private struct ListField: View {
    let key: String
    let items: [String]
    let write: ([String]) -> Void

    @State private var adding = ""

    var body: some View {
        WrappingRow(spacing: Spacing.tight, alignment: .trailing) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: Spacing.tight) {
                    Text(item).lettering(.chipLabel)
                    Button {
                        var remaining = items
                        remaining.remove(at: index)
                        write(remaining)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item)")
                    .accessibilityIdentifier("removeListItem-\(key)-\(index)")
                }
                .padding(.horizontal, Spacing.close)
                .padding(.vertical, Spacing.tight)
                .foregroundStyle(.tint)
                .background(.tint.opacity(0.14), in: Capsule())
            }
            TextField("Add", text: $adding)
                .lettering(.chipLabel)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit {
                    let item = adding.trimmingCharacters(in: .whitespaces)
                    guard !item.isEmpty else { return }
                    write(items + [item])
                    adding = ""
                }
                .frame(minWidth: 48)
                .padding(.vertical, Spacing.tight)
                .accessibilityIdentifier("propertyListAdd-\(key)")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("propertyList-\(key)")
    }
}

// MARK: - Adding one

/// The small control under the card that adds a Property, asking its kind
/// first.
private struct AddPropertyChip: View {
    @Binding var pending: Property.Kind?

    var body: some View {
        KindMenu(pending: $pending) {
            Label("Add a property", systemImage: "plus")
                .lettering(.marker)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .accessibilityIdentifier("addProperty")
    }
}

/// The kinds, offered as a menu: the kind is what seeds the value's shape,
/// so it is asked before the name.
private struct KindMenu<Label: View>: View {
    @Binding var pending: Property.Kind?
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            ForEach(Property.Kind.allCases, id: \.self) { kind in
                Button(kind.name, systemImage: kind.symbol) { pending = kind }
            }
        } label: {
            label()
        }
    }
}

/// The row for a Property asked for and not yet named. Nothing is in the
/// file until it is, and a row left empty goes without a trace.
private struct NewPropertyRow: View {
    let kind: Property.Kind
    @Binding var cut: CutEntry
    @Binding var pending: Property.Kind?
    let day: JournalDay

    @State private var name = ""
    @State private var refused = false
    @FocusState private var isNaming: Bool

    var body: some View {
        HStack(spacing: Spacing.comfortable) {
            TextField("Name", text: $name)
                .lettering(.rowValue)
                .foregroundStyle(refused ? Palette.alarmColor : Palette.inkMutedColor)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .focused($isNaming)
                .onSubmit { commit() }
                .onChange(of: isNaming) { if !isNaming { commit() } }
                .onChange(of: name) { refused = false }
                .accessibilityIdentifier("newPropertyKey")
            Label(kind.name, systemImage: kind.symbol)
                .lettering(.rowValue)
                .foregroundStyle(Palette.inkFaintColor)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.comfortable)
        .padding(.vertical, Spacing.close)
        .frame(minHeight: 44)
        .onAppear { isNaming = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("newProperty")
    }

    private func commit() {
        let key = name.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            pending = nil
            return
        }
        if cut.add(key, as: kind.seed(on: day, at: Property.clock(at: Date(), in: .current))) {
            pending = nil
        } else {
            refused = true
        }
    }
}

/// The small control over a day with no block, tucked above the top of the
/// text: reached by scrolling up past it, and in the accessibility tree the
/// whole time (``MarkdownTextView``).
private struct AddTheFirstProperty: View {
    @Binding var pending: Property.Kind?

    var body: some View {
        KindMenu(pending: $pending) {
            Label("Add a property", systemImage: "plus")
                .lettering(.marker)
                .foregroundStyle(Palette.inkFaintColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.close)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("addFirstProperty")
    }
}

// MARK: - The source

/// The block's own characters, fence to fence, in a monospace field.
///
/// Sized by a copy of the same text set in the same face underneath it,
/// because a text editor in SwiftUI has no height of its own: it scrolls,
/// and here the page is what scrolls.
///
/// Leaving the field is leaving the source: the block is read again by the
/// rule when the keyboard goes, and honoured for what it says. For a block
/// that is not understood this is the only way out, since no toggle is
/// offered — the user mends the text, and the day reads it.
private struct SourceField: View {
    @Binding var cut: CutEntry

    @FocusState private var isEditing: Bool

    /// How tall the text came out, which is how tall the field is made: a
    /// text editor offered any height takes all of it.
    @State private var height: CGFloat = 0

    private let face = Font.system(.footnote, design: .monospaced)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(cut.source + "\n")
                .font(face)
                .padding(.horizontal, Spacing.comfortable)
                .padding(.vertical, Spacing.close)
                .opacity(0)
                .accessibilityHidden(true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            TextEditor(text: Binding(get: { cut.source }, set: { cut.typedSource($0) }))
                .font(face)
                .frame(height: max(height, 44))
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isEditing)
                .onChange(of: isEditing) { if !isEditing { cut.showProperties() } }
                .padding(.horizontal, Spacing.close)
                .padding(.vertical, 0)
                .accessibilityIdentifier("frontmatterSource")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Swiping a row away

extension View {
    /// Lets a row be swiped leftwards to reveal the control that deletes it.
    ///
    /// By hand rather than `swipeActions`, which only a `List` offers, and a
    /// list is a scroll view — one that could not sit inside the page that
    /// already scrolls.
    fileprivate func swipeToDelete(identifier: String, delete: @escaping () -> Void) -> some View {
        modifier(SwipeToDelete(identifier: identifier, delete: delete))
    }
}

private struct SwipeToDelete: ViewModifier {
    let identifier: String
    let delete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isOpen = false

    private static let reveal: CGFloat = 80

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: .trailing) {
                if isOpen {
                    Button(role: .destructive, action: delete) {
                        Text("Delete")
                            .lettering(.rowValue)
                            .foregroundStyle(Palette.onAccentColor)
                            .frame(width: Self.reveal)
                            .frame(maxHeight: .infinity)
                            .background(Palette.alarmColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(identifier)
                }
            }
            .clipped()
            .highPriorityGesture(
                DragGesture(minimumDistance: 16)
                    .onChanged { drag in
                        // Sideways, and not a scroll that wandered.
                        guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                        offset = min(0, (isOpen ? -Self.reveal : 0) + drag.translation.width)
                        if offset < 0 { isOpen = true }
                    }
                    .onEnded { _ in
                        withAnimation(.snappy) {
                            if offset < -Self.reveal / 2 {
                                offset = -Self.reveal
                                isOpen = true
                            } else {
                                offset = 0
                                isOpen = false
                            }
                        }
                    }
            )
    }
}

// MARK: - What a kind is called

extension Property.Kind {
    /// What the menu offers this kind as.
    var name: String {
        switch self {
        case .text: "Text"
        case .number: "Number"
        case .checkbox: "Checkbox"
        case .date: "Date"
        case .dateTime: "Date and time"
        case .list: "List"
        }
    }

    var symbol: String {
        switch self {
        case .text: "textformat"
        case .number: "number"
        case .checkbox: "checkmark.square"
        case .date: "calendar"
        case .dateTime: "clock"
        case .list: "list.bullet"
        }
    }
}
