import Foundation

/// A measured or explicitly adapted response to one confirmed contact.
/// Units are integer millimetres and 60 Hz simulation ticks. These values do
/// not claim to reproduce a source game's physics without separate evidence.
public struct DuelImpactResponse: Codable, Equatable, Sendable {
    public let distanceMillimeters: Int
    public let durationTicks: Int
    public let launchVelocityMillimetersPerTick: Int
    public let gravityMillimetersPerTickSquared: Int

    public init(distanceMillimeters: Int, durationTicks: Int,
                launchVelocityMillimetersPerTick: Int = 0,
                gravityMillimetersPerTickSquared: Int = DuelGame.gravity) {
        self.distanceMillimeters = distanceMillimeters
        self.durationTicks = durationTicks
        self.launchVelocityMillimetersPerTick = launchVelocityMillimetersPerTick
        self.gravityMillimetersPerTickSquared = gravityMillimetersPerTickSquared
    }

    public var isValid: Bool {
        guard (0...10_000).contains(distanceMillimeters), (1...600).contains(durationTicks),
              (0...1_000).contains(launchVelocityMillimetersPerTick),
              (1...1_000).contains(gravityMillimetersPerTickSquared) else { return false }
        let velocity = launchVelocityMillimetersPerTick, gravity = gravityMillimetersPerTickSquared
        let ascentTicks = (velocity + gravity - 1) / gravity
        // Bound the discrete apex, not a continuous approximation. All
        // products are small after the explicit scalar limits above.
        let apex = ascentTicks * velocity - gravity * ascentTicks * (ascentTicks - 1) / 2
        return apex <= DuelImpactMotion.maximumHeightMillimeters
    }
}

/// State owned by the authoritative simulation. Drawing, audio and wall-clock
/// time cannot consume an impulse. Fighter.y/velocityY retain vertical state;
/// this object retains the horizontal schedule and its wall cancellation.
struct DuelImpactMotion: Equatable, Sendable {
    static let maximumHeightMillimeters = 10_000

    struct Sample: Equatable, Sendable {
        let x: Int
        let y: Int
        let velocityY: Int
        let landed: Bool
    }

    let response: DuelImpactResponse
    let direction: Int
    private(set) var elapsedTicks = 0
    private(set) var appliedHorizontalDistance = 0
    private(set) var horizontalStopped = false

    init?(response: DuelImpactResponse, direction: Int) {
        guard response.isValid, direction == -1 || direction == 1 else { return nil }
        self.response = response; self.direction = direction
    }

    var horizontalFinished: Bool { horizontalStopped || elapsedTicks >= response.durationTicks }

    mutating func advance(x: Int, y: Int, velocityY: Int) -> Sample {
        elapsedTicks = min(response.durationTicks, elapsedTicks + 1)
        var nextX = min(DuelGame.rightWall, max(DuelGame.leftWall, x))
        if !horizontalStopped {
            let duration = response.durationTicks, tick = elapsedTicks
            // Integer cumulative deceleration preserves the exact total at
            // the last tick. Rounding each velocity independently would drift.
            let desired = response.distanceMillimeters * tick * (2 * duration - tick + 1)
                / (duration * (duration + 1))
            let delta = max(0, desired - appliedHorizontalDistance)
            let unclamped = nextX + direction * delta
            let clamped = min(DuelGame.rightWall, max(DuelGame.leftWall, unclamped))
            appliedHorizontalDistance += abs(clamped - nextX)
            nextX = clamped
            if clamped != unclamped { horizontalStopped = true }
        }

        let oldY = min(Self.maximumHeightMillimeters, max(0, y))
        guard oldY > 0 || velocityY > 0 else {
            return .init(x: nextX, y: 0, velocityY: 0, landed: false)
        }
        // The public response bounds a fresh launch. The defensive clamp also
        // keeps interrupted/externally supplied fighter state within the same
        // network projection envelope, without integer conversion overflow.
        let velocity = min(2_000, max(-2_000, velocityY))
        let nextY = min(Self.maximumHeightMillimeters, max(0, oldY + velocity))
        let landed = nextY == 0 && oldY > 0
        return .init(x: nextX, y: nextY,
                     velocityY: nextY == 0 ? 0 : velocity - response.gravityMillimetersPerTickSquared,
                     landed: landed)
    }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.int(response.distanceMillimeters); try writer.int(response.durationTicks)
        try writer.int(response.launchVelocityMillimetersPerTick)
        try writer.int(response.gravityMillimetersPerTickSquared)
        try writer.int(direction); try writer.int(elapsedTicks)
        try writer.int(appliedHorizontalDistance); try writer.bool(horizontalStopped)
    }
}
