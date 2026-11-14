import Foundation
import XCTest
@testable import ShiftCore

/// Recovered D19 event boundaries with explicit synthetic contact geometry.
/// No original media is loaded; these are core behavior, not visual, tests.
final class DuelPanguReleasedModelTests: XCTestCase {
    private typealias State = DuelPanguState
    private typealias Rules = DuelPanguRules

    private func rules(level: Int = 1, power: Int = 1000) throws -> Rules {
        var rules = try Rules.d19HeavenlyKing(level: level, maximumHealth: 1000,
            weaponPower: power, unarmedPower: power, magicPower: power, rangedPower: power,
            spatialTemplate: DuelPanguTestFixture.rules(level: level))
        // Keep source timings while making the spear miss and stay in range.
        // This exposes lifecycle independently of a successful target contact.
        func miss(_ spec: inout Rules.AttackSpec) {
            spec.hitboxBottomMillimeters = 10_000; spec.hitboxTopMillimeters = 11_000
            spec.projectileSpeedMillimetersPerTick = 1
            spec.hitStopTicks = 0; spec.blockedHitStopTicks = 0
            spec.impact = .init(distanceMillimeters: 0, durationTicks: 1)
        }
        for index in rules.abilities.indices { miss(&rules.abilities[index].attack) }
        miss(&rules.hunt.empoweredSpear)
        return rules
    }

    private func alteredCatalog(_ source: DuelWeaponCatalog, knockdown: Bool = false,
                                quickReaction: Bool = false) throws -> DuelWeaponCatalog {
        let result = try DuelWeaponTestFixtures.changing(source) { profiles in
            for index in profiles.indices {
                let roles = profiles[index]["roles"] as! [String: String]
                var clips = profiles[index]["clips"] as! [[String: Any]]
                for clip in clips.indices {
                    var tracks = clips[clip]["tracks"] as! [String: Any]
                    let root = tracks["root"] as! [[Double]]
                    tracks["pelvis"] = Array(repeating: [0.0, 1.0, 0.0], count: root.count)
                    clips[clip]["tracks"] = tracks
                    if quickReaction && clips[clip]["name"] as? String == roles["hit"] {
                        clips[clip]["playbackTicks"] = 1
                    }
                }
                profiles[index]["clips"] = clips
                var combat = profiles[index]["combatRules"] as! [String: Any]
                var attacks = combat["attacks"] as! [[String: Any]]
                for attack in attacks.indices {
                    var strikes = attacks[attack]["strikes"] as! [[String: Any]]
                    for strike in strikes.indices {
                        strikes[strike]["hitStopTicks"] = 0
                        strikes[strike]["blockedHitStopTicks"] = 0
                        if knockdown && profiles[index]["id"] as? String != "liu_pangu" {
                            strikes[strike]["knocksDown"] = true
                        }
                    }
                    attacks[attack]["strikes"] = strikes
                }
                combat["attacks"] = attacks; profiles[index]["combatRules"] = combat
            }
        }
        try result.validate()
        return result
    }

    private func fight(empowered: Bool = false, knockdown: Bool = false, root: Bool = false,
                       panguFirst: Bool = true, facing: Int = 1,
                       mode: DuelGame.Mode = .practice, damage: Int = 30) throws -> DuelWeaponFight {
        let pangu = try rules(level: empowered ? 2 : 1)
        let source: DuelWeaponCatalog
        if root {
            var triad = DuelTriadFightFixture.rules(level: 2)
            triad.forest.curseChanceBps = 0
            triad.branches.holdTicks = 60; triad.branches.pulseDamage = 0
            triad.branches.entangledHoldReductionTicks = 0
            let index = try XCTUnwrap(triad.abilities.firstIndex { $0.ability == .branches })
            triad.abilities[index].startupTicks = 1
            triad.abilities[index].interruptible = false
            triad.abilities[index].attack?.hitStopTicks = 0
            triad.abilities[index].attack?.stunTicks = 0
            triad.abilities[index].attack?.impact = .init(distanceMillimeters: 0, durationTicks: 1)
            source = try DuelTriadFightFixture.catalog(rules: triad, pangu: pangu, damage: damage)
        } else {
            source = try DuelPanguFightFixture.catalog(rules: pangu, ordinaryDamage: damage,
                                                       ordinaryHitStop: 0)
        }
        let firstX = facing > 0 ? 3500 : 6500
        var result = try XCTUnwrap(DuelWeaponFight(fighters: [
            .init(hero: panguFirst ? .liu : .ember, x: firstX, facing: facing),
            .init(hero: panguFirst ? .ember : .liu, x: firstX + 800 * facing, facing: -facing)
        ], mode: mode, difficulty: .learning,
           catalog: alteredCatalog(source, knockdown: knockdown), seed: 41))
        if empowered {
            let owner = panguFirst ? 0 : 1
            let input = DuelGame.Input(move: -result.fighters[owner].facing, weaponCommand: .shadow)
            result.step(owner == 0 ? input : .neutral, opponent: owner == 1 ? input : .neutral)
            advance(&result, ticks: 80)
            XCTAssertNil(result.panguState(owner)?.activeCast)
            XCTAssertEqual(result.panguState(owner)?.rhythmRemainingTicks, 300)
        }
        return result
    }

    private func advance(_ fight: inout DuelWeaponFight, ticks: Int) {
        for _ in 0..<ticks { fight.step(.neutral, opponent: .neutral) }
    }
    @discardableResult private func beginSpear(_ fight: inout DuelWeaponFight, owner: Int) throws -> Int {
        let input = DuelGame.Input(weaponCommand: .ranged)
        fight.step(owner == 0 ? input : .neutral, opponent: owner == 1 ? input : .neutral)
        XCTAssertEqual(fight.panguState(owner)?.activeCast?.ability, .spear)
        XCTAssertEqual(fight.panguState(owner)?.activeCast?.tick, 0)
        return fight.panguPresentation.liveTick
    }
    private func spears(_ fight: DuelWeaponFight, owner: Int) -> [DuelPanguPresentation.Volume] {
        fight.panguPresentation.volumes.filter { $0.owner == owner && $0.ability == .spear }
    }
    private func bytes(_ fight: DuelWeaponFight) throws -> Data {
        var writer = try DuelReplayStateWriter(kind: 2)
        try fight.appendReplayState(to: &writer)
        return writer.data
    }

    func testOrdinaryHitAndKnockdownCancelCreateButRetainMissInEitherSeatAndFacing() throws {
        for empowered in [false, true] {
            let freeTick = empowered ? 50 : 60
            for hitTick in [7, 8, 45, 46, freeTick - 1, freeTick] {
                for knockdown in [false, true] {
                    for owner in [0, 1] {
                        // Fixed arena orientation makes seat0 face right
                        // and seat1 face left; swapping both would test only right.
                        let facing = 1
                        var value = try fight(empowered: empowered, knockdown: knockdown,
                                              panguFirst: owner == 0, facing: facing)
                        let origin = try beginSpear(&value, owner: owner)
                        advance(&value, ticks: hitTick - 2)
                        var uninterrupted = value
                        let attack = DuelGame.Input(weaponCommand: .weapon)
                        value.step(owner == 0 ? .neutral : attack, opponent: owner == 0 ? attack : .neutral)
                        value.step(.neutral, opponent: .neutral)
                        advance(&uninterrupted, ticks: 2)
                        let context = "empowered=\(empowered), hit=\(hitTick), down=\(knockdown), owner=\(owner)"
                        XCTAssertEqual(value.panguPresentation.liveTick, origin + hitTick, context)
                        XCTAssertEqual(value.landedHits[1 - owner], 1, context)
                        XCTAssertEqual(value.fighters[owner].health, 970, context)
                        XCTAssertNil(value.panguState(owner)?.activeCast, context)
                        XCTAssertEqual(spears(value, owner: owner).count, hitTick >= freeTick ? 1 : 0, context)
                        if knockdown { XCTAssertGreaterThan(value.fighters[owner].knockdown, 0, context) }
                        // The interruption cannot resurrect a queued attack, refund
                        // its charge, or consume a released model prematurely.
                        XCTAssertEqual(value.panguState(owner)?.rangedCharges,
                                       uninterrupted.panguState(owner)?.rangedCharges, context)
                        advance(&value, ticks: 65 - hitTick)
                        advance(&uninterrupted, ticks: 65 - hitTick)
                        XCTAssertEqual(spears(value, owner: owner).count, hitTick >= freeTick ? 1 : 0, context)
                        XCTAssertEqual(value.panguState(owner)?.rangedCharges,
                                       uninterrupted.panguState(owner)?.rangedCharges, context)
                        XCTAssertEqual(value.landedHits[owner], 0, context)
                    }
                }
            }
        }
    }

    func testRealSunRootUsesTheSameCreateAndFreeFlightBoundaries() throws {
        for empowered in [false, true] {
            let freeTick = empowered ? 50 : 60
            for tick in [8, 46, freeTick - 1, freeTick] {
                var value = try fight(empowered: empowered, root: true)
                let origin = try beginSpear(&value, owner: 0)
                advance(&value, ticks: tick - 2)
                value.step(.neutral, opponent: .init(weaponCommand: .shadow))
                value.step(.neutral, opponent: .neutral)
                let context = "empowered=\(empowered), root=\(tick)"
                XCTAssertEqual(value.panguPresentation.liveTick, origin + tick, context)
                XCTAssertTrue(value.triadPresentation.controls.contains { $0.target == 0 && $0.kind == .root }, context)
                XCTAssertNil(value.panguState(0)?.activeCast, context)
                XCTAssertEqual(spears(value, owner: 0).count, tick >= freeTick ? 1 : 0, context)
                advance(&value, ticks: 65 - tick)
                XCTAssertEqual(spears(value, owner: 0).count, tick >= freeTick ? 1 : 0, context)
                XCTAssertEqual(value.landedHits[0], 0, context)
            }
        }
    }

    func testNormalAndEmpoweredSpearKeepTheirDistinctFullFreeFlightLifetimes() throws {
        for empowered in [false, true] {
            var value = try fight(empowered: empowered)
            let origin = try beginSpear(&value, owner: 0)
            advance(&value, ticks: 46)
            XCTAssertEqual(spears(value, owner: 0).count, 1)
            let initial = try XCTUnwrap(spears(value, owner: 0).first)
            XCTAssertEqual(initial.expiresAtTick, origin + (empowered ? 49 : 109))
            advance(&value, ticks: (empowered ? 50 : 60) - 46)
            let flight = try XCTUnwrap(spears(value, owner: 0).first)
            XCTAssertEqual(flight.expiresAtTick, origin + (empowered ? 99 : 109))
            let expiry = flight.expiresAtTick
            advance(&value, ticks: expiry - value.panguPresentation.liveTick - 1)
            XCTAssertEqual(spears(value, owner: 0).count, 1)
            value.step(.neutral, opponent: .neutral)
            XCTAssertEqual(value.panguPresentation.liveTick, expiry)
            XCTAssertTrue(spears(value, owner: 0).isEmpty, "Expiry is consumed after its final collision opportunity")
            XCTAssertEqual(value.landedHits, [0, 0])
        }
    }

    func testGuardAfterOwnerRecoveryKeepsTheNormalSpearsRemainingFreeFlight() throws {
        var value = try fight()
        let origin = try beginSpear(&value, owner: 0)
        advance(&value, ticks: 100)
        XCTAssertNil(value.panguState(0)?.activeCast)
        let spear = try XCTUnwrap(spears(value, owner: 0).first)
        value.step(.init(guardHeld: true), opponent: .init(weaponCommand: .weapon))
        value.step(.init(guardHeld: true), opponent: .neutral)
        XCTAssertTrue(value.contacts.contains { $0.attacker == 1 && $0.kind == .block })
        XCTAssertEqual(value.fighters[0].health, 998)
        XCTAssertEqual(value.landedHits, [0, 0])
        XCTAssertEqual(spears(value, owner: 0).first?.attackID, spear.attackID)
        XCTAssertEqual(spears(value, owner: 0).first?.expiresAtTick, origin + 109)
    }

    func testRoundEndAndNextRoundClearUncreatedCreatingAndReleasedModelsWithIdenticalReplay() throws {
        for tick in [7, 8, 46, 60] {
            var value = try fight(mode: .versus, damage: 1000)
            _ = try beginSpear(&value, owner: 0)
            var replay = value
            for offset in 1...tick {
                let input: DuelGame.Input = offset == tick - 1 ? .init(weaponCommand: .weapon) : .neutral
                value.step(.neutral, opponent: input); replay.step(.neutral, opponent: input)
                XCTAssertEqual(try bytes(value), try bytes(replay))
            }
            XCTAssertEqual(value.wins, [0, 1]); XCTAssertEqual(value.fighters[0].health, 0)
            XCTAssertTrue(value.panguPresentation.volumes.isEmpty)
            XCTAssertNil(value.panguState(0)?.activeCast)
            for offset in 0..<220 {
                value.step(.neutral, opponent: .neutral); replay.step(.neutral, opponent: .neutral)
                // Check both sides of the round reset and regular live
                // checkpoints without serializing the catalog on every tick.
                if offset % 20 == 0 || (148...151).contains(offset) || offset == 219 {
                    XCTAssertEqual(try bytes(value), try bytes(replay))
                }
                XCTAssertTrue(value.panguPresentation.volumes.isEmpty)
            }
            XCTAssertEqual(value.roundNumber, 2)
            XCTAssertEqual(value.fighters[0].health, 1000)
            XCTAssertEqual(value.landedHits[0], 0, "A previous round's queue must never reappear")
        }
    }

    func testUpperWindDealsDamageWithoutInterruptingSunCastPendingReleaseOrIndependentVolume() throws {
        var pangu = try rules(level: 4, power: 100)
        let split = try XCTUnwrap(pangu.abilities.firstIndex { $0.ability == .splitter })
        pangu.abilities[split].attack.hitboxBottomMillimeters = 0
        pangu.abilities[split].attack.hitboxTopMillimeters = 1700
        pangu.windBlade.hitStopTicks = 0; pangu.windBlade.blockedHitStopTicks = 0
        pangu.windBlade.impact = .init(distanceMillimeters: 240, durationTicks: 8)
        var triad = DuelTriadFightFixture.rules(level: 2)
        triad.forest.curseChanceBps = 0
        let wave = try XCTUnwrap(triad.abilities.firstIndex { $0.ability == .mistOnslaught })
        triad.abilities[wave].startupTicks = 72
        for index in triad.abilities.indices {
            guard triad.abilities[index].attack != nil else { continue }
            triad.abilities[index].attack?.bottomMillimeters = 9000
            triad.abilities[index].attack?.topMillimeters = 10_000
            triad.abilities[index].attack?.speedMillimetersPerTick = 1
            triad.abilities[index].attack?.lifetimeTicks = 240
        }
        let catalog = try alteredCatalog(DuelTriadFightFixture.catalog(rules: triad, pangu: pangu), quickReaction: true)
        var value = try XCTUnwrap(DuelWeaponFight(fighters: [
            .init(hero: .liu, x: 3500, facing: 1), .init(hero: .ember, x: 4300, facing: -1)
        ], mode: .practice, difficulty: .learning, catalog: catalog, seed: 41))
        value.step(.init(vertical: 1, weaponCommand: .shadow),
                   opponent: .init(move: 1, weaponCommand: .shadow)) // Independent dynasty soul.
        advance(&value, ticks: 40)
        XCTAssertEqual(value.landedHits[0], 1, "The actual splitter must seed the upper-wind sequence")
        let soul = try XCTUnwrap(value.triadPresentation.volumes.first { $0.ability == .dynast })
        value.step(.neutral, opponent: .init(weaponCommand: .ranged))
        let cast = try XCTUnwrap(value.triadState(1)?.activeCast)
        XCTAssertEqual(cast.ability, .mistOnslaught)
        let x = value.fighters[1].x, health = value.fighters[1].health
        var replay = value
        for _ in 0..<70 {
            value.step(.neutral, opponent: .neutral); replay.step(.neutral, opponent: .neutral)
            XCTAssertEqual(try bytes(value), try bytes(replay))
            XCTAssertEqual(value.triadState(1)?.activeCast?.id, cast.id)
            XCTAssertEqual(value.fighters[1].x, x, "Hit_No_Reaction cannot schedule horizontal impulse")
            XCTAssertEqual(value.fighters[1].velocityY, 0)
            XCTAssertTrue(value.triadPresentation.volumes.contains { $0.attackID == soul.attackID })
        }
        XCTAssertEqual(value.landedHits[0], 6, "All five upper winds still make real contacts")
        XCTAssertEqual(health - value.fighters[1].health, 75,
                       "Each source 0.15 × 100 wind still deals 15; no-reaction is not damage immunity")
        XCTAssertEqual(value.damageDealt[0], triad.maximumHealth - value.fighters[1].health)
        // The unchanged owner-cast ID must still reach its scheduled release.
        var released = false
        for _ in 0..<3 {
            value.step(.neutral, opponent: .neutral)
            released = released || value.triadPresentation.volumes.contains { $0.ability == .mistOnslaught }
        }
        XCTAssertTrue(released, "The pending cast must survive Hit_No_Reaction and actually release")
    }
}
