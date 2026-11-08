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
        var lightmapped = 0
        sceneRoot.enumerateChildNodes { node, _ in
            for material in node.geometry?.materials ?? [] where material.multiply.mappingChannel == 1 {
                XCTAssertEqual(material.lightingModel, .constant)
                lightmapped += 1
            }
        }
        XCTAssertGreaterThan(lightmapped, 0, "The real lobby must preserve its baked lightmap UVs")
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
            let world = DuelWorldView(session: state)
            defer { world.shutdown(); state.shutdown() }
            world.frame = CGRect(x: 0, y: 0, width: 956, height: 440)
            world.layoutIfNeeded()
            let scene = try XCTUnwrap(world.scene)
            XCTAssertNotNil(world.stageAsset)
            XCTAssertNotNil(scene.rootNode.childNode(withName: "duel.stage.palace", recursively: false))
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

    private func capture(_ view: SCNView, name: String) {
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = view.scene; renderer.pointOfView = view.pointOfView
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1434, height: 660), antialiasingMode: .multisampling2X)
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 5000)
    }
}
