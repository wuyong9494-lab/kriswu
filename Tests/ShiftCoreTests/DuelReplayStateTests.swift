import XCTest
@testable import ShiftCore

final class DuelReplayStateTests: XCTestCase {
    private typealias Encoding = DuelReplayStateEncoding
    private typealias Fixture = DuelWeaponTestFixtures

    func testSameSeedAndInputReplayProducesIdenticalLaboratoryBytes() throws {
        for hero in DuelGame.Hero.allCases {
            for difficulty in DuelGame.Difficulty.allCases {
                var a = DuelGame(hero: hero, difficulty: difficulty, seed: 812)
                var b = DuelGame(hero: hero, difficulty: difficulty, seed: 812)
                for tick in 0..<600 {
                    let input = DuelGame.Input(move: tick % 110 < 65 ? 1 : -1, guardHeld: tick % 100 > 80,
                        taps: tick % 41 == 0 ? .skill1 : tick % 23 == 0 ? .light : [])
                    a.step(input); b.step(input)
                    XCTAssertEqual(try Encoding.encode(a), try Encoding.encode(b), "\(hero) tick \(tick)")
                }
            }
        }
    }

    func testBothEquippedHeroOrdersReplayIdenticallyWithSeededAI() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            for difficulty in DuelGame.Difficulty.allCases {
                var a = DuelGame(hero: hero, difficulty: difficulty, seed: 812, weaponCatalog: Fixture.catalog())
                var b = DuelGame(hero: hero, difficulty: difficulty, seed: 812, weaponCatalog: Fixture.catalog())
                for tick in 0..<240 {
                    let input = DuelGame.Input(move: tick % 70 < 40 ? 1 : -1,
                        guardHeld: tick % 100 > 80, taps: tick % 83 == 0 ? .jump : [],
                        weaponCommand: tick % 37 == 0 ? .weapon : tick % 53 == 0 ? .kick : nil)
                    a.step(input); b.step(input)
                    XCTAssertEqual(try Encoding.encode(a), try Encoding.encode(b), "\(hero) tick \(tick)")
                }
                let fight = try XCTUnwrap(a.weaponFight)
                XCTAssertEqual(fight.profiles.map(\.hero), [hero, hero == .ember ? .liu : .ember])
                XCTAssertEqual(try Encoding.encode(fight), try Encoding.encode(XCTUnwrap(b.weaponFight)))
            }
        }
    }

    func testStateChangeAndInvisibleRNGChangeProduceDifferentBytes() throws {
        var game = DuelGame(seed: 7)
        let before = try Encoding.encode(game)
        game.step(.init(move: 1), opponent: .neutral)
        XCTAssertNotEqual(before, try Encoding.encode(game))
        let otherSeed = DuelGame(seed: 8)
        XCTAssertEqual(DuelGame(seed: 7).fighters, otherSeed.fighters)
        XCTAssertNotEqual(before, try Encoding.encode(otherSeed), "RNG matters before the next AI decision")

        let equipped = DuelGame(hero: .ember, seed: 7, weaponCatalog: Fixture.catalog())
        let different = DuelGame(hero: .ember, seed: 8, weaponCatalog: Fixture.catalog())
        XCTAssertEqual(equipped.fighters, different.fighters)
        XCTAssertNotEqual(try Encoding.encode(XCTUnwrap(equipped.weaponFight)),
                          try Encoding.encode(XCTUnwrap(different.weaponFight)))
        XCTAssertNotEqual(try Encoding.encode(equipped), try Encoding.encode(different))
    }

    func testPausedCancellationChangesInvisibleEquippedQueueInBothOrders() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            var queued = DuelGame(hero: hero, mode: .practice, weaponCatalog: Fixture.catalog())
            queued.step(.init(weaponCommand: .weapon), opponent: .neutral)
            queued.step(.init(weaponCommand: .kick), opponent: .neutral)
            var cancelled = queued
            cancelled.cancelBufferedInputs()
            XCTAssertEqual(queued.fighters, cancelled.fighters)
            XCTAssertEqual(queued.frame, cancelled.frame)
            XCTAssertEqual(queued.events, cancelled.events)
            XCTAssertNotEqual(try Encoding.encode(queued), try Encoding.encode(cancelled))
            XCTAssertNotEqual(try Encoding.encode(XCTUnwrap(queued.weaponFight)),
                              try Encoding.encode(XCTUnwrap(cancelled.weaponFight)))
            let fight = try XCTUnwrap(queued.weaponFight)
            let kick = try XCTUnwrap(fight.profiles[0].clip(command: .kick)?.name)
            var playedQueuedKick = false
            for _ in 0..<40 {
                queued.step(.neutral, opponent: .neutral); cancelled.step(.neutral, opponent: .neutral)
                playedQueuedKick = playedQueuedKick || queued.fighters[0].weaponPose?.clip == kick
                XCTAssertNotEqual(cancelled.fighters[0].weaponPose?.clip, kick)
            }
            XCTAssertTrue(playedQueuedKick, "The hidden queue must be real, not a no-op cancellation")
        }
    }

    func testPausedCancellationChangesLaboratoryHitStopMailboxBytes() throws {
        var queued = laboratoryContact()
        XCTAssertGreaterThan(queued.hitStop, 0)
        queued.step(.init(taps: .heavy), opponent: .neutral)
        var cancelled = queued
        cancelled.cancelBufferedInputs()
        XCTAssertEqual(queued.fighters, cancelled.fighters)
        XCTAssertEqual(queued.frame, cancelled.frame)
        XCTAssertEqual(queued.hitStop, cancelled.hitStop)
        XCTAssertEqual(queued.events, cancelled.events)
        XCTAssertNotEqual(try Encoding.encode(queued), try Encoding.encode(cancelled))
    }

    func testCancelledLaboratoryComboLinkIsEncodedWithoutUndoingCurrentMove() throws {
        var queued = laboratoryContact()
        for _ in 0..<10 where queued.hitStop > 0 { queued.step(.neutral, opponent: .neutral) }
        queued.step(.init(taps: .light), opponent: .neutral)
        XCTAssertEqual(queued.fighters[0].attack?.comboQueued, true)
        var cancelled = queued
        cancelled.cancelBufferedInputs()
        XCTAssertEqual(cancelled.fighters[0].attack?.comboQueued, false)
        XCTAssertEqual(queued.fighters[0].attack?.move, cancelled.fighters[0].attack?.move)
        XCTAssertEqual(queued.fighters[0].attack?.age, cancelled.fighters[0].attack?.age)
        XCTAssertNotEqual(try Encoding.encode(queued), try Encoding.encode(cancelled))
    }

    private func laboratoryContact() -> DuelGame {
        var game = DuelGame()
        for _ in 0..<24 { game.step(.init(move: 1), opponent: .init(move: -1)) }
        game.step(.init(taps: .light), opponent: .neutral)
        for _ in 0..<20 where game.hitStop == 0 { game.step(.neutral, opponent: .neutral) }
        return game
    }

    func testCatalogTracksRolesAndComboChangesCannotHideBehindUnchangedAssetSHA() throws {
        let original = Fixture.catalog()
        let trackChanged = try Fixture.changing(original) { profiles in
            var clips = profiles[0]["clips"] as! [[String: Any]]
            var tracks = clips[0]["tracks"] as! [String: Any]
            var root = tracks["root"] as! [[Double]]
            root[1][0] = 0.125
            tracks["root"] = root; clips[0]["tracks"] = tracks; profiles[0]["clips"] = clips
        }
        let rolesChanged = try Fixture.changing(original) { profiles in
            var roles = profiles[0]["roles"] as! [String: String]
            roles["weapon1"] = "katana_heavy"; profiles[0]["roles"] = roles
        }
        let combosChanged = try Fixture.changing(original) { profiles in
            profiles[0]["comboLinks"] = [["from": "katana_weapon", "to": "katana_weapon2", "sourceFrame": 4]]
        }
        let baseline = DuelGame(hero: .ember, weaponCatalog: original)
        for changed in [trackChanged, rolesChanged, combosChanged] {
            try changed.validate()
            XCTAssertEqual(original.profiles.map(\.sha256), changed.profiles.map(\.sha256))
            let game = DuelGame(hero: .ember, weaponCatalog: changed)
            XCTAssertEqual(baseline.fighters, game.fighters)
            XCTAssertNotEqual(try Encoding.encode(baseline), try Encoding.encode(game))
            XCTAssertNotEqual(try Encoding.encodeCatalog(original), try Encoding.encodeCatalog(changed))
        }
    }

    func testDictionaryInsertionOrderCannotChangeCanonicalCatalogBytes() throws {
        let catalog = Fixture.catalog()
        func reordered(_ reversed: Bool) -> DuelWeaponCatalog {
            let profiles = catalog.profiles.map { p -> DuelWeaponProfile in
                var roles: [String: String] = [:]
                let keys = p.roles.keys.sorted()
                for key in reversed ? Array(keys.reversed()) : keys { roles[key] = p.roles[key] }
                return .init(id: p.id, hero: p.hero, faction: p.faction, resourceName: p.resourceName,
                    bytes: p.bytes, sha256: p.sha256, bodyID: p.bodyID, weaponID: p.weaponID,
                    activeWeaponSides: p.activeWeaponSides, roles: roles, clips: p.clips, comboLinks: p.comboLinks)
            }
            return .init(schemaVersion: catalog.schemaVersion, previewFramesPerSecond: catalog.previewFramesPerSecond,
                         sourceFramesPerSecond: catalog.sourceFramesPerSecond, profiles: profiles)
        }
        let forward = reordered(false), backward = reordered(true)
        XCTAssertEqual(forward, backward)
        XCTAssertEqual(try Encoding.encodeCatalog(forward), try Encoding.encodeCatalog(backward))
        XCTAssertEqual(try Encoding.encode(DuelGame(weaponCatalog: forward)),
                       try Encoding.encode(DuelGame(weaponCatalog: backward)))
    }


    func testInitialGameGoldenPinsTheCompleteVersionTwoFieldOrder() throws {
        // Independent signed-64/little-endian reference fixture, not JSON or a Swift hash.
        let hex = [
            "4455454c5354415402000600010000000200000000ac0d00000000000000000000000000000000000000000000010000",
            "0000000000e803000000000000e803000000000000640000000000000000000000000000000000000000000000000000",
            "000000000000000000000000000000000000000000000000000164190000000000000000000000000000000000000000",
            "0000ffffffffffffffffe803000000000000e80300000000000064000000000000000000000000000000000000000000",
            "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100e0000",
            "000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000",
            "000000000000000002000000000000000000000000000000000000000007000000000000000000000000000000000000",
            "000000000000000000000000000000000000000000000002000000000000000000000000000000000000000100"
        ].joined()
        let chars = Array(hex)
        let expected = stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...($0 + 1)]), radix: 16)! }
        XCTAssertEqual(try Encoding.encode(DuelGame(seed: 7)), Data(expected))
    }

    func testSyntheticDiagnosticSizesStayExplicit() throws {
        let catalog = Fixture.catalog()
        let game = DuelGame(weaponCatalog: catalog)
        // Measured by an independent schema-size calculation, also pinned here.
        XCTAssertEqual(try Encoding.encode(DuelGame()).count, 381)
        XCTAssertEqual(try Encoding.encodeCatalog(catalog).count, 65_388)
        XCTAssertEqual(try Encoding.encode(XCTUnwrap(game.weaponFight)).count, 65_849)
        XCTAssertEqual(try Encoding.encode(game).count, 66_298)
    }

    func testCanonicalScalarsHaveFixedGoldenByteOrderAndLengths() throws {
        var writer = try DuelReplayStateWriter(kind: 1)
        try writer.int(-2); try writer.u64(0x0123456789abcdef); try writer.double(0.25)
        try writer.string("é"); try writer.optional(nil as Int?) { try $0.int($1) }
        try writer.optional(7) { try $0.int($1) }
        XCTAssertEqual(Array(writer.data), [
            0x44, 0x55, 0x45, 0x4c, 0x53, 0x54, 0x41, 0x54, 2, 0, 6, 0, 1,
            0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
            0xef, 0xcd, 0xab, 0x89, 0x67, 0x45, 0x23, 0x01,
            0, 0, 0, 0, 0, 0, 0xd0, 0x3f,
            2, 0, 0, 0, 0xc3, 0xa9, 0, 1, 7, 0, 0, 0, 0, 0, 0, 0
        ])
    }

    func testFloatingBitPatternsAreNotRoundedOrNormalized() throws {
        for bits in [UInt64(0), 0x8000000000000000, 0x7ff8000000000001, 0x7ff8000000000002,
                            0x7ff0000000000000, 0x3ff0000000000001] {
            var writer = try DuelReplayStateWriter(kind: 2)
            try writer.double(Double(bitPattern: bits))
            let expected = (0..<8).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) }
            XCTAssertEqual(Array(writer.data.suffix(8)), expected)
        }
    }

    func testEncodingFailsClosedAtEachBoundWithoutTruncating() throws {
        var writer = try DuelReplayStateWriter(kind: 1, byteLimit: 13)
        XCTAssertThrowsError(try writer.u8(0)) { XCTAssertEqual($0 as? Encoding.Failure, .byteLimit) }
        writer = try DuelReplayStateWriter(kind: 1)
        XCTAssertThrowsError(try writer.string(String(repeating: "é", count: 2049))) {
            XCTAssertEqual($0 as? Encoding.Failure, .stringLimit)
        }
        XCTAssertThrowsError(try writer.array(Array(repeating: 0, count: Encoding.maximumCollectionCount + 1)) {
            try $0.int($1)
        }) { XCTAssertEqual($0 as? Encoding.Failure, .collectionLimit) }
        XCTAssertThrowsError(try writer.array([1, 2, 3], limit: 2) { try $0.int($1) }) {
            XCTAssertEqual($0 as? Encoding.Failure, .collectionLimit)
        }
        writer = try DuelReplayStateWriter(kind: 1, byteLimit: 13 + 4 + 3)
        try writer.string("abc")
        XCTAssertEqual(writer.data.count, 20)
        XCTAssertThrowsError(try writer.bool(false))
    }

    func testExplicitEnumTagsAndPayloadKindsArePinned() throws {
        var writer = try DuelReplayStateWriter(kind: 1)
        for hero in [DuelGame.Hero.ember, .gale, .liu] { try writer.hero(hero) }
        for difficulty in [DuelGame.Difficulty.learning, .challenging] { try writer.difficulty(difficulty) }
        for mode in [DuelGame.Mode.versus, .practice, .tutorial] { try writer.mode(mode) }
        for move in [DuelGame.Move.jab, .cross, .finisher, .heavy, .skill1, .skill2, .ultimate] { try writer.move(move) }
        for command in [DuelWeaponCommand.weapon, .weaponForward, .weaponUp, .weaponDown, .weaponBack,
                        .heavy, .kick, .kickForward, .kickUp, .kickDown, .kickBack, .shadow, .ranged] {
            try writer.command(command)
        }
        XCTAssertEqual(Array(writer.data.dropFirst(13)),
                       [0, 1, 2, 0, 1, 0, 1, 2, 0, 1, 2, 3, 4, 5, 6, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
        let events: [DuelGame.Event] = [.hit(attacker: 0, damage: 75), .blocked(defender: 1),
            .guardBreak(defender: 1), .whiff(attacker: 0), .jumped(player: 0), .roundEnded(winner: nil),
            .grappleStarted(attacker: 0), .grappleSlam(attacker: 0), .grappleReleased(attacker: 0), .grappleClash]
        for (tag, event) in events.enumerated() {
            var eventWriter = try DuelReplayStateWriter(kind: 1)
            try eventWriter.event(event)
            XCTAssertEqual(eventWriter.data[13], UInt8(tag))
        }
        for (tag, phase) in [DuelGame.Phase.fighting, .roundBreak(winner: nil, remaining: 120),
                             .matchOver(winner: 0)].enumerated() {
            var phaseWriter = try DuelReplayStateWriter(kind: 1)
            try phaseWriter.phase(phase)
            XCTAssertEqual(phaseWriter.data[13], UInt8(tag))
        }
        for (tag, kind) in [DuelWeaponFight.Contact.Kind.hit, .block].enumerated() {
            var contactWriter = try DuelReplayStateWriter(kind: 2)
            try contactWriter.contact(.init(kind: kind, attacker: 0, position: .init(), direction: 1,
                                            heavy: false, usesWeapon: true))
            XCTAssertEqual(contactWriter.data[13], UInt8(tag))
        }
        let game = DuelGame(weaponCatalog: Fixture.catalog())
        XCTAssertEqual(try Encoding.encode(game)[12], 1)
        XCTAssertEqual(try Encoding.encode(XCTUnwrap(game.weaponFight))[12], 2)
        XCTAssertEqual(try Encoding.encodeCatalog(Fixture.catalog())[12], 3)
    }
}
