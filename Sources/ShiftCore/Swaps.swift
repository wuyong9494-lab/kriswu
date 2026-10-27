import Foundation

/// 换班账本里的一条：某天谁替谁上了班。
/// effect：+1 他欠我一天（我替他上了），-1 我欠他一天（他替我上了），0 当天对换、两清。
public struct SwapRecord: Codable, Hashable, Identifiable {
    public var id: UUID
    public var detected: Date
    public var day: DayKey
    public var person: String
    /// 这天我原来 → 现在
    public var myOld: String
    public var myNew: String
    public var effect: Int
    /// 已经还清（手动标记）
    public var settled: Bool
    /// 手动添加的
    public var manual: Bool

    public init(id: UUID = UUID(), detected: Date = Date(), day: DayKey, person: String, myOld: String, myNew: String,
                effect: Int, settled: Bool = false, manual: Bool = false) {
        self.id = id
        self.detected = detected
        self.day = day
        self.person = person
        self.myOld = myOld
        self.myNew = myNew
        self.effect = effect
        self.settled = settled
        self.manual = manual
    }

    public var summary: String {
        switch effect {
        case 1: return "我替\(person)上了\(myNew)（\(person)欠我一天）"
        case -1: return "\(person)替我上了\(myOld)（我欠\(person)一天）"
        default: return "和\(person)对换：我\(myOld)→\(myNew)"
        }
    }
}

public enum SwapLedger {
    static func key(_ s: String) -> String { s.filter { !$0.isWhitespace }.uppercased() }

    /// 真正要上的岗位（不含休息、请假、出差、未排班；规则在 DayRules）
    static func posts(_ raw: String?, matcher: ShiftMatcher) -> [String] {
        DayRules.posts(raw, matcher: matcher)
    }

    /// 从一处排班变动推断换班：我丢掉的岗位现在是谁上（他替我），我新接的岗位原来是谁的（我替他）。
    /// 两件事是同一个人就是当天对换。只在这一天的全员排班是这次刚读到的时候（fresh）才判断。
    public static func detect(_ change: ScheduleChange, before: Roster, after: Roster, fresh: Bool,
                              matcher: ShiftMatcher, isMe: (String) -> Bool, now: Date = Date()) -> [SwapRecord] {
        let day = change.day
        // 之前没读到过这天的全员排班，就分不出谁是新接手的
        guard fresh, before.values.contains(where: { $0[day] != nil }) else { return [] }
        let oldPosts = posts(change.old, matcher: matcher), newPosts = posts(change.new, matcher: matcher)
        let gained = newPosts.filter { g in !oldPosts.contains { key($0) == key(g) } }
        let lost = oldPosts.filter { g in !newPosts.contains { key($0) == key(g) } }
        func has(_ name: String, _ post: String, in r: Roster) -> Bool {
            posts(r[name]?[day], matcher: matcher).contains { key($0) == key(post) }
        }
        let people = Set(before.keys).union(after.keys).filter { !isMe($0) }
        // 替我上的：现在有我丢掉的岗位，之前没有
        let coveredMe = Set(people.filter { p in lost.contains { has(p, $0, in: after) && !has(p, $0, in: before) } })
        // 我替他的：之前有我新接的岗位，现在没有
        let iCovered = Set(people.filter { p in gained.contains { has(p, $0, in: before) && !has(p, $0, in: after) } })
        let myOld = change.old.map(matcher.displayName) ?? "没排班"
        let myNew = change.new.map(matcher.displayName) ?? "没排班"
        return coveredMe.union(iCovered).sorted().map { p in
            let effect = coveredMe.contains(p) && iCovered.contains(p) ? 0 : (coveredMe.contains(p) ? -1 : 1)
            return SwapRecord(detected: now, day: day, person: p, myOld: myOld, myNew: myNew, effect: effect)
        }
    }

    /// 每个人的账：正数他欠我几天，负数我欠他几天（已还清的不算）
    public static func balances(_ records: [SwapRecord]) -> [String: Int] {
        var result: [String: Int] = [:]
        for r in records where !r.settled { result[r.person, default: 0] += r.effect }
        return result
    }

    /// 加入新记录：同一天、同一个人、同样结果的不重复记。
    public static func merge(_ new: [SwapRecord], into records: inout [SwapRecord]) {
        for r in new where !records.contains(where: { $0.day == r.day && $0.person == r.person && $0.effect == r.effect }) {
            records.append(r)
        }
        records.sort { ($0.day, $0.detected) > ($1.day, $1.detected) }
    }
}

/// 换班助手：我想把某天的班换出去，谁能替我。
public struct SwapCandidate: Equatable {
    public var name: String
    /// 他那天在干什么（没排班、休息、调休…）
    public var thatDay: String
    /// 他欠我几天（负数我欠他）
    public var owesMe: Int
    /// 以前和我换过几次
    public var pastSwaps: Int
    /// 这个月（到这天为止）他上了几天班
    public var recentWork: Int
    /// 以后两周里他有班、我正好没班的日子（可以换回来）
    public var returnDays: [DayKey]
    /// 为什么排在前面
    public var reasons: [String]
}

public enum SwapFinder {
    /// day：要换出去的那天；myPost：我那天的岗位；mine：我的排班；roster：全员排班；records：换班账本。
    public static func candidates(day: DayKey, myPost: String, mine: [DayKey: String], roster: Roster,
                                  records: [SwapRecord], matcher: ShiftMatcher, isMe: (String) -> Bool,
                                  calendar: Calendar = .current) -> [SwapCandidate] {
        let wantDuty = WorkloadCounter.isDuty(matcher.displayName(myPost))
        let wantGroup = matcher.displayName(myPost).split(separator: "+").contains { GroupNotes.isGroup(String($0)) }
        let balances = SwapLedger.balances(records)
        let window = day.adding(days: -14, calendar: calendar)...day.adding(days: 14, calendar: calendar)
        let monthStart = DayKey(year: day.year, month: day.month, day: 1)
        // 有空：没排，或者只是普通休息（调休、请假、出差、值班交接前都不算有空）；有班：排了岗位
        func free(_ raw: String?) -> Bool { DayRules.canCover(raw, matcher: matcher) }
        func works(_ raw: String?) -> Bool { !DayRules.posts(raw, matcher: matcher).isEmpty }
        func isDutyDay(_ raw: String?) -> Bool { raw.map { WorkloadCounter.isDuty(matcher.displayName($0)) } ?? false }

        var result: [SwapCandidate] = []
        for (name, history) in roster where !isMe(name) {
            // 最近两周在网站上出现过（调走的人不算）
            guard history.keys.contains(where: window.contains) else { continue }
            let raw = history[day]
            // 那天要有空：没排岗位，也不是调休、请假、出差（只有普通休息、没排班的能找）
            guard free(raw) else { continue }
            // 还在值完遥测后的休息里（休两三天），不打扰
            guard !(1...3).contains(where: { back in
                let d = day.adding(days: -back, calendar: calendar)
                return isDutyDay(history[d]) && SchedulePatterns.expectedRest(after: d, calendar: calendar).contains(day)
            }) else { continue }
            let all = history.values.map { matcher.displayName($0) }
            // 遥测找值过遥测的人，组别找轮过组别的人
            if wantDuty && !all.contains(where: WorkloadCounter.isDuty) { continue }
            if wantGroup && !all.contains(where: { $0.split(separator: "+").contains { GroupNotes.isGroup(String($0)) } }) { continue }
            // 我上遥测换给他：他第二天有班就会连上，不推荐
            if wantDuty && works(history[day.adding(days: 1, calendar: calendar)]) { continue }

            let past = records.filter { $0.person == name }.count
            let recent = (0...max(0, calendar.dateComponents([.day], from: monthStart.date(calendar: calendar, hour: 12),
                                                              to: day.date(calendar: calendar, hour: 12)).day ?? 0))
                .map { monthStart.adding(days: $0, calendar: calendar) }
                .filter { !SwapLedger.posts(history[$0], matcher: matcher).isEmpty }.count
            let back = (1...14).map { day.adding(days: $0, calendar: calendar) }
                .filter { works(history[$0]) && free(mine[$0]) && !isDutyDay(mine[$0.adding(days: -1, calendar: calendar)]) }
            var reasons: [String] = []
            let owes = balances[name] ?? 0
            if owes > 0 { reasons.append("欠你 \(owes) 天") }
            if owes < 0 { reasons.append("你欠他 \(-owes) 天") }
            if past > 0 { reasons.append("换过 \(past) 次") }
            if !back.isEmpty { reasons.append("可以换回来") }
            result.append(SwapCandidate(name: name, thatDay: raw.map(matcher.displayName) ?? "没排班", owesMe: owes,
                                        pastSwaps: past, recentWork: recent, returnDays: Array(back.prefix(3)),
                                        reasons: reasons))
        }
        // 欠我的优先，其次换过的、能换回来的、这个月上班少的
        return result.sorted {
            ($0.owesMe, $0.pastSwaps, $0.returnDays.isEmpty ? 0 : 1, -$0.recentWork, $1.name)
                > ($1.owesMe, $1.pastSwaps, $1.returnDays.isEmpty ? 0 : 1, -$1.recentWork, $0.name)
        }
    }
}

/// 全员排班里某天某个岗位换了人（谁和谁换了班）
public struct TeamChange: Codable, Hashable, Identifiable {
    public var id: UUID
    public var detected: Date
    public var day: DayKey
    public var post: String
    public var from: [String]
    public var to: [String]

    public init(id: UUID = UUID(), detected: Date = Date(), day: DayKey, post: String, from: [String], to: [String]) {
        self.id = id
        self.detected = detected
        self.day = day
        self.post = post
        self.from = from
        self.to = to
    }

    public var summary: String {
        "\(post)：\(from.isEmpty ? "（没人）" : from.joined(separator: "、")) → \(to.isEmpty ? "（没人）" : to.joined(separator: "、"))"
    }

    public func involves(_ name: String) -> Bool { from.contains(name) || to.contains(name) }
}

public enum RosterDiff {
    /// 某天每个岗位（组别、遥测、调度等，不含休息）是谁
    static func holders(_ roster: Roster, day: DayKey, matcher: ShiftMatcher) -> [String: (post: String, names: [String])] {
        var result: [String: (post: String, names: [String])] = [:]
        for (name, days) in roster {
            for post in SwapLedger.posts(days[day], matcher: matcher) {
                let key = SwapLedger.key(post)
                result[key, default: (post, [])].names.append(name)
            }
        }
        return result.mapValues { ($0.post, $0.names.sorted()) }
    }

    /// days：这次重新读到、之前也读到过的日子
    public static func changes(before: Roster, after: Roster, days: Set<DayKey>, matcher: ShiftMatcher,
                               now: Date = Date()) -> [TeamChange] {
        var result: [TeamChange] = []
        for day in days.sorted() {
            // 这次读到的人比上次少一半以上：多半是没读全，不比
            let countBefore = before.values.filter { $0[day] != nil }.count
            let countAfter = after.values.filter { $0[day] != nil }.count
            guard countAfter * 2 >= countBefore else { continue }
            let b = holders(before, day: day, matcher: matcher), a = holders(after, day: day, matcher: matcher)
            for key in Set(b.keys).union(a.keys).sorted() {
                // 岗位之前没人或现在没人（第一次排出来、取消了）不算换班
                guard let from = b[key]?.names, let to = a[key]?.names, Set(from) != Set(to) else { continue }
                result.append(TeamChange(detected: now, day: day, post: a[key]?.post ?? b[key]?.post ?? key,
                                         from: from.filter { !to.contains($0) }, to: to.filter { !from.contains($0) }))
            }
        }
        return result
    }
}
