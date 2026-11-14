import Foundation
import Metal
import SceneKit
import simd

/// Draws the ordered original-effect packets in SceneKit's current Metal pass.
/// The delegate callback reads immutable snapshots and never mutates SCNNodes.
/// Apple explicitly permits additional commands on currentRenderCommandEncoder
/// from SCNSceneRendererDelegate, including didRenderScene.
final class DuelTriadMetalRenderer: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    typealias Format = DuelTriadSourceMaterial.Format
    typealias Draw = DuelTriadSourceMaterial.Draw

    struct Frame: Sendable {
        let format: Format
        let draws: [Draw]
    }
    enum Failure: Error, Equatable {
        case unavailableMetal, unsupportedFormat, excessivePackets, stopped
        case missingEncoder, rendererChanged, projection, encode(String)
    }

    private let lock = NSLock()
    private let device: MTLDevice
    private let formats: Set<Format>
    private var current: Frame?
    private var failure: Failure?
    private var stopped = false

    init(device: MTLDevice?, formats: [Format]) throws {
        guard let device else { throw Failure.unavailableMetal }
        guard !formats.isEmpty, formats.count <= 4, Set(formats).count == formats.count,
              formats.allSatisfy({ $0.color != .invalid && [1, 2, 4].contains($0.samples) &&
                  device.supportsTextureSampleCount($0.samples) }) else { throw Failure.unsupportedFormat }
        self.device = device; self.formats = Set(formats)
        super.init()
    }

    /// Replacing a frame never advances simulation time. A repeated display
    /// refresh draws the same packet data until the authoritative tick changes.
    func submit(_ frame: Frame) throws {
        guard frame.draws.count <= 1536 else { throw Failure.excessivePackets }
        guard formats.contains(frame.format), frame.draws.allSatisfy({ $0.pipelines[frame.format] != nil }) else {
            throw Failure.unsupportedFormat
        }
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { throw Failure.stopped }
        if let failure { throw failure }
        current = frame
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        current = nil
    }
    func shutdown() {
        lock.lock(); defer { lock.unlock() }
        current = nil; stopped = true
    }
    var lastFailure: Failure? {
        lock.lock(); defer { lock.unlock() }
        return failure
    }
    var submittedPacketCount: Int {
        lock.lock(); defer { lock.unlock() }
        return current?.draws.count ?? 0
    }

    private func snapshot() -> Frame? {
        lock.lock(); defer { lock.unlock() }
        return stopped || failure != nil ? nil : current
    }
    private func record(_ value: Failure) {
        lock.lock(); defer { lock.unlock() }
        if failure == nil { failure = value }
        current = nil
    }

    /// A controlled render surface owns this encoder. SceneKit has already
    /// returned from its first pass, so no SceneKit-owned encoder is ended or
    /// retargeted. The same immutable packets also support the delegate path.
    func encodeCurrent(on encoder: MTLRenderCommandEncoder, format: Format,
                       device: MTLDevice, viewport: MTLViewport) throws {
        if let failure = lastFailure { throw failure }
        guard let frame = snapshot(), !frame.draws.isEmpty else { return }
        guard frame.format == format, device.registryID == self.device.registryID,
              viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 0, viewport.height > 0 else {
            record(.rendererChanged); throw Failure.rendererChanged
        }
        encoder.setViewport(viewport)
        encoder.setScissorRect(MTLScissorRect(x: 0, y: 0,
            width: Int(viewport.width), height: Int(viewport.height)))
        encoder.pushDebugGroup("Original H17 effect packets")
        defer { encoder.popDebugGroup() }
        do {
            // Interleaved blend modes remain in the original caller order.
            for draw in frame.draws { try draw.encode(on: encoder, format: frame.format) }
        } catch {
            let value = Failure.encode(String(describing: error))
            record(value); throw value
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        guard let frame = snapshot(), !frame.draws.isEmpty else { return }
        guard renderer.renderingAPI == .metal, !renderer.usesReverseZ,
              renderer.device?.registryID == device.registryID,
              renderer.colorPixelFormat == frame.format.color,
              renderer.depthPixelFormat == frame.format.depth,
              renderer.stencilPixelFormat == frame.format.stencil else {
            record(.rendererChanged); return
        }
        guard let encoder = renderer.currentRenderCommandEncoder else { record(.missingEncoder); return }
        encoder.pushDebugGroup("Original H17 effect packets")
        defer { encoder.popDebugGroup() }
        do {
            // Do not sort or batch by blend/material: the caller supplies the
            // original effect order, including interleaved premult/add/alpha.
            for draw in frame.draws { try draw.encode(on: encoder, format: frame.format) }
        } catch { record(.encode(String(describing: error))) }
    }

    /// Query the actual renderer formats, rather than assuming SceneKit's
    /// drawable or depth format. Read this during main-thread GPU preparation.
    @MainActor
    static func format(for renderer: SCNSceneRenderer, samples: Int) throws -> Format {
        guard renderer.renderingAPI == .metal, renderer.device != nil, !renderer.usesReverseZ,
              [1, 2, 4].contains(samples), renderer.device?.supportsTextureSampleCount(samples) == true,
              renderer.colorPixelFormat != .invalid else { throw Failure.unsupportedFormat }
        return Format(color: renderer.colorPixelFormat, depth: renderer.depthPixelFormat,
            stencil: renderer.stencilPixelFormat, samples: samples)
    }

    /// SceneKit synthesizes the projection from its real FOV/projection axis,
    /// orthographic scale, near/far and viewport aspect. Its public camera
    /// matrix can use OpenGL clip depth even when the rendering API is Metal.
    /// Inspect both depth endpoints instead of assuming a backend convention.
    /// https://developer.apple.com/documentation/scenekit/scncamera/projectiontransform(withviewportsize:)
    @MainActor
    static func cameraProjection(_ camera: SCNCamera, viewportSize: CGSize) throws -> simd_float4x4 {
        guard viewportSize.width.isFinite, viewportSize.height.isFinite,
              viewportSize.width > 0, viewportSize.height > 0,
              !camera.automaticallyAdjustsZRange else { throw Failure.projection }
        let matrix = simd_float4x4(camera.projectionTransform(withViewportSize: viewportSize))
        return try metalProjection(matrix, near: Float(camera.zNear), far: Float(camera.zFar))
    }

    static func metalProjection(_ projection: simd_float4x4, near: Float, far: Float) throws -> simd_float4x4 {
        guard DuelTriadSourceMaterial.finite(projection), near.isFinite, far.isFinite,
              near > 0, far > near else { throw Failure.projection }
        func depth(_ distance: Float) throws -> Float {
            let point = projection * SIMD4<Float>(0, 0, -distance, 1)
            guard DuelTriadSourceMaterial.finite(point), abs(point.w) > 1e-8 else { throw Failure.projection }
            return point.z / point.w
        }
        let n = try depth(near), f = try depth(far)
        guard abs(f - 1) <= 0.002 else { throw Failure.projection }
        if abs(n) <= 0.002 { return projection }
        guard abs(n + 1) <= 0.002 else { throw Failure.projection }
        var depthConversion = matrix_identity_float4x4
        depthConversion[2][2] = 0.5; depthConversion[3][2] = 0.5
        return depthConversion * projection
    }
}
