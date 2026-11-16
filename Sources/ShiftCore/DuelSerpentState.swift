import Foundation

/// D13 source-unit state component. This is not a registered fighter profile.
/// Lock 1389 supplies four independent poison stores; 1395/1397 upgrade their
/// coefficients. f213 is RaidDamageAmplifier, never either fighter's health.
/// The match adapter must supply accepted source events and convert ModHP units
/// explicitly. No collision, source input evaluator or projectile is invented.
public struct DuelSerpentState: Equatable, Sendable {
    public enum Channel: String, CaseIterable, Sendable {
        case weapon, unarmed, ranged, shadow
        var index: Int { Self.allCases.firstIndex(of: self)! }
    }
    public struct Poison: Equatable, Sendable {
        public fileprivate(set) var amount = 0.0
        public fileprivate(set) var remainingTicks = 0
        public var damagePerTick: Double { remainingTicks > 0 ? amount / 900 : 0 }
    }
    public struct Perks: Equatable, Sendable {
        public var poison = 0.0
        public var cobraDance = 0.0
        public var venomousLimbs = 0.0
        public var secretRitual = 0.0
        public init(poison: Double = 0, cobraDance: Double = 0,
                    venomousLimbs: Double = 0, secretRitual: Double = 0) {
            self.poison = poison; self.cobraDance = cobraDance
            self.venomousLimbs = venomousLimbs; self.secretRitual = secretRitual
        }
        var isValid: Bool {
            [poison, cobraDance, venomousLimbs, secretRitual].allSatisfy {
                $0.isFinite && (0...1_000_000).contains($0)
            }
        }
        func contribution(_ channel: Channel) -> Double {
            switch channel {
            case .weapon: return poison + cobraDance
            case .unarmed: return venomousLimbs + cobraDance
            case .ranged: return 0
            case .shadow: return secretRitual
            }
        }
    }
    /// Original PostHit guards also accept non-PostHit event families. Such
    /// events must be deliberately classified by the source-event adapter.
    public enum ContactEvent: Sendable { case postHit, otherSourceEvent }
    /// Only events delivered to the original Hit listener may use this rule.
    /// A ModHP status is not an alternative source Hit event.
    public enum HitEvent: Sendable { case hit, otherSourceEvent }
    public enum BloomTier: Int, Sendable { case empty, abilities, barkskin, lifeDrain, full }

    public let level: Int
    public let raidDamageAmplifier: Double
    public private(set) var roundActive = false
    public private(set) var bloom = 0.0
    public private(set) var lastPoisonChannel: Channel?
    public private(set) var bottleUsed = false
    public private(set) var bottleAwaitingRelease = false
    public private(set) var poisonAbilityCooldownRemaining = 0
    public private(set) var barkskinStacks = 0
    public private(set) var barkskinRechargeRemaining = 0
    public private(set) var lifeDrainActive = false
    /// Source ModHP applied during the most recent accepted live status tick.
    /// Reading this value never advances its timer or grants another heal.
    public private(set) var healingThisTick = 0.0
    private var barkskinActive = false
    private var lifeDrainTriggerRemaining = 0
    private var lifeDrainStatusRemaining = 0
    private var lifeDrainStatusPerTick = 0.0
    private var stores = Array(repeating: Poison(), count: 4)
    private var buffTicks = Array(repeating: 0, count: 4)

    public init?(level: Int, raidDamageAmplifier: Double) {
        // The numeric bound is an application input guard, not a source stat.
        guard (2...6).contains(level), raidDamageAmplifier.isFinite,
              raidDamageAmplifier > 0, raidDamageAmplifier <= 1_000_000 else { return nil }
        self.level = level; self.raidDamageAmplifier = raidDamageAmplifier
    }
    public var poisonCap: Double { 0.2 * raidDamageAmplifier }
    public var explosionMultiplier: Double { level >= 5 ? 4.5 : 2.75 }
    public var poisonAbilityCooldownTicks: Int { level >= 5 ? 420 : 960 }
    public var bloomTier: BloomTier {
        if bloom >= 1 { return .full }
        if bloom >= 0.75 { return .lifeDrain }
        if bloom >= 0.5 { return .barkskin }
        if bloom >= 0.25 { return .abilities }
        return .empty
    }
    public func poison(_ channel: Channel) -> Poison { stores[channel.index] }
    public func poisonBuffRemaining(_ channel: Channel) -> Int { buffTicks[channel.index] }
    /// The full input evaluator must additionally enforce controls, intervals
    /// and source equipment tags. This only checks this component's stores/CD.
    public var hasStoredPoison: Bool { stores.contains { $0.amount > 0 } }
    public func coefficient(_ channel: Channel) -> Double {
        (channel == .ranged ? 0.45 : 0.35) * (level >= 3 ? 1.3 : 1)
    }
    public mutating func beginRound() {
        roundActive = true; healingThisTick = 0
        activateBloomPassives()
    }
    public mutating func endRound() { roundActive = false; healingThisTick = 0; interruptBottle() }
    public mutating func resetMatch() {
        roundActive = false; bloom = 0; lastPoisonChannel = nil
        bottleUsed = false; bottleAwaitingRelease = false
        poisonAbilityCooldownRemaining = 0
        barkskinActive = false; barkskinStacks = 0; barkskinRechargeRemaining = 0
        lifeDrainActive = false; lifeDrainTriggerRemaining = 0
        lifeDrainStatusRemaining = 0; lifeDrainStatusPerTick = 0; healingThisTick = 0
        stores = Array(repeating: Poison(), count: 4)
        buffTicks = Array(repeating: 0, count: 4)
    }
    private func contactAllowed(_ event: ContactEvent, first: Bool, invisible: Bool) -> Bool {
        event == .otherSourceEvent || first || invisible
    }
    /// Lock 1389/2 replaces positive f59 after PreHit damage calculation and
    /// any earlier SetHit replacement. Preserve the fraction until the target's
    /// actual health-domain boundary; this is not a power or poison modifier.
    public func outgoingHitDamage(_ calculatedDamage: Double, event: HitEvent = .hit,
                                  first: Bool = true, invisible: Bool = false) -> Double {
        guard roundActive, calculatedDamage.isFinite, calculatedDamage > 0,
              event == .otherSourceEvent || first || invisible else { return calculatedDamage }
        return calculatedDamage * 0.66
    }
    private func excluded(_ tag: String?) -> Bool {
        tag == "Hit_D13_Poison_Ability_End" || tag == "Hit_D13_Bloom"
    }
    private mutating func addPoison(_ channel: Channel, amount: Double) {
        let i = channel.index
        stores[i].amount = min(poisonCap, stores[i].amount + amount)
        stores[i].remainingTicks = 900
        lastPoisonChannel = channel
    }
    /// Positive f59, accepted PostHit and the proper attack type are required.
    /// Perks enter before the channel multiplier, as in the original RPN.
    @discardableResult
    public mutating func outgoingContact(channel: Channel, sourceDamage: Double,
        event: ContactEvent = .postHit, first: Bool = true, invisible: Bool = false,
        hitTag: String? = nil, perks: Perks = .init()) -> Bool {
        guard roundActive, sourceDamage.isFinite, sourceDamage > 0,
              sourceDamage <= 1_000_000, perks.isValid,
              contactAllowed(event, first: first, invisible: invisible) else { return false }
        if !excluded(hitTag) {
            bloom = min(1, bloom + sourceDamage / raidDamageAmplifier * 0.45)
            activateBloomPassives()
        }
        if channel != .shadow || !excluded(hitTag) {
            addPoison(channel, amount: (sourceDamage + perks.contribution(channel)) * coefficient(channel))
        }
        return true
    }
    /// Incoming f59 is already in the owner's normalized domain. Unlike the
    /// outgoing expression, lock 1384/2 does not divide it by f213.
    @discardableResult
    public mutating func incomingContact(sourceDamage: Double, event: ContactEvent = .postHit,
                                         first: Bool = true, invisible: Bool = false) -> Bool {
        guard roundActive, sourceDamage.isFinite, sourceDamage > 0,
              sourceDamage <= 1_000_000,
              contactAllowed(event, first: first, invisible: invisible) else { return false }
        bloom = min(1, bloom + sourceDamage * 0.45)
        activateBloomPassives()
        return true
    }
    /// Lock 1389/5,12: threshold events and RoundFightStart share the same
    /// one-time activation guards. Do not refill consumed layers on every hit,
    /// or restart a running life-drain timer when another Bloom event arrives.
    private mutating func activateBloomPassives() {
        guard roundActive else { return }
        if bloom >= 0.5 && !barkskinActive {
            barkskinActive = true; barkskinStacks = 6; barkskinRechargeRemaining = 0
        }
        if bloom >= 0.75 && !lifeDrainActive {
            lifeDrainActive = true; lifeDrainTriggerRemaining = 30
        }
    }
    /// One accepted first PreHit, after resolving the original BLOCK flag.
    /// Locks 1389/6-7 read the old stack count, then consume one layer. The
    /// returned value multiplies Head/BodyDefense, not received HP damage.
    @discardableResult
    public mutating func prepareIncomingContact(blocked: Bool) -> Double {
        guard roundActive, !blocked, barkskinStacks > 0 else { return 1 }
        let previous = barkskinStacks
        if previous == 6 { barkskinRechargeRemaining = 300 }
        barkskinStacks -= 1
        return 1 + Double(previous) * 0.33
    }
    /// Lock 1400's four cloud callbacks are separate contacts, not a single
    /// all-channel grant. Their hit/zone schedule belongs to the model adapter.
    @discardableResult
    public mutating func poisonBombCloudPulse(_ channel: Channel, targetInvincible: Bool) -> Bool {
        guard roundActive, level >= 6, !targetInvincible else { return false }
        addPoison(channel, amount: 0.02 * raidDamageAmplifier)
        return true
    }
    /// One completed source status tick; caller must not invoke during frozen
    /// simulation time. Returns source ModHP magnitude, not integer hit points.
    /// Accumulated amounts are not drained: only the independent lifetime ends.
    public mutating func advanceStatusTick() -> Double {
        guard roundActive else { return 0 }
        healingThisTick = 0
        if poisonAbilityCooldownRemaining > 0 { poisonAbilityCooldownRemaining -= 1 }
        for i in buffTicks.indices where buffTicks[i] > 0 { buffTicks[i] -= 1 }
        var damage = 0.0
        for i in stores.indices where stores[i].remainingTicks > 0 {
            damage += stores[i].damagePerTick
            stores[i].remainingTicks -= 1
            if stores[i].remainingTicks == 0 { stores[i].amount = 0 }
        }
        // Lock 1389/10-11 replenishes one layer every 300 live ticks. A
        // subsequent hit while below six layers does not postpone recharge.
        if barkskinRechargeRemaining > 0 {
            barkskinRechargeRemaining -= 1
            if barkskinRechargeRemaining == 0 && barkskinStacks < 6 {
                barkskinStacks += 1
                if barkskinStacks < 6 { barkskinRechargeRemaining = 300 }
            }
        }
        // A status created by a timer event begins on the next live tick, as
        // with the existing poison statuses. Its source rate is captured for
        // that 30-tick segment, not recomputed from later poison changes.
        if lifeDrainStatusRemaining > 0 {
            healingThisTick = lifeDrainStatusPerTick
            lifeDrainStatusRemaining -= 1
            if lifeDrainStatusRemaining == 0 { lifeDrainStatusPerTick = 0 }
        }
        if lifeDrainActive && lifeDrainTriggerRemaining > 0 {
            lifeDrainTriggerRemaining -= 1
            if lifeDrainTriggerRemaining == 0 {
                let poison = stores.reduce(0) { $0 + $1.amount }
                lifeDrainStatusPerTick = (0.01 + poison / 900 * 0.01) / 30
                lifeDrainStatusRemaining = 30; lifeDrainTriggerRemaining = 30
            }
        }
        return damage
    }
    /// Projection of lock 1379/16 only. Buff selection, the separate Bloom
    /// model and later poison-clear events remain distinct caller events.
    public func poisonExplosionDamage(targetInvincible: Bool) -> Double {
        guard roundActive, !targetInvincible else { return 0 }
        return stores.reduce(0) { $0 + $1.amount * explosionMultiplier }
    }
    /// CLEAR_STATUS_VARIABLES does not reset Bloom, bottle usage or buffs.
    public mutating func clearPoisonStores() { stores = Array(repeating: Poison(), count: 4) }

    public struct Explosion: Equatable, Sendable {
        /// ModHP magnitudes in Channel.allCases order, before any source clear.
        public let damageByChannel: [Double]
        public let grantedBuff: Channel?
        public let cooldownStarted: Bool
        public var damage: Double { damageByChannel.reduce(0, +) }
    }
    /// Original strict maximum, with a special capped/last-type tie break.
    /// Equal non-capped stores deliberately do not select a channel.
    public var dominantPoisonChannel: Channel? {
        Channel.allCases.first { channel in
            let value = stores[channel.index].amount
            return value > 0 && ((value == poisonCap && lastPoisonChannel == channel) ||
                Channel.allCases.filter { $0 != channel }.allSatisfy { value > stores[$0.index].amount })
        }
    }
    /// One accepted SET_D13_POISON_EXPLOSION_KEY notification. The action
    /// runtime owns event de-duplication. Default-priority damage/buff triggers
    /// observe the old stores before priority -5 cleanup/redistribution.
    /// This covers the ordinary level 2–6 equipment-tag path only; the separate
    /// Bloom damage model and enhanced intoxication alias are not substituted.
    public mutating func resolvePoisonExplosionKey(targetInvincible: Bool) -> Explosion? {
        guard roundActive else { return nil }
        let damage = stores.map { targetInvincible ? 0 : $0.amount * explosionMultiplier }
        let selected = dominantPoisonChannel
        if let selected { buffTicks[selected.index] = 900 }
        var started = false
        if poisonAbilityCooldownRemaining == 0 {
            if level < 4 {
                clearPoisonStores(); lastPoisonChannel = nil
                started = true
            } else if let selected {
                let original = stores[selected.index].amount
                for channel in Channel.allCases where channel != selected {
                    let i = channel.index
                    if level >= 6 {
                        stores[i].amount = min(poisonCap, stores[i].amount + original / 3)
                        stores[i].remainingTicks = 900
                    } else {
                        stores[i].amount *= 0.25 // f230 preserves each remaining lifetime.
                    }
                }
                stores[selected.index] = Poison()
                started = true
            }
            if started { poisonAbilityCooldownRemaining = poisonAbilityCooldownTicks }
        }
        return Explosion(damageByChannel: damage, grantedBuff: selected, cooldownStarted: started)
    }

    /// Lock 1400: usage is consumed at D13_Bottle_Throw StageChange, not when
    /// the input button is pressed and not when the later model marker fires.
    @discardableResult
    public mutating func acceptBottleAnimationStart(rangedUsagesLeft: Int) -> Bool {
        guard roundActive, level >= 6, rangedUsagesLeft > 0, !bottleUsed else { return false }
        bottleUsed = true; bottleAwaitingRelease = true
        return true // Adapter applies original a224(-1) exactly once.
    }
    @discardableResult
    public mutating func acceptBottleReleaseMarker() -> Bool {
        guard roundActive, bottleAwaitingRelease else { return false }
        bottleAwaitingRelease = false
        return true // Adapter creates the original equipped Ranged model.
    }
    public mutating func interruptBottle() { bottleAwaitingRelease = false }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.int(level); try writer.double(raidDamageAmplifier)
        try writer.bool(roundActive); try writer.double(bloom)
        try writer.optional(lastPoisonChannel) { try $0.string($1.rawValue) }
        try writer.bool(bottleUsed); try writer.bool(bottleAwaitingRelease)
        try writer.int(poisonAbilityCooldownRemaining)
        for channel in Channel.allCases {
            let value = poison(channel)
            try writer.double(value.amount); try writer.int(value.remainingTicks)
            try writer.int(poisonBuffRemaining(channel))
        }
        try writer.bool(barkskinActive); try writer.int(barkskinStacks)
        try writer.int(barkskinRechargeRemaining); try writer.bool(lifeDrainActive)
        try writer.int(lifeDrainTriggerRemaining); try writer.int(lifeDrainStatusRemaining)
        try writer.double(lifeDrainStatusPerTick); try writer.double(healingThisTick)
    }
}
