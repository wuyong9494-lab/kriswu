import CryptoKit
import Foundation
import XCTest
@testable import ShiftReminder

/// Small synthetic documents test the signed-build trust boundary. No GLB,
/// source-game assets, media, or accepted Pangu release is loaded by these tests.
@MainActor
final class DuelFighterAssetReleaseLoaderTests: XCTestCase {
    private typealias Loader = DuelFighterAssetReleaseLoader
    private typealias Release = DuelFighterAssetRelease

    private func withDirectory(_ body: @MainActor (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("synthetic-release-loader-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func bundle(in root: URL, pin: String? = nil) throws -> Bundle {
        let identifier = UUID().uuidString.lowercased()
        let url = root.appendingPathComponent("Synthetic_" + identifier + ".bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var info: [String: Any] = [
            "CFBundleIdentifier": "com.synthetic.fighter-release." + identifier,
            "CFBundleName": "SyntheticReleaseTests",
            "CFBundleVersion": "1",
            "CFBundlePackageType": "BNDL"
        ]
        if let pin { info[Release.infoKey] = pin }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Info.plist"))
        let value = try XCTUnwrap(Bundle(url: url))
        XCTAssertEqual(value.object(forInfoDictionaryKey: Release.infoKey) as? String, pin,
                       "Each isolated test bundle must expose exactly its authored build pin")
        return value
    }

    /// Decodable as a release, but intentionally not a complete catalog. The
    /// tests using it must fail at file integrity before catalog interpretation.
    private func manifest(catalogName: String = "SF3_DistinctFighters.json",
                          catalogBytes: Int = 2, catalogHash: String) throws -> Data {
        let placeholder = String(repeating: "e", count: 64)
        let value: [String: Any] = [
            "schemaVersion": 1,
            "id": "synthetic-loader-boundary-only",
            "catalog": ["name": catalogName, "bytes": catalogBytes, "sha256": catalogHash],
            "sourceTrails": ["name": "Synthetic_Trails.json", "bytes": 1, "sha256": placeholder],
            "panguAudio": ["name": "Synthetic_Audio.json", "bytes": 1, "sha256": placeholder],
            "profiles": []
        ]
        return try JSONSerialization.data(withJSONObject: value, options: .sortedKeys)
    }

    private func assertFailure<T>(_ expected: Loader.Failure, _ message: String = "",
                                  file: StaticString = #filePath, line: UInt = #line,
                                  operation: () throws -> T) {
        XCTAssertThrowsError(try operation(), message, file: file, line: line) {
            XCTAssertEqual($0 as? Loader.Failure, expected, message, file: file, line: line)
        }
    }

    func testNoBuildPinAndNoManifestLeavesOptionalReleaseAbsent() throws {
        try withDirectory { root in
            let unsigned = try bundle(in: root)
            XCTAssertNil(try Loader.optional(directory: root, bundle: unsigned))
        }
    }

    func testPresentManifestCannotAuthorizeItselfWithoutBuildPin() throws {
        try withDirectory { root in
            let bytes = Data("{\"synthetic\":true}".utf8)
            try bytes.write(to: root.appendingPathComponent(Release.fileName))
            let unsigned = try bundle(in: root)
            assertFailure(.missingPin) {
                try Loader.optional(directory: root, bundle: unsigned)
            }
        }
    }

    func testEmptyBuildPinOnlyPermitsAnAbsentManifest() throws {
        try withDirectory { root in
            let unsigned = try bundle(in: root, pin: "")
            XCTAssertNil(try Loader.optional(directory: root, bundle: unsigned))
            try Data("{}".utf8).write(to: root.appendingPathComponent(Release.fileName))
            assertFailure(.missingPin) {
                try Loader.optional(directory: root, bundle: unsigned)
            }
        }
    }

    func testMalformedBuildPinsFailBeforeLookingForManifest() throws {
        try withDirectory { root in
            for pin in [String(repeating: "g", count: 64), String(repeating: "A", count: 64),
                        String(repeating: "a", count: 63), String(repeating: "a", count: 65),
                        String(repeating: "a", count: 63) + "\n"] {
                let invalid = try bundle(in: root, pin: pin)
                assertFailure(.invalidPin, pin) {
                    try Loader.optional(directory: root, bundle: invalid)
                }
                assertFailure(.invalidPin, "The explicit native-test seam must enforce the same pin format") {
                    try Loader(directory: root, expectedSHA256: pin)
                }
            }
        }
    }

    func testValidBuildPinRequiresTheManifestToExist() throws {
        try withDirectory { root in
            let pinned = try bundle(in: root, pin: String(repeating: "a", count: 64))
            assertFailure(.missingRelease) {
                try Loader.optional(directory: root, bundle: pinned)
            }
        }
    }

    func testChangedManifestBytesCannotPassTheOriginalBuildPin() throws {
        try withDirectory { root in
            let original = Data("{\"synthetic\":1}".utf8)
            let altered = Data("{\"synthetic\":2}".utf8)
            XCTAssertEqual(original.count, altered.count, "This must exercise the hash, not a size difference")
            try altered.write(to: root.appendingPathComponent(Release.fileName))
            let pinned = try bundle(in: root, pin: digest(original))
            assertFailure(.integrity(Release.fileName)) {
                try Loader.optional(directory: root, bundle: pinned)
            }
        }
    }

    func testManifestSymlinkIsRejectedEvenWhenTargetBytesMatchThePin() throws {
        try withDirectory { root in
            let bytes = Data("{\"synthetic\":true}".utf8)
            let target = root.appendingPathComponent("Synthetic_Manifest_Target.json")
            try bytes.write(to: target)
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent(Release.fileName), withDestinationURL: target)
            let pinned = try bundle(in: root, pin: digest(bytes))
            assertFailure(.integrity(Release.fileName)) {
                try Loader.optional(directory: root, bundle: pinned)
            }
        }
    }

    func testEmptyAndOversizedManifestsAreRejectedBeforeDecoding() throws {
        try withDirectory { root in
            for bytes in [Data(), Data(repeating: 32, count: Release.maximumBytes + 1)] {
                try bytes.write(to: root.appendingPathComponent(Release.fileName))
                let pinned = try bundle(in: root, pin: digest(bytes))
                assertFailure(.integrity(Release.fileName)) {
                    try Loader.optional(directory: root, bundle: pinned)
                }
            }
        }
    }

    func testUnsafeCatalogPathsFailBeforeAnyCatalogRead() throws {
        try withDirectory { root in
            for name in ["../catalog.json", "/tmp/catalog.json", "sub/catalog.json",
                         "sub\\catalog.json", ".catalog.json", "catalog.json\n"] {
                let bytes = try manifest(catalogName: name, catalogHash: digest(Data("{}".utf8)))
                try bytes.write(to: root.appendingPathComponent(Release.fileName))
                let pinned = try bundle(in: root, pin: digest(bytes))
                XCTAssertThrowsError(try Loader.optional(directory: root, bundle: pinned), name) { error in
                    XCTAssertEqual(error as? Release.Failure, .file,
                                   "Reject the path itself, rather than merely failing to find a file")
                }
            }
        }
    }

    func testUnapprovedCatalogBasenameIsRejectedEvenWithAValidReleasePin() throws {
        try withDirectory { root in
            let catalog = Data("{}".utf8)
            let wrongName = "Synthetic_Different_Catalog.json"
            try catalog.write(to: root.appendingPathComponent(wrongName))
            let bytes = try manifest(catalogName: wrongName, catalogHash: digest(catalog))
            try bytes.write(to: root.appendingPathComponent(Release.fileName))
            let pinned = try bundle(in: root, pin: digest(bytes))
            assertFailure(.integrity("catalog")) {
                try Loader.optional(directory: root, bundle: pinned)
            }
        }
    }

    func testCatalogHashAndDeclaredSizeAreCheckedBeforeCatalogDecoding() throws {
        try withDirectory { root in
            let catalogName = "SF3_DistinctFighters.json"
            let catalog = Data("{}".utf8)
            try catalog.write(to: root.appendingPathComponent(catalogName))
            let cases = [(catalog.count, String(repeating: "0", count: 64)),
                         (catalog.count + 1, digest(catalog))]
            for (count, hash) in cases {
                let bytes = try manifest(catalogBytes: count, catalogHash: hash)
                try bytes.write(to: root.appendingPathComponent(Release.fileName))
                let pinned = try bundle(in: root, pin: digest(bytes))
                assertFailure(.integrity(catalogName)) {
                    try Loader.optional(directory: root, bundle: pinned)
                }
            }
        }
    }

    func testVerifiedReadReturnsExactBytesAndRejectsSymlinkedCatalogs() throws {
        try withDirectory { root in
            let bytes = Data("{\"synthetic\":true}".utf8)
            let name = "Synthetic_Source.json"
            let source = root.appendingPathComponent(name)
            try bytes.write(to: source)
            let verified = try Loader.read(directory: root, name: name, maximum: bytes.count,
                                           bytes: bytes.count, hash: digest(bytes))
            XCTAssertEqual(verified, bytes)
            let alias = "SF3_DistinctFighters.json"
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(alias),
                                                       withDestinationURL: source)
            assertFailure(.integrity(alias)) {
                try Loader.read(directory: root, name: alias, maximum: bytes.count,
                                bytes: bytes.count, hash: digest(bytes))
            }
        }
    }
}
