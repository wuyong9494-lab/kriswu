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
                try checkBackground(theme,root:root,manifest:manifest,device:device)
            }
        }
    }

    private func checkBackground(_ theme: ArenaResourcePackManifest.Theme, root: URL,
                                 manifest: ArenaResourcePackManifest, device: MTLDevice) throws {
        let path = try XCTUnwrap(theme.sceneFile)
        let export = try XCTUnwrap(theme.sceneExport)
        let document = try document(path,root:root,manifest:manifest)
        let scene = try ArenaLobbyTimelineScene(document:document,exportName:export,sourceRect:theme.sceneSourceRect)
        let textures = try atlases(document,root:root,manifest:manifest)
        let renderer = try ArenaLobbyTimelineRenderer(device:device,scene:scene,atlases:textures)
        let first = try renderer.snapshot(time:0,width:512,height:288)
        let later = try renderer.snapshot(time:2,width:512,height:288)
        XCTAssertEqual(first.count,589824)
        XCTAssertTrue(first != later,"Original timeline must not be flattened")
        XCTAssertTrue(first.contains { $0 != 0 },"Original background must contain visible pixels")
        // The frozen Brawloween still used child-color replacement;
        // its color parity requires original-client evidence. All other
        // previews catch crop and double-alpha regressions.
        if theme.id != "Brawloween26" {
            let url = try resource(theme.backgroundFile,root:root,manifest:manifest)
            let data = try Data(contentsOf:url)
            let reference = try ArenaFacePixels(data:data)
            XCTAssertEqual(reference.width,1024)
            XCTAssertEqual(reference.height,576)
            guard reference.width == 1024,reference.height == 576 else { return }
            let error = Self.meanBaselineError(first,reference:reference.rgba)
            XCTAssertLessThan(error,6,"Private background differs from its verified framing/color baseline")
        }
    }

    private static func meanBaselineError(_ actual: [UInt8], reference: [UInt8]) -> Double {
        var difference = 0.0
        for y in 0..<288 {
            let actualRow = y * 512
            let referenceRow = (y * 2 + 1) * 1024
            for x in 0..<512 {
                let actualOffset = (actualRow + x) * 4
                let referenceOffset = (referenceRow + x * 2 + 1) * 4
                for channel in 0..<3 {
                    let a = Double(actual[actualOffset + channel])
                    let b = Double(reference[referenceOffset + channel])
                    difference += abs(a - b)
                }
            }
        }
        return difference / 442368.0
    }

    func testAllTwelvePrivateControlsRenderSavedStateAndSourceAnimations() throws {
        let (root,manifest) = try fixtures()
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(),"Private validation requires an actual Metal device")
        for font in manifest.fonts ?? [] { _ = try resource(font.file,root:root,manifest:manifest) }
        ArenaImportedFonts.prepare(manifest:manifest) { root.appendingPathComponent($0) }
        XCTAssertEqual(ArenaImportedFonts.availableNames.count,4)
        let path = try XCTUnwrap(manifest.interfaceSceneFile)
        let document = try document(path,root:root,manifest:manifest)
        let textures = try atlases(document,root:root,manifest:manifest)
        XCTAssertEqual(ArenaLobbySourceControl.Role.allCases.count,12)
        let season = ArenaLobbySourceControl.Season(tier:2,points:50,pointsPerTier:100,hasReward:false)
        let values = ArenaLobbySourceControl.Values(coins:2500,trophies:1250,playerName:"测试玩家",season:season)
        for role in ArenaLobbySourceControl.Role.allCases {
            try autoreleasepool {
                let title = values.title(for:role) ?? role.title
                let source = try ArenaLobbySourceControl(document:document,role:role,title:title,season:season)
                let frame = try source.scene.frame(time:0)
                let titles: [String] = frame.operations.compactMap { operation in
                    if case .text(let text) = operation { return text.value }
                    return nil
                }
                let expected = role == .season ? [title,"2","50/100"] : role.titlePath == nil ? [] : [title]
                XCTAssertEqual(titles,expected)
                let renderer = try ArenaLobbyTimelineRenderer(device:device,scene:source.scene,atlases:textures)
                let width = Int(ceil(source.bounds.width*3)),height = Int(ceil(source.bounds.height*3))
                let first = try renderer.snapshot(time:0,width:width,height:height)
                XCTAssertTrue(first.contains { $0 != 0 })
                if role == .shop {
                    let later = try renderer.snapshot(time:0.37,width:width,height:height)
                    XCTAssertTrue(first != later,"Source idle animation must change visible pixels")
                }
                if role == .profile {
                    let field = role.instance + "/player_name_txt"
                    source.scene.interfaceState?.text[field] = "Changed Player 玩家"
                    let renamed = try renderer.snapshot(time:0,width:width,height:height)
                    XCTAssertTrue(renamed != first,"Changing the nickname must replace the rendered name")
                }
                if role == .season {
                    XCTAssertEqual(try renderer.snapshot(time:0.37,width:width,height:height),first,
                                   "The pass must stay still unless its actual tier increases")
                    let event = try ArenaLobbySourceControl(document:document,role:.season,title:title,
                        season:season,animateSeasonTier:true)
                    let eventRenderer = try ArenaLobbyTimelineRenderer(device:device,scene:event.scene,atlases:textures)
                    let w = Int(ceil(event.bounds.width*3)),h = Int(ceil(event.bounds.height*3))
                    let rest = try eventRenderer.snapshot(time:0,width:w,height:h)
                    XCTAssertNotEqual(try eventRenderer.snapshot(time:0.37,width:w,height:h),rest)
                    XCTAssertEqual(try eventRenderer.snapshot(time:1.37,width:w,height:h),rest,
                                   "The real tier flash must finish instead of looping over the lobby")
                    XCTAssertTrue(try event.scene.oneShotPlaybackCompleted(at:1.37))
                    var previous = first
                    for saved in [
                        ArenaLobbySourceControl.Season(tier:2,points:99,pointsPerTier:100,hasReward:false),
                        .init(tier:3,points:0,pointsPerTier:100,hasReward:true),
                        .init(tier:3,points:0,pointsPerTier:100,hasReward:false),
                        .init(tier:50,points:100,pointsPerTier:100,hasReward:true),
                        .init(tier:0,points:0,pointsPerTier:100,hasReward:false)
                    ] {
                        let updated = try ArenaLobbySourceControl(document:document,role:.season,title:title,season:saved)
                        let updatedRenderer = try ArenaLobbyTimelineRenderer(device:device,scene:updated.scene,atlases:textures)
                        let frame = try updated.scene.frame(time:0)
                        let text: [String] = frame.operations.compactMap {
                            if case .text(let t) = $0 { return t.value }; return nil
                        }
                        XCTAssertEqual(text,[title,String(saved.tier),"\(saved.points)/\(saved.pointsPerTier)"])
                        let pixels = try updatedRenderer.snapshot(time:0,width:width,height:height)
                        XCTAssertTrue(pixels != previous,"Pass progress, tier, ready and reset states must redraw")
                        previous = pixels
                    }
                }
                if role == .coins || role == .trophies {
                    let field = role.instance + "/" + (try XCTUnwrap(role.titlePath))
                    var previous = first
                    for balance in ["0","75","2000000000","0"] {
                        source.scene.interfaceState?.text[field] = balance
                        let updated = try source.scene.frame(time:0)
                        let text: [String] = updated.operations.compactMap {
                            if case .text(let t) = $0 { return t.value }; return nil
                        }
                        XCTAssertEqual(text,[balance])
                        let pixels = try renderer.snapshot(time:0,width:width,height:height)
                        XCTAssertTrue(pixels != previous,"Spending and earning must redraw the saved balance")
                        previous = pixels
                    }
                }
            }
        }
    }
}
