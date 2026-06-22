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
            Text("总览")
                .font(.largeTitle.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow {
                    Text("当前状态")
                        .foregroundStyle(.secondary)
                    Text(controller.currentStatusText)
                }
                GridRow {
                    Text("下次提醒")
                        .foregroundStyle(.secondary)
                    Text(controller.nextReminderText.replacingOccurrences(of: "下次提醒：", with: ""))
                }
                GridRow {
                    Text("可播放视频")
                        .foregroundStyle(.secondary)
                    Text("\(scanner.lastScanResult.playableVideos.count)")
                }
                GridRow {
                    Text("今日提醒次数")
                        .foregroundStyle(.secondary)
                    Text("\(historyStore.history.todayReminderCount)")
                }
                GridRow {
                    Text("上次完成")
                        .foregroundStyle(.secondary)
                    Text(dateText(historyStore.history.lastConfirmationCompletedAt))
                }
            }
            .font(.system(size: 14))

            HStack {
                Button("测试提醒") {
                    controller.showTestReminder()
                }
                Button("扫描视频") {
                    controller.scanVideos()
                }
                Button("今日暂停") {
                    controller.pauseToday()
                }
                Button("恢复今日提醒") {
                    controller.resumeToday()
                }
            }

            if scanner.lastScanResult.playableVideos.isEmpty {
                Text("未找到可播放视频。请检查 `视频/视频素材/` 或视频库里的外接硬盘引用。")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            Text("本地视频只留在这台 Mac；GitHub 仓库只保留占位文件和目录说明。")
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
        guard let date else { return "暂无" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
