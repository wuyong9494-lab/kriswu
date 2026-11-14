import Foundation

/// Released H17 attacks have their own lifetime and contact budget. A pose or
/// particle can be drawn repeatedly without advancing this authoritative space.
struct DuelTriadSpatialState: Equatable, Sendable {
    /// Source soul triggers create independent models. Keep the appearance
    /// transform so their later strikes cannot follow a moving owner.
    struct Summon: Equatable, Sendable {
        let id: UInt64
        let owner: Int
        let soul: DuelTriadRules.Soul
        let origin: DuelTriadState.Origin
        let bornAt: Int
        var expiresAt: Int
        let x: Int
        let y: Int
        let z: Int
        let direction: Int
        let sourceMove: DuelTriadRules.SummonMove?
        var sourceAnimation: DuelTriadRules.SoulAnimation?
        var motionBeganAt: Int
        var lastSampleTick: Int
        var motionBaseX: Int = 0
        var motionRole: String? { sourceAnimation?.role ?? sourceMove?.role }
        func worldX(at tick: Int, profile: DuelWeaponProfile) -> Int {
            let offset = motionRole.flatMap { profile.summonTrack(role: $0) }?.offsetX(at: tick - motionBeganAt) ?? 0
            return x + motionBaseX + direction * offset
        }
    }
    struct Volume: Equatable, Sendable {
        let owner: Int
        let attack: DuelTriadState.Attack
        let originX: Int
        let originY: Int
        let direction: Int
        let releasedAt: Int
        let expiresAt: Int
        var x: Int
        var travelled = 0
        var spent = false
        var authoredBounds: DuelGame.Box? = nil

        var moves: Bool { attack.delivery != .roots && attack.delivery != .soulMelee }
        var centerY: Int { originY + (attack.hitboxBottomMillimeters + attack.hitboxTopMillimeters) / 2 }
        var halfHeight: Int { max(attack.radiusMillimeters, (attack.hitboxTopMillimeters - attack.hitboxBottomMillimeters + 1) / 2) }
        var bounds: DuelGame.Box {
            if let authoredBounds { return authoredBounds }
            if attack.delivery == .roots || moves {
                return .init(minX: x - attack.radiusMillimeters, maxX: x + attack.radiusMillimeters,
                    minY: originY + attack.hitboxBottomMillimeters, maxY: originY + attack.hitboxTopMillimeters)
            }
            let end = originX + direction * attack.rangeMillimeters
            return .init(minX: min(originX, end), maxX: max(originX, end),
                minY: originY + attack.hitboxBottomMillimeters, maxY: originY + attack.hitboxTopMillimeters)
        }
        mutating func setAuthoredBounds(_ capsules: [DuelWeaponCapsule]) {
            guard !capsules.isEmpty else { return }
            authoredBounds = .init(
                minX: Int((capsules.map { min($0.a.x, $0.b.x) - $0.radius }.min()! * 1000).rounded(.down)),
                maxX: Int((capsules.map { max($0.a.x, $0.b.x) + $0.radius }.max()! * 1000).rounded(.up)),
                minY: Int((capsules.map { min($0.a.y, $0.b.y) - $0.radius }.min()! * 1000).rounded(.down)),
                maxY: Int((capsules.map { max($0.a.y, $0.b.y) + $0.radius }.max()! * 1000).rounded(.up)))
        }
    }
    struct Control: Equatable, Sendable {
        var rootUntil = 0
        var rootSourceID: UInt64 = 0
        var rootOwner: Int? = nil
        var stunUntil = 0
        func rooted(at tick: Int) -> Bool { tick > 0 && rootUntil >= tick }
        func locked(at tick: Int) -> Bool { rooted(at: tick) || (tick > 0 && stunUntil >= tick) }
    }
    struct Hit: Equatable, Sendable {
        let owner: Int
        let attack: DuelTriadState.Attack
        let point: DuelWeaponPoint
        let direction: Int
        let blocked: Bool
    }
    struct Deferred: Equatable, Sendable {
        let owner: Int
        let effect: DuelTriadState.Effect
    }
    var tick = 0
    var controls = [Control(), Control()]
    var volumes: [Volume] = []
    var summons: [Summon] = []
    var deferred: [Deferred] = []
    var hitSequence: UInt64 = 0
    var rejectedVolumes = 0

    mutating func nextHitID() -> UInt64 {
        if hitSequence < UInt64.max { hitSequence += 1 }
        return hitSequence
    }
    mutating func resetRound() {
        // State-level duplicate fences survive rounds. Space cannot recycle
        // their event IDs when the next round starts at live tick zero.
        let sequence = hitSequence
        self = Self(); hitSequence = sequence
    }
    mutating func enqueue(_ effects: [DuelTriadState.Effect], owner: Int) {
        deferred.append(contentsOf: effects.map { .init(owner: owner, effect: $0) })
    }
    mutating func appear(_ soul: DuelTriadRules.Soul, origin: DuelTriadState.Origin,
                         id: UInt64, owner: Int, fighter: DuelGame.Fighter, duration: Int) {
        guard summons.count < DuelTriadState.maximumPendingEvents,
              !summons.contains(where: { $0.id == id && $0.owner == owner }) else { return }
        summons.append(.init(id: id, owner: owner, soul: soul, origin: origin,
            bornAt: tick, expiresAt: tick + max(1, duration), x: fighter.x,
            y: fighter.y, z: 0, direction: fighter.facing, sourceMove: nil,
            sourceAnimation: nil, motionBeganAt: tick, lastSampleTick: max(1, duration - 1)))
    }
    mutating func appear(_ value: DuelTriadState.SoulAppearance, owner: Int, fighters: [DuelGame.Fighter]) {
        guard summons.count < DuelTriadState.maximumPendingEvents,
              !summons.contains(where: { $0.id == value.summonID && $0.owner == owner }) else { return }
        let caster = fighters[owner], target = fighters[1 - owner]
        let toward = target.x >= caster.x ? 1 : -1
        let facing = value.reverseFacing ? -toward : toward
        let anchor = value.anchor == .owner ? caster : target
        // These authenticated exports use centimeters and an outer actor
        // scale of 0.92. Keep that application's conversion rational/exact.
        func millimeters(_ units: Int) -> Int { units * 92 / 10 }
        summons.append(.init(id: value.summonID, owner: owner, soul: value.soul, origin: value.origin,
            bornAt: tick, expiresAt: tick + value.lifetimeTicks,
            x: anchor.x + millimeters(value.offsetXSourceUnits) * facing,
            y: value.inheritsAnchorHeight ? anchor.y : 0, z: millimeters(value.offsetZSourceUnits),
            direction: facing, sourceMove: value.move, sourceAnimation: nil, motionBeganAt: tick,
            lastSampleTick: value.move.lastSampleTick))
    }
    mutating func changeMotion(id: UInt64, owner: Int, animation: DuelTriadRules.SoulAnimation,
                               profile: DuelWeaponProfile) {
        guard let index = summons.firstIndex(where: { $0.id == id && $0.owner == owner }) else { return }
        let value = summons[index]
        summons[index].motionBaseX = value.worldX(at: tick, profile: profile) - value.x
        summons[index].sourceAnimation = animation; summons[index].motionBeganAt = tick
        summons[index].lastSampleTick = animation.lastSampleTick
        summons[index].expiresAt = tick + animation.endEventTick + 1
    }
    @discardableResult
    mutating func spawn(_ attack: DuelTriadState.Attack, owner: Int,
                        fighters: [DuelGame.Fighter], profile: DuelWeaponProfile) -> Volume? {
        guard volumes.count < DuelTriadState.maximumPendingEvents else {
            rejectedVolumes += 1; return nil
        }
        let caster = fighters[owner], target = fighters[1 - owner]
        let root = attack.delivery == .roots
        let sourceModel = Self.modelTrack(for: attack.delivery, profile: profile)
        // The root appears at the release-time target position. An opponent
        // who leaves that position can evade it; it never follows a new target.
        guard !root || sourceModel != nil || abs(target.x - caster.x) <= attack.rangeMillimeters else { return nil }
        let soul = attack.summonID.flatMap { id in summons.first { $0.id == id && $0.owner == owner } }
        let direction = soul?.direction ?? caster.facing
        // Source Align only writes X. Model-local Y/Z remain in its sampled
        // capsules; an airborne owner must not lift this independent model.
        // The fighter's X already is its root-motion-adjusted pelvis centre.
        let origin = root ? target.x - (sourceModel == nil ? 0 : direction * 500) :
            soul?.worldX(at: tick, profile: profile) ?? caster.x
        var volume = Volume(owner: owner, attack: attack, originX: origin,
            originY: root || sourceModel != nil ? 0 : soul?.y ?? caster.y, direction: direction,
            releasedAt: tick, expiresAt: tick + max(1, attack.activeTicks), x: origin)
        if let sourceModel, let parts = sourceModel.attackParts?["primary"] {
            volume.setAuthoredBounds(sourceModel.capsules(parts: parts, tick: 0,
                x: origin, y: 0, z: 0, direction: direction))
        }
        volumes.append(volume)
        return volume
    }
    private static func modelTrack(for delivery: DuelTriadRules.Delivery,
                                   profile: DuelWeaponProfile) -> DuelSummonMotionTrack? {
        let key: String
        switch delivery { case .roots: key = "roots"; case .mistWave: key = "mistWave"; default: return nil }
        return profile.triadRules?.runtime?.modelTracks?[key]
    }
    mutating func contacts(fighters: [DuelGame.Fighter], profiles: [DuelWeaponProfile], hurts: [DuelGame.Box],
                           previousX: [Int], previousHurtY: [Int],
                           hurtBefore: [[(id: String, capsule: DuelWeaponCapsule)]?],
                           hurtAfter: [[(id: String, capsule: DuelWeaponCapsule)]?]) -> [Hit] {
        var hits: [Hit] = []
        for i in volumes.indices {
            var volume = volumes[i]
            guard !volume.spent, tick < volume.expiresAt else { continue }
            let target = 1 - volume.owner, hurt = hurts[target], defender = fighters[target]
            var touching: Bool, sourceContact: DuelWeaponPoint? = nil
            let summon = volume.attack.summonID.flatMap { id in summons.first { $0.id == id && $0.owner == volume.owner } }
            let track = summon?.motionRole.flatMap { profiles[volume.owner].summonTrack(role: $0) }
            var sourceShapes: (before: [DuelWeaponCapsule], after: [DuelWeaponCapsule])?
            if let model = Self.modelTrack(for: volume.attack.delivery, profile: profiles[volume.owner]),
               let parts = model.attackParts?["primary"] {
                let age = max(0, tick - volume.releasedAt)
                // Collision cannot sweep backwards into an inactive interval.
                let prior = age >= volume.attack.activationDelayTicks ?
                    max(volume.attack.activationDelayTicks, age - 1) : max(0, age - 1)
                func shapes(_ sample: Int) -> [DuelWeaponCapsule] {
                    model.capsules(parts: parts, tick: sample,
                        x: volume.originX + model.offsetX(at: sample) * volume.direction,
                        y: volume.originY, z: 0, direction: volume.direction)
                }
                volume.x = volume.originX + model.offsetX(at: age) * volume.direction
                sourceShapes = (shapes(prior), shapes(age))
            } else if let summon, let track, let stage = volume.attack.summonStage,
               let parts = track.attackParts?[stage.rawValue] {
                let nowTick = max(0, tick - summon.motionBeganAt)
                let oldTick = max(0, max(volume.releasedAt, tick - 1) - summon.motionBeganAt)
                func shapes(_ age: Int) -> [DuelWeaponCapsule] {
                    track.capsules(parts: parts, tick: age,
                        x: summon.x + summon.motionBaseX + track.offsetX(at: age) * summon.direction,
                        y: summon.y, z: summon.z, direction: summon.direction)
                }
                volume.x = summon.worldX(at: tick, profile: profiles[volume.owner])
                sourceShapes = (shapes(oldTick), shapes(nowTick))
            }
            if let sourceShapes {
                volume.setAuthoredBounds(sourceShapes.after)
                let targets: [(DuelWeaponCapsule, DuelWeaponCapsule)]
                if let after = hurtAfter[target], let before = hurtBefore[target] {
                    let previous = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0.capsule) })
                    targets = after.map { (previous[$0.id] ?? $0.capsule, $0.capsule) }
                } else {
                    // Legacy target catalogs have no source capsules. This
                    // explicit adapter ends when that target supplies its rig.
                    let radius = Double(hurt.maxX - hurt.minX) / 2000
                    let x = Double(hurt.minX + hurt.maxX) / 2000
                    let low = min(Double(hurt.maxY + hurt.minY) / 2000, Double(hurt.minY) / 1000 + radius)
                    let high = max(low, Double(hurt.maxY) / 1000 - radius)
                    let now = DuelWeaponCapsule(a: .init(x: x, y: low), b: .init(x: x, y: high), radius: radius)
                    let dx = Double(previousX[target] - defender.x) / 1000
                    let dy = Double(previousHurtY[target] - hurt.minY) / 1000
                    let prior = DuelWeaponCapsule(a: .init(x: x + dx, y: low + dy), b: .init(x: x + dx, y: high + dy), radius: radius)
                    targets = [(prior, now)]
                }
                var earliest: DuelWeaponCapsule.Contact?
                for (prior, now) in zip(sourceShapes.before, sourceShapes.after) {
                    for (before, after) in targets {
                        if let contact = DuelWeaponCapsule.swept(attackBefore: prior, attackAfter: now, hurtBefore: before, hurtAfter: after),
                           earliest == nil || contact.time < earliest!.time { earliest = contact }
                    }
                }
                touching = earliest != nil; sourceContact = earliest?.point
            } else if volume.moves {
                let previous = volume.x
                let delta = min(max(0, volume.attack.rangeMillimeters - volume.travelled),
                                volume.attack.projectileSpeedMillimetersPerTick)
                volume.x += volume.direction * delta; volume.travelled += delta
                let expanded = DuelGame.Box(minX: hurt.minX - volume.attack.radiusMillimeters,
                    maxX: hurt.maxX + volume.attack.radiusMillimeters,
                    minY: hurt.minY - volume.halfHeight, maxY: hurt.maxY + volume.halfHeight)
                let from = DuelWeaponPoint(x: Double(previous + defender.x - previousX[target]) / 1000,
                    y: Double(volume.centerY + hurt.minY - previousHurtY[target]) / 1000)
                let to = DuelWeaponPoint(x: Double(volume.x) / 1000, y: Double(volume.centerY) / 1000)
                touching = DuelWeaponFight.segment(from, to, intersects: expanded, radius: 0)
                if volume.travelled >= volume.attack.rangeMillimeters { volume.spent = true }
            } else { touching = volume.bounds.overlaps(hurt) }
            if touching && tick - volume.releasedAt >= volume.attack.activationDelayTicks && defender.invulnerable == 0 {
                volume.spent = true
                hits.append(.init(owner: volume.owner, attack: volume.attack,
                    point: sourceContact ?? .init(x: Double(min(hurt.maxX, max(hurt.minX, volume.x))) / 1000,
                        y: Double(min(hurt.maxY, max(hurt.minY, volume.centerY))) / 1000, z: 0.08),
                    direction: volume.direction,
                    blocked: volume.attack.blockable && defender.guarding && defender.y == 0))
            }
            volumes[i] = volume
        }
        volumes.removeAll { $0.spent || tick >= $0.expiresAt }
        return hits
    }
    mutating func cancelUnreleased(owner: Int) {
        deferred.removeAll { envelope in
            guard envelope.owner == owner else { return false }
            if case .attack(let attack) = envelope.effect { return attack.summonID == nil }
            return false
        }
    }
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.int(tick); try writer.u64(hitSequence); try writer.int(rejectedVolumes)
        try writer.array(controls, limit: 2) { writer, value in
            try writer.int(value.rootUntil); try writer.u64(value.rootSourceID)
            try writer.optional(value.rootOwner) { try $0.int($1) }; try writer.int(value.stunUntil)
        }
        try writer.array(volumes, limit: DuelTriadState.maximumPendingEvents) { writer, value in
            try writer.int(value.owner); try value.attack.appendReplayState(to: &writer)
            try writer.int(value.originX); try writer.int(value.originY); try writer.int(value.direction)
            try writer.int(value.releasedAt); try writer.int(value.expiresAt); try writer.int(value.x)
            try writer.int(value.travelled); try writer.bool(value.spent)
            try writer.optional(value.authoredBounds) { writer, bounds in
                try writer.int(bounds.minX); try writer.int(bounds.maxX); try writer.int(bounds.minY); try writer.int(bounds.maxY)
            }
        }
        try writer.array(summons, limit: DuelTriadState.maximumPendingEvents) { writer, value in
            try writer.u64(value.id); try writer.int(value.owner)
            try writer.string(value.soul.rawValue); try writer.string(value.origin.rawValue)
            try writer.int(value.bornAt); try writer.int(value.expiresAt)
            try writer.int(value.x); try writer.int(value.y); try writer.int(value.z); try writer.int(value.direction)
            try writer.optional(value.sourceMove) { try $0.string($1.rawValue) }
            try writer.optional(value.sourceAnimation) { try $0.string($1.rawValue) }
            try writer.int(value.motionBeganAt); try writer.int(value.lastSampleTick)
            try writer.int(value.motionBaseX)
        }
        try writer.array(deferred) { writer, value in
            try writer.int(value.owner); try value.effect.appendReplayState(to: &writer)
        }
    }
}
