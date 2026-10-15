import Foundation

/// 值班网站数据接口里的结构化信息（「接口字段查看」里看到的那几张表）：
/// - 每周排班表：一天一行，每个岗位一列（telemetry、rest、beforeHandover、assignments.组A……），格子里可能有好几个人
/// - 人员表：谁参加值班（onDuty）、哪几天能值遥测（telemetryWeekdays）、待休天数（unrestDays）
/// - 「固定」标记：fixedAssignments.telemetry = 1 的那天遥测是手动指定的
/// - 公告表：网站上写的排班规则
public enum SiteAPI {
    /// 一个人在网站上的设置
    public struct Person: Codable, Equatable {
        public var onDuty: Bool?
        /// 能值遥测的星期（1 = 周一 … 7 = 周日）
        public var telemetryWeekdays: Set<Int>?
        public var unrestDays: Int?
        public var category: String?

        public init(onDuty: Bool? = nil, telemetryWeekdays: Set<Int>? = nil, unrestDays: Int? = nil, category: String? = nil) {
            self.onDuty = onDuty
            self.telemetryWeekdays = telemetryWeekdays
            self.unrestDays = unrestDays
            self.category = category
        }
    }

    /// 网站标的「该休没休」：这天这个人本该休息（或在值班交接前那列），但还在上班
    public struct NoRest: Equatable, Hashable {
        public var day: DayKey
        public var name: String
        /// 「休息」或「值班交接前」
        public var column: String
    }

    public struct Result: Equatable {
        public var roster: Roster = [:]
        public var noRest: [NoRest] = []
        /// 各组负责的星（组A → 「高分03D01、高分03D02」）
        public var groupSatellites: [String: String] = [:]
        /// 手动指定（固定）遥测的日子
        public var fixedTelemetryDays: Set<DayKey> = []
        public var people: [String: Person] = [:]
        public var notices: [String] = []
        public var isEmpty: Bool { roster.isEmpty && people.isEmpty && notices.isEmpty }
        public init() {}
    }

    /// 列名 → 岗位（最后一段字段名）
    static let columnPosts: [String: String] = [
        "telemetry": "遥测", "duty": "遥测", "rest": "休息", "beforehandover": "值班交接前", "handover": "值班交接前",
        "timeoff": "调休", "leave": "请假", "businesstrip": "出差", "trip": "出差", "overtime": "加班", "dispatch": "调度",
    ]

    static func post(forColumn key: String, matcher: ShiftMatcher) -> String? {
        // 标记类的字段不是岗位
        let lower = key.lowercased()
        if lower.contains("norestflags") || lower.contains("fixedassignments") || lower.contains("flag") { return nil }
        let last = String(key.split(separator: ".").last ?? Substring(key))
        if let p = columnPosts[last.lowercased()] { return p }
        if GroupNotes.isGroup(last) { return GroupNotes.normalizeGroup(last) }
        return nil
    }

    public static func parse(_ bodies: [String], reference: DayKey, matcher: ShiftMatcher) -> Result {
        var result = Result()
        var satelliteNames: [String: String] = [:]
        let dates = DateTokenParser(reference: reference)
        for body in bodies {
            let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = text.first, first == "{" || first == "[",
                  let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { continue }
            for rows in JSONScheduleExtractor.tables(in: json) {
                parseWeekly(rows, dates: dates, matcher: matcher, into: &result)
                parsePeople(rows, into: &result)
                parseNotices(rows, into: &result)
                parseGroups(rows, into: &result, satellites: &satelliteNames)
            }
        }
        // 卫星编号换成名字（有卫星表的话）
        result.groupSatellites = result.groupSatellites.mapValues { list in
            list.components(separatedBy: "、").map { satelliteNames[$0] ?? $0 }.joined(separator: "、")
        }
        return result
    }

    /// 每周排班：有日期列，还有至少两列能对上岗位、格子里是人名
    static func parseWeekly(_ rows: [[String: String]], dates: DateTokenParser, matcher: ShiftMatcher, into result: inout Result) {
        guard let dateKey = JSONScheduleExtractor.dateKey(in: rows, dates: dates) else { return }
        let keys = Set(rows.flatMap(\.keys)).subtracting([dateKey])
        // 按字段名排好：同一天几个岗位拼起来的先后每次一样
        let columns = keys.sorted().compactMap { k in post(forColumn: k, matcher: matcher).map { (k, $0) } }
        guard columns.count >= 2 else { return }
        for row in rows {
            guard let day = row[dateKey].flatMap({ JSONScheduleExtractor.day(from: $0, dates: dates) }) else { continue }
            for (key, post) in columns {
                guard let cell = row[key] else { continue }
                for name in RosterExtractor.names(inCell: cell, matcher: matcher) {
                    RosterExtractor.add(post, for: name, on: day, to: &result.roster)
                }
            }
            if let fixed = row.first(where: { $0.key.lowercased() == "fixedassignments.telemetry" })?.value, fixed == "1" || fixed == "true" {
                result.fixedTelemetryDays.insert(day)
            }
            // noRestFlags.rest.active = 1，noRestFlags.rest.persons = 「张三、李四」
            for (flag, column) in [("rest", "休息"), ("beforehandover", "值班交接前")] {
                let prefix = "norestflags.\(flag)."
                let fields = row.filter { $0.key.lowercased().hasPrefix(prefix) }
                guard fields.contains(where: { $0.key.lowercased() == prefix + "active" && ($0.value == "1" || $0.value == "true") })
                else { continue }
                let names = fields.filter { $0.key.lowercased().hasSuffix("person") || $0.key.lowercased().hasSuffix("persons") }
                    .flatMap { RosterExtractor.names(inCell: $0.value, matcher: matcher) }
                for name in Set(names) where !result.noRest.contains(NoRest(day: day, name: name, column: column)) {
                    result.noRest.append(NoRest(day: day, name: name, column: column))
                }
            }
        }
    }

    /// 人员表：有 name 列，还有 onDuty / telemetryWeekdays / unrestDays 之一
    static func parsePeople(_ rows: [[String: String]], into result: inout Result) {
        func value(_ row: [String: String], _ name: String) -> String? {
            row.first { $0.key.split(separator: ".").last.map(String.init)?.lowercased() == name.lowercased() }?.value
        }
        guard rows.contains(where: { value($0, "telemetryWeekdays") != nil || value($0, "onDuty") != nil || value($0, "unrestDays") != nil })
        else { return }
        for row in rows {
            guard let raw = value(row, "name") else { continue }
            let name = RosterExtractor.cleanName(raw)
            guard RosterExtractor.looksLikeName(name) else { continue }
            var p = result.people[name] ?? Person()
            if let v = value(row, "onDuty") { p.onDuty = v == "1" || v.lowercased() == "true" }
            if let v = value(row, "telemetryWeekdays") {
                let days = v.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.filter { (1...7).contains($0) }
                p.telemetryWeekdays = Set(days)
            }
            if let v = value(row, "unrestDays"), let n = Int(v) { p.unrestDays = n }
            if let v = value(row, "category") { p.category = v }
            result.people[name] = p
        }
    }

    /// 公告：有 text / richText 列、内容够长的
    static func parseNotices(_ rows: [[String: String]], into result: inout Result) {
        for row in rows {
            guard let raw = row["text"] ?? row["richText"].map(HTMLText.toText) else { continue }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.count >= 12, row["hidden"] != "1", !result.notices.contains(text) { result.notices.append(text) }
        }
    }

    /// 组表（groupName + satellites）和卫星表（satelliteId + satelliteName）
    static func parseGroups(_ rows: [[String: String]], into result: inout Result, satellites: inout [String: String]) {
        for row in rows {
            if let id = row["satelliteId"], let name = row["satelliteName"], !id.isEmpty, !name.isEmpty { satellites[id] = name }
            if let group = row["groupName"], GroupNotes.isGroup(group), let list = row["satellites"], !list.isEmpty {
                result.groupSatellites[GroupNotes.normalizeGroup(group)] = list
            }
        }
    }

    /// 网站上的星期编号：1 = 周一 … 7 = 周日
    public static func siteWeekday(_ day: DayKey, calendar: Calendar) -> Int {
        let w = calendar.component(.weekday, from: day.date(calendar: calendar, hour: 12))   // 1 = 周日
        return w == 1 ? 7 : w - 1
    }
}
