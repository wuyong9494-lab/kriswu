import CryptoKit
import XCTest
@testable import ShiftReminder

final class ArenaImportedMapAssetsTests: XCTestCase {
    private func map(title: String = "First layout") -> ArenaImportedMap {
        let evidence = "Hand-authored synthetic map fixture"
        let floor = ArenaImportedMap.Terrain(id: "floor", blocksMovement: false, blocksProjectiles: false,
            concealsHeroes: false, destructible: false, evidence: evidence,
            runtimeBehavior: .init(visualKind: .floor, destroyedByNormalWeapons: false,
                                   destroyedInOvertime: false, evidence: evidence))
        return ArenaImportedMap(identity: .init(namespace: "fixture", dataset: "one", location: "arena", layout: "grid"),
            title: title, runtimeTheme: "stone", sourceRows: Array(repeating: ".....", count: 5),
            terrain: [floor], bindings: [.init(symbol: ".", terrainID: "floor", evidence: evidence)],
            spawns: [.init(team: 0, cells: [.init(0, 4), .init(2, 4), .init(4, 4)], evidence: evidence),
                     .init(team: 1, cells: [.init(0, 0), .init(2, 0), .init(4, 0)], evidence: evidence)],
            objectives: .init(center: V2(2.5, 2.5), evidence: evidence),
            mode: .init(sourceMode: "syntheticTeams", runtimeMode: "teamFight", teamCount: 2, teamSize: 3,
                        evidence: evidence), mappingEvidence: evidence)
    }

    private func writePack(at root: URL, title: String = "First layout", catalogID: String? = nil) throws -> URL {
        let descriptor = map(title: title)
        let catalogue: [String: Any] = ["schemaVersion": 1, "maps": [[
            "id": catalogID ?? descriptor.stableID, "title": "Synthetic arena", "file": "maps/arena.json",
            "environmentThemeID": "synthetic", "runtimeMode": "teamFight"]]]
        let payloads: [(String, Data)] = [
            ("maps/catalog.json", try JSONSerialization.data(withJSONObject: catalogue, options: .sortedKeys)),
            ("maps/arena.json", try JSONEncoder().encode(descriptor))]
        let manifest: [String: Any] = [
            "schemaVersion": 1, "id": "synthetic-maps", "title": "Synthetic maps",
            "sourceDescription": "Generated test content only", "sourceSHA256": String(repeating: "0", count: 64),
            "heroes": [], "themes": [], "music": [], "musicBindings": [:], "maps": [],
            "playableMapsFile": "maps/catalog.json",
            "files": payloads.map { path, data -> [String: Any] in ["path": path, "bytes": data.count,
                "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), "kind": "data"] }]
        let raw = try JSONSerialization.data(withJSONObject: manifest, options: .sortedKeys)
        var bytes = ArenaResourcePackArchive.magic
        var length = UInt32(raw.count).littleEndian
        bytes.append(withUnsafeBytes(of: &length) { Data($0) })
        bytes.append(raw)
        for (_, data) in payloads { bytes.append(data) }
        let url = root.appendingPathComponent(UUID().uuidString + ".arenapack")
        try bytes.write(to: url)
        return url
    }

    @MainActor
    private func fixture(_ body: @MainActor (ArenaResourcePackStore, ArenaImportedMapAssets, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "map-assets-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "arena.resources.hasChosenCombatHero")
        let store = ArenaResourcePackStore(defaults: defaults, directory: root.appendingPathComponent("installed"))
        await store.install(from: try writePack(at: root))
        XCTAssertNil(store.error)
        try await body(store, ArenaImportedMapAssets(store: store), root)
    }

    @MainActor
    func testPreviewAndMatchUseTheSameValidatedLayout() async throws {
        try await fixture { _, assets, _ in
            let id = try XCTUnwrap(assets.maps(for: .teamFight).first?.id)
            let preview = try await assets.previewChoice(id: id)
            let match = try assets.choice(id: id)
            XCTAssertEqual(preview, match)
            XCTAssertEqual(preview.plan.map.id, self.map().stableID)
            XCTAssertEqual(preview.plan.map.title, "First layout")
            XCTAssertEqual(preview.plan.mode, .teamFight)
        }
    }

    @MainActor
    func testReplacementWithIdenticalCatalogueReloadsChangedLayout() async throws {
        try await fixture { store, assets, root in
            let id = self.map().stableID
            _ = try await assets.previewChoice(id: id)
            let revision = store.contentRevision
            let before = try XCTUnwrap(store.url(for: "maps/catalog.json"))
            let catalogue = try Data(contentsOf: before)
            await store.install(from: try self.writePack(at: root, title: "Replacement layout"))
            XCTAssertNil(store.error)
            XCTAssertNotEqual(store.contentRevision, revision)
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.url(for: "maps/catalog.json"))), catalogue)
            let updated = try await assets.previewChoice(id: id)
            XCTAssertEqual(updated.plan.map.title, "Replacement layout")
            XCTAssertEqual(try assets.choice(id: id).plan.map.title, "Replacement layout")
        }
    }

    @MainActor
    func testDisabledPackRejectsCachedMapAndRecoversWhenEnabled() async throws {
        try await fixture { store, assets, _ in
            let id = self.map().stableID
            _ = try await assets.previewChoice(id: id)
            store.setEnabled(false)
            XCTAssertTrue(assets.maps(for: .teamFight).isEmpty)
            XCTAssertThrowsError(try assets.choice(id: id))
            do {
                _ = try await assets.previewChoice(id: id)
                XCTFail("A disabled pack must not expose a cached preview")
            } catch { XCTAssertTrue(error is ArenaResourcePackManifest.ValidationError) }
            store.setEnabled(true)
            let restored = try await assets.previewChoice(id: id)
            XCTAssertEqual(restored.plan.map.id, id)
        }
    }

    @MainActor
    func testCancelledPreviewRejectsEvenAnAlreadyCachedLayout() async throws {
        try await fixture { _, assets, _ in
            let id = self.map().stableID
            _ = try await assets.previewChoice(id: id)
            let request = Task { @MainActor in try await assets.previewChoice(id: id) }
            request.cancel()
            do {
                _ = try await request.value
                XCTFail("Cancelled views must not publish a cached result")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
    }

    @MainActor
    func testCatalogueCannotRenameAnUnrelatedLayout() async throws {
        try await fixture { store, assets, root in
            let wrongID = "imported:fixture:one:different"
            await store.install(from: try self.writePack(at: root, catalogID: wrongID))
            XCTAssertNil(store.error)
            do {
                _ = try await assets.previewChoice(id: wrongID)
                XCTFail("Catalogue and terrain identities must agree")
            } catch { XCTAssertTrue(error is ArenaResourcePackManifest.ValidationError) }
            XCTAssertThrowsError(try assets.choice(id: wrongID))
        }
    }
}
