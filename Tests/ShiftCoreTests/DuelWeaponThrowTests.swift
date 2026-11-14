import XCTest
@testable import ShiftCore

/// Artificial, short timelines and distances for interpreter tests only. None
/// of these values or role aliases are an original-game or production preset.
enum DuelWeaponThrowTestFixture {
    static func track(_ role: String, duration: Int, endX: Int = 0,
                      facing: Int = 1) -> DuelWeaponThrowTrack {
        .init(role: role, keyframes: [
            .init(tick: 0, phaseBps: 0, xMillimeters: 0, yMillimeters: 0, facingMultiplier: facing),
            .init(tick: duration, phaseBps: 10_000, xMillimeters: endX, yMillimeters: 0, facingMultiplier: facing)
        ])
    }

    static func rule() -> DuelWeaponThrowRule {
        .init(command: .weaponForward, contactStartTick: 2, contactEndTick: 4,
              minimumRangeMillimeters: 620, maximumRangeMillimeters: 900,
              canGrabAttackingTarget: false, damageKind: .unarmed,
              appliesPanguDamageScaling: false, startsPanguAttack: false,
              registersPanguContact: false, attackerEnergyGain: 0, targetEnergyGain: 0,
              attempt: .init(durationTicks: 6, attacker: track("throwAttempt", duration: 6, endX: 60),
                             target: nil, damageTick: 0, damage: 0, hitStopTicks: 0, knockdownTicks: 0),
              success: .init(durationTicks: 6, attacker: track("throwSuccess", duration: 6, endX: 120),
                             target: .init(role: "throwReceived", keyframes: [
                                .init(tick: 0, phaseBps: 0, xMillimeters: 0, yMillimeters: 0, facingMultiplier: -1),
                                .init(tick: 3, phaseBps: 6000, xMillimeters: 300, yMillimeters: 400, facingMultiplier: -1),
                                .init(tick: 6, phaseBps: 10_000, xMillimeters: 800, yMillimeters: 0, facingMultiplier: 1)
                             ]), damageTick: 4, damage: 70, hitStopTicks: 2, knockdownTicks: 9),
              miss: .init(durationTicks: 3, attacker: track("throwMiss", duration: 3),
                          target: nil, damageTick: 0, damage: 0, hitStopTicks: 0, knockdownTicks: 0),
              immune: .init(durationTicks: 4, attacker: track("throwResisted", duration: 4),
                            target: track("throwEscape", duration: 4, facing: -1),
                            damageTick: 0, damage: 0, hitStopTicks: 0, knockdownTicks: 0))
    }

    static func rules() -> DuelWeaponThrowRules {
        .init(id: "test-only-ordinary-throw", basis: .applicationAdaptation,
              sourceVersion: "synthetic-unit-tests", sourceSHA256: nil,
              evidence: ["Artificial rules; not source measurements or an original-game preset."],
              simultaneousContactPolicy: .bothMiss, attempts: [rule()])
    }

    static func changing(_ mutation: (inout [String: Any]) -> Void) throws -> DuelWeaponThrowRules {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(rules())) as? [String: Any])
        mutation(&object)
        return try JSONDecoder().decode(DuelWeaponThrowRules.self,
                                        from: JSONSerialization.data(withJSONObject: object))
    }

    static func changingRule(_ mutation: (inout [String: Any]) -> Void) throws -> DuelWeaponThrowRules {
        try changing { object in
            var attempts = object["attempts"] as! [[String: Any]]
            mutation(&attempts[0]); object["attempts"] = attempts
        }
    }

    static func profile(_ base: DuelWeaponProfile, pangu: Bool = false,
                        removing: [String] = []) throws -> DuelWeaponProfile {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any])
        var roles = try XCTUnwrap(object["roles"] as? [String: String])
        for role in ["throwAttempt", "throwSuccess", "throwMiss", "throwResisted", "throwReceived", "throwEscape"] {
            roles[role] = roles["hit"]
        }
        roles["weaponForward"] = roles["weapon1"]
        roles["weaponBack"] = roles["weapon1"]
        for role in removing { roles.removeValue(forKey: role) }
        object["roles"] = roles
        if pangu { object["id"] = "liu_pangu" }
        return try JSONDecoder().decode(DuelWeaponProfile.self,
                                        from: JSONSerialization.data(withJSONObject: object))
    }

    static func state(rule: DuelWeaponThrowRule = rule(), facing: Int = 1,
                      attackerX: Int = 4000, targetX: Int = 4700) throws -> DuelWeaponThrowState {
        try XCTUnwrap(DuelWeaponThrowState(rule: rule, attacker: 0, target: 1, facing: facing,
                                           attackerPosition: .init(x: attackerX, y: 0),
                                           targetPosition: .init(x: targetX, y: 0)))
    }

    static func context(_ state: DuelWeaponThrowState, targetX: Int = 4700,
                        targetY: Int = 0, attackerGrounded: Bool = true,
                        targetGrounded: Bool = true, attackerAlive: Bool = true,
                        targetAlive: Bool = true, available: Bool = true,
                        immune: Bool = false) -> DuelWeaponThrowState.ContactContext {
        let next = state.nextSample
        return .init(attackerPosition: next.attacker.position,
                     targetPosition: next.target?.position ?? .init(x: targetX, y: targetY),
                     attackerGrounded: attackerGrounded, targetGrounded: targetGrounded,
                     attackerAlive: attackerAlive, targetAlive: targetAlive,
                     targetAvailable: available, targetThrowImmune: immune)
    }
}

final class DuelWeaponThrowTests: XCTestCase {
    typealias Fixture = DuelWeaponThrowTestFixture

    func testExplicitRulesRoundTripAndOnlyExistingDirectionalCommandsAreEnabled() throws {
        let original = Fixture.rules()
        try original.validate()
        let decoded = try JSONDecoder().decode(DuelWeaponThrowRules.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertNotNil(decoded.rule(command: .weaponForward))
        XCTAssertNil(decoded.rule(command: .weaponBack))
        for command in DuelWeaponCommand.allCases where command != .weaponForward && command != .weaponBack {
            let invalid = try Fixture.changingRule { $0["command"] = command.rawValue }
            XCTAssertThrowsError(try invalid.validate(), command.rawValue)
        }
        let duplicate = try Fixture.changing { object in
            let first = (object["attempts"] as! [[String: Any]])[0]
            object["attempts"] = [first, first]
        }
        XCTAssertThrowsError(try duplicate.validate())
    }

    func testNoImplicitPolicyDistanceTimingDamageOrAnimationDefaultsDecode() throws {
        let mandatory = ["contactStartTick", "contactEndTick", "minimumRangeMillimeters", "maximumRangeMillimeters",
                         "canGrabAttackingTarget", "damageKind", "appliesPanguDamageScaling", "startsPanguAttack",
                         "registersPanguContact", "attackerEnergyGain", "targetEnergyGain", "attempt", "success", "miss", "immune"]
        for field in mandatory {
            XCTAssertThrowsError(try Fixture.changingRule { $0.removeValue(forKey: field) }, field)
        }
        XCTAssertThrowsError(try Fixture.changing { $0.removeValue(forKey: "simultaneousContactPolicy") })
        for field in ["durationTicks", "attacker", "damageTick", "damage", "hitStopTicks", "knockdownTicks"] {
            XCTAssertThrowsError(try Fixture.changingRule { rule in
                var sequence = rule["success"] as! [String: Any]
                sequence.removeValue(forKey: field); rule["success"] = sequence
            }, field)
        }
    }

    func testProvenanceAndMalformedSequencesFailClosed() throws {
        let invalidProvenance: [(inout [String: Any]) -> Void] = [
            { $0["id"] = "" }, { $0["basis"] = "sourceConfiguration" },
            { $0["basis"] = "referenceMeasurement"; $0["evidence"] = [] },
            { $0["sourceSHA256"] = String(repeating: "A", count: 64) },
            { $0["sourceVersion"] = String(repeating: "x", count: 257) }
        ]
        for mutate in invalidProvenance { XCTAssertThrowsError(try Fixture.changing(mutate).validate()) }
        let invalidRules: [(inout [String: Any]) -> Void] = [
            { $0["contactStartTick"] = 0 }, { $0["contactEndTick"] = 7 },
            { $0["minimumRangeMillimeters"] = 901 }, { $0["maximumRangeMillimeters"] = Int.max },
            { $0["attackerEnergyGain"] = 101 }, { $0["targetEnergyGain"] = -1 }
        ]
        for mutate in invalidRules { XCTAssertThrowsError(try Fixture.changingRule(mutate).validate()) }
        for name in ["attempt", "success", "miss", "immune"] {
            let invalid = try Fixture.changingRule { rule in
                var sequence = rule[name] as! [String: Any]
                sequence["durationTicks"] = 0; rule[name] = sequence
            }
            XCTAssertThrowsError(try invalid.validate(), name)
            XCTAssertNil(DuelWeaponThrowState(rule: invalid.attempts[0], attacker: 0, target: 1, facing: 1,
                                             attackerPosition: .init(x: 4000, y: 0), targetPosition: .init(x: 4700, y: 0)))
        }
        for name in ["attempt", "miss", "immune"] {
            let invalid = try Fixture.changingRule { rule in
                var sequence = rule[name] as! [String: Any]
                sequence["damage"] = 1; sequence["damageTick"] = 1; rule[name] = sequence
            }
            XCTAssertThrowsError(try invalid.validate(), "Non-success damage: \(name)")
        }
    }

    func testTrackOriginsSourcePhasesAndReleaseGroundingAreRequired() throws {
        for (field, value) in [("xMillimeters", 1), ("yMillimeters", 1), ("tick", 1), ("phaseBps", 10_001)] {
            let invalid = try Fixture.changingRule { rule in
                var sequence = rule["success"] as! [String: Any]
                var track = sequence["target"] as! [String: Any]
                var frames = track["keyframes"] as! [[String: Any]]
                frames[0][field] = value; track["keyframes"] = frames
                sequence["target"] = track; rule["success"] = sequence
            }
            XCTAssertThrowsError(try invalid.validate(), field)
        }
        for name in ["attempt", "success", "miss", "immune"] {
            let invalid = try Fixture.changingRule { rule in
                var sequence = rule[name] as! [String: Any]
                var track = sequence["attacker"] as! [String: Any]
                var frames = track["keyframes"] as! [[String: Any]]
                frames[frames.count - 1]["yMillimeters"] = 1; track["keyframes"] = frames
                sequence["attacker"] = track; rule[name] = sequence
            }
            XCTAssertThrowsError(try invalid.validate(), name)
        }
        for name in ["success", "immune"] {
            let invalid = try Fixture.changingRule { rule in
                var sequence = rule[name] as! [String: Any]
                sequence.removeValue(forKey: "target"); rule[name] = sequence
            }
            XCTAssertThrowsError(try invalid.validate(), name)
        }
    }

    func testSourceBindingsRequireEveryAttackerBranchAndOnlyReachableTargetBranch() throws {
        let catalog = DuelWeaponTestFixtures.catalog(), rules = Fixture.rules()
        let attacker = try Fixture.profile(catalog.profiles[0])
        let normal = try Fixture.profile(catalog.profiles[1], removing: ["throwEscape"])
        let pangu = try Fixture.profile(catalog.profiles[1], pangu: true, removing: ["throwReceived"])
        XCTAssertNoThrow(try rules.validate(for: attacker, target: normal))
        XCTAssertNoThrow(try rules.validate(for: attacker, target: pangu))
        for role in ["throwAttempt", "throwSuccess", "throwMiss", "throwResisted"] {
            let incomplete = try Fixture.profile(catalog.profiles[0], removing: [role])
            XCTAssertThrowsError(try rules.validate(for: incomplete, target: normal), role)
        }
        XCTAssertThrowsError(try rules.validate(for: attacker,
            target: Fixture.profile(catalog.profiles[1], removing: ["throwReceived"])))
        XCTAssertThrowsError(try rules.validate(for: attacker,
            target: Fixture.profile(catalog.profiles[1], pangu: true, removing: ["throwEscape"])))
    }

    func testUnreachableDirectionalInputAndAirborneSourceEndpointsCannotEnableThrowRules() throws {
        let catalog = DuelWeaponTestFixtures.catalog()
        let attacker = try Fixture.profile(catalog.profiles[0])
        let target = try Fixture.profile(catalog.profiles[1])
        let noCommand = try Fixture.profile(catalog.profiles[0], removing: ["weaponForward"])
        XCTAssertThrowsError(try Fixture.rules().validate(for: noCommand, target: target))
        for (sequenceName, actor, endpoint) in [("attempt", "attacker", 0),
                                               ("miss", "attacker", -1),
                                               ("success", "target", -1)] {
            let airborne = try Fixture.changingRule { rule in
                var sequence = rule[sequenceName] as! [String: Any]
                var track = sequence[actor] as! [String: Any]
                var frames = track["keyframes"] as! [[String: Any]]
                track["role"] = "jump"
                frames[endpoint < 0 ? frames.count - 1 : endpoint]["phaseBps"] = 5000
                track["keyframes"] = frames; sequence[actor] = track; rule[sequenceName] = sequence
            }
            XCTAssertNoThrow(try airborne.validate(), "World offsets are valid; source pose is the rejected part")
            XCTAssertThrowsError(try airborne.validate(for: attacker, target: target), sequenceName)
        }
    }

    func testPairMustFitArenaAtEverySampleForBothContactRangeEndpoints() throws {
        let tooWide = try Fixture.changingRule { rule in
            var sequence = rule["success"] as! [String: Any]
            var track = sequence["target"] as! [String: Any]
            var frames = track["keyframes"] as! [[String: Any]]
            frames[1]["xMillimeters"] = 10_000
            track["keyframes"] = frames; sequence["target"] = track; rule["success"] = sequence
        }
        XCTAssertThrowsError(try tooWide.validate(), "Interior apex exceeds arena even though final spacing fits")
        XCTAssertNil(DuelWeaponThrowState(rule: tooWide.attempts[0], attacker: 0, target: 1, facing: 1,
                                         attackerPosition: .init(x: 4000, y: 0), targetPosition: .init(x: 4700, y: 0)))
    }

    func testNormalTargetCompletesPairDamageExactlyOnceAndKnockdownOnlyOnRelease() throws {
        var state = try Fixture.state()
        XCTAssertEqual(state.stage, .attempt); XCTAssertEqual(state.stageTick, 0)
        XCTAssertTrue(state.ownsFighter(index: 0)); XCTAssertFalse(state.ownsFighter(index: 1))
        XCTAssertNil(state.advance(context: Fixture.context(state)).contactOutcome)
        let context = Fixture.context(state, targetX: 4780)
        let contact = state.advance(context: context)
        XCTAssertEqual(contact.contactOutcome, .success)
        XCTAssertEqual(state.stage, .success); XCTAssertEqual(state.stageTick, 0)
        XCTAssertEqual(contact.sample.attacker.position, context.attackerPosition)
        XCTAssertEqual(try XCTUnwrap(contact.sample.target).position, context.targetPosition)
        XCTAssertTrue(state.ownsFighter(index: 1)); XCTAssertTrue(state.contactConsumed)
        XCTAssertNil(contact.damage); XCTAssertEqual(contact.knockdownTicks, 0)
        var damageEvents: [DuelWeaponThrowState.Damage] = []
        for tick in 1...6 {
            let result = state.advance(context: Fixture.context(state))
            if let damage = result.damage { damageEvents.append(damage); XCTAssertEqual(tick, 4) }
            XCTAssertEqual(result.knockdownTicks, tick == 6 ? 9 : 0)
            XCTAssertEqual(result.released, tick == 6)
            XCTAssertNil(result.contactOutcome)
        }
        XCTAssertEqual(damageEvents.map(\.amount), [70])
        XCTAssertEqual(damageEvents.map(\.hitStopTicks), [2])
        XCTAssertTrue(state.isFinished); XCTAssertTrue(state.damageApplied)
        XCTAssertFalse(state.ownsFighter(index: 0)); XCTAssertFalse(state.ownsFighter(index: 1))
        XCTAssertEqual(state.sample.attacker.position.y, 0)
        XCTAssertEqual(state.sample.target?.position.y, 0)
        for _ in 0..<20 {
            let result = state.advance(context: Fixture.context(state))
            XCTAssertNil(result.damage); XCTAssertNil(result.contactOutcome)
            XCTAssertFalse(result.released); XCTAssertEqual(result.knockdownTicks, 0)
        }
    }

    func testOrdinaryImmunityIsARealContactAndPairedEscapeWithoutThrowEffects() throws {
        var state = try Fixture.state()
        _ = state.advance(context: Fixture.context(state, immune: true))
        XCTAssertFalse(state.ownsFighter(index: 1))
        let contact = state.advance(context: Fixture.context(state, targetX: 4810, immune: true))
        XCTAssertEqual(contact.contactOutcome, .immune)
        XCTAssertEqual(state.stage, .immune); XCTAssertEqual(state.stageTick, 0)
        XCTAssertTrue(state.ownsFighter(index: 1))
        XCTAssertEqual(contact.sample.target?.role, "throwEscape")
        XCTAssertEqual(contact.sample.target?.position.x, 4810)
        for tick in 1...4 {
            let result = state.advance(context: Fixture.context(state, immune: false))
            XCTAssertNil(result.damage); XCTAssertNil(result.contactOutcome)
            XCTAssertEqual(result.knockdownTicks, 0); XCTAssertEqual(result.released, tick == 4)
        }
        XCTAssertEqual(state.outcome, .immune)
        XCTAssertFalse(state.damageApplied)
    }

    func testWindowRechecksActualPositionsAndCapturesLastActiveTickWithoutTargetLock() throws {
        var state = try Fixture.state()
        for tick in 1...3 {
            let result = state.advance(context: Fixture.context(state, targetX: 5500))
            XCTAssertNil(result.contactOutcome, "tick \(tick)")
            XCTAssertNil(result.sample.target)
            XCTAssertFalse(state.ownsFighter(index: 1))
        }
        let context = Fixture.context(state, targetX: 4780)
        XCTAssertTrue(state.wouldContact(context: context))
        let contact = state.advance(context: context)
        XCTAssertEqual(contact.contactOutcome, .success)
        XCTAssertEqual(state.attackerOrigin, context.attackerPosition)
        XCTAssertEqual(state.targetOrigin, context.targetPosition)
        XCTAssertNotEqual(state.targetOrigin.x, 4700, "Must not pull the target back to input-time position")
    }

    func testMissConsumesWindowOnceAndNeverOwnsOrMovesTheTarget() throws {
        var state = try Fixture.state()
        for _ in 0..<3 { _ = state.advance(context: Fixture.context(state, targetX: 6000)) }
        let result = state.advance(context: Fixture.context(state, targetX: 6000))
        XCTAssertEqual(result.contactOutcome, .missed)
        XCTAssertEqual(state.stage, .miss); XCTAssertTrue(state.contactConsumed)
        XCTAssertNil(result.sample.target); XCTAssertFalse(state.ownsFighter(index: 1))
        for tick in 1...3 {
            let result = state.advance(context: Fixture.context(state, targetX: 4700))
            XCTAssertNil(result.sample.target); XCTAssertNil(result.contactOutcome); XCTAssertNil(result.damage)
            XCTAssertEqual(result.released, tick == 3)
        }
        XCTAssertEqual(state.outcome, .missed)
    }

    func testContactRequiresBothPhysicalAndSourceGroundingAvailabilityAndFrontSide() throws {
        var state = try Fixture.state()
        _ = state.advance(context: Fixture.context(state))
        let invalid = [
            Fixture.context(state, targetX: 4020),
            Fixture.context(state, targetX: 3300),
            Fixture.context(state, targetX: 4020 + 619),
            Fixture.context(state, targetX: 4020 + 901),
            Fixture.context(state, attackerGrounded: false),
            Fixture.context(state, targetGrounded: false),
            Fixture.context(state, targetY: 1),
            Fixture.context(state, available: false),
            Fixture.context(state, attackerAlive: false),
            Fixture.context(state, targetAlive: false)
        ]
        for context in invalid { XCTAssertFalse(state.wouldContact(context: context)) }
        for distance in [620, 900] {
            XCTAssertTrue(state.wouldContact(context: Fixture.context(state, targetX: 4020 + distance)))
        }
        XCTAssertTrue(state.wouldContact(context: Fixture.context(state, immune: true)),
                      "Ordinary throw immunity must produce escape, not skip contact")
        var mirrored = try Fixture.state(facing: -1, attackerX: 6000, targetX: 5300)
        _ = mirrored.advance(context: Fixture.context(mirrored, targetX: 5300))
        XCTAssertTrue(mirrored.wouldContact(context: Fixture.context(mirrored, targetX: 5300)))
        XCTAssertFalse(mirrored.wouldContact(context: Fixture.context(mirrored, targetX: 6700)))
    }

    func testExactPhasesMirroringAndUnclampedPositionsAreReturnedForPairTranslation() throws {
        var left = try Fixture.state(attackerX: 100, targetX: 800)
        var right = try Fixture.state(facing: -1, attackerX: 9900, targetX: 9200)
        for _ in 0..<2 {
            _ = left.advance(context: Fixture.context(left, targetX: 800))
            _ = right.advance(context: Fixture.context(right, targetX: 9200))
        }
        for _ in 0..<6 {
            let a = left.advance(context: Fixture.context(left, targetX: 800))
            let b = right.advance(context: Fixture.context(right, targetX: 9200))
            XCTAssertEqual(a.sample.attacker.position.x + b.sample.attacker.position.x, 10_000)
            XCTAssertEqual(try XCTUnwrap(a.sample.target).position.x + XCTUnwrap(b.sample.target).position.x, 10_000)
            XCTAssertEqual(a.sample.attacker.phaseBps, b.sample.attacker.phaseBps)
            XCTAssertEqual(a.sample.attacker.facing, -b.sample.attacker.facing)
        }
        XCTAssertEqual(left.sample.attacker.phaseBps, 10_000)
        XCTAssertLessThan(left.sample.attacker.position.x, DuelGame.leftWall,
                          "The state must not independently clamp one participant")
        XCTAssertGreaterThan(right.sample.attacker.position.x, DuelGame.rightWall)
    }

    func testReadOnlySamplesDoNotAdvanceHitstopAndCancellationOrKOCannotLeakDamage() throws {
        var state = try Fixture.state()
        for _ in 0..<2 { _ = state.advance(context: Fixture.context(state)) }
        let beforePause = state
        for _ in 0..<30 { _ = state.sample; _ = state.nextSample; _ = state.stage }
        XCTAssertEqual(state, beforePause)
        state.cancel()
        XCTAssertTrue(state.isFinished); XCTAssertTrue(state.isCancelled)
        XCTAssertFalse(state.ownsFighter(index: 0)); XCTAssertFalse(state.ownsFighter(index: 1))
        XCTAssertNil(state.advance(context: Fixture.context(state)).damage)

        var knockout = beforePause
        let result = knockout.advance(context: Fixture.context(knockout, targetAlive: false))
        XCTAssertTrue(result.released); XCTAssertNil(result.damage)
        XCTAssertEqual(result.knockdownTicks, 0); XCTAssertTrue(knockout.isCancelled)
        XCTAssertFalse(knockout.damageApplied)
    }

    func testSimultaneousForceMissIsAtomicAndCannotRewriteAnEstablishedPair() throws {
        var a = try Fixture.state()
        var b = try XCTUnwrap(DuelWeaponThrowState(rule: Fixture.rule(), attacker: 1, target: 0, facing: -1,
                                                  attackerPosition: .init(x: 4700, y: 0),
                                                  targetPosition: .init(x: 4000, y: 0)))
        _ = a.advance(context: Fixture.context(a))
        _ = b.advance(context: Fixture.context(b, targetX: 4000))
        let aContext = Fixture.context(a, targetX: b.nextSample.attacker.position.x)
        let bContext = Fixture.context(b, targetX: a.nextSample.attacker.position.x)
        XCTAssertTrue(a.wouldContact(context: aContext)); XCTAssertTrue(b.wouldContact(context: bContext))
        let aMiss = a.forceMiss(attackerPosition: aContext.attackerPosition, targetPosition: aContext.targetPosition)
        let bMiss = b.forceMiss(attackerPosition: bContext.attackerPosition, targetPosition: bContext.targetPosition)
        XCTAssertEqual(aMiss.contactOutcome, .missed); XCTAssertEqual(bMiss.contactOutcome, .missed)
        XCTAssertNil(aMiss.sample.target); XCTAssertNil(bMiss.sample.target)

        var paired = try Fixture.state()
        for _ in 0..<2 { _ = paired.advance(context: Fixture.context(paired)) }
        let established = paired
        let ignored = paired.forceMiss(attackerPosition: .init(x: 8000, y: 0), targetPosition: .init(x: 9000, y: 0))
        XCTAssertNil(ignored.contactOutcome); XCTAssertEqual(paired, established)
    }

    func testReplayRecordsHiddenTimersOriginsCancellationAndExplicitPolicies() throws {
        func bytes(_ state: DuelWeaponThrowState) throws -> Data {
            var writer = try DuelReplayStateWriter(kind: 41)
            try state.appendReplayState(to: &writer)
            return writer.data
        }
        let original = try Fixture.state()
        var advanced = original
        _ = advanced.advance(context: Fixture.context(advanced, targetX: 6000))
        XCTAssertNotEqual(try bytes(original), try bytes(advanced))
        var cancelled = original; cancelled.cancel()
        XCTAssertNotEqual(try bytes(original), try bytes(cancelled))
        let shifted = try Fixture.state(attackerX: 4001, targetX: 4701)
        XCTAssertNotEqual(try bytes(original), try bytes(shifted))
        let changedPolicy = try Fixture.changingRule { $0["registersPanguContact"] = true }
        XCTAssertNotEqual(try bytes(original), try bytes(Fixture.state(rule: changedPolicy.attempts[0])))
        var replay = original
        for _ in 0..<8 { _ = replay.advance(context: Fixture.context(replay)) }
        var repeated = original
        for _ in 0..<8 { _ = repeated.advance(context: Fixture.context(repeated)) }
        XCTAssertEqual(replay, repeated); XCTAssertEqual(try bytes(replay), try bytes(repeated))
    }

    func testStoredThrowFieldsRemainExplicitlyAuditedForCanonicalEncoding() throws {
        func fields(_ value: Any, _ expected: [String]) {
            XCTAssertEqual(Mirror(reflecting: value).children.compactMap(\.label).sorted(), expected.sorted())
        }
        let rules = Fixture.rules(), rule = Fixture.rule()
        fields(rules, ["id", "basis", "sourceVersion", "sourceSHA256", "evidence", "simultaneousContactPolicy", "attempts"])
        fields(rule, ["command", "contactStartTick", "contactEndTick", "minimumRangeMillimeters", "maximumRangeMillimeters",
                      "canGrabAttackingTarget", "damageKind", "appliesPanguDamageScaling", "startsPanguAttack",
                      "registersPanguContact", "attackerEnergyGain", "targetEnergyGain", "attempt", "success", "miss", "immune"])
        fields(rule.success, ["durationTicks", "attacker", "target", "damageTick", "damage", "hitStopTicks", "knockdownTicks"])
        fields(rule.success.attacker, ["role", "keyframes"])
        fields(rule.success.attacker.keyframes[0], ["tick", "phaseBps", "xMillimeters", "yMillimeters", "facingMultiplier"])
        fields(try Fixture.state(), ["rule", "attacker", "target", "facing", "attackerOrigin", "targetOrigin",
                                     "stageTick", "outcome", "contactConsumed", "damageApplied", "isFinished", "isCancelled"])
        fields(DuelWeaponThrowPosition(x: 1, y: 2), ["x", "y"])
    }
}
