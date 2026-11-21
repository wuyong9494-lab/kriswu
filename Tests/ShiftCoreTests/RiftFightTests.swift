import XCTest
@testable import ShiftCore

final class RiftFightTests: XCTestCase {

    private func play(_ a: RiftHeroID, _ b: RiftHeroID, seed: UInt64, difficulty: RiftDifficulty = .hard,
                      maxFrames: Int = 60 * 60 * 8) -> (fight: RiftFight, frames: Int, maxCombo: Double, roundFrames: [Int]) {
        var fight = RiftFight(left: a, right: b)
        var ai0 = RiftAI(side: 0, difficulty: difficulty, seed: seed)
        var ai1 = RiftAI(side: 1, difficulty: difficulty, seed: seed &+ 7_777)
        var maxCombo = 0.0
        var roundStart = 0
        var roundFrames: [Int] = []
        var n = 0
        while fight.phase != .matchOver && n < maxFrames {
            let i0 = ai0.input(for: fight)
            let i1 = ai1.input(for: fight)
            fight.step([i0, i1])
            for side in 0..<2 {
                let f = fight.fighters[side]
                maxCombo = max(maxCombo, Double(f.comboDamage) / Double(f.maxHealth))
            }
            for e in fight.events {
                if case .fight = e { roundStart = n }
                if case .roundEnd = e { roundFrames.append(n - roundStart) }
            }
            n += 1
        }
        return (fight, n, maxCombo, roundFrames)
    }

    func testEveryHeroHasCompleteKit() {
        for hero in RiftRoster.all {
            for slot in RiftMoveSlot.allCases {
                XCTAssertNotNil(hero.move(slot), "\(hero.name) 缺少 \(slot)")
            }
            XCTAssertFalse(hero.transformName.isEmpty)
        }
    }

    func testLightAttackDealsDamage() {
        for hero in RiftHeroID.allCases {
            var fight = RiftFight(left: hero, right: .wuYong)
            fight.debugSkipIntro()
            fight.debugPlace(0, x: -0.5)
            fight.debugPlace(1, x: 0.5)
            fight.step([RiftInput(light: true), .none])
            for _ in 0..<40 { fight.step([.none, .none]) }
            XCTAssertLessThan(fight.fighters[1].health, fight.fighters[1].maxHealth, "\(hero) 轻击没有扣血")
        }
    }

    func testEverySkillAndUltimateConnects() {
        for hero in RiftHeroID.allCases {
            for slot in [RiftMoveSlot.heavy, .skill1, .skill2] where !(hero == .wuYong && slot == .skill2) {
                var fight = RiftFight(left: hero, right: .liuQuanwei)
                fight.debugSkipIntro()
                fight.debugPlace(0, x: -0.6); fight.debugPlace(1, x: 0.6)
                var input = RiftInput()
                switch slot { case .heavy: input.heavy = true; case .skill1: input.skill1 = true; default: input.skill2 = true }
                fight.step([input, .none])
                for _ in 0..<90 { fight.step([.none, .none]) }
                XCTAssertLessThan(fight.fighters[1].health, fight.fighters[1].maxHealth, "\(hero) \(slot) 没有命中")
            }
            // 变身 + 终极技
            var fight = RiftFight(left: hero, right: .liuQuanwei)
            fight.debugSkipIntro()
            fight.debugSetRage(0, 100)
            fight.debugPlace(0, x: -0.8); fight.debugPlace(1, x: 0.8)
            var sawTransform = false, sawUltimate = false
            fight.step([RiftInput(transform: true), .none])
            for _ in 0..<70 {
                fight.step([.none, .none])
                if fight.fighters[0].isTransformed { sawTransform = true }
            }
            XCTAssertTrue(sawTransform, "\(hero) 变身失败")
            let before = fight.fighters[1].health
            fight.step([RiftInput(transform: true), .none])
            for _ in 0..<160 {
                fight.step([.none, .none])
                if fight.events.contains(where: { if case .ultimate = $0 { return true }; return false }) { sawUltimate = true }
            }
            XCTAssertTrue(sawUltimate || fight.fighters[0].ultimateUsed, "\(hero) 终极技没放出来")
            XCTAssertLessThan(fight.fighters[1].health, before, "\(hero) 终极技没有伤害")
        }
    }

    func testPerfectGuardStaggersAttacker() {
        var fight = RiftFight(left: .sunDeng, right: .wuYong)
        fight.debugSkipIntro()
        fight.debugPlace(0, x: -0.5); fight.debugPlace(1, x: 0.5)
        // 孙登出重击（startup 11），吴庸在命中前 3 帧按防御
        fight.step([RiftInput(heavy: true), .none])
        var sawParry = false
        for t in 0..<40 {
            fight.step([.none, RiftInput(guardHeld: t >= 6)])
            for e in fight.events { if case .hit(let h) = e, h.kind == .parry { sawParry = true } }
        }
        XCTAssertTrue(sawParry)
        XCTAssertEqual(fight.fighters[1].health, fight.fighters[1].maxHealth)
    }

    func testNoComboExceedsCap() {
        for a in RiftHeroID.allCases {
            for b in RiftHeroID.allCases {
                for seed in 0..<6 {
                    let r = play(a, b, seed: UInt64(seed), difficulty: .master)
                    XCTAssertLessThanOrEqual(r.maxCombo, RiftFight.comboDamageCap + 0.0001, "\(a) vs \(b) 连招超过上限")
                }
            }
        }
    }

    func testMatchupsAreBalanced() {
        var report: [String] = []
        var rounds: [Int] = []
        for (ai, a) in RiftHeroID.allCases.enumerated() {
            for b in RiftHeroID.allCases.dropFirst(ai + 1) {
                var winsA = 0, winsB = 0
                for seed in 0..<100 {
                    // 左右互换，抵消站位
                    let swap = seed % 2 == 1
                    let r = play(swap ? b : a, swap ? a : b, seed: UInt64(seed * 13 + 1))
                    rounds += r.roundFrames
                    guard let w = r.fight.matchWinner else { continue }
                    let aWon = swap ? (w == 1) : (w == 0)
                    if aWon { winsA += 1 } else { winsB += 1 }
                }
                let rate = Double(winsA) / Double(max(1, winsA + winsB))
                report.append("\(a.rawValue) vs \(b.rawValue): \(winsA)-\(winsB) (\(Int(rate * 100))%)")
                XCTAssertGreaterThanOrEqual(rate, 0.35, "\(a) vs \(b) 不平衡")
                XCTAssertLessThanOrEqual(rate, 0.65, "\(a) vs \(b) 不平衡")
            }
        }
        let avg = Double(rounds.reduce(0, +)) / Double(max(1, rounds.count)) / 60
        report.append(String(format: "平均每回合 %.1f 秒（%d 回合）", avg, rounds.count))
        print(report.joined(separator: "\n"))
        XCTAssertGreaterThan(avg, 15, "回合太短，伤害过高")
        XCTAssertLessThan(avg, 80, "回合太长")
    }

    func testIntroBufferAllowsImmediateOpeningAttack() {
        var fight = RiftFight(left: .liuQuanwei, right: .sunDeng)
        fight.debugPlace(0, x: -0.5)
        fight.debugPlace(1, x: 0.5)
        XCTAssertEqual(fight.phase, .intro)
        // 在开场最后 10 帧按轻击，进入正式战斗第 1 帧应立刻起手
        for t in 0..<45 {
            let press = t == 40
            fight.step([RiftInput(light: press), .none])
        }
        XCTAssertEqual(fight.phase, .fighting)
        fight.step([.none, .none])
        XCTAssertEqual(fight.fighters[0].state, .attacking, "开场结束前按下的攻击输入丢失")
        XCTAssertEqual(fight.fighters[0].slot, .light1)
    }

    func testLiuCanHitSunWithKnockbackAndHitstop() {
        var fight = RiftFight(left: .liuQuanwei, right: .sunDeng)
        fight.debugSkipIntro()
        fight.debugPlace(0, x: -0.55)
        fight.debugPlace(1, x: 0.55)
        let sunHPBefore = fight.fighters[1].health
        let sunXBefore = fight.fighters[1].x

        fight.step([RiftInput(heavy: true), .none])
        var sawHitEvent = false
        var sawHitstop = false
        var sawShake = false
        for _ in 0..<45 {
            fight.step([.none, .none])
            if fight.freeze > 0 { sawHitstop = true }
            if fight.lastShake > 0 { sawShake = true }
            for e in fight.events {
                if case .hit(let h) = e, h.attacker == 0, h.damage > 0 { sawHitEvent = true }
            }
        }
        XCTAssertTrue(sawHitEvent, "刘泉纬重击未产生命中事件")
        XCTAssertTrue(sawHitstop, "命中时未触发顿帧")
        XCTAssertTrue(sawShake, "命中时未触发震屏")
        XCTAssertLessThan(fight.fighters[1].health, sunHPBefore, "孙登未扣血")
        XCTAssertGreaterThan(fight.fighters[1].x, sunXBefore + 0.2, "孙登未被击退")
    }

    func testWuYongFullEnergyTransformAndUltimate() {
        var fight = RiftFight(left: .wuYong, right: .sunDeng)
        fight.debugSkipIntro()
        fight.debugPlace(0, x: -0.7)
        fight.debugPlace(1, x: 0.7)
        fight.debugSetRage(0, 100)
        XCTAssertTrue(fight.fighters[0].canTransform, "吴庸满能量后无法触发变身")

        var sawTransformStart = false
        fight.step([RiftInput(transform: true), .none])
        for _ in 0..<60 {
            for e in fight.events {
                if case .transformStart(let side) = e, side == 0 { sawTransformStart = true }
            }
            fight.step([.none, .none])
        }
        XCTAssertTrue(sawTransformStart, "未发出吴庸变身事件")
        XCTAssertTrue(fight.fighters[0].isTransformed, "吴庸变身状态未激活")
        XCTAssertTrue(fight.fighters[0].canUltimate, "吴庸变身后无法施放终极技")

        let hpBefore = fight.fighters[1].health
        var sawUltimate = false
        fight.step([RiftInput(transform: true), .none])
        for _ in 0..<80 {
            for e in fight.events {
                if case .ultimate(let side) = e, side == 0 { sawUltimate = true }
            }
            fight.step([.none, .none])
        }
        XCTAssertTrue(sawUltimate, "吴庸终极技未触发")
        XCTAssertLessThan(fight.fighters[1].health, hpBefore, "吴庸终极技未造成伤害")
    }
}
