import Foundation

/// Presentation observations emitted by actual source trigger transitions.
/// They do not create damage, move actors or advance simulation time.
public struct DuelErlangSourceEvent: Equatable, Sendable {
    public enum Kind: String, Sendable { case meditationStarted, meditationStopped }
    public let frame: Int
    public let sequence: Int
    public let liveTick: Int
    public let owner: Int
    public let kind: Kind
    public init(frame: Int, sequence: Int, liveTick: Int, owner: Int, kind: Kind) {
        self.frame = frame; self.sequence = sequence; self.liveTick = liveTick
        self.owner = owner; self.kind = kind
    }
}
