import XCTest
@testable import ShiftCore

final class DuelWeaponFightTests: XCTestCase {
    private typealias Fixture = DuelWeaponTestFixtures

    func testImpactPauseIsOneFrameForLightAndBlockTwoForHeavy() throws {
        for command in [DuelWeaponCommand.weapon, .heavy] {
            for blocked in [false, true] {
                var fight = try Fixture.fight()
                fight.step(.init(weaponCommand: command), opponent: .init(guardHeld: blocked))
                for _ in 0..<80 where fight.hitStop == 0 {
                    fight.step(.neutral, opponent: .init(guardHeld: blocked))
                }
                XCTAssertFalse(fight.contacts.isEmpty)
                XCTAssertEqual(fight.hitStop, blocked || command == .weapon ? 1 : 2)
                let pose = fight.fighters[0].weaponPose
                let pause = fight.hitStop
                for _ in 0..<pause { fight.step(.neutral, opponent: .neutral) }
                XCTAssertEqual(fight.fighters[0].weaponPose, pose)
                XCTAssertEqual(fight.hitStop, 0)
                fight.step(.neutral, opponent: .neutral)
                XCTAssertNotEqual(fight.fighters[0].weaponPose, pose)
            }
        }
    }

    func testFightRetainsTheTwoDifferentProfilesWhenPlayerOrderChanges() throws {
        let catalog = Fixture.catalog()
        for (first, second) in [(DuelGame.Hero.ember, DuelGame.Hero.liu), (.liu, .ember)] {
            var game = DuelGame(hero: first, mode: .practice, weaponCatalog: catalog)
            let fight = try XCTUnwrap(game.weaponFight)
            XCTAssertEqual(fight.profiles.map(\.hero), [first, second])
            XCTAssertNotEqual(fight.profiles[0].weaponID, fight.profiles[1].weaponID)
            game.step(.init(weaponCommand: .weapon), opponent: .neutral)
            XCTAssertEqual(game.fighters[0].weaponPose?.clip, catalog.profile(for: first)?.clip(command: .weapon)?.name)
            XCTAssertTrue(game.projectiles.isEmpty)
            XCTAssertNil(game.grapple)
        }
    }

    func testFightCannotStartWithAnInvalidSameEquipmentCatalog() throws {
        let duplicated = try Fixture.changing(Fixture.catalog()) { profiles in
            profiles[1]["weaponID"] = profiles[0]["weaponID"]
        }
        let fighters = [DuelGame.Fighter(hero: .ember, x: 3500, facing: 1),
                        DuelGame.Fighter(hero: .liu, x: 4300, facing: -1)]
        XCTAssertNil(DuelWeaponFight(fighters: fighters, mode: .practice, difficulty: .learning,
                                    catalog: duplicated, seed: 4))
        XCTAssertNil(DuelWeaponFight(fighters: [fighters[0], fighters[0]], mode: .practice, difficulty: .learning,
                                    catalog: Fixture.catalog(), seed: 4))
        var blocked = DuelGame(hero: .ember, mode: .practice, weaponCatalog: duplicated)
        XCTAssertNil(blocked.weaponFight)
        let before = blocked.fighters
        for _ in 0..<30 { blocked.step(.init(move: 1, taps: .light, weaponCommand: .weapon), opponent: .neutral) }
        XCTAssertEqual(blocked.fighters, before, "Invalid source equipment must not silently run the shared laboratory combat")
        XCTAssertEqual(blocked.frame, 0)
    }

    func testMovingWeaponSegmentMakesOneContactAndUpdatesDamage() throws {
        var fight = try Fixture.fight()
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        XCTAssertEqual(fight.landedHits, [0, 0])
        XCTAssertNil(fight.attackBox(0), "Startup cannot damage before the active window")
        var contact: DuelWeaponFight.Contact?
        for _ in 0..<24 {
            fight.step(.neutral, opponent: .neutral)
            if let hit = fight.contacts.first { contact = hit }
        }
        XCTAssertEqual(contact?.attacker, 0)
        XCTAssertEqual(contact?.kind, .hit)
        XCTAssertEqual(fight.landedHits, [1, 0])
        XCTAssertGreaterThan(fight.damageDealt[0], 0)
        XCTAssertEqual(1000 - fight.fighters[1].health, fight.damageDealt[0])
    }

    func testEmptyCornerOfDiagonalWeaponAABBCannotDamageTheTorso() throws {
        var fight = try Fixture.fight(catalog: Fixture.catalog(stroke: .emptyCorner))
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        var boundingBoxesOverlapped = false
        for _ in 0..<24 {
            fight.step(.neutral, opponent: .neutral)
            if let box = fight.attackBox(0), box.overlaps(fight.hurtBox(1)) { boundingBoxesOverlapped = true }
            XCTAssertTrue(fight.contacts.isEmpty)
        }
        XCTAssertTrue(boundingBoxesOverlapped, "The fixture must exercise an empty corner inside the broad AABB")
        XCTAssertEqual(fight.fighters[1].health, 1000)
        XCTAssertEqual(fight.landedHits, [0, 0])
    }

    func testPauseCancellationDropsARecoveryQueueWithoutUndoingTheCurrentAttack() throws {
        var fight = try Fixture.fight(distance: 3000)
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        fight.step(.init(weaponCommand: .kick), opponent: .neutral)
        var uncancelled = fight
        let current = fight.fighters[0].weaponPose
        fight.cancelBufferedInputs()
        XCTAssertEqual(fight.fighters[0].weaponPose, current)
        let kick = try XCTUnwrap(fight.profiles[0].clip(command: .kick)?.name)
        var baselinePlayedKick = false
        for _ in 0..<40 {
            fight.step(.neutral, opponent: .neutral)
            uncancelled.step(.neutral, opponent: .neutral)
            XCTAssertNotEqual(fight.fighters[0].weaponPose?.clip, kick)
            baselinePlayedKick = baselinePlayedKick || uncancelled.fighters[0].weaponPose?.clip == kick
        }
        XCTAssertTrue(baselinePlayedKick, "The test must cancel a real buffered move")
    }

    func testComboAnchorContinuesSourceTimeWithoutReplayingTheSharedStrikePrefix() throws {
        let catalog = try Fixture.changing(Fixture.catalog()) { profiles in
            profiles[0]["comboLinks"] = [["from": "katana_weapon", "to": "katana_weapon2", "sourceFrame": 4]]
        }
        var fight = try Fixture.fight(catalog: catalog)
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        XCTAssertEqual(fight.fighters[0].weaponPose?.clip, "katana_weapon")
        XCTAssertEqual(fight.fighters[0].weaponPose?.tick, 1, "The second press is queued before the common source pose")
        var continuationTicks: [Int] = []
        for _ in 0..<48 {
            fight.step(.neutral, opponent: .neutral)
            if let pose = fight.fighters[0].weaponPose, pose.clip == "katana_weapon2" {
                continuationTicks.append(pose.tick)
            }
        }
        XCTAssertEqual(continuationTicks.first, 8, "A source-frame 4 anchor must continue at simulation tick 8")
        XCTAssertTrue(continuationTicks.allSatisfy { $0 >= 8 }, "The shared prefix must never restart at tick zero")
        XCTAssertEqual(continuationTicks, continuationTicks.sorted())
        XCTAssertEqual(fight.landedHits[0], 1,
                       "These synthetic clips share the same single strike; linking must not hit again by replaying its prefix")
        XCTAssertEqual(fight.fighters[1].health, 1000 - fight.damageDealt[0])
    }

    func testStationaryGuardBlocksButForwardWalkingDoesNotCreateAFreeBlock() throws {
        var guarded = try Fixture.fight(), walking = try Fixture.fight()
        guarded.step(.init(weaponCommand: .weapon), opponent: .init(guardHeld: true))
        walking.step(.init(weaponCommand: .weapon), opponent: .init(move: -1, guardHeld: true))
        var guardedContact: DuelWeaponFight.Contact?, movingContact: DuelWeaponFight.Contact?
        for _ in 0..<12 {
            guarded.step(.neutral, opponent: .init(guardHeld: true))
            walking.step(.neutral, opponent: .init(move: -1, guardHeld: true))
            if let contact = guarded.contacts.first { guardedContact = contact }
            if let contact = walking.contacts.first { movingContact = contact }
        }
        XCTAssertEqual(guardedContact?.kind, .block)
        XCTAssertEqual(movingContact?.kind, .hit)
        XCTAssertEqual(guarded.landedHits[0], 0)
        XCTAssertEqual(walking.landedHits[0], 1)
        XCTAssertGreaterThan(guarded.fighters[1].health, walking.fighters[1].health)
    }

    func testBackGuardBlocksSourceContactsForEitherFacingWithoutNeutralAutoGuard() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            for facing in [1, -1] {
                let other: DuelGame.Hero = hero == .ember ? .liu : .ember
                let fighters = [DuelGame.Fighter(hero: hero, x: 5000, facing: facing),
                                DuelGame.Fighter(hero: other, x: 5000 + facing * 800, facing: -facing)]
                var fight = try XCTUnwrap(DuelWeaponFight(fighters: fighters, mode: .practice,
                    difficulty: .learning, catalog: Fixture.catalog(), seed: 7))
                var input = DuelWeaponInput()
                input.direction(x: facing, y: 0) // The defender's Back direction.
                fight.step(.init(weaponCommand: .weapon), opponent: input.consume(facing: -facing, airborne: false))
                var blocks = 0
                for _ in 0..<40 {
                    fight.step(.neutral, opponent: input.consume(facing: -facing, airborne: false))
                    blocks += fight.contacts.filter { $0.kind == .block }.count
                }
                XCTAssertEqual(blocks, 1)
                XCTAssertGreaterThan(fight.fighters[1].health, 980)
                input.direction(x: 0, y: 0)
                fight.step(.neutral, opponent: input.consume(facing: -facing, airborne: false))
                XCTAssertFalse(fight.fighters[1].guarding)
            }
        }
    }

    func testDamageBudgetRefillsBothShadowMetersBeforeEitherHealthBarRunsOut() throws {
        // Each actual contact is followed by recovery and a fixture re-approach.
        // Preserve health/energy across exchanges; do not award energy for a miss.
        for hero in [DuelGame.Hero.ember, .liu] {
            for command in [DuelWeaponCommand.weapon, .heavy, .kick] {
                let other: DuelGame.Hero = hero == .ember ? .liu : .ember
                var fighters = [DuelGame.Fighter(hero: hero, x: 3500, facing: 1),
                                DuelGame.Fighter(hero: other, x: 4300, facing: -1)]
                fighters[0].energy = 0; fighters[1].energy = 0
                var contacts = 0
                for _ in 0..<10 {
                    var fight = try XCTUnwrap(DuelWeaponFight(fighters: fighters, mode: .versus,
                        difficulty: .learning, catalog: Fixture.catalog(), seed: 7))
                    fight.step(.init(weaponCommand: command), opponent: .neutral)
                    for _ in 0..<90 {
                        fight.step(.neutral, opponent: .neutral)
                        contacts += fight.contacts.count
                    }
                    XCTAssertEqual(fight.phase, .fighting)
                    fighters = fight.fighters
                    if fighters.allSatisfy({ $0.energy == 100 }) {
                        XCTAssertGreaterThanOrEqual(fighters[1].health, 400, "Both weapons must unlock shadow while substantial health remains")
                        break
                    }
                    fighters[0].x = 3500; fighters[1].x = 4300
                }
                XCTAssertGreaterThan(contacts, 0)
                XCTAssertEqual(fighters.map(\.energy), [100, 100], "\(hero)/\(command)")
            }
        }
    }

    func testHeldGuardReturnsOnTheFirstReadyTickForBothWeapons() throws {
        let catalog = Fixture.catalog()
        for hero in [DuelGame.Hero.ember, .liu] {
            let other: DuelGame.Hero = hero == .ember ? .liu : .ember
            var fight = try XCTUnwrap(DuelWeaponFight(
                fighters: [.init(hero: hero, x: 3500, facing: 1),
                           .init(hero: other, x: 6500, facing: -1)],
                mode: .practice, difficulty: .learning, catalog: catalog, seed: 4))
            let duration = try XCTUnwrap(fight.profiles[0].clip(command: .weapon)?.ticks)
            fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
            for _ in 0..<duration {
                fight.step(.init(guardHeld: true), opponent: .neutral)
                XCTAssertNotNil(fight.fighters[0].attack)
                XCTAssertFalse(fight.fighters[0].guarding, "Guard must not cancel source recovery")
            }
            fight.step(.init(guardHeld: true), opponent: .neutral)
            XCTAssertNil(fight.fighters[0].attack)
            XCTAssertTrue(fight.fighters[0].guarding, "No extra vulnerable idle frame after recovery")
        }
    }

    func testRecoveryBoundaryAppliesMovementAndCrouchWithoutAnIdleTick() throws {
        for input in [DuelGame.Input(move: 1, guardHeld: true), .init(guardHeld: true, vertical: -1)] {
            var fight = try Fixture.fight(distance: 3000)
            let duration = try XCTUnwrap(fight.profiles[0].clip(command: .weapon)?.ticks)
            fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
            for _ in 0..<duration { fight.step(.neutral, opponent: .neutral) }
            fight.step(input, opponent: .neutral)
            XCTAssertNil(fight.fighters[0].attack)
            XCTAssertFalse(fight.fighters[0].guarding)
            if input.move != 0 {
                XCTAssertTrue(fight.fighters[0].walking)
                XCTAssertEqual(fight.fighters[0].movementDirection, 1)
            } else {
                XCTAssertEqual(fight.fighters[0].weaponPose?.clip, fight.profiles[0].roles["crouch"])
            }
        }
    }

    func testBufferedFollowUpStillTakesPriorityOverHeldGuardAtRecovery() throws {
        var fight = try Fixture.fight(distance: 3000)
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        fight.step(.init(weaponCommand: .kick), opponent: .neutral)
        let duration = try XCTUnwrap(fight.profiles[0].clip(command: .weapon)?.ticks)
        for _ in 1..<duration { fight.step(.init(guardHeld: true), opponent: .neutral) }
        fight.step(.init(guardHeld: true), opponent: .neutral)
        XCTAssertEqual(fight.fighters[0].weaponPose?.clip, fight.profiles[0].clip(command: .kick)?.name)
        XCTAssertEqual(fight.fighters[0].weaponPose?.tick, 0)
        XCTAssertFalse(fight.fighters[0].guarding)
    }

    func testDirectionalAerialKickDoesNotRequireAGroundDirectionalClip() throws {
        var fight = try Fixture.fight(distance: 3000)
        XCTAssertFalse(fight.supports(.kickUp, index: 0))
        fight.step(.init(taps: .jump), opponent: .neutral)
        for _ in 0..<4 { fight.step(.neutral, opponent: .neutral) }
        fight.step(.init(weaponCommand: .kickUp), opponent: .neutral)
        XCTAssertEqual(fight.fighters[0].weaponPose?.clip, fight.profiles[0].roles["kickJump"])
    }

    func testHitReactionRecoveryImmediatelyRestoresHeldDefense() throws {
        var fight = try Fixture.fight()
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        for _ in 0..<12 where fight.hitStop == 0 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertTrue(fight.fighters[1].weaponPose?.reaction == true)
        var recovered = false
        for _ in 0..<40 {
            fight.step(.neutral, opponent: .init(guardHeld: true))
            if fight.fighters[1].weaponPose?.reaction == false {
                recovered = true
                XCTAssertTrue(fight.fighters[1].guarding)
                XCTAssertEqual(fight.fighters[1].stun, 0)
                break
            }
            XCTAssertFalse(fight.fighters[1].guarding)
        }
        XCTAssertTrue(recovered)
    }

    func testUnsupportedCommandsCannotPoisonTheRecoveryBuffer() throws {
        let catalog = try Fixture.changing(Fixture.catalog()) { profiles in
            var roles = profiles[0]["roles"] as! [String: String]
            roles.removeValue(forKey: "shadow"); profiles[0]["roles"] = roles
        }
        for unavailable in [DuelWeaponCommand.shadow, .ranged] {
            var fight = try Fixture.fight(catalog: catalog, distance: 3000)
            XCTAssertFalse(fight.canUse(unavailable, index: 0))
            fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
            fight.step(.init(weaponCommand: unavailable), opponent: .neutral)
            fight.step(.init(weaponCommand: .kick), opponent: .neutral)
            let kick = fight.profiles[0].clip(command: .kick)?.name
            var playedKick = false
            for _ in 0..<40 {
                fight.step(.neutral, opponent: .neutral)
                playedKick = playedKick || fight.fighters[0].weaponPose?.clip == kick
            }
            XCTAssertTrue(playedKick, "An unavailable action must leave the buffer free for a valid press")
        }
    }

    func testUnsupportedHitStopPressLeavesRoomForAValidFollowUp() throws {
        var fight = try Fixture.fight()
        fight.step(.init(weaponCommand: .heavy), opponent: .neutral)
        for _ in 0..<80 where fight.hitStop == 0 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertGreaterThanOrEqual(fight.hitStop, 2)
        fight.step(.init(weaponCommand: .ranged), opponent: .neutral)
        fight.step(.init(weaponCommand: .kick), opponent: .neutral)
        let kick = fight.profiles[0].clip(command: .kick)?.name
        var playedKick = false
        for _ in 0..<40 {
            fight.step(.neutral, opponent: .neutral)
            playedKick = playedKick || fight.fighters[0].weaponPose?.clip == kick
        }
        XCTAssertTrue(playedKick)
    }

    func testJumpAnimationAloneNeverBecomesAnAttack() throws {
        var fight = try Fixture.fight()
        fight.step(.init(taps: .jump), opponent: .neutral)
        XCTAssertEqual(fight.events, [.jumped(player: 0)])
        var leftGround = false
        for _ in 0..<24 {
            fight.step(.neutral, opponent: .neutral)
            leftGround = leftGround || fight.isAirborne(0)
            XCTAssertNil(fight.attackBox(0))
            XCTAssertTrue(fight.contacts.isEmpty)
        }
        XCTAssertTrue(leftGround)
        XCTAssertEqual(fight.landedHits, [0, 0])
        XCTAssertEqual(fight.fighters[1].health, 1000)
    }

    func testAerialKickConsumesLaterAirborneButtonsWithoutReplayingOnLanding() throws {
        var fight = try Fixture.fight(distance: 3000)
        fight.step(.init(taps: .jump), opponent: .neutral)
        for _ in 0..<4 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertTrue(fight.isAirborne(0))
        fight.step(.init(weaponCommand: .kick), opponent: .neutral)
        XCTAssertEqual(fight.fighters[0].weaponPose?.clip, fight.profiles[0].roles["kickJump"])
        XCTAssertTrue(fight.isAirborne(0))
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        let weapon = fight.profiles[0].clip(command: .weapon)?.name
        let groundKick = fight.profiles[0].clip(command: .kick)?.name
        for _ in 0..<40 {
            fight.step(.neutral, opponent: .neutral)
            XCTAssertNotEqual(fight.fighters[0].weaponPose?.clip, weapon)
            XCTAssertNotEqual(fight.fighters[0].weaponPose?.clip, groundKick)
        }
        XCTAssertFalse(fight.isAirborne(0))
    }

    func testUnavailableAerialAttackIsConsumedInsteadOfSavedUntilLanding() throws {
        for command in [DuelWeaponCommand.weapon, .kick] {
            var fight = try Fixture.fight(catalog: Fixture.catalog(aerialKick: false), distance: 3000)
            fight.step(.init(taps: .jump), opponent: .neutral)
            for _ in 0..<4 { fight.step(.neutral, opponent: .neutral) }
            XCTAssertTrue(fight.isAirborne(0))
            fight.step(.init(weaponCommand: command), opponent: .neutral)
            let ground = fight.profiles[0].clip(command: command)?.name
            for _ in 0..<40 {
                fight.step(.neutral, opponent: .neutral)
                XCTAssertNotEqual(fight.fighters[0].weaponPose?.clip, ground)
            }
        }
    }

    func testHitStopFreezesPoseAndTimerAndItsBufferedButtonCanBeCancelled() throws {
        var fight = try Fixture.fight()
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        for _ in 0..<12 where fight.hitStop == 0 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertGreaterThan(fight.hitStop, 0)
        let pose = fight.fighters[0].weaponPose, health = fight.fighters[1].health
        let timer = fight.remainingTicks, frame = fight.frame, freeze = fight.hitStop
        fight.step(.init(weaponCommand: .kick), opponent: .neutral)
        XCTAssertEqual(fight.fighters[0].weaponPose, pose)
        XCTAssertEqual(fight.fighters[1].health, health)
        XCTAssertEqual(fight.remainingTicks, timer)
        XCTAssertEqual(fight.frame, frame + 1)
        XCTAssertEqual(fight.hitStop, freeze - 1)
        fight.cancelBufferedInputs()
        let kick = fight.profiles[0].clip(command: .kick)?.name
        for _ in 0..<40 {
            fight.step(.neutral, opponent: .neutral)
            XCTAssertNotEqual(fight.fighters[0].weaponPose?.clip, kick)
        }
        XCTAssertEqual(fight.landedHits[0], 1)
    }

    func testRoundBreakClearsPendingMovesAndResetsBothIndependentProfiles() throws {
        var fight = try Fixture.fight(mode: .versus, opponentHealth: 1)
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        for _ in 0..<12 where fight.phase == .fighting { fight.step(.neutral, opponent: .neutral) }
        guard case .roundBreak(let winner, let ticks) = fight.phase else { return XCTFail("Expected the first round to end") }
        XCTAssertEqual(winner, 0)
        XCTAssertEqual(fight.wins, [1, 0])
        XCTAssertEqual(fight.hitStop, 0)
        for _ in 0..<ticks { fight.step(.init(weaponCommand: .heavy), opponent: .neutral) }
        XCTAssertEqual(fight.phase, .fighting)
        XCTAssertEqual(fight.remainingTicks, 3600)
        XCTAssertEqual(fight.fighters.map(\.health), [1000, 1000])
        XCTAssertEqual(fight.fighters.map(\.hero), [.ember, .liu])
        fight.step(.neutral, opponent: .neutral)
        for index in 0..<2 {
            XCTAssertEqual(fight.fighters[index].weaponPose?.clip, fight.profiles[index].roles["idle"])
            XCTAssertNil(fight.fighters[index].attack)
        }
    }
}
