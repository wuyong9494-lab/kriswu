import Foundation

public struct DuelSerpentMatchEvent: Equatable, Sendable {
    public enum Effect: Equatable, Sendable {
        case action(DuelSerpentActionRuntime.Event)
        case model(DuelSerpentRainRuntime.Effect)
    }
    public let owner, liveTick: Int
    public let effect: Effect
}

/// Authenticated ordinary D13 match adapter. The App must separately authenticate
/// and load these models; this binding alone does not enable a selection or a
/// network loadout. Enhanced/Bloom abilities are not represented as fallback moves.
public struct DuelSerpentCombatBinding: Equatable, Codable, Sendable {
    public struct Control: Equatable, Codable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case uninterrupt, unbreakable, blocking, throwable, invincible
        }
        public let clip: String
        public let kind: Kind
        public let startTick, endTick: Int
    }
    public let schema, sourceSHA256: String
    /// Explicit arena normalization; neither value is a recovered equipment stat.
    public let maximumHealth, level, rangedUsages: Int
    public let raidDamageAmplifier: Double
    public let controls: [Control]
    public let bottle: DuelSerpentBottleMotion
    public let cloud: DuelSerpentCloudMotion
    public enum Failure: Error { case identity, configuration, controls }

    public func validate(profile: DuelWeaponProfile) throws {
        guard schema == "d13-ordinary-match-binding-v1",
              sourceSHA256 == "d169d518d0133ee6180c81d11edd5b5c11816e91886b7aae2eed54806f775d37",
              profile.panguRules == nil, profile.triadRules == nil, profile.erlangRules == nil,
              profile.combatRules?.id == "serpent-d13-source-shuangou-geometry-v1"
        else { throw Failure.identity }
        _ = try DuelSerpentActionBinding(profile: profile)
        try bottle.validate(); try cloud.validate()
        guard (1...1_000_000).contains(maximumHealth), (2...6).contains(level),
              (0...1_000).contains(rangedUsages), raidDamageAmplifier.isFinite,
              raidDamageAmplifier > 0, raidDamageAmplifier <= 1_000_000
        else { throw Failure.configuration }
        guard !controls.isEmpty, controls.count <= 512 else { throw Failure.controls }
        var keys = Set<String>()
        for value in controls {
            guard let clip = profile.clip(named: value.clip), value.startTick >= 0,
                  value.startTick <= value.endTick, value.endTick <= clip.ticks,
                  keys.insert("\(value.clip)/\(value.kind.rawValue)/\(value.startTick)/\(value.endTick)").inserted
            else { throw Failure.controls }
        }
        // Distinguish input lock from armor: poison has no Unbreakable window;
        // the bottle's armor is only its original frames 5 through 20.
        for (clip, kind, start, end) in [
            ("d13_ability", Control.Kind.uninterrupt, 0, 215),
            ("d13_ability", .blocking, 216, 236),
            ("d13_ability", .throwable, 204, 236),
            ("d13_bottle_throw", .uninterrupt, 0, 105),
            ("d13_bottle_throw", .blocking, 106, 112),
            ("d13_bottle_throw", .throwable, 94, 112),
            ("d13_bottle_throw", .unbreakable, 8, 39)
        ] {
            guard controls.filter({ $0.clip == clip && $0.kind == kind }).count == 1,
                  controls.contains(where: { $0.clip == clip && $0.kind == kind &&
                      $0.startTick == start && $0.endTick == end }) else { throw Failure.controls }
        }
        guard !controls.contains(where: { $0.clip == "d13_ability" && $0.kind == .unbreakable })
        else { throw Failure.controls }
    }

    public func contains(_ kind: Control.Kind, clip: String, tick: Int) -> Bool {
        controls.contains { $0.kind == kind && $0.clip == clip && ($0.startTick...$0.endTick).contains(tick) }
    }

    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.string(schema); try writer.string(sourceSHA256)
        try writer.int(maximumHealth); try writer.int(level); try writer.int(rangedUsages)
        try writer.double(raidDamageAmplifier)
        try writer.array(controls, limit: 512) { w, c in
            try w.string(c.clip); try w.string(c.kind.rawValue)
            try w.int(c.startTick); try w.int(c.endTick)
        }
        try bottle.appendReplayState(to: &writer)
        try cloud.appendReplayState(to: &writer)
    }
}
