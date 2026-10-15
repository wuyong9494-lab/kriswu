import SwiftUI

/// 排班预演：网站还没排出来的日子，先按反推的规律推演谁值遥测、谁在休息；网站排出来后自动对比猜中了多少。
struct RosterPreviewView: View {
    @EnvironmentObject private var store: AppStore
    @State private var days: [RosterPreview.Day]?

    var body: some View {
        List {
            accuracySection
            if let days {
                if days.isEmpty {
                    Section {
                        EmptyState(icon: "wand.and.stars", title: "还推不出来",
                                   message: "全员排班数据太少，或者看不出遥测怎么轮。先在工作量统计页「读取今年 1 月以来全部」。")
                    }
                }
                ForEach(days, id: \.day) { d in
                    Section {
                        HStack {
                            Label("遥测", systemImage: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(DS.Palette.accent)
                            Spacer()
                            if let name = d.telemetry { person(name) } else { Text("推不出").foregroundStyle(.secondary) }
                        }
                        if !d.resting.isEmpty {
                            row("休息（值完遥测）", icon: "bed.double", names: d.resting)
                        }
                        if !d.away.isEmpty {
                            row("已申请", icon: "airplane.departure", names: d.away)
                        }
                    } header: {
                        Text("\(d.day.month)月\(d.day.day)日 " + SchedulePatterns.weekdayName(SchedulePatterns.weekdayIndex(d.day, calendar: .app))
                             + (ChinaHolidays.isHoliday(d.day) ? " · 节假日" : ""))
                    }
                }
            } else {
                Section { SkeletonRows(rows: 6) }
            }
        }
        .appList()
        .navigationTitle("排班预演")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(store.dataRevision)-\(DayKey.today)") {
            days = store.rosterPreview()
        }
    }

    @ViewBuilder
    private var accuracySection: some View {
        let results = store.settings.previewResults
        Section {
            if results.isEmpty {
                Text("网站排出新的一周后，App 会自动拿之前的预演对一对，在这里显示猜对了几天。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                let hits = results.filter(\.hit).count
                HStack {
                    Text("遥测猜对").font(DS.Font.headline)
                    Spacer()
                    Text("\(hits)/\(results.count) 天（\(Int((Double(hits) / Double(results.count) * 100).rounded()))%）")
                        .font(DS.Font.headline.monospacedDigit())
                }
                DisclosureGroup("最近对比") {
                    ForEach(Array(results.suffix(30).reversed().enumerated()), id: \.offset) { _, r in
                        HStack {
                            Text(r.day.dropFirst(5)).monospacedDigit().font(.caption)
                            Spacer()
                            Text("猜 \(r.guess)").font(.caption)
                            Image(systemName: r.hit ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(r.hit ? Color.green : Color.orange)
                            Text("实际 \(r.actual)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } footer: {
            Text("只推演网站还没排的日子。按：谁能值哪几天（网站人员表）、轮转顺序、请假出差顺延、值完遥测休几天。组A–E 怎么排看不出固定排法，不推演。")
        }
    }

    private func person(_ name: String) -> some View {
        Text(name).fontWeight(store.isMe(name) ? .bold : .regular)
            .foregroundStyle(store.isMe(name) ? DS.Palette.accent : Color.primary)
    }

    private func row(_ title: String, icon: String, names: [String]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: icon).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(names.joined(separator: "、")).font(.subheadline).multilineTextAlignment(.trailing)
        }
    }
}
