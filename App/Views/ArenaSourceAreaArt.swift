import SceneKit
import UIKit

/// Gameplay coverage is drawn at the exact source-rule radius and lifetime.
/// Decorative SC art uses the App's documented point-to-tile presentation scale.
@MainActor
final class ArenaSourceAreaArt {
    static let unitsPerSourcePoint = 0.01
    let node = SCNNode()
    private let rim: SCNNode
    private let fill: SCNNode
    private let source: ArenaImportedSkillArt?

    init(area: ArenaSourceLiveArea, myTeam: Int) {
        let color = area.team == myTeam ? ArenaPalette.allyShot : ArenaPalette.enemyShot
        let radius = CGFloat(max(area.radius, 0.05))
        let tube = SCNTube(innerRadius: max(0, radius - 0.04), outerRadius: radius, height: 0.008)
        tube.radialSegmentCount = 40
        tube.firstMaterial = ArenaAvatar.decal(color.withAlphaComponent(0.8))
        rim = SCNNode(geometry: tube)
        let disc = SCNCylinder(radius: radius, height: 0.003)
        disc.radialSegmentCount = 40
        disc.firstMaterial = ArenaAvatar.decal(color.withAlphaComponent(0.12))
        fill = SCNNode(geometry: disc)
        source = ArenaImportedSkillAssets.shared.area(areaID: area.spawn.area.id, enemy: area.team != myTeam,
                                                     unitsPerSourcePoint: Self.unitsPerSourcePoint)
        [fill, rim].forEach { $0.castsShadow = false; $0.renderingOrder = 5; node.addChildNode($0) }
        if let source { source.node.position.y = 0.01; node.addChildNode(source.node) }
        update(area)
    }

    func update(_ area: ArenaSourceLiveArea) {
        node.simdPosition = SIMD3(Float(area.position.x), 0.045, Float(area.position.y))
        let remaining = max(0, area.spawn.area.duration - area.state.elapsed)
        // Fade only near the actual expiration; no fake repeated damage pulse.
        let alpha = CGFloat(min(1, remaining / 0.15))
        rim.opacity = alpha; fill.opacity = alpha
        source?.update(elapsed: area.state.elapsed, direction: V2(0, 1))
    }
}
