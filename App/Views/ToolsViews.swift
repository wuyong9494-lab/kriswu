import Charts
import SwiftUI

// MARK: - 换班助手

/// 想把某天的班换出去：从全员排班里找那天有空、能替你的人。
struct SwapHelperView: View {
    @EnvironmentObject private var store: AppStore
    let day: DayKey

    var body: some View {
        let myPost = store.shift(on: day) ?? ""
        let list = SwapFinder.candidates(day: day, myPost: myPost, mine: store.schedule, roster: store.roster,
                                         records: store.settings.swapRecords, matcher: store.matcher,
                                         isMe: store.isMe, calendar: .app)
        List {
            Section {
                LabeledContent(day.dateText, value: store.matcher.displayName(myPost))
            } footer: {
                Text("找的是那天没排岗位（没排班、休息）的人；前一天值了遥测在调休的、请假出差的不算。"
                     + (WorkloadCounter.isDuty(store.matcher.displayName(myPost)) ? "遥测只找值过遥测、第二天没班的人。" : "")
                     + "欠你班的、和你换过的、以后有班正好能换回来的排在前面。")
            }
            if store.roster.isEmpty {
                Text("还没有全员排班数据，先同步一次。").foregroundStyle(.secondary)
                SyncNowButton(source: "找人换班")
            } else if list.isEmpty {
                Text("那天没找到合适的人。").foregroundStyle(.secondary)
            }
            ForEach(list, id: \.name) { c in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Avatar(name: c.name, size: 32)
                        Text(c.name).font(DS.Font.headline)
                        Text(c.thatDay).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("本月已上 \(c.recentWork) 天").font(.caption).foregroundStyle(.secondary)
                    }
                    if !c.reasons.isEmpty {
                        Text(c.reasons.joined(separator: " · ")).font(.subheadline)
                            .foregroundStyle(c.owesMe > 0 ? Color.green : Color.primary)
                    }
                    if !c.returnDays.isEmpty {
                        Text("可以换回来的日子：" + c.returnDays.map { "\($0.dateText) \(store.roster[c.name]?[$0].map(store.matcher.displayName) ?? "")" }
                            .joined(separator: "、"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    let request = requestText(to: c.name, myPost: myPost, returnDays: c.returnDays)
                    HStack(spacing: DS.Space.s) {
                        Button {
                            UIPasteboard.general.string = request
                            Haptics.success()
                            ToastCenter.shared.show("已复制，去微信粘贴发给\(c.name)", style: .success)
                        } label: { Label("复制请求", systemImage: "doc.on.doc") }
                        ShareLink(item: request) { Label("发给他", systemImage: "square.and.arrow.up") }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .padding(.top, 2)
                }
                .padding(.vertical, 2)
            }
        }
        .appList()
        .navigationTitle("找人换班")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 发给同事的换班请求：哪天、什么班，能换回来就写上哪天
    private func requestText(to name: String, myPost: String, returnDays: [DayKey]) -> String {
        let post = store.matcher.displayName(myPost)
        let what = "我 \(day.month)月\(day.day)日（\(day.weekdayText)）" + (post.isEmpty ? "有班" : "排了「\(post)」")
        let back: String
        if let r = returnDays.first {
            let theirs = store.roster[name]?[r].map(store.matcher.displayName) ?? ""
            back = "我可以 \(r.month)月\(r.day)日（\(r.weekdayText)）替你" + (theirs.isEmpty ? "" : "的「\(theirs)」") + "换回来"
        } else {
            back = "以后你想换班我来补"
        }
        return "\(name)你好，\(what)，想请你帮忙替一下，\(back)。方便的话回我一下，谢谢！"
    }
}

// MARK: - 换班账本

/// 谁替我上过班、我替谁上过班：排班变动时自动记下，也可以手动记。
struct SwapLedgerView: View {
    @EnvironmentObject private var store: AppStore
    @State private var adding = false

    var body: some View {
        let records = store.settings.swapRecords
        let balances = SwapLedger.balances(records).filter { $0.value != 0 }
            .sorted { (abs($0.value), $1.key) > (abs($1.value), $0.key) }
        List {
            Section {
                if balances.isEmpty {
                    Text("没有没还的班").foregroundStyle(.secondary)
                }
                ForEach(balances, id: \.key) { name, value in
                    HStack {
                        Avatar(name: name, size: 28)
                        Text(name).font(DS.Font.headline)
                        Spacer()
                        Text(value > 0 ? "欠你 \(value) 天" : "你欠 \(-value) 天")
                            .foregroundStyle(value > 0 ? Color.green : Color.orange)
                        ConfirmButton(title: "还清", message: "和\(name)之间的换班记录都标成已还清。", role: nil) { settle(name) }
                            .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text("账")
            } footer: {
                Text("排班有变动时自动记：你原来的岗位现在是谁在上（他替你，你欠他），你新接的岗位原来是谁的（你替他，他欠你）；当天互换的算两清。不准的记录左滑删掉。")
            }
            Section("记录") {
                if records.isEmpty { Text("还没有记录").foregroundStyle(.secondary) }
                ForEach(records) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(r.day.dateText).font(.subheadline.bold())
                            if r.manual { Text("手动").font(.caption2).foregroundStyle(.secondary) }
                            if r.settled { Text("已还清").font(.caption2).foregroundStyle(.secondary) }
                        }
                        Text(r.summary).font(.subheadline).foregroundStyle(r.settled ? .secondary : .primary)
                    }
                }
                .onDelete { offsets in
                    store.settings.swapRecords.remove(atOffsets: offsets)
                }
            }
        }
        .appList()
        .navigationTitle("换班账本")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Label("手动记一笔", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $adding) { AddSwapView() }
    }

    private func settle(_ name: String) {
        var records = store.settings.swapRecords
        for i in records.indices where records[i].person == name { records[i].settled = true }
        store.settings.swapRecords = records
    }
}

private struct AddSwapView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var person = ""
    @State private var iCovered = true

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("日期", selection: $date, displayedComponents: .date)
                TextField("同事名字", text: $person)
                Picker("谁替谁", selection: $iCovered) {
                    Text("我替他上了班").tag(true)
                    Text("他替我上了班").tag(false)
                }
                .pickerStyle(.inline)
            }
            .appList()
            .navigationTitle("手动记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let day = DayKey(date: date, calendar: .app)
                        let name = person.trimmingCharacters(in: .whitespaces)
                        let post = store.shift(on: day).map(store.matcher.displayName) ?? "班"
                        var records = store.settings.swapRecords
                        records.append(SwapRecord(day: day, person: name, myOld: post, myNew: post,
                                                  effect: iCovered ? 1 : -1, manual: true))
                        records.sort { ($0.day, $0.detected) > ($1.day, $1.detected) }
                        store.settings.swapRecords = records
                        dismiss()
                    }
                    .disabled(person.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - 全年统计

struct YearStatsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var year = DayKey.today.year
    @State private var file: URL?
    @State private var report: AppStore.Workload?

    var body: some View {
        let report = self.report ?? AppStore.Workload(days: [], people: [], text: "")
        List {
            Section {
                HStack {
                    Button { year -= 1 } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(verbatim: "\(year)年全年").font(.headline)
                    Spacer()
                    Button { year += 1 } label: { Image(systemName: "chevron.right") }
                        .disabled(year >= DayKey.today.year)
                }
                .buttonStyle(.borderless)
                if let file {
                    ShareLink(item: file) { Label("导出表格（Excel 能打开）", systemImage: "tablecells") }
                }
                NavigationLink { YearSummaryView(year: year) } label: {
                    Label("我的 \(String(year)) 年度总结（可存图片）", systemImage: "star.circle")
                }
                Button {
                    Task { await store.readHistory(since: year) }
                } label: {
                    HStack {
                        Text("从电脑版网页读取 \(String(year)) 年 1 月以来的全员排班")
                        if store.isReadingDesktop { Spacer(); DSSpinner() }
                    }
                }
                .disabled(store.isReadingDesktop || !store.canSync)
                if let message = store.settings.desktopRosterMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                if self.report == nil {
                    SkeletonRows(rows: 3)
                } else if report.days.isEmpty {
                    Text("这一年还没有全员排班数据。")
                } else {
                    ExpandableText(text: "统计 \(report.days.first!.dateText) – \(report.days.last!.dateText) 共 \(report.days.count) 天（只算到今天），规则和每月统计一样。前面缺的月份点上面的按钮，用电脑版「值班查看」一周周往前翻着读（翻几十周要 1–2 分钟，读的时候别离开 App）。")
                }
            }
            ForEach(report.people, id: \.name) { p in
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack(alignment: .center) {
                        Avatar(name: p.name, size: 30)
                        Text(p.name).font(DS.Font.headline)
                            .foregroundStyle(store.isMe(p.name) ? DS.Palette.accent : Color.primary)
                        Spacer()
                        WorkPresentPair(work: p.workDays, present: p.presentDays)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Space.xxs) {
                            Chip(text: "遥测 \(p.dutyDays)", color: DS.Palette.accent)
                            Chip(text: "节假日上班 \(p.holidayWorkedDays)", color: .secondary)
                            Chip(text: "日常 \(p.regularDays)", color: .secondary)
                            if p.dutyRestDays > 0 { Chip(text: "值班调休 \(p.dutyRestDays)", color: .secondary) }
                            if p.tripDays > 0 { Chip(text: "出差 \(p.tripDays)", color: .secondary) }
                            Chip(text: "休息 \(p.offDays)", color: .secondary)
                            Chip(text: "节假日 \(p.holidayDays)", color: .secondary)
                        }
                    }
                }
                .padding(.vertical, DS.Space.xxs)
            }
        }
        .appList()
        .navigationTitle("全年统计")
        .navigationBarTitleDisplayMode(.inline)
        // 全年数据量大：换年份或全员排班更新时算一次，不在每次刷新界面时重算
        .task(id: "\(year)-\(store.dataRevision)") {
            let r = store.workload(year: year, month: nil)
            self.report = r
            file = store.workloadCSVFile(year: year, month: nil, report: r)
        }
    }
}

// MARK: - 遥测轮转预测

struct DutyForecastView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let today = DayKey.today
        let list = DutyForecaster.forecast(roster: store.roster, today: today, matcher: store.matcher, calendar: .app)
        List {
            if let turn = store.myDutyTurn() {
                Section {
                    if turn.scheduled, let day = turn.day {
                        LabeledContent("网站已排", value: day.dateText)
                    } else {
                        LabeledContent("前面还有", value: turn.ahead == 0 ? "下一个就是你" : "\(turn.ahead) 人（共 \(turn.total) 人轮）")
                        if let day = turn.day { LabeledContent("大约", value: day.dateText) }
                    }
                    NavigationLink("看完整顺序和规律") { SchedulePatternsView() }
                } header: {
                    Text("按顺序推算（请假出差自动顺延）")
                } footer: {
                    Text("和今天页、小组件是同一个结果：网站排好的优先，没排的按排班规律推出的顺序推算（请假、出差、休息的跳过，回来后优先）。")
                }
            }
            Section {
                ForEach(list.filter { !store.isMe($0.name) }, id: \.name) { row($0, today: today) }
            } header: {
                Text("接下来大概轮到谁")
            } footer: {
                Text("按每个人过去值遥测的间隔（取中间值）推算：已经排好的显示排好的日子，没排的 = 上次 + 间隔。只是估计，换班、请假、出差都会打乱。")
            }
        }
        .appList()
        .navigationTitle("遥测轮转预测")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ f: DutyForecast, today: DayKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Avatar(name: f.name, size: 28)
                Text(f.name).font(DS.Font.headline)
                Spacer()
                if let s = f.scheduled {
                    Text("已排 \(s.dateText)").foregroundStyle(Color.accentColor)
                } else if let p = f.predicted {
                    Text("约 \(p.dateText)")
                } else {
                    Text("推算不出").foregroundStyle(.secondary)
                }
            }
            Text("共 \(f.count) 次" + (f.last.map { " · 上次 \($0.dateText)" } ?? "")
                 + (f.interval.map { " · 大约每 \($0) 天一次" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 待休趋势

struct RestTrendView: View {
    @EnvironmentObject private var store: AppStore
    @State private var name: String?

    init(name: String? = nil) { _name = State(initialValue: name) }

    var body: some View {
        let zh = Locale(identifier: "zh_CN")
        let me = store.myRosterName
        let names = store.settings.restBalance.keys.sorted { a, b in
            a == me ? true : (b == me ? false : a.compare(b, locale: zh) == .orderedAscending)
        }
        let selected = name ?? me ?? names.first
        let points = selected.flatMap { store.settings.restHistory[$0] } ?? []
        List {
            if let selected {
                Section {
                    Picker("看谁", selection: Binding(get: { selected }, set: { name = $0 })) {
                        ForEach(names, id: \.self) { Text($0).tag($0) }
                    }
                    LabeledContent("现在待休", value: "\(store.settings.restBalance[selected] ?? 0) 天")
                    if points.count >= 2 {
                        Chart(points, id: \.day) { p in
                            AreaMark(x: .value("日期", p.day.date(calendar: .app, hour: 12)), y: .value("待休", p.value))
                                .interpolationMethod(.stepEnd)
                                .foregroundStyle(LinearGradient(colors: [DS.Palette.accent.opacity(0.28), DS.Palette.accent.opacity(0.02)],
                                                                startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("日期", p.day.date(calendar: .app, hour: 12)), y: .value("待休", p.value))
                                .interpolationMethod(.stepEnd)
                                .foregroundStyle(DS.Palette.accent)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            PointMark(x: .value("日期", p.day.date(calendar: .app, hour: 12)), y: .value("待休", p.value))
                                .foregroundStyle(DS.Palette.accent)
                                .symbolSize(36)
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(DS.Palette.hairline)
                                AxisValueLabel().font(DS.Font.caption)
                            }
                        }
                        .chartXAxis {
                            AxisMarks { _ in AxisValueLabel(format: .dateTime.month().day()).font(DS.Font.caption) }
                        }
                        .frame(height: 200)
                        .padding(.vertical, DS.Space.xs)
                    } else {
                        Text("数字变过两次以上才画得出趋势。App 每次同步读到人名后面的括号数字时记一笔。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                RestStepsSection(name: selected)
            } else {
                Text("还没读到待休天数（人名后面括号里的数字）。").foregroundStyle(.secondary)
            }
            Section {
                Stepper(store.settings.restAlertThreshold == 0 ? "不提醒" : "攒到 \(store.settings.restAlertThreshold) 天提醒我",
                        value: $store.settings.restAlertThreshold, in: 0...30)
            } footer: {
                Text("你的待休到了这个数会提醒一次，之后再涨才再提醒。" + (me == nil ? "（还没在全员排班里认出你的名字，先在「账号与同步」里填好名字。）" : ""))
            }
        }
        .appList()
        .navigationTitle("待休趋势")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 法定节假日

struct HolidaysView: View {
    @EnvironmentObject private var store: AppStore
    @State private var text = ""
    @State private var year = DayKey.today.year + 1
    @State private var message: String?

    var body: some View {
        let years = ChinaHolidays.knownYears.sorted()
        List {
            Section {
                LabeledContent("已有安排的年份", value: years.map(String.init).joined(separator: "、"))
                if !ChinaHolidays.knownYears.contains(DayKey.today.year + 1) {
                    Text("还没有 \(DayKey.today.year + 1) 年的安排。国务院一般在年底公布，公布后在下面粘贴，或者等 App 更新。")
                        .font(.footnote).foregroundStyle(.orange)
                }
            } footer: {
                Text("统计工作量时：法定假日里没排岗位的算「节假日」，调休上班的周末算工作日。")
            }
            Section {
                Stepper(value: $year, in: 2024...2040) { Text(verbatim: "年份：\(year)") }
                TextField("""
                每行一条，例如：
                1月1日至1月3日 放假
                2月6日至12日 春节放假
                2月14日 上班
                """, text: $text, axis: .vertical)
                .lineLimit(5...12)
                Button("加入") { add() }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } header: {
                Text("自己补充")
            } footer: {
                Text("可以直接粘贴通知里的句子，每个假期一行；写了「上班」「补班」的是调休上班的日子，其余算放假。没写年份的按上面的年份。")
            }
            let off = store.settings.customHolidayOff.sorted(), work = store.settings.customHolidayWork.sorted()
            if !off.isEmpty || !work.isEmpty {
                Section("已补充") {
                    if !off.isEmpty { Text("放假：" + off.joined(separator: "、")).font(.footnote) }
                    if !work.isEmpty { Text("上班：" + work.joined(separator: "、")).font(.footnote) }
                    ConfirmButton(title: "全部清除", message: "自己补充的放假、上班日子都会删掉。") {
                        store.settings.customHolidayOff = []
                        store.settings.customHolidayWork = []
                    }
                }
            }
        }
        .appList()
        .adminOnly()
        .navigationTitle("法定节假日")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func add() {
        let r = HolidayInput.parse(text, reference: DayKey(year: year, month: 7, day: 1), calendar: .app)
        var off = Set(store.settings.customHolidayOff), work = Set(store.settings.customHolidayWork)
        for d in r.off { off.insert(d.description); work.remove(d.description) }
        for d in r.work { work.insert(d.description); off.remove(d.description) }
        store.settings.customHolidayOff = off.sorted()
        store.settings.customHolidayWork = work.sorted()
        message = "加入放假 \(r.off.count) 天、上班 \(r.work.count) 天" + (r.skipped.isEmpty ? "" : "；没看懂：" + r.skipped.joined(separator: " / "))
        if r.skipped.isEmpty { text = "" }
    }
}


/// 待休天数是怎么变过来的：每次变化（几号从几天变成几天），以及前后排的遥测、休息、调休、请假。
struct RestStepsSection: View {
    @EnvironmentObject private var store: AppStore
    let name: String

    var body: some View {
        let points = (store.settings.restHistory[name] ?? []).map(\.point)
        let steps = RestBalanceHistory.steps(points: points, history: store.roster[name] ?? [:],
                                             matcher: store.matcher, calendar: .app)
        let audit = store.restBalanceAudit()
        Section {
            if steps.isEmpty {
                Text(points.isEmpty ? "还没有记录。" : "从 \(points[0].day.dateText) 起一直是 \(points[0].value) 天，没变过。")
                    .foregroundStyle(.secondary)
            }
            ForEach(steps, id: \.day) { step in
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    HStack {
                        Text(step.day.dateText).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(step.from) → \(step.to) 天")
                            .font(.subheadline.monospacedDigit())
                        Text(step.delta > 0 ? "+\(step.delta)" : "\(step.delta)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(step.delta > 0 ? Color.orange : Color.green)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((step.delta > 0 ? Color.orange : Color.green).opacity(0.15), in: Capsule())
                    }
                    // 待休对账：按反推的规律这次应该变多少
                    if let audit {
                        let expected = RestBalanceAudit.expectedChange(store.roster[name] ?? [:], from: step.since, to: step.day,
                                                                       rule: audit.rule, matcher: store.matcher, calendar: .app)
                        Label(expected == step.delta ? "和规律一致" : "按规律应该 \(expected > 0 ? "+" : "")\(expected)，对不上",
                              systemImage: expected == step.delta ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(expected == step.delta ? DS.Palette.success : DS.Palette.warning)
                    }
                    if step.events.isEmpty {
                        Text("\(step.since.dateText) 以来网站上没排遥测、休息、请假（可能是领导直接调整的）")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("这段时间：" + step.events.map { e in
                            "\(e.day.month)/\(e.day.day) \(e.post)" + (e.tag.map { "（\($0)）" } ?? "")
                        }.joined(separator: "、"))
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("怎么来的")
        } footer: {
            Text("数字取自网站上人名后面的括号。增加一般是周末、节假日值了遥测或加班，减少一般是休了、调休了；列出的是上次记录前两天到这天之间网站上排的遥测、加班、休息、请假、出差。在工作量统计页点「读取今年 1 月以来全部」能补全以前的记录。")
        }
    }
}
