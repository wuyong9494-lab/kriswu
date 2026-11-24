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

        for id in ["live", "image", "speech", "code", "work"] {
            XCTAssertTrue(app.buttons["ai.tools." + id].exists, "Missing tool " + id)
        }

        let live = app.buttons["ai.tools.live"]
        XCTAssertTrue(live.isHittable)
        live.tap()
        XCTAssertTrue(app.staticTexts["ai.live.status"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["ai.live.start"].exists)
        XCTAssertFalse(app.buttons["ai.live.end"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let gemini = app.buttons["ai.provider.gemini"]
        if !gemini.isHittable { app.swipeUp() }
        XCTAssertTrue(gemini.isHittable)
        app.buttons["ai.provider.gemini"].tap()
        let composer = app.descendants(matching: .any).matching(identifier: "ai.chat.composer").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["ai.chat.send"].isEnabled)
    }

    func testDutyWorkbenchPassPlanAndTenderNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "today"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }

        let workbench = app.descendants(matching: .any)
            .matching(identifier: "today.dutyWorkbench").firstMatch
        XCTAssertTrue(workbench.waitForExistence(timeout: 15), "值班工作台卡片未显示")

        let planButton = app.buttons["today.workbench.plan"]
        let handoffButton = app.buttons["today.workbench.handoff"]
        XCTAssertTrue(planButton.waitForExistence(timeout: 8) || handoffButton.exists, "值班工作台缺少计划或交班入口")
        if planButton.exists && planButton.isHittable {
            planButton.tap()
            let shotPlan = XCTAttachment(screenshot: app.screenshot())
            shotPlan.name = "duty-passplan-review"
            shotPlan.lifetime = .keepAlways
            add(shotPlan)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        let deepSeek = app.buttons["today.deepSeekChat"]
        XCTAssertTrue(deepSeek.waitForExistence(timeout: 10))
        deepSeek.tap()

        let tenderBtn = app.buttons["deepSeek.chat.tender"]
        XCTAssertTrue(tenderBtn.waitForExistence(timeout: 10), "DeepSeek 页面缺少生成投标书草稿入口")
        tenderBtn.tap()

        let importBtn = app.buttons["deepSeek.tender.import"]
        XCTAssertTrue(importBtn.waitForExistence(timeout: 10), "投标书草稿页未正常打开")
        let shotTender = XCTAttachment(screenshot: app.screenshot())
        shotTender.name = "duty-tender-draft"
        shotTender.lifetime = .keepAlways
        add(shotTender)
    }
}
