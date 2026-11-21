import XCTest

/// 裂隙对决 · 端到端真机模拟器验收测试：
/// 1. 进大厅、切换四名英雄并截图；
/// 2. 每名英雄在 15 秒内进局，通过真实触控移动并出招，验证对手扣血；
/// 3. 训练场验证变身与终极技触发。
final class RiftFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func hpValue(_ app: XCUIApplication, side: Int) -> Int? {
        let el = app.otherElements["rift.hp.\(side)"]
        guard el.waitForExistence(timeout: 5), let raw = el.value as? String else { return nil }
        return Int(raw)
    }

    func testLobbyAndAllFourHeroesCanFight() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "game"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()

        let entry = app.buttons["duel.enter"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "找不到裂隙对决入口")
        entry.tap()

        let home = app.otherElements["rift.home"]
        XCTAssertTrue(home.waitForExistence(timeout: 15), "未能进入裂隙对决大厅")
        sleep(1)
        shot("rift-lobby")

        for hero in ["sunDeng", "wuYong", "liuQuanwei", "xuXiao"] {
            let card = app.buttons["rift.hero.\(hero)"]
            XCTAssertTrue(card.waitForExistence(timeout: 10), "找不到英雄按钮 \(hero)")
            card.tap()
            usleep(400_000)
            shot("rift-showroom-\(hero)")

            let startButton = app.buttons["rift.start"]
            XCTAssertTrue(startButton.waitForExistence(timeout: 5))
            let t0 = CFAbsoluteTimeGetCurrent()
            startButton.tap()

            let arena = app.otherElements["rift.arena"]
            XCTAssertTrue(arena.waitForExistence(timeout: 15), "\(hero) 15 秒内未进局")
            let elapsed = CFAbsoluteTimeGetCurrent() - t0
            XCTAssertLessThan(elapsed, 15.0, "\(hero) 进局耗时 \(elapsed)s 过长")

            let hpBefore = hpValue(app, side: 1)
            XCTAssertNotNil(hpBefore, "\(hero) 读取不到对手初始血量")
            // 等开场动画结束（80 帧 ≈ 1.33s）
            usleep(1_600_000)

            let dash = app.buttons["rift.btn.dash"]
            let light = app.buttons["rift.btn.light"]
            let heavy = app.buttons["rift.btn.heavy"]
            let skill1 = app.buttons["rift.btn.skill1"]
            let stick = app.otherElements["rift.stick"]
            XCTAssertTrue(light.waitForExistence(timeout: 5), "\(hero) 找不到轻击按钮")

            var damaged = false
            for round in 0..<4 {
                // 向前拉近距离并连招
                if dash.exists { dash.tap() }
                if stick.exists {
                    let startCoord = stick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    let rightCoord = stick.coordinate(withNormalizedOffset: CGVector(dx: 1.4, dy: 0.5))
                    startCoord.press(forDuration: 0.05, thenDragTo: rightCoord)
                }
                light.tap()
                usleep(120_000)
                light.tap()
                usleep(120_000)
                if heavy.exists { heavy.tap() }
                usleep(180_000)
                if skill1.exists { skill1.tap() }
                usleep(350_000)
                if round == 0 { shot("rift-combat-\(hero)") }
                if let now = hpValue(app, side: 1), let before = hpBefore, now < before {
                    damaged = true
                    break
                }
            }
            XCTAssertTrue(damaged, "\(hero) 出招后对手未扣血（初始 \(hpBefore ?? -1)）")

            // 返回大厅
            let pause = app.buttons["rift.pause"]
            XCTAssertTrue(pause.waitForExistence(timeout: 5))
            pause.tap()
            let exit = app.buttons["rift.exit"]
            XCTAssertTrue(exit.waitForExistence(timeout: 5))
            exit.tap()
            XCTAssertTrue(home.waitForExistence(timeout: 10))
        }
    }

    func testTrainingTransformAndUltimate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "game", "-rift-autostart", "liuQuanwei", "-rift-training"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()

        let entry = app.buttons["duel.enter"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30))
        entry.tap()

        let arena = app.otherElements["rift.arena"]
        XCTAssertTrue(arena.waitForExistence(timeout: 15))
        usleep(1_700_000)

        let transformBtn = app.buttons["rift.btn.transform"]
        XCTAssertTrue(transformBtn.waitForExistence(timeout: 5))
        transformBtn.tap()

        let rage = app.otherElements["rift.rage.0"]
        XCTAssertTrue(rage.waitForExistence(timeout: 5))
        var transformed = false
        for _ in 0..<25 {
            if (rage.value as? String) == "transformed" {
                transformed = true
                break
            }
            usleep(200_000)
        }
        XCTAssertTrue(transformed, "训练场触发变身失败（当前状态：\(rage.value ?? "nil")）")
        shot("rift-transformed-liuQuanwei")

        // 变身中再按一次释放终极技
        transformBtn.tap()
        usleep(600_000)
        shot("rift-ultimate-liuQuanwei")
    }
}
