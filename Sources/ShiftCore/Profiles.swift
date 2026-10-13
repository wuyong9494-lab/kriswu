import Foundation

/// 人员档案：每个人是什么角色（可以从某天起改），什么时候来、什么时候走。
/// 有档案的按档案算；没有的按排班自动判断（见 PersonDirectory.suggest）。
public enum PersonRole: String, Codable, CaseIterable, Identifiable {
    /// 轮组别（组A–E）：没排岗位、没写休息的工作日是正常上班，不算工作量
    case group = "轮组别"
    /// 不轮组别：没排岗位、没写休息的工作日在做别的日常工作，算工作量
    case daily = "不轮组别"
    /// 调度：排班表上有名字才算一天
    case dispatch = "调度"
    /// 领导：自己没有排班，不参与统计
    case leader = "领导"

    public var id: String { rawValue }
}

public struct RoleSpan: Codable, Equatable, Hashable {
    /// 从哪天起（nil = 一直）
    public var from: DayKey?
    public var role: PersonRole

    public init(from: DayKey?, role: PersonRole) {
        self.from = from
        self.role = role
    }
}

public struct PersonProfile: Codable, Equatable {
    public var name: String
    /// 角色变化，按 from 排好；第一段一般是 from = nil
    public var spans: [RoleSpan]
    /// 来的日子（这天以前不统计）
    public var joined: DayKey?
    /// 走的日子（这天以后不统计）
    public var left: DayKey?

    public init(name: String, spans: [RoleSpan], joined: DayKey? = nil, left: DayKey? = nil) {
        self.name = name
        self.spans = spans.sorted { ($0.from ?? DayKey(year: 1900, month: 1, day: 1)) < ($1.from ?? DayKey(year: 1900, month: 1, day: 1)) }
        self.joined = joined
        self.left = left
    }

    /// 这天是什么角色（档案里没有就是 nil）
    public func role(on day: DayKey) -> PersonRole? {
        spans.last { ($0.from ?? DayKey(year: 1900, month: 1, day: 1)) <= day }?.role
    }

    /// 这天在不在岗（档案里填了来、走的日子才判断）
    public func isActive(on day: DayKey) -> Bool? {
        if joined == nil && left == nil { return nil }
        if let joined, day < joined { return false }
        if let left, day > left { return false }
        return true
    }

    /// 从 day 起改成 role（之后原来的变化不要了）
    public mutating func setRole(_ role: PersonRole, from day: DayKey?) {
        guard let day else {
            spans = [RoleSpan(from: nil, role: role)]
            return
        }
        spans.removeAll { ($0.from ?? DayKey(year: 1900, month: 1, day: 1)) >= day }
        spans.append(RoleSpan(from: day, role: role))
    }
}

public enum PersonDirectory {
    /// 按排班自动判断的角色：调度 → 轮组别 → 不轮组别
    public static func suggest(name: String, history: [DayKey: String], matcher: ShiftMatcher, asOf: DayKey? = nil) -> PersonRole {
        if WorkloadCounter.autoIsDispatch(history: history, matcher: matcher, asOf: asOf) { return .dispatch }
        if WorkloadCounter.autoIsGroupMember(history: history, matcher: matcher, asOf: asOf) { return .group }
        return .daily
    }
}

/// 规则改动的历史：until 这天以前（不含）按 rules 算
public struct RuleVersion: Codable, Equatable {
    public var until: DayKey
    public var rules: WorkloadRules

    public init(until: DayKey, rules: WorkloadRules) {
        self.until = until
        self.rules = rules
    }

    /// 从 from 起换成新规则：from 以前保持原来（按 old 历史和 current 算出的）规则
    public static func adding(_ versions: [RuleVersion], current: WorkloadRules, changeFrom from: DayKey) -> [RuleVersion] {
        let before = rules(on: from.adding(days: -1, calendar: .current), versions: versions, current: current)
        // from 以后原来的分段作废；最后一段之后到 from 之间按改之前的规则算
        var kept = versions.filter { $0.until < from }
        kept.append(RuleVersion(until: from, rules: before))
        return kept.sorted { $0.until < $1.until }
    }

    /// 某天用哪套规则
    public static func rules(on day: DayKey, versions: [RuleVersion], current: WorkloadRules) -> WorkloadRules {
        versions.sorted { $0.until < $1.until }.first { day < $0.until }?.rules ?? current
    }
}
