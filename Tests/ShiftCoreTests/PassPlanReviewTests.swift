import Foundation
import XCTest
@testable import ShiftCore

final class PassPlanReviewTests: XCTestCase {
    private let rules: [PassPlan.OperatorRule] = [
        .init(name: "示例甲", prefixes: ["甲站"]),
        .init(name: "示例乙", prefixes: ["乙站"])
    ]

    private func row(_ station: String = "甲站-01", sat: String = "试验星",
                     start: String = "10:00:00", end: String = "10:10:00", info: String = "通道1",
                     orbit: String = "01", status: String = "等待数传") -> PassPlanRow {
        PassPlanRow(orbit: orbit, satelliteID: sat + "-ID", satellite: sat, station: station,
                    start: "2026-11-23 " + start, end: "2026-11-23 " + end, info: info, status: status)
    }

    func testNoRulesBlocksEvenOriginalDisplayGrouping() {
        let plan = row()
        XCTAssertEqual(PassPlan.grouped([plan]).first?.name, "甲站", "display grouping remains compatible")
        let audit = PassPlan.reviewIssues([plan], format: .recognizedContent)
        XCTAssertEqual(audit[0]?.map(\.category), [.station])
        XCTAssertTrue(audit[0]?.first?.message.contains("不能分享") == true)
    }

    func testBatchRouteChangesOnlyTheIntendedWholeStationAndDoesNotAlterRules() {
        let first = row()
        let near = row("甲站-010", start: "11:00:00", end: "11:20:00")
        let batch = [PassPlan.normalizedStationAlias(first.station): "示例乙"]
        XCTAssertEqual(PassPlan.resolvedOperator(of: first.station, rules: rules, batchRoutes: batch), "示例乙")
        XCTAssertEqual(PassPlan.resolvedOperator(of: near.station, rules: rules, batchRoutes: batch), "示例甲")
        XCTAssertEqual(PassPlan.resolvedOperator(of: first.station, rules: rules), "示例甲")
        let groups = PassPlan.grouped([first, near], rules: rules, batchRoutes: batch)
        XCTAssertEqual(groups.map(\.name), ["示例甲", "示例乙"])
        XCTAssertEqual(groups.map(\.rows), [[near], [first]])
        XCTAssertTrue(PassPlan.reviewIssues([first, near], format: .recognizedContent, rules: rules, batchRoutes: batch).isEmpty)
    }

    func testTemporaryRoutingCannotOverrideConflictOrInventAnOperator() {
        let first = row()
        let conflicted = [
            PassPlan.OperatorRule(name: "甲", prefixes: [], exactStations: [first.station]),
            PassPlan.OperatorRule(name: "乙", prefixes: [], exactStations: ["甲站－０１"])
        ]
        let route = [PassPlan.normalizedStationAlias(first.station): "乙"]
        XCTAssertNil(PassPlan.resolvedOperator(of: first.station, rules: conflicted, batchRoutes: route))
        XCTAssertEqual(PassPlan.grouped([first], rules: conflicted, batchRoutes: route).first?.name, PassPlan.unassigned)
        XCTAssertTrue(PassPlan.reviewIssues([first], format: .recognizedContent, rules: conflicted, batchRoutes: route)[0]?
            .contains(where: { $0.message.contains("对照表冲突") }) == true)
        XCTAssertNil(PassPlan.resolvedOperator(of: "未知站", rules: rules, batchRoutes: ["未知站": "未知运营商"]))
    }

    func testDuplicatesRemainIndependentAndExcludedTestsNeverLeak() {
        let plan = row()
        let excluded = row(status: "test")
        let audit = PassPlan.reviewIssues([plan, plan, excluded], format: .recognizedContent, rules: rules)
        for index in [0, 1] {
            XCTAssertEqual(audit[index]?.map(\.category), [.duplicate])
            XCTAssertTrue(audit[index]?.first?.message.contains("2 条相同") == true)
        }
        XCTAssertNil(audit[2])
        XCTAssertEqual(PassPlan.grouped([plan, plan, excluded], rules: rules).first?.rows.count, 2)
        XCTAssertTrue(PassPlan.reviewIssues([plan], format: .recognizedContent, rules: rules).isEmpty)
    }

    func testOverlapsAreScopedToSameStationSameChannelAndDoNotIncludeTouchingEndpoints() {
        let plans = [
            row(),
            row(sat: "试验乙", start: "10:08:00", end: "10:20:00"),
            row(sat: "试验丙", start: "10:20:00", end: "10:25:00"),
            row(sat: "试验丙", start: "10:02:00", end: "10:25:00", info: "通道2"),
            row("乙站-07", sat: "试验乙", start: "10:09:00", end: "10:20:00")
        ]
        let audit = PassPlan.reviewIssues(plans, format: .recognizedContent, rules: rules)
        XCTAssertEqual(audit[0]?.map(\.category), [.time])
        XCTAssertEqual(audit[1]?.map(\.category), [.time])
        XCTAssertNil(audit[2]); XCTAssertNil(audit[3]); XCTAssertNil(audit[4])
    }

    func testYellowWarningStaysInEvidenceButDoesNotStayPendingAfterExplicitReview() {
        var plan = row()
        plan.recognitionIssues = ["原图黄色警告：需核实设备状态"]
        let audit = PassPlan.reviewIssues([plan], format: .recognizedContent, rules: rules)
        XCTAssertEqual(audit[0]?.map(\.category), [.yellow])
        let confirmed = PassPlan.confirmedDeliveryReview(plan, format: .recognizedContent)
        XCTAssertEqual(confirmed.reviewedWarnings, ["原图黄色警告：需核实设备状态"])
        XCTAssertTrue(PassPlan.reviewIssues([confirmed], format: .recognizedContent, rules: rules).isEmpty)
        XCTAssertNil(confirmed.recognitionIssues)
    }

    func testOriginalImageStillRequiresAllReviewChecksForPreview() {
        var plan = row()
        plan.end = ""
        plan.region = .init(y0: 0.2, slope: 0, height: 0.1, left: 0, right: 1)
        XCTAssertFalse(PassPlan.reviewIssues([plan], format: .originalImage, rules: rules).isEmpty)
    }

    func testSystemHandoffDoesNotAdvanceManualReceiptAndEditsInvalidateStatus() {
        var ledger = PassPlan.DeliveryLedger()
        let date = Date(timeIntervalSince1970: 100)
        XCTAssertFalse(ledger.confirmReceipt("示例甲", at: date))
        ledger.reportHandoff("示例甲", completed: true)
        XCTAssertFalse(ledger.handedOff.contains("示例甲"))
        ledger.requestShare("示例甲")
        ledger.reportHandoff("示例甲", completed: false)
        XCTAssertTrue(ledger.requested.contains("示例甲"))
        XCTAssertTrue(ledger.handedOff.isEmpty)
        ledger.reportHandoff("示例甲", completed: true)
        XCTAssertTrue(ledger.handedOff.contains("示例甲"))
        XCTAssertTrue(ledger.confirmedReceipts.isEmpty)
        XCTAssertTrue(ledger.confirmReceipt("示例甲", at: date))
        XCTAssertFalse(ledger.confirmReceipt("示例甲", at: date + 1))
        XCTAssertEqual(ledger.confirmedReceipts["示例甲"], date)
        ledger.invalidate("示例甲")
        XCTAssertTrue(ledger.requested.isEmpty && ledger.handedOff.isEmpty && ledger.confirmedReceipts.isEmpty)
    }
}
