import SceneKit
import SwiftUI
import UIKit
import simd

/// Displays the exact imported model and its named source animation. It does not
/// dress an existing Brawler in a different character or change combat behavior.
struct ArenaImportedHeroView: UIViewRepresentable {
    let url: URL
    let name: String
    let idleAnimation: String?
    var heroID: String?
    var live = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> ArenaImportedModelView { ArenaImportedModelView() }
    func updateUIView(_ view: ArenaImportedModelView, context: Context) {
        view.load(url: url, name: name, idleAnimation: idleAnimation, heroID: heroID)
        view.setLive(live && !reduceMotion)
    }
    static func dismantleUIView(_ view: ArenaImportedModelView, coordinator: ()) { view.setLive(false) }
}

@MainActor
final class ArenaImportedModelView: SCNView {
    private let world = SCNScene()
    private let turntable = SCNNode()
    private let cameraNode = SCNNode()
    private var loadedURL: URL?
    private var loadedAnimation: String?
    private var model: GLTFModel?
    private var instance: GLTFModel.Instance?
    private var clip: GLTFModel.Clip?
    private var animator: ArenaImportedHeroAnimator?
    private var sourceBounds: [Double]?
    private var lastPoseTime: Float = 0
    private var pose = GLTFModel.Pose(translation: [], rotation: [], scale: [])
    private var link: CADisplayLink?
    private var live = false
    private var clock: Float = 0
    private var previousTime: CFTimeInterval?
    private var framingCenter = SCNVector3Zero
    private var framingRadius: Float = 1
    private let failureLabel = UILabel()

    @MainActor private final class TickTarget: NSObject {
        weak var owner: ArenaImportedModelView?
        init(_ owner: ArenaImportedModelView) { self.owner = owner }
        @objc func step(_ link: CADisplayLink) { owner?.tick(link) }
    }

    init() {
        super.init(frame: .zero, options: nil)
        scene = world
        backgroundColor = .clear
        world.background.contents = UIColor.clear
        antialiasingMode = .multisampling2X
        preferredFramesPerSecond = 30
        isPlaying = false
        rendersContinuously = false
        world.rootNode.addChildNode(turntable)
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = true
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.zFar = 10_000
        world.rootNode.addChildNode(cameraNode)
        pointOfView = cameraNode
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 500
        world.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 800
        key.eulerAngles = SCNVector3(-0.45, -0.45, 0)
        world.rootNode.addChildNode(key)
        failureLabel.text = "该模型暂时无法显示"
        failureLabel.textColor = .white
        failureLabel.textAlignment = .center
        failureLabel.numberOfLines = 0
        failureLabel.isHidden = true
        addSubview(failureLabel)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
        isAccessibilityElement = true
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init()") }

    func load(url: URL, name: String, idleAnimation: String?, heroID: String? = nil) {
        accessibilityLabel = "\(name)，左右拖动查看模型"
        guard loadedURL != url || loadedAnimation != idleAnimation else { return }
        loadedURL = url
        loadedAnimation = idleAnimation
        stop()
        instance?.root.removeFromParentNode()
        instance = nil
        model = nil
        clip = nil
        animator = nil
        sourceBounds = nil
        lastPoseTime = 0
        clock = 0
        turntable.eulerAngles = SCNVector3Zero
        accessibilityLabel = "\(name)，左右拖动查看模型"
        do {
            let imported = heroID.flatMap { ArenaImportedHeroAssets.shared.asset(id: $0) }
            let asset = try imported?.model ?? GLTFModel(url: url, maxTexture: 1024, smoothNormals: false)
            let made = asset.instantiate()
            guard !made.root.childNodes.isEmpty else { throw GLTFModel.LoadError.badFormat }
            model = asset
            instance = made
            pose = asset.restPose
            if let idleAnimation { clip = asset.clips[idleAnimation] }
            if let imported {
                animator = ArenaImportedHeroAnimator(asset: imported, instance: made)
                sourceBounds = imported.hero.modelBounds
            }
            turntable.addChildNode(made.root)
            applyPose()
            measure()
            fitCamera()
            failureLabel.isHidden = true
            if live { start() }
        } catch {
            failureLabel.isHidden = false
            accessibilityLabel = "\(name)，模型暂时无法显示"
        }
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        failureLabel.frame = bounds.insetBy(dx: 16, dy: 16)
        fitCamera()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else if live { start() }
    }

    func setLive(_ value: Bool) {
        live = value
        if value { start() } else { stop() }
    }
    @objc private func background() { stop() }
    @objc private func foreground() { if live { start() } }
    private func start() {
        guard link == nil, window != nil, model != nil, clip != nil || animator != nil,
              UIApplication.shared.applicationState == .active else { return }
        let timer = CADisplayLink(target: TickTarget(self), selector: #selector(TickTarget.step(_:)))
        timer.preferredFramesPerSecond = 30
        timer.add(to: .main, forMode: .common)
        link = timer
        previousTime = nil
    }
    private func stop() { link?.invalidate(); link = nil; previousTime = nil }
    private func tick(_ timer: CADisplayLink) {
        if let previousTime { clock += Float(min(max(timer.timestamp - previousTime, 0), 0.1)) }
        previousTime = timer.timestamp
        applyPose()
        setNeedsDisplay()
    }
    private func applyPose() {
        guard let model, let instance else { return }
        if let animator {
            animator.update(base: "lobby", delta: max(clock - lastPoseTime, 0), visible: true)
            lastPoseTime = clock
            return
        }
        pose.reset(from: model.restPose)
        if let clip {
            let time = clip.duration > 0 ? clock.truncatingRemainder(dividingBy: clip.duration) : 0
            clip.sample(at: time, into: &pose)
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        for i in model.animated where instance.nodes.indices.contains(i) {
            instance.nodes[i].simdTransform = pose.transform(i)
        }
        SCNTransaction.commit()
    }

    private func measure() {
        if let bounds = sourceBounds, bounds.count == 6 {
            let low = SIMD3<Float>(Float(bounds[0]), Float(bounds[1]), Float(bounds[2]))
            let high = SIMD3<Float>(Float(bounds[3]), Float(bounds[4]), Float(bounds[5]))
            let center = (low + high) * 0.5
            framingCenter = SCNVector3(center.x, center.y, center.z)
            framingRadius = max(simd_length(high - low) * 0.6, 0.01)
            return
        }
        guard let root = instance?.root else { return }
        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        root.enumerateChildNodes { node, _ in
            guard !node.isHidden, let geometry = node.geometry else { return }
            let (a, b) = geometry.boundingBox
            for x in [a.x, b.x] { for y in [a.y, b.y] { for z in [a.z, b.z] {
                let p = node.simdConvertPosition(SIMD3(x, y, z), to: self.turntable)
                low = simd_min(low, p)
                high = simd_max(high, p)
            } } }
        }
        guard low.x.isFinite, high.y.isFinite, high.y > low.y else { return }
        let center = (low + high) * 0.5
        framingCenter = SCNVector3(center.x, center.y, center.z)
        framingRadius = max(simd_length(high - low) * 0.5, 0.01)
    }
    private func fitCamera() {
        guard bounds.width > 0 && bounds.height > 0 else { return }
        let aspect = Float(bounds.width / bounds.height)
        // A sphere conservatively includes all corners while dragging; source
        // units are preserved instead of borrowing another hero's scale.
        cameraNode.camera?.orthographicScale = Double(framingRadius * 2.15 / min(aspect, 1))
        let direction = simd_normalize(SIMD3<Float>(0.38, 0.13, 1)) * framingRadius * 4
        cameraNode.position = SCNVector3(framingCenter.x + direction.x, framingCenter.y + direction.y, framingCenter.z + direction.z)
        cameraNode.look(at: framingCenter)
    }
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        let movement = gesture.translation(in: self)
        turntable.eulerAngles.y += Float(movement.x) * 0.012
        gesture.setTranslation(.zero, in: self)
        setNeedsDisplay()
    }
}
