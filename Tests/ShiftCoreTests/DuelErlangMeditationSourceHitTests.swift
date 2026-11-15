import Foundation
import XCTest
@testable import ShiftCore

final class DuelErlangMeditationSourceHitTests: XCTestCase {
    private func actualCatalog() throws -> DuelWeaponCatalog {
        let env = ProcessInfo.processInfo.environment
        guard let actorPath = env["ERLANG_RUNTIME_PROFILE"], let opponentsPath = env["ERLANG_OPPONENT_CATALOG"] else {
            throw XCTSkip("Exact private actor/model and opponent catalogs are not staged")
        }
        let decoder = JSONDecoder()
        let actor = try decoder.decode(DuelWeaponProfile.self, from: Data(contentsOf: URL(fileURLWithPath: actorPath)))
        let opponents = try decoder.decode(DuelWeaponCatalog.self, from: Data(contentsOf: URL(fileURLWithPath: opponentsPath)))
        return .init(schemaVersion: 1, previewFramesPerSecond: 30,
                     profiles: [actor, try XCTUnwrap(opponents.profile(for: .ember))])
    }
    private func readyFight(_ catalog: DuelWeaponCatalog) throws -> DuelWeaponFight {
        var fight = try XCTUnwrap(DuelWeaponFight(fighters: [
            .init(hero: .wuYong, x: 3500, facing: 1), .init(hero: .ember, x: 5000, facing: -1)],
            mode: .practice, difficulty: .learning, catalog: catalog, seed: 42))
        for _ in 0..<1000 where fight.sourceIntroActive { fight.step(.neutral, opponent: .neutral) }
        for _ in 0..<100 where !fight.canUseErlang(.meditate, index: 0) { fight.step(.neutral, opponent: .neutral) }
        XCTAssertTrue(fight.canUseErlang(.meditate, index: 0))
        return fight
    }
    func testNormalizedReplacementPreservesSubDisplayHealthAndRejectsNonfiniteAmounts() {
        var target = DuelErlangFightState(seed: 1)
        let fraction: Float = 0.000123456
        XCTAssertEqual(target.receiveNormalizedDamage(fraction, maximumHealth: 2000), 0)
        XCTAssertEqual(target.normalizedHealth, 1 - fraction)
        XCTAssertEqual(target.displayedHealth(maximum: 2000), 2000)
        let before = target
        for invalid: Float in [.nan, .infinity, -.infinity, -0.1] {
            XCTAssertEqual(target.receiveNormalizedDamage(invalid, maximumHealth: 2000), 0)
            XCTAssertEqual(target, before)
        }
    }
    func testExplosionUsesHalfStacksOnceAndNinetyTickDeduplication() {
        var state = DuelErlangFightState(seed: 2)
        for _ in 0..<60 { state.advance() }
        XCTAssertTrue(state.start(.meditate, duration: 34, direction: 1, x: 0))
        state.transition(role: "erlangMeditationLoop", duration: 136)
        for _ in 0..<147 { state.advance() }
        XCTAssertEqual(state.explosionStacksHalf, 50)
        XCTAssertEqual(state.meditationExplosionFraction, Float(25) * 0.001)
        XCTAssertTrue(state.requestMeditationRelease())
        XCTAssertEqual(state.cooldown(.meditate), 120)
        XCTAssertTrue(state.claimMeditationExplosion()); XCTAssertFalse(state.claimMeditationExplosion())
        state.meditationExplosionContact()
        XCTAssertEqual(state.cooldown(.meditate), 24)
        state.transition(role: "erlangMeditationEnd", duration: 34)
        XCTAssertEqual(state.cooldown(.meditate), 24, "End must not overwrite the actual zero-or-positive damage hit's recharge reduction")
        for _ in 0..<89 { state.advance() }
        XCTAssertFalse(state.claimMeditationExplosion())
        state.advance(); XCTAssertTrue(state.claimMeditationExplosion())
    }
    func testActualEarlyReleaseHasZeroDamageButOneSourceContactAndCooldownReduction() throws {
        let catalog = try actualCatalog()
        var fight = try readyFight(catalog)
        let attack = try XCTUnwrap(catalog.profiles[0].erlangRules?.attacks.first(where: \.isSourceMeditationExplosion))
        XCTAssertEqual(attack.baseDamageBps, 0)
        fight.step(.init(weaponCommand: .ranged, rangedHeld: true), opponent: .neutral)
        fight.step(.neutral, opponent: .neutral)
        let model = try XCTUnwrap(fight.erlangModels.first { $0.role == "erlangSummon_meditation" })
        XCTAssertEqual(fight.erlangState(0)?.explosionStacksHalf, 0)
        XCTAssertEqual(fight.landedHits[0], 1)
        XCTAssertEqual(fight.damageDealt[0], 0)
        XCTAssertEqual(fight.erlangState(0)?.cooldown(.meditate), 24)
        XCTAssertEqual(model.acceptedAttackIDs, [attack.id])
        let clip = try XCTUnwrap(catalog.profiles[0].clip(role: "erlangMeditationStart"))
        let pelvis = try XCTUnwrap(clip.tracks.pelvis)
        let at = clip.tracks.sample(pelvis, phase: clip.phase(at: 1))
        XCTAssertEqual(model.origin.x, Double(fight.fighters[0].x) / 1000 + at.x, accuracy: 1e-8)
        XCTAssertEqual(model.origin.y, Double(fight.fighters[0].y) / 1000 + at.y + clip.tracks.lift(phase: clip.phase(at: 1)), accuracy: 1e-8)
        XCTAssertEqual(model.origin.z, 0)
        for _ in 0..<40 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.landedHits[0], 1)
        XCTAssertEqual(fight.erlangModels.filter { $0.role == model.role }.map(\.id), [model.id])
        XCTAssertLessThanOrEqual(fight.erlangState(0)?.cooldown(.meditate) ?? 999, 24)
    }
    func testActualChargedExplosionReplacesPowerDamageAtTheRealContact() throws {
        let catalog = try actualCatalog()
        var fight = try readyFight(catalog)
        fight.step(.init(weaponCommand: .ranged, rangedHeld: true), opponent: .neutral)
        for _ in 0..<150 where (fight.erlangState(0)?.explosionStacksHalf ?? 0) < 20 {
            fight.step(.init(rangedHeld: true), opponent: .neutral)
        }
        XCTAssertEqual(fight.landedHits[0], 0)
        XCTAssertGreaterThanOrEqual(fight.erlangState(0)?.explosionStacksHalf ?? 0, 20)
        fight.step(.neutral, opponent: .neutral)
        let state = try XCTUnwrap(fight.erlangState(0))
        let expected = Int((Double(state.meditationExplosionFraction) * Double(fight.maximumHealth(1))).rounded(.down))
        XCTAssertGreaterThan(expected, 0)
        XCTAssertEqual(fight.landedHits[0], 1)
        XCTAssertEqual(fight.damageDealt[0], expected, "SetHit replaces BaseDamage0 after PreHit; neither MagicPower1000 nor meditation factors multiply it again")
        XCTAssertEqual(fight.erlangModels.filter { $0.role == "erlangSummon_meditation" }.count, 1)
        XCTAssertEqual(state.cooldown(.meditate), 24)
    }
}
