import SwiftUI

@main
struct DrinkingProjectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let controller = AppController.shared

    var body: some Scene {
        WindowGroup("Drinking Project") {
            ContentView(controller: controller)
                .frame(minWidth: 920, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView(controller: controller)
                .frame(width: 520)
        }
    }
}
