import CryptoKit
import Foundation
import Metal
import MetalKit
import QuartzCore
import UIKit

/// A GPU compositor for bounded SC display lists. Source group blends and soft
/// masks use tightly bounded intermediate textures. Consecutive equal-state
/// triangles are batched; full-screen CPU pixel loops are never used.
@MainActor
final class ArenaLobbyTimelineRenderer: NSObject, MTKViewDelegate {
    typealias Scene = ArenaLobbyTimelineScene
    struct Atlas: Sendable {
        let width: Int
        let height: Int
        let rgba: [UInt8]
    }
    struct Statistics {
        let drawCalls: Int
        let renderPasses: Int
        let transientPixels: Int
        let sourceTime: Double
        let sourceClipFrames: [Int: Int]
    }
    private struct Mask {
        let texture: MTLTexture
        let rect: Scene.Rect
    }
    private struct PreparedDraw {
        let texture: MTLTexture
        let vertices: [Scene.Vertex]
        let blend: Int
        let framebuffer: Bool
        let mask: Mask?
    }
    private final class FramePool {
        struct Key: Hashable { let width: Int; let height: Int }
        var buckets: [Key: [MTLTexture]] = [:]
        var used: [Key: Int] = [:]
        var pixels = 0
        var retainedPixels = 0
        func reset() {
            used.removeAll(keepingCapacity: true)
            pixels = 0
            if retainedPixels > 24_000_000 {
                buckets.removeAll(); retainedPixels = 0
            }
        }
        func texture(device: MTLDevice, width: Int, height: Int) throws -> MTLTexture {
            // Small buckets prevent a moving sprite's one-pixel bounds changes
            // from retaining an unbounded set of differently sized textures.
            let w = ((width + 15) / 16) * 16, h = ((height + 15) / 16) * 16
            guard w > 0, h > 0, w <= 8192, h <= 8192,
                  pixels <= 16_000_000 - w*h else {
                throw ArenaLobbyTimelineError.invalid("Lobby intermediate textures exceed their frame budget")
            }
            pixels += w*h
            let key = Key(width: w, height: h), index = used[key, default: 0]
            used[key] = index + 1
            if let values = buckets[key], values.indices.contains(index) { return values[index] }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                width: w, height: h, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = [.renderTarget, .shaderRead]
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw ArenaLobbyTimelineError.invalid("Unable to allocate a lobby intermediate texture")
            }
            texture.label = "Lobby bounded group \(w)x\(h)"
            buckets[key, default: []].append(texture)
            retainedPixels += w*h
            return texture
        }
    }

    let scene: Scene
    let device: MTLDevice
    var onFailure: ((String) -> Void)?
    var onFirstFrame: (() -> Void)?
    private(set) var lastStatistics: Statistics?
    private let queue: MTLCommandQueue
    private let textures: [MTLTexture]
    private let whiteTexture: MTLTexture
    private let pipelines: [Int: MTLRenderPipelineState]
    private let inFlight = DispatchSemaphore(value: 3)
    private let pools = [FramePool(), FramePool(), FramePool()]
    private var poolIndex = 0
    private var epoch = CACurrentMediaTime()
    private var pauseStarted: Double?
    private var failed = false
    private var firstFrameDelivered = false
    private var drawCalls = 0
    private var renderPasses = 0

    nonisolated static func loadAtlases(document: ArenaLobbyTimelineDocument,
                                      resourceURL: (String) -> URL?) throws -> [Atlas] {
        try document.textures.map { entry in
            try Task.checkCancellation()
            guard let url = resourceURL(entry.file), url.isFileURL else {
                throw ArenaLobbyTimelineError.invalid("Lobby atlas is not approved by the resource pack")
            }
            let info = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard info.isRegularFile == true, let count = info.fileSize, count > 0, count <= 64*1024*1024 else {
                throw ArenaLobbyTimelineError.invalid("Lobby atlas exceeds its reading limit")
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard hash == entry.sha256 else { throw ArenaLobbyTimelineError.invalid("Lobby atlas hash mismatch") }
            // Use the same checked ImageIO boundary as source faces: the PNG
            // is explicitly straight; Core Graphics returns premultiplied RGBA.
            let pixels = try ArenaFacePixels(data: data)
            try Task.checkCancellation()
            guard pixels.width == entry.width, pixels.height == entry.height,
                  entry.alphaEncoding == "straight" else {
                throw ArenaLobbyTimelineError.invalid("Lobby atlas dimensions or alpha encoding differ")
            }
            return Atlas(width: pixels.width, height: pixels.height, rgba: pixels.rgba)
        }
    }

    init(device: MTLDevice, scene: Scene, atlases: [Atlas]) throws {
        guard let queue = device.makeCommandQueue(), atlases.count == scene.document.textures.count else {
            throw ArenaLobbyTimelineError.invalid("Metal is unavailable for the lobby")
        }
        self.scene = scene
        self.device = device
        self.queue = queue
        let library = try device.makeLibrary(source: ArenaLobbyTimelineShaders.source, options: nil)
        guard let vertex = library.makeFunction(name: "arenaLobbyVertex"),
              let fragment = library.makeFunction(name: "arenaLobbyFragment") else {
            throw ArenaLobbyTimelineError.invalid("Lobby Metal functions are unavailable")
        }
        var states: [Int: MTLRenderPipelineState] = [:]
        for blend in [0, 4, 8] {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "Lobby source blend \(blend)"
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            let color = descriptor.colorAttachments[0]!
            color.pixelFormat = .bgra8Unorm
            color.isBlendingEnabled = true
            color.rgbBlendOperation = .add
            color.alphaBlendOperation = .add
            color.sourceRGBBlendFactor = .one
            color.sourceAlphaBlendFactor = .one
            switch blend {
            case 0:
                color.destinationRGBBlendFactor = .oneMinusSourceAlpha
                color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            case 4:
                color.destinationRGBBlendFactor = .oneMinusSourceColor
                color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            default:
                color.destinationRGBBlendFactor = .one
                color.destinationAlphaBlendFactor = .one
            }
            states[blend] = try device.makeRenderPipelineState(descriptor: descriptor)
        }
        pipelines = states
        textures = try atlases.map { atlas in
            guard atlas.width > 0, atlas.height > 0,
                  atlas.rgba.count == atlas.width*atlas.height*4 else {
                throw ArenaLobbyTimelineError.invalid("Malformed lobby atlas pixels")
            }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                width: atlas.width, height: atlas.height, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.shaderRead]
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw ArenaLobbyTimelineError.invalid("Unable to allocate a lobby atlas")
            }
            atlas.rgba.withUnsafeBytes { raw in
                texture.replace(region: MTLRegionMake2D(0,0,atlas.width,atlas.height),
                    mipmapLevel: 0, withBytes: raw.baseAddress!, bytesPerRow: atlas.width*4)
            }
            return texture
        }
        let white = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        white.storageMode = .shared; white.usage = [.shaderRead]
        guard let fallback = device.makeTexture(descriptor: white) else {
            throw ArenaLobbyTimelineError.invalid("Unable to allocate the identity mask")
        }
        let rgba: [UInt8] = [255,255,255,255]
        rgba.withUnsafeBytes { raw in
            fallback.replace(region: MTLRegionMake2D(0,0,1,1), mipmapLevel: 0,
                             withBytes: raw.baseAddress!, bytesPerRow: 4)
        }
        whiteTexture = fallback
        super.init()
        guard MemoryLayout<Scene.Vertex>.stride == 48 else {
            throw ArenaLobbyTimelineError.invalid("Lobby vertex layout does not match its shader")
        }
        epoch = CACurrentMediaTime()
    }

    func suspend() {
        if pauseStarted == nil { pauseStarted = CACurrentMediaTime() }
    }
    func resume() {
        if let pauseStarted { epoch += CACurrentMediaTime()-pauseStarted; self.pauseStarted = nil }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard !failed, pauseStarted == nil, view.drawableSize.width > 0, view.drawableSize.height > 0,
              inFlight.wait(timeout: .now()) == .success else { return }
        guard let descriptor = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer() else { inFlight.signal(); return }
        let pool = pools[poolIndex]
        poolIndex = (poolIndex+1) % pools.count
        pool.reset()
        let time = firstFrameDelivered ? max(0, CACurrentMediaTime()-epoch) : 0
        let semaphore = inFlight
        command.addCompletedHandler { [weak self] buffer in
            semaphore.signal()
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error = buffer.error { self.reportFailure(error.localizedDescription) }
                else if !self.failed, !self.firstFrameDelivered {
                    self.firstFrameDelivered = true
                    self.epoch = CACurrentMediaTime()
                    if self.pauseStarted != nil { self.pauseStarted = self.epoch }
                    self.onFirstFrame?()
                }
            }
        }
        do {
            let viewport = Self.aspectFillRect(scene.sourceRect, width: Double(view.drawableSize.width), height: Double(view.drawableSize.height))
            let density = min(2, max(1, Double(view.drawableSize.width)/viewport.width))
            let frame = try scene.frame(time: time)
            drawCalls = 0; renderPasses = 0
            let prepared = try prepare(frame.operations, mask: nil, command: command, pool: pool, density: density)
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].storeAction = .store
            descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0)
            try encode(prepared, descriptor: descriptor, viewport: viewport, command: command)
            lastStatistics = Statistics(drawCalls: drawCalls, renderPasses: renderPasses,
                transientPixels: pool.pixels, sourceTime: time, sourceClipFrames: frame.clipFrames)
            command.present(drawable)
            command.commit()
        } catch {
            // A partially encoded command is never presented. Committing it
            // still releases its retained resources and the in-flight slot.
            command.commit()
            reportFailure(error.localizedDescription)
        }
    }

    private func reportFailure(_ reason: String) {
        guard !failed else { return }
        failed = true
        onFailure?(reason)
    }

    static func aspectFillRect(_ source: Scene.Rect, width: Double, height: Double) -> Scene.Rect {
        guard width > 0, height > 0 else { return source }
        let scale = max(width/source.width, height/source.height)
        let w = width/scale, h = height/scale
        let x = source.minX+(source.width-w)/2, y = source.minY+(source.height-h)/2
        return Scene.Rect([x,y,x+w,y+h])
    }

    private func quad(texture: MTLTexture, rect: Scene.Rect, blend: Int = 0, mask: Mask? = nil) -> PreparedDraw {
        let corners: [(Double,Double,Float,Float)] = [
            (rect.minX,rect.minY,0,0), (rect.minX,rect.maxY,0,1), (rect.maxX,rect.minY,1,0),
            (rect.maxX,rect.minY,1,0), (rect.minX,rect.maxY,0,1), (rect.maxX,rect.maxY,1,1)]
        return PreparedDraw(texture: texture, vertices: corners.map { x,y,u,v in
            Scene.Vertex(position: SIMD2(Float(x),Float(y)), uv: SIMD2(u,v),
                         multiply: SIMD4(repeating: 1), add: .zero)
        }, blend: blend, framebuffer: true, mask: mask)
    }

    private func textureRect(_ bounds: Scene.Rect) -> Scene.Rect? {
        Scene.Rect([floor(bounds.minX)-1, floor(bounds.minY)-1,
                    ceil(bounds.maxX)+1, ceil(bounds.maxY)+1]).intersection(scene.sourceRect)
    }

    private func renderTexture(_ operations: [Scene.Operation], bounds: Scene.Rect,
                               command: MTLCommandBuffer, pool: FramePool, density: Double) throws -> Mask? {
        guard let rect = textureRect(bounds) else { return nil }
        let prepared = try prepare(operations, mask: nil, command: command, pool: pool, density: density)
        let texture = try pool.texture(device: device, width: Int(ceil(rect.width*density)), height: Int(ceil(rect.height*density)))
        try encode(prepared, texture: texture, viewport: rect, command: command)
        return Mask(texture: texture, rect: rect)
    }

    private func prepare(_ operations: [Scene.Operation], mask: Mask?, command: MTLCommandBuffer,
                         pool: FramePool, density: Double) throws -> [PreparedDraw] {
        var result: [PreparedDraw] = []
        for operation in operations {
            switch operation {
            case .draw(let draw):
                result.append(PreparedDraw(texture: textures[draw.textureIndex], vertices: draw.vertices,
                    blend: draw.blendMode, framebuffer: false, mask: mask))
            case .layer(let children, let blend, let bounds):
                guard pipelines[blend] != nil else { throw ArenaLobbyTimelineError.invalid("Unsupported lobby group blend") }
                if children.count == 1, case .draw(let draw) = children[0], draw.blendMode == 0 {
                    result.append(PreparedDraw(texture: textures[draw.textureIndex], vertices: draw.vertices,
                        blend: blend, framebuffer: false, mask: mask))
                } else if let layer = try renderTexture(children, bounds: bounds, command: command, pool: pool, density: density) {
                    result.append(quad(texture: layer.texture, rect: layer.rect, blend: blend, mask: mask))
                }
            case .masked(let maskOperations, let content, let bounds):
                let maskBounds = maskOperations.map(\.bounds).reduce(nil as Scene.Rect?) { previous,next in
                    previous.map { $0.union(next) } ?? next
                }
                guard let maskBounds, let tight = maskBounds.intersection(bounds),
                      var combined = try renderTexture(maskOperations, bounds: tight, command: command, pool: pool, density: density) else { continue }
                if let parent = mask {
                    guard let rect = combined.rect.intersection(parent.rect) else { continue }
                    let texture = try pool.texture(device: device, width: Int(ceil(rect.width*density)), height: Int(ceil(rect.height*density)))
                    try encode([quad(texture: combined.texture, rect: combined.rect, mask: parent)],
                        texture: texture, viewport: rect, command: command)
                    combined = Mask(texture: texture, rect: rect)
                }
                // Apply the mask to each source fragment/group in order. Baking
                // every masked child into one normal layer changes ADD/SCREEN.
                result.append(contentsOf: try prepare(content, mask: combined, command: command, pool: pool, density: density))
            }
        }
        return result
    }

    private func encode(_ draws: [PreparedDraw], texture: MTLTexture, viewport: Scene.Rect,
                        command: MTLCommandBuffer) throws {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0)
        try encode(draws, descriptor: descriptor, viewport: viewport, command: command)
    }

    private func encode(_ draws: [PreparedDraw], descriptor: MTLRenderPassDescriptor,
                        viewport: Scene.Rect, command: MTLCommandBuffer) throws {
        guard let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else {
            throw ArenaLobbyTimelineError.invalid("Unable to encode a lobby render pass")
        }
        defer { encoder.endEncoding() }
        renderPasses += 1
        guard !draws.isEmpty else { return }
        let allVertices = draws.flatMap(\.vertices)
        guard !allVertices.isEmpty else { return }
        let length = allVertices.count * MemoryLayout<Scene.Vertex>.stride
        guard let buffer = allVertices.withUnsafeBytes({ raw in
            device.makeBuffer(bytes: raw.baseAddress!, length: length, options: .storageModeShared)
        }) else { throw ArenaLobbyTimelineError.invalid("Unable to allocate lobby geometry") }
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        var region = SIMD4(Float(viewport.minX),Float(viewport.minY),Float(viewport.width),Float(viewport.height))
        encoder.setVertexBytes(&region, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
        var offset = 0, index = 0
        while index < draws.count {
            let first = draws[index]
            guard let pipeline = pipelines[first.blend] else { throw ArenaLobbyTimelineError.invalid("Unknown lobby draw blend") }
            var count = first.vertices.count
            var next = index+1
            while next < draws.count, sameState(first, draws[next]) {
                count += draws[next].vertices.count; next += 1
            }
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(first.texture, index: 0)
            encoder.setFragmentTexture(first.mask?.texture ?? whiteTexture, index: 1)
            var settings = SIMD4<Float>(first.framebuffer ? 1 : 0, first.mask == nil ? 0 : 1, 0, 0)
            let rect = first.mask?.rect ?? Scene.Rect([0,0,1,1])
            var maskRect = SIMD4(Float(rect.minX),Float(rect.minY),Float(rect.width),Float(rect.height))
            encoder.setFragmentBytes(&settings, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            encoder.setFragmentBytes(&maskRect, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: offset, vertexCount: count)
            drawCalls += 1
            offset += count; index = next
        }
    }

    private func sameState(_ a: PreparedDraw, _ b: PreparedDraw) -> Bool {
        guard a.texture === b.texture, a.blend == b.blend, a.framebuffer == b.framebuffer else { return false }
        switch (a.mask,b.mask) {
        case (nil,nil): return true
        case (.some(let a),.some(let b)): return a.texture === b.texture && a.rect == b.rect
        default: return false
        }
    }

    /// Deterministic, bounded offscreen rendering for synthetic pixel tests and
    /// private acceptance captures. The live view never waits for GPU completion.
    func snapshot(time: Double, width: Int, height: Int) throws -> [UInt8] {
        guard (1...2048).contains(width), (1...2048).contains(height), let command = queue.makeCommandBuffer() else {
            throw ArenaLobbyTimelineError.invalid("Invalid lobby snapshot dimensions")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = [.renderTarget, .shaderRead]
        guard let output = device.makeTexture(descriptor: descriptor) else {
            throw ArenaLobbyTimelineError.invalid("Unable to allocate a lobby snapshot")
        }
        let pool = FramePool()
        let frame = try scene.frame(time: time)
        drawCalls = 0; renderPasses = 0
        let prepared = try prepare(frame.operations, mask: nil, command: command, pool: pool, density: 1)
        try encode(prepared, texture: output, viewport: scene.sourceRect, command: command)
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        var bytes = [UInt8](repeating: 0, count: width*height*4)
        bytes.withUnsafeMutableBytes { raw in
            output.getBytes(raw.baseAddress!, bytesPerRow: width*4,
                            from: MTLRegionMake2D(0,0,width,height), mipmapLevel: 0)
        }
        for at in stride(from: 0, to: bytes.count, by: 4) { bytes.swapAt(at,at+2) }
        lastStatistics = Statistics(drawCalls: drawCalls, renderPasses: renderPasses,
            transientPixels: pool.pixels, sourceTime: time, sourceClipFrames: frame.clipFrames)
        return bytes
    }
}
