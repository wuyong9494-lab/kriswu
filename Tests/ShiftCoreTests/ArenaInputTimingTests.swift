import XCTest
@testable import ShiftCore

final class ArenaInputTimingTests: XCTestCase {
    func testNominalCadenceDoesNotDependOnRenderRefreshRate() {
        for hz in [30, 60, 120] {
            var cadence = ArenaInputCadence()
            let sends = (0..<(hz * 10)).filter {
                cadence.takeSend(at: Double($0) / Double(hz))
            }
            XCTAssertEqual(sends.count, 300, "\(hz)Hz callbacks must send 30Hz movement")
        }
    }

    func testStallDoesNotBurstAndCancellationIsImmediate() {
        var cadence = ArenaInputCadence()
        XCTAssertTrue(cadence.takeSend(at: 0))
        XCTAssertFalse(cadence.takeSend(at: 0.01))
        XCTAssertTrue(cadence.takeSend(at: 0.01, force: true))
        XCTAssertFalse(cadence.takeSend(at: 0.02))
        XCTAssertTrue(cadence.takeSend(at: 5))
        for _ in 0..<100 { XCTAssertFalse(cadence.takeSend(at: 5)) }
        XCTAssertFalse(cadence.takeSend(at: .nan))
        XCTAssertFalse(cadence.takeSend(at: .infinity))
        XCTAssertFalse(cadence.takeSend(at: 4))
        XCTAssertTrue(cadence.takeSend(at: 5 + 1.0 / 30))
    }

    func testReceivedAckWaitsForSimulationAndLatestInputWins() {
        var remote = ArenaRemoteMovement()
        XCTAssertTrue(remote.receive(sequence: 1, move: V2(1, 0), at: 10))
        XCTAssertEqual(remote.appliedSequence, 0)
        XCTAssertTrue(remote.receive(sequence: 3, move: V2(0, 1), at: 10.02))
        XCTAssertFalse(remote.receive(sequence: 2, move: V2(-1, 0), at: 10.03))
        XCTAssertEqual(remote.consume(at: 10.04), V2(0, 1))
        XCTAssertEqual(remote.appliedSequence, 3)
    }

    func testPacketSilenceStopsMovementWithoutDisconnectAndFreshInputResumes() {
        var remote = ArenaRemoteMovement()
        remote.receive(sequence: 1, move: V2(1, 0), at: 1)
        XCTAssertEqual(remote.consume(at: 1.2), V2(1, 0))
        XCTAssertEqual(remote.consume(at: 1.251), .zero)
        // A late duplicate must not refresh the lease and restart stale movement.
        XCTAssertFalse(remote.receive(sequence: 1, move: V2(1, 0), at: 1.3))
        XCTAssertEqual(remote.consume(at: 1.3), .zero)
        remote.receive(sequence: 2, move: V2(-1, 0), at: 1.4)
        XCTAssertEqual(remote.consume(at: 1.41), V2(-1, 0))
        remote.receive(sequence: 4, move: .zero, at: 1.42)
        XCTAssertFalse(remote.receive(sequence: 3, move: V2(-1, 0), at: 1.43))
        XCTAssertEqual(remote.consume(at: 1.44), .zero)
    }

    func testMalformedMovementDoesNotPoisonLatestState() {
        var remote = ArenaRemoteMovement()
        XCTAssertFalse(remote.receive(sequence: 1, move: V2(.nan, 0), at: 0))
        XCTAssertFalse(remote.receive(sequence: 1, move: V2(1, 0), at: .infinity))
        XCTAssertTrue(remote.receive(sequence: 1, move: V2(10, 0), at: 0))
        XCTAssertEqual(remote.consume(at: 0), V2(1, 0))
    }
}
