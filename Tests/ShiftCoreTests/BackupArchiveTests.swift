import Foundation
import XCTest
@testable import ShiftCore

final class BackupArchiveTests: XCTestCase {
    private var emptyArchive: [String: Any] {
        ["version": 2, "settings": [String: Any](), "schedule": [String: String](),
         "covered": [String](), "roster": [String: [String: String]]()]
    }

    private func read(_ file: [String: Any]) throws -> BackupArchive {
        try BackupArchive(data: JSONSerialization.data(withJSONObject: file))
    }

    private func day(_ text: String) -> DayKey { DayKey(string: text)! }

    func testCurrentBackupKeepsScheduleCoverageRosterAndExtraSections() throws {
        var file = emptyArchive
        file["settings"] = ["aliases": ["张三"], "sourceURL": "https://example.invalid/schedule"]
        file["schedule"] = ["2026-11-04": "组A", "2026-11-06": "遥测"]
        file["covered"] = ["2026-11-04", "2026-11-05", "2026-11-06"]
        file["roster"] = ["张三": ["2026-11-04": "组A"], "李四": ["2026-11-06": "休"]]
        file["meeting"] = ["docURL": "https://example.invalid/meeting"]
        file["records"] = ["changeLog": [["date": "2026-11-04T08:00:00Z", "text": "组A → 组B"]]]

        let archive = try read(file)
        XCTAssertEqual(archive.version, 2)
        XCTAssertEqual(archive.schedule, [day("2026-11-04"): "组A", day("2026-11-06"): "遥测"])
        XCTAssertEqual(archive.covered, Set([day("2026-11-04"), day("2026-11-05"), day("2026-11-06")]))
        XCTAssertEqual(archive.roster["李四"], [day("2026-11-06"): "休"])
        XCTAssertEqual(archive.settings["aliases"] as? [String], ["张三"])
        XCTAssertEqual(archive.meeting?["docURL"] as? String, "https://example.invalid/meeting")
        XCTAssertEqual((archive.records?["changeLog"] as? [[String: String]])?.first?["text"], "组A → 组B")
    }

    func testLegitimateEmptyBackupIsAccepted() throws {
        let archive = try read(emptyArchive)
        XCTAssertTrue(archive.schedule.isEmpty)
        XCTAssertTrue(archive.covered.isEmpty)
        XCTAssertTrue(archive.roster.isEmpty)
        XCTAssertNil(archive.meeting)
        XCTAssertNil(archive.records)
    }

    func testLegacyBackupKeepsSettingsWithoutRequiringLaterSections() throws {
        for version in [nil, 1] as [Int?] {
            var file: [String: Any] = [
                "settings": ["aliases": ["张三"], "meetingDocURL": "https://example.invalid/meeting",
                             "taskHistory": ["2026-11-04": ["shift": "组A", "done": ["巡检"], "todo": [String]()]]],
                "schedule": ["2026-11-04": "组A", "2026-11-06": "遥测"],
            ]
            if let version { file["version"] = version }
            let archive = try read(file)
            XCTAssertEqual(archive.version, 1)
            XCTAssertEqual(archive.schedule[day("2026-11-04")], "组A")
            XCTAssertEqual(archive.covered, Set(archive.schedule.keys))
            XCTAssertFalse(archive.covered.contains(day("2026-11-05")), "旧备份不能凭空补出已取得的空班日")
            XCTAssertTrue(archive.roster.isEmpty)
            XCTAssertEqual(archive.settings["meetingDocURL"] as? String, "https://example.invalid/meeting")
            XCTAssertNotNil(archive.settings["taskHistory"], "留给 App 的旧字段迁移，不能在校验时丢掉")
        }
    }

    func testSettingsOnlyFileCannotEraseExistingSchedule() throws {
        XCTAssertThrowsError(try read(["settings": [String: Any]()])) {
            XCTAssertEqual($0 as? BackupArchive.ReadError, .missingField("schedule"))
        }
    }

    func testCurrentBackupRequiresEveryCoreSection() throws {
        for field in ["settings", "schedule", "covered", "roster"] {
            var file = emptyArchive
            file.removeValue(forKey: field)
            XCTAssertThrowsError(try read(file), field) {
                XCTAssertEqual($0 as? BackupArchive.ReadError, .missingField(field))
            }
        }
    }

    func testWrongCoreSectionTypesAreRejectedInsteadOfBecomingEmpty() throws {
        for field in ["settings", "schedule", "covered", "roster"] {
            for badValue in ["损坏", NSNull(), 42] as [Any] {
                var file = emptyArchive
                file[field] = badValue
                XCTAssertThrowsError(try read(file), field) {
                    XCTAssertEqual($0 as? BackupArchive.ReadError, .invalidField(field))
                }
            }
        }
        var file = emptyArchive
        file["schedule"] = ["2026-11-04": 42]
        XCTAssertThrowsError(try read(file)) {
            XCTAssertEqual($0 as? BackupArchive.ReadError, .invalidField("schedule.2026-11-04"))
        }
        file = emptyArchive
        file["roster"] = ["张三": "损坏"]
        XCTAssertThrowsError(try read(file)) {
            XCTAssertEqual($0 as? BackupArchive.ReadError, .invalidField("roster.张三"))
        }
        file["roster"] = ["张三": ["2026-11-04": false]]
        XCTAssertThrowsError(try read(file)) {
            XCTAssertEqual($0 as? BackupArchive.ReadError, .invalidField("roster.张三.2026-11-04"))
        }
    }

    func testInvalidDatesRejectTheWholeBackupInsteadOfDroppingEntries() throws {
        let badDate = "2026-02-30"
        var file = emptyArchive
        file["schedule"] = ["2026-11-04": "组A", badDate: "遥测"]
        XCTAssertThrowsError(try read(file)) {
            XCTAssertEqual($0 as? BackupArchive.ReadError, .invalidDate(field: "schedule", value: badDate))
        }
        file = emptyArchive
        file["covered"] = ["2026-11-04", badDate]
        XCTAssertThrowsError(try read(file)) {
            XCTAssertEqual($0 as? BackupArchive.ReadError, .invalidDate(field: "covered", value: badDate))
        }
        file = emptyArchive
        file["roster"] = ["张三": ["2026-11-04": "组A", badDate: "遥测"]]
        XCTAssertThrowsError(try read(file)) {
            XCTAssertEqual($0 as? BackupArchive.ReadError, .invalidDate(field: "roster.张三", value: badDate))
        }
    }

    func testMalformedDateKeysAreRejected() throws {
        for badDate in ["2026--11-04", "2026-X-11-04", "2026-13-04"] {
            var file = emptyArchive
            file["schedule"] = ["2026-11-04": "组A", badDate: "遥测"]
            XCTAssertThrowsError(try read(file), badDate) {
                XCTAssertEqual($0 as? BackupArchive.ReadError, .invalidDate(field: "schedule", value: badDate))
            }
        }
    }

    func testUnpaddedLegacyDatesAreNormalized() throws {
        var file = emptyArchive
        file["schedule"] = ["2026-1-2": "组A"]
        file["covered"] = ["2026-1-2"]
        file["roster"] = ["张三": ["2026-1-2": "组A"]]
        let archive = try read(file)
        XCTAssertEqual(archive.schedule, [day("2026-01-02"): "组A"])
        XCTAssertEqual(archive.covered, Set([day("2026-01-02")]))
        XCTAssertEqual(archive.roster["张三"], [day("2026-01-02"): "组A"])
    }

    func testDifferentKeysForTheSameDayAreRejectedInsteadOfOverwritten() throws {
        var file = emptyArchive
        file["schedule"] = ["2026-11-04": "组A", "2026-11-4": "遥测"]
        XCTAssertThrowsError(try read(file)) {
            XCTAssertEqual($0 as? BackupArchive.ReadError, .duplicateDate(field: "schedule", value: "2026-11-04"))
        }
        file = emptyArchive
        file["roster"] = ["张三": ["2026-11-04": "组A", "2026-11-4": "遥测"]]
        XCTAssertThrowsError(try read(file)) {
            XCTAssertEqual($0 as? BackupArchive.ReadError, .duplicateDate(field: "roster.张三", value: "2026-11-04"))
        }
    }

    func testOptionalSectionsAllowAbsenceOrNullButRejectWrongTypes() throws {
        for field in ["meeting", "records"] {
            var file = emptyArchive
            file[field] = NSNull()
            _ = try read(file)
            file[field] = [String]()
            XCTAssertThrowsError(try read(file), field) {
                XCTAssertEqual($0 as? BackupArchive.ReadError, .invalidField(field))
            }
        }
    }

    func testLegacyOptionalSectionsAreValidatedWhenPresent() throws {
        var file: [String: Any] = ["version": 1, "settings": [String: Any](), "schedule": [String: String](),
                                  "covered": ["不是日期"]]
        XCTAssertThrowsError(try read(file))
        file.removeValue(forKey: "covered")
        file["roster"] = ["张三": ["2026-11-04": 42]]
        XCTAssertThrowsError(try read(file))
    }

    func testInvalidAndUnsupportedVersionsAreRejected() throws {
        for version in [0, -1, 3] {
            var file = emptyArchive
            file["version"] = version
            XCTAssertThrowsError(try read(file)) {
                XCTAssertEqual($0 as? BackupArchive.ReadError, .unsupportedVersion(version))
            }
        }
        for version in [true, "2", 2.5, NSNull()] as [Any] {
            var file = emptyArchive
            file["version"] = version
            XCTAssertThrowsError(try read(file)) {
                XCTAssertEqual($0 as? BackupArchive.ReadError, .invalidField("version"))
            }
        }
    }

    func testNonObjectAndDamagedJSONAreRejected() {
        for json in ["[]", "null", "{", "不是 JSON"] {
            XCTAssertThrowsError(try BackupArchive(data: Data(json.utf8))) {
                XCTAssertEqual($0 as? BackupArchive.ReadError, .invalidFile)
            }
        }
    }
}
