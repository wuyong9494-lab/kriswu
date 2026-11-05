import XCTest
@testable import ShiftCore

final class ArenaSourceCombatTests: XCTestCase {
    // The values below are small factual numeric fixtures from the supplied
    // v69 source CSV, not a copy of native game code or proprietary media.
    private func colt(role: ArenaSourceSkillRole = .weapon) -> ArenaSourceSkill {
        let ultimate = role == .ultimate
        let projectile = ArenaSourceProjectile(id: ultimate ? "GunslingerUltiProjectile" : "GunslingerProjectile",
            speed: (ultimate ? 4891 : 4000) / 300.0, radius: (ultimate ? 101 : 50) / 300.0,
            piercesCharacters: ultimate, wallBreak: ultimate, pushback: 0, bounces: 0,
            bounceRangeAdd: 0, areaEffects: [], unsupportedReasons: [], rawSource: [:])
        return ArenaSourceSkill(id: ultimate ? "GunslingerUlti" : "GunslingerWeapon", role: role,
            behavior: "Attack", range: ultimate ? 11 : 9, damage: ultimate ? 320 : 360,
            chargeDamage: ultimate ? 320 : 360, ammoCapacity: ultimate ? 0 : 3,
            reload: ultimate ? 0 : 1.3, cooldown: 0.05, castingTime: 0,
            activeTime: ultimate ? 1.25 : 0.65, attackInterval: 0.1,
            executeFirstAttackImmediately: true, canMove: true, projectileCount: 1,
            spread: 0, projectiles: [projectile], areaEffects: [], charge: nil,
            unsupportedReasons: [], rawSource: [:])
    }

    private func hero() -> ArenaSourceHero {
        ArenaSourceHero(id: "Gunslinger", name: "colt", health: 3100, speed: 2.5,
            collisionRadius: 0.4, weapon: colt(), ultimate: colt(role: .ultimate),
            weaponChargePerDamage: 93 / 400000.0, ultimateChargePerDamage: 87 / 400000.0,
            initialSuperCharge: 0, unsupportedReasons: [], compatibilityPolicy: "source-csv-69-base-20hz-v1",
            rawSource: [:])
    }

    private func launches(_ emitted: [ArenaSourceEmission]) -> [ArenaSourceLaunch] {
        emitted.compactMap { if case .projectile(let launch) = $0 { return launch }; return nil }
    }

    private func sourceShield(casting: Double = 0) -> ArenaSourceSkill {
        var skill = colt(role: .ultimate)
        skill.id = "HostShield"
        skill.behavior = "Shield"
        skill.range = 0
        skill.damage = 0
        skill.chargeDamage = 0
        skill.castingTime = casting
        skill.activeTime = 4
        skill.projectiles = []
        skill.projectileCount = 0
        skill.shieldDamageMultiplier = 0.4
        return skill
    }

    private func healingPoco() -> ArenaSourceHero {
        var source = hero()
        source.id = "DeadMariachi"
        source.name = "Poco"
        source.health = 4000
        source.rawSource = ["Traits": "DeadMariachiProjectileHealPassive"]
        let passive = "hero.DeadMariachi.Traits=DeadMariachiProjectileHealPassive: requires a dedicated hero rule"
        let heal = "projectile.DeadMariachiUltiProjectile.HealOwnPercent=100: not yet interpreted"
        source.unsupportedReasons = [passive, heal]
        var weapon = colt()
        weapon.id = "DeadMariachiWeapon"
        weapon.damage = 760
        weapon.range = 7
        weapon.activeTime = 0.15
        weapon.projectileCount = 4
        weapon.spread = 1.1344640137963142
        weapon.projectiles[0].id = "DeadMariachiProjectile"
        weapon.projectiles[0].speed = 2500 / 300.0
        weapon.projectiles[0].radius = 0.5
        weapon.projectiles[0].piercesCharacters = true
        weapon.projectiles[0].damageOncePerVolley = true
        source.weapon = weapon
        var ultimate = colt(role: .ultimate)
        ultimate.id = "DeadMariachiUlti"
        ultimate.damage = 2100
        ultimate.range = 28 / 3.0
        ultimate.activeTime = 0.15
        ultimate.projectileCount = 3
        ultimate.spread = 1.1344640137963142
        ultimate.projectiles[0].id = "DeadMariachiUltiProjectile"
        ultimate.projectiles[0].speed = 5000 / 300.0
        ultimate.projectiles[0].radius = 400 / 300.0
        ultimate.projectiles[0].piercesCharacters = true
        ultimate.projectiles[0].passesEnvironment = true
        ultimate.projectiles[0].damageOncePerVolley = true
        ultimate.projectiles[0].rawSource["HealOwnPercent"] = "100"
        ultimate.projectiles[0].unsupportedReasons = [heal]
        ultimate.unsupportedReasons = [heal]
        source.ultimate = ultimate
        return source
    }

    private func longDashMortis() -> ArenaSourceHero {
        var source = hero()
        source.id = "Undertaker"
        source.name = "Mortis"
        source.health = 4000
        source.rawSource = ["UniqueProperty": "HAS_LONGER_DASH", "UniquePropertyValue1": "90",
                            "UniquePropertyValue2": "6"]
        source.unsupportedReasons = [
            "hero.Undertaker.UniquePropertyValue1=90: requires a dedicated hero rule",
            "hero.Undertaker.UniquePropertyValue2=6: requires a dedicated hero rule",
            "hero.Undertaker.UniqueProperty=HAS_LONGER_DASH: native identity behavior not implemented"
        ]
        var weapon = colt()
        weapon.id = "UndertakerWeapon"
        weapon.behavior = "Charge"
        weapon.range = 8.0 / 3
        weapon.damage = 1000
        weapon.chargeDamage = 1000
        weapon.reload = 2.4
        weapon.cooldown = 0
        weapon.activeTime = 0
        weapon.attackInterval = 0
        weapon.canMove = false
        weapon.projectileCount = 0
        weapon.projectiles = []
        weapon.charge = ArenaSourceChargeDefinition(sourceType: 4, speed: 9, wallBreak: false,
            pushback: 0, alwaysAtMaxRange: true, endAreas: [])
        source.weapon = weapon
        var ultimate = colt(role: .ultimate)
        ultimate.id = "UndertakerUlti"
        ultimate.damage = 900
        ultimate.projectiles[0].id = "UndertakerUltiProjectile"
        ultimate.projectiles[0].wallBreak = false
        ultimate.projectiles[0].lifeStealFraction = 1
        ultimate.projectiles[0].passesEnvironment = true
        source.ultimate = ultimate
        return source
    }

    private func trackedRocketGirl() -> ArenaSourceHero {
        var source = hero()
        source.id = "RocketGirl"
        source.name = "Brock"
        source.health = 3000
        var weapon = colt()
        weapon.id = "RocketGirlWeapon"
        source.weapon = weapon
        let pattern = "skill.RocketGirlUlti.AttackPattern=9: not yet interpreted"
        let spread = "skill.RocketGirlUlti.Spread: single-projectile dispersion needs a source pattern adapter"
        let tracking = "projectile.RocketGirlUltiProjectile.BooleanAttributes=IndirectProjectileTracksSource: not yet interpreted"
        source.unsupportedReasons = [pattern, spread, tracking]
        var ultimate = colt(role: .ultimate)
        ultimate.id = "RocketGirlUlti"
        ultimate.damage = 1040
        ultimate.range = 25.0 / 3
        ultimate.spread = 1.3962634015954636
        ultimate.activeTime = 1.85
        ultimate.attackInterval = 0.2
        ultimate.projectileCount = 1
        ultimate.rawSource = ["AttackPattern": "9", "NumBulletsInOneAttack": "1"]
        ultimate.unsupportedReasons = [pattern, spread, tracking]
        ultimate.projectiles[0].id = "RocketGirlUltiProjectile"
        ultimate.projectiles[0].indirect = true
        ultimate.projectiles[0].constantFlightTime = 0.9
        ultimate.projectiles[0].rawSource["BooleanAttributes"] = "IndirectProjectileTracksSource"
        ultimate.projectiles[0].unsupportedReasons = [tracking]
        source.ultimate = ultimate
        return source
    }

    private func smokeSandy() -> ArenaSourceHero {
        var source = hero()
        source.id = "Sandstorm"
        source.name = "Sandy"
        source.health = 3800
        let pattern = "skill.SandstormWeapon.AttackPattern=4: not yet interpreted"
        let smoke = "area.Sandy_def_ulti.Type=SmokeScreen: requires a dedicated area lifecycle"
        source.unsupportedReasons = [pattern, smoke]
        var weapon = colt()
        weapon.id = "SandstormWeapon"
        weapon.damage = 900
        weapon.chargeDamage = 900
        weapon.projectileCount = 3
        weapon.spread = 0.6981317007977318
        weapon.rawSource["AttackPattern"] = "4"
        weapon.rawSource["NumBulletsInOneAttack"] = "3"
        weapon.rawSource["Spread"] = "80"
        weapon.projectiles[0].id = "SandstormProjectile"
        weapon.projectiles[0].piercesCharacters = true
        weapon.projectiles[0].damageOncePerVolley = true
        weapon.unsupportedReasons = [pattern]
        source.weapon = weapon

        let area = ArenaSourceAreaEffect(id: "Sandy_def_ulti", kind: "SmokeScreen", radius: 2000 / 300.0,
            damage: nil, duration: 9, wallBreak: false, pushback: 0,
            unsupportedReasons: [smoke], rawSource: ["Type": "SmokeScreen"])
        var ultimate = colt(role: .ultimate)
        ultimate.id = "SandstormUlti"
        ultimate.damage = 0
        ultimate.chargeDamage = 0
        ultimate.range = 22 / 3.0
        ultimate.activeTime = 0.15
        ultimate.projectiles[0].id = "SandstormUltiProjectile"
        ultimate.projectiles[0].indirect = true
        ultimate.projectiles[0].directDamage = false
        ultimate.projectiles[0].wallBreak = false
        ultimate.projectiles[0].areaEffects = [area]
        ultimate.projectiles[0].unsupportedReasons = [smoke]
        ultimate.unsupportedReasons = [smoke]
        source.ultimate = ultimate
        return source
    }

    func testSandySmokeAndThreePelletFanRequireExactReviewedSource() throws {
        let original = smokeSandy()
        XCTAssertFalse(original.canPlay)
        let adapted = ArenaSourceCompatibility.adapt(original)
        XCTAssertTrue(adapted.canPlay, adapted.unsupportedReasons.joined(separator: ", "))
        XCTAssertTrue(adapted.unavailableCapabilities.isEmpty)
        XCTAssertEqual(adapted.weapon?.projectileCount, 3)
        XCTAssertEqual(adapted.weapon?.projectiles.first?.damageOncePerVolley, true)
        XCTAssertEqual(adapted.ultimate?.projectiles.first?.areaEffects.first?.kind, "SmokeScreen")
        XCTAssertTrue(adapted.compatibilityPolicy.contains("host-sandy-three-pellet-fan"))
        XCTAssertTrue(adapted.compatibilityPolicy.contains("host-sandy-ally-smoke-nine-seconds"))
        XCTAssertEqual(try JSONDecoder().decode(ArenaSourceHero.self, from: JSONEncoder().encode(adapted)), adapted)
        XCTAssertEqual(ArenaSourceCompatibility.adapt(adapted), adapted)
        XCTAssertEqual(original, smokeSandy(), "The private source profile is not mutated")

        var unknown = original
        unknown.weapon?.rawSource["AttackPattern"] = "7"
        XCTAssertFalse(ArenaSourceCompatibility.adapt(unknown).canPlay)
        unknown = original
        unknown.ultimate?.projectiles[0].areaEffects[0].duration = 10
        XCTAssertFalse(ArenaSourceCompatibility.adapt(unknown).canPlay)
        unknown = original
        unknown.unsupportedReasons.append("unreviewed smoke attribute")
        XCTAssertFalse(ArenaSourceCompatibility.adapt(unknown).canPlay)
    }

    func testSandySmokeConcealsAlliesWhileInsideAndExpiresAfterNineSeconds() throws {
        let source = ArenaSourceCompatibility.adapt(smokeSandy())
        let rows = (0..<13).map { y in String((0..<23).map { x -> Character in
            if x == 0 || x == 22 || y == 0 || y == 12 { return "#" }
            if x == 4 && y == 6 { return "a" }
            if x == 19 && y == 6 { return "b" }
            return "."
        }) }
        let entrants = [
            ArenaGame.Entrant(name: "Sandy", brawler: .ranger, isBot: false, team: 0, sourceHero: source),
            ArenaGame.Entrant(name: "Friendly project hero", brawler: .ranger, isBot: false, team: 0),
            ArenaGame.Entrant(name: "Opponent", brawler: .knight, isBot: false, team: 1)
        ]
        var game = try ArenaGame(sourceMode: .teamFight, entrants: entrants, seed: 807, map: ArenaMap(rows: rows))
        game.fighters[0].pos = V2(4.5, 6.5)
        game.fighters[1].pos = V2(6, 6.5)
        game.fighters[2].pos = V2(19.5, 6.5)
        let area = try XCTUnwrap(source.ultimate?.projectiles.first?.areaEffects.first)
        game.applySourceArea(ArenaSourceAreaSpawn(skillID: "SandstormUlti", role: .ultimate,
            area: area, position: V2(5.5, 6.5), damage: 0, chargeDamage: 0), owner: 0)
        XCTAssertEqual(game.sourceAreas.count, 1)
        XCTAssertGreaterThan(game.fighters[1].invisible, 0)
        XCTAssertEqual(game.fighters[2].invisible, 0)
        XCTAssertFalse(game.isVisible(game.fighters[1], to: 1))
        game.fighters[1].lastAttack = game.time
        XCTAssertTrue(game.isVisible(game.fighters[1], to: 1), "Attacking still reveals a concealed fighter")
        game.fighters[1].lastAttack = -10

        game.fighters[1].pos = V2(18.5, 6.5)
        runWorld(&game, frames: 20)
        XCTAssertEqual(game.fighters[1].invisible, 0, accuracy: 1e-9)
        game.fighters[1].pos = V2(6, 6.5)
        runWorld(&game, frames: 20)
        XCTAssertGreaterThan(game.fighters[1].invisible, 0)
        runWorld(&game, frames: 550)
        XCTAssertTrue(game.sourceAreas.isEmpty)
        XCTAssertEqual(game.fighters[1].invisible, 0, accuracy: 1e-9)
    }

    func testSandyUltimateProjectileCreatesSmokeForProjectHeroTeammates() throws {
        let source = ArenaSourceCompatibility.adapt(smokeSandy())
        let rows = (0..<13).map { y in String((0..<23).map { x -> Character in
            if x == 0 || x == 22 || y == 0 || y == 12 { return "#" }
            if x == 3 && y == 6 { return "a" }
            if x == 19 && y == 6 { return "b" }
            return "."
        }) }
        let entrants = [
            ArenaGame.Entrant(name: "Sandy", brawler: .ranger, isBot: false, team: 0, sourceHero: source),
            ArenaGame.Entrant(name: "Classic ally", brawler: .ranger, isBot: false, team: 0),
            ArenaGame.Entrant(name: "Enemy", brawler: .knight, isBot: false, team: 1)
        ]
        var game = try ArenaGame(sourceMode: .teamFight, entrants: entrants, seed: 808, map: ArenaMap(rows: rows))
        game.fighters[0].pos = V2(3.5, 6.5)
        game.fighters[1].pos = V2(8.5, 6.5)
        game.fighters[2].pos = V2(19.5, 6.5)
        game.fighters[0].superCharge = 1
        game.activateSourceSkill(0, role: .ultimate, aim: V2(5, 0))
        XCTAssertFalse(game.projectiles.isEmpty)
        runWorld(&game, frames: 60)
        XCTAssertTrue(game.sourceAreas.contains { $0.kind == "SmokeScreen" })
        XCTAssertGreaterThan(game.fighters[1].invisible, 0)
        XCTAssertEqual(game.fighters[2].invisible, 0)
    }

    func testBrockTrackedImpactOnlyUnblocksReviewedSourceAttributes() throws {
        let original = trackedRocketGirl()
        XCTAssertFalse(original.canPlay)
        let adapted = ArenaSourceCompatibility.adapt(original)
        XCTAssertTrue(adapted.canPlay, adapted.unsupportedReasons.joined(separator: ", "))
        XCTAssertTrue(adapted.unavailableCapabilities.isEmpty)
        XCTAssertEqual(adapted.ultimate?.dispersion, "seeded_cone")
        XCTAssertEqual(adapted.ultimate?.projectiles.first?.tracksCasterDisplacement, true)
        XCTAssertTrue(adapted.compatibilityPolicy.contains("host-brock-caster-tracked-impact"))
        XCTAssertTrue(adapted.compatibilityPolicy.contains("host-pattern9-seeded-cone"))
        XCTAssertEqual(try JSONDecoder().decode(ArenaSourceHero.self, from: JSONEncoder().encode(adapted)), adapted)
        XCTAssertEqual(ArenaSourceCompatibility.adapt(adapted), adapted)
        XCTAssertEqual(original, trackedRocketGirl(), "Original source records remain unchanged")

        var unknown = original
        unknown.ultimate?.projectiles[0].rawSource["BooleanAttributes"] = "other"
        XCTAssertFalse(ArenaSourceCompatibility.adapt(unknown).canPlay)
        unknown = original
        unknown.ultimate?.projectiles[0].constantFlightTime = nil
        XCTAssertFalse(ArenaSourceCompatibility.adapt(unknown).canPlay)
        unknown = original
        unknown.unsupportedReasons.append("new projectile behavior not understood")
        XCTAssertFalse(ArenaSourceCompatibility.adapt(unknown).canPlay)
        var invalid = try XCTUnwrap(adapted.ultimate?.projectiles.first)
        invalid.indirect = false
        XCTAssertFalse(invalid.isSupported)
    }

    func testBrockIndirectImpactTracksCasterMovementDuringFlightAndStaysInMap() throws {
        let source = ArenaSourceCompatibility.adapt(trackedRocketGirl())
        let rows = (0..<9).map { y in String((0..<27).map { x -> Character in
            if x == 0 || x == 26 || y == 0 || y == 8 { return "#" }
            if x == 3 && y == 4 { return "a" }
            if x == 23 && y == 4 { return "b" }
            return "."
        }) }
        let entrants = [
            ArenaGame.Entrant(name: "Brock", brawler: .ranger, isBot: false, team: 0, sourceHero: source),
            ArenaGame.Entrant(name: "Opponent", brawler: .knight, isBot: false, team: 1)
        ]
        var game = try ArenaGame(sourceMode: .teamFight, entrants: entrants, seed: 806, map: ArenaMap(rows: rows))
        game.fighters[0].pos = V2(3.5, 4.5)
        game.fighters[1].pos = V2(23.5, 4.5)
        game.fighters[0].superCharge = 1
        game.activateSourceSkill(0, role: .ultimate, aim: V2(1, 0))
        var projectile = try XCTUnwrap(game.projectiles.first)
        let originalTarget = try XCTUnwrap(projectile.sourceLaunch?.target)
        XCTAssertEqual(projectile.lob?.to, originalTarget)

        game.fighters[0].pos = V2(3.5, 6)
        XCTAssertTrue(game.advanceSourceProjectile(&projectile, dt: 0.1))
        XCTAssertEqual(projectile.lob?.to, originalTarget + V2(0, 1.5))
        game.fighters[0].pos = V2(3.5, 15) // invalid world position cannot pull the rocket out of bounds
        XCTAssertTrue(game.advanceSourceProjectile(&projectile, dt: 0.1))
        XCTAssertEqual(projectile.lob?.to, originalTarget + V2(0, 1.5))
        game.fighters[0].alive = false // projectile retains last valid destination if owner dies
        XCTAssertTrue(game.advanceSourceProjectile(&projectile, dt: 0.1))
        XCTAssertEqual(projectile.lob?.to, originalTarget + V2(0, 1.5))
    }

    func testMortisLongDashOnlyAdaptsReviewedIdentityAndKeepsNativeData() throws {
        let original = longDashMortis()
        XCTAssertFalse(original.canPlay)
        let adapted = ArenaSourceCompatibility.adapt(original)
        XCTAssertTrue(adapted.canPlay, adapted.unsupportedReasons.joined(separator: ", "))
        XCTAssertEqual(adapted.longDash, ArenaSourceLongDash(bonusDistanceFraction: 0.9, rechargeAfterSeconds: 6))
        XCTAssertTrue(adapted.unavailableCapabilities.isEmpty)
        XCTAssertTrue(adapted.compatibilityPolicy.contains("host-mortis-dash90pct-after6s"))
        XCTAssertEqual(ArenaSourceCompatibility.adapt(adapted), adapted)
        XCTAssertEqual(original, longDashMortis(), "Adaptation must not edit the source record")

        var unknown = original
        unknown.rawSource["UniquePropertyValue1"] = "91"
        XCTAssertFalse(ArenaSourceCompatibility.adapt(unknown).canPlay)
        unknown = original
        unknown.weapon?.charge?.alwaysAtMaxRange = false
        XCTAssertFalse(ArenaSourceCompatibility.adapt(unknown).canPlay)
        unknown = original
        unknown.unsupportedReasons.append("unreviewed identity component")
        XCTAssertFalse(ArenaSourceCompatibility.adapt(unknown).canPlay)

        var invalid = try XCTUnwrap(adapted.longDash)
        invalid.rechargeAfterSeconds = .infinity
        XCTAssertFalse(invalid.isSupported)
        invalid = try XCTUnwrap(adapted.longDash)
        invalid.bonusDistanceFraction = 4
        XCTAssertFalse(invalid.isSupported)
    }

    func testMortisHostLongDashChargesWithoutAmmoDependenceAndResetsOnAttack() throws {
        let source = ArenaSourceCompatibility.adapt(longDashMortis())
        XCTAssertTrue(source.canPlay)
        let rows = (0..<9).map { y in String((0..<33).map { x -> Character in
            if x == 0 || x == 32 || y == 0 || y == 8 { return "#" }
            if x == 3 && y == 4 { return "a" }
            if x == 29 && y == 4 { return "b" }
            return "."
        }) }
        let entrants = [
            ArenaGame.Entrant(name: "Mortis", brawler: .assassin, isBot: false, team: 0, sourceHero: source),
            ArenaGame.Entrant(name: "Opponent", brawler: .knight, isBot: false, team: 1)
        ]
        var game = try ArenaGame(sourceMode: .teamFight, entrants: entrants, seed: 805, map: ArenaMap(rows: rows))
        game.fighters[0].pos = V2(3.5, 4.5)
        game.fighters[1].pos = V2(29.5, 4.5)
        let ordinary = try XCTUnwrap(source.weapon?.range)
        game.activateSourceSkill(0, role: .weapon, aim: V2(1, 0))
        XCTAssertEqual(try XCTUnwrap(game.fighters[0].sourceCharge).remaining, ordinary, accuracy: 1e-9)
        runWorld(&game, frames: 60)
        let afterOrdinary = game.fighters[0].pos.x
        XCTAssertEqual(afterOrdinary, 3.5 + ordinary, accuracy: 1e-5)

        // The charge timer is independent of Super use and current ammo state.
        game.fighters[0].superCharge = 1
        game.activateSourceSkill(0, role: .ultimate, aim: V2(0, 1))
        runWorld(&game, frames: 360)
        game.activateSourceSkill(0, role: .weapon, aim: V2(1, 0))
        XCTAssertEqual(try XCTUnwrap(game.fighters[0].sourceCharge).remaining, ordinary * 1.9, accuracy: 1e-9)
        runWorld(&game, frames: 60)
        XCTAssertEqual(game.fighters[0].pos.x, afterOrdinary + ordinary * 1.9, accuracy: 1e-5)

        // The enhanced dash is consumed; attacking again before another six
        // seconds of charging must use the normal source charge distance.
        game.activateSourceSkill(0, role: .weapon, aim: V2(1, 0))
        XCTAssertEqual(try XCTUnwrap(game.fighters[0].sourceCharge).remaining, ordinary, accuracy: 1e-9)
    }

    func testSourceShieldWaitsForCastingAndEmitsOnce() throws {
        let skill = sourceShield(casting: 0.2)
        XCTAssertTrue(skill.isSupported)
        XCTAssertTrue(skill.runtimeCapabilities.contains("self_shield"))
        var state = ArenaSourceSkillState(skill: skill)
        XCTAssertTrue(try state.activate(origin: .zero, aim: V2(1, 0)).isEmpty)
        let before = state.advance(dt: 0.15, origin: .zero)
        XCTAssertTrue(before.isEmpty)
        let cast = state.advance(dt: 0.05, origin: .zero)
        XCTAssertEqual(cast, [.shield(ArenaSourceShield(duration: 4, damageMultiplier: 0.4))])
        let rest = state.advance(dt: 4.1, origin: .zero)
        XCTAssertEqual(rest.filter { if case .shield = $0 { return true }; return false }.count, 0)
        XCTAssertEqual(rest.filter { if case .finished = $0 { return true }; return false }.count, 1)
        XCTAssertFalse(state.active)
    }

    func testSourceShieldUsesExplicitReductionAndExpiresWithoutAffectingClassicDamage() throws {
        var source = hero()
        source.id = "HostShieldTester"
        source.ultimate = sourceShield()
        XCTAssertTrue(source.canPlay)
        let entrants = [
            ArenaGame.Entrant(name: "Shield", brawler: .ranger, isBot: false, team: 0, sourceHero: source),
            ArenaGame.Entrant(name: "Attacker", brawler: .knight, isBot: true, team: 1)
        ]
        var game = try ArenaGame(sourceMode: .teamFight, entrants: entrants, seed: 701, map: .canyon)
        game.applySourceEmissions([.shield(ArenaSourceShield(duration: .infinity, damageMultiplier: -1))], owner: 0)
        XCTAssertEqual(game.fighters[0].shield, 0)
        game.fighters[0].superCharge = 1
        game.activateSourceSkill(0, role: .ultimate, aim: V2(1, 0))
        XCTAssertEqual(game.fighters[0].shield, 4, accuracy: 1e-12)
        XCTAssertEqual(game.fighters[0].sourceShieldDamageMultiplier, 0.4)
        let previous = game.fighters[0].health
        game.hurt(0, 1000, by: 1, charges: false)
        XCTAssertEqual(game.fighters[0].health, previous - 400)
        XCTAssertEqual(game.damageTaken(game.fighters[1]), 1)
        // Drive the source fighter only: AI attacks or match timeout must not
        // make shield expiry tests depend on unrelated arena events.
        for _ in 0..<4 { game.updateSourceFighter(0, input: ArenaInput(), dt: 1) }
        XCTAssertEqual(game.fighters[0].shield, 0, accuracy: 1e-12)
        XCTAssertNil(game.fighters[0].sourceShieldDamageMultiplier)
        let unshielded = game.fighters[0].health
        game.hurt(0, 1000, by: 1, charges: false)
        XCTAssertEqual(game.fighters[0].health, unshielded - 1000)
    }

    func testReviewedRosaShieldDoesNotBypassMissingDamageTakenSourceEvidence() throws {
        var original = hero()
        original.id = "Rosa"
        original.rawSource = [:]
        let remaining = "hero.Rosa.ChargeUltiFromDamage=240: requires a dedicated hero rule"
        let shieldReason = "skill.RosaUlti.BehaviorType=Shield: requires a dedicated behavior adapter"
        original.unsupportedReasons = [remaining, shieldReason]
        var special = sourceShield()
        special.id = "RosaUlti"
        special.shieldDamageMultiplier = nil
        special.rawSource = ["BehaviorType": "Shield", "ActiveTime": "4000"]
        special.unsupportedReasons = [shieldReason]
        original.ultimate = special

        let adapted = ArenaSourceCompatibility.adapt(original)
        XCTAssertEqual(adapted.ultimate?.shieldDamageMultiplier, 0.4)
        XCTAssertEqual(adapted.ultimate?.unsupportedReasons, [])
        XCTAssertTrue(adapted.ultimate?.isSupported == true)
        XCTAssertEqual(adapted.unsupportedReasons, [remaining])
        XCTAssertFalse(adapted.canPlay)
        XCTAssertEqual(ArenaSourceCompatibility.adapt(adapted), adapted)
        XCTAssertEqual(original.ultimate?.unsupportedReasons, [shieldReason], "Private source profile remains frozen")

        var unknown = original
        unknown.ultimate?.rawSource["ActiveTime"] = "5000"
        XCTAssertEqual(ArenaSourceCompatibility.adapt(unknown), unknown)
        unknown = original
        unknown.ultimate?.unsupportedReasons.append("unverified area behavior")
        XCTAssertEqual(ArenaSourceCompatibility.adapt(unknown), unknown)
    }

    func testRosaHostShieldAndDamageTakenAdaptersEnableOnlyMatchingSourceFields() throws {
        var original = hero()
        original.id = "Rosa"
        original.health = 5400
        original.rawSource = ["ChargeUltiFromDamage": "240"]
        let chargeReason = "hero.Rosa.ChargeUltiFromDamage=240: requires a dedicated hero rule"
        let shieldReason = "skill.RosaUlti.BehaviorType=Shield: requires a dedicated behavior adapter"
        original.unsupportedReasons = [chargeReason, shieldReason]
        var special = sourceShield()
        special.id = "RosaUlti"
        special.shieldDamageMultiplier = nil
        special.rawSource = ["BehaviorType": "Shield", "ActiveTime": "4000"]
        special.unsupportedReasons = [shieldReason]
        original.ultimate = special

        let adapted = ArenaSourceCompatibility.adapt(original)
        XCTAssertTrue(adapted.canPlay)
        XCTAssertEqual(try XCTUnwrap(adapted.damageTakenChargePerDamage), 0.24 / 5400.0, accuracy: 1e-12)
        XCTAssertTrue(adapted.unavailableCapabilities.isEmpty)
        XCTAssertTrue(adapted.compatibilityPolicy.contains("host-damage-taken-permille-health"))
        XCTAssertTrue(adapted.compatibilityPolicy.contains("host-self-shield60"))
        XCTAssertEqual(ArenaSourceCompatibility.adapt(adapted), adapted)
        XCTAssertEqual(original.unsupportedReasons, [chargeReason, shieldReason], "Original data must remain unchanged")

        var nonMatching = original
        nonMatching.rawSource["ChargeUltiFromDamage"] = "241"
        let blocked = ArenaSourceCompatibility.adapt(nonMatching)
        XCTAssertFalse(blocked.canPlay)
        XCTAssertNil(blocked.damageTakenChargePerDamage)
        XCTAssertEqual(blocked.unsupportedReasons, [chargeReason])

        nonMatching = original
        nonMatching.unsupportedReasons.append("unimplemented summoned pet")
        XCTAssertFalse(ArenaSourceCompatibility.adapt(nonMatching).canPlay)
    }

    func testDamageTakenSuperChargeUsesRealEnemyDamageAfterShieldAndCapsGauge() throws {
        var source = hero()
        source.id = "HostTankTester"
        source.ultimate = sourceShield()
        source.damageTakenChargePerDamage = 0.24 / Double(source.health)
        XCTAssertTrue(source.canPlay)
        XCTAssertTrue(source.unavailableCapabilities.isEmpty)
        let entrants = [
            ArenaGame.Entrant(name: "Tank", brawler: .ranger, isBot: false, team: 0, sourceHero: source),
            ArenaGame.Entrant(name: "Enemy", brawler: .knight, isBot: true, team: 1)
        ]
        var game = try ArenaGame(sourceMode: .teamFight, entrants: entrants, seed: 702, map: .canyon)
        game.fighters[0].superCharge = 1
        game.activateSourceSkill(0, role: .ultimate, aim: V2(1, 0))
        XCTAssertEqual(game.fighters[0].superCharge, 0)
        game.hurt(0, 1000, by: 1, charges: false)
        XCTAssertEqual(game.fighters[0].superCharge, 400 * 0.24 / 3100.0, accuracy: 1e-12)
        let afterEnemy = game.fighters[0].superCharge
        game.hurt(0, 100, by: nil, charges: false)
        game.hurt(0, 100, by: 0, charges: false)
        XCTAssertEqual(game.fighters[0].superCharge, afterEnemy, accuracy: 1e-12)
        game.fighters[0].superCharge = 0.99
        game.hurt(0, 1000, by: 1, charges: false)
        XCTAssertEqual(game.fighters[0].superCharge, 1, accuracy: 1e-12)
    }

    func testPocoHostHealingOnlyAdaptsReviewedSourceAndPreservesOriginalData() throws {
        let original = healingPoco()
        XCTAssertFalse(original.canPlay)
        let adapted = ArenaSourceCompatibility.adapt(original)
        XCTAssertTrue(adapted.canPlay, adapted.unsupportedReasons.joined(separator: ", "))
        XCTAssertEqual(adapted.weapon?.projectiles.first?.allyHealMaxHealthFraction, 0.05)
        XCTAssertEqual(adapted.ultimate?.projectiles.first?.healAlliesInsteadOfDamage, true)
        XCTAssertEqual(adapted.ultimate?.projectiles.first?.casterHealFraction, 1)
        XCTAssertTrue(adapted.unavailableCapabilities.isEmpty)
        XCTAssertTrue(adapted.compatibilityPolicy.contains("host-poco-ally-heal5pct-and-super"))
        XCTAssertEqual(ArenaSourceCompatibility.adapt(adapted), adapted)
        XCTAssertEqual(original, healingPoco(), "Source records cannot be mutated by adaptation")

        var mismatched = original
        mismatched.ultimate?.projectiles[0].rawSource["HealOwnPercent"] = "99"
        XCTAssertFalse(ArenaSourceCompatibility.adapt(mismatched).canPlay)
        mismatched = original
        mismatched.rawSource["Traits"] = "unknown"
        XCTAssertFalse(ArenaSourceCompatibility.adapt(mismatched).canPlay)
        mismatched = original
        mismatched.unsupportedReasons.append("requires a different effect")
        XCTAssertFalse(ArenaSourceCompatibility.adapt(mismatched).canPlay)

        var invalid = try XCTUnwrap(adapted.ultimate?.projectiles.first)
        invalid.casterHealFraction = 1.01
        XCTAssertFalse(invalid.isSupported, "Host heal fractions must be bounded")
        invalid = try XCTUnwrap(adapted.ultimate?.projectiles.first)
        invalid.piercesCharacters = false
        XCTAssertFalse(invalid.isSupported, "A healing wave cannot silently stop on its first ally")
    }

    func testHealingProjectilesHealAlliesOnceButDoNotHarmEnemies() throws {
        let source = ArenaSourceCompatibility.adapt(healingPoco())
        XCTAssertTrue(source.canPlay)
        let rows = (0..<9).map { y in String((0..<15).map { x -> Character in
            if x == 0 || x == 14 || y == 0 || y == 8 { return "#" }
            if x == 2 && y == 4 { return "a" }
            if x == 11 && y == 4 { return "b" }
            return "."
        }) }
        let entrants = [
            ArenaGame.Entrant(name: "Poco", brawler: .ranger, isBot: false, team: 0, sourceHero: source),
            ArenaGame.Entrant(name: "Ally", brawler: .ranger, isBot: false, team: 0),
            ArenaGame.Entrant(name: "Opponent", brawler: .knight, isBot: false, team: 1)
        ]
        var game = try ArenaGame(sourceMode: .teamFight, entrants: entrants, seed: 801, map: ArenaMap(rows: rows))
        game.fighters[0].pos = V2(2.5, 4.5)
        game.fighters[1].pos = V2(4.0, 4.5)
        game.fighters[2].pos = V2(6.0, 4.5)
        game.fighters[0].health = 900
        game.fighters[1].health = game.fighters[1].maxHealth - 1000
        let enemyFull = game.fighters[2].health
        game.fighters[0].superCharge = 1
        game.activateSourceSkill(0, role: .ultimate, aim: V2(1, 0))
        XCTAssertEqual(game.fighters[0].health, 3000, "Caster is healed once at Super activation")
        runWorld(&game, frames: 50)
        XCTAssertEqual(game.fighters[1].health, game.fighters[1].maxHealth, "The ally is healed once, capped at full HP")
        XCTAssertEqual(game.fighters[2].health, enemyFull, "Poco's healing Super must not damage enemies")
        XCTAssertEqual(game.events.filter { if case .heal(let target, _) = $0 { return target == 1 }; return false }.count, 1,
            "Multiple projectiles in the same volley must not multiply healing")
    }

    func testPocoMainAttackCanHealAllyAndStillDamageEnemy() throws {
        let source = ArenaSourceCompatibility.adapt(healingPoco())
        let rows = (0..<9).map { y in String((0..<15).map { x -> Character in
            if x == 0 || x == 14 || y == 0 || y == 8 { return "#" }
            if x == 2 && y == 4 { return "a" }
            if x == 11 && y == 4 { return "b" }
            return "."
        }) }
        let entrants = [
            ArenaGame.Entrant(name: "Poco", brawler: .ranger, isBot: false, team: 0, sourceHero: source),
            ArenaGame.Entrant(name: "Ally", brawler: .ranger, isBot: false, team: 0),
            ArenaGame.Entrant(name: "Enemy", brawler: .knight, isBot: false, team: 1)
        ]
        var game = try ArenaGame(sourceMode: .teamFight, entrants: entrants, seed: 802, map: ArenaMap(rows: rows))
        game.fighters[0].pos = V2(2.5, 4.5)
        game.fighters[1].pos = V2(4.0, 4.5)
        game.fighters[2].pos = V2(6.0, 4.5)
        game.fighters[1].health = game.fighters[1].maxHealth - 1000
        game.fighters[1].lastHurt = game.time // isolate healing from ordinary out-of-combat regeneration
        let expectedHeal = Int((Double(game.fighters[1].maxHealth) * 0.05).rounded())
        let enemyFull = game.fighters[2].health
        game.activateSourceSkill(0, role: .weapon, aim: V2(1, 0))
        runWorld(&game, frames: 50)
        XCTAssertEqual(game.fighters[1].health, game.fighters[1].maxHealth - 1000 + expectedHeal)
        XCTAssertLessThan(game.fighters[2].health, enemyFull, "The main attack still damages opponents")
    }

    func testActualColt650msProducesSixShotsAnd1250msProducesTwelve() throws {
        for (role, expected) in [(ArenaSourceSkillRole.weapon, 6), (.ultimate, 12)] {
            var state = ArenaSourceSkillState(skill: colt(role: role))
            var all = try state.activate(origin: .zero, aim: V2(1, 0))
            all += state.advance(dt: 2, origin: .zero)
            let shots = launches(all)
            XCTAssertEqual(shots.count, expected)
            XCTAssertEqual(shots.map(\.volleyIndex), Array(0..<expected))
            XCTAssertEqual(shots.map(\.damage), Array(repeating: role == .weapon ? 360 : 320, count: expected))
            XCTAssertFalse(state.active)
            XCTAssertEqual(all.filter { if case .finished = $0 { return true }; return false }.count, 1)
        }
    }

    func testActualRico120msIntervalUsesFiveQuantizedBurstShots() throws {
        var skill = colt()
        skill.id = "TrickshotDudeWeapon"
        skill.activeTime = 0.6
        skill.attackInterval = 0.12
        skill.dispersion = "seeded_cone"
        skill.spread = 7.5 * .pi / 180
        var state = ArenaSourceSkillState(skill: skill, seed: 1234)
        var equalSeed = state
        var anotherSeed = ArenaSourceSkillState(skill: skill, seed: 5678)
        let a = try state.activate(origin: .zero, aim: V2(1, 0)) + state.advance(dt: 1, origin: .zero)
        let b = try equalSeed.activate(origin: .zero, aim: V2(1, 0)) + equalSeed.advance(dt: 1, origin: .zero)
        let c = try anotherSeed.activate(origin: .zero, aim: V2(1, 0)) + anotherSeed.advance(dt: 1, origin: .zero)
        XCTAssertEqual(launches(a).count, 5)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(launches(a).map(\.direction), launches(c).map(\.direction))
        for shot in launches(a) {
            XCTAssertLessThanOrEqual(abs(atan2(shot.direction.y, shot.direction.x)), skill.spread / 2)
        }
    }

    func testPatternNineHostAdapterEnablesOnlyVerifiedSingleProjectileCones() throws {
        var source = hero()
        var ultimate = colt(role: .ultimate)
        ultimate.id = "BarkeepUlti"
        ultimate.projectileCount = 1
        ultimate.activeTime = 1.05
        ultimate.attackInterval = 0.2
        ultimate.spread = 75 * .pi / 360
        ultimate.rawSource = ["AttackPattern": "9", "NumBulletsInOneAttack": "1", "Spread": "75"]
        let pattern = "skill.BarkeepUlti.AttackPattern=9: not yet interpreted"
        let spread = "skill.BarkeepUlti.Spread: single-projectile dispersion needs a source pattern adapter"
        ultimate.unsupportedReasons = [pattern, spread]
        source.ultimate = ultimate
        source.unsupportedReasons = [pattern, spread]
        XCTAssertFalse(source.canPlay)

        let adapted = ArenaSourceCompatibility.adapt(source)
        XCTAssertTrue(adapted.canPlay)
        XCTAssertEqual(adapted.ultimate?.dispersion, "seeded_cone")
        XCTAssertEqual(adapted.ultimate?.rawSource, ultimate.rawSource)
        XCTAssertEqual(source.unsupportedReasons, [pattern, spread], "The frozen source profile must not be rewritten")
        XCTAssertEqual(ArenaSourceCompatibility.adapt(adapted), adapted)
        var first = ArenaSourceSkillState(skill: try XCTUnwrap(adapted.ultimate), seed: 901)
        var second = first
        let a = try first.activate(origin: .zero, aim: V2(1, 0)) + first.advance(dt: 2, origin: .zero)
        let b = try second.activate(origin: .zero, aim: V2(1, 0)) + second.advance(dt: 2, origin: .zero)
        XCTAssertEqual(a, b)
        let shots = launches(a)
        XCTAssertEqual(shots.count, 5)
        XCTAssertGreaterThan(Set(shots.map(\.direction.x)).count, 1)
        XCTAssertTrue(shots.allSatisfy { abs(atan2($0.direction.y, $0.direction.x)) <= ultimate.spread / 2 })

        var unknown = source
        unknown.ultimate?.rawSource["AttackPattern"] = "8"
        XCTAssertFalse(ArenaSourceCompatibility.adapt(unknown).canPlay)
        var stillBlocked = source
        stillBlocked.unsupportedReasons.append("unimplemented ally-healing behavior")
        XCTAssertFalse(ArenaSourceCompatibility.adapt(stillBlocked).canPlay)
    }

    func testReservedTerminalTickDoesNotEmitSeventhColtShot() throws {
        var state = ArenaSourceSkillState(skill: colt())
        let immediate = try state.activate(origin: .zero, aim: V2(1, 0))
        let first600ms = state.advance(dt: 0.6, origin: .zero)
        XCTAssertEqual(launches(immediate + first600ms).count, 6)
        XCTAssertTrue(state.active)
        XCTAssertTrue(launches(state.advance(dt: 0.05, origin: .zero)).isEmpty)
        XCTAssertFalse(state.active)
        XCTAssertFalse(state.canActivate)
        _ = state.advance(dt: 0.05, origin: .zero)
        XCTAssertTrue(state.canActivate)
    }

    func testShellyFanIsOneVolleyWithFiveSymmetricPellets() throws {
        var skill = colt()
        skill.id = "ShotgunGirlWeapon"
        skill.activeTime = 0.15
        skill.projectileCount = 5
        skill.damage = 300
        skill.chargeDamage = 300
        skill.spread = 30 * .pi / 180
        skill.range = 23 / 3.0
        var state = ArenaSourceSkillState(skill: skill)
        let all = try state.activate(origin: .zero, aim: V2(1, 0)) + state.advance(dt: 1, origin: .zero)
        let shots = launches(all)
        XCTAssertEqual(shots.count, 5)
        XCTAssertEqual(shots.map(\.pelletIndex), Array(0..<5))
        XCTAssertEqual(Set(shots.map(\.volleyIndex)), [0])
        XCTAssertEqual(shots[2].direction, V2(1, 0))
        XCTAssertEqual(shots[0].direction.y, -shots[4].direction.y, accuracy: 1e-12)
        XCTAssertEqual(shots[0].direction.x, shots[4].direction.x, accuracy: 1e-12)
    }

    func testDispatchIsIndependentOfRenderFramePartition() throws {
        var one = ArenaSourceSkillState(skill: colt())
        var sixty = one
        var uneven = one
        let origin = V2(2, 3)
        var a = try one.activate(origin: origin, aim: V2(0, -1))
        var b = try sixty.activate(origin: origin, aim: V2(0, -1))
        var c = try uneven.activate(origin: origin, aim: V2(0, -1))
        a += one.advance(dt: 1, origin: origin)
        for _ in 0..<60 { b += sixty.advance(dt: 1 / 60.0, origin: origin) }
        for dt in [0.013, 0.207, 0.001, 0.349, 0.43] { c += uneven.advance(dt: dt, origin: origin) }
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, c)
        XCTAssertEqual(one.ammo, sixty.ammo, accuracy: 1e-10)
        XCTAssertEqual(one.cooldownRemaining, uneven.cooldownRemaining, accuracy: 1e-10)
    }

    func testAmmoReloadInterruptionAndRespawnUseSourceValues() throws {
        var skill = colt()
        skill.ammoCapacity = 2
        var state = ArenaSourceSkillState(skill: skill)
        _ = try state.activate(origin: .zero, aim: V2(1, 0))
        XCTAssertEqual(state.ammo, 1)
        _ = state.advance(dt: 0.65, origin: .zero)
        XCTAssertEqual(state.ammo, 1, accuracy: 1e-10)
        _ = state.advance(dt: 0.65, origin: .zero)
        XCTAssertEqual(state.ammo, 1.5, accuracy: 1e-10)
        _ = try state.activate(origin: .zero, aim: V2(1, 0))
        state.cancel()
        XCTAssertTrue(launches(state.advance(dt: 0.4, origin: .zero)).isEmpty)
        XCTAssertFalse(state.active)
        state.reset()
        XCTAssertEqual(state.ammo, 2)
        XCTAssertTrue(state.canActivate)
    }

    func testUnsupportedAndInvalidInputCannotConsumeAmmoOrFallback() throws {
        var unsupported = colt()
        unsupported.behavior = "ChangeCharacter"
        unsupported.unsupportedReasons = ["Source transformation state is not implemented"]
        var state = ArenaSourceSkillState(skill: unsupported)
        XCTAssertThrowsError(try state.activate(origin: .zero, aim: V2(1, 0)))
        XCTAssertEqual(state.ammo, 3)
        XCTAssertFalse(state.active)
        var finite = ArenaSourceSkillState(skill: colt())
        XCTAssertThrowsError(try finite.activate(origin: .zero, aim: .zero))
        XCTAssertThrowsError(try finite.activate(origin: .zero, aim: V2(.infinity, 1)))
        XCTAssertThrowsError(try finite.activate(origin: .zero, aim: V2(.greatestFiniteMagnitude, .greatestFiniteMagnitude)))
        XCTAssertEqual(finite.ammo, 3)
        var corrupt = colt()
        corrupt.activeTime = .infinity
        XCTAssertFalse(corrupt.isSupported)
        XCTAssertTrue(finite.advance(dt: .infinity, origin: .zero).isEmpty)
    }

    func testGroundChargeCarriesExactAdapterParametersAndBoundedAim() throws {
        var skill = colt()
        skill.behavior = "Charge"
        skill.range = 8 / 3.0
        skill.damage = 1000
        skill.chargeDamage = 1000
        skill.projectiles = []
        skill.charge = ArenaSourceChargeDefinition(sourceType: 4, speed: 9, wallBreak: false,
            pushback: 0, alwaysAtMaxRange: false, endAreas: [])
        var state = ArenaSourceSkillState(skill: skill)
        let output = try state.activate(origin: V2(2, 2), aim: V2(0, 2))
        guard case .charge(let charge) = try XCTUnwrap(output.first) else { return XCTFail("No charge emission") }
        XCTAssertEqual(charge.origin, V2(2, 2))
        XCTAssertEqual(charge.direction, V2(0, 1))
        XCTAssertEqual(charge.distance, 2)
        XCTAssertEqual(charge.speed, 9)
        XCTAssertEqual(charge.damage, 1000)
        XCTAssertFalse(charge.wallBreak)
        XCTAssertFalse(state.canActivate)
    }

    func testInProgressDispatcherSurvivesCodableRoundTripWithoutRepeatingShots() throws {
        var original = ArenaSourceSkillState(skill: colt())
        _ = try original.activate(origin: .zero, aim: V2(1, 0))
        _ = original.advance(dt: 0.23, origin: .zero)
        let data = try JSONEncoder().encode(original)
        var restored = try JSONDecoder().decode(ArenaSourceSkillState.self, from: data)
        XCTAssertEqual(original, restored)
        XCTAssertEqual(original.advance(dt: 1, origin: V2(1, 0)), restored.advance(dt: 1, origin: V2(1, 0)))
        XCTAssertEqual(original, restored)
    }

    func testVolleyGroupingCannotMergeTwoActivationsOrReuseIDOnRespawn() throws {
        var state = ArenaSourceSkillState(skill: colt())
        let first = try XCTUnwrap(launches(state.activate(origin: .zero, aim: V2(1, 0))).first)
        _ = state.advance(dt: 0.7, origin: .zero)
        let second = try XCTUnwrap(launches(state.activate(origin: .zero, aim: V2(1, 0))).first)
        state.reset()
        let third = try XCTUnwrap(launches(state.activate(origin: .zero, aim: V2(1, 0))).first)
        XCTAssertEqual([first.volleyIndex, second.volleyIndex, third.volleyIndex], [0, 0, 0])
        XCTAssertEqual([first.activationID, second.activationID, third.activationID], [1, 2, 3])
    }

    func testIndirectTargetClampsAimAndFuseIsMeasuredFromLaunch() throws {
        var skill = colt()
        skill.range = 5
        skill.projectiles[0].indirect = true
        skill.projectiles[0].constantFlightTime = 0.6
        skill.projectiles[0].impactDelay = 1
        var state = ArenaSourceSkillState(skill: skill)
        let launch = try XCTUnwrap(launches(state.activate(origin: V2(2, 3), aim: V2(0, 8))).first)
        XCTAssertEqual(launch.target, V2(2, 8))
        XCTAssertEqual(launch.flightDuration, 1, "Fuse is a launch-time minimum, not 0.6 + 1 seconds")
    }

    private func area(kind: String = "Dot") -> ArenaSourceAreaEffect {
        var result = ArenaSourceAreaEffect(id: "Barley_def_atk", kind: kind, radius: 2,
            damage: nil, duration: 1.9, wallBreak: false, pushback: 0,
            unsupportedReasons: [], rawSource: [:])
        result.tickInterval = 1
        return result
    }

    func testDotAllowsLateEntryOncePerDamageWindowAndStopsAtSourceDuration() {
        var state = ArenaSourceAreaState(definition: area())
        XCTAssertEqual(state.damageTargets([1]), [1])
        XCTAssertEqual(state.damageTargets([1]), [])
        state.advance(dt: 0.45)
        XCTAssertEqual(state.damageTargets([1, 2]), [2])
        state.advance(dt: 0.55)
        XCTAssertEqual(state.damageTargets([1, 2]), [1, 2])
        state.advance(dt: 0.9)
        XCTAssertTrue(state.expired)
        XCTAssertEqual(state.damageTargets([1, 2, 3]), [])
    }

    func testDamageAreaDoesNotRehitAndDelayedDotSkipsInitialWindow() {
        var single = ArenaSourceAreaState(definition: area(kind: "Damage"))
        XCTAssertEqual(single.damageTargets([1]), [1])
        single.advance(dt: 1)
        XCTAssertEqual(single.damageTargets([1, 2]), [2])
        var definition = area()
        definition.delayFirstTick = true
        var delayed = ArenaSourceAreaState(definition: definition)
        XCTAssertEqual(delayed.damageTargets([1]), [])
        delayed.advance(dt: 0.99)
        XCTAssertEqual(delayed.damageTargets([1]), [])
        delayed.advance(dt: 0.01)
        XCTAssertEqual(delayed.damageTargets([1]), [1])
    }

    func testSourceSlowRefreshClockAndAreaDamageInheritance() {
        var definition = area()
        definition.damage = 800
        definition.statusEnemy = ArenaSourceStatusEffect(id: "CactusUltiExplosionSlow", duration: 21 * 0.05,
            speedReductionAbsolute: 400 / 300.0, speedReductionFraction: 0,
            refreshable: true, unsupportedReasons: [], rawSource: [:])
        definition.statusTickInterval = 2 * 0.05
        XCTAssertEqual(definition.resolvedDamage(skillDamage: 400), 400)
        XCTAssertEqual(definition.resolvedDamage(skillDamage: 0), 800)
        definition.inheritsSkillDamage = false
        XCTAssertEqual(definition.resolvedDamage(skillDamage: 400), 800)
        definition.damageMultiplier = 0.3
        XCTAssertEqual(definition.resolvedDamage(skillDamage: 400), 240)
        var state = ArenaSourceAreaState(definition: definition)
        XCTAssertEqual(state.statusTargets([1]), [1])
        state.advance(dt: 0.05)
        XCTAssertEqual(state.statusTargets([1]), [])
        state.advance(dt: 0.05)
        XCTAssertEqual(state.statusTargets([1]), [1])
    }

    func testCactusRadialExplosionIsSixEvenDirectionsAndEmitsOnlyOnce() throws {
        let definition = ArenaSourceBulletExplosion(projectile: colt().projectiles[0], count: 6,
            range: 13 / 3.0, angleOffset: 0)
        XCTAssertEqual(definition.directions().count, 6)
        for direction in definition.directions() { XCTAssertEqual(direction.length, 1, accuracy: 1e-12) }
        XCTAssertEqual(definition.directions()[0], V2(1, 0))
        XCTAssertEqual(definition.directions()[3].x, -1, accuracy: 1e-12)
        var effect = area(kind: "BulletExplosion")
        effect.bulletExplosion = definition
        var state = ArenaSourceAreaState(definition: effect)
        XCTAssertNotNil(state.takeBulletExplosion())
        XCTAssertNil(state.takeBulletExplosion())
        let restored = try JSONDecoder().decode(ArenaSourceAreaState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored, state)
    }

    func testMissingDeclaredCapabilitiesCannotBypassDerivedCapabilityGate() {
        var value = hero()
        value.requiredCapabilities = []
        value.weapon!.projectiles[0].indirect = true
        if !ArenaSourceHero.implementedCapabilities.contains("indirect_flight") {
            XCTAssertFalse(value.canPlay)
            XCTAssertTrue(value.unavailableCapabilities.contains("indirect_flight"))
        }
    }

    func testPrivateSourceCatalogDecodesAll118ProfilesAndMatchesCapabilityDerivation() throws {
        guard let path = ProcessInfo.processInfo.environment["ARENA_SOURCE_COMBAT_CATALOG"] else {
            throw XCTSkip("Optional private source catalog is not bundled in repository tests")
        }
        struct Catalog: Decodable { var schemaVersion: Int; var heroes: [ArenaSourceHero] }
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertEqual(catalog.heroes.count, 118)
        XCTAssertEqual(Set(catalog.heroes.map(\.id)).count, 118)
        for hero in catalog.heroes {
            let derived = (hero.weapon?.runtimeCapabilities ?? []).union(hero.ultimate?.runtimeCapabilities ?? [])
            XCTAssertEqual(Set(hero.requiredCapabilities ?? []), derived, hero.id)
        }
        let coltHero = try XCTUnwrap(catalog.heroes.first { $0.id == "Gunslinger" })
        XCTAssertEqual(coltHero.health, 3100)
        XCTAssertTrue(coltHero.canPlay)
        var state = ArenaSourceSkillState(skill: try XCTUnwrap(coltHero.weapon))
        let all = try state.activate(origin: .zero, aim: V2(1, 0)) + state.advance(dt: 1, origin: .zero)
        XCTAssertEqual(launches(all).count, 6)
        let barley = try XCTUnwrap(catalog.heroes.first { $0.id == "Barkeep" })
        XCTAssertFalse(barley.canPlay)
        let adaptedBarley = ArenaSourceCompatibility.adapt(barley)
        XCTAssertTrue(adaptedBarley.canPlay, "Pattern 9 can be dispatched with the named seeded host policy")
        XCTAssertEqual(adaptedBarley.ultimate?.dispersion, "seeded_cone")
        let surge = try XCTUnwrap(catalog.heroes.first { $0.id == "PowerLeveler" })
        XCTAssertFalse(surge.canPlay)
        XCTAssertTrue(surge.unsupportedReasons.contains { $0.contains("PowerLevelsType") })
    }

    func testSourceHeroStatsDoNotDependOnClassicIdentityLevelOrBotAdvantage() throws {
        let source = hero()
        let entrants = [ArenaGame.Entrant(name: "Player", brawler: .ranger, isBot: false, team: 0, level: 11, sourceHero: source),
                        ArenaGame.Entrant(name: "Bot", brawler: .knight, isBot: true, team: 1, level: 1, sourceHero: source)]
        let game = try ArenaGame(sourceMode: .teamFight, entrants: entrants, seed: 1, map: .canyon)
        XCTAssertEqual(game.fighters[0].maxHealth, 3100)
        XCTAssertEqual(game.fighters[1].maxHealth, 3100)
        XCTAssertEqual(game.moveSpeed(game.fighters[0]), game.moveSpeed(game.fighters[1]))
        XCTAssertEqual(game.power(0, 360), 360)
        XCTAssertEqual(game.power(1, 360), 360)
        XCTAssertEqual(game.fighters[0].ammoCapacity, 3)
        XCTAssertEqual(game.fighters[0].heroName, "colt")
    }

    func testLocalMixedRosterRetainsBothProjectAndSourceFighterRules() throws {
        XCTAssertEqual((1..<6).filter { ArenaSourceBotRoster.usesImportedHero(seat: $0, mixProjectHeroes: true) }, [1, 3, 5])
        XCTAssertEqual((1..<6).filter { !ArenaSourceBotRoster.usesImportedHero(seat: $0, mixProjectHeroes: true) }, [2, 4])
        XCTAssertEqual((1..<6).filter { ArenaSourceBotRoster.usesImportedHero(seat: $0, mixProjectHeroes: false) }, [1, 2, 3, 4, 5])
        let source = hero()
        let entrants = [
            ArenaGame.Entrant(name: "Player", brawler: .ranger, isBot: false, team: 0, sourceHero: source),
            ArenaGame.Entrant(name: "Source bot", brawler: .knight, isBot: true, team: 1, sourceHero: source),
            ArenaGame.Entrant(name: "Project bot", brawler: .mage, isBot: true, team: 1)
        ]
        var game = try ArenaGame(sourceMode: .teamFight, entrants: entrants, seed: 7, map: .canyon)
        XCTAssertEqual(game.map.id, ArenaMap.canyon.id, "Source/project mixed matches can use an established project map")
        XCTAssertNotNil(game.fighters[0].sourceWeapon)
        XCTAssertNotNil(game.fighters[1].sourceWeapon)
        XCTAssertNil(game.fighters[2].sourceWeapon)
        XCTAssertEqual(game.fighters[1].heroName, "colt")
        XCTAssertEqual(game.fighters[2].heroName, Brawler.mage.name)
        XCTAssertEqual(game.fighters[1].maxHealth, 3100)
        XCTAssertEqual(game.fighters[2].maxHealth, Brawler.mage.maxHealth)
        game.step(1.0 / 60.0, inputs: [:])
        XCTAssertTrue(game.fighters.allSatisfy { $0.health > 0 })
    }

    func testSuperChargeUsesSourceDamageCoefficientInsteadOfClassicCost() throws {
        let source = hero()
        let entrants = [ArenaGame.Entrant(name: "Player", brawler: .knight, isBot: false, team: 0, sourceHero: source),
                        ArenaGame.Entrant(name: "Bot", brawler: .ranger, isBot: true, team: 1, sourceHero: source)]
        var game = try ArenaGame(sourceMode: .teamFight, entrants: entrants, seed: 1, map: .canyon)
        game.sourceDamage(1, amount: 360, owner: 0, role: .weapon, chargeDamage: 360, pushback: 0, direction: V2(1, 0))
        XCTAssertEqual(game.fighters[0].superCharge, 360 * 93 / 400000.0, accuracy: 1e-12)
        game.sourceDamage(1, amount: 320, owner: 0, role: .ultimate, chargeDamage: 320, pushback: 0, direction: V2(1, 0))
        XCTAssertEqual(game.fighters[0].superCharge, (360 * 93 + 320 * 87) / 400000.0, accuracy: 1e-12)
    }

    private func world(wall: Bool = false) throws -> ArenaGame {
        let rows = (0..<9).map { y in String((0..<15).map { x -> Character in
            if x == 0 || x == 14 || y == 0 || y == 8 || (wall && x == 6) { return "#" }
            if x == 2 && y == 4 { return "a" }
            if x == 11 && y == 4 { return "b" }
            return "."
        }) }
        let entrants = [ArenaGame.Entrant(name: "Source", brawler: .ranger, isBot: false, team: 0, sourceHero: hero()),
                        ArenaGame.Entrant(name: "Target", brawler: .knight, isBot: true, team: 1, sourceHero: hero())]
        var game = try ArenaGame(sourceMode: .teamFight, entrants: entrants, seed: 9876, map: ArenaMap(rows: rows))
        game.fighters[0].pos = V2(2.5, 4.5)
        game.fighters[1].pos = V2(11.5, 4.5)
        return game
    }

    private func runWorld(_ game: inout ArenaGame, frames: Int) {
        for _ in 0..<frames { game.step(1 / 60.0, inputs: [:]) }
    }

    private func privateHero(_ id: String) throws -> ArenaSourceHero {
        guard let path = ProcessInfo.processInfo.environment["ARENA_SOURCE_COMBAT_CATALOG"] else {
            throw XCTSkip("Optional private source catalog is not bundled in repository tests")
        }
        struct Catalog: Decodable { var heroes: [ArenaSourceHero] }
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        return try XCTUnwrap(catalog.heroes.first { $0.id == id })
    }

    func testPrivateRosaProfileUsesHostShieldAndDamageChargeWithoutClassicSkillFallback() throws {
        let original = try privateHero("Rosa")
        XCTAssertFalse(original.canPlay)
        let adapted = ArenaSourceCompatibility.adapt(original)
        XCTAssertTrue(adapted.canPlay, adapted.unsupportedReasons.joined(separator: ", "))
        XCTAssertEqual(adapted.health, 5400)
        XCTAssertEqual(adapted.ultimate?.behavior, "Shield")
        XCTAssertEqual(adapted.ultimate?.shieldDamageMultiplier, 0.4)
        XCTAssertEqual(try XCTUnwrap(adapted.damageTakenChargePerDamage), 0.24 / 5400.0, accuracy: 1e-12)
        XCTAssertEqual(adapted.ultimate?.projectiles.count, 0)
        XCTAssertEqual(adapted.weapon?.id, original.weapon?.id)
        XCTAssertEqual(adapted.rawSource, original.rawSource)
    }

    func testPrivatePocoHealingProfileAdaptsWithoutReplacingSourceSkills() throws {
        let original = try privateHero("DeadMariachi")
        XCTAssertFalse(original.canPlay)
        let adapted = ArenaSourceCompatibility.adapt(original)
        XCTAssertTrue(adapted.canPlay, adapted.unsupportedReasons.joined(separator: ", "))
        XCTAssertEqual(adapted.weapon?.id, "DeadMariachiWeapon")
        XCTAssertEqual(adapted.ultimate?.id, "DeadMariachiUlti")
        XCTAssertEqual(adapted.weapon?.projectiles.first?.allyHealMaxHealthFraction, 0.05)
        XCTAssertEqual(adapted.ultimate?.projectiles.first?.healAlliesInsteadOfDamage, true)
        XCTAssertEqual(adapted.ultimate?.projectiles.first?.casterHealFraction, 1)
        XCTAssertEqual(adapted.rawSource, original.rawSource)
        XCTAssertEqual(adapted.compatibilityPolicy.contains("host-poco-ally-heal5pct-and-super"), true)
    }

    func testPrivateMortisProfileUsesOwnChargeAndLifestealSuper() throws {
        let original = try privateHero("Undertaker")
        XCTAssertFalse(original.canPlay)
        let adapted = ArenaSourceCompatibility.adapt(original)
        XCTAssertTrue(adapted.canPlay, adapted.unsupportedReasons.joined(separator: ", "))
        XCTAssertEqual(adapted.weapon?.id, "UndertakerWeapon")
        XCTAssertEqual(adapted.ultimate?.id, "UndertakerUlti")
        XCTAssertEqual(adapted.longDash, ArenaSourceLongDash(bonusDistanceFraction: 0.9, rechargeAfterSeconds: 6))
        XCTAssertEqual(adapted.ultimate?.projectiles.first?.lifeStealFraction, 1)
        XCTAssertEqual(adapted.rawSource, original.rawSource)
    }

    func testPrivateBrockProfileKeepsBothImpactAreasAndTracksSourceMovement() throws {
        let original = try privateHero("RocketGirl")
        XCTAssertFalse(original.canPlay)
        let adapted = ArenaSourceCompatibility.adapt(original)
        XCTAssertTrue(adapted.canPlay, adapted.unsupportedReasons.joined(separator: ", "))
        XCTAssertEqual(adapted.weapon?.id, "RocketGirlWeapon")
        XCTAssertEqual(adapted.ultimate?.id, "RocketGirlUlti")
        XCTAssertEqual(adapted.weapon?.projectiles.first?.areaEffects.count, 2)
        XCTAssertEqual(adapted.ultimate?.projectiles.first?.tracksCasterDisplacement, true)
        XCTAssertEqual(adapted.ultimate?.dispersion, "seeded_cone")
        XCTAssertEqual(adapted.rawSource, original.rawSource)
    }

    func testPrivateSandyProfileKeepsRealSmokeAreaAndThreePelletAttack() throws {
        let original = try privateHero("Sandstorm")
        XCTAssertFalse(original.canPlay)
        let adapted = ArenaSourceCompatibility.adapt(original)
        XCTAssertTrue(adapted.canPlay, adapted.unsupportedReasons.joined(separator: ", "))
        XCTAssertEqual(adapted.weapon?.id, "SandstormWeapon")
        XCTAssertEqual(adapted.weapon?.projectileCount, 3)
        XCTAssertEqual(adapted.ultimate?.id, "SandstormUlti")
        XCTAssertEqual(adapted.ultimate?.projectiles.first?.areaEffects.first?.kind, "SmokeScreen")
        XCTAssertEqual(adapted.ultimate?.projectiles.first?.areaEffects.first?.duration, 9)
        XCTAssertEqual(adapted.rawSource, original.rawSource)
    }

    func testWorldOncePerVolleyKeysIncludeActivationAndExpire() throws {
        var game = try world()
        game.fighters[1].pos = V2(5.5, 4.5)
        var definition = colt().projectiles[0]
        definition.damageOncePerVolley = true
        var launch = ArenaSourceLaunch(skillID: "grouped_source", role: .weapon, projectile: definition,
            origin: game.fighters[0].pos, direction: V2(1, 0), range: 8, damage: 360, chargeDamage: 360,
            volleyIndex: 0, pelletIndex: 0)
        launch.activationID = 1
        game.applySourceEmissions(Array(repeating: .projectile(launch), count: 4), owner: 0)
        runWorld(&game, frames: 45)
        XCTAssertEqual(game.fighters[1].health, 3100 - 360)
        launch.activationID = 2
        game.applySourceEmissions(Array(repeating: .projectile(launch), count: 4), owner: 0)
        runWorld(&game, frames: 45)
        XCTAssertEqual(game.fighters[1].health, 3100 - 720)
        XCTAssertEqual(game.sourceVolleyHits.count, 2)
        runWorld(&game, frames: 240)
        XCTAssertTrue(game.sourceVolleyHits.isEmpty)
    }

    func testWorldPassesEnvironmentAndLifeStealUseSourceFields() throws {
        var game = try world(wall: true)
        game.fighters[1].pos = V2(9.5, 4.5)
        game.fighters[0].health = 1500
        game.fighters[0].lastHurt = game.time
        var definition = colt().projectiles[0]
        definition.lifeStealFraction = 1
        var launch = ArenaSourceLaunch(skillID: "pass_environment", role: .ultimate, projectile: definition,
            origin: game.fighters[0].pos, direction: V2(1, 0), range: 10, damage: 360, chargeDamage: 360,
            volleyIndex: 0, pelletIndex: 0)
        game.applySourceEmissions([.projectile(launch)], owner: 0)
        runWorld(&game, frames: 55)
        XCTAssertEqual(game.fighters[1].health, 3100, "An ordinary source bullet must stop at the wall")
        definition.passesEnvironment = true
        launch.projectile = definition
        game.applySourceEmissions([.projectile(launch)], owner: 0)
        runWorld(&game, frames: 55)
        XCTAssertEqual(game.fighters[1].health, 2740)
        XCTAssertEqual(game.fighters[0].health, 1860)
    }

    func testWorldFuseSkipsMidairCollisionAndWaitsUntilMinimumImpactTime() throws {
        var game = try world(wall: true)
        game.fighters[1].pos = V2(9.5, 4.5)
        var definition = colt().projectiles[0]
        definition.indirect = true
        definition.directDamage = false
        definition.constantFlightTime = 0.3
        definition.impactDelay = 1
        var blast = area(kind: "Damage")
        blast.duration = 0.7
        definition.areaEffects = [blast]
        var launch = ArenaSourceLaunch(skillID: "timed_lob", role: .weapon, projectile: definition,
            origin: game.fighters[0].pos, direction: V2(1, 0), range: 10, damage: 500, chargeDamage: 500,
            volleyIndex: 0, pelletIndex: 0)
        launch.target = game.fighters[1].pos
        launch.flightDuration = 1
        game.applySourceEmissions([.projectile(launch)], owner: 0)
        runWorld(&game, frames: 59)
        XCTAssertEqual(game.fighters[1].health, 3100)
        XCTAssertEqual(game.projectiles.first?.pos, V2(9.5, 4.5), "Projectile can land before its fuse expires")
        runWorld(&game, frames: 1)
        XCTAssertEqual(game.fighters[1].health, 2600)
        XCTAssertTrue(game.projectiles.isEmpty)
    }

    func testWorldAreaSharedCooldownAndSelfPushbackAreNotRepeatedEveryFrame() throws {
        var game = try world()
        game.fighters[1].pos = V2(5.5, 4.5)
        var definition = area()
        definition.duration = 2.9
        definition.sharedTargetCooldown = 1
        let spawn = ArenaSourceAreaSpawn(skillID: "barley_dot", role: .ultimate, area: definition,
            position: game.fighters[1].pos, damage: 100, chargeDamage: 100)
        game.applySourceArea(spawn, owner: 0)
        game.applySourceArea(spawn, owner: 0)
        XCTAssertEqual(game.fighters[1].health, 3000)
        runWorld(&game, frames: 60)
        XCTAssertEqual(game.fighters[1].health, 2900, "Two overlapping patches from one owner share the source cooldown")
        var push = area(kind: "Damage")
        push.ownPushback = 0.5
        let before = game.fighters[0].pos
        game.applySourceArea(ArenaSourceAreaSpawn(skillID: "source_self_push", role: .weapon, area: push,
            position: before - V2(0.5, 0), damage: 0, chargeDamage: 0), owner: 0)
        XCTAssertEqual(game.fighters[0].pos.x, before.x + 0.5, accuracy: 1e-10)
        runWorld(&game, frames: 5)
        XCTAssertEqual(game.fighters[0].pos.x, before.x + 0.5, accuracy: 1e-10)
    }

    func testWorldSourceSlowUsesAbsoluteReductionOnClassicAndSourceHeroes() throws {
        var game = try world()
        let slow = ArenaSourceStatusEffect(id: "CactusUltiExplosionSlow", duration: 1.05,
            speedReductionAbsolute: 400 / 300.0, speedReductionFraction: 0,
            refreshable: true, unsupportedReasons: [], rawSource: [:])
        game.applySourceSlow(slow, target: 0)
        XCTAssertEqual(game.moveSpeed(game.fighters[0]), 2.5 - 400 / 300.0, accuracy: 1e-12)
        game.fighters[1].sourceHero = nil
        game.applySourceSlow(slow, target: 1)
        XCTAssertEqual(game.moveSpeed(game.fighters[1]), Brawler.knight.speed - 400 / 300.0, accuracy: 1e-12)
        runWorld(&game, frames: 64)
        XCTAssertNil(game.fighters[0].sourceSlows)
        XCTAssertEqual(game.moveSpeed(game.fighters[0]), 2.5)
    }

    func testRealSpikeImpactPreservesAllSixChildrenAfterOwnerDeath() throws {
        let spike = try privateHero("Cactus")
        var game = try world()
        game.fighters[1].pos = V2(11.5, 1.5)
        var state = ArenaSourceSkillState(skill: try XCTUnwrap(spike.weapon))
        game.applySourceEmissions(try state.activate(origin: game.fighters[0].pos, aim: V2(1, 0)), owner: 0)
        game.knockOut(0, by: nil)
        var children: [Projectile] = []
        for _ in 0..<100 {
            game.step(1 / 60.0, inputs: [:])
            children = game.projectiles.filter { $0.sourceLaunch?.projectile.id == "CactusSpike" }
            if !children.isEmpty { break }
        }
        XCTAssertFalse(game.fighters[0].alive)
        XCTAssertEqual(children.count, 6, "Impact-created children must survive active-projectile draining")
        XCTAssertEqual(Set(children.map(\.id)).count, 6)
        XCTAssertTrue(children.allSatisfy { $0.damage == 540 })
    }

    func testRealSpikeUltimateCrossesWallThenApplies400DamageAndSourceSlow() throws {
        let spike = try privateHero("Cactus")
        var game = try world(wall: true)
        game.fighters[1].pos = V2(8.5, 4.5)
        var state = ArenaSourceSkillState(skill: try XCTUnwrap(spike.ultimate))
        game.applySourceEmissions(try state.activate(origin: game.fighters[0].pos, aim: V2(6, 0)), owner: 0)
        runWorld(&game, frames: 63)
        XCTAssertEqual(game.fighters[1].health, 2700)
        XCTAssertEqual(game.moveSpeed(game.fighters[1]), 2.5 - 400 / 300.0, accuracy: 1e-12)
        XCTAssertEqual(game.sourceAreas.first?.spawn.damage, 400, "Source area 800 is a fallback; skill damage 400 is inherited")
        runWorld(&game, frames: 30)
        XCTAssertEqual(game.fighters[1].health, 2700)
        game.knockOut(0, by: nil)
        runWorld(&game, frames: 30)
        XCTAssertEqual(game.fighters[1].health, 2300, "An existing area continues after owner death")
    }

    func testRealRicoFiveSourceBulletsBounceOffWallAndHitBehindOrigin() throws {
        let rico = try privateHero("TrickshotDude")
        var game = try world(wall: true)
        game.fighters[1].pos = V2(1.5, 4.5)
        var state = ArenaSourceSkillState(skill: try XCTUnwrap(rico.weapon), seed: 127)
        game.applySourceEmissions(try state.activate(origin: game.fighters[0].pos, aim: V2(1, 0)), owner: 0)
        for _ in 0..<90 {
            game.applySourceEmissions(state.advance(dt: 1 / 60.0, origin: game.fighters[0].pos), owner: 0)
            game.step(1 / 60.0, inputs: [:])
        }
        XCTAssertEqual(game.fighters[1].health, 1600)
        XCTAssertEqual(game.fighters[0].damageDealt, 1500)
    }

    func testRoundBreakClearsSourceAreasSlowsAndSharedHitCaches() throws {
        var game = try world()
        game.applySourceArea(ArenaSourceAreaSpawn(skillID: "clear_source", role: .weapon, area: area(),
            position: game.fighters[1].pos, damage: 100, chargeDamage: 100), owner: 0)
        XCTAssertFalse(game.sourceAreas.isEmpty)
        game.startBreak()
        XCTAssertTrue(game.sourceAreas.isEmpty)
        XCTAssertTrue(game.sourceSharedAreaCooldowns.isEmpty)
        XCTAssertTrue(game.sourceVolleyHits.isEmpty)
    }

    func testActualFourSourceHeroesAreAdmittedWithTheirOwnWeaponDefinitions() throws {
        let ids = ["ShotgunGirl", "Gunslinger", "TrickshotDude", "Cactus"]
        let profiles = try ids.map(privateHero)
        XCTAssertTrue(profiles.allSatisfy(\.canPlay))
        let entrants = profiles.enumerated().map { index, profile in
            ArenaGame.Entrant(name: profile.name, brawler: .ranger, isBot: index != 0,
                team: index < 2 ? 0 : 1, level: 9, sourceHero: profile)
        }
        var game = try ArenaGame(sourceMode: .teamFight, entrants: entrants, seed: 91, map: .canyon)
        for index in profiles.indices {
            XCTAssertEqual(game.fighters[index].sourceHero?.id, ids[index])
            XCTAssertEqual(game.fighters[index].health, profiles[index].health)
            XCTAssertEqual(game.power(index, profiles[index].weapon!.damage), profiles[index].weapon!.damage)
            game.activateSourceSkill(index, role: .weapon, aim: V2(1, 0))
        }
        XCTAssertEqual(game.projectiles.count, 8)
        XCTAssertEqual(Set(game.projectiles.compactMap { $0.sourceLaunch?.projectile.id }),
            ["ShotgunGirlProjectile", "GunslingerProjectile", "TrickshotDudeProjectile", "CactusProjectile"])
    }
}
