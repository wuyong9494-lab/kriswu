import Foundation

/// 网站改版自检：每次读到的全员排班和平时比，人数、天数、休息条数、组别条数突然少很多，多半是网站改版、App 读错了。
public enum SyncHealth {
    public struct Metrics: Codable, Equatable {
        /// 读到几个人
        public var people: Int
        /// 读到几天
        public var days: Int
        /// 休息、调休、请假、出差 条数
        public var leaves: Int
        /// 组A–E 条数
        public var groups: Int

        public init(people: Int, days: Int, leaves: Int, groups: Int) {
            self.people = people
            self.days = days
            self.leaves = leaves
            self.groups = groups
        }
    }

    public static func metrics(_ roster: Roster, matcher: ShiftMatcher) -> Metrics {
        var days = Set<DayKey>()
        var leaves = 0, groups = 0
        for history in roster.values {
            for (day, raw) in history {
                days.insert(day)
                if RosterExtractor.isLeave(raw, matcher: matcher) { leaves += 1 }
                if raw.split(separator: "+").contains(where: { WorkloadBalance.isGroup(matcher.displayName(String($0))) }) { groups += 1 }
            }
        }
        return Metrics(people: roster.count, days: days.count, leaves: leaves, groups: groups)
    }

    static func median(_ values: [Int]) -> Int {
        let s = values.sorted()
        return s.isEmpty ? 0 : s[s.count / 2]
    }

    /// 和以前正常的几次比，返回发现的问题（空 = 正常）。至少有 3 次正常记录才比。
    public static func problems(_ m: Metrics, history: [Metrics]) -> [String] {
        guard history.count >= 3 else { return [] }
        let people = median(history.map(\.people)), days = median(history.map(\.days))
        let leaves = median(history.map(\.leaves)), groups = median(history.map(\.groups))
        var result: [String] = []
        if people >= 4 && m.people * 2 < people {
            result.append("这次只读到 \(m.people) 个人，平时有 \(people) 个")
        }
        if days >= 4 && m.days * 2 < days {
            result.append("这次只读到 \(m.days) 天，平时有 \(days) 天")
        }
        if leaves >= 5 && m.leaves == 0 {
            result.append("这次一条休息、请假都没读到，平时有 \(leaves) 条")
        }
        if groups >= 5 && m.groups == 0 {
            result.append("这次没读到组A–E，平时有 \(groups) 条")
        }
        return result
    }
}
