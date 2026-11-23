import SwiftUI

/// Read-only schedule evidence; no model calls and no inference about actual
/// attendance, work hours, or individual performance.
struct DutyBurdenView: View {
    @EnvironmentObject private var store: AppStore
    @State private var nameQuery = ""
    @State private var onlyGaps = false

    var body: some View {
        let report = DutyBurdenAnalysis.analyze(roster: store.roster, today: .today, matcher: store.matcher,
                                                publishedDays: store.publishedDays)
        let filter = nameQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let members = report.members.filter {
            (filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter)) &&
                (!onlyGaps || !$0.isCoverageComplete || !$0.nightUnknownDates.isEmpty)
        }
        .sorted { $0.name.compare($1.name, locale: Locale(identifier: "zh_CN")) == .orderedAscending }

        List {
            overview(report)
            if !report.members.isEmpty {
                Section {
                    Toggle("只看有数据缺口的人", isOn: $onlyGaps)
                }
            }
            Section {
                if members.isEmpty {
                    Text(report.members.isEmpty ? "这 30 天没有可用的人员排班记录。" : "没有符合筛选条件的人员。")
                        .foregroundStyle(.secondary)
                }
                ForEach(members, id: \.name) { member in
                    NavigationLink {
                        DutyBurdenDetailView(member: member, start: report.start, end: report.end,
                                             records: store.roster[member.name] ?? [:],
                                             sources: store.rosterSources[member.name] ?? [:])
                    } label: {
                        memberRow(member)
                    }
                }
            } header: {
                Text("人员排班（按姓名排列）")
            } footer: {
                Text("人数和记录仅反映本机已有数据。查看个人排班明细可核对日期和原岗位。不会用这些数据评估个人表现。")
            }
        }
        .searchable(text: $nameQuery, prompt: "搜索人员")
        .appList()
        .navigationTitle("近 30 天值班负担")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("workload.dutyBurden.overview")
    }

    private func overview(_ report: DutyBurdenAnalysis.Report) -> some View {
        let gaps = report.members.filter { !$0.isCoverageComplete }.count
        let ambiguous = report.members.filter { !$0.nightUnknownDates.isEmpty }.count
        let unknownHolidayYears = report.holidayCalendarYearsWithoutData

        return Section {
            LabeledContent("统计日期", value: "\(report.start.description) 至 \(report.end.description)")
                .font(.subheadline)
            LabeledContent("有已发布排班记录的日期", value: "\(report.rosterDates.count) / 30 天")
            if gaps > 0 || ambiguous > 0 {
                Label("记录未覆盖全部日期：\(gaps) 人；有班次未能确认是否夜班：\(ambiguous) 人",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if !unknownHolidayYears.isEmpty {
                Text("本机缺少 \(unknownHolidayYears.sorted().map { String($0) }.joined(separator: "、")) 年的节假日日历，相应日期的节假日安排未能核实。")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("排班统计，不是实际工时")
        } footer: {
            Text("截至昨天，按已记录排班计算。缺失记录不当成休息，班次不明确不当成无夜班。结果仅在本机计算，不上传、不自动调整排班。")
        }
    }

    private func memberRow(_ member: DutyBurdenAnalysis.Member) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(name: member.name, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(member.name)
                    .font(.headline)
                    .foregroundStyle(store.isMe(member.name) ? Color.accentColor : Color.primary)
                Text("已记录 \(member.recordedDates.count)/30 天 · \(dutyText(member)) · \(nightText(member))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let days = member.longestDutyDays, days > 0 {
                    Text("\(member.dutyCountIsMinimum ? "已知最长" : "最长")连续值班 \(days) 天")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func nightText(_ member: DutyBurdenAnalysis.Member) -> String {
        guard let nights = member.confirmedNightDays else { return "夜班未知" }
        // An explicit zero is meaningful only when both dates and night types are known.
        if nights == 0 && member.nightCountIsMinimum { return "夜班未能核全" }
        return member.nightCountIsMinimum ? "已确认夜班 \(nights) 天" : "夜班 \(nights) 天"
    }

    private func dutyText(_ member: DutyBurdenAnalysis.Member) -> String {
        let count = member.dutyDates.count
        if count == 0 && member.dutyCountIsMinimum { return "值班未能核全" }
        return member.dutyCountIsMinimum ? "已确认值班 \(count) 天" : "值班 \(count) 天"
    }
}

private struct DutyBurdenDetailView: View {
    let member: DutyBurdenAnalysis.Member
    let start: DayKey
    let end: DayKey
    let records: [DayKey: String]
    let sources: [DayKey: Provenance]

    var body: some View {
        let recorded = member.recordedDates.sorted(by: >)
        let nights = Set(member.nightDates)
        let nightUnknown = Set(member.nightUnknownDates)
        let holiday = Set(member.holidayWorkDates)
        let duty = Set(member.dutyDates)
        List {
            Section {
                LabeledContent("有排班记录", value: "\(recorded.count)/30 天")
                LabeledContent("已记录值班", value: countLabel(duty.count, minimum: member.dutyCountIsMinimum))
                LabeledContent("已确认夜班", value: nightValue)
                LabeledContent("已确认节假日排班", value: countLabel(member.confirmedHolidayWorkDays,
                                                                    minimum: member.holidayCountIsMinimum))
                if let days = member.longestDutyDays {
                    LabeledContent("已知最长连续值班", value: "\(days) 天")
                }
                ForEach(member.longestDutyStreaks.indices, id: \.self) { index in
                    let streak = member.longestDutyStreaks[index]
                    if let first = streak.first, let last = streak.last {
                        Text(first == last ? first.description : "\(first.description) 至 \(last.description)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("\(start.description) 至 \(end.description)")
            } footer: {
                Text("仅按排班，不等于实际出勤。缺失记录不会补成休息或无值班；连续天数只计算能确认的连续日期。")
            }
            if !member.unknownDates.isEmpty || !member.nightUnknownDates.isEmpty {
                Section("未能确认") {
                    if !member.unknownDates.isEmpty {
                        DisclosureGroup("无可用排班记录 · \(member.unknownDates.count) 天") {
                            ForEach(member.unknownDates.sorted(by: >), id: \.self) { day in
                                Text(day.description).font(.footnote)
                            }
                        }
                    }
                    if !member.nightUnknownDates.isEmpty {
                        DisclosureGroup("记录未明确是否夜班 · \(member.nightUnknownDates.count) 天") {
                            ForEach(member.nightUnknownDates.sorted(by: >), id: \.self) { day in
                                Text(day.description).font(.footnote)
                            }
                        }
                    }
                }
            }
            Section("逐日证据 · 原始排班") {
                if recorded.isEmpty {
                    Text("未保留逐日记录。").foregroundStyle(.secondary)
                }
                ForEach(recorded, id: \.self) { day in
                    evidence(day: day, night: nights.contains(day), ambiguous: nightUnknown.contains(day),
                             holiday: holiday.contains(day), duty: duty.contains(day))
                }
            }
        }
        .appList()
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var nightValue: String {
        countLabel(member.confirmedNightDays, minimum: member.nightCountIsMinimum)
    }

    private func countLabel(_ count: Int?, minimum: Bool) -> String {
        guard let count else { return "未知" }
        if minimum { return count == 0 ? "未能核全" : "至少 \(count) 天" }
        return "\(count) 天"
    }

    private func evidence(day: DayKey, night: Bool, ambiguous: Bool, holiday: Bool, duty: Bool) -> some View {
        let indicators = [duty ? "值班" : nil, night ? "明确夜班" : nil, ambiguous ? "夜班未知" : nil,
                          holiday ? "节假日排班" : nil].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 4) {
            Text(day.description).font(.subheadline.weight(.semibold))
            Text(records[day] ?? "原始排班已不可用").font(.subheadline)
            if !indicators.isEmpty {
                Text(indicators.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(ambiguous ? Color.orange : Color.accentColor)
            }
            if let source = sources[day] {
                Text("来源：\(source.sourceTitle) · \(source.at.formatted(date: .numeric, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
