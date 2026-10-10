import SwiftUI

/// 值班表：某一天所有岗位各是谁，和网页版「值班查看」一样；可以前后切换日期。
struct DayRosterView: View {
    @EnvironmentObject private var store: AppStore
    @State private var day: DayKey

    init(day: DayKey = .today) {
        _day = State(initialValue: day)
    }

    private var date: Binding<Date> {
        Binding(get: { day.date(calendar: .app, hour: 12) },
                set: { day = DayKey(date: $0, calendar: .app) })
    }

    var body: some View {
        let rows = store.dayRoster(day)
        List {
            Section {
                HStack {
                    Button { day = day.adding(days: -1) } label: {
                        Image(systemName: "chevron.left").padding(8)
                    }
                    Spacer()
                    DatePicker("日期", selection: date, displayedComponents: .date)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    Spacer()
                    Button { day = day.adding(days: 1) } label: {
                        Image(systemName: "chevron.right").padding(8)
                    }
                }
                .buttonStyle(.borderless)
                HStack {
                    Text(day.dateText).font(.headline)
                    Spacer()
                    if day != .today {
                        Button("回到今天") { day = .today }.buttonStyle(.borderless)
                    } else {
                        Text("今天").foregroundStyle(.secondary)
                    }
                }
            }

            if rows.isEmpty {
                Section {
                    Text(store.roster.isEmpty
                         ? "还没有全员排班数据。同步时 App 会打开网站的「值班查看」页面读取，先在「今天」页下拉刷新一次。"
                         : "这一天还没有全员排班数据（只能看到网站上已经排出来的日子）。")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(rows, id: \.post) { row in
                let display = ShiftDisplay(raw: row.post, matcher: store.matcher)
                let note = store.groupNotes[row.post.filter { !$0.isWhitespace }.uppercased()]
                Section {
                    names(row.names)
                    if let note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Circle().fill(display?.color ?? .gray).frame(width: 8, height: 8)
                        Text("\(display?.emoji ?? "") \(row.post)")
                    }
                }
            }
        }
        .navigationTitle("值班表")
        .navigationBarTitleDisplayMode(.inline)
        .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
            if value.translation.width < -60 { day = day.adding(days: 1) }
            if value.translation.width > 60 { day = day.adding(days: -1) }
        })
    }

    /// 人名用顿号隔开，自己的名字加粗高亮。
    private func names(_ list: [String]) -> Text {
        list.enumerated().reduce(Text("")) { text, item in
            let sep = item.offset == 0 ? Text("") : Text("、")
            let name = store.isMe(item.element)
                ? Text(item.element).bold().foregroundColor(.accentColor)
                : Text(item.element)
            return text + sep + name
        }
    }
}
