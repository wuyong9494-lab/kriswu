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

    private var tools: [ToolGrid.Item] {
        [
            .init(title: "均衡分析", icon: "scalemass.fill", color: .indigo, destination: AnyView(FairnessView())),
            .init(title: "全年统计", icon: "calendar", color: .blue, destination: AnyView(YearStatsView())),
            .init(title: "人员档案", icon: "person.text.rectangle", color: .blue, destination: AnyView(PeopleProfilesView())),
            .init(title: "变动历史", icon: "clock.arrow.circlepath", color: .orange, destination: AnyView(RosterLogView())),
            .init(title: "排班规律", icon: "wand.and.stars", color: .pink, destination: AnyView(SchedulePatternsView())),
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
                HStack(spacing: DS.Space.s) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "\(year)年").font(DS.Font.caption).foregroundStyle(.secondary)
                        Text(verbatim: "\(month)月").font(DS.Font.title)
                    }
                    Spacer()
                    Button { Haptics.tap(); move(-1) } label: {
                        Image(systemName: "chevron.left").font(.headline).frame(width: 36, height: 36)
                            .background(DS.Palette.surfaceSunken, in: Circle())
                    }
                    Button { Haptics.tap(); move(1) } label: {
                        Image(systemName: "chevron.right").font(.headline).frame(width: 36, height: 36)
                            .background(DS.Palette.surfaceSunken, in: Circle())
                    }
                }
                .buttonStyle(.plain)
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
                    ExpandableText(text: "只算到今天，网站上能看到的日子才算得进来。「工作量」= 值班（遥测）+ 节假日值完遥测的第二天 + 日常（各组、调度等岗位）+ 出差。工作日网站上没排岗位、也没写休息的日子：不轮组别的人在做别的日常工作，算日常、算工作量；轮组别（组A–E）的人算正常上班，计入「上班」但不算工作量。写了休息、调休、请假的不管节假日还是平时都算休息；调度没排班的日子既不算工作量也不算上班。「节假日」是法定假日里网站上没排任何岗位的天数，调休上班的周末算工作日。点开某个人可以看每一天怎么算的。")
                }
            }
            Section {
                ToolGrid(items: tools, selection: $toolIndex)
                NavigationLink { SwapLedgerView() } label: { Label("换班账本", systemImage: "book.closed") }
                if let monthFile {
                    ShareLink(item: monthFile) { Label("导出本月表格（Excel 能打开）", systemImage: "tablecells") }
                }
            }
            Section {
                NavigationLink {
                    RotationMembersView()
                } label: {
                    LabeledContent("只按排班算的人", value: store.settings.scheduleOnlyMembers.isEmpty ? "调度" : "调度 + \(store.settings.scheduleOnlyMembers.count) 人")
                }
            } footer: {
                Text("调度（排班表上有名字才算一天）和这里另加的人，工作日网站上没给排岗位不算工作量；其他人（包括你们轮组别、遥测的人）没排岗位、没写休息的工作日是正常上班，算日常；写了休息、调休的算休息。")
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
                    Text("读取 \(String(year)) 年 1 月以来全部（1–2 分钟）")
                }
                .disabled(reading || store.isReadingDesktop || !store.canSync)
                if let message = store.settings.desktopRosterMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text("用电脑版打开「值班查看」，点「上一周」往前翻 9 周，把每周的全员排班存下来（约半分钟）。每天第一次打开 App 时也会自动读一次。")
            }
            ForEach(report.people, id: \.name) { person in
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
        .task(id: "\(year)-\(month)-\(store.roster.count)") { monthFile = store.workloadCSVFile(year: year, month: month) }
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

    /// 「值班 2 · 日常 8 · 休息 3 · 节假日 7」，出差、节假日上班有才显示
    private func summary(_ p: PersonWorkload) -> String {
        var parts = ["值班 \(p.dutyDays)", "值班调休 \(p.dutyRestDays)", "日常 \(p.regularDays)",
                     "出差 \(p.tripDays)"]
        if p.attendanceDays > 0 { parts.append("上班没排岗位 \(p.attendanceDays)（不算工作量）") }
        parts += ["休息 \(p.offDays)", "节假日 \(p.holidayDays)"]
        if p.unassignedDays > 0 { parts.append("没排班 \(p.unassignedDays)") }
        if p.holidayWorkedDays > 0 { parts.append("其中节假日上班 \(p.holidayWorkedDays)") }
        return parts.joined(separator: " · ")
    }

    private func move(_ delta: Int) {
        var m = month + delta, y = year
        if m < 1 { m = 12; y -= 1 }
        if m > 12 { m = 1; y += 1 }
        month = m; year = y
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

/// 设置「只按排班算」的人（调度自动算在内）：可以直接粘贴名字，也可以在全员排班的名单里勾选。
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
            Section {
                TextField("粘贴名字，用空格、逗号或顿号隔开", text: $text, axis: .vertical)
                Button("设为只按排班算") {
                    let parsed = text.split { " ,，、;；\n\t".contains($0) }.map(String.init).filter { !$0.isEmpty }
                    var seen = Set<String>()
                    store.settings.scheduleOnlyMembers = parsed.filter { seen.insert($0).inserted }
                    text = ""
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !members.isEmpty {
                    Button("清空（只按调度）", role: .destructive) { store.settings.scheduleOnlyMembers = [] }
                }
            } footer: {
                Text(members.isEmpty
                     ? "现在只有排过调度的人按排班算（排班表上有名字才算一天）。其他人没排岗位、没写休息的工作日都算正常上班。一般不用加人。"
                     : "另加了 \(members.count) 人：" + members.joined(separator: "、") + "。排过调度的人也按排班算。")
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
        .appList()
        .adminOnly()
        .navigationTitle("只按排班算的人")
        .navigationBarTitleDisplayMode(.inline)
    }
}
