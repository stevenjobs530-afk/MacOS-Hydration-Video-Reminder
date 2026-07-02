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
    /// Default label kept for backward compatibility / callers that don't pass a variant.
    static let label = AppVariant.standard.launchAgentLabel

    static func plistURL(for variant: AppVariant) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(variant.launchAgentLabel).plist")
    }

    static func status(variant: AppVariant = .standard) -> LaunchAgentStatus {
        let plistURL = plistURL(for: variant)
        return LaunchAgentStatus(
            isInstalled: FileManager.default.fileExists(atPath: plistURL.path),
            isLoaded: launchctlSucceeds(["print", serviceTarget(for: variant)]),
            plistPath: plistURL.path
        )
    }

    static func setEnabled(_ enabled: Bool, projectRoot: URL, variant: AppVariant = .standard) -> LaunchAgentActionResult {
        enabled ? install(projectRoot: projectRoot, variant: variant) : uninstall(variant: variant)
    }

    static func install(projectRoot: URL, variant: AppVariant = .standard) -> LaunchAgentActionResult {
        let plistURL = plistURL(for: variant)
        do {
            guard let executableURL = Bundle.main.executableURL else {
                throw LaunchAgentError.missingExecutable
            }
            try writePlist(executableURL: executableURL, projectRoot: projectRoot, variant: variant)
            _ = try runLaunchctl(["bootout", guiTarget, plistURL.path], allowFailure: true)
            _ = try runLaunchctl(["bootstrap", guiTarget, plistURL.path])
            _ = try runLaunchctl(["enable", serviceTarget(for: variant)])
            _ = try runLaunchctl(["kickstart", "-k", serviceTarget(for: variant)], allowFailure: true)

            let currentStatus = status(variant: variant)
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

    static func uninstall(variant: AppVariant = .standard) -> LaunchAgentActionResult {
        let plistURL = plistURL(for: variant)
        do {
            _ = try runLaunchctl(["bootout", guiTarget, plistURL.path], allowFailure: true)
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
            return LaunchAgentActionResult(
                succeeded: true,
                status: status(variant: variant),
                message: "开机自动运行已关闭；这不会退出当前正在运行的 App。"
            )
        } catch {
            return LaunchAgentActionResult(
                succeeded: false,
                status: status(variant: variant),
                message: "开机自动运行关闭失败：\(error.localizedDescription)"
            )
        }
    }

    private static var guiTarget: String {
        "gui/\(getuid())"
    }

    private static func serviceTarget(for variant: AppVariant) -> String {
        "\(guiTarget)/\(variant.launchAgentLabel)"
    }

    private static func writePlist(executableURL: URL, projectRoot: URL, variant: AppVariant) throws {
        let plistURL = plistURL(for: variant)
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var programArguments = [
            executableURL.path,
            "--project-dir",
            projectRoot.path,
            "--resume-on-launch"
        ]
        if !variant.isDefault {
            programArguments.append(contentsOf: ["--variant", variant.id])
        }
        let logSuffix = variant.isDefault ? "" : ".\(variant.id)"

        let plist: [String: Any] = [
            "Label": variant.launchAgentLabel,
            "ProgramArguments": programArguments,
            "WorkingDirectory": projectRoot.path,
            "RunAtLoad": true,
            "StandardOutPath": "/tmp/drinkingproject\(logSuffix).out.log",
            "StandardErrorPath": "/tmp/drinkingproject\(logSuffix).err.log"
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
