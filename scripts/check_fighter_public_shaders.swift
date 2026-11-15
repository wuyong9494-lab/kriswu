import Foundation
import AppKit
import CryptoKit
import Metal
import SceneKit

/// Standalone macOS check. All shader strings are the extracted production
/// expressions. Geometry and the one-pixel mask are explicit synthetic inputs.
@main
struct FighterPublicShaderCheck {
    enum Failure: Error, CustomStringConvertible {
        case unavailable(String), failed(String)
        var description: String {
            switch self { case .unavailable(let message), .failed(let message): return message }
        }
    }
    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure.failed(message) }
    }
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func identity(_ name: String, _ source: String) -> [String: Any] {
        let data = Data(source.utf8)
        return ["name": name, "bytes": data.count, "sha256": hash(data)]
    }
    static var programIdentities: [[String: Any]] {
        FighterPublicShaderSources.programs.sorted { $0.key < $1.key }.map { identity($0.key, $0.value) }
    }
    static var modifierIdentities: [[String: Any]] {
        [false, true].flatMap { constant in
            let pair = FighterPublicShaderSources.modifiers(constant: constant)
            let name = constant ? "morph-constant" : "morph-uv"
            return [identity(name+"-surface", pair.surface), identity(name+"-fragment", pair.fragment)]
        }
    }
    static func write(_ value: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .withoutOverwriting)
    }

    @MainActor
    static func complete(_ command: MTLCommandBuffer, label: String) throws {
        let completed = DispatchSemaphore(value: 0)
        command.addCompletedHandler { _ in completed.signal() }
        command.commit()
        try require(completed.wait(timeout: .now()+10) == .success, label+" GPU completion timed out")
        try require(command.status == .completed && command.error == nil,
                    label+" command failed: "+String(describing: command.error))
    }

    @MainActor
    static func makeMask(_ device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
            width: 1, height: 1, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw Failure.failed("Synthetic mask allocation failed") }
        let bytes: [UInt8] = [128, 0, 0, 255]
        bytes.withUnsafeBytes {
            texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                            withBytes: $0.baseAddress!, bytesPerRow: 4)
        }
        return texture
    }

    @MainActor
    static func sourceOrigin(_ device: MTLDevice, queue: MTLCommandQueue,
                             library: MTLLibrary, mask: MTLTexture) throws -> Float {
        guard let function = library.makeFunction(name: "triad_morph_source_origin") else {
            throw Failure.failed("Production source-origin kernel is missing")
        }
        let pipeline = try device.makeComputePipelineState(function: function)
        let descriptor = MTLSamplerDescriptor()
        descriptor.normalizedCoordinates = true
        descriptor.sAddressMode = .repeat; descriptor.tAddressMode = .repeat
        descriptor.minFilter = .linear; descriptor.magFilter = .linear
        descriptor.mipFilter = .notMipmapped; descriptor.maxAnisotropy = 1
        guard let sampler = device.makeSamplerState(descriptor: descriptor),
              let result = device.makeBuffer(length: MemoryLayout<Float>.size, options: .storageModeShared),
              let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
            throw Failure.failed("Synthetic source-origin resources could not be allocated")
        }
        result.contents().storeBytes(of: Float.nan, as: Float.self)
        encoder.setComputePipelineState(pipeline); encoder.setTexture(mask, index: 0)
        encoder.setSamplerState(sampler, index: 0); encoder.setBuffer(result, offset: 0, index: 0)
        encoder.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        encoder.endEncoding(); try complete(command, label: "source-origin")
        let value = result.contents().load(as: Float.self)
        try require(value.isFinite && abs(value-Float(128)/255) < 0.0001,
                    "Production kernel did not sample the synthetic original-format mask")
        return value
    }

    @MainActor
    static func capture(_ renderer: SCNRenderer, device: MTLDevice, queue: MTLCommandQueue,
                        label: String) throws -> [String: Any] {
        let side = 32, stride = 256
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: side, height: side, mipmapped: false)
        colorDescriptor.usage = [.renderTarget, .shaderRead]; colorDescriptor.storageMode = .private
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
            width: side, height: side, mipmapped: false)
        depthDescriptor.usage = .renderTarget; depthDescriptor.storageMode = .private
        guard let color = device.makeTexture(descriptor: colorDescriptor),
              let depth = device.makeTexture(descriptor: depthDescriptor),
              let readback = device.makeBuffer(length: stride*side, options: .storageModeShared),
              let command = queue.makeCommandBuffer() else { throw Failure.failed("Synthetic render allocation failed") }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear; pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1
        SCNTransaction.flush()
        renderer.render(atTime: 0, viewport: CGRect(x: 0, y: 0, width: side, height: side),
                        commandBuffer: command, passDescriptor: pass)
        guard let blit = command.makeBlitCommandEncoder() else { throw Failure.failed("Synthetic render readback encoder failed") }
        blit.copy(from: color, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: side, height: side, depth: 1), to: readback, destinationOffset: 0,
            destinationBytesPerRow: stride, destinationBytesPerImage: stride*side)
        blit.endEncoding(); try complete(command, label: label)
        let bytes = readback.contents().bindMemory(to: UInt8.self, capacity: stride*side)
        var compact = Data(), nonblack = 0, red = 0, green = 0
        for y in 0..<side {
            for x in 0..<side {
                let at = y*stride+x*4
                let b = Int(bytes[at]), g = Int(bytes[at+1]), r = Int(bytes[at+2])
                compact.append(contentsOf: [bytes[at], bytes[at+1], bytes[at+2], bytes[at+3]])
                if max(r, max(g, b)) > 8 { nonblack += 1 }
                if r > g+16 && r > b+16 { red += 1 }
                if g > r+16 && g > b+16 { green += 1 }
            }
        }
        return ["phase": label, "width": side, "height": side, "format": "bgra8Unorm",
                "nonblackPixels": nonblack, "redPixels": red, "greenPixels": green,
                "pixelsSHA256": hash(compact), "commandCompleted": true, "commandError": NSNull()]
    }

    @MainActor
    static func morphBranch(_ constant: Bool, device: MTLDevice, queue: MTLCommandQueue,
                            mask: MTLTexture, sourceValue: Float) throws -> [String: Any] {
        let name = constant ? "constant-no-uv" : "authored-uv"
        let material = SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents = NSColor.red
        material.readsFromDepthBuffer = true; material.writesToDepthBuffer = true
        material.blendMode = .replace
        let modifiers = FighterPublicShaderSources.modifiers(constant: constant)
        material.shaderModifiers = [.surface: modifiers.surface, .fragment: modifiers.fragment]
        if constant {
            material.setValue(NSNumber(value: sourceValue), forKey: "triadMorphSourceValue")
            material.setValue(NSNumber(value: sourceValue), forKey: "triadMorphSurfaceSourceValue")
        } else {
            for name in ["triadMorphMask", "triadMorphSurfaceMask"] {
                let property = SCNMaterialProperty(contents: mask)
                property.wrapS = .repeat; property.wrapT = .repeat
                property.minificationFilter = .linear; property.magnificationFilter = .linear
                property.mipFilter = .none; property.maxAnisotropy = 1
                material.setValue(property, forKey: name)
            }
            material.setValue(NSNumber(value: Float(1)), forKey: "triadMorphTile")
            material.setValue(NSNumber(value: Float(1)), forKey: "triadMorphSurfaceTile")
        }
        material.setValue(NSNumber(value: Float(0.2)), forKey: "triadMorphEdge")
        material.setValue(NSNumber(value: Float(0.2)), forKey: "triadMorphSurfaceEdge")
        material.setValue(NSValue(scnVector3: SCNVector3(0, 1, 0)), forKey: "triadMorphStart")
        material.setValue(NSValue(scnVector3: SCNVector3(0, 0.5, 0)), forKey: "triadMorphEnd")
        let positions = [SCNVector3(-0.75, -0.75, 0), SCNVector3(0.75, -0.75, 0), SCNVector3(0, 0.75, 0)]
        var sources = [SCNGeometrySource(vertices: positions),
                       SCNGeometrySource(normals: Array(repeating: SCNVector3(0, 0, 1), count: 3))]
        if !constant {
            sources.append(SCNGeometrySource(textureCoordinates: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0.5, y: 1)]))
        }
        let geometry = SCNGeometry(sources: sources,
            elements: [SCNGeometryElement(indices: [UInt16(0), 1, 2], primitiveType: .triangles)])
        geometry.materials = [material]
        try require(geometry.sources(for: .texcoord).isEmpty == constant, "Synthetic UV branch differs")
        let scene = SCNScene(); scene.rootNode.addChildNode(SCNNode(geometry: geometry))
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 1
        camera.camera?.zNear = 0.1; camera.camera?.zFar = 10
        camera.camera?.wantsHDR = false; camera.camera?.wantsExposureAdaptation = false
        camera.position = SCNVector3(0, 0, 3); scene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.usesReverseZ = false; renderer.scene = scene; renderer.pointOfView = camera
        defer { renderer.scene = nil; renderer.pointOfView = nil }
        func cutoff(_ value: Float) {
            material.setValue(NSNumber(value: value), forKey: "triadMorphCutoff")
            material.setValue(NSNumber(value: value), forKey: "triadMorphSurfaceCutoff")
        }
        cutoff(0.75)
        let deadline = ProcessInfo.processInfo.systemUptime+5
        try require(renderer.prepare(scene, shouldAbortBlock: { ProcessInfo.processInfo.systemUptime > deadline }),
                    name+" bounded preparation was canceled")
        let base = try capture(renderer, device: device, queue: queue, label: name+"-base")
        cutoff(0.45)
        let edge = try capture(renderer, device: device, queue: queue, label: name+"-edge")
        cutoff(0)
        let hidden = try capture(renderer, device: device, queue: queue, label: name+"-discard")
        try require((base["redPixels"] as? Int ?? 0) > 20 && (edge["greenPixels"] as? Int ?? 0) > 20
                    && (hidden["nonblackPixels"] as? Int) == 0
                    && base["pixelsSHA256"] as? String != edge["pixelsSHA256"] as? String,
                    name+" production surface/fragment did not produce the expected finite synthetic pixels")
        return ["branch": name, "prepared": true, "hasUV": !constant,
                "phases": [base, edge, hidden], "passed": true]
    }

    @MainActor
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 3 && ["--emit", "--check"].contains(args[1]) else {
            FileHandle.standardError.write(Data("Expected --emit or --check and the bounded output directory.\n".utf8))
            exit(1)
        }
        let output = URL(fileURLWithPath: args[2], isDirectory: true)
        var result: [String: Any] = ["schemaVersion": 1, "status": "failed",
            "programs": programIdentities, "modifiers": modifierIdentities,
            "syntheticInputsOnly": true, "privateProgramsChecked": 0,
            "syntheticMask": ["width": 1, "height": 1, "format": "rgba8Unorm", "rgba": [128, 0, 0, 255]],
            "simulatorLaunched": false, "iOSDeviceRenderingObserved": false]
        var code: Int32 = 1
        do {
            if args[1] == "--emit" {
                for (name, source) in FighterPublicShaderSources.programs {
                    try Data(source.utf8).write(to: output.appendingPathComponent(name), options: .withoutOverwriting)
                }
                try write(["programs": programIdentities, "modifiers": modifierIdentities],
                          to: output.appendingPathComponent("emitted-source-manifest.json"))
                print("Emitted exactly two complete production MSL programs and four modifier identities.")
                exit(0)
            }
            guard let device = MTLCreateSystemDefaultDevice() else {
                throw Failure.unavailable("MTLCreateSystemDefaultDevice returned nil; no GPU check ran.")
            }
            guard let queue = device.makeCommandQueue() else { throw Failure.failed("Metal command queue is unavailable") }
            result["deviceName"] = device.name
            var libraries: [String: MTLLibrary] = [:]
            for (name, source) in FighterPublicShaderSources.programs.sorted(by: { $0.key < $1.key }) {
                let options = MTLCompileOptions(); options.fastMathEnabled = false
                libraries[name] = try device.makeLibrary(source: source, options: options)
            }
            let required = Set(["projected_caster_vertex", "projected_caster_fragment", "projected_blur_vertex",
                                "projected_blur_fragment", "projected_receiver_vertex", "projected_receiver_fragment"])
            try require(Set(libraries["public-projected-shadow.metal"]!.functionNames) == required,
                        "Production projected-shadow entry points differ")
            result["runtimeLibraryFunctions"] = libraries.mapValues { $0.functionNames.sorted() }
            let mask = try makeMask(device)
            let value = try sourceOrigin(device, queue: queue, library: libraries["public-source-origin.metal"]!, mask: mask)
            result["sourceOriginSample"] = ["actual": value, "expected": Float(128)/255, "passed": true]
            result["morphBranches"] = try [false, true].map {
                try morphBranch($0, device: device, queue: queue, mask: mask, sourceValue: value)
            }
            result["status"] = "passed"; code = 0
        } catch Failure.unavailable(let reason) {
            result["status"] = "unavailable"; result["reason"] = reason; code = 3
        } catch {
            result["status"] = "failed"; result["reason"] = String(String(describing: error).prefix(2000))
        }
        do { try write(result, to: output.appendingPathComponent("runtime-result.json")) }
        catch { print("Could not persist the public shader check result: \(error)"); exit(1) }
        print("Public shader check: \(result["status"]!). Original private effect programs were not inputs.")
        exit(code)
    }
}
