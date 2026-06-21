import Combine
import Foundation

@MainActor
final class VideoLibraryStore: ObservableObject {
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
            lastSeenAt: nil
        )
        guard !items.contains(where: { $0.urlString == item.urlString }) else { return }
        items.append(item)
    }

    func deleteReference(id: UUID) {
        items.removeAll { $0.id == id }
    }

    func save() {
        JSONFileStore.save(items, to: fileURL)
    }
}
