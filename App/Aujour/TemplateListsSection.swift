import EventKit
import SwiftUI
import AujourCore

struct TemplateListsSection: View {
    let journal: Journal
    let placeholder: DataPlaceholder

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var lists: DayItemLists?
    @State private var excluded: Set<String>
    @State private var requestingAccess = false

    init(journal: Journal, placeholder: DataPlaceholder) {
        self.journal = journal
        self.placeholder = placeholder
        _excluded = State(initialValue: journal.deviceSettings.settings.excludedLists(for: placeholder))
    }

    var body: some View {
        Section {
            switch lists {
            case nil:
                ProgressView()
            case .needsAccess:
                Button(placeholder == .events ? "Allow Calendar access" : "Allow Reminders access") {
                    requestingAccess = true
                    Task {
                        await journal.prepareTemplateLists(for: placeholder)
                        await refresh()
                        requestingAccess = false
                    }
                }
                .disabled(requestingAccess)
                .accessibilityIdentifier("allowTemplateListAccess")
            case .denied:
                Text(placeholder == .events ? "Calendar access is turned off." : "Reminders access is turned off.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .accessibilityIdentifier("templateListSystemSettings")
            case .available(let available) where available.isEmpty:
                Text(placeholder == .events ? "No calendars available." : "No reminder lists available.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("noTemplateLists")
            case .available(let available):
                ForEach(available) { list in
                    Toggle(isOn: inclusion(of: list)) {
                        VStack(alignment: .leading) {
                            Text(list.title)
                            Text(list.account).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("templateList-\(list.id)")
                }
            }
        } footer: {
            Text("Included in new entries. Existing entries stay as written.")
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
        lists = await journal.templateLists(for: placeholder)
    }

    private func inclusion(of list: DayItemList) -> Binding<Bool> {
        Binding {
            !excluded.contains(list.id)
        } set: { included in
            if included { excluded.remove(list.id) } else { excluded.insert(list.id) }
            journal.deviceSettings.update {
                $0.setIncluded(included, list: list.id, for: placeholder)
            }
        }
    }
}
