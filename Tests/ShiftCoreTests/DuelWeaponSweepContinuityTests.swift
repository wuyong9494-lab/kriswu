import XCTest
@testable import ShiftCore

/// Synthetic endpoint tracks exercise actual damage and swing decisions. They
/// do not claim acceptance of the private source models or their animation.
final class DuelWeaponSweepContinuityTests: XCTestCase {
    func testAdjacentCeilingIsInclusiveForBothWeaponsWithoutPhantomHits() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            for step in [0.74, 0.75, 0.76] {
                let catalog = try catalog { tick in
                    .init(x: tick < 3 ? 0 : step, y: 1)
                }
                let result = try run(catalog: catalog, hero: hero)
                XCTAssertEqual(result.hits, step <= 0.75 ? 1 : 0, "\(hero) step \(step)")
                XCTAssertEqual(result.swings, step <= 0.75 ? 1 : 0, "\(hero) step \(step)")
            }
        }
    }

    func testTeleportedWeaponCannotCreateDamageAudioOrAnActiveTrail() throws {
        let catalog = try catalog { tick in .init(x: tick < 3 ? -1 : 1, y: 1) }
        for hero in [DuelGame.Hero.ember, .liu] {
            let result = try run(catalog: catalog, hero: hero)
            XCTAssertEqual(result.hits, 0)
            XCTAssertEqual(result.damage, 0)
            XCTAssertEqual(result.swings, 0)
            XCTAssertFalse(result.activeTrail)
        }
    }

    func testOutOfPlanePreviousSampleCannotSweepBackIntoTorso() throws {
        let catalog = try catalog { tick in
            .init(x: tick < 3 ? 0.1 : 0.7, y: 1, z: tick < 3 ? 0.81 : 0.70)
        }
        let result = try run(catalog: catalog, hero: .ember)
        XCTAssertEqual(result.hits, 0, "Both ends of a contact sweep must stay in the accepted plane")
        XCTAssertEqual(result.damage, 0)
    }

    func testDepthDiscontinuityCountsEvenWhenProjectedMovementLooksSmall() throws {
        let catalog = try catalog { tick in
            .init(x: tick < 3 ? 0.6 : 0.7, y: 1, z: tick < 3 ? -0.7 : 0.7)
        }
        let result = try run(catalog: catalog, hero: .liu)
        XCTAssertEqual(result.hits, 0)
        XCTAssertEqual(result.swings, 0)
    }

    func testBadPeakDoesNotSilenceLaterValidStroke() throws {
        let catalog = try catalog { tick in
            let x: Double
            switch tick {
            case 3...4: x = 3
            case 7...: x = 0.7
            default: x = 0
            }
            return .init(x: x, y: 1)
        }
        for hero in [DuelGame.Hero.ember, .liu] {
            let result = try run(catalog: catalog, hero: hero)
            XCTAssertEqual(result.hits, 1)
            XCTAssertEqual(result.swings, 1, "The valid stroke must determine onset instead of a teleport peak")
            XCTAssertEqual(result.contactTicks, [7], "The earlier teleport must not consume the hit budget")
            XCTAssertEqual(result.swingTicks, [7], "The earlier teleport must not determine sound onset")
            XCTAssertTrue(result.activeTrail)
        }
    }

    func testOneDiscontinuousHammerDoesNotSuppressTheOtherHammer() throws {
        let valid = try catalog { tick in .init(x: tick < 7 ? 0 : 0.7, y: 1) }
        let mixed = try DuelWeaponTestFixtures.changing(valid) { profiles in
            var clips = profiles[1]["clips"] as! [[String: Any]]
            let index = clips.firstIndex { $0["name"] as? String == "hammers_weapon" }!
            var tracks = clips[index]["tracks"] as! [String: Any]
            let tips = (0..<(2 * DuelWeaponTestFixtures.frames - 1)).map { tick in
                [tick < 7 ? -1.0 : 1.0, 1.0, 0.0]
            }
            tracks["weaponTipL"] = tips
            tracks["weaponBaseL"] = tips.map { [$0[0] - 0.1, $0[1], $0[2]] }
            clips[index]["tracks"] = tracks; profiles[1]["clips"] = clips
        }
        let result = try run(catalog: mixed, hero: .liu)
        XCTAssertEqual(result.contactTicks, [7])
        XCTAssertEqual(result.swingTicks, [7])
        XCTAssertTrue(result.activeTrail)
    }

    func testInvalidBaseCannotCreateAFalseShaftHitFromAContinuousTip() throws {
        for outOfPlane in [false, true] {
            let valid = try catalog { tick in .init(x: tick < 3 ? -1 : -0.9, y: 1) }
            let broken = try DuelWeaponTestFixtures.changing(valid) { profiles in
                var clips = profiles[0]["clips"] as! [[String: Any]]
                let index = clips.firstIndex { $0["name"] as? String == "katana_weapon" }!
                var tracks = clips[index]["tracks"] as! [String: Any]
                tracks["weaponBaseR"] = (0..<(2 * DuelWeaponTestFixtures.frames - 1)).map { tick in
                    [outOfPlane ? 2.0 : (tick < 3 ? -1.1 : 2.0), 1.0, outOfPlane ? 0.81 : 0.0]
                }
                clips[index]["tracks"] = tracks; profiles[0]["clips"] = clips
            }
            let result = try run(catalog: broken, hero: .ember)
            XCTAssertEqual(result.hits, 0, "Invalid base must not turn a distant moving tip into a torso hit")
            XCTAssertEqual(result.damage, 0)
        }
    }

    func testInvalidDistancesCannotBeAcceptedAsContinuity() {
        for distance in [-1.0, Double.nan, .infinity, -.infinity] {
            XCTAssertFalse(DuelWeaponSweepContinuity.accepts(distance: distance))
        }
        XCTAssertFalse(DuelWeaponSweepContinuity.accepts(distance:
            DuelWeaponSweepContinuity.distance(from: .init(), to: .init(x: .infinity))))
    }

    private func catalog(_ point: (Int) -> DuelWeaponPoint) throws -> DuelWeaponCatalog {
        try DuelWeaponTestFixtures.changing(DuelWeaponTestFixtures.catalog()) { profiles in
            for index in profiles.indices {
                var clips = profiles[index]["clips"] as! [[String: Any]]
                let role = (profiles[index]["roles"] as! [String: String])["weapon1"]!
                let clipIndex = clips.firstIndex { $0["name"] as? String == role }!
                var tracks = clips[clipIndex]["tracks"] as! [String: Any]
                let tips = (0..<(2 * DuelWeaponTestFixtures.frames - 1)).map { tick -> [Double] in
                    let p = point(tick); return [p.x, p.y, p.z]
                }
                let bases = tips.map { [$0[0] - 0.1, $0[1], $0[2]] }
                for side in profiles[index]["activeWeaponSides"] as! [String] {
                    let suffix = side == "left" ? "L" : "R"
                    tracks["weaponBase" + suffix] = bases
                    tracks["weaponTip" + suffix] = tips
                }
                clips[clipIndex]["tracks"] = tracks
                profiles[index]["clips"] = clips
            }
        }
    }

    private func run(catalog: DuelWeaponCatalog, hero: DuelGame.Hero) throws
        -> (hits: Int, damage: Int, swings: Int, activeTrail: Bool, contactTicks: [Int], swingTicks: [Int]) {
        let other: DuelGame.Hero = hero == .ember ? .liu : .ember
        var fight = try XCTUnwrap(DuelWeaponFight(
            fighters: [.init(hero: hero, x: 3500, facing: 1), .init(hero: other, x: 4300, facing: -1)],
            mode: .practice, difficulty: .learning, catalog: catalog, seed: 4))
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        var swings = 0, activeTrail = false
        var contactTicks: [Int] = [], swingTicks: [Int] = []
        for _ in 0..<30 {
            fight.step(.neutral, opponent: .neutral)
            swings += fight.swings.filter { $0.attacker == 0 }.count
            if fight.contacts.contains(where: { $0.attacker == 0 }) { contactTicks.append(fight.fighters[0].weaponPose?.tick ?? -1) }
            if fight.swings.contains(where: { $0.attacker == 0 }) { swingTicks.append(fight.fighters[0].weaponPose?.tick ?? -1) }
            activeTrail = activeTrail || fight.weaponTrailIsActive(0)
        }
        return (fight.landedHits[0], fight.damageDealt[0], swings, activeTrail, contactTicks, swingTicks)
    }
}
