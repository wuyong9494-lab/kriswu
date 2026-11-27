import XCTest
@testable import ShiftCore

final class WuMindFootageEditTests: XCTestCase {
    func testRemoveMiddleAndSubtitleOperateOnOriginalTime() throws {
        let edit = try XCTUnwrap(WuMindFootageEdit(instruction: "删除第 1 到 2 秒，字幕改为「抵达」"))
        XCTAssertEqual(edit.retainedRanges(duration: 3), [0..<1, 2..<3])
        XCTAssertEqual(edit.subtitle, "抵达")
        XCTAssertTrue(edit.retainedRanges(duration: 1.5).isEmpty)
        XCTAssertNil(WuMindFootageEdit(instruction: "删除第 3 到 1 秒"))
        XCTAssertNil(WuMindFootageEdit(instruction: "删除第 1 到 2 秒然后倒放"))
    }
}
