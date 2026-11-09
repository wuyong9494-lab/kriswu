import XCTest
@testable import ShiftReminder

// Keep these in the existing native lifecycle suite selected by fighter CI.
extension DuelLifecycleTests {
    func testPeerIdentityIsPinnedUntilDisconnect() {
        var bindings = GameRoomDirectIdentity<String>()
        bindings.bind("peer-one", to: "guest", localID: "host")
        bindings.bind("peer-one", to: "guest", localID: "host")
        XCTAssertEqual(bindings.identity(for: "peer-one"), "guest")
        bindings.bind("peer-one", to: "replacement", localID: "host")
        XCTAssertNil(bindings.identity(for: "peer-one"))
        bindings.bind("peer-one", to: "guest", localID: "host")
        XCTAssertNil(bindings.identity(for: "peer-one"), "Rebinding quarantines the peer until disconnect")
        bindings.remove("peer-one")
        bindings.bind("peer-one", to: "replacement", localID: "host")
        XCTAssertEqual(bindings.identity(for: "peer-one"), "replacement")
    }

    func testQuarantineReservesOriginalIdentityUntilDisconnect() {
        var bindings = GameRoomDirectIdentity<String>()
        bindings.bind("peer-one", to: "guest", localID: "host")
        bindings.bind("peer-one", to: "changed", localID: "host")
        bindings.bind("peer-two", to: "guest", localID: "host")
        XCTAssertNil(bindings.identity(for: "peer-one"))
        XCTAssertNil(bindings.identity(for: "peer-two"))
        bindings.remove("peer-one")
        bindings.remove("peer-two")
        bindings.bind("peer-two", to: "guest", localID: "host")
        XCTAssertEqual(bindings.identity(for: "peer-two"), "guest")
    }

    func testDuplicateOrLocalIdentityCannotBecomeTrusted() {
        var bindings = GameRoomDirectIdentity<String>()
        bindings.bind("peer-one", to: "guest", localID: "host")
        bindings.bind("peer-two", to: "guest", localID: "host")
        XCTAssertNil(bindings.identity(for: "peer-two"))
        XCTAssertEqual(bindings.identity(for: "peer-one"), "guest")
        bindings.bind("peer-three", to: "host", localID: "host")
        XCTAssertNil(bindings.identity(for: "peer-three"))
        bindings.removeAll()
        XCTAssertNil(bindings.identity(for: "peer-one"))
    }

    @MainActor
    func testLeavingClearsTrustedCallbackWithoutStartingTransport() {
        let room = GameRoom(kind: .arena, mode: .nearbyHost, name: "test", capacity: 2)
        room.onAuthenticatedDirect = { _, _ in XCTFail("No callback after leaving") }
        room.leave()
        XCTAssertNil(room.onAuthenticatedDirect)
    }

    func testDirectIdentityMustMatchTheCurrentTransportMember() {
        XCTAssertEqual(GameRoom.validatedDirectSender(claimed: "guest", transport: "guest",
            local: "host", memberIDs: ["host", "guest"]), "guest")
        XCTAssertEqual(GameRoom.validatedDirectSender(claimed: "host", transport: "host",
            local: "guest", memberIDs: ["host", "guest"]), "host")
    }

    func testForgedMissingLocalAndDuplicateIdentitiesAreRejected() {
        for (claimed, transport, members) in [
            ("host", Optional("guest"), ["host", "guest"]),
            ("guest", nil, ["host", "guest"]),
            ("host", Optional("host"), ["host", "guest"]),
            ("departed", Optional("departed"), ["host", "guest"]),
            ("guest", Optional("guest"), ["host", "guest", "guest"]),
            ("", Optional(""), ["host", ""])
        ] {
            XCTAssertNil(GameRoom.validatedDirectSender(claimed: claimed, transport: transport,
                local: "host", memberIDs: members))
        }
    }
}
