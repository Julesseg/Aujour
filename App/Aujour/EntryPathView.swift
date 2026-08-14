import SwiftUI
import AujourCore

/// Where inside the journal folder each day's Entry goes — the Path Template,
/// as something the user can change.
///
/// It sits beside the folder rather than on a settings screen of its own,
/// because the two answer one question together: *where are my files?* The
/// folder is the half Aujour picks up from the Files app; this is the half it
/// writes.
///
/// Changing it is the one setting in the app that moves somebody's existing
/// journal, so it is deliberately two steps. Typing a template only says what
/// the paths would look like; what happens to the files already in the folder
/// is asked separately, and is skippable (ADR 0002).
struct EntryPathSection: View {
    let journal: Journal

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

    init(journal: Journal) {
        self.journal = journal
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where each day's entry goes")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Entry path", text: $typed)
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .accessibilityIdentifier("entryPathField")

            saying

            Button("Change") { propose() }
                .buttonStyle(.bordered)
                .disabled(!isAChange || rejection != nil || planning || !journal.isOpen)
                .accessibilityIdentifier("changeEntryPath")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $proposed) { change in
            PathTemplateMigrationSheet(journal: journal, template: change.template, plan: change.plan)
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

    /// The one line under the field: what a day's file would be called, or
    /// why the template cannot say — the same sentence `PathTemplateError`
    /// carries, which is written to be shown as it is.
    @ViewBuilder
    private var saying: some View {
        if let rejection {
            Text(rejection.description)
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("entryPathProblem")
        } else if let problem {
            VStack(alignment: .leading, spacing: 2) {
                Text(problem.message)
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("entryPathChangeProblem")
                Text(problem.suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if case .success(let template) = typedTemplate {
            // The rule made concrete, on the day the user is actually in:
            // a template is easier to check against one real file name than
            // to read.
            Text("Today: \(template.render(journal.dayOnScreen))")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
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

/// The offer a Path Template change comes with: move the entries already in
/// the folder into the new shape, or leave them where they are (ADR 0002).
///
/// Everything it says is about files, because that is what the user is
/// deciding about — how many move, which days already have something at the
/// path they would move to, and what happens to what is not moved. Nothing
/// here is reversible by Aujour afterwards, so all of it is said before
/// rather than reported after.
struct PathTemplateMigrationSheet: View {
    let journal: Journal
    let template: PathTemplate
    let plan: MigrationPlan

    @State private var stage: Stage = .offering
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        /// Waiting on the user, which is the whole point of the screen.
        case offering
        /// The files are moving.
        case moving
        /// What became of them.
        case moved(MigrationOutcome)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch stage {
                    case .offering: theOffer
                    case .moving: ProgressView("Moving your entries").frame(maxWidth: .infinity)
                    case .moved(let outcome): summary(of: outcome)
                    }
                }
                .padding()
            }
            .navigationTitle("Where your entries go")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .interactiveDismissDisabled(isBusy)
        }
    }

    private var isBusy: Bool {
        if case .moving = stage { true } else { false }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch stage {
        case .offering:
            // Backing out leaves the template alone as well as the files:
            // nothing about this change has happened yet.
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("cancelEntryPathChange")
            }
        case .moving:
            // Nothing to press while the files are moving. Stopping halfway
            // is not an outcome worth offering — every move already made is
            // one the plan says is safe, and the way out of a migration that
            // did not finish is to change the entry path again.
            ToolbarItem(placement: .cancellationAction) { EmptyView() }
        case .moved:
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("dismissMigrationSummary")
            }
        }
    }

    // MARK: - The offer

    @ViewBuilder
    private var theOffer: some View {
        Text("Move your \(counted(plan.entryCount, "entry", "entries"))?")
            .font(.title3.weight(.semibold))
            .accessibilityIdentifier("migrationPrompt")

        Text(
            """
            Your entries are only entries where your entry path says they are, so anything \
            Aujour doesn't move stops showing up in the app. The files stay in your folder \
            either way — nothing is deleted.
            """
        )
        .font(.callout)
        .foregroundStyle(.secondary)

        // The one consequence nobody would guess, and the reason ADR 0002
        // says the prompt has to mention it: a daily note that changes name
        // is a note the vault's links no longer reach.
        Label(
            "Renaming files can break [[links]] to your daily notes in Obsidian.",
            systemImage: "link"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("migrationLinkWarning")

        collisions

        VStack(spacing: 12) {
            Button("Move Entries") { move() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("moveEntries")

            Button("Change Without Moving") { changeWithoutMoving() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("skipMigration")
        }
        .frame(maxWidth: .infinity)
    }

    /// The days whose new path something is already at — named one by one,
    /// because each of them is a file of the user's that Aujour is about to
    /// put a second file beside, and being asked about it is the whole of
    /// ADR 0002's collision rule.
    ///
    /// Said here rather than one question at a time as the files move: a
    /// vault that already keeps daily notes where the new template puts them
    /// collides on every single day, and a hundred prompts is not a decision
    /// anybody makes — it is one they dismiss.
    @ViewBuilder
    private var collisions: some View {
        let colliding = plan.collisions
        if !colliding.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    colliding.count == 1
                        ? "1 day already has a file where it would go"
                        : "\(colliding.count) days already have a file where they would go"
                )
                .font(.footnote.weight(.semibold))
                .accessibilityIdentifier("migrationCollisions")


                Text(
                    """
                    Aujour never overwrites. The file that's already there stays as that day's \
                    entry, and yours is kept beside it — open both and merge them by hand.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(colliding, id: \.to) { collision in
                    Text("\(collision.day.description) → \(collision.name)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - What happened

    @ViewBuilder
    private func summary(of outcome: MigrationOutcome) -> some View {
        Text(headline(of: outcome))
            .font(.title3.weight(.semibold))
            .accessibilityIdentifier("migrationSummary")

        if !outcome.parked.isEmpty {
            Text(
                """
                \(counted(outcome.parked.count, "day", "days")) already had a file where \
                \(outcome.parked.count == 1 ? "it" : "they") would go, so both were kept: \
                \(outcome.parked.map(\.name).formatted(.list(type: .and))). Open them in Files or \
                Obsidian to bring across anything you want.
                """
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("migrationParkedFiles")
        }

        if !outcome.leftBehind.isEmpty {
            Text(
                outcome.leftBehind.count == 1
                    ? """
                    1 entry couldn't be moved and is still where it was. Nothing was lost — \
                    change your entry path again to try it once more.
                    """
                    : """
                    \(outcome.leftBehind.count) entries couldn't be moved and are still where \
                    they were. Nothing was lost — change your entry path again to try them once \
                    more.
                    """
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("migrationLeftBehind")
        }
    }

    /// The one line at the top: how much of the journal moved.
    ///
    /// Counted over the days that were parked as well as the days that took
    /// their new path, because both of them moved — a day whose new path was
    /// taken is at a name beside it, and the sentence underneath is what says
    /// which. "0 entries moved" over a folder where a file did move is the one
    /// thing this must not say.
    private func headline(of outcome: MigrationOutcome) -> String {
        let moved = outcome.moved.count + outcome.parked.count
        guard moved > 0 else { return "Nothing moved." }
        return "\(counted(moved, "entry", "entries")) moved."
    }

    // MARK: - Deciding

    private func move() {
        stage = .moving
        Task {
            let outcome = await journal.changeThePathTemplate(to: template, movingEntriesBy: plan)
            stage = .moved(outcome ?? MigrationOutcome(moved: [], parked: [], leftBehind: []))
        }
    }

    /// The skip. The template changes and the files do not — which leaves the
    /// old ones on disk, no longer Entries and no longer surfaced anywhere.
    /// Aujour keeps no list of them: they are the user's to manage in Files or
    /// in Obsidian (ADR 0002).
    private func changeWithoutMoving() {
        Task {
            await journal.changeThePathTemplate(to: template, movingEntriesBy: nil)
            dismiss()
        }
    }

}

/// A number and the noun it counts, in the form the sentence needs — "1
/// entry", "12 entries".
///
/// Every sentence on this screen is about a count of the user's own days, and
/// a screen that says "1 entries" about somebody's journal reads as a screen
/// that was not looked at.
private func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
    "\(count) \(count == 1 ? singular : plural)"
}
