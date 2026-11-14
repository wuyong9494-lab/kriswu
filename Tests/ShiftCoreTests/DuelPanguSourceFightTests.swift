import XCTest
@testable import ShiftCore

/// Production event ordering with declared synthetic bodies and 1,000-unit
/// HP/power scales. Native source-asset acceptance is separate.
final class DuelPanguSourceFightTests: XCTestCase {
    private func rules(level: Int = 6) throws -> DuelPanguRules {
        try .d19HeavenlyKing(level: level, maximumHealth: 1000, weaponPower: 1000,
            unarmedPower: 1000, magicPower: 1000, rangedPower: 1000,
            spatialTemplate: DuelPanguTestFixture.rules(level: level))
    }

    func testSourceOrdinaryHitCountsComboBeforeItsOwnDamageExactlyOnce() throws {
        var fight = try DuelPanguFightFixture.fight(rules: rules(), ordinaryDamage: 100)
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        XCTAssertTrue(DuelPanguFightFixture.until(&fight) { $0.landedHits[0] == 1 })
        XCTAssertEqual(fight.panguState(0)?.combo, 1)
        XCTAssertEqual(fight.fighters[1].health, 899, "The first source PreHit grants 1% before its own damage")
    }

    func testHeavenfallKeepsItsCastWhileOrdinaryDamageReachesHealth() throws {
        var fight = try DuelPanguFightFixture.fight(rules: rules(), ordinaryDamage: 100,
            ordinaryImpact: .init(distanceMillimeters: 300, durationTicks: 10))
        fight.step(.init(weaponCommand: .shadow), opponent: .init(weaponCommand: .weapon))
        XCTAssertTrue(DuelPanguFightFixture.until(&fight, limit: 15) { $0.fighters[0].health < 1000 })
        XCTAssertEqual(fight.fighters[0].health, 900)
        XCTAssertEqual(fight.panguState(0)?.activeCast?.ability, .heavenfall)
        XCTAssertTrue(try XCTUnwrap(fight.panguState(0)).impactImmune)
        XCTAssertFalse(try XCTUnwrap(fight.panguState(0)).damageImmune)
        XCTAssertEqual(fight.fighters[0].x, 3500)
    }

    func testNextRoundPreservesTheSourcePersistentLightPool() throws {
        var fight = try DuelPanguFightFixture.fight(rules: rules(), mode: .versus, ordinaryDamage: 1000)
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        XCTAssertTrue(DuelPanguFightFixture.until(&fight) { $0.fighters[1].health == 0 })
        let light = try XCTUnwrap(fight.panguState(0)).light
        XCTAssertGreaterThan(light, 0)
        XCTAssertTrue(DuelPanguFightFixture.until(&fight, limit: 400) { $0.phase == .fighting && $0.fighters[1].health > 0 })
        XCTAssertEqual(fight.panguState(0)?.light, light)
    }

    func testSourceWindIsBornAtItsTargetAndDoesNotTravelOrBecomeBlockable() throws {
        var state = try XCTUnwrap(DuelPanguState(rules: rules(level: 2), seed: 7))
        for id in UInt64(1)...16 { state.contact(blocked: false, generated: false, hitID: id, heavy: id == 16) }
        var emitted: DuelPanguState.Attack?
        for _ in 0..<10 {
            for effect in state.step() { if case .attack(let value) = effect { emitted = value } }
        }
        let attack = try XCTUnwrap(emitted)
        XCTAssertEqual(attack.sourceStrike, .windBlade); XCTAssertEqual(attack.delivery, .ground)
        XCTAssertTrue(attack.unblockable); XCTAssertTrue(attack.anchorAtOpponent)
        let caster = DuelGame.Fighter(hero: .liu, x: 1800, facing: 1)
        var target = DuelGame.Fighter(hero: .ember, x: 6200, facing: -1); target.guarding = true
        var space = DuelPanguSpatialState()
        space.spawn(attack, owner: 0, fighter: caster, target: target, activeTicks: 1, frame: 10)
        XCTAssertEqual(space.volumes.first?.x, 6200)
        let hits = space.contacts(frame: 10, fighters: [caster, target],
            hurts: [.init(minX: 1600, maxX: 2000, minY: 0, maxY: 1800), .init(minX: 6000, maxX: 6400, minY: 0, maxY: 1800)],
            previousX: [1800, 6200], previousHurtY: [0, 0])
        XCTAssertEqual(hits.count, 1); XCTAssertEqual(hits.first?.blocked, false)
    }
}
