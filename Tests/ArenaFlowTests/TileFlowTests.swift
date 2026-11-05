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
        let start = app.buttons["tiles.continue"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["tiles.stage.12"].isEnabled)
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
}
