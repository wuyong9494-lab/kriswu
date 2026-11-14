import XCTest
@testable import ShiftCore

/// Synthetic pose points exercise the source-node contract. No geometry here
/// is presented as original character data or a native visual acceptance run.
final class DuelSourcePelvisTests: XCTestCase {
    private typealias F = DuelWeaponTestFixtures

    private func withPelvis(_ catalog: DuelWeaponCatalog = F.catalog(), lift: Double = 0.23,
                            points: (Int) -> [Double] = { _ in [0.33, 0.87, 0.17] }) throws -> DuelWeaponCatalog {
        try F.changing(catalog) { profiles in
            for index in profiles.indices {
                var clips = profiles[index]["clips"] as! [[String: Any]]
                for c in clips.indices {
                    let count = 2 * (clips[c]["frames"] as! Int) - 1
                    var tracks = clips[c]["tracks"] as! [String: Any]
                    tracks["pelvis"] = (0..<count).map(points)
                    tracks["groundLift"] = Array(repeating: lift, count: count)
                    clips[c]["tracks"] = tracks
                }
                profiles[index]["clips"] = clips
            }
        }
    }

    private func sourceRules() throws -> DuelPanguRules {
        var rules = try DuelPanguRules.d19HeavenlyKing(level: 4, maximumHealth: 1000,
            weaponPower: 1000, unarmedPower: 1000, magicPower: 1000, rangedPower: 1000,
            spatialTemplate: DuelPanguTestFixture.rules(level: 4))
        // Explicit synthetic spatial envelope makes the pelvis origin visible
        // directly at minY; these are not recovered D19 hitbox measurements.
        rules.windBlade.hitboxBottomMillimeters = 0
        rules.windBlade.hitboxTopMillimeters = 100
        return rules
    }

    private func wind(_ kind: DuelPanguRules.SourceStrike = .windBlade) throws -> DuelPanguState.Attack {
        var state = try XCTUnwrap(DuelPanguState(rules: sourceRules(), seed: 7))
        for id in UInt64(1)...16 {
            state.contact(blocked: false, generated: false, hitID: id, heavy: id == 16)
        }
        var emitted: DuelPanguState.Attack?
        for _ in 0..<10 {
            for effect in state.step() {
                if case .attack(let attack) = effect, attack.sourceStrike == .windBlade { emitted = attack }
            }
        }
        var attack = try XCTUnwrap(emitted)
        // Both source variants use the same explicit Enemy/Nodes/pelvis Align.
        // Their damage/timing distinction is covered by the runtime tests.
        attack.sourceStrike = kind
        return attack
    }

    func testLegacyCatalogKeepsAbsentPelvisAbsentAcrossRoundTrip() throws {
        let original = F.catalog()
        let decoded = try JSONDecoder().decode(DuelWeaponCatalog.self, from: JSONEncoder().encode(original))
        XCTAssertNoThrow(try decoded.validate())
        XCTAssertTrue(decoded.profiles.flatMap(\.clips).allSatisfy { $0.tracks.pelvis == nil })
        XCTAssertEqual(original, decoded)
    }

    func testPelvisShapeRequiresExactlyOnePointPerHalfSourceFrame() throws {
        let catalog = try withPelvis()
        XCTAssertNoThrow(try catalog.validate())
        for length in [0, 1, 16, 18] {
            let malformed = try F.changing(catalog) { profiles in
                var clips = profiles[0]["clips"] as! [[String: Any]]
                var tracks = clips[0]["tracks"] as! [String: Any]
                tracks["pelvis"] = Array(repeating: [0.0, 1.0, 0.0], count: length)
                clips[0]["tracks"] = tracks; profiles[0]["clips"] = clips
            }
            XCTAssertThrowsError(try malformed.validate(), "length \(length)")
        }
    }

    func testPelvisRejectsOutOfBoundsPointsAndMalformedCoordinateTuples() throws {
        for bad in [-100.0001, 100.0001, 1e308] {
            let catalog = try withPelvis(points: { _ in [bad, 1, 0] })
            XCTAssertThrowsError(try catalog.validate())
        }
        XCTAssertThrowsError(try withPelvis(points: { _ in [0, 1] }))
        XCTAssertThrowsError(try withPelvis(points: { _ in [0, 1, 0, 0] }))
    }

    func testPelvisChangesCanonicalIdentityWithoutChangingModelOrCOM() throws {
        let a = try withPelvis()
        let b = try withPelvis(points: { sample in [0.33, sample == 1 ? 0.91 : 0.87, 0.17] })
        XCTAssertEqual(a.profiles.map(\.sha256), b.profiles.map(\.sha256))
        XCTAssertEqual(a.profiles[0].clips[0].tracks.centerOfMass, b.profiles[0].clips[0].tracks.centerOfMass)
        XCTAssertNotEqual(try DuelReplayStateEncoding.encodeCatalog(a), try DuelReplayStateEncoding.encodeCatalog(b))
        XCTAssertNotEqual(try DuelReplayStateEncoding.encodeCatalog(F.catalog()),
                          try DuelReplayStateEncoding.encodeCatalog(a))
        let decoded = try JSONDecoder().decode(DuelWeaponCatalog.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(try DuelReplayStateEncoding.encodeCatalog(a), try DuelReplayStateEncoding.encodeCatalog(decoded))
    }

    func testWorldPelvisUsesEachActorsFacingAirHeightAndGroundLiftExactlyOnce() throws {
        let catalog = try withPelvis()
        for facing in [1, -1] {
            var a = DuelGame.Fighter(hero: .ember, x: 3000, facing: facing); a.y = 560
            var b = DuelGame.Fighter(hero: .liu, x: 7000, facing: -facing); b.y = 420
            let fight = try XCTUnwrap(DuelWeaponFight(fighters: [a, b], mode: .practice,
                difficulty: .learning, catalog: catalog, seed: 5))
            for index in 0..<2 {
                let fighter = fight.fighters[index], point = try XCTUnwrap(fight.sourcePelvis(index))
                XCTAssertEqual(point.x, Double(fighter.x) / 1000 + 0.33 * Double(fighter.facing), accuracy: 1e-9)
                XCTAssertEqual(point.y, Double(fighter.y) / 1000 + 0.87 + 0.23, accuracy: 1e-9)
                XCTAssertEqual(point.z, 0.17 * Double(fighter.facing), accuracy: 1e-9)
                XCTAssertNotEqual(point.y, Double(fighter.y) / 1000)
            }
            XCTAssertNil(fight.sourcePelvis(-1)); XCTAssertNil(fight.sourcePelvis(2))
        }
    }

    func testCurrentPoseUsesAuthoredHalfFramePelvisInsteadOfIntegerFrameEndpoints() throws {
        let catalog = try withPelvis(lift: 0, points: { sample in
            sample == 1 ? [0.41, 1.13, 0.2] : [0.1, 0.7, 0]
        })
        var fight = try F.fight(catalog: catalog)
        fight.step(.neutral, opponent: .neutral)
        XCTAssertEqual(fight.fighters[0].weaponPose?.tick, 1)
        let point = try XCTUnwrap(fight.sourcePelvis(0))
        XCTAssertEqual(point.x, Double(fight.fighters[0].x) / 1000 + 0.41, accuracy: 1e-9)
        XCTAssertEqual(point.y, 1.13, accuracy: 1e-9)
        XCTAssertEqual(point.z, 0.2, accuracy: 1e-9)
    }

    func testMissingPelvisNeverUsesRootDisplacementOrCenterOfMass() throws {
        let catalog = try F.changing(F.catalog()) { profiles in
            for index in profiles.indices {
                var clips = profiles[index]["clips"] as! [[String: Any]]
                for c in clips.indices {
                    let n = 2 * (clips[c]["frames"] as! Int) - 1
                    var tracks = clips[c]["tracks"] as! [String: Any]
                    tracks["root"] = Array(repeating: [0.6, 0.4, 0.0], count: n)
                    tracks["centerOfMass"] = Array(repeating: [0.3, 1.2, 0.0], count: n)
                    clips[c]["tracks"] = tracks
                }
                profiles[index]["clips"] = clips
            }
        }
        let fight = try F.fight(catalog: catalog)
        XCTAssertNotNil(fight.sourceCenterOfMass(0))
        XCTAssertNil(fight.sourcePelvis(0)); XCTAssertNil(fight.sourcePelvis(1))
    }

    func testBothSourceWindsAnchorAtExactEnemyPelvisAndKeepThatBirthPosition() throws {
        for kind in [DuelPanguRules.SourceStrike.windBlade, .upperWind] {
            for facing in [1, -1] {
                let attack = try wind(kind)
                var owner = DuelGame.Fighter(hero: .liu, x: 2000, facing: facing); owner.y = 190
                var target = DuelGame.Fighter(hero: .ember, x: 6200, facing: -facing); target.y = 410
                let point = DuelWeaponPoint(x: 6.2 - 0.33 * Double(facing), y: 1.51)
                var space = DuelPanguSpatialState()
                XCTAssertTrue(space.spawn(attack, owner: 0, fighter: owner, target: target,
                    targetPelvis: point, activeTicks: 1, frame: 10))
                let volume = try XCTUnwrap(space.volumes.first)
                XCTAssertEqual(volume.originX, Int((point.x * 1000).rounded()))
                XCTAssertEqual(volume.originY, 1510)
                XCTAssertEqual(volume.currentBounds(fighter: owner).minY, 1510)
                XCTAssertEqual(volume.direction, facing, "The caster direction is independent of enemy node alignment")
                owner.x += 400; owner.y += 300; target.x += 800; target.y += 600
                XCTAssertEqual(volume.currentBounds(fighter: owner).minY, 1510)
                XCTAssertEqual(volume.x, Int((point.x * 1000).rounded()))
            }
        }
    }

    func testMissingOrInvalidPelvisDoesNotSpawnAnApproximateSourceWind() throws {
        let owner = DuelGame.Fighter(hero: .liu, x: 2000, facing: 1)
        let target = DuelGame.Fighter(hero: .ember, x: 6200, facing: -1)
        for kind in [DuelPanguRules.SourceStrike.windBlade, .upperWind] {
            let attack = try wind(kind)
            for point in [nil, DuelWeaponPoint(x: .nan), DuelWeaponPoint(y: .infinity),
                          DuelWeaponPoint(x: Double.greatestFiniteMagnitude)] as [DuelWeaponPoint?] {
                var space = DuelPanguSpatialState()
                XCTAssertFalse(space.spawn(attack, owner: 0, fighter: owner, target: target,
                    targetPelvis: point, activeTicks: 1, frame: 10))
                XCTAssertTrue(space.volumes.isEmpty)
            }
        }
    }

    func testPivotAlignedSourceAndLegacyAttacksDoNotAcquirePelvisAlignment() throws {
        var owner = DuelGame.Fighter(hero: .liu, x: 2000, facing: 1); owner.y = 190
        var target = DuelGame.Fighter(hero: .ember, x: 6200, facing: -1); target.y = 410
        for kind in [DuelPanguRules.SourceStrike.upperFall, .heavenfallExplosion, nil] as [DuelPanguRules.SourceStrike?] {
            var attack = try wind(); attack.sourceStrike = kind
            var space = DuelPanguSpatialState()
            XCTAssertTrue(space.spawn(attack, owner: 0, fighter: owner, target: target,
                targetPelvis: .init(x: 6.53, y: 1.51), activeTicks: 1, frame: 10))
            XCTAssertEqual(space.volumes.first?.originX, target.x)
            XCTAssertEqual(space.volumes.first?.originY, target.y)
            attack.anchorAtOpponent = false
            XCTAssertTrue(space.spawn(attack, owner: 0, fighter: owner, target: target,
                targetPelvis: nil, activeTicks: 1, frame: 10))
            XCTAssertEqual(space.volumes.last?.originX, owner.x)
            XCTAssertEqual(space.volumes.last?.originY, owner.y)
        }
    }

    func testActualSourceSplitterFollowupReceivesEnemyPoseAnchorFromFight() throws {
        for facing in [1, -1] {
            let elevatedTarget = try withPelvis(DuelPanguFightFixture.catalog(rules: sourceRules()))
            let catalog = try F.changing(elevatedTarget) { profiles in
                // Keep the caster grounded so the actual source input gate
                // accepts Splitter. Only its enemy carries the test lift.
                for index in profiles.indices where profiles[index]["hero"] as? String == "liu" {
                    var clips = profiles[index]["clips"] as! [[String: Any]]
                    for c in clips.indices {
                        let count = 2 * (clips[c]["frames"] as! Int) - 1
                        var tracks = clips[c]["tracks"] as! [String: Any]
                        tracks["groundLift"] = Array(repeating: 0.0, count: count)
                        clips[c]["tracks"] = tracks
                    }
                    profiles[index]["clips"] = clips
                }
            }
            let ownX = facing > 0 ? 3500 : 6500
            let fighters = [DuelGame.Fighter(hero: .liu, x: ownX, facing: facing),
                            DuelGame.Fighter(hero: .ember, x: ownX + 800 * facing, facing: -facing)]
            var fight = try XCTUnwrap(DuelWeaponFight(fighters: fighters, mode: .practice,
                difficulty: .learning, catalog: catalog, seed: 41))
            fight.step(.init(vertical: 1, weaponCommand: .shadow), opponent: .neutral)
            XCTAssertEqual(fight.panguState(0)?.activeCast?.ability, .splitter)
            var release: DuelPanguPresentation.Volume?
            for _ in 0..<70 {
                for event in fight.panguPresentationEvents {
                    if case .attackReleased(let volume) = event.kind, volume.ability == nil,
                       volume.delivery == .ground { release = volume }
                }
                if release != nil { break }
                fight.step(.neutral, opponent: .neutral)
            }
            let volume = try XCTUnwrap(release), pelvis = try XCTUnwrap(fight.sourcePelvis(1))
            XCTAssertEqual(volume.bounds.minY, Int((pelvis.y * 1000).rounded()))
            let anchoredX = facing > 0 ? volume.bounds.minX : volume.bounds.maxX
            XCTAssertEqual(anchoredX, Int((pelvis.x * 1000).rounded()))
        }
    }

    func testActualSourceFightDoesNotAdvertiseOrDealAMissingPelvisWind() throws {
        var fight = try DuelPanguFightFixture.fight(rules: sourceRules())
        fight.step(.init(vertical: 1, weaponCommand: .shadow), opponent: .neutral)
        var windReleases = 0
        for _ in 0..<70 {
            for event in fight.panguPresentationEvents {
                if case .attackReleased(let volume) = event.kind, volume.ability == nil,
                   volume.delivery == .ground { windReleases += 1 }
            }
            fight.step(.neutral, opponent: .neutral)
        }
        XCTAssertGreaterThan(fight.landedHits[0], 0, "The real splitter must have activated its follow-ups")
        XCTAssertEqual(windReleases, 0)
        XCTAssertNil(fight.sourcePelvis(1))
    }
}
