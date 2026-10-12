import SwiftUI

/// 每个人一个月的工作量：上班天数、各组各几天、休息几天（数据来自同步读到的全员排班）。
struct WorkloadView: View {
    @EnvironmentObject private var store: AppStore
    @State private var year = DayKey.today.year
    @State private var month = DayKey.today.month
    @State private var reading = false

    var body: some View {
        let report = store.workload(year: year, month: month)
        List {
            if !ChinaHolidays.knownYears.contains(year) {
                Label("App 里还没有 \(year) 年的法定节假日，假期会被当成工作日算，请更新 App", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Section {
                NavigationLink {
                    FairnessView()
                } label: {
                    Label("工作量均衡分析（本周、本月谁干得多 / 少）", systemImage: "scalemass")
                        .font(.headline)
                }
            }
            Section {
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(verbatim: "\(year)年\(month)月").font(.headline)
                    Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.borderless)
            } footer: {
                Text(report.days.isEmpty
                     ? "这个月还没有全员排班数据。"
                     : "统计范围：已读到全员排班的 \(report.days.count) 天（\(report.days.first!.dateText) – \(report.days.last!.dateText)），只算到今天。网站上能看到的日子才算得进来；「值班」只算遥测；各组、调度等岗位算「日常班」；一直没有组别的日常班人员，工作日没排岗位也算日常班。轮班人员和调度，工作日网站上没给排岗位的算「没排班」，不算工作量。节假日里遥测后紧接着的休息是节假日值班换来的，算「值班调休」；平时的休息、调休（值班换来的、请假的）都算休息。「工作量」= 值班 + 值班调休 + 日常 + 出差；「节假日」是中秋、国庆、春节、清明、五一等法定假日里网站上没排任何岗位的天数；网站上写了休息、调休的算休息，周末没排岗位也算休息。调休上班的周末算工作日。点开某个人可以看每一天怎么算的。")
            }
            Section {
                NavigationLink {
                    RotationMembersView()
                } label: {
                    LabeledContent("轮班人员", value: store.settings.rotationMembers.isEmpty ? "自动判断" : "\(store.settings.rotationMembers.count) 人")
                }
            } footer: {
                Text("轮班人员和排过调度的人，工作日网站上没给排岗位的日子不算工作量；其他人（没有组别和调度任务的人，即使值遥测）工作日没排岗位算日常班。")
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
                        if reading || store.isReadingDesktop { Spacer(); ProgressView() }
                    }
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
                        Text("工作量 \(person.workDays) 天").font(.headline)
                    }
                    }
                    Text(summary(person))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    FlowChips(items: AppStore.sortedPosts(person).map { (text: "\($0.post) ×\($0.count)", raw: $0.post) })
                }
            }
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
                     "出差 \(p.tripDays)", "休息 \(p.offDays)", "节假日 \(p.holidayDays)"]
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
        let kinds = WorkloadCounter.kinds(of: store.roster[name] ?? [:], days: days, matcher: store.matcher,
                                          rotating: store.isRotating(name), calendar: .app)
        List(days.reversed()) { day in
            let raw = store.roster[name]?[day]
            let holiday = ChinaHolidays.isHoliday(day)
            let kind = kinds[day] ?? .off
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.dateText)
                    Text(raw.map(store.matcher.displayName) ?? (holiday ? "网站上没排（法定假日）" : "网站上没排"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(kind.rawValue)
                    .font(.subheadline.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(color(kind).opacity(0.2), in: Capsule())
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
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
        }
    }
}

/// 设置轮班人员：可以直接粘贴名字，也可以在全员排班的名单里勾选。
struct RotationMembersView: View {
    @EnvironmentObject private var store: AppStore
    @State private var text = ""

    private var members: [String] { store.settings.rotationMembers }

    var body: some View {
        let zh = Locale(identifier: "zh_CN")
        let names = store.roster.keys.sorted { a, b in
            let ma = members.contains(a), mb = members.contains(b)
            return ma != mb ? ma : a.compare(b, locale: zh) == .orderedAscending
        }
        List {
            Section {
                TextField("粘贴名字，用空格、逗号或顿号隔开", text: $text, axis: .vertical)
                Button("设为轮班人员") {
                    let parsed = text.split { " ,，、;；\n\t".contains($0) }.map(String.init).filter { !$0.isEmpty }
                    var seen = Set<String>()
                    store.settings.rotationMembers = parsed.filter { seen.insert($0).inserted }
                    text = ""
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !members.isEmpty {
                    Button("清空（改回自动判断）", role: .destructive) { store.settings.rotationMembers = [] }
                }
            } footer: {
                Text(members.isEmpty
                     ? "还没设置：现在按「有组别任务或调度任务」自动判断谁是轮班的；只值遥测的不算。"
                     : "已设置 \(members.count) 人：" + members.joined(separator: "、") + "。排过调度的人也按轮班算。")
            }
            Section("全员排班里的人（点一下勾选）") {
                ForEach(names, id: \.self) { name in
                    Button {
                        if let i = store.settings.rotationMembers.firstIndex(of: name) {
                            store.settings.rotationMembers.remove(at: i)
                        } else {
                            store.settings.rotationMembers.append(name)
                        }
                    } label: {
                        HStack {
                            Text(name).foregroundStyle(Color.primary)
                            Spacer()
                            if members.contains(name) {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            } else if store.isRotating(name) {
                                Text(members.isEmpty ? "自动：轮班" : "调度").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("轮班人员")
        .navigationBarTitleDisplayMode(.inline)
    }
}
