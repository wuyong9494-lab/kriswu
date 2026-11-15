import XCTest
@testable import ShiftCore

final class DuelErlangFightIntegrationTests: XCTestCase {
    private func catalog(opponent: DuelGame.Hero = .ember) -> DuelWeaponCatalog {
        let source = DuelWeaponTestFixtures.profile(hero: .liu, stroke: .straight, aerialKick: true)
        var roles = source.roles
        roles.removeValue(forKey: "shadow")
        for role in ["erlangMeditationStart", "erlangMeditationLoop", "erlangMeditationEnd", "erlangTransform",
                     "erlangAvatarIdle", "erlangStep", "erlangAxe", "erlangEye", "erlangEarthshaker",
                     "erlangJudgment", "erlangHound"] { roles[role] = source.roles["idle"] }
        let runtime = DuelErlangCombatRules(schemaVersion: 1,
            sourceVersion: DuelErlangFightState.sourceVersion, sourceSHA256: String(repeating: "e", count: 64),
            maximumHealth: 2000, normalizedWeaponPower: 1000, normalizedUnarmedPower: 1000,
            normalizedMagicPower: 1000, normalizedRangedPower: 1000, attacks: [], releases: [])
        let initial = DuelWeaponProfile(id: "wuyong_erlang", hero: .wuYong, faction: "Dynasty",
            resourceName: "Synthetic_Erlang", bytes: 384, sha256: String(repeating: "d", count: 64),
            bodyID: "synthetic_erlang_body", weaponID: "synthetic_imperial_spear", activeWeaponSides: source.activeWeaponSides,
            roles: roles, clips: source.clips, erlangRules: runtime)
        let wu = DuelWeaponProfile(id: initial.id, hero: initial.hero, faction: initial.faction,
            resourceName: initial.resourceName, bytes: initial.bytes, sha256: initial.sha256,
            bodyID: initial.bodyID, weaponID: initial.weaponID, activeWeaponSides: initial.activeWeaponSides,
            roles: roles, clips: initial.clips, combatRules: .legacy(for: initial), erlangRules: runtime)
        return .init(schemaVersion: 1, previewFramesPerSecond: 30,
            profiles: [wu, DuelWeaponTestFixtures.profile(hero: opponent, stroke: .straight, aerialKick: true)])
    }
    private func fight(distance: Int = 800, mode: DuelGame.Mode = .practice) throws -> DuelWeaponFight {
        let fighters = [DuelGame.Fighter(hero: .wuYong, x: 3500, facing: 1),
                        DuelGame.Fighter(hero: .ember, x: 3500 + distance, facing: -1)]
        return try XCTUnwrap(DuelWeaponFight(fighters: fighters, mode: mode, difficulty: .learning,
                                            catalog: catalog(), seed: 42))
    }
    func testStableThirdIdentityUsesActualTwoPersonMatchAndCannotUseLegacyOrNetworkWeapon() throws {
        XCTAssertEqual(DuelGame.Hero.wuYong.rawValue, "wuyong_erlang")
        for opponent in [DuelGame.Hero.ember, .liu] {
            XCTAssertNoThrow(try catalog(opponent: opponent).validate())
            let game = DuelGame(hero: .wuYong, mode: .practice, opponentHero: opponent, weaponCatalog: catalog(opponent: opponent))
            XCTAssertEqual(game.weaponFight?.profiles.map(\.hero), [.wuYong, opponent])
            XCTAssertEqual(game.fighters[0].energy, 0)
        }
        for weapon in [DuelMultiplayerSelection.Weapon.katana, .ninjato, .hammers, .pangu] {
            XCTAssertFalse(DuelMultiplayerSelection.Choice(hero: .wuYong, weapon: weapon).isValid)
        }
        var missing = DuelGame(hero: .wuYong, mode: .practice)
        let snapshot = missing.fighters
        for _ in 0..<20 { missing.step(.init(taps: .light, weaponCommand: .weapon)) }
        XCTAssertEqual(missing.fighters, snapshot)
        XCTAssertEqual(missing.frame, 0)
    }
    func testOrdinarySourceCollisionDrivesLightButAWhiffOrIdleDoesNot() throws {
        var hit = try fight(), miss = try fight(distance: 4000)
        hit.step(.init(weaponCommand: .weapon), opponent: .neutral)
        miss.step(.init(weaponCommand: .weapon), opponent: .neutral)
        for _ in 0..<24 { hit.step(.neutral, opponent: .neutral); miss.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(hit.landedHits[0], 1)
        XCTAssertEqual(hit.erlangState(0)?.light, 250)
        XCTAssertEqual(hit.fighters[0].energy, 2)
        XCTAssertEqual(miss.landedHits[0], 0)
        XCTAssertEqual(miss.erlangState(0)?.light, 0)
        for _ in 0..<120 { miss.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(miss.erlangState(0)?.light, 0, "Wu must never inherit legacy hammer regeneration")
    }
    func testContactKindSeparatesLightFromImperialSwordProcAndMeditationCooldownReduction() {
        var state = DuelErlangFightState(seed: 7)
        let before = state.cooldown(.meditate)
        state.acceptedPhysicalContact(kind: .unarmed, imperialSpear: false, generated: false, targetHasDogDebuff: false)
        XCTAssertEqual(state.light, 250)
        XCTAssertEqual(state.swords, 0)
        XCTAssertEqual(state.cooldown(.meditate), before, "A normal contact is not a meditation explosion")
        state.acceptedPhysicalContact(kind: .shadow, imperialSpear: false, generated: true, targetHasDogDebuff: false)
        XCTAssertEqual(state.light, 250)
        state.meditationExplosionContact()
        XCTAssertEqual(state.cooldown(.meditate), before / 5)
    }
    func testFixedStepCooldownAndStateFreezeDuringRealHitStop() throws {
        var fight = try fight()
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        for _ in 0..<24 where fight.hitStop == 0 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertGreaterThan(fight.hitStop, 0)
        let before = fight.erlangState(0)
        fight.step(.neutral, opponent: .neutral)
        XCTAssertEqual(fight.erlangState(0), before)
        fight.step(.neutral, opponent: .neutral)
        XCTAssertEqual(fight.erlangState(0)?.liveTick, (before?.liveTick ?? -1) + 1)
    }
    func testMeditationUsesSourcePulseAndReleaseWithoutResettingMaximumOnLoop() {
        var state = DuelErlangFightState(seed: 9)
        for _ in 0..<60 { state.advance() }
        XCTAssertTrue(state.start(.meditate, duration: 34, direction: 1, x: 3500))
        XCTAssertEqual(state.light, 0)
        state.transition(role: "erlangMeditationLoop", duration: 144)
        XCTAssertEqual(state.light, 50)
        for _ in 0..<3 { state.advance() }
        XCTAssertEqual(state.light, 100)
        XCTAssertEqual(state.meditationStacks, 2)
        let elapsed = state.meditationUnits
        state.transition(role: "erlangMeditationLoop", duration: 144)
        XCTAssertEqual(state.meditationUnits, elapsed)
        XCTAssertEqual(state.holiness, 0, "Meditation cannot fabricate dog-hit holiness")
        state.requestMeditationRelease()
        state.transition(role: "erlangMeditationEnd", duration: 42)
        XCTAssertFalse(state.isMeditating)
        XCTAssertGreaterThan(state.cooldown(.meditate), 0)
    }
    func testNormalFightMeditationOwnsSourcePoseAndPreventsOrdinaryAttackQueue() throws {
        var fight = try fight(distance: 4000)
        for _ in 0..<60 { fight.step(.neutral, opponent: .neutral) }
        fight.step(.init(weaponCommand: .ranged, rangedHeld: true), opponent: .neutral)
        XCTAssertEqual(fight.erlangState(0)?.cast?.ability, .meditate)
        for _ in 0..<18 { fight.step(.init(rangedHeld: true), opponent: .neutral) }
        XCTAssertGreaterThan(fight.erlangState(0)?.light ?? 0, 0)
        fight.step(.init(weaponCommand: .weapon, rangedHeld: true), opponent: .neutral)
        XCTAssertEqual(fight.erlangState(0)?.cast?.ability, .meditate)
        for _ in 0..<40 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertNil(fight.erlangState(0)?.cast)
        XCTAssertEqual(fight.landedHits[0], 0)
    }
    func testAvatarTransitionAndRoundResetDoNotBankPreviewState() {
        var state = DuelErlangFightState(seed: 12)
        for _ in 0..<40 { state.acceptedPhysicalContact(kind: .weapon, imperialSpear: true, generated: false, targetHasDogDebuff: true) }
        XCTAssertEqual(state.light, 10_000)
        XCTAssertTrue(state.start(.ascend, duration: 168, direction: 1, x: 3500))
        XCTAssertEqual(state.form, .human, "Accepting a button is not the source transform marker")
        _ = state.release()
        XCTAssertEqual(state.form, .avatar)
        XCTAssertFalse(state.mayGuard)
        state.completeCast()
        XCTAssertEqual(state.swords, 6)
        state.resetRound(seed: 12)
        XCTAssertEqual(state.form, .human)
        XCTAssertEqual(state.light, 0)
        XCTAssertEqual(state.swords, 0)
        XCTAssertEqual(state.holiness, 0)
        XCTAssertNil(state.cast)
    }
    func testMissingCompanionCollisionCannotEnableAnInvisibleHound() throws {
        let fight = try fight()
        XCTAssertFalse(fight.canUseErlang(.hound, index: 0))
        XCTAssertFalse(fight.canUseErlang(.axe, index: 0))
    }
    func testPracticeOpponentKOAlsoClearsSurvivingWuState() throws {
        var enemy = DuelGame.Fighter(hero: .ember, x: 4300, facing: -1)
        enemy.health = 1
        var fight = try XCTUnwrap(DuelWeaponFight(fighters: [.init(hero: .wuYong, x: 3500, facing: 1), enemy],
            mode: .practice, difficulty: .learning, catalog: catalog(), seed: 42))
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        for _ in 0..<24 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.landedHits[0], 1)
        XCTAssertEqual(fight.fighters[1].health, fight.maximumHealth(1))
        XCTAssertEqual(fight.erlangState(0)?.light, 0)
        XCTAssertNil(fight.erlangState(0)?.cast)
        XCTAssertTrue(fight.erlangModels.isEmpty)
    }
}
