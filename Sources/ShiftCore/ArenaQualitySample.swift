/// The focused playable slice. Existing heroes and modes remain available to legacy callers.
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
