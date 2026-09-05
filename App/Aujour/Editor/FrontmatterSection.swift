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
                PropertiesCard(cut: $cut, pending: $pending, day: day)
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

    var body: some View {
        VStack(alignment: .trailing, spacing: Spacing.tight) {
            VStack(spacing: 0) {
                if cut.isShowingSource {
                    SourceField(cut: $cut)
                } else {
                    ForEach(Array(cut.properties.enumerated()), id: \.element.key) { index, property in
                        if index > 0 { Hairline().padding(.leading, Spacing.comfortable) }
                        PropertyRow(property: property, cut: $cut)
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

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.comfortable) {
            KeyField(key: property.key) { newKey in cut.rename(property.key, to: newKey) }
            ValueControl(property: property, cut: $cut)
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
            .frame(width: 110, alignment: .leading)
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

    var body: some View {
        switch property.value {
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
            DatePicker(
                "",
                selection: Binding(
                    get: { property.value.moment(in: .current) ?? Date() },
                    set: { cut.set(property.key, to: .date(of: $0, in: .current)) }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("propertyDate-\(property.key)")

        case .dateTime:
            DatePicker(
                "",
                selection: Binding(
                    get: { property.value.moment(in: .current) ?? Date() },
                    set: { cut.set(property.key, to: .dateTime(of: $0, in: .current)) }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("propertyDate-\(property.key)")

        case .list(let items):
            ListField(key: property.key, items: items) { cut.set(property.key, to: .list($0)) }
        }
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
        WrappingRow(spacing: Spacing.tight) {
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

    private let face = Font.system(.footnote, design: .monospaced)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(cut.source + "\n")
                .font(face)
                .padding(.horizontal, Spacing.comfortable)
                .padding(.vertical, Spacing.close)
                .opacity(0)
                .accessibilityHidden(true)
            TextEditor(text: Binding(get: { cut.source }, set: { cut.typedSource($0) }))
                .font(face)
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
