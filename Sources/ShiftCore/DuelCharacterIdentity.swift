import Foundation

/// The four intended person/source-set bindings. These identifiers describe
/// the requested character; authenticated profiles and model bytes remain a
/// separate requirement before a lobby or match may use the character.
public enum DuelCharacterIdentity: String, CaseIterable, Sendable {
    case blackBlades = "sun_triad"
    case serpent = "liu_serpent"
    case erlang = "wuyong_erlang"
    case founder = "xuxiao_founder"

    public var hero: DuelGame.Hero {
        switch self {
        case .blackBlades: return .ember
        case .serpent: return .liu
        case .erlang: return .wuYong
        case .founder: return .gale
        }
    }

    public var sourceSetID: String {
        switch self {
        case .blackBlades: return "H17"
        case .serpent: return "D13"
        case .erlang: return "D15"
        case .founder: return "D20"
        }
    }

    /// Internal source-role metadata, not the displayed character name.
    public var roleName: String {
        switch self {
        case .blackBlades: return "黑色双刀"
        case .serpent: return "蛇王"
        case .erlang: return "二郎神"
        case .founder: return "嬴政"
        }
    }

    public var title: String { hero.name }

    public var personalHeadNode: String {
        switch self {
        case .blackBlades: return "Sun_Personal_Head"
        case .serpent: return "Liu_Personal_Head"
        case .erlang: return "WuYong_Personal_Head"
        case .founder: return "XuXiao_Personal_Head"
        }
    }

    public static func intended(for hero: DuelGame.Hero) -> Self {
        switch hero {
        case .ember: return .blackBlades
        case .liu: return .serpent
        case .wuYong: return .erlang
        case .gale: return .founder
        }
    }

    public init?(hero: DuelGame.Hero, profileID: String) {
        guard let identity = Self(rawValue: profileID), identity.hero == hero else { return nil }
        self = identity
    }

    /// Exact profile equipment identifiers, without the source Model path's
    /// Top100/ prefix. D20's two gloves are alternatives in one source slot,
    /// not permission to replace its missing actor with another set's body.
    public func matches(hero: DuelGame.Hero, profileID: String,
                        bodyID: String, weaponID: String) -> Bool {
        guard self.hero == hero, rawValue == profileID else { return false }
        switch self {
        case .blackBlades:
            return bodyID == "arm__prc_43" && weaponID == "wpn__ninjato_01_06"
        case .serpent:
            return bodyID == "arm__agl_41" && weaponID == "wpn__shuangou_01_04"
        case .erlang:
            return bodyID == "arm__agl_44" && weaponID == "wpn__agl_spear_01_01"
        case .founder:
            return bodyID == "arm__agl_49" &&
                ["wpn__imperial_gloves_01_01", "wpn__imperial_gloves_01_01a"].contains(weaponID)
        }
    }
}

public extension DuelGame.Hero {
    var characterIdentity: DuelCharacterIdentity { .intended(for: self) }
}

public extension DuelWeaponProfile {
    /// Logical identity only; callers deciding availability must also check
    /// the exact equipment, catalog rules, and independently verified assets.
    var characterIdentity: DuelCharacterIdentity? {
        DuelCharacterIdentity(hero: hero, profileID: id)
    }

    var isIntendedCharacter: Bool {
        characterIdentity?.matches(hero: hero, profileID: id, bodyID: bodyID, weaponID: weaponID) == true
    }
}
