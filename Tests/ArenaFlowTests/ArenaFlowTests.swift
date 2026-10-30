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

    private struct ControlState: Codable {
        let x, y, time, speed, charge: Double
        let alive: Bool
        let health, damage: Int
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
        XCTAssertTrue(attack.exists)
        XCTAssertTrue(special.exists)
        XCTAssertTrue(move.isHittable, "Move control is still covered by the intro")
        XCTAssertFalse(app.otherElements["harbor-wall-cells"].exists, "Decorative SceneKit mesh leaked into accessibility")
        shot("hero-\(hero)-battle")
        let battleTree = XCTAttachment(string: app.debugDescription)
        battleTree.name = "hero-\(hero)-battle-accessibility-tree"
        battleTree.lifetime = .keepAlways
        add(battleTree)
        // Cache stable on-screen control positions after the overlay has gone.
        // Querying every control and waitForExistence on every shot creates a
        // failure-triage snapshot each second even while the match is healthy.
        let screen = app.coordinate(withNormalizedOffset: .zero)
        let attackFrame = attack.frame
        let specialFrame = special.frame
        let moveFrame = move.frame
        let attackPoint = screen.withOffset(CGVector(dx: attackFrame.midX, dy: attackFrame.midY))
        let specialPoint = screen.withOffset(CGVector(dx: specialFrame.midX, dy: specialFrame.midY))
        let from = screen.withOffset(CGVector(dx: moveFrame.midX, dy: moveFrame.midY))
        var trace: [ControlState] = []
        defer {
            if let data = try? JSONEncoder().encode(trace) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "hero-\(hero)-control-trace.json"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        let back = app.buttons["arena.result.lobby"]
        // The clock remains mounted when the result hides the control sticks,
        // so a natural result arriving between queries cannot invalidate it.
        let clock = app.staticTexts["arena.match.clock"]
        let deadline = Date().addingTimeInterval(360)
        while !back.exists && Date() < deadline {
            let value = try XCTUnwrap(clock.value as? String, "Missing read-only movement feedback")
            let state = try JSONDecoder().decode(ControlState.self, from: Data(value.utf8))
            trace.append(state)
            if state.alive && state.y > 15.2 {
                // Clear the southern wall at x=9 before proceeding north. A
                // fixed two-second drag ended at x=9.4–9.8 and hit that wall.
                // Observe actual movement, including after respawn; all actions
                // still go through the same on-screen stick as a human player.
                let east = state.y > 19 && abs(state.x - 11) > 0.3
                let distance = east ? 11 - state.x : 14.5 - state.y
                let direction = distance > 0 ? 1.0 : -1.0
                let dx = east ? CGFloat(direction) * moveFrame.width * 0.4 : 0
                let dy = east ? 0 : CGFloat(direction) * moveFrame.height * 0.4
                let toward = from.withOffset(CGVector(dx: dx, dy: dy))
                let hold = min(1, max(0.15, abs(distance) / (state.speed * 0.8)))
                from.press(forDuration: 0.05, thenDragTo: toward, withVelocity: .fast, thenHoldForDuration: hold)
            }
            attackPoint.tap()
            specialPoint.tap() // The app itself rejects this until charge is earned.
            // Real input only; no failed waitForExistence diagnostics in the combat loop.
            Thread.sleep(forTimeInterval: 0.15)
        }
        XCTAssertTrue(back.exists, "Match did not naturally reach results")
        shot("hero-\(hero)-result")
        let scene = try XCTUnwrap(back.value as? String)
        XCTAssertFalse(scene.isEmpty, "Natural-result evidence was not saved")
        let evidence = XCTAttachment(string: scene)
        evidence.name = "arena-flow-hero-\(hero).json"
        evidence.lifetime = .keepAlways
        add(evidence)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(scene.utf8)) as? [String: Any])
        let events = try XCTUnwrap(payload["events"] as? [[String: Any]])
        let playerEvents = events.filter { ($0["fighter"] as? Int) == 0 }
        XCTAssertTrue(playerEvents.contains { ($0["kind"] as? String) == "attack" }, "No real player attack")
        XCTAssertTrue(playerEvents.contains { ($0["kind"] as? String) == "super" }, "No earned player super")
        back.tap()
        XCTAssertTrue(heroes.waitForExistence(timeout: 30))
        XCTAssertTrue(heroes.isHittable, "Lobby is still covered by the finished match")
        XCTAssertFalse(back.exists, "Result screen was not dismissed")
        shot("hero-\(hero)-returned-lobby")
        app.terminate()
    }
}
