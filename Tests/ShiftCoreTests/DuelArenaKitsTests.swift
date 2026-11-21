import XCTest
@testable import ShiftCore

final class DuelArenaKitsTests: XCTestCase {
    private func closeMatch(_ hero: DuelGame.Hero, opponent: DuelGame.Hero, mode: DuelGame.Mode = .practice) -> DuelGame {
        var game = DuelGame(hero: hero, mode: mode, seed: 20261121, opponentHero: opponent)
        for _ in 0..<24 {
            game.step(.init(move: 1), opponent: .init(move: -1))
        }
        return game
    }

    private func settle(_ game: inout DuelGame) {
        for _ in 0..<180 {
            if game.fighters[0].attack == nil && game.fighters[1].attack == nil &&
                game.hitStop == 0 && game.fighters[0].knockdown == 0 && game.fighters[0].invulnerable == 0 &&
                game.fighters[1].knockdown == 0 && game.fighters[1].invulnerable == 0 &&
                game.fighters[0].stun == 0 && game.fighters[1].stun == 0 {
                break
            }
            game.step(.neutral, opponent: .neutral)
        }
    }

    // MARK: - Xu Xiao (Grand Inquisitor Ingvar / 大审判官)

    func testInquisitorSalvationPillarAppliesStigmataBurnsEnergyHealsAndAutoFlashes() {
        var game = DuelGame(hero: .gale, mode: .versus, seed: 20261121, opponentHero: .ember)
        // Injure Xu Xiao slightly first so we can verify Salvation healing.
        for _ in 0..<20 { game.step(.init(move: 1), opponent: .init(move: -1)) }
        game.step(.neutral, opponent: .init(taps: .light))
        for _ in 0..<25 { game.step(.neutral, opponent: .neutral) }
        settle(&game)
        let xuHPBefore = game.fighters[0].health
        XCTAssertLessThan(xuHPBefore, 1000)

        // Back up a step and cast Salvation Light Pillar (skill1).
        for _ in 0..<12 { game.step(.init(move: -1), opponent: .neutral) }
        let foeEnergyBefore = game.fighters[1].energy
        var applied = false
        var flashed = false
        game.step(.init(taps: .skill1), opponent: .neutral)
        for _ in 0..<60 {
            game.step(.neutral, opponent: .neutral)
            if game.events.contains(.inquisitorStigmataApplied(defender: 1)) { applied = true }
        }
        XCTAssertTrue(applied, "Salvation Light Pillar must apply Stigmata")
        XCTAssertTrue(game.inquisitorState(0)?.hasStigmataOnOpponent == true)
        XCTAssertGreaterThan(game.fighters[0].health, xuHPBefore, "Salvation must heal Xu Xiao")
        XCTAssertLessThan(game.fighters[1].energy, foeEnergyBefore, "Salvation must burn opponent energy")
        XCTAssertGreaterThan(game.inquisitorState(0)?.blessings ?? 0, 0, "Stigmata must award Righteousness Blessing")

        // Let Stigmata countdown expire naturally -> auto-flash launches & damages opponent!
        let hpBeforeFlash = game.fighters[1].health
        for _ in 0..<(DuelInquisitorState.stigmataDurationTicks + 10) {
            game.step(.neutral, opponent: .neutral)
            if game.events.contains(where: { if case .inquisitorStigmataFlash(attacker: 0, _) = $0 { return true }; return false }) {
                flashed = true
                break
            }
        }
        XCTAssertTrue(flashed, "Stigmata must auto-flash when timer expires")
        XCTAssertLessThan(game.fighters[1].health, hpBeforeFlash)
        XCTAssertGreaterThan(game.fighters[1].knockdown, 0, "Stigmata flash must launch/knockdown opponent")
    }

    func testInquisitorStigmataDetonatesEarlyOnFinisherAndDispelsWhenHit() {
        // Branch A: Brand with skill2, then combo finisher detonates Stigmata early!
        var detonateGame = closeMatch(.gale, opponent: .ember)
        detonateGame.step(.init(taps: .skill2), opponent: .neutral)
        for _ in 0..<45 { detonateGame.step(.neutral, opponent: .neutral) }
        XCTAssertTrue(detonateGame.inquisitorState(0)?.hasStigmataOnOpponent == true)
        // Wait until opponent recovers, step close, and land 3-hit light chain ending in finisher.
        for _ in 0..<40 {
            let dir = abs(detonateGame.fighters[1].x - detonateGame.fighters[0].x) > 950 ? 1 : 0
            detonateGame.step(.init(move: dir), opponent: .neutral)
            if detonateGame.fighters[1].knockdown == 0 && detonateGame.fighters[1].invulnerable == 0 && detonateGame.fighters[0].attack == nil {
                break
            }
        }
        var earlyFlash = false
        detonateGame.step(.init(taps: .light), opponent: .neutral)
        for tick in 0..<80 {
            detonateGame.step(.init(taps: tick % 3 == 0 ? .light : []), opponent: .neutral)
            if detonateGame.events.contains(where: { if case .inquisitorStigmataFlash(attacker: 0, _) = $0 { return true }; return false }) {
                earlyFlash = true
                break
            }
        }
        XCTAssertTrue(earlyFlash, "Combo finisher must detonate branded Stigmata early")

        // Branch B: Opponent hitting Xu Xiao dispels Stigmata!
        var dispelGame = closeMatch(.gale, opponent: .ember)
        dispelGame.step(.init(taps: .skill1), opponent: .neutral)
        for _ in 0..<45 { dispelGame.step(.neutral, opponent: .neutral) }
        XCTAssertTrue(dispelGame.inquisitorState(0)?.hasStigmataOnOpponent == true)
        for _ in 0..<30 where abs(dispelGame.fighters[1].x - dispelGame.fighters[0].x) > 900 {
            dispelGame.step(.neutral, opponent: .init(move: -1))
        }
        dispelGame.step(.neutral, opponent: .init(taps: .light))
        for _ in 0..<25 { dispelGame.step(.neutral, opponent: .neutral) }
        XCTAssertFalse(dispelGame.inquisitorState(0)?.hasStigmataOnOpponent == true, "Taking an unblocked hit must dispel Stigmata")
    }

    func testInquisitorFormOfLightBreaksGuardUnlocksSpinAndKnockoutHalvesLight() {
        var game = closeMatch(.gale, opponent: .ember)
        // Build Light Power to 100 through real hits.
        for tick in 0..<500 {
            if game.inquisitorState(0)?.canEnterFormOfLight == true { break }
            let dist = abs(game.fighters[1].x - game.fighters[0].x)
            game.step(.init(move: dist > 1100 ? 1 : 0, taps: tick % 18 == 0 ? .light : []), opponent: .neutral)
        }
        settle(&game)
        XCTAssertTrue(game.inquisitorState(0)?.canEnterFormOfLight == true)

        // Activate Form of Light via ultimate!
        var entered = false
        game.step(.init(taps: .ultimate), opponent: .neutral)
        if game.events.contains(.inquisitorFormOfLight(fighter: 0)) { entered = true }
        XCTAssertTrue(entered)
        XCTAssertTrue(game.inquisitorState(0)?.isInFormOfLight == true)

        // Branch A: In Form of Light, skill2 becomes Tower's Dogma spin and BREAKS opponent's guard!
        var breakGame = game
        for _ in 0..<40 where abs(breakGame.fighters[1].x - breakGame.fighters[0].x) > 1050 {
            breakGame.step(.init(move: 1), opponent: .init(guardHeld: true))
        }
        var brokeGuard = false
        let hpBefore = breakGame.fighters[1].health
        breakGame.step(.init(taps: .skill2), opponent: .init(guardHeld: true))
        XCTAssertEqual(breakGame.fighters[0].attack?.move, .inquisitorLightSpin)
        for _ in 0..<40 {
            breakGame.step(.neutral, opponent: .init(guardHeld: true))
            if breakGame.events.contains(.guardBreak(defender: 1)) { brokeGuard = true }
        }
        XCTAssertTrue(brokeGuard, "Form of Light attacks must break guard")
        XCTAssertLessThan(breakGame.fighters[1].health, hpBefore, "Block-breaking Form of Light must deal health damage")

        // Branch B: Taking an unblocked hit knocks Xu Xiao out of Form of Light and halves remaining Light!
        var knockGame = game
        // Wait out entry invulnerability.
        for _ in 0..<(DuelInquisitorState.entryInvulnerableTicks + 4) {
            let dist = abs(knockGame.fighters[1].x - knockGame.fighters[0].x)
            knockGame.step(.neutral, opponent: .init(move: dist > 900 ? -1 : 0))
        }
        let lightBeforeHit = knockGame.inquisitorState(0)?.lightPower ?? 0
        XCTAssertGreaterThan(lightBeforeHit, 50)
        knockGame.step(.neutral, opponent: .init(taps: .light))
        for _ in 0..<25 { knockGame.step(.neutral, opponent: .neutral) }
        XCTAssertFalse(knockGame.inquisitorState(0)?.isInFormOfLight == true, "Unblocked hit must knock Xu Xiao out of Form of Light")
        XCTAssertLessThanOrEqual(knockGame.inquisitorState(0)?.lightPower ?? 100, lightBeforeHit / 2)
    }

    func testInquisitorMartyrdomRestoresLightBelow25PercentHP() {
        var game = closeMatch(.gale, opponent: .ember, mode: .versus)
        for tick in 0..<600 {
            if game.fighters[0].health <= DuelInquisitorState.martyrdomThresholdHP && game.fighters[0].health > 0 { break }
            let dist = abs(game.fighters[1].x - game.fighters[0].x)
            game.step(.neutral, opponent: .init(move: dist > 900 ? -1 : 0, taps: tick % 24 == 0 ? .light : []))
        }
        XCTAssertLessThanOrEqual(game.fighters[0].health, DuelInquisitorState.martyrdomThresholdHP)
        XCTAssertGreaterThan(game.fighters[0].health, 0)
        for _ in 0..<(DuelInquisitorState.martyrdomRestoreDuration + 5) {
            game.step(.neutral, opponent: .neutral)
        }
        XCTAssertTrue(game.inquisitorState(0)?.martyrdomUsed == true)
        XCTAssertGreaterThanOrEqual(game.inquisitorState(0)?.lightPower ?? 0, 50)
    }

    // MARK: - Liu Quanwei (Nonna / 诺娜 · 花焰巨斧)

    func testNonnaGreatAxeUnbreakableAbsorbsHitAndSummonsSpiritWolf() {
        var game = closeMatch(.liu, opponent: .ember)
        // Liu starts Great Axe heavy; opponent jabs right during Liu's Unbreakable window!
        game.step(.init(taps: .heavy), opponent: .neutral)
        var absorbed = false
        var wolfSummoned = false
        var wolfHit = false
        for tick in 0..<70 {
            game.step(.neutral, opponent: .init(taps: tick == 4 ? .light : []))
            if game.events.contains(.shogunArmorAbsorbed(defender: 0)) { absorbed = true }
            if game.nonnaState(0)?.wolfActive == true { wolfSummoned = true }
            if game.events.contains(where: { if case .nonnaWolfHit(owner: 0, _) = $0 { return true }; return false }) {
                wolfHit = true
            }
        }
        XCTAssertTrue(absorbed, "Nonna heavy Great Axe must have Legion Unbreakable hyper-armor")
        XCTAssertTrue(wolfSummoned, "Absorbing a hit during Unbreakable must summon Spirit Wolf")
        XCTAssertTrue(wolfHit || game.landedHits[0] > 0)
    }

    func testNonnaThirdStrikeSummonsBlazingHuntWolfAndOwlRecallStunsOpponent() {
        // Branch A: 3rd landed strike summons autonomous Spirit Wolf!
        var wolfGame = closeMatch(.liu, opponent: .ember)
        var sawWolf = false
        var sawWolfHit = false
        wolfGame.step(.init(taps: .light), opponent: .neutral)
        for tick in 0..<140 {
            let tap: DuelGame.Buttons = tick < 60 && tick % 3 == 0 ? .light : []
            wolfGame.step(.init(taps: tap), opponent: .neutral)
            if wolfGame.nonnaState(0)?.wolfActive == true { sawWolf = true }
            if wolfGame.events.contains(where: { if case .nonnaWolfHit(owner: 0, _) = $0 { return true }; return false }) {
                sawWolfHit = true
            }
        }
        XCTAssertTrue(sawWolf, "3rd landed strike must trigger Blazing Hunt Spirit Wolf")
        XCTAssertGreaterThan(wolfGame.nonnaState(0)?.flamePower ?? 0, 0)
        _ = sawWolfHit

        // Branch B: Fire Grip Spirit Owl launches, latches, manually recalls for free, and stuns!
        var owlGame = DuelGame(hero: .liu, mode: .practice, seed: 20261121, opponentHero: .ember)
        for _ in 0..<10 { owlGame.step(.init(move: 1), opponent: .neutral) }
        var outHit = false
        var returnHit = false
        var maxStun = 0
        owlGame.step(.init(taps: .skill1), opponent: .neutral)
        XCTAssertEqual(owlGame.nonnaState(0)?.owlPhase, .outbound)
        for _ in 0..<40 {
            owlGame.step(.neutral, opponent: .neutral)
            if owlGame.events.contains(where: { if case .nonnaOwlHit(owner: 0, _, returned: false) = $0 { return true }; return false }) {
                outHit = true
            }
            if owlGame.nonnaState(0)?.owlPhase == .latched { break }
        }
        XCTAssertTrue(outHit, "Outbound Spirit Owl must hit opponent")
        XCTAssertEqual(owlGame.nonnaState(0)?.owlPhase, .latched)
        while owlGame.hitStop > 0 { owlGame.step(.neutral, opponent: .neutral) }
        let energyBeforeRecall = owlGame.fighters[0].energy
        // Manual recall via skill1 must be free and immediately set owl returning!
        owlGame.step(.init(taps: .skill1), opponent: .neutral)
        XCTAssertEqual(owlGame.nonnaState(0)?.owlPhase, .returning)
        XCTAssertGreaterThanOrEqual(owlGame.fighters[0].energy, energyBeforeRecall, "Manual Owl recall must not spend skill1 energy")
        maxStun = max(maxStun, owlGame.fighters[1].stun)
        if owlGame.events.contains(where: { if case .nonnaOwlHit(owner: 0, _, returned: true) = $0 { return true }; return false }) {
            returnHit = true
        }
        for _ in 0..<45 {
            owlGame.step(.neutral, opponent: .neutral)
            maxStun = max(maxStun, owlGame.fighters[1].stun)
            if owlGame.events.contains(where: { if case .nonnaOwlHit(owner: 0, _, returned: true) = $0 { return true }; return false }) {
                returnHit = true
            }
        }
        XCTAssertTrue(returnHit, "Returning Spirit Owl must strike opponent")
        XCTAssertGreaterThanOrEqual(maxStun, DuelNonnaState.owlReturnStunTicks - 2, "Returning Owl must stun opponent")
        XCTAssertEqual(owlGame.nonnaState(0)?.owlCooldown, 0, "Flame Tongues must reset Owl cooldown when both hits land")
    }

    func testNonnaFlameFormPartialActivationBreaksBlockExecutesLowHPAndLeavesGreatHearth() {
        var game = closeMatch(.liu, opponent: .ember, mode: .versus)
        // Build Flame Power >= 30 (partial bar) with real strikes.
        for tick in 0..<180 {
            if game.nonnaState(0)?.canEnterFlameForm == true { break }
            let dist = abs(game.fighters[1].x - game.fighters[0].x)
            game.step(.init(move: dist > 950 ? 1 : 0, taps: tick % 20 == 0 ? .light : []), opponent: .neutral)
        }
        settle(&game)
        let flameBefore = game.nonnaState(0)?.flamePower ?? 0
        XCTAssertGreaterThanOrEqual(flameBefore, DuelNonnaState.flameFormMinPower)
        XCTAssertLessThan(flameBefore, DuelNonnaState.maxFlamePower, "Should activate on partial bar (<100)")

        // Enter Flame Form via skill2!
        var enteredFlame = false
        game.step(.init(taps: .skill2), opponent: .neutral)
        if game.events.contains(.nonnaFlameForm(fighter: 0)) { enteredFlame = true }
        XCTAssertTrue(enteredFlame)
        XCTAssertTrue(game.nonnaState(0)?.isInFlameForm == true)

        // Sub-check A: Flame Form breaks opponent block!
        var blockGame = game
        for _ in 0..<30 where abs(blockGame.fighters[1].x - blockGame.fighters[0].x) > 950 {
            blockGame.step(.init(move: 1), opponent: .init(guardHeld: true))
        }
        var brokeGuard = false
        let hpBefore = blockGame.fighters[1].health
        blockGame.step(.init(taps: .light), opponent: .init(guardHeld: true))
        for _ in 0..<30 {
            blockGame.step(.neutral, opponent: .init(guardHeld: true))
            if blockGame.events.contains(.guardBreak(defender: 1)) { brokeGuard = true }
        }
        XCTAssertTrue(brokeGuard, "Flame Form attacks must break guard")
        XCTAssertLessThan(blockGame.fighters[1].health, hpBefore)

        // Sub-check B: Exiting Flame Form grants The Great Hearth empowered strike!
        var hearthGame = game
        while hearthGame.nonnaState(0)?.isInFlameForm == true {
            hearthGame.step(.neutral, opponent: .neutral)
        }
        XCTAssertTrue(hearthGame.nonnaState(0)?.empoweredStrikeReady == true, "The Great Hearth must remain ready after Flame Form ends")
        XCTAssertTrue(hearthGame.nonnaState(0)?.breaksBlockNow == true)

        // Sub-check C: Survival of the Fittest executes opponent under 25% HP while in Flame Form!
        var execGame = closeMatch(.liu, opponent: .ember, mode: .versus)
        // Whittle opponent down under 250 HP (non-zero), then enter Flame Form and strike!
        for tick in 0..<900 {
            if execGame.fighters[1].health > 0 && execGame.fighters[1].health < DuelNonnaState.executeThresholdHP { break }
            let dist = abs(execGame.fighters[1].x - execGame.fighters[0].x)
            execGame.step(.init(move: dist > 950 ? 1 : 0, taps: tick % 26 == 0 ? .light : []), opponent: .neutral)
        }
        settle(&execGame)
        XCTAssertGreaterThan(execGame.fighters[1].health, 0)
        XCTAssertLessThan(execGame.fighters[1].health, DuelNonnaState.executeThresholdHP)
        XCTAssertTrue(execGame.nonnaState(0)?.canEnterFlameForm == true)
        execGame.step(.init(taps: .skill2), opponent: .neutral)
        XCTAssertTrue(execGame.nonnaState(0)?.isInFlameForm == true)
        for _ in 0..<30 where abs(execGame.fighters[1].x - execGame.fighters[0].x) > 950 {
            execGame.step(.init(move: 1), opponent: .neutral)
        }
        var executed = false
        execGame.step(.init(taps: .light), opponent: .neutral)
        for _ in 0..<30 {
            execGame.step(.neutral, opponent: .neutral)
            if execGame.events.contains(where: { if case .nonnaTrueShapeExecute(attacker: 0, _) = $0 { return true }; return false }) {
                executed = true
                break
            }
        }
        XCTAssertTrue(executed, "True Shape strike on <25% HP opponent must execute instantly")
        XCTAssertEqual(execGame.fighters[1].health, 0)
    }

    // MARK: - Sun Deng (Midnight / 午夜 · 影移双刃)

    func testMidnightWhiffTriggersShadowShiftPhasesThroughAttackAndMovesFaster() {
        var game = DuelGame(hero: .ember, mode: .practice, seed: 20261121, opponentHero: .gale)
        // Whiff a jab at range -> enters Shadow Shift!
        var shifted = false
        game.step(.init(taps: .light), opponent: .neutral)
        for _ in 0..<30 {
            game.step(.neutral, opponent: .neutral)
            if game.events.contains(.midnightShadowShift(fighter: 0)) { shifted = true; break }
        }
        XCTAssertTrue(shifted, "Whiffing an attack must trigger Midnight Shadow Shift")
        XCTAssertTrue(game.midnightState(0)?.isPhasedOut == true)

        // Verify Precise Shift enhanced speed while phased!
        let xBefore = game.fighters[0].x
        game.step(.init(move: 1), opponent: .neutral)
        XCTAssertEqual(game.fighters[0].x - xBefore, DuelMidnightState.preciseShiftSpeed)

        // Verify phased-out Midnight takes ZERO damage from opponent strike & earns Best Agent Shadow Energy!
        var dodgeGame = closeMatch(.ember, opponent: .gale)
        // Step back slightly so jab whiffs cleanly, then step forward while phased into opponent's swing!
        for _ in 0..<10 { dodgeGame.step(.init(move: -1), opponent: .neutral) }
        dodgeGame.step(.init(taps: .light), opponent: .neutral)
        for _ in 0..<30 where dodgeGame.midnightState(0)?.isPhasedOut != true {
            dodgeGame.step(.neutral, opponent: .neutral)
        }
        XCTAssertTrue(dodgeGame.midnightState(0)?.isPhasedOut == true)
        let shadowBefore = dodgeGame.midnightState(0)?.shadowEnergy ?? 0
        for _ in 0..<10 where abs(dodgeGame.fighters[1].x - dodgeGame.fighters[0].x) > 950 {
            dodgeGame.step(.init(move: 1), opponent: .neutral)
        }
        let hpBefore = dodgeGame.fighters[0].health
        dodgeGame.step(.neutral, opponent: .init(taps: .light))
        for _ in 0..<16 { dodgeGame.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(dodgeGame.fighters[0].health, hpBefore, "Phased-out Midnight must take zero damage")
        XCTAssertGreaterThan(dodgeGame.midnightState(0)?.shadowEnergy ?? 0, shadowBefore, "Phasing through an attack must award Best Agent shadow energy")
    }

    func testMidnightDistantShiftBlinkCounterAndRemovalShadowForm() {
        // Sub-check A: skill1 Distant Shift triggers Shadow Shift even on hit!
        var shiftGame = closeMatch(.ember, opponent: .gale)
        var shiftedOnSkill = false
        shiftGame.step(.init(taps: .skill1), opponent: .neutral)
        for _ in 0..<60 {
            shiftGame.step(.neutral, opponent: .neutral)
            if shiftGame.events.contains(.midnightShadowShift(fighter: 0)) { shiftedOnSkill = true }
        }
        XCTAssertTrue(shiftedOnSkill, "skill1 Distant Shift must trigger Shadow Shift even after hitting")

        // Sub-check B: skill2 Blink Counter-Stance negates incoming strike, teleports behind foe, deals 150 dmg, heals +95 HP!
        var blinkGame = closeMatch(.ember, opponent: .gale, mode: .versus)
        // Take one light hit first so we can verify Blink healing!
        blinkGame.step(.neutral, opponent: .init(taps: .light))
        for _ in 0..<30 { blinkGame.step(.neutral, opponent: .neutral) }
        settle(&blinkGame)
        for _ in 0..<15 where abs(blinkGame.fighters[1].x - blinkGame.fighters[0].x) > 950 {
            blinkGame.step(.init(move: 1), opponent: .neutral)
        }
        let sunHPBefore = blinkGame.fighters[0].health
        let foeXBefore = blinkGame.fighters[1].x
        let foeHPBefore = blinkGame.fighters[1].health
        blinkGame.step(.init(taps: .skill2), opponent: .init(taps: .light))
        XCTAssertTrue(blinkGame.midnightState(0)?.isInBlinkStance == true)
        var blinked = false
        for _ in 0..<25 {
            blinkGame.step(.neutral, opponent: .neutral)
            if blinkGame.events.contains(.midnightBlinkCounter(attacker: 0, damage: DuelMidnightState.blinkCounterDamage)) {
                blinked = true
                break
            }
        }
        XCTAssertTrue(blinked, "Blink counter-stance must trigger when struck")
        XCTAssertGreaterThan(blinkGame.fighters[0].x, foeXBefore, "Blink must teleport Sun Deng behind the opponent")
        XCTAssertGreaterThan(blinkGame.fighters[0].health, sunHPBefore, "Blink counter must heal Sun Deng")
        XCTAssertEqual(blinkGame.fighters[1].health, foeHPBefore - DuelMidnightState.blinkCounterDamage)

        // Sub-check C: Build 100 Shadow Energy -> Removal teleports, burns 100% opponent energy, enters Shadow Form (+35% crit)!
        var remGame = closeMatch(.ember, opponent: .gale, mode: .practice)
        for tick in 0..<500 {
            if remGame.midnightState(0)?.canUseRemoval == true { break }
            let dist = abs(remGame.fighters[1].x - remGame.fighters[0].x)
            remGame.step(.init(move: dist > 950 ? 1 : 0, taps: tick % 18 == 0 ? .light : []), opponent: .neutral)
        }
        settle(&remGame)
        XCTAssertTrue(remGame.midnightState(0)?.canUseRemoval == true)
        // Step back to mid-range (~2000mm) so teleportation is clearly exercised!
        for _ in 0..<16 { remGame.step(.init(move: -1), opponent: .neutral) }
        XCTAssertGreaterThan(abs(remGame.fighters[1].x - remGame.fighters[0].x), 1400)

        var sawRemoval = false
        var foeEnergyAtRemoval = -1
        remGame.step(.init(taps: .ultimate), opponent: .neutral)
        XCTAssertEqual(remGame.fighters[0].attack?.move, .midnightRemoval)
        for _ in 0..<45 {
            remGame.step(.neutral, opponent: .neutral)
            if remGame.events.contains(where: { if case .midnightRemovalStrike(attacker: 0, _) = $0 { return true }; return false }) {
                sawRemoval = true
                foeEnergyAtRemoval = remGame.fighters[1].energy
            }
        }
        XCTAssertTrue(sawRemoval, "Removal must teleport onto mid-range opponent and strike")
        XCTAssertEqual(foeEnergyAtRemoval, 0, "Terror of the Shadow Squads must burn 100% opponent energy on hit")
        XCTAssertTrue(remGame.midnightState(0)?.isInShadowForm == true, "Removal must activate Midnight Shadow Form")

        // Verify Shadow Form grants +35% crit bonus on follow-up jab (75 * 135 / 100 = 101)!
        for _ in 0..<60 where remGame.fighters[1].knockdown > 0 || remGame.fighters[1].invulnerable > 0 {
            remGame.step(.init(move: abs(remGame.fighters[1].x - remGame.fighters[0].x) > 950 ? 1 : 0), opponent: .neutral)
        }
        var sawCrit = false
        remGame.step(.init(taps: .light), opponent: .neutral)
        for _ in 0..<20 {
            remGame.step(.neutral, opponent: .neutral)
            if remGame.events.contains(.shogunCritical(attacker: 0, damage: 101)) { sawCrit = true }
        }
        XCTAssertTrue(sawCrit, "Shadow Form jab must deal +35% critical damage (101)")
    }

    // MARK: - Full 4-Hero Determinism

    func testAllFourSF4HeroesAreBitForBitDeterministicAcrossReplays() throws {
        let pairs: [(DuelGame.Hero, DuelGame.Hero)] = [(.gale, .liu), (.liu, .ember), (.ember, .wuYong), (.wuYong, .gale)]
        for (hero, foe) in pairs {
            var a = DuelGame(hero: hero, difficulty: .challenging, mode: .versus, seed: 4242, opponentHero: foe)
            var b = DuelGame(hero: hero, difficulty: .challenging, mode: .versus, seed: 4242, opponentHero: foe)
            for tick in 0..<360 {
                let taps: DuelGame.Buttons = tick % 61 == 0 ? .ultimate : tick % 47 == 0 ? .skill2 : tick % 31 == 0 ? .skill1 : tick % 19 == 0 ? .heavy : tick % 13 == 0 ? .light : []
                let input = DuelGame.Input(move: tick % 80 < 50 ? 1 : -1, guardHeld: tick % 70 > 55, taps: taps)
                a.step(input); b.step(input)
                XCTAssertEqual(try DuelReplayStateEncoding.encode(a), try DuelReplayStateEncoding.encode(b), "\(hero) vs \(foe) diverged at tick \(tick)")
            }
            XCTAssertGreaterThan(a.frame, 0)
        }
    }
}
