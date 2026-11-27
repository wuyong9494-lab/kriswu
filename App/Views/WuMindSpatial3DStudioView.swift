import Metal
import PDFKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Flagship WUMIND「AI 3D 空间工坊」:
/// Create & surgically edit multi-element 3D architectural complexes, measured interiors,
/// modern waterfront pavilions, villas, and exhibition spaces from text or uploaded drawings/photos.
/// Exports lossless re-importable `.wumind3d.json`, multi-node binary `.glb`, and dimensioned 2D Plan PDF.
@MainActor
struct WuMindSpatial3DStudioView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var spatialStore = WuMindSpatial3DStore.shared
    @ObservedObject private var chatStore = WuMindStore.shared

    @State private var selectedTaskIntent: WuMind3DTaskIntent = .gameTownWorld
    @State private var createTab: CreateTab = .textPrompt
    @State private var promptInput = ""
    @State private var selectedSceneType: WuMindSpatialSceneType = .gameScene
    @State private var nodeEditInstruction = ""
    private static let metalAvailable = MTLCreateSystemDefaultDevice() != nil
    @State private var renderedFrame = false
    @State private var frameWaitExpired = false
    @State private var viewportAttempt = 0
    @State private var showWalkPad = false
    @State private var showOutlinerExpanded = true
    @State private var showingMoreTools = false
    @State private var showingWorksHistory = false
    @State private var showingProjectLibrary = false
    @State private var showingTechRegistry = false
    @State private var showingTripoSheet = false
    @State private var showingDrawingImporter = false
    @State private var showingProjectImporter = false
    @State private var localExportDoc: WuMindBinaryExportDocument? = nil
    @State private var localExportFilename: String = "wumind_scene.glb"
    @State private var localExportContentType: UTType = .data
    @State private var showingLocalFileExporter = false
    @State private var uploadedPhotoItem: PhotosPickerItem?
    @State private var stagedImages: [AIProviderMessage.ImageAttachment] = []
    @State private var stagedFilenames: [String] = []
    @State private var stagedDrawingText: String = ""
    @FocusState private var promptFocused: Bool

    private enum CreateTab: String, CaseIterable, Identifiable {
        case textPrompt = "描述创建"
        case uploadRef = "上传图纸 / 草图 / 照片"
        var id: String { rawValue }
    }

    private var isDark: Bool { colorScheme == .dark }
    private var canvasBg: Color { DS.Palette.background }
    private var cardBg: Color { DS.Palette.cardSurface }
    private var cardBorder: Color { DS.Palette.hairline }

    private var shouldRenderViewport: Bool {
        scenePhase == .active && !showingMoreTools && !showingWorksHistory && !showingProjectLibrary
            && !showingTechRegistry && !showingTripoSheet && !showingDrawingImporter
            && !showingProjectImporter && !showingLocalFileExporter
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                viewportCard
                headerDisclaimerStrip
                layerAndHistoryToolbar

                if let notice = spatialStore.lastNotice {
                    statusBanner(text: notice, isError: false)
                }
                if let error = spatialStore.lastError {
                    statusBanner(text: error, isError: true)
                }
                if spatialStore.isGenerating {
                    generatingProgressCard
                }

                if let selected = spatialStore.selectedNode {
                    selectedNodeInspectorCard(selected)
                }

                if let blueprintDraft = spatialStore.activeBlueprintDraft {
                    blueprintOverlayReviewCard(blueprintDraft)
                }

                creationStudioCard
                exportDeliverablesCard

                if !spatialStore.scene.dimensionAuditItems.isEmpty {
                    dimensionAuditCard
                }

                sceneOutlinerCard

                Color.clear.frame(height: 18)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(canvasBg.ignoresSafeArea())
        .navigationTitle("3D 空间")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    showingWorksHistory = true
                } label: {
                    Label("历史", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityIdentifier("ai.spatial3d.history")

                Button {
                    showingTechRegistry = true
                } label: {
                    Image(systemName: "books.vertical.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel("3D 技术库")
                .accessibilityIdentifier("ai.spatial3d.openTechLibraryToolbar")

                Button {
                    promptFocused = false
                    showingMoreTools.toggle()
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel("更多 3D 工具")
                .accessibilityIdentifier("ai.spatial3d.moreToolsMenu")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if showingMoreTools {
                VStack(spacing: 0) {
                    toolRow("已保存工程库", image: "folder.fill", identifier: "ai.spatial3d.projectsAction") {
                        showingMoreTools = false
                        showingProjectLibrary = true
                    }
                    Divider()
                    toolRow("高级模型与道具接口（Tripo）", image: "cube.transparent.fill", identifier: "ai.spatial3d.tripoAction") {
                        showingMoreTools = false
                        showingTripoSheet = true
                    }
                }
                .background(DS.Palette.cardSurface)
            }
        }
        .sheet(isPresented: $showingWorksHistory) {
            WuMindWorksView(
                initialFilter: .scene3d,
                onReopenScene3D: { projectJSON, workID in
                    spatialStore.openProjectJSON(projectJSON, linkedWorkID: workID)
                }
            )
        }
        .sheet(isPresented: $showingProjectLibrary) {
            WuMindSpatialProjectLibrarySheet(onImportExternal: {
                showingProjectLibrary = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    showingProjectImporter = true
                }
            })
        }
        .sheet(isPresented: $showingTechRegistry) {
            WuMind3DTechRegistrySheet()
        }
        .sheet(isPresented: $showingTripoSheet) {
            WuMindSpatialTripoSheet()
        }
        .fileExporter(
            isPresented: $showingLocalFileExporter,
            document: localExportDoc,
            contentType: localExportContentType,
            defaultFilename: localExportFilename
        ) { result in
            switch result {
            case .success(let savedURL):
                spatialStore.lastNotice = "已离线保存到本机文件：\(savedURL.lastPathComponent)"
                Haptics.success()
            case .failure(let err):
                spatialStore.lastError = "保存到本地文件失败：\(err.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showingDrawingImporter,
            allowedContentTypes: [.pdf, .image, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImportedReferenceFile(result)
        }
        .fileImporter(
            isPresented: $showingProjectImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                spatialStore.importProjectFile(from: url)
            }
        }
        .onChange(of: uploadedPhotoItem) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let jpeg = Self.normalizedAttachmentJPEG(from: data) {
                    let filename = "参考图_\(stagedFilenames.count + 1).jpg"
                    stagedImages.append(AIProviderMessage.ImageAttachment(mimeType: "image/jpeg", base64Data: jpeg.base64EncodedString()))
                    stagedFilenames.append(filename)
                    if let uiImg = UIImage(data: jpeg) {
                        spatialStore.analyzeUploadedBlueprint(image: uiImg, filename: filename, ocrText: stagedDrawingText.isEmpty ? nil : stagedDrawingText)
                    }
                    Haptics.success()
                }
                uploadedPhotoItem = nil
            }
        }
    }

    // MARK: - 1. Header Disclaimer Strip

    private func toolRow(_ title: String, image: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: image)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, DS.Space.m)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var headerDisclaimerStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: spatialStore.scene.isConceptScene ? "sparkles.rectangle.stack.fill" : "ruler.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(spatialStore.scene.isConceptScene ? .orange : .green)
            VStack(alignment: .leading, spacing: 1) {
                Text(spatialStore.scene.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(spatialStore.scene.disclaimerBanner)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    // MARK: - 2. Live Interactive Metal 3D Viewport + Camera Presets + Weather + Walk Pad + FPS HUD

    private var viewportCard: some View {
        VStack(spacing: 0) {
            ZStack {
                if Self.metalAvailable {
                    WuMindSpatial3DViewport(
                        sceneDoc: spatialStore.scene,
                        sceneRevision: spatialStore.sceneRevision,
                        selectedNodeID: spatialStore.selectedNodeID,
                        activeFloorFilter: spatialStore.activeFloorFilter,
                        hideRoofs: spatialStore.hideRoofs,
                        hideExteriorWalls: spatialStore.hideExteriorWalls,
                        activeCameraPresetID: spatialStore.activeCameraPresetID,
                        cameraCommandRevision: spatialStore.cameraCommandRevision,
                        walkDeltaCommand: spatialStore.walkDeltaCommand,
                        renderContinuously: shouldRenderViewport,
                        onSelectNode: { uuid in
                            spatialStore.selectedNodeID = uuid
                            if uuid != nil { Haptics.tap() }
                        },
                        onPerfUpdate: { fps, loadMs, visibleNodes in
                            if !renderedFrame { renderedFrame = true }
                            spatialStore.perfMetrics.fps = fps
                            spatialStore.perfMetrics.lastBuildMs = loadMs
                            spatialStore.perfMetrics.nodeCount = visibleNodes
                        }
                    )
                    .id(viewportAttempt)
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("3D 画布")
                    .accessibilityValue(renderedFrame ? "已绘制" : "加载中")
                    .accessibilityIdentifier("ai.spatial3d.viewport")
                }

                // Top Overlay: Live FPS/Load/Device HUD (left) + Sunny/Snowy/Night Switcher (right)
                VStack {
                    HStack(alignment: .top, spacing: 6) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(spatialStore.perfMetrics.fps >= 45 ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            let metrics = spatialStore.perfMetrics
                            Text(metrics.fps > 0
                                ? String(format: "%.0f FPS · %.0fms · %d构件", metrics.fps, metrics.lastBuildMs, metrics.nodeCount)
                                : "首帧 · \(metrics.nodeCount)构件")
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.62), in: Capsule())
                        .accessibilityIdentifier("ai.spatial3d.perfHud")

                        Spacer(minLength: 4)

                        HStack(spacing: 4) {
                            ForEach(WuMindSpatialWeather.allCases) { weather in
                                let active = spatialStore.scene.weather == weather
                                Button {
                                    spatialStore.setWeather(weather)
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: weather.iconName)
                                            .font(.system(size: 10, weight: .bold))
                                        if active {
                                            Text(weather == .sunny ? "晴" : (weather == .snowy ? "雪" : "夜"))
                                                .font(.system(size: 10, weight: .bold))
                                        }
                                    }
                                    .foregroundStyle(active ? .black : .white)
                                    .padding(.horizontal, active ? 8 : 6)
                                    .padding(.vertical, 5)
                                    .background(active ? Color.white : Color.black.opacity(0.55), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("ai.spatial3d.weather.\(weather.rawValue)")
                            }
                        }
                    }
                    .padding(10)

                    Spacer()

                    // Bottom Overlay: Camera Presets + Free-Roam Walk D-Pad Toggle
                    HStack(alignment: .bottom, spacing: 8) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(spatialStore.scene.cameraPresets) { preset in
                                    let active = spatialStore.activeCameraPresetID == preset.id
                                    Button {
                                        spatialStore.focusCameraPreset(preset)
                                    } label: {
                                        Text(preset.title)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(active ? .white : .white.opacity(0.92))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                active
                                                    ? Color.orange
                                                    : Color.black.opacity(0.62),
                                                in: Capsule()
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("ai.spatial3d.camera.\(preset.id)")
                                }
                            }
                        }

                        if showWalkPad {
                            freeRoamPad
                        }

                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { showWalkPad.toggle() }
                        } label: {
                            Image(systemName: showWalkPad ? "xmark.circle.fill" : "figure.walk.motion")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(showWalkPad ? Color.orange : Color.black.opacity(0.62), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ai.spatial3d.walkToggle")
                    }
                    .padding(10)
                }
                .opacity(renderedFrame ? 1 : 0)
                .allowsHitTesting(renderedFrame)
                .accessibilityHidden(!renderedFrame)

                if !Self.metalAvailable {
                    Label("当前设备不支持 Metal，无法显示 3D 预览。", systemImage: "cube.transparent")
                        .font(DS.Font.callout)
                        .accessibilityIdentifier("ai.spatial3d.metalUnavailable")
                } else if !renderedFrame {
                    if frameWaitExpired {
                        VStack(spacing: DS.Space.s) {
                            Text("尚未收到 3D 画面")
                                .accessibilityIdentifier("ai.spatial3d.noFrame")
                            Button("重新加载画布") {
                                frameWaitExpired = false
                                viewportAttempt += 1
                            }
                        }
                    } else {
                        ProgressView("正在绘制 3D 场景…")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 360)
            .task(id: shouldRenderViewport ? viewportAttempt : nil) {
                guard shouldRenderViewport, Self.metalAvailable, !renderedFrame else { return }
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                if !Task.isCancelled && !renderedFrame { frameWaitExpired = true }
            }

            HStack {
                Text("单指旋转 · 双指平移 · 捏合缩放 · 点建筑单独选中修改 · 设备 \(spatialStore.perfMetrics.deviceModel)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    private var freeRoamPad: some View {
        let stepMeters: Float = spatialStore.scene.sceneType == .imperialComplex ? 6.0 : 1.2
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                walkBtn("arrow.up", dx: 0, dy: 0, dz: -stepMeters)
                walkBtn("arrow.up.to.line", dx: 0, dy: stepMeters * 0.5, dz: 0)
            }
            HStack(spacing: 4) {
                walkBtn("arrow.left", dx: -stepMeters, dy: 0, dz: 0)
                walkBtn("arrow.down", dx: 0, dy: 0, dz: stepMeters)
                walkBtn("arrow.right", dx: stepMeters, dy: 0, dz: 0)
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func walkBtn(_ icon: String, dx: Float, dy: Float, dz: Float) -> some View {
        Button {
            spatialStore.stepFreeWalk(dx: dx, dy: dy, dz: dz)
            Haptics.tap()
        } label: {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. Layer, Floor Filter & Undo/Redo Toolbar

    private var layerAndHistoryToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                // Undo / Redo
                Button {
                    spatialStore.undo()
                } label: {
                    Label("撤销", systemImage: "arrow.uturn.backward")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(cardBg, in: Capsule())
                        .overlay(Capsule().strokeBorder(cardBorder, lineWidth: 1))
                }
                .disabled(!spatialStore.canUndo)
                .accessibilityIdentifier("ai.spatial3d.undo")

                Button {
                    spatialStore.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(cardBg, in: Capsule())
                        .overlay(Capsule().strokeBorder(cardBorder, lineWidth: 1))
                }
                .disabled(!spatialStore.canRedo)

                // Hide Roof toggle
                Button {
                    spatialStore.hideRoofs.toggle()
                    Haptics.tap()
                } label: {
                    Label(spatialStore.hideRoofs ? "显示屋顶" : "隐藏屋顶", systemImage: "house.lodge")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(spatialStore.hideRoofs ? .white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(spatialStore.hideRoofs ? Color.orange : cardBg, in: Capsule())
                        .overlay(Capsule().strokeBorder(cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai.spatial3d.hideRoofs")

                // Hide Exterior Walls toggle
                Button {
                    spatialStore.hideExteriorWalls.toggle()
                    Haptics.tap()
                } label: {
                    Label(spatialStore.hideExteriorWalls ? "显示墙面" : "隐藏墙面", systemImage: "square.split.2x1")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(spatialStore.hideExteriorWalls ? .white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(spatialStore.hideExteriorWalls ? Color.indigo : cardBg, in: Capsule())
                        .overlay(Capsule().strokeBorder(cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)

                // Floor switcher when multi-floor exists
                let floors = spatialStore.scene.floorIndices
                if floors.count > 1 {
                    Menu {
                        Button("全部楼层") { spatialStore.activeFloorFilter = nil }
                        ForEach(floors, id: \.self) { f in
                            Button(f == 0 ? "仅看 1F / 底层" : "看至 \(f + 1)F") {
                                spatialStore.activeFloorFilter = f
                            }
                        }
                    } label: {
                        Label(
                            spatialStore.activeFloorFilter.map { "至 \($0 + 1)F" } ?? "全部楼层",
                            systemImage: "square.3.layers.3d"
                        )
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(cardBg, in: Capsule())
                        .overlay(Capsule().strokeBorder(cardBorder, lineWidth: 1))
                    }
                    .tint(.primary)
                }
            }
        }
    }

    // MARK: - 4. Selected Node Surgical Editor ("改这一处，其他不动")

    private func selectedNodeInspectorCard(_ node: WuMindSpatialNode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("已选中：\(node.name)")
                            .font(.subheadline.weight(.bold))
                        Text(node.category.displayName)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                    }
                    Text("\(node.dimensionSummaryText) · \(node.dimensionStatus.label)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    spatialStore.selectedNodeID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Natural-language surgical edit bar
            HStack(spacing: 8) {
                TextField(
                    "局部指令：如「屋顶改翠绿琉璃瓦」「柜宽加 200 毫米」「右移 1.5 米」",
                    text: $nodeEditInstruction
                )
                .font(.caption)
                .padding(9)
                .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

                Button("仅改此项") {
                    let cmd = nodeEditInstruction
                    nodeEditInstruction = ""
                    spatialStore.applyNaturalLanguageEditToSelected(cmd)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 10))
                .disabled(nodeEditInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // Quick exact millimeter / meter buttons (respects Z-axis doorway opening span!)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    let spanIsZ = (node.openingSpanAxis == "z")
                    quickPatchBtn("宽 +200mm") {
                        spatialStore.patchSelectedNode(
                            sizeDeltaMM: spanIsZ ? .init(x: 0, y: 0, z: 200) : .init(x: 200, y: 0, z: 0),
                            label: "加宽200mm"
                        )
                    }
                    quickPatchBtn("宽 -200mm") {
                        spatialStore.patchSelectedNode(
                            sizeDeltaMM: spanIsZ ? .init(x: 0, y: 0, z: -200) : .init(x: -200, y: 0, z: 0),
                            label: "缩窄200mm"
                        )
                    }
                    quickPatchBtn("宽 +1m") {
                        spatialStore.patchSelectedNode(
                            sizeDeltaMM: spanIsZ ? .init(x: 0, y: 0, z: 1_000) : .init(x: 1_000, y: 0, z: 0),
                            label: "加宽1米"
                        )
                    }
                    quickPatchBtn("向东移 2m") {
                        spatialStore.patchSelectedNode(positionDeltaMM: .init(x: 2_000, y: 0, z: 0), label: "东移2米")
                    }
                    quickPatchBtn("向西移 2m") {
                        spatialStore.patchSelectedNode(positionDeltaMM: .init(x: -2_000, y: 0, z: 0), label: "西移2米")
                    }
                }
            }

            // Roof / Material Swatch Picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    let isRoofTarget = node.category == .palaceHall || node.category == .gateTower || node.category == .cityWall
                    Text(isRoofTarget ? "改屋顶瓦色：" : "改构件材质：")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    ForEach([WuMindSpatialMaterialPreset.glazedGoldTile, .emeraldTile, .imperialCrimson, .whiteMarble, .warmCopper, .warmOak, .darkMetal]) { preset in
                        Button {
                            if isRoofTarget {
                                spatialStore.patchSelectedNode(roofPreset: preset, label: "换屋顶材质")
                            } else {
                                spatialStore.patchSelectedNode(bodyPreset: preset, label: "换构件材质")
                            }
                        } label: {
                            Text(preset.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.orange.opacity(0.50), lineWidth: 1.4))
    }

    // MARK: - 4B. Blueprint Overlay Review Card (Tap-to-Correct Walls, Doors, Windows & Scale Bar on Original Image)

    private func blueprintOverlayReviewCard(_ draft: WuMindBlueprintToSceneEngine.BlueprintOverlayDraft) -> some View {
        let isMeasured = draft.scaleCalibration.isMeasured
        let selectedOpening = draft.openings.first(where: { $0.id == spatialStore.selectedBlueprintOpeningID })
            ?? draft.openings.first(where: { $0.needsUserReview })
            ?? draft.openings.first

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: isMeasured ? "ruler.fill" : "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isMeasured ? .blue : .orange)
                Text("图纸叠图核对（确认后再生成 3D）")
                    .font(.caption.weight(.bold))
                Spacer()
                Text(draft.scaleCalibration.statusBadge)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((isMeasured ? Color.blue : Color.orange).opacity(0.14), in: Capsule())
                    .foregroundStyle(isMeasured ? .blue : .orange)
                Button {
                    spatialStore.dismissBlueprintDraft()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Original floorplan image with interactive wall / door / window / scale-bar vector overlay
            ZStack {
                if let img = spatialStore.activeBlueprintImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.10))
                }

                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    // Detected walls overlay (blue)
                    ForEach(draft.walls) { wall in
                        let rw = max(3, wall.rect.width * w)
                        let rh = max(3, wall.rect.height * h)
                        Rectangle()
                            .fill(Color.blue.opacity(0.32))
                            .overlay(Rectangle().stroke(Color.blue.opacity(0.9), lineWidth: 1.2))
                            .frame(width: rw, height: rh)
                            .position(x: wall.rect.centerX * w, y: wall.rect.centerY * h)
                    }

                    // Scale bar overlay (purple) when detected
                    if let bar = draft.scaleCalibration.scaleBarOverlayRect {
                        let bw = max(24, bar.width * w)
                        let bh = max(8, bar.height * h)
                        Rectangle()
                            .stroke(Color.purple, style: StrokeStyle(lineWidth: 2, dash: [4, 2]))
                            .background(Color.purple.opacity(0.18))
                            .frame(width: bw, height: bh)
                            .position(x: bar.centerX * w, y: bar.centerY * h)
                    }

                    // Interactive tappable door & window openings overlay
                    ForEach(draft.openings) { op in
                        let ow = max(22, op.rect.width * w)
                        let oh = max(22, op.rect.height * h)
                        let isSel = (selectedOpening?.id == op.id)
                        let strokeCol: Color = {
                            if op.kind == .falsePositiveRemoved { return .gray }
                            if op.needsUserReview { return .orange }
                            return op.kind == .door ? .green : .cyan
                        }()
                        Button {
                            spatialStore.selectedBlueprintOpeningID = op.id
                            Haptics.tap()
                        } label: {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(strokeCol.opacity(isSel ? 0.42 : 0.25))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(strokeCol, style: StrokeStyle(lineWidth: isSel ? 2.6 : 1.6, dash: op.needsUserReview ? [4, 2] : []))
                                )
                        }
                        .buttonStyle(.plain)
                        .frame(width: ow, height: oh)
                        .position(x: op.rect.centerX * w, y: op.rect.centerY * h)
                    }
                }
            }
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))

            if !isMeasured {
                Text("未检测到原图标尺：所有墙体、门窗及房间尺寸均已标为「估算」，绝不冒充精确毫米尺寸。")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let op = selectedOpening {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("已点选：\(op.name)（\(op.kind.chineseName) · \(op.isEstimated ? "估算 ~\(op.widthMM)mm" : "\(op.widthMM)mm")）")
                            .font(.caption2.weight(.bold))
                        Spacer()
                        if op.needsUserReview {
                            Text("待纠正").font(.system(size: 10, weight: .bold)).foregroundStyle(.orange)
                        } else if op.userCorrected {
                            Text("已纠正").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)
                        }
                    }
                    if let hint = op.reviewHint {
                        Text(hint).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            quickPatchBtn("纠正为门洞(含门框)") {
                                spatialStore.correctBlueprintOpening(openingID: op.id, newKind: .door, newName: "客厅-主卧门（已纠正）")
                            }
                            quickPatchBtn("改为窗洞") {
                                spatialStore.correctBlueprintOpening(openingID: op.id, newKind: .window)
                            }
                            quickPatchBtn("排除误识别") {
                                spatialStore.correctBlueprintOpening(openingID: op.id, newKind: .falsePositiveRemoved)
                            }
                            quickPatchBtn("宽 +100mm") {
                                spatialStore.correctBlueprintOpening(openingID: op.id, deltaWidthMM: 100)
                            }
                            quickPatchBtn("宽 -100mm") {
                                spatialStore.correctBlueprintOpening(openingID: op.id, deltaWidthMM: -100)
                            }
                        }
                    }
                }
                .padding(9)
                .background(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            }

            Button {
                spatialStore.confirmBlueprintAndBuildScene()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("确认叠图 → 生成独立可编辑 3D 场景（墙/门框/门窗/家具）")
                        .font(.caption.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.white)
                .padding(.vertical, 10)
                .background(LinearGradient(colors: [.blue, .teal], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ai.spatial3d.blueprint.confirm")
        }
        .padding(12)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.blue.opacity(0.45), lineWidth: 1.4))
    }

    private func quickPatchBtn(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption2.weight(.bold).monospacedDigit())
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.14), in: Capsule())
            .foregroundStyle(.orange)
    }

    // MARK: - 5. Unified Mobile Entry ("我要做什么" Task Intent -> Auto-Recommended Route)

    private var creationStudioCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("我要做什么")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Button {
                    showingTechRegistry = true
                } label: {
                    Label("3D 技术库", systemImage: "books.vertical")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.indigo)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai.spatial3d.openTechLibraryChip")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(WuMind3DTaskIntent.allCases) { intent in
                        let selected = selectedTaskIntent == intent
                        Button {
                            Haptics.select()
                            selectedTaskIntent = intent
                            switch intent {
                            case .gameTownWorld: selectedSceneType = .gameScene
                            case .interiorBIM: selectedSceneType = .interiorSpace
                            case .cadPartDrawing: selectedSceneType = .modernPavilion
                            case .singlePropPhoto3D: selectedSceneType = .modernPavilion
                            case .characterRigAnim: selectedSceneType = .gameScene
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: intent.iconName)
                                    .font(.caption2.weight(.bold))
                                Text(intent.title)
                                    .font(.caption2.weight(.bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(selected ? Color.indigo : (isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)), in: Capsule())
                            .foregroundStyle(selected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text(selectedTaskIntent.recommendedRouteSummary)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("创建方式", selection: $createTab) {
                ForEach(CreateTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            if createTab == .uploadRef {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button {
                                showingDrawingImporter = true
                            } label: {
                                Label("导入户型图 / PDF", systemImage: "doc.badge.plus")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.14), in: Capsule())
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)

                            PhotosPicker(selection: $uploadedPhotoItem, matching: .images) {
                                Label("选草图 / 参考照", systemImage: "photo.badge.plus")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.purple.opacity(0.14), in: Capsule())
                                    .foregroundStyle(.purple)
                            }

                            Button {
                                spatialStore.loadSampleBlueprintDraft(includeScaleBar: true)
                            } label: {
                                Label("带标尺户型图叠图", systemImage: "ruler")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.teal.opacity(0.14), in: Capsule())
                                    .foregroundStyle(.teal)
                            }
                            .buttonStyle(.plain)

                            Button {
                                spatialStore.loadSampleBlueprintDraft(includeScaleBar: false)
                            } label: {
                                Label("无标尺估算对照", systemImage: "questionmark.square.dashed")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.orange.opacity(0.14), in: Capsule())
                                    .foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !stagedFilenames.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "paperclip")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text("已附参考：\(stagedFilenames.joined(separator: "、"))")
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            Button("清空") {
                                stagedImages.removeAll()
                                stagedFilenames.removeAll()
                                stagedDrawingText = ""
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.red)
                        }
                    }

                    Text("图纸转 3D 规则：上传后先在原图上叠加显示墙线、门窗和比例尺，严格区分「标注尺寸 / 扫描值 / 估算值」，无标尺处自动标为「估算」，绝不编造精确尺寸。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            TextField(
                createTab == .uploadRef
                    ? "可补充文字要求：如「把南墙门向右移 600mm」或「改厨房地柜宽 2400mm」…"
                    : selectedTaskIntent.defaultPromptPlaceholder,
                text: $promptInput,
                axis: .vertical
            )
            .lineLimit(2...4)
            .font(.subheadline)
            .focused($promptFocused)
            .padding(10)
            .background(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("ai.spatial3d.prompt")

            HStack(spacing: 8) {
                Menu {
                    ForEach(WuMindSpatialSceneType.allCases) { type in
                        Button(type.displayName) { selectedSceneType = type }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "building.2.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(selectedSceneType.displayName)
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), in: Capsule())
                }
                .tint(.primary)

                Spacer(minLength: 4)

                Button {
                    promptFocused = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    let mode: WuMindSpatialCreationMode = stagedFilenames.isEmpty
                        ? .textDescription
                        : (promptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .uploadReference : .uploadAndText)
                    spatialStore.generateScene(
                        prompt: promptInput,
                        sceneType: selectedSceneType,
                        creationMode: mode,
                        referenceImages: stagedImages,
                        referenceFilenames: stagedFilenames,
                        extractedDrawingText: stagedDrawingText.isEmpty ? nil : stagedDrawingText,
                        using: chatStore
                    )
                } label: {
                    HStack(spacing: 6) {
                        if spatialStore.isGenerating {
                            ProgressView().tint(.white).controlSize(.mini)
                        } else {
                            Image(systemName: "cube.fill")
                                .font(.caption.weight(.bold))
                        }
                        Text("生成 3D 场景")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(spatialStore.isGenerating)
                .accessibilityIdentifier("ai.spatial3d.generate")
            }

            // Official acceptance scenarios (Red River Town first!)
            VStack(alignment: .leading, spacing: 6) {
                Text("示例场景")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        acceptanceChip("① 赤河镇（西部可走）", icon: "map.fill", tint: .orange) {
                            selectedTaskIntent = .gameTownWorld
                            selectedSceneType = .gameScene
                            spatialStore.loadAcceptanceCase(0)
                        }
                        acceptanceChip("② 户型图厨房+餐区", icon: "ruler.fill", tint: .teal) {
                            selectedTaskIntent = .interiorBIM
                            selectedSceneType = .interiorSpace
                            spatialStore.loadAcceptanceCase(2)
                        }
                        acceptanceChip("③ 四孔安装板 CAD", icon: "wrench.and.screwdriver.fill", tint: .blue) {
                            selectedTaskIntent = .cadPartDrawing
                            selectedSceneType = .modernPavilion
                            spatialStore.loadAcceptanceCase(4)
                        }
                        acceptanceChip("④ 故宫风格宫殿群", icon: "building.columns.fill", tint: .purple) {
                            selectedSceneType = .imperialComplex
                            spatialStore.loadAcceptanceCase(1)
                        }
                    }
                }
            }
        }
        .padding(13)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    private func acceptanceChip(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption2.weight(.bold))
                Text(title).font(.caption2.weight(.bold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.13), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 6. Offline Local Export Deliverables Card (Zero Cloud Dependency)

    private var exportDeliverablesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("导出与分享", systemImage: "square.and.arrow.up.on.square.fill")
                    .font(.caption.weight(.bold))
                Spacer()
            }

            if let walk = spatialStore.lastWalkabilityReport {
                HStack(spacing: 6) {
                    Image(systemName: walk.isWalkable ? "figure.walk.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(walk.isWalkable ? .green : .orange)
                    Text(walk.summary)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(walk.isWalkable ? .green : .orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((walk.isWalkable ? Color.green : Color.orange).opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("ai.spatial3d.walkability")
            }

            HStack(spacing: 8) {
                Button {
                    spatialStore.exportAllDeliverables()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "shippingbox.fill")
                            .font(.caption.weight(.bold))
                        Text("导出工程文件")
                            .font(.caption.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai.spatial3d.export")

                Button {
                    showingProjectImporter = true
                } label: {
                    Label("导入工程", systemImage: "square.and.arrow.down")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if let report = spatialStore.lastGLBValidation {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("GLB v\(report.version) 校验通过：\(report.nodeCount) 个独立构件 · \(report.materialCount) 种 PBR 材质 · \(max(1, report.byteCount / 1024)) KB")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            if let localDir = spatialStore.lastExportDirectoryPath {
                Text("已保存至本机目录（不依赖云同步）：\(localDir)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if spatialStore.exportedProjectURL != nil || spatialStore.exportedGLBURL != nil || spatialStore.exportedPlanPDFURL != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let glb = spatialStore.exportedGLBURL {
                            Button {
                                presentLocalFileSaver(url: glb, type: .data)
                            } label: {
                                shareChip("存本机 .glb", icon: "folder.badge.plus", color: .green)
                            }
                            .buttonStyle(.plain)

                            ShareLink(item: glb) {
                                shareChip("分享 .glb", icon: "cube.fill", color: .purple)
                            }
                        }
                        if let tscn = spatialStore.exportedGodotTSCNURL {
                            ShareLink(item: tscn) {
                                shareChip("分享 Godot .tscn", icon: "gamecontroller.fill", color: .orange)
                            }
                        }
                        if let proj = spatialStore.exportedProjectURL {
                            ShareLink(item: proj) {
                                shareChip("分享源工程 .json", icon: "doc.text.fill", color: .indigo)
                            }
                        }
                        if let pdf = spatialStore.exportedPlanPDFURL {
                            ShareLink(item: pdf) {
                                shareChip("分享平面图 .pdf", icon: "map.fill", color: .teal)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    private func presentLocalFileSaver(url: URL, type: UTType) {
        guard let data = try? Data(contentsOf: url) else {
            spatialStore.lastError = "未找到可保存的本地导出文件，请先点击「导出工程文件」。"
            return
        }
        localExportDoc = WuMindBinaryExportDocument(data: data)
        localExportFilename = url.lastPathComponent
        localExportContentType = type
        showingLocalFileExporter = true
    }

    private func shareChip(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color, in: Capsule())
    }

    // MARK: - 7. Dimension Audit Checklist & Outliner Tree

    private var dimensionAuditCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("尺寸核对与待确认清单（3D 与平面图实时同步）", systemImage: "ruler")
                    .font(.caption.weight(.bold))
                Spacer()
                if spatialStore.scene.pendingConfirmationCount > 0 {
                    Text("\(spatialStore.scene.pendingConfirmationCount) 项待补测")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.14), in: Capsule())
                }
            }

            ForEach(spatialStore.scene.dimensionAuditItems) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.status.isPending ? "exclamationmark.triangle.fill" : (item.status == .confirmedMeasured ? "checkmark.circle.fill" : "info.circle.fill"))
                        .font(.caption)
                        .foregroundStyle(item.status.isPending ? .red : (item.status == .confirmedMeasured ? .green : .orange))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(item.label)
                                .font(.caption.weight(.bold))
                            Spacer()
                            Text(item.valueMM.map { "\($0) mm" } ?? "待补测")
                                .font(.caption.weight(.heavy).monospacedDigit())
                                .foregroundStyle(item.status.isPending ? .red : .primary)
                        }
                        Text("\(item.status.label) · \(item.guidance)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .padding(12)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    private var sceneOutlinerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showOutlinerExpanded.toggle() }
            } label: {
                HStack {
                    Label("独立构件层级树（共 \(spatialStore.scene.nodes.count) 项，点击可选中修改）", systemImage: "list.bullet.indent")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: showOutlinerExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showOutlinerExpanded {
                ForEach(spatialStore.scene.nodes) { node in
                    let isSelected = spatialStore.selectedNodeID == node.id
                    Button {
                        spatialStore.selectedNodeID = isSelected ? nil : node.id
                        Haptics.tap()
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(isSelected ? Color.orange : Color.secondary.opacity(0.4))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(node.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("\(node.category.displayName) · \(node.dimensionSummaryText)")
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let roof = node.material.roofPreset {
                                Text(roof.displayName)
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(isSelected ? Color.orange.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
    }

    // MARK: - Helpers

    private var generatingProgressCard: some View {
        HStack(spacing: 10) {
            ProgressView().tint(.orange)
            Text(spatialStore.generationStatus)
                .font(.caption.weight(.semibold))
            Spacer()
        }
        .padding(12)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.orange.opacity(0.4), lineWidth: 1))
    }

    private func statusBanner(text: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .orange : .green)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(11)
        .background((isError ? Color.orange : Color.green).opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func handleImportedReferenceFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let filename = url.lastPathComponent
        if url.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: url) {
            var extracted: [String] = []
            for p in 0..<min(6, doc.pageCount) {
                if let text = doc.page(at: p)?.string {
                    extracted.append(text)
                }
            }
            let joined = extracted.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                stagedDrawingText += "\n" + joined
            }
            if let page0 = doc.page(at: 0) {
                let thumb = page0.thumbnail(of: CGSize(width: 1024, height: 1024), for: .cropBox)
                if let jpeg = thumb.jpegData(compressionQuality: 0.78) {
                    stagedImages.append(AIProviderMessage.ImageAttachment(mimeType: "image/jpeg", base64Data: jpeg.base64EncodedString()))
                }
                spatialStore.analyzeUploadedBlueprint(image: thumb, filename: filename, ocrText: joined.isEmpty ? nil : joined)
            }
            stagedFilenames.append(filename)
            Haptics.success()
        } else if let data = try? Data(contentsOf: url) {
            if let jpeg = Self.normalizedAttachmentJPEG(from: data) {
                stagedImages.append(AIProviderMessage.ImageAttachment(mimeType: "image/jpeg", base64Data: jpeg.base64EncodedString()))
                stagedFilenames.append(filename)
                if let uiImg = UIImage(data: jpeg) {
                    spatialStore.analyzeUploadedBlueprint(image: uiImg, filename: filename, ocrText: stagedDrawingText.isEmpty ? nil : stagedDrawingText)
                }
                Haptics.success()
            } else if let txt = String(data: data, encoding: .utf8) {
                stagedDrawingText += "\n" + txt
                stagedFilenames.append(filename)
                Haptics.success()
            }
        }
    }

    private static func normalizedAttachmentJPEG(from rawData: Data) -> Data? {
        guard let image = UIImage(data: rawData) else { return nil }
        let maxSide: CGFloat = 1024
        let longest = max(image.size.width, image.size.height)
        let scaled: UIImage
        if longest > maxSide, longest > 0 {
            let ratio = maxSide / longest
            let newSize = CGSize(width: (image.size.width * ratio).rounded(), height: (image.size.height * ratio).rounded())
            scaled = UIGraphicsImageRenderer(size: newSize).image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            scaled = image
        }
        return scaled.jpegData(compressionQuality: 0.78)
    }
}

// MARK: - Saved Projects Library Sheet

@MainActor
private struct WuMindSpatialProjectLibrarySheet: View {
    let onImportExternal: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var spatialStore = WuMindSpatial3DStore.shared

    var body: some View {
        NavigationStack {
            List {
                Section("已保存的 3D 空间工程（重开可继续编辑）") {
                    ForEach(spatialStore.savedProjectSummaries, id: \.id) { item in
                        Button {
                            spatialStore.openSavedProject(id: item.id)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("\(item.sceneType.displayName) · \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if spatialStore.scene.id == item.id {
                                    Text("当前").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .accessibilityIdentifier("ai.spatial3d.project.\(item.id.uuidString)")
                        .accessibilityValue(spatialStore.scene.id == item.id ? "当前" : "")
                    }
                    .onDelete { offsets in
                        for idx in offsets {
                            let id = spatialStore.savedProjectSummaries[idx].id
                            if id != spatialStore.scene.id {
                                spatialStore.deleteSavedProject(id: id)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        onImportExternal()
                    } label: {
                        Label("从「文件」导入 .wumind3d.json 工程", systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .navigationTitle("工程库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Optional Tripo 3D Freeform Prop API Settings Sheet

@MainActor
private struct WuMindSpatialTripoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tripoKeyInput = Keychain.tripoAPIKey ?? ""
    @State private var savedBanner: String?

    var body: some View {
        NavigationStack {
            Form {
                if let savedBanner {
                    Section {
                        Label(savedBanner, systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }

                Section("生成自由造型道具（可选）") {
                    SecureField("Tripo API Key (tsk_...)", text: $tripoKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button("保存 Tripo Key") {
                            _ = Keychain.setTripoAPIKey(tripoKeyInput)
                            savedBanner = tripoKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "已清空 Tripo 3D Key。"
                                : "已将 Tripo 3D Key 加密保存至本机 Keychain。"
                            Haptics.success()
                        }
                        .font(.subheadline.weight(.bold))
                        Spacer()
                        if Keychain.tripoAPIKey != nil {
                            Text("已配置").font(.caption.weight(.bold)).foregroundStyle(.green)
                        }
                    }
                }
            }
            .appList()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Tripo 自由造型道具接口")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

/// Offline FileDocument wrapper for saving exported .glb / .tscn / .wumind3d.json / .pdf directly into iOS Files.app.
private struct WuMindBinaryExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .json, .pdf, .plainText] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Secondary browsable 3D Tech Library sheet (`WuMind3DTechRegistry`) covering all 15 authoritative tools across 5 categories,
/// strictly separating `研究候选`, `样例跑通`, and `已接入验收` with official URLs, pinned versions, hardware/cost, and dual licenses.
private struct WuMind3DTechRegistrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var statusFilter: WuMind3DTechStatus? = nil

    private func color(for status: WuMind3DTechStatus) -> Color {
        switch status {
        case .integratedAccepted: return .green
        case .sampleVerified: return .blue
        case .researchCandidate: return .orange
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("最近核对 \(WuMind3DTechRegistry.lastUpdatedDate)").font(DS.Font.caption)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), alignment: .leading)]) {
                            filterChip("全部 (\(WuMind3DTechRegistry.entries.count))", active: statusFilter == nil, tint: .indigo) {
                                statusFilter = nil
                            }
                            ForEach(WuMind3DTechStatus.allCases, id: \.self) { st in
                                filterChip("\(st.badgeText) (\(WuMind3DTechRegistry.count(with: st)))", active: statusFilter == st, tint: color(for: st)) {
                                    statusFilter = st
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                ForEach(WuMind3DTechCategory.allCases) { category in
                    let items = WuMind3DTechRegistry.entries(for: category).filter {
                        statusFilter == nil || $0.status == statusFilter
                    }
                    if !items.isEmpty {
                        Section(category.displayName) {
                            ForEach(items) { entry in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .top, spacing: 8) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.name)
                                                .font(.subheadline.weight(.bold))
                                            Text("版本：\(entry.pinnedVersion) · 核对：\(entry.lastVerifiedDate)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(entry.status.badgeText)
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(color(for: entry.status))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(color(for: entry.status).opacity(0.14), in: Capsule())
                                    }

                                    Text("输入：\(entry.supportedInputs.joined(separator: " / ")) → 输出：\(entry.supportedOutputs.joined(separator: " / "))")
                                        .font(.caption2)
                                        .foregroundStyle(.primary)

                                    Text("算力与成本：\(entry.hardwareAndCost)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("代码许可：\(entry.codeLicense)")
                                        Text("权重/资产许可：\(entry.weightsOrAssetLicense)")
                                        Text("商用：\(entry.commercialUseAllowed ? "允许（须遵守条款）" : "受限") · 原始资产再分发：\(entry.redistributionAllowed ? "允许" : "禁止/受限")")
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                    Text("合规边界：\(entry.complianceNotes)")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)

                                    Text("实测样例：\(entry.testedSampleSummary)")
                                        .font(.caption2)
                                        .foregroundStyle(.teal)

                                    if let url = URL(string: entry.officialURL) {
                                        Link(destination: url) {
                                            Label(entry.officialURL, systemImage: "safari")
                                                .font(.caption2.weight(.medium))
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("3D 技术库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .accessibilityIdentifier("ai.spatial3d.techLibrarySheet")
        }
    }

    private func filterChip(_ title: String, active: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(active ? tint : tint.opacity(0.12), in: Capsule())
                .foregroundStyle(active ? .white : tint)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

