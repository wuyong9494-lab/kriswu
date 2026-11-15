import XCTest
import CryptoKit

/// A short, separate screen-evidence flow. The already successful shared-root
/// gameplay method is not repeated. These bytes come from the normal simulator
/// window, never from a SceneKit/Metal offscreen capture or injected fight state.
final class DuelNormalFrameCaptureTests: XCTestCase {
    private static let selector = "ArenaFlowTests/DuelNormalFrameCaptureTests/testSunPracticeCapturesTwoNormalWindowFrames"
    private static let schema = "fighter-normal-frame-capture-v1"
    private static let release = "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"
    private static let directoryName = "FighterNormalFrameCapture"
    private static let reportName = "normal-frame-capture-report.json"
    private static let labels = ["normal-sun-practice-ready", "normal-sun-practice-later"]
    private static let launchArguments = ["-demo", "-screen", "fighter"]

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

        func count(_ identifier: String) -> Int { elements[identifier]?.count ?? 0 }
        func label(_ identifier: String) -> String { elements[identifier]?.first?.label ?? "" }
        func value(_ identifier: String) -> String { elements[identifier]?.first?.value ?? "" }
        var isReadySunPractice: Bool {
            error == nil && width > height && count("duel.resourceError") == 0 &&
                count("duel.pause") == 1 && count("duel.resume") == 0 &&
                count("duel.stats.0") == 1 && count("duel.stats.1") == 1 &&
                count("duel.name.0") == 1 && count("duel.name.1") == 1 &&
                label("duel.name.0") == "孙登 · 黑色双刀" &&
                label("duel.name.1") == "刘泉纬 · 双锤" &&
                value("duel.control.joystick") == "居中" &&
                value("duel.control.weapon") == "可施放"
        }
    }

    private enum Failure: Error {
        case configuration(String)
        case notObserved(String)
        case missingControl(String)
        case evidenceLimit
        case invalidPNG
        case duplicateEvidence
    }

    private let app = XCUIApplication()
    private var sidecarDirectory: URL?
    private var identity: [String: Any] = [:]
    private var observations: [Observation] = []
    private var captures: [[String: Any]] = []
    private var phase = "not-launched"
    private var flowCompleted = false
    private var failurePhase: String?
    private var launched = false
    private let identifiers: Set<String> = [
        "duel.hero.ember", "duel.hero.liu", "duel.practice", "duel.pause", "duel.resume",
        "duel.control.weapon", "duel.control.shadow", "duel.control.joystick",
        "duel.stats.0", "duel.stats.1", "duel.name.0", "duel.name.1",
        "duel.triad.status", "duel.triad.control", "duel.resourceError", "duel.hits",
        "duel.lobby.orientationTransition"
    ]

    override func setUpWithError() throws { continueAfterFailure = false }

    override func tearDownWithError() throws {
        // Durable originals and a partial report precede application teardown.
        // A result-bundle finalization failure must not be their only outlet.
        var writeError: Error?
        if sidecarDirectory != nil && !flowCompleted {
            do { try writeReport() } catch { writeError = error }
        }
        if launched { app.terminate() }
        XCUIDevice.shared.orientation = .portrait
        if let writeError { throw writeError }
    }

    func testSunPracticeCapturesTwoNormalWindowFrames() throws {
        do {
            try initializeSidecars()
            phase = "launch"
            try writeReport()
            app.launchArguments = Self.launchArguments
            XCUIDevice.shared.orientation = .portrait
            launched = true
            app.launch()
            guard app.buttons["duel.hero.ember"].waitForExistence(timeout: 30) else {
                throw Failure.notObserved("sun-lobby-entry")
            }
            _ = try wait(phase: "landscape-lobby", timeout: 8) {
                $0.width > $0.height && $0.count("duel.lobby.orientationTransition") == 0 &&
                    $0.count("duel.hero.ember") == 1 && $0.count("duel.hero.liu") == 1
            }
            phase = "sun-select"
            try writeReport()
            let sun = app.buttons["duel.hero.ember"]
            guard sun.isHittable else { throw Failure.missingControl("duel.hero.ember") }
            sun.tap()
            _ = try wait(phase: "sun-selected", timeout: 12) {
                $0.value("duel.hero.ember") == "已选择" && $0.width > $0.height
            }
            let practice = app.buttons["duel.practice"]
            guard practice.isHittable else { throw Failure.missingControl("duel.practice") }
            phase = "enter-sun-practice"
            try writeReport()
            practice.tap()
            _ = try wait(phase: "sun-practice-ready", timeout: 15) { $0.isReadySunPractice }
            let firstCaptureFinished = try capture(Self.labels[0])

            // This is elapsed normal presentation, not a claimed frame/tick
            // count. No pause/resume, skill, joystick or render API is called.
            _ = try wait(phase: "sun-practice-later", timeout: 4) {
                $0.isReadySunPractice && $0.uptime >= firstCaptureFinished + 1.0
            }
            _ = try capture(Self.labels[1])
            phase = "two-normal-window-images-saved"
            flowCompleted = true
            try writeReport()
            try attachReport()
        } catch {
            failurePhase = phase
            flowCompleted = false
            // Keep the original error. Teardown separately fails if the final
            // partial report cannot be persisted; no substitute image is made.
            if sidecarDirectory != nil { try? writeReport() }
            throw error
        }
    }

    private func initializeSidecars() throws {
        let environment = ProcessInfo.processInfo.environment
        func required(_ key: String, pattern: String) throws -> String {
            guard let value = environment[key],
                  let range = value.range(of: pattern, options: .regularExpression),
                  range.lowerBound == value.startIndex, range.upperBound == value.endIndex else {
                throw Failure.configuration(key)
            }
            return value
        }
        let source = try required("FIGHTER_CAPTURE_SOURCE_SHA", pattern: "^[0-9a-f]{40}$")
        let run = try required("FIGHTER_CAPTURE_RUN_ID", pattern: "^[1-9][0-9]{0,19}$")
        let attempt = try required("FIGHTER_CAPTURE_RUN_ATTEMPT", pattern: "^1$")
        let nonce = try required("FIGHTER_CAPTURE_NONCE", pattern: "^[0-9A-Fa-f-]{36}$")
        let expectedUDID = try required("FIGHTER_CAPTURE_SIMULATOR_UDID", pattern: "^[0-9A-Fa-f-]{36}$")
        guard UUID(uuidString: nonce) != nil, UUID(uuidString: expectedUDID) != nil,
              let actualUDID = environment["SIMULATOR_UDID"],
              UUID(uuidString: actualUDID) == UUID(uuidString: expectedUDID),
              let runnerID = Bundle.main.bundleIdentifier,
              let testBundleID = Bundle(for: DuelNormalFrameCaptureTests.self).bundleIdentifier,
              !runnerID.isEmpty, !testBundleID.isEmpty, runnerID != "com.kriswu.shiftreminder" else {
            throw Failure.configuration("runner-or-simulator-identity")
        }
        identity = [
            "sourceSHA": source, "runID": run, "runAttempt": attempt, "nonce": nonce,
            "expectedSimulatorUDID": expectedUDID, "actualSimulatorUDID": actualUDID,
            "runnerBundleIdentifier": runnerID, "testBundleIdentifier": testBundleID,
            "targetAppBundleIdentifier": "com.kriswu.shiftreminder",
            "identitySource": "Test Runner launch environment; CI must independently join build, source, run and owned simulator",
            "launchEnvironment": ["FIGHTER_CAPTURE_SOURCE_SHA": source, "FIGHTER_CAPTURE_RUN_ID": run,
                "FIGHTER_CAPTURE_RUN_ATTEMPT": attempt, "FIGHTER_CAPTURE_NONCE": nonce,
                "FIGHTER_CAPTURE_SIMULATOR_UDID": expectedUDID]
        ]
        let manager = FileManager.default
        guard let documents = manager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw Failure.configuration("runner-documents")
        }
        let parent = documents.appendingPathComponent(Self.directoryName, isDirectory: true)
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        guard try parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
              try parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw Failure.configuration("runner-sidecar-parent")
        }
        let destination = parent.appendingPathComponent(nonce, isDirectory: true)
        guard !manager.fileExists(atPath: destination.path) else { throw Failure.duplicateEvidence }
        try manager.createDirectory(at: destination, withIntermediateDirectories: false)
        sidecarDirectory = destination
        phase = "sidecar-initialized"
        try writeReport()
    }

    private func wait(phase next: String, timeout: TimeInterval,
                      until predicate: @escaping (Observation) -> Bool) throws -> Observation {
        phase = next
        try writeReport()
        var last: Observation?
        var observationError: Error?
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            do {
                let current = try self.observe()
                last = current
                return predicate(current)
            } catch {
                observationError = error
                return true
            }
        }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        if let observationError { throw observationError }
        guard result == .completed, let last else { throw Failure.notObserved(next) }
        return last
    }

    private func observe() throws -> Observation {
        guard observations.count < 128 else { throw Failure.evidenceLimit }
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

    @discardableResult
    private func capture(_ label: String) throws -> TimeInterval {
        guard let sidecarDirectory, captures.count < Self.labels.count,
              label == Self.labels[captures.count], let last = observations.last,
              last.isReadySunPractice else { throw Failure.notObserved("capture-preconditions") }
        let started = ProcessInfo.processInfo.systemUptime
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let finished = ProcessInfo.processInfo.systemUptime
        guard data.count >= 24, data.count <= 24 * 1024 * 1024,
              Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10],
              Array(data[12..<16]) == [73, 72, 68, 82] else { throw Failure.invalidPNG }
        func integer(_ offset: Int) -> Int {
            data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
        }
        let width = integer(16), height = integer(20)
        guard width > height, height > 0, width <= 5000 else { throw Failure.invalidPNG }
        let file = label + ".png"
        let destination = sidecarDirectory.appendingPathComponent(file)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw Failure.duplicateEvidence }
        // Preserve exactly XCUIScreen's PNG bytes, without resizing, re-encoding
        // or choosing a later replacement frame. PNG precedes its index row.
        try data.write(to: destination, options: .atomic)
        captures.append([
            "label": label, "file": file, "phase": phase, "ordinal": captures.count + 1,
            "bytes": data.count, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            "width": width, "height": height, "captureStartedUptime": started,
            "captureFinishedUptime": finished, "observationIndex": observations.count - 1,
            "observationFinishedUptime": last.uptime + last.snapshotSeconds,
            "captureAPI": "XCUIScreen.main.screenshot().pngRepresentation", "originalBytesUnmodified": true
        ])
        try writeReport()
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = label; attachment.lifetime = .keepAlways; add(attachment)
        return finished
    }

    private func reportData() throws -> Data {
        let rows = try JSONSerialization.jsonObject(with: JSONEncoder().encode(observations))
        let notObserved: [String: Any] = [
            "status": "notObserved", "normalFrames": NSNull(), "gameTick": NSNull(),
            "animationTick": NSNull(), "sourceLiveTick": NSNull(), "firstCommitCount": NSNull(),
            "presentationKickAttempts": NSNull(), "preparationReady": NSNull(), "sourceMusicReady": NSNull(),
            "reason": "The unchanged App does not expose these internals through its UI accessibility contract"
        ]
        return try JSONSerialization.data(withJSONObject: [
            "schema": Self.schema, "selector": Self.selector, "identity": identity,
            "expectedReleaseSHA256": Self.release,
            "releaseIdentitySource": "CI validation of the installed App; not an assertion obtained from the UI",
            "launchArguments": Self.launchArguments, "sidecarDirectory": Self.directoryName,
            "reportFile": Self.reportName, "expectedCaptureLabels": Self.labels,
            "phase": phase, "flowCompleted": flowCompleted,
            "failurePhase": failurePhase.map { $0 as Any } ?? NSNull(),
            "observations": rows, "captures": captures,
            "writtenAtUptime": ProcessInfo.processInfo.systemUptime,
            "normalPresentationInternals": notObserved,
            "minimumSecondsBetweenCaptureOneEndAndLaterObservationStart": 1.0,
            "secondObservationWaitBudgetSeconds": 4.0,
            "screenshotsRequireVisualReview": true, "visualReview": "PENDING",
            "observationsAndScreenshotsShareExactFrame": false,
            "xctestOutcomeIsProvidedByThisReport": false, "normalDrawableCountersVerified": false,
            "sourcePreparationSequenceVerifiedByUI": false, "frameOrTickProgressVerified": false,
            "offscreenCaptureUsed": false, "renderAPIsInvoked": false, "internalCombatStateInjected": false,
            "shadowSkillInvoked": false, "joystickInvoked": false, "pauseOrResumeInvoked": false,
            "otherCharacterPracticeInvoked": false, "audiblePlaybackVerified": false,
            "physicalDeviceVerified": false, "panguEquipmentActivated": false
        ], options: [.sortedKeys])
    }

    private func writeReport() throws {
        guard let sidecarDirectory else { throw Failure.configuration("sidecar-not-initialized") }
        let data = try reportData()
        guard data.count <= 1024 * 1024 else { throw Failure.evidenceLimit }
        try data.write(to: sidecarDirectory.appendingPathComponent(Self.reportName), options: .atomic)
    }

    private func attachReport() throws {
        guard let sidecarDirectory else { throw Failure.configuration("sidecar-not-initialized") }
        let data = try Data(contentsOf: sidecarDirectory.appendingPathComponent(Self.reportName))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "normal-frame-capture-report"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
