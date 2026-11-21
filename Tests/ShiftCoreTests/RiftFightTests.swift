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
}
