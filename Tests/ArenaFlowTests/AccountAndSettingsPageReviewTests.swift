import XCTest

final class AccountAndSettingsPageReviewTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testExternalAccountWalletAndRechargeGuideFromLauncher() {
        let app = XCUIApplication()
        app.launchArguments = ["-reviewDemo", "NO", "-app.accessRole.v1", "externalUser"]
        app.launch()
        defer { app.terminate() }

        tap(app.buttons["workspace.home.wumind"], in: app)
        tap(app.buttons["app.tab.我的"], in: app)
        expectPage("我的", in: app)
        XCTAssertFalse(app.buttons["app.tab.设置"].exists)
        tap(app.buttons["钱包与用量"], in: app)
        reviewPage("WUMIND 钱包与计费", name: "account-wallet", in: app)
        let guide = app.buttons["wumind.wallet.guideToolbar"]
        tap(guide, in: app)
        reviewPage("充值与计费说明", name: "account-recharge-guide", in: app)
        closeSheet("充值与计费说明", button: "完成", returningTo: "WUMIND 钱包与计费", in: app)
        closeSheet("WUMIND 钱包与计费", button: "完成", returningTo: "我的", in: app)
        XCTAssertTrue(app.buttons["external.profile.bindAccount"].isHittable)
    }

    func testWorksFromLauncherReturnsToChat() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        defer { app.terminate() }

        tap(app.buttons["workspace.home.wumind"], in: app)
        tap(app.buttons["wumind.tab.works"], in: app)
        let search = app.textFields["搜索标题、提示词或模型"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        let emptyLibrary = app.staticTexts["暂无作品"]
        if emptyLibrary.exists {
            screenshot("account-works-empty", in: app)
        } else {
            // The same simulator can contain local projects saved by an earlier editing test.
            search.tap()
            search.typeText("no-matching-work-" + UUID().uuidString)
            XCTAssertTrue(app.staticTexts["未找到作品"].waitForExistence(timeout: 5))
            screenshot("account-works-empty-search", in: app)
            search.typeText("\n")
        }
        tap(app.buttons["wumind.tab.chat"], in: app)
        XCTAssertTrue(app.buttons["wumind.model.picker"].waitForExistence(timeout: 8))
    }

    func testAdministratorAndDutySettingsFromLauncher() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        defer { app.terminate() }

        tap(app.buttons["workspace.home.onDuty"], in: app)
        tap(app.buttons["app.tab.设置"], in: app)
        expectPage("设置", in: app)
        tap(app.buttons["settings.wumindAdmin"], in: app)
        expectPage("商业计费管理", in: app)

        for (id, name) in [
            ("wumind.admin.userDirectory", "admin-users-gateway-required"),
            ("wumind.admin.modelCatalog", "admin-pricing-gateway-required")
        ] {
            tap(app.buttons[id], in: app)
            reviewPage("需要配置网关", name: name, in: app)
            XCTAssertTrue(app.staticTexts["尚未配置计费网关连接"].exists)
            pop("需要配置网关", to: "商业计费管理", in: app)
        }
        tap(app.buttons["wumind.admin.payments"], in: app)
        reviewPage("充值与支付", name: "admin-payments", in: app)
        pop("充值与支付", to: "商业计费管理", in: app)
        tap(app.buttons["wumind.admin.gateway"], in: app)
        expectPage("网关与诊断", in: app)
        tap(app.buttons["wumind.admin.guide"], in: app)
        reviewPage("管理员配置教程", name: "admin-setup-guide", in: app)
        closeSheet("管理员配置教程", button: "关闭", returningTo: "网关与诊断", in: app)
        pop("网关与诊断", to: "商业计费管理", in: app)
        pop("商业计费管理", to: "设置", in: app)

        tap(app.buttons["settings.wumindPreferences"], in: app)
        reviewPage("WuMind 设置", name: "settings-wumind-account", in: app)
        for (title, name) in [
            ("个性化与记忆", "settings-wumind-memory"),
            ("上下文与智能体", "settings-wumind-context"),
            ("数据与诊断", "settings-wumind-data")
        ] {
            tap(app.buttons[title], in: app)
            reviewPage(title, name: name, in: app)
            pop(title, to: "WuMind 设置", in: app)
        }
        closeSheet("WuMind 设置", button: "完成", returningTo: "设置", in: app)

        tap(app.buttons["settings.reminders"], in: app)
        reviewPage("提醒", name: "settings-reminders", in: app)
        pop("提醒", to: "设置", in: app)
        tap(app.buttons["settings.appearance"], in: app)
        reviewPage("外观与显示", name: "settings-appearance", in: app)
        tap(app.buttons["今天页的卡片"], in: app)
        reviewPage("今天页的卡片", name: "settings-today-layout", in: app)
        pop("今天页的卡片", to: "外观与显示", in: app)
        tap(app.buttons["班次类型与颜色"], in: app)
        reviewPage("班次类型", name: "settings-shift-types", in: app)
        tap(app.buttons["settings.shiftType.day"], in: app)
        reviewPage("白班", name: "settings-shift-editor", in: app)
        XCTAssertTrue(app.textFields.firstMatch.exists)
        pop("白班", to: "班次类型", in: app)
        pop("班次类型", to: "外观与显示", in: app)
        pop("外观与显示", to: "设置", in: app)
        tap(app.buttons["settings.dutySpecific"], in: app)
        reviewPage("值班专用设置", name: "settings-duty", in: app)
        tap(app.buttons["settings.rosterAccount"], in: app)
        reviewPage("账号与同步", name: "settings-roster-account", in: app)
        tap(app.buttons["从全员名单里选我是谁"], in: app)
        reviewPage("我是谁", name: "settings-roster-identity", in: app)
        pop("我是谁", to: "账号与同步", in: app)
        pop("账号与同步", to: "值班专用设置", in: app)
        pop("值班专用设置", to: "设置", in: app)
    }

    private func expectPage(_ title: String, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 8), "未到达" + title)
    }

    private func screenshot(_ name: String, in app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func reviewPage(_ title: String, name: String, in app: XCUIApplication) {
        expectPage(title, in: app)
        screenshot(name, in: app)
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        if !element.waitForExistence(timeout: 3) || !element.isHittable {
            let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
            let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.36))
            for _ in 0..<5 where !element.isHittable {
                lower.press(forDuration: 0.05, thenDragTo: upper)
            }
            for _ in 0..<8 where !element.isHittable {
                upper.press(forDuration: 0.05, thenDragTo: lower)
            }
        }
        XCTAssertTrue(element.isHittable, element.description)
        element.tap()
    }

    private func closeSheet(_ title: String, button: String, returningTo parent: String, in app: XCUIApplication) {
        app.navigationBars[title].buttons[button].tap()
        expectPage(parent, in: app)
    }

    private func pop(_ title: String, to parent: String, in app: XCUIApplication) {
        let back = app.navigationBars[title].buttons.matching(NSPredicate(
            format: "identifier == 'BackButton' OR label CONTAINS %@ OR label == '返回' OR label == 'Back'", parent
        )).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5) && back.isHittable, "缺少返回" + parent + "的按钮")
        back.tap()
        expectPage(parent, in: app)
    }
}
