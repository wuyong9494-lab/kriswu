import XCTest
import SceneKit
import UIKit
import Metal
import simd
@testable import ShiftReminder

/// Actual private catalog + normal game/session/world path. These assertions
/// check the app adapter's physical contact and presentation, not source-game
/// damage constants, recovered event timing, or the undocumented source FPS.
@MainActor
final class DuelWeaponGameplayTests: XCTestCase {
    func testOriginalManualGuardReleasesAcrossPauseRestartAndControlReplacement() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            let state = DuelSession(.init(hero: hero, difficulty: .learning,
                                          mode: .practice, originalWeapons: true))
            defer { state.shutdown() }
            XCTAssertNil(state.loadError, "This selected test requires the verified original character pack")
            XCTAssertNotNil(state.game.weaponFight)
            let binding = DuelWeaponControls(session: state)
            let old = DuelSourceControlsView(images: [:]), current = DuelSourceControlsView(images: [:])
            defer { old.shutdown(); current.shutdown() }
            for view in [old, current] {
                view.frame = CGRect(x: 0, y: 0, width: 956, height: 440)
                view.setNeedsLayout(); view.layoutIfNeeded()
            }
            func hold(_ view: DuelSourceControlsView, _ id: String) {
                let frame = view.layoutSnapshot.manualGuard
                view.beginPointers([.init(id: id, location: CGPoint(x: frame.midX, y: frame.midY))])
            }
            XCTAssertTrue(binding.bind(old))
            let staleGuard = old.onGuard
            XCTAssertFalse(state.consumeLocalInput().guardHeld)
            hold(old, "old")
            XCTAssertTrue(state.consumeLocalInput().guardHeld)
            XCTAssertTrue(binding.bind(current))
            XCTAssertNil(old.onGuard)
            XCTAssertFalse(state.consumeLocalInput().guardHeld)
            hold(current, "current")
            staleGuard?(false)
            old.didMoveToWindow()
            XCTAssertTrue(state.consumeLocalInput().guardHeld, "Retired controls must not clear the current owner's defense")
            state.pause()
            staleGuard?(true)
            state.weaponGuard(true)
            XCTAssertFalse(state.consumeLocalInput().guardHeld)
            state.resume()
            XCTAssertFalse(state.consumeLocalInput().guardHeld)
            hold(current, "restart")
            XCTAssertTrue(state.consumeLocalInput().guardHeld)
            state.restart()
            XCTAssertEqual(state.localFighter.hero, hero)
            XCTAssertFalse(state.consumeLocalInput().guardHeld)
            current.endPointers(["current", "restart"])
            XCTAssertFalse(state.consumeLocalInput().guardHeld)
            let guardButton = try XCTUnwrap(current.subviews.first {
                $0.accessibilityIdentifier == "duel.control.guard"
            } as? UIButton)
            XCTAssertEqual(guardButton.accessibilityValue, "未按住")
        }
    }

    func testActualSourceWeaponHeavyAndKickHitInBothDirectionsWithoutCrossingBodies() throws {
        let assets = try DuelWeaponAssets()
        for hero in [DuelGame.Hero.ember, .liu] {
            let other: DuelGame.Hero = hero == .ember ? .liu : .ember
            for direction in [1, -1] {
                for command in [DuelWeaponCommand.weapon, .heavy, .kick] {
                    let fighters = [DuelGame.Fighter(hero: hero, x: 5000 - direction * 600, facing: direction),
                                    DuelGame.Fighter(hero: other, x: 5000 + direction * 600, facing: -direction)]
                    var fight = try XCTUnwrap(DuelWeaponFight(fighters: fighters, mode: .practice,
                        difficulty: .learning, catalog: assets.catalog, seed: 7))
                    let source = try XCTUnwrap(fight.profiles[0].clip(command: command))
                    fight.step(.init(weaponCommand: command), opponent: .neutral)
                    XCTAssertEqual(fight.fighters[0].weaponPose?.clip, source.name)
                    var contact: DuelWeaponFight.Contact?
                    var sampledLastSourceFrame = false
                    for _ in 0..<(source.ticks + 100) {
                        fight.step(.neutral, opponent: .neutral)
                        XCTAssertGreaterThanOrEqual((fight.fighters[1].x - fight.fighters[0].x) * direction,
                                                    DuelGame.bodyWidth, "\(hero)/\(command) crossed grounded bodies")
                        if let event = fight.contacts.first(where: { $0.attacker == 0 }) { contact = event }
                        if let pose = fight.fighters[0].weaponPose, pose.clip == source.name, pose.tick == source.ticks {
                            sampledLastSourceFrame = true
                        }
                    }
                    XCTAssertEqual(contact?.kind, .hit, "Real source geometry must contact: \(hero)/\(command)/\(direction)")
                    XCTAssertEqual(contact?.direction, direction)
                    XCTAssertGreaterThan(fight.landedHits[0], 0)
                    XCTAssertGreaterThan(fight.damageDealt[0], 0)
                    XCTAssertLessThan(fight.fighters[1].health, 1000)
                    XCTAssertTrue(sampledLastSourceFrame, "A complete source clip includes its last frame")
                }
            }
        }
    }

    func testProvisionalShadowUsesSafeSourceBodyAndCompletesWithoutTeleportTracks() throws {
        let assets = try DuelWeaponAssets()
        for hero in [DuelGame.Hero.ember, .liu] {
            let other: DuelGame.Hero = hero == .ember ? .liu : .ember
            let fighters = [DuelGame.Fighter(hero: hero, x: 2000, facing: 1),
                            DuelGame.Fighter(hero: other, x: 8000, facing: -1)]
            var fight = try XCTUnwrap(DuelWeaponFight(fighters: fighters, mode: .practice,
                difficulty: .learning, catalog: assets.catalog, seed: 7))
            let sourceShadow = try XCTUnwrap(fight.profiles[0].clip(role: "shadow"))
            let safeBody = try XCTUnwrap(fight.profiles[0].clip(command: .heavy))
            XCTAssertTrue(fight.canUse(.shadow, index: 0))
            fight.step(.init(weaponCommand: .shadow), opponent: .neutral)
            XCTAssertEqual(fight.fighters[0].weaponPose?.clip, safeBody.name)
            XCTAssertNotEqual(fight.fighters[0].weaponPose?.clip, sourceShadow.name)
            XCTAssertLessThan(fight.fighters[0].energy, 100)
            for _ in 0..<200 {
                let previous = fight.fighters[0].x
                fight.step(.neutral, opponent: .neutral)
                XCTAssertLessThanOrEqual(abs(fight.fighters[0].x - previous), 150)
                if fight.shadowVisual(0) != nil {
                    XCTAssertEqual(fight.fighters[0].weaponPose?.clip, safeBody.name)
                }
            }
            XCTAssertNil(fight.shadowVisual(0))
            XCTAssertGreaterThan(fight.shadowCooldownRemaining(0), 0)
            XCTAssertFalse(fight.canUse(.shadow, index: 0))
        }
    }

    func testRealOpticalFitRetainsLensOnInvalidSkinAndRecovers() throws {
        let state = DuelSession(.init(hero: .ember, difficulty: .learning,
                                      mode: .practice, originalWeapons: true))
        let view = DuelWorldView(session: state)
        defer { view.shutdown(); state.shutdown() }
        state.pause() // Mounted layout must not advance the real source pose.
        XCTAssertNil(state.loadError, "The verified source characters and stage are required")
        XCTAssertNotNil(state.game.weaponFight)
        XCTAssertNotNil(view.stageAsset)
        XCTAssertFalse(view.usesSyntheticPresentationResources)
        XCTAssertEqual(Set(view.weaponAssets.keys), Set([DuelGame.Hero.ember, .liu]))
        let assets = try XCTUnwrap(state.weaponAssets)
        let scene = try XCTUnwrap(view.scene)
        let camera = try XCTUnwrap(view.pointOfView?.camera)
        XCTAssertFalse(camera.usesOrthographicProjection)
        let controls = DuelSourceControlsView(assetDirectory: assets.directory)
        XCTAssertTrue(controls.sourceArtAvailable)
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 956, height: 440))
        window.rootViewController = host
        window.isHidden = false
        defer {
            controls.shutdown()
            window.isHidden = true; window.rootViewController = nil
        }
        host.view.addSubview(view); host.view.addSubview(controls)
        XCTAssertTrue(DuelWeaponControls(session: state).bind(controls))
        XCTAssertTrue(view.window === window && controls.window === window)
        func viewport(_ size: CGSize) {
            window.frame = CGRect(origin: .zero, size: size)
            host.view.frame = window.bounds
            view.frame = host.view.bounds; controls.frame = host.view.bounds
            controls.setNeedsLayout(); controls.layoutIfNeeded()
        }
        let landscape = CGSize(width: 956, height: 440)
        viewport(landscape); view.layoutSubviews()
        XCTAssertNil(view.opticalFramingFailure)
        let landscapeFOV = camera.fieldOfView
        let frame = state.game.frame, tracking = view.combatCamera
        for (index, fighter) in state.game.fighters.enumerated() {
            let asset = try XCTUnwrap(view.weaponAssets[fighter.hero])
            let actor = try XCTUnwrap(scene.rootNode.childNode(withName: "duel.actor.\(index)", recursively: false))
            let equipped = try XCTUnwrap(actor.childNode(
                withName: "duel.equipped.\(asset.profile.id)", recursively: false))
            var visibleMesh: SCNNode?
            equipped.enumerateChildNodes { node, stop in
                guard node.geometry != nil, node.skinner != nil else { return }
                var ancestor: SCNNode? = node
                while let current = ancestor {
                    if current.isHidden || current.opacity == 0 { return }
                    ancestor = current.parent
                }
                visibleMesh = node; stop.pointee = true
            }
            let holder = try XCTUnwrap(visibleMesh, "Inject failure in an actually displayed source mesh")
            let skin = try XCTUnwrap(holder.skinner)
            defer { holder.skinner = skin }

            // Obtain a wider SUCCESSFUL projection from the same real pose.
            // Rotation changes only the viewport, not geometry or private camera state.
            viewport(CGSize(width: 390, height: 844)); view.layoutSubviews()
            XCTAssertNil(view.opticalFramingFailure)
            let portraitFOV = camera.fieldOfView
            XCTAssertGreaterThan(portraitFOV, landscapeFOV + 1)
            holder.skinner = nil // The bounds cache still owns this exact source skinner.
            viewport(landscape)
            let target = try XCTUnwrap(controls.layoutSnapshot.actions[.weapon])
            state.updateCharacterOcclusion([controls.convert(target, to: view)], from: view)
            XCTAssertEqual(controls.obscuredActions, [.weapon], "Start with observable stale artwork overlap")
            for _ in 0..<3 {
                view.layoutSubviews()
                XCTAssertEqual(view.opticalFramingFailure, .invalidSkin)
                XCTAssertEqual(camera.fieldOfView, portraitFOV, accuracy: 0.0001,
                               "Unknown source geometry must retain the last successful wider lens")
                XCTAssertTrue(controls.obscuredActions.isEmpty,
                              "Failed fitting must clear previously projected artwork overlap")
            }
            let failedFOV = camera.fieldOfView
            holder.skinner = skin
            view.layoutSubviews()
            XCTAssertTrue(holder.skinner === skin)
            XCTAssertNil(view.opticalFramingFailure, "Restoring the same real skinner must recover fitting")
            XCTAssertEqual(camera.fieldOfView, landscapeFOV, accuracy: 0.0001)
            XCTAssertEqual(state.game.frame, frame)
            XCTAssertEqual(view.combatCamera, tracking)
            let evidence = XCTAttachment(string:
                "evidenceClass=real-source-resource-with-injected-skin-failure hero=\(fighter.hero.rawValue) " +
                "profileSHA256=\(asset.profile.sha256) frame=\(frame) " +
                "landscapeFOV=\(landscapeFOV) portraitFOV=\(portraitFOV) " +
                "failedFOV=\(failedFOV) restoredFOV=\(camera.fieldOfView)")
            evidence.name = "real-optical-fit-failure-recovery-\(fighter.hero.rawValue)"
            evidence.lifetime = .keepAlways; add(evidence)
        }
    }

    func testEquippedSessionsShowRealHitsPauseRestartAndReleaseTheirScenes() throws {
        let baselineClocks = DuelWorldView.activeClocks
        for hero in [DuelGame.Hero.ember, .liu] {
            weak var releasedAssets: DuelWeaponAssets?
            weak var releasedScene: SCNScene?
            weak var releasedHead: SCNNode?
            weak var releasedEffects: DuelSourceEffects?
            try autoreleasepool {
                var session: DuelSession? = DuelSession(.init(hero: hero, difficulty: .learning,
                                                              mode: .practice, originalWeapons: true))
                var world: DuelWorldView? = DuelWorldView(session: try XCTUnwrap(session))
                let state = try XCTUnwrap(session), view = try XCTUnwrap(world)
                defer { view.shutdown(); state.shutdown() }
                XCTAssertNil(state.loadError)
                XCTAssertNotNil(state.game.weaponFight)
                XCTAssertNotNil(view.stageAsset)
                XCTAssertEqual(Set(view.weaponAssets.keys), Set([DuelGame.Hero.ember, .liu]))
                XCTAssertTrue(view.originalAssets.isEmpty, "The default equipped fight must not load the previous shared body")
                XCTAssertNil(view.characterAsset)
                XCTAssertEqual(Set(view.weaponAssets.values.map { $0.profile.bodyID }).count, 2)
                XCTAssertEqual(Set(view.weaponAssets.values.map { $0.profile.weaponID }).count, 2)
                let scene = try XCTUnwrap(view.scene), effects = try XCTUnwrap(view.sourceEffects)
                releasedAssets = state.weaponAssets; releasedScene = scene; releasedEffects = effects
                let identity = hero == .ember ? "Sun" : "Liu"
                releasedHead = scene.rootNode.childNode(withName: identity + "_Personal_Head", recursively: true)
                XCTAssertNotNil(releasedHead)
                XCTAssertNil(scene.rootNode.childNode(withName: "duel.ember.original", recursively: true))
                XCTAssertNil(scene.rootNode.childNode(withName: "duel.liu.original", recursively: true))
                XCTAssertEqual(effects.sourceTextureCount, 9)
                XCTAssertEqual(effects.sourceAudioCount, 29)
                view.frame = CGRect(x: 0, y: 0, width: 956, height: 440); view.layoutIfNeeded()
                XCTAssertNil(view.opticalFramingFailure, "Initial source pose must have a measured camera fit")
                view.pointOfView?.camera?.wantsHDR = false
                view.pointOfView?.camera?.wantsExposureAdaptation = false
                let renderer = SCNRenderer(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()), options: nil)
                renderer.scene = scene; renderer.pointOfView = view.pointOfView
                let commands: [(String, DuelWeaponInput.Action, Int)] = [
                    ("weapon1", .weapon, 0), ("heavy", .weapon, DuelWeaponInput.longPressTicks), ("kick", .kick, 0)
                ]
                for (role, button, hold) in commands {
                    state.restart(); view.drawState()
                    XCTAssertEqual(effects.activeBurstCount, 0, "Restart must remove the previous contact immediately")
                    XCTAssertEqual(effects.playingAudioPlayerCount, 0)
                    XCTAssertEqual(state.animationTick, 0)
                    XCTAssertEqual(state.game.landedHits, [0, 0])
                    XCTAssertEqual(state.game.fighters.map(\.x), [3500, 6500])
                    state.weaponDirection(x: 1, y: 0)
                    for _ in 0..<600 {
                        if abs(state.game.fighters[1].x - state.game.fighters[0].x) <= 1200 { break }
                        state.advance()
                    }
                    state.weaponDirection(x: 0, y: 0); state.advance(); view.drawState()
                    XCTAssertLessThanOrEqual(abs(state.game.fighters[1].x - state.game.fighters[0].x), 1200,
                                             "The real source locomotion must approach the opponent")
                    state.weaponAction(button, down: true)
                    for _ in 0..<hold { state.advance() }
                    state.weaponAction(button, down: false)
                    if hold == 0 { state.advance() }
                    let profile = try XCTUnwrap(state.weaponAssets?.catalog.profile(for: hero))
                    let clip = try XCTUnwrap(profile.clip(role: role))
                    XCTAssertEqual(state.game.fighters[0].weaponPose?.clip, clip.name,
                                   "The physical controls must choose this fighter's original move")
                    for _ in 0..<(clip.ticks + 60) {
                        if state.game.landedHits[0] > 0 { break }
                        state.advance(); view.drawState()
                    }
                    XCTAssertGreaterThan(state.game.landedHits[0], 0, "\(hero)/\(role) must land using the real catalog")
                    XCTAssertGreaterThan(state.game.damageDealt[0], 0)
                    XCTAssertLessThan(state.game.fighters[1].health, 1000)
                    XCTAssertNil(state.game.grapple)
                    XCTAssertTrue(state.game.projectiles.isEmpty)
                    XCTAssertGreaterThan(state.game.hitStop, 0)
                    XCTAssertGreaterThan(effects.emittedHits, 0)
                    XCTAssertGreaterThan(effects.activeParticleCount, 0)
                    let contactCamera = view.combatCamera
                    XCTAssertGreaterThan(abs(contactCamera.impactOffsetX), 0,
                                         "Only the confirmed source contact should start camera recoil")
                    for _ in 0..<12 { view.drawState() }
                    XCTAssertEqual(view.combatCamera, contactCamera,
                                   "Repeated contact captures must not drain or restart the impulse")
                    if role != "kick" {
                        let category = hero == .ember ? "katanaHit" : "hammerHit"
                        XCTAssertGreaterThan(effects.playedSoundCategories[category, default: 0], 0)
                    }
                    view.drawState()
                    let bursts = scene.rootNode.childNodes.filter { $0.name?.hasPrefix("duel.source-effect.hit.") == true }
                    XCTAssertFalse(bursts.isEmpty)
                    let nativeState = particleState(bursts)
                    XCTAssertNil(view.opticalFramingFailure,
                                 "\(hero)/\(role): a fallback lens is not a successful source-contact fit")
                    let withEffect = try capture(renderer, name: "equipped-\(hero.rawValue)-\(role)-source-contact")
                    bursts.forEach { $0.isHidden = true }
                    let withoutEffect = try capture(renderer)
                    bursts.forEach { $0.isHidden = false }
                    XCTAssertGreaterThan(changedPixels(withEffect, withoutEffect), 10,
                                         "The source effect must contribute actual visible pixels in the game scene")
                    let frozenTick = state.animationTick
                    state.advance(); view.drawState()
                    XCTAssertEqual(state.animationTick, frozenTick)
                    XCTAssertEqual(view.combatCamera.centerX, contactCamera.centerX)
                    XCTAssertEqual(view.combatCamera.separation, contactCamera.separation)
                    XCTAssertLessThan(abs(view.combatCamera.impactOffsetX), abs(contactCamera.impactOffsetX),
                                      "Contact recoil settles on consumed frames while source poses remain frozen")
                    XCTAssertEqual(particleState(bursts), nativeState, "Hit-stop must freeze the visible source burst")
                    state.weaponAction(.weapon, down: true)
                    state.weaponAction(.weapon, down: false)
                    state.pause()
                    let pausedGame = state.game
                    for _ in 0..<10 { state.advance(); view.drawState() }
                    XCTAssertEqual(state.game, pausedGame)
                    XCTAssertEqual(state.animationTick, frozenTick)
                    XCTAssertEqual(particleState(bursts), nativeState)
                    XCTAssertEqual(effects.playingAudioPlayerCount, 0)
                    state.restart(); view.drawState()
                    XCTAssertFalse(state.paused)
                    XCTAssertEqual(state.animationTick, 0)
                    XCTAssertEqual(view.combatCamera.impactOffsetX, 0)
                    XCTAssertEqual(view.combatCamera.centerX, 5)
                    XCTAssertEqual(effects.activeBurstCount, 0)
                    XCTAssertEqual(effects.playingAudioPlayerCount, 0)
                    XCTAssertTrue(bursts.allSatisfy { $0.parent == nil })
                    for _ in 0..<4 { state.advance(); view.drawState() }
                    XCTAssertNil(state.game.fighters[0].attack, "Restart must discard a buffered physical button")
                }
                renderer.scene = nil; renderer.pointOfView = nil
                XCTAssertNotNil(releasedAssets)
                view.shutdown(); state.shutdown()
                XCTAssertNil(state.weaponAssets)
                XCTAssertNil(releasedAssets,
                             "Closing must release the resource owner even while the session and view remain alive")
                XCTAssertNil(view.scene)
                XCTAssertTrue(view.weaponAssets.isEmpty)
                XCTAssertNil(view.sourceEffects)
                XCTAssertEqual(effects.activeBurstCount, 0)
                XCTAssertEqual(effects.sourceTextureCount, 0)
                XCTAssertEqual(effects.sourceAudioCount, 0)
                let stoppedGame = state.game, stoppedTick = state.animationTick
                state.resume(); state.restart()
                state.weaponDirection(x: 1, y: 0)
                state.weaponAction(.weapon, down: true); state.advance()
                XCTAssertTrue(state.paused, "A closed session cannot resume or fall back to an unequipped fight")
                XCTAssertEqual(state.game, stoppedGame)
                XCTAssertEqual(state.animationTick, stoppedTick)
                state.shutdown()
                XCTAssertNil(state.weaponAssets, "Repeated teardown must remain safe")
                world = nil; session = nil; SCNTransaction.flush()
            }
            XCTAssertNil(releasedAssets)
            XCTAssertNil(releasedScene)
            XCTAssertNil(releasedHead)
            XCTAssertNil(releasedEffects)
            XCTAssertEqual(DuelWorldView.activeClocks, baselineClocks)
        }
    }

    /// Four fresh production-contact frames for the ordinary endpoint-ribbon
    /// adapter. Visible contribution is separate from approving source-art
    /// fidelity; only the weapon-effects owner is hidden for each comparison.
    func testOrdinaryRibbonAdapterContributesToRealSourceContacts() throws {
        let baselineClocks = DuelWorldView.activeClocks
        for hero in [DuelGame.Hero.ember, .liu] {
            try autoreleasepool {
                let state = DuelSession(.init(hero: hero, difficulty: .learning,
                                               mode: .practice, originalWeapons: true))
                let view = DuelWorldView(session: state)
                defer { view.shutdown(); state.shutdown() }
                XCTAssertNil(state.loadError, "This method requires the authenticated source characters and stage")
                XCTAssertNotNil(state.game.weaponFight)
                XCTAssertFalse(state.isPresentationFixture)
                XCTAssertFalse(view.usesSyntheticPresentationResources)
                XCTAssertNotNil(view.stageAsset)
                XCTAssertTrue(view.originalAssets.isEmpty)
                XCTAssertNil(view.characterAsset)
                XCTAssertEqual(Set(view.weaponAssets.keys), Set([DuelGame.Hero.ember, .liu]))
                XCTAssertEqual(Set(view.weaponAssets.values.map { $0.profile.bodyID }).count, 2)
                XCTAssertEqual(Set(view.weaponAssets.values.map { $0.profile.weaponID }).count, 2)
                let scene = try XCTUnwrap(view.scene), effects = try XCTUnwrap(view.weaponEffects)
                XCTAssertEqual(effects.sourceTextureCount, 11)
                XCTAssertTrue(effects.hasLiveContainer(attachedTo: scene.rootNode))
                let containers = scene.rootNode.childNodes.filter { $0.name == "duel.weapon-effects" }
                XCTAssertEqual(containers.count, 1, "The comparison must hide the actual unique ribbon owner")
                let container = try XCTUnwrap(containers.first)
                view.frame = CGRect(x: 0, y: 0, width: 956, height: 440); view.layoutIfNeeded()
                XCTAssertNil(view.opticalFramingFailure)
                let camera = try XCTUnwrap(view.pointOfView?.camera)
                camera.wantsHDR = false; camera.wantsExposureAdaptation = false
                let renderer = SCNRenderer(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()), options: nil)
                renderer.scene = scene; renderer.pointOfView = view.pointOfView
                defer { renderer.scene = nil; renderer.pointOfView = nil }
                let commands = [("weapon1", 0), ("heavy", DuelWeaponInput.longPressTicks)]
                for (role, hold) in commands {
                    state.restart(); view.drawState()
                    XCTAssertFalse(state.paused)
                    XCTAssertEqual(effects.retainedTrailCount, 0)
                    XCTAssertEqual(state.game.landedHits, [0, 0])
                    state.weaponDirection(x: 1, y: 0)
                    for _ in 0..<600 {
                        if abs(state.game.fighters[1].x - state.game.fighters[0].x) <= 1200 { break }
                        state.advance()
                    }
                    state.weaponDirection(x: 0, y: 0); state.advance(); view.drawState()
                    XCTAssertLessThanOrEqual(abs(state.game.fighters[1].x - state.game.fighters[0].x), 1200)
                    state.weaponAction(.weapon, down: true)
                    for _ in 0..<hold { state.advance() }
                    state.weaponAction(.weapon, down: false)
                    if hold == 0 { state.advance() }
                    let profile = try XCTUnwrap(state.weaponAssets?.catalog.profile(for: hero))
                    let clip = try XCTUnwrap(profile.clip(role: role))
                    XCTAssertEqual(state.game.fighters[0].weaponPose?.clip, clip.name)
                    for _ in 0..<(clip.ticks + 60) {
                        if state.game.landedHits[0] > 0 { break }
                        state.advance(); view.drawState()
                    }
                    view.drawState()
                    let detail = "\(hero.rawValue)/\(role)"
                    XCTAssertGreaterThan(state.game.landedHits[0], 0, "\(detail): capture the first real contact")
                    XCTAssertGreaterThan(state.game.damageDealt[0], 0)
                    XCTAssertLessThan(state.game.fighters[1].health, 1000)
                    XCTAssertGreaterThan(state.game.hitStop, 0)
                    XCTAssertNil(view.opticalFramingFailure, "\(detail): require a measured production camera fit")
                    XCTAssertGreaterThan(effects.renderedVertexCount, 0)
                    XCTAssertFalse(container.isHidden)
                    let frozenGame = state.game, frozenTick = state.animationTick
                    let frozenCamera = view.combatCamera
                    let frozenTrails = effects.trailDiagnostics, frozenSamples = effects.emittedSampleCount
                    for _ in 0..<3 { view.drawState() }
                    XCTAssertEqual(effects.trailDiagnostics, frozenTrails)
                    XCTAssertEqual(effects.emittedSampleCount, frozenSamples,
                                   "\(detail): repeated draws cannot append ribbon samples")
                    let withTrail = try capture(renderer,
                        name: "ribbon-equipped-\(hero.rawValue)-\(role)-source-contact")
                    let withoutTrail: [UInt8]
                    do {
                        container.isHidden = true
                        defer { container.isHidden = false }
                        withoutTrail = try capture(renderer)
                    }
                    XCTAssertGreaterThan(changedPixels(withTrail, withoutTrail), 10,
                                         "\(detail): the ribbon itself must contribute visible production pixels")
                    XCTAssertEqual(state.game, frozenGame)
                    XCTAssertEqual(state.animationTick, frozenTick)
                    XCTAssertEqual(view.combatCamera, frozenCamera)
                    XCTAssertEqual(effects.trailDiagnostics, frozenTrails)
                    state.pause()
                    for _ in 0..<3 { state.advance(); view.drawState() }
                    XCTAssertEqual(state.game, frozenGame)
                    XCTAssertEqual(state.animationTick, frozenTick)
                    XCTAssertEqual(view.combatCamera, frozenCamera)
                    XCTAssertEqual(effects.trailDiagnostics, frozenTrails,
                                   "\(detail): pause must freeze both live and fading ribbon geometry")
                    XCTAssertEqual(effects.emittedSampleCount, frozenSamples)
                }
                renderer.scene = nil; renderer.pointOfView = nil
                view.shutdown(); state.shutdown()
                XCTAssertNil(view.weaponEffects)
                XCTAssertNil(container.parent)
                XCTAssertEqual(effects.retainedTrailCount, 0)
                XCTAssertEqual(effects.renderedVertexCount, 0)
                XCTAssertEqual(effects.sourceTextureCount, 0)
            }
            XCTAssertEqual(DuelWorldView.activeClocks, baselineClocks)
        }
    }

    private func particleState(_ bursts: [SCNNode]) -> [[Float]] {
        bursts.flatMap { burst in
            burst.childNodes.map { node in
                let t = node.simdTransform
                let color = (node.geometry?.firstMaterial?.value(forKey: "sourceFXColor") as? NSValue)?.scnVector4Value ?? SCNVector4(0, 0, 0, 0)
                return [t.columns.0.x, t.columns.0.y, t.columns.1.x, t.columns.1.y,
                        t.columns.3.x, t.columns.3.y, t.columns.3.z,
                        color.x, color.y, color.z, color.w, node.isHidden ? 1 : 0]
            }
        }
    }

    private func capture(_ renderer: SCNRenderer, name: String? = nil) throws -> [UInt8] {
        SCNTransaction.flush()
        let width = 956, height = 440
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: CGFloat(width), height: CGFloat(height)), antialiasingMode: .multisampling2X)
        if let name {
            let attachment = XCTAttachment(image: image); attachment.name = name
            attachment.lifetime = .keepAlways; add(attachment)
        }
        let cg = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        return pixels
    }

    private func changedPixels(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return 0 }
        return stride(from: 0, to: a.count, by: 4).filter { i in
            (0..<3).contains { abs(Int(a[i + $0]) - Int(b[i + $0])) > 4 }
        }.count
    }
}
