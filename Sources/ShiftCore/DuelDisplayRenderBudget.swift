import Foundation

/// One pixel budget for the scene view and its independently owned Metal surface.
/// View bounds remain in points so the camera and touch layout keep their aspect.
public struct DuelDisplayRenderBudget: Equatable, Sendable {
    public let scale: CGFloat
    public let drawableSize: CGSize
    public let samples: Int

    public init?(size: CGSize, screenScale: CGFloat, casting: Bool) {
        guard size.width.isFinite, size.height.isFinite, screenScale.isFinite,
              size.width > 0, size.height > 0, screenScale > 0 else { return nil }
        let scale = casting
            ? min(screenScale, 1920 / max(size.width, size.height), 1080 / min(size.width, size.height))
            : screenScale
        let width = size.width * scale, height = size.height * scale
        guard width.isFinite, height.isFinite, width >= 1, height >= 1 else { return nil }
        self.scale = scale
        drawableSize = CGSize(width: floor(width), height: floor(height))
        samples = casting ? 1 : 2
    }
}
