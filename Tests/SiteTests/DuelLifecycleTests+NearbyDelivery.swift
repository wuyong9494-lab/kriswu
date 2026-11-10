import Foundation
@preconcurrency import MultipeerConnectivity
import XCTest
@testable import ShiftReminder

#if DEBUG
/// Encode the existing wire format, not a testing-only authenticated transport.
private enum NearbyDeliveryEnvelope: Encodable {
    case hello(GameRoom.Member)
    case payload(from: String, data: Data)
}

private func nearbyDirect(_ text: String, from sender: String = "guest") -> Data {
    let identity = Array(sender.utf8)
    return Data([GameRoom.directMarker, UInt8(identity.count)] + identity + Array(text.utf8))
}

/// Hold the main actor only until the finite source callback burst is enqueued.
/// No source callback waits on main, and the deadline prevents a test deadlock.
private func submitNearbySerialBurst(_ body: @escaping @Sendable () -> Void) {
    let enqueued = DispatchSemaphore(value: 0)
    DispatchQueue(label: "fighter.test.serial-delegate").async {
        XCTAssertFalse(Thread.isMainThread)
        body()
        enqueued.signal()
    }
    XCTAssertEqual(enqueued.wait(timeout: .now() + 5), .success)
}

@MainActor
private func finishNearbyTaskTurn() async {
    // Match the production bridge's explicit actor isolation. SE-0431 lets
    // the current Swift toolchain enqueue this closure directly on MainActor.
    // Positive ordering tests also wait for every expected callback, so a
    // prematurely scheduled marker cannot masquerade as a completed burst.
    await Task { @MainActor in XCTAssertTrue(Thread.isMainThread) }.value
}

extension DuelLifecycleTests {
    func testNearbyAllGamesKeepExistingSessionDelegate() throws {
        for kind in [GameKind.tiles, .gomoku, .arena, .fighter] {
            for mode in [GameRoom.Mode.nearbyHost, .nearbyGuest] {
                let room = GameRoom(kind: kind, mode: mode, name: "offline", capacity: 2)
                let session = room.testingMakeNearbySession()
                let delegate = try XCTUnwrap(session.delegate)
                XCTAssertTrue(delegate === room)
                XCTAssertEqual(session.encryptionPreference, .required)
                XCTAssertTrue(session.connectedPeers.isEmpty)
                XCTAssertEqual(room.phase, .idle, "The fixture must not start a network connection")
                room.leave()
                XCTAssertNil(session.delegate)
            }
        }
    }

    func testNearbyFighterSerialBurstPreservesStateHelloPayloadAndDirectOrder() async throws {
        let room = GameRoom(kind: .fighter, mode: .nearbyHost, name: "offline", capacity: 2)
        let session = room.testingMakeNearbySession()
        let delegate = try XCTUnwrap(session.delegate)
        let peer = MCPeerID(displayName: "peer")
        defer { room.leave() }
        var received: [String] = []
        let completed = expectation(description: "All state, envelope and direct callbacks")
        completed.expectedFulfillmentCount = 516
        room.onMembersChanged = {
            XCTAssertTrue(Thread.isMainThread)
            received.append(room.members.isEmpty ? "disconnected" : "hello")
            completed.fulfill()
        }
        room.onDirect = { data, sender in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(room.phase, .ready)
            XCTAssertEqual(room.members.map(\.id), ["guest"])
            XCTAssertEqual(sender, "guest")
            received.append(String(decoding: data, as: UTF8.self))
            completed.fulfill()
        }
        room.onPayload = { data, sender in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(sender, "guest")
            received.append(String(decoding: data, as: UTF8.self))
            completed.fulfill()
        }
        room.onAuthenticatedDirect = { _, _ in
            XCTFail("Injecting delegate callbacks cannot manufacture a live connected peer")
        }
        let hello = try JSONEncoder().encode(NearbyDeliveryEnvelope.hello(.init(id: "guest", name: "Guest")))
        var packets: [Data] = []
        var expected = ["hello"]
        for index in 0..<256 {
            packets.append(nearbyDirect("direct-\(index)"))
            packets.append(try JSONEncoder().encode(NearbyDeliveryEnvelope.payload(
                from: "guest", data: Data("payload-\(index)".utf8))))
            expected += ["direct-\(index)", "payload-\(index)"]
        }
        expected += ["disconnected", "hello", "after-reconnect"]
        // Match Apple's serial background source without advertising/browsing.
        let callbackPackets = packets
        submitNearbySerialBurst {
            delegate.session(session, peer: peer, didChange: .connecting)
            delegate.session(session, peer: peer, didChange: .connected)
            delegate.session(session, didReceive: hello, fromPeer: peer)
            for packet in callbackPackets { delegate.session(session, didReceive: packet, fromPeer: peer) }
            delegate.session(session, peer: peer, didChange: .notConnected)
            delegate.session(session, peer: peer, didChange: .connected)
            delegate.session(session, didReceive: hello, fromPeer: peer)
            delegate.session(session, didReceive: nearbyDirect("after-reconnect"), fromPeer: peer)
        }
        XCTAssertTrue(received.isEmpty, "Callbacks must enqueue, not execute on the delegate queue")
        await fulfillment(of: [completed], timeout: 5)
        XCTAssertEqual(received, expected)
        XCTAssertTrue(session.connectedPeers.isEmpty)
    }

    func testNearbyFighterCallbackAlreadyOnMainCannotOvertakeQueuedPacket() async throws {
        let room = GameRoom(kind: .fighter, mode: .nearbyHost, name: "offline", capacity: 2)
        let session = room.testingMakeNearbySession()
        let delegate = try XCTUnwrap(session.delegate)
        let peer = MCPeerID(displayName: "peer")
        defer { room.leave() }
        var received: [String] = []
        let completed = expectation(description: "Both callback sources finish")
        completed.expectedFulfillmentCount = 2
        room.onDirect = { data, _ in
            received.append(String(decoding: data, as: UTF8.self))
            completed.fulfill()
        }
        submitNearbySerialBurst {
            delegate.session(session, didReceive: nearbyDirect("first"), fromPeer: peer)
        }
        delegate.session(session, didReceive: nearbyDirect("second"), fromPeer: peer)
        XCTAssertTrue(received.isEmpty)
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(received, ["first", "second"])
    }

    func testNearbyFighterRejectsQueuedAndLateCallbacksFromRetiredSession() async throws {
        let room = GameRoom(kind: .fighter, mode: .nearbyHost, name: "offline", capacity: 2)
        let old = room.testingMakeNearbySession()
        let oldDelegate = try XCTUnwrap(old.delegate)
        let peer = MCPeerID(displayName: "peer")
        let oldHello = try JSONEncoder().encode(NearbyDeliveryEnvelope.hello(.init(id: "old", name: "Old")))
        let payload = try JSONEncoder().encode(NearbyDeliveryEnvelope.payload(from: "old", data: Data()))
        defer { room.leave(); old.disconnect() }
        var received: [String] = []
        room.onMembersChanged = { received.append(room.members.map(\.id).joined()) }
        room.onDirect = { data, _ in received.append(String(decoding: data, as: UTF8.self)) }
        room.onPayload = { _, _ in XCTFail("A stale session cannot deliver an envelope") }
        oldDelegate.session(old, didReceive: oldHello, fromPeer: peer)
        oldDelegate.session(old, didReceive: nearbyDirect("queued-old"), fromPeer: peer)
        oldDelegate.session(old, didReceive: payload, fromPeer: peer)
        oldDelegate.session(old, peer: peer, didChange: .notConnected)

        let current = room.testingMakeNearbySession()
        let currentDelegate = try XCTUnwrap(current.delegate)
        let hello = try JSONEncoder().encode(NearbyDeliveryEnvelope.hello(.init(id: "new", name: "New")))
        currentDelegate.session(current, didReceive: hello, fromPeer: peer)
        // Both sessions use the same room delegate. Only the source session
        // identity can authorize a callback; retaining that delegate is not enough.
        XCTAssertTrue(oldDelegate === currentDelegate)
        oldDelegate.session(old, didReceive: oldHello, fromPeer: peer)
        oldDelegate.session(old, didReceive: nearbyDirect("late-old"), fromPeer: peer)
        oldDelegate.session(old, didReceive: payload, fromPeer: peer)
        oldDelegate.session(old, peer: peer, didChange: .notConnected)
        currentDelegate.session(current, didReceive: nearbyDirect("current", from: "new"), fromPeer: peer)
        await finishNearbyTaskTurn()
        XCTAssertEqual(received, ["new", "current"])
        XCTAssertEqual(room.members.map(\.id), ["new"])
        XCTAssertEqual(room.phase, .ready)
    }

    func testNearbyFighterLeavingDiscardsQueuedAndLateWorkWithoutErasingNewCallbackOwner() async throws {
        let room = GameRoom(kind: .fighter, mode: .nearbyHost, name: "offline", capacity: 2)
        let session = room.testingMakeNearbySession()
        let delegate = try XCTUnwrap(session.delegate)
        let peer = MCPeerID(displayName: "peer")
        let hello = try JSONEncoder().encode(NearbyDeliveryEnvelope.hello(.init(id: "guest", name: "Guest")))
        delegate.session(session, didReceive: hello, fromPeer: peer)
        delegate.session(session, didReceive: nearbyDirect("queued"), fromPeer: peer)
        room.leave()
        let successor = UUID()
        XCTAssertTrue(room.installAuthenticatedDirect(owner: successor) { _, _ in XCTFail("Retired session") })
        room.onDirect = { _, _ in XCTFail("Retired session") }
        room.onPayload = { _, _ in XCTFail("Retired session") }
        room.onMembersChanged = { XCTFail("Retired session") }
        delegate.session(session, peer: peer, didChange: .connected)
        delegate.session(session, didReceive: hello, fromPeer: peer)
        delegate.session(session, didReceive: nearbyDirect("late"), fromPeer: peer)
        delegate.session(session, peer: peer, didChange: .notConnected)
        await finishNearbyTaskTurn()
        XCTAssertTrue(room.ownsAuthenticatedDirect(successor))
        XCTAssertTrue(room.members.isEmpty)
        XCTAssertEqual(room.phase, .idle)
        XCTAssertNil(session.delegate)
        room.leave()
    }

    func testNearbyFighterHelloCallbackCanLeaveBeforeRestOfBurst() async throws {
        let room = GameRoom(kind: .fighter, mode: .nearbyHost, name: "offline", capacity: 2)
        let session = room.testingMakeNearbySession()
        let delegate = try XCTUnwrap(session.delegate)
        let peer = MCPeerID(displayName: "peer")
        let hello = try JSONEncoder().encode(NearbyDeliveryEnvelope.hello(.init(id: "guest", name: "Guest")))
        var changes = 0
        room.onMembersChanged = {
            changes += 1
            room.leave()
            room.onDirect = { _, _ in XCTFail("Queued callback must not reach the replacement consumer") }
            room.onMembersChanged = { XCTFail("Queued disconnection must not reach replacement consumer") }
        }
        delegate.session(session, didReceive: hello, fromPeer: peer)
        delegate.session(session, didReceive: nearbyDirect("queued"), fromPeer: peer)
        delegate.session(session, peer: peer, didChange: .notConnected)
        await finishNearbyTaskTurn()
        XCTAssertEqual(changes, 1)
        XCTAssertNil(session.delegate)
        room.leave()
    }

    func testNearbyFighterDirectCallbackCanReplaceSessionDuringBurst() async throws {
        let room = GameRoom(kind: .fighter, mode: .nearbyHost, name: "offline", capacity: 2)
        let old = room.testingMakeNearbySession()
        let oldDelegate = try XCTUnwrap(old.delegate)
        let peer = MCPeerID(displayName: "peer")
        let hello = try JSONEncoder().encode(NearbyDeliveryEnvelope.hello(.init(id: "old", name: "Old")))
        var received: [String] = []
        let successor = UUID()
        room.onDirect = { data, _ in
            received.append(String(decoding: data, as: UTF8.self))
            room.leave()
            let current = room.testingMakeNearbySession()
            XCTAssertTrue(room.installAuthenticatedDirect(owner: successor) { _, _ in XCTFail("No connected peer") })
            room.onMembersChanged = { XCTFail("Old hello cannot mutate replacement session") }
            room.onDirect = { data, _ in received.append(String(decoding: data, as: UTF8.self)) }
            current.delegate?.session(current, didReceive: nearbyDirect("replacement"), fromPeer: peer)
        }
        oldDelegate.session(old, didReceive: nearbyDirect("first"), fromPeer: peer)
        oldDelegate.session(old, didReceive: nearbyDirect("stale-second"), fromPeer: peer)
        oldDelegate.session(old, didReceive: hello, fromPeer: peer)
        oldDelegate.session(old, peer: peer, didChange: .notConnected)
        await finishNearbyTaskTurn()
        // The replacement creates another explicitly isolated task from inside
        // the first delivery. Include a second actor turn for that nested task.
        await finishNearbyTaskTurn()
        XCTAssertEqual(received, ["first", "replacement"])
        XCTAssertTrue(room.ownsAuthenticatedDirect(successor))
        XCTAssertTrue(room.members.isEmpty)
        XCTAssertNil(old.delegate)
        room.leave()
    }

    func testNearbyFighterMalformedPacketsStayRejectedAndOfflineClaimsStayUnauthenticated() async throws {
        let room = GameRoom(kind: .fighter, mode: .nearbyHost, name: "offline", capacity: 2)
        let session = room.testingMakeNearbySession()
        let delegate = try XCTUnwrap(session.delegate)
        let peer = MCPeerID(displayName: "peer")
        defer { room.leave() }
        var legacySenders: [String] = []
        room.onDirect = { _, sender in legacySenders.append(sender) }
        room.onAuthenticatedDirect = { _, _ in XCTFail("A claimed identity is not an authenticated connection") }
        room.onPayload = { _, _ in XCTFail("Malformed envelope") }
        delegate.session(session, didReceive: Data(), fromPeer: peer)
        delegate.session(session, didReceive: Data([GameRoom.directMarker, 100, 1]), fromPeer: peer)
        delegate.session(session, didReceive: Data([GameRoom.directMarker, 1, 0xFF]), fromPeer: peer)
        delegate.session(session, didReceive: Data("{not-json}".utf8), fromPeer: peer)
        let hello = try JSONEncoder().encode(NearbyDeliveryEnvelope.hello(.init(id: "guest", name: "Guest")))
        delegate.session(session, didReceive: hello, fromPeer: peer)
        for claim in ["guest", "stranger", room.me.id, ""] {
            delegate.session(session, didReceive: nearbyDirect("claim", from: claim), fromPeer: peer)
        }
        await finishNearbyTaskTurn()
        XCTAssertEqual(legacySenders, ["guest", "stranger", room.me.id, ""],
                       "The legacy raw callback remains separate from authenticated delivery")
        XCTAssertTrue(session.connectedPeers.isEmpty)
    }

    func testNearbyOtherGamesKeepExistingDirectCallbackAndOfflineAuthenticationChecks() async throws {
        for kind in [GameKind.tiles, .gomoku, .arena] {
            let room = GameRoom(kind: kind, mode: .nearbyHost, name: "offline", capacity: 2)
            let session = room.testingMakeNearbySession()
            let delegate = try XCTUnwrap(session.delegate)
            let peer = MCPeerID(displayName: "peer")
            let delivered = expectation(description: "Existing \(kind.rawValue) Task bridge")
            room.onDirect = { data, sender in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertEqual(String(decoding: data, as: UTF8.self), "legacy")
                XCTAssertEqual(sender, "guest")
                delivered.fulfill()
            }
            room.onAuthenticatedDirect = { _, _ in XCTFail("No live connected peer") }
            XCTAssertTrue(delegate === room)
            delegate.session(session, didReceive: nearbyDirect("legacy"), fromPeer: peer)
            await fulfillment(of: [delivered], timeout: 1)
            room.leave()
        }
    }
}
#endif
