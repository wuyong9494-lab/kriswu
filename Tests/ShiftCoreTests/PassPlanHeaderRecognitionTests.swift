import XCTest
@testable import ShiftCore

final class PassPlanHeaderRecognitionTests: XCTestCase {
    private func values(for headers: [String]) -> [String] {
        headers.map { header in
            switch header {
            case "No.": return "1"
            case "圖号", "图号": return "808"
            case "圈号": return "901"
            case "卫星名称": return "匿名卫星A"
            case "卫星ID": return "SAT-ALPHA"
            case "地面站": return "甲站-01"
            case "数传开始时间": return "2032-06-18 08:00:00"
            case "数传结束时间": return "2032-06-18 08:06:00"
            default: return "等待数传"
            }
        }
    }

    private func boxes(_ headers: [String]) -> [PassPlan.TextBox] {
        func line(_ texts: [String], y: Double) -> [PassPlan.TextBox] {
            texts.enumerated().map { index, text in
                let center = Double(index + 1) / Double(headers.count + 1)
                return .init(text: text, x: center - 0.025, y: y, width: 0.05, height: 0.016)
            }
        }
        return line(headers, y: 0.12) + line(values(for: headers), y: 0.22)
    }

    func testPhotoRecoversUniqueObservedOrbitHeaderAndPreservesLabelAndPosition() throws {
        for satelliteHeader in ["卫星名称", "卫星ID"] {
            let headers = ["No.", "圖号", satelliteHeader, "地面站", "数传开始时间", "状态"]
            let reading = PassPlan.read(boxes(headers))
            let slot = try XCTUnwrap(reading.layout?.slots[1])
            XCTAssertEqual(slot.column, .orbit)
            XCTAssertEqual(slot.label, "圖号")
            XCTAssertEqual(slot.x, 2.0 / 7, accuracy: 0.000_001)
            XCTAssertEqual(reading.rows.map(\.orbit), ["808"])
            XCTAssertEqual(reading.rows.first?.cells[1], "808")
        }
    }

    func testPhotoRecoveryRequiresEveryContextColumnInTheSameHeader() throws {
        let incomplete = [
            ["No.", "圖号", "地面站", "数传开始时间", "数传结束时间"],
            ["No.", "圖号", "卫星名称", "数传开始时间", "数传结束时间"],
            ["No.", "圖号", "卫星名称", "地面站", "数传结束时间"],
        ]
        for headers in incomplete {
            let reading = PassPlan.read(boxes(headers))
            let layout = try XCTUnwrap(reading.layout)
            XCTAssertNil(layout.slots.first(where: { $0.label == "圖号" })?.column)
        }
        var otherLine = boxes(incomplete[0])
        otherLine.append(.init(text: "卫星名称", x: 0.3, y: 0.7, width: 0.05, height: 0.016))
        let layout = try XCTUnwrap(PassPlan.read(otherLine).layout)
        XCTAssertNil(layout.slots.first(where: { $0.label == "圖号" })?.column,
                     "照片其他位置的卫星字样不能补足这一排表头的上下文")
    }

    func testPhotoRecoveryDoesNotChooseDuplicateCandidatesOrReplaceAnExistingOrbit() throws {
        let duplicate = ["No.", "圖号", "圖号", "卫星名称", "地面站", "数传开始时间"]
        let duplicates = try XCTUnwrap(PassPlan.read(boxes(duplicate)).layout)
        XCTAssertFalse(duplicates.columns.contains(.orbit))
        XCTAssertTrue(duplicates.slots.filter { $0.label == "圖号" }.allSatisfy { $0.column == nil })

        let existing = ["No.", "圈号", "圖号", "卫星名称", "地面站", "数传开始时间"]
        let reading = PassPlan.read(boxes(existing))
        let layout = try XCTUnwrap(reading.layout)
        XCTAssertNil(layout.slots.first(where: { $0.label == "圖号" })?.column)
        XCTAssertEqual(layout.slots.filter { $0.column == .orbit }.count, 1)
        XCTAssertEqual(reading.rows.map(\.orbit), ["901"])
    }

    func testPhotoDoesNotTreatOrdinaryDrawingNumberAsOrbit() throws {
        let headers = ["No.", "图号", "卫星名称", "地面站", "数传开始时间"]
        let reading = PassPlan.read(boxes(headers))
        let layout = try XCTUnwrap(reading.layout)
        XCTAssertNil(layout.slots.first(where: { $0.label == "图号" })?.column)
        XCTAssertEqual(reading.rows.map(\.orbit), [""])
        XCTAssertEqual(reading.rows.first?.cells[1], "808")
    }

    func testLiteralTableAndHeaderClassificationRemainUnchanged() throws {
        for label in ["圖号", "图号"] {
            XCTAssertNil(PassPlan.column(forHeader: label))
            let headers = ["No.", label, "卫星名称", "地面站", "数传开始时间"]
            let reading = PassPlan.readTable([headers, values(for: headers)])
            let layout = try XCTUnwrap(reading.layout)
            XCTAssertNil(layout.slots.first(where: { $0.label == label })?.column)
            XCTAssertEqual(reading.rows.map(\.orbit), [""])
            XCTAssertEqual(reading.rows.first?.cells[1], "808")
        }
    }
}
