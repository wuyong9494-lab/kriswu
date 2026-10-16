import SwiftUI

/// 每个人一个月的工作量：上班天数、各组各几天、休息几天（数据来自同步读到的全员排班）。
struct WorkloadView: View {
    @EnvironmentObject private var store: AppStore
    @State private var year = DayKey.today.year
    @State private var month = DayKey.today.month
    @State private var reading = false
    @State private var monthFile: URL?
    /// 点了工具格子里的第几个
    @State private var toolIndex: Int?
    @State private var sort: Sort = .work
    @State private var query = ""

    /// 名单怎么排
    enum Sort: String, CaseIterable, Identifiable {
        case work = "工作量", present = "上班天数", rest = "待休", holiday = "节假日上班", name = "姓名"
        var id: String { rawValue }
    }

    /// 按选的方式排好；搜索时只留名字里有搜索词的；我自己固定在最前面
    private func people(_ report: AppStore.Workload) -> [PersonWorkload] {
        let zh = Locale(identifier: "zh_CN")
        let q = query.trimmingCharacters(in: .whitespaces)
        let rest = store.settings.restBalance
        func byName(_ a: PersonWorkload, _ b: PersonWorkload) -> Bool { a.name.compare(b.name, locale: zh) == .orderedAscending }
        func value(_ p: PersonWorkload) -> Int {
            switch sort {
            case .work: return p.workDays
            case .present: return p.presentDays
            case .rest: return rest[p.name] ?? -1
            case .holiday: return p.holidayWorkedDays
            case .name: return 0
            }
        }
        let list = report.people.filter { q.isEmpty || $0.name.contains(q) }
            .sorted { a, b in value(a) != value(b) ? value(a) > value(b) : byName(a, b) }
        return list.filter { store.isMe($0.name) } + list.filter { !store.isMe($0.name) }
    }

    private var tools: [ToolGrid.Item] {
        [
            .init(title: "均衡分析", icon: "scalemass.fill", color: .indigo, destination: AnyView(FairnessView())),
            .init(title: "全年统计", icon: "calendar", color: .blue, destination: AnyView(YearStatsView())),
            .init(title: "人员档案", icon: "person.text.rectangle", color: .blue, destination: AnyView(PeopleProfilesView())),
            .init(title: "变动历史", icon: "clock.arrow.circlepath", color: .orange, destination: AnyView(RosterLogView())),
            .init(title: "排班规律", icon: "wand.and.stars", color: .pink, destination: AnyView(SchedulePatternsView())),
            .init(title: "排班预演", icon: "sparkles.rectangle.stack", color: .mint, destination: AnyView(RosterPreviewView())),
            .init(title: "遥测预测", icon: "antenna.radiowaves.left.and.right", color: .teal, destination: AnyView(DutyForecastView())),
            .init(title: "数据核对", icon: "checkmark.shield.fill", color: .green, destination: AnyView(DataCheckView())),
            .init(title: "规则", icon: "slider.horizontal.3", color: .gray, destination: AnyView(WorkloadRulesView())),
            .init(title: "换班记录", icon: "arrow.left.arrow.right", color: .orange, destination: AnyView(TeamChangesView())),
            .init(title: "节假日值班", icon: "flag.fill", color: .red, destination: AnyView(HolidayDutyView())),
            .init(title: "待休趋势", icon: "chart.line.uptrend.xyaxis", color: .purple, destination: AnyView(RestTrendView())),
        ]
    }

    var body: some View {
        let report = store.workload(year: year, month: month)
        List {
            if !ChinaHolidays.knownYears.contains(year) {
                Label("App 里还没有 \(year) 年的法定节假日，假期会被当成工作日算，请更新 App", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Section {
                PeriodPager(caption: "\(year)年", title: "\(month)月", back: { move(-1) }, forward: { move(1) })
                if let first = report.days.first, let last = report.days.last {
                    HStack(spacing: DS.Space.xs) {
                        Chip(text: "\(report.days.count) 天", color: .secondary, icon: "calendar")
                        Chip(text: "\(first.month)/\(first.day) – \(last.month)/\(last.day)", color: .secondary)
                        Chip(text: "\(report.people.count) 人", color: .secondary, icon: "person.2")
                    }
                }
                if !report.people.isEmpty {
                    WorkloadBarChart(items: report.people.prefix(12).map {
                        .init(name: $0.name, value: $0.workDays, highlight: store.isMe($0.name), present: $0.presentDays)
                    })
                    Text("深色是工作量，后面浅色是上班天数").font(.caption2).foregroundStyle(.secondary)
                    .padding(.vertical, DS.Space.xs)
                }
            } footer: {
                if report.days.isEmpty {
                    Text("这个月还没有全员排班数据。")
                } else {
                    ExpandableText(text: "只算到今天，网站上能看到的日子才算得进来。「工作量」= 值班（遥测）+ 日常（各组、调度等岗位）+ 出差；假期里值完遥测的第二天休息算上班、算节假日上班，不算工作量。工作日网站上没排岗位、也没写休息的日子：除了调度，不管轮不轮组别都是正常上班，算日常、算工作量。写了休息、调休、请假的不管节假日还是平时都算休息；调度没排班的日子既不算工作量也不算上班。「节假日放假」是法定假日里网站上没排任何岗位的天数；「节假日上班」是法定假日里上了班（值班、各组、调度）的天数，两个数分开算；调休上班的周末算工作日。点开某个人可以看每一天怎么算的。")
                }
            }
            GroupAttendanceSection(people: report.people)
            Section {
                ToolGrid(items: tools, selection: $toolIndex)
                NavigationLink { SwapLedgerView() } label: { Label("换班账本", systemImage: "book.closed") }
                if let monthFile {
                    ShareLink(item: monthFile) { Label("导出本月表格（Excel 能打开）", systemImage: "tablecells") }
                }
            }
            // 统计口径只有管理员能改：普通用户不显示
            if store.canEdit {
                Section {
                    NavigationLink {
                        RotationMembersView()
                    } label: {
                        LabeledContent("没排班不算上班的人", value: store.settings.scheduleOnlyMembers.isEmpty ? "调度" : "调度 + \(store.settings.scheduleOnlyMembers.count) 人")
                    }
                } footer: {
                    Text("调度（排班表上有名字才算一天）和这里另加的人，工作日网站上没给排岗位不算工作量；其他人（包括轮组别、遥测的人）没排岗位、没写休息的工作日是正常上班，算日常、算工作量；写了休息、调休的算休息。")
                }
            }
            Section {
                Button {
                    reading = true
                    Task {
                        await store.readDesktopNotes()
                        reading = false
                    }
                } label: {
                    HStack {
                        Text("从电脑版网页读取前两个月")
                        if reading || store.isReadingDesktop { Spacer(); DSSpinner() }
                    }
                }
                .disabled(reading || store.isReadingDesktop || !store.canSync)
                Button {
                    reading = true
                    Task {
                        _ = await store.readHistory(since: year)
                        reading = false
                    }
                } label: {
                    Text("读取 \(store.historyLabel(since: year))（1–2 分钟）")
                }
                .disabled(reading || store.isReadingDesktop || !store.canSync)
                if let message = store.settings.desktopRosterMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text("用电脑版打开「值班查看」，点「上一周」往前翻 9 周，把每周的全员排班存下来（约半分钟）。每天第一次打开 App 时也会自动读一次。")
            }
            if !report.people.isEmpty {
                Section {
                    Picker("排序", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
            }
            ForEach(people(report), id: \.name) { person in
                Section {
                    NavigationLink {
                        WorkloadDetailView(name: person.name, days: report.days)
                    } label: {
                    HStack {
                        Avatar(name: person.name, size: 30)
                        Text(person.name)
                            .font(.headline)
                            .foregroundStyle(store.isMe(person.name) ? Color.accentColor : Color.primary)
                        if let rest = store.settings.restBalance[person.name], rest > 0 {
                            Text("待休 \(rest)")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2), in: Capsule())
                        }
                        Spacer()
                        WorkPresentPair(work: person.workDays, present: person.presentDays)
                    }
                    }
                    Text(summary(person))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    FlowChips(items: AppStore.sortedPosts(person).map { (text: "\($0.post) ×\($0.count)", raw: $0.post) })
                }
            }
        }
        .task(id: "\(year)-\(month)-\(store.dataRevision)") { monthFile = store.workloadCSVFile(year: year, month: month) }
        .searchable(text: $query, prompt: "搜名字")
        .appList()
        .navigationDestination(isPresented: Binding(get: { toolIndex != nil }, set: { if !$0 { toolIndex = nil } })) {
            if let i = toolIndex { tools[i].destination }
        }
        .navigationTitle("工作量统计")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    FairnessView()
                } label: {
                    Label("均衡分析", systemImage: "scalemass")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: report.text) { Label("分享", systemImage: "square.and.arrow.up") }
            }
        }
    }

    /// 「值班 2 · 日常 8 · 休息 3 · 节假日放假 7」：只写不是 0 的（节假日上班和节假日放假分开算，不是其中的一部分）
    private func summary(_ p: PersonWorkload) -> String {
        let parts: [(label: String, value: Int, note: String)] = [
            ("值班", p.dutyDays, ""), ("值班调休", p.dutyRestDays, ""),
            ("日常", p.regularDays, p.blankWorkDays > 0 ? "（其中没排岗位 \(p.blankWorkDays)）" : ""), ("出差", p.tripDays, ""),
            ("上班", p.attendanceDays, "（不算工作量）"), ("休息", p.offDays, ""), ("节假日放假", p.holidayDays, ""),
            ("没排班", p.unassignedDays, ""), ("节假日上班", p.holidayWorkedDays, ""),
        ]
        let shown = parts.filter { $0.value > 0 }.map { "\($0.label) \($0.value)\($0.note)" }
        return shown.isEmpty ? "这个月没有记录" : shown.joined(separator: " · ")
    }

    private func move(_ delta: Int) {
        (year, month) = Period.shiftMonth(year: year, month: month, by: delta)
    }
}

/// 一行放不下自动换行的小标签。
private struct FlowChips: View {
    @EnvironmentObject private var store: AppStore
    let items: [(text: String, raw: String)]

    var body: some View {
        // iOS 16 没有现成的流式布局：每行最多 4 个
        let rows = stride(from: 0, to: items.count, by: 4).map { Array(items[$0..<min($0 + 4, items.count)]) }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(rows[r], id: \.text) { item in
                        let display = ShiftDisplay(raw: item.raw, matcher: store.matcher)
                        Text(item.text)
                            .font(.footnote)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((display?.color ?? .gray).opacity(0.18), in: Capsule())
                    }
                }
            }
        }
    }
}

/// 某个人每一天怎么算的：日期、网站上的岗位、归到哪一类。
struct WorkloadDetailView: View {
    @EnvironmentObject private var store: AppStore
    let name: String
    let days: [DayKey]

    var body: some View {
        let explained = WorkloadCounter.explainedByMonth(name: name, history: store.roster[name] ?? [:], days: days,
                                                         matcher: store.matcher,
                                                         forced: store.rotationMembers?.contains(name) == true, calendar: .app)
        List(days.reversed()) { day in
            let raw = store.roster[name]?[day]
            let holiday = ChinaHolidays.isHoliday(day)
            let kind = explained[day]?.kind
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.dateText)
                    Text(raw.map(store.matcher.displayName) ?? (holiday ? "网站上没排（法定假日）" : "网站上没排"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    // 为什么这样算、这条是从哪读来的
                    if let reason = explained[day]?.reason {
                        Text(reason).font(.caption2).foregroundStyle(DS.Palette.accent.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let p = store.provenance(name, day) {
                        Text("来源：\(p.sourceTitle) · \(p.at.formatted(date: .numeric, time: .shortened))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if store.override(name, day) != nil {
                    Text("手动").font(.caption2).foregroundStyle(.orange)
                }
                Text(kind.map { $0 == .attendance ? "上班·不算工作量" : $0.rawValue }
                     ?? (store.override(name, day) == WorkloadCounter.excluded ? "不算" : "不在岗"))
                    .font(.subheadline.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background((kind.map(color) ?? .gray).opacity(0.2), in: Capsule())
            }
            .contentShape(Rectangle())
            .contextMenu {
                // 网站读错或有特殊情况：手动改这一天（以后同步也不会被冲掉）；只有管理员能改
                if store.canEdit {
                ForEach([WorkloadCounter.Kind.regular, .attendance, .duty, .dutyRest, .trip, .off, .holiday, .unassigned], id: \.self) { k in
                    Button(k.rawValue) { store.setOverride(name, day, k.rawValue) }
                }
                Button("这天不算") { store.setOverride(name, day, WorkloadCounter.excluded) }
                if store.override(name, day) != nil {
                    Button("恢复自动", role: .destructive) { store.setOverride(name, day, nil) }
                }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            Text(store.canEdit ? "长按某一天可以手动改（网站读错时用）" : "只读：管理员登录后才能手动改")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(.bar)
        }
        .appList()
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let rest = store.settings.restBalance[name] {
                    NavigationLink {
                        RestTrendView(name: name)
                    } label: {
                        Label("待休 \(rest)", systemImage: "bed.double")
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
    }

    private func color(_ kind: WorkloadCounter.Kind) -> Color {
        switch kind {
        case .duty: return .blue
        case .dutyRest: return .indigo
        case .regular: return .teal
        case .trip: return .orange
        case .holiday: return .red
        case .off: return .green
        case .unassigned: return .gray
        case .attendance: return .mint
        }
    }
}

/// 设置「没排班不算上班」的人（调度自动算在内）：可以直接粘贴名字，也可以在全员排班的名单里勾选。
struct RotationMembersView: View {
    @EnvironmentObject private var store: AppStore
    @State private var text = ""

    private var members: [String] { store.settings.scheduleOnlyMembers }

    var body: some View {
        let zh = Locale(identifier: "zh_CN")
        let names = store.roster.keys.sorted { a, b in
            let ma = members.contains(a), mb = members.contains(b)
            return ma != mb ? ma : a.compare(b, locale: zh) == .orderedAscending
        }
        List {
            Group {
                Section {
                    TextField("粘贴名字，用空格、逗号或顿号隔开", text: $text, axis: .vertical)
                    Button("设为没排班不算上班") {
                        let parsed = text.split { " ,，、;；\n\t".contains($0) }.map(String.init).filter { !$0.isEmpty }
                        var seen = Set<String>()
                        store.settings.scheduleOnlyMembers = parsed.filter { seen.insert($0).inserted }
                        text = ""
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !members.isEmpty {
                        ConfirmButton(title: "清空（只留调度）", message: "名单会清空，改成只有调度没排班不算上班。") {
                            store.settings.scheduleOnlyMembers = []
                        }
                    }
                } footer: {
                    Text(members.isEmpty
                         ? "现在只有排过调度的人没排班不算上班（排班表上有名字才算一天）。其他人没排岗位、没写休息的工作日都算正常上班。一般不用加人。"
                         : "另加了 \(members.count) 人：" + members.joined(separator: "、") + "。排过调度的人也一样。")
                }
                Section("全员排班里的人（点一下勾选）") {
                    ForEach(names, id: \.self) { name in
                        Button {
                            if let i = store.settings.scheduleOnlyMembers.firstIndex(of: name) {
                                store.settings.scheduleOnlyMembers.remove(at: i)
                            } else {
                                store.settings.scheduleOnlyMembers.append(name)
                            }
                        } label: {
                            HStack {
                                Text(name).foregroundStyle(Color.primary)
                                Spacer()
                                if members.contains(name) {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                } else if store.isRotating(name) {
                                    Text("调度").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            // 只读时按钮、输入框不能用，但页面照样能滚动（整个列表 disabled 会连滚动都禁掉）
            .disabled(!store.canEdit)
        }
        .appList()
        .adminOnly()
        .navigationTitle("没排班不算上班的人")
        .navigationBarTitleDisplayMode(.inline)
    }
}


/// 轮组别的人单独看：上了多少天班，其中多少天网站上没给排岗位（没排岗位、没写休息照常算上班、算工作量）
struct GroupAttendanceSection: View {
    @EnvironmentObject private var store: AppStore
    let people: [PersonWorkload]

    var body: some View {
        let zh = Locale(identifier: "zh_CN")
        let members = people.filter(\.isGroupMember).sorted { a, b in
            a.presentDays != b.presentDays ? a.presentDays > b.presentDays : a.name.compare(b.name, locale: zh) == .orderedAscending
        }
        if !members.isEmpty {
            Section {
                ForEach(members, id: \.name) { p in
                    HStack {
                        Text(p.name)
                            .foregroundStyle(store.isMe(p.name) ? Color.accentColor : Color.primary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("上班 \(p.presentDays) 天").font(.body.monospacedDigit())
                            Text("其中没排班 \(p.blankWorkDays) 天")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(p.blankWorkDays > 0 ? Color.orange : Color.secondary)
                        }
                    }
                }
            } header: {
                Text("轮组别的人（\(members.count) 人）")
            } footer: {
                Text("上班天数 = 工作量 + 假期里值完遥测后休息的那天。「没排班」是工作日网站上没给排岗位、也没写休息的日子：照常算上班、算工作量，这里单独数出来。谁轮组别看「人员档案」，没建档案的按最近三个月的排班认。")
            }
        }
    }
}
