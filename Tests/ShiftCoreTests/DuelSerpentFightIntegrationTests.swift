import Foundation
import XCTest
@testable import ShiftCore

final class DuelSerpentFightIntegrationTests: XCTestCase {
    private func profile(_ name: String) throws -> DuelWeaponProfile {
        guard let path = ProcessInfo.processInfo.environment[name] else {
            throw XCTSkip("Authenticated match resource required: \(name)")
        }
        return try JSONDecoder().decode(DuelWeaponProfile.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }
    private func catalog(integerTarget: Bool = false) throws -> DuelWeaponCatalog {
        let liu = try profile("SERPENT_MATCH_PROFILE")
        var wu = try profile("ERLANG_MATCH_PROFILE")
        if integerTarget {
            // Deliberate legacy-health test adapter using the actual second
            // rig's FK. This synthetic identity is never an output game asset.
            wu = .init(id: "sun_katana", hero: .ember, faction: wu.faction,
                resourceName: "Synthetic_Integer_Target", bytes: wu.bytes, sha256: wu.sha256,
                bodyID: wu.bodyID, weaponID: wu.weaponID, activeWeaponSides: wu.activeWeaponSides,
                roles: wu.roles.filter { !$0.key.hasPrefix("erlang") },
                clips: wu.clips.filter { $0.frames > 1 }, combatRules: nil, ordinaryThrows: wu.ordinaryThrows)
        }
        return .init(schemaVersion: 1, previewFramesPerSecond: 30, sourceFramesPerSecond: 60,
                     profiles: [liu, wu])
    }
    private func fight(direction: Int = 1, mode: DuelGame.Mode = .practice,
                       integerTarget: Bool = false, distance: Int = 1800, seed: UInt64 = 19) throws -> DuelWeaponFight {
        let catalog = try catalog(integerTarget: integerTarget)
        try catalog.validate()
        return try XCTUnwrap(DuelWeaponFight(fighters: [
            .init(hero: .liu, x: direction == 1 ? 3500 : 6500, facing: direction),
            .init(hero: integerTarget ? .ember : .wuYong,
                  x: (direction == 1 ? 3500 : 6500) + distance * direction, facing: -direction)
        ], mode: mode, difficulty: .learning, catalog: catalog, seed: seed))
    }

    private func approachWithLiveInput(_ value: inout DuelWeaponFight) {
        for _ in 0..<600 {
            if abs(value.fighters[1].x - value.fighters[0].x) <= 800 {
                value.step(.neutral, opponent: .neutral); return
            }
            value.step(.init(move: value.fighters[1].x > value.fighters[0].x ? 1 : -1), opponent: .neutral)
        }
        XCTFail("The actual source walk did not reach the opposing body")
    }

    private func nextHookContact(_ value: inout DuelWeaponFight, guardHeld: Bool) throws -> (DuelWeaponFight.Contact, Int) {
        value.step(.init(weaponCommand: .weapon), opponent: .init(guardHeld: guardHeld))
        for _ in 0..<120 {
            let previousHealth = value.fighters[1].health
            value.step(.neutral, opponent: .init(guardHeld: guardHeld))
            if let contact = value.contacts.first(where: { $0.attacker == 0 }) {
                return (contact, previousHealth - value.fighters[1].health)
            }
        }
        return (try XCTUnwrap(value.contacts.first(where: { $0.attacker == 0 }),
                              "Expected the actual shuangou contact"), 0)
    }

    func testActualBodyAndWuCatalogStartInSharedFightWithoutLegacyHammerOrShadowFallback() throws {
        let value = try fight()
        XCTAssertEqual(value.profiles.map(\.id), ["liu_serpent", "wuyong_erlang"])
        XCTAssertEqual(value.profiles[0].clips.count, 66)
        XCTAssertEqual(value.profiles[1].clips.count, 62)
        XCTAssertEqual(value.maximumHealth(0), 2000)
        XCTAssertEqual(value.fighters[0].energy, 0)
        XCTAssertTrue(value.supports(.weapon, index: 0))
        XCTAssertTrue(value.canUseSerpent(.bottle, index: 0))
        XCTAssertFalse(value.canUseSerpent(.poison, index: 0))
        XCTAssertFalse(value.supports(.shadow, index: 0))
        XCTAssertNil(value.panguState(0)); XCTAssertNil(value.shadowVisual(0))
        XCTAssertNil(DuelMultiplayerSelection.Weapon(rawValue: "liu_serpent"))
    }

    func testActualBottleZeroEightFiftySixClockAndFrozenOwnerAnchorInBothFacings() throws {
        for direction in [1, -1] {
            var value = try fight(direction: direction)
            value.step(.init(weaponCommand: .ranged), opponent: .neutral)
            XCTAssertEqual(value.serpentRuntime(0)?.actions.playback?.motionTick, 0)
            XCTAssertEqual(value.fighters[0].weaponPose?.clip, "d13_bottle_throw")
            XCTAssertEqual(value.serpentRuntime(0)?.actions.rangedUsagesLeft, 0)
            XCTAssertNil(value.serpentRuntime(0)?.bottle)
            var observed: [String: Int] = [:]
            for tick in 1...130 {
                value.step(.neutral, opponent: .neutral)
                for event in value.serpentEvents {
                    if case .model(.bottleBorn) = event.effect { observed["bottle"] = tick }
                    if case .model(.cloudBorn) = event.effect { observed["cloud"] = tick }
                }
                if tick < 8 { XCTAssertNil(value.serpentRuntime(0)?.bottle) }
            }
            XCTAssertEqual(observed, ["bottle": 8, "cloud": 56])
            let cloud = try XCTUnwrap(value.serpentRuntime(0)?.cloud)
            XCTAssertEqual(cloud.direction, direction)
            for _ in 0..<35 { value.step(.init(move: -direction), opponent: .neutral) }
            XCTAssertEqual(value.serpentRuntime(0)?.cloud?.rootX, cloud.rootX)
            XCTAssertFalse(value.canUseSerpent(.bottle, index: 0))
        }
    }

    func testRealRainLowersBothNormalizedAndIntegerHealthWithoutInventingPhysicalHits() throws {
        for legacy in [false, true] {
            var value = try fight(integerTarget: legacy)
            let initial = value.fighters[1].health
            value.step(.init(weaponCommand: .ranged), opponent: .neutral)
            for _ in 0..<150 { value.step(.neutral, opponent: .neutral) }
            XCTAssertLessThan(value.fighters[1].health, initial)
            XCTAssertGreaterThan(value.damageDealt[0], 0)
            XCTAssertEqual(value.landedHits[0], 0)
            XCTAssertEqual(value.hitStop, 0)
            XCTAssertEqual(value.fighters[0].energy, 0)
            XCTAssertTrue(value.contacts.isEmpty)
            XCTAssertTrue(value.serpentRuntime(0)?.actions.state.hasStoredPoison == true)
        }
    }

    func testCloudOutsideZoneDoesNotGrantPoisonOrDamage() throws {
        var value = try fight(distance: 5500)
        let initial = value.fighters[1].health
        value.step(.init(weaponCommand: .ranged), opponent: .neutral)
        for _ in 0..<350 { value.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(value.fighters[1].health, initial)
        XCTAssertEqual(value.damageDealt[0], 0)
        XCTAssertFalse(value.serpentRuntime(0)?.actions.state.hasStoredPoison ?? true)
    }

    func testPoisonUsesRealActionAndConsumesStoresOnlyAtOriginalReleaseTick() throws {
        var value = try fight(mode: .versus)
        value.step(.init(weaponCommand: .ranged), opponent: .neutral)
        for _ in 0..<115 { value.step(.neutral, opponent: .neutral) }
        XCTAssertTrue(value.canUseSerpent(.poison, index: 0))
        value.step(.init(taps: .skill1), opponent: .neutral)
        XCTAssertEqual(value.serpentRuntime(0)?.actions.playback?.motionTick, 0)
        XCTAssertEqual(value.fighters[0].weaponPose?.clip, "d13_ability")
        for tick in 1...166 {
            value.step(.neutral, opponent: .neutral)
            let explosions = value.serpentEvents.filter {
                if case .action(let action) = $0.effect, case .poisonExplosion = action.effect { return true }
                return false
            }
            XCTAssertEqual(explosions.count, tick == 166 ? 1 : 0)
        }
        XCTAssertEqual(value.serpentRuntime(0)?.actions.state.poisonAbilityCooldownRemaining, 420)
    }

    func testControlsKeepInputLockArmorAndThrowWindowIndependent() throws {
        let profile = try profile("SERPENT_MATCH_PROFILE")
        let binding = try XCTUnwrap(profile.serpentBinding)
        XCTAssertNoThrow(try binding.validate(profile: profile))
        for tick in [0, 7, 8, 39, 40, 94, 104] {
            XCTAssertTrue(binding.contains(.uninterrupt, clip: "d13_bottle_throw", tick: tick))
            XCTAssertEqual(binding.contains(.unbreakable, clip: "d13_bottle_throw", tick: tick), (8...39).contains(tick))
            XCTAssertEqual(binding.contains(.throwable, clip: "d13_bottle_throw", tick: tick), tick >= 94)
        }
        XCTAssertFalse(binding.contains(.unbreakable, clip: "d13_ability", tick: 166))
    }

    func testPoisonRecoveryAcceptsHeldGuardWithoutAutoGuardOrDiscardingItsSourcePose() throws {
        for direction in [1, -1] {
            var value = try fight(direction: direction, mode: .versus, distance: 800)
            // One real hook contact supplies a small poison store. A full rain
            // followed by the explosion would KO this opponent at tick 166,
            // correctly ending the round before the recovery under test.
            value.step(.init(weaponCommand: .weapon), opponent: .neutral)
            for _ in 0..<100 { value.step(.neutral, opponent: .neutral) }
            XCTAssertGreaterThan(value.landedHits[0], 0)
            XCTAssertTrue(value.canUseSerpent(.poison, index: 0))
            value.step(.init(taps: .skill1), opponent: .neutral)
            for tick in 1...215 {
                value.step(.init(guardHeld: true), opponent: .neutral)
                XCTAssertFalse(value.fighters[0].guarding, "No Blocking interval at source tick \(tick)")
            }
            XCTAssertEqual(value.serpentRuntime(0)?.actions.playback?.motionTick, 215)
            let recovery = value
            value.step(.init(guardHeld: true), opponent: .neutral)
            XCTAssertTrue(value.fighters[0].guarding)
            XCTAssertEqual(value.fighters[0].weaponPose?.clip, "d13_ability")
            XCTAssertEqual(value.fighters[0].weaponPose?.tick, 216)
            XCTAssertEqual(value.serpentRuntime(0)?.actions.playback?.motionTick, 216)
            value.step(.neutral, opponent: .neutral)
            XCTAssertFalse(value.fighters[0].guarding, "Releasing the control must end guard immediately")
            XCTAssertEqual(value.serpentRuntime(0)?.actions.playback?.motionTick, 217)

            var neutral = recovery
            neutral.step(.neutral, opponent: .neutral)
            XCTAssertFalse(neutral.fighters[0].guarding, "A Blocking interval does not enable automatic defense")
            for input in [DuelGame.Input(move: direction, guardHeld: true),
                          .init(guardHeld: true, vertical: -1),
                          .init(guardHeld: true, weaponCommand: .weapon)] {
                var incompatible = recovery
                incompatible.step(input, opponent: .neutral)
                XCTAssertFalse(incompatible.fighters[0].guarding)
            }
        }
    }

    func testBottleInputLockDoesNotHideItsActualThrowableRecoveryWindow() throws {
        var value = try fight(distance: 5500)
        value.step(.init(weaponCommand: .ranged), opponent: .neutral)
        let firstPlayback = try XCTUnwrap(value.serpentRuntime(0)?.actions.playback?.id)
        for tick in 1...103 {
            // A pressed attack, movement and guard cannot cancel the authored
            // lock or fabricate armor. The throw window is independently open
            // at 94, even while the body still owns its locked animation.
            value.step(.init(move: 1, guardHeld: true, weaponCommand: .weapon), opponent: .neutral)
            XCTAssertEqual(value.serpentRuntime(0)?.actions.playback?.id, firstPlayback)
            XCTAssertEqual(value.serpentRuntime(0)?.actions.playback?.motionTick, tick)
            XCTAssertEqual(value.fighters[0].weaponPose?.clip, "d13_bottle_throw")
            XCTAssertFalse(value.fighters[0].guarding)
            XCTAssertEqual(value.canBeThrown(0), tick >= 94)
        }
        value.step(.neutral, opponent: .neutral)
        XCTAssertNil(value.serpentRuntime(0)?.actions.playback, "The original AnimationEnd occurs at tick 104")
        value.step(.neutral, opponent: .neutral)
        XCTAssertEqual(value.fighters[0].weaponPose?.clip, value.profiles[0].clip(role: "idle")?.name,
                       "Commands rejected during the lock must not play later")
        XCTAssertTrue(value.canBeThrown(0))
        XCTAssertEqual(value.serpentRuntime(0)?.actions.rangedUsagesLeft, 0)
    }

    func testActualShuangouRecoveryUsesIndependentGuardAndThrowIntervals() throws {
        var value = try fight(distance: 5500)
        value.step(.init(weaponCommand: .weapon), opponent: .neutral)
        XCTAssertEqual(value.fighters[0].weaponPose?.clip, "shuangou_slash_1")
        XCTAssertFalse(value.canBeThrown(0))
        for tick in 1...49 {
            value.step(.init(guardHeld: true), opponent: .neutral)
            XCTAssertEqual(value.fighters[0].weaponPose?.tick, tick)
            XCTAssertFalse(value.fighters[0].guarding)
            XCTAssertEqual(value.canBeThrown(0), tick >= 38,
                           "The source Throwable interval begins before Blocking")
        }
        let recovery = value
        value.step(.init(guardHeld: true), opponent: .neutral)
        XCTAssertEqual(value.fighters[0].weaponPose?.clip, "shuangou_slash_1")
        XCTAssertEqual(value.fighters[0].weaponPose?.tick, 50)
        XCTAssertTrue(value.fighters[0].guarding)
        XCTAssertTrue(value.canBeThrown(0))
        value.step(.neutral, opponent: .neutral)
        XCTAssertFalse(value.fighters[0].guarding)
        var neutral = recovery
        neutral.step(.neutral, opponent: .neutral)
        XCTAssertFalse(neutral.fighters[0].guarding)
    }

    func testActualSourceThrowCanReplaceShuangouThrowableRecovery() throws {
        var value = try fight(distance: DuelGame.bodyWidth)
        value.step(.init(weaponCommand: .weapon), opponent: .neutral)
        // The opponent first receives the real FK contact, then finishes its
        // actual hit reaction. The remaining shuangou recovery is Throwable;
        // no fabricated action, source interval or target position is injected.
        for _ in 0..<120 {
            let opponentRecovered = value.landedHits[0] > 0 && value.hitStop == 0 &&
                value.fighters[1].stun == 0 &&
                ["idle", "walkForward"].contains { role in
                    value.fighters[1].weaponPose?.clip == value.profiles[1].clip(role: role)?.name
                }
            let inRange: Bool
            if let ownCOM = value.sourceCenterOfMass(1), let targetCOM = value.sourceCenterOfMass(0) {
                inRange = value.profiles[1].ordinaryThrows?.source?.inRange(
                    distanceMillimeters: abs(ownCOM.x - targetCOM.x) * 1000) == true
            } else { inRange = false }
            if opponentRecovered, inRange,
               value.fighters[0].weaponPose?.clip == "shuangou_slash_1",
               (value.fighters[0].weaponPose?.tick ?? 0) >= 38 { break }
            // The hit's real recoil can leave COM just outside the throw
            // radius. Close it with live walking after the reaction ends.
            value.step(.neutral, opponent: opponentRecovered ? .init(move: -1) : .neutral)
        }
        XCTAssertGreaterThan(value.landedHits[0], 0)
        XCTAssertEqual(value.fighters[0].weaponPose?.clip, "shuangou_slash_1")
        XCTAssertEqual(value.fighters[1].stun, 0)
        XCTAssertTrue(value.canBeThrown(0))
        let ownCOM = try XCTUnwrap(value.sourceCenterOfMass(1))
        let targetCOM = try XCTUnwrap(value.sourceCenterOfMass(0))
        let rules = try XCTUnwrap(value.profiles[1].ordinaryThrows?.source)
        XCTAssertTrue(rules.inRange(distanceMillimeters: abs(ownCOM.x - targetCOM.x) * 1000))
        value.step(.neutral, opponent: .init(weaponCommand: .weaponBack))
        let pair = try XCTUnwrap(value.sourceThrow(1))
        XCTAssertEqual(pair.initiator, 1)
        XCTAssertEqual(pair.target, 0)
        XCTAssertEqual(pair.tick, 0)
        XCTAssertTrue(pair.owns(0))
        XCTAssertNil(value.fighters[0].attack)
        XCTAssertNotEqual(value.fighters[0].weaponPose?.clip, "shuangou_slash_1")
    }

    func testWeaponPoisonBuffBreaksHeldGuardForItsRealLifetime() throws {
        var value = try fight(mode: .versus, distance: 800)
        value.step(.init(weaponCommand: .weapon), opponent: .neutral)
        for _ in 0..<100 { value.step(.neutral, opponent: .neutral) }
        value.step(.init(taps: .skill1), opponent: .neutral)
        for _ in 0..<230 { value.step(.neutral, opponent: .neutral) }
        XCTAssertGreaterThan(value.serpentRuntime(0)?.actions.state.poisonBuffRemaining(.weapon) ?? 0, 0)
        approachWithLiveInput(&value)
        var expired = value
        for _ in 0..<900 {
            if expired.serpentRuntime(0)?.actions.state.poisonBuffRemaining(.weapon) == 0 { break }
            expired.step(.neutral, opponent: .neutral)
        }
        XCTAssertEqual(expired.serpentRuntime(0)?.actions.state.poisonBuffRemaining(.weapon), 0)
        XCTAssertEqual(try nextHookContact(&value, guardHeld: true).0.kind, .hit)
        XCTAssertEqual(try nextHookContact(&expired, guardHeld: true).0.kind, .block)
    }

    func testRangedPoisonBuffAppliesOriginalDefenseFactorToAnOrdinaryHook() throws {
        // Seed zero chooses ranged for the first real cloud callback. The
        // opponent stands at the cloud edge and retreats after that callback,
        // leaving one genuine ranged store without taking the full rain.
        var value = try fight(mode: .versus, distance: 4500, seed: 0)
        value.step(.init(weaponCommand: .ranged), opponent: .neutral)
        var receivedRangedPulse = false
        for _ in 0..<120 {
            value.step(.neutral, opponent: receivedRangedPulse ? .init(move: 1) : .neutral)
            if value.serpentEvents.contains(where: {
                if case .model(.cloudPoison(.ranged, applied: true)) = $0.effect { return true }
                return false
            }) { receivedRangedPulse = true }
        }
        XCTAssertTrue(receivedRangedPulse)
        XCTAssertEqual(value.serpentRuntime(0)?.actions.state.dominantPoisonChannel, .ranged)
        value.step(.init(taps: .skill1), opponent: .neutral)
        for _ in 0..<230 { value.step(.neutral, opponent: .neutral) }
        XCTAssertGreaterThan(value.serpentRuntime(0)?.actions.state.poisonBuffRemaining(.ranged) ?? 0, 0)
        approachWithLiveInput(&value)
        var expired = value
        for _ in 0..<900 {
            if expired.serpentRuntime(0)?.actions.state.poisonBuffRemaining(.ranged) == 0 { break }
            expired.step(.neutral, opponent: .neutral)
        }
        XCTAssertEqual(expired.serpentRuntime(0)?.actions.state.poisonBuffRemaining(.ranged), 0)
        let activeHit = try nextHookContact(&value, guardHeld: false)
        let expiredHit = try nextHookContact(&expired, guardHeld: false)
        XCTAssertEqual(activeHit.0.kind, .hit); XCTAssertEqual(expiredHit.0.kind, .hit)
        // PreHit defense and final Hit damage are separate source stages:
        // 30 / .7 * .66 == 28.2857... before the target health conversion.
        // A live poison status can cross one further integer HUD point.
        XCTAssertTrue((28...29).contains(activeHit.1), "Actual HP loss: \(activeHit.1)")
        XCTAssertTrue((19...20).contains(expiredHit.1), "Actual HP loss: \(expiredHit.1)")
    }

    func testActualFinalHitScaleKeepsNormalizedHealthAndDoesNotScalePoisonModHP() throws {
        for legacy in [false, true] {
            var value = try fight(integerTarget: legacy, distance: 800)
            let initial = value.fighters[1].health
            let hit = try nextHookContact(&value, guardHeld: false)
            XCTAssertEqual(hit.0.kind, .hit)
            XCTAssertEqual(initial - value.fighters[1].health, legacy ? 19 : 20)
            let acceptedFraction: Double
            if legacy {
                acceptedFraction = 19.0 / Double(value.maximumHealth(1))
            } else {
                let health = try XCTUnwrap(value.erlangState(1)?.normalizedHealth)
                XCTAssertEqual(health, 1 - Float(30 * 0.66 / 2000), accuracy: 0.0000001)
                acceptedFraction = Double(1 - health)
            }
            let state = try XCTUnwrap(value.serpentRuntime(0)?.actions.state)
            XCTAssertEqual(state.poison(.weapon).amount,
                           acceptedFraction * state.coefficient(.weapon), accuracy: 0.000000001)
            XCTAssertEqual(state.bloom, acceptedFraction * 0.45, accuracy: 0.000000001)
            // The only strike already connected. Let its recovery and real
            // hit-stop finish, then measure only the separate ModHP status.
            for _ in 0..<100 { value.step(.neutral, opponent: .neutral) }
            XCTAssertEqual(value.hitStop, 0)
            XCTAssertNil(value.fighters[0].attack)
            if !legacy {
                let before = try XCTUnwrap(value.erlangState(1)?.normalizedHealth)
                let perTick = try XCTUnwrap(value.serpentRuntime(0)?.actions.state.poison(.weapon).damagePerTick)
                for _ in 0..<50 {
                    value.step(.neutral, opponent: .neutral)
                    XCTAssertTrue(value.contacts.isEmpty)
                }
                let after = try XCTUnwrap(value.erlangState(1)?.normalizedHealth)
                XCTAssertEqual(Double(before - after), perTick * 50, accuracy: 0.000002)
            }
        }
    }

    func testActualSourceThrowReceivesFinalHitScaleOnce() throws {
        var value = try fight(distance: DuelGame.bodyWidth)
        value.step(.init(weaponCommand: .weaponBack), opponent: .neutral)
        XCTAssertNotNil(value.sourceThrow(0))
        var connected = false
        for _ in 0..<160 {
            value.step(.neutral, opponent: .neutral)
            if value.contacts.contains(where: { $0.attacker == 0 }) {
                connected = true; break
            }
        }
        XCTAssertTrue(connected)
        XCTAssertEqual(value.landedHits[0], 1)
        XCTAssertEqual(value.damageDealt[0], 66)
        // Source throws resolve before this tick's serpent status update.
        // Their new unarmed poison therefore ticks once immediately. Ordinary
        // body contacts resolve after that update and begin on the next tick.
        let afterHit = 1 - Float(100 * 0.66 / 2000)
        let poison = Double(1 - afterHit) * (0.35 * 1.3)
        XCTAssertEqual(value.serpentRuntime(0)?.actions.state.poison(.unarmed).remainingTicks, 899)
        XCTAssertEqual(try XCTUnwrap(value.serpentRuntime(0)?.actions.state.poison(.unarmed).amount),
                       poison, accuracy: 0.000000000001)
        XCTAssertEqual(try XCTUnwrap(value.erlangState(1)?.normalizedHealth), afterHit - Float(poison / 900))
    }

    func testActualExchangesUnlockLifeDrainAndPreserveFractionalHealingOnMatchClock() throws {
        var value = try fight(mode: .versus, distance: 800)
        // Accumulate both authentic outgoing and incoming PostHit events.
        // Normal round replacement restores health through the match itself;
        // no health, Bloom value or passive timer is injected into the fixture.
        var checkpoints: [String] = []
        for setupTick in 0..<12_000 {
            if value.serpentRuntime(0)?.actions.state.lifeDrainActive == true { break }
            if case .matchOver = value.phase { break }
            let direction = value.fighters[1].x > value.fighters[0].x ? 1 : -1
            let near = abs(value.fighters[1].x - value.fighters[0].x) <= DuelGame.bodyWidth + 2
            let receive = value.fighters[0].health > value.maximumHealth(0) * 4 / 5
            var player = DuelGame.Input.neutral, opponent = DuelGame.Input.neutral
            if receive {
                if !near { opponent = .init(move: -direction) }
                else if value.canUse(.kickForward, index: 1), value.fighters[1].attack == nil,
                        value.fighters[1].stun == 0 { opponent = .init(weaponCommand: .kickForward) }
            } else {
                if !near { player = .init(move: direction) }
                else if value.canUse(.heavy, index: 0), value.fighters[0].attack == nil,
                        value.fighters[0].stun == 0 { player = .init(weaponCommand: .heavy) }
            }
            value.step(player, opponent: opponent)
            if setupTick % 360 == 0 {
                checkpoints.append("\(setupTick): round=\(value.roundNumber) hp=\(value.fighters.map(\.health)) x=\(value.fighters.map(\.x)) bloom=\(value.serpentRuntime(0)?.actions.state.bloom ?? 0) poses=\(value.fighters.map { $0.weaponPose?.clip ?? "nil" }) hits=\(value.landedHits)")
            }
        }
        guard value.serpentRuntime(0)?.actions.state.lifeDrainActive == true else {
            return XCTFail("Authentic contacts did not unlock life drain: \(checkpoints.joined(separator: "\n"))")
        }
        XCTAssertGreaterThan(value.roundNumber, 1)
        XCTAssertGreaterThan(value.damageDealt[0], 0); XCTAssertGreaterThan(value.damageDealt[1], 0)
        // Allow the last actually accepted attack to finish before measuring
        // healing; a held attack is never queued during the setup above.
        for _ in 0..<250 {
            if value.hitStop == 0, value.fighters.allSatisfy({ $0.attack == nil && $0.stun == 0 }) { break }
            value.step(.neutral, opponent: .neutral)
        }
        XCTAssertEqual(value.phase, .fighting)
        let wounded = value.fighters[0].health
        XCTAssertGreaterThan(wounded, 0); XCTAssertLessThan(wounded, value.maximumHealth(0))
        let liveTick = try XCTUnwrap(value.serpentRuntime(0)?.liveTick)
        var sourceHealing = 0.0
        for _ in 0..<60 {
            value.step(.neutral, opponent: .neutral)
            sourceHealing += try XCTUnwrap(value.serpentRuntime(0)?.actions.state.healingThisTick)
                * Double(value.maximumHealth(0))
        }
        XCTAssertEqual(value.serpentRuntime(0)?.liveTick, liveTick + 60)
        XCTAssertGreaterThan(value.fighters[0].health, wounded,
                             "Sub-HP source ModHP must accumulate in the integer arena health domain")
        // The earlier live ticks may retain a fraction in [0, 1), so the
        // observed integer gain has only those two possible rounded values.
        let wholeSourceHealing = Int(sourceHealing.rounded(.down))
        XCTAssertTrue((wholeSourceHealing...wholeSourceHealing + 1)
            .contains(value.fighters[0].health - wounded))
        XCTAssertLessThanOrEqual(value.fighters[0].health, value.maximumHealth(0))
        XCTAssertEqual(value.hitStop, 0)
    }

    func testEqualSeedAndInputsKeepAuthoritativeCloudChannelsAndHealthEqual() throws {
        var a = try fight(), b = a
        for tick in 0..<380 {
            let input: DuelGame.Input = tick == 0 ? .init(weaponCommand: .ranged) :
                tick == 120 ? .init(taps: .skill1) : .neutral
            a.step(input, opponent: .neutral); b.step(input, opponent: .neutral)
            XCTAssertEqual(a.fighters, b.fighters)
            XCTAssertEqual(a.serpentRuntime(0), b.serpentRuntime(0))
            XCTAssertEqual(a.serpentEvents, b.serpentEvents)
        }
        XCTAssertEqual(try DuelReplayStateEncoding.encode(a), try DuelReplayStateEncoding.encode(b))
    }

    func testActualWeaponCollisionGrantsPoisonAndHitStopFreezesTheWholeRuntime() throws {
        var value = try fight(distance: 800)
        value.step(.init(weaponCommand: .weapon), opponent: .neutral)
        for _ in 0..<120 where value.hitStop == 0 { value.step(.neutral, opponent: .neutral) }
        XCTAssertGreaterThan(value.landedHits[0], 0)
        XCTAssertGreaterThan(value.hitStop, 0)
        XCTAssertGreaterThan(value.serpentRuntime(0)?.actions.state.poison(.weapon).amount ?? 0, 0)
        let state = value.serpentRuntime(0), health = value.fighters[1].health
        value.step(.neutral, opponent: .neutral)
        XCTAssertEqual(value.serpentRuntime(0), state)
        XCTAssertEqual(value.fighters[1].health, health)
    }

    func testRoundReplacementClearsOldCloudAndTargetPoisonWithoutRefundingTheBottle() throws {
        var value = try fight(mode: .versus)
        value.step(.init(weaponCommand: .ranged), opponent: .neutral)
        for _ in 0..<3600 {
            if case .roundBreak = value.phase { break }
            value.step(.neutral, opponent: .neutral)
        }
        guard case .roundBreak = value.phase else { return XCTFail("Expected a completed real round") }
        let stopped = try XCTUnwrap(value.serpentRuntime(0))
        XCTAssertFalse(stopped.actions.state.roundActive)
        XCTAssertNil(stopped.bottle); XCTAssertNil(stopped.cloud); XCTAssertNil(stopped.pendingCloud)
        XCTAssertEqual(stopped.groundPoison.stacks, 0)
        XCTAssertFalse(stopped.actions.state.hasStoredPoison)
        XCTAssertTrue(stopped.actions.state.bottleUsed)
        for _ in 0..<10 { value.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(value.serpentRuntime(0), stopped)
        for _ in 0..<150 {
            if value.roundNumber == 2 { break }
            value.step(.neutral, opponent: .neutral)
        }
        XCTAssertEqual(value.roundNumber, 2)
        let health = value.fighters[1].health
        for _ in 0..<100 { value.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(value.fighters[1].health, health)
        XCTAssertFalse(value.canUseSerpent(.bottle, index: 0))
    }

    func testActualMatchAudioUsesSourceTicksAndRepeatedDisplayDoesNotReplay() throws {
        var value = try fight(), audio = DuelSerpentAudioTimeline()
        var heard: [(Int, String)] = []
        for tick in 0..<170 {
            let input: DuelGame.Input = tick == 0 ? .init(weaponCommand: .ranged) :
                tick == 120 ? .init(taps: .skill1) : .neutral
            value.step(input, opponent: .neutral)
            let commands = audio.consume(value.serpentEvents, frame: value.frame,
                fighting: value.phase == .fighting, paused: false, owners: [0])
            for command in commands {
                if case .play = command.operation { heard.append((tick, command.identifier)) }
            }
            XCTAssertTrue(audio.consume(value.serpentEvents, frame: value.frame,
                fighting: value.phase == .fighting, paused: false, owners: [0]).isEmpty)
        }
        XCTAssertEqual(heard.map { $0.0 }, [46, 56, 140, 156])
        XCTAssertEqual(heard.map { $0.1 }, [
            "set_d13/poison_rain_bottle@Battle@Movement", DuelSerpentRainRuntime.rainSound,
            "set_d13/poison_energy_cast@Battle@Movement",
            "shadow_moves/mind_throw/mind_throw_whoosh_1@Battle@Movement"
        ])
        XCTAssertEqual(audio.finish().map(\.operation), [.stop])
    }

    func testRuntimeBindingChangesCanonicalCatalogAndMissingOpponentLandmarkIsRejected() throws {
        let original = try catalog()
        let changed = try DuelWeaponTestFixtures.changing(original) { profiles in
            var binding = profiles[0]["serpentBinding"] as! [String: Any]
            binding["raidDamageAmplifier"] = 1.125
            profiles[0]["serpentBinding"] = binding
        }
        try changed.validate()
        XCTAssertEqual(original.profiles.map(\.sha256), changed.profiles.map(\.sha256))
        XCTAssertNotEqual(try DuelReplayStateEncoding.encodeCatalog(original),
                          try DuelReplayStateEncoding.encodeCatalog(changed))
        let missing = try DuelWeaponTestFixtures.changing(original) { profiles in
            var clips = profiles[1]["clips"] as! [[String: Any]]
            var tracks = clips[0]["tracks"] as! [String: Any]
            tracks.removeValue(forKey: "pelvis")
            clips[0]["tracks"] = tracks; profiles[1]["clips"] = clips
        }
        XCTAssertThrowsError(try missing.validate())
    }
}
