/// The balanced three-hero matchup used by the released Twin Gates quick entry.
/// The historical type name remains compatible with diagnostic capture scripts.
public enum ArenaQualitySample {
    public static let heroes: [Brawler] = [.ranger, .barbarian, .mage]

    public static func selected(_ candidate: Brawler) -> Brawler {
        heroes.contains(candidate) ? candidate : .ranger
    }

    /// Each side gets the same three mechanics; the selected hero occupies the local seat.
    public static func lineup(selected candidate: Brawler) -> [Brawler] {
        let hero = selected(candidate)
        let team = [hero] + heroes.filter { $0 != hero }
        return team + team
    }
}
