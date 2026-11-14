import XCTest
@testable import ShiftCore

/// Reflection is test-only: additions to stored state must update both the
/// explicit production encoder and its source audit. Reflection never encodes.
final class DuelReplayStateAuditTests: XCTestCase {
    private func fields(_ value: Any, _ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Mirror(reflecting: value).children.compactMap(\.label).sorted(), expected.sorted(),
                       "Stored state changed. Review the replay encoder and coverage document.", file: file, line: line)
    }

    func testCompleteStoredPropertyInventoryIncludingPrivateFields() throws {
        let catalog = DuelWeaponTestFixtures.catalog()
        var game = DuelGame(weaponCatalog: catalog)
        game.step(.init(weaponCommand: .weapon), opponent: .neutral)
        let fight = try XCTUnwrap(game.weaponFight)
        fields(game, ["selectedHero", "difficulty", "mode", "fighters", "projectiles", "grapple", "phase",
                      "frame", "remainingTicks", "wins", "hitStop", "events", "landedHits", "damageDealt",
                      "weaponFight", "random", "nextProjectile", "botHeld", "buffered", "opponentHero", "weaponModeRequested"])
        fields(fight, ["profiles", "fighters", "phase", "frame", "remainingTicks", "wins", "hitStop", "landedHits",
                       "damageDealt", "events", "contacts", "swings", "panguPresentationEvents", "mode", "difficulty", "actions", "queued",
                       "loopTicks", "loopRoles", "previousX", "random", "shadowCooldowns", "previousY", "previousHurtY", "impactMotions", "panguStates", "panguSpace", "ordinaryThrowStates", "ordinaryThrowKnockdownTicks"])
        fields(game.fighters[0], ["hero", "x", "y", "velocityY", "facing", "health", "guardMeter", "energy", "stun",
                                 "knockdown", "invulnerable", "guarding", "attack", "flash", "walking",
                                 "movementDirection", "weaponPose"])
        fields(DuelGame.Input.neutral, ["move", "guardHeld", "taps", "vertical", "weaponCommand"])
        fields(DuelGame.Buttons.light, ["rawValue"])
        fields(try XCTUnwrap(game.fighters[0].attack), ["move", "age", "connected", "spawned", "comboQueued"])
        fields(DuelGame.Projectile(id: 1, owner: 0, x: 4000, direction: 1), ["id", "owner", "x", "direction", "lifetime"])
        fields(DuelGame.Grapple(attacker: 0, direction: 1), ["attacker", "direction", "age"])
        fields(try XCTUnwrap(game.fighters[0].weaponPose), ["clip", "tick", "duration", "groundLift", "reaction"])
        fields(DuelWeaponPoint(), ["x", "y", "z"])
        fields(DuelWeaponFight.Contact(kind: .hit, attacker: 0, position: .init(), direction: 1, heavy: false, usesWeapon: true),
               ["kind", "attacker", "position", "direction", "heavy", "usesWeapon"])
        fields(DuelWeaponFight.Swing(attacker: 0, heavy: false, usesWeapon: true), ["attacker", "heavy", "usesWeapon"])
        // Action intentionally stays private, including in test code.
        let actions = try XCTUnwrap(Mirror(reflecting: fight).children.first { $0.label == "actions" }?.value)
        let firstOptional = try XCTUnwrap(Mirror(reflecting: actions).children.first?.value)
        let action = try XCTUnwrap(Mirror(reflecting: firstOptional).children.first?.value)
        fields(action, ["name", "role", "command", "tick", "hits", "touching", "landedStrikeIDs", "touchingStrikeIDs",
                        "requiresContactSeparation", "sounded", "reaction", "comboDepth", "soundAt", "shadowOriginX"])

        fields(catalog, ["schemaVersion", "previewFramesPerSecond", "sourceFramesPerSecond", "profiles"])
        fields(catalog.profiles[0], ["id", "hero", "faction", "resourceName", "bytes", "sha256", "bodyID", "weaponID",
                                     "activeWeaponSides", "roles", "clips", "comboLinks", "combatRules", "panguRules", "ordinaryThrows"])
        fields(catalog.profiles[0].clips[0], ["name", "frames", "sha256", "bundle", "tracks"])
        fields(catalog.profiles[0].clips[0].tracks, ["samplesPerSourceFrame", "root", "handL", "handR", "footL", "footR",
                                                   "weaponBaseL", "weaponTipL", "weaponBaseR", "weaponTipR", "groundLift"])
        fields(DuelWeaponComboLink(from: "a", to: "b", sourceFrame: 1), ["from", "to", "sourceFrame"])
        let rules = catalog.profiles[0].resolvedCombatRules
        fields(rules, ["id", "basis", "sourceVersion", "sourceSHA256", "evidence", "attacks"])
        fields(rules.attacks[0], ["command", "clipName", "strikes"])
        let strike = rules.attacks[0].strikes[0]
        fields(strike, ["id", "startTick", "endTick", "weaponSides", "damage", "blockedDamage", "knocksDown",
                        "hitStopTicks", "blockedHitStopTicks", "impact", "blockedImpact"])
        fields(strike.impact, ["distanceMillimeters", "durationTicks", "launchVelocityMillimetersPerTick",
                              "gravityMillimetersPerTickSquared"])
        fields(try XCTUnwrap(DuelImpactMotion(response: strike.impact, direction: 1)),
               ["response", "direction", "elapsedTicks", "appliedHorizontalDistance", "horizontalStopped"])
        let panguRules = DuelPanguTestFixture.rules()
        fields(panguRules, ["id", "basis", "sourceVersion", "sourceSHA256", "evidence", "level", "maximumHealth",
            "light", "combo", "abilities", "typhoon", "hunt", "heavenfall", "earth", "ranged", "trance",
            "windBlade", "heavyWindCount", "typhoonWindCount", "tranceWindCount", "level6CooldownRecoveryBps",
            "level4PrimordialCooldownReductionTicks", "level6PrimordialCooldownReductionTicks", "policies"])
        fields(panguRules.light, ["maximum", "initial", "damageToLightNumerator", "damageToLightDenominator",
            "absorbedKinds", "regularHitGain", "primordialHitGain", "level3GainBonus", "level5BlockedHitGain",
            "level5PrimordialGainBonus"])
        fields(panguRules.combo, ["maximum", "pointsPerHit", "holdTicks", "level6HoldTicks", "damageBonusPerPointBps",
            "maximumDamageBonusBps", "affectedKinds", "heavyWindThreshold", "allAttackWindThreshold",
            "rangedThreshold", "zeroCooldownThreshold", "level4SpeedThreshold", "level4AttackSpeedBps"])
        let panguAbility = try XCTUnwrap(panguRules.ability(.shard))
        fields(panguAbility, ["ability", "cooldownTicks", "lightCost", "startupTicks", "activeTicks", "recoveryTicks",
            "interruptible", "damageImmune", "attack"])
        fields(panguAbility.attack, ["damageKind", "damage", "blockedDamage", "delivery", "rangeMillimeters",
            "projectileSpeedMillimetersPerTick", "hitboxBottomMillimeters", "hitboxTopMillimeters", "radiusMillimeters",
            "impact", "stunTicks", "airHoldTicks", "knocksDown", "hitStopTicks", "blockedHitStopTicks"])
        fields(panguRules.typhoon, ["durationTicks", "fixedCooldownTicks", "damageBonusBps", "lightCostReductionBps",
            "stormGateUsesPerCycle", "stormGateBehindMillimeters"])
        fields(panguRules.hunt, ["durationTicks", "empoweredSpear", "pinTicks"])
        fields(panguRules.heavenfall, ["petrifyPhaseTicks", "targetPetrifyTicks", "riseTicks", "chargeTicks", "fallTicks",
            "recoveryTicks", "pillarHeightMillimeters", "descentVelocityMillimetersPerTick", "lightPerChargeTick",
            "level6LightPerChargeTick", "level6DamageBonusBps", "level6ComboGain", "level6CooldownMultiplierBps", "tranceTrigger",
            "level6LightChargeRatio", "level6ComboGainTrigger"])
        let chargeRatio = DuelPanguRules.LightChargeRatio(numerator: 5, denominator: 4,
            carryAcrossCasts: true, discardRemainderAtCapacity: false)
        fields(chargeRatio, ["numerator", "denominator", "carryAcrossCasts", "discardRemainderAtCapacity"])
        fields(panguRules.earth, ["shardDamageBonusBps", "shardStunTicks", "splitterDamageBonusBps", "dreadTicks",
            "dreadDamageTakenBonusBps", "dreadOutgoingReductionBps", "splitterWindCount", "splitterWindIntervalTicks",
            "earthquakeWindowTicks", "boulderBonusWindowTicks", "landingShock", "boulderBonus"])
        fields(panguRules.ranged, ["maximumCharges", "initialCharges", "rechargeTicks", "level5RechargeMultiplierBps"])
        fields(panguRules.trance, ["durationTicks", "attackSpeedBps", "incomingDamageMultiplierBps",
            "extraComboChancePerMillion", "extraComboPoints"])
        fields(panguRules.policies, ["blockedHitsCountCombo", "blockedPrimordialStartsRhythm", "blockedSpearCanPin",
            "generatedHitsCountCombo", "generatedHitsRestoreLight", "blockedDamageResetsCombo", "lightOnlyDamageResetsCombo",
            "level6ReceivedHitRefreshesHold", "consumeRhythmOnSpearCast", "windTrigger", "windSourcesStack",
            "thresholdsUseComboBeforeContact", "typhoonCooldownPriority", "level6RecoveryAffectsTyphoon",
            "level4ReductionAffectsTyphoon", "zeroCooldownClearsExisting", "shieldRequiresPositiveLight",
            "earthWindowTrigger", "interruptReleasesPetrification", "attackSpeedStacking"])
        var pangu = try XCTUnwrap(DuelPanguState(rules: panguRules, seed: 4))
        fields(pangu, ["rules", "light", "combo", "comboRemainingTicks", "typhoonRemainingTicks",
            "rhythmRemainingTicks", "tranceRemainingTicks", "earthquakeRemainingTicks", "boulderBonusRemainingTicks",
            "rangedCharges", "activeCast", "stormGateUses", "typhoonCycle", "cooldownUnits", "rangedRechargeUnits",
            "lightChargeRemainder", "randomState", "nextEffectID", "lastContactID", "lastAttackEventID", "lastLandingEventID",
            "pendingWinds", "rejectedPendingWindCount"])
        var space = DuelPanguSpatialState()
        fields(space, ["tick", "controls", "lifts", "volumes", "deferred", "deferredSlams", "speedRemainders",
                       "lastAirborne", "jumpEligible", "hitSequence"])
        fields(space.controls[0], ["stunUntil", "petrifyUntil", "petrifySourceID", "pinUntil", "airUntil", "airHeight",
                                  "pendingAirHoldTicks", "dreadUntil", "damageTakenBonusBps", "outgoingReductionBps"])

        // Build dynamic payloads through the interpreter, rather than keeping
        // parallel test-only copies of private Cast / Attack / pending types.
        var emitted = pangu.start(.splitter)
        fields(try XCTUnwrap(pangu.activeCast), ["id", "ability", "tick", "duration", "phase", "empowered"])
        let splitter = try XCTUnwrap(panguRules.ability(.splitter))
        for _ in 0..<splitter.startupTicks { emitted += pangu.step() }
        let attacks = emitted.compactMap { effect -> DuelPanguState.Attack? in
            if case .attack(let attack) = effect { return attack }; return nil
        }
        let attack = try XCTUnwrap(attacks.first)
        fields(attack, ["id", "ability", "damageKind", "damage", "blockedDamage", "delivery", "rangeMillimeters",
            "projectileSpeedMillimetersPerTick", "hitboxBottomMillimeters", "hitboxTopMillimeters", "radiusMillimeters",
            "impact", "stunTicks", "airHoldTicks", "knocksDown", "hitStopTicks", "blockedHitStopTicks", "generated", "empowered"])
        let contactEffects = pangu.contact(ability: .splitter, blocked: false, generated: false, hitID: 1)
        let controls = contactEffects.compactMap { effect -> DuelPanguState.Control? in
            if case .control(let control) = effect { return control }; return nil
        }
        fields(try XCTUnwrap(controls.first), ["sourceID", "kind", "durationTicks", "damageTakenBonusBps", "outgoingReductionBps"])
        let pendingWinds = try XCTUnwrap(Mirror(reflecting: pangu).children.first { $0.label == "pendingWinds" }?.value)
        let pendingWind = try XCTUnwrap(Mirror(reflecting: pendingWinds).children.first?.value)
        fields(pendingWind, ["remainingTicks", "ability"])

        space.lifts[0] = .init(startHeight: 0, targetHeight: panguRules.heavenfall.pillarHeightMillimeters,
                              duration: panguRules.heavenfall.riseTicks, phaseStartedTick: space.tick, height: 0)
        fields(try XCTUnwrap(space.lifts[0]), ["startHeight", "targetHeight", "duration", "age", "fallingSpeed",
                                             "phaseStartedTick", "height"])
        space.spawn(attack, owner: 0, fighter: .init(hero: .liu, x: 3500, facing: 1),
                    activeTicks: splitter.activeTicks, frame: space.tick)
        fields(try XCTUnwrap(space.volumes.first), ["owner", "attack", "originX", "originY", "direction", "expiresAt",
                                                   "x", "travelled", "spent"])
        space.enqueue(contactEffects, owner: 0)
        fields(try XCTUnwrap(space.deferred.first), ["owner", "effect"])
    }

    func testPanguPresentationQueueIsExplicitlyExcludedFromReplayBytes() throws {
        var fight = try DuelPanguFightFixture.fight()
        let canonical = try DuelReplayStateEncoding.encode(fight)
        let snapshot = fight.panguPresentation
        // The internal recorder writes derived feedback only. Deliberately
        // alter it independently so an accidental future encoder inclusion
        // fails even if two normal simulations generate identical feedback.
        fight.recordPanguPresentation(.landed(owner: 0, position: .init(x: 3.5, y: 0)))
        XCTAssertEqual(fight.panguPresentationEvents.count, 1)
        XCTAssertEqual(fight.panguPresentation, snapshot)
        XCTAssertEqual(try DuelReplayStateEncoding.encode(fight), canonical)
    }
}
