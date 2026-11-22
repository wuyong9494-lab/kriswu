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

    func testOriginalAudioPCMSynthesizesAllCombatAndHeroWeaponCuesDeterministically() {
        XCTAssertEqual(DuelOriginalAudioPCM.Cue.allCases.count, 19)
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
        // 1. Inquisitor Salvation: starts ready, telegraphs targeted sky pillar, hits target, halves cooldown, and triggers Light's Will 2nd smite!
        var inq = DuelGame(hero: .gale, seed: 31, opponentHero: .ember, ruleset: .shadowArena)
        XCTAssertTrue(inq.inquisitorState(0)?.canCastSalvation == true)
        inq.step(.init(weaponCommand: .ranged), opponent: .init(move: -1))
        XCTAssertEqual(inq.fighters[0].attack?.move, .skill1)
        XCTAssertEqual(inq.inquisitorState(0)?.rangedCooldown, DuelInquisitorState.rangedCooldownTicks)
        var sawSalvationTelegraph = false
        var sawSalvationStrike = false
        var sawEcho = false
        var halvedCooldown = false
        for _ in 0..<80 {
            inq.step(.neutral, opponent: .init(move: -1))
            if (inq.inquisitorState(0)?.salvationCastTicks ?? 0) > 0 { sawSalvationTelegraph = true }
            if inq.events.contains(where: { if case .inquisitorSalvationStrike(attacker: 0, _, let dmg) = $0, dmg > 0 { return true }; return false }) {
                sawSalvationStrike = true
            }
            if let cd = inq.inquisitorState(0)?.rangedCooldown, cd > 0 && cd < DuelInquisitorState.rangedCooldownTicks / 2 {
                halvedCooldown = true
            }
            if inq.events.contains(where: { if case .inquisitorSalvationEcho(attacker: 0, _, _) = $0 { return true }; return false }) {
                sawEcho = true
            }
        }
        XCTAssertTrue(sawSalvationTelegraph, "Salvation must arm its targeted ground telegraph before striking")
        XCTAssertTrue(sawSalvationStrike, "Salvation must detonate a targeted .inquisitorSalvationStrike sky pillar")
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

    func testWakeupLowKickAndCombatRecoveryRollFollowSF4Rules() {
        // 1. Standing forward roll (Down+Forward) travels forward with startup invulnerability,
        //    crosses through a close opponent, and does NOT emit a whiff event or Midnight Shadow Shift.
        var rollGame = closeArena(.ember, opponent: .wuYong, seed: 61)
        let startX = rollGame.fighters[0].x
        let foeX = rollGame.fighters[1].x
        rollGame.step(.init(move: 1, vertical: -1), opponent: .neutral)
        XCTAssertEqual(rollGame.fighters[0].attack?.move, .rollForward, "Down+Forward must trigger SF4 forward combat roll")
        XCTAssertGreaterThan(rollGame.fighters[0].invulnerable, 0, "Combat roll must grant early invulnerability frames")
        var sawWhiff = false
        for _ in 0..<24 {
            rollGame.step(.neutral, opponent: .neutral)
            if rollGame.events.contains(where: { if case .whiff(attacker: 0) = $0 { return true }; return false }) {
                sawWhiff = true
            }
        }
        XCTAssertFalse(sawWhiff, "Combat roll must never emit a missed-attack whiff event")
        XCTAssertGreaterThan(rollGame.fighters[0].x, foeX, "Forward roll in close range must cross up past the opponent")
        XCTAssertGreaterThan(rollGame.fighters[0].x - startX, 1200, "Forward roll must travel cleanly across the floor")

        // 2. Wake-up Low Kick from knockdown cancels knockdown, grants startup invulnerability, and hits low!
        var wk = closeArena(.wuYong, opponent: .liu, seed: 62)
        // Have Liu knock Wu Yong down with low sweep kick (.kickDown)
        wk.step(.init(move: 1), opponent: .init(weaponCommand: .kickDown))
        var knockedDown = false
        for _ in 0..<40 {
            wk.step(.init(move: 1), opponent: .neutral)
            if wk.fighters[0].knockdown > 0 && wk.fighters[0].knockdown <= 22 {
                knockedDown = true
                break
            }
        }
        XCTAssertTrue(knockedDown, "Liu's kickDown should knock Wu Yong down into the wakeup window")
        // Walk Liu close to pressure, while Wu Yong triggers Wake-up Low Kick!
        wk.step(.init(weaponCommand: .kick), opponent: .init(move: -1))
        XCTAssertEqual(wk.fighters[0].knockdown, 0, "Wake-up Kick must cancel remaining knockdown")
        XCTAssertEqual(wk.fighters[0].attack?.move, .wakeupKick, "Kick during knockdown wakeup window must start .wakeupKick")
        XCTAssertGreaterThanOrEqual(wk.fighters[0].invulnerable, 7, "Wake-up Kick must grant startup invulnerability")
        let foeHPBefore = wk.fighters[1].health
        for _ in 0..<25 {
            wk.step(.neutral, opponent: .init(move: -1))
        }
        XCTAssertLessThan(wk.fighters[1].health, foeHPBefore, "Wake-up Low Kick must connect against an advancing opponent")
        XCTAssertEqual(wk.fighters[1].lastHitZone, .low, "Wake-up Low Kick must register as a low sweep hit")
    }

    func testVelocitySlidingKnockbackAndCornerWallSplatBounceIntoJuggle() {
        // 1. Velocity-based sliding knockback: contact sets velocityX and slides smoothly AFTER hitStop!
        var slide = closeArena(.wuYong, opponent: .ember, seed: 71)
        slide.step(.init(weaponCommand: .heavy), opponent: .init(move: -1))
        var hitTickX = 0
        var velocityAtHit = 0
        var sawHit = false
        for _ in 0..<40 {
            slide.step(.neutral, opponent: .init(move: -1))
            if slide.landedHits[0] > 0 && !sawHit {
                sawHit = true
                hitTickX = slide.fighters[1].x
                velocityAtHit = slide.fighters[1].velocityX
                XCTAssertGreaterThan(slide.hitStop, 0, "Heavy hit must trigger hit-stop freeze frames")
                XCTAssertGreaterThan(velocityAtHit, 40, "Shadow Arena hit must impart positive sliding velocityX")
                break
            }
        }
        XCTAssertTrue(sawHit)
        // During hit-stop, victim stays locked in place for recoil shiver (no instant teleport!)
        while slide.hitStop > 0 {
            slide.step(.neutral, opponent: .neutral)
            XCTAssertEqual(slide.fighters[1].x, hitTickX, "Victim must not slide before hitStop releases")
        }
        // After hit-stop releases, victim smoothly slides across multiple frames and decelerates to 0!
        var slidePositions: [Int] = [hitTickX]
        for _ in 0..<14 {
            slide.step(.neutral, opponent: .neutral)
            slidePositions.append(slide.fighters[1].x)
        }
        XCTAssertGreaterThan(slidePositions.last ?? 0, hitTickX + 180, "Victim must smoothly slide backward across floor after hitStop")
        XCTAssertGreaterThan(slidePositions[2], hitTickX, "Slide begins immediately after hitStop ends")
        XCTAssertLessThan(slidePositions[2], slidePositions.last ?? 0, "Slide must span multiple ticks, not teleport in 1 tick")

        // 2. Corner Wall-Splat: slam opponent near rightWall -> emits .wallSplat, bounces inward & launches for juggle!
        var wall = DuelGame(hero: .wuYong, seed: 72, opponentHero: .ember, ruleset: .shadowArena)
        // Walk both fighters to the right corner!
        for _ in 0..<55 {
            wall.step(.init(move: 1), opponent: .init(move: 1))
        }
        XCTAssertGreaterThan(wall.fighters[1].x, DuelGame.rightWall - 500)
        // Step into melee range and land an unblocked heavy Odachi strike into the corner!
        for _ in 0..<20 where abs(wall.fighters[1].x - wall.fighters[0].x) > 1250 {
            wall.step(.init(move: 1), opponent: .neutral)
        }
        wall.step(.init(weaponCommand: .heavy), opponent: .init(move: -1))
        var sawWallSplat = false
        var bouncedInward = false
        var launchedOnSplat = false
        for _ in 0..<45 {
            wall.step(.neutral, opponent: .init(move: -1))
            if wall.events.contains(.wallSplat(defender: 1)) {
                sawWallSplat = true
                bouncedInward = wall.fighters[1].velocityX < 0
                launchedOnSplat = wall.fighters[1].y > 0 && wall.fighters[1].velocityY >= 100
                break
            }
        }
        XCTAssertTrue(sawWallSplat, "High-velocity corner knockback must trigger SF4 Wall-Splat")
        XCTAssertTrue(bouncedInward, "Wall-Splat must bounce defender inward off the wall")
        XCTAssertTrue(launchedOnSplat, "Wall-Splat must launch defender into juggle window")
    }

    func testShogunChargedHeavyAndDoubleTapDashThroughDuelWeaponInput() {
        // 1. Double-tap Forward Dash -> cancelable into attack; Double-tap Back-Hop -> grants invulnerability!
        var input = DuelWeaponInput()
        var game = DuelGame(hero: .wuYong, seed: 81, opponentHero: .liu, ruleset: .shadowArena)
        let xStart = game.fighters[0].x
        input.direction(x: 1, y: 0)
        _ = input.consume(facing: 1, airborne: false)
        input.direction(x: 0, y: 0)
        _ = input.consume(facing: 1, airborne: false)
        input.direction(x: 1, y: 0)
        let dashStep = input.consume(facing: 1, airborne: false)
        XCTAssertEqual(dashStep.dashDirection, 1, "Double-tap forward must emit dashDirection = +1")
        game.step(dashStep, opponent: .neutral)
        XCTAssertEqual(game.fighters[0].attack?.move, .dashForward)
        for _ in 0..<5 { game.step(.neutral, opponent: .neutral) }
        XCTAssertGreaterThan(game.fighters[0].x - xStart, 700, "Forward dash must cover burst distance")
        // Cancel dashForward at age >= 4 directly into jab!
        game.step(.init(weaponCommand: .weapon), opponent: .neutral)
        XCTAssertEqual(game.fighters[0].attack?.move, .jab, "dashForward must be attack-cancelable after age 4")
        for _ in 0..<30 { game.step(.neutral, opponent: .neutral) }

        // Double-tap Back-Hop
        input.cancelAll()
        input.direction(x: -1, y: 0)
        _ = input.consume(facing: 1, airborne: false)
        input.direction(x: 0, y: 0)
        _ = input.consume(facing: 1, airborne: false)
        input.direction(x: -1, y: 0)
        let backDashStep = input.consume(facing: 1, airborne: false)
        XCTAssertEqual(backDashStep.dashDirection, -1, "Double-tap back must emit dashDirection = -1")
        game.step(backDashStep, opponent: .neutral)
        XCTAssertEqual(game.fighters[0].attack?.move, .dashBack)
        XCTAssertGreaterThan(game.fighters[0].invulnerable, 0, "Back-hop must grant startup invulnerability frames")

        // 2. Shogun Charged Heavy through DuelWeaponInput.heavyHeld pass-through!
        var chargeInput = DuelWeaponInput()
        var chargeGame = closeArena(.wuYong, opponent: .ember, seed: 82)
        chargeInput.press(.weapon)
        var enteredCharge = false
        var peakChargeTicks = 0
        for _ in 0..<(DuelShogunState.heavyFullChargeTicks + 4) {
            let stepInput = chargeInput.consume(facing: chargeGame.fighters[0].facing, airborne: false)
            XCTAssertTrue(stepInput.heavyHeld, "Holding weapon button must keep heavyHeld == true")
            chargeGame.step(stepInput, opponent: .neutral)
            let ticks = chargeGame.shogunState(0)?.heavyChargeTicks ?? 0
            if ticks > 0 { enteredCharge = true; peakChargeTicks = max(peakChargeTicks, ticks) }
        }
        XCTAssertTrue(enteredCharge, "Holding weapon past longPressTicks must enter Shogun heavy charge stance")
        XCTAssertGreaterThanOrEqual(peakChargeTicks, DuelShogunState.heavyFullChargeTicks, "Shogun must reach full charge while heavyHeld stays true")
        chargeInput.release(.weapon)
        let releaseStep = chargeInput.consume(facing: chargeGame.fighters[0].facing, airborne: false)
        XCTAssertFalse(releaseStep.heavyHeld)
        chargeGame.step(releaseStep, opponent: .neutral)
        XCTAssertEqual(chargeGame.fighters[0].attack?.move, .heavy)
        XCTAssertGreaterThan(chargeGame.fighters[0].attack?.chargeTicks ?? 0, DuelWeaponInput.longPressTicks)
        var brokeGuard = false
        for _ in 0..<35 {
            chargeGame.step(.neutral, opponent: .neutral)
            if chargeGame.events.contains(.guardBreak(defender: 1)) { brokeGuard = true }
        }
        XCTAssertTrue(brokeGuard, "Fully charged Shogun Iaido Heavy must shatter standing auto-block")
    }

    func testCounterHitBladeClashJuggleAndMultiHitWeaponStrings() {
        // 1. Counter-Hit: interrupting opponent's slow heavy startup triggers .counterHit (+20% dmg)!
        var chGame = closeArena(.ember, opponent: .wuYong, seed: 91)
        chGame.step(.init(weaponCommand: .weapon), opponent: .init(weaponCommand: .heavy))
        var sawCounterHit = false
        for _ in 0..<25 {
            chGame.step(.neutral, opponent: .neutral)
            if chGame.events.contains(where: { if case .counterHit(attacker: 0, _) = $0 { return true }; return false }) {
                sawCounterHit = true
                break
            }
        }
        XCTAssertTrue(sawCounterHit, "Fast jab interrupting slow heavy startup must trigger .counterHit")

        // 2. Blade Clash: two overlapping active weapon arcs collide -> .bladeClash + mutual recoil + hitStop >= 10!
        var clashGame = closeArena(.wuYong, opponent: .wuYong, seed: 92)
        clashGame.step(.init(weaponCommand: .weapon), opponent: .init(weaponCommand: .weapon))
        var sawClash = false
        for _ in 0..<20 {
            clashGame.step(.neutral, opponent: .neutral)
            if clashGame.events.contains(where: { if case .bladeClash = $0 { return true }; return false }) {
                sawClash = true
                XCTAssertNil(clashGame.fighters[0].attack)
                XCTAssertNil(clashGame.fighters[1].attack)
                XCTAssertGreaterThanOrEqual(clashGame.hitStop, 10)
                XCTAssertLessThan(clashGame.fighters[0].velocityX, 0)
                XCTAssertGreaterThan(clashGame.fighters[1].velocityX, 0)
                break
            }
        }
        XCTAssertTrue(sawClash, "Simultaneous overlapping weapon swings must trigger .bladeClash")

        // 3. Multi-Hit Weapon String: step outside close-throw range so weaponForward runs the 3-hit flurry and lands 2+ hits!
        var multiGame = closeArena(.ember, opponent: .liu, seed: 93)
        for _ in 0..<6 { multiGame.step(.init(move: -1), opponent: .neutral) }
        XCTAssertGreaterThan(abs(multiGame.fighters[1].x - multiGame.fighters[0].x), DuelGame.throwMaxDistance)
        multiGame.step(.init(weaponCommand: .weaponForward), opponent: .init(move: -1))
        XCTAssertEqual(multiGame.fighters[0].attack?.move, .weaponForward)
        var maxHitsInOneMove = 0
        for _ in 0..<50 {
            multiGame.step(.neutral, opponent: .init(move: -1))
            maxHitsInOneMove = max(maxHitsInOneMove, multiGame.fighters[0].attack?.hitsLanded ?? 0)
        }
        XCTAssertGreaterThanOrEqual(maxHitsInOneMove, 2, "weaponForward multi-hit string must connect 2+ times within one clip")

        // 4. Airborne Juggle: launch with weaponUp, then follow up mid-air to increment juggleHits!
        var jugGame = closeArena(.wuYong, opponent: .ember, seed: 94)
        jugGame.step(.init(weaponCommand: .weaponUp), opponent: .init(move: -1))
        var launched = false
        for _ in 0..<30 {
            jugGame.step(.neutral, opponent: .init(move: -1))
            if jugGame.fighters[1].y > 0 && jugGame.fighters[1].knockdown == 0 {
                launched = true
                break
            }
        }
        XCTAssertTrue(launched, "weaponUp must launch opponent cleanly with knockdown == 0 for juggle")
        // Wait for Wu Yong's weaponUp to finish while opponent is still airborne, then strike mid-air!
        var maxJuggle = 0
        for _ in 0..<40 {
            let cmd: DuelWeaponCommand? = (jugGame.fighters[0].attack == nil && jugGame.fighters[1].y > 0) ? .weapon : nil
            jugGame.step(.init(move: 1, weaponCommand: cmd), opponent: .neutral)
            maxJuggle = max(maxJuggle, jugGame.fighters[1].juggleHits)
        }
        XCTAssertGreaterThanOrEqual(maxJuggle, 1, "Follow-up attack on launched airborne opponent must register a mid-air juggle")
    }

    func testInquisitorSoaringFormOfLightFourMovesAndKnockoutPenalty() {
        var game = closeArena(.gale, opponent: .liu, seed: 101)
        // Build Light Power to 100 through combat strikes!
        for _ in 0..<520 {
            if game.inquisitorState(0)?.canEnterFormOfLight == true &&
                game.fighters[0].attack == nil && game.fighters[0].stun == 0 &&
                game.fighters[1].attack == nil && game.fighters[1].knockdown == 0 {
                break
            }
            let gap = abs(game.fighters[1].x - game.fighters[0].x)
            let cmd: DuelWeaponCommand? = (gap < 1450 && game.fighters[0].attack == nil &&
                game.fighters[1].knockdown == 0 && game.fighters[1].invulnerable == 0) ? .weapon : nil
            game.step(.init(move: 1, weaponCommand: cmd), opponent: .init(move: -1))
        }
        XCTAssertTrue(game.inquisitorState(0)?.canEnterFormOfLight == true, "Inquisitor must reach 100 Light Power")
        game.step(.init(weaponCommand: .shadow), opponent: .neutral)
        XCTAssertTrue(game.inquisitorState(0)?.isInFormOfLight == true)

        // Verify all 4 directional soaring moves in Form of Light!
        var upBranch = game
        upBranch.step(.init(weaponCommand: .weaponUp), opponent: .neutral)
        XCTAssertEqual(upBranch.fighters[0].attack?.move, .inquisitorLightUp)

        var fwdBranch = game
        fwdBranch.step(.init(weaponCommand: .weaponForward), opponent: .neutral)
        XCTAssertEqual(fwdBranch.fighters[0].attack?.move, .inquisitorLightForward)

        var downBranch = game
        downBranch.step(.init(weaponCommand: .weaponDown), opponent: .neutral)
        XCTAssertEqual(downBranch.fighters[0].attack?.move, .inquisitorLightDown)

        var spinBranch = game
        spinBranch.step(.init(weaponCommand: .shadow), opponent: .neutral)
        XCTAssertEqual(spinBranch.fighters[0].attack?.move, .inquisitorLightSpin)

        // Verify taking an unblocked hit while soaring knocks Inquisitor out of Form of Light (-50% Light) & emits event!
        var knockBranch = game
        for _ in 0..<(DuelInquisitorState.entryInvulnerableTicks + 4) {
            let gap = abs(knockBranch.fighters[1].x - knockBranch.fighters[0].x)
            knockBranch.step(.init(move: 1), opponent: .init(move: gap > 1050 ? -1 : 0))
        }
        let lightBefore = knockBranch.inquisitorState(0)?.lightPower ?? 0
        XCTAssertGreaterThan(lightBefore, 50)
        knockBranch.step(.init(move: 1), opponent: .init(weaponCommand: .weapon))
        var sawBroken = false
        for _ in 0..<25 {
            knockBranch.step(.init(move: 1), opponent: .neutral)
            if knockBranch.events.contains(.inquisitorLightFormBroken(defender: 0)) {
                sawBroken = true
                break
            }
        }
        XCTAssertTrue(sawBroken, "Unblocked hit during Form of Light must emit .inquisitorLightFormBroken")
        XCTAssertFalse(knockBranch.inquisitorState(0)?.isInFormOfLight == true)
        XCTAssertLessThanOrEqual(knockBranch.inquisitorState(0)?.lightPower ?? 100, lightBefore / 2)
    }

    func testNonnaRunesOfAshHeartOfPackHealTrueShapeAndAncientFury() {
        // 1. Spirit Owl hit increments Runes of Ash & triggers Heart of the Pack 6% heal!
        var game = closeArena(.liu, opponent: .wuYong, seed: 111)
        // Take a clean hit first so healing is measurable, then wait until Nonna recovers!
        game.step(.init(move: 1), opponent: .init(weaponCommand: .heavy))
        for _ in 0..<100 {
            game.step(.init(move: 1), opponent: .neutral)
            if game.fighters[0].health < game.maximumHealth(0) &&
                game.fighters[0].knockdown == 0 && game.fighters[0].stun == 0 &&
                game.fighters[0].attack == nil {
                break
            }
        }
        let hpBeforeOwl = game.fighters[0].health
        XCTAssertLessThan(hpBeforeOwl, game.maximumHealth(0))
        game.step(.init(weaponCommand: .ranged), opponent: .init(move: -1))
        XCTAssertGreaterThanOrEqual(game.nonnaState(0)?.runesOfAsh ?? 0, 1, "Launching Spirit Owl must grant a Rune of Ash")
        var sawOwlHit = false
        for _ in 0..<30 {
            game.step(.neutral, opponent: .init(move: -1))
            if game.events.contains(where: { if case .nonnaOwlHit(owner: 0, _, returned: false) = $0 { return true }; return false }) {
                sawOwlHit = true
                break
            }
        }
        XCTAssertTrue(sawOwlHit)
        let expectedHeal = (game.maximumHealth(0) * DuelNonnaState.spiritHealPermille) / 1000
        XCTAssertEqual(game.fighters[0].health, min(game.maximumHealth(0), hpBeforeOwl + expectedHeal),
                       "Heart of the Pack must restore 6% max HP when Spirit Owl connects")

        // 2. Nonna True Shape strike event on >25% HP opponent during Flame Form!
        for _ in 0..<240 {
            if game.nonnaState(0)?.canEnterFlameForm == true && game.fighters[0].attack == nil &&
                game.fighters[1].knockdown == 0 && game.fighters[1].invulnerable == 0 { break }
            let gap = abs(game.fighters[1].x - game.fighters[0].x)
            let cmd: DuelWeaponCommand? = (gap < 1150 && game.fighters[0].attack == nil &&
                game.fighters[1].knockdown == 0 && game.fighters[1].invulnerable == 0) ? .weapon : nil
            game.step(.init(move: 1, weaponCommand: cmd), opponent: .init(move: -1))
        }
        XCTAssertTrue(game.nonnaState(0)?.canEnterFlameForm == true)
        game.step(.init(weaponCommand: .shadow), opponent: .neutral)
        XCTAssertTrue(game.nonnaState(0)?.isInFlameForm == true)
        for _ in 0..<20 where abs(game.fighters[1].x - game.fighters[0].x) > 1100 {
            game.step(.init(move: 1), opponent: .neutral)
        }
        var sawTrueShapeStrike = false
        game.step(.init(weaponCommand: .weapon), opponent: .neutral)
        for _ in 0..<30 {
            game.step(.neutral, opponent: .neutral)
            if game.events.contains(where: { if case .nonnaTrueShapeStrike(attacker: 0, _) = $0 { return true }; return false }) {
                sawTrueShapeStrike = true
                break
            }
        }
        XCTAssertTrue(sawTrueShapeStrike, "Flame Form strike against >25% HP opponent must emit .nonnaTrueShapeStrike")

        // 3. Ancient Fury: when opponent Shogun enters Shadow Form, Nonna activates 240-tick guaranteed Critical Fury!
        var furyGame = closeArena(.liu, opponent: .wuYong, seed: 112)
        var activatedFury = false
        for _ in 0..<520 {
            let gap = abs(furyGame.fighters[1].x - furyGame.fighters[0].x)
            let foeCmd: DuelWeaponCommand? = (gap < 1300 && furyGame.fighters[1].attack == nil &&
                furyGame.fighters[0].knockdown == 0 && furyGame.fighters[0].invulnerable == 0) ? .weapon : nil
            furyGame.step(.init(move: 1), opponent: .init(move: -1, weaponCommand: foeCmd))
            if furyGame.nonnaState(0)?.isAncientFuryActive == true {
                activatedFury = true
                break
            }
        }
        XCTAssertTrue(activatedFury, "Opponent entering Shadow Form must trigger Nonna's Ancient Fury")
        // Settle Nonna and land a guaranteed critical weapon hit while Ancient Fury is active!
        for _ in 0..<60 where furyGame.fighters[0].stun > 0 || furyGame.fighters[0].knockdown > 0 || furyGame.fighters[1].invulnerable > 0 {
            furyGame.step(.neutral, opponent: .neutral)
        }
        for _ in 0..<20 where abs(furyGame.fighters[1].x - furyGame.fighters[0].x) > 1100 {
            furyGame.step(.init(move: 1), opponent: .neutral)
        }
        XCTAssertTrue(furyGame.nonnaState(0)?.isAncientFuryActive == true)
        var sawFuryCrit = false
        furyGame.step(.init(weaponCommand: .weapon), opponent: .init(move: -1))
        for _ in 0..<30 {
            furyGame.step(.neutral, opponent: .init(move: -1))
            if furyGame.events.contains(where: { if case .criticalHit(attacker: 0, _) = $0 { return true }; return false }) {
                sawFuryCrit = true
                break
            }
        }
        XCTAssertTrue(sawFuryCrit, "Ancient Fury weapon strike must guarantee a Critical Hit")
    }

    func testMidnightPreciseShiftFourStackNocturneAndBlinkCounterFreeze() {
        // 1. Whiff 4 times to charge 4-stack Nocturne, then trigger Precise Shift teleport + unblockable Nocturne Burst!
        var noc = DuelGame(hero: .ember, seed: 121, opponentHero: .gale, ruleset: .shadowArena)
        XCTAssertGreaterThan(abs(noc.fighters[1].x - noc.fighters[0].x), 2000)
        for _ in 0..<4 {
            // Wait until idle and not phased (or clear shift) then whiff a quick jab at long range!
            while noc.fighters[0].attack != nil || noc.midnightState(0)?.isPhasedOut == true {
                noc.step(.neutral, opponent: .neutral)
            }
            noc.step(.init(weaponCommand: .weapon), opponent: .neutral)
            while noc.midnightState(0)?.isPhasedOut != true {
                noc.step(.neutral, opponent: .neutral)
            }
        }
        XCTAssertEqual(noc.midnightState(0)?.nocturneCharges, DuelMidnightState.maxNocturneCharges)
        XCTAssertTrue(noc.midnightState(0)?.isNocturneReady == true)
        XCTAssertTrue(noc.midnightState(0)?.isPhasedOut == true)
        let distBeforeTeleport = abs(noc.fighters[1].x - noc.fighters[0].x)
        XCTAssertGreaterThan(distBeforeTeleport, 1800)

        // Attack while phased out -> Precise Shift teleports onto standing auto-blocking opponent AND triggers 4-stack Nocturne Burst!
        noc.step(.init(move: 1, weaponCommand: .weapon), opponent: .neutral)
        XCTAssertLessThanOrEqual(abs(noc.fighters[1].x - noc.fighters[0].x), 950, "Precise Shift must teleport Sun Deng into strike range")
        var brokeGuard = false
        var sawNocturneBurst = false
        for _ in 0..<30 {
            noc.step(.neutral, opponent: .neutral)
            if noc.events.contains(.guardBreak(defender: 1)) { brokeGuard = true }
            if noc.events.contains(where: { if case .midnightNocturneBurst(attacker: 0, _) = $0 { return true }; return false }) {
                sawNocturneBurst = true
            }
        }
        XCTAssertTrue(brokeGuard, "4-stack Nocturne must shatter standing auto-block")
        XCTAssertTrue(sawNocturneBurst, "4-stack Nocturne strike must emit .midnightNocturneBurst")
        XCTAssertEqual(noc.midnightState(0)?.nocturneCharges, 0, "Nocturne Burst must consume all 4 charges")

        // 2. Blink Counter in Shadow Arena freezes attacker upright (frozenTicks > 0, knockdown == 0)!
        var blink = closeArena(.ember, opponent: .liu, seed: 122)
        for _ in 0..<240 {
            if (blink.midnightState(0)?.shadowEnergy ?? 0) >= DuelMidnightState.blinkShadowCost &&
                blink.fighters[0].attack == nil && blink.fighters[0].stun == 0 && blink.fighters[0].knockdown == 0 &&
                blink.fighters[1].attack == nil && blink.fighters[1].stun == 0 && blink.fighters[1].knockdown == 0 {
                break
            }
            let gap = abs(blink.fighters[1].x - blink.fighters[0].x)
            let needShadow = (blink.midnightState(0)?.shadowEnergy ?? 0) < DuelMidnightState.blinkShadowCost
            let cmd: DuelWeaponCommand? = (needShadow && gap < 1050 && blink.fighters[0].attack == nil &&
                blink.fighters[1].knockdown == 0 && blink.fighters[1].invulnerable == 0) ? .weapon : nil
            blink.step(.init(move: 1, weaponCommand: cmd), opponent: .init(move: -1))
        }
        for _ in 0..<20 where abs(blink.fighters[1].x - blink.fighters[0].x) > 880 {
            blink.step(.init(move: 1), opponent: .init(move: -1))
        }
        blink.step(.init(move: -blink.fighters[0].facing, weaponCommand: .shadow), opponent: .init(weaponCommand: .weapon))
        var sawFreeze = false
        for _ in 0..<24 {
            blink.step(.neutral, opponent: .neutral)
            if blink.fighters[1].frozenTicks > 0 {
                sawFreeze = true
                XCTAssertEqual(blink.fighters[1].knockdown, 0, "Blink Counter Freeze must hold opponent upright, not knock down")
                break
            }
        }
        XCTAssertTrue(sawFreeze, "Midnight Blink Counter in shadowArena must freeze attacker upright for a free follow-up")
    }
}
