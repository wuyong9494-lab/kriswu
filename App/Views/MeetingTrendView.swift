import Charts
import SwiftUI

/// 周会各组趋势：每周还挂着几个（按组叠起来）、每周新提 / 解决几个、各组现在的情况
struct MeetingTrendView: View {
    @EnvironmentObject private var store: AppStore

    private var week: DayKey { MeetingTracker.monday(of: .today) }

    /// 图里最多分 7 个组，再多的并成「其他」（颜色不够分）
    private static let maxGroups = DS.Palette.series.count - 1
    private static let other = "其他"

    private struct Bar: Identifiable {
        var id: String { label + "|" + group }
        let label: String
        let group: String
        let open: Int
    }

    var body: some View {
        let issues = store.meeting.issues
        let points = MeetingInsights.trend(issues, through: week)
        let order = MeetingInsights.groupOrder(issues)
        let shownGroups = order.count > Self.maxGroups + 1 ? Array(order.prefix(Self.maxGroups)) + [Self.other] : order
        let weeks = points.map(\.week).reduce(into: [DayKey]()) { if $0.last != $1 { $0.append($1) } }
        List {
            if issues.isEmpty {
                Text("还没有周会问题。导入周会文档以后，每周记一笔，这里画出各组还挂着几个。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Section {
                    chart(points: points, groups: shownGroups)
                    if weeks.count < 2 {
                        Text("现在只有一周的记录，每周导入一次，过两周就看得出走势。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("每周还挂着几个")
                } footer: {
                    Text("从 App 第一次导入周会文档那周算起，最多看 12 周。这周没再提、待确认的不算挂着。")
                }
                Section("每周") {
                    ForEach(weeks.reversed(), id: \.self) { w in
                        let ofWeek = points.filter { $0.week == w }
                        LabeledContent("\(w.month)/\(w.day) 那周") {
                            Text(weekLine(ofWeek)).monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
                Section("各组现在") {
                    ForEach(MeetingInsights.groupStats(issues, week: week), id: \.group) { stat in
                        groupRow(stat, color: color(of: stat.group, in: shownGroups))
                    }
                }
            }
        }
        .appList()
        .navigationTitle("各组趋势")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chart(points: [MeetingInsights.WeekPoint], groups: [String]) -> some View {
        var bars: [String: Bar] = [:]
        var order: [String] = []
        for p in points {
            let label = "\(p.week.month)/\(p.week.day)"
            let group = groups.contains(p.group) ? p.group : Self.other
            let key = label + "|" + group
            if bars[key] == nil { order.append(key) }
            bars[key] = Bar(label: label, group: group, open: (bars[key]?.open ?? 0) + p.open)
        }
        let data = order.compactMap { bars[$0] }
        return Chart(data) { bar in
            BarMark(x: .value("周", bar.label), y: .value("还挂着", bar.open), width: .ratio(0.6))
                .foregroundStyle(by: .value("组", bar.group))
        }
        .chartForegroundStyleScale(domain: groups, range: Array(DS.Palette.series.prefix(groups.count)))
        .chartLegend(position: .bottom, alignment: .leading)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(DS.Palette.hairline)
                AxisValueLabel().font(DS.Font.caption)
            }
        }
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(DS.Font.caption) }
        }
        .frame(height: 220)
        .padding(.vertical, DS.Space.xs)
        .accessibilityLabel("每周各组还挂着几个问题，下面「每周」里有每周的数")
    }

    /// 「挂着 7 · 新提 2 · 解决 1」
    private func weekLine(_ points: [MeetingInsights.WeekPoint]) -> String {
        let open = points.reduce(0) { $0 + $1.open }
        let new = points.reduce(0) { $0 + $1.new }
        let solved = points.reduce(0) { $0 + $1.resolved }
        var parts = ["挂着 \(open)"]
        if new > 0 { parts.append("新提 \(new)") }
        if solved > 0 { parts.append("解决 \(solved)") }
        return parts.joined(separator: " · ")
    }

    private func color(of group: String, in groups: [String]) -> Color {
        let i = groups.firstIndex(of: group) ?? groups.firstIndex(of: Self.other) ?? 0
        return DS.Palette.series[min(i, DS.Palette.series.count - 1)]
    }

    private func groupRow(_ stat: MeetingInsights.GroupStat, color: Color) -> some View {
        var parts: [String] = []
        if let oldest = stat.oldestWeeks, oldest >= 2 { parts.append("最久的挂到第 \(oldest) 周") }
        if stat.quiet > 0 { parts.append("\(stat.quiet) 个待确认") }
        if let avg = stat.averageWeeksToResolve {
            parts.append("解决了 \(stat.resolved) 个，平均 \(avg.formatted(.number.precision(.fractionLength(0...1)))) 周")
        }
        return HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(stat.group).font(.subheadline.weight(.medium))
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(stat.open == 0 ? "都解决了" : "挂着 \(stat.open)")
                .font(.subheadline).monospacedDigit()
                .foregroundStyle(stat.open == 0 ? DS.Palette.success : Color.primary)
        }
        .accessibilityElement(children: .combine)
    }
}
