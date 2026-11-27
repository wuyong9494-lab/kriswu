import XCTest

/// A fresh installation on the isolated simulator. Both identity changes use the visible account UI.
final class FirstUseRoleBoundaryTests: XCTestCase {
    func testFirstUseAndGuestAccessFromTheLauncher() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }
        dismissNotificationRequestIfPresent()

        tap(app.buttons["workspace.home.wumind"])
        let register = app.buttons["wumind.registration.submit"]
        XCTAssertTrue(register.waitForExistence(timeout: 8))
        XCTAssertFalse(register.isEnabled)
        capture("first-use-wumind-registration", app: app)
        tap(app.buttons["wumind.registration.backHome"])
        tap(app.buttons["workspace.home.onDuty"])

        for (title, action, name) in [
            ("欢迎使用值班提醒", "开始设置", "welcome"),
            ("连接值班网站", "跳过", "connect"),
            ("选一下你是谁", "跳过", "roster"),
            ("打开提醒", "下一步", "notifications")
        ] {
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 8), title)
            capture("first-use-" + name, app: app)
            tap(app.buttons[action])
        }

        dismissNotificationRequestIfPresent()
        XCTAssertTrue(app.staticTexts["设置好了"].waitForExistence(timeout: 8))
        capture("first-use-complete", app: app)
        tap(app.buttons["开始使用"])
        tap(app.buttons["app.tab.设置"])

        tap(app.buttons["settings.role"])
        let admin = app.buttons["登录为管理员"]
        let manager = app.buttons["登录为管理者"]
        XCTAssertTrue(admin.waitForExistence(timeout: 8))
        XCTAssertFalse(admin.isEnabled)
        XCTAssertFalse(manager.isEnabled)
        capture("role-ordinary-account", app: app)
        let back = app.navigationBars["身份"].buttons.matching(NSPredicate(
            format: "identifier == 'BackButton' OR label CONTAINS '设置' OR label == '返回' OR label == 'Back'"
        )).firstMatch
        tap(back)
        // The privileged link would be right after the conversation preferences in this section.
        XCTAssertTrue(app.buttons["settings.wumindPreferences"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["settings.wumindAdmin"].exists)
        tap(app.buttons["settings.externalAuth"])
        tap(app.buttons["external.auth.guest"])
        tap(app.buttons["app.tab.我的"])
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "外部访客模式")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["app.tab.设置"].exists)
        XCTAssertFalse(app.buttons["settings.wumindAdmin"].exists)
        capture("role-local-guest", app: app)

        if #available(iOS 16.4, *) {
            // A URL launch creates a new scene at the launcher. The guest identity must survive it.
            app.terminate()
            app.open(try XCTUnwrap(URL(string: "shiftreminder://capture/note")))
        } else {
            tap(app.buttons["app.tab.WUMIND"])
            tap(app.buttons["wumind.registration.backHome"])
        }
        let duty = app.buttons["workspace.home.onDuty"]
        XCTAssertTrue(duty.waitForExistence(timeout: 8) && duty.isHittable)
        XCTAssertFalse(app.buttons["worklog.note.save"].exists)
        XCTAssertFalse(app.buttons["app.tab.设置"].exists)
        capture("role-guest-cold-launch", app: app)
        tap(duty)
        capture("role-guest-duty-denied", app: app)
        let wumind = app.buttons["workspace.home.wumind"]
        XCTAssertTrue(wumind.isHittable)
        XCTAssertFalse(app.buttons["app.tab.今天"].exists)
        tap(wumind)
        tap(app.buttons["app.tab.我的"])
        XCTAssertTrue(app.buttons["external.profile.bindAccount"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "外部访客模式")).firstMatch.exists)

    }

    private func dismissNotificationRequestIfPresent() {
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 4) {
            let deny = permission.buttons.matching(NSPredicate(
                format: "label IN %@", ["不允许", "Don’t Allow", "Don't Allow"]
            )).firstMatch
            tap(deny)
        }
    }

    private func tap(_ button: XCUIElement) {
        XCTAssertTrue(button.waitForExistence(timeout: 8) && button.isHittable, button.description)
        button.tap()
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
