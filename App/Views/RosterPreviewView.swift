import SwiftUI

/// 排班预演：网站还没排出来的日子，先按反推的规律推演谁值遥测、谁在休息；网站排出来后自动对比猜中了多少。
struct RosterPreviewView: View {
    @EnvironmentObject private var store: AppStore
    @State private var days: [RosterPreview.Day]?

    var body: some View {
        List {
            if let days {
                if days.isEmpty {
                    Section {
                        AppEmptyStateCard(icon: "calendar", title: "暂时无法预演",
                                   message: "全员排班数据太少，或者看不出遥测怎么轮。先在工作量统计页「读取今年 1 月以来全部」。")
                    }
                }
                ForEach(days, id: \.day) { d in
                    Section {
                        HStack {
                            Label("遥测", systemImage: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(DS.Palette.accent)
                            Spacer()
                            if let name = d.telemetry { person(name) } else { Text("暂无结果").foregroundStyle(.secondary) }
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
                Section { ProgressView("正在读取排班预演…") }
            }
            accuracySection
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
                Text("发布新排班后，这里会显示预演与实际安排的对比。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                let hits = results.filter(\.hit).count
                LabeledContent("与实际排班相符", value: "\(hits)/\(results.count) 天（\(Int((Double(hits) / Double(results.count) * 100).rounded()))%）")
                DisclosureGroup("最近对比") {
                    ForEach(Array(results.suffix(30).reversed().enumerated()), id: \.offset) { _, r in
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Label(String(r.day.dropFirst(5)), systemImage: r.hit ? "checkmark.circle" : "xmark.circle")
                                .font(DS.Font.headline)
                                .accessibilityLabel("\(r.day)，\(r.hit ? "相符" : "不符")")
                            Text("预演 \(r.guess) · 实际 \(r.actual)")
                                .font(DS.Font.body)
                        }
                    }
                }
            }
        } header: {
            Text("历史对比")
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
