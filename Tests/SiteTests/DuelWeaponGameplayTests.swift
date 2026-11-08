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

    func testUnresolvedShadowTeleportsCannotBecomeInvisibleDamageSweeps() throws {
        let assets = try DuelWeaponAssets()
        for hero in [DuelGame.Hero.ember, .liu] {
            let other: DuelGame.Hero = hero == .ember ? .liu : .ember
            let fighters = [DuelGame.Fighter(hero: hero, x: 4400, facing: 1),
                            DuelGame.Fighter(hero: other, x: 5600, facing: -1)]
            var fight = try XCTUnwrap(DuelWeaponFight(fighters: fighters, mode: .practice,
                difficulty: .learning, catalog: assets.catalog, seed: 7))
            XCTAssertNotNil(fight.profiles[0].clip(role: "shadow"), "Preserve the original resource for later event reconstruction")
            XCTAssertEqual(fight.fighters[0].energy, 100)
            XCTAssertFalse(fight.canUse(.shadow, index: 0),
                           "Raw teleport / weapon visibility discontinuities lack recovered source event semantics")
            fight.step(.init(weaponCommand: .shadow), opponent: .neutral)
            for _ in 0..<200 {
                fight.step(.neutral, opponent: .neutral)
                XCTAssertTrue(fight.contacts.isEmpty)
                XCTAssertNil(fight.fighters[0].attack)
            }
            XCTAssertEqual(fight.fighters.map(\.x), [4400, 5600])
            XCTAssertEqual(fight.fighters.map(\.health), [1000, 1000])
            XCTAssertEqual(fight.fighters[0].energy, 100, "Unavailable input must not consume energy")
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
                    if role != "kick" {
                        let category = hero == .ember ? "katanaHit" : "hammerHit"
                        XCTAssertGreaterThan(effects.playedSoundCategories[category, default: 0], 0)
                    }
                    view.drawState()
                    let bursts = scene.rootNode.childNodes.filter { $0.name?.hasPrefix("duel.source-effect.hit.") == true }
                    XCTAssertFalse(bursts.isEmpty)
                    let nativeState = particleState(bursts)
                    let withEffect = try capture(renderer, name: "equipped-\(hero.rawValue)-\(role)-source-contact")
                    bursts.forEach { $0.isHidden = true }
                    let withoutEffect = try capture(renderer)
                    bursts.forEach { $0.isHidden = false }
                    XCTAssertGreaterThan(changedPixels(withEffect, withoutEffect), 10,
                                         "The source effect must contribute actual visible pixels in the game scene")
                    let frozenTick = state.animationTick
                    state.advance(); view.drawState()
                    XCTAssertEqual(state.animationTick, frozenTick)
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
                    XCTAssertEqual(effects.activeBurstCount, 0)
                    XCTAssertEqual(effects.playingAudioPlayerCount, 0)
                    XCTAssertTrue(bursts.allSatisfy { $0.parent == nil })
                    for _ in 0..<4 { state.advance(); view.drawState() }
                    XCTAssertNil(state.game.fighters[0].attack, "Restart must discard a buffered physical button")
                }
                renderer.scene = nil; renderer.pointOfView = nil
                view.shutdown(); state.shutdown()
                XCTAssertNil(view.scene)
                XCTAssertTrue(view.weaponAssets.isEmpty)
                XCTAssertNil(view.sourceEffects)
                XCTAssertEqual(effects.activeBurstCount, 0)
                XCTAssertEqual(effects.sourceTextureCount, 0)
                XCTAssertEqual(effects.sourceAudioCount, 0)
                world = nil; session = nil; SCNTransaction.flush()
            }
            XCTAssertNil(releasedAssets)
            XCTAssertNil(releasedScene)
            XCTAssertNil(releasedHead)
            XCTAssertNil(releasedEffects)
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
