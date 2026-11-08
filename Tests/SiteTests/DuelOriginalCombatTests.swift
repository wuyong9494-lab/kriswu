import XCTest
import SceneKit
import simd
@testable import ShiftReminder

@MainActor
final class DuelOriginalCombatTests: XCTestCase {
    private func asset(_ identity: DuelOriginalRigAsset.Identity) throws -> DuelOriginalRigAsset {
        try DuelOriginalRigAsset(url: XCTUnwrap(DuelOriginalRigAsset.bundledURL(for: identity),
            "Original-rig acceptance requires the actual encrypted source assets"), identity: identity)
    }

    private func capture(_ scene: SCNScene, camera: SCNNode?, name: String) {
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene; renderer.pointOfView = camera
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1434, height: 660), antialiasingMode: .multisampling2X)
        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 5000)
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testDefaultLobbyAndBattleUseBothOriginalSkinsAndPersonalHeads() throws {
        let state = DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
        let world = DuelWorldView(session: state)
        defer { world.shutdown(); state.shutdown() }
        XCTAssertEqual(Set(world.originalAssets.keys), Set([.ember, .liu]))
        XCTAssertNil(world.characterAsset, "The default must not silently show the old 42-bone model")
        XCTAssertNotNil(world.stageAsset)
        let scene = try XCTUnwrap(world.scene)
        world.frame = CGRect(x: 0, y: 0, width: 956, height: 440); world.layoutIfNeeded()
        for hero in [DuelGame.Hero.ember, .liu] {
            let identity = try XCTUnwrap(DuelOriginalRigAsset.identity(for: hero))
            let root = try XCTUnwrap(scene.rootNode.childNode(withName: "duel.\(hero.rawValue).original", recursively: true))
            XCTAssertFalse(root.isHidden)
            for name in DuelOriginalRigAsset.skeletonNames {
                XCTAssertNotNil(root.childNode(withName: name, recursively: true), name)
            }
            XCTAssertNotNil(root.childNode(withName: identity.rawValue + "_Personal_Head", recursively: true))
            let lobby = DuelLobbySceneView(hero: hero)
            defer { lobby.shutdown() }
            let lobbyScene = try XCTUnwrap(lobby.scene)
            let actor = try XCTUnwrap(lobbyScene.rootNode.childNode(withName: "duel.lobby.character.\(hero.rawValue)", recursively: false))
            XCTAssertNotNil(actor.childNode(withName: "pelvis", recursively: true))
            XCTAssertNil(actor.childNode(withName: "hips", recursively: true))
            XCTAssertNotNil(actor.childNode(withName: identity.rawValue + "_Personal_Head", recursively: true))
            capture(lobbyScene, camera: lobby.pointOfView, name: "original-runtime-lobby-\(identity.rawValue)")
        }
        capture(scene, camera: world.pointOfView, name: "original-runtime-battle-idle")
    }

    func testContactFramesMatchOriginalBonesInBothDirectionsAndDoNotDrift() throws {
        let scene = SCNScene()
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 2.4
        camera.position = SCNVector3(0, 2.5, 7); camera.look(at: SCNVector3(0, 0.8, 0))
        scene.rootNode.addChildNode(camera)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 350; scene.rootNode.addChildNode(ambient)
        let light = SCNNode(); light.light = SCNLight(); light.light?.type = .omni
        light.light?.intensity = 750; light.position = SCNVector3(-3, 4, 5); scene.rootNode.addChildNode(light)
        for move in [DuelGame.Move.jab, .cross, .finisher, .heavy, .skill1, .skill2] {
            for identity in DuelOriginalRigAsset.Identity.allCases {
                let asset = try asset(identity), actor = DuelOriginalCombatInstance(asset)
                let root = SCNNode(); root.addChildNode(actor.instance.root); scene.rootNode.addChildNode(root)
                var fighter = DuelGame(hero: identity == .liu ? .liu : .ember).fighters[0]
                fighter.attack = .init(move: move, age: DuelGame.data(move, hero: fighter.hero).startup)
                for direction in [1, -1] {
                    fighter.facing = direction; fighter.x = direction == 1 ? -1000 : 1000
                    actor.pose(fighter, tick: 100, grapple: nil, index: 0, phase: .fighting, root: root)
                    let selected = DuelOriginalCombatAnimation.sample(fighter, animationTick: 100, grapple: nil, index: 0, phase: .fighting)
                    var expected = asset.model.restPose; asset.sample(selected.selection, into: &expected)
                    for index in asset.model.animated {
                        XCTAssertEqual(actor.instance.nodes[index].simdTransform, expected.transform(index), "\(identity)/\(move)/\(direction)")
                    }
                    let hands = try [XCTUnwrap(actor.bone("hand.L")), XCTUnwrap(actor.bone("hand.R"))]
                    let reach = hands.map { ($0.worldPosition.x - root.position.x) * Float(direction) }.max() ?? 0
                    XCTAssertGreaterThan(reach, 0.35, "The selected contact must extend toward the opponent")
                    let frozen = actor.instance.nodes.map(\.simdWorldTransform)
                    for _ in 0..<3 { actor.pose(fighter, tick: 100, grapple: nil, index: 0, phase: .fighting, root: root) }
                    XCTAssertEqual(actor.instance.nodes.map(\.simdWorldTransform), frozen)
                }
                fighter.facing = identity == .liu ? 1 : -1
                fighter.x = identity == .liu ? -1000 : 1000
                actor.pose(fighter, tick: 100, grapple: nil, index: 0, phase: .fighting, root: root)
            }
            capture(scene, camera: camera, name: "original-runtime-contact-\(move.rawValue)")
            scene.rootNode.childNodes.filter { $0 !== camera && $0 !== ambient && $0 !== light }.forEach { $0.removeFromParentNode() }
        }
    }

    func testActualRuleGrappleStaysConnectedGroundedAndSeparatedBothDirections() throws {
        for direction in [1, -1] {
            let state = DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
            let world = DuelWorldView(session: state)
            defer { world.shutdown(); state.shutdown() }
            world.frame = CGRect(x: 0, y: 0, width: 956, height: 440); world.layoutIfNeeded()
            XCTAssertEqual(world.originalAssets.count, 2)
            state.input("right", down: true)
            for _ in 0..<42 { state.advance() }
            if direction == -1 {
                state.input("jump", down: true); state.advance(); state.input("jump", down: false)
                for _ in 0..<31 { state.advance() }
                state.input("right", down: false)
                XCTAssertGreaterThan(state.game.fighters[0].x, state.game.fighters[1].x)
                state.input("left", down: true)
                for _ in 0..<100 {
                    if abs(state.game.fighters[0].x - state.game.fighters[1].x) > 850 { state.advance() }
                }
                state.input("left", down: false)
            }
            state.input("right", down: false)
            state.input("ultimate", down: true); state.advance(); state.input("ultimate", down: false)
            for _ in 0..<35 { if state.game.grapple == nil { state.advance() } }
            XCTAssertEqual(state.game.grapple?.direction, direction)
            let scene = try XCTUnwrap(world.scene)
            let attacker = try XCTUnwrap(scene.rootNode.childNode(withName: "duel.actor.0", recursively: false))
            let defender = try XCTUnwrap(scene.rootNode.childNode(withName: "duel.actor.1", recursively: false))
            let skin = try XCTUnwrap(attacker.childNode(withName: "duel.liu.original", recursively: false))
            let other = try XCTUnwrap(defender.childNode(withName: "duel.ember.original", recursively: false))
            let side = direction == 1 ? "r" : "l"
            let hand = try XCTUnwrap(skin.childNode(withName: "hand_" + side, recursively: true))
            let captured = try XCTUnwrap(other.childNode(withName: "hand_" + side, recursively: true))
            let pelvis = try XCTUnwrap(skin.childNode(withName: "pelvis", recursively: true))
            let head = try XCTUnwrap(other.childNode(withName: "head", recursively: true))
            var worstGap: Float = 0, samples = 0
            for _ in 0..<300 {
                guard let hold = state.game.grapple else { break }
                world.drawState()
                skin.enumerateChildNodes { node, _ in
                    if node.name?.hasPrefix("duel.source.sole.") == true {
                        XCTAssertGreaterThanOrEqual(node.worldPosition.y, -0.05)
                    }
                    XCTAssertTrue(node.worldPosition.x.isFinite && node.worldPosition.y.isFinite && node.worldPosition.z.isFinite)
                }
                if hold.stage == .hold {
                    samples += 1
                    worstGap = max(worstGap, simd_distance(hand.simdWorldPosition, captured.simdWorldPosition))
                    XCTAssertGreaterThan(attacker.position.z - defender.position.z, 0.5)
                    XCTAssertGreaterThan(abs(pelvis.worldPosition.x - head.worldPosition.x), 0.45)
                }
                if [12, 65, 210].contains(hold.age) {
                    let before = hand.simdWorldTransform, otherBefore = captured.simdWorldTransform
                    world.drawState()
                    XCTAssertEqual(hand.simdWorldTransform, before)
                    XCTAssertEqual(captured.simdWorldTransform, otherBefore)
                    capture(scene, camera: world.pointOfView, name: "original-runtime-grapple-\(direction)-\(hold.age)")
                }
                state.advance()
            }
            XCTAssertEqual(samples, DuelGame.Grapple.holdTicks)
            XCTAssertLessThan(worstGap, 0.10, "The visible original wrists must actually connect")
            XCTAssertNil(state.game.grapple); XCTAssertEqual(state.game.damageDealt[0], 280)
            let metrics = XCTAttachment(string: "direction=\(direction) worstWristGap=\(worstGap) holdSamples=\(samples)")
            metrics.name = "original-runtime-contact-metrics-\(direction)"; metrics.lifetime = .keepAlways; add(metrics)
        }
    }

    func testHitStopPauseRestartAndJumpDoNotDriftOrDoubleRootLift() throws {
        let state = DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
        let world = DuelWorldView(session: state)
        defer { world.shutdown(); state.shutdown() }
        let skin = try XCTUnwrap(world.scene?.rootNode.childNode(withName: "duel.liu.original", recursively: true))
        let hand = try XCTUnwrap(skin.childNode(withName: "hand_r", recursively: true))
        let pelvis = try XCTUnwrap(skin.childNode(withName: "pelvis", recursively: true))
        let idleHeight = pelvis.worldPosition.y
        state.input("jump", down: true); state.advance(); state.input("jump", down: false)
        for _ in 0..<25 {
            world.drawState()
            XCTAssertEqual(pelvis.worldPosition.y, idleHeight + Float(state.game.fighters[0].y) / 1000, accuracy: 0.04)
            state.advance()
        }
        state.restart(); world.drawState()
        state.input("right", down: true); for _ in 0..<42 { state.advance() }
        state.input("right", down: false); state.input("light", down: true); state.advance(); state.input("light", down: false)
        for _ in 0..<20 { if state.game.hitStop == 0 { state.advance() } }
        XCTAssertGreaterThan(state.game.hitStop, 0)
        world.drawState(); let tick = state.animationTick, before = hand.simdWorldTransform
        state.advance(); world.drawState()
        XCTAssertEqual(state.animationTick, tick); XCTAssertEqual(hand.simdWorldTransform, before)
        state.pause()
        for _ in 0..<20 { state.advance(); world.drawState() }
        XCTAssertEqual(hand.simdWorldTransform, before)
        state.restart(); world.drawState(); XCTAssertEqual(state.animationTick, 0)
        let reference = DuelOriginalCombatInstance(try XCTUnwrap(world.originalAssets[.liu]))
        reference.apply(.sample(state.game.fighters[0], animationTick: 0, grapple: nil, index: 0, phase: .fighting), tick: 0)
        XCTAssertEqual(hand.simdTransform, try XCTUnwrap(reference.bone("hand.R")).simdTransform)
    }

    func testOriginalRuntimeAssetsScenesAndSkeletonsReleaseAfterRepeatedEntries() throws {
        let baseline = DuelWorldView.activeClocks
        for _ in 0..<3 {
            weak var releasedAsset: DuelOriginalRigAsset?
            weak var releasedScene: SCNScene?
            weak var releasedHead: SCNNode?
            try autoreleasepool {
                let state = DuelSession(.init(hero: .liu, difficulty: .learning, mode: .practice))
                let world = DuelWorldView(session: state)
                releasedAsset = world.originalAssets[.liu]; releasedScene = world.scene
                let skin = try XCTUnwrap(world.scene?.rootNode.childNode(withName: "duel.liu.original", recursively: true))
                releasedHead = skin.childNode(withName: "head", recursively: true)
                XCTAssertNotNil(releasedAsset); XCTAssertNotNil(releasedHead)
                world.shutdown(); state.shutdown(); SCNTransaction.flush()
                XCTAssertTrue(world.originalAssets.isEmpty)
            }
            XCTAssertNil(releasedAsset); XCTAssertNil(releasedScene); XCTAssertNil(releasedHead)
            XCTAssertEqual(DuelWorldView.activeClocks, baseline)
        }
    }
}
