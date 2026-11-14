import Foundation

/// Physical controls resolve a command; each equipped character resolves that
/// command against its own original animation set.
public enum DuelWeaponCommand: String, Codable, Sendable, CaseIterable {
    case weapon, weaponForward, weaponUp, weaponDown, weaponBack, heavy
    case kick, kickForward, kickUp, kickDown, kickBack, shadow, ranged
}

public struct DuelWeaponPoint: Equatable, Codable, Sendable {
    public var x: Double, y: Double, z: Double
    public init(x: Double = 0, y: Double = 0, z: Double = 0) { self.x = x; self.y = y; self.z = z }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer(), a = try c.decode([Double].self)
        guard a.count == 3, a.allSatisfy(\.isFinite) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid motion point")
        }
        self.init(x: a[0], y: a[1], z: a[2])
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode([x, y, z])
    }
    public func mixed(with b: Self, weight: Double) -> Self {
        .init(x: x + (b.x - x) * weight, y: y + (b.y - y) * weight, z: z + (b.z - z) * weight)
    }
}

/// Half-source-frame samples are computed after bone interpolation and forward
/// kinematics. Interpolating only integer-frame world endpoints changes arcs.
public struct DuelWeaponTracks: Equatable, Codable, Sendable {
    public let samplesPerSourceFrame: Int
    public let root, handL, handR, footL, footR: [DuelWeaponPoint]
    public let weaponBaseL, weaponTipL, weaponBaseR, weaponTipR: [DuelWeaponPoint]
    public let groundLift: [Double]

    public func sample(_ points: [DuelWeaponPoint], phase: Double) -> DuelWeaponPoint {
        guard let first = points.first else { return .init() }
        guard points.count > 1, phase.isFinite else { return first }
        let p = min(1, max(0, phase)) * Double(points.count - 1)
        let i = min(points.count - 2, Int(p))
        return points[i].mixed(with: points[i + 1], weight: p - Double(i))
    }
    public func lift(phase: Double) -> Double {
        guard let first = groundLift.first else { return 0 }
        guard groundLift.count > 1, phase.isFinite else { return first }
        let p = min(1, max(0, phase)) * Double(groundLift.count - 1)
        let i = min(groundLift.count - 2, Int(p)), w = p - Double(i)
        return groundLift[i] + (groundLift[i + 1] - groundLift[i]) * w
    }
}

public struct DuelWeaponClip: Equatable, Codable, Sendable {
    public let name: String
    public let frames: Int
    public let sha256: String
    public let bundle: String
    public let tracks: DuelWeaponTracks
    /// The export uses a documented 30 FPS preview clock. It is not evidence of
    /// recovered original combat speed or collision timing.
    public var ticks: Int { (2...2000).contains(frames) ? (frames - 1) * 2 : 2 }
    public func phase(at tick: Int) -> Double { min(1, max(0, Double(tick) / Double(ticks))) }
}

public struct DuelWeaponComboLink: Equatable, Codable, Sendable {
    public let from: String
    public let to: String
    public let sourceFrame: Int
}

public struct DuelWeaponProfile: Equatable, Codable, Sendable {
    public let id: String
    public let hero: DuelGame.Hero
    public let faction: String
    public let resourceName: String
    public let bytes: Int
    public let sha256: String
    public let bodyID: String
    public let weaponID: String
    public let activeWeaponSides: [String]
    public let roles: [String: String]
    public let clips: [DuelWeaponClip]
    public let comboLinks: [DuelWeaponComboLink]?
    public let combatRules: DuelCombatRuleProfile?
    public let panguRules: DuelPanguRules?
    /// Ordinary throws are opt-in source bindings and explicit application
    /// timing. A directional weapon command alone never invents a grapple.
    public let ordinaryThrows: DuelWeaponThrowRules?
    public init(id: String, hero: DuelGame.Hero, faction: String, resourceName: String,
                bytes: Int, sha256: String, bodyID: String, weaponID: String,
                activeWeaponSides: [String], roles: [String: String], clips: [DuelWeaponClip],
                comboLinks: [DuelWeaponComboLink]? = nil, combatRules: DuelCombatRuleProfile? = nil,
                panguRules: DuelPanguRules? = nil, ordinaryThrows: DuelWeaponThrowRules? = nil) {
        self.id = id; self.hero = hero; self.faction = faction; self.resourceName = resourceName
        self.bytes = bytes; self.sha256 = sha256; self.bodyID = bodyID; self.weaponID = weaponID
        self.activeWeaponSides = activeWeaponSides; self.roles = roles; self.clips = clips
        self.comboLinks = comboLinks; self.combatRules = combatRules
        self.panguRules = panguRules
        self.ordinaryThrows = ordinaryThrows
    }
    public var isKatana: Bool { id == "sun_katana" }
    public var isPangu: Bool { id == "liu_pangu" }
    public var title: String { isKatana ? "先锋 · 武士刀" : isPangu ? "盘古 · 双手长斧" : "军团 · 双锤" }
    public var weaponTitle: String { isKatana ? "武士刀" : isPangu ? "盘古大斧" : "双锤" }
    public func clip(named name: String) -> DuelWeaponClip? { clips.first { $0.name == name } }
    public func clip(role: String) -> DuelWeaponClip? { roles[role].flatMap { clip(named: $0) } }
    public func combo(from name: String) -> DuelWeaponComboLink? { comboLinks?.first { $0.from == name } }
    public func clip(command: DuelWeaponCommand, second: Bool = false) -> DuelWeaponClip? {
        let role = command == .weapon ? (second ? "weapon2" : "weapon1") : command.rawValue
        return clip(role: role)
    }
}

public struct DuelWeaponCatalog: Equatable, Codable, Sendable {
    public let schemaVersion: Int
    public let previewFramesPerSecond: Int
    public let sourceFramesPerSecond: Double?
    public let profiles: [DuelWeaponProfile]
    public enum ValidationError: Error { case identity, incomplete, invalidTracks }

    public func validate() throws {
        let expected: Set<String> = profiles.contains(where: \.isPangu)
            ? ["sun_katana", "liu_pangu"] : ["sun_katana", "liu_hammers"]
        guard schemaVersion == 1, previewFramesPerSecond == 30,
              profiles.count == 2,
              Set(profiles.map(\.id)) == expected,
              Set(profiles.map(\.hero)) == [.ember, .liu],
              Set(profiles.map(\.bodyID)).count == 2,
              Set(profiles.map(\.weaponID)).count == 2,
              Set(profiles.map(\.sha256)).count == 2 else { throw ValidationError.identity }
        for profile in profiles {
            guard (profile.isKatana && profile.hero == .ember) || (!profile.isKatana && profile.hero == .liu),
                  profile.bytes > 0, profile.sha256.count == 64,
                  profile.resourceName.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil,
                  Set(profile.clips.map(\.name)).count == profile.clips.count,
                  ["idle", "walkForward", "walkBackward", "guard", "jump", "hit", "knockdown", "getUp", "weapon1", "heavy", "kick"].allSatisfy({ profile.clip(role: $0) != nil }),
                  profile.roles.values.allSatisfy({ profile.clip(named: $0) != nil }),
                  !profile.activeWeaponSides.isEmpty,
                  Set(profile.activeWeaponSides).isSubset(of: ["left", "right"]),
                  Set(profile.activeWeaponSides).count == profile.activeWeaponSides.count else { throw ValidationError.incomplete }
            for clip in profile.clips {
                guard (2...2000).contains(clip.frames) else { throw ValidationError.invalidTracks }
                let n = 2 * clip.frames - 1, t = clip.tracks
                guard clip.sha256.count == 64,
                      t.samplesPerSourceFrame == 2,
                      [t.root, t.handL, t.handR, t.footL, t.footR].allSatisfy({
                          $0.count == n && $0.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
                      }), t.groundLift.count == n,
                      t.groundLift.allSatisfy({ $0.isFinite && (0...2).contains($0) }) else { throw ValidationError.invalidTracks }
                for (side, base, tip) in [("left", t.weaponBaseL, t.weaponTipL), ("right", t.weaponBaseR, t.weaponTipR)] {
                    let count = profile.activeWeaponSides.contains(side) ? n : 0
                    guard [base, tip].allSatisfy({ $0.count == count && $0.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) }) else {
                        throw ValidationError.invalidTracks
                    }
                }
            }
            for link in profile.comboLinks ?? [] {
                guard let from = profile.clip(named: link.from), let to = profile.clip(named: link.to),
                      link.from != link.to, link.sourceFrame >= 0,
                      link.sourceFrame < min(from.frames, to.frames) - 1 else { throw ValidationError.incomplete }
            }
            try profile.combatRules?.validate(for: profile)
            if profile.isPangu {
                // A target identity must arrive with its own rules and authored
                // motion bindings. The legacy two-hammer profile is never
                // upgraded by changing a title or enabling a shadow button.
                guard let pangu = profile.panguRules, profile.combatRules != nil,
                      profile.activeWeaponSides.count == 1,
                      ["panguShard", "panguTyphoon", "panguSplitter", "panguBones",
                       "panguSpear", "panguHeavenfall", "panguStormGate"].allSatisfy({
                          profile.clip(role: $0) != nil
                      }) else { throw ValidationError.incomplete }
                try pangu.validate()
            } else if profile.panguRules != nil { throw ValidationError.identity }
            if let throwRules = profile.ordinaryThrows,
               let target = profiles.first(where: { $0.hero != profile.hero }) {
                try throwRules.validate(for: profile, target: target)
            }
        }
        let throwPolicies = profiles.compactMap { $0.ordinaryThrows?.simultaneousContactPolicy }
        if let first = throwPolicies.first, throwPolicies.contains(where: { $0 != first }) {
            throw ValidationError.incomplete
        }
    }
    public func profile(for hero: DuelGame.Hero) -> DuelWeaponProfile? { profiles.first { $0.hero == hero } }
}

public struct DuelWeaponPose: Equatable, Sendable {
    public let clip: String
    public let tick: Int
    public let duration: Int
    public let groundLift: Double
    public let reaction: Bool
    public var phase: Double { min(1, max(0, Double(tick) / Double(max(1, duration)))) }
    public init(clip: String, tick: Int, duration: Int, groundLift: Double, reaction: Bool = false) {
        self.clip = clip; self.tick = tick; self.duration = duration
        self.groundLift = groundLift; self.reaction = reaction
    }
}
