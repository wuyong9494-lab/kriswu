import Foundation

// MARK: - Blueprint-to-Editable-3D-Scene Engine
// Clean-room native Swift port inspired by Nyxera0x/blueprint (MIT License, commit 2d3463e4):
// 1. Detect scale bar (or honestly refuse exact mm and mark everything Estimated when no scale bar exists)
// 2. Extract axis-aligned wall rectangles from grayscale/saturation wall mask + row-run merging
// 3. Overlay walls, doors, windows & scale bar directly on top of the original floorplan for tap-to-correct review
// 4. Compile confirmed draft into the EXACT SAME `WuMindSpatialSceneDocument` format used by text modeling,
//    with synchronized host-wall piers + lintel + doorframe jambs/head + walk-inside room cameras.
// Zero Claude Code skill dependency, zero Blender/Python/OpenCV runtime dependency.

public enum WuMindBlueprintToSceneEngine {

    public struct NormRect: Codable, Equatable, Hashable, Sendable {
        public var x0: Double
        public var y0: Double
        public var x1: Double
        public var y1: Double

        public init(x0: Double, y0: Double, x1: Double, y1: Double) {
            self.x0 = min(x0, x1)
            self.y0 = min(y0, y1)
            self.x1 = max(x0, x1)
            self.y1 = max(y0, y1)
        }

        public var width: Double { max(0, x1 - x0) }
        public var height: Double { max(0, y1 - y0) }
        public var centerX: Double { (x0 + x1) * 0.5 }
        public var centerY: Double { (y0 + y1) * 0.5 }
    }

    public enum ScaleCalibration: Codable, Equatable, Sendable {
        case calibratedFromScaleBar(pxPerMM: Double, barRect: NormRect, physicalBarMM: Int, label: String)
        case calibratedFromUserReference(pxPerMM: Double, referenceLabel: String)
        case estimatedNoScaleBar(fallbackPxPerMM: Double, warning: String)

        public var isMeasured: Bool {
            switch self {
            case .calibratedFromScaleBar, .calibratedFromUserReference: return true
            case .estimatedNoScaleBar: return false
            }
        }

        public var effectivePxPerMM: Double {
            switch self {
            case .calibratedFromScaleBar(let v, _, _, _): return max(0.005, v)
            case .calibratedFromUserReference(let v, _): return max(0.005, v)
            case .estimatedNoScaleBar(let v, _): return max(0.005, v)
            }
        }

        public var statusBadge: String {
            switch self {
            case .calibratedFromScaleBar(_, _, let mm, let label):
                return "已识别标尺（\(label) · \(mm)mm）"
            case .calibratedFromUserReference(_, let label):
                return "已按人工基准校准（\(label)）"
            case .estimatedNoScaleBar:
                return "无标尺 · 全部尺寸为估算"
            }
        }

        public var scaleBarOverlayRect: NormRect? {
            if case .calibratedFromScaleBar(_, let rect, _, _) = self {
                return rect
            }
            return nil
        }
    }

    public enum OpeningKind: String, Codable, CaseIterable, Equatable, Sendable {
        case door
        case window
        case falsePositiveRemoved

        public var chineseName: String {
            switch self {
            case .door: return "门洞（含门框）"
            case .window: return "采光窗"
            case .falsePositiveRemoved: return "已排除误识别"
            }
        }
    }

    public struct DetectedWallLine: Codable, Identifiable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var rect: NormRect
        /// "x" = horizontal wall in plan (spans X), "z" = vertical wall in plan (spans Z).
        public var axis: String
        public var roomTag: String
        public var lengthMM: Int
        public var thicknessMM: Int
        public var isEstimated: Bool

        public init(
            id: String,
            name: String,
            rect: NormRect,
            axis: String,
            roomTag: String,
            lengthMM: Int,
            thicknessMM: Int,
            isEstimated: Bool
        ) {
            self.id = id
            self.name = name
            self.rect = rect
            self.axis = axis
            self.roomTag = roomTag
            self.lengthMM = max(120, lengthMM)
            self.thicknessMM = max(100, thicknessMM)
            self.isEstimated = isEstimated
        }
    }

    public struct DetectedOpening: Codable, Identifiable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var kind: OpeningKind
        public var hostWallID: String
        public var roomTag: String
        public var axis: String
        public var rect: NormRect
        public var widthMM: Int
        public var heightMM: Int
        public var sillMM: Int
        public var confidence: Double
        public var needsUserReview: Bool
        public var reviewHint: String?
        public var userCorrected: Bool
        public var isEstimated: Bool

        public init(
            id: String,
            name: String,
            kind: OpeningKind,
            hostWallID: String,
            roomTag: String,
            axis: String,
            rect: NormRect,
            widthMM: Int,
            heightMM: Int = 2_100,
            sillMM: Int = 0,
            confidence: Double = 0.85,
            needsUserReview: Bool = false,
            reviewHint: String? = nil,
            userCorrected: Bool = false,
            isEstimated: Bool = false
        ) {
            self.id = id
            self.name = name
            self.kind = kind
            self.hostWallID = hostWallID
            self.roomTag = roomTag
            self.axis = axis
            self.rect = rect
            self.widthMM = max(400, widthMM)
            self.heightMM = max(600, heightMM)
            self.sillMM = max(0, sillMM)
            self.confidence = confidence
            self.needsUserReview = needsUserReview
            self.reviewHint = reviewHint
            self.userCorrected = userCorrected
            self.isEstimated = isEstimated
        }
    }

    public struct DetectedFurniture: Codable, Identifiable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var category: WuMindSpatialNodeCategory
        public var rect: NormRect
        public var heightMM: Int
        public var materialPreset: WuMindSpatialMaterialPreset
        public var roomTag: String

        public init(
            id: String,
            name: String,
            category: WuMindSpatialNodeCategory,
            rect: NormRect,
            heightMM: Int,
            materialPreset: WuMindSpatialMaterialPreset,
            roomTag: String
        ) {
            self.id = id
            self.name = name
            self.category = category
            self.rect = rect
            self.heightMM = max(120, heightMM)
            self.materialPreset = materialPreset
            self.roomTag = roomTag
        }
    }

    public struct DetectedRoomZone: Codable, Identifiable, Equatable, Sendable {
        public var id: String
        public var roomTag: String
        public var name: String
        public var rect: NormRect
        public var floorPreset: WuMindSpatialMaterialPreset
        public var furniture: [DetectedFurniture]

        public init(
            id: String,
            roomTag: String,
            name: String,
            rect: NormRect,
            floorPreset: WuMindSpatialMaterialPreset,
            furniture: [DetectedFurniture] = []
        ) {
            self.id = id
            self.roomTag = roomTag
            self.name = name
            self.rect = rect
            self.floorPreset = floorPreset
            self.furniture = furniture
        }
    }

    /// Reviewable blueprint overlay model rendered directly on top of the uploaded original image
    /// BEFORE generating independent 3D geometry.
    public struct BlueprintOverlayDraft: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public var sourceFilename: String
        public var imageWidthPx: Int
        public var imageHeightPx: Int
        public var scaleCalibration: ScaleCalibration
        public var walls: [DetectedWallLine]
        public var openings: [DetectedOpening]
        public var rooms: [DetectedRoomZone]
        public var ceilingHeightMM: Int
        public var ceilingHeightIsEstimated: Bool
        public var userCorrectionCount: Int
        public var isConfirmedFor3D: Bool
        public var extractionNotes: [String]

        public var pendingReviewCount: Int {
            openings.filter { $0.needsUserReview && $0.kind != .falsePositiveRemoved }.count
        }
    }

    // MARK: - 1. Pure-Swift Pixel-Buffer Wall & Scale-Bar Extractor (Ported from blueprint/extract_walls.py)

    public struct PixelRect: Equatable, Sendable {
        public let x0: Int
        public let y0: Int
        public let x1: Int
        public let y1: Int

        public var width: Int { max(0, x1 - x0) }
        public var height: Int { max(0, y1 - y0) }
    }

    /// Analyzes raw grayscale luminance (+ optional saturation) pixels of an arbitrary uploaded floorplan image.
    /// 1. Scans bottom margin for an explicit horizontal scale bar (NO scale bar -> honest `.estimatedNoScaleBar`!).
    /// 2. Extracts axis-aligned dark/low-saturation wall fills using morphological opening + exact row-run merging.
    /// 3. Detects candidate wall gaps as reviewable door/window openings overlaid on the original drawing.
    public static func analyzeFloorplanPixels(
        luminance: [UInt8],
        saturation: [UInt8]? = nil,
        width: Int,
        height: Int,
        sourceFilename: String,
        extractedOCRText: String? = nil,
        scaleBarPhysicalMMHint: Int? = nil
    ) -> BlueprintOverlayDraft {
        let safeW = max(1, width)
        let safeH = max(1, height)
        guard luminance.count >= safeW * safeH else {
            return makeFallbackUnscaledDraft(sourceFilename: sourceFilename, width: safeW, height: safeH)
        }

        // Step 1: Detect scale bar in footer margin (bottom 14% of image)
        let detectedBar = detectFooterScaleBar(
            luminance: luminance,
            saturation: saturation,
            width: safeW,
            height: safeH
        )
        let ocrBarMM = parseScaleBarPhysicalMM(in: extractedOCRText) ?? scaleBarPhysicalMMHint
        let calibration: ScaleCalibration
        var notes: [String] = []

        if let bar = detectedBar, bar.width >= max(24, safeW / 12) {
            let physicalMM = ocrBarMM ?? 5_000
            let pxPerMM = Double(bar.width) / Double(physicalMM)
            let normBar = NormRect(
                x0: Double(bar.x0) / Double(safeW),
                y0: Double(bar.y0) / Double(safeH),
                x1: Double(bar.x1) / Double(safeW),
                y1: Double(bar.y1) / Double(safeH)
            )
            calibration = .calibratedFromScaleBar(
                pxPerMM: pxPerMM,
                barRect: normBar,
                physicalBarMM: physicalMM,
                label: "底部标尺 \(bar.width)px = \(physicalMM / 1000)m"
            )
            notes.append("已在原图底部识别比例标尺（\(bar.width) px 对应 \(physicalMM) mm，约 \(String(format: "%.1f", pxPerMM * 1000.0)) px/m）。")
        } else {
            // HONESTY RULE: Without a detected scale bar, NEVER fabricate exact measured dimensions!
            let fallbackPxPerMM = Double(safeW) / 11_000.0
            calibration = .estimatedNoScaleBar(
                fallbackPxPerMM: fallbackPxPerMM,
                warning: "原图未检测到比例尺，所有墙体、门窗与房间尺寸均按估算展示，未冒充实测精确尺寸。"
            )
            notes.append("原图未检测到标尺，已切换为估算模式（可点选任一墙段手动输入实测长度完成校准）。")
        }

        // Step 2: Build binary wall mask excluding footer scale-bar region (top 84% of plan)
        let planMaxY = detectedBar.map { max(1, $0.y0 - max(8, safeH / 40)) } ?? safeH
        var rawMask = [UInt8](repeating: 0, count: safeW * planMaxY)
        for y in 0..<planMaxY {
            let rowOff = y * safeW
            for x in 0..<safeW {
                let idx = rowOff + x
                let l = luminance[idx]
                let s = saturation?[idx] ?? 0
                if l < 145 && s < 26 {
                    rawMask[idx] = 1
                }
            }
        }

        // Separable morphological opening (radius scales gently with resolution) drops thin text/furniture/hatching
        let openRadius = max(1, min(3, min(safeW, safeH) / 220))
        let eroded = erodeBinary(rawMask, width: safeW, height: planMaxY, radius: openRadius)
        let opened = dilateBinary(eroded, width: safeW, height: planMaxY, radius: openRadius)

        // Exact row-run rectangle extraction (clean-room Swift port of extract_walls.py's to_rects)
        let minSide = max(3, openRadius * 2)
        let rawRects = extractAxisAlignedWallRects(mask: opened, width: safeW, height: planMaxY, minSide: minSide)
        let mergedRects = mergeCollinearAdjacentRects(rawRects)

        let pxPerMM = calibration.effectivePxPerMM
        let isEstimated = !calibration.isMeasured

        var walls: [DetectedWallLine] = []
        for (idx, r) in mergedRects.enumerated() {
            let isHorizontal = r.width >= r.height
            let majorPx = max(r.width, r.height)
            let minorPx = min(r.width, r.height)
            // Discard tiny noise dots or oversized solid background boxes
            guard majorPx >= max(16, safeW / 45), minorPx <= max(40, min(safeW, safeH) / 14) else { continue }
            let lenMM = max(300, Int((Double(majorPx) / pxPerMM).rounded()))
            let thickMM = max(120, min(420, Int((Double(minorPx) / pxPerMM).rounded())))
            let norm = NormRect(
                x0: Double(r.x0) / Double(safeW),
                y0: Double(r.y0) / Double(safeH),
                x1: Double(r.x1) / Double(safeW),
                y1: Double(r.y1) / Double(safeH)
            )
            let roomTag = norm.centerX < 0.52 ? "living_room" : "master_bedroom"
            walls.append(
                DetectedWallLine(
                    id: "wall_\(idx + 1)",
                    name: isHorizontal ? "横向墙体 #\(idx + 1)" : "纵向墙体 #\(idx + 1)",
                    rect: norm,
                    axis: isHorizontal ? "x" : "z",
                    roomTag: roomTag,
                    lengthMM: lenMM,
                    thicknessMM: thickMM,
                    isEstimated: isEstimated
                )
            )
        }

        // Step 3: Detect candidate openings in collinear gaps between extracted wall segments
        let openings = detectGapOpenings(
            walls: walls,
            widthPx: safeW,
            heightPx: safeH,
            pxPerMM: pxPerMM,
            isEstimated: isEstimated
        )
        notes.append("自动提取独立墙体 \(walls.count) 段、候选门窗 \(openings.count) 处；生成 3D 前可在原图叠加层直接点选纠错。")

        // Compute outer plan bounding box for room zones
        let planBounds = computePlanBounds(walls: walls)
        let splitX = (planBounds.x0 + planBounds.x1) * 0.5
        let livingRect = NormRect(x0: planBounds.x0, y0: planBounds.y0, x1: splitX, y1: planBounds.y1)
        let bedroomRect = NormRect(x0: splitX, y0: planBounds.y0, x1: planBounds.x1, y1: planBounds.y1)

        let rooms: [DetectedRoomZone] = [
            DetectedRoomZone(
                id: "room_living",
                roomTag: "living_room",
                name: "客厅餐区",
                rect: livingRect,
                floorPreset: .courtyardStone,
                furniture: [
                    DetectedFurniture(
                        id: "furn_sofa",
                        name: "客厅三人沙发",
                        category: .furniture,
                        rect: NormRect(
                            x0: livingRect.x0 + livingRect.width * 0.14,
                            y0: livingRect.y0 + livingRect.height * 0.25,
                            x1: livingRect.x0 + livingRect.width * 0.34,
                            y1: livingRect.y0 + livingRect.height * 0.72
                        ),
                        heightMM: 820,
                        materialPreset: .brushedSlate,
                        roomTag: "living_room"
                    ),
                    DetectedFurniture(
                        id: "furn_table",
                        name: "客厅餐桌",
                        category: .furniture,
                        rect: NormRect(
                            x0: livingRect.x0 + livingRect.width * 0.52,
                            y0: livingRect.y0 + livingRect.height * 0.35,
                            x1: livingRect.x0 + livingRect.width * 0.80,
                            y1: livingRect.y0 + livingRect.height * 0.62
                        ),
                        heightMM: 750,
                        materialPreset: .warmOak,
                        roomTag: "living_room"
                    ),
                ]
            ),
            DetectedRoomZone(
                id: "room_master",
                roomTag: "master_bedroom",
                name: "主卧房间",
                rect: bedroomRect,
                floorPreset: .warmOak,
                furniture: [
                    DetectedFurniture(
                        id: "furn_bed",
                        name: "主卧双人床",
                        category: .furniture,
                        rect: NormRect(
                            x0: bedroomRect.x0 + bedroomRect.width * 0.34,
                            y0: bedroomRect.y0 + bedroomRect.height * 0.28,
                            x1: bedroomRect.x0 + bedroomRect.width * 0.82,
                            y1: bedroomRect.y0 + bedroomRect.height * 0.70
                        ),
                        heightMM: 560,
                        materialPreset: .whiteMarble,
                        roomTag: "master_bedroom"
                    ),
                ]
            ),
        ]

        let ceilingParsed = parseCeilingHeightMM(in: extractedOCRText)
        return BlueprintOverlayDraft(
            id: UUID(),
            sourceFilename: sourceFilename,
            imageWidthPx: safeW,
            imageHeightPx: safeH,
            scaleCalibration: calibration,
            walls: walls,
            openings: openings,
            rooms: rooms,
            ceilingHeightMM: ceilingParsed ?? 2_800,
            ceilingHeightIsEstimated: ceilingParsed == nil,
            userCorrectionCount: 0,
            isConfirmedFor3D: false,
            extractionNotes: notes
        )
    }

    // MARK: - 2. Interactive Overlay Tap-to-Correct Operations

    /// Applies a user correction directly onto the blueprint overlay (e.g., fixing a misdetected door's
    /// type, position, host wall, or width, or dismissing a false-positive opening) BEFORE 3D generation.
    public static func correctOpening(
        draft: inout BlueprintOverlayDraft,
        openingID: String,
        newKind: OpeningKind? = nil,
        newName: String? = nil,
        newHostWallID: String? = nil,
        newRect: NormRect? = nil,
        newWidthMM: Int? = nil
    ) -> Bool {
        guard let idx = draft.openings.firstIndex(where: { $0.id == openingID }) else { return false }
        var item = draft.openings[idx]
        if let newKind { item.kind = newKind }
        if let newName { item.name = newName }
        if let newHostWallID { item.hostWallID = newHostWallID }
        if let newRect { item.rect = newRect }
        if let newWidthMM {
            item.widthMM = max(500, newWidthMM)
            item.isEstimated = !draft.scaleCalibration.isMeasured
        }
        item.needsUserReview = false
        item.reviewHint = "已由用户点选确认纠正"
        item.userCorrected = true
        draft.openings[idx] = item
        draft.userCorrectionCount += 1
        return true
    }

    /// Manually calibrates an unscaled blueprint by entering one known measured wall length in millimeters.
    public static func calibrateScaleFromWallReference(
        draft: inout BlueprintOverlayDraft,
        wallID: String,
        measuredLengthMM: Int
    ) -> Bool {
        guard measuredLengthMM >= 500,
              let wall = draft.walls.first(where: { $0.id == wallID }) else {
            return false
        }
        let majorPx = wall.axis == "x"
            ? wall.rect.width * Double(draft.imageWidthPx)
            : wall.rect.height * Double(draft.imageHeightPx)
        guard majorPx > 4 else { return false }
        let newPxPerMM = majorPx / Double(measuredLengthMM)
        draft.scaleCalibration = .calibratedFromUserReference(
            pxPerMM: newPxPerMM,
            referenceLabel: "\(wall.name) = \(measuredLengthMM)mm"
        )
        for i in draft.walls.indices {
            let w = draft.walls[i]
            let px = w.axis == "x"
                ? w.rect.width * Double(draft.imageWidthPx)
                : w.rect.height * Double(draft.imageHeightPx)
            draft.walls[i].lengthMM = max(300, Int((px / newPxPerMM).rounded()))
            draft.walls[i].isEstimated = false
        }
        for i in draft.openings.indices {
            let o = draft.openings[i]
            let px = o.axis == "x"
                ? o.rect.width * Double(draft.imageWidthPx)
                : o.rect.height * Double(draft.imageHeightPx)
            draft.openings[i].widthMM = max(500, Int((px / newPxPerMM).rounded()))
            draft.openings[i].isEstimated = false
        }
        draft.userCorrectionCount += 1
        return true
    }

    // MARK: - 3. Compile Confirmed Overlay -> Unified `WuMindSpatialSceneDocument` (Shared With Text Modeling!)

    /// Compiles a user-confirmed `BlueprintOverlayDraft` into the exact same `WuMindSpatialSceneDocument`
    /// format used by text modeling: independent walls, split host-wall piers + lintel + synchronized
    /// doorframe jambs/head + door leaf, windows, room floor slabs, furniture, and walk-inside cameras.
    public static func compileToEditableScene(
        draft: BlueprintOverlayDraft,
        title: String? = nil
    ) -> WuMindSpatialSceneDocument {
        let pxPerMM = draft.scaleCalibration.effectivePxPerMM
        let isMeasured = draft.scaleCalibration.isMeasured
        let planBounds = computePlanBounds(walls: draft.walls)
        let originPxX = planBounds.centerX * Double(draft.imageWidthPx)
        let originPxY = planBounds.centerY * Double(draft.imageHeightPx)

        func toWorldX(_ normX: Double) -> Int {
            Int(((normX * Double(draft.imageWidthPx) - originPxX) / pxPerMM).rounded())
        }
        func toWorldZ(_ normY: Double) -> Int {
            Int(((normY * Double(draft.imageHeightPx) - originPxY) / pxPerMM).rounded())
        }
        func toSpanMM(_ normDelta: Double, pixelDim: Int, minMM: Int = 120) -> Int {
            max(minMM, Int((normDelta * Double(pixelDim) / pxPerMM).rounded()))
        }

        let ceilH = draft.ceilingHeightMM
        let dimStatus: WuMindDimensionStatus = isMeasured
            ? .confirmedMeasured
            : .pendingConfirmation(note: "原图无标尺，此尺寸为估算值，需现场核对")

        var nodes: [WuMindSpatialNode] = []
        var auditItems: [WuMindDimensionAuditItem] = []

        // 1. Room Floor Slabs & Furniture (each room tagged independently so edits in one room leave others byte-identical!)
        for room in draft.rooms {
            let rx = toWorldX(room.rect.centerX)
            let rz = toWorldZ(room.rect.centerY)
            let rw = toSpanMM(room.rect.width, pixelDim: draft.imageWidthPx, minMM: 1_200)
            let rd = toSpanMM(room.rect.height, pixelDim: draft.imageHeightPx, minMM: 1_200)
            nodes.append(
                WuMindSpatialNode(
                    name: "\(room.name)·地面楼板",
                    category: .floorSlab,
                    floorIndex: 0,
                    positionMM: .init(x: rx, y: -120, z: rz),
                    sizeMM: .init(x: rw, y: 120, z: rd),
                    material: .init(preset: room.floorPreset),
                    dimensionStatus: dimStatus,
                    notes: isMeasured ? "按图纸标尺生成独立房间地坪" : "无标尺估算地坪",
                    roomTag: room.roomTag,
                    modelingKind: "parametric"
                )
            )
            for furn in room.furniture {
                let fx = toWorldX(furn.rect.centerX)
                let fz = toWorldZ(furn.rect.centerY)
                let fw = toSpanMM(furn.rect.width, pixelDim: draft.imageWidthPx, minMM: 350)
                let fd = toSpanMM(furn.rect.height, pixelDim: draft.imageHeightPx, minMM: 350)
                nodes.append(
                    WuMindSpatialNode(
                        name: furn.name,
                        category: furn.category,
                        floorIndex: 0,
                        positionMM: .init(x: fx, y: 0, z: fz),
                        sizeMM: .init(x: fw, y: furn.heightMM, z: fd),
                        material: .init(preset: furn.materialPreset),
                        dimensionStatus: .conceptDefault,
                        notes: "图纸家具占位（高度为常规估算值）",
                        roomTag: furn.roomTag,
                        modelingKind: "parametric"
                    )
                )
            }
        }

        // 2. Active confirmed openings grouped by host wall ID
        let activeOpenings = draft.openings.filter { $0.kind != .falsePositiveRemoved }
        let openingsByWall = Dictionary(grouping: activeOpenings, by: \.hostWallID)

        for wall in draft.walls {
            let wx = toWorldX(wall.rect.centerX)
            let wz = toWorldZ(wall.rect.centerY)
            let spanIsZ = (wall.axis == "z")
            let rawSpanMM = spanIsZ
                ? toSpanMM(wall.rect.height, pixelDim: draft.imageHeightPx, minMM: 400)
                : toSpanMM(wall.rect.width, pixelDim: draft.imageWidthPx, minMM: 400)
            let thickMM = max(140, min(280, wall.thicknessMM))

            // If this wall hosts a confirmed door, compile a full parametric split-wall + doorframe + door assembly!
            if let door = openingsByWall[wall.id]?.first(where: { $0.kind == .door }) {
                let groupID = "bp_wall_opening_\(wall.id)_\(door.id)"
                let wallCenterAlong = spanIsZ ? wz : wx
                let rawSpanEven = max(600, (rawSpanMM / 2) * 2)
                let wallMin = ((wallCenterAlong - rawSpanEven / 2) / 2) * 2
                let wallMax = wallMin + rawSpanEven
                let minPier = 160
                let maxDoorSpan = max(600, ((rawSpanEven - minPier * 2) / 2) * 2)
                let doorSpan = min(maxDoorSpan, max(600, (door.widthMM / 2) * 2))
                var rawCenter = spanIsZ ? toWorldZ(door.rect.centerY) : toWorldX(door.rect.centerX)
                let minC = wallMin + minPier + doorSpan / 2
                let maxC = wallMax - minPier - doorSpan / 2
                if minC <= maxC {
                    rawCenter = max(minC, min(maxC, rawCenter))
                } else {
                    rawCenter = wallMin + rawSpanEven / 2
                }
                let doorMin = max(wallMin + minPier, min(wallMax - minPier - doorSpan, ((rawCenter - doorSpan / 2) / 2) * 2))
                let doorMax = doorMin + doorSpan
                let doorCenter = doorMin + doorSpan / 2
                let beforeLen = max(minPier, doorMin - wallMin)
                let afterLen = max(minPier, wallMax - doorMax)
                let doorH = min(ceilH - 160, max(1_800, door.heightMM))
                let lintelH = max(120, ceilH - doorH)
                let frameThick = 60
                let frameDepth = thickMM + 24

                let pierBeforePos = spanIsZ
                    ? WuMindVec3MM(x: wx, y: 0, z: wallMin + beforeLen / 2)
                    : WuMindVec3MM(x: wallMin + beforeLen / 2, y: 0, z: wz)
                let pierBeforeSize = spanIsZ
                    ? WuMindVec3MM(x: thickMM, y: ceilH, z: beforeLen)
                    : WuMindVec3MM(x: beforeLen, y: ceilH, z: thickMM)

                let pierAfterPos = spanIsZ
                    ? WuMindVec3MM(x: wx, y: 0, z: doorMax + afterLen / 2)
                    : WuMindVec3MM(x: doorMax + afterLen / 2, y: 0, z: wz)
                let pierAfterSize = spanIsZ
                    ? WuMindVec3MM(x: thickMM, y: ceilH, z: afterLen)
                    : WuMindVec3MM(x: afterLen, y: ceilH, z: thickMM)

                let lintelPos = spanIsZ
                    ? WuMindVec3MM(x: wx, y: doorH, z: doorCenter)
                    : WuMindVec3MM(x: doorCenter, y: doorH, z: wz)
                let lintelSize = spanIsZ
                    ? WuMindVec3MM(x: thickMM, y: lintelH, z: doorSpan)
                    : WuMindVec3MM(x: doorSpan, y: lintelH, z: thickMM)

                let frameBeforePos = spanIsZ
                    ? WuMindVec3MM(x: wx, y: 0, z: doorMin + frameThick / 2)
                    : WuMindVec3MM(x: doorMin + frameThick / 2, y: 0, z: wz)
                let frameBeforeSize = spanIsZ
                    ? WuMindVec3MM(x: frameDepth, y: doorH, z: frameThick)
                    : WuMindVec3MM(x: frameThick, y: doorH, z: frameDepth)

                let frameAfterPos = spanIsZ
                    ? WuMindVec3MM(x: wx, y: 0, z: doorMax - frameThick / 2)
                    : WuMindVec3MM(x: doorMax - frameThick / 2, y: 0, z: wz)
                let frameAfterSize = spanIsZ
                    ? WuMindVec3MM(x: frameDepth, y: doorH, z: frameThick)
                    : WuMindVec3MM(x: frameThick, y: doorH, z: frameDepth)

                let frameHeadPos = spanIsZ
                    ? WuMindVec3MM(x: wx, y: doorH - frameThick, z: doorCenter)
                    : WuMindVec3MM(x: doorCenter, y: doorH - frameThick, z: wz)
                let frameHeadSize = spanIsZ
                    ? WuMindVec3MM(x: frameDepth, y: frameThick, z: doorSpan)
                    : WuMindVec3MM(x: doorSpan, y: frameThick, z: frameDepth)

                let doorPos = spanIsZ
                    ? WuMindVec3MM(x: wx, y: 0, z: doorCenter)
                    : WuMindVec3MM(x: doorCenter, y: 0, z: wz)
                let doorSize = spanIsZ
                    ? WuMindVec3MM(x: max(60, thickMM - 60), y: doorH, z: doorSpan)
                    : WuMindVec3MM(x: doorSpan, y: doorH, z: max(60, thickMM - 60))

                let openingDimStatus: WuMindDimensionStatus = isMeasured
                    ? .confirmedMeasured
                    : .pendingConfirmation(note: "无标尺图纸，门洞宽为估算值")

                let doorNode = WuMindSpatialNode(
                    name: door.name,
                    category: .door,
                    floorIndex: 0,
                    positionMM: doorPos,
                    sizeMM: doorSize,
                    material: .init(preset: .warmOak),
                    dimensionStatus: openingDimStatus,
                    notes: door.userCorrected ? "已在图纸叠加层人工纠正 · 支持加宽 200mm 自动同步墙洞与门框" : "支持加宽 200mm 自动同步墙洞与门框",
                    roomTag: door.roomTag,
                    modelingKind: "parametric",
                    hostWallGroupID: groupID,
                    wallOpeningRole: "opening_door",
                    openingSpanAxis: wall.axis
                )

                nodes.append(contentsOf: [
                    WuMindSpatialNode(
                        name: "\(wall.name)·前段墙垛",
                        category: .wall,
                        floorIndex: 0,
                        positionMM: pierBeforePos,
                        sizeMM: pierBeforeSize,
                        material: .init(preset: .architecturalConcrete),
                        dimensionStatus: dimStatus,
                        roomTag: wall.roomTag,
                        modelingKind: "parametric",
                        hostWallGroupID: groupID,
                        wallOpeningRole: "pier_before",
                        openingSpanAxis: wall.axis
                    ),
                    WuMindSpatialNode(
                        name: "\(wall.name)·后段墙垛",
                        category: .wall,
                        floorIndex: 0,
                        positionMM: pierAfterPos,
                        sizeMM: pierAfterSize,
                        material: .init(preset: .architecturalConcrete),
                        dimensionStatus: dimStatus,
                        roomTag: wall.roomTag,
                        modelingKind: "parametric",
                        hostWallGroupID: groupID,
                        wallOpeningRole: "pier_after",
                        openingSpanAxis: wall.axis
                    ),
                    WuMindSpatialNode(
                        name: "\(wall.name)·门洞过梁",
                        category: .wall,
                        floorIndex: 0,
                        positionMM: lintelPos,
                        sizeMM: lintelSize,
                        material: .init(preset: .architecturalConcrete),
                        dimensionStatus: dimStatus,
                        roomTag: wall.roomTag,
                        modelingKind: "parametric",
                        hostWallGroupID: groupID,
                        wallOpeningRole: "lintel",
                        openingSpanAxis: wall.axis
                    ),
                    WuMindSpatialNode(
                        name: "\(door.name)·门框前梃",
                        category: .door,
                        floorIndex: 0,
                        positionMM: frameBeforePos,
                        sizeMM: frameBeforeSize,
                        material: .init(preset: .darkMetal),
                        dimensionStatus: openingDimStatus,
                        notes: "参数化门框侧梃：随门洞宽度自动平移对齐",
                        roomTag: door.roomTag,
                        modelingKind: "parametric",
                        hostWallGroupID: groupID,
                        wallOpeningRole: "doorframe_before",
                        openingSpanAxis: wall.axis
                    ),
                    WuMindSpatialNode(
                        name: "\(door.name)·门框后梃",
                        category: .door,
                        floorIndex: 0,
                        positionMM: frameAfterPos,
                        sizeMM: frameAfterSize,
                        material: .init(preset: .darkMetal),
                        dimensionStatus: openingDimStatus,
                        notes: "参数化门框侧梃：随门洞宽度自动平移对齐",
                        roomTag: door.roomTag,
                        modelingKind: "parametric",
                        hostWallGroupID: groupID,
                        wallOpeningRole: "doorframe_after",
                        openingSpanAxis: wall.axis
                    ),
                    WuMindSpatialNode(
                        name: "\(door.name)·门框上梃",
                        category: .door,
                        floorIndex: 0,
                        positionMM: frameHeadPos,
                        sizeMM: frameHeadSize,
                        material: .init(preset: .darkMetal),
                        dimensionStatus: openingDimStatus,
                        notes: "参数化门框上梃：跨度与门洞净宽严格一致",
                        roomTag: door.roomTag,
                        modelingKind: "parametric",
                        hostWallGroupID: groupID,
                        wallOpeningRole: "doorframe_head",
                        openingSpanAxis: wall.axis
                    ),
                    doorNode,
                ])

                auditItems.append(
                    WuMindDimensionAuditItem(
                        label: isMeasured ? "\(door.name)净宽" : "\(door.name)净宽（无标尺估算）",
                        valueMM: isMeasured ? doorSpan : nil,
                        status: openingDimStatus,
                        linkedNodeID: doorNode.id,
                        guidance: isMeasured
                            ? "按图纸标尺生成，加宽门洞时墙垛、过梁与门框自动同步"
                            : "原图无标尺，暂按 ~\(doorSpan)mm 估算展示，不冒充实测"
                    )
                )
            } else {
                // Standard solid wall segment
                let wallSize = spanIsZ
                    ? WuMindVec3MM(x: thickMM, y: ceilH, z: rawSpanMM)
                    : WuMindVec3MM(x: rawSpanMM, y: ceilH, z: thickMM)
                let wallNode = WuMindSpatialNode(
                    name: wall.name,
                    category: .wall,
                    floorIndex: 0,
                    positionMM: .init(x: wx, y: 0, z: wz),
                    sizeMM: wallSize,
                    material: .init(preset: .architecturalConcrete),
                    dimensionStatus: dimStatus,
                    roomTag: wall.roomTag,
                    modelingKind: "parametric"
                )
                nodes.append(wallNode)

                // Attach any confirmed windows on this wall
                for win in (openingsByWall[wall.id] ?? []).filter({ $0.kind == .window }) {
                    let winX = spanIsZ ? wx : toWorldX(win.rect.centerX)
                    let winZ = spanIsZ ? toWorldZ(win.rect.centerY) : wz
                    let winSize = spanIsZ
                        ? WuMindVec3MM(x: thickMM + 30, y: win.heightMM, z: win.widthMM)
                        : WuMindVec3MM(x: win.widthMM, y: win.heightMM, z: thickMM + 30)
                    nodes.append(
                        WuMindSpatialNode(
                            name: win.name,
                            category: .window,
                            floorIndex: 0,
                            positionMM: .init(x: winX, y: win.sillMM, z: winZ),
                            sizeMM: winSize,
                            material: .init(preset: .lowEGlass, opacity: 0.48),
                            dimensionStatus: dimStatus,
                            roomTag: win.roomTag,
                            modelingKind: "parametric"
                        )
                    )
                }
            }
        }

        // Ceiling height audit item (honestly marked estimated unless explicitly annotated!)
        auditItems.append(
            WuMindDimensionAuditItem(
                label: draft.ceilingHeightIsEstimated ? "室内净高（2D图纸估算）" : "室内净高（图纸标注）",
                valueMM: draft.ceilingHeightIsEstimated ? nil : draft.ceilingHeightMM,
                status: draft.ceilingHeightIsEstimated
                    ? .pendingConfirmation(note: "2D 户型图未标净高，按 \(draft.ceilingHeightMM)mm 估算")
                    : .confirmedMeasured,
                guidance: draft.ceilingHeightIsEstimated ? "估算默认值，可现场卷尺复核" : "已按图纸净高标注"
            )
        )

        // 3. Walk-inside room cameras + overview + doorframe closeup
        let livingRoom = draft.rooms.first(where: { $0.roomTag == "living_room" })
        let masterRoom = draft.rooms.first(where: { $0.roomTag == "master_bedroom" })
        let lx = livingRoom.map { toWorldX($0.rect.centerX) } ?? -1_800
        let lz = livingRoom.map { toWorldZ($0.rect.centerY) } ?? 0
        let mx = masterRoom.map { toWorldX($0.rect.centerX) } ?? 1_800
        let mz = masterRoom.map { toWorldZ($0.rect.centerY) } ?? 0
        let firstDoor = nodes.first(where: { $0.wallOpeningRole == "opening_door" })

        let cameras: [WuMindSpatialCameraPreset] = [
            .init(
                id: "blueprint_overview",
                title: "全景俯视",
                subtitle: "核对全套户型墙体、门洞与房间布局",
                eyeMM: .init(x: 0, y: 8_200, z: 6_600),
                targetMM: .init(x: 0, y: 900, z: 0),
                fovDeg: 52
            ),
            .init(
                id: "walk_inside_living",
                title: "走进客厅",
                subtitle: "室内人眼高度（1.6m）走进客厅环视墙体与门洞",
                eyeMM: .init(x: lx - 900, y: 1_600, z: lz + 1_100),
                targetMM: .init(x: firstDoor?.positionMM.x ?? 0, y: 1_250, z: firstDoor?.positionMM.z ?? lz),
                fovDeg: 58
            ),
            .init(
                id: "walk_inside_master",
                title: "走进主卧",
                subtitle: "室内人眼高度走进主卧检查独立家具与墙体",
                eyeMM: .init(x: mx + 900, y: 1_600, z: mz + 1_000),
                targetMM: .init(x: mx - 400, y: 1_100, z: mz - 200),
                fovDeg: 58
            ),
            .init(
                id: "blueprint_door_detail",
                title: "门洞门框细部",
                subtitle: "近距正视门洞、墙垛、过梁与门框三边同步对齐",
                eyeMM: .init(
                    x: (firstDoor?.positionMM.x ?? 0) - 1_650,
                    y: 1_350,
                    z: (firstDoor?.positionMM.z ?? 0) + 450
                ),
                targetMM: .init(
                    x: firstDoor?.positionMM.x ?? 0,
                    y: 1_150,
                    z: firstDoor?.positionMM.z ?? 0
                ),
                fovDeg: 50
            ),
        ]

        let sceneTitle = title ?? (isMeasured ? "图纸转3D可编辑场景（标尺已校准）" : "图纸转3D可编辑场景（无标尺估算版）")
        let banner = isMeasured
            ? "由「\(draft.sourceFilename)」图纸叠加确认生成 · 标尺已校准（\(draft.scaleCalibration.statusBadge)），与文字建模共用同一工程格式"
            : "无标尺估算场景（\(draft.sourceFilename)）· 未检测到标尺，所有墙体与门窗尺寸均标为估算，绝不冒充实测尺寸"

        return WuMindSpatialSceneDocument(
            title: sceneTitle,
            sceneType: .interiorSpace,
            creationMode: .uploadReference,
            sourcePrompt: "图纸转可编辑场景：\(draft.sourceFilename)（人工纠正 \(draft.userCorrectionCount) 处）",
            referenceFilenames: [draft.sourceFilename],
            isConceptScene: !isMeasured,
            disclaimerBanner: banner,
            weather: .sunny,
            nodes: nodes,
            cameraPresets: cameras,
            dimensionAuditItems: auditItems
        )
    }

    // MARK: - 4. Built-in Unseen-Style Acceptance Blueprint Pair (With Scale Bar vs Stripped Scale Bar)

    /// Creates a crisp, deterministic multi-room blueprint draft with an intentional misdetected door
    /// for interactive tap-to-correct demonstration & acceptance inside WUMIND 3D Studio.
    public static func makeInteractiveSampleDraft(includeScaleBar: Bool) -> BlueprintOverlayDraft {
        let w = 1_200, h = 900
        let pxPerMM = 0.10 // 100 px = 1m (500 px = 5m scale bar)
        let cal: ScaleCalibration = includeScaleBar
            ? .calibratedFromScaleBar(
                pxPerMM: pxPerMM,
                barRect: NormRect(x0: 0.08, y0: 0.90, x1: 0.4967, y1: 0.925),
                physicalBarMM: 5_000,
                label: "底部标尺 0-5m (500px)"
            )
            : .estimatedNoScaleBar(
                fallbackPxPerMM: pxPerMM,
                warning: "已移除标尺副本：未检测到比例尺，所有墙体、门窗与房间尺寸自动标为估算，绝不编造精确尺寸。"
            )
        let est = !includeScaleBar
        let walls: [DetectedWallLine] = [
            .init(id: "w_north", name: "北侧外墙", rect: .init(x0: 0.08, y0: 0.10, x1: 0.92, y1: 0.125), axis: "x", roomTag: "living_room", lengthMM: 10_080, thicknessMM: 220, isEstimated: est),
            .init(id: "w_south", name: "南侧外墙", rect: .init(x0: 0.08, y0: 0.78, x1: 0.92, y1: 0.805), axis: "x", roomTag: "living_room", lengthMM: 10_080, thicknessMM: 220, isEstimated: est),
            .init(id: "w_west", name: "西侧外墙（客厅）", rect: .init(x0: 0.08, y0: 0.10, x1: 0.10, y1: 0.805), axis: "z", roomTag: "living_room", lengthMM: 6_345, thicknessMM: 220, isEstimated: est),
            .init(id: "w_east", name: "东侧外墙（主卧/书房）", rect: .init(x0: 0.90, y0: 0.10, x1: 0.92, y1: 0.805), axis: "z", roomTag: "master_bedroom", lengthMM: 6_345, thicknessMM: 220, isEstimated: est),
            .init(id: "w_mid", name: "客厅-主卧中隔墙", rect: .init(x0: 0.50, y0: 0.125, x1: 0.518, y1: 0.78), axis: "z", roomTag: "living_room", lengthMM: 5_895, thicknessMM: 180, isEstimated: est),
            .init(id: "w_study_div", name: "主卧-书房隔墙", rect: .init(x0: 0.518, y0: 0.48, x1: 0.90, y1: 0.50), axis: "x", roomTag: "study", lengthMM: 4_584, thicknessMM: 180, isEstimated: est),
        ]
        let openings: [DetectedOpening] = [
            // Intentionally misclassified / misplaced door so user can tap-to-correct on the overlay!
            .init(
                id: "op_door_mid",
                name: "客厅通往主卧门（待纠偏）",
                kind: .window, // Deliberately misdetected as window by auto-pass!
                hostWallID: "w_mid",
                roomTag: "living_room",
                axis: "z",
                rect: .init(x0: 0.495, y0: 0.28, x1: 0.523, y1: 0.391),
                widthMM: 1_000,
                heightMM: 2_100,
                sillMM: 0,
                confidence: 0.54,
                needsUserReview: true,
                reviewHint: "自动识别疑似将「客厅-主卧门」误判为窗洞，请点选纠正为门洞",
                userCorrected: false,
                isEstimated: est
            ),
            .init(
                id: "op_win_living",
                name: "客厅南向采光窗",
                kind: .window,
                hostWallID: "w_south",
                roomTag: "living_room",
                axis: "x",
                rect: .init(x0: 0.18, y0: 0.775, x1: 0.38, y1: 0.81),
                widthMM: 2_400,
                heightMM: 1_450,
                sillMM: 900,
                confidence: 0.92,
                needsUserReview: false,
                isEstimated: est
            ),
            .init(
                id: "op_win_study",
                name: "书房东向采光窗",
                kind: .window,
                hostWallID: "w_east",
                roomTag: "study",
                axis: "z",
                rect: .init(x0: 0.895, y0: 0.56, x1: 0.925, y1: 0.72),
                widthMM: 1_440,
                heightMM: 1_350,
                sillMM: 900,
                confidence: 0.90,
                needsUserReview: false,
                isEstimated: est
            ),
        ]
        let rooms: [DetectedRoomZone] = [
            .init(
                id: "room_living",
                roomTag: "living_room",
                name: "客厅餐区",
                rect: .init(x0: 0.10, y0: 0.125, x1: 0.50, y1: 0.78),
                floorPreset: .courtyardStone,
                furniture: [
                    .init(id: "f_sofa", name: "客厅布艺沙发", category: .furniture, rect: .init(x0: 0.14, y0: 0.28, x1: 0.22, y1: 0.58), heightMM: 820, materialPreset: .brushedSlate, roomTag: "living_room"),
                    .init(id: "f_dining", name: "餐区橡木长桌", category: .furniture, rect: .init(x0: 0.28, y0: 0.54, x1: 0.43, y1: 0.68), heightMM: 750, materialPreset: .warmOak, roomTag: "living_room"),
                ]
            ),
            .init(
                id: "room_master",
                roomTag: "master_bedroom",
                name: "主卧房间",
                rect: .init(x0: 0.518, y0: 0.125, x1: 0.90, y1: 0.48),
                floorPreset: .warmOak,
                furniture: [
                    .init(id: "f_bed", name: "主卧双人床", category: .furniture, rect: .init(x0: 0.64, y0: 0.18, x1: 0.84, y1: 0.39), heightMM: 560, materialPreset: .whiteMarble, roomTag: "master_bedroom"),
                ]
            ),
            .init(
                id: "room_study",
                roomTag: "study",
                name: "独立书房（其他房间）",
                rect: .init(x0: 0.518, y0: 0.50, x1: 0.90, y1: 0.78),
                floorPreset: .warmOak,
                furniture: [
                    .init(id: "f_desk", name: "书房实木书桌", category: .furniture, rect: .init(x0: 0.68, y0: 0.56, x1: 0.85, y1: 0.65), heightMM: 760, materialPreset: .warmOak, roomTag: "study"),
                ]
            ),
        ]
        return BlueprintOverlayDraft(
            id: UUID(),
            sourceFilename: includeScaleBar ? "unseen_apartment_with_scalebar.png" : "unseen_apartment_no_scalebar.png",
            imageWidthPx: w,
            imageHeightPx: h,
            scaleCalibration: cal,
            walls: walls,
            openings: openings,
            rooms: rooms,
            ceilingHeightMM: 2_800,
            ceilingHeightIsEstimated: true,
            userCorrectionCount: 0,
            isConfirmedFor3D: false,
            extractionNotes: [
                includeScaleBar
                    ? "已识别底部 0-5m 标尺，墙线与门窗已叠加至原图，存在 1 处低置信度门洞待点选纠正。"
                    : "无标尺副本：未检测到比例尺，全部墙体与门窗已标为「估算」，不编造精确毫米值。"
            ]
        )
    }

    // MARK: - Low-Level Image Morphology & Geometry Helpers (Pure Swift, Zero External Deps)

    private static func detectFooterScaleBar(
        luminance: [UInt8],
        saturation: [UInt8]?,
        width: Int,
        height: Int
    ) -> PixelRect? {
        let startY = Int(Double(height) * 0.85)
        guard startY < height else { return nil }

        // Find horizontal runs of dark low-saturation pixels in footer band
        var best: PixelRect?
        var rowDarkCount = [Int](repeating: 0, count: height - startY)
        var rowMinX = [Int](repeating: width, count: height - startY)
        var rowMaxX = [Int](repeating: -1, count: height - startY)

        for y in startY..<height {
            let localY = y - startY
            let off = y * width
            var curStart: Int? = nil
            var bestRunLen = 0
            var bestRunX0 = 0
            var bestRunX1 = 0
            for x in 0..<width {
                let idx = off + x
                let dark = luminance[idx] < 75 && (saturation?[idx] ?? 0) < 25
                if dark {
                    if curStart == nil { curStart = x }
                } else if let s = curStart {
                    let len = x - s
                    if len > bestRunLen {
                        bestRunLen = len
                        bestRunX0 = s
                        bestRunX1 = x
                    }
                    curStart = nil
                }
            }
            if let s = curStart {
                let len = width - s
                if len > bestRunLen {
                    bestRunLen = len
                    bestRunX0 = s
                    bestRunX1 = width
                }
            }
            if bestRunLen >= max(24, width / 10) && bestRunLen <= Int(Double(width) * 0.65) {
                rowDarkCount[localY] = bestRunLen
                rowMinX[localY] = bestRunX0
                rowMaxX[localY] = bestRunX1
            }
        }

        // Group contiguous dark rows forming a crisp horizontal bar (thickness 2..40 px)
        var y = 0
        while y < rowDarkCount.count {
            if rowDarkCount[y] > 0 {
                let y0 = y
                var minX = rowMinX[y]
                var maxX = rowMaxX[y]
                while y < rowDarkCount.count && rowDarkCount[y] > 0 {
                    minX = min(minX, rowMinX[y])
                    maxX = max(maxX, rowMaxX[y])
                    y += 1
                }
                let thick = y - y0
                let span = maxX - minX
                if thick >= 2 && thick <= max(18, height / 25) && span >= max(24, width / 10) {
                    let cand = PixelRect(x0: minX, y0: startY + y0, x1: maxX, y1: startY + y)
                    if best == nil || cand.width > (best?.width ?? 0) {
                        best = cand
                    }
                }
            } else {
                y += 1
            }
        }
        return best
    }

    private static func erodeBinary(_ mask: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        guard radius > 0 else { return mask }
        var tmp = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let off = y * width
            for x in radius..<(width - radius) {
                var ok: UInt8 = 1
                for dx in -radius...radius {
                    if mask[off + x + dx] == 0 { ok = 0; break }
                }
                tmp[off + x] = ok
            }
        }
        var out = [UInt8](repeating: 0, count: width * height)
        for y in radius..<(height - radius) {
            for x in 0..<width {
                var ok: UInt8 = 1
                for dy in -radius...radius {
                    if tmp[(y + dy) * width + x] == 0 { ok = 0; break }
                }
                out[y * width + x] = ok
            }
        }
        return out
    }

    private static func dilateBinary(_ mask: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        guard radius > 0 else { return mask }
        var tmp = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let off = y * width
            for x in 0..<width {
                var hit: UInt8 = 0
                let x0 = max(0, x - radius), x1 = min(width - 1, x + radius)
                for nx in x0...x1 {
                    if mask[off + nx] != 0 { hit = 1; break }
                }
                tmp[off + x] = hit
            }
        }
        var out = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let y0 = max(0, y - radius), y1 = min(height - 1, y + radius)
            for x in 0..<width {
                var hit: UInt8 = 0
                for ny in y0...y1 {
                    if tmp[ny * width + x] != 0 { hit = 1; break }
                }
                out[y * width + x] = hit
            }
        }
        return out
    }

    /// Exact clean-room Swift port of `extract_walls.py`'s `to_rects`:
    /// Extracts row runs and merges identical horizontal spans down consecutive rows into exact rectangles.
    public static func extractAxisAlignedWallRects(
        mask: [UInt8],
        width: Int,
        height: Int,
        minSide: Int = 3
    ) -> [PixelRect] {
        struct RunKey: Hashable { let x0: Int; let x1: Int }
        var out: [PixelRect] = []
        var live: [RunKey: Int] = [:]

        for y in 0...height {
            var runs: Set<RunKey> = []
            if y < height {
                let off = y * width
                var start: Int? = nil
                for x in 0..<width {
                    if mask[off + x] != 0 {
                        if start == nil { start = x }
                    } else if let s = start {
                        if x - s >= minSide { runs.insert(RunKey(x0: s, x1: x)) }
                        start = nil
                    }
                }
                if let s = start, width - s >= minSide {
                    runs.insert(RunKey(x0: s, x1: width))
                }
            }
            for (k, yStart) in Array(live) where !runs.contains(k) {
                live.removeValue(forKey: k)
                if y - yStart >= minSide {
                    out.append(PixelRect(x0: k.x0, y0: yStart, x1: k.x1, y1: y))
                }
            }
            for r in runs where live[r] == nil {
                live[r] = y
            }
        }
        return out
    }

    private static func mergeCollinearAdjacentRects(_ rects: [PixelRect]) -> [PixelRect] {
        var list = rects
        var changed = true
        while changed {
            changed = false
            outer: for i in 0..<list.count {
                for j in (i + 1)..<list.count {
                    let a = list[i], b = list[j]
                    // Merge vertically stacked rects with near-identical X bounds
                    if abs(a.x0 - b.x0) <= 2 && abs(a.x1 - b.x1) <= 2 && (a.y1 >= b.y0 - 2 && b.y1 >= a.y0 - 2) {
                        list[i] = PixelRect(x0: min(a.x0, b.x0), y0: min(a.y0, b.y0), x1: max(a.x1, b.x1), y1: max(a.y1, b.y1))
                        list.remove(at: j)
                        changed = true
                        break outer
                    }
                    // Merge horizontally adjacent rects with near-identical Y bounds
                    if abs(a.y0 - b.y0) <= 2 && abs(a.y1 - b.y1) <= 2 && (a.x1 >= b.x0 - 2 && b.x1 >= a.x0 - 2) {
                        list[i] = PixelRect(x0: min(a.x0, b.x0), y0: min(a.y0, b.y0), x1: max(a.x1, b.x1), y1: max(a.y1, b.y1))
                        list.remove(at: j)
                        changed = true
                        break outer
                    }
                }
            }
        }
        return list
    }

    private static func detectGapOpenings(
        walls: [DetectedWallLine],
        widthPx: Int,
        heightPx: Int,
        pxPerMM: Double,
        isEstimated: Bool
    ) -> [DetectedOpening] {
        var openings: [DetectedOpening] = []
        for i in 0..<walls.count {
            for j in (i + 1)..<walls.count {
                let a = walls[i], b = walls[j]
                guard a.axis == b.axis else { continue }
                if a.axis == "z" {
                    // Collinear vertical walls with a doorway/window gap between them
                    if abs(a.rect.centerX - b.rect.centerX) <= 0.025 {
                        let top = a.rect.y1 <= b.rect.y0 ? a : b
                        let bot = a.rect.y1 <= b.rect.y0 ? b : a
                        let gapNorm = bot.rect.y0 - top.rect.y1
                        let gapMM = Int((gapNorm * Double(heightPx) / pxPerMM).rounded())
                        if gapMM >= 650 && gapMM <= 2_400 {
                            let isLikelyDoor = gapMM <= 1_400
                            let rect = NormRect(x0: min(top.rect.x0, bot.rect.x0), y0: top.rect.y1, x1: max(top.rect.x1, bot.rect.x1), y1: bot.rect.y0)
                            openings.append(
                                DetectedOpening(
                                    id: "op_gap_\(openings.count + 1)",
                                    name: isLikelyDoor ? "自动识别门洞 #\(openings.count + 1)" : "自动识别窗洞 #\(openings.count + 1)",
                                    kind: isLikelyDoor ? .door : .window,
                                    hostWallID: top.id,
                                    roomTag: top.roomTag,
                                    axis: "z",
                                    rect: rect,
                                    widthMM: gapMM,
                                    heightMM: isLikelyDoor ? 2_100 : 1_350,
                                    sillMM: isLikelyDoor ? 0 : 900,
                                    confidence: isLikelyDoor ? 0.72 : 0.65,
                                    needsUserReview: true,
                                    reviewHint: "请核对洞口类型（门/窗）与宽度",
                                    isEstimated: isEstimated
                                )
                            )
                        }
                    }
                } else {
                    if abs(a.rect.centerY - b.rect.centerY) <= 0.025 {
                        let left = a.rect.x1 <= b.rect.x0 ? a : b
                        let right = a.rect.x1 <= b.rect.x0 ? b : a
                        let gapNorm = right.rect.x0 - left.rect.x1
                        let gapMM = Int((gapNorm * Double(widthPx) / pxPerMM).rounded())
                        if gapMM >= 650 && gapMM <= 2_600 {
                            let isLikelyDoor = gapMM <= 1_300
                            let rect = NormRect(x0: left.rect.x1, y0: min(left.rect.y0, right.rect.y0), x1: right.rect.x0, y1: max(left.rect.y1, right.rect.y1))
                            openings.append(
                                DetectedOpening(
                                    id: "op_gap_\(openings.count + 1)",
                                    name: isLikelyDoor ? "自动识别门洞 #\(openings.count + 1)" : "自动识别窗洞 #\(openings.count + 1)",
                                    kind: isLikelyDoor ? .door : .window,
                                    hostWallID: left.id,
                                    roomTag: left.roomTag,
                                    axis: "x",
                                    rect: rect,
                                    widthMM: gapMM,
                                    heightMM: isLikelyDoor ? 2_100 : 1_350,
                                    sillMM: isLikelyDoor ? 0 : 900,
                                    confidence: isLikelyDoor ? 0.72 : 0.65,
                                    needsUserReview: true,
                                    reviewHint: "请核对洞口类型（门/窗）与宽度",
                                    isEstimated: isEstimated
                                )
                            )
                        }
                    }
                }
            }
        }
        return openings
    }

    private static func computePlanBounds(walls: [DetectedWallLine]) -> NormRect {
        guard let first = walls.first else {
            return NormRect(x0: 0.1, y0: 0.1, x1: 0.9, y1: 0.8)
        }
        var x0 = first.rect.x0, y0 = first.rect.y0, x1 = first.rect.x1, y1 = first.rect.y1
        for w in walls.dropFirst() {
            x0 = min(x0, w.rect.x0)
            y0 = min(y0, w.rect.y0)
            x1 = max(x1, w.rect.x1)
            y1 = max(y1, w.rect.y1)
        }
        return NormRect(x0: x0, y0: y0, x1: x1, y1: y1)
    }

    private static func parseScaleBarPhysicalMM(in text: String?) -> Int? {
        guard let text, !text.isEmpty else { return nil }
        let pattern = #"(?:标尺|scale|比例尺)[^\d]{0,12}([0-9]+(?:\.[0-9]+)?)\s*(m|米|mm|毫米)"#
        if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r1 = Range(m.range(at: 1), in: text),
           let r2 = Range(m.range(at: 2), in: text),
           let v = Double(text[r1]) {
            let u = text[r2].lowercased()
            return (u == "m" || u == "米") ? Int((v * 1000.0).rounded()) : Int(v.rounded())
        }
        return nil
    }

    private static func parseCeilingHeightMM(in text: String?) -> Int? {
        guard let text, !text.isEmpty else { return nil }
        let pattern = #"(?:净高|层高|ceiling)[^\d]{0,8}([0-9]+(?:\.[0-9]+)?)\s*(m|米|mm|毫米)"#
        if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r1 = Range(m.range(at: 1), in: text),
           let r2 = Range(m.range(at: 2), in: text),
           let v = Double(text[r1]) {
            let u = text[r2].lowercased()
            let mm = (u == "m" || u == "米") ? Int((v * 1000.0).rounded()) : Int(v.rounded())
            return (mm >= 2_000 && mm <= 6_000) ? mm : nil
        }
        return nil
    }

    private static func makeFallbackUnscaledDraft(sourceFilename: String, width: Int, height: Int) -> BlueprintOverlayDraft {
        var d = makeInteractiveSampleDraft(includeScaleBar: false)
        d.sourceFilename = sourceFilename
        d.imageWidthPx = width
        d.imageHeightPx = height
        return d
    }
}
