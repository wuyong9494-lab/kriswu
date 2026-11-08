import XCTest

/// Selected only by the job that stages the encrypted original assets. Every
/// interaction is a real UI touch; HUD values are observations, never state input.
final class DuelWeaponFlowTests: XCTestCase {
    private struct Observation: Codable {
        let hero: String
        let action: String
        let playerPosition: Int
        let opponentPosition: Int
        let hits: Int
        let damage: Int
        let playerEnergy: Int
        let shadowEnabled: Bool
    }
    private var observations: [Observation] = []

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        capture("original-weapons-final")
        let tree = XCTAttachment(string: XCUIApplication().debugDescription)
        tree.name = "original-weapons-final-accessibility"; tree.lifetime = .keepAlways; add(tree)
        if let data = try? JSONEncoder().encode(observations) {
            let trace = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            trace.name = "original-weapons-observed-controls.json"; trace.lifetime = .keepAlways; add(trace)
        }
        XCUIApplication().terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testBothOriginalWeaponProfilesUseSourceControlsAndLandRealHits() throws {
        let app = XCUIApplication()
        // Start at the normal games home and enter through its visible link.
        // No legacy-control flag, injected match state, or accelerated simulation.
        app.launchArguments = ["-demo", "-screen", "game"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let entry = app.buttons["duel.enter"]
        XCTAssertTrue(entry.waitForExistence(timeout: 30))
        entry.tap()
        XCTAssertTrue(app.buttons["duel.hero.ember"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["duel.hero.gale"].exists,
                       "The original-asset job must not fall back to the three-character laboratory")

        for (hero, person, weapon) in [("ember", "孙登", "武士刀"), ("liu", "刘泉纬", "双锤")] {
            try tapVisible(app.buttons["duel.hero.\(hero)"], app: app)
            try tapVisible(app.buttons["duel.practice"], app: app)
            XCTAssertTrue(app.buttons["duel.pause"].waitForExistence(timeout: 15))
            expectOrientation(app, landscape: true)
            try requireOriginalControls(app, person: person, weapon: weapon)
            capture("original-\(hero)-\(weapon)-controls")

            try exerciseEightDirections(app, hero: hero)
            let normalDamage = try performIsolatedAttack(app, hero: hero, action: "weapon")
            _ = try performIsolatedAttack(app, hero: hero, action: "kick")
            let heavyDamage = try performIsolatedAttack(app, hero: hero, action: "heavy")
            XCTAssertGreaterThan(heavyDamage, normalDamage,
                                 "A real long hold must resolve the equipped heavy attack, not another short tap")
            try verifyShadowState(app, hero: hero)

            try restart(app)
            try checkReleasePauseAndBackground(app, hero: hero)
            app.buttons["duel.pause"].tap()
            XCTAssertTrue(app.buttons["duel.exit"].waitForExistence(timeout: 4))
            app.buttons["duel.exit"].tap()
            XCTAssertTrue(app.buttons["duel.hero.\(hero)"].waitForExistence(timeout: 12))
            expectOrientation(app, landscape: false)
            capture("original-\(hero)-returned-portrait-selection")
        }

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["arena.enter"].exists)
        XCTAssertTrue(app.staticTexts["星了个星"].exists)
        XCTAssertTrue(app.staticTexts["五子棋"].exists)
    }

    private func requireOriginalControls(_ app: XCUIApplication, person: String, weapon: String) throws {
        XCTAssertFalse(app.staticTexts["duel.resourceError"].exists, "Missing or corrupt source assets must fail this suite")
        XCTAssertEqual(app.staticTexts["duel.name.0"].label, "\(person) · \(weapon)")
        let expected = Set(["duel.control.joystick", "duel.control.weapon", "duel.control.kick",
                            "duel.control.ranged", "duel.control.shadow"])
        let controls = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "duel.control.")).allElementsBoundByIndex
        XCTAssertEqual(Set(controls.map(\.identifier)), expected,
                       "Source mode has four actions and one stick; no separate jump, guard, skill, or heavy key")
        let stick = joystick(app)
        XCTAssertTrue(stick.exists)
        XCTAssertEqual(stick.label, "八方向摇杆")
        XCTAssertEqual(stick.value as? String, "居中")
        XCTAssertTrue(app.buttons["duel.control.weapon"].label.contains(weapon))
        for action in ["weapon", "kick"] {
            XCTAssertTrue(app.buttons["duel.control.\(action)"].isEnabled)
            XCTAssertTrue(app.buttons["duel.control.\(action)"].isHittable)
        }
        XCTAssertTrue(app.buttons["duel.control.shadow"].exists)
        XCTAssertFalse(app.buttons["duel.control.ranged"].isEnabled)
        XCTAssertTrue((app.buttons["duel.control.ranged"].value as? String ?? "").contains("未装备"))
        XCTAssertEqual(try hits(app), 0)
        XCTAssertEqual(try damage(app), 0)
    }

    private func exerciseEightDirections(_ app: XCUIApplication, hero: String) throws {
        // Cardinal offsets match the visible arrows; diagonal offsets follow the
        // smaller diagonal arrows. Native control tests assert the exact sectors.
        let directions = [(-1, 0, "left"), (1, 0, "right"), (0, -1, "down"),
                          (-1, -1, "down-left"), (1, -1, "down-right"),
                          (0, 1, "up"), (-1, 1, "up-left"), (1, 1, "up-right")]
        for (x, y, name) in directions {
            let before = try position(app, index: 0)
            stickCoordinate(app, x: x, y: y).press(forDuration: y == 0 ? 1.0 : 0.25)
            XCTAssertEqual(joystick(app).value as? String, "居中", "Releasing \(name) must release direction ownership")
            if y == 0 {
                wait("Real \(name) joystick touch changes position", timeout: 4) {
                    guard let now = self.observedPosition(app, index: 0) else { return false }
                    return x < 0 ? now < before : now > before
                }
            }
            XCTAssertEqual(try hits(app), 0, "A direction or jump alone must never cause an attack")
            try record(app, hero: hero, action: "stick-\(name)")
            capture("original-\(hero)-stick-\(name)")
        }
    }

    @discardableResult
    private func performIsolatedAttack(_ app: XCUIApplication, hero: String, action: String) throws -> Int {
        try restart(app)
        try approachWeaponRange(app)
        let beforeHits = try hits(app), beforeHealth = try health(app, index: 1)
        let identifier = action == "heavy" ? "weapon" : action
        let button = app.buttons["duel.control.\(identifier)"]
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(button.isHittable)
        let point = button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        if action == "heavy" { point.press(forDuration: 1.1) }
        else { point.tap() }
        wait("\(hero) \(action) must make actual contact", timeout: 12) {
            guard let value = self.observedHits(app) else { return false }
            return value > beforeHits
        }
        XCTAssertGreaterThan(try hits(app), beforeHits)
        XCTAssertLessThan(try health(app, index: 1), beforeHealth)
        let dealt = try damage(app)
        XCTAssertGreaterThan(dealt, 0)
        if action == "shadow" {
            wait("Shadow input spends the equipped character's energy", timeout: 4) {
                (button.value as? String ?? "").contains("需要 100 能量")
            }
        }
        try record(app, hero: hero, action: "\(action)-actual-hit")
        capture("original-\(hero)-\(action)-actual-hit")
        return dealt
    }

    private func verifyShadowState(_ app: XCUIApplication, hero: String) throws {
        try restart(app)
        let shadow = app.buttons["duel.control.shadow"]
        if hero == "ember" {
            XCTAssertFalse(shadow.isEnabled,
                           "The katana dash's discontinuous source coordinates require its original teleport event before enabling")
        }
        if shadow.isEnabled {
            _ = try performIsolatedAttack(app, hero: hero, action: "shadow")
            return
        }
        // Disabled is an explicit verified state, not a skipped action. Tap its
        // actual glyph coordinates and ensure it cannot alias another attack.
        try approachWeaponRange(app)
        try assertStationary(app)
        let beforeHits = try hits(app), beforeEnergy = try energy(app, index: 0)
        let beforePosition = try position(app, index: 0)
        shadow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let acted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.observedHits(app) != beforeHits ||
                self.integer(after: "能量 ", in: app.staticTexts["duel.stats.0"].label) != beforeEnergy ||
                self.observedPosition(app, index: 0) != beforePosition
        }, object: nil)
        acted.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [acted], timeout: 2.2), .completed,
                       "An unavailable original shadow ability cannot spend energy, move, or become a different attack")
        XCTAssertFalse(shadow.isEnabled)
        XCTAssertEqual(try hits(app), beforeHits)
        XCTAssertEqual(try energy(app, index: 0), beforeEnergy)
        try record(app, hero: hero, action: "shadow-disabled-no-substitute")
        capture("original-\(hero)-shadow-disabled-no-substitute")
    }

    private func approachWeaponRange(_ app: XCUIApplication) throws {
        // Busy simulators do not guarantee a number of simulation ticks for a
        // wall-clock hold. Re-read actual positions after each physical gesture.
        for _ in 0..<20 {
            let player = try position(app, index: 0), opponent = try position(app, index: 1)
            let gap = abs(opponent - player)
            if gap <= 800 { return }
            stickCoordinate(app, x: opponent > player ? 1 : -1, y: 0).press(forDuration: gap > 1500 ? 1.0 : 0.4)
            wait("Joystick movement reaches the live HUD", timeout: 3) {
                guard let now = self.observedPosition(app, index: 0) else { return false }
                return now != player
            }
        }
        let player = try position(app, index: 0), opponent = try position(app, index: 1)
        XCTAssertLessThanOrEqual(abs(opponent - player), 800,
                                 "Real joystick input must reach the equipped weapon's close range")
    }

    private func restart(_ app: XCUIApplication) throws {
        app.buttons["duel.pause"].tap()
        let restart = app.buttons["duel.restart"]
        XCTAssertTrue(restart.waitForExistence(timeout: 5), "A resource error cannot be skipped as a playable match")
        restart.tap()
        wait("Restart resets observed hit and position state", timeout: 5) {
            self.observedHits(app) == 0 && self.observedDamage(app) == 0 &&
                self.observedPosition(app, index: 0) == 3500 && self.observedPosition(app, index: 1) == 6500
        }
        XCTAssertFalse(app.staticTexts["duel.resourceError"].exists)
        XCTAssertEqual(try hits(app), 0)
        XCTAssertEqual(joystick(app).value as? String, "居中")
    }

    private func checkReleasePauseAndBackground(_ app: XCUIApplication, hero: String) throws {
        let before = try position(app, index: 0)
        stickCoordinate(app, x: 1, y: 0).press(forDuration: 1.0)
        wait("Movement is observed before testing its release", timeout: 4) {
            (self.observedPosition(app, index: 0) ?? before) > before
        }
        XCTAssertEqual(joystick(app).value as? String, "居中")
        try assertStationary(app)
        try record(app, hero: hero, action: "released-stick-stationary")
        capture("original-\(hero)-released-stick")

        app.buttons["duel.pause"].tap()
        let resume = app.buttons["duel.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["duel.resourceError"].exists)
        wait("Both independently equipped source characters are loaded", timeout: 10) {
            let status = app.staticTexts["duel.characterStatus"].label
            return status.contains("孙登") && status.contains("刘泉纬") && status.contains("武士刀 / 双锤")
        }
        let pausedPosition = try position(app, index: 0), pausedHits = try hits(app)
        capture("original-\(hero)-paused-source-status")
        resume.tap()
        wait("Manual resume returns control before backgrounding", timeout: 5) {
            !resume.exists && app.buttons["duel.pause"].isHittable
        }
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(resume.waitForExistence(timeout: 10), "Background return requires an explicit resume")
        XCTAssertEqual(try position(app, index: 0), pausedPosition)
        XCTAssertEqual(try hits(app), pausedHits)
        capture("original-\(hero)-background-return-paused")
        resume.tap()
        try assertStationary(app)
        XCTAssertEqual(try hits(app), pausedHits, "Resume must not replay a released or cancelled attack")
        capture("original-\(hero)-explicit-resume")
    }

    private func assertStationary(_ app: XCUIApplication) throws {
        var last: Int?
        wait("Released movement settles in the HUD", timeout: 5) {
            guard let current = self.observedPosition(app, index: 0) else { return false }
            defer { last = current }
            return last == current && (self.joystick(app).value as? String) == "居中"
        }
        let fixed = try position(app, index: 0)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let current = self.observedPosition(app, index: 0) else { return true }
            return current != fixed
        }, object: nil)
        moved.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 1.4), .completed,
                       "Letting go of the stick must stop movement without another input")
    }

    private func joystick(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "duel.control.joystick").firstMatch
    }
    private func stickCoordinate(_ app: XCUIApplication, x: Int, y: Int) -> XCUICoordinate {
        let offset: CGFloat = x != 0 && y != 0 ? 0.24 : 0.36
        return joystick(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5 + CGFloat(x) * offset,
                                                                       dy: 0.5 - CGFloat(y) * offset))
    }
    private func integer(after marker: String, in text: String) -> Int? {
        guard let range = text.range(of: marker) else { return nil }
        // SwiftUI localizes interpolated integers (for example "位置 6,021").
        // Read only this field and validate grouping before removing separators;
        // never merge the next position/height or accept a truncated prefix.
        let field = text[range.upperBound...].prefix { $0.isNumber || $0 == "-" || $0 == "," }
        let negative = field.first == "-"
        let unsigned = negative ? field.dropFirst() : field
        let groups = unsigned.split(separator: ",", omittingEmptySubsequences: false)
        guard !groups.isEmpty, groups.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        if groups.count > 1 {
            guard (1...3).contains(groups[0].count), groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
        return Int((negative ? "-" : "") + groups.joined())
    }
    private func observedPosition(_ app: XCUIApplication, index: Int) -> Int? {
        integer(after: "位置 ", in: app.staticTexts["duel.stats.\(index)"].value as? String ?? "")
    }
    private func observedHits(_ app: XCUIApplication) -> Int? {
        integer(after: "累计命中 ", in: app.staticTexts["duel.hits"].label)
    }
    private func observedDamage(_ app: XCUIApplication) -> Int? {
        integer(after: "伤害 ", in: app.staticTexts["duel.hits"].label)
    }
    private func position(_ app: XCUIApplication, index: Int) throws -> Int {
        try XCTUnwrap(observedPosition(app, index: index), "Missing read-only fighter position \(index)")
    }
    private func health(_ app: XCUIApplication, index: Int) throws -> Int {
        try XCTUnwrap(integer(after: "生命 ", in: app.staticTexts["duel.stats.\(index)"].value as? String ?? ""))
    }
    private func energy(_ app: XCUIApplication, index: Int) throws -> Int {
        try XCTUnwrap(integer(after: "能量 ", in: app.staticTexts["duel.stats.\(index)"].label))
    }
    private func hits(_ app: XCUIApplication) throws -> Int { try XCTUnwrap(observedHits(app), "Missing actual hit counter") }
    private func damage(_ app: XCUIApplication) throws -> Int { try XCTUnwrap(observedDamage(app), "Missing actual damage counter") }
    private func record(_ app: XCUIApplication, hero: String, action: String) throws {
        observations.append(.init(hero: hero, action: action, playerPosition: try position(app, index: 0),
                                  opponentPosition: try position(app, index: 1), hits: try hits(app), damage: try damage(app),
                                  playerEnergy: try energy(app, index: 0), shadowEnabled: app.buttons["duel.control.shadow"].isEnabled))
    }
    private func wait(_ message: String, timeout: TimeInterval, condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, message)
    }
    private func expectOrientation(_ app: XCUIApplication, landscape: Bool) {
        wait(landscape ? "Match uses landscape" : "Selection returns to portrait", timeout: 10) {
            let size = app.windows.firstMatch.frame.size
            return landscape ? size.width > size.height : size.height > size.width
        }
    }
    private func tapVisible(_ button: XCUIElement, app: XCUIApplication) throws {
        XCTAssertTrue(button.waitForExistence(timeout: 12))
        for _ in 0..<4 where !button.isHittable { app.swipeUp() }
        for _ in 0..<4 where !button.isHittable { app.swipeDown() }
        XCTAssertTrue(button.isHittable)
        button.tap()
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
