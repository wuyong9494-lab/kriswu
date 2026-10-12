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
                        // 问候 + 日期
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(Theme.greeting(context.date).uppercased())
                                .font(DS.Font.overline)
                                .kerning(0.8)
                                .foregroundStyle(.secondary)
                            Text(context.date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day().weekday(.wide)))
                                .font(DS.Font.display)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                        if let days = SigningInfo.daysLeft, days <= 2 {
                            Label("签名还有 \(days) 天到期：打开 LocalDevVPN，再到 SideStore 点「Refresh All」续签",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .card(tint: .orange)
                        }
                        if store.syncIsStale {
                            StaleSyncBanner()
                        }
                        if store.schedule.isEmpty {
                            EmptyScheduleHint()
                        }
                        TodayHero(day: today, now: context.date) {
                            Haptics.tap(); editing = today.adding(days: 1)
                        }
                        .onTapGesture { Haptics.tap(); editing = today }
                        WeekStrip(from: today) { Haptics.tap(); editing = $0 }
                        TaskChecklistCard(day: today)
                        RecentChanges()
                        QuickActions(today: today) { searching = true }
                        FavoritesCard(today: today)
                        UpcomingList(from: today.adding(days: 8), count: 14) { editing = $0 }
                        SyncStatus()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .appBackground()
            }
            .refreshable {
                // 下拉刷新后在顶部显示几秒「同步完成：没有变动 / 3 处变动」
                let ok = await store.sync(userInitiated: true)
                ToastCenter.shared.show(store.settings.lastSyncMessage ?? (ok ? "已同步" : "同步失败"),
                                        style: ok ? .success : .error)
            }
            .navigationTitle("值班提醒")
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

/// 今天的大卡片：按班次颜色的渐变，大字显示分工、组别工作内容，下面带明天。
struct TodayHero: View {
    @EnvironmentObject private var store: AppStore
    let day: DayKey
    let now: Date
    /// 点「明天」那一行
    var onTomorrow: () -> Void = {}

    var body: some View {
        let raw = store.shift(on: day)
        let display = ShiftDisplay(raw: raw, matcher: store.matcher)
        let color = display?.color ?? Color(hex: "#8E8E93")
        let tomorrow = ShiftDisplay(raw: store.shift(on: day.adding(days: 1)), matcher: store.matcher)
        let isDuty = raw.map { WorkloadCounter.isDuty(store.matcher.displayName($0)) } ?? false
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("今天").font(.subheadline.weight(.semibold)).opacity(0.85)
                Spacer()
                if store.settings.morningEnabled {
                    Label("每天 \(store.settings.morning.text)", systemImage: "bell.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.2), in: Capsule())
                }
            }
            HStack(alignment: .center, spacing: 14) {
                Text(display?.emoji ?? "🗓️")
                    .font(.system(size: 34))
                    .frame(width: 62, height: 62)
                    .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(display?.name ?? (store.isCovered(day) ? "未排班" : "暂无数据"))
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if isDuty {
                        Text("值班到明天 08:30").font(.subheadline.weight(.medium)).opacity(0.9)
                    }
                }
            }
            // 这个组要干什么（电脑版网页上的说明，或自己在设置里填写的）
            let notes = store.notes(for: raw)
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(notes, id: \.group) { item in
                        Text(notes.count > 1 ? "\(item.group)：\(item.note)" : item.note)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Divider().overlay(Color.white.opacity(0.35))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "sunrise.fill").font(.caption)
                    Text("明天").font(.subheadline.weight(.semibold))
                    Text(tomorrow.map { "\($0.emoji) \($0.name)" } ?? (store.isCovered(day.adding(days: 1)) ? "未排班" : "—"))
                        .font(.subheadline)
                    Spacer()
                    if store.settings.eveningEnabled {
                        Text("前一天 \(store.settings.evening.text) 提醒").font(.caption).opacity(0.8)
                    }
                    Image(systemName: "chevron.right").font(.caption2).opacity(0.7)
                }
                let tomorrowNotes = store.notes(for: store.shift(on: day.adding(days: 1)))
                if let first = tomorrowNotes.first {
                    Text(tomorrowNotes.count > 1 ? "\(first.group)：\(first.note)" : first.note)
                        .font(.caption)
                        .opacity(0.85)
                        .lineLimit(2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTomorrow)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.gradient(color), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: color.opacity(0.35), radius: 16, x: 0, y: 8)
        .contentShape(Rectangle())
    }
}

/// 接下来 7 天，一格一天，横着滑。
private struct WeekStrip: View {
    @EnvironmentObject private var store: AppStore
    let from: DayKey
    let onTap: (DayKey) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(1...7, id: \.self) { i in
                    let day = from.adding(days: i)
                    let display = ShiftDisplay(raw: store.shift(on: day), matcher: store.matcher)
                    let holiday = ChinaHolidays.isHoliday(day)
                    Button { onTap(day) } label: {
                        VStack(spacing: 6) {
                            Text(i == 1 ? "明天" : day.weekdayText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(holiday ? Color.red : Color.secondary)
                            Text("\(day.day)").font(.title3.bold())
                            Text(display?.emoji ?? (store.isCovered(day) ? "·" : " ")).font(.title3)
                            Text(display?.name ?? (store.isCovered(day) ? "未排" : "—"))
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .frame(width: 62, height: 112)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill((display?.color ?? .gray).opacity(display == nil ? 0.08 : 0.18))
                        }
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// 常用功能，一格一个
private struct QuickActions: View {
    @EnvironmentObject private var store: AppStore
    let today: DayKey
    let onSearch: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(title: "常用", icon: "square.grid.2x2.fill")
            LazyVGrid(columns: columns, spacing: 16) {
                tile("本周全员", "tablecells.fill", .blue) { WeekRosterView() }
                tile("工作量", "chart.bar.fill", .purple) { WorkloadView() }
                tile("均衡分析", "scalemass.fill", .indigo) { FairnessView() }
                tile("请假规划", "calendar.badge.minus", .orange) { LeavePlannerView() }
                tile("找人换班", "person.2.fill", .teal) { NextWorkSwapView(today: today) }
                tile("换班账本", "book.closed.fill", .brown) { SwapLedgerView() }
                Button(action: { Haptics.tap(); onSearch() }) { label("搜索成员", "magnifyingglass", .pink) }
                    .buttonStyle(PressableStyle())
                tile("自动同步", "wand.and.stars", store.automationLooksMissing ? .red : .green) { AutomationGuideView() }
            }
            if store.automationLooksMissing {
                NavigationLink { AutomationGuideView() } label: {
                    Label("还没设置快捷指令自动同步，App 关掉后排班变动收不到。点这里一步步设置。", systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .card()
    }


    private func tile<D: View>(_ title: String, _ icon: String, _ color: Color, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination) { label(title, icon, color) }
            .buttonStyle(PressableStyle())
            .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
    }

    private func label(_ title: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(title).font(.caption).foregroundStyle(.primary).lineLimit(1)
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
                            Text("\(display.emoji) \(display.name)")
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(display.color.opacity(0.18), in: Capsule())
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
        return Text("\(label) \(display?.name ?? "—")")
            .font(.footnote)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((display?.color ?? .gray).opacity(0.18), in: Capsule())
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
