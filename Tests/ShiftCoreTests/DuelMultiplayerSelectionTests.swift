import XCTest
@testable import ShiftCore

final class DuelMultiplayerSelectionTests: XCTestCase {
    private typealias Lobby = DuelMultiplayerSelection
    private func lobby() throws -> Lobby {
        try Lobby(sessionID: "session-one", hostID: "z-host", guestID: "a-guest")
    }
    @discardableResult
    private func send(_ command: Lobby.Command, to lobby: inout Lobby,
                      sender: String = "z-host", sequence: UInt64,
                      local: String = "z-host", session: String = "session-one",
                      version: Int = Lobby.protocolVersion) -> Lobby.Outcome {
        lobby.apply(.init(sessionID: session, sequence: sequence, command: command, version: version),
                    authenticatedSenderID: sender, localPlayerID: local)
    }
    private func chooseBoth(_ lobby: inout Lobby) {
        XCTAssertEqual(send(.select(.sun), to: &lobby, sequence: 1), .applied)
        XCTAssertEqual(send(.select(.liu), to: &lobby, sender: "a-guest", sequence: 1), .applied)
    }
    private func readyBoth(_ lobby: inout Lobby) {
        let revision = lobby.snapshot.selectionRevision
        XCTAssertEqual(send(.ready(true, selectionRevision: revision), to: &lobby, sequence: 2), .applied)
        XCTAssertEqual(send(.ready(true, selectionRevision: revision), to: &lobby,
                            sender: "a-guest", sequence: 2), .applied)
    }

    func testRosterValidationAndStableSeats() throws {
        let lobby = try lobby()
        XCTAssertEqual(lobby.snapshot.players.map(\.id), ["z-host", "a-guest"])
        XCTAssertEqual(lobby.snapshot.players.map(\.seat), [.host, .guest])
        XCTAssertFalse(lobby.snapshot.canStart)
        XCTAssertThrowsError(try Lobby(sessionID: "", hostID: "h", guestID: "g"))
        XCTAssertThrowsError(try Lobby(sessionID: "s", hostID: "same", guestID: "same"))
        XCTAssertThrowsError(try Lobby(sessionID: "s", hostID: " ", guestID: "g"))
    }

    func testOnlyExactHeroWeaponPairsAreAccepted() throws {
        for hero in DuelGame.Hero.allCases {
            for weapon in [Lobby.Weapon.katana, .hammers] {
                var lobby = try lobby()
                let choice = Lobby.Choice(hero: hero, weapon: weapon)
                let expected: Lobby.Outcome = choice.isValid ? .applied : .rejected(.invalidChoice)
                XCTAssertEqual(send(.select(choice), to: &lobby, sequence: 1), expected)
                XCTAssertEqual(lobby.snapshot.players[0].choice, choice.isValid ? choice : nil)
            }
        }
    }

    func testVersionSessionSenderAndHostValidationAreAtomic() throws {
        var lobby = try lobby()
        let initial = lobby
        XCTAssertEqual(send(.select(.sun), to: &lobby, sequence: 1, version: 99), .rejected(.unsupportedVersion))
        XCTAssertEqual(send(.select(.sun), to: &lobby, sequence: 1, session: "old"), .rejected(.wrongSession))
        XCTAssertEqual(send(.select(.sun), to: &lobby, sender: "stranger", sequence: 1), .rejected(.unknownPlayer))
        XCTAssertEqual(send(.select(.sun), to: &lobby, sequence: 1, local: "a-guest"), .rejected(.notHost))
        XCTAssertEqual(send(.select(.sun), to: &lobby, sequence: 0), .rejected(.invalidSequence))
        XCTAssertEqual(lobby, initial)
    }

    func testDuplicateAndOutOfOrderSelectionCannotRollBackState() throws {
        var lobby = try lobby()
        XCTAssertEqual(send(.select(.sun), to: &lobby, sequence: 2), .applied)
        let accepted = lobby
        XCTAssertEqual(send(.select(.liu), to: &lobby, sequence: 1), .ignoredStaleSequence)
        XCTAssertEqual(send(.select(.liu), to: &lobby, sequence: 2), .ignoredStaleSequence)
        XCTAssertEqual(lobby, accepted)
        XCTAssertEqual(send(.select(.liu), to: &lobby, sequence: 3), .applied)
    }

    func testSelectionChangeClearsBothReadyFlagsAndRejectsOldReady() throws {
        var lobby = try lobby()
        chooseBoth(&lobby)
        readyBoth(&lobby)
        let oldRevision = lobby.snapshot.selectionRevision
        XCTAssertTrue(lobby.snapshot.canStart)
        XCTAssertEqual(send(.select(.liu), to: &lobby, sequence: 3), .applied)
        XCTAssertEqual(lobby.snapshot.selectionRevision, oldRevision + 1)
        XCTAssertTrue(lobby.snapshot.players.allSatisfy { !$0.isReady })
        let changed = lobby
        XCTAssertEqual(send(.ready(true, selectionRevision: oldRevision), to: &lobby,
                            sender: "a-guest", sequence: 3), .rejected(.staleSelection))
        XCTAssertEqual(lobby, changed)
        XCTAssertEqual(send(.ready(true, selectionRevision: oldRevision + 1), to: &lobby,
                            sender: "a-guest", sequence: 3), .rejected(.conflictingChoices))
        XCTAssertEqual(lobby, changed)
        XCTAssertEqual(send(.start(selectionRevision: oldRevision + 1), to: &lobby, sequence: 4),
                       .rejected(.conflictingChoices))
        XCTAssertFalse(lobby.snapshot.canStart)
        XCTAssertEqual(send(.ready(false, selectionRevision: oldRevision + 1), to: &lobby, sequence: 4), .applied)
        XCTAssertEqual(send(.select(.sun), to: &lobby, sender: "a-guest", sequence: 3), .applied)
        let resolvedRevision = lobby.snapshot.selectionRevision
        XCTAssertEqual(send(.ready(true, selectionRevision: resolvedRevision), to: &lobby, sequence: 5), .applied)
        XCTAssertEqual(send(.ready(true, selectionRevision: resolvedRevision), to: &lobby, sender: "a-guest", sequence: 4), .applied)
        XCTAssertTrue(lobby.snapshot.canStart)
    }

    func testReselectingSameChoiceDoesNotInvalidateReadiness() throws {
        var lobby = try lobby()
        chooseBoth(&lobby)
        readyBoth(&lobby)
        let revision = lobby.snapshot.selectionRevision
        XCTAssertEqual(send(.select(.sun), to: &lobby, sequence: 3), .applied)
        XCTAssertEqual(lobby.snapshot.selectionRevision, revision)
        XCTAssertTrue(lobby.snapshot.canStart)
    }

    func testReadyBeforeSelectionOrForFutureRevisionIsRejected() throws {
        var lobby = try lobby()
        XCTAssertEqual(send(.ready(true, selectionRevision: 0), to: &lobby, sequence: 1), .rejected(.missingSelection))
        chooseBoth(&lobby)
        let revision = lobby.snapshot.selectionRevision
        XCTAssertEqual(send(.ready(true, selectionRevision: revision + 1), to: &lobby,
                            sequence: 5), .rejected(.staleSelection))
        // Invalid high sequence did not poison the stream.
        XCTAssertEqual(send(.ready(true, selectionRevision: revision), to: &lobby, sequence: 2), .applied)
    }

    func testUnreadyAndReorderedReadyCannotStartMatch() throws {
        var lobby = try lobby()
        chooseBoth(&lobby)
        readyBoth(&lobby)
        let revision = lobby.snapshot.selectionRevision
        XCTAssertEqual(send(.ready(false, selectionRevision: revision), to: &lobby,
                            sender: "a-guest", sequence: 4), .applied)
        XCTAssertEqual(send(.ready(true, selectionRevision: revision), to: &lobby,
                            sender: "a-guest", sequence: 3), .ignoredStaleSequence)
        XCTAssertEqual(send(.start(selectionRevision: revision), to: &lobby, sequence: 3), .rejected(.notReady))
    }

    func testOnlyHostStartsOnceWithCurrentReadySelections() throws {
        var lobby = try lobby()
        chooseBoth(&lobby)
        let revision = lobby.snapshot.selectionRevision
        XCTAssertEqual(send(.start(selectionRevision: revision), to: &lobby, sequence: 2), .rejected(.notReady))
        readyBoth(&lobby)
        XCTAssertEqual(send(.start(selectionRevision: revision), to: &lobby,
                            sender: "a-guest", sequence: 3), .rejected(.notHost))
        XCTAssertEqual(send(.start(selectionRevision: revision - 1), to: &lobby, sequence: 3), .rejected(.staleSelection))
        XCTAssertEqual(send(.start(selectionRevision: revision), to: &lobby, sequence: 3), .applied)
        XCTAssertEqual(lobby.snapshot.phase, .started)
        XCTAssertFalse(lobby.snapshot.canStart)
        let started = lobby
        XCTAssertEqual(send(.start(selectionRevision: revision), to: &lobby, sequence: 3), .ignoredStaleSequence)
        XCTAssertEqual(send(.select(.liu), to: &lobby, sequence: 4), .rejected(.closed))
        XCTAssertEqual(lobby, started)
    }

    func testDisconnectClearsSelectionsAndReadyAndRequiresFreshSession() throws {
        for departed in ["z-host", "a-guest"] {
            var lobby = try lobby()
            chooseBoth(&lobby)
            readyBoth(&lobby)
            XCTAssertEqual(lobby.disconnect(playerID: departed, localPlayerID: "z-host"), .applied)
            XCTAssertEqual(lobby.snapshot.phase, .disconnected)
            XCTAssertTrue(lobby.snapshot.players.allSatisfy { $0.choice == nil && !$0.isReady })
            XCTAssertEqual(send(.select(.sun), to: &lobby, sequence: 3), .rejected(.closed))
            var fresh = try Lobby(sessionID: "fresh", hostID: "z-host", guestID: "a-guest")
            XCTAssertEqual(send(.select(.sun), to: &fresh, sequence: 3), .rejected(.wrongSession))
            XCTAssertEqual(send(.select(.sun), to: &fresh, sequence: 1, session: "fresh"), .applied)
        }
    }

    func testDisconnectAuthorityAndStartedReset() throws {
        var lobby = try lobby()
        let initial = lobby
        XCTAssertEqual(lobby.disconnect(playerID: "a-guest", localPlayerID: "a-guest"), .rejected(.notHost))
        XCTAssertEqual(lobby.disconnect(playerID: "stranger", localPlayerID: "z-host"), .rejected(.unknownPlayer))
        XCTAssertEqual(lobby, initial)
        chooseBoth(&lobby)
        readyBoth(&lobby)
        let revision = lobby.snapshot.selectionRevision
        XCTAssertEqual(send(.start(selectionRevision: revision), to: &lobby, sequence: 3), .applied)
        XCTAssertEqual(lobby.disconnect(playerID: "a-guest", localPlayerID: "z-host"), .applied)
        let disconnected = lobby
        XCTAssertEqual(lobby.disconnect(playerID: "a-guest", localPlayerID: "z-host"), .rejected(.closed))
        XCTAssertEqual(lobby, disconnected)
    }

    func testWireRoundTripsAndMalformedEnumIsRejected() throws {
        let commands: [Lobby.Command] = [.select(.sun), .select(.liu),
                                         .ready(true, selectionRevision: 2), .start(selectionRevision: 2)]
        for command in commands {
            let message = Lobby.Message(sessionID: "session-one", sequence: 1, command: command)
            let encoded = try JSONEncoder().encode(message)
            XCTAssertEqual(try JSONDecoder().decode(Lobby.Message.self, from: encoded), message)
        }
        var lobby = try lobby()
        chooseBoth(&lobby)
        let encoded = try JSONEncoder().encode(lobby.snapshot)
        XCTAssertEqual(try JSONDecoder().decode(Lobby.Snapshot.self, from: encoded), lobby.snapshot)
        let malformed = Data("{\"hero\":\"ember\",\"weapon\":\"laser\"}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Lobby.Choice.self, from: malformed))
    }
}
