import UIKit
import XCTest

/// 最小可验收回归（保留现有 Duel 大厅、输入、战斗和结算代码，不加载任何 SF3 素材）：
/// 从首页 → 小游戏 → 裂隙对决大厅选刘泉纬对阵孙登 → 30 秒内进局 →
/// 实际按方向键和攻击键打中孙登，验证孙登扣血、受击与击退。
final class DuelOriginalMinimalFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func parseStat(_ app: XCUIApplication, side: Int, key: String) -> Int? {
        let el = app.staticTexts["duel.stats.\(side)"]
        guard el.exists, let raw = el.value as? String, let range = raw.range(of: "\(key) ") else { return nil }
        let field = raw[range.upperBound...].split(separator: "，").first ?? ""
        return Int(field.filter { $0.isNumber || $0 == "-" })
    }

    private func reveal(_ button: XCUIElement, containers: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if button.exists && button.isHittable { return true }
            for c in containers where c.exists {
                c.swipeUp()
                if button.exists && button.isHittable { return true }
            }
            usleep(200_000)
        }
        return button.exists && button.isHittable
    }

    func testLobbyLiuCanHitSunWithDamageAndKnockback() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        app.launch()

        // 1. Today → Games → Duel
        let games = app.buttons["games.enter"]
        let today = app.scrollViews.firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 15), "首页未打开")
        for _ in 0..<12 where !games.exists || !games.isHittable { today.swipeUp() }
        XCTAssertTrue(games.exists && games.isHittable, "首页找不到小游戏入口")
        games.tap()

        let duel = app.buttons["duel.enter"]
        XCTAssertTrue(reveal(duel, containers: [app.collectionViews.firstMatch, app.tables.firstMatch], timeout: 15),
                      "小游戏列表找不到裂隙对决")
        duel.tap()

        // 2. 现有大厅：选刘泉纬（默认对手孙登）并开局
        let liu = app.buttons["duel.hero.liu"]
        let roster = app.scrollViews["duel.lobby.roster"]
        let actions = app.scrollViews["duel.lobby.actions"]
        XCTAssertTrue(reveal(liu, containers: [roster, actions], timeout: 15), "大厅未显示刘泉纬选项")
        liu.tap()
        shot("duel-original-lobby")

        let start = app.buttons["duel.start"]
        XCTAssertTrue(reveal(start, containers: [actions], timeout: 10), "大厅未显示开始对战按钮")
        XCTAssertTrue(start.isEnabled, "开始对战按钮不可用")

        let t0 = CFAbsoluteTimeGetCurrent()
        start.tap()

        // 3. 30 秒内进局并出现现有 DuelControls 按键
        let light = app.buttons["duel.control.light"]
        let heavy = app.buttons["duel.control.heavy"]
        let right = app.buttons["duel.control.right"]
        XCTAssertTrue(light.waitForExistence(timeout: 30), "30 秒内未进入对战界面")
        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        XCTAssertLessThan(elapsed, 30.0, "进局耗时 \(elapsed)s 超过 30 秒")
        XCTAssertTrue(right.waitForExistence(timeout: 5), "缺少方向键")
        XCTAssertEqual(app.staticTexts["duel.name.0"].label, "刘泉纬")
        XCTAssertEqual(app.staticTexts["duel.name.1"].label, "孙登")

        let sunHPBefore = parseStat(app, side: 1, key: "生命")
        XCTAssertNotNil(sunHPBefore, "读取不到孙登初始生命")

        // 4. 实际按方向键接近孙登，再按攻击键，验证扣血与击退
        var damaged = false
        var knockedBack = false
        for attempt in 0..<10 {
            if let p0 = parseStat(app, side: 0, key: "位置"),
               let p1 = parseStat(app, side: 1, key: "位置"),
               abs(p1 - p0) > 1050 {
                let dir = p1 > p0 ? right : app.buttons["duel.control.left"]
                dir.press(forDuration: 0.35)
            }
            let posBeforeHit = parseStat(app, side: 1, key: "位置") ?? 0
            let hpBeforeHit = parseStat(app, side: 1, key: "生命") ?? (sunHPBefore ?? 1000)

            light.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            usleep(140_000)
            if heavy.exists {
                heavy.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            usleep(260_000)

            if attempt == 0 { shot("duel-original-combat") }

            let hpNow = parseStat(app, side: 1, key: "生命") ?? hpBeforeHit
            let posNow = parseStat(app, side: 1, key: "位置") ?? posBeforeHit
            if hpNow < (sunHPBefore ?? 1000) {
                damaged = true
                if posNow > posBeforeHit { knockedBack = true }
            }
            if damaged && knockedBack {
                shot("duel-original-after-hit")
                break
            }
        }
        XCTAssertTrue(damaged, "刘泉纬实际按键攻击后孙登未扣血（初始生命 \(sunHPBefore ?? -1)）")
        XCTAssertTrue(knockedBack, "孙登受击后未观察到击退位移")
    }
}
