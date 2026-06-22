import AppKit
import Combine
import SwiftUI

struct VideoLibraryView: View {
    @ObservedObject var store: VideoLibraryStore
    @ObservedObject var scanner: VideoScanner
    let paths: AppPaths

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("视频库")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Button("打开素材文件夹") {
                    openMaterialFolder()
                }
                Button("添加文件") {
                    addReference(choosingFolders: false)
                }
                Button("添加文件夹") {
                    addReference(choosingFolders: true)
                }
                Button("扫描视频") {
                    scanner.scanVideos()
                }
            }

            GroupBox("视频引用") {
                if store.items.isEmpty {
                    Text("还没有额外引用。App 仍会优先扫描 `视频/视频素材/`。")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach($store.items) { $item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Toggle("", isOn: $item.isEnabled)
                                        .labelsHidden()
                                    TextField("显示名称", text: $item.displayName)
                                        .textFieldStyle(.roundedBorder)
                                    Text(item.kind.title)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if item.kind == .folder {
                                        Button("重新扫描") {
                                            scanner.scanVideos()
                                        }
                                    }
                                    Button("在 Finder 显示") {
                                        revealInFinder(item.url)
                                    }
                                    .disabled(!FileManager.default.fileExists(atPath: item.url.path))
                                    Button("移除引用") {
                                        store.deleteReference(id: item.id)
                                        scanner.scanVideos()
                                    }
                                }
                                Text(item.urlString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let unavailable = unavailableReference(for: item.id) {
                                    Label(unavailable.reason, systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                Text("移除引用只会从列表里删除路径，不会删除原始视频文件。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Divider()
                        }
                    }
                }
            }

            GroupBox("扫描结果") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 18) {
                        Text("候选：\(scanner.lastScanResult.candidates.count)")
                        Text("可播放：\(scanner.lastScanResult.playableVideos.count)")
                        Text("不可播放：\(scanner.lastScanResult.notPlayableVideos.count)")
                        Text("引用不可用：\(scanner.lastScanResult.unavailableReferences.count)")
                    }
                    .font(.system(size: 13))

                    if scanner.lastScanResult.playableVideos.isEmpty {
                        Label("未找到可播放视频。把 mp4/mov/m4v 放到 视频/视频素材/ 里，然后点击扫描。", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }

                    if !scanner.lastScanResult.unavailableReferences.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("不可用引用")
                                .font(.headline)
                            ForEach(scanner.lastScanResult.unavailableReferences) { reference in
                                Text("\(reference.displayName)：\(reference.reason)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    if !scanner.lastScanResult.notPlayableVideos.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("不可播放文件")
                                .font(.headline)
                            ForEach(scanner.lastScanResult.notPlayableVideos, id: \.path) { url in
                                Text(url.lastPathComponent)
                                    .font(.caption)
                            }
                        }
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("可播放文件")
                                .font(.headline)
                            ForEach(scanner.lastScanResult.playableVideos, id: \.path) { url in
                                Text(url.lastPathComponent)
                                    .font(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 140)
                }
            }

            Spacer()
        }
        .padding(28)
        .onAppear {
            scanner.scanVideos()
        }
        .onReceive(store.$items.dropFirst()) { _ in
            scanner.scanVideos()
        }
    }

    private func addReference(choosingFolders: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !choosingFolders
        panel.canChooseDirectories = choosingFolders
        panel.allowsMultipleSelection = false
        if !choosingFolders {
            panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        }
        if panel.runModal() == .OK, let url = panel.url {
            store.addReference(url: url)
            scanner.scanVideos()
        }
    }

    private func unavailableReference(for id: UUID) -> UnavailableVideoReference? {
        scanner.lastScanResult.unavailableReferences.first { $0.id == id }
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openMaterialFolder() {
        try? FileManager.default.createDirectory(
            at: paths.videoMaterialDirectory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(paths.videoMaterialDirectory)
    }
}
