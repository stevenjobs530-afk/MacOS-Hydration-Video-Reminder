import SwiftUI

struct OverviewView: View {
    @ObservedObject var controller: AppController
    @ObservedObject private var scanner: VideoScanner
    @ObservedObject private var historyStore: HistoryStore

    init(controller: AppController) {
        self.controller = controller
        scanner = controller.videoScanner
        historyStore = controller.historyStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Overview")
                .font(.largeTitle.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow {
                    Text("Status")
                        .foregroundStyle(.secondary)
                    Text(controller.currentStatusText)
                }
                GridRow {
                    Text("Next reminder")
                        .foregroundStyle(.secondary)
                    Text(controller.nextReminderText.replacingOccurrences(of: "下次提醒：", with: ""))
                }
                GridRow {
                    Text("Playable videos")
                        .foregroundStyle(.secondary)
                    Text("\(scanner.lastScanResult.playableVideos.count)")
                }
                GridRow {
                    Text("Today reminders")
                        .foregroundStyle(.secondary)
                    Text("\(historyStore.history.todayReminderCount)")
                }
                GridRow {
                    Text("Last completed")
                        .foregroundStyle(.secondary)
                    Text(dateText(historyStore.history.lastConfirmationCompletedAt))
                }
            }
            .font(.system(size: 14))

            HStack {
                Button("Test Reminder") {
                    controller.showTestReminder()
                }
                Button("Scan Videos") {
                    controller.scanVideos()
                }
                Button("Pause Today") {
                    controller.pauseToday()
                }
                Button("Resume Today") {
                    controller.resumeToday()
                }
            }

            Text("Local videos stay on this Mac. The GitHub project keeps only placeholders and folder instructions.")
                .foregroundStyle(.secondary)
                .font(.callout)

            Spacer()
        }
        .padding(28)
        .onAppear {
            controller.scanVideos()
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "None yet" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
