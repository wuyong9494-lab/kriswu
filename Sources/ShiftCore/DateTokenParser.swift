import Foundation

/// 把表格里的“日期”单元格解析成 DayKey。
/// 支持：2026-10-09、2026/10/9、2026.10.9、2026年10月9日、20261009、
///       10-09、10/9、10月9日（年份按参考日期推断），以及在已知月份时的纯日号 "9" / "9日"。
/// 会忽略附带的星期，例如 "10/9(周五)"、"10月9日 星期五"、"Fri 10/9"。
public struct DateTokenParser {
    public var reference: DayKey

    public init(reference: DayKey) {
        self.reference = reference
    }

    private static let fullDate = try! NSRegularExpression(pattern: #"^(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})\s*日?"#)
    private static let compactDate = try! NSRegularExpression(pattern: #"^(\d{4})(\d{2})(\d{2})(?:$|T|\s)"#)
    private static let monthDay = try! NSRegularExpression(pattern: #"^(\d{1,2})\s*[-/.月]\s*(\d{1,2})\s*日?$"#)
    private static let dayOnly = try! NSRegularExpression(pattern: #"^(\d{1,2})\s*日?$"#)
    private static let yearMonth = try! NSRegularExpression(pattern: #"(\d{4})\s*[-/.年]\s*(\d{1,2})\s*月?"#)
    private static let noise = try! NSRegularExpression(
        pattern: #"[（(][^)）]*[)）]|(?:周|星期|礼拜)[一二三四五六日天]|今天|明天|昨天|今日|\b(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*\.?|\b(?:today|tomorrow)\b"#,
        options: [.caseInsensitive])

    static func cleaned(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(s.startIndex..., in: s)
        return noise.stringByReplacingMatches(in: s, range: range, withTemplate: "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",，")))
    }

    private static func groups(_ re: NSRegularExpression, _ s: String) -> [Int]? {
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1..<m.numberOfRanges).compactMap { i in
            Range(m.range(at: i), in: s).flatMap { Int(s[$0]) }
        }
    }

    /// 解析完整日期或“月-日”。不解析纯日号。
    public func parse(_ raw: String) -> DayKey? {
        let s = Self.cleaned(raw)
        guard !s.isEmpty else { return nil }

        if let g = Self.groups(Self.fullDate, s), g.count == 3, DayKey.isValid(year: g[0], month: g[1], day: g[2]) {
            return DayKey(year: g[0], month: g[1], day: g[2])
        }
        if let g = Self.groups(Self.compactDate, s), g.count == 3, DayKey.isValid(year: g[0], month: g[1], day: g[2]) {
            return DayKey(year: g[0], month: g[1], day: g[2])
        }
        if let g = Self.groups(Self.monthDay, s), g.count == 2 {
            return inferYear(month: g[0], day: g[1])
        }
        return nil
    }

    /// 解析纯日号（1...31），用于表头只写 "1 2 3 …" 的月度排班表。
    public func parseDayOnly(_ raw: String, year: Int, month: Int) -> DayKey? {
        let s = Self.cleaned(raw)
        guard let g = Self.groups(Self.dayOnly, s), g.count == 1,
              DayKey.isValid(year: year, month: month, day: g[0]) else { return nil }
        return DayKey(year: year, month: month, day: g[0])
    }

    /// 在一段文字里找 "2026年10月" / "2026-10" 之类的年月。
    public static func findYearMonth(in text: String) -> (year: Int, month: Int)? {
        guard let g = groups(yearMonth, text), g.count == 2, (1...12).contains(g[1]), (1900...2200).contains(g[0]) else { return nil }
        return (g[0], g[1])
    }

    /// “月-日”没写年份时，取离参考日期最近的那一年（跨年排班时也正确）。
    func inferYear(month: Int, day: Int) -> DayKey? {
        let candidates = [reference.year - 1, reference.year, reference.year + 1]
            .filter { DayKey.isValid(year: $0, month: month, day: day) }
            .map { DayKey(year: $0, month: month, day: day) }
        let ref = reference.ordinal
        return candidates.min { abs($0.ordinal - ref) < abs($1.ordinal - ref) }
    }
}

extension DayKey {
    /// 近似的天数序号，仅用于比较远近。
    var ordinal: Int { year * 372 + month * 31 + day }
}
