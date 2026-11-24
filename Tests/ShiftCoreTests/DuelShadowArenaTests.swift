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
        let emperorVsMonkey = DuelGame(hero: .liu, opponentHero: .ember, ruleset: .shadowArena)
        XCTAssertEqual(emperorVsMonkey.fighters[0].health, 5000)
        XCTAssertEqual(emperorVsMonkey.maximumHealth(0), 5000)
        XCTAssertEqual(emperorVsMonkey.fighters[1].health, 5100)
        XCTAssertEqual(emperorVsMonkey.maximumHealth(1), 5100)

        let shogunVsLegion = DuelGame(hero: .wuYong, opponentHero: .gale, ruleset: .shadowArena)
        XCTAssertEqual(shogunVsLegion.fighters[0].health, 5400)
        XCTAssertEqual(shogunVsLegion.fighters[1].health, 5800)
        XCTAssertEqual(shogunVsLegion.remainingTicks, 99 * 60)
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
        // 1. Wu Yong (Shogun): forward + kick -> Ruthless Advance; ranged -> Retinue strike
        var input = DuelWeaponInput()
        var game = closeArena(.wuYong, opponent: .ember)

        input.direction(x: 1, y: 0)
        input.press(.kick)
        let kickStep = input.consume(facing: game.fighters[0].facing, airborne: false)
        XCTAssertEqual(kickStep.weaponCommand, .kickForward)
        game.step(kickStep, opponent: .init(move: -1))
        XCTAssertEqual(game.fighters[0].attack?.move, .kickForward)
        input.release(.kick)
        input.direction(x: 0, y: 0)

        input.press(.ranged)
        let rangedStep = input.consume(facing: game.fighters[0].facing, airborne: false)
        XCTAssertEqual(rangedStep.weaponCommand, .ranged)
        game.step(rangedStep, opponent: .init(move: -1))
        XCTAssertEqual(game.shogunState(0)?.companionPhase, .windup)
        input.release(.ranged)

        // 2. Liu Quanwei (Emperor): .ranged throws Shadow Dart
        var empGame = DuelGame(hero: .liu, opponentHero: .ember, ruleset: .shadowArena)
        empGame.step(.init(weaponCommand: .ranged), opponent: .init(move: -1))
        XCTAssertEqual(empGame.fighters[0].attack?.move, .skill1)

        // 3. Xu Xiao (King of the Legion): .ranged casts 3D Shadow Chain
        var lkGame = DuelGame(hero: .gale, opponentHero: .ember, ruleset: .shadowArena)
        lkGame.step(.init(weaponCommand: .ranged), opponent: .init(move: -1))
        XCTAssertEqual(lkGame.fighters[0].attack?.move, .legionShadowChain)

        // 4. Sun Deng (Monkey King): .ranged climbs onto Ascension Pillar
        var mkGame = DuelGame(hero: .ember, opponentHero: .liu, ruleset: .shadowArena)
        mkGame.step(.init(weaponCommand: .ranged), opponent: .neutral)
        XCTAssertTrue(mkGame.monkeyKingState(0)?.isPerchedOnPillar == true)
        XCTAssertEqual(mkGame.fighters[0].y, DuelMonkeyKingState.ascensionPerchHeightMM)
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
        // 1. Grounded opponent gets swept in the Legs zone (.low) by weaponDown
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
        jumping.step(.init(weaponCommand: .kickDown), opponent: .init(taps: .jump))
        for _ in 0..<18 {
            jumping.step(.neutral, opponent: .neutral)
        }
        XCTAssertEqual(jumping.landedHits[0], 0, "Jumping opponent must cleanly clear low kickDown capsule sweep!")
    }

    func testWeaponCapsuleSweepHeroReachMatchesPhysicalBladeLength() {
        // Xu Xiao's Legion Greatsword (1.26m) cleanly reaches from ~1.58m away, whereas Liu's shorter gauntlets (0.96m) whiff!
        var xu = DuelGame(hero: .gale, seed: 21, opponentHero: .wuYong, ruleset: .shadowArena)
        var liu = DuelGame(hero: .liu, seed: 21, opponentHero: .wuYong, ruleset: .shadowArena)
        while abs(xu.fighters[1].x - xu.fighters[0].x) > 1620 {
            xu.step(.init(move: 1), opponent: .neutral)
        }
        while abs(liu.fighters[1].x - liu.fighters[0].x) > 1620 {
            liu.step(.init(move: 1), opponent: .neutral)
        }
        let xuDist = abs(xu.fighters[1].x - xu.fighters[0].x)
        let liuDist = abs(liu.fighters[1].x - liu.fighters[0].x)
        XCTAssertLessThanOrEqual(abs(xuDist - liuDist), 120)

        xu.step(.init(weaponCommand: .weapon), opponent: .neutral)
        liu.step(.init(weaponCommand: .weapon), opponent: .neutral)
        for _ in 0..<24 {
            xu.step(.neutral, opponent: .neutral)
            liu.step(.neutral, opponent: .neutral)
        }
        XCTAssertLessThan(xu.fighters[1].health, xu.maximumHealth(1), "Xu Xiao's 1.26m Greatsword capsule must reach at ~1.6m range")
        XCTAssertEqual(liu.fighters[1].health, liu.maximumHealth(1), "Liu's shorter 0.96m gauntlets must whiff at Greatsword max range")
        XCTAssertEqual(liu.landedHits[0], 0)
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

    func testDedicatedRangedCooldownsAndSignatureAbilitiesWorkWithoutEnergyGate() {
        // 1. Emperor Shadow Dart: fires .emperorShadowDart projectile, connects, enters rangedCooldown
        var emp = DuelGame(hero: .liu, seed: 31, opponentHero: .wuYong, ruleset: .shadowArena)
        XCTAssertTrue(emp.emperorState(0)?.canCastRanged == true)
        emp.step(.init(weaponCommand: .ranged), opponent: .init(move: -1))
        var sawDart = false
        var dartHit = false
        for _ in 0..<60 {
            emp.step(.neutral, opponent: .init(move: -1))
            if emp.projectiles.contains(where: { $0.kind == .emperorShadowDart }) { sawDart = true }
            if emp.landedHits[0] > 0 { dartHit = true }
        }
        XCTAssertTrue(sawDart, "Emperor .ranged must spawn .emperorShadowDart projectile")
        XCTAssertTrue(dartHit, "Emperor Shadow Dart must connect against advancing opponent")
        XCTAssertGreaterThan(emp.emperorState(0)?.rangedCooldown ?? 0, 100)

        // 2. King of the Legion 3D Shadow Chain: snags within 4.35m, pulls closer (-1.066m), lifts (velocityY=175)!
        var lk = DuelGame(hero: .gale, seed: 32, opponentHero: .wuYong, ruleset: .shadowArena)
        XCTAssertTrue(lk.legionKingState(0)?.canCastChain == true)
        let foeXBefore = lk.fighters[1].x
        lk.step(.init(weaponCommand: .ranged), opponent: .init(move: -1))
        XCTAssertEqual(lk.fighters[0].attack?.move, .legionShadowChain)
        var sawSnag = false
        var lifted = false
        for _ in 0..<45 {
            lk.step(.neutral, opponent: .init(move: -1))
            if lk.events.contains(where: { if case .legionChainSnag(attacker: 0, _) = $0 { return true }; return false }) {
                sawSnag = true
            }
            if lk.fighters[1].y > 0 || lk.fighters[1].velocityY > 0 { lifted = true }
        }
        XCTAssertTrue(sawSnag, "Legion King Shadow Chain must snag opponent within 4.35m")
        XCTAssertTrue(lifted, "Legion King Shadow Chain snag must lift victim vertically")
        XCTAssertLessThan(lk.fighters[1].x, foeXBefore - 600, "Legion King Shadow Chain must yank opponent toward Xu Xiao")
        XCTAssertGreaterThan(lk.legionKingState(0)?.chainCooldown ?? 0, 120)

        // 3. Monkey King Ascension Perch: climbs onto 3D pillar at Y=2120mm without energy gate
        var mk = DuelGame(hero: .ember, seed: 33, opponentHero: .liu, ruleset: .shadowArena)
        XCTAssertTrue(mk.monkeyKingState(0)?.canEnterAscension == true)
        mk.step(.init(weaponCommand: .ranged), opponent: .neutral)
        XCTAssertTrue(mk.events.contains(.monkeyAscensionPerch(fighter: 0)))
        XCTAssertTrue(mk.monkeyKingState(0)?.isPerchedOnPillar == true)
        XCTAssertEqual(mk.fighters[0].y, DuelMonkeyKingState.ascensionPerchHeightMM)
        XCTAssertGreaterThan(mk.monkeyKingState(0)?.pillarShowTicks ?? 0, 100)
    }

    func testShogunCalibratedOrdinaryHeavyVsChargedHeavyAndDirectionalShadow() {
        // 1. NO AFK passive shadow charging in shadowArena
        var idleShogun = DuelGame(hero: .wuYong, seed: 41, opponentHero: .gale, ruleset: .shadowArena)
        for _ in 0..<60 { idleShogun.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(idleShogun.shogunState(0)?.shadowEnergy, 0, "Shogun must NOT passively charge shadow while AFK")

        // 2. Phase 1 calibration: uncharged ordinary .heavy is BLOCKED by standing auto-block (does NOT guard-break!)
        var uncharged = closeArena(.wuYong, opponent: .gale, seed: 42)
        uncharged.step(.init(weaponCommand: .heavy), opponent: .neutral)
        var sawBlocked = false
        var sawGuardBreak = false
        for _ in 0..<40 {
            uncharged.step(.neutral, opponent: .neutral)
            if uncharged.events.contains(.blocked(defender: 1)) { sawBlocked = true }
            if uncharged.events.contains(.guardBreak(defender: 1)) { sawGuardBreak = true }
        }
        XCTAssertTrue(sawBlocked, "Calibrated ordinary Shogun heavy must be blockable by standing guard")
        XCTAssertFalse(sawGuardBreak, "Uncharged Shogun heavy must NOT guard-break standing auto-block")

        // 3. Build Shogun Shadow Form via Odachi combos -> test directional Shadow (Back=Despotism, Forward=Fierce Reprisal)
        var shogun = closeArena(.wuYong, opponent: .gale, seed: 43)
        var sawShadowForm = false
        for _ in 0..<480 {
            let gap = abs(shogun.fighters[1].x - shogun.fighters[0].x)
            let cmd: DuelWeaponCommand? = (gap < 1300 && shogun.fighters[0].attack == nil &&
                shogun.fighters[1].knockdown == 0 && shogun.fighters[1].invulnerable == 0) ? .weapon : nil
            shogun.step(.init(move: 1, weaponCommand: cmd), opponent: .init(move: -1))
            if shogun.events.contains(.shogunShadowForm(fighter: 0)) {
                sawShadowForm = true
                break
            }
        }
        XCTAssertTrue(sawShadowForm, "Shogun must reach Shadow Form through combat hits")

        var backBranch = shogun
        while backBranch.fighters[0].attack != nil || backBranch.fighters[0].stun > 0 {
            backBranch.step(.neutral, opponent: .neutral)
        }
        backBranch.step(.init(move: -backBranch.fighters[0].facing, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertEqual(backBranch.fighters[0].attack?.move, .shogunDespotism, "Back + Shadow must trigger Despotism")

        var fwdBranch = shogun
        while fwdBranch.fighters[0].attack != nil || fwdBranch.fighters[0].stun > 0 {
            fwdBranch.step(.neutral, opponent: .neutral)
        }
        fwdBranch.step(.init(move: fwdBranch.fighters[0].facing, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertEqual(fwdBranch.fighters[0].attack?.move, .shogunFierceReprisal, "Forward + Shadow must trigger Fierce Reprisal")
    }

    func testTakingDamageChargesAllNonShogunHeroesAndAirborneAttacks() {
        for defenderHero in [DuelGame.Hero.gale, .liu, .ember] {
            var g = closeArena(.wuYong, opponent: defenderHero, seed: 51)
            g.step(.init(weaponCommand: .weapon), opponent: .init(move: -1))
            for _ in 0..<30 { g.step(.neutral, opponent: .init(move: -1)) }
            XCTAssertGreaterThan(g.landedHits[0], 0)
            switch defenderHero {
            case .gale: XCTAssertGreaterThan(g.legionKingState(1)?.shadowEnergy ?? 0, 0)
            case .liu: XCTAssertGreaterThan(g.emperorState(1)?.shadowEnergy ?? 0, 0)
            case .ember: XCTAssertGreaterThan(g.monkeyKingState(1)?.shadowEnergy ?? 0, 0)
            case .wuYong: break
            }
        }

        // Airborne jump-kick executes .kickUp mid-air
        var air = DuelGame(hero: .wuYong, seed: 53, opponentHero: .ember, ruleset: .shadowArena)
        air.step(.init(taps: .jump), opponent: .neutral)
        for _ in 0..<4 { air.step(.neutral, opponent: .neutral) }
        XCTAssertGreaterThan(air.fighters[0].y, 0)
        air.step(.init(weaponCommand: .kick), opponent: .neutral)
        XCTAssertEqual(air.fighters[0].attack?.move, .kickUp, "Airborne kick in shadowArena must execute jump-kick (.kickUp)")
    }

    func testWakeupLowKickAndCombatRecoveryRollFollowSF4Rules() {
        // 1. Standing forward roll crosses through close opponent with startup invulnerability
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
        wk.step(.init(move: 1), opponent: .init(weaponCommand: .kickDown))
        var knockedDown = false
        for _ in 0..<62 {
            wk.step(.init(move: 1), opponent: .neutral)
            if wk.fighters[0].knockdown > 0 && wk.fighters[0].knockdown <= 22 {
                knockedDown = true
                break
            }
        }
        XCTAssertTrue(knockedDown, "Liu's kickDown should knock Wu Yong down into the wakeup window")
        wk.step(.init(weaponCommand: .kick), opponent: .init(move: -1))
        XCTAssertEqual(wk.fighters[0].knockdown, 0, "Wake-up Kick must cancel remaining knockdown")
        XCTAssertEqual(wk.fighters[0].attack?.move, .wakeupKick, "Kick during knockdown wakeup window must start .wakeupKick")
        XCTAssertGreaterThanOrEqual(wk.fighters[0].invulnerable, 7, "Wake-up Kick must grant startup invulnerability")
        let foeHPBefore = wk.fighters[1].health
        for _ in 0..<30 {
            wk.step(.neutral, opponent: .init(move: -1))
        }
        XCTAssertLessThan(wk.fighters[1].health, foeHPBefore, "Wake-up Low Kick must connect against an advancing opponent")
        XCTAssertEqual(wk.fighters[1].lastHitZone, .low, "Wake-up Low Kick must register as a low sweep hit")
    }

    func testVelocitySlidingKnockbackAndCornerWallSplatBounceIntoJuggle() {
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
        while slide.hitStop > 0 {
            slide.step(.neutral, opponent: .neutral)
            XCTAssertEqual(slide.fighters[1].x, hitTickX, "Victim must not slide before hitStop releases")
        }
        var slidePositions: [Int] = [hitTickX]
        for _ in 0..<14 {
            slide.step(.neutral, opponent: .neutral)
            slidePositions.append(slide.fighters[1].x)
        }
        XCTAssertGreaterThan(slidePositions.last ?? 0, hitTickX + 180, "Victim must smoothly slide backward across floor after hitStop")
        XCTAssertGreaterThan(slidePositions[2], hitTickX, "Slide begins immediately after hitStop ends")
        XCTAssertLessThan(slidePositions[2], slidePositions.last ?? 0, "Slide must span multiple ticks, not teleport in 1 tick")

        // Corner Wall-Splat
        var wall = DuelGame(hero: .wuYong, seed: 72, opponentHero: .ember, ruleset: .shadowArena)
        for _ in 0..<85 {
            wall.step(.init(move: 1), opponent: .init(move: 1))
        }
        XCTAssertGreaterThan(wall.fighters[1].x, DuelGame.rightWall - 500)
        for _ in 0..<30 where abs(wall.fighters[1].x - wall.fighters[0].x) > 1250 {
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
        for _ in 0..<8 { game.step(.neutral, opponent: .neutral) }
        XCTAssertGreaterThan(game.fighters[0].x - xStart, 700, "Forward dash must cover burst distance")
        game.step(.init(weaponCommand: .weapon), opponent: .neutral)
        XCTAssertEqual(game.fighters[0].attack?.move, .jab, "dashForward must be attack-cancelable after age 4")
        for _ in 0..<42 { game.step(.neutral, opponent: .neutral) }

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

        // Shogun Charged Heavy through DuelWeaponInput.heavyHeld pass-through shatters guard!
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
        XCTAssertGreaterThanOrEqual(peakChargeTicks, DuelShogunState.heavyFullChargeTicks)
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
        // 1. Counter-Hit
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

        // 2. Blade Clash
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

        // 3. Multi-Hit Weapon String
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

        // 4. Airborne Juggle
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
        var maxJuggle = 0
        for _ in 0..<40 {
            let cmd: DuelWeaponCommand? = (jugGame.fighters[0].attack == nil && jugGame.fighters[1].y > 0) ? .weapon : nil
            jugGame.step(.init(move: 1, weaponCommand: cmd), opponent: .neutral)
            maxJuggle = max(maxJuggle, jugGame.fighters[1].juggleHits)
        }
        XCTAssertGreaterThanOrEqual(maxJuggle, 1, "Follow-up attack on launched airborne opponent must register a mid-air juggle")
    }

    func testEmperorTransformToShadowBeastAndBeastLifestealHitGuardWhiffRules() {
        var game = closeArena(.liu, opponent: .wuYong, seed: 101)
        // Take one clean hit so Liu has missing HP to measure Beast lifesteal, then build 100 Shadow Energy!
        game.step(.init(move: 1), opponent: .init(weaponCommand: .heavy))
        for _ in 0..<70 { game.step(.init(move: 1), opponent: .neutral) }
        XCTAssertLessThan(game.fighters[0].health, game.maximumHealth(0))

        for _ in 0..<520 {
            if game.emperorState(0)?.canTransformToBeast == true &&
                game.fighters[0].attack == nil && game.fighters[0].stun == 0 && game.fighters[0].knockdown == 0 {
                break
            }
            let gap = abs(game.fighters[1].x - game.fighters[0].x)
            let cmd: DuelWeaponCommand? = (gap < 1150 && game.fighters[0].attack == nil &&
                game.fighters[1].knockdown == 0 && game.fighters[1].invulnerable == 0) ? .weapon : nil
            game.step(.init(move: 1, weaponCommand: cmd), opponent: .init(move: -1))
        }
        XCTAssertTrue(game.emperorState(0)?.canTransformToBeast == true, "Emperor must build 100 Shadow Energy to transform")
        XCTAssertFalse(game.emperorState(0)?.isBeastForm == true)

        // Trigger permanent Shadow Beast transformation via .shadow!
        let foeHPBeforeTransform = game.fighters[1].health
        game.step(.init(weaponCommand: .shadow), opponent: .neutral)
        XCTAssertEqual(game.fighters[0].attack?.move, .emperorTransform)
        var sawTransformEvent = false
        for _ in 0..<45 {
            game.step(.neutral, opponent: .neutral)
            if game.events.contains(where: { if case .emperorTransformed(fighter: 0, _) = $0 { return true }; return false }) {
                sawTransformEvent = true
            }
        }
        XCTAssertTrue(sawTransformEvent, "Emperor transformation must emit .emperorTransformed shockwave")
        XCTAssertTrue(game.emperorState(0)?.isBeastForm == true, "Emperor must permanently swap to Shadow Beast for the round")
        XCTAssertLessThan(game.fighters[1].health, foeHPBeforeTransform, "2.65m transform shockwave must damage nearby opponent")

        // Ensure Beast is damaged enough to measure exact +68 (hit), +18 (guard), 0 (whiff) lifesteal
        if game.fighters[0].health > game.maximumHealth(0) - 120 {
            game.step(.init(move: 1), opponent: .init(weaponCommand: .heavy))
            for _ in 0..<60 { game.step(.init(move: 1), opponent: .neutral) }
        }

        // Branch A: Beast Whiff at long range heals 0 HP!
        var whiffBranch = game
        for _ in 0..<30 { whiffBranch.step(.init(move: -1), opponent: .init(move: 1)) }
        let hpBeforeWhiff = whiffBranch.fighters[0].health
        whiffBranch.step(.init(weaponCommand: .weapon), opponent: .neutral)
        for _ in 0..<30 { whiffBranch.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(whiffBranch.fighters[0].health, hpBeforeWhiff, "Shadow Beast whiff must heal 0 HP")

        // Branch B: Beast Blocked strike heals +18 HP!
        var guardBranch = game
        for _ in 0..<80 {
            let dir = guardBranch.fighters[0].facing
            let gap = abs(guardBranch.fighters[1].x - guardBranch.fighters[0].x)
            if gap <= 980 && guardBranch.fighters[1].knockdown == 0 && guardBranch.fighters[1].invulnerable == 0 &&
                guardBranch.fighters[0].attack == nil { break }
            guardBranch.step(.init(move: gap > 980 ? dir : 0), opponent: .neutral)
        }
        let hpBeforeGuard = guardBranch.fighters[0].health
        guardBranch.step(.init(weaponCommand: .weapon), opponent: .neutral)
        var guardHeal = 0
        for _ in 0..<30 {
            guardBranch.step(.neutral, opponent: .neutral)
            for e in guardBranch.events {
                if case .emperorLifesteal(fighter: 0, let h) = e { guardHeal += h }
            }
        }
        XCTAssertEqual(guardHeal, DuelEmperorState.beastGuardLifestealHP, "Shadow Beast blocked claw must heal exactly +18 HP")
        XCTAssertEqual(guardBranch.fighters[0].health, min(guardBranch.maximumHealth(0), hpBeforeGuard + guardHeal))

        // Branch C: Beast Clean Hit heals +68 HP!
        var hitBranch = game
        for _ in 0..<80 {
            let dir = hitBranch.fighters[0].facing
            let gap = abs(hitBranch.fighters[1].x - hitBranch.fighters[0].x)
            if gap <= 980 && hitBranch.fighters[1].knockdown == 0 && hitBranch.fighters[1].invulnerable == 0 &&
                hitBranch.fighters[0].attack == nil { break }
            hitBranch.step(.init(move: gap > 980 ? dir : 0), opponent: .init(move: -dir))
        }
        let foeDir = hitBranch.fighters[1].facing
        let hpBeforeHit = hitBranch.fighters[0].health
        hitBranch.step(.init(weaponCommand: .weapon), opponent: .init(move: foeDir))
        var hitHeal = 0
        for _ in 0..<30 {
            hitBranch.step(.neutral, opponent: .init(move: foeDir))
            for e in hitBranch.events {
                if case .emperorLifesteal(fighter: 0, let h) = e { hitHeal += h }
            }
        }
        XCTAssertEqual(hitHeal, DuelEmperorState.beastHitLifestealHP, "Shadow Beast clean claw hit must heal exactly +68 HP")
        XCTAssertEqual(hitBranch.fighters[0].health, min(hitBranch.maximumHealth(0), hpBeforeHit + hitHeal))
    }

    func testLegionKingDarkIncarnationSingleTriggerReviveAndShadowSkills() {
        // 1. Dark Incarnation revives Xu Xiao with 520 HP on first lethal blow, and NEVER triggers a second time!
        var game = closeArena(.gale, opponent: .wuYong, seed: 111)
        var reviveCount = 0
        var hpAtRevive = 0
        var sawRoundOver = false

        for _ in 0..<1800 {
            let gap = abs(game.fighters[1].x - game.fighters[0].x)
            let foeCmd: DuelWeaponCommand? = (gap < 1300 && game.fighters[1].attack == nil &&
                game.fighters[0].knockdown == 0 && game.fighters[0].invulnerable == 0) ? .heavy : nil
            // Xu Xiao walks forward (guard open) to take clean lethal strikes
            game.step(.init(move: 1), opponent: .init(move: -1, weaponCommand: foeCmd))
            if game.events.contains(.legionDarkIncarnation(fighter: 0)) {
                reviveCount += 1
                hpAtRevive = game.fighters[0].health
            }
            if game.fighters[0].health == 0 || game.phase != .fighting {
                sawRoundOver = true
                break
            }
        }
        XCTAssertEqual(reviveCount, 1, "Dark Incarnation must trigger ONCE per round on first lethal blow")
        XCTAssertEqual(hpAtRevive, DuelLegionKingState.darkIncarnationReviveHP, "Dark Incarnation must revive with 520 HP")
        XCTAssertTrue(sawRoundOver, "Second lethal hit after Dark Incarnation must cleanly finish the round")

        // 2. Shadow Skills: Forward+Shadow -> .legionShadowForward (Sorrowful Prayer), Down+Shadow -> .legionShadowDown (Earthsplitter)
        var shadowGame = closeArena(.gale, opponent: .wuYong, seed: 112)
        for _ in 0..<520 {
            if shadowGame.legionKingState(0)?.canCastShadowAbility == true &&
                shadowGame.fighters[0].attack == nil && shadowGame.fighters[0].stun == 0 && shadowGame.fighters[0].knockdown == 0 {
                break
            }
            let gap = abs(shadowGame.fighters[1].x - shadowGame.fighters[0].x)
            let cmd: DuelWeaponCommand? = (gap < 1400 && shadowGame.fighters[0].attack == nil &&
                shadowGame.fighters[1].knockdown == 0 && shadowGame.fighters[1].invulnerable == 0) ? .weapon : nil
            shadowGame.step(.init(move: 1, weaponCommand: cmd), opponent: .init(move: -1))
        }
        XCTAssertTrue(shadowGame.legionKingState(0)?.canCastShadowAbility == true)

        var prayerBranch = shadowGame
        prayerBranch.step(.init(move: 1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertEqual(prayerBranch.fighters[0].attack?.move, .legionShadowForward)

        var splitBranch = shadowGame
        splitBranch.step(.init(vertical: -1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertEqual(splitBranch.fighters[0].attack?.move, .legionShadowDown)
    }

    func testMonkeyKingAscensionPerchLowEvadeAntiAirKnockoffPlungeAndHeavenlyPillar() {
        // 1. Perch atop 3D Ascension Pillar -> grounded low/mid strike is cleanly evaded!
        var evadeGame = closeArena(.ember, opponent: .wuYong, seed: 121)
        evadeGame.step(.init(weaponCommand: .ranged), opponent: .neutral)
        XCTAssertTrue(evadeGame.monkeyKingState(0)?.isPerchedOnPillar == true)
        let hpBeforeEvade = evadeGame.fighters[0].health
        let shadowBeforeEvade = evadeGame.monkeyKingState(0)?.shadowEnergy ?? 0
        evadeGame.step(.neutral, opponent: .init(weaponCommand: .weaponDown))
        var sawEvade = false
        for _ in 0..<30 {
            evadeGame.step(.neutral, opponent: .neutral)
            if evadeGame.events.contains(.monkeyPerchEvade(fighter: 0)) { sawEvade = true }
        }
        XCTAssertTrue(sawEvade, "Perched Monkey King must evade grounded low/mid attacks atop Ascension Pillar")
        XCTAssertEqual(evadeGame.fighters[0].health, hpBeforeEvade, "Evaded grounded attack must deal 0 damage")
        XCTAssertGreaterThan(evadeGame.monkeyKingState(0)?.shadowEnergy ?? 0, shadowBeforeEvade)
        XCTAssertTrue(evadeGame.monkeyKingState(0)?.isPerchedOnPillar == true)

        // 2. Anti-air high slash (.weaponUp) knocks Monkey King off the pillar!
        var antiAir = closeArena(.ember, opponent: .wuYong, seed: 122)
        antiAir.step(.init(weaponCommand: .ranged), opponent: .neutral)
        XCTAssertTrue(antiAir.monkeyKingState(0)?.isPerchedOnPillar == true)
        antiAir.step(.neutral, opponent: .init(weaponCommand: .weaponUp))
        for _ in 0..<30 { antiAir.step(.neutral, opponent: .neutral) }
        XCTAssertFalse(antiAir.monkeyKingState(0)?.isPerchedOnPillar == true, "High anti-air slash must knock Monkey King off pillar")
        XCTAssertLessThan(antiAir.fighters[0].health, antiAir.maximumHealth(0))

        // 3. Perched Forward+Weapon -> .monkeyAscensionPlunge!
        var plunge = closeArena(.ember, opponent: .liu, seed: 123)
        plunge.step(.init(weaponCommand: .ranged), opponent: .neutral)
        plunge.step(.init(move: 1, weaponCommand: .weaponForward), opponent: .init(move: -1))
        XCTAssertEqual(plunge.fighters[0].attack?.move, .monkeyAscensionPlunge)
        XCTAssertFalse(plunge.monkeyKingState(0)?.isPerchedOnPillar == true)
        for _ in 0..<35 { plunge.step(.neutral, opponent: .init(move: -1)) }
        XCTAssertLessThan(plunge.fighters[1].health, plunge.maximumHealth(1))

        // 4. Perched Shadow -> .monkeyHeavenlyPillar shatters standing auto-block & activates Heavenly Aura!
        var slam = closeArena(.ember, opponent: .liu, seed: 124)
        slam.step(.init(weaponCommand: .ranged), opponent: .neutral)
        slam.step(.init(weaponCommand: .shadow), opponent: .neutral)
        XCTAssertEqual(slam.fighters[0].attack?.move, .monkeyHeavenlyPillar)
        var sawSlam = false
        var brokeGuard = false
        for _ in 0..<45 {
            slam.step(.neutral, opponent: .neutral)
            if slam.events.contains(where: { if case .monkeyPillarSlam(attacker: 0, _) = $0 { return true }; return false }) {
                sawSlam = true
            }
            if slam.events.contains(.guardBreak(defender: 1)) { brokeGuard = true }
        }
        XCTAssertTrue(sawSlam, "Heavenly Pillar must emit .monkeyPillarSlam")
        XCTAssertTrue(brokeGuard, "Heavenly Pillar slam must shatter standing auto-block")
        XCTAssertTrue(slam.monkeyKingState(0)?.hasHeavenlyAura == true, "Heavenly Pillar must ignite Heavenly Aura")
    }
}
