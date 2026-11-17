import XCTest

/// Real controls and normal window screenshots for the newly installed actors.
/// No legacy mode, injected combat state, accelerated clock or offscreen renderer.
final class DuelRecoveredCharacterFlowTests: XCTestCase {
    private struct Element: Codable {
        let label: String
        let value: String?
        let enabled: Bool
    }
    private struct Observation: Codable {
        let phase: String
        let uptime: TimeInterval
        let snapshotSeconds: TimeInterval
        let width, height: Double
        let elements: [String: [Element]]
        let error: String?

        func count(_ id: String) -> Int { elements[id]?.count ?? 0 }
        func label(_ id: String) -> String { elements[id]?.first?.label ?? "" }
        func value(_ id: String) -> String { elements[id]?.first?.value ?? "" }
        func enabled(_ id: String) -> Bool { elements[id]?.first?.enabled == true }
        var live: Bool {
            error == nil && width > height && count("duel.resourceError") == 0 &&
                count("duel.pause") == 1 && count("duel.resume") == 0 &&
                count("duel.stats.0") == 1 && count("duel.stats.1") == 1 &&
                value("duel.control.joystick") == "居中" && enabled("duel.control.weapon")
        }
    }
    private enum Failure: Error {
        case configuration(String), notObserved(String), resourceFailure, evidenceLimit
    }
    private let app = XCUIApplication()
    private let identifiers: Set<String> = [
        "duel.hero.ember", "duel.hero.liu", "duel.hero.wuyong_erlang", "duel.hero.gale",
        "duel.practice", "duel.pause", "duel.resume", "duel.exit",
        "duel.control.weapon", "duel.control.joystick", "duel.stats.0", "duel.stats.1",
        "duel.name.0", "duel.name.1", "duel.resourceError", "duel.hits",
        "duel.lobby.orientationTransition", "duel.lobby.preparing", "duel.lobby.selectedHero"
    ]
    private var observations: [Observation] = []
    private var captures: [[String: Any]] = []
    private var completedHeroes: [String] = []
    private var identity: [String: String] = [:]
    private var evidenceDirectory: URL?
    private var phase = "not-launched"
    private var flowCompleted = false
    private var launched = false

    override func setUpWithError() throws { continueAfterFailure = false }

    override func tearDownWithError() throws {
        defer {
            if launched { app.terminate() }
            XCUIDevice.shared.orientation = .portrait
        }
        guard evidenceDirectory != nil else { return }
        if launched && !flowCompleted {
            try capture("recovered-failure", normal: false)
        }
        try writeReport()
    }

    func testRecoveredFightersSelectMoveHitTwicePauseAndReturn() throws {
        try prepareEvidence()
        app.launchArguments = ["-demo", "-screen", "fighter"]
        XCUIDevice.shared.orientation = .portrait
        phase = "launch"
        launched = true
        app.launch()
        _ = try wait("landscape-lobby", timeout: 35) {
            $0.width > $0.height && $0.count("duel.lobby.orientationTransition") == 0 &&
                $0.count("duel.hero.ember") == 1 && $0.count("duel.hero.liu") == 1 &&
                $0.count("duel.hero.wuyong_erlang") == 1 && $0.count("duel.hero.gale") == 1
        }

        // Preferred opponent starts as Sun and is not changed by this flow.
        // Selecting Sun therefore uses the roster's first available opponent.
        for (hero, person, opponent) in [
            ("ember", "孙登", "刘泉纬"),
            ("liu", "刘泉纬", "孙登"),
            ("wuyong_erlang", "吴庸", "孙登")
        ] {
            phase = hero + "-select"
            let selection = app.buttons["duel.hero." + hero]
            let roster = app.scrollViews["duel.lobby.roster"]
            for _ in 0..<3 where !selection.isHittable { roster.swipeUp() }
            for _ in 0..<3 where !selection.isHittable { roster.swipeDown() }
            XCTAssertTrue(selection.isHittable)
            selection.tap()
            let lobby = try wait(hero + "-lobby-ready", timeout: 30) {
                $0.value("duel.hero." + hero) == "已选择" &&
                    $0.label("duel.lobby.selectedHero") == person &&
                    $0.count("duel.lobby.preparing") == 0 && $0.enabled("duel.practice") &&
                    $0.width > $0.height
            }
            XCTAssertFalse(lobby.enabled("duel.hero.gale"),
                           "The incomplete D20 actor must not be replaced by an unrelated fighter")
            try capture("recovered-" + hero + "-lobby")
            try tap("duel.practice")
            let ready = try wait(hero + "-practice-ready", timeout: 30) {
                $0.live && $0.label("duel.name.0") == person && $0.label("duel.name.1") == opponent
            }
            XCTAssertEqual(integer(after: "累计命中 ", in: ready.label("duel.hits")), 0)
            try capture("recovered-" + hero + "-practice")

            for hit in 1...2 {
                try approach(hero: hero, input: hit)
                let before = try wait(hero + "-weapon-ready-\(hit)", timeout: 12) {
                    $0.live && $0.value("duel.control.weapon") == "可施放"
                }
                let oldHits = try XCTUnwrap(integer(after: "累计命中 ", in: before.label("duel.hits")))
                let oldHealth = try XCTUnwrap(integer(after: "生命 ", in: before.value("duel.stats.1")))
                XCTAssertGreaterThan(oldHealth, 0)
                try tap("duel.control.weapon")
                _ = try wait(hero + "-weapon-contact-\(hit)", timeout: 15) {
                    guard $0.live,
                          let hits = self.integer(after: "累计命中 ", in: $0.label("duel.hits")),
                          let health = self.integer(after: "生命 ", in: $0.value("duel.stats.1")),
                          let damage = self.integer(after: "伤害 ", in: $0.label("duel.hits")) else { return false }
                    return hits > oldHits && health < oldHealth && damage > 0
                }
            }
            try capture("recovered-" + hero + "-two-inputs")

            try tap("duel.pause")
            let paused = try wait(hero + "-paused", timeout: 8) {
                $0.count("duel.resume") == 1 && $0.count("duel.exit") == 1 &&
                    $0.value("duel.control.joystick") == "操作已暂停"
            }
            let frozen = paused.value("duel.stats.0")
            let frozenHits = paused.label("duel.hits")
            _ = try wait(hero + "-pause-stable", timeout: 5) {
                $0.count("duel.resume") == 1 && $0.value("duel.stats.0") == frozen &&
                    $0.label("duel.hits") == frozenHits && $0.uptime >= paused.uptime + 1
            }
            try tap("duel.resume")
            _ = try wait(hero + "-resumed", timeout: 8) { $0.live }
            try tap("duel.pause")
            _ = try wait(hero + "-exit-available", timeout: 8) { $0.count("duel.exit") == 1 }
            try tap("duel.exit")
            _ = try wait(hero + "-returned-to-lobby", timeout: 30) {
                $0.value("duel.hero." + hero) == "已选择" && $0.enabled("duel.practice") &&
                    $0.count("duel.pause") == 0 && $0.count("duel.lobby.preparing") == 0
            }
            completedHeroes.append(hero)
            try writeReport()
        }
        XCTAssertEqual(captures.count, 9)
        XCTAssertEqual(completedHeroes, ["ember", "liu", "wuyong_erlang"])
        phase = "three-recovered-fighters-completed"
        flowCompleted = true
        try writeReport()
    }

    private func approach(hero: String, input: Int) throws {
        for step in 0..<16 {
            let before = try wait(hero + "-approach-\(input)-\(step)", timeout: 8) { $0.live }
            let player = try XCTUnwrap(integer(after: "位置 ", in: before.value("duel.stats.0")))
            let opponent = try XCTUnwrap(integer(after: "位置 ", in: before.value("duel.stats.1")))
            let distance = abs(opponent - player)
            if distance <= 800 { return }
            let stick = app.descendants(matching: .any).matching(identifier: "duel.control.joystick").firstMatch
            let direction: CGFloat = opponent > player ? 1 : -1
            stick.coordinate(withNormalizedOffset: CGVector(dx: 0.5 + direction * 0.36, dy: 0.5))
                .press(forDuration: distance > 1_500 ? 1 : 0.4)
            _ = try wait(hero + "-movement-\(input)-\(step)", timeout: 5) {
                guard $0.live, let next = self.integer(after: "位置 ", in: $0.value("duel.stats.0")) else { return false }
                return direction > 0 ? next > player : next < player
            }
        }
        throw Failure.notObserved(hero + "-close-weapon-range")
    }

    private func tap(_ id: String) throws {
        let button = app.buttons[id]
        guard button.isEnabled && button.isHittable else { throw Failure.notObserved("control-" + id) }
        button.tap()
    }

    private func wait(_ label: String, timeout: TimeInterval,
                      until predicate: @escaping (Observation) -> Bool) throws -> Observation {
        phase = label
        var last: Observation?
        var evidenceError: Error?
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            do {
                let current = try self.observe()
                last = current
                return current.count("duel.resourceError") > 0 || predicate(current)
            } catch {
                evidenceError = error
                return true
            }
        }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        if let evidenceError { throw evidenceError }
        if last?.count("duel.resourceError") ?? 0 > 0 { throw Failure.resourceFailure }
        guard result == .completed, let last, predicate(last) else { throw Failure.notObserved(label) }
        return last
    }

    private func observe() throws -> Observation {
        guard observations.count < 400 else { throw Failure.evidenceLimit }
        let started = ProcessInfo.processInfo.systemUptime
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
            observation = .init(phase: phase, uptime: started,
                snapshotSeconds: ProcessInfo.processInfo.systemUptime - started,
                width: Double(root.frame.width), height: Double(root.frame.height), elements: elements, error: nil)
        } catch {
            observation = .init(phase: phase, uptime: started,
                snapshotSeconds: ProcessInfo.processInfo.systemUptime - started,
                width: 0, height: 0, elements: [:], error: "accessibility-snapshot-unavailable")
        }
        observations.append(observation)
        try writeReport()
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

    private func prepareEvidence() throws {
        let environment = ProcessInfo.processInfo.environment
        for (key, pattern) in [
            ("FIGHTER_CAPTURE_SOURCE_SHA", "^[0-9a-f]{40}$"),
            ("FIGHTER_CAPTURE_RUN_ID", "^[1-9][0-9]{0,19}$"),
            ("FIGHTER_CAPTURE_RUN_ATTEMPT", "^1$")
        ] {
            guard let value = environment[key], value.range(of: pattern, options: .regularExpression) != nil else {
                throw Failure.configuration(key)
            }
            identity[key] = value
        }
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        let directory = documents.appendingPathComponent("FighterRecoveredCharacterCapture", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            throw Failure.configuration("fresh-run-evidence-directory")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        evidenceDirectory = directory
        try writeReport()
    }

    private func capture(_ name: String, normal: Bool = true) throws {
        guard let directory = evidenceDirectory, captures.count < 10 else { throw Failure.evidenceLimit }
        let started = ProcessInfo.processInfo.systemUptime
        let screenshot = XCUIScreen.main.screenshot()
        let png = screenshot.pngRepresentation
        guard png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]), png.count < 32_000_000 else {
            throw Failure.configuration("original-png")
        }
        // Preserve the framework's PNG bytes; do not rotate, redraw or resize.
        try png.write(to: directory.appendingPathComponent(name + ".png"), options: .withoutOverwriting)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        captures.append(["name": name, "file": name + ".png", "phase": phase,
                         "uptime": started, "bytes": png.count, "normalFlow": normal])
        try writeReport()
    }

    private func writeReport() throws {
        guard let directory = evidenceDirectory else { return }
        let rows = try JSONSerialization.jsonObject(with: JSONEncoder().encode(observations))
        let report: [String: Any] = [
            "schema": "recovered-character-flow-v1", "identity": identity,
            "expectedReleaseSHA256": "527e0195b7911e5b532aec92c37057f36a633952768670518565bde65605cbd3",
            "flowCompleted": flowCompleted, "completedHeroes": completedHeroes,
            "lastPhase": phase, "observations": rows, "captures": captures,
            "launchArguments": ["-demo", "-screen", "fighter"],
            "screenshotsRequireVisualReview": true, "observationsAndScreenshotsShareExactFrame": false,
            "exactComboTimingVerified": false, "audiblePlaybackVerified": false,
            "physicalDeviceVerified": false, "completeD20Accepted": false,
            "internalCombatStateInjected": false
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        try data.write(to: directory.appendingPathComponent("recovered-character-flow.json"), options: .atomic)
        if flowCompleted {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "recovered-character-flow"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
