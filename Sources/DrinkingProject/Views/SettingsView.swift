import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject private var store: SettingsStore
    @State private var launchAgentStatus = LaunchAgentService.status()
    @State private var launchAgentMessage = ""
    @State private var isUpdatingLaunchAgent = false

    init(controller: AppController) {
        self.controller = controller
        store = controller.settingsStore
    }

    var body: some View {
        Form {
            Section("提醒") {
                Toggle("开启提醒", isOn: $store.settings.remindersEnabled)
                Toggle(
                    "开机自动运行",
                    isOn: Binding(
                        get: { launchAgentStatus.isInstalled },
                        set: { setLaunchAtLogin($0) }
                    )
                )
                .disabled(isUpdatingLaunchAgent)

                Text(launchAgentStatus.summary)
                    .font(.caption)
                    .foregroundStyle(launchAgentStatus.isInstalled ? Color.secondary : Color.orange)
                Text("LaunchAgent: \(launchAgentStatus.plistPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !launchAgentMessage.isEmpty {
                    Text(launchAgentMessage)
                        .font(.caption)
                        .foregroundStyle(launchAgentMessage.contains("失败") ? Color.red : Color.secondary)
                }
                Button("刷新开机启动状态") {
                    refreshLaunchAgentStatus()
                }
            }

            Section("播放") {
                Picker("播放方式", selection: $store.settings.playbackMode) {
                    ForEach(VideoPlaybackMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Slider(value: $store.settings.reminderVolume, in: 0...100, step: 1) {
                    Text("音量")
                }
                Text("提醒音量：\(Int(store.settings.reminderVolume))%")
                    .foregroundStyle(.secondary)
            }

            Section("今天") {
                Text(store.isPausedToday ? "今日已暂停" : "今日提醒运行中")
                HStack {
                    Button("今日暂停") {
                        controller.pauseToday()
                    }
                    Button("恢复今日提醒") {
                        controller.resumeToday()
                    }
                }
            }

            Section("轻松测试") {
                Toggle("轻松测试模式", isOn: $store.settings.playgroundModeEnabled)
                Text("只影响手动测试提醒，不影响正式定时提醒。开启后手动测试会使用约 3 秒等待、1 次确认、1 秒冷却。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("快速测试提醒窗口") {
                    controller.showTestReminder()
                }
            }

            Section {
                Button("恢复默认设置") {
                    store.restoreDefaults()
                    refreshLaunchAgentStatus()
                }
            }
        }
        .padding(24)
        .navigationTitle("设置")
        .onAppear {
            refreshLaunchAgentStatus()
        }
    }

    private func refreshLaunchAgentStatus() {
        launchAgentStatus = LaunchAgentService.status()
        store.settings.launchAtLoginEnabled = launchAgentStatus.isInstalled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        isUpdatingLaunchAgent = true
        let result = LaunchAgentService.setEnabled(enabled, projectRoot: controller.paths.projectRoot)
        launchAgentStatus = result.status
        launchAgentMessage = result.message
        store.settings.launchAtLoginEnabled = result.status.isInstalled
        isUpdatingLaunchAgent = false
    }
}
