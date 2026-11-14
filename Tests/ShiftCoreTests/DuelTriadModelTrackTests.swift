import XCTest
@testable import ShiftCore

/// Synthetic geometry in the authenticated source-model schema. The fixture
/// does not embed original motion samples, meshes or source script contents.
final class DuelTriadModelTrackTests: XCTestCase {
    private typealias Track = DuelSummonMotionTrack

    private func track(_ key: String, deltaX: Double = 0, y: Double = 1,
                       z: Double = 0, tipY: Double? = nil) -> Track {
        let roots = key == "roots", frames = roots ? 31 : 22, count = 2 * frames - 1
        let id = roots ? "Common_Model_40_bottom_top" : "Common_Model_40_Attacking_Edge_Big"
        let clip = roots ? "h17_root_spike_model" : "h17_wave_model"
        let digest = String(repeating: roots ? "a" : "b", count: 64)
        let root: [DuelWeaponPoint] = (0..<count).map { .init(x: 20 + Double($0) * deltaX, y: y, z: z) }
        let bases = Array(repeating: DuelWeaponPoint(x: 0, y: y, z: z), count: count)
        let tips = Array(repeating: DuelWeaponPoint(x: 0, y: tipY ?? y, z: z), count: count)
        let capsule = DuelWeaponHurtCapsule(id: id, radiusMillimeters: roots ? 300 : 1600,
            defense: .body, base: bases, tip: tips)
        return Track(role: "triadModel_" + key, clip: clip,
            frames: frames, sourceSHA256: digest,
            sourceBundle: "synthetic-independent-model-only",
            root: root,
            groundLift: .init(repeating: 0, count: count),
            boneConfigurationSHA256: String(repeating: "c", count: 64), collisionEdges: [],
            hurtCapsules: [capsule],
            attackParts: ["primary": [id]])
    }

    private func rules(roots: Track? = nil, wave: Track? = nil) throws -> DuelTriadRules {
        var value = try DuelTriadTestFixture.runtimeRules()
        value.runtime?.modelTracks = ["roots": roots ?? track("roots"), "mistWave": wave ?? track("mistWave")]
        // Deliberately different from the source geometry. These fallback
        // dimensions cannot influence a bound model's travel or contact.
        for i in value.abilities.indices where [.branches, .mistOnslaught].contains(value.abilities[i].ability) {
            value.abilities[i].attack?.rangeMillimeters = 100
            value.abilities[i].attack?.speedMillimetersPerTick = 1
            value.abilities[i].attack?.radiusMillimeters = 1
        }
        try value.validate(); return value
    }

    private func profile(_ rules: DuelTriadRules) throws -> DuelWeaponProfile {
        try XCTUnwrap(DuelTriadFightFixture.catalog(rules: rules).profile(for: .ember))
    }

    private func attack(_ ability: DuelTriadRules.Ability, rules: DuelTriadRules) throws -> DuelTriadState.Attack {
        var state = try XCTUnwrap(DuelTriadState(rules: rules, seed: 17))
        state.beginRound(roundID: 0)
        var effects = state.start(ability)
        for _ in 0..<200 {
            if let value = effects.compactMap({ effect -> DuelTriadState.Attack? in
                if case .attack(let value) = effect { return value }; return nil
            }).first { return value }
            effects = state.step()
        }
        throw NSError(domain: "SyntheticTriadModelFixture", code: 1)
    }

    private func fighters(direction: Int = 1) -> [DuelGame.Fighter] {
        [.init(hero: .ember, x: direction == 1 ? 3000 : 12_000, facing: direction),
         .init(hero: .liu, x: direction == 1 ? 12_000 : 3000, facing: -direction)]
    }

    private func contacts(_ space: inout DuelTriadSpatialState, profile: DuelWeaponProfile,
                          fighters: [DuelGame.Fighter], target: DuelWeaponCapsule? = nil,
                          previousTarget: DuelWeaponCapsule? = nil) -> [DuelTriadSpatialState.Hit] {
        let before = (previousTarget ?? target).map { [(id: "synthetic_target", capsule: $0)] }
        let after = target.map { [(id: "synthetic_target", capsule: $0)] }
        return space.contacts(fighters: fighters, profiles: [profile, profile],
            hurts: fighters.map { .init(minX: $0.x - 100, maxX: $0.x + 100, minY: 0, maxY: 1800) },
            previousX: fighters.map(\.x), previousHurtY: [0, 0],
            hurtBefore: [nil, before], hurtAfter: [nil, after])
    }

    private func point(_ x: Double, _ y: Double = 1, _ z: Double = 0) -> DuelWeaponCapsule {
        .init(a: .init(x: x, y: y, z: z), b: .init(x: x, y: y, z: z), radius: 0.05)
    }

    private func changing(_ value: Track, _ edit: (inout [String: Any]) -> Void) throws -> Track {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        edit(&object)
        return try JSONDecoder().decode(Track.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testOptionalSourceModelsRoundTripWithoutRequiringThemInLegacyProfiles() throws {
        let legacy = try DuelTriadTestFixture.runtimeRules()
        let legacyData = try JSONEncoder().encode(legacy)
        let decodedLegacy = try JSONDecoder().decode(DuelTriadRules.self, from: legacyData)
        XCTAssertNil(decodedLegacy.runtime?.modelTracks); try decodedLegacy.validate()
        let bound = try rules(), decoded = try JSONDecoder().decode(DuelTriadRules.self, from: JSONEncoder().encode(bound))
        XCTAssertEqual(decoded, bound); try decoded.validate()
        XCTAssertEqual(decoded.runtime?.modelTracks?["roots"]?.root.count, 61)
        XCTAssertEqual(decoded.runtime?.modelTracks?["mistWave"]?.root.count, 43)
    }

    func testSourceModelBindingRejectsMissingUnknownOrMisboundGeometry() throws {
        let original = try rules()
        for keys in [[], ["roots"], ["roots", "mistWave", "unknown"]] {
            var value = original
            value.runtime?.modelTracks = Dictionary(uniqueKeysWithValues: keys.map { ($0, track($0)) })
            XCTAssertThrowsError(try value.validate())
        }
        let invalid: [(inout [String: Any]) -> Void] = [
            { $0["role"] = "triadModel_mistWave" }, { $0["clip"] = "unrelated_model" },
            { $0["sourceSHA256"] = "unknown" }, { $0["groundLift"] = Array(repeating: 0.1, count: 61) },
            { $0["attackParts"] = ["primary": ["unbound_capsule"]] },
            { object in
                var capsules = object["hurtCapsules"] as! [[String: Any]]
                capsules[0]["radiusMillimeters"] = 276; object["hurtCapsules"] = capsules
            },
            { object in
                var capsules = object["hurtCapsules"] as! [[String: Any]]
                capsules[0]["base"] = [[0, 1, 0]]; object["hurtCapsules"] = capsules
            }
        ]
        for edit in invalid {
            var value = original
            value.runtime?.modelTracks?["roots"] = try changing(track("roots"), edit)
            XCTAssertThrowsError(try value.validate())
        }
    }

    func testCanonicalIdentityIncludesAllModelSamplesAndSortsTheirKeys() throws {
        let original = try rules()
        func encoded(_ value: DuelTriadRules) throws -> Data {
            try DuelReplayStateEncoding.encodeCatalog(DuelTriadFightFixture.catalog(rules: value))
        }
        var reordered = original
        reordered.runtime?.modelTracks = ["mistWave": track("mistWave"), "roots": track("roots")]
        XCTAssertEqual(try encoded(original), try encoded(reordered))
        for field in ["root", "hurtCapsules"] {
            var changed = original
            changed.runtime?.modelTracks?["roots"] = try changing(track("roots")) { object in
                if field == "root" {
                    var points = object["root"] as! [[Double]]; points[1][0] += 0.001; object["root"] = points
                } else {
                    var capsules = object["hurtCapsules"] as! [[String: Any]]
                    var points = capsules[0]["tip"] as! [[Double]]; points[1][2] += 0.001
                    capsules[0]["tip"] = points; object["hurtCapsules"] = capsules
                }
            }
            try changed.validate(); XCTAssertNotEqual(try encoded(original), try encoded(changed))
        }
        var absent = original; absent.runtime?.modelTracks = nil
        XCTAssertNotEqual(try encoded(original), try encoded(absent))
    }

    func testRootBirthUsesSourceFacingOffsetAndIgnoresLegacyRangeAndJumpHeight() throws {
        let rules = try rules(), profile = try profile(rules), attack = try attack(.branches, rules: rules)
        XCTAssertEqual(attack.activationDelayTicks, 22); XCTAssertEqual(attack.activeTicks, 61)
        for direction in [1, -1] {
            var fighters = fighters(direction: direction); fighters[0].y = 900; fighters[1].y = 700
            var space = DuelTriadSpatialState(); space.tick = 70
            let volume = try XCTUnwrap(space.spawn(attack, owner: 0, fighters: fighters, profile: profile))
            XCTAssertEqual(volume.originX, fighters[1].x - direction * 500)
            XCTAssertEqual(volume.originY, 0); XCTAssertEqual(volume.direction, direction)
            XCTAssertEqual(volume.expiresAt, 131); XCTAssertNotNil(volume.authoredBounds)
            fighters[0].x += 2000; fighters[1].x += 2000; space.tick += 10
            XCTAssertTrue(contacts(&space, profile: profile, fighters: fighters, target: point(50)).isEmpty)
            XCTAssertEqual(space.volumes.first?.originX, volume.originX)
            XCTAssertEqual(space.volumes.first?.x, volume.originX, "Root does not follow either moving fighter")
        }
        var adapted = rules; adapted.runtime?.modelTracks = nil
        var oldSpace = DuelTriadSpatialState()
        XCTAssertNil(oldSpace.spawn(attack, owner: 0, fighters: fighters(), profile: try self.profile(adapted)))
    }

    func testWaveMovesByUnscaledSourceRootOnceAndPreservesModelLocalHeightAndDepth() throws {
        let rules = try rules(wave: track("mistWave", deltaX: 0.25, y: 1, z: -0.3)), profile = try profile(rules)
        let attack = try attack(.mistOnslaught, rules: rules)
        XCTAssertEqual(attack.activationDelayTicks, 4); XCTAssertEqual(attack.activeTicks, 43)
        for direction in [1, -1] {
            var fighters = fighters(direction: direction); fighters[0].y = 800
            var space = DuelTriadSpatialState()
            let born = try XCTUnwrap(space.spawn(attack, owner: 0, fighters: fighters, profile: profile))
            XCTAssertEqual(born.originX, fighters[0].x); XCTAssertEqual(born.originY, 0)
            space.tick = 4
            XCTAssertTrue(contacts(&space, profile: profile, fighters: fighters, target: point(50)).isEmpty)
            let volume = try XCTUnwrap(space.volumes.first)
            XCTAssertEqual(volume.x, born.originX + direction * 1000, "Neither .92 scale nor the first root X is added")
            XCTAssertEqual(volume.travelled, 0, "Legacy speed/range bookkeeping does not consume the original model")
            XCTAssertEqual(Double(volume.bounds.minY) / 1000, -0.6, accuracy: 0.0011)
            XCTAssertEqual(Double(volume.bounds.maxY) / 1000, 2.6, accuracy: 0.0011)
            let hitX = Double(volume.x) / 1000
            XCTAssertEqual(contacts(&space, profile: profile, fighters: fighters,
                target: point(hitX, 1, -0.3 * Double(direction))).count, 1)
        }
    }

    func testModelCapsulesRejectOutOfPlaneTargetsInsideTheProjectedBounds() throws {
        let rules = try rules(roots: track("roots", y: 1, z: 2)), profile = try profile(rules)
        let attack = try attack(.branches, rules: rules), fighters = fighters()
        for z in [0.0, 2.0] {
            var space = DuelTriadSpatialState()
            let volume = try XCTUnwrap(space.spawn(attack, owner: 0, fighters: fighters, profile: profile)); space.tick = 22
            let hits = contacts(&space, profile: profile, fighters: fighters,
                target: point(Double(volume.originX) / 1000, 1, z))
            XCTAssertEqual(hits.count, z == 2 ? 1 : 0)
            if let hit = hits.first { XCTAssertEqual(hit.point.z, 2, accuracy: 1e-6) }
        }
    }

    func testFirstActiveStepDoesNotSweepInactiveSourceSamplesIntoAHit() throws {
        let moving = try changing(track("mistWave")) { object in
            var points = object["root"] as! [[Double]]
            for index in 4..<points.count { points[index][0] += 5 }
            object["root"] = points
        }
        let rules = try rules(wave: moving), profile = try profile(rules), attack = try attack(.mistOnslaught, rules: rules)
        let fighters = fighters(); var space = DuelTriadSpatialState()
        space.spawn(attack, owner: 0, fighters: fighters, profile: profile)
        space.tick = 3
        XCTAssertTrue(contacts(&space, profile: profile, fighters: fighters, target: point(5.5)).isEmpty)
        space.tick = 4
        XCTAssertTrue(contacts(&space, profile: profile, fighters: fighters, target: point(5.5)).isEmpty,
            "A target touched only by the inactive 3→4 sweep must not receive a retroactive hit")
        XCTAssertEqual(space.volumes.count, 1)
    }

    func testActiveModelSweepsCatchFastTravelAndContactBudgetIsNotReplayed() throws {
        let moving = try changing(track("mistWave")) { object in
            var points = object["root"] as! [[Double]]
            for index in 5..<points.count { points[index][0] += 5 }
            object["root"] = points
        }
        let rules = try rules(wave: moving), profile = try profile(rules), attack = try attack(.mistOnslaught, rules: rules)
        let fighters = fighters(); var space = DuelTriadSpatialState()
        space.spawn(attack, owner: 0, fighters: fighters, profile: profile); space.tick = 5
        XCTAssertEqual(contacts(&space, profile: profile, fighters: fighters, target: point(5.5)).count, 1)
        XCTAssertTrue(space.volumes.isEmpty)
        XCTAssertTrue(contacts(&space, profile: profile, fighters: fighters, target: point(5.5)).isEmpty)
    }

    func testRootsAndWaveIncludeTheirLastSourceSampleThenExpire() throws {
        let rules = try rules(), profile = try profile(rules), fighters = fighters()
        for ability in [DuelTriadRules.Ability.branches, .mistOnslaught] {
            let attack = try attack(ability, rules: rules)
            for age in [attack.activeTicks - 1, attack.activeTicks] {
                var space = DuelTriadSpatialState(); space.tick = 100
                let volume = try XCTUnwrap(space.spawn(attack, owner: 0, fighters: fighters, profile: profile))
                space.tick = 100 + age
                let hits = contacts(&space, profile: profile, fighters: fighters, target: point(Double(volume.originX) / 1000))
                XCTAssertEqual(hits.count, age < attack.activeTicks ? 1 : 0)
                XCTAssertTrue(space.volumes.isEmpty)
            }
        }
    }

    func testSourceModelCanHitLegacyTargetThroughTheExplicitBodyAdapter() throws {
        let rules = try rules(), profile = try profile(rules), attack = try attack(.mistOnslaught, rules: rules)
        var fighters = fighters(); fighters[1].x = fighters[0].x + 1000
        var space = DuelTriadSpatialState()
        space.spawn(attack, owner: 0, fighters: fighters, profile: profile); space.tick = 4
        XCTAssertEqual(contacts(&space, profile: profile, fighters: fighters).count, 1)
    }
}
