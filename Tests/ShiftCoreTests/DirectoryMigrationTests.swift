import Foundation
import XCTest
@testable import ShiftCore

final class DirectoryMigrationTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func write(_ text: String, to directory: URL, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: directory.appendingPathComponent(name))
    }

    func testMovesIndexAndAttachmentsTogetherIntoMissingOrEmptyDestination() throws {
        for existingEmptyDestination in [false, true] {
            let root = try temporaryDirectory()
            let source = root.appendingPathComponent("source")
            let target = root.appendingPathComponent("target")
            try write("index", to: source, name: "记录.json")
            try write("photo", to: source, name: "photo.jpg")
            if existingEmptyDestination {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            }
            try DirectoryMigration.move(from: source, to: target)
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("记录.json")), Data("index".utf8))
            XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("photo.jpg")), Data("photo".utf8))
        }
    }

    func testConflictingIndexPreservesBothDirectoriesAndEveryAttachment() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source")
        let target = root.appendingPathComponent("target")
        try write("current index", to: source, name: "记录.json")
        try write("current photo", to: source, name: "photo.jpg")
        try write("older index", to: target, name: "记录.json")
        try write("older audio", to: target, name: "audio.m4a")

        XCTAssertThrowsError(try DirectoryMigration.move(from: source, to: target))
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("记录.json")), Data("current index".utf8))
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("photo.jpg")), Data("current photo".utf8))
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("记录.json")), Data("older index".utf8))
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("audio.m4a")), Data("older audio".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("photo.jpg").path))
    }

    func testEmptyOldDirectoryDoesNotBlockThePopulatedCurrentLocation() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("empty-old-location")
        let target = root.appendingPathComponent("current-location")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try write("current index", to: target, name: "记录.json")
        try write("current photo", to: target, name: "photo.jpg")

        try DirectoryMigration.move(from: source, to: target)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("记录.json")), Data("current index".utf8))
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("photo.jpg")), Data("current photo".utf8))
    }

    func testPartialLegacyDestinationIsNotSilentlyMerged() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source")
        let target = root.appendingPathComponent("target")
        try write("index", to: source, name: "记录.json")
        try write("already moved attachment", to: target, name: "audio.m4a")

        XCTAssertThrowsError(try DirectoryMigration.move(from: source, to: target))
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("记录.json")), Data("index".utf8))
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("audio.m4a")), Data("already moved attachment".utf8))
    }

    func testDestinationCreationFailureLeavesSourceIntact() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source")
        try write("index", to: source, name: "记录.json")
        let parentFile = root.appendingPathComponent("not-a-directory")
        try Data("keep".utf8).write(to: parentFile)

        XCTAssertThrowsError(try DirectoryMigration.move(from: source, to: parentFile.appendingPathComponent("target")))
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent("记录.json")), Data("index".utf8))
        XCTAssertEqual(try Data(contentsOf: parentFile), Data("keep".utf8))
    }
}
