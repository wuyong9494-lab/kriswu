import XCTest
@testable import ShiftCore

final class PassPlanPassLayoutTests: XCTestCase {
    private let headers = ["卫星名称", "地面站", "数传开始时间", "状态"]
    private let centers = [0.15, 0.35, 0.65, 0.9]

    private func line(_ texts: [String], y: Double, xs: [Double]? = nil) -> [PassPlan.TextBox] {
        zip(texts, xs ?? centers).map { text, x in
            .init(text: text, x: x - 0.03, y: y, width: 0.06, height: 0.016)
        }
    }

    private func body(_ count: Int = 1, xs: [Double]? = nil) -> [PassPlan.TextBox] {
        (0..<count).flatMap { index in
            line(["虚构卫星\(index)", "甲站-01", "2032-06-18 08:\(String(format: "%02d", index)):00", "等待数传"],
                 y: 0.22 + Double(index) * 0.08, xs: xs)
        }
    }

    private var layout: PassPlan.Layout {
        .init(slots: zip(headers, centers).map { .init(label: $0.0, column: PassPlan.column(forHeader: $0.0), x: $0.1) })
    }

    func testMissingHeaderPassUsesCurrentPageLayoutAndKeepsItsOwnRows() {
        let complete = line(headers, y: 0.12) + body()
        let missing = body(3)
        XCTAssertTrue(PassPlan.read(missing).rows.isEmpty)
        let result = PassPlan.readPasses([complete, missing])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map { $0.rows.count }, [1, 3])
        XCTAssertNotNil(result[0].header)
        XCTAssertNil(result[1].header, "借用布局不能伪造原图表头")
        XCTAssertEqual(result[1].rows.map(\.satellite), ["虚构卫星0", "虚构卫星1", "虚构卫星2"])
        XCTAssertEqual(result[1].layout, result[0].layout)
    }

    func testCurrentPageHeaderOverridesPreviousPagePositions() {
        let stale = PassPlan.Layout(slots: zip(headers, [0.05, 0.15, 0.35, 0.65]).map {
            .init(label: $0.0, column: PassPlan.column(forHeader: $0.0), x: $0.1)
        })
        let complete = line(headers, y: 0.12) + body()
        let result = PassPlan.readPasses([body(2), complete], fallback: stale)
        XCTAssertEqual(result[0].rows.count, 2)
        XCTAssertEqual(result[0].layout, result[1].layout)
        XCTAssertNotEqual(result[0].layout, stale)
        XCTAssertNil(result[0].header)
    }

    func testAllPassesWithoutHeaderCanStillUsePreviousPage() {
        let result = PassPlan.readPasses([body(), body(2)], fallback: layout)
        XCTAssertEqual(result.map { $0.rows.count }, [1, 2])
        XCTAssertTrue(result.allSatisfy { $0.layout == layout && $0.header == nil })
    }

    func testEachRecognizedHeaderKeepsItsOwnLayoutAndHeader() {
        let shifted = [0.12, 0.32, 0.62, 0.87]
        let first = line(headers, y: 0.1) + body()
        let second = line(headers, y: 0.12, xs: shifted) + body(2, xs: shifted)
        let original = [PassPlan.read(first), PassPlan.read(second)]
        XCTAssertEqual(PassPlan.readPasses([first, second]), original)
        XCTAssertNotEqual(original[0].layout, original[1].layout)
    }

    func testBestCurrentPageLayoutIsChosenAndTiesUseOriginalPassOrder() {
        let shifted = [0.12, 0.32, 0.62, 0.87]
        let sparse = line(headers, y: 0.1) + body()
        let dense = line(headers, y: 0.12, xs: shifted) + body(2, xs: shifted)
        let result = PassPlan.readPasses([sparse, dense, body(2, xs: shifted)])
        XCTAssertEqual(result[2].layout, result[1].layout)
        let tied = line(headers, y: 0.12, xs: shifted) + body(1, xs: shifted)
        let tie = PassPlan.readPasses([sparse, tied, body()])
        XCTAssertEqual(tie[2].layout, tie[0].layout)
    }

    func testNoHeaderAndNoPreviousLayoutDoesNotInventPlans() {
        let result = PassPlan.readPasses([body(), [], body(2)])
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy { $0.rows.isEmpty && $0.layout == nil && $0.header == nil })
        XCTAssertTrue(PassPlan.readPasses([]).isEmpty)
    }

    func testFileColumnNumbersAndInvalidPositionsCannotBeShared() {
        let file = PassPlan.Layout(slots: layout.slots.enumerated().map {
            .init(label: $0.element.label, column: $0.element.column, x: Double($0.offset))
        })
        var invalid = layout
        invalid.slots[0].x = .nan
        var duplicate = layout
        duplicate.slots[0].x = duplicate.slots[1].x
        for bad in [file, invalid, duplicate, .init(slots: [])] {
            let result = PassPlan.readPasses([body()], fallback: bad)
            XCTAssertTrue(result[0].rows.isEmpty)
            XCTAssertNil(result[0].layout)
        }
    }

    func testHeaderOnlyPassCanRecoverAnotherPassWithoutLosingItsHeader() {
        let headerOnly = line(headers, y: 0.12)
        let result = PassPlan.readPasses([headerOnly, body(2)])
        XCTAssertNotNil(result[0].header)
        XCTAssertTrue(result[0].rows.isEmpty)
        XCTAssertEqual(result[1].rows.count, 2)
        XCTAssertNil(result[1].header)
    }

    private func tiltedDenseBoxes(slope: Double) -> (header: [PassPlan.TextBox], body: [PassPlan.TextBox]) {
        func tiltedLine(_ text: [String], y: Double) -> [PassPlan.TextBox] {
            zip(text, centers).map { value, x in
                .init(text: value, x: x - 0.025, y: y + slope * x - 0.006, width: 0.05, height: 0.012)
            }
        }
        let header = tiltedLine(headers, y: 0.12)
        let body = (0..<7).flatMap { i in
            tiltedLine(["虚构卫星\(i)", "甲站-0\(i)", "2032-06-18 08:0\(i):00", i % 2 == 0 ? "等待数传" : "已发送站"],
                       y: 0.24 + Double(i) * 0.035)
        }
        return (header, body)
    }

    func testBorrowedHeaderSlopePreservesDenseTiltedRowsAndEveryField() throws {
        for slope in [0.14, -0.14, 0.18, -0.18] {
            let sample = tiltedDenseBoxes(slope: slope)
            let result = PassPlan.readPasses([sample.header, sample.body])
            let header = try XCTUnwrap(result[0].header)
            XCTAssertEqual(header.slope, slope, accuracy: 0.000_001)
            XCTAssertNil(result[1].header)
            XCTAssertEqual(result[1].rows.count, 7, "借头时必须带上本页斜率；只借 x 会错配密集行：\(slope)")
            XCTAssertEqual(result[1].rows.map(\.satellite), (0..<7).map { "虚构卫星\($0)" })
            XCTAssertEqual(result[1].rows.map(\.station), (0..<7).map { "甲站-0\($0)" })
            XCTAssertEqual(result[1].rows.map(\.start), (0..<7).map { "2032-06-18 08:0\($0):00" })
            XCTAssertEqual(result[1].rows.map(\.status), (0..<7).map { $0 % 2 == 0 ? "等待数传" : "已发送站" })
        }
    }

    func testCurrentPageSlopeIsUsedEvenWhenPreviousLayoutHasSameXPositions() throws {
        let sample = tiltedDenseBoxes(slope: 0.16)
        let result = PassPlan.readPasses([sample.body, sample.header], fallback: layout)
        XCTAssertEqual(result[0].rows.count, 7)
        XCTAssertEqual(result[0].rows.map(\.start), (0..<7).map { "2032-06-18 08:0\($0):00" })
        XCTAssertNil(result[0].header)
        XCTAssertEqual(try XCTUnwrap(result[1].header).slope, 0.16, accuracy: 0.000_001)
    }
}
