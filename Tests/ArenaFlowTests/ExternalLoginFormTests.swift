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

    func testExternalRoleOpensProfileAndPhoneLogin() {
        let app = XCUIApplication()
        app.launchArguments = ["-reviewDemo", "NO", "-app.accessRole.v1", "externalUser"]
        app.launch()
        defer { app.terminate() }

        let workspace = app.buttons["workspace.home.wumind"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 10))
        workspace.tap()
        let profile = app.buttons["app.tab.我的"]
        XCTAssertTrue(profile.waitForExistence(timeout: 8))
        profile.tap()
        let account = app.buttons["external.profile.bindAccount"]
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["app.tab.设置"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "External-account-profile"
        capture.lifetime = .keepAlways
        add(capture)

        account.tap()
        XCTAssertTrue(app.textFields["external.auth.phone"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["external.auth.submitPhone"].isEnabled)
        app.navigationBars.buttons["关闭"].tap()
        XCTAssertTrue(account.waitForExistence(timeout: 5))
    }

    func testDutySettingsOpensEncryptedSync() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        defer { app.terminate() }
        let duty = app.buttons["workspace.home.onDuty"]
        XCTAssertTrue(duty.waitForExistence(timeout: 10))
        duty.tap()
        let updates = app.navigationBars["新功能"].buttons["知道了"]
        if updates.exists { updates.tap() }
        let settings = app.buttons["app.tab.设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        let preferences = app.buttons["settings.wumindPreferences"]
        for _ in 0..<4 where !preferences.isHittable { app.swipeUp() }
        XCTAssertTrue(preferences.isHittable)
        preferences.tap()
        let sync = app.buttons["wumind.settings.sync"]
        for _ in 0..<4 where !sync.isHittable { app.swipeUp() }
        XCTAssertTrue(sync.isHittable)
        sync.tap()
        XCTAssertTrue(app.secureTextFields["wumind.sync.passphrase"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["wumind.sync.push"].isEnabled)
        app.navigationBars["跨设备加密同步"].buttons["完成"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
    }

}
