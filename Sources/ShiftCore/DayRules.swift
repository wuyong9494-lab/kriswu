import Foundation

/// 网站上一格写的是什么，全 App 只在这里判断。工作量、找人换班、待休、遥测推算、合并全员排班都问它，
/// 改一条规则所有页面一起变。一格里有好几项时用「+」连着（「组A+出差」），一项一项判断。
public enum DayRules {
    /// 一项是哪一类
    public enum Part: String, CaseIterable, Sendable {
        /// 遥测、值班（「值班调休」「值班休息」「值班请假」「值班交接前」不算）
        case duty = "值班"
        /// 出差：算上班、算工作量
        case trip = "出差"
        /// 组A–组E、调度、加班等具体岗位
        case post = "岗位"
        /// 「值班交接前」：前一天值了遥测，今天休息
        case handover = "值班交接前"
        case rest = "休息"
        case compLeave = "调休"
        /// 请假、休假、年假、病假、事假
        case leave = "请假"
        /// 无分工、未排班：网站上写了但没给岗位
        case none = "没排"

        /// 要上班的：值班、出差、岗位
        public var isWork: Bool { self == .duty || self == .trip || self == .post }
        /// 不上班的：休息、调休、请假、交接前、没排（出差算上班，不在这里）
        public var isOff: Bool { !isWork }
        /// 归到哪一类假（合并全员排班、遥测推算里说「他那天在休什么」）
        public var leaveCategory: String? {
            switch self {
            case .trip: return "出差"
            case .compLeave: return "调休"
            case .leave: return "请假"
            case .rest, .handover, .none: return "休息"
            case .duty, .post: return nil
            }
        }
    }

    /// 一项（已经是显示名，比如「遥测」「调休」）是哪一类
    public static func part(_ name: String, matcher: ShiftMatcher) -> Part {
        let p = name.trimmingCharacters(in: .whitespaces)
        if WorkloadCounter.isIgnored(p) || p == WorkloadCounter.handoverRest { return .handover }
        if WorkloadCounter.isDuty(p) { return .duty }
        if WorkloadCounter.isTrip(p) { return .trip }
        // 「假期加班」「加班」是上班；「加班调休」是调休
        if p.contains("加班") && !p.contains("休") { return .post }
        if p == "无分工" || p == "未排班" { return .none }
        if p.contains("调休") { return .compLeave }
        // 「节假日值班」上面已经算值班
        if p.contains("假") { return .leave }
        if p.contains("休") || matcher.match(p)?.id == "off" { return .rest }
        return .post
    }

    /// 一格拆成一项一项（显示名）
    public static func names(_ raw: String?, matcher: ShiftMatcher) -> [String] {
        guard let raw else { return [] }
        return raw.split(separator: "+").map { matcher.displayName(String($0)) }.filter { !$0.isEmpty }
    }

    /// 一格里每一项的类别
    public static func parts(_ raw: String?, matcher: ShiftMatcher) -> [Part] {
        names(raw, matcher: matcher).map { part($0, matcher: matcher) }
    }

    /// 这天要上的岗位（值班和具体岗位；出差、休息这类不算岗位）
    public static func posts(_ raw: String?, matcher: ShiftMatcher) -> [String] {
        names(raw, matcher: matcher).filter { let k = part($0, matcher: matcher); return k == .duty || k == .post }
    }

    /// 这天上班（值班、出差或者有岗位）
    public static func isWorking(_ raw: String?, matcher: ShiftMatcher) -> Bool {
        parts(raw, matcher: matcher).contains(where: \.isWork)
    }

    /// 这天整天不上班：写的全是休息、调休、请假、交接前、没排（出差算上班）
    public static func isOffDay(_ raw: String?, matcher: ShiftMatcher) -> Bool {
        let list = parts(raw, matcher: matcher)
        return !list.isEmpty && list.allSatisfy(\.isOff)
    }

    /// 休息、请假、出差这类（不是具体岗位）：读网站时判断这次读到的有没有带休息列
    public static func isLeaveOrTrip(_ raw: String?, matcher: ShiftMatcher) -> Bool {
        let list = parts(raw, matcher: matcher)
        return !list.isEmpty && list.allSatisfy { $0.isOff || $0 == .trip }
    }

    /// 找人换班时这天能不能找他：没排，或者只写了普通休息。调休、请假、出差、值班交接前都不找
    public static func canCover(_ raw: String?, matcher: ShiftMatcher) -> Bool {
        parts(raw, matcher: matcher).allSatisfy { $0 == .rest || $0 == .none }
    }

    /// 值班换来的休息：休息、调休、交接前（请假不算）
    public static func isDutyRest(_ name: String, matcher: ShiftMatcher) -> Bool {
        let k = part(name, matcher: matcher)
        return k == .rest || k == .compLeave || k == .handover
    }
}
