import XCTest
import SwiftUI
import UIKit
@testable import ShiftReminder

final class TileVisualTests: XCTestCase {
    @MainActor
    func testTwelveIllustrationsAreVisibleAndDistinct() throws {
        var unique = Set<Data>()
        for kind in 0..<12 {
            let renderer = ImageRenderer(content: TileGlyph(kind: kind).frame(width: 80, height: 80))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            unique.insert(try XCTUnwrap(image.pngData()))
            let cg = try XCTUnwrap(image.cgImage)
            var bytes = [UInt8](repeating: 0, count: 80 * 80 * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 80, height: 80,
                    bitsPerComponent: 8, bytesPerRow: 320, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                context.draw(cg, in: CGRect(x: 0, y: 0, width: 80, height: 80))
            }
            XCTAssertGreaterThan(stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] > 128 }.count, 600, "图案 \(kind) 不应为空或只有几个点")
        }
        XCTAssertEqual(unique.count, 12, "不同牌种必须有不同轮廓，不能只更换名称")
        let gallery = LazyVGrid(columns: Array(repeating: GridItem(.fixed(86)), count: 4), spacing: 16) {
            ForEach(0..<12) { kind in
                VStack(spacing: 8) {
                    TileFace(kind: kind, side: 72)
                    Text(TileTheme.names[kind]).font(.caption).foregroundStyle(.white)
                }
            }
        }
        .padding(24).background(TileTheme.navy)
        try emit(gallery, name: "glyphs", size: CGSize(width: 420, height: 380))
    }

    @MainActor
    func testHomeAndBoardsRenderAtPhoneAndLandscapeSizes() throws {
        try emit(TileGameHomeView(), name: "home", size: CGSize(width: 440, height: 956))
        for (name, size, level) in [
            ("board", CGSize(width: 440, height: 956), TileGame.Level.hard),
            ("compact", CGSize(width: 375, height: 667), TileGame.Level.normal),
            ("landscape", CGSize(width: 956, height: 440), TileGame.Level.hard),
        ] {
            try emit(TileBoardView(play: TilePlay(level: level, seed: 38_101, mode: .solo), race: nil), name: name, size: size)
        }
    }

    @MainActor
    func testReplayRendersPressureStatesAtCompactAndLargeTypeSizes() async throws {
        var game = TileGame(level: .hard, seed: 84135585, ruleSet: .constellation)
        var replay = TileReplay(game: game)
        for _ in 0..<30 {
            guard game.status == .playing, let id = game.freeIDs.sorted().first else { break }
            XCTAssertTrue(game.pick(id))
            XCTAssertTrue(replay.append(.pick(id), resultingIn: game))
        }
        XCTAssertGreaterThan(replay.actionCount, 0)
        for (name, size) in [("replay-compact", CGSize(width: 375, height: 667)),
                             ("replay-pro-max", CGSize(width: 440, height: 956))] {
            try await emitHosted(TileReplayView(replay: replay), name: name, size: size)
        }
        try await emitHosted(TileReplayView(replay: replay).environment(\.dynamicTypeSize, .accessibility2),
                 name: "replay-large-type", size: CGSize(width: 440, height: 956))
    }

    func testOldRecordsDecodeWithoutAnyNewFields() throws {
        let data = Data(#"{"best":{"1":32.5},"played":{"1":4},"wins":{"1":2},"daily":{"2026-10-27":{"won":true,"seconds":32.5,"cleared":36,"total":36}}}"#.utf8)
        let old = try JSONDecoder().decode(TileRecords.self, from: data)
        XCTAssertEqual(old.best[1], 32.5)
        XCTAssertEqual(old.daily["2026-10-27"]?.total, 36)
    }

    /// GeometryReader/ScrollView may produce only the background through an
    /// offscreen ImageRenderer. Mount a real window and reject an empty board.
    @MainActor
    private func emitHosted<V: View>(_ view: V, name: String, size: CGSize) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        let host = UIHostingController(rootView: view.environment(\.colorScheme, .dark))
        host.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 250_000_000)
        host.view.layoutIfNeeded()
        XCTAssertEqual(window.bounds.size, size)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        var drew = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            drew = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(drew)
        let cg = try XCTUnwrap(image.cgImage)
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        var bright = 0
        for y in height / 3 ..< height * 3 / 4 {
            for x in width / 10 ..< width * 9 / 10 {
                let i = (y * width + x) * 4
                if pixels[i] > 180 && pixels[i + 1] > 180 && pixels[i + 2] > 180 { bright += 1 }
            }
        }
        XCTAssertGreaterThan(bright, 800, "复盘中央区域必须包含实际牌面，不能只截到星空背景")
        let attachment = XCTAttachment(image: image)
        attachment.name = "tiles-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor
    private func emit<V: View>(_ view: V, name: String, size: CGSize) throws {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .dark))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size, size)
        let data = try XCTUnwrap(image.pngData())
        XCTAssertGreaterThan(data.count, 4_000)
        let attachment = XCTAttachment(image: image); attachment.name = "tiles-\(name)"; attachment.lifetime = .keepAlways
        add(attachment)
        print("TILEIMG|\(name)|\(data.base64EncodedString())")
    }
}
