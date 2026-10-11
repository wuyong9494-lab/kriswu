import Foundation

/// 排班合理度分析：一周的组A–E分配、一个月的遥测值班。
/// 按几条常见的公平原则逐条检查，每发现一个问题扣分，100 分起。
public struct FairnessReport: Equatable {
    public struct Row: Equatable {
        public var name: String
        /// 这段时间排了几天（组别天数 / 遥测次数）
        public var count: Int
        /// 明细，例如「一A 二C 四A」或「3、9、15 日」
        public var detail: String
        /// 有问题时的说明（列表里标红）
        public var warning: String?
    }

    public var score: Int
    /// 合理 / 基本合理 / 不太合理
    public var verdict: String
    /// 发现的问题，每条一句话；没有问题时为空
    public var findings: [String]
    /// 每人一行，次数多的在前
    public var rows: [Row]
    /// 平均每人几天/几次
    public var average: Double

    static func verdict(for score: Int) -> String {
        score >= 85 ? "合理" : (score >= 70 ? "基本合理" : "不太合理")
    }
}

public enum FairnessAnalyzer {
    private static let groupPattern = try! NSRegularExpression(pattern: #"^组\s*[A-Ea-e]$"#)
    private static let weekdayNames = ["日", "一", "二", "三", "四", "五", "六"]

    /// 组A–组E
    static func group(_ post: String) -> String? {
        let t = post.filter { !$0.isWhitespace }
        guard groupPattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil else { return nil }
        return "组" + t.suffix(1).uppercased()
    }

    private static func posts(_ raw: String?, matcher: ShiftMatcher) -> [String] {
        raw?.split(separator: "+").map { matcher.displayName(String($0)) } ?? []
    }

    // MARK: - 一周的组别

    /// days：这一周（周一到周日）读到排班的日子。
    public static func groupWeek(roster: Roster, days: [DayKey], restBalance: [String: Int], matcher: ShiftMatcher,
                                 calendar: Calendar = .current) -> FairnessReport {
        var perPerson: [String: [(DayKey, String)]] = [:]
        var perDay: [DayKey: [String: [String]]] = [:]
        for (name, schedule) in roster {
            for day in days {
                for g in posts(schedule[day], matcher: matcher).compactMap(group) {
                    perPerson[name, default: []].append((day, g))
                    perDay[day, default: [:]][g, default: []].append(name)
                }
            }
        }
        var findings: [String] = []
        var warnings: [String: [String]] = [:]
        var penalty = 0
        func warn(_ name: String, _ text: String, _ points: Int) {
            findings.append(text)
            warnings[name, default: []].append(text)
            penalty += points
        }

        // 1. 每天每个组都要有人（这周出现过的组）
        let usedGroups = Set(perDay.values.flatMap(\.keys))
        for day in days.sorted() where perDay[day] != nil {
            let missing = usedGroups.subtracting(perDay[day]!.keys).sorted()
            if !missing.isEmpty, ChinaHolidays.isWorkday(day, calendar: calendar) {
                findings.append("\(day.month)月\(day.day)日 \(missing.joined(separator: "、"))没有人")
                penalty += 5
            }
            for (g, names) in perDay[day]! where names.count > 1 {
                findings.append("\(day.month)月\(day.day)日 \(g)排了 \(names.count) 个人（\(names.sorted().joined(separator: "、"))）")
                penalty += 2
            }
        }
        // 2. 同一个人一周里同一个组不宜太多；连续天数不宜太长
        for (name, list) in perPerson {
            let byGroup = Dictionary(grouping: list, by: { $0.1 }).mapValues(\.count)
            for (g, n) in byGroup where n >= 3 {
                warn(name, "\(name)本周\(g)排了 \(n) 次，同一个组太集中", 5)
            }
            let sortedDays = list.map { $0.0 }.sorted()
            var run = 1, longest = 1
            for i in sortedDays.indices.dropFirst() {
                run = sortedDays[i - 1].adding(days: 1, calendar: calendar) == sortedDays[i] ? run + 1 : 1
                longest = max(longest, run)
            }
            if longest >= 6 { warn(name, "\(name)连续 \(longest) 天都在组里，中间没有休息", 3) }
        }
        // 3. 人和人之间的天数差距
        let counts = perPerson.mapValues(\.count)
        let average = counts.isEmpty ? 0 : Double(counts.values.reduce(0, +)) / Double(counts.count)
        if let most = counts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }),
           let least = counts.min(by: { ($0.value, $1.key) < ($1.value, $0.key) }), most.value - least.value >= 3 {
            findings.append("组别天数差距大：\(most.key) \(most.value) 天，\(least.key) 只有 \(least.value) 天")
            penalty += 8
            warnings[most.key, default: []].append("比别人多")
        }
        // 4. 待休很多的人还排得多
        for (name, n) in counts {
            if let rest = restBalance[name], rest >= 5, Double(n) > average {
                warn(name, "\(name)还有 \(rest) 天待休，本周组别仍排了 \(n) 天（高于平均）", 3)
            }
        }

        let rows = perPerson.map { name, list -> FairnessReport.Row in
            let detail = list.sorted { $0.0 < $1.0 }.map { day, g in
                "周" + weekdayNames[calendar.component(.weekday, from: day.date(calendar: calendar, hour: 12)) - 1]
                    + g.replacingOccurrences(of: "组", with: "")
            }.joined(separator: " ")
            return .init(name: name, count: list.count, detail: detail, warning: warnings[name]?.first)
        }.sorted { ($0.count, $1.name) > ($1.count, $0.name) }
        let score = max(0, 100 - penalty)
        return FairnessReport(score: score, verdict: FairnessReport.verdict(for: score), findings: findings,
                              rows: rows, average: average)
    }

    // MARK: - 一个月的遥测

    /// days：这个月读到排班的日子（包括已经排好的以后的日子）。
    /// 人员范围：这个月排过遥测的人。
    public static func telemetryMonth(roster: Roster, days: [DayKey], restBalance: [String: Int], matcher: ShiftMatcher,
                                      calendar: Calendar = .current) -> FairnessReport {
        var duties: [String: [DayKey]] = [:]
        var perDay: [DayKey: [String]] = [:]
        for (name, schedule) in roster {
            for day in days where posts(schedule[day], matcher: matcher).contains(where: WorkloadCounter.isDuty) {
                duties[name, default: []].append(day)
                perDay[day, default: []].append(name)
            }
        }
        var findings: [String] = []
        var warnings: [String: [String]] = [:]
        var penalty = 0
        func warn(_ name: String, _ text: String, _ points: Int) {
            findings.append(text)
            warnings[name, default: []].append(text)
            penalty += points
        }
        func weekend(_ day: DayKey) -> Bool {
            let w = calendar.component(.weekday, from: day.date(calendar: calendar, hour: 12))
            return (w == 1 || w == 7) && !ChinaHolidays.isWorkday(day, calendar: calendar)
        }

        // 1. 每天要有人遥测
        let gaps = days.sorted().filter { perDay[$0] == nil }
        if !gaps.isEmpty {
            findings.append("有 \(gaps.count) 天没排遥测：" + gaps.prefix(6).map { "\($0.month)/\($0.day)" }.joined(separator: "、")
                            + (gaps.count > 6 ? "…" : ""))
            penalty += min(15, gaps.count * 3)
        }
        // 2. 两次遥测之间至少隔 2 天（值完班要休息）
        for (name, list) in duties {
            let sorted = list.sorted()
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                let gap = calendar.dateComponents([.day], from: a.date(calendar: calendar, hour: 12),
                                                  to: b.date(calendar: calendar, hour: 12)).day ?? 0
                if gap <= 2 {
                    warn(name, "\(name) \(a.month)/\(a.day) 和 \(b.month)/\(b.day) 两次遥测只隔 \(gap - 1) 天", 8)
                }
            }
        }
        // 3. 次数要平均
        let counts = duties.mapValues(\.count)
        let average = counts.isEmpty ? 0 : Double(counts.values.reduce(0, +)) / Double(counts.count)
        for (name, n) in counts {
            if Double(n) >= average + 2 { warn(name, "\(name)本月遥测 \(n) 次，比平均（\(String(format: "%.1f", average)) 次）多", 5) }
            if Double(n) <= average - 2 { warn(name, "\(name)本月遥测只有 \(n) 次，比平均少", 3) }
        }
        // 4. 节假日、周末的值班要分散
        let holidayCounts = duties.mapValues { $0.filter(ChinaHolidays.isHoliday).count }
        if let top = holidayCounts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }), top.value >= 2,
           holidayCounts.values.filter({ $0 == 0 }).count > 0 {
            warn(top.key, "\(top.key)本月节假日遥测 \(top.value) 次，有人一次都没有", 5)
        }
        let weekendCounts = duties.mapValues { $0.filter(weekend).count }
        for (name, n) in weekendCounts where n >= 3 {
            warn(name, "\(name)本月周末遥测 \(n) 次", 3)
        }
        // 5. 待休很多的人还排得多
        for (name, n) in counts {
            if let rest = restBalance[name], rest >= 5, Double(n) >= average {
                warn(name, "\(name)还有 \(rest) 天待休，本月仍排了 \(n) 次遥测", 3)
            }
        }

        let rows = duties.map { name, list -> FairnessReport.Row in
            let sorted = list.sorted()
            let marks = sorted.map { "\($0.day)" + (ChinaHolidays.isHoliday($0) ? "节" : (weekend($0) ? "末" : "")) }
            return .init(name: name, count: list.count, detail: marks.joined(separator: "、") + " 日",
                         warning: warnings[name]?.first)
        }.sorted { ($0.count, $1.name) > ($1.count, $0.name) }
        let score = max(0, 100 - penalty)
        return FairnessReport(score: score, verdict: FairnessReport.verdict(for: score), findings: findings,
                              rows: rows, average: average)
    }
}
