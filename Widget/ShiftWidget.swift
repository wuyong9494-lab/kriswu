import SwiftUI
import WidgetKit
import ActivityKit

struct ShiftEntry: TimelineEntry {
    let date: Date
    let today: WidgetDay?
    let tomorrow: WidgetDay?
    let hasData: Bool
}

struct ShiftProvider: TimelineProvider {
    private let sample = ShiftEntry(
        date: Date(),
        today: WidgetDay(date: "", title: "组D", emoji: "👥", colorHex: "#4A90E2"),
        tomorrow: WidgetDay(date: "", title: "组B", emoji: "👥", colorHex: "#4A90E2"),
        hasData: true)

    func placeholder(in context: Context) -> ShiftEntry { sample }

    func getSnapshot(in context: Context, completion: @escaping (ShiftEntry) -> Void) {
        completion(context.isPreview ? sample : entry(for: Date(), snapshot: WidgetStore.load()))
    }

    /// 准备今天和接下来 7 天每个 0 点的内容，过了 0 点自动换成新的一天，不需要打开 App。
    func getTimeline(in context: Context, completion: @escaping (Timeline<ShiftEntry>) -> Void) {
        let snapshot = WidgetStore.load()
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: Date())
        var entries = [entry(for: Date(), snapshot: snapshot)]
        for offset in 1...7 {
            if let day = calendar.date(byAdding: .day, value: offset, to: start) {
                entries.append(entry(for: day, snapshot: snapshot))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(for date: Date, snapshot: WidgetSnapshot?) -> ShiftEntry {
        let byDate = Dictionary((snapshot?.days ?? []).map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let tomorrow = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: date) ?? date
        return ShiftEntry(date: date,
                          today: byDate[WidgetStore.key(for: date)],
                          tomorrow: byDate[WidgetStore.key(for: tomorrow)],
                          hasData: snapshot != nil)
    }
}

struct ShiftWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShiftEntry

    // App 会把「取到了但没排班」的日子写成「未排班」；这里查不到的是还没取到数据的日子
    private var todayTitle: String { entry.today?.title ?? (entry.hasData ? "暂无数据" : "打开 App") }
    private var tomorrowTitle: String { entry.tomorrow?.title ?? "—" }
    private var color: Color { entry.today.map { Color(hex: $0.colorHex) } ?? .gray }

    private var weekday: String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let c = Calendar(identifier: .gregorian).dateComponents([.month, .day, .weekday], from: entry.date)
        return "\(c.month ?? 0)/\(c.day ?? 0) 周\(names[(c.weekday ?? 1) - 1])"
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("今天：\(todayTitle)")
                .widgetBackground(Color.clear)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Text(todayTitle)
                    .font(.system(size: 20, weight: .bold))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(4)
            }
            .widgetBackground(Color.clear)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("今天 \(weekday)").font(.caption2)
                Text(todayTitle).font(.headline).lineLimit(1).minimumScaleFactor(0.5)
                Text("明天：\(tomorrowTitle)").font(.caption2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetBackground(Color.clear)
        case .systemMedium:
            HStack(spacing: 12) {
                dayBlock(label: "今天", title: todayTitle, big: true)
                Divider().overlay(Color.white.opacity(0.5))
                dayBlock(label: "明天", title: tomorrowTitle, big: false)
            }
            .padding()
            .widgetBackground(color.gradient)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("今天 · \(weekday)")
                    .font(.caption.weight(.semibold))
                    .opacity(0.9)
                Spacer(minLength: 0)
                Text(todayTitle)
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                Spacer(minLength: 0)
                Text("明天：\(tomorrowTitle)")
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding()
            .widgetBackground(color.gradient)
        }
    }

    private func dayBlock(label: String, title: String, big: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).opacity(0.9)
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: big ? 40 : 28, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.35)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// iOS 17 起小组件要用 containerBackground 设置背景，iOS 16 用普通背景。
    @ViewBuilder
    func widgetBackground<S: ShapeStyle>(_ style: S) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(style, for: .widget)
        } else {
            background(style)
        }
    }
}

struct ShiftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.kind, provider: ShiftProvider()) { entry in
            ShiftWidgetView(entry: entry)
        }
        .configurationDisplayName("今日班组")
        .description("显示今天和明天的分工，每天 0 点自动更新。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct ShiftWidgetBundle: WidgetBundle {
    var body: some Widget {
        ShiftWidget()
        WeekWidget()
        NextDutyWidget()
        DutyLiveActivity()
    }
}

/// 值遥测时锁屏和灵动岛上的倒计时
struct DutyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DutyAttributes.self) { context in
            HStack(spacing: 12) {
                Text("📡").font(.largeTitle)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(context.attributes.post)值班中").font(.headline)
                    Text(context.state.after).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if context.isStale {
                        Text("已下班").font(.title3.bold())
                    } else {
                        Text("离下班").font(.caption2).foregroundStyle(.secondary)
                        Text(timerInterval: context.state.start...max(context.state.start, context.state.end), countsDown: true)
                            .font(.title2.monospacedDigit().bold())
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110, alignment: .trailing)
                    }
                }
            }
            .padding()
            .activityBackgroundTint(Color(hex: "#17A2B8").opacity(0.25))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("📡 \(context.attributes.post)").font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.start...max(context.state.start, context.state.end), countsDown: true)
                        .font(.headline.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.after).font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Text("📡")
            } compactTrailing: {
                Text(timerInterval: context.state.start...max(context.state.start, context.state.end), countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
            } minimal: {
                Text("📡")
            }
        }
    }
}

// MARK: - 本周 7 天

struct WeekEntry: TimelineEntry {
    let date: Date
    let days: [(key: String, label: String, day: WidgetDay?)]
}

struct WeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekEntry { entry(for: Date(), snapshot: nil) }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        completion(entry(for: Date(), snapshot: WidgetStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        let snapshot = WidgetStore.load()
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: Date())
        let entries = [entry(for: Date(), snapshot: snapshot)] + (1...3).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start).map { entry(for: $0, snapshot: snapshot) }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// 从今天起 7 天
    func entry(for date: Date, snapshot: WidgetSnapshot?) -> WeekEntry {
        let calendar = Calendar(identifier: .gregorian)
        let byDate = Dictionary((snapshot?.days ?? []).map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        let days = (0..<7).compactMap { offset -> (key: String, label: String, day: WidgetDay?)? in
            guard let d = calendar.date(byAdding: .day, value: offset, to: date) else { return nil }
            let key = WidgetStore.key(for: d)
            let label = offset == 0 ? "今" : names[calendar.component(.weekday, from: d) - 1]
            return (key, label, byDate[key])
        }
        return WeekEntry(date: date, days: days)
    }
}

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekWidget", provider: WeekProvider()) { entry in
            HStack(spacing: 4) {
                ForEach(entry.days, id: \.key) { d in
                    VStack(spacing: 4) {
                        Text(d.label).font(.caption2.bold()).foregroundStyle(.secondary)
                        Text(d.day?.emoji ?? "").font(.caption)
                        Text(d.day?.title ?? "—")
                            .font(.caption2.bold())
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 6)
                    .background((d.day.map { Color(hex: $0.colorHex) } ?? .gray).opacity(0.22),
                                in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(10)
            .widgetBackground(Color(.systemBackground))
        }
        .configurationDisplayName("本周排班")
        .description("从今天起 7 天的分工。")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - 下次遥测

struct NextDutyEntry: TimelineEntry {
    let date: Date
    /// 下一次遥测那天（yyyy-MM-dd）和离今天几天；nil 表示一个月内没有
    let next: (key: String, days: Int)?
}

struct NextDutyProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextDutyEntry { NextDutyEntry(date: Date(), next: ("", 3)) }

    func getSnapshot(in context: Context, completion: @escaping (NextDutyEntry) -> Void) {
        completion(entry(for: Date(), snapshot: WidgetStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextDutyEntry>) -> Void) {
        let snapshot = WidgetStore.load()
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: Date())
        let entries = [entry(for: Date(), snapshot: snapshot)] + (1...7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start).map { entry(for: $0, snapshot: snapshot) }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    func entry(for date: Date, snapshot: WidgetSnapshot?) -> NextDutyEntry {
        let calendar = Calendar(identifier: .gregorian)
        let today = WidgetStore.key(for: date)
        let next = (snapshot?.days ?? []).filter { $0.date >= today && $0.title.contains("遥测") }.map(\.date).min()
        guard let next, let nextDate = DateFormatterCache.day.date(from: next) else { return NextDutyEntry(date: date, next: nil) }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: nextDate)).day ?? 0
        return NextDutyEntry(date: date, next: (next, days))
    }
}

enum DateFormatterCache {
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

struct NextDutyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextDutyWidget", provider: NextDutyProvider()) { entry in
            NextDutyView(entry: entry)
        }
        .configurationDisplayName("下次遥测")
        .description("距离下一次遥测还有几天。")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct NextDutyView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextDutyEntry

    private var big: String {
        guard let n = entry.next else { return "—" }
        return n.days == 0 ? "今天" : "\(n.days)"
    }
    private var dateText: String {
        guard let key = entry.next?.key, key.count == 10 else { return "一个月内没有" }
        return "\(Int(key.dropFirst(5).prefix(2)) ?? 0)月\(Int(key.suffix(2)) ?? 0)日"
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("📡").font(.caption2)
                    Text(big).font(.system(size: 18, weight: .bold)).minimumScaleFactor(0.5)
                }
            }
            .widgetBackground(Color.clear)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("📡 下次遥测").font(.caption2)
                Text(entry.next.map { $0.days == 0 ? "今天" : "\($0.days) 天后" } ?? "—").font(.headline)
                Text(dateText).font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetBackground(Color.clear)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("📡 下次遥测").font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(big).font(.system(size: 44, weight: .heavy, design: .rounded)).minimumScaleFactor(0.4)
                    if let n = entry.next, n.days > 0 { Text("天后").font(.caption) }
                }
                Spacer(minLength: 0)
                Text(dateText).font(.caption)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding()
            .widgetBackground(Color(hex: "#17A2B8").gradient)
        }
    }
}
