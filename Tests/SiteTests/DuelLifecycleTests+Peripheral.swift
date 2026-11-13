import XCTest
import GameController
@testable import ShiftReminder

@MainActor
extension DuelLifecycleTests {
    func testPeripheralNeutralResetDoesNotSwallowFirstNewPress() throws {
        let pad = GCController.withExtendedGamepad()
        let adapter = DuelPeripheralInput(controllers: { [pad] }, keyboard: { nil }, applicationIsActive: { true })
        var states: [DuelPhysicalInput.State] = []
        adapter.canAccept = { true }
        adapter.onState = { _, state, cancelled in if !cancelled { states.append(state) } }
        adapter.start()
        defer { adapter.stop() }
        adapter.reset()
        try XCTUnwrap(pad.extendedGamepad).buttonX.setValue(1)
        adapter.refreshReadiness()
        XCTAssertTrue(states.last?.actions.contains(.weapon) == true)
    }

    func testPeripheralHeldAcrossResetRequiresNeutralBeforeRearming() throws {
        let pad = GCController.withExtendedGamepad()
        let p = try XCTUnwrap(pad.extendedGamepad)
        let adapter = DuelPeripheralInput(controllers: { [pad] }, keyboard: { nil }, applicationIsActive: { true })
        var states: [DuelPhysicalInput.State] = []
        adapter.canAccept = { true }
        adapter.onState = { _, state, cancelled in if !cancelled { states.append(state) } }
        adapter.start()
        defer { adapter.stop() }
        p.buttonX.setValue(1); adapter.refreshReadiness()
        adapter.reset(); states.removeAll()
        adapter.refreshReadiness()
        XCTAssertTrue(states.isEmpty)
        p.buttonX.setValue(0); adapter.refreshReadiness()
        p.buttonX.setValue(1); adapter.refreshReadiness()
        XCTAssertTrue(states.last?.actions.contains(.weapon) == true)
    }

    func testPeripheralOldViewCannotEraseNewControllerHandler() throws {
        let pad = GCController.withExtendedGamepad()
        let old = DuelPeripheralInput(controllers: { [pad] }, keyboard: { nil }, applicationIsActive: { true })
        let new = DuelPeripheralInput(controllers: { [pad] }, keyboard: { nil }, applicationIsActive: { true })
        var oldCancellations = 0
        old.onState = { _, _, cancelled in if cancelled { oldCancellations += 1 } }
        old.canAccept = { true }; new.canAccept = { true }
        old.start(); new.start()
        defer { old.stop(); new.stop() }
        oldCancellations = 0
        old.stop()
        XCTAssertEqual(oldCancellations, 0)
        XCTAssertNotNil(try XCTUnwrap(pad.extendedGamepad).valueChangedHandler)
    }

    func testPeripheralDisconnectPublishesCancellationNotRelease() throws {
        let pad = GCController.withExtendedGamepad()
        var connected = [pad]
        let adapter = DuelPeripheralInput(controllers: { connected }, keyboard: { nil }, applicationIsActive: { true })
        var cancellations = 0
        adapter.canAccept = { true }
        adapter.onState = { source, state, cancelled in
            if source.hasPrefix("pad:") && cancelled && state == .neutral { cancellations += 1 }
        }
        adapter.start()
        cancellations = 0
        defer { adapter.stop() }
        try XCTUnwrap(pad.extendedGamepad).buttonX.setValue(1); adapter.refreshReadiness()
        connected.removeAll(); adapter.refreshDevices()
        XCTAssertEqual(cancellations, 1)
    }
}
