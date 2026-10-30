import UIKit

/// Assigned textures for every released hero. Decode once before combat and reuse
/// the existing bounded particle pool; no file reads occur in event callbacks.
enum ArenaEffectAssets {
    enum Style: String, CaseIterable {
        case spark, smoke, slash, muzzle, magic, flame, fire, circle, twirl, heal, star, dirt, trace

        var file: String {
            switch self {
            case .spark: return "vendor_spark_01.png"
            case .smoke: return "vendor_smoke_01.png"
            default: return "vendor_effect_" + rawValue + ".png"
            }
        }
    }

    struct Profile {
        let attack: Style
        let special: Style
        let trail: Style
    }

    static func profile(for hero: Brawler) -> Profile {
        switch hero {
        case .knight: return Profile(attack: .slash, special: .star, trail: .slash)
        case .ranger: return Profile(attack: .muzzle, special: .trace, trail: .trace)
        case .barbarian: return Profile(attack: .slash, special: .dirt, trail: .slash)
        case .mage: return Profile(attack: .flame, special: .fire, trail: .flame)
        case .assassin: return Profile(attack: .trace, special: .slash, trail: .trace)
        case .guardian: return Profile(attack: .slash, special: .circle, trail: .slash)
        case .necromancer: return Profile(attack: .magic, special: .magic, trail: .magic)
        case .shade: return Profile(attack: .magic, special: .twirl, trail: .trace)
        case .summoner: return Profile(attack: .magic, special: .circle, trail: .magic)
        case .swordsman: return Profile(attack: .slash, special: .slash, trail: .slash)
        case .brewer: return Profile(attack: .smoke, special: .dirt, trail: .circle)
        case .scholar: return Profile(attack: .heal, special: .heal, trail: .heal)
        case .darter: return Profile(attack: .trace, special: .star, trail: .trace)
        }
    }

    static func style(for gadget: Gadget?) -> Style {
        switch gadget {
        case .sprint?, .roll?: return .dirt
        case .potion?: return .heal
        case .ward?, .shockwave?: return .circle
        case .reload?: return .star
        case .frost?: return .magic
        case .vanish?: return .smoke
        case .blink?: return .twirl
        case nil: return .spark
        }
    }

    @MainActor private static let textures: [Style: UIImage] = {
        var result: [Style: UIImage] = [:]
        for style in Style.allCases {
            let file = style.file as NSString
            if let url = Bundle.main.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension),
               let image = UIImage(contentsOfFile: url.path) { result[style] = image }
        }
        return result
    }()

    @MainActor static func prepare() { _ = textures }
    @MainActor static func image(_ style: Style) -> UIImage? { textures[style] }
}
