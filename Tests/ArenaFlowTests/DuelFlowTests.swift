import XCTest

final class DuelFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        capture("fighter-final")
        let tree = XCTAttachment(string: XCUIApplication().debugDescription)
        tree.name = "fighter-accessibility"; tree.lifetime = .keepAlways; add(tree)
        XCUIApplication().terminate(); XCUIDevice.shared.orientation = .portrait
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func expectOrientation(_ app: XCUIApplication, landscape: Bool) {
        let predicate = NSPredicate { _, _ in
            let size = app.windows.firstMatch.frame.size
            return landscape ? size.width > size.height : size.height > size.width
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app)], timeout: 8), .completed)
    }
    private func approachGrappleRange(_ app: XCUIApplication) {
        func position(_ index: Int) -> Int? {
            guard let value = app.staticTexts["duel.stats.\(index)"].value as? String,
                  let range = value.range(of: "位置 ") else { return nil }
            let field = value[range.upperBound...].split(separator: "，").first ?? ""
            return Int(field.filter { $0.isNumber })
        }
        // A wall-clock press does not guarantee 42 simulation ticks on a busy
        // simulator. Observe position after real touch input instead of firing
        // the ultimate from outside its unchanged 1050-unit grab range.
        for _ in 0..<12 {
            guard let player = position(0), let opponent = position(1) else {
                XCTFail("Fighter positions must be available before the grab"); return
            }
            if abs(opponent - player) <= 1000 { return }
            app.buttons[opponent > player ? "duel.control.right" : "duel.control.left"]
                .press(forDuration: 0.25)
        }
        guard let player = position(0), let opponent = position(1) else {
            XCTFail("Fighter positions disappeared during approach"); return
        }
        XCTAssertLessThanOrEqual(abs(opponent - player), 1000, "Real directional input must reach grab range")
    }

    func testLiuUltimateUsesRealTouchInputPausesAndDealsTwoImpacts() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "fighter"]
        XCUIDevice.shared.orientation = .portrait; app.launch()
        let selection = app.buttons["duel.hero.liu"]
        XCTAssertTrue(selection.waitForExistence(timeout: 20)); selection.tap()
        app.buttons["duel.practice"].tap()
        let pause = app.buttons["duel.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 8)); expectOrientation(app, landscape: true)
        let ultimate = app.buttons["duel.control.ultimate"]
        XCTAssertTrue(ultimate.isHittable)
        XCTAssertTrue((ultimate.value as? String ?? "").contains("可施放"))
        approachGrappleRange(app)
        ultimate.tap()
        let status = app.staticTexts["duel.grapple"]
        let holding = NSPredicate { _, _ in status.exists && status.label.contains("锁臂压制") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: holding, object: nil)], timeout: 4), .completed)
        XCTAssertTrue((ultimate.value as? String ?? "").contains("需要 100 能量"), "Spending energy must update the live button state")
        capture("fighter-liu-hold-controls")
        pause.tap()
        XCTAssertTrue(app.buttons["duel.resume"].waitForExistence(timeout: 3))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["duel.resume"].waitForExistence(timeout: 8))
        app.buttons["duel.resume"].tap()
        let finished = NSPredicate { _, _ in app.staticTexts["duel.hits"].label.contains("伤害 280") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: finished, object: nil)], timeout: 6), .completed)
        XCTAssertTrue(app.staticTexts["duel.hits"].label.contains("命中 2 次"))
        XCTAssertTrue((ultimate.value as? String ?? "").contains("需要 100 能量"))
        capture("fighter-liu-release-controls")
        pause.tap(); app.buttons["duel.restart"].tap()
        XCTAssertTrue((ultimate.value as? String ?? "").contains("可施放"))
        XCTAssertTrue(app.staticTexts["duel.hits"].label.contains("伤害 0"))
        pause.tap(); app.buttons["duel.exit"].tap()
        XCTAssertTrue(selection.waitForExistence(timeout: 8)); expectOrientation(app, landscape: false)
    }
    func testBothHeroesHitPauseBackgroundExitAndKeepExistingGameEntries() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "game"]
        XCUIDevice.shared.orientation = .portrait; app.launch()
        let entry = app.buttons["duel.enter"]
        XCTAssertTrue(entry.waitForExistence(timeout: 20)); entry.tap()
        for hero in ["gale", "ember"] {
            let selection = app.buttons["duel.hero.\(hero)"]
            XCTAssertTrue(selection.waitForExistence(timeout: 8)); selection.tap()
            app.buttons["duel.practice"].tap()
            let pause = app.buttons["duel.pause"]
            XCTAssertTrue(pause.waitForExistence(timeout: 8)); expectOrientation(app, landscape: true)
            let initial = app.staticTexts["duel.hits"].label
            if hero == "ember" {
                app.buttons["duel.control.right"].press(forDuration: 0.8)
                app.buttons["duel.control.light"].tap()
            } else { app.buttons["duel.control.skill1"].tap() }
            let hit = NSPredicate { _, _ in app.staticTexts["duel.hits"].label != initial }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hit, object: nil)], timeout: 5), .completed)
            app.buttons["duel.boxes"].tap(); capture("fighter-\(hero)-practice")
            pause.tap()
            XCTAssertTrue(app.buttons["duel.resume"].waitForExistence(timeout: 4))
            app.buttons["duel.resume"].tap()
            XCUIDevice.shared.press(.home); app.activate()
            XCTAssertTrue(app.buttons["duel.resume"].waitForExistence(timeout: 8), "Background return requires explicit resume")
            app.buttons["duel.resume"].tap()
            let stationary = app.staticTexts["duel.stats.0"].value as? String
            app.buttons["duel.control.guard"].press(forDuration: 0.4)
            XCTAssertEqual(app.staticTexts["duel.stats.0"].value as? String, stationary)
            pause.tap(); app.buttons["duel.exit"].tap()
            XCTAssertTrue(selection.waitForExistence(timeout: 8)); expectOrientation(app, landscape: false)
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["arena.enter"].exists)
        XCTAssertTrue(app.staticTexts["星了个星"].exists)
        XCTAssertTrue(app.staticTexts["五子棋"].exists)
    }
}
