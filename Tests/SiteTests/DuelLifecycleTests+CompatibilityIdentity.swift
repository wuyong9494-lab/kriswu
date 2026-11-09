import XCTest
@testable import ShiftReminder

/// Runs with the existing DuelLifecycleTests native suite; no workflow expansion.
extension DuelLifecycleTests {
    private var identityBuildContext: [String: String] {
        var value = Dictionary(uniqueKeysWithValues: DuelNetworkRulesManifest.buildKeys.map { ($0, "1") })
        value["mode"] = "xcode"; value["TARGET_NAME"] = "ShiftReminder"
        return value
    }
    private var identitySourceFiles: [DuelNetworkContentRecord] {
        DuelNetworkRulesManifest.requiredPaths.sorted().map {
            .init(path: $0, bytes: 3, sha256: DuelNetworkContentRecord.digest(Data("abc".utf8)))
        }
    }
    private func identityManifest(files: [DuelNetworkContentRecord]? = nil,
                                  build: [String: String]? = nil,
                                  mutate: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        let files = files ?? identitySourceFiles, build = build ?? identityBuildContext
        var object: [String: Any] = [
            "schemaVersion": 1, "recipe": DuelNetworkRulesManifest.recipe, "build": build,
            "files": files.map { ["path": $0.path, "bytes": $0.bytes, "sha256": $0.sha256] as [String: Any] },
            "fingerprint": DuelNetworkContentRecord.fingerprint(files, recipe: DuelNetworkRulesManifest.recipe, context: build)
        ]
        mutate(&object)
        return try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
    }

    func testNetworkIdentityRulesAcceptOnlySupportedVerifiedManifest() throws {
        let bytes = try identityManifest()
        let first = try DuelNetworkRulesManifest(data: bytes)
        let second = try DuelNetworkRulesManifest(data: bytes)
        XCTAssertEqual(first.fingerprint, second.fingerprint)
        XCTAssertEqual(first.files, identitySourceFiles)
        XCTAssertEqual(first.build, identityBuildContext)
        XCTAssertTrue(DuelNetworkContentRecord.validDigest(first.fingerprint))
        for data in [Data(), Data("not JSON".utf8), Data(repeating: 32, count: DuelNetworkRulesManifest.maximumBytes + 1)] {
            XCTAssertThrowsError(try DuelNetworkRulesManifest(data: data))
        }
        for key in ["schemaVersion", "recipe", "files", "build", "fingerprint"] {
            XCTAssertThrowsError(try DuelNetworkRulesManifest(data: identityManifest { $0.removeValue(forKey: key) }))
        }
        XCTAssertThrowsError(try DuelNetworkRulesManifest(data: identityManifest { $0["unexpected"] = 1 }))
        XCTAssertThrowsError(try DuelNetworkRulesManifest(data: identityManifest { $0["schemaVersion"] = 2 }))
        XCTAssertThrowsError(try DuelNetworkRulesManifest(data: identityManifest { $0["recipe"] = "semver" }))
        XCTAssertThrowsError(try DuelNetworkRulesManifest(data: identityManifest { $0["fingerprint"] = String(repeating: "0", count: 64) }))
    }

    func testNetworkIdentityRulesRejectMissingDuplicateUnsortedOrUnsafeSources() throws {
        let files = identitySourceFiles
        XCTAssertThrowsError(try DuelNetworkRulesManifest(data: identityManifest(files: Array(files.dropFirst()))))
        XCTAssertThrowsError(try DuelNetworkRulesManifest(data: identityManifest(files: files + [files[0]])))
        XCTAssertThrowsError(try DuelNetworkRulesManifest(data: identityManifest(files: Array(files.reversed()))))
        for path in ["App/../secret.swift", "/tmp/Duel.swift", "Widget/Widget.swift", "App/secret.glb", "App/bad\n.swift", "App/Extra.swift\n"] {
            let extra = DuelNetworkContentRecord(path: path, bytes: 3, sha256: files[0].sha256)
            XCTAssertThrowsError(try DuelNetworkRulesManifest(data: identityManifest(
                files: (files + [extra]).sorted { $0.path < $1.path })))
        }
        for (count, hash) in [(0, files[0].sha256), (8_000_001, files[0].sha256),
                              (3, files[0].sha256.uppercased()), (3, "not-a-digest")] {
            var invalid = files
            invalid[0] = .init(path: files[0].path, bytes: count, sha256: hash)
            XCTAssertThrowsError(try DuelNetworkRulesManifest(data: identityManifest(files: invalid)))
        }
        let additional = DuelNetworkContentRecord(path: "App/Nested/AppStore+New.generated.swift", bytes: 3, sha256: files[0].sha256)
        XCTAssertNoThrow(try DuelNetworkRulesManifest(data: identityManifest(
            files: (files + [additional]).sorted { $0.path < $1.path })))
    }

    func testNetworkIdentityBindsSourceBytesAndBuildSettingsNotJustNames() throws {
        let original = try DuelNetworkRulesManifest(data: identityManifest())
        var changed = identitySourceFiles
        changed[0] = .init(path: changed[0].path, bytes: 3, sha256: DuelNetworkContentRecord.digest(Data("abd".utf8)))
        let edited = try DuelNetworkRulesManifest(data: identityManifest(files: changed))
        XCTAssertNotEqual(original.fingerprint, edited.fingerprint)
        var build = identityBuildContext; build["CONFIGURATION"] = "Release"
        XCTAssertNotEqual(original.fingerprint, try DuelNetworkRulesManifest(data: identityManifest(build: build)).fingerprint)
        for (key, value) in [("mode", "source-only"), ("TARGET_NAME", "ShiftWidget"),
                             ("SDK_VERSION", ""), ("CONFIGURATION", "/Users/local"), ("CONFIGURATION", "Debug\n"),
                             ("CONFIGURATION", String(repeating: "a", count: 257))] {
            var invalid = identityBuildContext; invalid[key] = value
            XCTAssertThrowsError(try DuelNetworkRulesManifest(data: identityManifest(build: invalid)))
        }
        var missing = identityBuildContext; missing.removeValue(forKey: "SWIFT_VERSION")
        XCTAssertThrowsError(try DuelNetworkRulesManifest(data: identityManifest(build: missing)))
    }

    func testNetworkIdentityDigestMatchesPythonLengthFramingVector() {
        let files = [DuelNetworkContentRecord(path: "Sources/ShiftCore/DuelGame.swift", bytes: 3,
                                              sha256: DuelNetworkContentRecord.digest(Data("abc".utf8)))]
        XCTAssertEqual(DuelNetworkContentRecord.fingerprint(files, recipe: DuelNetworkRulesManifest.recipe),
                       "8ef062dbd8f73824c5187478e4b9f4b2a437cbdb9369d4d631337bb4f6be5a7d")
        XCTAssertEqual(DuelNetworkContentRecord.fingerprint(files, recipe: DuelNetworkRulesManifest.recipe,
                                                           context: ["mode": "xcode", "TARGET_NAME": "ShiftReminder"]),
                       "bec0e4cab282b0353e4166fe90e4b44f895dfe3cd24f7b242759c4e2887fe476")
        XCTAssertNotEqual(DuelNetworkContentRecord.fingerprint(files, recipe: DuelNetworkRulesManifest.recipe),
                          DuelNetworkContentRecord.fingerprint(files, recipe: DuelNetworkCompatibilityIdentity.contentRecipe))
    }

    func testNetworkIdentityContentFingerprintBindsCompleteCatalogAndResources() throws {
        func receipt(_ name: String, _ text: String) -> DuelNetworkContentRecord {
            let bytes = Data(text.utf8)
            return .init(path: name, bytes: bytes.count, sha256: DuelNetworkContentRecord.digest(bytes))
        }
        let catalog = receipt("catalog/SF3_DistinctFighters.json", "{\"schemaVersion\":1,\"profiles\":[\"sun_katana\",\"liu_hammers\"],\"clock\":30,\"tracks\":[1],\"comboLinks\":[]}")
        let model = receipt("characters/fixture.glb", "synthetic-model-1")
        let original = [catalog, model]
        let digest = DuelNetworkContentRecord.fingerprint(original, recipe: DuelNetworkCompatibilityIdentity.contentRecipe)
        let catalogMutation = receipt(catalog.path, "{\"schemaVersion\":1,\"profiles\":[\"sun_katana\",\"liu_hammers\"],\"clock\":30,\"tracks\":[2],\"comboLinks\":[]}")
        XCTAssertNotEqual(digest, DuelNetworkContentRecord.fingerprint([catalogMutation, model], recipe: DuelNetworkCompatibilityIdentity.contentRecipe))
        XCTAssertNotEqual(digest, DuelNetworkContentRecord.fingerprint([catalog, receipt(model.path, "synthetic-model-2")], recipe: DuelNetworkCompatibilityIdentity.contentRecipe))
        XCTAssertNotEqual(digest, DuelNetworkContentRecord.fingerprint([catalog], recipe: DuelNetworkCompatibilityIdentity.contentRecipe))
    }

    func testNetworkIdentityExplicitMissingOrCorruptContentNeverFallsBack() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rules = try DuelNetworkRulesManifest(data: identityManifest())
        let stage = directory.appendingPathComponent("SF3_Palace_Exterior.glb")
        let clocks = DuelWorldView.activeClocks
        XCTAssertThrowsError(try DuelNetworkCompatibilityIdentity.verify(rules: rules, directory: directory, stageURL: stage))
        let catalog = directory.appendingPathComponent("SF3_DistinctFighters.json")
        try Data("{\"profiles\":[\"sun_katana\",\"liu_hammers\"]}".utf8).write(to: catalog)
        XCTAssertThrowsError(try DuelNetworkCompatibilityIdentity.verify(rules: rules, directory: directory, stageURL: stage))
        try FileManager.default.removeItem(at: catalog)
        let target = directory.appendingPathComponent("target.json")
        try Data("fake".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: catalog, withDestinationURL: target)
        XCTAssertThrowsError(try DuelNetworkCompatibilityIdentity.verify(rules: rules, directory: directory, stageURL: stage))
        XCTAssertEqual(DuelWorldView.activeClocks, clocks)
    }

    func testNetworkIdentityBuildHookInstallsValidRulesAndNoFallbackIdentity() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: DuelNetworkRulesManifest.resourceName, withExtension: "json"),
                                "Main app post-build phase must regenerate and install the rules manifest")
        let rules = try DuelNetworkRulesManifest(data: Data(contentsOf: url))
        XCTAssertEqual(rules.build["TARGET_NAME"], "ShiftReminder")
        XCTAssertTrue(rules.files.contains { $0.path == "App/AppStore+Duty.swift" })
        XCTAssertTrue(rules.files.contains { $0.path == "project.yml" })
        if DuelWeaponAssets.catalogURL() == nil {
            XCTAssertThrowsError(try DuelNetworkCompatibilityIdentity.verify()) { error in
                XCTAssertEqual(error as? DuelNetworkCompatibilityIdentity.Failure, .missingCatalog)
            }
        }
    }

    func testNetworkIdentityVerifiesCompleteInstalledPrivateContentWithoutStartingClock() throws {
        guard DuelWeaponAssets.catalogURL() != nil else { throw XCTSkip("Private fighter resources are not installed") }
        let clocks = DuelWorldView.activeClocks
        let value = try DuelNetworkCompatibilityIdentity.verify()
        XCTAssertEqual(value.catalog.profiles.count, 2)
        XCTAssertEqual(value.verifiedFiles.count, 62)
        XCTAssertEqual(Set(value.verifiedFiles.map(\.path)).count, value.verifiedFiles.count)
        XCTAssertEqual(value.verifiedFiles.filter { $0.path.hasPrefix("controls/") }.count, 7)
        XCTAssertEqual(value.verifiedFiles.filter { $0.path.hasPrefix("stage/") }.map(\.path), ["stage/SF3_Palace_Exterior.glb"])
        XCTAssertTrue(DuelNetworkContentRecord.validDigest(value.compatibility.rulesFingerprint))
        XCTAssertTrue(DuelNetworkContentRecord.validDigest(value.compatibility.catalogFingerprint))
        XCTAssertEqual(value.compatibility.selectionProtocolVersion, DuelMultiplayerSelection.protocolVersion)
        XCTAssertEqual(value.compatibility.inputProtocolVersion, DuelNetworkInputs.protocolVersion)
        XCTAssertEqual(DuelWorldView.activeClocks, clocks)
    }
}
