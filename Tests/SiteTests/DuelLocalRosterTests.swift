import Foundation
import XCTest
@testable import ShiftReminder

@MainActor
final class DuelLocalRosterTests: XCTestCase {
    private typealias Fixture = DuelLocalProfileTestFixtures
    private var identity: DuelLobbyIdentitySnapshot { .init(verifiedCatalog: Fixture.catalog) }

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
            identity: .init(verifiedProfiles: [Fixture.profile(.liu)]), displayedHero: .liu)
        XCTAssertNil(roster.opponent(for: .liu, preferred: .ember))
        XCTAssertNil(roster.setup(hero: .liu, preferredOpponent: .ember, difficulty: .learning, mode: .practice))
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
