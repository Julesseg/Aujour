import SwiftUI
import AujourCore

/// Where inside the journal folder each day's Entry goes — the Path Template,
/// as something the user can change.
///
/// A page of its own, one step in from the settings sheet, beside the folder
/// and the photo path: the three answer one question together, *where are my
/// files?* The folder is the half Aujour picks up from the Files app; this is
/// the half it writes.
///
/// Changing it is the one setting in the app that moves somebody's existing
/// journal, so it is deliberately two steps. Typing a template only says what
/// the paths would look like; what happens to the files already in the folder
/// is asked separately, and is skippable (ADR 0002).
struct EntryPathView: View {
    let journal: Journal

    /// The one colour the app spends on itself, carried through to the sheet
    /// the change opens: nothing about a migration is drawn in a warning, and
    /// the colour it *is* drawn in is the reader's own.
    let accent: Accent

    /// The template as it is being typed, which is not the one in force until
    /// it is changed.
    @State private var typed: String

    /// What went wrong the last time "Change" was tapped — a folder that
    /// would not answer, or words that would not save. A rejected template is
    /// not this: that is shown while it is being typed.
    @State private var problem: StorageProblem?

    /// The change waiting on the user, which is what puts the offer on screen.
    @State private var proposed: ProposedChange?

    /// Whether the folder is being read to work out what a change would do.
    @State private var planning = false

    init(journal: Journal, accent: Accent) {
        self.journal = journal
        self.accent = accent
        _typed = State(initialValue: journal.pathTemplate)
    }

    /// A Path Template the user has typed, and the plan for adopting it —
    /// made before anything is moved, because it is what the offer is made of.
    private struct ProposedChange: Identifiable {
        let template: PathTemplate
        let plan: MigrationPlan

        var id: String { template.format }
    }

    /// The typed template, read — or the sentence saying why it cannot be.
    private var typedTemplate: Result<PathTemplate, PathTemplateError> {
        do {
            return .success(try PathTemplate(typed))
        } catch {
            // `PathTemplate` throws its rejection and nothing else, so this
            // is the sentence to show and not a guess at one.
            return .failure(error)
        }
    }

    private var rejection: PathTemplateError? {
        if case .failure(let rejection) = typedTemplate { rejection } else { nil }
    }

    private var isAChange: Bool {
        typed != journal.pathTemplate
    }

    /// Why a typed template cannot be read, drawn in the ink a sentence takes
    /// rather than in a warning colour.
    ///
    /// **No error colour anywhere in this flow**, and this line is where the
    /// flow starts: a template halfway to being typed is refused a dozen times
    /// on the way to one that is not, and colouring that like a fault would be
    /// the app telling somebody off for typing. It stands out by being full
    /// ink where this line is otherwise the muted example underneath the field
    /// — a step up rather than a change of meaning.
    ///
    /// A role and a token rather than `.caption` and `.red`, which is the rule
    /// the whole palette rests on: a screen names what a thing *is* and never
    /// what colour it comes out (`Palette`).
    static let rejectionInk = Palette.ink

    var body: some View {
        Form {
            // Not a `FormatField`, for the one thing this field has that the
            // others do not: a change here can fail against the folder, so the
            // footer has three things to say rather than two.
            Section {
                TextField("Entry path", text: $typed)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .accessibilityIdentifier("entryPathField")
            } footer: {
                saying
            }
            .settingsRows()

            Section {
                Button("Change") { propose() }
                    .disabled(!isAChange || rejection != nil || planning || !journal.isOpen)
                    .accessibilityIdentifier("changeEntryPath")
            }
            .settingsRows()
        }
        .settingsPage(titled: "Entry path")
        .sheet(item: $proposed) { change in
            PathTemplateMigrationSheet(
                journal: journal,
                accent: accent,
                template: change.template,
                plan: change.plan
            )
        }
        // Typing over a template that was refused clears the refusal about
        // the folder: it was about a change that is no longer the one being
        // asked for.
        .onChange(of: typed) { _, _ in problem = nil }
        // A template that changed underneath — this device having adopted
        // one, or the iPad having sent one — is what the field is supposed to
        // be showing.
        .onChange(of: journal.pathTemplate) { _, inForce in typed = inForce }
    }

    /// The one line under the field: what a day's file would be called, why
    /// the template cannot say — the same sentence `PathTemplateError` carries,
    /// which is written to be shown as it is — or what the folder said when
    /// the change was last attempted.
    @ViewBuilder
    private var saying: some View {
        if let rejection {
            Text(rejection.description)
                .foregroundStyle(Color(Self.rejectionInk))
                .accessibilityIdentifier("entryPathProblem")
        } else if let problem {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(problem.message)
                    .accessibilityIdentifier("entryPathChangeProblem")
                Text(problem.suggestion)
            }
        } else if case .success(let template) = typedTemplate {
            // The rule made concrete, on the day the user is actually in:
            // a template is easier to check against one real file name than
            // to read.
            Text("Today: \(template.render(journal.dayOnScreen))")
                .monospaced()
                .accessibilityIdentifier("entryPathExample")
        }
    }

    /// Reads the folder and works out what the change would do — which is
    /// what is put in front of the user, before a single file moves.
    ///
    /// A change that turns out to move nothing is not offered: there is
    /// nothing to accept or skip, so it is simply made.
    private func propose() {
        guard case .success(let template) = typedTemplate else { return }
        planning = true
        Task {
            defer { planning = false }
            do {
                let plan = try await journal.planChangingThePathTemplate(to: template)
                guard !plan.isEmpty else {
                    await journal.changeThePathTemplate(to: template, movingEntriesBy: nil)
                    return
                }
                proposed = ProposedChange(template: template, plan: plan)
            } catch {
                problem = StorageProblem(error)
            }
        }
    }
}

#Preview {
    NavigationStack {
        EntryPathView(journal: Journal.inAPreview(over: .system), accent: .driftwood)
    }
}
