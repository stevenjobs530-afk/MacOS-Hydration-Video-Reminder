import Combine
import Foundation

@MainActor
final class VideoLibraryStore: ObservableObject {
    static let supportedVideoExtensions = Set(["mp4", "mov", "m4v", "avi", "mkv", "webm"])

    @Published var items: [VideoItem] {
        didSet { save() }
    }

    private let fileURL: URL

    init(paths: AppPaths) {
        fileURL = paths.appSupportDirectory.appendingPathComponent("video-library.json")
        items = JSONFileStore.load([VideoItem].self, from: fileURL, fallback: [])
        save()
    }

    func addReference(url: URL) {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        let isFolder = values?.isDirectory ?? false
        let item = VideoItem(
            id: UUID(),
            displayName: url.lastPathComponent,
            urlString: url.path,
            kind: isFolder ? .folder : .file,
            isEnabled: true,
            addedAt: fileDate(for: url) ?? Date(),
            lastSeenAt: nil
        )
        guard !items.contains(where: { $0.urlString == item.urlString }) else { return }
        items.append(item)
    }

    @discardableResult
    func importVideos(from sourceURLs: [URL], to materialDirectory: URL) -> [Result<VideoItem, Error>] {
        var results: [Result<VideoItem, Error>] = []
        do {
            try FileManager.default.createDirectory(at: materialDirectory, withIntermediateDirectories: true)
        } catch {
            return sourceURLs.map { _ in .failure(error) }
        }

        for sourceURL in sourceURLs {
            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                guard Self.isSupportedVideo(sourceURL) else {
                    throw VideoLibraryError.unsupportedFormat(sourceURL.pathExtension)
                }
                let destination = uniqueDestination(for: sourceURL.lastPathComponent, in: materialDirectory)
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                let item = upsertVideoFile(url: destination, displayName: destination.deletingPathExtension().lastPathComponent, addedAt: Date())
                results.append(.success(item))
            } catch {
                results.append(.failure(error))
            }
        }
        return results
    }

    func syncMaterialVideos(_ urls: [URL]) {
        var changed = false
        for url in urls where Self.isSupportedVideo(url) {
            if let index = items.firstIndex(where: { $0.urlString == url.path }) {
                items[index].lastSeenAt = Date()
                changed = true
            } else {
                let item = VideoItem(
                    id: UUID(),
                    displayName: url.deletingPathExtension().lastPathComponent,
                    urlString: url.path,
                    kind: .file,
                    isEnabled: true,
                    addedAt: fileDate(for: url) ?? Date(),
                    lastSeenAt: Date()
                )
                items.append(item)
                changed = true
            }
        }
        if changed {
            save()
        }
    }

    @discardableResult
    func upsertVideoFile(url: URL, displayName: String, addedAt: Date) -> VideoItem {
        if let index = items.firstIndex(where: { $0.urlString == url.path }) {
            items[index].displayName = displayName
            items[index].kind = .file
            items[index].isEnabled = true
            items[index].addedAt = addedAt
            items[index].lastSeenAt = Date()
            return items[index]
        }
        let item = VideoItem(
            id: UUID(),
            displayName: displayName,
            urlString: url.path,
            kind: .file,
            isEnabled: true,
            addedAt: addedAt,
            lastSeenAt: Date()
        )
        items.append(item)
        return item
    }

    func renameVideo(id: UUID, displayName: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].displayName = displayName
    }

    func deleteVideo(id: UUID, deleteFile: Bool) throws {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if deleteFile, item.kind == .file, FileManager.default.fileExists(atPath: item.url.path) {
            try FileManager.default.removeItem(at: item.url)
        }
        deleteReference(id: id)
    }

    func deleteReference(id: UUID) {
        items.removeAll { $0.id == id }
    }

    func save() {
        JSONFileStore.save(items, to: fileURL)
    }

    static func isSupportedVideo(_ url: URL) -> Bool {
        supportedVideoExtensions.contains(url.pathExtension.lowercased())
    }

    private func uniqueDestination(for fileName: String, in directory: URL) -> URL {
        let sourceURL = URL(fileURLWithPath: fileName)
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        var candidate = directory.appendingPathComponent(fileName)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(baseName) \(suffix)" : "\(baseName) \(suffix).\(ext)"
            candidate = directory.appendingPathComponent(nextName)
            suffix += 1
        }
        return candidate
    }

    private func fileDate(for url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }
}

enum VideoLibraryError: LocalizedError {
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(ext):
            return "不支持的视频格式：\(ext.isEmpty ? "未知" : ext)"
        }
    }
}
