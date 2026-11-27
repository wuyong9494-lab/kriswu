import XCTest

final class WuMindChatReviewTests: XCTestCase {
    func testSharedMaterialAndComparisonLeadToActualChannelChooser() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "wumind", "-wumind-chat-pages-qa"]
        app.launch()
        defer { app.terminate() }

        func capture(_ name: String) {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "ChatReview-" + name
            shot.lifetime = .keepAlways
            add(shot)
        }
        func checkTapTarget(_ element: XCUIElement, line: UInt = #line) {
            XCTAssertTrue(element.waitForExistence(timeout: 8), line: line)
            XCTAssertTrue(element.isHittable, line: line)
            XCTAssertGreaterThanOrEqual(element.frame.height, 44, line: line)
        }
        func reveal(_ button: XCUIElement, in scroll: XCUIElement) {
            for _ in 0..<4 where !button.isHittable { scroll.swipeUp() }
            XCTAssertTrue(button.isHittable)
        }

        let shared = app.buttons["wumind.sharedMaterials.pill"]
        checkTapTarget(shared)
        shared.tap()
        let materials = app.navigationBars["对话共享资料"]
        XCTAssertTrue(materials.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["资料核对.txt"].exists)
        let remove = app.buttons["移除 资料核对.txt"]
        checkTapTarget(remove)
        capture("shared-file")
        remove.tap()
        XCTAssertTrue(app.staticTexts["暂无共享资料"].waitForExistence(timeout: 6))
        capture("shared-empty")
        materials.buttons["完成"].tap()
        XCTAssertFalse(shared.exists)

        let compare = app.buttons["wumind.turn.compare"]
        reveal(compare, in: app.scrollViews["wumind.transcript.scroll"])
        checkTapTarget(compare)
        compare.tap()
        let comparison = app.navigationBars["同题对比与交叉复核"]
        XCTAssertTrue(comparison.waitForExistence(timeout: 8))
        let independent = app.buttons["独立同题对比"]
        XCTAssertTrue(independent.waitForExistence(timeout: 5))
        independent.tap()
        XCTAssertTrue(independent.isSelected)
        XCTAssertTrue(app.staticTexts["没有可选的第二个模型"].exists)
        capture("comparison")
        let modelAction = app.buttons["打开模型中心"]
        if !modelAction.isHittable { app.swipeUp() }
        XCTAssertTrue(modelAction.isHittable)
        modelAction.tap()

        let hub = app.navigationBars["WUMIND 模型与能力中心"]
        XCTAssertTrue(hub.waitForExistence(timeout: 8))
        let builtin = app.buttons["wumind.channel.managed"]
        let own = app.buttons["wumind.channel.ownAPI"]
        checkTapTarget(builtin)
        checkTapTarget(own)
        XCTAssertTrue(builtin.isSelected)
        capture("managed-channel")
        own.tap()
        XCTAssertTrue(own.isSelected)
        let providers = app.buttons["wumind.provider.menu"]
        XCTAssertTrue(providers.waitForExistence(timeout: 5))
        capture("own-channel")
        providers.tap()
        XCTAssertTrue(app.buttons["Anthropic Claude"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["OpenRouter"].exists)
    }
}
