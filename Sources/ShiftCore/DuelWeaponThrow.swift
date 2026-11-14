import Foundation

/// Integer world coordinates. Throw tracks are offsets from each participant's
/// actual position at the start of the current sequence, never source root
/// displacement and never the target's position when the input was pressed.
public struct DuelWeaponThrowPosition: Codable, Equatable, Sendable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

/// Every animation phase, position and facing is explicitly authored. The
/// phase denominator is 10,000; ticks use the authoritative 60 Hz simulation.
public struct DuelWeaponThrowKeyframe: Codable, Equatable, Sendable {
    public let tick: Int
    public let phaseBps: Int
    public let xMillimeters: Int
    public let yMillimeters: Int
    public let facingMultiplier: Int

    public init(tick: Int, phaseBps: Int, xMillimeters: Int,
                yMillimeters: Int, facingMultiplier: Int) {
        self.tick = tick; self.phaseBps = phaseBps
        self.xMillimeters = xMillimeters; self.yMillimeters = yMillimeters
        self.facingMultiplier = facingMultiplier
    }
}

public struct DuelWeaponThrowTrack: Codable, Equatable, Sendable {
    public let role: String
    public let keyframes: [DuelWeaponThrowKeyframe]

    public init(role: String, keyframes: [DuelWeaponThrowKeyframe]) {
        self.role = role; self.keyframes = keyframes
    }

    /// Exact integer interpolation. Facing changes at a keyframe, rather than
    /// interpolating through an invalid zero-facing state.
    func interpolated(at tick: Int) -> DuelWeaponThrowKeyframe {
        guard let first = keyframes.first, let last = keyframes.last else {
            // Only validated tracks reach a live state. This defensive value
            // does not enable a missing role or create a playable rule.
            return .init(tick: 0, phaseBps: 0, xMillimeters: 0,
                         yMillimeters: 0, facingMultiplier: 1)
        }
        if tick <= first.tick { return first }
        if tick >= last.tick { return last }
        for index in 1..<keyframes.count {
            let a = keyframes[index - 1], b = keyframes[index]
            if tick == b.tick { return b }
            if tick < b.tick {
                let elapsed = tick - a.tick, duration = b.tick - a.tick
                func mix(_ x: Int, _ y: Int) -> Int { x + (y - x) * elapsed / duration }
                return .init(tick: tick, phaseBps: mix(a.phaseBps, b.phaseBps),
                             xMillimeters: mix(a.xMillimeters, b.xMillimeters),
                             yMillimeters: mix(a.yMillimeters, b.yMillimeters),
                             facingMultiplier: a.facingMultiplier)
            }
        }
        return last
    }
}

/// A complete attempt, paired throw, failed attempt, or paired escape. Target
/// tracks are absent before contact and on a miss: an out-of-range opponent
/// continues its own simulation. Knockdown starts only when this sequence
/// releases its participants, not at the damage marker in the middle.
public struct DuelWeaponThrowSequence: Codable, Equatable, Sendable {
    public let durationTicks: Int
    public let attacker: DuelWeaponThrowTrack
    public let target: DuelWeaponThrowTrack?
    public let damageTick: Int
    public let damage: Int
    public let hitStopTicks: Int
    public let knockdownTicks: Int

    public init(durationTicks: Int, attacker: DuelWeaponThrowTrack,
                target: DuelWeaponThrowTrack?, damageTick: Int, damage: Int,
                hitStopTicks: Int, knockdownTicks: Int) {
        self.durationTicks = durationTicks; self.attacker = attacker; self.target = target
        self.damageTick = damageTick; self.damage = damage
        self.hitStopTicks = hitStopTicks; self.knockdownTicks = knockdownTicks
    }
}

/// Ordinary throws reuse an existing relative directional weapon input, but
/// that input alone confers no weapon damage, wind, combo or resource effects.
/// Every such policy is explicit: startsPanguAttack is consumed at attempt
/// startup, while contact and resource gains use the successful damage marker.
/// There is no retail or legacy throw preset.
public struct DuelWeaponThrowRule: Codable, Equatable, Sendable {
    public let command: DuelWeaponCommand
    public let contactStartTick: Int
    public let contactEndTick: Int
    public let minimumRangeMillimeters: Int
    public let maximumRangeMillimeters: Int
    public let canGrabAttackingTarget: Bool
    public let damageKind: DuelPanguRules.DamageKind
    public let appliesPanguDamageScaling: Bool
    public let startsPanguAttack: Bool
    public let registersPanguContact: Bool
    public let attackerEnergyGain: Int
    public let targetEnergyGain: Int
    public let attempt: DuelWeaponThrowSequence
    public let success: DuelWeaponThrowSequence
    public let miss: DuelWeaponThrowSequence
    public let immune: DuelWeaponThrowSequence

    public init(command: DuelWeaponCommand, contactStartTick: Int, contactEndTick: Int,
                minimumRangeMillimeters: Int, maximumRangeMillimeters: Int,
                canGrabAttackingTarget: Bool, damageKind: DuelPanguRules.DamageKind,
                appliesPanguDamageScaling: Bool, startsPanguAttack: Bool,
                registersPanguContact: Bool, attackerEnergyGain: Int, targetEnergyGain: Int,
                attempt: DuelWeaponThrowSequence, success: DuelWeaponThrowSequence,
                miss: DuelWeaponThrowSequence, immune: DuelWeaponThrowSequence) {
        self.command = command; self.contactStartTick = contactStartTick
        self.contactEndTick = contactEndTick
        self.minimumRangeMillimeters = minimumRangeMillimeters
        self.maximumRangeMillimeters = maximumRangeMillimeters
        self.canGrabAttackingTarget = canGrabAttackingTarget; self.damageKind = damageKind
        self.appliesPanguDamageScaling = appliesPanguDamageScaling
        self.startsPanguAttack = startsPanguAttack
        self.registersPanguContact = registersPanguContact
        self.attackerEnergyGain = attackerEnergyGain; self.targetEnergyGain = targetEnergyGain
        self.attempt = attempt; self.success = success; self.miss = miss; self.immune = immune
    }
}

public struct DuelWeaponThrowRules: Codable, Equatable, Sendable {
    public enum SimultaneousContactPolicy: String, Codable, Sendable {
        case bothMiss, lowerFighterIndexWins
    }

    public let id: String
    public let basis: DuelCombatRuleProfile.Basis
    public let sourceVersion: String
    public let sourceSHA256: String?
    public let evidence: [String]
    public let simultaneousContactPolicy: SimultaneousContactPolicy
    public let attempts: [DuelWeaponThrowRule]

    public init(id: String, basis: DuelCombatRuleProfile.Basis, sourceVersion: String,
                sourceSHA256: String?, evidence: [String],
                simultaneousContactPolicy: SimultaneousContactPolicy,
                attempts: [DuelWeaponThrowRule]) {
        self.id = id; self.basis = basis; self.sourceVersion = sourceVersion
        self.sourceSHA256 = sourceSHA256; self.evidence = evidence
        self.simultaneousContactPolicy = simultaneousContactPolicy; self.attempts = attempts
    }

    public func rule(command: DuelWeaponCommand) -> DuelWeaponThrowRule? {
        attempts.first { $0.command == command }
    }

    public enum ValidationError: Error, Equatable {
        case provenance, incomplete, duplicateCommand, invalidRule, invalidSequence
        case invalidTrack, missingSourceRole
    }

    /// Bounds and shape are checked even for a branch that the current opponent
    /// cannot reach. Provenance labels alone do not authenticate source data.
    public func validate() throws {
        guard !id.isEmpty, id.utf8.count <= 128,
              !sourceVersion.isEmpty, sourceVersion.utf8.count <= 256,
              evidence.count <= 16,
              evidence.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }),
              basis == .applicationAdaptation || !evidence.isEmpty else {
            throw ValidationError.provenance
        }
        if let sourceSHA256 {
            guard sourceSHA256.utf8.count == 64,
                  sourceSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw ValidationError.provenance
            }
        } else if basis == .sourceConfiguration { throw ValidationError.provenance }
        guard !attempts.isEmpty, attempts.count <= 2 else { throw ValidationError.incomplete }
        var commands = Set<String>()
        for rule in attempts {
            guard commands.insert(rule.command.rawValue).inserted else {
                throw ValidationError.duplicateCommand
            }
            try rule.validateStructure()
        }
    }

    /// Attacker motions must all be bound. Only the opponent's reachable paired
    /// branch needs a source role: Pangu's ordinary-throw escape or a normal
    /// target's thrown motion. No idle/hit fallback silently substitutes a role.
    public func validate(for attacker: DuelWeaponProfile, target: DuelWeaponProfile) throws {
        try validate()
        for rule in attempts {
            guard let commandClip = attacker.clip(command: rule.command),
                  attacker.resolvedCombatRule(command: rule.command, clipName: commandClip.name) != nil else {
                throw ValidationError.missingSourceRole
            }
            for sequence in [rule.attempt, rule.success, rule.miss, rule.immune] {
                guard let clip = attacker.clip(role: sequence.attacker.role),
                      let end = sequence.attacker.keyframes.last,
                      Self.sourceIsGrounded(clip, phaseBps: end.phaseBps) else {
                    throw ValidationError.missingSourceRole
                }
            }
            guard let attemptClip = attacker.clip(role: rule.attempt.attacker.role),
                  let start = rule.attempt.attacker.keyframes.first,
                  Self.sourceIsGrounded(attemptClip, phaseBps: start.phaseBps) else {
                throw ValidationError.missingSourceRole
            }
            let targetTrack = target.isPangu ? rule.immune.target : rule.success.target
            guard let targetTrack, let targetClip = target.clip(role: targetTrack.role),
                  let end = targetTrack.keyframes.last,
                  Self.sourceIsGrounded(targetClip, phaseBps: end.phaseBps) else {
                throw ValidationError.missingSourceRole
            }
        }
    }

    private static func sourceIsGrounded(_ clip: DuelWeaponClip, phaseBps: Int) -> Bool {
        let phase = Double(phaseBps) / 10_000, tracks = clip.tracks
        return min(tracks.sample(tracks.footL, phase: phase).y,
                   tracks.sample(tracks.footR, phase: phase).y) + tracks.lift(phase: phase) <= 0.17
    }
}

extension DuelWeaponThrowRule {
    fileprivate func validateStructure() throws {
        typealias Failure = DuelWeaponThrowRules.ValidationError
        guard command == .weaponForward || command == .weaponBack,
              (0...10_000).contains(minimumRangeMillimeters),
              minimumRangeMillimeters <= maximumRangeMillimeters,
              maximumRangeMillimeters <= 10_000,
              contactStartTick >= 1, contactStartTick <= contactEndTick,
              contactEndTick <= attempt.durationTicks,
              (0...100).contains(attackerEnergyGain), (0...100).contains(targetEnergyGain) else {
            throw Failure.invalidRule
        }
        for (sequence, paired, effectsAllowed) in [
            (attempt, false, false), (success, true, true),
            (miss, false, false), (immune, true, false)
        ] {
            guard (1...600).contains(sequence.durationTicks),
                  paired == (sequence.target != nil),
                  (0...1_000_000).contains(sequence.damage),
                  (0...60).contains(sequence.hitStopTicks),
                  (0...600).contains(sequence.knockdownTicks),
                  sequence.damage == 0 ? sequence.damageTick == 0 :
                    (1...sequence.durationTicks).contains(sequence.damageTick) else {
                throw Failure.invalidSequence
            }
            if !effectsAllowed && (sequence.damage != 0 || sequence.damageTick != 0 ||
                                   sequence.hitStopTicks != 0 || sequence.knockdownTicks != 0) {
                throw Failure.invalidSequence
            }
            // Hitstop is an effect of an actual damage marker, not a timer that
            // a zero-damage/missing marker may trigger implicitly.
            if sequence.damage == 0 && sequence.hitStopTicks != 0 { throw Failure.invalidSequence }
            try sequence.attacker.validate(durationTicks: sequence.durationTicks, grounded: !paired)
            if let target = sequence.target {
                try target.validate(durationTicks: sequence.durationTicks, grounded: false)
                // Both actors retain their real contact position. For either
                // allowed contact-range endpoint, every integer sample must
                // fit in the arena after one common horizontal translation.
                let arenaWidth = DuelGame.rightWall - DuelGame.leftWall
                for tick in 0...sequence.durationTicks {
                    let relative = target.interpolated(at: tick).xMillimeters
                        - sequence.attacker.interpolated(at: tick).xMillimeters
                    guard abs(minimumRangeMillimeters + relative) <= arenaWidth,
                          abs(maximumRangeMillimeters + relative) <= arenaWidth else {
                        throw Failure.invalidSequence
                    }
                }
            }
        }
    }
}

extension DuelWeaponThrowTrack {
    fileprivate func validate(durationTicks: Int, grounded: Bool) throws {
        typealias Failure = DuelWeaponThrowRules.ValidationError
        guard !role.isEmpty, role.utf8.count <= 128,
              (2...64).contains(keyframes.count),
              let first = keyframes.first, let last = keyframes.last,
              first.tick == 0, last.tick == durationTicks,
              first.xMillimeters == 0, first.yMillimeters == 0,
              last.yMillimeters == 0 else { throw Failure.invalidTrack }
        var previousTick = -1
        for frame in keyframes {
            guard frame.tick > previousTick, (0...durationTicks).contains(frame.tick),
                  (0...10_000).contains(frame.phaseBps),
                  (-10_000...10_000).contains(frame.xMillimeters),
                  (0...10_000).contains(frame.yMillimeters),
                  frame.facingMultiplier == -1 || frame.facingMultiplier == 1,
                  !grounded || frame.yMillimeters == 0 else { throw Failure.invalidTrack }
            previousTick = frame.tick
        }
    }
}

/// Authoritative ordinary-throw state. The fight advances this exactly once per
/// simulation tick, excluding hitstop. It applies nextSample before constructing
/// the contact context so eligibility includes the current source pose and the
/// freely moving opponent. Rendering and wall-clock time cannot advance it.
///
/// The state deliberately returns unclamped positions. The fight translates a
/// paired sample as one unit at an arena wall, preserving its authored spacing.
public struct DuelWeaponThrowState: Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable { case success, missed, immune }
    public enum Stage: String, Sendable { case attempt, success, miss, immune, finished }

    public struct ContactContext: Equatable, Sendable {
        public let attackerPosition: DuelWeaponThrowPosition
        public let targetPosition: DuelWeaponThrowPosition
        public let attackerGrounded: Bool
        public let targetGrounded: Bool
        public let attackerAlive: Bool
        public let targetAlive: Bool
        public let targetAvailable: Bool
        public let targetThrowImmune: Bool

        public init(attackerPosition: DuelWeaponThrowPosition, targetPosition: DuelWeaponThrowPosition,
                    attackerGrounded: Bool, targetGrounded: Bool,
                    attackerAlive: Bool, targetAlive: Bool,
                    targetAvailable: Bool, targetThrowImmune: Bool) {
            self.attackerPosition = attackerPosition; self.targetPosition = targetPosition
            self.attackerGrounded = attackerGrounded; self.targetGrounded = targetGrounded
            self.attackerAlive = attackerAlive; self.targetAlive = targetAlive
            self.targetAvailable = targetAvailable; self.targetThrowImmune = targetThrowImmune
        }
    }

    public struct ActorSample: Equatable, Sendable {
        public let role: String
        public let phaseBps: Int
        public let position: DuelWeaponThrowPosition
        public let facing: Int
    }

    public struct Sample: Equatable, Sendable {
        public let attacker: ActorSample
        public let target: ActorSample?
    }

    public struct Damage: Equatable, Sendable {
        public let amount: Int
        public let hitStopTicks: Int
    }

    public struct Step: Equatable, Sendable {
        public let sample: Sample
        /// A one-shot transition, including a window-expired or rejected miss.
        public let contactOutcome: Outcome?
        public let damage: Damage?
        public let released: Bool
        /// Nonzero only on the successful release edge, never at contact/damage.
        public let knockdownTicks: Int
    }

    public let rule: DuelWeaponThrowRule
    public let attacker: Int
    public let target: Int
    public let facing: Int
    public private(set) var attackerOrigin: DuelWeaponThrowPosition
    public private(set) var targetOrigin: DuelWeaponThrowPosition
    public private(set) var stageTick = 0
    public private(set) var outcome: Outcome?
    public private(set) var contactConsumed = false
    public private(set) var damageApplied = false
    public private(set) var isFinished = false
    public private(set) var isCancelled = false

    public init?(rule: DuelWeaponThrowRule, attacker: Int, target: Int, facing: Int,
                 attackerPosition: DuelWeaponThrowPosition, targetPosition: DuelWeaponThrowPosition) {
        do { try rule.validateStructure() } catch { return nil }
        guard (0...1).contains(attacker), (0...1).contains(target), attacker != target,
              facing == -1 || facing == 1,
              Self.isSafe(attackerPosition), Self.isSafe(targetPosition) else { return nil }
        self.rule = rule; self.attacker = attacker; self.target = target; self.facing = facing
        attackerOrigin = attackerPosition; targetOrigin = targetPosition
    }

    public var stage: Stage {
        if isFinished { return .finished }
        switch outcome {
        case nil: return .attempt
        case .success: return .success
        case .missed: return .miss
        case .immune: return .immune
        }
    }

    public var currentSequence: DuelWeaponThrowSequence {
        switch outcome {
        case nil: return rule.attempt
        case .success: return rule.success
        case .missed: return rule.miss
        case .immune: return rule.immune
        }
    }

    public var sample: Sample { sample(at: stageTick) }
    public var nextSample: Sample {
        sample(at: isFinished ? stageTick : min(currentSequence.durationTicks, stageTick + 1))
    }

    public func ownsFighter(index: Int) -> Bool {
        guard !isFinished else { return false }
        return index == attacker || (index == target && (outcome == .success || outcome == .immune))
    }

    /// Read before advancing either participant when resolving simultaneous
    /// attempts. The caller applies the catalog's explicit arbitration policy.
    public func wouldContact(context: ContactContext) -> Bool {
        guard !isFinished, !contactConsumed, outcome == nil,
              Self.isSafe(context.attackerPosition), Self.isSafe(context.targetPosition),
              context.attackerAlive, context.targetAlive,
              context.attackerGrounded, context.targetGrounded,
              context.attackerPosition.y == 0, context.targetPosition.y == 0,
              context.targetAvailable else { return false }
        let nextTick = stageTick + 1
        guard nextTick >= rule.contactStartTick, nextTick <= rule.contactEndTick else { return false }
        let distance = (context.targetPosition.x - context.attackerPosition.x) * facing
        // A side switch during startup must not pull an opponent through the
        // attacker's back, regardless of the absolute distance being short.
        return distance > 0 && distance >= rule.minimumRangeMillimeters && distance <= rule.maximumRangeMillimeters
    }

    public mutating func advance(context: ContactContext) -> Step {
        guard !isFinished else { return step() }
        guard Self.isSafe(context.attackerPosition), Self.isSafe(context.targetPosition),
              context.attackerAlive, context.targetAlive else {
            cancel()
            return step(released: true)
        }

        if outcome == nil {
            let contacted = wouldContact(context: context)
            stageTick = min(rule.attempt.durationTicks, stageTick + 1)
            if contacted {
                let result: Outcome = context.targetThrowImmune ? .immune : .success
                begin(result, attackerPosition: context.attackerPosition, targetPosition: context.targetPosition)
                return step(contactOutcome: result)
            }
            // The last active tick is checked before it becomes a miss.
            if stageTick >= rule.contactEndTick {
                begin(.missed, attackerPosition: context.attackerPosition, targetPosition: context.targetPosition)
                return step(contactOutcome: .missed)
            }
            return step()
        }

        let sequence = currentSequence
        stageTick = min(sequence.durationTicks, stageTick + 1)
        var damage: Damage?
        if outcome == .success, !damageApplied, sequence.damage > 0, stageTick >= sequence.damageTick {
            damageApplied = true
            damage = .init(amount: sequence.damage, hitStopTicks: sequence.hitStopTicks)
        }
        let released = stageTick >= sequence.durationTicks
        if released { isFinished = true }
        return step(damage: damage, released: released,
                    knockdownTicks: released && outcome == .success ? sequence.knockdownTicks : 0)
    }

    /// Resolves simultaneous ordinary throws without applying either success
    /// branch first. It never turns an already paired outcome into a miss.
    public mutating func forceMiss(attackerPosition: DuelWeaponThrowPosition,
                                   targetPosition: DuelWeaponThrowPosition) -> Step {
        guard !isFinished, outcome == nil else { return step() }
        guard Self.isSafe(attackerPosition), Self.isSafe(targetPosition) else {
            cancel(); return step(released: true)
        }
        begin(.missed, attackerPosition: attackerPosition, targetPosition: targetPosition)
        return step(contactOutcome: .missed)
    }

    /// Removal, an interrupt, KO or a round transition must dispose of this
    /// authority. Cancellation does not award damage, knockdown or resources.
    public mutating func cancel() { isFinished = true; isCancelled = true }

    private mutating func begin(_ result: Outcome, attackerPosition: DuelWeaponThrowPosition,
                                targetPosition: DuelWeaponThrowPosition) {
        outcome = result; stageTick = 0; contactConsumed = true; damageApplied = false
        attackerOrigin = attackerPosition; targetOrigin = targetPosition
    }

    private func sample(at tick: Int) -> Sample {
        let sequence = currentSequence
        func actor(_ track: DuelWeaponThrowTrack, origin: DuelWeaponThrowPosition) -> ActorSample {
            let frame = track.interpolated(at: tick)
            return .init(role: track.role, phaseBps: frame.phaseBps,
                         position: .init(x: origin.x + frame.xMillimeters * facing,
                                         y: origin.y + frame.yMillimeters),
                         facing: facing * frame.facingMultiplier)
        }
        return .init(attacker: actor(sequence.attacker, origin: attackerOrigin),
                     target: sequence.target.map { actor($0, origin: targetOrigin) })
    }

    private func step(contactOutcome: Outcome? = nil, damage: Damage? = nil,
                      released: Bool = false, knockdownTicks: Int = 0) -> Step {
        .init(sample: sample, contactOutcome: contactOutcome, damage: damage,
              released: released, knockdownTicks: knockdownTicks)
    }

    private static func isSafe(_ position: DuelWeaponThrowPosition) -> Bool {
        (-1_000_000...1_000_000).contains(position.x) && (0...10_000).contains(position.y)
    }
}

// These bytes include the complete supplied configuration and every dynamic
// field. No hash string, presentation queue, wall clock, or Swift Hasher can
// substitute for the actual throw state in deterministic replay diagnostics.
extension DuelWeaponThrowRules {
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.string(id); try writer.string(basis.rawValue); try writer.string(sourceVersion)
        try writer.optional(sourceSHA256) { try $0.string($1) }
        try writer.array(evidence, limit: 16) { try $0.string($1) }
        try writer.string(simultaneousContactPolicy.rawValue)
        try writer.array(attempts, limit: 2) { try $1.appendReplayState(to: &$0) }
    }
}

extension DuelWeaponThrowRule {
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.command(command); try writer.int(contactStartTick); try writer.int(contactEndTick)
        try writer.int(minimumRangeMillimeters); try writer.int(maximumRangeMillimeters)
        try writer.bool(canGrabAttackingTarget); try writer.string(damageKind.rawValue)
        try writer.bool(appliesPanguDamageScaling); try writer.bool(startsPanguAttack)
        try writer.bool(registersPanguContact); try writer.int(attackerEnergyGain); try writer.int(targetEnergyGain)
        try attempt.appendReplayState(to: &writer); try success.appendReplayState(to: &writer)
        try miss.appendReplayState(to: &writer); try immune.appendReplayState(to: &writer)
    }
}

extension DuelWeaponThrowSequence {
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.int(durationTicks); try attacker.appendReplayState(to: &writer)
        try writer.optional(target) { try $1.appendReplayState(to: &$0) }
        try writer.int(damageTick); try writer.int(damage); try writer.int(hitStopTicks)
        try writer.int(knockdownTicks)
    }
}

extension DuelWeaponThrowTrack {
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.string(role)
        try writer.array(keyframes, limit: 64) { writer, frame in
            try writer.int(frame.tick); try writer.int(frame.phaseBps)
            try writer.int(frame.xMillimeters); try writer.int(frame.yMillimeters)
            try writer.int(frame.facingMultiplier)
        }
    }
}

extension DuelWeaponThrowState {
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try rule.appendReplayState(to: &writer)
        try writer.int(attacker); try writer.int(target); try writer.int(facing)
        try writer.int(attackerOrigin.x); try writer.int(attackerOrigin.y)
        try writer.int(targetOrigin.x); try writer.int(targetOrigin.y)
        try writer.int(stageTick); try writer.optional(outcome) { try $0.string($1.rawValue) }
        try writer.bool(contactConsumed); try writer.bool(damageApplied)
        try writer.bool(isFinished); try writer.bool(isCancelled)
    }
}
