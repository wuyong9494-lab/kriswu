import Foundation

extension DuelPanguRules.Ability {
    public var title: String {
        switch self {
        case .shard: return "创世之石"
        case .typhoon: return "原初风暴"
        case .splitter: return "劈开天际"
        case .bones: return "大地之骨"
        case .spear: return "远古猎矛"
        case .heavenfall: return "天坠"
        case .stormGate: return "风暴之门"
        }
    }
    var motionRole: String {
        switch self {
        case .shard: return "panguShard"
        case .typhoon: return "panguTyphoon"
        case .splitter: return "panguSplitter"
        case .bones: return "panguBones"
        case .spear: return "panguSpear"
        case .heavenfall: return "panguHeavenfall"
        case .stormGate: return "panguStormGate"
        }
    }
}

/// Authoritative space occupied by released Pangu attacks. This is separate
/// from animation and the renderer: drawing twice cannot deal damage twice.
struct DuelPanguSpatialState: Equatable, Sendable {
    typealias Ability = DuelPanguRules.Ability
    typealias Attack = DuelPanguState.Attack
    struct Control: Equatable, Sendable {
        var stunUntil = 0
        var petrifyUntil = 0
        var petrifySourceID: UInt64 = 0
        var pinUntil = 0
        var airUntil = 0
        var airHeight = 0
        var pendingAirHoldTicks = 0
        var dreadUntil = 0
        var damageTakenBonusBps = 0
        var outgoingReductionBps = 0
        func locked(at frame: Int) -> Bool {
            max(stunUntil, max(petrifyUntil, pinUntil)) >= frame && frame > 0
        }
        func airHeld(at frame: Int) -> Bool { airUntil >= frame && frame > 0 }
        func takenMultiplier(at frame: Int) -> Int {
            frame <= dreadUntil ? 10_000 + damageTakenBonusBps : 10_000
        }
        func outgoingMultiplier(at frame: Int) -> Int {
            frame <= dreadUntil ? 10_000 - outgoingReductionBps : 10_000
        }
    }
    struct Lift: Equatable, Sendable {
        let startHeight: Int
        let targetHeight: Int
        let duration: Int
        var age = 0
        var fallingSpeed = 0
        var phaseStartedTick: Int
        var height: Int
        mutating func step() -> Int {
            if fallingSpeed > 0 { height = max(0, height - fallingSpeed) }
            else {
                age = min(duration, age + 1)
                height = startHeight + (targetHeight - startHeight) * age / max(1, duration)
            }
            return height
        }
    }
    struct Volume: Equatable, Sendable {
        let owner: Int
        let attack: Attack
        let originX: Int
        let originY: Int
        let direction: Int
        let expiresAt: Int
        var x: Int
        var travelled = 0
        var spent = false

        var projectileCenterY: Int {
            originY + (attack.hitboxBottomMillimeters + attack.hitboxTopMillimeters) / 2
        }
        var projectileHalfHeight: Int {
            max(attack.radiusMillimeters, (attack.hitboxTopMillimeters - attack.hitboxBottomMillimeters + 1) / 2)
        }
        /// Shared by collision and its read-only presentation projection.
        /// Every coordinate is an authoritative world millimetre.
        func currentBounds(fighter: DuelGame.Fighter) -> DuelGame.Box {
            if attack.delivery == .projectile || attack.delivery == .windBlade {
                return .init(minX: x - attack.radiusMillimeters, maxX: x + attack.radiusMillimeters,
                    minY: projectileCenterY - projectileHalfHeight, maxY: projectileCenterY + projectileHalfHeight)
            }
            let followsCaster = attack.delivery == .melee
            let anchorX = followsCaster ? fighter.x : originX
            let anchorY = followsCaster ? fighter.y : 0
            let radial = attack.delivery == .landingShock
            let far = anchorX + direction * attack.rangeMillimeters
            return .init(minX: radial ? anchorX - attack.rangeMillimeters : min(anchorX, far),
                         maxX: radial ? anchorX + attack.rangeMillimeters : max(anchorX, far),
                         minY: anchorY + attack.hitboxBottomMillimeters,
                         maxY: anchorY + attack.hitboxTopMillimeters)
        }
    }
    struct Hit: Equatable, Sendable {
        let owner: Int
        let attack: Attack
        let point: DuelWeaponPoint
        let direction: Int
        let blocked: Bool
    }
    struct DeferredEffect: Equatable, Sendable {
        let owner: Int
        let effect: DuelPanguState.Effect
    }
    var tick = 0
    var controls = [Control(), Control()]
    var lifts: [Lift?] = [nil, nil]
    var volumes: [Volume] = []
    var deferred: [DeferredEffect] = []
    var deferredSlams: [Attack?] = [nil, nil]
    var speedRemainders = [0, 0]
    var lastAirborne = [false, false]
    var jumpEligible = [false, false]
    var hitSequence: UInt64 = 0

    mutating func nextHitID() -> UInt64 {
        // A bounded match cannot approach this limit; wrapping would allow a
        // previously consumed hit ID to become fresh, so saturate instead.
        if hitSequence < UInt64.max { hitSequence += 1 }
        return hitSequence
    }
    mutating func enqueue(_ effects: [DuelPanguState.Effect], owner: Int) {
        deferred.append(contentsOf: effects.map { .init(owner: owner, effect: $0) })
    }
    mutating func spawn(_ attack: Attack, owner: Int, fighter: DuelGame.Fighter,
                        activeTicks: Int, frame: Int) {
        let projectile = attack.delivery == .projectile || attack.delivery == .windBlade
        let lifetime = projectile ? (attack.rangeMillimeters + max(1, attack.projectileSpeedMillimetersPerTick) - 1) /
            max(1, attack.projectileSpeedMillimetersPerTick) + 1 : max(1, activeTicks)
        volumes.append(.init(owner: owner, attack: attack, originX: fighter.x,
            originY: fighter.y, direction: fighter.facing, expiresAt: frame + lifetime,
            x: fighter.x))
    }

    /// Projectile sweeps use the defender's current translating frame. A fast
    /// spear cannot tunnel through a torso, and a moving torso is not tested
    /// solely at its endpoint. Ground volumes retain their release location.
    mutating func contacts(frame: Int, fighters: [DuelGame.Fighter], hurts: [DuelGame.Box],
                           previousX: [Int], previousHurtY: [Int]) -> [Hit] {
        var result: [Hit] = []
        for index in volumes.indices {
            var volume = volumes[index]
            guard !volume.spent, frame <= volume.expiresAt else { continue }
            let attack = volume.attack, owner = volume.owner, target = 1 - owner
            let hurt = hurts[target], defender = fighters[target]
            let projectile = attack.delivery == .projectile || attack.delivery == .windBlade
            var hit = false, contactX = fighters[target].x
            var contactY = (hurt.minY + hurt.maxY) / 2
            if projectile {
                let previous = volume.x
                let delta = min(max(0, attack.rangeMillimeters - volume.travelled),
                                attack.projectileSpeedMillimetersPerTick)
                volume.x += volume.direction * delta; volume.travelled += delta
                let middleY = volume.projectileCenterY
                let halfHeight = volume.projectileHalfHeight
                let expanded = DuelGame.Box(minX: hurt.minX - attack.radiusMillimeters,
                    maxX: hurt.maxX + attack.radiusMillimeters,
                    minY: hurt.minY - halfHeight, maxY: hurt.maxY + halfHeight)
                let from = DuelWeaponPoint(x: Double(previous + fighters[target].x - previousX[target]) / 1000,
                    y: Double(middleY + hurt.minY - previousHurtY[target]) / 1000)
                let to = DuelWeaponPoint(x: Double(volume.x) / 1000, y: Double(middleY) / 1000)
                hit = DuelWeaponFight.segment(from, to, intersects: expanded, radius: 0)
                contactX = min(hurt.maxX, max(hurt.minX, volume.x))
                contactY = min(hurt.maxY, max(hurt.minY, middleY))
                if volume.travelled >= attack.rangeMillimeters { volume.spent = true }
            } else {
                hit = volume.currentBounds(fighter: fighters[owner]).overlaps(hurt)
            }
            if hit && defender.invulnerable == 0 {
                volume.spent = true
                // Airborne bodies cannot retreat-guard a spear or rock.
                let blocked = defender.guarding && defender.y == 0 && !controls[target].airHeld(at: frame)
                result.append(.init(owner: owner, attack: attack,
                    point: .init(x: Double(contactX) / 1000, y: Double(contactY) / 1000, z: 0.08),
                    direction: volume.direction, blocked: blocked))
            }
            volumes[index] = volume
        }
        volumes.removeAll { $0.spent || frame >= $0.expiresAt }
        return result
    }

    mutating func cancelMelee(owner: Int) {
        volumes.removeAll { $0.owner == owner && $0.attack.delivery == .melee }
        cancelUnreleasedAttacks(owner: owner)
        speedRemainders[owner] = 0
    }
    mutating func cancelUnreleasedAttacks(owner: Int) {
        deferred.removeAll { effect in
            guard effect.owner == owner else { return false }
            if case .attack = effect.effect { return true }
            return false
        }
        deferredSlams[owner] = nil
    }
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.int(tick)
        try writer.array(controls, limit: 2) { w, c in
            for value in [c.stunUntil, c.petrifyUntil, c.pinUntil, c.airUntil, c.airHeight, c.pendingAirHoldTicks,
                          c.dreadUntil, c.damageTakenBonusBps, c.outgoingReductionBps] { try w.int(value) }
            try w.u64(c.petrifySourceID)
        }
        try writer.array(lifts, limit: 2) { w, lift in
            try w.optional(lift) { w, l in
                for value in [l.startHeight, l.targetHeight, l.duration, l.age, l.fallingSpeed, l.phaseStartedTick, l.height] { try w.int(value) }
            }
        }
        try writer.array(volumes) { w, v in
            try w.int(v.owner); try v.attack.appendReplayState(to: &w)
            for value in [v.originX, v.originY, v.direction, v.expiresAt, v.x, v.travelled] { try w.int(value) }
            try w.bool(v.spent)
        }
        try writer.array(deferred) { w, event in
            try w.int(event.owner); try event.effect.appendReplayState(to: &w)
        }
        try writer.array(deferredSlams, limit: 2) { w, attack in
            try w.optional(attack) { w, a in try a.appendReplayState(to: &w) }
        }
        try writer.array(speedRemainders, limit: 2) { try $0.int($1) }
        try writer.array(lastAirborne, limit: 2) { try $0.bool($1) }
        try writer.array(jumpEligible, limit: 2) { try $0.bool($1) }
        try writer.u64(hitSequence)
    }
}
