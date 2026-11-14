import XCTest
import SceneKit
import UIKit
import Metal
import simd
@testable import ShiftReminder

/// Both standard and private fighter jobs stage the same small feedback pack.
/// Missing actual resources fail: a procedural flash cannot pass this suite.
@MainActor
final class DuelSourceEffectsTests: XCTestCase {
    func testFrozenImpactClockSkipsSamplingButPreservesNewContacts() throws {
        let root = SCNNode()
        let effects = DuelSourceEffects.preparationFixture(root: root)
        defer { effects.shutdown() }
        let contact = DuelSourceEffects.Contact(kind: .hit, position: SCNVector3Zero, direction: 1)
        effects.consumeStep(contacts: [contact], swings: [], animationTick: 1)
        XCTAssertEqual(effects.sampledFrameCount, 1)
        let visible = effects.activeParticleCount
        XCTAssertGreaterThan(visible, 0)
        for _ in 0..<60 { effects.consumeStep(contacts: [], swings: [], animationTick: 1) }
        XCTAssertEqual(effects.sampledFrameCount, 1)
        XCTAssertEqual(effects.activeParticleCount, visible)
        effects.consumeStep(contacts: [contact], swings: [], animationTick: 1)
        XCTAssertEqual(effects.sampledFrameCount, 2)
        XCTAssertEqual(effects.activeBurstCount, 2)
        XCTAssertEqual(effects.activeParticleCount, 2 * visible)
        effects.advance(to: 2)
        XCTAssertEqual(effects.sampledFrameCount, 3)
        effects.reset()
        effects.consumeStep(contacts: [contact], swings: [], animationTick: 1)
        XCTAssertEqual(effects.sampledFrameCount, 4)
        XCTAssertEqual(effects.activeBurstCount, 1)
    }

    func testPrewarmedImpactPoolReusesObjectsAndClearsRetiredState() throws {
        let root = SCNNode()
        let effects = DuelSourceEffects.preparationFixture(root: root)
        defer { effects.shutdown() }
        weak var released: SCNNode?
        // All Objective-C childNodes arrays used by the stress loop must drain,
        // not only the final lookup: they otherwise retain recycled pool slots.
        try autoreleasepool {
            let prepared = effects.preparationObjects().compactMap { $0 as? SCNGeometry }
            let identities = Set(prepared.map(ObjectIdentifier.init))
            XCTAssertEqual(identities.count, 512)
            var seenRoots = Set<ObjectIdentifier>()
            for tick in 0..<120 {
                effects.emit(kind: tick % 2 == 0 ? .hit : .block,
                             position: SCNVector3(Float(tick), 0, 0), direction: tick % 2 == 0 ? 1 : -1, tick: tick)
                let newest = try XCTUnwrap(root.childNodes.last)
                XCTAssertTrue(newest.childNodes.allSatisfy(\.isHidden), "Checkout must not show the previous owner's frame")
                seenRoots.insert(ObjectIdentifier(newest))
                effects.advance(to: tick + 1)
                XCTAssertLessThanOrEqual(effects.activeBurstCount, 8)
                for node in root.childNodes.flatMap(\.childNodes) {
                    XCTAssertTrue(identities.contains(ObjectIdentifier(try XCTUnwrap(node.geometry))))
                }
            }
            XCTAssertLessThanOrEqual(seenRoots.count, 16)
            effects.reset()
            XCTAssertTrue(root.childNodes.isEmpty)
            XCTAssertEqual(Set(effects.preparationObjects().compactMap { $0 as? SCNGeometry }.map(ObjectIdentifier.init)), identities)
            effects.emit(kind: .hit, position: SCNVector3Zero, direction: -1, tick: 0)
            effects.advance(to: 1)
            let live = try XCTUnwrap(root.childNodes.first)
            XCTAssertTrue(live.childNodes.allSatisfy { $0.scale.x < 0 })
            effects.emit(kind: .block, position: SCNVector3Zero, direction: 1, tick: 1)
            released = root.childNodes.last
            XCTAssertNotNil(released)
            effects.shutdown()
            XCTAssertEqual(effects.allocatedParticleCount, 0)
            SCNTransaction.flush()
        }
        XCTAssertNil(released, "Shutdown releases pooled nodes after inspection temporaries drain")
        XCTAssertTrue(root.childNodes.isEmpty)
        XCTAssertTrue(effects.preparationObjects().isEmpty)
    }

    func testActualHitAndBlockRenderFreezePauseAndRelease() throws {
        _ = try XCTUnwrap(DuelSourceEffects.manifestURL(), "Stage the verified original feedback pack")
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 1.4
        camera.camera?.zNear = 0.1; camera.camera?.zFar = 20
        camera.camera?.wantsHDR = false; camera.camera?.wantsExposureAdaptation = false
        camera.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()), options: nil)
        renderer.scene = scene; renderer.pointOfView = camera
        var effects: DuelSourceEffects? = try DuelSourceEffects(root: scene.rootNode)
        weak var weakEffects = effects
        defer { effects?.shutdown(); renderer.scene = nil; renderer.pointOfView = nil }
        XCTAssertEqual(effects?.allocatedParticleCount, 368, "Production loading prewarms both kinds before any contact or network preparation")
        XCTAssertEqual(effects?.sourceTextureCount, 9)
        XCTAssertEqual(effects?.sourceAudioCount, 29)
        let empty = try capture(renderer)

        effects?.consumeStep(contacts: [.init(kind: .hit, position: SCNVector3Zero, direction: 1)],
                             swings: [], animationTick: 1)
        XCTAssertEqual(effects?.emittedHits, 1)
        let hitRoot = try XCTUnwrap(scene.rootNode.childNodes.first { $0.name?.hasPrefix("duel.source-effect.hit.") == true })
        XCTAssertEqual(hitRoot.childNodes.count, 25)
        XCTAssertEqual(textureIdentities(hitRoot).count, 5)
        XCTAssertGreaterThan(effects?.activeParticleCount ?? 0, 0)
        let first = try capture(renderer, name: "source-hit-first-simulation-step")
        XCTAssertGreaterThan(changedPixels(empty.bytes, first.bytes), 30,
                             "Hit-stop must freeze a visible first-step spark, not an empty birth frame")
        let frozenState = state(hitRoot)
        effects?.advance(to: 1)
        XCTAssertEqual(state(hitRoot), frozenState)
        let repeated = try capture(renderer)
        XCTAssertLessThanOrEqual(maximumDelta(first.bytes, repeated.bytes), 1,
                                 "Repeated rendering at the same tick must not advance source particles")

        let previousSounds = effects?.playedSounds ?? 0
        effects?.playWhoosh(heavy: false, tick: 1)
        XCTAssertGreaterThan(effects?.playedSounds ?? 0, previousSounds, "The actual decoded source WAV must play")
        XCTAssertGreaterThan(effects?.playingAudioPlayerCount ?? 0, 0)
        effects?.setPaused(true)
        XCTAssertEqual(effects?.playingAudioPlayerCount, 0)
        XCTAssertGreaterThan(effects?.pausedAudioPlayerCount ?? 0, 0)
        effects?.advance(to: 100)
        effects?.consumeStep(contacts: [.init(kind: .block, position: SCNVector3Zero, direction: -1)],
                             swings: [.init()], animationTick: 100)
        XCTAssertEqual(state(hitRoot), frozenState)
        XCTAssertEqual(effects?.activeBurstCount, 1)
        XCTAssertEqual(effects?.emittedBlocks, 0)
        effects?.setPaused(false)
        XCTAssertEqual(effects?.pausedAudioPlayerCount, 0)
        effects?.advance(to: 4)
        XCTAssertNotEqual(state(hitRoot), frozenState)
        let hit = try capture(renderer, name: "source-hit-original-six-layers")
        XCTAssertGreaterThan(changedPixels(empty.bytes, hit.bytes), 100)
        effects?.advance(to: 60)
        XCTAssertEqual(effects?.activeBurstCount, 0)
        XCTAssertNil(hitRoot.parent)
        XCTAssertLessThanOrEqual(maximumDelta(empty.bytes, try capture(renderer).bytes), 1)

        effects?.consumeStep(contacts: [.init(kind: .block, position: SCNVector3Zero, direction: -1)],
                             swings: [], animationTick: 61)
        effects?.advance(to: 64)
        XCTAssertEqual(effects?.emittedBlocks, 1)
        let blockRoot = try XCTUnwrap(scene.rootNode.childNodes.first { $0.name?.hasPrefix("duel.source-effect.block.") == true })
        XCTAssertEqual(blockRoot.childNodes.count, 21)
        XCTAssertEqual(textureIdentities(blockRoot).count, 6)
        let block = try capture(renderer, name: "source-block-original-nine-layers")
        XCTAssertGreaterThan(changedPixels(empty.bytes, block.bytes), 100)
        XCTAssertGreaterThan(changedPixels(hit.bytes, block.bytes), 100,
                             "Block must use its own source layers, not the hit effect tinted another color")

        // The display callback may execute several simulation steps. Each
        // queue is consumed before another step overwrites it, including two
        // contacts in one step and events sharing a frozen animation clock.
        let twoHits = [DuelSourceEffects.Contact(kind: .hit, position: SCNVector3(-0.2, 0, 0), direction: 1, sound: .katana),
                       DuelSourceEffects.Contact(kind: .hit, position: SCNVector3(0.2, 0, 0), direction: -1, sound: .dualHammers)]
        let fistWhooshes = effects?.playedSoundCategories["whoosh", default: 0]
        effects?.consumeStep(contacts: twoHits, swings: [.init(sound: .katana), .init(sound: .dualHammers)], animationTick: 65)
        XCTAssertEqual(effects?.activeBurstCount, 3)
        XCTAssertEqual(effects?.emittedHits, 3)
        XCTAssertEqual(effects?.playedSoundCategories["katanaHit"], 1)
        XCTAssertEqual(effects?.playedSoundCategories["hammerHit"], 1)
        XCTAssertEqual(effects?.playedSoundCategories["katanaWhoosh"], 1)
        XCTAssertEqual(effects?.playedSoundCategories["whoosh", default: 0], fistWhooshes,
                       "Weapon swings must never fall back to the source fist whoosh")
        XCTAssertEqual(effects?.playedSoundCategories["heavyWhoosh", default: 0], 0)
        effects?.consumeStep(contacts: [twoHits[0]], swings: [], animationTick: 66)
        XCTAssertEqual(effects?.activeBurstCount, 4)
        effects?.consumeStep(contacts: [twoHits[1]], swings: [], animationTick: 66)
        XCTAssertEqual(effects?.activeBurstCount, 5)
        XCTAssertEqual(effects?.emittedHits, 5, "A shared visual tick must not reset or deduplicate queued contacts")
        let frozenBlock = state(blockRoot)
        effects?.consumeStep(contacts: [], swings: [], animationTick: 66)
        XCTAssertEqual(state(blockRoot), frozenBlock)
        effects?.consumeStep(contacts: [.init(kind: .block, position: SCNVector3Zero, direction: 1, sound: .katana),
                                       .init(kind: .block, position: SCNVector3Zero, direction: -1, sound: .dualHammers)],
                             swings: [], animationTick: 67)
        XCTAssertEqual(effects?.playedSoundCategories["katanaBlock"], 1)
        XCTAssertEqual(effects?.playedSoundCategories["hammerBlock"], 1)

        // Multiple contacts within one display callback remain separate. The
        // fixed cap bounds transient rendering and removes the oldest root.
        for _ in 0..<9 { effects?.emit(kind: .hit, position: SCNVector3Zero, direction: 1, tick: 67) }
        XCTAssertEqual(effects?.activeBurstCount, 8)
        XCTAssertNil(blockRoot.parent)
        effects?.setPaused(true)
        effects?.reset()
        XCTAssertEqual(effects?.activeBurstCount, 0)
        XCTAssertEqual(effects?.playingAudioPlayerCount, 0)
        XCTAssertEqual(effects?.pausedAudioPlayerCount, 0)
        XCTAssertEqual(effects?.emittedHits, 0)
        XCTAssertEqual(effects?.playedSoundCategories.count, 0)
        XCTAssertTrue(scene.rootNode.childNodes.allSatisfy { $0 === camera })
        effects?.setPaused(false)
        weak var closingRoot: SCNNode?
        // Drain SceneKit/Objective-C temporary references before checking
        // ownership, while keeping the scene and effects owner alive.
        autoreleasepool {
            effects?.emit(kind: .block, position: SCNVector3Zero, direction: 1, tick: 0)
            effects?.advance(to: 1)
            XCTAssertEqual(effects?.activeBurstCount, 1)
            closingRoot = scene.rootNode.childNodes.first { $0.name?.hasPrefix("duel.source-effect.") == true }
            XCTAssertNotNil(closingRoot)
            effects?.shutdown()
            SCNTransaction.flush()
        }
        XCTAssertNil(closingRoot, "A closed owner must release its last unrendered particle subtree")
        XCTAssertEqual(effects?.sourceTextureCount, 0)
        XCTAssertEqual(effects?.sourceAudioCount, 0)
        effects?.emit(kind: .hit, position: SCNVector3Zero, direction: 1, tick: 2)
        effects?.playWhoosh(heavy: true, tick: 2)
        XCTAssertEqual(effects?.activeBurstCount, 0)
        XCTAssertTrue(scene.rootNode.childNodes.allSatisfy { $0 === camera })
        effects = nil
        XCTAssertNil(weakEffects, "Scene nodes and audio players must not retain a closed effect owner")
    }

    func testOriginalBlockSignedScalesStayVisibleInBothDirections() throws {
        let url = try XCTUnwrap(DuelSourceEffects.manifestURL())
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let definitions = try XCTUnwrap(document["effects"] as? [String: [String: Any]])
        let tracks = try XCTUnwrap(definitions["block"]?["tracks"] as? [[String: Any]])
        XCTAssertEqual(tracks.count, 21)
        for direction in [-1, 1] {
            let root = SCNNode(), effects = try DuelSourceEffects(root: root)
            defer { effects.shutdown() }
            effects.emit(kind: .block, position: SCNVector3Zero, direction: direction, tick: 0)
            effects.advance(to: 3)
            let burst = try XCTUnwrap(root.childNodes.first)
            XCTAssertEqual(burst.childNodes.count, tracks.count)
            for track in tracks {
                let name = try XCTUnwrap(track["name"] as? String)
                let frames = try XCTUnwrap(track["frames"] as? [[Double]])
                // At 3/60 seconds the original 240 Hz export supplies sample
                // 12 directly; this expected value does not use the adapter.
                XCTAssertGreaterThan(frames.count, 12)
                let source = frames[12]
                XCTAssertEqual(source[0], 0.05, accuracy: 0.000001)
                XCTAssertLessThan(source[4], 0, "The actual source prefab reflects X")
                XCTAssertGreaterThan(source[5], 0)
                let node = try XCTUnwrap(burst.childNode(withName: name, recursively: false))
                XCTAssertFalse(node.isHidden, "A source reflection must not hide the block particle")
                XCTAssertEqual(node.scale.x, Float(source[4]) * 0.01 * Float(direction), accuracy: 0.00001)
                XCTAssertEqual(node.scale.y, Float(source[5]) * 0.01, accuracy: 0.00001)
            }
        }
    }

    func testAlteredSourceManifestOrTextureCannotFallBackToBundledArtwork() throws {
        let manifestURL = try XCTUnwrap(DuelSourceEffects.manifestURL())
        let original = try Data(contentsOf: manifestURL)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent(DuelSourceEffects.manifestName)
        var changed = original; changed[0] ^= 1
        try changed.write(to: destination)
        XCTAssertThrowsError(try DuelSourceEffects(root: SCNNode(), directory: folder)) { error in
            guard case DuelSourceEffects.Failure.manifest = error else { return XCTFail("Unexpected integrity error: \(error)") }
        }
        try original.write(to: destination)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        let files = try XCTUnwrap(document["files"] as? [[String: Any]])
        let name = try XCTUnwrap(files.first?["name"] as? String)
        var texture = try Data(contentsOf: manifestURL.deletingLastPathComponent().appendingPathComponent(name))
        texture[texture.count - 1] ^= 1
        try texture.write(to: folder.appendingPathComponent(name))
        XCTAssertThrowsError(try DuelSourceEffects(root: SCNNode(), directory: folder)) { error in
            guard case DuelSourceEffects.Failure.resource(let actual) = error else { return XCTFail("Unexpected resource error: \(error)") }
            XCTAssertEqual(actual, name)
        }
    }

    private func textureIdentities(_ root: SCNNode) -> Set<ObjectIdentifier> {
        Set(root.childNodes.compactMap { ($0.geometry?.firstMaterial?.diffuse.contents as? UIImage).map(ObjectIdentifier.init) })
    }

    private func state(_ root: SCNNode) -> [String: [Float]] {
        Dictionary(uniqueKeysWithValues: root.childNodes.map { node in
            let matrix = node.simdTransform
            let color = (node.geometry?.firstMaterial?.value(forKey: "sourceFXColor") as? NSValue)?.scnVector4Value ?? SCNVector4(0, 0, 0, 0)
            return (node.name ?? "", [matrix.columns.0.x, matrix.columns.0.y, matrix.columns.1.x, matrix.columns.1.y,
                                      matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z,
                                      color.x, color.y, color.z, color.w, node.isHidden ? 1 : 0])
        })
    }

    private func capture(_ renderer: SCNRenderer, name: String? = nil) throws -> (bytes: [UInt8], image: UIImage) {
        let side = 256
        SCNTransaction.flush()
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: CGFloat(side), height: CGFloat(side)), antialiasingMode: .multisampling2X)
        if let name {
            let attachment = XCTAttachment(image: image)
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        try bytes.withUnsafeMutableBytes { pointer in
            let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try XCTUnwrap(CGContext(data: pointer.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)))
        }
        return (bytes, image)
    }

    private func changedPixels(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return 0 }
        return stride(from: 0, to: a.count, by: 4).filter { i in
            (0..<3).contains { abs(Int(a[i + $0]) - Int(b[i + $0])) > 4 }
        }.count
    }

    private func maximumDelta(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return 255 }
        return zip(a, b).map { pair in abs(Int(pair.0) - Int(pair.1)) }.max() ?? 0
    }
}
