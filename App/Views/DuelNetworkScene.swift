import SwiftUI
import SceneKit

/// Read-only SceneKit presentation of the host's combat snapshots.
/// It never advances DuelGame, calculates damage, or starts another game clock.
struct DuelNetworkScene: UIViewRepresentable {
    let state: DuelNetworkCombatState
    func makeUIView(context: Context) -> DuelNetworkSceneView {
        let view = DuelNetworkSceneView()
        view.display(state)
        return view
    }
    func updateUIView(_ view: DuelNetworkSceneView, context: Context) {
        view.display(state)
    }
    static func dismantleUIView(_ view: DuelNetworkSceneView, coordinator: ()) {
        view.shutdown()
    }
}

@MainActor
final class DuelNetworkSceneView: SCNView {
    private var actors: [DuelActor] = []
    private var heroes: [DuelGame.Hero] = []
    private var lastTick: UInt64?
    private var weaponAssets: DuelWeaponAssets?
    private var stageAsset: DuelStageAsset?
    private let cameraNode = SCNNode()
    private var center: Float = 5

    override init(frame: CGRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        preferredFramesPerSecond = 60
        antialiasingMode = .multisampling2X
        isUserInteractionEnabled = false
        backgroundColor = UIColor(red: 0.045, green: 0.055, blue: 0.13, alpha: 1)
        let world = SCNScene()
        scene = world
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 350
        world.rootNode.addChildNode(cameraNode)
        pointOfView = cameraNode

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 540
        world.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1250
        key.light?.castsShadow = true
        key.eulerAngles = SCNVector3(-0.8, -0.5, 0)
        world.rootNode.addChildNode(key)

        if let url = DuelStageAsset.bundledURL, let stage = try? DuelStageAsset(url: url) {
            stageAsset = stage
            world.rootNode.addChildNode(stage.makeRoot())
            cameraNode.camera?.usesOrthographicProjection = false
        } else {
            let floor = DuelActor.shape(
                SCNBox(width: 11.5, height: 0.3, length: 3.2, chamferRadius: 0.1),
                UIColor(red: 0.14, green: 0.16, blue: 0.28, alpha: 1))
            floor.position = SCNVector3(5, -0.2, 0)
            world.rootNode.addChildNode(floor)
            cameraNode.camera?.usesOrthographicProjection = true
        }
        weaponAssets = try? DuelWeaponAssets()
        updateCamera(separation: 3)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCamera(separation: lastSeparation)
    }

    private var lastSeparation = 3.0

    func display(_ state: DuelNetworkCombatState) {
        guard state.isPlausible, state.fighters.count == 2 else { return }
        let incoming = state.fighters.map(\.hero)
        if incoming != heroes {
            actors.forEach { $0.root.removeFromParentNode() }
            actors.removeAll()
            heroes = incoming
            for hero in incoming {
                let asset = try? weaponAssets?.character(for: hero)
                let actor = DuelActor(hero: hero, asset: nil, weaponAsset: asset)
                actor.root.name = "duel.network.actor.\(actors.count)"
                actors.append(actor)
                scene?.rootNode.addChildNode(actor.root)
            }
            lastTick = nil
        }
        guard lastTick != state.tick else { return }
        lastTick = state.tick
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        for (index, snapshot) in state.fighters.enumerated() {
            var fighter = DuelGame.Fighter(hero: snapshot.hero, x: snapshot.x, facing: snapshot.facing)
            fighter.y = snapshot.y
            fighter.health = snapshot.health
            fighter.energy = snapshot.energy
            fighter.guardMeter = snapshot.guardMeter
            fighter.stun = snapshot.stun
            fighter.knockdown = snapshot.knockdown
            actors[index].pose(fighter, frame: Int(state.tick % 60_000),
                               grapple: nil, index: index, phase: .fighting)
        }
        let left = Float(state.fighters[0].x) / 1000
        let right = Float(state.fighters[1].x) / 1000
        center += (min(7, max(3, (left + right) * 0.5)) - center) * 0.12
        lastSeparation = Double(abs(left - right))
        updateCamera(separation: lastSeparation)
        SCNTransaction.commit()
    }

    private func updateCamera(separation: Double) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let framing = DuelCameraFraming(aspect: Double(bounds.width / bounds.height),
                                        separation: separation)
        if stageAsset != nil {
            cameraNode.camera?.fieldOfView = CGFloat(framing.verticalFieldOfView)
            cameraNode.position = SCNVector3(center, 2, Float(framing.perspectiveDistance))
            cameraNode.look(at: SCNVector3(center, 1.2, 0))
        } else {
            cameraNode.camera?.orthographicScale = CGFloat(framing.orthographicScale)
            cameraNode.position = SCNVector3(center, 3.6, 14)
            cameraNode.look(at: SCNVector3(center, 1, 0))
        }
    }

    func shutdown() {
        actors.forEach { $0.root.removeFromParentNode() }
        actors.removeAll()
        weaponAssets?.releaseCharacters()
        weaponAssets = nil
        stageAsset = nil
        pointOfView = nil
        scene = nil
    }
}
