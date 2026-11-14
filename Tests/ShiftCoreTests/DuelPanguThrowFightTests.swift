import XCTest
@testable import ShiftCore

/// Explicit artificial rules, source-role stand-ins and geometry. This fixture
/// exercises the live interpreter; it never changes the shipped asset catalog.
enum DuelPanguThrowFightFixture {
    static func catalog(pangu: Bool = true, panguRules: DuelPanguRules? = nil,
                        throwRules: DuelWeaponThrowRules = DuelWeaponThrowTestFixture.rules(),
                        enabledHeroes: Set<DuelGame.Hero> = [.ember, .liu],
                        ordinaryDamage: Int = 30) throws -> DuelWeaponCatalog {
        let original = try pangu ? DuelPanguFightFixture.catalog(
            rules: panguRules ?? DuelPanguTestFixture.rules(level: 2), ordinaryDamage: ordinaryDamage) :
            DuelWeaponTestFixtures.catalog()
        let profiles = try original.profiles.map { base -> DuelWeaponProfile in
            let idle = try XCTUnwrap(base.clip(role: "idle"))
            var roles = base.roles, clips = base.clips
            for role in ["throwAttempt", "throwSuccess", "throwMiss", "throwResisted", "throwReceived", "throwEscape"] {
                let name = "synthetic_" + base.id + "_" + role
                roles[role] = name
                clips.append(.init(name: name, frames: idle.frames, sha256: idle.sha256,
                    bundle: "synthetic-ordinary-throw-tests-only", tracks: idle.tracks))
            }
            for (role, direction) in [("walkForward", 1.0), ("walkBackward", -1.0)] {
                let name = "synthetic_" + base.id + "_" + role, t = idle.tracks
                let count = t.root.count
                let root = (0..<count).map { DuelWeaponPoint(x: Double($0) * 0.05 * direction) }
                roles[role] = name
                clips.append(.init(name: name, frames: idle.frames, sha256: idle.sha256,
                    bundle: "synthetic-ordinary-throw-tests-only",
                    tracks: .init(samplesPerSourceFrame: t.samplesPerSourceFrame, root: root,
                        handL: t.handL, handR: t.handR, footL: t.footL, footR: t.footR,
                        weaponBaseL: t.weaponBaseL, weaponTipL: t.weaponTipL,
                        weaponBaseR: t.weaponBaseR, weaponTipR: t.weaponTipR, groundLift: t.groundLift)))
            }
            roles["weaponForward"] = roles["weapon1"]; roles["weaponBack"] = roles["weapon1"]
            func profile(combat: DuelCombatRuleProfile?) -> DuelWeaponProfile {
                .init(id: base.id, hero: base.hero, faction: base.faction, resourceName: base.resourceName,
                    bytes: base.bytes, sha256: base.sha256, bodyID: base.bodyID, weaponID: base.weaponID,
                    activeWeaponSides: base.activeWeaponSides, roles: roles, clips: clips,
                    comboLinks: base.comboLinks, combatRules: combat, panguRules: base.panguRules,
                    ordinaryThrows: enabledHeroes.contains(base.hero) ? throwRules : nil)
            }
            let staged = profile(combat: nil)
            let attacks = DuelCombatRuleProfile.legacy(for: staged).attacks.map { binding in
                DuelCombatAttackRule(command: binding.command, clipName: binding.clipName,
                    strikes: [.init(id: 0, startTick: binding.command == .shadow ? 24 : 1,
                        endTick: binding.command == .shadow ? 39 : 12,
                        weaponSides: binding.command.rawValue.hasPrefix("kick") || binding.command == .shadow
                            ? [] : base.activeWeaponSides,
                        damage: ordinaryDamage, blockedDamage: 2, knocksDown: false,
                        hitStopTicks: 1, blockedHitStopTicks: 1,
                        impact: .init(distanceMillimeters: 0, durationTicks: 1),
                        blockedImpact: .init(distanceMillimeters: 0, durationTicks: 1))])
            }
            return profile(combat: .init(id: "synthetic-throw-combat-" + base.id,
                basis: .applicationAdaptation, sourceVersion: "synthetic-throw-integration-tests-only",
                evidence: ["Not original game configuration or measurements."], attacks: attacks))
        }
        let result = DuelWeaponCatalog(schemaVersion: 1, previewFramesPerSecond: 30,
            sourceFramesPerSecond: nil, profiles: profiles)
        try result.validate()
        return result
    }

    static func fight(pangu: Bool = true, panguFirst: Bool = false, distance: Int = 800,
                      firstX: Int = 3500, facing: Int = 1, mode: DuelGame.Mode = .practice,
                      panguRules: DuelPanguRules? = nil,
                      throwRules: DuelWeaponThrowRules = DuelWeaponThrowTestFixture.rules(),
                      enabledHeroes: Set<DuelGame.Hero> = [.ember, .liu],
                      ordinaryDamage: Int = 30) throws -> DuelWeaponFight {
        let fighters = [DuelGame.Fighter(hero: panguFirst ? .liu : .ember, x: firstX, facing: facing),
            DuelGame.Fighter(hero: panguFirst ? .ember : .liu,
                x: firstX + distance * facing, facing: -facing)]
        return try XCTUnwrap(.init(fighters: fighters, mode: mode, difficulty: .learning,
            catalog: catalog(pangu: pangu, panguRules: panguRules, throwRules: throwRules,
                enabledHeroes: enabledHeroes, ordinaryDamage: ordinaryDamage), seed: 117))
    }

    static func step(_ fight: inout DuelWeaponFight, count: Int) {
        for _ in 0..<count { fight.step(.neutral, opponent: .neutral) }
    }
}

final class DuelPanguThrowFightTests: XCTestCase {
    private typealias F = DuelPanguThrowFightFixture
    private typealias T = DuelWeaponThrowTestFixture

    func testPanguAutomaticallyEscapesOnlyAfterActualContactInBothSeatsAndFacings() throws {
        for panguFirst in [false, true] {
            for facing in [-1, 1] {
                var fight = try F.fight(panguFirst: panguFirst, facing: facing)
                let attacker = panguFirst ? 1 : 0, target = 1 - attacker
                let input = DuelGame.Input(weaponCommand: .weaponForward)
                fight.step(attacker == 0 ? input : .neutral, opponent: attacker == 1 ? input : .neutral)
                XCTAssertEqual(fight.ordinaryThrow(attacker)?.stage, .attempt)
                XCTAssertNil(fight.ordinaryThrow(target), "An attempt must not own the opponent before contact")
                XCTAssertFalse(fight.canBeThrown(target))
                XCTAssertTrue(fight.panguPresentationEvents.isEmpty)
                F.step(&fight, count: 1)
                XCTAssertEqual(fight.ordinaryThrow(attacker)?.stageTick, 1)
                F.step(&fight, count: 1)
                let escaping = try XCTUnwrap(fight.ordinaryThrow(target))
                XCTAssertEqual(escaping.stage, .immune); XCTAssertEqual(escaping.stageTick, 0)
                XCTAssertEqual(fight.fighters[target].weaponPose?.clip, fight.profiles[target].roles["throwEscape"])
                XCTAssertFalse(fight.canUse(.weapon, index: attacker))
                XCTAssertFalse(fight.canUsePangu(.shard, index: target))
                XCTAssertEqual(fight.panguPresentationEvents.filter {
                    if case .ordinaryThrowEscaped(let a, let t, _) = $0.kind { return a == attacker && t == target }
                    return false
                }.count, 1)
                let light = fight.panguState(target)?.light
                let energy = fight.fighters[attacker].energy
                for _ in 0..<escaping.rule.immune.durationTicks {
                    fight.step(.init(weaponCommand: .weapon), opponent: .init(weaponCommand: .weapon))
                }
                XCTAssertNil(fight.ordinaryThrow(attacker)); XCTAssertNil(fight.ordinaryThrow(target))
                F.step(&fight, count: 24)
                XCTAssertEqual(fight.fighters.map(\.health), [1000, 1000])
                XCTAssertEqual(fight.landedHits, [0, 0]); XCTAssertEqual(fight.hitStop, 0)
                XCTAssertEqual(fight.panguState(target)?.light, light)
                XCTAssertEqual(fight.fighters[attacker].energy, energy)
                XCTAssertEqual(fight.panguState(target)?.combo, 0)
                XCTAssertFalse(fight.fighters.contains { $0.knockdown > 0 || $0.stun > 0 })
            }
        }
    }

    func testNormalTargetIsThrownUnblockablyWithOneDamageMarkerAndExplicitKnockdown() throws {
        var fight = try F.fight(pangu: false)
        fight.step(.init(weaponCommand: .weaponForward), opponent: .init(guardHeld: true))
        F.step(&fight, count: 2)
        XCTAssertEqual(fight.ordinaryThrow(0)?.stage, .success)
        XCTAssertEqual(fight.fighters[1].weaponPose?.clip, fight.profiles[1].roles["throwReceived"])
        XCTAssertEqual(fight.fighters[1].health, 1000)
        F.step(&fight, count: 3)
        XCTAssertGreaterThan(fight.fighters[1].y, 0)
        XCTAssertEqual(fight.fighters[1].health, 1000)
        F.step(&fight, count: 1)
        XCTAssertEqual(fight.fighters[1].health, 930)
        XCTAssertEqual(fight.landedHits, [1, 0]); XCTAssertEqual(fight.hitStop, 2)
        XCTAssertEqual(fight.contacts.first?.usesWeapon, false)
        let paired = fight.ordinaryThrow(0), poses = fight.fighters.map(\.weaponPose)
        for _ in 0..<2 {
            fight.step(.init(weaponCommand: .heavy), opponent: .init(weaponCommand: .heavy))
            XCTAssertEqual(fight.ordinaryThrow(0), paired)
            XCTAssertEqual(fight.fighters.map(\.weaponPose), poses)
        }
        F.step(&fight, count: 2)
        XCTAssertNil(fight.ordinaryThrow(0)); XCTAssertEqual(fight.fighters[1].y, 0)
        for tick in (1...9).reversed() {
            fight.step(.neutral, opponent: .init(weaponCommand: .weaponForward))
            XCTAssertEqual(fight.fighters[1].knockdown, tick)
            XCTAssertNil(fight.fighters[1].attack)
        }
        F.step(&fight, count: 35)
        XCTAssertEqual(fight.fighters[1].health, 930)
        XCTAssertEqual(fight.landedHits, [1, 0], "Paused and knocked-down presses must not replay later")
    }

    func testOutOfRangeDirectionalInputRemainsAnOrdinaryAttack() throws {
        var fight = try F.fight(distance: 1600)
        fight.step(.init(weaponCommand: .weaponForward), opponent: .neutral)
        XCTAssertNil(fight.ordinaryThrow(0))
        XCTAssertEqual(fight.fighters[0].weaponPose?.clip, fight.profiles[0].clip(command: .weaponForward)?.name)
        XCTAssertTrue(fight.panguPresentationEvents.isEmpty)
    }

    func testTargetJumpOrWalkOutDuringStartupMakesARealMissWithoutTargetLock() throws {
        for jump in [true, false] {
            var fight = try F.fight(distance: 890)
            fight.step(.init(weaponCommand: .weaponForward), opponent: .neutral)
            let targetX = fight.fighters[1].x
            for _ in 0..<4 {
                fight.step(.neutral, opponent: jump ? .init(taps: .jump) : .init(move: 1))
            }
            XCTAssertEqual(fight.ordinaryThrow(0)?.stage, .miss)
            XCTAssertNil(fight.ordinaryThrow(1))
            XCTAssertEqual(fight.landedHits, [0, 0])
            XCTAssertTrue(fight.panguPresentationEvents.allSatisfy {
                if case .ordinaryThrowEscaped = $0.kind { return false }; return true
            })
            if jump { XCTAssertTrue(fight.isAirborne(1)) }
            else { XCTAssertGreaterThan(fight.fighters[1].x, targetX) }
        }
    }

    func testAttackingDuringStartupCanInterruptTheAttemptAndDoesNotGrantImmunityToDamage() throws {
        var fight = try F.fight(panguFirst: true)
        fight.step(.init(weaponCommand: .weaponForward), opponent: .neutral)
        fight.step(.neutral, opponent: .init(weaponCommand: .weapon))
        XCTAssertTrue(DuelPanguFightFixture.until(&fight, limit: 10) { $0.landedHits[1] == 1 })
        XCTAssertNil(fight.ordinaryThrow(0)); XCTAssertNil(fight.ordinaryThrow(1))
        XCTAssertGreaterThan(fight.panguState(0)?.light ?? 0, 0)
        XCTAssertEqual(fight.landedHits[0], 0)
        XCTAssertTrue(fight.fighters[0].weaponPose?.reaction == true)
        F.step(&fight, count: 30)
        XCTAssertEqual(fight.landedHits[0], 0)
    }

    func testPairKeepsItsSpacingAtBothWallsAndMirroredDirections() throws {
        for facing in [-1, 1] {
            let initial = facing == 1 ? DuelGame.rightWall - 800 : DuelGame.leftWall + 800
            var fight = try F.fight(pangu: false, firstX: initial, facing: facing)
            fight.step(.init(weaponCommand: .weaponForward), opponent: .neutral)
            F.step(&fight, count: 2)
            XCTAssertEqual(fight.ordinaryThrow(0)?.stage, .success)
            for _ in 0..<10 {
                fight.step(.neutral, opponent: .neutral)
                for fighter in fight.fighters { XCTAssertTrue((DuelGame.leftWall...DuelGame.rightWall).contains(fighter.x)) }
                if let state = fight.ordinaryThrow(0), let target = state.sample.target {
                    XCTAssertEqual(fight.fighters[1].x - fight.fighters[0].x,
                        target.position.x - state.sample.attacker.position.x)
                }
            }
            XCTAssertEqual(fight.landedHits, [1, 0]); XCTAssertEqual(fight.fighters[1].health, 930)
        }
    }

    func testSimultaneousContactsFollowOneExplicitCatalogPolicy() throws {
        for policy in [DuelWeaponThrowRules.SimultaneousContactPolicy.bothMiss, .lowerFighterIndexWins] {
            let rules = try T.changing { $0["simultaneousContactPolicy"] = policy.rawValue }
            var fight = try F.fight(pangu: false, throwRules: rules)
            fight.step(.init(weaponCommand: .weaponForward), opponent: .init(weaponCommand: .weaponForward))
            XCTAssertEqual(fight.ordinaryThrow(0)?.attacker, 0)
            XCTAssertEqual(fight.ordinaryThrow(1)?.attacker, 1)
            F.step(&fight, count: 2)
            if policy == .bothMiss {
                XCTAssertEqual(fight.ordinaryThrow(0)?.stage, .miss)
                XCTAssertEqual(fight.ordinaryThrow(1)?.stage, .miss)
            } else {
                XCTAssertEqual(fight.ordinaryThrow(0)?.stage, .success)
                XCTAssertEqual(fight.ordinaryThrow(1)?.attacker, 0)
            }
            F.step(&fight, count: 40)
            XCTAssertEqual(fight.landedHits, policy == .bothMiss ? [0, 0] : [1, 0])
        }
    }

    func testPanguOrdinaryThrowEffectsRequireExplicitPoliciesAndNeverInheritWeaponInput() throws {
        for enabled in [false, true] {
            let rules = try T.changingRule {
                $0["registersPanguContact"] = enabled
                $0["appliesPanguDamageScaling"] = enabled
            }
            var fight = try F.fight(panguFirst: true, throwRules: rules)
            fight.step(.init(weaponCommand: .weaponForward), opponent: .neutral)
            F.step(&fight, count: 10)
            XCTAssertEqual(fight.landedHits[0], 1)
            XCTAssertEqual(fight.fighters[1].health, 930)
            XCTAssertEqual(fight.panguState(0)?.combo, enabled ? 1 : 0)
        }
    }

    func testPracticeKOAndVersusRoundEndDisposeOfPairedAuthorityBeforeRefillOrReset() throws {
        let rules = try T.changingRule { rule in
            var success = rule["success"] as! [String: Any]
            success["damage"] = 2000; rule["success"] = success
        }
        for mode in [DuelGame.Mode.practice, .versus] {
            var fight = try F.fight(panguFirst: true, mode: mode, throwRules: rules)
            fight.step(.init(weaponCommand: .weaponForward), opponent: .neutral)
            XCTAssertTrue(DuelPanguFightFixture.until(&fight) { $0.landedHits[0] == 1 })
            XCTAssertNil(fight.ordinaryThrow(0)); XCTAssertNil(fight.ordinaryThrow(1))
            XCTAssertEqual(fight.damageDealt[0], 1000)
            if mode == .practice {
                XCTAssertEqual(fight.fighters[1].health, 1000)
                F.step(&fight, count: 45)
                XCTAssertEqual(fight.landedHits[0], 1)
                XCTAssertTrue(fight.fighters.allSatisfy { $0.y == 0 && $0.knockdown == 0 })
            } else {
                guard case .roundBreak(let winner, _) = fight.phase else { return XCTFail("Expected round break") }
                XCTAssertEqual(winner, 0)
                XCTAssertTrue(fight.fighters.allSatisfy { $0.y == 0 })
                F.step(&fight, count: 150)
                XCTAssertEqual(fight.phase, .fighting)
                XCTAssertNil(fight.ordinaryThrow(0)); XCTAssertNil(fight.ordinaryThrow(1))
                XCTAssertEqual(fight.fighters.map(\.health), [1000, 1000])
            }
        }
    }

    func testCatalogRejectsMissingEscapeBindingAndDisagreeingSimultaneousPolicies() throws {
        let catalog = try F.catalog()
        let missing = try DuelWeaponTestFixtures.changing(catalog) { profiles in
            var roles = profiles[1]["roles"] as! [String: String]
            roles.removeValue(forKey: "throwEscape"); profiles[1]["roles"] = roles
        }
        XCTAssertThrowsError(try missing.validate())
        let mismatch = try DuelWeaponTestFixtures.changing(catalog) { profiles in
            var rules = profiles[1]["ordinaryThrows"] as! [String: Any]
            rules["simultaneousContactPolicy"] = "lowerFighterIndexWins"
            profiles[1]["ordinaryThrows"] = rules
        }
        XCTAssertThrowsError(try mismatch.validate())
        XCTAssertNotEqual(try DuelReplayStateEncoding.encodeCatalog(catalog),
                          try DuelReplayStateEncoding.encodeCatalog(mismatch))
    }

    func testLegacyProfilesKeepTheirExistingCatalogAndDoNotGainImplicitThrows() throws {
        let catalog = DuelWeaponTestFixtures.catalog()
        XCTAssertTrue(catalog.profiles.allSatisfy { $0.ordinaryThrows == nil })
        var fight = try DuelWeaponTestFixtures.fight(catalog: catalog)
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        F.step(&fight, count: 20)
        XCTAssertNil(fight.ordinaryThrow(0)); XCTAssertNil(fight.ordinaryThrow(1))
        XCTAssertGreaterThan(fight.landedHits[0], 0)
        XCTAssertEqual(catalog, DuelWeaponTestFixtures.catalog())
    }

    func testMissRecoveryDoesNotUndoBodySeparationFromTheFreelyMovingTarget() throws {
        let rules = try T.changingRule { rule in
            var miss = rule["miss"] as! [String: Any]
            miss["durationTicks"] = 30
            var track = miss["attacker"] as! [String: Any]
            var frames = track["keyframes"] as! [[String: Any]]
            frames[frames.count - 1]["tick"] = 30; track["keyframes"] = frames
            miss["attacker"] = track; rule["miss"] = miss
        }
        var fight = try F.fight(distance: 890, throwRules: rules)
        fight.step(.init(weaponCommand: .weaponForward), opponent: .neutral)
        for _ in 0..<4 { fight.step(.neutral, opponent: .init(move: 1)) }
        XCTAssertEqual(fight.ordinaryThrow(0)?.stage, .miss)
        for _ in 0..<20 {
            fight.step(.neutral, opponent: .init(move: -1))
            XCTAssertGreaterThanOrEqual(abs(fight.fighters[1].x - fight.fighters[0].x), DuelGame.bodyWidth)
            XCTAssertNil(fight.ordinaryThrow(1))
        }
    }

    func testReleasedSpearKeepsFlyingDuringEscapeAndItsHitReleasesBothParticipants() throws {
        var pangu = DuelPanguTestFixture.rules(level: 2)
        DuelPanguFightFixture.changingAttack(&pangu, .spear) { $0.projectileSpeedMillimetersPerTick = 30 }
        let rules = try T.changingRule { rule in
            var immune = rule["immune"] as! [String: Any]
            immune["durationTicks"] = 40
            for key in ["attacker", "target"] {
                var track = immune[key] as! [String: Any]
                var frames = track["keyframes"] as! [[String: Any]]
                frames[frames.count - 1]["tick"] = 40; track["keyframes"] = frames; immune[key] = track
            }
            rule["immune"] = immune
        }
        var fight = try F.fight(panguFirst: true, panguRules: pangu, throwRules: rules)
        fight.step(.init(weaponCommand: .ranged), opponent: .neutral)
        XCTAssertTrue(DuelPanguFightFixture.until(&fight) { $0.panguState(0)?.activeCast == nil })
        XCTAssertEqual(fight.landedHits, [0, 0])
        XCTAssertFalse(fight.panguPresentation.volumes.isEmpty)
        fight.step(.neutral, opponent: .init(weaponCommand: .weaponForward))
        F.step(&fight, count: 2)
        XCTAssertEqual(fight.ordinaryThrow(0)?.stage, .immune)
        XCTAssertFalse(fight.panguPresentation.volumes.isEmpty, "An escape cannot erase a released spear")
        XCTAssertTrue(DuelPanguFightFixture.until(&fight, limit: 40) { $0.landedHits[0] == 1 })
        XCTAssertNil(fight.ordinaryThrow(0)); XCTAssertNil(fight.ordinaryThrow(1))
        XCTAssertEqual(fight.landedHits[1], 0)
        XCTAssertTrue(fight.fighters[1].weaponPose?.reaction == true)
        F.step(&fight, count: 50)
        XCTAssertEqual(fight.landedHits, [1, 0])
    }

    func testPetrificationInterruptsAnOrdinaryAttemptAndLeavesTheControlAuthoritative() throws {
        var fight = try F.fight()
        fight.step(.init(weaponCommand: .weaponForward), opponent: .neutral)
        XCTAssertNotNil(fight.ordinaryThrow(0))
        fight.step(.neutral, opponent: .init(weaponCommand: .shadow))
        XCTAssertTrue(DuelPanguFightFixture.until(&fight, limit: 5) {
            $0.panguPresentation.controls.contains { $0.target == 0 && $0.kind == .petrify }
        })
        XCTAssertNil(fight.ordinaryThrow(0)); XCTAssertNil(fight.ordinaryThrow(1))
        let x = fight.fighters[0].x
        fight.step(.init(weaponCommand: .weaponForward), opponent: .neutral)
        XCTAssertEqual(fight.fighters[0].x, x)
        XCTAssertNil(fight.fighters[0].attack)
        XCTAssertNil(fight.ordinaryThrow(0))
    }

    func testGroundedLethalReleaseCommitsADownPoseDuringTheRoundBreak() throws {
        let rules = try T.changingRule { rule in
            var success = rule["success"] as! [String: Any]
            success["damage"] = 2000; success["damageTick"] = success["durationTicks"]
            rule["success"] = success
        }
        var fight = try F.fight(panguFirst: true, mode: .versus, throwRules: rules)
        fight.step(.init(weaponCommand: .weaponForward), opponent: .neutral)
        XCTAssertTrue(DuelPanguFightFixture.until(&fight) { $0.phase != .fighting })
        XCTAssertNil(fight.ordinaryThrow(0)); XCTAssertEqual(fight.fighters[1].health, 0)
        let pose = try XCTUnwrap(fight.fighters[1].weaponPose)
        XCTAssertEqual(pose.clip, fight.profiles[1].roles["knockdown"])
        XCTAssertEqual(pose.phase, 1); XCTAssertEqual(fight.fighters[1].y, 0)
        XCTAssertGreaterThan(fight.fighters[1].knockdown, 0)
        F.step(&fight, count: 20)
        XCTAssertEqual(fight.fighters[1].weaponPose, pose)
    }

    func testBackThrowUsesItsExplicitMirroredPathAndCrossesSidesWithoutBodySeparation() throws {
        let rules = try T.changingRule { rule in
            rule["command"] = DuelWeaponCommand.weaponBack.rawValue
            var success = rule["success"] as! [String: Any]
            var track = success["target"] as! [String: Any]
            var frames = track["keyframes"] as! [[String: Any]]
            frames[1]["xMillimeters"] = -700
            frames[frames.count - 1]["xMillimeters"] = -1600
            track["keyframes"] = frames; success["target"] = track; rule["success"] = success
        }
        for facing in [-1, 1] {
            var fight = try F.fight(pangu: false, facing: facing, throwRules: rules)
            fight.step(.init(weaponCommand: .weaponBack), opponent: .neutral)
            F.step(&fight, count: 2)
            XCTAssertEqual(fight.ordinaryThrow(0)?.stage, .success)
            XCTAssertEqual(fight.ordinaryThrow(0)?.rule.command, .weaponBack)
            F.step(&fight, count: 8)
            XCTAssertNil(fight.ordinaryThrow(0))
            XCTAssertLessThan((fight.fighters[1].x - fight.fighters[0].x) * facing, 0)
            XCTAssertEqual(fight.landedHits[0], 1)
        }
    }

    func testStartingOwnThrowDoesNotEraseCompletedSplitterFollowupWinds() throws {
        var pangu = DuelPanguTestFixture.rules(level: 4)
        pangu.earth.splitterWindIntervalTicks = 100
        pangu.earth.dreadTicks = 0
        pangu.combo.holdTicks = 400
        pangu.combo.level6HoldTicks = 400
        DuelPanguFightFixture.changingAttack(&pangu, .splitter) {
            $0.impact = .init(distanceMillimeters: 0, durationTicks: 1)
            $0.airHoldTicks = 0; $0.hitStopTicks = 0
        }
        pangu.windBlade.impact = .init(distanceMillimeters: 0, durationTicks: 1)
        pangu.windBlade.hitStopTicks = 0
        var fight = try F.fight(panguFirst: true, panguRules: pangu)
        fight.step(.init(vertical: 1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertTrue(DuelPanguFightFixture.until(&fight, limit: 90) {
            $0.landedHits[0] >= 2 && $0.canUsePangu(.shard, index: 0) && $0.fighters[1].stun == 0
                && $0.fighters[1].weaponPose?.reaction == false
        })
        let before = fight.landedHits[0]
        XCTAssertLessThan(fight.frame, 100)
        fight.step(.init(weaponCommand: .weaponForward), opponent: .neutral)
        F.step(&fight, count: 2)
        XCTAssertEqual(fight.ordinaryThrow(0)?.stage, .success)
        F.step(&fight, count: 240)
        XCTAssertGreaterThanOrEqual(fight.landedHits[0], before + 3,
            "A successful own throw adds one hit and must retain both previously scheduled winds")
    }
}
