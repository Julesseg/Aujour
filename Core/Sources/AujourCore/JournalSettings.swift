/// The settings that shape the Journal itself: where Entries and Attachments
/// land, what a new Entry starts from, how embeds are written, and when the
/// Journal Day turns.
///
/// These are the settings two devices may not disagree about — an iPhone and
/// an iPad with different Path Templates would write the same day to two
/// paths and break the one-Entry-per-day rule — so they sync across the
/// user's devices through `JournalSettingsStore` (ADR 0003).
public struct JournalSettings: Equatable, Sendable {
    /// Moment-format path for an Entry, relative to the Journal Root.
    public var pathTemplate: String

    /// The markdown file a new Entry is spawned from, as a path relative to
    /// the Journal Root — or empty for none, which is a blank page.
    ///
    /// The file and not its text, because the template *is* a file in the
    /// user's vault: Obsidian's daily notes name one exactly this way, so an
    /// existing setup points at the file it already has, and editing that file
    /// in Obsidian is what changes tomorrow's Entry. There is no copy inside
    /// Aujour to go stale (ADR 0005).
    ///
    /// Inside the Journal Root and nowhere else, because this setting travels
    /// (ADR 0003): a bookmark to a file elsewhere on the device is that
    /// device's alone, and an iPad that could not find the template would
    /// start the same day from a different page than the iPhone.
    ///
    /// Empty by default: Obsidian ships no daily-note template either, and a
    /// blank page is a better first Entry than one full of scaffolding the
    /// user did not ask for.
    public var contentTemplateFile: String

    /// Moment-format folder for Attachments, relative to the Journal Root.
    public var attachmentPathTemplate: String

    /// How Attachment embeds are written into Entries. Aujour renders both
    /// regardless; this decides what it writes.
    public var embedSyntax: EmbedSyntax

    /// When the current Journal Day advances.
    public var rolloverHour: RolloverHour

    public init(
        pathTemplate: String = "YYYY/MM/YYYY-MM-DD",
        contentTemplateFile: String = "",
        attachmentPathTemplate: String = "[attachments]/YYYY/MM",
        embedSyntax: EmbedSyntax = .standardMarkdown,
        rolloverHour: RolloverHour = .midnight
    ) {
        self.pathTemplate = pathTemplate
        self.contentTemplateFile = contentTemplateFile
        self.attachmentPathTemplate = attachmentPathTemplate
        self.embedSyntax = embedSyntax
        self.rolloverHour = rolloverHour
    }

    /// The defaults from the product decision log: an Obsidian daily-notes
    /// layout, midnight rollover, standard-markdown embeds.
    public static let `default` = JournalSettings()
}

/// How an Attachment is embedded in an Entry.
public enum EmbedSyntax: String, Hashable, Sendable, CaseIterable {
    /// `![](attachments/2026/03/photo.jpg)` — portable markdown, the default.
    case standardMarkdown
    /// `![[photo.jpg]]` — Obsidian's wiki-style embed.
    case obsidianWikiLink
}

/// Keeps the journal-shaping settings in step across the user's devices.
///
/// Construction reads whatever the seam already holds; edits are written back
/// field by field; and writes arriving from another device are picked up and
/// announced to observers, so a Path Template changed on the iPad reshapes
/// the iPhone without a relaunch.
@MainActor
public final class JournalSettingsStore {
    private let storage: SettingsStorage<JournalSettings>

    /// - Parameter store: the seam these settings travel through — iCloud
    ///   key-value storage in the app, a fake in tests.
    public init(syncedThrough store: any SyncedKeyValueStore) {
        let storage = SettingsStorage<JournalSettings>(store: store)
        self.storage = storage
        // Weakly, so the seam outliving this store cannot keep it alive.
        store.observeExternalChanges { [weak storage] in storage?.reloadFromStore() }
    }

    public var settings: JournalSettings { storage.value }

    /// Applies an edit and syncs it. Fields left alone are not rewritten, so
    /// an edit made on another device at the same moment survives.
    public func update(_ change: (inout JournalSettings) -> Void) {
        storage.update(change)
    }

    /// Reports every change, whether made here or arriving from another
    /// device. Cancel the returned observation to stop.
    @discardableResult
    public func observe(_ handler: @escaping (JournalSettings) -> Void) -> SettingsObservation {
        storage.observe(handler)
    }
}

enum JournalSettingsKey {
    static let pathTemplate = "aujour.journal.pathTemplate"
    static let contentTemplateFile = "aujour.journal.contentTemplateFile"
    static let attachmentPathTemplate = "aujour.journal.attachmentPathTemplate"
    static let embedSyntax = "aujour.journal.embedSyntax"
    static let rolloverHour = "aujour.journal.rolloverHour"
}

extension JournalSettings: SettingsGroup {
    init(storedValues: (String) -> String?) {
        let fallback = JournalSettings.default
        // An empty template is not a template — it would name every Entry
        // `.md` — so it is treated as unreadable rather than obeyed.
        self.pathTemplate = storedValues(JournalSettingsKey.pathTemplate)
            .flatMap { $0.isEmpty ? nil : $0 } ?? fallback.pathTemplate
        self.contentTemplateFile = storedValues(JournalSettingsKey.contentTemplateFile)
            ?? fallback.contentTemplateFile
        self.attachmentPathTemplate = storedValues(JournalSettingsKey.attachmentPathTemplate)
            .flatMap { $0.isEmpty ? nil : $0 } ?? fallback.attachmentPathTemplate
        self.embedSyntax = storedValues(JournalSettingsKey.embedSyntax)
            .flatMap(EmbedSyntax.init(rawValue:)) ?? fallback.embedSyntax
        self.rolloverHour = storedValues(JournalSettingsKey.rolloverHour)
            .flatMap(Int.init).flatMap(RolloverHour.init(hour:)) ?? fallback.rolloverHour
    }

    func changedValues(from previous: JournalSettings) -> [(key: String, value: String?)] {
        var changes: [(key: String, value: String?)] = []
        if pathTemplate != previous.pathTemplate {
            changes.append((JournalSettingsKey.pathTemplate, pathTemplate))
        }
        if contentTemplateFile != previous.contentTemplateFile {
            changes.append((JournalSettingsKey.contentTemplateFile, contentTemplateFile))
        }
        if attachmentPathTemplate != previous.attachmentPathTemplate {
            changes.append((JournalSettingsKey.attachmentPathTemplate, attachmentPathTemplate))
        }
        if embedSyntax != previous.embedSyntax {
            changes.append((JournalSettingsKey.embedSyntax, embedSyntax.rawValue))
        }
        if rolloverHour != previous.rolloverHour {
            changes.append((JournalSettingsKey.rolloverHour, String(rolloverHour.hour)))
        }
        return changes
    }
}
