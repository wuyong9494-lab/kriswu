import XCTest
import SceneKit
import simd
import Metal
@testable import ShiftReminder

@MainActor
final class ArenaAnimationTests: XCTestCase {
    func testBushExitRestoresAuthoredSizeAfterRepeatedBoundaryReversals() {
        let node = SCNNode()
        let base = SIMD3<Float>(1.63, 1.45, 1.51)
        node.simdScale = base
        let bush = ArenaBushVisual(node: node, patchID: 7, bends: true)
        for frame in 0..<180 {
            let previousOpacity = node.opacity
            bush.update(open: frame % 2 == 0, dt: 1 / 60)
            XCTAssertLessThan(abs(node.opacity - previousOpacity), 0.16)
            XCTAssertGreaterThanOrEqual(node.simdScale.x, base.x)
            XCTAssertGreaterThanOrEqual(node.simdScale.y, base.y * 0.82 - 0.00001)
        }
        for _ in 0..<120 { bush.update(open: false, dt: 1 / 60) }
        XCTAssertEqual(node.simdScale, base)
        XCTAssertEqual(node.opacity, 1)
        XCTAssertFalse(node.hasActions)
        XCTAssertEqual(bush.patchID, 7)
    }

    func testBushTransitionIsCadenceIndependentAndSampleKeepsOpaqueDepth() {
        let slow = ArenaBushVisual(node: SCNNode(), patchID: 1, bends: true)
        let fast = ArenaBushVisual(node: SCNNode(), patchID: 1, bends: true)
        for _ in 0..<6 { slow.update(open: true, dt: 1 / 30) }
        for _ in 0..<24 { fast.update(open: true, dt: 1 / 120) }
        XCTAssertEqual(slow.openness, fast.openness, accuracy: 0.00001)
        XCTAssertEqual(slow.node.opacity, fast.node.opacity, accuracy: 0.00001)
        let sample = ArenaBushVisual(node: SCNNode(), patchID: 2, bends: false)
        sample.update(open: true, dt: 0)
        XCTAssertEqual(sample.node.opacity, 1)
        for _ in 0..<120 { sample.update(open: true, dt: 1 / 60) }
        XCTAssertEqual(sample.node.simdScale.x, 1)
        XCTAssertEqual(sample.node.simdScale.y, 0.82, accuracy: 0.00001)
        XCTAssertEqual(sample.node.simdScale.z, 1)
        XCTAssertEqual(sample.node.opacity, 1)
    }

    func testBushBoundaryNeverMakesCharacterOrFoliageTranslucent() {
        let game = ArenaGame(mode: .teamFight, entrants: [
            .init(name: "我", brawler: .ranger, isBot: false, team: 0),
            .init(name: "对手", brawler: .knight, isBot: true, team: 1)
        ], seed: 1)
        let avatar = ArenaAvatar(brawler: .ranger, color: .blue, isMe: true)
        let grass = ArenaBushVisual(node: SCNNode(), patchID: 1, bends: true)
        for frame in 0..<180 {
            let inside = frame % 2 == 0
            avatar.update(game.fighters[0], visible: true, translucent: inside, cheering: false,
                          dt: 1 / 60, clock: Double(frame) / 60)
            grass.update(open: inside, dt: 1 / 60)
            XCTAssertEqual(avatar.node.opacity, 1)
            XCTAssertFalse(avatar.node.isHidden)
            XCTAssertEqual(grass.node.opacity, 1)
        }
        XCTAssertGreaterThan(avatar.concealmentAmount, 0.95, "An ally in cover must have a visible ghost treatment")
        for frame in 0..<120 {
            avatar.update(game.fighters[0], visible: false, translucent: true, cheering: false,
                          dt: 1 / 60, clock: 3 + Double(frame) / 60)
        }
        XCTAssertTrue(avatar.node.isHidden, "Concealment cue must not reveal a hidden fighter")
        XCTAssertLessThan(avatar.concealmentAmount, 0.01)
        let other = ArenaAvatar(brawler: .ranger, color: .red, isMe: false)
        other.update(game.fighters[1], visible: true, translucent: false, cheering: false, dt: 1, clock: 8)
        XCTAssertEqual(other.concealmentAmount, 0)
    }

    func testConcealmentShaderActuallyRendersAndDiscardsCoverage() throws {
        // In-memory GPU assertion only: no screenshot files or visual approval step.
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderer = SCNRenderer(device: device, options: nil)
        let scene = SCNScene()
        scene.background.contents = UIColor.black
        renderer.scene = scene
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(camera)
        renderer.pointOfView = camera
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        material.shaderModifiers = [.fragment: ArenaAvatar.concealmentFragment]
        let plane = SCNNode(geometry: SCNPlane(width: 2, height: 2))
        plane.geometry?.firstMaterial = material
        scene.rootNode.addChildNode(plane)
        func litPixels(_ amount: Float) throws -> Int {
            material.setValue(amount, forKey: "arenaConcealment")
            SCNTransaction.flush()
            let image = renderer.snapshot(atTime: 0, with: CGSize(width: 128, height: 128), antialiasingMode: .none)
            let cg = try XCTUnwrap(image.cgImage)
            var rgba = [UInt8](repeating: 0, count: 128 * 128 * 4)
            let count: Int = try rgba.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 128, height: 128,
                    bitsPerComponent: 8, bytesPerRow: 128 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(cg, in: CGRect(x: 0, y: 0, width: 128, height: 128))
                let pixels = bytes.bindMemory(to: UInt8.self)
                return stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 64 }.count
            }
            return count
        }
        let solid = try litPixels(0)
        let hidden = try litPixels(1)
        XCTAssertGreaterThan(solid, 1000, "Shader must compile and render")
        XCTAssertGreaterThan(hidden, solid / 5, "Concealed ally remains readable")
        XCTAssertLessThan(hidden, solid * 3 / 4, "Concealment must visibly remove coverage")
        XCTAssertEqual(try litPixels(0), solid, "Leaving grass restores the opaque hero")
    }

    func testCombatCameraRetainsTopDownGroundCoverage() {
        let pitch = atan2(ArenaWorldView.cameraOffset.y, ArenaWorldView.cameraOffset.z) * 180 / Float.pi
        XCTAssertGreaterThan(pitch, 60)
        XCTAssertLessThan(pitch, 70)
        XCTAssertGreaterThan(ArenaWorldView.landscapeHalfWidth * 2, 25)
    }

    func testBenchmarkIsRepeatableAcrossCallbackCadences() {
        let setup = ArenaController.Setup(mode: .zone, brawler: .ranger, name: "压测", level: 3,
                                          loadout: .basic(.ranger, level: 3), benchmark: true)
        let fast = ArenaController(setup: setup, seed: 1)
        let slow = ArenaController(setup: setup, seed: 999)
        for fighter in fast.game.fighters {
            XCTAssertFalse(fast.game.map.collides(fighter.pos, radius: ArenaGame.fighterRadius))
        }
        fast.advance(ArenaController.introLength + 0.1)
        slow.advance(ArenaController.introLength + 0.1)
        for _ in 0..<360 { fast.advance(1.0 / 60) }
        for _ in 0..<180 { slow.advance(1.0 / 30) }
        XCTAssertEqual(fast.game.time, slow.game.time, accuracy: 0.00001)
        XCTAssertEqual(fast.game.fighters.map(\.pos), slow.game.fighters.map(\.pos))
        XCTAssertEqual(fast.game.fighters.map(\.health), slow.game.fighters.map(\.health))
    }

    func testOutlineWindingMatchesOutwardNormals() {
        let positions: [Float] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
        let normals: [Float] = [0, 0, 1, 0, 0, 1, 0, 0, 1]
        // Keep good faces, reverse the imported inward face, preserve a degenerate face.
        let repaired = GLTFModel.outwardTriangleIndices([0, 1, 2, 0, 2, 1, 0, 0, 1],
                                                        positions: positions, normals: normals)
        XCTAssertEqual(repaired, [0, 1, 2, 0, 1, 2, 0, 0, 1])
        XCTAssertEqual(GLTFModel.outwardTriangleIndices(repaired, positions: positions, normals: normals), repaired)
        XCTAssertEqual(GLTFModel.outwardTriangleIndices([0, 2, 1], positions: positions, normals: []), [0, 2, 1])
    }

    func testSharedModelCacheKeepsEveryCharactersCombatClips() throws {
        // Earlier characters deliberately load before their shared-model variants.
        for brawler in Brawler.allCases {
            let look = BrawlerLook.of(brawler)
            let model = try XCTUnwrap(ArenaModels.shared.character(brawler), look.file)
            for name in [look.idle, look.run, look.attack.clip, look.special.clip] {
                XCTAssertNotNil(model.clips[name], "\(brawler): missing \(name) in \(look.file)")
            }
        }
        for brawler in Brawler.allCases.reversed() {
            let look = BrawlerLook.of(brawler)
            let model = try XCTUnwrap(ArenaModels.shared.character(brawler))
            XCTAssertNotNil(model.clips[look.special.clip])
        }
    }

    func testHiddenFighterDoesNotReplayExpiredAttackWhenRevealed() throws {
        let game = ArenaGame(mode: .teamFight, entrants: [
            .init(name: "游侠", brawler: .ranger, isBot: false, team: 0),
            .init(name: "骑士", brawler: .knight, isBot: true, team: 1)
        ], seed: 1)
        let fighter = game.fighters[0]
        let reference = ArenaAvatar(brawler: .ranger, color: .blue, isMe: false, decorated: false)
        let hidden = ArenaAvatar(brawler: .ranger, color: .blue, isMe: false, decorated: false)
        let dt: Float = 1 / 60
        reference.attack()
        hidden.attack()
        for frame in 0..<120 {
            reference.update(fighter, visible: true, translucent: false, cheering: false, dt: dt, clock: Double(frame) / 60)
            hidden.update(fighter, visible: false, translucent: false, cheering: false, dt: dt, clock: Double(frame) / 60)
        }
        XCTAssertTrue(hidden.node.isHidden)
        reference.update(fighter, visible: true, translucent: false, cheering: false, dt: dt, clock: 2)
        hidden.update(fighter, visible: true, translucent: false, cheering: false, dt: dt, clock: 2)
        XCTAssertFalse(hidden.node.isHidden)
        // Compare actual rendered bones, not an internal animation-state flag.
        for name in ["spine", "chest", "upperarm.r", "lowerarm.r"] {
            let expected = try XCTUnwrap(reference.node.childNode(withName: name, recursively: true))
            let actual = try XCTUnwrap(hidden.node.childNode(withName: name, recursively: true))
            for column in 0..<4 {
                XCTAssertLessThan(simd_length(expected.simdTransform[column] - actual.simdTransform[column]), 0.0001, name)
            }
        }
    }

    func testRepeatedMovingAttacksExpireAndReturnToLocomotion() throws {
        let game = ArenaGame(mode: .teamFight, entrants: [
            .init(name: "游侠", brawler: .ranger, isBot: false, team: 0),
            .init(name: "骑士", brawler: .knight, isBot: true, team: 1)
        ], seed: 1)
        var fighter = game.fighters[0]
        let reference = ArenaAvatar(brawler: .ranger, color: .blue, isMe: false, decorated: false)
        let attacking = ArenaAvatar(brawler: .ranger, color: .blue, isMe: false, decorated: false)
        let dt: Float = 1 / 60
        var attackChangedPose = false
        for frame in 0..<240 {
            fighter.pos.x += 2.4 / 60
            if [0, 24, 48, 72].contains(frame) { attacking.attack() }
            for avatar in [reference, attacking] {
                avatar.update(fighter, visible: true, translucent: false, cheering: false, dt: dt, clock: Double(frame) / 60)
            }
            if frame == 80 {
                let a = try XCTUnwrap(reference.node.childNode(withName: "upperarm.r", recursively: true))
                let b = try XCTUnwrap(attacking.node.childNode(withName: "upperarm.r", recursively: true))
                attackChangedPose = (0..<4).contains { simd_length(a.simdTransform[$0] - b.simdTransform[$0]) > 0.001 }
            }
        }
        XCTAssertTrue(attackChangedPose, "Repeated attacks must actually animate while moving")
        try assertSamePose(reference, attacking)
    }

    func testDeathAndRespawnClearAttackLayer() throws {
        let game = ArenaGame(mode: .teamFight, entrants: [
            .init(name: "游侠", brawler: .ranger, isBot: false, team: 0),
            .init(name: "骑士", brawler: .knight, isBot: true, team: 1)
        ], seed: 1)
        var fighter = game.fighters[0]
        let reference = ArenaAvatar(brawler: .ranger, color: .blue, isMe: false, decorated: false)
        let revived = ArenaAvatar(brawler: .ranger, color: .blue, isMe: false, decorated: false)
        revived.attack()
        let dt: Float = 1 / 60
        for frame in 0..<240 {
            reference.update(game.fighters[0], visible: true, translucent: false, cheering: false, dt: dt, clock: Double(frame) / 60)
            fighter.alive = frame >= 120
            revived.update(fighter, visible: true, translucent: false, cheering: false, dt: dt, clock: Double(frame) / 60)
            if frame == 119 { XCTAssertTrue(revived.node.isHidden) }
        }
        XCTAssertFalse(revived.node.isHidden)
        try assertSamePose(reference, revived)
    }

    func testStoppingWorldClearsHeldAndQueuedInput() {
        let controller = ArenaController(setup: .init(mode: .teamFight, brawler: .ranger, name: "测试"), seed: 7)
        controller.advance(ArenaController.introLength + 0.1)
        let view = ArenaWorldView(controller: controller)
        let position = controller.mine.pos
        let ammo = controller.mine.ammo
        controller.move = V2(1, 0)
        controller.aiming = V2(1, 0)
        controller.fire(V2(1, 0))
        view.stop()
        view.stop() // teardown and background notifications may both stop it
        XCTAssertFalse(view.rendersContinuously)
        XCTAssertFalse(view.isPlaying)
        XCTAssertEqual(controller.move, .zero)
        XCTAssertNil(controller.aiming)
        controller.advance(ArenaController.step)
        XCTAssertEqual(controller.mine.pos, position)
        XCTAssertEqual(controller.mine.ammo, ammo)
    }

    private func assertSamePose(_ reference: ArenaAvatar, _ actual: ArenaAvatar) throws {
        for name in ["spine", "chest", "upperarm.r", "lowerarm.r"] {
            let expected = try XCTUnwrap(reference.node.childNode(withName: name, recursively: true))
            let result = try XCTUnwrap(actual.node.childNode(withName: name, recursively: true))
            for column in 0..<4 {
                XCTAssertLessThan(simd_length(expected.simdTransform[column] - result.simdTransform[column]), 0.0001, name)
            }
        }
    }

    func testPoseBuffersRestoreUnaffectedBonesBetweenLayers() {
        let rest = GLTFModel.Pose(translation: [.zero, SIMD3(1, 2, 3)],
                                 rotation: [simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)],
                                 scale: [SIMD3(repeating: 1), SIMD3(repeating: 1)])
        var pose = GLTFModel.Pose(translation: [], rotation: [], scale: [])
        pose.reset(from: rest)
        pose.translation[1] = SIMD3(8, 9, 10)
        pose.scale[0] = SIMD3(repeating: 2)
        pose.reset(from: rest)
        XCTAssertEqual(pose.translation, rest.translation)
        XCTAssertEqual(pose.scale, rest.scale)
        XCTAssertEqual(rest.translation[1], SIMD3(1, 2, 3))
    }
}

