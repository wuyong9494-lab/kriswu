import Foundation
import XCTest
@testable import ShiftCore

final class ArenaSourceLocalizationTests: XCTestCase {
    private let sourceDigest = String(repeating: "a", count: 64)
    private func data(_ overrides: [String: Any] = [:]) throws -> Data {
        var value: [String: Any] = ["schemaVersion":1, "locale":"CN", "sourceIPASHA256":sourceDigest,
            "strings":["TID_LABEL":"示例", "TID_COUNT":"<NUM> 次", "TID_RICH":"<c1>示例</c>", "TID_EMPTY":""]]
        value.merge(overrides) { _, new in new }
        return try JSONSerialization.data(withJSONObject: value)
    }
    func testPlainLabelsDoNotLeakUnboundCountersOrMarkup() throws {
        let catalog = try ArenaSourceLocalization(data: data(), expectedSourceSHA256: sourceDigest)
        XCTAssertEqual(catalog.plainText("TID_LABEL"), "示例")
        for key in ["TID_COUNT", "TID_RICH", "TID_EMPTY", "MISSING"] { XCTAssertNil(catalog.plainText(key)) }
        XCTAssertEqual(catalog.strings["TID_COUNT"], "<NUM> 次")
    }
    func testWrongSourceUnsupportedLocaleAndOversizedStringsFail() throws {
        XCTAssertThrowsError(try ArenaSourceLocalization(data: data(), expectedSourceSHA256: String(repeating:"b",count:64)))
        for override: [String: Any] in [["schemaVersion":2], ["locale":"unknown"],
                                       ["strings":["TID_LONG":String(repeating:"x",count:65_537)]]] {
            XCTAssertThrowsError(try ArenaSourceLocalization(data: data(override), expectedSourceSHA256: sourceDigest))
        }
    }
}
