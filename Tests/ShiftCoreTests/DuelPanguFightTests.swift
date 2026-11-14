import XCTest
@testable import ShiftCore

/// Synthetic integration geometry and balance only. No original catalog is
/// upgraded, and none of these quantities is a claim about the retail game.
enum DuelPanguFightFixture {
    static func changingAttack(_ rules: inout DuelPanguRules, _ ability: DuelPanguRules.Ability,
                               _ change: (inout DuelPanguRules.AttackSpec) -> Void) {
        guard let index = rules.abilities.firstIndex(where: { $0.ability == ability }) else { return }
        change(&rules.abilities[index].attack)
    }

    static func catalog(rules: DuelPanguRules, ordinaryDamage: Int = 30,
                        ordinaryHitStop: Int = 1,
                        ordinaryWindow: ClosedRange<Int>? = nil,
                        ordinaryImpact: DuelImpactResponse = .init(distanceMillimeters: 0, durationTicks: 1)) throws -> DuelWeaponCatalog {
        let old = DuelWeaponTestFixtures.catalog()
        let sun = try XCTUnwrap(old.profile(for: .ember))
        let liu = try XCTUnwrap(old.profile(for: .liu))
        let clips = liu.clips.map { clip -> DuelWeaponClip in
            let t = clip.tracks
            return .init(name: clip.name, frames: clip.frames, sha256: clip.sha256, bundle: clip.bundle,
                tracks: .init(samplesPerSourceFrame: t.samplesPerSourceFrame, root: t.root,
                    handL: t.handL, handR: t.handR, footL: t.footL, footR: t.footR,
                    weaponBaseL: [], weaponTipL: [], weaponBaseR: t.weaponBaseR,
                    weaponTipR: t.weaponTipR, groundLift: t.groundLift))
        }
        let idle = try XCTUnwrap(clips.first { $0.name == liu.roles["idle"] })
        var roles = liu.roles
        roles.removeValue(forKey: "shadow")
        var targetClips = clips
        for ability in DuelPanguRules.Ability.allCases {
            let name = "synthetic_" + ability.motionRole
            roles[ability.motionRole] = name
            targetClips.append(.init(name: name, frames: idle.frames, sha256: idle.sha256,
                                     bundle: "synthetic-pangu-integration-only", tracks: idle.tracks))
        }
        let pangu = DuelWeaponProfile(id: "liu_pangu", hero: .liu, faction: "Synthetic",
            resourceName: "Synthetic_Pangu_Integration", bytes: liu.bytes, sha256: liu.sha256,
            bodyID: "synthetic_pangu_body", weaponID: "synthetic_pangu_long_axe",
            activeWeaponSides: ["right"], roles: roles, clips: targetClips, panguRules: rules)

        func explicit(_ profile: DuelWeaponProfile) -> DuelWeaponProfile {
            // The old table supplies only the set of required command/clip
            // bindings. Damage, recoil and timing below are explicit test data.
            let attacks = DuelCombatRuleProfile.legacy(for: profile).attacks.map { binding in
                let weapon = !binding.command.rawValue.hasPrefix("kick") && binding.command != .shadow
                let blockedResponse = DuelImpactResponse(distanceMillimeters: ordinaryImpact.distanceMillimeters,
                    durationTicks: ordinaryImpact.durationTicks,
                    gravityMillimetersPerTickSquared: ordinaryImpact.gravityMillimetersPerTickSquared)
                return DuelCombatAttackRule(command: binding.command, clipName: binding.clipName,
                    strikes: [.init(id: 0, startTick: binding.command == .shadow ? 24 : (ordinaryWindow?.lowerBound ?? 1),
                        endTick: binding.command == .shadow ? 39 : (ordinaryWindow?.upperBound ?? 12),
                        weaponSides: weapon ? profile.activeWeaponSides : [],
                        damage: ordinaryDamage, blockedDamage: 2, knocksDown: false,
                        hitStopTicks: ordinaryHitStop, blockedHitStopTicks: ordinaryHitStop,
                        impact: ordinaryImpact, blockedImpact: blockedResponse)])
            }
            let combat = DuelCombatRuleProfile(id: "synthetic-fight-" + profile.id,
                basis: .applicationAdaptation, sourceVersion: "synthetic-integration-tests-only",
                evidence: ["Artificial geometry and values; not original game configuration."], attacks: attacks)
            return .init(id: profile.id, hero: profile.hero, faction: profile.faction,
                resourceName: profile.resourceName, bytes: profile.bytes, sha256: profile.sha256,
                bodyID: profile.bodyID, weaponID: profile.weaponID,
                activeWeaponSides: profile.activeWeaponSides, roles: profile.roles, clips: profile.clips,
                comboLinks: profile.comboLinks, combatRules: combat, panguRules: profile.panguRules)
        }
        let result = DuelWeaponCatalog(schemaVersion: 1, previewFramesPerSecond: 30,
            sourceFramesPerSecond: nil, profiles: [explicit(sun), explicit(pangu)])
        try result.validate()
        return result
    }

    static func fight(rules: DuelPanguRules = DuelPanguTestFixture.rules(level: 2),
                      distance: Int = 800, facing: Int = 1, panguFirst: Bool = true,
                      mode: DuelGame.Mode = .practice, ordinaryDamage: Int = 30,
                      ordinaryHitStop: Int = 1,
                      ordinaryWindow: ClosedRange<Int>? = nil,
                      ordinaryImpact: DuelImpactResponse = .init(distanceMillimeters: 0, durationTicks: 1)) throws -> DuelWeaponFight {
        let firstX = facing > 0 ? 3500 : 6500
        let fighters = [
            DuelGame.Fighter(hero: panguFirst ? .liu : .ember, x: firstX, facing: facing),
            DuelGame.Fighter(hero: panguFirst ? .ember : .liu,
                             x: firstX + distance * facing, facing: -facing)
        ]
        return try XCTUnwrap(DuelWeaponFight(fighters: fighters, mode: mode, difficulty: .learning,
            catalog: catalog(rules: rules, ordinaryDamage: ordinaryDamage,
                             ordinaryHitStop: ordinaryHitStop, ordinaryWindow: ordinaryWindow,
                             ordinaryImpact: ordinaryImpact),
            seed: 41))
    }

    @discardableResult
    static func until(_ fight: inout DuelWeaponFight, limit: Int = 160,
                      _ condition: (DuelWeaponFight) -> Bool) -> Bool {
        for _ in 0..<limit {
            if condition(fight) { return true }
            fight.step(.neutral, opponent: .neutral)
        }
        return condition(fight)
    }

    static func drainHitStop(_ fight: inout DuelWeaponFight) {
        for _ in 0..<fight.hitStop { fight.step(.neutral, opponent: .neutral) }
    }
}

final class DuelPanguFightTests: XCTestCase {
    private typealias F = DuelPanguFightFixture

    func testDirectionalShadowAndRangedReachTheirActualCastForBothFacingDirectionsAndPlayerSlots() throws {
        for panguFirst in [true, false] {
            for firstFacing in [1, -1] {
                let index = panguFirst ? 0 : 1
                let facing = panguFirst ? firstFacing : -firstFacing
                let cases: [(DuelGame.Input, DuelPanguRules.Ability)] = [
                    (.init(move: facing, weaponCommand: .shadow), .shard),
                    (.init(move: -facing, weaponCommand: .shadow), .typhoon),
                    (.init(vertical: 1, weaponCommand: .shadow), .splitter),
                    (.init(vertical: -1, weaponCommand: .shadow), .bones),
                    (.init(weaponCommand: .shadow), .heavenfall),
                    (.init(weaponCommand: .ranged), .spear)
                ]
                for (input, ability) in cases {
                    var fight = try F.fight(rules: DuelPanguTestFixture.rules(level: 4),
                        distance: 1800, facing: firstFacing, panguFirst: panguFirst)
                    XCTAssertEqual(fight.panguAbility(for: input, index: index), ability)
                    XCTAssertTrue(fight.canUsePangu(ability, index: index))
                    fight.step(panguFirst ? input : .neutral, opponent: panguFirst ? .neutral : input)
                    XCTAssertEqual(fight.panguState(index)?.activeCast?.ability, ability)
                    XCTAssertEqual(fight.fighters[index].weaponPose?.clip,
                                   fight.profiles[index].roles[ability.motionRole])
                    XCTAssertNil(fight.shadowVisual(index))
                    XCTAssertFalse(fight.shadowIsActive(index))
                }
            }
        }
    }

    func testRealWeaponContactSpendsLightBeforeHealthAndOnlyOverflowCountsAsHealthDamage() throws {
        let rules = DuelPanguTestFixture.rules(level: 2)
        for damage in [20, 100] {
            var fight = try F.fight(rules: rules, panguFirst: false, ordinaryDamage: damage)
            fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
            XCTAssertTrue(F.until(&fight) { $0.landedHits[0] == 1 })
            let capacity = rules.light.initial * rules.light.damageToLightDenominator
                / rules.light.damageToLightNumerator
            let absorbed = min(damage, capacity)
            let spent = (absorbed * rules.light.damageToLightNumerator
                + rules.light.damageToLightDenominator - 1) / rules.light.damageToLightDenominator
            XCTAssertEqual(fight.fighters[1].health, 1000 - (damage - absorbed))
            XCTAssertEqual(fight.panguState(1)?.light, rules.light.initial - spent)
            XCTAssertEqual(fight.damageDealt[0], damage - absorbed)
            XCTAssertEqual(fight.contacts.first?.attacker, 0)
            XCTAssertEqual(fight.contacts.first?.kind, .hit)
        }
    }

    func testWhiffCannotStartRhythmButConfirmedPrimalContactEmpowersDelayedSingleHitSpear() throws {
        let rules = DuelPanguTestFixture.rules(level: 2)
        var miss = try F.fight(rules: rules, distance: 4500)
        miss.step(.init(move: 1, weaponCommand: .shadow), opponent: .neutral)
        for _ in 0..<70 { miss.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(miss.landedHits, [0, 0])
        XCTAssertEqual(miss.panguState(0)?.rhythmRemainingTicks, 0)
        XCTAssertEqual(miss.panguState(0)?.combo, 0)
        miss.step(.init(weaponCommand: .ranged), opponent: .neutral)
        XCTAssertEqual(miss.panguState(0)?.activeCast?.empowered, false)
        XCTAssertEqual(miss.fighters[1].health, 1000)

        var hit = try F.fight(rules: rules, distance: 1800)
        hit.step(.init(move: 1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertEqual(hit.fighters[1].health, 1000)
        XCTAssertTrue(F.until(&hit) { $0.landedHits[0] == 1 })
        XCTAssertEqual(hit.panguState(0)?.rhythmRemainingTicks, rules.hunt.durationTicks)
        XCTAssertEqual(hit.fighters[1].health, 1000 - (try XCTUnwrap(rules.ability(.shard))).damage)
        F.drainHitStop(&hit)
        XCTAssertTrue(F.until(&hit) { $0.canUsePangu(.spear, index: 0) })
        let combo = try XCTUnwrap(hit.panguState(0)).combo
        let beforeSpearHealth = hit.fighters[1].health
        hit.step(.init(weaponCommand: .ranged), opponent: .neutral)
        XCTAssertEqual(hit.panguState(0)?.activeCast?.empowered, true)
        XCTAssertEqual(hit.panguState(0)?.rhythmRemainingTicks, 0)
        for _ in 0..<4 {
            hit.step(.neutral, opponent: .neutral)
            XCTAssertEqual(hit.fighters[1].health, beforeSpearHealth,
                           "Neither cast start nor release may hit a distant body immediately")
        }
        XCTAssertTrue(F.until(&hit) { $0.landedHits[0] == 2 })
        let bonus = min(rules.combo.maximumDamageBonusBps, combo * rules.combo.damageBonusPerPointBps)
        let expected = rules.hunt.empoweredSpear.damage * (10_000 + bonus) / 10_000
        XCTAssertEqual(hit.fighters[1].health, beforeSpearHealth - expected)
        for _ in 0..<80 { hit.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(hit.landedHits[0], 2, "A spent projectile cannot repeatedly damage an overlapping torso")
        XCTAssertEqual(hit.fighters[1].health, beforeSpearHealth - expected)
    }

    func testHeavenfallRangeRejectsRemotePetrificationAndLeavesOpponentAbleToAttack() throws {
        var rules = DuelPanguTestFixture.rules(level: 2)
        F.changingAttack(&rules, .heavenfall) { $0.rangeMillimeters = 800 }
        var fight = try F.fight(rules: rules, distance: 1800)
        fight.step(.init(weaponCommand: .shadow), opponent: .neutral)
        fight.step(.neutral, opponent: .init(weaponCommand: .weapon))
        XCTAssertEqual(fight.fighters[1].weaponPose?.clip, fight.profiles[1].roles["weapon1"])
        XCTAssertNotNil(fight.fighters[1].attack)
        for _ in 0..<35 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.fighters[1].health, 1000)
        XCTAssertEqual(fight.landedHits[0], 0)
    }

    func testPetrificationCancelsCurrentAttackAndConsumesPressedCommandsWithoutARecoveryBuffer() throws {
        var fight = try F.fight()
        let kick = fight.profiles[1].roles["kick"]
        fight.step(.init(weaponCommand: .shadow), opponent: .init(weaponCommand: .weapon))
        XCTAssertNil(fight.fighters[1].attack)
        fight.step(.neutral, opponent: .init(weaponCommand: .kick))
        XCTAssertNil(fight.fighters[1].attack)
        XCTAssertFalse(fight.fighters[1].guarding)
        for _ in 0..<65 {
            fight.step(.neutral, opponent: .neutral)
            XCTAssertNotEqual(fight.fighters[1].weaponPose?.clip, kick)
        }
        XCTAssertEqual(fight.landedHits[1], 0)
        fight.step(.neutral, opponent: .init(weaponCommand: .weapon))
        XCTAssertEqual(fight.fighters[1].weaponPose?.clip, fight.profiles[1].roles["weapon1"],
                       "A fresh edge must work after the control and reaction recover")
    }

    func testSplitterLaunchesHoldsAtApexThenLandsWithoutReplayingAnAirborneAttackPress() throws {
        var rules = DuelPanguTestFixture.rules(level: 2)
        F.changingAttack(&rules, .splitter) {
            $0.delivery = .melee; $0.rangeMillimeters = 1500; $0.hitStopTicks = 0
            $0.impact = .init(distanceMillimeters: 0, durationTicks: 1,
                             launchVelocityMillimetersPerTick: 180, gravityMillimetersPerTickSquared: 60)
            $0.airHoldTicks = 4
        }
        var fight = try F.fight(rules: rules)
        fight.step(.init(vertical: 1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertTrue(F.until(&fight) { $0.landedHits[0] == 1 })
        XCTAssertGreaterThan(fight.fighters[1].velocityY, 0)
        var maximumHeight = 0, heldTicks = 0
        var pressedWhileHeld = false
        for _ in 0..<70 {
            let before = fight.fighters[1]
            let held = before.y > 0 && before.velocityY == 0
            let input: DuelGame.Input = held && !pressedWhileHeld ? .init(weaponCommand: .weapon) : .neutral
            if held { pressedWhileHeld = true }
            fight.step(.neutral, opponent: input)
            maximumHeight = max(maximumHeight, fight.fighters[1].y)
            if held && fight.fighters[1].y == before.y { heldTicks += 1 }
        }
        XCTAssertGreaterThan(maximumHeight, 0)
        XCTAssertGreaterThanOrEqual(heldTicks, 4)
        XCTAssertTrue(pressedWhileHeld)
        XCTAssertEqual(fight.fighters[1].y, 0)
        XCTAssertEqual(fight.fighters[1].velocityY, 0)
        XCTAssertFalse(fight.isAirborne(1))
        XCTAssertNil(fight.fighters[1].attack)
        XCTAssertEqual(fight.landedHits[1], 0)
        fight.step(.neutral, opponent: .init(weaponCommand: .weapon))
        XCTAssertEqual(fight.fighters[1].weaponPose?.clip, fight.profiles[1].roles["weapon1"])
    }

    func testStormGateCrossesBehindReorientsAndCannotTurnItsTeleportIntoAWeaponSweep() throws {
        for facing in [1, -1] {
            var fight = try F.fight(rules: DuelPanguTestFixture.rules(level: 4),
                                    distance: 4500, facing: facing)
            let initialX = fight.fighters[0].x
            fight.step(.init(move: -facing, weaponCommand: .shadow), opponent: .neutral)
            XCTAssertTrue(F.until(&fight) { $0.canUsePangu(.stormGate, index: 0) })
            let input = DuelGame.Input(move: -fight.fighters[0].facing, weaponCommand: .shadow)
            XCTAssertEqual(fight.panguAbility(for: input, index: 0), .stormGate)
            fight.step(input, opponent: .neutral)
            XCTAssertTrue(F.until(&fight) { $0.fighters[0].x != initialX })
            XCTAssertGreaterThan((fight.fighters[0].x - fight.fighters[1].x) * facing, 0)
            XCTAssertEqual(fight.fighters[0].facing, -facing)
            XCTAssertGreaterThanOrEqual(abs(fight.fighters[0].x - fight.fighters[1].x), DuelGame.bodyWidth)
            XCTAssertEqual(fight.fighters.map(\.health), [1000, 1000])
            XCTAssertEqual(fight.landedHits, [0, 0])
            XCTAssertTrue(F.until(&fight) { $0.panguState(0)?.activeCast == nil })
            fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
            XCTAssertTrue(F.until(&fight) { $0.landedHits[0] > 0 })
            XCTAssertEqual(fight.contacts.first?.direction, -facing)
            XCTAssertLessThan(fight.fighters[1].health, 1000)
        }
    }

    func testHeavenfallHasVisibleRiseChargeLightAndDescentBeforeOneGroundedLandingHit() throws {
        var rules = DuelPanguTestFixture.rules(level: 2)
        rules.heavenfall.descentVelocityMillimetersPerTick = 300
        rules.heavenfall.fallTicks = 6
        var fight = try F.fight(rules: rules, distance: 1800)
        let ability = try XCTUnwrap(rules.ability(.heavenfall))
        fight.step(.init(weaponCommand: .shadow), opponent: .neutral)
        XCTAssertEqual(fight.panguState(0)?.activeCast?.phase, .petrifying)
        XCTAssertEqual(fight.panguState(0)?.light, rules.light.initial - ability.lightCost)
        var phases = Set<String>(), maximumHeight = 0, maximumPreHitLight = 0
        var observedHit = false
        for _ in 0..<45 {
            fight.step(.neutral, opponent: .neutral)
            let state = try XCTUnwrap(fight.panguState(0))
            if let phase = state.activeCast?.phase { phases.insert(phase.rawValue) }
            maximumHeight = max(maximumHeight, fight.fighters[0].y)
            if fight.fighters[1].health == 1000 { maximumPreHitLight = max(maximumPreHitLight, state.light) }
            if fight.fighters[0].y > 0 {
                XCTAssertEqual(fight.fighters[1].health, 1000, "A nominal phase cannot damage before physical landing")
            }
            if !observedHit && fight.fighters[1].health < 1000 {
                observedHit = true
                XCTAssertEqual(fight.fighters[0].y, 0)
                XCTAssertEqual(state.activeCast?.phase, .landing)
            }
        }
        XCTAssertTrue(["rising", "charging", "falling", "landing"].allSatisfy(phases.contains))
        XCTAssertEqual(maximumHeight, rules.heavenfall.pillarHeightMillimeters)
        XCTAssertEqual(maximumPreHitLight, rules.light.initial - ability.lightCost
            + rules.heavenfall.chargeTicks * rules.heavenfall.lightPerChargeTick)
        XCTAssertTrue(observedHit)
        XCTAssertEqual(fight.landedHits[0], 1)
        XCTAssertEqual(fight.fighters[1].health, 1000 - ability.damage)
        XCTAssertEqual(fight.fighters[0].y, 0)
        XCTAssertNil(fight.panguState(0)?.activeCast)
    }

    func testHitStopFreezesResourcesCooldownsBodiesAndAnAlreadyReleasedProjectileLifetime() throws {
        var rules = DuelPanguTestFixture.rules(level: 2)
        F.changingAttack(&rules, .spear) { $0.rangeMillimeters = 900 }
        var fight = try F.fight(rules: rules, distance: 1200, ordinaryHitStop: 24)
        fight.step(.init(weaponCommand: .ranged), opponent: .neutral)
        fight.step(.neutral, opponent: .neutral)
        fight.step(.neutral, opponent: .init(weaponCommand: .weapon))
        XCTAssertTrue(F.until(&fight) { $0.landedHits[1] == 1 })
        XCTAssertEqual(fight.landedHits[0], 0, "The spear must still be travelling when the other weapon connects")
        XCTAssertEqual(fight.hitStop, 24)
        let state = fight.panguState(0), fighters = fight.fighters, timer = fight.remainingTicks
        let spearCooldown = state?.cooldownRemaining(.spear)
        for _ in 0..<24 {
            fight.step(.neutral, opponent: .neutral)
            XCTAssertEqual(fight.panguState(0), state)
            XCTAssertEqual(fight.panguState(0)?.cooldownRemaining(.spear), spearCooldown)
            XCTAssertEqual(fight.fighters, fighters)
            XCTAssertEqual(fight.remainingTicks, timer)
            XCTAssertEqual(fight.landedHits[0], 0)
        }
        XCTAssertTrue(F.until(&fight, limit: 20) { $0.landedHits[0] == 1 },
                      "A pause longer than the projectile's nominal lifetime must not expire it")
        let damage = try XCTUnwrap(rules.ability(.spear)).damage
        XCTAssertEqual(fight.fighters[1].health, 1000 - damage)
        for _ in 0..<40 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.landedHits[0], 1)
    }

    func testPinnedTargetRetainsEveryControlTickAcrossHitStopAndThenResumesItsReaction() throws {
        var rules = DuelPanguTestFixture.rules(level: 2)
        rules.hunt.pinTicks = 5
        rules.hunt.empoweredSpear.hitStopTicks = 24
        rules.hunt.empoweredSpear.impact = .init(distanceMillimeters: 600, durationTicks: 3)
        var fight = try F.fight(rules: rules)
        fight.step(.init(move: 1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertTrue(F.until(&fight) { $0.landedHits[0] == 1 })
        F.drainHitStop(&fight)
        XCTAssertTrue(F.until(&fight) { $0.canUsePangu(.spear, index: 0) })
        fight.step(.init(weaponCommand: .ranged), opponent: .neutral)
        XCTAssertEqual(fight.panguState(0)?.activeCast?.empowered, true)
        XCTAssertTrue(F.until(&fight) { $0.landedHits[0] == 2 })
        XCTAssertEqual(fight.hitStop, 24)
        let pinnedX = fight.fighters[1].x
        let pinnedPoseTick = try XCTUnwrap(fight.fighters[1].weaponPose).tick
        F.drainHitStop(&fight)
        for _ in 0..<rules.hunt.pinTicks {
            fight.step(.neutral, opponent: .init(weaponCommand: .weapon))
            XCTAssertEqual(fight.fighters[1].x, pinnedX)
            XCTAssertEqual(fight.fighters[1].weaponPose?.tick, pinnedPoseTick,
                           "Pin must preserve the reaction sample for every remaining live tick")
            XCTAssertNil(fight.fighters[1].attack)
        }
        fight.step(.neutral, opponent: .neutral)
        XCTAssertGreaterThan(try XCTUnwrap(fight.fighters[1].weaponPose).tick, pinnedPoseTick)
        for _ in 0..<35 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.landedHits[1], 0, "Presses during pin cannot survive in the attack queue")
    }

    func testEveryTickReplayBytesMatchForIdenticalMixedInputsIncludingPrimalAbilitiesAndHitStop() throws {
        let rules = DuelPanguTestFixture.rules(level: 6)
        var first = try F.fight(rules: rules, distance: 1800)
        var second = try F.fight(rules: rules, distance: 1800)
        var sawCast = false, sawPause = false
        for tick in 0..<360 {
            let input: DuelGame.Input
            switch tick % 60 {
            case 0: input = .init(move: first.fighters[0].facing, weaponCommand: .shadow)
            case 14: input = .init(weaponCommand: .ranged)
            case 25: input = .init(vertical: -1, weaponCommand: .shadow)
            case 38: input = .init(weaponCommand: .shadow)
            case 52: input = .init(weaponCommand: .heavy)
            default: input = .neutral
            }
            let opponent = tick % 47 == 0 ? DuelGame.Input(weaponCommand: .weapon) : .neutral
            first.step(input, opponent: opponent); second.step(input, opponent: opponent)
            sawCast = sawCast || first.panguState(0)?.activeCast != nil
            sawPause = sawPause || first.hitStop > 0
            XCTAssertEqual(try DuelReplayStateEncoding.encode(first),
                           try DuelReplayStateEncoding.encode(second), "tick \(tick)")
        }
        XCTAssertTrue(sawCast)
        XCTAssertTrue(sawPause)
        XCTAssertGreaterThan(first.landedHits[0], 0)
    }

    func testRoundEndClearsAnInFlightProjectileAndResetRestoresResourcesBeforeTheFinalRound() throws {
        var rules = DuelPanguTestFixture.rules(level: 2)
        F.changingAttack(&rules, .spear) { $0.projectileSpeedMillimetersPerTick = 50 }
        F.changingAttack(&rules, .bones) { $0.damage = 2000 }
        var fight = try F.fight(rules: rules, distance: 1800, mode: .versus)
        fight.step(.init(weaponCommand: .ranged), opponent: .neutral)
        XCTAssertTrue(F.until(&fight) { $0.canUsePangu(.bones, index: 0) })
        XCTAssertEqual(fight.landedHits[0], 0, "The slow spear is still in flight before the ground attack")
        fight.step(.init(vertical: -1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertTrue(F.until(&fight) { $0.phase != .fighting })
        guard case .roundBreak(let winner, _) = fight.phase else { return XCTFail("Expected first-round break") }
        XCTAssertEqual(winner, 0)
        XCTAssertEqual(fight.wins, [1, 0])
        XCTAssertNil(fight.panguState(0)?.activeCast)
        XCTAssertTrue(fight.fighters.allSatisfy { $0.y == 0 && $0.velocityY == 0 })
        XCTAssertTrue(F.until(&fight, limit: 151) { $0.phase == .fighting })
        let reset = try XCTUnwrap(fight.panguState(0))
        XCTAssertEqual(reset.light, rules.light.initial)
        XCTAssertEqual(reset.rangedCharges, rules.ranged.initialCharges)
        XCTAssertEqual(reset.combo, 0)
        XCTAssertEqual(reset.rhythmRemainingTicks, 0)
        XCTAssertEqual(reset.typhoonRemainingTicks, 0)
        XCTAssertTrue(DuelPanguRules.Ability.allCases.allSatisfy { reset.cooldownRemaining($0) == 0 })
        XCTAssertEqual(fight.fighters.map(\.health), [1000, 1000])
        let hits = fight.landedHits
        for _ in 0..<100 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.fighters.map(\.health), [1000, 1000],
                       "An old projectile must not cross into the next round")
        XCTAssertEqual(fight.landedHits, hits)
        fight.step(.init(vertical: -1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertTrue(F.until(&fight) { $0.phase == .matchOver(winner: 0) })
        XCTAssertNil(fight.panguState(0)?.activeCast)
        fight.step(.neutral, opponent: .neutral) // Consume the terminal event mailbox.
        let terminal = try DuelReplayStateEncoding.encode(fight)
        for _ in 0..<30 { fight.step(.init(weaponCommand: .ranged), opponent: .neutral) }
        XCTAssertEqual(try DuelReplayStateEncoding.encode(fight), terminal)
    }

    func testEarthBoulderBonusStaysOnTheConfirmedRockTargetWhenCasterHasJumpedAway() throws {
        var rules = DuelPanguTestFixture.rules(level: 4)
        rules.combo.holdTicks = 200; rules.combo.level6HoldTicks = 200
        rules.combo.affectedKinds = [.weapon, .shadow] // An unarmed bonus must not inherit this multiplier.
        rules.earth.earthquakeWindowTicks = 0
        rules.earth.boulderBonusWindowTicks = 100
        rules.earth.boulderBonus.rangeMillimeters = 1
        var fight = try F.fight(rules: rules, distance: 2200)
        fight.step(.init(vertical: -1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertTrue(F.until(&fight) { $0.landedHits[0] == 1 })
        XCTAssertGreaterThan(try XCTUnwrap(fight.panguState(0)).boulderBonusRemainingTicks, 0)
        F.drainHitStop(&fight)
        XCTAssertTrue(F.until(&fight) { $0.canUsePangu(.shard, index: 0) })
        let initialCasterX = fight.fighters[0].x
        let targetHealth = fight.fighters[1].health
        let comboAtRelease = try XCTUnwrap(fight.panguState(0)).combo
        fight.step(.init(move: 1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertTrue(F.until(&fight) { $0.panguState(0)?.activeCast == nil })
        XCTAssertEqual(fight.landedHits[0], 1, "The rock must still be travelling when the caster leaves")
        fight.step(.init(move: -1, taps: .jump), opponent: .neutral)
        var recordedContacts: [DuelWeaponFight.Contact] = []
        var airborneAtContact = false
        for _ in 0..<80 {
            fight.step(.init(move: -1), opponent: .neutral)
            if fight.landedHits[0] > 1 {
                recordedContacts = fight.contacts.filter { $0.attacker == 0 }
                airborneAtContact = fight.isAirborne(0)
                break
            }
        }
        XCTAssertTrue(airborneAtContact)
        XCTAssertLessThan(fight.fighters[0].x, initialCasterX)
        XCTAssertGreaterThan(abs(fight.fighters[1].x - fight.fighters[0].x),
                             rules.earth.boulderBonus.rangeMillimeters)
        let shard = try XCTUnwrap(rules.ability(.shard))
        let primary = shard.damage * (10_000 + rules.earth.shardDamageBonusBps) / 10_000
            * (10_000 + min(rules.combo.maximumDamageBonusBps,
                           comboAtRelease * rules.combo.damageBonusPerPointBps)) / 10_000
        XCTAssertEqual(recordedContacts.count, 2, "The rock and its attached damage component share a confirmed contact")
        XCTAssertEqual(fight.landedHits[0], 3)
        XCTAssertEqual(fight.fighters[1].health, targetHealth - primary - rules.earth.boulderBonus.damage)
        XCTAssertEqual(recordedContacts.first?.position, recordedContacts.last?.position)
    }

    func testEarthLandingShockRequiresTheCastersOwnJumpAndCannotComeFromAnEnemyLaunch() throws {
        var rules = DuelPanguTestFixture.rules(level: 4)
        rules.combo.holdTicks = 200; rules.combo.level6HoldTicks = 200
        rules.earth.earthquakeWindowTicks = 160
        rules.earth.boulderBonusWindowTicks = 0
        let launch = DuelImpactResponse(distanceMillimeters: 0, durationTicks: 1,
            launchVelocityMillimetersPerTick: 180, gravityMillimetersPerTickSquared: 60)
        for ownJump in [true, false] {
            var fight = try F.fight(rules: rules, ordinaryImpact: launch)
            fight.step(.init(vertical: -1, weaponCommand: .shadow), opponent: .neutral)
            XCTAssertTrue(F.until(&fight) { $0.landedHits[0] == 1 })
            F.drainHitStop(&fight)
            XCTAssertTrue(F.until(&fight) {
                $0.canUsePangu(.shard, index: 0) && $0.fighters[1].stun == 0
                    && $0.fighters[1].weaponPose?.reaction == false
            })
            let healthBeforeLanding = fight.fighters[1].health
            let combo = try XCTUnwrap(fight.panguState(0)).combo
            if ownJump {
                fight.step(.init(taps: .jump), opponent: .neutral)
            } else {
                fight.step(.neutral, opponent: .init(weaponCommand: .weapon))
                XCTAssertTrue(F.until(&fight) { $0.landedHits[1] == 1 })
                XCTAssertGreaterThan(fight.fighters[0].velocityY, 0)
            }
            var sawAirborne = false
            for _ in 0..<70 {
                fight.step(.neutral, opponent: .neutral)
                sawAirborne = sawAirborne || fight.isAirborne(0)
            }
            XCTAssertTrue(sawAirborne)
            XCTAssertFalse(fight.isAirborne(0))
            XCTAssertEqual(fight.fighters[0].y, 0)
            if ownJump {
                let bonus = min(rules.combo.maximumDamageBonusBps, combo * rules.combo.damageBonusPerPointBps)
                let shock = rules.earth.landingShock.damage * (10_000 + bonus) / 10_000
                XCTAssertEqual(fight.landedHits[0], 2)
                XCTAssertEqual(fight.fighters[1].health, healthBeforeLanding - shock)
            } else {
                XCTAssertEqual(fight.landedHits[0], 1)
                XCTAssertEqual(fight.fighters[1].health, healthBeforeLanding,
                               "Being knocked into the air must not produce a free Earth landing attack")
            }
        }
    }

    func testPhysicalHeavenfallLandingPhaseAndTranceBeginOnExactlyTheSameTick() throws {
        var rules = DuelPanguTestFixture.rules(level: 6)
        F.changingAttack(&rules, .heavenfall) { $0.hitStopTicks = 0 }
        var fight = try F.fight(rules: rules, distance: 1800)
        fight.step(.init(weaponCommand: .shadow), opponent: .neutral)
        var sawFallingEntry = false, sawGroundContact = false
        for _ in 0..<40 {
            let beforeHeight = fight.fighters[0].y
            let beforePhase = fight.panguState(0)?.activeCast?.phase
            fight.step(.neutral, opponent: .neutral)
            let state = try XCTUnwrap(fight.panguState(0))
            if state.activeCast?.phase == .falling && beforePhase != .falling {
                sawFallingEntry = true
                XCTAssertEqual(fight.fighters[0].y, rules.heavenfall.pillarHeightMillimeters,
                               "Entering fall is its boundary; the first descent interval completes next tick")
            }
            if fight.fighters[0].y > 0 {
                XCTAssertEqual(state.tranceRemainingTicks, 0)
                XCTAssertNotEqual(state.activeCast?.phase, .landing)
            }
            if beforeHeight > 0 && fight.fighters[0].y == 0 {
                sawGroundContact = true
                XCTAssertEqual(state.activeCast?.phase, .landing)
                XCTAssertEqual(state.activeCast?.tick, rules.heavenfall.petrifyPhaseTicks
                    + rules.heavenfall.riseTicks + rules.heavenfall.chargeTicks + rules.heavenfall.fallTicks)
                XCTAssertEqual(state.tranceRemainingTicks, rules.trance.durationTicks)
                XCTAssertEqual(fight.landedHits[0], 1)
                break
            }
        }
        XCTAssertTrue(sawFallingEntry)
        XCTAssertTrue(sawGroundContact)
    }

    func testConfiguredMaximumHealthIsAppliedAtSpawnPracticeKOAndRoundReset() throws {
        var rules = DuelPanguTestFixture.rules(level: 2)
        rules.maximumHealth = 1500
        rules.light.initial = 0
        for mode in [DuelGame.Mode.practice, .versus] {
            var fight = try F.fight(rules: rules, panguFirst: false, mode: mode, ordinaryDamage: 2000)
            XCTAssertEqual(fight.maximumHealth(0), 1000)
            XCTAssertEqual(fight.maximumHealth(1), 1500)
            XCTAssertEqual(fight.fighters.map(\.health), [1000, 1500])
            fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
            XCTAssertTrue(F.until(&fight) { $0.landedHits[0] == 1 })
            XCTAssertEqual(fight.damageDealt[0], 1500, "Overkill must not count beyond the configured remaining health")
            if mode == .practice {
                XCTAssertEqual(fight.phase, .fighting)
                XCTAssertEqual(fight.fighters[1].health, 1500)
            } else {
                guard case .roundBreak(let winner, _) = fight.phase else { return XCTFail("Expected a KO round break") }
                XCTAssertEqual(winner, 0)
                XCTAssertEqual(fight.fighters[1].health, 0)
                XCTAssertTrue(F.until(&fight, limit: 151) { $0.phase == .fighting })
                XCTAssertEqual(fight.fighters.map(\.health), [1000, 1500])
                XCTAssertEqual(fight.panguState(1)?.light, rules.light.initial)
            }
        }
    }

    func testTimeoutComparesRemainingHealthFractionsAndKeepsOneHPDifferencesExact() throws {
        var rules = DuelPanguTestFixture.rules(level: 2)
        rules.maximumHealth = 1500
        rules.light.initial = 0
        for damagePangu in [false, true] {
            var fight = try F.fight(rules: rules, panguFirst: false, mode: .versus, ordinaryDamage: 1)
            if damagePangu {
                fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
                XCTAssertTrue(F.until(&fight) { $0.landedHits[0] == 1 })
                XCTAssertEqual(fight.fighters.map(\.health), [1000, 1499])
            }
            XCTAssertTrue(F.until(&fight, limit: 3601) { $0.phase != .fighting })
            guard case .roundBreak(let winner, _) = fight.phase else { return XCTFail("Expected a timeout round break") }
            XCTAssertEqual(winner, damagePangu ? 0 : nil,
                           "This application's timeout rule compares remaining fractions, not unlike raw HP totals")
            XCTAssertEqual(fight.wins, damagePangu ? [1, 0] : [0, 0])
            if !damagePangu {
                XCTAssertEqual(fight.landedHits, [0, 0])
                XCTAssertEqual(fight.fighters.map(\.health), [1000, 1500])
            }
        }
    }

    func testAttackSpeedChecksEverySingleTickWindowAndStopsAtTheHitBeforeFurtherMicrosteps() throws {
        var rules = DuelPanguTestFixture.rules(level: 4)
        rules.combo.holdTicks = 200; rules.combo.level6HoldTicks = 200
        rules.combo.level4SpeedThreshold = 1; rules.combo.level4AttackSpeedBps = 40_000
        rules.combo.damageBonusPerPointBps = 0; rules.combo.maximumDamageBonusBps = 0
        rules.heavyWindCount = 0; rules.typhoonWindCount = 0; rules.tranceWindCount = 0
        rules.earth.earthquakeWindowTicks = 0; rules.earth.boulderBonusWindowTicks = 0
        var fight = try F.fight(rules: rules, ordinaryDamage: 9, ordinaryHitStop: 4, ordinaryWindow: 2...2)
        fight.step(.init(vertical: -1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertTrue(F.until(&fight) { $0.landedHits[0] == 1 })
        F.drainHitStop(&fight)
        XCTAssertTrue(F.until(&fight) { $0.canUsePangu(.shard, index: 0) })
        XCTAssertEqual(fight.panguState(0)?.attackSpeedBps, 40_000)
        let beforeHealth = fight.fighters[1].health

        // Tick 2 is strictly inside the three extra logical steps available at
        // this speed. Sampling only their final frame would miss this strike.
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        XCTAssertEqual(fight.landedHits[0], 2)
        XCTAssertEqual(fight.fighters[1].health, beforeHealth - 9)
        XCTAssertEqual(fight.fighters[0].weaponPose?.tick, 2,
                       "The hit-stop guard must prevent consuming the remaining tick-3 microstep")
        XCTAssertEqual(fight.hitStop, 4)
        let stoppedPose = fight.fighters[0].weaponPose
        for _ in 0..<4 {
            fight.step(.neutral, opponent: .neutral)
            XCTAssertEqual(fight.fighters[0].weaponPose, stoppedPose)
            XCTAssertEqual(fight.landedHits[0], 2)
            XCTAssertEqual(fight.fighters[1].health, beforeHealth - 9)
        }
        for _ in 0..<30 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.landedHits[0], 2, "The consumed strike ID cannot hit again when accelerated playback resumes")
        XCTAssertEqual(fight.fighters[1].health, beforeHealth - 9)
    }

    func testLegacyCatalogRetainsTwoHammersAndItsExistingShadowWithoutPanguActivation() throws {
        let old = DuelWeaponTestFixtures.catalog()
        var fight = try DuelWeaponTestFixtures.fight(catalog: old)
        XCTAssertNil(fight.panguState(0))
        XCTAssertNil(fight.panguState(1))
        XCTAssertEqual(fight.profiles[1].id, "liu_hammers")
        XCTAssertEqual(Set(fight.profiles[1].activeWeaponSides), ["left", "right"])
        XCTAssertNil(fight.profiles[1].panguRules)
        XCTAssertNil(fight.panguAbility(for: .init(move: -1, weaponCommand: .shadow), index: 1))
        XCTAssertFalse(fight.supports(.ranged, index: 1))
        fight.step(.neutral, opponent: .init(move: -1, weaponCommand: .shadow))
        XCTAssertTrue(fight.shadowIsActive(1))
        XCTAssertNotNil(fight.shadowVisual(1))
        XCTAssertEqual(fight.fighters[1].energy, 0)
        XCTAssertNil(fight.panguState(1))
        XCTAssertEqual(old, DuelWeaponTestFixtures.catalog(), "The opt-in fixture must not mutate the old catalog")
    }
}
