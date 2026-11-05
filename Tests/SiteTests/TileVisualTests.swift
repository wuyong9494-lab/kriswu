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

    func testOldRecordsDecodeWithoutAnyNewFields() throws {
        let data = Data(#"{"best":{"1":32.5},"played":{"1":4},"wins":{"1":2},"daily":{"2026-10-27":{"won":true,"seconds":32.5,"cleared":36,"total":36}}}"#.utf8)
        let old = try JSONDecoder().decode(TileRecords.self, from: data)
        XCTAssertEqual(old.best[1], 32.5)
        XCTAssertEqual(old.daily["2026-10-27"]?.total, 36)
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
