import XCTest
import UIKit

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
        for (id, title, bodyLabel) in [
            ("arena.menu.商店", "商店", "小时换特惠"), ("arena.menu.活动", "赛季", "排位"),
            ("arena.menu.好友", "好友", "加上"), ("arena.trophyRoad", "奖杯之路", "30 金币"),
            ("arena.menu.组队", "组队", "进房间"), ("arena.settings", "设置", "一键连续性能诊断 / 导出")
        ] {
            let entry = app.buttons[id]
            XCTAssertTrue(entry.waitForExistence(timeout: 25), title)
            entry.tap()
            let heading = app.staticTexts[title].firstMatch
            XCTAssertTrue(heading.waitForExistence(timeout: 10))
            let close = app.buttons[title == "设置" ? "关闭设置" : "关上"]
            XCTAssertTrue(close.isHittable)
            let bodyText = NSPredicate(format: title == "商店" ? "label ENDSWITH %@" : "label == %@", bodyLabel)
            let body = app.descendants(matching: .any).matching(bodyText).firstMatch
            XCTAssertTrue(body.waitForExistence(timeout: 8), bodyLabel)
            capture(app, name: title)
            let window = app.windows.firstMatch.frame
            let bounds = window.insetBy(dx: -1, dy: -1)
            for item in [heading, close, body] {
                XCTAssertFalse(item.frame.isEmpty, title)
                XCTAssertTrue(bounds.contains(item.frame), "\(title)：\(item.frame) 超出窗口 \(window)")
            }
            XCTAssertLessThan(heading.frame.maxX, close.frame.minX, title)
            XCTAssertGreaterThan(close.frame.midX, window.midX, title)
            XCTAssertGreaterThan(body.frame.midY, heading.frame.midY, title)
            if ["商店", "赛季", "好友", "组队"].contains(title) {
                XCTAssertGreaterThan(body.frame.midX, window.midX, "\(title)：右侧正文或操作应完整显示")
            }
            print("ARENA_PANEL \(title) window=\(window) heading=\(heading.frame) close=\(close.frame) body=\(body.frame)")
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
        // The application's image can be cropped a second time during a portrait-to-landscape transition.
        let screen = XCUIScreen.main.screenshot().image
        guard let raster = screen.cgImage else { return XCTFail("没有可导出的屏幕像素") }
        let sideways = [.left, .leftMirrored, .right, .rightMirrored].contains(screen.imageOrientation)
        let pixels = CGSize(width: CGFloat(sideways ? raster.height : raster.width),
                            height: CGFloat(sideways ? raster.width : raster.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let upright = UIGraphicsImageRenderer(size: pixels, format: format).image { _ in
            screen.draw(in: CGRect(origin: .zero, size: pixels))
        }
        let shot = XCTAttachment(image: upright)
        shot.name = "game-panel-" + name
        shot.lifetime = .keepAlways
        add(shot)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.height, 0)
        XCTAssertEqual(pixels.width / pixels.height, window.width / window.height, accuracy: 0.025,
                       "\(name)：完整屏幕像素 \(pixels) 与窗口 \(window) 的方向和比例应一致")
        print("GAME_PANEL_SCREEN \(name) devicePixels=\(pixels) windowPoints=\(window.size)")
    }
}
