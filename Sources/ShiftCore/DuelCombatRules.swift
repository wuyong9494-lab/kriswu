import Foundation

/// One independently timed contact opportunity. A second blade or a later
/// strike needs its own ID; render frames and particle callbacks never create
/// additional damage. Ticks are authoritative 60 Hz simulation ticks.
public struct DuelCombatStrike: Equatable, Codable, Sendable {
    public let id: Int
    public let startTick: Int
    public let endTick: Int
    public let weaponSides: [String]
    public let damage: Int
    public let blockedDamage: Int
    public let knocksDown: Bool
    public let hitStopTicks: Int
    public let blockedHitStopTicks: Int
    public let impact: DuelImpactResponse
    public let blockedImpact: DuelImpactResponse
    public let collisionEdgeIDs: [String]?

    public init(id: Int, startTick: Int, endTick: Int, weaponSides: [String],
                damage: Int, blockedDamage: Int, knocksDown: Bool,
                hitStopTicks: Int, blockedHitStopTicks: Int,
                impact: DuelImpactResponse, blockedImpact: DuelImpactResponse,
                collisionEdgeIDs: [String]? = nil) {
        self.id = id; self.startTick = startTick; self.endTick = endTick
        self.weaponSides = weaponSides; self.damage = damage; self.blockedDamage = blockedDamage
        self.knocksDown = knocksDown; self.hitStopTicks = hitStopTicks
        self.blockedHitStopTicks = blockedHitStopTicks
        self.impact = impact; self.blockedImpact = blockedImpact
        self.collisionEdgeIDs = collisionEdgeIDs
    }

    public func isActive(at tick: Int) -> Bool { tick >= startTick && tick <= endTick }
}

/// Binds gameplay to a particular command AND animation stage. A combo stage
/// cannot accidentally inherit another stage's contact window or damage.
public struct DuelCombatAttackRule: Equatable, Codable, Sendable {
    public let command: DuelWeaponCommand
    public let clipName: String
    public let strikes: [DuelCombatStrike]

    public init(command: DuelWeaponCommand, clipName: String, strikes: [DuelCombatStrike]) {
        self.command = command; self.clipName = clipName; self.strikes = strikes
    }
}

/// A declared source is not proof that the original game has been recovered.
/// Asset authentication and reference acceptance must verify these receipts.
/// Legacy catalogs retain their explicitly named application adaptation.
public struct DuelCombatRuleProfile: Equatable, Codable, Sendable {
    public enum Basis: String, Codable, Sendable {
        case applicationAdaptation, referenceMeasurement, sourceConfiguration
    }
    public let id: String
    public let basis: Basis
    public let sourceVersion: String
    public let sourceSHA256: String?
    public let evidence: [String]
    public let attacks: [DuelCombatAttackRule]

    public init(id: String, basis: Basis, sourceVersion: String,
                sourceSHA256: String? = nil, evidence: [String], attacks: [DuelCombatAttackRule]) {
        self.id = id; self.basis = basis; self.sourceVersion = sourceVersion
        self.sourceSHA256 = sourceSHA256; self.evidence = evidence; self.attacks = attacks
    }

    public func rule(command: DuelWeaponCommand, clipName: String) -> DuelCombatAttackRule? {
        attacks.first { $0.command == command && $0.clipName == clipName }
    }

    public enum ValidationError: Error, Equatable {
        case provenance, incomplete, duplicateAttack, invalidStrike
    }

    public func validate(for profile: DuelWeaponProfile) throws {
        guard !id.isEmpty, id.utf8.count <= 128,
              !sourceVersion.isEmpty, sourceVersion.utf8.count <= 256,
              evidence.count <= 16,
              evidence.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }),
              basis == .applicationAdaptation || !evidence.isEmpty else {
            throw ValidationError.provenance
        }
        if let sourceSHA256 {
            guard sourceSHA256.utf8.count == 64,
                  sourceSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw ValidationError.provenance
            }
        } else if basis == .sourceConfiguration { throw ValidationError.provenance }

        let expected = Self.legacy(for: profile).attacks
        guard !attacks.isEmpty, attacks.count <= 128,
              expected.allSatisfy({ required in
                  rule(command: required.command, clipName: required.clipName) != nil
              }) else { throw ValidationError.incomplete }
        var identities = Set<String>()
        for attack in attacks {
            let identity = attack.command.rawValue + ":" + attack.clipName
            guard identities.insert(identity).inserted else { throw ValidationError.duplicateAttack }
            guard expected.contains(where: { $0.command == attack.command && $0.clipName == attack.clipName }),
                  let clip = profile.clip(named: attack.clipName),
                  !attack.strikes.isEmpty, attack.strikes.count <= 32 else {
                throw ValidationError.incomplete
            }
            let duration = attack.command == .shadow ? DuelShadowRules.duration(katana: profile.isKatana) : clip.ticks
            var strikeIDs = Set<Int>()
            for strike in attack.strikes {
                let physicalWeapon = !attack.command.rawValue.hasPrefix("kick") && attack.command != .shadow
                guard (0...1023).contains(strike.id), strikeIDs.insert(strike.id).inserted,
                      strike.startTick >= 1, strike.startTick <= strike.endTick,
                      strike.endTick <= duration,
                      (0...1_000_000).contains(strike.damage),
                      (0...1_000_000).contains(strike.blockedDamage),
                      (0...60).contains(strike.hitStopTicks),
                      (0...60).contains(strike.blockedHitStopTicks),
                      Set(strike.weaponSides).count == strike.weaponSides.count,
                      Set(strike.weaponSides).isSubset(of: Set(profile.activeWeaponSides)),
                      physicalWeapon ? !strike.weaponSides.isEmpty : strike.weaponSides.isEmpty,
                      strike.impact.isValid, strike.blockedImpact.isValid,
                      strike.blockedImpact.launchVelocityMillimetersPerTick == 0 else {
                    throw ValidationError.invalidStrike
                }
                if let edges = strike.collisionEdgeIDs {
                    let available = (clip.tracks.collisionEdges ?? []).filter { strike.weaponSides.contains($0.side) }.map(\.id) +
                        (clip.tracks.hurtCapsules ?? []).map(\.id)
                    guard attack.command != .shadow, !edges.isEmpty, edges.count <= 32,
                          Set(edges).count == edges.count,
                          Set(edges).isSubset(of: Set(available)) else { throw ValidationError.invalidStrike }
                }
                // The current provisional shadow interpreter has its own
                // bounded dash/throw/return timeline. Reject windows that it
                // cannot execute; changing numbers is not an implementation
                // of a different character's shadow or light-energy skill.
                if attack.command == .shadow {
                    guard strike.startTick >= DuelShadowRules.startup,
                          strike.endTick < (profile.isKatana ? 40 : 48) else {
                        throw ValidationError.invalidStrike
                    }
                }
            }
        }
    }

    /// Compatibility values from the previous application interpreter. These
    /// are NOT original Ninjato, Dead Forest Triad, or Heavenly King numbers.
    /// Recoil now consumes the same old total distance over multiple ticks.
    static func legacyStrike(command: DuelWeaponCommand, clip: DuelWeaponClip,
                             profile: DuelWeaponProfile) -> DuelCombatStrike {
        let heavy = command == .heavy || command == .shadow
        let kick = command.rawValue.hasPrefix("kick")
        let damage = kick ? 65 : command == .heavy ? (profile.isKatana ? 145 : 190) :
            command == .shadow ? (profile.isKatana ? 170 : 195) : (profile.isKatana ? 80 : 105)
        let impact = DuelImpactResponse(distanceMillimeters: heavy ? 200 : 65,
                                        durationTicks: heavy ? 10 : 6,
                                        launchVelocityMillimetersPerTick: 0,
                                        gravityMillimetersPerTickSquared: DuelGame.gravity)
        let start = command == .shadow ? DuelShadowRules.startup : Int(ceil(Double(clip.ticks) * 0.12))
        let end = command == .shadow ? (profile.isKatana ? 39 : 47) : Int(floor(Double(clip.ticks) * 0.78))
        return .init(id: 0, startTick: max(1, start), endTick: max(max(1, start), end),
                     weaponSides: kick || command == .shadow ? [] : profile.activeWeaponSides,
                     damage: damage, blockedDamage: max(1, damage / 12), knocksDown: heavy,
                     hitStopTicks: heavy ? 2 : 1, blockedHitStopTicks: 1,
                     impact: impact, blockedImpact: impact)
    }

    static func legacyRule(command: DuelWeaponCommand, clipName: String,
                           profile: DuelWeaponProfile) -> DuelCombatAttackRule? {
        if command.rawValue.hasPrefix("kick"), let aerial = profile.clip(role: "kickJump"),
           aerial.name == clipName {
            return .init(command: command, clipName: clipName,
                         strikes: [legacyStrike(command: command, clip: aerial, profile: profile)])
        }
        guard let initial = profile.clip(command: command == .shadow ? .heavy : command),
              command != .shadow || profile.clip(command: .shadow) != nil else { return nil }
        var name = initial.name, visited = Set<String>()
        while visited.insert(name).inserted {
            if name == clipName, let clip = profile.clip(named: name) {
                return .init(command: command, clipName: name,
                             strikes: [legacyStrike(command: command, clip: clip, profile: profile)])
            }
            guard command != .shadow, let link = profile.combo(from: name) else { return nil }
            name = link.to
        }
        return nil
    }

    static func legacy(for profile: DuelWeaponProfile) -> DuelCombatRuleProfile {
        var attacks: [DuelCombatAttackRule] = []
        for command in DuelWeaponCommand.allCases {
            guard let initial = profile.clip(command: command == .shadow ? .heavy : command),
                  command != .shadow || profile.clip(command: .shadow) != nil else { continue }
            var name = initial.name, visited = Set<String>()
            while visited.insert(name).inserted {
                guard let clip = profile.clip(named: name) else { break }
                attacks.append(.init(command: command, clipName: name,
                                     strikes: [legacyStrike(command: command, clip: clip, profile: profile)]))
                guard command != .shadow, let link = profile.combo(from: name) else { break }
                name = link.to
            }
            if command.rawValue.hasPrefix("kick"), let aerial = profile.clip(role: "kickJump"),
               !attacks.contains(where: { $0.command == command && $0.clipName == aerial.name }) {
                attacks.append(.init(command: command, clipName: aerial.name,
                                     strikes: [legacyStrike(command: command, clip: aerial, profile: profile)]))
            }
        }
        if profile.triadRules?.runtime != nil {
            // Source H17 root/wave animations contain physical blade strikes
            // in addition to independently emitted magic models. Their own
            // explicit rules are required; the magic volume cannot replace them.
            for role in ["triadBranches", "triadMistOnslaught", "triadMistOnslaught2", "triadMistOnslaught3"] {
                if let clip = profile.clip(role: role) {
                    attacks.append(.init(command: .weapon, clipName: clip.name,
                        strikes: [legacyStrike(command: .weapon, clip: clip, profile: profile)]))
                }
            }
        }
        return .init(id: profile.id + ".application.v2", basis: .applicationAdaptation,
                     sourceVersion: "application-0d83323-with-continuous-recoil",
                     evidence: ["docs/fighter-provisional-shadow-2026-11-10.md"], attacks: attacks)
    }
}

extension DuelWeaponProfile {
    public var resolvedCombatRules: DuelCombatRuleProfile { combatRules ?? .legacy(for: self) }

    /// Avoid materializing a whole legacy table on the per-tick collision path.
    /// An explicit but incomplete rule table never falls back to old numbers.
    public func resolvedCombatRule(command: DuelWeaponCommand, clipName: String) -> DuelCombatAttackRule? {
        if let combatRules { return combatRules.rule(command: command, clipName: clipName) }
        return DuelCombatRuleProfile.legacyRule(command: command, clipName: clipName, profile: self)
    }
}
