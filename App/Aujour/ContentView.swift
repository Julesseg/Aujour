import SwiftUI
import UniformTypeIdentifiers
import AujourCore

/// The app's one screen: today's Entry, over the folder the journal lives in.
///
/// Two things have to be true before there is anything to type into, and they
/// are the two states around the editor here — Aujour has found a folder, and
/// it has read what that folder holds for today. Neither is ever shown as an
/// empty page: an empty editor over a folder that could not be read is
/// indistinguishable from a day nobody wrote on (ADR 0001).
struct ContentView: View {
    @State private var journal: Journal
    @State private var showingTheJournalItself = false
    /// The screen on top of today's Entry, if one is — nil while today's is
    /// what is on screen.
    ///
    /// One piece of state for both, rather than a flag each: two
    /// `navigationDestination(isPresented:)` modifiers on one view are two
    /// destinations the stack picks between, and which one a tap opens stops
    /// being a thing this screen decides.
    @State private var wayIn: WayIntoTheJournal?

    /// The day the app is on, when it is not today's — its editor, made once
    /// and kept for as long as that day is on screen.
    ///
    /// `nil` while today is the day being written, because today's Entry is
    /// the Journal's own and there must never be two editors over one file:
    /// two of them autosaving over each other is a day's words losing to
    /// themselves. Which of the two is on screen is the calendar's to say, and
    /// this is only where the other one is kept.
    @State private var dayPickedOutOfTheGrid: OpenedDay?

    @Environment(\.scenePhase) private var scenePhase

    /// What this window is actually drawing in, light or dark — never "no
    /// preference", because this is the answer and not the question.
    ///
    /// Read here so that a sheet can be told it. A sheet is its own
    /// presentation: the appearance the window asks for reaches it when it is
    /// put up and not afterwards, so it has to be told again on every change.
    /// And told a *resolved* scheme, because the interesting case is Auto —
    /// "no preference" does not undo an override a sheet is already under, so
    /// a sheet told dark and then told nothing goes on being dark while the
    /// window behind it turns light.
    @Environment(\.colorScheme) private var drawnIn

    /// The two ways back into a day that is not today's: by when it was, and
    /// by what was written in it.
    private enum WayIntoTheJournal: Hashable {
        case search
    }

    /// How this device wants Aujour to look, held for the one screen that
    /// changes it. The app is already drawn in it — the appearance, the tint
    /// and the editor's typeface are applied above this view — so all this
    /// does is carry it as far as the page that offers the choices.
    private let appearance: DeviceAppearance

    init(journal: Journal = Journal(), appearance: DeviceAppearance) {
        _journal = State(wrappedValue: journal)
        self.appearance = appearance
    }

    /// Whether a welcome is owed, as something a cover can be presented on.
    ///
    /// Read-only in the direction that matters: the welcome ends when it has
    /// been answered, and it says so itself by no longer being due. Nothing
    /// SwiftUI can do to this binding is a way out of it, which is the point —
    /// a cover dismissed by anything but one of its own buttons would be a
    /// device that had been welcomed without hearing any of it.
    private var theWelcomeIsDue: Binding<Bool> {
        Binding(get: { journal.welcome.isDue }, set: { _ in })
    }

    /// The way out of a folder that has gone: the user's Entries are still in
    /// it, and Aujour's own folder is somewhere to write in the meantime.
    ///
    /// Offered only when the folder that failed is one they chose — for
    /// Aujour's own folder there is nowhere else to go, and a button that
    /// does nothing is worse than no button.
    private var wayBackToAujoursOwnFolder: (() async -> Void)? {
        guard journal.hasACustomFolder else { return nil }
        return { await journal.useAujoursOwnFolder() }
    }

    /// The day the app is showing, and the editor over it.
    ///
    /// Today's until a day is picked out of the grid, and today's again the
    /// moment today is picked — which is the calendar's answer and not a copy
    /// of it kept here, so that a phone left open past the rollover moves on
    /// to the new day rather than staying on the old one.
    private var entryOnScreen: OpenedDay? {
        if let picked = dayPickedOutOfTheGrid, journal.calendar?.dayBeingWritten == picked.day {
            return picked
        }
        return journal.today.map { OpenedDay(day: $0.day, editor: $0) }
    }

    /// Opens a day picked out of the date pill's grid.
    ///
    /// The day left behind is saved and the folder read again before anything
    /// else — which is what puts the dot on a day that has just been filled in,
    /// and what keeps the app to one editor per Entry.
    private func pick(_ day: JournalDay) {
        guard let calendar = journal.calendar, day != calendar.dayBeingWritten else { return }
        let leaving = dayPickedOutOfTheGrid
        // Refused for a day that has not arrived — the cell is disabled, and
        // this is the same refusal said where it cannot be tapped around.
        guard calendar.pick(day) else { return }

        // Today's Entry is the Journal's own, so picking today is putting this
        // one down rather than making another. One assignment either way, so
        // the day held here and the day the calendar is on cannot come apart.
        dayPickedOutOfTheGrid =
            calendar.isOnToday
            ? nil
            : calendar.editor(for: day).map { OpenedDay(day: day, editor: $0) }

        if let opened = dayPickedOutOfTheGrid {
            Task {
                // Before it is read, for the same reason today's Entry is: a
                // past day can have been written on two devices too —
                // backfilled on the iPad on the train and on the iPhone that
                // evening — and the version that loses its path is set aside
                // rather than left in iCloud where nobody would ever see it.
                await journal.settleAnyDivergence(before: opened.editor)
                await opened.editor.open()
            }
        }

        Task {
            if let leaving {
                await leaving.editor.save()
            } else {
                await journal.today?.save()
            }
            await calendar.scan()
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch journal.state {
                case .opening:
                    ProgressView("Opening your journal")
                        .accessibilityIdentifier("openingJournal")
                        .navigationTitle("Aujour")

                case .open:
                    // There is no open journal without today's Entry over it
                    // — but a blank page is the one thing this screen must
                    // never be, so the unreachable case is the spinner.
                    if let onScreen = entryOnScreen {
                        EntryView(
                            editor: onScreen.editor,
                            photographsFrom: journal.photoLibrary,
                            placesFrom: journal.places
                        )
                            .parkedFilesNotice(from: journal, for: onScreen.day)
                            .datePill(
                                over: journal.calendar,
                                accent: appearance.accent,
                                pick: pick,
                                // Written down before the month is read: the
                                // marks are a scan of the folder, and a day
                                // being filled in this second is a day whose
                                // file is not there yet.
                                settling: { await onScreen.editor.save() }
                            )
                            // The pill names the day now, so the bar carries
                            // the ways out of it and nothing else — a title
                            // saying the same thing twice, once in each of two
                            // typefaces, is the redesign's own worst screen.
                            .navigationTitle("")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    // The other way back into a day, and now
                                    // the only one in the bar: by when it was
                                    // is the pill's, and by what was written
                                    // in it is this.
                                    Button("Search", systemImage: "magnifyingglass") {
                                        wayIn = .search
                                    }
                                    .accessibilityIdentifier("openSearch")
                                }
                                ToolbarItem(placement: .topBarTrailing) {
                                    // One way in for the folder and every
                                    // setting over it, because they are one
                                    // answer: this is your journal, and this
                                    // is what Aujour will do with it.
                                    Button("Your journal", systemImage: "folder.badge.gearshape") {
                                        showingTheJournalItself = true
                                    }
                                    .accessibilityIdentifier("openTheJournalSheet")
                                }
                            }
                    } else {
                        ProgressView("Opening today's entry")
                            .accessibilityIdentifier("openingEntry")
                    }

                case .unavailable(let problem):
                    StorageProblemNotice(
                        problem: problem,
                        useAujoursOwnFolder: wayBackToAujoursOwnFolder
                    ) {
                        await journal.open()
                    }
                    .navigationTitle("Aujour")
                }
            }
            // Outside the states, like the calendar below and for the same
            // reason: choosing a folder closes the journal it was opened from
            // and opens another, and a sheet that lives inside one state is a
            // sheet that vanishes mid-decision.
            // Outside the states rather than inside `.open`: choosing a
            // folder closes the journal it was opened from and opens another,
            // and every setting on the sheet reopens it too — a sheet that
            // lived inside one state is a sheet that vanishes mid-decision.
            .sheet(isPresented: $showingTheJournalItself) {
                JournalSettingsSheet(journal: journal, appearance: appearance)
                    // The one sheet this matters most for: it is where the
                    // appearance is changed, so it is the one that would sit
                    // in yesterday's colours right under the control that had
                    // just changed them.
                    .preferredColorScheme(drawnIn)
                    // Counted again on the way in: the number from launch is
                    // one edit out of date the moment today's Entry is
                    // created.
                    .task { await journal.recount() }
            }
            // Declared outside the states rather than beside the button that
            // opens it: a destination registered only while one branch of a
            // switch is on screen is one the stack can find itself without.
            //
            // Today's Entry is what the app is for, so this is a step away
            // from it and back — and coming back is what re-reads the folder
            // for a day just filled in.
            .navigationDestination(item: $wayIn) { wayIn in
                switch wayIn {
                case .search:
                    if let search = journal.search {
                        JournalSearchView(search: search, journal: journal)
                    }
                }
            }
        }
        // Over everything rather than in place of it, and put up without
        // waiting for anything: the folder is being found and today's Entry
        // spawned behind this, so the app is ready to be written in the moment
        // the last page is answered. A first run that made somebody wait for a
        // folder before it would say hello would be a first run that made them
        // wait for iCloud.
        .fullScreenCover(isPresented: theWelcomeIsDue) {
            WelcomeView(journal: journal)
        }
        .task { await journal.open() }
        // A journal that has been reopened — a folder changed, a Path Template
        // changed — is a new calendar over new files, and a day held from the
        // old one is an editor over a store nothing is journaling into any
        // more.
        .onChange(of: journal.calendar.map(ObjectIdentifier.init)) { _, _ in
            dayPickedOutOfTheGrid = nil
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .inactive, .background:
                // The last chance to write: there is no next second to save in
                // once the app is out of the way, and the debounce the editor
                // is holding would be spent in it.
                //
                // And then the reminder, in that order and never the other
                // way: whether today still needs asking about is decided by
                // whether today's Entry is a file, and the words that would
                // make it one are the ones being saved here.
                //
                // Both editors, because a day backfilled from the pill is
                // being written into just as literally as today is.
                Task {
                    await journal.today?.save()
                    await dayPickedOutOfTheGrid?.editor.save()
                    await journal.reconsiderTheDailyReminder()
                }
            case .active:
                // What coming back to the front means for a journal that is
                // files in a folder — a new day, and a folder that moved on
                // while nothing was listening — is the Journal's to say. It
                // says it for today's Entry; a day picked out of the grid is
                // this screen's own, and catches up the same way, taking on
                // what its file says wherever nothing here is waiting to be
                // written to it.
                Task {
                    await journal.cameBackToTheFront()
                    await dayPickedOutOfTheGrid?.editor.reloadIfClean()
                }
            @unknown default:
                break
            }
        }
    }
}


extension View {
    /// Says, above a day's Entry, that another version of that day was kept
    /// beside it.
    ///
    /// A modifier because there are two ways into a day and both of them need
    /// it: today's screen, and a day filled in from the calendar. Each shows
    /// only its own day's Parked Files — a notice about March 1st over the
    /// Entry for the 14th would be about a file that is nowhere near it.
    ///
    /// Above the words rather than over them: a version of this day the user
    /// has not seen is news, and the day itself is still theirs to write in
    /// while the notice is up.
    func parkedFilesNotice(from journal: Journal, for day: JournalDay) -> some View {
        safeAreaInset(edge: .top) {
            let parked = journal.parkedFiles(from: day)
            if !parked.isEmpty {
                ParkedFilesNotice(files: parked) {
                    journal.acknowledgeParkedFiles(from: day)
                }
            }
        }
    }
}

/// A day two devices both wrote, said where the user is writing it.
///
/// The Parked File beside the Entry is the lasting notice — it is a file in
/// their vault, which is where they will meet it again. This is so that they
/// meet it at all: without it, the only sign that a version of today was set
/// aside would be a file they have no reason to go looking for.
///
/// Dismissible, and nothing else. Aujour does not offer to merge the two, or
/// to delete either: they are the user's words in the user's folder, and this
/// is the one moment the app is not the right thing to be doing it in
/// (ADR 0002).
struct ParkedFilesNotice: View {
    let files: [ParkedFile]
    let acknowledge: () -> Void

    private var names: String {
        files.map(\.name).formatted(.list(type: .and))
    }

    private var headline: String {
        files.count == 1
            ? "Another version of this day was kept"
            : "\(files.count) other versions of this day were kept"
    }

    private var detail: String {
        files.count == 1
            ? "Two devices wrote it, so Aujour kept both rather than merging them. The other one is beside your entry as \(names) — open it in Files or Obsidian to bring across anything you want."
            : "This day was written on more than one device, so Aujour kept every version rather than merging them. They are beside your entry as \(names) — open them in Files or Obsidian to bring across anything you want."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.on.doc")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("parkedFileNotice")
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("parkedFileNames")
            }
            Spacer(minLength: 0)
            Button("Dismiss", systemImage: "xmark", action: acknowledge)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("dismissParkedFileNotice")
        }
        .padding(12)
        .background(.thinMaterial)
    }
}

/// The reminder cannot arrive, said where somebody is setting one.
///
/// Two screens set the same reminder — the welcome's last page and the journal
/// sheet — and a device that has said no makes both of them untrue in exactly
/// the same way, so they say so in the same words. The way back is Settings and
/// nothing on either screen, which is the whole of what there is to say.
struct NudgesAreTurnedOffNotice: View {
    /// What a test finds it by: either screen can be the one it is on.
    let identifier: String

    var body: some View {
        Text(
            """
            Notifications are turned off for Aujour, so this won't arrive. \
            Turn them on in Settings › Notifications › Aujour.
            """
        )
        .font(.caption)
        .foregroundStyle(.red)
        .accessibilityIdentifier(identifier)
    }
}

/// Something that went wrong with a folder, in the two sentences it takes to
/// say what and what to do — the compact form, for beside the thing it is
/// about.
struct FolderProblemNotice: View {
    let problem: StorageProblem

    /// What a test would find it by — the sheet can show two of these at
    /// once, about two different folders.
    let identifier: String

    var body: some View {
        VStack(spacing: 4) {
            Text(problem.message)
                .font(.callout.weight(.semibold))
                .accessibilityIdentifier(identifier)
            Text(problem.suggestion)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }
}

/// A folder that could not be reached. Says what happened and what to do, and
/// offers the retry — never a blank page that reads as a lost journal.
struct StorageProblemNotice: View {
    let problem: StorageProblem

    /// The way back to the folder Aujour finds for itself, offered only when
    /// the folder that failed is one the user chose.
    ///
    /// Without it, a vault folder renamed on another device is a journal the
    /// user cannot get out of: retrying a folder that is gone will go on
    /// failing, and their words are somewhere Aujour can no longer be pointed.
    var useAujoursOwnFolder: (() async -> Void)? = nil

    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(problem.message, systemImage: "exclamationmark.icloud")
                .accessibilityIdentifier("storageProblem")
        } description: {
            Text(problem.suggestion)
        } actions: {
            Button("Try Again") {
                Task { await retry() }
            }
            .accessibilityIdentifier("retryOpeningJournal")

            if let useAujoursOwnFolder {
                Button("Use Aujour's Own Folder") {
                    Task { await useAujoursOwnFolder() }
                }
                // Not the sheet's button of the same words: a journal that
                // could not be opened can have both on screen at once.
                .accessibilityIdentifier("recoverWithAujoursOwnFolder")
            }
        }
    }
}

// Previews journal into a scratch folder rather than into whatever this Mac's
// iCloud Drive holds, so each one shows the state it is named after.
#Preview("Journaling into iCloud Drive") {
    ContentView(
        journal: Journal.inAPreview(over: .preview(.iCloudDrive)),
        appearance: .inMemory()
    )
}

#Preview("Journaling on the device") {
    ContentView(
        journal: Journal.inAPreview(over: .preview(.onThisDevice)),
        appearance: .inMemory()
    )
}

#Preview("Journaling into a folder of the user's own") {
    ContentView(
        journal: Journal.inAPreview(over: .previewCustomFolder),
        appearance: .inMemory()
    )
}

#Preview("Nowhere to journal") {
    ContentView(
        journal: Journal.inAPreview(over: .preview(nil)),
        appearance: .inMemory()
    )
}

extension JournalRootLocator {
    /// A locator over a scratch folder, pinned to one of Aujour's own
    /// locations — or to none, for the failure the user would see with iCloud
    /// Drive off and the app's own folder unreachable.
    ///
    /// Reachable from the other screens' previews too: any of them that takes
    /// a whole `Journal` needs one that is not this Mac's own.
    static func preview(_ location: JournalRoot.DefaultFolder?) -> JournalRootLocator {
        let folder = URL.temporaryDirectory.appending(path: "AujourPreview/\(location?.rawValue ?? "none")")
        return JournalRootLocator(
            iCloudDocuments: { location == .iCloudDrive ? folder : nil },
            onThisDeviceDocuments: { location == .onThisDevice ? folder : URL(filePath: "/dev/null/nowhere") },
            lastUsedLocation: { nil },
            rememberLocation: { _ in }
        )
    }

    /// A locator already pointed at a folder of the user's own, so the sheet
    /// shows what someone journaling inside an Obsidian vault sees.
    fileprivate static var previewCustomFolder: JournalRootLocator {
        let vault = URL.temporaryDirectory.appending(path: "AujourPreview/Vault/Journal")
        try? FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        // Straight to a bookmark: a preview has no picker to tap.
        let bookmark = try? vault.bookmarkData()
        return JournalRootLocator(
            iCloudDocuments: { nil },
            onThisDeviceDocuments: { URL(filePath: "/dev/null/nowhere") },
            lastUsedLocation: { nil },
            rememberLocation: { _ in },
            customRoot: CustomJournalRoot(
                storedBookmark: { bookmark },
                rememberBookmark: { _ in }
            )
        )
    }
}
