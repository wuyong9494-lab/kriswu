import XCTest
@testable import ShiftCore

final class DuelTriadStateTests: XCTestCase {
    private func state(_ rules: DuelTriadRules = DuelTriadTestFixture.rules(), seed: UInt64 = 19) throws -> DuelTriadState {
        var value = try XCTUnwrap(DuelTriadState(rules: rules, seed: seed))
        value.beginRound(roundID: 0); return value
    }
    private func attacks(_ events: [DuelTriadState.Effect]) -> [DuelTriadState.Attack] {
        events.compactMap { if case .attack(let value) = $0 { return value }; return nil }
    }
    private func pulses(_ events: [DuelTriadState.Effect]) -> [DuelTriadState.DamagePulse] {
        events.compactMap { if case .damagePulse(let value) = $0 { return value }; return nil }
    }
    @discardableResult private func advance(_ value: inout DuelTriadState, _ ticks: Int) -> [DuelTriadState.Effect] {
        var events: [DuelTriadState.Effect] = []
        for _ in 0..<ticks { events += value.step() }
        return events
    }
    @discardableResult private func release(_ ability: DuelTriadRules.Ability, _ value: inout DuelTriadState) -> [DuelTriadState.Effect] {
        let events = value.start(ability)
        let released = events + advance(&value, value.rules.ability(ability)!.startupTicks)
        let delay = attacks(released).map(\.activationDelayTicks).max() ?? 0
        return released + advance(&value, delay)
    }
    private func finishCast(_ value: inout DuelTriadState) {
        if let cast = value.activeCast { advance(&value, cast.duration - cast.tick) }
    }
    private func bytes(_ value: DuelTriadState) throws -> Data {
        var writer = try DuelReplayStateWriter(kind: 2)
        try value.appendReplayState(to: &writer); return writer.data
    }

    func testProductionSuppressionUsesOpponentMaximumHealthAndPreservesNonlethalBoundary() throws {
        var value = try state(DuelTriadTestFixture.runtimeRules(level: 2))
        value.configureOpponent(armor: .unknown, weapon: .unknown, maximumHealth: 2500)
        let wave = try XCTUnwrap(attacks(release(.mistOnslaught, &value)).first)
        _ = value.contact(attackID: wave.id, context: .init(), eventID: 1)
        let dots = pulses(advance(&value, 480)).filter { $0.kind == .suppression }
        XCTAssertEqual(dots.reduce(0) { $0 + $1.damage }, 100, "4% of opponent maxHP, not own 900 HP")
        XCTAssertTrue(dots.allSatisfy(\.nonlethal))
        XCTAssertTrue(dots.allSatisfy { $0.healthDamage(health: 1) == 0 })
        XCTAssertEqual(value.suppressionStacks, 0)
    }

    func testProductionStatusesWaitForTenTickBatchesAndDoNotDamageDuringPause() throws {
        var value = try state(DuelTriadTestFixture.runtimeRules(level: 2))
        value.configureOpponent(armor: .unknown, weapon: .unknown, maximumHealth: 12_000)
        let wave = try XCTUnwrap(attacks(release(.mistOnslaught, &value)).first)
        _ = value.contact(attackID: wave.id, context: .init(), eventID: 1)
        let snapshot = value
        XCTAssertEqual(snapshot, value)
        XCTAssertTrue(pulses(advance(&value, 9)).isEmpty)
        XCTAssertEqual(pulses(value.step()).map(\.damage), [10])
        XCTAssertTrue(pulses(advance(&value, 9)).isEmpty)
        XCTAssertEqual(pulses(value.step()).map(\.damage), [10])
    }

    func testProductionSuppressionDoesNotInventMissingOpponentMaximumHealth() throws {
        var value = try state(DuelTriadTestFixture.runtimeRules(level: 2))
        let wave = try XCTUnwrap(attacks(release(.mistOnslaught, &value)).first)
        _ = value.contact(attackID: wave.id, context: .init(), eventID: 1)
        XCTAssertEqual(value.suppressionStacks, 1)
        XCTAssertTrue(pulses(advance(&value, 480)).isEmpty)
        XCTAssertNil(value.opponentMaximumHealth)
    }

    func testProductionBladeDotSnapshotsItsOnePointThreeThreeMultiplier() throws {
        var value = try state(DuelTriadTestFixture.runtimeRules(level: 2))
        value.configureOpponent(armor: .unknown, weapon: .unknown, maximumHealth: 2500)
        value.weaponContact(blocked: false, critical: true, eventID: 1)
        release(.mistBlade, &value); finishCast(&value)
        let wave = try XCTUnwrap(attacks(release(.mistOnslaught, &value)).first)
        XCTAssertFalse(wave.blockable)
        _ = value.contact(attackID: wave.id, context: .init(blocked: true), eventID: 1)
        let dots = pulses(advance(&value, 480)).filter { $0.kind == .suppression }
        XCTAssertEqual(dots.reduce(0) { $0 + $1.damage }, 133)
    }

    func testProductionMistHitsRefreshOnePulseClockWithoutResettingOrStackingIt() throws {
        var value = try state(DuelTriadTestFixture.runtimeRules(level: 2))
        let wave = try XCTUnwrap(attacks(release(.mistOnslaught, &value)).first)
        _ = value.contact(attackID: wave.id, context: .init(), eventID: 1)
        advance(&value, 1)
        XCTAssertEqual(value.mist, 0, "The invisible wave itself is excluded by trigger 38/39")
        value.weaponContact(blocked: false, critical: false, eventID: 1)
        advance(&value, 1); XCTAssertEqual(value.mist, 110)
        for tick in 1...9 {
            value.weaponContact(blocked: false, critical: false, eventID: UInt64(tick + 1))
            advance(&value, 1)
        }
        XCTAssertEqual(value.mist, 110, "Repeated hits cannot create nine new recovery streams")
        advance(&value, 1); XCTAssertEqual(value.mist, 220, "The original pulse was not postponed by refreshes")
        advance(&value, 290)
        XCTAssertEqual(value.mist, 3410, "The refreshed expiry permits exactly one additional pulse")
    }

    func testProductionLevelFiveWritesFortyFivePercentRatherThanMultiplyingDisplayBonus() throws {
        var value = try state(DuelTriadTestFixture.runtimeRules(level: 5))
        let wave = try XCTUnwrap(attacks(release(.mistOnslaught, &value)).first)
        _ = value.contact(attackID: wave.id, context: .init(), eventID: 1)
        value.weaponContact(blocked: false, critical: false, eventID: 1)
        advance(&value, 300)
        XCTAssertEqual(value.mist, 4500)
    }

    func testProductionSuppressionReductionIsSingleDespiteMultipleDotInstances() throws {
        var value = try state(DuelTriadTestFixture.runtimeRules(level: 2))
        for event in 1...2 {
            let wave = try XCTUnwrap(attacks(release(.mistOnslaught, &value)).first)
            _ = value.contact(attackID: wave.id, context: .init(), eventID: UInt64(event))
            finishCast(&value)
        }
        XCTAssertEqual(value.suppressionStacks, 2)
        XCTAssertEqual(value.opponentOutgoingDamage(1000, kind: .weapon), 700)
        XCTAssertEqual(value.opponentOutgoingDamage(1000, kind: .shadow), 700)
        XCTAssertEqual(value.opponentOutgoingDamage(1000, kind: .trueDamage), 1000)
    }

    func testProductionPersonalFactorReductionsAddAndClampAtTenPercent() throws {
        var rules = try DuelTriadTestFixture.runtimeRules(level: 3)
        rules.forest.curseChanceBps = 10_000
        var value = try state(rules)
        value.configureOpponent(armor: .legion, weapon: .legion)
        XCTAssertEqual(value.opponentOutgoingDamage(1000, kind: .weapon), 680)
        XCTAssertEqual(value.opponentOutgoingDamage(1000, kind: .shadow), 600)
        let wave = try XCTUnwrap(attacks(release(.mistOnslaught, &value)).first)
        _ = value.contact(attackID: wave.id, context: .init(), eventID: 1)
        XCTAssertEqual(value.opponentOutgoingDamage(1000, kind: .weapon), 380)
        _ = value.opponentUsedShadowMove(eventID: 1)
        XCTAssertEqual(value.opponentOutgoingDamage(1000, kind: .weapon), 100)
        XCTAssertEqual(value.opponentOutgoingDamage(1000, kind: .shadow), 300)
        XCTAssertEqual(value.opponentOutgoingDamage(1000, kind: .trueDamage), 1000)
    }

    func testProductionTangibleWaveKeepsItsModelButLosesExpiredBladeDamageBonus() throws {
        var rules = try DuelTriadTestFixture.runtimeRules(level: 2)
        rules.blade.durationTicks = 80
        var value = try state(rules)
        value.weaponContact(blocked: false, critical: true, eventID: 1)
        release(.mistBlade, &value); finishCast(&value)
        let wave = try XCTUnwrap(attacks(release(.mistOnslaught, &value)).first)
        XCTAssertTrue(wave.empowered)
        XCTAssertEqual(wave.damage, 264)
        advance(&value, value.mistBladeRemainingTicks)
        let receipt = value.contact(attackID: wave.id, context: .init(), eventID: 1)
        XCTAssertTrue(receipt.accepted)
        XCTAssertEqual(receipt.damage, 132)
        XCTAssertTrue(receipt.attack?.empowered == true)
    }

    func testProductionSoulEvaluatesBladeAtContactIncludingCriticalRounding() throws {
        var rules = try DuelTriadTestFixture.runtimeRules(level: 4)
        rules.mist.initial = rules.mist.maximum
        var value = try state(rules)
        value.weaponContact(blocked: false, critical: true, eventID: 1)
        let soul = try XCTUnwrap(attacks(release(.herald, &value)).first)
        XCTAssertFalse(soul.empowered)
        XCTAssertEqual(soul.damage, 288)
        release(.mistBlade, &value)
        let receipt = value.contact(attackID: soul.id, context: .init(), eventID: 1)
        XCTAssertTrue(receipt.accepted)
        XCTAssertEqual(receipt.damage, 577)
    }

    func testProductionRootsKeepInitialDamageAndAddFailedReactionDamageOneTickLater() throws {
        var caught = try state(DuelTriadTestFixture.runtimeRules(level: 2))
        let root = try XCTUnwrap(attacks(release(.branches, &caught)).first)
        let receipt = caught.contact(attackID: root.id, context: .init(), eventID: 1)
        XCTAssertEqual(receipt.damage, 165)
        XCTAssertEqual(caught.rootRemainingTicks, 180)
        var escaped = try state(DuelTriadTestFixture.runtimeRules(level: 2))
        let failed = try XCTUnwrap(attacks(release(.branches, &escaped)).first)
        let miss = escaped.contact(attackID: failed.id, context: .init(airborne: true), eventID: 1)
        XCTAssertEqual(miss.damage, 165)
        XCTAssertTrue(pulses(miss.effects).isEmpty)
        let extra = pulses(escaped.step())
        XCTAssertEqual(extra.map(\.damage), [206])
        XCTAssertEqual(extra.map(\.damageKind), [.trueDamage])
        XCTAssertEqual(escaped.rootRemainingTicks, 0)
    }

    func testProductionBladeAddsShadowDamageWithoutRemovingItsPhysicalHit() throws {
        var value = try state(DuelTriadTestFixture.runtimeRules(level: 2))
        value.weaponContact(blocked: false, critical: true, eventID: 1)
        release(.mistBlade, &value)
        let hit = value.weaponDamage(100)
        XCTAssertEqual(hit.weapon, 200)
        XCTAssertEqual(hit.shadow, 180, "SetHit.Damage copies the resolved weapon hit without another MagicPower bonus")
    }

    func testSourceRootAppearsBeforeDamageAndUsesEarlyAnimationEndForOwnerStages() throws {
        var value = try state(DuelTriadTestFixture.runtimeRules(level: 2))
        value.start(.branches)
        XCTAssertEqual(value.ownerMotion?.animation, .branchesStart)
        XCTAssertEqual(value.ownerMotion?.lastSampleTick, 76)
        XCTAssertEqual(value.ownerMotion?.endEventTick, 68)
        let root = try XCTUnwrap(attacks(advance(&value, 42)).first)
        XCTAssertEqual(root.activationDelayTicks, 22)
        XCTAssertFalse(value.contact(attackID: root.id, context: .init(), eventID: 1).accepted)
        advance(&value, 21)
        XCTAssertFalse(value.contact(attackID: root.id, context: .init(), eventID: 1).accepted)
        advance(&value, 1)
        XCTAssertTrue(value.contact(attackID: root.id, context: .init(), eventID: 1).accepted)
        advance(&value, 4)
        XCTAssertEqual(value.ownerMotion?.animation, .branchesLoop)
        XCTAssertEqual(value.ownerMotion?.tick, 0)
        advance(&value, 176)
        XCTAssertEqual(value.rootRemainingTicks, 0)
        XCTAssertEqual(value.ownerMotion?.animation, .branchesLoop)
        advance(&value, 8)
        XCTAssertEqual(value.ownerMotion?.animation, .branchesEnd)
        XCTAssertTrue(value.movementLocked)
        advance(&value, 28)
        XCTAssertFalse(value.movementLocked); XCTAssertTrue(value.weaponAttacksLocked)
        advance(&value, 24)
        XCTAssertFalse(value.weaponAttacksLocked)
        advance(&value, 9)
        XCTAssertNil(value.ownerMotion); XCTAssertNil(value.activeCast)
    }

    func testSourceLevelFourRootOwnerEndsWhileTheOpponentRemainsRooted() throws {
        var value = try state(DuelTriadTestFixture.runtimeRules(level: 4))
        let root = try XCTUnwrap(attacks(release(.branches, &value)).first)
        _ = value.contact(attackID: root.id, context: .init(), eventID: 1)
        advance(&value, 4)
        XCTAssertEqual(value.ownerMotion?.animation, .branchesEnd)
        XCTAssertEqual(value.rootRemainingTicks, 176)
        advance(&value, 61)
        XCTAssertNil(value.ownerMotion)
        XCTAssertEqual(value.rootRemainingTicks, 115)
        XCTAssertFalse(value.weaponAttacksLocked); XCTAssertFalse(value.movementLocked)
    }

    func testSourceWaveComboPreservesItsFrameAndSpendsChargesOnlyAtTransitions() throws {
        var value = try state(DuelTriadTestFixture.runtimeRules())
        value.start(.mistOnslaught)
        XCTAssertTrue(value.requestOnslaughtContinuation())
        XCTAssertFalse(value.requestOnslaughtContinuation())
        XCTAssertEqual(value.onslaughtCharges, 2)
        let first = attacks(advance(&value, 26))
        XCTAssertEqual(first.count, 1); XCTAssertEqual(first.first?.activationDelayTicks, 4)
        advance(&value, 26)
        XCTAssertEqual(value.ownerMotion?.animation, .mistOnslaught2)
        XCTAssertEqual(value.ownerMotion?.tick, 52)
        XCTAssertEqual(value.onslaughtCharges, 1)
        XCTAssertTrue(value.requestOnslaughtContinuation())
        XCTAssertEqual(attacks(advance(&value, 22)).count, 1)
        advance(&value, 18)
        XCTAssertEqual(value.ownerMotion?.animation, .mistOnslaught3)
        XCTAssertEqual(value.ownerMotion?.tick, 92)
        XCTAssertEqual(value.onslaughtCharges, 0)
        XCTAssertEqual(attacks(advance(&value, 20)).count, 1)
        let last = try XCTUnwrap(attacks(advance(&value, 2)).first)
        XCTAssertEqual(last.origin, .lastWave)
        XCTAssertEqual(value.rootRemainingTicks, 0, "A released final wave is not a confirmed hit")
        advance(&value, 4)
        let receipt = value.contact(attackID: last.id, context: .init(), eventID: 1)
        let roots = try XCTUnwrap(attacks(receipt.effects).first)
        XCTAssertEqual(roots.origin, .entangled)
        XCTAssertEqual(roots.activationDelayTicks, 22)
        advance(&value, 22)
        XCTAssertTrue(value.contact(attackID: roots.id, context: .init(), eventID: 2).accepted)
        XCTAssertEqual(value.rootRemainingTicks, 120)
    }

    func testSourceOneRemainingChargeDoesNotInventTheThirdComboDoubleWave() throws {
        var rules = try DuelTriadTestFixture.runtimeRules(); rules.blade.initialOnslaughtCharges = 1
        var value = try state(rules)
        value.start(.mistOnslaught)
        XCTAssertFalse(value.requestOnslaughtContinuation())
        let all = attacks(advance(&value, 101))
        XCTAssertEqual(all.count, 1); XCTAssertEqual(all.first?.origin, .manual)
        XCTAssertNil(value.ownerMotion)
    }

    private func chargedSourceDanceState() throws -> DuelTriadState {
        var rules = try DuelTriadTestFixture.runtimeRules()
        // Only charging setup is synthetic; the source Dance sequence and
        // original appearance/attack timings remain unmodified.
        rules.souls.sharedCooldownTicks = 0
        let i = try XCTUnwrap(rules.abilities.firstIndex { $0.ability == .dynast })
        rules.abilities[i].cooldownTicks = 0; rules.abilities[i].mistCost = 0
        var value = try state(rules)
        for _ in 0..<18 { value.start(.dynast) }
        advance(&value, 70)
        XCTAssertEqual(value.notches, 18)
        return value
    }

    func testSourceDanceMissUsesInAndOutWithoutInventingTheRemainingFiveSummons() throws {
        var value = try chargedSourceDanceState()
        let start = value.start(.cryingDance)
        let first = start.compactMap { event -> DuelTriadRules.SummonMove? in
            if case .sourceSoulAppeared(let soul) = event { return soul.move }; return nil
        }
        XCTAssertEqual(first, [.danceNinjato]); XCTAssertEqual(value.notches, 1)
        XCTAssertFalse(value.impactImmune)
        let later = advance(&value, 22)
        XCTAssertEqual(value.ownerMotion?.animation, .cryingDanceOut)
        XCTAssertFalse(later.contains { if case .sourceSoulAppeared = $0 { return true }; return false })
        advance(&value, 65)
        XCTAssertNil(value.ownerMotion); XCTAssertEqual(value.notches, 1)
    }

    func testSourceDanceHitSchedulesSixDistinctMovesAndPairedNinjatoMotionAtTheirOriginalDelays() throws {
        var value = try chargedSourceDanceState()
        value.start(.cryingDance)
        let first = try XCTUnwrap(attacks(advance(&value, 4)).first)
        XCTAssertEqual(first.summonMove, .danceNinjato)
        let receipt = value.contact(attackID: first.id, context: .init(), eventID: 1)
        XCTAssertTrue(receipt.effects.contains(.sourceSoulMotion(summonID: first.summonID!, animation: .ninjatoActiveStart)))
        var appearances: [(Int, DuelTriadRules.SummonMove)] = []
        var phases: [(Int, DuelTriadRules.SoulAnimation)] = []
        for tick in 1...363 {
            for event in value.step() {
                if case .sourceSoulAppeared(let soul) = event, soul.origin == .dance { appearances.append((tick, soul.move)) }
                if case .sourceSoulMotion(_, let animation) = event { phases.append((tick, animation)) }
            }
        }
        XCTAssertEqual(appearances.map(\.0), [90, 180, 270, 360, 363])
        XCTAssertEqual(appearances.map(\.1), [.danceWhirl, .danceBlast, .danceThud, .danceRift1, .danceRift2])
        XCTAssertEqual(phases.map(\.0), [50]); XCTAssertEqual(phases.map(\.1), [.ninjatoActiveEnd])
        XCTAssertEqual(value.notches, 6)
        XCTAssertEqual(value.ownerMotion?.animation, .cryingDanceLoop)
        XCTAssertTrue(value.impactImmune)
        advance(&value, 183)
        XCTAssertEqual(value.ownerMotion?.animation, .cryingDanceOut)
        XCTAssertFalse(value.impactImmune)
    }

    func testSourceForestRainUsesSixIndependentBowmenThenHammerAndRespectsWallGates() throws {
        for (frontRoom, backRoom, expectedCount) in [(1000, 1000, 7), (150, 251, 3)] {
            var value = try state(DuelTriadTestFixture.runtimeRules())
            value.configureSummonSpace(opponentFrontRoomSourceUnits: frontRoom, opponentBackRoomSourceUnits: backRoom)
            let root = try XCTUnwrap(attacks(release(.branches, &value)).first)
            _ = value.contact(attackID: root.id, context: .init(), eventID: 1)
            var seen: [(Int, DuelTriadRules.SummonMove)] = []
            for tick in 1...142 {
                for event in value.step() {
                    if case .sourceSoulAppeared(let soul) = event, soul.origin == .forestRain { seen.append((tick, soul.move)) }
                }
            }
            XCTAssertEqual(seen.count, expectedCount)
            XCTAssertEqual(value.notches, expectedCount)
            XCTAssertEqual(seen.last?.0, 142); XCTAssertEqual(seen.last?.1, .legionHammer)
            if expectedCount == 7 {
                XCTAssertEqual(seen.map(\.0), [31, 31, 60, 60, 90, 90, 142])
                XCTAssertEqual(seen.map(\.1), [.rainCloseFront, .rainCloseBack, .rainMediumFront,
                    .rainMediumBack, .rainFarFront, .rainFarBack, .legionHammer])
            }
        }
    }

    func testSourceDefenderSuppressesImpactForOneTickWithoutErasingIncomingDamageOrAttacking() throws {
        var value = try state(DuelTriadTestFixture.runtimeRules())
        let receipt = value.defendAgainstIncomingAttack(whileAttacking: false, eventID: 1)
        XCTAssertTrue(receipt.accepted); XCTAssertFalse(receipt.deflected)
        XCTAssertTrue(value.impactImmune)
        XCTAssertTrue(attacks(receipt.effects).isEmpty)
        XCTAssertTrue(receipt.effects.contains { if case .sourceSoulAppeared(let s) = $0 { return s.move == .legionDefender }; return false })
        XCTAssertEqual(value.notches, 1)
        advance(&value, 1); XCTAssertFalse(value.impactImmune)
        XCTAssertTrue(value.defendAgainstIncomingAttack(whileAttacking: true, eventID: 2).effects.isEmpty)
    }

    func testSourceCriticalUsesBlackWeaponAttributeAndHeraldSoulCommonCriticalSeparately() throws {
        var rules = try DuelTriadTestFixture.runtimeRules(level: 4); rules.mist.initial = 10_000
        var value = try state(rules)
        XCTAssertEqual(value.weaponDamage(100).total, 120, "2.5 weapon critical × source self factor .48")
        value.weaponContact(blocked: false, critical: false, eventID: 1)
        XCTAssertEqual(value.weaponDamage(100).total, 100)
        let soul = try XCTUnwrap(attacks(release(.herald, &value)).first)
        XCTAssertTrue(soul.critical); XCTAssertEqual(soul.damage, 288, ".15 MagicPower ×1.1 L1 ×1.75 common critical")
        XCTAssertNil(value.ownerMotion)
    }

    func testRoundStartsOnceAndL1DoesNotAcquireTheTriadPuppetAbilities() throws {
        var value = try XCTUnwrap(DuelTriadState(rules: DuelTriadTestFixture.rules(), seed: 7))
        XCTAssertFalse(value.canUse(.mistOnslaught))
        XCTAssertEqual(value.beginRound(roundID: 3), [.forestStarted(roundID: 3)])
        XCTAssertTrue(value.isCursed); XCTAssertTrue(value.breakthroughReady)
        let before = value
        XCTAssertTrue(value.beginRound(roundID: 3).isEmpty)
        XCTAssertTrue(value.beginRound(roundID: 2).isEmpty)
        XCTAssertEqual(value, before)
        let one = try state(DuelTriadTestFixture.rules(level: 1))
        XCTAssertFalse(one.isCursed); XCTAssertFalse(one.breakthroughReady)
        XCTAssertTrue(DuelTriadRules.Ability.allCases.allSatisfy { !one.canUse($0) })
    }

    func testBreakthroughSurvivesWhiffsAndConfirmsOneCriticalWithoutInventingDamageBonus() throws {
        var value = try state(DuelTriadTestFixture.rules(level: 2))
        let prepared = value.weaponDamage(100)
        XCTAssertEqual(prepared.total, 100); XCTAssertTrue(prepared.critical); XCTAssertTrue(prepared.bypassesBlock)
        value.weaponAttackStarted(eventID: 1); advance(&value, 20)
        XCTAssertTrue(value.breakthroughReady, "An accepted attack start or elapsed time is not a hit")
        XCTAssertFalse(value.mistBladeUnlocked)
        value.weaponContact(blocked: true, critical: false, eventID: 1)
        XCTAssertTrue(value.breakthroughReady)
        value.weaponContact(blocked: false, critical: false, eventID: 2)
        XCTAssertFalse(value.breakthroughReady); XCTAssertTrue(value.mistBladeUnlocked)
        let after = value
        value.weaponContact(blocked: false, critical: true, eventID: 2)
        value.weaponContact(blocked: false, critical: true, eventID: 1)
        XCTAssertEqual(value, after)
        XCTAssertFalse(value.weaponDamage(100).critical)
        XCTAssertEqual(value.weaponDamage(100).total, 100)
    }

    func testMistBladeRequiresConfirmedCriticalAndExpiresBackToBreakthroughAtItsExactBoundary() throws {
        var value = try state(DuelTriadTestFixture.rules(level: 2))
        XCTAssertFalse(value.canUse(.mistBlade)); XCTAssertTrue(value.start(.mistBlade).isEmpty)
        value.weaponContact(blocked: false, critical: false, eventID: 1)
        let start = release(.mistBlade, &value)
        XCTAssertTrue(start.contains(.mistBladeStarted(durationTicks: 6)))
        XCTAssertEqual(value.mistBladeRemainingTicks, 6)
        let damage = value.weaponDamage(100)
        XCTAssertEqual(damage.weapon, 90); XCTAssertEqual(damage.shadow, 30)
        XCTAssertFalse(damage.critical)
        finishCast(&value)
        XCTAssertFalse(value.canUse(.mistBlade), "An active buff cannot be refreshed by another critical")
        advance(&value, 3); XCTAssertEqual(value.mistBladeRemainingTicks, 1)
        XCTAssertEqual(value.step().filter { $0 == .mistBladeEnded }, [.mistBladeEnded])
        XCTAssertTrue(value.breakthroughReady); XCTAssertFalse(value.mistBladeUnlocked)
        XCTAssertEqual(value.weaponDamage(100).weapon, 100)
    }

    func testUntangibleWaveSuppressesWithoutDirectDamageHitStopOrFalseCritical() throws {
        var value = try state(DuelTriadTestFixture.rules(level: 2))
        let wave = try XCTUnwrap(attacks(release(.mistOnslaught, &value)).first)
        XCTAssertEqual(wave.damage, 0); XCTAssertEqual(wave.blockedDamage, 0)
        XCTAssertFalse(wave.blockable); XCTAssertFalse(wave.critical)
        XCTAssertEqual(wave.stunTicks, 0); XCTAssertEqual(wave.hitStopTicks, 0)
        XCTAssertFalse(wave.knocksDown)
        let hit = value.contact(attackID: wave.id, context: .init(blocked: true), eventID: 1)
        XCTAssertTrue(hit.accepted); XCTAssertFalse(hit.blocked); XCTAssertEqual(hit.damage, 0)
        XCTAssertEqual(value.suppressionStacks, 1)
        XCTAssertEqual(value.suppressionRemainingTicks, 8)
        let before = value
        XCTAssertFalse(value.contact(attackID: wave.id, context: .init(), eventID: 2).accepted)
        XCTAssertEqual(value, before, "One consumed volume cannot reapply suppression with a different contact ID")
    }

    func testEmpoweredWaveDealsItsSnapshotDamageAndDoesNotFallBackToIntangibleAtContact() throws {
        var rules = DuelTriadTestFixture.rules(level: 2); rules.blade.durationTicks = 3
        var value = try state(rules)
        value.weaponContact(blocked: false, critical: false, eventID: 1)
        release(.mistBlade, &value); finishCast(&value)
        let wave = try XCTUnwrap(attacks(release(.mistOnslaught, &value)).first)
        XCTAssertTrue(wave.empowered); XCTAssertEqual(wave.damage, 30)
        XCTAssertEqual(value.mistBladeRemainingTicks, 0)
        let hit = value.contact(attackID: wave.id, context: .init(), eventID: 1)
        XCTAssertEqual(hit.damage, 30); XCTAssertTrue(wave.blockable)
    }

    func testLastChargeEmitsTwoDistinctWavesAndThirdCastCanReleaseOneEntangledRoot() throws {
        var value = try state()
        var released: [DuelTriadState.Attack] = []
        for _ in 0..<3 {
            released += attacks(release(.mistOnslaught, &value))
            released += attacks(advance(&value, 2))
        }
        XCTAssertEqual(value.onslaughtCharges, 0)
        XCTAssertEqual(released.filter { $0.delivery == .mistWave }.count, 4)
        XCTAssertEqual(released.filter { $0.origin == .entangled && $0.delivery == .roots }.count, 1)
        XCTAssertEqual(Set(released.map(\.id)).count, released.count)
        advance(&value, 30)
        XCTAssertFalse(value.canUse(.mistOnslaught), "Source has contact grants, not an invented periodic charge refill")
    }

    func testExplicitChainResetPreventsUnrelatedThirdCastsFromCreatingEntangledRoots() throws {
        var value = try state()
        release(.mistOnslaught, &value); finishCast(&value)
        value.weaponAttackStarted(eventID: 1)
        var events: [DuelTriadState.Effect] = []
        for _ in 0..<2 {
            events += release(.mistOnslaught, &value); events += advance(&value, 2)
        }
        XCTAssertFalse(attacks(events).contains { $0.origin == .entangled })
        XCTAssertEqual(attacks(events).filter { $0.delivery == .mistWave }.count, 3)
        var expiry = DuelTriadTestFixture.rules(); expiry.blade.chainWindowTicks = 1
        var expired = try state(expiry); var all: [DuelTriadState.Effect] = []
        for _ in 0..<3 { all += release(.mistOnslaught, &expired); all += advance(&expired, 2) }
        XCTAssertFalse(attacks(all).contains { $0.origin == .entangled })
    }

    func testRootContactLocksOnlyLowLevelPuppetAndDamageArrivesOnConfiguredPulseIntervals() throws {
        var value = try state(DuelTriadTestFixture.rules(level: 2))
        let root = try XCTUnwrap(attacks(release(.branches, &value)).first)
        XCTAssertEqual(value.rootRemainingTicks, 0, "A cast release has not yet caught an opponent")
        let hit = value.contact(attackID: root.id, context: .init(), eventID: 1)
        XCTAssertEqual(hit.damage, 0); XCTAssertTrue(value.weaponAttacksLocked); XCTAssertTrue(value.movementLocked)
        XCTAssertTrue(hit.effects.contains(.control(.init(sourceID: root.id, kind: .root, durationTicks: 6))))
        XCTAssertTrue(pulses(value.step()).isEmpty)
        let second = pulses(value.step()); XCTAssertEqual(second.map(\.damage), [10])
        XCTAssertEqual(second.first?.kind, .branches)
        let rest = advance(&value, 4)
        XCTAssertEqual(pulses(rest).map(\.damage), [10, 10])
        XCTAssertTrue(rest.contains(.controlReleased(sourceID: root.id, kind: .root)))
        XCTAssertFalse(value.weaponAttacksLocked); XCTAssertEqual(value.rootRemainingTicks, 0)
    }

    func testJumpRollAndShadowDamageUnbreakableProduceOnlyBranchBurst() throws {
        for context in [DuelTriadState.ContactContext(airborne: true), .init(rolling: true), .init(shadowDamageUnbreakable: true)] {
            var value = try state()
            let root = try XCTUnwrap(attacks(release(.branches, &value)).first)
            let hit = value.contact(attackID: root.id, context: context, eventID: 1)
            XCTAssertEqual(hit.damage, 40); XCTAssertEqual(value.rootRemainingTicks, 0)
            XCTAssertFalse(hit.effects.contains { if case .control = $0 { return true }; return false })
            XCTAssertFalse(hit.effects.contains { if case .soulSummoned = $0 { return true }; return false })
        }
    }

    func testAdultBranchesFreeTheWeaponAndActiveRootCannotBeResummoned() throws {
        var value = try state(DuelTriadTestFixture.rules(level: 4))
        let root = try XCTUnwrap(attacks(release(.branches, &value)).first)
        finishCast(&value)
        XCTAssertFalse(value.canUse(.branches), "An unresolved root volume also owns the single-root slot")
        value.contact(attackID: root.id, context: .init(), eventID: 1)
        XCTAssertFalse(value.weaponAttacksLocked); XCTAssertFalse(value.movementLocked)
        XCTAssertFalse(value.canUse(.branches))
        value.weaponContact(blocked: false, critical: false, eventID: 1)
        XCTAssertEqual(value.rootRemainingTicks, 6, "Unrelated attacks do not cancel a caught root")
        advance(&value, 6); XCTAssertTrue(value.canUse(.branches))
    }

    func testForestRainIsTriggeredByRootCatchAndCountsActualSummonsRatherThanHits() throws {
        var value = try state()
        release(.mistOnslaught, &value); finishCast(&value)
        XCTAssertEqual(value.onslaughtCharges, 2)
        let root = try XCTUnwrap(attacks(release(.branches, &value)).first)
        let caught = value.contact(attackID: root.id, context: .init(), eventID: 1)
        XCTAssertEqual(value.onslaughtCharges, 3)
        XCTAssertEqual(value.notches, 1)
        var summons = attacks(caught.effects).filter { $0.origin == .forestRain }
        summons += attacks(advance(&value, 4)).filter { $0.origin == .forestRain }
        XCTAssertEqual(summons.map(\.ability), [.legionary, .herald, .dynast])
        XCTAssertEqual(value.notches, 3, "Missed souls still were summoned; no contact is invented")
        let after = value
        XCTAssertFalse(value.contact(attackID: root.id, context: .init(), eventID: 2).accepted)
        XCTAssertEqual(value, after)
    }

    func testEntangledRootUsesShorterHoldAndExactlyItsSingleDynast() throws {
        var value = try state(); var root: DuelTriadState.Attack?
        for _ in 0..<3 {
            root = attacks(release(.mistOnslaught, &value)).first { $0.origin == .entangled } ?? root
            advance(&value, 2)
        }
        let hit = value.contact(attackID: try XCTUnwrap(root).id, context: .init(), eventID: 1)
        XCTAssertEqual(value.rootRemainingTicks, 4)
        XCTAssertEqual(attacks(hit.effects).map(\.ability), [.dynast])
        XCTAssertEqual(value.notches, 1)
        XCTAssertFalse(attacks(advance(&value, 4)).contains { $0.origin == .forestRain })
    }

    func testRootSoulBonusUsesActualContactStateInsteadOfBirthState() throws {
        var value = try state(DuelTriadTestFixture.rules(level: 4))
        let root = try XCTUnwrap(attacks(release(.branches, &value)).first)
        value.contact(attackID: root.id, context: .init(), eventID: 1); finishCast(&value)
        let soul = try XCTUnwrap(attacks(release(.legionary, &value)).first)
        var late = value
        XCTAssertEqual(value.contact(attackID: soul.id, context: .init(), eventID: 2).damage, 30)
        advance(&late, late.rootRemainingTicks)
        XCTAssertEqual(late.contact(attackID: soul.id, context: .init(), eventID: 2).damage, 20)
    }

    func testSoulsSpendMistAndHaveIndependentCooldownsWithNoMissRefund() throws {
        var value = try state()
        let before = value.mist
        let a = attacks(release(.legionary, &value))
        XCTAssertEqual(a.count, 1); XCTAssertEqual(value.mist, before - 10)
        finishCast(&value)
        XCTAssertFalse(value.canUse(.legionary)); XCTAssertTrue(value.canUse(.herald))
        release(.herald, &value); finishCast(&value)
        XCTAssertEqual(value.mist, before - 20)
        advance(&value, 3)
        XCTAssertTrue(value.canUse(.legionary))
        var empty = DuelTriadTestFixture.rules(); empty.mist.initial = 9
        var insufficient = try state(empty); let snapshot = insufficient
        XCTAssertTrue(insufficient.start(.dynast).isEmpty); XCTAssertEqual(insufficient, snapshot)
    }

    func testSuppressionStacksDealsExactNonlethalTotalAndExpiresAtBoundary() throws {
        var rules = DuelTriadTestFixture.rules(level: 4)
        rules.abilities[2].startupTicks = 0; rules.abilities[2].recoveryTicks = 0
        var value = try state(rules); var all: [DuelTriadState.Effect] = []
        for id in UInt64(1)...2 {
            let wave = try XCTUnwrap(attacks(value.start(.mistOnslaught)).first)
            value.contact(attackID: wave.id, context: .init(), eventID: id)
            if id == 1 { all += value.step() }
        }
        XCTAssertEqual(value.suppressionStacks, 2); XCTAssertFalse(value.opponentCanBlock)
        XCTAssertEqual(value.opponentOutgoingDamage(100, kind: .weapon), 80)
        all += advance(&value, 8)
        let dot = pulses(all).filter { $0.kind == .suppression }
        XCTAssertEqual(dot.reduce(0) { $0 + $1.damage }, 10)
        XCTAssertTrue(dot.allSatisfy(\.nonlethal))
        XCTAssertTrue(dot.allSatisfy { $0.healthDamage(health: 1) == 0 && $0.healthDamage(health: 0) == 0 })
        XCTAssertEqual(value.suppressionStacks, 0); XCTAssertTrue(value.opponentCanBlock)
    }

    func testMistRegenerationPreservesFractionalIntervalsAndDOTDoesNotRegenerateAgain() throws {
        var value = try state(DuelTriadTestFixture.rules(level: 2))
        let wave = try XCTUnwrap(attacks(release(.mistOnslaught, &value)).first)
        value.contact(attackID: wave.id, context: .init(), eventID: 1)
        let before = value.mist
        var gained: [Int] = []
        for _ in 0..<4 { value.step(); gained.append(value.mist - before) }
        XCTAssertEqual(gained, [1, 2, 3, 5])
        advance(&value, 20)
        XCTAssertEqual(value.mist, before + 5, "Suppression damage is not a new attack-contact feedback event")
    }

    func testBlockedAndGeneratedMistRegenerationRequireTheirExplicitPolicies() throws {
        var rules = DuelTriadTestFixture.rules(level: 5)
        rules.mist.level5GainBonusBps = 10_000
        rules.policies.blockedHitsRestoreMist = false; rules.policies.generatedHitsRestoreMist = false
        var value = try state(rules)
        let wave = try XCTUnwrap(attacks(release(.mistOnslaught, &value)).first)
        value.contact(attackID: wave.id, context: .init(), eventID: 1)
        advance(&value, 4); let baseline = value.mist
        value.weaponContact(blocked: true, critical: false, eventID: 1)
        advance(&value, 2); XCTAssertEqual(value.mist, baseline)
        value.weaponContact(blocked: false, critical: false, eventID: 2)
        advance(&value, 4)
        XCTAssertEqual(value.mist, baseline + 10)
    }

    func testCurseOnlyRollsForUniqueShadowStartsAndHonorsItsDebuffAndCooldown() throws {
        var rules = DuelTriadTestFixture.rules(); rules.forest.triggerCooldownTicks = 3
        var value = try state(rules); let before = value.mist
        let effects = value.opponentUsedShadowMove(eventID: 5)
        XCTAssertTrue(effects.contains { if case .control(let c) = $0 { return c.kind == .stun && c.durationTicks == 2 }; return false })
        XCTAssertEqual(value.mist, before + 7); XCTAssertEqual(value.curseDebuffRemainingTicks, 5)
        let snapshot = value
        XCTAssertTrue(value.opponentUsedShadowMove(eventID: 5).isEmpty); XCTAssertEqual(value, snapshot)
        XCTAssertTrue(value.opponentUsedShadowMove(eventID: 4).isEmpty); XCTAssertEqual(value, snapshot)
        XCTAssertTrue(value.opponentUsedShadowMove(eventID: 6).isEmpty)
        advance(&value, 3); XCTAssertFalse(value.opponentUsedShadowMove(eventID: 7).isEmpty)
        XCTAssertEqual(value.opponentOutgoingDamage(100, kind: .unarmed), 80)
        XCTAssertEqual(value.opponentOutgoingDamage(100, kind: .shadow), 100)
    }

    func testSeededCurseSequenceIsDeterministicAndDuplicateEventsDoNotConsumeRNG() throws {
        var rules = DuelTriadTestFixture.rules(); rules.forest.curseChanceBps = 5000
        var first = try state(rules, seed: 713), second = try state(rules, seed: 713)
        var successes = 0
        for id in UInt64(1)...32 {
            let a = first.opponentUsedShadowMove(eventID: id), b = second.opponentUsedShadowMove(eventID: id)
            XCTAssertEqual(a, b)
            if !a.isEmpty { successes += 1 }
            second.opponentUsedShadowMove(eventID: id)
            XCTAssertEqual(first, second)
        }
        XCTAssertGreaterThan(successes, 0); XCTAssertLessThan(successes, 32)
        XCTAssertEqual(try bytes(first), try bytes(second))
    }

    func testSoulsFlavoursRemainDistinctForArmorWeaponAndDamageKinds() throws {
        var value = try state(DuelTriadTestFixture.rules(level: 3))
        value.configureOpponent(armor: .legion, weapon: .dynasty)
        XCTAssertEqual(value.opponentOutgoingDamage(100, kind: .weapon), 90)
        XCTAssertEqual(value.opponentOutgoingDamage(100, kind: .unarmed), 90)
        XCTAssertEqual(value.opponentOutgoingDamage(100, kind: .shadow), 81)
        XCTAssertEqual(value.opponentOutgoingDamage(100, kind: .trueDamage), 100)
        value.configureOpponent(armor: .herald, weapon: .herald)
        XCTAssertEqual(value.opponentShadowEnergyGainMultiplierBps, 8100)
        XCTAssertEqual(value.opponentCriticalCooldownMultiplierBps, 11_500)
        var lower = try state(DuelTriadTestFixture.rules(level: 2))
        lower.configureOpponent(armor: .herald, weapon: .herald)
        XCTAssertEqual(lower.opponentShadowEnergyGainMultiplierBps, 10_000)
    }

    func testHungrySoulDeflectionNeedsAnAttackAndHasAnIndependentExactCooldown() throws {
        var value = try state()
        XCTAssertFalse(value.defendAgainstIncomingAttack(whileAttacking: false, eventID: 1).deflected)
        let defence = value.defendAgainstIncomingAttack(whileAttacking: true, eventID: 2)
        XCTAssertTrue(defence.deflected)
        XCTAssertEqual(attacks(defence.effects).map(\.ability), [.legionary])
        XCTAssertEqual(value.notches, 1)
        XCTAssertFalse(value.defendAgainstIncomingAttack(whileAttacking: true, eventID: 2).accepted)
        XCTAssertFalse(value.defendAgainstIncomingAttack(whileAttacking: true, eventID: 3).deflected)
        advance(&value, 5)
        XCTAssertFalse(value.defendAgainstIncomingAttack(whileAttacking: true, canDeflect: false, eventID: 4).deflected)
        XCTAssertTrue(value.defendAgainstIncomingAttack(whileAttacking: true, eventID: 5).deflected)
        XCTAssertEqual(value.notches, 2)
    }

    func testHungryHeraldIsCriticalAndDynastPoisonStacksWithoutCriticalWeaponFeedback() throws {
        var value = try state(DuelTriadTestFixture.rules(level: 4))
        let herald = try XCTUnwrap(attacks(release(.herald, &value)).first)
        XCTAssertTrue(herald.critical)
        value.contact(attackID: herald.id, context: .init(), eventID: 1)
        XCTAssertTrue(value.breakthroughReady, "A consumed soul does not spend the puppet's prepared critical")
        finishCast(&value)
        let dynast = try XCTUnwrap(attacks(release(.dynast, &value)).first)
        value.contact(attackID: dynast.id, context: .init(), eventID: 2)
        let dots = pulses(advance(&value, 4)).filter { $0.kind == .poison }
        XCTAssertEqual(dots.reduce(0) { $0 + $1.damage }, 10)
        XCTAssertTrue(dots.allSatisfy { $0.damageKind == .trueDamage && $0.canKill })
    }

    func testCryingDanceSpendsNotchesOnceAndItsTranceCannotBeInterruptedByDamage() throws {
        var value = try state()
        for ability in [DuelTriadRules.Ability.legionary, .herald, .dynast] {
            release(ability, &value); finishCast(&value)
        }
        XCTAssertEqual(value.notches, 3); XCTAssertTrue(value.canUse(.cryingDance))
        let started = value.start(.cryingDance)
        XCTAssertFalse(started.isEmpty); XCTAssertEqual(value.notches, 0)
        XCTAssertTrue(value.movementLocked); XCTAssertTrue(value.weaponAttacksLocked); XCTAssertTrue(value.impactImmune)
        XCTAssertFalse(value.damageImmune)
        XCTAssertTrue(value.interrupt().isEmpty)
        let snapshot = value
        XCTAssertTrue(value.start(.cryingDance).isEmpty); XCTAssertEqual(value, snapshot)
        let summons = attacks(advance(&value, 7)).filter { $0.origin == .dance }
        XCTAssertEqual(summons.count, 3); XCTAssertEqual(value.notches, 3)
        XCTAssertNil(value.activeCast); XCTAssertFalse(value.movementLocked)
    }

    func testFeastAndNotchesCarryAcrossRoundsWithoutReplayingContactsOrAdvancingDuringBreak() throws {
        var rules = DuelTriadTestFixture.rules(); rules.mist.betweenRoundsRetainedBps = 5000
        var value = try state(rules)
        let soul = try XCTUnwrap(attacks(release(.legionary, &value)).first)
        value.contact(attackID: soul.id, context: .init(), eventID: 10)
        value.weaponContact(blocked: false, critical: false, eventID: 10)
        let before = value.mist
        XCTAssertTrue(value.finishRound(won: true, eventID: 1).contains(.feast(mistGained: 100)))
        XCTAssertEqual(value.mist, before + 100); XCTAssertEqual(value.notches, 1)
        let breakState = value
        XCTAssertTrue(advance(&value, 100).isEmpty); XCTAssertEqual(value, breakState)
        XCTAssertTrue(value.finishRound(won: true, eventID: 2).isEmpty); XCTAssertEqual(value, breakState)
        value.beginRound(roundID: 1)
        XCTAssertEqual(value.mist, (before + 100) / 2); XCTAssertEqual(value.notches, 1)
        XCTAssertTrue(value.breakthroughReady)
        let newRound = value
        value.weaponContact(blocked: false, critical: false, eventID: 10)
        XCTAssertEqual(value, newRound, "Contact sequence fences do not reset between rounds")
        XCTAssertFalse(value.contact(attackID: soul.id, context: .init(), eventID: 11).accepted)
    }

    func testManualSoulAppearsBeforeAttackAndCountsOneNotchWithAStableSummonIdentity() throws {
        var rules = DuelTriadTestFixture.rules(); rules.abilities[3].startupTicks = 3
        var value = try state(rules)
        let appearing = value.start(.legionary)
        let summon = try XCTUnwrap(appearing.compactMap { event -> UInt64? in
            if case .soulAppeared(.legionary, .manual, let id) = event { return id }; return nil
        }.first)
        XCTAssertEqual(value.mist, 490); XCTAssertEqual(value.notches, 1)
        XCTAssertNil(value.activeCast)
        XCTAssertTrue(attacks(appearing).isEmpty)
        XCTAssertFalse(appearing.contains { if case .castPhase = $0 { return true }; return false })
        XCTAssertTrue(attacks(advance(&value, 2)).isEmpty)
        let released = value.step()
        let attack = try XCTUnwrap(attacks(released).first)
        XCTAssertEqual(attack.summonID, summon); XCTAssertNotEqual(attack.id, summon)
        XCTAssertEqual(value.notches, 1)
        XCTAssertTrue(released.contains(.soulSummoned(.legionary, .manual, attackID: attack.id)))
        XCTAssertFalse(released.contains { if case .soulAppeared = $0 { return true }; return false })
    }

    func testSoulSummonPreservesOwnerCastAndSurvivesItsInterruption() throws {
        var rules = DuelTriadTestFixture.rules()
        rules.abilities[2].startupTicks = 5; rules.abilities[3].startupTicks = 2
        var value = try state(rules)
        value.start(.mistOnslaught)
        let ownerCast = try XCTUnwrap(value.activeCast)
        XCTAssertTrue(value.canUse(.legionary))
        value.start(.legionary)
        XCTAssertEqual(value.activeCast, ownerCast)
        XCTAssertEqual(value.interrupt(), [.castInterrupted(.mistOnslaught)])
        XCTAssertNil(value.activeCast)
        let independent = try XCTUnwrap(attacks(advance(&value, 2)).first)
        XCTAssertEqual(independent.ability, .legionary)
        XCTAssertNotNil(independent.summonID)
        XCTAssertEqual(value.notches, 1)
        XCTAssertTrue(value.contact(attackID: independent.id, context: .init(), eventID: 1).accepted)
        XCTAssertTrue(attacks(advance(&value, 5)).isEmpty, "The interrupted owner's wave never releases")
    }

    func testLowLevelRootHoldAllowsIndependentSoulsButLocksOtherOwnerAbilities() throws {
        var value = try state(DuelTriadTestFixture.rules(level: 2))
        value.weaponContact(blocked: false, critical: false, eventID: 1)
        let root = try XCTUnwrap(attacks(release(.branches, &value)).first)
        value.contact(attackID: root.id, context: .init(), eventID: 1)
        finishCast(&value)
        XCTAssertGreaterThan(value.rootRemainingTicks, 0)
        XCTAssertFalse(value.canUse(.mistBlade)); XCTAssertFalse(value.canUse(.mistOnslaught))
        XCTAssertTrue(value.canUse(.legionary)); XCTAssertTrue(value.canUse(.herald)); XCTAssertTrue(value.canUse(.dynast))
        value.start(.legionary)
        XCTAssertNil(value.activeCast); XCTAssertTrue(value.movementLocked)
        XCTAssertEqual(attacks(value.step()).map(\.ability), [.legionary])
    }

    func testSharedSoulCooldownAndIndividualCooldownHaveSeparateExactBoundaries() throws {
        var rules = DuelTriadTestFixture.rules(); rules.souls.sharedCooldownTicks = 3
        var value = try state(rules)
        value.start(.legionary)
        XCTAssertEqual(value.sharedSoulCooldownRemainingTicks, 3)
        let before = value
        XCTAssertTrue(value.start(.herald).isEmpty); XCTAssertEqual(value, before)
        advance(&value, 2)
        XCTAssertEqual(value.sharedSoulCooldownRemainingTicks, 1); XCTAssertFalse(value.canUse(.dynast))
        value.step()
        XCTAssertEqual(value.sharedSoulCooldownRemainingTicks, 0)
        XCTAssertFalse(value.canUse(.legionary)); XCTAssertTrue(value.canUse(.herald))
        value.start(.herald)
        XCTAssertEqual(value.cooldownRemaining(.legionary), 2)
        XCTAssertEqual(value.cooldownRemaining(.herald), 5)
        XCTAssertEqual(value.sharedSoulCooldownRemainingTicks, 3)
    }

    func testRoundEndCancelsPendingSoulAttacksButKeepsAppearedNotchesAndIdentityFence() throws {
        var rules = DuelTriadTestFixture.rules(); rules.abilities[3].startupTicks = 5
        rules.souls.sharedCooldownTicks = 3
        var value = try state(rules)
        let appearing = value.start(.legionary)
        let firstID = try XCTUnwrap(appearing.compactMap { event -> UInt64? in
            if case .soulAppeared(_, _, let id) = event { return id }; return nil
        }.first)
        XCTAssertEqual(value.notches, 1)
        value.finishRound(won: false, eventID: 1); value.beginRound(roundID: 1)
        XCTAssertEqual(value.sharedSoulCooldownRemainingTicks, 0)
        XCTAssertTrue(attacks(advance(&value, 6)).isEmpty)
        XCTAssertEqual(value.notches, 1)
        let next = value.start(.legionary)
        let nextID = try XCTUnwrap(next.compactMap { event -> UInt64? in
            if case .soulAppeared(_, _, let id) = event { return id }; return nil
        }.first)
        XCTAssertGreaterThan(nextID, firstID); XCTAssertEqual(value.notches, 2)
    }

    func testExpiredOrUnknownVolumesCannotCreateDamageOrControlAndDoNotSpendContactFence() throws {
        var rules = DuelTriadTestFixture.rules(); rules.abilities[2].attack?.lifetimeTicks = 2
        var value = try state(rules)
        let wave = try XCTUnwrap(attacks(release(.mistOnslaught, &value)).first)
        advance(&value, 2)
        let before = value
        XCTAssertFalse(value.contact(attackID: wave.id, context: .init(), eventID: 1000).accepted)
        XCTAssertFalse(value.contact(attackID: 0, context: .init(), eventID: 1001).accepted)
        XCTAssertEqual(value, before)
        let root = try XCTUnwrap(attacks(release(.branches, &value)).first)
        XCTAssertTrue(value.contact(attackID: root.id, context: .init(), eventID: 1).accepted)
    }

    func testReplayIncludesPendingSoulsResourceRemaindersFencesAndRNG() throws {
        var first = try state(), second = first
        let root = try XCTUnwrap(attacks(release(.branches, &first)).first)
        second = first
        first.contact(attackID: root.id, context: .init(), eventID: 1)
        second.contact(attackID: root.id, context: .init(), eventID: 1)
        XCTAssertEqual(try bytes(first), try bytes(second))
        for _ in 0..<10 {
            XCTAssertEqual(first.step(), second.step())
            XCTAssertEqual(try bytes(first), try bytes(second))
        }
        var otherSeed = try state(seed: 20)
        XCTAssertNotEqual(try bytes(try state()), try bytes(otherSeed))
        otherSeed.opponentUsedShadowMove(eventID: 4)
        let once = try bytes(otherSeed)
        otherSeed.opponentUsedShadowMove(eventID: 4)
        XCTAssertEqual(try bytes(otherSeed), once)
    }
}
