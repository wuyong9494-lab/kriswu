import XCTest

/// 实际启动首页、开局、取牌、撤回和返回；不注入胜利或跳过规则。
final class TileFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "tiles-final"; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: XCUIApplication().debugDescription); tree.name = "tiles-accessibility"; tree.lifetime = .keepAlways; add(tree)
        XCUIApplication().terminate()
    }

    func testJourneyStartsPicksUndoesAndReturnsHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "tiles"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let library = app.buttons["tiles.modes"]
        XCTAssertTrue(library.waitForExistence(timeout:15))
        for _ in 0..<6 where !library.isHittable { app.swipeUp() }
        library.tap()
        let start = app.buttons["tiles.continue"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        let locked = app.buttons["tiles.stage.12"]
        for _ in 0..<6 where !locked.exists { app.swipeUp() }
        XCTAssertTrue(locked.exists)
        XCTAssertFalse(locked.isEnabled)
        for _ in 0..<6 where !start.isHittable { app.swipeDown() }
        XCTAssertTrue(start.isHittable)
        start.tap()
        let close = app.buttons["tiles.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tiles.card.' AND enabled == true"))
        XCTAssertGreaterThan(cards.count, 0)
        let card = cards.firstMatch
        let id = card.identifier
        XCTAssertTrue(card.isHittable)
        card.tap()
        let undo = app.buttons["tiles.tool.arrow.uturn.backward"]
        XCTAssertTrue(undo.isEnabled)
        undo.tap()
        XCTAssertFalse(undo.isEnabled)
        XCTAssertTrue(app.buttons[id].isEnabled)
        XCTAssertTrue(close.isHittable)
        close.tap()
        let quit = app.buttons["退出"].firstMatch
        XCTAssertTrue(quit.waitForExistence(timeout: 5)); quit.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10))
    }
    func testResultReplayIsReadOnlyAndReturnsToSameResult() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "gameBoard"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["tiles.close"].waitForExistence(timeout: 20))
        let replay = app.buttons["tiles.showReplay"]
        for _ in 0..<120 {
            if replay.exists { break }
            let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tiles.card.' AND enabled == true"))
            guard cards.count > 0 else { break }
            cards.firstMatch.tap()
        }
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
        let result = app.staticTexts["tiles.resultProgress"].label
        for _ in 0..<3 where !replay.isHittable { app.swipeUp() }
        XCTAssertTrue(replay.isHittable)
        replay.tap()
        let close = app.buttons["tiles.replay.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let step = app.staticTexts["tiles.replay.step"]
        let initial = step.label
        let previous = app.buttons["tiles.replay.previous"]
        for _ in 0..<4 where !previous.isHittable { app.swipeUp() }
        XCTAssertTrue(previous.isEnabled)
        previous.tap()
        XCTAssertNotEqual(step.label, initial)
        app.buttons["tiles.replay.next"].tap()
        XCTAssertEqual(step.label, initial)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "tiles-replay-interaction"; attachment.lifetime = .keepAlways; add(attachment)
        for _ in 0..<5 where !close.isHittable { app.swipeDown() }
        close.tap()
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["tiles.resultProgress"].label, result)
    }

}
