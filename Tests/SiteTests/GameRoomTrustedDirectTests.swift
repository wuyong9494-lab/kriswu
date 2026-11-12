import XCTest
import Combine
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


extension DuelLifecycleTests {
    @MainActor
    func testRemoteFighterDisconnectClosesDespiteRetainedMemberAndCannotReopen() {
        let room = GameRoom(kind: .fighter, mode: .remote(code: 2123), name: "local", capacity: 2)
        let peer = GameRoom.Member(id: "remote-peer", name: "peer")
        room.testingRemoteMembers([peer], expectedPlayerCount: 0)
        XCTAssertEqual(room.phase, .ready)
        var changed = 0
        room.onMembersChanged = { changed += 1 }
        room.testingRemoteDisconnected(playerID: peer.id)
        guard case .closed = room.phase else { return XCTFail("Disconnect must terminate combat") }
        XCTAssertTrue(room.members.contains(peer), "Do not depend on GKMatch removing its peer immediately")
        room.testingRemoteMembers([peer], expectedPlayerCount: 0)
        room.testingRemoteDisconnected(playerID: peer.id)
        guard case .closed = room.phase else { return XCTFail("Late membership must not resurrect room") }
        XCTAssertEqual(changed, 1)
        room.leave()
    }

    @MainActor
    func testRemoteFighterIgnoresUnknownDisconnectAndRequiresTrustedSendOwner() {
        let room = GameRoom(kind: .fighter, mode: .remote(code: 2123), name: "local", capacity: 2)
        room.testingRemoteMembers([.init(id: "remote-peer", name: "peer")], expectedPlayerCount: 0)
        room.testingRemoteDisconnected(playerID: "stranger")
        room.testingRemoteDisconnected(playerID: room.me.id)
        room.testingRemoteReliableSendFailure()
        XCTAssertEqual(room.phase, .ready)
        let owner = UUID()
        XCTAssertTrue(room.installAuthenticatedDirect(owner: owner, callback: { _, _ in XCTFail("No synthetic packet") }))
        var closures = 0
        room.onMembersChanged = {
            closures += 1
            room.removeAuthenticatedDirect(owner: owner)
            room.testingRemoteReliableSendFailure()
        }
        room.testingRemoteReliableSendFailure()
        guard case .closed = room.phase else { return XCTFail("Reliable send failure must terminate combat") }
        room.testingRemoteReliableSendFailure()
        room.testingRemoteMembers([.init(id: "remote-peer", name: "peer")], expectedPlayerCount: 0)
        XCTAssertEqual(closures, 1)
        XCTAssertFalse(room.ownsAuthenticatedDirect(owner))
        room.leave()
    }

    @MainActor
    func testRemoteFighterFailurePoliciesDoNotChangeLegacyGames() {
        for kind in [GameKind.tiles, .gomoku, .arena] {
            let room = GameRoom(kind: kind, mode: .remote(code: 2123), name: "local", capacity: 2)
            room.testingRemoteMembers([.init(id: "remote-peer", name: "peer")], expectedPlayerCount: 0)
            XCTAssertTrue(room.installAuthenticatedDirect(owner: UUID(), callback: { _, _ in }))
            room.testingRemoteDisconnected(playerID: "remote-peer")
            room.testingRemoteReliableSendFailure()
            XCTAssertEqual(room.phase, .ready)
            room.leave()
        }
    }
}


extension DuelLifecycleTests {
    @MainActor
    func testRemoteFighterTerminalPublicationCannotReenterOrResurrect() {
        for disconnect in [false, true] {
            let room = GameRoom(kind: .fighter, mode: .remote(code: 2123), name: "local", capacity: 2)
            let peers = [GameRoom.Member(id: "remote-peer", name: "peer")]
            room.testingRemoteMembers(peers, expectedPlayerCount: 0)
            XCTAssertTrue(room.installAuthenticatedDirect(owner: UUID(), callback: { _, _ in }))
            var terminalPublications = 0
            let observation = room.$phase.sink { value in
                if case .closed = value {
                    terminalPublications += 1
                    // @Published still exposes old ready here. The private latch
                    // must already prohibit another transition or membership update.
                    room.testingRemoteReliableSendFailure()
                    room.testingRemoteDisconnected(playerID: "remote-peer")
                    room.testingRemoteMembers(peers, expectedPlayerCount: 0)
                }
            }
            if disconnect { room.testingRemoteDisconnected(playerID: "remote-peer") }
            else { room.testingRemoteReliableSendFailure() }
            XCTAssertEqual(terminalPublications, 1)
            guard case .closed = room.phase else { return XCTFail("Terminal phase lost") }
            observation.cancel(); room.leave()
        }
    }

    @MainActor
    func testRemoteFighterLeaveDuringMembershipPublicationCannotBecomeReady() {
        let room = GameRoom(kind: .fighter, mode: .remote(code: 2123), name: "local", capacity: 2)
        let observation = room.$members.dropFirst().sink { _ in room.leave() }
        room.testingRemoteMembers([.init(id: "remote-peer", name: "peer")], expectedPlayerCount: 0)
        XCTAssertNotEqual(room.phase, .ready)
        XCTAssertNil(room.hostID)
        observation.cancel()
    }
}


extension DuelLifecycleTests {
    @MainActor
    func testRemoteFighterLeaveDuringReadyPublicationCannotRemainReady() {
        let room = GameRoom(kind: .fighter, mode: .remote(code: 2123), name: "local", capacity: 2)
        var notifications = 0
        room.onMembersChanged = { notifications += 1 }
        let observation = room.$phase.sink { if $0 == .ready { room.leave() } }
        room.testingRemoteMembers([.init(id: "remote-peer", name: "peer")], expectedPlayerCount: 0)
        guard case .closed = room.phase else { return XCTFail("Synchronous leave must retire ready publication") }
        XCTAssertEqual(notifications, 0)
        observation.cancel()
    }
}
