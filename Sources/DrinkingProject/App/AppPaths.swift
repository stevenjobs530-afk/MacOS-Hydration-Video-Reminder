import Foundation

struct AppPaths {
    let projectRoot: URL
    let appSupportDirectory: URL
    let webResourceDirectory: URL

    var videoDirectory: URL {
        projectRoot.appendingPathComponent("视频", isDirectory: true)
    }

    var videoMaterialDirectory: URL {
        videoDirectory.appendingPathComponent("视频素材", isDirectory: true)
    }

    init(arguments: [String]) {
        projectRoot = Self.resolveProjectRoot(arguments: arguments)

        if let explicitSupportPath = Self.value(after: "--app-support-dir", in: arguments) {
            appSupportDirectory = URL(fileURLWithPath: explicitSupportPath, isDirectory: true)
                .standardizedFileURL
        } else if arguments.contains("--self-test-persistence") {
            appSupportDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("DrinkingProjectSelfTest-\(UUID().uuidString)", isDirectory: true)
                .standardizedFileURL
        } else {
            let appSupportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? FileManager.default.homeDirectoryForCurrentUser
            appSupportDirectory = appSupportRoot
                .appendingPathComponent("Drinking Project", isDirectory: true)
                .standardizedFileURL
        }
        try? FileManager.default.createDirectory(
            at: appSupportDirectory,
            withIntermediateDirectories: true
        )

        if let explicitWebPath = Self.value(after: "--web-resources", in: arguments) {
            webResourceDirectory = URL(fileURLWithPath: explicitWebPath, isDirectory: true)
                .standardizedFileURL
        } else {
            webResourceDirectory = Self.resolveWebResourceDirectory(projectRoot: projectRoot)
        }
    }

    private static func resolveProjectRoot(arguments: [String]) -> URL {
        if let explicitRoot = value(after: "--project-dir", in: arguments) {
            return URL(fileURLWithPath: explicitRoot, isDirectory: true).standardizedFileURL
        }

        let currentDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).standardizedFileURL
        let bundleContainer = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .standardizedFileURL

        let candidates = [
            currentDirectory,
            bundleContainer,
            bundleContainer.deletingLastPathComponent(),
            bundleContainer.deletingLastPathComponent().deletingLastPathComponent()
        ]

        for candidate in candidates {
            if let root = nearestProjectRoot(from: candidate) {
                return root
            }
        }
        return currentDirectory
    }

    private static func nearestProjectRoot(from startURL: URL) -> URL? {
        var current = startURL.standardizedFileURL
        let fileManager = FileManager.default

        while true {
            let materialDirectory = current
                .appendingPathComponent("视频", isDirectory: true)
                .appendingPathComponent("视频素材", isDirectory: true)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: materialDirectory.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return current
            }

            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func resolveWebResourceDirectory(projectRoot: URL) -> URL {
        var candidates = [
            Bundle.main.resourceURL?
                .appendingPathComponent("WebResources", isDirectory: true)
                .appendingPathComponent("ReminderWeb", isDirectory: true),
            projectRoot
                .appendingPathComponent("Sources", isDirectory: true)
                .appendingPathComponent("DrinkingProject", isDirectory: true)
                .appendingPathComponent("WebResources", isDirectory: true)
                .appendingPathComponent("ReminderWeb", isDirectory: true),
            projectRoot
                .appendingPathComponent("WebResources", isDirectory: true)
                .appendingPathComponent("ReminderWeb", isDirectory: true),
            projectRoot
                .appendingPathComponent("Test ", isDirectory: true)
                .appendingPathComponent("ReminderWeb", isDirectory: true)
        ].compactMap { $0?.standardizedFileURL }

        #if SWIFT_PACKAGE
        if let packageResourceURL = Bundle.module.resourceURL?
                .appendingPathComponent("WebResources", isDirectory: true)
                .appendingPathComponent("ReminderWeb", isDirectory: true)
                .standardizedFileURL {
            candidates.insert(packageResourceURL, at: min(1, candidates.count))
        }
        #endif

        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
            ?? candidates.last
            ?? projectRoot
    }
}
