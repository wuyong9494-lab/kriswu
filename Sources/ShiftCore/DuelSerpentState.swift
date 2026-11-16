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
    public enum BloomTier: Int, Sendable { case empty, abilities, barkskin, lifeDrain, full }

    public let level: Int
    public let raidDamageAmplifier: Double
    public private(set) var roundActive = false
    public private(set) var bloom = 0.0
    public private(set) var lastPoisonChannel: Channel?
    public private(set) var bottleUsed = false
    public private(set) var bottleAwaitingRelease = false
    private var stores = Array(repeating: Poison(), count: 4)

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
    public func coefficient(_ channel: Channel) -> Double {
        (channel == .ranged ? 0.45 : 0.35) * (level >= 3 ? 1.3 : 1)
    }
    public mutating func beginRound() { roundActive = true }
    public mutating func endRound() { roundActive = false; interruptBottle() }
    public mutating func resetMatch() {
        roundActive = false; bloom = 0; lastPoisonChannel = nil
        bottleUsed = false; bottleAwaitingRelease = false
        stores = Array(repeating: Poison(), count: 4)
    }
    private func contactAllowed(_ event: ContactEvent, first: Bool, invisible: Bool) -> Bool {
        event == .otherSourceEvent || first || invisible
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
        return true
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
        var damage = 0.0
        for i in stores.indices where stores[i].remainingTicks > 0 {
            damage += stores[i].damagePerTick
            stores[i].remainingTicks -= 1
            if stores[i].remainingTicks == 0 { stores[i].amount = 0 }
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
}
