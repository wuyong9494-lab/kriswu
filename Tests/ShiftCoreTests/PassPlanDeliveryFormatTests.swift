import XCTest
@testable import ShiftCore

final class PassPlanDeliveryFormatTests: XCTestCase {
    private let rules = [PassPlan.OperatorRule(name: "演示甲", prefixes: ["演示甲站"])]
    private let layout = PassPlan.Layout(slots: [
        .init(label: "圈号", column: .orbit, x: 0.08),
        .init(label: "卫星ID", column: .satelliteID, x: 0.2),
        .init(label: "卫星名称", column: .satellite, x: 0.32),
        .init(label: "地面站", column: .station, x: 0.46),
        .init(label: "开始时间", column: .start, x: 0.6),
        .init(label: "结束时间", column: .end, x: 0.73),
        .init(label: "状态", column: .status, x: 0.9),
    ])

    private func row() -> PassPlanRow {
        .init(orbit: "80O", satelliteID: "", satellite: "", station: "演示甲站-01",
              start: "2032-06-18 08:0X:00", end: "", info: "未读全", status: "等待数传",
              region: .init(y0: 0.4, slope: 0.02, height: 0.05, left: 0, right: 1),
              recognitionIssues: ["照片中的卫星编号需对照原图确认", "卫星名称多次识别不一致，请核对原图",
                                  "数传信息多次识别不一致，请核对原图"], emergencyBadge: false)
    }

    private func originalProblems(_ value: PassPlanRow, layout: PassPlan.Layout? = nil) -> [String] {
        PassPlan.deliveryProblems(value, format: .originalImage, rules: rules, layout: layout ?? self.layout)
    }

    func testUnreadableTranscriptionDoesNotBlockAnIntactOriginalRow() {
        let candidate = row()
        XCTAssertTrue(originalProblems(candidate).isEmpty)
        XCTAssertEqual(PassPlan.deliveryProblems(candidate, format: .recognizedContent, rules: rules, layout: layout),
                       PassPlan.problems(candidate, rules: rules, layout: layout))
        XCTAssertFalse(PassPlan.problems(candidate, rules: rules, layout: layout).isEmpty)
        XCTAssertEqual(candidate, row(), "检查不改原字段、裁条或疑项")
    }

    func testOriginalImageStillRejectsUnknownAndAmbiguousOperators() {
        var candidate = row()
        candidate.station = "未知站-01"
        XCTAssertTrue(originalProblems(candidate).contains { $0.contains("分不出是哪家") })
        candidate = row()
        let ambiguous = rules + [.init(name: "演示乙", prefixes: ["演示甲站"])]
        XCTAssertTrue(PassPlan.deliveryProblems(candidate, format: .originalImage, rules: ambiguous, layout: layout)
            .contains { $0.contains("分不出是哪家") })
        candidate.recognitionIssues = ["地面站多次识别不一致，请核对原图"]
        XCTAssertEqual(originalProblems(candidate), candidate.recognitionIssues)
    }

    func testRoutingGeometryAndUnclassifiedWarningsCannotBeHiddenByIdentifierWords() {
        for issue in ["多次识别的行位置对应不清，请核对原图", "test 状态与行位置对应不清，请核对原图",
                      "跨页同站同时间、同圈号和同名卫星的编号不一致，请核对原图",
                      "跨页计划无法唯一对应，请核对原图", "原图行边界重叠，请核对后使用整理表格", "新类型的识别疑项"] {
            var candidate = row(); candidate.recognitionIssues = [issue]
            XCTAssertEqual(originalProblems(candidate), [issue])
        }
    }

    func testMissingOrInvalidOriginalGeometryCannotBeConfirmedAway() {
        let regions: [PassPlan.Region?] = [nil,
            .init(y0: 0.3, slope: 0, height: 0, left: 0, right: 1),
            .init(y0: 0.3, slope: 0, height: 0.05, left: 0.8, right: 0.2),
            .init(y0: .nan, slope: 0, height: 0.05, left: 0, right: 1),
            .init(y0: 0.98, slope: 0.1, height: 0.1, left: 0, right: 1),
            .init(page: -1, y0: 0.3, slope: 0, height: 0.05, left: 0, right: 1),
        ]
        for region in regions {
            var candidate = row(); candidate.region = region
            let confirmed = PassPlan.confirmedDeliveryReview(candidate, format: .originalImage)
            XCTAssertTrue(originalProblems(confirmed).contains { $0.contains("原图行") })
        }
    }

    func testEmergencyUnknownConflictAndPositionAmbiguityStillBlockOriginals() {
        var urgentLayout = layout
        urgentLayout.slots.append(.init(label: "是否应急", column: nil, x: 0.98))
        var candidate = row()
        candidate.emergencyBadge = nil
        candidate.cells = Array(repeating: "", count: urgentLayout.slots.count)
        XCTAssertTrue(originalProblems(candidate, layout: urgentLayout).contains { $0.contains("是否应急没认出来") })
        candidate.emergencyBadge = true
        candidate.cells[candidate.cells.count - 1] = "不是"
        XCTAssertTrue(originalProblems(candidate, layout: urgentLayout).contains { $0.contains("应急标签与是否应急列不一致") })
        candidate = row(); candidate.recognitionIssues = ["左侧应急标签与行位置对应不清，请核对原图"]
        XCTAssertEqual(originalProblems(candidate), candidate.recognitionIssues)
    }

    func testUnknownStatusRequiresReviewAndThatReviewIsBoundToTheActualValue() {
        for status in ["", "te5t", "等待教传", "新的状态"] {
            var candidate = row(); candidate.status = status
            XCTAssertTrue(originalProblems(candidate).contains { $0.contains("状态未确认") })
            let reviewed = PassPlan.confirmedDeliveryReview(candidate, format: .originalImage)
            XCTAssertTrue(originalProblems(reviewed).isEmpty)
            var changed = reviewed; changed.status += "?"
            XCTAssertTrue(originalProblems(changed).contains { $0.contains("状态未确认") })
        }
    }

    func testEveryFormatAndReviewKeepsTestExcludedIncludingUrgentRows() {
        for retained in [false, true] {
            var candidate = row(); candidate.emergencyBadge = true
            candidate.status = retained ? "等待数传" : " TeSt "
            candidate.testStatusDetected = retained ? true : nil
            for format in [PassPlan.DeliveryFormat.originalImage, .recognizedContent] {
                let reviewed = PassPlan.confirmedDeliveryReview(candidate, format: format)
                XCTAssertTrue(PassPlan.isExcludedFromSending(reviewed))
                XCTAssertFalse(PassPlan.deliveryProblems(reviewed, format: format, rules: rules, layout: layout).isEmpty)
                XCTAssertTrue(PassPlan.grouped([reviewed], rules: rules).isEmpty)
            }
        }
    }

    func testOriginalReviewDoesNotAlsoApproveRecognizedText() {
        var candidate = row()
        candidate.recognitionIssues! += ["地面站多次识别不一致，请核对原图", "状态没认出来，请核对原图是否为 test"]
        let reviewed = PassPlan.confirmedDeliveryReview(candidate, format: .originalImage)
        XCTAssertEqual(reviewed.recognitionIssues, row().recognitionIssues)
        XCTAssertTrue(originalProblems(reviewed).isEmpty)
        XCTAssertFalse(PassPlan.deliveryProblems(reviewed, format: .recognizedContent, rules: rules, layout: layout).isEmpty)
        var restored = reviewed; restored.recognitionIssues = candidate.recognitionIssues; restored.reviewedStatus = nil
        XCTAssertEqual(restored, candidate, "只核对发送规则不能重写 OCR 内容或切片位置")
    }

    func testTextReviewClearsWarningsButNotInvalidFields() {
        let reviewed = PassPlan.confirmedDeliveryReview(row(), format: .recognizedContent)
        XCTAssertNil(reviewed.recognitionIssues)
        let required = PassPlan.deliveryProblems(reviewed, format: .recognizedContent, rules: rules, layout: layout)
        XCTAssertTrue(required.contains("开始时间没认全"))
        XCTAssertTrue(required.contains("没认出卫星编号"))
    }

    func testOriginalTitleNeverUsesRecognizedDatesOrExcludedRows() {
        var a = row(); a.start = "2032-06-18 08:00:00"
        var b = row(); b.start = "2040-12-31 19:00:00"
        var excluded = row(); excluded.status = "test"
        XCTAssertEqual(PassPlan.originalImageTitle(name: "演示甲", rows: [a, excluded]), "数传计划（演示甲）共 1 条")
        XCTAssertEqual(PassPlan.originalImageTitle(name: "演示甲", rows: [a]), PassPlan.originalImageTitle(name: "演示甲", rows: [b]))
        XCTAssertTrue(PassPlan.title(name: "演示甲", rows: [a]).hasPrefix("6月18日"), "文字标题逻辑保持")
    }

    func testStatusReviewEncodingPreservesOldRowsAndRequiresExplicitConfirmation() throws {
        var candidate = row(); candidate.status = ""
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(candidate)) as? [String: Any])
        object.removeValue(forKey: "reviewedStatus")
        let old = try JSONDecoder().decode(PassPlanRow.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.reviewedStatus)
        XCTAssertFalse(originalProblems(old).isEmpty)
        let confirmed = PassPlan.confirmedDeliveryReview(old, format: .originalImage)
        let decoded = try JSONDecoder().decode(PassPlanRow.self, from: JSONEncoder().encode(confirmed))
        XCTAssertEqual(decoded, confirmed)
        XCTAssertTrue(originalProblems(decoded).isEmpty)
    }

    func testActualIdentifierRereadWarningsOnlyAffectRecognizedContent() {
        let reviewed = PassPlan.reviewIdentifierReread(row(), column: .satelliteID, candidates: ["DEMO-O01"])
        XCTAssertTrue(originalProblems(reviewed).isEmpty)
        let confirmed = PassPlan.confirmedDeliveryReview(reviewed, format: .originalImage)
        XCTAssertEqual(confirmed.recognitionIssues, reviewed.recognitionIssues)
        XCTAssertFalse(PassPlan.deliveryProblems(confirmed, format: .recognizedContent, rules: rules, layout: layout).isEmpty)
    }
}
