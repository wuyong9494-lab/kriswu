import XCTest
@testable import ShiftCore

final class PassPlanHeaderRecognitionTests: XCTestCase {
    private enum PhotoInput: CaseIterable {
        case boxes, systemTable
    }

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

    private func photo(_ headers: [String], input: PhotoInput) -> PassPlan.Reading {
        switch input {
        case .boxes: return PassPlan.read(boxes(headers))
        case .systemTable: return PassPlan.readPhotoTable([headers, values(for: headers)])
        }
    }

    func testPhotoRecoversUniqueObservedOrbitHeaderAndPreservesLabelAndPosition() throws {
        for input in PhotoInput.allCases {
            for satelliteHeader in ["卫星名称", "卫星ID"] {
                let headers = ["No.", "圖号", satelliteHeader, "地面站", "数传开始时间", "状态"]
                let reading = photo(headers, input: input)
                let slot = try XCTUnwrap(reading.layout?.slots[1])
                XCTAssertEqual(slot.column, .orbit)
                XCTAssertEqual(slot.label, "圖号")
                XCTAssertEqual(slot.x, input == .boxes ? 2.0 / 7 : 1, accuracy: 0.000_001)
                XCTAssertEqual(reading.rows.map(\.orbit), ["808"])
                XCTAssertEqual(reading.rows.first?.cells[1], "808")
            }
        }
    }

    func testPhotoRecoveryRequiresEveryContextColumnInTheSameHeader() throws {
        let incomplete = [
            ["No.", "圖号", "地面站", "数传开始时间", "数传结束时间"],
            ["No.", "圖号", "卫星名称", "数传开始时间", "数传结束时间"],
            ["No.", "圖号", "卫星名称", "地面站", "数传结束时间"],
        ]
        for input in PhotoInput.allCases {
            for headers in incomplete {
                let reading = photo(headers, input: input)
                let layout = try XCTUnwrap(reading.layout)
                XCTAssertNil(layout.slots.first(where: { $0.label == "圖号" })?.column)
            }
        }
        var otherLine = boxes(incomplete[0])
        otherLine.append(.init(text: "卫星名称", x: 0.3, y: 0.7, width: 0.05, height: 0.016))
        let layout = try XCTUnwrap(PassPlan.read(otherLine).layout)
        XCTAssertNil(layout.slots.first(where: { $0.label == "圖号" })?.column,
                     "照片其他位置的卫星字样不能补足这一排表头的上下文")
        let otherRow = PassPlan.readPhotoTable([incomplete[0], values(for: incomplete[0]), ["卫星名称"]])
        XCTAssertNil(otherRow.layout?.slots.first(where: { $0.label == "圖号" })?.column,
                     "系统表格其他行的卫星字样也不能补足表头上下文")
    }

    func testPhotoRecoveryDoesNotChooseDuplicateCandidatesOrReplaceAnExistingOrbit() throws {
        for input in PhotoInput.allCases {
            let duplicate = ["No.", "圖号", "圖号", "卫星名称", "地面站", "数传开始时间"]
            let duplicates = try XCTUnwrap(photo(duplicate, input: input).layout)
            XCTAssertFalse(duplicates.columns.contains(.orbit))
            XCTAssertTrue(duplicates.slots.filter { $0.label == "圖号" }.allSatisfy { $0.column == nil })

            let existing = ["No.", "圈号", "圖号", "卫星名称", "地面站", "数传开始时间"]
            let reading = photo(existing, input: input)
            let layout = try XCTUnwrap(reading.layout)
            XCTAssertNil(layout.slots.first(where: { $0.label == "圖号" })?.column)
            XCTAssertEqual(layout.slots.filter { $0.column == .orbit }.count, 1)
            XCTAssertEqual(reading.rows.map(\.orbit), ["901"])
        }
    }

    func testPhotoDoesNotTreatOrdinaryDrawingNumberAsOrbit() throws {
        for input in PhotoInput.allCases {
            let headers = ["No.", "图号", "卫星名称", "地面站", "数传开始时间"]
            let reading = photo(headers, input: input)
            let layout = try XCTUnwrap(reading.layout)
            XCTAssertNil(layout.slots.first(where: { $0.label == "图号" })?.column)
            XCTAssertEqual(reading.rows.map(\.orbit), [""])
            XCTAssertEqual(reading.rows.first?.cells[1], "808")
        }
    }

    func testLiteralTableAndHeaderClassificationRemainUnchanged() throws {
        for label in ["圖号", "图号"] {
            XCTAssertNil(PassPlan.column(forHeader: label))
            let headers = ["No.", label, "卫星名称", "地面站", "数传开始时间"]
            let table = [headers, values(for: headers)]
            let reading = PassPlan.readTable(table)
            let layout = try XCTUnwrap(reading.layout)
            XCTAssertNil(layout.slots.first(where: { $0.label == label })?.column)
            XCTAssertEqual(reading.rows.map(\.orbit), [""])
            XCTAssertEqual(reading.rows.first?.cells[1], "808")
            XCTAssertEqual(PassPlan.rows(fromTable: table), reading.rows)
        }
    }

    func testSystemPhotoTablePreservesRawFieldsAndExcludesEmergencyTestRows() throws {
        let headers = ["", "No.", "圖 号", "卫星ID", "卫星名称", "地面站", "数传开始时间", "数传结束时间", "数传信息", "状态"]
        let excluded = ["应 急", "1", "8O8", "SAT-O0C-01", "匿名卫星A", "甲站-01",
                        "2032-06-18 08:00:00", "2032-06-18 08:06:00", "通道O:90CM", "T e S t"]
        let normal = ["", "2", "901", "LEGIT-C0O-02", "匿名卫星B", "甲站-02",
                      "2032-06-18 09:00:00", "2032-06-18 09:06:00", "通道C:900M", "等待数传"]
        let reading = PassPlan.readPhotoTable([headers, excluded, normal])
        let layout = try XCTUnwrap(reading.layout)
        XCTAssertEqual(layout.slots.map(\.label), Array(headers.dropFirst()))
        XCTAssertEqual(layout.slots[1].column, .orbit)
        XCTAssertEqual(layout.slots[1].x, 2, "空白标签列被移除后仍保留原表格列位置")
        XCTAssertEqual(reading.rows.map(\.cells), [Array(excluded.dropFirst()), Array(normal.dropFirst())])
        XCTAssertEqual(reading.rows.map(\.orbit), ["8O8", "901"], "只恢复表头含义，不替换 O/0/C 字符")
        XCTAssertEqual(reading.rows.map(\.satelliteID), ["SAT-O0C-01", "LEGIT-C0O-02"])
        XCTAssertEqual(reading.rows.map(\.status), ["T e S t", "等待数传"])
        XCTAssertEqual(reading.rows.map(\.emergencyBadge), [true, false])
        XCTAssertEqual(reading.rows.map { PassPlan.emergency($0, layout: layout) }, [true, false])
        XCTAssertEqual(reading.rows.map(PassPlan.isExcludedFromSending), [true, false], "test 仍优先于应急")
        XCTAssertEqual(PassPlan.sendableRows(reading.rows).map(\.satelliteID), ["LEGIT-C0O-02"])
        XCTAssertEqual(PassPlan.grouped(reading.rows, rules: [.init(name: "甲", prefixes: ["甲站"])])
            .flatMap(\.rows).map(\.satelliteID), ["LEGIT-C0O-02"])
    }
}
