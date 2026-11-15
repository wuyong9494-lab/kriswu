import CryptoKit
import Metal
import SceneKit
import UIKit
import XCTest
@testable import ShiftReminder

/// These small textures and meshes are synthetic contract fixtures. No test
/// here is evidence that the private original character pack was installed.
@MainActor
final class DuelTriadSourceMorphTests: XCTestCase {
    private typealias Morph = DuelTriadSourceMorph

    private func device() throws -> MTLDevice {
        try XCTUnwrap(MTLCreateSystemDefaultDevice(), "MORPH acceptance requires actual Metal")
    }
    private func mask(_ data: Data, width: Int = 1, height: Int = 1,
                      format: Int = 4, colorSpace: Int = 0, filter: Int = 1,
                      file: String = "synthetic-morph.texture") -> Morph.Mask {
        .init(file: file, bytes: data.count,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            width: width, height: height, sourceTextureFormat: format,
            sourceColorSpace: colorSpace, mip: 1, filter: filter, wrapS: 0, wrapT: 0)
    }
    private func parameters(name: String = "synthetic-body", item: Int? = 2,
                            base: Bool = false, tile: Float = 1, edge: Float = 0.1,
                            start: [Float] = [0, 0, 0, 1],
                            end: [Float] = [0, 0.34, 0.38, 1]) -> Morph.MaterialBinding {
        .init(name: name, sourceItemType: item, actorBaseGeometry: base,
            tile: tile, edgeSize: edge, edgeStart: start, edgeEnd: end)
    }
    private func quad(uv: CGPoint?, material: SCNMaterial) -> SCNNode {
        let vertices: [SCNVector3] = [SCNVector3(-1, -1, 0), SCNVector3(1, -1, 0),
            SCNVector3(1, 1, 0), SCNVector3(-1, 1, 0)]
        let indices: [UInt16] = [0, 1, 2, 0, 2, 3]
        var sources = [SCNGeometrySource(vertices: vertices),
            SCNGeometrySource(normals: [SCNVector3](repeating: SCNVector3(0, 0, 1), count: 4))]
        if let uv { sources.append(SCNGeometrySource(textureCoordinates: [CGPoint](repeating: uv, count: 4))) }
        let geometry = SCNGeometry(sources: sources,
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }
    private func fixture(uv: CGPoint? = CGPoint(x: 0.25, y: 0.25),
                         color: UIColor = .red) -> GLTFModel.Instance {
        let material = SCNMaterial(); material.name = "synthetic-body"
        material.lightingModel = .constant; material.diffuse.contents = color
        material.readsFromDepthBuffer = true; material.writesToDepthBuffer = true
        material.blendMode = .alpha
        let node = quad(uv: uv, material: material), root = SCNNode()
        root.addChildNode(node)
        return .init(root: root, nodes: [node], materials: [material], outlines: [])
    }
    private func binding(_ instance: GLTFModel.Instance, device: MTLDevice,
                         red: UInt8 = 128, parameters value: Morph.MaterialBinding? = nil) throws -> Morph.Binding {
        let data = Data([red, 0, 0, 255])
        return try Morph.prepare(mask: mask(data), data: data, device: device)
            .install(on: instance, materials: [value ?? parameters()])
    }

    func testMaskRejectsDigestLayoutColorSpaceAndUnsupportedSampler() throws {
        let gpu = try device(), data = Data([0, 0, 0, 255])
        let good = mask(data)
        XCTAssertEqual(try Morph.prepare(mask: good, data: data, device: gpu).texture.pixelFormat, .rgba8Unorm)
        XCTAssertThrowsError(try Morph.prepare(mask: good, data: Data([1, 0, 0, 255]), device: gpu))
        for bad in [mask(data, width: 2), mask(data, width: 1025), mask(data, format: 47),
                    mask(data, colorSpace: 1), mask(data, filter: 0), mask(data, file: "../mask.texture")] {
            XCTAssertThrowsError(try Morph.prepare(mask: bad, data: data, device: gpu))
        }
    }

    func testBindingsRequireCompleteNamesAndHonestBaseGeometryIdentity() throws {
        let gpu = try device(), instance = fixture(), data = Data([0, 0, 0, 255])
        let prepared = try Morph.prepare(mask: mask(data), data: data, device: gpu)
        for invalid in [parameters(item: nil), parameters(item: 3, base: true), parameters(item: 0),
                        parameters(tile: .nan), parameters(edge: 0), parameters(start: [0, 0, 0, 0.5])] {
            XCTAssertThrowsError(try prepared.install(on: instance, materials: [invalid]))
        }
        XCTAssertThrowsError(try prepared.install(on: instance, materials: [parameters(name: "other")]))
        XCTAssertThrowsError(try prepared.install(on: instance, materials: [parameters(), parameters()]))
        XCTAssertNoThrow(try prepared.install(on: instance, materials: [parameters(item: nil, base: true)]))
        instance.materials[0].diffuse.contentsTransform = SCNMatrix4MakeScale(2, 1, 1)
        XCTAssertThrowsError(try prepared.install(on: instance, materials: [parameters()]))

        let missingEquipmentUV = fixture(uv: nil)
        XCTAssertThrowsError(try prepared.install(on: missingEquipmentUV, materials: [parameters()]))
        XCTAssertThrowsError(try prepared.install(on: missingEquipmentUV,
            materials: [parameters(item: nil, base: true)]), "Other personal meshes cannot infer a missing UV")
        let neck = fixture(uv: nil), neckMaterial = neck.materials[0]
        neckMaterial.name = "Liu_Neck_Skin"
        let neckParameters = parameters(name: "Liu_Neck_Skin", item: nil, base: true, tile: 0.2)
        XCTAssertNoThrow(try prepared.install(on: neck, materials: [neckParameters]))
        XCTAssertTrue(try XCTUnwrap(neck.nodes[0].geometry).sources(for: .texcoord).isEmpty)
        XCTAssertThrowsError(try prepared.install(on: neck,
            materials: [parameters(name: "Liu_Neck_Skin", item: 2)]))
        neckMaterial.diffuse.contents = UIImage()
        XCTAssertThrowsError(try prepared.install(on: neck, materials: [neckParameters]),
            "A textured material cannot use the untextured neck adapter")
        neckMaterial.diffuse.contents = UIColor.red
        let originalNormal = neckMaterial.normal.contents
        neckMaterial.normal.contents = UIImage()
        XCTAssertThrowsError(try prepared.install(on: neck, materials: [neckParameters]),
            "A solid diffuse color must not hide a secondary texture's missing UV")
        neckMaterial.normal.contents = originalNormal
        neck.root.addChildNode(quad(uv: .zero, material: neckMaterial))
        XCTAssertThrowsError(try prepared.install(on: neck, materials: [neckParameters]),
            "One material cannot mix authored UVs and the constant-origin adapter")
    }

    func testNormalBoundaryThenExactly140TicksCompletesAndRepeatedRequestsDoNotRestart() throws {
        let instance = fixture(), state = try binding(instance, device: device())
        let material = instance.materials[0], original = instance.materials[0].shaderModifiers
        try state.requestHide(sourceTick: 70)
        XCTAssertTrue(state.hasPendingBoundary); XCTAssertEqual(state.progress, 0)
        XCTAssertEqual(material.shaderModifiers, original)
        XCTAssertEqual(material.blendMode, .alpha, "Waiting for EndOfFrame must preserve the original raster state")
        try state.update(sourceTick: 70); try state.didRenderFrame(sourceTick: 70)
        XCTAssertFalse(state.hasPendingBoundary)
        try state.update(sourceTick: 209)
        XCTAssertEqual(state.progress, Float(139) / 140, accuracy: 1e-6)
        XCTAssertFalse(instance.nodes[0].isHidden)
        try state.requestHide(sourceTick: 70)
        try state.didRenderFrame(sourceTick: 209); try state.update(sourceTick: 209)
        XCTAssertEqual(state.progress, Float(139) / 140, accuracy: 1e-6)
        try state.update(sourceTick: 210)
        XCTAssertTrue(state.isComplete); XCTAssertTrue(instance.nodes[0].isHidden)
        XCTAssertEqual(state.progress, 1); XCTAssertNil(instance.materials[0].shaderModifiers)
    }

    func testNoRenderBoundaryNoProgressAndPauseDoesNotConsumeSourceTime() throws {
        let instance = fixture(), state = try binding(instance, device: device())
        try state.requestHide(sourceTick: 70); try state.update(sourceTick: 170)
        XCTAssertEqual(state.progress, 0); XCTAssertTrue(state.hasPendingBoundary)
        try state.didRenderFrame(sourceTick: 170); try state.update(sourceTick: 240)
        XCTAssertEqual(state.progress, 0.5)
        let cutoff = instance.materials[0].value(forKey: "triadMorphCutoff") as? NSNumber
        for _ in 0..<4 { try state.didRenderFrame(sourceTick: 240); try state.update(sourceTick: 240) }
        XCTAssertEqual(instance.materials[0].value(forKey: "triadMorphCutoff") as? NSNumber, cutoff)
        try state.update(sourceTick: 300, paused: true)
        XCTAssertEqual(state.progress, 0.5)
        try state.update(sourceTick: 369); XCTAssertFalse(state.isComplete)
        try state.update(sourceTick: 370); XCTAssertTrue(state.isComplete)
        XCTAssertThrowsError(try state.update(sourceTick: 369))
    }

    func testResetRestoresModifiersRasterVisibilityAndCanBeginNextRound() throws {
        let instance = fixture(), material = instance.materials[0]
        material.shaderModifiers = [.surface: "#pragma body\n_surface.diffuse.rgb *= 0.75;",
            .fragment: "#pragma body\n_output.color.a *= 1.0;"]
        let original = material.shaderModifiers
        let state = try binding(instance, device: device())
        try state.requestHide(sourceTick: 0); try state.didRenderFrame(sourceTick: 0)
        try state.update(sourceTick: 70)
        XCTAssertEqual(material.blendMode, .replace)
        XCTAssertTrue(material.shaderModifiers?[.surface]?.contains("_surface.diffuse.rgb *= 0.75;") == true)
        state.reset()
        XCTAssertEqual(material.shaderModifiers, original); XCTAssertEqual(material.blendMode, .alpha)
        XCTAssertTrue(material.readsFromDepthBuffer); XCTAssertTrue(material.writesToDepthBuffer)
        XCTAssertFalse(instance.nodes[0].isHidden); XCTAssertEqual(state.progress, 0)
        try state.requestHide(sourceTick: 0); try state.didRenderFrame(sourceTick: 0); try state.update(sourceTick: 140)
        XCTAssertTrue(instance.nodes[0].isHidden)
        state.reset(); XCTAssertFalse(instance.nodes[0].isHidden)
        state.shutdown(); XCTAssertThrowsError(try state.requestHide(sourceTick: 0))
    }

    func testCancellationHasSourceCompletionSemanticsOnlyAfterTweenStarts() throws {
        let instance = fixture(), state = try binding(instance, device: device())
        try state.requestHide(sourceTick: 0); state.cancel()
        XCTAssertFalse(instance.nodes[0].isHidden); XCTAssertFalse(state.isComplete)
        try state.requestHide(sourceTick: 0); try state.didRenderFrame(sourceTick: 0)
        try state.update(sourceTick: 1); state.cancel()
        XCTAssertTrue(state.isComplete); XCTAssertTrue(instance.nodes[0].isHidden)
        XCTAssertNil(instance.materials[0].shaderModifiers)
        state.reset(); XCTAssertFalse(instance.nodes[0].isHidden)
    }

    func testOriginalVIsRestoredBeforeTileAndDiscardDoesNotOccludeBackground() throws {
        let gpu = try device(), scene = SCNScene()
        let left = fixture(uv: CGPoint(x: 0.25, y: 0.25)), right = fixture(uv: CGPoint(x: 0.25, y: 0.75))
        left.root.position.x = -0.6; right.root.position.x = 0.6
        left.root.scale = SCNVector3(0.45, 0.8, 1); right.root.scale = SCNVector3(0.45, 0.8, 1)
        scene.rootNode.addChildNode(left.root); scene.rootNode.addChildNode(right.root)
        // Original row0 is zero, row1 is one; no upload-time image flip.
        let data = Data([0, 0, 0, 255, 0, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255])
        let prepared = try Morph.prepare(mask: mask(data, width: 2, height: 2), data: data, device: gpu)
        let a = try prepared.install(on: left, materials: [parameters()])
        let b = try prepared.install(on: right, materials: [parameters()])
        let background = SCNMaterial(); background.lightingModel = .constant; background.diffuse.contents = UIColor.green
        let back = quad(uv: .zero, material: background); back.position.z = -1
        back.scale = SCNVector3(3, 3, 1); back.renderingOrder = 10; scene.rootNode.addChildNode(back)
        for state in [a, b] {
            try state.requestHide(sourceTick: 0); try state.didRenderFrame(sourceTick: 0); try state.update(sourceTick: 70)
        }
        let harness = try Harness(device: gpu, scene: scene)
        let pixels = try harness.render()
        let l = harness.pixel(pixels, world: SCNVector3(-0.6, 0, 0))
        let r = harness.pixel(pixels, world: SCNVector3(0.6, 0, 0))
        XCTAssertGreaterThan(l.y, 230); XCTAssertLessThan(l.x, 15, "Clipped fragment must not write depth")
        XCTAssertGreaterThan(r.x, 230); XCTAssertLessThan(r.y, 15, "Surviving fragment must remain opaque in front")
        XCTAssertEqual(l.w, 255); XCTAssertEqual(r.w, 255)

        // With repeat+bilinear on this 2x2 mask, source UV(0,0) samples 0.5.
        // A fabricated glTF UV(0,0), then 1-V and tile0.2, samples near0.1.
        // A cutoff near0.23 must clip only the exact neck-origin adapter.
        let neckScene = SCNScene(), neck = fixture(uv: nil), flippedZero = fixture(uv: .zero)
        neck.materials[0].name = "Liu_Neck_Skin"
        let originalNeckGeometry = try XCTUnwrap(neck.nodes[0].geometry)
        neck.root.position.x = -0.6; flippedZero.root.position.x = 0.6
        for actor in [neck, flippedZero] { actor.root.scale = SCNVector3(0.45, 0.8, 1); neckScene.rootNode.addChildNode(actor.root) }
        let neckBinding = try prepared.install(on: neck, materials: [
            parameters(name: "Liu_Neck_Skin", item: nil, base: true, tile: 0.2)])
        let controlBinding = try prepared.install(on: flippedZero, materials: [parameters(tile: 0.2)])
        let neckBackground = quad(uv: .zero, material: background)
        neckBackground.position.z = -1; neckBackground.scale = SCNVector3(3, 3, 1)
        neckBackground.renderingOrder = 10; neckScene.rootNode.addChildNode(neckBackground)
        let neckHarness = try Harness(device: gpu, scene: neckScene)
        let baselineNeck = neckHarness.pixel(try neckHarness.render(), world: SCNVector3(-0.6, 0, 0))
        XCTAssertGreaterThan(baselineNeck.x, 230); XCTAssertLessThan(baselineNeck.y, 15)
        for state in [neckBinding, controlBinding] {
            try state.requestHide(sourceTick: 0, transitionTicks: 100)
            try state.didRenderFrame(sourceTick: 0); try state.update(sourceTick: 20)
        }
        // A missing SceneKit pipeline also reveals the green background. The
        // same no-UV geometry must first survive with MORPH actually installed,
        // otherwise the later discard pixel would be a false positive.
        let activeNeck = neckHarness.pixel(try neckHarness.render(), world: SCNVector3(-0.6, 0, 0))
        XCTAssertGreaterThan(activeNeck.x, 230); XCTAssertLessThan(activeNeck.y, 15)
        XCTAssertEqual(activeNeck, baselineNeck)
        let sourceValue = try XCTUnwrap(neck.materials[0].value(forKey: "triadMorphSourceValue") as? NSNumber)
        XCTAssertEqual(sourceValue.floatValue, 0.5, accuracy: 0.000001,
            "The original repeat/bilinear source origin is the four-corner sample, not the flipped glTF origin")
        XCTAssertFalse(neck.materials[0].shaderModifiers?.values.contains(where: {
            $0.contains("texture2d<") || $0.contains("constexpr sampler") || $0.contains("diffuseTexcoord")
        }) ?? true, "The constant-source adapter cannot retain a SceneKit texcoord dependency")
        try neckBinding.update(sourceTick: 50)
        let edgeNeck = neckHarness.pixel(try neckHarness.render(), world: SCNVector3(-0.6, 0, 0))
        // sample=.5, cutoff=.45 and edge=.1 put this at the source
        // smoothstep midpoint. The scalar path must retain the real edge RGB.
        let edgeMidpoint: [Float] = [0, 0.34 * 0.5, 0.38 * 0.5]
        for channel in 0..<3 {
            XCTAssertEqual(Float(edgeNeck[channel]), edgeMidpoint[channel] * 255, accuracy: 3)
        }
        XCTAssertEqual(edgeNeck.w, 255)
        for state in [neckBinding, controlBinding] { try state.update(sourceTick: 70) }
        let neckPixels = try neckHarness.render()
        let origin = neckHarness.pixel(neckPixels, world: SCNVector3(-0.6, 0, 0))
        let incorrectFlip = neckHarness.pixel(neckPixels, world: SCNVector3(0.6, 0, 0))
        XCTAssertGreaterThan(origin.y, 230); XCTAssertLessThan(origin.x, 15)
        XCTAssertGreaterThan(incorrectFlip.x, 230); XCTAssertLessThan(incorrectFlip.y, 15)
        XCTAssertEqual(origin.w, 255); XCTAssertEqual(incorrectFlip.w, 255)
        XCTAssertTrue(try XCTUnwrap(neck.nodes[0].geometry).sources(for: .texcoord).isEmpty,
            "The adapter must never manufacture or append a UV buffer")
        neckBinding.reset(); controlBinding.reset()
        let restoredNeck = neckHarness.pixel(try neckHarness.render(), world: SCNVector3(-0.6, 0, 0))
        XCTAssertGreaterThan(restoredNeck.x, 230); XCTAssertLessThan(restoredNeck.y, 15)
        XCTAssertEqual(restoredNeck, baselineNeck)
        XCTAssertTrue(neck.nodes[0].geometry === originalNeckGeometry)
        XCTAssertTrue(originalNeckGeometry.sources(for: .texcoord).isEmpty)

        // Sampling is tied to each authenticated mask, not hardcoded to this
        // 2x2 fixture's 0.5 or cached globally across different textures.
        let otherData = Data([64, 0, 0, 255])
        let otherPrepared = try Morph.prepare(mask: mask(otherData), data: otherData, device: gpu)
        let otherBinding = try otherPrepared.install(on: neck, materials: [
            parameters(name: "Liu_Neck_Skin", item: nil, base: true, tile: 0.2)])
        defer { otherBinding.shutdown() }
        try otherBinding.requestHide(sourceTick: 0); try otherBinding.didRenderFrame(sourceTick: 0)
        let otherValue = try XCTUnwrap(neck.materials[0].value(forKey: "triadMorphSourceValue") as? NSNumber)
        XCTAssertEqual(otherValue.floatValue, Float(64) / 255, accuracy: 0.00001)
        XCTAssertEqual(neckHarness.pixel(try neckHarness.render(), world: SCNVector3(-0.6, 0, 0)), baselineNeck)
        XCTAssertTrue(neck.nodes[0].geometry === originalNeckGeometry)
        XCTAssertTrue(originalNeckGeometry.sources(for: .texcoord).isEmpty)
    }

    func testGammaEdgeUsesOriginalSmoothstepAndPreservesOpaqueAlphaOnGPU() throws {
        let gpu = try device(), instance = fixture(), scene = SCNScene()
        scene.rootNode.addChildNode(instance.root)
        let end: [Float] = [0.2, 0.6, 0.8, 1]
        let state = try binding(instance, device: gpu, red: 128,
            parameters: parameters(edge: 1, end: end))
        try state.requestHide(sourceTick: 0, transitionTicks: 2)
        try state.didRenderFrame(sourceTick: 0); try state.update(sourceTick: 1)
        let harness = try Harness(device: gpu, scene: scene), pixels = try harness.render()
        let value = harness.pixel(pixels, world: SCNVector3Zero)
        let t = Float(128) / 255, smooth = t * t * (3 - 2 * t)
        for channel in 0..<3 {
            XCTAssertEqual(Float(value[channel]), end[channel] * smooth * 255, accuracy: 3)
        }
        XCTAssertEqual(value.w, 255)
        XCTAssertTrue(instance.materials[0].writesToDepthBuffer)
    }

    func testExactCutoffBoundaryAddsBaseAndEdgeStartInGammaSpaceOnGPU() throws {
        let gpu = try device(), instance = fixture(color: UIColor(red: 0.2, green: 0.1, blue: 0.05, alpha: 1))
        let scene = SCNScene(); scene.rootNode.addChildNode(instance.root)
        let harness = try Harness(device: gpu, scene: scene)
        let before = harness.pixel(try harness.render(), world: SCNVector3Zero)
        let start: [Float] = [0.1, 0.2, 0.3, 1]
        let state = try binding(instance, device: gpu, red: 0,
            parameters: parameters(edge: 1, start: start, end: [0.8, 0.8, 0.8, 1]))
        try state.requestHide(sourceTick: 0, transitionTicks: 2)
        try state.didRenderFrame(sourceTick: 0); try state.update(sourceTick: 1)
        let after = harness.pixel(try harness.render(), world: SCNVector3Zero)
        for channel in 0..<3 {
            XCTAssertEqual(Float(after[channel]), Float(before[channel]) + start[channel] * 255, accuracy: 3)
        }
        XCTAssertEqual(after.w, before.w)

        // The original weapon starts at cutoff=1 with a nonzero blue edge.
        // At mask=1 that edge is added to the base color, so installing MORPH
        // before EndOfFrame would visibly alter the waiting frame.
        state.reset()
        let weaponStart: [Float] = [0, 0.101960786, 0.572549045, 1]
        let weapon = try binding(instance, device: gpu, red: 255,
            parameters: parameters(item: 3, tile: 0.1, edge: 0.1,
                start: weaponStart, end: [0, 0.929411769, 0.956862748, 1]))
        let original = instance.materials[0].shaderModifiers
        try weapon.requestHide(sourceTick: 70)
        XCTAssertEqual(instance.materials[0].shaderModifiers, original)
        let waiting = harness.pixel(try harness.render(), world: SCNVector3Zero)
        XCTAssertEqual(waiting, before, "The real GPU waiting frame must have no premature weapon edge")
        XCTAssertTrue(weapon.hasPendingBoundary); XCTAssertEqual(weapon.progress, 0)
        // render() has committed and completed an actual command buffer.
        try weapon.didRenderFrame(sourceTick: 70)
        let started = harness.pixel(try harness.render(), world: SCNVector3Zero)
        for channel in 0..<3 {
            XCTAssertEqual(Float(started[channel]), Float(before[channel]) + weaponStart[channel] * 255, accuracy: 3)
        }
        XCTAssertGreaterThan(Int(started.z) - Int(waiting.z), 140)
        XCTAssertEqual(started.w, before.w); XCTAssertEqual(weapon.progress, 0)
        try weapon.didRenderFrame(sourceTick: 70); try weapon.update(sourceTick: 70)
        let duplicate = harness.pixel(try harness.render(), world: SCNVector3Zero)
        XCTAssertEqual(duplicate, started, "Repeated draws at the same source tick cannot advance the transition")
    }

    func testOriginalProjectionFadesWholeSilhouetteUntilCompletionAndRestoresOnReset() throws {
        // Original CharacterShader has no ShadowCaster pass. Native 38405 and
        // 23565 instead feed progress into an independent silhouette map; the
        // recovered receiver multiplies q+(1-q)*ShadowColor. This test replaces
        // the disproved assumption that SceneKit's opaque shadow samples MORPH.
        let gpu = try device(), scene = SCNScene()
        let target = DuelProjectedShadowFixture.actor(name: "morph_target", halfSize: 0.4, varyingUV: true)
        let opponent = DuelProjectedShadowFixture.actor(name: "unchanged_opponent", halfSize: 0.4)
        target.root.position.x = -0.65; opponent.root.position.x = 0.65
        scene.rootNode.addChildNode(target.root); scene.rootNode.addChildNode(opponent.root)
        let backgroundMaterial = SCNMaterial(); backgroundMaterial.lightingModel = .constant
        backgroundMaterial.diffuse.contents = UIColor.green
        let background = quad(uv: .zero, material: backgroundMaterial)
        background.position.z = -1; background.scale = SCNVector3(3, 3, 1)
        background.castsShadow = false; scene.rootNode.addChildNode(background)
        let projection = try DuelProjectedShadowFixture(device: gpu, actors: [target, opponent])
        defer { projection.renderer.shutdown() }
        let harness = try Harness(device: gpu, scene: scene)
        let original = try projection.receiver(tick: 0)
        let originalTarget = projection.rgba(original, x: 21), originalOpponent = projection.rgba(original, x: 42)
        XCTAssertLessThan(originalTarget.x, 60, "An actual source projection must be present before MORPH")
        let masks: [(Data, Int, String)] = [
            (Data([255, 0, 0, 255]), 1, "fully clipped body"),
            (Data([0, 0, 0, 255]), 1, "surviving opaque body"),
            (Data([0, 0, 0, 255, 255, 0, 0, 255, 0, 0, 0, 255, 255, 0, 0, 255]), 2, "partially clipped body")]
        var referenceMap: [UInt8]?
        for (data, side, label) in masks {
            let state = try Morph.prepare(mask: mask(data, width: side, height: side), data: data, device: gpu)
                .install(on: target, materials: [parameters()])
            defer { state.shutdown() }
            projection.renderer.reset(); projection.factors = [0, 0]
            try state.requestHide(sourceTick: 0)
            XCTAssertEqual(try projection.receiver(tick: 0), original, "The EndOfFrame wait preserves the original shadow")
            try state.didRenderFrame(sourceTick: 0); try state.update(sourceTick: 70)
            projection.factors[0] = state.progress
            let halfway = try projection.receiver(tick: 70)
            let shadow = projection.rgba(halfway, x: 21)
            for channel in 0..<4 {
                let base: [Float] = [204, 153, 102, 255]
                let color = projection.definition.sourceLocation.shadowColor[channel]
                XCTAssertEqual(Float(shadow[channel]), base[channel] * (0.5 + 0.5 * color), accuracy: 3, label)
            }
            XCTAssertEqual(projection.rgba(halfway, x: 42), originalOpponent, "The other actor cannot inherit the target's factor")
            let map = try projection.map(tick: 70)
            if let referenceMap { XCTAssertEqual(map, referenceMap, "All masks use the same whole-silhouette shadow") }
            else { referenceMap = map }
            XCTAssertFalse(target.nodes[0].isHidden); XCTAssertFalse(state.isComplete)
            let visible = try harness.render()
            let left = harness.pixel(visible, world: SCNVector3(-0.85, 0, 0))
            let right = harness.pixel(visible, world: SCNVector3(-0.45, 0, 0))
            if label == "fully clipped body" {
                XCTAssertGreaterThan(left.y, 230); XCTAssertGreaterThan(right.y, 230)
            } else if label == "surviving opaque body" {
                XCTAssertGreaterThan(left.x, 230); XCTAssertGreaterThan(right.x, 230)
            } else {
                XCTAssertGreaterThan(left.x, 230); XCTAssertGreaterThan(right.y, 230)
            }
            XCTAssertEqual(left.w, 255); XCTAssertEqual(right.w, 255)
            try state.update(sourceTick: 140); projection.factors[0] = state.progress
            XCTAssertTrue(state.isComplete); XCTAssertTrue(target.nodes[0].isHidden)
            let completed = try projection.receiver(tick: 140)
            XCTAssertEqual(projection.rgba(completed, x: 21), SIMD4<UInt8>(204, 153, 102, 255))
            XCTAssertEqual(projection.rgba(completed, x: 42), originalOpponent)
            state.reset(); projection.factors[0] = state.progress; projection.renderer.reset()
            XCTAssertEqual(try projection.receiver(tick: 0), original)
            try state.requestHide(sourceTick: 0); try state.didRenderFrame(sourceTick: 0)
            try state.update(sourceTick: 70); projection.factors[0] = state.progress
            _ = try projection.receiver(tick: 70)
            state.cancel(); projection.factors[0] = state.progress
            let canceled = try projection.receiver(tick: 70)
            XCTAssertEqual(projection.rgba(canceled, x: 21), SIMD4<UInt8>(204, 153, 102, 255),
                "Source cancel invokes completion without waiting for another core tick")
            state.reset(); projection.factors[0] = 0; projection.renderer.reset()
        }
    }

    func testCommittedControlledCaptureProvidesOneBoundaryAndShutdownClearsCallback() throws {
        let gpu = try device(), instance = fixture(), scene = SCNScene()
        scene.rootNode.addChildNode(instance.root)
        let state = try binding(instance, device: gpu)
        let packets = try DuelTriadMetalRenderer(device: gpu, formats: DuelTriadRenderSurface.formats(device: gpu))
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.position.z = 5
        scene.rootNode.addChildNode(camera)
        let surface = try DuelTriadRenderSurface(device: gpu, scene: scene, pointOfView: camera, packets: packets)
        defer { surface.shutdown(); packets.shutdown(); state.shutdown() }
        var boundaryErrors: [Error] = [], callbacks = 0
        surface.didSubmitFrame = {
            callbacks += 1
            do { try state.didRenderFrame(sourceTick: 70) } catch { boundaryErrors.append(error) }
        }
        try state.requestHide(sourceTick: 70)
        _ = try surface.captureFrame(tick: 70, pixelSize: CGSize(width: 16, height: 16), samples: 1)
        XCTAssertFalse(state.hasPendingBoundary); XCTAssertEqual(state.progress, 0)
        _ = try surface.captureFrame(tick: 70, pixelSize: CGSize(width: 16, height: 16), samples: 1)
        XCTAssertEqual(callbacks, 2); XCTAssertEqual(state.progress, 0); XCTAssertTrue(boundaryErrors.isEmpty)
        try state.update(sourceTick: 71); XCTAssertEqual(state.progress, Float(1) / 140, accuracy: 1e-6)
        surface.shutdown(); XCTAssertNil(surface.didSubmitFrame)
    }

    @MainActor private final class Harness {
        let device: MTLDevice, renderer: SCNRenderer, queue: MTLCommandQueue, camera: SCNNode
        let size = 96
        private var tick = 0
        init(device: MTLDevice, scene: SCNScene) throws {
            self.device = device; queue = try XCTUnwrap(device.makeCommandQueue())
            renderer = SCNRenderer(device: device, options: nil)
            renderer.scene = scene; renderer.usesReverseZ = false; renderer.autoenablesDefaultLighting = false
            camera = SCNNode(); camera.camera = SCNCamera()
            camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 1.5
            camera.camera?.wantsHDR = false; camera.camera?.wantsExposureAdaptation = false
            camera.camera?.zNear = 0.1; camera.camera?.zFar = 50
            camera.position = SCNVector3(0, 0, 5)
            scene.rootNode.addChildNode(camera); renderer.pointOfView = camera
        }
        func render() throws -> [UInt8] {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb,
                width: size, height: size, mipmapped: false)
            descriptor.storageMode = .shared; descriptor.usage = [.renderTarget, .shaderRead]
            let color = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
            let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                width: size, height: size, mipmapped: false)
            depthDescriptor.storageMode = .private; depthDescriptor.usage = .renderTarget
            let depth = try XCTUnwrap(device.makeTexture(descriptor: depthDescriptor))
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = color; pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
            pass.depthAttachment.texture = depth; pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.storeAction = .store; pass.depthAttachment.clearDepth = 1
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            SCNTransaction.flush()
            renderer.render(atTime: Double(tick) / 60, viewport: CGRect(x: 0, y: 0, width: size, height: size),
                commandBuffer: command, passDescriptor: pass)
            tick += 1; command.commit(); command.waitUntilCompleted()
            XCTAssertEqual(command.status, .completed, String(describing: command.error))
            var bytes = [UInt8](repeating: 0, count: size * size * 4)
            bytes.withUnsafeMutableBytes {
                color.getBytes($0.baseAddress!, bytesPerRow: size * 4,
                    from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
            }
            return bytes
        }
        func pixel(_ bytes: [UInt8], world: SCNVector3) -> SIMD4<UInt8> {
            let projected = renderer.projectPoint(world)
            let x = min(size - 1, max(0, Int(projected.x)))
            let y = min(size - 1, max(0, size - 1 - Int(projected.y)))
            let offset = (y * size + x) * 4
            return SIMD4(bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
        }
    }
}
