import Foundation

/// Source heroes keep stable string IDs. Their match records must never be
/// written under the compatibility-only classic enum carried by an entrant.
@MainActor
final class ArenaSourceProgressStore {
    static let shared = ArenaSourceProgressStore()
    struct Record: Codable {
        var matches = 0
        var wins = 0
        var kills = 0
        var damage = 0
    }
    private let defaults = UserDefaults.standard
    private let key = "arena.sourceHeroProgress.v1"
    private var records: [String: Record]
    private init() {
        records = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: Record].self, from: $0) } ?? [:]
    }
    func record(for id: String) -> Record { records[id] ?? Record() }
    func record(id: String, won: Bool, kills: Int, damage: Int) {
        var value = record(for: id)
        value.matches += 1; value.wins += won ? 1 : 0
        value.kills += max(kills, 0); value.damage += max(damage, 0)
        records[id] = value
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: key) }
    }
}
