import Foundation

/// 骨骼动画采样。不用 simd_slerp：iOS 27 上那个函数会进 atan2，再按一个不存在的地址读内存（SIGBUS）。
/// 这里只用四个浮点数，Linux 上的单元测试和手机上的 App 走同一份代码。
public enum BoneSampler {
    public struct Quat: Equatable, Sendable {
        public var x, y, z, w: Float
        public init(x: Float, y: Float, z: Float, w: Float) {
            self.x = x
            self.y = y
            self.z = z
            self.w = w
        }
        public static let identity = Quat(x: 0, y: 0, z: 0, w: 1)
    }

    public struct Vec3: Equatable, Sendable {
        public var x, y, z: Float
        public init(x: Float, y: Float, z: Float) {
            self.x = x
            self.y = y
            self.z = z
        }
        public static let zero = Vec3(x: 0, y: 0, z: 0)
        public static let one = Vec3(x: 1, y: 1, z: 1)
        public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
        public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
        public static func * (a: Vec3, k: Float) -> Vec3 { Vec3(x: a.x * k, y: a.y * k, z: a.z * k) }
    }

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

    public static func unit(_ q: Quat) -> Quat {
        guard q.x.isFinite, q.y.isFinite, q.z.isFinite, q.w.isFinite else { return .identity }
        let length = (q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w).squareRoot()
        guard length.isFinite, length > 1e-6 else { return .identity }
        return Quat(x: q.x / length, y: q.y / length, z: q.z / length, w: q.w / length)
    }

    public static func mix(_ a: Quat, _ b: Quat, _ t: Float) -> Quat {
        let from = unit(a)
        var to = unit(b)
        guard t.isFinite else { return from }
        if t <= 0 { return from }
        if t >= 1 { return to }
        let dot = from.x * to.x + from.y * to.y + from.z * to.z + from.w * to.w
        if dot < 0 { to = Quat(x: -to.x, y: -to.y, z: -to.z, w: -to.w) }
        let s = 1 - t
        return unit(Quat(x: from.x * s + to.x * t, y: from.y * s + to.y * t, z: from.z * s + to.z * t, w: from.w * s + to.w * t))
    }

    /// 把这段旋转相对静止姿势再推远一点。gain 为 1 时就是原来的姿势，1.5 大约再大一半。
    /// 不用 simd，避免 iOS 27 上 slerp 的崩溃。增益封在 1.8，骨头不会拧翻过去。
    public static func exaggerate(_ rest: Quat, _ pose: Quat, _ gain: Float) -> Quat {
        let from = unit(rest)
        var to = unit(pose)
        guard gain.isFinite else { return to }
        if gain <= 1 { return mix(from, to, max(gain, 0)) }
        let capped = min(gain, 1.8)
        let dot = from.x * to.x + from.y * to.y + from.z * to.z + from.w * to.w
        if dot < 0 { to = Quat(x: -to.x, y: -to.y, z: -to.z, w: -to.w) }
        let s = 1 - capped
        return unit(Quat(
            x: from.x * s + to.x * capped,
            y: from.y * s + to.y * capped,
            z: from.z * s + to.z * capped,
            w: from.w * s + to.w * capped
        ))
    }

    /// 关键帧不够、节点编号超出、数值不是有限数，都跳过，不读越界。
    public static func sample(_ time: Float,
                              _ channels: [Channel],
                              translation: inout [Vec3],
                              rotation: inout [Quat],
                              scale: inout [Vec3]) {
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
                    value = value + (value1 - value) * fraction
                }
                if channel.path == .translation {
                    translation[channel.node] = value
                } else {
                    scale[channel.node] = value
                }
            }
        }
    }

    private static func quat(_ v: [Float], _ key: Int) -> Quat? {
        guard key >= 0, key < 1_000_000 else { return nil }
        let base = key * 4
        guard base >= 0, base + 3 < v.count else { return nil }
        return Quat(x: v[base], y: v[base + 1], z: v[base + 2], w: v[base + 3])
    }

    private static func vec3(_ v: [Float], _ key: Int) -> Vec3? {
        guard key >= 0, key < 1_000_000 else { return nil }
        let base = key * 3
        guard base >= 0, base + 2 < v.count else { return nil }
        let value = Vec3(x: v[base], y: v[base + 1], z: v[base + 2])
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite else { return nil }
        return value
    }
}
