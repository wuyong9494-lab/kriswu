import Foundation

/// Binds the two ordinary D13 actions to the recovered body's actual clips.
/// This is an integration component, not a replacement full-fighter catalog.
public struct DuelSerpentActionBinding: Equatable, Sendable {
    public enum Action: String, CaseIterable, Sendable { case poison, bottle }
    public struct Motion: Equatable, Sendable {
        public let action: Action
        public let role, alias, clipName, clipSHA256: String
        public let frames, playbackTicks, endEventTick, releaseTick: Int
        public let releaseMarker: String
    }
    public enum Failure: Error { case identity, motion, state }
    public static let bodySHA256 = "f25b35dec9bf335bbe01ceee557389f47165c3d0b45b54502017fda394a8bd70"
    public static let settingsSHA256 = "3d660f485ad5e238f23bf6dd19d16855635a9449fd213bf1dd468a9cc979f701"
    public let motions: [Motion]

    public init(profile: DuelWeaponProfile) throws {
        guard profile.id == "liu_serpent", profile.hero == .liu,
              profile.bodyID == "arm__agl_41", profile.weaponID == "wpn__shuangou_01_04",
              profile.sha256 == Self.bodySHA256, profile.bytes == 15_561_412,
              profile.clips.count == 66, Set(profile.clips.map(\.name)).count == 66,
              profile.roles["shadow"] == nil, profile.roles["ranged"] == nil else { throw Failure.identity }
        motions = [
            Motion(action: .poison, role: "serpentPoison", alias: "D13_Poison_Ability", clipName: "d13_ability",
                   clipSHA256: "b9f6c1fc841353f09b352b2709e00fcfe1ae6696bec83f8984f9152186fe757f",
                   frames: 119, playbackTicks: 236, endEventTick: 228, releaseTick: 166,
                   releaseMarker: "D13_Poison_Apply"),
            Motion(action: .bottle, role: "serpentBottle", alias: "D13_Bottle_Throw", clipName: "d13_bottle_throw",
                   clipSHA256: "538d245fb5ed86c168cab9d80e32f43bb29102afb1cc9f853b23082cba6a8c24",
                   frames: 57, playbackTicks: 112, endEventTick: 104, releaseTick: 8,
                   releaseMarker: "D13_Bottle_Throw_Model")
        ]
        for motion in motions {
            guard let clip = profile.clip(role: motion.role), clip.name == motion.clipName,
                  clip.sha256 == motion.clipSHA256, clip.frames == motion.frames,
                  clip.playbackTicks == motion.playbackTicks,
                  clip.sourceEndEventTick == motion.endEventTick else { throw Failure.motion }
        }
    }
    public func motion(_ action: Action) -> Motion { motions.first { $0.action == action }! }
}

/// Deterministic bridge from accepted StageChange through source IntervalStart.
/// The caller still owns input-condition evaluation, collisions, presentation,
/// equipped-model creation and source-unit health conversion. In particular a
/// model request is not evidence of a projectile or a successful gameplay hit.
public struct DuelSerpentActionRuntime: Equatable, Sendable {
    public typealias Action = DuelSerpentActionBinding.Action
    public struct Playback: Equatable, Sendable {
        public let id: UInt64
        public let action: Action
        public fileprivate(set) var motionTick: Int
    }
    public enum Effect: Equatable, Sendable {
        case rangedUsageConsumed, clearRangedInput, poisonCastStarted
        case intervalStart(String)
        case equippedRangedModelRequested(group: String)
        case poisonExplosion(DuelSerpentState.Explosion)
        case sound(String)
        case animationEnded
    }
    public struct Event: Equatable, Sendable {
        public let playbackID: UInt64
        public let liveTick, motionTick: Int
        public let effect: Effect
    }
    public struct Step: Equatable, Sendable {
        public let poisonDamage: Double
        public let events: [Event]
    }
    public let binding: DuelSerpentActionBinding
    public private(set) var state: DuelSerpentState
    public private(set) var rangedUsagesLeft: Int
    public private(set) var liveTick = 0
    public private(set) var playback: Playback?
    public private(set) var lastPlaybackID: UInt64 = 0

    public init(binding: DuelSerpentActionBinding, level: Int, raidDamageAmplifier: Double,
                rangedUsagesLeft: Int) throws {
        guard let state = DuelSerpentState(level: level, raidDamageAmplifier: raidDamageAmplifier),
              (0...1_000_000).contains(rangedUsagesLeft) else { throw DuelSerpentActionBinding.Failure.state }
        self.binding = binding; self.state = state; self.rangedUsagesLeft = rangedUsagesLeft
    }
    public mutating func beginRound() { state.beginRound() }
    public mutating func endRound() { playback = nil; state.endRound() }
    /// Arena round replacement restores the opponent's health and discards
    /// effects targeting that old health bar. Owner Bloom/usage/cooldowns stay.
    mutating func clearTargetPoisonForArenaRound() { state.clearPoisonStores() }
    /// Input IDs are not playback IDs. Call only after source input/equipment
    /// guards accepted this actual animation. Repeated/old stage notifications
    /// cannot replace a live action or consume a second ranged usage.
    public mutating func acceptedAnimationStart(alias: String, playbackID: UInt64) -> [Event]? {
        guard state.roundActive, playback == nil, playbackID > lastPlaybackID,
              let motion = binding.motions.first(where: { $0.alias == alias }) else { return nil }
        var effects: [Effect]
        switch motion.action {
        case .poison:
            guard state.hasStoredPoison, state.poisonAbilityCooldownRemaining == 0 else { return nil }
            effects = [.poisonCastStarted]
        case .bottle:
            guard state.acceptBottleAnimationStart(rangedUsagesLeft: rangedUsagesLeft) else { return nil }
            rangedUsagesLeft -= 1
            effects = [.rangedUsageConsumed, .clearRangedInput]
        }
        lastPlaybackID = playbackID
        playback = Playback(id: playbackID, action: motion.action, motionTick: 0)
        return effects.map { Event(playbackID: playbackID, liveTick: liveTick, motionTick: 0, effect: $0) }
    }
    /// A simulation step, never a render callback. Exactly the next live tick
    /// is accepted; duplicate/frozen/backwards/skipped ticks have no effects.
    /// Catch-up must supply each tick's authoritative target state separately.
    public mutating func step(liveTick nextTick: Int, targetInvincible: Bool) -> Step? {
        guard state.roundActive, liveTick < Int.max, nextTick == liveTick + 1 else { return nil }
        liveTick = nextTick
        let damage = state.advanceStatusTick()
        guard var active = playback else { return Step(poisonDamage: damage, events: []) }
        active.motionTick += 1
        let motion = binding.motion(active.action), tick = active.motionTick
        var effects: [Effect] = []
        switch active.action {
        case .poison:
            if tick == 20 { effects.append(.sound("set_d13/poison_energy_cast@Battle@Movement")) }
            if tick == 30 { effects.append(.intervalStart("D13_Poison_Apply_VFX")) }
            if tick == 36 || tick == 180 {
                effects.append(.sound("shadow_moves/mind_throw/mind_throw_whoosh_1@Battle@Movement"))
            }
            if tick == motion.releaseTick {
                effects.append(.intervalStart(motion.releaseMarker))
                if let explosion = state.resolvePoisonExplosionKey(targetInvincible: targetInvincible) {
                    effects.append(.poisonExplosion(explosion))
                }
                effects.append(.sound("set_d13/poison_energy_hit_hiss@Battle@Movement"))
            }
        case .bottle:
            if tick == motion.releaseTick, state.acceptBottleReleaseMarker() {
                effects.append(.intervalStart(motion.releaseMarker))
                effects.append(.equippedRangedModelRequested(group: "D13_POSION_BOMB_MODEL"))
            }
            if tick == 46 { effects.append(.sound("set_d13/poison_rain_bottle@Battle@Movement")) }
        }
        if tick == motion.endEventTick {
            effects.append(.animationEnded); playback = nil; state.interruptBottle()
        } else { playback = active }
        return Step(poisonDamage: damage, events: effects.map {
            Event(playbackID: active.id, liveTick: liveTick, motionTick: tick, effect: $0)
        })
    }
    /// The caller decides whether a hit can interrupt using actual authored
    /// control intervals. An old network interruption cannot cancel a new cast.
    @discardableResult
    public mutating func interrupt(playbackID: UInt64) -> Bool {
        guard playback?.id == playbackID else { return false }
        playback = nil; state.interruptBottle()
        return true
    }
    @discardableResult
    public mutating func outgoingContact(channel: DuelSerpentState.Channel, sourceDamage: Double,
        event: DuelSerpentState.ContactEvent = .postHit, first: Bool = true, invisible: Bool = false,
        hitTag: String? = nil, perks: DuelSerpentState.Perks = .init()) -> Bool {
        state.outgoingContact(channel: channel, sourceDamage: sourceDamage, event: event,
                              first: first, invisible: invisible, hitTag: hitTag, perks: perks)
    }
    @discardableResult
    public mutating func incomingContact(sourceDamage: Double, event: DuelSerpentState.ContactEvent = .postHit,
                                        first: Bool = true, invisible: Bool = false) -> Bool {
        state.incomingContact(sourceDamage: sourceDamage, event: event, first: first, invisible: invisible)
    }
    /// Consume one accepted source PreHit before the host converts its damage.
    @discardableResult
    public mutating func prepareIncomingContact(blocked: Bool) -> Double {
        state.prepareIncomingContact(blocked: blocked)
    }
    @discardableResult
    public mutating func cloudPulse(_ channel: DuelSerpentState.Channel, targetInvincible: Bool) -> Bool {
        state.poisonBombCloudPulse(channel, targetInvincible: targetInvincible)
    }
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.string("d13-action-component-v1")
        try writer.string(DuelSerpentActionBinding.bodySHA256)
        try writer.string(DuelSerpentActionBinding.settingsSHA256)
        try state.appendReplayState(to: &writer)
        try writer.int(rangedUsagesLeft); try writer.int(liveTick); try writer.u64(lastPlaybackID)
        try writer.optional(playback) { writer, value in
            try writer.u64(value.id); try writer.string(value.action.rawValue); try writer.int(value.motionTick)
        }
    }
}
