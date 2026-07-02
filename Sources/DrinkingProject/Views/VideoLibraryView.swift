import AppKit
import AVFoundation
import AVKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct VideoLibraryView: View {
    @ObservedObject var store: VideoLibraryStore
    @ObservedObject var scanner: VideoScanner
    let paths: AppPaths

    @State private var sortOrder: VideoSortOrder = .newestFirst
    @State private var feedbackMessage = ""
    @State private var lastScanSignature = ""
    @State private var pendingDeletion: VideoItem?
    @State private var preview: VideoPreview?
    @State private var previewPlayer: AVPlayer?
    @State private var previewFailureMessage = ""
    @StateObject private var thumbnailLoader = VideoThumbnailLoader()

    private let columns = [
        GridItem(.adaptive(minimum: 230, maximum: 280), spacing: 12, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if !feedbackMessage.isEmpty {
                Text(feedbackMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if videoItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(videoItems) { item in
                            videoCard(for: item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)

                    externalReferences
                }
            }
        }
        .padding(28)
        .onAppear {
            refreshLibrary()
            lastScanSignature = Self.scanSignature(for: store.items)
        }
        .onReceive(store.$items.dropFirst()) { items in
            let signature = Self.scanSignature(for: items)
            guard signature != lastScanSignature else { return }
            lastScanSignature = signature
            _ = scanner.scanVideos()
        }
        .sheet(item: $preview, onDismiss: closePreview) { preview in
            VideoPreviewSheet(preview: preview, player: previewPlayer, onClose: closePreview)
        }
        .alert("删除视频？", isPresented: deleteAlertBinding) {
            Button("删除", role: .destructive) {
                if let item = pendingDeletion {
                    deleteVideo(item)
                }
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text(deleteMessage)
        }
        .alert("无法预览", isPresented: previewFailureBinding) {
            Button("好的", role: .cancel) {
                previewFailureMessage = ""
            }
        } message: {
            Text(previewFailureMessage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("媒体库")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Picker("排序", selection: $sortOrder) {
                    ForEach(VideoSortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                Button("打开素材文件夹") {
                    openMaterialFolder()
                }
                Button("添加视频") {
                    importVideos()
                }
                Menu {
                    Button("添加文件夹引用") {
                        addFolderReference()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                }
                .menuStyle(.borderlessButton)
            }

            HStack(spacing: 10) {
                Button("一键诊断") {
                    refreshLibrary()
                    feedbackMessage = "已重新扫描媒体库。"
                }
                Button("复制诊断摘要") {
                    copyDiagnostics()
                }
                Text("素材目录：\(paths.videoMaterialDirectory.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("当前没有视频")
                .font(.title3.weight(.semibold))
            Text("添加 mp4、mov、m4v、avi、mkv 或 webm 文件后，它们会复制到现有视频素材目录。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("添加视频") {
                importVideos()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 70)
    }

    private var externalReferences: some View {
        let references = store.items.filter { $0.kind == .folder }
        return Group {
            if !references.isEmpty {
                GroupBox("额外文件夹引用") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(references) { item in
                            HStack {
                                Text(item.displayTitle)
                                    .font(.headline)
                                Text(item.urlString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("重新扫描") {
                                    _ = scanner.scanVideos()
                                }
                                Button("移除引用") {
                                    store.deleteReference(id: item.id)
                                    _ = scanner.scanVideos()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var videoItems: [VideoItem] {
        store.items
            .filter { $0.kind == .file && VideoLibraryStore.isSupportedVideo($0.url) }
            .sorted { first, second in
                switch sortOrder {
                case .newestFirst:
                    return first.addedAt > second.addedAt
                case .oldestFirst:
                    return first.addedAt < second.addedAt
                }
            }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletion = nil
                }
            }
        )
    }

    private var previewFailureBinding: Binding<Bool> {
        Binding(
            get: { !previewFailureMessage.isEmpty },
            set: { isPresented in
                if !isPresented {
                    previewFailureMessage = ""
                }
            }
        )
    }

    private var deleteMessage: String {
        guard let item = pendingDeletion else { return "" }
        if isInMaterialDirectory(item.url) {
            return "这会从媒体库移除「\(item.displayTitle)」，并删除视频素材目录中的本地文件。"
        }
        return "这会从媒体库移除「\(item.displayTitle)」。该文件不在默认素材目录中，因此只会移除记录。"
    }

    private static func scanSignature(for items: [VideoItem]) -> String {
        items
            .map { "\($0.urlString)|\($0.displayName)|\($0.isEnabled)|\($0.kind.rawValue)|\($0.addedAt.timeIntervalSince1970)" }
            .joined(separator: ";")
    }

    private func videoCard(for item: VideoItem) -> some View {
        let fileStatus = status(for: item)
        let shouldGenerateThumbnail = canGenerateThumbnail(for: item, status: fileStatus)
        return VideoCard(
            item: item,
            title: titleBinding(for: item),
            status: fileStatus,
            thumbnailState: shouldGenerateThumbnail ? thumbnailLoader.state(for: item.url) : .placeholder,
            dateText: dateText(item.addedAt),
            canPreview: item.fileExists,
            onPreview: { previewVideo(item) },
            onCopyPath: { copyPath(item) },
            onReveal: { revealInFinder(item.url) },
            onDelete: { pendingDeletion = item }
        )
        .task(id: "\(item.url.path)|\(fileStatus.title)|\(shouldGenerateThumbnail)") {
            guard shouldGenerateThumbnail else { return }
            await thumbnailLoader.loadThumbnail(for: item.url)
        }
    }

    private func titleBinding(for item: VideoItem) -> Binding<String> {
        Binding(
            get: {
                store.items.first(where: { $0.id == item.id })?.displayName ?? item.displayName
            },
            set: { newValue in
                store.renameVideo(id: item.id, displayName: newValue)
            }
        )
    }

    private func refreshLibrary() {
        let result = scanner.scanVideos()
        let materialVideos = result.candidates.filter { isInMaterialDirectory($0) }
        store.syncMaterialVideos(materialVideos)
    }

    private func importVideos() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = VideoLibraryStore.supportedVideoExtensions
            .sorted()
            .compactMap { UTType(filenameExtension: $0) }

        guard panel.runModal() == .OK else { return }
        let results = store.importVideos(from: panel.urls, to: paths.videoMaterialDirectory)
        refreshLibrary()

        let successes = results.filter { if case .success = $0 { return true }; return false }.count
        let failures = results.compactMap { result -> String? in
            if case let .failure(error) = result {
                return error.localizedDescription
            }
            return nil
        }
        if failures.isEmpty {
            feedbackMessage = "已添加 \(successes) 个视频。"
        } else {
            feedbackMessage = "已添加 \(successes) 个视频；\(failures.count) 个失败：\(failures.prefix(2).joined(separator: "；"))"
        }
    }

    private func addFolderReference() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.addReference(url: url)
        _ = scanner.scanVideos()
        feedbackMessage = "已添加文件夹引用：\(url.path)"
    }

    private func deleteVideo(_ item: VideoItem) {
        do {
            try store.deleteVideo(id: item.id, deleteFile: isInMaterialDirectory(item.url))
            refreshLibrary()
            feedbackMessage = "已删除「\(item.displayTitle)」。"
        } catch {
            feedbackMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    private func previewVideo(_ item: VideoItem) {
        guard item.fileExists else {
            previewFailureMessage = "文件不存在：\(item.url.path)"
            return
        }
        let settledResult = scanner.diagnosticScan()
        if settledResult.notPlayableVideos.contains(where: { $0.path == item.url.path }) {
            previewFailureMessage = "这个文件当前无法由 macOS 原生播放器预览，可能需要转码。"
            return
        }
        closePreview()
        let player = AVPlayer(url: item.url)
        previewPlayer = player
        preview = VideoPreview(title: item.displayTitle, url: item.url)
        player.play()
    }

    private func closePreview() {
        previewPlayer?.pause()
        previewPlayer = nil
        preview = nil
    }

    private func copyPath(_ item: VideoItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.url.path, forType: .string)
        feedbackMessage = "已复制路径：\(item.url.path)"
    }

    private func copyDiagnostics() {
        let result = scanner.diagnosticScan()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.diagnosticSummary, forType: .string)
        feedbackMessage = "已复制诊断摘要到剪贴板。"
    }

    private func openMaterialFolder() {
        try? FileManager.default.createDirectory(
            at: paths.videoMaterialDirectory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(paths.videoMaterialDirectory)
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func status(for item: VideoItem) -> VideoFileStatus {
        guard item.fileExists else { return .missing }
        let notPlayable = Set(scanner.lastScanResult.notPlayableVideos.map(\.path))
        if notPlayable.contains(item.url.path) {
            return .notPlayable
        }
        return .available
    }

    private func isInMaterialDirectory(_ url: URL) -> Bool {
        let directoryPath = paths.videoMaterialDirectory.standardizedFileURL.path
        let itemPath = url.standardizedFileURL.path
        return itemPath == directoryPath || itemPath.hasPrefix(directoryPath + "/")
    }

    private func canGenerateThumbnail(for item: VideoItem, status: VideoFileStatus) -> Bool {
        item.kind == .file
            && status == .available
            && item.fileExists
            && isInMaterialDirectory(item.url)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = UKDayClock.calendar
        formatter.timeZone = UKDayClock.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private enum VideoSortOrder: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newestFirst:
            return "最新在前"
        case .oldestFirst:
            return "最旧在前"
        }
    }
}

private enum VideoFileStatus: Equatable {
    case available
    case missing
    case notPlayable

    var title: String {
        switch self {
        case .available:
            return "可用"
        case .missing:
            return "文件失效"
        case .notPlayable:
            return "不可播放"
        }
    }

    var color: Color {
        switch self {
        case .available:
            return .green
        case .missing:
            return .orange
        case .notPlayable:
            return .red
        }
    }
}

private enum VideoThumbnailState {
    case placeholder
    case loading
    case ready(NSImage)
    case failed
}

@MainActor
private final class VideoThumbnailLoader: ObservableObject {
    @Published private var states: [String: VideoThumbnailState] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    deinit {
        tasks.values.forEach { $0.cancel() }
    }

    func state(for url: URL) -> VideoThumbnailState {
        states[url.path] ?? .placeholder
    }

    func loadThumbnail(for url: URL) async {
        let key = url.path
        switch states[key] {
        case .ready, .loading:
            return
        case .failed, .placeholder, nil:
            break
        }

        states[key] = .loading
        tasks[key]?.cancel()
        let task = Task { [weak self] in
            let result = await VideoThumbnailGenerator.generateThumbnail(for: url)
            guard !Task.isCancelled else { return }
            self?.states[key] = result.image.map(VideoThumbnailState.ready) ?? .failed
            self?.tasks[key] = nil
        }
        tasks[key] = task
        await task.value
    }
}

private final class VideoThumbnailResult: @unchecked Sendable {
    let image: NSImage?

    init(image: NSImage?) {
        self.image = image
    }
}

private enum VideoThumbnailGenerator {
    static func generateThumbnail(for url: URL) async -> VideoThumbnailResult {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 270)

            let sampleSeconds: [Double] = [1, 2, 3, 5]
            var firstGeneratedImage: NSImage?
            for second in sampleSeconds {
                let time = CMTime(seconds: second, preferredTimescale: 600)
                guard let cgImage = generateCGImage(with: generator, at: time) else {
                    continue
                }
                let image = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: cgImage.width, height: cgImage.height)
                )
                if firstGeneratedImage == nil {
                    firstGeneratedImage = image
                }
                if !isMostlyBlack(cgImage) {
                    return VideoThumbnailResult(image: image)
                }
            }
            return VideoThumbnailResult(image: firstGeneratedImage)
        }.value
    }

    private static func generateCGImage(with generator: AVAssetImageGenerator, at time: CMTime) -> CGImage? {
        let result = GeneratedCGImageResult()
        let semaphore = DispatchSemaphore(value: 0)
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, generationResult, _ in
            if generationResult == .succeeded {
                result.image = image
            }
            semaphore.signal()
        }
        semaphore.wait()
        return result.image
    }

    private static func isMostlyBlack(_ image: CGImage) -> Bool {
        let width = 32
        let height = 18
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var darkPixels = 0
        var luminanceTotal = 0.0
        let pixelCount = width * height
        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let red = Double(pixels[index]) / 255.0
            let green = Double(pixels[index + 1]) / 255.0
            let blue = Double(pixels[index + 2]) / 255.0
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            luminanceTotal += luminance
            if luminance < 0.08 {
                darkPixels += 1
            }
        }

        let darkRatio = Double(darkPixels) / Double(pixelCount)
        let averageLuminance = luminanceTotal / Double(pixelCount)
        return darkRatio > 0.88 || averageLuminance < 0.05
    }
}

private final class GeneratedCGImageResult: @unchecked Sendable {
    var image: CGImage?
}

private struct VideoCard: View {
    let item: VideoItem
    @Binding var title: String
    let status: VideoFileStatus
    let thumbnailState: VideoThumbnailState
    let dateText: String
    let canPreview: Bool
    let onPreview: () -> Void
    let onCopyPath: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VideoThumbnailArea(status: status, state: thumbnailState)

            TextField("视频标题", text: $title)
                .font(.headline)
                .textFieldStyle(.plain)
                .lineLimit(2)

            Text(item.fileName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack {
                Label(status.title, systemImage: status == .available ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(status.color)
                Spacer()
                Text(dateText)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            HStack {
                Button {
                    onPreview()
                } label: {
                    Label("预览", systemImage: "play.fill")
                }
                .disabled(!canPreview)

                Spacer()

                Menu {
                    Button("复制路径", action: onCopyPath)
                    Button("在 Finder 显示", action: onReveal)
                        .disabled(!item.fileExists)
                    Divider()
                    Button("删除", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(12)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.18))
        )
    }
}

private struct VideoThumbnailArea: View {
    let status: VideoFileStatus
    let state: VideoThumbnailState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))

            switch visibleState {
            case .ready(let image):
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            case .loading:
                placeholder(icon: "film", text: "生成预览中")
            case .failed:
                placeholder(icon: "exclamationmark.triangle", text: "无法生成预览")
            case .placeholder:
                placeholder(icon: placeholderIcon, text: placeholderText)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var visibleState: VideoThumbnailState {
        switch status {
        case .missing, .notPlayable:
            return .placeholder
        case .available:
            return state
        }
    }

    private var placeholderIcon: String {
        switch status {
        case .available:
            return "film"
        case .missing, .notPlayable:
            return "exclamationmark.triangle"
        }
    }

    private var placeholderText: String? {
        switch status {
        case .available:
            return nil
        case .missing:
            return "文件失效"
        case .notPlayable:
            return "不可播放"
        }
    }

    private func placeholder(icon: String, text: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
            if let text {
                Text(text)
                    .font(.caption.weight(.medium))
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct VideoPreview: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

private struct VideoPreviewSheet: View {
    let preview: VideoPreview
    let player: AVPlayer?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preview.title)
                        .font(.title3.weight(.semibold))
                    Text(preview.url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("关闭") {
                    onClose()
                }
            }

            if let player {
                VideoPlayer(player: player)
                    .frame(minWidth: 680, minHeight: 420)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 34))
                        .foregroundStyle(.orange)
                    Text("无法加载预览")
                        .font(.headline)
                }
                    .frame(minWidth: 680, minHeight: 420)
            }
        }
        .padding(20)
    }
}
