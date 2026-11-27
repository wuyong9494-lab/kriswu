import CoreGraphics
import Foundation
import PDFKit
import UIKit

/// Persistent @MainActor store for WUMIND「AI 3D 空间工坊」.
/// Manages editable scene projects, AI/multimodal generation, surgical single-node editing,
/// undo/redo, lossless `.wumind3d.json` round-trip, multi-node `.glb` export, and dimensioned 2D Plan PDF.
@MainActor
final class WuMindSpatial3DStore: ObservableObject {
    static let shared = WuMindSpatial3DStore()

    struct PerfMetrics: Equatable {
        var fps: Double = 60.0
        var lastBuildMs: Double = 0.0
        var nodeCount: Int = 0
        var deviceModel: String = WuMindSpatial3DStore.currentDeviceModelName()
    }

    @Published var scene: WuMindSpatialSceneDocument
    @Published var savedProjectSummaries: [(id: UUID, title: String, sceneType: WuMindSpatialSceneType, updatedAt: Date)] = []
    @Published var selectedNodeID: UUID?
    @Published var activeCameraPresetID: String?
    @Published var activeFloorFilter: Int? = nil // nil = all floors
    @Published var hideRoofs = false
    @Published var hideExteriorWalls = false
    @Published var isGenerating = false
    @Published var generationStatus = ""
    @Published var lastError: String?
    @Published var lastNotice: String?
    @Published var exportedProjectURL: URL?
    @Published var exportedGLBURL: URL?
    @Published var exportedGodotTSCNURL: URL?
    @Published var lastExportDirectoryPath: String?
    @Published var lastGLBValidation: WuMindSpatialGLBExporter.ValidationReport?
    @Published var lastWalkabilityReport: WuMindSpatial3DEngine.WalkabilityReport?
    @Published var exportedPlanPDFURL: URL?
    @Published var perfMetrics = PerfMetrics()

    /// Active Blueprint-to-3D reviewable overlay state (shown on top of original floorplan before generating 3D).
    @Published var activeBlueprintDraft: WuMindBlueprintToSceneEngine.BlueprintOverlayDraft? = nil
    @Published var activeBlueprintImage: UIImage? = nil
    @Published var selectedBlueprintOpeningID: String? = nil

    /// Incremented whenever the SceneKit scene graph needs a full/incremental refresh.
    @Published var sceneRevision: Int = 0
    /// Incremented when requesting a smooth camera move to `activeCameraPresetID`.
    @Published var cameraCommandRevision: Int = 0
    /// Free-roam delta vector command `(dx, dy, dz)` in meters applied by the viewport.
    @Published var walkDeltaCommand: (id: UUID, dx: Float, dy: Float, dz: Float)?
    /// Linked `WuMindWorksStore` ID so edits create `v2, v3, ...` versions preserving the original scene.
    @Published var activeWorkID: String? = nil

    private var redoStack: [WuMindSpatialSceneSnapshot] = []
    private var generationTask: Task<Void, Never>?

    private init() {
        if let restored = Self.loadLastActiveProject() {
            self.scene = restored
        } else {
            // Default startup scene: flagship Red River Town Western walkable scene (independent landmarks + bridge)
            self.scene = WuMindSpatial3DEngine.buildRedRiverTown()
        }
        self.activeCameraPresetID = self.scene.cameraPresets.first?.id
        self.perfMetrics.nodeCount = self.scene.nodes.count
        if self.scene.sceneType == .gameScene {
            self.lastWalkabilityReport = WuMindSpatial3DEngine.verifyWalkableRoute(scene: self.scene)
        }
        self.persistCurrentScene()
        self.refreshProjectIndex()
    }

    var selectedNode: WuMindSpatialNode? {
        guard let id = selectedNodeID else { return nil }
        return scene.nodes.first(where: { $0.id == id })
    }

    var canUndo: Bool { !scene.savedVersions.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Scene Generation (Text Description / Uploaded Drawing / Hybrid)

    func generateScene(
        prompt: String,
        sceneType: WuMindSpatialSceneType,
        creationMode: WuMindSpatialCreationMode,
        referenceImages: [AIProviderMessage.ImageAttachment],
        referenceFilenames: [String],
        extractedDrawingText: String?,
        using chatStore: WuMindStore,
        preferDirectParametric: Bool = false
    ) {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty || !referenceImages.isEmpty || !(extractedDrawingText ?? "").isEmpty else {
            lastError = "请输入一段空间描述，或上传户型图 / 草图 / 照片 / PDF。"
            return
        }

        generationTask?.cancel()
        lastError = nil
        lastNotice = nil
        clearTransientExports()

        if preferDirectParametric {
            let built = WuMindSpatial3DEngine.synthesizeParametricScene(
                prompt: cleanPrompt,
                preferredType: sceneType,
                creationMode: creationMode,
                referenceFilenames: referenceFilenames,
                extractedDrawingText: extractedDrawingText
            )
            lastWalkabilityReport = built.sceneType == .gameScene
                ? WuMindSpatial3DEngine.verifyWalkableRoute(scene: built)
                : nil
            commitNewScene(built, notice: "已生成「\(built.title)」（\(built.nodes.count) 个独立可编辑构件）。")
            return
        }

        isGenerating = true
        generationStatus = "正在用 WUMIND 构思独立可拆 3D 空间构件与尺寸结构…"
        let effectivePrompt = cleanPrompt.isEmpty ? "根据上传图纸与参考图片生成可编辑 3D 空间工程" : cleanPrompt

        generationTask = Task { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.isGenerating = false
                    self?.generationStatus = ""
                }
            }
            do {
                let sys = WuMindSpatial3DEngine.sceneGenerationSystemPrompt(
                    prompt: effectivePrompt,
                    sceneType: sceneType,
                    creationMode: creationMode,
                    hasReferenceImages: !referenceImages.isEmpty,
                    extractedDrawingText: extractedDrawingText
                )
                guard referenceImages.isEmpty || chatStore.activeModelCapabilities.visionAttachments else {
                    self?.lastError = "当前模型不支持发送参考图片。请选择支持图片输入的模型，或移除图片。"
                    return
                }
                let userMsg = AIProviderMessage(
                    role: .user,
                    text: effectivePrompt,
                    images: referenceImages
                )
                let res = try await chatStore.runStatelessChat(
                    messages: [userMsg],
                    systemPrompt: sys,
                    deepThinking: false,
                    onAnswerDelta: { [weak self] partial in
                        self?.generationStatus = "正在输出可编辑 3D 空间结构 JSON（已生成 \(partial.count) 字）…"
                    }
                )
                try Task.checkCancellation()
                guard let self else { return }
                guard let built = WuMindSpatial3DEngine.parseGeneratedScene(
                    rawLLMOutput: res.answer,
                    sourcePrompt: effectivePrompt,
                    preferredType: sceneType,
                    creationMode: creationMode,
                    referenceFilenames: referenceFilenames
                ) else {
                    self.lastError = "模型未返回符合描述的可编辑场景，已保留当前工程。"
                    return
                }
                self.lastWalkabilityReport = built.sceneType == .gameScene
                    ? WuMindSpatial3DEngine.verifyWalkableRoute(scene: built)
                    : nil
                self.commitNewScene(built, notice: "已通过 WUMIND 生成「\(built.title)」（\(built.nodes.count) 个独立可选构件）。")
            } catch is CancellationError {
                // Cancelled cleanly
            } catch {
                guard let self else { return }
                self.lastError = "生成失败：" + MultiProviderAIClient.redactSecrets(in: error.localizedDescription)
            }
        }
    }

    /// Loads one of the official acceptance scenarios directly through the real parametric compiler.
    func loadAcceptanceCase(_ caseIndex: Int) {
        switch caseIndex {
        case 0:
            generateScene(
                prompt: "生成一个叫「赤河镇」的西部小镇，有赤河河道、木石主桥、赤河火车站与铁轨、西部酒馆，主街从酒馆过桥走到火车站",
                sceneType: .gameScene,
                creationMode: .textDescription,
                referenceImages: [],
                referenceFilenames: [],
                extractedDrawingText: nil,
                using: WuMindStore.shared,
                preferDirectParametric: true
            )
        case 1:
            generateScene(
                prompt: "从空白项目生成一座故宫风格可漫游宫殿建筑群，有南北贯通中轴、多进院落、太和殿主殿和东西配殿、午门与神武门城墙门楼、金水河水面和道路",
                sceneType: .imperialComplex,
                creationMode: .textDescription,
                referenceImages: [],
                referenceFilenames: [],
                extractedDrawingText: nil,
                using: WuMindStore.shared,
                preferDirectParametric: true
            )
        case 2:
            generateScene(
                prompt: "上传户型图生成厨房+餐区室内空间，北墙 5200mm，进深 4400mm，地柜宽 2400mm，净高 2800mm",
                sceneType: .interiorSpace,
                creationMode: .uploadAndText,
                referenceImages: [],
                referenceFilenames: ["厨房餐区实测户型图.pdf"],
                extractedDrawingText: "北墙 5200mm 进深 4400mm 地柜宽 2400mm 净高 2800mm",
                using: WuMindStore.shared,
                preferDirectParametric: true
            )
        case 4:
            generateScene(
                prompt: "生成一块 160×120×10mm 带四个 Ø10 安装孔的金属安装板 CAD 样例，横向孔距 120mm，纵向孔距 80mm",
                sceneType: .modernPavilion,
                creationMode: .textDescription,
                referenceImages: [],
                referenceFilenames: [],
                extractedDrawingText: nil,
                using: WuMindStore.shared,
                preferDirectParametric: true
            )
        default:
            generateScene(
                prompt: "做一个现代滨水艺术展馆，悬挑白色清水混凝土屋面，整面低反玻璃幕墙，亲水木栈道与中央圆形主展台",
                sceneType: .modernPavilion,
                creationMode: .uploadAndText,
                referenceImages: [],
                referenceFilenames: ["滨水展馆草图.png"],
                extractedDrawingText: nil,
                using: WuMindStore.shared,
                preferDirectParametric: true
            )
        }
    }

    // MARK: - Blueprint-to-Editable-3D-Scene Workflow (Overlay -> Tap Correct -> Compile Shared Scene Format)

    /// Analyzes an uploaded floorplan image natively using CoreGraphics pixel extraction (zero external CLI deps)
    /// and prepares a reviewable overlay directly on top of the original image BEFORE generating 3D geometry.
    func analyzeUploadedBlueprint(image: UIImage, filename: String, ocrText: String? = nil) {
        let maxW = 540
        let srcW = max(1, Int(image.size.width))
        let srcH = max(1, Int(image.size.height))
        let scale = srcW > maxW ? (Double(maxW) / Double(srcW)) : 1.0
        let targetW = max(64, Int((Double(srcW) * scale).rounded()))
        let targetH = max(64, Int((Double(srcH) * scale).rounded()))

        var rgba = [UInt8](repeating: 255, count: targetW * targetH * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        rgba.withUnsafeMutableBytes { ptr in
            if let base = ptr.baseAddress,
               let ctx = CGContext(
                   data: base,
                   width: targetW,
                   height: targetH,
                   bitsPerComponent: 8,
                   bytesPerRow: targetW * 4,
                   space: colorSpace,
                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
               ),
               let cg = image.cgImage {
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: targetW, height: targetH))
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
            }
        }

        var lum = [UInt8](repeating: 255, count: targetW * targetH)
        var sat = [UInt8](repeating: 0, count: targetW * targetH)
        for i in 0..<(targetW * targetH) {
            let r = Int(rgba[i * 4])
            let g = Int(rgba[i * 4 + 1])
            let b = Int(rgba[i * 4 + 2])
            lum[i] = UInt8((r * 299 + g * 587 + b * 114) / 1000)
            sat[i] = UInt8(max(r, max(g, b)) - min(r, min(g, b)))
        }

        let draft = WuMindBlueprintToSceneEngine.analyzeFloorplanPixels(
            luminance: lum,
            saturation: sat,
            width: targetW,
            height: targetH,
            sourceFilename: filename,
            extractedOCRText: ocrText
        )
        activeBlueprintImage = image
        activeBlueprintDraft = draft
        selectedBlueprintOpeningID = draft.openings.first(where: { $0.needsUserReview })?.id ?? draft.openings.first?.id
        lastNotice = "已叠图识别「\(filename)」：\(draft.scaleCalibration.statusBadge)，墙体 \(draft.walls.count) 段、门窗 \(draft.openings.count) 处，请点选核对后生成 3D。"
        lastError = nil
        Haptics.success()
    }

    /// Loads either the scale-bar or stripped-scale-bar apartment floorplan sample for interactive overlay review.
    func loadSampleBlueprintDraft(includeScaleBar: Bool) {
        let draft = WuMindBlueprintToSceneEngine.makeInteractiveSampleDraft(includeScaleBar: includeScaleBar)
        activeBlueprintImage = Self.renderSampleBlueprintImage(draft: draft, includeScaleBar: includeScaleBar)
        activeBlueprintDraft = draft
        selectedBlueprintOpeningID = draft.openings.first(where: { $0.needsUserReview })?.id ?? draft.openings.first?.id
        lastNotice = includeScaleBar
            ? "已载入带标尺户型图叠加预览：检测到 1 处误判门洞，点击橙色框纠正后即可生成独立 3D 场景。"
            : "已载入无标尺户型图副本：系统已自动将全部墙体与门窗标为「估算」，不会编造精确毫米值。"
        lastError = nil
        Haptics.tap()
    }

    func correctBlueprintOpening(
        openingID: String,
        newKind: WuMindBlueprintToSceneEngine.OpeningKind? = nil,
        newName: String? = nil,
        deltaWidthMM: Int? = nil
    ) {
        guard var draft = activeBlueprintDraft,
              let cur = draft.openings.first(where: { $0.id == openingID }) else { return }
        let updatedWidth = deltaWidthMM.map { max(600, cur.widthMM + $0) }
        if WuMindBlueprintToSceneEngine.correctOpening(
            draft: &draft,
            openingID: openingID,
            newKind: newKind,
            newName: newName,
            newWidthMM: updatedWidth
        ) {
            activeBlueprintDraft = draft
            lastNotice = "已纠正叠加层门窗「\(newName ?? cur.name)」，确认无误后点击生成 3D 场景。"
            Haptics.success()
        }
    }

    func confirmBlueprintAndBuildScene() {
        guard var draft = activeBlueprintDraft else { return }
        draft.isConfirmedFor3D = true
        activeBlueprintDraft = draft
        let built = WuMindBlueprintToSceneEngine.compileToEditableScene(draft: draft)
        let doorNode = built.nodes.first(where: { $0.wallOpeningRole == "opening_door" })
        commitNewScene(
            built,
            notice: "已由图纸叠加确认生成「\(built.title)」（\(built.nodes.count) 个独立墙体/门框/门窗/家具构件），与文字建模共用同一工程格式。"
        )
        selectedNodeID = doorNode?.id
    }

    func dismissBlueprintDraft() {
        activeBlueprintDraft = nil
        activeBlueprintImage = nil
        selectedBlueprintOpeningID = nil
    }

    private static func renderSampleBlueprintImage(
        draft: WuMindBlueprintToSceneEngine.BlueprintOverlayDraft,
        includeScaleBar: Bool
    ) -> UIImage {
        let size = CGSize(width: 960, height: 720)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            UIColor(white: 0.985, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // Subtle architectural blueprint grid
            UIColor(white: 0.92, alpha: 1).setStroke()
            cg.setLineWidth(0.75)
            for x in stride(from: CGFloat(0), through: size.width, by: 40) {
                cg.move(to: CGPoint(x: x, y: 0))
                cg.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: CGFloat(0), through: size.height, by: 40) {
                cg.move(to: CGPoint(x: 0, y: y))
                cg.addLine(to: CGPoint(x: size.width, y: y))
            }
            cg.strokePath()

            // Room labels
            for room in draft.rooms {
                let rect = CGRect(
                    x: room.rect.x0 * size.width,
                    y: room.rect.y0 * size.height,
                    width: room.rect.width * size.width,
                    height: room.rect.height * size.height
                )
                UIColor(white: 0.955, alpha: 0.85).setFill()
                cg.fill(rect)
                room.name.draw(
                    at: CGPoint(x: rect.midX - 36, y: rect.midY - 8),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: UIColor(white: 0.42, alpha: 1)]
                )
            }

            // Solid filled architectural walls
            UIColor(white: 0.24, alpha: 1).setFill()
            for wall in draft.walls {
                let r = CGRect(
                    x: wall.rect.x0 * size.width,
                    y: wall.rect.y0 * size.height,
                    width: max(4, wall.rect.width * size.width),
                    height: max(4, wall.rect.height * size.height)
                )
                cg.fill(r)
            }

            // Footer scale bar ONLY when `includeScaleBar == true`
            if includeScaleBar, let bar = draft.scaleCalibration.scaleBarOverlayRect {
                let r = CGRect(
                    x: bar.x0 * size.width,
                    y: bar.y0 * size.height,
                    width: bar.width * size.width,
                    height: max(8, bar.height * size.height)
                )
                UIColor(white: 0.12, alpha: 1).setFill()
                cg.fill(r)
                "0m            2.5m            5m (比例尺 1:100)".draw(
                    at: CGPoint(x: r.minX, y: r.maxY + 4),
                    withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 13, weight: .bold), .foregroundColor: UIColor(white: 0.15, alpha: 1)]
                )
            }
        }
    }

    private func commitNewScene(_ built: WuMindSpatialSceneDocument, notice: String, linkedWorkID: String? = nil) {
        redoStack.removeAll()
        scene = built
        selectedNodeID = nil
        activeFloorFilter = nil
        hideRoofs = false
        hideExteriorWalls = false
        activeCameraPresetID = built.cameraPresets.first?.id
        sceneRevision += 1
        cameraCommandRevision += 1
        lastNotice = notice
        lastError = nil
        persistCurrentScene()
        refreshProjectIndex()
        if let linkedWorkID {
            activeWorkID = linkedWorkID
        } else {
            archiveSceneInWorksStore(asNewVersion: false, glbData: nil, editSummary: nil)
        }
        Haptics.success()
    }

    // MARK: - Surgical Editing, Weather, Camera, Undo/Redo

    func setWeather(_ weather: WuMindSpatialWeather) {
        guard scene.weather != weather else { return }
        scene.weather = weather
        scene.updatedAt = Date()
        sceneRevision += 1
        persistCurrentScene()
        Haptics.tap()
    }

    func focusCameraPreset(_ preset: WuMindSpatialCameraPreset) {
        activeCameraPresetID = preset.id
        cameraCommandRevision += 1
        Haptics.tap()
    }

    func stepFreeWalk(dx: Float, dy: Float, dz: Float) {
        walkDeltaCommand = (UUID(), dx, dy, dz)
    }

    func applyNaturalLanguageEditToSelected(_ instruction: String) {
        guard let sid = selectedNodeID else {
            lastError = "请先在 3D 视图或构件树中点选要修改的单个建筑或构件。"
            return
        }
        let outcome = WuMindSpatial3DEngine.applyNaturalLanguageEdit(
            scene: scene,
            nodeID: sid,
            instruction: instruction
        )
        redoStack.removeAll()
        scene = outcome.updatedScene
        sceneRevision += 1
        lastError = nil
        lastNotice = outcome.summary
        clearTransientExports()
        persistCurrentScene()
        refreshProjectIndex()
        archiveSceneInWorksStore(asNewVersion: true, glbData: nil, editSummary: instruction)
        Haptics.success()
    }

    func patchSelectedNode(
        sizeDeltaMM: WuMindVec3MM? = nil,
        positionDeltaMM: WuMindVec3MM? = nil,
        roofPreset: WuMindSpatialMaterialPreset? = nil,
        bodyPreset: WuMindSpatialMaterialPreset? = nil,
        label: String
    ) {
        guard let sid = selectedNodeID else { return }
        redoStack.removeAll()
        scene = WuMindSpatial3DEngine.applyExactNodePatch(
            scene: scene,
            nodeID: sid,
            sizeDeltaMM: sizeDeltaMM,
            positionDeltaMM: positionDeltaMM,
            roofPreset: roofPreset,
            bodyPreset: bodyPreset,
            label: label
        )
        sceneRevision += 1
        lastError = nil
        if let updated = selectedNode {
            lastNotice = "已更新「\(updated.name)」（\(updated.dimensionSummaryText)），其余构件不动。"
        }
        clearTransientExports()
        persistCurrentScene()
        refreshProjectIndex()
        archiveSceneInWorksStore(asNewVersion: true, glbData: nil, editSummary: label)
        Haptics.tap()
    }

    func undo() {
        let currentSnap = WuMindSpatialSceneSnapshot(label: "撤销前状态", nodes: scene.nodes, weather: scene.weather)
        guard let previous = WuMindSpatial3DEngine.undo(scene: scene) else { return }
        redoStack.append(currentSnap)
        scene = previous
        sceneRevision += 1
        lastNotice = "已撤销上一步修改。"
        clearTransientExports()
        persistCurrentScene()
        Haptics.tap()
    }

    func redo() {
        guard let forward = redoStack.popLast() else { return }
        let backSnap = WuMindSpatialSceneSnapshot(label: "重做前状态", nodes: scene.nodes, weather: scene.weather)
        scene.savedVersions.append(backSnap)
        scene.nodes = forward.nodes
        scene.weather = forward.weather
        scene.updatedAt = Date()
        sceneRevision += 1
        lastNotice = "已重做修改。"
        clearTransientExports()
        persistCurrentScene()
        Haptics.tap()
    }

    // MARK: - Persistent Offline Local Exports (.wumind3d.json + Validated .glb + Godot 4 .tscn + Dimensioned Plan PDF)

    /// Exports all deliverables locally into persistent `Documents/WuMindSpatial3D/Exports/` so users
    /// can always save/share/open files in Files.app or external engines WITHOUT depending on cloud sync.
    func exportAllDeliverables() {
        lastError = nil
        let safeName = Self.sanitizedFilename(scene.title)
        let folder = Self.exportsDir(create: true)
            .appendingPathComponent("\(safeName)_\(scene.id.uuidString.prefix(8))", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            // 1. Lossless re-importable native source project JSON (.wumind3d.json)
            let projectData = try WuMindSpatial3DEngine.encodeProjectJSON(scene)
            let projectURL = folder.appendingPathComponent("\(safeName).wumind3d.json")
            try projectData.write(to: projectURL, options: [.atomic])
            exportedProjectURL = projectURL

            // 2. Real binary glTF 2.0 (.glb) with validation
            let glbFilename = "\(safeName).glb"
            let glbData = try WuMindSpatialGLBExporter.exportGLB(scene: scene)
            let report = try WuMindSpatialGLBExporter.validateGLB(glbData)
            let glbURL = folder.appendingPathComponent(glbFilename)
            try glbData.write(to: glbURL, options: [.atomic])
            exportedGLBURL = glbURL
            lastGLBValidation = report

            // 3. Godot 4 .tscn scene with StaticBody3D colliders referencing the exported .glb
            let tscnString = WuMindSpatial3DEngine.exportGodotSceneTSCN(scene: scene, glbFilename: glbFilename)
            let tscnURL = folder.appendingPathComponent("\(safeName).tscn")
            try Data(tscnString.utf8).write(to: tscnURL, options: [.atomic])
            exportedGodotTSCNURL = tscnURL

            // 4. Dimensioned 2D Architectural Floor Plan PDF
            let pdfURL = folder.appendingPathComponent("\(safeName)_平面标注图.pdf")
            try WuMindSpatialPlanPDFRenderer.renderPlanPDF(scene: scene, to: pdfURL)
            exportedPlanPDFURL = pdfURL

            lastExportDirectoryPath = "本地文件/WuMindSpatial3D/Exports/\(folder.lastPathComponent)"

            if scene.sceneType == .gameScene {
                lastWalkabilityReport = WuMindSpatial3DEngine.verifyWalkableRoute(scene: scene)
            }

            // Local export is ALREADY complete and independent of cloud sync; optionally log locally in Works.
            archiveSceneInWorksStore(asNewVersion: false, glbData: glbData, editSummary: nil)

            lastNotice = "已完成离线本地导出（不依赖云同步）：.wumind3d.json 源工程 + 校验 .glb（\(report.nodeCount) 节点 · \(max(1, report.byteCount / 1024)) KB）+ Godot 4 .tscn + 平面图 PDF。"
            Haptics.success()
        } catch {
            lastError = "本地导出失败：\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            Haptics.warning()
        }
    }

    func openProjectJSON(_ json: String, linkedWorkID: String? = nil) {
        guard let data = json.data(using: .utf8),
              let loaded = try? WuMindSpatial3DEngine.decodeProjectJSON(data) else {
            lastError = "未能读取该历史 3D 工程文件。"
            return
        }
        commitNewScene(
            loaded,
            notice: "已从「我的作品」重开 3D 工程「\(loaded.title)」（\(loaded.nodes.count) 个可编辑构件），修改将保存为新版本并保留原版。",
            linkedWorkID: linkedWorkID
        )
    }

    private func archiveSceneInWorksStore(asNewVersion: Bool, glbData: Data?, editSummary: String?) {
        guard let projData = try? WuMindSpatial3DEngine.encodeProjectJSON(scene),
              let projJSON = String(data: projData, encoding: .utf8) else {
            return
        }
        let works = WuMindWorksStore.shared
        let summaryPrompt = editSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? "\(scene.sourcePrompt)｜编辑：\(editSummary!)"
            : scene.sourcePrompt
        if asNewVersion, let parentID = activeWorkID {
            if let child = works.saveEditedVersion(
                from: parentID,
                title: scene.title,
                prompt: summaryPrompt,
                assetData: glbData,
                assetMime: glbData != nil ? "model/gltf-binary" : nil,
                assetExtension: glbData != nil ? "glb" : nil,
                projectJSON: projJSON
            ) {
                activeWorkID = child.id
                return
            }
        }
        if !asNewVersion, let existingID = activeWorkID, glbData != nil {
            if works.completeWork(
                id: existingID,
                title: scene.title,
                assetData: glbData,
                assetMime: "model/gltf-binary",
                assetExtension: "glb",
                projectJSON: projJSON
            ) != nil {
                return
            }
        }
        let created = works.recordSubmittedTask(
            workType: .scene3d,
            title: scene.title,
            prompt: summaryPrompt,
            modelID: "wumind-spatial-3d",
            params: [
                "sceneType": scene.sceneType.rawValue,
                "nodeCount": "\(scene.nodes.count)",
                "weather": scene.weather.rawValue,
            ],
            status: "completed",
            progress: 100
        )
        _ = works.completeWork(
            id: created.id,
            title: scene.title,
            assetData: glbData,
            assetMime: glbData != nil ? "model/gltf-binary" : nil,
            assetExtension: glbData != nil ? "glb" : nil,
            projectJSON: projJSON
        )
        activeWorkID = created.id
    }

    func importProjectFile(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let loaded = try WuMindSpatial3DEngine.decodeProjectJSON(data)
            commitNewScene(loaded, notice: "已成功重开工程「\(loaded.title)」（\(loaded.nodes.count) 个可编辑构件）。")
        } catch {
            lastError = "无法导入该工程文件：\(error.localizedDescription)"
            Haptics.warning()
        }
    }

    func openSavedProject(id: UUID) {
        let url = Self.projectsDir(create: false).appendingPathComponent("\(id.uuidString).wumind3d.json")
        guard let data = try? Data(contentsOf: url),
              let loaded = try? WuMindSpatial3DEngine.decodeProjectJSON(data) else {
            lastError = "未能读取该已保存工程。"
            return
        }
        commitNewScene(loaded, notice: "已重新打开工程「\(loaded.title)」，可继续编辑。")
    }

    func deleteSavedProject(id: UUID) {
        let url = Self.projectsDir(create: false).appendingPathComponent("\(id.uuidString).wumind3d.json")
        try? FileManager.default.removeItem(at: url)
        refreshProjectIndex()
    }

    private func clearTransientExports() {
        exportedProjectURL = nil
        exportedGLBURL = nil
        exportedGodotTSCNURL = nil
        lastExportDirectoryPath = nil
        lastGLBValidation = nil
        exportedPlanPDFURL = nil
    }

    private static func exportsDir(create: Bool) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? rootDir(create: create)
        let dir = docs
            .appendingPathComponent("WuMindSpatial3D", isDirectory: true)
            .appendingPathComponent("Exports", isDirectory: true)
        if create { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        return dir
    }

    // MARK: - Persistence Helpers

    private func persistCurrentScene() {
        guard let data = try? WuMindSpatial3DEngine.encodeProjectJSON(scene) else { return }
        let projURL = Self.projectsDir(create: true).appendingPathComponent("\(scene.id.uuidString).wumind3d.json")
        try? data.write(to: projURL, options: [.atomic, .completeFileProtection])
        let lastURL = Self.rootDir(create: true).appendingPathComponent("last_active_id.txt")
        try? Data(scene.id.uuidString.utf8).write(to: lastURL, options: [.atomic])
    }

    private func refreshProjectIndex() {
        let dir = Self.projectsDir(create: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            savedProjectSummaries = []
            return
        }
        var items: [(id: UUID, title: String, sceneType: WuMindSpatialSceneType, updatedAt: Date)] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let doc = try? WuMindSpatial3DEngine.decodeProjectJSON(data) {
                items.append((doc.id, doc.title, doc.sceneType, doc.updatedAt))
            }
        }
        savedProjectSummaries = items.sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func loadLastActiveProject() -> WuMindSpatialSceneDocument? {
        let lastURL = rootDir(create: false).appendingPathComponent("last_active_id.txt")
        guard let rawID = try? String(contentsOf: lastURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let uuid = UUID(uuidString: rawID) else {
            return nil
        }
        let projURL = projectsDir(create: false).appendingPathComponent("\(uuid.uuidString).wumind3d.json")
        guard let data = try? Data(contentsOf: projURL) else { return nil }
        return try? WuMindSpatial3DEngine.decodeProjectJSON(data)
    }

    private static func rootDir(create: Bool) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("WuMindSpatial3D", isDirectory: true)
        if create { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        return dir
    }

    private static func projectsDir(create: Bool) -> URL {
        let dir = rootDir(create: create).appendingPathComponent("Projects", isDirectory: true)
        if create { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        return dir
    }

    private static func sanitizedFilename(_ raw: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t ")
        let clean = raw.components(separatedBy: bad).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "WUMIND_3D" : String(clean.prefix(28))
    }

    nonisolated static func currentDeviceModelName() -> String {
        var sys = utsname()
        uname(&sys)
        let mirror = Mirror(reflecting: sys.machine)
        let id = mirror.children.reduce(into: "") { acc, el in
            if let v = el.value as? Int8, v != 0 {
                acc.append(Character(UnicodeScalar(UInt8(v))))
            }
        }
        return id.isEmpty ? "iOS Device" : id
    }
}

// MARK: - Dimensioned 2D Architectural Plan PDF Renderer (Synced with Live 3D Nodes!)

enum WuMindSpatialPlanPDFRenderer {

    @MainActor
    static func renderPlanPDF(scene: WuMindSpatialSceneDocument, to outputURL: URL) throws {
        let pageRect = CGRect(x: 0, y: 0, width: 842, height: 595) // Landscape A4
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            let cg = ctx.cgContext

            // Clean architectural white paper
            UIColor.white.setFill()
            cg.fill(pageRect)

            // Outer frame
            let borderRect = pageRect.insetBy(dx: 24, dy: 24)
            UIColor(white: 0.18, alpha: 1).setStroke()
            cg.setLineWidth(1.2)
            cg.stroke(borderRect)

            // Title bar
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: UIColor(white: 0.1, alpha: 1),
            ]
            "WUMIND AI 3D 空间工坊 · 平面尺寸标注图｜\(scene.title)".draw(
                in: CGRect(x: 38, y: 34, width: 540, height: 24),
                withAttributes: titleAttrs
            )

            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9.5, weight: .medium),
                .foregroundColor: UIColor(red: 0.72, green: 0.22, blue: 0.12, alpha: 1),
            ]
            "\(scene.disclaimerBanner) · 单位：毫米 (mm)".draw(
                in: CGRect(x: 38, y: 58, width: 760, height: 16),
                withAttributes: subAttrs
            )

            // Plan drawing canvas on left (540 x 470)
            let canvasRect = CGRect(x: 38, y: 84, width: 540, height: 470)
            UIColor(white: 0.975, alpha: 1).setFill()
            cg.fill(canvasRect)
            UIColor(white: 0.80, alpha: 1).setStroke()
            cg.setLineWidth(0.8)
            cg.stroke(canvasRect)

            let planNodes = scene.nodes.filter { $0.isVisible && $0.category != .roof }
            if !planNodes.isEmpty {
                var minX = Double.greatestFiniteMagnitude
                var maxX = -Double.greatestFiniteMagnitude
                var minZ = Double.greatestFiniteMagnitude
                var maxZ = -Double.greatestFiniteMagnitude

                for n in planNodes {
                    let hx = Double(n.sizeMM.x) / 2.0
                    let hz = Double(n.sizeMM.z) / 2.0
                    minX = min(minX, Double(n.positionMM.x) - hx)
                    maxX = max(maxX, Double(n.positionMM.x) + hx)
                    minZ = min(minZ, Double(n.positionMM.z) - hz)
                    maxZ = max(maxZ, Double(n.positionMM.z) + hz)
                }

                let worldW = max(1_000, maxX - minX)
                let worldD = max(1_000, maxZ - minZ)
                let pad: CGFloat = 44
                let scale = min(Double(canvasRect.width - pad * 2) / worldW, Double(canvasRect.height - pad * 2) / worldD)
                let drawW = CGFloat(worldW * scale)
                let drawD = CGFloat(worldD * scale)
                let originX = canvasRect.minX + (canvasRect.width - drawW) / 2
                let originY = canvasRect.minY + (canvasRect.height - drawD) / 2

                func mapRect(_ n: WuMindSpatialNode) -> CGRect {
                    let x0 = (Double(n.positionMM.x) - Double(n.sizeMM.x) / 2.0 - minX) * scale
                    let z0 = (Double(n.positionMM.z) - Double(n.sizeMM.z) / 2.0 - minZ) * scale
                    let w = max(2.0, Double(n.sizeMM.x) * scale)
                    let d = max(2.0, Double(n.sizeMM.z) * scale)
                    return CGRect(x: originX + CGFloat(x0), y: originY + CGFloat(z0), width: CGFloat(w), height: CGFloat(d))
                }

                // Draw background layers first (courtyards/slabs/water/roads), then architecture/cabinets
                let ordered = planNodes.sorted { priority(for: $0.category) < priority(for: $1.category) }
                for node in ordered {
                    let r = mapRect(node)
                    let fill = planFillColor(for: node)
                    fill.setFill()
                    if node.detailProfile.isCylindrical {
                        let path = UIBezierPath(ovalIn: r)
                        path.fill()
                        UIColor(white: 0.20, alpha: 0.85).setStroke()
                        path.lineWidth = 1.0
                        path.stroke()
                    } else {
                        cg.fill(r)
                        UIColor(white: 0.22, alpha: 0.85).setStroke()
                        cg.setLineWidth(node.category == .wall || node.category == .cityWall ? 1.4 : 0.8)
                        cg.stroke(r)
                    }

                    // Label key architectural / cabinet nodes + exact millimeter width callout
                    if shouldLabelOnPlan(node) && r.width > 24 && r.height > 12 {
                        let label = "\(node.name)\n\(node.sizeMM.x)×\(node.sizeMM.z)mm"
                        let style = NSMutableParagraphStyle()
                        style.alignment = .center
                        label.draw(
                            in: r.insetBy(dx: 2, dy: 2),
                            withAttributes: [
                                .font: UIFont.systemFont(ofSize: 7.5, weight: .bold),
                                .foregroundColor: UIColor(white: 0.08, alpha: 1),
                                .paragraphStyle: style,
                            ]
                        )
                    }
                }

                // Overall horizontal & vertical architectural dimension chains
                drawDimensionLine(
                    in: cg,
                    from: CGPoint(x: originX, y: originY - 16),
                    to: CGPoint(x: originX + drawW, y: originY - 16),
                    text: "总宽 \(Int(worldW.rounded())) mm"
                )
                drawDimensionLine(
                    in: cg,
                    from: CGPoint(x: originX - 18, y: originY),
                    to: CGPoint(x: originX - 18, y: originY + drawD),
                    text: "\(Int(worldD.rounded()))mm"
                )
            }

            // Right sidebar: Dimension Audit Table & Node Schedule
            let sideX: CGFloat = 594
            let sideW: CGFloat = 212
            "尺寸核对与关键构件清单".draw(
                in: CGRect(x: sideX, y: 84, width: sideW, height: 18),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: UIColor(white: 0.1, alpha: 1),
                ]
            )

            var yCursor: CGFloat = 108
            for item in scene.dimensionAuditItems.prefix(8) {
                let valStr = item.valueMM.map { "\($0) mm" } ?? "待现场补测"
                let color: UIColor = item.status.isPending
                    ? UIColor(red: 0.78, green: 0.16, blue: 0.12, alpha: 1)
                    : (item.status == .confirmedMeasured ? UIColor(red: 0.08, green: 0.45, blue: 0.22, alpha: 1) : UIColor(white: 0.30, alpha: 1))
                "• \(item.label)：\(valStr)".draw(
                    in: CGRect(x: sideX, y: yCursor, width: sideW, height: 15),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: color]
                )
                yCursor += 14
                "  [\(item.status.label)]".draw(
                    in: CGRect(x: sideX, y: yCursor, width: sideW, height: 13),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor(white: 0.42, alpha: 1)]
                )
                yCursor += 16
            }

            yCursor += 8
            "主要独立构件（共 \(scene.nodes.count) 项）".draw(
                in: CGRect(x: sideX, y: yCursor, width: sideW, height: 16),
                withAttributes: [.font: UIFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: UIColor(white: 0.15, alpha: 1)]
            )
            yCursor += 18

            for node in scene.nodes.prefix(12) where yCursor < 536 {
                let line = "\(node.name) · \(node.sizeMM.x)×\(node.sizeMM.z)×\(node.sizeMM.y)mm"
                line.draw(
                    in: CGRect(x: sideX, y: yCursor, width: sideW, height: 14),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor(white: 0.25, alpha: 1)]
                )
                yCursor += 14
            }
        }

        try data.write(to: outputURL, options: [.atomic, .completeFileProtection])
    }

    private static func priority(for cat: WuMindSpatialNodeCategory) -> Int {
        switch cat {
        case .courtyard, .floorSlab: return 0
        case .waterway, .road: return 1
        case .wall, .cityWall: return 2
        case .palaceHall, .gateTower, .exhibitStage, .cabinet, .furniture, .stairs: return 3
        default: return 4
        }
    }

    private static func shouldLabelOnPlan(_ node: WuMindSpatialNode) -> Bool {
        switch node.category {
        case .palaceHall, .gateTower, .cabinet, .furniture, .exhibitStage, .door: return true
        default: return false
        }
    }

    private static func planFillColor(for node: WuMindSpatialNode) -> UIColor {
        switch node.category {
        case .waterway: return UIColor(red: 0.72, green: 0.88, blue: 0.94, alpha: 1)
        case .courtyard, .floorSlab: return UIColor(white: 0.93, alpha: 1)
        case .road: return UIColor(white: 0.88, alpha: 1)
        case .palaceHall, .gateTower: return UIColor(red: 0.98, green: 0.88, blue: 0.66, alpha: 1)
        case .cabinet: return UIColor(red: 0.90, green: 0.80, blue: 0.68, alpha: 1)
        case .exhibitStage: return UIColor(red: 0.88, green: 0.84, blue: 0.96, alpha: 1)
        case .wall, .cityWall: return UIColor(white: 0.35, alpha: 1)
        case .landscape: return UIColor(red: 0.74, green: 0.88, blue: 0.74, alpha: 1)
        default: return UIColor(white: 0.82, alpha: 1)
        }
    }

    private static func drawDimensionLine(in cg: CGContext, from a: CGPoint, to b: CGPoint, text: String) {
        UIColor(red: 0.14, green: 0.34, blue: 0.72, alpha: 1).setStroke()
        cg.setLineWidth(0.9)
        cg.beginPath()
        cg.move(to: a)
        cg.addLine(to: b)
        cg.strokePath()

        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        text.draw(
            at: CGPoint(x: mid.x - 28, y: mid.y - 12),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 8.5, weight: .bold),
                .foregroundColor: UIColor(red: 0.14, green: 0.34, blue: 0.72, alpha: 1),
            ]
        )
    }
}
