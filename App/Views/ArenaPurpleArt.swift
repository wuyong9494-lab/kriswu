import SceneKit
import UIKit
import simd

/// Original procedural sample art. No borrowed textures. Only canyon opts in.
@MainActor
enum ArenaPurpleArt {
    private static func material(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 1)
        m.roughness.contents = 1
        return m
    }
    static let outside = material(0.12, 0.08, 0.22)
    private static let side = material(0.46, 0.24, 0.57)
    private static let top = material(0.72, 0.44, 0.74)
    private static let edge = material(0.58, 0.32, 0.64)
    private static let crateSide = material(0.39, 0.19, 0.46)
    private static let brace = material(0.69, 0.43, 0.66)
    private static let leaf = material(0.20, 0.56, 0.30)

    static func floor(_ map: ArenaMap) -> SCNMaterial {
        let cell: CGFloat = 32
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: CGFloat(map.width) * cell, height: CGFloat(map.height) * cell), format: format).image { ctx in
            let cg = ctx.cgContext
            for y in 0..<map.height {
                for x in 0..<map.width {
                    let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)
                    let light: CGFloat = (x / 3 + y / 3) % 2 == 0 ? 0.01 : 0
                    cg.setFillColor(UIColor(red: 0.24 + light, green: 0.16 + light, blue: 0.35 + light, alpha: 1).cgColor)
                    cg.fill(rect)
                    if map.tile(x, y) == .wall {
                        // Contact shading is baked into one opaque ground image.
                        cg.setFillColor(UIColor(red: 0.13, green: 0.08, blue: 0.21, alpha: 1).cgColor)
                        cg.fill(rect.insetBy(dx: -2, dy: -2).offsetBy(dx: 1, dy: 2))
                    } else if map.tile(x, y) == .bush {
                        cg.setFillColor(UIColor(red: 0.13, green: 0.31, blue: 0.23, alpha: 1).cgColor)
                        cg.fill(rect.insetBy(dx: 1, dy: 1))
                    }
                    if x % 3 == 0 && y % 3 == 0 {
                        cg.setFillColor(UIColor(red: 0.20, green: 0.13, blue: 0.30, alpha: 1).cgColor)
                        cg.fill(CGRect(x: rect.minX, y: rect.minY, width: cell * 2, height: 0.8))
                    }
                }
            }
        }
        let m = material(1, 1, 1)
        m.diffuse.contents = image
        m.diffuse.mipFilter = .linear
        return m
    }

    static func walls(_ map: ArenaMap) -> SCNNode {
        let root = SCNNode()
        let stone = SCNBox(width: 1, height: 1.05, length: 1, chamferRadius: 0.055)
        stone.chamferSegmentCount = 1
        stone.materials = [side, side, side, side, top, side]
        let crate = SCNBox(width: 1, height: 0.95, length: 1, chamferRadius: 0.035)
        crate.chamferSegmentCount = 1
        crate.materials = [crateSide, crateSide, crateSide, crateSide, edge, crateSide]
        let rib = SCNBox(width: 0.11, height: 0.74, length: 0.025, chamferRadius: 0.015)
        rib.firstMaterial = brace
        for y in 0..<map.height {
            for x in 0..<map.width where map.tile(x, y) == .wall && !map.isChest(x, y) {
                let isCrate = (x * 7 + y) % 4 == 0
                let node = SCNNode(geometry: isCrate ? crate : stone)
                node.simdPosition = SIMD3(Float(x) + 0.5, isCrate ? 0.475 : 0.525, Float(y) + 0.5)
                node.castsShadow = false
                if isCrate {
                    for z in [Float(-0.501), Float(0.501)] {
                        for angle in [Float(-0.65), Float(0.65)] {
                            let bar = SCNNode(geometry: rib)
                            bar.simdPosition = SIMD3(0, 0, z)
                            bar.simdEulerAngles.z = angle
                            node.addChildNode(bar)
                        }
                    }
                }
                root.addChildNode(node)
            }
        }
        return root.flattenedClone()
    }

    /// Six solid faceted leaf blades, 12 double-sided triangles per tile, under 0.65 units tall.
    static let bush: SCNGeometry = {
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        for i in 0..<6 {
            let x = Float(i % 3 - 1) * 0.25
            let z = Float(i / 3) * 0.36 - 0.18
            let h: Float = i % 2 == 0 ? 0.62 : 0.48
            let n = Int32(vertices.count)
            vertices += [SCNVector3(x - 0.12, 0, z), SCNVector3(x + 0.12, 0, z),
                         SCNVector3(x + 0.10, h, z - 0.12), SCNVector3(x, h * 0.45, z + 0.06)]
            indices += [n, n + 3, n + 2, n + 3, n + 1, n + 2]
        }
        // Explicit flat normals keep the low-poly leaves lit correctly with Lambert.
        var faces: [SCNVector3] = []
        var normals: [SCNVector3] = []
        for start in stride(from: 0, to: indices.count, by: 3) {
            let triangle = indices[start..<(start + 3)].map { vertices[Int($0)] }
            let a = SIMD3<Float>(triangle[0].x, triangle[0].y, triangle[0].z)
            let b = SIMD3<Float>(triangle[1].x, triangle[1].y, triangle[1].z)
            let c = SIMD3<Float>(triangle[2].x, triangle[2].y, triangle[2].z)
            let n = simd_normalize(simd_cross(b - a, c - a))
            faces += triangle
            normals += Array(repeating: SCNVector3(n.x, n.y, n.z), count: 3)
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: faces), SCNGeometrySource(normals: normals)],
                                   elements: [SCNGeometryElement(indices: (0..<faces.count).map { Int32($0) }, primitiveType: .triangles)])
        let m = leaf.copy() as! SCNMaterial
        m.isDoubleSided = true
        geometry.firstMaterial = m
        return geometry
    }()
}
