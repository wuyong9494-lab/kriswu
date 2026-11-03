import XCTest
@testable import ShiftCore

/// 匿名、虚构的状态栏读数；验证补空和拒绝错行，不依赖 Vision 的输出造真值。
final class PassPlanStatusRereadTests: XCTestCase {
    private let layout = PassPlan.Layout(slots: [
        .init(label: "卫星", column: .satellite, x: 0.15),
        .init(label: "地面站", column: .station, x: 0.3),
        .init(label: "数传信息", column: .info, x: 0.55),
        .init(label: "状态", column: .status, x: 0.85),
    ])

    private func row(_ status: String = "", y: Double = 0.3, slope: Double = 0) -> PassPlanRow {
        .init(satellite: "虚构甲星", station: "甲站-01", start: "2032-06-18 08:00:00", status: status,
              cells: ["虚构甲星", "甲站-01", "虚构信息", status],
              region: .init(y0: y, slope: slope, height: 0.06, left: 0.05, right: 1))
    }

    private func box(_ text: String, x: Double = 0.85, y: Double = 0.3, slope: Double = 0,
                     width: Double = 0.10, height: Double = 0.02) -> PassPlan.TextBox {
        .init(text: text, x: x - width / 2, y: y + slope * x - height / 2, width: width, height: height)
    }

    private func reread(_ rows: [PassPlanRow], _ boxes: [PassPlan.TextBox]) -> [PassPlanRow] {
        let marked = PassPlan.applyingRowMarkers(rows, markers: boxes, layout: layout)
        return PassPlan.applyingStatusReread(marked, readings: boxes, layout: layout)
    }

    func testCompleteStatusWordsAndWhitespaceAreAcceptedWithoutGuessing() {
        for text in ["等待数传", "等 待\n数 传", "已发送站", "test", "Ｔ Ｅ Ｓ Ｔ"] {
            XCTAssertTrue(PassPlan.isRecognizedPlanStatus(text), text)
        }
        for text in ["等待", "等待数据", "已发送", "tost", "test 2", "contest", "应急", "状态", ""] {
            XCTAssertFalse(PassPlan.isRecognizedPlanStatus(text), text)
        }
    }

    func testFillsEachTiltedRowAndItsCorrespondingCell() {
        let result = reread([row(y: 0.3, slope: 0.06), row(y: 0.4, slope: 0.04)], [
            box("等 待\n数 传", y: 0.3, slope: 0.06), box("已发送站", y: 0.4, slope: 0.04),
        ])
        XCTAssertEqual(result.map(\.status), ["等待数传", "已发送站"])
        XCTAssertEqual(result.map { $0.cells.last }, ["等待数传", "已发送站"])
        XCTAssertTrue(result.allSatisfy { $0.recognitionIssues == nil && !PassPlan.isExcludedFromSending($0) })
    }

    func testInformationColumnAndBoxesSpillingAcrossColumnBoundaryAreIgnored() {
        let original = row()
        for reading in [box("等待数传", x: 0.55), box("已发送站", x: 0.72, width: 0.10),
                        box("等待数传", x: 0.99, width: 0.10)] {
            XCTAssertEqual(reread([original], [reading]), [original])
        }
    }

    func testNoStatusColumnOrFileCoordinateLayoutDoesNotFill() {
        let original = row()
        let noStatus = PassPlan.Layout(slots: Array(layout.slots.dropLast()))
        let fileLayout = PassPlan.Layout(slots: layout.slots.enumerated().map {
            .init(label: $0.element.label, column: $0.element.column, x: Double($0.offset))
        })
        for other in [noStatus, fileLayout] {
            XCTAssertEqual(PassPlan.applyingStatusReread([original], readings: [box("等待数传")], layout: other), [original])
        }
    }

    func testNonemptyOriginalStatusIsPreservedAndConflictsRequireReview() {
        let original = row("等待数传")
        let result = reread([original], [box("已发送站")])[0]
        XCTAssertEqual(result.status, original.status)
        XCTAssertEqual(result.cells, original.cells)
        XCTAssertTrue(result.recognitionIssues?.contains("状态补读与原识别不一致，请核对原图") == true)
        XCTAssertEqual(reread([original], [box("等 待 数 传")]), [original])
    }

    func testTestRemainsExcludedWhenOrdinaryStatusIsReread() {
        var retained = row("等待数传")
        retained.testStatusDetected = true
        var blankWithTestEvidence = row()
        blankWithTestEvidence.testStatusDetected = true
        for original in [row("test"), retained, blankWithTestEvidence] {
            let result = reread([original], [box("等待数传")])[0]
            XCTAssertEqual(result.status, original.status)
            XCTAssertEqual(result.cells, original.cells)
            XCTAssertTrue(PassPlan.isExcludedFromSending(result))
            XCTAssertTrue(result.recognitionIssues?.contains("状态识别不一致（含 test），已排除发送") == true)
        }
    }

    func testNewTestEvidenceWinsRegardlessOfMarkerOrder() {
        for readings in [[box("等待数传"), box("test")], [box("test"), box("等待数传")]] {
            let result = reread([row()], readings)[0]
            XCTAssertEqual(result.status, "test")
            XCTAssertTrue(PassPlan.isExcludedFromSending(result))
            XCTAssertTrue(PassPlan.sendableRows([result]).isEmpty)
        }
    }

    func testDifferentOrdinaryCandidatesDoNotChooseArbitrarily() {
        for readings in [[box("等待数传"), box("已发送站")], [box("已发送站"), box("等待数传")]] {
            let result = reread([row()], readings)[0]
            XCTAssertEqual(result.status, "")
            XCTAssertEqual(result.cells.last, "")
            XCTAssertTrue(result.recognitionIssues?.contains("状态补读结果不一致，请核对原图") == true)
        }
        XCTAssertEqual(reread([row()], [box("等待数传"), box("等 待 数 传")])[0].status, "等待数传")
    }

    func testMarkerBetweenRowsLeavesBothRowsUnfilledAndRequiresReview() {
        let result = reread([row(y: 0.3), row(y: 0.4)], [box("等待数传", y: 0.35)])
        XCTAssertTrue(result.allSatisfy { $0.status.isEmpty && $0.cells.last == "" })
        XCTAssertTrue(result.allSatisfy { $0.recognitionIssues?.contains("状态补读与行位置对应不清，请核对原图") == true })
    }

    func testOverlappingRowsAndTallCrossRowBoxesCannotFill() {
        let overlap = reread([row(y: 0.3), row(y: 0.32)], [box("等待数传", y: 0.31)])
        XCTAssertTrue(overlap.allSatisfy { $0.status.isEmpty && !($0.recognitionIssues ?? []).isEmpty })
        let tall = reread([row(y: 0.3), row(y: 0.4)], [box("等待数传", y: 0.3, height: 0.14)])
        XCTAssertTrue(tall.allSatisfy { $0.status.isEmpty && !($0.recognitionIssues ?? []).isEmpty })
    }

    func testOutsidePageTextAndInvalidGeometryAreIgnored() {
        let original = row()
        for reading in [box("等待数传", y: 0.1), box("等待数传", y: 0.7),
                        box("等待数传", x: .nan), box("等待数传", width: -.infinity)] {
            XCTAssertEqual(PassPlan.applyingStatusReread([original], readings: [reading], layout: layout), [original])
        }
    }

    func testAmbiguityCannotBeClearedByAnAdditionalUnambiguousCandidate() {
        let result = reread([row(y: 0.3), row(y: 0.4)], [box("等待数传", y: 0.3), box("等待数传", y: 0.35)])
        XCTAssertTrue(result.allSatisfy { $0.status.isEmpty && !($0.recognitionIssues ?? []).isEmpty })
    }

    func testOtherRecognitionIssuesAndEmergencyEvidenceSurviveSuccessfulFill() {
        var original = row()
        original.recognitionIssues = ["照片中的卫星编号需对照原图确认"]
        original.emergencyBadge = true
        let result = reread([original], [box("等待数传")])[0]
        XCTAssertEqual(result.status, "等待数传")
        XCTAssertEqual(result.recognitionIssues, original.recognitionIssues)
        XCTAssertEqual(result.emergencyBadge, true)
    }

    func testCellsConflictIsNotSilentlyOverwritten() {
        var original = row()
        original.cells[3] = "已发送站"
        let result = reread([original], [box("等待数传")])[0]
        XCTAssertEqual(result.status, "")
        XCTAssertEqual(result.cells, original.cells)
        XCTAssertTrue(result.recognitionIssues?.contains("状态补读与原识别不一致，请核对原图") == true)
    }

    func testMultiplePagesCannotUseAnUnscopedStatusBox() {
        var first = row(y: 0.3), second = row(y: 0.4)
        first.region?.page = 0
        second.region?.page = 1
        XCTAssertEqual(PassPlan.applyingStatusReread([first, second], readings: [box("等待数传")], layout: layout), [first, second])
    }
}
