import XCTest

extension DeepSeekChatNavigationTests {
    func testExternalLoginFormAllowsKeyboardDismissAndMethodSwitch() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "onboarding"]
        app.launch()
        defer { app.terminate() }
        let login = app.buttons["onboarding.externalAuth"]
        XCTAssertTrue(login.waitForExistence(timeout: 10))
        login.tap()
        let phone = app.textFields["external.auth.phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5))
        phone.tap()
        phone.typeText("1")
        let dismissKeyboard = app.buttons["收起键盘"]
        if app.keyboards.firstMatch.exists {
            XCTAssertTrue(dismissKeyboard.isHittable)
            dismissKeyboard.tap()
        }
        XCTAssertFalse(app.buttons["external.auth.sendSMS"].isEnabled)
        XCTAssertFalse(app.buttons["external.auth.submitPhone"].isEnabled)
        let form = XCTAttachment(screenshot: app.screenshot())
        form.name = "External-login-phone"
        form.lifetime = .keepAlways
        add(form)

        app.segmentedControls.buttons["微信登录"].tap()
        XCTAssertTrue(app.textFields["external.auth.wechatCode"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["external.auth.submitWeChat"].isEnabled)
        XCTAssertTrue(app.buttons["external.auth.guest"].exists)
        app.navigationBars.buttons["关闭"].tap()
        XCTAssertTrue(login.waitForExistence(timeout: 5))
    }
}
