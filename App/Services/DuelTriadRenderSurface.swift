import Foundation
import MetalKit
import QuartzCore
import SceneKit
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
        case device, samples, size, target, allocation, stopped, paused, tick
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
    private let gpu: MTLDevice
    private let queue: MTLCommandQueue
    private let completion = DuelTriadSurfaceCompletion()
    private let inFlight = DispatchSemaphore(value: 3)
    private var targets: Targets?
    private var stopped = false
    private var presentationPaused = false
    private(set) var lastSubmittedTick: Int?
    private(set) var submittedFrames = 0
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
        self.sceneRenderer = SCNRenderer(device: device, options: nil)
        super.init(frame: frame, device: device)
        colorPixelFormat = .bgra8Unorm
        // The drawable is the final single-sample copy target. Scene MSAA and
        // preserved depth are explicitly owned below, not MTKView's auto pass.
        sampleCount = 1; depthStencilPixelFormat = .invalid
        framebufferOnly = false; autoResizeDrawable = true
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

    /// World calls this after its existing fixed-step poses and packet submit.
    /// A display-only redraw uses exactly the same tick. No simulation, audio,
    /// animation marker or particle history is advanced here.
    func drawFrame(tick: Int, pointOfView: SCNNode?, samples: Int) throws {
        guard !stopped else { throw Failure.stopped }
        guard !presentationPaused else { return }
        if let failure = lastFailure { throw failure }
        guard window != nil, bounds.width > 0, bounds.height > 0 else { return }
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
              destination.textureType == .type2D else { throw Failure.target }
        let target = try renderTargets(width: destination.width, height: destination.height, samples: samples)
        let viewport = CGRect(x: 0, y: 0, width: destination.width, height: destination.height)
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
        if hasEffects || samples > 1 {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = hasEffects ? target.gamma : target.scene
            pass.colorAttachments[0].loadAction = .load
            if samples > 1 {
                pass.colorAttachments[0].resolveTexture = hasEffects ? target.resolvedGamma : target.resolvedScene
                pass.colorAttachments[0].storeAction = .multisampleResolve
            } else { pass.colorAttachments[0].storeAction = .store }
            if hasEffects {
                pass.depthAttachment.texture = target.depthStencil
                pass.depthAttachment.loadAction = .load
                pass.depthAttachment.storeAction = .dontCare
                pass.stencilAttachment.texture = target.depthStencil
                pass.stencilAttachment.loadAction = .load
                pass.stencilAttachment.storeAction = .dontCare
            }
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { throw Failure.allocation }
            do {
                defer { encoder.endEncoding() }
                if hasEffects {
                    try packetRenderer.encodeCurrent(on: encoder, format: Self.format(samples: samples), device: gpu,
                        viewport: MTLViewport(originX: 0, originY: 0, width: Double(destination.width),
                            height: Double(destination.height), znear: 0, zfar: 1))
                }
            }
        }
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { throw Failure.allocation }
        blit.copy(from: target.resolvedGamma, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: destination.width, height: destination.height, depth: 1),
            to: destination, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
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
        command.commit(); command.waitUntilCompleted()
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
        delegate = nil; isPaused = true
        sceneRenderer.delegate = nil; sceneRenderer.scene = nil; sceneRenderer.pointOfView = nil
        removeFromSuperview()
    }
}
