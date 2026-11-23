import Foundation

/// Read-only summary of documented schedules. Missing rows are never treated as attendance,
/// an off day, a day shift, or a continuation of a consecutive duty streak.
public enum DutyBurdenAnalysis {
    public static let windowDays = 30

    public struct Report: Equatable, Sendable {
        /// Inclusive, ending yesterday. This is an analysis of scheduled entries, not clock-in evidence.
        public let start: DayKey
        public let end: DayKey
        /// Dates with at least one nonblank, published schedule row.
        public let rosterDates: [DayKey]
        /// Dates marked off by the App's public holiday arrangement (including linked days off).
        public let holidayDates: [DayKey]
        public let holidayCalendarYearsWithoutData: [Int]
        public let members: [Member]
    }

    public struct Member: Equatable, Identifiable, Sendable {
        public var id: String { name }
        public let name: String
        /// Dates with an interpretable published entry after applying the regular workload classification.
        public let recordedDates: [DayKey]
        /// Missing, tentative, contradictory or unclassifiable dates.
        public let unknownDates: [DayKey]
        public let nightDates: [DayKey]
        /// Recorded dates that establish a post but not whether it is a night shift.
        public let nightUnknownDates: [DayKey]
        public let holidayWorkDates: [DayKey]
        public let dutyDates: [DayKey]
        /// Evidence for every tied longest streak within the window, ordered chronologically.
        public let longestDutyStreaks: [[DayKey]]
        public let longestDutyDays: Int?
        public let confirmedNightDays: Int?
        public let confirmedHolidayWorkDays: Int?
        public let nightCountIsMinimum: Bool
        public let dutyCountIsMinimum: Bool
        public let holidayCountIsMinimum: Bool

        public var isCoverageComplete: Bool { unknownDates.isEmpty }
    }

    public static func analyze(roster: Roster, today: DayKey, matcher: ShiftMatcher,
                               publishedDays: Set<DayKey>? = nil, names: [String]? = nil) -> Report {
        let calendar = Calendar.dayMath
        let days = (1...windowDays).reversed().map { today.adding(days: -$0, calendar: calendar) }
        let start = days[0]
        let end = days[days.count - 1]
        let window = Set(days)
        let eligible = publishedDays.map { window.intersection($0) } ?? window
        let rosterDates = Set(roster.values.flatMap { history in
            history.compactMap { day, value in
                eligible.contains(day) && !matcher.posts(value).isEmpty ? day : nil
            }
        }).sorted()
        let holidayDates = days.filter(ChinaHolidays.isHoliday)
        let holidaySet = Set(holidayDates)
        let missingHolidayYears = Set(days.map(\.year)).subtracting(ChinaHolidays.knownYears).sorted()
        let targets = Set(names ?? roster.compactMap { pair in
            pair.value.keys.contains(where: window.contains) ? pair.key : nil
        }).sorted()
        let members = targets.map { name in
            // Stay on the same classification rules as the existing records detail view. Older records may
            // inform that classifier, but never enter the 30-day summary themselves. No lookahead.
            let history = (roster[name] ?? [:]).filter { day, value in
                day <= end && (publishedDays?.contains(day) ?? true) && !matcher.posts(value).isEmpty
            }
            let explanation = WorkloadCounter.explainedByMonth(name: name, history: history, days: days,
                                                             matcher: matcher, calendar: calendar)
            var recorded: [DayKey] = [], unknown: [DayKey] = [], nights: [DayKey] = []
            var nightUnknown: [DayKey] = [], holidayWork: [DayKey] = [], duties: [DayKey] = []
            var streaks: [[DayKey]] = [], running: [DayKey] = []
            var knownNightCount = 0

            func closeStreak() {
                guard !running.isEmpty else { return }
                let longest = streaks.first?.count ?? 0
                if running.count >= longest {
                    if running.count > longest { streaks.removeAll() }
                    streaks.append(running)
                }
                running.removeAll()
            }

            for day in days {
                guard let raw = history[day], let official = explanation[day]?.kind,
                      let parts = documentedParts(raw, matcher: matcher) else {
                    unknown.append(day)
                    closeStreak()
                    continue
                }

                let hasDuty = parts.contains { $0.part == .duty }
                let hasPost = parts.contains { $0.part == .post }
                let isDocumentedDuty = official == .duty && hasDuty
                let isDocumentedWork = isDocumentedDuty || (official == .regular && hasPost)
                let isDocumentedTrip = official == .trip && parts.contains { $0.part == .trip }
                let isDocumentedOff = !parts.contains(where: { $0.part.isWork })
                    && [.off, .holiday, .attendance, .dutyRest, .unassigned].contains(official)

                // In particular, a compensatory rest day can appear as attendance in existing totals,
                // but can neither increase holiday workload nor continue this documented-duty streak.
                guard isDocumentedWork || isDocumentedTrip || isDocumentedOff else {
                    unknown.append(day)
                    closeStreak()
                    continue
                }
                recorded.append(day)
                if isDocumentedDuty {
                    duties.append(day)
                    running.append(day)
                } else {
                    closeStreak()
                }
                // Match the ordinary report's on-duty / regular classifications, not attendance or trip.
                if isDocumentedWork && holidaySet.contains(day) { holidayWork.append(day) }
                if isDocumentedWork {
                    let working = parts.filter { $0.part == .duty || $0.part == .post }
                    if working.contains(where: { $0.shift == .night }) {
                        knownNightCount += 1
                        nights.append(day)
                    } else if working.allSatisfy({ $0.shift == .day }) {
                        knownNightCount += 1
                    } else {
                        nightUnknown.append(day)
                    }
                } else if isDocumentedTrip {
                    // A trip confirms work, not the time of day.
                    nightUnknown.append(day)
                }
            }
            closeStreak()
            let knownHolidays = recorded.contains(where: holidaySet.contains)
            let holidayCountAvailable = knownHolidays || (holidayDates.isEmpty && missingHolidayYears.isEmpty)
            let nightCountAvailable = knownNightCount > 0 || (unknown.isEmpty && nightUnknown.isEmpty)
            return Member(name: name, recordedDates: recorded, unknownDates: unknown,
                          nightDates: nights, nightUnknownDates: nightUnknown, holidayWorkDates: holidayWork,
                          dutyDates: duties, longestDutyStreaks: streaks,
                          longestDutyDays: recorded.isEmpty ? nil : (streaks.first?.count ?? 0),
                          confirmedNightDays: nightCountAvailable ? nights.count : nil,
                          confirmedHolidayWorkDays: holidayCountAvailable ? holidayWork.count : nil,
                          nightCountIsMinimum: !unknown.isEmpty || !nightUnknown.isEmpty,
                          dutyCountIsMinimum: !unknown.isEmpty || duties.first == start || duties.last == end,
                          holidayCountIsMinimum: !missingHolidayYears.isEmpty || unknown.contains(where: holidaySet.contains))
        }
        return Report(start: start, end: end, rosterDates: rosterDates,
                      holidayDates: holidayDates, holidayCalendarYearsWithoutData: missingHolidayYears,
                      members: members)
    }

    private enum ShiftMarker: Equatable { case day, night }
    private struct DocumentedPart { let part: DayRules.Part; let shift: ShiftMarker? }

    private static func documentedParts(_ raw: String, matcher: ShiftMatcher) -> [DocumentedPart]? {
        let posts = matcher.posts(raw)
        guard !posts.isEmpty else { return nil }
        var result: [DocumentedPart] = []
        for post in posts {
            let key = ShiftMatcher.normalize(post)
            let incomplete = ["未知", "待定", "暂定", "待确认", "未确认", "待排", "缺失", "未同步", "取消", "不排", "无数据"]
            guard !key.isEmpty, !["-", "—", "?", "？", "na", "n/a", "null", "无"].contains(key),
                  !incomplete.contains(where: key.contains) else { return nil }

            let marker = explicitShiftMarker(post, matcher: matcher)
            let display = matcher.displayName(post)
            let part: DayRules.Part
            if WorkloadCounter.isIgnored(display) || display == WorkloadCounter.handoverRest {
                part = .handover
            } else if display.contains("调休") || display.contains("补休") {
                part = .compLeave
            } else if ["请假", "休假", "病假", "年假", "事假", "婚假", "产假"].contains(where: display.contains) {
                part = .leave
            } else if display.contains("休息") {
                part = .rest
            } else {
                part = DayRules.part(display, matcher: matcher)
                // DayRules treats any unrecognized text as a regular post for existing statistics.
                // This report instead requires a recognized post or an explicit time-of-day marker.
                if part == .post, marker == nil, !matcher.isStrictMatch(post) { return nil }
            }
            result.append(DocumentedPart(part: part, shift: marker))
        }
        if result.contains(where: { $0.part.isWork }),
           result.contains(where: { [.rest, .compLeave, .leave].contains($0.part) }) {
            return nil // Conflicting records; not evidence for the streak or shift count.
        }
        return result
    }

    private static func explicitShiftMarker(_ raw: String, matcher: ShiftMatcher) -> ShiftMarker? {
        let key = ShiftMatcher.normalize(raw.folding(options: .widthInsensitive, locale: Locale(identifier: "en_US_POSIX")))
        let exactTypes = matcher.types.filter { type in
            ShiftMatcher.normalize(type.name) == key || type.codes.contains { ShiftMatcher.normalize($0) == key }
        }
        let exactIDs = Set(exactTypes.map(\.id))
        if exactIDs.count > 1 { return nil }
        if exactIDs == ["night"] { return .night }
        if exactIDs == ["day"] || exactIDs == ["middle"] { return .day }
        if exactIDs.isEmpty, ["夜", "夜班", "nightshift", "overnight", "遥测夜班", "夜班遥测", "值班夜班",
                              "夜班值班", "遥测(夜班)", "值班(夜班)"].contains(key) {
            return .night
        }
        if exactIDs.isEmpty, ["白", "白班", "日班", "早班", "中班", "day", "dayshift", "遥测(白班)",
                              "遥测(日班)", "值班(白班)"].contains(key) {
            return .day
        }
        return nil
    }
}
