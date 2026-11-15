import Foundation

/// The original Imperial Spear paired heavy. Asset capabilities and the
/// PostHit selector remain distinct: merely owning a passive clip cannot
/// initiate the pair or create its second damage component.
public enum DuelImperialHeavyMotion {
    public static let sourceContract = "IMPERIAL_SPEAR-4795-4797-38157-38302-v1"
    public static let configurationSHA256 = "fb54e61b150349f0a02735ee8354ed6fe21a4263862dd6162e0123583705e8b0"
    public static let bundle = "baccadc1bc62c24fcf83246b63fd6c17.bin"
    public static let activeRole = "imperialHeavyActive"
    public static let passiveRole = "imperialHeavyPassive"
    public static let mirroredRole = "imperialHeavyPassiveMirrored"
    public static let activeName = "imperial_spear_heavy_slash_active"
    public static let missSHA256 = "4cff0991d7d0139d72aa393ea77a6d6adacab7bbfe8b0f0ffd32e8d395e3eb64"
    public static let activeSHA256 = "493596ad52f62dd88ba6a0a6f34760b404cce0cf5eca2c8e1ca8a490b39ab979"
    public static let passiveSHA256 = "75e0ec9ac3674098657aac66d6c3ee51b66f342234aae2a7b33fc3a666a6c411"
    public static let captureTicks = 44...63
    public static let activeEndTick = 196
    public static let passiveEndTick = 132
    public static let floorfallTick = 112
    /// Original Align Shift.X is -200 cm. The human arena rig uses the
    /// existing 9.2 mm/source-cm adapter; this is not a native unit change.
    public static let passiveShiftMillimeters = -1840.0

    private static func matches(_ clip: DuelWeaponClip?, sha: String, frames: Int,
                                end: Int, needsToes: Bool) -> Bool {
        guard let clip, clip.sha256 == sha, clip.bundle == bundle,
              clip.frames == frames, clip.ticks == (frames - 1) * 2,
              clip.sourceEndEventTick == end, clip.tracks.samplesPerSourceFrame == 2,
              clip.tracks.pelvis?.count == clip.ticks + 1,
              clip.tracks.centerOfMass?.count == clip.ticks + 1,
              !(clip.tracks.hurtCapsules ?? []).isEmpty else { return false }
        return !needsToes || (clip.tracks.toeL?.count == clip.ticks + 1 &&
                             clip.tracks.toeR?.count == clip.ticks + 1)
    }
    public static func matchesAttacker(profile: DuelWeaponProfile) -> Bool {
        profile.isErlang &&
        matches(profile.clip(role: "heavy"), sha: missSHA256, frames: 77, end: 144, needsToes: true) &&
        matches(profile.clip(role: activeRole), sha: activeSHA256, frames: 103, end: activeEndTick, needsToes: true) &&
        profile.clip(role: activeRole)?.name == activeName
    }
    public static func matchesVictim(profile: DuelWeaponProfile) -> Bool {
        matches(profile.clip(role: passiveRole), sha: passiveSHA256, frames: 71,
                end: passiveEndTick, needsToes: false) &&
        matches(profile.clip(role: mirroredRole), sha: passiveSHA256, frames: 71,
                end: passiveEndTick, needsToes: false) &&
        profile.clip(role: passiveRole)?.name == "imperial_spear_heavy_slash_passive" &&
        ["imperial_spear_heavy_slash_passive_mirror", "imperial_spear_heavy_slash_passive_mirrored"]
            .contains(profile.clip(role: mirroredRole)?.name ?? "")
    }
    public static func matchesActiveRule(_ rule: DuelCombatAttackRule?, profile: DuelWeaponProfile) -> Bool {
        guard matchesAttacker(profile: profile), let rule, rule.command == .heavy,
              rule.clipName == activeName, rule.strikes.count == 1,
              let power = profile.erlangRules?.normalizedWeaponPower else { return false }
        let strike = rule.strikes[0]
        // Record8: frames82...85, one original left capsule, .08 WeaponDamage.
        // Recoil, block attenuation and hit-stop retain the declared arena rule.
        return strike.id == 0 && strike.startTick == 162 && strike.endTick == 169 &&
            strike.weaponSides == ["left"] && strike.collisionEdgeIDs == ["Spear_Attacking_Edge_l"] &&
            strike.damageKind == .weapon && strike.damage == power * 8 / 100
    }
    public static func canPair(attacker: DuelWeaponProfile, victim: DuelWeaponProfile) -> Bool {
        guard matchesAttacker(profile: attacker), matchesVictim(profile: victim),
              let miss = attacker.clip(role: "heavy"),
              let strike = attacker.combatRules?.rule(command: .heavy, clipName: miss.name)?.strikes.first,
              strike.startTick == 44, strike.endTick == 63,
              strike.collisionEdgeIDs == ["Spear_Attacking_Edge_l"] else { return false }
        return matchesActiveRule(attacker.combatRules?.rule(command: .heavy, clipName: activeName), profile: attacker)
    }

    public struct Selection: Equatable, Sendable {
        public let baseMirror: Bool
        public let sourceAliasFlipsMirror: Bool
        public var renderedMirror: Bool { baseMirror != sourceAliasFlipsMirror }
        public var role: String { renderedMirror ? mirroredRole : passiveRole }
    }
    /// lock4797's Me is the victim. f65 reads its own foot_l/foot_r, whereas
    /// Enemy supplies the attacker's COM and toe order. Operator21 is <=,
    /// operator18 is >, including the original equality boundaries.
    public static func selection(attackerCOMX: Double, victimCOMX: Double,
                                 attackerToeLX: Double, attackerToeRX: Double,
                                 victimFootLX: Double, victimFootRX: Double,
                                 victimDirection: Int) -> Selection? {
        guard [attackerCOMX, victimCOMX, attackerToeLX, attackerToeRX, victimFootLX, victimFootRX]
            .allSatisfy(\.isFinite), victimDirection == 1 || victimDirection == -1 else { return nil }
        let base = victimDirection == 1 ? victimFootLX <= victimFootRX : victimFootLX >= victimFootRX
        let toeForward = attackerToeLX > attackerToeRX
        let normal = attackerCOMX <= victimCOMX ? toeForward == base : toeForward != base
        // 38157 first resolves base mirror, applies the nullable -1 toggle,
        // then resolves that override. Alias alone is not the baked pose.
        return .init(baseMirror: base, sourceAliasFlipsMirror: !normal)
    }
}

/// Two independent source clocks sharing a confirmed PostHit. The active
/// actor inherits the Miss source position; the victim starts at zero. The
/// arena preserves its normalized actor root across that transition. The
/// separate native Me.Pivot re-alignment has not been asserted equivalent.
public struct DuelImperialHeavyState: Equatable, Sendable {
    public let attacker: Int
    public var target: Int { 1 - attacker }
    public let initialActiveTick: Int
    public var age: Int = 0
    public let attackerOriginXMillimeters: Double
    public let victimOriginXMillimeters: Double
    public let attackerDirection: Int
    public let victimDirection: Int
    public let baseMirror: Bool
    public let sourceAliasFlipsMirror: Bool
    public var attackerReleased = false
    public var victimReleased = false
    public var activeTick: Int { initialActiveTick + age }
    public var victimRole: String {
        baseMirror != sourceAliasFlipsMirror ? DuelImperialHeavyMotion.mirroredRole : DuelImperialHeavyMotion.passiveRole
    }
    public var finished: Bool { attackerReleased && victimReleased }
    public func owns(_ index: Int) -> Bool { index == attacker ? !attackerReleased : index == target && !victimReleased }
    public var suppressesBodySeparation: Bool {
        (!attackerReleased && activeTick <= 173) || (!victimReleased && age >= 46)
    }
    public init(attacker: Int, initialActiveTick: Int, attackerOriginXMillimeters: Double,
                victimOriginXMillimeters: Double, attackerDirection: Int, victimDirection: Int,
                selection: DuelImperialHeavyMotion.Selection) {
        self.attacker = attacker; self.initialActiveTick = initialActiveTick
        self.attackerOriginXMillimeters = attackerOriginXMillimeters
        self.victimOriginXMillimeters = victimOriginXMillimeters
        self.attackerDirection = attackerDirection; self.victimDirection = victimDirection
        self.baseMirror = selection.baseMirror; self.sourceAliasFlipsMirror = selection.sourceAliasFlipsMirror
    }
    public mutating func advance() {
        age += 1
        if activeTick > DuelImperialHeavyMotion.activeEndTick { attackerReleased = true }
        if age > DuelImperialHeavyMotion.passiveEndTick { victimReleased = true }
    }
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.string(DuelImperialHeavyMotion.sourceContract)
        try writer.int(attacker); try writer.int(initialActiveTick); try writer.int(age)
        try writer.double(attackerOriginXMillimeters); try writer.double(victimOriginXMillimeters)
        try writer.int(attackerDirection); try writer.int(victimDirection)
        try writer.bool(baseMirror); try writer.bool(sourceAliasFlipsMirror)
        try writer.bool(attackerReleased); try writer.bool(victimReleased)
    }
}
