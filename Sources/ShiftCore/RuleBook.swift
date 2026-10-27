import Foundation

/// 「规则说明」页的内容：App 里所有「怎么算」的规则用大白话列出来。
/// 每条带几个例子，页面上的例子结果是按现在的代码和设置当场算的；单元测试按默认设置逐条核对写的结果和算的一样，
/// 改了代码没改说明（或者反过来）测试就不过。
public enum RuleBook {
    /// 例子怎么算
    public enum Check: Equatable, Hashable {
        /// 网站上这一项算哪一类
        case part
        /// 找人换班时这天能不能找他
        case cover
        /// 周会「完成情况」里这句话算不算解决
        case note
        /// 工作量：工作日、周末、法定节假日写了这个（空的写「」）
        case workday, weekend, holiday
    }

    public struct Example: Equatable, Hashable {
        /// 页面上显示的（「工作日什么都没写」）
        public var label: String
        public var input: String
        /// 写在说明里的结果（默认设置下）
        public var result: String
        public var check: Check
    }

    public struct Rule: Equatable, Identifiable {
        public var id: String { text }
        public var text: String
        public var examples: [Example]
    }

    public struct Section: Equatable, Identifiable {
        public var id: String { title }
        public var title: String
        public var rules: [Rule]
    }

    private static func ex(_ input: String, _ result: String, _ check: Check = .part, label: String? = nil) -> Example {
        Example(label: label ?? (input.isEmpty ? "什么都没写" : input), input: input, result: result, check: check)
    }

    private static func rule(_ text: String, _ examples: Example...) -> Rule { Rule(text: text, examples: examples) }

    public static func sections(rules r: WorkloadRules = WorkloadRules(), saturdayIsWorkday: Bool = true) -> [Section] {
        [
            Section(title: "网站上写的是什么", rules: [
                rule("「遥测」「值班」算值班；「值班调休」「值班休息」「值班请假」是值完班后的休息，不算值班。",
                     ex("遥测", "值班"), ex("节假日值班", "值班"), ex("值班调休", "调休")),
                rule("「值班交接前」：前一天值了遥测，今天休息。", ex("值班交接前", "值班交接前")),
                rule("出差算上班、算工作量。", ex("出差", "出差")),
                rule("休息、调休、请假都不上班；休假、年假、病假、事假都算请假。",
                     ex("休息", "休息"), ex("调休", "调休"), ex("休假", "请假"), ex("年假", "请假")),
                rule("加班算上班；「加班调休」是调休。", ex("假期加班", "岗位"), ex("加班调休", "调休")),
                rule("「无分工」「未排班」：网站上写了，但没给岗位。", ex("无分工", "没排")),
                rule("组A–组E、调度和其它写法都是具体岗位。", ex("组A", "岗位"), ex("调度", "岗位")),
            ]),
            Section(title: "工作量", rules: [
                rule("算工作量的：值班、出差、日常岗位（组别、调度等）。不算的：休息、调休、请假、值班交接前。",
                     ex("遥测", "值班，算工作量", .workday, label: "工作日写了遥测"),
                     ex("组A", "日常，算工作量", .workday, label: "工作日写了组A"),
                     ex("出差", "出差，算工作量", .workday, label: "工作日写了出差"),
                     ex("调休", "休息，不算工作量", .workday, label: "工作日写了调休"),
                     ex("值班交接前", "休息，不算工作量", .workday, label: "工作日写了值班交接前")),
                rule(r.blankWorkdayIsWork
                     ? "工作日网站上没排岗位、也没写休息：正常上班，算工作量（调度除外）。轮组别的人另外数出这种日子有几天。"
                     : "工作日网站上没排岗位、也没写休息：不算上班（设置里关了「没排岗位算正常上班」）。",
                     ex("", "日常，算工作量", .workday, label: "工作日什么都没写")),
                rule(r.dispatchScheduleOnly
                     ? "调度只算排班表上有名字的日子：工作日没排他的那天不算工作量，也不算休息。"
                     : "调度和别人一样算（设置里关了「调度只按排班算」）。"),
                rule(saturdayIsWorkday
                     ? "周六是工作日（法定节假日除外），周日是休息日。"
                     : "周六、周日都是休息日（设置里关了「周六算工作日」）。",
                     ex("", "休息，不算工作量", .weekend, label: "周日什么都没写")),
                rule("法定节假日网站上没排岗位：算节假日，不算工作量。",
                     ex("", "节假日，不算工作量", .holiday, label: "国庆什么都没写")),
                rule(r.blankHolidayAfterDutyIsRest
                     ? "假期里值完遥测的第二天网站上没写：算值班调休，算工作量（设置里打开了）。"
                     : "假期里值完遥测的第二天（不是假期最后一天）网站上没写：休息，算上班天数和节假日上班，不算工作量。"),
                rule(r.holidayDutyRestCounts
                     ? "法定节假日值完遥测后写了休息、调休的：算值班调休，算工作量（设置里打开了）。"
                     : "法定节假日值完遥测后写了休息、调休的：和平时一样是休息，不算工作量。"),
            ]),
            Section(title: "值完遥测休几天", rules: [
                rule("平时值的休 2 天；周五、周六、周日或者节假日值的多休 1 天。"),
                rule("节假日期间值的（不是假期最后一天），只休第二天。"),
            ]),
            Section(title: "找人换班", rules: [
                rule("只找那天没排班或者正常休息的人；调休、请假、出差、值班交接前的不找。",
                     ex("", "能找", .cover, label: "那天什么都没写"), ex("休息", "能找", .cover),
                     ex("调休", "不找", .cover), ex("出差", "不找", .cover), ex("值班交接前", "不找", .cover)),
                rule("刚值完遥测、还在休息的不找。"),
                rule("我值遥测要换出去：第二天有岗位的不找（会连着上）。"),
                rule("遥测找值过遥测的人，组别找轮过组别的人。"),
                rule("排在前面的：欠我班的、和我换过的、以后正好能换回来的、这个月上班少的。"),
            ]),
            Section(title: "周会问题", rules: [
                rule("「完成情况」写了完成、上线、已解决、闭环这类：解决了；写了进行中、待、计划、再讨论、跟进这类：没解决。",
                     ex("上线", "解决了", .note), ex("已解决", "解决了", .note),
                     ex("进行中", "没解决", .note), ex("计划完成", "没解决", .note)),
                rule("「完成情况」只写了别的（比如一个问句）：看这一行「计划完成时间」写没写「已完成」。",
                     ex("部署更新？", "看计划完成时间", .note)),
                rule("上周还在提、这周文档里没再提的：标成待确认，你点「已解决」或「还没解决」。"),
                rule("挂了两周起标橙色，四周起标红色。"),
                rule("负责人里有你在「账号与同步」里填的名字（任一种写法），就算你负责的（「陈晨（组A）」也算）；只有一个字的名字要一模一样才算。"),
            ]),
        ]
    }

    /// 按现在的代码和设置算出这个例子的结果（页面上显示这个；测试核对和写的一样）
    public static func actual(_ e: Example, matcher: ShiftMatcher, rules: WorkloadRules = WorkloadRules()) -> String {
        let raw: String? = e.input.isEmpty ? nil : e.input
        switch e.check {
        case .part:
            return DayRules.part(e.input, matcher: matcher).rawValue
        case .cover:
            return DayRules.canCover(raw, matcher: matcher) ? "能找" : "不找"
        case .note:
            if MeetingTable.isDoneNote(e.input) { return "解决了" }
            return MeetingTable.isNotDoneNote(e.input) ? "没解决" : "看计划完成时间"
        case .workday, .weekend, .holiday:
            let x = WorkloadCounter.explain(raw, workday: e.check == .workday, holiday: e.check == .holiday,
                                            rotating: false, groupMember: false, rules: rules, matcher: matcher)
            return x.kind.rawValue + (x.kind.isWorkload ? "，算工作量" : "，不算工作量")
        }
    }
}
