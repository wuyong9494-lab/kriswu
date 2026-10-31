import SceneKit
import UIKit

/// A source-origin preserving plane driven by the original SC display list.
/// Timelines remain independent; special state or height frame selection is
/// explicitly static until a source-backed selector is implemented.
@MainActor
final class ArenaImportedSkillArt {
    let node = SCNNode()
    let playbackStatus: String
    let limitations: [String]
    private(set) var lastError: String?

    private static let emptyCanvas = ArenaFacePixels(width: 512, height: 512,
        rgba: [UInt8](repeating: 0, count: 512 * 512 * 4))
    private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 256
        return cache
    }()

    private let scene: ArenaFaceScene
    private let objectID: Int
    private let material: SCNMaterial
    private let crop: CGRect
    private let cachePrefix: String
    private let followsHeading: Bool
    private let headingOffset: Double
    private let animated: Bool
    private var lastSignature: String?
    private var lastElapsed: Double?

    static func prepare(binding: ArenaSkillArtworkSpecification.Binding,
                        selected: ArenaSkillArtworkSpecification.Export,
                        scene: ArenaFaceScene, cacheIdentity: String) throws {
        let crop = try sourceCrop(binding: binding, selected: selected)
        let prefix = imagePrefix(identity: cacheIdentity, selected: selected, crop: crop)
        _ = try image(scene: scene, root: selected.objectID, time: 0, prefix: prefix, crop: crop)
    }

    init(binding: ArenaSkillArtworkSpecification.Binding,
         selected: ArenaSkillArtworkSpecification.Export,
         scene: ArenaFaceScene, cacheIdentity: String,
         unitsPerSourcePoint: Double) throws {
        try binding.validate()
        let pps = binding.canvasPixelsPerSourcePoint
        let origin = binding.sourceOriginCanvas
        crop = try Self.sourceCrop(binding: binding, selected: selected)
        self.scene = scene
        objectID = selected.objectID
        playbackStatus = binding.playbackPolicy
        limitations = binding.limitations
        followsHeading = binding.rotationPolicy != "fixed_source_orientation"
        headingOffset = binding.rotationPolicy == "source_negative_x_follows_direction" ? .pi : 0
        animated = binding.playbackPolicy == "independent_absolute_clip_fps"
        cachePrefix = Self.imagePrefix(identity: cacheIdentity, selected: selected, crop: crop)

        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.blendMode = .alpha
        material.transparencyMode = .aOne
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.diffuse.minificationFilter = .linear
        material.diffuse.magnificationFilter = .linear
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        self.material = material

        let unit = unitsPerSourcePoint * binding.sourceScaleMultiplier / pps
        let plane = SCNPlane(width: crop.width * CGFloat(unit), height: crop.height * CGFloat(unit))
        plane.firstMaterial = material
        let display = SCNNode(geometry: plane)
        display.eulerAngles.x = -.pi / 2
        // The source origin is preserved even when its visible shape is not
        // centered. Image y grows down, mapping to positive host map z.
        display.position = SCNVector3(Float((Double(crop.midX) - origin[0]) * unit), 0,
                                     Float((Double(crop.midY) - origin[1]) * unit))
        display.castsShadow = false
        display.renderingOrder = 10
        node.addChildNode(display)
        node.castsShadow = false
        try render(time: 0)
        lastElapsed = 0
    }

    /// Elapsed time is the lifetime of this projectile/effect. Native FPS is
    /// retained when selecting source frames; display updates are capped at
    /// 30 Hz independently of simulation and movement.
    func update(elapsed: Double, direction: V2) {
        guard elapsed.isFinite, elapsed >= 0,
              direction.x.isFinite, direction.y.isFinite else {
            lastError = "Skill time and heading must be finite"
            return
        }
        if followsHeading, abs(direction.x) + abs(direction.y) > 1e-12 {
            node.eulerAngles.y = Float(headingOffset - atan2(direction.y, direction.x))
        }
        guard animated else { return }
        if let previous = lastElapsed, elapsed >= previous, elapsed - previous < 1.0 / 30.0 { return }
        do {
            try render(time: elapsed)
            lastElapsed = elapsed
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func render(time: Double) throws {
        let signature = try scene.signature(root: objectID, time: time)
        guard signature != lastSignature else { return }
        material.diffuse.contents = try Self.image(scene: scene, root: objectID,
            time: time, prefix: cachePrefix, crop: crop)
        lastSignature = signature
    }

    private static func sourceCrop(binding: ArenaSkillArtworkSpecification.Binding,
                                   selected: ArenaSkillArtworkSpecification.Export) throws -> CGRect {
        try binding.validate()
        let pps = binding.canvasPixelsPerSourcePoint
        let origin = binding.sourceOriginCanvas
        let bounds = selected.sourceBounds
        guard bounds.count == 4, bounds.allSatisfy(\.isFinite) else {
            throw ArenaSkillArtworkError.invalid("Invalid selected source skill bounds")
        }
        // Two transparent pixels retain sampling edges. The full timeline
        // bound is fixed for this instance, so animation never shifts the pivot.
        let left = floor(bounds[0] * pps + origin[0]) - 2
        let top = floor(bounds[1] * pps + origin[1]) - 2
        let right = ceil(bounds[2] * pps + origin[0]) + 2
        let bottom = ceil(bounds[3] * pps + origin[1]) + 2
        guard left >= 0, top >= 0, right <= 512, bottom <= 512,
              right > left, bottom > top else {
            throw ArenaSkillArtworkError.invalid("Source skill crop would truncate authored geometry")
        }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private static func imagePrefix(identity: String, selected: ArenaSkillArtworkSpecification.Export,
                                    crop: CGRect) -> String {
        identity + "|" + selected.exportName + "|\(crop.minX),\(crop.minY),\(crop.maxX),\(crop.maxY)"
    }

    private static func image(scene: ArenaFaceScene, root: Int, time: Double,
                              prefix: String, crop: CGRect) throws -> UIImage {
        let signature = try scene.signature(root: root, time: time)
        let key = (prefix + "|" + signature) as NSString
        let image: UIImage
        if let cached = images.object(forKey: key) {
            image = cached
        } else {
            let full = try scene.composite(root: root, time: time, base: emptyCanvas)
            // A copied bounded crop avoids caching a 1 MiB transparent canvas
            // for every tiny bullet. A CGImage crop alone can retain its parent.
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: crop.size, format: format)
            image = renderer.image { context in
                context.cgContext.interpolationQuality = .none
                full.draw(at: CGPoint(x: -crop.minX, y: -crop.minY))
            }
            images.setObject(image, forKey: key, cost: Int(crop.width * crop.height) * 4)
        }
        return image
    }
}
