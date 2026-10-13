import Charts
import SwiftUI

// MARK: - 数据核对

/// 找出可能读漏、读错的地方：遥测后没写休息、认不出的岗位、人数偏少的日子。
struct DataCheckView: View {
    @EnvironmentObject private var store: AppStore
    @State private var issues: [DataIssue]?

    var body: some View {
        List {
            if let issues {
                if issues.isEmpty {
                    Text("最近两个月没发现可疑的地方。").foregroundStyle(.secondary)
                }
                ForEach([DataIssue.Kind.noRestAfterDuty, .thinDay, .unknownPost], id: \.self) { kind in
                    let items = issues.filter { $0.kind == kind }
                    if !items.isEmpty {
                        Section {
                            ForEach(items, id: \.self) { issue in row(issue) }
                        } header: {
                            Text("\(kind.rawValue)（\(items.count)）")
                        } footer: {
                            Text(footer(kind))
                        }
                    }
                }
            } else {
                Section { SkeletonRows(rows: 5) }
            }
        }
        .appList()
        .navigationTitle("数据核对")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(store.roster.count)-\(store.publishedDays.count)-\(store.settings.workloadOverrides.count)-\(store.settings.lastSync?.timeIntervalSince1970 ?? 0)-\(store.settings.workloadRules.blankWorkdayIsWork)") {
            issues = DataCheck.issues(roster: store.roster, published: store.publishedDays, matcher: store.matcher,
                                      members: store.rotationMembers, today: .today, calendar: .app)
        }
    }

    @ViewBuilder
    private func row(_ issue: DataIssue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(issue.text).font(.subheadline)
            if issue.kind == .noRestAfterDuty, let name = issue.name, let day = issue.day {
                if let fixed = store.override(name, day) {
                    Text("已手动改成：\(fixed)").font(.caption).foregroundStyle(.orange)
                } else if store.canEdit {
                    HStack {
                        Button("这天其实休息") { store.setOverride(name, day, WorkloadCounter.Kind.off.rawValue) }
                        Button("确实上班了") { store.setOverride(name, day, WorkloadCounter.Kind.attendance.rawValue) }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
            if let day = issue.day {
                NavigationLink("看这天全部组别") { DayRosterView(day: day) }.font(.caption)
            }
        }
    }

    private func footer(_ kind: DataIssue.Kind) -> String {
        switch kind {
        case .noRestAfterDuty: return "值完遥测后的工作日网站上什么都没写，现在按上班算。对一下网站：真的写了休息，说明 App 没读到，点「这天其实休息」改过来，再截图告诉我；确实上班了就点「确实上班了」。"
        case .thinDay: return "这天读到的人比平时少一半以上，可能网页没加载完。下拉刷新或在工作量统计里「从电脑版网页读取」再读一次。"
        case .unknownPost: return "这些写法 App 不认识，按日常班算。如果其实是休息、请假之类，到「设置 › 显示 › 班次」里把它加到「休息」的关键字里。"
        }
    }
}

// MARK: - 工作量规则

struct WorkloadRulesView: View {
    @EnvironmentObject private var store: AppStore
    /// 改动从哪天起生效；关掉「只改以后」就所有日子都按新规则重算
    @State private var effective = Date()
    @State private var onlyFuture = true

    /// 改规则：只改以后的话，effective 以前按原来的规则算
    private func rule(_ keyPath: WritableKeyPath<WorkloadRules, Bool>) -> Binding<Bool> {
        Binding {
            store.settings.workloadRules[keyPath: keyPath]
        } set: { value in
            var new = store.settings.workloadRules
            new[keyPath: keyPath] = value
            apply(new)
        }
    }

    private func apply(_ new: WorkloadRules) {
        var s = store.settings
        if onlyFuture {
            s.ruleHistory = RuleVersion.adding(s.ruleHistory, current: s.workloadRules,
                                               changeFrom: DayKey(date: effective, calendar: .app))
        }
        s.workloadRules = new
        store.settings = s
    }

    var body: some View {
        Form {
            if !store.canEdit { Section { ReadOnlyNotice() } }
            Section {
                Toggle("只改以后，以前的日子还按原来的规则", isOn: $onlyFuture)
                if onlyFuture {
                    DatePicker("从这天起生效", selection: $effective, displayedComponents: .date)
                }
            } header: {
                Text("改动生效时间")
            } footer: {
                Text("单位规则变了时用：比如从下个月 1 号起换算法，以前月份的统计不受影响。关掉后所有日子都按新规则重算。")
            }
            Section {
                Toggle("工作日没排岗位、也没写休息算上班", isOn: rule(\.blankWorkdayIsWork))
                Toggle("调度只算排班表上有名字的日子", isOn: rule(\.dispatchScheduleOnly))
            } footer: {
                Text("工作日没排岗位、也没写休息的日子：轮组别（组A–E）的人是正常上班，算「上班天数」，不算工作量；不轮组别的人是在做别的日常工作，算工作量。谁轮组别、谁是调度看「人员档案」，没建档案的按最近三个月的排班自动判断。第一项关掉后，这些日子都显示「没排班」，不算上班也不算工作量。")
            }
            Section {
                Toggle("节假日值完遥测的第二天没写休息算工作量", isOn: rule(\.blankHolidayAfterDutyIsRest))
                Toggle("节假日值完遥测后写了休息也算工作量", isOn: rule(\.holidayDutyRestCounts))
            } header: {
                Text("休息")
            } footer: {
                Text("默认：网站上写了休息、调休、请假的，不管节假日还是平时都不算工作量；出差算工作量。「值班交接前」一列的人是前一天值了遥测，那天算休息。")
            }
            if !store.settings.ruleHistory.isEmpty {
                Section {
                    ForEach(Array(store.settings.ruleHistory.enumerated()), id: \.offset) { _, v in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(v.until.dateText) 以前").font(.subheadline.weight(.semibold))
                            Text(describe(v.rules)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button("清除历史，所有日子都按现在的规则", role: .destructive) { store.settings.ruleHistory = [] }
                } header: {
                    Text("以前的规则")
                }
            }
            Section {
                NavigationLink {
                    PeopleProfilesView()
                } label: {
                    LabeledContent("人员档案", value: "\(store.settings.profiles.count) 人已建")
                }
                NavigationLink {
                    RotationMembersView()
                } label: {
                    LabeledContent("只按排班算的人", value: store.settings.scheduleOnlyMembers.isEmpty ? "调度" : "调度 + \(store.settings.scheduleOnlyMembers.count) 人")
                }
                LabeledContent("手动改过的日子", value: "\(store.settings.workloadOverrides.values.map(\.count).reduce(0, +)) 天")
                if !store.settings.workloadOverrides.isEmpty {
                    Button("清除全部手动修改", role: .destructive) { store.settings.workloadOverrides = [:] }
                }
            } footer: {
                Text("在每个人的每日明细里长按某一天可以手动改。")
            }
            Section {
                Button("恢复默认规则") { apply(WorkloadRules()) }
            }
        }
        .disabled(!store.canEdit)
        .appList()
        .navigationTitle("工作量规则")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func describe(_ r: WorkloadRules) -> String {
        [r.blankWorkdayIsWork ? "没排岗位算上班" : "没排岗位不算上班",
         r.dispatchScheduleOnly ? "调度只按排班" : "调度也按上一条",
         r.blankHolidayAfterDutyIsRest ? "节假日值班第二天没写算工作量" : "节假日值班第二天没写不算",
         r.holidayDutyRestCounts ? "节假日值班后写了休息也算" : "写了休息不算"].joined(separator: "，")
    }
}

// MARK: - 全员换班记录

struct TeamChangesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let list = store.settings.teamChanges.filter { q.isEmpty || $0.involves(q) || $0.from.contains(where: { $0.contains(q) })
            || $0.to.contains(where: { $0.contains(q) }) || $0.post.contains(q) }
        List {
            if list.isEmpty {
                Text(store.settings.teamChanges.isEmpty ? "还没有记录。以后每次同步发现有人的岗位换了人就记在这里。" : "没有找到")
                    .foregroundStyle(.secondary)
            }
            ForEach(list) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.day.dateText).font(.subheadline.bold())
                    Text(c.summary).font(.subheadline)
                    Text(c.detected.formatted(date: .abbreviated, time: .shortened) + " 发现")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $query, prompt: "按名字或岗位查")
        .appList()
        .navigationTitle("全员换班记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("清空") { store.settings.teamChanges = [] }
                    .disabled(store.settings.teamChanges.isEmpty)
            }
        }
    }
}

// MARK: - 年度总结

/// 我的年度总结卡片，可以存成图片。
struct YearSummaryCard: View {
    let year: Int
    let me: PersonWorkload
    let months: [(month: Int, work: Int)]
    let holidayDuty: Int
    let rank: Int
    let total: Int

    var body: some View {
        let busiest = months.max { $0.work < $1.work }
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: "\(year) 年 · \(me.name)").font(.title2.bold())
            Grid(alignment: .leading, horizontalSpacing: DS.Space.l, verticalSpacing: DS.Space.s) {
                GridRow {
                    stat("\(me.workDays)", "天工作量")
                    stat("\(me.dutyDays)", "次遥测")
                    stat("\(holidayDuty)", "次节假日遥测")
                }
                GridRow {
                    stat("\(me.holidayWorkedDays)", "天节假日上班")
                    stat("\(me.tripDays)", "天出差")
                    stat("\(me.offDays)", "天休息")
                }
            }
            if let busiest, busiest.work > 0 {
                Text("最忙的是 \(busiest.month) 月，上了 \(busiest.work) 天").font(.headline)
            }
            // 每月工作量的小柱子
            HStack(alignment: .bottom, spacing: 4) {
                let top = max(1, months.map(\.work).max() ?? 1)
                ForEach(months, id: \.month) { m in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(0.8))
                            .frame(width: 16, height: CGFloat(m.work) / CGFloat(top) * 80 + 2)
                        Text("\(m.month)").font(.system(size: 9))
                    }
                }
            }
            if total > 1 {
                Text("全员工作量排第 \(rank) / \(total)").font(.subheadline).foregroundStyle(.secondary)
            }
            let posts = AppStore.sortedPosts(me).prefix(4).map { "\($0.post)×\($0.count)" }.joined(separator: "  ")
            if !posts.isEmpty { Text(posts).font(.footnote).foregroundStyle(.secondary) }
            Text("值班提醒").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 360, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: "#E8F4FF"), Color(hex: "#FFF6E5")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .foregroundStyle(Color.black)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.title.bold().monospacedDigit())
            Text(label).font(.caption)
        }
    }
}

struct YearSummaryView: View {
    @EnvironmentObject private var store: AppStore
    let year: Int
    @State private var image: Image?
    @State private var card: YearSummaryCard?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let card {
                    card.clipShape(RoundedRectangle(cornerRadius: 20))
                    if let image {
                        ShareLink(item: image, preview: SharePreview("\(year)年度总结", image: image)) {
                            Label("保存 / 分享图片", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Text("还没认出你在全员排班里的名字，或这一年没有数据。").foregroundStyle(.secondary).padding()
                }
            }
            .padding()
        }
        .appList()
        .navigationTitle("年度总结")
        .navigationBarTitleDisplayMode(.inline)
        .task { build() }
    }

    @MainActor
    private func build() {
        guard let me = store.myRosterName else { return }
        let report = store.workload(year: year, month: nil)
        guard let mine = report.people.first(where: { $0.name == me }) else { return }
        let months = (1...12).map { m -> (month: Int, work: Int) in
            let days = report.days.filter { $0.month == m }
            let w = WorkloadCounter.count(roster: [me: store.roster[me] ?? [:]], days: days, matcher: store.matcher,
                                          members: store.rotationMembers, calendar: .app).first?.workDays ?? 0
            return (m, w)
        }.filter { m in report.days.contains { $0.month == m.month } }
        let holidayDuty = HolidayDutyStats.count(roster: [me: store.roster[me] ?? [:]], days: Set(report.days),
                                                 matcher: store.matcher).first?.dutyDays ?? 0
        let rank = (report.people.firstIndex { $0.name == me } ?? 0) + 1
        let c = YearSummaryCard(year: year, me: mine, months: months, holidayDuty: holidayDuty, rank: rank, total: report.people.count)
        card = c
        let renderer = ImageRenderer(content: c)
        renderer.scale = 3
        image = renderer.uiImage.map { Image(uiImage: $0) }
    }
}

// MARK: - 图表


/// 每人一根横条（工作量）：渐变条、打开时从 0 长出来、数字浮在条尾；我这条用主题色，别人是灰色
struct WorkloadBarChart: View {
    struct Item: Identifiable {
        var id: String { name }
        let name: String
        let value: Int
        let highlight: Bool
        /// 上班天数（有的话画在工作量后面，浅色）
        var present: Int? = nil
    }

    let items: [Item]
    var average: Double?
    @State private var grown = false

    var body: some View {
        Chart {
            ForEach(items) { item in
                if let present = item.present, present > item.value {
                    BarMark(x: .value("天", grown ? Double(present) : 0.0001), y: .value("姓名", item.name), height: .fixed(14),
                            stacking: .unstacked)
                        .foregroundStyle((item.highlight ? DS.Palette.accent : DS.Palette.vivid[2]).opacity(0.16))
                        .cornerRadius(7)
                }
                BarMark(x: .value("天", grown ? Double(item.value) : 0.0001), y: .value("姓名", item.name), height: .fixed(14),
                        stacking: .unstacked)
                    .foregroundStyle(item.highlight
                                     ? AnyShapeStyle(LinearGradient(colors: [DS.Palette.accent.opacity(0.65), DS.Palette.accent],
                                                                    startPoint: .leading, endPoint: .trailing))
                                     : AnyShapeStyle(LinearGradient(colors: [DS.Palette.vivid[1].opacity(0.35), DS.Palette.vivid[2].opacity(0.6)],
                                                                    startPoint: .leading, endPoint: .trailing)))
                    .cornerRadius(7)
                    .annotation(position: .trailing, spacing: DS.Space.xxs + 2) {
                        Text(item.present.map { $0 > item.value ? "\(item.value) · 上班\($0)" : "\(item.value)" } ?? "\(item.value)")
                            .font(DS.Font.caption.monospacedDigit())
                            .foregroundStyle(item.highlight ? DS.Palette.accent : .secondary)
                            .opacity(grown ? 1 : 0)
                    }
            }
            if let average {
                RuleMark(x: .value("平均", average))
                    .foregroundStyle(DS.Palette.warning.opacity(0.9))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("平均 \(String(format: "%.1f", average))").font(DS.Font.caption).foregroundStyle(DS.Palette.warning)
                    }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel().font(DS.Font.caption)
            }
        }
        .chartXScale(domain: 0...Double(max(items.map { max($0.value, $0.present ?? 0) }.max() ?? 1, Int((average ?? 0).rounded(.up)), 1)) * 1.3)
        .frame(height: CGFloat(max(items.count, 1)) * 32 + (average == nil ? 8 : 28))
        .onAppear {
            guard !grown else { return }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.1)) { grown = true }
        }
    }
}
