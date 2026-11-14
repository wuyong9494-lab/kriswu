import Foundation
import XCTest
@testable import ShiftCore

/// Synthetic bindings only. These exercise the private release contract and
/// are not recovered Pangu assets, retail measurements, or an accepted release.
final class DuelFighterAssetReleaseTests: XCTestCase {
    private typealias Release = DuelFighterAssetRelease
    private typealias Object = [String: Any]

    private func catalog(sourceFPS: Double? = nil) throws -> DuelWeaponCatalog {
        let fixture = try DuelPanguFightFixture.catalog(rules: DuelPanguTestFixture.rules())
        return .init(schemaVersion: fixture.schemaVersion,
                     previewFramesPerSecond: fixture.previewFramesPerSecond,
                     sourceFramesPerSecond: sourceFPS, profiles: fixture.profiles)
    }

    private func document(for catalog: DuelWeaponCatalog) -> Object {
        func file(_ name: String, digest: String) -> Object {
            ["name": name, "bytes": 1, "sha256": String(repeating: digest, count: 64)]
        }
        let profiles: [Object] = catalog.profiles.map { profile in
            let motions: [Object] = profile.clips.map { clip in
                var motion: Object = ["clip": clip.name, "sourceSHA256": clip.sha256,
                    "sourceBundle": clip.bundle, "frames": clip.frames,
                    "exportFramesPerSecond": catalog.previewFramesPerSecond]
                if let fps = catalog.sourceFramesPerSecond {
                    motion["sourceFramesPerSecond"] = fps
                } else {
                    motion["sourceFramesPerSecond"] = NSNull()
                }
                return motion
            }
            return ["id": profile.id, "characterSHA256": profile.sha256,
                    "bodyID": profile.bodyID, "weaponID": profile.weaponID,
                    "sourceVersion": "synthetic-release-tests-only",
                    "evidence": ["Artificial fixture; no original-game source or fidelity claim."],
                    "motions": motions,
                    "skinRoots": [["skin": 0, "declared": 1, "corrected": 0]],
                    "restorePersonalBindSpace": true,
                    "materials": [["name": "SyntheticMaterial", "doubleSided": false,
                        "cull": "back", "minification": "linear", "magnification": "linear",
                        "mip": "none", "wrapS": "clamp", "wrapT": "repeat",
                        "maxAnisotropy": 1]]]
        }
        return ["schemaVersion": 1, "id": "synthetic-pangu-release-tests-only",
                "catalog": file("SF3_DistinctFighters.json", digest: "d"),
                "sourceTrails": file("Synthetic_Pangu_Trails.json", digest: "e"),
                "panguAudio": file("Synthetic_Pangu_Audio.json", digest: "f"),
                "profiles": profiles]
    }

    private func decode(_ object: Object) throws -> Release {
        try JSONDecoder().decode(Release.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func changingProfile(_ original: Object, id: String = "liu_pangu",
                                 _ mutation: (inout Object) throws -> Void) throws -> Object {
        var result = original
        var profiles = try XCTUnwrap(result["profiles"] as? [Object])
        let index = try XCTUnwrap(profiles.firstIndex { $0["id"] as? String == id })
        try mutation(&profiles[index])
        result["profiles"] = profiles
        return result
    }

    private func changingMotion(_ original: Object,
                                _ mutation: (inout Object) throws -> Void) throws -> Object {
        try changingProfile(original) { profile in
            var motions = try XCTUnwrap(profile["motions"] as? [Object])
            var first = try XCTUnwrap(motions.first)
            try mutation(&first)
            motions[0] = first
            profile["motions"] = motions
        }
    }

    private func assertRejected(_ object: Object, catalog: DuelWeaponCatalog,
                                as expected: Release.Failure, _ message: String = "",
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let release = try decode(object)
        XCTAssertThrowsError(try release.validate(catalog: catalog), message, file: file, line: line) {
            XCTAssertEqual($0 as? Release.Failure, expected, message, file: file, line: line)
        }
    }

    func testSyntheticReleaseRoundTripPreservesExactCatalogBindings() throws {
        let target = try catalog()
        let release = try decode(document(for: target))
        XCTAssertNoThrow(try release.validate(catalog: target))
        let roundTrip = try JSONDecoder().decode(Release.self, from: JSONEncoder().encode(release))
        XCTAssertEqual(roundTrip, release)
        let pangu = try XCTUnwrap(roundTrip.profile(id: "liu_pangu"))
        let equipped = try XCTUnwrap(target.profile(for: .liu))
        XCTAssertEqual(pangu.characterSHA256, equipped.sha256)
        XCTAssertEqual(pangu.bodyID, "synthetic_pangu_body")
        XCTAssertEqual(pangu.weaponID, "synthetic_pangu_long_axe")
        XCTAssertEqual(Set(pangu.motions.map(\.clip)), Set(equipped.clips.map(\.name)))
        XCTAssertEqual(pangu.motions.count, equipped.clips.count)
        XCTAssertNil(roundTrip.profile(id: "liu_hammers"))
    }

    func testCharacterHashCannotBelongToTheOtherFighterOrBeMalformed() throws {
        let target = try catalog(), original = document(for: target)
        let otherHash = try XCTUnwrap(target.profile(for: .ember)?.sha256)
        for hash in [otherHash, String(repeating: "d", count: 64),
                     String(repeating: "B", count: 64), String(repeating: "b", count: 63), ""] {
            let changed = try changingProfile(original) { $0["characterSHA256"] = hash }
            try assertRejected(changed, catalog: target, as: .profile, hash)
        }
    }

    func testBodyAndWeaponIDsCannotBeSwappedOrRebound() throws {
        let target = try catalog(), original = document(for: target)
        let other = try XCTUnwrap(target.profile(for: .ember))
        for (key, values) in [("bodyID", [other.bodyID, "unreviewed_body", ""]),
                              ("weaponID", [other.weaponID, "unreviewed_weapon", ""])] {
            for value in values {
                let changed = try changingProfile(original) { $0[key] = value }
                try assertRejected(changed, catalog: target, as: .profile, key + ":" + value)
            }
        }
    }

    func testMissingDuplicateAndUnknownProfileBindingsAreRejected() throws {
        let target = try catalog(), original = document(for: target)
        let profiles = try XCTUnwrap(original["profiles"] as? [Object])
        var unknown = profiles
        unknown[1]["id"] = "unreviewed_fighter"
        for changedProfiles in [Array(profiles.dropLast()), [profiles[0], profiles[0]],
                                profiles + [profiles[0]], unknown] {
            var changed = original
            changed["profiles"] = changedProfiles
            try assertRejected(changed, catalog: target, as: .profile)
        }
    }

    func testProfileSourceEvidenceCannotBeMissingOrUnbounded() throws {
        let target = try catalog(), original = document(for: target)
        for version in ["", String(repeating: "v", count: 257)] {
            let changed = try changingProfile(original) { $0["sourceVersion"] = version }
            try assertRejected(changed, catalog: target, as: .profile)
        }
        for evidence in [[], [""], [String(repeating: "e", count: 1025)],
                         Array(repeating: "synthetic", count: 33)] as [[String]] {
            let changed = try changingProfile(original) { $0["evidence"] = evidence }
            try assertRejected(changed, catalog: target, as: .profile)
        }
    }

    func testMissingDuplicateAndUnknownClipBindingsAreRejected() throws {
        let target = try catalog(), original = document(for: target)
        for mutation in 0..<4 {
            let changed = try changingProfile(original) { profile in
                var motions = try XCTUnwrap(profile["motions"] as? [Object])
                switch mutation {
                case 0: motions.removeLast()
                case 1: motions[0] = motions[1] // Same count, but one missing and one duplicated.
                case 2: motions.append(motions[0])
                default: motions[0]["clip"] = "unreviewed_pangu_clip"
                }
                profile["motions"] = motions
            }
            try assertRejected(changed, catalog: target, as: .motion, "case \(mutation)")
        }
    }

    func testMotionSourceDigestMustExactlyMatchItsCatalogClip() throws {
        let target = try catalog(), original = document(for: target)
        for hash in [String(repeating: "d", count: 64), String(repeating: "C", count: 64),
                     String(repeating: "c", count: 63), ""] {
            let changed = try changingMotion(original) { $0["sourceSHA256"] = hash }
            try assertRejected(changed, catalog: target, as: .motion)
        }
    }

    func testMotionBundleMustExactlyMatchItsCatalogClip() throws {
        let target = try catalog(), original = document(for: target)
        for bundle in ["unreviewed-bundle", "", String(repeating: "b", count: 513)] {
            let changed = try changingMotion(original) { $0["sourceBundle"] = bundle }
            try assertRejected(changed, catalog: target, as: .motion)
        }
    }

    func testMotionFrameCountCannotDisagreeWithTheBoundClip() throws {
        let target = try catalog(), original = document(for: target)
        let frames = try XCTUnwrap(target.profile(for: .liu)?.clips.first?.frames)
        for invalid in [0, -1, frames - 1, frames + 1, Int.max] {
            let changed = try changingMotion(original) { $0["frames"] = invalid }
            try assertRejected(changed, catalog: target, as: .motion, "\(invalid)")
        }
    }

    func testExportClockMustMatchTheCatalogPreviewClock() throws {
        let target = try catalog(), original = document(for: target)
        for invalid in [0, 24, 29, 31, 60, Int.max] {
            let changed = try changingMotion(original) { $0["exportFramesPerSecond"] = invalid }
            try assertRejected(changed, catalog: target, as: .motion, "\(invalid)")
        }
    }

    func testNullAndOmittedSourceClocksStayUnknownAfterRoundTrip() throws {
        let target = try catalog(), original = document(for: target)
        XCTAssertNil(target.sourceFramesPerSecond)
        for omitField in [false, true] {
            let changed = try changingProfile(original) { profile in
                var motions = try XCTUnwrap(profile["motions"] as? [Object])
                for index in motions.indices {
                    if omitField { motions[index].removeValue(forKey: "sourceFramesPerSecond") }
                    else { motions[index]["sourceFramesPerSecond"] = NSNull() }
                }
                profile["motions"] = motions
            }
            let release = try decode(changed)
            let roundTrip = try JSONDecoder().decode(Release.self, from: JSONEncoder().encode(release))
            XCTAssertNoThrow(try roundTrip.validate(catalog: target))
            for profile in roundTrip.profiles {
                for motion in profile.motions {
                    XCTAssertEqual(motion.exportFramesPerSecond, 30)
                    XCTAssertNil(motion.sourceFramesPerSecond,
                                 "The export clock cannot manufacture recovered source timing")
                }
            }
        }
    }

    func testExplicitPerClipSourceClockDoesNotFillOtherUnknownClocks() throws {
        let target = try catalog(), original = document(for: target)
        let changed = try changingMotion(original) { $0["sourceFramesPerSecond"] = 24.0 }
        let release = try decode(changed)
        XCTAssertNoThrow(try release.validate(catalog: target))
        let motions = try XCTUnwrap(release.profile(id: "liu_pangu")?.motions)
        XCTAssertEqual(motions.first?.sourceFramesPerSecond, 24)
        XCTAssertTrue(motions.dropFirst().allSatisfy { $0.sourceFramesPerSecond == nil })
        XCTAssertTrue(release.profile(id: "sun_katana")?.motions.allSatisfy {
            $0.sourceFramesPerSecond == nil
        } == true)
        XCTAssertNil(target.sourceFramesPerSecond,
                     "A per-clip declaration does not establish a uniform catalog source clock")
    }

    func testDeclaredUniformSourceClockRequiresEveryClipToMatch() throws {
        let target = try catalog(sourceFPS: 24), original = document(for: target)
        XCTAssertNoThrow(try decode(original).validate(catalog: target))
        for invalid in [30.0, 23.976, NSNull()] as [Any] {
            let changed = try changingMotion(original) { $0["sourceFramesPerSecond"] = invalid }
            try assertRejected(changed, catalog: target, as: .motion)
        }
        let omitted = try changingMotion(original) { $0.removeValue(forKey: "sourceFramesPerSecond") }
        try assertRejected(omitted, catalog: target, as: .motion)
    }

    func testPerClipSourceClockRejectsOutOfRangeValues() throws {
        let target = try catalog(), original = document(for: target)
        for invalid in [-1.0, 0, 0.5, 240.01, 241, Double.greatestFiniteMagnitude] {
            let changed = try changingMotion(original) { $0["sourceFramesPerSecond"] = invalid }
            try assertRejected(changed, catalog: target, as: .motion)
        }
    }

    func testReleaseFilePathsAndReservedLegacyNamesAreRejected() throws {
        let target = try catalog(), original = document(for: target)
        let paths = ["", "../other.json", "/tmp/other.json", "folder/other.json", "folder\\other.json",
                     ".private.json", "a..b.json", "https://example.test/data.json", "data.json\n",
                     "SF3_盘古.json", String(repeating: "a", count: 129) + ".json"]
        for key in ["catalog", "sourceTrails", "panguAudio"] {
            for path in paths {
                var changed = original
                var file = try XCTUnwrap(changed[key] as? Object)
                file["name"] = path; changed[key] = file
                try assertRejected(changed, catalog: target, as: .file, key + ":" + path)
            }
        }
        for (key, name) in [("catalog", "Synthetic_Different_Catalog.json"),
                            ("sourceTrails", "SF3_SourceTrails.json"),
                            ("panguAudio", "SF3FX_manifest.json"),
                            ("sourceTrails", "Synthetic_Trails.bin"),
                            ("panguAudio", "Synthetic_Audio.wav")] {
            var changed = original
            var file = try XCTUnwrap(changed[key] as? Object)
            file["name"] = name; changed[key] = file
            try assertRejected(changed, catalog: target, as: .file, name)
        }
    }

    func testReleaseFilesCannotAliasEachOtherOrTheReleaseManifest() throws {
        let target = try catalog(), original = document(for: target)
        for (key, name) in [("sourceTrails", "SF3_DistinctFighters.json"),
                            ("panguAudio", "SF3_DistinctFighters.json"),
                            ("sourceTrails", "Synthetic_Pangu_Audio.json"),
                            ("panguAudio", "Synthetic_Pangu_Trails.json"),
                            ("sourceTrails", Release.fileName), ("panguAudio", Release.fileName)] {
            var changed = original
            var file = try XCTUnwrap(changed[key] as? Object)
            file["name"] = name; changed[key] = file
            try assertRejected(changed, catalog: target, as: .file, key + ":" + name)
        }
    }

    func testReleaseFileSizesMustBePositiveAndBoundedByFileRole() throws {
        let target = try catalog(), original = document(for: target)
        for (key, maximum) in [("catalog", 32_000_000), ("sourceTrails", 2_000_000),
                               ("panguAudio", 256_000)] {
            for invalid in [-1, 0, maximum + 1, Int.max] {
                var changed = original
                var file = try XCTUnwrap(changed[key] as? Object)
                file["bytes"] = invalid; changed[key] = file
                try assertRejected(changed, catalog: target, as: .file, "\(key):\(invalid)")
            }
        }
    }

    func testReleaseFileDigestsRequireCompleteLowercaseSHA256() throws {
        let target = try catalog(), original = document(for: target)
        for key in ["catalog", "sourceTrails", "panguAudio"] {
            for invalid in ["", String(repeating: "a", count: 63), String(repeating: "a", count: 65),
                            String(repeating: "A", count: 64), String(repeating: "g", count: 64),
                            String(repeating: "a", count: 63) + "\n"] {
                var changed = original
                var file = try XCTUnwrap(changed[key] as? Object)
                file["sha256"] = invalid; changed[key] = file
                try assertRejected(changed, catalog: target, as: .file)
            }
        }
    }

    func testInvalidOrDuplicateSkinCorrectionsAreRejected() throws {
        let target = try catalog(), original = document(for: target)
        let valid = ["skin": 0, "declared": 1, "corrected": 0]
        let invalidRoots: [[[String: Int]]] = [
            [["skin": -1, "declared": 1, "corrected": 0]],
            [["skin": 32, "declared": 1, "corrected": 0]],
            [["skin": 0, "declared": -1, "corrected": 0]],
            [["skin": 0, "declared": 4096, "corrected": 0]],
            [["skin": 0, "declared": 1, "corrected": -1]],
            [["skin": 0, "declared": 1, "corrected": 4096]],
            [["skin": 0, "declared": 1, "corrected": 1]],
            [valid, ["skin": 0, "declared": 2, "corrected": 0]],
            (0..<33).map { ["skin": $0, "declared": 1, "corrected": 0] }
        ]
        for roots in invalidRoots {
            let changed = try changingProfile(original) { $0["skinRoots"] = roots }
            try assertRejected(changed, catalog: target, as: .rig)
        }
    }

    func testInvalidDuplicateOrExcessiveMaterialsAreRejected() throws {
        let target = try catalog(), original = document(for: target)
        for mutation in 0..<6 {
            let changed = try changingProfile(original) { profile in
                var materials = try XCTUnwrap(profile["materials"] as? [Object])
                switch mutation {
                case 0: materials[0]["name"] = ""
                case 1: materials[0]["name"] = String(repeating: "m", count: 257)
                case 2: materials[0]["maxAnisotropy"] = 0
                case 3: materials[0]["maxAnisotropy"] = 17
                case 4: materials.append(materials[0])
                default:
                    let template = materials[0]
                    materials = (0..<129).map { index in
                        var material = template; material["name"] = "Synthetic_\(index)"; return material
                    }
                }
                profile["materials"] = materials
            }
            try assertRejected(changed, catalog: target, as: .material)
        }
    }

    func testUnsupportedMaterialEnumsCannotDecodeIntoSilentDefaults() throws {
        let original = document(for: try catalog())
        for (field, invalid) in [("cull", "none"), ("minification", "automatic"),
                                 ("magnification", "trilinear"), ("mip", "automatic"),
                                 ("wrapS", "mirroredRepeat"), ("wrapT", "automatic")] {
            let changed = try changingProfile(original) { profile in
                var materials = try XCTUnwrap(profile["materials"] as? [Object])
                materials[0][field] = invalid; profile["materials"] = materials
            }
            XCTAssertThrowsError(try decode(changed), field) { error in
                guard case DecodingError.dataCorrupted = error else {
                    return XCTFail("Expected an invalid enum decode failure, got \(error)")
                }
            }
        }
    }

    func testUnsupportedReleaseSchemaAndInvalidIdentityAreRejected() throws {
        let target = try catalog(), original = document(for: target)
        for version in [-1, 0, 2, Int.max] {
            var changed = original; changed["schemaVersion"] = version
            try assertRejected(changed, catalog: target, as: .version)
        }
        for id in ["", String(repeating: "i", count: 129)] {
            var changed = original; changed["id"] = id
            try assertRejected(changed, catalog: target, as: .identity)
        }
    }

    func testLegacyHammerCatalogCannotBeAuthorizedAsAPanguRelease() throws {
        let legacy = DuelWeaponTestFixtures.catalog()
        XCTAssertNoThrow(try legacy.validate())
        let legacyBindings = document(for: legacy)
        try assertRejected(legacyBindings, catalog: legacy, as: .profile,
                           "Matching old body, weapon and clip hashes must not authorize a Pangu catalog")
        let targetBindings = document(for: try catalog())
        try assertRejected(targetBindings, catalog: legacy, as: .profile)
    }
}
