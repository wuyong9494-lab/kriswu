import XCTest
@testable import ShiftCore

/// Synthetic geometry exercises the authenticated-catalog capability contract
/// and live combat adapter. Original media/FK has a separate private receipt.
final class DuelSourceStunMotionTests: XCTestCase {
    private typealias Motion = DuelSourceStunMotion

    private func bound(_ catalog: DuelWeaponCatalog) -> DuelWeaponCatalog {
        let profiles = catalog.profiles.map { profile -> DuelWeaponProfile in
            var roles = profile.roles, clips = profile.clips
            for motion in Motion.allCases {
                let count = motion.lastSampleTick + 1
                let zero = Array(repeating: DuelWeaponPoint(), count: count)
                let torso = Array(repeating: DuelWeaponPoint(y: 1), count: count)
                let foot = Array(repeating: DuelWeaponPoint(x: 0.05), count: count)
                let hurt = (0..<15).map { index in
                    DuelWeaponHurtCapsule(id: "synthetic-stun-body-\(index)", radiusMillimeters: 150,
                        defense: .body, base: Array(repeating: .init(y: 0.5), count: count),
                        tip: Array(repeating: .init(y: 1.5), count: count))
                }
                let tracks = DuelWeaponTracks(samplesPerSourceFrame: 2, root: zero,
                    handL: torso, handR: torso, footL: foot, footR: zero,
                    weaponBaseL: profile.activeWeaponSides.contains("left") ? torso : [],
                    weaponTipL: profile.activeWeaponSides.contains("left") ? torso : [],
                    weaponBaseR: torso, weaponTipR: torso, groundLift: Array(repeating: 0, count: count),
                    hurtCapsules: hurt, centerOfMass: torso, pelvis: torso)
                clips.append(.init(name: motion.clip, frames: motion.frames, sha256: motion.sourceSHA256,
                    bundle: Motion.sourceBundle, tracks: tracks))
                roles[motion.role] = motion.clip
            }
            return .init(id: profile.id, hero: profile.hero, faction: profile.faction,
                resourceName: profile.resourceName, bytes: profile.bytes, sha256: profile.sha256,
                bodyID: profile.bodyID, weaponID: profile.weaponID, activeWeaponSides: profile.activeWeaponSides,
                roles: roles, clips: clips, comboLinks: profile.comboLinks, combatRules: profile.combatRules,
                panguRules: profile.panguRules, ordinaryThrows: profile.ordinaryThrows,
                triadRules: profile.triadRules, summonTracks: profile.summonTracks)
        }
        return .init(schemaVersion: catalog.schemaVersion, previewFramesPerSecond: catalog.previewFramesPerSecond,
            sourceFramesPerSecond: catalog.sourceFramesPerSecond, profiles: profiles)
    }

    private func fight(caster: Int = 0, originalBinding: Bool = true, lethal: Bool = false) throws -> DuelWeaponFight {
        let rules = try DuelPanguRules.d19HeavenlyKing(level: 2, maximumHealth: 10_000,
            weaponPower: 100, unarmedPower: 100, magicPower: 100, rangedPower: 100,
            spatialTemplate: DuelPanguTestFixture.rules(level: 2))
        let base = try DuelPanguFightFixture.catalog(rules: rules, ordinaryDamage: lethal ? 100_000 : 20,
            ordinaryHitStop: 3)
        let catalog = originalBinding ? bound(base) : base
        try catalog.validate()
        var result = try XCTUnwrap(DuelWeaponFight(fighters: [
            .init(hero: caster == 0 ? .liu : .ember, x: 3500, facing: 1),
            .init(hero: caster == 1 ? .liu : .ember, x: 4300, facing: -1)
        ], mode: .versus, difficulty: .learning, catalog: catalog, seed: 41))
        let input = DuelGame.Input(move: result.fighters[caster].facing, weaponCommand: .shadow)
        result.step(caster == 0 ? input : .neutral, opponent: caster == 1 ? input : .neutral)
        XCTAssertTrue(DuelPanguFightFixture.until(&result, limit: 180) { value in
            value.panguPresentation.controls.contains { $0.target == 1 - caster && $0.kind == .stun && $0.remainingTicks == 90 }
        })
        return result
    }

    func testThreeBindingsAreCompleteAndStrictWithoutReclassifyingLegacyEquipment() throws {
        let original = DuelWeaponTestFixtures.catalog()
        XCTAssertNoThrow(try original.validate())
        XCTAssertFalse(original.profiles.contains { Motion.matches(profile: $0) })
        let complete = bound(original)
        XCTAssertNoThrow(try complete.validate())
        XCTAssertTrue(complete.profiles.allSatisfy { Motion.matches(profile: $0) })
        XCTAssertEqual(complete.profile(for: .liu)?.id, "liu_hammers")
        XCTAssertFalse(try XCTUnwrap(complete.profile(for: .liu)).isPangu)
        for mutation in ["role", "sha", "bundle", "clock", "pelvis", "capsules"] {
            let invalid = try DuelWeaponTestFixtures.changing(complete) { profiles in
                var clips = profiles[0]["clips"] as! [[String: Any]]
                let index = clips.firstIndex { $0["name"] as? String == Motion.end.clip }!
                if mutation == "role" {
                    var roles = profiles[0]["roles"] as! [String: String]
                    roles.removeValue(forKey: Motion.end.role); profiles[0]["roles"] = roles
                } else if mutation == "sha" { clips[index]["sha256"] = String(repeating: "e", count: 64) }
                else if mutation == "bundle" { clips[index]["bundle"] = "other-common-bundle" }
                else if mutation == "clock" { clips[index]["playbackTicks"] = 59 }
                else {
                    var tracks = clips[index]["tracks"] as! [String: Any]
                    if mutation == "pelvis" { tracks.removeValue(forKey: "pelvis") }
                    else { tracks["hurtCapsules"] = Array((tracks["hurtCapsules"] as! [[String: Any]]).dropLast()) }
                    clips[index]["tracks"] = tracks
                }
                profiles[0]["clips"] = clips
            }
            XCTAssertThrowsError(try invalid.validate(), mutation)
        }
    }

    func testLiveSourceFramesStartAtZeroAndTimerExpiryWaitsForLoopEndInBothSlots() throws {
        for caster in [0, 1] {
            let target = 1 - caster
            var value = try fight(caster: caster)
            XCTAssertEqual(value.fighters[target].weaponPose?.clip, Motion.start.clip)
            XCTAssertEqual(value.fighters[target].weaponPose?.tick, 0)
            XCTAssertEqual(value.fighters[target].stun, 90)
            XCTAssertFalse(value.canUse(.weapon, index: target))
            let origin = value.fighters[target].x
            for _ in 0..<51 { value.step(.neutral, opponent: .neutral) }
            XCTAssertEqual(value.fighters[target].weaponPose?.tick, 51)
            value.step(.neutral, opponent: .neutral)
            XCTAssertEqual(value.fighters[target].weaponPose?.clip, Motion.loop.clip)
            XCTAssertEqual(value.fighters[target].weaponPose?.tick, 0)
            XCTAssertEqual(value.fighters[target].x, origin - 50 * value.fighters[target].facing,
                           "Source X-only foot alignment uses this rig's own first sample")
            let samples = value.sourceMotionSamples.filter { $0.owner == target }
            XCTAssertEqual(samples.map(\.clip), [Motion.start.clip, Motion.loop.clip])
            XCTAssertEqual(samples.map(\.tick), [Motion.start.endEventTick, 0])
            for _ in 0..<38 { value.step(.neutral, opponent: .neutral) }
            XCTAssertFalse(value.panguPresentation.controls.contains { $0.target == target && $0.kind == .stun })
            XCTAssertEqual(value.fighters[target].weaponPose?.clip, Motion.loop.clip)
            XCTAssertEqual(value.fighters[target].weaponPose?.tick, 38)
            XCTAssertEqual(value.fighters[target].stun, 1, "Original Loop remains Uninterrupt after the duration flag ends")
            for _ in 0..<22 { value.step(.neutral, opponent: .neutral) }
            XCTAssertEqual(value.fighters[target].weaponPose?.clip, Motion.end.clip)
            XCTAssertEqual(value.fighters[target].weaponPose?.tick, 0)
            XCTAssertFalse(value.canUse(.weapon, index: target))
            for _ in 0..<60 { value.step(.neutral, opponent: .neutral) }
            XCTAssertEqual(value.fighters[target].weaponPose?.tick, 60)
            let edge = DuelGame.Input(weaponCommand: .weapon)
            value.step(target == 0 ? edge : .neutral, opponent: target == 1 ? edge : .neutral)
            XCTAssertEqual(value.fighters[target].weaponPose?.clip, value.profiles[target].roles["idle"])
            XCTAssertNil(value.fighters[target].attack, "The recovery tick consumes attack edges")
            XCTAssertEqual(value.fighters[target].stun, 0)
            XCTAssertTrue(value.canUse(.weapon, index: target))
            XCTAssertFalse(value.fighters[caster].weaponPose?.reaction ?? false)
        }
    }

    func testUninterruptStillTakesDamageAndHitStopFreezesTheOriginalSample() throws {
        var value = try fight()
        XCTAssertTrue(DuelPanguFightFixture.until(&value) { $0.panguState(0)?.activeCast == nil })
        let before = value.damageDealt[0]
        value.step(.init(weaponCommand: .weapon), opponent: .neutral)
        XCTAssertTrue(DuelPanguFightFixture.until(&value, limit: 18) { $0.damageDealt[0] > before })
        XCTAssertGreaterThan(value.hitStop, 0)
        let pose = try XCTUnwrap(value.fighters[1].weaponPose)
        XCTAssertTrue([Motion.start.clip, Motion.loop.clip].contains(pose.clip),
                      "An ordinary damage hit must not replace the original full Uninterrupt interval")
        let live = value.panguPresentation.liveTick
        for _ in 0..<value.hitStop {
            value.step(.neutral, opponent: .init(weaponCommand: .weapon))
            XCTAssertEqual(value.fighters[1].weaponPose, pose)
            XCTAssertEqual(value.panguPresentation.liveTick, live)
            XCTAssertTrue(value.sourceMotionSamples.isEmpty)
        }
        value.step(.neutral, opponent: .neutral)
        XCTAssertEqual(value.fighters[1].weaponPose?.tick, pose.tick + 1)
        XCTAssertNil(value.fighters[1].attack)
    }

    func testRoundResetClearsSourceReactionAndUnboundCatalogKeepsExistingFallback() throws {
        let legacy = try fight(originalBinding: false)
        XCTAssertEqual(legacy.fighters[1].weaponPose?.clip, legacy.profiles[1].roles["hit"])
        XCTAssertEqual(legacy.fighters[1].stun, 90)
        var value = try fight(lethal: true)
        XCTAssertTrue(DuelPanguFightFixture.until(&value) { $0.panguState(0)?.activeCast == nil })
        value.step(.init(weaponCommand: .weapon), opponent: .neutral)
        XCTAssertTrue(DuelPanguFightFixture.until(&value, limit: 18) { $0.phase != .fighting })
        XCTAssertTrue(DuelPanguFightFixture.until(&value, limit: 200) { $0.phase == .fighting })
        for _ in 0..<180 { value.step(.neutral, opponent: .neutral) }
        XCTAssertFalse(value.panguPresentation.controls.contains { $0.kind == .stun })
        for fighter in value.fighters {
            XCTAssertFalse(Motion.allCases.contains { $0.clip == fighter.weaponPose?.clip })
            XCTAssertEqual(fighter.stun, 0)
        }
    }

    func testPrivateStagedCatalogAndReleaseKeepProductionIdentityWhenProvided() throws {
        guard let directory = ProcessInfo.processInfo.environment["SOURCE_STUN_PRIVATE_CANDIDATE"] else {
            throw XCTSkip("Set only for the locally assembled private Stun candidate")
        }
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        let catalog = try JSONDecoder().decode(DuelWeaponCatalog.self,
            from: Data(contentsOf: root.appendingPathComponent("SF3_DistinctFighters.json")))
        let release = try JSONDecoder().decode(DuelFighterAssetRelease.self,
            from: Data(contentsOf: root.appendingPathComponent("SF3_FighterRelease.json")))
        try catalog.validate()
        try release.validate(catalog: catalog)
        XCTAssertEqual(release.id, "shared-original-stun-20261115-v1")
        let sun = try XCTUnwrap(catalog.profile(for: .ember)), liu = try XCTUnwrap(catalog.profile(for: .liu))
        XCTAssertEqual(sun.sha256, "9513c85028541fe514f552a5e0d11fd01df277b8cd9f8ddeb832508ff975c699")
        XCTAssertEqual(liu.sha256, "66f8a748efb431bb28bdcd5e4cd91bc2d5d374fd456eb00e843f5d6590a26bfe")
        XCTAssertEqual(sun.clips.count, 68); XCTAssertEqual(liu.clips.count, 62)
        XCTAssertTrue(Motion.matches(profile: sun)); XCTAssertTrue(Motion.matches(profile: liu))
        XCTAssertTrue(DuelTriadRootVictimState.matches(profile: liu))
        XCTAssertEqual(liu.id, "liu_hammers"); XCTAssertFalse(liu.isPangu)
        XCTAssertNil(liu.panguRules); XCTAssertNil(release.panguAudio)
    }
}
