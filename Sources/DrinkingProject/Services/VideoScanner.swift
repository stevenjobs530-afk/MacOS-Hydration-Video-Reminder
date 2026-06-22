import AVFoundation
import Combine
import Foundation

@MainActor
final class VideoScanner: ObservableObject {
    @Published private(set) var lastScanResult = VideoScanResult.empty

    private let paths: AppPaths
    private let libraryStore: VideoLibraryStore
    private var shuffledQueue: [URL] = []
    private var lastPlayableSignature: [String] = []
    private let allowedExtensions = Set(["mp4", "mov", "m4v"])

    init(paths: AppPaths, libraryStore: VideoLibraryStore) {
        self.paths = paths
        self.libraryStore = libraryStore
    }

    func nextPlayableVideoURL() -> URL? {
        var result = scanVideos()
        let signature = result.playableVideos.map(\.path)

        if signature != lastPlayableSignature || shuffledQueue.isEmpty {
            shuffledQueue = result.playableVideos.shuffled()
            lastPlayableSignature = signature
        }

        let selected = shuffledQueue.popLast()
        result.selectedVideo = selected
        lastScanResult = result
        logScanResult(result)
        return selected
    }

    @discardableResult
    func scanVideos() -> VideoScanResult {
        var seenPaths = Set<String>()
        var candidates: [URL] = []
        var unavailableReferences: [UnavailableVideoReference] = []

        appendFiles(from: paths.videoMaterialDirectory, to: &candidates, seenPaths: &seenPaths)
        appendFiles(from: paths.videoDirectory, to: &candidates, seenPaths: &seenPaths)

        for item in libraryStore.items where item.isEnabled {
            switch item.kind {
            case .file:
                if !appendReferenceFile(item, to: &candidates, seenPaths: &seenPaths) {
                    unavailableReferences.append(unavailableReference(for: item))
                }
            case .folder:
                if !appendFiles(from: item.url, to: &candidates, seenPaths: &seenPaths) {
                    unavailableReferences.append(unavailableReference(for: item))
                }
            }
        }

        candidates.sort {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        let playableVideos = candidates.filter(isPlayable)
        let playablePaths = Set(playableVideos.map(\.path))
        let notPlayableVideos = candidates.filter { !playablePaths.contains($0.path) }
        let result = VideoScanResult(
            candidates: candidates,
            playableVideos: playableVideos,
            notPlayableVideos: notPlayableVideos,
            unavailableReferences: unavailableReferences,
            selectedVideo: nil
        )
        lastScanResult = result
        logScanResult(result)
        return result
    }

    @discardableResult
    private func appendFiles(from directory: URL, to candidates: inout [URL], seenPaths: inout Set<String>) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        for file in files {
            appendFile(file, to: &candidates, seenPaths: &seenPaths)
        }
        return true
    }

    @discardableResult
    private func appendFile(_ url: URL, to candidates: inout [URL], seenPaths: inout Set<String>) -> Bool {
        guard
            !url.lastPathComponent.hasPrefix("._"),
            allowedExtensions.contains(url.pathExtension.lowercased()),
            ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false),
            !seenPaths.contains(url.path)
        else {
            return false
        }
        candidates.append(url)
        seenPaths.insert(url.path)
        return true
    }

    private func appendReferenceFile(_ item: VideoItem, to candidates: inout [URL], seenPaths: inout Set<String>) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: item.url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        guard
            !item.url.lastPathComponent.hasPrefix("._"),
            allowedExtensions.contains(item.url.pathExtension.lowercased()),
            ((try? item.url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false)
        else {
            return false
        }
        if seenPaths.contains(item.url.path) {
            return true
        }
        candidates.append(item.url)
        seenPaths.insert(item.url.path)
        return true
    }

    private func unavailableReference(for item: VideoItem) -> UnavailableVideoReference {
        UnavailableVideoReference(
            id: item.id,
            displayName: item.displayName,
            path: item.url.path,
            kind: item.kind,
            reason: unavailableReason(for: item)
        )
    }

    private func unavailableReason(for item: VideoItem) -> String {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: item.url.path, isDirectory: &isDirectory)
        if !exists {
            if item.url.path.hasPrefix("/Volumes/") {
                return "位置不可用，外接硬盘可能未连接"
            }
            return "找不到文件或文件夹"
        }
        if item.kind == .folder, !isDirectory.boolValue {
            return "保存的是文件夹引用，但当前位置不是文件夹"
        }
        if item.kind == .file, isDirectory.boolValue {
            return "保存的是文件引用，但当前位置是文件夹"
        }
        if item.kind == .file, !allowedExtensions.contains(item.url.pathExtension.lowercased()) {
            return "格式不支持，仅支持 mp4、mov、m4v"
        }
        return "无法读取，请检查权限"
    }

    private func isPlayable(_ url: URL) -> Bool {
        AVURLAsset(url: url).isPlayable
    }

    private func logScanResult(_ result: VideoScanResult) {
        let notPlayableNames = result.notPlayableVideos
            .map(\.lastPathComponent)
            .joined(separator: ",")
        let unavailableNames = result.unavailableReferences
            .map(\.displayName)
            .joined(separator: ",")
        let selectedName = result.selectedVideo?.lastPathComponent ?? "none"
        print(
            "[DrinkingProject] video_scan candidate_count=\(result.candidates.count) " +
                "playable_count=\(result.playableVideos.count) " +
                "selected_video=\(selectedName) " +
                "not_playable_files=\(notPlayableNames.isEmpty ? "none" : notPlayableNames) " +
                "unavailable_references=\(unavailableNames.isEmpty ? "none" : unavailableNames)"
        )
    }
}
