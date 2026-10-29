import SceneKit
import UIKit
import simd

/// Original procedural art for the canyon fixture only. No gameplay or tile changes.
/// Opaque low-noise surfaces, shared leaf meshes, batched walls, no dynamic shadows.
@MainActor
enum ArenaSampleArt {
    static let ground = UIColor(red: 0.16, green: 0.12, blue: 0.25, alpha: 1)
    static let outside = UIColor(red: 0.12, green: 0.09, blue: 0.19, alpha: 1)

    private static func material(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        return material
    }
    private static let side = material(UIColor(red: 0.46, green: 0.27, blue: 0.52, alpha: 1))
    private static let top = material(UIColor(red: 0.67, green: 0.44, blue: 0.69, alpha: 1))
    private static let trim = material(UIColor(red: 0.76, green: 0.54, blue: 0.74, alpha: 1))
    private static let contact = material(UIColor(red: 0.10, green: 0.07, blue: 0.16, alpha: 1))

    static func floorMaterial(_ map: ArenaMap) -> SCNMaterial {
        let surface = material(ground)
        surface.diffuse.contents = floor(map)
        // World geometry must participate in depth testing (unlike HUD labels).
        surface.readsFromDepthBuffer = true
        surface.writesToDepthBuffer = true
        return surface
    }

    static func floor(_ map: ArenaMap) -> UIImage {
        let unit: CGFloat = 32
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: CGFloat(map.width) * unit, height: CGFloat(map.height) * unit), format: format).image { context in
            ground.setFill()
            context.fill(CGRect(x: 0, y: 0, width: CGFloat(map.width) * unit, height: CGFloat(map.height) * unit))
            // Large floor slabs, deliberately little contrast and no small grass marks.
            UIColor(red: 0.19, green: 0.15, blue: 0.29, alpha: 1).setFill()
            for y in stride(from: 0, to: map.height, by: 3) {
                for x in stride(from: 0, to: map.width, by: 3) where (x + y) % 2 == 0 {
                    context.fill(CGRect(x: CGFloat(x) * unit + 1, y: CGFloat(y) * unit + 1, width: unit * 3 - 2, height: unit * 3 - 2))
                }
            }
            // Grass footprint is exactly the occupied tile, not a guessed terrain type.
            UIColor(red: 0.13, green: 0.23, blue: 0.21, alpha: 1).setFill()
            for y in 0..<map.height {
                for x in 0..<map.width where map.tile(x, y) == .bush {
                    context.fill(CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit, width: unit, height: unit))
                }
            }
        }
    }

    static func walls(_ map: ArenaMap) -> SCNNode {
        var mesh = ArenaMesh(parts: 4)
        for y in 0..<map.height {
            for x in 0..<map.width where map.tile(x, y) == .wall && !map.isChest(x, y) {
                let foot = SIMD3<Float>(Float(x) + 0.5, 0, Float(y) + 0.5)
                mesh.box(center: foot + SIMD3(0, 0.04, 0), size: SIMD3(1, 0.08, 1), part: 3)
                mesh.beveledBlock(at: foot, side: 0, bevel: 2, top: 1)
                if (x * 7 + y * 11) % 5 == 0 {
                    for direction in [Float(-1), Float(1)] {
                        for offset in [Float(-0.35), Float(0.35)] {
                            mesh.box(center: foot + SIMD3(offset, 0.48, direction * 0.48), size: SIMD3(0.08, 0.64, 0.035), part: 2)
                        }
                    }
                }
            }
        }
        return SCNNode(geometry: mesh.geometry([side, top, trim, contact]))
    }

    static let grasses: [SCNGeometry] = (0..<3).map { makeGrass($0) }

    private static func makeGrass(_ variant: Int) -> SCNGeometry {
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        // Eight broad pointed blades, 24 triangles per cell; no alpha textures.
        for leaf in 0..<8 {
            let angle = Float(leaf) * .pi / 4 + Float(variant) * 0.23
            let direction = SIMD3<Float>(sin(angle), 0, cos(angle))
            let across = SIMD3<Float>(cos(angle), 0, -sin(angle))
            let base = direction * 0.15
            let shoulder = direction * 0.31 + SIMD3<Float>(0, 0.30, 0)
            let tip = direction * 0.44 + SIMD3<Float>(0, 0.48 + Float((leaf + variant) % 3) * 0.07, 0)
            let points: [SIMD3<Float>] = [base - across * Float(0.09), base + across * Float(0.09),
                          shoulder + across * Float(0.12), tip, shoulder - across * Float(0.12)]
            let index = Int32(vertices.count)
            vertices += points.map { SCNVector3($0.x, $0.y, $0.z) }
            indices += [index, index + 1, index + 2, index, index + 2, index + 4, index + 2, index + 3, index + 4]
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let colors: [UIColor] = [UIColor(red: 0.24, green: 0.57, blue: 0.35, alpha: 1),
                                 UIColor(red: 0.29, green: 0.64, blue: 0.39, alpha: 1),
                                 UIColor(red: 0.34, green: 0.68, blue: 0.42, alpha: 1)]
        let ink = material(colors[variant])
        ink.isDoubleSided = true
        geometry.materials = [ink]
        return geometry
    }
}
