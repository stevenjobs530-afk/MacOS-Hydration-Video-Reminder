import Foundation

enum VideoItemKind: String, Codable, CaseIterable, Identifiable {
    case file
    case folder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .file:
            return "文件"
        case .folder:
            return "文件夹"
        }
    }
}

struct VideoItem: Identifiable, Codable, Hashable {
    var id: UUID
    var displayName: String
    var urlString: String
    var kind: VideoItemKind
    var isEnabled: Bool
    var lastSeenAt: Date?

    var url: URL {
        URL(fileURLWithPath: urlString)
    }
}
