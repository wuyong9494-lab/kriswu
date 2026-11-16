import Foundation

/// Presentation-only consumption of accepted D13 events. A display callback
/// cannot advance a move or replay sounds from an already consumed match frame.
public struct DuelSerpentAudioTimeline: Sendable {
    public enum Operation: Equatable, Sendable { case play(loop: Bool), stop }
    public enum Reason: Equatable, Sendable { case sourceEvent, applicationLifecycle }
    public struct Command: Equatable, Sendable {
        public let owner: Int
        public let identifier: String
        public let operation: Operation
        public let reason: Reason
    }
    private struct Sound: Hashable, Sendable {
        let owner: Int
        let identifier: String
    }
    /// Pinned original Sound routes, not substitutes for missing PCM assets.
    public static let sounds: [String: Bool] = [
        "set_d13/poison_energy_cast@Battle@Movement": false,
        "shadow_moves/mind_throw/mind_throw_whoosh_1@Battle@Movement": false,
        "set_d13/poison_energy_hit_hiss@Battle@Movement": false,
        "set_d13/poison_rain_bottle@Battle@Movement": false,
        DuelSerpentRainRuntime.rainSound: true,
        DuelSerpentRainRuntime.rainOutSound: false
    ]
    private var lastFrame: Int?
    private var consumed: Set<Int> = []
    private var loops: Set<Sound> = []

    public init() {}

    public mutating func consume(_ events: [DuelSerpentMatchEvent], frame: Int,
                                 fighting: Bool, paused: Bool, owners: Set<Int>) -> [Command] {
        guard !paused, frame >= 0, lastFrame.map({ frame >= $0 }) ?? true else { return [] }
        let selected = Set(owners.filter { (0..<2).contains($0) })
        var commands = stop(loops.filter { !selected.contains($0.owner) })
        if lastFrame != frame { lastFrame = frame; consumed.removeAll(keepingCapacity: true) }
        for (sequence, event) in events.prefix(256).enumerated() {
            guard selected.contains(event.owner), event.liveTick >= 0,
                  consumed.insert(sequence).inserted else { continue }
            let identifier: String
            let stopping: Bool
            switch event.effect {
            case .action(let action):
                guard action.liveTick == event.liveTick, case .sound(let sound) = action.effect else { continue }
                identifier = sound; stopping = false
            case .model(.soundStarted(let sound)): identifier = sound; stopping = false
            case .model(.soundStopped(let sound)): identifier = sound; stopping = true
            default: continue
            }
            guard let looping = Self.sounds[identifier] else { continue }
            let sound = Sound(owner: event.owner, identifier: identifier)
            if stopping {
                if loops.remove(sound) != nil {
                    commands.append(.init(owner: event.owner, identifier: identifier,
                                          operation: .stop, reason: .sourceEvent))
                }
            } else {
                // A finishing step may still emit its real one-shot. It cannot
                // start another infinite player after the round has ended.
                guard !looping || fighting else { continue }
                if looping { loops.insert(sound) }
                commands.append(.init(owner: event.owner, identifier: identifier,
                                      operation: .play(loop: looping), reason: .sourceEvent))
            }
        }
        if !fighting { commands += stop(loops) }
        return commands
    }

    /// Explicit scene/session teardown. Audio owners apply the returned stops
    /// before discarding players; pause/resume must not call this reset.
    public mutating func finish() -> [Command] {
        let result = stop(loops)
        self = Self()
        return result
    }

    private mutating func stop(_ sounds: Set<Sound>) -> [Command] {
        loops.subtract(sounds)
        return sounds.sorted {
            $0.owner == $1.owner ? $0.identifier < $1.identifier : $0.owner < $1.owner
        }.map { .init(owner: $0.owner, identifier: $0.identifier,
                      operation: .stop, reason: .applicationLifecycle) }
    }
}
