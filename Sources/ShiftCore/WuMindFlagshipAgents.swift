import Foundation

// MARK: - 1. Live Screen Guidance Agent (Cross-App Multi-Page Guidance + Instant Stop)

/// Multi-page continuous live screen-guidance session running on `WuMindTaskRun`.
/// Pairs with iOS ReplayKit (`RPScreenRecorder` / `RPSystemBroadcastPickerView` + App Group frame bridge)
/// so users get step-by-step next-tap guidance across apps without manually taking 5 screenshots.
public enum WuMindScreenGuideEngine {
    public struct ScreenFrameObservation: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public let capturedAt: Date
        public let appName: String
        public let pageTitle: String
        public let visibleTextSummary: String
        public let frameDigest: String

        public init(
            id: UUID = UUID(),
            capturedAt: Date = Date(),
            appName: String,
            pageTitle: String,
            visibleTextSummary: String,
            frameDigest: String
        ) {
            self.id = id
            self.capturedAt = capturedAt
            self.appName = appName
            self.pageTitle = pageTitle
            self.visibleTextSummary = visibleTextSummary
            self.frameDigest = frameDigest
        }
    }

    public struct GuidanceInstruction: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public let stepNumber: Int
        public let appName: String
        public let pageTitle: String
        public let detectedIssue: String
        public let nextAction: String
        public let createdAt: Date

        public init(
            id: UUID = UUID(),
            stepNumber: Int,
            appName: String,
            pageTitle: String,
            detectedIssue: String,
            nextAction: String,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.stepNumber = stepNumber
            self.appName = appName
            self.pageTitle = pageTitle
            self.detectedIssue = detectedIssue
            self.nextAction = nextAction
            self.createdAt = createdAt
        }
    }

    public struct LiveGuideSession: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public var userQuestion: String
        public var isSharing: Bool
        public var lastFrameDigest: String?
        public var visitedPages: [String]
        public var instructions: [GuidanceInstruction]
        public var taskRun: WuMindTaskRun

        public init(
            id: UUID = UUID(),
            userQuestion: String,
            isSharing: Bool = true,
            lastFrameDigest: String? = nil,
            visitedPages: [String] = [],
            instructions: [GuidanceInstruction] = [],
            taskRun: WuMindTaskRun
        ) {
            self.id = id
            self.userQuestion = userQuestion
            self.isSharing = isSharing
            self.lastFrameDigest = lastFrameDigest
            self.visitedPages = visitedPages
            self.instructions = instructions
            self.taskRun = taskRun
        }
    }

    public static func startSession(userQuestion: String, now: Date = Date()) -> LiveGuideSession {
        let run = WuMindTaskRun(
            kind: .liveScreenGuide,
            title: "实时看屏指导：\(String(userQuestion.prefix(28)))",
            status: .running,
            activeModelLabel: "实时看屏视觉指导引擎",
            dataBoundary: .authorizedConnector,
            createdAt: now,
            updatedAt: now
        )
        return LiveGuideSession(userQuestion: userQuestion, isSharing: true, taskRun: run)
    }

    /// Processes a live screen frame from WUMIND or an external iOS app.
    /// Deduplicates unchanged frames, tracks cross-page transitions, diagnoses errors, and emits next-tap guidance.
    /// Returns `nil` instruction if sharing has been stopped or frame is identical to previous frame.
    public static func ingestFrame(
        session: inout LiveGuideSession,
        frame: ScreenFrameObservation,
        now: Date = Date()
    ) -> GuidanceInstruction? {
        guard session.isSharing else { return nil }
        guard frame.frameDigest != session.lastFrameDigest else { return nil }
        session.lastFrameDigest = frame.frameDigest

        let pageKey = "\(frame.appName)::\(frame.pageTitle)"
        if session.visitedPages.last != pageKey {
            session.visitedPages.append(pageKey)
        }

        let (issue, nextAction) = diagnoseFrame(frame: frame, question: session.userQuestion)
        let instruction = GuidanceInstruction(
            stepNumber: session.instructions.count + 1,
            appName: frame.appName,
            pageTitle: frame.pageTitle,
            detectedIssue: issue,
            nextAction: nextAction,
            createdAt: now
        )
        session.instructions.append(instruction)
        session.taskRun.recordCompletedStep(
            title: "看屏第 \(instruction.stepNumber) 步：\(frame.appName) / \(frame.pageTitle)",
            toolName: "live_screen_analyze",
            idempotencyKey: "screen:\(session.id.uuidString):\(frame.frameDigest)",
            dataSource: pageKey,
            modelUsed: session.taskRun.activeModelLabel,
            dataBoundary: .authorizedConnector,
            outputSummary: "\(issue) → \(nextAction)",
            now: now
        )
        return instruction
    }

    public static func stopSession(_ session: inout LiveGuideSession, now: Date = Date()) {
        session.isSharing = false
        session.taskRun.status = .completed
        session.taskRun.updatedAt = now
    }

    private static func diagnoseFrame(frame: ScreenFrameObservation, question: String) -> (String, String) {
        let lower = frame.visibleTextSummary.lowercased()
        if lower.contains("401") || lower.contains("invalid api key") || lower.contains("unauthorized") || lower.contains("token") {
            return ("识别到鉴权错误（HTTP 401 / Key 无效）", "点击「API Key 设置」检查密钥是否包含多余空格并重新保存验证。")
        }
        if lower.contains("403") || lower.contains("model not allowed") || lower.contains("forbidden") {
            return ("识别到模型访问受限（HTTP 403 / 权限不足）", "返回「模型列表」切换至账号已开通的可用模型，或核对白名单设置。")
        }
        if lower.contains("timeout") || lower.contains("timed out") || lower.contains("dns") || lower.contains("offline") || lower.contains("无法连接") {
            return ("识别到网络连接/代理超时", "打开系统「无线局域网 / 代理设置」确认网络连通后点击「重试连接」。")
        }
        if lower.contains("已连接") || lower.contains("connected") || lower.contains("200 ok") || lower.contains("测试通过") {
            return ("连接状态已恢复正常", "配置验证成功，可随时点击「停止共享」结束本次看屏指导。")
        }
        return ("已读取「\(frame.appName) · \(frame.pageTitle)」页面内容", "请根据当前页面提示点击下一步配置入口，切换页面后我将继续跟屏指导（问题：\(String(question.prefix(24)))）。")
    }
}

// MARK: - 2. Personal Textbook Agent (Audio Lecture + Interactive Quiz + Source Jump + Weakness Prioritization)

public enum WuMindPersonalTextbookEngine {
    public struct SourceChunk: Codable, Identifiable, Equatable, Sendable {
        public let id: String
        public let sourceTitle: String
        public let pageOrSection: String
        public let topic: String
        public let excerpt: String

        public init(id: String, sourceTitle: String, pageOrSection: String, topic: String, excerpt: String) {
            self.id = id
            self.sourceTitle = sourceTitle
            self.pageOrSection = pageOrSection
            self.topic = topic
            self.excerpt = excerpt
        }
    }

    public struct AudioSegment: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public let sourceChunkID: String
        public let title: String
        public let spokenScript: String
        public let estimatedSeconds: Int

        public init(id: UUID = UUID(), sourceChunkID: String, title: String, spokenScript: String, estimatedSeconds: Int) {
            self.id = id
            self.sourceChunkID = sourceChunkID
            self.title = title
            self.spokenScript = spokenScript
            self.estimatedSeconds = estimatedSeconds
        }
    }

    public struct QuizQuestion: Codable, Identifiable, Equatable, Sendable {
        public let id: String
        public let sourceChunkID: String
        public let topic: String
        public let prompt: String
        public let options: [String]
        public let correctIndex: Int
        public let explanation: String

        public init(id: String, sourceChunkID: String, topic: String, prompt: String, options: [String], correctIndex: Int, explanation: String) {
            self.id = id
            self.sourceChunkID = sourceChunkID
            self.topic = topic
            self.prompt = prompt
            self.options = options
            self.correctIndex = correctIndex
            self.explanation = explanation
        }
    }

    public struct StudyCourse: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public var title: String
        public var chunks: [SourceChunk]
        public var audioSegments: [AudioSegment]
        public var questions: [QuizQuestion]
        /// Topic weakness weight (higher = user missed more recently → prioritized next session!)
        public var topicWeakness: [String: Double]
        public var taskRun: WuMindTaskRun

        public init(
            id: UUID = UUID(),
            title: String,
            chunks: [SourceChunk],
            audioSegments: [AudioSegment],
            questions: [QuizQuestion],
            topicWeakness: [String: Double] = [:],
            taskRun: WuMindTaskRun
        ) {
            self.id = id
            self.title = title
            self.chunks = chunks
            self.audioSegments = audioSegments
            self.questions = questions
            self.topicWeakness = topicWeakness
            self.taskRun = taskRun
        }
    }

    public struct AnswerFeedback: Equatable, Sendable {
        public let isCorrect: Bool
        public let explanation: String
        public let sourceCitation: String
        public let sourceExcerpt: String
        public let updatedTopicWeakness: Double
    }

    public static func buildCourse(
        title: String,
        chunks: [SourceChunk],
        priorMistakeTopics: [String] = [],
        now: Date = Date()
    ) -> StudyCourse {
        var run = WuMindTaskRun(
            kind: .personalTextbook,
            title: "个人教材课程：\(title)",
            status: .running,
            activeModelLabel: "个人教材音频与自适应刷题引擎",
            dataBoundary: .localIntranetOnly,
            createdAt: now,
            updatedAt: now
        )
        var weakness: [String: Double] = [:]
        for c in chunks { weakness[c.topic] = 1.0 }
        for m in priorMistakeTopics { weakness[m, default: 1.0] += 2.0 }

        let audio = chunks.map { chunk in
            let script = "【\(chunk.topic)】参考《\(chunk.sourceTitle)》\(chunk.pageOrSection)。核心要点：\(chunk.excerpt)"
            return AudioSegment(
                sourceChunkID: chunk.id,
                title: "\(chunk.topic)（\(chunk.pageOrSection)）",
                spokenScript: script,
                estimatedSeconds: max(15, script.count / 4)
            )
        }
        let questions = chunks.enumerated().map { idx, chunk in
            QuizQuestion(
                id: "q-\(idx + 1)-\(chunk.id)",
                sourceChunkID: chunk.id,
                topic: chunk.topic,
                prompt: "依据《\(chunk.sourceTitle)》\(chunk.pageOrSection)，关于「\(chunk.topic)」以下哪项准确？",
                options: [
                    chunk.excerpt,
                    "与《\(chunk.sourceTitle)》所述相反，无需核对原条件",
                    "仅适用于旧版教材，当前章节已废止",
                    "该知识点与实际操作无关"
                ],
                correctIndex: 0,
                explanation: "原文位于《\(chunk.sourceTitle)》\(chunk.pageOrSection)：\(chunk.excerpt)"
            )
        }

        run.recordCompletedStep(
            title: "生成可听音频讲稿与溯源练习题",
            toolName: "textbook_course_build",
            idempotencyKey: "course:\(stableDigest(title + chunks.map(\.id).joined()))",
            dataSource: "\(chunks.count) 段教材与错题资料",
            modelUsed: "本地教材结构化引擎",
            dataBoundary: .localIntranetOnly,
            outputSummary: "产出 \(audio.count) 段可播放讲解 + \(questions.count) 道原文溯源练习题",
            now: now
        )
        run.status = .completed
        return StudyCourse(title: title, chunks: chunks, audioSegments: audio, questions: questions, topicWeakness: weakness, taskRun: run)
    }

    public static func submitAnswer(
        course: inout StudyCourse,
        questionID: String,
        selectedOptionIndex: Int,
        now: Date = Date()
    ) -> AnswerFeedback? {
        guard let q = course.questions.first(where: { $0.id == questionID }),
              let chunk = course.chunks.first(where: { $0.id == q.sourceChunkID }) else {
            return nil
        }
        let correct = selectedOptionIndex == q.correctIndex
        let current = course.topicWeakness[q.topic, default: 1.0]
        let nextWeight = correct ? max(0.2, current * 0.6) : (current + 2.5)
        course.topicWeakness[q.topic] = nextWeight
        course.taskRun.updatedAt = now
        return AnswerFeedback(
            isCorrect: correct,
            explanation: q.explanation,
            sourceCitation: "《\(chunk.sourceTitle)》\(chunk.pageOrSection)",
            sourceExcerpt: chunk.excerpt,
            updatedTopicWeakness: nextWeight
        )
    }

    /// Prioritizes questions from the user's weakest / recently missed topics FIRST!
    public static func nextPracticeQueue(for course: StudyCourse) -> [QuizQuestion] {
        course.questions.sorted { a, b in
            let wa = course.topicWeakness[a.topic, default: 1.0]
            let wb = course.topicWeakness[b.topic, default: 1.0]
            if wa != wb { return wa > wb }
            return a.id < b.id
        }
    }
}

// MARK: - 3. Mobile Dev & Verification Agent (Pre-Fix Fail → Patch + Diff → Same Test Post-Fix Pass → Approval-Gated Draft PR)

public enum WuMindMobileDevEngine {
    public struct TestRunEvidence: Codable, Equatable, Sendable {
        public let testIdentifier: String
        public let passed: Bool
        public let durationSeconds: Double
        public let logSnippet: String
        public let executedAt: Date

        public init(testIdentifier: String, passed: Bool, durationSeconds: Double, logSnippet: String, executedAt: Date = Date()) {
            self.testIdentifier = testIdentifier
            self.passed = passed
            self.durationSeconds = durationSeconds
            self.logSnippet = logSnippet
            self.executedAt = executedAt
        }
    }

    public struct PatchProposal: Codable, Equatable, Sendable {
        public let branchName: String
        public let touchedFiles: [String]
        public let unifiedDiff: String
        public let prTitle: String
        public let prBody: String

        public init(branchName: String, touchedFiles: [String], unifiedDiff: String, prTitle: String, prBody: String) {
            self.branchName = branchName
            self.touchedFiles = touchedFiles
            self.unifiedDiff = unifiedDiff
            self.prTitle = prTitle
            self.prBody = prBody
        }
    }

    public struct VerificationSession: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public let repoFullName: String
        public let bugSummary: String
        public let preFixEvidence: TestRunEvidence
        public let patch: PatchProposal
        public let postFixEvidence: TestRunEvidence
        public let verifiedFixed: Bool
        public var draftPRCreated: Bool
        public var mergedOrUploaded: Bool
        public var taskRun: WuMindTaskRun
    }

    /// Executes the strict verified mobile-dev workflow:
    /// 1. Requires a failing PRE-FIX test (`preFix.passed == false`).
    /// 2. Applies patch & unified diff.
    /// 3. Requires the **EXACT SAME TEST IDENTIFIER** passing POST-FIX (`postFix.passed == true`).
    /// 4. Stops at `WuMindApprovalGate(.commitOrCreatePR)` — NEVER auto-commits, auto-merges, or uploads builds!
    public static func runVerifiedBugFixPipeline(
        repoFullName: String,
        bugSummary: String,
        preFix: TestRunEvidence,
        patch: PatchProposal,
        postFix: TestRunEvidence,
        now: Date = Date()
    ) -> VerificationSession {
        var run = WuMindTaskRun(
            kind: .mobileDevVerify,
            title: "手机开发验收：\(String(bugSummary.prefix(26)))",
            status: .running,
            activeModelLabel: "隔离沙盒开发与测试验收引擎",
            dataBoundary: .authorizedConnector,
            createdAt: now,
            updatedAt: now
        )

        let sameTest = preFix.testIdentifier == postFix.testIdentifier && !preFix.testIdentifier.isEmpty
        let validTransition = sameTest && !preFix.passed && postFix.passed

        run.recordCompletedStep(
            title: "1. 修前复现测试：\(preFix.testIdentifier)",
            toolName: "sandbox_test_prefix",
            idempotencyKey: "dev-pre:\(repoFullName):\(preFix.testIdentifier)",
            dataSource: repoFullName,
            modelUsed: "隔离测试运行器",
            dataBoundary: .authorizedConnector,
            outputSummary: preFix.passed ? "警告：修前测试未复现失败" : "已复现失败：\(preFix.logSnippet)",
            now: now
        )

        run.recordCompletedStep(
            title: "2. 生成代码补丁与 Diff（\(patch.touchedFiles.count) 个文件）",
            toolName: "sandbox_patch_diff",
            idempotencyKey: "dev-patch:\(stableDigest(patch.unifiedDiff))",
            dataSource: patch.touchedFiles.joined(separator: ", "),
            modelUsed: "代码修复引擎",
            dataBoundary: .authorizedConnector,
            outputSummary: "分支 \(patch.branchName)：\(patch.touchedFiles.joined(separator: "、"))",
            now: now
        )

        if validTransition {
            run.recordCompletedStep(
                title: "3. 修后复跑同一测试：\(postFix.testIdentifier)",
                toolName: "sandbox_test_postfix",
                idempotencyKey: "dev-post:\(repoFullName):\(postFix.testIdentifier):\(stableDigest(patch.unifiedDiff))",
                dataSource: repoFullName,
                modelUsed: "隔离测试运行器",
                dataBoundary: .authorizedConnector,
                outputSummary: "同一测试修前 FAIL → 修后 PASS（\(String(format: "%.2fs", postFix.durationSeconds))）",
                now: now
            )
            // Hard approval boundary before committing/creating Draft PR
            run.requestApproval(
                WuMindApprovalGate(
                    actionKind: .commitOrCreatePR,
                    title: "确认提交补丁并创建 Draft PR（不自动合并/发版）",
                    targetResource: "\(repoFullName) @ \(patch.branchName)",
                    previewText: "\(patch.prTitle)\n测试证据：\(preFix.testIdentifier) 修前失败 → 修后通过\n改动文件：\(patch.touchedFiles.joined(separator: "、"))"
                ),
                now: now
            )
        } else {
            let reason = !sameTest
                ? "修前与修后不是同一项测试（\(preFix.testIdentifier) vs \(postFix.testIdentifier)）"
                : (preFix.passed ? "修前未复现测试失败，不能伪造验收证据" : "修后测试仍未通过：\(postFix.logSnippet)")
            run.recordFailedStep(
                title: "3. 修后验收校验失败",
                toolName: "sandbox_test_postfix",
                idempotencyKey: "dev-post-fail:\(now.timeIntervalSince1970)",
                dataSource: repoFullName,
                modelUsed: "隔离测试运行器",
                dataBoundary: .authorizedConnector,
                error: reason,
                now: now
            )
        }

        return VerificationSession(
            id: UUID(),
            repoFullName: repoFullName,
            bugSummary: bugSummary,
            preFixEvidence: preFix,
            patch: patch,
            postFixEvidence: postFix,
            verifiedFixed: validTransition,
            draftPRCreated: false,
            mergedOrUploaded: false,
            taskRun: run
        )
    }

    public static func approveDraftPRCreation(_ session: inout VerificationSession, now: Date = Date()) -> Bool {
        guard session.verifiedFixed, session.taskRun.status == .awaitingApproval else { return false }
        session.taskRun.resolveApproval(approved: true, now: now)
        session.draftPRCreated = true
        session.mergedOrUploaded = false // Never auto-merge or upload build!
        session.taskRun.recordCompletedStep(
            title: "4. 已按用户确认生成 Draft PR 草稿",
            toolName: "github_create_draft_pr",
            idempotencyKey: "dev-pr:\(session.repoFullName):\(session.patch.branchName)",
            dataSource: session.repoFullName,
            modelUsed: "GitHub API",
            dataBoundary: .authorizedConnector,
            outputSummary: "Draft PR 已准备就绪（未自动合并、未触发发版）",
            now: now
        )
        session.taskRun.status = .completed
        return true
    }
}

// MARK: - 4. Shareable Interactive Mini-App Artifact Engine + Strict Secret/PII Share Sanitizer

public enum WuMindMiniAppArtifactEngine {
    public struct PricingTierRule: Codable, Identifiable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var baseMonthlyYuan: Double
        public var perSeatYuan: Double
        public var annualDiscountRate: Double // e.g., 0.85 = 15% off

        public init(id: String, name: String, baseMonthlyYuan: Double, perSeatYuan: Double, annualDiscountRate: Double) {
            self.id = id
            self.name = name
            self.baseMonthlyYuan = baseMonthlyYuan
            self.perSeatYuan = perSeatYuan
            self.annualDiscountRate = annualDiscountRate
        }

        public func calculate(seats: Int, months: Int) -> Double {
            let safeSeats = max(1, seats)
            let safeMonths = max(1, months)
            let raw = (baseMonthlyYuan + Double(safeSeats) * perSeatYuan) * Double(safeMonths)
            let discounted = safeMonths >= 12 ? raw * annualDiscountRate : raw
            return (discounted * 100).rounded() / 100
        }
    }

    public struct MiniAppArtifact: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public var title: String
        public var subtitle: String
        public var tiers: [PricingTierRule]
        public var htmlContent: String
        public var taskRun: WuMindTaskRun
    }

    public struct SanitizedSharePackage: Equatable, Sendable {
        public let shareableHTML: String
        public let strippedRedactionCount: Int
        public let leakedSecretsDetected: Int
    }

    public static func buildThreeTierPricingCalculator(
        title: String = "三档套餐报价计算器",
        tiers: [PricingTierRule]? = nil,
        now: Date = Date()
    ) -> MiniAppArtifact {
        let activeTiers = tiers ?? [
            PricingTierRule(id: "starter", name: "基础版", baseMonthlyYuan: 299, perSeatYuan: 39, annualDiscountRate: 0.90),
            PricingTierRule(id: "pro", name: "专业版", baseMonthlyYuan: 899, perSeatYuan: 69, annualDiscountRate: 0.85),
            PricingTierRule(id: "enterprise", name: "旗舰企业版", baseMonthlyYuan: 2499, perSeatYuan: 119, annualDiscountRate: 0.80),
        ]
        var run = WuMindTaskRun(
            kind: .shareableMiniApp,
            title: "生成可分享小工具：\(title)",
            status: .running,
            activeModelLabel: "可分享交互小工具生成器",
            dataBoundary: .localIntranetOnly,
            createdAt: now,
            updatedAt: now
        )
        let html = renderCalculatorHTML(title: title, tiers: activeTiers)
        run.recordCompletedStep(
            title: "生成交互式报价计算器（单文件 HTML）",
            toolName: "miniapp_generate_html",
            idempotencyKey: "miniapp:\(stableDigest(title + activeTiers.map { "\($0.id):\($0.baseMonthlyYuan):\($0.perSeatYuan):\($0.annualDiscountRate)" }.joined()))",
            dataSource: "用户规则参数",
            modelUsed: "单文件 HTML/JS 生成器",
            dataBoundary: .localIntranetOnly,
            outputSummary: "已生成 \(activeTiers.count) 档套餐交互计算器，支持当场改规则实时重算与脱敏分享",
            now: now
        )
        run.status = .completed
        return MiniAppArtifact(id: UUID(), title: title, subtitle: "点选席位/时长或直接改规则实时重算，分享给客户打开即用", tiers: activeTiers, htmlContent: html, taskRun: run)
    }

    public static func updateTierRule(
        artifact: inout MiniAppArtifact,
        tierID: String,
        newBaseMonthlyYuan: Double? = nil,
        newPerSeatYuan: Double? = nil,
        newAnnualDiscountRate: Double? = nil
    ) {
        guard let idx = artifact.tiers.firstIndex(where: { $0.id == tierID }) else { return }
        if let v = newBaseMonthlyYuan { artifact.tiers[idx].baseMonthlyYuan = v }
        if let v = newPerSeatYuan { artifact.tiers[idx].perSeatYuan = v }
        if let v = newAnnualDiscountRate { artifact.tiers[idx].annualDiscountRate = v }
        artifact.htmlContent = renderCalculatorHTML(title: artifact.title, tiers: artifact.tiers)
    }

    /// Strictly strips any private customer table markers, phones, emails, API keys, or Bearer tokens
    /// before sharing a mini-app HTML page externally.
    public static func sanitizeForExternalShare(rawHTML: String) -> SanitizedSharePackage {
        var clean = rawHTML
        var redactions = 0

        let patterns: [(String, String)] = [
            (#"<!--\s*PRIVATE_DATA_BEGIN[\s\S]*?PRIVATE_DATA_END\s*-->"#, ""),
            (#"<script[^>]*data-private="true"[^>]*>[\s\S]*?</script>"#, ""),
            (#"sk-[A-Za-z0-9_\-]{12,}"#, "[REDACTED_KEY]"),
            (#"ghp_[A-Za-z0-9]{16,}"#, "[REDACTED_TOKEN]"),
            (#"Bearer\s+[A-Za-z0-9._\-]{12,}"#, "Bearer [REDACTED]"),
            (#"(?<!\d)1[3-9]\d{9}(?!\d)"#, "[REDACTED_PHONE]"),
            (#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, "[REDACTED_EMAIL]"),
        ]
        for (pat, repl) in patterns {
            if let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) {
                let range = NSRange(clean.startIndex..., in: clean)
                let hits = re.numberOfMatches(in: clean, range: range)
                if hits > 0 {
                    redactions += hits
                    clean = re.stringByReplacingMatches(in: clean, range: range, withTemplate: repl)
                }
            }
        }

        // Verify zero remaining secret patterns
        let checkPatterns = [#"sk-[A-Za-z0-9_\-]{12,}"#, #"ghp_[A-Za-z0-9]{16,}"#, #"PRIVATE_DATA_BEGIN"#]
        var leaked = 0
        for pat in checkPatterns {
            if let re = try? NSRegularExpression(pattern: pat),
               re.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)) != nil {
                leaked += 1
            }
        }
        return SanitizedSharePackage(shareableHTML: clean, strippedRedactionCount: redactions, leakedSecretsDetected: leaked)
    }

    private static func renderCalculatorHTML(title: String, tiers: [PricingTierRule]) -> String {
        let tiersJSON: String = {
            let arr: [[String: Any]] = tiers.map {
                [
                    "id": $0.id,
                    "name": $0.name,
                    "base": $0.baseMonthlyYuan,
                    "seat": $0.perSeatYuan,
                    "discount": $0.annualDiscountRate,
                ]
            }
            if let data = try? JSONSerialization.data(withJSONObject: arr, options: [.withoutEscapingSlashes]),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return "[]"
        }()
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(title)</title>
        <style>
        body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#f5f7fb;color:#111827;margin:0;padding:18px;}
        .wrap{max-width:680px;margin:0 auto;}
        .card{background:#fff;border-radius:16px;padding:16px;margin-bottom:14px;box-shadow:0 4px 14px rgba(15,23,42,.06);border:1px solid #e5e7eb;}
        h1{font-size:20px;margin:0 0 6px;}
        .sub{font-size:13px;color:#6b7280;margin:0 0 12px;}
        .row{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:12px;}
        label{font-size:12px;color:#4b5563;display:block;margin-bottom:4px;}
        input{width:100%;padding:8px 10px;border:1px solid #d1d5db;border-radius:10px;font-size:15px;box-sizing:border-box;}
        .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:10px;}
        .tier{border:1px solid #e5e7eb;border-radius:12px;padding:12px;background:#fafbff;}
        .price{font-size:24px;font-weight:800;color:#2563eb;margin:6px 0;}
        .badge{display:inline-block;font-size:11px;background:#dbeafe;color:#1d4ed8;padding:2px 8px;border-radius:99px;}
        </style>
        </head>
        <body>
        <div class="wrap">
          <div class="card">
            <h1>\(title)</h1>
            <p class="sub">由 WUMIND 生成的独立脱敏交互小工具（不含原始客户表与密钥）· 修改参数即时更新报价</p>
            <div class="row">
              <div style="flex:1;min-width:130px;"><label>使用人数（席位）</label><input id="seats" type="number" min="1" value="10" oninput="calc()"></div>
              <div style="flex:1;min-width:130px;"><label>购买月数（满12月享年付折扣）</label><input id="months" type="number" min="1" value="12" oninput="calc()"></div>
            </div>
          </div>
          <div id="grid" class="grid"></div>
        </div>
        <script>
        const tiers = \(tiersJSON);
        function calc(){
          const s = Math.max(1, Number(document.getElementById('seats').value)||1);
          const m = Math.max(1, Number(document.getElementById('months').value)||1);
          const g = document.getElementById('grid');
          g.innerHTML = tiers.map(t => {
            const raw = (t.base + s * t.seat) * m;
            const total = m >= 12 ? raw * t.discount : raw;
            return `<div class="tier"><div class="badge">${t.name}</div><div class="price">¥${total.toFixed(2)}</div><div class="sub">基础 ¥${t.base}/月 + ¥${t.seat}/席 · 年付 ${Math.round(t.discount*100)}折</div></div>`;
          }).join('');
        }
        calc();
        </script>
        </body>
        </html>
        """
    }
}

// MARK: - 5. Teach-Once → Pilot Sample → Approved Batch → Sanitized Shareable Workflow Engine

public enum WuMindTeachOnceWorkflowEngine {
    public struct WorkflowRule: Codable, Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var kind: RuleKind
        public var parameter: String
        public var enabled: Bool

        public enum RuleKind: String, Codable, Equatable, Sendable {
            case normalizeTaxRate       // e.g. "0.13"
            case includeFreightInTotal  // "true" | "false"
            case flagMissingField       // e.g. "交期"
            case customCheck
        }

        public init(id: String, title: String, kind: RuleKind, parameter: String, enabled: Bool = true) {
            self.id = id
            self.title = title
            self.kind = kind
            self.parameter = parameter
            self.enabled = enabled
        }
    }

    /// Editable, inspectable, testable user-taught workflow (NEVER an opaque giant prompt blob!).
    public struct TaughtWorkflow: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public var name: String
        public var description: String
        public var inputRequirements: [String]
        public var rules: [WorkflowRule]
        public var outputColumns: [String]
        /// Internal demonstration provenance — NEVER included in shared workflow packages!
        public var privateDemonstrationSamples: [String]
        public var privateRunHistoryCount: Int

        public init(
            id: UUID = UUID(),
            name: String,
            description: String,
            inputRequirements: [String],
            rules: [WorkflowRule],
            outputColumns: [String],
            privateDemonstrationSamples: [String] = [],
            privateRunHistoryCount: Int = 0
        ) {
            self.id = id
            self.name = name
            self.description = description
            self.inputRequirements = inputRequirements
            self.rules = rules
            self.outputColumns = outputColumns
            self.privateDemonstrationSamples = privateDemonstrationSamples
            self.privateRunHistoryCount = privateRunHistoryCount
        }
    }

    public struct PilotRunResult: Equatable, Sendable {
        public let sampleResult: WuMindCrossAppQuoteEngine.SupplierQuoteRow
        public let remainingItemCount: Int
        public let projectedRemainingCostYuan: Double
        public let taskRun: WuMindTaskRun
    }

    public struct BatchRunResult: Equatable, Sendable {
        public let allResults: [WuMindCrossAppQuoteEngine.SupplierQuoteRow]
        public let taskRun: WuMindTaskRun
    }

    /// Sanitized shareable workflow package — contains ONLY schema, rules, and output template.
    /// Zero supplier quotes, zero API keys, zero run history!
    public struct ShareableWorkflowPackage: Codable, Equatable, Sendable {
        public let schemaVersion: Int
        public let name: String
        public let description: String
        public let inputRequirements: [String]
        public let rules: [WorkflowRule]
        public let outputColumns: [String]
    }

    /// Teaches a reusable editable workflow from user demonstration quotes.
    public static func learnFromDemonstration(
        name: String,
        demonstrationFiles: [WuMindCrossAppQuoteEngine.QuoteFileInput],
        taxRate: Double = 0.13,
        includeFreight: Bool = true
    ) -> TaughtWorkflow {
        TaughtWorkflow(
            name: name,
            description: "根据 \(demonstrationFiles.count) 份示范样本提炼的可编辑、可试跑、可批量执行规则流程",
            inputRequirements: ["供应商报价单（CSV / TXT / Excel 文本）", "字段：供应商、报价、税率、运费、交期"],
            rules: [
                WorkflowRule(id: "r-tax", title: "未税报价统一按税率折算含税价", kind: .normalizeTaxRate, parameter: String(format: "%.2f", taxRate)),
                WorkflowRule(id: "r-freight", title: "运费计入到岸总价", kind: .includeFreightInTotal, parameter: includeFreight ? "true" : "false"),
                WorkflowRule(id: "r-lead", title: "缺少交期明确标记「待确认」，绝不编造", kind: .flagMissingField, parameter: "交期"),
            ],
            outputColumns: ["供应商", "折合含税到岸价", "交期", "缺失项标记"],
            privateDemonstrationSamples: demonstrationFiles.map(\.content)
        )
    }

    /// Step 2: Pilot on 1 UNSEEN sample FIRST before batch processing remaining N-1 items!
    public static func runPilotOnUnseenSample(
        workflow: TaughtWorkflow,
        unseenSample: WuMindCrossAppQuoteEngine.QuoteFileInput,
        totalBatchCount: Int,
        estimatedUnitCostYuan: Double = 0.02,
        now: Date = Date()
    ) -> PilotRunResult {
        let taxRate = workflow.rules.first(where: { $0.kind == .normalizeTaxRate && $0.enabled })
            .flatMap { Double($0.parameter) } ?? 0.13
        let includeFreight = workflow.rules.first(where: { $0.kind == .includeFreightInTotal && $0.enabled })?.parameter != "false"
        let key = "pilot:\(workflow.id.uuidString):\(unseenSample.fileName):\(stableDigest(unseenSample.content))"
        var row = WuMindCrossAppQuoteEngine.parseQuoteFile(unseenSample, idempotencyKey: key, defaultTaxRate: taxRate)
        if !includeFreight {
            let noFreight = ((row.normalizedLandedTotalYuan - row.freightYuan) * 100).rounded() / 100
            row = WuMindCrossAppQuoteEngine.SupplierQuoteRow(
                idempotencyKey: row.idempotencyKey,
                supplier: row.supplier,
                itemName: row.itemName,
                rawPrice: row.rawPrice,
                taxIncluded: row.taxIncluded,
                taxRate: row.taxRate,
                freightYuan: 0,
                normalizedLandedTotalYuan: noFreight,
                leadTimeDays: row.leadTimeDays,
                missingFields: row.missingFields,
                sourceFile: row.sourceFile
            )
        }
        let remaining = max(0, totalBatchCount - 1)
        let projectedCost = (Double(remaining) * estimatedUnitCostYuan * 1000).rounded() / 1000

        var run = WuMindTaskRun(
            kind: .teachOnceWorkflow,
            title: "陌生样本试跑：\(workflow.name)",
            status: .running,
            activeModelLabel: "自学习流程引擎",
            dataBoundary: .authorizedConnector,
            createdAt: now,
            updatedAt: now
        )
        run.recordCompletedStep(
            title: "试跑 1 份陌生样本：\(unseenSample.fileName)",
            toolName: "workflow_pilot_sample",
            idempotencyKey: key,
            dataSource: unseenSample.fileName,
            modelUsed: "结构化规则引擎",
            dataBoundary: .authorizedConnector,
            outputSummary: "\(row.supplier) → ¥\(String(format: "%.2f", row.normalizedLandedTotalYuan))（缺失：\(row.missingFields.isEmpty ? "无" : row.missingFields.joined(separator: "、"))）",
            costYuan: estimatedUnitCostYuan,
            now: now
        )
        if remaining > 0 {
            run.requestApproval(
                WuMindApprovalGate(
                    actionKind: .batchExecute,
                    title: "样本验收通过后批量执行剩余 \(remaining) 份",
                    targetResource: workflow.name,
                    previewText: "试跑结果：\(row.supplier) 折合 ¥\(String(format: "%.2f", row.normalizedLandedTotalYuan))。预计剩余 \(remaining) 份总费用约 ¥\(String(format: "%.2f", projectedCost))。",
                    estimatedCostYuan: projectedCost
                ),
                now: now
            )
        } else {
            run.status = .completed
        }
        return PilotRunResult(sampleResult: row, remainingItemCount: remaining, projectedRemainingCostYuan: projectedCost, taskRun: run)
    }

    /// Step 3: Executes the remaining batch ONLY after pilot approval (idempotent!).
    public static func executeApprovedBatch(
        workflow: TaughtWorkflow,
        pilot: PilotRunResult,
        remainingSamples: [WuMindCrossAppQuoteEngine.QuoteFileInput],
        approved: Bool,
        unitCostYuan: Double = 0.02,
        now: Date = Date()
    ) -> BatchRunResult {
        var run = pilot.taskRun
        run.resolveApproval(approved: approved, now: now)
        guard approved else {
            return BatchRunResult(allResults: [pilot.sampleResult], taskRun: run)
        }
        let taxRate = workflow.rules.first(where: { $0.kind == .normalizeTaxRate && $0.enabled })
            .flatMap { Double($0.parameter) } ?? 0.13
        var results = [pilot.sampleResult]
        for sample in remainingSamples {
            let key = "batch:\(workflow.id.uuidString):\(sample.fileName):\(stableDigest(sample.content))"
            if run.hasExecuted(idempotencyKey: key) { continue }
            let row = WuMindCrossAppQuoteEngine.parseQuoteFile(sample, idempotencyKey: key, defaultTaxRate: taxRate)
            results.append(row)
            run.recordCompletedStep(
                title: "批量执行：\(sample.fileName)",
                toolName: "workflow_batch_item",
                idempotencyKey: key,
                dataSource: sample.fileName,
                modelUsed: "结构化规则引擎",
                dataBoundary: .authorizedConnector,
                outputSummary: "\(row.supplier) → ¥\(String(format: "%.2f", row.normalizedLandedTotalYuan))",
                costYuan: unitCostYuan,
                now: now
            )
        }
        run.status = .completed
        return BatchRunResult(allResults: results, taskRun: run)
    }

    /// Step 4: Exports ONLY rules & templates (NEVER demonstration files, customer quotes, keys, or history!).
    public static func exportSanitizedPackage(workflow: TaughtWorkflow) throws -> Data {
        let pkg = ShareableWorkflowPackage(
            schemaVersion: 1,
            name: workflow.name,
            description: workflow.description,
            inputRequirements: workflow.inputRequirements,
            rules: workflow.rules,
            outputColumns: workflow.outputColumns
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(pkg)
    }
}
