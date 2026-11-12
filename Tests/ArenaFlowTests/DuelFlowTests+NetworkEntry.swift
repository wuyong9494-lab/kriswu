import XCTest

extension DuelFlowTests {
    /// No transport, local-network prompt, Game Center login or live peer is
    /// needed to open/close the entry form and validate its two-seat constraint.
    func testNetworkEntryCanBeRepeatedAndNeverFallsBackToOfflineCombat() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "fighter", "-duel-legacy-controls"]
        app.launch()
        let entry = app.buttons["duel.network.enter"]
        XCTAssertTrue(entry.waitForExistence(timeout: 20))
        for iteration in 0..<3 {
            for _ in 0..<4 where !entry.isHittable { app.scrollViews["duel.lobby.actions"].swipeUp() }
            XCTAssertTrue(entry.isHittable)
            entry.tap()
            let close = app.buttons["duel.network.entry.close"]
            XCTAssertTrue(close.waitForExistence(timeout: 8))
            XCTAssertTrue(app.staticTexts["duel.network.scope"].exists)
            let remote = app.buttons["duel.network.remote"]
            XCTAssertEqual(remote.label, "进入远程对战")
            XCTAssertFalse(app.staticTexts["远程 · 仅选角测试"].exists)
            XCTAssertFalse(remote.isEnabled)
            XCTAssertFalse(app.buttons["duel.pause"].exists, "Opening network entry must not launch single-player")
            if iteration == 0 {
                let code = app.textFields["duel.network.code"]
                XCTAssertTrue(code.exists)
                code.tap(); code.typeText("3456")
                XCTAssertFalse(remote.isEnabled, "Three-player codes must not start a fighter room")
                code.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "2345")
                XCTAssertTrue(remote.isEnabled)
                // Do not press it: this test deliberately performs no sign-in.
            }
            close.tap()
            XCTAssertTrue(entry.waitForExistence(timeout: 8))
            assertFighterLandscapeLobby(app)
            XCTAssertFalse(app.buttons["duel.network.leave"].exists)
            XCTAssertFalse(app.buttons["duel.pause"].exists)
        }
    }
}
