import XCTest
@testable import ShiftCore

final class WuMindTranscriptPresentationTests: XCTestCase {
    func testShortAnswersRemainVisibleAndLongResponsesFold() {
        XCTAssertFalse(WuMindTranscriptPresentation.shouldFoldAnswer("今天天气不错。"))
        XCTAssertFalse(WuMindTranscriptPresentation.shouldFoldAnswer(String(repeating: "字", count: 700)))
        XCTAssertTrue(WuMindTranscriptPresentation.shouldFoldAnswer(String(repeating: "字", count: 701)))
        let longCode = (0..<13).map { "let a\($0) = 1" }.joined(separator: "\n")
        XCTAssertTrue(WuMindTranscriptPresentation.shouldFoldAnswer(longCode))
    }

    func testPreviewDoesNotSplitVisibleUnicodeCharacters() {
        let glyph = "👩🏻‍💻"
        let output = WuMindTranscriptPresentation.answerPreview(String(repeating: glyph, count: 10_000))
        XCTAssertEqual(output, String(repeating: glyph, count: 250))
    }

    func testUserCanDetachFromStreamingAndExplicitlyResume() {
        var follow = WuMindScrollFollowState()
        follow.handleUserDrag(translationY: 12, isGenerating: true)
        XCTAssertFalse(follow.shouldAutoScrollOnStreamTick)
        follow.jumpToLatest()
        XCTAssertTrue(follow.shouldAutoScrollOnStreamTick)
        follow.pauseFollow()
        XCTAssertFalse(follow.shouldAutoScrollOnStreamTick)
    }
}
