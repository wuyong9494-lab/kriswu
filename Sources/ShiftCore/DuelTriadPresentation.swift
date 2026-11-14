import Foundation

/// A read-only projection for original H17 effect bindings, HUD and acceptance
/// tools. Rendering this value never calls a gameplay state transition.
public struct DuelTriadPresentation: Equatable, Sendable {
    /// Original model/animation lifecycle, separate from combat outcomes. An
    /// owner swing is not a projectile birth and a soul hit is not its exit.
    public enum SourceEvent: Equatable, Sendable {
        public enum ModelKind: String, Codable, Sendable { case roots, mistWave, heraldBlast }
        case modelCreated(id: UInt64, kind: ModelKind, origin: DuelTriadState.Origin)
        case rootModelEnded(id: UInt64)
        case soulModelCreated(id: UInt64, move: DuelTriadRules.SummonMove)
        case soulAnimationEnded(id: UInt64, role: String)
        /// This arena starts combat immediately. Its first-round ambience
        /// adapter does not claim to have played H17's original intro clip.
        case arenaForestLoopStarted(roundID: Int)
        case roundStarted(roundID: Int)
        case roundFightEnded
    }
    public struct Summon: Equatable, Sendable {
        public let id: UInt64
        public let owner: Int
        public let soul: DuelTriadRules.Soul
        public let origin: DuelTriadState.Origin
        public let age: Int
        public let duration: Int
        public let xMillimeters: Int
        public let yMillimeters: Int
        public let zMillimeters: Int
        public let direction: Int
        public let sourceMove: DuelTriadRules.SummonMove?
        public let sourceAnimation: DuelTriadRules.SoulAnimation?
        public let motionTick: Int
        public let lastSampleTick: Int
        public var motionRole: String {
            sourceAnimation?.role ?? sourceMove?.role ??
                (origin == .hungrySoul ? DuelTriadRules.SummonMove.legionDefender.role :
                    DuelTriadRules.Ability(rawValue: soul.rawValue)!.motionRole)
        }
    }
    public struct Volume: Equatable, Sendable {
        public let owner: Int
        public let attackID: UInt64
        public let ability: DuelTriadRules.Ability
        public let origin: DuelTriadState.Origin
        public let delivery: DuelTriadRules.Delivery
        public let bounds: DuelGame.Box
        public let direction: Int
        public let remainingTicks: Int
        /// Model creation uses its release-time transform. It cannot follow
        /// the owner or the opponent after the independent model is born.
        public var sourceModelKind: SourceEvent.ModelKind? = nil
        public var sourceOrigin: DuelWeaponPoint? = nil
    }
    public struct Control: Equatable, Sendable {
        public enum Kind: String, Sendable { case root, stun, suppression }
        public let target: Int
        public let kind: Kind
        public let remainingTicks: Int
        public let stacks: Int
        public let bounds: DuelGame.Box
    }
    public struct Contact: Equatable, Sendable {
        public let owner: Int
        public let target: Int
        public let attackID: UInt64?
        public let ability: DuelTriadRules.Ability?
        public let kind: DuelWeaponFight.Contact.Kind
        public let position: DuelWeaponPoint
        public let direction: Int
        public let critical: Bool
    }
    public struct Event: Equatable, Sendable {
        public struct ID: Equatable, Sendable {
            public let frame: Int
            public let sequence: Int
        }
        public enum Kind: Equatable, Sendable {
            case castStarted(owner: Int, cast: DuelTriadState.Cast)
            case attackReleased(Volume)
            case contact(Contact)
            case effect(owner: Int, effect: DuelTriadState.Effect)
            case source(owner: Int, event: SourceEvent)
        }
        public let id: ID
        public let liveTick: Int
        public let kind: Kind
        /// Captured before an AnimationEnd trigger changes the same soul's
        /// motion. End effects therefore use that original final source pose.
        public var sourceSummon: Summon? = nil
    }
    public static let maximumEventsPerStep = 128
    public let liveTick: Int
    public let volumes: [Volume]
    public let summons: [Summon]
    public let controls: [Control]

    public static func empty(liveTick: Int) -> Self { .init(liveTick: liveTick, volumes: [], summons: [], controls: []) }
    static func volume(_ value: DuelTriadSpatialState.Volume, liveTick: Int) -> Volume {
        .init(owner: value.owner, attackID: value.attack.id, ability: value.attack.ability,
            origin: value.attack.origin, delivery: value.attack.delivery, bounds: value.bounds,
            direction: value.direction, remainingTicks: max(0, value.expiresAt - liveTick))
    }
    static func summon(_ value: DuelTriadSpatialState.Summon, liveTick: Int) -> Summon {
        .init(id: value.id, owner: value.owner, soul: value.soul, origin: value.origin,
            age: max(0, liveTick - value.bornAt), duration: value.expiresAt - value.bornAt,
            xMillimeters: value.x + value.motionBaseX, yMillimeters: value.y, zMillimeters: value.z,
            direction: value.direction, sourceMove: value.sourceMove, sourceAnimation: value.sourceAnimation,
            motionTick: max(0, liveTick - value.motionBeganAt), lastSampleTick: value.lastSampleTick)
    }
    init(space: DuelTriadSpatialState, hurts: [DuelGame.Box], states: [DuelTriadState?]) {
        liveTick = space.tick
        volumes = space.volumes.map { Self.volume($0, liveTick: space.tick) }
        summons = space.summons.map { Self.summon($0, liveTick: space.tick) }
        var controls: [Control] = []
        for i in 0..<2 {
            let value = space.controls[i]
            if value.rooted(at: space.tick) {
                controls.append(.init(target: i, kind: .root, remainingTicks: value.rootUntil - space.tick + 1,
                    stacks: 1, bounds: hurts[i]))
            }
            if value.stunUntil >= space.tick && space.tick > 0 {
                controls.append(.init(target: i, kind: .stun, remainingTicks: value.stunUntil - space.tick + 1,
                    stacks: 1, bounds: hurts[i]))
            }
            if let state = states[1 - i], state.suppressionStacks > 0 {
                controls.append(.init(target: i, kind: .suppression, remainingTicks: state.suppressionRemainingTicks,
                    stacks: state.suppressionStacks, bounds: hurts[i]))
            }
        }
        self.controls = controls
    }
    private init(liveTick: Int, volumes: [Volume], summons: [Summon], controls: [Control]) {
        self.liveTick = liveTick; self.volumes = volumes; self.summons = summons; self.controls = controls
    }
}
