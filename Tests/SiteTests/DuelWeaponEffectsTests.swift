import XCTest
import SceneKit
import UIKit
import Metal
@testable import ShiftReminder

/// This suite renders the actual hash-bound source textures. No skip and no
/// generated artwork can substitute for a missing private feedback pack.
@MainActor
final class DuelWeaponEffectsTests: XCTestCase {
    /// A focused regression for the endpoint-ribbon adaptation. Actual source
    /// alpha/curves are required, but poses/camera and sampler substitutions are
    /// test inputs, not recovered source mesh UVs or production visual approval.
    func testOrdinaryRibbonsUseSourceAlphaWithoutMeshAtlasAndPreserveAge() throws {
        let manifestURL = try XCTUnwrap(DuelWeaponEffects.manifestURL(), "Stage original SF3WE resources")
        let definition = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        let profiles = try XCTUnwrap(definition["profiles"] as? [String: [String: Any]])
        func lifetime(_ family: DuelWeaponEffects.Family) throws -> Double {
            let profile = try XCTUnwrap(profiles[family.rawValue])
            let layers = try XCTUnwrap(profile["swing"] as? [[String: Any]])
            return try XCTUnwrap(layers.first?["lifetime"] as? NSNumber).doubleValue
        }
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.035, green: 0.045, blue: 0.065, alpha: 1)
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 2
        camera.camera?.zNear = 0.1; camera.camera?.zFar = 20
        camera.camera?.wantsHDR = false; camera.camera?.wantsExposureAdaptation = false
        camera.position = SCNVector3(0, 0, 4); scene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()), options: nil)
        renderer.scene = scene; renderer.pointOfView = camera
        let effects = try DuelWeaponEffects(root: scene.rootNode)
        defer { effects.shutdown(); renderer.scene = nil; renderer.pointOfView = nil }
        let container = try XCTUnwrap(scene.rootNode.childNode(withName: "duel.weapon-effects", recursively: false))
        let ordinaryTemplates = effects.preparationObjects().compactMap { ($0 as? SCNGeometry)?.firstMaterial }
            .filter { $0.shaderModifiers?[.fragment]?.contains("uniform vec4 sourceTrailAges;") == true }
        XCTAssertEqual(ordinaryTemplates.count, 2)
        let empty = try pixels(renderer, atTime: 0)
        for family in [DuelWeaponEffects.Family.katana, .dualHammers] {
            effects.reset()
            let sourceLifetime = try lifetime(family)
            effects.consumeStep(poses: [pose(tick: 0, family: family, active: false)], animationTick: 0)
            effects.consumeStep(poses: [pose(tick: 1, family: family)], animationTick: 1)
            let expectedSlots = family == .katana ? [0] : [0, 1]
            XCTAssertEqual(effects.trailDiagnostics.emitters.map(\.slot), expectedSlots)
            let firstLayers = container.childNodes.flatMap(\.childNodes)
            XCTAssertEqual(firstLayers.count, expectedSlots.count)
            for layer in firstLayers {
                try assertOrdinaryStrip(layer, lifetime: sourceLifetime, oldestTicks: 1, newestTicks: 0)
            }
            if family == .katana {
                let first = try pixels(renderer, atTime: 1, name: "ribbon-katana-first-active-step")
                XCTAssertGreaterThan(changed(empty, first), 20, "The first one-tick strip uses the alpha domain without aging it by a full lifetime")
            }
            for tick in 2...5 {
                effects.consumeStep(poses: [pose(tick: tick, family: family)], animationTick: tick)
            }
            let layers = container.childNodes.flatMap(\.childNodes)
            XCTAssertEqual(layers.count, expectedSlots.count)
            // The two authenticated families may have different lifetimes.
            // Derive which known input ticks are still alive rather than
            // assuming a six-sample minimum in either source profile.
            let retainedAtFive = (0...5).filter { Double(5 - $0) / 60 < sourceLifetime }
            let oldestAtFive = try XCTUnwrap(retainedAtFive.first)
            for layer in layers {
                try assertOrdinaryStrip(layer, lifetime: sourceLifetime, oldestTicks: 5 - oldestAtFive, newestTicks: 0)
            }
            let label = family == .katana ? "ribbon-katana-source-alpha" : "ribbon-double-hammer-source-alpha"
            let sourcePixels = try pixels(renderer, atTime: 5, name: label)
            XCTAssertGreaterThan(changed(empty, sourcePixels), 80)
            let frozen = geometryState(container)
            let count = effects.emittedSampleCount
            effects.consumeStep(poses: [pose(tick: 20, family: family)], animationTick: 5)
            XCTAssertEqual(geometryState(container), frozen, "The age uniforms freeze with geometry and shader time")
            XCTAssertEqual(effects.emittedSampleCount, count)
            XCTAssertLessThanOrEqual(maximumDelta(sourcePixels, try pixels(renderer, atTime: 105)), 1)

            // Deliberately unrelated atlas colors must not appear on a history
            // strip that has no source equipment-mesh UVs. Conversely, changing
            // the verified alpha sampler to black must remove every ribbon.
            let materials = try layers.map { try XCTUnwrap($0.geometry?.firstMaterial) }
            if materials.count == 2 {
                XCTAssertFalse(materials[0] === materials[1], "Each hammer owns a distinct live material")
                let firstAges = try XCTUnwrap(materials[0].value(forKey: "sourceTrailAges") as? NSValue)
                let secondAges = try XCTUnwrap(materials[1].value(forKey: "sourceTrailAges") as? NSValue)
                materials[0].setValue(NSValue(scnVector4: SCNVector4(0.5, 0.25, 0, 0)), forKey: "sourceTrailAges")
                XCTAssertEqual(materials[1].value(forKey: "sourceTrailAges") as? NSValue, secondAges)
                materials[0].setValue(firstAges, forKey: "sourceTrailAges")
            }
            try assertAtlasIndependenceAndAlphaControl(materials, renderer: renderer,
                                                       expected: sourcePixels, empty: empty)
            XCTAssertLessThanOrEqual(maximumDelta(sourcePixels, try pixels(renderer, atTime: 405)), 1,
                                     "Sampler substitutions are restored before any further age/lifecycle check")
            effects.consumeStep(poses: [], animationTick: 6)
            XCTAssertTrue(effects.trailDiagnostics.emitters.isEmpty)
            let retainedAtSix = (0...5).filter { Double(6 - $0) / 60 < sourceLifetime }
            for layer in layers {
                if retainedAtSix.count >= 2, let oldest = retainedAtSix.first {
                    try assertOrdinaryStrip(layer, lifetime: sourceLifetime, oldestTicks: 6 - oldest, newestTicks: 1)
                } else if retainedAtSix.count == 1 {
                    XCTAssertNil(layer.geometry, "One unexpired point retains its owner but cannot draw a segment")
                }
            }
            XCTAssertEqual(effects.retainedTrailCount, retainedAtSix.isEmpty ? 0 : expectedSlots.count,
                           "Stopping emission retains exactly the unexpired source history")
            effects.consumeStep(poses: [], animationTick: 5 + Int(ceil(sourceLifetime * 60)))
            XCTAssertEqual(effects.retainedTrailCount, 0)
            XCTAssertTrue(container.childNodes.isEmpty)
        }
        for material in ordinaryTemplates {
            let ages = try XCTUnwrap(material.value(forKey: "sourceTrailAges") as? NSValue).scnVector4Value
            XCTAssertEqual(ages.x, 1); XCTAssertEqual(ages.y, 0)
            XCTAssertTrue([ages.x, ages.y, ages.z, ages.w].allSatisfy(\.isFinite), "Template ages are finite and never mutated by a live ribbon")
        }
        try assertShaderUsesAgeUniforms(scene: scene, renderer: renderer, empty: empty)
        try assertPartialCoverageCompositesOverBackground(scene: scene, renderer: renderer)
    }

    func testSourceWeaponTrailsRenderAtRealEndpointsAndFreezeAndRelease() throws {
        _ = try XCTUnwrap(DuelWeaponEffects.manifestURL(), "Stage original SF3WE resources")
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.035, green: 0.045, blue: 0.065, alpha: 1)
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 2
        camera.camera?.zNear = 0.1; camera.camera?.zFar = 20
        camera.camera?.wantsHDR = false; camera.camera?.wantsExposureAdaptation = false
        camera.position = SCNVector3(0, 0, 4); scene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()), options: nil)
        renderer.scene = scene; renderer.pointOfView = camera
        var effects: DuelWeaponEffects? = try DuelWeaponEffects(root: scene.rootNode)
        weak var weakEffects = effects
        defer { effects?.shutdown(); renderer.scene = nil; renderer.pointOfView = nil }
        XCTAssertEqual(effects?.sourceTextureCount, 11)
        let empty = try pixels(renderer, atTime: 0)

        effects?.consumeStep(poses: [pose(tick: 0, family: .katana, active: false)], animationTick: 0)
        XCTAssertEqual(effects?.retainedTrailCount, 0)
        effects?.consumeStep(poses: [pose(tick: 1, family: .katana)], animationTick: 1)
        XCTAssertEqual(effects?.renderedVertexCount, 4, "The prior real idle pose must seed the first active sweep")
        let first = try pixels(renderer, atTime: 1, name: "source-katana-first-active-step")
        XCTAssertGreaterThan(changed(empty, first), 20, "First contact hit-stop must freeze a visible weapon sweep")
        for tick in 2...5 { effects?.consumeStep(poses: [pose(tick: tick, family: .katana)], animationTick: tick) }
        XCTAssertEqual(effects?.retainedTrailCount, 1)
        let katana = try pixels(renderer, atTime: 5, name: "source-katana-original-material")
        XCTAssertGreaterThan(changed(empty, katana), 80)
        let container = try XCTUnwrap(scene.rootNode.childNode(withName: "duel.weapon-effects", recursively: false))
        let frozen = geometryState(container)
        let count = effects?.emittedSampleCount
        // Changing wall time and supplying another pose at the same visual
        // tick cannot scroll noise or add interpolated/extra trail vertices.
        effects?.consumeStep(poses: [pose(tick: 20, family: .katana)], animationTick: 5)
        XCTAssertEqual(geometryState(container), frozen)
        XCTAssertEqual(effects?.emittedSampleCount, count)
        XCTAssertLessThanOrEqual(maximumDelta(katana, try pixels(renderer, atTime: 105)), 1)
        effects?.setPaused(true)
        effects?.consumeStep(poses: [], animationTick: 90)
        XCTAssertEqual(geometryState(container), frozen)
        effects?.setPaused(false)
        effects?.consumeStep(poses: [pose(tick: 6, family: .katana)], animationTick: 6)
        XCTAssertNotEqual(geometryState(container), frozen)
        effects?.consumeStep(poses: [], animationTick: 60)
        XCTAssertEqual(effects?.retainedTrailCount, 0)
        XCTAssertEqual(effects?.renderedVertexCount, 0)
        XCTAssertTrue(container.childNodes.isEmpty)

        effects?.reset()
        for tick in 0...5 {
            effects?.consumeStep(poses: [pose(tick: tick, family: .dualHammers, active: tick > 0)], animationTick: tick)
        }
        XCTAssertEqual(effects?.retainedTrailCount, 2, "Each physical hammer needs an independent history")
        let hammers = try pixels(renderer, atTime: 106, name: "source-double-hammer-original-material")
        XCTAssertGreaterThan(changed(empty, hammers), 80)
        XCTAssertGreaterThan(changed(katana, hammers), 80)

        effects?.reset()
        for tick in 0...25 {
            effects?.consumeStep(poses: [pose(tick: tick, family: .katana, active: tick > 0, shadow: true)], animationTick: tick)
        }
        XCTAssertEqual(container.childNodes.first?.childNodes.count, 2, "Katana dash has distinct source glow and scrolling noise layers")
        let dash = try pixels(renderer, atTime: 107, name: "source-katana-dash-two-materials")
        XCTAssertGreaterThan(changed(empty, dash), 80)
        let frozenDash = geometryState(container)
        effects?.consumeStep(poses: [pose(tick: 26, family: .katana, shadow: true)], animationTick: 25)
        XCTAssertEqual(geometryState(container), frozenDash)
        XCTAssertLessThanOrEqual(maximumDelta(dash, try pixels(renderer, atTime: 307)), 1,
                                 "Shadow shader noise must use simulation time, never renderer wall time")
        effects?.consumeStep(poses: [], animationTick: 90)
        XCTAssertEqual(effects?.retainedTrailCount, 0)

        effects?.reset()
        for tick in 0...6 {
            effects?.consumeStep(poses: [pose(tick: tick, family: .dualHammers, active: tick > 0, shadow: true)], animationTick: tick)
        }
        let shadowHammers = try pixels(renderer, atTime: 308, name: "source-hammer-smooth-trail-material")
        XCTAssertGreaterThan(changed(empty, shadowHammers), 20)
        XCTAssertGreaterThan(changed(hammers, shadowHammers), 30)

        // Rapid action changes stay bounded and never join two unrelated
        // motions into one long strip across an input transition.
        for tick in 7...30 {
            effects?.consumeStep(poses: [pose(tick: tick, family: .katana, shadow: true, action: "action.\(tick)")], animationTick: tick)
        }
        XCTAssertLessThanOrEqual(effects?.retainedTrailCount ?? 99, 16)
        effects?.setPaused(true); effects?.reset()
        XCTAssertEqual(effects?.emittedSampleCount, 0)
        XCTAssertTrue(container.childNodes.isEmpty)
        effects?.setPaused(false)
        weak var finalRoot: SCNNode?
        // Objective-C childNodes snapshots and SceneKit transactions can
        // retain temporary nodes until the autorelease pool drains. Keep the
        // effect owner and container alive while testing their final subtree.
        autoreleasepool {
            effects?.consumeStep(poses: [pose(tick: 0, family: .katana, active: false)], animationTick: 0)
            effects?.consumeStep(poses: [pose(tick: 1, family: .katana)], animationTick: 1)
            finalRoot = container.childNodes.first
            XCTAssertNotNil(finalRoot)
            effects?.shutdown()
            SCNTransaction.flush()
            XCTAssertTrue(container.childNodes.isEmpty)
        }
        XCTAssertNil(finalRoot, "Closing must release an unrendered final trail subtree")
        XCTAssertNil(container.parent)
        XCTAssertEqual(effects?.sourceTextureCount, 0)
        effects?.consumeStep(poses: [pose(tick: 2, family: .katana)], animationTick: 2)
        XCTAssertEqual(effects?.retainedTrailCount, 0)
        effects = nil; XCTAssertNil(weakEffects)
    }

    func testWeaponTextureIntegrityFailureCannotUseAnotherBundleCopy() throws {
        let source = try XCTUnwrap(DuelWeaponEffects.manifestURL())
        let data = try Data(contentsOf: source)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        try data.write(to: folder.appendingPathComponent(DuelWeaponEffects.manifestName))
        let definition = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let records = try XCTUnwrap(definition["files"] as? [[String: Any]])
        let name = try XCTUnwrap(records.first?["name"] as? String)
        var bytes = try Data(contentsOf: source.deletingLastPathComponent().appendingPathComponent(name))
        bytes[bytes.count - 1] ^= 1; try bytes.write(to: folder.appendingPathComponent(name))
        let root = SCNNode()
        XCTAssertThrowsError(try DuelWeaponEffects(root: root, directory: folder)) { error in
            guard case DuelWeaponEffects.Failure.resource(let file) = error else { return XCTFail("Unexpected integrity error: \(error)") }
            XCTAssertEqual(file, name)
        }
        XCTAssertTrue(root.childNodes.isEmpty, "Failed loading must not attach a partial renderer")
    }

    private func pose(tick: Int, family: DuelWeaponEffects.Family, active: Bool = true,
                      shadow: Bool = false, action: String = "attack.1") -> DuelWeaponEffects.Pose {
        let angle = Double(tick) * 0.23 - 0.8
        func endpoint(slot: Int, center: Float, offset: Double) -> DuelWeaponEffects.Endpoints {
            let length: Float = family == .katana ? 1.15 : 0.7
            let base = SCNVector3(center, -0.35, 0)
            return .init(slot: slot, base: base, tip: SCNVector3(base.x + Float(cos(angle + offset)) * length,
                                                               base.y + Float(sin(angle + offset)) * length, 0))
        }
        let endpoints = family == .katana ? [endpoint(slot: 0, center: -0.35, offset: 0)] :
            [endpoint(slot: 0, center: -0.65, offset: 0), endpoint(slot: 1, center: 0.65, offset: .pi)]
        return .init(fighterID: 0, family: family, motionID: active ? action : nil, isShadow: shadow, endpoints: endpoints)
    }

    private func geometryState(_ root: SCNNode) -> [Data] {
        root.childNodes.flatMap { trail in
            trail.childNodes.flatMap { node -> [Data] in
                guard let geometry = node.geometry else { return [] }
                let time = (geometry.firstMaterial?.value(forKey: "sourceTime") as? NSNumber)?.doubleValue ?? -1
                var uniforms = [Data(String(time).utf8)]
                if let material = geometry.firstMaterial,
                   material.shaderModifiers?[.fragment]?.contains("uniform vec4 sourceTrailAges;") == true,
                   let ages = (material.value(forKey: "sourceTrailAges") as? NSValue)?.scnVector4Value {
                    uniforms.append(Data("\(ages.x),\(ages.y),\(ages.z),\(ages.w)".utf8))
                }
                return geometry.sources.map(\.data) + geometry.elements.map(\.data) + uniforms
            }
        }
    }

    private func assertOrdinaryStrip(_ layer: SCNNode, lifetime: Double, oldestTicks: Int, newestTicks: Int) throws {
        let geometry = try XCTUnwrap(layer.geometry)
        let uv = try XCTUnwrap(geometry.sources(for: .texcoord).first)
        XCTAssertTrue(uv.usesFloatComponents)
        XCTAssertEqual(uv.componentsPerVector, 2)
        XCTAssertGreaterThanOrEqual(uv.vectorCount, 4)
        func component(_ index: Int, _ axis: Int) throws -> Double {
            let offset = uv.dataOffset + index * uv.dataStride + axis * uv.bytesPerComponent
            guard offset >= 0, offset + uv.bytesPerComponent <= uv.data.count else {
                XCTFail("UV source exceeds data bounds"); return .nan
            }
            if uv.bytesPerComponent == MemoryLayout<Float>.size {
                return uv.data.withUnsafeBytes { Double($0.loadUnaligned(fromByteOffset: offset, as: Float.self)) }
            }
            guard uv.bytesPerComponent == MemoryLayout<Double>.size else {
                XCTFail("Unsupported UV component width"); return .nan
            }
            return uv.data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Double.self) }
        }
        XCTAssertEqual(try component(0, 0), 0, accuracy: 0.000001)
        XCTAssertEqual(try component(uv.vectorCount - 1, 0), 1, accuracy: 0.000001)
        for index in stride(from: 0, to: uv.vectorCount, by: 2) {
            XCTAssertEqual(try component(index, 0), try component(index + 1, 0), accuracy: 0.000001)
            XCTAssertEqual(try component(index, 1), 0, accuracy: 0.000001)
            XCTAssertEqual(try component(index + 1, 1), 1, accuracy: 0.000001)
            if index > 0 { XCTAssertGreaterThan(try component(index, 0), try component(index - 2, 0)) }
        }
        let material = try XCTUnwrap(geometry.firstMaterial)
        let ages = try XCTUnwrap(material.value(forKey: "sourceTrailAges") as? NSValue).scnVector4Value
        XCTAssertEqual(Double(ages.x) * lifetime * 60, Double(oldestTicks), accuracy: 0.00001,
                       "Oldest vertex age is elapsed simulation ticks, independent of the full alpha UV span")
        XCTAssertEqual(Double(ages.y) * lifetime * 60, Double(newestTicks), accuracy: 0.00001)
    }

    private func assertAtlasIndependenceAndAlphaControl(_ materials: [SCNMaterial], renderer: SCNRenderer,
                                                      expected: [UInt8], empty: [UInt8]) throws {
        var original: [(SCNMaterialProperty, Any?)] = []
        var remembered: Set<ObjectIdentifier> = []
        func remember(_ property: SCNMaterialProperty) {
            // Material copies may share custom properties. Save each object's
            // first value, never a test replacement observed by the second hammer.
            if remembered.insert(ObjectIdentifier(property)).inserted {
                original.append((property, property.contents))
            }
        }
        defer { for (property, contents) in original { property.contents = contents } }
        func solid(_ color: UIColor) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }
        }
        for material in materials {
            let main = try XCTUnwrap(material.value(forKey: "sourceMain") as? SCNMaterialProperty)
            let mask = try XCTUnwrap(material.value(forKey: "sourceMask") as? SCNMaterialProperty)
            remember(main); remember(mask)
            main.contents = solid(.magenta); mask.contents = solid(.white)
        }
        XCTAssertLessThanOrEqual(maximumDelta(expected, try pixels(renderer, atTime: 205)), 1,
                                 "Equipment atlases cannot color a ribbon lacking equipment-mesh UVs")
        for material in materials {
            let alpha = try XCTUnwrap(material.value(forKey: "sourceAlpha") as? SCNMaterialProperty)
            remember(alpha); alpha.contents = solid(.black)
        }
        XCTAssertLessThanOrEqual(maximumDelta(empty, try pixels(renderer, atTime: 305)), 1,
                                 "The authenticated sourceAlpha role still controls all ribbon coverage")
    }

    private func assertShaderUsesAgeUniforms(scene: SCNScene, renderer: SCNRenderer, empty: [UInt8]) throws {
        // This isolated negative control uses the existing explicit DEBUG
        // fixture: constant white alpha texture, alpha curve 1 at birth / 0 at
        // death. It is not a replacement for the three source-image attachments.
        let fixtureRoot = SCNNode(); scene.rootNode.addChildNode(fixtureRoot)
        let fixture = DuelWeaponEffects.preparationFixture(root: fixtureRoot)
        defer { fixture.shutdown(); fixtureRoot.removeFromParentNode() }
        fixture.consumeStep(poses: [pose(tick: 0, family: .katana, active: false)], animationTick: 0)
        fixture.consumeStep(poses: [pose(tick: 1, family: .katana)], animationTick: 1)
        let container = try XCTUnwrap(fixtureRoot.childNode(withName: "duel.weapon-effects", recursively: false))
        let geometry = try XCTUnwrap(container.childNodes.first?.childNodes.first?.geometry)
        let material = try XCTUnwrap(geometry.firstMaterial)
        let vertices = geometry.sources.map(\.data) + geometry.elements.map(\.data)
        material.setValue(NSValue(scnVector4: SCNVector4(0, 0, 0, 0)), forKey: "sourceTrailAges")
        XCTAssertGreaterThan(changed(empty, try pixels(renderer, atTime: 505)), 20)
        material.setValue(NSValue(scnVector4: SCNVector4(1, 1, 0, 0)), forKey: "sourceTrailAges")
        XCTAssertLessThanOrEqual(maximumDelta(empty, try pixels(renderer, atTime: 605)), 1,
                                 "The GPU must use elapsed-age uniforms, not infer age from stretched spatial UVs")
        XCTAssertEqual(geometry.sources.map(\.data) + geometry.elements.map(\.data), vertices,
                       "The single-variable age probe leaves geometry and alpha UVs fixed")
    }
    private func assertPartialCoverageCompositesOverBackground(scene: SCNScene, renderer: SCNRenderer) throws {
        // One tick creates nonoverlapping quads. Use a known white sampler and
        // fixed birth age, changing coverage only. A straight-white fragment
        // incorrectly passes a "some pixels changed" test but fails both zero
        // coverage and the linear-light quarter/half compositing equations.
        let savedBackground = scene.background.contents
        defer { scene.background.contents = savedBackground }
        for background in [UIColor.black, UIColor(red: 0.08, green: 0.22, blue: 0.48, alpha: 1)] {
            scene.background.contents = background
            for family in [DuelWeaponEffects.Family.katana, .dualHammers] {
                let root = SCNNode(); scene.rootNode.addChildNode(root)
                let fixture = DuelWeaponEffects.preparationFixture(root: root)
                defer { fixture.shutdown(); root.removeFromParentNode() }
                let empty = try pixels(renderer, atTime: 701)
                fixture.consumeStep(poses: [pose(tick: 0, family: family, active: false)], animationTick: 0)
                fixture.consumeStep(poses: [pose(tick: 1, family: family)], animationTick: 1)
                let container = try XCTUnwrap(root.childNode(withName: "duel.weapon-effects", recursively: false))
                let materials = container.childNodes.flatMap(\.childNodes).compactMap { $0.geometry?.firstMaterial }
                XCTAssertEqual(materials.count, family == .katana ? 1 : 2)
                for material in materials {
                    material.setValue(NSValue(scnVector4: SCNVector4(0, 0, 0, 0)), forKey: "sourceTrailAges")
                }
                func coverage(_ value: Double) throws -> [UInt8] {
                    for material in materials { material.setValue(NSNumber(value: value), forKey: "presentationOpacity") }
                    return try pixels(renderer, atTime: 702)
                }
                let zero = try coverage(0), full = try coverage(1)
                XCTAssertLessThanOrEqual(maximumDelta(empty, zero), 1, "Zero coverage must leave the background unchanged")
                let interior = stride(from: 0, to: full.count, by: 4).filter {
                    full[$0] > 252 && full[$0 + 1] > 252 && full[$0 + 2] > 252
                }
                XCTAssertGreaterThan(interior.count, 20, "The full-coverage control must actually draw opaque interiors")
                func linear(_ byte: UInt8) -> Double {
                    let c = Double(byte) / 255
                    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
                }
                for alpha in [0.25, 0.5] {
                    let partial = try coverage(alpha)
                    var maximumError: Double = 0
                    for offset in interior {
                        for channel in 0..<3 {
                            let sample = offset + channel
                            let observed = linear(partial[sample])
                            let foreground = linear(full[sample]) * alpha
                            let background = linear(zero[sample]) * (1 - alpha)
                            maximumError = max(maximumError, abs(observed - foreground - background))
                        }
                    }
                    XCTAssertLessThan(maximumError, 0.035,
                                      "Partial coverage must blend with the background once, without opaque white or double attenuation")
                }
            }
        }
    }

    private func pixels(_ renderer: SCNRenderer, atTime: Double, name: String? = nil) throws -> [UInt8] {
        SCNTransaction.flush()
        let side = 256
        let image = renderer.snapshot(atTime: atTime, with: CGSize(width: CGFloat(side), height: CGFloat(side)), antialiasingMode: .multisampling2X)
        if let name { let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment) }
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)))
        }
        return bytes
    }
    private func changed(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return 0 }
        return stride(from: 0, to: a.count, by: 4).filter { i in (0..<3).contains { abs(Int(a[i + $0]) - Int(b[i + $0])) > 4 } }.count
    }
    private func maximumDelta(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return 255 }
        return zip(a, b).map { abs(Int($0.0) - Int($0.1)) }.max() ?? 0
    }
}
