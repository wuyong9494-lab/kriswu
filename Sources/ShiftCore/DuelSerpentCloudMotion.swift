import Foundation

/// Actual FK of the original virtual cloud. The resource loader authenticates
/// the binding JSON and GLB bytes before decoding this structural contract.
/// No mesh exists in the source ModelObject; particles attach to these nodes.
public struct DuelSerpentCloudMotion: Equatable, Codable, Sendable {
    public struct Sample: Equatable, Codable, Sendable {
        public let root, left, right, top, bottom: DuelWeaponPoint
        var points: [DuelWeaponPoint] { [root, left, right, top, bottom] }
    }
    public let schema, modelSHA256, motionSHA256, bonesSHA256, animation, coordinates: String
    public let modelBytes, lastSampleTick, loopEndEventTick, loopPeriodTicks: Int
    public let samples: [Sample]
    public enum Failure: Error { case identity, samples }

    public func validate() throws {
        guard schema == "d13-cloud-motion-binding-v1",
              modelSHA256 == "b6c0f8996645390d68a262661eb2c29d1251fb81d847e682bf8b7b2190d52a35",
              modelBytes == 26_108,
              motionSHA256 == "474b609e89df1a9756a6aa573bb6bc98590329fae763073e997cb2ae0a57da95",
              bonesSHA256 == "06347f1c97846e9678d2c457f28161628ea767cbe4077e45598086f910c1075c",
              animation == "D13_Poison_Bomb_Cloud_Model_Attack",
              coordinates == "source-centimeters-z-converted",
              lastSampleTick == 300, loopEndEventTick == 292, loopPeriodTicks == 293
        else { throw Failure.identity }
        guard samples.count == 301, let first = samples.first,
              samples.allSatisfy({ $0 == first }), first.points.allSatisfy({ point in
                  [point.x, point.y, point.z].allSatisfy { $0.isFinite && abs($0) <= 100_000 }
              }) else { throw Failure.samples }
    }

    /// Original loop flags its End at tick 292 and resets on the next step.
    /// All 151 original array-zero poses were measured as equal. Retaining the
    /// real clock still matters for source events and future presentation.
    public func sample(atAge age: Int) -> Sample? {
        guard age >= 0, loopPeriodTicks == 293, samples.count == 301 else { return nil }
        return samples[age % loopPeriodTicks]
    }

    public func frame(id: UInt64, bornAt: Int, alignedRootX: Double,
                      direction: Int, liveTick: Int) -> DuelSerpentRainRuntime.CloudFrame? {
        guard bornAt >= 0, liveTick >= bornAt, [-1, 1].contains(direction),
              alignedRootX.isFinite, abs(alignedRootX) <= 10_000_000,
              let sample = sample(atAge: liveTick - bornAt), let first = samples.first else { return nil }
        let rootX = alignedRootX + (sample.root.x - first.root.x) * Double(direction)
        guard rootX.isFinite && abs(rootX) <= 10_000_000 else { return nil }
        return .init(id: id, liveTick: liveTick, rootX: rootX)
    }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        for value in [schema, modelSHA256, motionSHA256, bonesSHA256, animation, coordinates] {
            try writer.string(value)
        }
        for value in [modelBytes, lastSampleTick, loopEndEventTick, loopPeriodTicks] { try writer.int(value) }
        // validate() proved every pose equal. Encode the one actual pose rather
        // than rehashing 301 duplicate poses for every authoritative state.
        try writer.int(samples.count)
        if let first = samples.first {
            for p in first.points { try writer.double(p.x); try writer.double(p.y); try writer.double(p.z) }
        }
    }
}
