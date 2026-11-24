import UIKit
import XCTest

/// Exercises the ordinary Today → Games → Duel → local versus route with a live opponent.
final class DuelLiveMatchFlowTests: XCTestCase {
    private var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var completedPhases = ["entryMs": -1, "lobbyMs": -1, "matchMs": -1]

    func testLiuCanHitSunFromToday() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Demo supplies a local work schedule and dismisses first-use schedule onboarding.
        // The game opens through visible navigation and runs its own clock and opponent.
        app.launchArguments = ["-demo", "-rift-live-readiness-diagnostics"]
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        app.launch()

        let games = app.buttons["app.tab.游戏"]
        XCTAssertTrue(games.waitForExistence(timeout: 12), "Bottom Games tab must be visible")
        XCTAssertTrue(games.isHittable, "Games tab must be reachable from Today")
        let entryStart = uptime
        games.tap()
        let duel = app.buttons["duel.enter"]
        let gameLists = [app.collectionViews.firstMatch, app.tables.firstMatch]
        XCTAssertTrue(revealButton(duel, containers: gameLists, timeout: 12), "The normal Games list must offer Duel")
        let entryMs = milliseconds(since: entryStart)
        completedPhases["entryMs"] = entryMs

        let lobbyStart = uptime
        duel.tap()
        let liu = app.buttons["duel.hero.liu"]
        let roster = app.scrollViews["duel.lobby.roster"]
        let actions = app.scrollViews["duel.lobby.actions"]
        let liuReady = revealButton(liu, containers: [roster, actions], timeout: 30)
        if !liuReady {
            recordProgress("liuSelection", since: lobbyStart, element: liu, in: app)
        }
        XCTAssertTrue(liu.exists, "The lobby must expose Liu's selection button")
        XCTAssertTrue(liu.isEnabled, "Liu's verified roster entry must be selectable")
        XCTAssertTrue(liuReady, "Liu's selection must be reachable within 30 seconds")
        liu.tap()
        XCTAssertEqual(liu.value as? String, "已选择")
        let versus = app.buttons["duel.start"]
        // The landscape action rail is fixed. Portrait and large-text layouts
        // scroll the entire action column, including the Start button.
        let startReady = revealButton(versus, containers: roster.exists ? [] : [actions], timeout: 30)
        if !startReady {
            recordProgress("versusStart", since: lobbyStart, element: versus, in: app)
        }
        XCTAssertTrue(versus.exists, "The lobby must expose the local match action")
        XCTAssertTrue(versus.isEnabled, "The visible showroom must finish preparing the match")
        XCTAssertTrue(startReady, "The local match action must be reachable within 30 seconds")
        let lobbyMs = milliseconds(since: lobbyStart)
        completedPhases["lobbyMs"] = lobbyMs

        let matchStart = uptime
        versus.tap()
        let weapon = app.buttons["duel.control.weapon"]
        var firstControlSeenMs = -1
        let sawControl = {
            if firstControlSeenMs == -1 { firstControlSeenMs = self.milliseconds(since: matchStart) }
        }
        // This is the original 30-second check, not a longer passing threshold.
        let gateDeadline = matchStart + 30
        let gateRemaining = gateDeadline - uptime
        let controlsOnTime = gateRemaining > 0
            && waitForButton(weapon, timeout: gateRemaining, onVisible: sawControl)
            && uptime <= gateDeadline
        let gateObservedMs = milliseconds(since: matchStart)
        if !controlsOnTime { recordProgress("matchControls", since: matchStart, element: weapon, in: app) }
        let controlsReady = controlsOnTime || waitForButton(weapon, timeout: 12, onVisible: sawControl)
        let matchMs = controlsReady ? milliseconds(since: matchStart) : -1
        guard controlsReady else {
            recordReadiness(controlsOnTime: controlsOnTime, firstSeenMs: firstControlSeenMs,
                            gateObservedMs: gateObservedMs, controlsReadyMs: -1,
                            openingReadyMs: -1, samples: [])
            XCTFail("The official match must mount live controls within 30 seconds; no controls in the bounded diagnostic tail")
            return
        }
        let intro = app.staticTexts["duel.intro"]
        let (openingReady, introSamples) = sampleOpening(intro, weapon: weapon, since: matchStart)
        let openingReadyMs = openingReady ? milliseconds(since: matchStart) : -1
        recordReadiness(controlsOnTime: controlsOnTime, firstSeenMs: firstControlSeenMs,
                        gateObservedMs: gateObservedMs, controlsReadyMs: matchMs,
                        openingReadyMs: openingReadyMs, samples: introSamples)
        if !openingReady { recordProgress("opening", since: matchStart, element: weapon, in: app) }
        XCTAssertTrue(openingReady,
                      "Sun's opening animation must release the controls and Liu's weapon must become ready")
        XCTAssertEqual(app.staticTexts["duel.name.0"].label, "刘泉纬")
        XCTAssertEqual(app.staticTexts["duel.name.1"].label, "孙登")
        XCTAssertFalse(app.staticTexts["duel.hits"].exists, "The training-only hit counter must be absent in versus")
        XCTAssertTrue(weapon.label.contains("毒牙双钩"))
        completedPhases["matchMs"] = matchMs

        let player = app.staticTexts["duel.stats.0"]
        let opponent = app.staticTexts["duel.stats.1"]
        let stick = app.descendants(matching: .any).matching(identifier: "duel.control.joystick").firstMatch
        XCTAssertTrue(stick.exists && stick.isHittable)
        let hitStart = uptime
        let combatDeadline = hitStart + 45
        var verifiedHit: (before: Int, after: Int)?
        var swings = 0
        var attempts = 0
        var approachHolds = 0
        var readinessBlocks = 0
        var lastGap = -1
        var lastBlocker = "notSampled"
        for _ in 0..<12 {
            guard uptime < combatDeadline else { break }
            attempts += 1
            let x = try XCTUnwrap(field("位置", of: player))
            let enemyX = try XCTUnwrap(field("位置", of: opponent))
            let gap = abs(enemyX - x)
            lastGap = gap
            if gap > 800 {
                lastBlocker = "distance"
                guard uptime < combatDeadline else { break }
                approachHolds += 1
                let offset = CGVector(dx: x < enemyX ? 0.86 : 0.14, dy: 0.5)
                stick.coordinate(withNormalizedOffset: offset).press(forDuration: gap > 1500 ? 0.8 : 0.35)
            } else {
                guard weapon.isEnabled && weapon.isHittable && weapon.value as? String == "可施放" else {
                    readinessBlocks += 1
                    lastBlocker = "readiness"
                    runUntil(combatDeadline, interval: 0.25)
                    continue
                }
                lastBlocker = "notSampled"
                // HP must fall after this actual press, not merely since opening.
                let before = try XCTUnwrap(field("生命", of: opponent))
                guard uptime < combatDeadline else { break }
                weapon.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                swings += 1
                lastBlocker = "hpUnchanged"
                let damage = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    guard let hp = self.field("生命", of: opponent), hp < before else { return false }
                    verifiedHit = (before, hp)
                    return true
                }, object: nil)
                let remaining = min(1.5, combatDeadline - uptime)
                if remaining > 0, XCTWaiter.wait(for: [damage], timeout: remaining) == .completed { break }
            }
        }
        if swings == 0 || verifiedHit == nil {
            let reason = uptime >= combatDeadline ? "elapsedBudget" : "attemptLimit"
            let diagnostics: [String: Any] = [
                "reason": reason, "lastBlocker": lastBlocker, "attempts": attempts,
                "approachHolds": approachHolds, "readinessBlocks": readinessBlocks,
                "weaponPresses": swings, "lastGap": lastGap
            ]
            recordProgress("combat", since: hitStart, element: weapon, in: app, combat: diagnostics)
        }
        XCTAssertGreaterThan(swings, 0, "Liu must make a physical weapon press; see combat diagnostics if none was made")
        let hit = try XCTUnwrap(verifiedHit, "Sun's live HP must fall after a physical weapon press")
        let hitMs = milliseconds(since: hitStart)

        app.buttons["duel.pause"].tap()
        XCTAssertTrue(app.buttons["duel.resume"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["duel.resourceError"].exists)
        let loaded = app.staticTexts["duel.characterStatus"].label
        XCTAssertTrue(loaded.contains("刘泉纬、孙登") && loaded.contains("毒牙双钩") && loaded.contains("黑色双刀"))
        let report = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "刷新回调 p95 ")).firstMatch
        XCTAssertTrue(report.waitForExistence(timeout: 5), "The live display callback must publish its observations")
        let text = report.label
        let pattern = #"刷新回调 p95 ([0-9]+[.,]?[0-9]*) ms · 慢回调 ([0-9]+)/([0-9]+)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let match = try XCTUnwrap(regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)))
        let values = (1...3).map { (text as NSString).substring(with: match.range(at: $0)) }
        let p95 = try XCTUnwrap(Double(values[0].replacingOccurrences(of: ",", with: ".")))
        let slow = try XCTUnwrap(Int(values[1]))
        let samples = try XCTUnwrap(Int(values[2]))
        XCTAssertGreaterThan(p95, 0)
        XCTAssertGreaterThan(samples, 1)
        XCTAssertLessThanOrEqual(slow, samples)

        let receipt: [String: Any] = [
            "entryMs": entryMs, "lobbyMs": lobbyMs, "matchMs": matchMs, "hitMs": hitMs,
            "hpBefore": hit.before, "hpAfter": hit.after, "weaponPresses": swings,
            "frameP95Ms": p95, "slowFrames": slow, "frameSamples": samples
        ]
        let data = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
        print("RIFT_LIVE " + String(decoding: data, as: UTF8.self))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "RIFT_LIVE"
        attachment.lifetime = .keepAlways
        add(attachment)
        // Late diagnostic success must never turn the original latency gate green.
        XCTAssertTrue(controlsOnTime, "The official match must mount live controls within 30 seconds")
    }

    private func revealButton(_ button: XCUIElement, containers: [XCUIElement], timeout: TimeInterval) -> Bool {
        let deadline = uptime + timeout
        var swipes = 0
        repeat {
            let exists = button.exists
            if exists && button.isEnabled && button.isHittable { return uptime <= deadline }
            if swipes < 8, let scroll = containers.first(where: { $0.exists && $0.isHittable }) {
                // A disabled visible row is waiting for verified content. Moving
                // it offscreen would obscure that state and waste the readiness budget.
                let buttonBounds = exists ? button.frame : .zero
                let visible = scroll.frame
                let middle = CGPoint(x: buttonBounds.midX, y: buttonBounds.midY)
                if !exists || (!buttonBounds.isEmpty && !visible.contains(middle)) {
                    if exists && middle.y < visible.minY { scroll.swipeDown() }
                    else { scroll.swipeUp() }
                    swipes += 1
                }
            }
            let remaining = deadline - uptime
            if remaining > 0 { RunLoop.current.run(until: Date(timeIntervalSinceNow: min(0.2, remaining))) }
        } while uptime < deadline
        return false
    }

    private func waitForButton(_ button: XCUIElement, timeout: TimeInterval, onVisible: @escaping () -> Void) -> Bool {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard button.exists else { return false }
            onVisible()
            return button.isEnabled && button.isHittable
        }, object: nil)
        return XCTWaiter.wait(for: [ready], timeout: timeout) == .completed
    }

    private func runUntil(_ deadline: TimeInterval, interval: TimeInterval) {
        let remaining = deadline - uptime
        if remaining > 0 { RunLoop.current.run(until: Date(timeIntervalSinceNow: min(interval, remaining))) }
    }

    private func sampleOpening(_ intro: XCUIElement, weapon: XCUIElement,
                               since start: TimeInterval) -> (Bool, [[String: Int]]) {
        let deadline = uptime + 20
        var samples: [[String: Int]] = []
        repeat {
            let visible = intro.exists
            let raw = visible ? (intro.value as? String).flatMap { Int($0) } : nil
            let ticks = raw.flatMap { (1...10000).contains($0) ? $0 : nil } ?? -1
            let playable = !visible && weapon.exists && weapon.isEnabled && weapon.isHittable
                && weapon.value as? String == "可施放"
            let elapsed = milliseconds(since: start)
            if (samples.last?["ms"] ?? -1) < elapsed {
                if samples.count == 8 { samples.removeLast() }
                samples.append(["ms": elapsed, "visible": visible ? 1 : 0, "ticks": ticks])
            }
            if playable && uptime <= deadline { return (true, samples) }
            runUntil(deadline, interval: 0.5)
        } while uptime < deadline
        return (false, samples)
    }

    private func recordReadiness(controlsOnTime: Bool, firstSeenMs: Int, gateObservedMs: Int,
                                 controlsReadyMs: Int, openingReadyMs: Int, samples: [[String: Int]]) {
        let facts: [String: Any] = ["controlGateMet": controlsOnTime, "controlGateSeconds": 30,
                                    "firstControlSeenMs": firstSeenMs, "gateObservedMs": gateObservedMs,
                                    "controlsReadyMs": controlsReadyMs, "openingReadyMs": openingReadyMs,
                                    "introSamples": samples]
        guard let data = try? JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]) else { return }
        print("RIFT_LIVE_READINESS " + String(decoding: data, as: UTF8.self))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "RIFT_LIVE_READINESS"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func milliseconds(since start: TimeInterval) -> Int {
        Int(((uptime - start) * 1000).rounded())
    }

    private func recordProgress(_ stage: String, since start: TimeInterval,
                                element: XCUIElement, in app: XCUIApplication,
                                combat: [String: Any]? = nil) {
        let elapsed = milliseconds(since: start)
        let targets = ["liuSelection": "duel.hero.liu", "versusStart": "duel.start",
                       "matchControls": "duel.control.weapon", "opening": "duel.control.weapon",
                       "combat": "duel.control.weapon"]
        guard let target = targets[stage] else { return }
        let observed: Set<String> = [
            "duel.enter", "duel.lobby.orientationTransition", "duel.lobby.roster", "duel.lobby.preparing",
            "duel.hero.liu", "duel.start", "duel.match.preparation", "duel.resourceError", "duel.pause",
            "duel.resume", "duel.intro", "duel.control.joystick", "duel.control.weapon", "duel.stats.1"
        ]
        let values = ["已选择": "selected", "未选择": "unselected", "人物准备中": "loading",
                      "专属角色资源尚未就绪": "unavailable", "角色资源校验未通过": "invalid",
                      "大厅资源未能载入，请返回后重试": "loadFailed", "可施放": "ready",
                      "暂不可施放": "notReady", "受击中": "hitRecovery", "收招中": "attackRecovery", "操作已暂停": "paused"]
        var facts: [String: Any] = ["stage": stage, "elapsedMs": elapsed, "snapshot": false,
                                    "found": false, "enabled": false, "hittable": false,
                                    "targetX": -1, "targetY": -1, "width": 0, "height": 0,
                                    "value": "unknown", "observed": [String](), "completed": completedPhases]
        if let combat = combat { facts["combat"] = combat }
        if let root = try? app.snapshot() {
            func point(_ number: CGFloat) -> Int {
                number.isFinite ? Int(max(-16000, min(16000, number)).rounded()) : -1
            }
            facts["snapshot"] = true
            facts["width"] = point(root.frame.width)
            facts["height"] = point(root.frame.height)
            var pending: [XCUIElementSnapshot] = [root]
            var found = Set<String>()
            while let node = pending.popLast() {
                if observed.contains(node.identifier) { found.insert(node.identifier) }
                if node.identifier == target {
                    facts["found"] = true
                    facts["enabled"] = node.isEnabled
                    facts["targetX"] = point(node.frame.midX)
                    facts["targetY"] = point(node.frame.midY)
                    facts["value"] = values[node.value as? String ?? ""] ?? "unknown"
                }
                pending.append(contentsOf: node.children)
            }
            facts["observed"] = found.sorted()
            if found.contains(target) { facts["hittable"] = element.isHittable }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]) else { return }
        print("RIFT_LIVE_PROGRESS " + String(decoding: data, as: UTF8.self))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "RIFT_LIVE_PROGRESS"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func field(_ name: String, of element: XCUIElement) -> Int? {
        guard let value = element.value as? String else { return nil }
        let prefix = name + " "
        let field = value.components(separatedBy: "，").first { $0.hasPrefix(prefix) }
        return field.flatMap { Int($0.dropFirst(prefix.count).replacingOccurrences(of: ",", with: "")) }
    }
}
