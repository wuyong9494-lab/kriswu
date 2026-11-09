import XCTest
@testable import ShiftCore

final class DuelMultiplayerReplicaTests: XCTestCase {
    private typealias Lobby = DuelMultiplayerSelection
    private typealias Replica = DuelMultiplayerReplica
    private func host() throws -> Lobby { try Lobby(sessionID: "s", hostID: "h", guestID: "g") }
    private func replica() throws -> Replica { try Replica(sessionID: "s", hostID: "h", guestID: "g") }
    private func bytes(_ lobby: Lobby, edit: ((inout [String: Any]) -> Void)? = nil) throws -> Data {
        let encoded = try JSONEncoder().encode(lobby.snapshot)
        guard let edit else { return encoded }
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        edit(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }
    private func send(_ lobby: inout Lobby, _ command: Lobby.Command, player: String, sequence: UInt64) {
        XCTAssertEqual(lobby.apply(.init(sessionID: "s", sequence: sequence, command: command),
                                   authenticatedSenderID: player, localPlayerID: "h"), .applied)
    }
    private func prepare(_ lobby: inout Lobby) {
        send(&lobby, .select(.sun), player: "h", sequence: 1)
        send(&lobby, .select(.liu), player: "g", sequence: 1)
        let revision = lobby.snapshot.selectionRevision
        send(&lobby, .ready(true, selectionRevision: revision), player: "h", sequence: 2)
        send(&lobby, .ready(true, selectionRevision: revision), player: "g", sequence: 2)
    }

    func testLegalSelectionStartDisconnectAndDuplicateFlow() throws {
        var host = try host(), guest = try replica()
        XCTAssertEqual(guest.receive(try bytes(host), authenticatedSenderID: "h"), .applied)
        let initial = try bytes(host)
        prepare(&host)
        XCTAssertEqual(guest.receive(try bytes(host), authenticatedSenderID: "h"), .applied)
        XCTAssertEqual(guest.receive(initial, authenticatedSenderID: "h"), .ignoredStaleRevision)
        let revision = host.snapshot.selectionRevision
        send(&host, .start(selectionRevision: revision), player: "h", sequence: 3)
        XCTAssertEqual(guest.receive(try bytes(host), authenticatedSenderID: "h"), .applied)
        XCTAssertEqual(guest.receive(try bytes(host), authenticatedSenderID: "h"), .ignoredStaleRevision)
        XCTAssertEqual(host.disconnect(playerID: "g", localPlayerID: "h"), .applied)
        XCTAssertEqual(guest.receive(try bytes(host), authenticatedSenderID: "h"), .applied)
        XCTAssertEqual(guest.snapshot, host.snapshot)
    }

    func testRejectsWrongSenderVersionSessionAndMalformedOrOversizedBytes() throws {
        var guest = try replica()
        let host = try host()
        XCTAssertEqual(guest.receive(try bytes(host), authenticatedSenderID: "g"), .rejected(.wrongHost))
        XCTAssertEqual(guest.receive(try bytes(host) { $0["version"] = 2 }, authenticatedSenderID: "h"), .rejected(.unsupportedVersion))
        XCTAssertEqual(guest.receive(try bytes(host) { $0["sessionID"] = "other" }, authenticatedSenderID: "h"), .rejected(.wrongSession))
        XCTAssertEqual(guest.receive(Data("not json".utf8), authenticatedSenderID: "h"), .rejected(.malformed))
        XCTAssertEqual(guest.receive(Data(repeating: 0, count: Replica.maximumSnapshotBytes + 1), authenticatedSenderID: "h"), .rejected(.oversized))
        XCTAssertNil(guest.snapshot)
    }

    func testRejectsWrongRosterSeatsInvalidChoiceAndReadyWithoutChoices() throws {
        let host = try host()
        let mutations: [([String: Any]) -> [String: Any]] = [
            { player in var p = player; p["id"] = "impostor"; return p },
            { player in var p = player; p["seat"] = 1; return p },
            { player in var p = player; p["choice"] = ["hero": "ember", "weapon": "liu_hammers"]; return p },
            { player in var p = player; p["isReady"] = true; return p }
        ]
        for (index, mutation) in mutations.enumerated() {
            var guest = try replica()
            let data = try bytes(host) {
                var players = $0["players"] as! [[String: Any]]
                players[0] = mutation(players[0]); $0["players"] = players
            }
            XCTAssertEqual(guest.receive(data, authenticatedSenderID: "h"),
                           .rejected(index < 2 ? .invalidRoster : .invalidState))
            XCTAssertNil(guest.snapshot)
        }
        var guest = try replica()
        XCTAssertEqual(guest.receive(try bytes(host) { $0["players"] = [] }, authenticatedSenderID: "h"), .rejected(.invalidRoster))
        XCTAssertEqual(guest.receive(try bytes(host) { $0["selectionRevision"] = 1 }, authenticatedSenderID: "h"), .rejected(.invalidState))
    }

    func testRejectsStartAsFirstSnapshotAndPhaseRollbackAfterStart() throws {
        var host = try host(), guest = try replica()
        prepare(&host)
        let selecting = try bytes(host)
        let revision = host.snapshot.selectionRevision
        send(&host, .start(selectionRevision: revision), player: "h", sequence: 3)
        XCTAssertEqual(guest.receive(try bytes(host), authenticatedSenderID: "h"), .rejected(.invalidTransition))
        XCTAssertEqual(guest.receive(selecting, authenticatedSenderID: "h"), .applied)
        XCTAssertEqual(guest.receive(try bytes(host), authenticatedSenderID: "h"), .applied)
        let started = guest
        XCTAssertEqual(guest.receive(try bytes(host) { $0["phase"] = "selecting"; $0["revision"] = 99 }, authenticatedSenderID: "h"), .rejected(.invalidTransition))
        XCTAssertEqual(guest, started)
    }

    func testRejectsChoiceChangeWithoutRevisionAndReadinessWithoutNewCommand() throws {
        var host = try host(), guest = try replica()
        prepare(&host)
        XCTAssertEqual(guest.receive(try bytes(host), authenticatedSenderID: "h"), .applied)
        let before = guest
        let data = try bytes(host) {
            $0["revision"] = 20
            var players = $0["players"] as! [[String: Any]]
            players[0]["choice"] = ["hero": "liu", "weapon": "liu_hammers"]
            players[0]["lastSequence"] = 3
            players[0]["isReady"] = false
            players[1]["isReady"] = false
            $0["players"] = players
        }
        XCTAssertEqual(guest.receive(data, authenticatedSenderID: "h"), .rejected(.invalidTransition))
        XCTAssertEqual(guest.receive(try bytes(host) { $0["revision"] = 20; $0["selectionRevision"] = 3 }, authenticatedSenderID: "h"), .rejected(.invalidTransition))
        XCTAssertEqual(guest, before)
    }

    func testRejectsSequenceAndSelectionRevisionRollbackAndTerminalReopen() throws {
        var host = try host(), guest = try replica()
        prepare(&host)
        XCTAssertEqual(guest.receive(try bytes(host), authenticatedSenderID: "h"), .applied)
        let before = guest
        XCTAssertEqual(guest.receive(try bytes(host) {
            $0["revision"] = 20; $0["selectionRevision"] = 1
        }, authenticatedSenderID: "h"), .rejected(.invalidTransition))
        XCTAssertEqual(guest.receive(try bytes(host) {
            $0["revision"] = 20
            var players = $0["players"] as! [[String: Any]]
            players[0]["lastSequence"] = 1; $0["players"] = players
        }, authenticatedSenderID: "h"), .rejected(.invalidTransition))
        XCTAssertEqual(guest, before)
        XCTAssertEqual(host.disconnect(playerID: "g", localPlayerID: "h"), .applied)
        XCTAssertEqual(guest.receive(try bytes(host), authenticatedSenderID: "h"), .applied)
        XCTAssertEqual(guest.receive(try bytes(host) {
            $0["revision"] = 21; $0["phase"] = "selecting"
        }, authenticatedSenderID: "h"), .rejected(.invalidTransition))
    }

    func testStartRequiresANewerHostCommandNotJustANewerSnapshot() throws {
        var host = try host(), guest = try replica()
        prepare(&host)
        XCTAssertEqual(guest.receive(try bytes(host), authenticatedSenderID: "h"), .applied)
        let before = guest
        let forgedStart = try bytes(host) {
            $0["revision"] = 20
            $0["phase"] = "started"
            var players = $0["players"] as! [[String: Any]]
            players[1]["lastSequence"] = 99
            $0["players"] = players
        }
        XCTAssertEqual(guest.receive(forgedStart, authenticatedSenderID: "h"), .rejected(.invalidTransition))
        XCTAssertEqual(guest, before)
        let revision = host.snapshot.selectionRevision
        send(&host, .start(selectionRevision: revision), player: "h", sequence: 3)
        XCTAssertEqual(guest.receive(try bytes(host), authenticatedSenderID: "h"), .applied)
    }

    func testEstablishedChoiceCannotBeClearedBeforeDisconnect() throws {
        for clearedSeat in 0...1 {
            var host = try host(), guest = try replica()
            prepare(&host)
            XCTAssertEqual(guest.receive(try bytes(host), authenticatedSenderID: "h"), .applied)
            let before = guest
            let forgedDeselect = try bytes(host) {
                $0["revision"] = 20
                $0["selectionRevision"] = 3
                var players = $0["players"] as! [[String: Any]]
                players[clearedSeat].removeValue(forKey: "choice")
                players[0]["isReady"] = false
                players[1]["isReady"] = false
                players[0]["lastSequence"] = 3
                players[1]["lastSequence"] = 3
                $0["players"] = players
            }
            XCTAssertEqual(guest.receive(forgedDeselect, authenticatedSenderID: "h"), .rejected(.invalidTransition))
            XCTAssertEqual(guest, before)
            XCTAssertEqual(host.disconnect(playerID: "g", localPlayerID: "h"), .applied)
            XCTAssertEqual(guest.receive(try bytes(host), authenticatedSenderID: "h"), .applied)
        }
    }

    func testAcceptsSelectionChangeAndFreshReadyEvenWhenSnapshotsAreSkipped() throws {
        var host = try host(), guest = try replica()
        prepare(&host)
        XCTAssertEqual(guest.receive(try bytes(host), authenticatedSenderID: "h"), .applied)
        send(&host, .select(.liu), player: "h", sequence: 3)
        send(&host, .select(.sun), player: "g", sequence: 3)
        let revision = host.snapshot.selectionRevision
        send(&host, .ready(true, selectionRevision: revision), player: "h", sequence: 4)
        send(&host, .ready(true, selectionRevision: revision), player: "g", sequence: 4)
        XCTAssertEqual(guest.receive(try bytes(host), authenticatedSenderID: "h"), .applied)
        XCTAssertEqual(guest.snapshot, host.snapshot)
    }
    func testConflictMayBeShownButNeverReadyOrStarted() throws {
        var host = try host(), guest = try replica()
        send(&host, .select(.sun), player: "h", sequence: 1)
        send(&host, .select(.sun), player: "g", sequence: 1)
        XCTAssertEqual(guest.receive(try bytes(host), authenticatedSenderID: "h"), .applied)
        let before = guest
        for phase in ["selecting", "started"] {
            let forged = try bytes(host) {
                $0["revision"] = 10; $0["phase"] = phase
                var players = $0["players"] as! [[String: Any]]
                for i in players.indices { players[i]["isReady"] = true; players[i]["lastSequence"] = 3 }
                $0["players"] = players
            }
            XCTAssertEqual(guest.receive(forged, authenticatedSenderID: "h"), .rejected(.invalidState))
            XCTAssertEqual(guest, before)
        }
    }

}
