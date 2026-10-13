import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct CalendarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var year = DayKey.today.year
    @State private var month = DayKey.today.month
    @State private var editing: DayKey?
    /// 翻月方向，决定日历从哪边滑进来
    @State private var flipForward = true
    @State private var jumping = false
    @State private var jumpDate = Date()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    LazyVGrid(columns: columns, spacing: DS.Space.xxs) {
                        ForEach(weekdays, id: \.self) { w in
                            Text(w).font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(0..<leadingBlanks, id: \.self) { i in
                            Color.clear.frame(height: 64).id("blank-\(i)")
                        }
                        ForEach(days) { day in
                            // 按钮（读屏会说「按钮」，也有按下效果）
                            Button { Haptics.tap(); editing = day } label: {
                                DayCell(day: day, isToday: day == DayKey.today)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .card(padding: DS.Space.s)
                    .id("\(year)-\(month)")
                    .transition(.asymmetric(insertion: .move(edge: flipForward ? .trailing : .leading).combined(with: .opacity),
                                            removal: .opacity))
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
                        // 给家人：导出成日历文件，导入后他们的日历里就有我的班
                        ShareLink(item: ScheduleICS(schedule: store.schedule, matcher: store.matcher),
                                  preview: SharePreview("我的排班.ics")) {
                            Label("导出日历文件（给家人）", systemImage: "calendar.badge.plus")
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
            // 点年月：选一个日期直接跳过去，不用一个月一个月翻
            Button {
                jumpDate = DayKey(year: year, month: month, day: 1).date(calendar: .app, hour: 12)
                jumping = true
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "\(year)年").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text(verbatim: "\(month)月").font(DS.Font.display)
                        Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(year)年\(month)月，点按选择日期")
            .sheet(isPresented: $jumping) {
                NavigationStack {
                    DatePicker("日期", selection: $jumpDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .environment(\.calendar, .app)
                        .padding()
                        .navigationTitle("跳到")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("取消") { jumping = false } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("查看这天") {
                                    let day = DayKey(date: jumpDate, calendar: .app)
                                    jumping = false
                                    withAnimation(DS.Motion.spring) { year = day.year; month = day.month }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { editing = day }
                                }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
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
            .accessibilityLabel("上个月")
            Button { Haptics.tap(); move(1) } label: {
                Image(systemName: "chevron.right").font(.headline).frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("下个月")
        }
        .padding(.horizontal, 4)
    }

    private func move(_ delta: Int) {
        var m = month + delta, y = year
        if m < 1 { m = 12; y -= 1 }
        if m > 12 { m = 1; y += 1 }
        flipForward = delta > 0
        withAnimation(DS.Motion.spring) { month = m; year = y }
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
        // 取到过结果但没给我排班：淡淡一个点；还没取到数据的日子：留空
        let unassigned = display == nil && store.isCovered(day)
        let holiday = ChinaHolidays.isHoliday(day)
        let mineIsDuty = display.map { WorkloadCounter.isDuty($0.name) } ?? false
        VStack(spacing: DS.Space.xxs) {
            Text("\(day.day)")
                .font(.system(size: 15, weight: isToday ? .heavy : .medium, design: .rounded))
                .foregroundStyle(isToday ? Color.white : (holiday ? DS.Palette.danger : Color.primary))
                .frame(width: 28, height: 28)
                .background(Circle().fill(isToday ? DS.Palette.accent : Color.clear))
            if let display {
                // 颜色只用在图标和字上，格子本身不涂色
                Image(systemName: display.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(display.color)
                Text(display.name)
                    .font(DS.Font.overline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else if unassigned {
                Circle().fill(DS.Palette.iconSecondary.opacity(0.5)).frame(width: 4, height: 4).padding(.top, DS.Space.xxs)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
            // 这天谁值遥测（全员排班里有、又不是我自己）
            if !mineIsDuty, let duty = dutyNames {
                Text(duty)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76)
        .padding(.vertical, DS.Space.xxs)
        .background {
            // 只有遥测这种重要的日子才给一层很淡的底
            if let display, WorkloadCounter.isDuty(display.name) {
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).fill(display.color.opacity(0.12))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var dutyNames: String? {
        let names = store.dayRoster(day).filter { WorkloadCounter.isDuty($0.post) }.flatMap(\.names)
        return names.isEmpty ? nil : names.joined(separator: "·")
    }
}

private struct MonthSummary: View {
    @EnvironmentObject private var store: AppStore
    let days: [DayKey]

    var body: some View {
        let counts = Dictionary(grouping: days.compactMap { ShiftDisplay(raw: store.shift(on: $0), matcher: store.matcher) },
                                by: \.name)
            .map { (name: $0.key, symbol: $0.value[0].symbol, color: $0.value[0].color, count: $0.value.count) }
            .sorted { $0.count > $1.count }
        if !counts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(title: "本月统计", icon: "chart.pie")
                let total = max(1, counts.map(\.count).reduce(0, +))
                ForEach(counts, id: \.name) { item in
                    VStack(spacing: DS.Space.xxs) {
                        HStack(spacing: DS.Space.xs) {
                            Image(systemName: item.symbol).font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(item.color).frame(width: 18)
                            Text(item.name).font(DS.Font.body)
                            Spacer()
                            Text("\(item.count) 天").font(DS.Font.callout.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        // 占比条
                        GeometryReader { geo in
                            Capsule().fill(DS.Palette.surfaceSunken)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(item.color.opacity(0.7))
                                        .frame(width: geo.size.width * CGFloat(item.count) / CGFloat(total))
                                }
                        }
                        .frame(height: 4)
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
                if !store.canEdit {
                    Section { ReadOnlyNotice() }
                } else {
                Section("选择班次") {
                    ForEach(store.settings.shiftTypes) { type in
                        Button {
                            store.setShift(type.name, on: day)
                            dismiss()
                        } label: {
                            HStack(spacing: DS.Space.s) {
                                Image(systemName: type.symbol)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(hex: type.colorHex))
                                    .frame(width: 20)
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

/// 分享出去的 .ics 文件
struct ScheduleICS: Transferable {
    let schedule: [DayKey: String]
    let matcher: ShiftMatcher

    static var transferRepresentation: some TransferRepresentation {
        // 点了分享才生成（不在每次刷新界面时拼一百多天的文件）
        FileRepresentation(exportedContentType: .calendarEvent) { item in
            let today = DayKey.today
            let text = ICSExport.make(schedule: item.schedule, from: today.adding(days: -7), to: today.adding(days: 120),
                                      matcher: item.matcher, calendar: .app)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("我的排班.ics")
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
