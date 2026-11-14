import SceneKit
import UIKit

/// Optional collision/state diagnostics. These simple wireframes deliberately
/// stay behind showBoxes; they are not substitutes for original stone/wind FX.
/// Continuous geometry is sampled from the fight, while transient accepted
/// events are retained across fixed-step catch-up before the next draw.
@MainActor
final class DuelPanguDiagnostics {
    private struct Marker {
        let node: SCNNode
        let bornAt: Int
    }

    private static let maximumMarkers = 32
    private static let markerTicks = 12
    private let root = SCNNode()
    private var shapes: [String: SCNNode] = [:]
    private var markers: [Marker] = []
    private var availableMarkers: [SCNNode] = []
    private var lastFrame: Int?
    private var lastLiveTick: Int?
    private var ended = false

    init(parent: SCNNode) {
        root.name = "duel.pangu.diagnostics"
        root.isHidden = true
        parent.addChildNode(root)
    }

    func consume(_ snapshot: DuelPanguPresentation,
                 events: [DuelPanguPresentation.Event], frame: Int, fighting: Bool) {
        guard !ended else { return }
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }
        if !fighting || lastFrame.map({ frame < $0 }) == true ||
            lastLiveTick.map({ snapshot.liveTick < $0 }) == true {
            reset()
        }
        guard fighting, lastFrame != frame else { return }
        lastFrame = frame; lastLiveTick = snapshot.liveTick
        expireMarkers(at: snapshot.liveTick)
        for event in events where event.id.frame == frame {
            switch event.kind {
            case .attackReleased(let volume):
                mark(volume.center, color: color(volume.delivery), liveTick: event.liveTick)
            case .contact(let contact):
                mark(contact.position, color: contact.kind == .block ? .systemBlue : .systemRed,
                     liveTick: event.liveTick)
            case .controlApplied(let control):
                let box = control.bounds
                mark(.init(x: Double(box.minX + box.maxX) / 2000,
                           y: Double(box.minY + box.maxY) / 2000),
                     color: color(control.kind), liveTick: event.liveTick)
            case .teleported(_, let from, let to):
                mark(from, color: .systemTeal, liveTick: event.liveTick)
                mark(to, color: .systemTeal, liveTick: event.liveTick)
            case .pillarStarted(let pillar), .descentStarted(let pillar):
                mark(.init(x: Double(pillar.xMillimeters) / 1000,
                           y: Double(pillar.heightMillimeters) / 1000),
                     color: .systemBrown, liveTick: event.liveTick)
            case .landed(_, let position):
                mark(position, color: .systemOrange, liveTick: event.liveTick)
            case .ordinaryThrowEscaped(_, _, let position):
                mark(position, color: .systemYellow, liveTick: event.liveTick)
            case .controlReleased, .castStarted, .castPhase, .castEnded:
                break
            }
        }
    }

    /// Repeated layout/draw calls change only node appearance. They cannot
    /// replay events, advance their lifetime, or change any combat state.
    func draw(_ snapshot: DuelPanguPresentation, visible: Bool, fighting: Bool) {
        guard !ended else { return }
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }
        root.isHidden = !visible || !fighting
        guard visible, fighting else { return }
        var alive: Set<String> = []
        for volume in snapshot.volumes {
            let key = "attack:\(volume.owner):\(volume.attackID)"
            alive.insert(key)
            place(shape(key, color: color(volume.delivery)), bounds: volume.bounds)
        }
        for pillar in snapshot.pillars where pillar.heightMillimeters > 0 {
            let key = "pillar:\(pillar.owner)"
            alive.insert(key)
            // Width denotes only the caster's body footprint, not a hitbox.
            place(shape(key, color: .systemBrown), bounds: .init(
                minX: pillar.xMillimeters - DuelGame.bodyWidth / 2,
                maxX: pillar.xMillimeters + DuelGame.bodyWidth / 2,
                minY: 0, maxY: pillar.heightMillimeters))
        }
        for control in snapshot.controls {
            let key = "control:\(control.target):\(control.kind.rawValue)"
            alive.insert(key)
            place(shape(key, color: color(control.kind)), bounds: control.bounds)
        }
        for key in Array(shapes.keys) where !alive.contains(key) {
            shapes.removeValue(forKey: key)?.removeFromParentNode()
        }
        for marker in markers {
            let age = max(0, snapshot.liveTick - marker.bornAt)
            marker.node.opacity = CGFloat(max(0, Self.markerTicks - age)) / CGFloat(Self.markerTicks)
        }
    }

    func reset() {
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }
        lastFrame = nil; lastLiveTick = nil
        shapes.values.forEach { $0.removeFromParentNode() }; shapes.removeAll()
        for marker in markers {
            marker.node.isHidden = true
            availableMarkers.append(marker.node)
        }
        markers.removeAll(keepingCapacity: true)
        root.isHidden = true
    }

    func shutdown() {
        guard !ended else { return }
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }
        reset(); ended = true
        availableMarkers.removeAll()
        root.removeFromParentNode()
    }

    private func expireMarkers(at tick: Int) {
        while let marker = markers.first, tick - marker.bornAt >= Self.markerTicks {
            marker.node.isHidden = true
            availableMarkers.append(markers.removeFirst().node)
        }
    }

    private func mark(_ point: DuelWeaponPoint, color: UIColor, liveTick: Int) {
        let node: SCNNode
        if markers.count >= Self.maximumMarkers {
            node = markers.removeFirst().node
        } else if let existing = availableMarkers.popLast() {
            node = existing
        } else {
            let geometry = SCNSphere(radius: 0.065)
            geometry.segmentCount = 8
            node = SCNNode(geometry: geometry)
            configure(node)
            node.name = "duel.pangu.accepted-event"
            root.addChildNode(node)
        }
        node.geometry?.firstMaterial?.diffuse.contents = color
        node.position = SCNVector3(Float(point.x), Float(point.y), 0.7)
        node.opacity = 1; node.isHidden = false
        markers.append(.init(node: node, bornAt: liveTick))
    }

    private func shape(_ key: String, color: UIColor) -> SCNNode {
        if let node = shapes[key] { return node }
        let node = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 0.02, chamferRadius: 0))
        configure(node)
        node.geometry?.firstMaterial?.diffuse.contents = color
        node.geometry?.firstMaterial?.fillMode = .lines
        node.name = "duel.pangu.\(key)"
        root.addChildNode(node); shapes[key] = node
        return node
    }

    private func configure(_ node: SCNNode) {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.readsFromDepthBuffer = false
        material.writesToDepthBuffer = false
        node.geometry?.materials = [material]
        node.castsShadow = false; node.renderingOrder = 21
    }

    private func place(_ node: SCNNode, bounds: DuelGame.Box) {
        node.position = SCNVector3(Float(bounds.minX + bounds.maxX) / 2000,
                                  Float(bounds.minY + bounds.maxY) / 2000, 0.65)
        node.scale = SCNVector3(Float(bounds.maxX - bounds.minX) / 1000,
                               Float(bounds.maxY - bounds.minY) / 1000, 1)
    }

    private func color(_ delivery: DuelPanguRules.Delivery) -> UIColor {
        switch delivery {
        case .melee: return .systemOrange
        case .projectile: return .systemYellow
        case .ground: return .systemBrown
        case .windBlade: return .systemTeal
        case .landingShock: return .systemPurple
        }
    }

    private func color(_ kind: DuelPanguPresentation.Control.Kind) -> UIColor {
        switch kind {
        case .stun: return .systemYellow
        case .petrify: return .systemGray
        case .pinned: return .systemBrown
        case .airHeld: return .systemCyan
        case .dread: return .systemPurple
        }
    }
}
