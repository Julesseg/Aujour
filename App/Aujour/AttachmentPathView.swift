import SwiftUI
import AujourCore

/// Where a day's photographs go inside the journal folder — the Attachment
/// Path Template, as something the user can change.
///
/// The same field as the entry path, and deliberately not the same ceremony:
/// changing where photographs go moves nothing. The pictures already in the
/// folder are pointed at by the days that embed them, and a picture that
/// moved would leave the day naming a file that is not there — so this
/// decides where the next one lands and nothing else.
struct AttachmentPathView: View {
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
        Form {
            FormatField(
                title: "Photo path",
                prompt: "Photo folder",
                text: $typed,
                saying: saying,
                identifier: "attachmentPath"
            )
        }
        .settingsPage(titled: "Photo path")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                // In the bar, as the entry path's is: one field, one tick.
                Button {
                    guard case .success(let template) = typedTemplate else { return }
                    Task { await journal.changeTheAttachmentPathTemplate(to: template) }
                } label: {
                    Label("Change", systemImage: "checkmark")
                }
                .disabled(!isAChange || rejection != nil)
                .accessibilityIdentifier("changeAttachmentPath")
            }
        }
        .onChange(of: journal.attachmentPathTemplate) { _, inForce in typed = inForce }
    }

    /// The one line under the field: the folder today's photograph would go
    /// into — the template made concrete on the day the user is in, the way
    /// the entry path and the embed are — or why the template cannot say.
    private var saying: FormatField.Saying {
        switch typedTemplate {
        case .success(let template): .example("Today: \(template.render(journal.dayOnScreen))")
        case .failure(let rejection): .problem(rejection.description)
        }
    }
}

#Preview {
    NavigationStack {
        AttachmentPathView(journal: Journal.inAPreview(over: .system))
    }
}
