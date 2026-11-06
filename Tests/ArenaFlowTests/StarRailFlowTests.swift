import XCTest

/// Drives actual buttons; no solved-game injection or bypassed rules.
final class StarRailFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    override func tearDownWithError() throws {
        let app = XCUIApplication()
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "star-rails-final"; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "star-rails-accessibility"; tree.lifetime = .keepAlways; add(tree)
        app.terminate()
    }

    func testPreviewUndoBackgroundAndRealWinUnlockNextStage() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "tiles", "-rails.testDomain", UUID().uuidString]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        tap("tiles.starRails", in: app)
        XCTAssertFalse(app.buttons["rails.stage.2"].isEnabled)
        tap("rails.stage.1", in: app)
        tap("rails.card.10", in: app)
        XCTAssertFalse(app.buttons["rails.card.11"].isEnabled, "The last rail card must show its anchor lock")
        tap("rails.undo", in: app)
        tap("rails.preview.0", in: app)
        XCTAssertFalse(app.buttons["rails.move"].isEnabled)
        tap("rails.preview.cancel", in: app)
        for id in [0, 1, 2] { tap("rails.card.\(id)", in: app) }
        tap("rails.preview.0", in: app)
        tap("rails.move", in: app)
        tap("rails.undo", in: app)
        tap("rails.preview.0", in: app)
        tap("rails.move", in: app)
        // Home and terminate both exercise persistence after committed actions.
        XCUIDevice.shared.press(.home)
        app.activate()
        tap("rails.close", in: app)
        app.terminate(); app.launch()
        tap("tiles.starRails", in: app)
        tap("rails.stage.1", in: app)
        XCTAssertFalse(app.buttons["rails.card.0"].exists)
        for id in [9, 10, 11, 3, 4, 6, 5, 7, 8] { tap("rails.card.\(id)", in: app) }
        let result = app.staticTexts["rails.result"]
        if !result.isHittable { app.swipeUp() }
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "航线完成")
        tap("rails.close", in: app)
        XCTAssertTrue(app.buttons["rails.stage.2"].isEnabled)
        tap("rails.stage.2", in: app)
        XCTAssertTrue(app.buttons["rails.card.0"].waitForExistence(timeout: 5))
    }

    private func tap(_ id: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        if ["tiles.railContinue", "tiles.starRails", "tiles.trials", "tiles.expeditions"].contains(id), !app.buttons[id].exists {
            let library = app.buttons["tiles.modes"]
            for _ in 0..<6 { if library.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(library.waitForExistence(timeout:5),file:file,line:line)
            library.tap()
        }
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 15), id, file: file, line: line)
        for _ in 0..<6 where !button.isHittable { app.swipeUp() }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true AND hittable == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed, id, file: file, line: line)
        button.tap()
    }
}
