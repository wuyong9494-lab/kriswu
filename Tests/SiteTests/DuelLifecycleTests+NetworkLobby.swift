import XCTest
@testable import ShiftReminder

@MainActor
private final class OfflineDuelTransport: DuelLobbyTransport {
    var state: DuelLobbyRoomState
    var owner: UUID?
    var receive: ((Data, String) -> Void)?
    var changed: (() -> Void)?
    var packets: [Data] = []
    weak var peer: OfflineDuelTransport?
    init(local: String, members: [String] = ["host", "guest"]) {
        state = .init(isFighter: true, capacity: 2, ready: true,
                      localID: local, hostID: "host", members: members)
    }
    func claim(_ owner: UUID, receive: @escaping (Data, String) -> Void,
               changed: @escaping () -> Void) -> Bool {
        guard self.owner == nil else { return false }
        self.owner = owner; self.receive = receive; self.changed = changed
        return true
    }
    func release(_ owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil; receive = nil; changed = nil
    }
    func sendReliable(_ data: Data) {
        packets.append(data)
        peer?.receive?(data, state.localID)
    }
}

extension DuelLifecycleTests {
    func testFighterMatchmakingGroupsStayDistinctAndStable() {
        XCTAssertEqual(GameKind.tiles.index, 1)
        XCTAssertEqual(GameKind.gomoku.index, 2)
        XCTAssertEqual(GameKind.arena.index, 3)
        XCTAssertEqual(GameKind.fighter.index, 4)
        XCTAssertEqual(GameKind.fighter.rawValue, "fighter")
    }

    func testNetworkLobbyOfflineHandshakeReadinessAndHostStart() throws {
        let h = OfflineDuelTransport(local: "host"), g = OfflineDuelTransport(local: "guest")
        h.peer = g; g.peer = h
        let host = DuelNetworkLobby(transport: h), guest = DuelNetworkLobby(transport: g)
        defer { host.shutdown(); guest.shutdown() }
        XCTAssertTrue(h.packets.isEmpty && g.packets.isEmpty)
        XCTAssertNil(h.receive); XCTAssertNil(g.receive)
        try host.attach(); try guest.attach()
        XCTAssertEqual(host.snapshot, guest.snapshot)
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(host.snapshot?.sessionID)))
        XCTAssertTrue(host.submit(.select(.sun)))
        XCTAssertTrue(guest.submit(.select(.liu)))
        let revision = try XCTUnwrap(host.snapshot?.selectionRevision)
        XCTAssertTrue(host.submit(.ready(true, selectionRevision: revision)))
        XCTAssertTrue(guest.submit(.ready(true, selectionRevision: revision)))
        XCTAssertEqual(guest.snapshot?.canStart, true)
        XCTAssertTrue(guest.submit(.select(.sun)))
        XCTAssertEqual(host.snapshot?.players.map(\.isReady), [false, false])
        XCTAssertFalse(host.submit(.start(selectionRevision: revision)))
        let conflict = try XCTUnwrap(host.snapshot?.selectionRevision)
        XCTAssertFalse(host.submit(.ready(true, selectionRevision: conflict)))
        XCTAssertTrue(guest.submit(.ready(true, selectionRevision: conflict)),
                      "Guest submission queues intent; it is not host acceptance")
        XCTAssertEqual(host.snapshot?.players.map(\.isReady), [false, false])
        XCTAssertEqual(guest.snapshot?.canStart, false)
        XCTAssertTrue(guest.submit(.select(.liu)))
        let current = try XCTUnwrap(host.snapshot?.selectionRevision)
        XCTAssertTrue(host.submit(.ready(true, selectionRevision: current)))
        XCTAssertTrue(guest.submit(.ready(true, selectionRevision: current)))
        XCTAssertFalse(guest.submit(.start(selectionRevision: current)))
        XCTAssertTrue(host.submit(.start(selectionRevision: current)))
        XCTAssertEqual(host.status, .started)
        XCTAssertEqual(host.snapshot, guest.snapshot)
    }

    func testNetworkLobbyGuestFirstHandshakeAndHostReattachment() throws {
        let h = OfflineDuelTransport(local: "host"), g = OfflineDuelTransport(local: "guest")
        h.peer = g; g.peer = h
        let host = DuelNetworkLobby(transport: h), guest = DuelNetworkLobby(transport: g)
        defer { host.shutdown(); guest.shutdown() }
        try guest.attach()
        XCTAssertEqual(guest.status, .connecting)
        XCTAssertEqual(g.packets.count, 1)
        let firstRequest = try XCTUnwrap(g.packets.first)
        let announcement = try JSONEncoder().encode(DuelNetworkLobby.Envelope(.available(sessionID: UUID().uuidString)))
        g.receive?(announcement, "stranger")
        XCTAssertEqual(g.packets.count, 1, "Untrusted announcements must not provoke replies")
        let malformed = try JSONEncoder().encode(DuelNetworkLobby.Envelope(.available(sessionID: "invalid")))
        g.receive?(malformed, "host")
        XCTAssertEqual(g.packets.count, 1)
        try host.attach()
        XCTAssertEqual(guest.status, .selecting)
        XCTAssertEqual(host.snapshot, guest.snapshot)
        let original = try JSONDecoder().decode(DuelNetworkLobby.Envelope.self, from: firstRequest)
        let retried = try JSONDecoder().decode(DuelNetworkLobby.Envelope.self, from: XCTUnwrap(g.packets.last))
        guard case .request(let firstNonce) = original.body,
              case .request(let retryNonce) = retried.body else { return XCTFail("Expected nonce requests") }
        XCTAssertEqual(firstNonce, retryNonce)
        let oldSession = guest.snapshot?.sessionID
        host.shutdown(); try host.attach()
        XCTAssertNotEqual(host.snapshot?.sessionID, oldSession)
        XCTAssertEqual(guest.status, .closed)
        XCTAssertNil(guest.snapshot)
        XCTAssertNil(g.receive)
        try guest.attach()
        XCTAssertEqual(host.snapshot, guest.snapshot)
    }

    func testNetworkLobbyGuestReattachmentResetsSessionCountersAndTerminalStart() throws {
        let h = OfflineDuelTransport(local: "host"), g = OfflineDuelTransport(local: "guest")
        h.peer = g; g.peer = h
        let host = DuelNetworkLobby(transport: h), guest = DuelNetworkLobby(transport: g)
        defer { host.shutdown(); guest.shutdown() }
        try host.attach(); try guest.attach()
        let retiredRequest = try XCTUnwrap(g.packets.first)
        XCTAssertTrue(host.submit(.select(.sun)))
        for _ in 0..<5 { XCTAssertTrue(guest.submit(.select(.liu))) }
        let previousSession = host.snapshot?.sessionID
        guest.shutdown(); try guest.attach()
        XCTAssertEqual(host.snapshot, guest.snapshot)
        XCTAssertNotEqual(host.snapshot?.sessionID, previousSession)
        XCTAssertEqual(host.snapshot?.players.map(\.lastSequence), [0, 0])
        XCTAssertEqual(host.snapshot?.players.map(\.isReady), [false, false])
        XCTAssertTrue(guest.submit(.select(.liu)))
        XCTAssertEqual(host.snapshot?.players[1].lastSequence, 1)
        let currentRequest = try XCTUnwrap(g.packets.first(where: { data in
            guard let envelope = try? JSONDecoder().decode(DuelNetworkLobby.Envelope.self, from: data),
                  case .request = envelope.body else { return false }
            return data != retiredRequest
        }))
        let beforeRetry = host.snapshot
        h.receive?(currentRequest, "guest")
        XCTAssertEqual(host.snapshot, beforeRetry, "Same nonce retry must not create another session")
        h.receive?(retiredRequest, "guest")
        XCTAssertEqual(host.snapshot, beforeRetry, "Retired nonce must not reset the current session")
        XCTAssertTrue(host.submit(.select(.sun)))
        let revision = try XCTUnwrap(host.snapshot?.selectionRevision)
        XCTAssertTrue(host.submit(.ready(true, selectionRevision: revision)))
        XCTAssertTrue(guest.submit(.ready(true, selectionRevision: revision)))
        XCTAssertTrue(host.submit(.start(selectionRevision: revision)))
        let startedSession = host.snapshot?.sessionID
        XCTAssertEqual(guest.status, .started)
        guest.shutdown(); try guest.attach()
        XCTAssertEqual(host.status, .selecting)
        XCTAssertEqual(guest.status, .selecting)
        XCTAssertNotEqual(host.snapshot?.sessionID, startedSession)
        XCTAssertEqual(host.snapshot, guest.snapshot)
        XCTAssertEqual(host.snapshot?.players.map(\.lastSequence), [0, 0])
        XCTAssertTrue(guest.submit(.select(.sun)))
        XCTAssertEqual(host.snapshot?.players[1].lastSequence, 1)
    }

    func testNetworkLobbyReentrantCallbackReplacementCannotBeErasedByOldOwner() {
        let room = GameRoom(kind: .fighter, mode: .nearbyHost, name: "offline", capacity: 2)
        let bridge = DuelGameRoomTransport(room: room)
        let owner = UUID()
        var replacementCalls = 0
        XCTAssertTrue(bridge.claim(owner, receive: { _, _ in
            room.onAuthenticatedDirect = { _, _ in replacementCalls += 1 }
            // The old callback is still on the stack at this point.
            bridge.release(owner)
        }, changed: {}))
        room.onAuthenticatedDirect?(Data(), "guest")
        XCTAssertFalse(room.ownsAuthenticatedDirect(owner))
        room.onAuthenticatedDirect?(Data(), "guest")
        XCTAssertEqual(replacementCalls, 1)
        room.onAuthenticatedDirect = nil
    }

    func testNetworkLobbyRejectedAndStaleCommandsResendAuthoritativeSnapshot() throws {
        let h = OfflineDuelTransport(local: "host"), g = OfflineDuelTransport(local: "guest")
        h.peer = g; g.peer = h
        let host = DuelNetworkLobby(transport: h), guest = DuelNetworkLobby(transport: g)
        defer { host.shutdown(); guest.shutdown() }
        try host.attach(); try guest.attach()
        h.peer = nil // Deliberately omit a snapshot, entirely in memory.
        XCTAssertTrue(host.submit(.select(.sun)))
        XCTAssertNil(guest.snapshot?.players.first?.choice)
        h.peer = g
        let beforeReject = h.packets.count
        XCTAssertTrue(guest.submit(.ready(true, selectionRevision: 0)))
        XCTAssertEqual(h.packets.count, beforeReject + 1)
        XCTAssertEqual(host.snapshot, guest.snapshot)
        XCTAssertEqual(host.snapshot?.players.map(\.isReady), [false, false])
        XCTAssertTrue(guest.submit(.select(.liu)))
        let acceptedCommand = try XCTUnwrap(g.packets.last)
        let acceptedState = host.snapshot
        let beforeReplay = h.packets.count
        h.receive?(acceptedCommand, "guest")
        XCTAssertEqual(h.packets.count, beforeReplay + 1)
        XCTAssertEqual(host.snapshot, acceptedState)
        XCTAssertEqual(guest.snapshot, acceptedState)
    }

    func testNetworkLobbyRejectsForeignMalformedOversizedAndReplayTraffic() throws {
        let h = OfflineDuelTransport(local: "host"), g = OfflineDuelTransport(local: "guest")
        h.peer = g; g.peer = h
        let host = DuelNetworkLobby(transport: h), guest = DuelNetworkLobby(transport: g)
        defer { host.shutdown(); guest.shutdown() }
        try host.attach(); try guest.attach()
        let initial = host.snapshot
        h.receive?(Data("not JSON".utf8), "guest")
        h.receive?(Data(repeating: 0, count: DuelNetworkLobby.maximumEnvelopeBytes + 1), "guest")
        let command = DuelMultiplayerSelection.Message(sessionID: try XCTUnwrap(initial?.sessionID),
                                                      sequence: 1, command: .select(.liu))
        let bytes = try JSONEncoder().encode(DuelNetworkLobby.Envelope(.command(command)))
        h.receive?(bytes, "stranger")
        XCTAssertEqual(host.snapshot, initial)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        object["namespace"] = "shift.arena"
        h.receive?(try JSONSerialization.data(withJSONObject: object), "guest")
        XCTAssertEqual(host.snapshot, initial)
        object["namespace"] = DuelNetworkLobby.namespace; object["version"] = 999
        h.receive?(try JSONSerialization.data(withJSONObject: object), "guest")
        XCTAssertEqual(host.snapshot, initial)
        h.receive?(bytes, "guest")
        let accepted = host.snapshot
        h.receive?(bytes, "guest")
        XCTAssertEqual(host.snapshot, accepted)
        XCTAssertEqual(host.snapshot, guest.snapshot)
    }

    func testNetworkLobbyLifecyclePinsRosterAndCreatesFreshSession() throws {
        let transport = OfflineDuelTransport(local: "host")
        let lobby = DuelNetworkLobby(transport: transport)
        try lobby.attach()
        let first = lobby.snapshot?.sessionID
        let oldCallback = transport.receive
        transport.state = .init(isFighter: true, capacity: 2, ready: true,
                                localID: "host", hostID: "host", members: ["host", "replacement"])
        transport.changed?()
        XCTAssertEqual(lobby.status, .closed)
        XCTAssertNil(lobby.snapshot); XCTAssertNil(transport.receive)
        try lobby.attach()
        XCTAssertNotEqual(lobby.snapshot?.sessionID, first)
        let before = lobby.snapshot
        oldCallback?(Data(), "guest")
        XCTAssertEqual(lobby.snapshot, before)
        lobby.shutdown(); lobby.shutdown()
        XCTAssertNil(transport.owner)
        XCTAssertFalse(lobby.submit(.select(.sun)))
    }

    func testNetworkLobbyDoesNotAttachToWrongRoomOrStealCallback() throws {
        let invalid = OfflineDuelTransport(local: "host", members: ["host", "guest", "third"])
        XCTAssertThrowsError(try DuelNetworkLobby(transport: invalid).attach())
        XCTAssertTrue(invalid.packets.isEmpty)
        let busy = OfflineDuelTransport(local: "host")
        busy.owner = UUID()
        XCTAssertThrowsError(try DuelNetworkLobby(transport: busy).attach())
        XCTAssertNotNil(busy.owner)
        XCTAssertTrue(busy.packets.isEmpty)
        // Actual bridge callback ownership can be tested without starting GameRoom.
        let room = GameRoom(kind: .fighter, mode: .nearbyHost, name: "offline", capacity: 2)
        let bridge = DuelGameRoomTransport(room: room)
        let owner = UUID()
        XCTAssertTrue(bridge.claim(owner, receive: { _, _ in }, changed: {}))
        var replacementCalls = 0
        room.onAuthenticatedDirect = { _, _ in replacementCalls += 1 }
        bridge.release(owner)
        room.onAuthenticatedDirect?(Data(), "guest")
        XCTAssertEqual(replacementCalls, 1)
        room.onAuthenticatedDirect = nil
        let next = UUID()
        XCTAssertTrue(bridge.claim(next, receive: { _, _ in }, changed: {}))
        bridge.release(owner)
        XCTAssertNotNil(room.onAuthenticatedDirect)
        bridge.release(next)
        XCTAssertNil(room.onAuthenticatedDirect)
    }

    func testNetworkLobbyDeallocationReleasesOnlyItsOwnLease() async throws {
        let transport = OfflineDuelTransport(local: "host")
        var lobby: DuelNetworkLobby? = DuelNetworkLobby(transport: transport)
        weak var released = lobby
        try lobby?.attach()
        lobby = nil
        XCTAssertNil(released)
        // Deinit cleanup is scheduled on MainActor; explicit shutdown remains
        // synchronous and is the integration contract for ordinary dismissal.
        for _ in 0..<20 where transport.owner != nil { await Task.yield() }
        XCTAssertNil(transport.owner)
        XCTAssertNil(transport.receive)
    }

    func testNetworkLobbyGuestRequiresFreshNonceBeforePinningHostSession() throws {
        let transport = OfflineDuelTransport(local: "guest")
        let lobby = DuelNetworkLobby(transport: transport)
        defer { lobby.shutdown() }
        try lobby.attach()
        let state = try DuelMultiplayerSelection(sessionID: UUID().uuidString, hostID: "host", guestID: "guest")
        let stale = try JSONEncoder().encode(DuelNetworkLobby.Envelope(.snapshot(state.snapshot, nonce: UUID().uuidString)))
        transport.receive?(stale, "host")
        XCTAssertNil(lobby.snapshot)
        let request = try JSONDecoder().decode(DuelNetworkLobby.Envelope.self, from: XCTUnwrap(transport.packets.first))
        guard case .request(let nonce) = request.body else { return XCTFail("Missing handshake") }
        let valid = try JSONEncoder().encode(DuelNetworkLobby.Envelope(.snapshot(state.snapshot, nonce: nonce)))
        transport.receive?(valid, "stranger")
        XCTAssertNil(lobby.snapshot)
        transport.receive?(valid, "host")
        XCTAssertEqual(lobby.snapshot, state.snapshot)
        let other = try DuelMultiplayerSelection(sessionID: UUID().uuidString, hostID: "host", guestID: "guest")
        transport.receive?(try JSONEncoder().encode(DuelNetworkLobby.Envelope(.snapshot(other.snapshot, nonce: nonce))), "host")
        XCTAssertEqual(lobby.snapshot, state.snapshot)
    }
}
