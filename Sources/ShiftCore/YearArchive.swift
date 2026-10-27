import Foundation

/// 一年的统计存档：全员排班原始数据只留一年多，一年过完把全年工作量存一份，以后能和往年比。
/// 存的是当时按当时的规则算出来的数，以后改了规则也不跟着变
public struct YearArchive: Codable, Equatable, Identifiable {
    public struct Person: Codable, Equatable {
        public var name: String
        public var workDays: Int
        public var presentDays: Int
        public var dutyDays: Int
        public var regularDays: Int
        public var tripDays: Int
        public var holidayWorkedDays: Int
        public var offDays: Int

        public init(_ p: PersonWorkload) {
            name = p.name
            workDays = p.workDays
            presentDays = p.presentDays
            dutyDays = p.dutyDays
            regularDays = p.regularDays
            tripDays = p.tripDays
            holidayWorkedDays = p.holidayWorkedDays
            offDays = p.offDays
        }
    }

    public var id: Int { year }
    public var year: Int
    /// 统计了几天（App 里有全员排班的日子）、从哪天到哪天
    public var days: Int
    public var first: DayKey?
    public var last: DayKey?
    public var people: [Person]
    public var saved: Date

    public init(year: Int, days: [DayKey], people: [PersonWorkload], saved: Date = Date()) {
        self.year = year
        self.days = days.count
        first = days.min()
        last = days.max()
        self.people = people.map(Person.init).sorted { ($1.workDays, $0.name) < ($0.workDays, $1.name) }
        self.saved = saved
    }

    /// 这一年要不要（重新）存：过完了的年份、没存过或者现在有的日子比存的时候多
    public static func needsSaving(year: Int, availableDays: Int, existing: YearArchive?, today: DayKey) -> Bool {
        guard year < today.year, availableDays > 0 else { return false }
        return (existing?.days ?? 0) < availableDays
    }

    /// 把新存的放进去（同一年替换），按年份从新到旧
    public static func merging(_ archive: YearArchive, into list: [YearArchive]) -> [YearArchive] {
        (list.filter { $0.year != archive.year } + [archive]).sorted { $0.year > $1.year }
    }

    /// 某个人历年的数（名字有几种写法时传几个），没有这个人的年份不列
    public func person(_ names: [String]) -> Person? {
        let set = Set(names)
        return people.first { set.contains($0.name) }
    }
}
