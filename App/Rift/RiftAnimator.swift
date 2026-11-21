import Foundation

/// 把战斗状态翻译成骨骼姿势。所有动作都是程序化关键帧：
/// 起手（蓄力）→ 出招（挥出，最快）→ 收招（回到架势），配合缓动曲线做出“重量感”。
enum RiftAnimator {

    // MARK: 基础架势

    static func stance(_ hero: RiftHeroID, t: Double) -> RiftPose {
        let breathe = Float(sin(t * 2.4)) * 0.025
        var p = RiftPose()
        p.hipsY = -0.06 + breathe * 0.5
        p.lean = 0.12 + breathe
        p.rThigh = 0.35; p.rKnee = 0.45
        p.lThigh = -0.15; p.lKnee = 0.25
        p.head = -0.05
        switch hero {
        case .sunDeng:
            // 双刀反握，前低后高
            p.rShoulder = 0.9; p.rRaise = 0.35; p.rElbow = 1.3; p.rWrist = 1.4
            p.lShoulder = 0.5; p.lRaise = 0.25; p.lElbow = 1.0; p.lWrist = 1.6
            p.twist = -0.25; p.hipsY = -0.12
        case .wuYong:
            // 中段青眼架势，双手握刀
            p.rShoulder = 0.85; p.rRaise = 0.15; p.rElbow = 0.9; p.rWrist = 1.0
            p.lShoulder = 0.9; p.lRaise = -0.1; p.lElbow = 1.1; p.lWrist = 1.0
            p.twist = -0.15
        case .liuQuanwei:
            // 巨斧扛肩
            p.rShoulder = 2.2; p.rRaise = 0.5; p.rElbow = 1.9; p.rWrist = 0.4
            p.lShoulder = 0.6; p.lRaise = 0.2; p.lElbow = 0.6; p.lWrist = 0.6
            p.hipsY = -0.1; p.lean = 0.2
            p.rThigh = 0.45; p.lThigh = -0.25
        case .xuXiao:
            // 帝王持剑，左手负于身后
            p.rShoulder = 0.7; p.rRaise = 0.2; p.rElbow = 0.6; p.rWrist = 1.2
            p.lShoulder = -0.35; p.lRaise = 0.15; p.lElbow = 1.6; p.lWrist = 0.4
            p.lean = 0.04; p.hipsY = -0.03
            p.twist = -0.1
        }
        return p
    }

    // MARK: 招式关键帧（起手 / 出招）

    static func strikeKeys(_ style: RiftMoveStyle, hero: RiftHeroID) -> (RiftPose, RiftPose) {
        var a = stance(hero, t: 0), b = stance(hero, t: 0)
        switch style {
        case .quickSlash:
            a.rShoulder = 2.4; a.rRaise = 0.9; a.rElbow = 1.2; a.twist = -0.6; a.rWrist = 1.4
            b.rShoulder = 0.9; b.rRaise = -0.5; b.rElbow = 0.1; b.twist = 0.55; b.rWrist = 0.6; b.lean = 0.35
        case .crossSlash:
            a.rShoulder = 2.3; a.rRaise = -0.4; a.lShoulder = 2.3; a.lRaise = -0.4; a.twist = -0.3; a.rElbow = 1; a.lElbow = 1
            b.rShoulder = 1.0; b.rRaise = 1.0; b.lShoulder = 1.0; b.lRaise = 1.0; b.rElbow = 0.1; b.lElbow = 0.1; b.twist = 0.3; b.lean = 0.35
        case .risingSlash:
            a.rShoulder = -0.3; a.rRaise = 0.3; a.rElbow = 0.3; a.hipsY = -0.22; a.twist = -0.5
            b.rShoulder = 2.9; b.rRaise = 0.2; b.rElbow = 0.1; b.hipsY = 0.02; b.twist = 0.3; b.lean = -0.1
        case .spinSlash:
            a.rShoulder = 1.4; a.rRaise = 1.4; a.lShoulder = 1.4; a.lRaise = 1.4; a.hipsY = -0.15
            b = a; b.rElbow = 0; b.lElbow = 0
        case .thrust:
            a.rShoulder = 0.6; a.rElbow = 2.0; a.rWrist = 1.5; a.twist = -0.6; a.lean = 0
            b.rShoulder = 1.55; b.rRaise = -0.1; b.rElbow = 0; b.rWrist = 1.55; b.twist = 0.45; b.lean = 0.45
            b.rThigh = 0.9; b.rKnee = 0.8; b.lThigh = -0.5; b.hipsY = -0.2
        case .overhead:
            a.rShoulder = 3.0; a.rElbow = 0.6; a.lShoulder = 3.0; a.lElbow = 0.6; a.lean = -0.25; a.hipsY = 0
            b.rShoulder = 0.7; b.rElbow = 0; b.lShoulder = 0.7; b.lElbow = 0.1; b.lean = 0.55; b.hipsY = -0.22
            b.rWrist = 1.3; b.rThigh = 0.8; b.rKnee = 0.9
        case .groundSlam:
            a.rShoulder = 3.1; a.rElbow = 0.3; a.lShoulder = 3.0; a.lElbow = 0.4; a.lean = -0.35; a.hipsY = 0.02
            b.rShoulder = 0.35; b.rElbow = 0; b.lShoulder = 0.4; b.lElbow = 0; b.lean = 0.75; b.hipsY = -0.35
            b.rWrist = 1.5; b.rThigh = 1.0; b.rKnee = 1.2; b.lThigh = -0.5; b.lKnee = 0.6
        case .dashSlash:
            a.rShoulder = -0.5; a.rRaise = 0.6; a.lShoulder = -0.5; a.lRaise = 0.6; a.hipsY = -0.25; a.lean = 0.6
            b.rShoulder = 1.3; b.rRaise = -0.9; b.lShoulder = 1.3; b.lRaise = -0.9; b.hipsY = -0.18; b.lean = 0.5
            b.twist = 0.5; b.rElbow = 0; b.lElbow = 0; b.rThigh = 1.0; b.rKnee = 0.9; b.lThigh = -0.7
        case .iaiDraw:
            a.rShoulder = 0.5; a.rRaise = -0.9; a.rElbow = 1.4; a.rWrist = 1.6; a.twist = -0.8; a.hipsY = -0.2; a.lean = 0.35
            a.lShoulder = 0.4; a.lRaise = -0.5; a.lElbow = 1.2
            b.rShoulder = 1.45; b.rRaise = 1.0; b.rElbow = 0; b.rWrist = 1.2; b.twist = 0.7; b.hipsY = -0.25; b.lean = 0.4
            b.lShoulder = 0.2; b.lRaise = 0.4; b.lElbow = 0.3; b.rThigh = 1.0; b.rKnee = 0.9; b.lThigh = -0.6
        case .counterStance:
            a.rShoulder = 1.5; a.rRaise = -0.5; a.rElbow = 0.7; a.rWrist = 0.3; a.lShoulder = 1.4; a.lRaise = -0.6; a.lElbow = 0.8
            a.hipsY = -0.2; a.twist = -0.3
            b = a
        case .cast:
            a.lShoulder = 0.3; a.lElbow = 2.0; a.rShoulder = 2.6; a.rRaise = 0.4; a.twist = -0.5
            b.rShoulder = 1.3; b.rRaise = -0.3; b.rElbow = 0; b.lShoulder = 1.5; b.lElbow = 0; b.lRaise = 0.1; b.twist = 0.4; b.lean = 0.3
        case .roar:
            a.rShoulder = 0.3; a.rRaise = -0.2; a.lShoulder = 0.3; a.lRaise = -0.2; a.lean = 0.5; a.hipsY = -0.2; a.head = 0.3
            b.rShoulder = 0.8; b.rRaise = 1.4; b.lShoulder = 0.8; b.lRaise = 1.4; b.rElbow = 0.2; b.lElbow = 0.2
            b.lean = -0.3; b.head = -0.4; b.hipsY = -0.05
        case .airSlash:
            a.rShoulder = 3.0; a.rElbow = 0.4; a.lShoulder = 2.6; a.rThigh = 1.2; a.rKnee = 1.6; a.lThigh = 0.9; a.lKnee = 1.8
            b.rShoulder = 0.4; b.rElbow = 0; b.lShoulder = 0.6; b.lean = 0.6; b.rThigh = 0.7; b.rKnee = 0.8; b.lThigh = 0.5; b.lKnee = 1.2
        case .transform:
            a.hipsY = -0.35; a.lean = 0.7; a.rShoulder = 0.2; a.lShoulder = 0.2; a.rElbow = 1.8; a.lElbow = 1.8; a.head = 0.4
            b.hipsY = 0.02; b.lean = -0.25; b.rShoulder = 2.4; b.rRaise = 0.9; b.lShoulder = 2.4; b.lRaise = 0.9
            b.rElbow = 0.1; b.lElbow = 0.1; b.head = -0.45
        case .flurry:
            a.rShoulder = 2.2; a.lShoulder = 0.6; a.hipsY = -0.2; a.lean = 0.45
            b.rShoulder = 0.6; b.lShoulder = 2.2; b.hipsY = -0.2; b.lean = 0.45
        case .dragonWave:
            a.rShoulder = 0.4; a.lShoulder = 0.4; a.rElbow = 2.0; a.lElbow = 2.0; a.twist = -0.6; a.hipsY = -0.2
            b.rShoulder = 1.6; b.lShoulder = 1.6; b.rElbow = 0; b.lElbow = 0; b.twist = 0.1; b.lean = 0.4; b.hipsY = -0.25
            b.rThigh = 0.9; b.rKnee = 0.8; b.lThigh = -0.6
        }
        if hero == .wuYong || hero == .liuQuanwei {
            // 双手武器：左手跟随右手
            a.lShoulder = a.rShoulder * 0.95; a.lRaise = -a.rRaise * 0.6 - 0.2; a.lElbow = a.rElbow + 0.2
            b.lShoulder = b.rShoulder * 0.95; b.lRaise = -b.rRaise * 0.6 - 0.2; b.lElbow = b.rElbow + 0.2
        }
        return (a, b)
    }

    // MARK: 主入口

    static func pose(for f: RiftFighter, time t: Double, frame: Int) -> RiftPose {
        let hero = f.heroID
        let base = stance(hero, t: t)
        let sf = Float(f.stateFrame)
        switch f.state {
        case .idle:
            return base
        case .guarding, .blockstun:
            var p = base
            p.rShoulder = 1.7; p.rRaise = -0.6; p.rElbow = 1.0; p.rWrist = 0.2
            p.lShoulder = 1.6; p.lRaise = -0.5; p.lElbow = 1.3; p.lWrist = 0.4
            p.hipsY = -0.16; p.lean = 0.05; p.twist = -0.2
            if f.state == .blockstun {
                let k = Float(max(0, 1 - Double(f.stateFrame) / 10))
                p.lean -= 0.25 * k; p.hipsForward = -0.06 * k
            }
            return p
        case .walking:
            var p = base
            let forward: Float = f.vx * f.facing >= 0 ? 1 : -1
            let ph = Float(t * 9) * forward
            p.rThigh = base.rThigh + sin(ph) * 0.45; p.rKnee = base.rKnee + max(0, -cos(ph)) * 0.6
            p.lThigh = base.lThigh - sin(ph) * 0.45; p.lKnee = base.lKnee + max(0, cos(ph)) * 0.6
            p.hipsY = base.hipsY + abs(sin(ph)) * 0.03
            return p
        case .dashing:
            var p = base
            let back = f.vx * f.facing < 0
            p.lean = back ? -0.25 : 0.6
            p.hipsY = -0.2
            p.rThigh = back ? -0.4 : 1.1; p.rKnee = 0.9; p.lThigh = back ? 0.6 : -0.6; p.lKnee = 0.5
            p.rShoulder = back ? 1.2 : -0.4; p.lShoulder = back ? 1.0 : -0.3
            return p
        case .airborne:
            var p = base
            p.rThigh = 1.0; p.rKnee = 1.5; p.lThigh = 0.5; p.lKnee = 1.2
            p.rootPitch = f.vy > 0 ? -0.1 : 0.1
            return p
        case .attacking:
            return attackPose(f, base: base, t: t)
        case .hitstun, .stunned, .guardBreak, .parried:
            var p = base
            let k = Float(max(0, 1 - Double(f.stateFrame) / max(1, Double(f.stateLength))))
            let recoil = f.state == .hitstun ? k : 1
            p.lean = -0.45 * recoil; p.head = -0.5 * recoil
            p.rShoulder = 0.3 + 0.8 * recoil; p.rRaise = 0.9 * recoil
            p.lShoulder = 0.2 + 0.6 * recoil; p.lRaise = 0.9 * recoil
            p.hipsForward = -0.1 * recoil; p.hipsY = -0.12
            if f.state != .hitstun {
                // 失衡摇晃
                let wob = Float(sin(Double(frame) * 0.35)) * 0.12
                p.rootRoll = wob; p.head += wob
                p.rShoulder = -0.3; p.lShoulder = -0.3; p.rRaise = 1.1; p.lRaise = 1.1
            }
            return p
        case .launched:
            var p = base
            p.rootPitch = -min(1.4, Float(f.stateFrame) * 0.06)
            p.rShoulder = 2.2; p.lShoulder = 2.0; p.rRaise = 0.6; p.lRaise = 0.6; p.rElbow = 0.3; p.lElbow = 0.3
            p.rThigh = 0.6; p.rKnee = 0.9; p.lThigh = 0.2; p.lKnee = 0.4; p.head = -0.4
            return p
        case .knockdown, .ko:
            var p = RiftPose()
            p.rootPitch = -.pi / 2; p.hipsY = -0.82
            p.rShoulder = 2.8; p.lShoulder = 2.5; p.rRaise = 0.5; p.lRaise = 0.7
            p.rThigh = 0.15; p.lThigh = 0.3; p.lKnee = 0.5
            let bounce = f.state == .knockdown && sf < 10 ? sin(sf / 10 * .pi) * 0.12 : 0
            p.hipsY += bounce
            return p
        case .getup:
            var lying = RiftPose()
            lying.rootPitch = -.pi / 2; lying.hipsY = -0.82
            let k = ease(min(1, sf / Float(max(1, f.stateLength))))
            return RiftPose.mix(lying, base, k)
        case .victory:
            var p = base
            let k = ease(min(1, sf / 30))
            var v = base
            v.rShoulder = 3.0; v.rRaise = 0.3; v.rElbow = 0.2; v.lShoulder = 0.3; v.lRaise = 0.5
            v.lean = -0.1; v.head = -0.25; v.hipsY = 0; v.rThigh = 0.1; v.lThigh = -0.1; v.rKnee = 0.1; v.lKnee = 0.1
            if hero == .xuXiao { v.rShoulder = 1.5; v.rElbow = 0; v.lShoulder = -0.35; v.lElbow = 1.6 }
            p = RiftPose.mix(base, v, k)
            return p
        }
    }

    private static func attackPose(_ f: RiftFighter, base: RiftPose, t: Double) -> RiftPose {
        guard let move = f.move else { return base }
        let (wind, strike) = strikeKeys(move.style, hero: f.heroID)
        let s = f.stateFrame
        var p: RiftPose
        if s < move.startup {
            let k = easeOut(Float(s) / Float(max(1, move.startup)))
            p = RiftPose.mix(base, wind, k)
        } else if s < move.startup + move.active {
            let k = Float(s - move.startup) / Float(max(1, move.active))
            // 出招前 40% 时间完成 85% 的挥动：快、狠
            let fast = min(1, easeOut(min(1, k * 2.2)))
            p = RiftPose.mix(wind, strike, fast)
            if move.style == .spinSlash {
                p.rootYaw = Float(k) * .pi * 2 * Float(max(1, move.hits / 2))
            }
            if move.style == .flurry {
                let osc = (sin(Double(s) * 0.9) + 1) / 2
                p = RiftPose.mix(wind, strike, Float(osc))
            }
            if f.slot == .ultimate, move.style == .iaiDraw {
                p.rootYaw = sin(Float(k) * .pi * 3) * 0.4
            }
        } else {
            let k = Float(s - move.startup - move.active) / Float(max(1, move.recovery))
            p = RiftPose.mix(strike, base, easeInOut(k))
        }
        return p
    }

    static func ease(_ x: Float) -> Float { x * x * (3 - 2 * x) }
    static func easeOut(_ x: Float) -> Float { 1 - (1 - x) * (1 - x) }
    static func easeInOut(_ x: Float) -> Float { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
}
