import XCTest
import UIKit
@testable import ShiftReminder

@MainActor
final class DuelSourceControlsTests: XCTestCase {
    private typealias Controls = DuelSourceControlsView

    private func controls() -> Controls {
        let view = Controls(images: [:])
        view.frame = CGRect(x: 0, y: 0, width: 956, height: 440)
        view.setNeedsLayout(); view.layoutIfNeeded()
        return view
    }

    private func center(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
    private func stickPoint(_ view: Controls, x: Int, y: Int) -> CGPoint {
        let layout = view.layoutSnapshot
        return CGPoint(x: layout.joystick.midX + CGFloat(x) * 180 * layout.scale,
                       y: layout.joystick.midY - CGFloat(y) * 180 * layout.scale)
    }

    func testSourceLayoutKeepsItsDiamondAndSafeMarginsOnPhonesAndTablet() throws {
        let cases: [(CGSize, UIEdgeInsets)] = [
            (CGSize(width: 956, height: 440), UIEdgeInsets(top: 0, left: 62, bottom: 21, right: 62)),
            (CGSize(width: 812, height: 375), UIEdgeInsets(top: 0, left: 44, bottom: 21, right: 44)),
            (CGSize(width: 1366, height: 1024), UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0))
        ]
        for (size, insets) in cases {
            let bounds = CGRect(origin: .zero, size: size), safe = bounds.inset(by: insets)
            let layout = Controls.makeLayout(in: bounds, safeArea: insets)
            XCTAssertEqual(layout.actions.count, 4)
            XCTAssertTrue(safe.insetBy(dx: -0.01, dy: -0.01).contains(layout.joystick))
            for action in Controls.Action.allCases {
                let frame = try XCTUnwrap(layout.actions[action])
                XCTAssertTrue(safe.insetBy(dx: -0.01, dy: -0.01).contains(frame), "\(size)/\(action)")
                XCTAssertGreaterThanOrEqual(frame.width, 44)
                XCTAssertTrue(try XCTUnwrap(layout.actionTouch[action]).contains(center(frame)))
            }
            let punch = try XCTUnwrap(layout.actions[.weapon]), kick = try XCTUnwrap(layout.actions[.kick])
            let ranged = try XCTUnwrap(layout.actions[.ranged]), shadow = try XCTUnwrap(layout.actions[.shadow])
            XCTAssertLessThan(shadow.midX, punch.midX)
            XCTAssertEqual(shadow.midY, punch.midY, accuracy: 0.001)
            XCTAssertLessThan(ranged.midY, punch.midY)
            XCTAssertGreaterThan(kick.midY, punch.midY)
            XCTAssertEqual(ranged.midX, (punch.midX + shadow.midX) / 2, accuracy: 0.001)
            XCTAssertEqual(punch.width / layout.joystick.width, 205.0 / 500.0, accuracy: 0.00001,
                           "Keep the measured source control proportions")
            XCTAssertLessThan(layout.joystick.maxX, shadow.minX)
        }
    }

    func testEightDirectionsHaveNeutralZoneAndWiderCardinalSectors() {
        let cases: [(CGPoint, Int, Int)] = [
            (.zero, 0, 0), (CGPoint(x: 65, y: 0), 0, 0),
            (CGPoint(x: 0, y: 200), 0, 1), (CGPoint(x: 150, y: 150), 1, 1),
            (CGPoint(x: 200, y: 0), 1, 0), (CGPoint(x: 150, y: -150), 1, -1),
            (CGPoint(x: 0, y: -200), 0, -1), (CGPoint(x: -150, y: -150), -1, -1),
            (CGPoint(x: -200, y: 0), -1, 0), (CGPoint(x: -150, y: 150), -1, 1),
            (CGPoint(x: 100, y: 50), 1, 0), (CGPoint(x: 100, y: 70), 1, 1),
            (CGPoint(x: 50, y: 100), 0, 1), (CGPoint(x: CGFloat.nan, y: 100), 0, 0)
        ]
        for (point, x, y) in cases {
            for scale in [CGFloat(0.25), 1, 2] {
                let result = Controls.quantizedDirection(offset: CGPoint(x: point.x * scale, y: point.y * scale), scale: scale)
                XCTAssertEqual(result.x, x); XCTAssertEqual(result.y, y)
            }
        }
    }

    func testDirectionArrivesBeforeAttackAndBothHandsRemainIndependent() throws {
        let view = controls()
        var events: [String] = []
        view.onDirection = { events.append("direction:\($0),\($1)") }
        view.onAction = { events.append("\($0.rawValue):\($1)") }
        let weapon = center(try XCTUnwrap(view.layoutSnapshot.actions[.weapon]))
        let kick = center(try XCTUnwrap(view.layoutSnapshot.actions[.kick]))
        // Reversed sample order must still form the direction+attack chord.
        view.beginPointers([.init(id: "weapon", location: weapon),
                            .init(id: "stick", location: stickPoint(view, x: 1, y: 0))])
        view.beginPointers([.init(id: "kick", location: kick)])
        view.endPointers(["weapon"])
        view.movePointers([.init(id: "stick", location: stickPoint(view, x: -1, y: -1))])
        view.endPointers(["kick", "stick"])
        XCTAssertEqual(events, ["direction:1,0", "weapon:true", "kick:true", "weapon:false",
                                "direction:-1,-1", "kick:false", "direction:0,0"])
    }

    func testOneOfTwoFingersCannotReleaseOrCancelTheOthersButton() throws {
        let view = controls()
        var events: [String] = []
        view.onAction = { events.append("\($0.rawValue):\($1)") }
        view.onActionCancelled = { events.append("cancel:\($0.rawValue)") }
        let point = center(try XCTUnwrap(view.layoutSnapshot.actions[.weapon]))
        view.beginPointers([.init(id: 1, location: point), .init(id: 2, location: point)])
        XCTAssertEqual(events, ["weapon:true"])
        view.cancelPointers([1])
        XCTAssertEqual(events, ["weapon:true"], "A second physical finger still holds the same action")
        view.endPointers([2, 1])
        XCTAssertEqual(events, ["weapon:true", "weapon:false"])
        view.beginPointers([.init(id: 3, location: point)])
        view.cancelPointers([3])
        XCTAssertEqual(Array(events.suffix(3)), ["weapon:true", "cancel:weapon", "weapon:false"])
    }

    func testDragOutCancelsBeforeReleaseAndNeverRetargetsAnotherButton() throws {
        let view = controls()
        var events: [String] = []
        var pending = Set<Controls.Action>()
        var completed: [Controls.Action] = []
        view.onAction = { action, down in
            events.append("\(action.rawValue):\(down)")
            if down { pending.insert(action) }
            else if pending.remove(action) != nil { completed.append(action) }
        }
        view.onActionCancelled = { action in
            events.append("cancel:\(action.rawValue)")
            pending.remove(action)
        }
        view.beginPointers([.init(id: "finger", location: center(try XCTUnwrap(view.layoutSnapshot.actions[.weapon])))])
        view.movePointers([.init(id: "finger", location: center(try XCTUnwrap(view.layoutSnapshot.actions[.kick])))])
        view.endPointers(["finger"])
        XCTAssertEqual(events, ["weapon:true", "cancel:weapon", "weapon:false"])
        XCTAssertTrue(completed.isEmpty, "Dragging off an action must cancel its pending tap before releasing")
        XCTAssertTrue(pending.isEmpty)
    }

    func testReadinessDoesNotReleaseHeldActionAndDisabledEquipmentCannotAttack() throws {
        let view = controls()
        var events: [String] = []
        view.onAction = { events.append("\($0.rawValue):\($1)") }
        view.onActionCancelled = { events.append("cancel:\($0.rawValue)") }
        view.setState(.init(enabled: false, ready: false, description: "未装备远程武器"), for: .ranged)
        view.beginPointers([.init(id: "ranged", location: center(try XCTUnwrap(view.layoutSnapshot.actions[.ranged])))])
        view.endPointers(["ranged"])
        XCTAssertTrue(events.isEmpty)
        view.beginPointers([.init(id: "weapon", location: center(try XCTUnwrap(view.layoutSnapshot.actions[.weapon])))])
        view.setState(.init(enabled: true, ready: false, description: "恢复中"), for: .weapon)
        XCTAssertEqual(events, ["weapon:true"])
        view.setState(.init(enabled: false, ready: false, description: "暂不可用"), for: .weapon)
        XCTAssertEqual(events, ["weapon:true", "cancel:weapon", "weapon:false"])
        view.endPointers(["weapon"])
        XCTAssertEqual(events.count, 3)
    }

    func testSecondStickTouchCannotStealDirectionAndFullCancellationClearsMailbox() throws {
        let view = controls()
        var directions: [String] = []
        var pendingDirection = false
        var cancellations = 0
        view.onDirection = { x, y in
            directions.append("\(x),\(y)")
            if x != 0 || y != 0 { pendingDirection = true }
        }
        view.onInputCancelled = { pendingDirection = false; cancellations += 1 }
        view.beginPointers([.init(id: "owner", location: stickPoint(view, x: 0, y: 1))])
        view.beginPointers([.init(id: "other", location: stickPoint(view, x: -1, y: 0))])
        view.movePointers([.init(id: "other", location: stickPoint(view, x: 1, y: 0))])
        XCTAssertEqual(directions, ["0,1"])
        XCTAssertTrue(pendingDirection)
        view.cancelPointers(["owner"])
        XCTAssertEqual(directions, ["0,1", "0,0"])
        XCTAssertFalse(pendingDirection)
        XCTAssertEqual(cancellations, 1)
        view.movePointers([.init(id: "other", location: stickPoint(view, x: 1, y: 0))])
        XCTAssertEqual(directions.count, 2)
    }

    func testPauseStyleCancellationAndLayoutChangeCannotTurnReleaseIntoATap() throws {
        let view = controls()
        var pending = Set<Controls.Action>()
        var completed: [Controls.Action] = []
        view.onAction = { action, down in
            if down { pending.insert(action) }
            else if pending.remove(action) != nil { completed.append(action) }
        }
        view.onActionCancelled = { pending.remove($0) }
        view.onInputCancelled = { pending.removeAll() }
        for changeLayout in [false, true] {
            view.inputEnabled = true
            view.beginPointers([.init(id: "weapon", location: center(try XCTUnwrap(view.layoutSnapshot.actions[.weapon])))])
            if changeLayout {
                view.frame = CGRect(x: 0, y: 0, width: 812, height: 375)
                view.setNeedsLayout(); view.layoutIfNeeded()
            } else {
                view.inputEnabled = false
            }
            view.endPointers(["weapon"])
            XCTAssertTrue(completed.isEmpty)
            XCTAssertTrue(pending.isEmpty)
        }
        view.inputEnabled = false
        view.beginPointers([.init(id: "blocked", location: center(try XCTUnwrap(view.layoutSnapshot.actions[.weapon])))])
        view.endPointers(["blocked"])
        XCTAssertTrue(completed.isEmpty)
        XCTAssertTrue(pending.isEmpty)
    }

    func testFullCancellationCanClearTheConsumerWithoutReentryOrRearmingTheBatch() throws {
        let view = controls()
        var events: [String] = []
        view.onAction = { events.append("\($0.rawValue):\($1)") }
        view.onActionCancelled = { events.append("cancel:\($0.rawValue)") }
        view.onInputCancelled = {
            events.append("cancel:all")
            view.cancelAll(notify: false)
        }
        view.onDirection = { x, y in
            events.append("direction:\(x),\(y)")
            if x != 0 || y != 0 { view.cancelAll() }
        }
        // Consumer cancellation during the first pointer invalidates the remaining
        // pointers from the same UIKit event, even if input is enabled afterward.
        view.beginPointers([.init(id: "weapon", location: center(try XCTUnwrap(view.layoutSnapshot.actions[.weapon]))),
                            .init(id: "stick", location: stickPoint(view, x: 1, y: 0))])
        XCTAssertEqual(events, ["direction:1,0", "cancel:all", "direction:0,0"])
        view.endPointers(["weapon", "stick"])
        XCTAssertEqual(events.count, 3)

        events.removeAll()
        view.beginPointers([.init(id: "weapon2", location: center(try XCTUnwrap(view.layoutSnapshot.actions[.weapon])))])
        view.cancelAll()
        view.endPointers(["weapon2"])
        XCTAssertEqual(events, ["weapon:true", "cancel:all", "cancel:weapon", "weapon:false"])
    }

    func testPauseAndEquipmentStatesAreVisibleToAccessibility() throws {
        let view = controls()
        let weapon = try XCTUnwrap(view.subviews.first { $0.accessibilityIdentifier == "duel.control.weapon" } as? UIButton)
        let stick = try XCTUnwrap(view.subviews.first { $0.accessibilityIdentifier == "duel.control.joystick" })
        view.setState(.init(enabled: true, ready: false, description: "收招中", accessibilityLabel: "孙登 · 武士刀"), for: .weapon)
        XCTAssertTrue(weapon.isEnabled)
        XCTAssertEqual(weapon.accessibilityLabel, "孙登 · 武士刀")
        XCTAssertEqual(weapon.accessibilityValue, "收招中")
        var cancellations = 0
        view.onInputCancelled = { cancellations += 1 }
        view.inputEnabled = false
        view.inputEnabled = false
        XCTAssertEqual(cancellations, 1)
        XCTAssertFalse(weapon.isEnabled)
        XCTAssertTrue(weapon.accessibilityTraits.contains(.notEnabled))
        XCTAssertTrue(stick.accessibilityTraits.contains(.notEnabled))
        XCTAssertEqual(weapon.accessibilityValue, "操作已暂停")
        XCTAssertFalse(weapon.accessibilityActivate())
        view.inputEnabled = true
        view.setState(.init(accessibilityLabel: "刘泉纬 · 双锤"), for: .weapon)
        XCTAssertTrue(weapon.isEnabled)
        XCTAssertFalse(weapon.accessibilityTraits.contains(.notEnabled))
        XCTAssertFalse(stick.accessibilityTraits.contains(.notEnabled))
        XCTAssertEqual(weapon.accessibilityLabel, "刘泉纬 · 双锤")
        XCTAssertEqual(stick.accessibilityValue, "居中")
    }

    func testAccessibilityActivationUsesTheSameCancellationContractAsTouch() throws {
        let view = controls()
        let weapon = try XCTUnwrap(view.subviews.first { $0.accessibilityIdentifier == "duel.control.weapon" } as? UIButton)
        var pending = Set<Controls.Action>()
        var completed: [Controls.Action] = []
        var cancelOnDown = false
        view.onAction = { action, down in
            if down {
                pending.insert(action)
                if cancelOnDown { view.inputEnabled = false }
            } else if pending.remove(action) != nil { completed.append(action) }
        }
        view.onActionCancelled = { pending.remove($0) }
        view.onInputCancelled = { pending.removeAll() }
        XCTAssertTrue(weapon.accessibilityActivate())
        XCTAssertEqual(completed, [.weapon])
        cancelOnDown = true
        XCTAssertFalse(weapon.accessibilityActivate())
        XCTAssertEqual(completed, [.weapon], "Disabling input during activation must not synthesize a second tap")
        XCTAssertTrue(pending.isEmpty)
    }

    func testFallbackCannotClaimSourceArtworkAndAccessibilityUsesFourActions() {
        let view = controls()
        XCTAssertFalse(view.sourceArtAvailable)
        XCTAssertTrue(view.loadedSpriteNames.isEmpty)
        let identifiers = Set(view.subviews.compactMap(\.accessibilityIdentifier))
        XCTAssertEqual(identifiers, Set(["duel.control.joystick", "duel.control.weapon", "duel.control.kick",
                                         "duel.control.ranged", "duel.control.shadow"]))
        XCTAssertFalse(view.point(inside: CGPoint(x: 478, y: 220), with: nil),
                       "The middle of the fight must remain available to the scene")
    }

    func testActualSourceSpritesLoadRenderAndRejectDecodableTampering() throws {
        let installed = Controls()
        XCTAssertTrue(installed.sourceArtAvailable, "This selected native suite requires the original private UI pack")
        let required = Set(["fist", "foot", "shadow", "shuriken_button", "stick_arrow", "stick_arrow_small", "stick_circle"])
        XCTAssertEqual(installed.loadedSpriteNames, required)
        installed.frame = CGRect(x: 0, y: 0, width: 956, height: 440)
        installed.setNeedsLayout(); installed.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: installed.bounds.size).image { context in
            UIColor(white: 0.08, alpha: 1).setFill()
            context.cgContext.fill(installed.bounds)
            installed.layer.render(in: context.cgContext)
        }
        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 5000)
        let attachment = XCTAttachment(image: image)
        attachment.name = "source-native-controls-four-actions-eight-directions"
        attachment.lifetime = .keepAlways; add(attachment)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SourceControls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in required {
            let source = try sourceURL(name)
            try Data(contentsOf: source).write(to: directory.appendingPathComponent("\(name).png"))
        }
        XCTAssertTrue(Controls(assetDirectory: directory).sourceArtAvailable)
        let fistURL = directory.appendingPathComponent("fist.png")
        var tampered = try Data(contentsOf: fistURL)
        tampered.append(0) // Same decodable PNG pixels, different unapproved bytes.
        XCTAssertNotNil(UIImage(data: tampered))
        try tampered.write(to: fistURL)
        let rejected = Controls(assetDirectory: directory)
        XCTAssertFalse(rejected.sourceArtAvailable)
        XCTAssertFalse(rejected.loadedSpriteNames.contains("fist"), "A valid bundled copy must not hide a corrupt explicit file")
        XCTAssertEqual(rejected.loadedSpriteNames, required.subtracting(["fist"]))

        // The preferred flattened resource must also be authoritative when an
        // otherwise-valid unprefixed duplicate is present in the same directory.
        try Data(contentsOf: sourceURL("fist")).write(to: fistURL)
        try tampered.write(to: directory.appendingPathComponent("SF3UI_fist.png"))
        let rejectedPreferred = Controls(assetDirectory: directory)
        XCTAssertEqual(rejectedPreferred.loadedSpriteNames, required.subtracting(["fist"]))
    }

    private func sourceURL(_ name: String) throws -> URL {
        let prefixed = "SF3UI_\(name)"
        var candidates: [URL] = []
        if let url = Bundle.main.url(forResource: prefixed, withExtension: "png") { candidates.append(url) }
        if let resource = Bundle.main.resourceURL {
            candidates.append(resource.appendingPathComponent("FighterPrivate/\(prefixed).png"))
            candidates.append(resource.appendingPathComponent("FighterPrivate/Controls/\(prefixed).png"))
            candidates.append(resource.appendingPathComponent("FighterPrivate/Controls/\(name).png"))
        }
        return try XCTUnwrap(candidates.first { FileManager.default.fileExists(atPath: $0.path) }, name)
    }
}
