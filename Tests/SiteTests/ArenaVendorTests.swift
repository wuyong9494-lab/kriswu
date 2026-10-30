import XCTest
import SceneKit
import UIKit
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
            XCTAssertNotNil(ArenaModels.shared.prop(file), "Real SceneKit loader rejected \(file)")
        }
        XCTAssertNotNil(ArenaVendorAssets.spark)
        XCTAssertNotNil(ArenaVendorAssets.smoke)
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
