import XCTest
import UIKit

final class DuelXuXiaoPracticeFlowTests: XCTestCase {
    private struct MovementObservation {
        let modelDelta: Int
        let figureDeltaPt: CGFloat
        let relativeToControlDeltaPt: CGFloat
        let endHP: Int?
        let endOpponentX: Int?
        let shape: Bool

        var modelMoved: Bool { modelDelta >= 96 } // Two 48-unit practice ticks.
        var moved: Bool { modelMoved && shape && figureDeltaPt >= 5 && relativeToControlDeltaPt >= 5 }
    }

    func testReplacementPracticePlaysAndReturnsToGames() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        app.launchArguments = ["-demo", "-screen", "game"]
        app.launch()
        let enter = app.buttons["games.xuxiao.practice.enter"]
        XCTAssertTrue(enter.waitForExistence(timeout: 30), "xu-preview-games-entry")
        for _ in 0..<3 where !enter.isHittable { app.swipeUp() }
        XCTAssertTrue(enter.isHittable, "xu-preview-games-entry-hittable")
        enter.tap()
        // Freeze the bout before slower title, layout and control queries.
        let pause = app.buttons["xuxiao.practice.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 25) && pause.isHittable, "xu-preview-pause-hittable")
        pause.tap()
        XCTAssertEqual(pause.label, "继续", "xu-preview-pause-state")
        XCTAssertFalse(app.buttons["xuxiao.practice.attack"].isEnabled, "xu-preview-paused-input")
        // A SwiftUI semantic header may be exposed as staticText or other.
        // Require the exact unique ID plus exact label; never accept fallback text.
        let titleMatches = app.descendants(matching: .any).matching(identifier: "xuxiao.practice.title")
        let title = titleMatches.firstMatch
        let titleAppeared = title.waitForExistence(timeout: 25)
        XCTAssertTrue(titleAppeared, "xu-preview-title")
        XCTAssertEqual(titleMatches.count, 1, "xu-preview-title-unique")
        XCTAssertEqual(title.label, "徐骁 · 替代练习版", "xu-preview-replacement-label")
        let window = app.windows.firstMatch
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            window.exists && window.frame.width > window.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 12), .completed, "xu-preview-landscape")
        let descendants = app.descendants(matching: .any)
        let player = descendants.matching(identifier: "xuxiao.practice.fighter.0").firstMatch
        let opponent = descendants.matching(identifier: "xuxiao.practice.fighter.1").firstMatch
        let right = descendants.matching(identifier: "xuxiao.practice.right").firstMatch
        XCTAssertTrue(player.exists, "xu-preview-fighter-exists")
        let windowFrame = window.frame
        let otherSnapshot = try opponent.snapshot()
        let otherStart = otherSnapshot.frame
        let start = try player.snapshot()
        let startX = try XCTUnwrap(modelX(start.value), "xu-preview-initial-model-position")
        XCTAssertTrue(validFigureFrame(start.frame, in: windowFrame) && validFigureFrame(otherStart, in: windowFrame),
                      "xu-preview-initial-figure-frame")

        let rightFrame = right.frame
        XCTAssertTrue(right.exists && !rightFrame.isEmpty && windowFrame.contains(rightFrame),
                      "xu-preview-movement-controls")
        let notice = app.buttons["xuxiao.practice.notice"]
        pause.tap()
        // Let XCTest resolve the live control hit point in the current scene.
        // iPhone enters from portrait; replaying a window-relative point can
        // use a different coordinate space after the landscape presentation.
        let pressStart = ProcessInfo.processInfo.systemUptime
        let requestedHoldMs = 380
        right.press(forDuration: Double(requestedHoldMs) / 1000)
        let pressCallMs = Int((ProcessInfo.processInfo.systemUptime - pressStart) * 1000)
        // Opening the notice pauses play. Inspect the response to this one
        // physical hold before letting the opponent finish the round.
        notice.tap()
        let alert = app.alerts["替代练习版，不是正式徐骁"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "xu-preview-notice")
        alert.buttons["知道了"].tap()

        // Require multiple real movement ticks and a separately observed
        // displacement of the figure itself. The AX element's snapshot pairs
        // its current geometry and semantic value in one observation.
        let currentWindow = window.frame
        let currentRight = right.frame
        XCTAssertTrue(abs(currentWindow.width - windowFrame.width) <= 2 &&
                      currentRight.contains(CGPoint(x: rightFrame.midX, y: rightFrame.midY)),
                      "xu-preview-movement-controls")
        func observeMovement() -> MovementObservation? {
            guard let current = try? player.snapshot(),
                  let x = modelX(current.value), let currentOpponent = try? opponent.snapshot() else { return nil }
            let other = currentOpponent.frame
            // Both figures share floor and size, including when text reflows.
            // A container accessibility frame may just enclose its children.
            let sameFloor = abs((current.frame.midY - other.midY) - (start.frame.midY - otherStart.midY)) <= 2
            let sameSize = abs((current.frame.width - other.width) - (start.frame.width - otherStart.width)) <= 2
            let geometry = validFigureFrame(current.frame, in: currentWindow) &&
                validFigureFrame(other, in: currentWindow) && sameFloor && sameSize
            let distance = (current.frame.midX - currentRight.midX) - (start.frame.midX - rightFrame.midX)
            let figureDelta = (current.frame.midX - currentWindow.minX) - (start.frame.midX - windowFrame.minX)
            return MovementObservation(modelDelta: x - startX, figureDeltaPt: figureDelta,
                relativeToControlDeltaPt: distance, endHP: modelHP(current.value),
                endOpponentX: modelX(currentOpponent.value), shape: geometry)
        }
        var observation: MovementObservation?
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            if observation?.moved != true { observation = observeMovement() }
            return observation?.moved == true
        }, object: nil)
        let motionResult = XCTWaiter.wait(for: [moved], timeout: 8)
        var evidence = ""
        if motionResult != .completed {
            func points(_ n: CGFloat) -> Int {
                guard n.isFinite, abs(n) < 10000 else { return -10000 }
                return Int(n.rounded())
            }
            let facts: [String: Int] = [
                "startX": startX, "endX": observation.map { startX + $0.modelDelta } ?? -1,
                "startHP": modelHP(start.value) ?? -1, "endHP": observation?.endHP ?? -1,
                "startOpponentX": modelX(otherSnapshot.value) ?? -1,
                "endOpponentX": observation?.endOpponentX ?? -1,
                "figureDX": points(observation?.figureDeltaPt ?? .nan), "windowW": points(windowFrame.width),
                "windowH": points(windowFrame.height), "rightCX": points(rightFrame.midX),
                "rightCY": points(rightFrame.midY), "pressCallMs": min(99999, max(0, pressCallMs)),
                "terminal": app.staticTexts["xuxiao.practice.result"].exists ? 1 : 0,
                "paused": pause.label == "继续" ? 1 : 0, "shapeValid": observation?.shape == true ? 1 : 0
            ]
            if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys]),
               let message = String(data: data, encoding: .utf8) {
                evidence = " XU_PREVIEW_MOVEMENT " + message
                print(evidence)
            }
            XCTAssertTrue(observation?.modelMoved == true, "xu-preview-player-model-moved" + evidence)
            XCTAssertTrue(observation?.shape == true, "xu-preview-player-figure-geometry" + evidence)
        }
        XCTAssertEqual(motionResult, .completed, "xu-preview-player-figure-moved" + evidence)
        XCTAssertEqual(pause.label, "继续", "xu-preview-notice-pauses")
        pause.tap()
        XCTAssertEqual(pause.label, "暂停", "xu-preview-resume-state")
        XCTAssertTrue(right.isHittable, "xu-preview-movement-controls")
        let result = app.staticTexts["xuxiao.practice.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 78), "xu-preview-result")
        XCTAssertFalse(app.buttons["xuxiao.practice.attack"].isEnabled, "xu-preview-result-input")
        let rematch = app.buttons["xuxiao.practice.rematch"]
        XCTAssertTrue(rematch.isHittable, "xu-preview-rematch")
        rematch.tap()
        let restarted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !result.exists && app.buttons["xuxiao.practice.attack"].isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restarted], timeout: 10), .completed, "xu-preview-restarted")
        app.buttons["xuxiao.practice.close"].tap()
        XCTAssertTrue(enter.waitForExistence(timeout: 12), "xu-preview-returned")
        XCTAssertFalse(title.exists, "xu-preview-closed")

        let measured = try XCTUnwrap(observation)
        let receipt: [String: Any] = [
            "modelDelta": measured.modelDelta, "figureDeltaPt": Double(measured.figureDeltaPt),
            "relativeToControlDeltaPt": Double(measured.relativeToControlDeltaPt),
            "windowWidthPt": Double(currentWindow.width), "windowHeightPt": Double(currentWindow.height),
            "requestedHoldMs": requestedHoldMs, "pressCallMs": pressCallMs
        ]
        let data = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
        print("RIFT_PRACTICE " + String(decoding: data, as: UTF8.self))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "RIFT_PRACTICE"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func modelX(_ value: Any?) -> Int? {
        guard let description = value as? String, description.hasPrefix("位置 "),
              let separator = description.firstIndex(of: "，"),
              let x = Int(description[description.index(description.startIndex, offsetBy: 3)..<separator]),
              (700...9300).contains(x) else { return nil }
        return x
    }

    private func modelHP(_ value: Any?) -> Int? {
        guard let description = value as? String,
              let health = description.components(separatedBy: "，").dropFirst().first,
              health.hasPrefix("生命 "), let hp = Int(health.dropFirst(3)), (0...100).contains(hp) else {
            return nil
        }
        return hp
    }

    private func validFigureFrame(_ figure: CGRect, in window: CGRect) -> Bool {
        guard !figure.isNull, !figure.isInfinite, !figure.isEmpty, figure.width.isFinite,
              figure.height.isFinite, figure.midX.isFinite, figure.midY.isFinite,
              window.width > window.height else { return false }
        // The practice renderer caps figures at 130 pt high and 65% as wide.
        return window.contains(CGPoint(x: figure.midX, y: figure.midY))
            && figure.height <= 132 && abs(figure.width - 0.65 * figure.height) <= 2
    }
}
