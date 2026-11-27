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
    @Environment(\.dynamicTypeSize) private var typeSize
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

    private var hasExportedFiles: Bool {
        spatialStore.exportedGLBURL != nil || spatialStore.exportedProjectURL != nil
            || spatialStore.exportedPlanPDFURL != nil || spatialStore.exportedGodotTSCNURL != nil
    }

    private var actionColumns: [GridItem] {
        typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 140), spacing: DS.Space.s)]
    }

    private var shouldRenderViewport: Bool {
        scenePhase == .active && !showingMoreTools && !showingWorksHistory && !showingProjectLibrary
            && !showingTechRegistry && !showingTripoSheet && !showingDrawingImporter
            && !showingProjectImporter && !showingLocalFileExporter
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                viewportCard
                sceneCaption
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

                if let blueprintDraft = spatialStore.activeBlueprintDraft {
                    blueprintOverlayReviewCard(blueprintDraft)
                }

                if let selected = spatialStore.selectedNode {
                    selectedNodeInspectorCard(selected)
                }

                if hasExportedFiles { exportDeliverablesCard }
                creationStudioCard
                if !hasExportedFiles { exportDeliverablesCard }

                if !spatialStore.scene.dimensionAuditItems.isEmpty {
                    dimensionAuditCard
                }

                sceneOutlinerCard

            }
            .padding(.horizontal, DS.Space.m)
            .padding(.top, DS.Space.s)
            .padding(.bottom, DS.Space.l)
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

    private var sceneCaption: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(spatialStore.scene.title)
                .font(DS.Font.title)
                .accessibilityAddTraits(.isHeader)
            Text(spatialStore.scene.disclaimerBanner)
                .font(DS.Font.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                            .font(DS.Font.caption.weight(.bold))
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
                        .font(DS.Font.caption.weight(.bold))
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
                                .font(DS.Font.caption.weight(.semibold))
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
                    .font(DS.Font.caption.weight(.bold))
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
                    .font(DS.Font.caption.weight(.semibold))
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
                            Text("待纠正").font(DS.Font.caption.weight(.bold)).foregroundStyle(.orange)
                        } else if op.userCorrected {
                            Text("已纠正").font(DS.Font.caption.weight(.bold)).foregroundStyle(.green)
                        }
                    }
                    if let hint = op.reviewHint {
                        Text(hint).font(DS.Font.caption).foregroundStyle(.secondary)
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
                Label("确认叠图并生成可编辑场景", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
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
        AppSectionCard {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                Text("创建场景").font(DS.Font.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("3D 技术库") { showingTechRegistry = true }
                    .font(DS.Font.caption)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("ai.spatial3d.openTechLibraryChip")
            }
            LabeledContent("创建方式") {
                Picker("创建方式", selection: $createTab) {
                    ForEach(CreateTab.allCases) { tab in Text(tab.rawValue).tag(tab) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            TextField(createTab == .uploadRef ? "补充图纸要求或尺寸" : selectedTaskIntent.defaultPromptPlaceholder,
                      text: $promptInput, axis: .vertical)
                .font(DS.Font.body)
                .lineLimit(3...7)
                .focused($promptFocused)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("场景描述")
                .accessibilityIdentifier("ai.spatial3d.prompt")

            if createTab == .uploadRef {
                referenceInputs
            }

            LabeledContent("用途") {
                Menu(selectedTaskIntent.title) {
                    ForEach(WuMind3DTaskIntent.allCases) { intent in
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
                        } label: { Label(intent.title, systemImage: intent.iconName) }
                    }
                }
            }
            Text(selectedTaskIntent.recommendedRouteSummary)
                .font(DS.Font.caption)
                .foregroundStyle(.secondary)
            LabeledContent("场景类型") {
                Menu(selectedSceneType.displayName) {
                    ForEach(WuMindSpatialSceneType.allCases) { type in
                        Button(type.displayName) { selectedSceneType = type }
                    }
                }
            }

            AppPrimaryCTA(title: "生成 3D 场景", icon: "cube", isLoading: spatialStore.isGenerating) {
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
            }
            .accessibilityIdentifier("ai.spatial3d.generate")

            Divider()
            DisclosureGroup("示例场景") {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Button("赤河镇（可步行）") {
                        selectedTaskIntent = .gameTownWorld
                        selectedSceneType = .gameScene
                        spatialStore.loadAcceptanceCase(0)
                    }
                    Button("户型图厨房与餐区") {
                        selectedTaskIntent = .interiorBIM
                        selectedSceneType = .interiorSpace
                        spatialStore.loadAcceptanceCase(2)
                    }
                    Button("四孔安装板 CAD") {
                        selectedTaskIntent = .cadPartDrawing
                        selectedSceneType = .modernPavilion
                        spatialStore.loadAcceptanceCase(4)
                    }
                    Button("故宫风格宫殿群") {
                        selectedSceneType = .imperialComplex
                        spatialStore.loadAcceptanceCase(1)
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, DS.Space.xs)
            }
        }
    }

    private var referenceInputs: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            LazyVGrid(columns: actionColumns, alignment: .leading, spacing: DS.Space.xs) {
                Button { showingDrawingImporter = true } label: { Label("导入图纸或 PDF", systemImage: "doc.badge.plus") }
                PhotosPicker(selection: $uploadedPhotoItem, matching: .images) {
                    Label("选取参考照片", systemImage: "photo")
                }
                Button("带标尺样图") { spatialStore.loadSampleBlueprintDraft(includeScaleBar: true) }
                Button("无标尺样图") { spatialStore.loadSampleBlueprintDraft(includeScaleBar: false) }
            }
            .buttonStyle(.bordered)
            if !stagedFilenames.isEmpty {
                Text(stagedFilenames.joined(separator: "、")).font(DS.Font.caption)
                Button("清空参考文件", role: .destructive) {
                    stagedImages.removeAll()
                    stagedFilenames.removeAll()
                    stagedDrawingText = ""
                }
            }
            Text("导入后可核对墙线、门窗和比例尺。没有标尺的尺寸会标为估算。")
                .font(DS.Font.caption).foregroundStyle(.secondary)
        }
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

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Button {
                    spatialStore.exportAllDeliverables()
                } label: {
                    Label("导出工程文件", systemImage: "shippingbox")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("ai.spatial3d.export")
                Button { showingProjectImporter = true } label: {
                    Label("导入工程", systemImage: "square.and.arrow.down")
                        .frame(minHeight: 44)
                }
            }
            .buttonStyle(.borderless)

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

            if hasExportedFiles {
                LazyVGrid(columns: actionColumns, alignment: .leading, spacing: DS.Space.xs) {
                    if let glb = spatialStore.exportedGLBURL {
                        Button { presentLocalFileSaver(url: glb, type: .data) } label: {
                            Label("保存 GLB", systemImage: "folder.badge.plus")
                        }
                        ShareLink(item: glb) { Label("分享 GLB", systemImage: "cube") }
                    }
                    if let tscn = spatialStore.exportedGodotTSCNURL {
                        ShareLink(item: tscn) { Label("分享 Godot 场景", systemImage: "gamecontroller") }
                    }
                    if let project = spatialStore.exportedProjectURL {
                        ShareLink(item: project) { Label("分享源工程", systemImage: "doc.text") }
                    }
                    if let pdf = spatialStore.exportedPlanPDFURL {
                        ShareLink(item: pdf) { Label("分享平面图 PDF", systemImage: "map") }
                    }
                }
                .buttonStyle(.bordered)
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

    // MARK: - 7. Dimension Audit Checklist & Outliner Tree

    private var dimensionAuditCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("尺寸核对与待确认清单（3D 与平面图实时同步）", systemImage: "ruler")
                    .font(.caption.weight(.bold))
                Spacer()
                if spatialStore.scene.pendingConfirmationCount > 0 {
                    Text("\(spatialStore.scene.pendingConfirmationCount) 项待补测")
                        .font(DS.Font.caption.weight(.bold))
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
                            .font(DS.Font.caption)
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
                                    .font(DS.Font.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let roof = node.material.roofPreset {
                                Text(roof.displayName)
                                    .font(DS.Font.caption.weight(.semibold))
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
                                            .font(DS.Font.caption.weight(.bold))
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
                .font(DS.Font.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(active ? tint : tint.opacity(0.12), in: Capsule())
                .foregroundStyle(active ? .white : tint)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

