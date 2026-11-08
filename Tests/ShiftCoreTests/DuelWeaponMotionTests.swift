import XCTest
@testable import ShiftCore

/// Deliberately tiny, synthetic geometry. These fixtures verify the interpreter;
/// they are not source animations and cannot satisfy private-resource acceptance.
enum DuelWeaponTestFixtures {
    enum Stroke { case straight, emptyCorner }
    static let frames = 9

    static func catalog(stroke: Stroke = .straight, aerialKick: Bool = true) -> DuelWeaponCatalog {
        .init(schemaVersion: 1, previewFramesPerSecond: 30, sourceFramesPerSecond: nil,
              profiles: [profile(hero: .ember, stroke: stroke, aerialKick: aerialKick),
                         profile(hero: .liu, stroke: stroke, aerialKick: aerialKick)])
    }

    static func profile(hero: DuelGame.Hero, stroke: Stroke, aerialKick: Bool) -> DuelWeaponProfile {
        let katana = hero == .ember, prefix = katana ? "katana" : "hammers"
        let sides = katana ? ["right"] : ["left", "right"]
        func clip(_ name: String, attack: Bool = false, kick: Bool = false, jump: Bool = false) -> DuelWeaponClip {
            let count = 2 * frames - 1
            var bases: [DuelWeaponPoint] = [], tips: [DuelWeaponPoint] = []
            var rightFoot: [DuelWeaponPoint] = [], lifts: [Double] = []
            for index in 0..<count {
                let phase = Double(index) / Double(count - 1)
                if attack && stroke == .emptyCorner {
                    // Its AABB overlaps a nearby torso, but this high diagonal
                    // and both moving endpoints pass outside the actual torso.
                    bases.append(.init(x: 0.16 * phase, y: 0))
                    tips.append(.init(x: 0.5 + 0.16 * phase, y: 3.2))
                } else {
                    bases.append(.init(x: 0.2 + (attack ? 0.8 * phase : 0), y: 1))
                    tips.append(.init(x: 0.7 + (attack ? 0.8 * phase : 0), y: 1))
                }
                rightFoot.append(kick ? .init(x: 0.6 + 0.8 * phase, y: 1) : .init(x: 0.1))
                lifts.append(jump ? sin(.pi * phase) * 0.8 : 0)
            }
            let zero = Array(repeating: DuelWeaponPoint(), count: count)
            let tracks = DuelWeaponTracks(
                samplesPerSourceFrame: 2, root: zero, handL: zero, handR: zero,
                footL: zero, footR: rightFoot,
                weaponBaseL: sides.contains("left") ? bases : [],
                weaponTipL: sides.contains("left") ? tips : [],
                weaponBaseR: bases, weaponTipR: tips, groundLift: lifts)
            return .init(name: "\(prefix)_\(name)", frames: frames, sha256: String(repeating: "c", count: 64),
                         bundle: "synthetic-test-only", tracks: tracks)
        }
        var clips = [clip("idle"), clip("crouch"), clip("reaction"), clip("jump", jump: true),
                     clip("weapon", attack: true), clip("weapon2", attack: true), clip("heavy", attack: true),
                     clip("kick", kick: true)]
        var roles = ["idle": "\(prefix)_idle", "walkForward": "\(prefix)_idle", "walkBackward": "\(prefix)_idle",
                     "crouch": "\(prefix)_crouch", "guard": "\(prefix)_reaction", "hit": "\(prefix)_reaction",
                     "knockdown": "\(prefix)_reaction", "getUp": "\(prefix)_reaction", "jump": "\(prefix)_jump",
                     "weapon1": "\(prefix)_weapon", "weapon2": "\(prefix)_weapon2",
                     "heavy": "\(prefix)_heavy", "kick": "\(prefix)_kick", "shadow": "\(prefix)_heavy"]
        if aerialKick {
            clips.append(clip("kickJump", kick: true, jump: true))
            roles["kickJump"] = "\(prefix)_kickJump"
        }
        return .init(id: katana ? "sun_katana" : "liu_hammers", hero: hero,
                     faction: katana ? "Herald" : "Legion", resourceName: "Synthetic_\(prefix)",
                     bytes: katana ? 128 : 256, sha256: String(repeating: katana ? "a" : "b", count: 64),
                     bodyID: "body_\(prefix)", weaponID: "weapon_\(prefix)", activeWeaponSides: sides,
                     roles: roles, clips: clips, comboLinks: nil)
    }

    static func changing(_ catalog: DuelWeaponCatalog,
                         _ mutation: (inout [[String: Any]]) -> Void) throws -> DuelWeaponCatalog {
        let data = try JSONEncoder().encode(catalog)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var profiles = try XCTUnwrap(object["profiles"] as? [[String: Any]])
        mutation(&profiles)
        object["profiles"] = profiles
        return try JSONDecoder().decode(DuelWeaponCatalog.self, from: JSONSerialization.data(withJSONObject: object))
    }

    static func fight(catalog: DuelWeaponCatalog = DuelWeaponTestFixtures.catalog(), distance: Int = 800,
                      mode: DuelGame.Mode = .practice, opponentHealth: Int = 1000) throws -> DuelWeaponFight {
        let a = DuelGame.Fighter(hero: .ember, x: 3500, facing: 1)
        var b = DuelGame.Fighter(hero: .liu, x: 3500 + distance, facing: -1)
        b.health = opponentHealth
        return try XCTUnwrap(DuelWeaponFight(fighters: [a, b], mode: mode, difficulty: .learning,
                                            catalog: catalog, seed: 4))
    }
}

final class DuelWeaponMotionTests: XCTestCase {
    func testRoundTripCatalogBindsEachPersonToTheirOwnBodyWeaponAndClips() throws {
        let original = DuelWeaponTestFixtures.catalog()
        let catalog = try JSONDecoder().decode(DuelWeaponCatalog.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(catalog, original)
        XCTAssertNoThrow(try catalog.validate())
        let sun = try XCTUnwrap(catalog.profile(for: .ember)), liu = try XCTUnwrap(catalog.profile(for: .liu))
        XCTAssertEqual(sun.id, "sun_katana")
        XCTAssertEqual(liu.id, "liu_hammers")
        XCTAssertNotEqual(sun.bodyID, liu.bodyID)
        XCTAssertNotEqual(sun.weaponID, liu.weaponID)
        XCTAssertNotEqual(sun.clip(command: .weapon)?.name, liu.clip(command: .weapon)?.name)
        XCTAssertEqual(sun.activeWeaponSides, ["right"])
        XCTAssertEqual(Set(liu.activeWeaponSides), ["left", "right"])
        XCTAssertNil(catalog.profile(for: .gale))
        XCTAssertNil(catalog.sourceFramesPerSecond, "The preview clock is not verified source combat timing")
    }

    func testCatalogRejectsSharedEquipmentAndSwappedPersonBindings() throws {
        for key in ["bodyID", "weaponID", "sha256"] {
            let duplicate = try DuelWeaponTestFixtures.changing(DuelWeaponTestFixtures.catalog()) { profiles in
                    profiles[1][key] = profiles[0][key]
                }
            XCTAssertThrowsError(try duplicate.validate(), key)
        }
        let swapped = try DuelWeaponTestFixtures.changing(DuelWeaponTestFixtures.catalog()) { profiles in
            profiles[0]["hero"] = "liu"; profiles[1]["hero"] = "ember"
        }
        XCTAssertThrowsError(try swapped.validate())
    }

    func testOnlyEquippedWeaponSidesCanProvideCollisionTracks() throws {
        let catalog = DuelWeaponTestFixtures.catalog()
        for (profileIndex, key) in [(0, "weaponTipR"), (1, "weaponBaseL")] {
            let missing = try DuelWeaponTestFixtures.changing(catalog) { profiles in
                var clips = profiles[profileIndex]["clips"] as! [[String: Any]]
                var tracks = clips[0]["tracks"] as! [String: Any]
                tracks[key] = [] as [Any]
                clips[0]["tracks"] = tracks; profiles[profileIndex]["clips"] = clips
            }
            XCTAssertThrowsError(try missing.validate())
        }
        let phantom = try DuelWeaponTestFixtures.changing(catalog) { profiles in
            var clips = profiles[0]["clips"] as! [[String: Any]]
            var tracks = clips[0]["tracks"] as! [String: Any]
            tracks["weaponTipL"] = tracks["weaponTipR"]
            clips[0]["tracks"] = tracks; profiles[0]["clips"] = clips
        }
        XCTAssertThrowsError(try phantom.validate(), "An unequipped hand must not become a phantom blade")
    }

    func testValidationRejectsBadFrameCountsBeforeSamplingOrArithmetic() throws {
        for invalid in [Int.min, 1, 2001, Int.max] {
            let catalog = try DuelWeaponTestFixtures.changing(DuelWeaponTestFixtures.catalog()) { profiles in
                var clips = profiles[0]["clips"] as! [[String: Any]]
                clips[0]["frames"] = invalid
                profiles[0]["clips"] = clips
            }
            XCTAssertThrowsError(try catalog.validate())
        }
    }

    func testHalfFrameSamplesRetainTheirMidpointAndClampAtIntervalEdges() throws {
        let clip = try XCTUnwrap(DuelWeaponTestFixtures.catalog().profile(for: .ember)?.clip(command: .weapon))
        let curved = [DuelWeaponPoint(x: 0), DuelWeaponPoint(x: 5, y: 2), DuelWeaponPoint(x: 0)]
        XCTAssertEqual(clip.tracks.sample(curved, phase: 0.5), curved[1],
                       "The saved half-frame point must not be replaced by interpolation of the two endpoints")
        XCTAssertEqual(clip.tracks.sample(curved, phase: 0.25), .init(x: 2.5, y: 1))
        XCTAssertEqual(clip.tracks.sample(curved, phase: -1), curved[0])
        XCTAssertEqual(clip.tracks.sample(curved, phase: 2), curved[2])
        XCTAssertEqual(clip.tracks.sample([], phase: 0.5), .init())
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(clip.tracks.sample(curved, phase: invalid), curved[0])
            XCTAssertEqual(clip.tracks.lift(phase: invalid), 0)
        }
        XCTAssertEqual(clip.ticks, 16)
        XCTAssertEqual(clip.phase(at: 8), 0.5)
        XCTAssertEqual(clip.phase(at: Int.min), 0)
        XCTAssertEqual(clip.phase(at: Int.max), 1)
    }

    func testPointDecoderRejectsIncorrectDimensionality() {
        for payload in ["[]", "[1,2]", "[1,2,3,4]", "[1,\"NaN\",3]"] {
            XCTAssertThrowsError(try JSONDecoder().decode(DuelWeaponPoint.self, from: Data(payload.utf8)))
        }
    }
}
