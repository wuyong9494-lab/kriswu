import Foundation
import XCTest
@testable import ShiftReminder

@MainActor
private final class RouterMemoryTransport: DuelLobbyTransport {
    var state: DuelLobbyRoomState
    var owner: UUID?
    var receive: ((Data, String) -> Void)?
    var changed: (() -> Void)?
    var claimCount = 0
    var releases: [UUID] = []
    var packets: [Data] = []
    var echo = false
    var claimHook: (() -> Void)?
    weak var peer: RouterMemoryTransport?

    init(local: String = "host", guest: String = "guest") {
        state = .init(isFighter: true, capacity: 2, ready: true,
                      localID: local, hostID: "host", members: ["host", guest])
    }
    func claim(_ owner: UUID, receive: @escaping (Data, String) -> Void,
               changed: @escaping () -> Void) -> Bool {
        claimCount += 1
        guard self.owner == nil else { return false }
        self.owner = owner; self.receive = receive; self.changed = changed
        claimHook?()
        return true
    }
    func release(_ owner: UUID) {
        releases.append(owner)
        guard self.owner == owner else { return }
        self.owner = nil; receive = nil; changed = nil
    }
    func sendReliable(_ data: Data) {
        packets.append(data)
        peer?.receive?(data, state.localID)
        if echo { receive?(data, state.localID) }
    }
}

@MainActor
private func routerPacket(_ phase: DuelNetworkMessageRouter.Phase,
                          size: Int? = nil, namespace: String? = nil,
                          version: Int? = nil) throws -> Data {
    let object: [String: Any] = [
        "namespace": namespace ?? phase.namespace, "version": version ?? phase.version,
        "body": ["sender": "forged-payload-identity", "sessionID": "payload-only"]
    ]
    var data = try JSONSerialization.data(withJSONObject: object)
    if let size {
        precondition(data.count <= size)
        // Trailing JSON whitespace keeps the boundary-sized packet parseable.
        data.append(Data(repeating: 32, count: size - data.count))
    }
    return data
}

extension DuelLifecycleTests {
    func testMessageRouterConstructionAndAttachAreExplicit() throws {
        let transport = RouterMemoryTransport()
        let router = DuelNetworkMessageRouter(transport: transport)
        let selection = router.channel(for: .selection)
        XCTAssertTrue(selection === router.channel(for: .selection))
        XCTAssertFalse(selection.state.ready)
        XCTAssertFalse(selection.claim(UUID(), receive: { _, _ in XCTFail() }, changed: {}))
        selection.sendReliable(try routerPacket(.selection))
        XCTAssertEqual(router.status, .idle)
        XCTAssertEqual(transport.claimCount, 0)
        XCTAssertTrue(transport.packets.isEmpty)
        try router.attach()
        defer { router.close() }
        XCTAssertEqual(router.status, .attached)
        XCTAssertTrue(selection.state.ready)
        XCTAssertEqual(transport.claimCount, 1)
        XCTAssertTrue(transport.packets.isEmpty)
        XCTAssertThrowsError(try router.attach()) {
            XCTAssertEqual($0 as? DuelNetworkMessageRouter.Failure, .alreadyAttached)
        }
        XCTAssertEqual(transport.claimCount, 1)
    }

    func testMessageRouterRejectsInvalidRoomAndDoesNotStealBusyLease() throws {
        let invalid = RouterMemoryTransport()
        invalid.state = .init(isFighter: true, capacity: 2, ready: true,
                              localID: "host", hostID: "host", members: ["host", "host"])
        let badRouter = DuelNetworkMessageRouter(transport: invalid)
        XCTAssertThrowsError(try badRouter.attach()) {
            XCTAssertEqual($0 as? DuelNetworkMessageRouter.Failure, .invalidRoom)
        }
        XCTAssertEqual(invalid.claimCount, 0)
        let busy = RouterMemoryTransport(), otherOwner = UUID()
        var calls = 0
        XCTAssertTrue(busy.claim(otherOwner, receive: { _, _ in calls += 1 }, changed: {}))
        let router = DuelNetworkMessageRouter(transport: busy)
        XCTAssertThrowsError(try router.attach()) {
            XCTAssertEqual($0 as? DuelNetworkMessageRouter.Failure, .callbackBusy)
        }
        router.close(); router.close()
        XCTAssertEqual(busy.owner, otherOwner)
        XCTAssertTrue(busy.releases.isEmpty)
        busy.receive?(Data(), "guest")
        XCTAssertEqual(calls, 1)
    }

    func testMessageRouterRoutesOnlyExactNamespaceAndPreservesAuthenticatedSender() throws {
        let transport = RouterMemoryTransport(guest: "Guest/用户")
        let router = DuelNetworkMessageRouter(transport: transport)
        try router.attach()
        defer { router.close() }
        var received: [DuelNetworkMessageRouter.Phase: [Data]] = [:]
        var senders: [String] = []
        for phase in DuelNetworkMessageRouter.Phase.allCases {
            XCTAssertTrue(router.channel(for: phase).claim(UUID(), receive: { data, sender in
                received[phase, default: []].append(data); senders.append(sender)
            }, changed: {}))
        }
        for phase in DuelNetworkMessageRouter.Phase.allCases {
            let bytes = try routerPacket(phase)
            transport.receive?(bytes, "Guest/用户")
            XCTAssertEqual(received[phase], [bytes])
        }
        XCTAssertEqual(senders, ["Guest/用户", "Guest/用户", "Guest/用户"])
        for sender in ["host", "guest/用户", "stranger", ""] {
            transport.receive?(try routerPacket(.selection), sender)
        }
        XCTAssertEqual(senders.count, 3)
        XCTAssertTrue(transport.packets.isEmpty, "Routing does not manufacture replies")
    }

    func testMessageRouterInvalidationDuringRootClaimClosesAndReleasesWithoutSending() throws {
        let transport = RouterMemoryTransport()
        transport.claimHook = { [weak transport] in
            transport?.state = .init(isFighter: true, capacity: 2, ready: true,
                                     localID: "host", hostID: "host", members: ["host", "replacement"])
            transport?.changed?()
        }
        let router = DuelNetworkMessageRouter(transport: transport)
        let channel = router.channel(for: .selection)
        XCTAssertThrowsError(try router.attach()) {
            XCTAssertEqual($0 as? DuelNetworkMessageRouter.Failure, .invalidRoom)
        }
        XCTAssertEqual(router.status, .closed)
        XCTAssertFalse(channel.state.ready)
        XCTAssertNil(transport.owner)
        XCTAssertEqual(transport.releases.count, 1)
        XCTAssertTrue(transport.packets.isEmpty)
        router.close()
        XCTAssertEqual(transport.releases.count, 1)
    }

    func testMessageRouterBoundsBeforeDecodeAndRejectsForeignHeaders() throws {
        let transport = RouterMemoryTransport()
        let router = DuelNetworkMessageRouter(transport: transport)
        try router.attach()
        defer { router.close() }
        var received: [DuelNetworkMessageRouter.Phase: Int] = [:]
        for phase in DuelNetworkMessageRouter.Phase.allCases {
            XCTAssertTrue(router.channel(for: phase).claim(UUID(), receive: { _, _ in
                received[phase, default: 0] += 1
            }, changed: {}))
            transport.receive?(try routerPacket(phase, size: phase.maximumBytes), "guest")
            XCTAssertEqual(received[phase], 1)
            transport.receive?(try routerPacket(phase, size: phase.maximumBytes + 1), "guest")
            transport.receive?(try routerPacket(phase, version: phase.version + 1), "guest")
            transport.receive?(try routerPacket(phase, namespace: phase.namespace + ".extra"), "guest")
            XCTAssertEqual(received[phase], 1)
        }
        let malformed = [Data(), Data("not JSON".utf8), Data("[]".utf8),
            Data("{\"body\":{\"namespace\":\"shift.fighter.selection\",\"version\":1}}".utf8),
            Data("{\"namespace\":\"shift.fighter.selection\",\"version\":\"1\"}".utf8),
            Data(repeating: 123, count: DuelNetworkMessageRouter.maximumPacketBytes + 1)]
        for bytes in malformed { transport.receive?(bytes, "guest") }
        transport.receive?(try routerPacket(.selection, namespace: "shift.arena"), "guest")
        XCTAssertEqual(received.values.reduce(0, +), 3)
    }

    func testMessageRouterOutboundRequiresClaimMatchingNamespaceVersionAndBound() throws {
        let transport = RouterMemoryTransport()
        let router = DuelNetworkMessageRouter(transport: transport)
        try router.attach()
        defer { router.close() }
        var loopbacks = 0
        transport.echo = true
        for phase in DuelNetworkMessageRouter.Phase.allCases {
            let channel = router.channel(for: phase), owner = UUID()
            let bytes = try routerPacket(phase, size: phase.maximumBytes)
            let before = transport.packets.count
            channel.sendReliable(bytes)
            XCTAssertEqual(transport.packets.count, before)
            XCTAssertTrue(channel.claim(owner, receive: { _, _ in loopbacks += 1 }, changed: {}))
            channel.sendReliable(bytes)
            XCTAssertEqual(transport.packets.last, bytes)
            for other in DuelNetworkMessageRouter.Phase.allCases where other != phase {
                channel.sendReliable(try routerPacket(other))
            }
            channel.sendReliable(try routerPacket(phase, size: phase.maximumBytes + 1))
            channel.sendReliable(try routerPacket(phase, version: 999))
            channel.sendReliable(try routerPacket(phase, namespace: "shift.arena"))
            channel.sendReliable(Data("garbage".utf8))
            channel.release(owner)
            channel.sendReliable(bytes)
            XCTAssertEqual(transport.packets.count, before + 1)
        }
        XCTAssertEqual(loopbacks, 0, "Even a transport echo must not route local outbound traffic")
    }

    func testMessageRouterChannelOwnershipIsIndependentAndRetiredOwnersCannotReleaseSuccessor() throws {
        let transport = RouterMemoryTransport()
        let router = DuelNetworkMessageRouter(transport: transport)
        try router.attach()
        defer { router.close() }
        let rootOwner = transport.owner
        let channel = router.channel(for: .selection), old = UUID(), next = UUID()
        var oldCalls = 0, nextCalls = 0, startCalls = 0
        XCTAssertTrue(channel.claim(old, receive: { _, _ in oldCalls += 1 }, changed: {}))
        XCTAssertFalse(channel.claim(old, receive: { _, _ in XCTFail() }, changed: {}))
        XCTAssertFalse(channel.claim(next, receive: { _, _ in XCTFail() }, changed: {}))
        XCTAssertTrue(router.channel(for: .start).claim(UUID(), receive: { _, _ in startCalls += 1 }, changed: {}))
        channel.release(next)
        transport.receive?(try routerPacket(.selection), "guest")
        channel.release(old)
        transport.receive?(try routerPacket(.selection), "guest") // No fallback to start.
        XCTAssertTrue(channel.claim(next, receive: { _, _ in nextCalls += 1 }, changed: {}))
        channel.release(old)
        transport.receive?(try routerPacket(.selection), "guest")
        transport.receive?(try routerPacket(.start), "guest")
        XCTAssertEqual(oldCalls, 1); XCTAssertEqual(nextCalls, 1); XCTAssertEqual(startCalls, 1)
        XCTAssertEqual(transport.owner, rootOwner)
        XCTAssertEqual(transport.claimCount, 1)
        XCTAssertTrue(transport.releases.isEmpty)
    }

    func testMessageRouterKeepsRootLeaseWhenStartedLobbyAndCombatChannelsCoexist() throws {
        let h = RouterMemoryTransport(), g = RouterMemoryTransport(local: "guest")
        h.peer = g; g.peer = h
        let hostRouter = DuelNetworkMessageRouter(transport: h), guestRouter = DuelNetworkMessageRouter(transport: g)
        try hostRouter.attach(); try guestRouter.attach()
        let host = DuelNetworkLobby(transport: hostRouter.channel(for: .selection))
        let guest = DuelNetworkLobby(transport: guestRouter.channel(for: .selection))
        defer { host.shutdown(); guest.shutdown(); hostRouter.close(); guestRouter.close() }
        try host.attach(); try guest.attach()
        XCTAssertTrue(host.submit(.select(.sun))); XCTAssertTrue(guest.submit(.select(.liu)))
        let revision = try XCTUnwrap(host.snapshot?.selectionRevision)
        XCTAssertTrue(host.submit(.ready(true, selectionRevision: revision)))
        XCTAssertTrue(guest.submit(.ready(true, selectionRevision: revision)))
        XCTAssertTrue(host.submit(.start(selectionRevision: revision)))
        XCTAssertEqual(host.status, .started); XCTAssertEqual(guest.status, .started)
        let selected = host.snapshot, rootOwner = h.owner
        var starts = 0, frames = 0
        for router in [hostRouter, guestRouter] {
            XCTAssertTrue(router.channel(for: .start).claim(UUID(), receive: { _, _ in starts += 1 }, changed: {}))
            XCTAssertTrue(router.channel(for: .combat).claim(UUID(), receive: { _, _ in frames += 1 }, changed: {}))
        }
        hostRouter.channel(for: .start).sendReliable(try routerPacket(.start))
        hostRouter.channel(for: .combat).sendReliable(try routerPacket(.combat))
        XCTAssertEqual(starts, 1); XCTAssertEqual(frames, 1)
        XCTAssertEqual(host.snapshot, selected); XCTAssertEqual(guest.snapshot, selected)
        XCTAssertEqual(h.owner, rootOwner); XCTAssertEqual(h.claimCount, 1); XCTAssertEqual(g.claimCount, 1)
        host.shutdown(); guest.shutdown()
        hostRouter.channel(for: .combat).sendReliable(try routerPacket(.combat))
        XCTAssertEqual(frames, 2)
        XCTAssertEqual(h.owner, rootOwner)
        XCTAssertTrue(h.releases.isEmpty && g.releases.isEmpty)
    }

    func testMessageRouterMemberReorderingDoesNotChangePinnedSeatsOrClose() throws {
        let transport = RouterMemoryTransport()
        let router = DuelNetworkMessageRouter(transport: transport)
        try router.attach()
        defer { router.close() }
        let channel = router.channel(for: .combat)
        var changes = 0, received = 0
        XCTAssertTrue(channel.claim(UUID(), receive: { _, _ in received += 1 }, changed: { changes += 1 }))
        transport.state = .init(isFighter: true, capacity: 2, ready: true,
                                localID: "host", hostID: "host", members: ["guest", "host"])
        transport.changed?()
        transport.receive?(try routerPacket(.combat), "guest")
        XCTAssertEqual(router.status, .attached); XCTAssertTrue(channel.state.ready)
        XCTAssertEqual(channel.state.hostID, "host"); XCTAssertEqual(channel.state.localID, "host")
        XCTAssertEqual(changes, 1); XCTAssertEqual(received, 1)
        XCTAssertTrue(transport.releases.isEmpty)
    }

    func testMessageRouterIdentityAndReadinessChangesCloseEveryConsumer() throws {
        let invalid: [DuelLobbyRoomState] = [
            .init(isFighter: false, capacity: 2, ready: true, localID: "host", hostID: "host", members: ["host", "guest"]),
            .init(isFighter: true, capacity: 3, ready: true, localID: "host", hostID: "host", members: ["host", "guest"]),
            .init(isFighter: true, capacity: 2, ready: false, localID: "host", hostID: "host", members: ["host", "guest"]),
            .init(isFighter: true, capacity: 2, ready: true, localID: "guest", hostID: "host", members: ["host", "guest"]),
            .init(isFighter: true, capacity: 2, ready: true, localID: "host", hostID: "guest", members: ["host", "guest"]),
            .init(isFighter: true, capacity: 2, ready: true, localID: "host", hostID: nil, members: ["host", "guest"]),
            .init(isFighter: true, capacity: 2, ready: true, localID: "host", hostID: "host", members: ["host", "replacement"]),
            .init(isFighter: true, capacity: 2, ready: true, localID: "host", hostID: "host", members: ["host", "host"]),
            .init(isFighter: true, capacity: 2, ready: true, localID: "host", hostID: "host", members: ["host", ""]),
            .init(isFighter: true, capacity: 2, ready: true, localID: "host", hostID: "host", members: ["host", String(repeating: "x", count: 257)])
        ]
        for state in invalid {
            let transport = RouterMemoryTransport()
            let router = DuelNetworkMessageRouter(transport: transport)
            try router.attach()
            var closed: [DuelNetworkMessageRouter.Phase] = []
            for phase in DuelNetworkMessageRouter.Phase.allCases {
                let channel = router.channel(for: phase)
                XCTAssertTrue(channel.claim(UUID(), receive: { _, _ in XCTFail() }, changed: {
                    XCTAssertFalse(channel.state.ready); closed.append(phase)
                }))
            }
            let oldReceive = transport.receive, oldChanged = transport.changed
            transport.state = state; transport.changed?()
            XCTAssertEqual(router.status, .closed)
            XCTAssertEqual(Set(closed), Set(DuelNetworkMessageRouter.Phase.allCases))
            oldReceive?(try routerPacket(.combat), "guest"); oldChanged?()
            router.close()
            XCTAssertEqual(closed.count, 3); XCTAssertEqual(transport.releases.count, 1)
            XCTAssertNil(transport.owner)
        }
    }

    func testMessageRouterDetectsMissedRoomObservationAtEveryBoundary() throws {
        for boundary in ["read", "claim", "send", "receive"] {
            let transport = RouterMemoryTransport()
            let router = DuelNetworkMessageRouter(transport: transport)
            try router.attach()
            let channel = router.channel(for: .selection)
            var closed = 0
            XCTAssertTrue(channel.claim(UUID(), receive: { _, _ in XCTFail() }, changed: { closed += 1 }))
            transport.state = .init(isFighter: true, capacity: 2, ready: true,
                                    localID: "host", hostID: "host", members: ["host", "new-peer"])
            switch boundary {
            case "read": XCTAssertFalse(channel.state.ready)
            case "claim": XCTAssertFalse(router.channel(for: .start).claim(UUID(), receive: { _, _ in }, changed: {}))
            case "send": channel.sendReliable(try routerPacket(.selection))
            default: transport.receive?(try routerPacket(.selection), "guest")
            }
            XCTAssertEqual(router.status, .closed, boundary)
            XCTAssertEqual(closed, 1, boundary)
            XCTAssertTrue(transport.packets.isEmpty)
            XCTAssertEqual(transport.releases.count, 1)
        }
    }

    func testMessageRouterCloseIsTerminalReentrantAndPropagatesClosedStateToLobby() throws {
        let transport = RouterMemoryTransport()
        let router = DuelNetworkMessageRouter(transport: transport)
        try router.attach()
        let lobby = DuelNetworkLobby(transport: router.channel(for: .selection))
        try lobby.attach()
        let start = router.channel(for: .start), combat = router.channel(for: .combat), combatOwner = UUID()
        var starts = 0, combats = 0
        XCTAssertTrue(start.claim(UUID(), receive: { _, _ in XCTFail() }, changed: {
            XCTAssertFalse(start.state.ready); XCTAssertFalse(combat.state.ready)
            starts += 1
            router.close()
            combat.release(combatOwner)
            XCTAssertFalse(combat.claim(UUID(), receive: { _, _ in XCTFail() }, changed: {}))
            combat.sendReliable(Data())
        }))
        XCTAssertTrue(combat.claim(combatOwner, receive: { _, _ in XCTFail() }, changed: { combats += 1 }))
        let oldReceive = transport.receive, oldChanged = transport.changed, packetCount = transport.packets.count
        router.close(); router.close()
        XCTAssertEqual(lobby.status, .closed); XCTAssertNil(lobby.snapshot)
        XCTAssertEqual(starts, 1); XCTAssertEqual(combats, 0, "Retired observers must not be called")
        XCTAssertEqual(transport.releases.count, 1)
        XCTAssertTrue(transport.state.ready, "Closing router must not mutate the underlying room")
        XCTAssertFalse(start.state.ready)
        XCTAssertThrowsError(try router.attach()) {
            XCTAssertEqual($0 as? DuelNetworkMessageRouter.Failure, .closed)
        }
        oldReceive?(try routerPacket(.selection), "guest"); oldChanged?()
        XCTAssertEqual(transport.packets.count, packetCount)
        XCTAssertEqual(starts, 1)
    }

    func testMessageRouterObservationDoesNotReachReplacementEvenWhenOwnerUUIDIsReused() throws {
        let transport = RouterMemoryTransport()
        let router = DuelNetworkMessageRouter(transport: transport)
        try router.attach()
        defer { router.close() }
        let selection = router.channel(for: .selection), start = router.channel(for: .start)
        let owner = UUID()
        var oldChanges = 0, newChanges = 0, newReceives = 0
        XCTAssertTrue(selection.claim(UUID(), receive: { _, _ in }, changed: {
            guard router.status == .attached else { return }
            start.release(owner)
            XCTAssertTrue(start.claim(owner, receive: { _, _ in newReceives += 1 }, changed: { newChanges += 1 }))
        }))
        XCTAssertTrue(start.claim(owner, receive: { _, _ in XCTFail() }, changed: { oldChanges += 1 }))
        transport.changed?()
        XCTAssertEqual(oldChanges, 0); XCTAssertEqual(newChanges, 0)
        transport.receive?(try routerPacket(.start), "guest")
        XCTAssertEqual(newReceives, 1)
    }

    func testMessageRouterCloseCannotRemoveReplacementRootCallback() throws {
        let transport = RouterMemoryTransport()
        let router = DuelNetworkMessageRouter(transport: transport)
        try router.attach()
        let retired = try XCTUnwrap(transport.owner), stale = transport.receive
        transport.release(retired)
        let replacement = UUID()
        var calls = 0
        XCTAssertTrue(transport.claim(replacement, receive: { _, _ in calls += 1 }, changed: {}))
        router.close()
        XCTAssertEqual(transport.owner, replacement)
        stale?(try routerPacket(.selection), "guest")
        transport.receive?(Data(), "guest")
        XCTAssertEqual(calls, 1)
    }

    func testMessageRouterDeallocationClosesRetainedEndpointAndReleasesRootOnce() async throws {
        let transport = RouterMemoryTransport()
        var router: DuelNetworkMessageRouter? = DuelNetworkMessageRouter(transport: transport)
        weak var released = router
        try router?.attach()
        let channel = try XCTUnwrap(router?.channel(for: .combat))
        var closures = 0
        XCTAssertTrue(channel.claim(UUID(), receive: { _, _ in XCTFail() }, changed: {
            XCTAssertFalse(channel.state.ready); closures += 1
        }))
        router = nil
        XCTAssertNil(released, "Endpoints must not retain the root")
        XCTAssertFalse(channel.state.ready)
        XCTAssertFalse(channel.claim(UUID(), receive: { _, _ in XCTFail() }, changed: {}))
        for _ in 0..<20 where transport.owner != nil { await Task.yield() }
        XCTAssertNil(transport.owner)
        XCTAssertEqual(transport.releases.count, 1)
        XCTAssertEqual(closures, 1)
    }

    func testRoutedSelectionModelOwnsRootAcrossSelectionAgreementUntilClose() {
        let h = RouterMemoryTransport(), g = RouterMemoryTransport(local: "guest")
        h.peer = g; g.peer = h
        let host = DuelNetworkSelectionModel(transport: h), guest = DuelNetworkSelectionModel(transport: g)
        defer { host.close(); guest.close() }
        XCTAssertEqual(h.claimCount, 0); XCTAssertEqual(g.claimCount, 0)
        XCTAssertTrue(h.packets.isEmpty && g.packets.isEmpty)
        host.attach(localID: "host"); guest.attach(localID: "guest")
        let hostOwner = h.owner, guestOwner = g.owner
        XCTAssertNotNil(hostOwner); XCTAssertNotNil(guestOwner)
        XCTAssertEqual(host.status, .selecting); XCTAssertEqual(guest.status, .selecting)
        host.choose(.sun); guest.choose(.liu)
        XCTAssertEqual(host.snapshot, guest.snapshot)
        XCTAssertEqual(host.localPlayer?.choice, .sun); XCTAssertEqual(guest.localPlayer?.choice, .liu)
        host.toggleReady(); guest.toggleReady(); host.startSelection()
        XCTAssertEqual(host.status, .started); XCTAssertEqual(guest.status, .started)
        XCTAssertEqual(h.owner, hostOwner); XCTAssertEqual(g.owner, guestOwner)
        XCTAssertTrue(h.releases.isEmpty && g.releases.isEmpty)
        host.attach(localID: "host"); guest.attach(localID: "guest")
        XCTAssertEqual(h.claimCount, 1); XCTAssertEqual(g.claimCount, 1)
        host.close(); guest.close()
        XCTAssertEqual(h.releases.count, 1); XCTAssertEqual(g.releases.count, 1)
        XCTAssertNil(h.owner); XCTAssertNil(g.owner)
        XCTAssertNil(host.snapshot); XCTAssertNil(guest.snapshot)
        XCTAssertNil(host.pending); XCTAssertNil(guest.pending)
        XCTAssertTrue(h.state.ready && g.state.ready, "The models must not disconnect their transports")
    }

    func testRoutedSelectionModelBackgroundCloseIsTerminalAndBeforeAttachIsInert() {
        for attachFirst in [false, true] {
            let transport = RouterMemoryTransport()
            let model = DuelNetworkSelectionModel(transport: transport)
            if attachFirst { model.attach(localID: "host") }
            let packetCount = transport.packets.count
            model.close(reason: "应用已进入后台")
            model.close(); model.attach(localID: "host")
            XCTAssertEqual(model.status, .closed)
            XCTAssertEqual(model.error, "应用已进入后台")
            XCTAssertNil(model.snapshot); XCTAssertNil(model.pending)
            XCTAssertNil(transport.owner)
            XCTAssertEqual(transport.claimCount, attachFirst ? 1 : 0)
            XCTAssertEqual(transport.releases.count, attachFirst ? 1 : 0)
            XCTAssertEqual(transport.packets.count, packetCount)
        }
    }

    func testRoutedSelectionModelHandshakeAndPendingTimeoutReleaseRootWithoutReclaim() async throws {
        for pendingCommand in [false, true] {
            let h = RouterMemoryTransport(), g = RouterMemoryTransport(local: "guest")
            let host = DuelNetworkSelectionModel(transport: h)
            let guest = DuelNetworkSelectionModel(transport: g, timeoutNanoseconds: 1_000_000)
            defer { host.close(); guest.close() }
            if pendingCommand {
                h.peer = g; g.peer = h
                host.attach(localID: "host")
            }
            guest.attach(localID: "guest")
            if pendingCommand {
                g.peer = nil
                guest.choose(.liu)
                XCTAssertNotNil(guest.pending)
            } else {
                XCTAssertEqual(guest.status, .connecting)
            }
            for _ in 0..<100 where guest.status != .closed { try await Task.sleep(nanoseconds: 1_000_000) }
            XCTAssertEqual(guest.status, .closed)
            XCTAssertTrue(guest.error?.contains("超时") == true)
            XCTAssertNil(guest.snapshot); XCTAssertNil(guest.pending); XCTAssertNil(g.owner)
            XCTAssertEqual(g.releases.count, 1)
            let count = g.packets.count
            guest.attach(localID: "guest"); guest.close()
            XCTAssertEqual(g.claimCount, 1); XCTAssertEqual(g.releases.count, 1)
            XCTAssertEqual(g.packets.count, count)
        }
    }

    func testRoutedSelectionModelAttachErrorsRetireOwnedRootWithoutStealingOrRetrying() {
        let busy = RouterMemoryTransport(), occupied = UUID()
        XCTAssertTrue(busy.claim(occupied, receive: { _, _ in }, changed: {}))
        let busyModel = DuelNetworkSelectionModel(transport: busy)
        busyModel.attach(localID: "host"); busyModel.attach(localID: "host"); busyModel.close()
        XCTAssertEqual(busyModel.status, .closed)
        XCTAssertTrue(busyModel.error?.contains("通道正在被使用") == true)
        XCTAssertEqual(busy.owner, occupied)
        XCTAssertEqual(busy.claimCount, 2, "One existing owner and one failed model claim")
        XCTAssertTrue(busy.releases.isEmpty && busy.packets.isEmpty)

        let changed = RouterMemoryTransport()
        changed.claimHook = { [weak changed] in
            changed?.state = .init(isFighter: true, capacity: 2, ready: false,
                                   localID: "host", hostID: "host", members: ["host", "guest"])
        }
        let failedModel = DuelNetworkSelectionModel(transport: changed)
        failedModel.attach(localID: "host"); failedModel.attach(localID: "host"); failedModel.close()
        XCTAssertEqual(failedModel.status, .closed)
        XCTAssertNotNil(failedModel.error)
        XCTAssertNil(failedModel.snapshot); XCTAssertNil(failedModel.pending); XCTAssertNil(changed.owner)
        XCTAssertEqual(changed.claimCount, 1); XCTAssertEqual(changed.releases.count, 1)
        XCTAssertTrue(changed.packets.isEmpty)
    }

    func testRoutedSelectionModelProtocolSessionClosureAlsoReleasesRoot() {
        let h = RouterMemoryTransport(), g = RouterMemoryTransport(local: "guest")
        h.peer = g; g.peer = h
        let host = DuelNetworkSelectionModel(transport: h), guest = DuelNetworkSelectionModel(transport: g)
        let nextHost = DuelNetworkSelectionModel(transport: h)
        defer { host.close(); guest.close(); nextHost.close() }
        host.attach(localID: "host"); guest.attach(localID: "guest")
        guest.choose(.liu)
        XCTAssertNotNil(guest.snapshot)
        host.close()
        // A new host session announces itself in the same authenticated room.
        // The old guest lobby closes without any room-state observation.
        nextHost.attach(localID: "host")
        XCTAssertEqual(guest.status, .closed)
        XCTAssertNil(guest.snapshot); XCTAssertNil(guest.pending); XCTAssertNil(g.owner)
        XCTAssertNotNil(guest.error)
        XCTAssertEqual(g.releases.count, 1)
        guest.attach(localID: "guest")
        XCTAssertEqual(g.claimCount, 1)
        XCTAssertTrue(g.state.ready)
    }

    func testRoutedSelectionModelDeallocationReleasesItsRetainedRoot() async {
        let transport = RouterMemoryTransport()
        var model: DuelNetworkSelectionModel? = DuelNetworkSelectionModel(transport: transport)
        weak var released = model
        model?.attach(localID: "host")
        XCTAssertNotNil(transport.owner)
        model = nil
        XCTAssertNil(released)
        for _ in 0..<20 where transport.owner != nil { await Task.yield() }
        XCTAssertNil(transport.owner)
        XCTAssertEqual(transport.claimCount, 1); XCTAssertEqual(transport.releases.count, 1)
    }
}
