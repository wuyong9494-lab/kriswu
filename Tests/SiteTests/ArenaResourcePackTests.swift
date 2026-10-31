import CryptoKit
import Foundation
import XCTest
#if ARENA_RESOURCE_RUNTIME_TESTS
@testable import ArenaResourceRuntime
#else
@testable import ShiftReminder
#endif

final class ArenaResourcePackTests: XCTestCase {
    private func manifest(path: String = "source/note.txt", payload: Data,
                          kind: String = "notice", hash: String? = nil) -> [String: Any] {
        ["schemaVersion": 1, "id": "synthetic-resource-pack", "title": "Synthetic",
         "sourceDescription": "Generated test data only", "sourceSHA256": String(repeating: "0", count: 64),
         "files": [["path": path, "bytes": payload.count,
                    "sha256": hash ?? SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(), "kind": kind]],
         "heroes": [], "themes": [], "music": [], "musicBindings": [:], "maps": []]
    }

    private func pack(_ manifest: [String: Any], payload: Data, at url: URL, trailing: Data = Data()) throws {
        let raw = try JSONSerialization.data(withJSONObject: manifest, options: .sortedKeys)
        var bytes = ArenaResourcePackArchive.magic
        var count = UInt32(raw.count).littleEndian
        bytes.append(withUnsafeBytes(of: &count) { Data($0) })
        bytes.append(raw)
        bytes.append(payload)
        bytes.append(trailing)
        try bytes.write(to: url)
    }

    func testCorruptReplacementPreservesWorkingInstallation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input.arenapack")
        let destination = root.appendingPathComponent("installed")
        let valid = Data("previous working content".utf8)
        try pack(manifest(payload: valid), payload: valid, at: input)
        let old = try ArenaResourcePackArchive.install(from: input, directory: destination) { _ in }
        let pointerURL = destination.appendingPathComponent("active.json")
        let pointer = try Data(contentsOf: pointerURL)
        let replacement = Data("different broken content".utf8)
        try pack(manifest(payload: replacement, hash: String(repeating: "0", count: 64)), payload: replacement, at: input)
        XCTAssertThrowsError(try ArenaResourcePackArchive.install(from: input, directory: destination) { _ in })
        XCTAssertEqual(try Data(contentsOf: pointerURL), pointer)
        XCTAssertEqual(try Data(contentsOf: old.root.appendingPathComponent("source/note.txt")), valid)
        let folders = try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        XCTAssertEqual(folders.count, 1, "Failed staging folders must not be activated or retained")
    }

    func testPathsAndCaseCollisionsCannotOverwriteInstallerMetadata() throws {
        let payload = Data("synthetic".utf8)
        for path in ["../outside.txt", "/tmp/outside.txt", "folder/../../outside.txt", "manifest.json", "Manifest.JSON", "manifest.json/child.txt", "a\\b.txt", "a%2fb.txt"] {
            let kind = path.lowercased().hasSuffix(".json") ? "data" : "notice"
            let raw = try JSONSerialization.data(withJSONObject: manifest(path: path, payload: payload, kind: kind))
            let value = try JSONDecoder().decode(ArenaResourcePackManifest.self, from: raw)
            XCTAssertThrowsError(try value.validate(), path)
        }
        var collision = manifest(payload: payload)
        var files = try XCTUnwrap(collision["files"] as? [[String: Any]])
        var other = files[0]
        other["path"] = "SOURCE/NOTE.TXT"
        files.append(other)
        collision["files"] = files
        let raw = try JSONSerialization.data(withJSONObject: collision)
        XCTAssertThrowsError(try JSONDecoder().decode(ArenaResourcePackManifest.self, from: raw).validate())
        other["path"] = "source/note.txt/child.txt"
        collision["files"] = [other, files[0]]
        let prefix = try JSONSerialization.data(withJSONObject: collision)
        XCTAssertThrowsError(try JSONDecoder().decode(ArenaResourcePackManifest.self, from: prefix).validate())
    }

    func testDuplicateGLBJSONCannotChangeValidatedExternalReferences() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var chunks = Data()
        func chunk(_ data: Data, type: UInt32) {
            var padded = data
            while padded.count % 4 != 0 { padded.append(type == 0x4E4F534A ? 32 : 0) }
            for value in [UInt32(padded.count), type] {
                var word = value.littleEndian
                chunks.append(withUnsafeBytes(of: &word) { Data($0) })
            }
            chunks.append(padded)
        }
        let good: [String: Any] = ["asset": ["version": "2.0"], "buffers": [["byteLength": 4]]]
        let bad: [String: Any] = ["asset": ["version": "2.0"], "buffers": [["byteLength": 4, "uri": "../secret.bin"]]]
        chunk(try JSONSerialization.data(withJSONObject: good), type: 0x4E4F534A)
        chunk(try JSONSerialization.data(withJSONObject: bad), type: 0x4E4F534A)
        chunk(Data([0, 0, 0, 0]), type: 0x004E4942)
        var payload = Data("glTF".utf8)
        for value in [UInt32(2), UInt32(12 + chunks.count)] {
            var word = value.littleEndian
            payload.append(withUnsafeBytes(of: &word) { Data($0) })
        }
        payload.append(chunks)
        let url = root.appendingPathComponent("duplicate-json.arenapack")
        try pack(manifest(path: "models/duplicate.glb", payload: payload, kind: "model"), payload: payload, at: url)
        XCTAssertThrowsError(try ArenaResourcePackArchive.install(from: url, directory: root.appendingPathComponent("install")) { _ in })
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("install/active.json").path))
    }

    func testExternalGLBReferencesAreRejectedEvenWithValidPayloadHash() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let object: [String: Any] = ["asset": ["version": "2.0"], "buffers": [["uri": "../other.bin", "byteLength": 4]]]
        var json = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        while json.count % 4 != 0 { json.append(32) }
        var glb = Data("glTF".utf8)
        for value in [UInt32(2), UInt32(32 + json.count), UInt32(json.count), UInt32(0x4E4F534A)] {
            var word = value.littleEndian
            glb.append(withUnsafeBytes(of: &word) { Data($0) })
        }
        glb.append(json)
        for value in [UInt32(4), UInt32(0x004E4942)] {
            var word = value.littleEndian
            glb.append(withUnsafeBytes(of: &word) { Data($0) })
        }
        glb.append(Data([0, 0, 0, 0]))
        let url = root.appendingPathComponent("external.arenapack")
        try pack(manifest(path: "models/unsafe.glb", payload: glb, kind: "model"), payload: glb, at: url)
        XCTAssertThrowsError(try ArenaResourcePackArchive.install(from: url, directory: root.appendingPathComponent("install")) { _ in })
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("install/active.json").path))
    }

    func testTruncatedAndTrailingPayloadNeverCommit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = Data("complete payload".utf8)
        let url = root.appendingPathComponent("invalid.arenapack")
        let destination = root.appendingPathComponent("install")
        try pack(manifest(payload: expected), payload: Data(expected.dropLast()), at: url)
        XCTAssertThrowsError(try ArenaResourcePackArchive.install(from: url, directory: destination) { _ in })
        try pack(manifest(payload: expected), payload: expected, at: url, trailing: Data([42]))
        XCTAssertThrowsError(try ArenaResourcePackArchive.install(from: url, directory: destination) { _ in })
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("active.json").path))
    }
}
