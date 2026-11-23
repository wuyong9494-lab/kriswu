import XCTest

/// Exercises the home entry without a real API key or outbound chat request.
final class DeepSeekChatNavigationTests: XCTestCase {
    func testOpenChatFromHomeAndReturn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "today"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }

        let entry = app.buttons["today.deepSeekChat"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        XCTAssertTrue(entry.isHittable)
        entry.tap()

        let nav = app.navigationBars["DeepSeek"]
        XCTAssertTrue(nav.waitForExistence(timeout: 10))
        let composer = app.descendants(matching: .any)
            .matching(identifier: "deepSeek.chat.composer").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "DeepSeek-chat"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        nav.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
    }
    func testProviderChooserOpensWithoutContactingAI() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "today"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }

        let home = app.buttons["today.deepSeekChat"]
        XCTAssertTrue(home.waitForExistence(timeout: 15))
        home.tap()
        let switcher = app.buttons["ai.providers.open"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 10))
        switcher.tap()

        for id in ["openAI", "gemini", "claude", "grok"] {
            XCTAssertTrue(app.buttons["ai.provider." + id].exists, "Missing provider " + id)
        }
        app.buttons["ai.provider.gemini"].tap()
        let composer = app.descendants(matching: .any).matching(identifier: "ai.chat.composer").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["ai.chat.send"].isEnabled)
    }

}
