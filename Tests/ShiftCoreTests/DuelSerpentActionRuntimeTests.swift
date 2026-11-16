import Foundation
import XCTest
@testable import ShiftCore

final class DuelSerpentActionRuntimeTests: XCTestCase {
    private typealias Runtime = DuelSerpentActionRuntime
    private struct Oracle: Decodable {
        struct Motion: Decodable {
            struct Sound: Decodable { let tick: Int; let name: String }
            let action, role, alias, clipName, clipSHA256, releaseMarker: String
            let frames, playbackTicks, endEventTick, releaseTick: Int
            let sounds: [Sound]
        }
        struct Explosion: Decodable {
            struct Contact: Decodable { let channel: String; let damage: Double; let delay: Int }
            let level: Int
            let name: String
            let invincible: Bool
            let contacts: [Contact]
            let damage, amounts: [Double]
            let timers: [Int]
            let selected, last: String?
            let cooldown: Int
        }
        let schema, receiptSHA256, profileSHA256: String
        let motions: [Motion]
        let explosionCases: [Explosion]
    }
    private func sourceData(_ variable: String) throws -> Data {
        guard let path = ProcessInfo.processInfo.environment[variable] else {
            throw XCTSkip("Authenticated D13 source input required: \(variable)")
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }
    private func profile() throws -> DuelWeaponProfile {
        try JSONDecoder().decode(DuelWeaponProfile.self, from: sourceData("SERPENT_PHYSICAL_PROFILE"))
    }
    private func runtime(level: Int = 6, usages: Int = 2) throws -> Runtime {
        let binding = try DuelSerpentActionBinding(profile: profile())
        var value = try Runtime(binding: binding, level: level, raidDamageAmplifier: 1, rangedUsagesLeft: usages)
        value.beginRound(); return value
    }
    private func encoded(_ value: Runtime) throws -> Data {
        var writer = try DuelReplayStateWriter(kind: 3)
        try value.appendReplayState(to: &writer); return writer.data
    }

    func testActualSourceMarkersSoundsAndAnimationEndAreBoundToRecoveredClips() throws {
        let oracle = try JSONDecoder().decode(Oracle.self, from: sourceData("SERPENT_ACTION_ORACLE"))
        XCTAssertEqual(oracle.schema, "d13-action-source-oracle-v1")
        XCTAssertEqual(oracle.receiptSHA256, "d169d518d0133ee6180c81d11edd5b5c11816e91886b7aae2eed54806f775d37")
        XCTAssertEqual(oracle.profileSHA256, "05f5e49993120467a1c2cd5fdcbce3dba0dd3e8a5223b455f50adcfcd5441818")
        XCTAssertEqual(oracle.motions.count, 2)
        for row in oracle.motions {
            var value = try runtime()
            value.outgoingContact(channel: .weapon, sourceDamage: 0.4)
            let action = try XCTUnwrap(DuelSerpentActionBinding.Action(rawValue: row.action))
            let bound = value.binding.motion(action)
            XCTAssertEqual(bound.alias, row.alias); XCTAssertEqual(bound.role, row.role)
            XCTAssertEqual(bound.clipName, row.clipName); XCTAssertEqual(bound.clipSHA256, row.clipSHA256)
            XCTAssertEqual(bound.frames, row.frames); XCTAssertEqual(bound.playbackTicks, row.playbackTicks)
            XCTAssertEqual(bound.releaseMarker, row.releaseMarker); XCTAssertEqual(bound.releaseTick, row.releaseTick)
            XCTAssertEqual(bound.endEventTick, row.endEventTick)
            XCTAssertNotNil(value.acceptedAnimationStart(alias: row.alias, playbackID: 1))
            var events: [Runtime.Event] = []
            for tick in 1...row.endEventTick {
                events += try XCTUnwrap(value.step(liveTick: tick, targetInvincible: false)).events
            }
            XCTAssertEqual(events.filter { $0.effect == .intervalStart(row.releaseMarker) }.map(\.motionTick), [row.releaseTick])
            XCTAssertEqual(events.filter { $0.effect == .animationEnded }.map(\.motionTick), [row.endEventTick])
            for sound in row.sounds {
                XCTAssertTrue(events.contains { $0.motionTick == sound.tick && $0.effect == .sound(sound.name) })
            }
            XCTAssertNil(value.playback)
        }
    }

    func testOriginalTriggerOraclesAgreeForAllLevelsTiesInvincibilityAndRemainingLifetimes() throws {
        let oracle = try JSONDecoder().decode(Oracle.self, from: sourceData("SERPENT_ACTION_ORACLE"))
        XCTAssertEqual(oracle.explosionCases.count, 100)
        for row in oracle.explosionCases {
            var state = try XCTUnwrap(DuelSerpentState(level: row.level, raidDamageAmplifier: 1))
            state.beginRound()
            for contact in row.contacts {
                let channel = try XCTUnwrap(DuelSerpentState.Channel(rawValue: contact.channel))
                state.outgoingContact(channel: channel, sourceDamage: contact.damage)
                for _ in 0..<contact.delay { _ = state.advanceStatusTick() }
            }
            let result = try XCTUnwrap(state.resolvePoisonExplosionKey(targetInvincible: row.invincible))
            let context = "level \(row.level), \(row.name), invincible=\(row.invincible)"
            XCTAssertEqual(result.grantedBuff?.rawValue, row.selected, context)
            XCTAssertEqual(result.cooldownStarted, row.cooldown > 0, context)
            XCTAssertEqual(state.poisonAbilityCooldownRemaining, row.cooldown, context)
            XCTAssertEqual(state.lastPoisonChannel?.rawValue, row.last, context)
            for (i, channel) in DuelSerpentState.Channel.allCases.enumerated() {
                XCTAssertEqual(result.damageByChannel[i], row.damage[i], accuracy: 1e-12, context)
                XCTAssertEqual(state.poison(channel).amount, row.amounts[i], accuracy: 1e-12, context)
                XCTAssertEqual(state.poison(channel).remainingTicks, row.timers[i], context)
                XCTAssertEqual(state.poisonBuffRemaining(channel), row.selected == channel.rawValue ? 900 : 0, context)
            }
        }
    }

    func testBottleConsumesOnceOnAcceptedStageAndReleasesOnceAtTickEight() throws {
        var value = try runtime()
        XCTAssertEqual(value.acceptedAnimationStart(alias: "D13_Bottle_Throw", playbackID: 1)?.map(\.effect),
                       [.rangedUsageConsumed, .clearRangedInput])
        XCTAssertEqual(value.rangedUsagesLeft, 1)
        let started = value
        XCTAssertNil(value.acceptedAnimationStart(alias: "D13_Bottle_Throw", playbackID: 1))
        XCTAssertNil(value.acceptedAnimationStart(alias: "D13_Bottle_Throw", playbackID: 2))
        XCTAssertEqual(value, started)
        var modelEvents: [Runtime.Event] = []
        for tick in 1...110 {
            let result = try XCTUnwrap(value.step(liveTick: tick, targetInvincible: false))
            modelEvents += result.events.filter { $0.effect == .equippedRangedModelRequested(group: "D13_POSION_BOMB_MODEL") }
            let beforeDuplicate = value
            XCTAssertNil(value.step(liveTick: tick, targetInvincible: true))
            XCTAssertEqual(value, beforeDuplicate)
        }
        XCTAssertEqual(modelEvents.map(\.motionTick), [8]); XCTAssertEqual(modelEvents.map(\.playbackID), [1])
        XCTAssertFalse(value.state.bottleAwaitingRelease)
        XCTAssertNil(value.acceptedAnimationStart(alias: "D13_Bottle_Throw", playbackID: 2))
        XCTAssertEqual(value.rangedUsagesLeft, 1)
    }

    func testInterruptBeforeBottleReleaseDoesNotRefundOrLeakAndOldInterruptCannotCancelNewCast() throws {
        var value = try runtime()
        XCTAssertNotNil(value.acceptedAnimationStart(alias: "D13_Bottle_Throw", playbackID: 10))
        for tick in 1...7 { _ = value.step(liveTick: tick, targetInvincible: false) }
        XCTAssertTrue(value.interrupt(playbackID: 10))
        XCTAssertEqual(value.step(liveTick: 8, targetInvincible: false)?.events, [])
        XCTAssertEqual(value.rangedUsagesLeft, 1); XCTAssertTrue(value.state.bottleUsed)
        XCTAssertFalse(value.state.bottleAwaitingRelease)
        value.outgoingContact(channel: .weapon, sourceDamage: 0.2)
        XCTAssertNil(value.acceptedAnimationStart(alias: "D13_Poison_Ability", playbackID: 10))
        XCTAssertNotNil(value.acceptedAnimationStart(alias: "D13_Poison_Ability", playbackID: 11))
        let active = value
        XCTAssertFalse(value.interrupt(playbackID: 10)); XCTAssertEqual(value, active)
    }

    func testPoisonInterruptionBeforeReleaseLeavesStoresAndCooldownUnconsumed() throws {
        var value = try runtime()
        value.outgoingContact(channel: .unarmed, sourceDamage: 0.2)
        XCTAssertNotNil(value.acceptedAnimationStart(alias: "D13_Poison_Ability", playbackID: 1))
        for tick in 1...165 { _ = value.step(liveTick: tick, targetInvincible: false) }
        XCTAssertEqual(value.state.poisonAbilityCooldownRemaining, 0)
        XCTAssertTrue(value.interrupt(playbackID: 1))
        XCTAssertEqual(value.step(liveTick: 166, targetInvincible: false)?.events, [])
        XCTAssertGreaterThan(value.state.poison(.unarmed).amount, 0)
        XCTAssertEqual(value.state.poisonAbilityCooldownRemaining, 0)
        XCTAssertNotNil(value.acceptedAnimationStart(alias: "D13_Poison_Ability", playbackID: 2))
    }

    func testFrozenSkippedTicksAndRoundExitDoNotAdvanceStateOrEmitPendingRelease() throws {
        var value = try runtime()
        value.outgoingContact(channel: .ranged, sourceDamage: 0.1)
        XCTAssertNotNil(value.acceptedAnimationStart(alias: "D13_Bottle_Throw", playbackID: 1))
        let before = try encoded(value)
        for tick in [0, -1, 2, Int.max] {
            XCTAssertNil(value.step(liveTick: tick, targetInvincible: false))
            XCTAssertEqual(try encoded(value), before)
        }
        _ = value.step(liveTick: 1, targetInvincible: false)
        value.endRound()
        let closed = try encoded(value)
        XCTAssertNil(value.step(liveTick: 2, targetInvincible: false)); XCTAssertEqual(try encoded(value), closed)
        value.beginRound()
        for tick in 2...10 { XCTAssertEqual(value.step(liveTick: tick, targetInvincible: false)?.events, []) }
        XCTAssertTrue(value.state.bottleUsed) // This adapter does not invent a cross-round refund.
    }

    func testRejectsUnavailableBottleUnsupportedAliasAndUnboundBodyOrClock() throws {
        for (level, usages) in [(5,2),(6,0)] {
            var value = try runtime(level: level, usages: usages)
            let before = value
            XCTAssertNil(value.acceptedAnimationStart(alias: "D13_Bottle_Throw", playbackID: 1))
            XCTAssertEqual(value, before)
        }
        var value = try runtime()
        value.outgoingContact(channel: .weapon, sourceDamage: 0.1)
        XCTAssertNil(value.acceptedAnimationStart(alias: "D13_Deadly_Intoxication_Ability", playbackID: 1))
        let rawProfile = try sourceData("SERPENT_PHYSICAL_PROFILE")
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: rawProfile) as? [String:Any])
        for mutation in 0..<5 {
            var altered = original
            if mutation == 0 { altered["sha256"] = String(repeating: "0", count: 64) }
            if mutation == 1 || mutation == 2 {
                var roles = try XCTUnwrap(altered["roles"] as? [String:String])
                if mutation == 1 { roles["serpentPoison"] = roles["serpentIntoxication"] }
                else { roles["shadow"] = roles["serpentPoison"] }
                altered["roles"] = roles
            }
            if mutation >= 3 {
                var clips = try XCTUnwrap(altered["clips"] as? [[String:Any]])
                let index = try XCTUnwrap(clips.firstIndex { $0["name"] as? String == "d13_bottle_throw" })
                if mutation == 3 { clips[index]["sourceEndEventTick"] = 112 }
                else { clips[index]["sha256"] = String(repeating: "0", count: 64) }
                altered["clips"] = clips
            }
            let data = try JSONSerialization.data(withJSONObject: altered)
            let profile = try JSONDecoder().decode(DuelWeaponProfile.self, from: data)
            XCTAssertThrowsError(try DuelSerpentActionBinding(profile: profile))
        }
    }

    func testDeterministicReplayIncludesPoisonReleaseCooldownAndPlaybackIdentity() throws {
        var a = try runtime(), b = a
        for tick in 1...500 {
            if tick == 1 {
                a.outgoingContact(channel: .weapon, sourceDamage: 0.3)
                b.outgoingContact(channel: .weapon, sourceDamage: 0.3)
                _ = a.acceptedAnimationStart(alias: "D13_Poison_Ability", playbackID: 3)
                _ = b.acceptedAnimationStart(alias: "D13_Poison_Ability", playbackID: 3)
            }
            if tick == 240 {
                _ = a.acceptedAnimationStart(alias: "D13_Bottle_Throw", playbackID: 4)
                _ = b.acceptedAnimationStart(alias: "D13_Bottle_Throw", playbackID: 4)
            }
            XCTAssertEqual(a.step(liveTick: tick, targetInvincible: false), b.step(liveTick: tick, targetInvincible: false))
            XCTAssertEqual(try encoded(a), try encoded(b))
            if tick == 166 {
                XCTAssertEqual(a.state.poisonAbilityCooldownRemaining, 420)
                XCTAssertEqual(a.state.poisonBuffRemaining(.weapon), 900)
                XCTAssertEqual(a.state.poison(.weapon).amount, 0)
                XCTAssertGreaterThan(a.state.poison(.unarmed).amount, 0)
            }
        }
        var c = try runtime()
        c.outgoingContact(channel: .weapon, sourceDamage: 0.3)
        var d = c
        _ = c.acceptedAnimationStart(alias: "D13_Poison_Ability", playbackID: 1)
        _ = d.acceptedAnimationStart(alias: "D13_Poison_Ability", playbackID: 2)
        XCTAssertNotEqual(try encoded(c), try encoded(d))
    }

    func testCooldownBeginsAtApplyAndRejectsEarlyRecastWithoutConsumingPlaybackID() throws {
        var value = try runtime()
        value.outgoingContact(channel: .weapon, sourceDamage: 0.3)
        XCTAssertNotNil(value.acceptedAnimationStart(alias: "D13_Poison_Ability", playbackID: 1))
        for tick in 1...585 { _ = value.step(liveTick: tick, targetInvincible: false) }
        XCTAssertEqual(value.state.poisonAbilityCooldownRemaining, 1)
        let before = value
        XCTAssertNil(value.acceptedAnimationStart(alias: "D13_Poison_Ability", playbackID: 2))
        XCTAssertEqual(value, before)
        _ = value.step(liveTick: 586, targetInvincible: false)
        XCTAssertEqual(value.state.poisonAbilityCooldownRemaining, 0)
        XCTAssertGreaterThan(value.state.poisonBuffRemaining(.weapon), 0)
        XCTAssertNotNil(value.acceptedAnimationStart(alias: "D13_Poison_Ability", playbackID: 2))
    }
}
