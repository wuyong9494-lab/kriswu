import SceneKit
import UIKit

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
    private static let metal = material(UIColor(red: 0.42, green: 0.29, blue: 0.19, alpha: 1))
    private static let cap = material(UIColor(red: 0.70, green: 0.52, blue: 0.30, alpha: 1))
    private static let seam = material(UIColor(red: 0.25, green: 0.23, blue: 0.21, alpha: 1))

    static let bush: SCNGeometry = {
        let geometry = ArenaPurpleArt.bush.copy() as! SCNGeometry
        let leaf = material(UIColor(red: 0.26, green: 0.48, blue: 0.32, alpha: 1))
        leaf.isDoubleSided = true
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
                        cg.setFillColor(UIColor(red: 0.17, green: 0.30, blue: 0.25, alpha: 1).cgColor)
                        cg.fill(rect)
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
        let body = SCNBox(width: 1, height: 0.9, length: 1, chamferRadius: 0.035)
        body.chamferSegmentCount = 1
        body.materials = [metal]
        let lid = SCNBox(width: 1, height: 0.12, length: 1, chamferRadius: 0.025)
        lid.chamferSegmentCount = 1
        lid.materials = [cap]
        let rib = SCNBox(width: 0.08, height: 0.014, length: 0.86, chamferRadius: 0)
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
