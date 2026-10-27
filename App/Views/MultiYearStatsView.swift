import Charts
import SwiftUI

/// 历年统计：每年过完存一份全年工作量（排班原始数据只留一年多），我自己历年的数、往年全员的数
struct MultiYearStatsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var current: AppStore.Workload?
    @State private var year: Int?

    /// 我一年的数（今年的到今天为止）
    private struct MyYear: Identifiable {
        var id: Int { year }
        let year: Int
        let partial: Bool
        let workDays: Int
        let dutyDays: Int
        let holidayWorkedDays: Int
        let tripDays: Int
    }

    var body: some View {
        let archives = store.records.yearArchives
        let mine = myYears(archives)
        let shownYear = year ?? archives.first?.year
        List {
            Section {
                if mine.count >= 2 {
                    chart(mine)
                }
                if mine.isEmpty {
                    Text(current == nil ? "正在算今年的…" : "还没有你的数：全员排班里没找到你的名字（设置 › 账号与同步）。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(mine.reversed()) { y in
                    LabeledContent {
                        Text(line(y)).monospacedDigit()
                    } label: {
                        Text(y.partial ? "\(String(y.year)) 年（到今天）" : "\(String(y.year)) 年")
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("我的历年")
            } footer: {
                Text("每年过完、App 里还有那一年全员排班的时候，自动把全年统计存一份（排班原始数据只留一年多）。存的是当时按当时规则算的数，以后改规则不会变。")
            }
            if let shownYear, let archive = archives.first(where: { $0.year == shownYear }) {
                Section {
                    if archives.count > 1 {
                        Picker("哪一年", selection: Binding(get: { shownYear }, set: { year = $0 })) {
                            ForEach(archives) { Text(String($0.year)).tag($0.year) }
                        }
                        .pickerStyle(.segmented)
                    }
                    ForEach(archive.people, id: \.name) { p in
                        HStack(alignment: .firstTextBaseline) {
                            Text(p.name).font(.subheadline.weight(store.isMe(p.name) ? .semibold : .regular))
                                .foregroundStyle(store.isMe(p.name) ? DS.Palette.accent : Color.primary)
                            Spacer()
                            Text("工作量 \(p.workDays) · 遥测 \(p.dutyDays)")
                                .font(.subheadline).monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("\(String(archive.year)) 年全员")
                } footer: {
                    Text(rangeText(archive))
                }
            } else {
                Section {
                    Text("还没有存下往年的。今年过完、App 同步过以后，明年这里就能看到今年的全年统计。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .appList()
        .navigationTitle("历年统计")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.dataRevision) {
            current = await store.workloadInBackground(year: DayKey.today.year, month: nil)
        }
    }

    private func myYears(_ archives: [YearArchive]) -> [MyYear] {
        var list = archives.compactMap { a -> MyYear? in
            guard let p = a.people.first(where: { store.isMe($0.name) }) else { return nil }
            return MyYear(year: a.year, partial: false, workDays: p.workDays, dutyDays: p.dutyDays,
                          holidayWorkedDays: p.holidayWorkedDays, tripDays: p.tripDays)
        }
        let thisYear = DayKey.today.year
        if let current, !list.contains(where: { $0.year == thisYear }),
           let p = current.people.first(where: { store.isMe($0.name) }) {
            list.append(MyYear(year: thisYear, partial: true, workDays: p.workDays, dutyDays: p.dutyDays,
                               holidayWorkedDays: p.holidayWorkedDays, tripDays: p.tripDays))
        }
        return list.sorted { $0.year < $1.year }
    }

    /// 「工作量 240 · 遥测 40 · 节假日上班 3」
    private func line(_ y: MyYear) -> String {
        var parts = ["工作量 \(y.workDays)", "遥测 \(y.dutyDays)"]
        if y.holidayWorkedDays > 0 { parts.append("节假日上班 \(y.holidayWorkedDays)") }
        if y.tripDays > 0 { parts.append("出差 \(y.tripDays)") }
        return parts.joined(separator: " · ")
    }

    private func rangeText(_ a: YearArchive) -> String {
        let range = a.first.flatMap { f in a.last.map { "\(f.dateText) – \($0.dateText)，" } } ?? ""
        return "\(range)统计了 \(a.days) 天，\(a.saved.formatted(date: .abbreviated, time: .omitted)) 存的。按工作量从多到少。"
    }

    /// 我每年的工作量（一种颜色；今年没过完，颜色淡一点）
    private func chart(_ years: [MyYear]) -> some View {
        Chart(years) { y in
            BarMark(x: .value("年", String(y.year)), y: .value("工作量", y.workDays), width: .ratio(0.5))
                .foregroundStyle(DS.Palette.accent.opacity(y.partial ? 0.45 : 1))
                .cornerRadius(4)
                .annotation(position: .top) {
                    Text("\(y.workDays)").font(DS.Font.caption).foregroundStyle(.secondary)
                }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(DS.Palette.hairline)
                AxisValueLabel().font(DS.Font.caption)
            }
        }
        .chartXAxis { AxisMarks { _ in AxisValueLabel().font(DS.Font.caption) } }
        .frame(height: 180)
        .padding(.vertical, DS.Space.xs)
        .accessibilityLabel("我每年的工作量，下面列着每年的数")
    }
}
