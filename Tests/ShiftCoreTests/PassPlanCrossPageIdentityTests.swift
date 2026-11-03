import XCTest
@testable import ShiftCore

/// 只用虚构计划验证跨页 OCR 编号冲突；不能改写编号或把不同身份的 test 标记互相复制。
final class PassPlanCrossPageIdentityTests: XCTestCase {
    private let warning = "跨页同站同时间、同圈号和同名卫星的编号不一致，请核对原图"
    private let rules = [PassPlan.OperatorRule(name: "虚构甲", prefixes: ["虚构甲站"])]
    private let layout = PassPlan.Layout(slots: [
        .init(label: "圈号", column: .orbit, x: 0.10),
        .init(label: "卫星ID", column: .satelliteID, x: 0.20),
        .init(label: "卫星名称", column: .satellite, x: 0.30),
        .init(label: "地面站", column: .station, x: 0.40),
        .init(label: "数传开始时间", column: .start, x: 0.55),
        .init(label: "数传结束时间", column: .end, x: 0.75),
        .init(label: "状态", column: .status, x: 0.90),
    ])

    private func row(id: String = "SAT-001", status: String = "等待数传", page: Int = 0) -> PassPlanRow {
        PassPlanRow(orbit: "808", satelliteID: id, satellite: "匿名卫星A", station: "虚构甲站-01",
                    start: "2032-06-18 08:00:00", end: "2032-06-18 08:06:00", status: status,
                    region: .init(page: page, y0: 0.3, slope: 0, height: 0.05, left: 0, right: 1))
    }

    private func hasIdentityWarning(_ row: PassPlanRow) -> Bool {
        row.recognitionIssues?.contains(warning) == true
    }

    func testConflictingIDsKeepBothPlansAndRequireReviewBeforeSharing() throws {
        let result = PassPlan.merge([[row(status: "test")], [row(id: "SAT-C01", page: 1)]], layout: layout)
        XCTAssertEqual(result.map(\.satelliteID), ["SAT-001", "SAT-C01"])
        XCTAssertTrue(result.allSatisfy(hasIdentityWarning))
        XCTAssertTrue(PassPlan.isExcludedFromSending(result[0]))
        XCTAssertFalse(PassPlan.isExcludedFromSending(result[1]), "编号未确认相同，不能把 test 强行赋给另一条")
        XCTAssertNil(result[1].testStatusDetected)
        let grouped = PassPlan.grouped(result, rules: rules).flatMap(\.rows)
        XCTAssertEqual(grouped.map(\.satelliteID), ["SAT-C01"])
        let ordinary = try XCTUnwrap(grouped.first)
        XCTAssertEqual(PassPlan.problems(ordinary, rules: rules, layout: layout), [warning],
                       "现有分享入口按 problems 拦截；普通状态的冲突条目也必须核对")
    }

    func testConflictingIDReviewDoesNotDependOnPhotoOrder() {
        let normal = row(id: "SAT-C01")
        let excluded = row(status: "test", page: 1)
        let result = PassPlan.merge([[normal], [excluded]], layout: layout)
        XCTAssertEqual(result.map(\.satelliteID), ["SAT-C01", "SAT-001"])
        XCTAssertTrue(result.allSatisfy(hasIdentityWarning))
        XCTAssertEqual(result.filter(PassPlan.isExcludedFromSending).map(\.satelliteID), ["SAT-001"])
        XCTAssertTrue(PassPlan.sendableRows(result).allSatisfy {
            !PassPlan.problems($0, rules: rules, layout: layout).isEmpty
        })
    }

    func testMultipleConflictingCandidatesAllRequireReviewWithoutChoosingAnID() {
        let result = PassPlan.merge([
            [row(status: "test"), row(id: "SAT-O01")],
            [row(id: "SAT-C01", page: 1)],
        ], layout: layout)
        XCTAssertEqual(result.map(\.satelliteID), ["SAT-001", "SAT-O01", "SAT-C01"])
        XCTAssertTrue(result.allSatisfy(hasIdentityWarning))
        XCTAssertEqual(result.filter(PassPlan.isExcludedFromSending).map(\.satelliteID), ["SAT-001"])
    }

    func testExactIDMatchDoesNotHideAnotherConflictingCandidate() {
        var repeated = row(id: "SAT-C01", page: 1)
        repeated.info = "虚构补充信息"
        let result = PassPlan.merge([
            [row(status: "test"), row(id: "SAT-C01")], [repeated],
        ], layout: layout)
        XCTAssertEqual(result.count, 2, "明确相同的 ID 仍可正常合并")
        XCTAssertTrue(result.allSatisfy(hasIdentityWarning))
        XCTAssertEqual(result.last?.info, repeated.info)
        XCTAssertEqual(result.filter(PassPlan.isExcludedFromSending).map(\.satelliteID), ["SAT-001"])
    }

    func testPreviouslyMatchedRowStillParticipatesInCrossPageConflictReview() {
        let result = PassPlan.merge([
            [row(status: "test")],
            [row(status: "test", page: 1), row(id: "SAT-C01", page: 1)],
        ], layout: layout)
        XCTAssertEqual(result.map(\.satelliteID), ["SAT-001", "SAT-C01"])
        XCTAssertTrue(result.allSatisfy(hasIdentityWarning))
    }

    func testDifferentNamesOrbitsStationsAndTimesRemainIndependent() {
        let original = row(status: "test")
        let base = row(id: "SAT-C01", page: 1)
        var differentName = base
        differentName.satellite = "匿名卫星B"
        var differentOrbit = base
        differentOrbit.orbit = "809"
        var differentStation = base
        differentStation.station = "虚构甲站-02"
        var differentStart = base
        differentStart.start = "2032-06-18 08:01:00"
        var differentEnd = base
        differentEnd.end = "2032-06-18 08:07:00"
        for independent in [differentName, differentOrbit, differentStation, differentStart, differentEnd] {
            let result = PassPlan.merge([[original], [independent]], layout: layout)
            XCTAssertEqual(result.count, 2)
            XCTAssertTrue(result.allSatisfy { $0.recognitionIssues == nil })
            XCTAssertTrue(PassPlan.problems(result[1], rules: rules, layout: layout).isEmpty)
        }
    }

    func testSamePageDifferentIDsDoNotAcquireCrossPageWarnings() {
        let result = PassPlan.merge([[row(status: "test"), row(id: "SAT-C01")]], layout: layout)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.recognitionIssues == nil })
        XCTAssertTrue(PassPlan.problems(result[1], rules: rules, layout: layout).isEmpty)
    }

    func testIdentityReviewRequiresCompleteNonIDContext() {
        let original = row(status: "test")
        let base = row(id: "SAT-C01", page: 1)
        for key in [\PassPlanRow.orbit, \PassPlanRow.satellite, \PassPlanRow.end] {
            var a = original, b = base
            a[keyPath: key] = ""
            b[keyPath: key] = ""
            let result = PassPlan.merge([[a], [b]], layout: layout)
            XCTAssertEqual(result.count, 2)
            XCTAssertFalse(result.contains(where: hasIdentityWarning))
        }
        var invalidA = original, invalidB = base
        invalidA.end = "2032-06-18 08:0C:00"
        invalidB.end = invalidA.end
        XCTAssertFalse(PassPlan.merge([[invalidA], [invalidB]], layout: layout).contains(where: hasIdentityWarning))
    }

    func testSameIDsKeepExistingTestExclusionWithoutAnIdentityWarning() {
        let result = PassPlan.merge([[row(status: "test")], [row(page: 1)]], layout: layout)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(PassPlan.sendableRows(result).isEmpty)
        XCTAssertFalse(result.contains(where: hasIdentityWarning))
        XCTAssertTrue(result[0].recognitionIssues?.contains { $0.contains("状态（含 test") } == true)
    }

    func testIdentityWarningSurvivesLaterMoreCompleteMerge() throws {
        let reviewed = PassPlan.merge([[row(status: "test")], [row(id: "SAT-C01", page: 1)]], layout: layout)
        var later = row(id: "SAT-C01", page: 2)
        later.info = "虚构补充信息"
        let result = PassPlan.merge([reviewed, [later]], layout: layout)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy(hasIdentityWarning))
        let ordinary = try XCTUnwrap(result.first { $0.satelliteID == "SAT-C01" })
        XCTAssertEqual(ordinary.info, later.info)
        XCTAssertNil(ordinary.testStatusDetected)
        XCTAssertTrue(PassPlan.problems(ordinary, rules: rules, layout: layout).contains(warning))
        XCTAssertEqual(ordinary.recognitionIssues?.filter { $0 == warning }.count, 1)
    }

    func testIdentityWarningSurvivesAConfidentOCRPass() throws {
        let reviewed = PassPlan.merge([[row(status: "test")], [row(id: "SAT-C01", page: 1)]], layout: layout)
        let ordinary = try XCTUnwrap(reviewed.first { $0.satelliteID == "SAT-C01" })
        var clean = row(id: "SAT-C01", page: 1)
        clean.info = "虚构补充信息"
        let result = PassPlan.combine([
            .init(rows: [ordinary], layout: layout), .init(rows: [clean], layout: layout),
        ], rules: rules)
        let kept = try XCTUnwrap(result.rows.first)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(kept.info, clean.info)
        XCTAssertTrue(hasIdentityWarning(kept))
        XCTAssertTrue(PassPlan.problems(kept, rules: rules, layout: layout).contains(warning))
        XCTAssertNil(kept.testStatusDetected)
    }
}
