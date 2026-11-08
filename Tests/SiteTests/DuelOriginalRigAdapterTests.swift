import XCTest
import SceneKit
@testable import ShiftReminder

@MainActor
final class DuelOriginalRigAdapterTests: XCTestCase {
    func testBothAdaptersSampleAllSourceFramesWithoutAffectingOtherInstances() throws {
        for identity in DuelOriginalRigAsset.Identity.allCases {
            let url = try XCTUnwrap(DuelOriginalRigAsset.bundledURL(for: identity))
            let asset = try DuelOriginalRigAsset(url: url, identity: identity)
            XCTAssertEqual(DuelOriginalRigAsset.skeletonNames.count, 64)
            let player = DuelOriginalRigInstance(asset), untouched = DuelOriginalRigInstance(asset)
            let initial = untouched.instance.nodes.map(\.simdTransform)
            for clip in DuelOriginalRigReview.Clip.allCases {
                for frame in 0..<clip.frameCount {
                    let selection = DuelOriginalRigReview.Selection(clip: clip, sourceFrame: frame)
                    player.apply(selection)
                    let data = try XCTUnwrap(asset.model.clips[clip.rawValue])
                    let start = try XCTUnwrap(data.channels.compactMap { $0.times.first }.min())
                    var direct = asset.model.restPose
                    data.sample(at: selection.assetTime(start: start, end: data.duration), into: &direct)
                    for index in asset.model.animated {
                        XCTAssertEqual(player.instance.nodes[index].simdTransform, direct.transform(index))
                    }
                }
            }
            XCTAssertEqual(untouched.instance.nodes.map(\.simdTransform), initial)
            // Revisit an earlier pose after another clip, then scrub backwards.
            player.apply(.init(clip: .jab, sourceFrame: 3))
            let before = player.instance.nodes.map(\.simdTransform)
            player.apply(.init(clip: .spinStrike, phase: 1))
            player.apply(.init(clip: .jab, sourceFrame: 3))
            XCTAssertEqual(player.instance.nodes.map(\.simdTransform), before)
        }
    }

    func testIdentityMismatchFailsBeforeDecoding() throws {
        let liu = try XCTUnwrap(DuelOriginalRigAsset.bundledURL(for: .liu))
        XCTAssertThrowsError(try DuelOriginalRigAsset(url: liu, identity: .sun)) { error in
            guard case DuelOriginalRigAsset.AssetError.integrity = error else {
                return XCTFail("Expected an integrity failure, got \(error)")
            }
        }
    }
}
