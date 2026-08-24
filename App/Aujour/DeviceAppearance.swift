import SwiftUI
import AujourCore

/// How this device wants Aujour to look, live.
///
/// The device-local half of the settings seam, as SwiftUI needs it: a value
/// that changes under a running app, and a view that redraws when it does.
/// It is read through `UserDefaults` and never through iCloud (ADR 0003) —
/// an iPhone in dark and an iPad in light are not in disagreement about
/// anything, and nothing here shapes a file in the journal folder.
///
/// Everything about how the app looks, and nothing about when it nudges: the
/// daily reminder is the other reader of this seam and lives in Core, where
/// what it has to decide can be tested.
///
/// Handed the store rather than making one, and the same store the reminder
/// reads — a settings group reports its changes to whoever is holding it, and
/// a second `DeviceSettingsStore` over the same `UserDefaults` would write a
/// theme this one never hears about.
///
/// The screen that chooses any of this is handed *this* object rather than one
/// of its own, and changes it by asking rather than by setting: every property
/// here is what the settings say, and the settings are the only place a choice
/// is kept.
@MainActor
@Observable
final class DeviceAppearance {
    private let settings: DeviceSettingsStore

    private(set) var theme: Theme
    private(set) var accent: Accent
    private(set) var editorFont: EditorFont

    /// Held for as long as this object is: cancelled with it, and reporting
    /// every change until then.
    private var watchingTheSettings: SettingsObservation?

    init(settings: DeviceSettingsStore = DeviceSettingsStore(storedOn: LocalSettingsStorage())) {
        self.settings = settings
        let inForce = settings.settings
        self.theme = inForce.theme
        self.accent = inForce.accent
        self.editorFont = inForce.editorFont
        watchingTheSettings = settings.observe { [weak self] in self?.adopt($0) }
    }

    /// An appearance that remembers nothing past this process — for previews
    /// and for tests, neither of which should be reading or writing the
    /// settings of the Aujour installed on this Mac.
    static func inMemory() -> DeviceAppearance {
        DeviceAppearance(settings: DeviceSettingsStore(storedOn: InMemoryLocalKeyValueStore()))
    }

    /// What SwiftUI is told to draw in, where `nil` is "whatever the system is
    /// doing" — the default, and the only one of the three that is not an
    /// instruction to override the system.
    var colorScheme: ColorScheme? {
        switch theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The app's own colour, for everything SwiftUI tints — every button, and
    /// the sheets they open.
    var accentColor: Color { accent.color }

    /// How the editor is to draw: the two of these that reach the words
    /// themselves, as the one value that travels to the text view.
    var editorLook: EditorLook { EditorLook(font: editorFont, accent: accent) }

    func use(_ theme: Theme) {
        settings.update { $0.theme = theme }
    }

    func use(_ accent: Accent) {
        settings.update { $0.accent = accent }
    }

    /// Named for the font rather than overloaded on `use`, because `.system`
    /// is both an appearance and a typeface and a reader should not have to
    /// work out which one a call meant.
    func useEditorFont(_ family: EditorFont.Family) {
        settings.update { $0.editorFont.family = family }
    }

    /// A point size for the editor — clamped to what the editor can render
    /// rather than obeyed, which is `EditorFont`'s own rule and not this
    /// screen's to restate.
    func useEditorFont(sized size: Double) {
        settings.update { $0.editorFont.size = size }
    }

    private func adopt(_ settings: DeviceSettings) {
        theme = settings.theme
        accent = settings.accent
        editorFont = settings.editorFont
    }
}
