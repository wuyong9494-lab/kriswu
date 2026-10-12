import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var year = DayKey.today.year
    @State private var month = DayKey.today.month
    @State private var editing: DayKey?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(weekdays, id: \.self) { w in
                            Text(w).font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(0..<leadingBlanks, id: \.self) { i in
                            Color.clear.frame(height: 64).id("blank-\(i)")
                        }
                        ForEach(days) { day in
                            DayCell(day: day, isToday: day == DayKey.today)
                                .onTapGesture { Haptics.tap(); editing = day }
                        }
                    }
                    .card(padding: 10)
                    MonthSummary(days: days)
                }
                .padding()
            }
            .appBackground()
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                // 只认明显的横向滑动，上下滚动时不翻月
                guard abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
                if value.translation.width < -60 { move(1) }
                if value.translation.width > 60 { move(-1) }
            })
            .refreshable { await store.sync(userInitiated: true) }
            .navigationTitle("排班日历")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ShareLink(item: store.monthReport(year: year, month: month)) {
                            Label("分享 / 复制本月统计", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            Task {
                                let ok = await store.pushToWeChat(title: "\(year)年\(month)月排班统计",
                                                                  content: store.monthReport(year: year, month: month), force: true)
                                ToastCenter.shared.show(ok ? "已发送到微信" : (store.settings.weChatMessage ?? "微信推送失败"),
                                                        style: ok ? .success : .error)
                            }
                        } label: {
                            Label("把本月统计发到微信", systemImage: "message")
                        }
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink {
                        WorkloadView()
                    } label: {
                        Label("工作量", systemImage: "chart.bar")
                    }
                }
            }
            .sheet(item: $editing) { DayEditor(day: $0) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "\(year)年").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Text(verbatim: "\(month)月").font(DS.Font.display)
            }
            Spacer()
            if year != DayKey.today.year || month != DayKey.today.month {
                Button("今天") {
                    Haptics.tap()
                    withAnimation { year = DayKey.today.year; month = DayKey.today.month }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .clipShape(Capsule())
            }
            Button { Haptics.tap(); move(-1) } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Button { Haptics.tap(); move(1) } label: {
                Image(systemName: "chevron.right").font(.headline).frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 4)
    }

    private func move(_ delta: Int) {
        var m = month + delta, y = year
        if m < 1 { m = 12; y -= 1 }
        if m > 12 { m = 1; y += 1 }
        withAnimation { month = m; year = y }
    }

    private var firstDay: DayKey { DayKey(year: year, month: month, day: 1) }

    private var days: [DayKey] {
        let cal = Calendar.app
        let count = cal.range(of: .day, in: .month, for: firstDay.date(calendar: cal, hour: 12))?.count ?? 30
        return (1...count).map { DayKey(year: year, month: month, day: $0) }
    }

    /// 周一为一周第一天
    private var leadingBlanks: Int {
        let weekday = Calendar.app.component(.weekday, from: firstDay.date(calendar: .app, hour: 12)) // 1 = 周日
        return (weekday + 5) % 7
    }
}

private struct DayCell: View {
    @EnvironmentObject private var store: AppStore
    let day: DayKey
    let isToday: Bool

    var body: some View {
        let display = ShiftDisplay(raw: store.shift(on: day), matcher: store.matcher)
        // 取到过结果但没给我排班：灰底「未排班」；还没取到数据的日子：留空
        let unassigned = display == nil && store.isCovered(day)
        let holiday = ChinaHolidays.isHoliday(day)
        VStack(spacing: 3) {
            Text("\(day.day)")
                .font(.subheadline.weight(isToday ? .heavy : .semibold))
                .foregroundStyle(isToday ? Color.white : (holiday ? Color.red : Color.primary))
                .frame(width: 26, height: 26)
                .background(Circle().fill(isToday ? Theme.accent : Color.clear))
            if let display {
                Text(display.emoji).font(.caption)
                Text(display.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else if unassigned {
                Spacer(minLength: 0)
                Text("未排班")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            } else {
                if holiday { Text("休").font(.caption2.bold()).foregroundStyle(.red) }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, maxHeight: 70)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(display.map { $0.color.opacity(0.18) } ?? (unassigned ? Color.gray.opacity(0.12) : Color(.secondarySystemGroupedBackground)))
        )
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isToday ? Theme.accent : .clear, lineWidth: 2))
        .contentShape(Rectangle())
    }
}

private struct MonthSummary: View {
    @EnvironmentObject private var store: AppStore
    let days: [DayKey]

    var body: some View {
        let counts = Dictionary(grouping: days.compactMap { ShiftDisplay(raw: store.shift(on: $0), matcher: store.matcher) },
                                by: \.name)
            .map { (name: $0.key, emoji: $0.value[0].emoji, color: $0.value[0].color, count: $0.value.count) }
            .sorted { $0.count > $1.count }
        if !counts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(title: "本月统计", icon: "chart.pie.fill")
                ForEach(counts, id: \.name) { item in
                    HStack {
                        Circle().fill(item.color).frame(width: 10, height: 10)
                        Text("\(item.emoji) \(item.name)")
                        Spacer()
                        Text("\(item.count) 天").foregroundStyle(.secondary)
                    }
                }
            }
            .card()
        }
    }
}

struct DayEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let day: DayKey
    @State private var custom = ""

    var body: some View {
        let current = store.shift(on: day)
        NavigationStack {
            List {
                if let current {
                    Section("当前") {
                        Text(current)
                    }
                }
                Section {
                    NavigationLink {
                        DayRosterView(day: day)
                    } label: {
                        Label("查看这一天全部组别", systemImage: "tablecells")
                    }
                    if let current, !SwapLedger.posts(current, matcher: store.matcher).isEmpty {
                        NavigationLink {
                            SwapHelperView(day: day)
                        } label: {
                            Label("找人换班", systemImage: "person.2.badge.gearshape")
                        }
                    }
                    NavigationLink {
                        SwapLedgerView()
                    } label: {
                        Label("换班账本", systemImage: "book.closed")
                    }
                }
                Section("选择班次") {
                    ForEach(store.settings.shiftTypes) { type in
                        Button {
                            store.setShift(type.name, on: day)
                            dismiss()
                        } label: {
                            HStack {
                                Text(type.emoji)
                                Text(type.name).foregroundStyle(Color.primary)
                                Spacer()
                                Circle().fill(Color(hex: type.colorHex)).frame(width: 12, height: 12)
                                if current.flatMap(store.matcher.match)?.id == type.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Section("自定义") {
                    TextField("例如：培训、加班、调休", text: $custom)
                    Button("保存") {
                        store.setShift(custom, on: day)
                        dismiss()
                    }
                    .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if current != nil {
                    Section {
                        Button("清除这一天", role: .destructive) {
                            store.setShift(nil, on: day)
                            dismiss()
                        }
                    }
                }
            }
            .appList()
            .navigationTitle(day.dateText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
