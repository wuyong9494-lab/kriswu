import Foundation

/// Device-local first-attempt observations. No inferred global player rate.
/// A first pick starts an attempt; a later retry cannot replace its outcome.
public struct TileDailyAttempts: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case pending, wonWithoutTools, lost, usedTools, abandoned
    }
    public struct Entry: Codable, Equatable, Sendable {
        public var attempts: Int
        public var firstOutcome: Outcome
        var firstID: String
        var lastID: String
    }
    public private(set) var entries: [String: Entry] = [:]
    public init() {}

    public mutating func begin(day: DayKey, attemptID: String) {
        let key = TileGame.dailyPlanningRecordKey(day)
        if var entry = entries[key] {
            guard entry.lastID != attemptID else { return }
            if entry.firstOutcome == .pending { entry.firstOutcome = .abandoned }
            entry.attempts += 1
            entry.lastID = attemptID
            entries[key] = entry
        } else {
            entries[key] = Entry(attempts: 1, firstOutcome: .pending, firstID: attemptID, lastID: attemptID)
        }
        if entries.count > 60 {
            let keep = Set(entries.keys.sorted().suffix(60))
            entries = entries.filter { keep.contains($0.key) }
        }
    }

    public mutating func observe(day: DayKey, attemptID: String, won: Bool, lost: Bool, toolsUsed: Bool, abandoned: Bool = false) {
        let key = TileGame.dailyPlanningRecordKey(day)
        guard var entry = entries[key], entry.firstID == attemptID, entry.firstOutcome == .pending else { return }
        if toolsUsed { entry.firstOutcome = .usedTools }
        else if lost { entry.firstOutcome = .lost }
        else if won { entry.firstOutcome = .wonWithoutTools }
        else if abandoned { entry.firstOutcome = .abandoned }
        entries[key] = entry
    }
}
