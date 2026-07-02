import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject private var store: SettingsStore
    @State private var launchAgentStatus = LaunchAgentService.status()
    @State private var launchAgentMessage = ""
    @State private var isUpdatingLaunchAgent = false
    @State private var mediaTestSummary = ""
    @State private var isTestingMedia = false

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
                    Text("提醒音量")
                }
                Text("提醒音量：\(Int(store.settings.reminderVolume))%（提示音和弹窗视频）")
                    .foregroundStyle(.secondary)
            }

            Section("提醒显示") {
                Picker("提醒样式", selection: $store.settings.reminderWindowStyle) {
                    ForEach(ReminderWindowStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Picker("提醒覆盖范围", selection: $store.settings.reminderScreenMode) {
                    ForEach(ReminderScreenMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text("全屏视频提醒：按上方覆盖范围显示；外接显示器同步画面时保持静音。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Mac 弹窗提醒：不方便看视频时使用。只在主屏幕中央弹出一个小窗口，不播放视频；等待、确认次数等强制流程保持不变，下次提醒生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("权限") {
                Text(accessibilityStatusText)
                    .font(.caption)
                    .foregroundStyle(BackgroundMediaControl.hasAccessibilityPermission ? Color.secondary : Color.orange)
                Text("辅助功能权限用于在提醒弹出前控制网易云音乐、微信读书等特殊播放器。不授权也能正常喝水提醒，但相关播放器无法强制暂停。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("打开系统设置 · 辅助功能") {
                    BackgroundMediaControl.openAccessibilitySettings()
                }
                Button("在 Finder 显示本 App") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
            }

            Section("后台媒体尽力暂停") {
                Text(BackgroundMediaControl.browserReadinessSummary())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("提醒出现前会尽力暂停浏览器标签页和常见播放器；如果 Chrome 或 Safari 没有可控标签页，提醒仍会正常播放声音。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("支持的浏览器：\(BackgroundMediaControl.supportedBrowserDisplayNames.joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("支持的播放器：\(BackgroundMediaControl.supportedPlayerDisplayNames.joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("浏览器自动化权限只影响是否能帮你暂停网页媒体，不再影响提醒视频和提示音。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(isTestingMedia ? "正在检查…" : "测试后台媒体暂停") {
                    runBackgroundMediaTest()
                }
                .disabled(isTestingMedia)
                Text("先播放 YouTube、Bilibili、Spotify、微信读书等，再点这个按钮。它只做一次尽力暂停测试，不会弹出提醒、不改规则、不写历史。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !mediaTestSummary.isEmpty {
                    Text(mediaTestSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
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

    private func runBackgroundMediaTest() {
        isTestingMedia = true
        mediaTestSummary = "正在测试后台媒体尽力暂停…"
        // Defer one runloop tick so the "正在测试…" state renders before the
        // (briefly blocking) AppleScript / accessibility work runs on the main thread.
        DispatchQueue.main.async {
            let report = BackgroundMediaControl.enforceBackgroundMediaPause()
            mediaTestSummary = report.summaryText
            isTestingMedia = false
        }
    }

    private var accessibilityStatusText: String {
        BackgroundMediaControl.hasAccessibilityPermission
            ? "辅助功能权限：已授权"
            : "辅助功能权限：未授权（特殊播放器无法强制暂停）"
    }

    private func refreshLaunchAgentStatus() {
        launchAgentStatus = LaunchAgentService.status(variant: controller.paths.variant)
        store.settings.launchAtLoginEnabled = launchAgentStatus.isInstalled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        isUpdatingLaunchAgent = true
        let result = LaunchAgentService.setEnabled(
            enabled,
            projectRoot: controller.paths.projectRoot,
            variant: controller.paths.variant
        )
        launchAgentStatus = result.status
        launchAgentMessage = result.message
        store.settings.launchAtLoginEnabled = result.status.isInstalled
        isUpdatingLaunchAgent = false
    }
}
