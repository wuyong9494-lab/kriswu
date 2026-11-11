import XCTest
@testable import ShiftReminder

@MainActor
private final class SelectionViewTransport: DuelLobbyTransport {
    var state: DuelLobbyRoomState
    var owner: UUID?
    var receive: ((Data, String) -> Void)?
    var changed: (() -> Void)?
    var packets: [Data] = []
    var delivers = true
    weak var peer: SelectionViewTransport?

    init(local: String) {
        state = .init(isFighter: true, capacity: 2, ready: true,
                      localID: local, hostID: "host", members: ["host", "guest"])
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
        if delivers { peer?.receive?(data, state.localID) }
    }
}

extension DuelLifecycleTests {
    func testSelectionEntryRejectsNonTwoPlayerRemoteCodes() {
        XCTAssertEqual(DuelNetworkSelectionModel.roomCode("2345"), 2345)
        for code in ["", "2", "234", "23456", "1234", "3456", "4567", "8123"] {
            XCTAssertNil(DuelNetworkSelectionModel.roomCode(code), code)
        }
    }

    func testSelectionPresentationConstructionIsInertAndAttachIsOnceOnly() {
        let transport = SelectionViewTransport(local: "host")
        let model = DuelNetworkSelectionModel(lobby: DuelNetworkLobby(transport: transport))
        defer { model.close() }
        XCTAssertEqual(model.status, .idle)
        XCTAssertNil(transport.owner)
        XCTAssertTrue(transport.packets.isEmpty)
        XCTAssertFalse(model.canChoose || model.canReady || model.canStart)
        model.attach(localID: "host")
        let original = model.snapshot?.sessionID
        let count = transport.packets.count
        model.attach(localID: "host")
        XCTAssertEqual(model.snapshot?.sessionID, original)
        XCTAssertEqual(transport.packets.count, count)
        model.close()
        model.attach(localID: "host")
        XCTAssertEqual(model.status, .closed)
        XCTAssertNil(transport.owner)
        XCTAssertNil(model.snapshot)
    }

    func testSelectionPresentationShowsBusyChannelWithoutStealingIt() {
        let transport = SelectionViewTransport(local: "host")
        let otherOwner = UUID()
        transport.owner = otherOwner
        let model = DuelNetworkSelectionModel(lobby: DuelNetworkLobby(transport: transport))
        model.attach(localID: "host")
        XCTAssertEqual(model.status, .closed)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(transport.owner, otherOwner)
        XCTAssertTrue(transport.packets.isEmpty)
    }

    func testSelectionPresentationConflictReadinessAndHostOnlyFinalization() {
        let h = SelectionViewTransport(local: "host"), g = SelectionViewTransport(local: "guest")
        h.peer = g; g.peer = h
        let host = DuelNetworkSelectionModel(lobby: DuelNetworkLobby(transport: h))
        let guest = DuelNetworkSelectionModel(lobby: DuelNetworkLobby(transport: g))
        defer { host.close(); guest.close() }
        host.attach(localID: "host"); guest.attach(localID: "guest")
        XCTAssertTrue(host.canChoose && guest.canChoose)
        XCTAssertFalse(host.canReady || guest.canReady || host.canStart || guest.canStart)
        host.choose(.sun); guest.choose(.sun)
        XCTAssertTrue(host.hasConflict && guest.hasConflict)
        XCTAssertFalse(host.canReady || guest.canReady)
        host.toggleReady(); guest.toggleReady()
        XCTAssertEqual(host.snapshot?.players.map(\.isReady), [false, false])
        guest.choose(.liu)
        XCTAssertFalse(host.hasConflict || guest.hasConflict)
        host.toggleReady(); guest.toggleReady()
        XCTAssertTrue(host.canStart)
        XCTAssertFalse(guest.canStart)
        let packets = g.packets.count
        guest.startSelection()
        XCTAssertEqual(g.packets.count, packets, "Guest UI must not even send Start")
        XCTAssertEqual(host.status, .selecting)
        host.startSelection()
        XCTAssertEqual(host.status, .started)
        XCTAssertEqual(guest.status, .started)
        XCTAssertNil(host.pending); XCTAssertNil(guest.pending)
        XCTAssertFalse(host.canChoose || guest.canChoose || host.canReady || host.canStart)
        let finalPackets = h.packets.count
        host.startSelection(); host.choose(.liu); host.toggleReady()
        XCTAssertEqual(h.packets.count, finalPackets, "Finalized selection remains terminal")
    }

    func testSelectionPresentationChangedChoiceClearsBothReadyStates() {
        let h = SelectionViewTransport(local: "host"), g = SelectionViewTransport(local: "guest")
        h.peer = g; g.peer = h
        let host = DuelNetworkSelectionModel(lobby: DuelNetworkLobby(transport: h))
        let guest = DuelNetworkSelectionModel(lobby: DuelNetworkLobby(transport: g))
        defer { host.close(); guest.close() }
        host.attach(localID: "host"); guest.attach(localID: "guest")
        host.choose(.sun); guest.choose(.liu)
        host.toggleReady(); guest.toggleReady()
        XCTAssertTrue(host.canStart)
        guest.choose(.sun)
        XCTAssertEqual(host.snapshot?.players.map(\.isReady), [false, false])
        XCTAssertEqual(host.snapshot, guest.snapshot)
        XCTAssertFalse(host.canStart)
    }

    func testSelectionPresentationGuestIntentIsNotAcceptedStateOrRepeatable() throws {
        let h = SelectionViewTransport(local: "host"), g = SelectionViewTransport(local: "guest")
        h.peer = g; g.peer = h
        let host = DuelNetworkSelectionModel(lobby: DuelNetworkLobby(transport: h))
        let guest = DuelNetworkSelectionModel(lobby: DuelNetworkLobby(transport: g))
        defer { host.close(); guest.close() }
        host.attach(localID: "host"); guest.attach(localID: "guest")
        g.delivers = false
        guest.choose(.liu)
        XCTAssertNil(guest.localPlayer?.choice, "Preview waits for authoritative acceptance")
        XCTAssertNotNil(guest.pending)
        XCTAssertFalse(guest.canChoose || guest.canReady)
        let count = g.packets.count
        guest.choose(.sun); guest.toggleReady(); guest.startSelection()
        XCTAssertEqual(g.packets.count, count)
        h.receive?(try XCTUnwrap(g.packets.last), "guest")
        XCTAssertNil(guest.pending)
        XCTAssertEqual(guest.localPlayer?.choice, .liu)
        XCTAssertTrue(guest.canChoose)
    }

    func testSelectionPresentationPendingTimeoutEndsSession() async throws {
        let h = SelectionViewTransport(local: "host"), g = SelectionViewTransport(local: "guest")
        h.peer = g; g.peer = h
        let host = DuelNetworkSelectionModel(lobby: DuelNetworkLobby(transport: h))
        let guest = DuelNetworkSelectionModel(lobby: DuelNetworkLobby(transport: g), timeoutNanoseconds: 1_000_000)
        defer { host.close(); guest.close() }
        host.attach(localID: "host"); guest.attach(localID: "guest")
        g.delivers = false
        guest.choose(.liu)
        for _ in 0..<100 where guest.status != .closed { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertEqual(guest.status, .closed)
        XCTAssertTrue(guest.error?.contains("超时") == true)
        XCTAssertNil(guest.snapshot); XCTAssertNil(guest.pending); XCTAssertNil(g.owner)
        XCTAssertFalse(guest.canChoose || guest.canReady || guest.canStart)
    }

    func testSelectionPresentationHandshakeTimeoutAndBackgroundCloseDoNotReattach() async throws {
        let transport = SelectionViewTransport(local: "guest")
        let model = DuelNetworkSelectionModel(lobby: DuelNetworkLobby(transport: transport), timeoutNanoseconds: 1_000_000)
        model.attach(localID: "guest")
        XCTAssertEqual(model.status, .connecting)
        for _ in 0..<100 where model.status != .closed { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertEqual(model.status, .closed)
        XCTAssertNil(transport.owner)
        model.close(reason: "应用已进入后台")
        model.attach(localID: "guest")
        XCTAssertEqual(model.status, .closed)
        XCTAssertEqual(model.error, "应用已进入后台")
        XCTAssertEqual(transport.packets.count, 1)
    }

    func testSelectionPresentationDisconnectClearsPreviewAndPendingIntent() {
        let h = SelectionViewTransport(local: "host"), g = SelectionViewTransport(local: "guest")
        h.peer = g; g.peer = h
        let host = DuelNetworkSelectionModel(lobby: DuelNetworkLobby(transport: h))
        let guest = DuelNetworkSelectionModel(lobby: DuelNetworkLobby(transport: g))
        defer { host.close(); guest.close() }
        host.attach(localID: "host"); guest.attach(localID: "guest")
        host.choose(.sun); guest.choose(.liu)
        g.delivers = false
        guest.toggleReady()
        XCTAssertNotNil(guest.pending)
        g.state = .init(isFighter: true, capacity: 2, ready: false,
                        localID: "guest", hostID: nil, members: ["guest"])
        g.changed?()
        XCTAssertEqual(guest.status, .closed)
        XCTAssertNil(guest.pending); XCTAssertNil(guest.snapshot); XCTAssertNil(g.owner)
        XCTAssertNotNil(guest.error)
    }
}
