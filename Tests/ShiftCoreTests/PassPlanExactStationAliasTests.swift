import Foundation
import XCTest
@testable import ShiftCore

final class PassPlanExactStationAliasTests: XCTestCase {
    private typealias Rule = PassPlan.OperatorRule

    func testExactOverridesOnlyMatchingStationWithoutChangingLegacyPrefixBehavior() {
        let rules = [
            Rule(name: "通用", prefixes: ["北站-"]),
            Rule(name: "精确", prefixes: [], exactStations: ["北站－０１"])
        ]
        XCTAssertEqual(PassPlan.operatorName(of: " 北站 — 01 ", rules: rules), "精确")
        XCTAssertEqual(PassPlan.operatorName(of: "北站-010", rules: rules), "通用")
        XCTAssertNil(PassPlan.operatorName(of: "北站—02", rules: rules), "旧前缀不扩大允许匹配的字符")
        XCTAssertEqual(PassPlan.operatorName(of: "北站-02", rules: []), "北站", "无规则仍兼容旧路由")
    }

    func testDuplicateExactOwnersStayUnassignedEvenWithUniquePrefix() {
        let station = "甲站-演示01"
        let rules = [
            Rule(name: "前缀", prefixes: ["甲站"]),
            Rule(name: "乙", prefixes: [], exactStations: [station]),
            Rule(name: "丙", prefixes: [], exactStations: ["甲站－演示０１"]),
            Rule(name: "乙", prefixes: [], exactStations: [station])
        ]
        XCTAssertNil(PassPlan.operatorName(of: station, rules: rules))
        XCTAssertEqual(PassPlan.stationCandidates(of: station, rules: rules), ["乙", "丙"])
        XCTAssertEqual(PassPlan.grouped([PassPlanRow(station: station)], rules: rules).first?.name,
                       PassPlan.unassigned)
    }

    func testNoDigitLetterOrCaseFoldingAndNoFuzzyAutomaticRouting() {
        let aliases = ["演示-0I", "北站-A1"]
        let rules = [Rule(name: "甲", prefixes: [], exactStations: aliases)]
        XCTAssertEqual(PassPlan.operatorName(of: "演示－０Ｉ", rules: rules), "甲")
        for invalid in ["演示-OI", "演示-01", "北站-a1", "北站-AI", "北站-A12", "演示_0I"] {
            XCTAssertNil(PassPlan.operatorName(of: invalid, rules: rules), invalid)
            XCTAssertTrue(PassPlan.stationCandidates(of: invalid, rules: rules).isEmpty, invalid)
        }
        XCTAssertTrue(PassPlan.vocabulary(rules).contains(aliases[0]))
    }

    func testNearAliasesAreOnlyBoundedSuggestionsAndNeverRouting() {
        let station = "示例站-AI"
        let rules = [
            Rule(name: "甲", prefixes: [], exactStations: ["示例站-A1", "示例站-Ａ１", "示例站-AIX"]),
            Rule(name: "乙", prefixes: [], exactStations: ["示例站-A", "示例站-AO", "完全无关"])
        ]
        XCTAssertEqual(PassPlan.nearbyStationAliases(of: station, rules: rules),
                       ["示例站-A1", "示例站-AIX", "示例站-A"])
        XCTAssertNil(PassPlan.operatorName(of: station, rules: rules))
        XCTAssertTrue(PassPlan.stationCandidates(of: station, rules: rules).isEmpty)
        XCTAssertTrue(PassPlan.nearbyStationAliases(of: String(repeating: "字", count: 81), rules: rules).isEmpty)
    }

    func testPrefixTiesExposeCandidatesWithoutAssigning() {
        let rules = [
            Rule(name: "短", prefixes: ["北站"]),
            Rule(name: "乙", prefixes: ["北站-甲"]),
            Rule(name: "丙", prefixes: ["北站-甲"])
        ]
        let station = "北站-甲03"
        XCTAssertEqual(PassPlan.stationCandidates(of: station, rules: rules), ["乙", "丙"])
        XCTAssertNil(PassPlan.operatorName(of: station, rules: rules))
    }

    func testMixedAndAliasOnlyImportExportDoNotAddDefaultPrefix() {
        let rules = PassPlan.parseRules("""
        混合：甲站/ 乙光 ＝完整 站名/一号、=备用站
        纯全名：=精确 站/01
        混合：=完整 站名/一号；=第三站
        旧版
        空别名：=
        """)
        XCTAssertEqual(rules, [
            Rule(name: "混合", prefixes: ["甲站", "乙光"], exactStations: ["完整 站名/一号", "备用站", "第三站"]),
            Rule(name: "纯全名", prefixes: [], exactStations: ["精确 站/01"]),
            Rule(name: "旧版", prefixes: ["旧版"])
        ])
        XCTAssertEqual(PassPlan.parseRules(PassPlan.rulesText(rules)), rules)
        XCTAssertNil(PassPlan.operatorName(of: "纯全名-03", rules: rules))
    }

    func testAliasesWithPunctuationQuoteOrBackslashRoundTrip() {
        let rules = [Rule(name: "甲", prefixes: [],
                          exactStations: ["站名，甲;乙", "站名\"丙\"", "站名\\\"甲、乙", "站名=特殊"])]
        XCTAssertEqual(PassPlan.parseRules(PassPlan.rulesText(rules)), rules)
    }

    func testCodableAcceptsOldPayloadWithoutAliasesAndRoundTripsNewPayload() throws {
        let old = try JSONDecoder().decode(Rule.self, from: Data(#"{"name":"甲","prefixes":["甲站"]}"#.utf8))
        XCTAssertNil(old.exactStations)
        XCTAssertEqual(old, Rule(name: "甲", prefixes: ["甲站"]))
        let new = Rule(name: "乙", prefixes: [], exactStations: ["专属站"])
        XCTAssertEqual(try JSONDecoder().decode(Rule.self, from: JSONEncoder().encode(new)), new)
    }
}
