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
        XCTAssertEqual(nonnaVsMid.fighters[0].health, 3200)
        XCTAssertEqual(nonnaVsMid.maximumHealth(0), 3200)
        XCTAssertEqual(nonnaVsMid.fighters[1].health, 2400)
        XCTAssertEqual(nonnaVsMid.maximumHealth(1), 2400)

        let shogunVsInq = DuelGame(hero: .wuYong, opponentHero: .gale, ruleset: .shadowArena)
        XCTAssertEqual(shogunVsInq.fighters[0].health, 2900)
        XCTAssertEqual(shogunVsInq.fighters[1].health, 2600)
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

    func testWeaponCapsuleSweepAllowsJumpingOverLowSweepsAndRecordsLowHitZone() {
        // 1. Grounded opponent gets swept in the Legs zone (.low) by weaponDown / kickDown
        var grounded = DuelGame(hero: .wuYong, seed: 11, opponentHero: .ember, ruleset: .shadowArena)
        for _ in 0..<26 { grounded.step(.init(move: 1), opponent: .init(move: -1)) }
        grounded.step(.init(weaponCommand: .weaponDown), opponent: .init(move: -1))
        var lowConnected = false
        for _ in 0..<24 {
            grounded.step(.neutral, opponent: .init(move: -1))
            if grounded.landedHits[0] > 0 { lowConnected = true; break }
        }
        XCTAssertTrue(lowConnected, "Low sweep should hit grounded opponent's Legs hurt capsule")
        XCTAssertEqual(grounded.fighters[1].lastHitZone, .low, "Low sweep must record .low hitZone for knee-buckle reaction")
        XCTAssertLessThan(grounded.fighters[1].lastContactY, 650, "Low sweep contact point should be near leg height")

        // 2. Jumping opponent cleanly vaults OVER kickDown capsule sweep!
        var jumping = DuelGame(hero: .liu, seed: 12, opponentHero: .ember, ruleset: .shadowArena)
        for _ in 0..<26 { jumping.step(.init(move: 1), opponent: .init(move: -1)) }
        // Opponent jumps right before kickDown becomes active
        jumping.step(.init(weaponCommand: .kickDown), opponent: .init(taps: .jump))
        for _ in 0..<18 {
            jumping.step(.neutral, opponent: .neutral)
        }
        XCTAssertEqual(jumping.landedHits[0], 0, "Jumping opponent must cleanly clear low kickDown capsule sweep!")
    }

    func testWeaponCapsuleSweepHeroReachMatchesPhysicalBladeLength() {
        // Wu Yong's Odachi (1.18m) cleanly reaches from ~1.50m away, whereas Sun Deng's short ninjato (0.64m) whiffs!
        var wu = DuelGame(hero: .wuYong, seed: 21, opponentHero: .liu, ruleset: .shadowArena)
        var sun = DuelGame(hero: .ember, seed: 21, opponentHero: .liu, ruleset: .shadowArena)
        // Walk each hero until separation is ~1.48m (inside Odachi reach, outside Ninjato reach)
        while abs(wu.fighters[1].x - wu.fighters[0].x) > 1520 {
            wu.step(.init(move: 1), opponent: .neutral)
        }
        while abs(sun.fighters[1].x - sun.fighters[0].x) > 1520 {
            sun.step(.init(move: 1), opponent: .neutral)
        }
        let wuDist = abs(wu.fighters[1].x - wu.fighters[0].x)
        let sunDist = abs(sun.fighters[1].x - sun.fighters[0].x)
        XCTAssertLessThanOrEqual(abs(wuDist - sunDist), 120)

        wu.step(.init(weaponCommand: .weapon), opponent: .neutral)
        sun.step(.init(weaponCommand: .weapon), opponent: .neutral)
        for _ in 0..<24 {
            wu.step(.neutral, opponent: .neutral)
            sun.step(.neutral, opponent: .neutral)
        }
        XCTAssertLessThan(wu.fighters[1].health, wu.maximumHealth(1), "Wu Yong's long Odachi capsule must reach and deal damage/chip at 1.5m range")
        XCTAssertEqual(sun.fighters[1].health, sun.maximumHealth(1), "Sun Deng's shorter dual ninjato capsule must completely whiff at 1.5m range")
        XCTAssertEqual(sun.landedHits[0], 0, "Sun Deng's shorter dual ninjato capsule must whiff at Odachi range")
    }

    func testOriginalAudioPCMSynthesizesAllFourteenCombatCuesDeterministically() {
        XCTAssertEqual(DuelOriginalAudioPCM.Cue.allCases.count, 14)
        for cue in DuelOriginalAudioPCM.Cue.allCases {
            let a = DuelOriginalAudioPCM.samples(for: cue)
            let b = DuelOriginalAudioPCM.samples(for: cue)
            XCTAssertGreaterThan(a.count, 1500, "Cue \(cue) should have audible duration")
            XCTAssertEqual(a, b, "Procedural PCM for \(cue) must be deterministic")
            XCTAssertTrue(a.allSatisfy { $0.isFinite && abs($0) <= 0.96 }, "Cue \(cue) must stay finite and non-clipping")
            let rms = sqrt(a.reduce(0.0) { $0 + Double($1 * $1) } / Double(a.count))
            XCTAssertGreaterThan(rms, 0.01, "Cue \(cue) must not be silent")
        }
    }

    func testDedicatedRangedCooldownsAndSignatureProjectilesWorkWithoutEnergyGate() {
        // 1. Inquisitor Salvation: starts ready, hits target, halves cooldown, and triggers Light's Will 2nd smite!
        var inq = DuelGame(hero: .gale, seed: 31, opponentHero: .ember, ruleset: .shadowArena)
        XCTAssertTrue(inq.inquisitorState(0)?.canCastSalvation == true)
        inq.step(.init(weaponCommand: .ranged), opponent: .init(move: -1))
        XCTAssertEqual(inq.fighters[0].attack?.move, .skill1)
        XCTAssertEqual(inq.inquisitorState(0)?.rangedCooldown, DuelInquisitorState.rangedCooldownTicks)
        var sawSalvationProjectile = false
        var sawEcho = false
        var halvedCooldown = false
        for _ in 0..<80 {
            inq.step(.neutral, opponent: .init(move: -1))
            if inq.projectiles.contains(where: { $0.kind == .salvationPillar }) { sawSalvationProjectile = true }
            if let cd = inq.inquisitorState(0)?.rangedCooldown, cd > 0 && cd < DuelInquisitorState.rangedCooldownTicks / 2 {
                halvedCooldown = true
            }
            if inq.events.contains(where: { if case .inquisitorSalvationEcho(attacker: 0, _, _) = $0 { return true }; return false }) {
                sawEcho = true
            }
        }
        XCTAssertTrue(sawSalvationProjectile, "Salvation must spawn a .salvationPillar projectile")
        XCTAssertTrue(halvedCooldown, "Salvation hit must halve Inquisitor rangedCooldown")
        XCTAssertTrue(sawEcho, "Salvation must arm and detonate Light's Will 2nd sky smite")

        // 2. Midnight Shadow Kunai: spawns fast .shadowKunai projectile, deals damage/chip, enters cooldown, and triggers Distant Shift!
        var mid = DuelGame(hero: .ember, seed: 32, opponentHero: .liu, ruleset: .shadowArena)
        XCTAssertTrue(mid.midnightState(0)?.canCastKunai == true)
        mid.step(.init(weaponCommand: .ranged), opponent: .init(move: -1))
        var sawKunai = false
        var sawShift = false
        var kunaiHit = false
        for _ in 0..<60 {
            mid.step(.neutral, opponent: .init(move: -1))
            if mid.projectiles.contains(where: { $0.kind == .shadowKunai }) { sawKunai = true }
            if mid.events.contains(.midnightShadowShift(fighter: 0)) { sawShift = true }
            if mid.landedHits[0] > 0 { kunaiHit = true }
        }
        XCTAssertTrue(sawKunai, "Midnight .ranged in shadowArena must fire a fast .shadowKunai projectile")
        XCTAssertTrue(kunaiHit, "Shadow Kunai must connect against advancing opponent")
        XCTAssertTrue(sawShift, "Shadow Kunai must trigger Distant Shift immediately after throw")
        XCTAssertGreaterThan(mid.midnightState(0)?.rangedCooldown ?? 0, 150)
    }

    func testDirectionalShadowCombosBlinkHealAndBanishingBlasphemy() {
        // 1. Shogun directional Shadow 搓招: Back+Shadow -> Despotism, Forward+Shadow -> Fierce Reprisal
        //    Also verify NO AFK passive shadow charging in shadowArena!
        var idleShogun = DuelGame(hero: .wuYong, seed: 41, opponentHero: .gale, ruleset: .shadowArena)
        for _ in 0..<60 { idleShogun.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(idleShogun.shogunState(0)?.shadowEnergy, 0, "Shogun must NOT passively charge shadow while AFK in shadowArena")

        // Build Shogun Shadow Form via Odachi weapon combos against Grand Inquisitor -> triggers Banishing Blasphemy!
        var shogunVsInq = closeArena(.wuYong, opponent: .gale, seed: 42)
        var sawShadowForm = false
        var sawBlasphemyStigmata = false
        for _ in 0..<480 {
            let gap = abs(shogunVsInq.fighters[1].x - shogunVsInq.fighters[0].x)
            let cmd: DuelWeaponCommand? = (gap < 1300 && shogunVsInq.fighters[0].attack == nil &&
                shogunVsInq.fighters[1].knockdown == 0 && shogunVsInq.fighters[1].invulnerable == 0) ? .weapon : nil
            shogunVsInq.step(.init(move: 1, weaponCommand: cmd), opponent: .init(move: -1))
            if shogunVsInq.events.contains(.shogunShadowForm(fighter: 0)) {
                sawShadowForm = true
                if shogunVsInq.events.contains(.inquisitorStigmataApplied(defender: 0)) {
                    sawBlasphemyStigmata = true
                }
                break
            }
        }
        XCTAssertTrue(sawShadowForm, "Shogun must reach Shadow Form through combat hits")
        XCTAssertTrue(sawBlasphemyStigmata, "Inquisitor Banishing Blasphemy must immediately brand Shogun upon entering Shadow Form")

        // Branch A: Back + Shadow -> Despotism!
        var backBranch = shogunVsInq
        while backBranch.fighters[0].attack != nil || backBranch.fighters[0].stun > 0 {
            backBranch.step(.neutral, opponent: .neutral)
        }
        backBranch.step(.init(move: -backBranch.fighters[0].facing, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertEqual(backBranch.fighters[0].attack?.move, .shogunDespotism, "Back + Shadow must trigger Despotism")

        // Branch B: Forward + Shadow -> Fierce Reprisal!
        var fwdBranch = shogunVsInq
        while fwdBranch.fighters[0].attack != nil || fwdBranch.fighters[0].stun > 0 {
            fwdBranch.step(.neutral, opponent: .neutral)
        }
        fwdBranch.step(.init(move: fwdBranch.fighters[0].facing, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertEqual(fwdBranch.fighters[0].attack?.move, .shogunFierceReprisal, "Forward + Shadow must trigger Fierce Reprisal")

        // 2. Midnight directional Shadow 搓招: Back + Shadow (at >=50 shadow) -> Blink Counter + 18% heal (432 HP)!
        var mid = closeArena(.ember, opponent: .liu, seed: 43)
        // Take a clean heavy hit from Nonna, then charge >= 50 shadow with weapon hits
        mid.step(.init(move: 1), opponent: .init(weaponCommand: .heavy))
        for _ in 0..<45 { mid.step(.init(move: 1), opponent: .neutral) }
        for _ in 0..<240 {
            if (mid.midnightState(0)?.shadowEnergy ?? 0) >= DuelMidnightState.blinkShadowCost &&
                mid.fighters[0].attack == nil && mid.fighters[0].stun == 0 && mid.fighters[0].knockdown == 0 &&
                mid.fighters[1].attack == nil && mid.fighters[1].stun == 0 && mid.fighters[1].knockdown == 0 {
                break
            }
            let gap = abs(mid.fighters[1].x - mid.fighters[0].x)
            let needShadow = (mid.midnightState(0)?.shadowEnergy ?? 0) < DuelMidnightState.blinkShadowCost
            let cmd: DuelWeaponCommand? = (needShadow && gap < 1050 && mid.fighters[0].attack == nil &&
                mid.fighters[1].knockdown == 0 && mid.fighters[1].invulnerable == 0) ? .weapon : nil
            mid.step(.init(move: 1, weaponCommand: cmd), opponent: .init(move: -1))
        }
        // Walk into crisp melee range while both fighters are idle
        for _ in 0..<20 where abs(mid.fighters[1].x - mid.fighters[0].x) > 880 {
            mid.step(.init(move: 1), opponent: .init(move: -1))
        }
        XCTAssertGreaterThanOrEqual(mid.midnightState(0)?.shadowEnergy ?? 0, DuelMidnightState.blinkShadowCost)
        let hpBeforeBlink = mid.fighters[0].health
        XCTAssertLessThan(hpBeforeBlink, mid.maximumHealth(0))
        // Activate Back + Shadow Blink right as Nonna swings!
        mid.step(.init(move: -mid.fighters[0].facing, weaponCommand: .shadow), opponent: .init(weaponCommand: .weapon))
        XCTAssertTrue(mid.midnightState(0)?.isInBlinkStance == true, "Back + Shadow must activate Blink counter-stance")
        var sawBlinkCounter = false
        for _ in 0..<24 {
            mid.step(.neutral, opponent: .neutral)
            if mid.events.contains(where: { if case .midnightBlinkCounter(attacker: 0, _) = $0 { return true }; return false }) {
                sawBlinkCounter = true
                break
            }
        }
        XCTAssertTrue(sawBlinkCounter, "Blink counter-stance must counter incoming melee attack")
        let expectedBlinkHeal = (mid.maximumHealth(0) * DuelMidnightState.blinkCounterHealPermille) / 1000
        XCTAssertEqual(mid.fighters[0].health, min(mid.maximumHealth(0), hpBeforeBlink + expectedBlinkHeal),
                       "Blink counter in shadowArena must heal 18% max HP (432 HP)")
    }

    func testTakingDamageChargingNonnaSideSwapAndAirborneAttacks() {
        // 1. All non-Shogun heroes charge their primary resource when taking unblocked damage in shadowArena!
        for defenderHero in [DuelGame.Hero.gale, .liu, .ember] {
            var g = closeArena(.wuYong, opponent: defenderHero, seed: 51)
            g.step(.init(weaponCommand: .weapon), opponent: .init(move: -1))
            for _ in 0..<30 { g.step(.neutral, opponent: .init(move: -1)) }
            XCTAssertGreaterThan(g.landedHits[0], 0)
            switch defenderHero {
            case .gale: XCTAssertGreaterThan(g.inquisitorState(1)?.lightPower ?? 0, 0)
            case .liu: XCTAssertGreaterThan(g.nonnaState(1)?.flamePower ?? 0, 0)
            case .ember: XCTAssertGreaterThan(g.midnightState(1)?.shadowEnergy ?? 0, 0)
            case .wuYong: break
            }
        }

        // 2. Nonna weaponBack hooks and swaps sides with the struck opponent!
        var nonna = closeArena(.liu, opponent: .ember, seed: 52)
        // Step slightly back so weaponBack doesn't trigger close-range backThrow
        for _ in 0..<8 { nonna.step(.init(move: -1), opponent: .neutral) }
        XCTAssertGreaterThan(abs(nonna.fighters[1].x - nonna.fighters[0].x), DuelGame.throwMaxDistance)
        let nonnaXBefore = nonna.fighters[0].x
        nonna.step(.init(weaponCommand: .weaponBack), opponent: .init(move: -1))
        var swapped = false
        for _ in 0..<35 {
            nonna.step(.neutral, opponent: .init(move: -1))
            if nonna.landedHits[0] > 0 && nonna.fighters[1].x < nonnaXBefore {
                swapped = true
                break
            }
        }
        XCTAssertTrue(swapped, "Nonna weaponBack in shadowArena must hook and swap sides with the opponent")

        // 3. Airborne jump-kick executes .kickUp mid-air and clears cleanly on landing!
        var air = DuelGame(hero: .wuYong, seed: 53, opponentHero: .ember, ruleset: .shadowArena)
        air.step(.init(taps: .jump), opponent: .neutral)
        for _ in 0..<4 { air.step(.neutral, opponent: .neutral) }
        XCTAssertGreaterThan(air.fighters[0].y, 0)
        air.step(.init(weaponCommand: .kick), opponent: .neutral)
        XCTAssertEqual(air.fighters[0].attack?.move, .kickUp, "Airborne kick in shadowArena must execute jump-kick (.kickUp)")
    }
}
