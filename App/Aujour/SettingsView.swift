import SwiftUI
import AujourCore

/// Everything about the journal and the app that the user can change, grouped
/// by what it is about.
///
/// Three sections and almost no words. The sheet used to sort its settings by
/// where they *go* — one group that reaches the other devices and one that
/// stays here — with a sentence over each saying so, and a caption under every
/// control explaining it. That answered a question ("does this reach my
/// iPad?") nobody had asked at the cost of the one they had ("where do I
/// change the folder?"): two paragraphs, six captions and a hero before the
/// first setting. So the grouping is by subject now — the files, what goes
/// into an entry, and this device — and nothing on the sheet says which
/// settings sync, deliberately.
///
/// Drawn with the platform's own components rather than the identity's
/// hand-built rows. A settings screen is the one screen in an app where being
/// recognisably iOS is worth more than being recognisably Aujour: the rows,
/// the chevrons, the toggles and the menus are muscle memory, and a hand-built
/// version of them is a worse copy of something the reader already knows. What
/// stays the identity's is the paper it is cut from — the list's own
/// background is hidden so the sheet shows through.
///
/// The rule for prose, applied everywhere below and on the four pages the rows
/// open: labels, values, worked examples and problem notices. Nothing else. A
/// setting that cannot be understood from its label and its value gets an
/// example of what it writes, which is the thing a paragraph was failing to
/// say.
///
/// Every row that opens a page shows its current value, so the sheet is a
/// summary of the journal and not a menu of doors. The toggles and the menus
/// act in place, because they have one answer each and a page for it would be
/// a page holding one control.
///
/// It takes the whole Journal rather than the folder it is currently over,
/// because choosing a folder closes one journal and opens another: the sheet
/// has to still be there, and still be saying something true, while that
/// happens. Nothing holds its own copy of a setting for longer than it is
/// being typed, for the same reason — the controls that are not text follow
/// the journal directly, so a setting changed on the iPad arrives here while
/// the sheet is up (ADR 0003).
struct SettingsSheet: View {
    let journal: Journal

    /// How Aujour looks on this device, for the one row here that is not about
    /// the journal at all.
    let appearance: DeviceAppearance

    @Environment(\.dismiss) private var dismiss

    /// "iPhone" or "iPad" — the app runs on both, and the Files app names the
    /// on-device folder after whichever one this is.
    private var device: String { UIDevice.current.model }

    var body: some View {
        NavigationStack {
            Form {
                // Above the settings, because it is the reason none of them
                // can be carried out: a folder that will not answer takes no
                // change either.
                if let problem = journal.folderProblem {
                    Section {
                        FolderProblemNotice(problem: problem, identifier: "folderProblem")
                    }
                    .settingsRows()
                }
                files.settingsRows()
                entries.settingsRows()
                thisDevice.settingsRows()
            }
            .settingsPage(titled: "Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Full height rather than half: this is the folder, its paths and its
        // templates, and nearly all of it would be below the fold.
        .presentationDetents([.large])
    }

    /// Where the writing lives: the folder, the two paths inside it, and the
    /// file a new day is spawned from.
    ///
    /// The folder is a row like the others now rather than the hero it used to
    /// be. It is the first thing anybody comes here for and it is at the top,
    /// which is all the emphasis a list has to give — and what it used to
    /// spend on a 44-point glyph and a promise was three settings' worth of
    /// screen.
    private var files: some View {
        Section("Files") {
            NavigationLink {
                JournalFolderView(journal: journal)
            } label: {
                LabeledContent("Journal folder", value: folderName)
            }
            .accessibilityIdentifier("openJournalFolder")

            NavigationLink {
                EntryPathView(journal: journal, accent: appearance.accent)
            } label: {
                LabeledContent("Entry path", value: journal.pathTemplate)
            }
            .accessibilityIdentifier("openEntryPath")

            NavigationLink {
                AttachmentPathView(journal: journal)
            } label: {
                LabeledContent("Photo path", value: journal.attachmentPathTemplate)
            }
            .accessibilityIdentifier("openPhotoPath")

            NavigationLink {
                ContentTemplateView(journal: journal)
            } label: {
                LabeledContent("Template", value: journal.contentTemplateName ?? "None")
            }
            .accessibilityIdentifier("openContentTemplate")
        }
    }

    /// The folder's name, or nothing at all while there is no folder to name.
    /// A row that said "Opening…" would be a row whose value is a status.
    private var folderName: String {
        guard case .open(let root, _) = journal.state else { return "" }
        return root.location.name(onDevice: device)
    }

    /// What ends up inside an entry: the day's own data, which day it is, and
    /// how a photograph is written in.
    ///
    /// The two data placeholders show their `{{token}}` as the row's value
    /// rather than its label, because that is the thing the user types into
    /// their template and the thing they are looking for.
    ///
    /// The embed setting is a toggle rather than two named spellings. There
    /// are exactly two, one of them is Obsidian's, and the example underneath
    /// says what either comes out as — which is a better answer than the words
    /// "Markdown" and "Wiki-style" side by side.
    private var entries: some View {
        Section {
            ForEach(DataPlaceholder.allCases, id: \.self) { placeholder in
                NavigationLink {
                    HowADataPlaceholderIsWrittenView(journal: journal, placeholder: placeholder)
                } label: {
                    LabeledContent(placeholder.onScreen, value: placeholder.token)
                }
                .accessibilityIdentifier("dataPlaceholder-\(placeholder.rawValue)")
            }

            Picker("Day starts at", selection: rolloverHour) {
                ForEach(RolloverHour.everyHourOfTheDay, id: \.hour) { rollover in
                    Text(rollover.spelledOut()).tag(rollover.hour)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("rolloverHour")

            Toggle("Wiki-style embeds", isOn: wikiStyleEmbeds)
                .accessibilityIdentifier("embedSyntax")
        } header: {
            Text("Entries")
        } footer: {
            // The setting made concrete on the day the user is in: two
            // spellings described in words are two spellings somebody has to
            // imagine, and this is the line that would go in their file.
            if let example = journal.exampleEmbed {
                Text(example)
                    .monospaced()
                    .accessibilityIdentifier("embedSyntaxExample")
            }
        }
    }

    /// The two settings that are about the device rather than the journal.
    ///
    /// Unnamed, because there is no honest name for it. "This device" was the
    /// old grouping's word and it promised something about syncing that the
    /// sheet no longer sets out to say; "Other" would be filing. What is in it
    /// is what was left over, and a section with no header is what a list says
    /// for that.
    private var thisDevice: some View {
        Section {
            NavigationLink {
                AppearanceSettingsView(appearance: appearance)
            } label: {
                LabeledContent("Appearance", value: appearance.accent.name)
            }
            .accessibilityIdentifier("openHowItLooks")

            Toggle("Daily reminder", isOn: remindMe)
                .accessibilityIdentifier("dailyReminder")

            // Off until a time is chosen, which is the whole of what the
            // toggle means: there is no reminder to disable on a fresh
            // install. So the time only exists while there is one.
            if journal.dailyReminder.time != nil {
                TimeOfDayPicker(label: "Time", time: reminderTime)
                    .accessibilityIdentifier("dailyReminderTime")
            }
        } footer: {
            // A problem notice, which is the one kind of sentence this sheet
            // still allows: a time set on a device where notifications are off
            // is a reminder that will never come, and the way back is Settings
            // rather than anything on this screen.
            if journal.dailyReminder.access == .refused, journal.dailyReminder.time != nil {
                NudgesAreTurnedOffNotice(identifier: "dailyReminderRefused")
            }
        }
    }

    /// When the current Journal Day advances — a binding rather than local
    /// state, because a Rollover Hour set on the iPad arrives here while the
    /// sheet is up (ADR 0003).
    private var rolloverHour: Binding<Int> {
        Binding(
            get: { journal.rolloverHour.hour },
            set: { chosen in
                guard let hour = RolloverHour(hour: chosen) else { return }
                Task { await journal.changeTheRolloverHour(to: hour) }
            }
        )
    }

    /// How Aujour writes an embed when a photograph goes into a day. Changing
    /// it moves nothing and rewrites nothing: both spellings are drawn as the
    /// picture they name wherever they are written (`EmbedTarget`), so this
    /// decides what the next one is written as and nothing else.
    private var wikiStyleEmbeds: Binding<Bool> {
        Binding(
            get: { journal.embedSyntax == .obsidianWikiLink },
            set: { wanted in
                let syntax: EmbedSyntax = wanted ? .obsidianWikiLink : .standardMarkdown
                Task { await journal.changeTheEmbedSyntax(to: syntax) }
            }
        )
    }

    /// Whether there is a reminder at all. Turning it on is also the one
    /// moment the notification permission is asked for — the app has no other
    /// reason to want one.
    private var remindMe: Binding<Bool> {
        Binding(
            get: { journal.dailyReminder.time != nil },
            set: { wanted in
                Task {
                    await journal.remindMeDaily(at: wanted ? DailyReminder.suggestedTime : nil)
                }
            }
        )
    }

    /// The time it arrives.
    ///
    /// Written through on every minute the picker passes over rather than on
    /// the one it is let go at, because a `DatePicker` has no notion of being
    /// let go: the reminder is whatever the wheels say, at every moment they
    /// say it. What that costs is a handful of settings writes and reckonings
    /// nobody sees — and the reckoning that lands out of order is dropped by
    /// `DailyReminder` rather than booked.
    private var reminderTime: Binding<TimeOfDay> {
        Binding(
            get: { journal.dailyReminder.time ?? DailyReminder.suggestedTime },
            set: { chosen in Task { await journal.remindMeDaily(at: chosen) } }
        )
    }
}

#Preview {
    SettingsSheet(journal: Journal.inAPreview(over: .system), appearance: .inMemory())
}
