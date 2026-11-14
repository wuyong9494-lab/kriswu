import XCTest
import UIKit
import SceneKit
import Metal
import simd
@testable import ShiftReminder

/// These cases use the independently pinned installed private release. No hash
/// override, generated artwork, injected energy or synthetic gameplay profile
/// may satisfy them. The dedicated private CI rejects every skipped method.
@MainActor
final class DuelTriadInstalledSourceTests: XCTestCase {
    private enum Failure: Error { case notReached(String) }

    private func installed() throws -> DuelWeaponAssets {
        guard let pin = Bundle.main.object(forInfoDictionaryKey: DuelFighterAssetRelease.infoKey) as? String,
              !pin.isEmpty else { throw XCTSkip("This build has no approved source release pin") }
        XCTAssertTrue(DuelFighterAssetRelease.validDigest(pin))
        return try DuelWeaponAssets()
    }
    private func audit(_ records: [DuelNetworkContentRecord], directory: URL) throws {
        XCTAssertFalse(records.isEmpty)
        XCTAssertEqual(Set(records.map(\.path)).count, records.count)
        for record in records {
            let data = try Data(contentsOf: directory.appendingPathComponent(record.path))
            XCTAssertEqual(data.count, record.bytes, record.path)
            XCTAssertEqual(DuelNetworkContentRecord.digest(data), record.sha256, record.path)
        }
    }

    func testInstalledReleaseKeepsOriginalSunIdentityAndDoesNotRelabelLiuAsPangu() throws {
        let assets = try installed(), release = try XCTUnwrap(assets.release)
        XCTAssertEqual(release.definition.schemaVersion, 2)
        let pin = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: DuelFighterAssetRelease.infoKey) as? String)
        XCTAssertEqual(DuelNetworkContentRecord.digest(try Data(contentsOf:
            assets.directory.appendingPathComponent(DuelFighterAssetRelease.fileName))), pin)
        XCTAssertNotEqual(release.definition.catalog.sha256, DuelWeaponAssets.catalogSHA256)
        let sun = try assets.character(for: .ember), liu = try assets.character(for: .liu)
        XCTAssertEqual(sun.profile.id, "sun_triad"); XCTAssertTrue(sun.profile.isTriad)
        XCTAssertEqual(sun.profile.bodyID, "arm__prc_43")
        XCTAssertEqual(sun.profile.weaponID, "wpn__ninjato_01_06")
        XCTAssertNotNil(sun.profile.triadRules?.runtime)
        XCTAssertEqual(sun.profile.triadRules?.level, 6)
        let modelTracks = try XCTUnwrap(sun.profile.triadRules?.runtime?.modelTracks)
        XCTAssertEqual(Set(modelTracks.keys), Set(["roots", "mistWave"]))
        XCTAssertEqual(modelTracks["roots"]?.root.count, 61)
        XCTAssertEqual(modelTracks["mistWave"]?.root.count, 43)
        XCTAssertEqual(modelTracks["roots"]?.hurtCapsules?.first?.radiusMillimeters, 300)
        XCTAssertEqual(modelTracks["mistWave"]?.hurtCapsules?.first?.radiusMillimeters, 1600)
        XCTAssertEqual(sun.profile.triadRules?.ability(.branches)?.attack?.lifetimeTicks, 61)
        XCTAssertEqual(liu.profile.id, "liu_hammers"); XCTAssertFalse(liu.profile.isPangu)
        XCTAssertFalse(liu.profile.isTriad); XCTAssertNil(assets.panguAudio)
        for character in [sun, liu] {
            let profile = character.profile
            let data = try Data(contentsOf: assets.directory.appendingPathComponent(profile.resourceName + ".glb"))
            try DuelFighterAssetReleaseLoader.validateSelfContainedGLB(data)
            XCTAssertEqual(data.count, profile.bytes); XCTAssertEqual(DuelNetworkContentRecord.digest(data), profile.sha256)
            XCTAssertTrue(character.model.hasSkinning)
            XCTAssertTrue(Set(profile.clips.map(\.name)).isSubset(of: Set(character.model.clips.keys)))
            XCTAssertEqual(character.releaseBinding?.characterSHA256, profile.sha256)
            XCTAssertNotNil(character.model.node(named: profile.hero == .ember ? "Sun_Personal_Head" : "Liu_Personal_Head"))
        }
        XCTAssertEqual(Set(sun.profile.clips.map(\.name)).count, sun.profile.clips.count)
        XCTAssertGreaterThanOrEqual(sun.profile.clips.count, 59)
        for ability in DuelTriadRules.Ability.allCases where ability.soul == nil {
            XCTAssertNotNil(sun.profile.clip(role: ability.motionRole))
        }
    }

    func testInstalledEightCompanionsBindTwentySourceRolesAndSixtyHertzTracks() throws {
        let assets = try installed(), summons = try XCTUnwrap(assets.triadSummons)
        let profile = try XCTUnwrap(assets.catalog.profile(for: .ember))
        XCTAssertEqual(summons.profileID, profile.id); XCTAssertEqual(summons.characterSHA256, profile.sha256)
        XCTAssertEqual(summons.models.count, 8); XCTAssertEqual(summons.roles.count, 20)
        XCTAssertEqual(Set(summons.models.keys), Set(DuelTriadRules.SummonMove.allCases.map(\.modelName)))
        for (role, binding) in summons.roles {
            let track = try XCTUnwrap(profile.summonTrack(role: role))
            XCTAssertEqual(binding.motion.clip, track.clip)
            XCTAssertEqual(binding.motion.sourceSHA256, track.sourceSHA256)
            XCTAssertEqual(binding.motion.root, track.root)
            XCTAssertEqual(binding.motion.groundLift, track.groundLift)
            XCTAssertEqual(track.root.count, 2 * (track.frames - 1) + 1)
            let model = try XCTUnwrap(summons.models[binding.model])
            XCTAssertTrue(model.model.hasSkinning)
            XCTAssertNotNil(model.model.clips[binding.motion.clip])
            XCTAssertNotNil(model.model.node(named: "SF3_Actor_Meters"))
        }
        try audit(summons.verifiedFiles, directory: assets.directory)
    }

    func testInstalledSourceEffectsAudioAndMixedTrailsRetainEveryFileIdentity() throws {
        let assets = try installed(), trails = try XCTUnwrap(assets.sourceTrails)
        let audio = try XCTUnwrap(assets.triadAudio), effects = try XCTUnwrap(assets.triadEffects)
        XCTAssertEqual(Set(trails.profiles.map(\.id)), Set(assets.catalog.profiles.map(\.id)))
        let sunTrail = try XCTUnwrap(trails.profiles.first { $0.id == "sun_triad" })
        let liuTrail = try XCTUnwrap(trails.profiles.first { $0.id == "liu_hammers" })
        XCTAssertFalse(try XCTUnwrap(sunTrail.clipWindows).isEmpty)
        XCTAssertNil(liuTrail.clipWindows, "Legacy Liu windows must not be reinterpreted as the source Sun schema")
        XCTAssertTrue(trails.verifiedFiles.contains { $0.path == DuelSourceWeaponTrails.fileName && $0.sha256 == DuelSourceWeaponTrails.sha256 })
        XCTAssertEqual(effects.effects.count, 36)
        XCTAssertEqual(effects.effects.values.reduce(0) { $0 + ($1.historyTrails?.count ?? 0) }, 4)
        XCTAssertEqual(effects.verifiedFiles.filter { $0.path.hasSuffix(".metal") }.count, 41)
        XCTAssertEqual(effects.verifiedFiles.filter { $0.path.hasSuffix(".texture") }.count, 69)
        XCTAssertFalse(effects.bindings.isEmpty); XCTAssertFalse(effects.markers.isEmpty)
        XCTAssertFalse(audio.cues.isEmpty); XCTAssertFalse(audio.markers.isEmpty)
        XCTAssertEqual(audio.characterSHA256, assets.catalog.profile(for: .ember)?.sha256)
        for records in [trails.verifiedFiles, audio.verifiedFiles, effects.verifiedFiles] {
            try audit(records, directory: assets.directory)
        }
        // Validate both actual rigs against their separate trail bindings.
        for hero in [DuelGame.Hero.ember, .liu] { _ = try assets.character(for: hero) }
    }

    func testInstalledNetworkFingerprintIncludesAllOriginalSourceBindings() throws {
        _ = try installed()
        let prepared = try DuelNetworkCompatibilityIdentity.prepare()
        defer { prepared.release() }
        let assets = try XCTUnwrap(prepared.assets), identity = prepared.identity
        XCTAssertTrue(prepared.hasExactResources)
        XCTAssertEqual(identity.compatibility.catalogFingerprint.count, 64)
        let groups = [("weapon-effects/", try XCTUnwrap(assets.sourceTrails).verifiedFiles),
                      ("triad-audio/", try XCTUnwrap(assets.triadAudio).verifiedFiles),
                      ("triad-souls/", try XCTUnwrap(assets.triadSummons).verifiedFiles),
                      ("triad-effects/", try XCTUnwrap(assets.triadEffects).verifiedFiles)]
        for (prefix, records) in groups {
            for file in records {
                let matches = identity.verifiedFiles.filter { $0.path == prefix + file.path }
                XCTAssertEqual(matches.count, 1); XCTAssertEqual(matches.first?.bytes, file.bytes)
                XCTAssertEqual(matches.first?.sha256, file.sha256)
            }
        }
        XCTAssertFalse(identity.verifiedFiles.contains { $0.path.hasPrefix("pangu-audio/") })
        XCTAssertEqual(identity.verifiedFiles.filter { $0.path.hasPrefix("asset-release/") }.count, 1)
        XCTAssertEqual(prepared.sourceEffects?.playedSounds, 0)
    }

    func testInstalledWorldRendersOriginalSkillsAndStopsWithoutAdvancingOnRedraw() throws {
        _ = try installed()
        let clocks = DuelWorldView.activeClocks
        let state = DuelSession(.init(hero: .ember, difficulty: .learning, mode: .practice, originalWeapons: true))
        let world = DuelWorldView(session: state)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 956, height: 440))
        window.rootViewController = UIViewController(); window.makeKeyAndVisible()
        world.frame = window.bounds; window.rootViewController?.view.addSubview(world)
        world.setNeedsLayout(); world.layoutIfNeeded()
        var captures: [[String: Any]] = []
        let assets = try XCTUnwrap(state.weaponAssets, world.triadPreparationFailure ?? "Missing installed source assets")
        let sun = try XCTUnwrap(assets.catalog.profile(for: .ember))
        let releaseSHA = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: DuelFighterAssetRelease.infoKey) as? String)
        defer {
            let report: [String: Any] = ["characterSHA256": sun.sha256, "releaseSHA256": releaseSHA,
                "captures": captures, "sourceQuality": "high", "sourceMirrorPose": false,
                "triadPreparationFailure": world.triadPreparationFailure ?? "",
                "conditionalNotExecuted": ["h17_ninjatoFire_trail_2_R requires original mirrored owner pose"],
                "sourcePrograms": assets.triadEffects?.verifiedFiles.filter { $0.path.hasSuffix(".metal") }.map {
                    ["file": $0.path, "bytes": $0.bytes, "sha256": $0.sha256] as [String: Any]
                } ?? [],
                "physicalDevice": false, "pixelParityWithOriginalClient": "not yet verified"]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "sun-source-capture-report"; attachment.lifetime = .keepAlways; add(attachment)
            }
            world.shutdown(); state.shutdown(); window.isHidden = true
        }
        XCTAssertNil(state.loadError); XCTAssertNotNil(world.stageAsset)
        XCTAssertEqual(Set(world.weaponAssets.keys), Set([DuelGame.Hero.ember, .liu]))
        let surface = try XCTUnwrap(world.triadRenderSurface, world.triadPreparationFailure ?? "Missing controlled source surface")
        let renderer = try XCTUnwrap(world.triadMetalRenderer, world.triadPreparationFailure ?? "Missing source Metal packets")
        XCTAssertFalse(world.rendersContinuously); XCTAssertFalse(world.isPlaying)
        XCTAssertTrue(surface.sceneRenderer.scene === world.scene)
        XCTAssertTrue(surface.sceneRenderer.pointOfView === world.pointOfView)
        XCTAssertEqual(surface.colorPixelFormat, .bgra8Unorm)
        let imageSize = CGSize(width: 956, height: 440)
        // All input and fixed-step operations remain synchronous on MainActor;
        // no wall-clock wait or display-link callback advances these scenarios.
        func step(_ count: Int = 1) throws {
            for _ in 0..<count { state.advance() }
            guard state.loadError == nil else { throw Failure.notReached("Source runtime rejected a fixed step") }
        }
        func wait(_ description: String, limit: Int, until predicate: () -> Bool) throws {
            for _ in 0..<limit {
                if predicate() { return }
                try step()
            }
            guard predicate() else { throw Failure.notReached(description) }
        }
        func tap(_ button: DuelWeaponInput.Action, x: Int = 0, y: Int = 0) throws {
            state.weaponDirection(x: x, y: y); state.weaponAction(button, down: true)
            state.weaponAction(button, down: false); state.weaponDirection(x: 0, y: 0)
            try step()
        }
        func capture(_ label: String, effects: Set<String> = [], summon: String? = nil) throws {
            let game = state.game, animation = state.animationTick, sounds = world.sourceEffects?.playedSounds
            world.drawState(); world.drawState()
            XCTAssertEqual(state.game, game); XCTAssertEqual(state.animationTick, animation)
            XCTAssertEqual(world.sourceEffects?.playedSounds, sounds)
            XCTAssertNil(state.loadError); XCTAssertNil(renderer.lastFailure); XCTAssertNil(surface.lastFailure)
            let fight = try XCTUnwrap(state.game.weaponFight)
            XCTAssertTrue(effects.isSubset(of: Set(world.activeSourceEffectIDs)), "Missing actual original effect at capture: \(label)")
            if let summon { XCTAssertTrue(fight.triadPresentation.summons.contains { $0.motionRole == summon }) }
            let samples = world.antialiasingMode == .none ? 1 : 2
            let image = try surface.captureFrame(tick: fight.triadPresentation.liveTick, pixelSize: imageSize, samples: samples)
            let png = try XCTUnwrap(image.pngData())
            XCTAssertEqual(image.cgImage?.width, 956); XCTAssertEqual(image.cgImage?.height, 440)
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = label; attachment.lifetime = .keepAlways; add(attachment)
            captures.append(["label": label, "frame": fight.frame, "liveTick": fight.triadPresentation.liveTick,
                "ownerClip": fight.fighters[0].weaponPose?.clip ?? "", "ownerPhase": fight.fighters[0].weaponPose?.phase ?? 0,
                "packetCount": renderer.submittedPacketCount, "sourceEffects": world.activeSourceEffectIDs,
                "summonRoles": fight.triadPresentation.summons.map(\.motionRole),
                "mist": fight.triadState(0)?.mist ?? -1, "notches": fight.triadState(0)?.notches ?? -1,
                "requestedSamples": samples, "actualSamples": DuelTriadRenderSurface.format(samples: samples).samples,
                "pngSHA256": DuelNetworkContentRecord.digest(png)])
        }
        try capture("sun-source-idle")
        state.weaponAction(.ranged, down: true)
        for (animation, tick, label, effects) in [
            (DuelTriadState.OwnerAnimation.mistOnslaught1, 28, "sun-source-wave-1", ["h17_ninjatoFire_trail_1_L(weapon_l)"]),
            (.mistOnslaught2, 78, "sun-source-wave-2", ["h17_ninjatoFire_trail_1_L(weapon_l)"]),
            (.mistOnslaught3, 118, "sun-source-wave-3", ["h17_ninjatoFire_trail_3_L(weapon_l)", "h17_ninjatoFire_trail_3_R(weapon_r)"])
        ] {
            try wait("Original chained wave capture \(label)", limit: 240) {
                let motion = state.game.weaponFight?.triadState(0)?.ownerMotion
                return motion?.animation == animation && (motion?.tick ?? -1) >= tick
            }
            try capture(label, effects: Set(effects))
        }
        state.weaponAction(.ranged, down: false)
        try wait("Original branch readiness", limit: 360) { state.game.weaponFight?.canUseTriad(.branches, index: 0) == true }
        try tap(.shadow)
        try wait("Original root model birth", limit: 160) {
            let motion = state.game.weaponFight?.triadState(0)?.ownerMotion
            return motion?.animation == .branchesStart && (motion?.tick ?? -1) >= 48
        }
        try capture("sun-source-roots", effects: ["h17_trees_attack_startIdle"])
        try wait("Root owner released for movement", limit: 300) { state.game.weaponFight?.triadState(0)?.movementLocked == false }
        // Earn source Mist from a real hit on a suppressed opponent. A missed
        // reach is retried at a shorter measured distance, never by setting HP.
        for targetGap in [1000, 650] {
            state.weaponDirection(x: state.game.fighters[0].facing, y: 0)
            try wait("Reach the practice opponent", limit: 900) {
                abs(state.game.fighters[1].x - state.game.fighters[0].x) <= targetGap
            }
            state.weaponDirection(x: 0, y: 0)
            let hits = state.game.landedHits[0]
            try tap(.weapon); try step(180)
            if state.game.landedHits[0] > hits { break }
        }
        try wait("Natural Mist regeneration for Legion", limit: 900) {
            state.game.weaponFight?.canUseTriad(.legionary, index: 0) == true
        }
        try tap(.shadow, y: -1)
        try wait("Original Legion model", limit: 60) {
            state.game.weaponFight?.triadPresentation.summons.contains { $0.motionRole == DuelTriadRules.SummonMove.legionSword.role && $0.motionTick >= 12 } == true
        }
        try capture("sun-source-legion", summon: DuelTriadRules.SummonMove.legionSword.role)
        // L6 Forest Rain's real appearances award Notches. The source wall
        // gates decide which bowmen can appear; at most six bounded cycles.
        for _ in 0..<6 {
            if (state.game.weaponFight?.triadState(0)?.notches ?? 0) >= 18 { break }
            try wait("Next real branch cooldown", limit: 1200) { state.game.weaponFight?.canUseTriad(.branches, index: 0) == true }
            try tap(.shadow); try step(320)
        }
        try wait("Naturally earned Crying Dance", limit: 300) { state.game.weaponFight?.canUseTriad(.cryingDance, index: 0) == true }
        try tap(.ranged, y: -1)
        try wait("Original Ninjato soul model", limit: 60) {
            state.game.weaponFight?.triadPresentation.summons.contains { $0.motionRole == DuelTriadRules.SummonMove.danceNinjato.role && $0.motionTick >= 10 } == true
        }
        try capture("sun-source-ninjato", summon: DuelTriadRules.SummonMove.danceNinjato.role)
        XCTAssertEqual(captures.count, 7)
        let frozen = state.game; state.pause()
        let submitted = surface.submittedFrames, sounds = world.sourceEffects?.playedSounds
        try step(3); world.drawState(); world.drawState()
        XCTAssertEqual(state.game, frozen); XCTAssertEqual(surface.submittedFrames, submitted)
        XCTAssertEqual(world.sourceEffects?.playedSounds, sounds)
        world.shutdown(); state.shutdown()
        XCTAssertNil(world.scene); XCTAssertNil(world.triadRenderSurface)
        XCTAssertNil(world.triadMetalRenderer); XCTAssertEqual(renderer.submittedPacketCount, 0)
        XCTAssertEqual(DuelWorldView.activeClocks, clocks)
    }
}
