import CryptoKit
import Foundation
import Metal
import XCTest
#if ARENA_RESOURCE_RUNTIME_TESTS
@testable import ArenaResourceRuntime
#else
@testable import ShiftReminder
#endif

/// Runs only on the private promotion runner. It never attaches original
/// pixels to an xcresult or writes them to public workflow artifacts.
@MainActor
final class ArenaPrivateResourceRenderingTests: XCTestCase {
    private func fixtures() throws -> (URL, ArenaResourcePackManifest) {
        guard let root = Bundle(for: Self.self).url(forResource: "ArenaPrivateValidation", withExtension: nil) else {
            throw XCTSkip("Private fixtures are intentionally absent from public CI")
        }
        let manifest = try JSONDecoder().decode(ArenaResourcePackManifest.self,
            from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        try manifest.validate()
        return (root,manifest)
    }

    private func resource(_ path: String, root: URL, manifest: ArenaResourcePackManifest) throws -> URL {
        let entry = try XCTUnwrap(manifest.files.first { $0.path == path })
        let url = root.appendingPathComponent(path)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count,entry.bytes)
        XCTAssertEqual(SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined(),entry.sha256)
        return url
    }

    private func document(_ path: String, root: URL, manifest: ArenaResourcePackManifest) throws -> ArenaLobbyTimelineDocument {
        try JSONDecoder().decode(ArenaLobbyTimelineDocument.self,
            from: Data(contentsOf: resource(path,root:root,manifest:manifest)))
    }

    private func atlases(_ document: ArenaLobbyTimelineDocument, root: URL,
                         manifest: ArenaResourcePackManifest) throws -> [ArenaLobbyTimelineRenderer.Atlas] {
        var urls: [String:URL] = [:]
        for texture in document.textures {
            let entry = try XCTUnwrap(manifest.files.first { $0.path == texture.file && $0.kind == .image })
            XCTAssertEqual(entry.sha256,texture.sha256)
            urls[texture.file] = try resource(texture.file,root:root,manifest:manifest)
        }
        return try ArenaLobbyTimelineRenderer.loadAtlases(document:document) { urls[$0] }
    }

    func testAllEightPrivateBackgroundsRenderChangingOriginalFrames() throws {
        let (root,manifest) = try fixtures()
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(),"Private validation requires an actual Metal device")
        XCTAssertEqual(manifest.themes.count,8)
        for theme in manifest.themes {
            try autoreleasepool {
                let document = try document(XCTUnwrap(theme.sceneFile),root:root,manifest:manifest)
                let scene = try ArenaLobbyTimelineScene(document:document,exportName:XCTUnwrap(theme.sceneExport),
                                                        sourceRect:theme.sceneSourceRect)
                let renderer = try ArenaLobbyTimelineRenderer(device:device,scene:scene,
                    atlases:atlases(document,root:root,manifest:manifest))
                let first = try renderer.snapshot(time:0,width:512,height:288)
                let later = try renderer.snapshot(time:2,width:512,height:288)
                XCTAssertEqual(first.count,512*288*4)
                XCTAssertTrue(first != later,"Original timeline must not be flattened")
                XCTAssertTrue(first.contains { $0 != 0 },"Original background must contain visible pixels")
                // The frozen Brawloween still used child-color replacement;
                // its color parity requires original-client evidence. All
                // other previews catch crop and double-alpha regressions.
                if theme.id != "Brawloween26" {
                    let reference = try ArenaFacePixels(data:Data(contentsOf:resource(theme.backgroundFile,root:root,manifest:manifest)))
                    XCTAssertEqual(reference.width,1024);XCTAssertEqual(reference.height,576)
                    guard reference.width == 1024,reference.height == 576 else { return }
                    var difference = 0.0
                    for y in 0..<288 { for x in 0..<512 { for channel in 0..<3 {
                        let actual = first[(y*512+x)*4+channel]
                        let expected = reference.rgba[((y*2+1)*1024+x*2+1)*4+channel]
                        difference += abs(Double(actual)-Double(expected))
                    } } }
                    XCTAssertLessThan(difference/Double(512*288*3),6,"Private background differs from its verified framing/color baseline")
                }
            }
        }
    }

    func testAllFivePrivateControlsRenderActualTitlesAndShopAnimation() throws {
        let (root,manifest) = try fixtures()
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(),"Private validation requires an actual Metal device")
        for font in manifest.fonts ?? [] { _ = try resource(font.file,root:root,manifest:manifest) }
        ArenaImportedFonts.prepare(manifest:manifest) { root.appendingPathComponent($0) }
        XCTAssertEqual(ArenaImportedFonts.availableNames.count,4)
        let document = try document(XCTUnwrap(manifest.interfaceSceneFile),root:root,manifest:manifest)
        let textures = try atlases(document,root:root,manifest:manifest)
        XCTAssertEqual(ArenaLobbySourceControl.Role.allCases.count,5)
        for role in ArenaLobbySourceControl.Role.allCases {
            try autoreleasepool {
                let source = try ArenaLobbySourceControl(document:document,role:role,title:role.title)
                let frame = try source.scene.frame(time:0)
                XCTAssertEqual(frame.operations.compactMap { if case .text(let text) = $0 { return text.value }; return nil },[role.title])
                let renderer = try ArenaLobbyTimelineRenderer(device:device,scene:source.scene,atlases:textures)
                let width = Int(ceil(source.bounds.width*3)),height = Int(ceil(source.bounds.height*3))
                let first = try renderer.snapshot(time:0,width:width,height:height)
                XCTAssertTrue(first.contains { $0 != 0 })
                if role == .shop {
                    let later = try renderer.snapshot(time:2,width:width,height:height)
                    XCTAssertTrue(first != later,"Original shop animation must change visible pixels")
                }
            }
        }
    }
}
