import Darwin
import Foundation

struct LaunchAgentStatus: Equatable {
    var isInstalled: Bool
    var isLoaded: Bool
    var plistPath: String

    var summary: String {
        if isInstalled && isLoaded {
            return "已开启，LaunchAgent 已安装并加载"
        }
        if isInstalled {
            return "已安装，将在下次登录时自动启动"
        }
        return "未开启"
    }
}

struct LaunchAgentActionResult: Equatable {
    var succeeded: Bool
    var status: LaunchAgentStatus
    var message: String
}

enum LaunchAgentService {
    static let label = "com.local.drinkingproject"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func status() -> LaunchAgentStatus {
        LaunchAgentStatus(
            isInstalled: FileManager.default.fileExists(atPath: plistURL.path),
            isLoaded: launchctlSucceeds(["print", serviceTarget]),
            plistPath: plistURL.path
        )
    }

    static func setEnabled(_ enabled: Bool, projectRoot: URL) -> LaunchAgentActionResult {
        enabled ? install(projectRoot: projectRoot) : uninstall()
    }

    static func install(projectRoot: URL) -> LaunchAgentActionResult {
        do {
            guard let executableURL = Bundle.main.executableURL else {
                throw LaunchAgentError.missingExecutable
            }
            try writePlist(executableURL: executableURL, projectRoot: projectRoot)
            _ = try runLaunchctl(["bootout", guiTarget, plistURL.path], allowFailure: true)
            _ = try runLaunchctl(["bootstrap", guiTarget, plistURL.path])
            _ = try runLaunchctl(["enable", serviceTarget])
            _ = try runLaunchctl(["kickstart", "-k", serviceTarget], allowFailure: true)

            let currentStatus = status()
            return LaunchAgentActionResult(
                succeeded: currentStatus.isInstalled,
                status: currentStatus,
                message: currentStatus.isLoaded
                    ? "开机自动运行已开启。当前 App 已在运行，LaunchAgent 也已加载。"
                    : "开机自动运行已开启。下次登录时会自动启动。"
            )
        } catch {
            return LaunchAgentActionResult(
                succeeded: false,
                status: status(),
                message: "开机自动运行开启失败：\(error.localizedDescription)"
            )
        }
    }

    static func uninstall() -> LaunchAgentActionResult {
        do {
            _ = try runLaunchctl(["bootout", guiTarget, plistURL.path], allowFailure: true)
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
            return LaunchAgentActionResult(
                succeeded: true,
                status: status(),
                message: "开机自动运行已关闭；这不会退出当前正在运行的 App。"
            )
        } catch {
            return LaunchAgentActionResult(
                succeeded: false,
                status: status(),
                message: "开机自动运行关闭失败：\(error.localizedDescription)"
            )
        }
    }

    private static var guiTarget: String {
        "gui/\(getuid())"
    }

    private static var serviceTarget: String {
        "\(guiTarget)/\(label)"
    }

    private static func writePlist(executableURL: URL, projectRoot: URL) throws {
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                executableURL.path,
                "--project-dir",
                projectRoot.path,
                "--resume-on-launch"
            ],
            "WorkingDirectory": projectRoot.path,
            "RunAtLoad": true,
            "StandardOutPath": "/tmp/drinkingproject.out.log",
            "StandardErrorPath": "/tmp/drinkingproject.err.log"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: [.atomic])
    }

    private static func launchctlSucceeds(_ arguments: [String]) -> Bool {
        (try? runLaunchctl(arguments, allowFailure: false)) != nil
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String], allowFailure: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 && !allowFailure {
            throw LaunchAgentError.commandFailed(
                command: "launchctl \(arguments.joined(separator: " "))",
                output: (output + errorOutput).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return output + errorOutput
    }
}

private enum LaunchAgentError: LocalizedError {
    case missingExecutable
    case commandFailed(command: String, output: String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "找不到当前 App 的可执行文件"
        case let .commandFailed(command, output):
            if output.isEmpty {
                return "\(command) 执行失败"
            }
            return "\(command) 执行失败：\(output)"
        }
    }
}
