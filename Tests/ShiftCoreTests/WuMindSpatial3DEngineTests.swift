import Foundation
import XCTest
@testable import ShiftCore

final class WuMindSpatial3DEngineTests: XCTestCase {

    // MARK: - Case 1: DeepSeek GIF-Level Imperial Palace Complex (Central Axis, Courtyards, Gate Towers, River, Weather, Single-Hall Edit, Undo, Round-Trip & GLB)

    func testCase1ImperialPalaceComplexStructureSingleHallEditUndoAndValidGLB() throws {
        var scene = WuMindSpatial3DEngine.synthesizeParametricScene(
            prompt: "从空白项目生成一座故宫风格可漫游宫殿建筑群，有南北贯通中轴、多进院落、太和殿主殿和东西配殿、午门与神武门城墙门楼、金水河水面和道路",
            preferredType: .imperialComplex,
            creationMode: .textDescription
        )

        XCTAssertTrue(scene.isConceptScene, "故宫样例必须明确标注为概念场景，不宣称实测复原")
        XCTAssertGreaterThanOrEqual(scene.nodes.count, 26, "故宫建筑群应包含多进院落、主殿、配殿、门楼、城墙、水系、御道与古树")
        XCTAssertTrue(scene.nodes.contains(where: { $0.category == .palaceHall && $0.name.contains("太和殿") }))
        XCTAssertTrue(scene.nodes.contains(where: { $0.category == .palaceHall && $0.name.contains("东配殿") }))
        XCTAssertTrue(scene.nodes.contains(where: { $0.category == .gateTower && $0.name.contains("午门") }))
        XCTAssertTrue(scene.nodes.contains(where: { $0.category == .cityWall }))
        XCTAssertTrue(scene.nodes.contains(where: { $0.category == .waterway && $0.detailProfile.hasBridgeArches }))
        XCTAssertTrue(scene.nodes.contains(where: { $0.category == .road }))
        XCTAssertEqual(scene.cameraPresets.map(\.title), ["全景俯瞰", "御道低空穿行", "门楼近景"])

        // Toggle sunny <-> snowy weather cleanly
        scene.weather = .snowy
        XCTAssertEqual(scene.weather, .snowy)

        // Surgical single-building edit on East Side Hall: change roof color + move east 2m, leaving ALL other buildings untouched
        let eastHall = try XCTUnwrap(scene.nodes.first(where: { $0.name.contains("东配殿") }))
        let mainHallBefore = try XCTUnwrap(scene.nodes.first(where: { $0.name.contains("太和殿主殿") }))
        let gateBefore = try XCTUnwrap(scene.nodes.first(where: { $0.name.contains("午门主城楼") }))

        let edit1 = WuMindSpatial3DEngine.applyNaturalLanguageEdit(
            scene: scene,
            nodeID: eastHall.id,
            instruction: "把屋顶改成翠绿琉璃瓦，向东移动 2 米，其他建筑不动"
        )
        scene = edit1.updatedScene
        let eastHallAfter = try XCTUnwrap(scene.nodes.first(where: { $0.id == eastHall.id }))
        XCTAssertEqual(eastHallAfter.material.roofPreset, .emeraldTile)
        XCTAssertEqual(eastHallAfter.positionMM.x, eastHall.positionMM.x + 2_000)
        XCTAssertEqual(scene.nodes.first(where: { $0.id == mainHallBefore.id }), mainHallBefore, "太和殿主殿必须保持原样")
        XCTAssertEqual(scene.nodes.first(where: { $0.id == gateBefore.id }), gateBefore, "午门城楼必须保持原样")

        // Export lossless project JSON & re-import
        let jsonData = try WuMindSpatial3DEngine.encodeProjectJSON(scene)
        let reopened = try WuMindSpatial3DEngine.decodeProjectJSON(jsonData)
        XCTAssertEqual(reopened.nodes.count, scene.nodes.count)
        XCTAssertEqual(reopened.nodes.first(where: { $0.id == eastHall.id })?.material.roofPreset, .emeraldTile)

        // Undo restores exact prior roof & position
        let undone = try XCTUnwrap(WuMindSpatial3DEngine.undo(scene: reopened))
        let eastHallUndone = try XCTUnwrap(undone.nodes.first(where: { $0.id == eastHall.id }))
        XCTAssertEqual(eastHallUndone.material.roofPreset, eastHall.material.roofPreset)
        XCTAssertEqual(eastHallUndone.positionMM.x, eastHall.positionMM.x)

        // Export multi-node GLB and validate every independent building exists as a named glTF node
        let glb = try WuMindSpatialGLBExporter.exportGLB(scene: scene)
        let report = try WuMindSpatialGLBExporter.validateGLB(glb)
        XCTAssertEqual(report.version, 2)
        XCTAssertEqual(report.nodeCount, scene.nodes.filter(\.isVisible).count)
        XCTAssertTrue(report.nodeNames.contains("太和殿主殿"))
        XCTAssertTrue(report.nodeNames.contains("东配殿 · 弘义阁"))
        XCTAssertTrue(report.nodeNames.contains("午门主城楼"))
    }

    // MARK: - Case 2: Uploaded Floor Plan Kitchen + Dining (+200mm Cabinet Sync & Missing Dimension Prompt)

    func testCase2UploadedKitchenInteriorCabinetPlus200mmSyncAndMissingDimensionAudit() throws {
        // Test A: drawing with explicit measured dimensions
        var kitchen = WuMindSpatial3DEngine.synthesizeParametricScene(
            prompt: "上传户型图生成厨房+餐区室内空间，北墙 5200mm，进深 4400mm，地柜宽 2400mm，净高 2800mm",
            preferredType: .interiorSpace,
            creationMode: .uploadAndText,
            referenceFilenames: ["kitchen_plan.pdf"]
        )
        XCTAssertFalse(kitchen.isConceptScene)
        XCTAssertTrue(kitchen.hasConfirmedMeasurements)

        let baseCab = try XCTUnwrap(kitchen.nodes.first(where: { $0.category == .cabinet && $0.name.contains("地柜") }))
        XCTAssertEqual(baseCab.sizeMM.x, 2_400)
        let islandBefore = try XCTUnwrap(kitchen.nodes.first(where: { $0.name.contains("中岛") }))

        // Change cabinet width by +200 mm -> 3D node AND linked dimension audit stay 100% synced!
        let outcome = WuMindSpatial3DEngine.applyNaturalLanguageEdit(
            scene: kitchen,
            nodeID: baseCab.id,
            instruction: "把主操作台地柜加宽 200 毫米，其他不动"
        )
        kitchen = outcome.updatedScene
        let baseCabAfter = try XCTUnwrap(kitchen.nodes.first(where: { $0.id == baseCab.id }))
        XCTAssertEqual(baseCabAfter.sizeMM.x, 2_600)
        let linkedAudit = try XCTUnwrap(kitchen.dimensionAuditItems.first(where: { $0.linkedNodeID == baseCab.id }))
        XCTAssertEqual(linkedAudit.valueMM, 2_600, "尺寸标注清单必须与 3D 柜宽实时一致")
        XCTAssertEqual(kitchen.nodes.first(where: { $0.id == islandBefore.id }), islandBefore)

        // Validate GLB export for interior scene
        let glb = try WuMindSpatialGLBExporter.exportGLB(scene: kitchen)
        let report = try WuMindSpatialGLBExporter.validateGLB(glb)
        XCTAssertTrue(report.nodeNames.contains("主操作台地柜"))

        // Test B: drawing missing ceiling height -> explicitly flags pendingConfirmation ("待确认")
        let missingDims = WuMindSpatial3DEngine.synthesizeParametricScene(
            prompt: "上传缺尺寸测试图（未标注净高）做厨房+餐区室内",
            preferredType: .interiorSpace,
            creationMode: .uploadReference,
            referenceFilenames: ["missing_height_test.png"]
        )
        XCTAssertGreaterThan(missingDims.pendingConfirmationCount, 0, "缺尺寸测试图必须明确标出待确认项提示补测")
    }

    // MARK: - Case 3: Heterogeneous Non-Palace Modern Waterfront Pavilion & Multi-Floor White Villa

    func testCase3ModernWaterfrontPavilionAndVillaProveNonSingleTemplateArchitecture() throws {
        // 3A. Modern Waterfront Pavilion (completely different structure from Palace!)
        var pavilion = WuMindSpatial3DEngine.synthesizeParametricScene(
            prompt: "做一个现代滨水艺术展馆，悬挑白色清水混凝土屋面，整面低反玻璃幕墙，亲水木栈道与中央圆形主展台",
            preferredType: .modernPavilion,
            creationMode: .uploadAndText,
            referenceFilenames: ["pavilion_sketch.png"]
        )
        XCTAssertFalse(pavilion.nodes.contains(where: { $0.category == .palaceHall }), "现代展馆不应混入故宫模板构件")
        let stage = try XCTUnwrap(pavilion.nodes.first(where: { $0.category == .exhibitStage && $0.detailProfile.isCylindrical }))
        let roof = try XCTUnwrap(pavilion.nodes.first(where: { $0.category == .roof }))

        let edited = WuMindSpatial3DEngine.applyNaturalLanguageEdit(
            scene: pavilion,
            nodeID: stage.id,
            instruction: "把中央圆形主展台向右移动 1.5 米并改为暖铜色，其他不动"
        )
        pavilion = edited.updatedScene
        let stageAfter = try XCTUnwrap(pavilion.nodes.first(where: { $0.id == stage.id }))
        XCTAssertEqual(stageAfter.positionMM.x, stage.positionMM.x + 1_500)
        XCTAssertEqual(stageAfter.material.preset, .warmCopper)
        XCTAssertEqual(pavilion.nodes.first(where: { $0.id == roof.id }), roof)

        // Save, reopen, and export validated multi-node GLB
        let reloaded = try WuMindSpatial3DEngine.decodeProjectJSON(try WuMindSpatial3DEngine.encodeProjectJSON(pavilion))
        XCTAssertEqual(reloaded.nodes.first(where: { $0.id == stage.id })?.positionMM.x, stage.positionMM.x + 1_500)
        let glb = try WuMindSpatialGLBExporter.exportGLB(scene: reloaded)
        let report = try WuMindSpatialGLBExporter.validateGLB(glb)
        XCTAssertEqual(report.nodeCount, reloaded.nodes.filter(\.isVisible).count)
        XCTAssertTrue(report.nodeNames.contains("中央圆形主展台"))

        // 3B. Two-story white villa with terrace & east main door
        var villa = WuMindSpatial3DEngine.synthesizeParametricScene(
            prompt: "做一栋两层白色别墅，有露台和内院，按草图正门改到东侧",
            preferredType: .villaBuilding,
            creationMode: .uploadAndText
        )
        XCTAssertTrue(villa.floorIndices.contains(1), "两层别墅必须支持楼层切换")
        XCTAssertTrue(villa.nodes.contains(where: { $0.category == .door && $0.name.contains("东侧") }))
        let terrace = try XCTUnwrap(villa.nodes.first(where: { $0.name.contains("二楼观景露台") }))
        let widen = WuMindSpatial3DEngine.applyNaturalLanguageEdit(
            scene: villa,
            nodeID: terrace.id,
            instruction: "只把二楼露台加宽一米，其他不动"
        )
        villa = widen.updatedScene
        XCTAssertEqual(villa.nodes.first(where: { $0.id == terrace.id })?.sizeMM.x, terrace.sizeMM.x + 1_000)
    }
}
