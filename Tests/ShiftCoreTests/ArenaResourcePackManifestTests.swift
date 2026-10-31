import Foundation
import XCTest
@testable import ShiftCore

final class ArenaResourcePackManifestTests: XCTestCase {
    private func document() -> [String: Any] {
        let hash = String(repeating: "1", count: 64)
        return ["schemaVersion": 1, "id": "synthetic", "title": "Synthetic", "sourceDescription": "Synthetic data only",
                "sourceSHA256": hash,
                "files": [
                    ["path": "lobby/still.png", "bytes": 1, "sha256": hash, "kind": "image"],
                    ["path": "lobby/scene.json", "bytes": 1, "sha256": hash, "kind": "data"],
                    ["path": "fonts/sample.ttf", "bytes": 1, "sha256": hash, "kind": "font"],
                    ["path": "source/rules.json", "bytes": 1, "sha256": hash, "kind": "data"]],
                "heroes": [], "themes": [["id": "Default", "title": "Default", "backgroundFile": "lobby/still.png",
                                           "sceneFile": "lobby/scene.json", "sceneExport": "background",
                                           "sceneSourceRect": [-512, -288, 512, 288]]],
                "music": [], "musicBindings": [:], "maps": [],
                "fonts": [["id": "sample", "file": "fonts/sample.ttf", "postScriptName": "Sample"]],
                "sourceRulesFile": "source/rules.json"]
    }

    private func validate(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value)
        try JSONDecoder().decode(ArenaResourcePackManifest.self, from: data).validate()
    }

    func testTimelineAndFontReferencesRequireRegisteredMatchingKinds() throws {
        let valid = document()
        XCTAssertNoThrow(try validate(valid))
        for field in ["sourceRulesFile", "sourceMapCatalogFile", "sourceAssetIndexFile", "lobbyLayoutFile"] {
            var changed = valid
            changed[field] = "source/missing.json"
            XCTAssertThrowsError(try validate(changed), field)
            changed[field] = "lobby/still.png"
            XCTAssertThrowsError(try validate(changed), field)
        }
        var wrongFont = valid
        wrongFont["fonts"] = [["id": "sample", "file": "lobby/still.png", "postScriptName": "Sample"]]
        XCTAssertThrowsError(try validate(wrongFont))
        var incomplete = valid
        incomplete["themes"] = [["id": "Default", "title": "Default", "backgroundFile": "lobby/still.png", "sceneFile": "lobby/scene.json"]]
        XCTAssertThrowsError(try validate(incomplete))
    }

    func testTimelineCropCannotBeMissingReversedOrOutOfRange() throws {
        for rect: [Double] in [[], [0, 0, 10], [10, 0, 0, 10], [0, 10, 10, 0], [0, 0, 100_001, 10]] {
            var changed = document()
            var themes = changed["themes"] as! [[String: Any]]
            themes[0]["sceneSourceRect"] = rect
            changed["themes"] = themes
            XCTAssertThrowsError(try validate(changed), String(describing: rect))
        }
    }

    func testExistingPackWithoutOptionalTimelineFieldsRemainsValid() throws {
        var old = document()
        old["themes"] = [["id": "Default", "title": "Default", "backgroundFile": "lobby/still.png"]]
        old.removeValue(forKey: "sourceRulesFile")
        old.removeValue(forKey: "fonts")
        old["files"] = [["path": "lobby/still.png", "bytes": 1, "sha256": String(repeating: "1", count: 64), "kind": "image"]]
        XCTAssertNoThrow(try validate(old))
    }

    func testSchemaTwoPayloadLimitDoesNotRelaxLegacyPacks() throws {
        var value = document()
        value["themes"] = []
        value.removeValue(forKey: "fonts")
        value.removeValue(forKey: "sourceRulesFile")
        let chunks = (0..<17).map { index -> [String: Any] in
            ["path": "data/chunk-\(index).json", "bytes": 128 * 1024 * 1024,
             "sha256": String(repeating: "1", count: 64), "kind": "data"]
        }
        value["files"] = Array(chunks.prefix(9))
        XCTAssertThrowsError(try validate(value), "Schema 1 must retain the original 1 GiB limit")
        value["schemaVersion"] = 2
        XCTAssertNoThrow(try validate(value))
        value["files"] = chunks
        XCTAssertThrowsError(try validate(value), "Schema 2 must remain bounded to 2 GiB")
        value["schemaVersion"] = 3
        XCTAssertThrowsError(try validate(value))
    }
}
