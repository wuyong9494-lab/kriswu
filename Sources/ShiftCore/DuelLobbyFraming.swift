import Foundation

/// Perspective-only composition for the local showroom. The camera stays on
/// the known clear side of the foreground scenery. Lens shift and optical zoom
/// fit the measured controls without moving the eye through opaque geometry.
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
    /// Earlier app showroom pose, not a recovered original-game camera pose.
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
    public let verticalTangent: Double
    public let verticalFieldOfViewDegrees: Double
    /// Additive normalized-device-coordinate lens shift, with positive Y up.
    public let projectionOffset: CGPoint
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
        guard right > left, top > bottom else { return nil }
        let aspect = Double(size.width / size.height)
        guard aspect.isFinite, aspect > 0 else { return nil }
        let points = Self.envelope.map { point -> Point in
            let relative = point - Self.originalPosition
            let depth = -relative.dot(Self.back)
            return .init(relative.dot(Self.right) / depth, relative.dot(Self.cameraUp) / depth, depth)
        }
        guard points.allSatisfy({ $0.z > 0 && $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let xMinimum = points.map(\.x).min()!, xMaximum = points.map(\.x).max()!
        let yMinimum = points.map(\.y).min()!, yMaximum = points.map(\.y).max()!
        // A point's angular coordinate is fixed for this eye position. Solve
        // the smallest perspective lens that fits both angular spans, then
        // shift their center into the actual opening. Do not move or hide the
        // stage or fighter. The 701 distance solver crossed the Bort_011 rail.
        let fittedTangent = max(tan(Self.verticalFieldOfView * .pi / 360),
                                (xMaximum - xMinimum) / (aspect * (right - left)),
                                (yMaximum - yMinimum) / (top - bottom))
        let zoom = zoom.isFinite ? min(1.5, max(0.7, zoom)) : 1
        verticalTangent = fittedTangent * zoom
        verticalFieldOfViewDegrees = atan(verticalTangent) * 360 / .pi
        projectionOffset = CGPoint(x: (left + right) / 2 - (xMinimum + xMaximum) / (2 * verticalTangent * aspect),
                                   y: (bottom + top) / 2 - (yMinimum + yMaximum) / (2 * verticalTangent))
        distance = Self.originalDistance
        target = Self.center
        position = Self.originalPosition
        // Finite inputs can still overflow, or lose the opening's entire span
        // when normalized against an extreme finite viewport. SceneKit consumes
        // Float coordinates, so reject values that would overflow that conversion
        // too. The caller retains the last valid camera on failure.
        guard [verticalTangent, verticalFieldOfViewDegrees, Double(projectionOffset.x), Double(projectionOffset.y)]
            .allSatisfy({ $0.isFinite && abs($0) <= Double(Float.greatestFiniteMagnitude) }),
              verticalTangent > 0, Float(verticalFieldOfViewDegrees) < 180,
              Float(1 / verticalTangent) > 0, Float(1 / (verticalTangent * aspect)) > 0 else { return nil }
    }

    /// The same top-left convention as UIKit. Native tests also call SceneKit's
    /// projectPoint independently, so this equation cannot validate itself alone.
    public func project(_ point: Point, size: CGSize) -> CGPoint {
        let relative = point - position
        let depth = -relative.dot(Self.back)
        return CGPoint(x: (1 + relative.dot(Self.right) / (depth * verticalTangent * Double(size.width / size.height))
                           + Double(projectionOffset.x)) * Double(size.width) / 2,
                       y: (1 - relative.dot(Self.cameraUp) / (depth * verticalTangent)
                           - Double(projectionOffset.y)) * Double(size.height) / 2)
    }
}
