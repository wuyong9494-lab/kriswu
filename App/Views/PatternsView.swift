import SwiftUI

/// 排班规律：从全员排班反推遥测、调度怎么轮，值完遥测休几天，组A–E 怎么排，哪些是手动调整的。
struct SchedulePatternsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var months = 6
    @State private var result: Result?

    struct Result {
        var duty: SchedulePatterns.Rotation?
        var dispatch: SchedulePatterns.Rotation?
        var rest: SchedulePatterns.RestRule
        var groups: SchedulePatterns.GroupPattern?
        var audit: RestBalanceAudit.Result?
        var days: Int
    }

    var body: some View {
        List {
            Section {
                Picker("统计范围", selection: $months) {
                    Text("近 3 个月").tag(3)
                    Text("近半年").tag(6)
                    Text("近一年").tag(12)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("按 App 里存的全员排班统计出来的规律，不是网站真正的程序。数据越多越准：先在工作量统计页「读取今年 1 月以来全部」。")
            }
            if let result {
                if result.days == 0 {
                    Section { Text("还没有全员排班数据。").foregroundStyle(.secondary) }
                } else {
                    warningSection
                    dutySection(result.duty, title: "遥测轮转", icon: "antenna.radiowaves.left.and.right")
                    restSection(result.rest)
                    groupSection(result.groups)
                    dutySection(result.dispatch, title: "调度轮转", icon: "dial.medium")
                    auditSection(result.audit)
                }
            } else {
                Section { SkeletonRows(rows: 5) }
            }
        }
        .appList()
        .navigationTitle("排班规律")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(months)-\(store.roster.count)-\(store.publishedDays.count)") { compute() }
    }

    private func compute() {
        let start = DayKey.today.adding(days: -months * 30)
        let days = store.publishedDays.filter { $0 >= start }.sorted()
        let roster = store.roster
        let m = store.matcher
        result = Result(
            duty: SchedulePatterns.rotation(post: "遥测", roster: roster, days: days, matcher: m, calendar: .app),
            dispatch: SchedulePatterns.rotation(post: "调度", roster: roster, days: days, matcher: m, calendar: .app),
            rest: SchedulePatterns.restRule(roster: roster, days: days, published: store.publishedDays, matcher: m, calendar: .app),
            groups: SchedulePatterns.groupPattern(roster: roster, days: days, matcher: m, calendar: .app),
            audit: store.restBalanceAudit(),
            days: days.count)
    }

    /// ①②③…（序号和名字不会被拆到两行）
    static func circled(_ n: Int) -> String {
        n <= 20 ? String(UnicodeScalar(0x2460 + n - 1)!) : "\(n)\u{2060}."
    }

    private func pct(_ rate: Double) -> String { "\(Int((rate * 100).rounded()))%" }

    private func verdict(_ rate: Double) -> (String, Color) {
        rate >= 0.85 ? ("基本按规律", .green) : (rate >= 0.6 ? ("大体按规律，常有调整", .orange) : ("看不出固定规律", .secondary))
    }

    private func short(_ day: DayKey) -> String {
        "\(day.month)/\(day.day) " + SchedulePatterns.weekdayName(SchedulePatterns.weekdayIndex(day, calendar: .app))
    }

    private func name(_ n: String) -> some View {
        Text(n).fontWeight(store.isMe(n) ? .bold : .regular).foregroundStyle(store.isMe(n) ? DS.Palette.accent : Color.primary)
    }

    // MARK: 轮转

    @ViewBuilder
    private func dutySection(_ r: SchedulePatterns.Rotation?, title: String, icon: String) -> some View {
        if let r {
            let v = verdict(r.rate)
            Section {
                HStack {
                    Label(v.0, systemImage: icon).foregroundStyle(v.1).font(DS.Font.headline)
                    Spacer()
                    Text(pct(r.rate)).font(DS.Font.headline.monospacedDigit())
                }
                LabeledContent("按顺序 + 请假出差顺延", value: "猜中 \(r.matched)/\(r.slots)")
                LabeledContent("只按顺序、不顺延", value: "猜中 \(r.strictMatched)/\(r.slots)")
                Text(deferralConclusion(r)).font(.footnote).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("现在的顺序（下一个在最前）").font(.caption).foregroundStyle(.secondary)
                    Text(r.order.enumerated().map { Self.circled($0.offset + 1) + $0.element }.joined(separator: "  "))
                        .font(.subheadline)
                    Text("\(r.order.count) 人轮，平均每人约 \(Int(r.cycleDays.rounded())) 天一次").font(.caption).foregroundStyle(.secondary)
                }
                if !r.forecast.isEmpty {
                    DisclosureGroup("网站还没排的，按顺序推下去") {
                        ForEach(r.forecast, id: \.day) { f in
                            HStack { Text(short(f.day)).monospacedDigit(); Spacer(); name(f.name) }
                        }
                    }
                }
                if !r.exceptions.isEmpty {
                    DisclosureGroup("不按顺序的 \(r.exceptions.count) 次（指定日期、换班）") {
                        ForEach(Array(r.exceptions.prefix(40).enumerated()), id: \.offset) { _, e in
                            HStack {
                                Text(short(e.day)).monospacedDigit()
                                Spacer()
                                name(e.actual)
                                Text("（按顺序是 \(e.expected)）").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !r.deferrals.isEmpty {
                    DisclosureGroup("请假出差顺延 \(r.deferrals.count) 次") {
                        ForEach(Array(r.deferrals.prefix(40).enumerated()), id: \.offset) { _, e in
                            HStack {
                                Text(short(e.day)).monospacedDigit()
                                Spacer()
                                name(e.name)
                                Text(e.reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text(title)
            } footer: {
                Text("模型：轮到最久没值的人；那天请假、出差、休息或者排了别的岗位就跳过，回来后排在最前面。猜不中的多半是指定日期或换班。")
            }
        }
    }

    private func deferralConclusion(_ r: SchedulePatterns.Rotation) -> String {
        let gain = r.matched - r.strictMatched
        if r.deferrals.isEmpty { return "这段时间没有因请假、出差顺延的情况。" }
        if gain > 0 { return "请假、出差的人会自动往后顺延：考虑顺延后多猜中 \(gain) 次。" }
        return "看不出请假、出差后是顺延还是直接跳过。"
    }

    // MARK: 值完遥测休息

    @ViewBuilder
    private func restSection(_ rule: SchedulePatterns.RestRule) -> some View {
        if rule.duties > 0 {
            let v = verdict(rule.rate)
            Section {
                HStack {
                    Label(v.0, systemImage: "bed.double").foregroundStyle(v.1).font(DS.Font.headline)
                    Spacer()
                    Text(pct(rule.rate)).font(DS.Font.headline.monospacedDigit())
                }
                ForEach(rule.rows, id: \.weekday) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("\(SchedulePatterns.weekdayName(row.weekday))值").font(.subheadline.weight(.semibold))
                            Text("规则休\(row.expected)").font(.subheadline)
                            Spacer()
                            Text("符合 \(row.matched)/\(row.duties)").font(.subheadline.monospacedDigit())
                                .foregroundStyle(row.matched == row.duties ? Color.green : Color.primary)
                        }
                        Text("实际最常见：\(row.typical == "不休" ? "不休" : "休" + row.typical)（\(row.typicalCount) 次）")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !rule.exceptions.isEmpty {
                    DisclosureGroup("和规则不一样的 \(rule.exceptions.count) 次") {
                        ForEach(Array(rule.exceptions.prefix(40).enumerated()), id: \.offset) { _, e in
                            HStack {
                                Text(short(e.day)).monospacedDigit()
                                name(e.name)
                                Spacer()
                                Text("应休\(e.expected)，实际\(e.actual == "不休" ? "没休" : "休" + e.actual)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("值完遥测休几天")
            } footer: {
                Text("规则：值完遥测休两天；周五、周六、周日（节假日同理）值的多休一天，比如周五值休六日一，周日值休一二三。周末没写也算在休；看的是哪天回来上班。")
            }
        }
    }

    // MARK: 组A–E

    @ViewBuilder
    private func groupSection(_ g: SchedulePatterns.GroupPattern?) -> some View {
        if let g, let best = g.best {
            let v = verdict(best.rate)
            Section {
                HStack {
                    Label(v.0, systemImage: "person.2").foregroundStyle(v.1).font(DS.Font.headline)
                    Spacer()
                    Text(pct(best.rate)).font(DS.Font.headline.monospacedDigit())
                }
                Text("最像的排法：\(best.title)").font(.subheadline.weight(.semibold))
                ForEach(Array(g.models.dropFirst().prefix(3).enumerated()), id: \.offset) { _, model in
                    LabeledContent(model.title, value: "\(pct(model.rate))")
                        .font(.footnote)
                }
                if g.resumeTotal > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.resumeHits >= g.calendarHits ? "请假、出差回来后接着上次的组往下排（顺延）" : "请假、出差回来后按日历跳过，不顺延")
                            .font(.subheadline)
                        Text("回来接着排符合 \(g.resumeHits)/\(g.resumeTotal) 次，按日历跳过符合 \(g.calendarHits)/\(g.resumeTotal) 次")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !g.adjustments.isEmpty {
                    DisclosureGroup("最近两个月手动调整的 \(g.adjustments.count) 次") {
                        ForEach(Array(g.adjustments.enumerated()), id: \.offset) { _, a in
                            HStack {
                                Text(short(a.day)).monospacedDigit()
                                name(a.name)
                                Spacer()
                                Text("按规律 \(a.expected)，实际 \(a.actual)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("组别（\(g.groups.joined(separator: " ")) · \(g.people) 人）")
            } footer: {
                Text("把几种常见排法都拿来对一遍，看哪种和实际最吻合；不吻合的日子多半是根据实际情况手动调的。")
            }
        }
    }

    // MARK: 排班预警

    @ViewBuilder
    private var warningSection: some View {
        let warnings = store.myRestWarnings()
        Section {
            if warnings.isEmpty {
                Label("你最近和以后的遥测，休息都按规则排了", systemImage: "checkmark.circle").foregroundStyle(.green)
            }
            ForEach(warnings, id: \.key) { w in
                Label {
                    Text(w.text).font(.subheadline)
                } icon: {
                    Image(systemName: w.kind == .assigned ? "exclamationmark.triangle.fill" : "questionmark.circle")
                        .foregroundStyle(w.kind == .assigned ? DS.Palette.warning : Color.secondary)
                }
            }
        } header: {
            Text("我的排班预警")
        } footer: {
            Text("按「值完遥测休两天，周五到周日值的多休一天」核对你的排班。该休却排了岗位的，同步到时会推送提醒；网站上没写休息的只在这里和首页显示。")
        }
    }

    // MARK: 待休核对

    @ViewBuilder
    private func auditSection(_ audit: RestBalanceAudit.Result?) -> some View {
        Section {
            if let audit {
                VStack(alignment: .leading, spacing: 4) {
                    Text("反推的规则").font(.caption).foregroundStyle(.secondary)
                    Text(audit.rule.text).font(.subheadline.weight(.semibold))
                    Text("\(audit.rows.count) 人里 \(audit.matched) 人对得上").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(audit.rows, id: \.name) { row in
                    HStack {
                        name(row.name)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("网站 \(signed(row.observed)) · 按规则 \(signed(row.expected))").font(.caption.monospacedDigit())
                            Text("\(row.from.month)/\(row.from.day)–\(row.to.month)/\(row.to.day)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(row.diff == 0 ? "对" : signed(row.diff))
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(row.diff == 0 ? Color.green : DS.Palette.warning)
                            .frame(minWidth: 28)
                    }
                }
            } else {
                Text("待休记录还不够：至少要两个人、每人三周以上的记录。先在工作量统计页「读取今年 1 月以来全部」。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("待休核对")
        } footer: {
            Text("拿每个人记录里第一次和最后一次的待休天数，和这段时间排的遥测、加班、休息、调休、请假对比，找一条最吻合的加减规则。对不上的多半是网站手动改过，或者有 App 没读到的加减。")
        }
    }

    private func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : (n < 0 ? "−\(abs(n))" : "0") }
}
