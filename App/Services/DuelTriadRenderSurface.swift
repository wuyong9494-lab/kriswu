import Foundation
import MetalKit
import QuartzCore
import SceneKit
import simd
import UIKit

/// Kept outside the MainActor view so Metal completion callbacks only touch
/// this explicitly locked value and never UIKit or SceneKit objects.
private final class DuelTriadSurfaceCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var failure: DuelTriadRenderSurface.Failure?
    var error: DuelTriadRenderSurface.Failure? { lock.lock(); defer { lock.unlock() }; return failure }
    func record(_ value: DuelTriadRenderSurface.Failure) {
        lock.lock(); defer { lock.unlock() }
        if failure == nil { failure = value }
    }
}

/// SceneKit keeps its sRGB scene pass. Original Gamma effects load the same
/// encoded colour bytes through a compatible unorm texture view, after
/// SceneKit has ended its own encoder. Depth/stencil and MSAA samples survive
/// between the two passes. Only public Metal/SceneKit APIs are used.
///
/// https://developer.apple.com/documentation/scenekit/scnrenderer/render(attime:viewport:commandbuffer:passdescriptor:)
/// https://developer.apple.com/documentation/metal/mtltexture/maketextureview(pixelformat:)
/// https://developer.apple.com/documentation/metal/setting-load-and-store-actions
@MainActor
final class DuelTriadRenderSurface: MTKView {
    typealias Format = DuelTriadSourceMaterial.Format
    enum Failure: Error, Equatable {
        case device, samples, size, target, allocation, stopped, paused, tick, projection, lateGeometry
        case command(String)
    }

    private struct Targets {
        let width: Int, height: Int, samples: Int
        let scene: MTLTexture, gamma: MTLTexture
        let resolvedScene: MTLTexture, resolvedGamma: MTLTexture
        let depthStencil: MTLTexture
    }
    let sceneRenderer: SCNRenderer
    let packetRenderer: DuelTriadMetalRenderer
    /// Original independent projector. Its map is encoded before the scene,
    /// then its recovered receiver multiplies the Gamma surface before FX.
    /// The two actors keep their own fade scalars in a shared source map.
    var projectedShadow: DuelSourceProjectedShadowRenderer?
    /// Native ModelSkin selects render-queue group 2 for the authenticated
    /// transparent H17 companions; SF3RenderSettings maps that group to 4852.
    /// Their primitive holders therefore follow receiver 2501 and FX 3000/3003.
    /// No other scene transparency is moved: all retained Palace transparent
    /// materials have recovered queues <= 2500.
    static let lateSourceCategory = 1 << 20
    var lateSourceGeometry: (() -> [SCNNode])?
    private let gpu: MTLDevice
    private let queue: MTLCommandQueue
    private let opaquePresentation: MTLRenderPipelineState
    private let completion = DuelTriadSurfaceCompletion()
    private let inFlight = DispatchSemaphore(value: 3)
    private var targets: Targets?
    private var stopped = false
    private var presentationPaused = false
    private var requestedRenderScale: CGFloat?
    private(set) var lastSubmittedTick: Int?
    private(set) var submittedFrames = 0
    /// A real render boundary, after command-buffer commit. This callback does
    /// not advance simulation time; source MORPH uses it to end its frame wait.
    var didSubmitFrame: (() -> Void)?
    var lastFailure: Failure? { completion.error }

    /// Apple's documented Simulator texture limits exclude 2x MSAA. The
    /// simulator validates 4x; this is never reported as real-device 2x proof.
    /// https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator
    static var multisampleCount: Int {
        #if targetEnvironment(simulator)
        return 4
        #else
        return 2
        #endif
    }

    static func format(samples: Int) -> Format {
        .init(color: .bgra8Unorm, depth: .depth32Float_stencil8,
            stencil: .depth32Float_stencil8, samples: samples == 2 ? multisampleCount : samples)
    }

    static func formats(device: MTLDevice?) throws -> [Format] {
        guard let device else { throw Failure.device }
        guard device.supportsTextureSampleCount(1), device.supportsTextureSampleCount(multisampleCount) else {
            throw Failure.samples
        }
        return [format(samples: 1), format(samples: 2)]
    }

    init(frame: CGRect = .zero, device: MTLDevice?, scene: SCNScene,
         pointOfView: SCNNode?, packets: DuelTriadMetalRenderer) throws {
        guard let device, let queue = device.makeCommandQueue() else { throw Failure.device }
        _ = try Self.formats(device: device)
        self.gpu = device; self.queue = queue; self.packetRenderer = packets
        let library = try device.makeLibrary(source: Self.opaquePresentationSource, options: nil)
        let presentation = MTLRenderPipelineDescriptor()
        presentation.vertexFunction = library.makeFunction(name: "duelPresentationVertex")
        presentation.fragmentFunction = library.makeFunction(name: "duelPresentationAlpha")
        presentation.colorAttachments[0].pixelFormat = .bgra8Unorm
        presentation.colorAttachments[0].writeMask = .alpha
        presentation.colorAttachments[0].isBlendingEnabled = false
        opaquePresentation = try device.makeRenderPipelineState(descriptor: presentation)
        self.sceneRenderer = SCNRenderer(device: device, options: nil)
        super.init(frame: frame, device: device)
        colorPixelFormat = .bgra8Unorm
        // The drawable is the final single-sample copy target. Scene MSAA and
        // preserved depth are explicitly owned below, not MTKView's auto pass.
        sampleCount = 1; depthStencilPixelFormat = .invalid
        // World owns the pixel budget, including mirror routes that connect
        // without changing this view's point size. UIKit's native-pixel default
        // must not silently undo the 1080p budget of the parent scene view.
        framebufferOnly = false; autoResizeDrawable = false
        isPaused = true; enableSetNeedsDisplay = false
        isOpaque = true; isUserInteractionEnabled = false
        isAccessibilityElement = false; accessibilityElementsHidden = true
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        }
        sceneRenderer.scene = scene; sceneRenderer.pointOfView = pointOfView
        sceneRenderer.usesReverseZ = false
        sceneRenderer.autoenablesDefaultLighting = false
        sceneRenderer.isPlaying = false
        // Source effects are encoded in our second pass, never twice through
        // the SceneKit delegate and then through the unorm surface.
        sceneRenderer.delegate = nil
        clearColor = MTLClearColorMake(0, 0, 0, 1)
        // Validate both required texture-view/sample configurations during
        // preparation, before World can report a successful source setup.
        _ = try renderTargets(width: 2, height: 2, samples: 1)
        _ = try renderTargets(width: 2, height: 2, samples: Self.multisampleCount)
        targets = nil
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setPaused(_ value: Bool) { presentationPaused = value }

    func applyRenderScale(_ scale: CGFloat) {
        guard !stopped, scale.isFinite, scale > 0 else { return }
        requestedRenderScale = scale
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        guard let budget = DuelDisplayRenderBudget(size: bounds.size,
            screenScale: requestedRenderScale ?? contentScaleFactor, casting: false) else { return }
        if contentScaleFactor != budget.scale { contentScaleFactor = budget.scale }
        if drawableSize != budget.drawableSize { drawableSize = budget.drawableSize }
    }

    /// World calls this after its existing fixed-step poses and packet submit.
    /// A display-only redraw uses exactly the same tick. No simulation, audio,
    /// animation marker or particle history is advanced here.
    func drawFrame(tick: Int, pointOfView: SCNNode?, samples: Int) throws {
        guard !stopped else { throw Failure.stopped }
        guard !presentationPaused else { return }
        if let failure = lastFailure { throw failure }
        guard window != nil, bounds.width > 0, bounds.height > 0 else { return }
        updateDrawableSize()
        guard inFlight.wait(timeout: .now()) == .success else { return }
        var submitted = false
        defer { if !submitted { inFlight.signal() } }
        guard let drawable = currentDrawable, let command = queue.makeCommandBuffer() else { return }
        sceneRenderer.pointOfView = pointOfView
        try encodeFrame(to: drawable.texture, atTick: tick, samples: samples, commandBuffer: command)
        let semaphore = inFlight, state = completion
        command.addCompletedHandler { command in
            if command.status == .error { state.record(.command(String(describing: command.error))) }
            semaphore.signal()
        }
        command.present(drawable); command.commit(); submitted = true
        lastSubmittedTick = tick; submittedFrames += 1
        didSubmitFrame?()
    }

    /// The same path is exposed to native acceptance with an explicit texture
    /// for deterministic readback. It never reads or writes a SceneKit drawable.
    func encodeFrame(to destination: MTLTexture, atTick tick: Int, samples: Int,
                     commandBuffer: MTLCommandBuffer) throws {
        guard !stopped else { throw Failure.stopped }
        guard !presentationPaused else { throw Failure.paused }
        if let failure = lastFailure { throw failure }
        guard (0...2_160_000).contains(tick) else { throw Failure.tick }
        guard [1, 2, Self.multisampleCount].contains(samples) else { throw Failure.samples }
        let samples = Self.format(samples: samples).samples
        guard gpu.supportsTextureSampleCount(samples) else { throw Failure.samples }
        guard destination.device.registryID == gpu.registryID,
              commandBuffer.device.registryID == gpu.registryID,
              destination.pixelFormat == .bgra8Unorm, destination.sampleCount == 1,
              destination.textureType == .type2D, destination.usage.contains(.renderTarget) else { throw Failure.target }
        let target = try renderTargets(width: destination.width, height: destination.height, samples: samples)
        let viewport = CGRect(x: 0, y: 0, width: destination.width, height: destination.height)
        let viewportSize = viewport.size
        let lateGeometry = lateSourceGeometry?() ?? []
        guard lateGeometry.count <= 512,
              Set(lateGeometry.map(ObjectIdentifier.init)).count == lateGeometry.count,
              lateGeometry.allSatisfy({ $0.geometry != nil && $0.categoryBitMask == Self.lateSourceCategory }) else {
            throw Failure.lateGeometry
        }
        let camera = sceneRenderer.pointOfView?.camera
        let cameraMask = camera?.categoryBitMask
        let hasLate = !lateGeometry.isEmpty && ((cameraMask ?? 0) & Self.lateSourceCategory) != 0
        if !lateGeometry.isEmpty && camera == nil { throw Failure.projection }
        // Masks are a camera/node intersection, not inherited layer state.
        // Only authenticated primitive holders carry the exclusive bit.
        // https://developer.apple.com/documentation/scenekit/scncamera/categorybitmask
        // These passes and synchronous captures can share one run-loop turn.
        // Automatic transactions would otherwise leave poses, visibility and
        // camera filtering at their previous presentation values. The real
        // Run10 late pass repainted that old scene in the unorm target.
        Self.commitPresentationChanges {
            if hasLate, let cameraMask { camera?.categoryBitMask = cameraMask & ~Self.lateSourceCategory }
        }
        defer {
            if hasLate, let cameraMask {
                Self.commitPresentationChanges { camera?.categoryBitMask = cameraMask }
            }
        }
        try projectedShadow?.encodeMap(on: commandBuffer, viewportSize: viewportSize, tick: tick)
        let scenePass = MTLRenderPassDescriptor()
        scenePass.colorAttachments[0].texture = target.scene
        scenePass.colorAttachments[0].loadAction = .clear
        scenePass.colorAttachments[0].clearColor = clearColor
        // Only store is needed here. The explicit next pass performs the
        // resolve, including on Simulator's more limited GPU feature family.
        scenePass.colorAttachments[0].storeAction = .store
        scenePass.depthAttachment.texture = target.depthStencil
        scenePass.depthAttachment.loadAction = .clear
        scenePass.depthAttachment.storeAction = .store
        scenePass.depthAttachment.clearDepth = 1
        scenePass.stencilAttachment.texture = target.depthStencil
        scenePass.stencilAttachment.loadAction = .clear
        scenePass.stencilAttachment.storeAction = .store
        scenePass.stencilAttachment.clearStencil = 0
        // SCNRenderer uses the caller-owned render pass; antialiasingMode is
        // a SCNView API. The color and depth textures carry the sample count.
        sceneRenderer.render(atTime: Double(tick) / 60, viewport: viewport,
            commandBuffer: commandBuffer, passDescriptor: scenePass)

        // With no source packets, keep SceneKit's resolved sRGB scene byte for
        // byte, including its edge resolve. Active source effects instead use
        // the original Gamma per-sample blend and Gamma resolve.
        let hasEffects = packetRenderer.submittedPacketCount > 0
        let hasGammaWork = hasEffects || projectedShadow != nil || hasLate
        if hasGammaWork || samples > 1 {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = hasGammaWork ? target.gamma : target.scene
            pass.colorAttachments[0].loadAction = .load
            if samples > 1 && !hasLate {
                pass.colorAttachments[0].resolveTexture = hasGammaWork ? target.resolvedGamma : target.resolvedScene
                pass.colorAttachments[0].storeAction = .multisampleResolve
            } else { pass.colorAttachments[0].storeAction = .store }
            if hasGammaWork {
                pass.depthAttachment.texture = target.depthStencil
                pass.depthAttachment.loadAction = .load
                pass.depthAttachment.storeAction = hasLate ? .store : .dontCare
                pass.stencilAttachment.texture = target.depthStencil
                pass.stencilAttachment.loadAction = .load
                pass.stencilAttachment.storeAction = hasLate ? .store : .dontCare
            }
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { throw Failure.allocation }
            do {
                defer { encoder.endEncoding() }
                if let projectedShadow {
                    guard let cameraNode = sceneRenderer.pointOfView, let camera = cameraNode.camera else {
                        throw Failure.projection
                    }
                    try projectedShadow.encodeReceiver(on: encoder, format: Self.format(samples: samples),
                        cameraProjection: DuelTriadMetalRenderer.cameraProjection(camera, viewportSize: viewportSize),
                        cameraView: simd_inverse(cameraNode.simdWorldTransform),
                        viewport: MTLViewport(originX: 0, originY: 0, width: Double(destination.width),
                            height: Double(destination.height), znear: 0, zfar: 1))
                }
                if hasEffects {
                    try packetRenderer.encodeCurrent(on: encoder, format: Self.format(samples: samples), device: gpu,
                        viewport: MTLViewport(originX: 0, originY: 0, width: Double(destination.width),
                            height: Double(destination.height), znear: 0, zfar: 1))
                }
            }
        }
        if hasLate, let cameraMask {
            // The source companion fragment emits original Gamma RGB. Draw
            // directly into the unorm view after the source receiver/FX, with
            // the first scene's depth still intact. Do not repaint the stage.
            let background = sceneRenderer.scene?.background.contents
            Self.commitPresentationChanges {
                camera?.categoryBitMask = cameraMask & Self.lateSourceCategory
                sceneRenderer.scene?.background.contents = nil
            }
            defer {
                Self.commitPresentationChanges { sceneRenderer.scene?.background.contents = background }
            }
            let late = MTLRenderPassDescriptor()
            late.colorAttachments[0].texture = target.gamma
            late.colorAttachments[0].loadAction = .load
            late.colorAttachments[0].storeAction = .store
            late.depthAttachment.texture = target.depthStencil
            late.depthAttachment.loadAction = .load
            late.depthAttachment.storeAction = .dontCare
            late.stencilAttachment.texture = target.depthStencil
            late.stencilAttachment.loadAction = .load
            late.stencilAttachment.storeAction = .dontCare
            // The pass-specific properties above are now committed. Keep one
            // timed update: a second render(atTime:) is not documented to be
            // idempotent for actions/physics merely because its time matches.
            // The draw-only call must not wait for the next run-loop commit
            // to see this layer; the native overlap test measures that path.
            // https://developer.apple.com/documentation/scenekit/scnrenderer/render(withviewport:commandbuffer:passdescriptor:)
            sceneRenderer.render(withViewport: viewport, commandBuffer: commandBuffer, passDescriptor: late)
            if samples > 1 {
                let resolve = MTLRenderPassDescriptor()
                resolve.colorAttachments[0].texture = target.gamma
                resolve.colorAttachments[0].loadAction = .load
                resolve.colorAttachments[0].resolveTexture = target.resolvedGamma
                resolve.colorAttachments[0].storeAction = .multisampleResolve
                guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: resolve) else {
                    throw Failure.allocation
                }
                encoder.endEncoding()
            }
        }
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { throw Failure.allocation }
        blit.copy(from: target.resolvedGamma, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: destination.width, height: destination.height, depth: 1),
            to: destination, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        if projectedShadow != nil || hasLate {
            // Keep the recovered receiver's full RGBA math available to every
            // subsequent source effect. Only the final opaque UIKit surface
            // drops that accumulated alpha; none of its RGB bytes change.
            // isOpaque requires opaque presented content, not a promise that
            // arbitrary intermediate shader alpha may be ignored by UIKit.
            // https://developer.apple.com/documentation/uikit/uiview/isopaque
            let presentation = MTLRenderPassDescriptor()
            presentation.colorAttachments[0].texture = destination
            presentation.colorAttachments[0].loadAction = .load
            presentation.colorAttachments[0].storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: presentation) else {
                throw Failure.allocation
            }
            encoder.setRenderPipelineState(opaquePresentation)
            encoder.setCullMode(.none)
            encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(destination.width),
                height: Double(destination.height), znear: 0, zfar: 1))
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
    }

    /// SceneKit normally flushes automatic transactions at the next run-loop
    /// iteration. Our adjacent passes need their presentation changes now,
    /// without starting an implicit animation or advancing a source tick.
    /// https://developer.apple.com/documentation/scenekit/scntransaction/flush()
    private static func commitPresentationChanges(_ changes: () -> Void) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true
        changes()
        SCNTransaction.commit()
        SCNTransaction.flush()
    }

    /// Explicit acceptance/diagnostic capture using the same command queue as
    /// presentation. It cannot race an in-flight frame on a second GPU queue.
    /// Normal gameplay never waits for GPU completion or calls this method.
    func captureFrame(tick: Int, pixelSize: CGSize, samples: Int) throws -> UIImage {
        guard pixelSize.width.isFinite, pixelSize.height.isFinite,
              pixelSize.width >= 1, pixelSize.height >= 1,
              pixelSize.width <= 2048, pixelSize.height <= 2048 else { throw Failure.size }
        let width = Int(pixelSize.width), height = Int(pixelSize.height)
        let description = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        description.storageMode = .shared; description.usage = .renderTarget
        guard let target = gpu.makeTexture(descriptor: description),
              let command = queue.makeCommandBuffer() else { throw Failure.allocation }
        try encodeFrame(to: target, atTick: tick, samples: samples, commandBuffer: command)
        command.commit(); didSubmitFrame?(); command.waitUntilCompleted()
        guard command.status == .completed else { throw Failure.command(String(describing: command.error)) }
        var data = Data(count: width * height * 4)
        data.withUnsafeMutableBytes {
            target.getBytes($0.baseAddress!, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue |
                    CGImageAlphaInfo.premultipliedFirst.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw Failure.allocation }
        return UIImage(cgImage: image)
    }

    private func renderTargets(width: Int, height: Int, samples: Int) throws -> Targets {
        guard width > 0, height > 0, width <= 8192, height <= 8192,
              width * height <= 16_777_216 else { throw Failure.size }
        if let targets, targets.width == width, targets.height == height, targets.samples == samples { return targets }
        func texture(_ format: MTLPixelFormat, _ count: Int) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                width: width, height: height, mipmapped: false)
            descriptor.textureType = count == 1 ? .type2D : .type2DMultisample
            descriptor.sampleCount = count; descriptor.storageMode = .private
            descriptor.usage = .renderTarget
            // Apple documents that sRGB/unorm views do not need the otherwise
            // costly pixelFormatView flag; component layout is unchanged.
            guard let value = gpu.makeTexture(descriptor: descriptor) else { throw Failure.allocation }
            return value
        }
        let scene = try texture(.bgra8Unorm_srgb, samples)
        let resolved = samples == 1 ? scene : try texture(.bgra8Unorm_srgb, 1)
        guard let gamma = scene.makeTextureView(pixelFormat: .bgra8Unorm),
              let resolvedGamma = resolved.makeTextureView(pixelFormat: .bgra8Unorm) else { throw Failure.allocation }
        let result = Targets(width: width, height: height, samples: samples, scene: scene, gamma: gamma,
            resolvedScene: resolved, resolvedGamma: resolvedGamma, depthStencil: try texture(.depth32Float_stencil8, samples))
        targets = result; return result
    }

    func shutdown() {
        guard !stopped else { return }
        stopped = true; presentationPaused = true; targets = nil
        projectedShadow?.shutdown(); projectedShadow = nil
        didSubmitFrame = nil; lateSourceGeometry = nil
        delegate = nil; isPaused = true
        sceneRenderer.delegate = nil; sceneRenderer.scene = nil; sceneRenderer.pointOfView = nil
        removeFromSuperview()
    }

    private static let opaquePresentationSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct DuelPresentationVertex { float4 position [[position]]; };
    vertex DuelPresentationVertex duelPresentationVertex(uint id [[vertex_id]]) {
        const float2 positions[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
        DuelPresentationVertex output; output.position = float4(positions[id], 0, 1); return output;
    }
    fragment half4 duelPresentationAlpha() { return half4(0, 0, 0, 1); }
    """
}
