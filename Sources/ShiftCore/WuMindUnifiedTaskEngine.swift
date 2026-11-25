import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - 1. Shared Unified Task, Approval, Recovery & Model-Routing Kernel

public enum WuMindTaskKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case dutyQuery
    case backgroundMonitor
    case crossAppExecution
    case deliverableRevision
    case shortDramaRevision
    case liveScreenGuide
    case personalTextbook
    case mobileDevVerify
    case shareableMiniApp
    case teachOnceWorkflow

    public var chineseTitle: String {
        switch self {
        case .dutyQuery: return "值班业务直查"
        case .backgroundMonitor: return "后台监测"
        case .crossAppExecution: return "跨应用执行"
        case .deliverableRevision: return "交付与局部修订"
        case .shortDramaRevision: return "短剧单镜局部重拍"
        case .liveScreenGuide: return "实时看屏指导"
        case .personalTextbook: return "个人教材与刷题"
        case .mobileDevVerify: return "手机开发与验收"
        case .shareableMiniApp: return "可分享小工具"
        case .teachOnceWorkflow: return "示范学习与批量流程"
        }
    }
}

public enum WuMindTaskStatus: String, Codable, Equatable, Hashable, Sendable {
    case queued
    case running
    case awaitingApproval
    case paused
    case completed
    case failed
    case cancelled

    public var chineseLabel: String {
        switch self {
        case .queued: return "排队中"
        case .running: return "执行中"
        case .awaitingApproval: return "待用户确认"
        case .paused: return "已暂停"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}

public enum WuMindDataBoundary: String, Codable, Equatable, Hashable, Sendable {
    case localIntranetOnly
    case authorizedConnector
    case publicModelAPI

    public var chineseLabel: String {
        switch self {
        case .localIntranetOnly: return "本机/内网隔离（不外发公共模型）"
        case .authorizedConnector: return "已授权连接器/文件夹"
        case .publicModelAPI: return "外部大模型 API"
        }
    }
}

public struct WuMindTaskStep: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var index: Int
    public var title: String
    public var toolName: String
    public var status: WuMindTaskStatus
    public var idempotencyKey: String
    public var dataSource: String
    public var modelUsed: String
    public var dataBoundary: WuMindDataBoundary
    public var startedAt: Date
    public var finishedAt: Date?
    public var outputSummary: String
    public var errorMessage: String?
    public var costYuan: Double

    public init(
        id: UUID = UUID(),
        index: Int,
        title: String,
        toolName: String,
        status: WuMindTaskStatus,
        idempotencyKey: String,
        dataSource: String,
        modelUsed: String,
        dataBoundary: WuMindDataBoundary,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        outputSummary: String = "",
        errorMessage: String? = nil,
        costYuan: Double = 0
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.toolName = toolName
        self.status = status
        self.idempotencyKey = idempotencyKey
        self.dataSource = dataSource
        self.modelUsed = modelUsed
        self.dataBoundary = dataBoundary
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outputSummary = outputSummary
        self.errorMessage = errorMessage
        self.costYuan = costYuan
    }
}

public struct WuMindApprovalGate: Codable, Identifiable, Equatable, Sendable {
    public enum ActionKind: String, Codable, Equatable, Sendable {
        case sendMessage = "对外发送"
        case overwriteFile = "覆盖写入文件"
        case publishExternal = "外部平台发布"
        case commitOrCreatePR = "提交代码/创建 PR"
        case batchExecute = "批量执行"
    }

    public let id: UUID
    public var actionKind: ActionKind
    public var title: String
    public var targetResource: String
    public var previewText: String
    public var estimatedCostYuan: Double
    public var approved: Bool?
    public var decidedAt: Date?

    public init(
        id: UUID = UUID(),
        actionKind: ActionKind,
        title: String,
        targetResource: String,
        previewText: String,
        estimatedCostYuan: Double = 0,
        approved: Bool? = nil,
        decidedAt: Date? = nil
    ) {
        self.id = id
        self.actionKind = actionKind
        self.title = title
        self.targetResource = targetResource
        self.previewText = previewText
        self.estimatedCostYuan = estimatedCostYuan
        self.approved = approved
        self.decidedAt = decidedAt
    }
}

/// Unified persistent task run shared by ALL WUMIND agents (Duty Query, Background Monitor,
/// Cross-App Execution, Deliverable Revision, Short-Drama Single-Shot Reshoot, Live Screen Guide,
/// Personal Textbook, Mobile Dev Verification, Shareable Mini-App, and Teach-Once Workflow).
public struct WuMindTaskRun: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var projectID: UUID?
    public var kind: WuMindTaskKind
    public var title: String
    public var status: WuMindTaskStatus
    public var steps: [WuMindTaskStep]
    public var pendingApproval: WuMindApprovalGate?
    public var completedIdempotencyKeys: Set<String>
    public var activeModelLabel: String
    public var lockedModelLabel: String?
    public var dataBoundary: WuMindDataBoundary
    public var budgetLimitYuan: Double?
    public var totalCostYuan: Double
    public var lastError: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        projectID: UUID? = nil,
        kind: WuMindTaskKind,
        title: String,
        status: WuMindTaskStatus = .queued,
        steps: [WuMindTaskStep] = [],
        pendingApproval: WuMindApprovalGate? = nil,
        completedIdempotencyKeys: Set<String> = [],
        activeModelLabel: String = "App 内置引擎",
        lockedModelLabel: String? = nil,
        dataBoundary: WuMindDataBoundary = .localIntranetOnly,
        budgetLimitYuan: Double? = nil,
        totalCostYuan: Double = 0,
        lastError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.kind = kind
        self.title = title
        self.status = status
        self.steps = steps
        self.pendingApproval = pendingApproval
        self.completedIdempotencyKeys = completedIdempotencyKeys
        self.activeModelLabel = activeModelLabel
        self.lockedModelLabel = lockedModelLabel
        self.dataBoundary = dataBoundary
        self.budgetLimitYuan = budgetLimitYuan
        self.totalCostYuan = totalCostYuan
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func hasExecuted(idempotencyKey: String) -> Bool {
        completedIdempotencyKeys.contains(idempotencyKey)
    }

    public mutating func recordCompletedStep(
        title: String,
        toolName: String,
        idempotencyKey: String,
        dataSource: String,
        modelUsed: String,
        dataBoundary: WuMindDataBoundary,
        outputSummary: String,
        costYuan: Double = 0,
        now: Date = Date()
    ) {
        guard !completedIdempotencyKeys.contains(idempotencyKey) else { return }
        completedIdempotencyKeys.insert(idempotencyKey)
        let step = WuMindTaskStep(
            index: steps.count + 1,
            title: title,
            toolName: toolName,
            status: .completed,
            idempotencyKey: idempotencyKey,
            dataSource: dataSource,
            modelUsed: modelUsed,
            dataBoundary: dataBoundary,
            startedAt: now,
            finishedAt: now,
            outputSummary: outputSummary,
            costYuan: costYuan
        )
        steps.append(step)
        totalCostYuan = ((totalCostYuan + costYuan) * 1_000_000).rounded() / 1_000_000
        updatedAt = now
    }

    public mutating func recordFailedStep(
        title: String,
        toolName: String,
        idempotencyKey: String,
        dataSource: String,
        modelUsed: String,
        dataBoundary: WuMindDataBoundary,
        error: String,
        now: Date = Date()
    ) {
        let step = WuMindTaskStep(
            index: steps.count + 1,
            title: title,
            toolName: toolName,
            status: .failed,
            idempotencyKey: idempotencyKey,
            dataSource: dataSource,
            modelUsed: modelUsed,
            dataBoundary: dataBoundary,
            startedAt: now,
            finishedAt: now,
            outputSummary: "",
            errorMessage: error
        )
        steps.append(step)
        status = .failed
        lastError = error
        updatedAt = now
    }

    public mutating func requestApproval(_ gate: WuMindApprovalGate, now: Date = Date()) {
        pendingApproval = gate
        status = .awaitingApproval
        updatedAt = now
    }

    public mutating func resolveApproval(approved: Bool, now: Date = Date()) {
        guard var gate = pendingApproval else { return }
        gate.approved = approved
        gate.decidedAt = now
        pendingApproval = gate
        status = approved ? .running : .cancelled
        updatedAt = now
    }

    /// Switches model mid-task without losing ANY completed steps or idempotency checkpoints,
    /// unless the user explicitly locked a model or restricted data to local intranet.
    public mutating func switchModel(to newModel: String, now: Date = Date()) -> Result<Void, WuMindModelRoutingError> {
        if dataBoundary == .localIntranetOnly {
            return .failure(.intranetDataBlockedFromPublicModel)
        }
        if let locked = lockedModelLabel, locked != newModel {
            return .failure(.modelLocked(locked: locked, requested: newModel))
        }
        activeModelLabel = newModel
        updatedAt = now
        return .success(())
    }
}

public enum WuMindModelRoutingError: LocalizedError, Equatable, Sendable {
    case modelLocked(locked: String, requested: String)
    case intranetDataBlockedFromPublicModel

    public var errorDescription: String? {
        switch self {
        case .modelLocked(let locked, let requested):
            return "用户已锁定模型「\(locked)」，禁止静默切换至「\(requested)」。"
        case .intranetDataBlockedFromPublicModel:
            return "当前任务属于内网隐私边界，禁止路由至外部公共大模型。"
        }
    }
}

/// Multi-model task-role router that assigns specialized models by workload role while strictly
/// obeying user model locks, budget caps, and intranet privacy boundaries.
public enum WuMindModelRouter {
    public enum TaskRole: String, Codable, Equatable, Sendable {
        case fastExtraction
        case deepAnalysis
        case videoGeneration
        case qualityVerification
        case localIntranet
    }

    public struct RoutingDecision: Equatable, Sendable {
        public let selectedModel: String
        public let dataBoundary: WuMindDataBoundary
        public let rationale: String
        public let switchedFromDefault: Bool
    }

    public static func route(
        role: TaskRole,
        lockedModel: String? = nil,
        restrictToIntranet: Bool = false,
        budgetRemainingYuan: Double? = nil
    ) -> RoutingDecision {
        if restrictToIntranet || role == .localIntranet {
            return RoutingDecision(
                selectedModel: "本机内网确定性引擎（零外发）",
                dataBoundary: .localIntranetOnly,
                rationale: "内网任务按内网权限在本地执行，不经过任何外部公共模型。",
                switchedFromDefault: false
            )
        }
        if let locked = lockedModel, !locked.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return RoutingDecision(
                selectedModel: locked,
                dataBoundary: .publicModelAPI,
                rationale: "遵守用户手动锁定模型「\(locked)」，不自动切换。",
                switchedFromDefault: false
            )
        }
        let lowBudget = (budgetRemainingYuan ?? .infinity) < 0.20
        switch role {
        case .fastExtraction:
            return RoutingDecision(
                selectedModel: "deepseek-chat",
                dataBoundary: .publicModelAPI,
                rationale: "快速结构化提取优先使用高性价比快速模型。",
                switchedFromDefault: false
            )
        case .deepAnalysis:
            let model = lowBudget ? "deepseek-chat" : "deepseek-reasoner"
            return RoutingDecision(
                selectedModel: model,
                dataBoundary: .publicModelAPI,
                rationale: lowBudget ? "受预算约束降级至 deepseek-chat 并已显式告知。" : "复杂招标与多文档分析分工给深度推理模型。",
                switchedFromDefault: lowBudget
            )
        case .videoGeneration:
            return RoutingDecision(
                selectedModel: "doubao-seedance-1-0-pro",
                dataBoundary: .publicModelAPI,
                rationale: "视频镜头生成路由至官方视频引擎。",
                switchedFromDefault: false
            )
        case .qualityVerification:
            let model = lowBudget ? "deepseek-chat" : "claude-sonnet-4-5"
            return RoutingDecision(
                selectedModel: model,
                dataBoundary: .publicModelAPI,
                rationale: lowBudget ? "预算保护模式下使用轻量复核模型。" : "成品验收分工给独立交叉复核模型。",
                switchedFromDefault: lowBudget
            )
        case .localIntranet:
            return RoutingDecision(
                selectedModel: "本机内网确定性引擎（零外发）",
                dataBoundary: .localIntranetOnly,
                rationale: "内网零外发。",
                switchedFromDefault: false
            )
        }
    }

    // MARK: - Step-Aware Tiered Routing & Candidate Benchmark Gate (Economy First -> Escalate on Complex Plan or Consecutive Failures)

    public enum WorkflowStepKind: String, Codable, Equatable, Sendable {
        case initialBuild
        case minorEdit
        case complexArchitecturePlan
        case testFailureRepair
        case localIntranet
    }

    public enum ModelTier: String, Codable, Equatable, Sendable {
        case localDeterministic
        case economy
        case strong
        case userLocked
    }

    public struct StepRoutingDecision: Equatable, Sendable {
        public let selectedModel: String
        public let tier: ModelTier
        public let dataBoundary: WuMindDataBoundary
        public let escalatedFromEconomy: Bool
        public let consecutiveTestFailures: Int
        public let rationale: String

        public init(
            selectedModel: String,
            tier: ModelTier,
            dataBoundary: WuMindDataBoundary,
            escalatedFromEconomy: Bool,
            consecutiveTestFailures: Int,
            rationale: String
        ) {
            self.selectedModel = selectedModel
            self.tier = tier
            self.dataBoundary = dataBoundary
            self.escalatedFromEconomy = escalatedFromEconomy
            self.consecutiveTestFailures = consecutiveTestFailures
            self.rationale = rationale
        }
    }

    /// Assigns economy model to initial build & routine small edits, escalating to strong model ONLY
    /// for complex architectural planning or after repeated deterministic test failures (`>= escalationThreshold`).
    public static func routeByStep(
        step: WorkflowStepKind,
        consecutiveTestFailures: Int = 0,
        escalationThreshold: Int = 2,
        economyModel: String = "deepseek-chat",
        strongModel: String = "deepseek-reasoner",
        lockedModel: String? = nil,
        restrictToIntranet: Bool = false,
        budgetRemainingYuan: Double? = nil
    ) -> StepRoutingDecision {
        if restrictToIntranet || step == .localIntranet {
            return StepRoutingDecision(
                selectedModel: "本机内网确定性引擎（零外发）",
                tier: .localDeterministic,
                dataBoundary: .localIntranetOnly,
                escalatedFromEconomy: false,
                consecutiveTestFailures: consecutiveTestFailures,
                rationale: "内网任务强制在本地确定性引擎执行，不向任何外部模型外发。"
            )
        }

        if let locked = lockedModel?.trimmingCharacters(in: .whitespacesAndNewlines), !locked.isEmpty {
            return StepRoutingDecision(
                selectedModel: locked,
                tier: .userLocked,
                dataBoundary: .publicModelAPI,
                escalatedFromEconomy: false,
                consecutiveTestFailures: consecutiveTestFailures,
                rationale: "遵守用户手动锁定模型「\(locked)」，不自动升档或切换。"
            )
        }

        let lowBudget = (budgetRemainingYuan ?? .infinity) < 0.25
        let safeThreshold = max(1, escalationThreshold)

        switch step {
        case .complexArchitecturePlan:
            if lowBudget {
                return StepRoutingDecision(
                    selectedModel: economyModel,
                    tier: .economy,
                    dataBoundary: .publicModelAPI,
                    escalatedFromEconomy: false,
                    consecutiveTestFailures: consecutiveTestFailures,
                    rationale: "复杂规划受剩余预算约束暂保留高性价比模型「\(economyModel)」，并显式提示。"
                )
            }
            return StepRoutingDecision(
                selectedModel: strongModel,
                tier: .strong,
                dataBoundary: .publicModelAPI,
                escalatedFromEconomy: false,
                consecutiveTestFailures: consecutiveTestFailures,
                rationale: "复杂架构规划直接分配强推理模型「\(strongModel)」。"
            )

        case .initialBuild, .minorEdit, .testFailureRepair:
            if consecutiveTestFailures >= safeThreshold && !lowBudget {
                return StepRoutingDecision(
                    selectedModel: strongModel,
                    tier: .strong,
                    dataBoundary: .publicModelAPI,
                    escalatedFromEconomy: true,
                    consecutiveTestFailures: consecutiveTestFailures,
                    rationale: "连续 \(consecutiveTestFailures) 次确定性跑测未通过（阈值 \(safeThreshold)），已从「\(economyModel)」升档至强模型「\(strongModel)」定向修复。"
                )
            }
            let stepLabel: String
            switch step {
            case .initialBuild: stepLabel = "初建草稿"
            case .minorEdit: stepLabel = "常规局部小改"
            case .testFailureRepair: stepLabel = "首次跑测修复"
            case .complexArchitecturePlan, .localIntranet: stepLabel = "常规步骤"
            }
            return StepRoutingDecision(
                selectedModel: economyModel,
                tier: .economy,
                dataBoundary: .publicModelAPI,
                escalatedFromEconomy: false,
                consecutiveTestFailures: consecutiveTestFailures,
                rationale: "\(stepLabel)优先使用高性价比模型「\(economyModel)」（当前连续失败 \(consecutiveTestFailures) 次，未触发升档）。"
            )

        case .localIntranet:
            return StepRoutingDecision(
                selectedModel: "本机内网确定性引擎（零外发）",
                tier: .localDeterministic,
                dataBoundary: .localIntranetOnly,
                escalatedFromEconomy: false,
                consecutiveTestFailures: consecutiveTestFailures,
                rationale: "内网零外发。"
            )
        }
    }

    public static let fable52CandidateModelID = "claude-fable-5.2"

    public enum CandidateProviderStatus: Equatable, Sendable {
        case verifiedCallable(endpointLabel: String, http200LatencyMS: Int)
        case unverifiedRequiresLiveProbe(reason: String)
        case unavailable(reason: String)

        public var isCallable: Bool {
            if case .verifiedCallable = self { return true }
            return false
        }
    }

    public struct ModelBenchmarkMetrics: Codable, Equatable, Sendable {
        public let modelID: String
        public let totalTasks: Int
        public let usableDeliverableCount: Int
        public let avgLatencySeconds: Double
        public let totalSpendYuan: Double

        public init(
            modelID: String,
            totalTasks: Int,
            usableDeliverableCount: Int,
            avgLatencySeconds: Double,
            totalSpendYuan: Double
        ) {
            self.modelID = modelID
            self.totalTasks = max(1, totalTasks)
            self.usableDeliverableCount = max(0, min(usableDeliverableCount, max(1, totalTasks)))
            self.avgLatencySeconds = max(0, avgLatencySeconds)
            self.totalSpendYuan = max(0, totalSpendYuan)
        }

        public var successRate: Double {
            Double(usableDeliverableCount) / Double(totalTasks)
        }

        /// True cost per usable deliverable (spent across all attempts divided by verified usable outputs).
        public var costPerUsableArtifactYuan: Double {
            guard usableDeliverableCount > 0 else { return .infinity }
            return totalSpendYuan / Double(usableDeliverableCount)
        }
    }

    public enum CandidatePromotionDecision: String, Codable, Equatable, Sendable {
        case keepIncumbentPendingLiveProbe
        case keepIncumbentBenchmarkNotBeaten
        case promoteCandidateAsDefault
    }

    public struct CandidateBenchmarkVerdict: Equatable, Sendable {
        public let decision: CandidatePromotionDecision
        public let recommendedDefaultModel: String
        public let incumbent: ModelBenchmarkMetrics
        public let candidate: ModelBenchmarkMetrics
        public let providerStatus: CandidateProviderStatus
        public let rationale: String
    }

    /// Evaluates a candidate model (such as `claude-fable-5.2`) strictly as a benchmark candidate:
    /// 1. Requires verified live API reachability on the user's actual endpoint/relay first.
    /// 2. Compares on the same task set using `(successRate, avgLatencySeconds, costPerUsableArtifactYuan)`.
    /// Never promotes blindly without live availability AND measured metric improvement!
    public static func evaluateCandidateForDefaultRouting(
        incumbent: ModelBenchmarkMetrics,
        candidate: ModelBenchmarkMetrics,
        providerStatus: CandidateProviderStatus,
        maxAllowedCostMultiplier: Double = 1.25
    ) -> CandidateBenchmarkVerdict {
        switch providerStatus {
        case .unverifiedRequiresLiveProbe(let reason):
            return CandidateBenchmarkVerdict(
                decision: .keepIncumbentPendingLiveProbe,
                recommendedDefaultModel: incumbent.modelID,
                incumbent: incumbent,
                candidate: candidate,
                providerStatus: providerStatus,
                rationale: "候选模型「\(candidate.modelID)」尚未在当前中转/官方接口完成实测连通探针（\(reason)），保持现用默认模型「\(incumbent.modelID)」，禁止盲目全量切换。"
            )
        case .unavailable(let reason):
            return CandidateBenchmarkVerdict(
                decision: .keepIncumbentPendingLiveProbe,
                recommendedDefaultModel: incumbent.modelID,
                incumbent: incumbent,
                candidate: candidate,
                providerStatus: providerStatus,
                rationale: "候选模型「\(candidate.modelID)」当前不可稳定调用（\(reason)），保持现用默认模型「\(incumbent.modelID)」。"
            )
        case .verifiedCallable(let endpointLabel, let latencyMS):
            guard candidate.usableDeliverableCount > 0 else {
                return CandidateBenchmarkVerdict(
                    decision: .keepIncumbentBenchmarkNotBeaten,
                    recommendedDefaultModel: incumbent.modelID,
                    incumbent: incumbent,
                    candidate: candidate,
                    providerStatus: providerStatus,
                    rationale: "候选模型「\(candidate.modelID)」同题评测可用成品数为 0，继续保留「\(incumbent.modelID)」。"
                )
            }

            let betterSuccessWithinCost =
                candidate.successRate > incumbent.successRate &&
                candidate.costPerUsableArtifactYuan <= incumbent.costPerUsableArtifactYuan * maxAllowedCostMultiplier
            let equalSuccessCheaperAndFast =
                candidate.successRate == incumbent.successRate &&
                candidate.costPerUsableArtifactYuan < incumbent.costPerUsableArtifactYuan &&
                candidate.avgLatencySeconds <= incumbent.avgLatencySeconds * 1.15

            if betterSuccessWithinCost || equalSuccessCheaperAndFast {
                return CandidateBenchmarkVerdict(
                    decision: .promoteCandidateAsDefault,
                    recommendedDefaultModel: candidate.modelID,
                    incumbent: incumbent,
                    candidate: candidate,
                    providerStatus: providerStatus,
                    rationale: "候选模型「\(candidate.modelID)」已通过「\(endpointLabel)」实测（探针 \(latencyMS)ms），同题成功率 \(Int((candidate.successRate * 100).rounded()))% vs \(Int((incumbent.successRate * 100).rounded()))%，单次可用成品成本 ¥\(String(format: "%.3f", candidate.costPerUsableArtifactYuan)) vs ¥\(String(format: "%.3f", incumbent.costPerUsableArtifactYuan))，平均耗时 \(String(format: "%.1f", candidate.avgLatencySeconds))s，满足晋升默认路由条件。"
                )
            } else {
                return CandidateBenchmarkVerdict(
                    decision: .keepIncumbentBenchmarkNotBeaten,
                    recommendedDefaultModel: incumbent.modelID,
                    incumbent: incumbent,
                    candidate: candidate,
                    providerStatus: providerStatus,
                    rationale: "候选模型「\(candidate.modelID)」虽已连通「\(endpointLabel)」，但同题评测（成功率 \(Int((candidate.successRate * 100).rounded()))% vs \(Int((incumbent.successRate * 100).rounded()))%，单次可用成品成本 ¥\(String(format: "%.3f", candidate.costPerUsableArtifactYuan)) vs ¥\(String(format: "%.3f", incumbent.costPerUsableArtifactYuan))，耗时 \(String(format: "%.1f", candidate.avgLatencySeconds))s）未综合优于现有默认模型「\(incumbent.modelID)」，保持候选不切换。"
                )
            }
        }
    }
}

// MARK: - 2. Pure-Swift Real Editable Excel (.xlsx) Workbook Exporter (ECMA-376 OpenXML)

/// Generates real, standard `.xlsx` workbooks editable in Microsoft Excel and WPS Office.
/// Pure Swift (zero third-party deps), shared across Cross-App Quote Comparison and Tender Response Matrix.
public enum WuMindXLSXExporter {
    public struct Sheet: Equatable, Sendable {
        public let name: String
        public let headers: [String]
        public let rows: [[String]]

        public init(name: String, headers: [String], rows: [[String]]) {
            self.name = name
            self.headers = headers
            self.rows = rows
        }
    }

    public static func makeWorkbook(sheets: [Sheet]) -> Data {
        let validSheets = sheets.isEmpty ? [Sheet(name: "Sheet1", headers: ["内容"], rows: [])] : sheets
        let xmlHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"

        var contentTypes = """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        """
        var wbSheetsXML = ""
        var wbRelsXML = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        wbRelsXML += "<Relationship Id=\"rIdStyles\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"

        var zipEntries: [(String, Data)] = []

        for (idx, sheet) in validSheets.enumerated() {
            let num = idx + 1
            let safeName = sanitizeSheetName(sheet.name, fallbackIndex: num)
            contentTypes += "\n  <Override PartName=\"/xl/worksheets/sheet\(num).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
            wbSheetsXML += "<sheet name=\"\(xmlEscape(safeName))\" sheetId=\"\(num)\" r:id=\"rId\(num)\"/>"
            wbRelsXML += "<Relationship Id=\"rId\(num)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(num).xml\"/>"

            let wsXML = xmlHeader + buildWorksheetXML(headers: sheet.headers, rows: sheet.rows)
            zipEntries.append(("xl/worksheets/sheet\(num).xml", Data(wsXML.utf8)))
        }

        contentTypes += "\n</Types>"
        wbRelsXML += "</Relationships>"

        let rootRels = xmlHeader + """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        let workbookXML = xmlHeader + """
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>\(wbSheetsXML)</sheets>
        </workbook>
        """
        let stylesXML = xmlHeader + """
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <fonts count="2">
            <font><sz val="11"/><name val="Arial"/></font>
            <font><b/><sz val="11"/><name val="Arial"/></font>
          </fonts>
          <fills count="2">
            <fill><patternFill patternType="none"/></fill>
            <fill><patternFill patternType="gray125"/></fill>
          </fills>
          <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
          <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
          <cellXfs count="2">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
            <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
          </cellXfs>
        </styleSheet>
        """

        var allEntries: [(String, Data)] = [
            ("[Content_Types].xml", Data((xmlHeader + contentTypes).utf8)),
            ("_rels/.rels", Data(rootRels.utf8)),
            ("xl/workbook.xml", Data(workbookXML.utf8)),
            ("xl/_rels/workbook.xml.rels", Data((xmlHeader + wbRelsXML).utf8)),
            ("xl/styles.xml", Data(stylesXML.utf8)),
        ]
        allEntries.append(contentsOf: zipEntries)
        return buildStoredZIP(allEntries)
    }

    private static func buildWorksheetXML(headers: [String], rows: [[String]]) -> String {
        var allRows: [[String]] = []
        if !headers.isEmpty { allRows.append(headers) }
        allRows.append(contentsOf: rows)
        var body = "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>"
        for (rIdx, cols) in allRows.enumerated() {
            let rowNumber = rIdx + 1
            let isHeader = rIdx == 0 && !headers.isEmpty
            body += "<row r=\"\(rowNumber)\">"
            for (cIdx, val) in cols.enumerated() {
                let ref = "\(columnLetter(cIdx))\(rowNumber)"
                let styleAttr = isHeader ? " s=\"1\"" : ""
                let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                if !isHeader, let num = Double(trimmed), num.isFinite, !trimmed.isEmpty,
                   trimmed.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil {
                    body += "<c r=\"\(ref)\"\(styleAttr)><v>\(trimmed)</v></c>"
                } else {
                    body += "<c r=\"\(ref)\" t=\"inlineStr\"\(styleAttr)><is><t xml:space=\"preserve\">\(xmlEscape(val))</t></is></c>"
                }
            }
            body += "</row>"
        }
        body += "</sheetData></worksheet>"
        return body
    }

    private static func columnLetter(_ index: Int) -> String {
        var n = index
        var out = ""
        repeat {
            let rem = n % 26
            out = String(UnicodeScalar(65 + rem)!) + out
            n = (n / 26) - 1
        } while n >= 0
        return out
    }

    private static func sanitizeSheetName(_ raw: String, fallbackIndex: Int) -> String {
        let invalid = CharacterSet(charactersIn: "[]:*?/\\")
        let cleaned = raw.unicodeScalars.filter { !invalid.contains($0) }.map(String.init).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(cleaned.prefix(31))
        return prefix.isEmpty ? "Sheet\(fallbackIndex)" : prefix
    }

    private static func xmlEscape(_ text: String) -> String {
        let legal = text.unicodeScalars.filter { scalar in
            let n = scalar.value
            return [9, 10, 13].contains(n) || (32...0xD7FF).contains(n)
                || (0xE000...0xFFFD).contains(n) || (0x10000...0x10FFFF).contains(n)
        }
        return String(String.UnicodeScalarView(legal))
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func buildStoredZIP(_ entries: [(String, Data)]) -> Data {
        var archive = Data()
        var central = Data()
        for (name, content) in entries {
            let nameData = Data(name.utf8)
            let crc = crc32(content)
            let offset = UInt32(archive.count)
            archive.append(le32(0x04034b50))
            archive.append(le16(20))
            archive.append(le16(0x0800))
            archive.append(le16(0))
            archive.append(le16(0))
            archive.append(le16(0))
            archive.append(le32(crc))
            archive.append(le32(UInt32(content.count)))
            archive.append(le32(UInt32(content.count)))
            archive.append(le16(UInt16(nameData.count)))
            archive.append(le16(0))
            archive.append(nameData)
            archive.append(content)

            central.append(le32(0x02014b50))
            central.append(le16(20))
            central.append(le16(20))
            central.append(le16(0x0800))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le32(crc))
            central.append(le32(UInt32(content.count)))
            central.append(le32(UInt32(content.count)))
            central.append(le16(UInt16(nameData.count)))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le32(0))
            central.append(le32(offset))
            central.append(nameData)
        }
        let cdOffset = UInt32(archive.count)
        archive.append(central)
        archive.append(le32(0x06054b50))
        archive.append(le16(0))
        archive.append(le16(0))
        archive.append(le16(UInt16(entries.count)))
        archive.append(le16(UInt16(entries.count)))
        archive.append(le32(UInt32(central.count)))
        archive.append(le32(cdOffset))
        archive.append(le16(0))
        return archive
    }

    private static func le16(_ v: UInt16) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)])
    }

    private static func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : (crc >> 1)
            }
        }
        return ~crc
    }
}

// MARK: - 3. Project-Centric Artifact Graph & Surgical Partial-Revision Engine

/// First-class Project Document Graph: clauses, editable chapters, and Excel response matrix rows
/// are persisted independently with explicit dependency edges and manual-edit protection.
public struct WuMindProjectArtifactGraph: Codable, Identifiable, Equatable, Sendable {
    public struct Clause: Codable, Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var text: String
        public var sourceLocation: String
        public var revision: Int

        public init(id: String, title: String, text: String, sourceLocation: String, revision: Int = 1) {
            self.id = id
            self.title = title
            self.text = text
            self.sourceLocation = sourceLocation
            self.revision = revision
        }
    }

    public struct Chapter: Codable, Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var body: String
        public var linkedClauseIDs: [String]
        public var humanEdited: Bool
        public var revision: Int
        public var lastUpdatedReason: String

        public init(
            id: String,
            title: String,
            body: String,
            linkedClauseIDs: [String],
            humanEdited: Bool = false,
            revision: Int = 1,
            lastUpdatedReason: String = "初稿生成"
        ) {
            self.id = id
            self.title = title
            self.body = body
            self.linkedClauseIDs = linkedClauseIDs
            self.humanEdited = humanEdited
            self.revision = revision
            self.lastUpdatedReason = lastUpdatedReason
        }
    }

    public struct MatrixRow: Codable, Identifiable, Equatable, Sendable {
        public var id: String
        public var clauseID: String
        public var requirement: String
        public var response: String
        public var status: String
        public var sourceLocation: String
        public var humanEdited: Bool
        public var revision: Int

        public init(
            id: String,
            clauseID: String,
            requirement: String,
            response: String,
            status: String,
            sourceLocation: String,
            humanEdited: Bool = false,
            revision: Int = 1
        ) {
            self.id = id
            self.clauseID = clauseID
            self.requirement = requirement
            self.response = response
            self.status = status
            self.sourceLocation = sourceLocation
            self.humanEdited = humanEdited
            self.revision = revision
        }
    }

    public struct ManualConflictProposal: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public var targetChapterID: String
        public var targetTitle: String
        public var clauseID: String
        public var preservedHumanBody: String
        public var proposedPatchNote: String
        public var resolved: Bool

        public init(
            id: UUID = UUID(),
            targetChapterID: String,
            targetTitle: String,
            clauseID: String,
            preservedHumanBody: String,
            proposedPatchNote: String,
            resolved: Bool = false
        ) {
            self.id = id
            self.targetChapterID = targetChapterID
            self.targetTitle = targetTitle
            self.clauseID = clauseID
            self.preservedHumanBody = preservedHumanBody
            self.proposedPatchNote = proposedPatchNote
            self.resolved = resolved
        }
    }

    public struct RevisionAudit: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public var at: Date
        public var reason: String
        public var changedClauseIDs: [String]
        public var updatedChapterIDs: [String]
        public var preservedHumanChapterIDs: [String]
        public var untouchedChapterIDs: [String]
        public var updatedMatrixRowIDs: [String]

        public init(
            id: UUID = UUID(),
            at: Date = Date(),
            reason: String,
            changedClauseIDs: [String],
            updatedChapterIDs: [String],
            preservedHumanChapterIDs: [String],
            untouchedChapterIDs: [String],
            updatedMatrixRowIDs: [String]
        ) {
            self.id = id
            self.at = at
            self.reason = reason
            self.changedClauseIDs = changedClauseIDs
            self.updatedChapterIDs = updatedChapterIDs
            self.preservedHumanChapterIDs = preservedHumanChapterIDs
            self.untouchedChapterIDs = untouchedChapterIDs
            self.updatedMatrixRowIDs = updatedMatrixRowIDs
        }
    }

    public let id: UUID
    public var title: String
    public var clauses: [Clause]
    public var chapters: [Chapter]
    public var matrixRows: [MatrixRow]
    public var conflictProposals: [ManualConflictProposal]
    public var revisionHistory: [RevisionAudit]

    public init(
        id: UUID = UUID(),
        title: String,
        clauses: [Clause],
        chapters: [Chapter],
        matrixRows: [MatrixRow],
        conflictProposals: [ManualConflictProposal] = [],
        revisionHistory: [RevisionAudit] = []
    ) {
        self.id = id
        self.title = title
        self.clauses = clauses
        self.chapters = chapters
        self.matrixRows = matrixRows
        self.conflictProposals = conflictProposals
        self.revisionHistory = revisionHistory
    }
}

public enum WuMindProjectRevisionEngine {
    public struct ClauseAmendment: Equatable, Sendable {
        public let clauseID: String
        public let newText: String
        public let newSourceLocation: String
        public let updatedResponseSummary: String
        public let reason: String

        public init(
            clauseID: String,
            newText: String,
            newSourceLocation: String,
            updatedResponseSummary: String,
            reason: String
        ) {
            self.clauseID = clauseID
            self.newText = newText
            self.newSourceLocation = newSourceLocation
            self.updatedResponseSummary = updatedResponseSummary
            self.reason = reason
        }
    }

    public struct PartialRevisionOutcome: Equatable, Sendable {
        public let graph: WuMindProjectArtifactGraph
        public let audit: WuMindProjectArtifactGraph.RevisionAudit
        public let taskRun: WuMindTaskRun
    }

    /// Surgically revises ONLY the chapters and Excel matrix rows linked to `amendments`.
    /// Untouched chapters keep exact text & revision; human-edited chapters are strictly preserved
    /// and receive a non-destructive `ManualConflictProposal` instead of silent overwrite.
    public static func applyPartialAmendments(
        graph: WuMindProjectArtifactGraph,
        amendments: [ClauseAmendment],
        taskRun existingRun: WuMindTaskRun? = nil,
        now: Date = Date()
    ) -> PartialRevisionOutcome {
        var updated = graph
        var run = existingRun ?? WuMindTaskRun(
            projectID: graph.id,
            kind: .deliverableRevision,
            title: "局部修订：\(graph.title)",
            status: .running,
            activeModelLabel: "项目依赖图局部修订引擎",
            dataBoundary: .localIntranetOnly,
            createdAt: now,
            updatedAt: now
        )

        var changedClauseIDs: [String] = []
        var updatedChapterIDs: [String] = []
        var preservedHumanChapterIDs: [String] = []
        var updatedMatrixRowIDs: [String] = []

        for amend in amendments {
            let idemKey = "rev:\(graph.id.uuidString):\(amend.clauseID):\(stableDigest(amend.newText))"
            if run.hasExecuted(idempotencyKey: idemKey) {
                continue
            }
            if let cIdx = updated.clauses.firstIndex(where: { $0.id == amend.clauseID }) {
                updated.clauses[cIdx].text = amend.newText
                updated.clauses[cIdx].sourceLocation = amend.newSourceLocation
                updated.clauses[cIdx].revision += 1
                changedClauseIDs.append(amend.clauseID)
            }

            for idx in updated.chapters.indices {
                guard updated.chapters[idx].linkedClauseIDs.contains(amend.clauseID) else { continue }
                if updated.chapters[idx].humanEdited {
                    // Preserve user's manual edits strictly!
                    preservedHumanChapterIDs.append(updated.chapters[idx].id)
                    updated.conflictProposals.append(
                        WuMindProjectArtifactGraph.ManualConflictProposal(
                            targetChapterID: updated.chapters[idx].id,
                            targetTitle: updated.chapters[idx].title,
                            clauseID: amend.clauseID,
                            preservedHumanBody: updated.chapters[idx].body,
                            proposedPatchNote: "关联条款[\(amend.clauseID)]变更（\(amend.reason)）：建议补充「\(amend.updatedResponseSummary)」（来源：\(amend.newSourceLocation)）"
                        )
                    )
                } else {
                    updated.chapters[idx].body = updated.chapters[idx].body
                        + "\n\n【更正同步 · \(amend.clauseID)】\(amend.updatedResponseSummary)（出处：\(amend.newSourceLocation)）"
                    updated.chapters[idx].revision += 1
                    updated.chapters[idx].lastUpdatedReason = amend.reason
                    updatedChapterIDs.append(updated.chapters[idx].id)
                }
            }

            for idx in updated.matrixRows.indices where updated.matrixRows[idx].clauseID == amend.clauseID {
                if !updated.matrixRows[idx].humanEdited {
                    updated.matrixRows[idx].requirement = amend.newText
                    updated.matrixRows[idx].response = amend.updatedResponseSummary
                    updated.matrixRows[idx].status = "已按更正更新"
                    updated.matrixRows[idx].sourceLocation = amend.newSourceLocation
                    updated.matrixRows[idx].revision += 1
                    updatedMatrixRowIDs.append(updated.matrixRows[idx].id)
                }
            }

            run.recordCompletedStep(
                title: "局部更新条款 \(amend.clauseID)",
                toolName: "project_partial_revision",
                idempotencyKey: idemKey,
                dataSource: amend.newSourceLocation,
                modelUsed: run.activeModelLabel,
                dataBoundary: .localIntranetOnly,
                outputSummary: "更新章节 \(updatedChapterIDs.count) 个、保护人工修改 \(preservedHumanChapterIDs.count) 个、更新矩阵行 \(updatedMatrixRowIDs.count) 条",
                now: now
            )
        }

        let affectedSet = Set(updatedChapterIDs + preservedHumanChapterIDs)
        let untouchedChapterIDs = updated.chapters.map(\.id).filter { !affectedSet.contains($0) }
        let audit = WuMindProjectArtifactGraph.RevisionAudit(
            at: now,
            reason: amendments.map(\.reason).joined(separator: "；"),
            changedClauseIDs: changedClauseIDs,
            updatedChapterIDs: updatedChapterIDs,
            preservedHumanChapterIDs: preservedHumanChapterIDs,
            untouchedChapterIDs: untouchedChapterIDs,
            updatedMatrixRowIDs: updatedMatrixRowIDs
        )
        updated.revisionHistory.append(audit)
        run.status = updated.conflictProposals.contains(where: { !$0.resolved }) ? .awaitingApproval : .completed
        if run.status == .awaitingApproval {
            run.requestApproval(
                WuMindApprovalGate(
                    actionKind: .overwriteFile,
                    title: "人工编辑章节冲突待确认",
                    targetResource: preservedHumanChapterIDs.joined(separator: "、"),
                    previewText: "检测到 \(preservedHumanChapterIDs.count) 个已人工修改章节受更正公告影响，已原样保留人工内容并生成修订建议。"
                ),
                now: now
            )
        }

        return PartialRevisionOutcome(graph: updated, audit: audit, taskRun: run)
    }

    /// Exports BOTH a real editable `.docx` draft AND a real editable `.xlsx` response matrix
    /// with verifiable clause source citations.
    public static func exportDeliverables(graph: WuMindProjectArtifactGraph) throws -> (docxData: Data, xlsxData: Data) {
        let sections = graph.chapters.map { ch -> TenderDOCXExporter.Section in
            let sources = ch.linkedClauseIDs.compactMap { cid in
                graph.clauses.first(where: { $0.id == cid }).map { "[\($0.id)] \($0.sourceLocation)" }
            }
            let suffix = sources.isEmpty ? "" : "\n（出处追溯：\(sources.joined(separator: "；"))）"
            return TenderDOCXExporter.Section(title: ch.title, body: ch.body + suffix)
        }
        let matrix = graph.matrixRows.map {
            TenderDOCXExporter.MatrixRow(
                requirement: $0.requirement,
                response: $0.response,
                status: $0.status,
                source: "[\($0.clauseID)] \($0.sourceLocation)"
            )
        }
        let reviewNotes = graph.conflictProposals.filter { !$0.resolved }.map {
            "人工修改保护章节「\($0.targetTitle)」：\($0.proposedPatchNote)"
        }
        let docx = try TenderDOCXExporter.make(
            title: graph.title,
            sections: sections,
            reviewNotes: reviewNotes,
            matrix: matrix
        )
        let xlsx = WuMindXLSXExporter.makeWorkbook(sheets: [
            WuMindXLSXExporter.Sheet(
                name: "响应矩阵",
                headers: ["条款编号", "招标要求", "响应内容", "核对状态", "原文出处", "修订版本"],
                rows: graph.matrixRows.map {
                    [$0.clauseID, $0.requirement, $0.response, $0.status, $0.sourceLocation, "v\($0.revision)"]
                }
            ),
            WuMindXLSXExporter.Sheet(
                name: "条款原文库",
                headers: ["条款编号", "标题", "原文内容", "出处位置", "版本"],
                rows: graph.clauses.map {
                    [$0.id, $0.title, $0.text, $0.sourceLocation, "v\($0.revision)"]
                }
            ),
        ])
        return (docx, xlsx)
    }

    /// Wires the exact same partial-revision task audit kernel into Short-Drama Studio single-shot reshoot.
    public static func auditShortDramaSingleShotReshoot(
        before: WuMindShortDramaProject,
        after: WuMindShortDramaProject,
        targetShotID: UUID,
        now: Date = Date()
    ) -> (preservedOtherShots: Bool, preservedSubtitlesAndAudio: Bool, taskRun: WuMindTaskRun) {
        let otherBefore = before.shots.filter { $0.id != targetShotID }
        let otherAfter = after.shots.filter { $0.id != targetShotID }
        let preservedOthers = otherBefore == otherAfter
        let cuesBefore = WuMindShortDramaEngine.subtitleCues(for: before)
        let cuesAfter = WuMindShortDramaEngine.subtitleCues(for: after)
        let preservedTracks = cuesBefore == cuesAfter
            && before.globalSubtitlesEnabled == after.globalSubtitlesEnabled
            && before.globalVoiceoverEnabled == after.globalVoiceoverEnabled
        let targetChanged = before.shots.first(where: { $0.id == targetShotID }) != after.shots.first(where: { $0.id == targetShotID })

        var run = WuMindTaskRun(
            projectID: after.id,
            kind: .shortDramaRevision,
            title: "短剧单镜局部重拍：\(after.title)",
            status: .running,
            activeModelLabel: "局部修订依赖引擎",
            dataBoundary: .localIntranetOnly,
            createdAt: now,
            updatedAt: now
        )
        if preservedOthers && preservedTracks && targetChanged {
            run.recordCompletedStep(
                title: "校验单镜局部修订边界",
                toolName: "short_drama_partial_reshoot_verify",
                idempotencyKey: "drama:\(after.id.uuidString):\(targetShotID.uuidString):\(after.shots.first(where: { $0.id == targetShotID })?.takes.count ?? 0)",
                dataSource: "短剧时间线工程",
                modelUsed: "本地依赖校验器",
                dataBoundary: .localIntranetOnly,
                outputSummary: "仅目标镜头更新，其余 \(otherAfter.count) 镜、\(cuesAfter.count) 条字幕时间轴与全局音轨保持字节级未变",
                now: now
            )
            run.status = .completed
        } else {
            run.recordFailedStep(
                title: "校验单镜局部修订边界",
                toolName: "short_drama_partial_reshoot_verify",
                idempotencyKey: "drama-fail:\(targetShotID.uuidString)",
                dataSource: "短剧时间线工程",
                modelUsed: "本地依赖校验器",
                dataBoundary: .localIntranetOnly,
                error: "检测到非目标镜头或独立字幕/音轨发生意外变更",
                now: now
            )
        }
        return (preservedOthers, preservedTracks, run)
    }
}

// MARK: - 4. Agent 1: Background Monitor Engine (Scheduled + Event Triggered + Dedup + Chained Revision)

public enum WuMindBackgroundMonitorEngine {
    public struct FieldDiff: Codable, Equatable, Sendable {
        public let field: String
        public let oldValue: String
        public let newValue: String

        public init(field: String, oldValue: String, newValue: String) {
            self.field = field
            self.oldValue = oldValue
            self.newValue = newValue
        }
    }

    public struct ExecutionLogEntry: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public var executedAt: Date
        public var trigger: String // "scheduled" | "event" | "manual"
        public var outcome: String // "noChange" | "changeDetected" | "paused" | "failed"
        public var contentHash: String?
        public var notificationDispatched: Bool
        public var summary: String
        public var errorMessage: String?

        public init(
            id: UUID = UUID(),
            executedAt: Date = Date(),
            trigger: String,
            outcome: String,
            contentHash: String? = nil,
            notificationDispatched: Bool = false,
            summary: String,
            errorMessage: String? = nil
        ) {
            self.id = id
            self.executedAt = executedAt
            self.trigger = trigger
            self.outcome = outcome
            self.contentHash = contentHash
            self.notificationDispatched = notificationDispatched
            self.summary = summary
            self.errorMessage = errorMessage
        }
    }

    public struct MonitorSubscription: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public var projectID: UUID?
        public var title: String
        public var targetURL: String
        public var intervalMinutes: Int
        public var eventTriggerEnabled: Bool
        public var paused: Bool
        public var seenContentHashes: Set<String>
        public var lastSnapshotText: String
        public var lastFields: [String: String]
        public var executionLog: [ExecutionLogEntry]

        public init(
            id: UUID = UUID(),
            projectID: UUID? = nil,
            title: String,
            targetURL: String,
            intervalMinutes: Int = 60,
            eventTriggerEnabled: Bool = true,
            paused: Bool = false,
            seenContentHashes: Set<String> = [],
            lastSnapshotText: String = "",
            lastFields: [String: String] = [:],
            executionLog: [ExecutionLogEntry] = []
        ) {
            self.id = id
            self.projectID = projectID
            self.title = title
            self.targetURL = targetURL
            self.intervalMinutes = intervalMinutes
            self.eventTriggerEnabled = eventTriggerEnabled
            self.paused = paused
            self.seenContentHashes = seenContentHashes
            self.lastSnapshotText = lastSnapshotText
            self.lastFields = lastFields
            self.executionLog = executionLog
        }
    }

    public struct MonitorNotification: Codable, Equatable, Sendable {
        public let id: UUID
        public let subscriptionID: UUID
        public let title: String
        public let sourceURL: String
        public let originalExcerpt: String
        public let diffs: [FieldDiff]
        public let contentHash: String
        public let createdAt: Date
    }

    public struct PollOutcome: Equatable, Sendable {
        public let subscription: MonitorSubscription
        public let notification: MonitorNotification?
        public let taskRun: WuMindTaskRun
    }

    public typealias PageFetcher = @Sendable (String) async throws -> String

    /// Polls a public notice URL (scheduled or event-triggered), deduplicates by content hash,
    /// extracts structured old→new diffs, and emits AT MOST ONE notification per unique notice revision.
    public static func poll(
        subscription: MonitorSubscription,
        trigger: String = "scheduled",
        fetcher: PageFetcher,
        now: Date = Date()
    ) async -> PollOutcome {
        var sub = subscription
        var run = WuMindTaskRun(
            projectID: sub.projectID,
            kind: .backgroundMonitor,
            title: "后台监测：\(sub.title)",
            status: .running,
            activeModelLabel: "后台监测抓取与差异引擎",
            dataBoundary: .authorizedConnector,
            createdAt: now,
            updatedAt: now
        )

        if sub.paused {
            sub.executionLog.append(ExecutionLogEntry(executedAt: now, trigger: trigger, outcome: "paused", summary: "监测已暂停，未抓取。"))
            run.status = .paused
            return PollOutcome(subscription: sub, notification: nil, taskRun: run)
        }

        do {
            let rawText = try await fetcher(sub.targetURL)
            let normalized = normalizeNoticeText(rawText)
            guard !normalized.isEmpty else {
                let err = "抓取内容为空"
                sub.executionLog.append(ExecutionLogEntry(executedAt: now, trigger: trigger, outcome: "failed", summary: err, errorMessage: err))
                run.recordFailedStep(title: "抓取监测目标", toolName: "monitor_fetch", idempotencyKey: "poll-empty:\(now.timeIntervalSince1970)", dataSource: sub.targetURL, modelUsed: "HTTP 抓取器", dataBoundary: .authorizedConnector, error: err, now: now)
                return PollOutcome(subscription: sub, notification: nil, taskRun: run)
            }

            let hash = stableDigest(normalized)
            if sub.seenContentHashes.contains(hash) {
                sub.executionLog.append(ExecutionLogEntry(executedAt: now, trigger: trigger, outcome: "noChange", contentHash: hash, notificationDispatched: false, summary: "内容哈希未变化，已去重免打扰。"))
                run.recordCompletedStep(title: "比对内容指纹（无变化）", toolName: "monitor_hash_dedup", idempotencyKey: "dedup:\(hash)", dataSource: sub.targetURL, modelUsed: "SHA-256 指纹比对", dataBoundary: .localIntranetOnly, outputSummary: "重复公告已过滤，不发重复通知", now: now)
                run.status = .completed
                return PollOutcome(subscription: sub, notification: nil, taskRun: run)
            }

            let newFields = extractNoticeFields(normalized)
            var diffs: [FieldDiff] = []
            for key in Set(sub.lastFields.keys).union(newFields.keys).sorted() {
                let oldV = sub.lastFields[key] ?? "（此前未标注）"
                let newV = newFields[key] ?? "（已移除）"
                if oldV != newV {
                    diffs.append(FieldDiff(field: key, oldValue: oldV, newValue: newV))
                }
            }
            if diffs.isEmpty && !sub.lastSnapshotText.isEmpty {
                diffs.append(FieldDiff(field: "正文变更", oldValue: String(sub.lastSnapshotText.prefix(80)), newValue: String(normalized.prefix(80))))
            }

            sub.seenContentHashes.insert(hash)
            sub.lastSnapshotText = normalized
            sub.lastFields = newFields

            let notif = MonitorNotification(
                id: UUID(),
                subscriptionID: sub.id,
                title: "【更正/新公告】\(sub.title)",
                sourceURL: sub.targetURL,
                originalExcerpt: String(normalized.prefix(320)),
                diffs: diffs,
                contentHash: hash,
                createdAt: now
            )
            let diffSummary = diffs.map { "\($0.field)：\($0.oldValue) → \($0.newValue)" }.joined(separator: "；")
            sub.executionLog.append(ExecutionLogEntry(
                executedAt: now,
                trigger: trigger,
                outcome: "changeDetected",
                contentHash: hash,
                notificationDispatched: true,
                summary: diffSummary.isEmpty ? "发现新公告" : diffSummary
            ))
            run.recordCompletedStep(
                title: "捕获公告变化并生成新旧差异",
                toolName: "monitor_diff_notify",
                idempotencyKey: "notify:\(sub.id.uuidString):\(hash)",
                dataSource: sub.targetURL,
                modelUsed: "结构化公告差异引擎",
                dataBoundary: .authorizedConnector,
                outputSummary: diffSummary.isEmpty ? "发现首次公告并通知" : diffSummary,
                now: now
            )
            run.status = .completed
            return PollOutcome(subscription: sub, notification: notif, taskRun: run)
        } catch {
            let err = error.localizedDescription
            sub.executionLog.append(ExecutionLogEntry(executedAt: now, trigger: trigger, outcome: "failed", summary: "抓取失败", errorMessage: err))
            run.recordFailedStep(title: "抓取监测目标", toolName: "monitor_fetch", idempotencyKey: "poll-err:\(now.timeIntervalSince1970)", dataSource: sub.targetURL, modelUsed: "HTTP 抓取器", dataBoundary: .authorizedConnector, error: err, now: now)
            return PollOutcome(subscription: sub, notification: nil, taskRun: run)
        }
    }

    /// Chained End-to-End Pipeline:
    /// Background Monitor catches amendment → locates affected clause(s) → partially updates ONLY affected
    /// Word chapters & Excel matrix rows (preserving manual edits) → exports updated `.docx` + `.xlsx` → notifies user!
    public static func runChainedMonitorAndPartialRevision(
        subscription: MonitorSubscription,
        graph: WuMindProjectArtifactGraph,
        fieldToClauseID: [String: String],
        trigger: String = "scheduled",
        fetcher: PageFetcher,
        now: Date = Date()
    ) async throws -> (poll: PollOutcome, revision: WuMindProjectRevisionEngine.PartialRevisionOutcome?, docxData: Data?, xlsxData: Data?) {
        let pollOutcome = await poll(subscription: subscription, trigger: trigger, fetcher: fetcher, now: now)
        guard let notif = pollOutcome.notification else {
            return (pollOutcome, nil, nil, nil)
        }
        var amendments: [WuMindProjectRevisionEngine.ClauseAmendment] = []
        for diff in notif.diffs {
            if let clauseID = fieldToClauseID[diff.field] {
                amendments.append(
                    WuMindProjectRevisionEngine.ClauseAmendment(
                        clauseID: clauseID,
                        newText: "\(diff.field)：\(diff.newValue)",
                        newSourceLocation: "\(notif.sourceURL)（更正公告哈希 \(String(notif.contentHash.prefix(8)))）",
                        updatedResponseSummary: "已同步更正公告：\(diff.field)由「\(diff.oldValue)」变更为「\(diff.newValue)」",
                        reason: "后台监测捕获 \(diff.field) 变更"
                    )
                )
            }
        }
        guard !amendments.isEmpty else {
            return (pollOutcome, nil, nil, nil)
        }
        let revOutcome = WuMindProjectRevisionEngine.applyPartialAmendments(
            graph: graph,
            amendments: amendments,
            taskRun: pollOutcome.taskRun,
            now: now
        )
        let deliverables = try WuMindProjectRevisionEngine.exportDeliverables(graph: revOutcome.graph)
        return (pollOutcome, revOutcome, deliverables.docxData, deliverables.xlsxData)
    }

    public static func extractNoticeFields(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        let patterns: [(String, String)] = [
            ("截标时间", #"(?:截标时间|投标截止时间|递交截止时间)\s*[：:]\s*([^\n；;。]+)"#),
            ("开标时间", #"开标时间\s*[：:]\s*([^\n；;。]+)"#),
            ("预算金额", #"(?:预算金额|最高限价)\s*[：:]\s*([^\n；;。]+)"#),
            ("更正事项", #"(?:更正事项|变更内容)\s*[：:]\s*([^\n。]+)"#),
            ("资质要求", #"(?:资质要求|资格要求)\s*[：:]\s*([^\n。]+)"#),
        ]
        for (label, pat) in patterns {
            if let re = try? NSRegularExpression(pattern: pat),
               let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               m.numberOfRanges >= 2,
               let r = Range(m.range(at: 1), in: text) {
                fields[label] = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return fields
    }

    private static func normalizeNoticeText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

// MARK: - 5. Agent 2: Cross-App Execution Engine (Authorized Folder Quotes → Real .xlsx Write + Approval + Idempotent Resume)

public enum WuMindCrossAppQuoteEngine {
    public struct QuoteFileInput: Codable, Equatable, Sendable {
        public let fileName: String
        public let content: String

        public init(fileName: String, content: String) {
            self.fileName = fileName
            self.content = content
        }
    }

    public struct SupplierQuoteRow: Codable, Identifiable, Equatable, Sendable {
        public var id: String { idempotencyKey }
        public let idempotencyKey: String
        public let supplier: String
        public let itemName: String
        public let rawPrice: Double
        public let taxIncluded: Bool
        public let taxRate: Double
        public let freightYuan: Double
        public let normalizedLandedTotalYuan: Double
        public let leadTimeDays: Int?
        public let missingFields: [String]
        public let sourceFile: String
    }

    public struct ComparisonExecutionState: Codable, Equatable, Sendable {
        public var taskRun: WuMindTaskRun
        public var extractedRows: [SupplierQuoteRow]
        public var targetWorkbookPath: String
        public var workbookWritten: Bool
        public var recommendationPreview: String
        public var sendDispatched: Bool
    }

    /// Parses supplier quote files from an authorized folder (supports CSV/key-value text),
    /// normalizes tax-inclusive landed cost, flags missing delivery lead times as `待确认`,
    /// supports mid-run crash resume + strict idempotency (retrying NEVER writes duplicate rows),
    /// and gates overwriting an existing target file or external send behind `WuMindApprovalGate`.
    public static func executeFolderQuoteComparison(
        files: [QuoteFileInput],
        targetWorkbookURL: URL,
        existingState: ComparisonExecutionState? = nil,
        defaultTaxRate: Double = 0.13,
        approvalGrantedForOverwrite: Bool = false,
        failAfterProcessedCount: Int? = nil,
        now: Date = Date()
    ) throws -> ComparisonExecutionState {
        var state = existingState ?? ComparisonExecutionState(
            taskRun: WuMindTaskRun(
                kind: .crossAppExecution,
                title: "跨应用报价比对与比价表写入",
                status: .running,
                activeModelLabel: "跨应用结构化解析与表格写入引擎",
                dataBoundary: .authorizedConnector,
                createdAt: now,
                updatedAt: now
            ),
            extractedRows: [],
            targetWorkbookPath: targetWorkbookURL.path,
            workbookWritten: false,
            recommendationPreview: "",
            sendDispatched: false
        )
        state.taskRun.status = .running

        var processedThisPass = 0
        for file in files {
            let key = "quote:\(file.fileName):\(stableDigest(file.content))"
            if state.taskRun.hasExecuted(idempotencyKey: key) {
                continue // Idempotent skip on resume/retry!
            }
            if let limit = failAfterProcessedCount, processedThisPass >= limit {
                state.taskRun.recordFailedStep(
                    title: "读取报价单 \(file.fileName)",
                    toolName: "authorized_folder_read",
                    idempotencyKey: "interrupt:\(file.fileName):\(now.timeIntervalSince1970)",
                    dataSource: file.fileName,
                    modelUsed: "本地报价解析器",
                    dataBoundary: .authorizedConnector,
                    error: "模拟中途断线中断，已完成 \(state.extractedRows.count) 份报价提取，可断点续跑",
                    now: now
                )
                return state
            }

            let parsed = parseQuoteFile(file, idempotencyKey: key, defaultTaxRate: defaultTaxRate)
            if !state.extractedRows.contains(where: { $0.idempotencyKey == key }) {
                state.extractedRows.append(parsed)
            }
            state.taskRun.recordCompletedStep(
                title: "提取并核对报价单：\(file.fileName)",
                toolName: "quote_extract_verify",
                idempotencyKey: key,
                dataSource: file.fileName,
                modelUsed: "本地报价解析器",
                dataBoundary: .authorizedConnector,
                outputSummary: "\(parsed.supplier) · 折合含税到岸价 ¥\(String(format: "%.2f", parsed.normalizedLandedTotalYuan))",
                now: now
            )
            processedThisPass += 1
        }

        // Build procurement recommendation preview
        let sorted = state.extractedRows.sorted { $0.normalizedLandedTotalYuan < $1.normalizedLandedTotalYuan }
        if let best = sorted.first {
            let missingNote = sorted.filter { !$0.missingFields.isEmpty }
                .map { "\($0.supplier)缺少\($0.missingFields.joined(separator: "/"))（待确认）" }
                .joined(separator: "；")
            state.recommendationPreview = "采购比价建议（共 \(sorted.count) 家）：推荐首选「\(best.supplier)」，含税含运到岸价 ¥\(String(format: "%.2f", best.normalizedLandedTotalYuan))（交期：\(best.leadTimeDays.map { "\($0) 天" } ?? "待确认")）。"
                + (missingNote.isEmpty ? "" : " 待补核项：\(missingNote)。")
        }

        // Strict approval gate BEFORE overwriting an existing target workbook!
        let targetExists = FileManager.default.fileExists(atPath: targetWorkbookURL.path)
        let writeKey = "write-xlsx:\(targetWorkbookURL.path):\(sorted.map(\.idempotencyKey).joined(separator: "|"))"
        if targetExists && !approvalGrantedForOverwrite && !state.taskRun.hasExecuted(idempotencyKey: writeKey) {
            state.taskRun.requestApproval(
                WuMindApprovalGate(
                    actionKind: .overwriteFile,
                    title: "覆盖写入现有比价表前需确认",
                    targetResource: targetWorkbookURL.lastPathComponent,
                    previewText: "目标文件已存在，将写入 \(sorted.count) 家核对后报价。\n\(state.recommendationPreview)"
                ),
                now: now
            )
            return state
        }

        // Actually write the real editable `.xlsx` workbook to disk (idempotent)!
        if !state.taskRun.hasExecuted(idempotencyKey: writeKey) {
            let xlsxData = WuMindXLSXExporter.makeWorkbook(sheets: [
                WuMindXLSXExporter.Sheet(
                    name: "供应商比价表",
                    headers: ["供应商", "标的物", "原始报价", "是否含税", "运费(元)", "折合含税到岸价(元)", "交期(天)", "缺失项标记", "来源文件"],
                    rows: sorted.map { r in
                        [
                            r.supplier,
                            r.itemName,
                            String(format: "%.2f", r.rawPrice),
                            r.taxIncluded ? "含税" : "未税(按\(Int(r.taxRate * 100))%折算)",
                            String(format: "%.2f", r.freightYuan),
                            String(format: "%.2f", r.normalizedLandedTotalYuan),
                            r.leadTimeDays.map(String.init) ?? "待确认",
                            r.missingFields.isEmpty ? "完整" : r.missingFields.joined(separator: "、"),
                            r.sourceFile,
                        ]
                    }
                ),
                WuMindXLSXExporter.Sheet(
                    name: "采购建议预览",
                    headers: ["生成时间", "结论预览", "状态"],
                    rows: [[ISO8601DateFormatter().string(from: now), state.recommendationPreview, "待用户确认发送"]]
                ),
            ])
            try FileManager.default.createDirectory(at: targetWorkbookURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try xlsxData.write(to: targetWorkbookURL, options: [.atomic])
            state.workbookWritten = true
            state.taskRun.recordCompletedStep(
                title: "真实写入目标比价表（.xlsx）",
                toolName: "xlsx_workbook_write",
                idempotencyKey: writeKey,
                dataSource: targetWorkbookURL.path,
                modelUsed: "ECMA-376 Excel 写入器",
                dataBoundary: .authorizedConnector,
                outputSummary: "已写入 \(sorted.count) 行至 \(targetWorkbookURL.lastPathComponent)（\(xlsxData.count) bytes）",
                now: now
            )
        }

        // Always stop before external sending — NEVER auto-send messages!
        state.taskRun.requestApproval(
            WuMindApprovalGate(
                actionKind: .sendMessage,
                title: "发送采购建议前确认预览",
                targetResource: "采购审批/分享预览",
                previewText: state.recommendationPreview
            ),
            now: now
        )
        return state
    }

    public static func parseQuoteFile(_ file: QuoteFileInput, idempotencyKey: String, defaultTaxRate: Double = 0.13) -> SupplierQuoteRow {
        let text = file.content
        func extract(_ keys: [String]) -> String? {
            for key in keys {
                let pat = "(?:\(key))\\s*[:：=,]\\s*([^\\n,;，；]+)"
                if let re = try? NSRegularExpression(pattern: pat, options: .caseInsensitive),
                   let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   m.numberOfRanges >= 2,
                   let r = Range(m.range(at: 1), in: text) {
                    let v = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !v.isEmpty { return v }
                }
            }
            return nil
        }

        let supplier = extract(["供应商", "公司", "supplier"]) ?? file.fileName.replacingOccurrences(of: ".csv", with: "").replacingOccurrences(of: ".txt", with: "")
        let item = extract(["标的物", "品名", "产品", "item"]) ?? "采购标的"
        let rawPriceStr = extract(["含税价", "未税价", "单价", "报价", "总价", "price"]) ?? "0"
        let rawPrice = extractNumber(from: rawPriceStr) ?? 0
        let explicitTaxFlag = extract(["含税", "税率类型", "tax"])
        let taxIncluded: Bool = {
            if text.contains("未税") || text.contains("不含税") || explicitTaxFlag?.contains("否") == true {
                return false
            }
            return true
        }()
        let freightStr = extract(["运费", "物流费", "freight"])
        let freight = freightStr.flatMap(extractNumber) ?? 0
        let leadStr = extract(["交期", "货期", "交付周期", "lead_time"])
        let leadDays = leadStr.flatMap(extractNumber).map { Int($0.rounded()) }

        var missing: [String] = []
        if leadDays == nil { missing.append("交期") }
        if freightStr == nil { missing.append("运费说明") }

        let taxAdjusted = taxIncluded ? rawPrice : (rawPrice * (1.0 + defaultTaxRate))
        let landed = ((taxAdjusted + freight) * 100).rounded() / 100

        return SupplierQuoteRow(
            idempotencyKey: idempotencyKey,
            supplier: supplier,
            itemName: item,
            rawPrice: rawPrice,
            taxIncluded: taxIncluded,
            taxRate: defaultTaxRate,
            freightYuan: freight,
            normalizedLandedTotalYuan: landed,
            leadTimeDays: leadDays,
            missingFields: missing,
            sourceFile: file.fileName
        )
    }

    private static func extractNumber(from s: String) -> Double? {
        let cleaned = s.replacingOccurrences(of: ",", with: "")
        guard let re = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#),
              let m = re.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
              let r = Range(m.range, in: cleaned) else {
            return nil
        }
        return Double(cleaned[r])
    }
}

// MARK: - Deterministic Cross-Platform Digest Helper

public func stableDigest(_ text: String) -> String {
    let data = Data(text.utf8)
    #if canImport(CryptoKit)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    #else
    // Deterministic 128-bit FNV-1a dual-lane hash for Linux fallback when CryptoKit is unavailable
    var h1: UInt64 = 0xcbf29ce484222325
    var h2: UInt64 = 0x84222325cbf29ce4
    for b in data {
        h1 = (h1 ^ UInt64(b)) &* 0x100000001b3
        h2 = (h2 ^ UInt64(b &+ 31)) &* 0x100000001b3
    }
    return String(format: "%016llx%016llx", h1, h2)
    #endif
}
