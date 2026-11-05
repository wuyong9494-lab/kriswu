import XCTest
@testable import ShiftCore

final class PassPlanNamedIdentifierTests: XCTestCase {
    private let layout = PassPlan.Layout(slots: [
        .init(label: "卫星ID", column: .satelliteID, x: 0.15),
        .init(label: "卫星名称", column: .satellite, x: 0.3),
        .init(label: "圈号", column: .orbit, x: 0.4),
        .init(label: "地面站", column: .station, x: 0.5),
        .init(label: "开始时间", column: .start, x: 0.6),
        .init(label: "结束时间", column: .end, x: 0.7),
        .init(label: "状态", column: .status, x: 0.8),
        .init(label: "备注", column: nil, x: 0.9),
    ])

    private func row(identifier: String = "SAMPLEO7D02", name: String = "演示07D星") -> PassPlanRow {
        let cells = [identifier, name, "12345", "演示甲站-01", "2032-06-18 08:23:45",
                     "2032-06-18 08:29:39", "等待数传", "保留备注"]
        return .init(orbit: cells[2], satelliteID: identifier, satellite: name, station: cells[3],
                     start: cells[4], end: cells[5], info: "通道1:800M", status: cells[6], cells: cells,
                     region: .init(page: 2, y0: 0.3, slope: 0.02, height: 0.04, left: 0.1, right: 0.9))
    }

    func testFragmentRequiresLiteralMixedNameSuffix() {
        XCTAssertEqual(PassPlan.identifierRereadFragment(row(), layout: layout), "07D")
        XCTAssertEqual(PassPlan.identifierRereadFragment(row(name: "演示 07 d 星"), layout: layout), "07D")
        for name in ["演示O7D星", "演示07D", "演示07D星备注", "演示007星", "演示AB7星",
                     "SAMPLE07D02星", "演示07D星08C星", "演示07星", "演示卫星"] {
            XCTAssertNil(PassPlan.identifierRereadFragment(row(name: name), layout: layout), name)
        }
    }

    func testRereadUsesObservedFullIdentifierAndRetainsOriginalEvidence() {
        var original = row()
        original.emergencyBadge = true
        original.recognitionIssues = ["保留已有疑项"]
        let raw = "sample 07d02"
        let result = PassPlan.reviewNamedIdentifierReread(original, reread: raw, layout: layout)
        var expected = original
        expected.satelliteID = "SAMPLE07D02"; expected.cells[0] = raw
        expected.recognitionIssues = ["保留已有疑项", "卫星编号原格复识与名称片段相符，原读数「SAMPLEO7D02」，请核对原图"]
        XCTAssertEqual(result, expected)
        let exported = PassPlan.table([result], layout: layout)
        let column = exported.headers.firstIndex(of: "卫星ID")!
        XCTAssertEqual(exported.cells[0][column], "SAMPLE07D02")
        XCTAssertEqual(PassPlan.emergency(result, layout: layout), true)
    }

    func testOtherPrefixSuffixAndLengthChangesCannotBeAdopted() {
        let original = row()
        for raw in ["SAMPLF07D02", "SAMPLE07D03", "07D02", "12SAMPLE07D02", "SAMPLE07D2",
                    "SAMPLE07D002", "SAMPLE07D02X", "SAMPLE08D02"] {
            XCTAssertEqual(PassPlan.reviewNamedIdentifierReread(original, reread: raw, layout: layout), original, raw)
        }
    }

    func testNumericPrefixIsRetainedRatherThanDeleted() {
        let original = row(identifier: "12SAMPLEO7D02")
        XCTAssertEqual(PassPlan.reviewNamedIdentifierReread(original, reread: "SAMPLE07D02", layout: layout), original)
        let result = PassPlan.reviewNamedIdentifierReread(original, reread: "12SAMPLE07D02", layout: layout)
        XCTAssertEqual(result.satelliteID, "12SAMPLE07D02")
        XCTAssertEqual(result.satellite, original.satellite)
    }

    func testAlreadyMatchingAndLegitimateLetterOIdentifiersRemainUnchanged() {
        for original in [row(identifier: "SAMPLE07D02"), row(identifier: "sample 07d02"),
                         row(identifier: "SAMPLE7OD02", name: "演示7OD星"),
                         row(identifier: "SAMPLEO7D02", name: "演示O7D星")] {
            XCTAssertNil(PassPlan.identifierRereadFragment(original, layout: layout))
            XCTAssertEqual(PassPlan.reviewNamedIdentifierReread(original, reread: "SAMPLE07D02", layout: layout), original)
        }
    }

    func testAmbiguousDuplicateNameFragmentAndInvalidCandidatesAreRejected() {
        let repeated = row(identifier: "SAMPLEO7DO7D")
        XCTAssertEqual(PassPlan.reviewNamedIdentifierReread(repeated, reread: "SAMPLE07D07D", layout: layout), repeated)
        let original = row()
        for raw in ["", "07D", "SAMPLE07D0?", "SAMPLE０7D02", "SAMPLE07D02星", "SAMPLE-07D02"] {
            XCTAssertEqual(PassPlan.reviewNamedIdentifierReread(original, reread: raw, layout: layout), original, raw)
        }
    }

    func testMalformedLayoutsOrStaleCellsCannotSupplyNameEvidence() {
        for malformed in [PassPlan.Layout(slots: layout.slots.filter { $0.column != .satellite }),
                          .init(slots: layout.slots + [layout.slots[0]]),
                          .init(slots: layout.slots + [layout.slots[1]])] {
            let observed = PassPlan.remap([row()], from: layout, to: malformed)[0]
            XCTAssertNil(PassPlan.identifierRereadFragment(observed, layout: malformed))
        }
        for index in [0, 1] {
            var stale = row(); stale.cells[index] = "其他原格"
            XCTAssertEqual(PassPlan.reviewNamedIdentifierReread(stale, reread: "SAMPLE07D02", layout: layout), stale)
        }
    }

    func testTestRowsAndMissingIdentityOrGeometryAreNotReread() {
        var examples: [PassPlanRow] = []
        var excluded = row(); excluded.testStatusDetected = true; examples.append(excluded)
        var noRegion = row(); noRegion.region = nil; examples.append(noRegion)
        var noOrbit = row(); noOrbit.orbit = ""; examples.append(noOrbit)
        var badOrbit = row(); badOrbit.orbit = "12O45"; examples.append(badOrbit)
        var noStation = row(); noStation.station = ""; examples.append(noStation)
        var badStart = row(); badStart.start = "08:23:45"; examples.append(badStart)
        for example in examples {
            XCTAssertEqual(PassPlan.reviewNamedIdentifierReread(example, reread: "SAMPLE07D02", layout: layout), example)
        }
    }

    func testFullNameSuffixCanSupportMultipleObservedCharacters() {
        let original = row(identifier: "SAMPLEO7DO2", name: "演示07D02星")
        let result = PassPlan.reviewNamedIdentifierReread(original, reread: "SAMPLE07D02", layout: layout)
        XCTAssertEqual(result.satelliteID, "SAMPLE07D02")
        XCTAssertEqual(result.satellite, original.satellite)
        XCTAssertEqual(result.region, original.region)
        XCTAssertEqual(result.start, original.start)
    }

    func testPhotoConfirmationStillRequiredAfterNameAssistedReread() {
        let result = PassPlan.reviewNamedIdentifierReread(row(), reread: "SAMPLE07D02", layout: layout)
        let required = PassPlan.requiringPhotoIdentifierReview(result, column: .satelliteID)
        XCTAssertTrue(required.recognitionIssues?.contains("照片中的卫星编号需对照原图确认") == true)
        XCTAssertFalse(PassPlan.problems(required, rules: [.init(name: "演示", prefixes: ["演示"])], layout: layout).isEmpty)
    }

    func testOnlyOneSupportedCompleteEngineAlternativeCanBeSelected() {
        let original = row()
        let expected = PassPlan.reviewNamedIdentifierReread(original, reread: "SAMPLE07D02", layout: layout)
        for candidates in [["SAMPLF07D02", "SAMPLE07D02", "SAMPLE07D03"],
                           ["SAMPLE07D02", "SAMPLEO7D02", "07D"]] {
            XCTAssertEqual(PassPlan.reviewNamedIdentifierRereads(original, rereads: candidates, layout: layout), expected)
        }
    }

    func testDistinctSupportedEngineAlternativesRemainUnresolvedInEitherOrder() {
        let original = row(identifier: "SAMPLEO7DO7D")
        let alternatives = ["SAMPLE07DO7D", "SAMPLEO7D07D"]
        for candidate in alternatives {
            XCTAssertNotEqual(PassPlan.reviewNamedIdentifierReread(original, reread: candidate, layout: layout), original)
        }
        XCTAssertEqual(PassPlan.reviewNamedIdentifierRereads(original, rereads: alternatives, layout: layout), original)
        XCTAssertEqual(PassPlan.reviewNamedIdentifierRereads(original, rereads: Array(alternatives.reversed()), layout: layout), original)
    }

    func testDuplicateFormattedEngineAlternativesPreserveFirstActualRawCell() {
        var original = row(); original.emergencyBadge = true; original.recognitionIssues = ["保留原疑项"]
        let expected = PassPlan.reviewNamedIdentifierReread(original, reread: "sample 07d02", layout: layout)
        let actual = PassPlan.reviewNamedIdentifierRereads(original, rereads: ["sample 07d02", "SAMPLE07D02"], layout: layout)
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.cells[0], "sample 07d02")
    }

    func testAbsentOrUnsupportedEngineAlternativesDoNotChangeTheRow() {
        let original = row()
        for candidates in [[], [""], ["SAMPLEO7D02", "SAMPLE07D03", "SAMPLF07D02"], ["07D", "SAMPLE07D002"]] {
            XCTAssertEqual(PassPlan.reviewNamedIdentifierRereads(original, rereads: candidates, layout: layout), original)
        }
    }
}
