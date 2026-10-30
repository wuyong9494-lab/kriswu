import SwiftUI
import UIKit

/// Small, shared interface textures. Source variants remain in the licensed archive;
/// only these assigned controls are decoded, once, when the arena UI first needs them.
enum ArenaInterfaceAssets {
    enum Role: String, CaseIterable {
        case panel, checkOn = "check_on", checkOff = "check_off"
        case sliderTrack = "slider_track", sliderFill = "slider_fill", sliderThumb = "slider_thumb"
        case musicOn = "music_on", musicOff = "music_off"
        case soundOn = "sound_on", soundOff = "sound_off"
        case settings, home, locked, information

        var file: String { "vendor_interface_" + rawValue + ".png" }
    }

    @MainActor private static let images: [Role: UIImage] = {
        var result: [Role: UIImage] = [:]
        for role in Role.allCases {
            let file = role.file as NSString
            if let url = Bundle.main.url(forResource: file.deletingPathExtension,
                                         withExtension: file.pathExtension),
               let image = UIImage(contentsOfFile: url.path) {
                result[role] = image
            }
        }
        return result
    }()

    @MainActor static func image(_ role: Role) -> UIImage? { images[role] }
}

struct ArenaInterfaceIcon: View {
    let role: ArenaInterfaceAssets.Role
    init(_ role: ArenaInterfaceAssets.Role) { self.role = role }
    var body: some View {
        if let image = ArenaInterfaceAssets.image(role) {
            Image(uiImage: image).renderingMode(.template).resizable().scaledToFit()
                .accessibilityHidden(true)
        }
    }
}

struct ArenaInterfaceTexture: View {
    let role: ArenaInterfaceAssets.Role
    var cap: CGFloat = 10
    var body: some View {
        if let image = ArenaInterfaceAssets.image(role) {
            Image(uiImage: image)
                .resizable(capInsets: EdgeInsets(top: cap, leading: cap, bottom: cap, trailing: cap))
                .accessibilityHidden(true)
        }
    }
}
