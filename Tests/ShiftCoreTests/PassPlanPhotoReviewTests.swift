import XCTest
@testable import ShiftCore

final class PassPlanPhotoReviewTests: XCTestCase {
    private let rules = [PassPlan.OperatorRule(name: "虚构甲", prefixes: ["虚构甲站"])]
    private let layout = PassPlan.Layout(slots: [
        .init(label: "圈号", column: .orbit, x: 0.1),
        .init(label: "卫星ID", column: .satelliteID, x: 0.2),
        .init(label: "卫星名称", column: .satellite, x: 0.3),
        .init(label: "地面站", column: .station, x: 0.4),
        .init(label: "数传开始时间", column: .start, x: 0.55),
        .init(label: "数传结束时间", column: .end, x: 0.75),
        .init(label: "状态", column: .status, x: 0.9),
    ])
    private let identifierIssue = "照片中的卫星编号需对照原图确认"

    private func row(id: String = "SAT-001") -> PassPlanRow {
        PassPlanRow(orbit: "808", satelliteID: id, satellite: "匿名卫星A", station: "虚构甲站-01",
                    start: "2032-06-18 08:00:00", end: "2032-06-18 08:06:00", info: "虚构信息", status: "等待数传",
                    cells: ["808", id, "匿名卫星A", "虚构甲站-01"],
                    region: .init(page: 2, y0: 0.3, slope: 0.01, height: 0.05, left: 0.02, right: 0.98),
                    emergencyBadge: true)
    }

    private func assertOriginalDataPreserved(_ result: PassPlanRow, from original: PassPlanRow,
                                            file: StaticString = #filePath, line: UInt = #line) {
        var data = result
        data.recognitionIssues = original.recognitionIssues
        XCTAssertEqual(data, original, file: file, line: line)
    }

    func testSixPreviouslyMissedCorrelatedReadsNowReachTheExistingReviewGate() {
        let identifiers = ["XBGFO7E01", "XBGFO7E04", "XBGFO7E04", "XBGFO7E04", "XBGFO7E04", "XBGFO7E04"]
        let photographed = identifiers.enumerated().map { index, identifier in
            var original = row(id: identifier)
            original.orbit = String(808 + index)
            // 重现完整读数和局部英语读数同错一致；核心复识方法原有语义不改。
            let agreeing = PassPlan.reviewIdentifierReread(original, column: .satelliteID, candidates: [identifier])
            XCTAssertEqual(agreeing, original)
            let required = PassPlan.requiringPhotoIdentifierReview(agreeing, column: .satelliteID)
            assertOriginalDataPreserved(required, from: original)
            return required
        }
        let grouped = PassPlan.grouped(photographed, rules: rules).flatMap(\.rows)
        XCTAssertEqual(grouped.count, 6, "普通计划保留在待核对分组，不冒充 test 或删除原行")
        XCTAssertTrue(grouped.allSatisfy {
            PassPlan.problems($0, rules: rules, layout: layout).contains(identifierIssue)
        }, "实际分享入口 readyToSend 使用同一 problems 结果拦截")
    }

    func testCorrectAndLegitimateOIdentifiersAlsoNeedConfirmationThenCanPass() {
        for identifier in ["XA101C", "LEGIT-O-01", "SAT-006", "123456"] {
            let original = row(id: identifier)
            let required = PassPlan.requiringPhotoIdentifierReview(original, column: .satelliteID)
            XCTAssertEqual(required.recognitionIssues, [identifierIssue])
            let confirmed = PassPlan.confirmedRecognitionReview(required)
            XCTAssertEqual(confirmed, original)
            XCTAssertEqual(PassPlan.grouped([confirmed], rules: rules).flatMap(\.rows), [confirmed])
            XCTAssertTrue(PassPlan.problems(confirmed, rules: rules, layout: layout).isEmpty)
        }
    }

    func testPhotoSatelliteCodeUsesTheSameRequirementWithoutChangingItsField() {
        var original = row()
        original.satellite = "XA101C"
        original.satelliteID = ""
        let result = PassPlan.requiringPhotoIdentifierReview(original, column: .satellite)
        XCTAssertEqual(result.recognitionIssues, ["照片中的卫星代号需对照原图确认"])
        assertOriginalDataPreserved(result, from: original)
        XCTAssertEqual(PassPlan.confirmedRecognitionReview(result), original)
    }

    func testMissingImageRegionDoesNotBypassPhotoConfirmation() {
        var original = row()
        original.region = nil
        let result = PassPlan.requiringPhotoIdentifierReview(original, column: .satelliteID)
        XCTAssertEqual(result.recognitionIssues, [identifierIssue])
        XCTAssertNil(result.region)
        assertOriginalDataPreserved(result, from: original)
        XCTAssertFalse(PassPlan.problems(result, rules: rules, layout: layout).isEmpty)
    }

    func testConfirmationCannotClearComputedTimeAndRequiredFieldProblems() {
        var original = row()
        original.start = "2032-06-18 08:0X:00"
        original.orbit = ""
        original.satelliteID = ""
        let required = PassPlan.requiringPhotoIdentifierReview(original, column: .satelliteID)
        let confirmed = PassPlan.confirmedRecognitionReview(required)
        assertOriginalDataPreserved(confirmed, from: original)
        XCTAssertNil(confirmed.recognitionIssues)
        let problems = PassPlan.problems(confirmed, rules: rules, layout: layout)
        XCTAssertTrue(problems.contains("开始时间没认全"))
        XCTAssertTrue(problems.contains("没认出圈号"))
        XCTAssertTrue(problems.contains("没认出卫星编号"))
        XCTAssertFalse(problems.isEmpty, "人工确认不是绕过字段格式和必填检查")
    }

    func testConfirmationNeverClearsTestEvidenceOrEmergencyMetadata() {
        var direct = row()
        direct.status = "test"
        direct.testStatusDetected = nil
        var retained = row()
        retained.testStatusDetected = true
        for original in [direct, retained] {
            let required = PassPlan.requiringPhotoIdentifierReview(original, column: .satelliteID)
            assertOriginalDataPreserved(required, from: original)
            let confirmed = PassPlan.confirmedRecognitionReview(required)
            XCTAssertEqual(confirmed, original)
            XCTAssertTrue(PassPlan.isExcludedFromSending(confirmed))
            XCTAssertTrue(PassPlan.grouped([confirmed], rules: rules).isEmpty)
            XCTAssertEqual(confirmed.emergencyBadge, original.emergencyBadge)
        }
    }

    func testExistingIssuesRemainAndRepeatedRequirementIsIdempotent() {
        var original = row()
        original.recognitionIssues = ["先前的识别冲突"]
        let first = PassPlan.requiringPhotoIdentifierReview(original, column: .satelliteID)
        XCTAssertEqual(first.recognitionIssues, ["先前的识别冲突", identifierIssue])
        XCTAssertEqual(PassPlan.requiringPhotoIdentifierReview(first, column: .satelliteID), first)
        XCTAssertEqual(PassPlan.reviewIdentifierReread(first, column: .satelliteID, candidates: [first.satelliteID]), first,
                       "局部复识一致不等于用户已经核对")
        let confirmed = PassPlan.confirmedRecognitionReview(first)
        XCTAssertNil(confirmed.recognitionIssues)
        assertOriginalDataPreserved(confirmed, from: original)
    }

    func testReadingAgainRequiresASecondExplicitConfirmation() {
        let once = PassPlan.requiringPhotoIdentifierReview(row(), column: .satelliteID)
        let confirmed = PassPlan.confirmedRecognitionReview(once)
        XCTAssertTrue(PassPlan.problems(confirmed, rules: rules, layout: layout).isEmpty)
        let newRead = PassPlan.requiringPhotoIdentifierReview(confirmed, column: .satelliteID)
        XCTAssertEqual(newRead.recognitionIssues, [identifierIssue])
        XCTAssertFalse(PassPlan.problems(newRead, rules: rules, layout: layout).isEmpty)
    }

    func testUnsupportedColumnsDoNotAddPhotoRequirements() {
        var original = row()
        original.recognitionIssues = ["先前的识别冲突"]
        for column in PassPlan.Column.allCases where column != .satelliteID && column != .satellite {
            XCTAssertEqual(PassPlan.requiringPhotoIdentifierReview(original, column: column), original)
        }
    }

    func testPhotoRequirementSurvivesEncodingCombinationAndPageMerging() throws {
        let original = row()
        let required = PassPlan.requiringPhotoIdentifierReview(original, column: .satelliteID)
        let restored = try JSONDecoder().decode(PassPlanRow.self, from: JSONEncoder().encode(required))
        XCTAssertEqual(restored, required)
        let combined = PassPlan.combine([
            .init(rows: [original], layout: layout), .init(rows: [restored], layout: layout),
        ], rules: rules)
        XCTAssertEqual(combined.rows.count, 1)
        XCTAssertTrue(combined.rows[0].recognitionIssues?.contains(identifierIssue) == true)
        var later = PassPlan.confirmedRecognitionReview(original)
        later.region?.page = 3
        later.info += "（补充）"
        let merged = PassPlan.merge([[restored], [later]], layout: layout)
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].recognitionIssues?.contains(identifierIssue) == true,
                      "另一页/另一遍没有确认提示不能抹掉此前未完成的照片核对")
    }

    func testTextTableImportDoesNotAcquirePhotoOnlyRequirements() throws {
        let reading = PassPlan.readTable([
            ["圈号", "卫星ID", "卫星名称", "地面站", "数传开始时间", "数传结束时间", "状态"],
            ["808", "LEGIT-O-01", "匿名卫星A", "虚构甲站-01", "2032-06-18 08:00:00", "2032-06-18 08:06:00", "等待数传"],
        ])
        let imported = try XCTUnwrap(reading.rows.first)
        XCTAssertNil(imported.recognitionIssues)
        XCTAssertTrue(PassPlan.problems(imported, rules: rules, layout: reading.layout).isEmpty)
    }
}
