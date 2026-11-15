import Foundation
import XCTest
@testable import ShiftCore

final class DuelImperialHeavyTests: XCTestCase {
    private func profiles() throws -> (DuelWeaponProfile, DuelWeaponCatalog) {
        let env = ProcessInfo.processInfo.environment
        guard let actor = env["ERLANG_RUNTIME_PROFILE"], let opponents = env["ERLANG_OPPONENT_CATALOG"] else {
            throw XCTSkip("Authenticated Imperial source actor/victim profiles are not staged")
        }
        let decoder = JSONDecoder()
        return (try decoder.decode(DuelWeaponProfile.self, from: Data(contentsOf: URL(fileURLWithPath: actor))),
                try decoder.decode(DuelWeaponCatalog.self, from: Data(contentsOf: URL(fileURLWithPath: opponents))))
    }
    private func catalog(_ actor: DuelWeaponProfile, _ target: DuelWeaponProfile) -> DuelWeaponCatalog {
        .init(schemaVersion: 1, previewFramesPerSecond: 30, profiles: [actor, target])
    }
    private func fight(_ catalog: DuelWeaponCatalog, direction: Int = 1,
                       mode: DuelGame.Mode = .practice, targetHealth: Int = 1000) throws -> DuelWeaponFight {
        let x = direction == 1 ? 3500 : 6500
        var target = DuelGame.Fighter(hero: catalog.profiles[1].hero, x: x + direction * 1500, facing: -direction)
        target.health = targetHealth
        var fight = try XCTUnwrap(DuelWeaponFight(fighters: [.init(hero: .wuYong, x: x, facing: direction), target],
            mode: mode, difficulty: .learning, catalog: catalog, seed: 42))
        for _ in 0..<1000 where fight.sourceIntroActive { fight.step(.neutral, opponent: .neutral) }
        return fight
    }
    private func startPair(_ fight: inout DuelWeaponFight) throws -> DuelImperialHeavyState {
        if fight.profiles[1].isTriad {
            // The real H17 Hungry Defender protects the first incoming hit
            // for one source tick. Consume it by actual combat, then exercise
            // the pair during its unchanged 600-tick cooldown.
            let hits = fight.landedHits[0]
            fight.step(.init(weaponCommand: .heavy), opponent: .neutral)
            for _ in 0..<96 where fight.landedHits[0] == hits { fight.step(.neutral, opponent: .neutral) }
            XCTAssertEqual(fight.landedHits[0], hits + 1)
            XCTAssertNil(fight.imperialHeavyState); XCTAssertEqual(fight.triadState(1)?.impactImmune, true)
            let idle = fight.profiles[0].clip(role: "idle")?.name
            for _ in 0..<500 where fight.fighters[0].weaponPose?.clip != idle ||
                fight.fighters[0].stun > 0 || fight.fighters[0].knockdown > 0 {
                fight.step(.neutral, opponent: .neutral)
            }
            XCTAssertEqual(fight.fighters[0].weaponPose?.clip, idle)
        }
        let earlierHits = fight.landedHits[0]
        fight.step(.init(weaponCommand: .heavy), opponent: .neutral)
        var beforeContact = ""
        for _ in 0..<96 where fight.imperialHeavyState == nil {
            let prior = "poses=\(String(describing: fight.fighters.map(\.weaponPose))), air=\(fight.isAirborne(1)), impactImmune=\(fight.triadState(1)?.impactImmune ?? false), down=\(fight.fighters[1].knockdown), stun=\(fight.fighters[1].stun)"
            let hits = fight.landedHits[0]
            fight.step(.neutral, opponent: .neutral)
            if fight.landedHits[0] > hits { beforeContact = prior; break }
        }
        let pair = try XCTUnwrap(fight.imperialHeavyState,
            "Original Miss must contact; landed=\(fight.landedHits), x=\(fight.fighters.map(\.x)), before=\(beforeContact)")
        XCTAssertEqual(fight.landedHits[0], earlierHits + 1)
        XCTAssertTrue(DuelImperialHeavyMotion.captureTicks.contains(pair.initialActiveTick))
        XCTAssertEqual(pair.age, 0)
        XCTAssertEqual(fight.fighters[0].weaponPose?.clip, DuelImperialHeavyMotion.activeName)
        XCTAssertEqual(fight.fighters[0].weaponPose?.tick, pair.initialActiveTick)
        XCTAssertEqual(fight.fighters[1].weaponPose?.tick, 0)
        XCTAssertEqual(fight.fighters[1].weaponPose?.clip, fight.profiles[1].clip(role: pair.victimRole)?.name)
        let own = try XCTUnwrap(fight.sourcePelvis(0)), victim = try XCTUnwrap(fight.sourcePelvis(1))
        XCTAssertEqual(victim.x - own.x, -1.840 * Double(pair.victimDirection), accuracy: 0.002)
        return pair
    }
    func testOriginalSelectorKeepsEqualityVictimFootContextAndBaseXorAlias() throws {
        // Explicit source truth table: COM-left, Enemy toe-left-forward,
        // victim f65, original Mirror alias, actual mirrored local pose.
        let cases: [(Bool, Bool, Bool, Bool, Bool)] = [
            (true,true,false,true,true), (true,true,true,false,true),
            (true,false,false,false,false), (true,false,true,true,false),
            (false,true,false,false,false), (false,true,true,true,false),
            (false,false,false,true,true), (false,false,true,false,true)]
        for direction in [-1, 1] {
            for (left, toe, base, alias, rendered) in cases {
                let footL = (base ? -1.0 : 1.0) * Double(direction)
                let selection = try XCTUnwrap(DuelImperialHeavyMotion.selection(
                    attackerCOMX: left ? -1 : 1, victimCOMX: 0,
                    attackerToeLX: toe ? 1 : -1, attackerToeRX: 0,
                    victimFootLX: footL, victimFootRX: 0, victimDirection: direction))
                XCTAssertEqual(selection.baseMirror, base)
                XCTAssertEqual(selection.sourceAliasFlipsMirror, alias)
                XCTAssertEqual(selection.renderedMirror, rendered)
            }
        }
        let equal = try XCTUnwrap(DuelImperialHeavyMotion.selection(attackerCOMX: 0, victimCOMX: 0,
            attackerToeLX: 0, attackerToeRX: 0, victimFootLX: 0, victimFootRX: 0, victimDirection: -1))
        XCTAssertTrue(equal.baseMirror); XCTAssertTrue(equal.sourceAliasFlipsMirror); XCTAssertFalse(equal.renderedMirror)
        XCTAssertNil(DuelImperialHeavyMotion.selection(attackerCOMX: .nan, victimCOMX: 0,
            attackerToeLX: 0, attackerToeRX: 0, victimFootLX: 0, victimFootRX: 0, victimDirection: 1))
    }
    func testAuxiliaryRuleRequiresExactSourceActiveCapabilityAndWindow() throws {
        let (wu, prior) = try profiles(), sun = try XCTUnwrap(prior.profile(for: .ember))
        let bound = catalog(wu, sun)
        XCTAssertNoThrow(try bound.validate())
        XCTAssertTrue(DuelImperialHeavyMotion.canPair(attacker: wu, victim: sun))
        for variant in 0..<2 {
            let changed = try DuelWeaponTestFixtures.changing(bound) { profiles in
                var rules = profiles[0]["combatRules"] as! [String: Any]
                var attacks = rules["attacks"] as! [[String: Any]]
                let i = attacks.firstIndex { $0["clipName"] as? String == DuelImperialHeavyMotion.activeName }!
                if variant == 0 { attacks[i]["clipName"] = profiles[0]["roles"].flatMap { ($0 as? [String: String])?["idle"] } }
                else {
                    var strikes = attacks[i]["strikes"] as! [[String: Any]]
                    strikes[0]["startTick"] = 161; attacks[i]["strikes"] = strikes
                }
                rules["attacks"] = attacks; profiles[0]["combatRules"] = rules
            }
            XCTAssertThrowsError(try changed.validate(), "Variant \(variant)")
        }
    }
    func testActualTwoRigsAndFacingsKeepIndependentSourceClocksAndSecondContact() throws {
        let (wu, prior) = try profiles()
        for (hero, direction) in [(DuelGame.Hero.ember, 1), (.liu, -1)] {
            var fight = try fight(catalog(wu, XCTUnwrap(prior.profile(for: hero))), direction: direction)
            let initial = try startPair(&fight)
            let initialHits = fight.landedHits[0], initialDamage = fight.damageDealt[0]
            var secondHitTick: Int?
            var victimReleasedAt: Int?
            for _ in 0..<230 where fight.imperialHeavyState != nil {
                let previousHits = fight.landedHits[0]
                fight.step(.neutral, opponent: .neutral)
                if fight.landedHits[0] > previousHits { secondHitTick = fight.fighters[0].weaponPose?.tick }
                if let pair = fight.imperialHeavyState {
                    XCTAssertEqual(pair.activeTick, initial.initialActiveTick + pair.age)
                    if pair.victimReleased, victimReleasedAt == nil { victimReleasedAt = pair.age }
                    if !pair.victimReleased {
                        XCTAssertEqual(fight.fighters[1].weaponPose?.tick, pair.age)
                        XCTAssertFalse(fight.canUse(.weapon, index: 1))
                    }
                }
            }
            XCTAssertNotNil(secondHitTick); XCTAssertTrue((162...169).contains(secondHitTick ?? -1))
            XCTAssertEqual(fight.landedHits[0], initialHits + 1); XCTAssertEqual(fight.damageDealt[0], initialDamage + 80)
            XCTAssertEqual(victimReleasedAt, 133); XCTAssertNil(fight.imperialHeavyState)
        }
    }
    func testSeparatedSecondCapsuleDoesNotAutoDamageAndLethalPairClears() throws {
        let (wu, prior) = try profiles(), liu = try XCTUnwrap(prior.profile(for: .liu))
        let original = catalog(wu, liu)
        // Deliberate in-memory geometry fault, not an authenticated release:
        // move only Active's actual left capsule away. Miss remains original.
        let noSecondContact = try DuelWeaponTestFixtures.changing(original) { profiles in
            var clips = profiles[0]["clips"] as! [[String: Any]]
            let i = clips.firstIndex { $0["name"] as? String == DuelImperialHeavyMotion.activeName }!
            var tracks = clips[i]["tracks"] as! [String: Any]
            var edges = tracks["collisionEdges"] as! [[String: Any]]
            let edge = edges.firstIndex { $0["id"] as? String == "Spear_Attacking_Edge_l" }!
            for key in ["base", "tip"] {
                edges[edge][key] = (edges[edge][key] as! [[Double]]).map { p in [p[0] + 10, p[1], p[2]] }
            }
            tracks["collisionEdges"] = edges; clips[i]["tracks"] = tracks; profiles[0]["clips"] = clips
        }
        var miss = try fight(noSecondContact)
        _ = try startPair(&miss)
        for _ in 0..<230 where miss.imperialHeavyState != nil { miss.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(miss.landedHits[0], 1); XCTAssertEqual(miss.damageDealt[0], 70)
        var lethal = try fight(original, mode: .versus, targetHealth: 100)
        let lethalPair = try startPair(&lethal)
        for _ in 0..<220 where lethal.phase == .fighting { lethal.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(lethal.landedHits[0], 2, "Initial source tick \(lethalPair.initialActiveTick), mirror \(lethalPair.victimRole)"); XCTAssertEqual(lethal.fighters[1].health, 0)
        XCTAssertNil(lethal.imperialHeavyState)
        for _ in 0..<500 where lethal.roundNumber == 1 { lethal.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(lethal.roundNumber, 2); XCTAssertNil(lethal.imperialHeavyState)
        XCTAssertEqual(lethal.fighters[1].health, 1000)
    }
}
