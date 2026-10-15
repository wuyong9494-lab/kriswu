import SwiftUI

/// 工作量均衡分析：有组别（组A–E）排班的人，这一周、这一个月谁干得多、谁干得少。
struct FairnessView: View {
    @EnvironmentObject private var store: AppStore
    @State private var weekOffset = 0
    @State private var year = DayKey.today.year
    @State private var month = DayKey.today.month
    /// 只算到今天（关掉则包括已经排好的以后几天）
    @State private var untilToday = true
    /// 导出的表格（换周、换月、同步后重新生成，不在每次刷新界面时写文件）
    @State private var csvURL: URL?
    /// 在后台算好的结果（全员几百天，放在界面线程算会卡）
    @State private var weekReport: BalanceReport?
    @State private var monthReport: BalanceReport?

    private var weekDays: [DayKey] { Period.week(of: .today, offset: weekOffset) }

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
        let weekReport = self.weekReport ?? BalanceReport.empty
        let monthReport = self.monthReport ?? BalanceReport.empty
        List {
            if !ChinaHolidays.knownYears.contains(year) {
                Label("App 里还没有 \(year) 年的法定节假日，假期会被当成工作日算，请更新 App", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Section {
                Toggle("只算到今天", isOn: $untilToday)
            } footer: {
                ExpandableText(text: "比较的是这段时间有组别（组A–E）排班的人。工作量 = 值班（遥测）+ 日常（各组、调度等岗位）+ 出差，休息、调休、请假、值班交接前一律不算；这里比较的都是轮组别的人，他们没排岗位、没写休息的工作日算上班，不算工作量。关掉「只算到今天」时，网站上已经排好组别、遥测的以后几天也算进去，看排班本身是否均衡；只有提前申请的请假、调休的日子不算。")
            }
            Section {
                switcher(title: "\(weekDays[0].month)/\(weekDays[0].day) – \(weekDays[6].month)/\(weekDays[6].day)",
                         back: { weekOffset -= 1 }, forward: { weekOffset += 1 })
                Summary(report: weekReport, empty: week.isEmpty ? "这一周还没有全员排班数据" : (self.weekReport == nil ? "正在计算…" : nil), range: rangeText(week))
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
                Summary(report: monthReport, empty: monthKnown.isEmpty ? "这个月还没有全员排班数据" : (self.monthReport == nil ? "正在计算…" : nil), range: rangeText(monthKnown))
            } header: {
                Text("本月工作量")
            } footer: {
                Text("和平均差 3 天以上算偏多 / 偏少；最多和最少差 1 天以内为均衡，3 天以内为基本均衡。")
            }
            if !monthReport.rows.isEmpty {
                Section { ForEach(monthReport.rows, id: \.name) { RowView(row: $0) } }
            }
        }
        .task(id: "\(weekOffset)-\(year)-\(month)-\(untilToday)-\(store.dataRevision)") {
            let roster = store.roster, matcher = store.matcher, members = store.rotationMembers
            let (w, m) = await Task.detached(priority: .userInitiated) {
                (WorkloadBalance.analyze(roster: roster, days: week, matcher: matcher, tolerance: 2, members: members, calendar: .app),
                 WorkloadBalance.analyze(roster: roster, days: monthKnown, matcher: matcher, tolerance: 3, members: members, calendar: .app))
            }.value
            self.weekReport = w
            self.monthReport = m
            csvURL = store.csvFile(named: "工作量均衡\(year)年\(month)月.csv",
                                   text: WorkloadCSV.balance(w, title: "本周（\(rangeText(week) ?? "")）") + "\n"
                                       + WorkloadCSV.balance(m, title: "\(year)年\(month)月（\(rangeText(monthKnown) ?? "")）"))
        }
        .appList()
        .navigationTitle("工作量均衡")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ShareLink(item: shareText(weekReport, monthReport)) { Label("分享文字", systemImage: "text.alignleft") }
                    if let csvURL {
                        ShareLink(item: csvURL) { Label("导出表格（Excel 能打开）", systemImage: "tablecells") }
                    }
                } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
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
        PeriodPager(title: title, back: back, forward: forward)
    }

    private func moveMonth(_ delta: Int) {
        (year, month) = Period.shiftMonth(year: year, month: month, by: delta)
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
    @EnvironmentObject private var store: AppStore
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
                    .font(DS.Font.title)
                    .foregroundStyle(color)
                Spacer()
                Chip(text: "相差 \(report.spread) 天", color: color)
            }
            WorkloadBarChart(items: report.rows.map { .init(name: $0.name, value: $0.workload.workDays, highlight: store.isMe($0.name),
                                                            present: $0.workload.presentDays) },
                             average: report.average)
                .padding(.vertical, DS.Space.xs)
            ForEach(report.findings, id: \.self) { line in
                Text(line).font(.subheadline)
            }
        }
    }

    private var color: Color {
        switch report.verdict {
        case "均衡": return DS.Palette.success
        case "基本均衡": return DS.Palette.warning
        default: return DS.Palette.danger
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
                Avatar(name: row.name, size: 28)
                Text(row.name).font(DS.Font.headline)
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
                WorkPresentPair(work: w.workDays, present: w.presentDays)
            }
            Text("遥测 \(w.dutyDays) · 组别 \(row.groupDays) · 其它岗位 \(max(0, w.regularDays - row.groupDays)) · 出差 \(w.tripDays)"
                 + (w.attendanceDays > 0 ? " · 上班没排岗位 \(w.attendanceDays)（不算工作量）" : "")
                 + " · 休息 \(w.offDays)"
                 + (w.holidayDays > 0 ? " · 节假日放假 \(w.holidayDays)" : "")
                 + (w.unassignedDays > 0 ? " · 没排班 \(w.unassignedDays)" : ""))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(String(format: "%+.1f 天", row.diff))
                .font(.caption)
                .foregroundStyle(row.level == .more ? .red : (row.level == .less ? .blue : .secondary))
        }
    }
}
