import XCTest

final class GameDirectoryReviewTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testStarAdventureMenusFromDutyGames() {
        let app = openGames()
        defer { app.terminate() }
        app.buttons["games.tiles"].tap()
        let modes = app.buttons["tiles.modes"]
        reveal(modes, in: app)
        modes.tap()
        for (id, title) in [
            ("tiles.journeyContinue", "星际旅程"), ("tiles.collection", "星图修复"),
            ("tiles.expeditions", "分岔远征"), ("tiles.trials", "星约试炼"), ("tiles.starRails", "星轨移层")
        ] {
            let entry = app.buttons[id]
            reveal(entry, in: app)
            entry.tap()
            let page = app.navigationBars[title]
            XCTAssertTrue(page.waitForExistence(timeout: 10))
            capture(app, name: title)
            page.buttons["返回"].tap()
            XCTAssertTrue(app.navigationBars["星了个星"].waitForExistence(timeout: 8))
        }
    }

    func testArenaLobbyPanelsFromDutyGames() {
        let app = openGames()
        defer { app.terminate() }
        app.buttons["arena.enter"].tap()
        for (id, title) in [
            ("arena.menu.商店", "商店"), ("arena.menu.活动", "赛季"), ("arena.menu.好友", "好友"),
            ("arena.trophyRoad", "奖杯之路"), ("arena.menu.组队", "组队"), ("arena.settings", "设置")
        ] {
            let entry = app.buttons[id]
            XCTAssertTrue(entry.waitForExistence(timeout: 25), title)
            entry.tap()
            XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 10))
            let close = app.buttons["关上"]
            XCTAssertTrue(close.isHittable)
            capture(app, name: title)
            close.tap()
            XCTAssertTrue(entry.waitForExistence(timeout: 10))
        }
    }

    private func openGames() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        let duty = app.buttons["workspace.home.onDuty"]
        XCTAssertTrue(duty.waitForExistence(timeout: 12))
        duty.tap()
        let games = app.buttons["app.tab.游戏"]
        XCTAssertTrue(games.waitForExistence(timeout: 10))
        games.tap()
        XCTAssertTrue(app.navigationBars["小游戏"].waitForExistence(timeout: 8))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<15 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "game-panel-" + name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
