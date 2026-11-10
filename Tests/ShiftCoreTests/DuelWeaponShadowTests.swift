import XCTest
@testable import ShiftCore

/// Synthetic fixtures verify the provisional interpreter, not original timing.
final class DuelWeaponShadowTests: XCTestCase {
    private func fight(_ hero: DuelGame.Hero = .ember, direction: Int = 1, distance: Int = 1800,
                       energy: Int = 100, mode: DuelGame.Mode = .practice, health: Int = 1000,
                       catalog: DuelWeaponCatalog = DuelWeaponTestFixtures.catalog()) throws -> DuelWeaponFight {
        var a = DuelGame.Fighter(hero: hero, x: direction == 1 ? 2500 : 7500, facing: direction)
        a.energy = energy
        var b = DuelGame.Fighter(hero: hero == .ember ? .liu : .ember,
                                 x: a.x + direction * distance, facing: -direction)
        b.health = health
        return try XCTUnwrap(DuelWeaponFight(fighters: [a, b], mode: mode,
                                             difficulty: .learning, catalog: catalog, seed: 47))
    }

    func testBothSkillsHaveStartupOneHitRecoveryEnergyAndCooldownInBothDirections() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            for direction in [1, -1] {
                var game = try fight(hero, direction: direction)
                XCTAssertTrue(game.canUse(.shadow, index: 0))
                game.step(.init(weaponCommand: .shadow), opponent: .neutral)
                XCTAssertEqual(game.fighters[0].energy, 0)
                XCTAssertEqual(game.shadowCooldownRemaining(0), 360)
                XCTAssertEqual(game.shadowVisual(0)?.kind, hero == .ember ? .katanaDash : .hammerThrow)
                XCTAssertNil(game.attackBox(0))
                var hits = 0, swings = 0
                for _ in 0..<130 {
                    let priorX = game.fighters[0].x
                    game.step(.init(guardHeld: true), opponent: .neutral)
                    XCTAssertLessThanOrEqual(abs(game.fighters[0].x - priorX), 150)
                    XCTAssertGreaterThanOrEqual((game.fighters[1].x - game.fighters[0].x) * direction, DuelGame.bodyWidth)
                    if let visual = game.shadowVisual(0), visual.tick < 24 {
                        XCTAssertNil(game.attackBox(0)); XCTAssertTrue(game.contacts.isEmpty)
                    }
                    hits += game.contacts.filter { $0.attacker == 0 }.count
                    swings += game.swings.filter { $0.attacker == 0 }.count
                    if let contact = game.contacts.first { XCTAssertEqual(contact.direction, direction) }
                }
                XCTAssertEqual(hits, 1); XCTAssertEqual(swings, 1)
                XCTAssertEqual(game.damageDealt[0], hero == .ember ? 170 : 195)
                XCTAssertEqual(game.fighters[0].energy, 0, "A shadow hit must not refund its own cost")
                XCTAssertNil(game.shadowVisual(0)); XCTAssertNil(game.fighters[0].attack)
                XCTAssertTrue(game.fighters[0].guarding)
                XCTAssertFalse(game.canUse(.shadow, index: 0))
                XCTAssertGreaterThan(game.shadowCooldownRemaining(0), 0)
            }
        }
    }

    func testHammerMovesContinuouslyAndReturnNeverDamagesOrEmitsAnotherSwing() throws {
        var game = try fight(.liu, distance: 6000)
        game.step(.init(weaponCommand: .shadow), opponent: .neutral)
        var last: DuelWeaponPoint?, sawReturn = false
        let initial = game.fighters[0].x
        for _ in 0..<100 {
            game.step(.neutral, opponent: .neutral)
            XCTAssertEqual(game.fighters[0].x, initial)
            if let visual = game.shadowVisual(0), let point = visual.weaponBase {
                if let last { XCTAssertLessThanOrEqual(abs(point.x - last.x), 0.210) }
                last = point
                if visual.tick >= 48 {
                    sawReturn = true
                    XCTAssertFalse(visual.isAttacking); XCTAssertNil(game.attackBox(0))
                    XCTAssertTrue(game.contacts.isEmpty); XCTAssertTrue(game.swings.isEmpty)
                }
            }
        }
        XCTAssertTrue(sawReturn); XCTAssertNil(game.shadowVisual(0))
        XCTAssertEqual(game.landedHits, [0, 0])
    }

    func testShadowCannotRestartOrOccupyBufferWithoutEnergy() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            var game = try fight(hero, energy: 99)
            let initial = game.fighters
            XCTAssertFalse(game.canUse(.shadow, index: 0))
            game.step(.init(weaponCommand: .shadow), opponent: .neutral)
            XCTAssertNil(game.shadowVisual(0)); XCTAssertEqual(game.fighters[0].energy, initial[0].energy)
            XCTAssertEqual(game.shadowCooldownRemaining(0), 0)
            game.step(.init(weaponCommand: .weapon), opponent: .neutral)
            game.step(.init(weaponCommand: .shadow), opponent: .neutral)
            game.step(.init(weaponCommand: .kick), opponent: .neutral)
            var kick = false
            for _ in 0..<35 {
                game.step(.neutral, opponent: .neutral)
                kick = kick || game.fighters[0].weaponPose?.clip == game.profiles[0].roles["kick"]
            }
            XCTAssertTrue(kick)
        }
    }

    func testGuardBlocksBothShadowsAndHitStopFreezesTheirClockAndCooldown() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            var game = try fight(hero)
            game.step(.init(weaponCommand: .shadow), opponent: .init(guardHeld: true))
            for _ in 0..<60 where game.hitStop == 0 { game.step(.neutral, opponent: .init(guardHeld: true)) }
            XCTAssertEqual(game.contacts.first?.kind, .block)
            XCTAssertGreaterThan(game.hitStop, 0)
            let visual = game.shadowVisual(0), cooldown = game.shadowCooldownRemaining(0)
            game.step(.neutral, opponent: .neutral)
            XCTAssertEqual(game.shadowVisual(0), visual)
            XCTAssertEqual(game.shadowCooldownRemaining(0), cooldown)
            XCTAssertTrue(game.contacts.isEmpty); XCTAssertTrue(game.swings.isEmpty)
        }
    }

    func testHitInterruptsWindupWithoutRefundOrDelayedProjectile() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            var game = try fight(hero, distance: 800)
            game.step(.init(weaponCommand: .shadow), opponent: .init(weaponCommand: .weapon))
            var interrupted = false
            for _ in 0..<125 {
                game.step(.neutral, opponent: .neutral)
                if game.fighters[0].weaponPose?.reaction == true { interrupted = true }
                if interrupted { XCTAssertNil(game.shadowVisual(0)); XCTAssertNil(game.attackBox(0)) }
            }
            XCTAssertTrue(interrupted); XCTAssertEqual(game.fighters[0].energy, 5)
            XCTAssertEqual(game.landedHits[0], 0)
        }
    }

    func testEarlyHitStopPressCannotBypassShadowRecoveryBufferWindow() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            var game = try fight(hero)
            game.step(.init(weaponCommand: .shadow), opponent: .neutral)
            for _ in 0..<60 where game.hitStop == 0 { game.step(.neutral, opponent: .neutral) }
            XCTAssertGreaterThan(game.hitStop, 0)
            game.step(.init(weaponCommand: .kick), opponent: .neutral)
            for _ in 0..<130 {
                game.step(.neutral, opponent: .neutral)
                XCTAssertNotEqual(game.fighters[0].weaponPose?.clip, game.profiles[0].roles["kick"])
            }
        }
    }

    func testInterruptionAfterHammerReleaseRemovesItsFutureHitAndReturn() throws {
        let catalog = try DuelWeaponTestFixtures.changing(DuelWeaponTestFixtures.catalog()) { profiles in
            // A long synthetic opponent stroke can reach the caster after
            // release while the projectile is still well short of its target.
            var clips = profiles[0]["clips"] as! [[String: Any]]
            let index = clips.firstIndex { $0["name"] as? String == "katana_weapon" }!
            var tracks = clips[index]["tracks"] as! [String: Any]
            for key in ["weaponBaseR", "weaponTipR"] {
                var points = tracks[key] as! [[Double]]
                for n in points.indices { points[n][0] += 3.3 }
                tracks[key] = points
            }
            clips[index]["tracks"] = tracks; profiles[0]["clips"] = clips
        }
        var game = try fight(.liu, distance: 4000, catalog: catalog)
        game.step(.init(weaponCommand: .shadow), opponent: .neutral)
        for _ in 0..<25 { game.step(.neutral, opponent: .neutral) }
        XCTAssertNotNil(game.shadowVisual(0)?.weaponBase)
        game.step(.neutral, opponent: .init(weaponCommand: .weapon))
        var interrupted = false
        for _ in 0..<120 {
            game.step(.neutral, opponent: .neutral)
            if game.fighters[0].weaponPose?.reaction == true { interrupted = true }
            if interrupted { XCTAssertNil(game.shadowVisual(0)); XCTAssertNil(game.attackBox(0)) }
        }
        XCTAssertTrue(interrupted); XCTAssertEqual(game.landedHits[0], 0)
    }

    func testCooldownExpiresOnlyOnUnpausedSimulationTicks() throws {
        // An intentionally overfilled test fixture isolates cooldown from the
        // separately tested energy gate; real fighters are capped at 100.
        var game = try fight(.liu, distance: 6000, energy: 200)
        game.step(.init(weaponCommand: .shadow), opponent: .neutral)
        for _ in 0..<359 { game.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(game.shadowCooldownRemaining(0), 1)
        XCTAssertFalse(game.canUse(.shadow, index: 0))
        game.step(.neutral, opponent: .neutral)
        XCTAssertEqual(game.shadowCooldownRemaining(0), 0)
        XCTAssertTrue(game.canUse(.shadow, index: 0))
    }

    func testRoundEndAndResetRemoveProjectileAndResetCooldown() throws {
        var game = try fight(.liu, mode: .versus, health: 1)
        game.step(.init(weaponCommand: .shadow), opponent: .neutral)
        for _ in 0..<60 {
            game.step(.neutral, opponent: .neutral)
            if case .roundBreak = game.phase { break }
        }
        guard case .roundBreak = game.phase else { return XCTFail("Shadow should end the round") }
        XCTAssertNil(game.shadowVisual(0)); XCTAssertNil(game.fighters[0].attack)
        for _ in 0..<150 { game.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(game.phase, .fighting)
        XCTAssertEqual(game.shadowCooldownRemaining(0), 0)
        XCTAssertTrue(game.canUse(.shadow, index: 0))
    }

    func testShadowReplayIncludesHiddenOriginCooldownAndCancellation() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            for direction in [1, -1] {
                var host = try fight(hero, direction: direction)
                var replay = host
                for tick in 0..<450 {
                    let input = DuelGame.Input(weaponCommand: tick == 0 ? .shadow : tick == 65 ? .kick : nil)
                    host.step(input, opponent: .neutral); replay.step(input, opponent: .neutral)
                    if tick == 66 { host.cancelBufferedInputs(); replay.cancelBufferedInputs() }
                    XCTAssertEqual(host, replay)
                    XCTAssertEqual(try DuelReplayStateEncoding.encode(host), try DuelReplayStateEncoding.encode(replay))
                }
            }
        }
    }

    func testRawShadowDiscontinuitiesDoNotEnterAnyCollisionOrMovementPath() throws {
        let catalog = try DuelWeaponTestFixtures.changing(DuelWeaponTestFixtures.catalog()) { profiles in
            for i in profiles.indices {
                var clips = profiles[i]["clips"] as! [[String: Any]]
                var shadow = clips.first { ($0["name"] as? String)?.hasSuffix("heavy") == true }!
                shadow["name"] = "unsafe_shadow_\(i)"
                var tracks = shadow["tracks"] as! [String: Any]
                for key in ["root", "weaponBaseR", "weaponTipR"] {
                    var points = tracks[key] as! [[Double]]
                    for n in points.indices { points[n][0] = n % 2 == 0 ? -80 : 80 }
                    tracks[key] = points
                }
                shadow["tracks"] = tracks; clips.append(shadow); profiles[i]["clips"] = clips
                var roles = profiles[i]["roles"] as! [String: String]
                roles["shadow"] = "unsafe_shadow_\(i)"; profiles[i]["roles"] = roles
            }
        }
        for hero in [DuelGame.Hero.ember, .liu] {
            var game = try fight(hero, distance: 6000, catalog: catalog)
            game.step(.init(weaponCommand: .shadow), opponent: .neutral)
            for _ in 0..<120 {
                let x = game.fighters[0].x
                game.step(.neutral, opponent: .neutral)
                XCTAssertLessThanOrEqual(abs(game.fighters[0].x - x), 150)
                XCTAssertFalse(game.fighters[0].weaponPose?.clip.hasPrefix("unsafe_shadow") ?? true)
            }
            XCTAssertEqual(game.landedHits[0], 0)
        }
    }
}
