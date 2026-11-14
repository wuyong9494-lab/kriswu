import XCTest
@testable import ShiftCore

/// Synthetic interpreter checks. No response below is represented as a
/// measured Ninjato, Dead Forest Triad or Heavenly King gameplay constant.
final class DuelWeaponImpactTests: XCTestCase {
    private typealias Fixture = DuelWeaponTestFixtures

    func testConfirmedContactDoesNotTeleportAndHitStopFreezesTheScheduledRecoil() throws {
        for command in [DuelWeaponCommand.weapon, .heavy] {
            for blocked in [false, true] {
                for direction in [-1, 1] {
                    var fight = try makeFight(direction: direction)
                    let originalX = fight.fighters[1].x
                    try reachContact(&fight, command: command, blocked: blocked)
                    XCTAssertEqual(fight.fighters[1].x, originalX, "Contact must schedule rather than teleport")
                    let frozen = fight.fighters[1], pause = fight.hitStop
                    for _ in 0..<pause {
                        fight.step(.neutral, opponent: .init(guardHeld: blocked))
                        XCTAssertEqual(fight.fighters[1], frozen)
                    }
                    fight.step(.neutral, opponent: .init(guardHeld: blocked))
                    let firstDistance = abs(fight.fighters[1].x - originalX)
                    let total = command == .heavy ? 200 : 65
                    XCTAssertGreaterThan(firstDistance, 0); XCTAssertLessThan(firstDistance, total)
                    for _ in 0..<35 { fight.step(.neutral, opponent: .init(guardHeld: blocked)) }
                    XCTAssertEqual(fight.fighters[1].x, originalX + direction * total)
                    XCTAssertEqual(fight.fighters[1].y, 0, "Legacy heavy hits must not silently gain a fabricated launch")
                    XCTAssertEqual(fight.fighters[1].velocityY, 0)
                    XCTAssertEqual(fight.landedHits[0], blocked ? 0 : 1)
                }
            }
        }
    }

    func testOriginalReactionRootAndExternalRecoilEachApplyOnce() throws {
        let catalog = try Fixture.changing(Fixture.catalog()) { profiles in
            var clips = profiles[1]["clips"] as! [[String: Any]]
            let reaction = clips.firstIndex { $0["name"] as? String == "hammers_reaction" }!
            var tracks = clips[reaction]["tracks"] as! [String: Any]
            let count = (tracks["root"] as! [[Double]]).count
            tracks["root"] = (0..<count).map { [Double($0) * 0.001, 0.0, 0.0] }
            clips[reaction]["tracks"] = tracks; profiles[1]["clips"] = clips
        }
        var fight = try makeFight(catalog: catalog)
        let originalX = fight.fighters[1].x
        try reachContact(&fight, command: .weapon)
        for _ in 0..<40 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.fighters[1].x, originalX + 65 - 16,
                       "The mirrored 16 mm source root and 65 mm recoil are separate contributions")
        XCTAssertEqual(fight.landedHits[0], 1)
    }

    func testSimultaneousContactsRetainBothDamageAndOpposingRecoil() throws {
        for direction in [-1, 1] {
            var fight = try makeFight(direction: direction)
            let original = fight.fighters.map(\.x)
            fight.step(.init(weaponCommand: .weapon), opponent: .init(weaponCommand: .weapon))
            for _ in 0..<20 where fight.contacts.isEmpty { fight.step(.neutral, opponent: .neutral) }
            XCTAssertEqual(fight.contacts.count, 2)
            XCTAssertEqual(fight.landedHits, [1, 1])
            XCTAssertEqual(fight.fighters.map(\.health), [895, 920])
            XCTAssertEqual(fight.fighters.map(\.x), original)
            for _ in 0..<30 { fight.step(.neutral, opponent: .neutral) }
            XCTAssertEqual(fight.fighters.map(\.x), [original[0] - 65 * direction, original[1] + 65 * direction])
            XCTAssertEqual(fight.landedHits, [1, 1], "Recoil cannot restore either interrupted strike budget")
        }
    }

    func testExplicitLaunchCannotStartGetUpInTheAirOrReplayRecoveryInputs() throws {
        let response = DuelImpactResponse(distanceMillimeters: 200, durationTicks: 10,
                                          launchVelocityMillimetersPerTick: 180,
                                          gravityMillimetersPerTickSquared: 10)
        let source = try separateGetUpClip(in: Fixture.catalog())
        let catalog = try replacingRules(in: source, profileIndex: 0) { rule in
            guard rule.command == .heavy else { return rule }
            return .init(command: rule.command, clipName: rule.clipName,
                         strikes: rule.strikes.map { copy($0, impact: response) })
        }
        var fight = try makeFight(catalog: catalog)
        try reachContact(&fight, command: .heavy)
        let getUp = try XCTUnwrap(fight.profiles[1].roles["getUp"])
        var airborneTicks = 0, landed = false, previousHeight = 0
        for _ in 0..<100 {
            fight.step(.neutral, opponent: .init(move: -1, guardHeld: true, taps: .jump, weaponCommand: .weapon))
            let fighter = fight.fighters[1]
            if fighter.y > 0 {
                airborneTicks += 1
                XCTAssertTrue(fight.isAirborne(1)); XCTAssertFalse(fighter.guarding)
                XCTAssertTrue(fighter.weaponPose?.reaction == true)
                XCTAssertNotEqual(fighter.weaponPose?.clip, getUp)
                XCTAssertGreaterThan(fighter.knockdown, 0)
                XCTAssertEqual(fight.hurtBox(1).minY, fighter.y + 180)
            }
            if previousHeight > 0 && fighter.y == 0 {
                landed = true
                XCTAssertEqual(fighter.velocityY, 0)
                XCTAssertNotEqual(fighter.weaponPose?.clip, getUp, "The first floor sample precedes get-up")
                break
            }
            previousHeight = fighter.y
        }
        XCTAssertGreaterThan(airborneTicks, 16, "Flight must outlast the synthetic source reaction clip")
        XCTAssertTrue(landed)
        fight.step(.neutral, opponent: .init(guardHeld: true))
        XCTAssertEqual(fight.fighters[1].weaponPose?.clip, getUp)
        XCTAssertEqual(fight.fighters[1].y, 0)
        var recovered = false
        for _ in 0..<40 {
            fight.step(.neutral, opponent: .init(guardHeld: true))
            if fight.fighters[1].weaponPose?.reaction == false {
                recovered = true
                XCTAssertTrue(fight.fighters[1].guarding)
                XCTAssertNil(fight.fighters[1].attack)
                XCTAssertEqual(fight.fighters[1].knockdown, 0)
                XCTAssertGreaterThan(fight.fighters[1].invulnerable, 0)
                break
            }
        }
        XCTAssertTrue(recovered)
        XCTAssertEqual(fight.landedHits, [1, 0], "Recovery presses must not emerge as a delayed attack")
    }

    func testSourceJumpHitPreservesWorldHeightBeforeApplyingAnExplicitLaunch() throws {
        let source = try Fixture.changing(Fixture.catalog()) { profiles in
            var clips = profiles[1]["clips"] as! [[String: Any]]
            let index = clips.firstIndex { $0["name"] as? String == "hammers_jump" }!
            var tracks = clips[index]["tracks"] as! [String: Any]
            let count = (tracks["root"] as! [[Double]]).count
            tracks["root"] = (0..<count).map { [0.0, sin(.pi * Double($0) / Double(count - 1)) * 0.2, 0.0] }
            tracks["groundLift"] = (0..<count).map { sin(.pi * Double($0) / Double(count - 1)) * 0.5 }
            clips[index]["tracks"] = tracks; profiles[1]["clips"] = clips
        }
        for launch in [0, 90] {
            let response = DuelImpactResponse(distanceMillimeters: 65, durationTicks: 6,
                                              launchVelocityMillimetersPerTick: launch)
            let catalog = try replacingRules(in: source, profileIndex: 0) { rule in
                guard rule.command == .weapon else { return rule }
                return .init(command: rule.command, clipName: rule.clipName,
                             strikes: rule.strikes.map { copy($0, impact: response) })
            }
            var fight = try makeFight(catalog: catalog), unhit = fight
            fight.step(.neutral, opponent: .init(taps: .jump))
            unhit.step(.neutral, opponent: .init(taps: .jump))
            for _ in 0..<4 {
                fight.step(.neutral, opponent: .neutral); unhit.step(.neutral, opponent: .neutral)
            }
            XCTAssertEqual(fight.fighters[1].y, 0, "Authored jumping starts in the source pose")
            XCTAssertTrue(fight.isAirborne(1))
            fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
            unhit.step(.neutral, opponent: .neutral)
            for _ in 0..<20 where fight.contacts.isEmpty {
                fight.step(.neutral, opponent: .neutral); unhit.step(.neutral, opponent: .neutral)
            }
            XCTAssertFalse(fight.contacts.isEmpty)
            let expectedHeight = bodyHeight(unhit, index: 1)
            XCTAssertGreaterThan(expectedHeight, 0)
            XCTAssertEqual(bodyHeight(fight, index: 1), expectedHeight,
                           "A reaction must inherit both source pelvis Y and ground lift once")
            XCTAssertEqual(fight.fighters[1].velocityY, launch)
            for _ in 0..<fight.hitStop { fight.step(.neutral, opponent: .neutral) }
            fight.step(.neutral, opponent: .neutral)
            XCTAssertEqual(bodyHeight(fight, index: 1), expectedHeight + launch)
        }
    }

    func testMovingSourceHurtboxParticipatesInTheRelativeSweepWithZeroExternalHeight() throws {
        let catalog = try Fixture.changing(Fixture.catalog()) { profiles in
            var attackClips = profiles[0]["clips"] as! [[String: Any]]
            let attack = attackClips.firstIndex { $0["name"] as? String == "katana_weapon" }!
            var attackTracks = attackClips[attack]["tracks"] as! [String: Any]
            for name in ["weaponBaseR", "weaponTipR"] {
                var points = attackTracks[name] as! [[Double]]
                for i in points.indices { points[i][1] = 1.88 }
                attackTracks[name] = points
            }
            attackClips[attack]["tracks"] = attackTracks; profiles[0]["clips"] = attackClips
            var targetClips = profiles[1]["clips"] as! [[String: Any]]
            let jump = targetClips.firstIndex { $0["name"] as? String == "hammers_jump" }!
            var targetTracks = targetClips[jump]["tracks"] as! [String: Any]
            let count = (targetTracks["groundLift"] as! [Double]).count
            targetTracks["groundLift"] = (0..<count).map { $0 < 3 ? 0.4 : 0.0 }
            targetClips[jump]["tracks"] = targetTracks; profiles[1]["clips"] = targetClips
        }
        var fight = try makeFight(catalog: catalog)
        fight.step(.neutral, opponent: .init(taps: .jump))
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        fight.step(.neutral, opponent: .neutral)
        XCTAssertEqual(fight.fighters[1].y, 0)
        XCTAssertTrue(fight.contacts.isEmpty)
        XCTAssertEqual(fight.hurtBox(1).minY, 580)
        fight.step(.neutral, opponent: .neutral)
        XCTAssertEqual(fight.fighters[1].y, 0)
        XCTAssertEqual(fight.hurtBox(1).minY, 180)
        XCTAssertEqual(fight.landedHits[0], 1,
                       "The hurtbox crosses the blade even though the final blade is above the final hurtbox")
    }

    func testAirborneShaftContactEffectStaysInsideTheActualHurtbox() throws {
        let catalog = try highShaftCatalog()
        var fight = try makeFight(catalog: catalog, opponentHeight: 2000)
        try reachContact(&fight, command: .weapon)
        let contact = try XCTUnwrap(fight.contacts.first)
        let box = fight.hurtBox(1)
        XCTAssertGreaterThanOrEqual(contact.position.y, Double(box.minY) / 1000)
        XCTAssertLessThanOrEqual(contact.position.y, Double(box.maxY) / 1000)
        XCTAssertGreaterThan(contact.position.y, 2, "A flying target's impact cannot be clamped to ground-level 1.6 m")
    }

    func testAirborneKOAndTimeoutCommitGroundedTerminalState() throws {
        var knockout = try makeFight(catalog: highShaftCatalog(), mode: .versus,
                                     opponentHealth: 1, opponentHeight: 2000)
        try reachContact(&knockout, command: .weapon)
        guard case .roundBreak = knockout.phase else { return XCTFail("Expected airborne KO") }
        for _ in 0..<20 {
            XCTAssertEqual(knockout.fighters.map(\.y), [0, 0])
            XCTAssertEqual(knockout.fighters.map(\.velocityY), [0, 0])
            XCTAssertFalse(knockout.isAirborne(1))
            knockout.step(.neutral, opponent: .neutral)
        }

        let response = DuelImpactResponse(distanceMillimeters: 65, durationTicks: 6,
                                          launchVelocityMillimetersPerTick: 180,
                                          gravityMillimetersPerTickSquared: 10)
        let catalog = try replacingRules(in: Fixture.catalog(), profileIndex: 0) { rule in
            guard rule.command == .heavy else { return rule }
            return .init(command: rule.command, clipName: rule.clipName,
                         strikes: rule.strikes.map { copy($0, impact: response) })
        }
        var timeout = try makeFight(catalog: catalog, mode: .versus)
        for _ in 0..<3590 { timeout.step(.neutral, opponent: .neutral) }
        timeout.step(.init(weaponCommand: .heavy), opponent: .neutral)
        var observedFlight = false
        for _ in 0..<40 where timeout.phase == .fighting {
            observedFlight = observedFlight || timeout.fighters[1].y > 0
            timeout.step(.neutral, opponent: .neutral)
        }
        XCTAssertTrue(observedFlight)
        guard case .roundBreak = timeout.phase else { return XCTFail("Expected timeout") }
        XCTAssertEqual(timeout.fighters.map(\.y), [0, 0])
        XCTAssertEqual(timeout.fighters.map(\.velocityY), [0, 0])
        XCTAssertFalse(timeout.isAirborne(0)); XCTAssertFalse(timeout.isAirborne(1))
    }

    func testTwoExplicitBladeWindowsOwnIndependentDamageBudgets() throws {
        let stationary = DuelImpactResponse(distanceMillimeters: 0, durationTicks: 1)
        let catalog = try replacingRules(in: Fixture.catalog(), profileIndex: 1) { rule in
            guard rule.command == .weapon else { return rule }
            let left = DuelCombatStrike(id: 31, startTick: 2, endTick: 5, weaponSides: ["left"],
                damage: 17, blockedDamage: 1, knocksDown: false, hitStopTicks: 0, blockedHitStopTicks: 0,
                impact: stationary, blockedImpact: stationary)
            let right = DuelCombatStrike(id: 47, startTick: 8, endTick: 12, weaponSides: ["right"],
                damage: 23, blockedDamage: 2, knocksDown: false, hitStopTicks: 0, blockedHitStopTicks: 0,
                impact: stationary, blockedImpact: stationary)
            return .init(command: rule.command, clipName: rule.clipName, strikes: [left, right])
        }
        for direction in [-1, 1] {
            var fight = try makeFight(catalog: catalog, hero: .liu, direction: direction)
            fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
            var contactTicks: [Int] = []
            for _ in 0..<40 {
                fight.step(.neutral, opponent: .neutral)
                contactTicks += fight.contacts.map { _ in fight.fighters[0].weaponPose?.tick ?? -1 }
            }
            XCTAssertEqual(contactTicks, [2, 8])
            XCTAssertEqual(fight.landedHits[0], 2)
            XCTAssertEqual(fight.damageDealt[0], 40)
            XCTAssertEqual(fight.fighters[1].health, 960)
        }
    }

    func testComboStageWithDifferentStrikeIDCannotRehitTheUnseparatedSharedPose() throws {
        let source = try Fixture.changing(Fixture.catalog()) { profiles in
            profiles[0]["comboLinks"] = [["from": "katana_weapon", "to": "katana_weapon2", "sourceFrame": 4]]
        }
        let catalog = try replacingRules(in: source, profileIndex: 0) { rule in
            guard rule.command == .weapon else { return rule }
            return .init(command: rule.command, clipName: rule.clipName, strikes: rule.strikes.map { strike in
                .init(id: rule.clipName == "katana_weapon" ? 10 : 20,
                      startTick: strike.startTick, endTick: strike.endTick, weaponSides: strike.weaponSides,
                      damage: strike.damage, blockedDamage: strike.blockedDamage, knocksDown: strike.knocksDown,
                      hitStopTicks: strike.hitStopTicks, blockedHitStopTicks: strike.blockedHitStopTicks,
                      impact: strike.impact, blockedImpact: strike.blockedImpact)
            })
        }
        for direction in [-1, 1] {
            var fight = try makeFight(catalog: catalog, direction: direction)
            fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
            fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
            var continued = false
            for _ in 0..<40 {
                fight.step(.neutral, opponent: .neutral)
                continued = continued || fight.fighters[0].weaponPose?.clip == "katana_weapon2"
            }
            XCTAssertTrue(continued)
            XCTAssertEqual(fight.landedHits[0], 1)
            XCTAssertEqual(fight.damageDealt[0], 80)
        }
    }

    func testReactionCannotFinishBeforeItsLongerHorizontalResponse() throws {
        let response = DuelImpactResponse(distanceMillimeters: 65, durationTicks: 32)
        let catalog = try replacingRules(in: Fixture.catalog(), profileIndex: 0) { rule in
            guard rule.command == .weapon else { return rule }
            return .init(command: rule.command, clipName: rule.clipName,
                         strikes: rule.strikes.map { copy($0, impact: response) })
        }
        var fight = try makeFight(catalog: catalog)
        let originalX = fight.fighters[1].x
        try reachContact(&fight, command: .weapon)
        for _ in 0..<fight.hitStop { fight.step(.neutral, opponent: .neutral) }
        for _ in 0..<31 {
            fight.step(.neutral, opponent: .init(move: -1, guardHeld: true, taps: .jump, weaponCommand: .weapon))
            XCTAssertTrue(fight.fighters[1].weaponPose?.reaction == true)
            XCTAssertGreaterThan(fight.fighters[1].stun, 0)
            XCTAssertFalse(fight.fighters[1].guarding)
            XCTAssertNil(fight.fighters[1].attack)
        }
        fight.step(.neutral, opponent: .init(guardHeld: true))
        XCTAssertEqual(fight.fighters[1].x, originalX + 65)
        XCTAssertTrue(fight.fighters[1].weaponPose?.reaction == false)
        XCTAssertTrue(fight.fighters[1].guarding)
        XCTAssertNil(fight.fighters[1].attack)
        XCTAssertEqual(fight.landedHits, [1, 0])
    }

    func testInactiveSecondWeaponCannotStealAnExplicitFirstWeaponWindow() throws {
        let source = try Fixture.changing(Fixture.catalog()) { profiles in
            var clips = profiles[1]["clips"] as! [[String: Any]]
            let index = clips.firstIndex { $0["name"] as? String == "hammers_weapon" }!
            var tracks = clips[index]["tracks"] as! [String: Any]
            for name in ["weaponBaseL", "weaponTipL"] {
                let count = (tracks[name] as! [[Double]]).count
                tracks[name] = Array(repeating: [-2.0, 1.0, 0.0], count: count)
            }
            clips[index]["tracks"] = tracks; profiles[1]["clips"] = clips
        }
        let catalog = try replacingRules(in: source, profileIndex: 1) { rule in
            guard rule.command == .weapon else { return rule }
            return .init(command: rule.command, clipName: rule.clipName,
                         strikes: rule.strikes.map { copy($0, sides: ["left"]) })
        }
        var fight = try makeFight(catalog: catalog, hero: .liu)
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        for _ in 0..<40 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.landedHits[0], 0)
        XCTAssertEqual(fight.fighters[1].health, 1000)
    }

    func testOverkillAndRoundResetDoNotRetainImpulseOrInflateDamage() throws {
        var fight = try makeFight(mode: .versus, opponentHealth: 1)
        fight.step(.init(weaponCommand: .heavy), opponent: .neutral)
        for _ in 0..<40 where fight.phase == .fighting { fight.step(.neutral, opponent: .neutral) }
        guard case .roundBreak(_, let ticks) = fight.phase else { return XCTFail("Expected KO") }
        XCTAssertEqual(fight.damageDealt[0], 1)
        XCTAssertTrue(fight.fighters.allSatisfy { $0.velocityY == 0 })
        for _ in 0..<ticks { fight.step(.neutral, opponent: .neutral) }
        let start = fight.fighters.map(\.x)
        for _ in 0..<20 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.fighters.map(\.x), start)
        XCTAssertEqual(fight.fighters.map(\.y), [0, 0])
        XCTAssertEqual(fight.fighters.map(\.velocityY), [0, 0])
    }

    func testSameInputsEncodeIdenticalStateDuringFlightLandingAndRecovery() throws {
        let response = DuelImpactResponse(distanceMillimeters: 123, durationTicks: 11,
                                          launchVelocityMillimetersPerTick: 120,
                                          gravityMillimetersPerTickSquared: 9)
        let catalog = try replacingRules(in: Fixture.catalog(), profileIndex: 0) { rule in
            guard rule.command == .heavy else { return rule }
            return .init(command: rule.command, clipName: rule.clipName,
                         strikes: rule.strikes.map { copy($0, impact: response) })
        }
        var a = try makeFight(catalog: catalog), b = a
        for tick in 0..<150 {
            let input = DuelGame.Input(weaponCommand: tick == 0 ? .heavy : nil)
            let other = DuelGame.Input(guardHeld: tick > 80)
            a.step(input, opponent: other); b.step(input, opponent: other)
            XCTAssertEqual(try DuelReplayStateEncoding.encode(a), try DuelReplayStateEncoding.encode(b), "Tick \(tick)")
        }
        XCTAssertEqual(a.landedHits[0], 1)
    }

    private func reachContact(_ fight: inout DuelWeaponFight, command: DuelWeaponCommand,
                              blocked: Bool = false) throws {
        fight.step(.init(weaponCommand: command), opponent: .init(guardHeld: blocked))
        for _ in 0..<80 where fight.contacts.isEmpty {
            fight.step(.neutral, opponent: .init(guardHeld: blocked))
        }
        XCTAssertFalse(fight.contacts.isEmpty)
    }

    private func makeFight(catalog: DuelWeaponCatalog = Fixture.catalog(), hero: DuelGame.Hero = .ember,
                           direction: Int = 1, mode: DuelGame.Mode = .practice,
                           opponentHealth: Int = 1000, opponentHeight: Int = 0) throws -> DuelWeaponFight {
        let x = direction > 0 ? 3500 : 6500
        let a = DuelGame.Fighter(hero: hero, x: x, facing: direction)
        var b = DuelGame.Fighter(hero: hero == .ember ? .liu : .ember, x: x + 800 * direction, facing: -direction)
        b.health = opponentHealth; b.y = opponentHeight
        return try XCTUnwrap(DuelWeaponFight(fighters: [a, b], mode: mode,
                                            difficulty: .learning, catalog: catalog, seed: 901))
    }

    private func bodyHeight(_ fight: DuelWeaponFight, index: Int) -> Int {
        let fighter = fight.fighters[index]
        guard let pose = fighter.weaponPose, let clip = fight.profiles[index].clip(named: pose.clip) else { return fighter.y }
        return fighter.y + Int(((pose.groundLift + clip.tracks.sample(clip.tracks.root, phase: pose.phase).y) * 1000).rounded())
    }

    private func highShaftCatalog() throws -> DuelWeaponCatalog {
        try Fixture.changing(Fixture.catalog()) { profiles in
            var clips = profiles[0]["clips"] as! [[String: Any]]
            let index = clips.firstIndex { $0["name"] as? String == "katana_weapon" }!
            var tracks = clips[index]["tracks"] as! [String: Any]
            for (name, height) in [("weaponBaseR", 1.0), ("weaponTipR", 4.0)] {
                var points = tracks[name] as! [[Double]]
                for i in points.indices { points[i][1] = height }
                tracks[name] = points
            }
            clips[index]["tracks"] = tracks; profiles[0]["clips"] = clips
        }
    }

    private func replacingRules(in catalog: DuelWeaponCatalog, profileIndex: Int,
                                 transform: (DuelCombatAttackRule) -> DuelCombatAttackRule) throws -> DuelWeaponCatalog {
        let base = catalog.profiles[profileIndex].resolvedCombatRules
        let rules = DuelCombatRuleProfile(id: "synthetic-impact-test", basis: .applicationAdaptation,
            sourceVersion: "synthetic-test-only", evidence: [], attacks: base.attacks.map(transform))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rules))
        return try Fixture.changing(catalog) { $0[profileIndex]["combatRules"] = object }
    }

    private func separateGetUpClip(in catalog: DuelWeaponCatalog) throws -> DuelWeaponCatalog {
        try Fixture.changing(catalog) { profiles in
            var clips = profiles[1]["clips"] as! [[String: Any]]
            var up = clips.first { $0["name"] as? String == "hammers_reaction" }!
            up["name"] = "hammers_get_up"; clips.append(up); profiles[1]["clips"] = clips
            var roles = profiles[1]["roles"] as! [String: String]
            roles["getUp"] = "hammers_get_up"; profiles[1]["roles"] = roles
        }
    }
}

private func copy(_ strike: DuelCombatStrike, impact: DuelImpactResponse? = nil,
                  sides: [String]? = nil) -> DuelCombatStrike {
    .init(id: strike.id, startTick: strike.startTick, endTick: strike.endTick,
          weaponSides: sides ?? strike.weaponSides, damage: strike.damage, blockedDamage: strike.blockedDamage,
          knocksDown: strike.knocksDown, hitStopTicks: strike.hitStopTicks,
          blockedHitStopTicks: strike.blockedHitStopTicks, impact: impact ?? strike.impact,
          blockedImpact: strike.blockedImpact)
}
