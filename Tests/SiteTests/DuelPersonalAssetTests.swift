import XCTest
import SceneKit
import simd
@testable import ShiftReminder

/// Selected only by the private-personal-fighters workflow input. Missing real
/// assets must fail this suite; procedural actors are never acceptance evidence.
@MainActor
final class DuelPersonalAssetTests: XCTestCase {
    private func asset(_ hero: DuelGame.Hero) throws -> DuelCharacterAsset {
        let url = try XCTUnwrap(DuelCharacterAsset.bundledURL(for: hero), "Stage the actual personal model")
        return try DuelCharacterAsset(url: url, hero: hero)
    }

    func testBothPersonalModelsHaveCompleteIndependentFinitePoses() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            let asset = try asset(hero)
            XCTAssertTrue(asset.model.hasSkinning)
            let first = DuelCharacterInstance(asset), second = DuelCharacterInstance(asset)
            XCTAssertFalse(first.bone("head") === second.bone("head"))
            let untouched = try XCTUnwrap(second.bone("hand.R")).simdTransform
            for name in DuelCharacterAnimation.Clip.allCases.map(\.rawValue) {
                let clip = try XCTUnwrap(asset.model.clips[name])
                let start = asset.starts[name] ?? 0
                for progress in [Float(0), 0.25, 0.5, 0.75, 1] {
                    var pose = asset.model.restPose
                    clip.sample(at: start + (clip.duration - start) * progress, into: &pose)
                    for index in asset.model.animated {
                        first.instance.nodes[index].simdTransform = pose.transform(index)
                    }
                    for name in ["head", "hips", "hand.L", "hand.R", "foot.L", "foot.R"] {
                        let bone = try XCTUnwrap(first.bone(name))
                        let p = bone.simdWorldPosition
                        XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.z.isFinite)
                        XCTAssertLessThan(simd_length(p), 4, "A sampled joint escaped the authored character bounds")
                    }
                    XCTAssertEqual(try XCTUnwrap(second.bone("hand.R")).simdTransform, untouched)
                }
            }
            let other: DuelGame.Hero = hero == .liu ? .ember : .liu
            XCTAssertThrowsError(try DuelCharacterAsset(url: XCTUnwrap(DuelCharacterAsset.bundledURL(for: hero)), hero: other))
        }
    }

    func testLobbyLoadsBothRealModelsAndBakedScene() throws {
        let sceneAsset = try DuelStageAsset(url: XCTUnwrap(DuelStageAsset.bundledURL(for: .autumnLobby)), kind: .autumnLobby)
        let sceneRoot = sceneAsset.makeRoot()
        let sourceMaterials: Set<String> = ["ALFA", "BG", "ALFA_BG", "Base_mat", "Leavs_mat"]
        let uniformLightmaps: Set<String> = ["BG", "ALFA_BG", "Leavs_mat"]
        var materialCounts = [String: Int]()
        sceneRoot.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            for material in geometry.materials {
                let name = material.name ?? ""
                materialCounts[name, default: 0] += 1
                XCTAssertEqual(material.lightingModel, .constant)
                XCTAssertNotNil(material.multiply.contents)
                XCTAssertEqual(material.multiply.mappingChannel, uniformLightmaps.contains(name) ? 0 : 1,
                               "The actual lobby must retain its uniform or UV1 baked lightmap: \(name)")
                let surface = material.shaderModifiers?[.surface] ?? ""
                XCTAssertEqual(surface.components(separatedBy: GLTFModel.sourceLocationColorMarker).count - 1,
                               sourceMaterials.contains(name) ? 1 : 0, "Unexpected source RGB gain: \(name)")
                if name == "Matcup_mat" {
                    XCTAssertTrue(geometry.sources(for: .color).isEmpty,
                                  "The MatCap variant must remain outside the static color compatibility mode")
                }
            }
        }
        XCTAssertEqual(materialCounts, ["ALFA": 5, "BG": 1, "ALFA_BG": 11,
                                        "Base_mat": 63, "Matcup_mat": 14, "Leavs_mat": 2])
        // The two leaf meshes stored white UNorm8 colors as FLOAT 255. The
        // distant background cards have no source colors and need identity RGB.
        // Inspect this existing instance instead of loading another large model.
        for (name, count) in [("Leaves_01", 196), ("Leaves_002", 214), ("BG_01", 52), ("BG_ALf_0000", 32)] {
            let node = try XCTUnwrap(sceneRoot.childNode(withName: name, recursively: true))
            let geometry = try XCTUnwrap(node.childNodes.compactMap(\.geometry).first)
            let colors = try XCTUnwrap(geometry.sources(for: .color).first)
            assertWhiteSourceColors(colors, count: count, label: name)
        }
        let clocks = DuelWorldView.activeClocks
        let lobby = DuelLobbySceneView(hero: .ember)
        defer { lobby.shutdown() }
        let scene = try XCTUnwrap(lobby.scene)
        XCTAssertNotNil(scene.rootNode.childNode(withName: "duel.stage.autumnLobby", recursively: false))
        for hero in [DuelGame.Hero.ember, .liu, .ember] {
            lobby.select(hero)
            let characters = scene.rootNode.childNodes.filter { $0.name?.hasPrefix("duel.lobby.character.") == true }
            XCTAssertEqual(characters.count, 1)
            XCTAssertEqual(characters.first?.name, "duel.lobby.character.\(hero.rawValue)")
            capture(lobby, name: "personal-lobby-\(hero.rawValue)")
        }
        XCTAssertEqual(DuelWorldView.activeClocks, clocks)
    }

    func testBothMatchSelectionsLoadPersonalOpponentsAndPalace() throws {
        for hero in [DuelGame.Hero.ember, .liu] {
            let state = DuelSession(.init(hero: hero, difficulty: .learning, mode: .practice))
            let world = DuelWorldView(session: state, characterSource: .legacy)
            defer { world.shutdown(); state.shutdown() }
            world.frame = CGRect(x: 0, y: 0, width: 956, height: 440)
            world.layoutIfNeeded()
            let scene = try XCTUnwrap(world.scene)
            XCTAssertNotNil(world.stageAsset)
            let palace = try XCTUnwrap(scene.rootNode.childNode(withName: "duel.stage.palace", recursively: false))
            if hero == .ember {
                // The captured roof stored 1985 white UNorm8 colors as FLOAT
                // 255. Verify the actual asset is normalized before rendering.
                let roof = try XCTUnwrap(palace.childNode(withName: "roof_back", recursively: true))
                let geometry = try XCTUnwrap(roof.childNodes.compactMap(\.geometry).first)
                let colors = try XCTUnwrap(geometry.sources(for: .color).first)
                assertWhiteSourceColors(colors, count: 1985, label: "roof_back")
            }
            for (index, fighter) in state.game.fighters.enumerated() {
                let actor = try XCTUnwrap(scene.rootNode.childNode(withName: "duel.actor.\(index)", recursively: false))
                XCTAssertNotNil(actor.childNode(withName: "duel.\(fighter.hero.rawValue).skinned", recursively: false))
            }
            capture(world, name: "personal-palace-\(hero.rawValue)")
            state.restart(); world.drawState()
            XCTAssertEqual(state.game.fighters[0].hero, hero)
            XCTAssertEqual(state.game.fighters[1].hero, hero == .liu ? .ember : .liu)
        }
    }

    private func assertWhiteSourceColors(_ source: SCNGeometrySource, count: Int, label: String,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let vectorBytes = 4 * MemoryLayout<Float>.size
        guard count > 0, source.vectorCount == count, source.usesFloatComponents,
              source.componentsPerVector == 4, source.bytesPerComponent == MemoryLayout<Float>.size else {
            XCTFail("Expected \(count) Float4 source colors for \(label)", file: file, line: line)
            return
        }
        // Validate the complete last vector before any load. Division keeps
        // malformed strides/counts from overflowing the bounds calculation.
        guard source.dataOffset >= 0, source.dataOffset <= source.data.count,
              source.dataStride >= vectorBytes, source.data.count - source.dataOffset >= vectorBytes,
              count - 1 <= (source.data.count - source.dataOffset - vectorBytes) / source.dataStride else {
            XCTFail("Source color layout exceeds its buffer for \(label)", file: file, line: line)
            return
        }
        let white = source.data.withUnsafeBytes { bytes in
            (0..<count).allSatisfy { vertex in
                (0..<4).allSatisfy { channel in
                    let offset = source.dataOffset + vertex * source.dataStride + channel * MemoryLayout<Float>.size
                    let value = bytes.loadUnaligned(fromByteOffset: offset, as: Float.self)
                    return value.isFinite && abs(value - 1) < 0.00001
                }
            }
        }
        XCTAssertTrue(white, "Expected normalized white RGB and independent alpha for \(label)", file: file, line: line)
    }

    private func capture(_ view: SCNView, name: String) {
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = view.scene; renderer.pointOfView = view.pointOfView
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1434, height: 660), antialiasingMode: .multisampling2X)
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 5000)
    }
}
