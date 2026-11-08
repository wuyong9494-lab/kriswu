import XCTest
import CryptoKit
import SceneKit
import simd
@testable import ShiftReminder

/// Explicit private-asset review only. These source-rig clips are not the
/// current gameplay profile, so successful loading cannot certify combat timing.
@MainActor
final class DuelOriginalRigAssetTests: XCTestCase {
    private let identities: [(String, Int, String)] = [
        ("Sun", 5_985_528, "b38d30c4e3afd3bc94b9e62ed40964e8d6fe70548a0f29576dfe07665a2451df"),
        ("Liu", 5_351_896, "16381ae1b4d3a8c291ceb883a9bd83474655d90d8e63dcaf1296344a3e3f40d5")
    ]
    private let clips: Set<String> = [
        "Idle", "Enter", "Walk", "BackStep", "ForwardHop", "BackwardHop", "Guard", "HighGuard",
        "Dodge", "Jump", "Jab", "Cross", "ComboFinish", "Heavy", "Uppercut", "LowPunch",
        "SpinStart", "SpinStrike", "SpinRecover", "Hit", "Knockdown", "GetUp", "Victory",
        "BackThrowActive", "BackThrowPassive", "TPose"
    ]

    private func models() throws -> [GLTFModel] {
        try identities.map { name, size, digest in
            let resource = name + "_OriginalRig_ActionSet"
            let url = try XCTUnwrap(Bundle.main.url(forResource: resource, withExtension: "glb") ??
                Bundle.main.url(forResource: resource, withExtension: "glb", subdirectory: "FighterPrivate"),
                "Stage the approved real original-rig model; no fallback is accepted")
            let bytes = try Data(contentsOf: url)
            XCTAssertEqual(bytes.count, size)
            XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), digest)
            let model = try GLTFModel(url: url, maxTexture: 1024, physicallyBased: true)
            XCTAssertTrue(model.hasSkinning)
            XCTAssertEqual(Set(model.clips.keys), clips)
            for bone in ["pelvis", "head", "neck", "hand_l", "hand_r", "foot_l", "foot_r", "forearm_twist_l", "forearm_twist_r"] {
                XCTAssertNotNil(model.node(named: bone), "Missing original skeleton node: \(bone)")
            }
            XCTAssertNotNil(model.node(named: name + "_Personal_Head"))
            return model
        }
    }

    func testEveryOriginalClipHasFiniteIndependentNativePoses() throws {
        for model in try models() {
            let first = model.instantiate(), second = model.instantiate()
            let untouched = second.nodes.map(\.simdTransform)
            for name in clips.sorted() {
                let clip = try XCTUnwrap(model.clips[name])
                let start = clip.channels.compactMap { $0.times.first }.min() ?? 0
                let frameCount = max(1, Int(((clip.duration - start) * 30).rounded()) + 1)
                var pose = model.restPose
                for frame in 0..<frameCount {
                    pose.reset(from: model.restPose)
                    clip.sample(at: min(clip.duration, start + Float(frame) / 30), into: &pose)
                    for index in model.animated { first.nodes[index].simdTransform = pose.transform(index) }
                    for node in first.nodes {
                        let p = node.simdWorldPosition
                        XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.z.isFinite, name)
                        XCTAssertLessThan(simd_length(p), 5, "Native source-rig joint escaped bounds: \(name)")
                    }
                }
            }
            XCTAssertEqual(second.nodes.map(\.simdTransform), untouched)
        }
    }

    func testRenderBothOriginalRigsWithTheirPersonalHeads() throws {
        let models = try models(), scene = SCNScene()
        let instances = models.enumerated().map { index, model in
            let instance = model.instantiate()
            instance.root.position.x = index == 0 ? -1.05 : 1.05
            instance.root.eulerAngles.y = .pi + (index == 0 ? 0.2 : -0.2)
            scene.rootNode.addChildNode(instance.root)
            return instance
        }
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 2.5
        camera.position = SCNVector3(0, 2.2, 7); camera.look(at: SCNVector3(0, 1, 0))
        scene.rootNode.addChildNode(camera)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 650; scene.rootNode.addChildNode(ambient)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .omni
        key.light?.intensity = 1100; key.position = SCNVector3(-3, 4, 4); scene.rootNode.addChildNode(key)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene; renderer.pointOfView = camera
        var digests = Set<String>()
        for (name, progress) in [("Enter", Float(0.5)), ("Jab", 0.5), ("Heavy", 0.5), ("Jump", 0.5)] {
            for (model, instance) in zip(models, instances) {
                let clip = try XCTUnwrap(model.clips[name])
                let start = clip.channels.compactMap { $0.times.first }.min() ?? 0
                var pose = model.restPose
                clip.sample(at: start + (clip.duration - start) * progress, into: &pose)
                for index in model.animated { instance.nodes[index].simdTransform = pose.transform(index) }
            }
            let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1200, height: 800), antialiasingMode: .multisampling2X)
            let data = try XCTUnwrap(image.pngData())
            XCTAssertGreaterThan(data.count, 5000)
            digests.insert(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            let attachment = XCTAttachment(image: image)
            attachment.name = "original-rig-review-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(digests.count, 4, "Distinct actual clips must change the rendered poses")
    }
}
