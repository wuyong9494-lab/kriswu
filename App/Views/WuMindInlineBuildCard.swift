import AVKit
import QuickLook
import SwiftUI

struct WuMindInlineBuildCard: View {
    let workID: String
    let onPreview: (WuMindLocalWork) -> Void
    @ObservedObject private var works = WuMindWorksStore.shared

    var body: some View {
        if let work = works.works.first(where: { $0.id == workID }), work.isCompleted {
            WuMindInlineBuildPreview(work: work, asset: works.localAssetURL(for: work), onPreview: onPreview)
                .id(work.id)
        }
    }
}

private struct WuMindInlineBuildPreview: View {
    let work: WuMindLocalWork
    let asset: URL?
    let onPreview: (WuMindLocalWork) -> Void
    @State private var thumbnail: UIImage?
    @State private var videoPlayer: AVPlayer?
    @State private var filePreviewURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !work.modelID.isEmpty {
                Label("已使用 \(work.modelID)", systemImage: "square.on.square")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("wumind.chat.buildModel")
            }
            card
        }
        .onDisappear { videoPlayer?.pause() }
        .quickLookPreview($filePreviewURL)
        .task(id: work.thumbnailFileName) {
            guard work.workType == .image, work.thumbnailFileName != nil else { return }
            thumbnail = WuMindWorksStore.shared.loadThumbnailImage(for: work)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            if work.workType == .image, let thumbnail {
                Button { onPreview(work) } label: {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 310)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("预览生成的图片")
            }
            if work.workType == .video, let asset {
                if let videoPlayer {
                    VideoPlayer(player: videoPlayer)
                        .frame(height: 214)
                        .accessibilityIdentifier("wumind.chat.videoInline")
                } else {
                    Button {
                        videoPlayer = AVPlayer(url: asset)
                    } label: {
                        Label("在对话里播放视频", systemImage: "play.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 124)
                            .background(.secondary.opacity(0.08))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wumind.chat.playInline")
                }
            }
            HStack(spacing: 8) {
                Button {
                    if work.workType == .ppt, let asset, QLPreviewController.canPreview(asset as NSURL) {
                        filePreviewURL = asset
                    } else {
                        onPreview(work)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(work.title).font(.subheadline.weight(.medium)).lineLimit(2)
                            Text(work.workType.title + (asset.map { " · " + $0.pathExtension.uppercased() } ?? ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                    }
                    .frame(minHeight: 44)
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wumind.chat.buildResult")
                if let asset {
                    ShareLink(item: asset) {
                        Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("分享作品文件")
                }
            }
            .padding(.leading, 12)
        }
        .background(.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var icon: String {
        switch work.workType {
        case .image: return "photo"
        case .video: return "video"
        case .ppt: return "rectangle.on.rectangle"
        case .scene3d: return "cube"
        case .document: return "doc.text"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
}


// Created on demand when the user taps a result; no 3D renderer or script execution in the transcript.
struct WuMindChatArtifactPreview: View {
    let work: WuMindLocalWork
    @Environment(\.dismiss) private var dismiss
    @State private var scene: WuMindSpatialSceneDocument?
    @State private var plainText: String?
    @State private var didLoad = false

    var body: some View {
        if work.workType == .scene3d || work.workType == .code || (work.workType == .document && work.assetMime == "text/markdown") {
            NavigationStack {
                Group {
                    if let scene {
                        WuMindSpatial3DViewport(
                            sceneDoc: scene, sceneRevision: 1, selectedNodeID: nil, activeFloorFilter: nil,
                            hideRoofs: false, hideExteriorWalls: false, activeCameraPresetID: nil, cameraCommandRevision: 0,
                            walkDeltaCommand: nil, onSelectNode: { _ in }, onPerfUpdate: { _, _, _ in }
                        )
                    } else if let plainText {
                        ScrollView {
                            Text(plainText)
                                .font(work.workType == .code ? .system(.footnote, design: .monospaced) : .body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18)
                        }
                    } else if didLoad {
                        VStack(spacing: 10) {
                            Image(systemName: "doc")
                                .font(.system(size: 30))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text("无法在 App 内预览")
                                .font(.headline)
                            Text("可以导出原始文件，在支持的应用里打开。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(24)
                    } else {
                        ProgressView()
                    }
                }
                .navigationTitle(work.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                    if let asset = WuMindWorksStore.shared.localAssetURL(for: work) {
                        ToolbarItem(placement: .primaryAction) {
                            ShareLink(item: asset) { Label("分享原文件", systemImage: "square.and.arrow.up") }
                        }
                    }
                }
                .task { loadLocalPreview() }
            }
        } else {
            WuMindWorkDetailSheet(work: work)
        }
    }

    private func loadLocalPreview() {
        defer { didLoad = true }
        let store = WuMindWorksStore.shared
        if work.workType == .scene3d, let project = store.loadLocalProjectJSON(for: work) {
            scene = try? WuMindSpatial3DEngine.decodeProjectJSON(Data(project.utf8))
        } else if let url = store.localAssetURL(for: work), let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            if let prefix = try? handle.read(upToCount: 32_768) {
                plainText = String(decoding: prefix, as: UTF8.self)
                    + (prefix.count == 32_768 ? "\n\n（预览已截断，请导出原文件查看全文。）" : "")
            }
        }
    }
}
