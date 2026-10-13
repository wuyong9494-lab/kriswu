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

    /// 每年自动下载的安排（公开的节假日数据），优先级在自己录入的之后、App 自带的之前
    @Locked public static var downloadedOff: Set<String> = []
    @Locked public static var downloadedWork: Set<String> = []

    /// 用户在 App 里补充的安排（新的一年公布后自己录入，或者纠正）：优先于上面的表
    @Locked public static var customOff: Set<String> = []
    @Locked public static var customWork: Set<String> = []

    /// 已经录入节假日安排的年份（App 自带的加上自己录入的）
    public static var knownYears: Set<Int> {
        Set([2025, 2026]).union(customOff.union(customWork).union(downloadedOff).union(downloadedWork).compactMap { Int($0.prefix(4)) })
    }

    /// 法定节假日（放假的日子，含调休连休）
    public static func isHoliday(_ day: DayKey) -> Bool {
        let key = day.description
        if customWork.contains(key) { return false }
        if customOff.contains(key) { return true }
        if downloadedWork.contains(key) { return false }
        return downloadedOff.contains(key) || off.contains(key)
    }

    /// 是否工作日：调休上班的周末算，法定假日不算，其余按周一到周五。
    public static func isWorkday(_ day: DayKey, calendar: Calendar) -> Bool {
        let key = day.description
        if customWork.contains(key) { return true }
        if customOff.contains(key) { return false }
        if downloadedWork.contains(key) { return true }
        if downloadedOff.contains(key) { return false }
        if workingWeekends.contains(key) { return true }
        if off.contains(key) { return false }
        let w = calendar.component(.weekday, from: day.date(calendar: calendar, hour: 12))
        return w != 1 && w != 7
    }
}

/// 公开的节假日数据（holiday-cn 的格式）：{"year":2027,"days":[{"name":"元旦","date":"2027-01-01","isOffDay":true},…]}
public enum HolidayFeed {
    public static func url(year: Int) -> URL {
        URL(string: "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/\(year).json")!
    }

    /// 放假的日子、调休上班的日子（「2027-01-01」这样的字符串）；格式不对返回 nil
    public static func parse(_ data: Data) -> (off: [String], work: [String])? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let days = json["days"] as? [[String: Any]] else { return nil }
        var off: [String] = [], work: [String] = []
        for d in days {
            guard let date = d["date"] as? String, DayKey(string: date) != nil, let isOff = d["isOffDay"] as? Bool else { continue }
            if isOff { off.append(date) } else { work.append(date) }
        }
        return off.isEmpty && work.isEmpty ? nil : (off.sorted(), work.sorted())
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

    private static let rangeSeparators = ["至", "到", "~", "～", "—", "–", "-"]
    private static let dateToken = try! NSRegularExpression(
        pattern: #"\d{4}\s*[-/.年]\s*\d{1,2}\s*[-/.月]\s*\d{1,2}\s*日?|\d{1,2}\s*[-/.月]\s*\d{1,2}\s*日?|\d{1,2}\s*日"#)

    private enum Kind { case off, work }

    /// 一个分句说的是放假还是上班（没写就是 nil，跟着同一句里后面/前面的分句）
    private static func kind(of clause: String) -> Kind? {
        if (clause.contains("上班") || clause.contains("补班")) && !clause.contains("放假") { return .work }
        if clause.contains("放假") || clause.contains("休") { return .off }
        return nil
    }

    /// 节日名：一行里没写放假、上班，但写了节日名的也认
    private static let festivals = ["元旦", "春节", "清明", "劳动", "五一", "端午", "中秋", "国庆"]

    public static func parse(_ text: String, reference: DayKey, calendar: Calendar = .current) -> Result {
        var result = Result(off: [], work: [], skipped: [])
        let parser = DateTokenParser(reference: reference)
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            // 通知落款、发布时间之类的日期不是假期：没写放假、上班，也没写节日名的行不要
            guard kind(of: line) != nil || festivals.contains(where: line.contains) else {
                result.skipped.append(line)
                continue
            }
            var off: [DayKey] = [], work: [DayKey] = []
            var found = false, bad = false
            // 一行里可能有好几句：「1月1日（周五）至3日（周日）放假调休，共3天。1月4日（周一）上班」
            for sentence in line.split(whereSeparator: { "。；;".contains($0) }).map(String.init) {
                let clauses = sentence.split(whereSeparator: { "，,".contains($0) }).map(String.init)
                let kinds = clauses.map(kind(of:))
                for (i, clause) in clauses.enumerated() {
                    guard let days = dates(in: clause, parser: parser, year: reference.year, calendar: calendar) else {
                        bad = true
                        continue
                    }
                    guard !days.isEmpty else { continue }
                    found = true
                    // 分句里没写放假还是上班：看同一句后面的，再看前面的，都没有算放假
                    let k = kinds[i] ?? kinds[(i + 1)...].compactMap { $0 }.first
                        ?? kinds[..<i].compactMap { $0 }.last ?? .off
                    if k == .work { work += days } else { off += days }
                }
            }
            if !found || bad {
                result.skipped.append(line)
            } else {
                result.off += off
                result.work += work
            }
        }
        return result
    }

    /// 分句里所有日期：「1月1日至3日」展开成 1、2、3 日，「2月14日、2月28日」是两天。
    /// 没写年份的按 year；范围倒过来或超过 40 天说明没看懂，返回 nil。
    private static func dates(in clause: String, parser: DateTokenParser, year: Int, calendar: Calendar) -> [DayKey]? {
        let ns = clause as NSString
        let matches = dateToken.matches(in: clause, range: NSRange(location: 0, length: ns.length))
        var days: [DayKey] = []
        var previous: DayKey?
        var lastEnd = 0
        for m in matches {
            let token = ns.substring(with: m.range).trimmingCharacters(in: .whitespaces)
            let between = ns.substring(with: NSRange(location: lastEnd, length: m.range.location - lastEnd))
            lastEnd = m.range.location + m.range.length
            let isRangeEnd = previous != nil && rangeSeparators.contains(where: between.contains)
            let hasYear = token.prefix(4).allSatisfy(\.isNumber) && token.count > 4
            var dayOnly = false
            var day: DayKey?
            if let d = parser.parse(token) {
                day = hasYear ? d : DayKey(year: year, month: d.month, day: d.day)
            } else if let p = previous, let d = parser.parseDayOnly(token, year: p.year, month: p.month) {
                day = d
                dayOnly = true
            }
            guard var d = day else { continue }
            if isRangeEnd, let first = previous {
                if d < first {
                    if dayOnly {
                        // 「1月30日至2日」：到下个月 2 日
                        let next = first.month == 12 ? (first.year + 1, 1) : (first.year, first.month + 1)
                        guard DayKey.isValid(year: next.0, month: next.1, day: d.day) else { return nil }
                        d = DayKey(year: next.0, month: next.1, day: d.day)
                    } else if !hasYear {
                        // 跨年：「12月31日至1月2日」
                        d = DayKey(year: d.year + 1, month: d.month, day: d.day)
                    } else {
                        return nil
                    }
                }
                var x = first
                var span: [DayKey] = []
                while x < d {
                    x = x.adding(days: 1, calendar: calendar)
                    span.append(x)
                    if span.count > 40 { return nil }
                }
                days += span
                previous = nil   // 一段范围结束
            } else {
                days.append(d)
                previous = d
            }
        }
        return days
    }
}
