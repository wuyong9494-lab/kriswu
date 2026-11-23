import Foundation
import XCTest
@testable import ShiftCore

final class TenderShareInboxTests: XCTestCase {
    private static let pdf = Data("%PDF-1.4\n% synthetic inbox fixture\n%%EOF".utf8)
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSeparateInstancesShareOneLocalAtomicPackage() throws {
        try withTemporaryDirectory { root in
            let folder = root.appendingPathComponent("Inbox")
            let extensionInbox = TenderShareInbox(directory: folder)
            let appInbox = TenderShareInbox(directory: folder)
            let item = try extensionInbox.save(data: Self.pdf, filename: "../out/投标\u{202e}资料.PDF", now: Self.now)
            XCTAssertEqual(item.filename, "投标资料.pdf")
            XCTAssertEqual(item.byteCount, Self.pdf.count)
            XCTAssertEqual(try appInbox.items(now: Self.now), [item])
            XCTAssertEqual(try appInbox.read(item, now: Self.now), Self.pdf)
            let package = folder.appendingPathComponent(item.id.uuidString.lowercased())
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [item.id.uuidString.lowercased()])
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: package.path)), ["metadata.json", "source.pdf"])
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("out").path))
        }
    }

    func testReadsBoundedProviderURLAndRejectsSymlink() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("original.pdf")
            let alias = root.appendingPathComponent("alias.pdf")
            try Self.pdf.write(to: source)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
            let inbox = TenderShareInbox(directory: root.appendingPathComponent("Inbox"))
            XCTAssertThrowsError(try inbox.save(fileURL: alias, now: Self.now)) {
                XCTAssertEqual($0 as? TenderShareInbox.Failure, .invalidDocument)
            }
            let item = try inbox.save(fileURL: source, filename: "网页附件.pdf", now: Self.now)
            XCTAssertEqual(item.filename, "网页附件.pdf")
            XCTAssertEqual(try inbox.read(item, now: Self.now), Self.pdf)
            XCTAssertEqual(try Data(contentsOf: source), Self.pdf)
        }
    }

    func testWordPackageRequiresActualDocxContainer() throws {
        try withTemporaryDirectory { root in
            let inbox = TenderShareInbox(directory: root.appendingPathComponent("Inbox"))
            let validWord = try TenderDOCXExporter.make(
                title: "合成招标文件", sections: [.init(title: "条款", body: "申报资料根据实际填写。")], reviewNotes: []
            )
            let item = try inbox.save(data: validWord, filename: "需求.docx", now: Self.now)
            XCTAssertEqual(try inbox.read(item, now: Self.now), validWord)
            XCTAssertThrowsError(try inbox.save(data: Data([0x50, 0x4B, 0x03, 0x04]), filename: "伪造.DOCX")) {
                XCTAssertEqual($0 as? TenderShareInbox.Failure, .invalidDocument)
            }
            XCTAssertThrowsError(try inbox.save(data: Self.pdf, filename: "伪造.docx")) {
                XCTAssertEqual($0 as? TenderShareInbox.Failure, .invalidDocument)
            }
            XCTAssertThrowsError(try inbox.save(data: validWord, filename: "脚本.docm")) {
                XCTAssertEqual($0 as? TenderShareInbox.Failure, .invalidDocument)
            }
        }
    }

    func testSizeLimitAndNoPartialEntry() throws {
        try withTemporaryDirectory { root in
            let folder = root.appendingPathComponent("Inbox")
            let inbox = TenderShareInbox(directory: folder)
            let tooLarge = Data(repeating: 0, count: TenderShareInbox.maxFileBytes + 1)
            XCTAssertThrowsError(try inbox.save(data: tooLarge, filename: "超限.pdf")) {
                XCTAssertEqual($0 as? TenderShareInbox.Failure, .tooLarge)
            }
            let local = root.appendingPathComponent("override.pdf")
            try tooLarge.write(to: local)
            XCTAssertThrowsError(try inbox.save(fileURL: local)) {
                XCTAssertEqual($0 as? TenderShareInbox.Failure, .tooLarge)
            }
            XCTAssertTrue(try inbox.items(now: Self.now).isEmpty)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        }
    }

    func testExpiresOnAccessAndDeletesIndividualPackagesInStableOrder() throws {
        try withTemporaryDirectory { root in
            let inbox = TenderShareInbox(directory: root.appendingPathComponent("Inbox"))
            let older = try inbox.save(data: Self.pdf, filename: "较早.pdf", now: Self.now)
            let newer = try inbox.save(data: Self.pdf, filename: "较晚.pdf", now: Self.now + 60)
            XCTAssertEqual(try inbox.items(now: Self.now + 90), [newer, older])
            let later = Self.now + TenderShareInbox.expirationInterval
            XCTAssertThrowsError(try inbox.read(older, now: later)) {
                XCTAssertEqual($0 as? TenderShareInbox.Failure, .noLongerAvailable)
            }
            XCTAssertEqual(try inbox.items(now: later), [newer])
            try inbox.delete(newer)
            try inbox.delete(newer) // Concurrent removal or a repeated action is safe.
            XCTAssertTrue(try inbox.items(now: later).isEmpty)
        }
    }

    func testDisallowsSymlinkedPayloadAndPackageAndDoesNotDeleteOutside() throws {
        try withTemporaryDirectory { root in
            let folder = root.appendingPathComponent("Inbox")
            let inbox = TenderShareInbox(directory: folder)
            let outside = root.appendingPathComponent("Outside", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            let safeFile = outside.appendingPathComponent("do-not-touch.pdf")
            try Self.pdf.write(to: safeFile)
            let item = try inbox.save(data: Self.pdf, filename: "待处理.pdf", now: Self.now)
            let package = folder.appendingPathComponent(item.id.uuidString.lowercased())
            let local = package.appendingPathComponent("source.pdf")
            try FileManager.default.removeItem(at: local)
            try FileManager.default.createSymbolicLink(at: local, withDestinationURL: safeFile)
            XCTAssertTrue(try inbox.items(now: Self.now).isEmpty)
            XCTAssertThrowsError(try inbox.read(item, now: Self.now))
            try inbox.delete(item)
            XCTAssertEqual(try Data(contentsOf: safeFile), Self.pdf)

            try FileManager.default.createSymbolicLink(at: package, withDestinationURL: outside)
            XCTAssertTrue(try inbox.items(now: Self.now).isEmpty)
            XCTAssertThrowsError(try inbox.delete(item))
            XCTAssertEqual(try Data(contentsOf: safeFile), Self.pdf)
        }
    }

    func testInboxCapAllowsReusingSlotAfterDelete() throws {
        try withTemporaryDirectory { root in
            let inbox = TenderShareInbox(directory: root.appendingPathComponent("Inbox"))
            var items: [TenderShareInbox.Item] = []
            for n in 0..<TenderShareInbox.maxInboxItems {
                items.append(try inbox.save(data: Self.pdf, filename: "文件\(n).pdf", now: Self.now))
            }
            XCTAssertThrowsError(try inbox.save(data: Self.pdf, filename: "超限.pdf", now: Self.now)) {
                XCTAssertEqual($0 as? TenderShareInbox.Failure, .storageFull)
            }
            try inbox.delete(items[0])
            _ = try inbox.save(data: Self.pdf, filename: "空位.pdf", now: Self.now)
            XCTAssertEqual(try inbox.items(now: Self.now).count, TenderShareInbox.maxInboxItems)
        }
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
}
