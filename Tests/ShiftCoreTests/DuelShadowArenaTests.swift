import XCTest
@testable import ShiftCore

final class DuelShadowArenaTests: XCTestCase {
    private func closeArena(_ hero: DuelGame.Hero = .wuYong, opponent: DuelGame.Hero = .ember,
                            seed: UInt64 = 20261121) -> DuelGame {
        var game = DuelGame(hero: hero, seed: seed, opponentHero: opponent, ruleset: .shadowArena)
        for _ in 0..<24 {
            game.step(.init(move: 1), opponent: .init(move: -1))
        }
        return game
    }

    func testShadowArenaHeroHealthPoolsAreDifferentiated() {
        let nonnaVsMid = DuelGame(hero: .liu, opponentHero: .ember, ruleset: .shadowArena)
        XCTAssertEqual(nonnaVsMid.fighters[0].health, 3000)
        XCTAssertEqual(nonnaVsMid.maximumHealth(0), 3000)
        XCTAssertEqual(nonnaVsMid.fighters[1].health, 2400)
        XCTAssertEqual(nonnaVsMid.maximumHealth(1), 2400)

        let shogunVsInq = DuelGame(hero: .wuYong, opponentHero: .gale, ruleset: .shadowArena)
        XCTAssertEqual(shogunVsInq.fighters[0].health, 2800)
        XCTAssertEqual(shogunVsInq.fighters[1].health, 2700)
    }

    func testNeutralStandingAutomaticallyBlocksFrontalStrikesWithChipDamage() {
        var game = closeArena(.wuYong, opponent: .ember)
        let startHP = game.fighters[1].health
        // Opponent sends .neutral (standing completely still — NO manual guard button!)
        game.step(.init(weaponCommand: .weapon), opponent: .neutral)
        var sawBlock = false
        var chipDealt = 0
        for _ in 0..<40 {
            game.step(.neutral, opponent: .neutral)
            if game.events.contains(.blocked(defender: 1)) { sawBlock = true }
            for e in game.events {
                if case .chipDamage(attacker: 0, let dmg) = e { chipDealt += dmg }
            }
        }
        XCTAssertTrue(sawBlock, "Standing still (.neutral) must automatically block frontal attacks in Shadow Arena")
        XCTAssertGreaterThan(chipDealt, 0, "Blocked attacks in Shadow Arena must deal authentic chip damage")
        XCTAssertEqual(game.fighters[1].health, startHP - chipDealt)
        XCTAssertEqual(game.landedHits[0], 0, "Blocked strike counts as chip, not clean unblocked hit")
    }

    func testBackWalkMaintainsAutoBlockWhileMovingBackwardAndForwardWalkOpensGuard() {
        var game = closeArena(.wuYong, opponent: .ember)
        let xBeforeBack = game.fighters[1].x
        // Opponent walks backward (+1 since facing == -1) while taking attack
        game.step(.init(weaponCommand: .weapon), opponent: .init(move: 1))
        var blocked = false
        for _ in 0..<25 {
            game.step(.neutral, opponent: .init(move: 1))
            if game.events.contains(.blocked(defender: 1)) { blocked = true }
        }
        XCTAssertTrue(blocked, "Walking backward must preserve auto-block")
        XCTAssertGreaterThan(game.fighters[1].x, xBeforeBack, "Defensive back-walk must still move backward")

        // Walking forward drops auto-block and takes full unblocked hit!
        var openGame = closeArena(.wuYong, opponent: .ember)
        let openStartHP = openGame.fighters[1].health
        openGame.step(.init(weaponCommand: .weapon), opponent: .init(move: -1))
        var fullHit = 0
        for _ in 0..<30 {
            openGame.step(.neutral, opponent: .init(move: -1))
            for e in openGame.events {
                if case .hit(attacker: 0, let dmg) = e { fullHit += dmg }
            }
        }
        XCTAssertGreaterThan(fullHit, 100, "Walking forward must drop auto-block and take full unblocked damage")
        XCTAssertEqual(openGame.fighters[1].health, openStartHP - fullHit)
    }

    func testCloseRangeForwardAndBackThrowBypassAutoBlockAndBackThrowSwitchesSides() {
        // Bring fighters into close throw range (<= 860mm)
        var fwd = DuelGame(hero: .liu, opponentHero: .ember, ruleset: .shadowArena)
        for _ in 0..<35 { fwd.step(.init(move: 1), opponent: .init(move: -1)) }
        XCTAssertLessThanOrEqual(abs(fwd.fighters[1].x - fwd.fighters[0].x), DuelGame.throwMaxDistance)
        let hpBefore = fwd.fighters[1].health
        // Opponent stands completely still (auto-blocking!) — forward + weapon executes Throw!
        fwd.step(.init(move: 1, weaponCommand: .weaponForward), opponent: .neutral)
        var sawForwardThrow = false
        for _ in 0..<35 {
            fwd.step(.neutral, opponent: .neutral)
            if fwd.events.contains(where: { if case .throwHit(attacker: 0, _, backThrow: false) = $0 { return true }; return false }) {
                sawForwardThrow = true
            }
        }
        XCTAssertTrue(sawForwardThrow, "Close forward+weapon must execute throw bypassing passive auto-block")
        XCTAssertLessThan(fwd.fighters[1].health, hpBefore - 200)
        XCTAssertGreaterThan(fwd.fighters[1].knockdown, 0)

        // Back throw switches sides!
        var back = DuelGame(hero: .wuYong, opponentHero: .gale, ruleset: .shadowArena)
        for _ in 0..<35 { back.step(.init(move: 1), opponent: .init(move: -1)) }
        let attXBefore = back.fighters[0].x
        back.step(.init(move: -1, weaponCommand: .weaponBack), opponent: .neutral)
        var sawBackThrow = false
        for _ in 0..<35 {
            back.step(.neutral, opponent: .neutral)
            if back.events.contains(where: { if case .throwHit(attacker: 0, _, backThrow: true) = $0 { return true }; return false }) {
                sawBackThrow = true
            }
        }
        XCTAssertTrue(sawBackThrow, "Close back+weapon must execute over-the-shoulder back throw")
        XCTAssertLessThan(back.fighters[1].x, attXBefore, "Back throw must toss opponent behind the attacker")
    }

    func testHighWeaponUpTriggersHeadHitBonusAndLaunch() {
        var game = closeArena(.gale, opponent: .ember)
        // Opponent walks forward so hit lands clean (not auto-blocked)
        game.step(.init(weaponCommand: .weaponUp), opponent: .init(move: -1))
        var sawHeadHit = false
        var launched = false
        for _ in 0..<35 {
            game.step(.neutral, opponent: .init(move: -1))
            if game.events.contains(where: { if case .headHit(attacker: 0, _) = $0 { return true }; return false }) {
                sawHeadHit = true
            }
            if game.fighters[1].y > 0 { launched = true }
        }
        XCTAssertTrue(sawHeadHit, "weaponUp striking standing opponent must trigger Head Hit (+25%)")
        XCTAssertTrue(launched, "weaponUp should lift target cleanly")
    }

    func testDuelWeaponInputDrivesAllFourHeroesIncludingAutoBlockAndDirectionalSkills() {
        // Verify original DuelWeaponInput (joystick + 4 buttons) drives Shogun Retinue (.ranged),
        // directional kicks (.kickForward = Ruthless Advance), heavy hold charge, and combo chaining!
        var input = DuelWeaponInput()
        var game = closeArena(.wuYong, opponent: .ember)

        // Hold forward + kick -> Ruthless Advance armored kick!
        input.direction(x: 1, y: 0)
        input.press(.kick)
        let kickStep = input.consume(facing: game.fighters[0].facing, airborne: false)
        XCTAssertEqual(kickStep.weaponCommand, .kickForward)
        game.step(kickStep, opponent: .init(move: -1))
        XCTAssertEqual(game.fighters[0].attack?.move, .kickForward)
        input.release(.kick)
        input.direction(x: 0, y: 0)

        // Press Ranged while attacking -> Shogun async Retinue strike!
        input.press(.ranged)
        let rangedStep = input.consume(facing: game.fighters[0].facing, airborne: false)
        XCTAssertEqual(rangedStep.weaponCommand, .ranged)
        game.step(rangedStep, opponent: .init(move: -1))
        XCTAssertEqual(game.shogunState(0)?.companionPhase, .windup)
        input.release(.ranged)

        // Verify Nonna Owl launch & recall through .ranged
        var nonnaGame = DuelGame(hero: .liu, opponentHero: .ember, ruleset: .shadowArena)
        nonnaGame.step(.init(weaponCommand: .ranged), opponent: .init(move: -1))
        XCTAssertEqual(nonnaGame.nonnaState(0)?.owlPhase, .outbound)
        for _ in 0..<20 { nonnaGame.step(.neutral, opponent: .init(move: -1)) }
        if nonnaGame.nonnaState(0)?.owlPhase == .latched || nonnaGame.nonnaState(0)?.owlPhase == .outbound {
            nonnaGame.step(.init(weaponCommand: .ranged), opponent: .neutral)
            XCTAssertEqual(nonnaGame.nonnaState(0)?.owlPhase, .returning)
        }

        // Verify Inquisitor Salvation pillar via .ranged
        var inqGame = DuelGame(hero: .gale, opponentHero: .ember, ruleset: .shadowArena)
        inqGame.step(.init(weaponCommand: .ranged), opponent: .init(move: -1))
        XCTAssertEqual(inqGame.fighters[0].attack?.move, .skill1)

        // Verify Midnight Shadow Shift via .ranged
        var midGame = DuelGame(hero: .ember, opponentHero: .liu, ruleset: .shadowArena)
        midGame.step(.init(weaponCommand: .ranged), opponent: .neutral)
        for _ in 0..<45 { midGame.step(.neutral, opponent: .neutral) }
        XCTAssertTrue(midGame.midnightState(0)?.isPhasedOut == true)
    }

    func testShadowArenaSeededReplayIsBitwiseDeterministic() throws {
        for hero in DuelGame.Hero.allCases {
            var a = DuelGame(hero: hero, difficulty: .challenging, seed: 4242, ruleset: .shadowArena)
            var b = a
            let commands: [DuelWeaponCommand?] = [nil, .weapon, .weaponForward, .weaponUp, .weaponDown, .kick, .ranged, .shadow]
            for tick in 0..<400 {
                let cmd = tick % 19 == 0 ? commands[(tick / 19) % commands.count] : nil
                let inp = DuelGame.Input(move: tick % 80 < 45 ? 1 : (tick % 80 < 65 ? 0 : -1), weaponCommand: cmd)
                a.step(inp); b.step(inp)
                XCTAssertEqual(try DuelReplayStateEncoding.encode(a), try DuelReplayStateEncoding.encode(b))
            }
        }
    }
}
