import XCTest
@testable import ShiftCore

/// End-to-end transport checks use artificial throw tracks, timing and damage.
/// They verify deterministic integration, not an original-game motion preset.
final class DuelPanguThrowNetworkTests: XCTestCase {
    private typealias Selection = DuelMultiplayerSelection
    private typealias Barrier = DuelNetworkStartBarrier
    private let sessionID = "pangu-ordinary-throw-network"
    private let hostID = "throw-host", guestID = "throw-guest"
    private let compatibility = Barrier.Compatibility(
        rulesFingerprint: String(repeating: "a", count: 64),
        catalogFingerprint: String(repeating: "b", count: 64))

    private func started(panguHost: Bool) throws -> Selection.Snapshot {
        var selection = try Selection(sessionID: sessionID, hostID: hostID, guestID: guestID)
        for (sender, sequence, command) in [
            (hostID, UInt64(1), Selection.Command.select(panguHost ? .liuPangu : .sun)),
            (guestID, UInt64(1), .select(panguHost ? .sun : .liuPangu)),
            (hostID, UInt64(2), .ready(true, selectionRevision: 2)),
            (guestID, UInt64(2), .ready(true, selectionRevision: 2)),
            (hostID, UInt64(3), .start(selectionRevision: 2))
        ] {
            XCTAssertEqual(selection.apply(.init(sessionID: sessionID, sequence: sequence, command: command),
                authenticatedSenderID: sender, localPlayerID: hostID), .applied)
        }
        return selection.snapshot
    }

    private func connected(catalog: DuelWeaponCatalog, panguHost: Bool) throws
        -> (DuelNetworkCombatHost, DuelNetworkReplay) {
        let snapshot = try started(panguHost: panguHost)
        var host = try Barrier(started: snapshot, sessionID: sessionID, hostID: hostID,
            guestID: guestID, localPlayerID: hostID, compatibility: compatibility)
        var guest = try Barrier(started: snapshot, sessionID: sessionID, hostID: hostID,
            guestID: guestID, localPlayerID: guestID, compatibility: compatibility)
        let offer = try host.makeOffer(startID: "ordinary-throw-start", seed: 91, sequence: 1)
        XCTAssertEqual(guest.receive(try offer.encoded(), authenticatedSenderID: hostID), .applied)
        let configuration = try XCTUnwrap(host.offeredConfiguration)
        let hostLoaded = try host.confirmLoaded(configuration: configuration,
            loadedCompatibility: compatibility, catalog: catalog, sequence: 2)
        let guestLoaded = try guest.confirmLoaded(configuration: configuration,
            loadedCompatibility: compatibility, catalog: catalog, sequence: 1)
        XCTAssertEqual(host.receive(try guestLoaded.encoded(), authenticatedSenderID: guestID), .applied)
        XCTAssertEqual(guest.receive(try hostLoaded.encoded(), authenticatedSenderID: hostID), .applied)
        XCTAssertEqual(guest.receive(try host.commit(sequence: 3).encoded(), authenticatedSenderID: hostID), .applied)
        return (try DuelNetworkCombatHost(committed: host, started: snapshot,
                    loadedCompatibility: compatibility, catalog: catalog),
                try DuelNetworkReplay(committed: guest, loadedCompatibility: compatibility, catalog: catalog))
    }

    func testActualThrowEscapeAndSuccessReplayThroughHostWireInBothSeats() throws {
        let throwRules = try DuelWeaponThrowTestFixture.changing { object in
            let forward = (object["attempts"] as! [[String: Any]])[0]
            var backward = forward
            backward["command"] = DuelWeaponCommand.weaponBack.rawValue
            object["attempts"] = [forward, backward]
        }
        let catalog = try DuelPanguThrowFightFixture.catalog(throwRules: throwRules)
        let successDamage = try XCTUnwrap(throwRules.rule(command: .weaponForward)).success.damage

        for panguHost in [true, false] {
            var (host, guest) = try connected(catalog: catalog, panguHost: panguHost)
            let panguIndex = panguHost ? 0 : 1, sunIndex = 1 - panguIndex
            // Both existing directional wire values are exercised across the
            // two seat assignments; no throw-specific wire command is added.
            let command: DuelWeaponCommand = panguHost ? .weaponBack : .weaponForward
            var tick = UInt64(0)
            var sawEscape = false, sawSuccess = false, sawFrozenThrow = false
            var sawEscapePresentation = false
            let initialHealth = host.game.fighters.map(\.health)
            let initialLight = try XCTUnwrap(host.game.weaponFight?.panguState(panguIndex)).light

            func advance(_ inputs: [DuelGame.Input]) throws {
                let before = try XCTUnwrap(host.game.weaponFight)
                for (index, sender) in [hostID, guestID].enumerated() {
                    let input = inputs[index]
                    XCTAssertEqual(host.receive(.init(sessionID: sessionID, sequence: tick + 1, tick: tick,
                        move: input.move, vertical: input.vertical, guardHeld: input.guardHeld,
                        tapBits: input.taps.rawValue, weaponCommand: input.weaponCommand),
                        authenticatedSenderID: sender), .applied)
                }
                let message = try host.advance()
                XCTAssertEqual(guest.receive(try message.encoded(), authenticatedSenderID: hostID), .applied)
                let context = "tick \(tick), Pangu host \(panguHost)"
                XCTAssertEqual(host.game, guest.game, context)
                XCTAssertEqual(try DuelReplayStateEncoding.encode(host.game),
                               try DuelReplayStateEncoding.encode(guest.game), context)
                XCTAssertEqual(try host.verificationState(), try guest.verificationState(), context)
                XCTAssertTrue(DuelNetworkCombatState(game: host.game, sessionID: sessionID,
                    tick: tick + 1, epoch: 0).isPlausible, context)
                XCTAssertNil(host.game.grapple, "Equipped throws must not enter the laboratory ultimate")

                let fight = try XCTUnwrap(host.game.weaponFight)
                if before.hitStop > 0, before.ordinaryThrow(panguIndex) != nil {
                    sawFrozenThrow = true
                    for index in 0..<2 {
                        XCTAssertEqual(before.ordinaryThrow(index), fight.ordinaryThrow(index), context)
                        XCTAssertEqual(before.fighters[index].weaponPose, fight.fighters[index].weaponPose, context)
                    }
                }
                if let state = fight.ordinaryThrow(sunIndex), state.attacker == sunIndex, state.stage == .immune {
                    sawEscape = true
                    XCTAssertEqual(state.target, panguIndex)
                    XCTAssertTrue(state.contactConsumed)
                    XCTAssertFalse(state.damageApplied)
                    XCTAssertEqual(fight.fighters.map(\.health), initialHealth)
                    XCTAssertEqual(fight.panguState(panguIndex)?.light, initialLight)
                    XCTAssertEqual(fight.fighters[panguIndex].weaponPose?.clip,
                                   fight.profiles[panguIndex].roles["throwEscape"])
                    XCTAssertEqual(fight.fighters[panguIndex].weaponPose?.duration, 10_000)
                }
                if let state = fight.ordinaryThrow(panguIndex), state.attacker == panguIndex, state.stage == .success {
                    sawSuccess = true
                    XCTAssertEqual(state.target, sunIndex)
                    XCTAssertTrue(state.contactConsumed)
                    XCTAssertEqual(fight.fighters[sunIndex].weaponPose?.clip,
                                   fight.profiles[sunIndex].roles["throwReceived"])
                    XCTAssertEqual(fight.fighters[sunIndex].weaponPose?.duration, 10_000)
                }
                for event in fight.panguPresentationEvents {
                    if case .ordinaryThrowEscaped(let attacker, let target, _) = event.kind {
                        XCTAssertEqual(attacker, sunIndex); XCTAssertEqual(target, panguIndex)
                        sawEscapePresentation = true
                    }
                }
                tick += 1
            }

            func neutral() throws { try advance([.neutral, .neutral]) }
            func gap() -> Int { abs(host.game.fighters[1].x - host.game.fighters[0].x) }
            func requestThrow(_ index: Int) throws {
                let facing = host.game.fighters[index].facing
                var inputs = [DuelGame.Input.neutral, .neutral]
                inputs[index] = .init(move: command == .weaponForward ? facing : -facing,
                                      weaponCommand: command)
                try advance(inputs)
                XCTAssertEqual(host.game.weaponFight?.ordinaryThrow(index)?.stage, .attempt)
            }

            // Approach through authentic network inputs. Changing only the
            // initial fixture positions would miss movement/wire integration.
            for _ in 0..<40 {
                if gap() <= 850 { break }
                try advance(host.game.fighters.map { .init(move: $0.facing) })
            }
            XCTAssertTrue((620...850).contains(gap()), "Both fighters must really enter the configured throw range")
            try requestThrow(sunIndex)
            for _ in 0..<16 {
                if host.game.weaponFight?.ordinaryThrow(sunIndex) == nil { break }
                try neutral()
            }
            XCTAssertTrue(sawEscape, "Pangu must enter the actual paired escape branch")
            XCTAssertTrue(sawEscapePresentation)
            XCTAssertEqual(host.game.fighters.map(\.health), initialHealth)
            XCTAssertEqual(host.game.weaponFight?.panguState(panguIndex)?.light, initialLight)
            XCTAssertEqual(host.game.landedHits, [0, 0])
            XCTAssertEqual(host.game.weaponFight?.damageDealt, [0, 0])
            XCTAssertNil(host.game.weaponFight?.ordinaryThrow(sunIndex))

            try requestThrow(panguIndex)
            for _ in 0..<40 {
                try neutral()
                if sawSuccess, host.game.weaponFight?.ordinaryThrow(panguIndex) == nil,
                   host.game.fighters[sunIndex].knockdown == 0,
                   host.game.fighters[sunIndex].stun == 0 { break }
            }
            XCTAssertTrue(sawSuccess, "An ordinary target must follow the successful throw branch")
            XCTAssertTrue(sawFrozenThrow, "The successful damage marker must produce frozen paired poses during hit-stop")
            XCTAssertEqual(host.game.fighters[sunIndex].health, initialHealth[sunIndex] - successDamage)
            XCTAssertEqual(host.game.fighters[panguIndex].health, initialHealth[panguIndex])
            XCTAssertEqual(host.game.landedHits[panguIndex], 1)
            XCTAssertEqual(host.game.weaponFight?.damageDealt[panguIndex], successDamage)
            XCTAssertNil(host.game.weaponFight?.ordinaryThrow(panguIndex))

            let beforeRetreat = gap()
            for _ in 0..<12 {
                try advance(host.game.fighters.map { .init(move: -$0.facing) })
            }
            XCTAssertGreaterThan(gap(), beforeRetreat + 200, "Both participants must regain movement after release")
            XCTAssertEqual(host.game.fighters[sunIndex].health, initialHealth[sunIndex] - successDamage)
            XCTAssertEqual(host.game.weaponFight?.panguState(panguIndex)?.light, initialLight)
            for index in 0..<2 { XCTAssertNil(host.game.weaponFight?.ordinaryThrow(index)) }
        }
    }

    func testMissingEscapeSourceCannotLoadAndSourceRebindingChangesCanonicalCatalog() throws {
        let catalog = try DuelPanguThrowFightFixture.catalog()
        let missing = try DuelWeaponTestFixtures.changing(catalog) { profiles in
            let index = profiles.firstIndex { $0["id"] as? String == "liu_pangu" }!
            var roles = profiles[index]["roles"] as! [String: String]
            roles.removeValue(forKey: "throwEscape")
            profiles[index]["roles"] = roles
        }
        XCTAssertThrowsError(try missing.validate()) {
            XCTAssertEqual($0 as? DuelWeaponThrowRules.ValidationError, .missingSourceRole)
        }
        let snapshot = try started(panguHost: false)
        var barrier = try Barrier(started: snapshot, sessionID: sessionID, hostID: hostID,
            guestID: guestID, localPlayerID: hostID, compatibility: compatibility)
        _ = try barrier.makeOffer(startID: "missing-escape", seed: 91, sequence: 1)
        let configuration = try XCTUnwrap(barrier.offeredConfiguration)
        let before = barrier
        XCTAssertThrowsError(try barrier.confirmLoaded(configuration: configuration,
            loadedCompatibility: compatibility, catalog: missing, sequence: 2)) {
            XCTAssertEqual($0 as? Barrier.Failure, .invalidCatalog)
        }
        XCTAssertEqual(barrier, before, "Rejected source bindings must not consume the load acknowledgement")

        let rebound = try DuelWeaponTestFixtures.changing(catalog) { profiles in
            let index = profiles.firstIndex { $0["id"] as? String == "liu_pangu" }!
            var roles = profiles[index]["roles"] as! [String: String]
            roles["throwEscape"] = roles["idle"]
            profiles[index]["roles"] = roles
        }
        try rebound.validate()
        XCTAssertEqual(catalog.profiles.map(\.sha256), rebound.profiles.map(\.sha256))
        XCTAssertNotEqual(try DuelReplayStateEncoding.encodeCatalog(catalog),
                          try DuelReplayStateEncoding.encodeCatalog(rebound),
                          "Canonical identity must bind the actual paired source role, not only asset SHA labels")
        XCTAssertNoThrow(try barrier.confirmLoaded(configuration: configuration,
            loadedCompatibility: compatibility, catalog: catalog, sequence: 2))
    }
}
