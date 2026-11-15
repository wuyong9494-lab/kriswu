import Foundation

/// Integrity-bound source intervals and model releases. BaseDamage multiplies
/// an explicit arena power. D15's separately authenticated SetHit replacement
/// is handled after that calculation in normalized health units. Every collision
/// part is a recovered capsule name; missing geometry cannot become an AABB.
public struct DuelErlangCombatRules: Codable, Equatable, Sendable {
    public typealias Ability = DuelErlangFightState.Ability
    public struct Attack: Codable, Equatable, Sendable {
        public let id: String
        public let ability: Ability
        public let role: String
        public let modelRole: String?
        public let sourceConfigurationSHA256: String
        public let sourceRecordIndex: Int
        public let startTick: Int
        public let endTick: Int
        public let parts: [String]
        public let damageKind: DuelPanguRules.DamageKind
        public let baseDamageBps: Int
        public let unblockable: Bool
        public let knocksDown: Bool
        public let impact: DuelImpactResponse
        public let hitStopTicks: Int
        public let hitTags: [String]?
        public var isSourceMeditationExplosion: Bool {
            ability == .meditate && modelRole == "erlangSummon_meditation" &&
                sourceRecordIndex == 106 &&
                sourceConfigurationSHA256 == "3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701" &&
                damageKind == .shadow && baseDamageBps == 0 && unblockable &&
                hitTags?.contains("Hit_D15_Meditation_Explosion") == true
        }
    }
    public struct Release: Codable, Equatable, Sendable {
        public let id: String
        public let ability: Ability
        public let ownerRole: String
        public let atTick: Int
        public let modelRole: String
        public let anchor: String
        public let offset: DuelWeaponPoint
        public let minimumLevel: Int
    }
    public struct Control: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case uninterrupt, blocking, throwable }
        public let role: String
        public let kind: Kind
        public let startTick: Int
        public let endTick: Int
        public let sourceConfigurationSHA256: String
        public let sourceRecordIndex: Int
    }
    public struct SwordSlot: Codable, Equatable, Sendable {
        public let slot: Int
        public let birthRole: String
        /// Original Shift converted to arena metres: [X,Y,-Z]/100.
        /// Native39421 flips only X for LEFT. Z is not multiplied by facing.
        public let offset: DuelWeaponPoint
        public let sourceRecordIndex: Int
    }
    public let schemaVersion: Int
    public let sourceVersion: String
    public let sourceSHA256: String
    public let maximumHealth: Int
    public let normalizedWeaponPower: Int
    public let normalizedUnarmedPower: Int
    public let normalizedMagicPower: Int
    public let normalizedRangedPower: Int
    public let attacks: [Attack]
    public let releases: [Release]
    public let controls: [Control]?
    public let swordSlots: [SwordSlot]?

    public init(schemaVersion: Int, sourceVersion: String, sourceSHA256: String, maximumHealth: Int,
                normalizedWeaponPower: Int, normalizedUnarmedPower: Int, normalizedMagicPower: Int,
                normalizedRangedPower: Int, attacks: [Attack], releases: [Release], controls: [Control]? = nil,
                swordSlots: [SwordSlot]? = nil) {
        self.schemaVersion = schemaVersion; self.sourceVersion = sourceVersion; self.sourceSHA256 = sourceSHA256
        self.maximumHealth = maximumHealth; self.normalizedWeaponPower = normalizedWeaponPower
        self.normalizedUnarmedPower = normalizedUnarmedPower; self.normalizedMagicPower = normalizedMagicPower
        self.normalizedRangedPower = normalizedRangedPower; self.attacks = attacks; self.releases = releases
        self.controls = controls
        self.swordSlots = swordSlots
    }
    public func contains(_ kind: Control.Kind, role: String, tick: Int) -> Bool {
        controls?.contains { $0.kind == kind && $0.role == role && ($0.startTick...$0.endTick).contains(tick) } ?? false
    }

    public func damage(for attack: Attack) -> Int {
        let power: Int
        switch attack.damageKind {
        case .weapon: power = normalizedWeaponPower
        case .unarmed: power = normalizedUnarmedPower
        case .shadow: power = normalizedMagicPower
        }
        return power * attack.baseDamageBps / 10_000
    }
    public func validate(profile: DuelWeaponProfile) throws {
        typealias Failure = DuelWeaponCatalog.ValidationError
        guard schemaVersion == 1, sourceVersion == DuelErlangFightState.sourceVersion,
              DuelFighterAssetRelease.validDigest(sourceSHA256),
              (1...1_000_000).contains(maximumHealth),
              [normalizedWeaponPower, normalizedUnarmedPower, normalizedMagicPower, normalizedRangedPower]
                .allSatisfy({ (1...1_000_000).contains($0) }),
              attacks.count <= 256, Set(attacks.map(\.id)).count == attacks.count,
              releases.count <= 128, Set(releases.map(\.id)).count == releases.count else { throw Failure.identity }
        for attack in attacks {
            guard !attack.id.isEmpty, attack.id.utf8.count <= 128,
                  DuelFighterAssetRelease.validDigest(attack.sourceConfigurationSHA256),
                  attack.sourceRecordIndex >= 0, attack.startTick >= 0,
                  attack.endTick >= attack.startTick, attack.endTick <= 36_000,
                  !attack.parts.isEmpty, attack.parts.count <= 32,
                  Set(attack.parts).count == attack.parts.count,
                  (0...100_000).contains(attack.baseDamageBps),
                  attack.impact.isValid, (0...60).contains(attack.hitStopTicks) else { throw Failure.incomplete }
            guard (attack.hitTags?.count ?? 0) <= 64,
                  attack.hitTags?.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }) ?? true else { throw Failure.incomplete }
            let parts: Set<String>, duration: Int
            if let modelRole = attack.modelRole {
                guard let model = profile.summonTrack(role: modelRole) else { throw Failure.incomplete }
                parts = Set((model.collisionEdges ?? []).map(\.id) + (model.hurtCapsules ?? []).map(\.id))
                duration = model.sourceLastActiveTick
            } else {
                guard let clip = profile.clip(role: attack.role) else { throw Failure.incomplete }
                parts = Set((clip.tracks.collisionEdges ?? []).map(\.id) + (clip.tracks.hurtCapsules ?? []).map(\.id))
                duration = clip.ticks
            }
            guard attack.endTick <= duration, Set(attack.parts).isSubset(of: parts) else { throw Failure.invalidTracks }
        }
        for release in releases {
            guard !release.id.isEmpty, release.id.utf8.count <= 128,
                  let owner = profile.clip(role: release.ownerRole),
                  (0...owner.ticks).contains(release.atTick),
                  profile.summonTrack(role: release.modelRole) != nil,
                  ["root", "pelvis", "pelvis.x", "pelvis.xy", "head.x", "enemy.pelvis.x", "centerOfMass", "hand_l", "hand_r", "foot_l", "foot_r"].contains(release.anchor),
                  [release.offset.x, release.offset.y, release.offset.z].allSatisfy({ $0.isFinite && abs($0) <= 100 }),
                  (2...8).contains(release.minimumLevel) else { throw Failure.incomplete }
        }
        guard (controls?.count ?? 0) <= 512 else { throw Failure.incomplete }
        for control in controls ?? [] {
            guard let clip = profile.clip(role: control.role), control.startTick >= 0,
                  control.endTick >= control.startTick, control.endTick <= clip.ticks,
                  control.sourceRecordIndex >= 0,
                  DuelFighterAssetRelease.validDigest(control.sourceConfigurationSHA256) else { throw Failure.incomplete }
        }
        if let swordSlots {
            let offsets: [DuelWeaponPoint] = [
                .init(x: -0.75, y: 1.70, z: 0.50), .init(x: -0.75, y: 1.70, z: -0.50),
                .init(x: -0.75, y: 1.95, z: 0.50), .init(x: -0.75, y: 1.95, z: -0.50),
                .init(x: -0.75, y: 2.05, z: 0.15), .init(x: -0.75, y: 2.25, z: 0.15)]
            guard swordSlots.count == 6, Set(swordSlots.map(\.slot)) == Set(1...6),
                  DuelErlangSwordMotion.matches(profile: profile) else { throw Failure.incomplete }
            for slot in swordSlots {
                guard slot.birthRole == "erlangSummon_swordBirth\(slot.slot)",
                      slot.sourceRecordIndex == 109 + slot.slot,
                      slot.offset == offsets[slot.slot - 1],
                      profile.summonTrack(role: slot.birthRole)?.sourceEndEventTick == 92 else { throw Failure.incomplete }
            }
        }
    }
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.int(schemaVersion); try writer.string(sourceVersion); try writer.string(sourceSHA256)
        try writer.int(maximumHealth); try writer.int(normalizedWeaponPower); try writer.int(normalizedUnarmedPower)
        try writer.int(normalizedMagicPower); try writer.int(normalizedRangedPower)
        try writer.array(attacks, limit: 256) { writer, a in
            try writer.string(a.id); try writer.string(a.ability.rawValue); try writer.string(a.role)
            try writer.optional(a.modelRole) { try $0.string($1) }; try writer.string(a.sourceConfigurationSHA256)
            try writer.int(a.sourceRecordIndex); try writer.int(a.startTick); try writer.int(a.endTick)
            try writer.array(a.parts, limit: 32) { try $0.string($1) }; try writer.string(a.damageKind.rawValue)
            try writer.int(a.baseDamageBps); try writer.bool(a.unblockable); try writer.bool(a.knocksDown)
            try writer.int(a.impact.distanceMillimeters); try writer.int(a.impact.durationTicks)
            try writer.int(a.impact.launchVelocityMillimetersPerTick); try writer.int(a.impact.gravityMillimetersPerTickSquared)
            try writer.int(a.hitStopTicks)
            try writer.optional(a.hitTags) { writer, tags in
                try writer.array(tags, limit: 64) { try $0.string($1) }
            }
        }
        try writer.array(releases, limit: 128) { writer, r in
            try writer.string(r.id); try writer.string(r.ability.rawValue); try writer.string(r.ownerRole)
            try writer.int(r.atTick); try writer.string(r.modelRole); try writer.string(r.anchor)
            try writer.point(r.offset); try writer.int(r.minimumLevel)
        }
        try writer.optional(controls) { writer, controls in
            try writer.array(controls, limit: 512) { writer, c in
                try writer.string(c.role); try writer.string(c.kind.rawValue)
                try writer.int(c.startTick); try writer.int(c.endTick)
                try writer.string(c.sourceConfigurationSHA256); try writer.int(c.sourceRecordIndex)
            }
        }
        try writer.optional(swordSlots) { writer, slots in
            try writer.array(slots, limit: 6) { writer, slot in
                try writer.int(slot.slot); try writer.string(slot.birthRole); try writer.point(slot.offset)
                try writer.int(slot.sourceRecordIndex)
            }
        }
    }
}

/// Model lifetimes and per-source-interval contact latches survive draw skips.
/// Renderers observe these records; they cannot create contacts or advance time.
public struct DuelErlangSpatialState: Equatable, Sendable {
    public struct Model: Equatable, Sendable {
        public let id: UInt64
        public let owner: Int
        public let ability: DuelErlangFightState.Ability
        public var role: String
        public let bornAt: Int
        public var stateStartedAt: Int
        public let swordSlot: Int?
        public var direction: Int
        public var origin: DuelWeaponPoint
        public var previousOrigin: DuelWeaponPoint
        public var swordMotion: DuelErlangSwordMotion?
        public var acceptedAttackIDs: [String] = []
        public init(id: UInt64, owner: Int, ability: DuelErlangFightState.Ability, role: String,
                    bornAt: Int, direction: Int, origin: DuelWeaponPoint, stateStartedAt: Int? = nil,
                    swordSlot: Int? = nil, acceptedAttackIDs: [String] = [],
                    previousOrigin: DuelWeaponPoint? = nil, swordMotion: DuelErlangSwordMotion? = nil) {
            self.id = id; self.owner = owner; self.ability = ability; self.role = role; self.bornAt = bornAt
            self.stateStartedAt = stateStartedAt ?? bornAt; self.swordSlot = swordSlot
            self.direction = direction; self.origin = origin; self.acceptedAttackIDs = acceptedAttackIDs
            self.previousOrigin = previousOrigin ?? origin; self.swordMotion = swordMotion
        }
        public func motionTick(at liveTick: Int) -> Int { max(0, liveTick - stateStartedAt) }
    }
    public var liveTick = 0
    public var models: [Model] = []
    public var bodyContactIDs: [[String]] = [[], []]
    public var releasedModelIDs: [[String]] = [[], []]
    public var dogDebuffTicks = [0, 0]
    private var nextID: UInt64 = 0
    public init() {}
    mutating func beginCast(owner: Int) { bodyContactIDs[owner] = []; releasedModelIDs[owner] = [] }
    @discardableResult
    mutating func spawn(owner: Int, ability: DuelErlangFightState.Ability, role: String,
                        direction: Int, origin: DuelWeaponPoint, swordSlot: Int? = nil) -> UInt64? {
        guard models.count < 64 else { return nil }
        nextID &+= 1
        models.append(.init(id: nextID, owner: owner, ability: ability, role: role,
                            bornAt: liveTick, direction: direction, origin: origin, swordSlot: swordSlot))
        return nextID
    }
    mutating func transition(id: UInt64, role: String, direction: Int? = nil, origin: DuelWeaponPoint? = nil) {
        guard let index = models.firstIndex(where: { $0.id == id }) else { return }
        models[index].role = role; models[index].stateStartedAt = liveTick
        if let direction { models[index].direction = direction }
        if let origin { models[index].origin = origin }
        models[index].acceptedAttackIDs = []
    }
    mutating func advance() {
        liveTick += 1; dogDebuffTicks = dogDebuffTicks.map { max(0, $0 - 1) }
        for i in models.indices { models[i].previousOrigin = models[i].origin }
    }
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.int(liveTick); try writer.u64(nextID)
        try writer.array(models, limit: 64) { writer, model in
            try writer.u64(model.id); try writer.int(model.owner); try writer.string(model.ability.rawValue)
            try writer.string(model.role); try writer.int(model.bornAt); try writer.int(model.stateStartedAt)
            try writer.optional(model.swordSlot) { try $0.int($1) }; try writer.int(model.direction)
            try writer.point(model.origin); try writer.point(model.previousOrigin)
            try writer.optional(model.swordMotion) { writer, motion in try motion.appendReplayState(to: &writer) }
            try writer.array(model.acceptedAttackIDs, limit: 256) { try $0.string($1) }
        }
        for values in [bodyContactIDs, releasedModelIDs] {
            try writer.array(values, limit: 2) { writer, ids in try writer.array(ids, limit: 256) { try $0.string($1) } }
        }
        try writer.array(dogDebuffTicks, limit: 2) { try $0.int($1) }
    }
}
