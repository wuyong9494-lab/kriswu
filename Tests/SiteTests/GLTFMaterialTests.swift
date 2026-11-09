import XCTest
import SceneKit
import Metal
import ImageIO
import UniformTypeIdentifiers
#if ARENA_RESOURCE_RUNTIME_TESTS
@testable import ArenaResourceRuntime
#else
@testable import ShiftReminder
#endif

/// Synthetic glTF fixtures only. These checks render small in-memory surfaces;
/// they do not import third-party assets or run gameplay/screenshot recording.
@MainActor
final class GLTFMaterialTests: XCTestCase {
    func testOpaqueIgnoresBaseAlphaAndKeepsNodeOpacity() throws {
        let solid = try fixture(factor: [1, 1, 1, 0.2], pixel: [255, 0, 0, 255]).instantiate()
        let alpha = try fixture(factor: [1, 1, 1, 0.2], pixel: [255, 0, 0, 64]).instantiate()
        let expected = try snapshot(solid)
        let actual = try snapshot(alpha)
        assertPixel(actual.center, equals: expected.center)
        XCTAssertGreaterThan(actual.center.x, 240)
        alpha.root.opacity = 0.5
        let faded = try snapshot(alpha).center
        XCTAssertEqual(faded.x, 128, accuracy: 15)
        XCTAssertEqual(faded.z, 128, accuracy: 15)
        XCTAssertTrue(alpha.materials[0].writesToDepthBuffer)
    }

    func testOpaquePreservesOriginalRGBAtZeroAlphaBeforeResizing() throws {
        // Fixed RGBA8 PNG pixels are [255, 0, 0, 0]. Do not let a fixture
        // encoder discard the hidden RGB before the loader can be tested.
        let png = try zeroAlphaRedPNG()
        for embedded in [false, true] {
            let instance = try fixture(factor: [1, 1, 1, 0], texturePNG: png,
                embeddedTexture: embedded, maxTexture: 1).instantiate()
            assertPixel(try snapshot(instance).center, equals: SIMD3(255, 0, 0))
            instance.root.opacity = 0.5
            assertPixel(try snapshot(instance).center, equals: SIMD3(128, 0, 128), accuracy: 15)
        }
    }

    func testTexturedFactorMatchesLinearSolidColorAndRemainsIndependentOfTint() throws {
        let factor = [0.25, 0.5, 0.75, 1.0]
        let model = try fixture(factor: factor)
        let textured = model.instantiate()
        let solid = try fixture(factor: factor, pixel: nil).instantiate()
        assertPixel(try snapshot(textured).center, equals: try snapshot(solid).center)
        let second = model.instantiate()
        XCTAssertFalse(textured.materials[0] === second.materials[0])
        textured.materials[0].multiply.contents = UIColor.red
        let tinted = try snapshot(textured).center
        XCTAssertGreaterThan(tinted.x, 40)
        XCTAssertLessThan(tinted.y, 5)
        XCTAssertLessThan(tinted.z, 5)
        XCTAssertGreaterThan(try snapshot(second).center.y, 100)
    }

    func testMaskUsesSampledAlphaTimesFactorAndInclusiveCutoff() throws {
        let rejected = try fixture(alphaMode: "MASK", factor: [1, 1, 1, 0.5],
                                   pixel: [255, 0, 0, 204]).instantiate(outline: SCNMaterial())
        assertPixel(try snapshot(rejected).center, equals: SIMD3(0, 0, 255))
        let boundary = try fixture(alphaMode: "MASK", factor: [1, 1, 1, 0.5],
                                   pixel: [255, 0, 0, 255]).instantiate(outline: SCNMaterial())
        assertPixel(try snapshot(boundary).center, equals: SIMD3(255, 0, 0))
        XCTAssertTrue(boundary.materials[0].writesToDepthBuffer)
        XCTAssertTrue(boundary.outlines.isEmpty, "A solid hull must not fill a masked hole")
        let aboveOne = try fixture(alphaMode: "MASK", cutoff: 1.2).instantiate()
        assertPixel(try snapshot(aboveOne).center, equals: SIMD3(0, 0, 255))
    }

    func testMaskRestoresOpaqueColorForAcceptedFractionalAndZeroAlpha() throws {
        let accepted = try fixture(alphaMode: "MASK", factor: [1, 1, 1, 1],
            pixel: [255, 0, 0, 128], cutoff: 0.5).instantiate()
        assertPixel(try snapshot(accepted).center, equals: SIMD3(255, 0, 0))
        // With cutoff zero, even zero-alpha source pixels are fully opaque.
        let zero = try fixture(alphaMode: "MASK", factor: [1, 1, 1, 0], cutoff: 0,
            texturePNG: zeroAlphaRedPNG()).instantiate()
        assertPixel(try snapshot(zero).center, equals: SIMD3(255, 0, 0))
    }

    func testBlendMultipliesTextureAndFactorAlphaExactlyOnce() throws {
        let factorOnly = try fixture(alphaMode: "BLEND", factor: [1, 1, 1, 0.25],
                                      pixel: [255, 0, 0, 255]).instantiate(outline: SCNMaterial())
        let sampled = try fixture(alphaMode: "BLEND", factor: [1, 1, 1, 0.5],
                                   pixel: [255, 0, 0, 128]).instantiate()
        let expected = SIMD3<Float>(64, 0, 191)
        assertPixel(try snapshot(factorOnly).center, equals: expected, accuracy: 15)
        assertPixel(try snapshot(sampled).center, equals: expected, accuracy: 15)
        XCTAssertFalse(factorOnly.materials[0].writesToDepthBuffer)
        XCTAssertTrue(factorOnly.materials[0].readsFromDepthBuffer)
        XCTAssertTrue(factorOnly.outlines.isEmpty)
        factorOnly.root.opacity = 0.5
        assertPixel(try snapshot(factorOnly).center, equals: SIMD3(32, 0, 223), accuracy: 15)
    }

    func testBlendZeroFactorAlphaLeavesBackgroundUntouched() throws {
        for pixel: [UInt8]? in [[255, 0, 0, 255], [255, 0, 0, 128], nil] {
            let instance = try fixture(alphaMode: "BLEND", factor: [1, 0, 0, 0], pixel: pixel).instantiate()
            assertPixel(try snapshot(instance).center, equals: SIMD3(0, 0, 255))
        }
    }

    func testSamplerWrapAndFilterModesArePreserved() throws {
        let modes: [(Int, SCNFilterMode, SCNFilterMode)] = [
            (9728, .nearest, .none), (9729, .linear, .none),
            (9984, .nearest, .nearest), (9985, .linear, .nearest),
            (9986, .nearest, .linear), (9987, .linear, .linear)
        ]
        for (value, minification, mip) in modes {
            let material = try XCTUnwrap(fixture(sampler: ["magFilter": 9728, "minFilter": value,
                "wrapS": 33071, "wrapT": 33648]).instantiate().materials.first)
            XCTAssertEqual(material.diffuse.magnificationFilter, .nearest)
            XCTAssertEqual(material.diffuse.minificationFilter, minification)
            XCTAssertEqual(material.diffuse.mipFilter, mip)
            XCTAssertEqual(material.diffuse.wrapS, .clamp)
            XCTAssertEqual(material.diffuse.wrapT, .mirror)
        }
        let repeatUV = [[Float]](repeating: [1.25, 0.5], count: 4).flatMap { $0 }
        let pixels: [UInt8] = [255, 0, 0, 255, 0, 0, 255, 255]
        let repeated = try fixture(pixel: pixels, sampler: ["wrapS": 10497, "magFilter": 9728], uv: repeatUV).instantiate()
        let clamped = try fixture(pixel: pixels, sampler: ["wrapS": 33071, "magFilter": 9728], uv: repeatUV).instantiate()
        assertPixel(try snapshot(repeated).center, equals: SIMD3(255, 0, 0))
        assertPixel(try snapshot(clamped).center, equals: SIMD3(0, 0, 255))
    }

    func testToonAndConcealmentPreserveImportedCoverage() throws {
        let instance = try fixture(alphaMode: "BLEND", factor: [1, 1, 1, 0.5], pixel: [255, 0, 0, 255]).instantiate()
        let material = try XCTUnwrap(instance.materials.first)
        let grade = "#pragma body\n_surface.diffuse.rgb *= float3(0.5, 1.0, 1.0);"
        ArenaColorGrade.grade(material, grade)
        let graded = material.shaderModifiers
        ArenaColorGrade.grade(material, grade)
        XCTAssertEqual(material.shaderModifiers, graded, "Repeated styling must not apply the base factor or grade twice")
        let previous = material.shaderModifiers?[.fragment] ?? ""
        material.shaderModifiers?[.fragment] = GLTFModel.combiningShaderModifiers(previous, ArenaColorGrade.concealmentFragment)
        material.setValue(Float(0), forKey: "arenaConcealment")
        let result = try snapshot(instance).center
        assertPixel(result, equals: SIMD3(64, 0, 128), accuracy: 15)
        XCTAssertFalse(material.writesToDepthBuffer)
        // A flash is a separate emission input, not multiplied by base color.
        material.emission.contents = UIColor.green
        XCTAssertGreaterThan(try snapshot(instance).center.y, result.y + 70)
    }

    func testSkinUsesBoneRootAndIgnoresUnrelatedMeshTransform() throws {
        for explicitRoot in [false, true] {
            let model = try fixture(pixel: [255, 0, 0, 255], skinned: true, explicitRoot: explicitRoot)
            let instance = model.instantiate()
            let mesh = try XCTUnwrap(instance.nodes[2].childNodes.first { $0.skinner != nil })
            let skinner = try XCTUnwrap(mesh.skinner)
            XCTAssertTrue(skinner.skeleton === instance.nodes[explicitRoot ? 0 : 1])
            XCTAssertTrue(skinner.bones[0] === instance.nodes[1])
            let rest = try snapshot(instance)
            XCTAssertGreaterThan(rest.redPixelCount, 500, "A translated mesh node must not move the skinned geometry out of frame")
            XCTAssertEqual(rest.redCenterX, 80, accuracy: 3)
            instance.nodes[2].simdPosition.x = -70
            XCTAssertEqual(try snapshot(instance).redCenterX, rest.redCenterX, accuracy: 1)
            instance.nodes[1].simdPosition.x += 0.5
            XCTAssertEqual(try snapshot(instance).redCenterX - rest.redCenterX, 16, accuracy: 3)
        }
    }

    func testExplicitSkinRootCorrectionPreservesAncestorJointAndRenderedMotion() throws {
        // Reproduce the source export: both the ancestor and its child are
        // joints, yet the declaration points only to the child. Ordinary loads
        // must reject it; the verified caller supplies the exact correction.
        XCTAssertThrowsError(try fixture(skinned: true, includeRootJoint: true, declaredRoot: 1))
        let model = try fixture(pixel: [255, 0, 0, 255], skinned: true,
            includeRootJoint: true, declaredRoot: 1,
            skinRootCorrections: [0: .init(declared: 1, corrected: 0)])
        let instance = model.instantiate()
        let mesh = try XCTUnwrap(instance.nodes[2].childNodes.first { $0.skinner != nil })
        let skinner = try XCTUnwrap(mesh.skinner)
        XCTAssertTrue(skinner.skeleton === instance.nodes[0])
        XCTAssertEqual(skinner.bones.count, 2)
        XCTAssertTrue(skinner.bones[0] === instance.nodes[0])
        XCTAssertTrue(skinner.bones[1] === instance.nodes[1])
        XCTAssertEqual(skinner.boneInverseBindTransforms?.count, 2)
        let reference = try fixture(pixel: [255, 0, 0, 255], skinned: true,
            includeRootJoint: true, declaredRoot: 0).instantiate()
        let rest = try snapshot(instance), expected = try snapshot(reference)
        XCTAssertGreaterThan(rest.redPixelCount, 500)
        XCTAssertEqual(rest.redCenterX, expected.redCenterX, accuracy: 1)
        instance.nodes[1].simdPosition.x += 0.5
        XCTAssertEqual(try snapshot(instance).redCenterX - rest.redCenterX, 16, accuracy: 3,
                       "Correcting only the root must preserve joint weights and bone motion")
    }

    func testSkinRootCorrectionsRejectWrongDeclarationUnrelatedNodeAndMissingSkin() throws {
        for correction in [GLTFModel.SkinRootCorrection(declared: 0, corrected: 0),
                           .init(declared: 1, corrected: 1), .init(declared: 1, corrected: 2)] {
            XCTAssertThrowsError(try fixture(skinned: true, includeRootJoint: true, declaredRoot: 1,
                skinRootCorrections: [0: correction]))
        }
        XCTAssertThrowsError(try fixture(skinned: true, includeRootJoint: true, declaredRoot: 2,
            skinRootCorrections: [0: .init(declared: 2, corrected: 0)]),
            "A mesh node cannot be accepted as a source joint declaration")
        XCTAssertThrowsError(try fixture(skinned: true, includeRootJoint: true, declaredRoot: 1,
            skinRootCorrections: [1: .init(declared: 1, corrected: 0)]),
            "Unused correction entries must not silently hide a caller error")
    }

    func testPBRIsOptInAndRoutesPackedTextureChannels() throws {
        let packed: [String: Any] = ["metallicRoughnessTexture": ["index": 0], "roughnessFactor": 0.6, "metallicFactor": 0.2]
        let legacy = try fixture(pbrOverrides: packed).instantiate()
        XCTAssertEqual(legacy.materials[0].lightingModel, .lambert)
        let material = try XCTUnwrap(fixture(physicallyBased: true, pbrOverrides: packed).instantiate().materials.first)
        XCTAssertEqual(material.lightingModel, .physicallyBased)
        XCTAssertEqual(material.roughness.textureComponents, .green)
        XCTAssertEqual(material.metalness.textureComponents, .blue)
        XCTAssertEqual(material.roughness.intensity, 0.6, accuracy: 0.00001)
        XCTAssertEqual(material.metalness.intensity, 0.2, accuracy: 0.00001)
        XCTAssertTrue(material.roughness.contents is UIImage)
        XCTAssertThrowsError(try fixture(physicallyBased: true, pbrOverrides: ["roughnessFactor": -0.1]))
        XCTAssertThrowsError(try fixture(physicallyBased: true, pbrOverrides: ["metallicRoughnessTexture": ["index": 99]]))
    }

    func testInvalidMaterialConfigurationFailsInsteadOfSilentlyChangingItsMeaning() throws {
        XCTAssertThrowsError(try fixture(alphaMode: "UNKNOWN"))
        XCTAssertThrowsError(try fixture(alphaMode: "MASK", cutoff: -0.1))
        XCTAssertThrowsError(try fixture(factor: [1, 1, 1, 2]))
        XCTAssertThrowsError(try fixture(sampler: ["wrapS": 123]))
        XCTAssertThrowsError(try fixture(sampler: ["minFilter": 9988]))
    }

    func testBakedLightmapUsesIndependentUVsAndStaysUnlitWithPBRLoader() throws {
        let left = [[Float]](repeating: [Float(0.25), 0.5], count: 4).flatMap { $0 }
        let right = [[Float]](repeating: [Float(0.75), 0.5], count: 4).flatMap { $0 }
        let material: [String: Any] = ["extensions": ["KHR_materials_unlit": [String: Any]()],
            "extras": ["sf3Lightmap": ["index": 0, "texCoord": 1]]]
        let instance = try fixture(pixel: [255, 255, 255, 255, 255, 0, 0, 255],
            sampler: ["magFilter": 9728, "minFilter": 9728], uv: left,
            physicallyBased: true, materialOverrides: material, uv1: right).instantiate()
        XCTAssertEqual(instance.materials[0].lightingModel, .constant)
        XCTAssertEqual(instance.materials[0].multiply.mappingChannel, 1)
        assertPixel(try snapshot(instance).center, equals: SIMD3(255, 0, 0))
    }

    func testBakedLightmapRejectsMissingUVsAndBrokenTextureReferences() throws {
        let unlit: [String: Any] = ["KHR_materials_unlit": [String: Any]()]
        let valid: [String: Any] = ["extensions": unlit,
            "extras": ["sf3Lightmap": ["index": 0, "texCoord": 1]]]
        XCTAssertThrowsError(try fixture(pixel: [255, 255, 255, 255, 255, 0, 0, 255], materialOverrides: valid))
        let uv = [Float](repeating: 0.5, count: 8)
        XCTAssertThrowsError(try fixture(materialOverrides: ["extensions": unlit,
            "extras": ["sf3Lightmap": ["index": 99, "texCoord": 1]]], uv1: uv))
        XCTAssertThrowsError(try fixture(materialOverrides: ["extensions": unlit,
            "extras": ["sf3Lightmap": ["index": 0, "texCoord": 0]]], uv1: uv))
    }

    func testUniformLightmapRendersWithoutInventingASecondUVSet() throws {
        let material: [String: Any] = ["extensions": ["KHR_materials_unlit": [String: Any]()],
            "extras": ["sf3Lightmap": ["index": 0, "texCoord": 1]]]
        let instance = try fixture(pixel: [255, 0, 0, 255, 255, 0, 0, 255],
            physicallyBased: true, materialOverrides: material).instantiate()
        XCTAssertEqual(instance.materials[0].lightingModel, .constant)
        XCTAssertEqual(instance.materials[0].multiply.mappingChannel, 0)
        assertPixel(try snapshot(instance).center, equals: SIMD3(255, 0, 0))
    }

    func testSourceLocationByteColorsMultiplyBakedRGBOnceAndPreserveCoverage() throws {
        let left = [[Float]](repeating: [Float(0.25), 0.5], count: 4).flatMap { $0 }
        let right = [[Float]](repeating: [Float(0.75), 0.5], count: 4).flatMap { $0 }
        let colors = [[Float]](repeating: [128, 64, 192, 17], count: 4).flatMap { $0 }
        let material: [String: Any] = ["name": "home_01",
            "extensions": ["KHR_materials_unlit": [String: Any]()],
            "extras": ["sf3Lightmap": ["index": 0, "texCoord": 1]]]
        // A white base texel and a mid-gray lightmap make a missing gain,
        // duplicate vertex modulation, or unnormalized 255 observable.
        func surface(_ factor: [Double], mode: String = "OPAQUE", vertexColors: [Float]? = nil,
                     enabled: Bool = false, name: String = "home_01") throws -> GLTFModel {
            var definition = material; definition["name"] = name
            return try fixture(alphaMode: mode, factor: factor,
                pixel: [255, 255, 255, 255, 188, 188, 188, 255],
                sampler: ["magFilter": 9728, "minFilter": 9728], uv: left,
                physicallyBased: true, materialOverrides: definition, uv1: right,
                vertexColors: vertexColors, sourceLocationMaterials: enabled ? ["home_01"] : [])
        }
        let factor = [0.5, 0.5, 0.5, 0.5]
        let expectedFactor = [128.0 / 255, 64.0 / 255, 192.0 / 255, 0.5]
        let model = try surface(factor, vertexColors: colors, enabled: true)
        let expected = try snapshot(surface(expectedFactor).instantiate()).center
        assertPixel(try snapshot(model.instantiate()).center, equals: expected, accuracy: 5)
        assertPixel(try snapshot(model.instantiate()).center, equals: expected, accuracy: 5)
        XCTAssertGreaterThan(expected.x, 40); XCTAssertLessThan(expected.x, 100)

        let ordinary = try snapshot(surface(factor).instantiate()).center
        assertPixel(try snapshot(surface(factor, vertexColors: colors).instantiate()).center,
                    equals: ordinary, accuracy: 5)
        assertPixel(try snapshot(surface(factor, vertexColors: colors, enabled: true,
                                        name: "unrelated").instantiate()).center, equals: ordinary, accuracy: 5)
        let white = [Float](repeating: 255, count: 16)
        let whiteExpected = try snapshot(surface([1, 1, 1, 0.5]).instantiate()).center
        assertPixel(try snapshot(surface(factor, vertexColors: white, enabled: true).instantiate()).center,
                    equals: whiteExpected, accuracy: 5)
        assertPixel(try snapshot(surface(factor, enabled: true).instantiate()).center,
                    equals: whiteExpected, accuracy: 5)

        let blended = try surface(factor, mode: "BLEND", vertexColors: colors, enabled: true).instantiate()
        let blendReference = try surface(expectedFactor, mode: "BLEND").instantiate()
        assertPixel(try snapshot(blended).center, equals: try snapshot(blendReference).center, accuracy: 5)
        blended.root.opacity = 0.5; blendReference.root.opacity = 0.5
        assertPixel(try snapshot(blended).center, equals: try snapshot(blendReference).center, accuracy: 5)
    }

    private func assertPixel(_ actual: SIMD3<Float>, equals expected: SIMD3<Float>, accuracy: Float = 10,
                             file: StaticString = #filePath, line: UInt = #line) {
        for i in 0..<3 { XCTAssertEqual(actual[i], expected[i], accuracy: accuracy, file: file, line: line) }
    }

    private struct Pixels {
        let center: SIMD3<Float>
        let redPixelCount: Int
        let redCenterX: Float
    }

    private func snapshot(_ instance: GLTFModel.Instance) throws -> Pixels {
        let renderer = SCNRenderer(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()), options: nil)
        let scene = SCNScene()
        scene.background.contents = UIColor.blue
        scene.rootNode.addChildNode(instance.root)
        instance.materials.forEach { $0.lightingModel = .constant }
        let eye = SCNNode()
        eye.camera = SCNCamera()
        eye.camera?.usesOrthographicProjection = true
        eye.camera?.orthographicScale = 2
        eye.camera?.wantsHDR = false
        eye.camera?.wantsExposureAdaptation = false
        eye.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(eye)
        renderer.scene = scene
        renderer.pointOfView = eye
        SCNTransaction.flush()
        let cg = try XCTUnwrap(renderer.snapshot(atTime: 0, with: CGSize(width: 128, height: 128), antialiasingMode: .none).cgImage)
        var rgba = [UInt8](repeating: 0, count: 128 * 128 * 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB))
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 128, height: 128,
                bitsPerComponent: 8, bytesPerRow: 128 * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 128, height: 128))
        }
        let middle = (64 * 128 + 64) * 4
        let center = SIMD3(Float(rgba[middle]), Float(rgba[middle + 1]), Float(rgba[middle + 2]))
        let red = stride(from: 0, to: rgba.count, by: 4).filter { rgba[$0] > 200 && rgba[$0 + 2] < 30 }
        let sum = red.reduce(0) { $0 + ($1 / 4) % 128 }
        return Pixels(center: center, redPixelCount: red.count, redCenterX: red.isEmpty ? -1 : Float(sum) / Float(red.count))
    }

    private func zeroAlphaRedPNG() throws -> Data {
        // 2x2, RGBA8, no color conversion metadata; each scanline retains red
        // at alpha zero. The opaque test downsizes this image to one pixel.
        try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DAAMIMMAYAKegD/QE6Y34AAAAASUVORK5CYII="))
    }

    private func fixture(alphaMode: String = "OPAQUE", factor: [Double] = [1, 1, 1, 1],
                         pixel: [UInt8]? = [255, 255, 255, 255], cutoff: Double? = nil,
                         sampler: [String: Int]? = nil, uv: [Float]? = nil,
                         skinned: Bool = false, explicitRoot: Bool = false,
                         includeRootJoint: Bool = false, declaredRoot: Int? = nil,
                         skinRootCorrections: [Int: GLTFModel.SkinRootCorrection] = [:],
                         texturePNG: Data? = nil, embeddedTexture: Bool = false,
                         maxTexture: CGFloat = 512, physicallyBased: Bool = false,
                         pbrOverrides: [String: Any] = [:], materialOverrides: [String: Any] = [:],
                         uv1: [Float]? = nil, vertexColors: [Float]? = nil,
                         sourceLocationMaterials: Set<String> = []) throws -> GLTFModel {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gltf-material-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        var binary = Data(), views: [[String: Any]] = [], accessors: [[String: Any]] = []
        func append(_ data: Data, component: Int, type: String, count: Int) -> Int {
            while !binary.count.isMultiple(of: 4) { binary.append(0) }
            let view = views.count
            views.append(["buffer": 0, "byteOffset": binary.count, "byteLength": data.count])
            binary.append(data)
            accessors.append(["bufferView": view, "componentType": component, "type": type, "count": count])
            return accessors.count - 1
        }
        func floats(_ values: [Float], type: String, width: Int) -> Int {
            append(values.withUnsafeBufferPointer { Data(buffer: $0) }, component: 5126, type: type, count: values.count / width)
        }
        let positions = floats([-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0], type: "VEC3", width: 3)
        accessors[positions]["min"] = [-1, -1, 0]
        accessors[positions]["max"] = [1, 1, 0]
        let normals = floats([0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1], type: "VEC3", width: 3)
        let texcoords = floats(uv ?? [0, 1, 1, 1, 1, 0, 0, 0], type: "VEC2", width: 2)
        let indexValues: [UInt16] = [0, 1, 2, 0, 2, 3]
        let indices = append(indexValues.withUnsafeBufferPointer { Data(buffer: $0) }, component: 5123, type: "SCALAR", count: 6)
        var attributes = ["POSITION": positions, "NORMAL": normals, "TEXCOORD_0": texcoords]
        if let uv1 { attributes["TEXCOORD_1"] = floats(uv1, type: "VEC2", width: 2) }
        if let vertexColors { attributes["COLOR_0"] = floats(vertexColors, type: "VEC4", width: 4) }
        var nodes: [[String: Any]] = [["name": "mesh", "mesh": 0]]
        var skin: [String: Any]?
        if skinned {
            let jointIndices: [UInt8] = (0..<4).flatMap { _ in [includeRootJoint ? 1 : 0, 0, 0, 0] }
            attributes["JOINTS_0"] = append(Data(jointIndices), component: 5121, type: "VEC4", count: 4)
            attributes["WEIGHTS_0"] = floats([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], type: "VEC4", width: 4)
            let identity: [Float] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
            let bind = floats(includeRootJoint ? identity + identity : identity, type: "MAT4", width: 16)
            skin = ["joints": includeRootJoint ? [0, 1] : [1], "inverseBindMatrices": bind]
            if explicitRoot { skin?["skeleton"] = 0 }
            if let declaredRoot { skin?["skeleton"] = declaredRoot }
            nodes = [["name": "skeletonRoot", "translation": [0.2, 0, 0], "children": [1, 2]],
                     ["name": "joint", "translation": [0.3, 0, 0]],
                     ["name": "mesh", "mesh": 0, "skin": 0, "translation": [40, 0, 0]]]
        }
        var pbr: [String: Any] = ["baseColorFactor": factor]
        if pixel != nil || texturePNG != nil { pbr["baseColorTexture"] = ["index": 0] }
        pbr.merge(pbrOverrides) { _, new in new }
        var material: [String: Any] = ["name": "synthetic", "alphaMode": alphaMode, "pbrMetallicRoughness": pbr]
        material.merge(materialOverrides) { _, new in new }
        if let cutoff { material["alphaCutoff"] = cutoff }
        var document: [String: Any] = ["asset": ["version": "2.0"], "scene": 0, "scenes": [["nodes": [0]]],
            "nodes": nodes, "meshes": [["primitives": [["attributes": attributes, "indices": indices, "material": 0]]]],
            "materials": [material], "buffers": [["uri": "mesh.bin", "byteLength": binary.count]],
            "bufferViews": views, "accessors": accessors]
        if let skin { document["skins"] = [skin] }
        if pixel != nil || texturePNG != nil {
            let png: Data
            if let texturePNG {
                png = texturePNG
            } else {
                let pixel = try XCTUnwrap(pixel)
                let data = Data(pixel)
                let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
                let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
                let image = try XCTUnwrap(CGImage(width: pixel.count / 4, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: pixel.count, space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
                let encoded = NSMutableData()
                let destination = try XCTUnwrap(CGImageDestinationCreateWithData(encoded as CFMutableData, UTType.png.identifier as CFString, 1, nil))
                CGImageDestinationAddImage(destination, image, nil)
                XCTAssertTrue(CGImageDestinationFinalize(destination))
                png = encoded as Data
            }
            if embeddedTexture {
                while !binary.count.isMultiple(of: 4) { binary.append(0) }
                document["images"] = [["bufferView": views.count, "mimeType": "image/png"]]
                views.append(["buffer": 0, "byteOffset": binary.count, "byteLength": png.count])
                binary.append(png)
                document["bufferViews"] = views
                document["buffers"] = [["uri": "mesh.bin", "byteLength": binary.count]]
            } else {
                try png.write(to: folder.appendingPathComponent("color.png"))
                document["images"] = [["uri": "color.png"]]
            }
            var texture: [String: Any] = ["source": 0]
            if let sampler { document["samplers"] = [sampler]; texture["sampler"] = 0 }
            document["textures"] = [texture]
        }
        try binary.write(to: folder.appendingPathComponent("mesh.bin"))
        let url = folder.appendingPathComponent("fixture.gltf")
        try JSONSerialization.data(withJSONObject: document).write(to: url)
        return try GLTFModel(url: url, maxTexture: maxTexture, physicallyBased: physicallyBased,
                             sourceLocationMaterials: sourceLocationMaterials, skinRootCorrections: skinRootCorrections)
    }
}
