import XCTest
import SceneKit
@testable import ShiftReminder

@MainActor
final class DuelCharacterTests: XCTestCase {
    private func asset() throws -> DuelCharacterAsset {
        try DuelCharacterAsset(url: XCTUnwrap(DuelCharacterAsset.bundledURL, "Fighter CI must stage the actual private model; a greybox is not acceptance evidence"))
    }
    func testActualAssetHasIndependentSkeletonsAndAuthoredMaterials() throws {
        let asset = try asset(), a = DuelCharacterInstance(asset), b = DuelCharacterInstance(asset)
        XCTAssertEqual(asset.model.clips.count, 12)
        XCTAssertTrue(asset.model.hasSkinning)
        XCTAssertFalse(a.bone("hand.R") === b.bone("hand.R"))
        let before = try XCTUnwrap(b.bone("hand.R")).simdTransform
        var fighter = DuelGame(hero: .liu).fighters[0]
        fighter.attack = .init(move: .jab, age: DuelGame.data(.jab, hero: .liu).startup)
        a.apply(.sample(fighter, animationTick: 12, grapple: nil, index: 0, phase: .fighting), tick: 12)
        XCTAssertEqual(try XCTUnwrap(b.bone("hand.R")).simdTransform, before)
        XCTAssertTrue(a.instance.materials.allSatisfy { $0.lightingModel == .physicallyBased })
        let skin = try XCTUnwrap(a.instance.materials.first { $0.name == "tripo_mat_c4757646" })
        XCTAssertNotNil(skin.normal.contents)
        XCTAssertEqual(skin.roughness.textureComponents, .green)
        XCTAssertEqual(skin.metalness.textureComponents, .blue)
        let untouched = b.instance.materials[0].emission.contents as? UIColor
        a.instance.materials[0].emission.contents = UIColor.red
        XCTAssertEqual(b.instance.materials[0].emission.contents as? UIColor, untouched)
    }
    func testPausedAndHitStopAnimationClockAndAssetLifetime() throws {
        let state = DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
        var world: DuelWorldView? = DuelWorldView(session: state)
        weak var retainedAsset = world?.characterAsset
        XCTAssertNotNil(retainedAsset)
        state.input("right", down: true)
        for _ in 0..<42 { state.advance() }
        state.input("right", down: false); state.input("light", down: true); state.advance(); state.input("light", down: false)
        for _ in 0..<20 { if state.game.hitStop == 0 { state.advance() } }
        XCTAssertGreaterThan(state.game.hitStop, 0)
        let tick = state.animationTick
        state.advance(); XCTAssertEqual(state.animationTick, tick)
        world?.drawState()
        let scene = try XCTUnwrap(world?.scene)
        let hand = try XCTUnwrap(scene.rootNode.childNode(withName: "hand.R", recursively: true))
        let before = hand.simdWorldTransform
        state.pause()
        for _ in 0..<20 { state.advance(); world?.drawState() }
        XCTAssertEqual(state.animationTick, tick); XCTAssertEqual(hand.simdWorldTransform, before)
        state.restart(); XCTAssertEqual(state.animationTick, 0)
        world?.drawState(); world?.shutdown(); world = nil
        XCTAssertNil(retainedAsset, "The decoded model must not survive scene shutdown")
    }
    func testRealLiuGrappleGroundingContactAndRenderedEvidence() throws {
        let state = DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
        let world = DuelWorldView(session: state)
        defer { world.shutdown(); state.shutdown() }
        XCTAssertNotNil(world.characterAsset)
        world.frame = CGRect(x: 0, y: 0, width: 956, height: 440); world.layoutIfNeeded()
        let scene = try XCTUnwrap(world.scene)
        let actor = try XCTUnwrap(scene.rootNode.childNode(withName: "duel.actor.0", recursively: false))
        let skin = try XCTUnwrap(actor.childNode(withName: "duel.liu.skinned", recursively: false))
        XCTAssertFalse(skin.isHidden)
        let defender = try XCTUnwrap(scene.rootNode.childNode(withName: "duel.actor.1", recursively: false))
        let capturedWrist: SCNNode
        let defenderHead: SCNNode
        if let defenderSkin = defender.childNode(withName: "duel.\(state.game.fighters[1].hero.rawValue).skinned", recursively: false) {
            XCTAssertFalse(defenderSkin.isHidden)
            capturedWrist = try XCTUnwrap(defenderSkin.childNode(withName: "hand.R", recursively: true))
            defenderHead = try XCTUnwrap(defenderSkin.childNode(withName: "head", recursively: true))
        } else {
            // The Liu-only workflow retains a procedural opponent. When the
            // personal Sun asset is staged, only its visible skeleton counts.
            capturedWrist = try XCTUnwrap(defender.childNode(withName: "duel.hand.right", recursively: true))
            defenderHead = try XCTUnwrap(defender.childNode(withName: "head", recursively: false))
        }
        snapshot(world, name: "liu-native-idle")
        state.input("right", down: true)
        for _ in 0..<42 { state.advance() }
        state.input("right", down: false); state.input("ultimate", down: true); state.advance(); state.input("ultimate", down: false)
        for _ in 0..<35 { if state.game.grapple == nil { state.advance() } }
        XCTAssertNotNil(state.game.grapple)
        var worstGap: Float = 0
        while let hold = state.game.grapple {
            world.drawState()
            skin.enumerateChildNodes { node, _ in
                if node.name?.hasPrefix("duel.sole.") == true {
                    XCTAssertGreaterThanOrEqual(node.worldPosition.y, -0.05, "Actual imported sole must not cross the stage")
                }
                let p = node.worldPosition
                XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.z.isFinite)
            }
            if hold.stage == .hold {
                let hand = try XCTUnwrap(skin.childNode(withName: "hand.R", recursively: true))
                let a = hand.worldPosition, b = capturedWrist.worldPosition
                let gap = ((a.x-b.x)*(a.x-b.x) + (a.y-b.y)*(a.y-b.y) + (a.z-b.z)*(a.z-b.z)).squareRoot()
                worstGap = max(worstGap, gap)
                XCTAssertGreaterThan(actor.position.z - defender.position.z, 0.5)
                let hip = try XCTUnwrap(skin.childNode(withName: "hips", recursively: true))
                XCTAssertGreaterThan(abs(hip.worldPosition.x - defenderHead.worldPosition.x), 0.45)
                if hold.age == 65 {
                    let grip = hand.simdWorldTransform, captured = capturedWrist.simdWorldTransform
                    world.drawState()
                    XCTAssertEqual(hand.simdWorldTransform, grip, "A repeated hold draw must not drift the grip")
                    XCTAssertEqual(capturedWrist.simdWorldTransform, captured, "A repeated hold draw must not drift the captured arm")
                }
            }
            if [12, 65, 210].contains(hold.age) { snapshot(world, name: "liu-native-grapple-\(hold.age)") }
            state.advance()
        }
        XCTAssertLessThan(worstGap, 0.10, "Imported hand must actually connect to the captured wrist")
        XCTAssertEqual(state.game.damageDealt[0], 280)
        let evidence = XCTAttachment(string: "worstWristGap=\(worstGap) triangles=70836 joints=42 textureLimit=1024")
        evidence.name = "liu-native-metrics"; evidence.lifetime = .keepAlways; add(evidence)
    }

    func testFirstRenderedContactAndRepeatedPunchesUseAuthoredPose() throws {
        let model = try asset()
        let actor = DuelCharacterInstance(model)
        var fighter = DuelGame(hero: .liu).fighters[0]
        actor.apply(.sample(fighter, animationTick: 0, grapple: nil, index: 0, phase: .fighting), tick: 0)
        for (index, move) in [DuelGame.Move.jab, .jab, .cross, .finisher].enumerated() {
            let tick = 100 * (index + 1)
            fighter.attack = .init(move: move, age: DuelGame.data(move, hero: .liu).startup)
            let selection = DuelCharacterAnimation.sample(fighter, animationTick: tick, grapple: nil, index: 0, phase: .fighting)
            let reference = DuelCharacterInstance(model)
            reference.apply(selection, tick: tick)
            actor.apply(selection, tick: tick)
            for name in ["hand.L", "hand.R", "chest"] {
                let bone = try XCTUnwrap(actor.bone(name))
                XCTAssertEqual(bone.simdTransform, try XCTUnwrap(reference.bone(name)).simdTransform)
                let frozen = bone.simdTransform
                for _ in 0..<5 { actor.apply(selection, tick: tick) }
                XCTAssertEqual(bone.simdTransform, frozen, "Repeated paused/hit-stop draws must be idempotent")
            }
        }
    }

    func testRepeatedJabRestartsAndAdvancesStartupBlendWithoutIdleDraw() throws {
        let asset = try asset()
        let actor = DuelCharacterInstance(asset)
        let clip = try XCTUnwrap(asset.model.clips["Jab"])
        let start = asset.starts["Jab"] ?? 0
        var fighter = DuelGame(hero: .liu).fighters[0]
        let data = DuelGame.data(.jab, hero: .liu)
        func authoredPose(_ selection: DuelCharacterAnimation) -> GLTFModel.Pose {
            var pose = asset.model.restPose
            clip.sample(at: start + (clip.duration - start) * selection.progress, into: &pose)
            return pose
        }
        // Leave the last rendered jab at contact, then skip recovery/idle draws.
        // A move-only key would fail to restart the next startup transition.
        fighter.attack = .init(move: .jab, age: data.startup)
        let contact = DuelCharacterAnimation.sample(fighter, animationTick: 100,
                                                    grapple: nil, index: 0, phase: .fighting)
        actor.apply(contact, tick: 100)
        var previousKey = contact.key
        var previousPose = authoredPose(contact)
        for onset in [200, 300] {
            let transitionPose = previousPose
            for age in 0..<data.startup {
                fighter.attack = .init(move: .jab, age: age)
                let selection = DuelCharacterAnimation.sample(fighter, animationTick: onset + age,
                                                              grapple: nil, index: 0, phase: .fighting)
                if age == 0 { XCTAssertNotEqual(selection.key, previousKey) }
                else { XCTAssertEqual(selection.key, previousKey) }
                previousKey = selection.key
                XCTAssertEqual(selection.transitionTicks, 3)
                var expected = authoredPose(selection)
                expected.blend(toward: transitionPose, weight: max(0, 1 - Float(age) / 3),
                               nodes: asset.model.animated)
                actor.apply(selection, tick: onset + age)
                for node in asset.model.animated {
                    XCTAssertEqual(actor.instance.nodes[node].simdTransform, expected.transform(node),
                                   "Startup blend must advance from its original captured pose")
                }
                // Paused/hit-stop redraws must neither advance nor restart it.
                for _ in 0..<3 { actor.apply(selection, tick: onset + age) }
                for node in asset.model.animated {
                    XCTAssertEqual(actor.instance.nodes[node].simdTransform, expected.transform(node))
                }
                previousPose = expected
            }
        }
    }

    func testOpeningFeedbackSurvivesFirstTickAndRestart() {
        let state = DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
        defer { state.shutdown() }
        let opening = state.feedback
        state.advance()
        XCTAssertEqual(state.feedback, opening)
        state.pause()
        for _ in 0..<100 { state.advance() }
        XCTAssertEqual(state.feedback, opening)
        state.resume()
        for _ in 0..<75 { state.advance() }
        XCTAssertEqual(state.feedback, "")
        state.restart(); state.advance()
        XCTAssertEqual(state.feedback, opening)
    }
    private func snapshot(_ world: DuelWorldView, name: String) {
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = world.scene; renderer.pointOfView = world.pointOfView
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1434, height: 660), antialiasingMode: .multisampling2X)
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 5000)
    }
}
