import XCTest

/// Walks ordinary navigation links in the demo account. The screenshot name records the actual destination.
final class DutyPageReviewTests: XCTestCase {
    func testSiteTabOpensLoginAndShowsOfflineRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        defer { app.terminate() }
        let duty = app.buttons["workspace.home.onDuty"]
        XCTAssertTrue(duty.waitForExistence(timeout: 12))
        duty.tap()
        let site = app.buttons["app.tab.网站"]
        XCTAssertTrue(site.waitForExistence(timeout: 10))
        site.tap()
        let open = app.buttons["打开网页登录"]
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        open.tap()
        let address = app.textFields["值班系统网址"]
        XCTAssertTrue(address.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["抓取本页"].isEnabled)

        address.tap()
        address.typeText("http://127.0.0.1:1/")
        app.buttons["前往"].tap()
        let retry = app.buttons["重试"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        XCTAssertFalse(app.buttons["设为同步地址"].isEnabled)
        retry.tap()
        XCTAssertTrue(app.staticTexts["网页未能打开。请核对网址和网络连接。"].waitForExistence(timeout: 12))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "duty-site-local-offline-retry"
        shot.lifetime = .keepAlways
        add(shot)
        app.navigationBars["网页登录"].buttons["完成"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        app.buttons["app.tab.今天"].tap()
        XCTAssertTrue(app.buttons["app.tab.网站"].isHittable)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testSchedulePagesFromSettingsDirectory() {
        review([
            ("本周全员", "本周全员"), ("按日查看", "值班表"), ("搜索成员", "搜索成员"),
            ("下次遥测", "遥测轮转预测"), ("节假日值班", "节假日值班"), ("排班预览", "排班预演"),
            ("排班变动记录", "排班变动历史"), ("换班记录", "全员换班记录"), ("换班账本", "换班账本"),
            ("请假规划", "请假规划"), ("待休变化", "待休趋势")
        ])
    }

    func testStatisticsAndWorkPagesFromSettingsDirectory() {
        review([
            ("工作量", "工作量统计"), ("全年统计", "全年统计"), ("年度总结", "年度总结"),
            ("历年统计", "历年统计"), ("均衡分析", "工作量均衡"), ("数据核对", "数据核对"),
            ("周会问题", "周会问题"), ("我负责的周会问题", "周会问题"), ("周会各组趋势", "各组趋势"),
            ("发数传计划", "发数传计划"), ("工作留痕", "工作留痕"), ("各组工作内容", "各组工作内容"), ("网站公告", "网站公告")
        ])
    }

    func testPreferencesAndHelpPagesFromSettingsDirectory() {
        review([
            ("小游戏", "小游戏"), ("规则说明", "规则说明"), ("自检与诊断", "自检与诊断"),
            ("自动同步设置向导", "自动同步设置"), ("身份", "身份"), ("备份与恢复", "备份与恢复"),
            ("今天页的卡片", "今天页的卡片")
        ])
    }

    func testMemberRowsAndHolidaySummaryFromDirectory() {
        review([("搜索成员", "搜索成员"), ("节假日值班", "节假日值班")]) { feature, app in
            if feature == "搜索成员" {
                let member = app.buttons.matching(identifier: "duty.member.row").firstMatch
                XCTAssertTrue(member.waitForExistence(timeout: 6))
                XCTAssertFalse(member.label.contains("点击查看排班与共同休息日"))
            } else {
                let empty = app.staticTexts["暂无节假日排班"]
                let row = app.descendants(matching: .any).matching(identifier: "duty.holiday.row").firstMatch
                XCTAssertTrue(empty.exists || row.exists, "应显示节假日排班或明确的空状态")
            }
        }
    }

    private func review(_ routes: [(String, String)], verify: ((String, XCUIApplication) -> Void)? = nil) {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        defer { app.terminate() }
        let duty = app.buttons["workspace.home.onDuty"]
        XCTAssertTrue(duty.waitForExistence(timeout: 12))
        duty.tap()
        let settings = app.buttons["app.tab.设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 12))
        settings.tap()
        let all = app.buttons["settings.duty.directory"]
        scrollToDutyControl(all, in: app)
        all.tap()
        let directory = app.navigationBars["全部功能"]
        XCTAssertTrue(directory.waitForExistence(timeout: 8))

        for (feature, destination) in routes {
            XCTContext.runActivity(named: "全部功能 › " + feature) { activity in
                let row = app.buttons["duty.feature." + feature]
                scrollToDutyControl(row, in: app)
                row.tap()
                let page = app.navigationBars[destination]
                XCTAssertTrue(page.waitForExistence(timeout: 8), feature)
                verify?(feature, app)
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "duty-page-" + feature
                shot.lifetime = .keepAlways
                activity.add(shot)
                XCTAssertFalse(settings.isHittable)
                let back = page.buttons.matching(NSPredicate(
                    format: "identifier == 'BackButton' OR label CONTAINS '全部功能' OR label == '返回' OR label == 'Back'"
                )).firstMatch
                XCTAssertTrue(back.waitForExistence(timeout: 4) && back.isHittable, "没有返回全部功能的导航按钮：\(feature)")
                back.tap()
                XCTAssertTrue(directory.waitForExistence(timeout: 8))
            }
        }
    }


}

/// Native hit testing includes partly visible rows. Bring their centers clear of navigation and search chrome.
func scrollToDutyControl(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let screen = app.frame
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
    for _ in 0..<30 {
        if element.exists {
            let frame = element.frame
            if element.isHittable && frame.midY > screen.minY + 100 && frame.midY < screen.maxY - 44 {
                let center = CGPoint(x: frame.midX, y: frame.midY)
                let searchOverRow = app.searchFields.allElementsBoundByIndex.contains {
                    $0.isHittable && $0.frame.contains(center)
                }
                if !searchOverRow { return }
            }
            if !frame.isEmpty && frame.midY < screen.minY + 100 {
                end.press(forDuration: 0.05, thenDragTo: start)
                continue
            }
        }
        start.press(forDuration: 0.05, thenDragTo: end)
    }
    XCTFail("无法把控件滚动到可见内容区：\(element.description)", file: file, line: line)
}
