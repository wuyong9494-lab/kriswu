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

    func testShowcaseCanSwitchBetweenOriginalAndSampleWithoutStaleModel() {
        let view = ArenaShowcaseView(brawler: .ranger)
        defer { view.stop() }
        func jointCounts() -> [Int] {
            var counts: [Int] = []
            view.scene?.rootNode.enumerateChildNodes { node, _ in
                if let skinner = node.skinner { counts.append(skinner.bones.count) }
            }
            return counts
        }
        XCTAssertTrue(jointCounts().contains(22))
        view.show(.ranger, qualitySample: true)
        XCTAssertTrue(jointCounts().contains(27))
        XCTAssertFalse(jointCounts().contains(22))
        view.show(.ranger)
        XCTAssertTrue(jointCounts().contains(22))
        XCTAssertFalse(jointCounts().contains(27))
    }

    func testHarborGrassStaysInsideTileAndBelowStandingCharacter() {
        let (low, high) = ArenaHarborArt.bush.boundingBox
        XCTAssertGreaterThanOrEqual(low.x, -0.5)
        XCTAssertLessThanOrEqual(high.x, 0.5)
        XCTAssertGreaterThanOrEqual(low.z, -0.5)
        XCTAssertLessThanOrEqual(high.z, 0.5)
        XCTAssertGreaterThanOrEqual(low.y, 0)
        XCTAssertLessThanOrEqual(high.y, 0.65)
    }

    func testHarborArtPlacesSolidsOnlyOnDeclaredWallCells() throws {
        let map = ArenaMap.twinGates
        let walls = ArenaHarborArt.walls(map)
        var expected = 0
        for y in 0..<map.height {
            for x in 0..<map.width where map.tile(x, y) == .wall {
                expected += 1
                let cell = try XCTUnwrap(walls.childNode(withName: "wall-\(x)-\(y)", recursively: false))
                XCTAssertEqual(cell.position.x, Float(x) + 0.5)
                XCTAssertEqual(cell.position.z, Float(y) + 0.5)
                let (low, high) = cell.boundingBox
                XCTAssertGreaterThanOrEqual(low.x, -0.501)
                XCTAssertLessThanOrEqual(high.x, 0.501)
                XCTAssertGreaterThanOrEqual(low.z, -0.501)
                XCTAssertLessThanOrEqual(high.z, 0.501)
            }
        }
        XCTAssertEqual(walls.childNodes.count, expected)
    }

    func testSampleBoltsKeepTeamSilhouetteAndActualRadiusAcrossStrengths() throws {
        for ally in [true, false] {
            for strength in 0...2 {
                let radius: CGFloat = strength == 0 ? 0.22 : 0.32
                let bolt = ArenaSampleBolt.make(radius: radius, ally: ally, isSuper: strength > 0,
                                               hyper: strength == 2, height: 0.6)
                let shell = try XCTUnwrap(bolt.childNode(withName: "team-shell", recursively: true))
                let color = try XCTUnwrap(shell.geometry?.firstMaterial?.diffuse.contents as? UIColor)
                XCTAssertEqual(color, ally ? ArenaPalette.allyShot : ArenaPalette.enemyShot)
                let footprint = try XCTUnwrap(bolt.childNode(withName: "collision-radius", recursively: true))
                let tube = try XCTUnwrap(footprint.geometry as? SCNTube)
                XCTAssertEqual(tube.outerRadius, radius, accuracy: 0.0001)
                XCTAssertEqual(footprint.position.y + 0.6, 0.04, accuracy: 0.0001)
                XCTAssertNotNil(bolt.childNode(withName: ally ? "ally-inner-tick" : "enemy-forward-notch", recursively: true))
                bolt.enumerateChildNodes { node, _ in
                    XCTAssertTrue(node.particleSystems?.isEmpty ?? true)
                    for material in node.geometry?.materials ?? [] {
                        XCTAssertNotEqual(material.blendMode, .add, "Stacking shots must not add a white halo")
                    }
                }
            }
        }
    }

    func testFaceSampleUsesSeparateAssetAndSamplesFacialChannels() throws {
        XCTAssertEqual(BrawlerLook.of(.ranger).file, "Ranger_Original.glb")
        XCTAssertEqual(BrawlerLook.of(.ranger, qualitySample: true).file, "Ranger_FaceSample.glb")
        let model = try XCTUnwrap(ArenaModels.shared.character(.ranger, qualitySample: true))
        let eye = try XCTUnwrap(model.node(named: "eye.r"))
        let brow = try XCTUnwrap(model.node(named: "brow.r"))
        let mouth = try XCTUnwrap(model.node(named: "mouth"))
        var pose = model.restPose
        let idle = try XCTUnwrap(model.clips["Ranger_Idle"])
        idle.sample(at: idle.duration * 0.72, into: &pose)
        XCTAssertLessThan(pose.scale[eye].y, 0.35, "Blink must survive GLB import")
        pose.reset(from: model.restPose)
        let shot = try XCTUnwrap(model.clips["Ranger_Shoot"])
        shot.sample(at: 0, into: &pose)
        XCTAssertGreaterThan(simd_length(pose.rotation[brow].vector - model.restPose.rotation[brow].vector), 0.02)
        pose.reset(from: model.restPose)
        let cheer = try XCTUnwrap(model.clips["Cheer"])
        cheer.sample(at: cheer.duration * 0.5, into: &pose)
        XCTAssertGreaterThan(simd_distance(pose.translation[mouth], model.restPose.translation[mouth]), 0.01)
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
        XCTAssertGreaterThan(high, 1.13)
        XCTAssertLessThan(high, 1.29, "Ranger must not become a giant relative to the existing map and roster")
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

