import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class WuMindHardeningTests: XCTestCase {

    // MARK: - 1. Per-Account Storage Isolation

    func testAccountStorageScopeIsolatesAccountsAndSanitizesIDs() {
        let base = URL(fileURLWithPath: "/tmp/WuMindLocal", isDirectory: true)
        let ownerA = WuMindAccountStorageScope.resolvedOwnerID(
            managedAccountID: "WM-USER-ALPHA",
            externalWuMindUserID: nil,
            externalProfileID: nil
        )
        let ownerB = WuMindAccountStorageScope.resolvedOwnerID(
            managedAccountID: "WM-USER-BETA",
            externalWuMindUserID: nil,
            externalProfileID: nil
        )
        XCTAssertNotEqual(ownerA, ownerB)

        let urlA = WuMindAccountStorageScope.conversationsFileURL(baseFolder: base, ownerID: ownerA)
        let urlB = WuMindAccountStorageScope.conversationsFileURL(baseFolder: base, ownerID: ownerB)
        XCTAssertNotEqual(urlA.path, urlB.path)
        XCTAssertTrue(urlA.path.contains("/Accounts/WM-USER-ALPHA/conversations.json"))
        XCTAssertTrue(urlB.path.contains("/Accounts/WM-USER-BETA/conversations.json"))

        // Path traversal or special characters must be sanitized safely
        let unsafeOwner = WuMindAccountStorageScope.sanitize("../../evil/owner name!")
        XCTAssertFalse(unsafeOwner.contains("/"))
        XCTAssertFalse(unsafeOwner.contains(".."))
        XCTAssertFalse(unsafeOwner.isEmpty)

        // Fallback to external user ID and finally "local"
        let externalResolved = WuMindAccountStorageScope.resolvedOwnerID(
            managedAccountID: "   ",
            externalWuMindUserID: "WM-EXT-001",
            externalProfileID: "ext-profile"
        )
        XCTAssertEqual(externalResolved, "WM-EXT-001")
        let localResolved = WuMindAccountStorageScope.resolvedOwnerID(
            managedAccountID: "",
            externalWuMindUserID: nil,
            externalProfileID: nil
        )
        XCTAssertEqual(localResolved, "local")
    }

    // MARK: - 2. Pending Delete Tombstone Queue (No Resurrection on Cloud Sync)

    func testPendingDeleteQueuePreventsResurrectionUntilConfirmed() throws {
        var queue = WuMindPendingDeleteQueue()
        XCTAssertTrue(queue.isEmpty)

        queue.enqueue("work-deleted-offline")
        XCTAssertEqual(queue.count, 1)
        XCTAssertTrue(queue.isTombstoned("work-deleted-offline"))
        XCTAssertTrue(queue.shouldSkipRemoteWork("work-deleted-offline"))
        XCTAssertFalse(queue.shouldSkipRemoteWork("work-alive"))

        // Simulate offline DELETE retry failure — tombstone must remain active
        queue.recordFailure("work-deleted-offline", error: "网络断开，待恢复后补发删除")
        XCTAssertEqual(queue.entries["work-deleted-offline"]?.retryCount, 1)
        XCTAssertTrue(queue.shouldSkipRemoteWork("work-deleted-offline"))

        // Codable persistence round-trip across app restart
        let encoded = try JSONEncoder().encode(queue)
        var restored = try JSONDecoder().decode(WuMindPendingDeleteQueue.self, from: encoded)
        XCTAssertTrue(restored.shouldSkipRemoteWork("work-deleted-offline"))
        XCTAssertEqual(restored.entries["work-deleted-offline"]?.retryCount, 1)

        // Confirm cloud deletion (HTTP 200 / 204 / 404) clears tombstone
        restored.confirmDeleted("work-deleted-offline")
        XCTAssertTrue(restored.isEmpty)
        XCTAssertFalse(restored.shouldSkipRemoteWork("work-deleted-offline"))
    }

    // MARK: - 3. Video Submission Failure vs Polling/Download Unconfirmed Status

    func testVideoJobFailureClassifierSeparatesSubmissionFromPollingAndUpstreamFail() {
        // Phase 1: failed before server returned jobID -> safe to mark failed & allow retry
        XCTAssertEqual(
            WuMindVideoJobFailureClassifier.classify(upstreamJobID: nil, upstreamConfirmedFailed: false),
            .submissionFailed
        )
        XCTAssertEqual(
            WuMindVideoJobFailureClassifier.classify(upstreamJobID: "   ", upstreamConfirmedFailed: false),
            .submissionFailed
        )

        // Phase 2: server already accepted jobID, phone lost network during poll/download -> MUST be unconfirmed ("暂时无法确认")
        XCTAssertEqual(
            WuMindVideoJobFailureClassifier.classify(upstreamJobID: "vid_job_98765", upstreamConfirmedFailed: false),
            .pollStatusUnconfirmed
        )

        // Phase 3: upstream explicitly confirmed terminal failure -> safe to mark failed & offer retry
        XCTAssertEqual(
            WuMindVideoJobFailureClassifier.classify(upstreamJobID: "vid_job_98765", upstreamConfirmedFailed: true),
            .upstreamConfirmedFailed
        )
    }

    // MARK: - 4. Strict Failure Honesty for Web Search & Agent Citations

    func testToolTruthfulnessPolicyBlocksCapabilityVerifiedBadgeAndFailedAgentCitations() {
        let okAgent = WuMindAgentCitation(agentID: "agent_duty", agentName: "值班核对助手", summary: "已核对排班", succeeded: true)
        let failedAgent = WuMindAgentCitation(agentID: "agent_ppt", agentName: "PPT规划助手", summary: "", succeeded: false, errorMessage: "上游超时")
        let searchFailure = WuMindToolFailureNotice(toolKind: "web_search", targetName: "今日卫星公告", message: "联网搜索上游超时，未产生扣费")

        // Case A: All succeeded, 0 failures -> allowed to display badge and succeeded agent citation
        XCTAssertFalse(WuMindToolTruthfulnessPolicy.hasAnyToolFailure(agentCitations: [okAgent], failureNotices: []))
        XCTAssertTrue(WuMindToolTruthfulnessPolicy.canShowCapabilityVerifiedBadge(
            baseBadge: "能力已验证",
            agentCitations: [okAgent],
            failureNotices: []
        ))
        XCTAssertEqual(WuMindToolTruthfulnessPolicy.visibleAgentCitations(from: [okAgent]).map(\.agentName), ["值班核对助手"])

        // Case B: Web search failed -> MUST block "能力已验证" even if baseBadge was set
        XCTAssertTrue(WuMindToolTruthfulnessPolicy.hasAnyToolFailure(agentCitations: [okAgent], failureNotices: [searchFailure]))
        XCTAssertFalse(WuMindToolTruthfulnessPolicy.canShowCapabilityVerifiedBadge(
            baseBadge: "能力已验证",
            agentCitations: [okAgent],
            failureNotices: [searchFailure]
        ))

        // Case C: Agent failed -> MUST exclude failed agent from visibleAgentCitations AND block "能力已验证"
        let visible = WuMindToolTruthfulnessPolicy.visibleAgentCitations(from: [okAgent, failedAgent])
        XCTAssertEqual(visible.map(\.agentName), ["值班核对助手"])
        XCTAssertFalse(visible.contains(where: { $0.agentID == "agent_ppt" }))
        XCTAssertFalse(WuMindToolTruthfulnessPolicy.canShowCapabilityVerifiedBadge(
            baseBadge: "能力已验证",
            agentCitations: [okAgent, failedAgent],
            failureNotices: []
        ))
    }

    // MARK: - 5. Gateway Real SSE Web Search Event Stream

    func testStreamWebSearchEmitsRealSearchingReadingPageResultAndDoneEvents() async throws {
        let client = WuMindGatewayClient(
            dataTransport: { _ in fatalError("Not expected") },
            streamTransport: { request, status, line in
                XCTAssertEqual(request.url?.absoluteString, "https://api.wumind.test/v1/tools/web-search")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
                try status(200)
                try await line("event: searching")
                try await line(#"data: {"query":"2026年航天测控最新进展"}"#)
                try await line("")
                try await line("event: search_results")
                try await line(#"data: {"query":"2026年航天测控最新进展","count":2}"#)
                try await line("")
                try await line("event: reading")
                try await line(#"data: {"title":"国家航天局公告","domain":"cnsa.gov.cn","url":"https://www.cnsa.gov.cn/n1","index":1,"total":2}"#)
                try await line("")
                try await line("event: page_result")
                try await line(#"data: {"url":"https://www.cnsa.gov.cn/n1","ok":true,"domain":"cnsa.gov.cn","title":"国家航天局公告"}"#)
                try await line("")
                try await line("event: done")
                try await line(#"data: {"ok":true,"status":"ok","query":"2026年航天测控最新进展","provider":"tavily","results":[{"title":"国家航天局公告","url":"https://www.cnsa.gov.cn/n1","snippet":"测控站升级完成","readStatus":"full_text","extractedText":"正文"}],"fullTextCount":1,"fetchFailedCount":0,"costYuan":0.03,"balanceYuan":9.97}"#)
                try await line("")
            }
        )

        var sawSearching: String?
        var sawReadingDomains: [String] = []
        var sawPageResultOK = false
        var finalResp: WuMindWebSearchResponse?

        for try await ev in client.streamWebSearch(
            gatewayURL: "https://api.wumind.test",
            userToken: "wm_live_token",
            query: "2026年航天测控最新进展"
        ) {
            switch ev {
            case .searching(let q):
                sawSearching = q
            case .reading(_, let domain, _, _, _):
                sawReadingDomains.append(domain)
            case .pageResult(_, let ok, _, _):
                sawPageResultOK = ok
            case .done(let resp):
                finalResp = resp
            case .searchResults, .error:
                break
            }
        }

        XCTAssertEqual(sawSearching, "2026年航天测控最新进展")
        XCTAssertEqual(sawReadingDomains, ["cnsa.gov.cn"])
        XCTAssertTrue(sawPageResultOK)
        XCTAssertEqual(finalResp?.results.count, 1)
        XCTAssertEqual(finalResp?.fullTextCount, 1)
        XCTAssertEqual(finalResp?.costYuan, 0.03)
    }

    func testStreamWebSearchEmitsErrorEventWithoutFabricatingSuccess() async throws {
        let client = WuMindGatewayClient(
            dataTransport: { _ in fatalError("Not expected") },
            streamTransport: { _, status, line in
                try status(200)
                try await line("event: searching")
                try await line(#"data: {"query":"实时股价"}"#)
                try await line("")
                try await line("event: error")
                try await line(#"data: {"status":503,"code":"search_not_configured","message":"网关尚未配置联网搜索密钥，未产生扣费"}"#)
                try await line("")
            }
        )

        var receivedErrorCode: String?
        var receivedDone = false
        for try await ev in client.streamWebSearch(
            gatewayURL: "https://api.wumind.test",
            userToken: "wm_live_token",
            query: "实时股价"
        ) {
            switch ev {
            case .error(_, let code, _):
                receivedErrorCode = code
            case .done:
                receivedDone = true
            default:
                break
            }
        }

        XCTAssertEqual(receivedErrorCode, "search_not_configured")
        XCTAssertFalse(receivedDone, "Failed SSE web search MUST NOT emit a synthetic done response")
    }

    // MARK: - 6. Duty PassPlan Multi-Shot Burst, Header Carryover, Web vs Spreadsheet Time Rules & Smart Dedup

    private func makeWebLayout() -> PassPlan.Layout {
        PassPlan.Layout(slots: [
            .init(label: "计划编号", column: nil, x: 0.05),
            .init(label: "圈次", column: .orbit, x: 0.16),
            .init(label: "卫星代号", column: .satellite, x: 0.28),
            .init(label: "地面站", column: .station, x: 0.42),
            .init(label: "数传开始时间", column: .start, x: 0.58),
            .init(label: "数传结束时间", column: .end, x: 0.74),
            .init(label: "状态", column: .status, x: 0.90),
        ])
    }

    private func makeSpreadsheetLayout() -> PassPlan.Layout {
        PassPlan.Layout(slots: [
            .init(label: "计划编号", column: nil, x: 0.05),
            .init(label: "圈次", column: .orbit, x: 0.16),
            .init(label: "卫星代号", column: .satellite, x: 0.28),
            .init(label: "地面站", column: .station, x: 0.42),
            .init(label: "数传开始时间", column: .start, x: 0.60),
            // Intentionally mis-tagged .end on 创建时间 to also verify sanitizedLayout strips it!
            .init(label: "创建时间", column: .end, x: 0.78),
            .init(label: "状态", column: .status, x: 0.92),
        ])
    }

    func testPassPlanBurstEngineWebPageKeepsStartAndEndAndFlagsUnreadableEnd() {
        let layout = makeWebLayout()
        XCTAssertEqual(PassPlanBurstEngine.classifyTableKind(layout: layout), .webPage)

        let completeRow = PassPlanRow(
            orbit: "1024",
            satellite: "GF-01",
            station: "喀什站",
            start: "2026-11-25 08:10:00",
            end: "2026-11-25 08:21:30",
            status: "正常",
            cells: ["P-1001", "1024", "GF-01", "喀什站", "2026-11-25 08:10:00", "2026-11-25 08:21:30", "正常"]
        )
        let missingEndRow = PassPlanRow(
            orbit: "1025",
            satellite: "GF-02",
            station: "三亚站",
            start: "2026-11-25 09:00:00",
            end: "",
            status: "正常",
            cells: ["P-1002", "1025", "GF-02", "三亚站", "2026-11-25 09:00:00", "", "正常"]
        )

        let batch = PassPlanBurstEngine.processBurstPages([
            .init(pageIndex: 0, rows: [completeRow, missingEndRow], layout: layout, hasOwnHeader: true)
        ])

        XCTAssertEqual(batch.tableKind, .webPage)
        XCTAssertEqual(batch.rows.count, 2)
        XCTAssertEqual(batch.rows[0].start, "2026-11-25 08:10:00")
        XCTAssertEqual(batch.rows[0].end, "2026-11-25 08:21:30")
        XCTAssertNil(batch.rows[0].recognitionIssues)

        // Unreadable web end time must stay blank and be flagged "待核对" (never fabricated)
        XCTAssertEqual(batch.rows[1].end, "")
        XCTAssertTrue((batch.rows[1].recognitionIssues ?? []).contains(where: { $0.contains("待核对") }))
    }

    func testPassPlanBurstEngineSpreadsheetIgnoresCreatedTimeAndLeavesEndBlank() {
        let rawLayout = makeSpreadsheetLayout()
        let cleaned = PassPlanBurstEngine.sanitizedLayout(rawLayout)
        XCTAssertNil(cleaned.slots[5].column, "创建时间列绝不能映射到 .end")
        XCTAssertEqual(PassPlanBurstEngine.classifyTableKind(layout: cleaned), .spreadsheet)

        // Even if OCR/LLM mistakenly stuffed 创建时间 into `end`, spreadsheet enforcement MUST wipe `end` to ""
        let pollutedRow = PassPlanRow(
            orbit: "2048",
            satellite: "ZY-03",
            station: "密云站",
            start: "2026-11-25 10:15:00",
            end: "2026-11-24 18:00:00",
            status: "已下发",
            cells: ["P-2001", "2048", "ZY-03", "密云站", "2026-11-25 10:15:00", "2026-11-24 18:00:00", "已下发"]
        )

        let batch = PassPlanBurstEngine.processBurstPages([
            .init(pageIndex: 0, rows: [pollutedRow], layout: rawLayout, hasOwnHeader: true)
        ])

        XCTAssertEqual(batch.tableKind, .spreadsheet)
        XCTAssertEqual(batch.rows.count, 1)
        XCTAssertEqual(batch.rows[0].start, "2026-11-25 10:15:00")
        XCTAssertEqual(batch.rows[0].end, "", "导出表格的创建时间绝不能当成数传结束时间，必须留空")
        XCTAssertNil(batch.rows[0].recognitionIssues, "表格模式留空结束时间不应误报缺失警告")
    }

    func testPassPlanBurstEngineCarriesHeaderToAlignedContinuationAndFlagsMisalignedContinuation() {
        let spreadsheetLayout = makeSpreadsheetLayout()

        // Photo 1: has header (spreadsheet)
        let p1 = PassPlanBurstEngine.PageInput(
            pageIndex: 0,
            rows: [
                PassPlanRow(
                    orbit: "3001", satellite: "SAT-A", station: "喀什站",
                    start: "2026-11-25 11:00:00", end: "2026-11-24 17:00:00",
                    cells: ["P-3001", "3001", "SAT-A", "喀什站", "2026-11-25 11:00:00", "2026-11-24 17:00:00", "正常"]
                )
            ],
            layout: spreadsheetLayout,
            hasOwnHeader: true
        )

        // Photo 2: headerless, aligned column geometry -> inherits spreadsheet rule (end wiped to ""), zero alignment warnings
        let p2 = PassPlanBurstEngine.PageInput(
            pageIndex: 1,
            rows: [
                PassPlanRow(
                    orbit: "3002", satellite: "SAT-B", station: "三亚站",
                    start: "2026-11-25 12:00:00", end: "2026-11-24 17:05:00",
                    cells: ["P-3002", "3002", "SAT-B", "三亚站", "2026-11-25 12:00:00", "2026-11-24 17:05:00", "正常"]
                )
            ],
            layout: nil,
            hasOwnHeader: false,
            observedColumnXs: [0.06, 0.17, 0.29, 0.43, 0.61, 0.79, 0.91],
            observedColumnCount: 7
        )

        // Photo 3: headerless, severely misaligned column count & x positions -> MUST flag "待核对"
        let p3 = PassPlanBurstEngine.PageInput(
            pageIndex: 2,
            rows: [
                PassPlanRow(
                    orbit: "3003", satellite: "SAT-C", station: "佳木斯站",
                    start: "2026-11-25 13:00:00", end: "",
                    cells: ["3003", "SAT-C", "2026-11-25 13:00:00"]
                )
            ],
            layout: nil,
            hasOwnHeader: false,
            observedColumnXs: [0.10, 0.50, 0.85],
            observedColumnCount: 3
        )

        let result = PassPlanBurstEngine.processBurstPages([p1, p2, p3])
        XCTAssertEqual(result.tableKind, .spreadsheet)
        XCTAssertEqual(result.rows.count, 3)
        XCTAssertEqual(result.alignmentWarningPages, [2])
        // Photo 2 inherited spreadsheet rule cleanly
        XCTAssertEqual(result.rows[1].end, "")
        XCTAssertNil(result.rows[1].recognitionIssues)
        // Photo 3 flagged for human verification due to column misalignment
        XCTAssertTrue((result.rows[2].recognitionIssues ?? []).contains(where: { $0.contains("待核对") && $0.contains("未对齐") }))
    }

    func testPassPlanBurstEngineDedupPriority1PlanCodeAndFlagsKeyConflicts() {
        let layout = makeWebLayout()

        // Photo 1: row P-5001 (missing status, complete end) + row P-5002 (orbit "502")
        let page1 = PassPlanBurstEngine.PageInput(
            pageIndex: 0,
            rows: [
                PassPlanRow(
                    orbit: "501", satellite: "GF-05", station: "喀什站",
                    start: "2026-11-25 14:00:00", end: "2026-11-25 14:12:00", status: "",
                    cells: ["P-5001", "501", "GF-05", "喀什站", "2026-11-25 14:00:00", "2026-11-25 14:12:00", ""]
                ),
                PassPlanRow(
                    orbit: "502", satellite: "GF-06", station: "密云站",
                    start: "2026-11-25 15:00:00", end: "2026-11-25 15:10:00", status: "正常",
                    cells: ["P-5002", "502", "GF-06", "密云站", "2026-11-25 15:00:00", "2026-11-25 15:10:00", "正常"]
                ),
            ],
            layout: layout,
            hasOwnHeader: true
        )

        // Photo 2 overlaps BOTH:
        // - P-5001 now has clearer status "已确认" -> merged cleanly with 0 conflicts
        // - P-5002 has conflicting station "三亚站" vs "密云站" -> merged by 计划编号 AND flagged "待核对"
        let page2 = PassPlanBurstEngine.PageInput(
            pageIndex: 1,
            rows: [
                PassPlanRow(
                    orbit: "501", satellite: "GF-05", station: "喀什站",
                    start: "2026-11-25 14:00:00", end: "2026-11-25 14:12:00", status: "已确认",
                    cells: ["P-5001", "501", "GF-05", "喀什站", "2026-11-25 14:00:00", "2026-11-25 14:12:00", "已确认"]
                ),
                PassPlanRow(
                    orbit: "502", satellite: "GF-06", station: "三亚站",
                    start: "2026-11-25 15:00:00", end: "2026-11-25 15:10:00", status: "正常",
                    cells: ["P-5002", "502", "GF-06", "三亚站", "2026-11-25 15:00:00", "2026-11-25 15:10:00", "正常"]
                ),
            ],
            layout: nil,
            hasOwnHeader: false
        )

        let res = PassPlanBurstEngine.processBurstPages([page1, page2])
        XCTAssertEqual(res.rows.count, 2)
        XCTAssertEqual(res.mergedDuplicateCount, 2)
        XCTAssertEqual(res.conflictCount, 1)
        XCTAssertEqual(res.rows[0].status, "已确认", "重叠合并应保留更清晰完整的字段")
        XCTAssertTrue((res.rows[1].recognitionIssues ?? []).contains(where: { $0.contains("待核对") && $0.contains("冲突") }))
    }

    func testPassPlanBurstEngineDedupPriority2CompositeKeyNeverDedupsByStartTimeAlone() {
        // Layout WITHOUT 计划编号 to exercise Priority 2 `(satellite, station, orbit, startTime)`
        let layout = PassPlan.Layout(slots: [
            .init(label: "圈次", column: .orbit, x: 0.10),
            .init(label: "卫星代号", column: .satellite, x: 0.25),
            .init(label: "地面站", column: .station, x: 0.42),
            .init(label: "数传开始时间", column: .start, x: 0.62),
            .init(label: "数传结束时间", column: .end, x: 0.82),
        ])

        let p1 = PassPlanBurstEngine.PageInput(
            pageIndex: 0,
            rows: [
                PassPlanRow(
                    orbit: "701", satellite: "JL-01", station: "喀什站",
                    start: "2026-11-25 16:00:00", end: "2026-11-25 16:11:00",
                    cells: ["701", "JL-01", "喀什站", "2026-11-25 16:00:00", "2026-11-25 16:11:00"]
                )
            ],
            layout: layout,
            hasOwnHeader: true
        )

        // Photo 2 contains:
        // 1. Exact overlap of (701, JL-01, 喀什站, 16:00:00) -> MUST deduplicate into 1
        // 2. SAME startTime (16:00:00) & SAME satellite, but DIFFERENT station ("三亚站") -> MUST KEEP BOTH!
        let p2 = PassPlanBurstEngine.PageInput(
            pageIndex: 1,
            rows: [
                PassPlanRow(
                    orbit: "701", satellite: "JL-01", station: "喀什站",
                    start: "2026-11-25 16:00:00", end: "2026-11-25 16:11:00",
                    cells: ["701", "JL-01", "喀什站", "2026-11-25 16:00:00", "2026-11-25 16:11:00"]
                ),
                PassPlanRow(
                    orbit: "701", satellite: "JL-01", station: "三亚站",
                    start: "2026-11-25 16:00:00", end: "2026-11-25 16:11:00",
                    cells: ["701", "JL-01", "三亚站", "2026-11-25 16:00:00", "2026-11-25 16:11:00"]
                ),
            ],
            layout: nil,
            hasOwnHeader: false
        )

        let res = PassPlanBurstEngine.processBurstPages([p1, p2])
        XCTAssertEqual(res.mergedDuplicateCount, 1)
        XCTAssertEqual(res.rows.count, 2, "同开始时间但不同地面站的两条计划绝不能被误去重")
        XCTAssertEqual(Set(res.rows.map(\.station)), ["喀什站", "三亚站"])
    }
}
