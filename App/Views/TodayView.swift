import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: DayKey?
    @State private var searching = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let today = DayKey(date: context.date, calendar: .app)
                ScrollView {
                    VStack(spacing: DS.Space.m) {
                        // 问候小字 → 超大的日号 → 月份星期：三级层级，一眼看到重点
                        DateHeader(date: context.date).staggered(0)
                        if let days = SigningInfo.daysLeft, days <= 2 {
                            Label("签名还有 \(days) 天到期：打开 LocalDevVPN，再到 SideStore 点「Refresh All」续签",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(DS.Font.body)
                                .card(tint: DS.Palette.warning)
                        }
                        if store.syncIsStale {
                            StaleSyncBanner()
                        }
                        if store.schedule.isEmpty {
                            EmptyScheduleHint()
                        }
                        // 外层用轻点手势、里面「明天」是按钮：按钮优先，不会被外层吞掉
                        TodayHero(day: today, now: context.date) { Haptics.tap(); editing = today.adding(days: 1) }
                            .onTapGesture { Haptics.tap(); editing = today }
                            .staggered(1)
                        WeekStrip(from: today) { Haptics.tap(); editing = $0 }.staggered(2)
                        WorkLogCard(day: today).staggered(2)
                        DutyInsightCard(today: today).staggered(3)
                        TaskChecklistCard(day: today).staggered(3)
                        RecentChanges().staggered(3)
                        // 两列：左边本月数字，右边常用入口（高度不同，有节奏）
                        HStack(alignment: .top, spacing: DS.Space.s) {
                            MonthStatCard(today: today)
                            QuickActions(today: today) { searching = true }
                        }
                        .staggered(4)
                        FavoritesCard(today: today).staggered(5)
                        UpcomingList(from: today.adding(days: 8), count: 14) { editing = $0 }.staggered(6)
                        SyncStatus().staggered(7)
                    }
                    .padding(.horizontal, DS.Space.m)
                    .padding(.bottom, DS.Space.l)
                }
                .appBackground()
            }
            .refreshable {
                // 下拉刷新后在顶部显示几秒「同步完成：没有变动 / 3 处变动」
                let ok = await store.sync(userInitiated: true)
                ToastCenter.shared.show(store.settings.lastSyncMessage ?? (ok ? "已同步" : "同步失败"),
                                        style: ok ? .success : .error)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    NavigationLink {
                        DayRosterView()
                    } label: {
                        Label("值班表", systemImage: "tablecells")
                    }
                    Button { searching = true } label: {
                        Label("搜索成员", systemImage: "magnifyingglass")
                    }
                }
            }
            .sheet(item: $editing) { DayEditor(day: $0) }
            .sheet(isPresented: $searching) { MemberSearchView() }
        }
    }
}

/// 顶部日期：GOOD MORNING 小字 → 超大日号 → 月份和星期
private struct DateHeader: View {
    let date: Date

    var body: some View {
        let day = DayKey(date: date, calendar: .app)
        VStack(alignment: .leading, spacing: 0) {
            Text(Theme.greeting(date))
                .font(DS.Font.overline)
                .kerning(1.2)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: DS.Space.s) {
                Text("\(day.day)")
                    .font(DS.Font.giant)
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "\(day.month)月").font(DS.Font.title).foregroundStyle(.primary)
                    Text(day.weekdayText).font(DS.Font.callout).foregroundStyle(.secondary)
                }
                .padding(.bottom, DS.Space.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, DS.Space.xs)
    }
}

/// 今天的大卡片：按班次颜色的渐变，超大字显示分工、组别工作内容，下面带明天。
struct TodayHero: View {
    @EnvironmentObject private var store: AppStore
    let day: DayKey
    let now: Date
    /// 点「明天」那一行
    var onTomorrow: () -> Void = {}

    var body: some View {
        let raw = store.shift(on: day)
        let display = ShiftDisplay(raw: raw, matcher: store.matcher)
        let color = display?.color ?? Color(hex: "#6E6E78")
        let tomorrow = ShiftDisplay(raw: store.shift(on: day.adding(days: 1)), matcher: store.matcher)
        let isDuty = raw.map { WorkloadCounter.isDuty(store.matcher.displayName($0)) } ?? false
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack {
                Label("今天", systemImage: display?.symbol ?? "calendar")
                    .font(DS.Font.caption)
                    .padding(.horizontal, DS.Space.xs).padding(.vertical, DS.Space.xxs)
                    .background(Color.white.opacity(0.16), in: Capsule())
                Spacer()
                if store.settings.morningEnabled {
                    Label("每天 \(store.settings.morning.text)", systemImage: "bell")
                        .font(DS.Font.caption)
                        .opacity(0.85)
                }
            }
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(display?.name ?? (store.isCovered(day) ? "未排班" : "暂无数据"))
                    .font(DS.Font.hero)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if isDuty {
                    Text("值班到明天 08:30").font(DS.Font.callout).opacity(0.9)
                }
            }
            // 这个组要干什么（电脑版网页上的说明，或自己在设置里填写的）
            let notes = store.notes(for: raw)
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    ForEach(notes, id: \.group) { item in
                        Text(notes.count > 1 ? "\(item.group)：\(item.note)" : item.note)
                            .font(DS.Font.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(DS.Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            }
            Button(action: onTomorrow) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    HStack(spacing: DS.Space.xs) {
                        Text("明天").font(DS.Font.caption).opacity(0.8)
                        if let tomorrow {
                            Image(systemName: tomorrow.symbol).font(.system(size: 12, weight: .semibold))
                            Text(tomorrow.name).font(DS.Font.callout)
                        } else {
                            Text(store.isCovered(day.adding(days: 1)) ? "未排班" : "—").font(DS.Font.callout)
                        }
                        Spacer()
                        if store.settings.eveningEnabled {
                            Text("前一天 \(store.settings.evening.text) 提醒").font(DS.Font.caption).opacity(0.7)
                        }
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).opacity(0.6)
                    }
                    let tomorrowNotes = store.notes(for: store.shift(on: day.adding(days: 1)))
                    if let first = tomorrowNotes.first {
                        Text(tomorrowNotes.count > 1 ? "\(first.group)：\(first.note)" : first.note)
                            .font(DS.Font.caption)
                            .opacity(0.75)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(.top, DS.Space.s)
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.22)).frame(height: 0.5) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
            shape.fill(Theme.gradient(color))
                // 顶边高光 + 底部一点暗，像一块有厚度的玻璃
                .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.05)],
                                                            startPoint: .top, endPoint: .bottom), lineWidth: 1))
                // 右下角一个很淡的大图标水印，不抢文字
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: display?.symbol ?? "calendar")
                        .font(.system(size: 108, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.07))
                        .offset(x: 18, y: 26)
                }
                .clipShape(shape)
        }
        .shadow(color: color.opacity(0.32), radius: 22, x: 0, y: 12)
        .contentShape(Rectangle())
    }
}

/// 接下来 7 天，一格一天，横着滑。颜色只用在图标和文字上，格子本身是玻璃。
private struct WeekStrip: View {
    @EnvironmentObject private var store: AppStore
    let from: DayKey
    let onTap: (DayKey) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.xs) {
                ForEach(1...7, id: \.self) { i in
                    let day = from.adding(days: i)
                    let display = ShiftDisplay(raw: store.shift(on: day), matcher: store.matcher)
                    let holiday = ChinaHolidays.isHoliday(day)
                    Button { onTap(day) } label: {
                        VStack(spacing: DS.Space.xs) {
                            Text(i == 1 ? "明天" : day.weekdayText)
                                .font(DS.Font.overline)
                                .foregroundStyle(holiday ? DS.Palette.danger : .secondary)
                            Text("\(day.day)").font(DS.Font.title)
                            Image(systemName: display?.symbol ?? "minus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(display?.color ?? DS.Palette.iconSecondary)
                                .frame(height: 16)
                            Text(display?.name ?? (store.isCovered(day) ? "未排" : "—"))
                                .font(DS.Font.caption)
                                .foregroundStyle(display == nil ? .secondary : .primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(width: 64, height: 116)
                        .background {
                            let shape = RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                            shape.fill(.ultraThinMaterial)
                                .overlay(shape.fill(DS.Palette.surface.opacity(0.7)))
                                .overlay(shape.strokeBorder(DS.Palette.hairline, lineWidth: 1))
                        }
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.vertical, DS.Space.xxs)
        }
    }
}

/// 本月到今天的数字：工作量、遥测、待休（数字会从 0 跳上来）
private struct MonthStatCard: View {
    @EnvironmentObject private var store: AppStore
    let today: DayKey

    var body: some View {
        let report = store.workload(year: today.year, month: today.month)
        let me = report.people.first { store.isMe($0.name) }
        let rest = store.myRosterName.flatMap { store.settings.restBalance[$0] }
        NavigationLink { WorkloadView() } label: {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text("本月 · 到今天")
                    .font(DS.Font.overline).kerning(0.6).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: DS.Space.xxs) {
                        CountUpText(value: me?.workDays ?? 0, font: DS.Font.giant)
                        Text("天").font(DS.Font.caption).foregroundStyle(.secondary)
                    }
                    Text("工作量").font(DS.Font.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: DS.Space.m) {
                    VStack(alignment: .leading, spacing: 0) {
                        CountUpText(value: me?.dutyDays ?? 0, font: DS.Font.title)
                        Text("遥测").font(DS.Font.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        CountUpText(value: rest ?? 0, font: DS.Font.title)
                        Text("待休").font(DS.Font.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(PressableStyle())
    }
}

/// 常用功能：单色玻璃图标，2×4 排
private struct QuickActions: View {
    @EnvironmentObject private var store: AppStore
    let today: DayKey
    let onSearch: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: DS.Space.xs), count: 2)

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("常用").font(DS.Font.overline).kerning(0.6).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: DS.Space.s) {
                tile("本周全员", "tablecells") { WeekRosterView() }
                tile("均衡分析", "scalemass") { FairnessView() }
                tile("请假规划", "calendar.badge.minus") { LeavePlannerView() }
                tile("找人换班", "person.2") { NextWorkSwapView(today: today) }
                tile("换班账本", "book.closed") { SwapLedgerView() }
                Button(action: { Haptics.tap(); onSearch() }) { label("搜索成员", "magnifyingglass") }
                    .buttonStyle(PressableStyle())
                tile("自动同步", store.automationLooksMissing ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath",
                     color: store.automationLooksMissing ? DS.Palette.warning : nil) { AutomationGuideView() }
                tile("工作量", "chart.bar") { WorkloadView() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func tile<D: View>(_ title: String, _ icon: String, color: Color? = nil,
                               @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination) { label(title, icon, color: color) }
            .buttonStyle(PressableStyle())
            .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
    }

    private func label(_ title: String, _ icon: String, color: Color? = nil) -> some View {
        VStack(spacing: DS.Space.xxs + 2) {
            IconBadge(icon: icon, color: color, size: 40)
            Text(title).font(DS.Font.caption).foregroundStyle(color ?? .primary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct UpcomingList: View {
    @EnvironmentObject private var store: AppStore
    let from: DayKey
    let count: Int
    let onTap: (DayKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle(title: "之后两周", icon: "calendar")
                .padding(.bottom, 8)
            ForEach(0..<count, id: \.self) { i in
                let day = from.adding(days: i)
                let display = ShiftDisplay(raw: store.shift(on: day), matcher: store.matcher)
                Button { onTap(day) } label: {
                    HStack {
                        Text(day.dateText)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let display {
                            ShiftLabel(display: display, font: DS.Font.callout)
                        } else if store.isCovered(day) {
                            Text("未排班")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.18), in: Capsule())
                        } else {
                            Text("—").foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                if i < count - 1 { Divider() }
            }
        }
        .card()
    }
}

/// 超过一天没同步成功：红色提示，避免照着旧排班上班。
private struct StaleSyncBanner: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(store.settings.lastSync.map { "从 \($0.formatted(date: .abbreviated, time: .shortened)) 起一直没同步成功" }
                  ?? "还没有同步成功过", systemImage: "exclamationmark.octagon.fill")
                .font(.headline)
            Text((store.settings.lastSyncMessage ?? "同步失败") + "\n现在显示的可能不是最新排班。下拉刷新重试；一直失败到「设置 › 诊断」看原因。")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.gradient(.red), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// 最近 3 天内同步发现的排班变动。
private struct RecentChanges: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let recent = store.settings.changeLog.filter { Date().timeIntervalSince($0.date) < 3 * 86_400 }
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(title: "最近排班变动", icon: "arrow.left.arrow.right", color: .orange) {
                    Button("清除") { store.settings.changeLog = [] }
                        .font(.footnote)
                }
                ForEach(recent, id: \.self) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened) + " 发现")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.text)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .card(tint: .orange)
        }
    }
}

/// 收藏的同事今天、明天在哪个组。
private struct FavoritesCard: View {
    @EnvironmentObject private var store: AppStore
    let today: DayKey

    var body: some View {
        if !store.settings.favorites.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                CardTitle(title: "关注的同事", icon: "star.fill", color: .orange)
                    .padding(.bottom, 8)
                ForEach(Array(store.settings.favorites.enumerated()), id: \.element) { i, name in
                    NavigationLink {
                        MemberScheduleView(name: name)
                    } label: {
                        HStack {
                            Avatar(name: name, size: 28)
                            Text(name)
                            Spacer()
                            post("今天", store.roster[name]?[today])
                            post("明天", store.roster[name]?[today.adding(days: 1)])
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    if i < store.settings.favorites.count - 1 { Divider() }
                }
            }
            .card()
        }
    }

    private func post(_ label: String, _ raw: String?) -> some View {
        let display = ShiftDisplay(raw: raw, matcher: store.matcher)
        return HStack(spacing: DS.Space.xxs) {
            Text(label).foregroundStyle(.secondary)
            if let display {
                Image(systemName: display.symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(display.color)
            }
            Text(display?.name ?? "—")
        }
        .font(DS.Font.caption)
    }
}

private struct EmptyScheduleHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("还没有排班数据", systemImage: "tray")
                .font(.headline)
            Text("到「设置」里填写排班网址自动同步，或者导入/粘贴排班表；也可以在「日历」里逐天点选。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .card(tint: Theme.accent)
    }
}

struct SyncStatus: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 4) {
            if store.isSyncing {
                HStack(spacing: DS.Space.xs) { DSSpinner(size: 14); Text("正在同步…") }
            } else if store.canSync {
                if let message = store.settings.lastSyncMessage {
                    Text(message)
                }
                if let last = store.settings.lastSync {
                    Text("上次成功同步：\(last.formatted(date: .abbreviated, time: .shortened))")
                }
                Text("下拉可刷新")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}

/// 找人换班：点开时才找下一个有班的日子（没有就明天）
private struct NextWorkSwapView: View {
    @EnvironmentObject private var store: AppStore
    let today: DayKey

    var body: some View {
        let day = (0...30).map { today.adding(days: $0) }
            .first { !SwapLedger.posts(store.shift(on: $0), matcher: store.matcher).isEmpty } ?? today.adding(days: 1)
        SwapHelperView(day: day)
    }
}


/// 下次遥测（按顺序推算）和排班预警（值完遥测该休却排了岗位、工作日没写休息）
private struct DutyInsightCard: View {
    @EnvironmentObject private var store: AppStore
    let today: DayKey

    var body: some View {
        let turn = store.myDutyTurn()
        let warnings = store.myRestWarnings()
        if turn != nil || !warnings.isEmpty {
            NavigationLink { SchedulePatternsView() } label: {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    if let turn {
                        HStack(spacing: DS.Space.s) {
                            IconBadge(icon: "antenna.radiowaves.left.and.right", size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("下次遥测").font(DS.Font.caption).foregroundStyle(.secondary)
                                Text(turnText(turn)).font(DS.Font.headline).foregroundStyle(.primary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    ForEach(warnings.prefix(3), id: \.key) { w in
                        Label {
                            Text(w.text).font(DS.Font.caption).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        } icon: {
                            Image(systemName: w.kind == .assigned ? "exclamationmark.triangle.fill" : "questionmark.circle")
                                .foregroundStyle(w.kind == .assigned ? DS.Palette.warning : Color.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(tint: warnings.contains { $0.kind == .assigned } ? DS.Palette.warning : nil)
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func turnText(_ t: AppStore.DutyTurn) -> String {
        if t.scheduled, let day = t.day {
            return day == today ? "今天" : "\(day.dateText)（网站已排）"
        }
        let ahead = t.ahead == 0 ? "下一个就是你" : "前面还有 \(t.ahead) 人"
        return (t.day.map { "大约 \($0.dateText) · " } ?? "") + ahead
    }
}
