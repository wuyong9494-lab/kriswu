import Foundation

/// Lobby readiness is separate from protocol support. A known identifier is
/// selectable only when this build actually loaded its authenticated profile.
struct DuelLocalRoster {
    let originalWeapons: Bool
    let identity: DuelLobbyIdentitySnapshot?
    let displayedHero: DuelGame.Hero?

    var choices: [DuelGame.Hero] {
        [.ember, .liu, .wuYong, .gale]
    }

    func isAvailable(_ hero: DuelGame.Hero) -> Bool {
        choices.contains(hero) && (!originalWeapons || identity?.intendedIdentity(for: hero) != nil)
    }

    func opponents(for hero: DuelGame.Hero) -> [DuelGame.Hero] {
        choices.filter { $0 != hero && isAvailable($0) }
    }

    func opponent(for hero: DuelGame.Hero, preferred: DuelGame.Hero) -> DuelGame.Hero? {
        let available = opponents(for: hero)
        return available.contains(preferred) ? preferred : available.first
    }

    func canStart(hero: DuelGame.Hero, opponent: DuelGame.Hero) -> Bool {
        hero != opponent && isAvailable(hero) && isAvailable(opponent) &&
            (!originalWeapons || displayedHero == hero)
    }

    func setup(hero: DuelGame.Hero, preferredOpponent: DuelGame.Hero,
               difficulty: DuelGame.Difficulty, mode: DuelGame.Mode) -> DuelSetup? {
        guard let opponent = opponent(for: hero, preferred: preferredOpponent),
              canStart(hero: hero, opponent: opponent) else { return nil }
        return DuelSetup(hero: hero, difficulty: difficulty, mode: mode,
                         originalWeapons: originalWeapons, opponentHero: opponent)
    }
}
