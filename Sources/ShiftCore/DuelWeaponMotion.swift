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
public struct DuelWeaponCollisionEdge: Equatable, Codable, Sendable {
    public let id: String
    public let side: String
    public let radiusMillimeters: Int
    public let base: [DuelWeaponPoint]
    public let tip: [DuelWeaponPoint]
    public init(id: String, side: String, radiusMillimeters: Int,
                base: [DuelWeaponPoint], tip: [DuelWeaponPoint]) {
        self.id = id; self.side = side; self.radiusMillimeters = radiusMillimeters
        self.base = base; self.tip = tip
    }
}

public struct DuelWeaponHurtCapsule: Equatable, Codable, Sendable {
    public enum Defense: String, Codable, Sendable { case head, body }
    public let id: String
    public let radiusMillimeters: Int
    public let defense: Defense
    public let base: [DuelWeaponPoint]
    public let tip: [DuelWeaponPoint]
    public init(id: String, radiusMillimeters: Int, defense: Defense,
                base: [DuelWeaponPoint], tip: [DuelWeaponPoint]) {
        self.id = id; self.radiusMillimeters = radiusMillimeters; self.defense = defense
        self.base = base; self.tip = tip
    }
}

public struct DuelWeaponTracks: Equatable, Codable, Sendable {
    public let samplesPerSourceFrame: Int
    public let root, handL, handR, footL, footR: [DuelWeaponPoint]
    public let weaponBaseL, weaponTipL, weaponBaseR, weaponTipR: [DuelWeaponPoint]
    public let groundLift: [Double]
    /// Source BonesData capsules, including handles distinct from blade edges.
    /// Nil retains the legacy exported endpoint interpretation.
    public let collisionEdges: [DuelWeaponCollisionEdge]?
    public let hurtCapsules: [DuelWeaponHurtCapsule]?
    /// Original bone-mass weighted centre in the same local metre basis as
    /// the other FK tracks. It is not the pelvis or the actor's arena origin.
    /// Nil is retained only for the older catalog's coordinate adapter.
    public let centerOfMass: [DuelWeaponPoint]?
    /// The original pelvis node origin after half-frame bone interpolation
    /// and FK, in the same local metre basis as hand/foot tracks. This is an
    /// absolute pose landmark, not root displacement or a mass-weighted centre.
    public let pelvis: [DuelWeaponPoint]?
    public init(samplesPerSourceFrame: Int, root: [DuelWeaponPoint], handL: [DuelWeaponPoint],
                handR: [DuelWeaponPoint], footL: [DuelWeaponPoint], footR: [DuelWeaponPoint],
                weaponBaseL: [DuelWeaponPoint], weaponTipL: [DuelWeaponPoint],
                weaponBaseR: [DuelWeaponPoint], weaponTipR: [DuelWeaponPoint], groundLift: [Double],
                collisionEdges: [DuelWeaponCollisionEdge]? = nil,
                hurtCapsules: [DuelWeaponHurtCapsule]? = nil,
                centerOfMass: [DuelWeaponPoint]? = nil,
                pelvis: [DuelWeaponPoint]? = nil) {
        self.samplesPerSourceFrame = samplesPerSourceFrame; self.root = root
        self.handL = handL; self.handR = handR; self.footL = footL; self.footR = footR
        self.weaponBaseL = weaponBaseL; self.weaponTipL = weaponTipL
        self.weaponBaseR = weaponBaseR; self.weaponTipR = weaponTipR; self.groundLift = groundLift
        self.collisionEdges = collisionEdges
        self.hurtCapsules = hurtCapsules
        self.centerOfMass = centerOfMass
        self.pelvis = pelvis
    }

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
    /// Explicit authoritative duration from a bound combat/source profile.
    /// Sampling/export FPS remains independent of this playback duration.
    public let playbackTicks: Int?
    public init(name: String, frames: Int, sha256: String, bundle: String,
                tracks: DuelWeaponTracks, playbackTicks: Int? = nil) {
        self.name = name; self.frames = frames; self.sha256 = sha256; self.bundle = bundle
        self.tracks = tracks; self.playbackTicks = playbackTicks
    }
    /// The export uses a documented 30 FPS preview clock. It is not evidence of
    /// recovered original combat speed or collision timing.
    public var ticks: Int { playbackTicks ?? ((2...2000).contains(frames) ? (frames - 1) * 2 : 2) }
    public func phase(at tick: Int) -> Double { min(1, max(0, Double(tick) / Double(ticks))) }
    public func tick(atSourceFrame frame: Int) -> Int {
        min(ticks, max(0, frame) * ticks / max(1, frames - 1))
    }
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
    public let triadRules: DuelTriadRules?
    public let summonTracks: [DuelSummonMotionTrack]?
    /// Ordinary throws are opt-in source bindings and explicit application
    /// timing. A directional weapon command alone never invents a grapple.
    public let ordinaryThrows: DuelWeaponThrowRules?
    public init(id: String, hero: DuelGame.Hero, faction: String, resourceName: String,
                bytes: Int, sha256: String, bodyID: String, weaponID: String,
                activeWeaponSides: [String], roles: [String: String], clips: [DuelWeaponClip],
                comboLinks: [DuelWeaponComboLink]? = nil, combatRules: DuelCombatRuleProfile? = nil,
                panguRules: DuelPanguRules? = nil, ordinaryThrows: DuelWeaponThrowRules? = nil,
                triadRules: DuelTriadRules? = nil, summonTracks: [DuelSummonMotionTrack]? = nil) {
        self.id = id; self.hero = hero; self.faction = faction; self.resourceName = resourceName
        self.bytes = bytes; self.sha256 = sha256; self.bodyID = bodyID; self.weaponID = weaponID
        self.activeWeaponSides = activeWeaponSides; self.roles = roles; self.clips = clips
        self.comboLinks = comboLinks; self.combatRules = combatRules
        self.panguRules = panguRules
        self.triadRules = triadRules
        self.summonTracks = summonTracks
        self.ordinaryThrows = ordinaryThrows
    }
    public var isKatana: Bool { id == "sun_katana" }
    public var isTriad: Bool { id == "sun_triad" }
    public var isPangu: Bool { id == "liu_pangu" }
    public var title: String { isTriad ? "死亡森林三魄 · 忍刀双刃" : isKatana ? "先锋 · 武士刀" : isPangu ? "盘古 · 双手长斧" : "军团 · 双锤" }
    public var weaponTitle: String { isTriad ? "黑色双刀" : isKatana ? "武士刀" : isPangu ? "盘古大斧" : "双锤" }
    public func clip(named name: String) -> DuelWeaponClip? { clips.first { $0.name == name } }
    public func summonTrack(role: String) -> DuelSummonMotionTrack? { summonTracks?.first { $0.role == role } }
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
        guard schemaVersion == 1, previewFramesPerSecond == 30,
              profiles.count == 2,
              Set(profiles.map(\.id)).count == 2,
              profiles.allSatisfy({ profile in
                  guard let weapon = DuelMultiplayerSelection.Weapon(rawValue: profile.id) else { return false }
                  return DuelMultiplayerSelection.Choice(hero: profile.hero, weapon: weapon).isValid
              }),
              Set(profiles.map(\.hero)) == [.ember, .liu],
              Set(profiles.map(\.bodyID)).count == 2,
              Set(profiles.map(\.weaponID)).count == 2,
              Set(profiles.map(\.sha256)).count == 2 else { throw ValidationError.identity }
        for profile in profiles {
            guard profile.bytes > 0, profile.sha256.count == 64,
                  profile.resourceName.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil,
                  Set(profile.clips.map(\.name)).count == profile.clips.count,
                  ["idle", "walkForward", "walkBackward", "guard", "jump", "hit", "knockdown", "getUp", "weapon1", "heavy", "kick"].allSatisfy({ profile.clip(role: $0) != nil }),
                  profile.roles.values.allSatisfy({ profile.clip(named: $0) != nil }),
                  !profile.activeWeaponSides.isEmpty,
                  Set(profile.activeWeaponSides).isSubset(of: ["left", "right"]),
                  Set(profile.activeWeaponSides).count == profile.activeWeaponSides.count else { throw ValidationError.incomplete }
            for clip in profile.clips {
                guard (2...2000).contains(clip.frames),
                      clip.playbackTicks.map({ (1...36_000).contains($0) }) ?? true else { throw ValidationError.invalidTracks }
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
                if let edges = t.collisionEdges {
                    guard (1...8).contains(edges.count), Set(edges.map(\.id)).count == edges.count,
                          edges.allSatisfy({ edge in
                              !edge.id.isEmpty && edge.id.utf8.count <= 128 &&
                              profile.activeWeaponSides.contains(edge.side) && (1...2000).contains(edge.radiusMillimeters) &&
                              [edge.base, edge.tip].allSatisfy { points in
                                  points.count == n && points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
                              }
                          }) else { throw ValidationError.invalidTracks }
                }
                if let capsules = t.hurtCapsules {
                    guard (1...32).contains(capsules.count), Set(capsules.map(\.id)).count == capsules.count,
                          capsules.allSatisfy({ capsule in
                              !capsule.id.isEmpty && capsule.id.utf8.count <= 128 &&
                              (1...2000).contains(capsule.radiusMillimeters) &&
                              [capsule.base, capsule.tip].allSatisfy { points in
                                  points.count == n && points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
                              }
                          }) else { throw ValidationError.invalidTracks }
                }
                if let centers = t.centerOfMass {
                    guard centers.count == n,
                          centers.allSatisfy({ point in
                              [point.x, point.y, point.z].allSatisfy { $0.isFinite && (-100...100).contains($0) }
                          }) else { throw ValidationError.invalidTracks }
                }
                if let pelvis = t.pelvis {
                    guard pelvis.count == n,
                          pelvis.allSatisfy({ point in
                              [point.x, point.y, point.z].allSatisfy { $0.isFinite && (-100...100).contains($0) }
                          }) else { throw ValidationError.invalidTracks }
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
            if profile.isTriad {
                guard let triad = profile.triadRules, profile.combatRules != nil,
                      Set(profile.activeWeaponSides) == Set(["left", "right"]),
                      DuelTriadRules.Ability.allCases.filter({ $0.soul == nil }).allSatisfy({
                          profile.clip(role: $0.motionRole) != nil
                      }) else {
                    throw ValidationError.incomplete
                }
                try triad.validate()
                if triad.runtime != nil {
                    guard DuelTriadState.OwnerAnimation.allCases.allSatisfy({ animation in
                        profile.clip(role: animation.role)?.frames == animation.sourceFrameCount
                    }) else { throw ValidationError.incomplete }
                    let roles = Set(DuelTriadRules.SummonMove.allCases.map(\.role) +
                        [DuelTriadRules.SoulAnimation.ninjatoActiveStart.role, DuelTriadRules.SoulAnimation.ninjatoActiveEnd.role])
                    guard Set(profile.summonTracks?.map(\.role) ?? []) == roles else { throw ValidationError.incomplete }
                }
            } else if profile.triadRules != nil { throw ValidationError.identity }
            if let tracks = profile.summonTracks {
                guard profile.isTriad, (1...32).contains(tracks.count),
                      Set(tracks.map(\.role)).count == tracks.count else { throw ValidationError.identity }
                for track in tracks { try track.validate() }
            }
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
