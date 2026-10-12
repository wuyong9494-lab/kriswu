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
                Text("还没有全员排班数据，先下拉刷新同步一次。").foregroundStyle(.secondary)
            } else if list.isEmpty {
                Text("那天没找到合适的人。").foregroundStyle(.secondary)
            }
            ForEach(list, id: \.name) { c in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(c.name).font(.headline)
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
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("找人换班")
        .navigationBarTitleDisplayMode(.inline)
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
                        Text(name).font(.headline)
                        Spacer()
                        Text(value > 0 ? "欠你 \(value) 天" : "你欠 \(-value) 天")
                            .foregroundStyle(value > 0 ? Color.green : Color.orange)
                        Button("还清") { settle(name) }
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
            } footer: {
                Text(self.report == nil ? "正在统计…" : report.days.isEmpty ? "这一年还没有全员排班数据。"
                     : "统计 \(report.days.first!.dateText) – \(report.days.last!.dateText) 共 \(report.days.count) 天（App 从开始同步起记下的全员排班，只算到今天），规则和每月统计一样。")
            }
            ForEach(report.people, id: \.name) { p in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(p.name).font(.headline)
                            .foregroundStyle(store.isMe(p.name) ? Color.accentColor : Color.primary)
                        Spacer()
                        Text("工作量 \(p.workDays) 天").font(.headline)
                    }
                    Text("遥测 \(p.dutyDays) 次 · 节假日上班 \(p.holidayWorkedDays) 天 · 值班调休 \(p.dutyRestDays) · 日常 \(p.regularDays) · 出差 \(p.tripDays) · 休息 \(p.offDays) · 节假日 \(p.holidayDays)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("全年统计")
        .navigationBarTitleDisplayMode(.inline)
        // 全年数据量大：换年份或全员排班更新时算一次，不在每次刷新界面时重算
        .task(id: "\(year)-\(store.roster.count)-\(store.publishedDays.count)-\(store.settings.rotationMembers.hashValue)-\(store.settings.customHolidayOff.count)-\(store.settings.customHolidayWork.count)-\(store.settings.lastSync?.timeIntervalSince1970 ?? 0)") {
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
        let mine = list.first { store.isMe($0.name) }
        List {
            if let mine {
                Section("我") { row(mine, today: today) }
            }
            Section {
                ForEach(list.filter { !store.isMe($0.name) }, id: \.name) { row($0, today: today) }
            } header: {
                Text("接下来大概轮到谁")
            } footer: {
                Text("按每个人过去值遥测的间隔（取中间值）推算：已经排好的显示排好的日子，没排的 = 上次 + 间隔。只是估计，换班、请假、出差都会打乱。")
            }
        }
        .navigationTitle("遥测轮转预测")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ f: DutyForecast, today: DayKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(f.name).font(.headline)
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
                            LineMark(x: .value("日期", p.day.date(calendar: .app, hour: 12)), y: .value("待休", p.value))
                                .interpolationMethod(.stepEnd)
                            PointMark(x: .value("日期", p.day.date(calendar: .app, hour: 12)), y: .value("待休", p.value))
                        }
                        .chartYAxisLabel("天")
                        .frame(height: 180)
                    } else {
                        Text("数字变过两次以上才画得出趋势。App 每次同步读到人名后面的括号数字时记一笔。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(points.reversed(), id: \.day) { p in
                        LabeledContent(p.day.dateText, value: "\(p.value) 天")
                    }
                }
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
                    Button("全部清除", role: .destructive) {
                        store.settings.customHolidayOff = []
                        store.settings.customHolidayWork = []
                    }
                }
            }
        }
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
