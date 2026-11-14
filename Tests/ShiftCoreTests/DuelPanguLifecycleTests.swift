import XCTest
@testable import ShiftCore

/// These cases use synthetic rules and real fight inputs. They exercise
/// lifecycle boundaries, not original-game balance or animation acceptance.
final class DuelPanguLifecycleTests: XCTestCase {
    private typealias F = DuelPanguFightFixture

    func testKnockdownAfterSplitterCastEndsCancelsItsUnreleasedFollowupWinds() throws {
        var rules = DuelPanguTestFixture.rules(level: 4)
        rules.combo.affectedKinds = []
        rules.light.absorbedKinds = []
        rules.heavyWindCount = 0
        rules.typhoonWindCount = 0
        rules.tranceWindCount = 0
        rules.earth.splitterDamageBonusBps = 0
        rules.earth.dreadTicks = 0
        rules.earth.splitterWindCount = 3
        rules.earth.splitterWindIntervalTicks = 80
        F.changingAttack(&rules, .splitter) {
            $0.delivery = .melee
            $0.rangeMillimeters = 1200
            $0.damage = 20
            $0.hitStopTicks = 0
            $0.stunTicks = 0
            $0.airHoldTicks = 0
            $0.knocksDown = false
            $0.impact = .init(distanceMillimeters: 0, durationTicks: 1)
        }
        rules.windBlade.damage = 7
        rules.windBlade.projectileSpeedMillimetersPerTick = 1200
        rules.windBlade.rangeMillimeters = 2000
        rules.windBlade.hitStopTicks = 0
        rules.windBlade.stunTicks = 0
        rules.windBlade.airHoldTicks = 0
        rules.windBlade.knocksDown = false
        rules.windBlade.impact = .init(distanceMillimeters: 0, durationTicks: 1)

        let source = try F.catalog(rules: rules, ordinaryHitStop: 0)
        let catalog = try DuelWeaponTestFixtures.changing(source) { profiles in
            guard var combat = profiles[0]["combatRules"] as? [String: Any],
                  var attacks = combat["attacks"] as? [[String: Any]] else {
                return XCTFail("The Sun fixture must have explicit ordinary strike rules")
            }
            for index in attacks.indices where attacks[index]["command"] as? String == "weapon" {
                guard var strikes = attacks[index]["strikes"] as? [[String: Any]] else {
                    return XCTFail("The ordinary weapon rule must contain strikes")
                }
                for strike in strikes.indices { strikes[strike]["knocksDown"] = true }
                attacks[index]["strikes"] = strikes
            }
            combat["attacks"] = attacks
            profiles[0]["combatRules"] = combat
        }
        try catalog.validate()
        let sun = try XCTUnwrap(catalog.profile(for: .ember))
        let sunWeapon = try XCTUnwrap(sun.clip(command: .weapon))
        let knockdownRule = try XCTUnwrap(sun.resolvedCombatRule(command: .weapon, clipName: sunWeapon.name))
        XCTAssertTrue(knockdownRule.strikes.allSatisfy(\.knocksDown))
        var interrupted = try XCTUnwrap(DuelWeaponFight(fighters: [
            .init(hero: .liu, x: 3500, facing: 1),
            .init(hero: .ember, x: 4300, facing: -1)
        ], mode: .practice, difficulty: .learning, catalog: catalog, seed: 41))

        interrupted.step(.init(vertical: 1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertTrue(F.until(&interrupted, limit: 40) {
            $0.landedHits[0] == 2 && $0.panguState(0)?.activeCast == nil
                && $0.fighters[1].stun == 0 && $0.fighters[1].weaponPose?.reaction == false
        }, "The Splitter and its first wind must actually hit, finish, and let Sun recover")
        XCTAssertEqual(interrupted.landedHits[0], 2)
        XCTAssertEqual(interrupted.fighters[1].health, 973)
        XCTAssertNil(interrupted.panguState(0)?.activeCast)
        XCTAssertLessThan(interrupted.frame, rules.earth.splitterWindIntervalTicks,
                          "The two delayed winds must still be pending when the counterattack starts")

        // This untouched branch proves the same scheduled attacks would hit.
        // A cancelled branch alone could pass if the follow-ups never existed.
        var uninterrupted = interrupted
        interrupted.step(.neutral, opponent: .init(weaponCommand: .weapon))
        XCTAssertNotNil(interrupted.fighters[1].attack)
        XCTAssertTrue(F.until(&interrupted, limit: 12) { $0.landedHits[1] == 1 })
        XCTAssertEqual(interrupted.contacts.last?.attacker, 1)
        XCTAssertEqual(interrupted.contacts.last?.kind, .hit)
        XCTAssertGreaterThan(interrupted.fighters[0].knockdown, 0)
        XCTAssertNil(interrupted.panguState(0)?.activeCast,
                     "Cancellation must work without a remaining cast to interrupt")
        let healthAfterCounterattack = interrupted.fighters[1].health
        XCTAssertEqual(healthAfterCounterattack, 973)

        for _ in 0..<(rules.earth.splitterWindIntervalTicks * 2 + 40) {
            interrupted.step(.neutral, opponent: .neutral)
            uninterrupted.step(.neutral, opponent: .neutral)
        }
        XCTAssertEqual(uninterrupted.landedHits[0], 4,
                       "The control branch must receive the Splitter and all three winds")
        XCTAssertEqual(uninterrupted.fighters[1].health, 959)
        XCTAssertEqual(interrupted.landedHits[0], 2)
        XCTAssertEqual(interrupted.fighters[1].health, healthAfterCounterattack,
                       "No not-yet-released wind may emerge from the knocked-down caster")
    }

    func testHeavenfallStartupWindUsesTheGroundOriginOnItsActualLandingTick() throws {
        var rules = DuelPanguTestFixture.rules(level: 6)
        rules.combo.affectedKinds = []
        rules.policies.windTrigger = .attackStarted
        rules.heavenfall.tranceTrigger = .landing
        rules.heavenfall.level6DamageBonusBps = 0
        rules.heavenfall.targetPetrifyTicks = 30
        rules.heavyWindCount = 0
        rules.typhoonWindCount = 0
        rules.tranceWindCount = 1
        F.changingAttack(&rules, .heavenfall) {
            $0.damage = 20
            $0.hitStopTicks = 0
            $0.impact = .init(distanceMillimeters: 0, durationTicks: 1)
        }
        rules.windBlade.damage = 7
        rules.windBlade.projectileSpeedMillimetersPerTick = 2000
        rules.windBlade.hitboxBottomMillimeters = 800
        rules.windBlade.hitboxTopMillimeters = 820
        rules.windBlade.radiusMillimeters = 10
        rules.windBlade.hitStopTicks = 0
        rules.windBlade.impact = .init(distanceMillimeters: 0, durationTicks: 1)
        var fight = try F.fight(rules: rules, distance: 1800)
        let lastAirborneHeight = rules.heavenfall.pillarHeightMillimeters
            - rules.heavenfall.descentVelocityMillimetersPerTick
        XCTAssertGreaterThan(lastAirborneHeight + rules.windBlade.hitboxBottomMillimeters,
                             fight.hurtBox(1).maxY + rules.windBlade.radiusMillimeters,
                             "The old airborne origin must miss this narrow ground-level target")

        fight.step(.init(weaponCommand: .shadow), opponent: .neutral)
        var sawFalling = false
        var sawLanding = false
        for _ in 0..<45 {
            let beforeHeight = fight.fighters[0].y
            fight.step(.neutral, opponent: .neutral)
            let state = try XCTUnwrap(fight.panguState(0))
            sawFalling = sawFalling || state.activeCast?.phase == .falling
            if beforeHeight > 0 && fight.fighters[0].y == 0 {
                sawLanding = true
                XCTAssertTrue(sawFalling)
                XCTAssertEqual(beforeHeight, lastAirborneHeight)
                XCTAssertEqual(state.activeCast?.phase, .landing)
                XCTAssertEqual(state.tranceRemainingTicks, rules.trance.durationTicks)
                let contacts = fight.contacts.filter { $0.attacker == 0 }
                XCTAssertEqual(contacts.count, 2,
                               "The slam and its one startup wind must both contact on this landing tick")
                XCTAssertEqual(fight.landedHits[0], 2)
                XCTAssertEqual(fight.fighters[1].health, 973)
                XCTAssertTrue(contacts.contains { abs($0.position.y - 0.81) < 0.001 },
                              "The wind must cross at its ground-relative height, not at the previous flight height")
                break
            }
            XCTAssertEqual(fight.landedHits[0], 0)
        }
        XCTAssertTrue(sawLanding, "The test must reach physical landing, not merely exhaust its frame budget")
        for _ in 0..<35 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.landedHits[0], 2, "The deferred landing batch must be consumed exactly once")
        XCTAssertEqual(fight.fighters[1].health, 973)
    }

    func testActualHitInterruptsAirborneHeavenfallAndReturnsItsCasterToGroundWithoutASlam() throws {
        var rules = DuelPanguTestFixture.rules(level: 2)
        rules.heavenfall.targetPetrifyTicks = 3
        rules.heavenfall.riseTicks = 4
        rules.heavenfall.chargeTicks = 80
        rules.heavenfall.pillarHeightMillimeters = 400
        rules.heavenfall.descentVelocityMillimetersPerTick = 200
        rules.heavenfall.fallTicks = 2
        let heavenfallIndex = try XCTUnwrap(rules.abilities.firstIndex { $0.ability == .heavenfall })
        rules.abilities[heavenfallIndex].interruptible = true
        rules.abilities[heavenfallIndex].damageImmune = false
        var fight = try F.fight(rules: rules, ordinaryHitStop: 1)

        fight.step(.init(weaponCommand: .shadow), opponent: .neutral)
        XCTAssertEqual(fight.panguState(0)?.activeCast?.ability, .heavenfall)
        for _ in 0..<rules.heavenfall.targetPetrifyTicks {
            fight.step(.neutral, opponent: .init(weaponCommand: .weapon))
            XCTAssertNil(fight.fighters[1].attack,
                         "Actual petrification must suppress the opponent's attempted attacks")
            XCTAssertGreaterThan(fight.fighters[1].stun, 0)
            XCTAssertEqual(fight.landedHits[1], 0)
        }

        // The current two-profile fixture has no autonomous opponent projectile:
        // Sun cannot hit while petrified. Let that short control expire, while
        // Heavenfall deliberately remains in a much longer charge phase. This
        // verifies an actual airborne interruption and its spatial cleanup; it
        // does not claim to prove early release of still-active petrification.
        XCTAssertTrue(F.until(&fight, limit: 40) {
            $0.fighters[1].stun == 0 && $0.fighters[1].weaponPose?.reaction == false
        })
        XCTAssertEqual(fight.landedHits, [0, 0],
                       "Commands pressed during petrification must not become a delayed counterattack")
        XCTAssertEqual(fight.panguState(0)?.activeCast?.phase, .charging)
        XCTAssertEqual(fight.fighters[0].y, rules.heavenfall.pillarHeightMillimeters)
        XCTAssertTrue(fight.isAirborne(0))
        let opponentHealthBeforeInterrupt = fight.fighters[1].health

        fight.step(.neutral, opponent: .init(weaponCommand: .weapon))
        XCTAssertEqual(fight.fighters[1].weaponPose?.clip, fight.profiles[1].roles["weapon1"])
        XCTAssertNotNil(fight.fighters[1].attack)
        XCTAssertTrue(F.until(&fight, limit: 12) { $0.landedHits[1] == 1 })
        XCTAssertEqual(fight.contacts.last?.attacker, 1)
        XCTAssertEqual(fight.contacts.last?.kind, .hit)
        XCTAssertGreaterThan(fight.fighters[0].y, 0,
                             "The hit must interrupt an elevated caster rather than an already completed cast")
        XCTAssertNil(fight.panguState(0)?.activeCast)
        XCTAssertEqual(fight.fighters[0].weaponPose?.reaction, true)
        let lightAfterInterrupt = try XCTUnwrap(fight.panguState(0)).light

        XCTAssertTrue(F.until(&fight, limit: 90) {
            $0.fighters[0].y == 0 && $0.fighters[0].velocityY == 0 && !$0.isAirborne(0)
                && $0.fighters[0].stun == 0 && $0.fighters[0].weaponPose?.reaction == false
        }, "The interrupted pillar must release the body into a completed grounded recovery")
        for _ in 0..<rules.heavenfall.duration { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.landedHits[0], 0)
        XCTAssertEqual(fight.fighters[1].health, opponentHealthBeforeInterrupt)
        XCTAssertEqual(fight.panguState(0)?.light, lightAfterInterrupt,
                       "An interrupted charge must not continue restoring Light")
        XCTAssertNil(fight.panguState(0)?.activeCast)
        XCTAssertEqual(fight.fighters[0].y, 0)
        XCTAssertEqual(fight.fighters[0].velocityY, 0)
        fight.step(.neutral, opponent: .init(weaponCommand: .kick))
        XCTAssertEqual(fight.fighters[1].weaponPose?.clip, fight.profiles[1].roles["kick"])
        XCTAssertNotNil(fight.fighters[1].attack, "No stale petrification may block fresh input after recovery")
    }
}
