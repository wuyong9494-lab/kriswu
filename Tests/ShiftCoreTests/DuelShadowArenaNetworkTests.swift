import XCTest
@testable import ShiftCore

final class DuelShadowArenaNetworkTests: XCTestCase {
    private func makeConnectedPair(
        hostHero: DuelGame.Hero = .wuYong,
        guestHero: DuelGame.Hero = .gale,
        hostDigest: String = "sha256:shadow-arena-v1",
        guestDigest: String = "sha256:shadow-arena-v1"
    ) -> (host: DuelShadowArenaNetworkSession, guest: DuelShadowArenaNetworkSession) {
        var host = DuelShadowArenaNetworkSession(
            role: .host, localPlayerID: "host-1", hostID: "host-1", guestID: "guest-2",
            localAssetDigest: hostDigest, initialHero: hostHero
        )
        var guest = DuelShadowArenaNetworkSession(
            role: .guest, localPlayerID: "guest-2", hostID: "host-1", guestID: "guest-2",
            localAssetDigest: guestDigest, initialHero: guestHero
        )
        _ = host.receive(guest.makeHelloPacket(), from: "guest-2")
        _ = guest.receive(host.makeHelloPacket(), from: "host-1")
        return (host, guest)
    }

    func testAllFourHeroesSelectableAndDeterministicTwoPlayerSync() throws {
        // Test all 4 heroes including Xu Xiao (.gale) and mirror match support
        for (h, g) in [(DuelGame.Hero.wuYong, DuelGame.Hero.gale),
                       (DuelGame.Hero.liu, DuelGame.Hero.ember),
                       (DuelGame.Hero.wuYong, DuelGame.Hero.wuYong)] {
            var (host, guest) = makeConnectedPair(hostHero: h, guestHero: g)
            XCTAssertTrue(host.peerCompatible)
            XCTAssertTrue(guest.peerCompatible)

            if let p = host.setLocalHero(h) { _ = guest.receive(p, from: "host-1") }
            if let p = guest.setLocalHero(g) { _ = host.receive(p, from: "guest-2") }
            if let p = host.setLocalReady(true) { _ = guest.receive(p, from: "host-1") }
            if let p = guest.setLocalReady(true) { _ = host.receive(p, from: "guest-2") }
            XCTAssertTrue(host.canStartMatch)

            let startPacket = try host.startMatch(matchID: "match-01", seed: 20261124)
            let startWire = try startPacket.encoded()
            let decodedStart = try DuelShadowArenaNetworkPacket.decode(startWire)
            let guestStart = guest.receive(decodedStart, from: "host-1")
            XCTAssertTrue(guestStart.matchStarted)
            XCTAssertEqual(host.game, guest.game)

            // Simulate 120 ticks (2 seconds) of batched 2-tick frames with real attacks, movement, and guard
            for batch in 0..<60 {
                let guestIn = DuelGame.Input(
                    move: batch < 15 ? -1 : 0,
                    guardHeld: batch >= 40 && batch < 50,
                    taps: [],
                    vertical: 0,
                    weaponCommand: batch == 20 ? .weapon : (batch == 32 ? .kick : nil)
                )
                if let gPkt = guest.makeGuestInputPacket(guestIn) {
                    let wire = try gPkt.encoded()
                    let recv = host.receive(try DuelShadowArenaNetworkPacket.decode(wire), from: "guest-2")
                    XCTAssertTrue(recv.applied)
                }

                let hostIn = DuelGame.Input(
                    move: batch < 15 ? 1 : 0,
                    guardHeld: batch >= 25 && batch < 35,
                    taps: [],
                    vertical: 0,
                    weaponCommand: batch == 18 ? .weapon : (batch == 42 ? .ranged : nil),
                    heavyHeld: batch >= 50 && batch < 55
                )
                let advanced = try host.advanceHostTicks(count: 2, hostInput: hostIn)
                let framePacket = try XCTUnwrap(advanced.packet)
                let wire = try framePacket.encoded()
                let decoded = try DuelShadowArenaNetworkPacket.decode(wire)
                let guestRecv = guest.receive(decoded, from: "host-1")
                XCTAssertTrue(guestRecv.applied)
                XCTAssertEqual(guestRecv.steps.count, advanced.steps.count)

                // Duplicate retry of the same packet must be safely ignored
                let dupRecv = guest.receive(decoded, from: "host-1")
                XCTAssertFalse(dupRecv.applied)
                XCTAssertTrue(dupRecv.steps.isEmpty)

                // Bit-for-bit identical game state at every single batch
                XCTAssertEqual(host.game, guest.game)
                XCTAssertEqual(host.nextTick, guest.nextTick)
                XCTAssertFalse(guest.desyncDetected)
            }
            // Verify actual fighting moved fighters & dealt combat exchanges (not frozen/bot)
            XCTAssertGreaterThan(host.nextTick, 100)
            XCTAssertNotEqual(host.game?.fighters[0].x, 3400)
        }
    }

    func testAssetDigestMismatchBlocksMatchStart() {
        var (host, guest) = makeConnectedPair(
            hostDigest: "sha256:build-A",
            guestDigest: "sha256:build-B"
        )
        XCTAssertFalse(host.peerCompatible)
        XCTAssertFalse(guest.peerCompatible)
        XCTAssertNotNil(host.incompatibilityReason)
        _ = host.setLocalReady(true)
        _ = guest.setLocalReady(true)
        if let p = guest.setLocalReady(true) { _ = host.receive(p, from: "guest-2") }
        XCTAssertFalse(host.canStartMatch)
        XCTAssertThrowsError(try host.startMatch(matchID: "bad", seed: 1)) { error in
            XCTAssertEqual(error as? DuelShadowArenaNetworkSession.Failure, .peerNotCompatible)
        }
    }

    func testSpoofedSenderAndOutOfOrderFramesAreRejectedSafely() throws {
        var (host, guest) = makeConnectedPair()
        if let p = host.setLocalReady(true) { _ = guest.receive(p, from: "host-1") }
        if let p = guest.setLocalReady(true) { _ = host.receive(p, from: "guest-2") }
        let start = try host.startMatch(matchID: "m-sec", seed: 77)
        _ = guest.receive(start, from: "host-1")

        // Wrong sender cannot inject frames or cancel
        let spoofed = guest.receive(.cancel(reason: "spoof"), from: "attacker")
        XCTAssertFalse(spoofed.applied)
        XCTAssertEqual(guest.phase, .playing(matchID: "m-sec"))

        // Frame gap closes cleanly with desync flag
        let gapPacket = DuelShadowArenaNetworkPacket.hostFrames(
            matchID: "m-sec",
            startTick: 10,
            frames: [.init(host: .neutral, guest: .neutral)],
            checksum: nil
        )
        let gapRes = guest.receive(gapPacket, from: "host-1")
        XCTAssertFalse(gapRes.applied)
        XCTAssertTrue(guest.desyncDetected)
        if case .closed = guest.phase {} else { XCTFail("Expected closed phase on frame gap") }
    }

    func testRematchAndReturnToLobbyFlowWithoutDisconnecting() throws {
        var (host, guest) = makeConnectedPair(hostHero: .wuYong, guestHero: .liu)
        if let p = host.setLocalReady(true) { _ = guest.receive(p, from: "host-1") }
        if let p = guest.setLocalReady(true) { _ = host.receive(p, from: "guest-2") }
        let start = try host.startMatch(matchID: "m-1", seed: 42)
        _ = guest.receive(start, from: "host-1")

        // Return to lobby mid-match returns both peers cleanly to selection
        let ret = try XCTUnwrap(host.requestReturnToLobby())
        let guestRet = guest.receive(ret, from: "host-1")
        XCTAssertTrue(guestRet.returnedToLobby)
        XCTAssertEqual(host.phase, .lobby)
        XCTAssertEqual(guest.phase, .lobby)
        XCTAssertFalse(host.hostSeat.ready)
        XCTAssertFalse(guest.guestSeat.ready)
    }
}
