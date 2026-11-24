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
            case .ember: return "齐天大圣 · 如意金箍棒与腾云飞升"
            case .gale: return "军团之王 · 巨剑锁链与暗影化身"
            case .liu: return "暗影君主 · 皇室体术与暗影兽"
            case .wuYong: return "幕府将军 · 野太刀与暗影死士"
            }
        }
        public var skill1Name: String {
            switch self { case .ember: return "腾云攀棍"; case .gale: return "暗影锁链"; case .liu: return "暗影飞刃"; case .wuYong: return "无情突踢" }
        }
        public var skill2Name: String {
            switch self { case .ember: return "定海神柱"; case .gale: return "悲悯重斩"; case .liu: return "暗影兽化"; case .wuYong: return "死士突袭" }
        }
        public var skillHelp: String {
            switch self {
            case .ember: return "孙悟空·如意金箍棒中远距压制与飞跃重砸；按「远程」跃上定海神柱（2.12m高台）免疫中低段地面攻击，可衔接「武器/重击」飞升俯冲突刺或「踢击/暗影」神柱震地破防；满能「暗影」直接发动破防定海神柱重砸。"
            case .gale: return "军团之王·1.26m双手巨剑霸体重斩压制；按「远程」射出28节3D暗影锁链（4.35m射程），命中将对手挑空并拉回身边1.07m接连招；满能「暗影」施放破防悲悯冲斩/裂地审判；被动「暗影化身」每局致死时触发一次无敌暗影爆裂并复苏520生命。"
            case .liu: return "暗影君主·双形态切换：人形态王朝体术快攻与「远程」暗影飞刃快速蓄能；满能按「暗影」爆发2.65m暗影冲击波并永久化身为「暗影兽」形态，解锁三连利爪撕裂与命中/格挡吸血（挥空不吸血），暗影兽满能可发动暗影跃爆破防。"
            case .wuYong: return "幕府将军·1.18m野太刀长距压制，前+武器3段斩、上+武器2段挑空；普通重击不破防高削血，长按蓄满居合必暴破防；前+踢3段霸体无情突踢；远程指挥「死士突袭」随时眩晕；暗影100入影（猛烈报复/暴政吸伤挑空），200爆发暗影灾变。"
            }
        }
    }
    public enum CombatRuleset: UInt8, Codable, Equatable, Sendable {
        /// Deterministic 1000-HP legacy ruleset preserved for existing laboratory tests.
        case laboratory = 0
        /// Authentic Shadow Fight 4 ruleset: hero-differentiated HP, neutral+back auto-block,
        /// velocity knockback, wall-splat, juggle, counter-hit, blade clash, dash & full 4-hero kits.
        case shadowArena = 1
    }
    public enum HitZone: UInt8, Codable, Equatable, Sendable {
        case high = 0, mid = 1, low = 2
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
        public var dashDirection: Int
        public init(move: Int = 0, guardHeld: Bool = false, taps: Buttons = [], vertical: Int = 0,
                    weaponCommand: DuelWeaponCommand? = nil, rangedHeld: Bool = false, heavyHeld: Bool = false,
                    dashDirection: Int = 0) {
            self.move = min(1, max(-1, move)); self.guardHeld = guardHeld; self.taps = taps
            self.vertical = min(1, max(-1, vertical)); self.weaponCommand = weaponCommand
            self.rangedHeld = rangedHeld; self.heavyHeld = heavyHeld
            self.dashDirection = min(1, max(-1, dashDirection))
        }
        private enum CodingKeys: String, CodingKey { case move, guardHeld, taps, vertical, weaponCommand, rangedHeld, heavyHeld, dashDirection }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(move: try c.decodeIfPresent(Int.self, forKey: .move) ?? 0,
                      guardHeld: try c.decodeIfPresent(Bool.self, forKey: .guardHeld) ?? false,
                      taps: try c.decodeIfPresent(Buttons.self, forKey: .taps) ?? [],
                      vertical: try c.decodeIfPresent(Int.self, forKey: .vertical) ?? 0,
                      weaponCommand: try c.decodeIfPresent(DuelWeaponCommand.self, forKey: .weaponCommand),
                      rangedHeld: try c.decodeIfPresent(Bool.self, forKey: .rangedHeld) ?? false,
                      heavyHeld: try c.decodeIfPresent(Bool.self, forKey: .heavyHeld) ?? false,
                      dashDirection: try c.decodeIfPresent(Int.self, forKey: .dashDirection) ?? 0)
        }
        public static let neutral = Input()
    }
    public enum Move: String, Codable, Sendable {
        case jab, cross, finisher, heavy, skill1, skill2, ultimate
        case shogunFierceReprisal, shogunDespotism
        case inquisitorLightSpin, midnightRemoval
        case weaponForward, weaponUp, weaponDown, weaponBack
        case kick, kickForward, kickUp, kickDown, kickBack
        case throwForward, throwBack
        case wakeupKick, rollForward, rollBack
        case dashForward, dashBack
        case inquisitorLightUp, inquisitorLightForward, inquisitorLightDown
        case emperorTransform, emperorBeastShadowJump
        case legionShadowChain, legionShadowForward, legionShadowDown
        case monkeyAscensionPlunge, monkeyHeavenlyPillar

        public var isRoll: Bool { self == .rollForward || self == .rollBack }
        public var isDash: Bool { self == .dashForward || self == .dashBack }
        public var isKick: Bool {
            self == .kick || self == .kickForward || self == .kickUp || self == .kickDown ||
                self == .kickBack || self == .wakeupKick
        }
        public var isInquisitorLightMove: Bool {
            self == .inquisitorLightUp || self == .inquisitorLightForward ||
                self == .inquisitorLightDown || self == .inquisitorLightSpin
        }
    }
    public struct Attack: Equatable, Sendable {
        public let move: Move
        public var age = 0
        public var connected = false
        public var spawned = false
        public var comboQueued = false
        public var chargeTicks = 0
        public var hitsLanded = 0
        public init(move: Move, age: Int = 0, connected: Bool = false, spawned: Bool = false,
                    comboQueued: Bool = false, chargeTicks: Int = 0, hitsLanded: Int = 0) {
            self.move = move; self.age = age; self.connected = connected
            self.spawned = spawned; self.comboQueued = comboQueued
            self.chargeTicks = chargeTicks; self.hitsLanded = hitsLanded
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
        public var lastHitZone: HitZone = .mid
        public var lastContactX = 0
        public var lastContactY = 1150
        public var velocityX = 0
        public var juggleHits = 0
        public var frozenTicks = 0
    }
    public struct Projectile: Equatable, Sendable {
        public enum Kind: UInt8, Codable, Equatable, Sendable {
            case salvationPillar = 0
            case shadowKunai = 1
            case emperorShadowDart = 2
        }
        public let id: Int
        public let owner: Int
        public var x: Int
        public let direction: Int
        public var lifetime = 65
        public let kind: Kind
        public init(id: Int, owner: Int, x: Int, direction: Int, lifetime: Int = 65, kind: Kind = .salvationPillar) {
            self.id = id; self.owner = owner; self.x = x; self.direction = direction
            self.lifetime = lifetime; self.kind = kind
        }
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
        case inquisitorSalvationEcho(attacker: Int, x: Int, damage: Int)
        case nonnaFlameForm(fighter: Int)
        case nonnaWolfHit(owner: Int, damage: Int)
        case nonnaOwlHit(owner: Int, damage: Int, returned: Bool)
        case nonnaTrueShapeExecute(attacker: Int, damage: Int)
        case midnightShadowShift(fighter: Int)
        case midnightBlinkCounter(attacker: Int, damage: Int)
        case midnightRemovalStrike(attacker: Int, damage: Int)
        case headHit(attacker: Int, damage: Int)
        case criticalHit(attacker: Int, damage: Int)
        case chipDamage(attacker: Int, damage: Int)
        case throwHit(attacker: Int, damage: Int, backThrow: Bool)
        case counterHit(attacker: Int, damage: Int)
        case bladeClash(x: Int, y: Int)
        case wallSplat(defender: Int)
        case inquisitorSalvationStrike(attacker: Int, x: Int, damage: Int)
        case inquisitorLightFormBroken(defender: Int)
        case nonnaTrueShapeStrike(attacker: Int, damage: Int)
        case midnightNocturneBurst(attacker: Int, damage: Int)
        case emperorTransformed(fighter: Int, damage: Int)
        case emperorLifesteal(fighter: Int, healed: Int)
        case legionChainSnag(attacker: Int, damage: Int)
        case legionDarkIncarnation(fighter: Int)
        case monkeyAscensionPerch(fighter: Int)
        case monkeyPerchEvade(fighter: Int)
        case monkeyPillarSlam(attacker: Int, damage: Int)
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
        public let hitZone: HitZone
        public let breaksBlock: Bool
        public let isThrow: Bool
        public let launchVelocityY: Int
        public let chipBps: Int
        public let hitCount: Int
        public let blockStunTicks: Int
        public let cancelAfterActive: Bool
        public init(startup: Int, active: Int, recovery: Int, reach: Int, damage: Int, push: Int,
                    knockdown: Bool, hitStop: Int = 5, armorStart: Int = -1, armorEnd: Int = -1,
                    absorbsFrontDamage: Bool = false, guardMultiplierBps: Int = 20000, stunTicks: Int = 17,
                    shadowGain: Int = 0, isShadow: Bool = false, isCritical: Bool = false,
                    hitZone: HitZone = .mid, breaksBlock: Bool = false, isThrow: Bool = false,
                    launchVelocityY: Int = 0, chipBps: Int = 1600,
                    hitCount: Int = 1, blockStunTicks: Int = 10, cancelAfterActive: Bool = false) {
            self.startup = startup; self.active = active; self.recovery = recovery
            self.reach = reach; self.damage = damage; self.push = push; self.knockdown = knockdown
            self.hitStop = hitStop; self.armorStart = armorStart; self.armorEnd = armorEnd
            self.absorbsFrontDamage = absorbsFrontDamage; self.guardMultiplierBps = guardMultiplierBps
            self.stunTicks = stunTicks; self.shadowGain = shadowGain
            self.isShadow = isShadow; self.isCritical = isCritical
            self.hitZone = hitZone; self.breaksBlock = breaksBlock; self.isThrow = isThrow
            self.launchVelocityY = launchVelocityY; self.chipBps = chipBps
            self.hitCount = max(1, hitCount); self.blockStunTicks = blockStunTicks
            self.cancelAfterActive = cancelAfterActive
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
        guard grapple == nil, let attack = f.attack, !attack.move.isRoll, !attack.move.isDash,
              !(f.hero == .gale && attack.move == .skill1),
              !(ruleset == .shadowArena && f.hero == .liu && attack.move == .skill1 && emperorState(index)?.isBeastForm == false),
              !(ruleset == .shadowArena && f.hero == .ember && attack.move == .skill1) else { return nil }
        let data = moveData(attack.move, hero: f.hero, chargeTicks: attack.chargeTicks)
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
    public static let shadowArenaBodyWidth = 900
    public static let throwMaxDistance = 1080
    public static let autoBlockRecoveryTicks = 10
    public static let shadowArenaRoundSeconds = 99

    public static func maximumHealth(for hero: Hero, ruleset: CombatRuleset) -> Int {
        guard ruleset == .shadowArena else { return 1000 }
        switch hero {
        case .gale: return 5800     // King of the Legion (armored greatsword overlord + 3D chain + Dark Incarnation)
        case .wuYong: return 5400   // Shogun (armored samurai overlord + Odachi + retinue + Overlord revive)
        case .ember: return 5100    // Monkey King (extendable Jingu Staff + Ascension Pillar evasion)
        case .liu: return 5000      // Emperor / Shadow Beast (dual-form royal martial artist + beast lifesteal)
        }
    }

    public static func critChancePercent(for hero: Hero) -> Int {
        switch hero {
        case .ember: return 16      // Monkey King: agile Jingu Staff strikes
        case .wuYong: return 12     // Shogun: Odachi precision
        case .gale: return 12       // King of the Legion: heavy greatsword cleaves
        case .liu: return 14        // Emperor / Shadow Beast: ferocious martial/claw strikes
        }
    }

    public func maximumHealth(_ index: Int) -> Int {
        if let weaponFight { return weaponFight.maximumHealth(index) }
        guard fighters.indices.contains(index) else { return 1000 }
        return Self.maximumHealth(for: fighters[index].hero, ruleset: ruleset)
    }

    public func moveData(_ move: Move, hero: Hero, chargeTicks: Int = 0) -> MoveData {
        Self.data(move, hero: hero, chargeTicks: chargeTicks, ruleset: ruleset)
    }

    private func scaledDamage(_ base: Int) -> Int {
        ruleset == .shadowArena ? (base * 26) / 10 : base
    }

    public let selectedHero: Hero
    public let difficulty: Difficulty
    public let mode: Mode
    public let ruleset: CombatRuleset
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
    public private(set) var guardRecoveryTicks = [0, 0]
    public private(set) var comboCount = [0, 0]
    private var random: UInt64
    private var nextProjectile = 0
    private var botHeld = Input.neutral
    private var buffered: [Buttons] = [[], []]
    private var bufferedCommands: [DuelWeaponCommand?] = [nil, nil]
    private let opponentHero: Hero
    private let weaponModeRequested: Bool

    public init(hero: Hero = .ember, difficulty: Difficulty = .learning, mode: Mode = .versus, seed: UInt64 = 20261107,
                opponentHero: Hero? = nil, weaponCatalog: DuelWeaponCatalog? = nil,
                ruleset: CombatRuleset = .laboratory) {
        selectedHero = hero; self.difficulty = difficulty; self.mode = mode; self.ruleset = ruleset; random = seed
        weaponModeRequested = weaponCatalog != nil
        self.remainingTicks = (ruleset == .shadowArena && weaponCatalog == nil) ? (Self.shadowArenaRoundSeconds * Self.ticksPerSecond) : (60 * Self.ticksPerSecond)
        self.opponentHero = opponentHero ?? (weaponCatalog != nil ? (hero == .liu ? .ember : .liu) : (hero == .gale ? .ember : .gale))
        var initialFighters = [Fighter(hero: hero, x: 3500, facing: 1),
                               Fighter(hero: self.opponentHero, x: 6500, facing: -1)]
        if weaponCatalog == nil {
            for i in initialFighters.indices {
                initialFighters[i].health = Self.maximumHealth(for: initialFighters[i].hero, ruleset: ruleset)
                if initialFighters[i].hero == .wuYong || ruleset == .shadowArena {
                    initialFighters[i].energy = 0
                }
            }
        }
        fighters = initialFighters
        shogunStates = initialFighters.map {
            $0.hero == .wuYong && weaponCatalog == nil ? DuelShogunState(ownerX: $0.x, ownerFacing: $0.facing) : nil
        }
        arenaKitStates = initialFighters.map { fighter in
            guard weaponCatalog == nil else { return nil }
            if ruleset == .shadowArena {
                switch fighter.hero {
                case .liu: return .emperor(DuelEmperorState())
                case .gale: return .legionKing(DuelLegionKingState())
                case .ember: return .monkeyKing(DuelMonkeyKingState())
                case .wuYong: return nil
                }
            }
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
    public func emperorState(_ index: Int) -> DuelEmperorState? {
        guard weaponFight == nil, arenaKitStates.indices.contains(index),
              case .emperor(let state) = arenaKitStates[index] else { return nil }
        return state
    }
    public func legionKingState(_ index: Int) -> DuelLegionKingState? {
        guard weaponFight == nil, arenaKitStates.indices.contains(index),
              case .legionKing(let state) = arenaKitStates[index] else { return nil }
        return state
    }
    public func monkeyKingState(_ index: Int) -> DuelMonkeyKingState? {
        guard weaponFight == nil, arenaKitStates.indices.contains(index),
              case .monkeyKing(let state) = arenaKitStates[index] else { return nil }
        return state
    }
    public var round: Int { wins.reduce(0, +) + 1 }
    /// Pause/interruption cancels future commands, without undoing a move that
    /// already started. Hit-stop buffers and queued combo links are input too.
    public mutating func cancelBufferedInputs() {
        weaponFight?.cancelBufferedInputs()
        buffered = [[], []]
        bufferedCommands = [nil, nil]
        for i in fighters.indices {
            fighters[i].attack?.comboQueued = false
            shogunStates[i]?.heavyChargeTicks = 0
        }
        botHeld = .neutral
    }
    public static func data(_ move: Move, hero: Hero, chargeTicks: Int = 0,
                            ruleset: CombatRuleset = .laboratory) -> MoveData {
        let base = rawMoveData(move, hero: hero, chargeTicks: chargeTicks)
        guard ruleset == .shadowArena else { return base }
        return calibratedForShadowArena(base, move: move)
    }

    private static func calibratedForShadowArena(_ raw: MoveData, move: Move) -> MoveData {
        if move.isRoll {
            return .init(startup: 2, active: 0, recovery: 30, reach: 0, damage: 0, push: 0,
                         knockdown: false, hitStop: 0, shadowGain: 0)
        }
        if move.isDash {
            return .init(startup: 2, active: 0, recovery: 20, reach: 0, damage: 0, push: 0,
                         knockdown: false, hitStop: 0, shadowGain: 0)
        }
        let startup = max(7, (raw.startup * 145) / 100)
        let active = raw.active > 0 ? max(4, (raw.active * 135) / 100) : 0
        let recovery = max(14, (raw.recovery * 145) / 100)
        let armorStart = raw.armorStart >= 0 ? (raw.armorStart * 145) / 100 : -1
        let armorEnd = raw.armorEnd >= 0 ? (raw.armorEnd * 140) / 100 : -1
        let hitStop = raw.hitStop > 0 ? min(14, raw.hitStop + 2) : 0
        let stunTicks = max(raw.stunTicks, (raw.stunTicks * 125) / 100)
        let blockStunTicks = max(raw.blockStunTicks, (raw.blockStunTicks * 120) / 100)
        let chipBps = raw.isShadow ? min(raw.chipBps, 2400) : min(raw.chipBps, 1200)
        return .init(
            startup: startup,
            active: active,
            recovery: recovery,
            reach: raw.reach,
            damage: raw.damage,
            push: raw.push,
            knockdown: raw.knockdown,
            hitStop: hitStop,
            armorStart: armorStart,
            armorEnd: armorEnd,
            absorbsFrontDamage: raw.absorbsFrontDamage,
            guardMultiplierBps: raw.guardMultiplierBps,
            stunTicks: stunTicks,
            shadowGain: raw.shadowGain,
            isShadow: raw.isShadow,
            isCritical: raw.isCritical,
            hitZone: raw.hitZone,
            breaksBlock: raw.breaksBlock,
            isThrow: raw.isThrow,
            launchVelocityY: raw.launchVelocityY,
            chipBps: chipBps,
            hitCount: raw.hitCount,
            blockStunTicks: blockStunTicks,
            cancelAfterActive: raw.cancelAfterActive
        )
    }

    private static func rawMoveData(_ move: Move, hero: Hero, chargeTicks: Int) -> MoveData {
        if hero == .wuYong {
            switch move {
            case .jab:
                return .init(startup: 7, active: 4, recovery: 13, reach: 1320, damage: 80, push: 130,
                             knockdown: false, hitStop: 4, shadowGain: 16, blockStunTicks: 12, cancelAfterActive: true)
            case .cross:
                return .init(startup: 8, active: 4, recovery: 15, reach: 1460, damage: 95, push: 160,
                             knockdown: false, hitStop: 5, shadowGain: 20, blockStunTicks: 13, cancelAfterActive: true)
            case .finisher:
                return .init(startup: 11, active: 5, recovery: 24, reach: 1620, damage: 135, push: 460,
                             knockdown: true, hitStop: 8, shadowGain: 26, blockStunTicks: 10)
            case .weaponForward:
                // 3-hit advancing Odachi slash -> reverse rise -> piercing thrust
                return .init(startup: 8, active: 15, recovery: 19, reach: 1660, damage: 55, push: 240,
                             knockdown: false, hitStop: 5, shadowGain: 10, hitCount: 3, blockStunTicks: 13)
            case .weaponUp:
                // 2-hit rising anti-air launcher
                return .init(startup: 8, active: 10, recovery: 16, reach: 1480, damage: 68, push: 200,
                             knockdown: false, hitStop: 6, shadowGain: 12, hitZone: .high, launchVelocityY: 135,
                             hitCount: 2, blockStunTicks: 12)
            case .weaponDown:
                return .init(startup: 9, active: 5, recovery: 19, reach: 1560, damage: 105, push: 230,
                             knockdown: false, hitStop: 6, shadowGain: 18, hitZone: .low, blockStunTicks: 11)
            case .weaponBack:
                return .init(startup: 7, active: 4, recovery: 17, reach: 1460, damage: 105, push: 320,
                             knockdown: false, hitStop: 6, shadowGain: 18, blockStunTicks: 12)
            case .heavy:
                let clamped = min(DuelShogunState.heavyMaxChargeTicks, max(0, chargeTicks))
                let isFull = clamped >= DuelShogunState.heavyFullChargeTicks
                let extraReach = min(420, (clamped * 420) / DuelShogunState.heavyFullChargeTicks)
                let extraDamage = isFull ? 125 : (clamped * 85) / DuelShogunState.heavyFullChargeTicks
                return .init(startup: isFull ? 14 : 18, active: 6, recovery: 28, reach: 1680 + extraReach,
                             damage: 175 + extraDamage, push: isFull ? 640 : 500, knockdown: true,
                             hitStop: isFull ? 12 : 9, guardMultiplierBps: isFull ? 44000 : 24000,
                             stunTicks: isFull ? 26 : 20, shadowGain: isFull ? 36 : 24, isCritical: isFull,
                             hitZone: .high, breaksBlock: isFull, blockStunTicks: 10)
            case .kick:
                return .init(startup: 5, active: 3, recovery: 12, reach: 1040, damage: 65, push: 210,
                             knockdown: false, hitStop: 4, shadowGain: 10, blockStunTicks: 11)
            case .kickForward, .skill1:
                // Ruthless Advance: Legion-style 3-step unbreakable advancing kick.
                return .init(startup: 10, active: 12, recovery: 24, reach: 1280, damage: 58, push: 320,
                             knockdown: false, hitStop: 5, armorStart: 4, armorEnd: 22, shadowGain: 10,
                             hitCount: 3, blockStunTicks: 10)
            case .kickUp:
                return .init(startup: 7, active: 4, recovery: 16, reach: 1060, damage: 90, push: 240,
                             knockdown: false, hitStop: 6, shadowGain: 14, hitZone: .high, blockStunTicks: 11)
            case .kickDown:
                return .init(startup: 8, active: 4, recovery: 19, reach: 1100, damage: 85, push: 200,
                             knockdown: true, hitStop: 6, shadowGain: 14, hitZone: .low, blockStunTicks: 10)
            case .kickBack:
                return .init(startup: 8, active: 4, recovery: 18, reach: 1080, damage: 95, push: 520,
                             knockdown: false, hitStop: 7, shadowGain: 15, blockStunTicks: 11)
            case .throwForward, .throwBack:
                return .init(startup: 6, active: 4, recovery: 18, reach: 1120, damage: 130, push: 600,
                             knockdown: true, hitStop: 9, shadowGain: 20, breaksBlock: true, isThrow: true)
            case .wakeupKick:
                return .init(startup: 7, active: 4, recovery: 13, reach: 1120, damage: 78, push: 380,
                             knockdown: false, hitStop: 6, shadowGain: 12, hitZone: .low, blockStunTicks: 9)
            case .rollForward, .rollBack:
                return .init(startup: 1, active: 0, recovery: 17, reach: 0, damage: 0, push: 0,
                             knockdown: false, hitStop: 0, shadowGain: 0)
            case .dashForward, .dashBack:
                return .init(startup: 1, active: 0, recovery: 13, reach: 0, damage: 0, push: 0,
                             knockdown: false, hitStop: 0, shadowGain: 0)
            case .skill2:
                return .init(startup: 10, active: 8, recovery: 16, reach: 1080, damage: 75, push: 180,
                             knockdown: false, hitStop: 7, stunTicks: DuelShogunState.companionStunTicks)
            case .shogunFierceReprisal:
                // Forward Shadow Ability: 2-hit Cataclysm Odachi dash double-slash.
                return .init(startup: 11, active: 14, recovery: 23, reach: 1680, damage: 190, push: 540,
                             knockdown: true, hitStop: 9, armorStart: 5, armorEnd: 25,
                             guardMultiplierBps: 32000, stunTicks: 24, isShadow: true, breaksBlock: true,
                             hitCount: 2, blockStunTicks: 12)
            case .shogunDespotism:
                // Back Shadow Ability: Despotism (front damage absorption + telekinetic pull + juggle upper slash).
                return .init(startup: 9, active: 8, recovery: 25, reach: 2600, damage: 185, push: 420,
                             knockdown: false, hitStop: 10, armorStart: 0, armorEnd: 17,
                             absorbsFrontDamage: true, guardMultiplierBps: 30000, stunTicks: 34,
                             isShadow: true, hitZone: .high, breaksBlock: true, launchVelocityY: 160, blockStunTicks: 12)
            case .ultimate, .inquisitorLightSpin, .inquisitorLightUp, .inquisitorLightForward, .inquisitorLightDown, .midnightRemoval,
                 .emperorTransform, .emperorBeastShadowJump, .legionShadowChain, .legionShadowForward, .legionShadowDown,
                 .monkeyAscensionPlunge, .monkeyHeavenlyPillar:
                return .init(startup: 12, active: 10, recovery: 26, reach: 1650, damage: 210, push: 520,
                             knockdown: true, hitStop: 10, isShadow: true, breaksBlock: true)
            }
        }
        let long = hero == .gale ? 260 : hero == .ember ? 160 : 0
        let fast = hero == .ember ? 1 : 0
        switch move {
        case .jab: return .init(startup: 6, active: 3, recovery: 13, reach: 1060 + long, damage: 75, push: 130, knockdown: false, blockStunTicks: 12, cancelAfterActive: true)
        case .cross: return .init(startup: 7, active: 3, recovery: 15, reach: 1180 + long, damage: 90, push: 160, knockdown: false, blockStunTicks: 13, cancelAfterActive: true)
        case .finisher: return .init(startup: 10, active: 4, recovery: 23, reach: 1280 + long, damage: 125, push: 440, knockdown: true, hitStop: 8, blockStunTicks: 10)
        case .weaponForward:
            if hero == .liu {
                // Emperor Dynasty spinning double punch / Shadow Beast 2-hit feral claw sweep
                return .init(startup: 9, active: 12, recovery: 18, reach: 1380, damage: 78, push: 300,
                             knockdown: false, hitStop: 6, armorStart: 4, armorEnd: 16, hitCount: 2, blockStunTicks: 12)
            }
            if hero == .ember {
                // Monkey King 3-hit Jingu staff whirlwind forward combo!
                return .init(startup: 7, active: 15, recovery: 18, reach: 1540, damage: 52, push: 240,
                             knockdown: false, hitStop: 5, hitCount: 3, blockStunTicks: 12)
            }
            // King of the Legion 2-hit advancing greatsword cleave
            return .init(startup: 9, active: 12, recovery: 19, reach: 1460 + long, damage: 78, push: 320,
                         knockdown: false, hitStop: 7, armorStart: 5, armorEnd: 18, hitCount: 2, blockStunTicks: 12)
        case .weaponUp:
            if hero == .liu {
                return .init(startup: 8, active: 4, recovery: 18, reach: 1300, damage: 108, push: 240,
                             knockdown: false, hitStop: 7, hitZone: .high, launchVelocityY: 145, blockStunTicks: 12)
            }
            return .init(startup: max(6, 8 - fast), active: 4, recovery: 17, reach: 1260 + long, damage: 105, push: 220,
                         knockdown: false, hitStop: 7, hitZone: .high, launchVelocityY: 135, blockStunTicks: 12)
        case .weaponDown:
            if hero == .liu {
                return .init(startup: 8, active: 10, recovery: 17, reach: 1340, damage: 64, push: 230,
                             knockdown: false, hitStop: 5, hitZone: .low, hitCount: 2, blockStunTicks: 11)
            }
            return .init(startup: max(6, 9 - fast), active: 5, recovery: 19, reach: 1360 + long, damage: 100, push: 220,
                         knockdown: false, hitStop: 6, hitZone: .low, blockStunTicks: 11)
        case .weaponBack:
            if hero == .liu {
                return .init(startup: 7, active: 9, recovery: 16, reach: 1280, damage: 64, push: 280,
                             knockdown: false, hitStop: 6, hitCount: 2, blockStunTicks: 12)
            }
            return .init(startup: max(5, 7 - fast), active: 4, recovery: 17, reach: 1280 + long, damage: 100, push: 300,
                         knockdown: false, hitStop: 6, blockStunTicks: 12)
        case .heavy:
            if hero == .liu {
                // Emperor Heavy Lunge (`p_agl_heavy_punch`) / Shadow Beast Claw Slash (`claws_spinning_slash_1`)
                return .init(startup: 16, active: 6, recovery: 24, reach: 1480, damage: 165, push: 460,
                             knockdown: true, hitStop: 9, armorStart: 6, armorEnd: 19, hitZone: .mid, blockStunTicks: 10)
            }
            if hero == .ember {
                // Monkey King Leaping Extendable Jingu Staff Heavy (`staff_heavy_slash`, long reach lunge!)
                return .init(startup: 16, active: 6, recovery: 24, reach: 1780, damage: 165, push: 480,
                             knockdown: true, hitStop: 9, hitZone: .high, blockStunTicks: 10)
            }
            // King of the Legion Two-Handed Greatsword Heavy (`twohanded_sword_heavy_slash`, unbreakable hyper-armor!)
            return .init(startup: 18, active: 6, recovery: 28, reach: 1560 + long, damage: 165, push: 520,
                         knockdown: true, hitStop: 10, armorStart: 6, armorEnd: 22, hitZone: .high, blockStunTicks: 10)
        case .kick:
            return .init(startup: 5, active: 3, recovery: 12, reach: 1040, damage: 60, push: 200, knockdown: false, hitStop: 4, blockStunTicks: 11)
        case .kickForward:
            return .init(startup: 9, active: 5, recovery: 18, reach: 1180, damage: 95, push: 360, knockdown: false, hitStop: 6, blockStunTicks: 11)
        case .kickUp:
            return .init(startup: 7, active: 4, recovery: 16, reach: 1060, damage: 85, push: 240,
                         knockdown: false, hitStop: 6, hitZone: .high, blockStunTicks: 11)
        case .kickDown:
            return .init(startup: 8, active: 4, recovery: 19, reach: 1080, damage: 80, push: 200,
                         knockdown: true, hitStop: 6, hitZone: .low, blockStunTicks: 10)
        case .kickBack:
            return .init(startup: 8, active: 4, recovery: 18, reach: 1080, damage: 90, push: 520, knockdown: false, hitStop: 7, blockStunTicks: 11)
        case .throwForward, .throwBack:
            return .init(startup: 6, active: 4, recovery: 18, reach: 1120, damage: 125, push: 600,
                         knockdown: true, hitStop: 9, breaksBlock: true, isThrow: true)
        case .wakeupKick:
            return .init(startup: 7, active: 4, recovery: 13, reach: 1120, damage: 78, push: 380,
                         knockdown: false, hitStop: 6, hitZone: .low, blockStunTicks: 9)
        case .rollForward, .rollBack:
            return .init(startup: 1, active: 0, recovery: 17, reach: 0, damage: 0, push: 0, knockdown: false, hitStop: 0)
        case .dashForward, .dashBack:
            return .init(startup: 1, active: 0, recovery: 13, reach: 0, damage: 0, push: 0, knockdown: false, hitStop: 0)
        case .skill1: return .init(startup: hero == .gale ? 18 : 11, active: 5, recovery: 26, reach: 1200, damage: 135, push: 280, knockdown: false, hitStop: 6)
        case .skill2:
            if hero == .gale {
                return .init(startup: 8, active: 5, recovery: 32, reach: 1550, damage: 155, push: 460,
                             knockdown: true, hitStop: 9, armorStart: 4, armorEnd: 13, hitZone: .high, breaksBlock: true, blockStunTicks: 10)
            }
            return .init(startup: 8, active: 5, recovery: 32, reach: 1550, damage: 155, push: 460, knockdown: true, hitStop: 8, blockStunTicks: 10)
        case .inquisitorLightSpin:
            return .init(startup: 6, active: 10, recovery: 16, reach: 1520, damage: 180, push: 480,
                         knockdown: true, hitStop: 9, armorStart: 0, armorEnd: 16, guardMultiplierBps: 50000,
                         breaksBlock: true, blockStunTicks: 12)
        case .inquisitorLightUp:
            return .init(startup: 7, active: 5, recovery: 16, reach: 1480, damage: 130, push: 260,
                         knockdown: false, hitStop: 7, hitZone: .high, breaksBlock: true, launchVelocityY: 145, blockStunTicks: 12)
        case .inquisitorLightForward:
            return .init(startup: 9, active: 7, recovery: 18, reach: 1780, damage: 155, push: 480,
                         knockdown: false, hitStop: 8, breaksBlock: true, blockStunTicks: 12)
        case .inquisitorLightDown:
            return .init(startup: 11, active: 6, recovery: 20, reach: 1620, damage: 165, push: 340,
                         knockdown: true, hitStop: 10, hitZone: .low, breaksBlock: true, blockStunTicks: 12)
        case .midnightRemoval:
            return .init(startup: 12, active: 6, recovery: 22, reach: 2800, damage: DuelMidnightState.removalDamage,
                         push: 560, knockdown: true, hitStop: 12, guardMultiplierBps: 45000,
                         isShadow: true, isCritical: true, breaksBlock: true)
        case .emperorTransform:
            // Emperor -> Shadow Beast transformation explosion (`emperor_transition`)
            return .init(startup: 18, active: 6, recovery: 20, reach: DuelEmperorState.transformBurstRadius,
                         damage: DuelEmperorState.transformBurstDamage, push: 580, knockdown: true, hitStop: 10,
                         armorStart: 0, armorEnd: 24, isShadow: true, breaksBlock: false, chipBps: 3000, blockStunTicks: 14)
        case .emperorBeastShadowJump:
            // Shadow Beast leaping obsidian shockwave (`emperor_shadow_jump_explosion`)
            return .init(startup: 14, active: 8, recovery: 22, reach: 1880,
                         damage: DuelEmperorState.beastShadowExplosionDamage, push: 560, knockdown: true, hitStop: 11,
                         armorStart: 4, armorEnd: 20, isShadow: true, breaksBlock: true, blockStunTicks: 14)
        case .legionShadowChain:
            // King of the Legion 3D 28-Link Shadow Chain cast (`shadow_ranged_chain`, 4.35m reach, pulls -1.066m & lifts!)
            return .init(startup: 14, active: 10, recovery: 22, reach: DuelLegionKingState.chainMaxReach,
                         damage: DuelLegionKingState.chainHitDamage, push: 0, knockdown: false, hitStop: 7,
                         stunTicks: 34, isShadow: false, hitZone: .mid, breaksBlock: false,
                         launchVelocityY: DuelLegionKingState.chainLiftVelocityY, chipBps: 2400, blockStunTicks: 12)
        case .legionShadowForward:
            // King of the Legion Sorrowful Prayer advancing shadow greatsword cleave (`shadow_twohanded_sword_forward`)
            return .init(startup: 12, active: 10, recovery: 22, reach: 1920, damage: 162, push: 540,
                         knockdown: true, hitStop: 11, armorStart: 4, armorEnd: 22,
                         isShadow: true, breaksBlock: true, blockStunTicks: 14)
        case .legionShadowDown:
            // King of the Legion Earthsplitter seismic shadow slam (`shadow_twohanded_sword_down`, hits downed foes!)
            return .init(startup: 14, active: 8, recovery: 24, reach: 1960, damage: 175, push: 460,
                         knockdown: true, hitStop: 12, armorStart: 4, armorEnd: 22,
                         isShadow: true, hitZone: .low, breaksBlock: true, blockStunTicks: 14)
        case .monkeyAscensionPlunge:
            // Monkey King Ascension Forward Plunge (`monkey_king_climb_forward_attack`, +2.73m dive!)
            return .init(startup: 12, active: 8, recovery: 20, reach: 1980,
                         damage: DuelMonkeyKingState.plungeDamage, push: 520, knockdown: true, hitStop: 10,
                         hitZone: .high, breaksBlock: false, chipBps: 3000, blockStunTicks: 14)
        case .monkeyHeavenlyPillar:
            // Monkey King Heavenly Pillar Slam (`monkey_king_climb_pillar_attack`, guard-breaking Jingu smash!)
            return .init(startup: 16, active: 8, recovery: 24, reach: 2060,
                         damage: DuelMonkeyKingState.pillarSlamDamage, push: 560, knockdown: true, hitStop: 12,
                         armorStart: 6, armorEnd: 22, isShadow: true, hitZone: .high, breaksBlock: true, blockStunTicks: 14)
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
            buffered = [[], []]; bufferedCommands = [nil, nil]; botHeld = .neutral
            advanceGrapple(); resolveRound(); return
        }
        let other = opponent ?? (mode == .versus ? botInput() : .neutral)
        let inputs = [player, other]
        for i in 0..<2 {
            buffered[i].formUnion(inputs[i].taps)
            if let cmd = inputs[i].weaponCommand { bufferedCommands[i] = cmd }
        }
        if hitStop > 0 { hitStop -= 1; return }
        if mode == .versus { remainingTicks -= 1 }
        for i in 0..<2 {
            updateFighter(i, input: inputs[i], taps: buffered[i], command: bufferedCommands[i])
            buffered[i] = []
            bufferedCommands[i] = nil
        }
        separateBodies()
        // Collect all contacts before applying any: simultaneous active attacks can trade or Blade Clash!
        var contacts: [(attacker: Int, move: Move, data: MoveData, direction: Int, isCompanion: Bool,
                        hitZone: HitZone, contactX: Int?, contactY: Int?)] = []
        var grabs: [Int] = []
        // Blade Clash ("拼刀!"): simultaneous active weapon arcs colliding mid-air cancel both strikes with sparks & recoil!
        if ruleset == .shadowArena,
           let atk0 = fighters[0].attack, let atk1 = fighters[1].attack,
           !atk0.move.isRoll, !atk0.move.isDash, !atk0.move.isKick,
           !atk1.move.isRoll, !atk1.move.isDash, !atk1.move.isKick {
            let d0 = moveData(atk0.move, hero: fighters[0].hero, chargeTicks: atk0.chargeTicks)
            let d1 = moveData(atk1.move, hero: fighters[1].hero, chargeTicks: atk1.chargeTicks)
            let act0 = !d0.isThrow && atk0.age >= d0.startup && atk0.age < d0.startup + d0.active && atk0.hitsLanded == 0
            let act1 = !d1.isThrow && atk1.age >= d1.startup && atk1.age < d1.startup + d1.active && atk1.hitsLanded == 0
            if act0 && act1,
               let clash = DuelShadowArenaCollision.evaluateBladeClash(
                first: fighters[0], firstMove: atk0.move, firstCharge: atk0.chargeTicks,
                firstAge: atk0.age - d0.startup, firstActive: d0.active,
                second: fighters[1], secondMove: atk1.move, secondCharge: atk1.chargeTicks,
                secondAge: atk1.age - d1.startup, secondActive: d1.active
               ) {
                for idx in 0..<2 {
                    fighters[idx].attack = nil
                    fighters[idx].stun = 10
                    fighters[idx].velocityX = -fighters[idx].facing * 95
                    fighters[idx].flash = 6
                }
                hitStop = max(hitStop, 10)
                events.append(.bladeClash(x: clash.pointX, y: clash.pointY))
                resolveRound()
                return
            }
        }
        for i in 0..<2 {
            guard var attack = fighters[i].attack else { continue }
            let data = moveData(attack.move, hero: fighters[i].hero, chargeTicks: attack.chargeTicks)
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
            // Emperor Transformation: trigger permanent Human -> Shadow Beast swap at burst onset!
            if attack.move == .emperorTransform && attack.age == data.startup {
                if case .emperor(var emp) = arenaKitStates[i], !emp.isBeastForm {
                    emp.completeTransformation()
                    arenaKitStates[i] = .emperor(emp)
                    fighters[i].energy = 0
                    fighters[i].invulnerable = max(fighters[i].invulnerable, 14)
                    events.append(.emperorTransformed(fighter: i, damage: scaledDamage(DuelEmperorState.transformBurstDamage)))
                }
            }
            // Legion King 28-Link Shadow Chain: project live 3D chain beam from hand during active stretch!
            if attack.move == .legionShadowChain && attack.age == data.startup {
                if case .legionKing(var lk) = arenaKitStates[i] {
                    lk.chainActiveTicks = 24
                    lk.chainSnagged = false
                    lk.chainTargetX = min(Self.rightWall, max(Self.leftWall, fighters[i].x + fighters[i].facing * DuelLegionKingState.chainMaxReach))
                    arenaKitStates[i] = .legionKing(lk)
                }
            }
            let active = attack.age >= data.startup && attack.age < data.startup + data.active
            if attack.move == .ultimate {
                if active && !attack.connected && canGrapple(i) { grabs.append(i) }
            } else if fighters[i].hero == .gale && attack.move == .skill1 {
                if active && !attack.spawned {
                    if ruleset == .shadowArena, case .inquisitor(var inq) = arenaKitStates[i] {
                        // Authentic SF4 Grand Inquisitor Salvation: targeted fixed-range sky pillar (NOT slow fireball!)
                        let foeX = fighters[1 - i].x
                        let minX = fighters[i].x + fighters[i].facing * 900
                        let maxX = fighters[i].x + fighters[i].facing * 3600
                        let lo = min(minX, maxX), hi = max(minX, maxX)
                        let clampedTarget = min(Self.rightWall - 200, max(Self.leftWall + 200, min(hi, max(lo, foeX))))
                        inq.salvationCastTicks = DuelInquisitorState.salvationTelegraphTicks
                        inq.salvationCastX = clampedTarget
                        arenaKitStates[i] = .inquisitor(inq)
                    } else {
                        nextProjectile += 1
                        projectiles.append(.init(id: nextProjectile, owner: i, x: fighters[i].x + fighters[i].facing * 650,
                                                 direction: fighters[i].facing, lifetime: 65, kind: .salvationPillar))
                    }
                    attack.spawned = true
                }
            } else if ruleset == .shadowArena && fighters[i].hero == .liu && attack.move == .skill1,
                      case .emperor(let emp) = arenaKitStates[i], !emp.isBeastForm {
                if active && !attack.spawned {
                    nextProjectile += 1
                    projectiles.append(.init(id: nextProjectile, owner: i, x: fighters[i].x + fighters[i].facing * 460,
                                             direction: fighters[i].facing, lifetime: 46, kind: .emperorShadowDart))
                    attack.spawned = true
                }
            } else if ruleset == .shadowArena && fighters[i].hero == .ember && attack.move == .skill1,
                      case .midnight = arenaKitStates[i] {
                if active && !attack.spawned {
                    nextProjectile += 1
                    projectiles.append(.init(id: nextProjectile, owner: i, x: fighters[i].x + fighters[i].facing * 420,
                                             direction: fighters[i].facing, lifetime: 44, kind: .shadowKunai))
                    attack.spawned = true
                }
            } else if active {
                // True multi-hit active windows: distribute `hitCount` evenly across `data.active` frames!
                let hitCount = (ruleset == .shadowArena) ? data.hitCount : 1
                let hitSlice = max(1, data.active / max(1, hitCount))
                let activeAge = attack.age - data.startup
                let expectedHitIndex = min(hitCount - 1, activeAge / hitSlice)
                let canLandNextHit = attack.hitsLanded <= expectedHitIndex && attack.hitsLanded < hitCount
                if canLandNextHit {
                    if ruleset == .shadowArena {
                        let defender = fighters[1 - i]
                        let isJuggleable = defender.y > 0 && defender.juggleHits < 2 && defender.invulnerable == 0
                        let hitsDowned = (attack.move == .inquisitorLightDown || attack.move == .legionShadowDown) &&
                            defender.knockdown > 0 && defender.y == 0
                        let canStrike = (defender.knockdown == 0 && defender.invulnerable == 0) || isJuggleable || hitsDowned
                        if data.isThrow {
                            let dist = (defender.x - fighters[i].x) * fighters[i].facing
                            if defender.knockdown == 0 && defender.invulnerable == 0 && defender.y == 0 && dist >= -120 && dist <= data.reach {
                                contacts.append((i, attack.move, data, fighters[i].facing, false,
                                                 .mid, (fighters[i].x + defender.x) / 2, 1080))
                                attack.connected = true
                                attack.hitsLanded += 1
                            }
                        } else if hitsDowned && abs(defender.x - fighters[i].x) <= data.reach {
                            contacts.append((i, attack.move, data, fighters[i].facing, false,
                                             .low, defender.x, 320))
                            attack.connected = true
                            attack.hitsLanded += 1
                        } else if canStrike, monkeyKingState(1 - i)?.isPerchedOnPillar == true {
                            let signedDist = (defender.x - fighters[i].x) * fighters[i].facing
                            if signedDist >= -150 && signedDist <= data.reach + 160 {
                                let isAntiAir = data.hitZone == .high || fighters[i].y >= 400 || data.isShadow ||
                                    attack.move == .legionShadowChain || attack.move == .weaponUp || attack.move == .kickUp
                                contacts.append((i, attack.move, data, fighters[i].facing, false,
                                                 isAntiAir ? .high : .low,
                                                 defender.x, isAntiAir ? defender.y + 820 : 720))
                                attack.connected = true
                                attack.hitsLanded += 1
                            }
                        } else if canStrike, let hit = DuelShadowArenaCollision.evaluateSweep(
                            attacker: fighters[i], defender: defender,
                            move: attack.move, chargeTicks: attack.chargeTicks,
                            activeAge: activeAge, activeDuration: data.active
                        ) {
                            let resolvedZone: HitZone = (data.hitZone == .low) ? .low :
                                (hit.zone == .high || data.hitZone == .high) ? .high : hit.zone
                            contacts.append((i, attack.move, data, fighters[i].facing, false,
                                             resolvedZone, hit.pointX, hit.pointY))
                            attack.connected = true
                            attack.hitsLanded += 1
                        }
                    } else if canHit(i, reach: data.reach) {
                        contacts.append((i, attack.move, data, fighters[i].facing, false, data.hitZone, nil, nil))
                        attack.connected = true
                        attack.hitsLanded += 1
                    }
                }
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
                contacts.append((i, .skill2, moveData(.skill2, hero: .wuYong), shogun.companionFacing, true,
                                 .mid, target.x, target.y + 1120))
            }
        }
        // Advance Nonna autonomous Spirit Wolf & Fire Grip Spirit Owl, and Inquisitor Salvation Cast / Stigmata / Light's Will echo.
        advanceArenaEntities()
        for index in projectiles.indices.reversed() {
            let speed: Int = {
                switch projectiles[index].kind {
                case .shadowKunai: return 210
                case .emperorShadowDart: return 205
                case .salvationPillar: return 135
                }
            }()
            projectiles[index].x += projectiles[index].direction * speed
            projectiles[index].lifetime -= 1
            let p = projectiles[index], target = fighters[1 - p.owner]
            let hitRadius = p.kind == .salvationPillar ? 440 : 380
            if abs(p.x - target.x) < hitRadius && target.y < 1100 && target.knockdown == 0 && target.invulnerable == 0 {
                if p.kind == .shadowKunai {
                    let kunaiData = MoveData(startup: 0, active: 1, recovery: 0, reach: 360,
                                             damage: DuelMidnightState.kunaiDamage, push: 220, knockdown: false,
                                             hitStop: 5, stunTicks: 14)
                    contacts.append((p.owner, .skill1, kunaiData, p.direction, false, .mid, p.x, target.y + 1220))
                } else if p.kind == .emperorShadowDart {
                    let dartData = MoveData(startup: 0, active: 1, recovery: 0, reach: 380,
                                            damage: DuelEmperorState.rangedBurstDamage, push: 260, knockdown: false,
                                            hitStop: 5, stunTicks: 16)
                    contacts.append((p.owner, .skill1, dartData, p.direction, false, .mid, p.x, target.y + 1180))
                } else {
                    contacts.append((p.owner, .skill1, moveData(.skill1, hero: .gale), p.direction, false,
                                     .mid, p.x, target.y + 1150))
                    if ruleset == .shadowArena, case .inquisitor(var inq) = arenaKitStates[p.owner] {
                        inq.rangedCooldown = inq.rangedCooldown / 2
                        inq.salvationEchoTicks = DuelInquisitorState.salvationEchoDelayTicks
                        inq.salvationEchoX = p.x
                        arenaKitStates[p.owner] = .inquisitor(inq)
                    }
                }
                projectiles.remove(at: index)
            } else if p.lifetime <= 0 || p.x < 0 || p.x > 10000 {
                if ruleset == .shadowArena && p.kind == .salvationPillar && p.lifetime <= 0,
                   case .inquisitor(var inq) = arenaKitStates[p.owner] {
                    inq.salvationEchoTicks = DuelInquisitorState.salvationEchoDelayTicks
                    inq.salvationEchoX = min(Self.rightWall, max(Self.leftWall, p.x))
                    arenaKitStates[p.owner] = .inquisitor(inq)
                }
                projectiles.remove(at: index)
            }
        }
        for contact in contacts {
            applyHit(from: contact.attacker, move: contact.move, data: contact.data,
                     direction: contact.direction, isCompanion: contact.isCompanion,
                     hitZone: contact.hitZone, contactX: contact.contactX, contactY: contact.contactY)
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
                let data = moveData(attack.move, hero: fighters[i].hero, chargeTicks: attack.chargeTicks)
                // Snappy SF4 combo cancel: jab -> cross -> finisher chains right after active window!
                if ruleset == .shadowArena && attack.comboQueued && attack.connected &&
                    data.cancelAfterActive && attack.move != .finisher &&
                    attack.age >= data.startup + data.active + 2 {
                    fighters[i].attack = Attack(move: attack.move == .jab ? .cross : .finisher)
                } else if attack.age >= data.duration {
                    let isNonStrike = attack.move.isRoll || attack.move.isDash
                    let whiffed = !isNonStrike && !attack.connected && !attack.spawned
                    if whiffed {
                        events.append(.whiff(attacker: i))
                        // Midnight Shadow Shift: whiffing an attack phases Sun Deng out of this dimension & charges Nocturne!
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
                        // Midnight Distant Shift: Kunai / Phantom Bell skill always triggers Shadow Shift!
                        mid.enterShadowShift()
                        arenaKitStates[i] = .midnight(mid)
                        events.append(.midnightShadowShift(fighter: i))
                    }
                    if attack.comboQueued && attack.connected && attack.move != .finisher {
                        fighters[i].attack = Attack(move: attack.move == .jab ? .cross : .finisher)
                    } else {
                        fighters[i].attack = nil
                        if ruleset == .shadowArena {
                            guardRecoveryTicks[i] = isNonStrike ? 4 : (whiffed ? Self.autoBlockRecoveryTicks : Self.autoBlockRecoveryTicks / 2)
                        }
                    }
                } else { fighters[i].attack = attack }
            }
            if let shogun = shogunStates[i] {
                fighters[i].energy = shogun.shadowEnergy
            } else if case .emperor(let emp) = arenaKitStates[i] {
                fighters[i].energy = emp.shadowEnergy
            } else if case .legionKing(let lk) = arenaKitStates[i] {
                fighters[i].energy = lk.shadowEnergy
            } else if case .monkeyKing(let mk) = arenaKitStates[i] {
                fighters[i].energy = mk.shadowEnergy
            }
        }
        resolveRound()
    }

    private mutating func resolveRound() {
        if mode != .versus {
            guard grapple == nil else { return }
            for i in 0..<2 where fighters[i].health == 0 || (fighters[i].knockdown == 0 && fighters[i].stun == 0 && fighters[i].frozenTicks == 0) {
                fighters[i].health = maximumHealth(i)
            }
        } else if fighters.contains(where: { $0.health <= 0 }) || remainingTicks <= 0 {
            let winner: Int? = fighters[0].health == fighters[1].health ? nil : (fighters[0].health > fighters[1].health ? 0 : 1)
            if let winner { wins[winner] += 1 }
            events.append(.roundEnded(winner: winner))
            projectiles.removeAll(); buffered = [[], []]; bufferedCommands = [nil, nil]; grapple = nil; hitStop = 0
            for i in 0..<2 {
                fighters[i].attack = nil; fighters[i].guarding = false
                fighters[i].velocityX = 0; fighters[i].frozenTicks = 0
                shogunStates[i]?.heavyChargeTicks = 0
            }
            if let winner, wins[winner] == 2 { phase = .matchOver(winner: winner) }
            else { phase = .roundBreak(winner: winner, remaining: 120) }
        }
    }

    private mutating func triggerInquisitorBanishingBlasphemy(against shadowUser: Int) {
        guard ruleset == .shadowArena else { return }
        let inquisitorIndex = 1 - shadowUser
        guard case .inquisitor(var inq) = arenaKitStates[inquisitorIndex] else { return }
        if inq.hasStigmataOnOpponent {
            // Banishing Blasphemy: if Stigmata is already applied, entering Shadow Form flashes it immediately!
            detonateInquisitorStigmata(attacker: inquisitorIndex)
        } else {
            inq.applyStigmata()
            arenaKitStates[inquisitorIndex] = .inquisitor(inq)
            events.append(.inquisitorStigmataApplied(defender: shadowUser))
        }
    }

    /// Nonna Ancient Fury: whenever the opponent activates Shadow Form, Cataclysm, or Form of Light,
    /// Nonna enters 4 seconds of guaranteed Critical Hits!
    private mutating func triggerNonnaAncientFury(against shadowUser: Int) {
        guard ruleset == .shadowArena else { return }
        let nonnaIndex = 1 - shadowUser
        guard case .nonna(var nonna) = arenaKitStates[nonnaIndex] else { return }
        nonna.ancientFuryTicks = DuelNonnaState.ancientFuryDurationTicks
        arenaKitStates[nonnaIndex] = .nonna(nonna)
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
            triggerInquisitorBanishingBlasphemy(against: owner)
            triggerNonnaAncientFury(against: owner)
        case .cataclysm:
            events.append(.shogunCataclysm(fighter: owner))
            let opponent = 1 - owner
            let delta = fighters[opponent].x - fighters[owner].x
            if abs(delta) <= DuelShogunState.cataclysmEruptionRange && fighters[opponent].knockdown == 0 {
                let sign = delta >= 0 ? 1 : -1
                if ruleset == .shadowArena {
                    fighters[opponent].velocityX = sign * 115
                } else {
                    fighters[opponent].x = min(Self.rightWall, max(Self.leftWall, fighters[opponent].x + sign * DuelShogunState.cataclysmEruptionPush))
                }
            }
            hitStop = max(hitStop, 6)
            triggerInquisitorBanishingBlasphemy(against: owner)
            triggerNonnaAncientFury(against: owner)
        }
    }

    private mutating func updateShogunCompanion(_ i: Int, taps: Buttons, command: DuelWeaponCommand?) {
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
        } else if ruleset == .laboratory && frame % 24 == 0 && shogun.shadowEnergy < DuelShogunState.maxShadowEnergy {
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
            let companionTriggered = taps.contains(.skill2) || command == .ranged
            // Absolute Power: Shogun can command his companion even while attacking or stunned.
            if companionTriggered && shogun.isCompanionAvailable && fighters[i].health > 0 && fighters[i].knockdown == 0 {
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
                // Targeted SF4 Salvation Sky Pillar telegraph -> towering strike -> arms Light's Will 2nd smite!
                if inq.salvationCastTicks > 0 {
                    inq.salvationCastTicks -= 1
                    if inq.salvationCastTicks == 0 {
                        let strikeX = inq.salvationCastX
                        let target = fighters[defender]
                        let hitPillar = abs(strikeX - target.x) <= DuelInquisitorState.salvationPillarRadius &&
                            target.y < 1400 && target.knockdown == 0 && target.invulnerable == 0
                        var dealtDamage = 0
                        if hitPillar {
                            inq.rangedCooldown = inq.rangedCooldown / 2
                            arenaKitStates[i] = .inquisitor(inq)
                            let hpBefore = fighters[defender].health
                            let pillarData = MoveData(startup: 0, active: 1, recovery: 0, reach: DuelInquisitorState.salvationPillarRadius,
                                                      damage: 135, push: 280, knockdown: false, hitStop: 7, stunTicks: 20, hitZone: .high)
                            applyHit(from: i, move: .skill1, data: pillarData,
                                     direction: target.x >= strikeX ? 1 : -1, isCompanion: false,
                                     hitZone: .high, contactX: strikeX, contactY: target.y + 1500)
                            dealtDamage = max(0, hpBefore - fighters[defender].health)
                            if case .inquisitor(let updated) = arenaKitStates[i] { inq = updated }
                        }
                        // Arm Light's Will 2nd smite at pillar location whether 1st pillar hit or forced a dodge!
                        inq.salvationEchoTicks = DuelInquisitorState.salvationEchoDelayTicks
                        inq.salvationEchoX = strikeX
                        arenaKitStates[i] = .inquisitor(inq)
                        events.append(.inquisitorSalvationStrike(attacker: i, x: strikeX, damage: dealtDamage))
                    }
                }
                if inq.salvationEchoTicks > 0 {
                    inq.salvationEchoTicks -= 1
                    if inq.salvationEchoTicks == 0 {
                        let echoX = inq.salvationEchoX
                        let target = fighters[defender]
                        let echoDmg = scaledDamage(DuelInquisitorState.salvationEchoDamage)
                        var hitEcho = false
                        if abs(echoX - target.x) < 560 && target.y < 1200 && target.knockdown == 0 && target.invulnerable == 0 {
                            hitEcho = true
                            inq.gainLight(12)
                            if !inq.hasStigmataOnOpponent {
                                inq.applyStigmata()
                                events.append(.inquisitorStigmataApplied(defender: defender))
                            }
                            arenaKitStates[i] = .inquisitor(inq)
                            let echoData = MoveData(startup: 0, active: 1, recovery: 0, reach: 560,
                                                    damage: DuelInquisitorState.salvationEchoDamage, push: 220,
                                                    knockdown: false, hitStop: 6, stunTicks: 18)
                            applyHit(from: i, move: .skill1, data: echoData,
                                     direction: target.x >= echoX ? 1 : -1, isCompanion: true,
                                     hitZone: .high, contactX: echoX, contactY: target.y + 1450)
                            if case .inquisitor(let updated) = arenaKitStates[i] { inq = updated }
                            fighters[i].health = min(maximumHealth(i), fighters[i].health + (echoDmg * 25) / 100)
                        }
                        events.append(.inquisitorSalvationEcho(attacker: i, x: echoX, damage: hitEcho ? echoDmg : 0))
                    }
                }
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
                                                damage: wolfDmg, push: 340, knockdown: false, hitStop: 6, stunTicks: 24)
                        applyHit(from: i, move: .skill1, data: wolfData, direction: nonna.wolfFacing, isCompanion: true,
                                 hitZone: .mid, contactX: nonna.wolfX, contactY: target.y + 820)
                        // Heart of the Pack: spirit companion hit restores 6% max HP!
                        if ruleset == .shadowArena {
                            let heal = (maximumHealth(i) * DuelNonnaState.spiritHealPermille) / 1000
                            fighters[i].health = min(maximumHealth(i), fighters[i].health + heal)
                        }
                        events.append(.nonnaWolfHit(owner: i, damage: scaledDamage(wolfDmg)))
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
                    let targetUnbreakable: Bool = {
                        guard let atk = target.attack else { return false }
                        let d = moveData(atk.move, hero: target.hero, chargeTicks: atk.chargeTicks)
                        return d.armorStart >= 0 && atk.age >= d.armorStart && atk.age < d.armorEnd
                    }()
                    switch nonna.owlPhase {
                    case .idle: break
                    case .outbound:
                        nonna.owlX = min(Self.rightWall, max(Self.leftWall, nonna.owlX + nonna.owlFacing * DuelNonnaState.owlSpeed))
                        if !nonna.owlHitOut && abs(nonna.owlX - target.x) < 420 &&
                            target.y < 1150 && target.knockdown == 0 && target.invulnerable == 0 {
                            nonna.owlHitOut = true
                            nonna.owlPhase = .latched
                            nonna.owlTimer = 0
                            nonna.owlX = min(Self.rightWall, max(Self.leftWall, target.x + nonna.owlFacing * 360))
                            nonna.gainFlame(16)
                            arenaKitStates[i] = .nonna(nonna)
                            let owlData = MoveData(startup: 0, active: 1, recovery: 0, reach: 420,
                                                   damage: DuelNonnaState.owlOutDamage, push: 140, knockdown: false,
                                                   hitStop: 2, stunTicks: targetUnbreakable ? 0 : 14)
                            applyHit(from: i, move: .skill1, data: owlData, direction: nonna.owlFacing, isCompanion: true,
                                     hitZone: .mid, contactX: nonna.owlX, contactY: target.y + 1250)
                            if ruleset == .shadowArena {
                                let heal = (maximumHealth(i) * DuelNonnaState.spiritHealPermille) / 1000
                                fighters[i].health = min(maximumHealth(i), fighters[i].health + heal)
                            }
                            events.append(.nonnaOwlHit(owner: i, damage: scaledDamage(DuelNonnaState.owlOutDamage), returned: false))
                            if case .nonna(let updated) = arenaKitStates[i] { nonna = updated }
                        } else if nonna.owlTimer >= 22 || nonna.owlX <= Self.leftWall || nonna.owlX >= Self.rightWall {
                            nonna.owlPhase = .latched
                            nonna.owlTimer = 0
                        }
                    case .latched:
                        if nonna.owlTimer >= DuelNonnaState.owlLatchMaxTicks {
                            nonna.recallOwl()
                        }
                    case .returning:
                        let ownerX = fighters[i].x
                        let towardOwner = ownerX >= nonna.owlX ? 1 : -1
                        nonna.owlX = min(Self.rightWall, max(Self.leftWall, nonna.owlX + towardOwner * 175))
                        if !nonna.owlHitBack && abs(nonna.owlX - target.x) < 440 &&
                            target.y < 1150 && target.knockdown == 0 && target.invulnerable == 0 {
                            nonna.owlHitBack = true
                            nonna.gainFlame(18)
                            arenaKitStates[i] = .nonna(nonna)
                            let retData = MoveData(startup: 0, active: 1, recovery: 0, reach: 440,
                                                   damage: DuelNonnaState.owlReturnDamage, push: 200, knockdown: false,
                                                   hitStop: 6, stunTicks: targetUnbreakable ? 0 : DuelNonnaState.owlReturnStunTicks)
                            applyHit(from: i, move: .skill1, data: retData, direction: towardOwner, isCompanion: true,
                                     hitZone: .high, contactX: nonna.owlX, contactY: target.y + 1380)
                            if ruleset == .shadowArena {
                                let heal = (maximumHealth(i) * DuelNonnaState.spiritHealPermille) / 1000
                                fighters[i].health = min(maximumHealth(i), fighters[i].health + heal)
                            }
                            events.append(.nonnaOwlHit(owner: i, damage: scaledDamage(DuelNonnaState.owlReturnDamage), returned: true))
                            if case .nonna(let updated) = arenaKitStates[i] { nonna = updated }
                        }
                        if abs(nonna.owlX - ownerX) <= 220 || nonna.owlTimer >= 40 {
                            nonna.owlCooldown = (nonna.owlHitOut && nonna.owlHitBack) ? 0 : DuelNonnaState.owlCooldownTicks
                            nonna.owlPhase = .idle
                            nonna.owlTimer = 0
                        }
                    }
                }
                arenaKitStates[i] = .nonna(nonna)

            case .midnight, .emperor, .legionKing, .monkeyKing, .none:
                break
            }
        }
    }

    private mutating func detonateInquisitorStigmata(attacker: Int) {
        let defender = 1 - attacker
        guard case .inquisitor(var inq) = arenaKitStates[attacker] else { return }
        let damage = scaledDamage(inq.stigmataFlashDamage)
        inq.dispelStigmata()
        inq.gainLight(18)
        arenaKitStates[attacker] = .inquisitor(inq)

        var target = fighters[defender]
        guard target.health > 0, target.invulnerable == 0 else { return }
        // Purging the Scourge + Sacred Euphoria: Stigmata flash burns ALL enemy resource gauges, heals Xu Xiao, and launches into JUGGLE!
        target.health = max(0, target.health - damage)
        target.energy = max(0, target.energy - DuelInquisitorState.stigmataEnergyBurn)
        if var defShogun = shogunStates[defender] {
            defShogun.shadowEnergy = max(0, defShogun.shadowEnergy - DuelInquisitorState.stigmataEnergyBurn)
            target.energy = defShogun.shadowEnergy
            shogunStates[defender] = defShogun
        }
        if case .midnight(var defMid) = arenaKitStates[defender] {
            defMid.shadowEnergy = max(0, defMid.shadowEnergy - DuelInquisitorState.stigmataEnergyBurn)
            arenaKitStates[defender] = .midnight(defMid)
        } else if case .nonna(var defNonna) = arenaKitStates[defender] {
            defNonna.flamePower = max(0, defNonna.flamePower - DuelInquisitorState.stigmataEnergyBurn)
            arenaKitStates[defender] = .nonna(defNonna)
        }
        if ruleset == .shadowArena && target.health > 0 {
            // True SF4 Juggle launch! (knockdown = 0 while airborne so Xu Xiao can juggle combo!)
            target.knockdown = 0
            target.stun = 38
            target.velocityY = 165
            target.juggleHits = 0
        } else {
            target.knockdown = 40
            target.stun = 24
        }
        target.lastHitZone = .high
        target.lastContactX = target.x
        target.lastContactY = target.y + 1500
        target.attack = nil
        target.guarding = false
        target.flash = 10
        fighters[defender] = target

        fighters[attacker].health = min(maximumHealth(attacker), fighters[attacker].health + (damage * 25) / 100)
        landedHits[attacker] += 1
        damageDealt[attacker] += damage
        hitStop = max(hitStop, 8)
        events.append(.inquisitorStigmataFlash(attacker: attacker, damage: damage))
        events.append(.hit(attacker: attacker, damage: damage))
    }

    private mutating func updateFighter(_ i: Int, input: Input, taps: Buttons, command: DuelWeaponCommand?) {
        if shogunStates[i] != nil {
            updateShogunCompanion(i, taps: taps, command: command)
        }
        let maxHP = maximumHealth(i)
        // Tick SF4 hero resource/state timers before action selection.
        var nonnaRecalledOwl = false
        switch arenaKitStates[i] {
        case .inquisitor(var inq):
            inq.rangedCooldown = max(0, inq.rangedCooldown - 1)
            inq.deliveranceCooldown = max(0, inq.deliveranceCooldown - 1)
            if inq.formOfLightTicks > 0 {
                inq.formOfLightTicks -= 1
                inq.lightPower = (inq.formOfLightTicks * DuelInquisitorState.maxLightPower) / DuelInquisitorState.formOfLightDurationTicks
            }
            let martyrdomThreshold = (maxHP * DuelInquisitorState.martyrdomThresholdHP) / 1000
            if fighters[i].health <= martyrdomThreshold && !inq.martyrdomUsed && fighters[i].health > 0 {
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
            nonna.ancientFuryTicks = max(0, nonna.ancientFuryTicks - 1)
            if nonna.flameFormTicks > 0 {
                nonna.flameFormTicks -= 1
                nonna.flamePower = (nonna.flameFormTicks * DuelNonnaState.maxFlamePower) / DuelNonnaState.flameFormMaxTicks
                if nonna.flameFormTicks == 0 {
                    // The Great Hearth: retain Flame block-break for one final strike!
                    nonna.empoweredStrikeReady = true
                }
            }
            // Manual Owl recall can be triggered at any moment while Owl is out or latched!
            if (taps.contains(.skill1) || command == .ranged) && (nonna.owlPhase == .latched || nonna.owlPhase == .outbound) {
                nonna.recallOwl()
                nonnaRecalledOwl = true
            }
            arenaKitStates[i] = .nonna(nonna)
        case .midnight(var mid):
            mid.shadowShiftTicks = max(0, mid.shadowShiftTicks - 1)
            mid.shadowFormTicks = max(0, mid.shadowFormTicks - 1)
            mid.blinkStanceTicks = max(0, mid.blinkStanceTicks - 1)
            mid.blinkCooldown = max(0, mid.blinkCooldown - 1)
            mid.rangedCooldown = max(0, mid.rangedCooldown - 1)
            arenaKitStates[i] = .midnight(mid)
        case .emperor(var emp):
            emp.rangedCooldown = max(0, emp.rangedCooldown - 1)
            emp.transformBurstTicks = max(0, emp.transformBurstTicks - 1)
            arenaKitStates[i] = .emperor(emp)
        case .legionKing(var lk):
            lk.chainCooldown = max(0, lk.chainCooldown - 1)
            lk.chainActiveTicks = max(0, lk.chainActiveTicks - 1)
            if lk.chainActiveTicks == 0 { lk.chainSnagged = false }
            lk.reviveAnimTicks = max(0, lk.reviveAnimTicks - 1)
            lk.shadowEmpoweredTicks = max(0, lk.shadowEmpoweredTicks - 1)
            arenaKitStates[i] = .legionKing(lk)
        case .monkeyKing(var mk):
            mk.ascensionCooldown = max(0, mk.ascensionCooldown - 1)
            mk.heavenlyAuraTicks = max(0, mk.heavenlyAuraTicks - 1)
            mk.pillarShowTicks = max(0, mk.pillarShowTicks - 1)
            if mk.ascensionTicks > 0 {
                mk.ascensionTicks -= 1
                mk.pillarShowTicks = max(mk.pillarShowTicks, 2)
                if mk.ascensionTicks == 0 {
                    mk.exitAscension()
                }
            }
            arenaKitStates[i] = .monkeyKing(mk)
        case .none:
            break
        }

        if guardRecoveryTicks[i] > 0 { guardRecoveryTicks[i] -= 1 }
        var f = fighters[i]
        f.flash = max(0, f.flash - 1); f.invulnerable = max(0, f.invulnerable - 1)
        f.stun = max(0, f.stun - 1); f.walking = false; f.movementDirection = 0
        if f.frozenTicks > 0 {
            f.frozenTicks -= 1
            f.stun = max(f.stun, 1)
            f.guarding = false
        }
        // Monkey King Ascension Perch: hold Sun Deng atop the 2.12m Jingu Pillar and dispatch Plunge / Pillar Slam / Dismount!
        if case .monkeyKing(var mk) = arenaKitStates[i], mk.isPerchedOnPillar {
            if f.stun > 0 || f.knockdown > 0 || f.frozenTicks > 0 || f.health <= 0 {
                mk.exitAscension()
                arenaKitStates[i] = .monkeyKing(mk)
            } else {
                f.facing = fighters[1 - i].x >= f.x ? 1 : -1
                f.y = DuelMonkeyKingState.ascensionPerchHeightMM
                f.velocityY = 0
                f.velocityX = 0
                f.guarding = false
                f.energy = mk.shadowEnergy
                let wantsPlunge = taps.contains(.light) || taps.contains(.heavy) ||
                    command == .weapon || command == .weaponForward || command == .heavy
                let wantsSlam = taps.contains(.ultimate) || taps.contains(.skill1) || taps.contains(.skill2) ||
                    command == .shadow || command == .ranged || command == .weaponDown || command == .weaponUp ||
                    command == .kick || command == .kickDown
                let wantsDismount = input.move == -f.facing || input.vertical < 0 || command == .weaponBack
                if wantsSlam {
                    mk.exitAscension(keepPillarTicks: 30)
                    if mk.shadowEnergy >= DuelMonkeyKingState.maxShadowEnergy {
                        mk.shadowEnergy = 0
                    }
                    f.energy = mk.shadowEnergy
                    f.attack = Attack(move: .monkeyHeavenlyPillar)
                    f.y = 820
                    f.velocityY = -45
                    arenaKitStates[i] = .monkeyKing(mk)
                } else if wantsPlunge {
                    mk.exitAscension(keepPillarTicks: 20)
                    arenaKitStates[i] = .monkeyKing(mk)
                    f.attack = Attack(move: .monkeyAscensionPlunge)
                    f.y = 920
                    f.velocityY = -40
                } else if wantsDismount {
                    mk.exitAscension()
                    arenaKitStates[i] = .monkeyKing(mk)
                    f.x = min(Self.rightWall, max(Self.leftWall, f.x - f.facing * 260))
                    f.velocityY = -30
                }
                fighters[i] = f
                return
            }
        }
        // Velocity-based sliding knockback + floor friction + Wall-Splat (runs cleanly AFTER hitStop releases!)
        if ruleset == .shadowArena && f.velocityX != 0 {
            let nextX = f.x + f.velocityX
            let hitLeftWall = nextX <= Self.leftWall && f.velocityX < 0
            let hitRightWall = nextX >= Self.rightWall && f.velocityX > 0
            f.x = min(Self.rightWall, max(Self.leftWall, nextX))
            if (hitLeftWall || hitRightWall) && abs(f.velocityX) >= 65 && (f.stun > 0 || f.knockdown > 20 || f.y > 0) && f.health > 0 {
                // Authentic SF4 Wall-Splat: slam into courtyard boundary -> bounce into juggle!
                let bounceSign = hitLeftWall ? 1 : -1
                f.velocityX = bounceSign * 42
                f.velocityY = max(f.velocityY, 125)
                f.stun = max(f.stun, 34)
                f.knockdown = 0
                f.juggleHits = 0
                f.attack = nil
                f.guarding = false
                hitStop = max(hitStop, 6)
                events.append(.wallSplat(defender: i))
            } else {
                let friction = f.y > 0 ? 8 : 24
                if abs(f.velocityX) <= friction { f.velocityX = 0 }
                else { f.velocityX += (f.velocityX > 0 ? -friction : friction) }
            }
        }
        if f.knockdown > 0 {
            if ruleset == .shadowArena && f.health > 0 && f.y == 0 && f.knockdown <= 22 && f.attack == nil {
                let wantsWakeupKick: Bool = {
                    guard let cmd = command else { return false }
                    switch cmd {
                    case .kick, .kickForward, .kickUp, .kickDown, .kickBack: return true
                    default: return false
                    }
                }()
                if wantsWakeupKick {
                    f.knockdown = 0; f.stun = 0; f.guarding = false
                    f.invulnerable = max(f.invulnerable, 8)
                    f.facing = fighters[1 - i].x >= f.x ? 1 : -1
                    f.attack = Attack(move: .wakeupKick)
                } else if input.vertical < 0 && input.move != 0 {
                    f.knockdown = 0; f.stun = 0; f.guarding = false
                    f.invulnerable = max(f.invulnerable, 12)
                    f.facing = fighters[1 - i].x >= f.x ? 1 : -1
                    let rollMove: Move = (input.move == f.facing) ? .rollForward : .rollBack
                    f.attack = Attack(move: rollMove)
                } else {
                    f.knockdown -= 1; f.guarding = false
                    if f.knockdown == 0 { f.invulnerable = 20 }
                }
            } else {
                f.knockdown -= 1; f.guarding = false
                if f.knockdown == 0 { f.invulnerable = 20 }
            }
        }
        if f.stun == 0 && f.knockdown == 0 && f.y == 0 && f.frozenTicks == 0 {
            comboCount[1 - i] = 0
            f.juggleHits = 0
        }
        if f.y > 0 || f.velocityY > 0 {
            f.y = max(0, f.y + f.velocityY); f.velocityY -= Self.gravity
            if f.y == 0 {
                f.velocityY = 0
                if ruleset == .shadowArena {
                    let keepDiveAttack = f.attack?.move == .monkeyAscensionPlunge || f.attack?.move == .monkeyHeavenlyPillar
                    if !keepDiveAttack {
                        f.attack = nil
                    }
                    if f.juggleHits > 0 || f.stun > 0 {
                        // Hard knockdown upon hitting ground after an airborne juggle!
                        f.knockdown = max(f.knockdown, 28)
                        f.juggleHits = 0
                    }
                    guardRecoveryTicks[i] = max(guardRecoveryTicks[i], 4)
                }
            }
        }
        if f.attack == nil { f.facing = fighters[1 - i].x >= f.x ? 1 : -1 }
        let isChargingShogunHeavy = (shogunStates[i]?.heavyChargeTicks ?? 0) > 0
        if ruleset == .shadowArena {
            let standingOrBack = input.move == 0 || input.move == -f.facing
            let noActionIntent = command == nil && taps.isEmpty && input.vertical == 0 && input.dashDirection == 0 && !isChargingShogunHeavy
            let autoBlockReady = standingOrBack && noActionIntent && guardRecoveryTicks[i] == 0
            f.guarding = (input.guardHeld || autoBlockReady) && f.y == 0 && f.attack == nil &&
                (f.stun == 0 || f.guarding) && f.knockdown == 0 && f.frozenTicks == 0
        } else {
            f.guarding = input.guardHeld && f.y == 0 && f.attack == nil &&
                (f.stun == 0 || f.guarding) && f.knockdown == 0
        }
        if !f.guarding { f.guardMeter = min(1000, f.guardMeter + 3) }
        if let shogun = shogunStates[i] {
            f.energy = shogun.shadowEnergy
        } else if case .emperor(let emp) = arenaKitStates[i] {
            f.energy = emp.shadowEnergy
        } else if case .legionKing(let lk) = arenaKitStates[i] {
            f.energy = lk.shadowEnergy
        } else if case .monkeyKing(let mk) = arenaKitStates[i] {
            f.energy = mk.shadowEnergy
        } else {
            if frame % 12 == 0 { f.energy = min(100, f.energy + 1) }
        }
        if f.stun > 0 || f.knockdown > 0 || f.guarding || f.y > 0 || f.frozenTicks > 0 {
            shogunStates[i]?.heavyChargeTicks = 0
        }
        if f.stun == 0 && f.knockdown == 0 && f.frozenTicks == 0 {
            if let rollAtk = f.attack, rollAtk.move.isRoll {
                let rollActiveTicks = ruleset == .shadowArena ? 24 : 14
                let rollStep = ruleset == .shadowArena ? 68 : 125
                if rollAtk.age < rollActiveTicks {
                    let dir = rollAtk.move == .rollForward ? f.facing : -f.facing
                    f.x = min(Self.rightWall, max(Self.leftWall, f.x + dir * rollStep))
                    f.movementDirection = dir
                }
                fighters[i] = f
                return
            }
            // Active Dash Forward (cancelable into Dash-Grab or attack!) / Dash Back (nimble hop)
            if let dashAtk = f.attack, dashAtk.move.isDash {
                let cancelAge = ruleset == .shadowArena ? 6 : 4
                let canCancelDash = dashAtk.move == .dashForward && dashAtk.age >= cancelAge && (command != nil || !taps.isEmpty)
                if canCancelDash {
                    f.attack = nil
                } else {
                    let dashActiveTicks = ruleset == .shadowArena ? 15 : 10
                    if dashAtk.age < dashActiveTicks {
                        let dir = dashAtk.move == .dashForward ? f.facing : -f.facing
                        let step = ruleset == .shadowArena
                            ? (dashAtk.move == .dashForward ? 88 : 84)
                            : (dashAtk.move == .dashForward ? 150 : 145)
                        f.x = min(Self.rightWall, max(Self.leftWall, f.x + dir * step))
                        f.movementDirection = dir
                    }
                    fighters[i] = f
                    return
                }
            }
            // Double-tap Dash Forward / Back-Hop trigger in Shadow Arena!
            if ruleset == .shadowArena && f.y == 0 && f.attack == nil && !isChargingShogunHeavy && input.dashDirection != 0 {
                // Midnight Precise Shift: Back-Dash while phased blinks cleanly away!
                if case .midnight(var mid) = arenaKitStates[i], mid.isPhasedOut, input.dashDirection == -f.facing {
                    f.x = min(Self.rightWall, max(Self.leftWall, f.x - f.facing * 1450))
                    mid.shadowShiftTicks = 0
                    arenaKitStates[i] = .midnight(mid)
                }
                let dashMove: Move = (input.dashDirection == f.facing) ? .dashForward : .dashBack
                f.guarding = false
                if dashMove == .dashBack { f.invulnerable = max(f.invulnerable, 10) }
                f.attack = Attack(move: dashMove)
                let dir = dashMove == .dashForward ? f.facing : -f.facing
                f.x = min(Self.rightWall, max(Self.leftWall, f.x + dir * (dashMove == .dashForward ? 88 : 84)))
                f.movementDirection = dir
                fighters[i] = f
                return
            }
            if ruleset == .shadowArena && f.y == 0 && f.attack == nil && guardRecoveryTicks[i] == 0 &&
                !isChargingShogunHeavy && input.vertical < 0 && input.move != 0 && command == nil && taps.isEmpty {
                let rollMove: Move = (input.move == f.facing) ? .rollForward : .rollBack
                f.guarding = false
                f.invulnerable = max(f.invulnerable, 16)
                f.attack = Attack(move: rollMove)
                let dir = rollMove == .rollForward ? f.facing : -f.facing
                f.x = min(Self.rightWall, max(Self.leftWall, f.x + dir * 68))
                f.movementDirection = dir
                fighters[i] = f
                return
            }
            if taps.contains(.jump) && f.y == 0 && f.attack == nil {
                shogunStates[i]?.heavyChargeTicks = 0
                f.velocityY = Self.jumpVelocity; f.guarding = false; events.append(.jumped(player: i))
            }
            let defensiveBackWalk = ruleset == .shadowArena && f.guarding && f.attack == nil && input.move == -f.facing
            if defensiveBackWalk {
                let isMidPhased = midnightState(i)?.isPhasedOut == true
                let baseSpeed = isMidPhased ? DuelMidnightState.preciseShiftSpeed : (f.hero == .gale ? 42 : f.hero == .wuYong ? 44 : f.hero == .ember ? 48 : 46)
                let backSpeed = (baseSpeed * 8) / 10
                f.x += input.move * backSpeed
                f.walking = true
                f.movementDirection = input.move
            } else if !f.guarding {
                let isChargingHeavy = (shogunStates[i]?.heavyChargeTicks ?? 0) > 0
                let isMidPhased = midnightState(i)?.isPhasedOut == true
                let heroWalkSpeed = ruleset == .shadowArena
                    ? (f.hero == .gale ? 42 : f.hero == .wuYong ? 44 : f.hero == .ember ? 48 : 46)
                    : (f.hero == .gale ? 66 : f.hero == .wuYong ? 70 : f.hero == .ember ? 76 : 74)
                let baseSpeed = isMidPhased ? DuelMidnightState.preciseShiftSpeed : heroWalkSpeed
                let speed = baseSpeed * (f.attack == nil ? 10 : 4) / 10
                if f.attack?.move != .ultimate && !isChargingHeavy {
                    f.x += min(1, max(-1, input.move)) * speed; f.walking = input.move != 0
                    f.movementDirection = min(1, max(-1, input.move))
                }
                let foe = fighters[1 - i]
                // Midnight Precise Shift: attacking/forward-striking while phased teleports right onto the opponent!
                if ruleset == .shadowArena && f.attack == nil && f.y == 0,
                   case .midnight(var mid) = arenaKitStates[i], mid.isPhasedOut,
                   (command != nil || !taps.isEmpty) && command != .ranged && !taps.contains(.skill1) && !taps.contains(.jump) {
                    let targetX = foe.x - f.facing * 740
                    f.x = min(Self.rightWall, max(Self.leftWall, targetX))
                    mid.shadowShiftTicks = 0
                    arenaKitStates[i] = .midnight(mid)
                }
                let absDist = abs(foe.x - f.x)
                let canCloseThrow = ruleset == .shadowArena && f.y == 0 && foe.y == 0 &&
                    foe.knockdown == 0 && foe.invulnerable == 0 && absDist <= Self.throwMaxDistance
                if var attack = f.attack {
                    let data = moveData(attack.move, hero: f.hero, chargeTicks: attack.chargeTicks)
                    if (taps.contains(.light) || command == .weapon) && attack.age >= data.startup && attack.age < data.duration &&
                        (attack.move == .jab || attack.move == .cross) { attack.comboQueued = true }
                    f.attack = attack
                } else if ruleset == .shadowArena && f.y > 0 {
                    if let cmd = command {
                        switch cmd {
                        case .kick, .kickForward, .kickUp, .kickDown, .kickBack:
                            f.attack = Attack(move: .kickUp)
                        case .weapon, .weaponForward, .weaponUp, .weaponDown, .weaponBack, .heavy:
                            f.attack = Attack(move: .weaponDown)
                        case .ranged, .shadow:
                            break
                        }
                    }
                } else if var shogun = shogunStates[i] {
                    if shogun.heavyChargeTicks > 0 {
                        if input.heavyHeld && shogun.heavyChargeTicks < DuelShogunState.heavyMaxChargeTicks {
                            shogun.heavyChargeTicks += 1
                            f.walking = false; f.movementDirection = 0
                        } else {
                            f.attack = Attack(move: .heavy, chargeTicks: shogun.heavyChargeTicks)
                            shogun.heavyChargeTicks = 0
                        }
                    } else if (taps.contains(.ultimate) || command == .shadow) && shogun.canUseShadowAbility && f.y == 0 && f.velocityY == 0 {
                        let shadowMove: Move = (input.move == -f.facing || input.vertical != 0) ? .shogunDespotism : .shogunFierceReprisal
                        f.attack = Attack(move: shadowMove)
                        shogun.shadowAbilityCooldown = DuelShogunState.shadowAbilityCooldownTicks
                        f.walking = false
                    } else if (taps.contains(.skill1) || command == .kickForward) && shogun.canUseRuthlessKick && f.y == 0 {
                        f.attack = Attack(move: command == .kickForward ? .kickForward : .skill1)
                        shogun.ruthlessKickCooldown = DuelShogunState.ruthlessKickCooldownTicks
                    } else if taps.contains(.heavy) || command == .heavy {
                        if input.heavyHeld && f.y == 0 {
                            shogun.heavyChargeTicks = command == .heavy ? DuelWeaponInput.longPressTicks : 1
                            f.walking = false; f.movementDirection = 0
                        } else {
                            f.attack = Attack(move: .heavy, chargeTicks: command == .heavy ? DuelWeaponInput.longPressTicks : 0)
                        }
                    } else if let cmd = command {
                        switch cmd {
                        case .weapon: f.attack = Attack(move: .jab)
                        case .weaponForward: f.attack = Attack(move: canCloseThrow ? .throwForward : .weaponForward)
                        case .weaponBack: f.attack = Attack(move: canCloseThrow ? .throwBack : .weaponBack)
                        case .weaponUp: f.attack = Attack(move: .weaponUp)
                        case .weaponDown: f.attack = Attack(move: .weaponDown)
                        case .kick: f.attack = Attack(move: .kick)
                        case .kickForward: f.attack = Attack(move: .kickForward)
                        case .kickUp: f.attack = Attack(move: .kickUp)
                        case .kickDown: f.attack = Attack(move: .kickDown)
                        case .kickBack: f.attack = Attack(move: .kickBack)
                        case .heavy, .shadow, .ranged: break
                        }
                    } else if taps.contains(.light) {
                        f.attack = Attack(move: .jab)
                    }
                    shogunStates[i] = shogun
                } else {
                    var move: Move?
                    let hotBloodThreshold = (maxHP * DuelNonnaState.hotBloodThresholdHP) / 1000
                    // 1. Hero-specific Ultimate / Form / Directional Shadow 搓招
                    if (taps.contains(.ultimate) || command == .shadow) && f.y == 0 && f.velocityY == 0 {
                        if case .emperor(var emp) = arenaKitStates[i] {
                            if emp.canTransformToBeast {
                                move = .emperorTransform
                                f.invulnerable = max(f.invulnerable, 16)
                                f.walking = false
                            } else if emp.canCastBeastShadow {
                                emp.shadowEnergy = 0
                                arenaKitStates[i] = .emperor(emp)
                                f.energy = 0
                                move = .emperorBeastShadowJump
                                f.walking = false
                            }
                        } else if case .legionKing(var lk) = arenaKitStates[i] {
                            if lk.canCastShadowAbility {
                                lk.shadowEnergy = 0
                                arenaKitStates[i] = .legionKing(lk)
                                f.energy = 0
                                let explicitForward = input.move * f.facing > 0 && input.vertical >= 0
                                let wantsDown = !explicitForward && (input.vertical < 0 || foe.knockdown > 0)
                                move = wantsDown ? .legionShadowDown : .legionShadowForward
                                f.walking = false
                            }
                        } else if case .monkeyKing(var mk) = arenaKitStates[i] {
                            if mk.canCastHeavenlyPillar {
                                mk.shadowEnergy = 0
                                mk.pillarX = f.x
                                mk.pillarShowTicks = 34
                                arenaKitStates[i] = .monkeyKing(mk)
                                f.energy = 0
                                move = .monkeyHeavenlyPillar
                                f.walking = false
                            }
                        } else if taps.contains(.ultimate) && f.hero == .liu && f.energy == 100 {
                            move = .ultimate; f.energy = 0; f.walking = false
                        } else if case .inquisitor(var inq) = arenaKitStates[i] {
                            if inq.isInFormOfLight {
                                move = .inquisitorLightSpin
                                f.invulnerable = max(f.invulnerable, 16)
                            } else if inq.canEnterFormOfLight {
                                inq.enterFormOfLight()
                                arenaKitStates[i] = .inquisitor(inq)
                                f.invulnerable = max(f.invulnerable, DuelInquisitorState.entryInvulnerableTicks)
                                events.append(.inquisitorFormOfLight(fighter: i))
                                triggerNonnaAncientFury(against: i)
                            } else if command == .shadow {
                                if ruleset == .shadowArena && inq.canCastDeliverance {
                                    inq.deliveranceCooldown = DuelInquisitorState.deliveranceCooldownTicks
                                    arenaKitStates[i] = .inquisitor(inq)
                                    move = .skill2
                                } else if ruleset == .laboratory && f.energy >= 45 {
                                    move = .skill2; f.energy -= 45
                                }
                            }
                        } else if case .nonna(var nonna) = arenaKitStates[i] {
                            if nonna.canEnterFlameForm {
                                nonna.enterFlameForm()
                                arenaKitStates[i] = .nonna(nonna)
                                if f.health <= hotBloodThreshold {
                                    f.invulnerable = max(f.invulnerable, 22)
                                }
                                events.append(.nonnaFlameForm(fighter: i))
                            } else if ruleset == .shadowArena && nonna.isInFlameForm && !nonna.wolfActive {
                                nonna.summonWolf(from: f.x, facing: f.facing)
                                arenaKitStates[i] = .nonna(nonna)
                            } else if command == .shadow && ruleset == .laboratory && f.energy == 100 && absDist <= 1050 {
                                move = .ultimate; f.energy = 0; f.walking = false
                            }
                        } else if case .midnight(var mid) = arenaKitStates[i] {
                            let wantsBlink = input.move == -f.facing || input.vertical < 0
                            if ruleset == .shadowArena {
                                if wantsBlink && mid.canUseBlink {
                                    mid.shadowEnergy = max(0, mid.shadowEnergy - DuelMidnightState.blinkShadowCost)
                                    mid.blinkStanceTicks = DuelMidnightState.blinkStanceDurationTicks
                                    mid.blinkCooldown = DuelMidnightState.blinkCooldownTicks
                                    arenaKitStates[i] = .midnight(mid)
                                    f.walking = false
                                } else if mid.canUseRemoval {
                                    mid.shadowEnergy = 0
                                    arenaKitStates[i] = .midnight(mid)
                                    move = .midnightRemoval
                                    f.walking = false
                                } else if mid.canUseBlink {
                                    mid.shadowEnergy = max(0, mid.shadowEnergy - DuelMidnightState.blinkShadowCost)
                                    mid.blinkStanceTicks = DuelMidnightState.blinkStanceDurationTicks
                                    mid.blinkCooldown = DuelMidnightState.blinkCooldownTicks
                                    arenaKitStates[i] = .midnight(mid)
                                    f.walking = false
                                }
                            } else {
                                if mid.canUseRemoval && (input.move != -f.facing && input.vertical >= 0 || mid.blinkCooldown > 0) {
                                    mid.shadowEnergy = 0
                                    arenaKitStates[i] = .midnight(mid)
                                    move = .midnightRemoval
                                    f.walking = false
                                } else if command == .shadow && mid.blinkCooldown == 0 && f.energy >= 45 {
                                    f.energy -= 45
                                    mid.blinkStanceTicks = DuelMidnightState.blinkStanceDurationTicks
                                    mid.blinkCooldown = DuelMidnightState.blinkCooldownTicks
                                    arenaKitStates[i] = .midnight(mid)
                                    f.walking = false
                                }
                            }
                        }
                    }
                    // 2. Hero-specific Skill2
                    if move == nil && taps.contains(.skill2) {
                        if case .emperor(var emp) = arenaKitStates[i] {
                            if emp.canTransformToBeast {
                                move = .emperorTransform
                                f.invulnerable = max(f.invulnerable, 16)
                                f.walking = false
                            } else if emp.canCastBeastShadow {
                                emp.shadowEnergy = 0
                                arenaKitStates[i] = .emperor(emp)
                                f.energy = 0
                                move = .emperorBeastShadowJump
                                f.walking = false
                            }
                        } else if case .legionKing(var lk) = arenaKitStates[i], lk.canCastShadowAbility {
                            lk.shadowEnergy = 0
                            arenaKitStates[i] = .legionKing(lk)
                            f.energy = 0
                            move = .legionShadowForward
                        } else if case .monkeyKing(var mk) = arenaKitStates[i], mk.canCastHeavenlyPillar {
                            mk.shadowEnergy = 0
                            mk.pillarX = f.x
                            mk.pillarShowTicks = 34
                            arenaKitStates[i] = .monkeyKing(mk)
                            f.energy = 0
                            move = .monkeyHeavenlyPillar
                        } else if case .inquisitor(let inq) = arenaKitStates[i], inq.isInFormOfLight {
                            move = .inquisitorLightSpin
                            f.invulnerable = max(f.invulnerable, 16)
                        } else if case .nonna(var nonna) = arenaKitStates[i], nonna.canEnterFlameForm {
                            nonna.enterFlameForm()
                            arenaKitStates[i] = .nonna(nonna)
                            if f.health <= hotBloodThreshold {
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
                    // 3. Ranged / Soaring Form of Light 4-Move Mapping / Directional Weapon & Kick / Heavy / Light
                    let inquisitorSoaring = ruleset == .shadowArena && (inquisitorState(i)?.isInFormOfLight == true)
                    if move == nil {
                        if (taps.contains(.skill1) || command == .ranged) && !nonnaRecalledOwl {
                            if ruleset == .shadowArena {
                                switch arenaKitStates[i] {
                                case .emperor(var emp):
                                    if !emp.isBeastForm && emp.canCastRanged {
                                        emp.rangedCooldown = DuelEmperorState.rangedCooldownTicks
                                        arenaKitStates[i] = .emperor(emp)
                                        move = .skill1
                                    } else if emp.isBeastForm && emp.rangedCooldown == 0 {
                                        emp.rangedCooldown = 65
                                        arenaKitStates[i] = .emperor(emp)
                                        move = .weaponForward
                                    }
                                case .legionKing(var lk):
                                    if lk.canCastChain {
                                        lk.chainCooldown = DuelLegionKingState.chainCooldownTicks
                                        arenaKitStates[i] = .legionKing(lk)
                                        move = .legionShadowChain
                                    }
                                case .monkeyKing(var mk):
                                    if mk.canEnterAscension && f.y == 0 {
                                        mk.enterAscension(at: f.x)
                                        arenaKitStates[i] = .monkeyKing(mk)
                                        f.y = DuelMonkeyKingState.ascensionPerchHeightMM
                                        f.velocityY = 0
                                        f.guarding = false
                                        f.walking = false
                                        events.append(.monkeyAscensionPerch(fighter: i))
                                        fighters[i] = f
                                        return
                                    }
                                case .inquisitor(var inq):
                                    if inq.canCastSalvation {
                                        inq.rangedCooldown = DuelInquisitorState.rangedCooldownTicks
                                        arenaKitStates[i] = .inquisitor(inq)
                                        move = .skill1
                                    }
                                case .nonna(var nonna):
                                    if nonna.canLaunchOwl {
                                        nonna.launchOwl(from: f.x, facing: f.facing)
                                        arenaKitStates[i] = .nonna(nonna)
                                        move = .skill1
                                    }
                                case .midnight(var mid):
                                    if mid.canCastKunai {
                                        mid.rangedCooldown = DuelMidnightState.rangedCooldownTicks
                                        arenaKitStates[i] = .midnight(mid)
                                        move = .skill1
                                    }
                                case .none:
                                    if f.energy >= 30 { move = .skill1; f.energy -= 30 }
                                }
                            } else if f.energy >= 30 {
                                if case .nonna(var nonna) = arenaKitStates[i] {
                                    if nonna.owlPhase == .idle && nonna.owlCooldown == 0 {
                                        nonna.launchOwl(from: f.x, facing: f.facing)
                                        arenaKitStates[i] = .nonna(nonna)
                                    }
                                    move = .skill1; f.energy -= 30
                                } else {
                                    move = .skill1; f.energy -= 30
                                }
                            }
                        } else if taps.contains(.heavy) || command == .heavy {
                            if inquisitorSoaring {
                                move = .inquisitorLightSpin
                                f.invulnerable = max(f.invulnerable, 16)
                            } else {
                                move = .heavy
                            }
                        } else if let cmd = command {
                            if inquisitorSoaring {
                                // Authentic SF4 Grand Inquisitor Form of Light soaring 4-move aerial kit!
                                switch cmd {
                                case .weapon, .weaponUp: move = .inquisitorLightUp
                                case .weaponForward: move = .inquisitorLightForward
                                case .weaponDown, .weaponBack: move = .inquisitorLightDown
                                case .kick: move = .kick
                                case .kickForward: move = .kickForward
                                case .kickUp: move = .kickUp
                                case .kickDown: move = .kickDown
                                case .kickBack: move = .kickBack
                                case .heavy, .ranged, .shadow: break
                                }
                            } else {
                                switch cmd {
                                case .weapon: move = .jab
                                case .weaponForward: move = canCloseThrow ? .throwForward : .weaponForward
                                case .weaponBack: move = canCloseThrow ? .throwBack : .weaponBack
                                case .weaponUp: move = .weaponUp
                                case .weaponDown: move = .weaponDown
                                case .kick: move = .kick
                                case .kickForward: move = .kickForward
                                case .kickUp: move = .kickUp
                                case .kickDown: move = .kickDown
                                case .kickBack: move = .kickBack
                                case .heavy, .ranged, .shadow: break
                                }
                            }
                        } else if taps.contains(.light) {
                            move = inquisitorSoaring ? .inquisitorLightUp : .jab
                        }
                    }
                    if let move { f.attack = Attack(move: move) }
                }
                if let attack = f.attack {
                    if f.hero == .wuYong {
                        if (attack.move == .jab || attack.move == .cross || attack.move == .finisher) &&
                            input.move == f.facing && attack.age < 10 {
                            f.x += f.facing * 42
                        } else if attack.move == .heavy && attack.age >= 8 && attack.age < 22 {
                            f.x += f.facing * 52
                        } else if (attack.move == .skill1 || attack.move == .kickForward) && attack.age < 18 {
                            f.x += f.facing * 92
                        } else if attack.move == .weaponForward && attack.age < 21 {
                            f.x += f.facing * 68
                        } else if attack.move == .weaponBack && attack.age < 6 {
                            f.x -= f.facing * 68
                        } else if attack.move == .shogunFierceReprisal && attack.age >= 5 && attack.age < 22 {
                            f.x += f.facing * 138
                        }
                    } else {
                        if attack.move == .skill1, f.hero != .gale, !(ruleset == .shadowArena && (f.hero == .ember || f.hero == .liu)), attack.age < 11 { f.x += f.facing * 115 }
                        if attack.move == .skill2, f.hero == .gale, attack.age < 7 { f.x -= f.facing * 85 }
                        if attack.move == .inquisitorLightSpin, attack.age < 12 { f.x += f.facing * 110 }
                        if attack.move == .inquisitorLightForward, attack.age < 14 { f.x += f.facing * 125 }
                        if attack.move == .inquisitorLightDown, attack.age < 10 { f.x += f.facing * 80 }
                        if attack.move == .emperorBeastShadowJump, attack.age >= 5 && attack.age < 17 { f.x += f.facing * 130 }
                        if attack.move == .legionShadowForward, attack.age >= 6 && attack.age < 20 { f.x += f.facing * 118 }
                        if attack.move == .monkeyAscensionPlunge, attack.age < 18 { f.x += f.facing * 142 }
                        if attack.move == .monkeyHeavenlyPillar, attack.age >= 5 && attack.age < 16 { f.x += f.facing * 92 }
                        if ruleset == .shadowArena, attack.move == .heavy, f.hero == .ember, attack.age >= 6 && attack.age < 18 { f.x += f.facing * 125 }
                        if attack.move == .weaponForward && attack.age < 21 { f.x += f.facing * 68 }
                        if attack.move == .weaponBack && attack.age < 6 { f.x -= f.facing * 68 }
                        if attack.move == .kickForward && attack.age < 12 { f.x += f.facing * 88 }
                    }
                }
            }
        }
        f.x = min(Self.rightWall, max(Self.leftWall, f.x)); fighters[i] = f
    }
    private mutating func separateBodies() {
        guard abs(fighters[0].y - fighters[1].y) < 1250 else { return }
        if fighters.contains(where: { $0.attack?.move == .rollForward && $0.invulnerable > 0 }) { return }
        let minWidth = ruleset == .shadowArena ? Self.shadowArenaBodyWidth : Self.bodyWidth
        let gap = fighters[1].x - fighters[0].x
        let overlap = minWidth - abs(gap)
        guard overlap > 0 else { return }
        let sign = gap >= 0 ? 1 : -1
        fighters[0].x = min(Self.rightWall, max(Self.leftWall, fighters[0].x - sign * (overlap + 1) / 2))
        fighters[1].x = min(Self.rightWall, max(Self.leftWall, fighters[1].x + sign * (overlap + 1) / 2))
        let residual = minWidth - abs(fighters[1].x - fighters[0].x)
        if residual > 0 {
            // Landing can put both centers on the same wall. Resolve the pair
            // inside the arena instead of pushing the second body outside it.
            let left = sign > 0 ? 0 : 1, right = 1 - left
            fighters[left].x = min(fighters[left].x, Self.rightWall - minWidth)
            fighters[right].x = fighters[left].x + minWidth
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
            distance >= 0 && distance <= moveData(.ultimate, hero: .liu).reach
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
        let scaled = scaledDamage(damage)
        let actual = min(scaled, fighters[defender].health)
        fighters[defender].health -= actual; fighters[defender].flash = 8
        if fighters[defender].health == 0 { fighters[defender].knockdown = 36 }
        landedHits[attacker] += 1; damageDealt[attacker] += actual
        events.append(.hit(attacker: attacker, damage: actual))
    }
    private mutating func nextRandomPercent() -> Int {
        random = random &* 6364136223846793005 &+ 1442695040888963407
        return Int((random >> 32) % 100)
    }
    private mutating func applyHit(from attacker: Int, move: Move, data: MoveData, direction: Int, isCompanion: Bool,
                                   hitZone: HitZone = .mid, contactX: Int? = nil, contactY: Int? = nil) {
        let defender = 1 - attacker
        var target = fighters[defender]
        let front = target.facing == -direction
        let attackerMaxHP = maximumHealth(attacker)
        let defenderMaxHP = maximumHealth(defender)
        target.lastHitZone = hitZone
        target.lastContactX = contactX ?? target.x
        target.lastContactY = contactY ?? (target.y + (hitZone == .high ? 1620 : hitZone == .low ? 400 : 1150))

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

        // 1b. Monkey King Ascension Perch: perched at Y=2.12m atop Jingu Pillar evades low/mid grounded strikes, knocked off by anti-air!
        if case .monkeyKing(var defMK) = arenaKitStates[defender], defMK.isPerchedOnPillar {
            let isAntiAir = hitZone == .high || data.hitZone == .high || fighters[attacker].y >= 400 ||
                data.isShadow || move == .legionShadowChain || move == .weaponUp || move == .kickUp
            if !isAntiAir && !isCompanion {
                defMK.gainShadow(14)
                arenaKitStates[defender] = .monkeyKing(defMK)
                target.energy = defMK.shadowEnergy
                fighters[defender] = target
                events.append(.monkeyPerchEvade(fighter: defender))
                return
            } else {
                defMK.exitAscension()
                arenaKitStates[defender] = .monkeyKing(defMK)
            }
        }

        // 2. Midnight Blink Counter-Stance: negate incoming melee/projectile, teleport behind attacker, FREEZE & heal 18%!
        if case .midnight(var defMid) = arenaKitStates[defender], defMid.isInBlinkStance, !isCompanion {
            defMid.blinkStanceTicks = 0
            defMid.gainShadow(DuelMidnightState.blinkCounterShadowReward)
            arenaKitStates[defender] = .midnight(defMid)
            let attackerFacing = fighters[attacker].facing
            let behindX = min(Self.rightWall, max(Self.leftWall, fighters[attacker].x - attackerFacing * 680))
            target.x = behindX
            target.facing = attackerFacing
            let blinkHeal = ruleset == .shadowArena
                ? (defenderMaxHP * DuelMidnightState.blinkCounterHealPermille) / 1000
                : scaledDamage(DuelMidnightState.blinkCounterHeal)
            target.health = min(defenderMaxHP, target.health + blinkHeal)
            target.invulnerable = max(target.invulnerable, 14)
            target.flash = 6
            fighters[defender] = target

            let counterDmg = scaledDamage(DuelMidnightState.blinkCounterDamage)
            fighters[attacker].health = max(0, fighters[attacker].health - counterDmg)
            if ruleset == .shadowArena && fighters[attacker].health > 0 {
                // Authentic SF4 Midnight Blink Freeze: freezes attacker upright for 28 ticks for a free combo!
                fighters[attacker].frozenTicks = DuelMidnightState.blinkCounterFreezeTicks
                fighters[attacker].stun = DuelMidnightState.blinkCounterFreezeTicks
                fighters[attacker].knockdown = 0
                fighters[attacker].velocityX = 0
            } else {
                fighters[attacker].stun = 24
                fighters[attacker].knockdown = 32
            }
            fighters[attacker].lastHitZone = .mid
            fighters[attacker].lastContactX = fighters[attacker].x
            fighters[attacker].lastContactY = fighters[attacker].y + 1180
            fighters[attacker].attack = nil
            fighters[attacker].guarding = false
            fighters[attacker].flash = 10
            landedHits[defender] += 1
            damageDealt[defender] += counterDmg
            hitStop = max(hitStop, 9)
            events.append(.midnightBlinkCounter(attacker: defender, damage: counterDmg))
            events.append(.hit(attacker: defender, damage: counterDmg))
            separateBodies()
            return
        }

        // 3. Overlord of Shadow: Despotism Odachi planted blade absorbs frontal damage.
        if !data.isThrow, let defAttack = target.attack {
            let defData = moveData(defAttack.move, hero: target.hero, chargeTicks: defAttack.chargeTicks)
            if defData.absorbsFrontDamage && front && defAttack.age >= defData.armorStart && defAttack.age < defData.armorEnd {
                events.append(.shogunArmorAbsorbed(defender: defender))
                awardShogunShadow(to: defender, amount: 14)
                hitStop = max(hitStop, 5)
                target.flash = 6; fighters[defender] = target
                return
            }
        }

        // 4. Guard check — Throws, Form of Light, Flame Form, Shadow, Nocturne 4-stack & Block-Breakers shatter guard!
        let midnightNocturneArmed: Bool = {
            guard ruleset == .shadowArena && !isCompanion && !data.isThrow && !move.isKick,
                  case .midnight(let atkMid) = arenaKitStates[attacker] else { return false }
            return atkMid.isNocturneReady
        }()
        let attackerBreaksBlock: Bool = {
            guard !isCompanion else { return false }
            if midnightNocturneArmed { return true }
            if ruleset == .shadowArena && (data.breaksBlock || data.isShadow || data.isCritical || shogunStates[attacker]?.isCataclysm == true) {
                return true
            }
            switch arenaKitStates[attacker] {
            case .inquisitor(let inq): return inq.isInFormOfLight
            case .nonna(let nonna): return nonna.breaksBlockNow
            case .legionKing(let lk): return lk.isShadowEmpowered && move == .heavy
            default: return false
            }
        }()

        if !data.isThrow && target.guarding && front {
            if attackerBreaksBlock {
                target.guardMeter = 0
                target.guarding = false
                events.append(.guardBreak(defender: defender))
            } else if ruleset == .shadowArena {
                let baseScaled = scaledDamage(data.damage)
                let chip = max(12, (baseScaled * data.chipBps) / 10000)
                let actualChip = min(chip, target.health)
                if target.health - actualChip <= 0,
                   case .legionKing(var defLK) = arenaKitStates[defender],
                   !defLK.hasRevivedThisRound {
                    defLK.triggerDarkIncarnation()
                    arenaKitStates[defender] = .legionKing(defLK)
                    target.health = min(defenderMaxHP, DuelLegionKingState.darkIncarnationReviveHP)
                    target.energy = defLK.shadowEnergy
                    target.invulnerable = DuelLegionKingState.darkIncarnationInvulnerableTicks
                    target.stun = 0; target.knockdown = 0; target.guarding = false
                    target.velocityX = 0; target.flash = 10
                    fighters[attacker].velocityX = -direction * 105
                    fighters[defender] = target
                    events.append(.legionDarkIncarnation(fighter: defender))
                    return
                }
                target.health -= actualChip
                damageDealt[attacker] += actualChip
                // Differentiated blockstun (light safe -2, special 0, heavy/armored punishable!)
                target.stun = data.blockStunTicks
                target.guarding = target.health > 0
                if target.health == 0 { target.knockdown = 43 }
                events.append(.blocked(defender: defender))
                if actualChip > 0 { events.append(.chipDamage(attacker: attacker, damage: actualChip)) }
                hitStop = max(hitStop, 4)
                if shogunStates[attacker] != nil && !isCompanion {
                    awardShogunShadow(to: attacker, amount: max(6, data.shadowGain / 2))
                }
                if !isCompanion {
                    switch arenaKitStates[attacker] {
                    case .inquisitor(var atkInq):
                        atkInq.gainLight(8); arenaKitStates[attacker] = .inquisitor(atkInq)
                    case .nonna(var atkNonna):
                        atkNonna.gainFlame(8); arenaKitStates[attacker] = .nonna(atkNonna)
                    case .midnight(var atkMid):
                        atkMid.gainShadow(8); arenaKitStates[attacker] = .midnight(atkMid)
                    case .emperor(var atkEmp):
                        atkEmp.gainShadow(8)
                        if atkEmp.isBeastForm && !data.isThrow {
                            let heal = DuelEmperorState.beastGuardLifestealHP
                            fighters[attacker].health = min(attackerMaxHP, fighters[attacker].health + heal)
                            atkEmp.lifestealTotalHP += heal
                            events.append(.emperorLifesteal(fighter: attacker, healed: heal))
                        }
                        arenaKitStates[attacker] = .emperor(atkEmp)
                        fighters[attacker].energy = atkEmp.shadowEnergy
                    case .legionKing(var atkLK):
                        atkLK.gainShadow(8); arenaKitStates[attacker] = .legionKing(atkLK)
                        fighters[attacker].energy = atkLK.shadowEnergy
                    case .monkeyKing(var atkMK):
                        atkMK.gainShadow(8); arenaKitStates[attacker] = .monkeyKing(atkMK)
                        fighters[attacker].energy = atkMK.shadowEnergy
                    case .none:
                        break
                    }
                }
                if shogunStates[defender] != nil { awardShogunShadow(to: defender, amount: 5) }
                else {
                    switch arenaKitStates[defender] {
                    case .inquisitor(var defInq):
                        defInq.gainLight(5); arenaKitStates[defender] = .inquisitor(defInq)
                    case .nonna(var defNonna):
                        defNonna.gainFlame(5); arenaKitStates[defender] = .nonna(defNonna)
                    case .midnight(var defMid):
                        defMid.gainShadow(5); arenaKitStates[defender] = .midnight(defMid)
                    case .emperor(var defEmp):
                        defEmp.gainShadow(5); arenaKitStates[defender] = .emperor(defEmp)
                        target.energy = defEmp.shadowEnergy
                    case .legionKing(var defLK):
                        defLK.gainShadow(5); arenaKitStates[defender] = .legionKing(defLK)
                        target.energy = defLK.shadowEnergy
                    case .monkeyKing(var defMK):
                        defMK.gainShadow(5); arenaKitStates[defender] = .monkeyKing(defMK)
                        target.energy = defMK.shadowEnergy
                    case .none:
                        break
                    }
                }
                // Velocity-based sliding block pushback!
                let blockVel = min(92, max(40, (data.push * 22) / 100))
                target.velocityX = direction * blockVel
                target.flash = 6; fighters[defender] = target
                return
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
                    atkInq.gainLight(6); arenaKitStates[attacker] = .inquisitor(atkInq)
                }
                if case .nonna(var atkNonna) = arenaKitStates[attacker], !isCompanion {
                    atkNonna.gainFlame(6); arenaKitStates[attacker] = .nonna(atkNonna)
                }
                if case .midnight(var atkMid) = arenaKitStates[attacker], !isCompanion {
                    atkMid.gainShadow(6); arenaKitStates[attacker] = .midnight(atkMid)
                }
                target.x = min(Self.rightWall, max(Self.leftWall, target.x + direction * data.push))
                target.flash = 8; fighters[defender] = target
                return
            }
        }

        // Unblocked hit resolution.
        var damage = scaledDamage(data.damage)
        var effectiveHitStop = data.hitStop
        var effectiveStun = data.stunTicks
        var cataclysmConsumed = false
        var headHitTriggered = false
        var criticalTriggered = false
        var counterHitTriggered = false
        var nonnaTrueShapeHit = false
        var midnightNocturneFired = false

        // Counter-Hit ("破招!"): interrupting opponent during attack startup!
        if ruleset == .shadowArena && !isCompanion && !data.isThrow, let defAttack = target.attack {
            let defData = moveData(defAttack.move, hero: target.hero, chargeTicks: defAttack.chargeTicks)
            let defArmored = defData.armorStart >= 0 && defAttack.age >= defData.armorStart && defAttack.age < defData.armorEnd
            if defAttack.age < defData.startup && !defArmored {
                damage = (damage * 120) / 100
                effectiveHitStop += 3
                effectiveStun += 6
                counterHitTriggered = true
            }
        }

        // Authentic Shadow Fight combo scaling (100% -> 92% -> 84% -> 76% -> 68%) in shadowArena mode.
        if ruleset == .shadowArena && !isCompanion && !data.isThrow {
            let comboScale = max(68, 100 - comboCount[attacker] * 8)
            damage = max(1, (damage * comboScale) / 100)
            comboCount[attacker] += 1
        }

        // Authentic Shadow Fight Head Hit (+25% bonus when the blade/kick physically intersects Head hurt capsule!).
        if ruleset == .shadowArena && !isCompanion && !data.isThrow && (hitZone == .high || data.hitZone == .high) {
            damage = (damage * 125) / 100
            effectiveHitStop += 2
            headHitTriggered = true
            target.lastHitZone = .high
        }

        // Emperor Beast (+12%), Legion King Dark Incarnation Empowered (+15%), Monkey King Heavenly Aura (+15%)!
        if ruleset == .shadowArena && !isCompanion && !data.isThrow {
            switch arenaKitStates[attacker] {
            case .emperor(let atkEmp) where atkEmp.isBeastForm && move != .emperorTransform:
                damage = (damage * 112) / 100
            case .legionKing(let atkLK) where atkLK.isShadowEmpowered:
                damage = (damage * 115) / 100
            case .monkeyKing(let atkMK) where atkMK.heavenlyAuraTicks > 0 && move != .monkeyHeavenlyPillar:
                damage = (damage * 115) / 100
            default:
                break
            }
        }

        let attackerCataclysm = !isCompanion && shogunStates[attacker]?.isCataclysm == true
        let defenderCataclysm = !isCompanion && shogunStates[defender]?.isCataclysm == true
        if attackerCataclysm {
            if move == .shogunFierceReprisal {
                damage = (damage * 22) / 10 + scaledDamage(90)
            } else {
                damage = (damage * 20) / 10
            }
            if ruleset == .shadowArena {
                damage = min(damage, (defenderMaxHP * 46) / 100)
            }
            shogunStates[attacker]?.consumeCataclysm(shogunLandedFirst: true)
            fighters[attacker].energy = 0
            cataclysmConsumed = true
            effectiveHitStop = max(effectiveHitStop, 14)
            events.append(.shogunCataclysmStrike(attacker: attacker, damage: damage))
        } else if defenderCataclysm {
            damage = (damage * 19) / 10
            if ruleset == .shadowArena {
                damage = min(damage, (defenderMaxHP * 44) / 100)
            }
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

        // Nonna Runes of Ash defender damage reduction (-3% per rune, max -18%)!
        if !cataclysmConsumed && ruleset == .shadowArena, case .nonna(let defNonna) = arenaKitStates[defender], defNonna.runesOfAsh > 0 {
            let pct = max(82, 100 - defNonna.runesOfAsh * 3)
            damage = max(1, (damage * pct) / 100)
        }

        // Nonna Runes of Ash (+4% dmg/rune), Ancient Fury (guaranteed crit), True Shape & <25% HP execute!
        var nonnaExecuted = false
        var nonnaAncientCrit = false
        if !isCompanion, case .nonna(var atkNonna) = arenaKitStates[attacker] {
            if ruleset == .shadowArena && atkNonna.runesOfAsh > 0 {
                damage = (damage * (100 + atkNonna.runesOfAsh * 4)) / 100
            }
            if ruleset == .shadowArena && atkNonna.isAncientFuryActive && !move.isKick {
                damage = (damage * 145) / 100
                nonnaAncientCrit = true
                effectiveHitStop = max(effectiveHitStop, 10)
            }
            if atkNonna.isInFlameForm {
                let bonus = scaledDamage((atkNonna.flameEntryPower * 55) / 100)
                damage += bonus
                effectiveHitStop = max(effectiveHitStop, 9)
                nonnaTrueShapeHit = true
                let executeThreshold = (defenderMaxHP * DuelNonnaState.executeThresholdHP) / 1000
                if target.health > 0 && target.health < executeThreshold {
                    damage = target.health
                    nonnaExecuted = true
                    effectiveHitStop = max(effectiveHitStop, 14)
                }
            } else if atkNonna.empoweredStrikeReady {
                atkNonna.empoweredStrikeReady = false
                damage += scaledDamage(35)
                arenaKitStates[attacker] = .nonna(atkNonna)
            }
        }

        // Midnight Cornered Beast (<35% HP -> +25%), Nocturne 4-stack (+40% guaranteed crit!), Shadow Form (+35%)!
        var midnightCrit = false
        if !isCompanion, case .midnight(var atkMid) = arenaKitStates[attacker] {
            if ruleset == .shadowArena &&
                fighters[attacker].health <= (attackerMaxHP * DuelMidnightState.corneredBeastThresholdPermille) / 1000 {
                damage = (damage * 125) / 100
            }
            if midnightNocturneArmed {
                atkMid.nocturneCharges = 0
                arenaKitStates[attacker] = .midnight(atkMid)
                damage = (damage * 140) / 100
                midnightCrit = true
                midnightNocturneFired = true
                effectiveHitStop = max(effectiveHitStop, 11)
            } else if atkMid.isInShadowForm && move != .midnightRemoval {
                damage = (damage * 135) / 100
                midnightCrit = true
                effectiveHitStop = max(effectiveHitStop, 8)
            }
        }

        // Authentic Shadow Fight deterministic Critical Hit roll in shadowArena mode (1.45x + knockdown!).
        if ruleset == .shadowArena && !isCompanion && !data.isThrow && !nonnaExecuted && !cataclysmConsumed {
            if data.isCritical || midnightCrit || nonnaAncientCrit {
                criticalTriggered = true
            } else if nextRandomPercent() < Self.critChancePercent(for: fighters[attacker].hero) {
                damage = (damage * 145) / 100
                criticalTriggered = true
                effectiveHitStop = max(effectiveHitStop, 10)
            }
        }

        // Check unbreakable hyper-armor (Shogun kick / Legion King Heavy / Nonna Great Axe / Inquisitor Deliverance).
        var armored = false
        if !cataclysmConsumed && !nonnaExecuted && !data.isThrow, let defAttack = target.attack {
            let defData = moveData(defAttack.move, hero: target.hero, chargeTicks: defAttack.chargeTicks)
            if defData.armorStart >= 0 && defAttack.age >= defData.armorStart && defAttack.age < defData.armorEnd {
                armored = true
                damage = max(1, (damage * 4) / 10)
                events.append(.shogunArmorAbsorbed(defender: defender))
                if case .nonna(var defNonna) = arenaKitStates[defender], !defNonna.wolfActive {
                    defNonna.gainFlame(16)
                    defNonna.summonWolf(from: target.x, facing: target.facing)
                    arenaKitStates[defender] = .nonna(defNonna)
                }
            }
        }

        let isMultiHitIntermediate = ruleset == .shadowArena && !isCompanion &&
            data.hitCount > 1 && (fighters[attacker].attack?.hitsLanded ?? 1) < data.hitCount
        var brokeInquisitorForm = false
        var legionRevived = false

        if ruleset == .shadowArena && !cataclysmConsumed && move == .shogunFierceReprisal {
            damage = max(1, (damage * 65) / 100)
        }

        // Overlord of Oppression (Shogun) OR Dark Incarnation (Legion King): single-trigger lethal cheat-death!
        if target.health - damage <= 0, var defShogun = shogunStates[defender],
           !defShogun.reviveUsed, defShogun.companionPhase != .unconscious {
            defShogun.reviveUsed = true
            defShogun.agonyRemainingTicks = DuelShogunState.agonyDurationTicks
            defShogun.companionPhase = .follow
            defShogun.companionTimer = 0
            defShogun.companionCooldown = 0
            shogunStates[defender] = defShogun
            target.health = (defenderMaxHP * DuelShogunState.reviveHealth) / 1000
            target.invulnerable = 30
            target.stun = 0
            target.knockdown = 0
            target.velocityX = 0
            target.frozenTicks = 0
            target.attack = nil
            target.guarding = false
            effectiveHitStop = min(effectiveHitStop, 4)
            events.append(.shogunRevived(fighter: defender))
        } else if target.health - damage <= 0,
                  case .legionKing(var defLK) = arenaKitStates[defender],
                  !defLK.hasRevivedThisRound {
            defLK.triggerDarkIncarnation()
            arenaKitStates[defender] = .legionKing(defLK)
            legionRevived = true
            target.health = min(defenderMaxHP, DuelLegionKingState.darkIncarnationReviveHP)
            target.energy = defLK.shadowEnergy
            target.invulnerable = DuelLegionKingState.darkIncarnationInvulnerableTicks
            target.stun = 0
            target.knockdown = 0
            target.velocityX = 0
            target.frozenTicks = 0
            target.attack = nil
            target.guarding = false
            fighters[attacker].velocityX = -direction * 105
            effectiveHitStop = max(effectiveHitStop, 10)
            events.append(.legionDarkIncarnation(fighter: defender))
        } else {
            target.health = max(0, target.health - damage)
            if !armored {
                target.frozenTicks = 0
                if ruleset == .shadowArena && target.health > 0 {
                    let wasAirborne = target.y > 0
                    let launches = data.launchVelocityY > 0
                    if wasAirborne && target.juggleHits < 2 {
                        // Mid-air Juggle continuation!
                        target.juggleHits += 1
                        target.stun = max(effectiveStun, 26)
                        if target.juggleHits >= 2 || (!isMultiHitIntermediate && (data.knockdown || criticalTriggered)) {
                            target.knockdown = 36
                            target.velocityY = max(target.velocityY, 55)
                        } else {
                            target.knockdown = 0
                            target.velocityY = max(target.velocityY, 105)
                        }
                    } else if launches && !data.knockdown && !nonnaExecuted {
                        // Launch cleanly into Juggle state (knockdown = 0 while airborne!)
                        target.stun = max(effectiveStun, 32)
                        target.knockdown = 0
                        target.velocityY = data.launchVelocityY
                        target.juggleHits = 0
                    } else {
                        target.stun = effectiveStun
                        target.knockdown = (!isMultiHitIntermediate && (data.knockdown || nonnaExecuted || criticalTriggered)) ? 54 : 0
                        if data.launchVelocityY > 0 && target.y == 0 {
                            target.velocityY = data.launchVelocityY
                        }
                    }
                } else {
                    target.stun = effectiveStun
                    target.knockdown = (data.knockdown || nonnaExecuted || criticalTriggered) ? 43 : 0
                }
                target.attack = nil
                target.guarding = false
                shogunStates[defender]?.heavyChargeTicks = 0
            }
        }

        landedHits[attacker] += 1; damageDealt[attacker] += damage
        events.append(.hit(attacker: attacker, damage: damage))
        if counterHitTriggered { events.append(.counterHit(attacker: attacker, damage: damage)) }
        if data.isThrow { events.append(.throwHit(attacker: attacker, damage: damage, backThrow: move == .throwBack)) }
        if headHitTriggered { events.append(.headHit(attacker: attacker, damage: damage)) }
        if criticalTriggered { events.append(.criticalHit(attacker: attacker, damage: damage)) }
        if data.isCritical || midnightCrit { events.append(.shogunCritical(attacker: attacker, damage: damage)) }
        if nonnaTrueShapeHit && !nonnaExecuted { events.append(.nonnaTrueShapeStrike(attacker: attacker, damage: damage)) }
        if nonnaExecuted { events.append(.nonnaTrueShapeExecute(attacker: attacker, damage: damage)) }
        if midnightNocturneFired { events.append(.midnightNocturneBurst(attacker: attacker, damage: damage)) }

        // Defender Inquisitor counterplay: taking an unblocked hit dispels Stigmata & knocks out of Form of Light (-50% Light)!
        if !armored, case .inquisitor(var defInq) = arenaKitStates[defender] {
            if defInq.hasStigmataOnOpponent { defInq.dispelStigmata() }
            if defInq.isInFormOfLight {
                defInq.knockOutOfFormOfLight()
                brokeInquisitorForm = true
                events.append(.inquisitorLightFormBroken(defender: defender))
            }
            arenaKitStates[defender] = .inquisitor(defInq)
        }

        var chainSnaggedPull = false
        if isCompanion {
            if shogunStates[attacker] != nil {
                events.append(.shogunCompanionHit(owner: attacker, damage: damage))
                target.energy = max(0, target.energy - DuelShogunState.companionEnergyDrain)
                if var defShogun = shogunStates[defender] {
                    defShogun.shadowEnergy = max(0, defShogun.shadowEnergy - DuelShogunState.companionEnergyDrain)
                    target.energy = defShogun.shadowEnergy
                    shogunStates[defender] = defShogun
                }
                if case .midnight(var defMid) = arenaKitStates[defender] {
                    defMid.shadowEnergy = max(0, defMid.shadowEnergy - DuelShogunState.companionEnergyDrain)
                    arenaKitStates[defender] = .midnight(defMid)
                } else if case .emperor(var defEmp) = arenaKitStates[defender] {
                    defEmp.shadowEnergy = max(0, defEmp.shadowEnergy - DuelShogunState.companionEnergyDrain)
                    target.energy = defEmp.shadowEnergy
                    arenaKitStates[defender] = .emperor(defEmp)
                } else if case .legionKing(var defLK) = arenaKitStates[defender] {
                    defLK.shadowEnergy = max(0, defLK.shadowEnergy - DuelShogunState.companionEnergyDrain)
                    target.energy = defLK.shadowEnergy
                    arenaKitStates[defender] = .legionKing(defLK)
                } else if case .monkeyKing(var defMK) = arenaKitStates[defender] {
                    defMK.shadowEnergy = max(0, defMK.shadowEnergy - DuelShogunState.companionEnergyDrain)
                    target.energy = defMK.shadowEnergy
                    arenaKitStates[defender] = .monkeyKing(defMK)
                }
                awardShogunShadow(to: attacker, amount: DuelShogunState.companionShadowGain)
            }
        } else if shogunStates[attacker] != nil {
            if data.isShadow {
                let heal = (damage * 30) / 100
                fighters[attacker].health = min(attackerMaxHP, fighters[attacker].health + heal)
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
            switch arenaKitStates[attacker] {
            case .emperor(var atkEmp):
                if move != .emperorTransform && move != .emperorBeastShadowJump {
                    atkEmp.gainShadow(move == .heavy ? 24 : move == .skill1 ? 14 : 18)
                }
                if atkEmp.isBeastForm && move != .emperorTransform && !data.isThrow {
                    let heal = DuelEmperorState.beastHitLifestealHP
                    fighters[attacker].health = min(attackerMaxHP, fighters[attacker].health + heal)
                    atkEmp.lifestealTotalHP += heal
                    events.append(.emperorLifesteal(fighter: attacker, healed: heal))
                }
                arenaKitStates[attacker] = .emperor(atkEmp)
                fighters[attacker].energy = atkEmp.shadowEnergy

            case .legionKing(var atkLK):
                if !data.isShadow {
                    atkLK.gainShadow(move == .heavy ? 22 : move == .legionShadowChain ? 16 : 14)
                }
                if move == .legionShadowChain && !legionRevived && target.health > 0 {
                    let minFrontX = fighters[attacker].x + direction * 780
                    let desiredPullX = target.x - direction * DuelLegionKingState.chainPullDistance
                    let pulledX: Int = direction > 0 ? max(minFrontX, desiredPullX) : min(minFrontX, desiredPullX)
                    target.x = min(Self.rightWall, max(Self.leftWall, pulledX))
                    target.knockdown = 0
                    target.stun = 34
                    target.velocityY = DuelLegionKingState.chainLiftVelocityY
                    target.velocityX = -direction * 45
                    target.juggleHits = 0
                    atkLK.chainSnagged = true
                    atkLK.chainActiveTicks = max(atkLK.chainActiveTicks, 18)
                    atkLK.chainTargetX = target.x
                    chainSnaggedPull = true
                    events.append(.legionChainSnag(attacker: attacker, damage: damage))
                }
                arenaKitStates[attacker] = .legionKing(atkLK)
                fighters[attacker].energy = atkLK.shadowEnergy

            case .monkeyKing(var atkMK):
                if move == .monkeyHeavenlyPillar {
                    atkMK.heavenlyAuraTicks = DuelMonkeyKingState.heavenlyAuraDurationTicks
                    events.append(.monkeyPillarSlam(attacker: attacker, damage: damage))
                } else {
                    atkMK.gainShadow(move == .monkeyAscensionPlunge ? 24 : move == .heavy ? 20 : 15)
                }
                arenaKitStates[attacker] = .monkeyKing(atkMK)
                fighters[attacker].energy = atkMK.shadowEnergy

            case .inquisitor(var atkInq):
                if move == .skill1 {
                    atkInq.applyStigmata()
                    atkInq.gainLight(18)
                    let burn = DuelInquisitorState.stigmataEnergyBurn
                    target.energy = max(0, target.energy - burn)
                    if var defShogun = shogunStates[defender] {
                        defShogun.shadowEnergy = max(0, defShogun.shadowEnergy - burn)
                        target.energy = defShogun.shadowEnergy
                        shogunStates[defender] = defShogun
                    }
                    if case .midnight(var defMid) = arenaKitStates[defender] {
                        defMid.shadowEnergy = max(0, defMid.shadowEnergy - burn)
                        arenaKitStates[defender] = .midnight(defMid)
                    } else if case .nonna(var defNonna) = arenaKitStates[defender] {
                        defNonna.flamePower = max(0, defNonna.flamePower - burn)
                        arenaKitStates[defender] = .nonna(defNonna)
                    }
                    fighters[attacker].health = min(attackerMaxHP, fighters[attacker].health + scaledDamage(DuelInquisitorState.salvationHeal))
                    events.append(.inquisitorStigmataApplied(defender: defender))
                    arenaKitStates[attacker] = .inquisitor(atkInq)
                } else {
                    let wasBranded = atkInq.hasStigmataOnOpponent
                    atkInq.gainLight(wasBranded ? 24 : 15)
                    if atkInq.isInFormOfLight {
                        fighters[attacker].health = min(attackerMaxHP, fighters[attacker].health + (damage * 25) / 100)
                        target.energy = max(0, target.energy - 15)
                        if var defShogun = shogunStates[defender] {
                            defShogun.shadowEnergy = max(0, defShogun.shadowEnergy - 15)
                            target.energy = defShogun.shadowEnergy
                            shogunStates[defender] = defShogun
                        }
                        if case .midnight(var defMid) = arenaKitStates[defender] {
                            defMid.shadowEnergy = max(0, defMid.shadowEnergy - 15)
                            arenaKitStates[defender] = .midnight(defMid)
                        } else if case .nonna(var defNonna) = arenaKitStates[defender] {
                            defNonna.flamePower = max(0, defNonna.flamePower - 15)
                            arenaKitStates[defender] = .nonna(defNonna)
                        }
                    }
                    if wasBranded {
                        atkInq.stigmataHits += 1
                    } else if move == .skill2 || move == .inquisitorLightSpin || move == .inquisitorLightDown ||
                                (ruleset == .shadowArena && atkInq.isInFormOfLight && move == .weaponDown) {
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
                        atkNonna.summonWolf(from: fighters[attacker].x, facing: fighters[attacker].facing)
                    }
                } else {
                    atkNonna.attackSeriesCount = 0
                }
                arenaKitStates[attacker] = .nonna(atkNonna)

            case .midnight(var atkMid):
                if move == .midnightRemoval {
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
                    // Executioner Herald: entering Shadow Form immediately resets Blink cooldown!
                    atkMid.shadowFormTicks = DuelMidnightState.shadowFormDurationTicks
                    atkMid.blinkCooldown = 0
                    arenaKitStates[attacker] = .midnight(atkMid)
                    events.append(.midnightRemovalStrike(attacker: attacker, damage: damage))
                    fighters[defender] = target
                    triggerInquisitorBanishingBlasphemy(against: attacker)
                    triggerNonnaAncientFury(against: attacker)
                    target = fighters[defender]
                } else {
                    if ruleset == .shadowArena && atkMid.isInShadowForm {
                        atkMid.gainShadow(25)
                        atkMid.blinkCooldown /= 2
                    } else if move == .skill1 {
                        atkMid.gainShadow(16)
                    } else {
                        atkMid.gainShadow(move == .heavy ? 20 : 14)
                    }
                    arenaKitStates[attacker] = .midnight(atkMid)
                }
            case .none:
                break
            }
        }

        // Authentic SF4 damage-taken energy charging for all 4 heroes.
        if !cataclysmConsumed && move != .midnightRemoval && target.health > 0 && !legionRevived {
            if shogunStates[defender] != nil {
                awardShogunShadow(to: defender, amount: 14)
            } else if ruleset == .shadowArena {
                switch arenaKitStates[defender] {
                case .emperor(var defEmp):
                    defEmp.gainShadow(12); arenaKitStates[defender] = .emperor(defEmp)
                    target.energy = defEmp.shadowEnergy
                case .legionKing(var defLK):
                    defLK.gainShadow(12); arenaKitStates[defender] = .legionKing(defLK)
                    target.energy = defLK.shadowEnergy
                case .monkeyKing(var defMK):
                    defMK.gainShadow(12); arenaKitStates[defender] = .monkeyKing(defMK)
                    target.energy = defMK.shadowEnergy
                case .inquisitor(var defInq):
                    if !brokeInquisitorForm {
                        defInq.gainLight(10); arenaKitStates[defender] = .inquisitor(defInq)
                    }
                case .nonna(var defNonna):
                    defNonna.gainFlame(10); arenaKitStates[defender] = .nonna(defNonna)
                case .midnight(var defMid):
                    defMid.gainShadow(10); arenaKitStates[defender] = .midnight(defMid)
                case .none:
                    break
                }
            }
        }

        // Knockback application: in `.shadowArena` use VELOCITY-BASED SLIDING KNOCKBACK (applied AFTER hitStop!),
        // never teleporting victim in mid-air before hitStop finishes!
        if chainSnaggedPull || legionRevived {
            // Pull or Dark Incarnation counter-knockback already applied cleanly!
        } else if move == .throwBack {
            let behindX = fighters[attacker].x - direction * 820
            target.x = min(Self.rightWall, max(Self.leftWall, behindX))
            target.velocityX = -direction * 95
            target.facing = direction
            fighters[attacker].facing = -direction
        } else if ruleset == .shadowArena && move == .weaponBack && fighters[attacker].hero == .liu && !armored {
            let behindX = fighters[attacker].x - direction * 760
            target.x = min(Self.rightWall, max(Self.leftWall, behindX))
            target.velocityX = -direction * 65
            target.facing = direction
            fighters[attacker].facing = -direction
        } else if move == .shogunDespotism {
            let pulledX = fighters[attacker].x + direction * 760
            if ruleset == .shadowArena {
                target.x = min(Self.rightWall, max(Self.leftWall, pulledX))
                target.velocityX = direction * 95
            } else {
                target.x = min(Self.rightWall, max(Self.leftWall, pulledX + direction * data.push))
            }
        } else if ruleset == .shadowArena {
            let effectivePush = armored ? data.push / 4 : (criticalTriggered || counterHitTriggered ? (data.push * 125) / 100 : data.push)
            // Compute crisp initial slide velocity (with friction=24/tick, v=135 slides ~420mm smoothly over 6 frames!)
            // Intermediate hits of a multi-hit string keep tight hit-glue so follow-up hits land cleanly.
            let rawSlide = min(210, max(36, (effectivePush * 34) / 100))
            let slideVel = isMultiHitIntermediate ? min(44, max(24, rawSlide / 2)) : rawSlide
            target.velocityX = direction * slideVel
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
        for i in resetFighters.indices {
            resetFighters[i].health = Self.maximumHealth(for: resetFighters[i].hero, ruleset: ruleset)
            if resetFighters[i].hero == .wuYong || ruleset == .shadowArena {
                resetFighters[i].energy = 0
            }
        }
        fighters = resetFighters
        shogunStates = resetFighters.map {
            $0.hero == .wuYong ? DuelShogunState(ownerX: $0.x, ownerFacing: $0.facing) : nil
        }
        arenaKitStates = resetFighters.map { fighter in
            switch fighter.hero {
            case .gale:
                return ruleset == .shadowArena ? .legionKing(DuelLegionKingState()) : .inquisitor(DuelInquisitorState())
            case .liu:
                return ruleset == .shadowArena ? .emperor(DuelEmperorState()) : .nonna(DuelNonnaState())
            case .ember:
                return ruleset == .shadowArena ? .monkeyKing(DuelMonkeyKingState()) : .midnight(DuelMidnightState())
            case .wuYong:
                return nil
            }
        }
        guardRecoveryTicks = [0, 0]; comboCount = [0, 0]
        remainingTicks = ruleset == .shadowArena ? (Self.shadowArenaRoundSeconds * Self.ticksPerSecond) : 3600
        hitStop = 0; buffered = [[], []]; bufferedCommands = [nil, nil]
        botHeld = .neutral; grapple = nil; phase = .fighting
    }
    private mutating func botInput() -> Input {
        let interval = ruleset == .shadowArena
            ? (difficulty == .learning ? 30 : 15)
            : (difficulty == .learning ? 24 : 10)
        var input = botHeld; input.taps = []; input.weaponCommand = nil
        guard frame % interval == 0 else { return input }
        random = random &* 6364136223846793005 &+ 1442695040888963407
        let choice = Int((random >> 32) % 100), me = fighters[1], foe = fighters[0]
        let distance = abs(me.x - foe.x), toward = foe.x > me.x ? 1 : -1
        input = .neutral
        let preferred = ruleset == .shadowArena
            ? (me.hero == .gale ? 1560 : me.hero == .wuYong ? 1380 : me.hero == .liu ? 1140 : 1280)
            : (me.hero == .gale ? 1700 : me.hero == .wuYong ? 1200 : 900)
        if ruleset == .shadowArena {
            if distance > preferred { input.move = toward }
            else if me.hero == .gale && distance < 1080 { input.move = -toward }
            else if distance < 960 && foe.attack == nil && choice < 26 { input.move = -toward }
            let rangedReady: Bool = {
                switch arenaKitStates[1] {
                case .emperor(let emp): return !emp.isBeastForm ? emp.canCastRanged : (emp.rangedCooldown == 0 && distance < 1800)
                case .legionKing(let lk): return lk.canCastChain
                case .monkeyKing(let mk): return mk.canEnterAscension && distance > 1100 && distance < 2600
                case .inquisitor(let inq): return inq.canCastSalvation
                case .nonna(let nonna): return nonna.canLaunchOwl
                case .midnight(let mid): return mid.canCastKunai
                case .none: return false
                }
            }()
            // Monkey King perched atop Ascension Pillar: dive forward or slam Heavenly Pillar!
            if case .monkeyKing(let mk) = arenaKitStates[1], mk.isPerchedOnPillar {
                if mk.canCastHeavenlyPillar && distance < 2100 && choice < 60 {
                    input.weaponCommand = .shadow
                } else if distance < 2400 && choice < 72 {
                    input.weaponCommand = .weaponForward
                } else if choice >= 85 {
                    input.move = -toward
                }
                botHeld = Input(move: input.move)
                return input
            }
            // In Shadow Arena, standing neutral or backing up automatically blocks!
            if foe.attack != nil && distance < 1500 && difficulty == .challenging && choice < 36,
               case .midnight(let mid) = arenaKitStates[1], mid.canUseBlink {
                input.move = -toward
                input.weaponCommand = .shadow
            } else if foe.attack != nil && distance < 1700 && choice < (difficulty == .learning ? 26 : 58) {
                input.move = distance < 1100 ? -toward : 0
            } else if distance <= Self.throwMaxDistance && foe.guarding && foe.knockdown == 0 && foe.invulnerable == 0 &&
                      choice < (difficulty == .learning ? 10 : 52) {
                input.move = toward
                input.weaponCommand = choice % 2 == 0 ? .weaponForward : .weaponBack
            } else if let shogun = shogunStates[1] {
                if shogun.canUseShadowAbility && distance < 2200 && foe.y == 0 && choice < 55 {
                    input.move = distance > 1500 ? -toward : toward
                    input.weaponCommand = .shadow
                } else if shogun.isCompanionAvailable && abs(foe.x - shogun.companionX) < 1050 && choice < 50 {
                    input.weaponCommand = .ranged
                } else if foe.attack != nil && distance < 1250 && shogun.canUseRuthlessKick && choice < 45 {
                    input.weaponCommand = .kickForward
                } else if distance < 1500 {
                    let moves: [DuelWeaponCommand] = distance <= Self.throwMaxDistance && difficulty == .learning
                        ? [.weapon, .weaponUp, .weaponDown, .kick, .heavy]
                        : [.weapon, .weaponForward, .weaponUp, .weaponDown, .kick, .heavy]
                    input.weaponCommand = moves[choice % moves.count]
                } else if choice > 92 {
                    input.taps = .jump
                }
            } else if case .emperor(let emp) = arenaKitStates[1], emp.canTransformToBeast && distance < 2400 && choice < 65 {
                input.weaponCommand = .shadow
            } else if case .emperor(let emp) = arenaKitStates[1], emp.canCastBeastShadow && distance < 2100 && choice < 55 {
                input.weaponCommand = .shadow
            } else if case .legionKing(let lk) = arenaKitStates[1], lk.canCastShadowAbility && distance < 2100 && choice < 55 {
                input.vertical = (foe.knockdown > 0 || distance < 1150) ? -1 : 0
                input.weaponCommand = .shadow
            } else if case .legionKing(let lk) = arenaKitStates[1], lk.canCastChain && distance >= 1400 && distance <= 4150 && choice < 50 {
                input.weaponCommand = .ranged
            } else if case .monkeyKing(let mk) = arenaKitStates[1], mk.canCastHeavenlyPillar && distance < 1900 && choice < 55 {
                input.weaponCommand = .shadow
            } else if case .monkeyKing(let mk) = arenaKitStates[1], mk.canEnterAscension && distance >= 1200 && distance <= 2500 && choice < 40 {
                input.weaponCommand = .ranged
            } else if case .inquisitor(let inq) = arenaKitStates[1], inq.canEnterFormOfLight && foe.y == 0 && choice < 55 {
                input.weaponCommand = .shadow
            } else if case .inquisitor(let inq) = arenaKitStates[1], inq.isInFormOfLight && distance < 1750 && choice < 62 {
                let lightMoves: [DuelWeaponCommand] = [.weaponForward, .weaponUp, .weaponDown, .shadow]
                input.weaponCommand = lightMoves[choice % lightMoves.count]
            } else if case .inquisitor(let inq) = arenaKitStates[1], inq.canCastDeliverance && distance < 1550 && choice < 38 {
                input.weaponCommand = .shadow
            } else if case .nonna(let nonna) = arenaKitStates[1], nonna.owlPhase == .latched && choice < 65 {
                input.weaponCommand = .ranged
            } else if case .nonna(let nonna) = arenaKitStates[1], nonna.canEnterFlameForm && distance < 1600 && choice < 45 {
                input.weaponCommand = .shadow
            } else if case .midnight(let mid) = arenaKitStates[1], mid.canUseRemoval && distance < 2500 && foe.y == 0 && choice < 50 {
                input.move = toward
                input.weaponCommand = .shadow
            } else if difficulty == .challenging && distance > preferred + 650 && choice < 24 {
                input.dashDirection = toward
            } else if difficulty == .challenging && foe.attack != nil && distance < 1150 && choice >= 72 && choice < 86 {
                input.dashDirection = -toward
            } else if distance < 1300 {
                let moves: [DuelWeaponCommand] = distance <= Self.throwMaxDistance && difficulty == .learning
                    ? [.weapon, .weaponUp, .weaponDown, .kick, .kickDown, .heavy]
                    : [.weapon, .weaponForward, .weaponUp, .weaponDown, .weaponBack, .kick, .kickDown, .heavy]
                input.weaponCommand = moves[choice % moves.count]
            } else if distance < 4200 && rangedReady && choice < 48 {
                input.weaponCommand = .ranged
            } else if choice > 90 {
                input.taps = .jump
            }
            botHeld = Input(move: input.move)
            return input
        }
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
        try writer.u8(ruleset.rawValue)
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
        try writer.array(guardRecoveryTicks, limit: 2) { try $0.int($1) }
        try writer.array(comboCount, limit: 2) { try $0.int($1) }
        try writer.u64(random); try writer.int(nextProjectile); try writer.input(botHeld)
        try writer.array(buffered, limit: 2) { try $0.int($1.rawValue) }
        try writer.array(bufferedCommands, limit: 2) { writer, cmd in
            try writer.optional(cmd) { try $0.command($1) }
        }
        try writer.hero(opponentHero); try writer.bool(weaponModeRequested)
    }
}
