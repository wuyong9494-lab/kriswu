import Foundation

/// 只有本版新建日历时保存的身份、以及事件上的完整标记同时匹配，才允许同步改动。
/// 旧版的日历 ID、同名日历和无标记事件都不能证明归属。
public struct CalendarEventOwnership: Codable, Equatable, Sendable {
    public let calendarIdentifier: String
    public let ownerToken: UUID

    public init(calendarIdentifier: String, ownerToken: UUID) {
        self.calendarIdentifier = calendarIdentifier
        self.ownerToken = ownerToken
    }

    public func eventURL(for day: DayKey) -> URL {
        URL(string: "shiftreminder://managed-calendar/v2/\(ownerToken.uuidString)/\(day.description)")!
    }

    /// 比较完整地址，不能把相似前缀、另一个日历或其它安装生成的事件认领过来。
    public func managedDay(eventURL: URL?, calendarIdentifier: String) -> DayKey? {
        guard !self.calendarIdentifier.isEmpty, self.calendarIdentifier == calendarIdentifier,
              let eventURL, let day = DayKey(string: eventURL.lastPathComponent),
              eventURL.absoluteString == self.eventURL(for: day).absoluteString else { return nil }
        return day
    }
}
