import Foundation

/// 一个不带时区的“日历日”，例如 2026-10-09。
public struct DayKey: Hashable, Comparable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// 解析 "yyyy-MM-dd"。
    public init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, DayKey.isValid(year: parts[0], month: parts[1], day: parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public func date(calendar: Calendar = .current, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    public func adding(days: Int, calendar: Calendar) -> DayKey {
        let d = calendar.date(byAdding: .day, value: days, to: date(calendar: calendar, hour: 12))!
        return DayKey(date: d, calendar: calendar)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public static func isValid(year: Int, month: Int, day: Int) -> Bool {
        guard (1900...2200).contains(year), (1...12).contains(month), day >= 1 else { return false }
        let days = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        if day > days[month - 1] { return false }
        if month == 2 && day == 29 {
            return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        }
        return true
    }

    // Codable 用字符串表示，便于阅读存档文件。
    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let key = DayKey(string: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad day: \(s)"))
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}
