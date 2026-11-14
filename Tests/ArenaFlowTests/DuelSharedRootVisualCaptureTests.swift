import XCTest

/// One new UI flow for the final installed shared-root release. All combat
/// actions are real touches; observations never write energy, HP or match state.
/// The workflow verifies the built App's release pin before selecting this case.
final class DuelSharedRootVisualCaptureTests: XCTestCase {
    private struct Element: Codable {
        let label: String
        let value: String?
        let enabled: Bool
    }
    private struct Observation: Codable {
        let phase: String
        let uptime: TimeInterval
        let snapshotSeconds: TimeInterval
        let width: Double
        let height: Double
        let elements: [String: [Element]]
        let error: String?

        func count(_ id: String) -> Int { elements[id]?.count ?? 0 }
        func label(_ id: String) -> String { elements[id]?.first?.label ?? "" }
        func value(_ id: String) -> String { elements[id]?.first?.value ?? "" }
        var isReadyPractice: Bool {
            error == nil && width > height && count("duel.resourceError") == 0 &&
                count("duel.pause") == 1 && count("duel.resume") == 0 &&
                count("duel.stats.0") == 1 && count("duel.stats.1") == 1 &&
                value("duel.control.joystick") == "居中" &&
                value("duel.control.weapon") == "可施放"
        }
    }
    private enum Failure: Error { case notObserved(String) }
    private var observations: [Observation] = []
    private var captures: [[String: Any]] = []
    private var completed = false
    private var phase = "not-launched"
    private let identifiers: Set<String> = [
        "duel.hero.ember", "duel.hero.liu", "duel.practice", "duel.pause", "duel.resume", "duel.exit",
        "duel.control.weapon", "duel.control.shadow", "duel.control.joystick",
        "duel.stats.0", "duel.stats.1", "duel.name.0", "duel.name.1",
        "duel.triad.status", "duel.triad.control", "duel.resourceError", "duel.hits",
        "duel.lobby.orientationTransition"
    ]

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws {
        if !completed { capture("shared-root-ui-failure") }
        if let encoded = try? JSONEncoder().encode(observations),
           let rows = try? JSONSerialization.jsonObject(with: encoded) {
            let report: [String: Any] = [
                "expectedReleaseSHA256": "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5",
                "releaseIdentitySource": "Workflow audit of the built App; UI process observes visible controls only",
                "launchArguments": ["-demo", "-screen", "fighter"],
                "flowCompleted": completed, "lastPhase": phase,
                "observations": rows, "captures": captures,
                "scope": "Two real selections and practice views; Sun branches input, visible root control and HP change",
                "screenshotsRequireVisualReview": true,
                "observationsAndScreenshotsShareExactFrame": false,
                "exactRootAnimationTicksObserved": false,
                "audiblePlaybackVerified": false, "physicalDeviceVerified": false,
                "internalCombatStateInjected": false, "panguEquipmentActivated": false
            ]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "shared-root-ui-observations"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        XCUIApplication().terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    func testFinalSharedRootReleaseShowsBothFightersAndAcceptsSunBranchesThroughRealControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-screen", "fighter"]
        XCUIDevice.shared.orientation = .portrait
        phase = "launch"
        app.launch()
        XCTAssertTrue(app.buttons["duel.hero.ember"].waitForExistence(timeout: 30))
        _ = try wait(app, phase: "landscape-lobby", timeout: 8) {
            $0.width > $0.height && $0.count("duel.lobby.orientationTransition") == 0 &&
                $0.count("duel.hero.ember") == 1 && $0.count("duel.hero.liu") == 1
        }

        for (hero, person, weapon) in [("ember", "孙登", "黑色双刀"), ("liu", "刘泉纬", "双锤")] {
            phase = hero + "-select"
            let selection = app.buttons["duel.hero." + hero]
            XCTAssertTrue(selection.isHittable)
            selection.tap()
            _ = try wait(app, phase: hero + "-selected", timeout: 12) {
                $0.value("duel.hero." + hero) == "已选择" && $0.width > $0.height
            }
            capture("shared-root-ui-" + (hero == "ember" ? "sun" : "liu") + "-lobby")
            let practice = app.buttons["duel.practice"]
            XCTAssertTrue(practice.isHittable)
            practice.tap()
            // Existing UI flow budgets are retained. Readiness observes the
            // source entrance ending; a fixed delay cannot substitute for it.
            let ready = try wait(app, phase: hero + "-practice-ready", timeout: 15) { $0.isReadyPractice }
            XCTAssertEqual(ready.label("duel.name.0"), person + " · " + weapon)
            XCTAssertTrue(ready.label("duel.name.1").contains(hero == "ember" ? "刘泉纬" : "孙登"))
            capture("shared-root-ui-" + (hero == "ember" ? "sun" : "liu") + "-practice")

            guard hero == "ember" else { continue }
            let before = try wait(app, phase: "sun-branches-ready", timeout: 12) {
                $0.isReadyPractice && $0.label("duel.control.shadow") == "枝蔓囚笼" &&
                    $0.value("duel.control.shadow") == "可施放"
            }
            let health = try XCTUnwrap(integer(after: "生命 ", in: before.value("duel.stats.1")))
            XCTAssertGreaterThan(health, 0)
            // Default practice positions already support the reviewed root
            // contact. Leave the joystick centered; directional shadow selects
            // another source skill and must not satisfy this scenario.
            let branches = app.buttons["duel.control.shadow"]
            XCTAssertTrue(branches.isHittable)
            branches.tap()
            _ = try wait(app, phase: "sun-root-visible", timeout: 8) { observation in
                guard observation.error == nil, observation.count("duel.resourceError") == 0,
                      let currentHP = self.integer(after: "生命 ", in: observation.value("duel.stats.1")) else { return false }
                return observation.label("duel.triad.control").contains("根枝束缚") && currentHP < health
            }
            capture("shared-root-ui-sun-root-observed")
            _ = try wait(app, phase: "sun-root-control-released", timeout: 12) { observation in
                guard observation.error == nil, observation.count("duel.resourceError") == 0,
                      let currentHP = self.integer(after: "生命 ", in: observation.value("duel.stats.1")) else { return false }
                return observation.count("duel.pause") == 1 && currentHP < health &&
                    !observation.label("duel.triad.control").contains("根枝束缚")
            }
            // Control expiry is observable here; it does not assert the exact
            // End clip frame or tick38. Those have separate native/Core gates.
            capture("shared-root-ui-sun-root-control-released")
            app.buttons["duel.pause"].tap()
            XCTAssertTrue(app.buttons["duel.exit"].waitForExistence(timeout: 5))
            app.buttons["duel.exit"].tap()
            XCTAssertTrue(app.buttons["duel.hero.liu"].waitForExistence(timeout: 12))
        }
        phase = "both-practice-scenes-captured"
        completed = true
    }

    private func wait(_ app: XCUIApplication, phase: String, timeout: TimeInterval,
                      until predicate: @escaping (Observation) -> Bool) throws -> Observation {
        self.phase = phase
        var last: Observation?
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let current = self.observe(app, phase: phase)
            last = current
            return predicate(current)
        }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Did not observe \(phase) within its bounded UI budget")
        guard result == .completed, let last else { throw Failure.notObserved(phase) }
        return last
    }

    private func observe(_ app: XCUIApplication, phase: String) -> Observation {
        let start = ProcessInfo.processInfo.systemUptime
        let observation: Observation
        do {
            let root = try app.snapshot()
            var pending = [root], elements: [String: [Element]] = [:]
            while let node = pending.popLast() {
                if identifiers.contains(node.identifier) {
                    elements[node.identifier, default: []].append(.init(label: node.label,
                        value: node.value as? String, enabled: node.isEnabled))
                }
                pending.append(contentsOf: node.children)
            }
            observation = .init(phase: phase, uptime: start,
                snapshotSeconds: ProcessInfo.processInfo.systemUptime - start,
                width: Double(root.frame.width), height: Double(root.frame.height), elements: elements, error: nil)
        } catch {
            observation = .init(phase: phase, uptime: start,
                snapshotSeconds: ProcessInfo.processInfo.systemUptime - start,
                width: 0, height: 0, elements: [:], error: String(describing: error))
        }
        observations.append(observation)
        return observation
    }

    private func integer(after marker: String, in text: String) -> Int? {
        guard let range = text.range(of: marker) else { return nil }
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

    private func capture(_ name: String) {
        let started = ProcessInfo.processInfo.systemUptime
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        captures.append(["name": name, "phase": phase, "uptime": started])
    }
}
