import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Unified Editable 3D Spatial Scene Models (Millimeter Precision)

public struct WuMindVec3MM: Codable, Equatable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var z: Int

    public init(x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }

    public var xMeters: Float { Float(x) / 1000.0 }
    public var yMeters: Float { Float(y) / 1000.0 }
    public var zMeters: Float { Float(z) / 1000.0 }
}

public enum WuMindSpatialSceneType: String, CaseIterable, Codable, Identifiable, Sendable, Hashable {
    case imperialComplex
    case modernPavilion
    case interiorSpace
    case villaBuilding
    case courtyardPark
    case gameScene

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .imperialComplex: return "故宫级建筑群"
        case .modernPavilion: return "展厅 / 滨水展馆"
        case .interiorSpace: return "精确室内空间"
        case .villaBuilding: return "建筑外观 / 别墅"
        case .courtyardPark: return "庭院 / 园区"
        case .gameScene: return "可漫游游戏场景"
        }
    }
}

public enum WuMindSpatialCreationMode: String, Codable, Equatable, Sendable {
    case textDescription
    case uploadReference
    case uploadAndText

    public var badgeLabel: String {
        switch self {
        case .textDescription: return "描述创建 · 概念默认尺寸"
        case .uploadReference: return "图纸上传 · 尺寸核对"
        case .uploadAndText: return "草图/图纸 + 描述创建"
        }
    }
}

public enum WuMindSpatialWeather: String, CaseIterable, Codable, Identifiable, Sendable, Hashable {
    case sunny
    case snowy
    case nightSciFi

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sunny: return "晴天日光"
        case .snowy: return "漫天雪景"
        case .nightSciFi: return "夜景灯光"
        }
    }

    public var iconName: String {
        switch self {
        case .sunny: return "sun.max.fill"
        case .snowy: return "snowflake"
        case .nightSciFi: return "moon.stars.fill"
        }
    }
}

public enum WuMindDimensionStatus: Codable, Equatable, Sendable {
    case confirmedMeasured
    case conceptDefault
    case pendingConfirmation(note: String)

    public var label: String {
        switch self {
        case .confirmedMeasured: return "图纸核对实测"
        case .conceptDefault: return "概念默认值（非实测）"
        case .pendingConfirmation: return "待确认（建议补测）"
        }
    }

    public var isPending: Bool {
        if case .pendingConfirmation = self { return true }
        return false
    }
}

public enum WuMindSpatialNodeCategory: String, CaseIterable, Codable, Identifiable, Sendable, Hashable {
    case palaceHall
    case gateTower
    case cityWall
    case courtyard
    case waterway
    case road
    case wall
    case floorSlab
    case roof
    case door
    case window
    case stairs
    case cabinet
    case furniture
    case exhibitStage
    case landscape
    case light
    case freeformProp

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .palaceHall: return "宫殿建筑"
        case .gateTower: return "城墙门楼"
        case .cityWall: return "宫墙/城墙"
        case .courtyard: return "院落/广场"
        case .waterway: return "水系/石桥"
        case .road: return "中轴道路"
        case .wall: return "墙体"
        case .floorSlab: return "楼板/露台"
        case .roof: return "屋顶"
        case .door: return "门"
        case .window: return "窗/幕墙"
        case .stairs: return "台阶/楼梯"
        case .cabinet: return "定制柜体"
        case .furniture: return "家具"
        case .exhibitStage: return "展台/展馆体块"
        case .landscape: return "景观/古树"
        case .light: return "灯光"
        case .freeformProp: return "自由造型道具"
        }
    }

    public var isRoofCategory: Bool {
        self == .roof
    }

    public var isExteriorWallCategory: Bool {
        self == .wall || self == .cityWall
    }
}

public enum WuMindSpatialMaterialPreset: String, CaseIterable, Codable, Identifiable, Sendable, Hashable {
    case glazedGoldTile
    case emeraldTile
    case imperialCrimson
    case whiteMarble
    case greyBrick
    case courtyardStone
    case architecturalConcrete
    case lowEGlass
    case warmOak
    case brushedSlate
    case warmCopper
    case waterJade
    case cypressGreen
    case darkMetal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .glazedGoldTile: return "明黄琉璃瓦"
        case .emeraldTile: return "翠绿琉璃瓦"
        case .imperialCrimson: return "故宫朱红"
        case .whiteMarble: return "汉白玉"
        case .greyBrick: return "青砖城台"
        case .courtyardStone: return "金砖石板"
        case .architecturalConcrete: return "白色清水混凝土"
        case .lowEGlass: return "低反幕墙玻璃"
        case .warmOak: return "温润橡木"
        case .brushedSlate: return "哑光岩板"
        case .warmCopper: return "拉丝暖铜"
        case .waterJade: return "碧波水面"
        case .cypressGreen: return "古柏苍松"
        case .darkMetal: return "深灰金属"
        }
    }

    public var hexColor: String {
        switch self {
        case .glazedGoldTile: return "#D99B1E"
        case .emeraldTile: return "#1F7A5A"
        case .imperialCrimson: return "#9B221B"
        case .whiteMarble: return "#EFECE4"
        case .greyBrick: return "#6E6D6A"
        case .courtyardStone: return "#C8C1B2"
        case .architecturalConcrete: return "#EAEAE5"
        case .lowEGlass: return "#79A8BF"
        case .warmOak: return "#B78756"
        case .brushedSlate: return "#464A52"
        case .warmCopper: return "#B87344"
        case .waterJade: return "#2B6E7D"
        case .cypressGreen: return "#2D5236"
        case .darkMetal: return "#343942"
        }
    }

    public var roughness: Double {
        switch self {
        case .lowEGlass, .waterJade: return 0.12
        case .glazedGoldTile, .emeraldTile: return 0.28
        case .warmCopper, .darkMetal: return 0.32
        case .whiteMarble, .brushedSlate: return 0.45
        case .warmOak, .imperialCrimson: return 0.58
        case .architecturalConcrete, .greyBrick, .courtyardStone, .cypressGreen: return 0.82
        }
    }

    public var metalness: Double {
        switch self {
        case .warmCopper, .darkMetal: return 0.72
        case .glazedGoldTile, .emeraldTile: return 0.18
        case .lowEGlass, .waterJade: return 0.10
        default: return 0.04
        }
    }
}

public struct WuMindSpatialMaterial: Codable, Equatable, Hashable, Sendable {
    public var preset: WuMindSpatialMaterialPreset
    public var primaryHex: String
    public var roofPreset: WuMindSpatialMaterialPreset?
    public var roofHex: String?
    public var opacity: Double

    public init(
        preset: WuMindSpatialMaterialPreset,
        primaryHex: String? = nil,
        roofPreset: WuMindSpatialMaterialPreset? = nil,
        roofHex: String? = nil,
        opacity: Double = 1.0
    ) {
        self.preset = preset
        self.primaryHex = primaryHex ?? preset.hexColor
        self.roofPreset = roofPreset
        self.roofHex = roofHex ?? roofPreset?.hexColor
        self.opacity = max(0.15, min(1.0, opacity))
    }
}

public struct WuMindArchitecturalDetailProfile: Codable, Equatable, Hashable, Sendable {
    /// 1 = single eave, 2 = double-tier imperial eave (重檐)
    public var eaveTiers: Int
    public var columnCountX: Int
    public var columnCountZ: Int
    public var plinthHeightMM: Int
    public var archCount: Int
    public var isCylindrical: Bool
    public var hasBridgeArches: Bool
    public var hasRidgeOrnaments: Bool

    public init(
        eaveTiers: Int = 1,
        columnCountX: Int = 0,
        columnCountZ: Int = 0,
        plinthHeightMM: Int = 0,
        archCount: Int = 0,
        isCylindrical: Bool = false,
        hasBridgeArches: Bool = false,
        hasRidgeOrnaments: Bool = false
    ) {
        self.eaveTiers = max(0, min(3, eaveTiers))
        self.columnCountX = max(0, min(20, columnCountX))
        self.columnCountZ = max(0, min(12, columnCountZ))
        self.plinthHeightMM = max(0, plinthHeightMM)
        self.archCount = max(0, min(5, archCount))
        self.isCylindrical = isCylindrical
        self.hasBridgeArches = hasBridgeArches
        self.hasRidgeOrnaments = hasRidgeOrnaments
    }
}

public struct WuMindSpatialNode: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var category: WuMindSpatialNodeCategory
    public var floorIndex: Int
    /// Center X, base elevation Y, center Z in millimeters.
    public var positionMM: WuMindVec3MM
    /// Width (X), Height (Y), Depth (Z) in millimeters.
    public var sizeMM: WuMindVec3MM
    public var rotationYDeg: Double
    public var material: WuMindSpatialMaterial
    public var dimensionStatus: WuMindDimensionStatus
    public var detailProfile: WuMindArchitecturalDetailProfile
    public var notes: String?
    public var isVisible: Bool
    /// Logical room grouping tag (e.g. "kitchen", "adjacent_living_room") for multi-room isolation checks.
    public var roomTag: String?
    /// "parametric" for dimension-critical architectural geometry vs "decorative_tripo" for decorative props.
    public var modelingKind: String?
    /// Shared identifier tying a door/window opening to its host wall piers and lintel.
    public var hostWallGroupID: String?
    /// Role inside a host wall assembly: "pier_before" | "pier_after" | "lintel" | "opening_door".
    public var wallOpeningRole: String?
    /// Primary opening span axis: "x" (North/South wall) or "z" (East/West wall).
    public var openingSpanAxis: String?

    public init(
        id: UUID = UUID(),
        name: String,
        category: WuMindSpatialNodeCategory,
        floorIndex: Int = 0,
        positionMM: WuMindVec3MM,
        sizeMM: WuMindVec3MM,
        rotationYDeg: Double = 0,
        material: WuMindSpatialMaterial,
        dimensionStatus: WuMindDimensionStatus = .conceptDefault,
        detailProfile: WuMindArchitecturalDetailProfile = WuMindArchitecturalDetailProfile(),
        notes: String? = nil,
        isVisible: Bool = true,
        roomTag: String? = nil,
        modelingKind: String? = nil,
        hostWallGroupID: String? = nil,
        wallOpeningRole: String? = nil,
        openingSpanAxis: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.floorIndex = floorIndex
        self.positionMM = positionMM
        self.sizeMM = WuMindVec3MM(
            x: max(50, sizeMM.x),
            y: max(40, sizeMM.y),
            z: max(50, sizeMM.z)
        )
        self.rotationYDeg = rotationYDeg
        self.material = material
        self.dimensionStatus = dimensionStatus
        self.detailProfile = detailProfile
        self.notes = notes
        self.isVisible = isVisible
        self.roomTag = roomTag
        self.modelingKind = modelingKind
        self.hostWallGroupID = hostWallGroupID
        self.wallOpeningRole = wallOpeningRole
        self.openingSpanAxis = openingSpanAxis
    }

    /// Primary span width in millimeters along the node's functional width axis.
    public var primaryWidthMM: Int {
        openingSpanAxis == "z" ? sizeMM.z : sizeMM.x
    }

    public var dimensionSummaryText: String {
        let w = formatMillimeters(sizeMM.x)
        let d = formatMillimeters(sizeMM.z)
        let h = formatMillimeters(sizeMM.y)
        return "宽 \(w) × 深 \(d) × 高 \(h)"
    }

    private func formatMillimeters(_ mm: Int) -> String {
        if mm >= 10_000 {
            return String(format: "%.1fm", Double(mm) / 1000.0)
        }
        return "\(mm)mm"
    }
}

public struct WuMindSpatialCameraPreset: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var eyeMM: WuMindVec3MM
    public var targetMM: WuMindVec3MM
    public var fovDeg: Double

    public init(
        id: String,
        title: String,
        subtitle: String,
        eyeMM: WuMindVec3MM,
        targetMM: WuMindVec3MM,
        fovDeg: Double = 52
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.eyeMM = eyeMM
        self.targetMM = targetMM
        self.fovDeg = fovDeg
    }
}

public struct WuMindDimensionAuditItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var valueMM: Int?
    public var status: WuMindDimensionStatus
    public var linkedNodeID: UUID?
    public var guidance: String

    public init(
        id: UUID = UUID(),
        label: String,
        valueMM: Int?,
        status: WuMindDimensionStatus,
        linkedNodeID: UUID? = nil,
        guidance: String
    ) {
        self.id = id
        self.label = label
        self.valueMM = valueMM
        self.status = status
        self.linkedNodeID = linkedNodeID
        self.guidance = guidance
    }
}

public struct WuMindSpatialSceneSnapshot: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var createdAt: Date
    public var nodes: [WuMindSpatialNode]
    public var weather: WuMindSpatialWeather

    public init(
        id: UUID = UUID(),
        label: String,
        createdAt: Date = Date(),
        nodes: [WuMindSpatialNode],
        weather: WuMindSpatialWeather
    ) {
        self.id = id
        self.label = label
        self.createdAt = createdAt
        self.nodes = nodes
        self.weather = weather
    }
}

public struct WuMindSpatialSceneDocument: Identifiable, Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var id: UUID
    public var title: String
    public var sceneType: WuMindSpatialSceneType
    public var creationMode: WuMindSpatialCreationMode
    public var sourcePrompt: String
    public var referenceFilenames: [String]
    public var isConceptScene: Bool
    public var disclaimerBanner: String
    public var weather: WuMindSpatialWeather
    public var nodes: [WuMindSpatialNode]
    public var cameraPresets: [WuMindSpatialCameraPreset]
    public var dimensionAuditItems: [WuMindDimensionAuditItem]
    public var savedVersions: [WuMindSpatialSceneSnapshot]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        formatVersion: Int = 1,
        id: UUID = UUID(),
        title: String,
        sceneType: WuMindSpatialSceneType,
        creationMode: WuMindSpatialCreationMode,
        sourcePrompt: String,
        referenceFilenames: [String] = [],
        isConceptScene: Bool,
        disclaimerBanner: String? = nil,
        weather: WuMindSpatialWeather = .sunny,
        nodes: [WuMindSpatialNode],
        cameraPresets: [WuMindSpatialCameraPreset],
        dimensionAuditItems: [WuMindDimensionAuditItem] = [],
        savedVersions: [WuMindSpatialSceneSnapshot] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.title = title
        self.sceneType = sceneType
        self.creationMode = creationMode
        self.sourcePrompt = sourcePrompt
        self.referenceFilenames = referenceFilenames
        self.isConceptScene = isConceptScene
        self.disclaimerBanner = disclaimerBanner ?? (
            isConceptScene
                ? "概念 3D 空间场景（含标注概念默认尺寸，非实测复原或施工蓝图）"
                : "图纸核对空间工程（已标注实测尺寸与待确认项，概念深化用途，非施工蓝图）"
        )
        self.weather = weather
        self.nodes = nodes
        self.cameraPresets = cameraPresets
        self.dimensionAuditItems = dimensionAuditItems
        self.savedVersions = savedVersions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var floorIndices: [Int] {
        let unique = Set(nodes.map(\.floorIndex))
        return unique.sorted()
    }

    public var hasConfirmedMeasurements: Bool {
        dimensionAuditItems.contains { $0.status == .confirmedMeasured }
    }

    public var pendingConfirmationCount: Int {
        dimensionAuditItems.filter { $0.status.isPending }.count
            + nodes.filter { $0.dimensionStatus.isPending }.count
    }
}

// MARK: - Core Spatial 3D Scene Engine (AI Prompts + Dynamic Synthesizer + Surgical Patching)

public enum WuMindSpatial3DEngine {

    public static func sceneGenerationSystemPrompt(
        prompt: String,
        sceneType: WuMindSpatialSceneType,
        creationMode: WuMindSpatialCreationMode,
        hasReferenceImages: Bool,
        extractedDrawingText: String?
    ) -> String {
        let refNote = hasReferenceImages
            ? "用户已上传参考图/图纸。若图纸文字含明确毫米标注，将对应构件标记为 confirmedMeasured；若是单张照片或草图，只作视觉与轮廓参考，不得编造实测尺寸，全部标为 conceptDefault 或对缺失关键尺寸输出 pendingConfirmation。"
            : "用户仅通过文字描述创建，缺少的尺寸必须明确标记为 conceptDefault（概念默认值），不得冒充实测。"

        return """
        你是 WUMIND「AI 3D 空间工坊」的资深建筑与空间场景架构师。
        你的职责是生成「可拆、可选、可编辑」的结构化 3D 场景工程 JSON（单位严格为毫米 mm），绝不输出一整块不可拆模型。
        \(refNote)
        坐标规范：X 为东西向（右正），Y 为地面标高（0 为地面），Z 为南北向（南正、北负）。
        允许的 category：palaceHall / gateTower / cityWall / courtyard / waterway / road / wall / floorSlab / roof / door / window / stairs / cabinet / furniture / exhibitStage / landscape / light / freeformProp。
        允许的 material preset：glazedGoldTile / emeraldTile / imperialCrimson / whiteMarble / greyBrick / courtyardStone / architecturalConcrete / lowEGlass / warmOak / brushedSlate / warmCopper / waterJade / cypressGreen / darkMetal。
        要求：
        1. 输出至少 10~32 个独立构件节点（建筑群须包含中轴道路、多进院落、主殿、配殿、门楼、城墙、水面/桥、古树）。
        2. 屋顶、墙体、楼板、门窗、柜体/展台必须分离为独立节点，以便隐藏屋顶、切换楼层与单独修改。
        3. 只返回合法 JSON 对象：
        {
          "title": "场景名",
          "weather": "sunny|snowy|nightSciFi",
          "nodes": [
            {
              "name": "太和殿主殿",
              "category": "palaceHall",
              "floorIndex": 0,
              "x": 0, "y": 0, "z": -18000,
              "width": 32000, "height": 16500, "depth": 18000,
              "rotationYDeg": 0,
              "preset": "imperialCrimson",
              "roofPreset": "glazedGoldTile",
              "dimensionStatus": "conceptDefault",
              "eaveTiers": 2, "columnCountX": 10, "plinthHeightMM": 3600
            }
          ],
          "dimensionAudit": [
            { "label": "主操作台地柜宽", "valueMM": 2400, "status": "confirmedMeasured", "guidance": "来源：图纸标注" }
          ]
        }
        当前目标空间类型：\(sceneType.displayName)；创建方式：\(creationMode.badgeLabel)。
        \(extractedDrawingText.map { "提取到的图纸/PDF 文字：\n\(String($0.prefix(2500)))" } ?? "")
        """
    }

    public static func parseOrSynthesizeScene(
        rawLLMOutput: String,
        sourcePrompt: String,
        preferredType: WuMindSpatialSceneType,
        creationMode: WuMindSpatialCreationMode,
        referenceFilenames: [String] = [],
        extractedDrawingText: String? = nil
    ) -> WuMindSpatialSceneDocument {
        let cleaned = extractJSONObject(from: rawLLMOutput)
        if let data = cleaned.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(RawScenePayload.self, from: data),
           let rawNodes = decoded.nodes, rawNodes.count >= 4 {
            let parsedNodes: [WuMindSpatialNode] = rawNodes.enumerated().map { idx, r in
                let cat = WuMindSpatialNodeCategory(rawValue: r.category ?? "") ?? .wall
                let preset = WuMindSpatialMaterialPreset(rawValue: r.preset ?? "") ?? .architecturalConcrete
                let roofPreset = r.roofPreset.flatMap { WuMindSpatialMaterialPreset(rawValue: $0) }
                let dimStatus: WuMindDimensionStatus = {
                    switch (r.dimensionStatus ?? "").lowercased() {
                    case "confirmedmeasured", "measured": return .confirmedMeasured
                    case "pendingconfirmation", "pending":
                        return .pendingConfirmation(note: r.note ?? "图纸未明确标注，建议补测")
                    default: return .conceptDefault
                    }
                }()
                let detail = WuMindArchitecturalDetailProfile(
                    eaveTiers: r.eaveTiers ?? (cat == .palaceHall || cat == .gateTower ? 2 : 1),
                    columnCountX: r.columnCountX ?? (cat == .palaceHall ? 8 : 0),
                    columnCountZ: r.columnCountZ ?? (cat == .palaceHall ? 4 : 0),
                    plinthHeightMM: r.plinthHeightMM ?? (cat == .palaceHall ? 2400 : 0),
                    archCount: r.archCount ?? (cat == .gateTower ? 3 : 0),
                    isCylindrical: r.isCylindrical ?? (cat == .exhibitStage),
                    hasBridgeArches: r.hasBridgeArches ?? false,
                    hasRidgeOrnaments: cat == .palaceHall || cat == .gateTower
                )
                return WuMindSpatialNode(
                    name: (r.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "构件 \(idx + 1)",
                    category: cat,
                    floorIndex: r.floorIndex ?? 0,
                    positionMM: WuMindVec3MM(x: r.x ?? 0, y: r.y ?? 0, z: r.z ?? 0),
                    sizeMM: WuMindVec3MM(x: r.width ?? 4000, y: r.height ?? 3000, z: r.depth ?? 4000),
                    rotationYDeg: r.rotationYDeg ?? 0,
                    material: WuMindSpatialMaterial(
                        preset: preset,
                        roofPreset: roofPreset,
                        opacity: preset == .lowEGlass ? 0.45 : (preset == .waterJade ? 0.85 : 1.0)
                    ),
                    dimensionStatus: dimStatus,
                    detailProfile: detail,
                    notes: r.note
                )
            }

            let auditItems: [WuMindDimensionAuditItem] = (decoded.dimensionAudit ?? []).map { a in
                let st: WuMindDimensionStatus = {
                    switch (a.status ?? "").lowercased() {
                    case "confirmedmeasured", "measured": return .confirmedMeasured
                    case "pendingconfirmation", "pending":
                        return .pendingConfirmation(note: a.guidance ?? "缺少标注，建议现场补测")
                    default: return .conceptDefault
                    }
                }()
                let linkedID = parsedNodes.first(where: { $0.name.contains(a.label ?? "") || (a.label ?? "").contains($0.name) })?.id
                return WuMindDimensionAuditItem(
                    label: a.label ?? "关键尺寸",
                    valueMM: a.valueMM,
                    status: st,
                    linkedNodeID: linkedID,
                    guidance: a.guidance ?? st.label
                )
            }

            let weather = WuMindSpatialWeather(rawValue: decoded.weather ?? "") ?? detectWeather(in: sourcePrompt)
            let title = (decoded.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? String(sourcePrompt.prefix(16))
            let cameras = computeDefaultCameras(for: parsedNodes, sceneType: preferredType)
            let hasMeasured = auditItems.contains { $0.status == .confirmedMeasured }

            return WuMindSpatialSceneDocument(
                title: title.isEmpty ? "AI 3D 空间工程" : title,
                sceneType: preferredType,
                creationMode: creationMode,
                sourcePrompt: sourcePrompt,
                referenceFilenames: referenceFilenames,
                isConceptScene: !hasMeasured,
                weather: weather,
                nodes: parsedNodes,
                cameraPresets: cameras,
                dimensionAuditItems: auditItems
            )
        }

        // Dynamic parametric synthesis fallback (structured multi-element geometry driven by prompt parameters)
        return synthesizeParametricScene(
            prompt: sourcePrompt,
            preferredType: preferredType,
            creationMode: creationMode,
            referenceFilenames: referenceFilenames,
            extractedDrawingText: extractedDrawingText
        )
    }

    // MARK: - Dynamic Parametric Architectural Synthesizer (Multi-Domain, Non-Static)

    public static func synthesizeParametricScene(
        prompt: String,
        preferredType: WuMindSpatialSceneType? = nil,
        creationMode: WuMindSpatialCreationMode = .textDescription,
        referenceFilenames: [String] = [],
        extractedDrawingText: String? = nil
    ) -> WuMindSpatialSceneDocument {
        let lower = prompt.lowercased()
        let weather = detectWeather(in: prompt)

        let resolvedType: WuMindSpatialSceneType = {
            if let preferredType {
                // Honor explicit prompt domain switches even if picker wasn't changed
                if lower.contains("故宫") || lower.contains("宫殿") || lower.contains("紫禁") || lower.contains("中轴") {
                    return .imperialComplex
                }
                if lower.contains("厨房") || lower.contains("餐区") || lower.contains("户型") || lower.contains("橱柜") || lower.contains("地柜") {
                    return .interiorSpace
                }
                if lower.contains("展馆") || lower.contains("展厅") || lower.contains("展台") || lower.contains("滨水") {
                    return .modernPavilion
                }
                if lower.contains("别墅") || lower.contains("两层") || lower.contains("露台") {
                    return .villaBuilding
                }
                return preferredType
            }
            if lower.contains("故宫") || lower.contains("宫殿") || lower.contains("紫禁") { return .imperialComplex }
            if lower.contains("厨房") || lower.contains("餐区") || lower.contains("户型") { return .interiorSpace }
            if lower.contains("展馆") || lower.contains("展厅") || lower.contains("展台") { return .modernPavilion }
            if lower.contains("别墅") || lower.contains("露台") { return .villaBuilding }
            if lower.contains("庭院") || lower.contains("园区") { return .courtyardPark }
            return .modernPavilion
        }()

        switch resolvedType {
        case .imperialComplex:
            return buildImperialPalaceComplex(
                prompt: prompt,
                creationMode: creationMode,
                referenceFilenames: referenceFilenames,
                weather: weather
            )
        case .interiorSpace:
            return buildKitchenDiningInterior(
                prompt: prompt,
                creationMode: creationMode,
                referenceFilenames: referenceFilenames,
                extractedDrawingText: extractedDrawingText
            )
        case .modernPavilion:
            return buildModernWaterfrontPavilion(
                prompt: prompt,
                creationMode: creationMode,
                referenceFilenames: referenceFilenames,
                weather: weather
            )
        case .villaBuilding:
            return buildTwoStoryCourtyardVilla(
                prompt: prompt,
                creationMode: creationMode,
                referenceFilenames: referenceFilenames,
                weather: weather
            )
        case .courtyardPark, .gameScene:
            return buildModernWaterfrontPavilion(
                prompt: prompt,
                creationMode: creationMode,
                referenceFilenames: referenceFilenames,
                weather: weather,
                overrideType: resolvedType
            )
        }
    }

    // MARK: - 1. Flagship Imperial Palace Complex (DeepSeek GIF Benchmark: Central Axis, Multi-Courtyards, Gate Towers, River & Bridges)

    public static func buildImperialPalaceComplex(
        prompt: String = "生成一座故宫风格可漫游宫殿建筑群，包含南北贯通中轴御道、多进院落、太和殿主殿与东西配殿、午门与神武门城墙门楼、内金水河与汉白玉石桥、四角楼及古柏，支持晴天与雪景切换。",
        creationMode: WuMindSpatialCreationMode = .textDescription,
        referenceFilenames: [String] = [],
        weather: WuMindSpatialWeather = .sunny
    ) -> WuMindSpatialSceneDocument {
        let wantsEmeraldRoof = prompt.contains("绿瓦") || prompt.contains("翠绿")
        let defaultRoof: WuMindSpatialMaterialPreset = wantsEmeraldRoof ? .emeraldTile : .glazedGoldTile

        var nodes: [WuMindSpatialNode] = []

        // 1. Ground & Multi-Courtyard Pavements (160m x 120m axial layout)
        nodes.append(WuMindSpatialNode(
            name: "第一进院落 · 太和门广场",
            category: .courtyard,
            floorIndex: 0,
            positionMM: .init(x: 0, y: 0, z: 32_000),
            sizeMM: .init(x: 108_000, y: 240, z: 42_000),
            material: .init(preset: .courtyardStone),
            notes: "概念默认尺寸 · 午门至太和门礼仪广场"
        ))
        nodes.append(WuMindSpatialNode(
            name: "第二进院落 · 太和殿大广场",
            category: .courtyard,
            floorIndex: 0,
            positionMM: .init(x: 0, y: 0, z: -12_000),
            sizeMM: .init(x: 110_000, y: 260, z: 46_000),
            material: .init(preset: .courtyardStone),
            notes: "概念默认尺寸 · 主殿前开阔大院"
        ))
        nodes.append(WuMindSpatialNode(
            name: "第三进院落 · 后朝庭院",
            category: .courtyard,
            floorIndex: 0,
            positionMM: .init(x: 0, y: 0, z: -56_000),
            sizeMM: .init(x: 104_000, y: 260, z: 36_000),
            material: .init(preset: .courtyardStone),
            notes: "概念默认尺寸 · 中和殿与保和殿院落"
        ))

        // 2. Continuous North-South Central Imperial Axis Road (中轴御道)
        nodes.append(WuMindSpatialNode(
            name: "中轴御道（南段 · 午门至太和门）",
            category: .road,
            floorIndex: 0,
            positionMM: .init(x: 0, y: 240, z: 36_000),
            sizeMM: .init(x: 8_200, y: 140, z: 54_000),
            material: .init(preset: .whiteMarble),
            notes: "贯通南北中轴的石板御道"
        ))
        nodes.append(WuMindSpatialNode(
            name: "中轴御道（中段 · 太和殿朝路）",
            category: .road,
            floorIndex: 0,
            positionMM: .init(x: 0, y: 260, z: -10_000),
            sizeMM: .init(x: 9_000, y: 140, z: 44_000),
            material: .init(preset: .whiteMarble)
        ))
        nodes.append(WuMindSpatialNode(
            name: "中轴御道（北段 · 通往神武门）",
            category: .road,
            floorIndex: 0,
            positionMM: .init(x: 0, y: 260, z: -56_000),
            sizeMM: .init(x: 7_800, y: 140, z: 40_000),
            material: .init(preset: .whiteMarble)
        ))

        // 3. Waterways & Arched White-Marble Golden Water Bridges (内金水河 + 五桥 + 南护城河)
        nodes.append(WuMindSpatialNode(
            name: "内金水河与五座汉白玉金水桥",
            category: .waterway,
            floorIndex: 0,
            positionMM: .init(x: 0, y: 120, z: 32_500),
            sizeMM: .init(x: 102_000, y: 220, z: 9_500),
            material: .init(preset: .waterJade, opacity: 0.88),
            detailProfile: .init(archCount: 5, hasBridgeArches: true),
            notes: "横贯第一进院落的水面与五座汉白玉石拱桥"
        ))
        nodes.append(WuMindSpatialNode(
            name: "南侧护城河水面",
            category: .waterway,
            floorIndex: 0,
            positionMM: .init(x: 0, y: 80, z: 74_000),
            sizeMM: .init(x: 152_000, y: 200, z: 14_000),
            material: .init(preset: .waterJade, opacity: 0.88),
            detailProfile: .init(archCount: 1, hasBridgeArches: true)
        ))

        // 4. South Meridian Gate Complex (午门城墙与重檐门楼群)
        nodes.append(WuMindSpatialNode(
            name: "午门主城楼",
            category: .gateTower,
            floorIndex: 0,
            positionMM: .init(x: 0, y: 0, z: 58_000),
            sizeMM: .init(x: 34_000, y: 19_500, z: 14_500),
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof),
            detailProfile: .init(eaveTiers: 2, columnCountX: 10, columnCountZ: 4, plinthHeightMM: 7_200, archCount: 3, hasRidgeOrnaments: true),
            notes: "砖砌收分城台 + 三券洞门道 + 重檐庑殿城楼"
        ))
        nodes.append(WuMindSpatialNode(
            name: "午门东翼雁翅楼",
            category: .gateTower,
            floorIndex: 0,
            positionMM: .init(x: 24_000, y: 0, z: 53_000),
            sizeMM: .init(x: 11_000, y: 14_200, z: 16_000),
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof),
            detailProfile: .init(eaveTiers: 1, columnCountX: 4, columnCountZ: 6, plinthHeightMM: 6_000, archCount: 0, hasRidgeOrnaments: true)
        ))
        nodes.append(WuMindSpatialNode(
            name: "午门西翼雁翅楼",
            category: .gateTower,
            floorIndex: 0,
            positionMM: .init(x: -24_000, y: 0, z: 53_000),
            sizeMM: .init(x: 11_000, y: 14_200, z: 16_000),
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof),
            detailProfile: .init(eaveTiers: 1, columnCountX: 4, columnCountZ: 6, plinthHeightMM: 6_000, archCount: 0, hasRidgeOrnaments: true)
        ))

        // 5. Middle Gate Hall (太和门 + 协和门 / 熙和门)
        nodes.append(WuMindSpatialNode(
            name: "太和门大殿",
            category: .palaceHall,
            floorIndex: 0,
            positionMM: .init(x: 0, y: 240, z: 14_000),
            sizeMM: .init(x: 28_000, y: 15_000, z: 14_000),
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof),
            detailProfile: .init(eaveTiers: 2, columnCountX: 8, columnCountZ: 4, plinthHeightMM: 2_600, hasRidgeOrnaments: true)
        ))
        nodes.append(WuMindSpatialNode(
            name: "协和门（东侧仪门）",
            category: .palaceHall,
            floorIndex: 0,
            positionMM: .init(x: 34_000, y: 240, z: 14_000),
            sizeMM: .init(x: 14_000, y: 10_200, z: 9_000),
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof),
            detailProfile: .init(eaveTiers: 1, columnCountX: 6, columnCountZ: 3, plinthHeightMM: 1_200, hasRidgeOrnaments: true)
        ))
        nodes.append(WuMindSpatialNode(
            name: "熙和门（西侧仪门）",
            category: .palaceHall,
            floorIndex: 0,
            positionMM: .init(x: -34_000, y: 240, z: 14_000),
            sizeMM: .init(x: 14_000, y: 10_200, z: 9_000),
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof),
            detailProfile: .init(eaveTiers: 1, columnCountX: 6, columnCountZ: 3, plinthHeightMM: 1_200, hasRidgeOrnaments: true)
        ))

        // 6. Grand Main Hall + Side Halls + Flanking Galleries (太和殿主殿 + 东西配殿 + 东西庑房)
        nodes.append(WuMindSpatialNode(
            name: "太和殿主殿",
            category: .palaceHall,
            floorIndex: 0,
            positionMM: .init(x: 0, y: 260, z: -22_000),
            sizeMM: .init(x: 42_000, y: 22_800, z: 22_000),
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof),
            detailProfile: .init(eaveTiers: 2, columnCountX: 12, columnCountZ: 6, plinthHeightMM: 4_800, hasRidgeOrnaments: true),
            notes: "三层汉白玉须弥座丹陛 + 12 柱朱红大殿 + 重檐庑殿顶"
        ))
        nodes.append(WuMindSpatialNode(
            name: "东配殿 · 弘义阁",
            category: .palaceHall,
            floorIndex: 0,
            positionMM: .init(x: 38_000, y: 260, z: -12_000),
            sizeMM: .init(x: 13_000, y: 12_600, z: 24_000),
            rotationYDeg: 0,
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof),
            detailProfile: .init(eaveTiers: 1, columnCountX: 4, columnCountZ: 8, plinthHeightMM: 1_600, hasRidgeOrnaments: true),
            notes: "可独立选中修改屋顶颜色或移动位置，其余宫殿不动"
        ))
        nodes.append(WuMindSpatialNode(
            name: "西配殿 · 体仁阁",
            category: .palaceHall,
            floorIndex: 0,
            positionMM: .init(x: -38_000, y: 260, z: -12_000),
            sizeMM: .init(x: 13_000, y: 12_600, z: 24_000),
            rotationYDeg: 0,
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof),
            detailProfile: .init(eaveTiers: 1, columnCountX: 4, columnCountZ: 8, plinthHeightMM: 1_600, hasRidgeOrnaments: true)
        ))
        nodes.append(WuMindSpatialNode(
            name: "东庑长廊",
            category: .palaceHall,
            floorIndex: 0,
            positionMM: .init(x: 46_000, y: 260, z: 28_000),
            sizeMM: .init(x: 7_500, y: 7_200, z: 28_000),
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof),
            detailProfile: .init(eaveTiers: 1, columnCountX: 2, columnCountZ: 10, plinthHeightMM: 800)
        ))
        nodes.append(WuMindSpatialNode(
            name: "西庑长廊",
            category: .palaceHall,
            floorIndex: 0,
            positionMM: .init(x: -46_000, y: 260, z: 28_000),
            sizeMM: .init(x: 7_500, y: 7_200, z: 28_000),
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof),
            detailProfile: .init(eaveTiers: 1, columnCountX: 2, columnCountZ: 10, plinthHeightMM: 800)
        ))

        // 7. Rear Axis Halls (中和殿 + 保和殿) & North Gate Tower (神武门)
        nodes.append(WuMindSpatialNode(
            name: "中和殿",
            category: .palaceHall,
            floorIndex: 0,
            positionMM: .init(x: 0, y: 260, z: -46_000),
            sizeMM: .init(x: 18_000, y: 14_800, z: 18_000),
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof),
            detailProfile: .init(eaveTiers: 2, columnCountX: 6, columnCountZ: 6, plinthHeightMM: 3_200, hasRidgeOrnaments: true)
        ))
        nodes.append(WuMindSpatialNode(
            name: "保和殿",
            category: .palaceHall,
            floorIndex: 0,
            positionMM: .init(x: 0, y: 260, z: -64_000),
            sizeMM: .init(x: 32_000, y: 17_800, z: 16_000),
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof),
            detailProfile: .init(eaveTiers: 2, columnCountX: 10, columnCountZ: 4, plinthHeightMM: 3_400, hasRidgeOrnaments: true)
        ))
        nodes.append(WuMindSpatialNode(
            name: "神武门北城楼",
            category: .gateTower,
            floorIndex: 0,
            positionMM: .init(x: 0, y: 0, z: -84_000),
            sizeMM: .init(x: 28_000, y: 17_500, z: 12_500),
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof),
            detailProfile: .init(eaveTiers: 2, columnCountX: 8, columnCountZ: 4, plinthHeightMM: 6_500, archCount: 3, hasRidgeOrnaments: true)
        ))

        // 8. Perimeter Imperial City Walls & 4 Corner Watchtowers (东西南北宫墙 + 四角楼)
        nodes.append(WuMindSpatialNode(
            name: "东侧红墙宫墙",
            category: .cityWall,
            floorIndex: 0,
            positionMM: .init(x: 62_000, y: 0, z: -13_000),
            sizeMM: .init(x: 4_500, y: 8_200, z: 142_000),
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof)
        ))
        nodes.append(WuMindSpatialNode(
            name: "西侧红墙宫墙",
            category: .cityWall,
            floorIndex: 0,
            positionMM: .init(x: -62_000, y: 0, z: -13_000),
            sizeMM: .init(x: 4_500, y: 8_200, z: 142_000),
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof)
        ))
        nodes.append(WuMindSpatialNode(
            name: "东南角楼",
            category: .gateTower,
            floorIndex: 0,
            positionMM: .init(x: 62_000, y: 0, z: 58_000),
            sizeMM: .init(x: 11_000, y: 16_500, z: 11_000),
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof),
            detailProfile: .init(eaveTiers: 2, columnCountX: 4, columnCountZ: 4, plinthHeightMM: 7_500, hasRidgeOrnaments: true)
        ))
        nodes.append(WuMindSpatialNode(
            name: "西南角楼",
            category: .gateTower,
            floorIndex: 0,
            positionMM: .init(x: -62_000, y: 0, z: 58_000),
            sizeMM: .init(x: 11_000, y: 16_500, z: 11_000),
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof),
            detailProfile: .init(eaveTiers: 2, columnCountX: 4, columnCountZ: 4, plinthHeightMM: 7_500, hasRidgeOrnaments: true)
        ))
        nodes.append(WuMindSpatialNode(
            name: "东北角楼",
            category: .gateTower,
            floorIndex: 0,
            positionMM: .init(x: 62_000, y: 0, z: -84_000),
            sizeMM: .init(x: 11_000, y: 16_500, z: 11_000),
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof),
            detailProfile: .init(eaveTiers: 2, columnCountX: 4, columnCountZ: 4, plinthHeightMM: 7_500, hasRidgeOrnaments: true)
        ))
        nodes.append(WuMindSpatialNode(
            name: "西北角楼",
            category: .gateTower,
            floorIndex: 0,
            positionMM: .init(x: -62_000, y: 0, z: -84_000),
            sizeMM: .init(x: 11_000, y: 16_500, z: 11_000),
            material: .init(preset: .imperialCrimson, roofPreset: defaultRoof),
            detailProfile: .init(eaveTiers: 2, columnCountX: 4, columnCountZ: 4, plinthHeightMM: 7_500, hasRidgeOrnaments: true)
        ))

        // 9. Ancient Courtyard Cypress Clusters (古柏苍松景观)
        let treeCoords: [(String, Int, Int)] = [
            ("东庭院古柏群", 30_000, 42_000),
            ("西庭院古柏群", -30_000, 42_000),
            ("太和殿东侧古松", 48_000, -34_000),
            ("太和殿西侧古松", -48_000, -34_000),
        ]
        for (name, tx, tz) in treeCoords {
            nodes.append(WuMindSpatialNode(
                name: name,
                category: .landscape,
                floorIndex: 0,
                positionMM: .init(x: tx, y: 240, z: tz),
                sizeMM: .init(x: 6_500, y: 9_200, z: 6_500),
                material: .init(preset: .cypressGreen)
            ))
        }

        // Exact 3 camera presets matching DeepSeek Palace GIF benchmark
        let cameras: [WuMindSpatialCameraPreset] = [
            .init(
                id: "aerial_overview",
                title: "全景俯瞰",
                subtitle: "南北中轴、多进院落、城墙门楼与护城河全局层次",
                eyeMM: .init(x: 62_000, y: 66_000, z: 98_000),
                targetMM: .init(x: 0, y: 6_000, z: -12_000),
                fovDeg: 48
            ),
            .init(
                id: "road_walkthrough",
                title: "御道低空穿行",
                subtitle: "沿中轴御道低空越过金水桥直望太和门与太和殿",
                eyeMM: .init(x: 0, y: 4_200, z: 46_000),
                targetMM: .init(x: 0, y: 7_800, z: -18_000),
                fovDeg: 58
            ),
            .init(
                id: "gate_closeup",
                title: "门楼近景",
                subtitle: "近距查验午门砖台券洞、朱红柱列、斗拱屋檐与台阶",
                eyeMM: .init(x: 15_500, y: 9_800, z: 75_500),
                targetMM: .init(x: 0, y: 9_200, z: 57_000),
                fovDeg: 44
            ),
        ]

        let audit: [WuMindDimensionAuditItem] = [
            .init(label: "中轴南北总进深（概念默认）", valueMM: 160_000, status: .conceptDefault, guidance: "概念建筑群场景，非故宫实测文物复原"),
            .init(label: "太和殿主殿面阔（概念默认）", valueMM: 42_000, status: .conceptDefault, linkedNodeID: nodes.first(where: { $0.name == "太和殿主殿" })?.id, guidance: "可点击主殿或配殿独立调整尺寸与屋顶瓦色"),
        ]

        return WuMindSpatialSceneDocument(
            title: "故宫风格可漫游建筑群（概念版）",
            sceneType: .imperialComplex,
            creationMode: creationMode,
            sourcePrompt: prompt,
            referenceFilenames: referenceFilenames,
            isConceptScene: true,
            disclaimerBanner: "故宫风格概念可漫游建筑群（\(nodes.count) 个独立可编辑构件，概念默认尺寸，非实测复原）",
            weather: weather,
            nodes: nodes,
            cameraPresets: cameras,
            dimensionAuditItems: audit
        )
    }

    // MARK: - 2. Measured Interior Space (3629.MP4 Kitchen + Dining Room with +200mm Sync & Missing Dimension Audit)

    public static func buildKitchenDiningInterior(
        prompt: String,
        creationMode: WuMindSpatialCreationMode = .uploadAndText,
        referenceFilenames: [String] = ["厨房餐区户型图.pdf"],
        extractedDrawingText: String? = nil
    ) -> WuMindSpatialSceneDocument {
        let combined = prompt + "\n" + (extractedDrawingText ?? "")
        let lacksCeiling = combined.contains("缺尺寸") || combined.contains("未标注净高") || combined.contains("无净高")
        let roomWidthMM = parseMM(in: combined, keywords: ["房间宽", "总宽", "开间", "北墙"]) ?? 5_200
        let roomDepthMM = parseMM(in: combined, keywords: ["进深", "总长", "纵深"]) ?? 4_400
        let ceilingHeightMM = lacksCeiling ? 2_800 : (parseMM(in: combined, keywords: ["净高", "层高"]) ?? 2_800)
        let baseCabinetWidthMM = parseMM(in: combined, keywords: ["地柜宽", "主操作台", "橱柜宽", "柜宽"]) ?? 2_400

        let cabinetNode = WuMindSpatialNode(
            name: "主操作台地柜",
            category: .cabinet,
            floorIndex: 0,
            positionMM: .init(x: -900, y: 0, z: -(roomDepthMM / 2) + 420),
            sizeMM: .init(x: baseCabinetWidthMM, y: 860, z: 620),
            material: .init(preset: .warmOak, roofPreset: .brushedSlate),
            dimensionStatus: .confirmedMeasured,
            notes: "支持直接输入「改柜宽 +200 毫米」并同步更新 3D、尺寸清单与平面图 PDF"
        )
        let wallCabNode = WuMindSpatialNode(
            name: "北墙吊柜",
            category: .cabinet,
            floorIndex: 0,
            positionMM: .init(x: -900, y: 1_520, z: -(roomDepthMM / 2) + 280),
            sizeMM: .init(x: baseCabinetWidthMM, y: 740, z: 360),
            material: .init(preset: .architecturalConcrete),
            dimensionStatus: .confirmedMeasured
        )
        let islandNode = WuMindSpatialNode(
            name: "厨房中岛吧台",
            category: .cabinet,
            floorIndex: 0,
            positionMM: .init(x: -500, y: 0, z: -300),
            sizeMM: .init(x: 1_800, y: 900, z: 850),
            material: .init(preset: .brushedSlate, roofPreset: .whiteMarble),
            dimensionStatus: .confirmedMeasured
        )
        let fridgeNode = WuMindSpatialNode(
            name: "嵌入式冰箱高柜",
            category: .cabinet,
            floorIndex: 0,
            positionMM: .init(x: (roomWidthMM / 2) - 560, y: 0, z: -(roomDepthMM / 2) + 460),
            sizeMM: .init(x: 880, y: 2_260, z: 720),
            material: .init(preset: .darkMetal),
            dimensionStatus: .confirmedMeasured
        )
        let diningTableNode = WuMindSpatialNode(
            name: "餐区实木长餐桌",
            category: .furniture,
            floorIndex: 0,
            positionMM: .init(x: 350, y: 0, z: 1_150),
            sizeMM: .init(x: 1_650, y: 750, z: 900),
            material: .init(preset: .warmOak),
            dimensionStatus: .conceptDefault,
            notes: "照片参考家具尺度（概念默认值）"
        )

        let wallGroupID = "kitchen_east_partition"
        let doorWidthMM = parseMM(in: combined, keywords: ["门宽", "移门宽", "洞口宽"]) ?? 1_200
        let doorHeightMM = 2_150
        let doorCenterZ = 1_100
        let wallMinZ = -(roomDepthMM / 2)
        let wallMaxZ = roomDepthMM / 2
        let doorMinZ = doorCenterZ - doorWidthMM / 2
        let doorMaxZ = doorCenterZ + doorWidthMM / 2
        let northPierLen = max(200, doorMinZ - wallMinZ)
        let southPierLen = max(200, wallMaxZ - doorMaxZ)
        let lintelHeight = max(120, ceilingHeightMM - doorHeightMM)

        let northWall = WuMindSpatialNode(
            name: "厨房北墙",
            category: .wall,
            floorIndex: 0,
            positionMM: .init(x: 0, y: 0, z: -(roomDepthMM / 2)),
            sizeMM: .init(x: roomWidthMM, y: ceilingHeightMM, z: 180),
            material: .init(preset: .architecturalConcrete),
            dimensionStatus: lacksCeiling ? .pendingConfirmation(note: "测试图缺少净高标注，暂按 2800mm 占位，请现场补测") : .confirmedMeasured,
            roomTag: "kitchen",
            modelingKind: "parametric"
        )
        let westWall = WuMindSpatialNode(
            name: "西侧外墙",
            category: .wall,
            floorIndex: 0,
            positionMM: .init(x: -(roomWidthMM / 2), y: 0, z: 0),
            sizeMM: .init(x: 180, y: ceilingHeightMM, z: roomDepthMM),
            material: .init(preset: .architecturalConcrete),
            dimensionStatus: .confirmedMeasured,
            roomTag: "kitchen",
            modelingKind: "parametric"
        )
        // True parametric east partition split around the doorway opening (zero solid-wall penetration!)
        let eastWallNorthPier = WuMindSpatialNode(
            name: "东侧隔墙·北段墙垛",
            category: .wall,
            floorIndex: 0,
            positionMM: .init(x: roomWidthMM / 2, y: 0, z: wallMinZ + northPierLen / 2),
            sizeMM: .init(x: 180, y: ceilingHeightMM, z: northPierLen),
            material: .init(preset: .architecturalConcrete),
            dimensionStatus: .confirmedMeasured,
            notes: "参数化墙垛：随餐区入户移门加宽/缩窄自动同步墙洞边线",
            roomTag: "kitchen",
            modelingKind: "parametric",
            hostWallGroupID: wallGroupID,
            wallOpeningRole: "pier_before",
            openingSpanAxis: "z"
        )
        let eastWallSouthPier = WuMindSpatialNode(
            name: "东侧隔墙·南段墙垛",
            category: .wall,
            floorIndex: 0,
            positionMM: .init(x: roomWidthMM / 2, y: 0, z: doorMaxZ + southPierLen / 2),
            sizeMM: .init(x: 180, y: ceilingHeightMM, z: southPierLen),
            material: .init(preset: .architecturalConcrete),
            dimensionStatus: .confirmedMeasured,
            notes: "参数化墙垛：随餐区入户移门加宽/缩窄自动同步墙洞边线",
            roomTag: "kitchen",
            modelingKind: "parametric",
            hostWallGroupID: wallGroupID,
            wallOpeningRole: "pier_after",
            openingSpanAxis: "z"
        )
        let eastWallLintel = WuMindSpatialNode(
            name: "东侧隔墙·门洞过梁",
            category: .wall,
            floorIndex: 0,
            positionMM: .init(x: roomWidthMM / 2, y: doorHeightMM, z: doorCenterZ),
            sizeMM: .init(x: 180, y: lintelHeight, z: doorWidthMM),
            material: .init(preset: .architecturalConcrete),
            dimensionStatus: .confirmedMeasured,
            notes: "参数化过梁：跨度与门洞净宽严格一致",
            roomTag: "kitchen",
            modelingKind: "parametric",
            hostWallGroupID: wallGroupID,
            wallOpeningRole: "lintel",
            openingSpanAxis: "z"
        )
        let kitchenDoorNode = WuMindSpatialNode(
            name: "餐区入户移门",
            category: .door,
            floorIndex: 0,
            positionMM: .init(x: roomWidthMM / 2, y: 0, z: doorCenterZ),
            sizeMM: .init(x: 120, y: doorHeightMM, z: doorWidthMM),
            material: .init(preset: .warmOak),
            dimensionStatus: .confirmedMeasured,
            notes: "参数化门洞构件：支持「把门加宽 200 毫米」并自动同步东侧隔墙门洞与过梁",
            roomTag: "kitchen",
            modelingKind: "parametric",
            hostWallGroupID: wallGroupID,
            wallOpeningRole: "opening_door",
            openingSpanAxis: "z"
        )

        // Adjacent living room nodes (isolated roomTag: "adjacent_living_room" — MUST stay byte-identical when kitchen door changes!)
        let livingFloor = WuMindSpatialNode(
            name: "隔壁客厅·地面楼板",
            category: .floorSlab,
            floorIndex: 0,
            positionMM: .init(x: (roomWidthMM / 2) + 2_100, y: -120, z: 0),
            sizeMM: .init(x: 4_000, y: 120, z: roomDepthMM + 360),
            material: .init(preset: .warmOak),
            dimensionStatus: .confirmedMeasured,
            roomTag: "adjacent_living_room",
            modelingKind: "parametric"
        )
        let livingSofa = WuMindSpatialNode(
            name: "隔壁客厅·三人布艺沙发",
            category: .furniture,
            floorIndex: 0,
            positionMM: .init(x: (roomWidthMM / 2) + 2_400, y: 0, z: -200),
            sizeMM: .init(x: 950, y: 820, z: 2_200),
            material: .init(preset: .brushedSlate),
            dimensionStatus: .conceptDefault,
            notes: "相邻房间家具（修改厨房门洞时应保持完全不变）",
            roomTag: "adjacent_living_room",
            modelingKind: "parametric"
        )
        let livingEastWall = WuMindSpatialNode(
            name: "隔壁客厅·东侧外墙",
            category: .wall,
            floorIndex: 0,
            positionMM: .init(x: (roomWidthMM / 2) + 4_100, y: 0, z: 0),
            sizeMM: .init(x: 180, y: ceilingHeightMM, z: roomDepthMM),
            material: .init(preset: .architecturalConcrete),
            dimensionStatus: .confirmedMeasured,
            roomTag: "adjacent_living_room",
            modelingKind: "parametric"
        )
        let decorativeTripoPlant = WuMindSpatialNode(
            name: "餐区装饰绿植（可选 Tripo 道具）",
            category: .freeformProp,
            floorIndex: 0,
            positionMM: .init(x: 1_550, y: 0, z: -1_400),
            sizeMM: .init(x: 480, y: 1_350, z: 480),
            material: .init(preset: .emeraldTile),
            dimensionStatus: .conceptDefault,
            notes: "非尺寸敏感装饰道具，可选调用 Tripo 3D 生成自由网格替换",
            roomTag: "kitchen",
            modelingKind: "decorative_tripo"
        )

        let nodes: [WuMindSpatialNode] = [
            WuMindSpatialNode(
                name: "厨房与餐区地面楼板",
                category: .floorSlab,
                floorIndex: 0,
                positionMM: .init(x: 0, y: -120, z: 0),
                sizeMM: .init(x: roomWidthMM + 360, y: 120, z: roomDepthMM + 360),
                material: .init(preset: .courtyardStone),
                dimensionStatus: .confirmedMeasured,
                roomTag: "kitchen",
                modelingKind: "parametric"
            ),
            WuMindSpatialNode(
                name: "室内平顶屋面（可隐藏）",
                category: .roof,
                floorIndex: 1,
                positionMM: .init(x: 0, y: ceilingHeightMM, z: 0),
                sizeMM: .init(x: roomWidthMM + 360, y: 160, z: roomDepthMM + 360),
                material: .init(preset: .architecturalConcrete),
                dimensionStatus: lacksCeiling ? .pendingConfirmation(note: "缺少净高实测，建议补测") : .confirmedMeasured,
                roomTag: "kitchen",
                modelingKind: "parametric"
            ),
            northWall, westWall, eastWallNorthPier, eastWallSouthPier, eastWallLintel,
            WuMindSpatialNode(
                name: "北侧采光窗",
                category: .window,
                floorIndex: 0,
                positionMM: .init(x: 1_050, y: 1_050, z: -(roomDepthMM / 2) + 10),
                sizeMM: .init(x: 1_500, y: 1_300, z: 220),
                material: .init(preset: .lowEGlass, opacity: 0.48),
                dimensionStatus: .confirmedMeasured,
                roomTag: "kitchen",
                modelingKind: "parametric"
            ),
            kitchenDoorNode,
            cabinetNode, wallCabNode, islandNode, fridgeNode, diningTableNode,
            WuMindSpatialNode(
                name: "餐区线性吊灯",
                category: .light,
                floorIndex: 0,
                positionMM: .init(x: 350, y: 2_150, z: 1_150),
                sizeMM: .init(x: 1_200, y: 80, z: 120),
                material: .init(preset: .warmCopper),
                dimensionStatus: .conceptDefault,
                roomTag: "kitchen",
                modelingKind: "parametric"
            ),
            decorativeTripoPlant,
            livingFloor, livingSofa, livingEastWall,
        ]

        var auditItems: [WuMindDimensionAuditItem] = [
            .init(label: "厨房开间净宽", valueMM: roomWidthMM, status: .confirmedMeasured, linkedNodeID: northWall.id, guidance: "已核对户型图开间尺寸"),
            .init(label: "厨房+餐区总进深", valueMM: roomDepthMM, status: .confirmedMeasured, linkedNodeID: westWall.id, guidance: "已核对户型图纵深尺寸"),
            .init(label: "主操作台地柜宽", valueMM: baseCabinetWidthMM, status: .confirmedMeasured, linkedNodeID: cabinetNode.id, guidance: "修改柜宽后 3D 构件与导出平面图标注自动同步"),
            .init(label: "餐区入户移门净宽", valueMM: doorWidthMM, status: .confirmedMeasured, linkedNodeID: kitchenDoorNode.id, guidance: "参数化门洞联动：加宽门时东侧墙垛与过梁自动同步，隔壁客厅不变"),
            .init(label: "厨房中岛宽度", valueMM: 1_800, status: .confirmedMeasured, linkedNodeID: islandNode.id, guidance: "满足 950mm 过道通行间距"),
        ]
        if lacksCeiling {
            auditItems.append(.init(
                label: "室内梁下净高（待补测）",
                valueMM: nil,
                status: .pendingConfirmation(note: "上传图纸未标注室内净高，需现场卷尺补测后确认"),
                linkedNodeID: northWall.id,
                guidance: "待确认：暂按 2800mm 概念默认值展示，请实测补录"
            ))
        } else {
            auditItems.append(.init(
                label: "室内净高",
                valueMM: ceilingHeightMM,
                status: .confirmedMeasured,
                linkedNodeID: northWall.id,
                guidance: "已核对净高尺寸"
            ))
        }

        let cameras: [WuMindSpatialCameraPreset] = [
            .init(id: "interior_overview", title: "俯视空间", subtitle: "隐藏顶面查验厨房+餐区与隔壁客厅完整动线", eyeMM: .init(x: 2_800, y: 5_200, z: 5_200), targetMM: .init(x: 800, y: 900, z: -100), fovDeg: 52),
            .init(id: "kitchen_counter", title: "橱柜近景", subtitle: "近看主操作台地柜、吊柜与中岛尺度", eyeMM: .init(x: -200, y: 1_550, z: 1_450), targetMM: .init(x: -700, y: 1_050, z: -1_800), fovDeg: 54),
            .init(id: "dining_view", title: "餐区视角", subtitle: "餐桌、入户移门与开放厨房透视", eyeMM: .init(x: -1_900, y: 1_600, z: 1_900), targetMM: .init(x: 1_500, y: 1_050, z: 1_100), fovDeg: 54),
            .init(id: "door_opening_detail", title: "门洞细部", subtitle: "正视检查餐区移门、过梁与墙垛同步对齐", eyeMM: .init(x: 600, y: 1_450, z: 1_100), targetMM: .init(x: roomWidthMM / 2, y: 1_200, z: 1_100), fovDeg: 50),
        ]

        return WuMindSpatialSceneDocument(
            title: "厨房+餐区精确室内工程",
            sceneType: .interiorSpace,
            creationMode: creationMode,
            sourcePrompt: prompt,
            referenceFilenames: referenceFilenames,
            isConceptScene: false,
            disclaimerBanner: lacksCeiling
                ? "图纸深化室内工程 · 检测到 1 项待补测尺寸（梁下净高），概念深化用途非施工图"
                : "图纸核对室内工程 · 柜体与墙体精确到毫米，导出平面 PDF 与 3D 实时同步（非施工蓝图）",
            weather: .sunny,
            nodes: nodes,
            cameraPresets: cameras,
            dimensionAuditItems: auditItems
        )
    }

    // MARK: - 3. Heterogeneous Modern Waterfront Pavilion / Sci-Fi Exhibition Hall (Non-Palace Architecture)

    public static func buildModernWaterfrontPavilion(
        prompt: String,
        creationMode: WuMindSpatialCreationMode = .textDescription,
        referenceFilenames: [String] = [],
        weather: WuMindSpatialWeather = .sunny,
        overrideType: WuMindSpatialSceneType = .modernPavilion
    ) -> WuMindSpatialSceneDocument {
        let isSciFi = prompt.contains("科幻") || prompt.contains("夜景") || weather == .nightSciFi
        let resolvedWeather: WuMindSpatialWeather = isSciFi ? .nightSciFi : weather
        let eastDoor = prompt.contains("正门改到东侧") || prompt.contains("东侧入口")

        let stageNode = WuMindSpatialNode(
            name: "中央圆形主展台",
            category: .exhibitStage,
            floorIndex: 0,
            positionMM: .init(x: 0, y: 300, z: -1_000),
            sizeMM: .init(x: 6_800, y: 650, z: 6_800),
            material: .init(preset: isSciFi ? .darkMetal : .whiteMarble, roofPreset: .warmCopper),
            detailProfile: .init(isCylindrical: true),
            notes: "可独立选中移动位置、调直径或改暖铜/岩板材质"
        )

        let nodes: [WuMindSpatialNode] = [
            WuMindSpatialNode(
                name: "滨水镜面水景池",
                category: .waterway,
                floorIndex: 0,
                positionMM: .init(x: 0, y: 0, z: 14_500),
                sizeMM: .init(x: 42_000, y: 200, z: 14_000),
                material: .init(preset: .waterJade, opacity: 0.85)
            ),
            WuMindSpatialNode(
                name: "亲水橡木栈道与广场",
                category: .road,
                floorIndex: 0,
                positionMM: .init(x: 0, y: 200, z: 8_200),
                sizeMM: .init(x: 36_000, y: 180, z: 6_400),
                material: .init(preset: .warmOak)
            ),
            WuMindSpatialNode(
                name: "展馆主底板平台",
                category: .floorSlab,
                floorIndex: 0,
                positionMM: .init(x: 0, y: 0, z: -2_000),
                sizeMM: .init(x: 28_000, y: 300, z: 18_000),
                material: .init(preset: .courtyardStone)
            ),
            WuMindSpatialNode(
                name: "二层观景夹层楼板",
                category: .floorSlab,
                floorIndex: 1,
                positionMM: .init(x: 0, y: 4_500, z: -6_500),
                sizeMM: .init(x: 24_000, y: 320, z: 7_000),
                material: .init(preset: .architecturalConcrete)
            ),
            WuMindSpatialNode(
                name: "悬挑白色清水混凝土屋面",
                category: .roof,
                floorIndex: 2,
                positionMM: .init(x: 0, y: 9_200, z: -1_000),
                sizeMM: .init(x: 34_000, y: 550, z: 23_000),
                material: .init(preset: isSciFi ? .darkMetal : .architecturalConcrete),
                notes: "支持一键隐藏屋顶查看展馆内部双层中庭"
            ),
            WuMindSpatialNode(
                name: "南侧大跨低反玻璃幕墙",
                category: .window,
                floorIndex: 0,
                positionMM: .init(x: 0, y: 300, z: 6_800),
                sizeMM: .init(x: 26_000, y: 8_900, z: 240),
                material: .init(preset: .lowEGlass, opacity: 0.42)
            ),
            WuMindSpatialNode(
                name: "北侧清水混凝土主展墙",
                category: .wall,
                floorIndex: 0,
                positionMM: .init(x: 0, y: 300, z: -10_800),
                sizeMM: .init(x: 28_000, y: 8_900, z: 420),
                material: .init(preset: isSciFi ? .brushedSlate : .architecturalConcrete)
            ),
            WuMindSpatialNode(
                name: "西侧实体展墙",
                category: .wall,
                floorIndex: 0,
                positionMM: .init(x: -13_800, y: 300, z: -2_000),
                sizeMM: .init(x: 420, y: 8_900, z: 17_800),
                material: .init(preset: isSciFi ? .brushedSlate : .architecturalConcrete)
            ),
            WuMindSpatialNode(
                name: eastDoor ? "东侧玻璃幕墙与正门入口" : "东侧观景幕墙",
                category: eastDoor ? .door : .window,
                floorIndex: 0,
                positionMM: .init(x: 13_800, y: 300, z: -2_000),
                sizeMM: .init(x: 260, y: 8_900, z: 17_600),
                material: .init(preset: .lowEGlass, opacity: 0.45)
            ),
            stageNode,
            WuMindSpatialNode(
                name: "东侧雕塑矩形展台",
                category: .exhibitStage,
                floorIndex: 0,
                positionMM: .init(x: 7_800, y: 300, z: -2_800),
                sizeMM: .init(x: 3_600, y: 850, z: 2_600),
                material: .init(preset: .warmCopper)
            ),
            WuMindSpatialNode(
                name: "西侧数字交互展台",
                category: .exhibitStage,
                floorIndex: 0,
                positionMM: .init(x: -7_800, y: 300, z: -2_800),
                sizeMM: .init(x: 3_600, y: 850, z: 2_600),
                material: .init(preset: .brushedSlate)
            ),
            WuMindSpatialNode(
                name: "中庭通往二层楼梯",
                category: .stairs,
                floorIndex: 0,
                positionMM: .init(x: -9_500, y: 300, z: -7_200),
                sizeMM: .init(x: 2_400, y: 4_200, z: 5_200),
                material: .init(preset: .warmOak)
            ),
            WuMindSpatialNode(
                name: "滨水景观乔木（东）",
                category: .landscape,
                floorIndex: 0,
                positionMM: .init(x: 18_000, y: 200, z: 8_000),
                sizeMM: .init(x: 4_500, y: 7_200, z: 4_500),
                material: .init(preset: .cypressGreen)
            ),
            WuMindSpatialNode(
                name: "滨水景观乔木（西）",
                category: .landscape,
                floorIndex: 0,
                positionMM: .init(x: -18_000, y: 200, z: 8_000),
                sizeMM: .init(x: 4_500, y: 7_200, z: 4_500),
                material: .init(preset: .cypressGreen)
            ),
            WuMindSpatialNode(
                name: "中庭环形聚光灯架",
                category: .light,
                floorIndex: 1,
                positionMM: .init(x: 0, y: 7_600, z: -1_000),
                sizeMM: .init(x: 7_200, y: 180, z: 7_200),
                material: .init(preset: .warmCopper),
                detailProfile: .init(isCylindrical: true)
            ),
        ]

        let cameras: [WuMindSpatialCameraPreset] = [
            .init(id: "pavilion_aerial", title: "滨水全景", subtitle: "悬挑屋面、镜面水景与木栈道全局", eyeMM: .init(x: 24_000, y: 16_000, z: 32_000), targetMM: .init(x: 0, y: 3_500, z: 0), fovDeg: 50),
            .init(id: "pavilion_boardwalk", title: "栈道低空穿行", subtitle: "沿滨水栈道穿过幕墙望向中央圆形展台", eyeMM: .init(x: 0, y: 2_400, z: 22_000), targetMM: .init(x: 0, y: 2_600, z: -2_000), fovDeg: 58),
            .init(id: "pavilion_stage", title: "主展台近景", subtitle: "近距离检视圆形主展台与夹层空间", eyeMM: .init(x: 6_800, y: 2_800, z: 5_200), targetMM: .init(x: 0, y: 1_200, z: -1_000), fovDeg: 50),
        ]

        return WuMindSpatialSceneDocument(
            title: isSciFi ? "夜景科幻展厅（圆形主展台）" : "现代滨水艺术展馆",
            sceneType: overrideType,
            creationMode: creationMode,
            sourcePrompt: prompt,
            referenceFilenames: referenceFilenames,
            isConceptScene: true,
            disclaimerBanner: "异构现代空间概念工程（\(nodes.count) 个独立可编辑构件，概念默认尺寸，非施工图）",
            weather: resolvedWeather,
            nodes: nodes,
            cameraPresets: cameras,
            dimensionAuditItems: [
                .init(label: "展馆主体面阔（概念默认）", valueMM: 28_000, status: .conceptDefault, guidance: "概念空间默认值"),
                .init(label: "中央圆形主展台直径（概念默认）", valueMM: 6_800, status: .conceptDefault, linkedNodeID: stageNode.id, guidance: "选中后可语音/文字或数值单独修改"),
            ]
        )
    }

    // MARK: - 4. Two-Story White Villa with Terrace & Courtyard (Multi-Floor & Door Orientation)

    public static func buildTwoStoryCourtyardVilla(
        prompt: String,
        creationMode: WuMindSpatialCreationMode = .textDescription,
        referenceFilenames: [String] = [],
        weather: WuMindSpatialWeather = .sunny
    ) -> WuMindSpatialSceneDocument {
        let eastMainDoor = prompt.contains("正门改到东侧") || prompt.contains("东门")
        let terraceNode = WuMindSpatialNode(
            name: "二楼观景露台",
            category: .floorSlab,
            floorIndex: 1,
            positionMM: .init(x: 2_800, y: 3_400, z: 4_400),
            sizeMM: .init(x: 6_000, y: 260, z: 3_200),
            material: .init(preset: .warmOak),
            notes: "试试输入「只把二楼露台加宽一米，其他不动」"
        )
        let doorNode = WuMindSpatialNode(
            name: eastMainDoor ? "东侧主入户门" : "南侧主入户门",
            category: .door,
            floorIndex: 0,
            positionMM: eastMainDoor ? .init(x: 6_100, y: 200, z: 1_200) : .init(x: 0, y: 200, z: 4_550),
            sizeMM: eastMainDoor ? .init(x: 260, y: 2_400, z: 1_600) : .init(x: 1_600, y: 2_400, z: 260),
            material: .init(preset: .warmOak)
        )

        let nodes: [WuMindSpatialNode] = [
            WuMindSpatialNode(name: "内院石板庭院", category: .courtyard, floorIndex: 0, positionMM: .init(x: 0, y: 0, z: 3_500), sizeMM: .init(x: 18_000, y: 200, z: 16_000), material: .init(preset: .courtyardStone)),
            WuMindSpatialNode(name: "内院静水景观池", category: .waterway, floorIndex: 0, positionMM: .init(x: -4_200, y: 120, z: 7_500), sizeMM: .init(x: 6_000, y: 180, z: 3_600), material: .init(preset: .waterJade, opacity: 0.85)),
            WuMindSpatialNode(name: "一层建筑底板", category: .floorSlab, floorIndex: 0, positionMM: .init(x: 0, y: 0, z: -500), sizeMM: .init(x: 12_400, y: 200, z: 10_000), material: .init(preset: .architecturalConcrete)),
            WuMindSpatialNode(name: "一层北侧白墙", category: .wall, floorIndex: 0, positionMM: .init(x: 0, y: 200, z: -5_400), sizeMM: .init(x: 12_200, y: 3_200, z: 260), material: .init(preset: .architecturalConcrete)),
            WuMindSpatialNode(name: "一层西侧白墙", category: .wall, floorIndex: 0, positionMM: .init(x: -6_000, y: 200, z: -500), sizeMM: .init(x: 260, y: 3_200, z: 9_800), material: .init(preset: .architecturalConcrete)),
            WuMindSpatialNode(name: "一层东侧白墙", category: .wall, floorIndex: 0, positionMM: .init(x: 6_000, y: 200, z: -500), sizeMM: .init(x: 260, y: 3_200, z: 9_800), material: .init(preset: .architecturalConcrete)),
            WuMindSpatialNode(name: "一层南侧落地窗", category: .window, floorIndex: 0, positionMM: .init(x: -2_200, y: 200, z: 4_400), sizeMM: .init(x: 5_400, y: 2_900, z: 200), material: .init(preset: .lowEGlass, opacity: 0.45)),
            doorNode,
            WuMindSpatialNode(name: "室内跃层楼梯", category: .stairs, floorIndex: 0, positionMM: .init(x: -4_200, y: 200, z: -2_600), sizeMM: .init(x: 1_400, y: 3_200, z: 3_800), material: .init(preset: .warmOak)),
            WuMindSpatialNode(name: "二层主体楼板", category: .floorSlab, floorIndex: 1, positionMM: .init(x: -1_000, y: 3_400, z: -1_200), sizeMM: .init(x: 10_400, y: 260, z: 8_400), material: .init(preset: .architecturalConcrete)),
            terraceNode,
            WuMindSpatialNode(name: "二层北墙", category: .wall, floorIndex: 1, positionMM: .init(x: -1_000, y: 3_660, z: -5_300), sizeMM: .init(x: 10_200, y: 3_000, z: 240), material: .init(preset: .architecturalConcrete)),
            WuMindSpatialNode(name: "二层西墙", category: .wall, floorIndex: 1, positionMM: .init(x: -6_000, y: 3_660, z: -1_200), sizeMM: .init(x: 240, y: 3_000, z: 8_200), material: .init(preset: .architecturalConcrete)),
            WuMindSpatialNode(name: "二层南向全景窗", category: .window, floorIndex: 1, positionMM: .init(x: -1_000, y: 3_660, z: 2_900), sizeMM: .init(x: 7_200, y: 2_700, z: 200), material: .init(preset: .lowEGlass, opacity: 0.45)),
            WuMindSpatialNode(name: "白色平顶屋面（可隐藏）", category: .roof, floorIndex: 2, positionMM: .init(x: -600, y: 6_660, z: -800), sizeMM: .init(x: 12_200, y: 360, z: 10_200), material: .init(preset: .architecturalConcrete)),
            WuMindSpatialNode(name: "庭院景观树", category: .landscape, floorIndex: 0, positionMM: .init(x: 6_200, y: 200, z: 8_200), sizeMM: .init(x: 3_600, y: 5_400, z: 3_600), material: .init(preset: .cypressGreen)),
        ]

        let cameras: [WuMindSpatialCameraPreset] = [
            .init(id: "villa_overview", title: "建筑全景", subtitle: "两层白色体块、二楼露台与内院水景", eyeMM: .init(x: 16_000, y: 12_000, z: 20_000), targetMM: .init(x: 0, y: 3_000, z: 1_000), fovDeg: 48),
            .init(id: "villa_courtyard", title: "内院视角", subtitle: "低角度仰看二楼露台与落地窗", eyeMM: .init(x: 3_500, y: 1_800, z: 13_500), targetMM: .init(x: 0, y: 3_400, z: 1_000), fovDeg: 56),
            .init(id: "villa_door", title: "主门近景", subtitle: "检查正门朝向与外墙细节", eyeMM: eastMainDoor ? .init(x: 13_500, y: 2_400, z: 5_200) : .init(x: 0, y: 2_200, z: 11_000), targetMM: doorNode.positionMM, fovDeg: 48),
        ]

        return WuMindSpatialSceneDocument(
            title: "两层白色内院别墅（概念版）",
            sceneType: .villaBuilding,
            creationMode: creationMode,
            sourcePrompt: prompt,
            referenceFilenames: referenceFilenames,
            isConceptScene: true,
            weather: weather,
            nodes: nodes,
            cameraPresets: cameras,
            dimensionAuditItems: [
                .init(label: "二楼露台宽度（概念默认）", valueMM: 6_000, status: .conceptDefault, linkedNodeID: terraceNode.id, guidance: "支持自然语言或数值单独加宽，其余不动"),
                .init(label: "主入户门宽（概念默认）", valueMM: 1_600, status: .conceptDefault, linkedNodeID: doorNode.id, guidance: eastMainDoor ? "已按要求置于东侧" : "默认南向"),
            ]
        )
    }

    // MARK: - Surgical Single-Node Editing & Version History (Zero Side Effects on Other Nodes!)

    public struct NodeEditOutcome: Equatable, Sendable {
        public let updatedScene: WuMindSpatialSceneDocument
        public let summary: String

        public init(updatedScene: WuMindSpatialSceneDocument, summary: String) {
            self.updatedScene = updatedScene
            self.summary = summary
        }
    }

    /// Applies a surgical single-node edit from a Chinese/English natural-language instruction
    /// (e.g. `"只把二楼露台加宽一米，其他不动"`, `"把东配殿屋顶改为翠绿琉璃瓦"`, `"把主操作台地柜加宽 200 毫米"`).
    /// Strictly mutates ONLY `nodeID`, pushes previous state to `savedVersions`, and syncs linked dimension audit items.
    public static func applyNaturalLanguageEdit(
        scene: WuMindSpatialSceneDocument,
        nodeID: UUID,
        instruction: String
    ) -> NodeEditOutcome {
        guard let idx = scene.nodes.firstIndex(where: { $0.id == nodeID }) else {
            return NodeEditOutcome(updatedScene: scene, summary: "未找到目标构件。")
        }

        let clean = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return NodeEditOutcome(updatedScene: scene, summary: "请输入修改要求。")
        }

        var next = pushSnapshot(onto: scene, label: "修改前：\(scene.nodes[idx].name)")
        var target = next.nodes[idx]
        var changes: [String] = []

        // 1. Parse delta distance in millimeters (supports "200毫米", "200mm", "1.5米", "一米", "两米", "0.5m")
        let deltaMM = parseSignedDeltaMM(in: clean)
        let spanIsZ = (target.openingSpanAxis == "z")

        if clean.contains("加宽") || clean.contains("变宽") || clean.contains("宽加") || clean.contains("柜宽") || clean.contains("门宽") {
            let amt = abs(deltaMM ?? 500)
            if spanIsZ {
                target.sizeMM.z += amt
                changes.append("洞口净宽 +\(amt)mm（现 \(target.sizeMM.z)mm）")
            } else {
                target.sizeMM.x += amt
                changes.append("宽度 +\(amt)mm（现 \(target.sizeMM.x)mm）")
            }
        } else if clean.contains("减宽") || clean.contains("变窄") || clean.contains("缩窄") {
            let amt = abs(deltaMM ?? 300)
            if spanIsZ {
                target.sizeMM.z = max(600, target.sizeMM.z - amt)
                changes.append("洞口净宽 -\(amt)mm（现 \(target.sizeMM.z)mm）")
            } else {
                target.sizeMM.x = max(200, target.sizeMM.x - amt)
                changes.append("宽度 -\(amt)mm（现 \(target.sizeMM.x)mm）")
            }
        }

        if clean.contains("加高") || clean.contains("增高") || clean.contains("拉高") {
            let amt = abs(deltaMM ?? 500)
            target.sizeMM.y += amt
            changes.append("高度 +\(amt)mm（现 \(target.sizeMM.y)mm）")
        } else if clean.contains("降低") || clean.contains("矮") {
            let amt = abs(deltaMM ?? 500)
            target.sizeMM.y = max(120, target.sizeMM.y - amt)
            changes.append("高度 -\(amt)mm（现 \(target.sizeMM.y)mm）")
        }

        if clean.contains("加深") || clean.contains("加长") {
            let amt = abs(deltaMM ?? 500)
            target.sizeMM.z += amt
            changes.append("进深 +\(amt)mm（现 \(target.sizeMM.z)mm）")
        }

        // 2. Position translation
        if clean.contains("东移") || clean.contains("右移") || clean.contains("向右") {
            let amt = abs(deltaMM ?? 2_000)
            target.positionMM.x += amt
            changes.append("向东/右移动 \(amt)mm")
        } else if clean.contains("西移") || clean.contains("左移") || clean.contains("向左") {
            let amt = abs(deltaMM ?? 2_000)
            target.positionMM.x -= amt
            changes.append("向西/左移动 \(amt)mm")
        }
        if clean.contains("南移") || clean.contains("前移") || clean.contains("向前") {
            let amt = abs(deltaMM ?? 2_000)
            target.positionMM.z += amt
            changes.append("向南/前移动 \(amt)mm")
        } else if clean.contains("北移") || clean.contains("后移") || clean.contains("向后") {
            let amt = abs(deltaMM ?? 2_000)
            target.positionMM.z -= amt
            changes.append("向北/后移动 \(amt)mm")
        }

        // 3. Roof color / Material preset changes
        if let matPreset = detectMaterialPreset(in: clean) {
            if clean.contains("屋顶") || clean.contains("瓦") || target.category == .palaceHall || target.category == .gateTower {
                target.material.roofPreset = matPreset
                target.material.roofHex = matPreset.hexColor
                changes.append("屋顶材质改为「\(matPreset.displayName)」")
            } else {
                target.material.preset = matPreset
                target.material.primaryHex = matPreset.hexColor
                changes.append("主体材质改为「\(matPreset.displayName)」")
            }
        }

        if clean.contains("隐藏") {
            target.isVisible = false
            changes.append("已隐藏该构件")
        } else if clean.contains("显示") {
            target.isVisible = true
            changes.append("已显示该构件")
        }

        if changes.isEmpty {
            // Safe fallback if user wrote a stylistic tweak without explicit preset
            target.notes = "局部指令：\(clean)"
            changes.append("已记录局部修改备注「\(clean)」")
        }

        next.nodes[idx] = target
        let syncedWallParts = synchronizeHostWallOpening(scene: &next, openingNodeIndex: idx)
        let finalTarget = next.nodes[idx]
        syncLinkedDimensionAudit(scene: &next, node: finalTarget)
        next.updatedAt = Date()

        let untouchedCount = max(0, next.nodes.count - 1 - syncedWallParts.count)
        let summary: String
        if syncedWallParts.isEmpty {
            summary = "仅更新「\(finalTarget.name)」（\(changes.joined(separator: "、"))），其余 \(untouchedCount) 个构件未改动。"
        } else {
            summary = "已更新「\(finalTarget.name)」（\(changes.joined(separator: "、"))），并自动同步 \(syncedWallParts.count) 个宿主墙洞构件（\(syncedWallParts.joined(separator: "、"))），其余 \(untouchedCount) 个构件与相邻房间保持不变。"
        }
        return NodeEditOutcome(updatedScene: next, summary: summary)
    }

    /// Applies an exact numeric dimension / position / material update onto a single node.
    /// When the target node is a parametric wall opening, its host wall piers and lintel stay 100% synchronized.
    public static func applyExactNodePatch(
        scene: WuMindSpatialSceneDocument,
        nodeID: UUID,
        sizeDeltaMM: WuMindVec3MM? = nil,
        positionDeltaMM: WuMindVec3MM? = nil,
        roofPreset: WuMindSpatialMaterialPreset? = nil,
        bodyPreset: WuMindSpatialMaterialPreset? = nil,
        label: String = "精确数值调整"
    ) -> WuMindSpatialSceneDocument {
        guard let idx = scene.nodes.firstIndex(where: { $0.id == nodeID }) else { return scene }
        var next = pushSnapshot(onto: scene, label: "\(label)：\(scene.nodes[idx].name)")
        var target = next.nodes[idx]
        if let sd = sizeDeltaMM {
            target.sizeMM.x = max(100, target.sizeMM.x + sd.x)
            target.sizeMM.y = max(80, target.sizeMM.y + sd.y)
            target.sizeMM.z = max(100, target.sizeMM.z + sd.z)
        }
        if let pd = positionDeltaMM {
            target.positionMM.x += pd.x
            target.positionMM.y += pd.y
            target.positionMM.z += pd.z
        }
        if let roofPreset {
            target.material.roofPreset = roofPreset
            target.material.roofHex = roofPreset.hexColor
        }
        if let bodyPreset {
            target.material.preset = bodyPreset
            target.material.primaryHex = bodyPreset.hexColor
        }
        next.nodes[idx] = target
        _ = synchronizeHostWallOpening(scene: &next, openingNodeIndex: idx)
        syncLinkedDimensionAudit(scene: &next, node: next.nodes[idx])
        next.updatedAt = Date()
        return next
    }

    /// Synchronizes parametric host wall piers (`pier_before`, `pier_after`) and `lintel` whenever an
    /// `opening_door` node changes span or height, keeping 0mm gap/overlap and leaving all other rooms untouched.
    @discardableResult
    public static func synchronizeHostWallOpening(
        scene: inout WuMindSpatialSceneDocument,
        openingNodeIndex: Int
    ) -> [String] {
        guard scene.nodes.indices.contains(openingNodeIndex) else { return [] }
        var opening = scene.nodes[openingNodeIndex]
        guard let groupID = opening.hostWallGroupID,
              !groupID.isEmpty,
              opening.wallOpeningRole == "opening_door" else {
            return []
        }

        let pierBeforeIdx = scene.nodes.firstIndex(where: { $0.hostWallGroupID == groupID && $0.wallOpeningRole == "pier_before" })
        let pierAfterIdx = scene.nodes.firstIndex(where: { $0.hostWallGroupID == groupID && $0.wallOpeningRole == "pier_after" })
        let lintelIdx = scene.nodes.firstIndex(where: { $0.hostWallGroupID == groupID && $0.wallOpeningRole == "lintel" })
        guard let beforeIdx = pierBeforeIdx, let afterIdx = pierAfterIdx else { return [] }

        let spanIsZ = (opening.openingSpanAxis == "z")
        let minPierMM = 150
        let beforeNode = scene.nodes[beforeIdx]
        let afterNode = scene.nodes[afterIdx]

        let wallMin = spanIsZ
            ? (beforeNode.positionMM.z - beforeNode.sizeMM.z / 2)
            : (beforeNode.positionMM.x - beforeNode.sizeMM.x / 2)
        let wallMax = spanIsZ
            ? (afterNode.positionMM.z + afterNode.sizeMM.z / 2)
            : (afterNode.positionMM.x + afterNode.sizeMM.x / 2)
        let maxOpeningSpan = max(600, (wallMax - wallMin) - minPierMM * 2)

        var openingSpan = min(maxOpeningSpan, spanIsZ ? opening.sizeMM.z : opening.sizeMM.x)
        var openingCenter = spanIsZ ? opening.positionMM.z : opening.positionMM.x

        let minCenter = wallMin + minPierMM + openingSpan / 2
        let maxCenter = wallMax - minPierMM - openingSpan / 2
        if minCenter <= maxCenter {
            openingCenter = max(minCenter, min(maxCenter, openingCenter))
        } else {
            openingCenter = (wallMin + wallMax) / 2
            openingSpan = maxOpeningSpan
        }

        let openingMin = openingCenter - openingSpan / 2
        let openingMax = openingMin + openingSpan
        let newBeforeLen = max(minPierMM, openingMin - wallMin)
        let newAfterLen = max(minPierMM, wallMax - openingMax)

        if spanIsZ {
            opening.sizeMM.z = openingSpan
            opening.positionMM.z = openingCenter
        } else {
            opening.sizeMM.x = openingSpan
            opening.positionMM.x = openingCenter
        }
        scene.nodes[openingNodeIndex] = opening

        var syncedNames: [String] = []
        var updatedBefore = beforeNode
        if spanIsZ {
            updatedBefore.sizeMM.z = newBeforeLen
            updatedBefore.positionMM.z = wallMin + newBeforeLen / 2
        } else {
            updatedBefore.sizeMM.x = newBeforeLen
            updatedBefore.positionMM.x = wallMin + newBeforeLen / 2
        }
        scene.nodes[beforeIdx] = updatedBefore
        syncedNames.append(updatedBefore.name)

        var updatedAfter = afterNode
        if spanIsZ {
            updatedAfter.sizeMM.z = newAfterLen
            updatedAfter.positionMM.z = openingMax + newAfterLen / 2
        } else {
            updatedAfter.sizeMM.x = newAfterLen
            updatedAfter.positionMM.x = openingMax + newAfterLen / 2
        }
        scene.nodes[afterIdx] = updatedAfter
        syncedNames.append(updatedAfter.name)

        if let lintelIdx {
            var updatedLintel = scene.nodes[lintelIdx]
            let wallTopY = max(updatedBefore.positionMM.y + updatedBefore.sizeMM.y, updatedAfter.positionMM.y + updatedAfter.sizeMM.y)
            let openingTopY = opening.positionMM.y + opening.sizeMM.y
            let lintelHeight = max(80, wallTopY - openingTopY)
            if spanIsZ {
                updatedLintel.sizeMM.z = openingSpan
                updatedLintel.positionMM.z = openingCenter
            } else {
                updatedLintel.sizeMM.x = openingSpan
                updatedLintel.positionMM.x = openingCenter
            }
            updatedLintel.positionMM.y = openingTopY
            updatedLintel.sizeMM.y = lintelHeight
            scene.nodes[lintelIdx] = updatedLintel
            syncedNames.append(updatedLintel.name)
        }

        return syncedNames
    }

    // MARK: - Self-Verifying 3D Geometry, Multi-View & GLB Delivery Audit (Argona Run-Check-Deliver Pattern)

    public struct WallOpeningAudit: Equatable, Sendable {
        public let hostWallGroupID: String
        public let openingName: String
        public let openingWidthMM: Int
        public let beforeEdgeGapMM: Int
        public let afterEdgeGapMM: Int
        public let lintelSpanErrorMM: Int
        public let lintelElevationErrorMM: Int

        public var isPerfectlySynced: Bool {
            beforeEdgeGapMM == 0 && afterEdgeGapMM == 0 && lintelSpanErrorMM == 0 && lintelElevationErrorMM == 0
        }
    }

    public struct SceneSelfVerificationReport: Equatable, Sendable {
        public let openingAudits: [WallOpeningAudit]
        public let checkedCameraViewIDs: [String]
        public let parametricNodeCount: Int
        public let decorativeTripoNodeCount: Int
        public let glbValidated: Bool
        public let glbNodeCount: Int
        public let glbByteCount: Int
        public let projectRoundTripPassed: Bool
        public let issues: [String]
        /// Honest separation: automated modeling/geometry/GLB checks run offline without claiming real iPhone testing.
        public let automatedModelCheckPassed: Bool
        public let physicalDeviceTested: Bool

        public var summaryLine: String {
            let openingsOK = openingAudits.allSatisfy(\.isPerfectlySynced)
            return "参数化构件 \(parametricNodeCount) 个 · Tripo 装饰道具 \(decorativeTripoNodeCount) 个 · 多视角检查 \(checkedCameraViewIDs.count) 组 · 门洞墙体联动 \(openingsOK ? "0mm误差通过" : "发现异常") · GLB \(glbValidated ? "已验(\(glbNodeCount)节点/\(glbByteCount)B)" : "未通过") · 工程重载 \(projectRoundTripPassed ? "通过" : "失败") · 真机实测：\(physicalDeviceTested ? "已实测" : "未在真机运行")"
        }
    }

    /// Deterministically checks wall-opening geometric alignment (0mm gap/overlap), multi-view cameras,
    /// editable JSON round-trip, and multi-node GLB export BEFORE delivering a 3D scene to the user.
    public static func verifySceneGeometryAndMultiView(
        scene: WuMindSpatialSceneDocument
    ) -> SceneSelfVerificationReport {
        var issues: [String] = []
        var openingAudits: [WallOpeningAudit] = []

        let openings = scene.nodes.filter { $0.wallOpeningRole == "opening_door" && ($0.hostWallGroupID?.isEmpty == false) }
        for opening in openings {
            guard let groupID = opening.hostWallGroupID else { continue }
            let spanIsZ = (opening.openingSpanAxis == "z")
            let before = scene.nodes.first(where: { $0.hostWallGroupID == groupID && $0.wallOpeningRole == "pier_before" })
            let after = scene.nodes.first(where: { $0.hostWallGroupID == groupID && $0.wallOpeningRole == "pier_after" })
            let lintel = scene.nodes.first(where: { $0.hostWallGroupID == groupID && $0.wallOpeningRole == "lintel" })

            guard let before, let after, let lintel else {
                issues.append("墙洞组「\(groupID)」缺少完整的左右墙垛或过梁构件")
                continue
            }

            let openCenter = spanIsZ ? opening.positionMM.z : opening.positionMM.x
            let openSpan = spanIsZ ? opening.sizeMM.z : opening.sizeMM.x
            let openMin = openCenter - openSpan / 2
            let openMax = openMin + openSpan

            let beforeMax = spanIsZ
                ? (before.positionMM.z + before.sizeMM.z / 2)
                : (before.positionMM.x + before.sizeMM.x / 2)
            let afterMin = spanIsZ
                ? (after.positionMM.z - after.sizeMM.z / 2)
                : (after.positionMM.x - after.sizeMM.x / 2)
            let lintelSpan = spanIsZ ? lintel.sizeMM.z : lintel.sizeMM.x
            let lintelElevErr = lintel.positionMM.y - (opening.positionMM.y + opening.sizeMM.y)

            let audit = WallOpeningAudit(
                hostWallGroupID: groupID,
                openingName: opening.name,
                openingWidthMM: openSpan,
                beforeEdgeGapMM: openMin - beforeMax,
                afterEdgeGapMM: afterMin - openMax,
                lintelSpanErrorMM: lintelSpan - openSpan,
                lintelElevationErrorMM: lintelElevErr
            )
            openingAudits.append(audit)
            if !audit.isPerfectlySynced {
                issues.append("门洞「\(opening.name)」与宿主墙存在误差（前垛差 \(audit.beforeEdgeGapMM)mm、后垛差 \(audit.afterEdgeGapMM)mm、过梁跨度差 \(audit.lintelSpanErrorMM)mm）")
            }
        }

        let checkedViews = scene.cameraPresets.map(\.id)
        if checkedViews.count < 3 {
            issues.append("多视角预检镜头少于 3 组（当前 \(checkedViews.count) 组）")
        }

        var glbValidated = false
        var glbNodeCount = 0
        var glbByteCount = 0
        do {
            let glbData = try WuMindSpatialGLBExporter.exportGLB(scene: scene)
            let report = try WuMindSpatialGLBExporter.validateGLB(glbData)
            glbByteCount = glbData.count
            glbNodeCount = report.nodeCount
            glbValidated = (report.version == 2 && report.nodeCount == scene.nodes.filter(\.isVisible).count)
            if !glbValidated {
                issues.append("GLB 节点数（\(report.nodeCount)）与可见构件数不一致")
            }
        } catch {
            issues.append("GLB 导出或校验失败：\(error.localizedDescription)")
        }

        var roundTripOK = false
        do {
            let json = try encodeProjectJSON(scene)
            let reloaded = try decodeProjectJSON(json)
            roundTripOK = (reloaded.nodes == scene.nodes && reloaded.dimensionAuditItems == scene.dimensionAuditItems)
            if !roundTripOK {
                issues.append("可编辑工程 JSON 往返反序列化后节点数据不一致")
            }
        } catch {
            issues.append("可编辑工程 JSON 序列化失败：\(error.localizedDescription)")
        }

        let decorativeCount = scene.nodes.filter { $0.modelingKind == "decorative_tripo" || $0.category == .freeformProp }.count
        let parametricCount = scene.nodes.count - decorativeCount
        let allPassed = issues.isEmpty && glbValidated && roundTripOK && openingAudits.allSatisfy(\.isPerfectlySynced)

        return SceneSelfVerificationReport(
            openingAudits: openingAudits,
            checkedCameraViewIDs: checkedViews,
            parametricNodeCount: parametricCount,
            decorativeTripoNodeCount: decorativeCount,
            glbValidated: glbValidated,
            glbNodeCount: glbNodeCount,
            glbByteCount: glbByteCount,
            projectRoundTripPassed: roundTripOK,
            issues: issues,
            automatedModelCheckPassed: allPassed,
            physicalDeviceTested: false
        )
    }

    public static func undo(scene: WuMindSpatialSceneDocument) -> WuMindSpatialSceneDocument? {
        var next = scene
        guard let last = next.savedVersions.popLast() else { return nil }
        next.nodes = last.nodes
        next.weather = last.weather
        for node in next.nodes {
            syncLinkedDimensionAudit(scene: &next, node: node)
        }
        next.updatedAt = Date()
        return next
    }

    public static func encodeProjectJSON(_ scene: WuMindSpatialSceneDocument) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(scene)
    }

    public static func decodeProjectJSON(_ data: Data) throws -> WuMindSpatialSceneDocument {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(WuMindSpatialSceneDocument.self, from: data)
    }

    // MARK: - Helpers

    private static func pushSnapshot(onto scene: WuMindSpatialSceneDocument, label: String) -> WuMindSpatialSceneDocument {
        var next = scene
        let snap = WuMindSpatialSceneSnapshot(label: label, nodes: scene.nodes, weather: scene.weather)
        next.savedVersions.append(snap)
        if next.savedVersions.count > 20 {
            next.savedVersions.removeFirst(next.savedVersions.count - 20)
        }
        return next
    }

    private static func syncLinkedDimensionAudit(scene: inout WuMindSpatialSceneDocument, node: WuMindSpatialNode) {
        for idx in scene.dimensionAuditItems.indices {
            if scene.dimensionAuditItems[idx].linkedNodeID == node.id {
                scene.dimensionAuditItems[idx].valueMM = node.primaryWidthMM
            }
        }
    }

    private static func detectWeather(in text: String) -> WuMindSpatialWeather {
        if text.contains("雪") || text.contains("冬") { return .snowy }
        if text.contains("夜") || text.contains("科幻") || text.contains("霓虹") { return .nightSciFi }
        return .sunny
    }

    private static func detectMaterialPreset(in text: String) -> WuMindSpatialMaterialPreset? {
        if text.contains("翠绿") || text.contains("绿瓦") || text.contains("绿色") { return .emeraldTile }
        if text.contains("金") || text.contains("黄瓦") || text.contains("明黄") { return .glazedGoldTile }
        if text.contains("朱红") || text.contains("红墙") || text.contains("红色") { return .imperialCrimson }
        if text.contains("汉白玉") || text.contains("大理石") { return .whiteMarble }
        if text.contains("青砖") || text.contains("灰瓦") || text.contains("青瓦") { return .greyBrick }
        if text.contains("清水") || text.contains("白色") { return .architecturalConcrete }
        if text.contains("玻璃") { return .lowEGlass }
        if text.contains("橡木") || text.contains("木色") || text.contains("木纹") { return .warmOak }
        if text.contains("岩板") { return .brushedSlate }
        if text.contains("铜") { return .warmCopper }
        if text.contains("深灰") || text.contains("金属") || text.contains("黑") { return .darkMetal }
        return nil
    }

    private static func parseSignedDeltaMM(in text: String) -> Int? {
        // Explicit Chinese unit phrases first
        if text.contains("两米") || text.contains("二米") { return 2_000 }
        if text.contains("一米半") { return 1_500 }
        if text.contains("半米") { return 500 }
        if text.contains("一米") { return 1_000 }

        // Regex for numbers + mm/毫米/cm/厘米/m/米
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(毫米|mm|厘米|cm|米|m)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let numRange = Range(match.range(at: 1), in: text),
           let unitRange = Range(match.range(at: 2), in: text),
           let value = Double(text[numRange]) {
            let unit = text[unitRange].lowercased()
            switch unit {
            case "毫米", "mm": return Int(value.rounded())
            case "厘米", "cm": return Int((value * 10.0).rounded())
            case "米", "m": return Int((value * 1000.0).rounded())
            default: return Int(value.rounded())
            }
        }
        return nil
    }

    private static func parseMM(in text: String, keywords: [String]) -> Int? {
        for kw in keywords {
            guard let range = text.range(of: kw) else { continue }
            let slice = String(text[range.lowerBound...].prefix(36))
            if let mm = parseSignedDeltaMM(in: slice), mm >= 300, mm <= 200_000 {
                return mm
            }
        }
        return nil
    }

    private static func computeDefaultCameras(
        for nodes: [WuMindSpatialNode],
        sceneType: WuMindSpatialSceneType
    ) -> [WuMindSpatialCameraPreset] {
        let maxX = nodes.map { abs($0.positionMM.x) + $0.sizeMM.x / 2 }.max() ?? 10_000
        let maxZ = nodes.map { abs($0.positionMM.z) + $0.sizeMM.z / 2 }.max() ?? 10_000
        let maxY = nodes.map { $0.positionMM.y + $0.sizeMM.y }.max() ?? 6_000
        let span = max(maxX, maxZ, 5_000)

        return [
            .init(
                id: "overview",
                title: sceneType == .imperialComplex ? "全景俯瞰" : "全景鸟瞰",
                subtitle: "完整建筑群与空间布局总览",
                eyeMM: .init(x: Int(Double(span) * 0.95), y: Int(Double(span) * 0.85), z: Int(Double(span) * 1.25)),
                targetMM: .init(x: 0, y: maxY / 3, z: 0),
                fovDeg: 50
            ),
            .init(
                id: "walkthrough",
                title: "低空穿行",
                subtitle: "沿中轴与主要动线低空游览",
                eyeMM: .init(x: 0, y: max(1_800, maxY / 5), z: Int(Double(span) * 0.85)),
                targetMM: .init(x: 0, y: max(1_600, maxY / 3), z: -span / 4),
                fovDeg: 58
            ),
            .init(
                id: "closeup",
                title: "建筑近景",
                subtitle: "近距检查屋檐、柱列、台阶与材质",
                eyeMM: .init(x: span / 3, y: max(2_200, maxY / 2), z: Int(Double(span) * 0.60)),
                targetMM: .init(x: 0, y: maxY / 3, z: 0),
                fovDeg: 46
            ),
        ]
    }

    private static func extractJSONObject(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.firstIndex(of: "{"),
              let last = trimmed.lastIndex(of: "}"),
              first < last else {
            return trimmed
        }
        return String(trimmed[first...last])
    }

    private struct RawScenePayload: Decodable {
        struct RawNode: Decodable {
            let name: String?
            let category: String?
            let floorIndex: Int?
            let x: Int?
            let y: Int?
            let z: Int?
            let width: Int?
            let height: Int?
            let depth: Int?
            let rotationYDeg: Double?
            let preset: String?
            let roofPreset: String?
            let dimensionStatus: String?
            let eaveTiers: Int?
            let columnCountX: Int?
            let columnCountZ: Int?
            let plinthHeightMM: Int?
            let archCount: Int?
            let isCylindrical: Bool?
            let hasBridgeArches: Bool?
            let note: String?
        }
        struct RawAudit: Decodable {
            let label: String?
            let valueMM: Int?
            let status: String?
            let guidance: String?
        }
        let title: String?
        let weather: String?
        let nodes: [RawNode]?
        let dimensionAudit: [RawAudit]?
    }
}

// MARK: - Optional Tripo 3D Freeform Prop Client (Decorative Props Only — Never Whole Building!)

/// Official Tripo 3D OpenAPI client strictly scoped to standalone decorative `.freeformProp` assets
/// (e.g., courtyard sculpture, bespoke exhibition art piece). Main architecture ALWAYS stays parametric & editable.
public struct Tripo3DPropClient: Sendable {
    public static let defaultBaseURL = "https://api.tripo3d.ai"
    private let transport: MultiProviderAIClient.Transport?

    public init(transport: MultiProviderAIClient.Transport? = nil) {
        self.transport = transport
    }

    public func submitPropTask(prompt: String, apiKey: String) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw AIVideoToolError.generationFailed("请先配置 Tripo 3D 官方 API Key（仅用于生成可摆入场景的自由造型单件道具）。")
        }
        let clean = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw AIVideoToolError.invalidPrompt }

        guard let url = URL(string: "\(Self.defaultBaseURL)/v2/openapi/task") else {
            throw MultiProviderAIError.invalidRequest
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.httpShouldHandleCookies = false
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(
            withJSONObject: ["type": "text_to_model", "prompt": clean],
            options: [.withoutEscapingSlashes]
        )

        let result: (Data, URLResponse)
        if let transport {
            result = try await transport(req)
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.httpShouldSetCookies = false
            result = try await URLSession(configuration: cfg).data(for: req)
        }
        guard let http = result.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MultiProviderAIError.invalidResponse
        }
        struct Envelope: Decodable {
            struct DataObj: Decodable {
                let taskID: String?
                enum CodingKeys: String, CodingKey { case taskID = "task_id" }
            }
            let code: Int?
            let data: DataObj?
        }
        let parsed = try JSONDecoder().decode(Envelope.self, from: result.0)
        guard let tid = parsed.data?.taskID, !tid.isEmpty else {
            throw MultiProviderAIError.invalidResponse
        }
        return tid
    }
}
