import AppKit
import SwiftUI

struct VideoLibraryView: View {
    @ObservedObject var store: VideoLibraryStore
    @ObservedObject var scanner: VideoScanner

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Video Library")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Button("Add File") {
                    addReference(choosingFolders: false)
                }
                Button("Add Folder") {
                    addReference(choosingFolders: true)
                }
                Button("Scan") {
                    scanner.scanVideos()
                }
            }

            GroupBox("References") {
                if store.items.isEmpty {
                    Text("No extra references yet. The app still scans 视频/视频素材/ first.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach($store.items) { $item in
                            HStack {
                                Toggle("", isOn: $item.isEnabled)
                                    .labelsHidden()
                                TextField("Display name", text: $item.displayName)
                                    .textFieldStyle(.roundedBorder)
                                Text(item.kind.rawValue)
                                    .foregroundStyle(.secondary)
                                Button("Remove") {
                                    store.deleteReference(id: item.id)
                                }
                            }
                            Text(item.urlString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            GroupBox("Playable Scan") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Candidates: \(scanner.lastScanResult.candidates.count)")
                    Text("Playable: \(scanner.lastScanResult.playableVideos.count)")
                    Text("Not playable: \(scanner.lastScanResult.notPlayableVideos.count)")

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
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
}
