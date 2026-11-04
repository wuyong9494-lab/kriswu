import XCTest
@testable import ShiftCore

final class PassPlanRequiredFieldsTests: XCTestCase {
    private let rules = [PassPlan.OperatorRule(name: "虚构甲", prefixes: ["虚构甲站"])]

    private func layout(_ required: [PassPlan.Column]) -> PassPlan.Layout {
        let columns = required + [.satellite, .station, .start, .end, .status]
        return .init(slots: columns.enumerated().map { index, column in
            .init(label: column.rawValue, column: column, x: Double(index + 1) / Double(columns.count + 1))
        })
    }

    private func row() -> PassPlanRow {
        PassPlanRow(satellite: "匿名卫星A", station: "虚构甲站-01",
                    start: "2032-06-18 08:00:00", end: "2032-06-18 08:06:00", status: "等待数传",
                    region: .init(y0: 0.3, slope: 0, height: 0.05, left: 0, right: 1))
    }

    func testRecognizedColumnsRequireTheirMissingValues() {
        let candidate = row()
        XCTAssertEqual(PassPlan.problems(candidate, rules: rules, layout: layout([.orbit, .satelliteID])),
                       ["没认出圈号", "没认出卫星编号"])
        XCTAssertEqual(candidate.orbit, "")
        XCTAssertEqual(candidate.satelliteID, "", "检查不能补造字段")
    }

    func testEachRequiredFieldIsCheckedIndependently() {
        var candidate = row()
        candidate.orbit = "808"
        XCTAssertEqual(PassPlan.problems(candidate, rules: rules, layout: layout([.orbit, .satelliteID])),
                       ["没认出卫星编号"])
        candidate.orbit = ""
        candidate.satelliteID = "SAT-C01"
        XCTAssertEqual(PassPlan.problems(candidate, rules: rules, layout: layout([.orbit, .satelliteID])),
                       ["没认出圈号"])
    }

    func testAbsentColumnsAndLegacyNilLayoutDoNotInventRequiredFields() {
        let candidate = row()
        XCTAssertTrue(PassPlan.problems(candidate, rules: rules, layout: layout([])).isEmpty)
        XCTAssertTrue(PassPlan.problems(candidate, rules: rules).isEmpty)
        XCTAssertEqual(PassPlan.problems(candidate, rules: rules, layout: layout([.orbit])), ["没认出圈号"])
        XCTAssertEqual(PassPlan.problems(candidate, rules: rules, layout: layout([.satelliteID])), ["没认出卫星编号"])
    }

    func testWhitespaceOnlyValuesCountAsMissingInRecognizedColumns() {
        var candidate = row()
        candidate.orbit = " \t\n　"
        candidate.satelliteID = "\r\n\t　 "
        XCTAssertEqual(PassPlan.problems(candidate, rules: rules, layout: layout([.orbit, .satelliteID])),
                       ["没认出圈号", "没认出卫星编号"], "空白圈号应提示缺失，不同时声称是有内容的非数字值")
        XCTAssertEqual(PassPlan.problems(candidate, rules: rules), ["圈号不全是数字"],
                       "没有已识别布局时保持旧版检查行为")
    }

    func testCompleteValuesDoNotAddSatelliteIDFormatGuesses() {
        for id in ["SAT-C01", "C0", "0", "编号甲", "SAT-002"] {
            var candidate = row()
            candidate.orbit = "00808"
            candidate.satelliteID = id
            XCTAssertTrue(PassPlan.problems(candidate, rules: rules, layout: layout([.orbit, .satelliteID])).isEmpty, id)
            XCTAssertEqual(candidate.satelliteID, id)
        }
    }

    func testColumnMeaningMustActuallyBeRecognized() {
        var unknown = layout([])
        unknown.slots.append(.init(label: "圈号", column: nil, x: 0.8))
        unknown.slots.append(.init(label: "卫星ID", column: nil, x: 0.9))
        XCTAssertTrue(PassPlan.problems(row(), rules: rules, layout: unknown).isEmpty,
                      "没有识别出的列含义时，不能只凭显示标签新增必填项")
        unknown.slots[unknown.slots.count - 2].column = .orbit
        unknown.slots[unknown.slots.count - 2].label = "圖号"
        XCTAssertEqual(PassPlan.problems(row(), rules: rules, layout: unknown), ["没认出圈号"],
                       "照片表头恢复后的明确列含义也要检查缺值")
    }

    func testExistingNonNumericOrbitCheckStillAppliesWithOrWithoutLayout() {
        var candidate = row()
        candidate.orbit = "8C8"
        candidate.satelliteID = "SAT-C01"
        for columns in [layout([.orbit, .satelliteID]), layout([])] {
            XCTAssertEqual(PassPlan.problems(candidate, rules: rules, layout: columns), ["圈号不全是数字"])
        }
        XCTAssertEqual(PassPlan.problems(candidate, rules: rules), ["圈号不全是数字"])
    }

    func testMissingFieldsAndEarlierOCRWarningsSurviveAnotherPass() throws {
        let columns = layout([.orbit, .satelliteID])
        let previous = "卫星名称多次识别不一致，请核对原图"
        var marked = row()
        marked.recognitionIssues = [previous]
        let combined = PassPlan.combine([
            .init(rows: [row()], layout: columns), .init(rows: [marked], layout: columns),
        ], rules: rules)
        var kept = try XCTUnwrap(combined.rows.first)
        XCTAssertEqual(combined.rows.count, 1)
        XCTAssertEqual(PassPlan.problems(kept, rules: rules, layout: combined.layout),
                       ["没认出圈号", "没认出卫星编号", previous])
        kept.orbit = "808"
        kept.satelliteID = "SAT-001"
        XCTAssertEqual(PassPlan.problems(kept, rules: rules, layout: combined.layout), [previous],
                       "补齐字段可解除缺值提示，但不能顺便抹掉其他 OCR 冲突")
    }
}
