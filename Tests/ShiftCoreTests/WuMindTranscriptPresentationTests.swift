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

    func testStreamingBlocksRetainVerbatimTextAcrossReplacementsAndSplitLineEndings() {
        var answer = WuMindStreamingAnswer()
        let longLine = String(repeating: "👩🏻‍💻", count: 300)
        answer.append(longLine + "\r")
        XCTAssertTrue(answer.completeBlocks.isEmpty)
        answer.append("\n第二段\n\n")
        XCTAssertEqual(answer.completeBlocks, [longLine])
        XCTAssertEqual(answer.tail, "第二段\n\n")
        XCTAssertEqual(answer.text, longLine + "\r\n第二段\n\n")
        let revision = answer.revision
        answer.replace(with: "甲")
        answer.replace(with: "乙")
        XCTAssertGreaterThan(answer.revision, revision)
        XCTAssertEqual(answer.text, "乙")
        XCTAssertEqual(answer.tail, "乙")
        XCTAssertTrue(answer.completeBlocks.isEmpty)
    }

    func testLongMultiParagraphStreamKeepsCompletedBlocksStableAtEveryFlush() {
        var answer = WuMindStreamingAnswer()
        var input = ""
        var previousCount = 0
        var fullBytes = 0
        var changedBytes = 0
        for index in 1...1_500 {
            let delta = "第\(index)段：核对输入、处理过程和输出结果。\n\n"
            input += delta
            answer.append(delta)
            guard index.isMultiple(of: 6) else { continue }
            fullBytes += answer.text.utf8.count
            changedBytes += answer.completeBlocks[previousCount...].reduce(0) { $0 + $1.utf8.count }
            changedBytes += answer.tail.utf8.count
            previousCount = answer.completeBlocks.count
        }
        XCTAssertEqual(answer.text, input)
        XCTAssertEqual((answer.completeBlocks + [answer.tail]).joined(separator: "\n"), input)
        XCTAssertLessThan(changedBytes, fullBytes / 10)
        print("WUMIND_TEXT identicalInputBytes=\(input.utf8.count) flushes=250 fullBodyBytes=\(fullBytes) changedBlockBytes=\(changedBytes)")
    }

    func testScrollFollowsOverflowAndSkipsContentThatFitsOrHasSettled() {
        let heights: [Double] = [75, 100, 100, 105, 100, 100.5, 120, 100]
        let requests = heights.filter {
            WuMindTranscriptPresentation.needsScrollToRevealBottom(contentBottom: $0, viewportHeight: 100)
        }
        XCTAssertEqual(requests, [105, 120])
        XCTAssertFalse(WuMindTranscriptPresentation.needsScrollToRevealBottom(contentBottom: 500, viewportHeight: 0))
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
