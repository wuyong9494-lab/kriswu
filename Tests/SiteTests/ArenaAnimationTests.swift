import XCTest
import simd
@testable import ShiftReminder

@MainActor
final class ArenaAnimationTests: XCTestCase {
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
