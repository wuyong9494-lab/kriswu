import XCTest
import CryptoKit
import ImageIO

/// A short, separate screen-evidence flow. The already successful shared-root
/// gameplay method is not repeated. These bytes come from the normal simulator
/// window, never from a SceneKit/Metal offscreen capture or injected fight state.
final class DuelNormalFrameCaptureTests: XCTestCase {
    private static let selector = "ArenaFlowTests/DuelNormalFrameCaptureTests/testSunPracticeCapturesTwoNormalWindowFrames"
    private static let schema = "fighter-normal-frame-capture-v3"
    private static let release = "e5c0ccaeef85ce86c5b8fd4ee64524794d6556f5a561f4078362f6899bedf4e5"
    private static let directoryName = "FighterNormalFrameCapture"
    private static let reportName = "normal-frame-capture-report.json"
    private static let labels = ["normal-sun-practice-ready", "normal-sun-practice-later"]
    private static let launchArguments = ["-demo", "-screen", "fighter"]

    private static let diagnosticLabels = ["lobby-before-sun-touch", "normal-frame-failure"]

    private struct Frame: Codable {
        let x: Double, y: Double, width: Double, height: Double
        init(_ rect: CGRect) {
            x = Double(rect.minX); y = Double(rect.minY)
            width = Double(rect.width); height = Double(rect.height)
        }
        var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
        var valid: Bool { [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0 }
        var dictionary: [String: Double] { ["x": x, "y": y, "width": width, "height": height] }
    }

    private struct Element: Codable {
        let label: String
        let value: String?
        let enabled: Bool
        let frame: Frame
        let windowFrame: Frame?
    }

    private struct Observation: Codable {
        let phase: String
        let uptime: TimeInterval
        let snapshotSeconds: TimeInterval
        let width: Double
        let height: Double
        let elements: [String: [Element]]
        let rootFrame: Frame
        let windowFrames: [Frame]
        let sunTitleFrames: [Frame]
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
    private var diagnosticCaptures: [[String: Any]] = []
    private var diagnosticErrors: [[String: String]] = []
    private var selectionTouch: [String: Any]?
    private var failureCaptureAttempted = false
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
            captureFailureOnce()
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
            // The one root snapshot proves both entry and landscape readiness.
            // Do not spend a separate element existence query before observing
            // the same lobby; this replaces the previous 30 + 8 second waits.
            _ = try wait(phase: "landscape-lobby", timeout: 30) {
                $0.width > $0.height && $0.count("duel.lobby.orientationTransition") == 0 &&
                    $0.count("duel.hero.ember") == 1 && $0.count("duel.hero.liu") == 1
            }
            phase = "sun-select-before-touch"
            try captureDiagnostic(Self.diagnosticLabels[0])
            try tapSunFromFreshGeometry()
            _ = try wait(phase: "sun-selected", timeout: 12) {
                $0.count("duel.hero.ember") == 1 && $0.count("duel.hero.liu") == 1 &&
                    $0.value("duel.hero.ember") == "已选择" &&
                    $0.value("duel.hero.liu") == "未选择" && $0.width > $0.height
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
            if sidecarDirectory != nil {
                captureFailureOnce()
                try? writeReport()
            }
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
            var pending = [(root, Optional<CGRect>.none)], elements: [String: [Element]] = [:]
            var windows: [Frame] = [], titles: [Frame] = []
            while let (node, parentWindow) = pending.popLast() {
                let window = node.elementType == .window ? node.frame : parentWindow
                if node.elementType == .window { windows.append(Frame(node.frame)) }
                if identifiers.contains(node.identifier) {
                    elements[node.identifier, default: []].append(.init(label: node.label,
                        value: node.value as? String, enabled: node.isEnabled, frame: Frame(node.frame),
                        windowFrame: window.map(Frame.init)))
                }
                if node.identifier == "duel.hero.ember" {
                    var labels = node.children
                    while let label = labels.popLast() {
                        if label.elementType == .staticText && label.label == "孙登" {
                            titles.append(Frame(label.frame))
                        }
                        labels.append(contentsOf: label.children)
                    }
                }
                pending.append(contentsOf: node.children.map { ($0, window) })
            }
            observation = .init(phase: phase, uptime: started,
                snapshotSeconds: ProcessInfo.processInfo.systemUptime - started,
                width: Double(root.frame.width), height: Double(root.frame.height), elements: elements,
                rootFrame: Frame(root.frame), windowFrames: windows, sunTitleFrames: titles, error: nil)
        } catch {
            observation = .init(phase: phase, uptime: started,
                snapshotSeconds: ProcessInfo.processInfo.systemUptime - started,
                width: 0, height: 0, elements: [:], rootFrame: Frame(.zero),
                windowFrames: [], sunTitleFrames: [], error: "accessibility-snapshot-unavailable")
        }
        observations.append(observation)
        try writeReport()
        return observation
    }

    private func tapSunFromFreshGeometry() throws {
        guard selectionTouch == nil else { throw Failure.duplicateEvidence }
        phase = "sun-touch-geometry"
        let observed = try observe()
        guard observed.error == nil, observed.width > observed.height,
              observed.count("duel.hero.ember") == 1, observed.count("duel.hero.liu") == 1,
              observed.value("duel.hero.ember") == "未选择", observed.value("duel.hero.liu") == "已选择",
              let sun = observed.elements["duel.hero.ember"]?.first,
              let liu = observed.elements["duel.hero.liu"]?.first,
              sun.enabled, sun.frame.valid, liu.frame.valid, observed.rootFrame.valid,
              let window = sun.windowFrame, window.valid,
              observed.rootFrame.rect.contains(sun.frame.rect), window.rect.contains(sun.frame.rect),
              !sun.frame.rect.intersects(liu.frame.rect) else { throw Failure.missingControl("sun-touch-geometry") }
        let titleFrames = observed.sunTitleFrames.filter { $0.valid && sun.frame.rect.contains($0.rect) }
        guard titleFrames.count <= 1 else { throw Failure.missingControl("ambiguous-sun-title") }
        let target = titleFrames.first ?? sun.frame
        let point = CGPoint(x: target.rect.midX, y: target.rect.midY)
        guard sun.frame.rect.insetBy(dx: 1, dy: 1).contains(point), window.rect.contains(point),
              observed.rootFrame.rect.contains(point) else { throw Failure.missingControl("sun-point-outside-button") }
        let offset = CGVector(dx: point.x - observed.rootFrame.rect.minX,
                              dy: point.y - observed.rootFrame.rect.minY)
        let coordinate = app.coordinate(withNormalizedOffset: .zero).withOffset(offset)
        let observedEnd = observed.uptime + observed.snapshotSeconds
        selectionTouch = [
            "identifier": "duel.hero.ember", "tapCount": 0, "invocationState": "intent",
            "observationIndex": observations.count - 1,
            "rootFrame": observed.rootFrame.dictionary, "windowFrame": window.dictionary,
            "buttonFrame": sun.frame.dictionary, "targetFrame": target.dictionary,
            "targetKind": titleFrames.isEmpty ? "observed-button-center" : "observed-sun-title-center",
            "pointInScreenCoordinates": ["x": Double(point.x), "y": Double(point.y)],
            "offsetFromAppOrigin": ["x": Double(offset.dx), "y": Double(offset.dy)],
            "observationFinishedUptime": observedEnd,
            "intentPreparedAtUptime": ProcessInfo.processInfo.systemUptime,
            "invokedAtUptime": NSNull(), "returnedAtUptime": NSNull(),
            "maximumObservationAgeAtInvocationSeconds": 2,
            "api": "XCUIApplication.coordinate(withNormalizedOffset:).withOffset(_:).tap()",
            "coordinateBasis": "Observed AX frames in screen coordinates; offset relative to application root origin",
            "synthesizedEventTimeObserved": false, "internalSelectionStateInjected": false,
            "retryPerformed": false
        ]
        // Persist intent before any call. If this write stalls, the later age
        // check rejects the stale geometry; the durable report still says zero
        // recorded invocations. If interrupted inside tap, intent alone cannot
        // establish whether any input was delivered.
        try writeReport()
        let invoked = ProcessInfo.processInfo.systemUptime
        guard invoked >= observedEnd, invoked - observedEnd <= 2.0 else {
            throw Failure.notObserved("fresh-sun-touch-geometry")
        }
        // No synchronous I/O or UI query may enter between this age check and
        // tap. Only in-memory bookkeeping occurs here. Return or teardown later
        // persists the actual call, separately from its earlier durable intent.
        selectionTouch?["tapCount"] = 1
        selectionTouch?["invocationState"] = "called"
        selectionTouch?["invokedAtUptime"] = invoked
        coordinate.tap()
        selectionTouch?["returnedAtUptime"] = ProcessInfo.processInfo.systemUptime
        selectionTouch?["invocationState"] = "returned"
        try writeReport()
    }

    private func captureFailureOnce() {
        guard sidecarDirectory != nil, launched, !failureCaptureAttempted else { return }
        failureCaptureAttempted = true
        do { try captureDiagnostic(Self.diagnosticLabels[1]) }
        catch {
            // PNG persistence and its in-memory receipt precede writeReport.
            // A later report-write error must not claim those bytes are absent.
            if !diagnosticCaptures.contains(where: { $0["label"] as? String == Self.diagnosticLabels[1] }) {
                diagnosticErrors.append(["label": Self.diagnosticLabels[1], "error": "normal-window-capture-unavailable"])
            }
        }
    }

    private func captureDiagnostic(_ label: String) throws {
        guard let sidecarDirectory, Self.diagnosticLabels.contains(label), diagnosticCaptures.count < 2,
              !diagnosticCaptures.contains(where: { $0["label"] as? String == label }) else { throw Failure.duplicateEvidence }
        let started = ProcessInfo.processInfo.systemUptime
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let finished = ProcessInfo.processInfo.systemUptime
        guard data.count >= 24, data.count <= 24 * 1024 * 1024,
              Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10],
              Array(data[12..<16]) == [73, 72, 68, 82] else { throw Failure.invalidPNG }
        func integer(_ offset: Int) -> Int { data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) } }
        let width = integer(16), height = integer(20)
        guard width > 0, height > 0, width <= 5000, height <= 5000 else { throw Failure.invalidPNG }
        let file = label + ".png", destination = sidecarDirectory.appendingPathComponent(label + ".png")
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw Failure.duplicateEvidence }
        try data.write(to: destination, options: .atomic)
        diagnosticCaptures.append([
            "label": label, "file": file, "phase": phase, "bytes": data.count,
            "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            "width": width, "height": height, "captureStartedUptime": started, "captureFinishedUptime": finished,
            "captureAPI": "XCUIScreen.main.screenshot().pngRepresentation", "originalBytesUnmodified": true,
            "countsAsNormalPracticeFrame": false
        ])
        try writeReport()
    }

    @discardableResult
    private func capture(_ label: String) throws -> TimeInterval {
        guard let sidecarDirectory, captures.count < Self.labels.count,
              label == Self.labels[captures.count], let last = observations.last,
              last.isReadySunPractice else { throw Failure.notObserved("capture-preconditions") }
        phase = "capture-" + label
        try writeReport()
        let started = ProcessInfo.processInfo.systemUptime
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let finished = ProcessInfo.processInfo.systemUptime
        let geometry = try normalPNGGeometry(data, observation: last)
        let file = label + ".png"
        let destination = sidecarDirectory.appendingPathComponent(file)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw Failure.duplicateEvidence }
        // Preserve exactly XCUIScreen's PNG bytes, including its EXIF/XMP
        // orientation. No rotation, resizing, re-encoding or replacement frame.
        try data.write(to: destination, options: .atomic)
        var receipt: [String: Any] = [
            "label": label, "file": file, "phase": phase, "ordinal": captures.count + 1,
            "bytes": data.count, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            "captureStartedUptime": started, "captureFinishedUptime": finished,
            "observationIndex": observations.count - 1,
            "observationFinishedUptime": last.uptime + last.snapshotSeconds,
            "captureAPI": "XCUIScreen.main.screenshot().pngRepresentation", "originalBytesUnmodified": true,
            "orientationReader": "ImageIO CGImageSourceCopyPropertiesAtIndex"
        ]
        for (key, value) in geometry { receipt[key] = value }
        captures.append(receipt)
        try writeReport()
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = label; attachment.lifetime = .keepAlways; add(attachment)
        return finished
    }

    private func normalPNGGeometry(_ data: Data, observation: Observation) throws -> [String: Int] {
        guard data.count >= 24, data.count <= 24 * 1024 * 1024,
              Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10],
              Array(data[12..<16]) == [73, 72, 68, 82] else { throw Failure.invalidPNG }
        func integer(_ offset: Int) -> Int {
            data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
        }
        let width = integer(16), height = integer(20)
        guard width > 0, height > 0, width <= 5000, height <= 5000 else { throw Failure.invalidPNG }
        var offset = 8, exifCount = 0
        while offset < data.count {
            guard offset + 12 <= data.count else { throw Failure.invalidPNG }
            let count = integer(offset)
            guard count <= data.count - offset - 12 else { throw Failure.invalidPNG }
            if Array(data[(offset + 4)..<(offset + 8)]) == [101, 88, 73, 102] {
                guard (8...65536).contains(count) else { throw Failure.invalidPNG }
                exifCount += 1
            }
            offset += count + 12
        }
        // Apple documents this property as the TIFF/EXIF orientation value.
        // UIImage.Orientation uses different raw values and is not read here.
        guard exifCount == 1,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let storedWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let storedHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              storedWidth.doubleValue == Double(width), storedHeight.doubleValue == Double(height),
              let number = properties[kCGImagePropertyOrientation] as? NSNumber,
              number.doubleValue == Double(number.intValue), [1, 3, 6, 8].contains(number.intValue) else {
            throw Failure.invalidPNG
        }
        let orientation = number.intValue, swapsAxes = orientation == 6 || orientation == 8
        let displayWidth = swapsAxes ? height : width, displayHeight = swapsAxes ? width : height
        // This capture is pinned to an iPhone 17 Pro Max at exactly 3 pixels
        // per AX point. Stored portrait axes alone never authorize swapping.
        guard displayWidth > displayHeight,
              Double(displayWidth) == observation.width * 3,
              Double(displayHeight) == observation.height * 3 else { throw Failure.invalidPNG }
        return ["width": width, "height": height, "storedWidth": width, "storedHeight": height,
                "exifOrientation": orientation, "displayWidth": displayWidth, "displayHeight": displayHeight,
                "displayToAXScale": 3]
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
            "selectionTouch": selectionTouch.map { $0 as Any } ?? NSNull(),
            "selectionTouchPolicy": "one-coordinate-touch-from-fresh-observed-geometry",
            "diagnosticCaptures": diagnosticCaptures, "diagnosticCaptureErrors": diagnosticErrors,
            "allowedDiagnosticCaptureLabels": Self.diagnosticLabels,
            "diagnosticsCountAsNormalPracticeFrames": false,
            "writtenAtUptime": ProcessInfo.processInfo.systemUptime,
            "normalPresentationInternals": notObserved,
            "minimumSecondsBetweenCaptureOneEndAndLaterObservationStart": 1.0,
            "secondObservationWaitBudgetSeconds": 4.0,
            "normalPNGOrientationPolicy": "embedded-exif-nonmirrored-display-at-3x-AX; XMP-if-present-must-agree",
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
