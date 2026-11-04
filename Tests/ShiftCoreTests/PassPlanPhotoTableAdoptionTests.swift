import XCTest
@testable import ShiftCore

final class PassPlanPhotoTableAdoptionTests: XCTestCase {
    private let rules = [PassPlan.OperatorRule(name: "甲", prefixes: ["甲站"])]
    private let issue = "圈号由系统表格补读，请对照原图核对"
    private let orbitIndex = 5

    private var layout: PassPlan.Layout {
        let headers = ["卫星ID", "卫星名称", "地面站", "数传开始时间", "数传结束时间", "圈号", "数传信息", "状态"]
        return .init(slots: headers.enumerated().map {
            .init(label: $0.element, column: PassPlan.column(forHeader: $0.element), x: Double($0.offset) / 8)
        })
    }

    private func row(orbit: String = "", station: String = "甲站-01") -> PassPlanRow {
        let start = "2032-06-18 08:00:00", end = "2032-06-18 08:06:00"
        return PassPlanRow(orbit: orbit, satelliteID: "LEGIT-O0C-01", satellite: "匿名卫星A", station: station,
                           start: start, end: end, info: "通道O:9C0M", status: "等待数传",
                           cells: ["LEGIT-O0C-01", "匿名卫星A", station, start, end, orbit, "通道O:9C0M", "等待数传"],
                           region: .init(y0: 0.3, slope: 0.01, height: 0.04, left: 0, right: 1))
    }

    func testUniqueEmptyOrbitAndCellAreFilledWithoutChangingStationAdoptionOrLeadingZeros() {
        let original = row(station: "申站-01")
        let candidate = row(orbit: "0042930")
        let baseline = PassPlan.adoptStations([original], from: [candidate], rules: rules)[0]
        XCTAssertEqual(baseline.orbit, "", "通用站名核对入口不新增圈号补写")
        var expected = baseline
        expected.orbit = candidate.orbit
        expected.cells[orbitIndex] = candidate.orbit
        expected.recognitionIssues = [issue]
        let result = PassPlan.adoptPhotoTable([original], from: [candidate], layout: layout, rules: rules)[0]
        XCTAssertEqual(result, expected, "除了原有站名行为，只补圈号和对应空格并增加核对提示")
        XCTAssertEqual(result.station, "甲站-01")
        XCTAssertEqual(result.orbit, "0042930")
        XCTAssertEqual(result.cells[orbitIndex], "0042930")
        XCTAssertEqual(PassPlan.adoptPhotoTable([result], from: [candidate], layout: layout, rules: rules), [result],
                       "重复处理不能改值或重复添加提示")
    }

    func testAnyNonemptyOriginalOrbitOrRawCellPreventsFill() {
        let candidate = row(orbit: "42930")
        for (orbit, rawCell) in [("42930", ""), ("10885", ""), ("", "原O0C"),
                                 ("", "42930"), (" ", ""), ("", " ")] {
            var original = row(orbit: orbit)
            original.cells[orbitIndex] = rawCell
            let baseline = PassPlan.adoptStations([original], from: [candidate], rules: rules)
            XCTAssertEqual(PassPlan.adoptPhotoTable([original], from: [candidate], layout: layout, rules: rules),
                           baseline, "字段或原格有内容时都不补：\(orbit) / \(rawCell)")
        }
    }

    func testOrbitColumnMustBeUniqueAndCellsMustMatchTheWholeLayout() {
        let original = row(), candidate = row(orbit: "42930")
        let baseline = PassPlan.adoptStations([original], from: [candidate], rules: rules)
        var absent = layout
        absent.slots[orbitIndex].column = nil
        var duplicate = layout
        duplicate.slots[6].column = .orbit
        for candidateLayout in [nil, absent, duplicate] as [PassPlan.Layout?] {
            XCTAssertEqual(PassPlan.adoptPhotoTable([original], from: [candidate], layout: candidateLayout, rules: rules), baseline)
        }
        for cells in [[], Array(original.cells.prefix(orbitIndex)), Array(original.cells.dropLast()), original.cells + [""]] {
            var malformed = original
            malformed.cells = cells
            XCTAssertEqual(PassPlan.adoptPhotoTable([malformed], from: [candidate], layout: layout, rules: rules),
                           PassPlan.adoptStations([malformed], from: [candidate], rules: rules),
                           "缺格或多格时即使圈号索引仍存在，也不猜对应关系")
        }
    }

    func testCandidateMustContainOnlyASCIIDigitsWithoutWhitespaceOrCharacterRepair() {
        let original = row()
        for raw in ["", "42O30", "42C30", "42 930", " 42930", "42930 ", "42\n930",
                    "４２９３０", "٤٢٩٣٠", "+42930", "42.930"] {
            let candidate = row(orbit: raw)
            XCTAssertEqual(PassPlan.adoptPhotoTable([original], from: [candidate], layout: layout, rules: rules),
                           PassPlan.adoptStations([original], from: [candidate], rules: rules), raw)
        }
    }

    func testMatchingStillRequiresValidEqualStartSatelliteIdentityAndNoEndConflict() {
        let original = row(), candidate = row(orbit: "42930")
        var cases: [(PassPlanRow, PassPlanRow)] = []
        var differentStart = candidate
        differentStart.start = "2032-06-18 08:01:00"
        cases.append((original, differentStart))
        var invalidSource = original, invalidCandidate = candidate
        invalidSource.start = "2032-06-18 08:00:0O"
        invalidCandidate.start = invalidSource.start
        cases.append((invalidSource, invalidCandidate))
        var conflictingID = candidate
        conflictingID.satelliteID = "LEGIT-00C-01"
        cases.append((original, conflictingID))
        var conflictingEnd = candidate
        conflictingEnd.end = "2032-06-18 08:09:00"
        cases.append((original, conflictingEnd))
        var namesOnlySource = original, namesOnlyCandidate = candidate
        namesOnlySource.satelliteID = ""
        namesOnlyCandidate.satelliteID = ""
        namesOnlyCandidate.satellite = "另一颗卫星"
        cases.append((namesOnlySource, namesOnlyCandidate))
        namesOnlySource.satellite = ""
        namesOnlyCandidate.satellite = ""
        cases.append((namesOnlySource, namesOnlyCandidate))
        for (source, other) in cases {
            XCTAssertEqual(PassPlan.adoptPhotoTable([source], from: [other], layout: layout, rules: rules),
                           PassPlan.adoptStations([source], from: [other], rules: rules))
        }
    }

    func testDuplicateCandidatesAndReverseMatchesNeverSupplyAnOrbit() {
        let original = row(), candidate = row(orbit: "42930")
        for candidates in [[candidate, candidate], [candidate, row(orbit: "10885")], [candidate, row(orbit: "42O30")]] {
            XCTAssertEqual(PassPlan.adoptPhotoTable([original], from: candidates, layout: layout, rules: rules),
                           PassPlan.adoptStations([original], from: candidates, rules: rules),
                           "不先过滤看起来不好的候选再把剩下一条当作唯一匹配")
        }
        var otherSource = original
        otherSource.cells[orbitIndex] = "已有原格"
        for sources in [[original, original], [original, otherSource]] {
            XCTAssertEqual(PassPlan.adoptPhotoTable(sources, from: [candidate], layout: layout, rules: rules),
                           PassPlan.adoptStations(sources, from: [candidate], rules: rules),
                           "反向唯一性包含所有原行，不能只数有资格补写的行")
        }
    }

    func testFillRetainsPriorIssuesAndEmergencyTestExclusion() {
        var original = row()
        original.recognitionIssues = ["原先的结束时间疑问"]
        original.emergencyBadge = true
        original.testStatusDetected = true
        var candidate = row(orbit: "42930")
        candidate.recognitionIssues = ["系统表格已有提示"]
        candidate.status = "test"
        candidate.emergencyBadge = true
        var expected = PassPlan.adoptStations([original], from: [candidate], rules: rules)[0]
        expected.orbit = candidate.orbit
        expected.cells[orbitIndex] = candidate.orbit
        expected.recognitionIssues = (expected.recognitionIssues ?? []) + [issue]
        let result = PassPlan.adoptPhotoTable([original], from: [candidate], layout: layout, rules: rules)[0]
        XCTAssertEqual(result, expected)
        XCTAssertEqual(result.status, "等待数传", "不从系统表格改写原状态")
        XCTAssertTrue(result.emergencyBadge == true && result.testStatusDetected == true)
        XCTAssertTrue(PassPlan.sendableRows([result]).isEmpty, "补圈号不能让应急 test 恢复发送")
        XCTAssertEqual(result.recognitionIssues, ["原先的结束时间疑问", "系统表格已有提示", issue])
    }

    func testOrbitFillDoesNotFillMissingIdentifierStatusEndOrOtherCells() {
        var original = row()
        original.satelliteID = ""
        original.status = ""
        original.end = ""
        for index in [0, 4, 7] { original.cells[index] = "" }
        let candidate = row(orbit: "42930")
        var expected = PassPlan.adoptStations([original], from: [candidate], rules: rules)[0]
        expected.orbit = candidate.orbit
        expected.cells[orbitIndex] = candidate.orbit
        expected.recognitionIssues = [issue]
        let result = PassPlan.adoptPhotoTable([original], from: [candidate], layout: layout, rules: rules)[0]
        XCTAssertEqual(result, expected)
        XCTAssertEqual(result.satelliteID, "")
        XCTAssertEqual(result.status, "")
        XCTAssertEqual(result.end, "")
        XCTAssertEqual([result.cells[0], result.cells[4], result.cells[7]], ["", "", ""])
    }
}
