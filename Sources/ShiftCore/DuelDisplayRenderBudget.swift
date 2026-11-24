import Foundation

/// One pixel & GPU quality budget for the scene view and its independently owned Metal surface.
/// View bounds remain in points so the camera and touch layout keep their aspect.
public struct DuelDisplayRenderBudget: Equatable, Sendable {
    public let scale: CGFloat
    public let drawableSize: CGSize
    public let samples: Int
    public let isCasting: Bool
    /// Shadow map edge resolution in pixels (1024 native mobile, 512 while casting to prevent AirPlay encoder GPU stalls).
    public let shadowMapDimension: Int
    /// PCF shadow samples (2 native mobile, 1 while casting).
    public let shadowSampleCount: Int
    /// Multi-pass depth-of-field bokeh is disabled during external/wireless TV casting.
    public let allowsDepthOfField: Bool
    /// Full-screen SSAO pass is disabled during external/wireless TV casting.
    public let allowsAmbientOcclusion: Bool
    /// HDR bloom blur pass is disabled during external/wireless TV casting.
    public let allowsBloom: Bool

    /// Recognizes wired HDMI / external window scenes, mirrored displays, and iOS 16+ wireless AirPlay screen capture.
    public static func isCasting(externalDisplay: Bool, mirrored: Bool, screenCaptured: Bool) -> Bool {
        externalDisplay || mirrored || screenCaptured
    }

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
        isCasting = casting
        shadowMapDimension = casting ? 512 : 1024
        shadowSampleCount = casting ? 1 : 2
        allowsDepthOfField = !casting
        allowsAmbientOcclusion = !casting
        allowsBloom = !casting
    }
}
