import XCTest

/// Shared by the ordinary and actual-equipped-resource flows. Check the real
/// window and accessibility frames, not a synthetic image or a rendered mock.
func assertFighterLandscapeLobby(_ app: XCUIApplication,
                                file: StaticString = #filePath, line: UInt = #line) {
    // Identifiers on a transparent ancestor stack can replace identifiers on
    // child buttons/scroll views. Keep these presentation-only containers untagged.
    XCTAssertFalse(app.buttons["duel.lobby.landscape"].exists, file: file, line: line)
    XCTAssertFalse(app.buttons["duel.lobby.playRail"].exists, file: file, line: line)
    let window = app.windows.firstMatch.frame
    XCTAssertGreaterThan(window.width, window.height, file: file, line: line)
    let showroom = app.descendants(matching: .any).matching(identifier: "duel.lobby.showroom").firstMatch
    XCTAssertTrue(showroom.exists, file: file, line: line)
    XCTAssertGreaterThanOrEqual(showroom.frame.width, window.width * 0.90,
                               "The stage must span the lobby, not a left-hand card", file: file, line: line)
    XCTAssertGreaterThanOrEqual(showroom.frame.height, window.height * 0.80, file: file, line: line)
    let settings = app.scrollViews["duel.lobby.actions"]
    XCTAssertTrue(settings.exists, file: file, line: line)
    let roster = app.scrollViews["duel.lobby.roster"]
    XCTAssertTrue(roster.exists, file: file, line: line)
    XCTAssertLessThan(roster.frame.maxX, settings.frame.minX,
                      "Roster and settings must leave a clear central showroom", file: file, line: line)
    XCTAssertLessThan(roster.frame.midX, window.midX, file: file, line: line)
    XCTAssertGreaterThan(settings.frame.midX, window.midX, file: file, line: line)
    for identifier in ["duel.practice", "duel.tutorial", "duel.start"] {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.isHittable, "\(identifier) must be reachable without scrolling", file: file, line: line)
        XCTAssertFalse(settings.buttons[identifier].exists,
                       "Play actions must stay outside the scrolling settings panel", file: file, line: line)
        XCTAssertGreaterThanOrEqual(button.frame.height, 44, file: file, line: line)
    }
}

extension DuelFlowTests {
    func testLargestTextKeepsLobbySelectionAndPracticeReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "fighter", "-duel-legacy-controls",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let actions = app.scrollViews["duel.lobby.actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 20))
        XCTAssertFalse(app.scrollViews["duel.lobby.roster"].exists,
                       "Accessibility text must use one scrollable stacked layout, not side panels")
        XCTAssertEqual(app.scrollViews.count, 1)
        let selection = app.buttons["duel.hero.ember"]
        for _ in 0..<10 where !selection.isHittable { actions.swipeUp() }
        XCTAssertTrue(selection.isHittable)
        selection.tap()
        XCTAssertEqual(selection.value as? String, "已选择")
        let practice = app.buttons["duel.practice"]
        for _ in 0..<10 where !practice.isHittable { actions.swipeUp() }
        XCTAssertTrue(practice.isHittable)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "fighter-largest-text-lobby"; attachment.lifetime = .keepAlways; add(attachment)
        // Selection and scrolling alone must not start or alter a match.
        XCTAssertFalse(app.buttons["duel.pause"].exists)
    }
}
