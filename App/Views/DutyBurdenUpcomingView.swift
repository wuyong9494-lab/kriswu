import SwiftUI

struct DutyBurdenUpcomingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var focus: CoverSelection?

    private struct CoverSelection: Identifiable {
        let member: String
        let day: DayKey
        let review: DutyBurdenAnalysis.CoverReview?
        var id: String { "\(member)-\(day)" }
    }

    var body: some View {
        let today = DayKey.today
        let calendar = Calendar.dayMath
        let next = (1...7).map { today.adding(days: $0, calendar: calendar) }
        let runs = DutyBurdenAnalysis.upcomingRuns(roster: store.roster, today: today,
                                                   published: store.publishedDays, matcher: store.matcher)
        let missing = next.filter { !store.publishedDays.contains($0) }
        let changes = store.settings.teamChanges.filter {
            (next.contains($0.day) || ($0.day <= today && $0.day >= today.adding(days: -30, calendar: calendar)))
        }.sorted { ($0.day, $0.detected) > ($1.day, $1.detected) }
        List {
            Section {
                LabeledContent("已发布日期", value: "\(next.count - missing.count)/7 天")
                if !missing.isEmpty {
                    Text("未见已发布排班：" + missing.map(\.dateText).joined(separator: "、"))
                        .font(.footnote).foregroundStyle(.orange)
                }
            } footer: {
                Text("按本机同步的组别和遥测分工判断排班是否已有发布记录，不使用预测。仍可能有个别人员缺行。")
            }
            Section {
                if runs.isEmpty {
                    Text("现有记录未检出连续 3 天及以上的在岗安排。")
                        .foregroundStyle(.secondary)
                }
                ForEach(runs) { run in
                    DisclosureGroup {
                        ForEach(run.days, id: \.self) { day in
                            Button {
                                focus = CoverSelection(member: run.member, day: day,
                                                       review: DutyBurdenAnalysis.coverReview(
                                                        roster: store.roster, member: run.member, day: day, today: today,
                                                        published: store.publishedDays, matcher: store.matcher))
                            } label: {
                                LabeledContent(day.dateText, value: store.roster[run.member]?[day] ?? "")
                            }
                        }
                    } label: {
                        LabeledContent(run.member, value: "连续 \(run.days.count) 天")
                    }
                }
            } header: {
                Text("未来 7 天 · 连续在岗复核")
            } footer: {
                Text("这不是违规判定。点具体日期可看可联系的人选；缺记录不连成一段，也不当成明确的休息。")
            }
            Section {
                if changes.isEmpty {
                    Text("本机没有保留此范围的岗位人员变动。").foregroundStyle(.secondary)
                }
                ForEach(changes) { change in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(change.summary).font(.subheadline)
                        Text("岗位日期 \(change.day.dateText) · 同步发现于 \(change.detected.formatted(date: .numeric, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("岗位人员变动 · 近 30 天至未来 7 天")
            } footer: {
                Text("这些是同步时发现的排班变化，不能确认是临时替班，也不能作为实际出勤记录。")
            }
        }
        .appList()
        .navigationTitle("排班复核")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $focus) { item in
            NavigationStack {
                List {
                    Section {
                        LabeledContent("原排班人员", value: item.member)
                        LabeledContent("岗位日期", value: item.day.dateText)
                        if let review = item.review {
                            LabeledContent("岗位", value: review.post)
                        }
                    }
                    Section {
                        if let review = item.review {
                            if review.candidates.isEmpty {
                                Text("现有记录不足以列出人选。").foregroundStyle(.secondary)
                            }
                            ForEach(review.candidates) { candidate in
                                LabeledContent(candidate.name, value: "同岗记录 \(candidate.previousPostDay.dateText)")
                            }
                        } else {
                            Text("没有可确认的单一岗位，无法列出人选。").foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("可询问的人选 · 不是已确认替班")
                    } footer: {
                        Text("候选人在当日和前后一天均明确为普通休息，且近 90 天有同岗排班。仍要人工核对资质、真实可用性与休息要求。这里不发消息，不改排班。")
                    }
                }
                .appList()
                .navigationTitle("补位参考")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { focus = nil }
                    }
                }
            }
        }
    }
}
