import Foundation

/// A versioned fixture, not a new game mode. Real rules, damage, collision and AI.
public enum ArenaBenchmark {
    public static let id = "canyon-3v3-v1"
    public static let seed: UInt64 = 0xA3E12026
    public static let cycleSteps = 1800
    public static func game() -> ArenaGame {
        let roles: [Brawler] = [.ranger, .knight, .mage, .ranger, .knight, .mage]
        let entrants = roles.enumerated().map { index, role in
            ArenaGame.Entrant(name: "压测\(index + 1)", brawler: role, isBot: true,
                              team: index < 3 ? 0 : 1, level: 7,
                              loadout: ArenaLoadout.basic(role, level: 7))
        }
        return ArenaGame(mode: .zone, entrants: entrants, seed: seed, map: .canyon)
    }
}
