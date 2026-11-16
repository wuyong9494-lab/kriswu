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
    /// Original left/right toe node FK landmarks. These are distinct from the
    /// foot tracks and are required for Imperial Spear's source paired choice.
    /// Older fighters may omit them; no foot substitution is made.
    public let toeL, toeR: [DuelWeaponPoint]?
    /// Original head node FK in the same local metre basis. D15 beam models
    /// align to this node; a pelvis or fixed-height fallback is not equivalent.
    public let head: [DuelWeaponPoint]?
    public init(samplesPerSourceFrame: Int, root: [DuelWeaponPoint], handL: [DuelWeaponPoint],
                handR: [DuelWeaponPoint], footL: [DuelWeaponPoint], footR: [DuelWeaponPoint],
                weaponBaseL: [DuelWeaponPoint], weaponTipL: [DuelWeaponPoint],
                weaponBaseR: [DuelWeaponPoint], weaponTipR: [DuelWeaponPoint], groundLift: [Double],
                collisionEdges: [DuelWeaponCollisionEdge]? = nil,
                hurtCapsules: [DuelWeaponHurtCapsule]? = nil,
                centerOfMass: [DuelWeaponPoint]? = nil,
                pelvis: [DuelWeaponPoint]? = nil,
                toeL: [DuelWeaponPoint]? = nil,
                toeR: [DuelWeaponPoint]? = nil,
                head: [DuelWeaponPoint]? = nil) {
        self.samplesPerSourceFrame = samplesPerSourceFrame; self.root = root
        self.handL = handL; self.handR = handR; self.footL = footL; self.footR = footR
        self.weaponBaseL = weaponBaseL; self.weaponTipL = weaponTipL
        self.weaponBaseR = weaponBaseR; self.weaponTipR = weaponTipR; self.groundLift = groundLift
        self.collisionEdges = collisionEdges
        self.hurtCapsules = hurtCapsules
        self.centerOfMass = centerOfMass
        self.pelvis = pelvis
        self.toeL = toeL; self.toeR = toeR
        self.head = head
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
    /// Native AnimationEnd threshold, which may precede the last exported
    /// transition sample. It does not shorten the FK interpolation timeline.
    public let sourceEndEventTick: Int?
    public init(name: String, frames: Int, sha256: String, bundle: String,
                tracks: DuelWeaponTracks, playbackTicks: Int? = nil,
                sourceEndEventTick: Int? = nil) {
        self.name = name; self.frames = frames; self.sha256 = sha256; self.bundle = bundle
        self.tracks = tracks; self.playbackTicks = playbackTicks
        self.sourceEndEventTick = sourceEndEventTick
    }
    /// The export uses a documented 30 FPS preview clock. It is not evidence of
    /// recovered original combat speed or collision timing.
    public var ticks: Int { playbackTicks ?? ((2...2000).contains(frames) ? (frames - 1) * 2 : 2) }
    public func phase(at tick: Int) -> Double {
        guard ticks > 0 else { return 0 }
        return min(1, max(0, Double(tick) / Double(ticks)))
    }
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
    public let erlangRules: DuelErlangCombatRules?
    public let serpentBinding: DuelSerpentCombatBinding?
    public let summonTracks: [DuelSummonMotionTrack]?
    /// Ordinary throws are opt-in source bindings and explicit application
    /// timing. A directional weapon command alone never invents a grapple.
    public let ordinaryThrows: DuelWeaponThrowRules?
    public init(id: String, hero: DuelGame.Hero, faction: String, resourceName: String,
                bytes: Int, sha256: String, bodyID: String, weaponID: String,
                activeWeaponSides: [String], roles: [String: String], clips: [DuelWeaponClip],
                comboLinks: [DuelWeaponComboLink]? = nil, combatRules: DuelCombatRuleProfile? = nil,
                panguRules: DuelPanguRules? = nil, ordinaryThrows: DuelWeaponThrowRules? = nil,
                triadRules: DuelTriadRules? = nil, erlangRules: DuelErlangCombatRules? = nil, summonTracks: [DuelSummonMotionTrack]? = nil,
                serpentBinding: DuelSerpentCombatBinding? = nil) {
        self.id = id; self.hero = hero; self.faction = faction; self.resourceName = resourceName
        self.bytes = bytes; self.sha256 = sha256; self.bodyID = bodyID; self.weaponID = weaponID
        self.activeWeaponSides = activeWeaponSides; self.roles = roles; self.clips = clips
        self.comboLinks = comboLinks; self.combatRules = combatRules
        self.panguRules = panguRules
        self.triadRules = triadRules
        self.erlangRules = erlangRules
        self.serpentBinding = serpentBinding
        self.summonTracks = summonTracks
        self.ordinaryThrows = ordinaryThrows
    }
    public var isKatana: Bool { id == "sun_katana" }
    public var isTriad: Bool { id == "sun_triad" }
    public var isSerpent: Bool { id == "liu_serpent" && hero == .liu }
    public var isPangu: Bool { id == "liu_pangu" }
    public var isErlang: Bool { id == "wuyong_erlang" && hero == .wuYong }
    public var title: String { isSerpent ? "蛇王 · 毒牙双钩" : isErlang ? "二郎神 · 天律长枪" : isTriad ? "死亡森林三魄 · 忍刀双刃" : isKatana ? "先锋 · 武士刀" : isPangu ? "盘古 · 双手长斧" : "军团 · 双锤" }
    public var weaponTitle: String { isSerpent ? "毒牙双钩" : isErlang ? "天律长枪" : isTriad ? "黑色双刀" : isKatana ? "武士刀" : isPangu ? "盘古大斧" : "双锤" }
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
    public init(schemaVersion: Int, previewFramesPerSecond: Int, sourceFramesPerSecond: Double? = nil,
                profiles: [DuelWeaponProfile]) {
        self.schemaVersion = schemaVersion; self.previewFramesPerSecond = previewFramesPerSecond
        self.sourceFramesPerSecond = sourceFramesPerSecond; self.profiles = profiles
    }
    public enum ValidationError: Error { case identity, incomplete, invalidTracks }

    public func validate() throws {
        guard schemaVersion == 1, previewFramesPerSecond == 30,
              profiles.count == 2,
              Set(profiles.map(\.id)).count == 2,
              profiles.allSatisfy({ profile in
                  if profile.isSerpent { return profile.combatRules != nil && profile.serpentBinding != nil }
                  if profile.isErlang { return profile.combatRules != nil && profile.erlangRules != nil }
                  guard let weapon = DuelMultiplayerSelection.Weapon(rawValue: profile.id) else { return false }
                  return DuelMultiplayerSelection.Choice(hero: profile.hero, weapon: weapon).isValid
              }),
              Set(profiles.map(\.hero)).count == 2,
              Set(profiles.map(\.hero)).isSubset(of: [.ember, .liu, .wuYong]),
              Set(profiles.map(\.bodyID)).count == 2,
              Set(profiles.map(\.weaponID)).count == 2,
              Set(profiles.map(\.sha256)).count == 2 else { throw ValidationError.identity }
        if profiles.contains(where: \.isSerpent) {
            guard profiles.allSatisfy({ $0.clips.allSatisfy { clip in
                clip.tracks.pelvis?.count == 2 * clip.frames - 1 &&
                clip.tracks.centerOfMass?.count == 2 * clip.frames - 1
            } }) else { throw ValidationError.invalidTracks }
        }
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
                let sampledMotion = (2...2000).contains(clip.frames) &&
                    (clip.playbackTicks.map({ (1...36_000).contains($0) }) ?? true)
                // D15's original Transform_Out crops staff_idle to its first
                // sample and emits AnimationEnd at tick zero. This narrowly
                // authenticated transition must not fabricate a second frame.
                guard sampledMotion || DuelErlangTransformOutMotion.matches(clip: clip, profile: profile),
                      clip.sourceEndEventTick.map({ (0...clip.ticks).contains($0) }) ?? true else { throw ValidationError.invalidTracks }
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
                              (profile.activeWeaponSides.contains(edge.side) || (profile.isErlang && ["left", "right"].contains(edge.side))) && (1...2000).contains(edge.radiusMillimeters) &&
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
                for landmark in [t.toeL, t.toeR, t.head].compactMap({ $0 }) {
                    guard landmark.count == n,
                          landmark.allSatisfy({ point in
                              [point.x, point.y, point.z].allSatisfy { $0.isFinite && (-100...100).contains($0) }
                          }) else { throw ValidationError.invalidTracks }
                }
            }
            let comboLinks = profile.comboLinks ?? []
            guard comboLinks.count <= 128,
                  Set(comboLinks.map(\.from)).count == comboLinks.count else {
                throw ValidationError.incomplete
            }
            let nextCombo = Dictionary(uniqueKeysWithValues: comboLinks.map { ($0.from, $0.to) })
            for link in comboLinks {
                guard let from = profile.clip(named: link.from), let to = profile.clip(named: link.to),
                      link.from != link.to, link.sourceFrame >= 0,
                      link.sourceFrame < min(from.frames, to.frames) - 1 else { throw ValidationError.incomplete }
                var visited = Set<String>(), name = link.from
                while let next = nextCombo[name] {
                    guard visited.insert(name).inserted else { throw ValidationError.incomplete }
                    name = next
                }
            }
            if DuelSourceStunMotion.declaresBinding(profile), !DuelSourceStunMotion.matches(profile: profile) {
                throw ValidationError.incomplete
            }
            if let transition = profile.clip(role: DuelErlangTransformOutMotion.role),
               !DuelErlangTransformOutMotion.matches(clip: transition, profile: profile) {
                throw ValidationError.incomplete
            }
            try profile.combatRules?.validate(for: profile)
            if profile.isSerpent {
                guard let binding = profile.serpentBinding else { throw ValidationError.incomplete }
                try binding.validate(profile: profile)
            } else if profile.serpentBinding != nil { throw ValidationError.identity }
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
            if profile.isErlang {
                guard let rules = profile.erlangRules,
                      ["erlangMeditationStart", "erlangMeditationLoop", "erlangMeditationEnd",
                       "erlangTransform", "erlangAvatarIdle", "erlangStep", "erlangAxe", "erlangEye",
                       "erlangEarthshaker", "erlangJudgment", "erlangHound"].allSatisfy({ profile.clip(role: $0) != nil }) else {
                    throw ValidationError.incomplete
                }
                try rules.validate(profile: profile)
            } else if profile.erlangRules != nil { throw ValidationError.identity }
            if let tracks = profile.summonTracks {
                guard profile.isTriad || profile.isErlang, (1...32).contains(tracks.count),
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
    /// Authoritative D15 pelvis-local scale. This value also drives the
    /// corresponding collision/FK sample, including the previous sweep pose.
    public let pelvisScale: Float
    /// Offset applied by the native pose sampler, in original centimetres.
    /// A FloorOffset event may already have changed the next sample's value.
    public let pelvisSourceYOffset: Int
    public var phase: Double { min(1, max(0, Double(tick) / Double(max(1, duration)))) }
    public init(clip: String, tick: Int, duration: Int, groundLift: Double, reaction: Bool = false,
                pelvisScale: Float = 1, pelvisSourceYOffset: Int = 0) {
        self.clip = clip; self.tick = tick; self.duration = duration
        self.groundLift = groundLift; self.reaction = reaction
        self.pelvisScale = pelvisScale
        self.pelvisSourceYOffset = pelvisSourceYOffset
    }
}
