import Foundation
import XCTest
@testable import ShiftReminder

/// Synthetic interpreter fixtures only; they do not assert source-asset or
/// visual acceptance for any character.
@MainActor
enum DuelLocalProfileTestFixtures {
    static func profile(_ hero: DuelGame.Hero, sourceRules: Bool = true,
                        bodyID: String? = nil) -> DuelWeaponProfile {
        let identity: (String, String)
        switch hero {
        case .ember: identity = ("sun_katana", "a")
        case .liu: identity = ("liu_hammers", "b")
        case .wuYong: identity = ("wuyong_erlang", "c")
        case .gale: identity = ("xuxiao_founder", "d")
        }
        let count = 17
        let zero = Array(repeating: DuelWeaponPoint(), count: count)
        let tracks = DuelWeaponTracks(samplesPerSourceFrame: 2,
            root: zero, handL: zero, handR: zero, footL: zero, footR: zero,
            weaponBaseL: [], weaponTipL: [], weaponBaseR: zero,
            weaponTipR: Array(repeating: .init(x: 1, y: 1), count: count),
            groundLift: Array(repeating: 0, count: count))
        let clip = DuelWeaponClip(name: "Synthetic_" + hero.rawValue, frames: 9,
            sha256: String(repeating: "f", count: 64), bundle: "synthetic-test-only", tracks: tracks)
        let roles = Dictionary(uniqueKeysWithValues:
            ["idle", "walkForward", "walkBackward", "guard", "jump", "hit", "knockdown",
             "getUp", "weapon1", "heavy", "kick"].map { ($0, clip.name) })
        func make(_ rules: DuelCombatRuleProfile?) -> DuelWeaponProfile {
            .init(id: identity.0, hero: hero, faction: "Synthetic", resourceName: "Synthetic_" + hero.rawValue,
                bytes: 128, sha256: String(repeating: identity.1, count: 64),
                bodyID: bodyID ?? "body_" + hero.rawValue, weaponID: "weapon_" + hero.rawValue,
                activeWeaponSides: ["right"], roles: roles, clips: [clip], combatRules: rules)
        }
        let profile = make(nil)
        guard hero == .gale, sourceRules else { return profile }
        return make(.init(id: "synthetic-founder-contract", basis: .sourceConfiguration,
            sourceVersion: "synthetic-test-only", sourceSHA256: String(repeating: "e", count: 64),
            evidence: ["Synthetic validation fixture; not recovered D20 combat data"],
            attacks: DuelCombatRuleProfile.legacy(for: profile).attacks))
    }

    static var catalog: DuelWeaponCatalog {
        .init(schemaVersion: 1, previewFramesPerSecond: 30, profiles: [profile(.ember), profile(.liu)])
    }

    static func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
}

@MainActor
final class DuelLocalWeaponProfileTests: XCTestCase {
    private typealias Fixture = DuelLocalProfileTestFixtures
    private typealias Loader = DuelLocalWeaponProfiles

    private func write(_ profile: DuelWeaponProfile, to root: URL) throws -> Data {
        let data = try JSONEncoder().encode(profile)
        try data.write(to: root.appendingPathComponent(Loader.founderFileName))
        return data
    }

    private func append(_ root: URL, pin: String?, profiles: [DuelWeaponProfile]? = nil,
                        characterSHA256: String? = nil) throws -> [DuelWeaponProfile] {
        try Loader.appendingOptional(directory: root, name: Loader.founderFileName,
            expectedSHA256: pin, hero: .gale, profileID: "xuxiao_founder",
            characterSHA256: characterSHA256, to: profiles ?? Fixture.catalog.profiles, catalog: Fixture.catalog)
    }

    func testAbsentOptionalProfilePreservesTheVerifiedRoster() throws {
        try Fixture.withDirectory { root in
            XCTAssertEqual(try append(root, pin: nil), Fixture.catalog.profiles)
        }
    }

    func testPresentProfileCannotTrustItsOwnModelHash() throws {
        try Fixture.withDirectory { root in
            _ = try write(Fixture.profile(.gale), to: root)
            for pin in [nil, ""] as [String?] {
                XCTAssertThrowsError(try append(root, pin: pin)) {
                    XCTAssertEqual($0 as? Loader.Failure, .missingPin)
                }
            }
        }
    }

    func testMalformedBuildPinIsRejectedBeforeDecoding() throws {
        try Fixture.withDirectory { root in
            _ = try write(Fixture.profile(.gale), to: root)
            for pin in [String(repeating: "g", count: 64), String(repeating: "A", count: 64), "short"] {
                XCTAssertThrowsError(try append(root, pin: pin)) {
                    XCTAssertEqual($0 as? Loader.Failure, .invalidPin)
                }
            }
        }
    }

    func testAuthenticatedFounderAppendsWithoutRelabelingExistingProfiles() throws {
        try Fixture.withDirectory { root in
            let founder = Fixture.profile(.gale)
            let data = try write(founder, to: root)
            let actual = try append(root, pin: DuelWeaponAssets.digest(data))
            XCTAssertEqual(actual, Fixture.catalog.profiles + [founder])
            for other in Fixture.catalog.profiles {
                XCTAssertNoThrow(try DuelWeaponCatalog(schemaVersion: 1, previewFramesPerSecond: 30,
                    profiles: [founder, other]).validate())
            }
        }
    }

    func testSameSizeChangedProfileCannotPassTheTrustedDigest() throws {
        try Fixture.withDirectory { root in
            let original = try write(Fixture.profile(.gale), to: root)
            var changed = original
            changed[0] = changed[0] == 123 ? 91 : 123
            XCTAssertEqual(changed.count, original.count)
            try changed.write(to: root.appendingPathComponent(Loader.founderFileName))
            XCTAssertThrowsError(try append(root, pin: DuelWeaponAssets.digest(original)))
        }
    }

    func testSymlinkCannotSupplyAnOtherwiseAuthenticatedProfile() throws {
        try Fixture.withDirectory { root in
            let data = try JSONEncoder().encode(Fixture.profile(.gale))
            let target = root.appendingPathComponent("Synthetic_Target.json")
            try data.write(to: target)
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(Loader.founderFileName),
                                                       withDestinationURL: target)
            XCTAssertThrowsError(try append(root, pin: DuelWeaponAssets.digest(data)))
        }
    }

    func testDifferentPersonsProfileIsRejectedEvenWithItsCorrectDigest() throws {
        try Fixture.withDirectory { root in
            let data = try write(Fixture.profile(.liu), to: root)
            XCTAssertThrowsError(try append(root, pin: DuelWeaponAssets.digest(data))) {
                XCTAssertEqual($0 as? Loader.Failure, .identity)
            }
        }
    }

    func testDuplicateLocalPersonCannotReplaceAnExistingVerifiedProfile() throws {
        try Fixture.withDirectory { root in
            let founder = Fixture.profile(.gale)
            let data = try write(founder, to: root)
            XCTAssertThrowsError(try append(root, pin: DuelWeaponAssets.digest(data),
                profiles: Fixture.catalog.profiles + [founder])) {
                XCTAssertEqual($0 as? Loader.Failure, .identity)
            }
        }
    }

    func testIndependentCharacterPinMustMatchTheProfile() throws {
        try Fixture.withDirectory { root in
            let data = try write(Fixture.profile(.gale), to: root)
            XCTAssertThrowsError(try append(root, pin: DuelWeaponAssets.digest(data),
                characterSHA256: String(repeating: "a", count: 64))) {
                XCTAssertEqual($0 as? Loader.Failure, .identity)
            }
        }
    }

    func testAllOpponentsAreValidatedBeforeAdvertisingANewPerson() throws {
        try Fixture.withDirectory { root in
            // The first pairing is valid; only the second shares this body.
            let data = try write(Fixture.profile(.gale, bodyID: "body_liu"), to: root)
            XCTAssertThrowsError(try append(root, pin: DuelWeaponAssets.digest(data)))
        }
    }

    func testFounderWithoutSourceRulesCannotUseLegacyCombatFallback() throws {
        try Fixture.withDirectory { root in
            let data = try write(Fixture.profile(.gale, sourceRules: false), to: root)
            XCTAssertThrowsError(try append(root, pin: DuelWeaponAssets.digest(data)))
        }
    }

    func testUnsafeProfilePathIsRejectedBeforeCheckingForAFile() throws {
        try Fixture.withDirectory { root in
            XCTAssertThrowsError(try Loader.appendingOptional(directory: root, name: "../profile.json",
                expectedSHA256: nil, hero: .gale, profileID: "xuxiao_founder",
                to: Fixture.catalog.profiles, catalog: Fixture.catalog)) {
                XCTAssertEqual($0 as? Loader.Failure, .identity)
            }
        }
    }
}
