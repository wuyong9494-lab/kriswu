// Additive, deterministic third-fighter prototype. No shared roster registration.
public struct DuelErlangState: Equatable, Codable, Sendable {
    public enum Phase: String, Codable, Sendable { case base, meditating, ascended }
    public enum Mode: String, Codable, Sendable { case versus, teamRaid }
    public enum Input: Equatable, Sendable {
        case weaponHit, beginMeditation, interruptMeditation, finishMeditation, tick, ascend, hound, nextRound, nextMatch
    }
    public enum Cue: String, Equatable, Sendable {
        case meditationStarted, meditationInterrupted, ascension, houndRush
    }
    public private(set) var phase: Phase = .base
    public private(set) var light = 0
    public private(set) var meditationTicks = 0
    public private(set) var houndCooldown = 0
    public private(set) var meditationCooldown: Int
    public let mode: Mode

    // Preview tuning, NOT a claim about the publisher’s highest-level values.
    public struct PreviewTuning: Equatable, Sendable {
        public let weaponLight = 5
        public let meditationTicksPerPulse = 12
        public let meditationLight = 3
        public let houndCooldownTicks = 90
        public let initialMeditationCooldownTicks = 30
        public let meditationCooldownTicks = 48
        public init() {}
    }

    public init(mode: Mode, tuning: PreviewTuning = .init()) {
        self.mode = mode
        self.meditationCooldown = tuning.initialMeditationCooldownTicks
    }

    // Used only by the Level 6 fixture driver, which owns action gating.
    mutating func clearAvatarLight() { if phase == .ascended { light = 0 } }
    mutating func endAvatarAfterLethalHit() {
        guard phase == .ascended else { return }
        phase = .base
        light = 0
        meditationTicks = 0
    }
    mutating func restoreAvatarLight(_ amount: Int) {
        if phase == .ascended { light = min(100, light + amount) }
    }

    mutating func shortenMeditationCooldown(by ticks: Int) {
        meditationCooldown = max(0, meditationCooldown - ticks)
    }

    /// Drive from authoritative fixed simulation steps, not the render loop.
    /// Only an actual accepted weapon hit should produce .weaponHit.
    /// Called on actual host input edges, not on every frame of a held button.
    @discardableResult
    public mutating func apply(_ input: Input, tuning: PreviewTuning = .init()) -> Cue? {
        switch input {
        case .weaponHit:
            guard phase == .base else { return nil }
            light = min(100, light + tuning.weaponLight)
        case .beginMeditation:
            guard phase == .base, light < 100, meditationCooldown == 0 else { return nil }
            phase = .meditating
            meditationTicks = 0
            return .meditationStarted
        case .interruptMeditation, .finishMeditation:
            guard phase == .meditating else { return nil }
            phase = .base
            meditationTicks = 0
            meditationCooldown = tuning.meditationCooldownTicks
            if input == .interruptMeditation { return .meditationInterrupted }
        case .tick:
            houndCooldown = max(0, houndCooldown - 1)
            meditationCooldown = max(0, meditationCooldown - 1)
            if phase == .meditating {
                meditationTicks += 1
                if meditationTicks >= tuning.meditationTicksPerPulse {
                    light = min(100, light + tuning.meditationLight)
                    meditationTicks = 0
                    if light == 100 {
                        phase = .base
                        meditationCooldown = tuning.meditationCooldownTicks
                    }
                }
            }
        case .ascend:
            guard phase == .base, light == 100 else { return nil }
            phase = .ascended
            return .ascension
        case .hound:
            guard phase == .base, houndCooldown == 0 else { return nil }
            houndCooldown = tuning.houndCooldownTicks
            return .houndRush
        case .nextRound:
            if mode == .teamRaid && phase == .ascended {
                houndCooldown = 0
            } else {
                self = Self(mode: mode, tuning: tuning)
            }
        case .nextMatch:
            self = Self(mode: mode, tuning: tuning)
        }
        return nil
    }
}
