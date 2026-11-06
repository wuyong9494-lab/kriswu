import Foundation

extension TileGame {
    /// Display identity only. Save keys, daily seed salt and room wire IDs stay stable.
    public static let displayName = "星了个星"
}

extension StarRail {
    public enum TrialRule: String, Codable, CaseIterable, Sendable {
        case compact = "N", pulse = "E", master = "M"
        public var title: String {
            switch self {
            case .compact: return "窄舱规划"
            case .pulse: return "单芯储能"
            case .master: return "大师航线"
            }
        }
        public var detail: String {
            switch self {
            case .compact: return "只有 6 格收集槽，提前拆解遮挡，留出第三张的位置。"
            case .pulse: return "只能储存 1 点能量，让消除与移层交替衔接。"
            case .master: return "6 格槽、1 点储能；移层不能超过预算，每次出发都要有目的。"
            }
        }
    }

    /// Twelve authored-board contracts. SX2 pins both the layout and contract
    /// rules; future catalogs must not silently replace these shared challenges.
    public struct Trial: Identifiable, Equatable, Sendable {
        public let stageID: Int
        public let rule: TrialRule
        public var id: String { "SX2-0\(stageID)-\(rule.rawValue)" }
        public var stage: Stage {
            var result = StarRail.stage(stageID, revision: 2)!
            result.trial = rule
            return result
        }
        public init?(stageID: Int, rule: TrialRule) {
            guard (3...6).contains(stageID) else { return nil }
            self.stageID = stageID; self.rule = rule
        }
        public static let all: [Trial] = (3...6).flatMap { id in
            TrialRule.allCases.map { Trial(stageID: id, rule: $0)! }
        }
        /// Match the versioned namespace, not arbitrary SX letters in a valid legacy code.
        public static func containsCodePrefix(_ text: String) -> Bool {
            text.range(of: "(?i)(?<![A-Z0-9-])SX[0-9]+-", options: .regularExpression) != nil
        }
        public static func decode(_ text: String) -> Trial? {
            guard text.utf8.count <= 8_192 else { return nil }
            let upper = text.uppercased()
            let pattern = "(?<![A-Z0-9-])SX2-0[3-6]-[NEM](?![A-Z0-9-])"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let codes = Set(regex.matches(in: upper, range: NSRange(upper.startIndex..., in: upper))
                .compactMap { Range($0.range, in: upper).map { String(upper[$0]) } })
            guard codes.count == 1, let code = codes.first else { return nil }
            return all.first { $0.id == code }
        }
        /// Same date and challenge on all devices, independent of local time zone.
        /// Repeats the explicit 12-contract rotation; it is not a random level generator.
        public static func daily(at date: Date) -> Trial {
            let calendar = Calendar.dayMath
            let start = DayKey(year: 2026, month: 1, day: 1).date(calendar: calendar)
            let today = calendar.startOfDay(for: date)
            let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
            let index = ((days % 12) + 12) % 12
            return Trial(stageID: 3 + index % 4, rule: TrialRule.allCases[index % 3])!
        }
        public var shareText: String {
            "来「\(TileGame.displayName)」挑战\(stage.title) · \(rule.title)！星约码 \(id)。打开值班提醒 › 小游戏 › \(TileGame.displayName)，粘贴到挑战码；同一棋盘、同一规则，比谁规划得更好。"
        }
    }

    static func archivedStage(id: Int, revision: Int, trial: TrialRule?, expeditionID: Int? = nil, journey: StarJourney.Configuration? = nil) -> Stage? {
        if let journey {
            guard trial == nil, expeditionID == nil, revision == 4, journey.isValid, id == 201 + journey.chapter else { return nil }
            return journey.stage
        }
        if let expeditionID {
            guard trial == nil, revision == 3, let expedition = Expedition(id: expeditionID), expedition.stage.id == id else { return nil }
            return expedition.stage
        }
        guard let trial else { return stage(id, revision: revision) }
        guard revision == 2 else { return nil }
        return Trial(stageID: id, rule: trial)?.stage
    }

    /// Records hold an entire winning replay, so metrics always come from one
    /// real run rather than combining the best values from different attempts.
    public struct TrialSave: Codable, Equatable, Sendable {
        public static let storageKey = "tileGame.starTrials.v1"
        public let version: Int
        public private(set) var runs: [String: Game.Archive]
        public private(set) var best: [String: Game.Archive]
        public init() { version = 1; runs = [:]; best = [:] }

        public var isValid: Bool {
            guard version == 1, runs.count <= 12, best.count <= 12 else { return false }
            func valid(_ entries: [String: Game.Archive], won: Bool) -> Bool {
                entries.allSatisfy { code, archive in
                    guard let trial = Trial.decode(code), code == trial.id,
                          let game = Game(archive: archive), game.stage == trial.stage else { return false }
                    return !won || game.status == .won
                }
            }
            return valid(runs, won: false) && valid(best, won: true)
        }
        public init?(data: Data) {
            guard data.count <= 524_288,
                  let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
            self = decoded
        }
        private enum CodingKeys: String, CodingKey { case version, runs, best }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self,forKey:.version)
            runs = try c.decode([String:Game.Archive].self,forKey:.runs)
            best = try c.decode([String:Game.Archive].self,forKey:.best)
            guard isValid else { throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"Invalid trial replay")) }
        }
        public func encoded() -> Data? { try? JSONEncoder().encode(self) }
        public func game(for trial: Trial) -> Game {
            runs[trial.id].flatMap(Game.init(archive:)) ?? Game(stage: trial.stage)
        }
        public func record(for trial: Trial) -> Game? { best[trial.id].flatMap(Game.init(archive:)) }
        public var mastered: Int {
            best.values.compactMap(Game.init(archive:)).filter { $0.stars == 3 && $0.rewinds == 0 }.count
        }
        public var completed: Int { best.count }

        @discardableResult public mutating func keep(_ game: Game) -> Bool {
            guard version == 1, let rule = game.stage.trial,
                  let trial = Trial(stageID: game.stage.id, rule: rule), game.stage == trial.stage else { return false }
            runs[trial.id] = game.archive
            if game.status == .won {
                if let previous = record(for: trial) {
                    if Self.isBetter(game, than: previous) { best[trial.id] = game.archive }
                } else { best[trial.id] = game.archive }
            }
            return true
        }
        public static func isBetter(_ candidate: Game, than previous: Game) -> Bool {
            let a = [-candidate.stars, candidate.rewinds, candidate.state.shifts, candidate.state.peak, candidate.state.overflowEnergy]
            let b = [-previous.stars, previous.rewinds, previous.state.shifts, previous.state.peak, previous.state.overflowEnergy]
            return a.lexicographicallyPrecedes(b)
        }
    }
}
