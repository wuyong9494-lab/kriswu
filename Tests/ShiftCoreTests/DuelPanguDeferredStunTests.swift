import XCTest
@testable import ShiftCore

/// lock_1548's pending SET_D19_STUN gate, using declared synthetic bodies,
/// hit geometry and application HP/power scales. No production media is bound.
final class DuelPanguDeferredStunTests: XCTestCase {
    private func rules() throws -> DuelPanguRules {
        try DuelPanguRules.d19HeavenlyKing(level: 2, maximumHealth: 10_000,
            weaponPower: 100, unarmedPower: 100, magicPower: 100, rangedPower: 100,
            spatialTemplate: DuelPanguTestFixture.rules(level: 2))
    }

    private func fight(caster: Int = 0, repeatShard: Bool = false,
                       mode: DuelGame.Mode = .practice, ordinaryDamage: Int = 1) throws -> DuelWeaponFight {
        var value = try rules()
        if repeatShard {
            let index = try XCTUnwrap(value.abilities.firstIndex { $0.ability == .shard })
            value.abilities[index].cooldownTicks = 0 // Only to exercise duplicate pending hits.
        }
        var targetRules = DuelTriadFightFixture.rules()
        targetRules.maximumHealth = 10_000
        targetRules.forest.curseChanceBps = 0
        targetRules.souls.notchCost = 1
        for index in targetRules.abilities.indices {
            targetRules.abilities[index].attack?.rangeMillimeters = 1
            targetRules.abilities[index].attack?.radiusMillimeters = 1
            targetRules.abilities[index].attack?.damage = 0
            targetRules.abilities[index].attack?.blockedDamage = 0
            if targetRules.abilities[index].ability == .cryingDance {
                targetRules.abilities[index].startupTicks = 1
                targetRules.abilities[index].activeTicks = 300
                targetRules.abilities[index].recoveryTicks = 19
            }
        }
        let base = try DuelTriadFightFixture.catalog(rules: targetRules, pangu: value, damage: 1)
        let catalog = try DuelWeaponTestFixtures.changing(base) { profiles in
            let pangu = profiles.firstIndex { $0["id"] as? String == "liu_pangu" }!
            var combat = profiles[pangu]["combatRules"] as! [String: Any]
            var bindings = combat["attacks"] as! [[String: Any]]
            for binding in bindings.indices {
                var strikes = bindings[binding]["strikes"] as! [[String: Any]]
                for strike in strikes.indices { strikes[strike]["damage"] = ordinaryDamage }
                bindings[binding]["strikes"] = strikes
            }
            combat["attacks"] = bindings; profiles[pangu]["combatRules"] = combat
        }
        var result = try XCTUnwrap(DuelWeaponFight(fighters: [
            .init(hero: caster == 0 ? .liu : .ember, x: 3500, facing: 1),
            .init(hero: caster == 1 ? .liu : .ember, x: 4300, facing: -1)
        ], mode: mode, difficulty: .learning, catalog: catalog, seed: 41))
        // One real manual summon supplies the Notch needed for Crying Dance.
        let summon = DuelGame.Input(vertical: 1, weaponCommand: .shadow)
        result.step(caster == 1 ? summon : .neutral, opponent: caster == 0 ? summon : .neutral)
        XCTAssertEqual(result.triadState(1 - caster)?.notches, 1)
        let shard = DuelGame.Input(move: result.fighters[caster].facing, weaponCommand: .shadow)
        let protected = DuelGame.Input(vertical: -1, weaponCommand: .ranged)
        result.step(caster == 0 ? shard : protected, opponent: caster == 1 ? shard : protected)
        XCTAssertEqual(result.panguState(caster)?.activeCast?.ability, .shard)
        XCTAssertEqual(result.triadState(1 - caster)?.activeCast?.ability, .cryingDance)
        return result
    }

    private func stun(_ fight: DuelWeaponFight, target: Int) -> DuelPanguPresentation.Control? {
        fight.panguPresentation.controls.first { $0.target == target && $0.kind == .stun }
    }

    private func encodedSpace(_ space: DuelPanguSpatialState) throws -> [UInt8] {
        var writer = try DuelReplayStateWriter(kind: 2)
        try space.appendReplayState(to: &writer)
        return Array(writer.data)
    }

    private func waitForRock(_ fight: inout DuelWeaponFight, target: Int) -> Bool {
        DuelPanguFightFixture.until(&fight, limit: 120) { value in
            value.panguPresentationEvents.contains {
                if case .contact(let contact) = $0.kind {
                    return contact.target == target && contact.ability == .shard &&
                        contact.delivery == .projectile && contact.kind == .hit
                }
                return false
            }
        }
    }

    func testProtectedSourceContactRetainsControlButDuplicateOrBlockedContactDoesNot() throws {
        var state = try XCTUnwrap(DuelPanguState(rules: rules(), seed: 17))
        let effects = state.contact(blocked: false, generated: true, hitID: 1,
                                    sourceStrike: .shardThrown, reactable: false)
        let controls = effects.compactMap { effect -> DuelPanguState.Control? in
            if case .control(let value) = effect { return value }; return nil
        }
        XCTAssertEqual(controls.count, 1, "The source hit sets a pending flag even during Uninterrupt")
        XCTAssertEqual(controls.first?.kind, .stun)
        XCTAssertEqual(controls.first?.durationTicks, 90)
        XCTAssertTrue(state.contact(blocked: false, generated: true, hitID: 1,
                                    sourceStrike: .shardThrown, reactable: false).isEmpty)
        XCTAssertTrue(state.contact(blocked: true, generated: true, hitID: 2,
                                    sourceStrike: .shardThrown, reactable: false).isEmpty)

        var waiting = DuelPanguSpatialState()
        let empty = try encodedSpace(waiting)
        waiting.pendingSourceShardStuns[1] = try XCTUnwrap(controls.first).sourceID
        XCTAssertNotEqual(try encodedSpace(waiting), empty,
                          "A visually inactive pending flag must participate in replay identity")
        var otherTarget = DuelPanguSpatialState()
        otherTarget.pendingSourceShardStuns[0] = waiting.pendingSourceShardStuns[1]
        XCTAssertNotEqual(try encodedSpace(waiting), try encodedSpace(otherTarget))
        waiting = DuelPanguSpatialState()
        XCTAssertEqual(try encodedSpace(waiting), empty)
    }

    func testProtectedCastReleasesAFullStunInEitherFighterSlotAndFreezesDuringHitStop() throws {
        for caster in [0, 1] {
            let target = 1 - caster
            var value = try fight(caster: caster)
            XCTAssertTrue(waitForRock(&value, target: target))
            XCTAssertNil(stun(value, target: target))
            XCTAssertEqual(value.triadState(target)?.activeCast?.ability, .cryingDance)
            XCTAssertGreaterThan(value.hitStop, 0)
            let protectedState = value.triadState(target)
            let liveTick = value.panguPresentation.liveTick
            DuelPanguFightFixture.drainHitStop(&value)
            XCTAssertEqual(value.triadState(target), protectedState)
            XCTAssertEqual(value.panguPresentation.liveTick, liveTick)
            XCTAssertNil(stun(value, target: target))
            XCTAssertTrue(DuelPanguFightFixture.until(&value, limit: 350) {
                guard let cast = $0.triadState(target)?.activeCast else { return false }
                return cast.tick == cast.duration - 1
            })
            let attemptedAttack = DuelGame.Input(weaponCommand: .weaponBack)
            value.step(target == 0 ? attemptedAttack : .neutral,
                       opponent: target == 1 ? attemptedAttack : .neutral)
            XCTAssertNil(value.triadState(target)?.activeCast)
            let active = try XCTUnwrap(stun(value, target: target))
            XCTAssertEqual(active.remainingTicks, 90, "Waiting must not consume the source stun timer")
            XCTAssertEqual(value.fighters[target].stun, 90)
            XCTAssertNil(value.fighters[target].attack, "Deferred control takes priority over the first unlocked input")
            let damage = value.damageDealt[caster]
            for _ in 0..<89 { value.step(.neutral, opponent: .neutral) }
            XCTAssertEqual(stun(value, target: target)?.remainingTicks, 1)
            value.step(.neutral, opponent: .neutral)
            XCTAssertNil(stun(value, target: target))
            XCTAssertEqual(value.damageDealt[caster], damage, "Starting the delayed control must not replay damage")
        }
    }

    func testTwoProtectedRockHitsCoalesceIntoOnePendingStun() throws {
        var value = try fight(repeatShard: true)
        XCTAssertTrue(waitForRock(&value, target: 1))
        let damage = value.damageDealt[0]
        XCTAssertTrue(DuelPanguFightFixture.until(&value) { $0.panguState(0)?.activeCast == nil })
        value.step(.init(move: 1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertEqual(value.panguState(0)?.activeCast?.ability, .shard)
        XCTAssertTrue(waitForRock(&value, target: 1))
        XCTAssertGreaterThan(value.damageDealt[0], damage)
        XCTAssertEqual(value.triadState(1)?.activeCast?.ability, .cryingDance)
        XCTAssertNil(stun(value, target: 1))
        XCTAssertTrue(DuelPanguFightFixture.until(&value, limit: 350) { $0.triadState(1)?.activeCast == nil })
        XCTAssertEqual(stun(value, target: 1)?.remainingTicks, 90)
        var applications = value.panguPresentationEvents.filter {
            if case .controlApplied(let control) = $0.kind { return control.kind == .stun }; return false
        }.count
        for _ in 0..<100 {
            value.step(.neutral, opponent: .neutral)
            applications += value.panguPresentationEvents.filter {
                if case .controlApplied(let control) = $0.kind { return control.kind == .stun }; return false
            }.count
        }
        XCTAssertEqual(applications, 1, "SET_D19_STUN is one flag, not a queue of stacked stuns")
        XCTAssertNil(stun(value, target: 1))
    }

    func testLethalRoundEndDiscardsPendingStunBeforeNextRound() throws {
        var value = try fight(mode: .versus, ordinaryDamage: 100_000)
        XCTAssertTrue(waitForRock(&value, target: 1))
        XCTAssertTrue(DuelPanguFightFixture.until(&value) { $0.panguState(0)?.activeCast == nil })
        value.step(.init(weaponCommand: .weapon), opponent: .neutral)
        XCTAssertTrue(DuelPanguFightFixture.until(&value, limit: 30) { $0.phase != .fighting })
        XCTAssertNil(stun(value, target: 1))
        XCTAssertTrue(DuelPanguFightFixture.until(&value, limit: 200) { $0.phase == .fighting })
        for _ in 0..<330 {
            value.step(.neutral, opponent: .neutral)
            XCTAssertNil(stun(value, target: 0)); XCTAssertNil(stun(value, target: 1))
        }
    }
}
