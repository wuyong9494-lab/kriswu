import Foundation
import XCTest
@testable import ShiftCore

final class DuelErlangSourceBindingTests: XCTestCase {
    private func actualProfile() throws -> DuelWeaponProfile {
        guard let path = ProcessInfo.processInfo.environment["ERLANG_RUNTIME_PROFILE"] else {
            throw XCTSkip("Exact private D15 profile is not staged for this source acceptance check")
        }
        return try JSONDecoder().decode(DuelWeaponProfile.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }
    private func actualCatalog() throws -> DuelWeaponCatalog {
        guard let path = ProcessInfo.processInfo.environment["ERLANG_OPPONENT_CATALOG"] else {
            throw XCTSkip("Exact private opponent catalog is not staged")
        }
        let existing = try JSONDecoder().decode(DuelWeaponCatalog.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        return .init(schemaVersion: existing.schemaVersion, previewFramesPerSecond: existing.previewFramesPerSecond,
                     profiles: [try actualProfile(), try XCTUnwrap(existing.profile(for: .ember))])
    }
    func testActualActorControlsAndCompanionDecodeAgainstRealCapsules() throws {
        let catalog = try actualCatalog()
        XCTAssertNoThrow(try catalog.validate())
        let wu = try XCTUnwrap(catalog.profile(for: .wuYong)), rules = try XCTUnwrap(wu.erlangRules)
        XCTAssertEqual(rules.maximumHealth, 2000)
        XCTAssertEqual(rules.normalizedWeaponPower, 1000)
        XCTAssertEqual(rules.normalizedMagicPower, 1000)
        XCTAssertEqual(rules.controls?.count, 106)
        let dog = try XCTUnwrap(wu.summonTrack(role: "erlangSummon_hound"))
        XCTAssertEqual(dog.sourceEndEventTick, 110)
        XCTAssertEqual(dog.root.count, 119)
        XCTAssertEqual(dog.collisionEdges?.count, 6)
        let attack = try XCTUnwrap(rules.attacks.first { $0.ability == .hound })
        XCTAssertEqual(attack.startTick, 22); XCTAssertEqual(attack.endTick, 67)
        XCTAssertEqual(rules.damage(for: attack), 150)
        XCTAssertEqual(rules.releases.first { $0.ability == .hound }?.anchor, "pelvis.x")
    }
    func testActualAxeAndEndEventsKeepSourceClockSeparateFromSamples() throws {
        let wu = try actualProfile(), rules = try XCTUnwrap(wu.erlangRules)
        let attack = try XCTUnwrap(rules.attacks.first { $0.ability == .axe })
        XCTAssertEqual(attack.startTick, 64); XCTAssertEqual(attack.endTick, 73)
        XCTAssertEqual(attack.parts, ["Spear_Attacking_Edge_l", "Spear_Attacking_Edge_r", "Hand_left", "Forearm_left"])
        XCTAssertEqual(rules.damage(for: attack), 800, "BaseDamage .8 uses normalized power 1000, not HP 2000")
        XCTAssertTrue(attack.hitTags?.contains("Hit_D15_Avatara_Light_Ability") == true)
        let earth = try XCTUnwrap(wu.clip(role: "erlangEarthshaker"))
        XCTAssertEqual(earth.frames, 111); XCTAssertEqual(earth.ticks, 110)
        XCTAssertEqual(earth.sourceEndEventTick, 106)
        let transform = try XCTUnwrap(wu.clip(role: "erlangTransform"))
        XCTAssertEqual(transform.ticks, 168); XCTAssertEqual(transform.sourceEndEventTick, 160)
        XCTAssertEqual(transform.tracks.toeL?.count, 169)
        XCTAssertEqual(transform.tracks.toeR?.count, 169)
        XCTAssertTrue(rules.contains(.uninterrupt, role: "erlangHound", tick: 73))
        XCTAssertFalse(rules.contains(.uninterrupt, role: "erlangHound", tick: 74))
    }
    func testActualHoundReleaseUsesPelvisAndEndsBeforeTransitionTail() throws {
        let catalog = try actualCatalog()
        var enemy = DuelGame.Fighter(hero: .ember, x: 9000, facing: -1)
        enemy.invulnerable = 10_000 // Isolate the authored source clock from contact hit-stop.
        var fight = try XCTUnwrap(DuelWeaponFight(fighters: [.init(hero: .wuYong, x: 3000, facing: 1), enemy],
            mode: .practice, difficulty: .learning, catalog: catalog, seed: 42))
        for _ in 0..<1000 where fight.sourceIntroActive { fight.step(.neutral, opponent: .neutral) }
        XCTAssertTrue(fight.canUseErlang(.hound, index: 0))
        fight.step(.init(taps: .skill1), opponent: .neutral)
        for _ in 0..<7 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertTrue(fight.erlangModels.isEmpty)
        fight.step(.neutral, opponent: .neutral)
        let model = try XCTUnwrap(fight.erlangModels.first)
        XCTAssertEqual(fight.erlangModels.count, 1)
        XCTAssertEqual(fight.erlangState(0)?.cast?.tick, 8)
        let clip = try XCTUnwrap(catalog.profile(for: .wuYong)?.clip(role: "erlangHound"))
        let pelvis = try XCTUnwrap(clip.tracks.pelvis)
        let expectedX = Double(fight.fighters[0].x) / 1000 + clip.tracks.sample(pelvis, phase: clip.phase(at: 8)).x
        XCTAssertEqual(model.origin.x, expectedX, accuracy: 0.000001)
        XCTAssertEqual(model.origin.y, Double(fight.fighters[0].y) / 1000, accuracy: 0.000001)
        for _ in 0..<110 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.erlangModels.first?.id, model.id, "Retain the source terminal sample")
        fight.step(.neutral, opponent: .neutral)
        XCTAssertTrue(fight.erlangModels.isEmpty, "The final eight transition-tail samples cannot extend model life")
    }
    func testSourceMultipliersUseOneStackClockAndOnlyTaggedLightAbility() {
        var state = DuelErlangFightState(seed: 7)
        for _ in 0..<60 { state.advance() }
        XCTAssertTrue(state.start(.meditate, duration: 34, direction: 1, x: 0))
        state.transition(role: "erlangMeditationLoop", duration: 136)
        for _ in 0..<3 { state.advance() }
        XCTAssertEqual(state.meditationStacks, 2)
        state.interrupt()
        state.acceptedPhysicalContact(kind: .unarmed, imperialSpear: false, generated: false, targetHasDogDebuff: true)
        XCTAssertEqual(state.holiness, 1)
        XCTAssertEqual(state.outgoingDamage(1000, lightAbility: false), 1024)
        XCTAssertEqual(state.outgoingDamage(1000, lightAbility: true), 1046)
        for _ in 0..<480 { state.advance() }
        XCTAssertEqual(state.holiness, 0)
        XCTAssertEqual(state.meditationStacks, 2)
        for _ in 0..<120 { state.advance() }
        XCTAssertEqual(state.meditationStacks, 0)
    }
    func testActualProfileRejectsTruncatedToeAndEndEventOutsideSourceTimeline() throws {
        let original = try actualCatalog()
        let data = try JSONEncoder().encode(original.profiles[0])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var clips = try XCTUnwrap(object["clips"] as? [[String: Any]])
        let index = try XCTUnwrap(clips.firstIndex { ($0["name"] as? String) == original.profiles[0].roles["erlangTransform"] })
        let initial = clips[index]
        var tracks = try XCTUnwrap(initial["tracks"] as? [String: Any])
        var toes = try XCTUnwrap(tracks["toeL"] as? [Any]); toes.removeLast()
        tracks["toeL"] = toes; clips[index]["tracks"] = tracks; object["clips"] = clips
        func candidate(_ object: [String: Any]) throws -> DuelWeaponCatalog {
            let profile = try JSONDecoder().decode(DuelWeaponProfile.self, from: JSONSerialization.data(withJSONObject: object))
            return .init(schemaVersion: 1, previewFramesPerSecond: 30, profiles: [profile, original.profiles[1]])
        }
        XCTAssertThrowsError(try candidate(object).validate())
        clips[index] = initial
        clips[index]["sourceEndEventTick"] = 169
        object["clips"] = clips
        XCTAssertThrowsError(try candidate(object).validate())
    }
    func testActualTransformOutRetainsOneSourcePoseAndZeroEndEvent() throws {
        let catalog = try actualCatalog(), profile = catalog.profiles[0]
        let clip = try XCTUnwrap(profile.clip(role: DuelErlangTransformOutMotion.role))
        XCTAssertNoThrow(try catalog.validate())
        XCTAssertTrue(DuelErlangTransformOutMotion.matches(clip: clip, profile: profile))
        XCTAssertEqual(clip.frames, 1); XCTAssertEqual(clip.ticks, 0)
        XCTAssertEqual(clip.sourceEndEventTick, 0)
        XCTAssertEqual(clip.tracks.root.count, 1); XCTAssertEqual(clip.tracks.head?.count, 1)
        for tick in [Int.min, 0, 1, Int.max] {
            XCTAssertEqual(clip.phase(at: tick), 0)
            XCTAssertTrue(clip.phase(at: tick).isFinite)
        }
        XCTAssertEqual(clip.tick(atSourceFrame: 0), 0)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        var clips = try XCTUnwrap(object["clips"] as? [[String: Any]])
        let index = try XCTUnwrap(clips.firstIndex { ($0["name"] as? String) == clip.name })
        let original = clips[index]
        for (key, value) in [("sha256", String(repeating: "a", count: 64) as Any),
                             ("frames", 2 as Any), ("playbackTicks", 1 as Any),
                             ("sourceEndEventTick", 1 as Any)] {
            clips[index] = original; clips[index][key] = value; object["clips"] = clips
            let altered = try JSONDecoder().decode(DuelWeaponProfile.self, from: JSONSerialization.data(withJSONObject: object))
            let candidate = DuelWeaponCatalog(schemaVersion: 1, previewFramesPerSecond: 30,
                profiles: [altered, catalog.profiles[1]])
            XCTAssertThrowsError(try candidate.validate(), "The one-frame exception must remain source-specific: \(key)")
        }
    }
    func testActualWuVictimCapabilitiesKeepSharedStunRootAndHypnosisSeparate() throws {
        let catalog = try actualCatalog(), profile = catalog.profiles[0]
        try catalog.validate()
        XCTAssertTrue(DuelSourceStunMotion.matches(profile: profile))
        XCTAssertTrue(DuelTriadRootVictimState.matches(profile: profile))
        var retained = Set<String>()
        for motion in DuelSourceStunMotion.allCases {
            let clip = try XCTUnwrap(profile.clip(role: motion.role))
            XCTAssertEqual(clip.sourceEndEventTick, motion.endEventTick)
            XCTAssertEqual(clip.tracks.head?.count, motion.lastSampleTick + 1)
            XCTAssertEqual(clip.tracks.hurtCapsules?.count, 15)
            XCTAssertTrue(retained.insert(clip.name).inserted)
        }
        for motion in DuelTriadRootVictimState.Motion.allCases {
            let clip = try XCTUnwrap(profile.clip(named: motion.clip))
            XCTAssertEqual(clip.sourceEndEventTick, motion.endEventTick)
            XCTAssertEqual(clip.tracks.head?.count, motion.lastSampleTick + 1)
            XCTAssertEqual(clip.tracks.hurtCapsules?.count, 15)
            XCTAssertTrue(retained.insert(clip.name).inserted)
        }
        for (role, name) in [("erlangHypnosisIn", "h17_trans_start"),
                             ("erlangHypnosisLoop", "h17_trans_loop"),
                             ("erlangHypnosisOut", "h17_trans_end")] {
            XCTAssertEqual(profile.roles[role], name)
            XCTAssertNotNil(profile.clip(named: name))
            XCTAssertTrue(retained.insert(name).inserted)
        }
        XCTAssertEqual(retained.count, 9, "Different source victim events must retain their own motions")
        XCTAssertEqual(profile.clips.count, 62)
        XCTAssertTrue(profile.isErlang)
        XCTAssertFalse(profile.isPangu)
    }
    func testActualHoundHorizontalSourceMotionReachesDistantTargetInEitherDirection() throws {
        let catalog = try actualCatalog()
        // The real dog local capsules remain within roughly one metre. Only
        // its authenticated five-metre root motion can reach this target.
        for direction in [1, -1] {
            let ownerX = direction == 1 ? 3000 : 9000
            let targetX = ownerX + direction * 3500
            var fight = try XCTUnwrap(DuelWeaponFight(fighters: [
                .init(hero: .wuYong, x: ownerX, facing: direction),
                .init(hero: .ember, x: targetX, facing: -direction)],
                mode: .practice, difficulty: .learning, catalog: catalog, seed: 42))
            for _ in 0..<1000 where fight.sourceIntroActive { fight.step(.neutral, opponent: .neutral) }
            fight.step(.init(taps: .skill1), opponent: .neutral)
            for _ in 0..<100 { fight.step(.neutral, opponent: .neutral) }
            XCTAssertEqual(fight.landedHits[0], 1, "The source root must move the collision along with the visible dog")
            XCTAssertGreaterThan(fight.damageDealt[0], 0)
        }
    }
}
