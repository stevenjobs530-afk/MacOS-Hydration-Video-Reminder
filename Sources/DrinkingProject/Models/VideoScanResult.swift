import Foundation

struct UnavailableVideoReference: Identifiable, Equatable {
    var id: UUID
    var displayName: String
    var path: String
    var kind: VideoItemKind
    var reason: String
}

struct VideoScanResult: Equatable {
    var candidates: [URL]
    var playableVideos: [URL]
    var notPlayableVideos: [URL]
    var unavailableReferences: [UnavailableVideoReference]
    var selectedVideo: URL?

    static let empty = VideoScanResult(
        candidates: [],
        playableVideos: [],
        notPlayableVideos: [],
        unavailableReferences: [],
        selectedVideo: nil
    )

    /// A human-readable, copy-friendly diagnostic summary. No file is modified.
    var diagnosticSummary: String {
        var lines: [String] = []
        lines.append("Drinking Project 视频诊断")
        lines.append("候选 candidate_count=\(candidates.count)")
        lines.append("可播放 playable_count=\(playableVideos.count)")
        lines.append("不可播放 not_playable_count=\(notPlayableVideos.count)")
        lines.append("引用不可用 unavailable_count=\(unavailableReferences.count)")

        if notPlayableVideos.isEmpty {
            lines.append("不可播放文件：无")
        } else {
            lines.append("不可播放文件：")
            for url in notPlayableVideos {
                lines.append("  - \(url.lastPathComponent)")
            }
        }

        if unavailableReferences.isEmpty {
            lines.append("不可用引用：无")
        } else {
            lines.append("不可用引用：")
            for reference in unavailableReferences {
                lines.append("  - \(reference.displayName)：\(reference.reason)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
