import XCTest
@testable import ShiftCore

final class BoneSamplerTests: XCTestCase {
    func testMixStaysFinite() {
        let samples: [BoneSampler.Quat] = [
            .init(x: 0, y: 0, z: 0, w: 0),
            .init(x: .nan, y: 0, z: 0, w: 1),
            .init(x: .infinity, y: .nan, z: 0, w: 1),
            .init(x: 1, y: 0, z: 0, w: 0),
            .init(x: -1, y: 0, z: 0, w: 0),
            .identity,
            .init(x: 0.2, y: -0.4, z: 0.1, w: 0.8),
        ]
        let times: [Float] = [.nan, -.infinity, .infinity, -1, 0, 0.25, 0.5, 1, 2]
        for a in samples {
            for b in samples {
                for t in times {
                    let q = BoneSampler.mix(a, b, t)
                    XCTAssertTrue(finite(q), "mix \(a) \(b) t=\(t) -> \(q)")
                }
            }
        }
    }

    func testExaggeratePushesPastTheClipAndStaysFinite() {
        let rest = BoneSampler.Quat.identity
        let pose = BoneSampler.Quat(x: 0, y: 0.25, z: 0, w: 0.95)
        let same = BoneSampler.exaggerate(rest, pose, 1)
        let bigger = BoneSampler.exaggerate(rest, pose, 1.6)
        let still = BoneSampler.exaggerate(rest, rest, 1.8)
        XCTAssertTrue(finite(same) && finite(bigger) && finite(still))
        XCTAssertEqual(still.w, 1, accuracy: 0.001)
        XCTAssertGreaterThan(abs(bigger.y), abs(same.y))
        let broken = BoneSampler.exaggerate(.init(x: .nan, y: 0, z: 0, w: 1), pose, .infinity)
        XCTAssertTrue(finite(broken))
    }

    func testShortAndWildChannelsDoNotTrap() {
        var translation = [BoneSampler.Vec3](repeating: .zero, count: 2)
        var rotation = [BoneSampler.Quat](repeating: .identity, count: 2)
        var scale = [BoneSampler.Vec3](repeating: .one, count: 2)
        let channels = [
            BoneSampler.Channel(node: 0, path: .rotation, times: [0, 1], values: [0, 0, 0, 1], step: false),
            BoneSampler.Channel(node: 99, path: .rotation, times: [0, 0.5, 1], values: [0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1], step: false),
            BoneSampler.Channel(node: 1, path: .translation, times: [0, 1], values: [1, 2, 3], step: false),
            BoneSampler.Channel(node: 0, path: .scale, times: [], values: [], step: false),
            BoneSampler.Channel(node: -1, path: .rotation, times: [0], values: [0, 0, 0, 1], step: true),
            BoneSampler.Channel(node: 0, path: .translation, times: [Float.nan, 1], values: [.nan, 0, 0, 1, 0, 0], step: false),
        ]
        for step in 0...60 {
            BoneSampler.sample(Float(step) / 30, channels, translation: &translation, rotation: &rotation, scale: &scale)
        }
        XCTAssertTrue(rotation.allSatisfy(finite))
        XCTAssertEqual(translation[0], .zero)
    }

    func testKnownRotationLandsOnTheSecondKey() {
        var translation = [BoneSampler.Vec3](repeating: .zero, count: 1)
        var rotation = [BoneSampler.Quat.identity]
        var scale = [BoneSampler.Vec3](repeating: .one, count: 1)
        let channel = BoneSampler.Channel(node: 0, path: .rotation, times: [0, 1],
                                           values: [0, 0, 0, 1, 0, 0, 0, 1], step: true)
        BoneSampler.sample(1, [channel], translation: &translation, rotation: &rotation, scale: &scale)
        XCTAssertEqual(rotation[0].w, 1, accuracy: 0.001)
    }

    private func finite(_ q: BoneSampler.Quat) -> Bool {
        q.x.isFinite && q.y.isFinite && q.z.isFinite && q.w.isFinite
    }
}
