import XCTest
@testable import ShiftCore

final class DuelNetworkHostSimulationTests: XCTestCase {
    private typealias Simulation = DuelNetworkHostSimulation
    private func started(swapped: Bool = false) throws -> DuelMultiplayerSelection.Snapshot {
        var lobby = try DuelMultiplayerSelection(sessionID: "s", hostID: "z-host", guestID: "a-guest")
        func send(_ command: DuelMultiplayerSelection.Command, _ sender: String, _ sequence: UInt64) {
            XCTAssertEqual(lobby.apply(.init(sessionID: "s", sequence: sequence, command: command),
                                       authenticatedSenderID: sender, localPlayerID: "z-host"), .applied)
        }
        send(.select(swapped ? .liu : .sun), "z-host", 1)
        send(.select(swapped ? .sun : .liu), "a-guest", 1)
        send(.ready(true, selectionRevision: 2), "z-host", 2)
        send(.ready(true, selectionRevision: 2), "a-guest", 2)
        send(.start(selectionRevision: 2), "z-host", 3)
        return lobby.snapshot
    }
    private func simulation(swapped: Bool = false) throws -> Simulation {
        try Simulation(started: started(swapped: swapped), localPlayerID: "z-host",
                       catalog: DuelWeaponTestFixtures.catalog(), seed: 73)
    }
    private func edit(_ snapshot: DuelMultiplayerSelection.Snapshot,
                      _ mutation: (inout [String: Any]) -> Void) throws -> DuelMultiplayerSelection.Snapshot {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        mutation(&object)
        return try JSONDecoder().decode(DuelMultiplayerSelection.Snapshot.self,
                                        from: JSONSerialization.data(withJSONObject: object))
    }

    func testPinnedSeatsAndBothHeroOrdersUseEquippedProfiles() throws {
        for swapped in [false, true] {
            let sim = try simulation(swapped: swapped)
            XCTAssertEqual(sim.inputs.hostID, "z-host")
            XCTAssertEqual(sim.inputs.guestID, "a-guest")
            XCTAssertEqual(sim.game.fighters.map(\.hero), swapped ? [.liu, .ember] : [.ember, .liu])
            XCTAssertNotNil(sim.game.weaponFight)
            XCTAssertEqual(sim.seed, 73)
        }
    }

    func testDecodedInvalidStartNeverCreatesAuthority() throws {
        let snapshot = try started()
        let edits: [(inout [String: Any]) -> Void] = [
            { $0["version"] = 99 }, { $0["sessionID"] = " " },
            { $0["phase"] = "selecting" }, { $0["phase"] = "disconnected" },
            { $0["players"] = [] }, { $0["revision"] = 0 },
            { $0["selectionRevision"] = 0 }, { $0["selectionRevision"] = 5 },
            { var p = $0["players"] as! [[String: Any]]; p.reverse(); $0["players"] = p },
            { var p = $0["players"] as! [[String: Any]]; p[1]["id"] = "z-host"; $0["players"] = p },
            { var p = $0["players"] as! [[String: Any]]; p[1]["id"] = " "; $0["players"] = p },
            { var p = $0["players"] as! [[String: Any]]; p[1]["seat"] = 0; $0["players"] = p },
            { var p = $0["players"] as! [[String: Any]]; p[1]["isReady"] = false; $0["players"] = p },
            { var p = $0["players"] as! [[String: Any]]; p[0]["lastSequence"] = 2; $0["players"] = p },
            { var p = $0["players"] as! [[String: Any]]; p[1].removeValue(forKey: "choice"); $0["players"] = p },
            { var p = $0["players"] as! [[String: Any]]; p[1]["choice"] = p[0]["choice"]; $0["players"] = p },
            { var p = $0["players"] as! [[String: Any]]; p[1]["choice"] = ["hero": "ember", "weapon": "liu_hammers"]; $0["players"] = p }
        ]
        for mutation in edits {
            let invalid = try edit(snapshot, mutation)
            XCTAssertThrowsError(try Simulation(started: invalid, localPlayerID: "z-host",
                                                catalog: DuelWeaponTestFixtures.catalog(), seed: 73))
        }
        XCTAssertThrowsError(try Simulation(started: snapshot, localPlayerID: "a-guest",
                                            catalog: DuelWeaponTestFixtures.catalog(), seed: 73)) {
            XCTAssertEqual($0 as? Simulation.Failure, .notHost)
        }
    }

    func testMissingAndInvalidCatalogNeverFallBackToLaboratory() throws {
        let snapshot = try started()
        XCTAssertThrowsError(try Simulation(started: snapshot, localPlayerID: "z-host", catalog: nil, seed: 73)) {
            XCTAssertEqual($0 as? Simulation.Failure, .missingCatalog)
        }
        let invalid = try DuelWeaponTestFixtures.changing(DuelWeaponTestFixtures.catalog()) { $0.removeLast() }
        XCTAssertThrowsError(try Simulation(started: snapshot, localPlayerID: "z-host", catalog: invalid, seed: 73)) {
            XCTAssertEqual($0 as? Simulation.Failure, .invalidCatalog)
        }
    }

    func testMissingGuestNeverRunsAIAndSeededStreamsReproduce() throws {
        var a = try simulation(), b = try simulation()
        var expected = a.game
        for tick in UInt64(0)..<120 {
            let message = DuelNetworkInputs.Message(sessionID: "s", sequence: tick + 1, tick: tick,
                                                    move: tick < 12 ? 1 : 0,
                                                    weaponCommand: tick % 20 == 0 ? .weapon : nil)
            XCTAssertEqual(a.receive(message, authenticatedSenderID: "z-host", localPlayerID: "z-host"), .applied)
            XCTAssertEqual(b.receive(message, authenticatedSenderID: "z-host", localPlayerID: "z-host"), .applied)
            let frame = try a.step(localPlayerID: "z-host")
            XCTAssertEqual(frame.guest, .neutral)
            XCTAssertEqual(try b.step(localPlayerID: "z-host"), frame)
            expected.step(frame.host, opponent: .neutral)
            XCTAssertEqual(a.game, expected)
            XCTAssertEqual(a, b)
        }
        XCTAssertEqual(a.game.fighters[1].x, 6500)
    }

    func testBothPeersReplayAgainstExplicitGameInBothHeroOrders() throws {
        for swapped in [false, true] {
            var sim = try simulation(swapped: swapped)
            var replay = try simulation(swapped: swapped)
            var expected = sim.game
            for tick in UInt64(0)..<180 {
                // Distinct inputs make a swapped seat or ignored guest observable.
                let host = DuelGame.Input(move: tick < 18 ? 1 : 0,
                                          weaponCommand: tick >= 20 && tick % 24 == 20 ? .weapon : nil)
                let guest = DuelGame.Input(move: tick < 18 ? -1 : 0,
                                           weaponCommand: tick >= 20 && tick % 30 == 20 ? .heavy : nil)
                for (player, input) in [("z-host", host), ("a-guest", guest)] {
                    let message = DuelNetworkInputs.Message(
                        sessionID: "s", sequence: tick + 1, tick: tick,
                        move: input.move, weaponCommand: input.weaponCommand)
                    XCTAssertEqual(sim.receive(message, authenticatedSenderID: player,
                                               localPlayerID: "z-host"), .applied)
                    XCTAssertEqual(replay.receive(message, authenticatedSenderID: player,
                                                  localPlayerID: "z-host"), .applied)
                }
                let frame = try sim.step(localPlayerID: "z-host")
                XCTAssertEqual(frame.tick, tick)
                XCTAssertEqual(frame.host, host)
                XCTAssertEqual(frame.guest, guest)
                XCTAssertEqual(try replay.step(localPlayerID: "z-host"), frame)
                expected.step(host, opponent: guest)
                XCTAssertEqual(sim.game, expected)
                XCTAssertEqual(sim, replay)
            }
        }
    }

    func testHostOnlyLifecycleAndRejectedInputAreAtomic() throws {
        var sim = try simulation()
        let initial = sim
        let message = DuelNetworkInputs.Message(sessionID: "s", sequence: 1, tick: 0, move: 1)
        XCTAssertEqual(sim.receive(message, authenticatedSenderID: "a-guest", localPlayerID: "a-guest"), .rejected(.notHost))
        XCTAssertEqual(sim.receive(message, authenticatedSenderID: "unknown", localPlayerID: "z-host"), .rejected(.unknownPlayer))
        XCTAssertThrowsError(try sim.step(localPlayerID: "a-guest"))
        XCTAssertEqual(sim.pause(localPlayerID: "a-guest"), .rejected(.notHost))
        XCTAssertEqual(sim.resume(localPlayerID: "a-guest"), .rejected(.notHost))
        XCTAssertEqual(sim.cancel(localPlayerID: "a-guest"), .rejected(.notHost))
        XCTAssertEqual(sim.disconnect(playerID: "a-guest", localPlayerID: "a-guest"), .rejected(.notHost))
        XCTAssertEqual(sim.disconnect(playerID: "unknown", localPlayerID: "z-host"), .rejected(.unknownPlayer))
        XCTAssertEqual(sim, initial)
        XCTAssertEqual(sim.cancel(localPlayerID: "z-host"), .applied)
        let closed = sim
        XCTAssertThrowsError(try sim.step(localPlayerID: "z-host"))
        XCTAssertEqual(sim.resume(localPlayerID: "z-host"), .rejected(.inactive))
        XCTAssertEqual(sim, closed)
    }

    func testPauseClearsInboxLeasesAndGameBuffersThenRequiresNewEpoch() throws {
        var sim = try simulation()
        for player in ["z-host", "a-guest"] {
            XCTAssertEqual(sim.receive(.init(sessionID: "s", sequence: 1, tick: 0, weaponCommand: .weapon),
                                       authenticatedSenderID: player, localPlayerID: "z-host"), .applied)
        }
        try sim.step(localPlayerID: "z-host")
        // Queue another move inside each running action, plus a future inbox entry.
        for player in ["z-host", "a-guest"] {
            XCTAssertEqual(sim.receive(.init(sessionID: "s", sequence: 2, tick: 1, move: 1, weaponCommand: .heavy),
                                       authenticatedSenderID: player, localPlayerID: "z-host"), .applied)
            XCTAssertEqual(sim.receive(.init(sessionID: "s", sequence: 3, tick: 3, weaponCommand: .heavy),
                                       authenticatedSenderID: player, localPlayerID: "z-host"), .applied)
        }
        try sim.step(localPlayerID: "z-host")
        var expected = sim.game
        expected.cancelBufferedInputs()
        XCTAssertNotEqual(expected, sim.game, "Fixture must actually have queued game commands")
        XCTAssertEqual(sim.pause(localPlayerID: "z-host"), .applied)
        XCTAssertEqual(sim.game, expected)
        let paused = sim
        XCTAssertThrowsError(try sim.step(localPlayerID: "z-host"))
        XCTAssertEqual(sim, paused)
        XCTAssertEqual(sim.resume(localPlayerID: "z-host"), .applied)
        XCTAssertEqual(sim.receive(.init(sessionID: "s", sequence: 4, tick: 2, move: 1),
                                   authenticatedSenderID: "a-guest", localPlayerID: "z-host"), .rejected(.wrongEpoch))
        for _ in 0..<40 {
            let frame = try sim.step(localPlayerID: "z-host")
            XCTAssertEqual(frame.host, .neutral); XCTAssertEqual(frame.guest, .neutral)
            expected.step(.neutral, opponent: .neutral)
            XCTAssertEqual(sim.game, expected)
        }
        XCTAssertEqual(sim.receive(.init(sessionID: "s", epoch: 1, sequence: 4, tick: sim.inputs.nextTick, move: -1),
                                   authenticatedSenderID: "a-guest", localPlayerID: "z-host"), .applied)
        XCTAssertEqual(try sim.step(localPlayerID: "z-host").guest.move, -1)
        XCTAssertEqual(sim.disconnect(playerID: "a-guest", localPlayerID: "z-host"), .applied)
        XCTAssertThrowsError(try sim.step(localPlayerID: "z-host"))
    }
}
