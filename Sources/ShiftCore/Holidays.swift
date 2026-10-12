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

    public static func parse(_ text: String, reference: DayKey, calendar: Calendar = .current) -> Result {
        var result = Result(off: [], work: [], skipped: [])
        let parser = DateTokenParser(reference: reference)
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let isWork = line.contains("班") && !line.contains("放假")
            // 按「至」「~」分成前后两半，每半找出里面的日期（旁边写的「元旦」「春节」之类不管）
            var pieces = [line]
            for sep in rangeSeparators where line.contains(sep) {
                pieces = line.components(separatedBy: sep)
                break
            }
            func token(_ piece: String) -> String? {
                guard let m = dateToken.firstMatch(in: piece, range: NSRange(piece.startIndex..., in: piece)),
                      let r = Range(m.range, in: piece) else { return nil }
                return String(piece[r])
            }
            var dates = pieces.compactMap { token($0).flatMap(parser.parse) }
            // 「1月1日至3日」：后半只写了日
            if dates.count == 1, pieces.count == 2, let first = dates.first, let t = token(pieces[1]),
               let end = parser.parseDayOnly(t, year: first.year, month: first.month) {
                dates.append(end)
            }
            guard let first = dates.first, dates.count == pieces.count else {
                result.skipped.append(line)
                continue
            }
            var days = [first]
            if dates.count == 2, let last = dates.last, last > first {
                var d = first
                while d < last, days.count < 40 {
                    d = d.adding(days: 1, calendar: calendar)
                    days.append(d)
                }
            }
            if isWork { result.work += days } else { result.off += days }
        }
        return result
    }
}
