import XCTest
import SceneKit
import simd
@testable import ShiftReminder

@MainActor
final class ArenaAnimationTests: XCTestCase {
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
