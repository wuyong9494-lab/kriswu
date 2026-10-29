import XCTest
import SceneKit
import simd
@testable import ShiftReminder

@MainActor
final class ArenaRangerTests: XCTestCase {
    func testIndependentAssetImportsAllGameplayActionsAndAnchors() throws {
        let look = BrawlerLook.of(.ranger)
        XCTAssertEqual(look.file, "Ranger_Original.glb")
        XCTAssertTrue(look.authored)
        let model = try XCTUnwrap(ArenaModels.shared.character(.ranger))
        for name in look.clips { XCTAssertNotNil(model.clips[name], name) }
        for name in ["spine", "chest", "head", "handslot.r", "muzzle", "foot.l", "foot.r"] {
            XCTAssertNotNil(model.node(named: name), name)
        }
        let instance = model.instantiate()
        XCTAssertEqual(instance.materials.count, 1)
        var skinners = 0
        instance.root.enumerateChildNodes { node, _ in
            if let skin = node.skinner {
                skinners += 1
                XCTAssertEqual(skin.bones.count, 22)
            }
        }
        XCTAssertEqual(skinners, 1)
        XCTAssertLessThan(model.animated.count, 22, "Static anchors should not be sampled every frame")
    }

    func testShotMuzzleMatchesImmediateAimWithoutMovingCollisionBody() throws {
        let game = ArenaGame(mode: .teamFight, entrants: [
            .init(name: "游侠", brawler: .ranger, isBot: false, team: 0),
            .init(name: "骑士", brawler: .knight, isBot: true, team: 1)
        ], seed: 1)
        var fighter = game.fighters[0]
        fighter.pos = V2(5, 5)
        fighter.facing = V2(0, 1)
        let avatar = ArenaAvatar(brawler: .ranger, color: .blue, isMe: true, decorated: false)
        avatar.update(fighter, visible: true, translucent: false, cheering: false, dt: 0, clock: 0)
        fighter.facing = V2(1, 0)
        avatar.update(fighter, visible: true, translucent: false, cheering: false, dt: 1 / 60, clock: 1 / 60)
        avatar.attack()
        let muzzle = try XCTUnwrap(avatar.muzzlePosition)
        XCTAssertGreaterThan(muzzle.x, 5.7)
        XCTAssertEqual(muzzle.z, 5, accuracy: 0.05)
        XCTAssertEqual(muzzle.y, 1.34 * ArenaAvatar.scale, accuracy: 0.03)
        XCTAssertEqual(avatar.node.simdPosition, SIMD3<Float>(5, 0, 5))
    }

    func testEveryOriginalClipProducesFiniteSkinnedTransforms() throws {
        let model = try XCTUnwrap(ArenaModels.shared.character(.ranger))
        var pose = model.restPose
        for clip in model.clips.values {
            for step in 0...60 {
                pose.reset(from: model.restPose)
                clip.sample(at: clip.duration * Float(step) / 60, into: &pose)
                for index in model.animated {
                    let matrix = pose.transform(index)
                    for column in 0..<4 {
                        let v = matrix[column]
                        XCTAssertTrue(v.x.isFinite && v.y.isFinite && v.z.isFinite && v.w.isFinite, clip.name)
                    }
                }
            }
        }
    }
}
