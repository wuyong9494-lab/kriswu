import Foundation
import XCTest
@testable import ShiftCore

final class DuelNetworkCombatWireTests: XCTestCase {
    func testGuestInputWireRoundTripAndNamespace() {
        var guest = DuelNetworkCombatGuest(sessionID: "session", hostID: "host", guestID: "guest")
        let data = guest.input(tick: 0, move: 1, tapBits: DuelGame.Buttons.light.rawValue)
        XCTAssertNotNil(data)
        guard let data, let body = DuelNetworkCombatWire.decode(data) else {
            return XCTFail("Expected valid guest input envelope")
        }
        guard case .input(let input) = body else { return XCTFail("Expected input") }
        XCTAssertEqual(input.sessionID, "session")
        XCTAssertEqual(input.sequence, 1)
        XCTAssertEqual(input.tick, 0)
        XCTAssertEqual(input.move, 1)
        XCTAssertNil(DuelNetworkCombatWire.decode(Data("invalid".utf8)))
        XCTAssertNil(DuelNetworkCombatWire.decode(Data(repeating: 0, count: DuelNetworkCombatWire.maximumBytes + 1)))
    }

    func testGuestCannotAcceptUntrustedHostState() {
        var guest = DuelNetworkCombatGuest(sessionID: "session", hostID: "host", guestID: "guest")
        let input = guest.input(tick: 0)!
        XCTAssertEqual(guest.receive(input, authenticatedSenderID: "host"), .rejected)
        XCTAssertNil(guest.replica.latest)
    }

    func testHostRejectsPeerStateAndUnknownSession() {
        let input = DuelNetworkInputs.Message(sessionID: "wrong", sequence: 1, tick: 0, move: 1)
        guard let data = DuelNetworkCombatWire.encode(.input(input)) else {
            return XCTFail("Expected encoded message")
        }
        guard case .input(let decoded)? = DuelNetworkCombatWire.decode(data) else {
            return XCTFail("Expected decoded input")
        }
        XCTAssertEqual(decoded.sessionID, "wrong")
    }
}
