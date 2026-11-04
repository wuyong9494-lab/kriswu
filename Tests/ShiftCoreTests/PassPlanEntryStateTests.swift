import XCTest
@testable import ShiftCore

final class PassPlanEntryStateTests: XCTestCase {
    private func reading(_ identifier: String) -> PassPlan.Reading {
        .init(rows: [.init(satelliteID: identifier, station: "示例站-01", start: "2032-06-18 08:00:00")], layout: nil)
    }

    func testReturningFromSettingsPreservesEditedRowsAndSentOperators() {
        let imported = reading("SAT-001")
        var entry = PassPlanEntryState()
        var current = entry.consume(initial: imported, autoScan: false).reading!
        var sent: Set<String> = []
        current.rows[0].satelliteID = "已核对-O-01"
        sent.insert("示例运营商")

        if let repeated = entry.consume(initial: imported, autoScan: false).reading {
            current = repeated
            sent = []
        }
        XCTAssertEqual(current.rows[0].satelliteID, "已核对-O-01")
        XCTAssertEqual(sent, ["示例运营商"])
    }

    func testReturningAfterScanningDoesNotRestoreTheOriginalImportedPlan() {
        let imported = reading("SAT-001")
        var entry = PassPlanEntryState()
        XCTAssertEqual(entry.consume(initial: imported, autoScan: false).reading, imported)
        var current = reading("新拍的-SAT-002")

        if let repeated = entry.consume(initial: imported, autoScan: false).reading { current = repeated }
        XCTAssertEqual(current, reading("新拍的-SAT-002"))
    }

    func testChangedIncomingSourceIsAcceptedAndThenConsumed() {
        var entry = PassPlanEntryState()
        _ = entry.consume(initial: reading("SAT-001"), autoScan: false)
        let next = reading("SAT-002")
        XCTAssertEqual(entry.consume(initial: next, autoScan: false).reading, next)
        XCTAssertNil(entry.consume(initial: next, autoScan: false).reading)
    }

    func testNilSeparatesTwoNewImportsWithIdenticalContents() {
        var entry = PassPlanEntryState()
        let imported = reading("SAT-001")
        XCTAssertEqual(entry.consume(initial: imported, autoScan: false).reading, imported)
        XCTAssertNil(entry.consume(initial: nil, autoScan: false).reading)
        XCTAssertEqual(entry.consume(initial: imported, autoScan: false).reading, imported)
    }

    func testEmptyEntryDoesNotReplaceTheCurrentSessionOrPreventLaterImport() {
        var entry = PassPlanEntryState()
        XCTAssertNil(entry.consume(initial: nil, autoScan: false).reading)
        XCTAssertNil(entry.consume(initial: .init(rows: [], layout: nil), autoScan: false).reading)
        XCTAssertEqual(entry.consume(initial: reading("SAT-001"), autoScan: false).reading, reading("SAT-001"))
    }

    func testAutomaticScanStartsOnceWithoutAnInitialPlan() {
        var entry = PassPlanEntryState()
        let first = entry.consume(initial: nil, autoScan: true)
        XCTAssertNil(first.reading)
        XCTAssertTrue(first.autoScan)
        XCTAssertFalse(entry.consume(initial: nil, autoScan: true).autoScan)
        XCTAssertFalse(entry.consume(initial: reading("SAT-001"), autoScan: true).autoScan,
                       "入口计划变化不能重复弹出同一次扫描请求")
    }

    func testLaterAutomaticScanRequestIsIndependentOfImportConsumption() {
        var entry = PassPlanEntryState()
        let imported = reading("SAT-001")
        XCTAssertEqual(entry.consume(initial: imported, autoScan: false).reading, imported)
        let requested = entry.consume(initial: imported, autoScan: true)
        XCTAssertNil(requested.reading)
        XCTAssertTrue(requested.autoScan)
        XCTAssertFalse(entry.consume(initial: imported, autoScan: true).autoScan)
        XCTAssertFalse(entry.consume(initial: imported, autoScan: false).autoScan)
        XCTAssertTrue(entry.consume(initial: imported, autoScan: true).autoScan)
    }
}
