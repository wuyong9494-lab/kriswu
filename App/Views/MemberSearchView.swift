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
            .sorted { $0.compare($1, locale: Locale(identifier: "zh_CN")) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.roster.isEmpty {
                    Section {
                        Text("还没有全员排班数据。同步时 App 会打开网站的「值班查看」页面读取全员排班；先在「今天」页下拉刷新一次，再回来搜索。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(names, id: \.self) { name in
                        NavigationLink {
                            MemberScheduleView(name: name)
                        } label: {
                            HStack {
                                Text(name)
                                Spacer()
                                if let today = store.roster[name]?[.today] {
                                    Text("今天：\(store.matcher.displayName(today))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "输入姓名")
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

    var body: some View {
        let today = DayKey.today
        let upcoming = days.filter { $0.day >= today }
        let past = days.filter { $0.day < today }
        List {
            if days.isEmpty {
                Text("没有他的排班").foregroundStyle(.secondary)
            }
            if !upcoming.isEmpty {
                Section("今天及以后") {
                    ForEach(upcoming, id: \.day) { item in
                        NavigationLink { DayRosterView(day: item.day) } label: { row(item.day, item.post, isToday: item.day == today) }
                    }
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
        .navigationTitle(name)
    }

    private func row(_ day: DayKey, _ post: String, isToday: Bool) -> some View {
        let display = ShiftDisplay(raw: post, matcher: store.matcher)
        return HStack {
            Text(day.dateText)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
            Spacer()
            Text("\(display?.emoji ?? "") \(display?.name ?? post)")
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background((display?.color ?? .gray).opacity(0.18), in: Capsule())
        }
    }
}
