import XCTest
@testable import ShiftCore

final class DuelNetworkStartBarrierTests: XCTestCase {
    private typealias Barrier = DuelNetworkStartBarrier
    private typealias Configuration = Barrier.Configuration
    private let hostID = "z-host", guestID = "a-guest", sessionID = "session-1"
    private var compatibility: Barrier.Compatibility {
        .init(rulesFingerprint: String(repeating: "a", count: 64),
              catalogFingerprint: String(repeating: "b", count: 64))
    }
    private func started(swapped: Bool = false) throws -> DuelMultiplayerSelection.Snapshot {
        var lobby = try DuelMultiplayerSelection(sessionID: sessionID, hostID: hostID, guestID: guestID)
        let commands: [(String, UInt64, DuelMultiplayerSelection.Command)] = [
            (hostID, 1, .select(swapped ? .liu : .sun)),
            (guestID, 1, .select(swapped ? .sun : .liu)),
            (hostID, 2, .ready(true, selectionRevision: 2)),
            (guestID, 2, .ready(true, selectionRevision: 2)),
            (hostID, 3, .start(selectionRevision: 2))
        ]
        for (sender, sequence, command) in commands {
            XCTAssertEqual(lobby.apply(.init(sessionID: sessionID, sequence: sequence, command: command),
                                       authenticatedSenderID: sender, localPlayerID: hostID), .applied)
        }
        return lobby.snapshot
    }
    private func barrier(host: Bool, swapped: Bool = false,
                         compatibility supplied: Barrier.Compatibility? = nil) throws -> Barrier {
        try Barrier(started: started(swapped: swapped), sessionID: sessionID, hostID: hostID, guestID: guestID,
                    localPlayerID: host ? hostID : guestID, compatibility: supplied ?? compatibility)
    }
    private func offered(swapped: Bool = false) throws -> (Barrier, Barrier, Configuration) {
        var host = try barrier(host: true, swapped: swapped), guest = try barrier(host: false, swapped: swapped)
        let message = try host.makeOffer(startID: "start-1", seed: 73, sequence: 1)
        XCTAssertEqual(guest.receive(try message.encoded(), authenticatedSenderID: hostID), .applied)
        return (host, guest, try XCTUnwrap(host.offeredConfiguration))
    }
    private func load(_ endpoint: inout Barrier, _ config: Configuration, sequence: UInt64) throws -> Barrier.Message {
        try endpoint.confirmLoaded(configuration: config, loadedCompatibility: compatibility,
                                   catalog: DuelWeaponTestFixtures.catalog(), sequence: sequence)
    }
    private func edit<T: Codable>(_ value: T, _ mutation: (inout [String: Any]) -> Void) throws -> T {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        mutation(&object)
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func packet(_ command: Barrier.Command, sequence: UInt64 = 2) throws -> Data {
        try Barrier.Message(sessionID: sessionID, sequence: sequence, command: command).encoded()
    }
    private func assertFailure(_ failure: Barrier.Failure, _ body: () throws -> Void,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual($0 as? Barrier.Failure, failure, file: file, line: line)
        }
    }

    func testBothSeatOrdersRequireExplicitOfferBothLoadsAndCommit() throws {
        for swapped in [false, true] {
            var (host, guest, config) = try offered(swapped: swapped)
            XCTAssertEqual(config.host.id, hostID); XCTAssertEqual(config.guest.id, guestID)
            XCTAssertEqual(config.host.seat, .host); XCTAssertEqual(config.guest.seat, .guest)
            XCTAssertEqual(config.host.choice, swapped ? .liu : .sun)
            XCTAssertEqual(config.guest.choice, swapped ? .sun : .liu)
            XCTAssertEqual(config.seed, 73); XCTAssertEqual(config.ticksPerSecond, 60)
            XCTAssertEqual(config.mode, .versus); XCTAssertEqual(config.difficulty, .learning)
            XCTAssertEqual(config.compatibility, compatibility)
            XCTAssertEqual(config.snapshotRevision, 5); XCTAssertEqual(config.selectionRevision, 2)
            XCTAssertNil(host.committedConfiguration); XCTAssertNil(guest.committedConfiguration)
            let hostLoad = try load(&host, config, sequence: 2)
            let guestLoad = try load(&guest, config, sequence: 1)
            XCTAssertEqual(host.receive(try guestLoad.encoded(), authenticatedSenderID: guestID), .applied)
            XCTAssertEqual(guest.receive(try hostLoad.encoded(), authenticatedSenderID: hostID), .applied)
            XCTAssertNil(host.committedConfiguration); XCTAssertNil(guest.committedConfiguration)
            let commit = try host.commit(sequence: 3)
            XCTAssertEqual(host.committedConfiguration, config)
            XCTAssertNil(guest.committedConfiguration, "Host commit does not prove transport delivery")
            XCTAssertEqual(guest.receive(try commit.encoded(), authenticatedSenderID: hostID), .applied)
            XCTAssertEqual(guest.committedConfiguration, config)
            XCTAssertEqual(try JSONDecoder().decode(Barrier.Message.self, from: commit.encoded()), commit)
            XCTAssertEqual(try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config)), config)
        }
    }

    func testHostCannotCommitWithZeroOrOnlyOneLoadedSeat() throws {
        for hostFirst in [false, true] {
            var (host, guest, config) = try offered()
            let initial = host
            assertFailure(.notLoaded) { _ = try host.commit(sequence: 3) }
            XCTAssertEqual(host, initial)
            if hostFirst {
                _ = try load(&host, config, sequence: 2)
            } else {
                let ack = try load(&guest, config, sequence: 1)
                XCTAssertEqual(host.receive(try ack.encoded(), authenticatedSenderID: guestID), .applied)
            }
            let oneLoaded = host
            assertFailure(.notLoaded) { _ = try host.commit(sequence: 3) }
            XCTAssertEqual(host, oneLoaded)
            XCTAssertNil(host.committedConfiguration)
        }
    }

    func testOutOfOrderCommitIsAtomicAndCanRetryAfterMissingHostLoad() throws {
        var (host, guest, config) = try offered()
        let hostLoad = try load(&host, config, sequence: 2)
        let guestLoad = try load(&guest, config, sequence: 1)
        XCTAssertEqual(host.receive(try guestLoad.encoded(), authenticatedSenderID: guestID), .applied)
        let commit = try host.commit(sequence: 3)
        let waiting = guest
        XCTAssertEqual(guest.receive(try commit.encoded(), authenticatedSenderID: hostID), .rejected(.notLoaded))
        XCTAssertEqual(guest, waiting, "Early commit must not consume its higher sequence")
        XCTAssertEqual(guest.receive(try hostLoad.encoded(), authenticatedSenderID: hostID), .applied)
        XCTAssertEqual(guest.receive(try commit.encoded(), authenticatedSenderID: hostID), .applied)
        XCTAssertEqual(guest.committedConfiguration, config)
    }

    func testRemotePacketsCannotClaimLocalLoadOrBypassLocalCatalogCheck() throws {
        var (host, guest, config) = try offered()
        let bytes = try packet(.loaded(config))
        let originalHost = host, originalGuest = guest
        XCTAssertEqual(host.receive(bytes, authenticatedSenderID: hostID), .rejected(.wrongSender))
        XCTAssertEqual(guest.receive(bytes, authenticatedSenderID: guestID), .rejected(.wrongSender))
        XCTAssertEqual(guest.receive(bytes, authenticatedSenderID: "intruder"), .rejected(.wrongSender))
        XCTAssertEqual(host, originalHost); XCTAssertEqual(guest, originalGuest)
        XCTAssertEqual(guest.receive(bytes, authenticatedSenderID: hostID), .applied)
        XCTAssertEqual(guest.receive(try packet(.commit(config), sequence: 3), authenticatedSenderID: hostID),
                       .rejected(.notLoaded))
        XCTAssertFalse(guest.guestLoaded); XCTAssertNil(guest.committedConfiguration)
    }

    func testGuestCannotOfferCommitOrImpersonateHostThroughItsAuthenticatedSender() throws {
        var (host, guest, config) = try offered()
        let originalHost = host, originalGuest = guest
        assertFailure(.notHost) { _ = try guest.makeOffer(startID: "other", seed: 9, sequence: 1) }
        assertFailure(.notHost) { _ = try guest.commit(sequence: 1) }
        XCTAssertEqual(host.receive(try packet(.offer(config), sequence: 1), authenticatedSenderID: guestID), .rejected(.notHost))
        XCTAssertEqual(host.receive(try packet(.commit(config), sequence: 1), authenticatedSenderID: guestID), .rejected(.notHost))
        XCTAssertEqual(host, originalHost); XCTAssertEqual(guest, originalGuest)
    }

    func testConstructorPinsIndependentSessionRosterAndValidatedStartedSelection() throws {
        let original = try started()
        let invalid: [(inout [String: Any]) -> Void] = [
            { $0["version"] = 99 }, { $0["sessionID"] = "other" },
            { $0["phase"] = "selecting" }, { $0["phase"] = "disconnected" },
            { $0["revision"] = 0 }, { $0["selectionRevision"] = 0 }, { $0["selectionRevision"] = 4 },
            { $0["players"] = [] },
            { var p = $0["players"] as! [[String: Any]]; p.reverse(); $0["players"] = p },
            { var p = $0["players"] as! [[String: Any]]; p[0]["id"] = "other"; $0["players"] = p },
            { var p = $0["players"] as! [[String: Any]]; p[1]["seat"] = 0; $0["players"] = p },
            { var p = $0["players"] as! [[String: Any]]; p[1]["isReady"] = false; $0["players"] = p },
            { var p = $0["players"] as! [[String: Any]]; p[0]["lastSequence"] = 2; $0["players"] = p },
            { var p = $0["players"] as! [[String: Any]]; p[1]["lastSequence"] = 1; $0["players"] = p },
            { var p = $0["players"] as! [[String: Any]]; p[1].removeValue(forKey: "choice"); $0["players"] = p },
            { var p = $0["players"] as! [[String: Any]]; p[1]["choice"] = p[0]["choice"]; $0["players"] = p },
            { var p = $0["players"] as! [[String: Any]]; p[0]["choice"] = ["hero": "gale", "weapon": "sun_katana"]; $0["players"] = p }
        ]
        for mutation in invalid {
            XCTAssertThrowsError(try Barrier(started: edit(original, mutation), sessionID: sessionID,
                                            hostID: hostID, guestID: guestID, localPlayerID: hostID,
                                            compatibility: compatibility))
        }
        assertFailure(.wrongSession) {
            _ = try Barrier(started: original, sessionID: "stale-session", hostID: hostID, guestID: guestID,
                            localPlayerID: hostID, compatibility: compatibility)
        }
        assertFailure(.invalidLocalPlayer) {
            _ = try Barrier(started: original, sessionID: sessionID, hostID: hostID, guestID: guestID,
                            localPlayerID: "intruder", compatibility: compatibility)
        }
    }

    func testIdentifierAndFingerprintBoundsRejectInvalidTrustedInputs() throws {
        for badID in ["", " \n", "bad\u{0000}id", String(repeating: "x", count: 257), String(repeating: "界", count: 86)] {
            assertFailure(.invalidSession) {
                _ = try Barrier(started: started(), sessionID: badID, hostID: hostID, guestID: guestID,
                                localPlayerID: hostID, compatibility: compatibility)
            }
            assertFailure(.invalidRoster) {
                _ = try Barrier(started: started(), sessionID: sessionID, hostID: badID, guestID: guestID,
                                localPlayerID: badID, compatibility: compatibility)
            }
            var host = try barrier(host: true)
            let before = host
            assertFailure(.invalidConfiguration) { _ = try host.makeOffer(startID: badID, seed: 0, sequence: 1) }
            XCTAssertEqual(host, before)
        }
        for badDigest in ["", String(repeating: "a", count: 63), String(repeating: "A", count: 64),
                          String(repeating: "g", count: 64), String(repeating: "a", count: 65)] {
            assertFailure(.invalidCompatibility) {
                _ = try barrier(host: true, compatibility: .init(rulesFingerprint: badDigest,
                                                                catalogFingerprint: compatibility.catalogFingerprint))
            }
        }
        for value in [Barrier.Compatibility(rulesFingerprint: compatibility.rulesFingerprint,
                                            catalogFingerprint: compatibility.catalogFingerprint, selectionProtocolVersion: 99),
                      Barrier.Compatibility(rulesFingerprint: compatibility.rulesFingerprint,
                                            catalogFingerprint: compatibility.catalogFingerprint, inputProtocolVersion: 99)] {
            assertFailure(.invalidCompatibility) { _ = try barrier(host: true, compatibility: value) }
        }
        var host = try barrier(host: true)
        _ = try host.makeOffer(startID: String(repeating: "x", count: 256), seed: UInt64.max, sequence: 1)
        XCTAssertEqual(host.offeredConfiguration?.seed, UInt64.max)
    }

    func testDifferentRulesOrCatalogFingerprintRejectsOfferWithoutLoading() throws {
        for different in [Barrier.Compatibility(rulesFingerprint: String(repeating: "c", count: 64),
                                                catalogFingerprint: compatibility.catalogFingerprint),
                          Barrier.Compatibility(rulesFingerprint: compatibility.rulesFingerprint,
                                                catalogFingerprint: String(repeating: "c", count: 64))] {
            var host = try barrier(host: true), guest = try barrier(host: false, compatibility: different)
            let message = try host.makeOffer(startID: "start-1", seed: 73, sequence: 1)
            let before = guest
            XCTAssertEqual(guest.receive(try message.encoded(), authenticatedSenderID: hostID), .rejected(.incompatible))
            XCTAssertEqual(guest, before)
        }
    }

    func testOfferMustMatchPinnedSelectionRulesAndProtocolConfiguration() throws {
        let (_, _, original) = try offered()
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["sessionID"] = "other" }, { $0["startID"] = "" },
            { $0["snapshotRevision"] = 6 }, { $0["selectionRevision"] = 3 },
            { $0["ticksPerSecond"] = 30 }, { $0["mode"] = "practice" }, { $0["difficulty"] = "challenging" },
            { let h = $0["host"]; $0["host"] = $0["guest"]; $0["guest"] = h },
            { var p = $0["host"] as! [String: Any]; p["id"] = "other"; $0["host"] = p },
            { var p = $0["guest"] as! [String: Any]; p["seat"] = 0; $0["guest"] = p },
            { var p = $0["host"] as! [String: Any]; p["choice"] = ["hero": "liu", "weapon": "liu_hammers"]; $0["host"] = p },
            { var c = $0["compatibility"] as! [String: Any]; c["selectionProtocolVersion"] = 99; $0["compatibility"] = c },
            { var c = $0["compatibility"] as! [String: Any]; c["inputProtocolVersion"] = 99; $0["compatibility"] = c }
        ]
        for mutation in mutations {
            var guest = try barrier(host: false)
            let before = guest
            XCTAssertEqual(guest.receive(try packet(.offer(edit(original, mutation)), sequence: 1),
                                         authenticatedSenderID: hostID), .rejected(.invalidConfiguration))
            XCTAssertEqual(guest, before)
            XCTAssertEqual(guest.receive(try packet(.offer(original), sequence: 1), authenticatedSenderID: hostID), .applied)
        }
    }

    func testMissingInvalidOrMismatchedLocalLoadNeverConsumesSequence() throws {
        var (host, _, config) = try offered()
        let before = host
        assertFailure(.missingCatalog) {
            _ = try host.confirmLoaded(configuration: config, loadedCompatibility: compatibility, catalog: nil, sequence: 2)
        }
        let invalid = try DuelWeaponTestFixtures.changing(DuelWeaponTestFixtures.catalog()) { $0.removeLast() }
        assertFailure(.invalidCatalog) {
            _ = try host.confirmLoaded(configuration: config, loadedCompatibility: compatibility, catalog: invalid, sequence: 2)
        }
        let changedSource = Barrier.Compatibility(rulesFingerprint: compatibility.rulesFingerprint,
                                                  catalogFingerprint: String(repeating: "d", count: 64))
        assertFailure(.incompatible) {
            _ = try host.confirmLoaded(configuration: config, loadedCompatibility: changedSource,
                                       catalog: DuelWeaponTestFixtures.catalog(), sequence: 2)
        }
        let changedSeed = try edit(config) { $0["seed"] = 74 }
        assertFailure(.configurationMismatch) { _ = try load(&host, changedSeed, sequence: 2) }
        XCTAssertEqual(host, before)
        _ = try load(&host, config, sequence: 2)
        XCTAssertTrue(host.hostLoaded)
    }

    func testRemoteAcknowledgementAndCommitBindEntireExactConfiguration() throws {
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["seed"] = 74 }, { $0["startID"] = "old-start" }, { $0["sessionID"] = "old-session" },
            { $0["snapshotRevision"] = 6 }, { $0["selectionRevision"] = 3 }, { $0["ticksPerSecond"] = 30 },
            { var p = $0["host"] as! [String: Any]; p["choice"] = ["hero": "liu", "weapon": "liu_hammers"]; $0["host"] = p },
            { var c = $0["compatibility"] as! [String: Any]; c["rulesFingerprint"] = String(repeating: "c", count: 64); $0["compatibility"] = c },
            { var c = $0["compatibility"] as! [String: Any]; c["catalogFingerprint"] = String(repeating: "c", count: 64); $0["compatibility"] = c }
        ]
        for mutation in mutations {
            var (host, guest, config) = try offered()
            let wrong = try edit(config, mutation)
            let beforeHost = host, beforeGuest = guest
            XCTAssertEqual(host.receive(try packet(.loaded(wrong), sequence: 1), authenticatedSenderID: guestID),
                           .rejected(.configurationMismatch))
            XCTAssertEqual(guest.receive(try packet(.commit(wrong), sequence: 3), authenticatedSenderID: hostID),
                           .rejected(.configurationMismatch))
            XCTAssertEqual(host, beforeHost); XCTAssertEqual(guest, beforeGuest)
            XCTAssertEqual(host.receive(try packet(.loaded(config), sequence: 1), authenticatedSenderID: guestID), .applied)
        }
    }

    func testBoundedVersionedNamespacedWireAndSessionChecksAreAtomic() throws {
        var (host, _, config) = try offered()
        let cases: [(Data, Barrier.Failure)] = [
            (Data(repeating: 32, count: Barrier.maximumMessageBytes + 1), .oversized),
            (Data(repeating: 32, count: Barrier.maximumMessageBytes), .malformed),
            (Data("{}".utf8), .malformed), (Data("not JSON".utf8), .malformed),
            (try Barrier.Message(sessionID: sessionID, sequence: 1, command: .loaded(config), version: 99).encoded(), .unsupportedVersion),
            (try Barrier.Message(sessionID: sessionID, sequence: 1, command: .loaded(config), namespace: "arena").encoded(), .wrongNamespace),
            (try Barrier.Message(sessionID: "old-session", sequence: 1, command: .loaded(config)).encoded(), .wrongSession),
            (try packet(.loaded(config), sequence: 0), .invalidSequence)
        ]
        for (data, failure) in cases {
            let before = host
            XCTAssertEqual(host.receive(data, authenticatedSenderID: guestID), .rejected(failure))
            XCTAssertEqual(host, before)
        }
        XCTAssertEqual(host.receive(try packet(.loaded(config), sequence: 1), authenticatedSenderID: guestID), .applied)
        let oversized = Barrier.Message(sessionID: String(repeating: "x", count: Barrier.maximumMessageBytes),
                                        sequence: 1, command: .cancel)
        assertFailure(.oversized) { _ = try oversized.encoded() }
    }

    func testDuplicatesNewerRepeatedCommandsAndSecondOfferNeverRestartBarrier() throws {
        var (host, guest, config) = try offered()
        let offerReplay = try packet(.offer(config), sequence: 1)
        XCTAssertEqual(guest.receive(offerReplay, authenticatedSenderID: hostID), .ignoredStaleSequence)
        let hostLoad = try load(&host, config, sequence: 2)
        let guestLoad = try load(&guest, config, sequence: 1)
        XCTAssertEqual(host.receive(try guestLoad.encoded(), authenticatedSenderID: guestID), .applied)
        XCTAssertEqual(guest.receive(try hostLoad.encoded(), authenticatedSenderID: hostID), .applied)
        let hostBefore = host, guestBefore = guest
        XCTAssertEqual(host.receive(try guestLoad.encoded(), authenticatedSenderID: guestID), .ignoredStaleSequence)
        XCTAssertEqual(host.receive(try packet(.loaded(config), sequence: 2), authenticatedSenderID: guestID), .rejected(.alreadyLoaded))
        assertFailure(.alreadyLoaded) { _ = try load(&host, config, sequence: 3) }
        assertFailure(.alreadyOffered) { _ = try host.makeOffer(startID: "start-2", seed: 9, sequence: 3) }
        XCTAssertEqual(host, hostBefore); XCTAssertEqual(guest, guestBefore)
        let commit = try host.commit(sequence: 3)
        XCTAssertEqual(guest.receive(try commit.encoded(), authenticatedSenderID: hostID), .applied)
        let committed = guest
        XCTAssertEqual(guest.receive(try commit.encoded(), authenticatedSenderID: hostID), .ignoredStaleSequence)
        XCTAssertEqual(guest.receive(try packet(.commit(config), sequence: 4), authenticatedSenderID: hostID), .rejected(.closed))
        XCTAssertEqual(guest, committed)
    }

    func testSequenceGapsAndUInt64MaximumDoNotOverflowOrPreventLocalShutdown() throws {
        var (host, guest, config) = try offered()
        let guestLoad = try load(&guest, config, sequence: UInt64.max)
        XCTAssertEqual(host.receive(try guestLoad.encoded(), authenticatedSenderID: guestID), .applied)
        let before = host
        XCTAssertEqual(host.receive(try packet(.loaded(config), sequence: UInt64.max - 1), authenticatedSenderID: guestID),
                       .ignoredStaleSequence)
        XCTAssertEqual(host, before)
        XCTAssertEqual(guest.cancel(), .applied)
        XCTAssertEqual(host.disconnect(playerID: guestID), .applied)
        var exhausted = try barrier(host: true)
        _ = try exhausted.makeOffer(startID: "start-max", seed: 0, sequence: UInt64.max)
        let offered = exhausted
        assertFailure(.invalidSequence) { _ = try exhausted.makeCancellation(sequence: UInt64.max) }
        XCTAssertEqual(exhausted, offered)
        XCTAssertEqual(exhausted.cancel(), .applied)
        XCTAssertEqual(exhausted.phase, .closed)
    }

    func testCancelDisconnectAndWireCancellationAreTerminalAtEveryStage() throws {
        for stage in 0...3 {
            var host = try barrier(host: true), guest = try barrier(host: false)
            var hostSequence: UInt64 = 1
            if stage > 0 {
                let offer = try host.makeOffer(startID: "start-1", seed: 73, sequence: 1)
                XCTAssertEqual(guest.receive(try offer.encoded(), authenticatedSenderID: hostID), .applied)
                hostSequence = 2
            }
            if stage > 1 {
                let config = try XCTUnwrap(host.offeredConfiguration)
                let a = try load(&host, config, sequence: 2), b = try load(&guest, config, sequence: 1)
                XCTAssertEqual(host.receive(try b.encoded(), authenticatedSenderID: guestID), .applied)
                XCTAssertEqual(guest.receive(try a.encoded(), authenticatedSenderID: hostID), .applied)
                hostSequence = 3
            }
            if stage > 2 {
                let commit = try host.commit(sequence: 3)
                XCTAssertEqual(guest.receive(try commit.encoded(), authenticatedSenderID: hostID), .applied)
                hostSequence = 4
            }
            // Trusted local shutdown also works in every phase and on either
            // endpoint, independently of a deliverable cancellation message.
            for endpoint in [host, guest] {
                for disconnectedID in [hostID, guestID] {
                    var disconnected = endpoint
                    XCTAssertEqual(disconnected.disconnect(playerID: disconnectedID), .applied)
                    XCTAssertEqual(disconnected.phase, .closed)
                    XCTAssertNil(disconnected.committedConfiguration)
                    XCTAssertNil(disconnected.offeredConfiguration)
                    XCTAssertFalse(disconnected.hostLoaded); XCTAssertFalse(disconnected.guestLoaded)
                }
                var cancelled = endpoint
                XCTAssertEqual(cancelled.cancel(), .applied)
                XCTAssertNil(cancelled.committedConfiguration)
                XCTAssertNil(cancelled.offeredConfiguration)
                XCTAssertEqual(cancelled.phase, .closed)
            }
            let before = guest
            XCTAssertEqual(guest.disconnect(playerID: "intruder"), .rejected(.wrongSender))
            XCTAssertEqual(guest, before)
            let cancel = try host.makeCancellation(sequence: hostSequence)
            XCTAssertEqual(guest.receive(try cancel.encoded(), authenticatedSenderID: hostID), .applied)
            for endpoint in [host, guest] {
                XCTAssertEqual(endpoint.phase, .closed)
                XCTAssertNil(endpoint.offeredConfiguration); XCTAssertNil(endpoint.committedConfiguration)
                XCTAssertFalse(endpoint.hostLoaded); XCTAssertFalse(endpoint.guestLoaded)
            }
            let closed = guest
            XCTAssertEqual(guest.receive(try cancel.encoded(), authenticatedSenderID: hostID), .rejected(.closed))
            XCTAssertEqual(guest.cancel(), .rejected(.closed)); XCTAssertEqual(guest, closed)
            assertFailure(.closed) { _ = try host.makeOffer(startID: "start-new", seed: 2, sequence: hostSequence + 1) }
        }
        for localHost in [true, false] {
            for disconnectedID in [hostID, guestID] {
                var endpoint = try barrier(host: localHost)
                XCTAssertEqual(endpoint.disconnect(playerID: disconnectedID), .applied)
                XCTAssertEqual(endpoint.phase, .closed)
            }
        }
    }

    func testGuestCancellationClosesHostAndNewSessionRejectsOldPackets() throws {
        var (host, guest, config) = try offered()
        let cancellation = try guest.makeCancellation(sequence: 1)
        XCTAssertEqual(host.receive(try cancellation.encoded(), authenticatedSenderID: guestID), .applied)
        let newSnapshot = try edit(try started()) { $0["sessionID"] = "session-2" }
        var next = try Barrier(started: newSnapshot, sessionID: "session-2", hostID: hostID, guestID: guestID,
                               localPlayerID: guestID, compatibility: compatibility)
        let fresh = next
        for command in [Barrier.Command.offer(config), .loaded(config), .commit(config), .cancel] {
            XCTAssertEqual(next.receive(try packet(command), authenticatedSenderID: hostID), .rejected(.wrongSession))
            XCTAssertEqual(next, fresh)
        }
    }

    func testLoadingOrCommitBeforeOfferNeverConsumesSequence() throws {
        let (_, _, config) = try offered()
        var guest = try barrier(host: false)
        let before = guest
        XCTAssertEqual(guest.receive(try packet(.loaded(config)), authenticatedSenderID: hostID), .rejected(.noOffer))
        XCTAssertEqual(guest.receive(try packet(.commit(config), sequence: 3), authenticatedSenderID: hostID), .rejected(.noOffer))
        assertFailure(.noOffer) { _ = try load(&guest, config, sequence: 1) }
        XCTAssertEqual(guest, before)
        XCTAssertEqual(guest.receive(try packet(.offer(config), sequence: 1), authenticatedSenderID: hostID), .applied)
    }
}
