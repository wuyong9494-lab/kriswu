import Foundation

/// 可复现的随机数（同一个种子得到同样的对局，便于测试和回放）
public struct RiftRandom: Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    public mutating func chance(_ p: Double) -> Bool { Double(next() % 10_000) / 10_000 < p }
    public mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
    }
}

public enum RiftDifficulty: String, CaseIterable, Codable, Sendable, Identifiable {
    case easy, normal, hard, master
    public var id: String { rawValue }
    public var title: String {
        switch self { case .easy: return "新手"; case .normal: return "普通"; case .hard: return "困难"; case .master: return "大师" }
    }
    var reaction: Int { switch self { case .easy: return 26; case .normal: return 16; case .hard: return 10; case .master: return 6 } }
    var blockChance: Double { switch self { case .easy: return 0.15; case .normal: return 0.4; case .hard: return 0.6; case .master: return 0.72 } }
    var parryChance: Double { switch self { case .easy: return 0.0; case .normal: return 0.08; case .hard: return 0.2; case .master: return 0.3 } }
    var comboChance: Double { switch self { case .easy: return 0.35; case .normal: return 0.65; case .hard: return 0.88; case .master: return 0.97 } }
    var aggression: Double { switch self { case .easy: return 0.25; case .normal: return 0.45; case .hard: return 0.6; case .master: return 0.7 } }
    var skillUse: Double { switch self { case .easy: return 0.2; case .normal: return 0.45; case .hard: return 0.7; case .master: return 0.85 } }
}

/// 电脑对手：会走位、防御、完美格挡、连招、放技能、变身和终极技
public struct RiftAI: Sendable {
    public let side: Int
    public let difficulty: RiftDifficulty
    private var rng: RiftRandom
    private var nextThink = 0
    private var horizontal: Int8 = 0
    private var holdGuardUntil = -1
    private var parryPressAt = -1
    private var watchedAttack = -1
    private var lastChainFrame = -100

    public init(side: Int, difficulty: RiftDifficulty, seed: UInt64) {
        self.side = side
        self.difficulty = difficulty
        rng = RiftRandom(seed: seed &* 31 &+ UInt64(side))
    }

    public mutating func input(for fight: RiftFight) -> RiftInput {
        var out = RiftInput()
        guard fight.phase == .fighting else { return out }
        let me = fight.fighters[side]
        let op = fight.fighters[1 - side]
        let frame = fight.frame
        let dx = op.x - me.x
        let dist = abs(dx)
        let toward: Int8 = dx >= 0 ? 1 : -1
        let spec = me.spec
        let reach = spec.move(.light1)?.reachEnd ?? 1.4

        // 1. 完美格挡后的反击
        if me.counterReady > 0 { out.light = true; return out }

        // 2. 连招：命中后继续
        if me.state == .attacking, me.connected, let slot = me.slot, frame - lastChainFrame > 4 {
            if rng.chance(difficulty.comboChance) {
                lastChainFrame = frame
                switch slot {
                case .light1, .light2:
                    out.light = true
                case .light3:
                    if me.canUltimate && rng.chance(0.6) { out.transform = true }
                    else if me.cooldown(.skill1) == 0 && rng.chance(difficulty.skillUse) { out.skill1 = true }
                    else if me.cooldown(.skill2) == 0 && rng.chance(difficulty.skillUse * 0.6) { out.skill2 = true }
                    else { out.heavy = true }
                case .heavy, .counter:
                    if me.canUltimate && rng.chance(0.5) { out.transform = true }
                    else if me.cooldown(.skill1) == 0 && rng.chance(difficulty.skillUse) { out.skill1 = true }
                default: break
                }
                return out
            }
            lastChainFrame = frame
        }

        // 3. 对手出招：防御 / 完美格挡
        if op.state == .attacking, let move = op.move, move.damage > 0 || move.projectile != nil {
            let attackID = frame - op.stateFrame
            if attackID != watchedAttack {
                watchedAttack = attackID
                let threatRange = move.projectile != nil ? 9 : (move.radius > 0 ? move.radius : move.reachEnd) + 0.9 + move.lunge * Double(move.startup)
                if dist < threatRange && rng.chance(difficulty.blockChance) {
                    let hitFrame = attackID + move.startup
                    if rng.chance(difficulty.parryChance) {
                        parryPressAt = max(frame + difficulty.reaction / 3, hitFrame - 3)
                    } else {
                        parryPressAt = frame + difficulty.reaction
                    }
                    holdGuardUntil = attackID + move.total + 2
                } else {
                    parryPressAt = -1
                }
            }
        }
        if parryPressAt >= 0, frame >= parryPressAt, frame <= holdGuardUntil {
            out.guardHeld = true
            return out
        }
        if frame > holdGuardUntil { parryPressAt = -1 }

        // 4. 思考间隔（反应速度）
        guard frame >= nextThink else {
            out.horizontal = horizontal
            return out
        }
        nextThink = frame + difficulty.reaction / 2 + rng.int(0...max(1, difficulty.reaction / 2))
        horizontal = 0

        guard me.state == .idle || me.state == .walking || me.state == .guarding || me.state == .airborne else {
            return out
        }

        // 变身 / 终极技
        if me.canTransform && (dist > 2.6 || rng.chance(0.3)) { out.transform = true; return out }
        if me.canUltimate, let ult = spec.move(.ultimate) {
            let ultReach = ult.projectile != nil ? 6 : max(ult.reachEnd, ult.radius) + ult.lunge * Double(ult.startup)
            if dist < ultReach && rng.chance(0.35) { out.transform = true; return out }
        }

        // 对空
        if !op.grounded && dist < reach + 0.4 && rng.chance(0.5) { out.light = true; return out }

        let zoner = spec.move(.skill1)?.projectile != nil
        let preferred = zoner && me.cooldown(.skill1) == 0 ? 3.6 : reach * 0.85
        if zoner && me.cooldown(.skill1) == 0 && dist > 2.4 && rng.chance(difficulty.skillUse) {
            out.skill1 = true; return out
        }

        if dist > preferred + 0.3 {
            if dist > 4.5 && rng.chance(0.25) { out.dash = true; out.horizontal = toward; return out }
            if rng.chance(0.06) { out.jump = true; out.horizontal = toward; return out }
            horizontal = toward
            out.horizontal = toward
            return out
        }

        // 在攻击距离内
        if rng.chance(difficulty.aggression) || op.state == .parried || op.state == .guardBreak || op.state == .stunned {
            let r = Double(rng.next() % 1000) / 1000
            if op.state == .guarding && me.cooldown(.skill2) == 0 && r < 0.35 { out.skill2 = true }
            else if me.cooldown(.skill1) == 0 && r < 0.2 * difficulty.skillUse { out.skill1 = true }
            else if r < 0.35 { out.heavy = true }
            else { out.light = true }
            return out
        }
        // 保持距离 / 防守
        if rng.chance(0.35) {
            horizontal = -toward
            out.horizontal = -toward
        } else if rng.chance(0.3) {
            out.guardHeld = true
        }
        return out
    }
}
