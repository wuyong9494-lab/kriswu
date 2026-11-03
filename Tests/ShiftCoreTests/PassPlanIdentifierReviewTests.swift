import XCTest
@testable import ShiftCore

final class PassPlanIdentifierReviewTests: XCTestCase {
    private func row() -> PassPlanRow {
        PassPlanRow(orbit: "808", satelliteID: "SAT-001", satellite: "XA102C", station: "虚构甲站-01",
                    start: "2032-06-18 08:00:00", end: "2032-06-18 08:06:00", info: "虚构信息", status: "等待数传",
                    cells: ["808", "SAT-001", "XA102C", "虚构甲站-01"],
                    region: .init(page: 2, y0: 0.3, slope: 0.01, height: 0.05, left: 0.02, right: 0.98),
                    emergencyBadge: true)
    }

    private func assertOnlyReviewIssuesChanged(_ result: PassPlanRow, from original: PassPlanRow,
                                              file: StaticString = #filePath, line: UInt = #line) {
        var restored = result
        restored.recognitionIssues = original.recognitionIssues
        XCTAssertEqual(restored, original, "原字段、原始单元格、裁条和发送标记必须保留", file: file, line: line)
    }

    func testDifferentEnglishReadNeverAutomaticallyReplacesAnIdentifier() throws {
        for (original, candidate) in [("SAT-005", "SAT-006"), ("SAT-001", "SAT-00L"),
                                      ("SAT-C01", "SAT-001"), ("SAT-O01", "SAT-001")] {
            var source = row()
            source.satelliteID = original
            let result = PassPlan.reviewIdentifierReread(source, column: .satelliteID, candidates: [candidate])
            assertOnlyReviewIssuesChanged(result, from: source)
            let warning = try XCTUnwrap(result.recognitionIssues?.last)
            XCTAssertTrue(warning.contains("卫星编号"))
            XCTAssertTrue(warning.contains("「\(candidate)」"))
            XCTAssertTrue(warning.contains("请核对原图"))
        }
    }

    func testSatelliteNameOrCodeUsesItsOwnFieldWithoutConfusingLegitimateC() throws {
        let source = row()
        let changed = PassPlan.reviewIdentifierReread(source, column: .satellite, candidates: ["XA1020"])
        assertOnlyReviewIssuesChanged(changed, from: source)
        XCTAssertEqual(changed.satellite, "XA102C")
        let warning = try XCTUnwrap(changed.recognitionIssues?.last)
        XCTAssertTrue(warning.contains("卫星名称"))
        XCTAssertTrue(warning.contains("「XA1020」"))
        XCTAssertEqual(PassPlan.reviewIdentifierReread(source, column: .satellite, candidates: ["XA102C"]), source)
    }

    func testOnlyExistingFormatNormalizationCanEstablishAgreement() {
        var source = row()
        source.satelliteID = " sat—001 "
        source.recognitionIssues = ["先前的核对问题"]
        let result = PassPlan.reviewIdentifierReread(source, column: .satelliteID,
                                                    candidates: ["S A T - 0 0 1", "SAT－001", "\tsat-001\n"])
        XCTAssertEqual(result, source, "空白、大小写与连字符格式差异不制造冲突，也不清掉已有问题")
    }

    func testNoUsableReadRequiresReviewWithoutClaimingAnOCRFailure() {
        let source = row()
        for (column, label) in [(PassPlan.Column.satelliteID, "卫星编号"), (.satellite, "卫星名称")] {
            for readings in [[], [""], [" ", "\t\n", "　"]] {
                let result = PassPlan.reviewIdentifierReread(source, column: column, candidates: readings)
                assertOnlyReviewIssuesChanged(result, from: source)
                XCTAssertEqual(result.recognitionIssues, ["\(label)未能完成独立复核，请核对原图"])
            }
        }
    }

    func testMissingOriginalIsNotFilledByAReReadCandidate() {
        for original in ["", " \t\n　"] {
            var source = row()
            source.satelliteID = original
            let result = PassPlan.reviewIdentifierReread(source, column: .satelliteID, candidates: ["SAT-001"])
            assertOnlyReviewIssuesChanged(result, from: source)
            XCTAssertEqual(result.satelliteID, original)
            XCTAssertTrue(result.recognitionIssues?.contains { $0.contains("「SAT-001」") } == true)
        }
    }

    func testEmptyCandidatesDoNotInvalidateAnAvailableAgreeingRead() {
        let source = row()
        XCTAssertEqual(PassPlan.reviewIdentifierReread(source, column: .satelliteID,
                                                      candidates: ["", "  ", "SAT-001"]), source)
        let conflicting = PassPlan.reviewIdentifierReread(source, column: .satelliteID,
                                                          candidates: ["", "SAT-001", "SAT-C01"])
        XCTAssertTrue(conflicting.recognitionIssues?.contains { $0.contains("「SAT-C01」") } == true)
        assertOnlyReviewIssuesChanged(conflicting, from: source)
    }

    func testReviewDisplaysRawDistinctCandidatesInsteadOfNormalizedOrReplacedValues() throws {
        let source = row()
        let result = PassPlan.reviewIdentifierReread(source, column: .satelliteID,
                                                    candidates: ["SAT-001", " sat—C01 ", "SAT-C01", "SAT-O01"])
        let issue = try XCTUnwrap(result.recognitionIssues?.last)
        XCTAssertTrue(issue.contains("「sat—C01」"), "保留复识原文的大小写和连字符")
        XCTAssertTrue(issue.contains("「SAT-O01」"))
        XCTAssertFalse(issue.contains("「SAT-C01」"), "格式等价的重复读数只显示一次")
        XCTAssertFalse(issue.contains("「SAT-001」"), "一致读数不能冒充冲突候选")
        assertOnlyReviewIssuesChanged(result, from: source)
    }

    func testReviewCandidateExcerptsHaveBoundedLengthAndCount() throws {
        let source = row()
        let long = String(repeating: "C", count: 300)
        let result = PassPlan.reviewIdentifierReread(source, column: .satelliteID,
                                                    candidates: [long, "DIFFERENT-2", "DIFFERENT-3", "DIFFERENT-4"])
        let issue = try XCTUnwrap(result.recognitionIssues?.last)
        XCTAssertTrue(issue.contains("「\(String(repeating: "C", count: 64))…」"))
        XCTAssertFalse(issue.contains(String(repeating: "C", count: 65)))
        XCTAssertTrue(issue.contains("DIFFERENT-2"))
        XCTAssertTrue(issue.contains("DIFFERENT-3"))
        XCTAssertFalse(issue.contains("DIFFERENT-4"))
        XCTAssertTrue(issue.contains("等"))
        XCTAssertLessThan(issue.count, 280)
    }

    func testUnsupportedColumnsLeaveTheWholeRowUnchanged() {
        var source = row()
        source.recognitionIssues = ["保留已有核对问题"]
        for column in PassPlan.Column.allCases where column != .satelliteID && column != .satellite {
            XCTAssertEqual(PassPlan.reviewIdentifierReread(source, column: column, candidates: ["DIFFERENT"]), source)
            XCTAssertEqual(PassPlan.reviewIdentifierReread(source, column: column, candidates: []), source)
        }
    }

    func testMetadataAndPriorIssuesArePreservedAndRepeatedReviewsAreIdempotent() {
        for detected in [nil, false, true] as [Bool?] {
            var source = row()
            source.status = "test"
            source.testStatusDetected = detected
            source.recognitionIssues = ["已有问题"]
            let changed = PassPlan.reviewIdentifierReread(source, column: .satelliteID, candidates: ["SAT-C01"])
            assertOnlyReviewIssuesChanged(changed, from: source)
            XCTAssertEqual(changed.recognitionIssues?.first, "已有问题")
            XCTAssertEqual(PassPlan.reviewIdentifierReread(changed, column: .satelliteID, candidates: ["SAT-C01"]), changed)
            XCTAssertEqual(PassPlan.reviewIdentifierReread(changed, column: .satelliteID, candidates: [source.satelliteID]), changed)
            XCTAssertEqual(PassPlan.reviewIdentifierReread(changed, column: .satellite, candidates: [source.satellite]), changed)
            let unavailable = PassPlan.reviewIdentifierReread(changed, column: .satelliteID, candidates: [])
            assertOnlyReviewIssuesChanged(unavailable, from: source)
            XCTAssertEqual(Array((unavailable.recognitionIssues ?? []).prefix(2)), changed.recognitionIssues)
            XCTAssertEqual(PassPlan.reviewIdentifierReread(unavailable, column: .satelliteID, candidates: []), unavailable)
        }
    }

    func testIdentifierReviewWarningSurvivesLaterOCRCombination() throws {
        let source = row()
        let reviewed = PassPlan.reviewIdentifierReread(source, column: .satelliteID, candidates: ["SAT-C01"])
        let layout = PassPlan.Layout(slots: [
            .init(label: "卫星ID", column: .satelliteID, x: 0.2),
            .init(label: "卫星名称", column: .satellite, x: 0.4),
            .init(label: "地面站", column: .station, x: 0.6),
            .init(label: "数传开始时间", column: .start, x: 0.8),
        ])
        let combined = PassPlan.combine([
            .init(rows: [source], layout: layout), .init(rows: [reviewed], layout: layout),
        ], rules: [.init(name: "虚构甲", prefixes: ["虚构甲站"])])
        let kept = try XCTUnwrap(combined.rows.first)
        XCTAssertEqual(combined.rows.count, 1)
        XCTAssertEqual(kept.satelliteID, source.satelliteID)
        XCTAssertEqual(kept.recognitionIssues, reviewed.recognitionIssues)
    }
}
