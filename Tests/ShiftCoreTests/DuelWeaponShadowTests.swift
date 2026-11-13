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
                // This fixture releases at source X=0.4 m. Its former
                // absolute apex stays at X=5.25 m, across 23 intervals.
                if let last { XCTAssertLessThanOrEqual(abs(point.x - last.x), 4.85 / 23 + 0.0000001) }
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

    private func anchoredCatalog(movingOpponent: Bool = false) throws -> DuelWeaponCatalog {
        try DuelWeaponTestFixtures.changing(DuelWeaponTestFixtures.catalog()) { profiles in
            var clips = profiles[1]["clips"] as! [[String: Any]]
            let index = clips.firstIndex { $0["name"] as? String == "hammers_heavy" }!
            var tracks = clips[index]["tracks"] as! [String: Any]
            let count = 2 * DuelWeaponTestFixtures.frames - 1
            var bases: [[Double]] = [], tips: [[Double]] = [], lift: [Double] = []
            for sample in 0..<count {
                let p = Double(sample) / Double(count - 1)
                let base = [0.15 + 0.5 * p, 0.65 + 0.3 * p, 0.12 + 0.04 * p]
                bases.append(base)
                tips.append([base[0] + 0.4 * (1 - 2 * p), base[1] + 0.25 - 0.1 * p, base[2] + 0.1])
                lift.append(0.07 + 0.03 * p)
            }
            tracks["weaponBaseR"] = bases; tracks["weaponTipR"] = tips; tracks["groundLift"] = lift
            clips[index]["tracks"] = tracks; profiles[1]["clips"] = clips
            if movingOpponent {
                var opponentClips = profiles[0]["clips"] as! [[String: Any]]
                let idle = opponentClips.firstIndex { $0["name"] as? String == "katana_idle" }!
                var walk = opponentClips[idle]["tracks"] as! [String: Any]
                walk["root"] = (0..<count).map { [Double($0) * 0.02, 0.0, 0.0] }
                opponentClips[idle]["tracks"] = walk; profiles[0]["clips"] = opponentClips
            }
        }
    }

    private func heldPoints(_ game: DuelWeaponFight) throws -> DuelShadowRules.HammerSegment {
        let fighter = game.fighters[0], pose = try XCTUnwrap(fighter.weaponPose)
        let clip = try XCTUnwrap(game.profiles[0].clip(named: pose.clip))
        func world(_ point: DuelWeaponPoint) -> DuelWeaponPoint {
            .init(x: Double(fighter.x) / 1000 + point.x * Double(fighter.facing),
                  y: point.y + pose.groundLift, z: point.z * Double(fighter.facing))
        }
        return .init(base: world(clip.tracks.sample(clip.tracks.weaponBaseR, phase: pose.phase)),
                     tip: world(clip.tracks.sample(clip.tracks.weaponTipR, phase: pose.phase)))
    }

    private func equalPoint(_ a: DuelWeaponPoint, _ b: DuelWeaponPoint,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 0.000000001, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 0.000000001, file: file, line: line)
        XCTAssertEqual(a.z, b.z, accuracy: 0.000000001, file: file, line: line)
    }

    func testHammerReleaseAndCatchMatchActualMappedHeldPoseInBothDirections() throws {
        for direction in [1, -1] {
            var game = try fight(.liu, direction: direction, distance: 6000, catalog: anchoredCatalog())
            let origin = game.fighters[0].x
            game.step(.init(weaponCommand: .shadow), opponent: .neutral)
            var seen = Set<Int>(), apex: DuelWeaponPoint?
            for _ in 0..<100 {
                if let visual = game.shadowVisual(0) {
                    let held = try heldPoints(game)
                    if let base = visual.weaponBase, let tip = visual.weaponTip {
                        XCTAssertEqual(DuelShadowRules.distance(base, tip),
                                       DuelShadowRules.distance(held.base, held.tip), accuracy: 0.000000001)
                        if visual.tick == 24 || visual.tick == 71 {
                            equalPoint(base, held.base); equalPoint(tip, held.tip); seen.insert(visual.tick)
                        }
                        if visual.tick == 47 {
                            equalPoint(base, .init(x: Double(min(DuelGame.rightWall,
                                max(DuelGame.leftWall, origin + direction * 5250))) / 1000, y: 0.82, z: 0.08))
                            XCTAssertEqual(tip.x, base.x, accuracy: 0.000000001)
                            XCTAssertGreaterThan(tip.y, base.y); apex = base
                        }
                        if visual.tick == 48 { equalPoint(base, try XCTUnwrap(apex)) }
                        if visual.tick >= 48 {
                            XCTAssertFalse(visual.isAttacking); XCTAssertNil(game.attackBox(0))
                            XCTAssertTrue(game.contacts.isEmpty); XCTAssertTrue(game.swings.isEmpty)
                        }
                    }
                    if visual.tick == 23 || visual.tick == 72 {
                        XCTAssertNil(visual.weaponBase); XCTAssertNil(visual.weaponTip); seen.insert(visual.tick)
                    }
                }
                game.step(.neutral, opponent: .neutral)
            }
            XCTAssertEqual(seen, [23, 24, 71, 72]); XCTAssertEqual(game.landedHits, [0, 0])
        }
    }

    func testHammerAxisAndWallCorridorKeepLengthIncludingAntiparallelAnchors() throws {
        for direction in [1, -1] {
            let origin = direction > 0 ? 9000 : 1000
            for axis in [DuelWeaponPoint(x: 0.6), .init(y: -0.6), .init(x: 0.000001, y: -0.6)] {
                func mirrored(_ p: DuelWeaponPoint) -> DuelWeaponPoint {
                    .init(x: direction > 0 ? p.x : 10 - p.x, y: p.y, z: p.z * Double(direction))
                }
                let release = DuelShadowRules.HammerSegment(base: mirrored(.init(x: 9.3, y: 1, z: 0.1)),
                    tip: mirrored(.init(x: 9.3 + axis.x, y: 1 + axis.y, z: 0.1 + axis.z)))
                let catchPose = DuelShadowRules.HammerSegment(base: mirrored(.init(x: 9.1, y: 1.2, z: 0.15)),
                    tip: mirrored(.init(x: 9.1 + axis.x, y: 1.2 + axis.y, z: 0.15 + axis.z)))
                let sourceLength = DuelShadowRules.distance(release.base, release.tip)
                var previous: DuelShadowRules.HammerSegment?
                for tick in 24..<72 {
                    let length = sourceLength + 0.15 * sin(.pi * Double(tick - 24) / 47)
                    let value = try XCTUnwrap(DuelShadowRules.hammer(tick, origin: origin, direction: direction,
                        release: release, catchPose: catchPose, length: length))
                    XCTAssertTrue(DuelShadowRules.valid(value))
                    XCTAssertEqual(DuelShadowRules.distance(value.base, value.tip), length, accuracy: 0.000000001)
                    let held = tick < 48 ? release : catchPose
                    let apex = Double(direction > 0 ? DuelGame.rightWall : DuelGame.leftWall) / 1000
                    for point in [value.base, value.tip] {
                        if direction > 0 { XCTAssertLessThanOrEqual(point.x, max(apex, held.base.x, held.tip.x) + 0.000000001) }
                        else { XCTAssertGreaterThanOrEqual(point.x, min(apex, held.base.x, held.tip.x) - 0.000000001) }
                    }
                    if let previous {
                        XCTAssertLessThan(DuelShadowRules.distance(previous.base, value.base), 0.2)
                        XCTAssertLessThan(DuelShadowRules.distance(previous.tip, value.tip), 0.2)
                    }
                    if tick == 24 { equalPoint(value.base, release.base); equalPoint(value.tip, release.tip) }
                    if tick == 71 { equalPoint(value.base, catchPose.base); equalPoint(value.tip, catchPose.tip) }
                    previous = value
                }
            }
        }
    }

    func testHammerContactUsesActualSegmentsAndRejectsEmptyCornersAndDiscontinuities() throws {
        typealias Segment = DuelShadowRules.HammerSegment
        let hurt = DuelGame.Box(minX: 800, maxX: 1200, minY: 400, maxY: 1200)
        let old = Segment(base: .init(x: 0, y: 0), tip: .init(x: 0.5, y: 3.2))
        let now = Segment(base: .init(x: 0.16, y: 0), tip: .init(x: 0.66, y: 3.2))
        XCTAssertTrue(DuelGame.Box(minX: -180, maxX: 840, minY: -180, maxY: 3380).overlaps(hurt))
        XCTAssertNil(DuelShadowRules.hammerContact(previous: old, current: now, sweep: true, hurt: hurt))

        let reverse = Segment(base: .init(x: 1, y: 1.4, z: 0.15), tip: .init(x: 1, y: 0.7, z: 0.15))
        let prior = Segment(base: .init(x: 0.8, y: 1.4, z: 0.15), tip: .init(x: 0.8, y: 0.7, z: 0.15))
        let contact = try XCTUnwrap(DuelShadowRules.hammerContact(previous: prior, current: reverse, sweep: true,
            hurt: .init(minX: 900, maxX: 1100, minY: 800, maxY: 1000)))
        equalPoint(contact, .init(x: 1, y: 1, z: 0.15))

        let left = Segment(base: .init(x: 0, y: 0), tip: .init(x: 0, y: 2))
        let right = Segment(base: .init(x: 0.6, y: 0), tip: .init(x: 0.6, y: 2))
        let inside = DuelGame.Box(minX: 250, maxX: 350, minY: 800, maxY: 1200)
        XCTAssertNil(DuelShadowRules.hammerContact(previous: left, current: right, sweep: false, hurt: inside))
        XCTAssertNotNil(DuelShadowRules.hammerContact(previous: left, current: right, sweep: true, hurt: inside))
        let jumped = Segment(base: .init(x: 1, y: 0), tip: .init(x: 1, y: 2))
        XCTAssertNil(DuelShadowRules.hammerContact(previous: left, current: jumped, sweep: true, hurt: hurt))
        let offPlane = Segment(base: .init(x: 1, y: 1.4, z: 0.81), tip: .init(x: 1, y: 0.7, z: 0.81))
        XCTAssertNil(DuelShadowRules.hammerContact(previous: offPlane, current: offPlane, sweep: true, hurt: hurt))

        // Both endpoints move less than 0.75 m, yet the swept surface folds
        // outside its boundary polygon's even/odd interior. The midpoint
        // shaft contains (3.1875, 0.1875), inside this actual hurt rectangle.
        let foldedBefore = Segment(base: .init(x: 3, y: 0, z: 0.08), tip: .init(x: 3, y: 0.749, z: 0.08))
        let foldedNow = Segment(base: .init(x: 3.749, y: 0.001, z: 0.08), tip: .init(x: 3.001, y: 0, z: 0.08))
        let foldedHurt = DuelGame.Box(minX: 3186, maxX: 3726, minY: 186, maxY: 1666)
        XCTAssertLessThan(DuelShadowRules.distance(foldedBefore.base, foldedNow.base), 0.75)
        XCTAssertLessThan(DuelShadowRules.distance(foldedBefore.tip, foldedNow.tip), 0.75)
        XCTAssertNotNil(DuelShadowRules.hammerContact(previous: foldedBefore, current: foldedNow,
                                                     sweep: true, hurt: foldedHurt))
        // The reflected fold has the same contact; no privileged positive-X
        // quadratic root or a filled broad hull may decide it.
        func mirror(_ p: DuelWeaponPoint) -> DuelWeaponPoint { .init(x: 10 - p.x, y: p.y, z: p.z) }
        XCTAssertNotNil(DuelShadowRules.hammerContact(
            previous: .init(base: mirror(foldedBefore.base), tip: mirror(foldedBefore.tip)),
            current: .init(base: mirror(foldedNow.base), tip: mirror(foldedNow.tip)), sweep: true,
            hurt: .init(minX: 6274, maxX: 6814, minY: 186, maxY: 1666)))

        // A true double root: at t=0.5 the shaft from (0.35,0) to
        // (0,0.35) only touches expanded corner (0.175,0.175).
        XCTAssertNotNil(DuelShadowRules.hammerContact(
            previous: .init(base: .init(), tip: .init(y: 0.7)),
            current: .init(base: .init(x: 0.7), tip: .init()), sweep: true,
            hurt: .init(minX: 355, maxX: 895, minY: 355, maxY: 1835)))
        let almostParallel = Segment(base: .init(x: 0.6), tip: .init(x: 0.6, y: 2.000000001))
        XCTAssertNotNil(DuelShadowRules.hammerContact(previous: left, current: almostParallel, sweep: true, hurt: inside))
        // Supporting-line corner roots lie above this short shaft. Rechecking
        // the finite segment must reject them instead of reporting a ghost hit.
        XCTAssertNil(DuelShadowRules.hammerContact(
            previous: .init(base: .init(), tip: .init(y: 0.1)),
            current: .init(base: .init(x: 0.6), tip: .init(x: 0.6, y: 0.1)), sweep: true, hurt: inside))
    }

    func testInvalidHammerAnchorsFailClosedWithoutFixedPathFallback() throws {
        typealias Segment = DuelShadowRules.HammerSegment
        let valid = Segment(base: .init(x: 3, y: 1), tip: .init(x: 3.5, y: 1))
        for bad in [Segment(base: .init(x: 3, y: 1), tip: .init(x: 3, y: 1)),
                    Segment(base: .init(x: .nan), tip: .init(x: 3.5, y: 1)),
                    Segment(base: .init(x: 1e300), tip: .init(x: 1e300, y: 1))] {
            XCTAssertNil(DuelShadowRules.hammer(24, origin: 2500, direction: 1, release: bad, catchPose: valid, length: 0.5))
            XCTAssertNil(DuelShadowRules.hammer(71, origin: 2500, direction: 1, release: valid, catchPose: bad, length: 0.5))
        }
        for length in [0, Double.nan, Double.infinity, 1e300] {
            XCTAssertNil(DuelShadowRules.hammer(35, origin: 2500, direction: 1, release: valid, catchPose: valid, length: length))
        }
        for badX in [0.0, 1e300] {
            let catalog = try DuelWeaponTestFixtures.changing(DuelWeaponTestFixtures.catalog()) { profiles in
                var clips = profiles[1]["clips"] as! [[String: Any]]
                let index = clips.firstIndex { $0["name"] as? String == "hammers_heavy" }!
                var tracks = clips[index]["tracks"] as! [String: Any]
                let values = Array(repeating: [badX, 1.0, 0.0], count: 2 * DuelWeaponTestFixtures.frames - 1)
                tracks["weaponBaseR"] = values; tracks["weaponTipR"] = values
                clips[index]["tracks"] = tracks; profiles[1]["clips"] = clips
            }
            var game = try fight(.liu, distance: 800, catalog: catalog)
            game.step(.init(weaponCommand: .shadow), opponent: .neutral)
            for _ in 0..<100 {
                if let visual = game.shadowVisual(0) {
                    XCTAssertNil(visual.weaponBase); XCTAssertNil(visual.weaponTip); XCTAssertFalse(visual.isAttacking)
                    XCTAssertNil(game.attackBox(0)); XCTAssertFalse(game.weaponTrailIsActive(0))
                }
                XCTAssertTrue(game.contacts.isEmpty)
                game.step(.neutral, opponent: .neutral)
            }
            XCTAssertEqual(game.landedHits[0], 0)
        }
    }

    func testHammerReleaseOriginFreezesAfterPushAndReturnTracksCurrentHandWithReplay() throws {
        let catalog = try anchoredCatalog(movingOpponent: true)
        for direction in [1, -1] {
            let caster = DuelGame.Fighter(hero: .liu, x: direction > 0 ? 4500 : 5500, facing: direction)
            var opponent = DuelGame.Fighter(hero: .ember, x: caster.x + direction * DuelGame.bodyWidth, facing: -direction)
            opponent.invulnerable = 1000 // Isolate body pushes from contact hit-stop.
            var host = try XCTUnwrap(DuelWeaponFight(fighters: [caster, opponent], mode: .practice,
                difficulty: .learning, catalog: catalog, seed: 47))
            var replay = host
            var release: DuelShadowRules.HammerSegment?, releaseX: Int?
            var sawPushedAfterRelease = false, sawCatch = false
            for frame in 0..<110 {
                let input = DuelGame.Input(weaponCommand: frame == 0 ? .shadow : nil)
                let push = DuelGame.Input(move: -direction)
                host.step(input, opponent: push); replay.step(input, opponent: push)
                XCTAssertEqual(host, replay)
                XCTAssertEqual(try DuelReplayStateEncoding.encode(host), try DuelReplayStateEncoding.encode(replay))
                guard let visual = host.shadowVisual(0) else { continue }
                if visual.tick == 24 {
                    let held = try heldPoints(host)
                    equalPoint(try XCTUnwrap(visual.weaponBase), held.base)
                    equalPoint(try XCTUnwrap(visual.weaponTip), held.tip)
                    release = held; releaseX = host.fighters[0].x
                    XCTAssertNotEqual(releaseX, caster.x)
                }
                if visual.tick == 25 {
                    let origin = try XCTUnwrap(releaseX), held = try XCTUnwrap(release)
                    XCTAssertNotEqual(host.fighters[0].x, origin); sawPushedAfterRelease = true
                    let apex = DuelWeaponPoint(x: Double(min(DuelGame.rightWall,
                        max(DuelGame.leftWall, origin + direction * 5250))) / 1000, y: 0.82, z: 0.08)
                    equalPoint(try XCTUnwrap(visual.weaponBase), held.base.mixed(with: apex, weight: 1.0 / 23))
                }
                if visual.tick == 71 {
                    let held = try heldPoints(host)
                    equalPoint(try XCTUnwrap(visual.weaponBase), held.base)
                    equalPoint(try XCTUnwrap(visual.weaponTip), held.tip); sawCatch = true
                }
                if visual.tick >= 48 { XCTAssertNil(host.attackBox(0)); XCTAssertTrue(host.contacts.isEmpty) }
            }
            XCTAssertTrue(sawPushedAfterRelease); XCTAssertTrue(sawCatch)
        }
    }
}
