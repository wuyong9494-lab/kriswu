import SwiftUI

/// Match the source button's hit rectangle after aspect fitting, including any
/// transparent image margin. The real SwiftUI Button continues to own input.
struct ArenaSourceControlHitShape: Shape {
    let imageSize: CGSize
    let region: CGRect

    func path(in rect: CGRect) -> Path {
        guard imageSize.width > 0, imageSize.height > 0 else { return Path(rect) }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let width = imageSize.width * scale, height = imageSize.height * scale
        return Path(CGRect(x: rect.midX - width/2 + region.minX * width,
                           y: rect.midY - height/2 + region.minY * height,
                           width: region.width * width, height: region.height * height))
    }
}
