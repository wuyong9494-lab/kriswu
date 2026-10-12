import Foundation

/// 国家法定节假日安排（国务院办公厅每年公布）：放假的日子不算工作日，调休上班的周末算工作日。
/// 用于工作量统计里「没排岗位的工作日 = 日常班」。新的一年公布后在这里补上。
public enum ChinaHolidays {
    private static func range(_ year: Int, _ month: Int, _ from: Int, _ to: Int) -> [String] {
        (from...to).map { String(format: "%04d-%02d-%02d", year, month, $0) }
    }

    /// 放假的日子
    static let off: Set<String> = Set(
        // 2025
        range(2025, 1, 1, 1) + range(2025, 1, 28, 31) + range(2025, 2, 1, 4) + range(2025, 4, 4, 6)
        + range(2025, 5, 1, 5) + range(2025, 5, 31, 31) + range(2025, 6, 1, 2) + range(2025, 10, 1, 8)
        // 2026
        + range(2026, 1, 1, 3) + range(2026, 2, 15, 23) + range(2026, 4, 4, 6) + range(2026, 5, 1, 5)
        + range(2026, 6, 19, 21) + range(2026, 9, 25, 27) + range(2026, 10, 1, 7)
    )

    /// 调休上班的周末
    static let workingWeekends: Set<String> = [
        "2025-01-26", "2025-02-08", "2025-04-27", "2025-09-28", "2025-10-11",
        "2026-01-04", "2026-02-14", "2026-02-28", "2026-05-09", "2026-09-20", "2026-10-10",
    ]

    /// 用户在 App 里补充的安排（新的一年公布后自己录入，或者纠正）：优先于上面的表
    public static var customOff: Set<String> = []
    public static var customWork: Set<String> = []

    /// 已经录入节假日安排的年份（App 自带的加上自己录入的）
    public static var knownYears: Set<Int> {
        Set([2025, 2026]).union(customOff.union(customWork).compactMap { Int($0.prefix(4)) })
    }

    /// 法定节假日（放假的日子，含调休连休）
    public static func isHoliday(_ day: DayKey) -> Bool {
        let key = day.description
        if customWork.contains(key) { return false }
        return customOff.contains(key) || off.contains(key)
    }

    /// 是否工作日：调休上班的周末算，法定假日不算，其余按周一到周五。
    public static func isWorkday(_ day: DayKey, calendar: Calendar) -> Bool {
        let key = day.description
        if customWork.contains(key) { return true }
        if customOff.contains(key) { return false }
        if workingWeekends.contains(key) { return true }
        if off.contains(key) { return false }
        let w = calendar.component(.weekday, from: day.date(calendar: calendar, hour: 12))
        return w != 1 && w != 7
    }
}

/// 把「2027-01-01 至 2027-01-03 放假」「2027-02-07 上班」这样一行一行的文字读成放假、上班的日子。
public enum HolidayInput {
    public struct Result: Equatable {
        public var off: [DayKey]
        public var work: [DayKey]
        /// 看不懂的行
        public var skipped: [String]
    }

    private static let rangeSeparators = ["至", "到", "~", "～", "—", "–"]
    private static let dateToken = try! NSRegularExpression(
        pattern: #"\d{4}\s*[-/.年]\s*\d{1,2}\s*[-/.月]\s*\d{1,2}\s*日?|\d{1,2}\s*[-/.月]\s*\d{1,2}\s*日?|\d{1,2}\s*日"#)

    private enum Kind { case off, work }

    /// 一个分句说的是放假还是上班（没写就是 nil，跟着同一句里后面/前面的分句）
    private static func kind(of clause: String) -> Kind? {
        if (clause.contains("上班") || clause.contains("补班")) && !clause.contains("放假") { return .work }
        if clause.contains("放假") || clause.contains("休") { return .off }
        return nil
    }

    public static func parse(_ text: String, reference: DayKey, calendar: Calendar = .current) -> Result {
        var result = Result(off: [], work: [], skipped: [])
        let parser = DateTokenParser(reference: reference)
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            var found = false
            // 一行里可能有好几句：「1月1日（周五）至3日（周日）放假调休，共3天。1月4日（周一）上班」
            for sentence in line.split(whereSeparator: { "。；;".contains($0) }).map(String.init) {
                let clauses = sentence.split(whereSeparator: { "，,".contains($0) }).map(String.init)
                let kinds = clauses.map(kind(of:))
                for (i, clause) in clauses.enumerated() {
                    let days = dates(in: clause, parser: parser, calendar: calendar)
                    guard !days.isEmpty else { continue }
                    found = true
                    // 分句里没写放假还是上班：看同一句后面的，再看前面的，都没有算放假
                    let k = kinds[i] ?? kinds[(i + 1)...].compactMap { $0 }.first
                        ?? kinds[..<i].compactMap { $0 }.last ?? .off
                    if k == .work { result.work += days } else { result.off += days }
                }
            }
            if !found { result.skipped.append(line) }
        }
        return result
    }

    /// 分句里所有日期：「1月1日至3日」展开成 1、2、3 日，「2月14日、2月28日」是两天
    private static func dates(in clause: String, parser: DateTokenParser, calendar: Calendar) -> [DayKey] {
        let ns = clause as NSString
        let matches = dateToken.matches(in: clause, range: NSRange(location: 0, length: ns.length))
        var days: [DayKey] = []
        var previous: DayKey?
        var lastEnd = 0
        for m in matches {
            let token = ns.substring(with: m.range)
            let between = ns.substring(with: NSRange(location: lastEnd, length: m.range.location - lastEnd))
            lastEnd = m.range.location + m.range.length
            let isRangeEnd = previous != nil && rangeSeparators.contains(where: between.contains)
            var day = parser.parse(token)
            if day == nil, let p = previous { day = parser.parseDayOnly(token, year: p.year, month: p.month) }
            guard var d = day else { continue }
            if isRangeEnd, let first = previous {
                // 跨年：「12月31日至1月2日」
                if d < first { d = DayKey(year: d.year + 1, month: d.month, day: d.day) }
                var x = first
                var count = 0
                while x < d, count < 40 {
                    x = x.adding(days: 1, calendar: calendar)
                    days.append(x)
                    count += 1
                }
                previous = nil   // 一段范围结束
            } else {
                days.append(d)
                previous = d
            }
        }
        return days
    }
}
