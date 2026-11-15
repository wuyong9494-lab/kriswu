import Foundation

/// Consumes only the actual source trigger events. Clip phases and model ages
/// cannot synthesize a meditation start or a conditional StopSound.
struct DuelErlangMeditationAudioClock {
    enum Kind: Equatable { case start, stop }
    enum Reason: Equatable { case sourceTrigger, applicationLifecycle }
    struct Event {
        let frame: Int
        let sequence: Int
        let liveTick: Int
        let owner: Int
        let kind: Kind
    }
    struct Command: Equatable {
        let owner: Int
        let kind: Kind
        let reason: Reason
    }
    private var lastFrame: Int?
    private var consumed: Set<Int> = []
    private var activeOwners: Set<Int> = []

    mutating func reset() { self = Self() }

    mutating func consume(_ events: [Event], frame: Int, fighting: Bool,
                          paused: Bool, owners: Set<Int>) -> [Command] {
        guard !paused, frame >= 0, lastFrame.map({ frame >= $0 }) ?? true else { return [] }
        let selected = Set(owners.filter { (0..<2).contains($0) })
        var commands = activeOwners.subtracting(selected).sorted().map {
            Command(owner: $0, kind: .stop, reason: .applicationLifecycle)
        }
        activeOwners.formIntersection(selected)
        if lastFrame != frame { lastFrame = frame; consumed.removeAll(keepingCapacity: true) }
        for event in events.prefix(32) {
            guard event.frame == frame, event.liveTick >= 0, selected.contains(event.owner),
                  (0..<32).contains(event.sequence), consumed.insert(event.sequence).inserted else { continue }
            switch event.kind {
            case .start:
                guard fighting else { continue }
                activeOwners.insert(event.owner)
                commands.append(.init(owner: event.owner, kind: .start, reason: .sourceTrigger))
            case .stop:
                if activeOwners.remove(event.owner) != nil {
                    commands.append(.init(owner: event.owner, kind: .stop, reason: .sourceTrigger))
                }
            }
        }
        // Round completion cleans the application player. It is explicitly
        // separate from the source a195 StopSound event above.
        if !fighting {
            commands += activeOwners.sorted().map { .init(owner: $0, kind: .stop, reason: .applicationLifecycle) }
            activeOwners.removeAll(keepingCapacity: true)
        }
        return commands
    }
}
