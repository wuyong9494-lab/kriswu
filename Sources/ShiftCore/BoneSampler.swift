import Foundation
import simd

/// 骨骼动画采样。不调用 simd_slerp：iOS 27 上那个函数会进 atan2，再按一个不存在的地址读内存（SIGBUS）。
public enum BoneSampler {
    public struct Channel: Sendable {
        public enum Path: Sendable { case translation, rotation, scale }
        public var node: Int
        public var path: Path
        public var times: [Float]
        public var values: [Float]
        public var step: Bool

        public init(node: Int, path: Path, times: [Float], values: [Float], step: Bool) {
            self.node = node
            self.path = path
            self.times = times
            self.values = values
            self.step = step
        }
    }

    public static func unit(_ q: simd_quatf) -> simd_quatf {
        let x = q.vector.x, y = q.vector.y, z = q.vector.z, w = q.vector.w
        guard x.isFinite, y.isFinite, z.isFinite, w.isFinite else { return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) }
        let length = (x * x + y * y + z * z + w * w).squareRoot()
        guard length.isFinite, length > 1e-6 else { return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) }
        return simd_quatf(ix: x / length, iy: y / length, iz: z / length, r: w / length)
    }

    public static func mix(_ a: simd_quatf, _ b: simd_quatf, _ t: Float) -> simd_quatf {
        let from = unit(a)
        var to = unit(b)
        guard t.isFinite else { return from }
        if t <= 0 { return from }
        if t >= 1 { return to }
        let dot = from.vector.x * to.vector.x + from.vector.y * to.vector.y + from.vector.z * to.vector.z + from.vector.w * to.vector.w
        if dot < 0 { to = simd_quatf(vector: -to.vector) }
        let s = 1 - t
        return unit(simd_quatf(ix: from.vector.x * s + to.vector.x * t,
                               iy: from.vector.y * s + to.vector.y * t,
                               iz: from.vector.z * s + to.vector.z * t,
                               r: from.vector.w * s + to.vector.w * t))
    }

    /// 按时间把通道写进姿势。关键帧不够、节点编号超出、数值不是有限数，都跳过，不读越界。
    public static func sample(_ time: Float,
                              _ channels: [Channel],
                              translation: inout [SIMD3<Float>],
                              rotation: inout [simd_quatf],
                              scale: inout [SIMD3<Float>]) {
        let time = time.isFinite ? time : 0
        for channel in channels {
            let times = channel.times
            let last = times.count - 1
            var k0 = 0
            var k1 = 0
            var fraction: Float = 0
            if last > 0, times.indices.contains(0), time > times[0] {
                if time >= times[last] {
                    k0 = last
                    k1 = last
                } else {
                    var low = 0
                    var high = last
                    while high - low > 1 {
                        let middle = (low + high) / 2
                        if times[middle] <= time { low = middle } else { high = middle }
                    }
                    k0 = low
                    k1 = high
                    let span = times[k1] - times[k0]
                    fraction = channel.step || !(span > 0) ? 0 : (time - times[k0]) / span
                }
            }
            if !fraction.isFinite { fraction = 0 }
            fraction = min(max(fraction, 0), 1)
            let v = channel.values
            switch channel.path {
            case .rotation:
                guard let a = quat(v, k0), let b = quat(v, k1), rotation.indices.contains(channel.node) else { continue }
                rotation[channel.node] = fraction > 0 ? mix(a, b, fraction) : unit(a)
            case .translation, .scale:
                guard let value0 = vec3(v, k0), translation.indices.contains(channel.node), scale.indices.contains(channel.node) else { continue }
                var value = value0
                if fraction > 0, let value1 = vec3(v, k1) {
                    value += (value1 - value) * fraction
                }
                if channel.path == .translation {
                    translation[channel.node] = value
                } else {
                    scale[channel.node] = value
                }
            }
        }
    }

    private static func quat(_ v: [Float], _ key: Int) -> simd_quatf? {
        guard key >= 0, key < 1_000_000 else { return nil }
        let base = key * 4
        guard base >= 0, base + 3 < v.count else { return nil }
        return simd_quatf(ix: v[base], iy: v[base + 1], iz: v[base + 2], r: v[base + 3])
    }

    private static func vec3(_ v: [Float], _ key: Int) -> SIMD3<Float>? {
        guard key >= 0, key < 1_000_000 else { return nil }
        let base = key * 3
        guard base >= 0, base + 2 < v.count else { return nil }
        let value = SIMD3(v[base], v[base + 1], v[base + 2])
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite else { return nil }
        return value
    }
}
