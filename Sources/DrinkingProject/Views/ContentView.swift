import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: AppController
    @State private var selection: AppSection = .overview

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Drinking Project")
        } detail: {
            switch selection {
            case .overview:
                OverviewView(controller: controller)
            case .rules:
                ReminderRulesView(store: controller.reminderStore)
            case .videos:
                VideoLibraryView(
                    store: controller.videoLibraryStore,
                    scanner: controller.videoScanner
                )
            case .settings:
                SettingsView(controller: controller)
            }
        }
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case rules
    case videos
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .rules: return "Reminder Rules"
        case .videos: return "Video Library"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "gauge"
        case .rules: return "clock"
        case .videos: return "film"
        case .settings: return "gearshape"
        }
    }
}
