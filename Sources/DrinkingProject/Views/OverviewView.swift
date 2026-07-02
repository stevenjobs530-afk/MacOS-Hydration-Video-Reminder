import SwiftUI

struct OverviewView: View {
    @ObservedObject var controller: AppController
    @ObservedObject private var scanner: VideoScanner
    @ObservedObject private var historyStore: HistoryStore
    @ObservedObject private var settingsStore: SettingsStore

    init(controller: AppController) {
        self.controller = controller
        scanner = controller.videoScanner
        historyStore = controller.historyStore
        settingsStore = controller.settingsStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("总览")
                .font(.largeTitle.weight(.semibold))

            Text(dailyStatusMessage)
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                metricCard(title: "今日提醒", value: "\(historyStore.history.todayReminderCount)")
                metricCard(title: "今日完成", value: "\(historyStore.history.todayCompletedCount)")
                metricCard(title: "完成率", value: completionRateText)
                metricCard(title: "可播放视频", value: "\(scanner.lastScanResult.playableVideos.count)")
            }

            GroupBox("今日小结") {
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
                        Text("上次提醒")
                            .foregroundStyle(.secondary)
                        Text(dateText(historyStore.history.lastReminderAt))
                    }
                    GridRow {
                        Text("最近完成")
                            .foregroundStyle(.secondary)
                        Text(dateText(historyStore.history.lastConfirmationCompletedAt))
                    }
                }
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button(settingsStore.settings.playgroundModeEnabled ? "轻松测试提醒" : "测试提醒") {
                    controller.showTestReminder()
                }
                Button("扫描视频") {
                    controller.scanVideos()
                }
                if settingsStore.isPausedToday {
                    Button("恢复今日提醒") {
                        controller.resumeToday()
                    }
                } else {
                    Button("今日暂停") {
                        controller.pauseToday()
                    }
                }
            }

            if settingsStore.settings.playgroundModeEnabled {
                Text("轻松测试模式已开启：手动测试会等待约 3 秒、确认 1 次；正式定时提醒仍按真实规则。可在「设置」中关闭。")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            if scanner.lastScanResult.playableVideos.isEmpty {
                Text("未找到可播放视频。把 mp4/mov/m4v/avi/mkv/webm 放到 `视频/视频素材/` 里，或在「视频库」添加视频。")
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
        formatter.calendar = UKDayClock.calendar
        formatter.timeZone = UKDayClock.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var completionRateText: String {
        let reminders = historyStore.history.todayReminderCount
        guard reminders > 0 else { return "今天还没开始" }
        let rate = Double(historyStore.history.todayCompletedCount) / Double(reminders)
        return "\(Int((rate * 100).rounded()))%"
    }

    private var dailyStatusMessage: String {
        let completed = historyStore.history.todayCompletedCount
        if completed > 0 {
            return "今天已经喝水 \(completed) 次，继续保持。"
        }
        if scanner.lastScanResult.playableVideos.isEmpty {
            return "先放几段喜欢的视频进来，提醒会更有意思。"
        }
        if historyStore.history.todayReminderCount == 0 {
            return "今天还没有完成提醒，先来一次测试吧。"
        }
        return "可播放视频已经准备好了。"
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
