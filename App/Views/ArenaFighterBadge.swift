import SwiftUI
import SceneKit
import Metal

/// Every source portrait uses its own model, never the compatibility save ID.
struct ArenaFighterBadge: View {
    let fighter: Fighter
    let size: CGFloat
    @State private var sourceImage: UIImage?
    var body: some View {
        Group {
            if let source = fighter.sourceHero {
                ZStack {
                    Circle().fill(Color(red: 0.15, green: 0.2, blue: 0.32))
                    if let sourceImage { Image(uiImage: sourceImage).resizable().scaledToFit() }
                    else { Text(String(source.name.prefix(2))).font(.system(size: max(10, size / 4), weight: .bold)) }
                }.frame(width: size, height: size).clipShape(Circle())
                    .accessibilityLabel(source.name)
                    .task(id: source.id) { sourceImage = ArenaImportedPortraitCache.shared.image(id: source.id) }
            } else { BrawlerBadge(brawler: fighter.brawler, size: size) }
        }
    }
}

@MainActor
private final class ArenaImportedPortraitCache {
    static let shared = ArenaImportedPortraitCache()
    private var images: [String: UIImage] = [:]
    func image(id: String) -> UIImage? {
        let store = ArenaResourcePackStore.shared
        let modelPath = store.manifest?.heroes.first { $0.id == id }?.modelFile
        let digest = store.manifest?.files.first { $0.path == modelPath }?.sha256 ?? ""
        let cacheKey = (store.manifest?.id ?? "") + "@" + digest + "@" + id
        if let image = images[cacheKey] { return image }
        guard let device = MTLCreateSystemDefaultDevice(), ArenaImportedHeroAssets.shared.asset(id: id) != nil else { return nil }
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        let avatar = ArenaAvatar(brawler: .ranger, color: .clear, isMe: false, decorated: false, sourceHeroID: id)
        avatar.turn(to: -0.3)
        scene.rootNode.addChildNode(avatar.node)
        let camera = SCNNode()
        camera.camera = SCNCamera(); camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 1.15; camera.camera?.zNear = 0.1; camera.camera?.zFar = 20
        camera.position = SCNVector3(0, 1, 5)
        camera.look(at: SCNVector3(0, 0.95, 0)); scene.rootNode.addChildNode(camera)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.intensity = 650
        scene.rootNode.addChildNode(ambient)
        let light = SCNNode(); light.light = SCNLight(); light.light?.type = .directional; light.light?.intensity = 650
        light.eulerAngles = SCNVector3(-0.4, -0.4, 0); scene.rootNode.addChildNode(light)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene; renderer.pointOfView = camera
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 200, height: 200), antialiasingMode: .none)
        renderer.scene = nil
        if images.count >= 128 { images.removeAll() }
        images[cacheKey] = image
        return image
    }
}
