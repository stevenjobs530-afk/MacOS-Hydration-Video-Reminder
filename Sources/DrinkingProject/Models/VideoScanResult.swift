import Foundation

struct VideoScanResult: Equatable {
    var candidates: [URL]
    var playableVideos: [URL]
    var notPlayableVideos: [URL]
    var selectedVideo: URL?

    static let empty = VideoScanResult(
        candidates: [],
        playableVideos: [],
        notPlayableVideos: [],
        selectedVideo: nil
    )
}
