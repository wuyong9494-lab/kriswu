import Foundation
import XCTest
@testable import ShiftCore

/// Deterministic core lifecycle regression. UI/SceneKit teardown and real
/// GameRoom callbacks still require simulator/device instrumentation.
final class DuelNetworkReentryTests: XCTestCase {
    func testTwentyFreshRoomsNeverAcceptPreviousSessionInputs() throws {
        for iteration in 0..<20 {
            let id = "fight-\(iteration)"
            var inbox = try DuelNetworkInputs(sessionID: id, hostID: "host", guestID: "guest")
            let first = DuelNetworkInputs.Message(sessionID: id, sequence: 1,
                tick: 0, tapBits: DuelGame.Buttons.light.rawValue)
            XCTAssertEqual(inbox.receive(first, authenticatedSenderID: "guest",
                                         localPlayerID: "host"), .applied)
            XCTAssertEqual(try inbox.consume(localPlayerID: "host").guest.taps, .light)
            XCTAssertEqual(inbox.cancel(localPlayerID: "host"), .applied)
            XCTAssertEqual(inbox.phase, .closed)
            XCTAssertThrowsError(try inbox.consume(localPlayerID: "host"))
            XCTAssertEqual(inbox.receive(.init(sessionID: id, sequence: 2, tick: 1),
                                         authenticatedSenderID: "guest", localPlayerID: "host"),
                           .rejected(.inactive))

            let nextID = "fight-\(iteration + 1)"
            var fresh = try DuelNetworkInputs(sessionID: nextID, hostID: "host", guestID: "guest")
            XCTAssertEqual(fresh.receive(first, authenticatedSenderID: "guest",
                                         localPlayerID: "host"), .rejected(.wrongSession))
            XCTAssertEqual(fresh.nextTick, 0)
            XCTAssertEqual(fresh.phase, .active)
            XCTAssertEqual(try fresh.consume(localPlayerID: "host").guest, .neutral)
        }
    }

    func testDisconnectedGuestCannotAdvanceOldCombat() throws {
        var inbox = try DuelNetworkInputs(sessionID: "room", hostID: "host", guestID: "guest")
        XCTAssertEqual(inbox.receive(.init(sessionID: "room", sequence: 1, tick: 0, move: 1),
                                     authenticatedSenderID: "guest", localPlayerID: "host"), .applied)
        XCTAssertEqual(inbox.disconnect(playerID: "guest", localPlayerID: "host"), .applied)
        XCTAssertEqual(inbox.phase, .closed)
        XCTAssertThrowsError(try inbox.consume(localPlayerID: "host"))
        XCTAssertEqual(inbox.receive(.init(sessionID: "room", sequence: 2, tick: 1),
                                     authenticatedSenderID: "guest", localPlayerID: "host"),
                       .rejected(.inactive))
    }
}
