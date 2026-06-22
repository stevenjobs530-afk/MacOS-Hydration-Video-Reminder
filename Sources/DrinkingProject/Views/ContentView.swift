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
                ReminderRulesView(controller: controller)
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
        case .overview: return "总览"
        case .rules: return "提醒规则"
        case .videos: return "视频库"
        case .settings: return "设置"
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
