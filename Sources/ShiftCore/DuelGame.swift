import Foundation

/// Offline fighting laboratory. All gameplay uses integer units and 60 Hz ticks;
/// rendering time, SceneKit physics and animation callbacks never decide a hit.
public struct DuelGame: Equatable, Sendable {
    public enum Hero: String, CaseIterable, Codable, Sendable {
        case ember, gale, liu
        public var name: String {
            switch self { case .ember: return "孙登"; case .gale: return "青岚"; case .liu: return "刘泉纬" }
        }
        public var style: String {
            switch self {
            case .ember: return "近身压制 · 连击与突进"
            case .gale: return "距离控制 · 飞刃与反击"
            case .liu: return "近身擒拿 · 锁臂与震地"
            }
        }
        public var skill1Name: String {
            switch self { case .ember: return "裂步突进"; case .gale: return "远程飞刃"; case .liu: return "进身冲击" }
        }
        public var skill2Name: String {
            switch self { case .ember: return "升龙重击"; case .gale: return "撤步反击"; case .liu: return "击倒重击" }
        }
        public var skillHelp: String {
            switch self {
            case .ember: return "裂步突进：消耗 30 能量，向前突进攻击。升龙重击：消耗 45 能量，命中后击倒对手。"
            case .gale: return "远程飞刃：消耗 30 能量，发射飞刃。撤步反击：消耗 45 能量，后撤出手，命中后击倒对手。"
            case .liu: return "进身冲击：消耗 30 能量，突进接近对手。击倒重击：消耗 45 能量，命中后击倒对手。满能量时可施放擒拿震地。"
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
        public init(move: Int = 0, guardHeld: Bool = false, taps: Buttons = []) {
            self.move = min(1, max(-1, move)); self.guardHeld = guardHeld; self.taps = taps
        }
        public static let neutral = Input()
    }
    public enum Move: String, Codable, Sendable { case jab, cross, finisher, heavy, skill1, skill2, ultimate }
    public struct Attack: Equatable, Sendable {
        public let move: Move
        public var age = 0
        public var connected = false
        public var spawned = false
        public var comboQueued = false
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
        public var duration: Int { startup + active + recovery }
    }
    public struct Box: Equatable, Sendable {
        public let minX: Int, maxX: Int, minY: Int, maxY: Int
        public func overlaps(_ other: Box) -> Bool {
            minX <= other.maxX && maxX >= other.minX && minY < other.maxY && maxY > other.minY
        }
    }
    public func hurtBox(_ index: Int) -> Box {
        let f = fighters[index]
        return Box(minX: f.x - 310, maxX: f.x + 310, minY: f.y + 275, maxY: f.y + 1525)
    }
    public func attackBox(_ index: Int) -> Box? {
        let f = fighters[index]
        guard grapple == nil, let attack = f.attack, !(f.hero == .gale && attack.move == .skill1) else { return nil }
        let data = Self.data(attack.move, hero: f.hero)
        guard attack.age >= data.startup && attack.age < data.startup + data.active else { return nil }
        return rangeBox(index, reach: data.reach)
    }
    private func rangeBox(_ index: Int, reach: Int) -> Box {
        let f = fighters[index], near = f.x + f.facing * 200, far = f.x + f.facing * (reach - 310)
        return Box(minX: min(near, far), maxX: max(near, far), minY: f.y + 275, maxY: f.y + 1525)
    }
    public static let ticksPerSecond = 60
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
    private var random: UInt64
    private var nextProjectile = 0
    private var botHeld = Input.neutral
    private var buffered: [Buttons] = [[], []]
    private let opponentHero: Hero

    public init(hero: Hero = .ember, difficulty: Difficulty = .learning, mode: Mode = .versus, seed: UInt64 = 20261107,
                opponentHero: Hero? = nil) {
        selectedHero = hero; self.difficulty = difficulty; self.mode = mode; random = seed
        self.opponentHero = opponentHero ?? (hero == .gale ? .ember : .gale)
        fighters = [Fighter(hero: hero, x: 3500, facing: 1),
                    Fighter(hero: self.opponentHero, x: 6500, facing: -1)]
    }
    public var round: Int { wins.reduce(0, +) + 1 }
    /// Pause/interruption cancels future commands, without undoing a move that
    /// already started. Hit-stop buffers and queued combo links are input too.
    public mutating func cancelBufferedInputs() {
        buffered = [[], []]
        for i in fighters.indices { fighters[i].attack?.comboQueued = false }
        botHeld = .neutral
    }
    public static func data(_ move: Move, hero: Hero) -> MoveData {
        let long = hero == .gale ? 240 : 0
        switch move {
        case .jab: return .init(startup: 6, active: 3, recovery: 13, reach: 1030 + long, damage: 75, push: 110, knockdown: false)
        case .cross: return .init(startup: 7, active: 3, recovery: 15, reach: 1170 + long, damage: 90, push: 130, knockdown: false)
        case .finisher: return .init(startup: 10, active: 4, recovery: 23, reach: 1280 + long, damage: 125, push: 380, knockdown: true)
        case .heavy: return .init(startup: 19, active: 5, recovery: 29, reach: 1450 + long, damage: 165, push: 450, knockdown: true)
        case .skill1: return .init(startup: hero == .gale ? 18 : 11, active: 5, recovery: 26, reach: 1200, damage: 135, push: 260, knockdown: false)
        case .skill2: return .init(startup: 8, active: 5, recovery: 32, reach: 1550, damage: 155, push: 430, knockdown: true)
        case .ultimate: return .init(startup: 24, active: 5, recovery: 45, reach: 1050, damage: 0, push: 0, knockdown: false)
        }
    }

    /// A replay needs only the original configuration, seed and this input stream.
    /// Passing opponent input is useful for deterministic local tests and future replay tools.
    public mutating func step(_ player: Input, opponent: Input? = nil) {
        if case .matchOver = phase { return }
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
        // Collect both contacts before applying either: simultaneous active attacks can trade.
        var contacts: [(attacker: Int, data: MoveData, direction: Int)] = []
        var grabs: [Int] = []
        for i in 0..<2 {
            guard var attack = fighters[i].attack else { continue }
            let data = Self.data(attack.move, hero: fighters[i].hero)
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
                contacts.append((i, data, fighters[i].facing)); attack.connected = true
            }
            fighters[i].attack = attack
        }
        for index in projectiles.indices.reversed() {
            projectiles[index].x += projectiles[index].direction * 135
            projectiles[index].lifetime -= 1
            let p = projectiles[index], target = fighters[1 - p.owner]
            if abs(p.x - target.x) < 440 && target.y < 1100 && target.knockdown == 0 && target.invulnerable == 0 {
                contacts.append((p.owner, Self.data(.skill1, hero: .gale), p.direction))
                projectiles.remove(at: index)
            } else if p.lifetime <= 0 || p.x < 0 || p.x > 10000 { projectiles.remove(at: index) }
        }
        for contact in contacts { applyHit(from: contact.attacker, data: contact.data, direction: contact.direction) }
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
                let data = Self.data(attack.move, hero: fighters[i].hero)
                if attack.age >= data.duration {
                    if !attack.connected && !attack.spawned { events.append(.whiff(attacker: i)) }
                    if attack.comboQueued && attack.connected && attack.move != .finisher {
                        fighters[i].attack = Attack(move: attack.move == .jab ? .cross : .finisher)
                    } else { fighters[i].attack = nil }
                } else { fighters[i].attack = attack }
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
            for i in 0..<2 { fighters[i].attack = nil; fighters[i].guarding = false }
            if let winner, wins[winner] == 2 { phase = .matchOver(winner: winner) }
            else { phase = .roundBreak(winner: winner, remaining: 120) }
        }
    }

    private mutating func updateFighter(_ i: Int, input: Input, taps: Buttons) {
        var f = fighters[i]
        f.flash = max(0, f.flash - 1); f.invulnerable = max(0, f.invulnerable - 1)
        f.stun = max(0, f.stun - 1); f.walking = false
        if f.knockdown > 0 {
            f.knockdown -= 1; f.guarding = false
            if f.knockdown == 0 { f.invulnerable = 20 }
        }
        if f.y > 0 || f.velocityY > 0 {
            f.y = max(0, f.y + f.velocityY); f.velocityY -= 18
            if f.y == 0 { f.velocityY = 0 }
        }
        if f.attack == nil { f.facing = fighters[1 - i].x >= f.x ? 1 : -1 }
        f.guarding = input.guardHeld && f.y == 0 && f.attack == nil && (f.stun == 0 || f.guarding) && f.knockdown == 0
        if !f.guarding { f.guardMeter = min(1000, f.guardMeter + 3) }
        if frame % 12 == 0 { f.energy = min(100, f.energy + 1) }
        if f.stun == 0 && f.knockdown == 0 {
            if taps.contains(.jump) && f.y == 0 && f.attack == nil {
                f.velocityY = 235; f.guarding = false; events.append(.jumped(player: i))
            }
            if !f.guarding {
                let speed = (f.hero == .gale ? 78 : 68) * (f.attack == nil ? 10 : 4) / 10
                if f.attack?.move != .ultimate {
                    f.x += min(1, max(-1, input.move)) * speed; f.walking = input.move != 0
                }
                if var attack = f.attack {
                    let data = Self.data(attack.move, hero: f.hero)
                    if taps.contains(.light) && attack.age >= data.startup && attack.age < data.duration &&
                        (attack.move == .jab || attack.move == .cross) { attack.comboQueued = true }
                    f.attack = attack
                } else {
                    let move: Move?
                    if taps.contains(.ultimate) && f.hero == .liu && f.energy == 100 && f.y == 0 && f.velocityY == 0 {
                        move = .ultimate; f.energy = 0; f.walking = false
                    }
                    else if taps.contains(.skill2) && f.energy >= 45 { move = .skill2; f.energy -= 45 }
                    else if taps.contains(.skill1) && f.energy >= 30 { move = .skill1; f.energy -= 30 }
                    else if taps.contains(.heavy) { move = .heavy }
                    else if taps.contains(.light) { move = .jab }
                    else { move = nil }
                    if let move { f.attack = Attack(move: move) }
                }
                if let attack = f.attack, attack.move == .skill1, f.hero != .gale, attack.age < 11 { f.x += f.facing * 115 }
                if let attack = f.attack, attack.move == .skill2, f.hero == .gale, attack.age < 7 { f.x -= f.facing * 85 }
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
            fighters[i].walking = false; fighters[i].flash = 0
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
    private mutating func applyHit(from attacker: Int, data: MoveData, direction: Int) {
        let defender = 1 - attacker
        var target = fighters[defender]
        let front = target.facing == -direction
        if target.guarding && front {
            target.guardMeter = max(0, target.guardMeter - data.damage * 2)
            target.stun = target.guardMeter == 0 ? 42 : 10
            target.guarding = target.guardMeter > 0
            events.append(target.guardMeter == 0 ? .guardBreak(defender: defender) : .blocked(defender: defender))
            hitStop = max(hitStop, 3)
        } else {
            target.health = max(0, target.health - data.damage)
            target.stun = 17; target.knockdown = data.knockdown ? 43 : 0
            target.attack = nil; target.guarding = false
            landedHits[attacker] += 1; damageDealt[attacker] += data.damage
            events.append(.hit(attacker: attacker, damage: data.damage)); hitStop = max(hitStop, 5)
        }
        target.x = min(Self.rightWall, max(Self.leftWall, target.x + direction * data.push))
        target.flash = 8; fighters[defender] = target
    }
    private mutating func resetRound() {
        fighters = [Fighter(hero: selectedHero, x: 3500, facing: 1),
                    Fighter(hero: opponentHero, x: 6500, facing: -1)]
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
        let preferred = me.hero == .gale ? 1700 : 900
        if distance > preferred { input.move = toward }
        else if me.hero == .gale && distance < 900 { input.move = -toward }
        if foe.attack?.move == .ultimate && distance < 1600 && difficulty == .challenging && choice < 65 {
            input.move = -toward; input.taps = .jump
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
