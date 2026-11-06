import XCTest

/// Real UI actions only: no completed-save injection, forced win, or solver in the app.
final class StarExpeditionFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "expedition-final"; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: XCUIApplication().debugDescription)
        tree.name = "expedition-accessibility"; tree.lifetime = .keepAlways; add(tree)
        XCUIDevice.shared.orientation = .portrait
        XCUIApplication().terminate()
    }
    func testBothBranchPreviewsReplayRestoreAndResume() {
        let app = launch()
        tap("tiles.expeditions", in: app); tap("expeditions.route.1", in: app)
        XCTAssertTrue(app.otherElements["rails.lesson"].exists || app.staticTexts["分岔课堂"].exists)
        for id in [0,1,2] { tap("rails.card.\(id)", in: app) }
        tap("rails.preview.0", in: app)
        XCTAssertTrue(app.buttons["rails.move"].isEnabled)
        tap("rails.stop.0.2", in: app)
        XCTAssertFalse(app.buttons["rails.move"].isEnabled, "Far branch costs two, and only one is stored")
        tap("rails.stop.0.1", in: app); tap("rails.move", in: app)
        tap("rails.replay", in: app)
        XCTAssertEqual(app.staticTexts["replay.step"].label, "第 4 / 4 手")
        tap("replay.previous", in: app); tap("replay.restore", in: app)
        tap("rails.preview.0", in: app)
        XCTAssertTrue(app.buttons["rails.stop.0.2"].exists, "Restore must put the rail back at home")
        tap("rails.preview.cancel", in: app); tap("rails.close", in: app)
        app.terminate(); app.launch()
        tap("tiles.expeditions", in: app); tap("expeditions.route.1", in: app)
        XCTAssertFalse(app.buttons["rails.card.0"].exists)
        tap("rails.replay", in: app)
        XCTAssertEqual(app.staticTexts["replay.step"].label, "第 3 / 3 手")
    }
    func testActualFarRouteWinKeepsBestReplayAndLightsFirstConstellationStar() {
        let app = launch()
        tap("tiles.expeditions", in: app); tap("expeditions.route.1", in: app)
        for id in [19,4,18,23,6,22,8] { tap("rails.card.\(id)", in: app) }
        tap("rails.preview.0", in: app); tap("rails.stop.0.2", in: app); tap("rails.move", in: app)
        for id in [11,12] { tap("rails.card.\(id)", in: app) }
        tap("rails.preview.0", in: app); tap("rails.move", in: app)
        for id in [21,5,9,20,7,14,0,1,2,3,10,13,15,16,17] { tap("rails.card.\(id)", in: app) }
        XCTAssertEqual(app.staticTexts["rails.result"].label,"航线完成")
        tap("rails.close", in: app); tap("expeditions.best.1", in: app)
        XCTAssertTrue(app.staticTexts["replay.step"].label.contains("26 / 26"))
        XCTAssertFalse(app.buttons["replay.restore"].exists, "Saved best replays are read-only")
        tap("replay.close", in: app); tap("expeditions.close", in: app); tap("tiles.collection", in: app)
        XCTAssertTrue(app.staticTexts["累计 3 星章"].exists)
        for _ in 0..<4 { if app.buttons["collection.back.orbit"].exists { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["collection.back.orbit"].exists)
        XCTAssertFalse(app.buttons["collection.back.orbit"].isEnabled)
        XCTAssertTrue(app.buttons["collection.back.starlines"].isEnabled)
    }
    func testBoardTrayAndControlsStayVisibleAfterRotationAndTutorialCanBeSkipped() {
        let app = launch(); tap("tiles.railContinue", in: app)
        tap("rails.lesson.skip", in: app)
        for orientation in [UIDeviceOrientation.landscapeLeft,.portrait] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(app.buttons["rails.card.0"].isHittable)
            XCTAssertTrue(app.buttons["rails.preview.0"].isHittable)
            XCTAssertTrue(app.buttons["rails.restart"].isHittable)
        }
        tap("rails.close", in: app); tap("tiles.railContinue", in: app)
        XCTAssertFalse(app.buttons["rails.lesson.skip"].exists)
    }
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo","-screen","tiles","-rails.testDomain",UUID().uuidString]
        XCUIDevice.shared.orientation = .portrait; app.launch(); return app
    }
    private func tap(_ id: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        if ["tiles.railContinue", "tiles.starRails", "tiles.trials", "tiles.expeditions"].contains(id), !app.buttons[id].exists {
            let library = app.buttons["tiles.modes"]
            for _ in 0..<6 { if library.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(library.waitForExistence(timeout:5),file:file,line:line)
            library.tap()
        }
        let button = app.buttons[id]
        // Menus scroll. The live board deliberately does not.
        if !id.hasPrefix("rails.") && !id.hasPrefix("replay.") {
            for _ in 0..<5 {
                if button.waitForExistence(timeout: 1) && button.isHittable { break }
                if id == "tiles.collection" { app.swipeDown() } else { app.swipeUp() }
            }
        }
        XCTAssertTrue(button.waitForExistence(timeout: 8),id,file:file,line:line)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format:"enabled == true AND hittable == true"),object:button)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:5),.completed,id,file:file,line:line)
        button.tap()
    }
}
