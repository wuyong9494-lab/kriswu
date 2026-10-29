/// Logical audio scene is independent of renderer attachment and app suspension.
public struct ArenaAudioState: Sendable {
    public enum Scene: Equatable, Sendable { case off, lobby, battle, result }
    public enum Pause: Hashable, Sendable { case background, interruption, renderer }
    public private(set) var scene: Scene = .off
    public private(set) var pauses: Set<Pause> = []
    public private(set) var lobbyOpen = false
    public init() {}
    public var inMatch: Bool { scene == .battle || scene == .result }
    public var canPlay: Bool { pauses.isEmpty && scene != .off }
    public mutating func enterLobby() {
        lobbyOpen = true
        if !inMatch { scene = .lobby }
    }
    public mutating func leaveLobby() {
        lobbyOpen = false
        if !inMatch { scene = .off }
    }
    public mutating func begin() {
        if !inMatch { scene = .battle }
        pauses.remove(.renderer)
    }
    public mutating func finish() { if inMatch { scene = .result } }
    public mutating func end() {
        scene = lobbyOpen ? .lobby : .off
        pauses.remove(.renderer)
    }
    public mutating func pause(_ reason: Pause) { pauses.insert(reason) }
    public mutating func resume(_ reason: Pause) { pauses.remove(reason) }
}
