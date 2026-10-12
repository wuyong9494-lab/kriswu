import SwiftUI

/// 工作量均衡分析：有组别（组A–E）排班的人，这一周、这一个月谁干得多、谁干得少。
struct FairnessView: View {
    @EnvironmentObject private var store: AppStore
    @State private var weekOffset = 0
    @State private var year = DayKey.today.year
    @State private var month = DayKey.today.month
    /// 只算到今天（关掉则包括已经排好的以后几天）
    @State private var untilToday = false

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

    private func usable(_ days: [DayKey], known: Set<DayKey>) -> [DayKey] {
        days.filter { known.contains($0) && (!untilToday || $0 <= .today) }
    }

    var body: some View {
        let known = store.publishedDays
        let week = usable(weekDays, known: known)
        let monthKnown = usable(monthDays, known: known)
        let weekReport = WorkloadBalance.analyze(roster: store.roster, days: week, matcher: store.matcher,
                                                 tolerance: 2, members: store.rotationMembers, calendar: .app)
        let monthReport = WorkloadBalance.analyze(roster: store.roster, days: monthKnown, matcher: store.matcher,
                                                  tolerance: 3, members: store.rotationMembers, calendar: .app)
        List {
            if !ChinaHolidays.knownYears.contains(year) {
                Label("App 里还没有 \(year) 年的法定节假日，假期会被当成工作日算，请更新 App", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Section {
                Toggle("只算到今天", isOn: $untilToday)
            } footer: {
                Text("比较的是这段时间有组别（组A–E）排班的人。工作量 = 值班（遥测）+ 节假日值班调休 + 日常（各组、调度等岗位，以及没排岗位、没写休息的工作日）+ 出差。关掉「只算到今天」时，网站上已经排好组别、遥测的以后几天也算进去，看排班本身是否均衡；只有提前申请的请假、调休的日子不算。")
            }
            Section {
                switcher(title: "\(weekDays[0].month)/\(weekDays[0].day) – \(weekDays[6].month)/\(weekDays[6].day)",
                         back: { weekOffset -= 1 }, forward: { weekOffset += 1 })
                Summary(report: weekReport, empty: week.isEmpty ? "这一周还没有全员排班数据" : nil, range: rangeText(week))
            } header: {
                Text("本周工作量")
            } footer: {
                Text("和平均差 2 天以上算偏多 / 偏少；最多和最少差 1 天以内为均衡，2 天以内为基本均衡。")
            }
            if !weekReport.rows.isEmpty {
                Section { ForEach(weekReport.rows, id: \.name) { RowView(row: $0) } }
            }

            Section {
                switcher(title: "\(year)年\(month)月", back: { moveMonth(-1) }, forward: { moveMonth(1) })
                Summary(report: monthReport, empty: monthKnown.isEmpty ? "这个月还没有全员排班数据" : nil, range: rangeText(monthKnown))
            } header: {
                Text("本月工作量")
            } footer: {
                Text("和平均差 3 天以上算偏多 / 偏少；最多和最少差 1 天以内为均衡，3 天以内为基本均衡。")
            }
            if !monthReport.rows.isEmpty {
                Section { ForEach(monthReport.rows, id: \.name) { RowView(row: $0) } }
            }
        }
        .navigationTitle("工作量均衡")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: shareText(weekReport, monthReport)) { Label("分享", systemImage: "square.and.arrow.up") }
            }
        }
    }

    /// 「统计 10月1日 周四 – 10月25日 周日，共 25 天」
    private func rangeText(_ days: [DayKey]) -> String? {
        guard let first = days.first, let last = days.last else { return nil }
        return "统计 \(first.dateText) – \(last.dateText)，共 \(days.count) 天"
            + (!untilToday && last > .today ? "（含已排好的以后几天）" : "")
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

    private func shareText(_ week: BalanceReport, _ month: BalanceReport) -> String {
        func block(_ title: String, _ r: BalanceReport) -> String {
            guard !r.rows.isEmpty else { return "\(title)：没有数据" }
            return "\(title)：\(r.verdict)\n" + r.findings.map { "· \($0)" }.joined(separator: "\n") + "\n"
                + r.rows.map { row in
                    let w = row.workload
                    return "\(row.name) \(w.workDays) 天（遥测 \(w.dutyDays)，组别 \(row.groupDays)，出差 \(w.tripDays)，休息 \(w.offDays)）"
                        + (row.level == .normal ? "" : " \(row.level.rawValue)")
                }.joined(separator: "\n")
        }
        let known = store.publishedDays
        return block("本周工作量（\(rangeText(usable(weekDays, known: known)) ?? "")）", week) + "\n\n"
            + block("\(year)年\(month)月工作量（\(rangeText(usable(monthDays, known: known)) ?? "")）", month)
    }
}

private struct Summary: View {
    let report: BalanceReport
    let empty: String?
    var range: String?

    var body: some View {
        if let empty {
            Text(empty).foregroundStyle(.secondary)
        } else if report.rows.isEmpty {
            Text("这段时间没有人排组别").foregroundStyle(.secondary)
        } else {
            if let range {
                Label(range, systemImage: "calendar")
                    .font(.subheadline.bold())
            }
            HStack(alignment: .firstTextBaseline) {
                Text(report.verdict)
                    .font(.title2.bold())
                    .foregroundStyle(color)
                Spacer()
                Text("相差 \(report.spread) 天 · 平均 \(String(format: "%.1f", report.average)) 天")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(report.findings, id: \.self) { line in
                Text(line).font(.subheadline)
            }
        }
    }

    private var color: Color {
        switch report.verdict {
        case "均衡": return .green
        case "基本均衡": return .orange
        default: return .red
        }
    }
}

private struct RowView: View {
    @EnvironmentObject private var store: AppStore
    let row: BalanceReport.Row

    var body: some View {
        let w = row.workload
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
                if row.level != .normal {
                    Text(row.level.rawValue)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((row.level == .more ? Color.red : Color.blue).opacity(0.2), in: Capsule())
                }
                Text("\(w.workDays) 天").bold()
            }
            Text("遥测 \(w.dutyDays) · 组别 \(row.groupDays) · 其它日常 \(max(0, w.regularDays - row.groupDays)) · 出差 \(w.tripDays) · 休息 \(w.offDays)"
                 + (w.holidayDays > 0 ? " · 节假日 \(w.holidayDays)" : "")
                 + (w.unassignedDays > 0 ? " · 没排班 \(w.unassignedDays)" : ""))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(String(format: "%+.1f 天", row.diff))
                .font(.caption)
                .foregroundStyle(row.level == .more ? .red : (row.level == .less ? .blue : .secondary))
        }
    }
}
