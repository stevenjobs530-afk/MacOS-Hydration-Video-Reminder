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
}
