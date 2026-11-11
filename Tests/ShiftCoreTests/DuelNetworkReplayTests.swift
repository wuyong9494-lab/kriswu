import XCTest
@testable import ShiftCore

final class DuelNetworkReplayTests: XCTestCase {
    private typealias Wire = DuelNetworkCombatProtocol
    private typealias Barrier = DuelNetworkStartBarrier
    private let hostID = "z-host", guestID = "a-guest", sessionID = "combat-session"
    private var compatibility: Barrier.Compatibility {
        .init(rulesFingerprint: String(repeating: "a", count: 64),
              catalogFingerprint: String(repeating: "b", count: 64))
    }

    private func started(swapped: Bool = false) throws -> DuelMultiplayerSelection.Snapshot {
        var selection = try DuelMultiplayerSelection(sessionID: sessionID, hostID: hostID, guestID: guestID)
        let commands: [(String, UInt64, DuelMultiplayerSelection.Command)] = [
            (hostID, 1, .select(swapped ? .liu : .sun)), (guestID, 1, .select(swapped ? .sun : .liu)),
            (hostID, 2, .ready(true, selectionRevision: 2)), (guestID, 2, .ready(true, selectionRevision: 2)),
            (hostID, 3, .start(selectionRevision: 2))
        ]
        for (sender, sequence, command) in commands {
            XCTAssertEqual(selection.apply(.init(sessionID: sessionID, sequence: sequence, command: command),
                                            authenticatedSenderID: sender, localPlayerID: hostID), .applied)
        }
        return selection.snapshot
    }

    private func barriers(swapped: Bool = false, commit: Bool = true, seed: UInt64 = 73,
                          startID: String = "start-1",
                          catalog: DuelWeaponCatalog = DuelWeaponTestFixtures.catalog()) throws -> (Barrier, Barrier) {
        let snapshot = try started(swapped: swapped)
        var host = try Barrier(started: snapshot, sessionID: sessionID, hostID: hostID, guestID: guestID,
                               localPlayerID: hostID, compatibility: compatibility)
        var guest = try Barrier(started: snapshot, sessionID: sessionID, hostID: hostID, guestID: guestID,
                                localPlayerID: guestID, compatibility: compatibility)
        let offer = try host.makeOffer(startID: startID, seed: seed, sequence: 1)
        XCTAssertEqual(guest.receive(try offer.encoded(), authenticatedSenderID: hostID), .applied)
        let configuration = try XCTUnwrap(host.offeredConfiguration)
        let hostLoaded = try host.confirmLoaded(configuration: configuration, loadedCompatibility: compatibility,
                                                catalog: catalog, sequence: 2)
        let guestLoaded = try guest.confirmLoaded(configuration: configuration, loadedCompatibility: compatibility,
                                                  catalog: catalog, sequence: 1)
        XCTAssertEqual(host.receive(try guestLoaded.encoded(), authenticatedSenderID: guestID), .applied)
        XCTAssertEqual(guest.receive(try hostLoaded.encoded(), authenticatedSenderID: hostID), .applied)
        if commit {
            let message = try host.commit(sequence: 3)
            XCTAssertEqual(guest.receive(try message.encoded(), authenticatedSenderID: hostID), .applied)
        }
        return (host, guest)
    }

    private func endpoints(swapped: Bool = false,
                           catalog: DuelWeaponCatalog = DuelWeaponTestFixtures.catalog()) throws
        -> (DuelNetworkCombatHost, DuelNetworkReplay) {
        let (host, guest) = try barriers(swapped: swapped, catalog: catalog)
        return (try DuelNetworkCombatHost(committed: host, started: started(swapped: swapped),
                                          loadedCompatibility: compatibility, catalog: catalog),
                try DuelNetworkReplay(committed: guest, loadedCompatibility: compatibility, catalog: catalog))
    }

    /// Deliberately bypasses safe outbound validation to exercise hostile bytes.
    private func raw(_ message: Wire.Message) throws -> Data { try JSONEncoder().encode(message) }

    private func packet(sequence: UInt64 = 1, ticks: [UInt64] = [0],
                        host: Wire.Input = .init(), guest: Wire.Input = .init(),
                        epoch: UInt64 = 0, startID: String = "start-1",
                        session: String? = nil) -> Wire.Message {
        .init(sessionID: session ?? sessionID, startID: startID, epoch: epoch, sequence: sequence,
              command: .frames(ticks.map { .init(tick: $0, host: host, guest: guest) }))
    }

    func testBothHeroOrdersReplayActualHostWireEveryTickWithoutAI() throws {
        for swapped in [false, true] {
            var (host, guest) = try endpoints(swapped: swapped)
            XCTAssertEqual(guest.game.fighters.map(\.hero), swapped ? [.liu, .ember] : [.ember, .liu])
            XCTAssertEqual(guest.game, host.game)
            XCTAssertNotNil(guest.game.weaponFight)
            XCTAssertEqual(try host.verificationState(), try guest.verificationState())
            var reference = host.game
            for tick in UInt64(0)..<180 {
                let hostInput = DuelGame.Input(move: tick < 18 ? 1 : 0,
                                                weaponCommand: tick >= 20 && tick % 24 == 20 ? .weapon : nil)
                let guestInput = DuelGame.Input(move: tick < 18 ? -1 : 0,
                                                 weaponCommand: tick >= 20 && tick % 30 == 20 ? .heavy : nil)
                for (sender, input) in [(hostID, hostInput), (guestID, guestInput)] {
                    XCTAssertEqual(host.receive(.init(sessionID: sessionID, sequence: tick + 1, tick: tick,
                                                       move: input.move, weaponCommand: input.weaponCommand),
                                                authenticatedSenderID: sender), .applied)
                }
                let message = try host.advance()
                XCTAssertEqual(message.sequence, tick + 1)
                XCTAssertEqual(message.command, .frames([.init(tick: tick,
                                                                host: .init(consumed: hostInput),
                                                                guest: .init(consumed: guestInput))]))
                let bytes = try message.encoded()
                XCTAssertEqual(try JSONDecoder().decode(Wire.Message.self, from: bytes), message)
                XCTAssertEqual(guest.receive(bytes, authenticatedSenderID: hostID), .applied)
                reference.step(hostInput, opponent: guestInput)
                XCTAssertEqual(guest.game, host.game, "Host/guest divergence at \(tick), swapped=\(swapped)")
                XCTAssertEqual(guest.game, reference)
                XCTAssertEqual(guest.nextTick, tick + 1)
                // These diagnostics include the complete canonical game state.
                XCTAssertEqual(try host.verificationState(), try guest.verificationState())
            }
        }
    }

    func testWireContainsConsumedLeaseAndLateInputNotOriginalRequests() throws {
        var (host, guest) = try endpoints()
        XCTAssertEqual(host.receive(.init(sessionID: sessionID, sequence: 1, tick: 0,
                                           move: 1, weaponCommand: .weapon), authenticatedSenderID: hostID), .applied)
        let first = try host.advance(frameCount: 2)
        XCTAssertEqual(first.command, .frames([
            .init(tick: 0, host: .init(move: 1, weaponCommand: .weapon), guest: .init()),
            .init(tick: 1, host: .init(move: 1), guest: .init())
        ]))
        XCTAssertEqual(guest.receive(try first.encoded(), authenticatedSenderID: hostID), .applied)
        // Two ticks late is resolved by the host to tick 2. The guest never
        // independently schedules the original request's tick 0 or lease.
        XCTAssertEqual(host.receive(.init(sessionID: sessionID, sequence: 1, tick: 0,
                                           move: -1, weaponCommand: .heavy), authenticatedSenderID: guestID), .applied)
        let second = try host.advance(frameCount: 4)
        XCTAssertEqual(second.command, .frames([
            .init(tick: 2, host: .init(move: 1), guest: .init(move: -1, weaponCommand: .heavy)),
            .init(tick: 3, host: .init(), guest: .init(move: -1)),
            .init(tick: 4, host: .init(), guest: .init(move: -1)),
            .init(tick: 5, host: .init(), guest: .init())
        ]))
        XCTAssertEqual(guest.receive(try second.encoded(), authenticatedSenderID: hostID), .applied)
        XCTAssertEqual(guest.game, host.game)
        XCTAssertEqual(try host.verificationState(), try guest.verificationState())
    }

    func testMissingGuestIsExplicitNeutralAndReplicaNeverRunsAhead() throws {
        var (host, guest) = try endpoints()
        let initial = guest
        let message = try host.advance(frameCount: 32)
        XCTAssertEqual(guest, initial, "Host advancement alone must not advance the guest")
        if case .frames(let frames) = message.command {
            XCTAssertEqual(frames.count, 32)
            XCTAssertTrue(frames.allSatisfy { $0.host == .init() && $0.guest == .init() })
        } else { XCTFail("Expected consumed frame batch") }
        XCTAssertEqual(guest.receive(try message.encoded(), authenticatedSenderID: hostID), .applied)
        XCTAssertEqual(guest.game, host.game)
        XCTAssertEqual(guest.game.fighters[1].x, 6500)
        XCTAssertEqual(guest.nextTick, 32)
    }

    func testOnlyCommittedCorrectRoleMatchingSnapshotAndCatalogCanConstruct() throws {
        let (uncommittedHost, uncommittedGuest) = try barriers(commit: false)
        XCTAssertThrowsError(try DuelNetworkReplay(committed: uncommittedGuest, loadedCompatibility: compatibility,
                                                   catalog: DuelWeaponTestFixtures.catalog())) {
            XCTAssertEqual($0 as? Wire.Failure, .notCommitted)
        }
        XCTAssertThrowsError(try DuelNetworkCombatHost(committed: uncommittedHost, started: started(),
                                                       loadedCompatibility: compatibility, catalog: DuelWeaponTestFixtures.catalog()))
        let (host, guest) = try barriers()
        XCTAssertThrowsError(try DuelNetworkReplay(committed: host, loadedCompatibility: compatibility,
                                                   catalog: DuelWeaponTestFixtures.catalog())) {
            XCTAssertEqual($0 as? Wire.Failure, .wrongRole)
        }
        XCTAssertThrowsError(try DuelNetworkCombatHost(committed: guest, started: started(),
                                                       loadedCompatibility: compatibility, catalog: DuelWeaponTestFixtures.catalog()))
        XCTAssertThrowsError(try DuelNetworkCombatHost(committed: host, started: started(swapped: true),
                                                       loadedCompatibility: compatibility, catalog: DuelWeaponTestFixtures.catalog())) {
            XCTAssertEqual($0 as? Wire.Failure, .configurationMismatch)
        }
        XCTAssertThrowsError(try DuelNetworkReplay(committed: guest, loadedCompatibility: compatibility, catalog: nil)) {
            XCTAssertEqual($0 as? Wire.Failure, .missingCatalog)
        }
        let invalid = try DuelWeaponTestFixtures.changing(DuelWeaponTestFixtures.catalog()) { $0.removeLast() }
        XCTAssertThrowsError(try DuelNetworkReplay(committed: guest, loadedCompatibility: compatibility, catalog: invalid)) {
            XCTAssertEqual($0 as? Wire.Failure, .invalidCatalog)
        }
        let other = Barrier.Compatibility(rulesFingerprint: String(repeating: "c", count: 64),
                                          catalogFingerprint: compatibility.catalogFingerprint)
        XCTAssertThrowsError(try DuelNetworkReplay(committed: guest, loadedCompatibility: other,
                                                   catalog: DuelWeaponTestFixtures.catalog())) {
            XCTAssertEqual($0 as? Wire.Failure, .incompatible)
        }
        var closed = guest
        _ = closed.cancel()
        XCTAssertThrowsError(try DuelNetworkReplay(committed: closed, loadedCompatibility: compatibility,
                                                   catalog: DuelWeaponTestFixtures.catalog()))
    }

    func testSequenceGapRetryDuplicatesConflictsAndOldReplayAreAtomic() throws {
        var (host, guest) = try endpoints()
        let one = try host.advance(frameCount: 2), two = try host.advance(frameCount: 3)
        let initial = guest
        XCTAssertEqual(guest.receive(try two.encoded(), authenticatedSenderID: hostID), .rejected(.sequenceGap))
        XCTAssertEqual(guest, initial)
        XCTAssertEqual(guest.receive(try one.encoded(), authenticatedSenderID: hostID), .applied)
        let afterOne = guest
        XCTAssertEqual(guest.receive(try one.encoded(), authenticatedSenderID: hostID), .ignoredDuplicate)
        XCTAssertEqual(guest, afterOne)
        let conflict = packet(sequence: 1, ticks: [0, 1], host: .init(move: -1))
        XCTAssertEqual(guest.receive(try conflict.encoded(), authenticatedSenderID: hostID), .rejected(.conflictingDuplicate))
        XCTAssertEqual(guest, afterOne)
        XCTAssertEqual(guest.receive(try two.encoded(), authenticatedSenderID: hostID), .applied)
        XCTAssertEqual(guest.game, host.game)
        let afterTwo = guest
        XCTAssertEqual(guest.receive(try one.encoded(), authenticatedSenderID: hostID), .rejected(.staleSequence))
        XCTAssertEqual(guest, afterTwo)
    }

    func testTickGapsOverlapInternalGapsAndInvalidFinalFrameRejectWholeBatch() throws {
        var (_, guest) = try endpoints()
        let initial = guest
        let bad: [(Wire.Message, Wire.Failure)] = [
            (packet(ticks: [1, 2]), .tickGap), (packet(ticks: [0, 2]), .noncontiguousTicks),
            (packet(ticks: [0, 0]), .noncontiguousTicks), (packet(ticks: [1, 0]), .noncontiguousTicks),
            (.init(sessionID: sessionID, startID: "start-1", sequence: 1, command: .frames([
                .init(tick: 0, host: .init(move: 1), guest: .init()),
                .init(tick: 1, host: .init(), guest: .init(move: 99))
            ])), .invalidInput)
        ]
        for (message, failure) in bad {
            XCTAssertEqual(guest.receive(try raw(message), authenticatedSenderID: hostID), .rejected(failure))
            XCTAssertEqual(guest, initial)
        }
        XCTAssertEqual(guest.receive(try packet(ticks: [0, 1]).encoded(), authenticatedSenderID: hostID), .applied)
        let after = guest
        XCTAssertEqual(guest.receive(try packet(sequence: 2, ticks: [1, 2]).encoded(), authenticatedSenderID: hostID),
                       .rejected(.tickGap))
        XCTAssertEqual(guest, after)
        XCTAssertEqual(guest.receive(try packet(sequence: 2, ticks: [2, 3]).encoded(), authenticatedSenderID: hostID), .applied)
    }

    func testStrictRawScalarsCombinationsAndMissingFieldsDoNotClampOrDefault() throws {
        var (_, guest) = try endpoints()
        let initial = guest
        let invalid: [Wire.Input] = [
            .init(move: -2), .init(move: Int.max), .init(vertical: 2), .init(vertical: Int.min),
            .init(tapBits: -1), .init(tapBits: 64), .init(tapBits: 6), .init(tapBits: 63),
            .init(tapBits: 1, weaponCommand: .weapon), .init(guardHeld: true, tapBits: 1),
            .init(guardHeld: true, weaponCommand: .heavy)
        ]
        for input in invalid {
            for hostSeat in [true, false] {
                let message = packet(host: hostSeat ? input : .init(), guest: hostSeat ? .init() : input)
                XCTAssertEqual(guest.receive(try raw(message), authenticatedSenderID: hostID), .rejected(.invalidInput))
                XCTAssertEqual(guest, initial)
                XCTAssertThrowsError(try message.encoded())
            }
        }
        let original = try XCTUnwrap(String(data: packet().encoded(), encoding: .utf8))
        for field in ["move", "vertical", "tapBits"] {
            // Removing a required field, not merely changing it, must fail.
            let missing = original.replacingOccurrences(of: "\"\(field)\":0,", with: "")
                .replacingOccurrences(of: ",\"\(field)\":0", with: "")
            XCTAssertNotEqual(missing, original)
            XCTAssertEqual(guest.receive(Data(missing.utf8), authenticatedSenderID: hostID), .rejected(.malformed))
            XCTAssertEqual(guest, initial)
        }
        let missingGuard = original.replacingOccurrences(of: "\"guardHeld\":false,", with: "")
            .replacingOccurrences(of: ",\"guardHeld\":false", with: "")
        XCTAssertNotEqual(missingGuard, original)
        let fractional = original.replacingOccurrences(of: "\"move\":0", with: "\"move\":0.5")
        let stringDirection = original.replacingOccurrences(of: "\"move\":0", with: "\"move\":\"1\"")
        let armed = try XCTUnwrap(String(data: packet(host: .init(weaponCommand: .weapon)).encoded(), encoding: .utf8))
        let unknownCommand = armed.replacingOccurrences(of: "\"weaponCommand\":\"weapon\"",
                                                        with: "\"weaponCommand\":\"invented\"")
        for text in [missingGuard, fractional, stringDirection, unknownCommand] {
            XCTAssertEqual(guest.receive(Data(text.utf8), authenticatedSenderID: hostID), .rejected(.malformed))
            XCTAssertEqual(guest, initial)
        }
        let legal = packet(host: .init(move: 1, vertical: -1, guardHeld: true), guest: .init(tapBits: 3))
        XCTAssertEqual(guest.receive(try legal.encoded(), authenticatedSenderID: hostID), .applied)
    }

    func testIdentityNamespaceSessionStartAndVersionFailuresAreAtomic() throws {
        var (_, guest) = try endpoints()
        let initial = guest, valid = packet()
        for sender in [guestID, "outsider"] {
            XCTAssertEqual(guest.receive(try valid.encoded(), authenticatedSenderID: sender), .rejected(.wrongSender))
        }
        let wrong: [(Wire.Message, Wire.Failure)] = [
            (packet(session: "other"), .wrongSession), (packet(startID: "other"), .wrongStart),
            (.init(sessionID: sessionID, startID: "start-1", sequence: 1, command: .cancel,
                   version: 99), .unsupportedVersion),
            (.init(sessionID: sessionID, startID: "start-1", sequence: 1, command: .cancel,
                   namespace: "fighter.combat-start"), .wrongNamespace),
            (packet(sequence: 0), .invalidSequence), (packet(startID: " "), .invalidIdentifier),
            (packet(startID: "a\nb"), .invalidIdentifier),
            (packet(startID: String(repeating: "a", count: 257)), .invalidIdentifier)
        ]
        for (message, failure) in wrong {
            XCTAssertEqual(guest.receive(try raw(message), authenticatedSenderID: hostID), .rejected(failure))
            XCTAssertEqual(guest, initial)
        }
        XCTAssertEqual(guest, initial)
        XCTAssertEqual(guest.receive(try valid.encoded(), authenticatedSenderID: hostID), .applied)
    }

    func testByteBatchAndCounterBounds() throws {
        var (host, guest) = try endpoints()
        let initialHost = host, initialGuest = guest
        for count in [Int.min, -1, 0, 33, Int.max] {
            XCTAssertThrowsError(try host.advance(frameCount: count)) {
                XCTAssertEqual($0 as? Wire.Failure, .invalidBatch)
            }
            XCTAssertEqual(host, initialHost)
        }
        let invalidBatches: [[UInt64]] = [[], Array(UInt64(0)...UInt64(32))]
        for ticks in invalidBatches {
            XCTAssertEqual(guest.receive(try raw(packet(ticks: ticks)), authenticatedSenderID: hostID), .rejected(.invalidBatch))
        }
        XCTAssertEqual(guest.receive(Data(repeating: 32, count: Wire.maximumMessageBytes + 1), authenticatedSenderID: hostID),
                       .rejected(.oversized))
        XCTAssertEqual(guest.receive(Data("{}".utf8), authenticatedSenderID: hostID), .rejected(.malformed))
        XCTAssertEqual(guest.receive(try raw(packet(ticks: [UInt64.max])), authenticatedSenderID: hostID), .rejected(.tickExhausted))
        XCTAssertEqual(guest.receive(try raw(packet(sequence: UInt64.max)), authenticatedSenderID: hostID), .rejected(.sequenceGap))
        XCTAssertEqual(guest, initialGuest)
        let maximum = try host.advance(frameCount: Wire.maximumFrames)
        XCTAssertLessThanOrEqual(try maximum.encoded().count, Wire.maximumMessageBytes)
        XCTAssertEqual(guest.receive(try maximum.encoded(), authenticatedSenderID: hostID), .applied)
        XCTAssertEqual(guest.game, host.game)
    }

    func testCancellationDisconnectAndInterruptionAreTerminal() throws {
        var (host, guest) = try endpoints()
        for sender in [hostID, guestID] {
            XCTAssertEqual(host.receive(.init(sessionID: sessionID, sequence: 1, tick: 0,
                                               weaponCommand: .weapon), authenticatedSenderID: sender), .applied)
        }
        XCTAssertEqual(guest.receive(try host.advance().encoded(), authenticatedSenderID: hostID), .applied)
        for sender in [hostID, guestID] {
            XCTAssertEqual(host.receive(.init(sessionID: sessionID, sequence: 2, tick: 1,
                                               weaponCommand: .heavy), authenticatedSenderID: sender), .applied)
        }
        XCTAssertEqual(guest.receive(try host.advance().encoded(), authenticatedSenderID: hostID), .applied)
        var cleared = guest.game
        cleared.cancelBufferedInputs()
        XCTAssertNotEqual(guest.game, cleared, "Fixture must exercise clearing pending game commands")
        let cancellation = try host.makeCancellation()
        XCTAssertEqual(guest.receive(try cancellation.encoded(), authenticatedSenderID: hostID), .applied)
        XCTAssertEqual(guest.game, cleared)
        XCTAssertEqual(try guest.verificationState(), try host.verificationState())
        let closed = guest
        XCTAssertEqual(guest.receive(try cancellation.encoded(), authenticatedSenderID: hostID), .ignoredDuplicate)
        XCTAssertEqual(guest.receive(try packet(sequence: 4, ticks: [2]).encoded(), authenticatedSenderID: hostID), .rejected(.closed))
        XCTAssertEqual(guest, closed)
        XCTAssertThrowsError(try host.advance())
        XCTAssertEqual(host.receive(.init(sessionID: sessionID, sequence: 3, tick: 2), authenticatedSenderID: guestID),
                       .rejected(.inactive))
        for player in [hostID, guestID] {
            var (h, g) = try endpoints()
            XCTAssertEqual(h.disconnect(playerID: "stranger"), .rejected(.wrongSender))
            XCTAssertEqual(g.disconnect(playerID: "stranger"), .rejected(.wrongSender))
            XCTAssertEqual(h.disconnect(playerID: player), .applied)
            XCTAssertEqual(g.disconnect(playerID: player), .applied)
            XCTAssertEqual(h.phase, .closed); XCTAssertEqual(g.phase, .closed)
            XCTAssertThrowsError(try h.advance())
            XCTAssertEqual(g.receive(try packet().encoded(), authenticatedSenderID: hostID), .rejected(.closed))
        }
        var (h, g) = try endpoints()
        XCTAssertEqual(h.interrupt(), .applied); XCTAssertEqual(g.interrupt(), .applied)
        XCTAssertThrowsError(try h.makeCancellation())
        XCTAssertEqual(g.interrupt(), .rejected(.closed))
    }

    func testEpochChangeFailsClosedOnlyForPinnedHostAndStart() throws {
        var (_, guest) = try endpoints()
        let initial = guest
        XCTAssertEqual(guest.receive(try packet(epoch: 1).encoded(), authenticatedSenderID: guestID), .rejected(.wrongSender))
        XCTAssertEqual(guest.receive(try packet(epoch: 1, startID: "old").encoded(), authenticatedSenderID: hostID),
                       .rejected(.wrongStart))
        XCTAssertEqual(guest, initial)
        XCTAssertEqual(guest.receive(try packet(epoch: 1).encoded(), authenticatedSenderID: hostID), .terminatedForEpochChange)
        XCTAssertEqual(guest.phase, .closed)
        XCTAssertEqual(guest.nextTick, 0); XCTAssertEqual(guest.lastSequence, 0)
        XCTAssertEqual(guest.receive(try packet().encoded(), authenticatedSenderID: hostID), .rejected(.closed))
    }

    func testVerificationPinsConfigurationAndStreamBoundaryNotOnlyVisibleGame() throws {
        var (host, guest) = try endpoints()
        let initial = try guest.verificationState()
        let message = try host.advance(frameCount: 2)
        XCTAssertNotEqual(initial, try host.verificationState())
        XCTAssertEqual(guest.receive(try message.encoded(), authenticatedSenderID: hostID), .applied)
        XCTAssertEqual(try host.verificationState(), try guest.verificationState())
        XCTAssertEqual(try guest.verificationState().gameBytes, try DuelReplayStateEncoding.encode(guest.game))
        let (_, otherBarrier) = try barriers(startID: "another-start")
        let other = try DuelNetworkReplay(committed: otherBarrier, loadedCompatibility: compatibility,
                                           catalog: DuelWeaponTestFixtures.catalog())
        let otherInitial = try other.verificationState()
        XCTAssertEqual(initial.gameBytes, otherInitial.gameBytes)
        XCTAssertNotEqual(initial, otherInitial, "Same game state does not identify the same committed start")
    }

    /// Local to terminal tests: shared fixtures intentionally have zero root motion.
    /// Clone idle as a forward walk with 0.64 units per 16-tick cycle. Idle,
    /// weapon geometry, damage, timing and production rules remain unchanged.
    private func terminalCatalog() throws -> DuelWeaponCatalog {
        let catalog = try DuelWeaponTestFixtures.changing(DuelWeaponTestFixtures.catalog()) { profiles in
            for index in profiles.indices {
                var roles = profiles[index]["roles"] as! [String: String]
                var clips = profiles[index]["clips"] as! [[String: Any]]
                let idleName = roles["idle"]!
                var walk = clips.first { $0["name"] as? String == idleName }!
                let walkName = idleName + "_terminal_walk"
                walk["name"] = walkName
                let samples = 2 * (walk["frames"] as! Int) - 1
                var tracks = walk["tracks"] as! [String: Any]
                tracks["root"] = (0..<samples).map { sample in
                    [0.64 * Double(sample) / Double(samples - 1), 0.0, 0.0]
                }
                walk["tracks"] = tracks
                clips.append(walk)
                roles["walkForward"] = walkName
                profiles[index]["clips"] = clips
                profiles[index]["roles"] = roles
            }
        }
        try catalog.validate()
        return catalog
    }

    /// Exercise the real host and consumed-input wire, without injecting game state.
    /// Return the guest BEFORE the terminal batch so rejection can be checked atomically.
    private func terminalEndpoints(swapped: Bool = false) throws
        -> (DuelNetworkCombatHost, DuelNetworkReplay, Wire.Message) {
        let catalog = try terminalCatalog()
        var (host, guest) = try endpoints(swapped: swapped, catalog: catalog)
        let initialGap = abs(host.game.fighters[1].x - host.game.fighters[0].x)
        var approached = false
        var landedDamage = false
        func diagnostic(_ reason: String) -> NSError {
            NSError(domain: "DuelNetworkReplayTests.terminalFixture", code: 1,
                    userInfo: [NSLocalizedDescriptionKey:
                        "\(reason); swapped=\(swapped), tick=\(host.nextTick), phase=\(host.game.phase), " +
                        "x=\(host.game.fighters.map(\.x)), health=\(host.game.fighters.map(\.health)), " +
                        "wins=\(host.game.wins), hits=\(host.game.landedHits), damage=\(host.game.damageDealt)"])
        }
        for _ in 0..<12_000 {
            let tick = host.nextTick
            let gap = abs(host.game.fighters[1].x - host.game.fighters[0].x)
            let direction = host.game.fighters[0].x < host.game.fighters[1].x ? 1 : -1
            // Approach first. The unchanged synthetic strike can intersect a
            // torso within one unit; a 3-unit opening swing cannot land.
            let attack = gap <= 1_000 && tick % 30 == 0
            XCTAssertEqual(host.receive(.init(sessionID: sessionID, sequence: tick + 1, tick: tick,
                                               move: direction,
                                               weaponCommand: attack ? .weapon : nil),
                                        authenticatedSenderID: hostID), .applied)
            let message = try host.advance()
            approached = approached || abs(host.game.fighters[1].x - host.game.fighters[0].x) < initialGap
            landedDamage = landedDamage || (host.game.landedHits[0] > 0 && host.game.damageDealt[0] > 0)
            if host.nextTick == 120 {
                XCTAssertTrue(approached, diagnostic("No actual forward approach by tick 120").localizedDescription)
                guard approached else { throw diagnostic("Approach fixture failed") }
            }
            if host.nextTick == 300 {
                XCTAssertTrue(landedDamage, diagnostic("No landed damage by tick 300").localizedDescription)
                guard landedDamage else { throw diagnostic("Contact fixture failed") }
            }
            if case .matchOver = host.game.phase {
                XCTAssertTrue(approached, "Terminal setup must include actual movement")
                XCTAssertTrue(landedDamage, "Terminal setup must include actual damaging contact")
                return (host, guest, message)
            }
            XCTAssertNil(message.terminalState, "Ordinary frames must not carry a terminal projection")
            XCTAssertEqual(guest.receive(try message.encoded(), authenticatedSenderID: hostID), .applied)
        }
        throw diagnostic("Host did not finish within the bounded 12000-tick fixture")
    }

    private func changingTerminalState(_ state: DuelNetworkCombatState,
                                       _ change: (inout [String: Any]) -> Void) throws -> DuelNetworkCombatState {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state))
                                  as? [String: Any])
        change(&object)
        return try JSONDecoder().decode(DuelNetworkCombatState.self,
                                        from: JSONSerialization.data(withJSONObject: object))
    }

    private func replacingTerminalState(_ message: Wire.Message,
                                        with state: DuelNetworkCombatState?) -> Wire.Message {
        .init(sessionID: message.sessionID, startID: message.startID, epoch: message.epoch,
              sequence: message.sequence, command: message.command,
              version: message.version, namespace: message.namespace, terminalState: state)
    }

    func testHostTerminalProjectionPreservesSeatsAndDuplicateIsIdempotent() throws {
        for swapped in [false, true] {
            let (host, before, message) = try terminalEndpoints(swapped: swapped)
            var guest = before
            let state = try XCTUnwrap(message.terminalState)
            XCTAssertEqual(state, DuelNetworkCombatState(game: host.game, sessionID: sessionID,
                                                         tick: host.nextTick, epoch: host.epoch))
            XCTAssertEqual(state.phase, .matchOver)
            XCTAssertEqual(state.winner, 0, "Winner is the host seat, not lexical player-ID or hero order")
            XCTAssertEqual(state.fighters.map(\.hero), swapped ? [.liu, .ember] : [.ember, .liu])
            XCTAssertEqual(state.wins, host.game.wins)
            XCTAssertEqual(state.tick, guest.nextTick + 1)
            XCTAssertTrue(state.isPlausible)
            let bytes = try message.encoded()
            XCTAssertEqual(try JSONDecoder().decode(Wire.Message.self, from: bytes), message)
            XCTAssertEqual(guest.receive(bytes, authenticatedSenderID: hostID), .applied)
            XCTAssertEqual(guest.game, host.game)
            XCTAssertEqual(try guest.verificationState(), try host.verificationState())
            let finished = guest
            XCTAssertEqual(guest.receive(bytes, authenticatedSenderID: hostID), .ignoredDuplicate)
            XCTAssertEqual(guest, finished, "Retry must not step or overwrite the final state")
        }
    }

    func testPlausibleButTamperedTerminalProjectionRejectsEntireCandidateAndAllowsRetry() throws {
        let (host, before, message) = try terminalEndpoints()
        let state = try XCTUnwrap(message.terminalState)
        let tampered = try changingTerminalState(state) { object in
            var fighters = object["fighters"] as! [[String: Any]]
            fighters[0]["health"] = 999
            object["fighters"] = fighters
        }
        XCTAssertTrue(tampered.isPlausible)
        XCTAssertNotEqual(tampered, state)
        var guest = before
        let mismatch = replacingTerminalState(message, with: tampered)
        XCTAssertEqual(guest.receive(try mismatch.encoded(), authenticatedSenderID: hostID),
                       .rejected(.terminalStateMismatch))
        XCTAssertEqual(guest, before, "Game, tick, sequence and duplicate cache must all remain unchanged")
        let changedScore = try changingTerminalState(state) { object in
            var wins = object["wins"] as! [Int]
            wins[0] += 1
            object["wins"] = wins
        }
        XCTAssertEqual(guest.receive(try replacingTerminalState(message, with: changedScore).encoded(),
                                     authenticatedSenderID: hostID), .rejected(.terminalStateMismatch))
        XCTAssertEqual(guest, before, "A score-only mismatch must not change game, counters or duplicate cache")
        let missingScore = try changingTerminalState(state) { $0.removeValue(forKey: "wins") }
        XCTAssertNil(missingScore.wins, "The standalone legacy DTO still decodes without a score")
        XCTAssertEqual(guest.receive(try replacingTerminalState(message, with: missingScore).encoded(),
                                     authenticatedSenderID: hostID), .rejected(.terminalStateMismatch))
        XCTAssertEqual(guest, before, "Embedded terminal snapshots must include the complete score")
        XCTAssertEqual(guest.receive(try message.encoded(), authenticatedSenderID: hostID), .applied)
        XCTAssertEqual(guest.game, host.game)
        let finished = guest
        XCTAssertEqual(guest.receive(try mismatch.encoded(), authenticatedSenderID: hostID),
                       .rejected(.conflictingDuplicate))
        XCTAssertEqual(guest, finished)
    }

    func testTerminalProjectionShapeFailuresAndLegacyAbsentSnapshotAreAtomic() throws {
        let (host, before, message) = try terminalEndpoints()
        let state = try XCTUnwrap(message.terminalState)
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["sessionID"] = "other-session" },
            { $0["epoch"] = state.epoch + 1 },
            { $0["tick"] = state.tick + 1 },
            { $0["phase"] = "fighting"; $0.removeValue(forKey: "winner") },
            { $0["version"] = 99 },
            { $0["fighters"] = [] as [Any] }
        ]
        var guest = before
        for change in mutations {
            let invalid = replacingTerminalState(message, with: try changingTerminalState(state, change))
            XCTAssertThrowsError(try invalid.encoded()) {
                XCTAssertEqual($0 as? Wire.Failure, .invalidTerminalState)
            }
            XCTAssertEqual(guest.receive(try raw(invalid), authenticatedSenderID: hostID),
                           .rejected(.invalidTerminalState))
            XCTAssertEqual(guest, before)
        }
        let cancellation = Wire.Message(sessionID: message.sessionID, startID: message.startID,
                                        epoch: message.epoch, sequence: message.sequence,
                                        command: .cancel, terminalState: state)
        XCTAssertEqual(guest.receive(try raw(cancellation), authenticatedSenderID: hostID),
                       .rejected(.invalidTerminalState))
        XCTAssertEqual(guest, before)

        // Older senders omit the optional field completely, including on their final batch.
        let legacy = replacingTerminalState(message, with: nil)
        let bytes = try legacy.encoded()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertNil(object["terminalState"])
        XCTAssertNil(try JSONDecoder().decode(Wire.Message.self, from: bytes).terminalState)
        XCTAssertEqual(guest.receive(bytes, authenticatedSenderID: hostID), .applied)
        XCTAssertEqual(guest.game, host.game)
        XCTAssertEqual(try guest.verificationState(), try host.verificationState())
    }

}
