import Foundation

// 裂隙对决 · 原创战斗模拟（60 帧，确定性）

public enum RiftFighterState: String, Codable, Sendable {
    case idle, walking, dashing, airborne, attacking, guarding, blockstun, hitstun
    case launched, knockdown, getup, guardBreak, parried, stunned, ko, victory
}

public enum RiftAttackPhase: String, Codable, Sendable { case startup, active, recovery }

public enum RiftHitKind: String, Codable, Sendable {
    case hit, counterHit, block, parry, armor, echo, guardBreak
}

public struct RiftHitEvent: Equatable, Codable, Sendable {
    public var attacker: Int
    public var x: Double
    public var y: Double
    public var damage: Int
    public var tier: RiftImpactTier
    public var style: RiftMoveStyle
    public var kind: RiftHitKind
    public var heroID: RiftHeroID
}

public enum RiftEvent: Equatable, Sendable {
    case hit(RiftHitEvent)
    case swing(side: Int, slot: RiftMoveSlot, style: RiftMoveStyle)
    case projectileSpawned(side: Int, style: RiftMoveStyle)
    case projectileClash(x: Double, y: Double)
    case burst(side: Int)
    case transformStart(side: Int)
    case transformEnd(side: Int)
    case ultimate(side: Int)
    case jump(side: Int)
    case dash(side: Int)
    case land(side: Int, heavy: Bool)
    case knockdown(side: Int)
    case ko(side: Int)
    case roundStart(round: Int)
    case fight
    case roundEnd(winner: Int?)
    case matchEnd(winner: Int?)
}

public struct RiftFighter: Equatable, Sendable {
    public let heroID: RiftHeroID
    public var x: Double
    public var y: Double = 0
    public var vx: Double = 0
    public var vy: Double = 0
    public var facing: Double
    public var health: Int
    public var rage: Double = 0
    public var guardMeter: Double = 100
    public var state: RiftFighterState = .idle
    public var stateFrame = 0
    public var stateLength = 0
    public var slot: RiftMoveSlot?
    public var move: RiftMoveSpec?
    public var hitsDone = 0
    public var connected = false
    public var projectileFired = false
    public var airAttackUsed = false
    public var cooldowns: [RiftMoveSlot: Int] = [:]
    public var transformRemaining = 0
    public var ultimateUsed = false
    public var comboHits = 0
    public var comboDamage = 0
    public var juggleCount = 0
    public var knockdownPending = false
    public var invulnerable = 0
    public var guardPressedAt = -1000
    public var guardWasHeld = false
    public var counterReady = 0
    public var hitFlash = 0
    public var wins = 0
    /// 输入缓冲：最近按下的攻击键和剩余有效帧
    public var buffered: RiftMoveSlot?
    public var bufferedLight = false
    public var bufferTimer = 0
    public var jumpBuffered = 0
    public var dashBuffered = 0
    public var lastDamageTaken = 0
    /// 本招已经用霸体吃下的次数（霸体只吃一下）
    public var armorAbsorbed = 0

    public var spec: RiftHeroSpec { RiftRoster.spec(heroID) }
    public var isTransformed: Bool { transformRemaining > 0 }
    public var maxHealth: Int { spec.maxHealth }
    public var grounded: Bool { y <= 0.0001 }

    public var phase: RiftAttackPhase? {
        guard state == .attacking, let move else { return nil }
        if stateFrame < move.startup { return .startup }
        if stateFrame < move.startup + move.active { return .active }
        return .recovery
    }

    /// 动作进度 0...1（用于表现层插值）
    public var progress: Double {
        stateLength > 0 ? min(1, Double(stateFrame) / Double(stateLength)) : 0
    }

    public func cooldown(_ slot: RiftMoveSlot) -> Int { cooldowns[slot] ?? 0 }

    public func cooldownFraction(_ slot: RiftMoveSlot) -> Double {
        guard let total = spec.move(slot)?.cooldown, total > 0 else { return 0 }
        return Double(cooldown(slot)) / Double(total)
    }

    public var canTransform: Bool { rage >= 100 && !isTransformed }
    public var canUltimate: Bool { isTransformed && !ultimateUsed }
}

public struct RiftProjectile: Equatable, Sendable {
    public var owner: Int
    public var x: Double
    public var y: Double
    public var vx: Double
    public var spec: RiftProjectileSpec
    public var move: RiftMoveSpec
    public var age = 0
    public var hitsLeft: Int
    public var hitCooldown = 0
    public var id: Int
}

public enum RiftMatchPhase: String, Codable, Sendable { case intro, fighting, roundOver, matchOver }

public struct RiftFight: Sendable {
    public static let ticksPerSecond = 60
    public static let roundSeconds = 99
    public static let stageHalfWidth = 7.0
    public static let gravity = 0.011
    public static let bodyHalfWidth = 0.35
    public static let bodyHeight = 1.8
    /// 单套连招最多打掉最大血量的比例：保证不会被秒杀
    public static let comboDamageCap = 0.35
    public static let roundsToWin = 2

    public private(set) var fighters: [RiftFighter]
    public private(set) var projectiles: [RiftProjectile] = []
    public private(set) var events: [RiftEvent] = []
    public private(set) var frame = 0
    public private(set) var freeze = 0
    public private(set) var phase: RiftMatchPhase = .intro
    public private(set) var phaseFrame = 0
    public private(set) var round = 1
    public private(set) var roundTicksLeft = RiftFight.roundSeconds * RiftFight.ticksPerSecond
    public private(set) var matchWinner: Int?
    public private(set) var roundWinner: Int?
    /// 最近一次命中的震屏强度（表现层读取后自行衰减）
    public private(set) var lastShake = 0.0
    public var trainingMode = false
    private var nextProjectileID = 1

    public init(left: RiftHeroID, right: RiftHeroID, training: Bool = false) {
        fighters = [
            RiftFighter(heroID: left, x: -2.2, facing: 1, health: RiftRoster.spec(left).maxHealth),
            RiftFighter(heroID: right, x: 2.2, facing: -1, health: RiftRoster.spec(right).maxHealth),
        ]
        trainingMode = training
        events = [.roundStart(round: 1)]
    }

    public var secondsLeft: Int { (roundTicksLeft + Self.ticksPerSecond - 1) / Self.ticksPerSecond }

    // MARK: - 主循环

    public mutating func step(_ inputs: [RiftInput]) {
        events.removeAll(keepingCapacity: true)
        lastShake = 0
        frame += 1
        phaseFrame += 1
        let input0 = inputs.indices.contains(0) ? inputs[0] : .none
        let input1 = inputs.indices.contains(1) ? inputs[1] : .none
        let pair = [input0, input1]

        switch phase {
        case .intro:
            if phaseFrame >= 80 { phase = .fighting; phaseFrame = 0; events.append(.fight) }
            for i in 0..<2 { idleStep(i) }
            return
        case .roundOver:
            for i in 0..<2 { idleStep(i) }
            physics()
            if phaseFrame >= 150 { advanceRound() }
            return
        case .matchOver:
            for i in 0..<2 { idleStep(i) }
            physics()
            return
        case .fighting:
            break
        }

        for i in 0..<2 { bufferInput(i, pair[i]) }
        if freeze > 0 { freeze -= 1; return }

        for i in 0..<2 { update(i, pair[i]) }
        physics()
        for i in 0..<2 { updateFacing(i) }
        resolveMelee()
        updateProjectiles()
        tickTimers()
        checkRoundEnd()
    }

    private mutating func idleStep(_ i: Int) {
        var f = fighters[i]
        f.stateFrame += 1
        if f.hitFlash > 0 { f.hitFlash -= 1 }
        if f.state == .attacking || f.state == .hitstun || f.state == .blockstun || f.state == .walking || f.state == .dashing {
            if f.grounded { f.state = .idle; f.slot = nil; f.move = nil }
        }
        f.vx *= 0.85
        fighters[i] = f
    }

    // MARK: - 输入

    private mutating func bufferInput(_ i: Int, _ input: RiftInput) {
        var f = fighters[i]
        if input.guardHeld && !f.guardWasHeld { f.guardPressedAt = frame }
        f.guardWasHeld = input.guardHeld
        var pressed: RiftMoveSlot?
        if input.transform { pressed = f.isTransformed ? .ultimate : .transform }
        else if input.skill2 { pressed = .skill2 }
        else if input.skill1 { pressed = .skill1 }
        else if input.heavy { pressed = .heavy }
        else if input.light { pressed = .light1 }
        if let pressed { f.buffered = pressed; f.bufferTimer = 9 }
        if input.jump { f.jumpBuffered = 6 }
        if input.dash { f.dashBuffered = 6 }
        fighters[i] = f
    }

    // MARK: - 状态更新

    private mutating func update(_ i: Int, _ input: RiftInput) {
        var f = fighters[i]
        let spec = f.spec
        f.stateFrame += 1
        if f.hitFlash > 0 { f.hitFlash -= 1 }
        if f.invulnerable > 0 { f.invulnerable -= 1 }
        if f.counterReady > 0 { f.counterReady -= 1 }
        if f.bufferTimer > 0 { f.bufferTimer -= 1 } else { f.buffered = nil }
        if f.jumpBuffered > 0 { f.jumpBuffered -= 1 }
        if f.dashBuffered > 0 { f.dashBuffered -= 1 }
        for (k, v) in f.cooldowns where v > 0 { f.cooldowns[k] = v - 1 }
        if f.state != .guarding && f.state != .blockstun { f.guardMeter = min(100, f.guardMeter + 0.25) }
        if f.transformRemaining > 0 && !(f.state == .attacking && (f.slot == .transform || f.slot == .ultimate)) {
            f.transformRemaining -= 1
            if f.transformRemaining == 0 { events.append(.transformEnd(side: i)) }
        }
        if trainingMode { f.rage = max(f.rage, 0); if i == 1 { f.health = max(f.health, 1) } }

        let speedScale = f.isTransformed ? spec.transform.speedScale : 1

        switch f.state {
        case .attacking:
            guard let move = f.move else { f.state = .idle; break }
            // 出招位移
            if f.stateFrame < move.startup + move.active, move.lunge != 0 {
                f.vx = move.lunge * f.facing * speedScale
            } else if f.grounded {
                f.vx *= 0.7
            }
            // 飞行道具
            if let p = move.projectile, !f.projectileFired, f.stateFrame >= move.startup {
                f.projectileFired = true
                spawnProjectile(owner: i, fighter: f, spec: p, move: move)
            }
            // 吴庸铁壁持续期间维持无敌判定交由命中逻辑处理
            if f.stateFrame >= f.stateLength {
                if f.slot == .transform {
                    f.transformRemaining = spec.transform.duration
                }
                if f.slot == .ultimate {
                    f.transformRemaining = 0
                    events.append(.transformEnd(side: i))
                }
                endAction(&f)
            } else if tryCancel(&f, side: i) {
                break
            }
        case .hitstun, .blockstun, .stunned, .parried, .guardBreak:
            f.vx *= 0.86
            if f.stateFrame >= f.stateLength {
                if f.state == .hitstun || f.state == .stunned || f.state == .guardBreak { resetCombo(&f) }
                endAction(&f)
            }
        case .launched:
            break // 落地在 physics 中处理
        case .knockdown:
            f.vx *= 0.8
            if f.stateFrame >= f.stateLength {
                f.state = .getup; f.stateFrame = 0; f.stateLength = 26; f.invulnerable = 30
                resetCombo(&f)
            }
        case .getup:
            if f.stateFrame >= f.stateLength { endAction(&f) }
        case .dashing:
            f.vx *= 0.9
            if f.stateFrame >= f.stateLength { endAction(&f) }
        case .airborne:
            if let slot = f.buffered, (slot == .light1 || slot == .heavy), !f.airAttackUsed {
                f.buffered = nil
                f.airAttackUsed = true
                startMove(&f, .airAttack, side: i)
            }
        case .ko, .victory:
            f.vx *= 0.85
        case .idle, .walking, .guarding:
            neutral(&f, input, side: i, speedScale: speedScale)
        }
        fighters[i] = f
    }

    private mutating func neutral(_ f: inout RiftFighter, _ input: RiftInput, side i: Int, speedScale: Double) {
        let spec = f.spec
        // 完美格挡后的反击
        if f.counterReady > 0, f.buffered == .light1 {
            f.buffered = nil; f.counterReady = 0
            startMove(&f, .counter, side: i)
            return
        }
        if let slot = f.buffered, canStart(f, slot) {
            f.buffered = nil
            startMove(&f, slot, side: i)
            return
        }
        if f.jumpBuffered > 0 && f.grounded {
            f.jumpBuffered = 0
            f.state = .airborne; f.stateFrame = 0
            f.vy = spec.jumpVelocity
            f.vx = Double(input.horizontal) * spec.walkSpeed * 1.5 * speedScale
            f.airAttackUsed = false
            events.append(.jump(side: i))
            return
        }
        if f.dashBuffered > 0 {
            f.dashBuffered = 0
            let dir = input.horizontal != 0 ? Double(input.horizontal) : f.facing
            let back = dir != f.facing
            f.state = .dashing; f.stateFrame = 0; f.stateLength = back ? 16 : 14
            f.vx = dir * spec.dashSpeed * speedScale * (back ? 0.85 : 1)
            if back { f.invulnerable = 8 }
            events.append(.dash(side: i))
            return
        }
        if input.guardHeld {
            if f.state != .guarding { f.state = .guarding; f.stateFrame = 0 }
            f.vx = 0
            return
        }
        if input.horizontal != 0 {
            let dir = Double(input.horizontal)
            let back = dir != f.facing
            f.vx = dir * spec.walkSpeed * speedScale * (back ? 0.8 : 1)
            if f.state != .walking { f.state = .walking; f.stateFrame = 0 }
        } else {
            f.vx = 0
            if f.state != .idle { f.state = .idle; f.stateFrame = 0 }
        }
    }

    private func canStart(_ f: RiftFighter, _ slot: RiftMoveSlot) -> Bool {
        switch slot {
        case .transform: return f.canTransform
        case .ultimate: return f.canUltimate
        case .skill1, .skill2: return f.cooldown(slot) == 0
        default: return f.spec.move(slot) != nil
        }
    }

    /// 连招取消：命中或被格挡后可以取消进下一招
    private mutating func tryCancel(_ f: inout RiftFighter, side: Int) -> Bool {
        guard let current = f.slot, let move = f.move, let wanted = f.buffered else { return false }
        let firstHit = move.startup
        let whiffWindow = f.stateFrame >= f.stateLength - 6
        let canChain = (f.connected && f.stateFrame >= firstHit) || whiffWindow
        guard canChain else { return false }
        var next: RiftMoveSlot?
        switch (current, wanted) {
        case (.light1, .light1): next = .light2
        case (.light2, .light1): next = .light3
        case (.light1, .heavy), (.light2, .heavy), (.light3, .heavy): next = f.connected ? .heavy : nil
        case (.light1, .skill1), (.light2, .skill1), (.light3, .skill1), (.heavy, .skill1), (.counter, .skill1),
             (.light1, .skill2), (.light2, .skill2), (.light3, .skill2), (.heavy, .skill2), (.counter, .skill2):
            next = (f.connected && f.cooldown(wanted) == 0) ? wanted : nil
        case (_, .ultimate):
            next = (f.connected && f.canUltimate && current != .ultimate && current != .transform) ? .ultimate : nil
        default: next = nil
        }
        guard let next else { return false }
        f.buffered = nil
        startMove(&f, next, side: side)
        return true
    }

    private mutating func startMove(_ f: inout RiftFighter, _ slot: RiftMoveSlot, side i: Int) {
        guard var move = f.spec.move(slot) else { return }
        if f.isTransformed, f.spec.transform.frameScale != 1, slot != .transform {
            let s = f.spec.transform.frameScale
            move.startup = max(2, Int((Double(move.startup) * s).rounded()))
            move.active = max(1, Int((Double(move.active) * s).rounded()))
            move.recovery = max(4, Int((Double(move.recovery) * s).rounded()))
        }
        if f.isTransformed, f.spec.transform.permanentArmor, slot != .transform {
            move.armorFrom = 0
            move.armorUntil = move.startup + move.active
        }
        f.state = .attacking
        f.slot = slot
        f.move = move
        f.stateFrame = 0
        f.stateLength = move.total
        f.hitsDone = 0
        f.connected = false
        f.projectileFired = false
        f.armorAbsorbed = 0
        if move.cooldown > 0 { f.cooldowns[slot] = move.cooldown }
        if slot == .transform {
            f.rage = 0
            events.append(.transformStart(side: i))
            lastShake = max(lastShake, 0.12)
        } else if slot == .ultimate {
            f.ultimateUsed = true
            events.append(.ultimate(side: i))
            freeze = max(freeze, 18)
        }
        if move.invulnUntil > 0 { f.invulnerable = max(f.invulnerable, move.invulnUntil) }
        events.append(.swing(side: i, slot: slot, style: move.style))
    }

    private func endAction(_ f: inout RiftFighter) {
        f.slot = nil; f.move = nil; f.stateFrame = 0; f.stateLength = 0
        f.state = f.grounded ? .idle : .airborne
    }

    private func resetCombo(_ f: inout RiftFighter) {
        f.comboHits = 0; f.comboDamage = 0; f.juggleCount = 0
    }

    // MARK: - 物理

    private mutating func physics() {
        for i in 0..<2 {
            var f = fighters[i]
            let wasAir = !f.grounded
            let airborneStates: Set<RiftFighterState> = [.airborne, .launched]
            if !f.grounded || f.vy > 0 || airborneStates.contains(f.state) {
                f.vy -= Self.gravity
                f.y += f.vy
            }
            f.x += f.vx
            if f.y <= 0 {
                f.y = 0
                if wasAir || f.vy < 0 {
                    let heavyLanding = f.state == .launched
                    f.vy = 0
                    if f.state == .launched {
                        f.state = .knockdown; f.stateFrame = 0; f.stateLength = 40
                        events.append(.knockdown(side: i))
                    } else if f.state == .airborne {
                        f.state = .idle; f.stateFrame = 0
                    } else if f.state == .attacking, f.slot == .airAttack {
                        f.state = .idle; f.slot = nil; f.move = nil
                    } else if f.state == .hitstun, f.knockdownPending {
                        f.state = .knockdown; f.stateFrame = 0; f.stateLength = 40
                    }
                    f.knockdownPending = false
                    if wasAir { events.append(.land(side: i, heavy: heavyLanding)) }
                }
            }
            f.x = min(Self.stageHalfWidth, max(-Self.stageHalfWidth, f.x))
            fighters[i] = f
        }
        // 互相推开
        let dx = fighters[1].x - fighters[0].x
        let minGap = Self.bodyHalfWidth * 2
        if abs(dx) < minGap && abs(fighters[1].y - fighters[0].y) < 1.2 {
            let push = (minGap - abs(dx)) / 2
            let dir: Double = dx >= 0 ? 1 : -1
            fighters[0].x -= push * dir
            fighters[1].x += push * dir
            for i in 0..<2 { fighters[i].x = min(Self.stageHalfWidth, max(-Self.stageHalfWidth, fighters[i].x)) }
        }
    }

    private mutating func updateFacing(_ i: Int) {
        let neutralStates: Set<RiftFighterState> = [.idle, .walking, .guarding, .getup]
        guard neutralStates.contains(fighters[i].state) else { return }
        let other = fighters[1 - i].x
        let d = other - fighters[i].x
        if abs(d) > 0.05 { fighters[i].facing = d > 0 ? 1 : -1 }
    }

    // MARK: - 命中

    private func isHittable(_ d: RiftFighter) -> Bool {
        if d.invulnerable > 0 { return false }
        switch d.state {
        case .knockdown, .getup, .ko, .victory: return false
        case .launched: return d.juggleCount < 4
        default: return true
        }
    }

    private func overlaps(attacker a: RiftFighter, move: RiftMoveSpec, defender d: RiftFighter) -> Bool {
        let dx = d.x - a.x
        let bodyLow = d.y, bodyHigh = d.y + Self.bodyHeight
        if move.radius > 0 {
            return abs(dx) <= move.radius + Self.bodyHalfWidth && d.y < a.y + 2.2
        }
        let rel = dx * a.facing
        let horizontal = rel + Self.bodyHalfWidth >= move.reachStart && rel - Self.bodyHalfWidth <= move.reachEnd
        let low = a.y + move.hitLow, high = a.y + move.hitHigh
        return horizontal && bodyHigh >= low && bodyLow <= high
    }

    private mutating func resolveMelee() {
        var pending: [(Int, RiftMoveSpec)] = []
        for i in 0..<2 {
            var a = fighters[i]
            guard a.state == .attacking, let move = a.move, move.damage > 0, move.projectile == nil,
                  a.hitsDone < move.hits else { continue }
            let hitFrames = (0..<move.hits).map { move.startup + ($0 * move.active) / move.hits }
            let hitIndex = a.hitsDone
            let windowStart = hitFrames[hitIndex]
            let windowEnd = hitIndex + 1 < move.hits ? hitFrames[hitIndex + 1] : move.startup + move.active
            guard a.stateFrame >= windowStart else { continue }
            if a.stateFrame >= windowEnd { a.hitsDone += 1; fighters[i] = a; continue }
            let d = fighters[1 - i]
            guard isHittable(d), overlaps(attacker: a, move: move, defender: d) else { continue }
            a.hitsDone += 1
            fighters[i] = a
            pending.append((i, move))
        }
        for (i, move) in pending {
            applyHit(attacker: i, move: move, sourceX: fighters[i].x, projectile: false)
        }
    }

    private mutating func applyHit(attacker i: Int, move: RiftMoveSpec, sourceX: Double, projectile: Bool) {
        var a = fighters[i]
        var d = fighters[1 - i]
        let dir: Double = d.x >= sourceX ? 1 : -1
        let contactX = d.x - dir * 0.3
        let contactY = d.y + 1.15

        // 吴庸铁壁：架势中被打，自动反击
        if d.state == .attacking, let stance = d.move, stance.counterStance,
           d.stateFrame >= stance.startup, d.stateFrame < stance.startup + stance.active {
            events.append(.hit(RiftHitEvent(attacker: 1 - i, x: contactX, y: contactY, damage: 0, tier: .heavy,
                                            style: .counterStance, kind: .parry, heroID: d.heroID)))
            fighters[1 - i] = d
            var dd = fighters[1 - i]
            dd.facing = a.x >= dd.x ? 1 : -1
            startMove(&dd, .counter, side: 1 - i)
            dd.invulnerable = max(dd.invulnerable, 10)
            fighters[1 - i] = dd
            if !projectile {
                a.state = .parried; a.stateFrame = 0; a.stateLength = 20; a.slot = nil; a.move = nil
                fighters[i] = a
            }
            freeze = max(freeze, 10)
            lastShake = max(lastShake, 0.1)
            return
        }

        let facingAttacker = (sourceX - d.x) * d.facing >= -0.1
        if d.state == .guarding, facingAttacker, !move.unblockable {
            if frame - d.guardPressedAt <= d.spec.parryWindow {
                // 完美格挡：对手露出破绽，自己获得反击机会
                d.rage = min(100, d.rage + 12)
                d.counterReady = 32
                d.guardMeter = min(100, d.guardMeter + 20)
                if !projectile {
                    a.state = .parried; a.stateFrame = 0; a.stateLength = 34; a.slot = nil; a.move = nil
                    a.vx = -dir * 0.05
                }
                events.append(.hit(RiftHitEvent(attacker: i, x: contactX, y: contactY, damage: 0, tier: .heavy,
                                                style: move.style, kind: .parry, heroID: a.heroID)))
                freeze = max(freeze, 9)
                lastShake = max(lastShake, 0.06)
            } else {
                let chip = max(1, Int(Double(move.damage) * 0.12))
                d.health = max(1, d.health - chip)
                d.guardMeter -= Double(move.guardDamage)
                d.rage = min(100, d.rage + 3)
                a.rage = min(100, a.rage + 2)
                a.connected = true
                if d.guardMeter <= 0 {
                    d.guardMeter = 100
                    d.state = .guardBreak; d.stateFrame = 0; d.stateLength = 56
                    d.vx = dir * 0.06
                    events.append(.hit(RiftHitEvent(attacker: i, x: contactX, y: contactY, damage: chip, tier: .heavy,
                                                    style: move.style, kind: .guardBreak, heroID: a.heroID)))
                    freeze = max(freeze, 10)
                    lastShake = max(lastShake, 0.12)
                } else {
                    d.state = .blockstun; d.stateFrame = 0; d.stateLength = move.blockstun
                    d.vx = dir * max(0.03, move.knockback * 0.6)
                    events.append(.hit(RiftHitEvent(attacker: i, x: contactX, y: contactY, damage: chip, tier: move.impact,
                                                    style: move.style, kind: .block, heroID: a.heroID)))
                    freeze = max(freeze, 3)
                }
            }
            fighters[i] = a
            fighters[1 - i] = d
            return
        }

        // 正常命中
        let counterHit = d.state == .attacking && d.phase == .startup
        let attackScale = a.isTransformed ? a.spec.transform.damageScale : 1
        let takenScale = d.isTransformed ? d.spec.transform.damageTaken : 1
        let comboScale = max(0.45, 1 - 0.08 * Double(d.comboHits))
        var damage = Double(move.damage) * attackScale * takenScale * comboScale * (counterHit ? 1.2 : 1)
        var echo = 0.0
        if a.isTransformed, a.spec.transform.echoDamage > 0 { echo = damage * a.spec.transform.echoDamage }
        let cap = Int(Double(d.maxHealth) * Self.comboDamageCap)
        let remaining = max(0, cap - d.comboDamage)
        damage = min(damage, Double(remaining))
        echo = min(echo, Double(max(0, remaining - Int(damage))))
        let total = max(remaining > 0 ? 1 : 0, Int(damage.rounded()) + Int(echo.rounded()))
        d.health = max(0, d.health - total)
        d.comboHits += 1
        d.comboDamage += total
        d.lastDamageTaken = total
        d.hitFlash = 6
        a.connected = true
        a.rage = min(100, a.rage + Double(total) * 0.11)
        d.rage = min(100, d.rage + Double(total) * 0.09)

        let armored: Bool = {
            guard d.state == .attacking, let dm = d.move else { return false }
            let limit = d.isTransformed && d.spec.transform.permanentArmor ? 2 : 1
            return d.stateFrame >= dm.armorFrom && d.stateFrame < dm.armorUntil && dm.armorUntil > 0 && d.armorAbsorbed < limit
        }()
        if armored { d.armorAbsorbed += 1 }
        let kind: RiftHitKind = armored ? .armor : (counterHit ? .counterHit : .hit)
        events.append(.hit(RiftHitEvent(attacker: i, x: contactX, y: contactY, damage: total, tier: move.impact,
                                        style: move.style, kind: kind, heroID: a.heroID)))
        if echo >= 1 {
            events.append(.hit(RiftHitEvent(attacker: i, x: contactX, y: contactY + 0.2, damage: Int(echo.rounded()),
                                            tier: .light, style: .crossSlash, kind: .echo, heroID: a.heroID)))
        }
        freeze = max(freeze, armored ? 3 : move.impact.hitstop + (counterHit ? 3 : 0))
        lastShake = max(lastShake, move.impact.shake * (armored ? 0.5 : 1))

        if d.health <= 0 {
            d.state = .launched; d.stateFrame = 0
            d.vy = 0.17; d.vx = dir * 0.09
            d.slot = nil; d.move = nil
            events.append(.ko(side: 1 - i))
            freeze = max(freeze, 30)
            lastShake = max(lastShake, 0.25)
        } else if !armored {
            d.slot = nil; d.move = nil
            let airborne = !d.grounded || d.state == .launched
            if move.launch > 0 || airborne {
                d.state = .launched; d.stateFrame = 0
                d.vy = max(move.launch, airborne ? 0.10 : 0)
                d.vx = dir * max(0.03, move.knockback * 0.7)
                d.juggleCount += 1
            } else {
                d.state = .hitstun; d.stateFrame = 0
                d.stateLength = move.hitstun + move.stun + (counterHit ? 6 : 0)
                d.vx = dir * move.knockback
                d.knockdownPending = move.knockdown
                if move.knockdown && d.grounded {
                    d.state = .launched; d.vy = 0.07; d.juggleCount += 1
                }
            }
        }
        // 连招伤害到上限：受击方破招脱身
        if d.health > 0, d.comboDamage >= cap {
            d.state = .airborne; d.stateFrame = 0
            d.vy = 0.14; d.vx = dir * 0.12
            d.invulnerable = 40
            d.slot = nil; d.move = nil
            resetCombo(&d)
            events.append(.burst(side: 1 - i))
        }
        fighters[i] = a
        fighters[1 - i] = d
    }

    // MARK: - 飞行道具

    private mutating func spawnProjectile(owner i: Int, fighter f: RiftFighter, spec: RiftProjectileSpec, move: RiftMoveSpec) {
        var heights = [spec.height]
        if f.isTransformed && f.spec.transform.doubleProjectile && spec.style != .dragonWave { heights.append(0.45) }
        for h in heights {
            projectiles.append(RiftProjectile(owner: i, x: f.x + f.facing * 0.7, y: h, vx: spec.speed * f.facing,
                                              spec: spec, move: move, hitsLeft: spec.hits, id: nextProjectileID))
            nextProjectileID += 1
        }
        events.append(.projectileSpawned(side: i, style: spec.style))
    }

    private mutating func updateProjectiles() {
        guard !projectiles.isEmpty else { return }
        for k in projectiles.indices {
            projectiles[k].x += projectiles[k].vx
            projectiles[k].age += 1
            if projectiles[k].hitCooldown > 0 { projectiles[k].hitCooldown -= 1 }
        }
        // 互相抵消
        for a in projectiles.indices {
            for b in projectiles.indices where b > a {
                guard projectiles[a].owner != projectiles[b].owner, projectiles[a].hitsLeft > 0, projectiles[b].hitsLeft > 0 else { continue }
                if abs(projectiles[a].x - projectiles[b].x) < projectiles[a].spec.halfWidth + projectiles[b].spec.halfWidth,
                   abs(projectiles[a].y - projectiles[b].y) < projectiles[a].spec.halfHeight + projectiles[b].spec.halfHeight {
                    let pa = projectiles[a].spec.hits, pb = projectiles[b].spec.hits
                    projectiles[a].hitsLeft -= max(1, pb)
                    projectiles[b].hitsLeft -= max(1, pa)
                    events.append(.projectileClash(x: (projectiles[a].x + projectiles[b].x) / 2, y: projectiles[a].y))
                }
            }
        }
        var hits: [(Int, RiftMoveSpec, Double)] = []
        for k in projectiles.indices {
            var p = projectiles[k]
            guard p.hitsLeft > 0, p.hitCooldown == 0 else { continue }
            let d = fighters[1 - p.owner]
            guard isHittable(d) else { continue }
            let horizontal = abs(d.x - p.x) <= p.spec.halfWidth + Self.bodyHalfWidth
            let vertical = d.y + Self.bodyHeight >= p.y - p.spec.halfHeight && d.y <= p.y + p.spec.halfHeight
            if horizontal && vertical {
                p.hitsLeft -= 1
                p.hitCooldown = p.spec.hitInterval
                hits.append((p.owner, p.move, p.x - p.vx * 4))
            }
            projectiles[k] = p
        }
        for (owner, move, x) in hits { applyHit(attacker: owner, move: move, sourceX: x, projectile: true) }
        projectiles.removeAll { $0.hitsLeft <= 0 || $0.age >= $0.spec.lifetime || abs($0.x) > Self.stageHalfWidth + 1 }
    }

    // MARK: - 回合

    private mutating func tickTimers() {
        if !trainingMode { roundTicksLeft = max(0, roundTicksLeft - 1) }
    }

    private mutating func checkRoundEnd() {
        guard phase == .fighting else { return }
        let koSides = (0..<2).filter { fighters[$0].health <= 0 }
        var winner: Int?
        if !koSides.isEmpty {
            winner = koSides.count == 2 ? nil : 1 - koSides[0]
        } else if roundTicksLeft == 0 {
            let r0 = Double(fighters[0].health) / Double(fighters[0].maxHealth)
            let r1 = Double(fighters[1].health) / Double(fighters[1].maxHealth)
            winner = abs(r0 - r1) < 0.0001 ? nil : (r0 > r1 ? 0 : 1)
        } else {
            return
        }
        if trainingMode {
            // 训练场：木桩不会被打死，自己回满
            for i in 0..<2 { fighters[i].health = fighters[i].maxHealth }
            return
        }
        roundWinner = winner
        if let winner {
            fighters[winner].wins += 1
            if fighters[winner].state != .attacking { fighters[winner].state = .victory; fighters[winner].stateFrame = 0 }
        }
        events.append(.roundEnd(winner: winner))
        phase = .roundOver
        phaseFrame = 0
        projectiles.removeAll()
        if let winner, fighters[winner].wins >= Self.roundsToWin {
            matchWinner = winner
        } else if winner == nil, round >= 5 {
            matchWinner = fighters[0].wins == fighters[1].wins ? nil : (fighters[0].wins > fighters[1].wins ? 0 : 1)
        }
    }

    private mutating func advanceRound() {
        if matchWinner != nil || (round >= 5) {
            phase = .matchOver; phaseFrame = 0
            events.append(.matchEnd(winner: matchWinner))
            return
        }
        round += 1
        for i in 0..<2 {
            let old = fighters[i]
            var f = RiftFighter(heroID: old.heroID, x: i == 0 ? -2.2 : 2.2, facing: i == 0 ? 1 : -1, health: old.maxHealth)
            f.wins = old.wins
            f.rage = min(100, old.rage)
            fighters[i] = f
        }
        roundTicksLeft = Self.roundSeconds * Self.ticksPerSecond
        roundWinner = nil
        phase = .intro; phaseFrame = 0
        events.append(.roundStart(round: round))
    }

    /// 测试与表现层用：直接给某侧加怒气
    public mutating func debugSetRage(_ side: Int, _ value: Double) { fighters[side].rage = value }
    public mutating func debugSkipIntro() { if phase == .intro { phase = .fighting; phaseFrame = 0 } }
    public mutating func debugPlace(_ side: Int, x: Double) { fighters[side].x = x }
}
