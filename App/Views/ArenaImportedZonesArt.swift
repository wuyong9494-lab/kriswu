import SceneKit
import UIKit

/// Every reviewed capture area keeps its own geometry and two independent
/// progress tracks. Enemy presence never changes a ring to a blocked state.
@MainActor
final class ArenaImportedZonesArt {
    let node = SCNNode()
    private let myTeam: Int
    private let friendly = UIColor(red: 0.19, green: 0.72, blue: 1, alpha: 1)
    private let opposing = UIColor(red: 1, green: 0.29, blue: 0.39, alpha: 1)
    private var definitions: [ArenaImportedMap.CaptureZone] = []
    private var visuals: [Visual] = []

    private struct Visual {
        let root: SCNNode
        let arcs: [SCNNode]
        let label: SCNNode
        var displayedPercent: [Int]
    }

    init(objective: ArenaZoneObjectiveState, myTeam: Int) {
        self.myTeam = (0...1).contains(myTeam) ? myTeam : 0
        node.name = "imported-capture-zones"
        update(objective)
    }

    func update(_ objective: ArenaZoneObjectiveState) {
        if definitions != objective.zones {
            node.childNodes.forEach { $0.removeFromParentNode() }
            definitions = objective.zones
            visuals = definitions.map(makeZone)
            visuals.forEach { node.addChildNode($0.root) }
        }
        for index in definitions.indices {
            let percent = [myTeam, 1 - myTeam].map { team -> Int in
                guard objective.fractions.indices.contains(team), objective.fractions[team].indices.contains(index) else { return 0 }
                let value = objective.fractions[team][index]
                guard value.isFinite else { return 0 }
                return Int((min(max(value, 0), 1) * 100 + 1e-8).rounded(.down))
            }
            guard percent != visuals[index].displayedPercent else { continue }
            let radius = CGFloat(definitions[index].radius)
            for teamSlot in 0...1 {
                let arc = visuals[index].arcs[teamSlot]
                arc.isHidden = percent[teamSlot] == 0
                if !arc.isHidden {
                    let path = UIBezierPath(arcCenter: .zero, radius: radius * (teamSlot == 0 ? 0.95 : 0.87),
                        startAngle: -.pi / 2, endAngle: -.pi / 2 + 2 * .pi * CGFloat(percent[teamSlot]) / 100,
                        clockwise: true)
                    let stroke = path.cgPath.copy(strokingWithWidth: max(0.045, radius * 0.024),
                                                   lineCap: .round, lineJoin: .round, miterLimit: 1)
                    let shape = SCNShape(path: UIBezierPath(cgPath: stroke), extrusionDepth: 0.012)
                    shape.firstMaterial = material(teamSlot == 0 ? friendly : opposing)
                    arc.geometry = shape
                }
            }
            visuals[index].label.geometry?.firstMaterial?.diffuse.contents = labelImage(percent)
            visuals[index].displayedPercent = percent
        }
    }

    private func makeZone(_ definition: ArenaImportedMap.CaptureZone) -> Visual {
        let root = SCNNode()
        root.name = "capture-zone-" + definition.id
        root.position = SCNVector3(Float(definition.center.x), 0.04, Float(definition.center.y))
        let radius = CGFloat(definition.radius)
        let fill = SCNCylinder(radius: radius, height: 0.008)
        fill.radialSegmentCount = 64
        fill.firstMaterial = material(UIColor.white.withAlphaComponent(0.055))
        let fillNode = SCNNode(geometry: fill)
        fillNode.castsShadow = false
        root.addChildNode(fillNode)
        let boundary = SCNTorus(ringRadius: radius, pipeRadius: 0.018)
        boundary.ringSegmentCount = 72
        boundary.pipeSegmentCount = 6
        boundary.firstMaterial = material(UIColor.white.withAlphaComponent(0.62))
        let boundaryNode = SCNNode(geometry: boundary)
        boundaryNode.position.y = 0.02
        boundaryNode.castsShadow = false
        root.addChildNode(boundaryNode)
        let arcs = (0...1).map { slot -> SCNNode in
            let result = SCNNode()
            result.name = slot == 0 ? "friendly-progress" : "opposing-progress"
            result.eulerAngles.x = -.pi / 2
            result.position.y = Float(0.035 + Double(slot) * 0.01)
            result.castsShadow = false
            root.addChildNode(result)
            return result
        }
        let labelGeometry = SCNPlane(width: min(2.9, radius * 1.6), height: min(0.59, radius * 0.34))
        labelGeometry.firstMaterial = material(.white)
        let label = SCNNode(geometry: labelGeometry)
        label.name = "independent-team-percentages"
        label.eulerAngles.x = -.pi / 2
        label.position = SCNVector3(0, 0.07, 0)
        label.castsShadow = false
        root.addChildNode(label)
        return Visual(root: root, arcs: arcs, label: label, displayedPercent: [-1, -1])
    }

    private func material(_ color: UIColor) -> SCNMaterial {
        let result = SCNMaterial()
        result.lightingModel = .constant
        result.diffuse.contents = color
        result.isDoubleSided = true
        result.writesToDepthBuffer = false
        return result
    }

    /// Re-render only when an integer percentage changes, not every scene frame.
    private func labelImage(_ percent: [Int]) -> UIImage {
        let size = CGSize(width: 320, height: 64)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let background = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 5), cornerRadius: 15)
            UIColor(white: 0.05, alpha: 0.72).setFill()
            background.fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            for slot in 0...1 {
                let title = (slot == 0 ? "我方 " : "对方 ") + "\(percent[slot])%"
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 23, weight: .bold),
                    .foregroundColor: slot == 0 ? friendly : opposing,
                    .paragraphStyle: paragraph]
                (title as NSString).draw(in: CGRect(x: CGFloat(slot) * 158 + 4, y: 18, width: 152, height: 34), withAttributes: attributes)
            }
        }
    }
}
