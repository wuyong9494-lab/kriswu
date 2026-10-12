import SwiftUI

// MARK: - 组别任务清单

/// 今天组别要做的事，做完打勾（内容来自「各组工作内容」）。
struct TaskChecklistCard: View {
    @EnvironmentObject private var store: AppStore
    let day: DayKey

    /// 同样的事项写了两遍也分得开
    static func key(_ index: Int, _ item: String) -> String { "\(index).\(item)" }

    var body: some View {
        let groups = store.notes(for: store.shift(on: day))
            .map { (group: $0.group, items: TaskList.items(from: $0.note)) }
            .filter { $0.items.count > 1 }
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                let total = groups.map(\.items.count).reduce(0, +)
                let done = groups.map { g in g.items.indices.filter { store.isTaskDone(day, g.group, Self.key($0, g.items[$0])) }.count }
                    .reduce(0, +)
                HStack {
                    Label("今天要做", systemImage: "checklist").font(.headline)
                    Spacer()
                    Text("\(done)/\(total)").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(groups, id: \.group) { g in
                    if groups.count > 1 { Text(g.group).font(.subheadline.bold()) }
                    ForEach(Array(g.items.enumerated()), id: \.offset) { i, item in
                        let checked = store.isTaskDone(day, g.group, Self.key(i, item))
                        Button {
                            store.toggleTask(day, g.group, Self.key(i, item))
                        } label: {
                            HStack(alignment: .top) {
                                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(checked ? Color.green : Color.secondary)
                                Text(item)
                                    .strikethrough(checked)
                                    .foregroundStyle(checked ? Color.secondary : Color.primary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - 本周全员排班表

struct WeekRosterView: View {
    @EnvironmentObject private var store: AppStore
    @State private var weekOffset = 0
    @State private var image: Image?

    private var days: [DayKey] {
        let cal = Calendar.app
        let today = DayKey.today
        let weekday = cal.component(.weekday, from: today.date(calendar: cal, hour: 12))
        let monday = today.adding(days: -((weekday + 5) % 7) + weekOffset * 7)
        return (0..<7).map { monday.adding(days: $0) }
    }

    var body: some View {
        let days = self.days
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(spacing: DS.Space.s) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(weekOffset == 0 ? "本周" : (weekOffset == 1 ? "下周" : (weekOffset == -1 ? "上周" : "第 \(weekOffset) 周")))
                            .font(DS.Font.caption).foregroundStyle(.secondary)
                        Text("\(days[0].month)/\(days[0].day) – \(days[6].month)/\(days[6].day)").font(DS.Font.title)
                    }
                    Spacer()
                    Button { Haptics.tap(); withAnimation(DS.Motion.spring) { weekOffset -= 1 } } label: {
                        Image(systemName: "chevron.left").font(.headline).frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Button { Haptics.tap(); withAnimation(DS.Motion.spring) { weekOffset += 1 } } label: {
                        Image(systemName: "chevron.right").font(.headline).frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DS.Space.m)
                ScrollView(.horizontal, showsIndicators: false) {
                    WeekTable(days: days)
                        .padding(DS.Space.s)
                        .card(padding: 0)
                        .padding(.horizontal, DS.Space.m)
                        .padding(.bottom, DS.Space.l)
                }
            }
            .padding(.top, DS.Space.xs)
        }
        .appBackground()
        .navigationTitle("本周全员")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let image {
                    ShareLink(item: image, preview: SharePreview("全员排班", image: image)) {
                        Label("分享图片", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: "\(weekOffset)-\(store.roster.count)") { render(days) }
    }

    @MainActor
    private func render(_ days: [DayKey]) {
        let renderer = ImageRenderer(content: WeekTable(days: days).padding(12).background(Color.white)
            .environmentObject(store).environment(\.colorScheme, .light))
        renderer.scale = 2
        image = renderer.uiImage.map { Image(uiImage: $0) }
    }
}

/// 一周的表：每人一行，一天一列。轮组别、遥测、调度的人在前面。
private struct WeekTable: View {
    @EnvironmentObject private var store: AppStore
    let days: [DayKey]

    var body: some View {
        let range = days[0]...days[6]
        let people = store.roster.filter { $0.value.keys.contains(where: range.contains) }
        let zh = Locale(identifier: "zh_CN")
        // 轮组别、遥测、调度的人排在前面（先算好，别在排序里一遍遍翻整段历史）
        let rotating = Set(people.keys.filter { name in
            people[name]?.values.contains { raw in
                raw.split(separator: "+").contains { p in
                    let post = store.matcher.displayName(String(p))
                    return GroupNotes.isGroup(post) || WorkloadCounter.isDuty(post) || post.contains("调度")
                }
            } ?? false
        })
        let names = people.keys.sorted { a, b in
            let ra = rotating.contains(a), rb = rotating.contains(b)
            if ra != rb { return ra }
            return a.compare(b, locale: zh) == .orderedAscending
        }
        Grid(horizontalSpacing: DS.Space.xxs, verticalSpacing: DS.Space.xxs) {
            GridRow {
                Text("").frame(width: 64)
                ForEach(days, id: \.self) { d in
                    VStack(spacing: 0) {
                        Text(d.weekdayText).font(.caption2)
                        Text("\(d.month)/\(d.day)").font(.caption.bold())
                    }
                    .frame(width: 58)
                    .foregroundStyle(ChinaHolidays.isHoliday(d) ? Color.red : Color.primary)
                }
            }
            ForEach(names, id: \.self) { name in
                GridRow {
                    Text(name).font(DS.Font.caption.weight(.semibold)).lineLimit(1).frame(width: 64, alignment: .leading)
                        .foregroundStyle(store.isMe(name) ? Color.accentColor : Color.primary)
                    ForEach(days, id: \.self) { d in
                        let raw = people[name]?[d]
                        let type = raw.flatMap(store.matcher.match)
                        Text(raw.map(store.matcher.displayName) ?? "")
                            .font(DS.Font.caption)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .frame(width: 58, height: 32)
                            .background((type.map { Color(hex: $0.colorHex) } ?? DS.Palette.surfaceSunken).opacity(type == nil ? 1 : 0.2),
                                        in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
                    }
                }
            }
        }
    }
}

// MARK: - 自动同步设置向导

struct AutomationGuideView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        let dayAgo = Date().addingTimeInterval(-86_400)
        let runs = store.settings.syncLog.filter { $0.date > dayAgo && $0.source.hasPrefix("快捷指令") }
        List {
            Section {
                LabeledContent("最近 24 小时快捷指令同步", value: "\(runs.count) 次")
                if let last = runs.first {
                    LabeledContent("上一次", value: last.date.formatted(date: .omitted, time: .shortened) + (last.ok ? " 成功" : " 失败"))
                }
            } footer: {
                Text(runs.isEmpty ? "还没有快捷指令自动同步过。iPhone 上划关掉 App 后不会在后台运行，照下面设好，不开 App 也能及时收到排班变动。"
                     : "已经在自动同步了。")
            }
            Section("第一步：每天定时同步排班") {
                step(1, "打开「快捷指令」App，点底部「自动化」")
                step(2, "点右上角「+」，选「特定时间」")
                step(3, "时间设 9:00，重复选「每天」，选「立即运行」（不要勾「运行前询问」）")
                step(4, "点「新建空白自动化」，搜索「值班提醒」，选「同步排班」，点「完成」")
                step(5, "同样再建 12:00、15:00、18:00 三个（也可以更多）")
            }
            Section("第二步：微信准点提醒（用微信推送才需要）") {
                step(1, "同样新建 7:30 的自动化，动作选「发送值班提醒到微信」，哪天选「今天」")
                step(2, "再建 20:30 的，哪天选「明天」")
                step(3, "周日 20:00 的选「下周」，就能收到下周预告")
            }
            Section {
                step(1, "新建 8:40 的自动化，动作先选「是不是遥测后补觉时间」")
                step(2, "再加「如果」：如果「是不是遥测后补觉时间」为「是」")
                step(3, "在「如果」里面加「设定专注模式」：打开「勿扰模式」（或「睡眠」），直到「关闭时」改成到 \(store.settings.restFocusUntil.text)")
                DatePicker("补觉到", selection: Binding(
                    get: { store.settings.restFocusUntil.date },
                    set: { store.settings.restFocusUntil = ClockTime(date: $0) }), displayedComponents: .hourAndMinute)
            } header: {
                Text("第三步（可选）：遥测下班后自动勿扰")
            } footer: {
                Text("昨天值了遥测，今天 8:40 自动打开勿扰补觉；平时这个自动化什么也不做。")
            }
            Section {
                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label("打开快捷指令", systemImage: "arrow.up.forward.app")
                }
            } footer: {
                Text("也可以直接对 Siri 说：「值班提醒明天什么班」「值班提醒今天谁值遥测」「值班提醒我下次遥测」。")
            }
        }
        .appList()
        .navigationTitle("自动同步设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.caption.bold()).frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.2), in: Circle())
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 节假日值班统计

struct HolidayDutyView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let today = DayKey.today
        let days = store.publishedDays.filter { $0 <= today }
        let stats = HolidayDutyStats.count(roster: store.roster, days: days, matcher: store.matcher)
        let range = days.filter(ChinaHolidays.isHoliday)
        List {
            Section {
                ForEach(stats, id: \.name) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Avatar(name: s.name, size: 28)
                            Text(s.name).font(DS.Font.headline)
                                .foregroundStyle(store.isMe(s.name) ? Color.accentColor : Color.primary)
                            Spacer()
                            Text("遥测 \(s.dutyDays) 次 · 上班 \(s.workDays) 天")
                        }
                        if !s.dutyDates.isEmpty {
                            Text("遥测：" + s.dutyDates.map(\.dateText).joined(separator: "、"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text(range.isEmpty ? "还没有法定节假日的全员排班数据。"
                     : "统计 \(range.min()!.dateText) – \(range.max()!.dateText) 之间 App 记下的 \(range.count) 天法定假日（春节、国庆、中秋等），按节假日遥测次数排序。")
            }
        }
        .appList()
        .navigationTitle("节假日值班")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 请假规划

struct LeavePlannerView: View {
    @EnvironmentObject private var store: AppStore
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(2 * 86_400)

    var body: some View {
        let from = DayKey(date: start, calendar: .app), to = DayKey(date: max(start, end), calendar: .app)
        let plan = LeavePlanner.plan(from: from, to: to, mine: store.schedule, published: store.publishedDays,
                                     matcher: store.matcher, calendar: .app)
        let rest = store.myRosterName.flatMap { store.settings.restBalance[$0] }
        List {
            Section {
                DatePicker("从", selection: $start, displayedComponents: .date)
                DatePicker("到", selection: $end, in: start..., displayedComponents: .date)
            }
            Section {
                LabeledContent("要请几天", value: "\(plan.needDays.count) 天")
                LabeledContent("本来就不用上班", value: "\(plan.freeDays.count) 天")
                if let rest {
                    LabeledContent("现在待休", value: "\(rest) 天")
                    if plan.needDays.count > rest {
                        Text("待休不够，还差 \(plan.needDays.count - rest) 天").foregroundStyle(.orange)
                    }
                }
            } footer: {
                Text("排了岗位的日子要请；周末、法定假日、本来就休息的、网站排了班但没给你排的日子不用请。网站还没排到的工作日先按要请算。")
            }
            if !plan.dutyDays.isEmpty {
                Section("这几天有遥测，要先换出去") {
                    ForEach(plan.dutyDays, id: \.self) { d in
                        NavigationLink { SwapHelperView(day: d) } label: {
                            LabeledContent(d.dateText, value: "找人换班")
                        }
                    }
                }
            }
            Section("每天") {
                ForEach(dayList(from: from, to: to), id: \.self) { d in
                    let raw = store.shift(on: d)
                    let status = plan.unknownDays.contains(d) ? "网站还没排" : (plan.needDays.contains(d) ? "要请假" : "不用上班")
                    LabeledContent("\(d.dateText) \(raw.map(store.matcher.displayName) ?? "")", value: status)
                        .foregroundStyle(plan.needDays.contains(d) ? Color.primary : Color.secondary)
                }
            }
        }
        .appList()
        .navigationTitle("请假规划")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dayList(from: DayKey, to: DayKey) -> [DayKey] {
        var result: [DayKey] = []
        var d = from
        while d <= to, result.count < 120 { result.append(d); d = d.adding(days: 1) }
        return result
    }
}
