import XCTest
@testable import ShiftCore

final class PassPlanEndTimeRereadTests: XCTestCase {
    private let layout = PassPlan.Layout(slots: [
        .init(label: "卫星ID", column: .satelliteID, x: 0.1),
        .init(label: "卫星名称", column: .satellite, x: 0.2),
        .init(label: "圈号", column: .orbit, x: 0.3),
        .init(label: "地面站", column: .station, x: 0.4),
        .init(label: "开始时间", column: .start, x: 0.5),
        .init(label: "结束时间", column: .end, x: 0.6),
        .init(label: "数传信息", column: .info, x: 0.7),
        .init(label: "状态", column: .status, x: 0.8),
        .init(label: "备注", column: nil, x: 0.9),
    ])
    private let firstEnd = "2032-06-18 08:30:03"
    private let secondEnd = "2032-06-18 08:29:39"

    private func row(end: String = "2032-06-18 08:30:03", y: Double = 0.2) -> PassPlanRow {
        let cells = ["DEMO02B03", "虚构02B03星", "12345", "虚构甲站-01",
                     "2032-06-18 08:23:45", end, "通道1:800M", "等待数传", "保留备注"]
        return .init(orbit: cells[2], satelliteID: cells[0], satellite: cells[1], station: cells[3],
                     start: cells[4], end: end, info: cells[6], status: cells[7], cells: cells,
                     region: .init(y0: y, slope: 0, height: 0.04, left: 0, right: 1))
    }
    private func reading(_ rows: [PassPlanRow]) -> PassPlan.Reading { .init(rows: rows, layout: layout) }

    func testTwoFullReadingsProduceConflictingEndCandidatesAfterColumnRemapping() {
        let first = row(), second = row(end: secondEnd)
        let reversed = PassPlan.Layout(slots: Array(layout.slots.reversed()))
        let source = PassPlan.Reading(rows: PassPlan.remap([second], from: layout, to: reversed), layout: reversed)
        let candidates = PassPlan.endTimeRereadCandidates(reading([first]), from: [reading([first]), source])
        XCTAssertEqual(candidates, [0: [secondEnd, firstEnd]])
        XCTAssertTrue(PassPlan.endTimeRereadCandidates(reading([first]), from: [reading([first])]).isEmpty)
        XCTAssertTrue(PassPlan.endTimeRereadCandidates(reading([first]), from: [reading([first]), reading([first])]).isEmpty)
    }

    func testDifferentDatesStationsOrbitsAndLiteralIdentifiersCannotSupplyCandidates() {
        let first = row()
        for field in [PassPlan.Column.start, .station, .orbit, .satelliteID] {
            var other = row(end: secondEnd)
            switch field {
            case .start: other.start = "2032-06-17 08:23:45"; other.cells[4] = other.start
            case .station: other.station = "虚构甲站-02"; other.cells[3] = other.station
            case .orbit: other.orbit = "12346"; other.cells[2] = other.orbit
            case .satelliteID: other.satelliteID = "DEMO02BO3"; other.cells[0] = other.satelliteID
            default: XCTFail("unexpected test field")
            }
            XCTAssertTrue(PassPlan.endTimeRereadCandidates(reading([first]),
                from: [reading([first]), reading([other])]).isEmpty, field.rawValue)
        }
    }

    func testDuplicateOrAmbiguousRowsAndDifferentPagesCannotBecomeConfirmation() {
        let first = row(), second = row(end: secondEnd)
        for rows in [[first, second], [second, second]] {
            XCTAssertTrue(PassPlan.endTimeRereadCandidates(reading([first]),
                from: [reading([first]), reading(rows)]).isEmpty)
        }
        let adjacent = row(y: 0.21)
        XCTAssertTrue(PassPlan.endTimeRereadCandidates(reading([first, adjacent]),
            from: [reading([first]), reading([row(end: secondEnd, y: 0.205)])]).isEmpty)
        var anotherPage = second; anotherPage.region?.page = 1
        XCTAssertTrue(PassPlan.endTimeRereadCandidates(reading([first]),
            from: [reading([first]), reading([anotherPage])]).isEmpty)
    }

    func testCellConfirmationChangesOnlyEndAndItsRawCellAndKeepsAllReviewEvidence() {
        var first = row()
        first.recognitionIssues = ["结束时间多次识别不一致，请核对原图", "保留已有疑项"]
        first.emergencyBadge = true
        let raw = "2032/06/18 08:29:39"
        let result = PassPlan.reviewEndTimeReread(first, candidates: [firstEnd, secondEnd], reread: raw, layout: layout)
        var expected = first
        expected.end = secondEnd; expected.cells[5] = raw; expected.recognitionIssues = result.recognitionIssues
        XCTAssertEqual(result, expected)
        XCTAssertEqual(result.recognitionIssues?.prefix(2), first.recognitionIssues?.prefix(2))
        XCTAssertTrue(result.recognitionIssues?.contains("结束时间由原格复识与多轮候选核对，请核对原图") == true)
        let exported = PassPlan.table([result], layout: layout)
        XCTAssertEqual(exported.headers, ["No.", "应急", "卫星ID", "卫星名称", "圈号", "地面站",
                                          "开始时间", "结束时间", "数传信息", "状态", "备注"])
        XCTAssertEqual(exported.cells, [["1", "应急", "DEMO02B03", "虚构02B03星", "12345", "虚构甲站-01",
                                          "2032-06-18 08:23:45", "2032-06-18 08:29:39",
                                          "通道1:800M", "等待数传", "保留备注"]])
        XCTAssertEqual(PassPlan.emergency(result, layout: layout), true)
    }

    func testNovelOrPartialCellTextCannotOverrideAnExistingCandidate() {
        let first = row()
        let candidates = [firstEnd, secondEnd]
        for raw in ["", "08:29:39", "2032-06-18 08:29", "2032-06-18 08:29:3O",
                    "2032-02-30 08:29:39", "2032-06-18 08:20:00", "extra " + secondEnd] {
            XCTAssertEqual(PassPlan.reviewEndTimeReread(first, candidates: candidates, reread: raw, layout: layout), first, raw)
        }
        let novel = PassPlan.reviewEndTimeReread(first, candidates: candidates,
                                               reread: "2032-06-18 08:31:17", layout: layout)
        XCTAssertEqual(novel.end, first.end)
        XCTAssertEqual(novel.cells, first.cells)
        XCTAssertTrue(novel.recognitionIssues?.contains("结束时间原格复识与多轮候选不一致，请核对原图") == true)
    }

    func testMissingSecondsCannotBeConfirmedByAnInventedZero() {
        let first = row()
        XCTAssertEqual(PassPlan.reviewEndTimeReread(first,
            candidates: [firstEnd, "2032-06-18 08:29:00"], reread: "2032-06-18 08:29", layout: layout), first)
    }

    func testCrossMidnightFullDatesArePreservedWithoutInferringTheDay() {
        var first = row(end: "2032-06-19 00:10:03")
        first.start = "2032-06-18 23:58:45"; first.cells[4] = first.start
        let end = "2032-06-19 00:09:39"
        let result = PassPlan.reviewEndTimeReread(first, candidates: [first.end, end], reread: end, layout: layout)
        XCTAssertEqual(result.start, first.start)
        XCTAssertEqual(result.end, end)
        XCTAssertEqual(PassPlan.reviewEndTimeReread(first, candidates: [first.end, end],
                                                   reread: "2032-06-18 00:09:39", layout: layout), first)
    }

    func testTestRecordsAndInvalidLayoutsRemainUnchanged() {
        var first = row(); first.testStatusDetected = true
        XCTAssertTrue(PassPlan.endTimeRereadCandidates(reading([first]),
            from: [reading([row()]), reading([row(end: secondEnd)])]).isEmpty)
        XCTAssertEqual(PassPlan.reviewEndTimeReread(first, candidates: [firstEnd, secondEnd],
                                                   reread: secondEnd, layout: layout), first)
        XCTAssertTrue(PassPlan.sendableRows([first]).isEmpty)
        for malformed in [PassPlan.Layout(slots: layout.slots.filter { $0.column != .end }),
                          .init(slots: layout.slots + [layout.slots[5]])] {
            XCTAssertEqual(PassPlan.reviewEndTimeReread(row(), candidates: [firstEnd, secondEnd],
                                                       reread: secondEnd, layout: malformed), row())
        }
        var truncated = row(); truncated.cells.removeLast()
        XCTAssertEqual(PassPlan.reviewEndTimeReread(truncated, candidates: [firstEnd, secondEnd],
                                                   reread: secondEnd, layout: layout), truncated)
    }
}
