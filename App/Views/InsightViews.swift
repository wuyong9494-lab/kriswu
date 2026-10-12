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
                ProgressView()
            }
        }
        .navigationTitle("数据核对")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(store.roster.count)-\(store.publishedDays.count)-\(store.settings.workloadOverrides.count)") {
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
                } else {
                    HStack {
                        Button("这天其实休息") { store.setOverride(name, day, WorkloadCounter.Kind.off.rawValue) }
                        Button("确实上班了") { store.setOverride(name, day, WorkloadCounter.Kind.regular.rawValue) }
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

    var body: some View {
        Form {
            Section {
                Toggle("工作日没排岗位、也没写休息算上班", isOn: $store.settings.workloadRules.blankWorkdayIsWork)
                Toggle("调度只算排班表上有名字的日子", isOn: $store.settings.workloadRules.dispatchScheduleOnly)
            } footer: {
                Text("第一项关掉后，所有人没排岗位的工作日都不算工作量（显示「没排班」）。第二项关掉后，调度也按第一项算。")
            }
            Section {
                Toggle("节假日值完遥测后的休息算工作量", isOn: $store.settings.workloadRules.holidayDutyRestCounts)
                Toggle("节假日值完遥测的第二天没写也算", isOn: $store.settings.workloadRules.blankHolidayAfterDutyIsRest)
                    .disabled(!store.settings.workloadRules.holidayDutyRestCounts)
            } footer: {
                Text("平时值完遥测的休息不管写没写都不算工作量；写了「休息」「调休」才算休息。")
            }
            Section {
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
                Button("恢复默认规则") { store.settings.workloadRules = WorkloadRules() }
            }
        }
        .navigationTitle("工作量规则")
        .navigationBarTitleDisplayMode(.inline)
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
            HStack(spacing: 18) {
                stat("\(me.workDays)", "天工作量")
                stat("\(me.dutyDays)", "次遥测")
                stat("\(holidayDuty)", "次节假日遥测")
            }
            HStack(spacing: 18) {
                stat("\(me.holidayWorkedDays)", "天节假日上班")
                stat("\(me.tripDays)", "天出差")
                stat("\(me.offDays)", "天休息")
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
