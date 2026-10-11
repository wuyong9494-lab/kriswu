import Foundation

/// 工作量均衡分析：有组别（组A–E）排班的人，这段时间工作量是否差不多，谁干得多、谁干得少。
/// 工作量按 WorkloadCounter 的规则算（值班 + 节假日值班调休 + 日常 + 出差）。
public struct BalanceReport: Equatable {
    public enum Level: String { case more = "偏多", less = "偏少", normal = "正常" }

    public struct Row: Equatable {
        public var name: String
        public var workload: PersonWorkload
        /// 日常班里有组别（组A–E）的天数（regularDays 的一部分）
        public var groupDays: Int
        /// 和平均的差（天）
        public var diff: Double
        public var level: Level
    }

    /// 参与比较的人（这段时间有组别排班的人），工作量多的在前
    public var rows: [Row]
    public var average: Double
    /// 最多和最少差几天
    public var spread: Int
    /// 均衡 / 基本均衡 / 不均衡
    public var verdict: String
    /// 一句句的结论
    public var findings: [String]
}

public enum WorkloadBalance {
    private static let groupPattern = try! NSRegularExpression(pattern: #"^组\s*[A-Ea-e]$"#)

    /// 组A–组E
    static func isGroup(_ post: String) -> Bool {
        let t = post.filter { !$0.isWhitespace }
        return groupPattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }

    /// days：统计哪些日子；tolerance：和平均差多少天算「偏多/偏少」（一周 2 天，一个月 3 天）。
    public static func analyze(roster: Roster, days: [DayKey], matcher: ShiftMatcher, tolerance: Double,
                               calendar: Calendar = .current) -> BalanceReport {
        func hasGroup(_ raw: String?) -> Bool {
            raw?.split(separator: "+").contains { isGroup(matcher.displayName(String($0))) } ?? false
        }
        func groupDays(_ history: [DayKey: String]) -> Int { days.filter { hasGroup(history[$0]) }.count }
        /// 算在「日常」里的组别天数（同一天还有遥测的算值班，不在这里）
        func regularGroupDays(_ history: [DayKey: String]) -> Int {
            let kinds = WorkloadCounter.kinds(of: history, days: days, matcher: matcher, calendar: calendar)
            return days.filter { kinds[$0] == .regular && hasGroup(history[$0]) }.count
        }
        // 只比较这段时间有组别排班的人
        let pool = roster.filter { groupDays($0.value) > 0 }
        let workloads = WorkloadCounter.count(roster: pool, days: days, matcher: matcher, calendar: calendar)
        guard !workloads.isEmpty else {
            return BalanceReport(rows: [], average: 0, spread: 0, verdict: "没有数据", findings: [])
        }
        let average = Double(workloads.map(\.workDays).reduce(0, +)) / Double(workloads.count)
        let rows = workloads.map { w -> BalanceReport.Row in
            let diff = Double(w.workDays) - average
            let level: BalanceReport.Level = diff >= tolerance ? .more : (diff <= -tolerance ? .less : .normal)
            return .init(name: w.name, workload: w, groupDays: regularGroupDays(pool[w.name] ?? [:]), diff: diff, level: level)
        }.sorted { ($0.workload.workDays, $0.workload.dutyDays, $1.name) > ($1.workload.workDays, $1.workload.dutyDays, $0.name) }

        let most = rows.first!, least = rows.last!
        let spread = most.workload.workDays - least.workload.workDays
        let verdict = Double(spread) <= tolerance / 2 ? "均衡" : (Double(spread) <= tolerance ? "基本均衡" : "不均衡")
        var findings = ["平均每人 \(String(format: "%.1f", average)) 天；最多 \(most.name) \(most.workload.workDays) 天，"
                        + "最少 \(least.name) \(least.workload.workDays) 天，相差 \(spread) 天"]
        for row in rows where row.level == .more {
            findings.append("\(row.name)干得多：\(row.workload.workDays) 天，比平均多 \(String(format: "%.1f", row.diff)) 天"
                            + (row.workload.dutyDays > 0 ? "（其中遥测 \(row.workload.dutyDays) 次）" : ""))
        }
        for row in rows.reversed() where row.level == .less {
            var why: [String] = []
            if row.workload.offDays > 0 { why.append("休息 \(row.workload.offDays) 天") }
            if row.workload.holidayDays > 0 { why.append("节假日 \(row.workload.holidayDays) 天") }
            findings.append("\(row.name)干得少：\(row.workload.workDays) 天，比平均少 \(String(format: "%.1f", -row.diff)) 天"
                            + (why.isEmpty ? "" : "（\(why.joined(separator: "，"))）"))
        }
        // 遥测次数也看一下：工作量天数一样，遥测多的人更累
        let duties = rows.map(\.workload.dutyDays)
        if let maxDuty = duties.max(), let minDuty = duties.min(), maxDuty - minDuty >= 2 {
            let heavy = rows.filter { $0.workload.dutyDays == maxDuty }.map(\.name).joined(separator: "、")
            let light = rows.filter { $0.workload.dutyDays == minDuty }.map(\.name).joined(separator: "、")
            findings.append("遥测不均：\(heavy) \(maxDuty) 次，\(light) \(minDuty) 次")
        }
        return BalanceReport(rows: rows, average: average, spread: spread, verdict: verdict, findings: findings)
    }
}
