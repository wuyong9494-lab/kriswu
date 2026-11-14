import XCTest
@testable import ShiftCore

final class DuelPanguNetworkTests: XCTestCase {
    private typealias Selection = DuelMultiplayerSelection
    private typealias Barrier = DuelNetworkStartBarrier
    private let sessionID = "pangu-network-test"
    private let hostID = "host", guestID = "guest"
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

    func testPanguChoiceComesFromExactCatalogAndCannotLoadLegacyHammers() throws {
        let pangu = try DuelPanguFightFixture.catalog(rules: DuelPanguTestFixture.rules())
        let legacy = DuelWeaponTestFixtures.catalog()
        XCTAssertEqual(Selection.Choice.available(in: legacy), [.sun, .liu])
        XCTAssertEqual(Selection.Choice.available(in: pangu), [.sun, .liuPangu])
        XCTAssertFalse(Selection.Choice(hero: .ember, weapon: .pangu).isValid)
        XCTAssertFalse(Selection.Choice(hero: .gale, weapon: .pangu).isValid)
        let snapshot = try started(panguHost: false)
        XCTAssertThrowsError(try DuelNetworkHostSimulation(started: snapshot, localPlayerID: hostID,
            catalog: legacy, seed: 9)) {
            XCTAssertEqual($0 as? DuelNetworkHostSimulation.Failure, .invalidCatalog)
        }
        XCTAssertNoThrow(try DuelNetworkHostSimulation(started: snapshot, localPlayerID: hostID,
            catalog: pangu, seed: 9))
    }

    func testPanguDirectionsAndMechanicsReplayThroughRealHostWireInBothSeats() throws {
        var rules = DuelPanguTestFixture.rules()
        // Exercise the opt-in precise fields in both real wire/replay seats.
        // These lifetime/timing policies are synthetic, not a retail preset.
        rules.heavenfall.lightPerChargeTick = 1
        rules.heavenfall.level6LightChargeRatio = .init(numerator: 5, denominator: 4,
            carryAcrossCasts: true, discardRemainderAtCapacity: false)
        rules.heavenfall.level6ComboGainTrigger = .castStarted
        rules.maximumHealth = 1500
        // Low synthetic damage keeps this transport test in a single round.
        for index in rules.abilities.indices {
            rules.abilities[index].attack.damage = 1
            rules.abilities[index].attack.blockedDamage = 0
        }
        rules.hunt.empoweredSpear.damage = 1; rules.windBlade.damage = 1
        rules.earth.boulderBonus.damage = 1; rules.earth.landingShock.damage = 1
        let catalog = try DuelPanguFightFixture.catalog(rules: rules, ordinaryDamage: 1)

        for panguHost in [true, false] {
            let snapshot = try started(panguHost: panguHost)
            var hostBarrier = try Barrier(started: snapshot, sessionID: sessionID, hostID: hostID,
                guestID: guestID, localPlayerID: hostID, compatibility: compatibility)
            var guestBarrier = try Barrier(started: snapshot, sessionID: sessionID, hostID: hostID,
                guestID: guestID, localPlayerID: guestID, compatibility: compatibility)
            let offer = try hostBarrier.makeOffer(startID: "pangu-start", seed: 73, sequence: 1)
            XCTAssertEqual(guestBarrier.receive(try offer.encoded(), authenticatedSenderID: hostID), .applied)
            let configuration = try XCTUnwrap(hostBarrier.offeredConfiguration)
            let hostLoaded = try hostBarrier.confirmLoaded(configuration: configuration,
                loadedCompatibility: compatibility, catalog: catalog, sequence: 2)
            let guestLoaded = try guestBarrier.confirmLoaded(configuration: configuration,
                loadedCompatibility: compatibility, catalog: catalog, sequence: 1)
            XCTAssertEqual(hostBarrier.receive(try guestLoaded.encoded(), authenticatedSenderID: guestID), .applied)
            XCTAssertEqual(guestBarrier.receive(try hostLoaded.encoded(), authenticatedSenderID: hostID), .applied)
            XCTAssertEqual(guestBarrier.receive(try hostBarrier.commit(sequence: 3).encoded(),
                authenticatedSenderID: hostID), .applied)
            var host = try DuelNetworkCombatHost(committed: hostBarrier, started: snapshot,
                loadedCompatibility: compatibility, catalog: catalog)
            var guest = try DuelNetworkReplay(committed: guestBarrier,
                loadedCompatibility: compatibility, catalog: catalog)
            let panguIndex = panguHost ? 0 : 1
            var casts: Set<DuelPanguRules.Ability> = []
            for tick in UInt64(0)..<270 {
                let facing = host.game.fighters[panguIndex].facing
                let pangu: DuelGame.Input
                switch tick {
                case 0: pangu = .init(move: facing, weaponCommand: .shadow)
                case 40, 48: pangu = .init(move: -facing, weaponCommand: .shadow)
                case 90: pangu = .init(vertical: 1, weaponCommand: .shadow)
                case 130: pangu = .init(vertical: -1, weaponCommand: .shadow)
                case 170: pangu = .init(weaponCommand: .ranged)
                case 210: pangu = .init(weaponCommand: .shadow)
                default: pangu = .neutral
                }
                let inputs: [DuelGame.Input] = panguHost ? [pangu, .neutral] : [.neutral, pangu]
                for (index, sender) in [hostID, guestID].enumerated() {
                    let input = inputs[index]
                    XCTAssertEqual(host.receive(.init(sessionID: sessionID, sequence: tick + 1, tick: tick,
                        move: input.move, vertical: input.vertical, guardHeld: input.guardHeld,
                        tapBits: input.taps.rawValue, weaponCommand: input.weaponCommand),
                        authenticatedSenderID: sender), .applied)
                }
                let message = try host.advance()
                XCTAssertEqual(guest.receive(try message.encoded(), authenticatedSenderID: hostID), .applied)
                XCTAssertEqual(host.game, guest.game, "Pangu replay diverged at tick \(tick), host=\(panguHost)")
                if let ability = host.game.weaponFight?.panguState(panguIndex)?.activeCast?.ability {
                    casts.insert(ability)
                }
                if tick.isMultiple(of: 60) {
                    XCTAssertEqual(try host.verificationState(), try guest.verificationState())
                    XCTAssertTrue(DuelNetworkCombatState(game: host.game, sessionID: sessionID,
                        tick: tick + 1, epoch: 0).isPlausible)
                }
            }
            XCTAssertEqual(casts, Set(DuelPanguRules.Ability.allCases), "Every directional/active ability must really start")
            XCTAssertGreaterThan(host.game.landedHits[panguIndex], 0)
            XCTAssertEqual(host.game.weaponFight?.maximumHealth(panguIndex), 1500)
            XCTAssertEqual(host.game.fighters[panguIndex].health, 1500)
        }
    }

    func testConfiguredHealthProjectionAcceptsSupportedMaximumAndRejectsOutOfRangeValues() {
        var fighter = DuelGame.Fighter(hero: .liu, x: 3500, facing: 1)
        for health in [0, 1500, 1_000_000] {
            fighter.health = health
            XCTAssertTrue(DuelNetworkCombatState.Fighter(fighter).isPlausible)
        }
        for health in [-1, 1_000_001] {
            fighter.health = health
            XCTAssertFalse(DuelNetworkCombatState.Fighter(fighter).isPlausible)
        }
    }
}
