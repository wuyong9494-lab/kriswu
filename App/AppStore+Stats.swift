import Foundation

/// 工作量统计（按月、全年）、表格导出
@MainActor
extension AppStore {
    func workload(year: Int, month: Int?) -> Workload {
        let key = "\(year)-\(month ?? 0)-\(DayKey.today)"
        if let cached = workloadCache[key] { return cached }
        let value = computeWorkload(year: year, month: month)
        workloadCache[key] = value
        return value
    }

    private func computeWorkload(year: Int, month: Int?) -> Workload {
        Self.buildWorkload(year: year, month: month, today: .today, published: publishedDays, roster: roster,
                           matcher: matcher, members: rotationMembers, restBalance: settings.restBalance)
    }

    /// 过完了的年份：全员排班还在的时候把全年统计存一份（原始数据只留一年多），以后能和往年比。
    /// 数据变了、过了零点时检查；这一年存过、天数没变多就不重算
    func archivePastYears() async {
        guard !Self.isDemo else { return }
        let today = DayKey.today
        let byYear = Dictionary(grouping: publishedDays.filter { $0 <= today }, by: \.year)
        for (year, days) in byYear.sorted(by: { $0.key < $1.key }) {
            let existing = records.yearArchives.first { $0.year == year }
            guard YearArchive.needsSaving(year: year, availableDays: days.count, existing: existing, today: today) else { continue }
            let report = await workloadInBackground(year: year, month: nil)
            guard !report.days.isEmpty else { continue }
            records.yearArchives = YearArchive.merging(YearArchive(year: year, days: report.days, people: report.people),
                                                       into: records.yearArchives)
        }
    }

    /// 全年这种大统计：在后台算，算好放进缓存（数据在算的时候变了就不放）
    func workloadInBackground(year: Int, month: Int?) async -> Workload {
        let key = "\(year)-\(month ?? 0)-\(DayKey.today)"
        if let cached = workloadCache[key] { return cached }
        let revision = dataRevision
        let (today, published, roster, matcher, members, rest) = (DayKey.today, publishedDays, roster, matcher,
                                                                rotationMembers, settings.restBalance)
        let value = await Task.detached(priority: .userInitiated) {
            AppStore.buildWorkload(year: year, month: month, today: today, published: published, roster: roster,
                                   matcher: matcher, members: members, restBalance: rest)
        }.value
        if revision == dataRevision { workloadCache[key] = value }
        return value
    }

    /// 只用传进来的数据，可以在后台线程算
    nonisolated static func buildWorkload(year: Int, month: Int?, today: DayKey, published: Set<DayKey>, roster: Roster,
                                          matcher: ShiftMatcher, members: Set<String>?, restBalance: [String: Int]) -> Workload {
        // 只统计到今天：网站上提前排好的以后的日子还没上，不算
        let days = published.filter { $0.year == year && (month == nil || $0.month == month) && $0 <= today }.sorted()
        let zh = Locale(identifier: "zh_CN")
        let people = WorkloadCounter.count(roster: roster, days: days, matcher: matcher, members: members,
                                           calendar: .app).sorted { a, b in
            a.workDays != b.workDays ? a.workDays > b.workDays : a.name.compare(b.name, locale: zh) == .orderedAscending
        }
        var text = "\(year)年" + (month.map { "\($0)月" } ?? "全年") + "工作量统计"
        if let first = days.first, let last = days.last {
            text += "（\(first.dateText) – \(last.dateText)，共 \(days.count) 天；工作量 = 值班（遥测）+ 日常（各组、调度等岗位；除了调度，没排岗位、没写休息的工作日也算）+ 出差；休息、调休、请假、值班交接前一律不算；上班 = 工作量 + 假期里值完遥测后休息的那天）"
        }
        for p in people {
            text += "\n\(p.name)：工作量 \(p.workDays) 天（值班 \(p.dutyDays)\(p.dutyRestDays > 0 ? "，值班调休 \(p.dutyRestDays)" : "")，日常 \(p.regularDays)"
                + (p.blankWorkDays > 0 ? "（其中没排岗位 \(p.blankWorkDays)）" : "") + "，出差 \(p.tripDays)），上班 \(p.presentDays) 天"
                + (p.attendanceDays > 0 ? "（其中 \(p.attendanceDays) 天不算工作量）" : "")
                + "，休息 \(p.offDays) 天，节假日放假 \(p.holidayDays) 天" + (p.unassignedDays > 0 ? "，没排班 \(p.unassignedDays) 天" : "")
                + (restBalance[p.name].map { "，待休 \($0) 天" } ?? "")
                + (p.holidayWorkedDays > 0 ? "，节假日上班 \(p.holidayWorkedDays) 天" : "") + "；"
                + Self.sortedPosts(p).map { "\($0.post)×\($0.count)" }.joined(separator: " ")
        }
        // 轮组别的人单独看：上了多少天班，其中多少天网站上没给排岗位
        let members = people.filter(\.isGroupMember).sorted { $0.name.compare($1.name, locale: zh) == .orderedAscending }
        if !members.isEmpty {
            text += "\n\n轮组别的人（\(members.count) 人）：上班天数，其中没排班（工作日网站上没排岗位、没写休息，照常算工作量）"
            for p in members { text += "\n\(p.name)：上班 \(p.presentDays) 天，其中没排班 \(p.blankWorkDays) 天" }
        }
        return Workload(days: days, people: people, text: text)
    }

    /// 把一段 CSV 文字存成临时文件（带 BOM，Excel 才认得出中文）
    func csvFile(named name: String, text: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }

    /// 导出成表格文件（CSV，Excel / WPS / Numbers 能直接打开），返回临时文件地址
    func workloadCSVFile(year: Int, month: Int?, report: Workload? = nil) -> URL? {
        let report = report ?? workload(year: year, month: month)
        let name = "工作量\(year)年" + (month.map { "\($0)月" } ?? "全年") + ".csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        // 带 BOM，Excel 才认得出中文
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(WorkloadCSV.make(report.people, restBalance: settings.restBalance).utf8)
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }

    nonisolated static func sortedPosts(_ p: PersonWorkload) -> [(post: String, count: Int)] {
        p.posts.map { (post: $0.key, count: $0.value) }.sorted { ($0.count, $1.post) > ($1.count, $0.post) }
    }
}
