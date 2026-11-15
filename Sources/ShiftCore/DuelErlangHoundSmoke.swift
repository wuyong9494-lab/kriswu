/// Cosmetic state only. These lifetimes do not come from original gameplay.
public struct DuelErlangHoundSmoke: Equatable, Encodable, Sendable {
    public private(set) var castID: UInt64 = 0
    public private(set) var trail = false
    public var spawnPuff: Bool { spawnTicks > 0 }
    public var dismissPuff: Bool { dismissTicks > 0 }

    private var spawnTicks = 0
    private var dismissTicks = 0
    private static let puffDuration = 3

    public init() {}

    mutating func clear() {
        trail = false
        spawnTicks = 0
        dismissTicks = 0
    }

    mutating func observe(_ pose: DuelErlangHoundPresentation, roundFinished: Bool) {
        if roundFinished || pose.outcome == .cancelled {
            clear()
            return
        }
        spawnTicks = max(0, spawnTicks - 1)
        dismissTicks = max(0, dismissTicks - 1)
        if pose.started && pose.visible && pose.castID != castID {
            castID = pose.castID
            trail = true
            spawnTicks = Self.puffDuration
            dismissTicks = 0
        } else if trail && !pose.visible {
            trail = false
            spawnTicks = 0
            dismissTicks = Self.puffDuration
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(castID, forKey: .castID)
        try c.encode(trail, forKey: .trail)
        try c.encode(spawnPuff, forKey: .spawnPuff)
        try c.encode(dismissPuff, forKey: .dismissPuff)
    }

    private enum CodingKeys: String, CodingKey { case castID, trail, spawnPuff, dismissPuff }
}
