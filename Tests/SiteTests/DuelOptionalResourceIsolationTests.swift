import Foundation
import XCTest
@testable import ShiftReminder

/// Synthetic profile fixtures test failure scope only. These tests do not
/// certify any recovered model, source material, animation or rendered pixel.
@MainActor
final class DuelOptionalResourceIsolationTests: XCTestCase {
    private typealias Fixture = DuelLocalProfileTestFixtures
    private typealias Loader = DuelLocalWeaponProfiles

    func testDamagedSerpentRemovesLegacyLiuWithoutDiscardingAnotherVerifiedProfile() throws {
        try Fixture.withDirectory { root in
            try Data("damaged optional profile".utf8)
                .write(to: root.appendingPathComponent(DuelSerpentAssetIdentity.profileName))
            var resolution = Loader.Resolution(profiles: Fixture.catalog.profiles)
            resolution.applyingOptional(hero: .liu, resourceName: DuelSerpentAssetIdentity.profileName) {
                try Loader.replacingOptionalSerpent(directory: root, in: $0, catalog: Fixture.catalog)
            }
            XCTAssertEqual(resolution.profiles, [Fixture.profile(.ember)])
            XCTAssertEqual(resolution.unavailableHeroes[.liu]?.stage, .profile)
            XCTAssertEqual(resolution.unavailableHeroes[.liu]?.resourceName, DuelSerpentAssetIdentity.profileName)
            XCTAssertFalse(resolution.profiles.contains { $0.hero == .liu })
            XCTAssertEqual(Fixture.catalog.profiles[1].id, "liu_hammers", "The signed base descriptor is not rewritten")

            let founder = Fixture.profile(.gale), bytes = try JSONEncoder().encode(founder)
            try bytes.write(to: root.appendingPathComponent(Loader.founderFileName))
            resolution.applyingOptional(hero: .gale, resourceName: Loader.founderFileName) {
                try Loader.appendingOptional(directory: root, name: Loader.founderFileName,
                    expectedSHA256: DuelWeaponAssets.digest(bytes), hero: .gale, profileID: "xuxiao_founder",
                    to: $0, catalog: Fixture.catalog)
            }
            XCTAssertEqual(resolution.profiles, [Fixture.profile(.ember), founder])
            XCTAssertNil(resolution.unavailableHeroes[.ember])
            XCTAssertNil(resolution.unavailableHeroes[.gale])
        }
    }

    func testUnpinnedOrWrongPersonOptionalFileOnlyQuarantinesItsAdvertisedSlot() throws {
        try Fixture.withDirectory { root in
            for (profile, independentlyPinned) in [(Fixture.profile(.gale), false), (Fixture.profile(.liu), true)] {
                let bytes = try JSONEncoder().encode(profile)
                try bytes.write(to: root.appendingPathComponent(Loader.founderFileName))
                var resolution = Loader.Resolution(profiles: Fixture.catalog.profiles)
                resolution.applyingOptional(hero: .gale, resourceName: Loader.founderFileName) {
                    try Loader.appendingOptional(directory: root, name: Loader.founderFileName,
                        expectedSHA256: independentlyPinned ? DuelWeaponAssets.digest(bytes) : nil,
                        hero: .gale, profileID: "xuxiao_founder", to: $0, catalog: Fixture.catalog)
                }
                XCTAssertEqual(resolution.profiles, Fixture.catalog.profiles)
                XCTAssertEqual(Set(resolution.unavailableHeroes.keys), [.gale])
                XCTAssertEqual(resolution.unavailableHeroes[.gale]?.stage, .profile)
                XCTAssertFalse(resolution.profiles.contains { $0.hero == .gale })
            }
        }
    }

    func testDefaultAndExplicitNetworkSelectionBothRejectLegacyIdentity() throws {
        try Fixture.catalog.validate()
        XCTAssertThrowsError(try Loader.networkCatalog(base: Fixture.catalog, profiles: Fixture.catalog.profiles))
        XCTAssertThrowsError(try Loader.networkCatalog(base: Fixture.catalog,
            profiles: Fixture.catalog.profiles, heroes: [.ember, .liu]))
        XCTAssertThrowsError(try Loader.networkCatalog(base: Fixture.catalog,
            profiles: [Fixture.profile(.ember)], heroes: [.ember, .liu]))
    }
}

/// Requires the real authenticated private pack. No environment variable or
/// absent-resource skip can turn these native boundary checks into a pass.
/// Mutations affect a private test copy; originals and build pins never change.
@MainActor
final class DuelOptionalResourceIsolationInstalledTests: XCTestCase {
    func testLocalMatchLoadsOnlySelectedPairFromBundledIndex() async throws {
        let index = try await DuelWeaponAssetIndex.loadBundled()
        let assets = try DuelWeaponAssets(verifiedIndex: index, purpose: .localMatch(.wuYong, .liu))
        let pair = try assets.localCatalog(hero: .wuYong, opponent: .liu)
        XCTAssertEqual(pair.profiles.map(\.hero), [.wuYong, .liu])
        XCTAssertNotNil(assets.loadedCharacter(for: .wuYong))
        XCTAssertNotNil(assets.loadedCharacter(for: .liu))
        XCTAssertNotNil(assets.erlangCompanions)
        XCTAssertNotNil(assets.serpentBottle)
        XCTAssertNil(assets.triadSummons)
        XCTAssertNil(assets.triadEffects)
        XCTAssertNil(assets.erlangVictoryMorph)
        XCTAssertNil(assets.serpentVictoryMorph)
        XCTAssertThrowsError(try assets.localCatalog(hero: .ember, opponent: .liu))
        XCTAssertThrowsError(try assets.requireNetworkCatalog())
        XCTAssertTrue(index.resolution.profiles.contains { $0.hero == .ember })
    }

    private func withInstalledCopy(_ body: (URL) throws -> Void) throws {
        let source = try XCTUnwrap(DuelWeaponAssets.catalogURL(), "Authenticated recovered resources must be installed")
            .deletingLastPathComponent()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fighter-isolation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        // A flat resource pack may live at the app bundle root. Do not duplicate
        // its executable/frameworks; copy the source loaders' resource formats.
        let extensions: Set<String> = ["json", "glb", "png", "jpg", "jpeg", "wav", "pcm", "bin", "metal", "gz", "texture"]
        for url in try FileManager.default.contentsOfDirectory(at: source,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isRegularFile == true, values.isSymbolicLink != true,
               extensions.contains(url.pathExtension.lowercased()) {
                try FileManager.default.copyItem(at: url, to: root.appendingPathComponent(url.lastPathComponent))
            }
        }
        try body(root)
    }

    private func changed(_ name: String, in root: URL, _ body: () throws -> Void) throws {
        let url = root.appendingPathComponent(name), original = try Data(contentsOf: url)
        guard !original.isEmpty else { XCTFail("The authenticated input is empty: \(name)"); return }
        var damaged = original
        damaged[damaged.count / 2] ^= 1
        try damaged.write(to: url, options: .atomic)
        defer { try? original.write(to: url, options: .atomic) }
        try body()
    }

    private func missing(_ name: String, in root: URL, _ body: () throws -> Void) throws {
        let url = root.appendingPathComponent(name), original = try Data(contentsOf: url)
        try FileManager.default.removeItem(at: url)
        defer { try? original.write(to: url, options: .atomic) }
        try body()
    }

    private func assertAvailablePair(_ heroes: [DuelGame.Hero], assets: DuelWeaponAssets,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let catalog = try assets.localCatalog(hero: heroes[0], opponent: heroes[1])
        XCTAssertEqual(catalog.profiles.map(\.hero), heroes, file: file, line: line)
        XCTAssertTrue(catalog.profiles.allSatisfy(\.isIntendedCharacter), file: file, line: line)
        for profile in catalog.profiles {
            let character = try assets.character(for: profile.hero)
            XCTAssertEqual(character.profile, profile, file: file, line: line)
            XCTAssertNotNil(character.model.node(named: profile.hero.characterIdentity.personalHeadNode), file: file, line: line)
        }
    }

    func testRestartAfterARealModelFailureCannotReplaceTheFightWithLegacySimulation() throws {
        try withInstalledCopy { root in
            let assets = try DuelWeaponAssets(directory: root)
            let setup = DuelSetup(hero: .wuYong, difficulty: .learning, mode: .practice,
                                  originalWeapons: true, opponentHero: .liu)
            let session = DuelSession(setup, installedAssets: assets)
            defer { session.shutdown() }
            XCTAssertNil(session.loadError)
            let profiles = try XCTUnwrap(session.game.weaponFight).profiles
            var resets = 0, simulatedSteps = 0
            session.didReset = { resets += 1 }
            session.didSimulateStep = { _, _ in simulatedSteps += 1 }
            let actorName = try XCTUnwrap(profiles.first { $0.hero == .wuYong }).resourceName + ".glb"
            try changed(actorName, in: root) {
                assets.releaseCharacter(for: .wuYong)
                XCTAssertThrowsError(try assets.character(for: .wuYong))
                XCTAssertEqual(assets.unavailableHeroes[.wuYong]?.stage, .model)
                session.restart()
                XCTAssertNotNil(session.loadError)
                XCTAssertTrue(session.paused)
                XCTAssertEqual(session.game.weaponFight?.profiles, profiles)
                XCTAssertEqual(resets, 0)
                XCTAssertEqual(simulatedSteps, 0)
            }
        }
    }

    func testBadOptionalProfilesPreserveUnrelatedPairsAndNeverRestoreLegacyLiu() throws {
        try withInstalledCopy { root in
            try changed(DuelErlangAssetIdentity.profileName, in: root) {
                let assets = try DuelWeaponAssets(directory: root)
                defer { assets.releaseCharacters() }
                XCTAssertEqual(assets.unavailableHeroes[.wuYong]?.stage, .profile)
                XCTAssertFalse(assets.localProfiles.contains { $0.hero == .wuYong })
                try assertAvailablePair([.ember, .liu], assets: assets)
                XCTAssertEqual(try assets.requireNetworkCatalog().profiles.map(\.hero), [.ember, .liu])
                XCTAssertThrowsError(try DuelWeaponAssets(directory: root, networkHeroes: [.wuYong, .liu]))
            }
            try changed(DuelSerpentAssetIdentity.profileName, in: root) {
                let assets = try DuelWeaponAssets(directory: root)
                defer { assets.releaseCharacters() }
                XCTAssertEqual(assets.unavailableHeroes[.liu]?.stage, .profile)
                XCTAssertFalse(assets.localProfiles.contains { $0.hero == .liu })
                XCTAssertNil(assets.networkCatalog)
                XCTAssertThrowsError(try assets.requireNetworkCatalog())
                XCTAssertThrowsError(try assets.character(for: .liu))
                XCTAssertThrowsError(try DuelWeaponAssets(directory: root, networkHeroes: [.ember, .liu]))
                try assertAvailablePair([.ember, .wuYong], assets: assets)
            }
            try missing(DuelSerpentAssetIdentity.profileName, in: root) {
                let assets = try DuelWeaponAssets(directory: root)
                defer { assets.releaseCharacters() }
                XCTAssertFalse(assets.localProfiles.contains { $0.hero == .liu && $0.isIntendedCharacter })
                XCTAssertNil(assets.networkCatalog)
                XCTAssertThrowsError(try assets.requireNetworkCatalog())
                XCTAssertThrowsError(try assets.localCatalog(hero: .liu, opponent: .ember))
                XCTAssertThrowsError(try DuelWeaponAssets(directory: root, networkHeroes: [.ember, .liu]))
                try assertAvailablePair([.ember, .wuYong], assets: assets)
            }
            let founderURL = root.appendingPathComponent(DuelLocalWeaponProfiles.founderFileName)
            XCTAssertFalse(FileManager.default.fileExists(atPath: founderURL.path), "No complete D20 is included in this reviewed pack")
            try Data("{}".utf8).write(to: founderURL)
            let assets = try DuelWeaponAssets(directory: root)
            defer { assets.releaseCharacters() }
            XCTAssertEqual(assets.unavailableHeroes[.gale]?.stage, .profile)
            XCTAssertFalse(assets.localProfiles.contains(where: \.isFounder))
            try assertAvailablePair([.wuYong, .liu], assets: assets)
            XCTAssertThrowsError(try assets.localCatalog(hero: .gale, opponent: .liu))
        }
    }

    func testChangedOptionalModelIsRejectedBeforeAdvertisingItsHero() throws {
        try withInstalledCopy { root in
            for (name, hero, usable) in [
                (DuelErlangAssetIdentity.profileName, DuelGame.Hero.wuYong, [DuelGame.Hero.ember, .liu]),
                (DuelSerpentAssetIdentity.profileName, DuelGame.Hero.liu, [DuelGame.Hero.ember, .wuYong])
            ] {
                let profile = try JSONDecoder().decode(DuelWeaponProfile.self,
                    from: Data(contentsOf: root.appendingPathComponent(name)))
                try changed(profile.resourceName + ".glb", in: root) {
                    let assets = try DuelWeaponAssets(directory: root)
                    defer { assets.releaseCharacters() }
                    XCTAssertEqual(assets.unavailableHeroes[hero]?.stage, .model)
                    XCTAssertEqual(assets.unavailableHeroes[hero]?.resourceName, profile.resourceName + ".glb")
                    XCTAssertFalse(assets.localProfiles.contains { $0.hero == hero })
                    XCTAssertThrowsError(try assets.character(for: hero))
                    try assertAvailablePair(usable, assets: assets)
                    XCTAssertThrowsError(try DuelWeaponAssets(directory: root, networkHeroes: [hero, usable[0]]))
                }
                try missing(profile.resourceName + ".glb", in: root) {
                    let assets = try DuelWeaponAssets(directory: root, purpose: .showroom)
                    XCTAssertEqual(assets.unavailableHeroes[hero]?.stage, .model)
                    XCTAssertFalse(assets.localProfiles.contains { $0.hero == hero })
                    XCTAssertThrowsError(try assets.character(for: hero))
                }
            }
        }
    }

    func testFailedOptionalCombatMediaDoesNotLeavePartialMediaOrBlockOtherPairs() throws {
        try withInstalledCopy { root in
            try changed(DuelErlangSkillEffectAssets.fileName, in: root) {
                let assets = try DuelWeaponAssets(directory: root)
                defer { assets.releaseCharacters() }
                XCTAssertEqual(assets.unavailableHeroes[.wuYong]?.stage, .combatMedia)
                XCTAssertNil(assets.erlangCompanions); XCTAssertNil(assets.erlangHoundEffects)
                XCTAssertNil(assets.erlangStompEffects); XCTAssertNil(assets.erlangSwordEffects)
                XCTAssertNil(assets.erlangSkillEffects); XCTAssertNil(assets.erlangAudio)
                XCTAssertNil(assets.erlangVictoryMorph)
                try assertAvailablePair([.ember, .liu], assets: assets)
                XCTAssertThrowsError(try assets.localCatalog(hero: .wuYong, opponent: .liu))
            }
            try changed(DuelSerpentBottlePresentation.fileName, in: root) {
                let assets = try DuelWeaponAssets(directory: root)
                defer { assets.releaseCharacters() }
                XCTAssertEqual(assets.unavailableHeroes[.liu]?.stage, .combatMedia)
                XCTAssertNil(assets.serpentAudio); XCTAssertNil(assets.serpentBottle)
                XCTAssertNil(assets.serpentVictoryMorph)
                try assertAvailablePair([.ember, .wuYong], assets: assets)
                XCTAssertThrowsError(try assets.requireNetworkCatalog())
            }
        }
    }

    func testBadVictoryMorphBlocksOnlyItsActualPairAndCannotUseOldHammerTarget() throws {
        try withInstalledCopy { root in
            for (name, target, other) in [
                (DuelErlangAssetIdentity.victoryMorphManifestName, DuelGame.Hero.wuYong, DuelGame.Hero.liu),
                (DuelSerpentAssetIdentity.victoryMorphManifestName, DuelGame.Hero.liu, DuelGame.Hero.wuYong)
            ] {
                try changed(name, in: root) {
                    let assets = try DuelWeaponAssets(directory: root)
                    defer { assets.releaseCharacters() }
                    XCTAssertTrue(assets.unavailableHeroes.isEmpty)
                    XCTAssertEqual(assets.pairFailure(for: [.ember, target])?.resourceName, name)
                    XCTAssertEqual(assets.pairFailure(for: [target, .ember])?.resourceName, name)
                    XCTAssertNil(assets.pairFailure(for: [.wuYong, .liu]))
                    try assertAvailablePair([.wuYong, .liu], assets: assets)
                    try assertAvailablePair([.ember, other], assets: assets)
                    XCTAssertThrowsError(try assets.localCatalog(hero: .ember, opponent: target))
                    XCTAssertThrowsError(try DuelWeaponAssets(directory: root, networkHeroes: [.ember, target]))
                    let pair = [.ember, target].compactMap { hero in assets.localProfiles.first { $0.hero == hero } }
                    XCTAssertEqual(pair.count, 2)
                    XCTAssertNil(assets.sourceMorph(for: pair), "A different target's verified morph is never a replacement")
                }
            }
        }
    }

    func testLateShowroomModelFailureUpdatesRosterAndCannotReloadAFallback() throws {
        try withInstalledCopy { root in
            let assets = try DuelWeaponAssets(directory: root, purpose: .showroom)
            defer { assets.releaseCharacters() }
            let liu = try XCTUnwrap(assets.localProfiles.first(where: \.isSerpent))
            try changed(liu.resourceName + ".glb", in: root) {
                XCTAssertThrowsError(try assets.character(for: .liu))
                XCTAssertEqual(assets.unavailableHeroes[.liu]?.stage, .model)
                XCTAssertFalse(assets.localProfiles.contains { $0.hero == .liu })
                XCTAssertNil(assets.loadedCharacter(for: .liu))
                XCTAssertNil(assets.networkCatalog)
                XCTAssertNotNil(try assets.character(for: .wuYong).model.node(named: "WuYong_Personal_Head"))
            }
            // Restoration on disk requires a fresh verified store. The failed
            // live store must not restore the old Liu profile behind the UI.
            XCTAssertThrowsError(try assets.character(for: .liu))
            XCTAssertFalse(assets.localProfiles.contains { $0.id == "liu_hammers" || $0.id == "liu_pangu" })
        }
    }
}
