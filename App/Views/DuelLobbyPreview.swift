import SwiftUI
import SceneKit
import UIKit

/// Static lobby presentation: no simulation clock remains behind a full-screen fight.
struct DuelLobbyPreview: UIViewRepresentable {
    let hero: DuelGame.Hero
    func makeUIView(context: Context) -> DuelLobbySceneView { DuelLobbySceneView(hero: hero) }
    func updateUIView(_ view: DuelLobbySceneView, context: Context) { view.select(hero) }
    static func dismantleUIView(_ view: DuelLobbySceneView, coordinator: ()) { view.shutdown() }
}

@MainActor
final class DuelLobbySceneView: SCNView {
    private(set) var selectedHero: DuelGame.Hero?
    private var stage: DuelStageAsset?
    private var character: DuelCharacterAsset?
    private var originalCharacter: DuelOriginalRigAsset?
    private var characterRoot: SCNNode?

    init(hero: DuelGame.Hero) {
        super.init(frame: .zero, options: nil)
        backgroundColor = UIColor(red: 0.045, green: 0.04, blue: 0.075, alpha: 1)
        antialiasingMode = .multisampling2X
        rendersContinuously = false; isPlaying = false; isUserInteractionEnabled = false
        isAccessibilityElement = false; accessibilityElementsHidden = true
        let world = SCNScene(); scene = world
        if let url = DuelStageAsset.bundledURL(for: .autumnLobby),
           let asset = try? DuelStageAsset(url: url, kind: .autumnLobby) {
            stage = asset; world.rootNode.addChildNode(asset.makeRoot())
        }
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.projectionDirection = .vertical; camera.camera?.fieldOfView = 35
        camera.camera?.zNear = 0.05; camera.camera?.zFar = 100
        camera.position = SCNVector3(5, 1.6, 4.8)
        camera.look(at: SCNVector3(4.7, 0.85, -0.35))
        world.rootNode.addChildNode(camera); pointOfView = camera
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 450; ambient.light?.color = UIColor(white: 0.8, alpha: 1)
        world.rootNode.addChildNode(ambient)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional
        key.light?.intensity = 1100; key.light?.color = UIColor(red: 1, green: 0.91, blue: 0.8, alpha: 1)
        key.eulerAngles = SCNVector3(-0.7, -0.4, 0); world.rootNode.addChildNode(key)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .omni
        // Neutral fill keeps the personal face and armor consistent with combat.
        fill.light?.intensity = 180; fill.light?.color = UIColor.white
        fill.position = SCNVector3(7, 3, -1); world.rootNode.addChildNode(fill)
        select(hero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func select(_ hero: DuelGame.Hero) {
        guard selectedHero != hero, let scene else { return }
        selectedHero = hero
        characterRoot?.removeFromParentNode(); characterRoot = nil; character = nil; originalCharacter = nil
        if let identity = DuelOriginalRigAsset.identity(for: hero),
           let url = DuelOriginalRigAsset.bundledURL(for: identity) {
            guard let asset = try? DuelOriginalRigAsset(url: url, identity: identity) else { return }
            let actor = DuelOriginalRigInstance(asset)
            actor.apply(.init(clip: .idle, phase: 0))
            actor.instance.root.position = SCNVector3(4.7, -0.14, -0.35)
            actor.instance.root.eulerAngles.y = .pi
            actor.instance.root.name = "duel.lobby.character.\(hero.rawValue)"
            scene.rootNode.addChildNode(actor.instance.root)
            originalCharacter = asset; characterRoot = actor.instance.root; setNeedsDisplay()
            return
        }
        guard let url = DuelCharacterAsset.bundledURL(for: hero),
              let asset = try? DuelCharacterAsset(url: url, hero: hero) else { return }
        let instance = asset.model.instantiate()
        var pose = asset.model.restPose
        if let clip = asset.model.clips["Idle"] {
            clip.sample(at: asset.starts["Idle"] ?? 0, into: &pose)
            for i in asset.model.animated { instance.nodes[i].simdTransform = pose.transform(i) }
        }
        instance.root.position = SCNVector3(4.7, -0.14, -0.35)
        instance.root.name = "duel.lobby.character.\(hero.rawValue)"
        scene.rootNode.addChildNode(instance.root)
        character = asset; characterRoot = instance.root; setNeedsDisplay()
    }
    func shutdown() {
        // Detach resource-owning nodes even if SceneKit keeps an autoreleased
        // scene or renderer alive until the current event finishes.
        scene?.rootNode.childNodes.forEach { $0.removeFromParentNode() }
        scene = nil; pointOfView = nil; stage = nil; character = nil; originalCharacter = nil; characterRoot = nil
        rendersContinuously = false; isPlaying = false
    }
}
