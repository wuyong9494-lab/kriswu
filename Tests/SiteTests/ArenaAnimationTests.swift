import XCTest
import SceneKit
import simd
@testable import ShiftReminder

@MainActor
final class ArenaAnimationTests: XCTestCase {
    func testVisualSampleKeepsSimulationIdenticalAndCaptureFrozen() {
        let old = ArenaController(setup: .init(mode: .zone, brawler: .ranger, name: "test", benchmark: true, benchmarkStill: true))
        let sample = ArenaController(setup: .init(mode: .zone, brawler: .ranger, name: "test", benchmark: true, benchmarkStill: true, sampleMap: true))
        XCTAssertEqual(old.benchmarkSteps, 900)
        XCTAssertEqual(old.game.map.id, sample.game.map.id)
        XCTAssertEqual(old.game.fighters.map(\.pos), sample.game.fighters.map(\.pos))
        XCTAssertEqual(old.game.fighters.map(\.health), sample.game.fighters.map(\.health))
        XCTAssertEqual(old.game.projectiles.count, sample.game.projectiles.count)
        sample.advance(10)
        XCTAssertEqual(sample.benchmarkSteps, 900)
        XCTAssertEqual(old.game.time, sample.game.time)
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
