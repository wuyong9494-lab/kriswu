import SwiftUI

/// 搜索成员：输入姓名，列出他的全部排班（数据来自同步时读到的「值班查看」全员排班，只存在手机上）。
struct MemberSearchView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var names: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return store.roster.keys
            .filter { q.isEmpty || $0.localizedCaseInsensitiveContains(q) }
            .sorted { a, b in
                // 收藏的同事排在前面
                let fa = store.isFavorite(a), fb = store.isFavorite(b)
                if fa != fb { return fa }
                return a.compare(b, locale: Locale(identifier: "zh_CN")) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.roster.isEmpty {
                    Section {
                        Text("还没有全员排班数据。同步时 App 会打开网站的「值班查看」页面读取全员排班；同步一次再回来搜索。")
                            .foregroundStyle(.secondary)
                        SyncNowButton(source: "搜索成员")
                    }
                } else {
                    ForEach(names, id: \.self) { name in
                        let todayRaw = store.roster[name]?[.today]
                        let todayDisplay = todayRaw.flatMap { ShiftDisplay(raw: $0, matcher: store.matcher) }
                        NavigationLink {
                            MemberScheduleView(name: name)
                        } label: {
                            HStack(spacing: DS.Space.s) {
                                Avatar(name: name, size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(name).font(.subheadline.weight(.semibold))
                                        if store.isFavorite(name) {
                                            Image(systemName: "star.fill")
                                                .foregroundStyle(.yellow)
                                                .font(.caption2)
                                        }
                                    }
                                    Text(store.isMe(name) ? "本人排班" : "点击查看排班与共同休息日")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                if let todayRaw {
                                    let tint = todayDisplay?.color ?? .secondary
                                    Text(todayDisplay?.name ?? store.matcher.displayName(todayRaw))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(tint)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(tint.opacity(0.14), in: Capsule())
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "输入姓名")
            .appList()
            .navigationTitle("搜索成员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct MemberScheduleView: View {
    @EnvironmentObject private var store: AppStore
    let name: String

    private var days: [(day: DayKey, post: String)] {
        (store.roster[name] ?? [:]).map { (day: $0.key, post: $0.value) }.sorted { $0.day < $1.day }
    }

    /// 两个人都不上班的日子（网站已经排了班的）
    private func commonOffDays(from today: DayKey) -> [DayKey] {
        guard let me = store.myRosterName else { return [] }
        func off(_ person: String, _ day: DayKey) -> Bool {
            guard let raw = store.roster[person]?[day] ?? (person == me ? store.shift(on: day) : nil) else {
                return !ChinaHolidays.isWorkday(day, calendar: .app)
            }
            return DayRules.isOffDay(raw, matcher: store.matcher)
        }
        return (0..<30).map { today.adding(days: $0) }
            .filter { store.publishedDays.contains($0) && off(me, $0) && off(name, $0) }
    }

    var body: some View {
        let today = DayKey.today
        let upcoming = days.filter { $0.day >= today }
        let past = days.filter { $0.day < today }
        List {
            Section {
                HStack(spacing: DS.Space.s) {
                    Avatar(name: name, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(name).font(DS.Font.headline)
                            if store.isFavorite(name) {
                                Chip(text: "已收藏", color: .orange, icon: "star.fill")
                            }
                        }
                        Text("已记录 \(days.count) 天排班 · 后续 \(upcoming.count) 天")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
            if days.isEmpty {
                Section {
                    EmptyState(icon: "calendar.badge.exclamationmark", title: "暂无排班记录",
                               message: "同步全员排班后会显示该成员的班次安排。")
                }
            }
            if !upcoming.isEmpty {
                Section("今天及以后") {
                    ForEach(upcoming, id: \.day) { item in
                        NavigationLink { DayRosterView(day: item.day) } label: { row(item.day, item.post, isToday: item.day == today) }
                    }
                }
            }
            // 和他一起休息的日子（约饭、换班都用得上）
            let together = commonOffDays(from: today)
            if !store.isMe(name), store.myRosterName != nil, !together.isEmpty {
                Section {
                    Text(together.map { "\($0.month)/\($0.day) \($0.weekdayText)" }.joined(separator: "、"))
                        .font(.subheadline)
                } header: {
                    Text("接下来 30 天你们都休息的日子")
                } footer: {
                    Text("只算网站已经排了班的日子：两个人都写了休息、调休、请假，或者都是没排岗位的周末、节假日。")
                }
            }
            if !past.isEmpty {
                Section("之前") {
                    ForEach(past.reversed(), id: \.day) { item in
                        NavigationLink { DayRosterView(day: item.day) } label: { row(item.day, item.post, isToday: false) }
                    }
                }
            }
        }
        .appList()
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { store.toggleFavorite(name) } label: {
                    Label(store.isFavorite(name) ? "取消收藏" : "收藏",
                          systemImage: store.isFavorite(name) ? "star.fill" : "star")
                }
            }
        }
    }

    private func row(_ day: DayKey, _ post: String, isToday: Bool) -> some View {
        let display = ShiftDisplay(raw: post, matcher: store.matcher)
        return HStack {
            Text(day.dateText)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
            Spacer()
            HStack(spacing: DS.Space.xxs) {
                if let display {
                    Image(systemName: display.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(display.color)
                }
                Text(display?.name ?? post)
            }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background((display?.color ?? .gray).opacity(0.18), in: Capsule())
        }
    }
}
