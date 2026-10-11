import SwiftUI

/// 排班合理度分析：这一周组A–E 怎么分的，这个月遥测值班排得公不公平。
struct FairnessView: View {
    @EnvironmentObject private var store: AppStore
    @State private var weekOffset = 0
    @State private var year = DayKey.today.year
    @State private var month = DayKey.today.month

    private var weekDays: [DayKey] {
        let cal = Calendar.app
        let today = DayKey.today
        let weekday = cal.component(.weekday, from: today.date(calendar: cal, hour: 12))   // 1 = 周日
        let monday = today.adding(days: -((weekday + 5) % 7) + 7 * weekOffset)
        return (0..<7).map { monday.adding(days: $0) }
    }

    private var monthDays: [DayKey] {
        let cal = Calendar.app
        let first = DayKey(year: year, month: month, day: 1)
        let count = cal.range(of: .day, in: .month, for: first.date(calendar: cal, hour: 12))?.count ?? 30
        return (1...count).map { DayKey(year: year, month: month, day: $0) }
    }

    var body: some View {
        let known = Set(store.roster.values.flatMap(\.keys))
        let week = weekDays.filter(known.contains)
        let monthKnown = monthDays.filter(known.contains)
        let groupReport = FairnessAnalyzer.groupWeek(roster: store.roster, days: week, restBalance: store.settings.restBalance,
                                                     matcher: store.matcher, calendar: .app)
        let teleReport = FairnessAnalyzer.telemetryMonth(roster: store.roster, days: monthKnown,
                                                         restBalance: store.settings.restBalance,
                                                         matcher: store.matcher, calendar: .app)
        List {
            Section {
                switcher(title: "\(weekDays[0].month)/\(weekDays[0].day) – \(weekDays[6].month)/\(weekDays[6].day)",
                         back: { weekOffset -= 1 }, forward: { weekOffset += 1 })
                ReportSummary(report: groupReport, unit: "天", empty: week.isEmpty ? "这一周还没有全员排班数据" : nil)
            } header: {
                Text("本周组A–E 分配")
            } footer: {
                Text("看：每天每个组是否都有人且只有一个人；同一个人一周别总在同一个组（3 次以上）；不要连续 6 天以上都在组里；每人组别天数差距别超过 2 天；待休多的人别排太多。")
            }
            if !groupReport.rows.isEmpty {
                Section {
                    ForEach(groupReport.rows, id: \.name) { row in RowView(row: row, unit: "天") }
                }
            }

            Section {
                switcher(title: "\(year)年\(month)月", back: { moveMonth(-1) }, forward: { moveMonth(1) })
                ReportSummary(report: teleReport, unit: "次", empty: monthKnown.isEmpty ? "这个月还没有全员排班数据" : nil)
            } header: {
                Text("本月遥测值班")
            } footer: {
                Text("看：每天都有人遥测；同一个人两次遥测之间至少隔 2 天；每人次数和平均差不超过 2 次；节假日、周末的遥测要分散；待休多的人别再多排。日期后「节」= 法定节假日，「末」= 周末。包括已经排好的以后的日子。")
            }
            if !teleReport.rows.isEmpty {
                Section {
                    ForEach(teleReport.rows, id: \.name) { row in RowView(row: row, unit: "次") }
                }
            }
        }
        .navigationTitle("排班合理度")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: shareText(groupReport, teleReport)) { Label("分享", systemImage: "square.and.arrow.up") }
            }
        }
    }

    private func switcher(title: String, back: @escaping () -> Void, forward: @escaping () -> Void) -> some View {
        HStack {
            Button(action: back) { Image(systemName: "chevron.left") }
            Spacer()
            Text(title).font(.headline)
            Spacer()
            Button(action: forward) { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.borderless)
    }

    private func moveMonth(_ delta: Int) {
        var m = month + delta, y = year
        if m < 1 { m = 12; y -= 1 }
        if m > 12 { m = 1; y += 1 }
        month = m; year = y
    }

    private func shareText(_ g: FairnessReport, _ t: FairnessReport) -> String {
        func block(_ title: String, _ r: FairnessReport, _ unit: String) -> String {
            var s = "\(title)：\(r.score) 分（\(r.verdict)）"
            s += r.findings.isEmpty ? "\n没有发现问题" : "\n" + r.findings.map { "· \($0)" }.joined(separator: "\n")
            s += "\n" + r.rows.map { row in
                "\(row.name) \(row.count)\(unit)" + (store.settings.restBalance[row.name].map { "（待休\($0)）" } ?? "") + "：\(row.detail)"
            }.joined(separator: "\n")
            return s
        }
        return block("本周组A–E（\(weekDays[0].month)/\(weekDays[0].day)起）", g, "天") + "\n\n"
            + block("\(year)年\(month)月遥测", t, "次")
    }
}

private struct ReportSummary: View {
    let report: FairnessReport
    let unit: String
    let empty: String?

    var body: some View {
        if let empty {
            Text(empty).foregroundStyle(.secondary)
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text("\(report.score)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text("分 · \(report.verdict)").font(.headline).foregroundStyle(color)
                Spacer()
                Text("平均 \(String(format: "%.1f", report.average)) \(unit)/人")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if report.findings.isEmpty {
                Label("没有发现问题", systemImage: "checkmark.circle").foregroundStyle(.green)
            } else {
                ForEach(report.findings, id: \.self) { finding in
                    Label(finding, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var color: Color { report.score >= 85 ? .green : (report.score >= 70 ? .orange : .red) }
}

private struct RowView: View {
    @EnvironmentObject private var store: AppStore
    let row: FairnessReport.Row
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.name).font(.headline)
                    .foregroundStyle(store.isMe(row.name) ? Color.accentColor : Color.primary)
                if let rest = store.settings.restBalance[row.name], rest > 0 {
                    Text("待休 \(rest)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2), in: Capsule())
                }
                Spacer()
                Text("\(row.count) \(unit)").bold()
            }
            Text(row.detail).font(.footnote).foregroundStyle(.secondary)
            if let warning = row.warning {
                Text(warning).font(.footnote).foregroundStyle(.orange)
            }
        }
    }
}
