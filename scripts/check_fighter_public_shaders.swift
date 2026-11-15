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
        try require(renderer.usesReverseZ, "The public fixture requires explicit reverse-Z rendering")
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
        pass.depthAttachment.clearDepth = 0
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
        let center = (side/2)*stride+(side/2)*4
        return ["phase": label, "width": side, "height": side, "format": "bgra8Unorm",
                "nonblackPixels": nonblack, "redPixels": red, "greenPixels": green,
                "centerPixelBGRA": (0..<4).map { Int(bytes[center+$0]) },
                "pixelsSHA256": hash(compact), "commandCompleted": true, "commandError": NSNull(),
                "depthConfiguration": ["usesReverseZ": renderer.usesReverseZ,
                    "clearDepth": pass.depthAttachment.clearDepth, "depthPixelFormat": depth.pixelFormat.rawValue,
                    "loadAction": "clear", "storeAction": "dontCare"]]
    }

    static func finite(_ value: Double) -> Any { value.isFinite ? value as Any : NSNull() }
    static func vector(_ value: SCNVector3) -> [Any] {
        [finite(Double(value.x)), finite(Double(value.y)), finite(Double(value.z))]
    }
    static func matrix(_ value: SCNMatrix4) -> [Any] {
        [value.m11, value.m12, value.m13, value.m14, value.m21, value.m22, value.m23, value.m24,
         value.m31, value.m32, value.m33, value.m34, value.m41, value.m42, value.m43, value.m44]
            .map { finite(Double($0)) }
    }
    @MainActor
    static func sourceDiagnostic(_ source: SCNGeometrySource) -> [String: Any] {
        let data = source.data
        var result: [String: Any] = ["semantic": source.semantic.rawValue, "dataBytes": data.count,
            "dataSHA256": hash(data), "vectorCount": source.vectorCount,
            "usesFloatComponents": source.usesFloatComponents, "componentsPerVector": source.componentsPerVector,
            "bytesPerComponent": source.bytesPerComponent, "dataOffset": source.dataOffset,
            "dataStride": source.dataStride]
        // Inspect the format SceneKit actually produced. The convenience
        // initializer may convert SCNVector3 data; do not assume CGFloat layout.
        guard source.usesFloatComponents, [4, 8].contains(source.bytesPerComponent),
              (0...3).contains(source.vectorCount), (1...3).contains(source.componentsPerVector),
              source.dataOffset >= 0, source.dataStride > 0 else {
            result["decodeStatus"] = "unsupported-synthetic-layout"; return result
        }
        let size = source.bytesPerComponent
        var vectors = [[Any]]()
        for index in 0..<source.vectorCount {
            let start = source.dataOffset + index*source.dataStride
            guard start >= 0, start <= data.count,
                  source.componentsPerVector*size <= data.count-start else {
                result["decodeStatus"] = "out-of-bounds"; return result
            }
            vectors.append(data.withUnsafeBytes { bytes in
                (0..<source.componentsPerVector).map { component in
                    let at = start+component*size
                    let value = size == 4 ? Double(bytes.loadUnaligned(fromByteOffset: at, as: Float.self))
                                          : bytes.loadUnaligned(fromByteOffset: at, as: Double.self)
                    return finite(value)
                }
            })
        }
        result["decodeStatus"] = "decoded"; result["vectors"] = vectors
        return result
    }
    @MainActor
    static func fixtureDiagnostic(_ renderer: SCNRenderer, node: SCNNode, camera: SCNNode,
                                  geometry: SCNGeometry, material: SCNMaterial,
                                  positions: [SCNVector3]) -> [String: Any] {
        let bounds = geometry.boundingBox, color = (material.diffuse.contents as? NSColor)?.usingColorSpace(.deviceRGB)
        let elements: [[String: Any]] = geometry.elements.prefix(1).map { element in
            let data = element.data, size = element.bytesPerIndex
            var indices = [Int]()
            if [1, 2, 4].contains(size), data.count >= 3*size {
                for at in stride(from: 0, to: 3*size, by: size) {
                    indices.append(data.withUnsafeBytes { bytes in
                        switch size {
                        case 1: return Int(bytes.load(fromByteOffset: at, as: UInt8.self))
                        case 2: return Int(bytes.loadUnaligned(fromByteOffset: at, as: UInt16.self))
                        default: return Int(bytes.loadUnaligned(fromByteOffset: at, as: UInt32.self))
                        }
                    })
                }
            }
            return ["primitiveType": element.primitiveType.rawValue, "primitiveCount": element.primitiveCount,
                "bytesPerIndex": size, "dataBytes": data.count, "dataSHA256": hash(data), "indices": indices]
        }
        let nodeInfo: [String: Any] = ["hidden": node.isHidden, "opacity": finite(Double(node.opacity)),
            "categoryBitMask": node.categoryBitMask, "worldTransform": matrix(node.worldTransform),
            "presentationWorldTransform": matrix(node.presentation.worldTransform)]
        let cameraInfo: [String: Any] = ["orthographic": camera.camera?.usesOrthographicProjection ?? false,
            "orthographicScale": finite(camera.camera?.orthographicScale ?? .nan),
            "zNear": finite(camera.camera?.zNear ?? .nan), "zFar": finite(camera.camera?.zFar ?? .nan),
            "categoryBitMask": camera.camera?.categoryBitMask ?? 0,
            "worldTransform": matrix(camera.worldTransform),
            "presentationWorldTransform": matrix(camera.presentation.worldTransform),
            "projectionTransform": matrix(camera.camera?.projectionTransform ?? SCNMatrix4Identity)]
        let materialInfo: [String: Any] = ["lightingModel": material.lightingModel.rawValue,
            "diffuseRGBA": color.map { [finite(Double($0.redComponent)), finite(Double($0.greenComponent)),
                finite(Double($0.blueComponent)), finite(Double($0.alphaComponent))] } ?? [],
            "doubleSided": material.isDoubleSided, "cullMode": material.cullMode.rawValue,
            "readsDepth": material.readsFromDepthBuffer, "writesDepth": material.writesToDepthBuffer,
            "colorBufferWriteMask": material.colorBufferWriteMask.rawValue]
        let rendererInfo: [String: Any] = ["renderingAPI": renderer.renderingAPI.rawValue, "usesReverseZ": renderer.usesReverseZ,
            "colorPixelFormat": renderer.colorPixelFormat.rawValue, "depthPixelFormat": renderer.depthPixelFormat.rawValue,
            "stencilPixelFormat": renderer.stencilPixelFormat.rawValue, "pointOfViewMatchesCamera": renderer.pointOfView === camera]
        return ["observedAfter": "unmodified-baseline", "renderTime": 0, "viewport": [0, 0, 32, 32],
            "sourceCount": geometry.sources.count, "elementCount": geometry.elements.count,
            "sources": geometry.sources.prefix(3).map { sourceDiagnostic($0) }, "elements": elements,
            "bounds": ["min": vector(bounds.min), "max": vector(bounds.max)],
            "node": nodeInfo, "camera": cameraInfo, "material": materialInfo, "renderer": rendererInfo,
            // This is a bounding-box/frustum test, not an occlusion or GPU pass.
            "insideFrustum": renderer.isNode(node, insideFrustumOf: camera),
            "projectedInputVertices": positions.prefix(3).map { vector(renderer.projectPoint(node.convertPosition($0, to: nil))) }]
    }
    @MainActor
    static func depthOcclusionCheck(_ renderer: SCNRenderer, scene: SCNScene, triangle: SCNNode,
                                    geometry: SCNGeometry, material: SCNMaterial, device: MTLDevice,
                                    queue: MTLCommandQueue, label: String,
                                    diagnosticDeadline: TimeInterval) -> [String: Any] {
        var result: [String: Any] = ["required": true, "prepared": false, "passed": false,
                                    "phases": [[String: Any]]()]
        // Leave the existing 60-second native process enough time to persist
        // the original readbacks. A skipped required check is still a failure.
        guard ProcessInfo.processInfo.systemUptime+25 <= diagnosticDeadline else {
            result["skippedReason"] = "insufficient-native-budget-after-original-readbacks"; return result
        }
        let modifiers = material.shaderModifiers, position = triangle.position, order = triangle.renderingOrder
        let greenMaterial = SCNMaterial(); greenMaterial.lightingModel = .constant
        greenMaterial.diffuse.contents = NSColor.green; greenMaterial.blendMode = .replace
        greenMaterial.readsFromDepthBuffer = true; greenMaterial.writesToDepthBuffer = true
        let greenGeometry = SCNGeometry(sources: geometry.sources, elements: geometry.elements)
        greenGeometry.materials = [greenMaterial]
        let green = SCNNode(geometry: greenGeometry)
        scene.rootNode.addChildNode(green)
        defer {
            SCNTransaction.begin(); SCNTransaction.disableActions = true
            green.removeFromParentNode(); triangle.position = position; triangle.renderingOrder = order
            material.shaderModifiers = modifiers
            SCNTransaction.commit(); SCNTransaction.flush()
        }
        material.shaderModifiers = nil
        // Explicit order, unchanged in both frames: red first, green last.
        // Thus a disabled depth test or last-draw-wins cannot pass red-near.
        triangle.renderingOrder = 0; green.renderingOrder = 1
        result["readsDepth"] = material.readsFromDepthBuffer && greenMaterial.readsFromDepthBuffer
        result["writesDepth"] = material.writesToDepthBuffer && greenMaterial.writesToDepthBuffer
        result["shaderModifierCount"] = (material.shaderModifiers?.count ?? 0) + (greenMaterial.shaderModifiers?.count ?? 0)
        do {
            try require(result["readsDepth"] as? Bool == true && result["writesDepth"] as? Bool == true,
                        label+" requires both materials to read and write depth")
            let cases = [("red", SCNVector3(0, 0, 0), SCNVector3(0, 0, -0.5)),
                         ("green", SCNVector3(0, 0, -0.5), SCNVector3(0, 0, 0))]
            SCNTransaction.begin(); SCNTransaction.disableActions = true
            triangle.position = cases[0].1; green.position = cases[0].2; SCNTransaction.commit()
            let deadline = ProcessInfo.processInfo.systemUptime+5
            try require(renderer.prepare(scene, shouldAbortBlock: { ProcessInfo.processInfo.systemUptime > deadline }),
                        label+" preparation was canceled")
            result["prepared"] = true
            var phases = [[String: Any]]()
            for (nearColor, redPosition, greenPosition) in cases {
                SCNTransaction.begin(); SCNTransaction.disableActions = true
                triangle.position = redPosition; green.position = greenPosition; SCNTransaction.commit()
                var phase = try capture(renderer, device: device, queue: queue, label: label+"-"+nearColor+"-near")
                let actualRed = triangle.presentation.position, actualGreen = green.presentation.position
                phase["expectedNearColor"] = nearColor
                phase["redRenderingOrder"] = triangle.renderingOrder; phase["greenRenderingOrder"] = green.renderingOrder
                phase["redPresentationPosition"] = vector(actualRed); phase["greenPresentationPosition"] = vector(actualGreen)
                phase["positionsMatch"] = actualRed.x == redPosition.x && actualRed.y == redPosition.y && actualRed.z == redPosition.z
                    && actualGreen.x == greenPosition.x && actualGreen.y == greenPosition.y && actualGreen.z == greenPosition.z
                phases.append(phase); result["phases"] = phases
            }
            result["passed"] = (result["shaderModifierCount"] as? Int) == 0
                && phases.allSatisfy { ($0["positionsMatch"] as? Bool) == true
                    && ($0["redRenderingOrder"] as? Int) == 0 && ($0["greenRenderingOrder"] as? Int) == 1 }
                && (phases[0]["redPixels"] as? Int ?? 0) > 20 && (phases[0]["greenPixels"] as? Int) == 0
                && (phases[1]["greenPixels"] as? Int ?? 0) > 20 && (phases[1]["redPixels"] as? Int) == 0
                && phases[0]["pixelsSHA256"] as? String != phases[1]["pixelsSHA256"] as? String
        } catch { result["error"] = String(String(describing: error).prefix(2000)) }
        return result
    }

    @MainActor
    static func morphBranch(_ constant: Bool, device: MTLDevice, queue: MTLCommandQueue,
                            mask: MTLTexture, sourceValue: Float, diagnosticDeadline: TimeInterval,
                            receipt: inout [String: Any]) throws {
        let name = constant ? "constant-no-uv" : "authored-uv"
        // Keep the attempted branch and every completed readback even when a
        // later draw or the unchanged pixel assertion throws.
        receipt = ["branch": name, "prepared": false, "hasUV": !constant,
                   "activePhase": "setup", "phases": [[String: Any]](), "passed": false]
        let material = SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents = NSColor.red
        material.readsFromDepthBuffer = true; material.writesToDepthBuffer = true
        material.blendMode = .replace
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
        let scene = SCNScene(), triangle = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(triangle)
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 1
        camera.camera?.zNear = 0.1; camera.camera?.zFar = 10
        camera.camera?.wantsHDR = false; camera.camera?.wantsExposureAdaptation = false
        camera.position = SCNVector3(0, 0, 3); scene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.usesReverseZ = true; renderer.scene = scene; renderer.pointOfView = camera
        defer { renderer.scene = nil; renderer.pointOfView = nil }
        // The exact same triangle, camera, renderer, target allocation and
        // readback path must first draw without any shader modifier. Keep a
        // failed baseline as evidence and still attempt the production phases;
        // otherwise a blank fixture could be mistaken for successful discard.
        receipt["unmodifiedBaseline"] = ["prepared": false, "passed": false,
            "shaderModifierCount": material.shaderModifiers?.count ?? 0]
        receipt["activePhase"] = name+"-unmodified-prepare"
        let baselineDeadline = ProcessInfo.processInfo.systemUptime+5
        try require(renderer.prepare(scene, shouldAbortBlock: { ProcessInfo.processInfo.systemUptime > baselineDeadline }),
                    name+" unmodified baseline preparation was canceled")
        receipt["unmodifiedBaseline"] = ["prepared": true, "passed": false,
            "shaderModifierCount": material.shaderModifiers?.count ?? 0]
        receipt["activePhase"] = name+"-unmodified-baseline"
        var baseline = try capture(renderer, device: device, queue: queue, label: name+"-unmodified-baseline")
        let baselinePassed = (material.shaderModifiers?.isEmpty ?? true)
            && (baseline["redPixels"] as? Int ?? 0) > 20
            && (baseline["nonblackPixels"] as? Int ?? 0) > 20
        baseline["prepared"] = true; baseline["passed"] = baselinePassed
        baseline["shaderModifierCount"] = material.shaderModifiers?.count ?? 0
        receipt["unmodifiedBaseline"] = baseline
        receipt["fixtureDiagnostics"] = fixtureDiagnostic(renderer, node: triangle, camera: camera,
            geometry: geometry, material: material, positions: positions)

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
        func cutoff(_ value: Float) {
            material.setValue(NSNumber(value: value), forKey: "triadMorphCutoff")
            material.setValue(NSNumber(value: value), forKey: "triadMorphSurfaceCutoff")
        }
        cutoff(0.75)
        let deadline = ProcessInfo.processInfo.systemUptime+5
        receipt["activePhase"] = name+"-prepare"
        try require(renderer.prepare(scene, shouldAbortBlock: { ProcessInfo.processInfo.systemUptime > deadline }),
                    name+" bounded preparation was canceled")
        receipt["prepared"] = true
        receipt["activePhase"] = name+"-base"
        let base = try capture(renderer, device: device, queue: queue, label: name+"-base")
        receipt["phases"] = [base]
        cutoff(0.45)
        receipt["activePhase"] = name+"-edge"
        let edge = try capture(renderer, device: device, queue: queue, label: name+"-edge")
        receipt["phases"] = [base, edge]
        cutoff(0)
        receipt["activePhase"] = name+"-discard"
        let hidden = try capture(renderer, device: device, queue: queue, label: name+"-discard")
        receipt["phases"] = [base, edge, hidden]
        if !constant {
            receipt["activePhase"] = name+"-depth-occlusion"
            receipt["depthOcclusion"] = depthOcclusionCheck(renderer, scene: scene, triangle: triangle,
                geometry: geometry, material: material, device: device, queue: queue,
                label: name+"-depth-occlusion", diagnosticDeadline: diagnosticDeadline)
        }
        receipt["activePhase"] = name+"-pixel-assertions"
        try require((base["redPixels"] as? Int ?? 0) > 20 && (edge["greenPixels"] as? Int ?? 0) > 20
                    && (hidden["nonblackPixels"] as? Int) == 0
                    && base["pixelsSHA256"] as? String != edge["pixelsSHA256"] as? String,
                    name+" production surface/fragment did not produce the expected finite synthetic pixels")
        receipt["activePhase"] = name+"-unmodified-pixel-assertions"
        try require(baselinePassed, name+" unmodified red baseline did not produce the expected synthetic pixels")
        if !constant {
            receipt["activePhase"] = name+"-depth-occlusion-assertions"
            try require((receipt["depthOcclusion"] as? [String: Any])?["passed"] as? Bool == true,
                        name+" required depth occlusion did not pass")
        }
        receipt["passed"] = true
        receipt["activePhase"] = name+"-completed"
    }

    @MainActor
    static func main() {
        let diagnosticDeadline = ProcessInfo.processInfo.systemUptime+55
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
            var branches = [[String: Any]]()
            for constant in [false, true] {
                var branch = [String: Any]()
                do {
                    try morphBranch(constant, device: device, queue: queue, mask: mask,
                                    sourceValue: value, diagnosticDeadline: diagnosticDeadline, receipt: &branch)
                } catch {
                    branches.append(branch)
                    result["morphBranches"] = branches
                    throw error
                }
                branches.append(branch)
                result["morphBranches"] = branches
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
