import SwiftUI
import UniformTypeIdentifiers
import AujourCore

/// Where the journal is kept, and the ways of pointing it somewhere else.
///
/// A page of its own, one step in from the settings sheet, and one row: the
/// folder, named the way the Files app names it, and tapping it is how the
/// journal is moved. Choosing a folder used to be a
/// button under the row, and before that a hero on the sheet with the count
/// of entries and a promise about the folder, which is a screenful of the one
/// setting somebody changes once. A row that is the folder and offers the
/// change when it is tapped, and the way back to Aujour's own folder under it
/// for as long as there is one, is the whole of it.
///
/// It is not really a setting, which is why it is the first row on the sheet
/// rather than part of a group: it is the journal. Each device picks its own
/// once and the bookmark is inherently local (ADR 0003), so nothing about the
/// choice travels.
struct JournalFolderView: View {
    let journal: Journal

    /// Whether the offer to move the journal is up.
    @State private var changing = false

    /// Whether the Files picker is up.
    @State private var picking = false

    /// "iPhone" or "iPad" — the Files app names the on-device folder after
    /// whichever one this is.
    private var device: String { UIDevice.current.model }

    var body: some View {
        Form {
            whereItIs
        }
        .settingsPage(titled: "Journal folder")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            // Only a folder that was picked is news: the other outcome is
            // mostly the user tapping Cancel, and an error notice for a mind
            // changed is worse than nothing.
            guard case .success(let folder) = result else { return }
            Task { await journal.use(folder) }
        }
    }

    @ViewBuilder
    private var whereItIs: some View {
        switch journal.state {
        case .opening:
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            .settingsRows()

        case .open(let root, _):
            Section {
                // The folder as the Files app names it — "iCloud Drive ›
                // Aujour", or a picked folder's own name — which is what the
                // sheet's row says too, and the only part of where the folder
                // sits that means anything to the person who put it there. A
                // raw path was tried here and is a sandbox container's worth
                // of hex before the one word that matters.
                //
                // An `HStack` and not a `LabeledContent`, which answers a
                // value that does not fit by stacking it under its label on a
                // line of its own; a folder's name is one line, cut if it must
                // be. The colours are `Color`s and not the hierarchical
                // styles: inside a button `.primary` is the button's tint at
                // full strength, and this is a row that happens to answer a
                // tap, not a call to action.
                Button {
                    changing = true
                } label: {
                    HStack {
                        Text("Location")
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Text(root.location.name(onDevice: device))
                            .lineLimit(1)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .accessibilityIdentifier("journalRootLocation")
                // Anchored to the row rather than the page, which is where an
                // iPad draws it from. No title: the row it comes out of has
                // just said which folder this is about.
                .confirmationDialog(
                    "Journal folder",
                    isPresented: $changing,
                    titleVisibility: .hidden
                ) {
                    Button("Choose Another Folder…") { chooseAFolder() }
                        .accessibilityIdentifier("chooseCustomFolder")
                }
            }
            .settingsRows()

            // The way back, when there is one. A button and not a second
            // choice in the row's dialog: it undoes the folder rather than
            // choosing one, and a thing that undoes belongs where it can be
            // seen before anything is tapped.
            if journal.hasACustomFolder {
                Section {
                    Button("Use Aujour's own folder") {
                        Task { await journal.useAujoursOwnFolder() }
                    }
                    .accessibilityIdentifier("useAujoursOwnFolder")
                }
                .settingsRows()
            }

            // Said on the page that can do something about it as well as on
            // the sheet: a folder that cannot be reached is the likeliest
            // reason to be here at all.
            if let problem = journal.folderProblem {
                Section {
                    FolderProblemNotice(problem: problem, identifier: "journalFolderProblem")
                }
                .settingsRows()
            }

        case .unavailable(let problem):
            Section {
                FolderProblemNotice(problem: problem, identifier: "journalRootProblem")
            }
            .settingsRows()
        }
    }

    private func chooseAFolder() {
        // The Files picker is another process's screen, and driving it is the
        // one part of choosing a folder that a UI test cannot do without
        // becoming a test of that screen. So the UI suite says which folder it
        // means at launch, and it goes in through the same door the picker's
        // would — everything after this point is the app's own code.
        if let folder = UITestingJournal.folderToPick() {
            Task { await journal.use(folder) }
            return
        }
        picking = true
    }
}

#Preview {
    NavigationStack {
        JournalFolderView(journal: Journal.inAPreview(over: .system))
    }
}
