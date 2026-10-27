import EventKit
import SwiftUI
import AujourCore

struct TemplateListsRow: View {
    let journal: Journal
    let placeholder: DataPlaceholder

    @Environment(\.scenePhase) private var scenePhase
    @State private var summary = ""

    var body: some View {
        Section {
            NavigationLink {
                Form {
                    TemplateListsSection(journal: journal, placeholder: placeholder)
                }
                .settingsPage(titled: placeholder.templateListsTitle)
            } label: {
                LabeledContent(placeholder.templateListsTitle, value: summary)
            }
            .accessibilityIdentifier("openTemplateLists")
        }
        .settingsRows()
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        switch await journal.templateLists(for: placeholder) {
        case .needsAccess: summary = "Allow access"
        case .denied: summary = "Access off"
        case .available(let lists):
            let excluded = journal.deviceSettings.settings.excludedLists(for: placeholder)
            let included = lists.filter { !excluded.contains($0.id) }.count
            summary = lists.isEmpty ? "None available" : "\(included) of \(lists.count)"
        }
    }
}

private extension DataPlaceholder {
    var templateListsTitle: String {
        switch self {
        case .events: "Calendars"
        case .reminders: "Reminder lists"
        }
    }
}
