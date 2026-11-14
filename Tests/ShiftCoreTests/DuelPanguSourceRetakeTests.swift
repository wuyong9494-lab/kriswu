import XCTest
@testable import ShiftCore

/// Recovered record248 timing and pair ownership, with intentionally synthetic
/// source hashes, grounded foot samples, COM and 1,000-unit attack scales.
/// No original fighter media or native resource acceptance is implied.
final class DuelPanguSourceRetakeTests: XCTestCase {
    private typealias F = DuelSourceThrowFixture

    private func catalog(activeFeetY: Double = 0, activeCOMX: Double = 0) throws -> DuelWeaponCatalog {
        let rules = try DuelPanguRules.d19HeavenlyKing(level: 2, maximumHealth: 1000,
            weaponPower: 1000, unarmedPower: 1000, magicPower: 1000, rangedPower: 1000,
            spatialTemplate: DuelPanguTestFixture.rules(level: 2))
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rules))
        return try DuelWeaponTestFixtures.changing(F.catalog(pangu: true)) { profiles in
            for owner in profiles.indices {
                if profiles[owner]["id"] as? String == "liu_pangu" { profiles[owner]["panguRules"] = encoded }
                var clips = profiles[owner]["clips"] as! [[String: Any]]
                for index in clips.indices {
                    guard let name = clips[index]["name"] as? String,
                          name.hasPrefix("synthetic_source_") else { continue }
                    var tracks = clips[index]["tracks"] as! [String: Any]
                    let count = (tracks["root"] as! [[Double]]).count
                    let active = name == "synthetic_source_panguActive"
                    let feet = Array(repeating: [0.0, active ? activeFeetY : 0.0, 0.0], count: count)
                    tracks["footL"] = feet; tracks["footR"] = feet
                    if active {
                        tracks["centerOfMass"] = Array(repeating: [activeCOMX, 1.0, 0.0], count: count)
                    }
                    clips[index]["tracks"] = tracks
                }
                profiles[owner]["clips"] = clips
            }
        }
    }

    private func fight(facing: Int = 1, panguFirst: Bool = false,
                       activeFeetY: Double = 0, activeCOMX: Double = 0,
                       mode: DuelGame.Mode = .practice, initiatorHealth: Int = 1000) throws -> DuelWeaponFight {
        let firstX = facing > 0 ? 4000 : 6000
        var fighters: [DuelGame.Fighter] = [
            .init(hero: panguFirst ? .liu : .ember, x: firstX, facing: facing),
            .init(hero: panguFirst ? .ember : .liu, x: firstX + 800 * facing, facing: -facing)
        ]
        fighters[panguFirst ? 1 : 0].health = initiatorHealth
        return try XCTUnwrap(.init(fighters: fighters, mode: mode, difficulty: .learning,
            catalog: catalog(activeFeetY: activeFeetY, activeCOMX: activeCOMX), seed: 41))
    }

    private func attempt(_ fight: inout DuelWeaponFight, initiator: Int, both: Bool = false) {
        let input = DuelGame.Input(weaponCommand: .weaponBack)
        fight.step(initiator == 0 || both ? input : .neutral,
                   opponent: initiator == 1 || both ? input : .neutral)
    }

    private func escapes(_ fight: DuelWeaponFight) -> Int {
        fight.panguPresentationEvents.filter {
            if case .ordinaryThrowEscaped = $0.kind { return true }; return false
        }.count
    }

    func testRecord248WindowUsesTheObservedCurrentOrNextSampleAndClosesAtEnd() throws {
        var state = try F.state(.panguEscape)
        for _ in 0..<133 { _ = state.advance() }
        XCTAssertFalse(state.owns(0)); XCTAssertTrue(state.owns(1))
        XCTAssertFalse(state.permitsPanguRecoveryTakeover(1, sampleTick: 133))
        XCTAssertTrue(state.permitsPanguRecoveryTakeover(1, sampleTick: 134))
        XCTAssertFalse(state.permitsPanguRecoveryTakeover(1, sampleTick: 135), "A fabricated future sample is rejected")
        XCTAssertFalse(state.permitsPanguRecoveryTakeover(0, sampleTick: 134))
        _ = state.advance()
        XCTAssertTrue(state.permitsPanguRecoveryTakeover(1, sampleTick: 134))
        XCTAssertFalse(state.canInterrupt(1), "The source Throwable window overlaps Uninterrupt")
        for _ in 134..<153 { _ = state.advance() }
        XCTAssertTrue(state.permitsPanguRecoveryTakeover(1, sampleTick: 153))
        XCTAssertFalse(state.permitsPanguRecoveryTakeover(1, sampleTick: 154))
        _ = state.advance()
        XCTAssertTrue(state.isFinished)
        XCTAssertFalse(state.permitsPanguRecoveryTakeover(1, sampleTick: 154))
    }

    func testTakeoverNeverDropsAnUnreleasedPartnerOrAcceptsAnOrdinaryPair() throws {
        let extended = try F.changed(F.rules()) { object in
            var motions = object["motions"] as! [String: [String: Any]]
            // Deliberately different synthetic passive lifetime proves the
            // ownership predicate; it is not an alternative source timing.
            motions["panguPassive"]!["lastSampleTick"] = 220
            motions["panguPassive"]!["animationEndTick"] = 210
            motions["panguPassive"]!["uninterruptEndTick"] = 220
            motions["panguPassive"]!["rootMillimeters"] = Array(0...220)
            object["motions"] = motions
        }
        var both = try XCTUnwrap(DuelSourceThrowState(rules: extended, variant: .panguEscape,
            initiator: 0, target: 1, facing: 1, initiatorX: 4000, counterUnarmedPower: 1000))
        for _ in 0..<134 { _ = both.advance() }
        XCTAssertTrue(both.owns(0)); XCTAssertTrue(both.owns(1))
        XCTAssertFalse(both.permitsPanguRecoveryTakeover(1, sampleTick: 134))
        let unchanged = both
        XCTAssertFalse(both.permitsPanguRecoveryTakeover(1, sampleTick: 135)); XCTAssertEqual(both, unchanged)
        both.release(0)
        XCTAssertTrue(both.permitsPanguRecoveryTakeover(1, sampleTick: 134))
        both.cancel(); XCTAssertFalse(both.permitsPanguRecoveryTakeover(1, sampleTick: 134))

        for variant in [DuelSourceThrowRules.Variant.back, .forward] {
            var ordinary = try F.state(variant)
            for _ in 0..<134 { _ = ordinary.advance() }
            for actor in 0..<2 {
                XCTAssertFalse(ordinary.permitsPanguRecoveryTakeover(actor, sampleTick: 134))
            }
        }
    }

    func testRealRecoveryAcceptsPrepared134Not133AndNewPairCannotAdvanceOrDamageEarly() throws {
        for facing in [-1, 1] {
            for panguFirst in [false, true] {
                let owner = panguFirst ? 0 : 1, initiator = 1 - owner
                var baseline = try fight(facing: facing, panguFirst: panguFirst)
                attempt(&baseline, initiator: initiator)
                F.advance(&baseline, 132)
                XCTAssertNil(baseline.sourceThrow(initiator))
                XCTAssertEqual(baseline.sourceThrow(owner)?.tick, 132)
                XCTAssertEqual(baseline.landedHits[owner], 1)
                var early = baseline
                attempt(&early, initiator: initiator)
                XCTAssertEqual(early.sourceThrow(owner)?.tick, 133)
                XCTAssertNil(early.sourceThrow(initiator)); XCTAssertEqual(escapes(early), 0)

                F.advance(&baseline, 1)
                attempt(&baseline, initiator: initiator, both: true)
                let replacement = try XCTUnwrap(baseline.sourceThrow(owner))
                XCTAssertEqual(replacement, baseline.sourceThrow(initiator))
                XCTAssertEqual(replacement.tick, 0, "The old advancing snapshot must not advance a replacement")
                XCTAssertTrue(replacement.owns(owner)); XCTAssertTrue(replacement.owns(initiator))
                XCTAssertFalse(replacement.damageApplied); XCTAssertEqual(escapes(baseline), 1)
                XCTAssertFalse(baseline.canBeThrown(owner))
                let poses = baseline.sourceMotionSamples.filter { $0.owner == owner && $0.clip == "synthetic_source_panguActive" }
                XCTAssertEqual(poses.map(\.tick), [134, 0], "The real current sample is observed before the exact replacement start")
                XCTAssertEqual(baseline.fighters[owner].weaponPose?.tick, 0)
                XCTAssertEqual(baseline.fighters[initiator].health, 849)
                F.advance(&baseline, 20)
                XCTAssertEqual(baseline.sourceThrow(owner)?.tick, 20, "The old AnimationEnd at154 cannot release the new pair")
                XCTAssertNotNil(baseline.sourceThrow(initiator))
                F.advance(&baseline, 77)
                XCTAssertEqual(baseline.sourceThrow(owner)?.tick, 97)
                XCTAssertEqual(baseline.fighters[initiator].health, 849)
                XCTAssertEqual(baseline.landedHits[owner], 1)
                F.advance(&baseline, 1)
                XCTAssertEqual(baseline.sourceThrow(owner)?.tick, 98)
                XCTAssertEqual(baseline.fighters[initiator].health, 696)
                XCTAssertEqual(baseline.landedHits[owner], 2)
                XCTAssertEqual(baseline.damageDealt[owner], 304, "151 then153: two separate .15 source hits with normal PreHit")
                F.advance(&baseline, 14)
                XCTAssertNil(baseline.sourceThrow(initiator)); XCTAssertNotNil(baseline.sourceThrow(owner))
                XCTAssertEqual(baseline.landedHits[owner], 2)
            }
        }
    }

    func testCounterRecoveryStillHonorsGroundCOMAndBusyInitiatorGates() throws {
        for (feet, com) in [(0.3, 0.0), (0.0, -2.0)] {
            var blocked = try fight(activeFeetY: feet, activeCOMX: com)
            attempt(&blocked, initiator: 0)
            F.advance(&blocked, 133)
            attempt(&blocked, initiator: 0)
            XCTAssertNil(blocked.sourceThrow(0))
            XCTAssertEqual(blocked.sourceThrow(1)?.tick, 134)
            XCTAssertEqual(escapes(blocked), 0)
            XCTAssertEqual(blocked.landedHits[1], 1)
        }
        var jumping = try fight()
        attempt(&jumping, initiator: 0); F.advance(&jumping, 130)
        jumping.step(.init(taps: .jump), opponent: .neutral)
        F.advance(&jumping, 2)
        XCTAssertTrue(jumping.isAirborne(0))
        attempt(&jumping, initiator: 0)
        XCTAssertNil(jumping.sourceThrow(0)); XCTAssertEqual(jumping.sourceThrow(1)?.tick, 134)
        XCTAssertEqual(escapes(jumping), 0)
    }

    func testCounterRetakeDoesNotRefundOrResetTheOwnersPanguState() throws {
        var value = try fight()
        value.step(.neutral, opponent: .init(move: 1, weaponCommand: .shadow))
        XCTAssertEqual(value.panguState(1)?.activeCast?.ability, .typhoon)
        F.advance(&value, 67); attempt(&value, initiator: 0)
        XCTAssertEqual(value.sourceThrow(1)?.tick, 0)
        F.advance(&value, 133)
        var expected = try XCTUnwrap(value.panguState(1))
        _ = expected.step() // Only the ordinary live core tick elapses.
        attempt(&value, initiator: 0)
        let actual = try XCTUnwrap(value.panguState(1))
        XCTAssertEqual(value.sourceThrow(1)?.tick, 0)
        XCTAssertEqual(actual.light, expected.light); XCTAssertEqual(actual.combo, expected.combo)
        XCTAssertEqual(actual.comboRemainingTicks, expected.comboRemainingTicks)
        XCTAssertEqual(actual.rangedCharges, expected.rangedCharges)
        XCTAssertEqual(actual.typhoonRemainingTicks, expected.typhoonRemainingTicks)
        XCTAssertEqual(actual.typhoonCycle, expected.typhoonCycle)
        XCTAssertEqual(actual.stormGateUses, expected.stormGateUses)
        for ability in DuelPanguRules.Ability.allCases {
            XCTAssertEqual(actual.cooldownRemaining(ability), expected.cooldownRemaining(ability))
        }
        XCTAssertNil(actual.activeCast)
    }

    func testRepeatedRecoveryTakeoversHaveOneDeterministicPairAndCanonicalState() throws {
        var a = try fight(facing: -1, panguFirst: true), b = a
        attempt(&a, initiator: 1); attempt(&b, initiator: 1)
        for iteration in 0..<2 {
            for _ in 0..<133 {
                a.step(.neutral, opponent: .neutral); b.step(.neutral, opponent: .neutral)
            }
            XCTAssertEqual(a.landedHits[0], iteration + 1)
            let before = try DuelReplayStateEncoding.encode(a)
            attempt(&a, initiator: 1); attempt(&b, initiator: 1)
            XCTAssertNotEqual(try DuelReplayStateEncoding.encode(a), before)
            XCTAssertEqual(try DuelReplayStateEncoding.encode(a), try DuelReplayStateEncoding.encode(b))
            XCTAssertEqual(a.sourceThrow(0), a.sourceThrow(1))
            XCTAssertEqual(a.sourceThrow(0)?.tick, 0)
            XCTAssertEqual(escapes(a), 1)
        }
        F.advance(&a, 97); F.advance(&b, 97)
        XCTAssertEqual(a.landedHits[0], 2)
        F.advance(&a, 1); F.advance(&b, 1)
        XCTAssertEqual(a.landedHits[0], 3)
        XCTAssertEqual(try DuelReplayStateEncoding.encode(a), try DuelReplayStateEncoding.encode(b))
    }

    func testUntouchedCounterTailStillEndsAt154WithoutOpeningOrdinaryThrows() throws {
        var value = try fight()
        attempt(&value, initiator: 0); F.advance(&value, 112)
        XCTAssertNil(value.sourceThrow(0)); XCTAssertNotNil(value.sourceThrow(1))
        F.advance(&value, 41)
        XCTAssertEqual(value.sourceThrow(1)?.tick, 153)
        XCTAssertFalse(value.canBeThrown(1)); XCTAssertEqual(value.landedHits, [0, 1])
        F.advance(&value, 1)
        XCTAssertNil(value.sourceThrow(0)); XCTAssertNil(value.sourceThrow(1))
        XCTAssertEqual(value.fighters[1].weaponPose?.clip, value.profiles[1].roles["idle"])
        XCTAssertEqual(value.landedHits, [0, 1])
    }

    func testRoundResetAfterReplacementCannotCarryOldPairOr98Damage() throws {
        var value = try fight(mode: .versus, initiatorHealth: 200)
        attempt(&value, initiator: 0); F.advance(&value, 133)
        XCTAssertEqual(value.fighters[0].health, 49)
        attempt(&value, initiator: 0); F.advance(&value, 98)
        XCTAssertEqual(value.fighters[0].health, 0); XCTAssertEqual(value.landedHits[1], 2)
        XCTAssertTrue(DuelPanguFightFixture.until(&value, limit: 200) { $0.roundNumber == 2 && $0.phase == .fighting })
        XCTAssertNil(value.sourceThrow(0)); XCTAssertNil(value.sourceThrow(1))
        F.advance(&value, 120)
        XCTAssertEqual(value.fighters[0].health, 1000)
        XCTAssertNil(value.sourceThrow(0)); XCTAssertNil(value.sourceThrow(1))
        XCTAssertTrue(value.panguPresentationEvents.allSatisfy {
            if case .ordinaryThrowEscaped = $0.kind { return false }; return true
        })
    }
}
