import Foundation

/// 把我的排班导出成 .ics 日历文件（全天事件），发给家人导入他们的日历
public enum ICSExport {
    public static func make(schedule: [DayKey: String], from: DayKey, to: DayKey, matcher: ShiftMatcher,
                            calendar: Calendar, stamp: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        func day(_ d: DayKey) -> String { String(format: "%04d%02d%02d", d.year, d.month, d.day) }
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\;")
                .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\n", with: "\\n")
        }
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//ShiftReminder//CN", "CALSCALE:GREGORIAN",
                     "X-WR-CALNAME:\(escape("值班安排"))"]
        for (d, raw) in schedule.filter({ $0.key >= from && $0.key <= to }).sorted(by: { $0.key < $1.key }) {
            let name = matcher.displayName(raw)
            let emoji = matcher.match(raw)?.emoji ?? ""
            lines += ["BEGIN:VEVENT",
                      "UID:shift-\(d)@shiftreminder",
                      "DTSTAMP:\(f.string(from: stamp))",
                      "DTSTART;VALUE=DATE:\(day(d))",
                      "DTEND;VALUE=DATE:\(day(d.adding(days: 1, calendar: calendar)))",
                      "SUMMARY:\(escape((emoji.isEmpty ? "" : emoji + " ") + name))",
                      "TRANSP:TRANSPARENT",
                      "END:VEVENT"]
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
