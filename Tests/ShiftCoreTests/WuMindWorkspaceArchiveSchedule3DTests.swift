import Foundation
import XCTest
@testable import ShiftCore

final class WuMindWorkspaceArchiveSchedule3DTests: XCTestCase {

    // MARK: - Workstream 2: Conversation Archive & Cross-Device Merge Policy

    func testArchiveAndUnarchivePreserveTimestampsTurnCountAttachmentsAndSortOrder() {
        let base = Date(timeIntervalSince1970: 1_795_000_000)
        let idOld = UUID()
        let idMid = UUID()
        let idNew = UUID()

        let convOld = WuMindConversationArchiveState(
            id: idOld,
            title: "季度复盘",
            searchableText: "Q3 预算与现金流分析",
            createdAt: base.addingTimeInterval(-7_200),
            updatedAt: base.addingTimeInterval(-3_600),
            turnCount: 6,
            attachmentCount: 2
        )
        let convMid = WuMindConversationArchiveState(
            id: idMid,
            title: "赤河镇 3D 方案",
            searchableText: "河流 桥梁 火车站 酒馆",
            createdAt: base.addingTimeInterval(-3_000),
            updatedAt: base.addingTimeInterval(-1_800),
            turnCount: 10,
            attachmentCount: 3
        )
        let convNew = WuMindConversationArchiveState(
            id: idNew,
            title: "今日值班计划",
            searchableText: "测控站交接清单",
            createdAt: base.addingTimeInterval(-600),
            updatedAt: base,
            turnCount: 4,
            attachmentCount: 1
        )

        // Archive middle thread -> preserves createdAt, updatedAt, turnCount, attachmentCount!
        let archiveTime = base.addingTimeInterval(120)
        let archivedMid = WuMindConversationArchivePolicy.archive(convMid, at: archiveTime)
        XCTAssertTrue(archivedMid.isArchived)
        XCTAssertEqual(archivedMid.archivedAt, archiveTime)
        XCTAssertEqual(archivedMid.archiveStateUpdatedAt, archiveTime)
        XCTAssertEqual(archivedMid.createdAt, convMid.createdAt)
        XCTAssertEqual(archivedMid.updatedAt, convMid.updatedAt)
        XCTAssertEqual(archivedMid.turnCount, 10)
        XCTAssertEqual(archivedMid.attachmentCount, 3)

        let pool = [convOld, archivedMid, convNew]

        // Active list excludes archived; Archived list contains ONLY archived
        XCTAssertEqual(WuMindConversationArchivePolicy.sortActive(pool).map(\.id), [idNew, idOld])
        XCTAssertEqual(WuMindConversationArchivePolicy.sortArchived(pool).map(\.id), [idMid])

        // Default search excludes archived; toggling includeArchived reveals it
        let defaultSearch = WuMindConversationArchivePolicy.filter(pool, query: "赤河镇", includeArchived: false)
        XCTAssertTrue(defaultSearch.isEmpty, "默认搜索不得包含已归档对话")
        let expandedSearch = WuMindConversationArchivePolicy.filter(pool, query: "赤河镇", includeArchived: true)
        XCTAssertEqual(expandedSearch.map(\.id), [idMid], "开启「包含已归档」后必须能检索到归档对话")

        // Unarchive restores exact original sort position between idNew and idOld with zero timestamp mutation
        let unarchivedMid = WuMindConversationArchivePolicy.unarchive(archivedMid, at: archiveTime.addingTimeInterval(60))
        XCTAssertFalse(unarchivedMid.isArchived)
        XCTAssertNil(unarchivedMid.archivedAt)
        XCTAssertEqual(unarchivedMid.updatedAt, convMid.updatedAt)
        XCTAssertEqual(unarchivedMid.turnCount, 10)
        XCTAssertEqual(unarchivedMid.attachmentCount, 3)

        let restoredOrder = WuMindConversationArchivePolicy.sortActive([convOld, unarchivedMid, convNew])
        XCTAssertEqual(restoredOrder.map(\.id), [idNew, idMid, idOld], "取消归档后必须按原时间顺序回到主列表，不重复")
    }

    func testCrossDeviceArchiveMergeResolvesByArchiveStateClock() {
        let t0 = Date(timeIntervalSince1970: 1_795_000_000)
        let t1 = t0.addingTimeInterval(300)
        let t2 = t0.addingTimeInterval(600)

        // Device B archived at t1, Device A still had stale unarchived payload from t0 -> archived wins!
        let r1 = WuMindConversationArchivePolicy.resolveMerge(
            localUpdatedAt: t0,
            localTurnCount: 4,
            localIsArchived: false,
            localArchivedAt: nil,
            localArchiveStateUpdatedAt: nil,
            incomingUpdatedAt: t0,
            incomingTurnCount: 4,
            incomingIsArchived: true,
            incomingArchivedAt: t1,
            incomingArchiveStateUpdatedAt: t1
        )
        XCTAssertTrue(r1.isArchived)
        XCTAssertEqual(r1.archivedAt, t1)

        // Later Device A explicitly unarchives at t2 while syncing older archived snapshot from t1 -> unarchived wins!
        let r2 = WuMindConversationArchivePolicy.resolveMerge(
            localUpdatedAt: t0,
            localTurnCount: 4,
            localIsArchived: false,
            localArchivedAt: nil,
            localArchiveStateUpdatedAt: t2,
            incomingUpdatedAt: t1,
            incomingTurnCount: 6,
            incomingIsArchived: true,
            incomingArchivedAt: t1,
            incomingArchiveStateUpdatedAt: t1
        )
        XCTAssertTrue(r2.preferIncomingContent, "应保留更新的对话消息内容")
        XCTAssertFalse(r2.isArchived, "较新的取消归档状态（t2）不得被旧归档快照（t1）覆盖")
        XCTAssertNil(r2.archivedAt)
    }

    // MARK: - Workstream 3: Scheduled Tasks Honesty, Beijing Timezone & Legacy Decode

    func testScheduledTaskStatusNeverClaimsScheduledBeforeServerAckAndOwnAPIWarnsHonestly() throws {
        let future = Date().addingTimeInterval(3_600)

        // 1. Managed task NOT yet confirmed by server MUST NOT display "已安排"
        let unconfirmed = WuMindScheduledTask(
            title: "每日简报",
            prompt: "汇总行业动态",
            channelRaw: "managed",
            cadence: .daily(hour: 9, minute: 0),
            serverConfirmed: false,
            serverStatus: "pending_sync"
        )
        XCTAssertFalse(unconfirmed.supportsLockScreenCloudExecution)
        XCTAssertFalse(unconfirmed.statusBadgeTitle.contains("已安排"), "未拿到服务端确认回执前不得宣称「已安排」")

        // 2. Managed task with server ACK displays "已安排 · 云端锁屏可执行"
        let confirmed = WuMindScheduledTask(
            title: "单次提醒",
            prompt: "整理下午议程",
            channelRaw: "managed",
            cadence: .once(future),
            cloudSynced: true,
            serverConfirmed: true,
            serverStatus: "active"
        )
        XCTAssertTrue(confirmed.supportsLockScreenCloudExecution)
        XCTAssertTrue(confirmed.statusBadgeTitle.contains("已安排"))

        // 3. Completed one-time task clearly marks termination
        let completedOnce = WuMindScheduledTask(
            title: "单次任务",
            prompt: "一次性执行",
            channelRaw: "managed",
            cadence: .once(future),
            enabled: false,
            cloudSynced: true,
            serverConfirmed: true,
            serverStatus: "completed"
        )
        XCTAssertFalse(completedOnce.supportsLockScreenCloudExecution)
        XCTAssertTrue(completedOnce.statusBadgeTitle.contains("已完成"))
        XCTAssertEqual(completedOnce.displayNextRunBeijingText, "单次任务已执行完毕")

        // 4. Own API Key explicitly reports lock-screen unsupported (never silently switches to managed)
        let ownAPI = WuMindScheduledTask(
            title: "自有 Key 定时",
            prompt: "本机提醒",
            channelRaw: "ownAPI",
            cadence: .daily(hour: 8, minute: 30)
        )
        XCTAssertFalse(ownAPI.isManagedCloudTask)
        XCTAssertFalse(ownAPI.supportsLockScreenCloudExecution)
        XCTAssertTrue(ownAPI.statusBadgeTitle.contains("自有 Key 不支持锁屏云端执行"))

        // 5. Legacy JSON payload without new fields decodes cleanly
        let legacyJSON = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "title": "旧版任务",
          "prompt": "测试兼容",
          "modelID": "deepseek-reasoner",
          "channelRaw": "managed",
          "useAgentMode": true,
          "cadence": { "daily": { "hour": 8, "minute": 30 } },
          "enabled": true,
          "cloudSynced": true
        }
        """
        let decoded = try JSONDecoder().decode(WuMindScheduledTask.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.executionMode, .aiRun)
        XCTAssertEqual(decoded.timezoneID, "Asia/Shanghai")
        XCTAssertTrue(decoded.serverConfirmed)
        XCTAssertEqual(decoded.serverStatus, "active")
        XCTAssertTrue(decoded.runs.isEmpty)
    }

    func testScheduleCadenceBeijingTimeFormattingAndWeeklyCalculation() {
        let cal = WuMindScheduleCadence.beijingCalendar
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 15, minute: 0))! // Thu
        let formatted = WuMindScheduleCadence.formatBeijingDate(now)
        XCTAssertEqual(formatted, "2026-11-26 15:00 (北京时间)")

        let weekly = WuMindScheduleCadence.weekly(weekday: 2, hour: 9, minute: 15) // Monday 09:15 Beijing
        let next = weekly.nextRunDate(after: now, calendar: cal)
        XCTAssertNotNil(next)
        let comps = cal.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: next!)
        XCTAssertEqual(comps.weekday, 2)
        XCTAssertEqual(comps.hour, 9)
        XCTAssertEqual(comps.minute, 15)
        XCTAssertEqual(comps.day, 30)
    }

    // MARK: - Workstream 4: 3D Tech Library, Western Town Anti-Palace Fix, Walkability, Godot .tscn & CAD Plate

    func test3DTechRegistryCoversAll5CategoriesAndSeparatesStatusesStrictly() {
        XCTAssertEqual(WuMind3DTechCategory.allCases.count, 5)
        for category in WuMind3DTechCategory.allCases {
            let items = WuMind3DTechRegistry.entries(for: category)
            XCTAssertFalse(items.isEmpty, "分类 \(category.displayName) 不能为空")
        }
        XCTAssertGreaterThanOrEqual(WuMind3DTechRegistry.entries.count, 15)

        // All 3 maturity statuses must exist and never be conflated
        XCTAssertGreaterThan(WuMind3DTechRegistry.count(with: .researchCandidate), 0)
        XCTAssertGreaterThan(WuMind3DTechRegistry.count(with: .sampleVerified), 0)
        XCTAssertGreaterThan(WuMind3DTechRegistry.count(with: .integratedAccepted), 0)

        // Every entry must have official URL, version, dual license fields, and 2026 verification date
        for entry in WuMind3DTechRegistry.entries {
            XCTAssertTrue(entry.officialURL.hasPrefix("https://"), "\(entry.id) 必须填写官方 HTTPS 链接")
            XCTAssertFalse(entry.pinnedVersion.isEmpty)
            XCTAssertFalse(entry.codeLicense.isEmpty)
            XCTAssertFalse(entry.weightsOrAssetLicense.isEmpty)
            XCTAssertEqual(entry.lastVerifiedDate, "2026-11-26")
        }

        // Single-image-to-3D GPU tools MUST stay Research Candidate (not falsely marked Integrated!)
        let trellis = WuMind3DTechRegistry.entries.first { $0.id == "asset.trellis2" }
        XCTAssertEqual(trellis?.status, .researchCandidate)

        // Mixamo MUST forbid redistribution!
        let mixamo = WuMind3DTechRegistry.entries.first { $0.id == "char.mixamo" }
        XCTAssertEqual(mixamo?.redistributionAllowed, false)
        XCTAssertEqual(mixamo?.status, .researchCandidate)
    }

    func testWesternTownPromptNeverFallsBackToForbiddenCityEvenWhenPreferredTypeIsImperialComplex() throws {
        let prompt = "生成一个叫赤河镇的西部小镇，有河流、木桥、火车站、西部酒馆，主街可以从酒馆过桥走到火车站"
        let scene = WuMindSpatial3DEngine.synthesizeParametricScene(
            prompt: prompt,
            preferredType: .imperialComplex, // Intentionally hostile preferredType to prove regression fix!
            creationMode: .textDescription
        )

        XCTAssertEqual(scene.sceneType, .gameScene, "西部小镇描述绝不能落回故宫（.imperialComplex）")
        XCTAssertFalse(scene.nodes.contains(where: { $0.category == .palaceHall || $0.name.contains("太和殿") || $0.name.contains("午门") }),
                       "西部小镇绝不能出现任何故宫构件")

        // Verify all 4 independent editable landmarks exist
        XCTAssertTrue(scene.nodes.contains(where: { $0.category == .waterway && $0.name.contains("赤河") }))
        XCTAssertTrue(scene.nodes.contains(where: { $0.category == .road && $0.name.contains("桥") }))
        XCTAssertTrue(scene.nodes.contains(where: { $0.name.contains("火车站") }))
        XCTAssertTrue(scene.nodes.contains(where: { $0.name.contains("酒馆") }))

        // Verify real geometric walkability passes from Saloon across Bridge to Train Station
        let walkReport = WuMindSpatial3DEngine.verifyWalkableRoute(scene: scene)
        XCTAssertTrue(walkReport.isWalkable, "赤河镇主街过桥必须可连续行走: \(walkReport.summary)")
        XCTAssertEqual(walkReport.blockedPoints, 0)
        XCTAssertEqual(walkReport.supportedPoints, walkReport.sampledPoints)

        // Negative control: moving Saloon onto Main Street (Z = 0) MUST fail walkability with exact blocker name!
        var obstructed = scene
        if let idx = obstructed.nodes.firstIndex(where: { $0.name.contains("酒馆（Saloon）") }) {
            obstructed.nodes[idx].positionMM.z = 0
        }
        let obstructedReport = WuMindSpatial3DEngine.verifyWalkableRoute(scene: obstructed)
        XCTAssertFalse(obstructedReport.isWalkable, "建筑挡在主街上时碰撞检测必须报阻挡")
        XCTAssertGreaterThan(obstructedReport.blockedPoints, 0)
        XCTAssertTrue(obstructedReport.blockingNodeNames.contains(where: { $0.contains("酒馆") }))

        // Export GLB + Godot 4 .tscn and validate both
        let glb = try WuMindSpatialGLBExporter.exportGLB(scene: scene)
        let glbReport = try WuMindSpatialGLBExporter.validateGLB(glb)
        XCTAssertEqual(glbReport.version, 2)
        XCTAssertTrue(glbReport.nodeNames.contains("赤河火车站主站房"))
        XCTAssertTrue(glbReport.nodeNames.contains("赤河西部酒馆（Saloon）"))

        let tscn = WuMindSpatial3DEngine.exportGodotSceneTSCN(scene: scene, glbFilename: "red_river_town.glb")
        XCTAssertTrue(tscn.contains("[gd_scene"))
        XCTAssertTrue(tscn.contains("res://red_river_town.glb"))
        XCTAssertTrue(tscn.contains("StaticBody3D"))
        XCTAssertTrue(tscn.contains("BoxShape3D_1"))
    }

    func testCADMountingPlateRoutesCorrectlyAndRegeneratesHolePitch() {
        let v1 = WuMindSpatial3DEngine.buildCADMountingPlate(holePitchXMM: 120, holePitchYMM: 80)
        let v2 = WuMindSpatial3DEngine.buildCADMountingPlate(holePitchXMM: 130, holePitchYMM: 90)

        let holesV1 = v1.nodes.filter { $0.name.contains("安装孔") }
        let holesV2 = v2.nodes.filter { $0.name.contains("安装孔") }
        XCTAssertEqual(holesV1.count, 4)
        XCTAssertEqual(holesV2.count, 4)
        XCTAssertTrue(holesV1.allSatisfy { abs($0.positionMM.x) == 600 && abs($0.positionMM.z) == 400 })
        XCTAssertTrue(holesV2.allSatisfy { abs($0.positionMM.x) == 650 && abs($0.positionMM.z) == 450 })

        // Prompt routing must also detect CAD plate even if preferredType was imperialComplex
        let routed = WuMindSpatial3DEngine.synthesizeParametricScene(
            prompt: "生成一块带四个安装孔的金属安装板，孔距 130mm，导出 STEP 与 DXF",
            preferredType: .imperialComplex,
            creationMode: .textDescription
        )
        XCTAssertTrue(routed.title.contains("四孔安装板"))
        XCTAssertFalse(routed.nodes.contains(where: { $0.category == .palaceHall }))
    }

    func testHallucinatedPalaceLLMOutputRejectedForWesternTownPrompt() {
        let hallucinatedJSON = """
        {
          "title": "故宫建筑群",
          "sceneType": "imperialComplex",
          "isConceptScene": true,
          "nodes": [
            { "name": "太和殿主殿", "category": "palaceHall", "positionMM": {"x":0,"y":0,"z":0}, "sizeMM": {"x":30000,"y":15000,"z":18000} },
            { "name": "午门主城楼", "category": "gateTower", "positionMM": {"x":0,"y":0,"z":50000}, "sizeMM": {"x":24000,"y":12000,"z":10000} }
          ]
        }
        """
        let guarded = WuMindSpatial3DEngine.parseOrSynthesizeScene(
            rawModelText: hallucinatedJSON,
            prompt: "做一个西部牛仔小镇，有河流、木桥、火车站和酒馆",
            preferredType: .gameScene,
            creationMode: .textDescription
        )
        XCTAssertEqual(guarded.sceneType, .gameScene)
        XCTAssertFalse(guarded.nodes.contains(where: { $0.name.contains("太和殿") || $0.name.contains("午门") }),
                       "模型幻觉吐出故宫时必须被防错回退为真实西部小镇")
        XCTAssertTrue(guarded.nodes.contains(where: { $0.name.contains("火车站") }))
    }
}
