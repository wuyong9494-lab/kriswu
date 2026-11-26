import Foundation

// MARK: - Projects (Workspaces with Custom Instructions & Persistent Knowledge Files)

public struct WuMindProjectDoc: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var filename: String
    public var kindRaw: String
    public var summaryBadge: String
    public var extractedText: String
    public var addedAt: Date

    public init(id: UUID = UUID(),
                filename: String,
                kindRaw: String,
                summaryBadge: String,
                extractedText: String,
                addedAt: Date = Date()) {
        self.id = id
        self.filename = filename
        self.kindRaw = kindRaw
        self.summaryBadge = summaryBadge
        self.extractedText = extractedText
        self.addedAt = addedAt
    }
}

public struct WuMindProject: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var icon: String
    public var colorKey: String
    public var summary: String
    public var customInstructions: String
    public var attachedRepoFullName: String?
    public var enabledConnectorIDs: [String]
    public var knowledgeDocs: [WuMindProjectDoc]
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(),
                name: String,
                icon: String = "folder.fill",
                colorKey: String = "indigo",
                summary: String = "",
                customInstructions: String = "",
                attachedRepoFullName: String? = nil,
                enabledConnectorIDs: [String] = ["dev.github", "dev.webfetch", "dev.calculator"],
                knowledgeDocs: [WuMindProjectDoc] = [],
                createdAt: Date = Date(),
                updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorKey = colorKey
        self.summary = summary
        self.customInstructions = customInstructions
        self.attachedRepoFullName = attachedRepoFullName
        self.enabledConnectorIDs = enabledConnectorIDs
        self.knowledgeDocs = knowledgeDocs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func formattedProjectSystemBlock(maxChars: Int = 64_000) -> String {
        var parts: [String] = ["[当前项目空间：\(name)]"]
        let instr = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instr.isEmpty {
            parts.append("【项目专属指令】\n\(String(instr.prefix(12_000)))")
        }
        if let repo = attachedRepoFullName, !repo.isEmpty {
            parts.append("【项目绑定 GitHub 仓库】\(repo)")
        }
        if !knowledgeDocs.isEmpty {
            var remaining = max(4_000, maxChars - 14_000)
            let perDoc = max(2_000, remaining / knowledgeDocs.count)
            var docLines: [String] = ["【项目持久知识库文件（共 \(knowledgeDocs.count) 份）】"]
            for doc in knowledgeDocs {
                guard remaining > 200 else { break }
                let budget = min(perDoc, remaining)
                let body = doc.extractedText.count > budget
                    ? String(doc.extractedText.prefix(budget)) + "\n…（已按上下文预算截断，可用 project_search 工具精确检索）"
                    : doc.extractedText
                remaining -= body.count
                docLines.append("### \(doc.filename)（\(doc.summaryBadge)）\n\(body)")
            }
            parts.append(docLines.joined(separator: "\n\n"))
        }
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Customizations Marketplace & Installed Connectors (Modeled on Flagship Customizations Hub)

public enum WuMindCustomizationCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case workspace
    case developer
    case duty

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .workspace: return "办公与云端套件（Workspace & MCP）"
        case .developer: return "研发与智能体工具（Build & Agent）"
        case .duty: return "值班与本机工作台（Duty Workbench）"
        }
    }

    public var subtitle: String {
        switch self {
        case .workspace: return "接入文档、表格、邮件、日程与云端 MCP 桥接服务"
        case .developer: return "赋予智能体直连代码库、实时读网页、算力校验与 Webhook 调用能力"
        case .duty: return "按需将本机排班、遥测计划与工作留痕连接至智能体（默认关闭，保护隐私）"
        }
    }
}

public struct WuMindConnectorSpec: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let category: WuMindCustomizationCategory
    public let iconName: String
    public let tintKey: String
    public let toolName: String?
    public let requiresEndpoint: Bool
    public let defaultInstalled: Bool
    public let agentPromptHint: String

    public init(id: String,
                name: String,
                subtitle: String,
                category: WuMindCustomizationCategory,
                iconName: String,
                tintKey: String,
                toolName: String?,
                requiresEndpoint: Bool,
                defaultInstalled: Bool,
                agentPromptHint: String) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.category = category
        self.iconName = iconName
        self.tintKey = tintKey
        self.toolName = toolName
        self.requiresEndpoint = requiresEndpoint
        self.defaultInstalled = defaultInstalled
        self.agentPromptHint = agentPromptHint
    }

    public static let marketplaceCatalog: [WuMindConnectorSpec] = [
        // Build & Agent Developer Tools (Live Executable)
        WuMindConnectorSpec(
            id: "dev.github",
            name: "GitHub 仓库直连",
            subtitle: "实时浏览仓库目录、README、提交记录并按需读取任意源码文件",
            category: .developer,
            iconName: "chevron.left.forwardslash.chevron.right",
            tintKey: "teal",
            toolName: "github_inspect",
            requiresEndpoint: false,
            defaultInstalled: true,
            agentPromptHint: "可调用 github_inspect(repo, path?) 直接查看仓库结构或读取指定源码文件。"
        ),
        WuMindConnectorSpec(
            id: "dev.websearch",
            name: "联网深度搜索（Web Search）",
            subtitle: "实时检索全网权威资料、最新新闻与技术文档，支撑多步 Deep Research 深度调研",
            category: .developer,
            iconName: "magnifyingglass.circle.fill",
            tintKey: "cyan",
            toolName: "web_search",
            requiresEndpoint: false,
            defaultInstalled: true,
            agentPromptHint: "可调用 web_search(query, depth?) 实时搜索全网资料，再结合 web_fetch 深读原始页面并给出带来源链接的结论。"
        ),
        WuMindConnectorSpec(
            id: "dev.webfetch",
            name: "网页实时抓读（Web Fetch）",
            subtitle: "直接抓取任意 HTTPS 技术文档、公告或文章正文，免手动复制",
            category: .developer,
            iconName: "globe",
            tintKey: "blue",
            toolName: "web_fetch",
            requiresEndpoint: false,
            defaultInstalled: true,
            agentPromptHint: "可调用 web_fetch(url) 实时抓取公开 HTTPS 网页正文内容。"
        ),
        WuMindConnectorSpec(
            id: "dev.calculator",
            name: "精确表达式精算器",
            subtitle: "执行高精度数学、费用、工时与比例计算，避免大模型心算误差",
            category: .developer,
            iconName: "function",
            tintKey: "orange",
            toolName: "calculator_verify",
            requiresEndpoint: false,
            defaultInstalled: true,
            agentPromptHint: "可调用 calculator_verify(expression) 执行精确算术计算。"
        ),
        WuMindConnectorSpec(
            id: "dev.project_search",
            name: "项目知识库检索",
            subtitle: "在当前项目空间绑定的长文档、代码与历史资料中按关键词检索片段",
            category: .developer,
            iconName: "doc.text.magnifyingglass",
            tintKey: "indigo",
            toolName: "project_search",
            requiresEndpoint: false,
            defaultInstalled: true,
            agentPromptHint: "可调用 project_search(query) 检索当前项目知识库中的相关段落。"
        ),
        WuMindConnectorSpec(
            id: "dev.webhook",
            name: "自定义 Webhook / MCP 桥接",
            subtitle: "连接任意 HTTPS 自动化端点、飞书/钉钉机器人或自建 MCP 工具服务",
            category: .developer,
            iconName: "antenna.radiowaves.left.and.right",
            tintKey: "purple",
            toolName: "webhook_call",
            requiresEndpoint: true,
            defaultInstalled: false,
            agentPromptHint: "可调用 webhook_call(action, payload) 调用用户配置的自定义 HTTPS/MCP 桥接服务。"
        ),
        // Workspace & Cloud Suite (Modeled on Antigravity Customizations Marketplace)
        WuMindConnectorSpec(
            id: "ws.docs",
            name: "云端文档（Docs / Word）",
            subtitle: "起草、审阅与结构化排版正式文档，支持通过 MCP 桥接读写云文档",
            category: .workspace,
            iconName: "doc.richtext.fill",
            tintKey: "blue",
            toolName: "webhook_call",
            requiresEndpoint: true,
            defaultInstalled: false,
            agentPromptHint: "擅长文档起草与修订；若已配置 Docs MCP 桥接地址，可通过 webhook_call 读写文档。"
        ),
        WuMindConnectorSpec(
            id: "ws.sheets",
            name: "云端表格（Sheets / Excel）",
            subtitle: "精读多表数据、生成统计公式与财务对比表，支持 MCP 桥接同步",
            category: .workspace,
            iconName: "tablecells.fill",
            tintKey: "green",
            toolName: "webhook_call",
            requiresEndpoint: true,
            defaultInstalled: false,
            agentPromptHint: "擅长表格指标分析与公式生成；若已配置 Sheets MCP 桥接地址，可调用工具同步数据。"
        ),
        WuMindConnectorSpec(
            id: "ws.slides",
            name: "演示文稿（Slides / PPT）",
            subtitle: "一键规划汇报大纲、逐页演讲稿与信息图表布局",
            category: .workspace,
            iconName: "play.rectangle.fill",
            tintKey: "yellow",
            toolName: nil,
            requiresEndpoint: false,
            defaultInstalled: false,
            agentPromptHint: "输出汇报型内容时自动按「页标题 / 核心结论 / 视觉排版建议 / 演讲备注」结构化生成。"
        ),
        WuMindConnectorSpec(
            id: "ws.drive",
            name: "云盘检索（Drive / OSS）",
            subtitle: "通过 HTTPS/MCP 网关检索并读取云盘共享文档与资料库",
            category: .workspace,
            iconName: "externaldrive.fill.badge.icloud",
            tintKey: "cyan",
            toolName: "webhook_call",
            requiresEndpoint: true,
            defaultInstalled: false,
            agentPromptHint: "若已配置 Drive MCP 桥接地址，可调用 webhook_call 检索云盘文件。"
        ),
        WuMindConnectorSpec(
            id: "ws.calendar",
            name: "智能日程（Calendar）",
            subtitle: "检查空闲时段、安排会议日程、梳理周期提醒事项",
            category: .workspace,
            iconName: "calendar.badge.clock",
            tintKey: "red",
            toolName: "duty_schedule_lookup",
            requiresEndpoint: false,
            defaultInstalled: false,
            agentPromptHint: "可结合值班排班查询近期待办与空闲日期，协助规划日程。"
        ),
        WuMindConnectorSpec(
            id: "ws.mail",
            name: "邮件助手（Mail / Gmail）",
            subtitle: "撰写专业中英文商务邮件、提炼往来重点，支持桥接发信草稿",
            category: .workspace,
            iconName: "envelope.fill",
            tintKey: "pink",
            toolName: "webhook_call",
            requiresEndpoint: true,
            defaultInstalled: false,
            agentPromptHint: "生成邮件时提供清晰主题行、收件人称谓、核心要点与明确行动项。"
        ),
        // Duty Workbench Native Connector (Opt-in privacy boundary)
        WuMindConnectorSpec(
            id: "duty.schedule",
            name: "值班排班实时读取",
            subtitle: "授权智能体查询今日/近期值班班次、下一次遥测日期与本月工作量",
            category: .duty,
            iconName: "calendar.day.timeline.left",
            tintKey: "mint",
            toolName: "duty_schedule_lookup",
            requiresEndpoint: false,
            defaultInstalled: false,
            agentPromptHint: "可调用 duty_schedule_lookup(days?) 读取本机已同步的值班排班与下一次遥测时间。"
        ),
    ]

    public static var defaultInstalledIDs: Set<String> {
        Set(marketplaceCatalog.filter(\.defaultInstalled).map(\.id))
    }
}

// MARK: - Scheduled Tasks / Automations

public enum WuMindScheduleExecutionMode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case aiRun = "ai_run"
    case reminderOnly = "reminder_only"

    public var displayTitle: String {
        switch self {
        case .aiRun: return "AI 自动执行"
        case .reminderOnly: return "仅到点提醒"
        }
    }
}

public enum WuMindScheduleRunStatus: String, Codable, Equatable, Hashable, Sendable {
    case aiCompleted = "ai_completed"
    case reminderSent = "reminder_sent"
    case failedInsufficientBalance = "failed_insufficient_balance"
    case failedUpstream = "failed_upstream"
    case failedConfig = "failed_config"

    public var badgeLabel: String {
        switch self {
        case .aiCompleted: return "AI 已完成"
        case .reminderSent: return "到点提醒已送达"
        case .failedInsufficientBalance: return "余额不足未执行"
        case .failedUpstream: return "执行失败（未扣费）"
        case .failedConfig: return "模型未开通"
        }
    }

    public var isFailure: Bool {
        switch self {
        case .aiCompleted, .reminderSent: return false
        case .failedInsufficientBalance, .failedUpstream, .failedConfig: return true
        }
    }
}

public struct WuMindScheduleRunRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let idempotencyKey: String
    public let executedAtText: String
    public let status: WuMindScheduleRunStatus
    public let executionMode: WuMindScheduleExecutionMode
    public let modelID: String
    public let costYuan: Double
    public let failureReason: String?
    public let answerPreview: String?
    public var conversationID: UUID?

    public init(
        id: String = UUID().uuidString,
        idempotencyKey: String,
        executedAtText: String,
        status: WuMindScheduleRunStatus,
        executionMode: WuMindScheduleExecutionMode,
        modelID: String = "",
        costYuan: Double = 0,
        failureReason: String? = nil,
        answerPreview: String? = nil,
        conversationID: UUID? = nil
    ) {
        self.id = id
        self.idempotencyKey = idempotencyKey
        self.executedAtText = executedAtText
        self.status = status
        self.executionMode = executionMode
        self.modelID = modelID
        self.costYuan = costYuan
        self.failureReason = failureReason
        self.answerPreview = answerPreview
        self.conversationID = conversationID
    }
}

public enum WuMindScheduleCadence: Codable, Equatable, Hashable, Sendable {
    case daily(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int) // 1 = Sun ... 7 = Sat
    case intervalHours(Int)
    case once(Date)

    public static var beijingCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 3600)!
        return cal
    }

    public static func formatBeijingDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.calendar = beijingCalendar
        df.timeZone = beijingCalendar.timeZone
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return "\(df.string(from: date)) (北京时间)"
    }

    public var recurrenceKindRaw: String {
        switch self {
        case .once: return "once"
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .intervalHours: return "interval"
        }
    }

    public var scheduleTimeComponents: (hour: Int, minute: Int, weekday: Int, intervalMinutes: Int) {
        switch self {
        case .daily(let h, let m):
            return (h, m, 2, 1440)
        case .weekly(let wd, let h, let m):
            return (h, m, wd, 10080)
        case .intervalHours(let hrs):
            return (8, 30, 2, max(15, hrs * 60))
        case .once(let d):
            let comps = Self.beijingCalendar.dateComponents([.hour, .minute, .weekday], from: d)
            return (comps.hour ?? 8, comps.minute ?? 30, comps.weekday ?? 2, 0)
        }
    }

    public var displayLabel: String {
        switch self {
        case .daily(let h, let m):
            return String(format: "每天 %02d:%02d", h, m)
        case .weekly(let wd, let h, let m):
            let names = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            let dayName = (1...7).contains(wd) ? names[wd] : "每周"
            return String(format: "每%@ %02d:%02d", dayName, h, m)
        case .intervalHours(let hrs):
            return "每 \(max(1, hrs)) 小时"
        case .once(let date):
            return "仅一次 · \(Self.formatBeijingDate(date))"
        }
    }

    public func nextRunDate(after now: Date, calendar: Calendar = WuMindScheduleCadence.beijingCalendar) -> Date? {
        switch self {
        case .daily(let hour, let minute):
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = min(23, max(0, hour))
            comps.minute = min(59, max(0, minute))
            comps.second = 0
            guard let candidate = calendar.date(from: comps) else { return nil }
            if candidate > now { return candidate }
            return calendar.date(byAdding: .day, value: 1, to: candidate)
        case .weekly(let weekday, let hour, let minute):
            var comps = DateComponents()
            comps.weekday = min(7, max(1, weekday))
            comps.hour = min(23, max(0, hour))
            comps.minute = min(59, max(0, minute))
            comps.second = 0
            return calendar.nextDate(after: now, matching: comps, matchingPolicy: .nextTime)
        case .intervalHours(let hours):
            return now.addingTimeInterval(TimeInterval(max(1, min(168, hours)) * 3600))
        case .once(let date):
            return date > now ? date : nil
        }
    }
}

public struct WuMindScheduledTask: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var prompt: String
    public var projectID: UUID?
    public var modelID: String
    public var channelRaw: String // "ownAPI" or "managed"
    public var useAgentMode: Bool
    public var cadence: WuMindScheduleCadence
    public var executionMode: WuMindScheduleExecutionMode
    public var timezoneID: String
    public var enabled: Bool
    public var nextRunAt: Date?
    public var nextRunBeijingText: String?
    public var lastRunAt: Date?
    public var lastStatus: String?
    public var lastCostYuan: Double?
    public var lastTokens: Int?
    public var lastConversationID: UUID?
    public var cloudSynced: Bool
    public var serverConfirmed: Bool
    public var serverStatus: String // "active" | "paused" | "completed" | "cancelled" | "pending_sync" | "sync_failed" | "local_only"
    public var syncError: String?
    public var runs: [WuMindScheduleRunRecord]

    public var isManagedCloudTask: Bool {
        channelRaw == "managed"
    }

    public var supportsLockScreenCloudExecution: Bool {
        isManagedCloudTask && serverConfirmed && serverStatus == "active"
    }

    public var displayNextRunBeijingText: String {
        if serverStatus == "completed" { return "单次任务已执行完毕" }
        if serverStatus == "cancelled" { return "任务已取消" }
        if !enabled || serverStatus == "paused" { return "已暂停" }
        if let txt = nextRunBeijingText, !txt.isEmpty { return txt }
        if let d = nextRunAt { return WuMindScheduleCadence.formatBeijingDate(d) }
        return "无后续计划"
    }

    public var statusBadgeTitle: String {
        if serverStatus == "completed" { return "已完成（单次结束）" }
        if serverStatus == "cancelled" { return "已取消" }
        if !enabled || serverStatus == "paused" { return "已暂停" }
        if !isManagedCloudTask { return "仅本机提醒（自有 Key 不支持锁屏云端执行）" }
        if serverConfirmed { return "已安排 · 云端锁屏可执行" }
        if syncError != nil || serverStatus == "sync_failed" { return "未安排（云端同步失败）" }
        return "待服务端确认…"
    }

    public init(id: UUID = UUID(),
                title: String,
                prompt: String,
                projectID: UUID? = nil,
                modelID: String = "deepseek-reasoner",
                channelRaw: String = "ownAPI",
                useAgentMode: Bool = true,
                cadence: WuMindScheduleCadence = .daily(hour: 8, minute: 30),
                executionMode: WuMindScheduleExecutionMode = .aiRun,
                timezoneID: String = "Asia/Shanghai",
                enabled: Bool = true,
                nextRunAt: Date? = nil,
                nextRunBeijingText: String? = nil,
                lastRunAt: Date? = nil,
                lastStatus: String? = nil,
                lastCostYuan: Double? = nil,
                lastTokens: Int? = nil,
                lastConversationID: UUID? = nil,
                cloudSynced: Bool = false,
                serverConfirmed: Bool = false,
                serverStatus: String? = nil,
                syncError: String? = nil,
                runs: [WuMindScheduleRunRecord] = []) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.projectID = projectID
        self.modelID = modelID
        self.channelRaw = channelRaw
        self.useAgentMode = useAgentMode
        self.cadence = cadence
        self.executionMode = executionMode
        self.timezoneID = timezoneID
        self.enabled = enabled
        let computedNext = nextRunAt ?? (enabled ? cadence.nextRunDate(after: Date()) : nil)
        self.nextRunAt = computedNext
        self.nextRunBeijingText = nextRunBeijingText ?? computedNext.map { WuMindScheduleCadence.formatBeijingDate($0) }
        self.lastRunAt = lastRunAt
        self.lastStatus = lastStatus
        self.lastCostYuan = lastCostYuan
        self.lastTokens = lastTokens
        self.lastConversationID = lastConversationID
        self.cloudSynced = cloudSynced
        self.serverConfirmed = serverConfirmed
        if let serverStatus {
            self.serverStatus = serverStatus
        } else if !enabled {
            self.serverStatus = "paused"
        } else {
            self.serverStatus = channelRaw == "managed" ? (serverConfirmed ? "active" : "pending_sync") : "local_only"
        }
        self.syncError = syncError
        self.runs = runs
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, prompt, projectID, modelID, channelRaw, useAgentMode, cadence
        case executionMode, timezoneID, enabled, nextRunAt, nextRunBeijingText
        case lastRunAt, lastStatus, lastCostYuan, lastTokens, lastConversationID
        case cloudSynced, serverConfirmed, serverStatus, syncError, runs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        prompt = try c.decode(String.self, forKey: .prompt)
        projectID = try c.decodeIfPresent(UUID.self, forKey: .projectID)
        modelID = try c.decode(String.self, forKey: .modelID)
        channelRaw = try c.decode(String.self, forKey: .channelRaw)
        useAgentMode = try c.decode(Bool.self, forKey: .useAgentMode)
        cadence = try c.decode(WuMindScheduleCadence.self, forKey: .cadence)
        executionMode = try c.decodeIfPresent(WuMindScheduleExecutionMode.self, forKey: .executionMode) ?? .aiRun
        timezoneID = try c.decodeIfPresent(String.self, forKey: .timezoneID) ?? "Asia/Shanghai"
        enabled = try c.decode(Bool.self, forKey: .enabled)
        nextRunAt = try c.decodeIfPresent(Date.self, forKey: .nextRunAt)
        nextRunBeijingText = try c.decodeIfPresent(String.self, forKey: .nextRunBeijingText)
        lastRunAt = try c.decodeIfPresent(Date.self, forKey: .lastRunAt)
        lastStatus = try c.decodeIfPresent(String.self, forKey: .lastStatus)
        lastCostYuan = try c.decodeIfPresent(Double.self, forKey: .lastCostYuan)
        lastTokens = try c.decodeIfPresent(Int.self, forKey: .lastTokens)
        lastConversationID = try c.decodeIfPresent(UUID.self, forKey: .lastConversationID)
        cloudSynced = try c.decodeIfPresent(Bool.self, forKey: .cloudSynced) ?? false
        serverConfirmed = try c.decodeIfPresent(Bool.self, forKey: .serverConfirmed) ?? cloudSynced
        serverStatus = try c.decodeIfPresent(String.self, forKey: .serverStatus)
            ?? (enabled ? (channelRaw == "managed" ? (serverConfirmed ? "active" : "pending_sync") : "local_only") : "paused")
        syncError = try c.decodeIfPresent(String.self, forKey: .syncError)
        runs = try c.decodeIfPresent([WuMindScheduleRunRecord].self, forKey: .runs) ?? []
    }
}

// MARK: - User Personalization, Long-Term Memory & Flagship Settings

public struct WuMindMemoryItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var content: String
    public var category: String
    public var ruleVersion: String?
    public var projectID: UUID?
    public var updatedAt: Date

    public init(id: UUID = UUID(),
                content: String,
                category: String = "偏好",
                ruleVersion: String? = nil,
                projectID: UUID? = nil,
                updatedAt: Date = Date()) {
        self.id = id
        self.content = content
        self.category = category
        let trimmedVersion = ruleVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ruleVersion = (trimmedVersion?.isEmpty == false) ? trimmedVersion : nil
        self.projectID = projectID
        self.updatedAt = updatedAt
    }

    public static let standardCategories: [String] = [
        "站名表", "规则", "更正", "标书", "偏好"
    ]
}

public struct WuMindPreferences: Codable, Equatable, Sendable {
    public var userDisplayName: String
    public var userRoleBackground: String
    public var responseStyle: String
    public var memoryEnabled: Bool
    public var agentEnabledByDefault: Bool
    public var agentMaxSteps: Int
    public var agentMaxCostYuanPerRun: Double
    public var autoCompactThresholdPercent: Int // 70, 80, 90
    public var backgroundNotificationsEnabled: Bool
    public var streamSmoothMode: Bool

    public init(userDisplayName: String = "",
                userRoleBackground: String = "",
                responseStyle: String = "结论先行、结构清晰、专业克制",
                memoryEnabled: Bool = true,
                agentEnabledByDefault: Bool = false,
                agentMaxSteps: Int = 6,
                agentMaxCostYuanPerRun: Double = 2.0,
                autoCompactThresholdPercent: Int = 80,
                backgroundNotificationsEnabled: Bool = true,
                streamSmoothMode: Bool = true) {
        self.userDisplayName = userDisplayName
        self.userRoleBackground = userRoleBackground
        self.responseStyle = responseStyle
        self.memoryEnabled = memoryEnabled
        self.agentEnabledByDefault = agentEnabledByDefault
        self.agentMaxSteps = min(10, max(2, agentMaxSteps))
        self.agentMaxCostYuanPerRun = max(0.1, agentMaxCostYuanPerRun)
        self.autoCompactThresholdPercent = [70, 80, 90].contains(autoCompactThresholdPercent) ? autoCompactThresholdPercent : 80
        self.backgroundNotificationsEnabled = backgroundNotificationsEnabled
        self.streamSmoothMode = streamSmoothMode
    }

    public var autoCompactRatio: Double {
        Double(min(95, max(50, autoCompactThresholdPercent))) / 100.0
    }

    public func formattedSystemProfileBlock(
        memories: [WuMindMemoryItem],
        activeProjectID: UUID? = nil,
        isTemporaryChat: Bool = false
    ) -> String? {
        if isTemporaryChat {
            return "[WUMIND 临时无痕模式]\n- 本次对话为无痕临时聊天：不读取也不写入跨对话长期记忆与项目私有规则。"
        }

        var lines: [String] = []
        let cleanName = userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRole = userRoleBackground.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanStyle = responseStyle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanName.isEmpty { lines.append("- 用户称呼：\(cleanName)") }
        if !cleanRole.isEmpty { lines.append("- 专业背景：\(cleanRole)") }
        if !cleanStyle.isEmpty { lines.append("- 偏好输出风格：\(cleanStyle)") }

        // Strict project isolation: only global memories (projectID == nil) or memories bound to activeProjectID.
        let scoped = memories
            .filter { item in
                item.projectID == nil || (activeProjectID != nil && item.projectID == activeProjectID)
            }
            .sorted { $0.updatedAt > $1.updatedAt }

        if memoryEnabled && !scoped.isEmpty {
            let capped = Array(scoped.prefix(24))
            var countsByCategory: [String: Int] = [:]
            var hasVersionedOrConflicting = false
            for item in capped {
                let key = item.category.trimmingCharacters(in: .whitespacesAndNewlines)
                countsByCategory[key, default: 0] += 1
                if item.ruleVersion != nil || countsByCategory[key, default: 0] > 1 {
                    hasVersionedOrConflicting = true
                }
            }

            lines.append("【跨对话长期记忆与生效规则（严格按项目隔离）】")
            if hasVersionedOrConflicting {
                lines.append("【规则与版本冲突准则】若存在新旧规则、站名表或用户更正冲突，必须优先采用标注「最新生效」且时间最新的版本，并在回答中显式注明“本次采用规则版本：…”。")
            }

            var seenCategories: Set<String> = []
            for item in capped {
                let cat = item.category.trimmingCharacters(in: .whitespacesAndNewlines)
                let scopeTag = item.projectID != nil ? "当前项目" : "全局"
                let versionTag = item.ruleVersion.map { " · 版本 \($0)" } ?? ""
                let conflictTag: String
                if (countsByCategory[cat] ?? 0) > 1 || item.ruleVersion != nil {
                    if !seenCategories.contains(cat) {
                        conflictTag = "【最新生效】"
                    } else {
                        conflictTag = "【历史旧版】"
                    }
                } else {
                    conflictTag = ""
                }
                seenCategories.insert(cat)
                lines.append("- \(conflictTag)[\(scopeTag)·\(cat)\(versionTag)] \(item.content)")
            }
        }
        guard !lines.isEmpty else { return nil }
        return "[WUMIND 用户画像与长期记忆]\n" + lines.joined(separator: "\n")
    }
}

// MARK: - Multi-Step Agent Execution Trace & Accurate Cumulative Metering

public struct WuMindAgentStep: Codable, Identifiable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case planning
        case toolCall
        case synthesizing
        case budgetStopped
    }

    public let id: UUID
    public var stepIndex: Int
    public var phase: Phase
    public var toolName: String
    public var toolSummary: String
    public var resultPreview: String
    public var promptTokens: Int
    public var completionTokens: Int
    public var reasoningTokens: Int
    public var costYuan: Double
    public var durationSeconds: Double
    public var succeeded: Bool

    public init(id: UUID = UUID(),
                stepIndex: Int,
                phase: Phase,
                toolName: String,
                toolSummary: String,
                resultPreview: String = "",
                promptTokens: Int = 0,
                completionTokens: Int = 0,
                reasoningTokens: Int = 0,
                costYuan: Double = 0,
                durationSeconds: Double = 0,
                succeeded: Bool = true) {
        self.id = id
        self.stepIndex = stepIndex
        self.phase = phase
        self.toolName = toolName
        self.toolSummary = toolSummary
        self.resultPreview = resultPreview
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.reasoningTokens = reasoningTokens
        self.costYuan = costYuan
        self.durationSeconds = durationSeconds
        self.succeeded = succeeded
    }
}

public struct WuMindAgentUsageTotals: Equatable, Sendable {
    public let stepCount: Int
    public let promptTokens: Int
    public let completionTokens: Int
    public let reasoningTokens: Int
    public let costYuan: Double

    public var totalTokens: Int {
        promptTokens + completionTokens + reasoningTokens
    }

    public static func aggregate(steps: [WuMindAgentStep],
                                 finalPromptTokens: Int = 0,
                                 finalCompletionTokens: Int = 0,
                                 finalReasoningTokens: Int = 0,
                                 finalCostYuan: Double = 0) -> WuMindAgentUsageTotals {
        let p = steps.reduce(finalPromptTokens) { $0 + $1.promptTokens }
        let c = steps.reduce(finalCompletionTokens) { $0 + $1.completionTokens }
        let r = steps.reduce(finalReasoningTokens) { $0 + $1.reasoningTokens }
        let cost = steps.reduce(finalCostYuan) { $0 + $1.costYuan }
        return WuMindAgentUsageTotals(
            stepCount: max(1, steps.count + (finalCompletionTokens > 0 || finalPromptTokens > 0 ? 1 : 0)),
            promptTokens: p,
            completionTokens: c,
            reasoningTokens: r,
            costYuan: (cost * 1_000_000).rounded() / 1_000_000
        )
    }
}

/// Cross-provider Agent tool-calling protocol & budget guardrail.
/// Uses structured `<wumind_tool>{...}</wumind_tool>` envelopes so ALL 5 providers
/// (DeepSeek, OpenAI, Gemini, Claude, Grok) + WUMIND Managed Gateway execute multi-step tool chains identically.
public enum WuMindAgentProtocol {
    public struct ToolInvocation: Equatable, Sendable {
        public let tool: String
        public let args: [String: String]

        public init(tool: String, args: [String: String]) {
            self.tool = tool
            self.args = args
        }
    }

    public static func agentSystemDirective(enabledConnectors: [WuMindConnectorSpec], maxSteps: Int) -> String {
        let activeToolConnectors = enabledConnectors.filter { $0.toolName != nil }
        var lines: [String] = [
            "[WUMIND 自主智能体模式已启用（单次最多 \(maxSteps) 步）]",
            "你可以像顶级 AI 智能体一样先规划，并在需要外部真实信息或精确验算时调用下方已安装工具。只有在确实需要工具时才调用；若已有足够信息，请直接给出高质量最终回答。",
            "调用工具格式（每次只调用 1 个工具，输出以下标签后立即停止本轮输出等待观察结果）：",
            #"<wumind_tool>{"tool":"工具名","args":{"参数名":"参数值"}}</wumind_tool>"#,
            "可用工具列表："
        ]
        var seenTools: Set<String> = []
        for spec in activeToolConnectors {
            guard let tool = spec.toolName, !seenTools.contains(tool) else { continue }
            seenTools.insert(tool)
            switch tool {
            case "github_inspect":
                lines.append("- github_inspect: args={\"repo\":\"owner/repo\", \"path\":\"可选相对文件路径\"} — 读取 GitHub 仓库概览或指定源码文件")
            case "web_search":
                lines.append("- web_search: args={\"query\":\"搜索关键词\", \"depth\":\"basic 或 advanced\"} — 联网深度搜索最新公开资讯、技术文档与权威来源（返回标题、链接与摘要）")
            case "web_fetch":
                lines.append("- web_fetch: args={\"url\":\"https://...\"} — 实时抓取公开 HTTPS 网页正文")
            case "calculator_verify":
                lines.append("- calculator_verify: args={\"expression\":\"(12.5*8+30)/2\"} — 精确算术表达式计算")
            case "project_search":
                lines.append("- project_search: args={\"query\":\"关键词\"} — 在当前项目持久知识库文档中检索相关片段")
            case "duty_schedule_lookup":
                lines.append("- duty_schedule_lookup: args={\"days\":\"7\"} — 查询本机最近 N 天值班排班与下一次遥测日期")
            case "webhook_call":
                lines.append("- webhook_call: args={\"connector_id\":\"dev.webhook\", \"action\":\"动作\", \"payload\":\"JSON或文本\"} — 调用已配置的自定义 HTTPS / MCP 桥接服务")
            default:
                break
            }
        }
        let nonToolHints = enabledConnectors.filter { $0.toolName == nil }.map { "- \($0.name)：\($0.agentPromptHint)" }
        if !nonToolHints.isEmpty {
            lines.append("已安装协作能力偏好：")
            lines.append(contentsOf: nonToolHints)
        }
        return lines.joined(separator: "\n")
    }

    /// Parses the first `<wumind_tool>{...}</wumind_tool>` block from a model response.
    public static func parseToolInvocation(from text: String) -> ToolInvocation? {
        guard let startRange = text.range(of: "<wumind_tool>"),
              let endRange = text.range(of: "</wumind_tool>", range: startRange.upperBound..<text.endIndex) else {
            return nil
        }
        let rawJSON = text[startRange.upperBound..<endRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = rawJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let toolName = (obj["tool"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !toolName.isEmpty else {
            return nil
        }
        var stringArgs: [String: String] = [:]
        if let rawArgs = obj["args"] as? [String: Any] {
            for (k, v) in rawArgs {
                if let s = v as? String {
                    stringArgs[k] = s
                } else if let n = v as? NSNumber {
                    stringArgs[k] = n.stringValue
                } else if let nested = try? JSONSerialization.data(withJSONObject: v),
                          let nestedStr = String(data: nested, encoding: .utf8) {
                    stringArgs[k] = nestedStr
                }
            }
        }
        return ToolInvocation(tool: toolName, args: stringArgs)
    }

    /// Strips raw `<wumind_tool>...</wumind_tool>` tags if any remain in final user-visible text.
    public static func stripToolTags(from text: String) -> String {
        var output = text
        while let start = output.range(of: "<wumind_tool>"),
              let end = output.range(of: "</wumind_tool>", range: start.upperBound..<output.endIndex) {
            output.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Checks whether the Agent loop must stop early due to step limit or per-run cost budget guardrail.
    public static func budgetStopReason(
        completedSteps: Int,
        maxSteps: Int,
        accumulatedCostYuan: Double,
        maxCostYuan: Double,
        isManagedChannel: Bool
    ) -> String? {
        if completedSteps >= maxSteps {
            return "已达到设定的单次智能体最大步数上限（\(maxSteps) 步），正在基于已收集结果汇总最终回复。"
        }
        if isManagedChannel && maxCostYuan > 0 && accumulatedCostYuan >= maxCostYuan {
            return String(format: "已触及单次智能体费用保护上限（¥%.2f），已自动停止继续调用工具并汇总结论。", maxCostYuan)
        }
        return nil
    }
}
