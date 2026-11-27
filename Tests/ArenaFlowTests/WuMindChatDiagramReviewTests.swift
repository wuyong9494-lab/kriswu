import XCTest

final class WuMindChatDiagramReviewTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testChatMermaidSourceGraphAndFullScreenRoundTrip() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "wumind", "-wumind-chat-pages-qa"]
        app.launch()
        defer { app.terminate() }

        let scroll = app.scrollViews["wumind.transcript.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        let toggle = app.buttons["wumind.rich.diagram.toggle"]
        for _ in 0..<8 {
            if toggle.exists && toggle.isHittable && scroll.frame.contains(toggle.frame) { break }
            if toggle.exists && !toggle.frame.isEmpty && toggle.frame.midY < scroll.frame.minY {
                scroll.swipeDown(velocity: .slow)
            } else {
                scroll.swipeUp(velocity: .slow)
            }
        }
        let copy = app.buttons["wumind.rich.diagram.copy"]
        let expand = app.buttons["wumind.rich.diagram.expand"]
        checkAction(toggle, label: "查看源码")
        checkAction(copy, label: "复制图表源码")
        checkAction(expand, label: "全屏查看图表")
        checkNodes(in: app)
        capture("chat-mermaid-inline")

        toggle.tap()
        checkAction(toggle, label: "查看图形")
        let source = app.descendants(matching: .any).matching(identifier: "wumind.rich.diagram.source").firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(source.label.contains("flowchart TD"))
        XCTAssertTrue(source.label.contains("A[读取资料] --> B[核对原文]"))
        XCTAssertFalse(app.staticTexts["wumind.rich.diagram.node.A"].exists)
        XCTAssertFalse(expand.exists)
        capture("chat-mermaid-source")

        toggle.tap()
        XCTAssertFalse(source.exists)
        checkAction(toggle, label: "查看源码")
        checkNodes(in: app)
        expand.tap()
        let title = app.staticTexts["wumind.rich.diagram.fullTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertEqual(title.label, "Mermaid 流程图")
        let canvas = app.scrollViews.matching(identifier: "wumind.rich.diagram.fullCanvas").firstMatch
        XCTAssertTrue(canvas.exists)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(canvas.frame.width, window.width * 0.94)
        XCTAssertGreaterThan(canvas.frame.height, window.height * 0.70)
        checkNodes(in: canvas)
        let done = app.buttons["wumind.rich.diagram.done"]
        checkAction(done, label: "完成")
        capture("chat-mermaid-full-screen")

        done.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertFalse(title.exists)
        checkAction(toggle, label: "查看源码")
        checkNodes(in: app)
    }

    private func checkNodes(in scope: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let input = scope.staticTexts["wumind.rich.diagram.node.A"]
        let result = scope.staticTexts["wumind.rich.diagram.node.B"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(input.label, "读取资料", file: file, line: line)
        XCTAssertEqual(result.label, "核对原文", file: file, line: line)
        XCTAssertLessThan(input.frame.midY, result.frame.midY, "TD 流程的两个实际节点应从上至下排列", file: file, line: line)
    }

    private func checkAction(_ button: XCUIElement, label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(button.isHittable, label, file: file, line: line)
        XCTAssertEqual(button.label, label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(button.frame.width, 44, label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(button.frame.height, 44, label, file: file, line: line)
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
