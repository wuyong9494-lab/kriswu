import Foundation
import XCTest
@testable import ShiftCore

final class WuMindSelfVerifyingAgentsTests: XCTestCase {

    // MARK: - 1. 3D Studio Parametric Modeling Acceptance: Kitchen Door +200mm Syncs Host Wall, Untouched Adjacent Room, Multi-View & GLB

    func testKitchenDoorPlus200mmSynchronizesHostWallOpeningWithoutTouchingAdjacentRoom() throws {
        let initial = WuMindSpatial3DEngine.synthesizeParametricScene(
            prompt: "上传户型图生成厨房+餐区室内空间，北墙 5200mm，进深 4400mm，地柜宽 2400mm，门宽 1200mm，净高 2800mm",
            preferredType: .interiorSpace,
            creationMode: .uploadAndText,
            referenceFilenames: ["kitchen_plan.pdf"]
        )

        let doorBefore = try XCTUnwrap(initial.nodes.first(where: { $0.wallOpeningRole == "opening_door" }))
        let northPierBefore = try XCTUnwrap(initial.nodes.first(where: { $0.wallOpeningRole == "pier_before" }))
        let southPierBefore = try XCTUnwrap(initial.nodes.first(where: { $0.wallOpeningRole == "pier_after" }))
        let lintelBefore = try XCTUnwrap(initial.nodes.first(where: { $0.wallOpeningRole == "lintel" }))
        let adjacentBefore = initial.nodes.filter { $0.roomTag == "adjacent_living_room" }
        let decorativeBefore = initial.nodes.filter { $0.modelingKind == "decorative_tripo" }
        let untouchedKitchenBefore = initial.nodes.filter {
            $0.roomTag != "adjacent_living_room" && $0.hostWallGroupID != doorBefore.hostWallGroupID
        }

        XCTAssertEqual(doorBefore.sizeMM.z, 1_200, "默认厨房移门净宽应为 1200mm")
        XCTAssertEqual(doorBefore.sizeMM.x, 120, "移门厚度应为 120mm")
        XCTAssertEqual(adjacentBefore.count, 3, "应包含隔壁客厅隔离房间构件用于零回归验收")
        XCTAssertEqual(decorativeBefore.count, 1, "装饰道具应显式标记为 decorative_tripo，与参数化建筑构件分离")

        let reportBefore = WuMindSpatial3DEngine.verifySceneGeometryAndMultiView(scene: initial)
        XCTAssertTrue(reportBefore.automatedModelCheckPassed, "初始厨房几何、多视角与 GLB 自校验必须通过：\(reportBefore.issues)")
        XCTAssertEqual(reportBefore.openingAudits.first?.openingWidthMM, 1_200)
        XCTAssertEqual(reportBefore.openingAudits.first?.isPerfectlySynced, true)
        XCTAssertGreaterThanOrEqual(reportBefore.checkedCameraViewIDs.count, 4)
        XCTAssertFalse(reportBefore.physicalDeviceTested, "离线自校验绝不能冒充真机实测通过")

        // Acceptance prompt: widen door by +200mm -> host wall piers & lintel synchronize, adjacent living room unchanged!
        let outcome = WuMindSpatial3DEngine.applyNaturalLanguageEdit(
            scene: initial,
            nodeID: doorBefore.id,
            instruction: "把餐区入户移门加宽 200 毫米，其他房间不动"
        )
        let after = outcome.updatedScene

        let doorAfter = try XCTUnwrap(after.nodes.first(where: { $0.id == doorBefore.id }))
        let northPierAfter = try XCTUnwrap(after.nodes.first(where: { $0.id == northPierBefore.id }))
        let southPierAfter = try XCTUnwrap(after.nodes.first(where: { $0.id == southPierBefore.id }))
        let lintelAfter = try XCTUnwrap(after.nodes.first(where: { $0.id == lintelBefore.id }))

        XCTAssertEqual(doorAfter.sizeMM.z, 1_400, "门净宽必须精确加宽 200mm（1200 -> 1400mm）")
        XCTAssertEqual(doorAfter.sizeMM.x, doorBefore.sizeMM.x, "门板厚度不应被误改为加宽轴")
        XCTAssertEqual(northPierAfter.sizeMM.z, northPierBefore.sizeMM.z - 100, "北段墙垛应同步收缩 100mm")
        XCTAssertEqual(southPierAfter.sizeMM.z, southPierBefore.sizeMM.z - 100, "南段墙垛应同步收缩 100mm")
        XCTAssertEqual(lintelAfter.sizeMM.z, 1_400, "门洞过梁跨度必须同步加宽至 1400mm")

        // Linked dimension audit updated to 1400mm
        let doorAudit = try XCTUnwrap(after.dimensionAuditItems.first(where: { $0.linkedNodeID == doorBefore.id }))
        XCTAssertEqual(doorAudit.valueMM, 1_400, "尺寸清单门宽必须与 3D 实时同步")

        // Adjacent living room & unrelated kitchen nodes MUST be 100% byte-identical!
        let adjacentAfter = after.nodes.filter { $0.roomTag == "adjacent_living_room" }
        XCTAssertEqual(adjacentAfter, adjacentBefore, "修改厨房门宽时隔壁客厅所有构件必须保持完全不变")
        let untouchedKitchenAfter = after.nodes.filter {
            $0.roomTag != "adjacent_living_room" && $0.hostWallGroupID != doorBefore.hostWallGroupID
        }
        XCTAssertEqual(untouchedKitchenAfter, untouchedKitchenBefore, "橱柜/中岛/餐桌/北墙/西墙/装饰道具必须保持原样")

        // Self-verify geometry (0mm gap/overlap), multi-view cameras, editable JSON round-trip & multi-node GLB
        let reportAfter = WuMindSpatial3DEngine.verifySceneGeometryAndMultiView(scene: after)
        XCTAssertTrue(reportAfter.automatedModelCheckPassed, "加宽门后几何与 GLB 自校验必须零误差通过：\(reportAfter.issues)")
        let openingAudit = try XCTUnwrap(reportAfter.openingAudits.first)
        XCTAssertEqual(openingAudit.openingWidthMM, 1_400)
        XCTAssertEqual(openingAudit.beforeEdgeGapMM, 0)
        XCTAssertEqual(openingAudit.afterEdgeGapMM, 0)
        XCTAssertEqual(openingAudit.lintelSpanErrorMM, 0)
        XCTAssertEqual(openingAudit.lintelElevationErrorMM, 0)
        XCTAssertTrue(reportAfter.glbValidated)
        XCTAssertTrue(reportAfter.projectRoundTripPassed)
        XCTAssertEqual(reportAfter.decorativeTripoNodeCount, 1)

        // Undo cleanly restores door (1200mm), host wall piers, lintel, and dimension audit
        let undone = try XCTUnwrap(WuMindSpatial3DEngine.undo(scene: after))
        XCTAssertEqual(undone.nodes.first(where: { $0.id == doorBefore.id })?.sizeMM.z, 1_200)
        XCTAssertEqual(undone.nodes.first(where: { $0.id == northPierBefore.id })?.sizeMM.z, northPierBefore.sizeMM.z)
        XCTAssertEqual(undone.nodes.first(where: { $0.id == lintelBefore.id })?.sizeMM.z, 1_200)
        XCTAssertEqual(undone.dimensionAuditItems.first(where: { $0.linkedNodeID == doorBefore.id })?.valueMM, 1_200)
    }

    // MARK: - 2. Mobile Game Studio 3-Piece Self-Verifying Deliverable + Separate Web/Native Badges + L1 Zero-Regression

    func testMobileGameThreePieceDeliverableSeparatesWebPreviewFromNativeAndProvesLevel1ZeroRegression() async throws {
        let level1 = WuMindMobileGameGraphWorkflow.RouteLevelSpec(
            levelNumber: 1,
            name: "晨间配送",
            startStation: "A",
            edges: ["A": ["B", "C"], "B": ["D"], "C": ["D"], "D": ["E"], "E": ["A"]],
            targetChain: ["D", "E"],
            hopBudget: 4
        )
        let level2Hard = WuMindMobileGameGraphWorkflow.RouteLevelSpec(
            levelNumber: 2,
            name: "晚高峰换乘",
            startStation: "A",
            edges: ["A": ["B"], "B": ["C", "D"], "C": ["E"], "D": ["E"], "E": ["F"], "F": ["B"]],
            targetChain: ["E", "F", "B"],
            hopBudget: 5
        )
        let level2Easier = WuMindMobileGameGraphWorkflow.RouteLevelSpec(
            levelNumber: 2,
            name: "晚高峰换乘（降难版）",
            startStation: "A",
            edges: ["A": ["B", "D"], "B": ["C", "D"], "C": ["E"], "D": ["E"], "E": ["F"], "F": ["B"]],
            targetChain: ["E", "F", "B"],
            hopBudget: 7
        )

        let baseGraph = WuMindMobileGameGraphWorkflow.makeGraph(title: "最后一跳", level1: level1, level2: level2Hard)
        let v1Graph = await WuMindMobileGameGraphWorkflow.execute(graph: baseGraph, level1: level1, level2: level2Hard)
        let v1Deliverable = WuMindMobileGameGraphWorkflow.buildSelfVerifyingDeliverable(
            title: "最后一跳",
            graph: v1Graph,
            level1: level1,
            level2: level2Hard,
            priorLevel1Hash: nil,
            nativePackagePassed: false,
            physicalDeviceTested: false
        )

        XCTAssertTrue(v1Deliverable.isCompleteThreePieceDeliverable)
        XCTAssertTrue(v1Deliverable.playablePreviewHTML.contains("<!DOCTYPE html>"))
        XCTAssertTrue(v1Deliverable.playablePreviewHTML.contains("restartLevel()"))
        XCTAssertTrue(v1Deliverable.editableSourceJSON.contains("晨间配送"))
        XCTAssertTrue(v1Deliverable.evidence.touchControlsVerified)
        XCTAssertTrue(v1Deliverable.evidence.winLoseConditionsVerified)
        XCTAssertTrue(v1Deliverable.evidence.restartVerified)
        XCTAssertEqual(v1Deliverable.evidence.level1SolvableMinHops, 3)
        XCTAssertEqual(v1Deliverable.evidence.level2SolvableMinHops, 5)
        // Strict separation: webPreviewPassed != nativePackagePassed != physicalDeviceTested
        XCTAssertTrue(v1Deliverable.evidence.webPreviewPassed)
        XCTAssertFalse(v1Deliverable.evidence.nativePackagePassed)
        XCTAssertFalse(v1Deliverable.evidence.physicalDeviceTested)
        XCTAssertTrue(v1Deliverable.evidence.separatedStatusBadges.contains("网页预览：通过"))
        XCTAssertTrue(v1Deliverable.evidence.separatedStatusBadges.contains("原生打包：未验证（与网页预览分开标示）"))

        let l1HashBefore = try XCTUnwrap(v1Graph.node(id: "level_1_build")?.outputHash)

        // Phase 2 surgical edit: "只把第二关变简单" -> Level 1 regression hash MUST stay identical and never re-run!
        let v2Graph = await WuMindMobileGameGraphWorkflow.reviseLevel2Only(
            existingGraph: v1Graph,
            level1: level1,
            easierLevel2: level2Easier,
            requireSlackAtLeast: 2
        )
        let v2Deliverable = WuMindMobileGameGraphWorkflow.buildSelfVerifyingDeliverable(
            title: "最后一跳",
            graph: v2Graph,
            level1: level1,
            level2: level2Easier,
            priorLevel1Hash: l1HashBefore,
            nativePackagePassed: false,
            physicalDeviceTested: false
        )

        XCTAssertTrue(v2Deliverable.isCompleteThreePieceDeliverable)
        XCTAssertTrue(v2Deliverable.evidence.level1RegressionUnchanged)
        XCTAssertEqual(v2Deliverable.evidence.level1RegressionHashBefore, l1HashBefore)
        XCTAssertEqual(v2Deliverable.evidence.level1RegressionHashAfter, l1HashBefore)
        XCTAssertEqual(v2Graph.node(id: "level_1_build")?.executionCount, 1, "只改第 2 关时第 1 关绝不能重跑")
        XCTAssertEqual(v2Graph.node(id: "level_2_build")?.executionCount, 2)
        XCTAssertEqual(v2Deliverable.evidence.level2SolvableMinHops, 4, "新增直连边后第 2 关最短路径应从 5 跳降至 4 跳（余量 +3）")
    }

    // MARK: - 3. Step-Aware Tiered Model Routing & Fable 5.2 Candidate Benchmark Gate

    func testStepAwareTieredModelRoutingAndFable52CandidateBenchmarkGate() {
        // 3A. Initial build & routine edits use economy model; complex planning uses strong model
        let initialBuild = WuMindModelRouter.routeByStep(step: .initialBuild, consecutiveTestFailures: 0)
        XCTAssertEqual(initialBuild.tier, .economy)
        XCTAssertEqual(initialBuild.selectedModel, "deepseek-chat")
        XCTAssertFalse(initialBuild.escalatedFromEconomy)

        let minorEdit = WuMindModelRouter.routeByStep(step: .minorEdit, consecutiveTestFailures: 1)
        XCTAssertEqual(minorEdit.tier, .economy)
        XCTAssertFalse(minorEdit.escalatedFromEconomy)

        let complexPlan = WuMindModelRouter.routeByStep(step: .complexArchitecturePlan)
        XCTAssertEqual(complexPlan.tier, .strong)
        XCTAssertEqual(complexPlan.selectedModel, "deepseek-reasoner")

        // 3B. Consecutive deterministic test failures (>= 2) automatically escalate from economy to strong model
        let escalatedRepair = WuMindModelRouter.routeByStep(step: .testFailureRepair, consecutiveTestFailures: 2)
        XCTAssertEqual(escalatedRepair.tier, .strong)
        XCTAssertEqual(escalatedRepair.selectedModel, "deepseek-reasoner")
        XCTAssertTrue(escalatedRepair.escalatedFromEconomy)

        // 3C. Intranet privacy boundary & user lock strictly override escalation
        let intranetLocked = WuMindModelRouter.routeByStep(step: .testFailureRepair, consecutiveTestFailures: 5, restrictToIntranet: true)
        XCTAssertEqual(intranetLocked.dataBoundary, .localIntranetOnly)
        XCTAssertEqual(intranetLocked.tier, .localDeterministic)

        let userLocked = WuMindModelRouter.routeByStep(step: .testFailureRepair, consecutiveTestFailures: 5, lockedModel: "qwen-max")
        XCTAssertEqual(userLocked.tier, .userLocked)
        XCTAssertEqual(userLocked.selectedModel, "qwen-max")

        // 3D. Fable 5.2 Candidate Benchmark Gate: NEVER promote without verified live provider probe!
        let incumbent = WuMindModelRouter.ModelBenchmarkMetrics(
            modelID: "deepseek-chat",
            totalTasks: 10,
            usableDeliverableCount: 8,
            avgLatencySeconds: 18.0,
            totalSpendYuan: 1.60 // ¥0.20 per usable artifact
        )
        let fableStrongNumbers = WuMindModelRouter.ModelBenchmarkMetrics(
            modelID: WuMindModelRouter.fable52CandidateModelID,
            totalTasks: 10,
            usableDeliverableCount: 9,
            avgLatencySeconds: 22.0,
            totalSpendYuan: 2.07 // ¥0.23 per usable artifact (within 1.25x & higher success rate)
        )

        let unprobed = WuMindModelRouter.evaluateCandidateForDefaultRouting(
            incumbent: incumbent,
            candidate: fableStrongNumbers,
            providerStatus: .unverifiedRequiresLiveProbe(reason: "当前中转 Key 尚未验证 claude-fable-5.2 路由连通")
        )
        XCTAssertEqual(unprobed.decision, .keepIncumbentPendingLiveProbe)
        XCTAssertEqual(unprobed.recommendedDefaultModel, "deepseek-chat")

        // Even when callable, if cost per usable artifact explodes (>1.25x), DO NOT promote
        let fableTooExpensive = WuMindModelRouter.ModelBenchmarkMetrics(
            modelID: WuMindModelRouter.fable52CandidateModelID,
            totalTasks: 10,
            usableDeliverableCount: 9,
            avgLatencySeconds: 31.0,
            totalSpendYuan: 5.40 // ¥0.60 per usable artifact (3x incumbent!)
        )
        let rejectedExpensive = WuMindModelRouter.evaluateCandidateForDefaultRouting(
            incumbent: incumbent,
            candidate: fableTooExpensive,
            providerStatus: .verifiedCallable(endpointLabel: "官方/中转实测通道", http200LatencyMS: 620)
        )
        XCTAssertEqual(rejectedExpensive.decision, .keepIncumbentBenchmarkNotBeaten)
        XCTAssertEqual(rejectedExpensive.recommendedDefaultModel, "deepseek-chat")

        // Only when BOTH live-verified AND beating incumbent on (successRate, latency, costPerUsableArtifact) -> promote!
        let promoted = WuMindModelRouter.evaluateCandidateForDefaultRouting(
            incumbent: incumbent,
            candidate: fableStrongNumbers,
            providerStatus: .verifiedCallable(endpointLabel: "官方/中转实测通道", http200LatencyMS: 540)
        )
        XCTAssertEqual(promoted.decision, .promoteCandidateAsDefault)
        XCTAssertEqual(promoted.recommendedDefaultModel, WuMindModelRouter.fable52CandidateModelID)
    }
}
