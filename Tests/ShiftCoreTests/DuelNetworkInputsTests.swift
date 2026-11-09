import Foundation
import XCTest
@testable import ShiftCore

final class DuelNetworkInputsTests: XCTestCase {
    private typealias Inbox = DuelNetworkInputs
    private func inbox() throws -> Inbox { try Inbox(sessionID: "s", hostID: "h", guestID: "g") }
    @discardableResult
    private func send(_ box: inout Inbox, _ message: Inbox.Message, sender: String = "g") -> Inbox.Outcome {
        box.receive(message, authenticatedSenderID: sender, localPlayerID: "h")
    }
    private func take(_ box: inout Inbox) throws -> Inbox.Frame { try box.consume(localPlayerID: "h") }

    func testPinnedAuthorityAndAtomicRejections() throws {
        XCTAssertThrowsError(try Inbox(sessionID: " ", hostID: "h", guestID: "g"))
        XCTAssertThrowsError(try Inbox(sessionID: "s", hostID: "h", guestID: "h"))
        let message = Inbox.Message(sessionID: "s", sequence: 1, tick: 0, move: 1)
        var box = try inbox()
        let original = box
        XCTAssertEqual(box.receive(message, authenticatedSenderID: "g", localPlayerID: "g"), .rejected(.notHost))
        XCTAssertEqual(send(&box, message, sender: "outsider"), .rejected(.unknownPlayer))
        XCTAssertEqual(send(&box, .init(sessionID: "other", sequence: 1, tick: 0)), .rejected(.wrongSession))
        XCTAssertEqual(send(&box, .init(sessionID: "s", sequence: 1, tick: 0, version: 2)), .rejected(.unsupportedVersion))
        XCTAssertEqual(send(&box, .init(sessionID: "s", sequence: 0, tick: 0)), .rejected(.invalidSequence))
        XCTAssertThrowsError(try box.consume(localPlayerID: "g"))
        XCTAssertEqual(box.pause(localPlayerID: "g"), .rejected(.notHost))
        XCTAssertEqual(box.cancel(localPlayerID: "g"), .rejected(.notHost))
        XCTAssertEqual(box.disconnect(playerID: "outsider", localPlayerID: "h"), .rejected(.unknownPlayer))
        XCTAssertEqual(box, original)
        XCTAssertEqual(send(&box, message), .applied)
        XCTAssertEqual(try take(&box).guest.move, 1)
    }

    func testRawDecodeDoesNotClampAndInvalidCombinationsAreAtomic() throws {
        var box = try inbox()
        let invalid: [Inbox.Message] = [
            .init(sessionID: "s", sequence: 1, tick: 0, move: 2),
            .init(sessionID: "s", sequence: 1, tick: 0, vertical: -2),
            .init(sessionID: "s", sequence: 1, tick: 0, tapBits: -1),
            .init(sessionID: "s", sequence: 1, tick: 0, tapBits: 64),
            .init(sessionID: "s", sequence: 1, tick: 0, tapBits: 6),
            .init(sessionID: "s", sequence: 1, tick: 0, tapBits: 1, weaponCommand: .weapon),
            .init(sessionID: "s", sequence: 1, tick: 0, guardHeld: true, tapBits: 2),
            .init(sessionID: "s", sequence: 1, tick: 0, guardHeld: true, weaponCommand: .heavy)
        ]
        let original = box
        for message in invalid {
            let decoded = try JSONDecoder().decode(Inbox.Message.self, from: JSONEncoder().encode(message))
            XCTAssertEqual(decoded, message)
            XCTAssertEqual(send(&box, decoded), .rejected(.invalidInput))
            XCTAssertEqual(box, original)
        }
        XCTAssertEqual(send(&box, .init(sessionID: "s", sequence: 1, tick: 0, tapBits: 3)), .applied)
        XCTAssertEqual(try take(&box).guest.taps.rawValue, 3)
    }

    func testEdgesOnceAndHeldLeaseExpiresWithoutAIFallback() throws {
        var box = try inbox()
        let message = Inbox.Message(sessionID: "s", sequence: 1, tick: 0, move: -1,
                                    vertical: 1, weaponCommand: .weaponUp)
        XCTAssertEqual(send(&box, message), .applied)
        XCTAssertEqual(send(&box, message), .ignoredStaleSequence)
        let first = try take(&box)
        XCTAssertEqual(first.host, .neutral)
        XCTAssertEqual(first.guest.weaponCommand, .weaponUp)
        for _ in 0..<2 {
            let frame = try take(&box)
            XCTAssertEqual(frame.guest, .init(move: -1, vertical: 1))
        }
        XCTAssertEqual(try take(&box).guest, .neutral)
        XCTAssertEqual(send(&box, .init(sessionID: "s", sequence: 2, tick: 4, guardHeld: true)), .applied)
        for _ in 0..<3 { XCTAssertTrue(try take(&box).guest.guardHeld) }
        XCTAssertEqual(try take(&box).guest, .neutral)
        XCTAssertEqual(send(&box, .init(sessionID: "s", sequence: 3, tick: 8, tapBits: 2)), .applied)
        XCTAssertEqual(try take(&box).guest.taps, .light)
        XCTAssertEqual(try take(&box).guest.taps, [])
    }

    func testPeerLeasesAreIndependentAndNeutralReleasesImmediately() throws {
        var box = try inbox()
        send(&box, .init(sessionID: "s", sequence: 1, tick: 0, move: 1), sender: "h")
        send(&box, .init(sessionID: "s", sequence: 1, tick: 0, guardHeld: true))
        _ = try take(&box)
        send(&box, .init(sessionID: "s", sequence: 2, tick: 1), sender: "h")
        let released = try take(&box)
        XCTAssertEqual(released.host, .neutral)
        XCTAssertTrue(released.guest.guardHeld)
        XCTAssertTrue(try take(&box).guest.guardHeld)
        XCTAssertEqual(try take(&box).guest, .neutral)
    }

    func testTickWindowLateSchedulingConflictsAndReorderedSequences() throws {
        var box = try inbox()
        XCTAssertEqual(send(&box, .init(sessionID: "s", sequence: 1, tick: 7)), .rejected(.outsideTickWindow))
        for tick in UInt64(0)...6 {
            XCTAssertEqual(send(&box, .init(sessionID: "s", sequence: tick + 1, tick: tick, tapBits: 2)), .applied)
        }
        let full = box
        XCTAssertEqual(send(&box, .init(sessionID: "s", sequence: 8, tick: 6)), .rejected(.conflictingTick))
        XCTAssertEqual(send(&box, .init(sessionID: "s", sequence: 6, tick: 5)), .ignoredStaleSequence)
        XCTAssertEqual(box, full)
        for tick in UInt64(0)...6 {
            let frame = try take(&box)
            XCTAssertEqual(frame.tick, tick)
            XCTAssertEqual(frame.guest.taps, .light)
        }
        XCTAssertEqual(send(&box, .init(sessionID: "s", sequence: 8, tick: 4)), .rejected(.outsideTickWindow))
        XCTAssertEqual(send(&box, .init(sessionID: "s", sequence: 8, tick: 5, tapBits: 4)), .applied)
        XCTAssertEqual(try take(&box).guest.taps, .heavy)
        XCTAssertEqual(try take(&box).guest.taps, [])
        // A newer packet with an earlier target cannot reorder a queued timeline.
        XCTAssertEqual(send(&box, .init(sessionID: "s", sequence: 10, tick: 11)), .applied)
        XCTAssertEqual(send(&box, .init(sessionID: "s", sequence: 9, tick: 10)), .ignoredStaleSequence)
        XCTAssertEqual(send(&box, .init(sessionID: "s", sequence: 11, tick: 10)), .rejected(.conflictingTick))
    }

    func testPauseEpochClearsHeldQueuedAndUnseenInFlightInputs() throws {
        var box = try inbox()
        send(&box, .init(sessionID: "s", sequence: 1, tick: 0, move: 1))
        _ = try take(&box)
        send(&box, .init(sessionID: "s", sequence: 2, tick: 2, tapBits: 32))
        XCTAssertEqual(box.pause(localPlayerID: "h"), .applied)
        XCTAssertEqual(box.epoch, 1)
        XCTAssertThrowsError(try take(&box))
        XCTAssertEqual(send(&box, .init(sessionID: "s", epoch: 1, sequence: 3, tick: 1)), .rejected(.inactive))
        XCTAssertEqual(box.resume(localPlayerID: "h"), .applied)
        XCTAssertEqual(send(&box, .init(sessionID: "s", sequence: 99, tick: 1, tapBits: 2)), .rejected(.wrongEpoch))
        XCTAssertEqual(send(&box, .init(sessionID: "s", epoch: 1, sequence: 2, tick: 1)), .ignoredStaleSequence)
        XCTAssertEqual(try take(&box).guest, .neutral)
        XCTAssertEqual(try take(&box).guest, .neutral)
        XCTAssertEqual(send(&box, .init(sessionID: "s", epoch: 1, sequence: 3, tick: 3, move: -1)), .applied)
        XCTAssertEqual(try take(&box).guest.move, -1)
    }

    func testCancelAndEitherDisconnectAreTerminal() throws {
        for player in ["h", "g"] {
            var box = try inbox()
            send(&box, .init(sessionID: "s", sequence: 1, tick: 0, tapBits: 2))
            XCTAssertEqual(box.disconnect(playerID: player, localPlayerID: "h"), .applied)
            XCTAssertEqual(box.phase, .closed)
            XCTAssertThrowsError(try take(&box))
            XCTAssertEqual(box.resume(localPlayerID: "h"), .rejected(.inactive))
            XCTAssertEqual(send(&box, .init(sessionID: "s", sequence: 2, tick: 0)), .rejected(.inactive))
        }
        var box = try inbox()
        XCTAssertEqual(box.cancel(localPlayerID: "h"), .applied)
        XCTAssertThrowsError(try take(&box))
    }

    func testExplicitTwoPlayerReplayMatchesDirectSimulation() throws {
        var box = try inbox()
        var replay = DuelGame(seed: 42), direct = DuelGame(seed: 42)
        for tick in UInt64(0)..<180 {
            let host = DuelGame.Input(move: tick < 25 ? 1 : 0, taps: tick % 30 == 0 ? .light : [])
            let guest = DuelGame.Input(move: tick < 25 ? -1 : 0, taps: tick % 45 == 0 ? .heavy : [])
            for (id, input) in [("h", host), ("g", guest)] {
                XCTAssertEqual(send(&box, .init(sessionID: "s", sequence: tick + 1, tick: tick,
                                               move: input.move, tapBits: input.taps.rawValue), sender: id), .applied)
            }
            let frame = try take(&box)
            replay.step(frame.host, opponent: frame.guest)
            direct.step(host, opponent: guest)
            XCTAssertEqual(replay, direct, "Diverged at input tick \(tick)")
        }
    }
}
