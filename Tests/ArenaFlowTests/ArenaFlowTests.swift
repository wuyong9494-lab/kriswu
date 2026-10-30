import XCTest

/// Drives real pages and real controls. No forced result or accelerated simulation.
final class ArenaFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    override func tearDownWithError() throws {
        shot("final-state")
        let tree = XCTAttachment(string: XCUIApplication().debugDescription)
        tree.name = "final-accessibility-tree"
        tree.lifetime = .keepAlways
        add(tree)
        XCUIApplication().terminate()
    }

    func testRangerLoop() throws { try play(hero: 1) }
    func testBarbarianLoop() throws { try play(hero: 2) }
    func testMageLoop() throws { try play(hero: 3) }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func play(hero: Int) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "game", "-arena.snapshotTime", "0",
                               "-arena.captureTraversal", "NO", "-arena.captureFlow", "YES", "-arena.previewRanger", "NO"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let entry = app.buttons["arena.enter"]
        XCTAssertTrue(entry.waitForExistence(timeout: 40))
        shot("hero-\(hero)-entry")
        entry.tap()
        let heroes = app.buttons["arena.openHeroes"]
        XCTAssertTrue(heroes.waitForExistence(timeout: 40))
        shot("hero-\(hero)-lobby")
        heroes.tap()
        let card = app.buttons["arena.hero.\(hero)"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        shot("hero-\(hero)-list")
        card.tap()
        let select = app.buttons["arena.hero.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 20))
        shot("hero-\(hero)-detail")
        select.tap()
        let start = app.buttons["arena.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()
        let move = app.descendants(matching: .any).matching(identifier: "arena.control.move").firstMatch
        let attack = app.descendants(matching: .any).matching(identifier: "arena.control.attack").firstMatch
        let special = app.descendants(matching: .any).matching(identifier: "arena.control.special").firstMatch
        XCTAssertTrue(move.waitForExistence(timeout: 45))
        shot("hero-\(hero)-battle")
        let from = move.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let toward = move.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        from.press(forDuration: 0.1, thenDragTo: toward, withVelocity: .slow, thenHoldForDuration: 4)
        let back = app.buttons["arena.result.lobby"]
        let deadline = Date().addingTimeInterval(360)
        while !back.exists && Date() < deadline {
            if attack.exists && attack.isHittable { attack.tap() }
            if special.exists && special.isHittable { special.tap() }
            // Wait for the naturally completed match; do not inject a win or rewrite time.
            _ = back.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(back.exists, "Match did not naturally reach results")
        shot("hero-\(hero)-result")
        let scene = try XCTUnwrap(back.value as? String)
        XCTAssertFalse(scene.isEmpty, "Natural-result evidence was not saved")
        let evidence = XCTAttachment(string: scene)
        evidence.name = "arena-flow-hero-\(hero).json"
        evidence.lifetime = .keepAlways
        add(evidence)
        back.tap()
        XCTAssertTrue(heroes.waitForExistence(timeout: 30))
        shot("hero-\(hero)-returned-lobby")
        app.terminate()
    }
}
