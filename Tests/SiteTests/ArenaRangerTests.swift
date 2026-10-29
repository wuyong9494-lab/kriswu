import XCTest
import SceneKit
import simd
@testable import ShiftReminder

@MainActor
final class ArenaRangerTests: XCTestCase {
    func testShowcaseRefitsAfterPortraitToLandscapeTransition() throws {
        let view = ArenaShowcaseView(brawler: .ranger)
        defer { view.stop() }
        view.frame = CGRect(x: 0, y: 0, width: 260, height: 698)
        view.layoutSubviews()
        let portraitDistance = try XCTUnwrap(view.pointOfView).position.z
        view.frame = CGRect(x: 0, y: 0, width: 698, height: 260)
        view.layoutSubviews()
        let landscapeDistance = try XCTUnwrap(view.pointOfView).position.z
        XCTAssertTrue(landscapeDistance.isFinite)
        XCTAssertGreaterThan(landscapeDistance, 0)
        XCTAssertLessThan(landscapeDistance, portraitDistance,
                          "A portrait-width camera must not leave the landscape hero undersized")
        view.frame = CGRect(x: 0, y: 0, width: 260, height: 698)
        view.layoutSubviews()
        XCTAssertEqual(try XCTUnwrap(view.pointOfView).position.z, portraitDistance, accuracy: 0.001)
    }

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

    func testOriginalRangerFitsExistingWorldScaleAndGroundPlane() {
        let avatar = ArenaAvatar(brawler: .ranger, color: .blue, isMe: true, decorated: false)
        var low = Float.greatestFiniteMagnitude
        var high = -Float.greatestFiniteMagnitude
        avatar.node.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            let (a, b) = geometry.boundingBox
            for x in [a.x, b.x] { for y in [a.y, b.y] { for z in [a.z, b.z] {
                let point = node.simdConvertPosition(SIMD3(x, y, z), to: avatar.node)
                low = min(low, point.y)
                high = max(high, point.y)
            } } }
        }
        XCTAssertEqual(low, 0, accuracy: 0.002)
        XCTAssertGreaterThan(high, 1.42)
        XCTAssertLessThan(high, 1.60, "Ranger must not become a giant relative to the existing map and roster")
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
        XCTAssertEqual(muzzle.x - 5, 0.93 * ArenaAvatar.scale * BrawlerLook.rangerScale, accuracy: 0.03)
        XCTAssertEqual(muzzle.z, 5, accuracy: 0.05)
        XCTAssertEqual(muzzle.y, 1.34 * ArenaAvatar.scale * BrawlerLook.rangerScale, accuracy: 0.03)
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
