import Foundation
import XCTest
@testable import ShiftReminder

/// Original resource tests, separate from the resource-free roster CI gate.
@MainActor
final class DuelSerpentProfileSourceTests: XCTestCase {
    private func data(_ key: String) throws -> Data {
        if let path = ProcessInfo.processInfo.environment[key] {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        }
        let names = ["SERPENT_MATCH_PROFILE": "SF3_Serpent_Profile.json",
                     "ERLANG_MATCH_PROFILE": "SF3_Erlang_Profile.json",
                     "SERPENT_BASE_CATALOG": "Validation_PreStunCatalog.json"]
        let name = try XCTUnwrap(names[key], "Unknown private source input")
        let file = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: nil) ??
            Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "FighterPrivate"),
            "The authenticated native resource must be installed: \(name)")
        return try Data(contentsOf: file)
    }
    private func base() throws -> DuelWeaponCatalog {
        let bytes = try data("SERPENT_BASE_CATALOG")
        XCTAssertEqual(DuelWeaponAssets.digest(bytes), "fbd9ecbd9fb16de79c0240404e315af81d8cbbaa113b6042e6afc5ed7b1d0330")
        let catalog = try JSONDecoder().decode(DuelWeaponCatalog.self, from: bytes)
        try catalog.validate()
        XCTAssertEqual(catalog.profiles.map(\.id), ["sun_triad", "liu_hammers"])
        return catalog
    }
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
    private func replaced(_ root: URL, base: DuelWeaponCatalog) throws -> [DuelWeaponProfile] {
        try DuelLocalWeaponProfiles.replacingOptionalSerpent(directory: root, in: base.profiles, catalog: base)
    }

    func testPinnedOriginalD13ReplacesOnlyLegacyLiuAndKeepsSignedBaseCatalogSeparate() throws {
        let base = try base(), raw = try data("SERPENT_MATCH_PROFILE")
        XCTAssertEqual(DuelWeaponAssets.digest(raw), DuelSerpentAssetIdentity.profileSHA256)
        try withDirectory { root in
            try raw.write(to: root.appendingPathComponent(DuelSerpentAssetIdentity.profileName))
            let profiles = try replaced(root, base: base)
            XCTAssertEqual(profiles.map(\.id), ["sun_triad", "liu_serpent"])
            XCTAssertEqual(profiles[0], base.profiles[0])
            XCTAssertEqual(base.profiles[1].id, "liu_hammers")
            let liu = profiles[1]
            XCTAssertEqual(liu.title, "刘泉纬")
            XCTAssertEqual(liu.bodyID, "arm__agl_41")
            XCTAssertEqual(liu.weaponID, "wpn__shuangou_01_04")
            XCTAssertEqual(liu.sha256, DuelSerpentAssetIdentity.characterSHA256)
            XCTAssertNotNil(liu.serpentBinding)
            XCTAssertNil(liu.panguRules)
            let network = try DuelLocalWeaponProfiles.networkCatalog(base: base, profiles: profiles)
            XCTAssertEqual(network.profiles, profiles)
            XCTAssertEqual(DuelMultiplayerSelection.Choice.availableIntended(in: network).map(\.weapon), [.ninjato, .serpent])
        }
    }

    func testAbsentOptionalProfileRemainsUnavailableAndChangedBytesCannotDowngradeToHammers() throws {
        let base = try base()
        try withDirectory { root in
            let absent = try replaced(root, base: base)
            XCTAssertEqual(absent, base.profiles)
            XCTAssertThrowsError(try DuelLocalWeaponProfiles.networkCatalog(base: base,
                profiles: absent, heroes: [.ember, .liu]))
            var changed = try data("SERPENT_MATCH_PROFILE")
            changed[changed.count - 1] ^= 1
            try changed.write(to: root.appendingPathComponent(DuelSerpentAssetIdentity.profileName))
            XCTAssertThrowsError(try replaced(root, base: base))
        }
    }

    func testSelectedWuLiuPairUsesOriginalProfilesAndRejectsMissingFounderOrDuplicateHero() throws {
        let base = try base()
        let wu = try JSONDecoder().decode(DuelWeaponProfile.self, from: data("ERLANG_MATCH_PROFILE"))
        try withDirectory { root in
            try data("SERPENT_MATCH_PROFILE").write(to: root.appendingPathComponent(DuelSerpentAssetIdentity.profileName))
            let profiles = try replaced(root, base: base) + [wu]
            for heroes in [[DuelGame.Hero.wuYong, .liu], [.liu, .wuYong], [.wuYong, .ember]] {
                let pair = try DuelLocalWeaponProfiles.networkCatalog(base: base, profiles: profiles, heroes: heroes)
                XCTAssertEqual(pair.profiles.map(\.hero), heroes)
                XCTAssertTrue(pair.profiles.allSatisfy(\.isIntendedCharacter))
                XCTAssertEqual(DuelMultiplayerSelection.Choice.availableIntended(in: pair).count, 2)
                XCTAssertFalse(pair.profiles.contains { $0.id == "liu_hammers" || $0.id == "liu_pangu" })
            }
            for invalid in [[DuelGame.Hero.gale, .liu], [.liu, .liu], [.liu]] {
                XCTAssertThrowsError(try DuelLocalWeaponProfiles.networkCatalog(base: base, profiles: profiles, heroes: invalid))
            }
        }
    }

    func testInstalledSelectedPairsPrepareOnlyTheirActualModelsAndContentIdentities() throws {
        // This class already requires authenticated private inputs. An omitted
        // launch environment variable must not silently skip the only check of
        // the actual selected network models and their resource fingerprints.
        var fingerprints = Set<String>()
        for heroes in [[DuelGame.Hero.ember, .liu], [.wuYong, .liu], [.ember, .wuYong]] {
            let prepared = try DuelNetworkCompatibilityIdentity.prepare(heroes: heroes)
            defer { prepared.release() }
            XCTAssertTrue(prepared.hasExactResources)
            let assets = try XCTUnwrap(prepared.assets)
            XCTAssertEqual(prepared.identity.catalog.profiles.map(\.hero), heroes)
            XCTAssertEqual(assets.networkCatalog, prepared.identity.catalog)
            let networkCatalog = try assets.requireNetworkCatalog()
            XCTAssertTrue(networkCatalog.profiles.allSatisfy(\.isIntendedCharacter))
            XCTAssertEqual(DuelMultiplayerSelection.Choice.availableIntended(in: prepared.identity.catalog).count, 2)
            fingerprints.insert(prepared.identity.compatibility.catalogFingerprint)
            if heroes.contains(.liu) {
                let liu = try XCTUnwrap(prepared.loadedCharacter(for: .liu))
                XCTAssertEqual(liu.profile.id, "liu_serpent")
                XCTAssertEqual(liu.profile.sha256, DuelSerpentAssetIdentity.characterSHA256)
                XCTAssertNil(liu.sourceTrails, "The base hammer trail binding cannot be borrowed by D13")
                XCTAssertNil(liu.releaseBinding, "A legacy Liu release binding must not attach to D13")
                XCTAssertNotNil(liu.model.node(named: "Liu_Personal_Head"))
                XCTAssertFalse(liu.model.materialNames.contains("mat_wpn__hammers_01_01_base"))
                XCTAssertTrue(prepared.identity.verifiedFiles.contains {
                    $0.path == "serpent-bottle/SF3_D13_Bottle_Source.glb" &&
                    $0.sha256 == DuelSerpentBottlePresentation.fileSHA256
                })
                XCTAssertTrue(prepared.identity.verifiedFiles.contains {
                    $0.path == "local-profiles/SF3_Serpent_Profile.json" &&
                    $0.sha256 == DuelSerpentAssetIdentity.profileSHA256
                })
            }
            if heroes == [.ember, .liu] {
                let morph = try XCTUnwrap(assets.sourceMorph(for: networkCatalog.profiles))
                XCTAssertEqual(morph.ownerProfileID, "sun_triad")
                XCTAssertEqual(morph.targetProfileID, "liu_serpent")
                XCTAssertEqual(morph.targetCharacterSHA256, DuelSerpentAssetIdentity.characterSHA256)
                XCTAssertTrue(prepared.identity.verifiedFiles.contains {
                    $0.path == "serpent-victory-target/" + DuelSerpentAssetIdentity.victoryMorphManifestName &&
                    $0.sha256 == DuelSerpentAssetIdentity.victoryMorphManifestSHA256
                })
            }
            if heroes.contains(.wuYong) {
                let wu = try XCTUnwrap(prepared.loadedCharacter(for: .wuYong))
                XCTAssertEqual(wu.profile.id, "wuyong_erlang")
                XCTAssertNil(wu.sourceTrails)
                XCTAssertNotNil(assets.erlangCompanions)
                XCTAssertTrue(prepared.identity.verifiedFiles.contains { $0.path.hasPrefix("erlang-companions/") })
                let retainedAudio = try XCTUnwrap(prepared.sourceEffects?.erlangAudio,
                    "The network effects owner must retain D15 event audio, not merely fingerprint its files")
                XCTAssertEqual(retainedAudio.profileID, wu.profile.id)
                XCTAssertEqual(retainedAudio.characterSHA256, wu.profile.sha256)
                XCTAssertEqual(retainedAudio.verifiedFiles, try XCTUnwrap(assets.erlangAudio).verifiedFiles)
            }
        }
        XCTAssertEqual(fingerprints.count, 3, "Different actual pairs must not share a content identity")
    }
}
