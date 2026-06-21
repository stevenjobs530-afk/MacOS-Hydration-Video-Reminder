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

        appendFiles(from: paths.videoMaterialDirectory, to: &candidates, seenPaths: &seenPaths)
        appendFiles(from: paths.videoDirectory, to: &candidates, seenPaths: &seenPaths)

        for item in libraryStore.items where item.isEnabled {
            switch item.kind {
            case .file:
                appendFile(item.url, to: &candidates, seenPaths: &seenPaths)
            case .folder:
                appendFiles(from: item.url, to: &candidates, seenPaths: &seenPaths)
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
            selectedVideo: nil
        )
        lastScanResult = result
        logScanResult(result)
        return result
    }

    private func appendFiles(from directory: URL, to candidates: inout [URL], seenPaths: inout Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for file in files {
            appendFile(file, to: &candidates, seenPaths: &seenPaths)
        }
    }

    private func appendFile(_ url: URL, to candidates: inout [URL], seenPaths: inout Set<String>) {
        guard
            !url.lastPathComponent.hasPrefix("._"),
            allowedExtensions.contains(url.pathExtension.lowercased()),
            ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false),
            !seenPaths.contains(url.path)
        else {
            return
        }
        candidates.append(url)
        seenPaths.insert(url.path)
    }

    private func isPlayable(_ url: URL) -> Bool {
        AVURLAsset(url: url).isPlayable
    }

    private func logScanResult(_ result: VideoScanResult) {
        let notPlayableNames = result.notPlayableVideos
            .map(\.lastPathComponent)
            .joined(separator: ",")
        let selectedName = result.selectedVideo?.lastPathComponent ?? "none"
        print(
            "[DrinkingProject] video_scan candidate_count=\(result.candidates.count) " +
                "playable_count=\(result.playableVideos.count) " +
                "selected_video=\(selectedName) " +
                "not_playable_files=\(notPlayableNames.isEmpty ? "none" : notPlayableNames)"
        )
    }
}
