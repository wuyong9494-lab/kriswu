import Foundation

/// Offline fighting laboratory. All gameplay uses integer units and 60 Hz ticks;
/// rendering time, SceneKit physics and animation callbacks never decide a hit.
public struct DuelGame: Equatable, Sendable {
    public enum Hero: String, CaseIterable, Codable, Sendable {
        case ember, gale, liu
        case wuYong = "wuyong_erlang"
        public var name: String {
            switch self { case .ember: return "孙登"; case .gale: return "徐骁"; case .liu: return "刘泉纬"; case .wuYong: return "吴庸" }
        }
        public var style: String {
            switch self {
            case .ember: return "午夜影移 · 双短忍刀与瞬闪"
            case .gale: return "圣殿审判 · 圣光柱与圣痕"
            case .liu: return "诺娜狂斧 · 灵兽与烈焰形态"
            case .wuYong: return "暗影幕府 · 野太刀与死士"
            }
        }
        public var skill1Name: String {
            switch self { case .ember: return "影铃幻步"; case .gale: return "救赎圣光"; case .liu: return "灵枭扑击"; case .wuYong: return "无情突踢" }
        }
        public var skill2Name: String {
            switch self { case .ember: return "瞬闪防反"; case .gale: return "圣裁重斩"; case .liu: return "烈焰形态"; case .wuYong: return "死士突袭" }
        }
        public var skillHelp: String {
            switch self {
            case .ember: return "双短忍刀疾袭；出招落空或影铃幻步自动触发「影移虚化」躲避伤害并回能；瞬闪防反可瞬移至背后回血；满能施放「抹除」瞬移必杀并清空对手能量。"
            case .gale: return "十字大剑远程压制；救赎圣光召唤圣光柱并烙印「圣痕」，倒计时或连击终结引爆浮空；圣光伤害吸血并燃烧对手能量；满圣光开启「圣光形态」全攻击破防。"
            case .liu: return "双手巨斧重击附带军团霸体；3连击或霸体承伤自动召唤「花焰灵狼」；灵枭扑击可二次召回定身；怒火≥30即可提前进入「烈焰形态」全武器破防，对手低于25%血量触发真身斩杀。"
            case .wuYong: return "野太刀长距压制；长按重击蓄力必暴击；无情突踢附带霸体；死士突袭可在出招或受击时眩晕对手；暗影蓄满 100 自动入影、达 200 爆发暗影灾变决杀。"
            }
        }
    }
    public enum Difficulty: String, CaseIterable, Codable, Sendable { case learning, challenging }
    public enum Mode: String, Codable, Sendable { case versus, practice, tutorial }
    public struct Buttons: OptionSet, Codable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let jump = Self(rawValue: 1), light = Self(rawValue: 2), heavy = Self(rawValue: 4)
        public static let skill1 = Self(rawValue: 8), skill2 = Self(rawValue: 16)
        public static let ultimate = Self(rawValue: 32)
    }
    public struct Input: Equatable, Codable, Sendable {
        public var move: Int
        public var guardHeld: Bool
        public var taps: Buttons
        public var vertical: Int
        public var weaponCommand: DuelWeaponCommand?
        public var rangedHeld: Bool
        public var heavyHeld: Bool
        public init(move: Int = 0, guardHeld: Bool = false, taps: Buttons = [], vertical: Int = 0,
                    weaponCommand: DuelWeaponCommand? = nil, rangedHeld: Bool = false, heavyHeld: Bool = false) {
            self.move = min(1, max(-1, move)); self.guardHeld = guardHeld; self.taps = taps
            self.vertical = min(1, max(-1, vertical)); self.weaponCommand = weaponCommand
            self.rangedHeld = rangedHeld; self.heavyHeld = heavyHeld
        }
        private enum CodingKeys: String, CodingKey { case move, guardHeld, taps, vertical, weaponCommand, rangedHeld, heavyHeld }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(move: try c.decodeIfPresent(Int.self, forKey: .move) ?? 0,
                      guardHeld: try c.decodeIfPresent(Bool.self, forKey: .guardHeld) ?? false,
                      taps: try c.decodeIfPresent(Buttons.self, forKey: .taps) ?? [],
                      vertical: try c.decodeIfPresent(Int.self, forKey: .vertical) ?? 0,
                      weaponCommand: try c.decodeIfPresent(DuelWeaponCommand.self, forKey: .weaponCommand),
                      rangedHeld: try c.decodeIfPresent(Bool.self, forKey: .rangedHeld) ?? false,
                      heavyHeld: try c.decodeIfPresent(Bool.self, forKey: .heavyHeld) ?? false)
        }
        public static let neutral = Input()
    }
    public enum Move: String, Codable, Sendable {
        case jab, cross, finisher, heavy, skill1, skill2, ultimate
        case shogunFierceReprisal, shogunDespotism
        case inquisitorLightSpin, midnightRemoval
    }
    public struct Attack: Equatable, Sendable {
        public let move: Move
        public var age = 0
        public var connected = false
        public var spawned = false
        public var comboQueued = false
        public var chargeTicks = 0
        public init(move: Move, age: Int = 0, connected: Bool = false, spawned: Bool = false,
                    comboQueued: Bool = false, chargeTicks: Int = 0) {
            self.move = move; self.age = age; self.connected = connected
            self.spawned = spawned; self.comboQueued = comboQueued; self.chargeTicks = chargeTicks
        }
    }
    public struct Fighter: Equatable, Sendable {
        public let hero: Hero
        public var x: Int
        public var y = 0
        public var velocityY = 0
        public var facing: Int
        public var health = 1000
        public var guardMeter = 1000
        public var energy = 100
        public var stun = 0
        public var knockdown = 0
        public var invulnerable = 0
        public var guarding = false
        public var attack: Attack?
        public var flash = 0
        public var walking = false
        public var movementDirection = 0
        public var weaponPose: DuelWeaponPose?
    }
    public struct Projectile: Equatable, Sendable {
        public let id: Int
        public let owner: Int
        public var x: Int
        public let direction: Int
        public var lifetime = 65
    }
    public enum Phase: Equatable, Sendable {
        case fighting
        case roundBreak(winner: Int?, remaining: Int)
        case matchOver(winner: Int)
    }
    public enum Event: Equatable, Sendable {
        case hit(attacker: Int, damage: Int), blocked(defender: Int), guardBreak(defender: Int)
        case whiff(attacker: Int), jumped(player: Int), roundEnded(winner: Int?)
        case grappleStarted(attacker: Int), grappleSlam(attacker: Int), grappleReleased(attacker: Int), grappleClash
        case shogunShadowForm(fighter: Int), shogunCataclysm(fighter: Int)
        case shogunCataclysmStrike(attacker: Int, damage: Int)
        case shogunCompanionHit(owner: Int, damage: Int)
        case shogunArmorAbsorbed(defender: Int), shogunRevived(fighter: Int)
        case shogunCritical(attacker: Int, damage: Int)
        case inquisitorStigmataApplied(defender: Int)
        case inquisitorStigmataFlash(attacker: Int, damage: Int)
        case inquisitorFormOfLight(fighter: Int)
        case nonnaFlameForm(fighter: Int)
        case nonnaWolfHit(owner: Int, damage: Int)
        case nonnaOwlHit(owner: Int, damage: Int, returned: Bool)
        case nonnaTrueShapeExecute(attacker: Int, damage: Int)
        case midnightShadowShift(fighter: Int)
        case midnightBlinkCounter(attacker: Int, damage: Int)
        case midnightRemovalStrike(attacker: Int, damage: Int)
    }
    /// Presentation reads this timeline; no animation callback can extend a hold.
    public struct Grapple: Equatable, Sendable {
        public enum Stage: Equatable, Sendable { case takedown, hold, release }
        public let attacker: Int
        public let direction: Int
        public var age = 0
        public static let takedownTicks = 24, holdTicks = 180, releaseTicks = 24
        public static var duration: Int { takedownTicks + holdTicks + releaseTicks }
        public var stage: Stage {
            age < Self.takedownTicks ? .takedown : age < Self.takedownTicks + Self.holdTicks ? .hold : .release
        }
        public var holdRemaining: Int { max(0, Self.takedownTicks + Self.holdTicks - max(age, Self.takedownTicks)) }
    }
    public struct MoveData: Equatable, Sendable {
        public let startup: Int, active: Int, recovery: Int, reach: Int, damage: Int, push: Int
        public let knockdown: Bool
        public let hitStop: Int
        public let armorStart: Int
        public let armorEnd: Int
        public let absorbsFrontDamage: Bool
        public let guardMultiplierBps: Int
        public let stunTicks: Int
        public let shadowGain: Int
        public let isShadow: Bool
        public let isCritical: Bool
        public init(startup: Int, active: Int, recovery: Int, reach: Int, damage: Int, push: Int,
                    knockdown: Bool, hitStop: Int = 5, armorStart: Int = -1, armorEnd: Int = -1,
                    absorbsFrontDamage: Bool = false, guardMultiplierBps: Int = 20000, stunTicks: Int = 17,
                    shadowGain: Int = 0, isShadow: Bool = false, isCritical: Bool = false) {
            self.startup = startup; self.active = active; self.recovery = recovery
            self.reach = reach; self.damage = damage; self.push = push; self.knockdown = knockdown
            self.hitStop = hitStop; self.armorStart = armorStart; self.armorEnd = armorEnd
            self.absorbsFrontDamage = absorbsFrontDamage; self.guardMultiplierBps = guardMultiplierBps
            self.stunTicks = stunTicks; self.shadowGain = shadowGain
            self.isShadow = isShadow; self.isCritical = isCritical
        }
        public var duration: Int { startup + active + recovery }
    }
    public struct Box: Equatable, Sendable {
        public let minX: Int, maxX: Int, minY: Int, maxY: Int
        public func overlaps(_ other: Box) -> Bool {
            minX <= other.maxX && maxX >= other.minX && minY < other.maxY && maxY > other.minY
        }
    }
    public func hurtBox(_ index: Int) -> Box {
        if let weaponFight { return weaponFight.hurtBox(index) }
        let f = fighters[index]
        return Box(minX: f.x - 310, maxX: f.x + 310, minY: f.y + 275, maxY: f.y + 1525)
    }
    public func attackBox(_ index: Int) -> Box? {
        if let weaponFight { return weaponFight.attackBox(index) }
        let f = fighters[index]
        guard grapple == nil, let attack = f.attack, !(f.hero == .gale && attack.move == .skill1) else { return nil }
        let data = Self.data(attack.move, hero: f.hero, chargeTicks: attack.chargeTicks)
        guard attack.age >= data.startup && attack.age < data.startup + data.active else { return nil }
        return rangeBox(index, reach: data.reach)
    }
    private func rangeBox(_ index: Int, reach: Int) -> Box {
        let f = fighters[index], near = f.x + f.facing * 200, far = f.x + f.facing * (reach - 310)
        return Box(minX: min(near, far), maxX: max(near, far), minY: f.y + 275, maxY: f.y + 1525)
    }
    public static let ticksPerSecond = 60
    public static let jumpVelocity = 235, gravity = 18
    public static let leftWall = 550, rightWall = 9450, bodyWidth = 620
    public let selectedHero: Hero
    public let difficulty: Difficulty
    public let mode: Mode
    public private(set) var fighters: [Fighter]
    public private(set) var projectiles: [Projectile] = []
    public private(set) var grapple: Grapple?
    public private(set) var phase: Phase = .fighting
    public private(set) var frame = 0
    public private(set) var remainingTicks = 60 * 60
    public private(set) var wins = [0, 0]
    public private(set) var hitStop = 0
    public private(set) var events: [Event] = []
    public private(set) var landedHits = [0, 0]
    public private(set) var damageDealt = [0, 0]
    public private(set) var weaponFight: DuelWeaponFight?
    public private(set) var shogunStates: [DuelShogunState?]
    public private(set) var arenaKitStates: [DuelArenaKitState?]
    private var random: UInt64
    private var nextProjectile = 0
    private var botHeld = Input.neutral
    private var buffered: [Buttons] = [[], []]
    private let opponentHero: Hero
    private let weaponModeRequested: Bool

    public init(hero: Hero = .ember, difficulty: Difficulty = .learning, mode: Mode = .versus, seed: UInt64 = 20261107,
                opponentHero: Hero? = nil, weaponCatalog: DuelWeaponCatalog? = nil) {
        selectedHero = hero; self.difficulty = difficulty; self.mode = mode; random = seed
        weaponModeRequested = weaponCatalog != nil
        self.opponentHero = opponentHero ?? (weaponCatalog != nil ? (hero == .liu ? .ember : .liu) : (hero == .gale ? .ember : .gale))
        var initialFighters = [Fighter(hero: hero, x: 3500, facing: 1),
                               Fighter(hero: self.opponentHero, x: 6500, facing: -1)]
        if weaponCatalog == nil {
            for i in initialFighters.indices where initialFighters[i].hero == .wuYong {
                initialFighters[i].energy = 0
            }
        }
        fighters = initialFighters
        shogunStates = initialFighters.map {
            $0.hero == .wuYong && weaponCatalog == nil ? DuelShogunState(ownerX: $0.x, ownerFacing: $0.facing) : nil
        }
        arenaKitStates = initialFighters.map { fighter in
            guard weaponCatalog == nil else { return nil }
            switch fighter.hero {
            case .gale: return .inquisitor(DuelInquisitorState())
            case .liu: return .nonna(DuelNonnaState())
            case .ember: return .midnight(DuelMidnightState())
            case .wuYong: return nil
            }
        }
        if let weaponCatalog {
            weaponFight = DuelWeaponFight(fighters: fighters, mode: mode, difficulty: difficulty,
                                           catalog: weaponCatalog, seed: seed)
            if let weaponFight { fighters = weaponFight.fighters }
        }
    }
    public func shogunState(_ index: Int) -> DuelShogunState? {
        guard weaponFight == nil, shogunStates.indices.contains(index) else { return nil }
        return shogunStates[index]
    }
    public func inquisitorState(_ index: Int) -> DuelInquisitorState? {
        guard weaponFight == nil, arenaKitStates.indices.contains(index),
              case .inquisitor(let state) = arenaKitStates[index] else { return nil }
        return state
    }
    public func nonnaState(_ index: Int) -> DuelNonnaState? {
        guard weaponFight == nil, arenaKitStates.indices.contains(index),
              case .nonna(let state) = arenaKitStates[index] else { return nil }
        return state
    }
    public func midnightState(_ index: Int) -> DuelMidnightState? {
        guard weaponFight == nil, arenaKitStates.indices.contains(index),
              case .midnight(let state) = arenaKitStates[index] else { return nil }
        return state
    }
    public var round: Int { wins.reduce(0, +) + 1 }
    /// Pause/interruption cancels future commands, without undoing a move that
    /// already started. Hit-stop buffers and queued combo links are input too.
    public mutating func cancelBufferedInputs() {
        weaponFight?.cancelBufferedInputs()
        buffered = [[], []]
        for i in fighters.indices {
            fighters[i].attack?.comboQueued = false
            shogunStates[i]?.heavyChargeTicks = 0
        }
        botHeld = .neutral
    }
    public static func data(_ move: Move, hero: Hero, chargeTicks: Int = 0) -> MoveData {
        if hero == .wuYong {
            switch move {
            case .jab:
                return .init(startup: 7, active: 4, recovery: 13, reach: 1320, damage: 80, push: 130,
                             knockdown: false, hitStop: 4, shadowGain: 16)
            case .cross:
                return .init(startup: 8, active: 4, recovery: 15, reach: 1460, damage: 95, push: 160,
                             knockdown: false, hitStop: 5, shadowGain: 20)
            case .finisher:
                return .init(startup: 11, active: 5, recovery: 24, reach: 1620, damage: 135, push: 410,
                             knockdown: true, hitStop: 7, shadowGain: 26)
            case .heavy:
                let clamped = min(DuelShogunState.heavyMaxChargeTicks, max(0, chargeTicks))
                let isFull = clamped >= DuelShogunState.heavyFullChargeTicks
                let extraReach = min(420, (clamped * 420) / DuelShogunState.heavyFullChargeTicks)
                let extraDamage = isFull ? 125 : (clamped * 85) / DuelShogunState.heavyFullChargeTicks
                return .init(startup: isFull ? 14 : 18, active: 6, recovery: 28, reach: 1680 + extraReach,
                             damage: 175 + extraDamage, push: isFull ? 580 : 480, knockdown: true,
                             hitStop: isFull ? 12 : 8, guardMultiplierBps: isFull ? 44000 : 24000,
                             stunTicks: isFull ? 24 : 19, shadowGain: isFull ? 36 : 24, isCritical: isFull)
            case .skill1:
                // Ruthless Advance: Legion-style 3-step unbreakable advancing kick.
                return .init(startup: 10, active: 10, recovery: 26, reach: 1280, damage: 145, push: 320,
                             knockdown: false, hitStop: 6, armorStart: 4, armorEnd: 20, shadowGain: 22)
            case .skill2:
                return .init(startup: 10, active: 8, recovery: 16, reach: 1080, damage: 75, push: 160,
                             knockdown: false, hitStop: 6, stunTicks: DuelShogunState.companionStunTicks)
            case .shogunFierceReprisal:
                // Forward Shadow Ability: Fierce Reprisal (Odachi dash slash).
                return .init(startup: 12, active: 10, recovery: 26, reach: 1650, damage: 210, push: 520,
                             knockdown: true, hitStop: 10, armorStart: 6, armorEnd: 22,
                             guardMultiplierBps: 32000, stunTicks: 22, isShadow: true)
            case .shogunDespotism:
                // Back Shadow Ability: Despotism (front damage absorption + telekinetic pull + upper slash).
                return .init(startup: 9, active: 8, recovery: 25, reach: 2600, damage: 185, push: 560,
                             knockdown: true, hitStop: 9, armorStart: 0, armorEnd: 17,
                             absorbsFrontDamage: true, guardMultiplierBps: 30000, stunTicks: 22, isShadow: true)
            case .ultimate, .inquisitorLightSpin, .midnightRemoval:
                return .init(startup: 12, active: 10, recovery: 26, reach: 1650, damage: 210, push: 520,
                             knockdown: true, hitStop: 10, isShadow: true)
            }
        }
        let long = hero == .gale ? 240 : 0
        switch move {
        case .jab: return .init(startup: 6, active: 3, recovery: 13, reach: 1030 + long, damage: 75, push: 110, knockdown: false)
        case .cross: return .init(startup: 7, active: 3, recovery: 15, reach: 1170 + long, damage: 90, push: 130, knockdown: false)
        case .finisher: return .init(startup: 10, active: 4, recovery: 23, reach: 1280 + long, damage: 125, push: 380, knockdown: true)
        case .heavy:
            if hero == .liu {
                // Nonna Legion Great Axe: Unbreakable hyper-armor during windup & strike.
                return .init(startup: 19, active: 5, recovery: 29, reach: 1450, damage: 165, push: 450,
                             knockdown: true, hitStop: 8, armorStart: 6, armorEnd: 18)
            }
            return .init(startup: 19, active: 5, recovery: 29, reach: 1450 + long, damage: 165, push: 450, knockdown: true)
        case .skill1: return .init(startup: hero == .gale ? 18 : 11, active: 5, recovery: 26, reach: 1200, damage: 135, push: 260, knockdown: false)
        case .skill2:
            if hero == .gale {
                // Grand Inquisitor Deliverance Scar: unbreakable heavy holy cleave.
                return .init(startup: 8, active: 5, recovery: 32, reach: 1550, damage: 155, push: 430,
                             knockdown: true, hitStop: 7, armorStart: 4, armorEnd: 13)
            }
            return .init(startup: 8, active: 5, recovery: 32, reach: 1550, damage: 155, push: 430, knockdown: true)
        case .inquisitorLightSpin:
            // Tower's Dogma: invulnerable Form of Light spinning slash.
            return .init(startup: 6, active: 10, recovery: 16, reach: 1500, damage: 160, push: 440,
                         knockdown: true, hitStop: 8, armorStart: 0, armorEnd: 16, guardMultiplierBps: 50000)
        case .midnightRemoval:
            // Midnight Removal: teleportation execute slashing shadow energy away.
            return .init(startup: 12, active: 6, recovery: 22, reach: 2800, damage: DuelMidnightState.removalDamage,
                         push: 520, knockdown: true, hitStop: 11, guardMultiplierBps: 45000, isShadow: true, isCritical: true)
        case .ultimate, .shogunFierceReprisal, .shogunDespotism:
            return .init(startup: 24, active: 5, recovery: 45, reach: 1050, damage: 0, push: 0, knockdown: false)
        }
    }

    /// A replay needs only the original configuration, seed and this input stream.
    /// Passing opponent input is useful for deterministic local tests and future replay tools.
    public mutating func step(_ player: Input, opponent: Input? = nil) {
        if case .matchOver = phase { return }
        if var fight = weaponFight {
            fight.step(player, opponent: opponent); weaponFight = fight
            fighters = fight.fighters; phase = fight.phase; frame = fight.frame
            remainingTicks = fight.remainingTicks; wins = fight.wins; hitStop = fight.hitStop
            events = fight.events; landedHits = fight.landedHits; damageDealt = fight.damageDealt
            projectiles = []; grapple = nil
            return
        }
        // Invalid equipped resources cannot silently turn into the common
        // laboratory moveset. The native session presents its resource error.
        if weaponModeRequested { events.removeAll(keepingCapacity: true); return }
        events.removeAll(keepingCapacity: true)
        advance(player, opponent: opponent)
    }
    private mutating func advance(_ player: Input, opponent: Input?) {
        frame += 1
        if case .roundBreak(_, let remaining) = phase {
            if remaining <= 1 { resetRound() }
            else if case .roundBreak(let winner, _) = phase { phase = .roundBreak(winner: winner, remaining: remaining - 1) }
            return
        }
        if grapple != nil {
            // Both fighters are occupied. Discard taps instead of replaying them
            // after release; the round timer is held during this fixed cinematic.
            buffered = [[], []]; botHeld = .neutral
            advanceGrapple(); resolveRound(); return
        }
        let other = opponent ?? (mode == .versus ? botInput() : .neutral)
        let inputs = [player, other]
        for i in 0..<2 { buffered[i].formUnion(inputs[i].taps) }
        if hitStop > 0 { hitStop -= 1; return }
        if mode == .versus { remainingTicks -= 1 }
        for i in 0..<2 { updateFighter(i, input: inputs[i], taps: buffered[i]); buffered[i] = [] }
        separateBodies()
        // Collect all contacts before applying any: simultaneous active attacks can trade.
        var contacts: [(attacker: Int, move: Move, data: MoveData, direction: Int, isCompanion: Bool)] = []
        var grabs: [Int] = []
        for i in 0..<2 {
            guard var attack = fighters[i].attack else { continue }
            let data = Self.data(attack.move, hero: fighters[i].hero, chargeTicks: attack.chargeTicks)
            // Despotism telekinetic pull draws a mid/close opponent toward the planted Odachi.
            if fighters[i].hero == .wuYong && attack.move == .shogunDespotism && attack.age == 5 {
                let defender = 1 - i
                let dist = (fighters[defender].x - fighters[i].x) * fighters[i].facing
                if dist > 760 && dist <= data.reach && fighters[defender].knockdown == 0 && fighters[defender].invulnerable == 0 {
                    let pull = min(dist - 760, 480)
                    fighters[defender].x = min(Self.rightWall, max(Self.leftWall, fighters[defender].x - fighters[i].facing * pull))
                    separateBodies()
                }
            }
            // Midnight Removal: turn transparent & teleport onto the opponent right before the execute slash!
            if fighters[i].hero == .ember && attack.move == .midnightRemoval && attack.age == 9 {
                let defender = 1 - i
                let desiredX = fighters[defender].x - fighters[i].facing * 680
                fighters[i].x = min(Self.rightWall, max(Self.leftWall, desiredX))
                fighters[i].invulnerable = max(fighters[i].invulnerable, 10)
                separateBodies()
            }
            let active = attack.age >= data.startup && attack.age < data.startup + data.active
            if attack.move == .ultimate {
                if active && !attack.connected && canGrapple(i) { grabs.append(i) }
            } else if fighters[i].hero == .gale && attack.move == .skill1 {
                if active && !attack.spawned {
                    nextProjectile += 1
                    projectiles.append(.init(id: nextProjectile, owner: i, x: fighters[i].x + fighters[i].facing * 650, direction: fighters[i].facing))
                    attack.spawned = true
                }
            } else if active && !attack.connected && canHit(i, reach: data.reach) {
                contacts.append((i, attack.move, data, fighters[i].facing, false)); attack.connected = true
            }
            fighters[i].attack = attack
        }
        // Check Shogun asynchronous companion active strikes.
        for i in 0..<2 {
            guard var shogun = shogunStates[i], shogun.companionPhase == .strike, !shogun.companionHitApplied else { continue }
            let target = fighters[1 - i]
            let distance = (target.x - shogun.companionX) * shogun.companionFacing
            if distance >= -220 && distance <= DuelShogunState.companionStrikeReach &&
                target.y < 1100 && target.knockdown == 0 && target.invulnerable == 0 {
                shogun.companionHitApplied = true
                shogunStates[i] = shogun
                contacts.append((i, .skill2, Self.data(.skill2, hero: .wuYong), shogun.companionFacing, true))
            }
        }
        // Advance Nonna autonomous Spirit Wolf & Fire Grip Spirit Owl, and Inquisitor Stigmata countdown.
        advanceArenaEntities()
        for index in projectiles.indices.reversed() {
            projectiles[index].x += projectiles[index].direction * 135
            projectiles[index].lifetime -= 1
            let p = projectiles[index], target = fighters[1 - p.owner]
            if abs(p.x - target.x) < 440 && target.y < 1100 && target.knockdown == 0 && target.invulnerable == 0 {
                contacts.append((p.owner, .skill1, Self.data(.skill1, hero: .gale), p.direction, false))
                projectiles.remove(at: index)
            } else if p.lifetime <= 0 || p.x < 0 || p.x > 10000 { projectiles.remove(at: index) }
        }
        for contact in contacts {
            applyHit(from: contact.attacker, move: contact.move, data: contact.data,
                     direction: contact.direction, isCompanion: contact.isCompanion)
        }
        // A strike on the same tick interrupts a grab. Mirrored simultaneous
        // grabs break apart symmetrically rather than favoring array index zero.
        grabs = grabs.filter { fighters[$0].attack?.move == .ultimate && canGrapple($0) }
        if grabs.count == 2 {
            for i in 0..<2 { fighters[i].attack = nil; fighters[i].stun = 18 }
            events.append(.grappleClash); hitStop = 4
        } else if let attacker = grabs.first {
            beginGrapple(attacker)
            resolveRound(); return
        }
        for i in 0..<2 {
            if var attack = fighters[i].attack {
                attack.age += 1
                let data = Self.data(attack.move, hero: fighters[i].hero, chargeTicks: attack.chargeTicks)
                if attack.age >= data.duration {
                    let whiffed = !attack.connected && !attack.spawned
                    if whiffed {
                        events.append(.whiff(attacker: i))
                        // Midnight Shadow Shift: whiffing an attack phases Sun Deng out of this dimension!
                        if case .midnight(var mid) = arenaKitStates[i] {
                            mid.enterShadowShift()
                            arenaKitStates[i] = .midnight(mid)
                            events.append(.midnightShadowShift(fighter: i))
                        }
                        // Midnight Best Agent: opponent whiffing nearby grants bonus Shadow Energy!
                        let foe = 1 - i
                        if case .midnight(var foeMid) = arenaKitStates[foe], abs(fighters[0].x - fighters[1].x) < 2200 {
                            foeMid.gainShadow(DuelMidnightState.whiffShadowReward)
                            arenaKitStates[foe] = .midnight(foeMid)
                            fighters[foe].energy = min(100, fighters[foe].energy + 12)
                        }
                    } else if attack.move == .skill1, case .midnight(var mid) = arenaKitStates[i] {
                        // Midnight Distant Shift: Phantom Bell / Kunai skill always triggers Shadow Shift!
                        mid.enterShadowShift()
                        arenaKitStates[i] = .midnight(mid)
                        events.append(.midnightShadowShift(fighter: i))
                    }
                    if attack.comboQueued && attack.connected && attack.move != .finisher {
                        fighters[i].attack = Attack(move: attack.move == .jab ? .cross : .finisher)
                    } else { fighters[i].attack = nil }
                } else { fighters[i].attack = attack }
            }
            if let shogun = shogunStates[i] {
                fighters[i].energy = shogun.shadowEnergy
            }
        }
        resolveRound()
    }

    private mutating func resolveRound() {
        if mode != .versus {
            guard grapple == nil else { return }
            for i in 0..<2 where fighters[i].health == 0 || (fighters[i].knockdown == 0 && fighters[i].stun == 0) {
                fighters[i].health = 1000
            }
        } else if fighters.contains(where: { $0.health <= 0 }) || remainingTicks <= 0 {
            let winner: Int? = fighters[0].health == fighters[1].health ? nil : (fighters[0].health > fighters[1].health ? 0 : 1)
            if let winner { wins[winner] += 1 }
            events.append(.roundEnded(winner: winner))
            projectiles.removeAll(); buffered = [[], []]; grapple = nil; hitStop = 0
            for i in 0..<2 {
                fighters[i].attack = nil; fighters[i].guarding = false
                shogunStates[i]?.heavyChargeTicks = 0
            }
            if let winner, wins[winner] == 2 { phase = .matchOver(winner: winner) }
            else { phase = .roundBreak(winner: winner, remaining: 120) }
        }
    }

    private mutating func awardShogunShadow(to owner: Int, amount: Int) {
        guard var shogun = shogunStates[owner], amount > 0 else { return }
        let transitioned = shogun.gainShadowEnergy(amount)
        shogunStates[owner] = shogun
        fighters[owner].energy = shogun.shadowEnergy
        if let transitioned {
            handleShogunPhaseTransition(owner: owner, phase: transitioned)
        }
    }

    private mutating func handleShogunPhaseTransition(owner: Int, phase: DuelShogunState.ShadowPhase) {
        switch phase {
        case .normal: break
        case .shadowForm:
            events.append(.shogunShadowForm(fighter: owner))
        case .cataclysm:
            events.append(.shogunCataclysm(fighter: owner))
            let opponent = 1 - owner
            let delta = fighters[opponent].x - fighters[owner].x
            if abs(delta) <= DuelShogunState.cataclysmEruptionRange && fighters[opponent].knockdown == 0 {
                let sign = delta >= 0 ? 1 : -1
                fighters[opponent].x = min(Self.rightWall, max(Self.leftWall, fighters[opponent].x + sign * DuelShogunState.cataclysmEruptionPush))
            }
            hitStop = max(hitStop, 6)
        }
    }

    private mutating func updateShogunCompanion(_ i: Int, taps: Buttons) {
        guard var shogun = shogunStates[i] else { return }
        shogun.shadowAbilityCooldown = max(0, shogun.shadowAbilityCooldown - 1)
        shogun.ruthlessKickCooldown = max(0, shogun.ruthlessKickCooldown - 1)
        shogun.cataclysmPulseTicks = max(0, shogun.cataclysmPulseTicks - 1)
        shogun.defenseBonusTicks = max(0, shogun.defenseBonusTicks - 1)
        shogun.opponentDefenseDebuffTicks = max(0, shogun.opponentDefenseDebuffTicks - 1)
        if shogun.shadowPhase == .cataclysm {
            shogun.cataclysmTicks += 1
            if shogun.cataclysmTicks >= DuelShogunState.cataclysmMaxTicks {
                shogun.shadowPhase = .normal
                shogun.shadowEnergy = 0
                shogun.cataclysmTicks = 0
            }
        } else if frame % 24 == 0 && shogun.shadowEnergy < DuelShogunState.maxShadowEnergy {
            if let transitioned = shogun.gainShadowEnergy(1) {
                shogunStates[i] = shogun
                handleShogunPhaseTransition(owner: i, phase: transitioned)
                shogun = shogunStates[i]!
            }
        }
        if shogun.agonyRemainingTicks > 0 {
            shogun.agonyRemainingTicks -= 1
            if shogun.agonyRemainingTicks == 0 {
                shogun.companionPhase = .unconscious
                shogun.companionTimer = 0
                shogun.companionCooldown = 0
            }
        }
        if shogun.companionPhase != .unconscious {
            shogun.companionCooldown = max(0, shogun.companionCooldown - 1)
            let foe = fighters[1 - i]
            // Absolute Power: Shogun can command his companion even while attacking or stunned.
            if taps.contains(.skill2) && shogun.isCompanionAvailable && fighters[i].health > 0 && fighters[i].knockdown == 0 {
                shogun.companionPhase = .windup
                shogun.companionTimer = 0
                shogun.companionHitApplied = false
                shogun.companionFacing = foe.x >= shogun.companionX ? 1 : -1
            } else {
                switch shogun.companionPhase {
                case .follow:
                    let toward = foe.x >= shogun.companionX ? 1 : -1
                    shogun.companionFacing = toward
                    let desiredX = foe.x - toward * DuelShogunState.companionTargetGap
                    let delta = desiredX - shogun.companionX
                    let speed = shogun.agonyRemainingTicks > 0
                        ? DuelShogunState.companionAgonyFollowSpeed
                        : DuelShogunState.companionFollowSpeed
                    if abs(delta) <= speed { shogun.companionX = desiredX }
                    else { shogun.companionX += (delta > 0 ? 1 : -1) * speed }
                    shogun.companionX = min(Self.rightWall, max(Self.leftWall, shogun.companionX))
                case .windup:
                    shogun.companionTimer += 1
                    shogun.companionFacing = foe.x >= shogun.companionX ? 1 : -1
                    if shogun.companionTimer >= DuelShogunState.companionWindupTicks {
                        shogun.companionPhase = .strike
                        shogun.companionTimer = 0
                        shogun.companionHitApplied = false
                    }
                case .strike:
                    shogun.companionTimer += 1
                    shogun.companionX = min(Self.rightWall, max(Self.leftWall, shogun.companionX + shogun.companionFacing * 45))
                    if shogun.companionTimer >= DuelShogunState.companionStrikeTicks {
                        shogun.companionPhase = .recover
                        shogun.companionTimer = 0
                    }
                case .recover:
                    shogun.companionTimer += 1
                    if shogun.companionTimer >= DuelShogunState.companionRecoverTicks {
                        shogun.companionPhase = .follow
                        shogun.companionTimer = 0
                        shogun.companionCooldown = shogun.agonyRemainingTicks > 0
                            ? DuelShogunState.companionAgonyCooldownTicks
                            : DuelShogunState.companionCooldownTicks
                    }
                case .unconscious:
                    break
                }
            }
        }
        shogunStates[i] = shogun
    }

    private mutating func advanceArenaEntities() {
        for i in 0..<2 {
            let defender = 1 - i
            switch arenaKitStates[i] {
            case .inquisitor(var inq):
                if inq.stigmataTicks > 0 {
                    inq.stigmataTicks -= 1
                    if inq.stigmataTicks == 0 {
                        arenaKitStates[i] = .inquisitor(inq)
                        detonateInquisitorStigmata(attacker: i)
                        continue
                    }
                }
                arenaKitStates[i] = .inquisitor(inq)

            case .nonna(var nonna):
                if nonna.wolfActive {
                    nonna.wolfTimer += 1
                    nonna.wolfX = min(Self.rightWall, max(Self.leftWall, nonna.wolfX + nonna.wolfFacing * DuelNonnaState.wolfSpeed))
                    let target = fighters[defender]
                    if !nonna.wolfHitApplied && abs(nonna.wolfX - target.x) < 440 &&
                        target.y < 1050 && target.knockdown == 0 && target.invulnerable == 0 {
                        nonna.wolfHitApplied = true
                        nonna.gainFlame(DuelNonnaState.wolfFlameGain)
                        arenaKitStates[i] = .nonna(nonna)
                        let wolfDmg = DuelNonnaState.wolfDamage
                        let wolfData = MoveData(startup: 0, active: 1, recovery: 0, reach: 500,
                                                damage: wolfDmg, push: 320, knockdown: false, hitStop: 5, stunTicks: 22)
                        applyHit(from: i, move: .skill1, data: wolfData, direction: nonna.wolfFacing, isCompanion: true)
                        events.append(.nonnaWolfHit(owner: i, damage: wolfDmg))
                        if case .nonna(let updated) = arenaKitStates[i] { nonna = updated }
                    }
                    if nonna.wolfTimer >= DuelNonnaState.wolfMaxTicks ||
                        nonna.wolfX <= Self.leftWall || nonna.wolfX >= Self.rightWall {
                        nonna.wolfActive = false
                    }
                }
                if nonna.owlPhase != .idle {
                    nonna.owlTimer += 1
                    let target = fighters[defender]
                    switch nonna.owlPhase {
                    case .idle: break
                    case .outbound:
                        nonna.owlX = min(Self.rightWall, max(Self.leftWall, nonna.owlX + nonna.owlFacing * DuelNonnaState.owlSpeed))
                        if !nonna.owlHitOut && abs(nonna.owlX - target.x) < 420 &&
                            target.y < 1150 && target.knockdown == 0 && target.invulnerable == 0 {
                            nonna.owlHitOut = true
                            nonna.owlPhase = .latched
                            nonna.owlTimer = 0
                            // Perch just past the struck target so manual/auto recall streaks back through them!
                            nonna.owlX = min(Self.rightWall, max(Self.leftWall, target.x + nonna.owlFacing * 360))
                            nonna.gainFlame(15)
                            arenaKitStates[i] = .nonna(nonna)
                            let owlData = MoveData(startup: 0, active: 1, recovery: 0, reach: 420,
                                                   damage: DuelNonnaState.owlOutDamage, push: 120, knockdown: false, hitStop: 4, stunTicks: 14)
                            applyHit(from: i, move: .skill1, data: owlData, direction: nonna.owlFacing, isCompanion: true)
                            events.append(.nonnaOwlHit(owner: i, damage: DuelNonnaState.owlOutDamage, returned: false))
                            if case .nonna(let updated) = arenaKitStates[i] { nonna = updated }
                        } else if nonna.owlTimer >= 22 || nonna.owlX <= Self.leftWall || nonna.owlX >= Self.rightWall {
                            nonna.owlPhase = .latched
                            nonna.owlTimer = 0
                        }
                    case .latched:
                        if nonna.owlTimer >= DuelNonnaState.owlLatchMaxTicks {
                            // Legends of the Northlands: Owl automatically returns if not manually recalled.
                            nonna.recallOwl()
                        }
                    case .returning:
                        let ownerX = fighters[i].x
                        let towardOwner = ownerX >= nonna.owlX ? 1 : -1
                        nonna.owlX = min(Self.rightWall, max(Self.leftWall, nonna.owlX + towardOwner * 175))
                        if !nonna.owlHitBack && abs(nonna.owlX - target.x) < 440 &&
                            target.y < 1150 && target.knockdown == 0 && target.invulnerable == 0 {
                            nonna.owlHitBack = true
                            nonna.gainFlame(15)
                            arenaKitStates[i] = .nonna(nonna)
                            let retData = MoveData(startup: 0, active: 1, recovery: 0, reach: 440,
                                                   damage: DuelNonnaState.owlReturnDamage, push: 180, knockdown: false,
                                                   hitStop: 6, stunTicks: DuelNonnaState.owlReturnStunTicks)
                            applyHit(from: i, move: .skill1, data: retData, direction: towardOwner, isCompanion: true)
                            events.append(.nonnaOwlHit(owner: i, damage: DuelNonnaState.owlReturnDamage, returned: true))
                            if case .nonna(let updated) = arenaKitStates[i] { nonna = updated }
                        }
                        if abs(nonna.owlX - ownerX) <= 220 || nonna.owlTimer >= 40 {
                            // Flame Tongues: if both out and return hit, recharge immediately!
                            nonna.owlCooldown = (nonna.owlHitOut && nonna.owlHitBack) ? 0 : DuelNonnaState.owlCooldownTicks
                            nonna.owlPhase = .idle
                            nonna.owlTimer = 0
                        }
                    }
                }
                arenaKitStates[i] = .nonna(nonna)

            case .midnight, .none:
                break
            }
        }
    }

    private mutating func detonateInquisitorStigmata(attacker: Int) {
        let defender = 1 - attacker
        guard case .inquisitor(var inq) = arenaKitStates[attacker] else { return }
        let damage = inq.stigmataFlashDamage
        inq.dispelStigmata()
        inq.gainLight(18)
        arenaKitStates[attacker] = .inquisitor(inq)

        var target = fighters[defender]
        guard target.health > 0, target.invulnerable == 0 else { return }
        // Purging the Scourge + Sacred Euphoria: Stigmata flash burns energy, heals Xu Xiao, and launches!
        target.health = max(0, target.health - damage)
        target.energy = max(0, target.energy - DuelInquisitorState.stigmataEnergyBurn)
        if var defShogun = shogunStates[defender] {
            defShogun.shadowEnergy = max(0, defShogun.shadowEnergy - DuelInquisitorState.stigmataEnergyBurn)
            target.energy = defShogun.shadowEnergy
            shogunStates[defender] = defShogun
        }
        target.knockdown = 40
        target.stun = 24
        target.attack = nil
        target.guarding = false
        target.flash = 10
        fighters[defender] = target

        fighters[attacker].health = min(1000, fighters[attacker].health + (damage * 25) / 100)
        landedHits[attacker] += 1
        damageDealt[attacker] += damage
        hitStop = max(hitStop, 7)
        events.append(.inquisitorStigmataFlash(attacker: attacker, damage: damage))
        events.append(.hit(attacker: attacker, damage: damage))
    }

    private mutating func updateFighter(_ i: Int, input: Input, taps: Buttons) {
        if shogunStates[i] != nil {
            updateShogunCompanion(i, taps: taps)
        }
        // Tick SF4 hero resource/state timers before action selection.
        var nonnaRecalledOwl = false
        switch arenaKitStates[i] {
        case .inquisitor(var inq):
            if inq.formOfLightTicks > 0 {
                inq.formOfLightTicks -= 1
                inq.lightPower = (inq.formOfLightTicks * DuelInquisitorState.maxLightPower) / DuelInquisitorState.formOfLightDurationTicks
            }
            if fighters[i].health <= DuelInquisitorState.martyrdomThresholdHP && !inq.martyrdomUsed && fighters[i].health > 0 {
                inq.martyrdomUsed = true
                inq.martyrdomRestoreTicks = DuelInquisitorState.martyrdomRestoreDuration
            }
            if inq.martyrdomRestoreTicks > 0 {
                inq.martyrdomRestoreTicks -= 1
                inq.gainLight(1)
            }
            arenaKitStates[i] = .inquisitor(inq)
        case .nonna(var nonna):
            nonna.owlCooldown = max(0, nonna.owlCooldown - 1)
            if nonna.flameFormTicks > 0 {
                nonna.flameFormTicks -= 1
                nonna.flamePower = (nonna.flameFormTicks * DuelNonnaState.maxFlamePower) / DuelNonnaState.flameFormMaxTicks
                if nonna.flameFormTicks == 0 {
                    // The Great Hearth: retain Flame block-break for one final strike!
                    nonna.empoweredStrikeReady = true
                }
            }
            // Manual Owl recall can be triggered at any moment while Owl is out or latched!
            if taps.contains(.skill1) && (nonna.owlPhase == .latched || nonna.owlPhase == .outbound) {
                nonna.recallOwl()
                nonnaRecalledOwl = true
            }
            arenaKitStates[i] = .nonna(nonna)
        case .midnight(var mid):
            mid.shadowShiftTicks = max(0, mid.shadowShiftTicks - 1)
            mid.shadowFormTicks = max(0, mid.shadowFormTicks - 1)
            mid.blinkStanceTicks = max(0, mid.blinkStanceTicks - 1)
            mid.blinkCooldown = max(0, mid.blinkCooldown - 1)
            arenaKitStates[i] = .midnight(mid)
        case .none:
            break
        }

        var f = fighters[i]
        f.flash = max(0, f.flash - 1); f.invulnerable = max(0, f.invulnerable - 1)
        f.stun = max(0, f.stun - 1); f.walking = false; f.movementDirection = 0
        if f.knockdown > 0 {
            f.knockdown -= 1; f.guarding = false
            if f.knockdown == 0 { f.invulnerable = 20 }
        }
        if f.y > 0 || f.velocityY > 0 {
            f.y = max(0, f.y + f.velocityY); f.velocityY -= Self.gravity
            if f.y == 0 { f.velocityY = 0 }
        }
        if f.attack == nil { f.facing = fighters[1 - i].x >= f.x ? 1 : -1 }
        f.guarding = input.guardHeld && f.y == 0 && f.attack == nil && (f.stun == 0 || f.guarding) && f.knockdown == 0
        if !f.guarding { f.guardMeter = min(1000, f.guardMeter + 3) }
        if shogunStates[i] == nil {
            if frame % 12 == 0 { f.energy = min(100, f.energy + 1) }
        } else {
            f.energy = shogunStates[i]?.shadowEnergy ?? 0
        }
        if f.stun > 0 || f.knockdown > 0 || f.guarding || f.y > 0 {
            shogunStates[i]?.heavyChargeTicks = 0
        }
        if f.stun == 0 && f.knockdown == 0 {
            if taps.contains(.jump) && f.y == 0 && f.attack == nil {
                shogunStates[i]?.heavyChargeTicks = 0
                f.velocityY = Self.jumpVelocity; f.guarding = false; events.append(.jumped(player: i))
            }
            if !f.guarding {
                let isChargingHeavy = (shogunStates[i]?.heavyChargeTicks ?? 0) > 0
                let isMidPhased = midnightState(i)?.isPhasedOut == true
                let baseSpeed = isMidPhased ? DuelMidnightState.preciseShiftSpeed : (f.hero == .gale ? 78 : f.hero == .wuYong ? 70 : 68)
                let speed = baseSpeed * (f.attack == nil ? 10 : 4) / 10
                if f.attack?.move != .ultimate && !isChargingHeavy {
                    f.x += min(1, max(-1, input.move)) * speed; f.walking = input.move != 0
                    f.movementDirection = min(1, max(-1, input.move))
                }
                if var attack = f.attack {
                    let data = Self.data(attack.move, hero: f.hero, chargeTicks: attack.chargeTicks)
                    if taps.contains(.light) && attack.age >= data.startup && attack.age < data.duration &&
                        (attack.move == .jab || attack.move == .cross) { attack.comboQueued = true }
                    f.attack = attack
                } else if var shogun = shogunStates[i] {
                    // Wu Yong (Shogun): charged heavy execution, Ruthless Advance kick, and Shadow Abilities.
                    if shogun.heavyChargeTicks > 0 {
                        if input.heavyHeld && shogun.heavyChargeTicks < DuelShogunState.heavyMaxChargeTicks {
                            shogun.heavyChargeTicks += 1
                            f.walking = false; f.movementDirection = 0
                        } else {
                            f.attack = Attack(move: .heavy, chargeTicks: shogun.heavyChargeTicks)
                            shogun.heavyChargeTicks = 0
                        }
                    } else if taps.contains(.ultimate) && shogun.canUseShadowAbility && f.y == 0 && f.velocityY == 0 {
                        let shadowMove: Move = input.move == -f.facing ? .shogunDespotism : .shogunFierceReprisal
                        f.attack = Attack(move: shadowMove)
                        shogun.shadowAbilityCooldown = DuelShogunState.shadowAbilityCooldownTicks
                        f.walking = false
                    } else if taps.contains(.skill1) && shogun.canUseRuthlessKick && f.y == 0 {
                        f.attack = Attack(move: .skill1)
                        shogun.ruthlessKickCooldown = DuelShogunState.ruthlessKickCooldownTicks
                    } else if taps.contains(.heavy) {
                        if input.heavyHeld && f.y == 0 {
                            shogun.heavyChargeTicks = 1
                            f.walking = false; f.movementDirection = 0
                        } else {
                            f.attack = Attack(move: .heavy, chargeTicks: 0)
                        }
                    } else if taps.contains(.light) {
                        f.attack = Attack(move: .jab)
                    }
                    shogunStates[i] = shogun
                } else {
                    var move: Move?
                    // 1. Hero-specific Ultimate / Form activations
                    if taps.contains(.ultimate) && f.y == 0 && f.velocityY == 0 {
                        if f.hero == .liu && f.energy == 100 {
                            move = .ultimate; f.energy = 0; f.walking = false
                        } else if case .inquisitor(var inq) = arenaKitStates[i], inq.canEnterFormOfLight {
                            inq.enterFormOfLight()
                            arenaKitStates[i] = .inquisitor(inq)
                            f.invulnerable = max(f.invulnerable, DuelInquisitorState.entryInvulnerableTicks)
                            events.append(.inquisitorFormOfLight(fighter: i))
                        } else if case .nonna(var nonna) = arenaKitStates[i], nonna.canEnterFlameForm {
                            nonna.enterFlameForm()
                            arenaKitStates[i] = .nonna(nonna)
                            if f.health <= DuelNonnaState.hotBloodThresholdHP {
                                f.invulnerable = max(f.invulnerable, 22)
                            }
                            events.append(.nonnaFlameForm(fighter: i))
                        } else if case .midnight(var mid) = arenaKitStates[i], mid.canUseRemoval {
                            mid.shadowEnergy = 0
                            arenaKitStates[i] = .midnight(mid)
                            move = .midnightRemoval
                            f.walking = false
                        }
                    }
                    // 2. Hero-specific Skill2 (Tower's Dogma / Nonna Flame Form / Midnight Blink)
                    if move == nil && taps.contains(.skill2) {
                        if case .inquisitor(let inq) = arenaKitStates[i], inq.isInFormOfLight {
                            move = .inquisitorLightSpin
                            f.invulnerable = max(f.invulnerable, 16)
                        } else if case .nonna(var nonna) = arenaKitStates[i], nonna.canEnterFlameForm {
                            nonna.enterFlameForm()
                            arenaKitStates[i] = .nonna(nonna)
                            if f.health <= DuelNonnaState.hotBloodThresholdHP {
                                f.invulnerable = max(f.invulnerable, 22)
                            }
                            events.append(.nonnaFlameForm(fighter: i))
                        } else if case .midnight(var mid) = arenaKitStates[i], mid.blinkCooldown == 0, f.energy >= 45 {
                            f.energy -= 45
                            mid.blinkStanceTicks = DuelMidnightState.blinkStanceDurationTicks
                            mid.blinkCooldown = DuelMidnightState.blinkCooldownTicks
                            arenaKitStates[i] = .midnight(mid)
                            f.walking = false
                        } else if f.energy >= 45 {
                            move = .skill2; f.energy -= 45
                        }
                    }
                    // 3. Skill1 / Heavy / Light
                    if move == nil {
                        if taps.contains(.skill1) && !nonnaRecalledOwl && f.energy >= 30 {
                            if case .nonna(var nonna) = arenaKitStates[i] {
                                if nonna.owlPhase == .idle && nonna.owlCooldown == 0 {
                                    nonna.launchOwl(from: f.x, facing: f.facing)
                                    arenaKitStates[i] = .nonna(nonna)
                                    move = .skill1; f.energy -= 30
                                } else {
                                    move = .skill1; f.energy -= 30
                                }
                            } else {
                                move = .skill1; f.energy -= 30
                            }
                        } else if taps.contains(.heavy) {
                            move = .heavy
                        } else if taps.contains(.light) {
                            move = .jab
                        }
                    }
                    if let move { f.attack = Attack(move: move) }
                }
                if let attack = f.attack {
                    if f.hero == .wuYong {
                        if (attack.move == .jab || attack.move == .cross || attack.move == .finisher) &&
                            input.move == f.facing && attack.age < 10 {
                            f.x += f.facing * 42
                        } else if attack.move == .skill1 && attack.age < 16 {
                            f.x += f.facing * 95
                        } else if attack.move == .shogunFierceReprisal && attack.age >= 6 && attack.age < 18 {
                            f.x += f.facing * 145
                        }
                    } else {
                        if attack.move == .skill1, f.hero != .gale, attack.age < 11 { f.x += f.facing * 115 }
                        if attack.move == .skill2, f.hero == .gale, attack.age < 7 { f.x -= f.facing * 85 }
                        if attack.move == .inquisitorLightSpin, attack.age < 12 { f.x += f.facing * 110 }
                    }
                }
            }
        }
        f.x = min(Self.rightWall, max(Self.leftWall, f.x)); fighters[i] = f
    }
    private mutating func separateBodies() {
        guard abs(fighters[0].y - fighters[1].y) < 1250 else { return }
        let gap = fighters[1].x - fighters[0].x
        let overlap = Self.bodyWidth - abs(gap)
        guard overlap > 0 else { return }
        let sign = gap >= 0 ? 1 : -1
        fighters[0].x = min(Self.rightWall, max(Self.leftWall, fighters[0].x - sign * (overlap + 1) / 2))
        fighters[1].x = min(Self.rightWall, max(Self.leftWall, fighters[1].x + sign * (overlap + 1) / 2))
        let residual = Self.bodyWidth - abs(fighters[1].x - fighters[0].x)
        if residual > 0 {
            // Landing can put both centers on the same wall. Resolve the pair
            // inside the arena instead of pushing the second body outside it.
            let left = sign > 0 ? 0 : 1, right = 1 - left
            fighters[left].x = min(fighters[left].x, Self.rightWall - Self.bodyWidth)
            fighters[right].x = fighters[left].x + Self.bodyWidth
        }
    }
    private func canHit(_ attacker: Int, reach: Int) -> Bool {
        let a = fighters[attacker], b = fighters[1 - attacker]
        let distance = (b.x - a.x) * a.facing
        return distance >= 0 && rangeBox(attacker, reach: reach).overlaps(hurtBox(1 - attacker)) && b.knockdown == 0 && b.invulnerable == 0
    }
    private func canGrapple(_ attacker: Int) -> Bool {
        let a = fighters[attacker], b = fighters[1 - attacker]
        let distance = (b.x - a.x) * a.facing
        return a.hero == .liu && a.health > 0 && b.health > 0 && a.y == 0 && a.velocityY == 0 &&
            b.y == 0 && b.velocityY == 0 && b.stun == 0 && b.knockdown == 0 && b.invulnerable == 0 &&
            distance >= 0 && distance <= Self.data(.ultimate, hero: .liu).reach
    }
    private mutating func beginGrapple(_ attacker: Int) {
        let defender = 1 - attacker, direction = fighters[attacker].facing
        // Leave room for the prone silhouette at both walls, and preserve order.
        let center = min(7700, max(2300, (fighters[0].x + fighters[1].x) / 2))
        fighters[attacker].x = center - direction * 475
        fighters[defender].x = center + direction * 475
        for i in 0..<2 {
            fighters[i].y = 0; fighters[i].velocityY = 0; fighters[i].stun = 0
            fighters[i].knockdown = 0; fighters[i].attack = nil; fighters[i].guarding = false
            fighters[i].walking = false; fighters[i].movementDirection = 0; fighters[i].flash = 0
            shogunStates[i]?.heavyChargeTicks = 0
        }
        fighters[attacker].facing = direction; fighters[defender].facing = -direction
        grapple = Grapple(attacker: attacker, direction: direction)
        projectiles.removeAll(); buffered = [[], []]; botHeld = .neutral; hitStop = 0
        events.append(.grappleStarted(attacker: attacker))
    }
    private mutating func advanceGrapple() {
        guard var hold = grapple else { return }
        hold.age += 1; grapple = hold
        for i in 0..<2 { fighters[i].flash = max(0, fighters[i].flash - 1) }
        if hold.age == Grapple.takedownTicks {
            grappleDamage(100, attacker: hold.attacker)
            events.append(.grappleSlam(attacker: hold.attacker))
        }
        if hold.age == Grapple.takedownTicks + Grapple.holdTicks {
            grappleDamage(180, attacker: hold.attacker)
            events.append(.grappleReleased(attacker: hold.attacker))
        }
        if hold.age >= Grapple.duration {
            let attacker = hold.attacker, defender = 1 - attacker
            fighters[defender].x = min(Self.rightWall, max(Self.leftWall, fighters[defender].x + hold.direction * 700))
            fighters[defender].knockdown = 36; fighters[defender].stun = 0
            fighters[attacker].stun = 24
            grapple = nil; buffered = [[], []]; botHeld = .neutral
            separateBodies()
        }
    }
    private mutating func grappleDamage(_ damage: Int, attacker: Int) {
        let defender = 1 - attacker
        let actual = min(damage, fighters[defender].health)
        fighters[defender].health -= actual; fighters[defender].flash = 8
        if fighters[defender].health == 0 { fighters[defender].knockdown = 36 }
        landedHits[attacker] += 1; damageDealt[attacker] += actual
        events.append(.hit(attacker: attacker, damage: actual))
    }
    private mutating func applyHit(from attacker: Int, move: Move, data: MoveData, direction: Int, isCompanion: Bool) {
        let defender = 1 - attacker
        var target = fighters[defender]
        let front = target.facing == -direction

        // 1. Midnight Shadow Shift: phased-out Sun Deng is untouchable and earns Best Agent Shadow Energy!
        if case .midnight(var defMid) = arenaKitStates[defender], defMid.isPhasedOut {
            if !defMid.shiftDodgeRewarded {
                defMid.shiftDodgeRewarded = true
                defMid.gainShadow(DuelMidnightState.dodgeShadowReward)
                target.energy = min(100, target.energy + 15)
                arenaKitStates[defender] = .midnight(defMid)
                fighters[defender] = target
            }
            return
        }

        // 2. Midnight Blink Counter-Stance: negate incoming attack, teleport behind attacker, stab & heal!
        if case .midnight(var defMid) = arenaKitStates[defender], defMid.isInBlinkStance, !isCompanion {
            defMid.blinkStanceTicks = 0
            defMid.gainShadow(DuelMidnightState.blinkCounterShadowReward)
            arenaKitStates[defender] = .midnight(defMid)
            let attackerFacing = fighters[attacker].facing
            let behindX = min(Self.rightWall, max(Self.leftWall, fighters[attacker].x - attackerFacing * 680))
            target.x = behindX
            target.facing = attackerFacing
            target.health = min(1000, target.health + DuelMidnightState.blinkCounterHeal)
            target.invulnerable = max(target.invulnerable, 14)
            target.flash = 6
            fighters[defender] = target

            let counterDmg = DuelMidnightState.blinkCounterDamage
            fighters[attacker].health = max(0, fighters[attacker].health - counterDmg)
            fighters[attacker].stun = 24
            fighters[attacker].knockdown = 32
            fighters[attacker].attack = nil
            fighters[attacker].guarding = false
            fighters[attacker].flash = 10
            landedHits[defender] += 1
            damageDealt[defender] += counterDmg
            hitStop = max(hitStop, 8)
            events.append(.midnightBlinkCounter(attacker: defender, damage: counterDmg))
            events.append(.hit(attacker: defender, damage: counterDmg))
            separateBodies()
            return
        }

        // 3. Overlord of Shadow: Despotism Odachi planted blade absorbs frontal damage.
        if let defAttack = target.attack {
            let defData = Self.data(defAttack.move, hero: target.hero, chargeTicks: defAttack.chargeTicks)
            if defData.absorbsFrontDamage && front && defAttack.age >= defData.armorStart && defAttack.age < defData.armorEnd {
                events.append(.shogunArmorAbsorbed(defender: defender))
                awardShogunShadow(to: defender, amount: 14)
                hitStop = max(hitStop, 4)
                target.flash = 6; fighters[defender] = target
                return
            }
        }

        // 4. Guard check — Grand Inquisitor Form of Light & Nonna Flame Form / Great Hearth BREAK BLOCK!
        let attackerBreaksBlock: Bool = {
            guard !isCompanion else { return false }
            switch arenaKitStates[attacker] {
            case .inquisitor(let inq): return inq.isInFormOfLight
            case .nonna(let nonna): return nonna.breaksBlockNow
            default: return false
            }
        }()

        if target.guarding && front {
            if attackerBreaksBlock {
                // Unblockable Form of Light / Flame Form shatters guard and proceeds to full hit!
                target.guardMeter = 0
                target.guarding = false
                events.append(.guardBreak(defender: defender))
            } else {
                let guardDamage = (data.damage * data.guardMultiplierBps) / 10000
                target.guardMeter = max(0, target.guardMeter - guardDamage)
                target.stun = target.guardMeter == 0 ? 42 : 10
                target.guarding = target.guardMeter > 0
                events.append(target.guardMeter == 0 ? .guardBreak(defender: defender) : .blocked(defender: defender))
                hitStop = max(hitStop, 3)
                if shogunStates[attacker] != nil && !isCompanion {
                    awardShogunShadow(to: attacker, amount: max(4, data.shadowGain / 3))
                }
                if case .inquisitor(var atkInq) = arenaKitStates[attacker], !isCompanion {
                    atkInq.gainLight(6)
                    arenaKitStates[attacker] = .inquisitor(atkInq)
                }
                if case .nonna(var atkNonna) = arenaKitStates[attacker], !isCompanion {
                    atkNonna.gainFlame(6)
                    arenaKitStates[attacker] = .nonna(atkNonna)
                }
                if case .midnight(var atkMid) = arenaKitStates[attacker], !isCompanion {
                    atkMid.gainShadow(6)
                    arenaKitStates[attacker] = .midnight(atkMid)
                }
                target.x = min(Self.rightWall, max(Self.leftWall, target.x + direction * data.push))
                target.flash = 8; fighters[defender] = target
                return
            }
        }

        // Unblocked hit resolution.
        var damage = data.damage
        var effectiveHitStop = data.hitStop
        var cataclysmConsumed = false
        let attackerCataclysm = !isCompanion && shogunStates[attacker]?.isCataclysm == true
        let defenderCataclysm = !isCompanion && shogunStates[defender]?.isCataclysm == true
        if attackerCataclysm {
            if move == .shogunFierceReprisal {
                damage = (damage * 22) / 10 + 90
            } else {
                damage = (damage * 20) / 10
            }
            shogunStates[attacker]?.consumeCataclysm(shogunLandedFirst: true)
            fighters[attacker].energy = 0
            cataclysmConsumed = true
            effectiveHitStop = max(effectiveHitStop, 14)
            events.append(.shogunCataclysmStrike(attacker: attacker, damage: damage))
        } else if defenderCataclysm {
            damage = (damage * 19) / 10
            shogunStates[defender]?.consumeCataclysm(shogunLandedFirst: false)
            target.energy = 0
            cataclysmConsumed = true
            effectiveHitStop = max(effectiveHitStop, 14)
            events.append(.shogunCataclysmStrike(attacker: attacker, damage: damage))
        } else {
            if (shogunStates[attacker]?.opponentDefenseDebuffTicks ?? 0) > 0 {
                damage = (damage * 12) / 10
            }
            if (shogunStates[defender]?.defenseBonusTicks ?? 0) > 0 {
                damage = (damage * 8) / 10
            }
        }

        // Grand Inquisitor Righteousness Blessings defense reduction (2% per blessing, max 24%).
        if !cataclysmConsumed, case .inquisitor(let defInq) = arenaKitStates[defender], defInq.blessings > 0 {
            let pct = max(76, 100 - defInq.blessings * 2)
            damage = max(1, (damage * pct) / 100)
        }

        // Nonna Flame Form True Shape scaling & Survival of the Fittest (<25% HP execute) + Great Hearth!
        var nonnaExecuted = false
        if !isCompanion, case .nonna(var atkNonna) = arenaKitStates[attacker] {
            if atkNonna.isInFlameForm {
                // A Beast Hungry as Flame: bonus True Shape damage proportional to stored Flame!
                let bonus = (atkNonna.flameEntryPower * 55) / 100
                damage += bonus
                effectiveHitStop = max(effectiveHitStop, 9)
                // Survival of the Fittest: execute opponent under 25% HP on clean True Shape hit!
                if target.health > 0 && target.health < DuelNonnaState.executeThresholdHP {
                    damage = target.health
                    nonnaExecuted = true
                    effectiveHitStop = max(effectiveHitStop, 14)
                }
            } else if atkNonna.empoweredStrikeReady {
                atkNonna.empoweredStrikeReady = false
                damage += 35
                arenaKitStates[attacker] = .nonna(atkNonna)
            }
        }

        // Midnight For the Chancellor: Shadow Form dual-blade hits deal +35% Critical Damage!
        var midnightCrit = false
        if !isCompanion, case .midnight(let atkMid) = arenaKitStates[attacker], atkMid.isInShadowForm, move != .midnightRemoval {
            damage = (damage * 135) / 100
            midnightCrit = true
            effectiveHitStop = max(effectiveHitStop, 7)
        }

        // Check unbreakable hyper-armor (Shogun kick / Nonna Great Axe / Inquisitor Deliverance Scar).
        var armored = false
        if !cataclysmConsumed && !nonnaExecuted, let defAttack = target.attack {
            let defData = Self.data(defAttack.move, hero: target.hero, chargeTicks: defAttack.chargeTicks)
            if defData.armorStart >= 0 && defAttack.age >= defData.armorStart && defAttack.age < defData.armorEnd {
                armored = true
                damage = max(1, (damage * 4) / 10)
                events.append(.shogunArmorAbsorbed(defender: defender))
                // Nonna Unbreakable Chieftain: absorbing a hit while Unbreakable immediately summons Spirit Wolf!
                if case .nonna(var defNonna) = arenaKitStates[defender], !defNonna.wolfActive {
                    defNonna.gainFlame(16)
                    defNonna.summonWolf(from: target.x, facing: target.facing)
                    arenaKitStates[defender] = .nonna(defNonna)
                }
            }
        }

        // Overlord of Oppression: cheat death once per round by sacrificing companion into Agony.
        if target.health - damage <= 0, var defShogun = shogunStates[defender],
           !defShogun.reviveUsed, defShogun.companionPhase != .unconscious {
            defShogun.reviveUsed = true
            defShogun.agonyRemainingTicks = DuelShogunState.agonyDurationTicks
            defShogun.companionPhase = .follow
            defShogun.companionTimer = 0
            defShogun.companionCooldown = 0
            shogunStates[defender] = defShogun
            target.health = DuelShogunState.reviveHealth
            target.invulnerable = 30
            target.stun = 0
            target.knockdown = 0
            target.attack = nil
            target.guarding = false
            events.append(.shogunRevived(fighter: defender))
        } else {
            target.health = max(0, target.health - damage)
            if !armored {
                target.stun = data.stunTicks
                target.knockdown = (data.knockdown || nonnaExecuted) ? 43 : 0
                target.attack = nil
                target.guarding = false
                shogunStates[defender]?.heavyChargeTicks = 0
            }
        }

        landedHits[attacker] += 1; damageDealt[attacker] += damage
        events.append(.hit(attacker: attacker, damage: damage))
        if data.isCritical || midnightCrit { events.append(.shogunCritical(attacker: attacker, damage: damage)) }
        if nonnaExecuted { events.append(.nonnaTrueShapeExecute(attacker: attacker, damage: damage)) }

        // Defender Inquisitor counterplay: taking an unblocked hit dispels Stigmata on attacker & knocks out of Form of Light!
        if !armored, case .inquisitor(var defInq) = arenaKitStates[defender] {
            if defInq.hasStigmataOnOpponent { defInq.dispelStigmata() }
            if defInq.isInFormOfLight { defInq.knockOutOfFormOfLight() }
            arenaKitStates[defender] = .inquisitor(defInq)
        }

        if isCompanion {
            if shogunStates[attacker] != nil {
                events.append(.shogunCompanionHit(owner: attacker, damage: damage))
                target.energy = max(0, target.energy - DuelShogunState.companionEnergyDrain)
                if var defShogun = shogunStates[defender] {
                    defShogun.shadowEnergy = max(0, defShogun.shadowEnergy - DuelShogunState.companionEnergyDrain)
                    target.energy = defShogun.shadowEnergy
                    shogunStates[defender] = defShogun
                }
                awardShogunShadow(to: attacker, amount: DuelShogunState.companionShadowGain)
            }
        } else if shogunStates[attacker] != nil {
            if data.isShadow {
                let heal = (damage * 30) / 100
                fighters[attacker].health = min(1000, fighters[attacker].health + heal)
                if !cataclysmConsumed, var atkShogun = shogunStates[attacker], atkShogun.shadowPhase == .shadowForm {
                    atkShogun.enterCataclysm()
                    shogunStates[attacker] = atkShogun
                    fighters[attacker].energy = atkShogun.shadowEnergy
                    handleShogunPhaseTransition(owner: attacker, phase: .cataclysm)
                }
            } else if data.shadowGain > 0 && !cataclysmConsumed {
                awardShogunShadow(to: attacker, amount: data.shadowGain)
            }
        } else {
            // Post-hit SF4 hero state updates for Grand Inquisitor, Nonna, and Midnight!
            switch arenaKitStates[attacker] {
            case .inquisitor(var atkInq):
                if move == .skill1 {
                    // Salvation Light Pillar: apply Stigmata, burn enemy energy, heal Xu Xiao!
                    atkInq.applyStigmata()
                    atkInq.gainLight(18)
                    target.energy = max(0, target.energy - DuelInquisitorState.stigmataEnergyBurn)
                    if var defShogun = shogunStates[defender] {
                        defShogun.shadowEnergy = max(0, defShogun.shadowEnergy - DuelInquisitorState.stigmataEnergyBurn)
                        target.energy = defShogun.shadowEnergy
                        shogunStates[defender] = defShogun
                    }
                    fighters[attacker].health = min(1000, fighters[attacker].health + DuelInquisitorState.salvationHeal)
                    events.append(.inquisitorStigmataApplied(defender: defender))
                    arenaKitStates[attacker] = .inquisitor(atkInq)
                } else {
                    let wasBranded = atkInq.hasStigmataOnOpponent
                    atkInq.gainLight(wasBranded ? 24 : 15)
                    if atkInq.isInFormOfLight {
                        fighters[attacker].health = min(1000, fighters[attacker].health + (damage * 25) / 100)
                        target.energy = max(0, target.energy - 15)
                    }
                    if wasBranded {
                        atkInq.stigmataHits += 1
                    } else if move == .skill2 || move == .inquisitorLightSpin {
                        atkInq.applyStigmata()
                        events.append(.inquisitorStigmataApplied(defender: defender))
                    }
                    let shouldDetonateEarly = wasBranded && !atkInq.isInFormOfLight && move == .finisher
                    arenaKitStates[attacker] = .inquisitor(atkInq)
                    if shouldDetonateEarly {
                        fighters[defender] = target
                        detonateInquisitorStigmata(attacker: attacker)
                        target = fighters[defender]
                    }
                }

            case .nonna(var atkNonna):
                atkNonna.gainFlame(move == .heavy ? 22 : 14)
                if move == .jab {
                    atkNonna.attackSeriesCount = 1
                } else if move == .cross {
                    atkNonna.attackSeriesCount = 2
                } else if move == .finisher || (move == .heavy && atkNonna.isInFlameForm) {
                    atkNonna.attackSeriesCount = 3
                    if !atkNonna.wolfActive {
                        // Blazing Hunt: completing a full attack series summons autonomous Spirit Wolf!
                        atkNonna.summonWolf(from: fighters[attacker].x, facing: fighters[attacker].facing)
                    }
                } else {
                    atkNonna.attackSeriesCount = 0
                }
                arenaKitStates[attacker] = .nonna(atkNonna)

            case .midnight(var atkMid):
                if move == .midnightRemoval {
                    // Terror of the Shadow Squads: burn 100% of opponent's energy/shadow & enter Shadow Form!
                    target.energy = 0
                    if var defShogun = shogunStates[defender] {
                        defShogun.shadowEnergy = 0
                        shogunStates[defender] = defShogun
                    }
                    if case .inquisitor(var defInq) = arenaKitStates[defender] {
                        defInq.lightPower = 0
                        arenaKitStates[defender] = .inquisitor(defInq)
                    }
                    if case .nonna(var defNonna) = arenaKitStates[defender] {
                        defNonna.flamePower = 0
                        arenaKitStates[defender] = .nonna(defNonna)
                    }
                    if case .midnight(var defMid) = arenaKitStates[defender] {
                        defMid.shadowEnergy = 0
                        arenaKitStates[defender] = .midnight(defMid)
                    }
                    atkMid.shadowFormTicks = DuelMidnightState.shadowFormDurationTicks
                    arenaKitStates[attacker] = .midnight(atkMid)
                    events.append(.midnightRemovalStrike(attacker: attacker, damage: damage))
                } else {
                    atkMid.gainShadow(move == .heavy ? 20 : 14)
                    arenaKitStates[attacker] = .midnight(atkMid)
                }
            case .none:
                break
            }
        }

        if shogunStates[defender] != nil && !cataclysmConsumed && target.health > 0 {
            awardShogunShadow(to: defender, amount: 14)
        }

        if move == .shogunDespotism {
            let pulledX = fighters[attacker].x + direction * 760
            target.x = min(Self.rightWall, max(Self.leftWall, pulledX + direction * data.push))
        } else {
            let push = armored ? data.push / 4 : data.push
            target.x = min(Self.rightWall, max(Self.leftWall, target.x + direction * push))
        }
        hitStop = max(hitStop, effectiveHitStop)
        target.flash = 8; fighters[defender] = target
    }
    private mutating func resetRound() {
        var resetFighters = [Fighter(hero: selectedHero, x: 3500, facing: 1),
                             Fighter(hero: opponentHero, x: 6500, facing: -1)]
        for i in resetFighters.indices where resetFighters[i].hero == .wuYong {
            resetFighters[i].energy = 0
        }
        fighters = resetFighters
        shogunStates = resetFighters.map {
            $0.hero == .wuYong ? DuelShogunState(ownerX: $0.x, ownerFacing: $0.facing) : nil
        }
        arenaKitStates = resetFighters.map { fighter in
            switch fighter.hero {
            case .gale: return .inquisitor(DuelInquisitorState())
            case .liu: return .nonna(DuelNonnaState())
            case .ember: return .midnight(DuelMidnightState())
            case .wuYong: return nil
            }
        }
        remainingTicks = 3600; hitStop = 0; buffered = [[], []]; botHeld = .neutral; grapple = nil; phase = .fighting
    }
    private mutating func botInput() -> Input {
        let interval = difficulty == .learning ? 24 : 10
        var input = botHeld; input.taps = []
        guard frame % interval == 0 else { return input }
        random = random &* 6364136223846793005 &+ 1442695040888963407
        let choice = Int((random >> 32) % 100), me = fighters[1], foe = fighters[0]
        let distance = abs(me.x - foe.x), toward = foe.x > me.x ? 1 : -1
        input = .neutral
        let preferred = me.hero == .gale ? 1700 : me.hero == .wuYong ? 1200 : 900
        if distance > preferred { input.move = toward }
        else if me.hero == .gale && distance < 900 { input.move = -toward }
        if foe.attack?.move == .ultimate && distance < 1600 && difficulty == .challenging && choice < 65 {
            input.move = -toward; input.taps = .jump
        }
        else if let shogun = shogunStates[1] {
            if shogun.canUseShadowAbility && distance < 2200 && foe.y == 0 && choice < 55 {
                input.move = distance > 1500 ? -toward : toward
                input.taps = .ultimate
            } else if shogun.isCompanionAvailable && abs(foe.x - shogun.companionX) < 1050 && choice < 50 {
                input.taps = .skill2
            } else if foe.attack != nil && distance < 1250 && shogun.canUseRuthlessKick && choice < 45 {
                input.taps = .skill1
            } else if foe.attack != nil && distance < 1700 && choice < (difficulty == .learning ? 30 : 60) {
                input.guardHeld = true
            } else if distance < 1600 {
                input.taps = choice < 60 ? .light : .heavy
            } else if choice > 92 {
                input.taps = .jump
            }
        }
        else if case .inquisitor(let inq) = arenaKitStates[1], inq.canEnterFormOfLight && foe.y == 0 && choice < 55 {
            input.taps = .ultimate
        }
        else if case .nonna(let nonna) = arenaKitStates[1], nonna.owlPhase == .latched && choice < 65 {
            input.taps = .skill1
        }
        else if case .nonna(let nonna) = arenaKitStates[1], nonna.canEnterFlameForm && distance < 1600 && choice < 45 {
            input.taps = .skill2
        }
        else if case .midnight(let mid) = arenaKitStates[1], mid.canUseRemoval && distance < 2500 && foe.y == 0 && choice < 50 {
            input.taps = .ultimate
        }
        else if me.hero == .liu && me.energy == 100 && distance <= 1000 && foe.y == 0 && choice < 45 { input.taps = .ultimate }
        else if foe.attack != nil && distance < 1700 && choice < (difficulty == .learning ? 30 : 65) { input.guardHeld = true }
        else if distance < 1300 { input.taps = choice < 65 ? .light : choice < 85 ? .heavy : .skill2 }
        else if distance < 4300 && me.energy >= 30 && choice < 55 { input.taps = .skill1 }
        else if choice > 90 { input.taps = .jump }
        botHeld = Input(move: input.move, guardHeld: input.guardHeld)
        return input
    }
}

/// Bound catch-up after a hitch; suspend resets the accumulator so background time
/// cannot advance a fight. Dropped time is reported rather than disguised as 60 FPS.
public struct DuelClock: Sendable {
    public private(set) var accumulator = 0.0
    public private(set) var droppedSeconds = 0.0
    public init() {}
    public mutating func reset() { accumulator = 0 }
    public mutating func consume(seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        let accepted = min(0.1, seconds)
        droppedSeconds += seconds - accepted; accumulator += accepted
        let ticks = min(6, Int((accumulator + 0.000000001) * 60))
        accumulator = max(0, accumulator - Double(ticks) / 60)
        return ticks
    }
}

// Kept in this file to inspect private state without widening gameplay access.
// Stored-property audit and exact field order: fighter-replay-state-encoding.md.
extension DuelGame {
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.hero(selectedHero); try writer.difficulty(difficulty); try writer.mode(mode)
        try writer.array(fighters, limit: 2) { try $0.fighter($1) }
        try writer.array(projectiles) { try $0.projectile($1) }
        try writer.optional(grapple) { try $0.grapple($1) }
        try writer.phase(phase); try writer.int(frame); try writer.int(remainingTicks)
        try writer.array(wins, limit: 2) { try $0.int($1) }; try writer.int(hitStop)
        try writer.array(events) { try $0.event($1) }
        try writer.array(landedHits, limit: 2) { try $0.int($1) }
        try writer.array(damageDealt, limit: 2) { try $0.int($1) }
        try writer.optional(weaponFight) { writer, fight in try fight.appendReplayState(to: &writer) }
        try writer.array(shogunStates, limit: 2) { writer, state in
            try writer.optional(state) { try $1.appendReplayState(to: &$0) }
        }
        try writer.array(arenaKitStates, limit: 2) { writer, state in
            try writer.optional(state) { try $1.appendReplayState(to: &$0) }
        }
        try writer.u64(random); try writer.int(nextProjectile); try writer.input(botHeld)
        try writer.array(buffered, limit: 2) { try $0.int($1.rawValue) }
        try writer.hero(opponentHero); try writer.bool(weaponModeRequested)
    }
}
