import XCTest
@testable import ShiftCore

/// 全部为匿名、虚构的表格和坐标；不包含实际计划照片或其业务字段。
final class PassPlanDeliveryRulesTests: XCTestCase {
    private let rules = [PassPlan.OperatorRule(name: "甲", prefixes: ["甲站"]),
                         PassPlan.OperatorRule(name: "乙", prefixes: ["乙站"])]
    private let headers = ["No.", "圈号", "卫星ID", "卫星名称", "地面站", "数传开始时间", "数传结束时间", "数传信息", "状态"]
    private let xs = [0.20, 0.27, 0.35, 0.43, 0.54, 0.67, 0.81, 0.90, 0.97]

    private var layout: PassPlan.Layout {
        PassPlan.Layout(slots: zip(headers, xs).map {
            .init(label: $0.0, column: PassPlan.column(forHeader: $0.0), x: $0.1)
        })
    }

    private func box(_ text: String, x: Double, y: Double, slope: Double = 0, width: Double = 0.04) -> PassPlan.TextBox {
        .init(text: text, x: x - width / 2, y: y + slope * x - 0.008, width: width, height: 0.016)
    }

    private func row(_ satellite: String = "SAT-ALPHA", station: String = "甲站-北区01", status: String = "等待数传", y: Double = 0.3) -> PassPlanRow {
        PassPlanRow(orbit: "501", satelliteID: satellite, satellite: satellite, station: station,
                    start: "2032-06-18 08:00:00", end: "2032-06-18 08:06:00", info: "通道1:900M", status: status,
                    cells: ["1", "501", satellite, satellite, station, "2032-06-18 08:00:00", "2032-06-18 08:06:00", "通道1:900M", status],
                    region: .init(y0: y, slope: 0, height: 0.05, left: 0.04, right: 1))
    }

    private func webBoxes(badges: Set<Int> = [1], statuses: [String] = ["等待数传", "等待数传", "等待数传"], slope: Double = 0.02) -> [PassPlan.TextBox] {
        var result = zip(headers, xs).map { box($0.0, x: $0.1, y: 0.18, slope: slope) }
        for index in 0..<3 {
            let y = 0.3 + Double(index) * 0.06
            let hour = String(format: "%02d", index + 8)
            let cells = ["\(index + 1)", "\(501 + index)", "SAT-\(index)", "虚构卫星\(index)", "甲站-北区0\(index + 1)",
                         "2032-06-18 \(hour):00:00", "2032-06-18 \(hour):06:00", "通道1:900M", statuses[index]]
            result += zip(cells, xs).map { box($0.0, x: $0.1, y: y, slope: slope) }
            if badges.contains(index) { result.append(box("应 急", x: 0.10, y: y, slope: slope, width: 0.025)) }
        }
        return result
    }

    func testHeaderlessEmergencyBadgeFollowsItsTiltedRow() throws {
        let reading = PassPlan.read(webBoxes().shuffled())
        XCTAssertEqual(reading.rows.count, 3)
        XCTAssertEqual(reading.rows.map(\.orbit), ["501", "502", "503"], "左标签不能挤进圈号或卫星列")
        XCTAssertEqual(reading.rows.map(\.emergencyBadge), [false, true, false])
        XCTAssertEqual(reading.rows.map { PassPlan.emergency($0, layout: reading.layout) }, [false, true, false])
        XCTAssertEqual(PassPlan.caption(reading.rows, layout: reading.layout, normal: "普通", urgent: "应急"), "应急")
        let region = try XCTUnwrap(reading.rows[1].region)
        XCTAssertLessThanOrEqual(region.left, 0.0875, "原图裁条必须包含标签最左边")
        XCTAssertTrue(reading.rows.allSatisfy { PassPlan.problems($0, rules: rules, layout: reading.layout).isEmpty })
    }

    func testNoBadgeDoesNotInventAnEmergencyOrRequireUnknownColumn() {
        let reading = PassPlan.read(webBoxes(badges: []))
        XCTAssertTrue(reading.rows.allSatisfy { $0.emergencyBadge == nil })
        XCTAssertEqual(PassPlan.caption(reading.rows, layout: reading.layout, normal: "普通", urgent: "应急"), "普通")
        XCTAssertTrue(reading.rows.allSatisfy { PassPlan.problems($0, rules: rules, layout: reading.layout).isEmpty },
                      "未出现标签且没有是否应急列的普通页面，不能全部变成待核对")
    }

    func testOnlyExactMarkerInTheCorrectColumnChangesDeliveryRules() {
        let original = row()
        let unrelated = [box("应急", x: 0.90, y: 0.3), box("test", x: 0.43, y: 0.3),
                         box("test", x: 0.90, y: 0.3), box("应急计划说明", x: 0.10, y: 0.3),
                         box("contest", x: 0.97, y: 0.3)]
        let unchanged = PassPlan.applyingRowMarkers([original], markers: unrelated, layout: layout)[0]
        XCTAssertEqual(unchanged, original, "卫星/信息列的同名文字、边栏说明不能当标签或状态")
        let status = PassPlan.applyingRowMarkers([original], markers: [box(" T e S t ", x: 0.97, y: 0.3)], layout: layout)[0]
        XCTAssertTrue(PassPlan.isExcludedFromSending(status))
        XCTAssertEqual(status.status, original.status, "保留原读数，独立保存 test 证据")
    }

    func testBadgeAndStatusAmbiguityRequiresReview() {
        var a = row(y: 0.30), b = row("SAT-BETA", y: 0.32)
        a.region?.height = 0.06
        b.region?.height = 0.06
        let result = PassPlan.applyingRowMarkers([a, b], markers: [box("应急", x: 0.10, y: 0.31), box("test", x: 0.97, y: 0.31)], layout: layout)
        XCTAssertTrue(result.allSatisfy { $0.emergencyBadge == nil && $0.testStatusDetected == nil })
        XCTAssertTrue(result.allSatisfy { $0.recognitionIssues?.contains("左侧应急标签与行位置对应不清，请核对原图") == true })
        XCTAssertTrue(result.allSatisfy { $0.recognitionIssues?.contains("test 状态与行位置对应不清，请核对原图") == true })
    }

    func testUnmatchedMarkerBetweenRowsIsNotSilentlyIgnored() {
        var a = row(y: 0.30), b = row("SAT-BETA", y: 0.36)
        a.region?.height = 0.02
        b.region?.height = 0.02
        let result = PassPlan.applyingRowMarkers([a, b], markers: [box("test", x: 0.97, y: 0.33)], layout: layout)
        XCTAssertTrue(result.allSatisfy { $0.testStatusDetected == nil })
        XCTAssertTrue(result.allSatisfy { $0.recognitionIssues?.contains("test 状态与行位置对应不清，请核对原图") == true })
    }

    func testHeaderlessBadgeInTableCellsAndTestRowsAreRetainedForReview() {
        let reading = PassPlan.readTable([
            [""] + headers,
            ["应急"] + row(status: " Te ST ").cells,
            [""] + row("SAT-BETA").cells,
        ])
        XCTAssertEqual(reading.rows.count, 2, "识别结果保留 test 原行")
        XCTAssertEqual(reading.rows.map(\.emergencyBadge), [true, false])
        XCTAssertTrue(PassPlan.isExcludedFromSending(reading.rows[0]))
        XCTAssertFalse(PassPlan.isExcludedFromSending(reading.rows[1]))
        XCTAssertEqual(PassPlan.sendableRows(reading.rows).map(\.satellite), ["SAT-BETA"])
    }

    func testPhotoTestStatusRemainsInReadingButNeverInGroups() {
        let reading = PassPlan.read(webBoxes(badges: [1], statuses: ["等待数传", "t e S T", "已发送站"]))
        XCTAssertEqual(reading.rows.count, 3)
        XCTAssertTrue(PassPlan.isExcludedFromSending(reading.rows[1]))
        XCTAssertEqual(PassPlan.grouped(reading.rows, rules: rules).flatMap(\.rows).map(\.orbit), ["501", "503"])
        XCTAssertEqual(PassPlan.caption(reading.rows, layout: reading.layout, normal: "普通", urgent: "应急"), "普通",
                       "不发送的应急 test 不能改变正常计划的说明")
    }

    func testAllExportPathsUseTheSameTestExclusion() {
        let normal = row("VISIBLE")
        var excluded = row("HIDDEN-ONE", station: "乙站-南区02", status: " T e S T ")
        excluded.emergencyBadge = true
        var inherited = row("HIDDEN-TWO")
        inherited.testStatusDetected = true
        let all = [normal, excluded, inherited]
        XCTAssertEqual(all.count, 3, "过滤只生成发送视图，不修改原结果")
        XCTAssertEqual(PassPlan.sendableRows(all).map(\.satellite), ["VISIBLE"])
        XCTAssertEqual(PassPlan.grouped(all, rules: rules).map(\.name), ["甲"])
        XCTAssertEqual(PassPlan.idle(all, rules: rules), ["乙"])
        XCTAssertTrue(PassPlan.title(name: "甲", rows: all).hasSuffix("共 1 条"))
        XCTAssertEqual(PassPlan.caption(all, layout: layout, normal: "普通", urgent: "应急"), "普通")
        for output in [PassPlan.table(all), PassPlan.table(all, layout: layout)] {
            XCTAssertEqual(output.cells.count, 1)
            XCTAssertFalse(output.cells.joined().contains { $0.contains("HIDDEN") })
        }
        let message = PassPlan.message(name: "甲", rows: all, layout: layout)
        XCTAssertTrue(message.contains("VISIBLE"))
        XCTAssertFalse(message.contains("HIDDEN"))
    }

    func testAnAllTestSelectionHasNothingToSend() {
        let all = [row(status: "test"), row("SAT-BETA", status: "Ｔ Ｅ Ｓ Ｔ")]
        XCTAssertTrue(PassPlan.grouped(all, rules: rules).isEmpty)
        XCTAssertTrue(PassPlan.table(all, layout: layout).cells.isEmpty)
        XCTAssertEqual(PassPlan.message(name: "甲", rows: all, layout: layout, caption: "不要发送空表"), "")
        XCTAssertTrue(PassPlan.title(name: "甲", rows: all).hasSuffix("共 0 条"))
    }

    func testTestIsAnExactStatusValueNotASubstringOrAnotherField() {
        for status in ["test", "TEST", " Te St ", "t\ne\ts t", "ＴＥＳＴ"] {
            XCTAssertTrue(PassPlan.isExcludedFromSending(row(status: status)), status)
        }
        for status in ["testing", "contest", "test 2", "latest", "测试", "已发送站"] {
            var candidate = row("test", station: "甲站-test", status: status)
            candidate.info = "test 应急"
            XCTAssertFalse(PassPlan.isExcludedFromSending(candidate), status)
        }
    }

    func testBadgeIsPrintedInRedrawnTableAndTextWithoutDuplicateEmergencyColumn() {
        var urgent = row()
        urgent.emergencyBadge = true
        var normal = row("SAT-BETA")
        normal.emergencyBadge = false
        for result in [PassPlan.table([urgent, normal]), PassPlan.table([urgent, normal], layout: layout)] {
            let index = result.headers.firstIndex(of: "应急")
            XCTAssertNotNil(index)
            XCTAssertEqual(result.cells[0][index!], "应急")
            XCTAssertEqual(result.cells[1][index!], "")
        }
        XCTAssertTrue(PassPlan.message(name: "甲", rows: [urgent], layout: layout).contains("应急"))
        let explicit = PassPlan.Layout(slots: layout.slots + [.init(label: "是否应急", column: nil, x: 1)])
        urgent.cells.append("是")
        let result = PassPlan.table([urgent], layout: explicit)
        XCTAssertEqual(result.headers.filter { $0.contains("应急") }, ["是否应急"])
        XCTAssertEqual(result.cells[0].last, "是")
    }

    func testBadgeAndExplicitNoConflictRequiresReview() {
        let explicit = PassPlan.Layout(slots: layout.slots + [.init(label: "是否应急", column: nil, x: 1)])
        var candidate = row()
        candidate.emergencyBadge = true
        candidate.cells.append("不是")
        XCTAssertEqual(PassPlan.emergency(candidate, layout: explicit), true)
        XCTAssertTrue(PassPlan.problems(candidate, rules: rules, layout: explicit)
            .contains("左侧应急标签与是否应急列不一致，请核对原图"))
        candidate.emergencyBadge = false
        XCTAssertEqual(PassPlan.emergency(candidate, layout: explicit), false, "手动核对后同步两处才解除冲突")
    }

    func testRedrawnEmergencyColumnCanBeImportedAgain() {
        let reading = PassPlan.readTable([
            ["卫星", "地面站", "数传开始", "应急"],
            ["SAT-ALPHA", "甲站-北区01", "2032-06-18 08:00:00", "应急"],
            ["SAT-BETA", "甲站-北区02", "2032-06-18 09:00:00", ""],
        ])
        XCTAssertEqual(reading.rows.map { PassPlan.emergency($0, layout: reading.layout) }, [true, false])
        XCTAssertTrue(reading.rows.allSatisfy { PassPlan.problems($0, rules: rules, layout: reading.layout).isEmpty })
        let explicit = PassPlan.readTable([
            ["卫星", "地面站", "数传开始", "是否应急"],
            ["SAT-ALPHA", "甲站-北区01", "2032-06-18 08:00:00", ""],
        ])
        XCTAssertNil(PassPlan.emergency(explicit.rows[0], layout: explicit.layout))
        XCTAssertTrue(PassPlan.problems(explicit.rows[0], rules: rules, layout: explicit.layout)
            .contains("是否应急没认出来，请核对原图"))
    }

    func testCombineKeepsBadgeWhenAnotherPassMissesIt() {
        var badge = row()
        badge.emergencyBadge = true
        var missing = badge
        missing.emergencyBadge = false
        let result = PassPlan.combine([.init(rows: [missing], layout: layout), .init(rows: [badge], layout: layout)], rules: rules).rows[0]
        XCTAssertEqual(result.emergencyBadge, true)
        XCTAssertNil(result.recognitionIssues, "没识别到标签不等于读到了否，不制造应急冲突")
    }

    func testCombineAndMergeKeepTestEvidenceWhenOtherFieldsWin() {
        var test = row(status: "test")
        test.station = "申站-北区01"
        let normal = row()
        let combined = PassPlan.combine([.init(rows: [normal], layout: layout), .init(rows: [test], layout: layout)], rules: rules).rows[0]
        XCTAssertEqual(combined.station, normal.station)
        XCTAssertEqual(combined.status, normal.status)
        XCTAssertTrue(combined.testStatusDetected == true)
        XCTAssertTrue(PassPlan.sendableRows([combined]).isEmpty)
        var earlier = row(status: "test")
        earlier.info = ""
        var later = row()
        later.region?.page = 1
        let merged = PassPlan.merge([[earlier], [later]], layout: layout)[0]
        XCTAssertEqual(merged.status, later.status, "字段更多的另一页可成为首选")
        XCTAssertTrue(PassPlan.isExcludedFromSending(merged), "另一页不能抹掉 test 排除证据")
    }

    func testTableIdentityVerificationTransfersMarkersWithoutGuessingAStation() {
        let original = row()
        var table = row(station: "未知站", status: "test")
        table.emergencyBadge = true
        for configured in [rules, []] {
            let result = PassPlan.adoptStations([original], from: [table], rules: configured)[0]
            XCTAssertEqual(result.station, original.station)
            XCTAssertTrue(PassPlan.isExcludedFromSending(result))
            XCTAssertEqual(PassPlan.emergency(result, layout: layout), true)
        }
    }

    func testCrossPageOverlapPreservesBadgeAndTestMetadata() {
        var first = row()
        first.emergencyBadge = true
        first.testStatusDetected = true
        var second = first
        second.emergencyBadge = false
        second.testStatusDetected = nil
        second.region?.page = 1
        let result = PassPlan.merge([[first], [second]], layout: layout)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].emergencyBadge, true)
        XCTAssertTrue(PassPlan.isExcludedFromSending(result[0]))
        let moved = PassPlan.remap(result, from: layout, to: .init(slots: Array(layout.slots.reversed())))[0]
        XCTAssertEqual(moved.emergencyBadge, true)
        XCTAssertTrue(PassPlan.isExcludedFromSending(moved))
    }

    func testOriginalImageBoundsDoNotIncludeNeighboringTestRow() throws {
        var first = row(y: 0.30), test = row("HIDDEN", status: "test", y: 0.35), last = row("LAST", y: 0.40)
        first.region?.height = 0.12
        test.region?.height = 0.03
        last.region?.height = 0.08
        let bounded = PassPlan.boundedRegions([first, test, last])
        let top = try XCTUnwrap(bounded[0].region), bottom = try XCTUnwrap(bounded[2].region)
        XCTAssertLessThan(top.y0 + top.height / 2, 0.325)
        XCTAssertGreaterThan(bottom.y0 - bottom.height / 2, 0.375)
        XCTAssertEqual(PassPlan.sendableRows(bounded).count, 2, "先用全部行裁边界，再排除 test")
        XCTAssertEqual(PassPlan.boundedRegions(bounded), bounded, "重复限定边界不能继续缩小文字")
    }

    func testCrossingImageRowsCannotProduceAnUnsafeOriginalStrip() {
        let a = row(y: 0.3), b = row("SAT-BETA", y: 0.3)
        let bounded = PassPlan.boundedRegions([a, b])
        XCTAssertEqual(bounded.count, 2)
        XCTAssertTrue(bounded.allSatisfy { $0.region == nil })
        XCTAssertTrue(bounded.allSatisfy { $0.recognitionIssues?.contains("原图行边界重叠，请核对后使用整理表格") == true })
    }

    func testOldSavedRowsDecodeAndNewMarkerEvidenceRoundTrips() throws {
        var original = row()
        original.emergencyBadge = true
        original.testStatusDetected = true
        let encoded = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(PassPlanRow.self, from: encoded), original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "emergencyBadge")
        json.removeValue(forKey: "testStatusDetected")
        let old = try JSONDecoder().decode(PassPlanRow.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.emergencyBadge)
        XCTAssertNil(old.testStatusDetected)
        XCTAssertEqual(old.satellite, original.satellite)
    }
}
