import Foundation
import XCTest
@testable import ShiftCore

final class WuMindBlueprintToSceneEngineTests: XCTestCase {

    /// Synthesizes a brand-new unseen 600x450 raster floorplan pixel buffer with crisp filled walls,
    /// an interior dividing wall containing a doorway gap, and an optional footer 0-5m scale bar (250px = 5000mm).
    private func rasterizeUnseenFloorplan(includeScaleBar: Bool) -> (lum: [UInt8], width: Int, height: Int) {
        let w = 600, h = 450
        var lum = [UInt8](repeating: 250, count: w * h)

        func fillRect(x0: Int, y0: Int, x1: Int, y1: Int, value: UInt8) {
            for y in max(0, y0)..<min(h, y1) {
                let off = y * w
                for x in max(0, x0)..<min(w, x1) {
                    lum[off + x] = value
                }
            }
        }

        // Outer apartment perimeter walls (dark architectural fill lum = 40, thickness = 10px -> 200mm at 0.05 px/mm)
        fillRect(x0: 60, y0: 45, x1: 540, y1: 55, value: 40)   // North outer wall (480px = 9600mm)
        fillRect(x0: 60, y0: 345, x1: 540, y1: 355, value: 40) // South outer wall
        fillRect(x0: 60, y0: 45, x1: 70, y1: 355, value: 40)   // West outer wall (310px = 6200mm)
        fillRect(x0: 530, y0: 45, x1: 540, y1: 355, value: 40) // East outer wall

        // Interior partition wall at x = 300..310 with an explicit 50px (1000mm) doorway gap at y = 160..210
        fillRect(x0: 300, y0: 55, x1: 310, y1: 160, value: 40)  // Partition north segment
        fillRect(x0: 300, y0: 210, x1: 310, y1: 345, value: 40) // Partition south segment

        // Thin 1px furniture outline inside living room (must be filtered out by morphological opening!)
        fillRect(x0: 110, y0: 120, x1: 180, y1: 121, value: 80)
        fillRect(x0: 110, y0: 190, x1: 180, y1: 191, value: 80)

        // Optional 0-5m footer scale bar: 250px wide at y = 405..413 -> exact 0.05 px/mm
        if includeScaleBar {
            fillRect(x0: 60, y0: 405, x1: 310, y1: 413, value: 20)
        }
        return (lum, w, h)
    }

    // MARK: - 1. Unseen Floorplan WITH Scale Bar vs Stripped Scale Bar Copy (Zero Fabricated Precision!)

    func testUnseenFloorplanWithScaleBarDetectsCalibrationAndWallsWhileStrippedCopyMarksEverythingEstimated() throws {
        // A. Unseen floorplan WITH 0-5m scale bar (250px = 5000mm -> 0.05 px/mm)
        let withBar = rasterizeUnseenFloorplan(includeScaleBar: true)
        let draftScaled = WuMindBlueprintToSceneEngine.analyzeFloorplanPixels(
            luminance: withBar.lum,
            width: withBar.width,
            height: withBar.height,
            sourceFilename: "unseen_flat_with_scalebar.png",
            extractedOCRText: "比例尺 标尺 5m"
        )

        XCTAssertTrue(draftScaled.scaleCalibration.isMeasured, "带标尺户型图必须真实检出底部标尺")
        XCTAssertNotNil(draftScaled.scaleCalibration.scaleBarOverlayRect, "叠加层必须提供标尺位置框")
        XCTAssertEqual(draftScaled.scaleCalibration.effectivePxPerMM, 0.05, accuracy: 0.002, "250px/5000mm 标尺换算必须精确")
        XCTAssertGreaterThanOrEqual(draftScaled.walls.count, 4, "形态学开运算与行游程合并必须提取出独立墙段")
        XCTAssertTrue(draftScaled.walls.allSatisfy { !$0.isEstimated })
        XCTAssertTrue(draftScaled.openings.contains(where: { $0.axis == "z" }), "中隔墙 50px 门洞缺口必须被检出并展示在叠加层")
        XCTAssertTrue(draftScaled.ceilingHeightIsEstimated, "2D 平面图未标净高时，净高仍必须诚实标为估算")

        // B. EXACT SAME floorplan with footer scale bar stripped -> MUST NOT fabricate exact millimeters!
        let withoutBar = rasterizeUnseenFloorplan(includeScaleBar: false)
        let draftUnscaled = WuMindBlueprintToSceneEngine.analyzeFloorplanPixels(
            luminance: withoutBar.lum,
            width: withoutBar.width,
            height: withoutBar.height,
            sourceFilename: "unseen_flat_no_scalebar.png",
            extractedOCRText: nil
        )

        XCTAssertFalse(draftUnscaled.scaleCalibration.isMeasured, "去掉标尺的副本绝不能假装已校准精确尺寸")
        XCTAssertNil(draftUnscaled.scaleCalibration.scaleBarOverlayRect)
        XCTAssertTrue(draftUnscaled.walls.allSatisfy(\.isEstimated), "无标尺副本的每一段墙体都必须标为估算")
        XCTAssertTrue(draftUnscaled.openings.allSatisfy(\.isEstimated), "无标尺副本的每一处门窗都必须标为估算")

        let sceneUnscaled = WuMindBlueprintToSceneEngine.compileToEditableScene(draft: draftUnscaled)
        XCTAssertTrue(sceneUnscaled.isConceptScene, "无标尺副本生成的场景必须明确标为估算/概念场景")
        XCTAssertTrue(sceneUnscaled.disclaimerBanner.contains("无标尺") && sceneUnscaled.disclaimerBanner.contains("估算"))
        XCTAssertFalse(sceneUnscaled.hasConfirmedMeasurements, "无标尺副本绝不能包含 confirmedMeasured 节点")
    }

    // MARK: - 2. Full Acceptance Walkthrough: Tap-Correct Misdetected Door -> Generate Shared Scene Format -> Walk Inside -> Widen Door +200mm (Wall & Doorframe Sync, Other Rooms Unchanged) -> Save/Reopen -> GLB

    func testTapCorrectDoorCompileEditableSceneWiden200mmSyncsWallAndDoorframeWithoutTouchingOtherRooms() throws {
        var draft = WuMindBlueprintToSceneEngine.makeInteractiveSampleDraft(includeScaleBar: true)
        XCTAssertTrue(draft.scaleCalibration.isMeasured)
        XCTAssertEqual(draft.pendingReviewCount, 1, "初始识别应标记 1 处误判门洞待用户点选纠正")

        // Step 1: User taps the misdetected opening on the overlay and corrects window -> door
        let misdetected = try XCTUnwrap(draft.openings.first(where: { $0.id == "op_door_mid" }))
        XCTAssertEqual(misdetected.kind, .window)
        let corrected = WuMindBlueprintToSceneEngine.correctOpening(
            draft: &draft,
            openingID: misdetected.id,
            newKind: .door,
            newName: "客厅-主卧入户门",
            newWidthMM: 1_000
        )
        XCTAssertTrue(corrected)
        XCTAssertEqual(draft.pendingReviewCount, 0)
        XCTAssertEqual(draft.userCorrectionCount, 1)

        // Step 2: Confirm overlay -> compile into EXACT SAME `WuMindSpatialSceneDocument` format used by text modeling
        var scene = WuMindBlueprintToSceneEngine.compileToEditableScene(draft: draft)
        XCTAssertFalse(scene.isConceptScene)
        XCTAssertTrue(scene.cameraPresets.contains(where: { $0.id == "walk_inside_living" }), "必须生成可走进房间的室内漫游镜头")
        XCTAssertTrue(scene.cameraPresets.contains(where: { $0.id == "walk_inside_master" }))

        let doorBefore = try XCTUnwrap(scene.nodes.first(where: { $0.wallOpeningRole == "opening_door" }))
        let groupID = try XCTUnwrap(doorBefore.hostWallGroupID)
        let pierBefore0 = try XCTUnwrap(scene.nodes.first(where: { $0.hostWallGroupID == groupID && $0.wallOpeningRole == "pier_before" }))
        let pierAfter0 = try XCTUnwrap(scene.nodes.first(where: { $0.hostWallGroupID == groupID && $0.wallOpeningRole == "pier_after" }))
        let lintel0 = try XCTUnwrap(scene.nodes.first(where: { $0.hostWallGroupID == groupID && $0.wallOpeningRole == "lintel" }))
        let frameBefore0 = try XCTUnwrap(scene.nodes.first(where: { $0.hostWallGroupID == groupID && $0.wallOpeningRole == "doorframe_before" }))
        let frameAfter0 = try XCTUnwrap(scene.nodes.first(where: { $0.hostWallGroupID == groupID && $0.wallOpeningRole == "doorframe_after" }))
        let frameHead0 = try XCTUnwrap(scene.nodes.first(where: { $0.hostWallGroupID == groupID && $0.wallOpeningRole == "doorframe_head" }))

        // Snapshot OTHER room ("study") completely before editing the door
        let studyNodesBefore = scene.nodes.filter { $0.roomTag == "study" }
        XCTAssertGreaterThanOrEqual(studyNodesBefore.count, 3, "必须包含独立的书房构件用于零回归证明")

        XCTAssertEqual(doorBefore.sizeMM.z, 1_000)
        XCTAssertEqual(frameHead0.sizeMM.z, 1_000)
        let auditBefore = WuMindSpatial3DEngine.verifySceneGeometryAndMultiView(scene: scene)
        XCTAssertTrue(auditBefore.automatedModelCheckPassed, "初始编译几何与门框自检必须通过：\(auditBefore.issues)")

        // Step 3: Widen door opening by +200mm -> wall piers, lintel AND all 3 doorframe parts synchronize with 0mm error!
        let widen = WuMindSpatial3DEngine.applyNaturalLanguageEdit(
            scene: scene,
            nodeID: doorBefore.id,
            instruction: "把门洞加宽 200 毫米，其他房间不动"
        )
        scene = widen.updatedScene

        let doorAfter = try XCTUnwrap(scene.nodes.first(where: { $0.id == doorBefore.id }))
        let pierBefore1 = try XCTUnwrap(scene.nodes.first(where: { $0.id == pierBefore0.id }))
        let pierAfter1 = try XCTUnwrap(scene.nodes.first(where: { $0.id == pierAfter0.id }))
        let lintel1 = try XCTUnwrap(scene.nodes.first(where: { $0.id == lintel0.id }))
        let frameBefore1 = try XCTUnwrap(scene.nodes.first(where: { $0.id == frameBefore0.id }))
        let frameAfter1 = try XCTUnwrap(scene.nodes.first(where: { $0.id == frameAfter0.id }))
        let frameHead1 = try XCTUnwrap(scene.nodes.first(where: { $0.id == frameHead0.id }))

        XCTAssertEqual(doorAfter.sizeMM.z, 1_200, "门洞净宽应精确加宽 +200mm (1000 -> 1200mm)")
        XCTAssertEqual(pierBefore1.sizeMM.z, pierBefore0.sizeMM.z - 100, "前段墙垛应同步收缩 100mm")
        XCTAssertEqual(pierAfter1.sizeMM.z, pierAfter0.sizeMM.z - 100, "后段墙垛应同步收缩 100mm")
        XCTAssertEqual(lintel1.sizeMM.z, 1_200, "过梁跨度应同步加宽至 1200mm")
        XCTAssertEqual(frameBefore1.positionMM.z, frameBefore0.positionMM.z - 100, "门框前梃应随门洞同步外移 100mm")
        XCTAssertEqual(frameAfter1.positionMM.z, frameAfter0.positionMM.z + 100, "门框后梃应随门洞同步外移 100mm")
        XCTAssertEqual(frameHead1.sizeMM.z, 1_200, "门框上梃应同步加宽至 1200mm")

        // Other room ("study") MUST remain 100% byte-identical!
        let studyNodesAfter = scene.nodes.filter { $0.roomTag == "study" }
        XCTAssertEqual(studyNodesAfter, studyNodesBefore, "加宽客厅-主卧门洞时，书房所有构件必须保持完全不变")

        let auditAfter = WuMindSpatial3DEngine.verifySceneGeometryAndMultiView(scene: scene)
        XCTAssertTrue(auditAfter.automatedModelCheckPassed, "加宽 200mm 后墙洞与门框误差必须全为 0mm：\(auditAfter.issues)")
        let openAudit = try XCTUnwrap(auditAfter.openingAudits.first)
        XCTAssertEqual(openAudit.beforeEdgeGapMM, 0)
        XCTAssertEqual(openAudit.afterEdgeGapMM, 0)
        XCTAssertEqual(openAudit.lintelSpanErrorMM, 0)
        XCTAssertEqual(openAudit.doorframeErrorMM, 0)

        // Step 4: Save project JSON, reopen, continue editing (+100mm), and export valid multi-node GLB v2!
        let projectJSON = try WuMindSpatial3DEngine.encodeProjectJSON(scene)
        let reopened = try WuMindSpatial3DEngine.decodeProjectJSON(projectJSON)
        XCTAssertEqual(reopened.nodes, scene.nodes)

        let secondEdit = WuMindSpatial3DEngine.applyNaturalLanguageEdit(
            scene: reopened,
            nodeID: doorBefore.id,
            instruction: "把门洞加宽 100 毫米"
        )
        XCTAssertEqual(secondEdit.updatedScene.nodes.first(where: { $0.id == doorBefore.id })?.sizeMM.z, 1_300)
        XCTAssertEqual(secondEdit.updatedScene.nodes.filter { $0.roomTag == "study" }, studyNodesBefore)
        let auditReopened = WuMindSpatial3DEngine.verifySceneGeometryAndMultiView(scene: secondEdit.updatedScene)
        XCTAssertTrue(auditReopened.automatedModelCheckPassed)
        XCTAssertTrue(auditReopened.glbValidated)
        XCTAssertEqual(auditReopened.glbNodeCount, secondEdit.updatedScene.nodes.filter(\.isVisible).count)
    }
}
