import Foundation
import XCTest
@testable import ShiftCore

final class DuelSerpentRainRuntimeTests: XCTestCase {
    private typealias Rain = DuelSerpentRainRuntime
    private struct Oracle: Decodable {
        struct Contact: Decodable {
            let center, target: Double
            let roll, groundStacks: Int
            let invincible: Bool
            let rainChannel: Int?
        }
        let schema, receiptSHA256: String
        let cloudPeriod, cloudLifetime, groundDelay, groundLifetime, groundFirstPulse: Int
        let groundPeriod, groundPoisonLifetime: Int
        let groundPoisonPerStack, halfWidth, cloudOffset: Double
        let cloudMotionBound, groundHasInvincibilityGuard: Bool
        let contactCases: [Contact]
        let rainTicks, groundTicks: [Int]
    }
    private func data(_ key: String) throws -> Data {
        guard let path = ProcessInfo.processInfo.environment[key] else { throw XCTSkip("Authenticated D13 input required: \(key)") }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }
    private func runtime(amplifier: Double = 1, boundCloud: Bool = false) throws -> Rain {
        let profile = try JSONDecoder().decode(DuelWeaponProfile.self, from: data("SERPENT_PHYSICAL_PROFILE"))
        let motion = try JSONDecoder().decode(DuelSerpentBottleMotion.self, from: data("SERPENT_BOTTLE_BINDING"))
        let cloud = try boundCloud ? JSONDecoder().decode(DuelSerpentCloudMotion.self,
            from: data("SERPENT_CLOUD_BINDING")) : nil
        var runtime = try Rain(binding: .init(profile: profile), bottleMotion: motion,
                               level: 6, raidDamageAmplifier: amplifier, rangedUsagesLeft: 2, cloudMotion: cloud)
        runtime.beginRound(); return runtime
    }
    private func encoded(_ value: Rain) throws -> Data {
        var writer = try DuelReplayStateWriter(kind: 3)
        try value.appendReplayState(to: &writer); return writer.data
    }
    private func scene(owner: Double = 350, target: Double = 550, direction: Int = 1) -> Rain.Scene {
        .init(ownerPelvisX: owner, targetCOMX: target, direction: direction)
    }
    private func pending(_ original: Rain? = nil, direction: Int = 1) throws -> Rain {
        var value = try original ?? runtime()
        XCTAssertNotNil(value.acceptedAnimationStart(alias: "D13_Bottle_Throw", playbackID: 1))
        for tick in 1...56 {
            _ = try XCTUnwrap(value.step(liveTick: tick, scene: scene(direction: direction), targetInvincible: false))
        }
        XCTAssertEqual(value.pendingCloud?.requestedAt, 56)
        XCTAssertNil(value.bottle); return value
    }
    private func born(roll: Int = 1, amplifier: Double = 1) throws -> Rain {
        var value = try pending(runtime(amplifier: amplifier))
        let request = try XCTUnwrap(value.pendingCloud)
        XCTAssertEqual(value.acceptedCloudBirth(frame: .init(id: request.id, liveTick: 56, rootX: request.alignedRootX),
            animation: request.animation, randomChoice: roll), [.cloudBorn(1), .rainStarted, .soundStarted(Rain.rainSound)])
        return value
    }
    func testRecoveredCloudFKDrivesRainWithoutCallerInventingCloudFrames() throws {
        for direction in [-1, 1] {
            var automatic = try pending(runtime(boundCloud: true), direction: direction)
            XCTAssertNotNil(automatic.acceptedCloudBirth(randomChoice: 1))
            let center = 350 + 200 * Double(direction)
            var explicit = automatic, pulses = 0, ground = 0
            for age in 1...1080 {
                let next = automatic.liveTick + 1
                let roll: Int? = automatic.requiresPoisonChoice(at: next) ? age % 4 + 1 : nil
                // Source Align is evaluated at birth; a later owner movement
                // or turn must not drag the existing cloud across the arena.
                let state = scene(owner: 2000, target: center, direction: -direction)
                let expected = try XCTUnwrap(explicit.step(liveTick: next, scene: state,
                    targetInvincible: false, cloudFrame: explicit.sourceCloudFrame(at: next), nextPoisonChoice: roll))
                let actual = try XCTUnwrap(automatic.step(liveTick: next, scene: state,
                    targetInvincible: false, nextPoisonChoice: roll))
                XCTAssertEqual(actual, expected); XCTAssertEqual(automatic, explicit)
                if let cloud = automatic.cloud { XCTAssertEqual(cloud.rootX, center) }
                for event in actual.modelEvents {
                    if case .cloudPoison(_, applied: true) = event { pulses += 1 }
                    if case .groundPoison = event { ground += 1 }
                }
            }
            XCTAssertEqual(pulses, 29); XCTAssertEqual(ground, 15)
            XCTAssertNil(automatic.cloud); XCTAssertNil(automatic.sourceCloudFrame(at: 1137))
            XCTAssertEqual(try encoded(automatic), try encoded(explicit))
        }
    }
    func testBoundCloudRejectsConflictingFrameAndInvalidRandomAtomically() throws {
        var value = try pending(runtime(boundCloud: true))
        let pending = try encoded(value)
        XCTAssertNil(value.acceptedCloudBirth(randomChoice: 5)); XCTAssertEqual(try encoded(value), pending)
        XCTAssertNotNil(value.acceptedCloudBirth(randomChoice: 2))
        let before = try encoded(value)
        XCTAssertNil(value.step(liveTick: 57, scene: scene(), targetInvincible: false,
            cloudFrame: .init(id: 1, liveTick: 57, rootX: 551)))
        XCTAssertEqual(try encoded(value), before)
        XCTAssertNotNil(value.step(liveTick: 57, scene: scene(), targetInvincible: false))
    }
    func testRecoveredCloudBindingAuthenticatesClockAndRejectsChangedPose() throws {
        let raw = try data("SERPENT_CLOUD_BINDING")
        let motion = try JSONDecoder().decode(DuelSerpentCloudMotion.self, from: raw)
        XCTAssertNoThrow(try motion.validate()); XCTAssertEqual(motion.samples.count, 301)
        XCTAssertNil(motion.sample(atAge: -1))
        for age in [0, 292, 293, 586, 1080, Int.max] {
            XCTAssertEqual(motion.sample(atAge: age), motion.samples[age % 293])
        }
        XCTAssertNil(motion.frame(id: 1, bornAt: 56, alignedRootX: 550, direction: 1, liveTick: 55))
        XCTAssertNil(motion.frame(id: 1, bornAt: 56, alignedRootX: .nan, direction: 1, liveTick: 56))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        object["loopPeriodTicks"] = 300
        var changed = try JSONDecoder().decode(DuelSerpentCloudMotion.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try changed.validate())
        object["loopPeriodTicks"] = 293
        var samples = try XCTUnwrap(object["samples"] as? [[String: Any]])
        samples[1]["root"] = [1.0, 0.0, 0.0]; object["samples"] = samples
        changed = try JSONDecoder().decode(DuelSerpentCloudMotion.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try changed.validate())
    }
    @discardableResult
    private func advance(_ value: inout Rain, target: Double = 550, center: Double = 550,
                         invincible: Bool = false, roll: Int = 1) throws -> Rain.Step {
        let next = value.liveTick + 1
        let frame = value.cloud.map { Rain.CloudFrame(id: $0.id, liveTick: next, rootX: center) }
        return try XCTUnwrap(value.step(liveTick: next, scene: scene(target: target), targetInvincible: invincible,
            cloudFrame: frame, nextPoisonChoice: value.requiresPoisonChoice(at: next) ? roll : nil))
    }

    func testReleaseCreatesRealFlightAtZeroThenSourceEndCreatesCloudBeforeDeletion() throws {
        for direction in [-1, 1] {
            var value = try runtime()
            XCTAssertNotNil(value.acceptedAnimationStart(alias: "D13_Bottle_Throw", playbackID: 1))
            for tick in 1...56 {
                let row = try XCTUnwrap(value.step(liveTick: tick, scene: scene(owner: tick < 56 ? 350 : 375, direction: direction), targetInvincible: false))
                if tick < 8 { XCTAssertNil(value.bottle); XCTAssertTrue(row.modelEvents.isEmpty) }
                if tick == 8 {
                    XCTAssertEqual(row.modelEvents, [.bottleBorn(1)])
                    XCTAssertEqual(value.bottle?.motionTick, 0)
                    let sample = try XCTUnwrap(value.bottleSample())
                    XCTAssertEqual(try XCTUnwrap(value.bottleWorldPoint(sample.root)).x, 350, accuracy: 1e-9)
                }
                if (8..<56).contains(tick) {
                    XCTAssertEqual(value.bottle?.motionTick, tick - 8)
                    let sample = try XCTUnwrap(value.bottleSample())
                    let expected = 350 + Double(direction) * (sample.left.x - value.bottleMotion.samples[0].root.x)
                    XCTAssertEqual(try XCTUnwrap(value.bottleWorldPoint(sample.left)).x, expected, accuracy: 1e-9)
                    XCTAssertEqual(row.statusDamage, 0)
                }
                if tick == 56 {
                    let request = try XCTUnwrap(value.pendingCloud)
                    XCTAssertEqual(request.alignedRootX, 375 + 200 * Double(direction))
                    XCTAssertEqual(row.modelEvents, [.cloudRequested(request), .modelDeleted(.bottle, 1)])
                }
            }
        }
    }

    func testMissingCloudMotionAndStaleBirthCannotBeReplacedByStationaryCollision() throws {
        var value = try pending()
        let before = try encoded(value), request = try XCTUnwrap(value.pendingCloud)
        XCTAssertNil(value.step(liveTick: 57, scene: scene(), targetInvincible: false))
        for frame in [Rain.CloudFrame(id: 2, liveTick: 56, rootX: 550), .init(id: 1, liveTick: 55, rootX: 550),
                      .init(id: 1, liveTick: 56, rootX: 551), .init(id: 1, liveTick: 56, rootX: .nan)] {
            XCTAssertNil(value.acceptedCloudBirth(frame: frame, animation: request.animation, randomChoice: 1))
            XCTAssertEqual(try encoded(value), before)
        }
        XCTAssertNil(value.acceptedCloudBirth(frame: .init(id: 1, liveTick: 56, rootX: 550), animation: "idle", randomChoice: 1))
        XCTAssertNil(value.acceptedCloudBirth(frame: .init(id: 1, liveTick: 56, rootX: 550), animation: request.animation, randomChoice: 5))
        XCTAssertEqual(try encoded(value), before)
        XCTAssertNotNil(value.acceptedCloudBirth(frame: .init(id: 1, liveTick: 56, rootX: 550), animation: request.animation, randomChoice: 1))
        let after = value
        XCTAssertNil(value.acceptedCloudBirth(frame: .init(id: 1, liveTick: 56, rootX: 550), animation: request.animation, randomChoice: 1))
        XCTAssertEqual(value, after)
    }

    func testAuthenticatedSourceTimersDriveOneRainAndGroundLifetime() throws {
        let source = try JSONDecoder().decode(Oracle.self, from: data("SERPENT_RAIN_ORACLE"))
        XCTAssertEqual(source.schema, "d13-rain-source-oracle-v1")
        XCTAssertEqual(source.receiptSHA256, "d169d518d0133ee6180c81d11edd5b5c11816e91886b7aae2eed54806f775d37")
        XCTAssertFalse(source.cloudMotionBound); XCTAssertFalse(source.groundHasInvincibilityGuard)
        XCTAssertEqual(source.halfWidth, 300); XCTAssertEqual(source.cloudOffset, 200)
        XCTAssertEqual(source.groundFirstPulse, 0)
        XCTAssertEqual(source.groundPoisonLifetime, 1200); XCTAssertEqual(source.groundPoisonPerStack, 0.02)
        var value = try born(), rainTicks: [Int] = [], groundTicks: [Int] = []
        var rainEnded: [Int] = [], groundEnded: [Int] = [], deleted: [Int] = []
        for age in 1...source.groundDelay + source.groundLifetime {
            let row = try advance(&value)
            for effect in row.modelEvents {
                switch effect {
                case .cloudPoison(_, applied: true): rainTicks.append(age)
                case .groundPoison: groundTicks.append(age)
                case .rainEnded: rainEnded.append(age)
                case .groundEnded: groundEnded.append(age)
                case .modelDeleted(.cloud, _): deleted.append(age)
                default: break
                }
            }
        }
        XCTAssertEqual(rainTicks, source.rainTicks); XCTAssertEqual(rainTicks.count, 29)
        XCTAssertEqual(groundTicks, source.groundTicks); XCTAssertEqual(groundTicks.count, 15)
        XCTAssertEqual(rainEnded, [source.cloudLifetime])
        XCTAssertEqual(groundEnded, [source.groundDelay + source.groundLifetime]); XCTAssertEqual(deleted, groundEnded)
        XCTAssertEqual(value.groundPoison.stacks, 15); XCTAssertNil(value.cloud)
        XCTAssertEqual(value.groundPoison.remainingTicks, 1140)
        // The puddle's model lifetime and target's poison lifetime are distinct.
        var damage = 0.0
        for _ in 1...1140 { damage += try advance(&value).statusDamage }
        XCTAssertGreaterThanOrEqual(damage, 0.02 * 15 / 1200 * 1140 - 1e-10)
        XCTAssertEqual(value.groundPoison.stacks, 0); XCTAssertEqual(value.groundPoison.remainingTicks, 0)
        XCTAssertEqual(try advance(&value).statusDamage, 0)
    }

    func testSourceContactOracleCoversEveryChannelExactEdgesMissesAndInvincibility() throws {
        let source = try JSONDecoder().decode(Oracle.self, from: data("SERPENT_RAIN_ORACLE"))
        XCTAssertEqual(source.contactCases.count, 168)
        let base = try pending()
        for row in source.contactCases {
            var value = base
            let request = try XCTUnwrap(value.pendingCloud)
            XCTAssertNotNil(value.acceptedCloudBirth(frame: .init(id: 1, liveTick: 56, rootX: request.alignedRootX),
                                                     animation: request.animation, randomChoice: row.roll))
            var firstPulse: Rain.Step?
            for age in 1...180 {
                let step = try advance(&value, target: row.target, center: row.center, invincible: row.invincible, roll: row.roll)
                if age == 20 { firstPulse = step }
            }
            let applied = try XCTUnwrap(firstPulse).modelEvents.compactMap { effect -> Int? in
                if case .cloudPoison(let c, applied: true) = effect { return c.index + 1 }; return nil
            }
            XCTAssertEqual(applied, row.rainChannel.map { [$0] } ?? [], "\(row.center), \(row.target), \(row.roll), \(row.invincible)")
            XCTAssertEqual(value.groundPoison.stacks, row.groundStacks)
        }
    }

    func testRainUsesOldRandomChoiceThenRerollsEvenOnMissAndInvincibleTarget() throws {
        var value = try born(roll: 4)
        for _ in 1...19 { try advance(&value, roll: 1) }
        let first = try advance(&value, roll: 1)
        XCTAssertTrue(first.modelEvents.contains(.cloudPoison(.shadow, applied: true)))
        XCTAssertEqual(value.cloud?.poisonChoice, 1)
        for _ in 21...40 { try advance(&value, target: 2000, roll: 2) }
        XCTAssertEqual(value.cloud?.poisonChoice, 2)
        for _ in 41...59 { try advance(&value, invincible: true, roll: 3) }
        let immune = try advance(&value, invincible: true, roll: 3)
        XCTAssertTrue(immune.modelEvents.contains(.cloudPoison(.unarmed, applied: false)))
        XCTAssertEqual(value.cloud?.poisonChoice, 3)
        for _ in 61...79 { try advance(&value, roll: 4) }
        XCTAssertTrue(try advance(&value, roll: 4).modelEvents.contains(.cloudPoison(.ranged, applied: true)))
    }

    func testCloudSamplesUseLiveCenterAndCOMInsteadOfOwnerOrLaunchPosition() throws {
        var value = try born()
        for age in 1...20 { try advance(&value, target: 900, center: 900 + Double(20 - age) * 100) }
        XCTAssertEqual(value.actions.state.poison(.weapon).amount, 0.02)
        for _ in 21...40 { try advance(&value, target: 550, center: 900) }
        XCTAssertEqual(value.actions.state.poison(.weapon).amount, 0.02)
        XCTAssertEqual(value.cloud?.rootX, 900)
    }

    func testInvalidFrozenSkippedTicksAndMissingRandomInputsAreAtomic() throws {
        var value = try born()
        let before = try encoded(value)
        for tick in [55, 56, 58] {
            XCTAssertNil(value.step(liveTick: tick, scene: scene(), targetInvincible: false,
                                     cloudFrame: .init(id: 1, liveTick: tick, rootX: 550)))
        }
        XCTAssertNil(value.step(liveTick: 57, scene: scene(), targetInvincible: false))
        XCTAssertNil(value.step(liveTick: 57, scene: scene(), targetInvincible: false,
                                 cloudFrame: .init(id: 1, liveTick: 56, rootX: 550)))
        XCTAssertNil(value.step(liveTick: 57, scene: scene(), targetInvincible: false,
                                 cloudFrame: .init(id: 1, liveTick: 57, rootX: 550), nextPoisonChoice: 1))
        XCTAssertEqual(try encoded(value), before)
        for _ in 1...19 { try advance(&value) }
        let atPulse = try encoded(value)
        XCTAssertNil(value.step(liveTick: 76, scene: scene(), targetInvincible: false,
                                 cloudFrame: .init(id: 1, liveTick: 76, rootX: 550)))
        XCTAssertNil(value.step(liveTick: 76, scene: scene(), targetInvincible: false,
                                 cloudFrame: .init(id: 1, liveTick: 76, rootX: 550), nextPoisonChoice: 0))
        XCTAssertEqual(try encoded(value), atPulse)
        try advance(&value)
        XCTAssertEqual(value.actions.state.poison(.weapon).amount, 0.02)
    }

    func testInterruptBeforeReleaseCancelsButAfterReleasePreservesFlight() throws {
        for stopAt in [7, 8] {
            var value = try runtime()
            XCTAssertNotNil(value.acceptedAnimationStart(alias: "D13_Bottle_Throw", playbackID: 1))
            for tick in 1...stopAt { _ = value.step(liveTick: tick, scene: scene(), targetInvincible: false) }
            XCTAssertTrue(value.interrupt(playbackID: 1)); XCTAssertFalse(value.interrupt(playbackID: 1))
            for tick in stopAt + 1...56 { _ = value.step(liveTick: tick, scene: scene(), targetInvincible: false) }
            XCTAssertEqual(value.pendingCloud != nil, stopAt == 8)
            XCTAssertEqual(value.actions.rangedUsagesLeft, 1)
        }
    }

    func testDestroyedBottleDoesNotProduceCloudAndOldRemovalCannotDeleteLiveCloud() throws {
        var value = try runtime()
        _ = value.acceptedAnimationStart(alias: "D13_Bottle_Throw", playbackID: 1)
        for tick in 1...10 { _ = value.step(liveTick: tick, scene: scene(), targetInvincible: false) }
        XCTAssertNil(value.removeModel(.bottle, id: 2))
        XCTAssertEqual(value.removeModel(.bottle, id: 1), [.modelDeleted(.bottle, 1)])
        XCTAssertNil(value.removeModel(.bottle, id: 1))
        for tick in 11...60 { _ = value.step(liveTick: tick, scene: scene(), targetInvincible: false) }
        XCTAssertNil(value.pendingCloud); XCTAssertNil(value.cloud)
        value = try born()
        let before = value
        XCTAssertNil(value.removeModel(.cloud, id: 2)); XCTAssertNil(value.removeModel(.bottle, id: 1))
        XCTAssertEqual(value, before)
        XCTAssertTrue(try XCTUnwrap(value.removeModel(.cloud, id: 1)).contains(.modelDeleted(.cloud, 1)))
        XCTAssertNil(value.cloud)
    }

    func testRoundEndClearsPendingAndActiveEntitiesOnceAndFreezesStatuses() throws {
        var pendingValue = try pending()
        let request = try XCTUnwrap(pendingValue.pendingCloud)
        pendingValue.endRound()
        XCTAssertNil(pendingValue.pendingCloud)
        XCTAssertNil(pendingValue.acceptedCloudBirth(frame: .init(id: 1, liveTick: 56, rootX: 550),
                                                    animation: request.animation, randomChoice: 1))
        var value = try born()
        for _ in 1...180 { try advance(&value) }
        let effects = value.endRound()
        XCTAssertTrue(effects.contains(.groundEnded)); XCTAssertTrue(effects.contains(.rainEnded))
        XCTAssertTrue(effects.contains(.soundStopped(Rain.rainSound)))
        XCTAssertEqual(value.endRound(), [])
        let before = try encoded(value)
        XCTAssertNil(value.step(liveTick: value.liveTick + 1, scene: scene(), targetInvincible: false))
        XCTAssertEqual(try encoded(value), before)
    }

    func testReplayIncludesFlightPendingCloudRandomPositionAndLingeringGroundState() throws {
        var a = try born(), b = a
        for age in 1...1080 {
            let target = age % 150 < 75 ? 550.0 : 900.0
            let ra = try advance(&a, target: target, roll: age % 4 + 1)
            let rb = try advance(&b, target: target, roll: age % 4 + 1)
            XCTAssertEqual(ra, rb)
            if age % 180 == 0 { XCTAssertEqual(try encoded(a), try encoded(b)) }
        }
        XCTAssertNil(a.cloud); XCTAssertGreaterThan(a.groundPoison.stacks, 0)
        XCTAssertEqual(try encoded(a), try encoded(b))
        try advance(&a)
        XCTAssertNotEqual(try encoded(a), try encoded(b))
    }

    func testContactBridgePreservesSourceGuardsTagsPerksAndIncomingBloom() throws {
        var value = try runtime(amplifier: 2.5)
        let before = value
        XCTAssertFalse(value.outgoingContact(channel: .weapon, sourceDamage: 0.2, first: false))
        XCTAssertFalse(value.incomingContact(sourceDamage: 0.2, first: false))
        XCTAssertEqual(value, before)
        XCTAssertTrue(value.outgoingContact(channel: .weapon, sourceDamage: 0.2,
                                           perks: .init(poison: 0.02, cobraDance: 0.03)))
        XCTAssertEqual(value.actions.state.poison(.weapon).amount, 0.25 * 0.35 * 1.3, accuracy: 1e-12)
        let bloom = value.actions.state.bloom
        XCTAssertTrue(value.outgoingContact(channel: .shadow, sourceDamage: 0.2, hitTag: "Hit_D13_Bloom"))
        XCTAssertEqual(value.actions.state.bloom, bloom)
        XCTAssertEqual(value.actions.state.poison(.shadow).amount, 0)
        XCTAssertTrue(value.incomingContact(sourceDamage: 0.2, first: false, invisible: true))
        XCTAssertEqual(value.actions.state.bloom, bloom + 0.2 * 0.45, accuracy: 1e-12)
    }

    func testRandomScheduleHandlesExtremeQueriesWithoutIntegerOverflow() throws {
        let value = try born()
        XCTAssertFalse(value.requiresPoisonChoice(at: Int.min))
        XCTAssertFalse(value.requiresPoisonChoice(at: Int.max))
        XCTAssertFalse(value.requiresPoisonChoice(at: 56))
        XCTAssertTrue(value.requiresPoisonChoice(at: 76))
    }
}
