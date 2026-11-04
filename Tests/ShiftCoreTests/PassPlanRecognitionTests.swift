import XCTest
@testable import ShiftCore

final class PassPlanRecognitionTests: XCTestCase {
    private let rules = [PassPlan.OperatorRule(name: "甲", prefixes: ["甲站"]),
                         PassPlan.OperatorRule(name: "乙", prefixes: ["乙站"])]

    private var layout: PassPlan.Layout {
        PassPlan.Layout(slots: [
            .init(label: "卫星名称", column: .satellite, x: 0.1),
            .init(label: "地面站", column: .station, x: 0.25),
            .init(label: "数传开始时间", column: .start, x: 0.4),
            .init(label: "数传结束时间", column: .end, x: 0.55),
            .init(label: "圈号", column: .orbit, x: 0.65),
            .init(label: "卫星ID", column: .satelliteID, x: 0.75),
            .init(label: "数传信息", column: .info, x: 0.85),
            .init(label: "是否应急", column: nil, x: 0.95),
        ])
    }

    private func row(_ satellite: String = "SAT-A", station: String = "甲站-北区01", at y: Double = 0.2) -> PassPlanRow {
        let start = "2026-10-27 08:00:00", end = "2026-10-27 08:07:00"
        return PassPlanRow(satellite: satellite, station: station, start: start, end: end,
                           cells: [satellite, station, start, end, "", "", "", "不是"],
                           region: .init(y0: y, slope: 0, height: 0.04, left: 0, right: 1))
    }

    func testMalformedSecondsAreNotSilentlyZeroedOrTruncated() {
        for value in ["2026-10-27 08:00:5O", "2026-10-27 08:00:001", "2026-10-27 08:003",
                      "2026-10-27 08:00:00 extra", "extra 2026-10-27 08:00:00", "2026-10-27 08:00:70"] {
            XCTAssertEqual(PassPlan.normalizedTime(value), value, value)
            XCTAssertFalse(PassPlan.isValidTime(PassPlan.normalizedTime(value)), value)
        }
    }

    func testMissingSeparatorsDoNotAllowLettersToCreateATime() {
        let damaged = "2026-10-27 08:OO:30 12"
        XCTAssertEqual(PassPlan.normalizedTime(damaged), damaged,
                       "不能删除 OO 再把后面的数字拼成另一个合法时间")
        XCTAssertEqual(PassPlan.normalizedTime("2026 10-27 22:05:25"), "2026-10-27 22:05:25")
        XCTAssertEqual(PassPlan.normalizedTime("2026-10 28 075658"), "2026-10-28 07:56:58")
        XCTAssertEqual(PassPlan.normalizedTime("20261027080525"), "2026-10-27 08:05:25")
        XCTAssertEqual(PassPlan.normalizedTime("2026年10月27日 8:05"), "2026-10-27 08:05:00")
    }

    func testCalendarDatesAreValidatedIncludingCenturyLeapYears() {
        for day in ["2026-02-29", "2026-02-30", "2026-04-31", "2100-02-29", "0000-01-01"] {
            let value = day + " 08:00:00"
            XCTAssertFalse(PassPlan.isValidTime(value), value)
            XCTAssertEqual(PassPlan.normalizedTime(value), value)
            var invalid = row()
            invalid.start = value
            XCTAssertTrue(PassPlan.problems(invalid, rules: rules, layout: layout).contains("开始时间没认全"))
        }
        for day in ["2024-02-29", "2000-02-29", "2026-02-28", "2026-04-30"] {
            XCTAssertTrue(PassPlan.isValidTime(day + " 08:00:00"), day)
        }
    }

    func testStationAdoptionDisambiguatesSimultaneousSatellites() {
        let mine = [row("SAT-A", station: "申站-北区01"), row("SAT-B", station: "已站-南区02")]
        let table = [row("SAT-B", station: "乙站-南区02"), row("SAT-A", station: "甲站-北区01")]
        let result = PassPlan.adoptStations(mine, from: table, rules: rules)
        XCTAssertEqual(result.map(\.station), ["甲站-北区01", "乙站-南区02"],
                       "同一秒的不同卫星必须各自对应，不能全用第一条站名")
        XCTAssertTrue(result.allSatisfy { $0.recognitionIssues == nil })
    }

    func testStationAdoptionRequiresUniqueCandidate() {
        let original = row(station: "申站-北区01")
        let result = PassPlan.adoptStations([original], from: [row(), row(station: "乙站-南区02")], rules: rules)
        XCTAssertEqual(result[0].station, original.station)
        XCTAssertTrue(result[0].recognitionIssues?.contains("同一时间对应多个地面站，需核对原图") == true)
    }

    func testStationAdoptionDoesNotReuseOneTableRowForTwoSourceRows() {
        let mine = [row(station: "申站-北区01"), row(station: "已站-南区02")]
        let result = PassPlan.adoptStations(mine, from: [row()], rules: rules)
        XCTAssertEqual(result.map(\.station), mine.map(\.station),
                       "同一卫星同时向两站数传时，一个候选不能重复套到两行")
        XCTAssertTrue(result.allSatisfy {
            $0.recognitionIssues?.contains("同一时间的计划无法唯一对应地面站，请核对原图") == true
        })
    }

    func testStationAdoptionRejectsConflictingOrbitEndAndSatelliteID() {
        var original = row(station: "申站-北区01")
        original.orbit = "101"
        original.satelliteID = "ID-A"
        var candidate = row()
        candidate.orbit = "102"
        candidate.satelliteID = "ID-A"
        XCTAssertEqual(PassPlan.adoptStations([original], from: [candidate], rules: rules)[0].station, original.station)
        candidate.orbit = "101"
        candidate.satelliteID = "ID-B"
        XCTAssertEqual(PassPlan.adoptStations([original], from: [candidate], rules: rules)[0].station, original.station)
        candidate.satelliteID = "ID-A"
        candidate.end = "2026-10-27 08:09:00"
        XCTAssertEqual(PassPlan.adoptStations([original], from: [candidate], rules: rules)[0].station, original.station)
    }

    func testStationAdoptionDoesNotUseTimeAloneOrUnconfiguredPrefixes() {
        var original = row("", station: "申站-北区01")
        XCTAssertEqual(PassPlan.adoptStations([original], from: [row()], rules: rules)[0].station, original.station)
        original.satellite = "SAT-A"
        XCTAssertEqual(PassPlan.adoptStations([original], from: [row()], rules: [])[0].station, original.station,
                       "没有对照表时，带横杠不能证明站名正确")
        original.start = "2026-10-27 08:00:5O"
        var candidate = row()
        candidate.start = original.start
        XCTAssertEqual(PassPlan.adoptStations([original], from: [candidate], rules: rules)[0].station, original.station)
    }

    func testKnownStationConflictRequiresReviewInsteadOfReplacement() {
        let original = row()
        let result = PassPlan.adoptStations([original], from: [row(station: "乙站-南区02")], rules: rules)[0]
        XCTAssertEqual(result.station, original.station)
        XCTAssertTrue(result.recognitionIssues?.contains("地面站多次识别不一致，请核对原图") == true)
    }

    func testLocalStationRereadNeedsTwoAgreeingReadings() {
        var original = row(station: "申站-北区01")
        original.recognitionIssues = ["先前需要核对"]
        XCTAssertEqual(PassPlan.reviewStationReread(original, candidates: ["甲站-北区01"], rules: rules), original)
        XCTAssertEqual(PassPlan.reviewStationReread(original, candidates: ["甲站-北区01", ""], rules: rules), original)
        let result = PassPlan.reviewStationReread(original, candidates: ["甲站-北区01", "甲站 — 北区01"], rules: rules)
        XCTAssertEqual(result.station, "甲站-北区01")
        XCTAssertEqual(result.recognitionIssues, original.recognitionIssues, "修复一个字段不能清掉其他核对标记")
    }

    func testLocalStationRereadKeepsKnownAndUnknownValuesOnConflict() {
        let known = row()
        let conflict = PassPlan.reviewStationReread(known, candidates: ["乙站-南区02"], rules: rules)
        XCTAssertEqual(conflict.station, known.station)
        XCTAssertTrue(conflict.recognitionIssues?.contains("地面站多次识别不一致，请核对原图") == true)
        let unknown = row(station: "申站-北区01")
        let mixed = PassPlan.reviewStationReread(unknown, candidates: ["甲站-北区01", "乙站-南区02"], rules: rules)
        XCTAssertEqual(mixed.station, unknown.station)
        XCTAssertNotNil(mixed.recognitionIssues)
        XCTAssertEqual(PassPlan.reviewStationReread(unknown, candidates: ["申站-北区09", "申站-北区09"], rules: rules), unknown)
        XCTAssertEqual(PassPlan.reviewStationReread(unknown, candidates: ["甲站-北区01", "甲站-北区01"], rules: []), unknown)
    }

    func testMergeKeepsDifferentSatelliteIDsAndOrbits() {
        var a = row(), b = row("SAT-B")
        a.satelliteID = "ID-A"
        b.satelliteID = "ID-B"
        a.orbit = "101"
        b.orbit = "101"
        XCTAssertEqual(PassPlan.merge([[a], [b]]).count, 2, "同站同时间不同卫星 ID 不能去重")
        b = a
        b.orbit = "102"
        XCTAssertEqual(PassPlan.merge([[a], [b]]).count, 2, "圈次不同不能去重")
    }

    func testMergeKeepsDifferentSatelliteNamesWithoutStableIdentity() {
        var a = row(), b = row("SAT-B")
        a.end = ""
        b.end = ""
        XCTAssertEqual(PassPlan.merge([[a], [b]]).map(\.satellite), ["SAT-A", "SAT-B"],
                       "Excel 没有结束时间时，同站同一开始时间不够证明是同条计划")
        a.orbit = "101"
        b.orbit = "101"
        let sameOrbit = PassPlan.merge([[a], [b]])
        XCTAssertEqual(sameOrbit.map(\.satellite), ["SAT-A", "SAT-B"], "圈次不是全局卫星身份")
        XCTAssertTrue(sameOrbit.allSatisfy {
            $0.recognitionIssues?.contains("跨页同站同时间的卫星不一致，请核对原图") == true
        })
    }

    func testMergeDoesNotDropRowsWithinOnePageOrWithInvalidTime() {
        let original = row()
        XCTAssertEqual(PassPlan.merge([[original, original]]).count, 2)
        var malformed = original
        malformed.start = "2026-10-27 08:00:5O"
        XCTAssertEqual(PassPlan.merge([[malformed], [malformed]]).count, 2,
                       "认坏的时间不能作为跨页身份凭据")
    }

    func testMergeStableIdentityRetainsSatelliteConflictAndPriorIssues() {
        var a = row("试验一号")
        a.orbit = "101"
        a.satelliteID = "ID-A"
        a.recognitionIssues = ["原有提示"]
        var b = a
        b.satellite = "试验-号"
        b.info = "通道1"
        b.recognitionIssues = ["另一页提示"]
        let merged = PassPlan.merge([[a], [b]])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].info, "通道1")
        XCTAssertEqual(Set(merged[0].recognitionIssues ?? []), Set(["原有提示", "另一页提示", "卫星名称多次识别不一致，请核对原图"]))
    }

    func testMergeAmbiguousOverlapIsVisible() {
        let a = row()
        let merged = PassPlan.merge([[a, a], [a]])
        XCTAssertEqual(merged.count, 3, "不能凭时间吞掉无法唯一对应的行")
        XCTAssertTrue(merged.allSatisfy { $0.recognitionIssues?.contains("跨页计划无法唯一对应，请核对原图") == true })
    }

    func testMergeFlagsEmergencyDisagreementAcrossPages() {
        let first = row()
        var second = first
        second.cells[7] = "是"
        second.region?.page = 1
        let merged = PassPlan.merge([[first], [second]], layout: layout)
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].recognitionIssues?.contains("是否应急多次识别不一致，请核对原图") == true)
        XCTAssertTrue(PassPlan.problems(merged[0], rules: rules, layout: layout)
            .contains("是否应急多次识别不一致，请核对原图"))
    }

    func testCombineFlagsValidTimeAndStationDisagreement() {
        let a = row()
        var b = row(station: "乙站-南区02")
        b.start = "2026-10-27 08:01:00"
        b.end = "2026-10-27 08:09:00"
        let combined = PassPlan.combine([.init(rows: [a], layout: layout), .init(rows: [b], layout: layout)], rules: rules)
        XCTAssertEqual(combined.rows.count, 1)
        XCTAssertEqual(combined.rows[0].start, a.start, "没有证据时不随意覆盖首选读数")
        let issues = PassPlan.problems(combined.rows[0], rules: rules, layout: layout)
        for field in ["开始时间", "结束时间", "地面站"] {
            XCTAssertTrue(issues.contains("\(field)多次识别不一致，请核对原图"), field)
        }
    }

    func testCombineFlagsSatelliteOrbitInformationAndEmergencyDisagreement() {
        var a = row()
        a.orbit = "101"
        a.satelliteID = "ID-A"
        a.info = "通道1:900M"
        var b = row("SAT-B")
        b.orbit = "102"
        b.satelliteID = "ID-B"
        b.info = "通道1:800M"
        b.cells[7] = "是"
        let result = PassPlan.combine([.init(rows: [a], layout: layout), .init(rows: [b], layout: layout)], rules: rules).rows[0]
        for field in ["卫星名称", "卫星编号", "圈号", "数传信息", "是否应急"] {
            XCTAssertTrue(result.recognitionIssues?.contains("\(field)多次识别不一致，请核对原图") == true, field)
        }
    }

    func testCombineKeepsWarningsWhenMoreCompleteReadingWins() {
        var damaged = row(station: "申站-北区01")
        damaged.start = "2026-10-27 08:00:5O"
        damaged.recognitionIssues = ["原有提示"]
        let good = row()
        let result = PassPlan.combine([.init(rows: [damaged], layout: layout), .init(rows: [good], layout: layout)], rules: rules).rows[0]
        XCTAssertEqual(result.station, good.station)
        XCTAssertEqual(result.start, good.start)
        XCTAssertEqual(result.recognitionIssues, ["原有提示"], "格式坏的读数不冒充第二个合法时间，但旧提示不能丢")
    }

    func testCombineDoesNotCompareDifferentRowsOrDifferentPages() {
        let a = row()
        let b = row("SAT-B", at: 0.3)
        let result = PassPlan.combine([.init(rows: [a], layout: layout), .init(rows: [b], layout: layout)], rules: rules)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertTrue(result.rows.allSatisfy { $0.recognitionIssues == nil })
        var anotherPage = row("SAT-C")
        anotherPage.region?.page = 1
        let pages = PassPlan.combine([.init(rows: [a], layout: layout), .init(rows: [anotherPage], layout: layout)], rules: rules)
        XCTAssertEqual(pages.rows.count, 2)
        XCTAssertTrue(pages.rows.allSatisfy { $0.recognitionIssues == nil })
    }

    func testCombineAmbiguousGeometryDoesNotSilentlyReplaceARow() {
        let a = row()
        let b = row("SAT-B", at: 0.21)
        let result = PassPlan.combine([.init(rows: [a, b], layout: layout), .init(rows: [row(at: 0.205)], layout: layout)], rules: rules)
        XCTAssertEqual(result.rows.count, 3)
        XCTAssertTrue(result.rows.allSatisfy { $0.recognitionIssues?.contains("多次识别的行位置对应不清，请核对原图") == true })
    }

    func testRemapAndCodableKeepReviewIssuesAndReadOldPlans() throws {
        var original = row()
        original.recognitionIssues = ["开始时间多次识别不一致，请核对原图"]
        let reversed = PassPlan.Layout(slots: Array(layout.slots.reversed()))
        let moved = PassPlan.remap([original], from: layout, to: reversed)[0]
        XCTAssertEqual(moved.recognitionIssues, original.recognitionIssues)
        let encoded = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(PassPlanRow.self, from: encoded), original)
        var oldJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        oldJSON.removeValue(forKey: "recognitionIssues")
        let old = try JSONDecoder().decode(PassPlanRow.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        XCTAssertNil(old.recognitionIssues, "之前保存的计划不含新字段，仍能加载")
        XCTAssertEqual(old.station, original.station)
    }

    func testEmergencyDoesNotAcceptArbitraryYesOrNoPrefixes() {
        for value in ["是否", "是X", "不是未知", "否认", "是/否"] {
            var candidate = row()
            candidate.cells[7] = value
            XCTAssertNil(PassPlan.emergency(candidate, layout: layout), value)
        }
        var candidate = row()
        candidate.cells[7] = "是 不"
        XCTAssertEqual(PassPlan.emergency(candidate, layout: layout), true)
        candidate.cells[7] = "不是不"
        XCTAssertEqual(PassPlan.emergency(candidate, layout: layout), false)
    }

    func testAmbiguousOperatorPrefixDoesNotChooseAnArbitraryCompany() {
        let conflicting = [PassPlan.OperatorRule(name: "甲", prefixes: ["共同站"]),
                           PassPlan.OperatorRule(name: "乙", prefixes: ["共同站"])]
        XCTAssertNil(PassPlan.operatorName(of: "共同站-北区01", rules: conflicting))
        XCTAssertNil(PassPlan.operatorName(of: "共同站-北区01", rules: Array(conflicting.reversed())))
        let specific = conflicting + [PassPlan.OperatorRule(name: "丙", prefixes: ["共同站-北区"])]
        XCTAssertEqual(PassPlan.operatorName(of: "共同站-北区01", rules: specific), "丙", "唯一的更长前缀仍可分家")
    }
}
