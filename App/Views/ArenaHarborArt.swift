import SceneKit
import UIKit
import simd

/// Original Blue Moon Harbor study for Twin Gates. All solids follow wall cells.
@MainActor
enum ArenaHarborArt {
    private static func material(_ color: UIColor) -> SCNMaterial {
        let result = SCNMaterial()
        result.lightingModel = .lambert
        result.diffuse.contents = color
        result.roughness.contents = 1
        return result
    }
    static let outside = material(UIColor(red: 0.09, green: 0.18, blue: 0.23, alpha: 1))
    private static let metal = material(UIColor(red: 0.27, green: 0.35, blue: 0.37, alpha: 1))
    private static let cap = material(UIColor(red: 0.70, green: 0.52, blue: 0.30, alpha: 1))
    private static let seam = material(UIColor(red: 0.49, green: 0.37, blue: 0.24, alpha: 1))

    static let bush: SCNGeometry = {
        // Closed, rounded leaf volumes: one shared mesh and material per tile.
        // No alpha cutouts, extra lights, or change to gameplay visibility.
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        for leafIndex in 0..<11 {
            let angle = Float(leafIndex) * 2.39996
            // Include blade width and outward lean in the tile envelope.
            let distance: Float = leafIndex < 3 ? 0.12 : 0.285
            let center = SIMD3<Float>(cos(angle) * distance, 0, sin(angle) * distance)
            let height: Float = leafIndex % 2 == 0 ? 0.64 : 0.53
            let base = Int32(vertices.count)
            // Tapered, flattened blades instead of round ellipsoid clumps.
            let profile: [Float] = [0.001, 0.055, 0.13, 0.19, 0.16, 0.085, 0.001]
            for ring in 0...6 {
                let t = Float(ring) / 6
                let radius = profile[ring]
                let lean = (1 - t) * 0.06
                let lo = max(0, ring - 1), hi = min(6, ring + 1)
                let drdy = (profile[hi] - profile[lo]) / (-height * Float(hi - lo) / 6)
                for side in 0..<6 {
                    let phi = Float(side) * .pi / 3
                    let localX = radius * cos(phi)
                    let localZ = radius * sin(phi) * 0.80
                    let n = simd_normalize(SIMD3<Float>(cos(phi), -drdy, sin(phi) / 0.80))
                    vertices.append(SCNVector3(center.x + localX * cos(angle) - localZ * sin(angle) + lean * cos(angle),
                        height * (1 - t), center.z + localX * sin(angle) + localZ * cos(angle) + lean * sin(angle)))
                    normals.append(SCNVector3(n.x * cos(angle) - n.z * sin(angle), n.y,
                                              n.x * sin(angle) + n.z * cos(angle)))
                }
            }
            for ring in 0..<6 {
                for side in 0..<6 {
                    let a = base + Int32(ring * 6 + side)
                    let b = base + Int32(ring * 6 + (side + 1) % 6)
                    indices += [a, b, a + 6, b, b + 6, a + 6]
                }
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),
            SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let leaf = material(UIColor(red: 0.26, green: 0.48, blue: 0.32, alpha: 1))
        geometry.materials = [leaf]
        return geometry
    }()

    static func floor(_ map: ArenaMap) -> SCNMaterial {
        let cell: CGFloat = 32
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: CGFloat(map.width) * cell,
            height: CGFloat(map.height) * cell), format: format).image { context in
            let cg = context.cgContext
            for y in 0..<map.height {
                for x in 0..<map.width {
                    let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)
                    let variation: CGFloat = (x / 4 + y / 4) % 2 == 0 ? 0.012 : 0
                    cg.setFillColor(UIColor(red: 0.20 + variation, green: 0.34 + variation,
                                           blue: 0.39 + variation, alpha: 1).cgColor)
                    cg.fill(rect)
                    // Opaque contact shading; no extra transparent floor layer.
                    if map.tile(x, y) == .wall {
                        cg.setFillColor(UIColor(red: 0.12, green: 0.23, blue: 0.27, alpha: 1).cgColor)
                        cg.fill(rect.insetBy(dx: -2, dy: -2))
                    }
                    if map.tile(x, y) == .bush {
                        // Joined, low-contrast beds: round exposed corners without
                        // drawing a dark checkerboard beneath individual leaf clumps.
                        cg.setFillColor(UIColor(red: 0.19, green: 0.33, blue: 0.32, alpha: 1).cgColor)
                        cg.addPath(UIBezierPath(roundedRect: rect, cornerRadius: cell * 0.23).cgPath)
                        cg.fillPath()
                        if map.tile(x - 1, y) == .bush { cg.fill(CGRect(x: rect.minX, y: rect.minY, width: cell / 2, height: cell)) }
                        if map.tile(x + 1, y) == .bush { cg.fill(CGRect(x: rect.midX, y: rect.minY, width: cell / 2, height: cell)) }
                        if map.tile(x, y - 1) == .bush { cg.fill(CGRect(x: rect.minX, y: rect.minY, width: cell, height: cell / 2)) }
                        if map.tile(x, y + 1) == .bush { cg.fill(CGRect(x: rect.minX, y: rect.midY, width: cell, height: cell / 2)) }
                    }
                }
            }
        }
        let result = material(.white)
        result.diffuse.contents = image
        result.diffuse.mipFilter = .linear
        return result
    }

    static func walls(_ map: ArenaMap) -> SCNNode {
        let root = SCNNode()
        root.name = "harbor-wall-cells"
        let body = SCNBox(width: 1, height: 0.9, length: 1, chamferRadius: 0.10)
        body.chamferSegmentCount = 3
        body.materials = [metal]
        let lid = SCNBox(width: 1, height: 0.12, length: 1, chamferRadius: 0.055)
        lid.chamferSegmentCount = 3
        lid.materials = [cap]
        let rib = SCNBox(width: 0.035, height: 0.008, length: 0.76, chamferRadius: 0)
        rib.materials = [seam]
        for y in 0..<map.height {
            for x in 0..<map.width where map.tile(x, y) == .wall {
                let cell = SCNNode()
                cell.name = "wall-\(x)-\(y)"
                cell.position = SCNVector3(Float(x) + 0.5, 0, Float(y) + 0.5)
                let base = SCNNode(geometry: body)
                base.position.y = 0.45
                let top = SCNNode(geometry: lid)
                top.position.y = 0.96
                cell.addChildNode(base)
                cell.addChildNode(top)
                for side in [Float(-0.28), Float(0.28)] {
                    let strip = SCNNode(geometry: rib)
                    strip.position = SCNVector3(side, 1.027, 0)
                    cell.addChildNode(strip)
                }
                root.addChildNode(cell)
            }
        }
        root.enumerateChildNodes { node, _ in node.castsShadow = false }
        return root
    }
}

