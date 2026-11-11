import SceneKit
import simd

/// Cached influence bounds, built AFTER instance-only bind corrections. The
/// convex hull of transformed joint boxes contains linear-blend skinning. No
/// vertices are skinned on draw; current bones include recovery and detachment.
@MainActor
final class DuelDisplayedSkinBounds {
    enum Failure: Error, Equatable { case unsupportedGeometry, invalidSkin, invalidTransform, intersectsEye }
    private struct Box {
        var low = SIMD3<Float>(repeating: .infinity)
        var high = SIMD3<Float>(repeating: -.infinity)
        mutating func include(_ p: SIMD3<Float>) { low = simd_min(low, p); high = simd_max(high, p) }
        var corners: [SIMD3<Float>] {
            (0..<8).map { i in SIMD3(i & 1 == 0 ? low.x : high.x,
                i & 2 == 0 ? low.y : high.y, i & 4 == 0 ? low.z : high.z) }
        }
    }
    private struct Influence { let bone: SCNNode; let box: Box }
    private struct Part {
        let holder: SCNNode
        let skin: SCNSkinner
        let influences: [Influence]
        let sumLow: Float
        let sumHigh: Float
    }
    private let parts: [Part]

    init(root: SCNNode) throws {
        var holders: [SCNNode] = []
        root.enumerateChildNodes { node, _ in if node.geometry != nil { holders.append(node) } }
        guard !holders.isEmpty else { throw Failure.unsupportedGeometry }
        parts = try holders.map { holder in
            guard let skin = holder.skinner, let geometry = skin.baseGeometry,
                  let positions = geometry.sources(for: .vertex).first,
                  let binds = skin.boneInverseBindTransforms, binds.count == skin.bones.count,
                  !binds.isEmpty,
                  SCNMatrix4EqualToMatrix4(skin.baseGeometryBindTransform, SCNMatrix4Identity)
            else { throw Failure.unsupportedGeometry }
            let indices = skin.boneIndices, weights = skin.boneWeights
            guard positions.usesFloatComponents, positions.bytesPerComponent == 4,
                  positions.componentsPerVector == 3, positions.vectorCount > 0,
                  weights.usesFloatComponents, weights.bytesPerComponent == 4,
                  !indices.usesFloatComponents, indices.bytesPerComponent == 2,
                  weights.componentsPerVector == 4, indices.componentsPerVector == 4,
                  weights.vectorCount == positions.vectorCount, indices.vectorCount == positions.vectorCount
            else { throw Failure.unsupportedGeometry }
            for source in [positions, indices, weights] {
                guard source.dataOffset >= 0, source.dataStride >= source.componentsPerVector * source.bytesPerComponent,
                      source.dataOffset + (source.vectorCount - 1) * source.dataStride
                        + source.componentsPerVector * source.bytesPerComponent <= source.data.count
                else { throw Failure.unsupportedGeometry }
            }
            let matrices = binds.map { SCNMatrix4ToMat4($0.scnMatrix4Value) }
            guard matrices.allSatisfy(Self.affine) else { throw Failure.invalidTransform }
            var boxes = [Box](repeating: Box(), count: binds.count)
            var used = Set<Int>(), low: Float = 1, high: Float = 1
            // Data copies are obtained once per mesh, never per display frame.
            let pd = positions.data, id = indices.data, wd = weights.data
            try pd.withUnsafeBytes { (pb: UnsafeRawBufferPointer) in
                try id.withUnsafeBytes { (ib: UnsafeRawBufferPointer) in
                    try wd.withUnsafeBytes { (wb: UnsafeRawBufferPointer) in
                        func scalar(_ b: UnsafeRawBufferPointer, _ o: Int) -> Float {
                            Float(bitPattern: UInt32(littleEndian: b.loadUnaligned(fromByteOffset: o, as: UInt32.self)))
                        }
                        for v in 0..<positions.vectorCount {
                            let po = positions.dataOffset + v * positions.dataStride
                            let p = SIMD4(scalar(pb, po), scalar(pb, po + 4), scalar(pb, po + 8), 1)
                            guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { throw Failure.invalidSkin }
                            var sum: Double = 0
                            for c in 0..<4 {
                                let joint = Int(UInt16(littleEndian: ib.loadUnaligned(fromByteOffset:
                                    indices.dataOffset + v * indices.dataStride + c * 2, as: UInt16.self)))
                                let w = scalar(wb, weights.dataOffset + v * weights.dataStride + c * 4)
                                guard w.isFinite, w >= 0, matrices.indices.contains(joint) else { throw Failure.invalidSkin }
                                sum += Double(w)
                                if w > 0 {
                                    let q = matrices[joint] * p
                                    boxes[joint].include(SIMD3(q.x, q.y, q.z)); used.insert(joint)
                                }
                            }
                            guard sum.isFinite, sum > 0 else { throw Failure.invalidSkin }
                            low = min(low, Float(sum).nextDown); high = max(high, Float(sum).nextUp)
                        }
                    }
                }
            }
            // Include both raw and normalized weights without assuming exact
            // float sums. Raw skinning is sumWeights * the normalized convex
            // combination, including each bone's world translation.
            return Part(holder: holder, skin: skin,
                influences: used.sorted().map { Influence(bone: skin.bones[$0], box: boxes[$0]) },
                sumLow: low, sumHigh: high)
        }
    }

    private static func affine(_ m: simd_float4x4) -> Bool {
        let columns = [m.columns.0, m.columns.1, m.columns.2, m.columns.3]
        return columns.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w.isFinite }
            && abs(m.columns.0.w) < 0.000001 && abs(m.columns.1.w) < 0.000001
            && abs(m.columns.2.w) < 0.000001 && abs(m.columns.3.w - 1) < 0.000001
    }
    private func visible(_ node: SCNNode) -> Bool {
        var current: SCNNode? = node
        while let n = current { if n.isHidden || n.opacity == 0 { return false }; current = n.parent }
        return true
    }

    /// Camera-local conservative points, with explicit failure rather than a
    /// claimed fit for unknown geometry or a box crossing the eye/near plane.
    func cameraPoints(camera: SCNNode) throws -> [SIMD3<Float>] {
        let view = simd_inverse(camera.simdWorldTransform)
        guard Self.affine(view) else { throw Failure.invalidTransform }
        var points: [SIMD3<Float>] = []
        for part in parts where visible(part.holder) {
            guard part.holder.skinner === part.skin else { throw Failure.invalidSkin }
            for influence in part.influences {
                let world = influence.bone.simdWorldTransform
                guard Self.affine(world) else { throw Failure.invalidTransform }
                for corner in influence.box.corners {
                    let p = world * SIMD4(corner.x, corner.y, corner.z, 1)
                    for sum in [part.sumLow, part.sumHigh] {
                        let q = view * SIMD4(p.x * sum, p.y * sum, p.z * sum, 1)
                        guard q.x.isFinite, q.y.isFinite, q.z.isFinite else { throw Failure.invalidTransform }
                        points.append(SIMD3(q.x, q.y, q.z))
                    }
                }
            }
        }
        return points
    }

    static func verticalFOV(points: [SIMD3<Float>], aspect: Double, minimum: Double,
                            near: Double, inset: Double = 1) throws -> Double {
        guard aspect.isFinite, aspect > 0, minimum.isFinite, minimum > 0, minimum < 180, near.isFinite, near > 0,
              inset > 0, inset <= 1 else { throw Failure.invalidTransform }
        var tangent = tan(minimum * .pi / 360)
        for p in points {
            guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { throw Failure.invalidTransform }
            let depth = -Double(p.z)
            guard depth > near else { throw Failure.intersectsEye }
            let horizontalDenominator = depth * aspect * inset, verticalDenominator = depth * inset
            guard horizontalDenominator.isFinite, horizontalDenominator > 0,
                  verticalDenominator.isFinite, verticalDenominator > 0 else { throw Failure.invalidTransform }
            let horizontal = abs(Double(p.x)) / horizontalDenominator
            let vertical = abs(Double(p.y)) / verticalDenominator
            guard horizontal.isFinite, vertical.isFinite else { throw Failure.invalidTransform }
            tangent = max(tangent, horizontal, vertical)
        }
        // No distance fallback: a near-plane/eye crossing is not repairable by
        // an optical FOV and must remain a reported validation gap.
        let fov = 2 * atan(tangent) * 180 / .pi
        guard tangent.isFinite, fov.isFinite, fov > 0, fov < 180, Float(fov) > 0, Float(fov) < 180 else { throw Failure.invalidTransform }
        return fov
    }
}
