import CoreGraphics
import SceneKit
import simd
import SwiftUI
import UIKit

/// Metal-backed interactive SceneKit 3D Viewport for WUMIND「AI 3D 空间工坊」.
/// Renders articulated parametric architecture (palace roofs, columns, dougong, arched gates,
/// marble bridges, cabinets, modern glass curtain walls, circular stages), real-time Sunny/Snowy/Night
/// lighting & snowfall particles, tap-to-select highlighting, free-roam walkthrough, and live FPS HUD.
@MainActor
struct WuMindSpatial3DViewport: UIViewRepresentable {
    let sceneDoc: WuMindSpatialSceneDocument
    let sceneRevision: Int
    let selectedNodeID: UUID?
    let activeFloorFilter: Int?
    let hideRoofs: Bool
    let hideExteriorWalls: Bool
    let activeCameraPresetID: String?
    let cameraCommandRevision: Int
    let walkDeltaCommand: (id: UUID, dx: Float, dy: Float, dz: Float)?
    let onSelectNode: (UUID?) -> Void
    let onPerfUpdate: (Double, Double, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectNode: onSelectNode, onPerfUpdate: onPerfUpdate)
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = true
        scnView.antialiasingMode = .multisampling2X
        scnView.preferredFramesPerSecond = 60
        scnView.isPlaying = true
        scnView.rendersContinuously = true
        scnView.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        scnView.addGestureRecognizer(tap)

        context.coordinator.attachView(scnView)
        context.coordinator.rebuildScene(
            doc: sceneDoc,
            selectedNodeID: selectedNodeID,
            activeFloorFilter: activeFloorFilter,
            hideRoofs: hideRoofs,
            hideExteriorWalls: hideExteriorWalls,
            applyCameraPresetID: activeCameraPresetID ?? sceneDoc.cameraPresets.first?.id
        )
        context.coordinator.lastSceneRevision = sceneRevision
        context.coordinator.lastCameraRevision = cameraCommandRevision
        context.coordinator.lastSelectionID = selectedNodeID
        context.coordinator.lastFloorFilter = activeFloorFilter
        context.coordinator.lastHideRoofs = hideRoofs
        context.coordinator.lastHideWalls = hideExteriorWalls
        return scnView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SCNView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite else { return nil }
        return CGSize(width: width, height: height)
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        uiView.delegate = nil
        uiView.rendersContinuously = false
        uiView.isPlaying = false
    }

    func updateUIView(_ scnView: SCNView, context: Context) {
        let c = context.coordinator
        c.onSelectNode = onSelectNode
        c.onPerfUpdate = onPerfUpdate

        let needsRebuild = c.lastSceneRevision != sceneRevision
            || c.lastFloorFilter != activeFloorFilter
            || c.lastHideRoofs != hideRoofs
            || c.lastHideWalls != hideExteriorWalls

        if needsRebuild {
            c.lastSceneRevision = sceneRevision
            c.lastFloorFilter = activeFloorFilter
            c.lastHideRoofs = hideRoofs
            c.lastHideWalls = hideExteriorWalls
            c.lastSelectionID = selectedNodeID
            let camToApply = (c.lastCameraRevision != cameraCommandRevision) ? activeCameraPresetID : nil
            c.lastCameraRevision = cameraCommandRevision
            c.rebuildScene(
                doc: sceneDoc,
                selectedNodeID: selectedNodeID,
                activeFloorFilter: activeFloorFilter,
                hideRoofs: hideRoofs,
                hideExteriorWalls: hideExteriorWalls,
                applyCameraPresetID: camToApply
            )
            return
        }

        if c.lastSelectionID != selectedNodeID {
            c.lastSelectionID = selectedNodeID
            c.updateSelectionHighlight(selectedNodeID: selectedNodeID)
        }

        if c.lastCameraRevision != cameraCommandRevision {
            c.lastCameraRevision = cameraCommandRevision
            if let presetID = activeCameraPresetID,
               let preset = sceneDoc.cameraPresets.first(where: { $0.id == presetID }) {
                c.animateCamera(to: preset)
            }
        }

        if let walk = walkDeltaCommand, c.lastWalkCommandID != walk.id {
            c.lastWalkCommandID = walk.id
            c.applyFreeWalkDelta(dx: walk.dx, dy: walk.dy, dz: walk.dz)
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var onSelectNode: (UUID?) -> Void
        var onPerfUpdate: (Double, Double, Int) -> Void

        weak var scnView: SCNView?
        private var contentRootNode = SCNNode()
        private var highlightNode: SCNNode?
        private var nodeLookup: [UUID: SCNNode] = [:]

        var lastSceneRevision: Int = -1
        var lastCameraRevision: Int = -1
        var lastSelectionID: UUID?
        var lastFloorFilter: Int?
        var lastHideRoofs: Bool = false
        var lastHideWalls: Bool = false
        var lastWalkCommandID: UUID?

        private let fpsTracker = SpatialFPSTracker()

        init(
            onSelectNode: @escaping (UUID?) -> Void,
            onPerfUpdate: @escaping (Double, Double, Int) -> Void
        ) {
            self.onSelectNode = onSelectNode
            self.onPerfUpdate = onPerfUpdate
        }

        func attachView(_ view: SCNView) {
            self.scnView = view
        }

        func rebuildScene(
            doc: WuMindSpatialSceneDocument,
            selectedNodeID: UUID?,
            activeFloorFilter: Int?,
            hideRoofs: Bool,
            hideExteriorWalls: Bool,
            applyCameraPresetID: String?
        ) {
            guard let scnView else { return }
            let startTime = CFAbsoluteTimeGetCurrent()

            let scene = scnView.scene ?? SCNScene()
            if scnView.scene == nil {
                scnView.scene = scene
            }

            // Preserve current camera transform if user already orbited and no preset switch was requested
            let existingCamTransform = scnView.pointOfView?.simdTransform

            for child in scene.rootNode.childNodes {
                child.removeFromParentNode()
            }
            nodeLookup.removeAll()
            highlightNode = nil

            configureEnvironment(scene: scene, weather: doc.weather, sceneType: doc.sceneType)

            let root = SCNNode()
            root.name = "wumind_spatial_root"
            scene.rootNode.addChildNode(root)
            contentRootNode = root

            // Subtle expansive ground horizon plane so palace / pavilion feels grounded in world space
            let groundSpan: CGFloat = doc.sceneType == .imperialComplex ? 420 : (doc.sceneType == .interiorSpace ? 28 : 160)
            let horizonPlane = SCNFloor()
            horizonPlane.reflectivity = doc.weather == .snowy ? 0.04 : 0.02
            let hMat = SCNMaterial()
            hMat.lightingModel = .physicallyBased
            if doc.weather == .snowy {
                hMat.diffuse.contents = UIColor(red: 0.88, green: 0.91, blue: 0.95, alpha: 1)
                hMat.roughness.contents = 0.85
            } else if doc.weather == .nightSciFi {
                hMat.diffuse.contents = UIColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1)
                hMat.roughness.contents = 0.65
            } else {
                hMat.diffuse.contents = doc.sceneType == .interiorSpace
                    ? UIColor(red: 0.90, green: 0.90, blue: 0.89, alpha: 1)
                    : UIColor(red: 0.56, green: 0.54, blue: 0.48, alpha: 1)
                hMat.roughness.contents = 0.92
            }
            horizonPlane.materials = [hMat]
            let horizonNode = SCNNode(geometry: horizonPlane)
            horizonNode.position = SCNVector3(0, -0.14, 0)
            _ = groundSpan
            root.addChildNode(horizonNode)

            var visibleCount = 0
            for item in doc.nodes where item.isVisible {
                if let floor = activeFloorFilter, item.floorIndex > floor {
                    continue
                }
                if hideRoofs && item.category.isRoofCategory {
                    continue
                }
                if hideExteriorWalls && item.category.isExteriorWallCategory {
                    continue
                }

                let built = SpatialGeometryFactory.makeNode(
                    for: item,
                    weather: doc.weather,
                    hidePalaceRoofs: hideRoofs
                )
                built.name = "wumind_node_\(item.id.uuidString)"
                built.position = SCNVector3(item.positionMM.xMeters, item.positionMM.yMeters, item.positionMM.zMeters)
                built.eulerAngles = SCNVector3(0, Float(item.rotationYDeg * .pi / 180.0), 0)
                root.addChildNode(built)
                nodeLookup[item.id] = built
                visibleCount += 1
            }

            // Camera node
            let camNode = SCNNode()
            camNode.name = "wumind_main_camera"
            let cam = SCNCamera()
            cam.zNear = 0.15
            cam.zFar = 650.0
            cam.fieldOfView = 50
            cam.wantsHDR = true
            camNode.camera = cam
            scene.rootNode.addChildNode(camNode)
            scnView.pointOfView = camNode

            if let presetID = applyCameraPresetID,
               let preset = doc.cameraPresets.first(where: { $0.id == presetID }) {
                applyCameraTransform(camNode: camNode, preset: preset)
            } else if let prev = existingCamTransform {
                camNode.simdTransform = prev
            } else if let first = doc.cameraPresets.first {
                applyCameraTransform(camNode: camNode, preset: first)
            }

            if doc.weather == .snowy {
                attachSnowfallEmitter(to: scene.rootNode, sceneType: doc.sceneType)
            }

            updateSelectionHighlight(selectedNodeID: selectedNodeID)

            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            fpsTracker.recordBuild(loadMs: elapsedMs, visibleNodes: visibleCount)
        }

        func updateSelectionHighlight(selectedNodeID: UUID?) {
            highlightNode?.removeFromParentNode()
            highlightNode = nil
            guard let id = selectedNodeID, let target = nodeLookup[id] else { return }

            let (bMin, bMax) = target.boundingBox
            let pad: Float = 0.12
            let w = max(0.2, (bMax.x - bMin.x) + pad * 2)
            let h = max(0.2, (bMax.y - bMin.y) + pad * 2)
            let d = max(0.2, (bMax.z - bMin.z) + pad * 2)

            let box = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: 0.04)
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor(red: 1.0, green: 0.78, blue: 0.12, alpha: 0.18)
            mat.emission.contents = UIColor(red: 1.0, green: 0.75, blue: 0.10, alpha: 0.55)
            mat.isDoubleSided = true
            box.materials = [mat]

            let outline = SCNNode(geometry: box)
            outline.position = SCNVector3(
                (bMin.x + bMax.x) / 2,
                (bMin.y + bMax.y) / 2,
                (bMin.z + bMax.z) / 2
            )
            outline.renderingOrder = 10
            target.addChildNode(outline)
            highlightNode = outline
        }

        func animateCamera(to preset: WuMindSpatialCameraPreset) {
            guard let camNode = scnView?.pointOfView else { return }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.75
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            applyCameraTransform(camNode: camNode, preset: preset)
            SCNTransaction.commit()
        }

        func applyFreeWalkDelta(dx: Float, dy: Float, dz: Float) {
            guard let camNode = scnView?.pointOfView else { return }
            // Move along camera's horizontal forward/right basis so walkthrough feels intuitive from any angle
            let fwd = camNode.simdWorldFront
            var flatFwd = simd_float3(fwd.x, 0, fwd.z)
            let fLen = simd_length(flatFwd)
            if fLen > 0.001 { flatFwd /= fLen } else { flatFwd = simd_float3(0, 0, -1) }
            let right = simd_float3(-flatFwd.z, 0, flatFwd.x)
            let delta = right * dx + flatFwd * (-dz) + simd_float3(0, dy, 0)

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.22
            camNode.simdPosition += delta
            if camNode.simdPosition.y < 1.2 {
                camNode.simdPosition.y = 1.2
            }
            SCNTransaction.commit()
        }

        private func applyCameraTransform(camNode: SCNNode, preset: WuMindSpatialCameraPreset) {
            camNode.camera?.fieldOfView = CGFloat(preset.fovDeg)
            camNode.position = SCNVector3(preset.eyeMM.xMeters, preset.eyeMM.yMeters, preset.eyeMM.zMeters)
            camNode.look(at: SCNVector3(preset.targetMM.xMeters, preset.targetMM.yMeters, preset.targetMM.zMeters))
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scnView else { return }
            let pt = gesture.location(in: scnView)
            let hits = scnView.hitTest(pt, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue])
            for hit in hits {
                var current: SCNNode? = hit.node
                while let node = current {
                    if let name = node.name, name.hasPrefix("wumind_node_") {
                        let rawID = String(name.dropFirst("wumind_node_".count))
                        if let uuid = UUID(uuidString: rawID) {
                            onSelectNode(uuid)
                            return
                        }
                    }
                    current = node.parent
                }
            }
            onSelectNode(nil)
        }

        private func configureEnvironment(scene: SCNScene, weather: WuMindSpatialWeather, sceneType: WuMindSpatialSceneType) {
            let skyColor: UIColor
            let keyColor: UIColor
            let keyIntensity: CGFloat
            let ambientColor: UIColor
            let ambientIntensity: CGFloat

            switch weather {
            case .sunny:
                skyColor = sceneType == .interiorSpace
                    ? UIColor(red: 0.92, green: 0.94, blue: 0.97, alpha: 1)
                    : UIColor(red: 0.56, green: 0.76, blue: 0.94, alpha: 1)
                keyColor = UIColor(red: 1.0, green: 0.95, blue: 0.86, alpha: 1)
                keyIntensity = 1350
                ambientColor = UIColor(red: 0.78, green: 0.84, blue: 0.94, alpha: 1)
                ambientIntensity = 520
            case .snowy:
                skyColor = UIColor(red: 0.74, green: 0.80, blue: 0.88, alpha: 1)
                keyColor = UIColor(red: 0.90, green: 0.94, blue: 1.0, alpha: 1)
                keyIntensity = 980
                ambientColor = UIColor(red: 0.80, green: 0.86, blue: 0.95, alpha: 1)
                ambientIntensity = 680
            case .nightSciFi:
                skyColor = UIColor(red: 0.05, green: 0.07, blue: 0.13, alpha: 1)
                keyColor = UIColor(red: 0.62, green: 0.76, blue: 1.0, alpha: 1)
                keyIntensity = 680
                ambientColor = UIColor(red: 0.24, green: 0.30, blue: 0.48, alpha: 1)
                ambientIntensity = 380
            }

            scene.background.contents = skyColor
            scene.fogColor = skyColor
            scene.fogStartDistance = sceneType == .imperialComplex ? 140 : 60
            scene.fogEndDistance = sceneType == .imperialComplex ? 380 : 180
            scene.fogDensityExponent = 1.2

            // Primary Sun / Directional Key Light with soft shadows
            let keyLight = SCNLight()
            keyLight.type = .directional
            keyLight.color = keyColor
            keyLight.intensity = keyIntensity
            keyLight.castsShadow = true
            keyLight.shadowRadius = 3.0
            keyLight.shadowSampleCount = 4
            keyLight.shadowMapSize = CGSize(width: 2048, height: 2048)
            keyLight.orthographicScale = sceneType == .imperialComplex ? 110 : 28
            keyLight.zNear = 1
            keyLight.zFar = 320
            let keyNode = SCNNode()
            keyNode.light = keyLight
            keyNode.position = SCNVector3(65, 95, 75)
            keyNode.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(keyNode)

            // Cool Fill Light from opposite side so north/shadowed columns & eaves stay crisp
            let fillLight = SCNLight()
            fillLight.type = .directional
            fillLight.color = UIColor(red: 0.76, green: 0.86, blue: 1.0, alpha: 1)
            fillLight.intensity = weather == .nightSciFi ? 280 : 420
            let fillNode = SCNNode()
            fillNode.light = fillLight
            fillNode.position = SCNVector3(-70, 50, -60)
            fillNode.look(at: SCNVector3(0, 0, 0))
            scene.rootNode.addChildNode(fillNode)

            // Ambient hemisphere fill
            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.color = ambientColor
            ambient.intensity = ambientIntensity
            let ambientNode = SCNNode()
            ambientNode.light = ambient
            scene.rootNode.addChildNode(ambientNode)
        }

        private func attachSnowfallEmitter(to root: SCNNode, sceneType: WuMindSpatialSceneType) {
            let ps = SCNParticleSystem()
            ps.birthRate = sceneType == .imperialComplex ? 420 : 160
            ps.particleLifeSpan = 9.0
            ps.particleLifeSpanVariation = 3.0
            ps.particleSize = sceneType == .imperialComplex ? 0.34 : 0.12
            ps.particleSizeVariation = 0.12
            ps.particleColor = UIColor.white.withAlphaComponent(0.92)
            ps.particleVelocity = 4.5
            ps.particleVelocityVariation = 1.8
            ps.emittingDirection = SCNVector3(0.18, -1.0, 0.12)
            ps.spreadingAngle = 14
            let span: CGFloat = sceneType == .imperialComplex ? 170 : 45
            ps.emitterShape = SCNBox(width: span, height: 1, length: span, chamferRadius: 0)
            ps.birthLocation = .volume

            let emitterNode = SCNNode()
            emitterNode.position = SCNVector3(0, sceneType == .imperialComplex ? 58 : 18, 0)
            emitterNode.addParticleSystem(ps)
            root.addChildNode(emitterNode)
        }

        nonisolated func renderer(_ renderer: any SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
            guard !renderer.currentViewport.isEmpty, renderer.pointOfView != nil else { return }
            if let snapshot = fpsTracker.tick(time: time) {
                Task { @MainActor [weak self] in
                    self?.onPerfUpdate(snapshot.fps, snapshot.loadMs, snapshot.visibleNodes)
                }
            }
        }
    }
}

/// Thread-safe FPS & load telemetry tracker for live SceneKit performance measurement (0 concurrency warnings).
private final class SpatialFPSTracker: @unchecked Sendable {
    struct Snapshot: Sendable {
        let fps: Double
        let loadMs: Double
        let visibleNodes: Int
    }

    private let lock = NSLock()
    private var windowStart: TimeInterval = 0
    private var frameCount: Int = 0
    private var lastLoadMs: Double = 0.0
    private var lastVisibleNodes: Int = 0

    func recordBuild(loadMs: Double, visibleNodes: Int) {
        lock.lock()
        lastLoadMs = loadMs
        lastVisibleNodes = visibleNodes
        lock.unlock()
    }

    func tick(time: TimeInterval) -> Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        if windowStart == 0 {
            windowStart = time
            frameCount = 0
            return Snapshot(fps: 0, loadMs: lastLoadMs, visibleNodes: lastVisibleNodes)
        }
        frameCount += 1
        let dt = time - windowStart
        if dt >= 0.55 {
            let measured = min(120.0, max(1.0, Double(frameCount) / dt))
            windowStart = time
            frameCount = 0
            return Snapshot(fps: measured, loadMs: lastLoadMs, visibleNodes: lastVisibleNodes)
        }
        return nil
    }
}

// MARK: - Procedural Articulated Architectural Geometry Factory (Palace Roofs, Columns, Arched Gates, Bridges, Cabinets)

@MainActor
private enum SpatialGeometryFactory {

    private static var textureCache: [String: UIImage] = [:]

    static func makeNode(
        for spec: WuMindSpatialNode,
        weather: WuMindSpatialWeather,
        hidePalaceRoofs: Bool
    ) -> SCNNode {
        let container = SCNNode()
        let w = CGFloat(spec.sizeMM.xMeters)
        let h = CGFloat(spec.sizeMM.yMeters)
        let d = CGFloat(spec.sizeMM.zMeters)

        let bodyColor = uiColor(hex: spec.material.primaryHex)
        let roofHex = spec.material.roofHex ?? spec.material.roofPreset?.hexColor ?? WuMindSpatialMaterialPreset.glazedGoldTile.hexColor
        let roofColor = uiColor(hex: roofHex)

        switch spec.category {
        case .palaceHall:
            buildPalaceHall(
                into: container, w: w, h: h, d: d,
                bodyColor: bodyColor, roofColor: roofColor,
                detail: spec.detailProfile, weather: weather,
                hideRoof: hidePalaceRoofs
            )

        case .gateTower:
            buildGateTower(
                into: container, w: w, h: h, d: d,
                bodyColor: bodyColor, roofColor: roofColor,
                detail: spec.detailProfile, weather: weather,
                hideRoof: hidePalaceRoofs
            )

        case .cityWall:
            buildCityWall(into: container, w: w, h: h, d: d, bodyColor: bodyColor, roofColor: roofColor, weather: weather)

        case .waterway:
            buildWaterway(into: container, w: w, h: h, d: d, waterColor: bodyColor, detail: spec.detailProfile, weather: weather)

        case .courtyard, .road, .floorSlab:
            let geo = SCNBox(width: w, height: h, length: d, chamferRadius: 0.02)
            let mat = pbrMaterial(color: bodyColor, roughness: spec.material.preset.roughness, metalness: spec.material.preset.metalness)
            if spec.category == .courtyard {
                mat.diffuse.contents = cachedCourtyardTexture(snowy: weather == .snowy)
                mat.diffuse.wrapS = .repeat
                mat.diffuse.wrapT = .repeat
                mat.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(max(2, w / 6)), Float(max(2, d / 6)), 1)
            } else if weather == .snowy && spec.category == .road {
                mat.diffuse.contents = UIColor(red: 0.91, green: 0.93, blue: 0.96, alpha: 1)
            }
            geo.materials = [mat]
            let n = SCNNode(geometry: geo)
            n.position = SCNVector3(0, Float(h / 2), 0)
            container.addChildNode(n)

        case .cabinet:
            buildCabinet(into: container, w: w, h: h, d: d, bodyColor: bodyColor, topColor: spec.material.roofPreset != nil ? roofColor : uiColor(hex: "#EFECE4"))

        case .stairs:
            buildStairs(into: container, w: w, h: h, d: d, color: bodyColor)

        case .exhibitStage, .light:
            let mat = pbrMaterial(
                color: bodyColor,
                roughness: spec.material.preset.roughness,
                metalness: spec.material.preset.metalness,
                opacity: spec.material.opacity
            )
            if spec.category == .light || (weather == .nightSciFi && spec.category == .exhibitStage) {
                mat.emission.contents = roofColor.withAlphaComponent(spec.category == .light ? 0.85 : 0.22)
            }
            let geo: SCNGeometry = spec.detailProfile.isCylindrical
                ? SCNCylinder(radius: max(w, d) / 2, height: h)
                : SCNBox(width: w, height: h, length: d, chamferRadius: 0.04)
            geo.materials = [mat]
            let n = SCNNode(geometry: geo)
            n.position = SCNVector3(0, Float(h / 2), 0)
            container.addChildNode(n)

            if spec.detailProfile.isCylindrical && spec.category == .exhibitStage {
                let ring = SCNTorus(ringRadius: max(w, d) / 2 + 0.06, pipeRadius: 0.07)
                let ringMat = pbrMaterial(color: roofColor, roughness: 0.25, metalness: 0.80)
                if weather == .nightSciFi {
                    ringMat.emission.contents = roofColor.withAlphaComponent(0.75)
                }
                ring.materials = [ringMat]
                let ringNode = SCNNode(geometry: ring)
                ringNode.position = SCNVector3(0, Float(h), 0)
                container.addChildNode(ringNode)
            }

        case .landscape:
            buildLandscapeTrees(into: container, w: w, h: h, d: d, foliageColor: bodyColor, snowy: weather == .snowy)

        case .window:
            buildGlassCurtainWall(into: container, w: w, h: h, d: d, glassColor: bodyColor, opacity: spec.material.opacity)

        default:
            let geo = SCNBox(width: w, height: h, length: d, chamferRadius: 0.02)
            let mat = pbrMaterial(
                color: bodyColor,
                roughness: spec.material.preset.roughness,
                metalness: spec.material.preset.metalness,
                opacity: spec.material.opacity
            )
            if spec.category == .roof && weather == .snowy {
                mat.diffuse.contents = UIColor(red: 0.94, green: 0.96, blue: 0.99, alpha: 1)
            }
            geo.materials = [mat]
            let n = SCNNode(geometry: geo)
            n.position = SCNVector3(0, Float(h / 2), 0)
            container.addChildNode(n)
        }

        return container
    }

    // MARK: - Palace Hall (Stepped Xumi Terrace + Crimson Columns + Lattice Doors + Dougong + Double-Eave Tiled Roof)

    private static func buildPalaceHall(
        into parent: SCNNode,
        w: CGFloat, h: CGFloat, d: CGFloat,
        bodyColor: UIColor, roofColor: UIColor,
        detail: WuMindArchitecturalDetailProfile,
        weather: WuMindSpatialWeather,
        hideRoof: Bool
    ) {
        let plinthH = min(h * 0.36, max(0.6, CGFloat(detail.plinthHeightMM) / 1000.0))
        let bodyH = max(1.6, (h - plinthH) * 0.52)
        let roofH = max(1.2, h - plinthH - bodyH)

        let marbleMat = pbrMaterial(color: uiColor(hex: "#EFECE4"), roughness: 0.48, metalness: 0.04)
        let crimsonMat = pbrMaterial(color: bodyColor, roughness: 0.52, metalness: 0.06)
        let dougongMat = pbrMaterial(color: UIColor(red: 0.14, green: 0.38, blue: 0.36, alpha: 1), roughness: 0.42, metalness: 0.12)
        let roofMat = glazedRoofMaterial(color: roofColor, repeatX: max(4, Float(w / 1.5)), repeatY: max(3, Float(d / 1.8)))
        let snowMat = pbrMaterial(color: UIColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 1), roughness: 0.80, metalness: 0.02)

        // 1. Stepped White-Marble Xumi Plinth (2 or 3 tiers for grand main hall)
        let tiers = plinthH >= 3.2 ? 3 : (plinthH >= 1.8 ? 2 : 1)
        let tierH = plinthH / CGFloat(tiers)
        for t in 0..<tiers {
            let expand = 1.04 + CGFloat(tiers - 1 - t) * 0.09
            let slab = SCNBox(width: w * expand, height: tierH, length: d * (expand + 0.06), chamferRadius: 0.03)
            slab.materials = [marbleMat]
            let slabNode = SCNNode(geometry: slab)
            slabNode.position = SCNVector3(0, Float(CGFloat(t) * tierH + tierH / 2), 0)
            parent.addChildNode(slabNode)

            // White marble balustrade coping rail around terrace edge
            let railH: CGFloat = 0.38
            let railW = w * expand
            let railD = d * (expand + 0.06)
            let frontRail = SCNBox(width: railW, height: railH, length: 0.16, chamferRadius: 0.02)
            frontRail.materials = [marbleMat]
            let frNode = SCNNode(geometry: frontRail)
            frNode.position = SCNVector3(0, Float(CGFloat(t + 1) * tierH + railH / 2), Float(railD / 2 - 0.12))
            parent.addChildNode(frNode)
        }

        // Central axial stepped marble stairs + imperial ramp (丹陛石阶)
        let stepCount = min(10, max(4, Int(plinthH * 2.5)))
        let stairW = min(w * 0.36, 7.5)
        let stairRun = plinthH * 1.45
        for s in 0..<stepCount {
            let frac = CGFloat(s + 1) / CGFloat(stepCount)
            let sh = plinthH / CGFloat(stepCount)
            let stepGeo = SCNBox(width: stairW, height: sh, length: stairRun / CGFloat(stepCount) + 0.12, chamferRadius: 0.01)
            stepGeo.materials = [marbleMat]
            let stepNode = SCNNode(geometry: stepGeo)
            let zBase = d * (1.04 + CGFloat(tiers - 1) * 0.09 + 0.06) / 2
            stepNode.position = SCNVector3(
                0,
                Float(CGFloat(s) * sh + sh / 2),
                Float(zBase + stairRun * (1.0 - frac))
            )
            parent.addChildNode(stepNode)
        }

        // 2. Recessed Palace Core Wall with Golden Lattice Doors (隔扇门窗)
        let coreW = w * 0.84
        let coreD = d * 0.76
        let coreBox = SCNBox(width: coreW, height: bodyH, length: coreD, chamferRadius: 0.02)
        let doorMat = SCNMaterial()
        doorMat.lightingModel = .physicallyBased
        doorMat.diffuse.contents = cachedLatticeDoorTexture()
        doorMat.diffuse.wrapS = .repeat
        doorMat.diffuse.wrapT = .clamp
        doorMat.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(max(3, detail.columnCountX / 2)), 1, 1)
        doorMat.roughness.contents = 0.46
        coreBox.materials = [doorMat, crimsonMat, doorMat, crimsonMat, crimsonMat, crimsonMat]
        let coreNode = SCNNode(geometry: coreBox)
        coreNode.position = SCNVector3(0, Float(plinthH + bodyH / 2), 0)
        parent.addChildNode(coreNode)

        // 3. Perimeter Crimson Columns (朱红柱列)
        let colsX = max(4, min(12, detail.columnCountX > 0 ? detail.columnCountX : 6))
        let colRadius: CGFloat = max(0.18, min(0.42, w * 0.014))
        let colGeo = SCNCylinder(radius: colRadius, height: bodyH)
        colGeo.materials = [crimsonMat]
        let frontZ = Float(d * 0.44)
        let backZ = Float(-d * 0.44)
        for i in 0..<colsX {
            let t = colsX == 1 ? 0.5 : CGFloat(i) / CGFloat(colsX - 1)
            let cx = Float(-w * 0.45 + t * w * 0.90)
            for cz in [frontZ, backZ] {
                let col = SCNNode(geometry: colGeo)
                col.position = SCNVector3(cx, Float(plinthH + bodyH / 2), cz)
                parent.addChildNode(col)
            }
        }

        // 4. Painted Dougong Eaves Band (斗拱彩画额枋)
        let dgH: CGFloat = min(1.0, bodyH * 0.16)
        let dgBox = SCNBox(width: w * 0.96, height: dgH, length: d * 0.92, chamferRadius: 0.02)
        dgBox.materials = [dougongMat]
        let dgNode = SCNNode(geometry: dgBox)
        dgNode.position = SCNVector3(0, Float(plinthH + bodyH - dgH / 2), 0)
        parent.addChildNode(dgNode)

        guard !hideRoof else { return }

        // 5. Overhanging Pitched Imperial Roof (Single or Double-Tier 重檐庑殿顶)
        let roofBaseY = plinthH + bodyH
        if detail.eaveTiers >= 2 {
            let lowerH = roofH * 0.44
            let upperH = roofH * 0.56
            let lowerRoof = makeHipRoofSCNNode(w: w * 1.15, h: lowerH, d: d * 1.16, ridgeRatio: 0.62, material: roofMat)
            lowerRoof.position = SCNVector3(0, Float(roofBaseY), 0)
            parent.addChildNode(lowerRoof)

            // Clerestory neck between lower & upper eaves
            let neckH = lowerH * 0.48
            let neck = SCNBox(width: w * 0.78, height: neckH, length: d * 0.72, chamferRadius: 0.01)
            neck.materials = [dougongMat]
            let neckNode = SCNNode(geometry: neck)
            neckNode.position = SCNVector3(0, Float(roofBaseY + lowerH * 0.68), 0)
            parent.addChildNode(neckNode)

            let upperRoof = makeHipRoofSCNNode(w: w * 0.92, h: upperH, d: d * 0.90, ridgeRatio: 0.54, material: roofMat)
            upperRoof.position = SCNVector3(0, Float(roofBaseY + lowerH * 0.85), 0)
            parent.addChildNode(upperRoof)

            // Golden main roof ridge + chiwen ornaments
            addRoofRidgeBar(into: parent, ridgeW: w * 0.92 * 0.54, y: roofBaseY + lowerH * 0.85 + upperH, color: roofColor)

            if weather == .snowy {
                let snowLower = makeHipRoofSCNNode(w: w * 1.12, h: lowerH * 0.96, d: d * 1.13, ridgeRatio: 0.60, material: snowMat)
                snowLower.position = SCNVector3(0, Float(roofBaseY + 0.12), 0)
                parent.addChildNode(snowLower)
                let snowUpper = makeHipRoofSCNNode(w: w * 0.89, h: upperH * 0.96, d: d * 0.87, ridgeRatio: 0.52, material: snowMat)
                snowUpper.position = SCNVector3(0, Float(roofBaseY + lowerH * 0.85 + 0.14), 0)
                parent.addChildNode(snowUpper)
            }
        } else {
            let roof = makeHipRoofSCNNode(w: w * 1.14, h: roofH, d: d * 1.14, ridgeRatio: 0.56, material: roofMat)
            roof.position = SCNVector3(0, Float(roofBaseY), 0)
            parent.addChildNode(roof)
            addRoofRidgeBar(into: parent, ridgeW: w * 1.14 * 0.56, y: roofBaseY + roofH, color: roofColor)

            if weather == .snowy {
                let snow = makeHipRoofSCNNode(w: w * 1.10, h: roofH * 0.96, d: d * 1.10, ridgeRatio: 0.54, material: snowMat)
                snow.position = SCNVector3(0, Float(roofBaseY + 0.12), 0)
                parent.addChildNode(snow)
            }
        }
    }

    // MARK: - Gate Tower (Battered Red-Brick Base + Arched Portals + Parapets + Upper Double-Eave Pavilion)

    private static func buildGateTower(
        into parent: SCNNode,
        w: CGFloat, h: CGFloat, d: CGFloat,
        bodyColor: UIColor, roofColor: UIColor,
        detail: WuMindArchitecturalDetailProfile,
        weather: WuMindSpatialWeather,
        hideRoof: Bool
    ) {
        let baseH = min(h * 0.50, max(3.5, CGFloat(detail.plinthHeightMM) / 1000.0))
        let upperH = max(3.0, h - baseH)

        let wallMat = SCNMaterial()
        wallMat.lightingModel = .physicallyBased
        wallMat.diffuse.contents = cachedMasonryTexture(baseColor: bodyColor)
        wallMat.diffuse.wrapS = .repeat
        wallMat.diffuse.wrapT = .repeat
        wallMat.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(max(3, w / 4)), Float(max(2, baseH / 3)), 1)
        wallMat.roughness.contents = 0.82

        // 1. Massive City Gate Base Platform (城台)
        let baseBox = SCNBox(width: w, height: baseH, length: d, chamferRadius: 0.04)
        baseBox.materials = [wallMat]
        let baseNode = SCNNode(geometry: baseBox)
        baseNode.position = SCNVector3(0, Float(baseH / 2), 0)
        parent.addChildNode(baseNode)

        // Stone plinth trim + white marble parapet edge
        let marbleMat = pbrMaterial(color: uiColor(hex: "#E8E4DA"), roughness: 0.55, metalness: 0.04)
        let trim = SCNBox(width: w + 0.25, height: 0.45, length: d + 0.25, chamferRadius: 0.02)
        trim.materials = [marbleMat]
        let trimNode = SCNNode(geometry: trim)
        trimNode.position = SCNVector3(0, Float(baseH + 0.20), 0)
        parent.addChildNode(trimNode)

        // 2. Arched Gate Portals (券洞门道)
        let archCount = max(0, min(3, detail.archCount))
        if archCount > 0 {
            let darkTunnelMat = pbrMaterial(color: UIColor(red: 0.10, green: 0.09, blue: 0.11, alpha: 1), roughness: 0.95, metalness: 0.0)
            let archW = min(4.2, w / CGFloat(archCount * 2 + 1))
            let archH = min(baseH * 0.68, 5.2)
            for i in 0..<archCount {
                let offsetX: CGFloat = archCount == 1 ? 0 : (CGFloat(i) - CGFloat(archCount - 1) / 2.0) * (archW * 1.95)
                let portal = SCNBox(width: archW, height: archH, length: d + 0.18, chamferRadius: archW * 0.26)
                portal.materials = [darkTunnelMat]
                let pNode = SCNNode(geometry: portal)
                pNode.position = SCNVector3(Float(offsetX), Float(archH / 2), 0)
                parent.addChildNode(pNode)

                // Stone arch surround
                let frame = SCNBox(width: archW + 0.55, height: archH + 0.35, length: d + 0.08, chamferRadius: archW * 0.28)
                frame.materials = [marbleMat]
                let fNode = SCNNode(geometry: frame)
                fNode.position = SCNVector3(Float(offsetX), Float((archH + 0.35) / 2), 0)
                parent.addChildNode(fNode)
            }
        }

        // 3. Crenelated Battlements along front & back edges (城墙垛口)
        let merlonCount = max(4, Int(w / 2.4))
        let merlonGeo = SCNBox(width: 1.1, height: 1.0, length: 0.45, chamferRadius: 0.02)
        merlonGeo.materials = [weather == .snowy ? pbrMaterial(color: .white, roughness: 0.85, metalness: 0) : wallMat]
        for i in 0..<merlonCount {
            let t = CGFloat(i) / CGFloat(max(1, merlonCount - 1))
            let mx = Float(-w * 0.46 + t * w * 0.92)
            for mz in [Float(d / 2 - 0.25), Float(-d / 2 + 0.25)] {
                let m = SCNNode(geometry: merlonGeo)
                m.position = SCNVector3(mx, Float(baseH + 0.75), mz)
                parent.addChildNode(m)
            }
        }

        // 4. Upper Timber-Column Gate Pavilion (城楼重檐主体)
        let pavilionRoot = SCNNode()
        pavilionRoot.position = SCNVector3(0, Float(baseH + 0.35), 0)
        var upperDetail = detail
        upperDetail.plinthHeightMM = 500
        buildPalaceHall(
            into: pavilionRoot,
            w: w * 0.86,
            h: upperH,
            d: d * 0.78,
            bodyColor: bodyColor,
            roofColor: roofColor,
            detail: upperDetail,
            weather: weather,
            hideRoof: hideRoof
        )
        parent.addChildNode(pavilionRoot)
    }

    // MARK: - City Wall, Waterway + Arched Bridges, Cabinets, Stairs, Curtain Walls, Trees

    private static func buildCityWall(
        into parent: SCNNode,
        w: CGFloat, h: CGFloat, d: CGFloat,
        bodyColor: UIColor, roofColor: UIColor,
        weather: WuMindSpatialWeather
    ) {
        let copingH = min(0.75, h * 0.14)
        let wallMat = pbrMaterial(color: bodyColor, roughness: 0.78, metalness: 0.04)
        let body = SCNBox(width: w, height: h - copingH, length: d, chamferRadius: 0.02)
        body.materials = [wallMat]
        let bNode = SCNNode(geometry: body)
        bNode.position = SCNVector3(0, Float((h - copingH) / 2), 0)
        parent.addChildNode(bNode)

        let copingMat = weather == .snowy
            ? pbrMaterial(color: UIColor(red: 0.94, green: 0.96, blue: 1.0, alpha: 1), roughness: 0.80, metalness: 0.02)
            : glazedRoofMaterial(color: roofColor, repeatX: 2, repeatY: Float(max(4, d / 3)))
        let coping = SCNBox(width: w * 1.12, height: copingH, length: d + 0.2, chamferRadius: 0.06)
        coping.materials = [copingMat]
        let cNode = SCNNode(geometry: coping)
        cNode.position = SCNVector3(0, Float(h - copingH / 2), 0)
        parent.addChildNode(cNode)
    }

    private static func buildWaterway(
        into parent: SCNNode,
        w: CGFloat, h: CGFloat, d: CGFloat,
        waterColor: UIColor,
        detail: WuMindArchitecturalDetailProfile,
        weather: WuMindSpatialWeather
    ) {
        let waterMat = pbrMaterial(
            color: weather == .snowy ? UIColor(red: 0.64, green: 0.78, blue: 0.86, alpha: 1) : waterColor,
            roughness: weather == .snowy ? 0.25 : 0.08,
            metalness: 0.24,
            opacity: 0.90
        )
        let water = SCNBox(width: w, height: h, length: d, chamferRadius: 0.0)
        water.materials = [waterMat]
        let wNode = SCNNode(geometry: water)
        wNode.position = SCNVector3(0, Float(h / 2), 0)
        parent.addChildNode(wNode)

        // White-marble river embankment curbs
        let marbleMat = pbrMaterial(color: uiColor(hex: "#EFECE4"), roughness: 0.45, metalness: 0.04)
        for edgeZ in [Float(d / 2), Float(-d / 2)] {
            let curb = SCNBox(width: w, height: 0.45, length: 0.55, chamferRadius: 0.02)
            curb.materials = [marbleMat]
            let curbNode = SCNNode(geometry: curb)
            curbNode.position = SCNVector3(0, Float(h + 0.16), edgeZ)
            parent.addChildNode(curbNode)
        }

        // White-Marble Golden Water Bridges (汉白玉金水桥)
        if detail.hasBridgeArches {
            let bridgeCount = max(1, min(5, detail.archCount))
            let spacing: CGFloat = 10.5
            for i in 0..<bridgeCount {
                let bx = Float((CGFloat(i) - CGFloat(bridgeCount - 1) / 2.0) * spacing)
                let bw: CGFloat = i == bridgeCount / 2 ? 5.6 : 4.0
                let deck = SCNBox(width: bw, height: 0.65, length: d + 2.4, chamferRadius: 0.12)
                deck.materials = [marbleMat]
                let deckNode = SCNNode(geometry: deck)
                deckNode.position = SCNVector3(bx, Float(h + 0.52), 0)
                parent.addChildNode(deckNode)

                for sideX in [Float(-bw / 2 + 0.16), Float(bw / 2 - 0.16)] {
                    let rail = SCNBox(width: 0.26, height: 0.85, length: d + 2.2, chamferRadius: 0.04)
                    rail.materials = [marbleMat]
                    let rNode = SCNNode(geometry: rail)
                    rNode.position = SCNVector3(bx + sideX, Float(h + 1.15), 0)
                    parent.addChildNode(rNode)
                }
            }
        }
    }

    private static func buildCabinet(
        into parent: SCNNode,
        w: CGFloat, h: CGFloat, d: CGFloat,
        bodyColor: UIColor, topColor: UIColor
    ) {
        let topH: CGFloat = 0.055
        let kickH: CGFloat = h < 1.2 ? 0.09 : 0.0
        let bodyH = max(0.15, h - topH - kickH)

        let bodyMat = pbrMaterial(color: bodyColor, roughness: 0.55, metalness: 0.05)
        let topMat = pbrMaterial(color: topColor, roughness: 0.35, metalness: 0.08)

        if kickH > 0 {
            let kick = SCNBox(width: w - 0.04, height: kickH, length: d - 0.08, chamferRadius: 0.0)
            kick.materials = [pbrMaterial(color: UIColor(white: 0.22, alpha: 1), roughness: 0.8, metalness: 0.1)]
            let kNode = SCNNode(geometry: kick)
            kNode.position = SCNVector3(0, Float(kickH / 2), -0.03)
            parent.addChildNode(kNode)
        }

        let body = SCNBox(width: w, height: bodyH, length: d, chamferRadius: 0.01)
        body.materials = [bodyMat]
        let bNode = SCNNode(geometry: body)
        bNode.position = SCNVector3(0, Float(kickH + bodyH / 2), 0)
        parent.addChildNode(bNode)

        let top = SCNBox(width: w + 0.02, height: topH, length: d + 0.03, chamferRadius: 0.01)
        top.materials = [topMat]
        let tNode = SCNNode(geometry: top)
        tNode.position = SCNVector3(0, Float(h - topH / 2), 0.01)
        parent.addChildNode(tNode)
    }

    private static func buildStairs(into parent: SCNNode, w: CGFloat, h: CGFloat, d: CGFloat, color: UIColor) {
        let steps = 10
        let mat = pbrMaterial(color: color, roughness: 0.62, metalness: 0.04)
        let sh = h / CGFloat(steps)
        let sd = d / CGFloat(steps)
        for i in 0..<steps {
            let box = SCNBox(width: w, height: sh * CGFloat(i + 1), length: sd + 0.02, chamferRadius: 0.01)
            box.materials = [mat]
            let n = SCNNode(geometry: box)
            n.position = SCNVector3(0, Float(sh * CGFloat(i + 1) / 2), Float(-d / 2 + sd * (CGFloat(i) + 0.5)))
            parent.addChildNode(n)
        }
    }

    private static func buildGlassCurtainWall(
        into parent: SCNNode,
        w: CGFloat, h: CGFloat, d: CGFloat,
        glassColor: UIColor, opacity: Double
    ) {
        let glassMat = pbrMaterial(color: glassColor, roughness: 0.08, metalness: 0.18, opacity: opacity)
        let glass = SCNBox(width: w, height: h, length: d, chamferRadius: 0.0)
        glass.materials = [glassMat]
        let gNode = SCNNode(geometry: glass)
        gNode.position = SCNVector3(0, Float(h / 2), 0)
        parent.addChildNode(gNode)

        // Vertical architectural mullions
        let mullionMat = pbrMaterial(color: UIColor(white: 0.22, alpha: 1), roughness: 0.35, metalness: 0.72)
        let isLongX = w >= d
        let span = max(w, d)
        let count = max(3, min(10, Int(span / 2.6)))
        for i in 0..<count {
            let t = CGFloat(i) / CGFloat(max(1, count - 1)) - 0.5
            let mGeo = SCNBox(
                width: isLongX ? 0.12 : w + 0.08,
                height: h,
                length: isLongX ? d + 0.08 : 0.12,
                chamferRadius: 0.01
            )
            mGeo.materials = [mullionMat]
            let mNode = SCNNode(geometry: mGeo)
            mNode.position = SCNVector3(isLongX ? Float(t * span) : 0, Float(h / 2), isLongX ? 0 : Float(t * span))
            parent.addChildNode(mNode)
        }
    }

    private static func buildLandscapeTrees(
        into parent: SCNNode,
        w: CGFloat, h: CGFloat, d: CGFloat,
        foliageColor: UIColor, snowy: Bool
    ) {
        let trunkMat = pbrMaterial(color: UIColor(red: 0.36, green: 0.25, blue: 0.18, alpha: 1), roughness: 0.90, metalness: 0)
        let leafMat = pbrMaterial(color: foliageColor, roughness: 0.85, metalness: 0)
        let snowMat = pbrMaterial(color: UIColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 1), roughness: 0.82, metalness: 0)

        let offsets: [(Float, Float, CGFloat)] = [
            (0, 0, 1.0),
            (Float(w * 0.28), Float(d * 0.22), 0.82),
            (Float(-w * 0.26), Float(-d * 0.18), 0.74),
        ]
        for (ox, oz, scale) in offsets {
            let th = h * scale
            let tr = min(w, d) * 0.28 * scale
            let trunk = SCNCylinder(radius: tr * 0.22, height: th * 0.36)
            trunk.materials = [trunkMat]
            let tNode = SCNNode(geometry: trunk)
            tNode.position = SCNVector3(ox, Float(th * 0.18), oz)
            parent.addChildNode(tNode)

            for tier in 0..<2 {
                let coneH = th * (tier == 0 ? 0.44 : 0.36)
                let coneR = tr * (tier == 0 ? 1.0 : 0.72)
                let cone = SCNCone(topRadius: 0.08, bottomRadius: coneR, height: coneH)
                cone.materials = [snowy && tier == 1 ? snowMat : leafMat]
                let cNode = SCNNode(geometry: cone)
                cNode.position = SCNVector3(ox, Float(th * (tier == 0 ? 0.48 : 0.74)), oz)
                parent.addChildNode(cNode)
            }
        }
    }

    // MARK: - Custom Pitched Imperial Hip Roof SCNGeometry

    private static func makeHipRoofSCNNode(
        w: CGFloat, h: CGFloat, d: CGFloat,
        ridgeRatio: CGFloat,
        material: SCNMaterial
    ) -> SCNNode {
        let hx = Float(w / 2), hz = Float(d / 2), fh = Float(h)
        let rx = hx * Float(ridgeRatio)

        let blf = SCNVector3(-hx, 0, hz)
        let brf = SCNVector3(hx, 0, hz)
        let brb = SCNVector3(hx, 0, -hz)
        let blb = SCNVector3(-hx, 0, -hz)
        let rl  = SCNVector3(-rx, fh, 0)
        let rr  = SCNVector3(rx, fh, 0)

        var verts: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var indices: [Int32] = []

        func quad(_ a: SCNVector3, _ b: SCNVector3, _ c: SCNVector3, _ d: SCNVector3) {
            let base = Int32(verts.count)
            verts.append(contentsOf: [a, b, c, d])
            uvs.append(contentsOf: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)])
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }
        func tri(_ a: SCNVector3, _ b: SCNVector3, _ c: SCNVector3) {
            let base = Int32(verts.count)
            verts.append(contentsOf: [a, b, c])
            uvs.append(contentsOf: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0.5, y: 1)])
            indices.append(contentsOf: [base, base + 1, base + 2])
        }

        quad(blf, brf, rr, rl)
        quad(brb, blb, rl, rr)
        tri(brf, brb, rr)
        tri(blb, blf, rl)
        quad(blb, brb, brf, blf)

        let vSrc = SCNGeometrySource(vertices: verts)
        let tSrc = SCNGeometrySource(textureCoordinates: uvs)
        let elem = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geo = SCNGeometry(sources: [vSrc, tSrc], elements: [elem])
        geo.materials = [material]
        return SCNNode(geometry: geo)
    }

    private static func addRoofRidgeBar(into parent: SCNNode, ridgeW: CGFloat, y: CGFloat, color: UIColor) {
        let mat = pbrMaterial(color: color, roughness: 0.24, metalness: 0.25)
        let bar = SCNBox(width: ridgeW + 0.3, height: 0.42, length: 0.36, chamferRadius: 0.04)
        bar.materials = [mat]
        let node = SCNNode(geometry: bar)
        node.position = SCNVector3(0, Float(y + 0.16), 0)
        parent.addChildNode(node)

        // End ridge chiwen finials (正吻)
        for sign: CGFloat in [-1, 1] {
            let fin = SCNBox(width: 0.46, height: 0.85, length: 0.42, chamferRadius: 0.06)
            fin.materials = [mat]
            let fNode = SCNNode(geometry: fin)
            fNode.position = SCNVector3(Float(sign * (ridgeW / 2 + 0.08)), Float(y + 0.44), 0)
            parent.addChildNode(fNode)
        }
    }

    // MARK: - Procedural PBR Materials & Cached Architectural Textures

    private static func pbrMaterial(color: UIColor, roughness: Double, metalness: Double, opacity: Double = 1.0) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        mat.diffuse.contents = color
        mat.roughness.contents = roughness
        mat.metalness.contents = metalness
        mat.transparency = CGFloat(opacity)
        mat.isDoubleSided = opacity < 0.99
        return mat
    }

    private static func glazedRoofMaterial(color: UIColor, repeatX: Float, repeatY: Float) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        mat.diffuse.contents = cachedGlazedTileTexture(baseColor: color)
        mat.diffuse.wrapS = .repeat
        mat.diffuse.wrapT = .repeat
        mat.diffuse.contentsTransform = SCNMatrix4MakeScale(repeatX, repeatY, 1)
        mat.roughness.contents = 0.26
        mat.metalness.contents = 0.22
        mat.isDoubleSided = true
        return mat
    }

    private static func cachedGlazedTileTexture(baseColor: UIColor) -> UIImage {
        let key = "tile_\(baseColor.description)"
        if let cached = textureCache[key] { return cached }
        let size = CGSize(width: 128, height: 128)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            baseColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            // Vertical glazed tile ribs
            for x in stride(from: 0, to: 128, by: 16) {
                UIColor.black.withAlphaComponent(0.22).setFill()
                ctx.fill(CGRect(x: x, y: 0, width: 3, height: 128))
                UIColor.white.withAlphaComponent(0.20).setFill()
                ctx.fill(CGRect(x: x + 5, y: 0, width: 4, height: 128))
            }
            // Horizontal tile courses
            for y in stride(from: 0, to: 128, by: 24) {
                UIColor.black.withAlphaComponent(0.16).setFill()
                ctx.fill(CGRect(x: 0, y: y, width: 128, height: 2))
            }
        }
        textureCache[key] = img
        return img
    }

    private static func cachedMasonryTexture(baseColor: UIColor) -> UIImage {
        let key = "masonry_\(baseColor.description)"
        if let cached = textureCache[key] { return cached }
        let size = CGSize(width: 128, height: 128)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            baseColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.withAlphaComponent(0.18).setStroke()
            ctx.cgContext.setLineWidth(1.5)
            for row in 0..<8 {
                let y = CGFloat(row * 16)
                ctx.cgContext.move(to: CGPoint(x: 0, y: y))
                ctx.cgContext.addLine(to: CGPoint(x: 128, y: y))
                let offset = (row % 2 == 0) ? 0 : 16
                for col in stride(from: offset, to: 128, by: 32) {
                    ctx.cgContext.move(to: CGPoint(x: CGFloat(col), y: y))
                    ctx.cgContext.addLine(to: CGPoint(x: CGFloat(col), y: y + 16))
                }
            }
            ctx.cgContext.strokePath()
        }
        textureCache[key] = img
        return img
    }

    private static func cachedCourtyardTexture(snowy: Bool) -> UIImage {
        let key = snowy ? "courtyard_snow" : "courtyard_sun"
        if let cached = textureCache[key] { return cached }
        let size = CGSize(width: 128, height: 128)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let bg = snowy
                ? UIColor(red: 0.90, green: 0.93, blue: 0.97, alpha: 1)
                : UIColor(red: 0.78, green: 0.75, blue: 0.69, alpha: 1)
            bg.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.withAlphaComponent(snowy ? 0.08 : 0.14).setStroke()
            ctx.cgContext.setLineWidth(1.5)
            for p in stride(from: 0, to: 128, by: 32) {
                ctx.cgContext.move(to: CGPoint(x: p, y: 0)); ctx.cgContext.addLine(to: CGPoint(x: p, y: 128))
                ctx.cgContext.move(to: CGPoint(x: 0, y: p)); ctx.cgContext.addLine(to: CGPoint(x: 128, y: p))
            }
            ctx.cgContext.strokePath()
        }
        textureCache[key] = img
        return img
    }

    private static func cachedLatticeDoorTexture() -> UIImage {
        if let cached = textureCache["lattice_door"] { return cached }
        let size = CGSize(width: 128, height: 128)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.58, green: 0.12, blue: 0.10, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            // Upper golden window lattice
            UIColor(red: 0.94, green: 0.84, blue: 0.56, alpha: 1).setFill()
            ctx.fill(CGRect(x: 12, y: 12, width: 104, height: 56))
            UIColor(red: 0.52, green: 0.12, blue: 0.10, alpha: 1).setStroke()
            ctx.cgContext.setLineWidth(3)
            for x in stride(from: 12, through: 116, by: 26) {
                ctx.cgContext.move(to: CGPoint(x: x, y: 12)); ctx.cgContext.addLine(to: CGPoint(x: x, y: 68))
            }
            for y in stride(from: 12, through: 68, by: 14) {
                ctx.cgContext.move(to: CGPoint(x: 12, y: y)); ctx.cgContext.addLine(to: CGPoint(x: 116, y: y))
            }
            ctx.cgContext.strokePath()
            // Lower crimson door panels with gold trim
            UIColor(red: 0.82, green: 0.64, blue: 0.22, alpha: 0.7).setStroke()
            ctx.cgContext.setLineWidth(2)
            ctx.cgContext.stroke(CGRect(x: 14, y: 78, width: 46, height: 40))
            ctx.cgContext.stroke(CGRect(x: 68, y: 78, width: 46, height: 40))
        }
        textureCache["lattice_door"] = img
        return img
    }

    private static func uiColor(hex: String) -> UIColor {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count == 6, let val = UInt32(clean, radix: 16) else { return .lightGray }
        return UIColor(
            red: CGFloat((val >> 16) & 0xFF) / 255.0,
            green: CGFloat((val >> 8) & 0xFF) / 255.0,
            blue: CGFloat(val & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
