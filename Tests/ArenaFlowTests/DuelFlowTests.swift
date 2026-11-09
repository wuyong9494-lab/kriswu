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
    private func expectSinglePracticeHit(_ counter: XCUIElement, damage: Int,
                                         file: StaticString = #filePath, line: UInt = #line) {
        // The resource simulator can spend several seconds resolving one HUD
        // snapshot. Use the same bounded observation budget as the original
        // weapon flow, and keep the element as the expectation's stable object.
        // Only actual cumulative hit/damage counts satisfy this expectation;
        // a changed/missing label or another attack cannot stand in for contact.
        let expected = "累计命中 1 次 · 伤害 \(damage)"
        let hit = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: counter)
        XCTAssertEqual(XCTWaiter.wait(for: [hit], timeout: 12), .completed,
                       "One real attack must produce exactly one hit and \(damage) damage", file: file, line: line)
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

    private func exerciseSunMotion(_ app: XCUIApplication) {
        // Record distinct attacks through real controls. Restarting isolates
        // each input from the previous move's knockdown, energy use and drift.
        for (control, damage) in [("heavy", 165), ("skill1", 135), ("skill2", 155)] {
            app.buttons["duel.pause"].tap()
            XCTAssertTrue(app.buttons["duel.restart"].waitForExistence(timeout: 3))
            app.buttons["duel.restart"].tap()
            approachGrappleRange(app)
            let button = app.buttons["duel.control.\(control)"]
            XCTAssertTrue(button.isHittable)
            button.tap()
            let connected = NSPredicate { _, _ in
                let hits = app.staticTexts["duel.hits"].label
                return hits.contains("命中 1 次") && hits.contains("伤害 \(damage)")
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: connected, object: nil)], timeout: 5), .completed)
            capture("fighter-ember-motion-\(control)")
        }
        app.buttons["duel.pause"].tap(); app.buttons["duel.restart"].tap()
        let reset = NSPredicate { _, _ in app.staticTexts["duel.hits"].label.contains("伤害 0") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: reset, object: nil)], timeout: 3), .completed)
    }

    func testLiuUltimateUsesRealTouchInputPausesAndDealsTwoImpacts() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "fighter", "-duel-legacy-controls"]
        XCUIDevice.shared.orientation = .portrait; app.launch()
        let selection = app.buttons["duel.hero.liu"]
        XCTAssertTrue(selection.waitForExistence(timeout: 20)); expectOrientation(app, landscape: true); selection.tap()
        app.buttons["duel.practice"].tap()
        let pause = app.buttons["duel.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 8)); expectOrientation(app, landscape: true)
        let ultimate = app.buttons["duel.control.ultimate"]
        XCTAssertTrue(ultimate.isHittable)
        XCTAssertTrue((ultimate.value as? String ?? "").contains("可施放"))
        approachGrappleRange(app)
        let status = app.staticTexts["duel.grapple"]
        // Trigger through the real control and observe the simulation phase,
        // not an assumed number of ticks during a wall-clock press. A following
        // app-coordinate tap can spend the entire three-second hold resolving
        // accessibility snapshots (run 30 took over five seconds). Home uses a
        // real device event without that extra app query and exercises the
        // production background-pause path; the other flow covers the pause UI.
        ultimate.tap()
        let holding = NSPredicate(format: "label CONTAINS %@", "锁臂压制")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: holding, object: status)], timeout: 4), .completed)
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["duel.resume"].waitForExistence(timeout: 8))
        XCTAssertTrue(status.label.contains("锁臂压制"), "Backgrounding must freeze the observed hold before its release impact")
        let heldStatus = status.label, heldHits = app.staticTexts["duel.hits"].label
        let heldOpponent = app.staticTexts["duel.stats.1"].value as? String
        XCTAssertTrue(heldHits.contains("命中 1 次") && heldHits.contains("伤害 100"))
        XCTAssertTrue((heldOpponent ?? "").contains("生命 900，"))
        XCTAssertTrue((ultimate.value as? String ?? "").contains("需要 100 能量"), "Spending energy must update the live button state")
        capture("fighter-liu-hold-controls")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["duel.resume"].waitForExistence(timeout: 8))
        XCTAssertEqual(status.label, heldStatus, "A paused hold must not advance while backgrounded")
        XCTAssertEqual(app.staticTexts["duel.hits"].label, heldHits)
        XCTAssertEqual(app.staticTexts["duel.stats.1"].value as? String, heldOpponent)
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
        XCTAssertTrue(selection.waitForExistence(timeout: 8)); expectOrientation(app, landscape: true)
    }
    func testBothHeroesHitPauseBackgroundExitAndKeepExistingGameEntries() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "game", "-duel-legacy-controls"]
        XCUIDevice.shared.orientation = .portrait; app.launch()
        let entry = app.buttons["duel.enter"]
        XCTAssertTrue(entry.waitForExistence(timeout: 20)); entry.tap()
        for hero in ["gale", "ember"] {
            let selection = app.buttons["duel.hero.\(hero)"]
            XCTAssertTrue(selection.waitForExistence(timeout: 8)); selection.tap()
            app.buttons["duel.practice"].tap()
            let pause = app.buttons["duel.pause"]
            XCTAssertTrue(pause.waitForExistence(timeout: 8)); expectOrientation(app, landscape: true)
            let counter = app.staticTexts["duel.hits"]
            XCTAssertEqual(counter.label, "累计命中 0 次 · 伤害 0")
            if hero == "ember" {
                XCTAssertEqual(app.staticTexts["duel.name.0"].label, "孙登 · 你")
                XCTAssertEqual(app.staticTexts["duel.name.1"].label, "刘泉纬 · 对手")
                // The jab reaches 1030 units. Observe a gap at most 1000
                // instead of assuming a wall-clock hold advances enough ticks.
                approachGrappleRange(app)
                app.buttons["duel.control.light"].tap()
            } else { app.buttons["duel.control.skill1"].tap() }
            expectSinglePracticeHit(counter, damage: hero == "gale" ? 135 : 75)
            app.buttons["duel.boxes"].tap(); capture("fighter-\(hero)-practice")
            if hero == "ember" {
                app.buttons["duel.boxes"].tap()
                exerciseSunMotion(app)
            }
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
            XCTAssertTrue(selection.waitForExistence(timeout: 8)); expectOrientation(app, landscape: true)
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        expectOrientation(app, landscape: false)
        XCTAssertTrue(app.buttons["arena.enter"].exists)
        XCTAssertTrue(app.staticTexts["星了个星"].exists)
        XCTAssertTrue(app.staticTexts["五子棋"].exists)
    }
}
