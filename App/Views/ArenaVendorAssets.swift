import SceneKit
import SwiftUI
import UIKit

/// Runtime files have unique names; the full licensed source packs live in art/vendor.
enum ArenaVendorAssets {
    static let propFiles = ["vendor_axe.gltf", "vendor_crates.glb", "vendor_barrel.glb",
                            "vendor_bush.glb", "vendor_rock.glb", "vendor_tree.glb"]
    static let imageFiles = ["vendor_button_blue.png", "vendor_button_yellow.png",
                             "vendor_icon_arrowLeft.png", "vendor_icon_checkmark.png",
                             "vendor_icon_cross.png", "vendor_icon_star.png",
                             "vendor_spark_01.png", "vendor_smoke_01.png"]
    // These are loose bundle resources, not asset-catalog names. Resolve the
    // file explicitly and share the decoded images between SwiftUI and SceneKit.
    @MainActor private static let images: [String: UIImage] = {
        var result: [String: UIImage] = [:]
        for file in imageFiles {
            let path = file as NSString
            if let url = Bundle.main.url(forResource: path.deletingPathExtension,
                                         withExtension: path.pathExtension),
               let image = UIImage(contentsOfFile: url.path) {
                result[file] = image
            }
        }
        return result
    }()
    @MainActor static func image(_ file: String) -> UIImage? { images[file] }
    @MainActor static var spark: UIImage? { image("vendor_spark_01.png") }
    @MainActor static var smoke: UIImage? { image("vendor_smoke_01.png") }

    /// Fit imported scenery inside the existing cell; gameplay collision is unchanged.
    @MainActor static func prop(_ file: String, width: Float, height: Float) -> SCNNode? {
        guard let model = ArenaModels.shared.prop(file) else { return nil }
        let content = model.instantiate(shareMaterials: true).root
        let (low, high) = content.boundingBox
        let span = SIMD3<Float>(high.x - low.x, high.y - low.y, high.z - low.z)
        guard span.x > 0, span.y > 0, span.z > 0 else { return nil }
        let scale = min(width / max(span.x, span.z), height / span.y)
        content.simdScale = SIMD3(repeating: scale)
        content.simdPosition = SIMD3(-(low.x + high.x) * scale / 2, -low.y * scale,
                                    -(low.z + high.z) * scale / 2)
        content.enumerateChildNodes { node, _ in node.castsShadow = false }
        content.castsShadow = false
        let root = SCNNode()
        root.name = "vendor-" + file
        root.addChildNode(content)
        root.castsShadow = false
        return root
    }

    @MainActor static func border(width: Float, height: Float) -> SCNNode {
        let root = SCNNode()
        root.name = "vendor-nature-border"
        // A fixed, small number of shared meshes stays outside playable/collision cells.
        for (index, x) in [Float(2), width / 2, width - 2].enumerated() {
            for z in [Float(-1.5), height + 1.5] {
                let file = index == 1 ? "vendor_bush.glb" : "vendor_tree.glb"
                if let node = prop(file, width: 1.1, height: index == 1 ? 0.8 : 1.8) {
                    node.simdPosition = SIMD3(x, 0, z)
                    root.addChildNode(node)
                }
            }
        }
        for x in [Float(-0.9), width + 0.9] {
            for z in [height * 0.25, height * 0.75] {
                if let node = prop("vendor_rock.glb", width: 0.8, height: 0.6) {
                    node.simdPosition = SIMD3(x, 0, z)
                    root.addChildNode(node)
                }
            }
        }
        return root
    }
}

struct ArenaVendorIcon: View {
    let name: String
    var body: some View {
        if let image = ArenaVendorAssets.image("vendor_icon_" + name + ".png") {
            Image(uiImage: image)
                .renderingMode(.template).resizable().scaledToFit()
                .accessibilityHidden(true)
        }
    }
}

struct ArenaVendorButtonFace: View {
    var primary = false
    var pressed = false
    var body: some View {
        if let image = ArenaVendorAssets.image(primary ? "vendor_button_yellow.png" : "vendor_button_blue.png") {
            Image(uiImage: image)
                .resizable(capInsets: EdgeInsets(top: 14, leading: 14, bottom: 18, trailing: 14))
                .brightness(pressed ? -0.08 : 0)
                .accessibilityHidden(true)
        }
    }
}
