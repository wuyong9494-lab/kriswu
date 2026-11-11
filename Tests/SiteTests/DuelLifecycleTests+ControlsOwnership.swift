import XCTest
import UIKit
@testable import ShiftReminder

@MainActor
extension DuelLifecycleTests {
    private func ownershipControls() -> DuelSourceControlsView {
        let view = DuelSourceControlsView(images: [:])
        view.frame = CGRect(x: 0, y: 0, width: 956, height: 440)
        view.setNeedsLayout(); view.layoutIfNeeded()
        return view
    }

    func testOfflineControlReplacementRetiresOldViewAndPreservesCurrentReset() throws {
        let state = DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
        let binding = DuelWeaponControls(session: state)
        let old = ownershipControls(), current = ownershipControls()
        defer { old.shutdown(); current.shutdown(); state.shutdown() }
        XCTAssertTrue(binding.bind(old))
        XCTAssertTrue(binding.bind(current))
        XCTAssertTrue(old.isShutdown)
        XCTAssertFalse(old.inputEnabled)
        XCTAssertNil(old.onDirection); XCTAssertNil(old.onAction)
        XCTAssertNil(old.onActionCancelled); XCTAssertNil(old.onInputCancelled)
        XCTAssertTrue(state.acceptsWeaponControls(current))

        let layout = current.layoutSnapshot
        let point = CGPoint(x: layout.joystick.midX + 180 * layout.scale, y: layout.joystick.midY)
        current.beginPointers([.init(id: "current", location: point)])
        let stick = try XCTUnwrap(current.subviews.first { $0.accessibilityIdentifier == "duel.control.joystick" })
        XCTAssertEqual(stick.accessibilityValue, "右")
        old.didMoveToWindow()
        DuelWeaponControls.dismantleUIView(old, coordinator: ())
        binding.updateReadiness(old)
        XCTAssertFalse(old.inputEnabled, "A late readiness update must not revive a retired control")
        XCTAssertNotNil(state.inputReset)
        XCTAssertEqual(stick.accessibilityValue, "右", "Late old-view teardown must preserve current contacts")
        state.clearInput()
        XCTAssertEqual(stick.accessibilityValue, "居中", "The current owner must retain the session reset hook")
        current.shutdown()
        XCTAssertNil(state.inputReset)
    }

    func testOfflineControlBindCannotOverwriteAReentrantReplacement() {
        let state = DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
        let binding = DuelWeaponControls(session: state)
        let old = ownershipControls(), superseded = ownershipControls(), newest = ownershipControls()
        defer { old.shutdown(); superseded.shutdown(); newest.shutdown(); state.shutdown() }
        XCTAssertTrue(binding.bind(old))
        state.inputReset = {
            state.inputReset = nil
            XCTAssertTrue(binding.bind(newest))
        }
        XCTAssertFalse(binding.bind(superseded))
        XCTAssertTrue(old.isShutdown)
        XCTAssertTrue(superseded.isShutdown)
        XCTAssertFalse(newest.isShutdown)
        XCTAssertTrue(state.acceptsWeaponControls(newest))
        XCTAssertNotNil(state.inputReset)
        superseded.shutdown()
        XCTAssertTrue(state.acceptsWeaponControls(newest))
        XCTAssertNotNil(state.inputReset)
    }

    func testShutdownDuringControlClaimRejectsLateBindingAndInputHooks() {
        let state = DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
        let binding = DuelWeaponControls(session: state)
        let pending = ownershipControls(), late = ownershipControls()
        state.inputReset = { state.shutdown() }
        XCTAssertFalse(binding.bind(pending))
        XCTAssertTrue(pending.isShutdown)
        XCTAssertTrue(state.paused)
        XCTAssertNil(state.inputReset)
        XCTAssertFalse(binding.bind(late))
        XCTAssertTrue(late.isShutdown)
        XCTAssertNil(late.onDirection); XCTAssertNil(late.onAction)
        XCTAssertNil(state.inputReset)
    }

    func testOldControlShutdownCannotLetStaleClaimClearNewerInput() {
        let state = DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
        let binding = DuelWeaponControls(session: state)
        let old = ownershipControls(), superseded = ownershipControls(), newest = ownershipControls()
        defer { old.shutdown(); superseded.shutdown(); newest.shutdown(); state.shutdown() }
        XCTAssertTrue(binding.bind(old))
        let released = old.onShutdown
        old.onShutdown = {
            released?()
            XCTAssertTrue(binding.bind(newest))
            state.input("right", down: true)
        }
        XCTAssertFalse(binding.bind(superseded))
        XCTAssertTrue(state.acceptsWeaponControls(newest))
        XCTAssertTrue(state.held.contains("right"), "A superseded claim must not clear the newer owner's mailbox")
        XCTAssertNotNil(state.inputReset)
    }

    func testCurrentControlDismantleClearsInputAndCannotBeRebound() {
        let state = DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
        let binding = DuelWeaponControls(session: state)
        let controls = ownershipControls()
        defer { state.shutdown() }
        XCTAssertTrue(binding.bind(controls))
        state.input("right", down: true)
        DuelWeaponControls.dismantleUIView(controls, coordinator: ())
        XCTAssertTrue(state.held.isEmpty)
        XCTAssertNil(state.inputReset)
        XCTAssertFalse(binding.bind(controls))
        controls.inputEnabled = true
        XCTAssertFalse(controls.point(inside: controls.layoutSnapshot.joystick.origin, with: nil))
        XCTAssertFalse(state.acceptsWeaponControls(controls))
    }
}
