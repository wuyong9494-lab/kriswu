import XCTest
@testable import ShiftCore

final class PassPlanFieldMergeTests: XCTestCase {
    private let rules = [PassPlan.OperatorRule(name: "虚构甲", prefixes: ["虚构甲站"])]
    private let layout = PassPlan.Layout(slots: [
        .init(label: "卫星ID", column: .satelliteID, x: 0.08),
        .init(label: "卫星名称", column: .satellite, x: 0.18),
        .init(label: "地面站", column: .station, x: 0.28),
        .init(label: "开始时间", column: .start, x: 0.40),
        .init(label: "结束时间", column: .end, x: 0.54),
        .init(label: "圈号", column: .orbit, x: 0.66),
        .init(label: "数传信息", column: .info, x: 0.76),
        .init(label: "状态", column: .status, x: 0.84),
        .init(label: "是否应急", column: nil, x: 0.91),
        .init(label: "备注", column: nil, x: 0.97),
    ])

    private func row(_ changes: [PassPlan.Column: String] = [:], y: Double = 0.2,
                     emergency: String = "不是", note: String = "原始备注") -> PassPlanRow {
        let values: [PassPlan.Column: String] = [
            .satelliteID: "DEMO0A01", .satellite: "虚构01星", .station: "虚构甲站-01",
            .start: "2032-06-18 08:00:00", .end: "2032-06-18 08:07:00",
            .orbit: "12345", .info: "通道1:800M", .status: "等待数传",
        ].merging(changes) { _, new in new }
        let cells = layout.slots.map { slot in
            slot.column.flatMap { values[$0] } ?? (slot.label == "是否应急" ? emergency : note)
        }
        return PassPlanRow(orbit: values[.orbit]!, satelliteID: values[.satelliteID]!,
            satellite: values[.satellite]!, station: values[.station]!, start: values[.start]!, end: values[.end]!,
            info: values[.info]!, status: values[.status]!, cells: cells,
            region: .init(y0: y, slope: 0, height: 0.04, left: 0, right: 1))
    }

    private func combine(_ first: PassPlanRow, _ other: PassPlanRow,
                         otherLayout: PassPlan.Layout? = nil) -> PassPlanRow {
        // A fuller page wins the page score even when this particular row has
        // a damaged cell. This is the real trigger for whole-row replacement.
        let base = PassPlan.Reading(rows: [first, row(y: 0.5), row(y: 0.7)], layout: layout)
        let source = otherLayout ?? layout
        let alternate = PassPlan.Reading(rows: PassPlan.remap([other], from: layout, to: source), layout: source)
        let reading = PassPlan.combine([base, alternate], rules: rules)
        XCTAssertEqual(reading.rows.count, 3)
        return reading.rows[0]
    }

    func testStationRepairCannotReplaceCompleteTimesNameOrbitAndPayload() {
        let first = row([.station: "虚构申站-01"])
        let other = row([.satellite: "虚构0I星", .start: "2032-06-18 08:04:00",
                         .end: "2032-06-18 08:09:00", .orbit: "12346", .info: "通道1:900M"])
        let result = combine(first, other)
        XCTAssertEqual(result.station, other.station)
        XCTAssertEqual(result.satelliteID, first.satelliteID)
        XCTAssertEqual(result.satellite, first.satellite)
        XCTAssertEqual(result.start, first.start)
        XCTAssertEqual(result.end, first.end)
        XCTAssertEqual(result.orbit, first.orbit)
        XCTAssertEqual(result.info, first.info)
        var expected = first.cells; expected[2] = other.cells[2]
        XCTAssertEqual(result.cells, expected)
        for label in ["开始时间", "结束时间", "卫星名称", "圈号", "数传信息"] {
            XCTAssertTrue(result.recognitionIssues?.contains("\(label)多次识别不一致，请核对原图") == true)
        }
    }

    func testComplementaryReadsRepairMalformedCellsWithoutLosingCompleteOnes() {
        let first = row([.start: "2032-06-18 08:OO:00", .orbit: "12O45", .info: ""])
        let other = row([.satelliteID: "", .end: "2032-06-18 08:07:OO"])
        let result = combine(first, other)
        XCTAssertEqual(result.start, other.start)
        XCTAssertEqual(result.orbit, other.orbit)
        XCTAssertEqual(result.info, other.info)
        XCTAssertEqual(result.end, first.end)
        XCTAssertEqual(result.satelliteID, first.satelliteID)
        XCTAssertEqual(result.cells, row().cells)
        let reviewed = PassPlan.requiringPhotoIdentifierReview(result, column: .satelliteID)
        XCTAssertTrue(PassPlan.problems(reviewed, rules: rules, layout: layout)
            .contains("照片中的卫星编号需对照原图确认"))
    }

    func testRepairsUseRemappedCellsAndKeepUnknownColumnsAndExportInSync() {
        let first = row([.station: "虚构申站-01", .orbit: ""])
        let other = row([.start: "2032-06-18 08:01:00"], note: "另一轮备注")
        let result = combine(first, other, otherLayout: .init(slots: Array(layout.slots.reversed())))
        var expected = first.cells
        expected[2] = other.station; expected[5] = other.orbit
        XCTAssertEqual(result.cells, expected)
        let exported = PassPlan.table([result], layout: layout)
        XCTAssertEqual(Array(exported.cells[0].dropFirst()), expected)
        XCTAssertEqual(result.start, first.start)
        XCTAssertEqual(result.region, first.region)
    }

    func testConflictingLiteralIdentifiersCannotBorrowFieldsFromAnotherSatellite() {
        let first = row([.satelliteID: "0OO10", .station: "虚构申站-01", .orbit: ""])
        let other = row([.satelliteID: "OOO10"])
        let result = combine(first, other)
        XCTAssertEqual(result.satelliteID, "0OO10")
        XCTAssertEqual(result.station, first.station)
        XCTAssertEqual(result.orbit, first.orbit)
        XCTAssertEqual(result.cells, first.cells)
        XCTAssertTrue(result.recognitionIssues?.contains("卫星编号多次识别不一致，请核对原图") == true)
    }

    func testTimeRepairsCannotCreateANewImpossibleInterval() {
        let first = row([.start: "2032-06-18 08:OO:00"])
        let other = row([.start: "2032-06-18 09:00:00", .end: "2032-06-18 09:07:00"])
        let result = combine(first, other)
        XCTAssertEqual(result.start, first.start)
        XCTAssertEqual(result.end, first.end)
        XCTAssertTrue(PassPlan.problems(result, rules: rules, layout: layout).contains("开始时间没认全"))
    }

    func testTestExclusionAndEmergencyEvidenceSurviveFieldRepairs() {
        let first = row([.station: "虚构申站-01", .orbit: ""])
        var other = row([.end: "2032-06-18 08:07:OO", .status: "t e s t"], emergency: "是")
        other.emergencyBadge = true
        let result = combine(first, other)
        XCTAssertEqual(result.station, other.station)
        XCTAssertEqual(result.orbit, other.orbit)
        XCTAssertEqual(result.end, first.end)
        XCTAssertTrue(PassPlan.isExcludedFromSending(result))
        XCTAssertTrue(PassPlan.sendableRows([result]).isEmpty)
        XCTAssertTrue(PassPlan.grouped([result], rules: rules).isEmpty)
        XCTAssertEqual(PassPlan.emergency(result, layout: layout), true)
        XCTAssertTrue(result.recognitionIssues?.contains("状态（含 test，已排除发送）多次识别不一致，请核对原图") == true)
    }
}
