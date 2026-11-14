import XCTest
@testable import ShiftCore

final class DuelTriadSourceFightTests: XCTestCase {
    private func rules(level: Int = 6) throws -> DuelTriadRules {
        var value = try DuelTriadTestFixture.runtimeRules(level: level)
        value.mist.initial = value.mist.maximum
        return value
    }

    func testHeldRangedAdvancesSourceWaveStagesAtTheirSharedTicks() throws {
        var fight = try DuelTriadFightFixture.fight(rules: rules(), distance: 2600)
        fight.step(.init(weaponCommand: .ranged, rangedHeld: true), opponent: .neutral)
        XCTAssertEqual(fight.triadState(0)?.ownerMotion?.tick, 0)
        XCTAssertEqual(fight.triadState(0)?.onslaughtCharges, 2)
        for tick in 1...92 {
            fight.step(.init(rangedHeld: true), opponent: .neutral)
            XCTAssertEqual(fight.triadState(0)?.ownerMotion?.tick, tick)
            let stage: DuelTriadState.OwnerAnimation = tick < 52 ? .mistOnslaught1 : tick < 92 ? .mistOnslaught2 : .mistOnslaught3
            XCTAssertEqual(fight.triadState(0)?.ownerMotion?.animation, stage)
            XCTAssertEqual(fight.fighters[0].weaponPose?.clip, fight.profiles[0].roles[stage.role])
            XCTAssertEqual(fight.fighters[0].weaponPose?.tick, tick)
            XCTAssertEqual(fight.triadState(0)?.onslaughtCharges, tick < 52 ? 2 : tick < 92 ? 1 : 0)
        }
    }

    func testReleasingRangedDoesNotSpendOrInventLaterWaveStages() throws {
        var fight = try DuelTriadFightFixture.fight(rules: rules(), distance: 2600)
        fight.step(.init(weaponCommand: .ranged), opponent: .neutral)
        var releases = 0
        for _ in 0..<110 {
            fight.step(.neutral, opponent: .neutral)
            releases += fight.triadPresentationEvents.filter {
                if case .attackReleased(let volume) = $0.kind { return volume.ability == .mistOnslaught }
                return false
            }.count
        }
        XCTAssertEqual(releases, 1)
        XCTAssertEqual(fight.triadState(0)?.onslaughtCharges, 2)
        XCTAssertNil(fight.triadState(0)?.ownerMotion)
    }

    func testSourceSoulReleaseUsesItsOwnMotionInsteadOfBirthOrMovingOwner() throws {
        let sourceRules = try rules()
        let catalog = try DuelTriadFightFixture.catalog(rules: sourceRules)
        let profile = try XCTUnwrap(catalog.profile(for: .ember))
        var state = try XCTUnwrap(DuelTriadState(rules: sourceRules, seed: 15)); state.beginRound(roundID: 0)
        let appearance = try XCTUnwrap(state.start(.legionary).compactMap {
            if case .sourceSoulAppeared(let appearance) = $0 { return appearance }; return nil
        }.first)
        var fighters = [DuelGame.Fighter(hero: .ember, x: 3500, facing: -1),
                        DuelGame.Fighter(hero: .liu, x: 6500, facing: -1)]
        fighters[0].y = 600
        var space = DuelTriadSpatialState(); space.tick = 10
        space.appear(appearance, owner: 0, fighters: fighters)
        let summon = try XCTUnwrap(space.summons.first)
        XCTAssertEqual(summon.direction, 1, "Source SetDirection recomputes the target direction")
        XCTAssertEqual(summon.y, 0, "This arena's source scene baseline is zero, independent of owner's jump")
        var attack: DuelTriadState.Attack?
        for _ in 0..<34 {
            for effect in state.step() { if case .attack(let value) = effect { attack = value } }
            space.tick += 1
        }
        fighters[0].x = 7000
        let volume = try XCTUnwrap(space.spawn(XCTUnwrap(attack), owner: 0, fighters: fighters, profile: profile))
        XCTAssertEqual(volume.originX, 3500 - 1380 + 340)
        XCTAssertEqual(volume.originY, 0)
        XCTAssertEqual(volume.direction, 1)
    }

    func testChangingSourceSoulMotionAccumulatesRootWithoutTeleporting() throws {
        let sourceRules = try rules(), profile = try XCTUnwrap(DuelTriadFightFixture.catalog(rules: sourceRules).profile(for: .ember))
        var space = DuelTriadSpatialState()
        space.appear(.init(summonID: 1, origin: .dance, move: .danceNinjato), owner: 0,
            fighters: [.init(hero: .ember, x: 3000, facing: 1), .init(hero: .liu, x: 6000, facing: -1)])
        space.tick = 20
        let before = try XCTUnwrap(space.summons.first).worldX(at: space.tick, profile: profile)
        space.changeMotion(id: 1, owner: 0, animation: .ninjatoActiveStart, profile: profile)
        XCTAssertEqual(space.summons[0].worldX(at: 20, profile: profile), before)
        XCTAssertEqual(space.summons[0].worldX(at: 27, profile: profile), before + 70)
        XCTAssertEqual(space.summons[0].motionBeganAt, 20)
    }

    func testAuthoredSoulCapsuleRejectsAnOutOfPlaneHitInsideItsOldRectangle() throws {
        let sourceRules = try rules(), base = try XCTUnwrap(DuelTriadFightFixture.catalog(rules: sourceRules).profile(for: .ember))
        var state = try XCTUnwrap(DuelTriadState(rules: sourceRules, seed: 7)); state.beginRound(roundID: 0)
        let appearance = try XCTUnwrap(state.start(.legionary).compactMap {
            if case .sourceSoulAppeared(let value) = $0 { return value }; return nil
        }.first)
        var attack: DuelTriadState.Attack?
        for _ in 0..<34 { for effect in state.step() { if case .attack(let value) = effect { attack = value } } }
        let sourceAttack = try XCTUnwrap(attack)
        let fighters = [DuelGame.Fighter(hero: .ember, x: 3500, facing: 1), DuelGame.Fighter(hero: .liu, x: 5000, facing: -1)]
        let target = DuelWeaponCapsule(a: .init(x: 5, y: 0.9), b: .init(x: 5, y: 1.4), radius: 0.1)
        for z in [2.0, 0.0] {
            let track = try XCTUnwrap(base.summonTrack(role: appearance.role))
            let capsule = DuelWeaponCollisionEdge(id: "synthetic_blade", side: "right", radiusMillimeters: 40,
                base: .init(repeating: .init(x: 2.54, y: 1, z: z), count: track.root.count),
                tip: .init(repeating: .init(x: 2.54, y: 1.4, z: z), count: track.root.count))
            let bound = DuelSummonMotionTrack(role: track.role, clip: track.clip, frames: track.frames,
                sourceSHA256: track.sourceSHA256, sourceBundle: track.sourceBundle, root: track.root, groundLift: track.groundLift,
                boneConfigurationSHA256: String(repeating: "a", count: 64), collisionEdges: [capsule], hurtCapsules: [],
                attackParts: ["primary": [capsule.id]])
            try bound.validate()
            let profile = DuelWeaponProfile(id: base.id, hero: base.hero, faction: base.faction, resourceName: base.resourceName,
                bytes: base.bytes, sha256: base.sha256, bodyID: base.bodyID, weaponID: base.weaponID,
                activeWeaponSides: base.activeWeaponSides, roles: base.roles, clips: base.clips,
                combatRules: base.combatRules, triadRules: base.triadRules, summonTracks: [bound])
            var space = DuelTriadSpatialState(); space.appear(appearance, owner: 0, fighters: fighters); space.tick = 34
            space.spawn(sourceAttack, owner: 0, fighters: fighters, profile: profile)
            let hits = space.contacts(fighters: fighters, profiles: [profile, base],
                hurts: [.init(minX: 3300, maxX: 3700, minY: 0, maxY: 1800), .init(minX: 4900, maxX: 5100, minY: 0, maxY: 1800)],
                previousX: [3500, 5000], previousHurtY: [0, 0],
                hurtBefore: [nil, [("synthetic_torso", target)]], hurtAfter: [nil, [("synthetic_torso", target)]])
            XCTAssertEqual(hits.count, z == 0 ? 1 : 0)
        }
    }
}
