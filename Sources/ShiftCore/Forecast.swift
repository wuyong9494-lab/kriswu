import Foundation

/// 遥测轮转预测：按每个人过去值遥测的间隔，推算下一次大概哪天。
public struct DutyForecast: Equatable, Sendable {
    public var name: String
    /// 记录里一共值了几次
    public var count: Int
    /// 最近一次（今天及以前）
    public var last: DayKey?
    /// 网站上已经排好的下一次（今天以后）
    public var scheduled: DayKey?
    /// 平均隔几天值一次（至少两次才有）
    public var interval: Int?
    /// 推算的下一次：已经排好的就是排好的那天，否则 最近一次 + 间隔
    public var predicted: DayKey?
}

public enum DutyForecaster {
    /// roster：全员排班；today：今天。只看值过遥测的人。
    public static func forecast(roster: Roster, today: DayKey, matcher: ShiftMatcher,
                                calendar: Calendar = .current) -> [DutyForecast] {
        func daysBetween(_ a: DayKey, _ b: DayKey) -> Int {
            calendar.dateComponents([.day], from: a.date(calendar: calendar, hour: 12), to: b.date(calendar: calendar, hour: 12)).day ?? 0
        }
        var result: [DutyForecast] = []
        for (name, history) in roster {
            let duties = history.filter { WorkloadCounter.isDuty(matcher.displayName($0.value)) }.keys.sorted()
            guard !duties.isEmpty else { continue }
            let past = duties.filter { $0 <= today }
            let scheduled = duties.first { $0 > today }
            let gaps = zip(duties, duties.dropFirst()).map { daysBetween($0, $1) }.filter { $0 > 0 }.sorted()
            // 中位数：偶尔一次换班、请假不会把间隔拉偏太多
            let interval = gaps.isEmpty ? nil : gaps[gaps.count / 2]
            var predicted = scheduled
            if predicted == nil, let last = past.last, let interval {
                var next = last.adding(days: interval, calendar: calendar)
                // 推算的日子已经过了还没排上：顺延到明天以后
                while next <= today { next = next.adding(days: interval, calendar: calendar) }
                predicted = next
            }
            result.append(DutyForecast(name: name, count: duties.count, last: past.last, scheduled: scheduled,
                                       interval: interval, predicted: predicted))
        }
        // 下一次早的在前；推算不出来的放最后，按上次值班早的在前（隔得久，可能快轮到了）
        return result.sorted { a, b in
            switch (a.predicted, b.predicted) {
            case let (x?, y?): return x != y ? x < y : a.name < b.name
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return (a.last ?? today, a.name) < (b.last ?? today, b.name)
            }
        }
    }
}

/// 导出表格（CSV，Excel、WPS、Numbers 都能打开）
public enum WorkloadCSV {
    static func field(_ s: String) -> String {
        s.contains(where: { ",\"\n".contains($0) }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    public static func make(_ people: [PersonWorkload], restBalance: [String: Int] = [:]) -> String {
        var lines = ["姓名,工作量,上班天数,值班(遥测),值班调休,日常,出差,上班(不算工作量),休息,节假日,没排班,节假日上班,待休,轮组别,其中没排岗位上班,各岗位"]
        for p in people {
            let posts = p.posts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map { "\($0.key)×\($0.value)" }.joined(separator: " ")
            let cells = [p.name, "\(p.workDays)", "\(p.presentDays)", "\(p.dutyDays)", "\(p.dutyRestDays)", "\(p.regularDays)",
                         "\(p.tripDays)", "\(p.attendanceDays)", "\(p.offDays)", "\(p.holidayDays)", "\(p.unassignedDays)", "\(p.holidayWorkedDays)",
                         restBalance[p.name].map(String.init) ?? "", p.isGroupMember ? "是" : "", "\(p.blankWorkDays)", posts]
            lines.append(cells.map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// 工作量均衡分析导出
    public static func balance(_ report: BalanceReport, title: String) -> String {
        var lines = [field(title), "结论," + field(report.verdict), "平均," + String(format: "%.1f", report.average),
                     "姓名,工作量,上班天数,和平均差,判断,遥测,组别天数,其它日常,出差,上班(不算工作量),休息,节假日"]
        for row in report.rows {
            let w = row.workload
            lines.append([row.name, "\(w.workDays)", "\(w.presentDays)", String(format: "%+.1f", row.diff), row.level.rawValue,
                          "\(w.dutyDays)", "\(row.groupDays)", "\(max(0, w.regularDays - row.groupDays))", "\(w.tripDays)",
                          "\(w.attendanceDays)", "\(w.offDays)",
                          "\(w.holidayDays)"].map(field).joined(separator: ","))
        }
        lines += report.findings.map(field)
        return lines.joined(separator: "\n") + "\n"
    }
}
