import Foundation
import XCTest
@testable import ShiftReminder

@MainActor
final class DuelLocalRosterTests: XCTestCase {
    private typealias Fixture = DuelLocalProfileTestFixtures
    // Display projections only: no synthetic motion profile is represented as
    // an authenticated Serpent, Erlang, Founder or Triad combat resource.
    private var displayIdentities: [DuelGame.Hero: DuelLobbyIdentitySnapshot.Identity] {
        [
            .ember: .init(profileID: "sun_triad", bodyID: "arm__prc_43",
                weaponID: "wpn__ninjato_01_06", title: "孙登", weaponTitle: "黑色双刀",
                hasDirectionalAttacks: true, hasHeavy: true),
            .liu: .init(profileID: "liu_serpent", bodyID: "arm__agl_41",
                weaponID: "wpn__shuangou_01_04", title: "刘泉纬", weaponTitle: "毒牙双钩",
                hasDirectionalAttacks: true, hasHeavy: true),
            .wuYong: .init(profileID: "wuyong_erlang", bodyID: "arm__agl_44",
                weaponID: "wpn__agl_spear_01_01", title: "吴庸", weaponTitle: "天律长枪",
                hasDirectionalAttacks: true, hasHeavy: true),
            .gale: .init(profileID: "xuxiao_founder", bodyID: "arm__agl_49",
                weaponID: "wpn__imperial_gloves_01_01", title: "徐骁", weaponTitle: "帝国御拳",
                hasDirectionalAttacks: true, hasHeavy: true)
        ]
    }
    private var identity: DuelLobbyIdentitySnapshot {
        .init(displayIdentities: displayIdentities.filter { [.ember, .liu].contains($0.key) })
    }

    func testLoadingRosterCannotSilentlyStartALegacyMatch() {
        let roster = DuelLocalRoster(originalWeapons: true, identity: nil, displayedHero: nil)
        XCTAssertFalse(roster.isAvailable(.liu))
        XCTAssertNil(roster.setup(hero: .liu, preferredOpponent: .ember, difficulty: .learning, mode: .versus))
    }

    func testKnownFounderIdentifierDoesNotAdvertiseAbsentResources() {
        let roster = DuelLocalRoster(originalWeapons: true, identity: identity, displayedHero: .liu)
        XCTAssertTrue(roster.choices.contains(.gale))
        XCTAssertFalse(roster.isAvailable(.gale))
        XCTAssertFalse(roster.isAvailable(.wuYong))
        XCTAssertNil(roster.setup(hero: .gale, preferredOpponent: .liu, difficulty: .learning, mode: .practice))
    }

    func testSelectedNameCannotStartWhileAnotherPersonsPortraitIsDisplayed() {
        for displayed in [nil, DuelGame.Hero.ember] as [DuelGame.Hero?] {
            let roster = DuelLocalRoster(originalWeapons: true, identity: identity, displayedHero: displayed)
            XCTAssertTrue(roster.isAvailable(.liu))
            XCTAssertFalse(roster.canStart(hero: .liu, opponent: .ember))
            XCTAssertNil(roster.setup(hero: .liu, preferredOpponent: .ember, difficulty: .learning, mode: .versus))
        }
    }

    func testEveryLocalModeRetainsTheAuthenticatedSourceMode() throws {
        let roster = DuelLocalRoster(originalWeapons: true, identity: identity, displayedHero: .liu)
        for mode in [DuelGame.Mode.versus, .practice, .tutorial] {
            let setup = try XCTUnwrap(roster.setup(hero: .liu, preferredOpponent: .ember,
                difficulty: .challenging, mode: mode))
            XCTAssertTrue(setup.originalWeapons)
            XCTAssertEqual(setup.hero, .liu)
            XCTAssertEqual(setup.opponentHero, .ember)
            XCTAssertEqual(setup.mode, mode)
            XCTAssertEqual(setup.difficulty, .challenging)
        }
    }

    func testOpponentSelectionIncludesOnlyReadyDistinctPeople() {
        let roster = DuelLocalRoster(originalWeapons: true, identity: identity, displayedHero: .liu)
        XCTAssertEqual(roster.opponents(for: .liu), [.ember])
        XCTAssertEqual(roster.opponent(for: .liu, preferred: .gale), .ember)
        XCTAssertFalse(roster.canStart(hero: .liu, opponent: .gale))
        XCTAssertFalse(roster.canStart(hero: .liu, opponent: .liu))
    }

    func testSingleLoadedPersonCannotStartWithoutAnOpponent() {
        let roster = DuelLocalRoster(originalWeapons: true,
            identity: .init(displayIdentities: displayIdentities.filter { $0.key == .liu }), displayedHero: .liu)
        XCTAssertTrue(roster.isAvailable(.liu))
        XCTAssertNil(roster.opponent(for: .liu, preferred: .ember))
        XCTAssertNil(roster.setup(hero: .liu, preferredOpponent: .ember, difficulty: .learning, mode: .practice))
    }

    func testResourceFailureOverridesAnEarlierDisplayIdentityWithoutReplacingTheHero() {
        let snapshot = DuelLobbyIdentitySnapshot(displayIdentities: displayIdentities,
            unavailableReasons: [.wuYong: "角色资源校验未通过"])
        let roster = DuelLocalRoster(originalWeapons: true, identity: snapshot, displayedHero: .wuYong)
        XCTAssertEqual(snapshot.unavailableMessage(for: .wuYong), "角色资源校验未通过")
        XCTAssertNil(snapshot.intendedIdentity(for: .wuYong))
        XCTAssertFalse(roster.isAvailable(.wuYong))
        XCTAssertNil(roster.setup(hero: .wuYong, preferredOpponent: .ember,
                                  difficulty: .learning, mode: .practice))
        XCTAssertTrue(roster.isAvailable(.liu))
        XCTAssertTrue(roster.isAvailable(.ember))
        XCTAssertNil(snapshot.unavailableMessage(for: .liu))
    }

    func testAllFourPeopleRequireTheirSpecifiedSourceIdentity() throws {
        let snapshot = DuelLobbyIdentitySnapshot(displayIdentities: displayIdentities)
        let names: [DuelGame.Hero: String] = [.wuYong: "吴庸", .ember: "孙登", .liu: "刘泉纬", .gale: "徐骁"]
        for (hero, name) in names {
            let roster = DuelLocalRoster(originalWeapons: true, identity: snapshot, displayedHero: hero)
            XCTAssertTrue(roster.isAvailable(hero), name)
            XCTAssertEqual(try XCTUnwrap(snapshot.intendedIdentity(for: hero)).title, name)
            XCTAssertEqual(roster.opponents(for: hero).count, 3)
            let setup = try XCTUnwrap(roster.setup(hero: hero, preferredOpponent: .liu,
                difficulty: .learning, mode: .versus))
            XCTAssertEqual(setup.hero, hero)
            XCTAssertNotEqual(setup.opponentHero, hero)
            XCTAssertTrue(setup.originalWeapons)
        }
    }

    func testLegacyProfilesCannotBecomeReadyByChangingTheirDisplayedNames() throws {
        let legacy = DuelLobbyIdentitySnapshot(verifiedCatalog: Fixture.catalog)
        for hero in [DuelGame.Hero.ember, .liu] {
            XCTAssertNil(legacy.intendedIdentity(for: hero))
        }
        let oldIDs: [(DuelGame.Hero, String)] = [(.ember, "sun_katana"), (.liu, "liu_hammers"), (.liu, "liu_pangu")]
        for (hero, profileID) in oldIDs {
            let intended = try XCTUnwrap(displayIdentities[hero])
            let renamed = DuelLobbyIdentitySnapshot.Identity(profileID: profileID,
                bodyID: intended.bodyID, weaponID: intended.weaponID, title: intended.title,
                weaponTitle: intended.weaponTitle, hasDirectionalAttacks: true, hasHeavy: true)
            let snapshot = DuelLobbyIdentitySnapshot(displayIdentities: [hero: renamed])
            let roster = DuelLocalRoster(originalWeapons: true, identity: snapshot, displayedHero: hero)
            XCTAssertFalse(roster.isAvailable(hero), profileID)
            XCTAssertNil(snapshot.intendedIdentity(for: hero))
            XCTAssertNil(roster.setup(hero: hero, preferredOpponent: .ember, difficulty: .learning, mode: .versus))
        }
    }

    func testAnotherPersonsSourceProfileCannotUnlockTheSelectedName() {
        for (owner, identity) in displayIdentities {
            for hero in displayIdentities.keys where hero != owner {
                let snapshot = DuelLobbyIdentitySnapshot(displayIdentities: [hero: identity])
                let roster = DuelLocalRoster(originalWeapons: true, identity: snapshot, displayedHero: hero)
                XCTAssertFalse(roster.isAvailable(hero), "\(owner.name) cannot stand in for \(hero.name)")
                XCTAssertNil(snapshot.intendedIdentity(for: hero))
            }
        }
    }

    func testCorrectNamesAndProfileIDsCannotHideWrongBodyOrWeapon() {
        for (hero, identity) in displayIdentities {
            for wrongBody in [false, true] {
                let wrong = DuelLobbyIdentitySnapshot.Identity(profileID: identity.profileID,
                    bodyID: wrongBody ? "another_person_body" : identity.bodyID,
                    weaponID: wrongBody ? identity.weaponID : "another_set_weapon",
                    title: identity.title, weaponTitle: identity.weaponTitle,
                    hasDirectionalAttacks: true, hasHeavy: true)
                let snapshot = DuelLobbyIdentitySnapshot(displayIdentities: [hero: wrong])
                let roster = DuelLocalRoster(originalWeapons: true, identity: snapshot, displayedHero: hero)
                XCTAssertFalse(roster.isAvailable(hero), hero.name)
                XCTAssertNil(snapshot.intendedIdentity(for: hero))
            }
        }
    }

    func testExplicitLegacyModeRemainsIndependentOfSourceResourceReadiness() throws {
        let roster = DuelLocalRoster(originalWeapons: false, identity: nil, displayedHero: nil)
        XCTAssertEqual(roster.choices, [.ember, .gale, .liu])
        let setup = try XCTUnwrap(roster.setup(hero: .gale, preferredOpponent: .liu,
            difficulty: .learning, mode: .tutorial))
        XCTAssertFalse(setup.originalWeapons)
        XCTAssertEqual(setup.hero, .gale)
        XCTAssertEqual(setup.opponentHero, .liu)
        XCTAssertFalse(roster.isAvailable(.wuYong))
    }

    func testLegacyResourceLookupNeverBorrowsAnotherPersonsBody() throws {
        try Fixture.withDirectory { root in
            let directory = root.appendingPathComponent("Synthetic.bundle", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let plist: [String: Any] = ["CFBundleIdentifier": "com.synthetic." + UUID().uuidString,
                "CFBundleName": "Synthetic", "CFBundleVersion": "1", "CFBundlePackageType": "BNDL"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: directory.appendingPathComponent("Info.plist"))
            for name in ["Sun_FullBody_Prototype.glb", "Liu_FullBody_Mobile.glb"] {
                try Data("synthetic lookup only".utf8).write(to: directory.appendingPathComponent(name))
            }
            let bundle = try XCTUnwrap(Bundle(url: directory))
            XCTAssertNotNil(DuelCharacterAsset.bundledURL(for: .ember, bundle: bundle))
            XCTAssertNotNil(DuelCharacterAsset.bundledURL(for: .liu, bundle: bundle))
            XCTAssertNil(DuelCharacterAsset.bundledURL(for: .wuYong, bundle: bundle))
            XCTAssertNil(DuelCharacterAsset.bundledURL(for: .gale, bundle: bundle))
        }
    }

    func testDirectLegacyLoadingRejectsSourceOnlyPeopleBeforeOpeningAForeignModel() {
        let nonexistent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".glb")
        for hero in [DuelGame.Hero.wuYong, .gale] {
            XCTAssertThrowsError(try DuelCharacterAsset(url: nonexistent, hero: hero)) { error in
                guard let failure = error as? DuelCharacterAsset.AssetError else {
                    return XCTFail("Identity must fail before filesystem or model decoding")
                }
                if case .incomplete = failure {} else { XCTFail("Unexpected legacy identity failure") }
            }
        }
    }

    func testPreviewSelectionReportsOnlyTheLatestRenderedPerson() async {
        let coordinator = DuelLobbyPreview.Coordinator()
        var delivered: [DuelGame.Hero?] = []
        coordinator.updateSelection(.liu) { delivered.append($0) }
        coordinator.updateSelection(.ember) { delivered.append($0) }
        coordinator.updateSelection(nil) { delivered.append($0) }
        XCTAssertTrue(delivered.isEmpty, "SwiftUI update callbacks must be deferred")
        await drainMainQueue()
        XCTAssertEqual(delivered, [nil])
        coordinator.invalidate()
    }

    func testDismantledPreviewCannotPublishAStaleSelection() async {
        let coordinator = DuelLobbyPreview.Coordinator()
        var delivered: [DuelGame.Hero?] = []
        coordinator.updateSelection(.liu) { delivered.append($0) }
        coordinator.invalidate()
        await drainMainQueue()
        XCTAssertTrue(delivered.isEmpty)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
