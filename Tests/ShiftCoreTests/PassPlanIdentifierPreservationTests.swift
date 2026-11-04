import XCTest
@testable import ShiftCore

final class PassPlanIdentifierPreservationTests: XCTestCase {
    private let headers = ["卫星ID", "卫星名称", "地面站", "数传开始时间", "状态"]
    private let rules = [PassPlan.OperatorRule(name: "虚构甲", prefixes: ["虚构甲站"]),
                         PassPlan.OperatorRule(name: "虚构乙", prefixes: ["虚构乙站"])]
    private let values = [
        ["12AB34", "2024AB星", "虚构甲站-01", "2032-06-18 08:00:00", "等待数传"],
        ["0OO10", "3XA102C", "虚构乙站-01", "2032-06-18 09:00:00", "等待数传"],
        ["4243XB7", "00ABO0", "虚构甲站-02", "2032-06-18 10:00:00", "test"],
    ]

    private func assertPreserved(_ reading: PassPlan.Reading,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(reading.rows.map(\.satelliteID), values.map { $0[0] }, file: file, line: line)
        XCTAssertEqual(reading.rows.map(\.satellite), values.map { $0[1] }, file: file, line: line)
        XCTAssertEqual(reading.rows.map(\.cells), values, file: file, line: line)
        let groups = PassPlan.grouped(reading.rows, rules: rules)
        XCTAssertEqual(groups.map(\.name), ["虚构甲", "虚构乙"], file: file, line: line)
        XCTAssertEqual(groups.map { $0.rows.map(\.satelliteID) }, [["12AB34"], ["0OO10"]],
                       "按原站名分组，test 仍不发给任何运营商", file: file, line: line)
        for group in groups {
            let table = PassPlan.table(group.rows, layout: reading.layout)
            XCTAssertEqual(table.cells.map { $0[1] }, group.rows.map(\.satelliteID), file: file, line: line)
            XCTAssertEqual(table.cells.map { $0[2] }, group.rows.map(\.satellite), file: file, line: line)
        }
    }

    func testCSVPreservesLeadingDigitsAndDistinctLetterOAndZeroThroughExport() {
        let csv = ([headers] + values).map { $0.joined(separator: ",") }.joined(separator: "\n")
        let reading = PassPlan.readTable(MeetingTable.rows(csv, separator: ","))
        assertPreserved(reading)
    }

    func testExcelAndSystemPhotoTablesPreserveTheSameLiteralIdentifiers() {
        assertPreserved(PassPlan.readTable([headers] + values))
        assertPreserved(PassPlan.readPhotoTable([headers] + values))
    }

    func testPublicSyntheticPhotoBoxesPreserveIdentifiersAndKeepHumanReviewRequired() throws {
        func line(_ cells: [String], y: Double) -> [PassPlan.TextBox] {
            cells.enumerated().map { index, text in
                let center = Double(index + 1) / Double(headers.count + 1)
                return .init(text: text, x: center - 0.025, y: y, width: 0.05, height: 0.016)
            }
        }
        let boxes = line(headers, y: 0.12) + values.enumerated().flatMap { index, cells in
            line(cells, y: 0.22 + Double(index) * 0.1)
        }
        let reading = PassPlan.read(boxes)
        assertPreserved(reading)
        XCTAssertNotNil(reading.header)
        for row in reading.rows where !PassPlan.isExcludedFromSending(row) {
            XCTAssertNotNil(row.region)
            let reviewed = PassPlan.requiringPhotoIdentifierReview(row, column: .satelliteID)
            XCTAssertEqual(reviewed.satelliteID, row.satelliteID)
            XCTAssertEqual(reviewed.satellite, row.satellite)
            XCTAssertTrue(PassPlan.problems(reviewed, rules: rules, layout: reading.layout)
                .contains("照片中的卫星编号需对照原图确认"))
            XCTAssertEqual(PassPlan.confirmedRecognitionReview(reviewed), row)
        }
    }

    func testDifferentDigitPrefixesCannotCollapsePlanIdentityOrBorrowAnotherStation() throws {
        let reading = PassPlan.readTable([
            headers,
            ["12AB34", "同名示例星", "虚构甲站-01", "2032-06-18 08:00:00", "等待数传"],
            ["AB34", "同名示例星", "虚构甲站-01", "2032-06-18 08:00:00", "等待数传"],
        ])
        XCTAssertEqual(reading.rows.count, 2)
        let first = try XCTUnwrap(reading.rows.first)
        let second = try XCTUnwrap(reading.rows.last)
        let merged = PassPlan.merge([[first], [second]], layout: reading.layout)
        XCTAssertEqual(merged.map(\.satelliteID), ["12AB34", "AB34"], "不同编号不能因删前缀被跨页去重")
        let group = try XCTUnwrap(PassPlan.grouped(merged, rules: rules).first)
        XCTAssertEqual(group.rows.map(\.satelliteID), ["12AB34", "AB34"])

        var unknownStation = first
        unknownStation.station = "虚构申站-01"
        let adopted = PassPlan.adoptStations([unknownStation], from: [second], rules: rules)
        XCTAssertEqual(adopted[0].station, unknownStation.station, "编号不同不能借用另一个卫星的地面站")
        XCTAssertEqual(adopted[0].satelliteID, "12AB34")
    }
}
