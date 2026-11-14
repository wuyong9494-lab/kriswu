import XCTest
@testable import ShiftCore

/// Original clock/branch semantics with deliberately synthetic geometry,
/// hashes and normalized power. These fixtures are never shipping assets.
enum DuelSourceThrowFixture {
    static let frames = [51, 42, 83, 81, 82, 61]
    static let ends = [92, 74, 156, 152, 154, 112]
    static let roles = ["ordinaryThrowBack", "ordinaryThrownBack", "ordinaryThrowForward",
                        "ordinaryThrownForward", "ordinaryPanguEscape", "ordinaryPanguResisted"]

    static func rules(pelvis: Int = 0) -> DuelSourceThrowRules {
        let motions = Dictionary(uniqueKeysWithValues: DuelSourceThrowRules.Motion.allCases.enumerated().map { i, key in
            let last = 2 * (frames[i] - 1)
            return (key.rawValue, DuelSourceThrowMotion(role: roles[i],
                sourceSHA256: String(repeating: String(i + 1), count: 64), lastSampleTick: last,
                animationEndTick: ends[i], uninterruptEndTick: i == 0 ? 88 : i == 4 ? 146 : last + 1,
                rootMillimeters: Array(0...last), footLeftMillimeters: 20, pelvisMillimeters: pelvis))
        })
        return .init(motions: motions, normalizedUnarmedPower: 1000,
            millimetersPerSourceUnitNumerator: 92, millimetersPerSourceUnitDenominator: 10,
            maximumRangeSourceUnits: 102, forwardWallThresholdSourceUnits: 150,
            backWallThresholdSourceUnits: 100, throwDisabledAfterVictimEndTicks: 105)
    }

    static func wrapper(_ source: DuelSourceThrowRules = rules()) -> DuelWeaponThrowRules {
        .init(id: "synthetic-source-pair-tests", basis: .applicationAdaptation,
            sourceVersion: "synthetic test geometry; recovered branch and clock interpreter",
            sourceSHA256: nil, evidence: ["Not original source media, rig geometry, or equipment stats."],
            simultaneousContactPolicy: .sourceComplementaryLottery, attempts: [], source: source)
    }

    static func changed<T: Codable>(_ value: T, _ change: (inout [String: Any]) -> Void) throws -> T {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        change(&object)
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    static func state(_ variant: DuelSourceThrowRules.Variant = .back, facing: Int = 1,
                      targetRules: DuelSourceThrowRules? = nil) throws -> DuelSourceThrowState {
        try XCTUnwrap(.init(rules: rules(), variant: variant, initiator: 0, target: 1,
            facing: facing, initiatorX: 4000, counterUnarmedPower: 2000, targetRules: targetRules))
    }

    static func catalog(pangu: Bool = false, com: Double = 0, liuCOM: Double? = nil) throws -> DuelWeaponCatalog {
        let base = try pangu ? DuelPanguFightFixture.catalog(rules: .d19HeavenlyKing(level: 1,
            maximumHealth: 1000, weaponPower: 1000, unarmedPower: 1000, magicPower: 1000,
            rangedPower: 1000, spatialTemplate: DuelPanguTestFixture.rules(level: 1))) : DuelWeaponTestFixtures.catalog()
        let profiles = base.profiles.map { profile -> DuelWeaponProfile in
            var roles = profile.roles
            var clips = profile.clips.map { clip -> DuelWeaponClip in
                let t = clip.tracks
                return .init(name: clip.name, frames: clip.frames, sha256: clip.sha256, bundle: clip.bundle,
                    tracks: .init(samplesPerSourceFrame: 2, root: t.root, handL: t.handL, handR: t.handR,
                        footL: t.footL, footR: t.footR, weaponBaseL: t.weaponBaseL, weaponTipL: t.weaponTipL,
                        weaponBaseR: t.weaponBaseR, weaponTipR: t.weaponTipR, groundLift: t.groundLift,
                        collisionEdges: t.collisionEdges, hurtCapsules: t.hurtCapsules,
                        centerOfMass: Array(repeating: .init(x: profile.hero == .liu ? (liuCOM ?? com) : com, y: 1), count: 2 * clip.frames - 1)),
                    playbackTicks: clip.playbackTicks)
            }
            for (i, key) in DuelSourceThrowRules.Motion.allCases.enumerated() {
                let motion = rules().motion(key)!, count = 2 * frames[i] - 1
                let points = Array(repeating: DuelWeaponPoint(x: 0, y: 1), count: count)
                let name = "synthetic_source_" + key.rawValue
                roles[motion.role] = name
                clips.append(.init(name: name, frames: frames[i], sha256: motion.sourceSHA256,
                    bundle: "synthetic-source-throw-only",
                    tracks: .init(samplesPerSourceFrame: 2, root: points, handL: points, handR: points,
                        footL: points, footR: points,
                        weaponBaseL: profile.activeWeaponSides.contains("left") ? points : [],
                        weaponTipL: profile.activeWeaponSides.contains("left") ? points : [],
                        weaponBaseR: profile.activeWeaponSides.contains("right") ? points : [],
                        weaponTipR: profile.activeWeaponSides.contains("right") ? points : [],
                        groundLift: Array(repeating: 0, count: count), centerOfMass: points)))
            }
            return .init(id: profile.id, hero: profile.hero, faction: profile.faction,
                resourceName: profile.resourceName, bytes: profile.bytes, sha256: profile.sha256,
                bodyID: profile.bodyID, weaponID: profile.weaponID, activeWeaponSides: profile.activeWeaponSides,
                roles: roles, clips: clips, comboLinks: profile.comboLinks, combatRules: profile.combatRules,
                panguRules: profile.panguRules, ordinaryThrows: wrapper())
        }
        let result = DuelWeaponCatalog(schemaVersion: 1, previewFramesPerSecond: 30,
            sourceFramesPerSecond: nil, profiles: profiles)
        try result.validate(); return result
    }

    static func fight(pangu: Bool = false, distance: Int = 800, com: Double = 0, liuCOM: Double? = nil,
                      facing: Int = 1, seed: UInt64 = 42, firstX: Int = 4000) throws -> DuelWeaponFight {
        try XCTUnwrap(.init(fighters: [.init(hero: .ember, x: firstX, facing: facing),
            .init(hero: .liu, x: firstX + distance * facing, facing: -facing)],
            mode: .practice, difficulty: .learning, catalog: catalog(pangu: pangu, com: com, liuCOM: liuCOM), seed: seed))
    }
    static func advance(_ fight: inout DuelWeaponFight, _ count: Int) {
        for _ in 0..<count { fight.step(.neutral, opponent: .neutral) }
    }
}

final class DuelSourceThrowTests: XCTestCase {
    typealias F = DuelSourceThrowFixture

    func testSourceRulesRoundTripAndSixMotionsRemainDistinct() throws {
        let rules = F.wrapper()
        try rules.validate()
        XCTAssertEqual(try JSONDecoder().decode(DuelWeaponThrowRules.self, from: JSONEncoder().encode(rules)), rules)
        XCTAssertEqual(rules.source?.motions.count, 6)
        XCTAssertNil(rules.rule(command: .weaponForward), "A source miss must not start a fabricated grab animation")
    }

    func testSourceRulesRejectLegacyAttemptsAndInvalidHashesOrFrameCounts() throws {
        let mixed = try F.changed(F.wrapper()) { $0["attempts"] = try! JSONSerialization.jsonObject(with: JSONEncoder().encode([DuelWeaponThrowTestFixture.rule()])) }
        XCTAssertThrowsError(try mixed.validate())
        for field in ["sourceSHA256", "rootMillimeters"] {
            let malformed = try F.changed(F.rules()) { object in
                var motions = object["motions"] as! [String: [String: Any]]
                if field == "sourceSHA256" { motions["backActive"]![field] = "invalid" }
                else { motions["backActive"]![field] = [0] }
                object["motions"] = motions
            }
            XCTAssertThrowsError(try malformed.validate())
        }
    }

    func testSourceRangeUsesInclusiveOriginalUnitsWithoutRoundingUp() {
        XCTAssertTrue(F.rules().inRange(distanceMillimeters: 938))
        XCTAssertFalse(F.rules().inRange(distanceMillimeters: 939))
        XCTAssertFalse(F.rules().inRange(distanceMillimeters: -1))
    }

    func testFractionalCOMRangeKeeps938Point4Boundary() {
        XCTAssertTrue(F.rules().inRange(distanceMillimeters: 938.4))
        XCTAssertFalse(F.rules().inRange(distanceMillimeters: 938.4001))
        XCTAssertFalse(F.rules().inRange(distanceMillimeters: Double.nan))
        XCTAssertFalse(F.rules().inRange(distanceMillimeters: Double.infinity))
    }

    func testFractionalWallThresholdsAreNotRoundedAcrossBranches() {
        let rules = F.rules()
        XCTAssertEqual(rules.variant(command: .weaponForward, targetToFrontWallMillimeters: 1380.0,
            initiatorToBackWallMillimeters: 2000.0, targetHasD19Rules: false), .back)
        XCTAssertEqual(rules.variant(command: .weaponForward, targetToFrontWallMillimeters: 1380.0001,
            initiatorToBackWallMillimeters: 2000.0, targetHasD19Rules: false), .forward)
        XCTAssertEqual(rules.variant(command: .weaponBack, targetToFrontWallMillimeters: 2000.0,
            initiatorToBackWallMillimeters: 920.0, targetHasD19Rules: false), .forward)
        XCTAssertEqual(rules.variant(command: .weaponBack, targetToFrontWallMillimeters: 2000.0,
            initiatorToBackWallMillimeters: 920.0001, targetHasD19Rules: false), .back)
    }

    func testWallBranchesKeepTheirInclusiveBoundaries() {
        let r = F.rules()
        XCTAssertEqual(r.variant(command: .weaponForward, targetToFrontWallMillimeters: 1380,
            initiatorToBackWallMillimeters: 2000, targetHasD19Rules: false), .back)
        XCTAssertEqual(r.variant(command: .weaponForward, targetToFrontWallMillimeters: 1381,
            initiatorToBackWallMillimeters: 2000, targetHasD19Rules: false), .forward)
        XCTAssertEqual(r.variant(command: .weaponBack, targetToFrontWallMillimeters: 2000,
            initiatorToBackWallMillimeters: 920, targetHasD19Rules: false), .forward)
        XCTAssertEqual(r.variant(command: .weaponBack, targetToFrontWallMillimeters: 2000,
            initiatorToBackWallMillimeters: 921, targetHasD19Rules: false), .back)
        XCTAssertNil(r.variant(command: .heavy, targetToFrontWallMillimeters: 2000,
            initiatorToBackWallMillimeters: 2000, targetHasD19Rules: false))
    }

    func testAllThreeDamageMarkersAndActualParticipants() throws {
        for (variant, at, owner, amount) in [(DuelSourceThrowRules.Variant.back, 54, 0, 100),
                                           (.forward, 92, 0, 100), (.panguEscape, 98, 1, 300)] {
            var state = try F.state(variant)
            for _ in 1..<at { XCTAssertNil(state.advance().damage) }
            let damage = try XCTUnwrap(state.advance().damage)
            XCTAssertEqual(damage.attacker, owner); XCTAssertEqual(damage.target, 1 - owner)
            XCTAssertEqual(damage.amount, amount)
            for _ in 0..<200 { XCTAssertNil(state.advance().damage) }
        }
    }

    func testEachParticipantEndsOnItsOwnSourceAnimationEnd() throws {
        var state = try F.state()
        for _ in 0..<73 { _ = state.advance() }
        let release = state.advance()
        XCTAssertEqual(release.released, [1]); XCTAssertEqual(release.disabledThrowOwner, 0)
        XCTAssertTrue(state.owns(0)); XCTAssertFalse(state.owns(1))
        for _ in 74..<91 { _ = state.advance() }
        XCTAssertEqual(state.advance().released, [0]); XCTAssertTrue(state.isFinished)
    }

    func testRealUninterruptBoundaryDoesNotStretchUntilAnimationEnd() throws {
        var state = try F.state()
        for _ in 0..<87 { _ = state.advance() }
        XCTAssertFalse(state.canInterrupt(0))
        _ = state.advance(); XCTAssertTrue(state.canInterrupt(0))
        XCTAssertTrue(state.release(0)); XCTAssertTrue(state.isFinished)
    }

    func testPairedAlignmentUsesTheOtherActorsOwnRigAndMirrorsTogether() throws {
        let state = try F.state(targetRules: F.rules(pelvis: 90))
        XCTAssertEqual(state.origins, [3980, 3630])
        let mirrored = try F.state(facing: -1, targetRules: F.rules(pelvis: 90))
        XCTAssertEqual(mirrored.origins, [4020, 4370])
        XCTAssertEqual(state.participantMotions[1].pelvisMillimeters, 90)
        XCTAssertEqual(state.nextSamples[0].xMillimeters, 3981)
        XCTAssertEqual(state.nextSamples[1].xMillimeters, 3629)
    }

    func testCancellationAndEarlyReleaseCannotDeliverFutureDamage() throws {
        var cancelled = try F.state(.panguEscape); cancelled.cancel()
        for _ in 0..<120 { XCTAssertNil(cancelled.advance().damage) }
        var released = try F.state(); XCTAssertTrue(released.release(1))
        for _ in 0..<100 { XCTAssertNil(released.advance().damage) }
    }

    func testSourceCatalogRejectsMissingCOMAndWrongPairedMotionIdentity() throws {
        let catalog = try F.catalog()
        for mutation in [0, 1] {
            let invalid = try F.changed(catalog) { value in
                var profiles = value["profiles"] as! [[String: Any]]
                var clips = profiles[1]["clips"] as! [[String: Any]]
                if mutation == 0 {
                    var tracks = clips[0]["tracks"] as! [String: Any]
                    tracks.removeValue(forKey: "centerOfMass"); clips[0]["tracks"] = tracks
                } else { clips[clips.count - 1]["sha256"] = String(repeating: "f", count: 64) }
                profiles[1]["clips"] = clips; value["profiles"] = profiles
            }
            XCTAssertThrowsError(try invalid.validate())
        }
    }

    func testCOMValidationAndReplayCoverValuesAndPresence() throws {
        let catalog = try F.catalog()
        let changed = try F.changed(catalog) { value in
            var profiles = value["profiles"] as! [[String: Any]]
            var clips = profiles[0]["clips"] as! [[String: Any]]
            var tracks = clips[0]["tracks"] as! [String: Any]
            var points = tracks["centerOfMass"] as! [[Double]]
            points[0][0] += 0.2; tracks["centerOfMass"] = points
            clips[0]["tracks"] = tracks; profiles[0]["clips"] = clips; value["profiles"] = profiles
        }
        try changed.validate()
        XCTAssertNotEqual(try DuelReplayStateEncoding.encodeCatalog(catalog), try DuelReplayStateEncoding.encodeCatalog(changed))
        let malformed = try F.changed(changed) { value in
            var profiles = value["profiles"] as! [[String: Any]]
            var clips = profiles[0]["clips"] as! [[String: Any]]
            var tracks = clips[0]["tracks"] as! [String: Any]
            tracks["centerOfMass"] = [[0.0, 0.0, 0.0]]
            clips[0]["tracks"] = tracks; profiles[0]["clips"] = clips; value["profiles"] = profiles
        }
        XCTAssertThrowsError(try malformed.validate())
    }

    func testStoredSourceStateInventoryAndCanonicalProgress() throws {
        var state = try F.state(.panguEscape)
        XCTAssertEqual(Set(Mirror(reflecting: state).children.compactMap(\.label)),
            Set(["rules", "variant", "initiator", "target", "facing", "origins", "counterUnarmedPower",
                 "participantMotions", "tick", "released", "damageApplied", "cancelled"]))
        var a = try DuelReplayStateWriter(kind: 4); try state.appendReplayState(to: &a)
        _ = state.advance()
        var b = try DuelReplayStateWriter(kind: 4); try state.appendReplayState(to: &b)
        XCTAssertNotEqual(a.data, b.data)
    }
}
