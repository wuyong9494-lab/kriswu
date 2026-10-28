import XCTest
import simd
@testable import ShiftCore

final class BoneSamplerTests: XCTestCase {
    func testMixStaysFinite() {
        let samples: [simd_quatf] = [
            simd_quatf(ix: 0, iy: 0, iz: 0, r: 0),
            simd_quatf(ix: .nan, iy: 0, iz: 0, r: 1),
            simd_quatf(ix: .infinity, iy: .nan, iz: 0, r: 1),
            simd_quatf(ix: 1, iy: 0, iz: 0, r: 0),
            simd_quatf(ix: -1, iy: 0, iz: 0, r: 0),
            simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
            simd_quatf(ix: 0.2, iy: -0.4, iz: 0.1, r: 0.8),
        ]
        let times: [Float] = [.nan, -.infinity, .infinity, -1, 0, 0.25, 0.5, 1, 2]
        for a in samples {
            for b in samples {
                for t in times {
                    let q = BoneSampler.mix(a, b, t)
                    XCTAssertTrue(finite(q), "mix \(a.vector) \(b.vector) t=\(t) -> \(q.vector)")
                }
            }
        }
    }

    func testShortAndWildChannelsDoNotTrap() {
        var translation = [SIMD3<Float>](repeating: .zero, count: 2)
        var rotation = [simd_quatf](repeating: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), count: 2)
        var scale = [SIMD3<Float>](repeating: SIMD3(repeating: 1), count: 2)
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
        var translation = [SIMD3<Float>](repeating: .zero, count: 1)
        var rotation = [simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)]
        var scale = [SIMD3<Float>](repeating: SIMD3(repeating: 1), count: 1)
        let channel = BoneSampler.Channel(node: 0, path: .rotation, times: [0, 1],
                                           values: [0, 0, 0, 1, 0, 0, 0, 1], step: true)
        BoneSampler.sample(1, [channel], translation: &translation, rotation: &rotation, scale: &scale)
        XCTAssertEqual(rotation[0].real, 1, accuracy: 0.001)
    }

    private func finite(_ q: simd_quatf) -> Bool {
        q.vector.x.isFinite && q.vector.y.isFinite && q.vector.z.isFinite && q.vector.w.isFinite
    }
}
