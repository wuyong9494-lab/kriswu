import Foundation

/// Perspective-only composition for the local showroom. The scene still covers
/// the entire view; only its camera moves to reserve space for measured controls.
public struct DuelLobbyFraming: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public let x, y, z: Double
        public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
        fileprivate func dot(_ other: Self) -> Double { x * other.x + y * other.y + z * other.z }
        fileprivate static func + (a: Self, b: Self) -> Self { .init(a.x + b.x, a.y + b.y, a.z + b.z) }
        fileprivate static func - (a: Self, b: Self) -> Self { .init(a.x - b.x, a.y - b.y, a.z - b.z) }
        fileprivate static func * (a: Self, b: Double) -> Self { .init(a.x * b, a.y * b, a.z * b) }
    }

    public static let verticalFieldOfView = 35.0
    public static let center = Point(4.7, 0.85, -0.35)
    public static let originalPosition = Point(5, 1.6, 4.8)
    private static let originalDistance = sqrt(0.3 * 0.3 + 0.75 * 0.75 + 5.15 * 5.15)
    private static let back = Point(0.3, 0.75, 5.15) * (1 / originalDistance)
    private static let right = Point(5.15, 0, -0.3) * (1 / sqrt(5.15 * 5.15 + 0.3 * 0.3))
    private static let cameraUp = Point(back.y * right.z, back.z * right.x - back.x * right.z, -back.y * right.x)

    /// A presentation envelope, not collision geometry or a model scale change.
    /// The lower box reserves a 2.7 m-wide floor footprint; the upper box is a
    /// conservative idle body/weapon allowance through a full rotation. These
    /// are authored bounds, not recovered source dimensions. Actual-source
    /// vertex checks and rendered pedestal inspection remain acceptance gates.
    public static let envelope: [Point] = {
        var points: [Point] = []
        for (radius, heights) in [(1.35, [-0.28, -0.12]), (1.05, [-0.14, 2.05])] {
            for x in [-radius, radius] {
                for y in heights {
                    for z in [-radius, radius] { points.append(.init(center.x + x, y, center.z + z)) }
                }
            }
        }
        return points
    }()

    public let position: Point
    public let target: Point
    public let distance: Double
    /// Normalized, top-left-origin region after the point-space safety margin.
    public let visibleRegion: CGRect

    /// Returns nil during zero-size/transient layout rather than poisoning the
    /// last valid camera. Geometry must describe the *actual* SceneKit view.
    public init?(size: CGSize, visibleRect: CGRect, zoom: Double = 1, margin: Double = 8) {
        guard [size.width, size.height, visibleRect.minX, visibleRect.minY,
               visibleRect.width, visibleRect.height].allSatisfy({ $0.isFinite }),
              size.width > 0, size.height > 0, visibleRect.width > 0, visibleRect.height > 0 else { return nil }
        let clipped = visibleRect.intersection(CGRect(origin: .zero, size: size))
        guard !clipped.isNull, clipped.width > 2, clipped.height > 2 else { return nil }
        let inset = min(margin.isFinite ? max(0, margin) : 8, Double(min(clipped.width, clipped.height)) * 0.1)
        let safe = clipped.insetBy(dx: CGFloat(inset), dy: CGFloat(inset))
        visibleRegion = CGRect(x: safe.minX / size.width, y: safe.minY / size.height,
                               width: safe.width / size.width, height: safe.height / size.height)
        let left = Double(visibleRegion.minX) * 2 - 1, right = Double(visibleRegion.maxX) * 2 - 1
        let bottom = 1 - Double(visibleRegion.maxY) * 2, top = 1 - Double(visibleRegion.minY) * 2
        let tangentY = tan(Self.verticalFieldOfView * .pi / 360)
        let tangentX = tangentY * Double(size.width / size.height)
        let points = Self.envelope.map { point -> Point in
            let relative = point - Self.center
            return .init(relative.dot(Self.right), relative.dot(Self.cameraUp), relative.dot(Self.back))
        }
        let xLower = points.map { $0.x / tangentX + right * $0.z }.max()!
        let xUpper = points.map { $0.x / tangentX + left * $0.z }.min()!
        let yLower = points.map { $0.y / tangentY + top * $0.z }.max()!
        let yUpper = points.map { $0.y / tangentY + bottom * $0.z }.min()!
        // Intersect every point's allowed camera-translation interval. The first
        // distance where all intervals overlap is the closest safe perspective
        // view. Solve translation too: fixing the old look-at in the opening's
        // center would unnecessarily shrink the featured character.
        let fittedDistance = max(Self.originalDistance,
                                 (xLower - xUpper) / (right - left),
                                 (yLower - yUpper) / (top - bottom))
        let zoom = zoom.isFinite ? min(1.5, max(0.7, zoom)) : 1
        distance = fittedDistance * zoom
        let offsetX = tangentX * (xLower + xUpper - (left + right) * distance) / 2
        let offsetY = tangentY * (yLower + yUpper - (bottom + top) * distance) / 2
        // Translate the camera and its target together, preserving the original
        // perspective orientation, rather than tilting toward a new look-at.
        let shift = Self.right * offsetX + Self.cameraUp * offsetY
        target = Self.center + shift
        position = target + Self.back * distance
        // Finite inputs can still overflow, or lose the opening's entire span
        // when normalized against an extreme finite viewport. SceneKit consumes
        // Float coordinates, so reject values that would overflow that conversion
        // too. The caller retains the last valid camera on failure.
        guard [distance, target.x, target.y, target.z, position.x, position.y, position.z]
            .allSatisfy({ $0.isFinite && abs($0) <= Double(Float.greatestFiniteMagnitude) }) else { return nil }
    }

    /// The same top-left convention as UIKit. Native tests also call SceneKit's
    /// projectPoint independently, so this equation cannot validate itself alone.
    public func project(_ point: Point, size: CGSize) -> CGPoint {
        let relative = point - position
        let depth = -relative.dot(Self.back)
        let tangentY = tan(Self.verticalFieldOfView * .pi / 360)
        return CGPoint(x: (1 + relative.dot(Self.right) / (depth * tangentY * Double(size.width / size.height))) * Double(size.width) / 2,
                       y: (1 - relative.dot(Self.cameraUp) / (depth * tangentY)) * Double(size.height) / 2)
    }
}
