import XCTest
import SceneKit
import UIKit
import SwiftUI
@testable import ShiftReminder

@MainActor
final class ArenaVendorTests: XCTestCase {
    func testAllElevenPacksAreBundledWithDecodableRuntimeFiles() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "arena-vendor-runtime", withExtension: "json"))
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(report["packCount"] as? Int, 11)
        let files = try XCTUnwrap(report["files"] as? [[String: Any]])
        XCTAssertEqual(Set(files.compactMap { $0["pack"] as? String }).count, 11)
        for entry in files {
            let file = try XCTUnwrap(entry["file"] as? String)
            let path = file as NSString
            let resource = try XCTUnwrap(Bundle.main.url(forResource: path.deletingPathExtension,
                                                        withExtension: path.pathExtension), file)
            XCTAssertGreaterThan(try Data(contentsOf: resource).count, 0, file)
            if path.pathExtension == "png" { XCTAssertNotNil(UIImage(contentsOfFile: resource.path), file) }
        }
        XCTAssertNotNil(Bundle.main.url(forResource: "ArenaVendor-LICENSES", withExtension: "txt"))
        for file in ArenaVendorAssets.propFiles {
            let model = try XCTUnwrap(ArenaModels.shared.prop(file), "Real SceneKit loader rejected \(file)")
            let root = model.instantiate(shareMaterials: true).root
            var vertices = 0
            root.enumerateChildNodes { node, _ in
                vertices += node.geometry?.sources(for: .vertex).first?.vectorCount ?? 0
            }
            XCTAssertGreaterThan(vertices, 0, "Selected scene has no visible mesh: \(file)")
        }
        XCTAssertNotNil(ArenaVendorAssets.spark)
        XCTAssertNotNil(ArenaVendorAssets.smoke)
        for file in ArenaVendorAssets.imageFiles {
            XCTAssertNotNil(ArenaVendorAssets.image(file), "Missing runtime image: \(file)")
        }
    }

    func testImportedButtonsAndCloseIconRenderVisiblePixels() throws {
        // A decodable bundled PNG alone did not guarantee that SwiftUI rendered
        // it in 469. Inspect the actual rendered controls, not just file presence.
        let blue = try pixels(ArenaVendorButtonFace().frame(width: 160, height: 50))
        XCTAssertGreaterThan(blue.filter { $0.3 > 200 && $0.2 > $0.0 && $0.1 > $0.0 }.count, 4000)
        let yellow = try pixels(ArenaVendorButtonFace(primary: true).frame(width: 160, height: 50))
        XCTAssertGreaterThan(yellow.filter { $0.3 > 200 && $0.0 > 180 && $0.1 > 120 && $0.2 < 120 }.count, 4000)
        let close = try pixels(ArenaVendorIcon(name: "cross").foregroundStyle(.white).frame(width: 32, height: 32))
        XCTAssertGreaterThan(close.filter { $0.3 > 200 }.count, 60)
    }

    private func pixels<V: View>(_ view: V) throws -> [(UInt8, UInt8, UInt8, UInt8)] {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        let count = image.width * image.height
        var bytes = [UInt8](repeating: 0, count: count * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        return stride(from: 0, to: bytes.count, by: 4).map { (bytes[$0], bytes[$0+1], bytes[$0+2], bytes[$0+3]) }
    }

    func testImportedCargoFitsOneExistingCollisionCell() throws {
        for file in ["vendor_crates.glb", "vendor_barrel.glb"] {
            let node = try XCTUnwrap(ArenaVendorAssets.prop(file, width: 0.96, height: 1.02))
            let (low, high) = node.boundingBox
            XCTAssertGreaterThan(high.y - low.y, 0.05)
            XCTAssertLessThanOrEqual(high.x - low.x, 0.9601)
            XCTAssertLessThanOrEqual(high.z - low.z, 0.9601)
            XCTAssertLessThanOrEqual(high.y - low.y, 1.0201)
            XCTAssertEqual(low.y, 0, accuracy: 0.0001)
            XCTAssertEqual(low.x + high.x, 0, accuracy: 0.0001)
        }
    }

    func testBarbarianUsesImportedAxeOnExistingAnimatedHand() throws {
        let look = BrawlerLook.of(.barbarian)
        XCTAssertTrue(look.hidden.contains("2H_Axe"))
        XCTAssertEqual(look.weapons.first?.file, "vendor_axe.gltf")
        let avatar = ArenaAvatar(brawler: .barbarian, color: .blue, isMe: true, qualitySample: true)
        let hand = try XCTUnwrap(avatar.node.childNode(withName: "handslot.r", recursively: true))
        XCTAssertNotNil(hand.childNode(withName: "axe_2handed", recursively: true))
    }

    func testNatureDressingStaysOutsidePlayableBounds() {
        let border = ArenaVendorAssets.border(width: 20, height: 30)
        XCTAssertEqual(border.childNodes.count, 10)
        for node in border.childNodes {
            let p = node.simdPosition
            XCTAssertTrue(p.x < 0 || p.x > 20 || p.z < 0 || p.z > 30)
        }
    }
}
