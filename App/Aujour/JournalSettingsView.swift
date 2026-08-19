import SwiftUI
import AujourCore

/// The settings that shape the Journal, as something the user can change:
/// what a new day starts as, when the day turns, and where a photograph goes.
///
/// A screen of its own rather than more of the folder sheet, because these
/// three are not about the folder. The folder sheet answers *where are my
/// files, and what are they called* — the Journal Root, the Path Template and
/// the one line Aujour writes into a day. This answers *what is in a day when
/// it starts, and which day is it* — and the Content Template, the biggest of
/// them, is a page of text rather than a field.
///
/// Every one of these travels: changed here they arrive on the iPad, changed
/// there they arrive here while this sheet is up (ADR 0003). So nothing here
/// holds its own copy of a setting for longer than it is being typed, and the
/// controls that are not text follow the journal directly.
struct JournalSettingsSheet: View {
    let journal: Journal

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ContentTemplateSection(journal: journal)
                    Divider()
                    RolloverHourSection(journal: journal)
                    Divider()
                    AttachmentPathSection(journal: journal)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            // The Content Template is typed into on a phone whose keyboard
            // then covers the button that uses it: a swipe puts it away.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Journal settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // The Content Template is a page of text; anything less than the whole
        // sheet is a template read through a letterbox.
        .presentationDetents([.large])
    }
}

/// What a day nobody has written yet starts as.
///
/// A page rather than a field, because that is what it is: an Obsidian daily
/// note template pasted in whole, headings and all. Applied on a button and
/// not as it is typed — a template half-written is a template that would
/// spawn today's Entry half-written, and the journal reopens around every
/// change to one.
private struct ContentTemplateSection: View {
    let journal: Journal

    /// The template as it is being typed, which is not the one in force until
    /// it is used.
    @State private var typed: String

    @FocusState private var writing: Bool

    init(journal: Journal) {
        self.journal = journal
        _typed = State(initialValue: journal.contentTemplate)
    }

    private var isAChange: Bool { typed != journal.contentTemplate }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What a new day starts as")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: $typed)
                .font(.callout.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($writing)
                .frame(minHeight: 140)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator)
                )
                .accessibilityIdentifier("contentTemplateField")

            Text(
                """
                Days you haven't written yet start from this. \
                {{date}}, {{time}} and {{title}} are filled in when the day \
                is spawned; anything Aujour doesn't know stays as you typed \
                it, so Obsidian sees nothing broken. Leave it empty for a \
                blank page.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Use this template") {
                writing = false
                Task { await journal.changeTheContentTemplate(to: typed) }
            }
            .buttonStyle(.bordered)
            .disabled(!isAChange)
            .accessibilityIdentifier("changeContentTemplate")
        }
        // A template that changed underneath — the iPad having sent one, or
        // this device having just used one — is what the page is supposed to
        // be showing. Not while it is being written into: what somebody is
        // part-way through typing is not something to replace under them.
        .onChange(of: journal.contentTemplate) { _, inForce in
            if !writing { typed = inForce }
        }
    }
}

/// When the current Journal Day advances.
///
/// The setting shown as the day it makes it right now, and not only as an
/// hour: "the day turns at 4 AM" is a rule somebody has to apply to their own
/// clock, and "right now this is Tuesday" is the answer they were applying it
/// for.
private struct RolloverHourSection: View {
    let journal: Journal

    /// The setting, and changing it — a binding rather than local state,
    /// because a Rollover Hour set on the iPad arrives here while the sheet
    /// is up (ADR 0003).
    private var hour: Binding<Int> {
        Binding(
            get: { journal.rolloverHour.hour },
            set: { chosen in
                guard let hour = RolloverHour(hour: chosen) else { return }
                Task { await journal.changeTheRolloverHour(to: hour) }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("When the day turns")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("When the day turns", selection: hour) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(Self.onTheClock(hour)).tag(hour)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("rolloverHour")

            Text("Right now, you're writing \(journal.dayOnScreen.spelledOut()).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("rolloverHourDay")

            Text(
                """
                Entries already written stay on the days they're named for. \
                Push this later than midnight and a late night lands on the \
                day you're describing rather than the one the clock has \
                moved on to.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// An hour of the day as this user's clock writes it — 12- or 24-hour,
    /// whichever their region is on.
    private static func onTheClock(_ hour: Int) -> String {
        let midnight = Calendar.current.startOfDay(for: Date())
        let atThatHour = Calendar.current.date(byAdding: .hour, value: hour, to: midnight) ?? midnight
        return atThatHour.formatted(date: .omitted, time: .shortened)
    }
}

/// Where a day's photographs go inside the journal folder — the Attachment
/// Path Template, as something the user can change.
///
/// The same field as the entry path, and deliberately not the same ceremony:
/// changing where photographs go moves nothing. The pictures already in the
/// folder are pointed at by the days that embed them, and a picture that
/// moved would leave the day naming a file that is not there — so this
/// decides where the next one lands and nothing else.
private struct AttachmentPathSection: View {
    let journal: Journal

    @State private var typed: String

    init(journal: Journal) {
        self.journal = journal
        _typed = State(initialValue: journal.attachmentPathTemplate)
    }

    /// The typed template, read — or the sentence saying why it cannot be.
    /// `AttachmentPathTemplate` throws its rejection and nothing else, so this
    /// is the sentence to show rather than a guess at one.
    private var typedTemplate: Result<AttachmentPathTemplate, PathTemplateError> {
        do {
            return .success(try AttachmentPathTemplate(typed))
        } catch {
            return .failure(error)
        }
    }

    private var rejection: PathTemplateError? {
        if case .failure(let rejection) = typedTemplate { rejection } else { nil }
    }

    private var isAChange: Bool { typed != journal.attachmentPathTemplate }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where photos go")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Photo folder", text: $typed)
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .accessibilityIdentifier("attachmentPathField")

            saying

            Text(
                """
                Inside your journal folder. Date tokens like YYYY and MM are \
                filled in; anything in [brackets] is a folder name. Photos \
                already in the journal stay where they are.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Change") {
                guard case .success(let template) = typedTemplate else { return }
                Task { await journal.changeTheAttachmentPathTemplate(to: template) }
            }
            .buttonStyle(.bordered)
            .disabled(!isAChange || rejection != nil)
            .accessibilityIdentifier("changeAttachmentPath")
        }
        .onChange(of: journal.attachmentPathTemplate) { _, inForce in typed = inForce }
    }

    /// The one line under the field: the folder today's photograph would go
    /// into, or why the template cannot say.
    @ViewBuilder
    private var saying: some View {
        if let rejection {
            Text(rejection.description)
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("attachmentPathProblem")
        } else if case .success(let template) = typedTemplate {
            // The template made concrete on the day the user is in, the way
            // the entry path and the embed are: a folder described in tokens
            // is a folder somebody has to imagine.
            Text(template.render(journal.dayOnScreen))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("attachmentPathExample")
        }
    }
}

#Preview {
    JournalSettingsSheet(journal: Journal(settings: .inMemory()))
}
