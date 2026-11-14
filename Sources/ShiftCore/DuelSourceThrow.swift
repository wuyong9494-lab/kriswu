import Foundation

/// A source animation projected onto the arena's integer coordinate system.
/// The application explicitly supplies the centimetre-to-millimetre scale;
/// source clip identities, frame boundaries and root samples remain separate.
public struct DuelSourceThrowMotion: Codable, Equatable, Sendable {
    public let role: String
    public let sourceSHA256: String
    public let lastSampleTick: Int
    public let animationEndTick: Int
    public let uninterruptEndTick: Int
    public let rootMillimeters: [Int]
    public let footLeftMillimeters: Int
    public let pelvisMillimeters: Int

    public init(role: String, sourceSHA256: String, lastSampleTick: Int,
                animationEndTick: Int, uninterruptEndTick: Int,
                rootMillimeters: [Int], footLeftMillimeters: Int, pelvisMillimeters: Int) {
        self.role = role; self.sourceSHA256 = sourceSHA256
        self.lastSampleTick = lastSampleTick; self.animationEndTick = animationEndTick
        self.uninterruptEndTick = uninterruptEndTick; self.rootMillimeters = rootMillimeters
        self.footLeftMillimeters = footLeftMillimeters; self.pelvisMillimeters = pelvisMillimeters
    }

    fileprivate func validate() throws {
        guard !role.isEmpty, role.utf8.count <= 128,
              sourceSHA256.utf8.count == 64,
              sourceSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              (2...600).contains(lastSampleTick),
              (1...lastSampleTick).contains(animationEndTick),
              (1...lastSampleTick + 1).contains(uninterruptEndTick),
              rootMillimeters.count == lastSampleTick + 1, rootMillimeters.first == 0,
              rootMillimeters.allSatisfy({ (-10_000...10_000).contains($0) }),
              (-10_000...10_000).contains(footLeftMillimeters),
              (-10_000...10_000).contains(pelvisMillimeters) else {
            throw DuelWeaponThrowRules.ValidationError.invalidTrack
        }
    }

    fileprivate func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.string(role); try writer.string(sourceSHA256)
        try writer.int(lastSampleTick); try writer.int(animationEndTick); try writer.int(uninterruptEndTick)
        try writer.array(rootMillimeters, limit: 601) { try $0.int($1) }
        try writer.int(footLeftMillimeters); try writer.int(pelvisMillimeters)
    }
}

/// Recovered common-throw trigger semantics. This is deliberately independent
/// of the older authored attempt/miss interpreter: the source has no grab-miss
/// animation, and D19's real paired escape damages the original initiator.
public struct DuelSourceThrowRules: Codable, Equatable, Sendable {
    public enum Motion: String, CaseIterable, Codable, Sendable {
        case backActive, backPassive, forwardActive, forwardPassive, panguActive, panguPassive
    }
    public enum Variant: String, Codable, Sendable { case back, forward, panguEscape }

    public let motions: [Motion.RawValue: DuelSourceThrowMotion]
    public let normalizedUnarmedPower: Int
    public let millimetersPerSourceUnitNumerator: Int
    public let millimetersPerSourceUnitDenominator: Int
    public let maximumRangeSourceUnits: Int
    public let forwardWallThresholdSourceUnits: Int
    public let backWallThresholdSourceUnits: Int
    public let throwDisabledAfterVictimEndTicks: Int

    public init(motions: [Motion.RawValue: DuelSourceThrowMotion], normalizedUnarmedPower: Int,
                millimetersPerSourceUnitNumerator: Int, millimetersPerSourceUnitDenominator: Int,
                maximumRangeSourceUnits: Int, forwardWallThresholdSourceUnits: Int,
                backWallThresholdSourceUnits: Int, throwDisabledAfterVictimEndTicks: Int) {
        self.motions = motions; self.normalizedUnarmedPower = normalizedUnarmedPower
        self.millimetersPerSourceUnitNumerator = millimetersPerSourceUnitNumerator
        self.millimetersPerSourceUnitDenominator = millimetersPerSourceUnitDenominator
        self.maximumRangeSourceUnits = maximumRangeSourceUnits
        self.forwardWallThresholdSourceUnits = forwardWallThresholdSourceUnits
        self.backWallThresholdSourceUnits = backWallThresholdSourceUnits
        self.throwDisabledAfterVictimEndTicks = throwDisabledAfterVictimEndTicks
    }

    public func motion(_ key: Motion) -> DuelSourceThrowMotion? { motions[key.rawValue] }

    public func validate() throws {
        guard Set(motions.keys) == Set(Motion.allCases.map(\.rawValue)),
              Set(motions.values.map(\.role)).count == Motion.allCases.count,
              (1...1_000_000).contains(normalizedUnarmedPower),
              (1...1000).contains(millimetersPerSourceUnitNumerator),
              (1...1000).contains(millimetersPerSourceUnitDenominator),
              (1...1000).contains(maximumRangeSourceUnits),
              (1...1000).contains(forwardWallThresholdSourceUnits),
              (1...1000).contains(backWallThresholdSourceUnits),
              (1...600).contains(throwDisabledAfterVictimEndTicks) else {
            throw DuelWeaponThrowRules.ValidationError.invalidRule
        }
        for value in motions.values { try value.validate() }
        // Source damage happens while both paired animations still exist.
        guard let back = motion(.backActive), let backTarget = motion(.backPassive),
              let forward = motion(.forwardActive), let forwardTarget = motion(.forwardPassive),
              let escape = motion(.panguActive), let escaped = motion(.panguPassive),
              min(back.animationEndTick, backTarget.animationEndTick) > 54,
              min(forward.animationEndTick, forwardTarget.animationEndTick) > 92,
              min(escape.animationEndTick, escaped.animationEndTick) > 98 else {
            throw DuelWeaponThrowRules.ValidationError.invalidSequence
        }
    }

    public func validate(for attacker: DuelWeaponProfile, target: DuelWeaponProfile) throws {
        try validate()
        guard target.ordinaryThrows?.source != nil else {
            throw DuelWeaponThrowRules.ValidationError.missingSourceRole
        }
        for profile in [attacker, target] {
            guard profile.clips.allSatisfy({ $0.tracks.centerOfMass != nil }) else {
                throw DuelWeaponThrowRules.ValidationError.invalidTrack
            }
            for motion in motions.values {
                guard let clip = profile.clip(role: motion.role), clip.sha256 == motion.sourceSHA256,
                      clip.frames > 1, 2 * (clip.frames - 1) == motion.lastSampleTick,
                      clip.ticks == motion.lastSampleTick else {
                    throw DuelWeaponThrowRules.ValidationError.missingSourceRole
                }
            }
        }
    }

    /// The comparison is inclusive at the original 102-unit COM boundary.
    /// Keeping the rational scale avoids turning 938.4 mm into a 939 mm grab.
    public func inRange(distanceMillimeters: Int) -> Bool {
        guard (0...20_000).contains(distanceMillimeters) else { return false }
        return distanceMillimeters * millimetersPerSourceUnitDenominator <=
            maximumRangeSourceUnits * millimetersPerSourceUnitNumerator
    }

    /// COM samples retain fractional millimetres. Rounding either actor before
    /// subtraction can move an out-of-range pair across the source boundary.
    public func inRange(distanceMillimeters: Double) -> Bool {
        guard distanceMillimeters.isFinite, (0...20_000).contains(distanceMillimeters) else { return false }
        return distanceMillimeters <= Double(maximumRangeSourceUnits * millimetersPerSourceUnitNumerator) /
            Double(millimetersPerSourceUnitDenominator)
    }

    public func variant(command: DuelWeaponCommand, targetToFrontWallMillimeters: Int,
                        initiatorToBackWallMillimeters: Int, targetHasD19Rules: Bool) -> Variant? {
        guard command == .weaponForward || command == .weaponBack,
              (0...20_000).contains(targetToFrontWallMillimeters),
              (0...20_000).contains(initiatorToBackWallMillimeters) else { return nil }
        if targetHasD19Rules { return .panguEscape }
        if command == .weaponForward {
            return targetToFrontWallMillimeters * millimetersPerSourceUnitDenominator <=
                forwardWallThresholdSourceUnits * millimetersPerSourceUnitNumerator ? .back : .forward
        }
        // The dedicated forward trigger is installed after the basic common
        // trigger and uses the explicit near-back-wall branch.
        return initiatorToBackWallMillimeters * millimetersPerSourceUnitDenominator <=
            backWallThresholdSourceUnits * millimetersPerSourceUnitNumerator ? .forward : .back
    }

    public func variant(command: DuelWeaponCommand, targetToFrontWallMillimeters: Double,
                        initiatorToBackWallMillimeters: Double, targetHasD19Rules: Bool) -> Variant? {
        guard command == .weaponForward || command == .weaponBack,
              targetToFrontWallMillimeters.isFinite, initiatorToBackWallMillimeters.isFinite,
              (0...20_000).contains(targetToFrontWallMillimeters),
              (0...20_000).contains(initiatorToBackWallMillimeters) else { return nil }
        if targetHasD19Rules { return .panguEscape }
        if command == .weaponForward {
            let boundary = Double(forwardWallThresholdSourceUnits * millimetersPerSourceUnitNumerator) /
                Double(millimetersPerSourceUnitDenominator)
            return targetToFrontWallMillimeters <= boundary ? .back : .forward
        }
        let boundary = Double(backWallThresholdSourceUnits * millimetersPerSourceUnitNumerator) /
            Double(millimetersPerSourceUnitDenominator)
        return initiatorToBackWallMillimeters <= boundary ? .forward : .back
    }

    fileprivate func millimeters(_ sourceUnits: Int) -> Int {
        sourceUnits * millimetersPerSourceUnitNumerator / millimetersPerSourceUnitDenominator
    }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        for key in Motion.allCases {
            try writer.string(key.rawValue)
            try writer.optional(motion(key)) { try $1.appendReplayState(to: &$0) }
        }
        for value in [normalizedUnarmedPower, millimetersPerSourceUnitNumerator,
            millimetersPerSourceUnitDenominator, maximumRangeSourceUnits,
            forwardWallThresholdSourceUnits, backWallThresholdSourceUnits,
            throwDisabledAfterVictimEndTicks] { try writer.int(value) }
    }
}

/// Source pairing starts at tick zero only after the fight has accepted both
/// actors from the same input snapshot. Each actor keeps its own source clock
/// and can finish before the other; no duration stretching or idle substitute.
public struct DuelSourceThrowState: Equatable, Sendable {
    public typealias Variant = DuelSourceThrowRules.Variant
    public struct ActorSample: Equatable, Sendable {
        public let fighter: Int
        public let role: String
        public let tick: Int
        public let lastSampleTick: Int
        public let xMillimeters: Int
        public let facing: Int
    }
    public struct Damage: Equatable, Sendable {
        public let attacker: Int
        public let target: Int
        public let amount: Int
    }
    public struct Step: Equatable, Sendable {
        public let samples: [ActorSample]
        public let released: [Int]
        public let damage: Damage?
        public let disabledThrowOwner: Int?
    }

    public let rules: DuelSourceThrowRules
    public let variant: Variant
    public let initiator: Int
    public let target: Int
    public let facing: Int
    public let origins: [Int]
    public let counterUnarmedPower: Int
    /// The other actor's FK geometry comes from that actor's own source rig.
    public let participantMotions: [DuelSourceThrowMotion]
    public private(set) var tick = 0
    public private(set) var released = [false, false]
    public private(set) var damageApplied = false
    public private(set) var cancelled = false

    public init?(rules: DuelSourceThrowRules, variant: Variant, initiator: Int, target: Int,
                 facing: Int, initiatorX: Int, counterUnarmedPower: Int,
                 targetRules: DuelSourceThrowRules? = nil) {
        do { try rules.validate(); try targetRules?.validate() } catch { return nil }
        guard (0...1).contains(initiator), target == 1 - initiator,
              facing == 1 || facing == -1,
              (-1_000_000...1_000_000).contains(initiatorX),
              (1...1_000_000).contains(counterUnarmedPower) else { return nil }
        self.rules = rules; self.variant = variant; self.initiator = initiator; self.target = target
        self.facing = facing; self.counterUnarmedPower = counterUnarmedPower
        let ownKey: DuelSourceThrowRules.Motion = variant == .panguEscape ? .panguPassive :
            variant == .back ? .backActive : .forwardActive
        let enemyKey: DuelSourceThrowRules.Motion = variant == .panguEscape ? .panguActive :
            variant == .back ? .backPassive : .forwardPassive
        guard let own = rules.motion(ownKey),
              let enemy = (targetRules ?? rules).motion(enemyKey) else { return nil }
        participantMotions = [own, enemy]
        let ownFacing = facing * (variant == .forward ? -1 : 1), enemyFacing = -ownFacing
        // Original Align first anchors the initiator's left foot to its pivot,
        // then the paired pelvis to that foot plus the source-local shift.
        let ownOrigin = initiatorX - own.footLeftMillimeters * ownFacing
        let sourceShift = variant == .panguEscape ? -80 : variant == .back ? 50 : -168
        let enemyOrigin = ownOrigin + own.footLeftMillimeters * ownFacing +
            rules.millimeters(sourceShift) * enemyFacing - enemy.pelvisMillimeters * enemyFacing
        origins = [ownOrigin, enemyOrigin]
        // A wall adapter may translate a pair, but must never squeeze the two
        // tracks independently or allow malformed data wider than the arena.
        for sample in 0..<min(own.animationEndTick, enemy.animationEndTick) {
            let a = ownOrigin + own.rootMillimeters[sample] * ownFacing
            let b = enemyOrigin + enemy.rootMillimeters[sample] * enemyFacing
            guard abs(a - b) <= DuelGame.rightWall - DuelGame.leftWall else { return nil }
        }
    }

    public var isFinished: Bool { cancelled || released.allSatisfy { $0 } }
    public func owns(_ fighter: Int) -> Bool {
        guard !cancelled, let slot = slot(fighter) else { return false }
        return !released[slot]
    }
    public func canInterrupt(_ fighter: Int) -> Bool {
        guard owns(fighter), let slot = slot(fighter), let motion = motion(slot) else { return false }
        return tick >= motion.uninterruptEndTick
    }
    public var samples: [ActorSample] { samples(at: tick, includeReleased: false) }
    public var nextSamples: [ActorSample] { samples(at: tick + 1, includeReleased: false) }

    @discardableResult public mutating func release(_ fighter: Int) -> Bool {
        guard owns(fighter), let slot = slot(fighter) else { return false }
        released[slot] = true; return true
    }

    public mutating func advance() -> Step {
        guard !isFinished else { return .init(samples: [], released: [], damage: nil, disabledThrowOwner: nil) }
        tick += 1
        let frameSamples = samples(at: tick, includeReleased: false)
        var ends: [Int] = [], disable: Int?
        var damage: Damage?
        let damageTick = variant == .panguEscape ? 98 : variant == .back ? 54 : 92
        if !damageApplied, tick == damageTick, !released[0], !released[1] {
            damageApplied = true
            damage = .init(attacker: variant == .panguEscape ? target : initiator,
                target: variant == .panguEscape ? initiator : target,
                amount: variant == .panguEscape ? counterUnarmedPower * 1500 / 10_000 :
                    rules.normalizedUnarmedPower * 1000 / 10_000)
        }
        for index in 0..<2 where !released[index] {
            if let motion = motion(index), tick >= motion.animationEndTick {
                released[index] = true; ends.append(index == 0 ? initiator : target)
                if index == 1 && variant != .panguEscape { disable = initiator }
            }
        }
        return .init(samples: frameSamples, released: ends, damage: damage, disabledThrowOwner: disable)
    }

    public mutating func cancel() { cancelled = true; released = [true, true] }

    private func slot(_ fighter: Int) -> Int? { fighter == initiator ? 0 : fighter == target ? 1 : nil }
    private func motion(_ slot: Int) -> DuelSourceThrowMotion? {
        participantMotions.indices.contains(slot) ? participantMotions[slot] : nil
    }
    private func samples(at atTick: Int, includeReleased: Bool) -> [ActorSample] {
        guard !cancelled else { return [] }
        return (0..<2).compactMap { index in
            guard includeReleased || !released[index], let motion = motion(index) else { return nil }
            let actorFacing = facing * (variant == .forward ? -1 : 1) * (index == 0 ? 1 : -1)
            let sampleTick = min(atTick, motion.lastSampleTick)
            return .init(fighter: index == 0 ? initiator : target, role: motion.role,
                tick: sampleTick, lastSampleTick: motion.lastSampleTick,
                xMillimeters: origins[index] + motion.rootMillimeters[sampleTick] * actorFacing,
                facing: actorFacing)
        }
    }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try rules.appendReplayState(to: &writer); try writer.string(variant.rawValue)
        try writer.int(initiator); try writer.int(target); try writer.int(facing)
        try writer.array(origins, limit: 2) { try $0.int($1) }
        try writer.int(counterUnarmedPower)
        try writer.array(participantMotions, limit: 2) { try $1.appendReplayState(to: &$0) }
        try writer.int(tick)
        try writer.array(released, limit: 2) { try $0.bool($1) }
        try writer.bool(damageApplied); try writer.bool(cancelled)
    }
}
