import XCTest
@testable import ShiftReminder

@MainActor
final class DuelLocalMatchPreparationTests: XCTestCase {
    private actor Deferred {
        private var released = false
        private var pending: CheckedContinuation<Void, Never>?

        func wait() async {
            if !released { await withCheckedContinuation { pending = $0 } }
        }

        func release() {
            released = true
            pending?.resume()
            pending = nil
        }
    }

    func testLatePreparationsCannotMountAfterBackgroundingOrExit() async throws {
        let gate = DuelLocalMatchPreparationGate()
        var mounted: [Int] = []
        let first = try XCTUnwrap(gate.begin(active: true))
        let firstLoad = Deferred()
        let late = Task {
            await firstLoad.wait()
            gate.finish(first, active: true) { mounted.append(1) }
        }
        gate.suspend()
        XCTAssertNil(gate.begin(active: false))
        let foreground = try XCTUnwrap(gate.begin(active: true))
        await firstLoad.release()
        await late.value
        XCTAssertTrue(mounted.isEmpty)
        gate.finish(foreground, active: true) { mounted.append(2) }

        let last = try XCTUnwrap(gate.begin(active: true))
        let lastLoad = Deferred()
        let afterExit = Task {
            await lastLoad.wait()
            gate.finish(last, active: true) { mounted.append(3) }
        }
        gate.leave()
        await lastLoad.release()
        await afterExit.value
        XCTAssertNil(gate.begin(active: true))
        XCTAssertEqual(mounted, [2])
    }
}
