import Foundation

/// Derives read-only schedule evidence. Presence and actual completion are
/// never inferred from a roster or a reminder.
public enum DutyWorkbench {
    public struct Window: Equatable, Sendable {
        public let day: DayKey
        public let label: String
        public let start: Date
        public let end: Date

        public func contains(_ date: Date) -> Bool { start <= date && date < end }
    }

    public static func isStandardTelemetryPost(_ raw: String, matcher: ShiftMatcher) -> Bool {
        DutyBurdenAnalysis.usesStandardTelemetryWindow(raw, matcher: matcher)
    }

    public static func window(on day: DayKey, schedule: [DayKey: String],
                              matcher: ShiftMatcher, handover: ClockTime,
                              calendar: Calendar = .dayMath) -> Window? {
        guard (0...23).contains(handover.hour), (0...59).contains(handover.minute),
              let raw = schedule[day], isStandardTelemetryPost(raw, matcher: matcher) else { return nil }
        let next = day.adding(days: 1, calendar: calendar)
        return Window(day: day, label: matcher.displayName(raw),
                      start: day.date(calendar: calendar, hour: handover.hour, minute: handover.minute),
                      end: next.date(calendar: calendar, hour: handover.hour, minute: handover.minute))
    }

    public static func current(now: Date, schedule: [DayKey: String], matcher: ShiftMatcher,
                               handover: ClockTime, calendar: Calendar = .dayMath) -> Window? {
        guard let day = rosterDay(asOf: now, handover: handover, calendar: calendar) else { return nil }
        return window(on: day, schedule: schedule, matcher: matcher, handover: handover, calendar: calendar)
    }

    /// Assigns time to a schedule date, without asserting someone is actually present.
    public static func rosterDay(asOf date: Date, handover: ClockTime,
                                 calendar: Calendar = .dayMath) -> DayKey? {
        guard (0...23).contains(handover.hour), (0...59).contains(handover.minute) else { return nil }
        let today = DayKey(date: date, calendar: calendar)
        let starts = today.date(calendar: calendar, hour: handover.hour, minute: handover.minute)
        return date < starts ? today.adding(days: -1, calendar: calendar) : today
    }

    public static func next(atOrAfter date: Date, schedule: [DayKey: String], matcher: ShiftMatcher,
                            handover: ClockTime, calendar: Calendar = .dayMath) -> Window? {
        let day = DayKey(date: date, calendar: calendar)
        for candidate in schedule.keys.filter({ $0 >= day }).sorted() {
            if let known = window(on: candidate, schedule: schedule, matcher: matcher,
                                  handover: handover, calendar: calendar), known.start >= date {
                return known
            }
        }
        return nil
    }

    public static func changes(_ records: [RosterEdit], in window: Window, now: Date) -> [RosterEdit] {
        records.filter { $0.at <= now && window.contains($0.at) }
            .sorted {
                if $0.at != $1.at { return $0.at > $1.at }
                if $0.day != $1.day { return $0.day < $1.day }
                return $0.name < $1.name
            }
    }

    public static func confirmed(_ records: [String: Date], in window: Window, now: Date) -> [String] {
        records.filter { $0.value <= now && window.contains($0.value) }.map(\.key).sorted()
    }
}
