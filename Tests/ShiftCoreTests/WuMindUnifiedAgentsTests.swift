import Foundation
import XCTest
@testable import ShiftCore

final class WuMindUnifiedAgentsTests: XCTestCase {

    // MARK: - 1. Background Monitor Agent (Dedup + Diff + Pause + Failure)

    func testBackgroundMonitorDedupDiffPauseAndFailure() async {
        let initialSub = WuMindBackgroundMonitorEngine.MonitorSubscription(
            title: "公开招标监测",
            targetURL: "https://example.gov.cn/tender/2026",
            intervalMinutes: 30,
            lastFields: ["截标时间": "2026-12-01 09:30", "预算金额": "150 万元"]
        )
        let amendmentPage = """
        <html><body>
        更正公告：
        截标时间：2026-12-10 14:30
        预算金额：150 万元
        更正事项：递交截止时间延期 9 天。
        </body></html>
        """

        // Pass 1: Detects amendment and dispatches EXACTLY 1 notification with original excerpt & old->new diff
        let first = await WuMindBackgroundMonitorEngine.poll(subscription: initialSub, trigger: "scheduled", fetcher: { _ in amendmentPage })
        XCTAssertNotNil(first.notification)
        XCTAssertEqual(first.notification?.diffs.first(where: { $0.field == "截标时间" })?.oldValue, "2026-12-01 09:30")
        XCTAssertEqual(first.notification?.diffs.first(where: { $0.field == "截标时间" })?.newValue, "2026-12-10 14:30")
        XCTAssertTrue(first.notification?.originalExcerpt.contains("更正公告") == true)
        XCTAssertEqual(first.taskRun.status, .completed)

        // Pass 2: Same content polled again -> deduplicated, ZERO notification!
        let second = await WuMindBackgroundMonitorEngine.poll(subscription: first.subscription, trigger: "scheduled", fetcher: { _ in amendmentPage })
        XCTAssertNil(second.notification)
        XCTAssertEqual(second.subscription.executionLog.last?.outcome, "noChange")

        // Pass 3: Paused monitor does not fetch
        var pausedSub = second.subscription
        pausedSub.paused = true
        let paused = await WuMindBackgroundMonitorEngine.poll(subscription: pausedSub, trigger: "scheduled", fetcher: { _ in
            XCTFail("Paused monitor must not fetch")
            return ""
        })
        XCTAssertEqual(paused.taskRun.status, .paused)

        // Pass 4: Failure records explicit reason
        let failed = await WuMindBackgroundMonitorEngine.poll(subscription: second.subscription, trigger: "event", fetcher: { _ in
            throw NSError(domain: "Net", code: 504, userInfo: [NSLocalizedDescriptionKey: "Gateway Timeout 504"])
        })
        XCTAssertNil(failed.notification)
        XCTAssertEqual(failed.taskRun.status, .failed)
        XCTAssertTrue(failed.taskRun.lastError?.contains("504") == true)
    }

    // MARK: - 2. Cross-App Execution Agent (Real .xlsx Write + Approval Gate + Interrupt Resume + Idempotent Retry)

    func testCrossAppQuoteComparisonRealXLSXWriteApprovalAndIdempotentResume() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("WuMindQuoteTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let targetXLSX = tmpDir.appendingPathComponent("比价表.xlsx")

        let files: [WuMindCrossAppQuoteEngine.QuoteFileInput] = [
            .init(fileName: "A_quote.csv", content: "供应商：甲公司\n标的物：功放\n未税价：10000\n运费：200\n交期：7天"),
            .init(fileName: "B_quote.csv", content: "供应商：乙公司\n标的物：功放\n含税价：11200\n运费：0\n交期：5天"),
            .init(fileName: "C_quote.csv", content: "供应商：丙公司\n标的物：功放\n含税价：10900\n运费：300"),
        ]

        // 1. Simulate interruption after 2 of 3 files
        let interrupted = try WuMindCrossAppQuoteEngine.executeFolderQuoteComparison(
            files: files,
            targetWorkbookURL: targetXLSX,
            failAfterProcessedCount: 2
        )
        XCTAssertEqual(interrupted.taskRun.status, .failed)
        XCTAssertEqual(interrupted.extractedRows.count, 2)
        XCTAssertFalse(interrupted.workbookWritten)

        // 2. Resume from checkpoint: processes ONLY the 3rd file, ZERO duplicate rows, writes real .xlsx to disk!
        let resumed = try WuMindCrossAppQuoteEngine.executeFolderQuoteComparison(
            files: files,
            targetWorkbookURL: targetXLSX,
            existingState: interrupted
        )
        XCTAssertEqual(resumed.extractedRows.count, 3)
        XCTAssertTrue(resumed.workbookWritten)
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetXLSX.path))
        // Must pause at Approval Gate before external sending!
        XCTAssertEqual(resumed.taskRun.status, .awaitingApproval)
        XCTAssertEqual(resumed.taskRun.pendingApproval?.actionKind, .sendMessage)
        XCTAssertFalse(resumed.sendDispatched)

        // Verify the written file on disk is a real ZIP/OpenXML .xlsx workbook containing supplier rows!
        let bytes = try Data(contentsOf: targetXLSX)
        XCTAssertEqual(bytes.prefix(2), Data([0x50, 0x4B]), "Written .xlsx must start with PK ZIP header")
        let rawText = String(decoding: bytes, as: UTF8.self)
        XCTAssertTrue(rawText.contains("xl/worksheets/sheet1.xml"))
        XCTAssertTrue(rawText.contains("甲公司"))
        XCTAssertTrue(rawText.contains("乙公司"))
        XCTAssertTrue(rawText.contains("丙公司"))
        XCTAssertTrue(rawText.contains("待确认"))

        // 3. Re-running against an existing file WITHOUT overwrite approval pauses at overwrite approval gate
        let overwriteGuard = try WuMindCrossAppQuoteEngine.executeFolderQuoteComparison(
            files: files,
            targetWorkbookURL: targetXLSX,
            approvalGrantedForOverwrite: false
        )
        XCTAssertEqual(overwriteGuard.taskRun.status, .awaitingApproval)
        XCTAssertEqual(overwriteGuard.taskRun.pendingApproval?.actionKind, .overwriteFile)
    }

    // MARK: - 3. Deliverable Export (.docx + .xlsx) & Chained End-to-End Acceptance (Monitor -> Partial Revision)

    func testChainedMonitorAmendmentToPartialRevisionProtectingHumanEditsAndExportingDOCXAndXLSX() async throws {
        let graph = WuMindProjectArtifactGraph(
            title: "某测控运维标书项目",
            clauses: [
                .init(id: "C-DEADLINE", title: "截标时间", text: "截标时间：2026-12-01 09:30", sourceLocation: "招标公告第 2 章第 1 条"),
                .init(id: "C-TECH", title: "SLA 指标", text: "可用性 99.95%", sourceLocation: "技术规格书第 5 章第 2 条"),
            ],
            chapters: [
                .init(id: "CH-1", title: "第一章 投标函", body: "承诺于 2026-12-01 09:30 前递交。", linkedClauseIDs: ["C-DEADLINE"], humanEdited: false),
                .init(id: "CH-2", title: "第二章 商务定稿（人工修改）", body: "【人工定稿】严格保留本段商务签章说明。", linkedClauseIDs: ["C-DEADLINE"], humanEdited: true),
                .init(id: "CH-3", title: "第三章 技术方案", body: "双活值守，可用性 99.98%。", linkedClauseIDs: ["C-TECH"], humanEdited: false),
            ],
            matrixRows: [
                .init(id: "M-1", clauseID: "C-DEADLINE", requirement: "截标时间：2026-12-01 09:30", response: "按期递交", status: "已响应", sourceLocation: "招标公告第 2 章第 1 条"),
                .init(id: "M-2", clauseID: "C-TECH", requirement: "可用性 99.95%", response: "承诺 99.98%", status: "优于指标", sourceLocation: "技术规格书第 5 章第 2 条"),
            ]
        )
        let sub = WuMindBackgroundMonitorEngine.MonitorSubscription(
            projectID: graph.id,
            title: "采购网监测",
            targetURL: "https://ccgp.example.cn/notice/88",
            lastFields: ["截标时间": "2026-12-01 09:30"]
        )

        let chained = try await WuMindBackgroundMonitorEngine.runChainedMonitorAndPartialRevision(
            subscription: sub,
            graph: graph,
            fieldToClauseID: ["截标时间": "C-DEADLINE"],
            trigger: "scheduled",
            fetcher: { _ in "更正公告：截标时间：2026-12-10 14:30；其余条款不变。" }
        )

        // 1. Background monitor caught diff & emitted notification
        XCTAssertNotNil(chained.poll.notification)
        XCTAssertEqual(chained.poll.notification?.diffs.first?.newValue, "2026-12-10 14:30")

        // 2. Partial revision updated ONLY CH-1 & M-1; preserved CH-2 (humanEdited) & untouched CH-3 & M-2!
        let rev = try XCTUnwrap(chained.revision)
        XCTAssertEqual(rev.audit.updatedChapterIDs, ["CH-1"])
        XCTAssertEqual(rev.audit.preservedHumanChapterIDs, ["CH-2"])
        XCTAssertEqual(rev.audit.untouchedChapterIDs, ["CH-3"])
        XCTAssertEqual(rev.audit.updatedMatrixRowIDs, ["M-1"])
        XCTAssertEqual(rev.graph.chapters[1].body, "【人工定稿】严格保留本段商务签章说明。", "Human-edited chapter must NEVER be clobbered")
        XCTAssertEqual(rev.graph.chapters[2].revision, 1, "Unrelated chapter revision must remain untouched")
        XCTAssertEqual(rev.graph.matrixRows[1].revision, 1, "Unrelated matrix row must remain untouched")
        XCTAssertTrue(rev.graph.matrixRows[0].requirement.contains("2026-12-10 14:30"))
        XCTAssertEqual(rev.taskRun.status, .awaitingApproval, "Conflict on human-edited chapter requires user approval")

        // 3. Exported real editable .docx + .xlsx binaries contain updated deadline & traceable source citations
        let docx = try XCTUnwrap(chained.docxData)
        let xlsx = try XCTUnwrap(chained.xlsxData)
        XCTAssertEqual(docx.prefix(2), Data([0x50, 0x4B]))
        XCTAssertEqual(xlsx.prefix(2), Data([0x50, 0x4B]))
        XCTAssertTrue(String(decoding: docx, as: UTF8.self).contains("word/document.xml"))
        XCTAssertTrue(String(decoding: xlsx, as: UTF8.self).contains("2026-12-10 14:30"))
    }

    // MARK: - 4. Short-Drama Single-Shot Reshoot Wired to Same Partial-Revision Audit Kernel

    func testShortDramaSingleShotReshootUsesSamePartialRevisionAuditKernel() {
        let project = WuMindShortDramaEngine.sampleVerticalDrama(defaultEngine: .seedance)
        let targetShot = project.shots[1]
        let newTake = WuMindShotTake(
            takeNumber: 2,
            engine: .seedance,
            modelID: "doubao-seedance-1-0-pro",
            promptUsed: "换成近景",
            revisionNote: "换成近景，台词和声音不变",
            videoFilename: "shot2_take2.mp4",
            durationSeconds: targetShot.durationSeconds,
            estimatedCostYuan: 0.8
        )
        let updated = WuMindShortDramaEngine.applySingleShotTake(
            project: project,
            shotID: targetShot.id,
            take: newTake,
            updatedFraming: .closeUp,
            updatedVisualPrompt: "近景特写",
            updatedDialogue: nil,
            keepDialogueAndVoice: true
        )
        let audit = WuMindProjectRevisionEngine.auditShortDramaSingleShotReshoot(before: project, after: updated, targetShotID: targetShot.id)
        XCTAssertTrue(audit.preservedOtherShots)
        XCTAssertTrue(audit.preservedSubtitlesAndAudio)
        XCTAssertEqual(audit.taskRun.kind, .shortDramaRevision)
        XCTAssertEqual(audit.taskRun.status, .completed)
    }

    // MARK: - 5. Live Screen Guide (3 External Pages + Frame Dedup + Instant Stop)

    func testLiveScreenGuideAcrossThreeExternalPagesAndInstantStop() {
        var session = WuMindScreenGuideEngine.startSession(userQuestion: "这个模型为什么连不上？")
        let p1 = WuMindScreenGuideEngine.ScreenFrameObservation(appName: "系统设置", pageTitle: "API 配置页", visibleTextSummary: "Error 401 Invalid API Key", frameDigest: "f1")
        let p1Dup = WuMindScreenGuideEngine.ScreenFrameObservation(appName: "系统设置", pageTitle: "API 配置页", visibleTextSummary: "Error 401 Invalid API Key", frameDigest: "f1")
        let p2 = WuMindScreenGuideEngine.ScreenFrameObservation(appName: "系统设置", pageTitle: "模型白名单", visibleTextSummary: "HTTP 403 model not allowed", frameDigest: "f2")
        let p3 = WuMindScreenGuideEngine.ScreenFrameObservation(appName: "第三方AI客户端", pageTitle: "连接测试", visibleTextSummary: "HTTP 200 OK 已连接", frameDigest: "f3")

        XCTAssertNotNil(WuMindScreenGuideEngine.ingestFrame(session: &session, frame: p1))
        XCTAssertNil(WuMindScreenGuideEngine.ingestFrame(session: &session, frame: p1Dup), "Identical static frame must deduplicate")
        XCTAssertNotNil(WuMindScreenGuideEngine.ingestFrame(session: &session, frame: p2))
        XCTAssertNotNil(WuMindScreenGuideEngine.ingestFrame(session: &session, frame: p3))
        XCTAssertEqual(session.visitedPages.count, 3)
        XCTAssertEqual(session.instructions.count, 3)

        // Stop sharing immediately halts ingestion
        WuMindScreenGuideEngine.stopSession(&session)
        let afterStop = WuMindScreenGuideEngine.ScreenFrameObservation(appName: "微信", pageTitle: "私聊", visibleTextSummary: "机密聊天", frameDigest: "f4")
        XCTAssertNil(WuMindScreenGuideEngine.ingestFrame(session: &session, frame: afterStop))
        XCTAssertEqual(session.taskRun.status, .completed)
    }

    // MARK: - 6. Personal Textbook Agent (Audio + Quiz + Jump Back to Source + Weakness Prioritization)

    func testPersonalTextbookAudioQuizSourceJumpAndWeaknessPrioritization() {
        let chunks: [WuMindPersonalTextbookEngine.SourceChunk] = [
            .init(id: "C1", sourceTitle: "测控教材", pageOrSection: "P18 第2节", topic: "天线仰角限制", excerpt: "仰角低于 5 度禁止发射上行载波。"),
            .init(id: "C2", sourceTitle: "测控教材", pageOrSection: "P45 第4节", topic: "应急指令复核", excerpt: "所有应急指令必须经双人复核确认后方可发送。"),
        ]
        var course = WuMindPersonalTextbookEngine.buildCourse(title: "测控上岗课", chunks: chunks)
        XCTAssertEqual(course.audioSegments.count, 2)

        // Answer Q2 WRONG -> must return exact P45 source citation AND rank C2 FIRST in next practice queue!
        let wrongFeedback = WuMindPersonalTextbookEngine.submitAnswer(course: &course, questionID: course.questions[1].id, selectedOptionIndex: 2)
        XCTAssertEqual(wrongFeedback?.isCorrect, false)
        XCTAssertTrue(wrongFeedback?.sourceCitation.contains("P45") == true)
        XCTAssertTrue(wrongFeedback?.sourceExcerpt.contains("双人复核") == true)

        let nextQueue = WuMindPersonalTextbookEngine.nextPracticeQueue(for: course)
        XCTAssertEqual(nextQueue.first?.topic, "应急指令复核", "Missed topic must be prioritized FIRST next session")
    }

    // MARK: - 7. Mobile Dev & Verification Agent (Pre-Fix FAIL -> Patch Diff -> Same Test Post-Fix PASS -> Approval Gate)

    func testMobileDevPreFixFailPostFixSameTestPassAndApprovalGatedDraftPR() {
        let patch = WuMindMobileDevEngine.PatchProposal(
            branchName: "fix/bug-101",
            touchedFiles: ["Sources/ShiftCore/WuMindDutyQueryEngine.swift"],
            unifiedDiff: "- old\n+ new",
            prTitle: "fix: duty lookup",
            prBody: "Verified fix"
        )
        var verified = WuMindMobileDevEngine.runVerifiedBugFixPipeline(
            repoFullName: "wuyong9494-lab/kriswu",
            bugSummary: "值班问答遗漏全员排班",
            preFix: .init(testIdentifier: "DutyTests/testOnDuty", passed: false, durationSeconds: 0.3, logSnippet: "FAIL"),
            patch: patch,
            postFix: .init(testIdentifier: "DutyTests/testOnDuty", passed: true, durationSeconds: 0.1, logSnippet: "PASS")
        )
        XCTAssertTrue(verified.verifiedFixed)
        XCTAssertEqual(verified.taskRun.status, .awaitingApproval)
        XCTAssertFalse(verified.draftPRCreated)
        XCTAssertFalse(verified.mergedOrUploaded)

        XCTAssertTrue(WuMindMobileDevEngine.approveDraftPRCreation(&verified))
        XCTAssertTrue(verified.draftPRCreated)
        XCTAssertFalse(verified.mergedOrUploaded, "Must NEVER auto-merge or upload builds")

        // Mismatched test names must FAIL verification
        let mismatched = WuMindMobileDevEngine.runVerifiedBugFixPipeline(
            repoFullName: "wuyong9494-lab/kriswu",
            bugSummary: "伪造测试",
            preFix: .init(testIdentifier: "DutyTests/testA", passed: false, durationSeconds: 0.2, logSnippet: "FAIL"),
            patch: patch,
            postFix: .init(testIdentifier: "DutyTests/testB", passed: true, durationSeconds: 0.1, logSnippet: "PASS")
        )
        XCTAssertFalse(mismatched.verifiedFixed)
        XCTAssertEqual(mismatched.taskRun.status, .failed)
    }

    // MARK: - 8. Shareable Mini-App (Rule Edit Recalculation + Zero Secret/Customer Leak Sanitizer)

    func testShareableMiniAppRuleEditAndZeroLeakSanitizer() {
        var app = WuMindMiniAppArtifactEngine.buildThreeTierPricingCalculator()
        let beforePrice = app.tiers[1].calculate(seats: 10, months: 12)
        WuMindMiniAppArtifactEngine.updateTierRule(artifact: &app, tierID: "pro", newAnnualDiscountRate: 0.75)
        let afterPrice = app.tiers[1].calculate(seats: 10, months: 12)
        XCTAssertLessThan(afterPrice, beforePrice)
        XCTAssertTrue(app.htmlContent.contains("0.75"))

        // Inject private customer table, phone, email, API key, GitHub token -> sanitizer MUST strip ALL!
        let fakeAPIKey = "sk-" + "live1234567890abcdef"
        let fakeGHToken = "ghp_" + "1234567890abcdefghij"
        let dirtyHTML = app.htmlContent + """
        <!-- PRIVATE_DATA_BEGIN 客户：秘密公司 13800138000 boss@secret.com PRIVATE_DATA_END -->
        <script data-private="true">const k = "\(fakeAPIKey)"; const g = "\(fakeGHToken)";</script>
        """
        let sanitized = WuMindMiniAppArtifactEngine.sanitizeForExternalShare(rawHTML: dirtyHTML)
        XCTAssertEqual(sanitized.leakedSecretsDetected, 0)
        XCTAssertGreaterThanOrEqual(sanitized.strippedRedactionCount, 2)
        XCTAssertFalse(sanitized.shareableHTML.contains("秘密公司"))
        XCTAssertFalse(sanitized.shareableHTML.contains(fakeAPIKey))
        XCTAssertFalse(sanitized.shareableHTML.contains(fakeGHToken))
    }

    // MARK: - 9. Teach-Once -> Unseen Pilot -> Approved Batch -> Sanitized Shareable Workflow

    func testTeachOncePilotBatchAndSanitizedWorkflowExport() throws {
        let demos: [WuMindCrossAppQuoteEngine.QuoteFileInput] = [
            .init(fileName: "demo1.txt", content: "供应商：私有老客户A\n未税价：10000\n运费：200\n交期：7天"),
        ]
        var wf = WuMindTeachOnceWorkflowEngine.learnFromDemonstration(name: "每周报价比对", demonstrationFiles: demos, taxRate: 0.13)
        XCTAssertEqual(wf.rules.count, 3)

        // Pilot on 1 unseen sample BEFORE running remaining 4 items
        let unseen = WuMindCrossAppQuoteEngine.QuoteFileInput(fileName: "new_vendor.txt", content: "供应商：新厂商\n未税价：10000\n运费：300")
        let pilot = WuMindTeachOnceWorkflowEngine.runPilotOnUnseenSample(workflow: wf, unseenSample: unseen, totalBatchCount: 5, estimatedUnitCostYuan: 0.05)
        XCTAssertEqual(pilot.sampleResult.normalizedLandedTotalYuan, 11600.0, accuracy: 0.01)
        XCTAssertTrue(pilot.sampleResult.missingFields.contains("交期"))
        XCTAssertEqual(pilot.remainingItemCount, 4)
        XCTAssertEqual(pilot.projectedRemainingCostYuan, 0.20, accuracy: 0.001)
        XCTAssertEqual(pilot.taskRun.status, .awaitingApproval)

        // User edits tax rule to 0.06 and runs approved batch
        wf.rules[0].parameter = "0.06"
        let rest: [WuMindCrossAppQuoteEngine.QuoteFileInput] = [
            .init(fileName: "v2.txt", content: "供应商：厂2\n未税价：10000\n运费：0\n交期：3天"),
            .init(fileName: "v3.txt", content: "供应商：厂3\n含税价：10500\n运费：0\n交期：4天"),
        ]
        let batch = WuMindTeachOnceWorkflowEngine.executeApprovedBatch(workflow: wf, pilot: pilot, remainingSamples: rest, approved: true)
        XCTAssertEqual(batch.taskRun.status, .completed)
        XCTAssertEqual(batch.allResults.count, 3)
        XCTAssertEqual(batch.allResults[1].normalizedLandedTotalYuan, 10600.0, accuracy: 0.01)

        // Export sanitized workflow package: MUST contain rules, MUST NOT contain private demo customer data!
        let exported = try WuMindTeachOnceWorkflowEngine.exportSanitizedPackage(workflow: wf)
        let jsonStr = String(decoding: exported, as: UTF8.self)
        XCTAssertTrue(jsonStr.contains("每周报价比对"))
        XCTAssertTrue(jsonStr.contains("normalizeTaxRate"))
        XCTAssertFalse(jsonStr.contains("私有老客户A"), "Shared workflow package must NEVER carry raw supplier data")
    }

    // MARK: - 10. Multi-Model Router & Locked/Intranet Enforcement

    func testModelRouterHonorsLocksAndIntranetIsolation() {
        let locked = WuMindModelRouter.route(role: .deepAnalysis, lockedModel: "claude-sonnet-4-5")
        XCTAssertEqual(locked.selectedModel, "claude-sonnet-4-5")
        XCTAssertFalse(locked.switchedFromDefault)

        let intranet = WuMindModelRouter.route(role: .deepAnalysis, lockedModel: "gpt-5", restrictToIntranet: true)
        XCTAssertEqual(intranet.dataBoundary, .localIntranetOnly)

        var run = WuMindTaskRun(kind: .dutyQuery, title: "内网值班", dataBoundary: .localIntranetOnly)
        let switchRes = run.switchModel(to: "gpt-5")
        if case .failure(.intranetDataBlockedFromPublicModel) = switchRes {
            // Expected!
        } else {
            XCTFail("Intranet task must block switching to public model")
        }
    }
}
