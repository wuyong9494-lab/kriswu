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

    /// 是否工作日：调休上班的周末算，法定假日不算，其余按周一到周五。
    public static func isWorkday(_ day: DayKey, calendar: Calendar) -> Bool {
        let key = day.description
        if workingWeekends.contains(key) { return true }
        if off.contains(key) { return false }
        let w = calendar.component(.weekday, from: day.date(calendar: calendar, hour: 12))
        return w != 1 && w != 7
    }
}
