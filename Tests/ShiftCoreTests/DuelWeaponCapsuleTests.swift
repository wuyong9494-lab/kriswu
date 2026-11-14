import XCTest
@testable import ShiftCore

final class DuelWeaponCapsuleTests: XCTestCase {
    private func point(_ x: Double, _ y: Double = 0, _ z: Double = 0) -> DuelWeaponPoint { .init(x: x, y: y, z: z) }
    private func capsule(_ a: DuelWeaponPoint, _ b: DuelWeaponPoint? = nil, radius: Double = 0.05) -> DuelWeaponCapsule {
        .init(a: a, b: b ?? a, radius: radius)
    }
    func testActualCapsulesRejectEmptyDiagonalBoundingCornersAndOutOfPlanePoints() {
        let diagonal = capsule(point(-1, 0), point(1, 2))
        XCTAssertFalse(diagonal.overlaps(capsule(point(0.8, 0.2))))
        XCTAssertTrue(diagonal.overlaps(capsule(point(0, 1))))
        XCTAssertFalse(diagonal.overlaps(capsule(point(0, 1, 1))))
    }
    func testFastMovingCapsuleCannotTunnelThroughThinStationaryForearm() throws {
        let start = capsule(point(-1), radius: 0.04), end = capsule(point(1), radius: 0.04)
        let arm = capsule(point(0, -0.5), point(0, 0.5), radius: 0.06)
        XCTAssertFalse(start.overlaps(arm)); XCTAssertFalse(end.overlaps(arm))
        let hit = try XCTUnwrap(DuelWeaponCapsule.swept(attackBefore: start, attackAfter: end, hurtBefore: arm, hurtAfter: arm))
        XCTAssertEqual(hit.time, 0.45, accuracy: 0.00001)
    }
    func testMovingHurtCapsuleIsSweptAgainstAStationaryActiveEdge() throws {
        let edge = capsule(point(0, -0.5), point(0, 0.5), radius: 0.04)
        let before = capsule(point(-1), radius: 0.06), after = capsule(point(1), radius: 0.06)
        let hit = try XCTUnwrap(DuelWeaponCapsule.swept(attackBefore: edge, attackAfter: edge, hurtBefore: before, hurtAfter: after))
        XCTAssertEqual(hit.time, 0.45, accuracy: 0.00001)
    }
    func testRotatingBladeInteriorHitsWithoutEitherEndpointCrossingTheBody() {
        let before = capsule(point(-1, 1), point(1, -1)), after = capsule(point(-1, -1), point(1, 1))
        let torso = capsule(point(0.5, 0))
        XCTAssertFalse(before.overlaps(torso)); XCTAssertFalse(after.overlaps(torso))
        XCTAssertNotNil(DuelWeaponCapsule.swept(attackBefore: before, attackAfter: after, hurtBefore: torso, hurtAfter: torso))
    }
    func testGrazingContactAndParallelMissAreStable() {
        let start = capsule(point(-1, 0.1)), end = capsule(point(1, 0.1)), target = capsule(point(0))
        XCTAssertNotNil(DuelWeaponCapsule.swept(attackBefore: start, attackAfter: end, hurtBefore: target, hurtAfter: target))
        let missA = capsule(point(-1, 0.1001)), missB = capsule(point(1, 0.1001))
        XCTAssertNil(DuelWeaponCapsule.swept(attackBefore: missA, attackAfter: missB, hurtBefore: target, hurtAfter: target))
    }

    private func sourceCatalog(handleOnly: Bool = false, radius: Int = 40,
                               playbackTicks: Int? = nil) throws -> DuelWeaponCatalog {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(DuelTriadFightFixture.catalog())) as? [String: Any])
        var profiles = try XCTUnwrap(object["profiles"] as? [[String: Any]])
        for index in profiles.indices {
            var clips = try XCTUnwrap(profiles[index]["clips"] as? [[String: Any]])
            for n in clips.indices {
                let count = 2 * (clips[n]["frames"] as! Int) - 1
                func track(_ x: Double, _ y: Double) -> [[Double]] { Array(repeating: [x, y, 0], count: count) }
                var tracks = clips[n]["tracks"] as! [String: Any]
                tracks["hurtCapsules"] = [["id": "Torso", "radiusMillimeters": 20, "defense": "body",
                    "base": track(0, 0.7), "tip": track(0, 1.3)]]
                if index == 0 {
                    tracks["collisionEdges"] = [
                        ["id": "Ninjato_Attacking_Edge_r", "side": "right", "radiusMillimeters": radius,
                         "base": track(0.5, 1), "tip": track(0.9, 1)],
                        ["id": "Ninjato_Handle_Attacking_Edge_r", "side": "right", "radiusMillimeters": radius,
                         "base": track(0.1, 1), "tip": track(0.2, 1)]]
                }
                clips[n]["tracks"] = tracks
                if let playbackTicks { clips[n]["playbackTicks"] = playbackTicks }
            }
            profiles[index]["clips"] = clips
            if handleOnly && index == 0 {
                var combat = profiles[index]["combatRules"] as! [String: Any]
                var attacks = combat["attacks"] as! [[String: Any]]
                for at in attacks.indices where !(attacks[at]["command"] as! String).hasPrefix("kick") {
                    var strikes = attacks[at]["strikes"] as! [[String: Any]]
                    for s in strikes.indices { strikes[s]["collisionEdgeIDs"] = ["Ninjato_Handle_Attacking_Edge_r"] }
                    attacks[at]["strikes"] = strikes
                }
                combat["attacks"] = attacks; profiles[index]["combatRules"] = combat
            }
        }
        object["profiles"] = profiles
        return try JSONDecoder().decode(DuelWeaponCatalog.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func fight(distance: Int, handleOnly: Bool = false) throws -> DuelWeaponFight {
        let catalog = try sourceCatalog(handleOnly: handleOnly)
        try catalog.validate()
        return try XCTUnwrap(DuelWeaponFight(fighters: [.init(hero: .ember, x: 3500, facing: 1),
            .init(hero: .liu, x: 3500 + distance, facing: -1)], mode: .practice,
            difficulty: .learning, catalog: catalog, seed: 2))
    }
    func testSourceBodyAndFourCentimeterEdgeReplaceGenericRectangleReach() throws {
        var miss = try fight(distance: 1200)
        miss.step(.init(weaponCommand: .weapon), opponent: .neutral)
        for _ in 0..<30 { miss.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(miss.landedHits[0], 0)
        XCTAssertEqual(miss.hurtBox(1).maxX - miss.hurtBox(1).minX, 40)
        var hit = try fight(distance: 900)
        hit.step(.init(weaponCommand: .weapon), opponent: .neutral)
        XCTAssertTrue(DuelTriadFightFixture.until(&hit) { $0.landedHits[0] == 1 })
    }
    func testExplicitHandleBindingCannotAcquireBladeReach() throws {
        var fight = try fight(distance: 900, handleOnly: true)
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        for _ in 0..<30 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.landedHits[0], 0)
    }
    func testSourcePlaybackTimeAndCollisionRadiusParticipateInCanonicalIdentity() throws {
        let normal = try sourceCatalog(), slow = try sourceCatalog(playbackTicks: 32), wider = try sourceCatalog(radius: 41)
        try normal.validate(); try slow.validate(); try wider.validate()
        let clip = try XCTUnwrap(slow.profile(for: .ember)?.clip(role: "weapon1"))
        XCTAssertEqual(clip.ticks, 32); XCTAssertEqual(clip.tick(atSourceFrame: 4), 16)
        XCTAssertEqual(clip.phase(at: 16), 0.5)
        XCTAssertNotEqual(try DuelReplayStateEncoding.encodeCatalog(normal), try DuelReplayStateEncoding.encodeCatalog(slow))
        XCTAssertNotEqual(try DuelReplayStateEncoding.encodeCatalog(normal), try DuelReplayStateEncoding.encodeCatalog(wider))
        XCTAssertThrowsError(try sourceCatalog(radius: 0).validate())
        XCTAssertThrowsError(try sourceCatalog(playbackTicks: 0).validate())
    }
}
