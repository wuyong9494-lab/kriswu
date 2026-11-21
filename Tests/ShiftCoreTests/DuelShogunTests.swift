import XCTest
@testable import ShiftCore

final class DuelShogunTests: XCTestCase {
    private func closeMatch(opponent: DuelGame.Hero = .ember, mode: DuelGame.Mode = .versus) -> DuelGame {
        var game = DuelGame(hero: .wuYong, mode: mode, seed: 20261121, opponentHero: opponent)
        for _ in 0..<20 {
            game.step(.init(move: 1), opponent: .init(move: -1))
        }
        return game
    }

    func testOdachiReachComboAndShadowAccumulationAutoEntersShadowForm() {
        var game = closeMatch(mode: .practice)
        XCTAssertEqual(game.shogunState(0)?.shadowPhase, .normal)
        var enteredShadowForm = false
        var seenMoves = Set<DuelGame.Move>()
        for tick in 0..<320 {
            let dir = game.fighters[1].x > game.fighters[0].x ? 1 : -1
            let dist = abs(game.fighters[1].x - game.fighters[0].x)
            let tapLight = dist < 1300 && (tick % 4 == 0)
            game.step(.init(move: dist > 1100 ? dir : 0, taps: tapLight ? .light : []), opponent: .neutral)
            if let m = game.fighters[0].attack?.move { seenMoves.insert(m) }
            if game.events.contains(.shogunShadowForm(fighter: 0)) { enteredShadowForm = true }
            if enteredShadowForm && seenMoves.count >= 3 { break }
        }
        XCTAssertTrue(seenMoves.isSuperset(of: [.jab, .cross, .finisher]), "Expected 3-hit Odachi chain, got \(seenMoves)")
        XCTAssertTrue(enteredShadowForm, "Expected Wu Yong to automatically enter Shadow Form at 100 shadow energy")
        XCTAssertNotEqual(game.shogunState(0)?.shadowPhase, .normal)
        XCTAssertGreaterThanOrEqual(game.fighters[0].energy, DuelShogunState.shadowFormThreshold)
    }

    func testChargedHeavyExecutionProducesGuaranteedCriticalWithExtraReachAndDamage() {
        var uncharged = closeMatch(mode: .practice)
        uncharged.step(.init(taps: .heavy), opponent: .neutral)
        for _ in 0..<60 { uncharged.step(.neutral, opponent: .neutral) }

        var charged = closeMatch(mode: .practice)
        // Step back slightly so only extended charged reach shines, while still within charged reach
        charged.step(.init(taps: .heavy, heavyHeld: true), opponent: .neutral)
        for _ in 0..<DuelShogunState.heavyFullChargeTicks {
            charged.step(.init(heavyHeld: true), opponent: .neutral)
        }
        XCTAssertTrue(charged.shogunState(0)?.isHeavyFullyCharged == true)
        var sawCrit = false
        var peakHitStop = 0
        // Release heavy
        charged.step(.init(heavyHeld: false), opponent: .neutral)
        for _ in 0..<60 {
            charged.step(.neutral, opponent: .neutral)
            peakHitStop = max(peakHitStop, charged.hitStop)
            if charged.events.contains(where: { if case .shogunCritical(attacker: 0, _) = $0 { return true }; return false }) {
                sawCrit = true
            }
        }
        XCTAssertTrue(sawCrit, "Full-charged heavy must trigger guaranteed critical")
        XCTAssertGreaterThan(charged.damageDealt[0], uncharged.damageDealt[0] + 80)
        XCTAssertGreaterThanOrEqual(peakHitStop, 12, "Critical heavy must deliver heavy hitstop")
    }

    func testRuthlessAdvanceSpecialKickGrantsUnbreakableHyperArmor() {
        var game = closeMatch(mode: .practice)
        // Wu Yong triggers Ruthless Advance (skill1), opponent jabs right during Wu Yong's armor window.
        game.step(.init(taps: .skill1), opponent: .neutral)
        var absorbed = false
        var kickConnected = false
        for tick in 0..<60 {
            let foeTap: DuelGame.Buttons = tick == 2 ? .light : []
            game.step(.neutral, opponent: .init(taps: foeTap))
            if game.events.contains(.shogunArmorAbsorbed(defender: 0)) { absorbed = true }
            if game.landedHits[0] > 0 { kickConnected = true }
        }
        XCTAssertTrue(absorbed, "Ruthless Advance should absorb opponent jab with hyper-armor")
        XCTAssertTrue(kickConnected, "Wu Yong's armored kick must not be interrupted and should land")
        XCTAssertGreaterThan(game.shogunState(0)?.ruthlessKickCooldown ?? 0, 0)
    }

    func testAsyncCompanionCanCommandWhileStunnedStunsOpponentAndDrainsEnergy() {
        var game = closeMatch(mode: .practice)
        // Let companion stalk close to opponent first.
        for _ in 0..<65 { game.step(.neutral, opponent: .neutral) }
        // Opponent hits Wu Yong to put Wu Yong into hitstun.
        game.step(.neutral, opponent: .init(taps: .light))
        for _ in 0..<25 where game.fighters[0].stun == 0 {
            game.step(.neutral, opponent: .neutral)
        }
        // Wait for hitStop to clear while Wu Yong is still in hitstun.
        while game.hitStop > 0 { game.step(.neutral, opponent: .neutral) }
        XCTAssertGreaterThan(game.fighters[0].stun, 0, "Wu Yong should be in hitstun")
        let foeEnergyBefore = game.fighters[1].energy
        let wuShadowBefore = game.shogunState(0)?.shadowEnergy ?? 0

        // Command companion (skill2) WHILE STUNNED!
        game.step(.init(taps: .skill2), opponent: .neutral)
        XCTAssertEqual(game.shogunState(0)?.companionPhase, .windup, "Companion command must work during hitstun")

        var companionHit = false
        var maxFoeStun = 0
        for _ in 0..<40 {
            game.step(.neutral, opponent: .neutral)
            maxFoeStun = max(maxFoeStun, game.fighters[1].stun)
            if game.events.contains(where: { if case .shogunCompanionHit(owner: 0, _) = $0 { return true }; return false }) {
                companionHit = true
            }
        }
        XCTAssertTrue(companionHit, "Companion lunge should strike opponent")
        XCTAssertGreaterThanOrEqual(maxFoeStun, DuelShogunState.companionStunTicks - 2, "Companion must stun opponent for ~0.9s")
        XCTAssertLessThan(game.fighters[1].energy, foeEnergyBefore, "Companion must drain opponent energy")
        XCTAssertGreaterThan(game.shogunState(0)?.shadowEnergy ?? 0, wuShadowBefore, "Companion must transfer shadow energy to Wu Yong")
    }

    private func settle(_ game: inout DuelGame) {
        for _ in 0..<180 {
            if game.fighters[0].attack == nil && game.fighters[1].attack == nil &&
                game.hitStop == 0 && game.fighters[1].knockdown == 0 && game.fighters[1].invulnerable == 0 &&
                game.fighters[0].knockdown == 0 && game.fighters[0].invulnerable == 0 {
                break
            }
            game.step(.neutral, opponent: .neutral)
        }
    }

    func testShadowAbilityTriggersCataclysmAndDoubleEdgedExecutionWorksForBothSides() {
        // Helper to reach Shadow Form via real hits, then settle to neutral.
        func buildShadowForm() -> DuelGame {
            var g = closeMatch(mode: .practice)
            for tick in 0..<400 {
                if g.shogunState(0)?.shadowPhase == .shadowForm { break }
                let dist = abs(g.fighters[1].x - g.fighters[0].x)
                g.step(.init(move: dist > 1100 ? 1 : 0, taps: tick % 18 == 0 ? .light : []), opponent: .neutral)
            }
            settle(&g)
            return g
        }

        // Case 1: Cast Fierce Reprisal in Shadow Form -> heals Wu Yong, fills bar to Cataclysm, pushes foe, reloads shadow CD!
        var game = buildShadowForm()
        XCTAssertEqual(game.shogunState(0)?.shadowPhase, .shadowForm)
        for _ in 0..<80 where abs(game.fighters[1].x - game.fighters[0].x) > 1100 {
            let dir = game.fighters[1].x > game.fighters[0].x ? 1 : -1
            game.step(.init(move: dir), opponent: .neutral)
        }
        var erupted = false
        game.step(.init(move: game.fighters[0].facing, taps: .ultimate), opponent: .neutral)
        XCTAssertEqual(game.fighters[0].attack?.move, .shogunFierceReprisal)
        for _ in 0..<70 {
            game.step(.neutral, opponent: .neutral)
            if game.events.contains(.shogunCataclysm(fighter: 0)) { erupted = true }
        }
        XCTAssertTrue(erupted, "Landing Fierce Reprisal in Shadow Form must erupt Shadow Cataclysm")
        XCTAssertEqual(game.shogunState(0)?.shadowPhase, .cataclysm)
        XCTAssertEqual(game.shogunState(0)?.shadowAbilityCooldown, 0, "Foreshadowing the End must reload shadow abilities on Cataclysm")
        settle(&game)

        // Branch A: Wu Yong lands Fierce Reprisal during Cataclysm -> double bonus massive execution damage + debuffs foe!
        var wuFirst = game
        for _ in 0..<60 where abs(wuFirst.fighters[1].x - wuFirst.fighters[0].x) > 1200 {
            wuFirst.step(.init(move: wuFirst.fighters[0].facing), opponent: .neutral)
        }
        var cataclysmDamageWu = 0
        var shadowEnergyOnConsume = -1
        wuFirst.step(.init(move: wuFirst.fighters[0].facing, taps: .ultimate), opponent: .neutral)
        for _ in 0..<60 {
            wuFirst.step(.neutral, opponent: .neutral)
            for e in wuFirst.events {
                if case .shogunCataclysmStrike(attacker: 0, let dmg) = e {
                    cataclysmDamageWu = dmg
                    shadowEnergyOnConsume = wuFirst.shogunState(0)?.shadowEnergy ?? -1
                }
            }
        }
        XCTAssertGreaterThanOrEqual(cataclysmDamageWu, 500, "Fierce Reprisal during Cataclysm deals double bonus damage")
        XCTAssertEqual(wuFirst.shogunState(0)?.shadowPhase, .normal)
        XCTAssertEqual(shadowEnergyOnConsume, 0, "Shadow energy must deplete immediately to 0 when Cataclysm triggers")
        XCTAssertGreaterThan(wuFirst.shogunState(0)?.opponentDefenseDebuffTicks ?? 0, 0)

        // Branch B: Opponent lands FIRST unblocked strike during Wu Yong's Cataclysm -> double-edged sword punishes Wu Yong!
        var foeFirst = game
        for _ in 0..<60 where abs(foeFirst.fighters[1].x - foeFirst.fighters[0].x) > 950 {
            foeFirst.step(.neutral, opponent: .init(move: foeFirst.fighters[1].facing))
        }
        var cataclysmDamageFoe = 0
        foeFirst.step(.neutral, opponent: .init(taps: .heavy))
        for _ in 0..<60 {
            foeFirst.step(.neutral, opponent: .neutral)
            for e in foeFirst.events {
                if case .shogunCataclysmStrike(attacker: 1, let dmg) = e { cataclysmDamageFoe = dmg }
            }
        }
        XCTAssertGreaterThanOrEqual(cataclysmDamageFoe, 300, "Opponent landing first during Cataclysm must deal massive punish damage")
        XCTAssertEqual(foeFirst.shogunState(0)?.shadowPhase, .normal)
        XCTAssertGreaterThan(foeFirst.shogunState(0)?.defenseBonusTicks ?? 0, 0, "Possessed by Shadow buffs Wu Yong defense after taking Cataclysm hit")
    }

    func testDespotismAbsorbsFrontalAttackPullsOpponentAndLaunches() {
        var game = closeMatch(mode: .practice)
        // Reach Shadow Form, then settle to idle.
        for tick in 0..<400 {
            if game.shogunState(0)?.shadowPhase == .shadowForm { break }
            let dist = abs(game.fighters[1].x - game.fighters[0].x)
            game.step(.init(move: dist > 1100 ? 1 : 0, taps: tick % 18 == 0 ? .light : []), opponent: .neutral)
        }
        settle(&game)
        XCTAssertEqual(game.shogunState(0)?.shadowPhase, .shadowForm)

        // Sub-check A: Frontal attack during Despotism is absorbed cleanly (Overlord of Shadow).
        var absorbGame = game
        for _ in 0..<60 where abs(absorbGame.fighters[1].x - absorbGame.fighters[0].x) > 900 {
            absorbGame.step(.init(move: absorbGame.fighters[0].facing), opponent: .neutral)
        }
        let wuHPBefore = absorbGame.fighters[0].health
        absorbGame.step(.init(move: -absorbGame.fighters[0].facing, taps: .ultimate), opponent: .init(taps: .light))
        var absorbedFront = false
        for _ in 0..<30 {
            absorbGame.step(.neutral, opponent: .neutral)
            if absorbGame.events.contains(.shogunArmorAbsorbed(defender: 0)) { absorbedFront = true }
        }
        XCTAssertTrue(absorbedFront, "Despotism planted Odachi must absorb frontal attack")
        XCTAssertEqual(absorbGame.fighters[0].health, wuHPBefore, "Absorbed frontal attack must deal zero damage")

        // Sub-check B: Position at mid-range (~1750 mm) where normal jab whiffs -> Despotism pulls & launches.
        for _ in 0..<80 {
            let dist = abs(game.fighters[1].x - game.fighters[0].x)
            if dist >= 1650 && dist <= 2000 { break }
            let dir = dist > 2000 ? game.fighters[0].facing : -game.fighters[0].facing
            game.step(.init(move: dir), opponent: .neutral)
        }
        let distBefore = abs(game.fighters[1].x - game.fighters[0].x)
        XCTAssertGreaterThan(distBefore, 1400)
        XCTAssertLessThanOrEqual(distBefore, 2200)

        let hitsBefore = game.landedHits[0]
        game.step(.init(move: -game.fighters[0].facing, taps: .ultimate), opponent: .neutral)
        XCTAssertEqual(game.fighters[0].attack?.move, .shogunDespotism)
        for _ in 0..<50 { game.step(.neutral, opponent: .neutral) }
        XCTAssertGreaterThan(game.landedHits[0], hitsBefore, "Despotism should pull and strike mid-range opponent")
    }

    func testOverlordOfOppressionRevivesOnceTriggersAgonyThenUnconscious() {
        var game = closeMatch(mode: .versus)
        var revived = false
        for tick in 0..<900 {
            let dist = abs(game.fighters[1].x - game.fighters[0].x)
            game.step(.neutral, opponent: .init(move: dist > 900 ? -1 : 0, taps: tick % 30 == 0 ? .heavy : []))
            if game.events.contains(.shogunRevived(fighter: 0)) {
                revived = true
                break
            }
        }
        XCTAssertTrue(revived, "Overlord of Oppression must revive Wu Yong from lethal damage once")
        XCTAssertEqual(game.fighters[0].health, DuelShogunState.reviveHealth)
        XCTAssertTrue(game.shogunState(0)?.reviveUsed == true)
        XCTAssertGreaterThan(game.shogunState(0)?.agonyRemainingTicks ?? 0, 0)

        // Advance past Agony duration -> companion loses consciousness until round end.
        for _ in 0..<(DuelShogunState.agonyDurationTicks + 5) {
            game.step(.neutral, opponent: .neutral)
        }
        XCTAssertEqual(game.shogunState(0)?.companionPhase, .unconscious)
    }

    func testShogunMatchIsBitForBitDeterministicAcrossReplays() throws {
        var a = DuelGame(hero: .wuYong, difficulty: .challenging, mode: .versus, seed: 9911, opponentHero: .ember)
        var b = DuelGame(hero: .wuYong, difficulty: .challenging, mode: .versus, seed: 9911, opponentHero: .ember)
        for tick in 0..<500 {
            let holdHeavy = (tick >= 120 && tick < 200)
            let taps: DuelGame.Buttons = tick == 120 ? .heavy : tick % 73 == 0 ? .skill2 : tick % 51 == 0 ? .skill1 : tick % 19 == 0 ? .light : tick % 67 == 0 ? .ultimate : []
            let input = DuelGame.Input(move: tick % 90 < 55 ? 1 : -1, guardHeld: false, taps: taps, heavyHeld: holdHeavy)
            a.step(input); b.step(input)
            XCTAssertEqual(try DuelReplayStateEncoding.encode(a), try DuelReplayStateEncoding.encode(b), "Diverged at tick \(tick)")
        }
        XCTAssertGreaterThan(a.frame, 0)
    }
}
