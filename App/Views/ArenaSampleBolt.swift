import SceneKit
import UIKit

/// Trial-only ranger projectile. Team silhouette survives super/hyper accents.
/// Only supers project their radius onto the floor; normal bolts keep a clean airborne silhouette.
@MainActor
enum ArenaSampleBolt {
    static func make(radius: CGFloat, ally: Bool, isSuper: Bool, hyper: Bool, height: Float) -> SCNNode {
        let root = SCNNode()
        root.name = "sample-ranger-bolt"
        let team = ally ? ArenaPalette.allyShot : ArenaPalette.enemyShot
        let length: CGFloat = isSuper ? 0.78 : 0.55
        root.addChildNode(wedge(name: "team-shell", width: radius * 1.55, length: length, color: team))
        let accent = isSuper ? (hyper ? ArenaPalette.hyper : ArenaPalette.gold) : UIColor(white: 0.85, alpha: 1)
        let core = wedge(name: "strength-core", width: radius * 0.6, length: length * 0.64, color: accent)
        core.position.y = 0.012
        root.addChildNode(core)
        let tail = wedge(name: "short-tail", width: radius * 0.45, length: 0.22, color: team.withAlphaComponent(0.3))
        tail.position.z = -Float(length * 0.5 + 0.08)
        root.addChildNode(tail)

        // The airborne shell communicates team/strength. Repeated normal-shot
        // ground rings visually joined the tips into musical-note silhouettes.
        guard isSuper else { return root }
        let tube = SCNTube(innerRadius: max(0, radius - 0.018), outerRadius: radius, height: 0.008)
        tube.radialSegmentCount = 24
        tube.firstMaterial = material(team.withAlphaComponent(0.42))
        let footprint = SCNNode(geometry: tube)
        footprint.name = "collision-radius"
        footprint.position.y = 0.04 - height
        footprint.castsShadow = false
        root.addChildNode(footprint)
        // Opponents have a pointed forward notch; allies have two inner ticks.
        if ally {
            for sign in [Float(-1), Float(1)] {
                let tick = SCNNode(geometry: SCNBox(width: 0.025, height: 0.008, length: radius * 0.35, chamferRadius: 0))
                tick.name = "ally-inner-tick"
                tick.geometry?.firstMaterial = material(team)
                tick.position = SCNVector3(sign * Float(radius * 0.5), 0, 0)
                tick.castsShadow = false
                footprint.addChildNode(tick)
            }
        } else {
            let notch = wedge(name: "enemy-forward-notch", width: radius * 0.5, length: radius * 0.6, color: team)
            notch.position.z = Float(radius * 0.7)
            footprint.addChildNode(notch)
        }
        return root
    }

    private static func wedge(name: String, width: CGFloat, length: CGFloat, color: UIColor) -> SCNNode {
        // XZ plane, facing +Z (same convention as the simulation velocity).
        let vertices = [SCNVector3(0, 0, Float(length / 2)),
                        SCNVector3(-Float(width / 2), 0, -Float(length * 0.12)),
                        SCNVector3(0, 0, -Float(length / 2)),
                        SCNVector3(Float(width / 2), 0, -Float(length * 0.12))]
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
                                  elements: [SCNGeometryElement(indices: [Int32(0), 1, 2, 0, 2, 3], primitiveType: .triangles)])
        geometry.firstMaterial = material(color)
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.castsShadow = false
        return node
    }

    private static func material(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        material.isDoubleSided = true
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        return material
    }
}
