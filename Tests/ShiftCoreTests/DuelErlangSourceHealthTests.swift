import Foundation
import XCTest
@testable import ShiftCore

final class DuelErlangSourceHealthTests: XCTestCase {
    private func avatar(level: Int = 8, withStacks: Bool = false) -> DuelErlangFightState {
        var state = DuelErlangFightState(level: level, seed: 17)
        if withStacks {
            for _ in 0..<60 { state.advance() }
            XCTAssertTrue(state.start(.meditate, duration: 34, direction: 1, x: 3500))
            state.transition(role: "erlangMeditationLoop", duration: 144)
            for _ in 0..<3 { state.advance() }
            state.interrupt()
        }
        for _ in 0..<40 {
            state.acceptedPhysicalContact(kind: .weapon, imperialSpear: true,
                generated: false, targetHasDogDebuff: withStacks)
        }
        XCTAssertTrue(state.start(.ascend, duration: 160, direction: 1, x: 3500))
        _ = state.release(); state.completeCast()
        return state
    }
    func testNativeCriticalFloorPrecedesOneTickHalfHealthStatus() {
        var state = avatar()
        XCTAssertTrue(state.immortalActive)
        state.receiveDamage(5000, maximumHealth: 2000)
        XCTAssertEqual(state.normalizedHealth.bitPattern, 0x3727c5ac)
        XCTAssertEqual(state.displayedHealth(maximum: 2000), 1)
        XCTAssertEqual(state.criticalHealTicks, 1)
        XCTAssertEqual(state.immortalDisableTicks, 3)
        XCTAssertTrue(state.lethalProtectionSpent)
        state.advance()
        XCTAssertEqual(state.normalizedHealth, DuelErlangFightState.criticalHealthFloor + 0.5)
        XCTAssertEqual(state.displayedHealth(maximum: 2000), 1000)
        XCTAssertEqual(state.criticalHealTicks, 0)
        XCTAssertEqual(state.immortalDisableTicks, 2)
        XCTAssertEqual(state.form, .avatar)
    }
    func testContinuousLethalContactsDoNotRefreshHealOrThreeTickDeadline() {
        var state = avatar()
        state.receiveDamage(5000, maximumHealth: 2000)
        state.receiveDamage(5000, maximumHealth: 2000)
        XCTAssertEqual(state.criticalHealTicks, 1)
        XCTAssertEqual(state.immortalDisableTicks, 3)
        state.advance()
        state.receiveDamage(5000, maximumHealth: 2000)
        XCTAssertEqual(state.normalizedHealth, DuelErlangFightState.criticalHealthFloor)
        XCTAssertEqual(state.criticalHealTicks, 0)
        XCTAssertEqual(state.immortalDisableTicks, 2)
        state.advance()
        state.receiveDamage(5000, maximumHealth: 2000)
        XCTAssertEqual(state.immortalDisableTicks, 1)
        state.advance()
        XCTAssertEqual(state.form, .human)
        XCTAssertFalse(state.immortalActive)
        state.receiveDamage(1, maximumHealth: 2000)
        XCTAssertEqual(state.normalizedHealth, 0, "A displayed 1 HP must not replace the actual 0.02 HP source fraction")
        XCTAssertEqual(state.displayedHealth(maximum: 2000), 0)
    }
    func testHumanAndBelowLevelSixHaveNoUnboundLethalProtection() {
        var human = DuelErlangFightState(seed: 1), lowLevel = avatar(level: 5)
        human.receiveDamage(2000, maximumHealth: 2000)
        lowLevel.receiveDamage(2000, maximumHealth: 2000)
        XCTAssertEqual(human.normalizedHealth, 0)
        XCTAssertEqual(lowLevel.normalizedHealth, 0)
        XCTAssertEqual(human.criticalHealTicks, 0)
        XCTAssertEqual(lowLevel.immortalDisableTicks, 0)
    }
    func testThreeTickDisableClearsBuffsAndRetainsReturnUntilARealPoseCanStart() {
        var state = avatar(withStacks: true)
        XCTAssertGreaterThan(state.meditationStacks, 0)
        XCTAssertGreaterThan(state.holiness, 0)
        state.receiveDamage(5000, maximumHealth: 2000)
        for _ in 0..<3 { state.advance() }
        XCTAssertEqual(state.meditationStacks, 0); XCTAssertEqual(state.holiness, 0)
        XCTAssertEqual(state.form, .human); XCTAssertFalse(state.immortalActive)
        XCTAssertTrue(state.returnToHumanPending)
        XCTAssertFalse(state.canUse(.hound))
        XCTAssertEqual(state.light, 10_000)
        state.advance()
        XCTAssertEqual(state.light, 9400, "lock1454/t28 drains .06, not meditation's .005")
        state.advance(); state.advance()
        XCTAssertEqual(state.light, 9400)
        state.advance(); XCTAssertEqual(state.light, 8800)
        XCTAssertTrue(state.beginHumanReturn(duration: 0, direction: -1, x: 4000))
        XCTAssertEqual(state.cast?.role, "erlangTransformOut")
        XCTAssertEqual(state.cast?.tick, 0); XCTAssertEqual(state.cast?.duration, 0)
        state.advance(); XCTAssertEqual(state.cast?.tick, 1)
        state.completeCast()
        state.resetRound(seed: 18)
        XCTAssertEqual(state.normalizedHealth, 1); XCTAssertEqual(state.light, 0)
        XCTAssertFalse(state.immortalActive); XCTAssertFalse(state.lethalProtectionSpent)
        XCTAssertEqual(state.criticalHealTicks, 0); XCTAssertEqual(state.immortalDisableTicks, 0)
        XCTAssertFalse(state.returnToHumanPending); XCTAssertNil(state.cast)
    }

    private func collisionCatalog() throws -> DuelWeaponCatalog {
        let source = DuelWeaponTestFixtures.profile(hero: .liu, stroke: .straight, aerialKick: true)
        var roles = source.roles; roles.removeValue(forKey: "shadow")
        for role in ["erlangMeditationStart", "erlangMeditationLoop", "erlangMeditationEnd", "erlangTransform",
                     "erlangAvatarIdle", "erlangStep", "erlangAxe", "erlangEye", "erlangEarthshaker",
                     "erlangJudgment", "erlangHound"] { roles[role] = source.roles["idle"] }
        // This is a synthetic interpreter fixture with the one-frame contract
        // and source identity declarations. Its deliberately simple FK points
        // are not recovered source poses or private-resource acceptance proof.
        let first = try XCTUnwrap(source.clip(role: "idle")).tracks
        func one(_ points: [DuelWeaponPoint]) -> [DuelWeaponPoint] { Array(points.prefix(1)) }
        let landmark = [DuelWeaponPoint(y: 1)]
        let returnTracks = DuelWeaponTracks(samplesPerSourceFrame: 2,
            root: one(first.root), handL: one(first.handL), handR: one(first.handR),
            footL: one(first.footL), footR: one(first.footR),
            weaponBaseL: one(first.weaponBaseL), weaponTipL: one(first.weaponTipL),
            weaponBaseR: one(first.weaponBaseR), weaponTipR: one(first.weaponTipR),
            groundLift: [0], hurtCapsules: (0..<15).map {
                .init(id: "synthetic_return_hurt_\($0)", radiusMillimeters: 70,
                      defense: .body, base: landmark, tip: landmark)
            }, centerOfMass: landmark, pelvis: landmark,
            toeL: one(first.footL), toeR: one(first.footR), head: [DuelWeaponPoint(y: 1.7)])
        let returnClip = DuelWeaponClip(name: "synthetic_erlang_transform_out", frames: 1,
            sha256: DuelErlangTransformOutMotion.sourceSHA256,
            bundle: DuelErlangTransformOutMotion.sourceBundle, tracks: returnTracks,
            playbackTicks: 0, sourceEndEventTick: 0)
        roles[DuelErlangTransformOutMotion.role] = returnClip.name
        let rules = DuelErlangCombatRules(schemaVersion: 1, sourceVersion: DuelErlangFightState.sourceVersion,
            sourceSHA256: String(repeating: "e", count: 64), maximumHealth: 2000,
            normalizedWeaponPower: 1000, normalizedUnarmedPower: 1000,
            normalizedMagicPower: 1000, normalizedRangedPower: 1000, attacks: [], releases: [])
        let actor = DuelWeaponProfile(id: "wuyong_erlang", hero: .wuYong, faction: "Dynasty",
            resourceName: "Synthetic_Erlang_Health", bytes: 384, sha256: String(repeating: "d", count: 64),
            bodyID: "synthetic_erlang_body", weaponID: "synthetic_imperial_spear",
            activeWeaponSides: source.activeWeaponSides, roles: roles, clips: source.clips + [returnClip], erlangRules: rules)
        var actorJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(actor)) as? [String: Any])
        actorJSON["combatRules"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DuelCombatRuleProfile.legacy(for: actor)))
        let wu = try JSONDecoder().decode(DuelWeaponProfile.self, from: JSONSerialization.data(withJSONObject: actorJSON))
        let enemy = DuelWeaponTestFixtures.profile(hero: .ember, stroke: .straight, aerialKick: true)
        let original = DuelCombatRuleProfile.legacy(for: enemy)
        let attacks = original.attacks.map { attack in
            DuelCombatAttackRule(command: attack.command, clipName: attack.clipName, strikes: attack.strikes.map { s in
                .init(id: s.id, startTick: s.startTick, endTick: s.endTick, weaponSides: s.weaponSides,
                      damage: 5000, blockedDamage: 0, knocksDown: false, hitStopTicks: 2, blockedHitStopTicks: 0,
                      impact: s.impact, blockedImpact: s.blockedImpact)
            })
        }
        let lethal = DuelCombatRuleProfile(id: original.id, basis: original.basis,
            sourceVersion: original.sourceVersion, evidence: original.evidence, attacks: attacks)
        var enemyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(enemy)) as? [String: Any])
        enemyJSON["combatRules"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(lethal))
        let opponent = try JSONDecoder().decode(DuelWeaponProfile.self, from: JSONSerialization.data(withJSONObject: enemyJSON))
        return .init(schemaVersion: 1, previewFramesPerSecond: 30, profiles: [wu, opponent])
    }
    func testActualFightCollisionCannotEndTheRoundBeforePendingHealAndResetsNextRound() throws {
        let catalog = try collisionCatalog()
        var fight = try XCTUnwrap(DuelWeaponFight(fighters: [
            .init(hero: .wuYong, x: 3500, facing: 1), .init(hero: .ember, x: 4300, facing: -1)],
            mode: .versus, difficulty: .learning, catalog: catalog, seed: 42))
        // Drive real public input/timers rather than mutating private Fight state.
        for _ in 0..<2400 where fight.erlangState(0)?.light != 10_000 {
            let start = fight.canUseErlang(.meditate, index: 0)
            fight.step(.init(weaponCommand: start ? .ranged : nil, rangedHeld: true), opponent: .neutral)
        }
        for _ in 0..<100 where fight.erlangState(0)?.cast != nil { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.erlangState(0)?.light, 10_000)
        fight.step(.init(weaponCommand: .shadow), opponent: .neutral)
        for _ in 0..<100 where fight.erlangState(0)?.cast != nil { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.erlangState(0)?.form, .avatar)
        fight.step(.neutral, opponent: .init(weaponCommand: .weapon))
        for _ in 0..<30 where fight.erlangState(0)?.lethalProtectionSpent == false { fight.step(.neutral, opponent: .neutral) }
        XCTAssertTrue(fight.erlangState(0)?.lethalProtectionSpent == true)
        XCTAssertEqual(fight.phase, .fighting)
        XCTAssertEqual(fight.fighters[0].health, 1)
        let critical = try XCTUnwrap(fight.erlangState(0))
        while fight.hitStop > 0 {
            fight.step(.neutral, opponent: .neutral)
            XCTAssertEqual(fight.erlangState(0), critical, "Hit-stop must also freeze the source heal/disable clocks")
        }
        fight.step(.neutral, opponent: .neutral)
        XCTAssertEqual(fight.fighters[0].health, 1000)
        XCTAssertEqual(fight.phase, .fighting)
        fight.step(.neutral, opponent: .neutral); fight.step(.neutral, opponent: .neutral)
        XCTAssertEqual(fight.erlangState(0)?.form, .human)
        XCTAssertFalse(fight.erlangState(0)?.immortalActive ?? true)
        XCTAssertEqual(fight.erlangState(0)?.cast?.role, "erlangTransformOut")
        for _ in 0..<40 { fight.step(.neutral, opponent: .neutral) }
        fight.step(.neutral, opponent: .init(weaponCommand: .weapon))
        for _ in 0..<100 where fight.phase == .fighting { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.wins, [0, 1], "The next unprotected lethal contact must end the round")
        for _ in 0..<1200 where fight.roundNumber == 1 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.roundNumber, 2)
        XCTAssertEqual(fight.fighters[0].health, 2000)
        XCTAssertEqual(fight.erlangState(0)?.normalizedHealth, 1)
        XCTAssertFalse(fight.erlangState(0)?.lethalProtectionSpent ?? true)
        XCTAssertEqual(fight.erlangState(0)?.immortalDisableTicks, 0)
    }
}
