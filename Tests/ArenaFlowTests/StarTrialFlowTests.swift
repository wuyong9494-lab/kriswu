import XCTest

/// Native acceptance: actual taps, persisted rewind count and a real contract win.
final class StarTrialFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "star-trial-final"; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: XCUIApplication().debugDescription)
        tree.name = "star-trial-accessibility"; tree.lifetime = .keepAlways; add(tree)
        XCUIApplication().terminate()
    }

    func testBrandPrimaryEntryAndAccessibleListPicking() {
        let app = launch()
        XCTAssertTrue(app.navigationBars["星了个星"].waitForExistence(timeout: 10))
        tap("tiles.railContinue", in: app)
        tap("rails.inspect", in: app)
        tap("rails.listCard.0", in: app)
        XCTAssertFalse(app.buttons["rails.listCard.0"].exists)
        tap("rails.inspect.done", in: app)
        XCTAssertFalse(app.buttons["rails.card.0"].exists)
        tap("rails.undo", in: app)
        XCTAssertTrue(app.buttons["rails.card.0"].exists)
    }

    func testContractSurvivesRelaunchCompletesAndRetryKeepsRules() {
        let app = launch()
        tap("tiles.trials", in: app)
        tap("trials.SX2-03-N", in: app)
        tap("rails.card.0", in: app)
        tap("rails.undo", in: app)
        tap("rails.close", in: app)
        app.terminate(); app.launch()
        tap("tiles.trials", in: app)
        tap("trials.SX2-03-N", in: app)
        XCTAssertTrue(app.staticTexts["rails.rewinds"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["rails.rewinds"].label.contains("本局撤回 1 次"))
        for id in [18, 11, 19, 22, 16] { tap("rails.card.\(id)", in: app) }
        tap("rails.preview.0", in: app); tap("rails.move", in: app)
        for id in [4, 15, 5, 23, 9, 8, 20, 21, 6, 17, 7, 10, 13, 0, 1, 2, 3, 12, 14] {
            tap("rails.card.\(id)", in: app)
        }
        XCTAssertTrue(app.staticTexts["rails.result"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["rails.result"].label, "航线完成")
        tap("trials.retry", in: app)
        XCTAssertTrue(app.staticTexts["rails.rewinds"].label.contains("本局撤回 0 次"))
        XCTAssertTrue(app.staticTexts["0/6 格"].exists)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "tiles", "-rails.testDomain", UUID().uuidString]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        return app
    }

    private func tap(_ id: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        if ["tiles.railContinue", "tiles.starRails", "tiles.trials", "tiles.expeditions"].contains(id), !app.buttons[id].exists {
            let library = app.buttons["tiles.modes"]
            for _ in 0..<6 { if library.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(library.waitForExistence(timeout:5),file:file,line:line)
            library.tap()
        }
        let button = app.buttons[id]
        for _ in 0..<6 {
            if button.waitForExistence(timeout: 1) && button.isHittable { break }
            if id.hasPrefix("rails.card.") || id == "rails.inspect.done" { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5), id, file: file, line: line)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true AND hittable == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, id, file: file, line: line)
        button.tap()
    }
}
