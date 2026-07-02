import AVFoundation
import Combine
import Foundation

private final class PlayabilityResult: @unchecked Sendable {
    var value = false
}

@MainActor
final class VideoScanner: ObservableObject {
    @Published private(set) var lastScanResult = VideoScanResult.empty

    private let paths: AppPaths
    private let libraryStore: VideoLibraryStore
    private var shuffledQueue: [URL] = []
    private var lastPlayableSignature: [String] = []
    private let allowedExtensions = VideoLibraryStore.supportedVideoExtensions

    /// Cached playability keyed by file path. Each entry remembers the modification
    /// date it was computed for, so a changed file is re-validated automatically.
    private struct PlayabilityCacheEntry {
        let modified: Date
        let isPlayable: Bool
    }
    private var playabilityCache: [String: PlayabilityCacheEntry] = [:]
    private var validationTask: Task<Void, Never>?
    /// Bumped whenever a new scan publishes a result. A background validation pass only
    /// republishes if its generation still matches, so a late-finishing task can never
    /// overwrite a newer scan with a stale snapshot.
    private var scanGeneration = 0

    init(paths: AppPaths, libraryStore: VideoLibraryStore) {
        self.paths = paths
        self.libraryStore = libraryStore
    }

    func nextPlayableVideoURL() -> URL? {
        // The reminder must show a genuinely playable video, so validate synchronously
        // here. Cached files resolve instantly; only never-seen files pay the load cost.
        // This is an authoritative result: supersede any in-flight background validation.
        scanGeneration += 1
        validationTask?.cancel()
        let (candidates, unavailableReferences) = scanCandidates()
        validatePlayabilitySynchronously(candidates)
        var result = makeResult(candidates: candidates, unavailableReferences: unavailableReferences)
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
        // Build the candidate list synchronously (fast file-system checks) and classify
        // playability from the cache without ever blocking the main thread. Unknown files
        // are validated in the background and the result is republished when ready.
        scanGeneration += 1
        let (candidates, unavailableReferences) = scanCandidates()
        let result = makeResult(candidates: candidates, unavailableReferences: unavailableReferences)
        lastScanResult = result
        logScanResult(result)
        validatePlayabilityInBackground(candidates: candidates, unavailableReferences: unavailableReferences)
        return result
    }

    /// Fully-validated synchronous scan for diagnostics, where an accurate (settled) result
    /// matters more than non-blocking behavior. Runs only on explicit user action (the
    /// "copy diagnostics" button), so the brief validation cost is acceptable.
    @discardableResult
    func diagnosticScan() -> VideoScanResult {
        scanGeneration += 1
        validationTask?.cancel()
        let (candidates, unavailableReferences) = scanCandidates()
        validatePlayabilitySynchronously(candidates)
        let result = makeResult(candidates: candidates, unavailableReferences: unavailableReferences)
        lastScanResult = result
        logScanResult(result)
        return result
    }

    /// Fast, synchronous: collect candidate files and unavailable references. No playability work.
    private func scanCandidates() -> (candidates: [URL], unavailableReferences: [UnavailableVideoReference]) {
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

        return (candidates, unavailableReferences)
    }

    /// Build a scan result from the current cache. Files whose playability is not yet known
    /// are treated as playable optimistically (they are usually fine); a background pass
    /// corrects any that turn out to be unplayable.
    private func makeResult(candidates: [URL], unavailableReferences: [UnavailableVideoReference]) -> VideoScanResult {
        let playableVideos = candidates.filter { cachedPlayability(for: $0) != false }
        let playablePaths = Set(playableVideos.map(\.path))
        let notPlayableVideos = candidates.filter { !playablePaths.contains($0.path) }
        return VideoScanResult(
            candidates: candidates,
            playableVideos: playableVideos,
            notPlayableVideos: notPlayableVideos,
            unavailableReferences: unavailableReferences,
            selectedVideo: nil
        )
    }

    /// Returns the cached playability if a fresh (matching modification date) entry exists.
    private func cachedPlayability(for url: URL) -> Bool? {
        guard let entry = playabilityCache[url.path] else { return nil }
        guard entry.modified == modificationDate(for: url) else { return nil }
        return entry.isPlayable
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// Validate any not-yet-known candidates off the main thread, then update the cache and
    /// republish the result. Cancels a previous in-flight pass so rapid scans don't pile up.
    private func validatePlayabilityInBackground(candidates: [URL], unavailableReferences: [UnavailableVideoReference]) {
        // Always supersede a previous pass first, even when there is nothing new to validate,
        // so an older task can't finish later and publish a stale snapshot.
        validationTask?.cancel()
        validationTask = nil

        let unknown = candidates.filter { cachedPlayability(for: $0) == nil }
        guard !unknown.isEmpty else { return }

        let generation = scanGeneration
        let snapshot = candidates
        validationTask = Task.detached(priority: .utility) { [weak self] in
            var resolved: [(path: String, modified: Date, isPlayable: Bool)] = []
            for url in unknown {
                if Task.isCancelled { return }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let isPlayable = await VideoScanner.loadIsPlayable(url)
                resolved.append((url.path, modified, isPlayable))
            }
            let finalResolved = resolved
            await MainActor.run { [weak self, finalResolved] in
                guard let self, !Task.isCancelled else { return }
                // The validations themselves stay valid (cache is keyed by path + mtime), so
                // always store them; but only republish if this is still the latest scan.
                for entry in finalResolved {
                    self.playabilityCache[entry.path] = PlayabilityCacheEntry(modified: entry.modified, isPlayable: entry.isPlayable)
                }
                guard self.scanGeneration == generation else { return }
                let refreshed = self.makeResult(candidates: snapshot, unavailableReferences: unavailableReferences)
                self.lastScanResult = refreshed
                self.logScanResult(refreshed)
            }
        }
    }

    /// Validate uncached/stale candidates synchronously and store the results. Used only on the
    /// reminder path, where a correct immediate answer matters more than non-blocking behavior.
    private func validatePlayabilitySynchronously(_ urls: [URL]) {
        for url in urls where cachedPlayability(for: url) == nil {
            let modified = modificationDate(for: url)
            let isPlayable = blockingIsPlayable(url)
            playabilityCache[url.path] = PlayabilityCacheEntry(modified: modified, isPlayable: isPlayable)
        }
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
            return "格式不支持，仅支持 mp4、mov、m4v、avi、mkv、webm"
        }
        return "无法读取，请检查权限"
    }

    /// Synchronous playability check used only on the reminder path. Runs the modern async
    /// AVAsset property on a detached task and waits, with a timeout safety net.
    private func blockingIsPlayable(_ url: URL) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let result = PlayabilityResult()

        Task.detached(priority: .utility) {
            result.value = await VideoScanner.loadIsPlayable(url)
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + 5) == .success else {
            return false
        }
        return result.value
    }

    /// Loads the asset's playability off the main actor.
    private static func loadIsPlayable(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        return (try? await asset.load(.isPlayable)) ?? false
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
