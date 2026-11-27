import AVKit
import QuickLook
import SwiftUI
import WebKit

struct WuMindInlineBuildCard: View {
    let workID: String
    let onPreview: (WuMindLocalWork) -> Void
    let onVideoStage: () -> Void
    @ObservedObject private var works = WuMindWorksStore.shared

    var body: some View {
        if let work = works.works.first(where: { $0.id == workID }) {
            if work.isCompleted {
                WuMindInlineBuildPreview(work: work, asset: works.localAssetURL(for: work),
                                         onPreview: onPreview, onVideoStage: onVideoStage)
                    .id(work.id)
            } else if work.workType == .video && work.isInProgress {
                Button(action: onVideoStage) {
                    Label(work.isStatusUnknown ? "查看视频任务状态" : "查看视频生成", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.medium))
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wumind.chat.videoStage")
            }
        }
    }
}

private struct WuMindInlineBuildPreview: View {
    let work: WuMindLocalWork
    let asset: URL?
    let onPreview: (WuMindLocalWork) -> Void
    @State private var thumbnail: UIImage?
    let onVideoStage: () -> Void
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
            if work.workType == .video, asset != nil {
                Button(action: onVideoStage) {
                    Label("预览视频", systemImage: "play.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 124)
                        .background(.secondary.opacity(0.08))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wumind.chat.playInline")
            }
            HStack(spacing: 8) {
                Button {
                    if work.workType == .video, asset != nil {
                        onVideoStage()
                    } else if work.workType == .ppt, let asset, QLPreviewController.canPreview(asset as NSURL) {
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
            .padding(.leading, DS.Space.s)
            if work.workType == .ppt, work.projectFileName != nil || work.hasRemoteProject {
                Divider()
                Button { onPreview(work) } label: {
                    Label("编辑幻灯片", systemImage: "pencil")
                        .font(DS.Font.callout)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .background(DS.Palette.cardSurface, in: RoundedRectangle(cornerRadius: DS.Radius.m))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m))
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
    var onReopenPPT: ((WuMindPPTDeck, String) -> Void)? = nil
    var onReopenScene3D: ((String, String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var scene: WuMindSpatialSceneDocument?
    @State private var sceneSource: String?
    @State private var plainText: String?
    @State private var didLoad = false
    @State private var editingCode = false
    @State private var savedCodeWork: WuMindLocalWork?
    @State private var codeError: String?


    var body: some View {
        if work.workType == .scene3d && didLoad && scene == nil && work.hasRemoteProject {
            WuMindWorkDetailSheet(work: work, onReopenScene3D: onReopenScene3D)
        } else if work.workType == .scene3d || work.workType == .code || (work.workType == .document && work.assetMime == "text/markdown") {
            NavigationStack {
                Group {
                    if let scene {
                        WuMindSpatial3DViewport(
                            sceneDoc: scene, sceneRevision: 1, selectedNodeID: nil, activeFloorFilter: nil,
                            hideRoofs: false, hideExteriorWalls: false, activeCameraPresetID: nil, cameraCommandRevision: 0,
                            walkDeltaCommand: nil, onSelectNode: { _ in }, onPerfUpdate: { _, _, _ in }
                        )
                    } else if work.workType == .code, let html = plainText {
                        if editingCode {
                            TextEditor(text: Binding(get: { plainText ?? "" }, set: { plainText = $0 }))
                                .font(.system(.footnote, design: .monospaced))
                        } else {
                            WuMindOfflineHTMLPreview(html: html)
                        }
                    } else if let plainText {
                        ScrollView {
                            Text(plainText)
                                .font(work.workType == .code ? .system(.footnote, design: .monospaced) : .body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18)
                        }
                    } else if didLoad {
                        AppEmptyStateCard(icon: "doc", title: "无法预览此文件", message: "可分享原文件，在支持此格式的应用中打开。")
                            .padding(DS.Space.m)
                    } else {
                        ProgressView()
                    }
                }
                .navigationTitle(work.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                    if let sceneSource, let onReopenScene3D {
                        ToolbarItem(placement: .primaryAction) {
                            Button("编辑场景") { onReopenScene3D(sceneSource, work.id) }
                        }
                    }
                    if work.workType == .code, plainText != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button(editingCode ? "保存版本" : "编辑源码") {
                                if editingCode { saveCodeVersion() } else { editingCode = true }
                            }
                        }
                    }
                    if !editingCode, let asset = WuMindWorksStore.shared.localAssetURL(for: savedCodeWork ?? work) {
                        ToolbarItem(placement: .primaryAction) {
                            ShareLink(item: asset) { Label("分享原文件", systemImage: "square.and.arrow.up") }
                        }
                    }
                }
                .task { loadLocalPreview() }
                .alert("保存代码", isPresented: Binding(get: { codeError != nil }, set: { if !$0 { codeError = nil } })) {
                    Button("好") { codeError = nil }
                } message: { Text(codeError ?? "") }
            }
        } else {
            WuMindWorkDetailSheet(work: work, onReopenPPT: onReopenPPT, onReopenScene3D: onReopenScene3D)
        }
    }

    private func saveCodeVersion() {
        guard let html = plainText.flatMap(WuMindChatBuild.standaloneHTML) else {
            codeError = "需要包含完整的 HTML 页面。"
            return
        }
        let store = WuMindWorksStore.shared
        guard let next = store.saveEditedVersion(from: (savedCodeWork ?? work).id, assetData: Data(html.utf8),
                                                 assetMime: "text/html", assetExtension: "html"),
              store.localAssetURL(for: next) != nil else {
            codeError = "未能写入本地作品，请重试。"
            return
        }
        savedCodeWork = next
        plainText = html
        editingCode = false
    }

    private func loadLocalPreview() {
        defer { didLoad = true }
        let store = WuMindWorksStore.shared
        if work.workType == .scene3d, let project = store.loadLocalProjectJSON(for: work) {
            scene = try? WuMindSpatial3DEngine.decodeProjectJSON(Data(project.utf8))
            sceneSource = scene == nil ? nil : project
        } else if let url = store.localAssetURL(for: work), let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            if work.workType == .code {
                if let data = try? handle.read(upToCount: 1_000_001), data.count <= 1_000_000,
                   let html = String(data: data, encoding: .utf8) {
                    plainText = WuMindChatBuild.standaloneHTML(html)
                }
            } else if let prefix = try? handle.read(upToCount: 32_768) {
                plainText = String(decoding: prefix, as: UTF8.self)
                    + (prefix.count == 32_768 ? "\n\n（预览已截断，请导出原文件查看全文。）" : "")
            }
        }
    }
}

/// The child document has an opaque origin and can run inline scripts only.
private struct WuMindOfflineHTMLPreview: UIViewRepresentable {
    let html: String

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.request.url?.scheme == "about" ? .allow : .cancel)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        view.loadHTMLString(WuMindChatBuild.offlinePreviewDocument(html), baseURL: nil)
    }
}
