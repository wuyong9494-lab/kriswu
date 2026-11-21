import UIKit
import XCTest

/// 原创暗影格斗对决回归测试（不加载任何 SF3 版权素材）：
/// 1. 校验原版八方向摇杆 + 四键（武器 / 踢击 / 远程 / 暗影），确认无旧版 9 键/独立防御键。
/// 2. 校验站立不动自动防守（防御 1）。
/// 3. 校验四位角色差异化血量池（刘泉纬 3000 / 吴庸 2800 / 徐骁 2700 / 孙登 2400）、实际摇杆接近 + 武器/踢击/远程出招、扣血、击退与能量积累。
/// 4. 当设置 `DUEL_REQUIRE_RIGGED_CHARACTERS=1` 时，严格断言对局加载了真实骨骼 3D 模型（`原创骨骼角色`，而非 `动作替身`）。
final class DuelOriginalMinimalFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    private var requiresRiggedCharacters: Bool {
        ProcessInfo.processInfo.environment["DUEL_REQUIRE_RIGGED_CHARACTERS"] == "1"
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

    private func parseLabelNumber(_ app: XCUIApplication, side: Int, marker: String) -> Int? {
        let el = app.staticTexts["duel.stats.\(side)"]
        guard el.exists, let range = el.label.range(of: marker) else { return nil }
        let digits = el.label[range.upperBound...].prefix(while: { $0.isNumber })
        return Int(digits)
    }

    private func joystick(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "duel.control.joystick").firstMatch
    }

    private func stickCoordinate(_ app: XCUIApplication, x: Int, y: Int) -> XCUICoordinate {
        let offset: CGFloat = x != 0 && y != 0 ? 0.24 : 0.36
        return joystick(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5 + CGFloat(x) * offset,
                                                                       dy: 0.5 - CGFloat(y) * offset))
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

    private func enterLobbyAndStart(_ app: XCUIApplication, heroID: String, shotPrefix: String) throws -> Double {
        app.launchArguments = ["-demo"]
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        app.launch()

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

        let heroButton = app.buttons["duel.hero.\(heroID)"]
        let roster = app.scrollViews["duel.lobby.roster"]
        let actions = app.scrollViews["duel.lobby.actions"]
        XCTAssertTrue(reveal(heroButton, containers: [roster, actions], timeout: 15), "大厅未显示角色 \(heroID)")
        heroButton.tap()
        // Allow showroom 3D character to render a settled idle frame before screenshot
        usleep(400_000)
        shot("\(shotPrefix)-lobby")

        let start = app.buttons["duel.start"]
        XCTAssertTrue(reveal(start, containers: [actions], timeout: 10), "大厅未显示开始对战按钮")
        XCTAssertTrue(start.isEnabled, "开始对战按钮不可用")

        let t0 = CFAbsoluteTimeGetCurrent()
        start.tap()

        let weapon = app.buttons["duel.control.weapon"]
        XCTAssertTrue(weapon.waitForExistence(timeout: 30), "30 秒内未进入对战界面（缺少原版武器键）")
        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        XCTAssertLessThan(elapsed, 30.0, "进局耗时 \(elapsed)s 超过 30 秒")
        return elapsed
    }

    private func assertOriginalControlsAndAutoBlock(_ app: XCUIApplication, expectedHeroName: String,
                                                    expectedMaxHP: Int) {
        let stick = joystick(app)
        let weapon = app.buttons["duel.control.weapon"]
        let kick = app.buttons["duel.control.kick"]
        let ranged = app.buttons["duel.control.ranged"]
        let shadow = app.buttons["duel.control.shadow"]

        XCTAssertTrue(stick.exists, "缺少原版八方向摇杆 duel.control.joystick")
        XCTAssertTrue(weapon.exists && weapon.isEnabled, "原版武器键不可用")
        XCTAssertTrue(kick.exists && kick.isEnabled, "原版踢击键不可用")
        XCTAssertTrue(ranged.exists && ranged.isEnabled, "原版远程/战术键不可用")
        XCTAssertTrue(shadow.exists && shadow.isEnabled, "原版暗影键不可用")

        // 严格确认旧版 9 键面板与手动防御键已彻底移除
        XCTAssertFalse(app.buttons["duel.control.light"].exists, "不应再显示旧版普攻键 duel.control.light")
        XCTAssertFalse(app.buttons["duel.control.guard"].exists, "不应存在手动防御键 duel.control.guard（应为原版不动自动防守）")

        XCTAssertEqual(app.staticTexts["duel.name.0"].label, expectedHeroName)
        let stats0Label = app.staticTexts["duel.stats.0"].label
        let normalizedStats0 = stats0Label.replacingOccurrences(of: ",", with: "")
        XCTAssertTrue(normalizedStats0.contains("/\(expectedMaxHP)"),
                      "\(expectedHeroName) 最大血量应为 \(expectedMaxHP)，实际 HUD：\(stats0Label)")

        // 校验原版不动自动防守：摇杆居中且站立未受击时自动处于防守态（防御 1）
        XCTAssertEqual(stick.value as? String, "居中", "开局未触碰摇杆时应居中")
        var observedAutoGuard = parseStat(app, side: 0, key: "防御") == 1
        if !observedAutoGuard {
            // 若 XCUITest 轮询期间 AI 已近身破防/投技，沿远离对手方向后拉半步拉开身位再松开回中，验证不动自动防守恢复
            let p0 = parseStat(app, side: 0, key: "位置") ?? 3500
            let p1 = parseStat(app, side: 1, key: "位置") ?? 6500
            let awayX = p0 <= p1 ? -1 : 1
            stickCoordinate(app, x: awayX, y: 0).press(forDuration: 0.25)
            let deadline = Date().addingTimeInterval(2.0)
            while Date() < deadline {
                if parseStat(app, side: 0, key: "防御") == 1 {
                    observedAutoGuard = true
                    break
                }
                usleep(100_000)
            }
        }
        XCTAssertTrue(observedAutoGuard, "\(expectedHeroName) 站立不动时应自动触发防守（防御 1）")
    }

    private func verifyRiggedCharacterStatusIfRequired(_ app: XCUIApplication, expectedHeroName: String) {
        let pause = app.buttons["duel.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5), "缺少暂停按钮")
        pause.tap()
        let statusEl = app.staticTexts["duel.characterStatus"]
        XCTAssertTrue(statusEl.waitForExistence(timeout: 5), "暂停面板未显示角色资源状态")
        let statusText = statusEl.label
        print("[duel-character-status] \(expectedHeroName): \(statusText)")
        XCTAssertFalse(app.staticTexts["duel.resourceError"].exists, "角色加载报错")
        if requiresRiggedCharacters {
            XCTAssertTrue(statusText.contains("原创骨骼角色"),
                          "开启真实模型校验时必须加载真实 3D 骨骼角色，实际状态：\(statusText)")
            XCTAssertTrue(statusText.contains(expectedHeroName),
                          "真实骨骼角色状态应包含当前角色 \(expectedHeroName)，实际：\(statusText)")
            XCTAssertFalse(statusText.contains("动作替身"),
                           "不允许退回动作替身，实际：\(statusText)")
        }
        let resume = app.buttons["duel.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        XCTAssertTrue(app.buttons["duel.control.weapon"].waitForExistence(timeout: 5))
    }

    private func fightAndVerify(
        _ app: XCUIApplication,
        shotPrefix: String,
        approachDistance: Int,
        resourceMarker: String,
        useRangedOnFirst: Bool = false,
        requireKnockback: Bool = true
    ) {
        let weapon = app.buttons["duel.control.weapon"]
        let kick = app.buttons["duel.control.kick"]
        let ranged = app.buttons["duel.control.ranged"]

        let foeHPBefore = parseStat(app, side: 1, key: "生命")
        XCTAssertNotNil(foeHPBefore, "读取不到对手初始生命")
        let startHP = foeHPBefore ?? 2400

        var damaged = false
        var knockedBack = false
        var gainedResource = false

        for attempt in 0..<14 {
            let p0 = parseStat(app, side: 0, key: "位置") ?? 3500
            let p1 = parseStat(app, side: 1, key: "位置") ?? 6500
            let hpBeforeHit = parseStat(app, side: 1, key: "生命") ?? startHP

            if useRangedOnFirst && attempt == 0 && ranged.exists {
                ranged.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }

            if abs(p1 - p0) > approachDistance {
                let dirX = p1 > p0 ? 1 : -1
                stickCoordinate(app, x: dirX, y: 0).press(forDuration: 0.32)
            }
            let posBeforeHit = parseStat(app, side: 1, key: "位置") ?? p1

            // 原版暗影格斗出招：武器连斩 + 踢击 + 间隔蓄力重击/战术技
            weapon.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            usleep(120_000)
            weapon.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if attempt % 2 == 0 {
                kick.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            } else {
                weapon.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.42)
            }
            if attempt == 2 && ranged.exists {
                ranged.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }

            if attempt == 0 { shot("\(shotPrefix)-combat") }

            let hpNow = parseStat(app, side: 1, key: "生命") ?? hpBeforeHit
            let posNow = parseStat(app, side: 1, key: "位置") ?? posBeforeHit
            if let val = parseLabelNumber(app, side: 0, marker: resourceMarker), val > 0 {
                gainedResource = true
            }
            if hpNow < startHP {
                damaged = true
                if posNow != posBeforeHit { knockedBack = true }
            }
            if damaged && (!requireKnockback || knockedBack) && gainedResource {
                shot("\(shotPrefix)-after-hit")
                break
            }
        }

        XCTAssertTrue(damaged, "\(shotPrefix) 使用原版摇杆与武器/踢击键后对手未扣血（初始生命 \(startHP)）")
        if requireKnockback {
            XCTAssertTrue(knockedBack, "\(shotPrefix) 命中后未观察到击退位移")
        }
        XCTAssertTrue(gainedResource, "\(shotPrefix) 战斗命中后未积累资源（\(resourceMarker)）")
    }

    func testLobbyLiuCanHitSunWithDamageAndKnockback() throws {
        let app = XCUIApplication()
        _ = try enterLobbyAndStart(app, heroID: "liu", shotPrefix: "duel-original")
        assertOriginalControlsAndAutoBlock(app, expectedHeroName: "刘泉纬", expectedMaxHP: 3000)
        XCTAssertEqual(app.staticTexts["duel.name.1"].label, "孙登")
        let stats1Label = app.staticTexts["duel.stats.1"].label
        XCTAssertTrue(stats1Label.replacingOccurrences(of: ",", with: "").contains("/2400"),
                      "孙登最大血量应为 2400，实际 HUD：\(stats1Label)")
        XCTAssertTrue(app.staticTexts["duel.stats.0"].label.contains("怒火"), "刘泉纬 HUD 应显示诺娜怒火条")
        verifyRiggedCharacterStatusIfRequired(app, expectedHeroName: "刘泉纬")

        fightAndVerify(app, shotPrefix: "duel-original", approachDistance: 1050, resourceMarker: "怒火 ", requireKnockback: true)
    }

    func testLobbyWuYongShogunCanHitWithOdachiAndCommandRetinue() throws {
        let app = XCUIApplication()
        _ = try enterLobbyAndStart(app, heroID: "wuyong_erlang", shotPrefix: "duel-shogun")
        assertOriginalControlsAndAutoBlock(app, expectedHeroName: "吴庸", expectedMaxHP: 2800)
        XCTAssertTrue(app.staticTexts["duel.stats.0"].label.contains("暗影"), "吴庸 HUD 应显示暗影能量条")
        verifyRiggedCharacterStatusIfRequired(app, expectedHeroName: "吴庸")

        fightAndVerify(app, shotPrefix: "duel-shogun", approachDistance: 1280, resourceMarker: "暗影 ",
                       useRangedOnFirst: true, requireKnockback: true)
    }

    func testLobbyXuXiaoInquisitorCanCastSalvationAndGainLight() throws {
        let app = XCUIApplication()
        _ = try enterLobbyAndStart(app, heroID: "gale", shotPrefix: "duel-inquisitor")
        assertOriginalControlsAndAutoBlock(app, expectedHeroName: "徐骁", expectedMaxHP: 2700)
        XCTAssertTrue(app.staticTexts["duel.stats.0"].label.contains("圣光"), "徐骁 HUD 应显示圣光条")
        verifyRiggedCharacterStatusIfRequired(app, expectedHeroName: "徐骁")

        fightAndVerify(app, shotPrefix: "duel-inquisitor", approachDistance: 1200, resourceMarker: "圣光 ",
                       useRangedOnFirst: true, requireKnockback: false)
    }

    func testLobbySunDengMidnightCanHitAndGainShadowEnergy() throws {
        let app = XCUIApplication()
        _ = try enterLobbyAndStart(app, heroID: "ember", shotPrefix: "duel-midnight")
        assertOriginalControlsAndAutoBlock(app, expectedHeroName: "孙登", expectedMaxHP: 2400)
        XCTAssertTrue(app.staticTexts["duel.stats.0"].label.contains("影能"), "孙登 HUD 应显示影能条")
        verifyRiggedCharacterStatusIfRequired(app, expectedHeroName: "孙登")

        fightAndVerify(app, shotPrefix: "duel-midnight", approachDistance: 820, resourceMarker: "影能 ",
                       requireKnockback: false)
    }
}
