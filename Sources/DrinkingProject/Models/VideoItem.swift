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
    var addedAt: Date
    var lastSeenAt: Date?

    var url: URL {
        URL(fileURLWithPath: urlString)
    }

    var fileName: String {
        url.lastPathComponent
    }

    var displayTitle: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? url.deletingPathExtension().lastPathComponent : trimmed
    }

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case urlString
        case kind
        case isEnabled
        case addedAt
        case lastSeenAt
    }

    init(
        id: UUID,
        displayName: String,
        urlString: String,
        kind: VideoItemKind,
        isEnabled: Bool,
        addedAt: Date,
        lastSeenAt: Date?
    ) {
        self.id = id
        self.displayName = displayName
        self.urlString = urlString
        self.kind = kind
        self.isEnabled = isEnabled
        self.addedAt = addedAt
        self.lastSeenAt = lastSeenAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        urlString = try container.decode(String.self, forKey: .urlString)
        kind = try container.decode(VideoItemKind.self, forKey: .kind)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt)
            ?? lastSeenAt
            ?? Self.fileDate(for: URL(fileURLWithPath: urlString))
            ?? Date()
    }

    private static func fileDate(for url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }
}
