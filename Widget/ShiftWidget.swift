import SwiftUI
import WidgetKit

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

    private var todayTitle: String { entry.today?.title ?? (entry.hasData ? "未排班" : "打开 App") }
    private var tomorrowTitle: String { entry.tomorrow?.title ?? "未排班" }
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
    }
}
