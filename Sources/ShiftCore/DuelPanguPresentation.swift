import Foundation

/// Read-only geometry and accepted presentation events from the fixed-step
/// fight. These values are diagnostic bindings, not original Pangu artwork,
/// animation events, or balance data. Sampling never advances the simulation.
public struct DuelPanguPresentation: Equatable, Sendable {
    public typealias Ability = DuelPanguRules.Ability

    public struct VolumeID: Hashable, Sendable {
        public let owner: Int
        public let attackID: UInt64
    }
    public struct Volume: Equatable, Sendable {
        public let id: VolumeID
        public var owner: Int { id.owner }
        public var attackID: UInt64 { id.attackID }
        public let ability: Ability?
        public let delivery: DuelPanguRules.Delivery
        public let damageKind: DuelPanguRules.DamageKind
        public let generated: Bool
        public let empowered: Bool
        public let direction: Int
        /// World metres, matching existing source contact / SceneKit adapters.
        public let center: DuelWeaponPoint
        /// World millimetres. This is the actual instantaneous collision extent;
        /// projectile sweep history is not represented as a persistent shape.
        public let bounds: DuelGame.Box
        public let radiusMillimeters: Int
        public let expiresAtTick: Int
    }
    public struct Pillar: Equatable, Sendable {
        public let owner: Int
        public let xMillimeters: Int
        public let heightMillimeters: Int
        public let targetHeightMillimeters: Int
        public let isDescending: Bool
    }
    public struct Control: Equatable, Sendable {
        public enum Kind: String, Sendable { case stun, petrify, pinned, airHeld, dread }
        public let target: Int
        public let kind: Kind
        public let bounds: DuelGame.Box
        public let expiresAtTick: Int
        /// Spatial controls have an inclusive last active tick.
        public let remainingTicks: Int
    }
    public struct Cast: Equatable, Sendable {
        public let owner: Int
        public let id: UInt64
        public let ability: Ability
        public let phase: DuelPanguState.Phase
        public let tick: Int
        public let duration: Int
        public let empowered: Bool
        /// The caster's authoritative external origin in world metres.
        public let position: DuelWeaponPoint
    }
    public struct Contact: Equatable, Sendable {
        public let owner: Int
        public let target: Int
        /// Nil for an ordinary weapon / unarmed contact by a Pangu fighter.
        public let attackID: UInt64?
        public let ability: Ability?
        public let delivery: DuelPanguRules.Delivery?
        public let damageKind: DuelPanguRules.DamageKind
        public let generated: Bool
        public let empowered: Bool
        public let kind: DuelWeaponFight.Contact.Kind
        public let position: DuelWeaponPoint
        public let direction: Int
    }
    public struct EventID: Hashable, Sendable {
        /// Fight.frame is monotonic across rounds, unlike the spatial live tick.
        /// A new match must reset the renderer's consumed-event cache.
        public let frame: Int
        public let sequence: Int
    }
    public struct Event: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case attackReleased(Volume)
            case contact(Contact)
            case controlApplied(Control)
            case controlReleased(target: Int, kind: Control.Kind)
            case teleported(owner: Int, from: DuelWeaponPoint, to: DuelWeaponPoint)
            case pillarStarted(Pillar)
            case descentStarted(Pillar)
            case landed(owner: Int, position: DuelWeaponPoint)
            case ordinaryThrowEscaped(attacker: Int, target: Int, position: DuelWeaponPoint)
            case castStarted(Cast)
            case castPhase(owner: Int, ability: Ability, phase: DuelPanguState.Phase)
            case castEnded(owner: Int, ability: Ability, interrupted: Bool)
        }
        public let id: EventID
        public let liveTick: Int
        public let kind: Kind
    }

    /// Presentation overflow drops later feedback only. It never limits or
    /// changes gameplay effects, damage, RNG, or canonical replay bytes.
    public static let maximumEventsPerStep = 128
    public let liveTick: Int
    public let volumes: [Volume]
    public let pillars: [Pillar]
    public let controls: [Control]
    public let casts: [Cast]

    static func empty(liveTick: Int) -> Self {
        .init(liveTick: liveTick, volumes: [], pillars: [], controls: [], casts: [])
    }

    init(space: DuelPanguSpatialState, fighters: [DuelGame.Fighter],
         hurts: [DuelGame.Box], states: [DuelPanguState?]) {
        liveTick = space.tick
        volumes = space.volumes.filter { !$0.spent && space.tick <= $0.expiresAt }.map {
            Self.volume($0, fighter: fighters[$0.owner])
        }
        pillars = fighters.indices.compactMap { owner in
            space.lifts[owner].map { Self.pillar($0, owner: owner, fighter: fighters[owner]) }
        }
        controls = fighters.indices.flatMap { target in
            Self.controls(space.controls[target], target: target, hurt: hurts[target], liveTick: space.tick)
        }
        casts = fighters.indices.compactMap { owner in
            states[owner]?.activeCast.map { Self.cast($0, owner: owner, fighter: fighters[owner]) }
        }
    }

    private init(liveTick: Int, volumes: [Volume], pillars: [Pillar], controls: [Control], casts: [Cast]) {
        self.liveTick = liveTick; self.volumes = volumes; self.pillars = pillars
        self.controls = controls; self.casts = casts
    }

    static func volume(_ volume: DuelPanguSpatialState.Volume, fighter: DuelGame.Fighter) -> Volume {
        let bounds = volume.currentBounds(fighter: fighter)
        return .init(id: .init(owner: volume.owner, attackID: volume.attack.id),
            ability: volume.attack.ability, delivery: volume.attack.delivery, damageKind: volume.attack.damageKind,
            generated: volume.attack.generated, empowered: volume.attack.empowered, direction: volume.direction,
            center: .init(x: Double(bounds.minX + bounds.maxX) / 2000,
                          y: Double(bounds.minY + bounds.maxY) / 2000),
            bounds: bounds, radiusMillimeters: volume.attack.radiusMillimeters, expiresAtTick: volume.expiresAt)
    }
    static func pillar(_ lift: DuelPanguSpatialState.Lift, owner: Int, fighter: DuelGame.Fighter) -> Pillar {
        .init(owner: owner, xMillimeters: fighter.x, heightMillimeters: lift.height,
              targetHeightMillimeters: lift.targetHeight, isDescending: lift.fallingSpeed > 0)
    }
    static func cast(_ cast: DuelPanguState.Cast, owner: Int, fighter: DuelGame.Fighter) -> Cast {
        .init(owner: owner, id: cast.id, ability: cast.ability, phase: cast.phase, tick: cast.tick,
              duration: cast.duration, empowered: cast.empowered,
              position: .init(x: Double(fighter.x) / 1000, y: Double(fighter.y) / 1000))
    }
    static func controls(_ control: DuelPanguSpatialState.Control, target: Int,
                         hurt: DuelGame.Box, liveTick: Int) -> [Control] {
        guard liveTick > 0 else { return [] }
        let entries: [(Control.Kind, Int)] = [(.stun, control.stunUntil), (.petrify, control.petrifyUntil),
            (.pinned, control.pinUntil), (.airHeld, control.airUntil), (.dread, control.dreadUntil)]
        return entries.compactMap { kind, until in
            guard until >= liveTick else { return nil }
            return .init(target: target, kind: kind, bounds: hurt, expiresAtTick: until,
                         remainingTicks: until - liveTick + 1)
        }
    }
}
