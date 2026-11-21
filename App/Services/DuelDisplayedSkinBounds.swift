import SceneKit
import simd

/// Cached geometry bounds, built AFTER instance-only bind corrections. The
/// convex hull of transformed joint boxes contains linear-blend skinning;
/// rigid meshes keep their own local vertex box and current holder transform.
/// No vertices are skinned on draw. Rigid personal heads are never omitted or
/// assigned invented weights to satisfy the skin path.
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
    // The bind-space box never changes after instance construction. Cache its
    // eight corners once rather than allocating them for every display callback.
    private struct Influence { let bone: SCNNode; let corners: [SIMD3<Float>] }
    private enum Binding {
        case skinned(SCNSkinner, [Influence], sumLow: Float, sumHigh: Float)
        case rigid([SIMD3<Float>])
        var pointCount: Int {
            switch self {
            case let .skinned(_, influences, _, _): return influences.count * 16
            case .rigid: return 16
            }
        }
    }
    private struct Part {
        let holder: SCNNode
        let geometry: SCNGeometry
        let binding: Binding
    }
    private let parts: [Part]
    private let pointCapacity: Int

    init(root: SCNNode) throws {
        var holders: [SCNNode] = root.geometry == nil ? [] : [root]
        root.enumerateChildNodes { node, _ in if node.geometry != nil { holders.append(node) } }
        guard !holders.isEmpty else { throw Failure.unsupportedGeometry }
        parts = try holders.map { holder in
            guard let visibleGeometry = holder.geometry, holder.morpher == nil else {
                throw Failure.unsupportedGeometry
            }
            guard let skin = holder.skinner else {
                // Cache the actual source vertex extent in this mesh's own
                // coordinate system. Its parent may be an animated head bone.
                let positions = try Self.positions(in: visibleGeometry)
                guard !GLTFModel.hasSkinBinding(on: holder) else { throw Failure.invalidSkin }
                guard visibleGeometry.sources(for: .boneWeights).isEmpty,
                      visibleGeometry.sources(for: .boneIndices).isEmpty,
                      SCNMatrix4EqualToMatrix4(holder.pivot, SCNMatrix4Identity) else {
                    throw Failure.unsupportedGeometry
                }
                var box = Box()
                try positions.data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                    for vertex in 0..<positions.vectorCount {
                        let offset = positions.dataOffset + vertex * positions.dataStride
                        func scalar(_ component: Int) -> Float {
                            Float(bitPattern: UInt32(littleEndian:
                                bytes.loadUnaligned(fromByteOffset: offset + component * 4, as: UInt32.self)))
                        }
                        let value = SIMD3(scalar(0), scalar(1), scalar(2))
                        guard value.x.isFinite, value.y.isFinite, value.z.isFinite else {
                            throw Failure.invalidTransform
                        }
                        box.include(value)
                    }
                }
                return Part(holder: holder, geometry: visibleGeometry, binding: .rigid(box.corners))
            }
            guard let geometry = skin.baseGeometry,
                  let sources = GLTFModel.skinSources(for: holder),
                  let binds = skin.boneInverseBindTransforms, binds.count == skin.bones.count,
                  !binds.isEmpty,
                  SCNMatrix4EqualToMatrix4(skin.baseGeometryBindTransform, SCNMatrix4Identity)
            else { throw Failure.unsupportedGeometry }
            let positions = try Self.positions(in: geometry)
            let indices = sources.indices, weights = sources.weights
            let influenceCount = weights.componentsPerVector
            guard weights.semantic == .boneWeights,
                  indices.semantic == .boneIndices,
                  weights.usesFloatComponents, weights.bytesPerComponent == 4,
                  (1...4).contains(influenceCount), !indices.usesFloatComponents,
                  [1, 2, 4].contains(indices.bytesPerComponent),
                  indices.componentsPerVector == influenceCount,
                  weights.vectorCount == positions.vectorCount, indices.vectorCount == positions.vectorCount
            else { throw Failure.unsupportedGeometry }
            for source in [indices, weights] { try Self.validateLayout(source) }
            let matrices = binds.map { simd_float4x4($0.scnMatrix4Value) }
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
                        // Read the exact source buffers retained when this
                        // holder's skinner was constructed. SceneKit's getter
                        // can be empty even for valid input. Do not infer a
                        // rigid skin, normalize weights or invent influences.
                        func jointIndex(_ offset: Int) -> Int {
                            switch indices.bytesPerComponent {
                            case 1:
                                return Int(ib.loadUnaligned(fromByteOffset: offset, as: UInt8.self))
                            case 2:
                                return Int(UInt16(littleEndian: ib.loadUnaligned(fromByteOffset: offset, as: UInt16.self)))
                            default:
                                return Int(UInt32(littleEndian: ib.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
                            }
                        }
                        for v in 0..<positions.vectorCount {
                            let po = positions.dataOffset + v * positions.dataStride
                            let p = SIMD4(scalar(pb, po), scalar(pb, po + 4), scalar(pb, po + 8), 1)
                            guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { throw Failure.invalidSkin }
                            var sum: Double = 0
                            for c in 0..<influenceCount {
                                let joint = jointIndex(indices.dataOffset + v * indices.dataStride
                                    + c * indices.bytesPerComponent)
                                let w = scalar(wb, weights.dataOffset + v * weights.dataStride + c * 4)
                                guard w.isFinite, (0...1).contains(w), matrices.indices.contains(joint) else { throw Failure.invalidSkin }
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
            let influences = used.sorted().map { Influence(bone: skin.bones[$0], corners: boxes[$0].corners) }
            return Part(holder: holder, geometry: visibleGeometry,
                        binding: .skinned(skin, influences, sumLow: low, sumHigh: high))
        }
        pointCapacity = parts.reduce(0) { $0 + $1.binding.pointCount }
    }

    private static func validateLayout(_ source: SCNGeometrySource) throws {
        let width = source.componentsPerVector * source.bytesPerComponent
        guard source.vectorCount > 0, source.dataOffset >= 0, source.dataOffset <= source.data.count,
              source.dataStride >= width, width > 0, width <= source.data.count - source.dataOffset,
              source.vectorCount - 1 <= (source.data.count - source.dataOffset - width) / source.dataStride
        else { throw Failure.unsupportedGeometry }
    }

    private static func positions(in geometry: SCNGeometry) throws -> SCNGeometrySource {
        guard let source = geometry.sources(for: .vertex).first,
              source.semantic == .vertex, source.usesFloatComponents,
              source.bytesPerComponent == 4, source.componentsPerVector == 3 else {
            throw Failure.unsupportedGeometry
        }
        try validateLayout(source)
        return source
    }

    private static func affine(_ m: simd_float4x4) -> Bool {
        func finite(_ c: SIMD4<Float>) -> Bool {
            c.x.isFinite && c.y.isFinite && c.z.isFinite && c.w.isFinite
        }
        return finite(m.columns.0) && finite(m.columns.1) && finite(m.columns.2) && finite(m.columns.3)
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
        var points: [SIMD3<Float>] = []
        try appendCameraPoints(view: simd_inverse(camera.simdWorldTransform), to: &points)
        return points
    }

    func appendCameraPoints(view: simd_float4x4, to points: inout [SIMD3<Float>]) throws {
        guard Self.affine(view) else { throw Failure.invalidTransform }
        points.reserveCapacity(points.count + pointCapacity)
        for part in parts where visible(part.holder) {
            guard part.holder.geometry === part.geometry, part.holder.morpher == nil else {
                throw Failure.unsupportedGeometry
            }
            switch part.binding {
            case let .rigid(corners):
                guard part.holder.skinner == nil, !GLTFModel.hasSkinBinding(on: part.holder) else {
                    throw Failure.invalidSkin
                }
                guard SCNMatrix4EqualToMatrix4(part.holder.pivot, SCNMatrix4Identity) else {
                    throw Failure.unsupportedGeometry
                }
                let world = part.holder.simdWorldTransform
                guard Self.affine(world) else { throw Failure.invalidTransform }
                let viewFromLocal = view * world
                for corner in corners {
                    let q = viewFromLocal * SIMD4(corner.x, corner.y, corner.z, 1)
                    guard q.x.isFinite, q.y.isFinite, q.z.isFinite else { throw Failure.invalidTransform }
                    let point = SIMD3(q.x, q.y, q.z)
                    // Preserve the shared 16-point envelope contract. Rigid
                    // endpoints coincide; they are not synthetic skin weights.
                    points.append(point); points.append(point)
                }
            case let .skinned(skin, influences, sumLow, sumHigh):
                guard part.holder.skinner === skin else { throw Failure.invalidSkin }
                for influence in influences {
                    let world = influence.bone.simdWorldTransform
                    guard Self.affine(world) else { throw Failure.invalidTransform }
                    for corner in influence.corners {
                        let p = world * SIMD4(corner.x, corner.y, corner.z, 1)
                        for endpoint in 0..<2 {
                            let sum = endpoint == 0 ? sumLow : sumHigh
                            let q = view * SIMD4(p.x * sum, p.y * sum, p.z * sum, 1)
                            guard q.x.isFinite, q.y.isFinite, q.z.isFinite else { throw Failure.invalidTransform }
                            points.append(SIMD3(q.x, q.y, q.z))
                        }
                    }
                }
            }
        }
    }

    /// Artwork-only overlap regions: preserve each influence box separately so
    /// a long weapon and the torso do not dim controls in the empty space between.
    /// cameraPoints emits 8 corners x 2 endpoints per influence or rigid part.
    /// These regions are NOT a silhouette/visibility acceptance assertion.
    static func artworkRectangles(points: [SIMD3<Float>], size: CGSize,
                                  verticalFieldOfView: Double) -> [CGRect] {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              verticalFieldOfView.isFinite, verticalFieldOfView > 0, verticalFieldOfView < 180,
              points.count.isMultiple(of: 16) else { return [] }
        let tangent = tan(verticalFieldOfView * .pi / 360)
        let aspect = Double(size.width / size.height)
        var rectangles: [CGRect] = []
        rectangles.reserveCapacity(points.count / 16)
        for start in stride(from: 0, to: points.count, by: 16) {
            var minX = Double.infinity, minY = Double.infinity
            var maxX = -Double.infinity, maxY = -Double.infinity
            for index in start..<(start + 16) {
                let p = points[index], depth = -Double(points[index].z)
                guard p.x.isFinite, p.y.isFinite, p.z.isFinite, depth > 0 else { return [] }
                let x = Double(size.width) * (0.5 + Double(p.x) / (depth * tangent * aspect) / 2)
                let y = Double(size.height) * (0.5 - Double(p.y) / (depth * tangent) / 2)
                guard x.isFinite, y.isFinite else { return [] }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
            rectangles.append(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
        }
        return rectangles
    }

    static func verticalFOV(points: [SIMD3<Float>], aspect: Double, minimum: Double,
                            near: Double, inset: Double = 1) throws -> Double {
        guard aspect.isFinite, aspect > 0, minimum.isFinite, minimum > 0, minimum < 180, near.isFinite, near > 0,
              inset > 0, inset <= 1 else { throw Failure.invalidTransform }
        // cameraPoints emits one 16-point geometry envelope at a time.
        // No visible geometry (or a truncated envelope) is an unknown fit, not a
        // successful 29-degree close-up that could crop returning geometry.
        guard !points.isEmpty, points.count.isMultiple(of: 16) else {
            throw Failure.unsupportedGeometry
        }
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

