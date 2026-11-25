import Foundation

/// Deterministic, read-only, intranet-only Duty App Q&A engine for WUMIND.
///
/// Key architectural guarantees:
/// 1. **Programmatic First**: The App resolves business dates ("今天", "明天", explicit dates, and cross-midnight
///    telemetry handover windows) and invokes scoped read-only queries BEFORE any cloud LLM is ever involved.
/// 2. **Intranet Zero-Leakage**: Internal roster, swaps, leave/trip, workload, pass-plan, and meeting data stay
///    strictly on-device (`exfiltratedToExternalModel == false`) and are NEVER sent to public external models.
/// 3. **Authoritative Source Separation**: Planned roster, temporary swaps, leave records, business-trip records,
///    and actual physical attendance are queried separately; planned schedule is NEVER used to fabricate actual presence.
/// 4. **Partial-Answer-First & Explicit 4-State Semantics**: Every queried item carries its resolved date,
///    auditable data source, and exact status (`confirmed` / `checkedEmpty` / `unauthorizedOrUnconnected` / `queryFailed`).
/// 5. **Normal Chat Isolation**: General non-duty chat returns `nil` from `classifyIntent` and NEVER touches duty data.
public enum WuMindDutyQueryEngine {

    // MARK: - Domain Types

    public enum QueryStatus: String, Codable, Equatable, Sendable {
        case confirmed                  // 已查到明确记录
        case checkedEmpty               // 已查权威数据源，确无记录
        case unauthorizedOrUnconnected  // 无权限或未接入权威数据源
        case queryFailed                // 查询失败

        public var chineseLabel: String {
            switch self {
            case .confirmed: return "已确认"
            case .checkedEmpty: return "已查·确无记录"
            case .unauthorizedOrUnconnected: return "未确认（无权限/未接入）"
            case .queryFailed: return "查询失败"
            }
        }
    }

    public enum PermissionState: Equatable, Sendable {
        case authorized(roleTitle: String)
        case denied(reason: String)
    }

    public enum DataSourceStatus: Equatable, Sendable {
        case available(sourceName: String, syncedAt: Date? = nil)
        case unavailable(reason: String)
        case failed(sourceName: String, error: String)
    }

    public enum SubTopic: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
        case onDuty
        case restingGroups
        case leave
        case trip
        case actualAttendance
        case swaps
        case mySchedule
        case personSchedule
        case workload
        case forecast
        case passPlan
        case meeting
        case noticesAndGroupNotes
        case workLog
        case holidays
    }

    public struct ParsedIntent: Equatable, Sendable {
        public let resolvedDate: DayKey
        public let businessTimezoneID: String
        public let isRelativeToday: Bool
        public let topics: [SubTopic]
        public let mentionedPerson: String?

        public init(
            resolvedDate: DayKey,
            businessTimezoneID: String,
            isRelativeToday: Bool,
            topics: [SubTopic],
            mentionedPerson: String? = nil
        ) {
            self.resolvedDate = resolvedDate
            self.businessTimezoneID = businessTimezoneID
            self.isRelativeToday = isRelativeToday
            self.topics = topics
            self.mentionedPerson = mentionedPerson
        }
    }

    public struct AuthoritativeLeaveRecord: Equatable, Sendable {
        public let person: String
        public let day: DayKey
        public let category: String // e.g. "年假", "病假", "事假", "请假"
        public let source: String

        public init(person: String, day: DayKey, category: String, source: String) {
            self.person = person
            self.day = day
            self.category = category
            self.source = source
        }
    }

    public struct AuthoritativeTripRecord: Equatable, Sendable {
        public let person: String
        public let day: DayKey
        public let destinationOrNote: String
        public let source: String

        public init(person: String, day: DayKey, destinationOrNote: String, source: String) {
            self.person = person
            self.day = day
            self.destinationOrNote = destinationOrNote
            self.source = source
        }
    }

    public struct AuthoritativeAttendanceRecord: Equatable, Sendable {
        public let person: String
        public let day: DayKey
        public let status: String // e.g. "已打卡在岗"
        public let checkedAt: String
        public let source: String

        public init(person: String, day: DayKey, status: String, checkedAt: String, source: String) {
            self.person = person
            self.day = day
            self.status = status
            self.checkedAt = checkedAt
            self.source = source
        }
    }

    /// Read-only point-in-time snapshot built from `AppStore` (or test fixtures).
    public struct DutyDataSnapshot: Sendable {
        public let permission: PermissionState
        public let businessTimezoneID: String
        public let handoverTime: ClockTime
        public let matcher: ShiftMatcher

        // Authoritative source states (strictly separated)
        public let rosterSource: DataSourceStatus
        public let leaveAuthoritySource: DataSourceStatus
        public let tripAuthoritySource: DataSourceStatus
        public let actualAttendanceSource: DataSourceStatus

        // Core schedule / swap / rotation rule data
        public let roster: Roster
        public let mySchedule: [DayKey: String]
        public let publishedDays: Set<DayKey>
        public let teamChanges: [TeamChange]
        public let swapRecords: [SwapRecord]
        public let restBalance: [String: Int]
        public let activeGroupCatalog: [String]
        public let rotationRulesSufficient: Bool
        public let myName: String?

        // Separate authoritative HR / OA / attendance records (when connected)
        public let explicitLeaveRecords: [AuthoritativeLeaveRecord]
        public let explicitTripRecords: [AuthoritativeTripRecord]
        public let explicitAttendanceRecords: [AuthoritativeAttendanceRecord]
        /// True ONLY if the synced roster source itself explicitly includes leave/trip columns (`settings.leaveSources` non-empty).
        public let rosterIncludesLeaveColumns: Bool

        // Broader Duty App domain summaries (so WUMIND can answer ANY Duty App question)
        public let workloadSummary: String?
        public let nextTelemetrySummary: String?
        public let passPlanSummary: String?
        public let meetingOpenSummaries: [String]
        public let siteNotices: [String]
        public let groupNotes: [String: String]
        public let workLogTodayCount: Int

        public init(
            permission: PermissionState = .authorized(roleTitle: "值班人员"),
            businessTimezoneID: String = "Asia/Shanghai",
            handoverTime: ClockTime = ClockTime(hour: 8, minute: 30),
            matcher: ShiftMatcher = ShiftMatcher(types: ShiftType.defaults),
            rosterSource: DataSourceStatus,
            leaveAuthoritySource: DataSourceStatus,
            tripAuthoritySource: DataSourceStatus,
            actualAttendanceSource: DataSourceStatus = .unavailable(reason: "未接入实时考勤打卡系统（计划排班不可倒推实际到岗）"),
            roster: Roster = [:],
            mySchedule: [DayKey: String] = [:],
            publishedDays: Set<DayKey> = [],
            teamChanges: [TeamChange] = [],
            swapRecords: [SwapRecord] = [],
            restBalance: [String: Int] = [:],
            activeGroupCatalog: [String] = [],
            rotationRulesSufficient: Bool = false,
            myName: String? = nil,
            explicitLeaveRecords: [AuthoritativeLeaveRecord] = [],
            explicitTripRecords: [AuthoritativeTripRecord] = [],
            explicitAttendanceRecords: [AuthoritativeAttendanceRecord] = [],
            rosterIncludesLeaveColumns: Bool = false,
            workloadSummary: String? = nil,
            nextTelemetrySummary: String? = nil,
            passPlanSummary: String? = nil,
            meetingOpenSummaries: [String] = [],
            siteNotices: [String] = [],
            groupNotes: [String: String] = [:],
            workLogTodayCount: Int = 0
        ) {
            self.permission = permission
            self.businessTimezoneID = businessTimezoneID
            self.handoverTime = handoverTime
            self.matcher = matcher
            self.rosterSource = rosterSource
            self.leaveAuthoritySource = leaveAuthoritySource
            self.tripAuthoritySource = tripAuthoritySource
            self.actualAttendanceSource = actualAttendanceSource
            self.roster = roster
            self.mySchedule = mySchedule
            self.publishedDays = publishedDays
            self.teamChanges = teamChanges
            self.swapRecords = swapRecords
            self.restBalance = restBalance
            self.activeGroupCatalog = activeGroupCatalog
            self.rotationRulesSufficient = rotationRulesSufficient
            self.myName = myName
            self.explicitLeaveRecords = explicitLeaveRecords
            self.explicitTripRecords = explicitTripRecords
            self.explicitAttendanceRecords = explicitAttendanceRecords
            self.rosterIncludesLeaveColumns = rosterIncludesLeaveColumns
            self.workloadSummary = workloadSummary
            self.nextTelemetrySummary = nextTelemetrySummary
            self.passPlanSummary = passPlanSummary
            self.meetingOpenSummaries = meetingOpenSummaries
            self.siteNotices = siteNotices
            self.groupNotes = groupNotes
            self.workLogTodayCount = workLogTodayCount
        }
    }

    public struct DutyToolCallRecord: Codable, Equatable, Sendable {
        public let toolName: String
        public let arguments: [String: String]
        public let sourceName: String
        public let status: QueryStatus
        public let returnedCount: Int
        public let summary: String

        public init(
            toolName: String,
            arguments: [String: String],
            sourceName: String,
            status: QueryStatus,
            returnedCount: Int,
            summary: String
        ) {
            self.toolName = toolName
            self.arguments = arguments
            self.sourceName = sourceName
            self.status = status
            self.returnedCount = returnedCount
            self.summary = summary
        }
    }

    public struct DutyAnswerSection: Codable, Equatable, Sendable {
        public let topic: SubTopic
        public let title: String
        public let dateLabel: String
        public let status: QueryStatus
        public let sourceLabel: String
        public let headline: String
        public let details: [String]

        public init(
            topic: SubTopic,
            title: String,
            dateLabel: String,
            status: QueryStatus,
            sourceLabel: String,
            headline: String,
            details: [String] = []
        ) {
            self.topic = topic
            self.title = title
            self.dateLabel = dateLabel
            self.status = status
            self.sourceLabel = sourceLabel
            self.headline = headline
            self.details = details
        }
    }

    public struct DutyQueryExecution: Equatable, Sendable {
        public let intent: ParsedIntent
        public let activeHandoverDay: DayKey?
        public let isCrossMidnightWindow: Bool
        public let activeModelLabel: String
        public let exfiltratedToExternalModel: Bool
        public let toolCalls: [DutyToolCallRecord]
        public let sections: [DutyAnswerSection]
        public let formattedReport: String

        public func section(for topic: SubTopic) -> DutyAnswerSection? {
            sections.first { $0.topic == topic }
        }
    }

    // MARK: - Business Calendar Helper

    public static func businessCalendar(timezoneID: String = "Asia/Shanghai") -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timezoneID) ?? TimeZone(secondsFromGMT: 8 * 3600) ?? .current
        cal.locale = Locale(identifier: "zh_CN")
        return cal
    }

    // MARK: - Deterministic Intent Classification (Zero False Triggers on Normal Chat)

    /// Returns a `ParsedIntent` ONLY when the prompt asks about Duty App data/operations.
    /// General chat (coding, weather, PPT, tender monitoring, recipes, mini-apps) returns `nil`.
    public static func classifyIntent(
        prompt: String,
        now: Date = Date(),
        timezoneID: String = "Asia/Shanghai",
        knownPeople: [String] = []
    ) -> ParsedIntent? {
        let q = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }

        // Exclude non-duty creative/general prompts even if they mention "今天" or "项目"
        let dutySignals = [
            "值班", "排班", "遥测", "轮班", "轮休", "哪组休", "哪组不上班", "哪组休息", "谁休息", "谁休",
            "谁请假", "请假", "出差", "调班", "换班", "替班", "待休", "交班", "接班", "在岗", "出勤",
            "值班表", "数传计划", "发计划", "周会问题", "工作留痕", "工作量", "值班负担", "网站公告",
            "各组工作", "组A", "组B", "组C", "组D", "组E", "我今天什么班", "我明天什么班", "什么班", "上什么班", "休不休"
        ]
        let matchedPerson = knownPeople.first { !$0.isEmpty && q.contains($0) }
        let hasDutySignal = dutySignals.contains { q.contains($0) }
            || (matchedPerson != nil && (q.contains("班") || q.contains("休") || q.contains("假") || q.contains("差") || q.contains("在岗")))
        guard hasDutySignal else { return nil }

        let cal = businessCalendar(timezoneID: timezoneID)
        let (resolvedDate, isRelativeToday) = resolveBusinessDate(in: q, now: now, calendar: cal)

        var topics: [SubTopic] = []
        func add(_ topic: SubTopic) {
            if !topics.contains(topic) { topics.append(topic) }
        }

        if q.contains("谁值班") || q.contains("值班") || q.contains("排班") || q.contains("遥测") || q.contains("分工") || q.contains("值班表") {
            add(.onDuty)
        }
        if q.contains("休息") || q.contains("轮休") || q.contains("哪组休") || q.contains("不上班") || q.contains("休班") {
            add(.restingGroups)
        }
        if q.contains("请假") || q.contains("休假") || q.contains("年假") || q.contains("病假") || q.contains("事假") {
            add(.leave)
        }
        if q.contains("出差") {
            add(.trip)
        }
        if q.contains("实际在岗") || q.contains("到岗") || q.contains("出勤") || q.contains("考勤") || q.contains("打卡") {
            add(.actualAttendance)
        }
        if q.contains("调班") || q.contains("换班") || q.contains("替班") || q.contains("欠班") {
            add(.swaps)
        }
        if q.contains("我今天") || q.contains("我明天") || q.contains("我的班") || q.contains("我什么班") || q.contains("待休") || q.contains("我这周") {
            add(.mySchedule)
        }
        if let _ = matchedPerson {
            add(.personSchedule)
        }
        if q.contains("工作量") || q.contains("值班负担") || q.contains("公平") || q.contains("均衡") {
            add(.workload)
        }
        if q.contains("下次遥测") || q.contains("轮到我") || q.contains("预测") || q.contains("排班规律") {
            add(.forecast)
        }
        if q.contains("数传计划") || q.contains("发计划") {
            add(.passPlan)
        }
        if q.contains("周会") {
            add(.meeting)
        }
        if q.contains("公告") || q.contains("各组工作") || q.contains("职责") {
            add(.noticesAndGroupNotes)
        }
        if q.contains("工作留痕") || q.contains("留痕") {
            add(.workLog)
        }
        if q.contains("节假日") || q.contains("放假") {
            add(.holidays)
        }

        if topics.isEmpty {
            add(.onDuty)
        }

        return ParsedIntent(
            resolvedDate: resolvedDate,
            businessTimezoneID: cal.timeZone.identifier,
            isRelativeToday: isRelativeToday,
            topics: topics,
            mentionedPerson: matchedPerson
        )
    }

    /// Parses explicit or relative Chinese dates in the authoritative business calendar.
    public static func resolveBusinessDate(in text: String, now: Date, calendar: Calendar) -> (DayKey, Bool) {
        let today = DayKey(date: now, calendar: calendar)

        // 1. Explicit YYYY-MM-DD or YYYY/MM/DD
        if let regex = try? NSRegularExpression(pattern: #"(20\d{2})[-/年](\d{1,2})[-/月](\d{1,2})"#),
           let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r1 = Range(m.range(at: 1), in: text),
           let r2 = Range(m.range(at: 2), in: text),
           let r3 = Range(m.range(at: 3), in: text),
           let y = Int(text[r1]), let mo = Int(text[r2]), let d = Int(text[r3]),
           (1...12).contains(mo), (1...31).contains(d) {
            let parsed = DayKey(year: y, month: mo, day: d)
            return (parsed, parsed == today)
        }

        // 2. Explicit M月D日 / M月D号
        if let regex = try? NSRegularExpression(pattern: #"(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]?"#),
           let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r1 = Range(m.range(at: 1), in: text),
           let r2 = Range(m.range(at: 2), in: text),
           let mo = Int(text[r1]), let d = Int(text[r2]),
           (1...12).contains(mo), (1...31).contains(d) {
            let parsed = DayKey(year: today.year, month: mo, day: d)
            return (parsed, parsed == today)
        }

        // 3. Relative Chinese expressions
        if text.contains("后天") { return (today.adding(days: 2, calendar: calendar), false) }
        if text.contains("明天") || text.contains("明日") { return (today.adding(days: 1, calendar: calendar), false) }
        if text.contains("前天") { return (today.adding(days: -2, calendar: calendar), false) }
        if text.contains("昨天") || text.contains("昨日") { return (today.adding(days: -1, calendar: calendar), false) }

        return (today, true)
    }

    // MARK: - Programmatic Execution Engine

    /// Executes scoped read-only Duty App queries strictly inside the App (zero external model exfiltration).
    /// Works identically regardless of which AI model (`activeModelLabel`) the user currently selected.
    public static func execute(
        prompt: String,
        snapshot: DutyDataSnapshot,
        now: Date = Date(),
        activeModelLabel: String = "DeepSeek"
    ) -> DutyQueryExecution? {
        let people = Array(snapshot.roster.keys)
        guard let intent = classifyIntent(
            prompt: prompt,
            now: now,
            timezoneID: snapshot.businessTimezoneID,
            knownPeople: people
        ) else {
            return nil
        }

        let cal = businessCalendar(timezoneID: snapshot.businessTimezoneID)
        let handoverDay = DutyWorkbench.rosterDay(asOf: now, handover: snapshot.handoverTime, calendar: cal)
        let isCrossMidnight = intent.isRelativeToday && handoverDay != nil && handoverDay != intent.resolvedDate
        let dateStr = intent.resolvedDate.description

        // 1. Permission boundary check FIRST (e.g., External User is strictly denied)
        if case .denied(let reason) = snapshot.permission {
            let call = DutyToolCallRecord(
                toolName: "duty_permission_check",
                arguments: ["date": dateStr, "timezone": intent.businessTimezoneID],
                sourceName: "App 权限边界校验",
                status: .unauthorizedOrUnconnected,
                returnedCount: 0,
                summary: reason
            )
            let sec = DutyAnswerSection(
                topic: intent.topics.first ?? .onDuty,
                title: "权限不足",
                dateLabel: dateStr,
                status: .unauthorizedOrUnconnected,
                sourceLabel: "App 权限边界校验",
                headline: "无权查询内部值班与排班数据：\(reason)",
                details: ["当前账号处于外部隔离或无授权边界，未读取任何内部排班、调班或请假记录。"]
            )
            let report = formatReport(
                intent: intent,
                activeHandoverDay: handoverDay,
                isCrossMidnight: isCrossMidnight,
                handoverTime: snapshot.handoverTime,
                sections: [sec],
                toolCalls: [call],
                activeModelLabel: activeModelLabel
            )
            return DutyQueryExecution(
                intent: intent,
                activeHandoverDay: handoverDay,
                isCrossMidnightWindow: isCrossMidnight,
                activeModelLabel: activeModelLabel,
                exfiltratedToExternalModel: false,
                toolCalls: [call],
                sections: [sec],
                formattedReport: report
            )
        }

        var toolCalls: [DutyToolCallRecord] = []
        var sections: [DutyAnswerSection] = []

        for topic in intent.topics {
            switch topic {
            case .onDuty:
                let (call, sec) = queryOnDuty(
                    day: intent.resolvedDate,
                    handoverDay: isCrossMidnight ? handoverDay : nil,
                    snapshot: snapshot
                )
                toolCalls.append(call)
                sections.append(sec)

            case .restingGroups:
                let (call, sec) = queryRestingGroups(day: intent.resolvedDate, snapshot: snapshot)
                toolCalls.append(call)
                sections.append(sec)

            case .leave:
                let (call, sec) = queryLeave(day: intent.resolvedDate, snapshot: snapshot)
                toolCalls.append(call)
                sections.append(sec)

            case .trip:
                let (call, sec) = queryTrip(day: intent.resolvedDate, snapshot: snapshot)
                toolCalls.append(call)
                sections.append(sec)

            case .actualAttendance:
                let (call, sec) = queryActualAttendance(day: intent.resolvedDate, snapshot: snapshot)
                toolCalls.append(call)
                sections.append(sec)

            case .swaps:
                let (call, sec) = querySwaps(day: intent.resolvedDate, snapshot: snapshot)
                toolCalls.append(call)
                sections.append(sec)

            case .mySchedule:
                let (call, sec) = queryMySchedule(day: intent.resolvedDate, snapshot: snapshot)
                toolCalls.append(call)
                sections.append(sec)

            case .personSchedule:
                if let person = intent.mentionedPerson {
                    let (call, sec) = queryPersonSchedule(person: person, day: intent.resolvedDate, snapshot: snapshot)
                    toolCalls.append(call)
                    sections.append(sec)
                }

            case .workload:
                let (call, sec) = querySummaryTopic(
                    topic: .workload,
                    toolName: "duty_workload_lookup",
                    title: "工作量与值班负担",
                    sourceName: "App 工作量统计引擎",
                    day: intent.resolvedDate,
                    value: snapshot.workloadSummary,
                    missingReason: "暂无本月工作量统计，请先同步全员排班。"
                )
                toolCalls.append(call)
                sections.append(sec)

            case .forecast:
                let (call, sec) = querySummaryTopic(
                    topic: .forecast,
                    toolName: "duty_forecast_lookup",
                    title: "下次遥测与轮班推算",
                    sourceName: "App 遥测推算引擎",
                    day: intent.resolvedDate,
                    value: snapshot.nextTelemetrySummary,
                    missingReason: "历史排班不足，暂无法推算下次遥测日期。"
                )
                toolCalls.append(call)
                sections.append(sec)

            case .passPlan:
                let (call, sec) = querySummaryTopic(
                    topic: .passPlan,
                    toolName: "duty_passplan_lookup",
                    title: "发数传计划状态",
                    sourceName: "App 数传计划会话",
                    day: intent.resolvedDate,
                    value: snapshot.passPlanSummary,
                    missingReason: "当前内存批次暂无已识别的数传计划。"
                )
                toolCalls.append(call)
                sections.append(sec)

            case .meeting:
                let status: QueryStatus = snapshot.meetingOpenSummaries.isEmpty ? .checkedEmpty : .confirmed
                let call = DutyToolCallRecord(
                    toolName: "duty_meeting_issues_lookup",
                    arguments: ["date": dateStr],
                    sourceName: "App 周会问题追踪",
                    status: status,
                    returnedCount: snapshot.meetingOpenSummaries.count,
                    summary: status == .confirmed ? "共 \(snapshot.meetingOpenSummaries.count) 条未解决周会问题" : "当前无未解决周会问题"
                )
                let sec = DutyAnswerSection(
                    topic: .meeting,
                    title: "周会未解决问题",
                    dateLabel: dateStr,
                    status: status,
                    sourceLabel: "App 周会问题追踪",
                    headline: status == .confirmed ? "当前挂起 \(snapshot.meetingOpenSummaries.count) 项未解决周会问题" : "已查周会记录，当前确无未解决问题",
                    details: Array(snapshot.meetingOpenSummaries.prefix(8))
                )
                toolCalls.append(call)
                sections.append(sec)

            case .noticesAndGroupNotes:
                let hasAny = !snapshot.siteNotices.isEmpty || !snapshot.groupNotes.isEmpty
                let status: QueryStatus = hasAny ? .confirmed : .checkedEmpty
                var details: [String] = snapshot.siteNotices.prefix(5).map { "公告：\($0)" }
                for key in snapshot.groupNotes.keys.sorted().prefix(6) {
                    if let val = snapshot.groupNotes[key] {
                        details.append("\(key)：\(String(val.prefix(120)))")
                    }
                }
                let call = DutyToolCallRecord(
                    toolName: "duty_notices_and_notes_lookup",
                    arguments: ["date": dateStr],
                    sourceName: "App 网站公告与各组工作内容",
                    status: status,
                    returnedCount: details.count,
                    summary: hasAny ? "读取到 \(snapshot.siteNotices.count) 条公告、\(snapshot.groupNotes.count) 组说明" : "暂无网站公告与组别说明"
                )
                let sec = DutyAnswerSection(
                    topic: .noticesAndGroupNotes,
                    title: "网站公告与各组职责",
                    dateLabel: dateStr,
                    status: status,
                    sourceLabel: "App 网站公告与各组工作内容",
                    headline: hasAny ? "已查到 \(snapshot.siteNotices.count) 条公告、\(snapshot.groupNotes.count) 组职责说明" : "已查本机缓存，当前确无公告或组别说明",
                    details: details
                )
                toolCalls.append(call)
                sections.append(sec)

            case .workLog:
                let status: QueryStatus = snapshot.workLogTodayCount > 0 ? .confirmed : .checkedEmpty
                let call = DutyToolCallRecord(
                    toolName: "duty_worklog_lookup",
                    arguments: ["date": dateStr],
                    sourceName: "App 本机工作留痕",
                    status: status,
                    returnedCount: snapshot.workLogTodayCount,
                    summary: "当日留痕 \(snapshot.workLogTodayCount) 条"
                )
                let sec = DutyAnswerSection(
                    topic: .workLog,
                    title: "工作留痕",
                    dateLabel: dateStr,
                    status: status,
                    sourceLabel: "App 本机工作留痕",
                    headline: snapshot.workLogTodayCount > 0 ? "当天已记录 \(snapshot.workLogTodayCount) 条本机工作留痕" : "已查本机留痕，当天确无记录",
                    details: []
                )
                toolCalls.append(call)
                sections.append(sec)

            case .holidays:
                let isHol = ChinaHolidays.isHoliday(intent.resolvedDate)
                let isWork = ChinaHolidays.isWorkday(intent.resolvedDate, calendar: cal)
                let call = DutyToolCallRecord(
                    toolName: "duty_holidays_lookup",
                    arguments: ["date": dateStr],
                    sourceName: "App 法定节假日规则库",
                    status: .confirmed,
                    returnedCount: 1,
                    summary: isHol ? "法定节假日" : (isWork ? "工作日" : "周末休息日")
                )
                let sec = DutyAnswerSection(
                    topic: .holidays,
                    title: "节假日属性",
                    dateLabel: dateStr,
                    status: .confirmed,
                    sourceLabel: "App 法定节假日规则库",
                    headline: "\(dateStr) 为\(isHol ? "法定节假日" : (isWork ? "正常工作日" : "周末非工作日"))",
                    details: []
                )
                toolCalls.append(call)
                sections.append(sec)
            }
        }

        // Order confirmed answers FIRST so the user immediately sees verified facts before unconfirmed items!
        let orderedSections = sections.sorted { a, b in
            priority(a.status) < priority(b.status)
        }

        let report = formatReport(
            intent: intent,
            activeHandoverDay: handoverDay,
            isCrossMidnight: isCrossMidnight,
            handoverTime: snapshot.handoverTime,
            sections: orderedSections,
            toolCalls: toolCalls,
            activeModelLabel: activeModelLabel
        )

        return DutyQueryExecution(
            intent: intent,
            activeHandoverDay: handoverDay,
            isCrossMidnightWindow: isCrossMidnight,
            activeModelLabel: activeModelLabel,
            exfiltratedToExternalModel: false,
            toolCalls: toolCalls,
            sections: orderedSections,
            formattedReport: report
        )
    }

    private static func priority(_ status: QueryStatus) -> Int {
        switch status {
        case .confirmed: return 0
        case .checkedEmpty: return 1
        case .unauthorizedOrUnconnected: return 2
        case .queryFailed: return 3
        }
    }

    // MARK: - Sub-Query Implementations

    private static func queryOnDuty(
        day: DayKey,
        handoverDay: DayKey?,
        snapshot: DutyDataSnapshot
    ) -> (DutyToolCallRecord, DutyAnswerSection) {
        let dateStr = day.description
        switch snapshot.rosterSource {
        case .unavailable(let reason):
            let call = DutyToolCallRecord(
                toolName: "duty_roster_lookup",
                arguments: ["date": dateStr],
                sourceName: "App 全员排班表",
                status: .unauthorizedOrUnconnected,
                returnedCount: 0,
                summary: reason
            )
            let sec = DutyAnswerSection(
                topic: .onDuty,
                title: "计划值班与岗位排班",
                dateLabel: dateStr,
                status: .unauthorizedOrUnconnected,
                sourceLabel: "App 全员排班表",
                headline: "排班数据源未接入或未同步：\(reason)",
                details: []
            )
            return (call, sec)

        case .failed(let src, let err):
            let call = DutyToolCallRecord(
                toolName: "duty_roster_lookup",
                arguments: ["date": dateStr],
                sourceName: src,
                status: .queryFailed,
                returnedCount: 0,
                summary: err
            )
            let sec = DutyAnswerSection(
                topic: .onDuty,
                title: "计划值班与岗位排班",
                dateLabel: dateStr,
                status: .queryFailed,
                sourceLabel: src,
                headline: "查询排班表失败：\(err)",
                details: []
            )
            return (call, sec)

        case .available(let src, _):
            let entries = postsForDay(day, snapshot: snapshot)
            let daySwaps = snapshot.teamChanges.filter { $0.day == day }
            var details: [String] = []

            // Cross-midnight active overnight telemetry window (e.g. 01:30 AM before 08:30 handover)
            if let prevDay = handoverDay {
                let prevEntries = postsForDay(prevDay, snapshot: snapshot)
                let overnightTelemetry = prevEntries.filter { DutyWorkbench.isStandardTelemetryPost($0.post, matcher: snapshot.matcher) }
                if !overnightTelemetry.isEmpty {
                    let names = overnightTelemetry.flatMap(\.names).joined(separator: "、")
                    details.append("【跨午夜当前值守班次（\(prevDay.description) \(snapshot.handoverTime.text) → \(dateStr) \(snapshot.handoverTime.text)）】遥测值班：\(names)")
                } else {
                    details.append("【跨午夜窗口提示】当前时间早于今日交班时刻 \(snapshot.handoverTime.text)，上一班日期为 \(prevDay.description)（未查到上一班标准遥测记录）。")
                }
            }

            for item in entries {
                details.append("\(item.post)：\(item.names.joined(separator: "、"))")
            }

            if !daySwaps.isEmpty {
                for sw in daySwaps {
                    details.append("临时调班记录：\(sw.summary)")
                }
            }

            let isEmpty = entries.isEmpty && (handoverDay == nil || details.isEmpty)
            let status: QueryStatus = isEmpty ? .checkedEmpty : .confirmed
            let telemetry = entries.filter { WorkloadCounter.isDuty($0.post) }.flatMap(\.names)
            let headline: String
            if isEmpty {
                headline = snapshot.publishedDays.contains(day)
                    ? "\(dateStr) 已查全员排班表，当天确无岗位排班记录。"
                    : "\(dateStr) 全员排班表暂未发布该日排班，确无已排记录。"
            } else if !telemetry.isEmpty {
                headline = "\(dateStr) 计划遥测值班：\(telemetry.joined(separator: "、"))（共 \(entries.count) 个岗位已排班\(daySwaps.isEmpty ? "" : "，含 \(daySwaps.count) 条临时调班")）"
            } else {
                headline = "\(dateStr) 共查到 \(entries.count) 个在排岗位（\(entries.map(\.post).joined(separator: "、"))\(daySwaps.isEmpty ? "" : "，含 \(daySwaps.count) 条临时调班")）"
            }

            let call = DutyToolCallRecord(
                toolName: "duty_roster_lookup",
                arguments: [
                    "date": dateStr,
                    "cross_midnight_handover_day": handoverDay?.description ?? "none",
                    "include_swaps": "true"
                ],
                sourceName: src,
                status: status,
                returnedCount: entries.count + daySwaps.count,
                summary: headline
            )
            let sec = DutyAnswerSection(
                topic: .onDuty,
                title: "计划值班与岗位排班（不含实际打卡）",
                dateLabel: dateStr,
                status: status,
                sourceLabel: src + (daySwaps.isEmpty ? "" : " + 临时调班记录"),
                headline: headline,
                details: details
            )
            return (call, sec)
        }
    }

    private static func queryRestingGroups(
        day: DayKey,
        snapshot: DutyDataSnapshot
    ) -> (DutyToolCallRecord, DutyAnswerSection) {
        let dateStr = day.description
        switch snapshot.rosterSource {
        case .unavailable(let reason):
            return (
                DutyToolCallRecord(toolName: "duty_resting_groups_lookup", arguments: ["date": dateStr], sourceName: "App 全员排班与轮班规则", status: .unauthorizedOrUnconnected, returnedCount: 0, summary: reason),
                DutyAnswerSection(topic: .restingGroups, title: "计划休息组 / 休息人员", dateLabel: dateStr, status: .unauthorizedOrUnconnected, sourceLabel: "App 全员排班与轮班规则", headline: "排班源不可用，无法判断休息组：\(reason)")
            )
        case .failed(let src, let err):
            return (
                DutyToolCallRecord(toolName: "duty_resting_groups_lookup", arguments: ["date": dateStr], sourceName: src, status: .queryFailed, returnedCount: 0, summary: err),
                DutyAnswerSection(topic: .restingGroups, title: "计划休息组 / 休息人员", dateLabel: dateStr, status: .queryFailed, sourceLabel: src, headline: "查询休息组失败：\(err)")
            )
        case .available(let src, _):
            // 1. Check explicit literal rest / comp-leave / handover-rest entries on `day`
            var explicitRestPeople: [String] = []
            var scheduledGroups = Set<String>()
            for (person, days) in snapshot.roster {
                guard let raw = days[day] else { continue }
                let names = DayRules.names(raw, matcher: snapshot.matcher)
                for n in names {
                    let kind = DayRules.part(n, matcher: snapshot.matcher)
                    if kind == .rest || kind == .compLeave || kind == .handover {
                        explicitRestPeople.append("\(person)（\(n)）")
                    }
                    if GroupNotes.isGroup(n) {
                        scheduledGroups.insert(normalizedGroupName(n))
                    }
                }
            }
            explicitRestPeople.sort()

            // 2. Derive planned resting groups from rotation catalog ONLY when rules are sufficient
            let catalog = snapshot.activeGroupCatalog.map(normalizedGroupName).filter { !$0.isEmpty }
            var seenGroups = Set<String>()
            let uniqueCatalog = catalog.filter { seenGroups.insert($0).inserted }
            let canDerive = snapshot.rotationRulesSufficient && uniqueCatalog.count >= 2 && !scheduledGroups.isEmpty
            let derivedRestingGroups = canDerive ? uniqueCatalog.filter { !scheduledGroups.contains($0) } : []

            if !explicitRestPeople.isEmpty || !derivedRestingGroups.isEmpty {
                var details: [String] = []
                if !derivedRestingGroups.isEmpty {
                    details.append("按组别轮班规则推导的计划轮休组：\(derivedRestingGroups.joined(separator: "、"))（全组清单：\(uniqueCatalog.joined(separator: "、"))；当日在排组：\(scheduledGroups.sorted().joined(separator: "、"))）")
                }
                if !explicitRestPeople.isEmpty {
                    details.append("排班表显式标注休息/调休/交接前：\(explicitRestPeople.joined(separator: "、"))")
                }
                let headline: String
                if !derivedRestingGroups.isEmpty && explicitRestPeople.isEmpty {
                    headline = "排班表未写「休息」字样；据轮班规则推导，\(dateStr) 计划轮休组为：\(derivedRestingGroups.joined(separator: "、"))"
                } else if !derivedRestingGroups.isEmpty {
                    headline = "\(dateStr) 计划轮休组：\(derivedRestingGroups.joined(separator: "、"))；另有 \(explicitRestPeople.count) 人显式标休"
                } else {
                    headline = "\(dateStr) 排班表显式标休人员：\(explicitRestPeople.joined(separator: "、"))"
                }
                let call = DutyToolCallRecord(
                    toolName: "duty_resting_groups_lookup",
                    arguments: ["date": dateStr, "rotation_rules_sufficient": canDerive ? "true" : "false"],
                    sourceName: canDerive ? "\(src) + 轮班组别规则" : src,
                    status: .confirmed,
                    returnedCount: derivedRestingGroups.count + explicitRestPeople.count,
                    summary: headline
                )
                return (call, DutyAnswerSection(
                    topic: .restingGroups,
                    title: "计划休息组 / 标休人员",
                    dateLabel: dateStr,
                    status: .confirmed,
                    sourceLabel: canDerive ? "\(src) + 轮班组别规则" : src,
                    headline: headline,
                    details: details
                ))
            }

            // Neither explicit "休息" nor sufficient rotation rules to infer resting groups!
            // CRITICAL: Never claim "nobody is resting" just because the word "休息" wasn't found!
            if canDerive && derivedRestingGroups.isEmpty {
                let headline = "\(dateStr) 已查全员排班与轮班规则：全部已知组别（\(uniqueCatalog.joined(separator: "、"))）均有排班，确无轮休组与标休人员。"
                let call = DutyToolCallRecord(
                    toolName: "duty_resting_groups_lookup",
                    arguments: ["date": dateStr, "rotation_rules_sufficient": "true"],
                    sourceName: "\(src) + 轮班组别规则",
                    status: .checkedEmpty,
                    returnedCount: 0,
                    summary: headline
                )
                return (call, DutyAnswerSection(
                    topic: .restingGroups,
                    title: "计划休息组 / 标休人员",
                    dateLabel: dateStr,
                    status: .checkedEmpty,
                    sourceLabel: "\(src) + 轮班组别规则",
                    headline: headline,
                    details: ["全部已知组别（\(uniqueCatalog.joined(separator: "、"))）当日均有排班。"]
                ))
            }

            let reason = "当日排班表未见「休息」字样，且现有组别轮班规则不足以反推计划轮休组，不能推定无人休息。"
            let call = DutyToolCallRecord(
                toolName: "duty_resting_groups_lookup",
                arguments: ["date": dateStr, "rotation_rules_sufficient": "false"],
                sourceName: "\(src)（轮班规则不足）",
                status: .unauthorizedOrUnconnected,
                returnedCount: 0,
                summary: reason
            )
            return (call, DutyAnswerSection(
                topic: .restingGroups,
                title: "计划休息组 / 标休人员",
                dateLabel: dateStr,
                status: .unauthorizedOrUnconnected,
                sourceLabel: "\(src)（轮班规则不足）",
                headline: "未确认：\(reason)",
                details: ["提示：没看到「休息」字样不等于没人休息；完善各组清单与轮班规则后才可推导计划休息组。"]
            ))
        }
    }

    private static func queryLeave(
        day: DayKey,
        snapshot: DutyDataSnapshot
    ) -> (DutyToolCallRecord, DutyAnswerSection) {
        let dateStr = day.description
        switch snapshot.leaveAuthoritySource {
        case .unavailable(let reason):
            return (
                DutyToolCallRecord(toolName: "duty_leave_records_lookup", arguments: ["date": dateStr], sourceName: "权威请假记录源", status: .unauthorizedOrUnconnected, returnedCount: 0, summary: reason),
                DutyAnswerSection(
                    topic: .leave,
                    title: "请假记录",
                    dateLabel: dateStr,
                    status: .unauthorizedOrUnconnected,
                    sourceLabel: "权威请假记录源（未接入）",
                    headline: "未确认：\(reason)",
                    details: ["不可从计划排班倒推谁请假；请核对 OA / 考勤系统或确认排班源已含请假列。"]
                )
            )
        case .failed(let src, let err):
            return (
                DutyToolCallRecord(toolName: "duty_leave_records_lookup", arguments: ["date": dateStr], sourceName: src, status: .queryFailed, returnedCount: 0, summary: err),
                DutyAnswerSection(topic: .leave, title: "请假记录", dateLabel: dateStr, status: .queryFailed, sourceLabel: src, headline: "查询请假记录失败：\(err)")
            )
        case .available(let src, _):
            var items: [String] = snapshot.explicitLeaveRecords
                .filter { $0.day == day }
                .map { "\($0.person)：\($0.category)（来源：\($0.source)）" }
            if snapshot.rosterIncludesLeaveColumns {
                for (person, days) in snapshot.roster {
                    guard let raw = days[day] else { continue }
                    let leaveParts = DayRules.names(raw, matcher: snapshot.matcher)
                        .filter { DayRules.part($0, matcher: snapshot.matcher) == .leave }
                    if !leaveParts.isEmpty && !items.contains(where: { $0.hasPrefix("\(person)：") }) {
                        items.append("\(person)：\(leaveParts.joined(separator: "、"))（来源：\(src)）")
                    }
                }
            }
            items.sort()
            let status: QueryStatus = items.isEmpty ? .checkedEmpty : .confirmed
            let headline = items.isEmpty
                ? "\(dateStr) 已查权威请假来源（\(src)），当天确无请假记录。"
                : "\(dateStr) 共查到 \(items.count) 人请假：\(items.joined(separator: "；"))"
            return (
                DutyToolCallRecord(toolName: "duty_leave_records_lookup", arguments: ["date": dateStr], sourceName: src, status: status, returnedCount: items.count, summary: headline),
                DutyAnswerSection(topic: .leave, title: "请假记录", dateLabel: dateStr, status: status, sourceLabel: src, headline: headline, details: items)
            )
        }
    }

    private static func queryTrip(
        day: DayKey,
        snapshot: DutyDataSnapshot
    ) -> (DutyToolCallRecord, DutyAnswerSection) {
        let dateStr = day.description
        switch snapshot.tripAuthoritySource {
        case .unavailable(let reason):
            return (
                DutyToolCallRecord(toolName: "duty_trip_records_lookup", arguments: ["date": dateStr], sourceName: "权威出差记录源", status: .unauthorizedOrUnconnected, returnedCount: 0, summary: reason),
                DutyAnswerSection(
                    topic: .trip,
                    title: "出差记录",
                    dateLabel: dateStr,
                    status: .unauthorizedOrUnconnected,
                    sourceLabel: "权威出差记录源（未接入）",
                    headline: "未确认：\(reason)",
                    details: ["不可仅凭计划排班推定无人出差。"]
                )
            )
        case .failed(let src, let err):
            return (
                DutyToolCallRecord(toolName: "duty_trip_records_lookup", arguments: ["date": dateStr], sourceName: src, status: .queryFailed, returnedCount: 0, summary: err),
                DutyAnswerSection(topic: .trip, title: "出差记录", dateLabel: dateStr, status: .queryFailed, sourceLabel: src, headline: "查询出差记录失败：\(err)")
            )
        case .available(let src, _):
            var items: [String] = snapshot.explicitTripRecords
                .filter { $0.day == day }
                .map { "\($0.person)：\($0.destinationOrNote)（来源：\($0.source)）" }
            if snapshot.rosterIncludesLeaveColumns {
                for (person, days) in snapshot.roster {
                    guard let raw = days[day] else { continue }
                    let tripParts = DayRules.names(raw, matcher: snapshot.matcher)
                        .filter { DayRules.part($0, matcher: snapshot.matcher) == .trip }
                    if !tripParts.isEmpty && !items.contains(where: { $0.hasPrefix("\(person)：") }) {
                        items.append("\(person)：\(tripParts.joined(separator: "、"))（来源：\(src)）")
                    }
                }
            }
            items.sort()
            let status: QueryStatus = items.isEmpty ? .checkedEmpty : .confirmed
            let headline = items.isEmpty
                ? "\(dateStr) 已查权威出差来源（\(src)），当天确无出差记录。"
                : "\(dateStr) 共查到 \(items.count) 人出差：\(items.joined(separator: "；"))"
            return (
                DutyToolCallRecord(toolName: "duty_trip_records_lookup", arguments: ["date": dateStr], sourceName: src, status: status, returnedCount: items.count, summary: headline),
                DutyAnswerSection(topic: .trip, title: "出差记录", dateLabel: dateStr, status: status, sourceLabel: src, headline: headline, details: items)
            )
        }
    }

    private static func queryActualAttendance(
        day: DayKey,
        snapshot: DutyDataSnapshot
    ) -> (DutyToolCallRecord, DutyAnswerSection) {
        let dateStr = day.description
        switch snapshot.actualAttendanceSource {
        case .unavailable(let reason):
            return (
                DutyToolCallRecord(toolName: "duty_actual_attendance_lookup", arguments: ["date": dateStr], sourceName: "实际在岗/打卡记录源", status: .unauthorizedOrUnconnected, returnedCount: 0, summary: reason),
                DutyAnswerSection(
                    topic: .actualAttendance,
                    title: "实际在岗/打卡记录",
                    dateLabel: dateStr,
                    status: .unauthorizedOrUnconnected,
                    sourceLabel: "实际在岗/打卡记录源（未接入）",
                    headline: "未确认：\(reason)",
                    details: ["排班表仅代表计划安排，不代表实际刷卡到岗状态。"]
                )
            )
        case .failed(let src, let err):
            return (
                DutyToolCallRecord(toolName: "duty_actual_attendance_lookup", arguments: ["date": dateStr], sourceName: src, status: .queryFailed, returnedCount: 0, summary: err),
                DutyAnswerSection(topic: .actualAttendance, title: "实际在岗/打卡记录", dateLabel: dateStr, status: .queryFailed, sourceLabel: src, headline: "查询实际在岗记录失败：\(err)")
            )
        case .available(let src, _):
            let recs = snapshot.explicitAttendanceRecords.filter { $0.day == day }
            let details = recs.map { "\($0.person)：\($0.status)（\($0.checkedAt)，来源：\($0.source)）" }
            let status: QueryStatus = recs.isEmpty ? .checkedEmpty : .confirmed
            let headline = recs.isEmpty
                ? "\(dateStr) 已查实际在岗源（\(src)），当天确无打卡/在岗记录。"
                : "\(dateStr) 实际在岗记录 \(recs.count) 条"
            return (
                DutyToolCallRecord(toolName: "duty_actual_attendance_lookup", arguments: ["date": dateStr], sourceName: src, status: status, returnedCount: recs.count, summary: headline),
                DutyAnswerSection(topic: .actualAttendance, title: "实际在岗/打卡记录", dateLabel: dateStr, status: status, sourceLabel: src, headline: headline, details: details)
            )
        }
    }

    private static func querySwaps(
        day: DayKey,
        snapshot: DutyDataSnapshot
    ) -> (DutyToolCallRecord, DutyAnswerSection) {
        let dateStr = day.description
        let dayChanges = snapshot.teamChanges.filter { $0.day == day }
        let balances = SwapLedger.balances(snapshot.swapRecords).filter { $0.value != 0 }
            .sorted { abs($0.value) > abs($1.value) }
        var details = dayChanges.map { "当日调班：\($0.summary)" }
        for (person, delta) in balances {
            details.append("换班账本：\(person) \(delta > 0 ? "欠我 \(delta) 天" : "我欠 \(-delta) 天")")
        }
        let status: QueryStatus = details.isEmpty ? .checkedEmpty : .confirmed
        let headline = details.isEmpty
            ? "\(dateStr) 已查调班与换班账本，当天无临时调班且无未结清换班。"
            : "\(dateStr) 查到 \(dayChanges.count) 条当日调班、\(balances.count) 人未还清换班账本"
        return (
            DutyToolCallRecord(toolName: "duty_swaps_lookup", arguments: ["date": dateStr], sourceName: "App 调班与换班账本", status: status, returnedCount: details.count, summary: headline),
            DutyAnswerSection(topic: .swaps, title: "调班与换班账本", dateLabel: dateStr, status: status, sourceLabel: "App 调班与换班账本", headline: headline, details: details)
        )
    }

    private static func queryMySchedule(
        day: DayKey,
        snapshot: DutyDataSnapshot
    ) -> (DutyToolCallRecord, DutyAnswerSection) {
        let dateStr = day.description
        let shift = snapshot.mySchedule[day]
        let rest = snapshot.myName.flatMap { snapshot.restBalance[$0] }
        let status: QueryStatus = (shift != nil || rest != nil) ? .confirmed : .checkedEmpty
        var details: [String] = []
        if let shift { details.append("\(dateStr) 本人排班：\(snapshot.matcher.displayName(shift))") }
        if let rest { details.append("当前待休余额：\(rest) 天") }
        let headline = shift.map { "\(dateStr) 本人计划班次：\(snapshot.matcher.displayName($0))" }
            ?? "\(dateStr) 本人排班表无岗位记录"
        return (
            DutyToolCallRecord(toolName: "duty_my_schedule_lookup", arguments: ["date": dateStr], sourceName: "App 本人排班与待休余额", status: status, returnedCount: details.count, summary: headline),
            DutyAnswerSection(topic: .mySchedule, title: "本人排班与待休", dateLabel: dateStr, status: status, sourceLabel: "App 本人排班与待休余额", headline: headline, details: details)
        )
    }

    private static func queryPersonSchedule(
        person: String,
        day: DayKey,
        snapshot: DutyDataSnapshot
    ) -> (DutyToolCallRecord, DutyAnswerSection) {
        let dateStr = day.description
        let shift = snapshot.roster[person]?[day]
        let status: QueryStatus = shift != nil ? .confirmed : .checkedEmpty
        let headline = shift.map { "\(dateStr) \(person) 计划排班：\(snapshot.matcher.displayName($0))" }
            ?? "\(dateStr) 全员排班表中未查到 \(person) 的排班记录"
        return (
            DutyToolCallRecord(toolName: "duty_person_schedule_lookup", arguments: ["person": person, "date": dateStr], sourceName: "App 全员排班表", status: status, returnedCount: shift == nil ? 0 : 1, summary: headline),
            DutyAnswerSection(topic: .personSchedule, title: "\(person) 排班查询", dateLabel: dateStr, status: status, sourceLabel: "App 全员排班表", headline: headline)
        )
    }

    private static func querySummaryTopic(
        topic: SubTopic,
        toolName: String,
        title: String,
        sourceName: String,
        day: DayKey,
        value: String?,
        missingReason: String
    ) -> (DutyToolCallRecord, DutyAnswerSection) {
        let dateStr = day.description
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let status: QueryStatus = trimmed.isEmpty ? .checkedEmpty : .confirmed
        let headline = trimmed.isEmpty ? missingReason : trimmed
        return (
            DutyToolCallRecord(toolName: toolName, arguments: ["date": dateStr], sourceName: sourceName, status: status, returnedCount: trimmed.isEmpty ? 0 : 1, summary: headline),
            DutyAnswerSection(topic: topic, title: title, dateLabel: dateStr, status: status, sourceLabel: sourceName, headline: headline)
        )
    }

    // MARK: - Helpers & Formatting

    private static func postsForDay(_ day: DayKey, snapshot: DutyDataSnapshot) -> [(post: String, names: [String])] {
        var byPost: [String: [String]] = [:]
        for (person, days) in snapshot.roster {
            guard let raw = days[day] else { continue }
            for post in DayRules.posts(raw, matcher: snapshot.matcher) {
                byPost[post, default: []].append(person)
            }
        }
        return byPost
            .map { (post: $0.key, names: $0.value.sorted()) }
            .sorted { a, b in
                let da = WorkloadCounter.isDuty(a.post), db = WorkloadCounter.isDuty(b.post)
                if da != db { return da }
                return a.post < b.post
            }
    }

    private static func normalizedGroupName(_ raw: String) -> String {
        raw.filter { !$0.isWhitespace }.uppercased()
    }

    private static func formatReport(
        intent: ParsedIntent,
        activeHandoverDay: DayKey?,
        isCrossMidnight: Bool,
        handoverTime: ClockTime,
        sections: [DutyAnswerSection],
        toolCalls: [DutyToolCallRecord],
        activeModelLabel: String
    ) -> String {
        var lines: [String] = []
        lines.append("### 值班业务查询结果（\(intent.resolvedDate.description) · 时区 \(intent.businessTimezoneID)）")
        if isCrossMidnight, let prev = activeHandoverDay {
            lines.append("> 跨午夜值班提醒：当前处于交班时刻（\(handoverTime.text)）之前，正在值守的跨日夜班归属日期为 **\(prev.description)**，以下同时列出当前值守班次与 \(intent.resolvedDate.description) 当日排班。")
        }

        for sec in sections {
            lines.append("")
            lines.append("**\(sec.title)**｜状态：`\(sec.status.chineseLabel)`｜日期：\(sec.dateLabel)｜来源：\(sec.sourceLabel)")
            lines.append("- \(sec.headline)")
            for detail in sec.details {
                lines.append("  - \(detail)")
            }
        }

        lines.append("")
        lines.append("---")
        lines.append("**实际查询与核对记录**（App 内网只读引擎直查 · 独立于模型 `\(activeModelLabel)` · 内网数据未发送至任何外部大模型）")
        for (idx, call) in toolCalls.enumerated() {
            let argsStr = call.arguments.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            lines.append("\(idx + 1). `\(call.toolName)(\(argsStr))` → **\(call.status.chineseLabel)**｜来源：\(call.sourceName)｜命中 \(call.returnedCount) 条")
        }
        return lines.joined(separator: "\n")
    }
}
