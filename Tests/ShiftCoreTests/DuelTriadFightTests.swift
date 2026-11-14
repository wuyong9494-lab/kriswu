import XCTest
@testable import ShiftCore

/// Tiny artificial bodies/timings exercise the shared simulation. Real model,
/// animation and source-cue acceptance is a separate native resource check.
enum DuelTriadFightFixture {
    static func rules(level: Int = 6) -> DuelTriadRules {
        var rules = DuelTriadRules.debug(level: level)
        rules.mist.initial = 5000
        rules.suppression.level6ShadowDefenseReductionBps = 0
        return rules
    }
    static func catalog(rules: DuelTriadRules = rules(), pangu: DuelPanguRules? = nil,
                        damage: Int = 90) throws -> DuelWeaponCatalog {
        let old = try pangu.map { try DuelPanguFightFixture.catalog(rules: $0) } ?? DuelWeaponTestFixtures.catalog()
        let sun = try XCTUnwrap(old.profile(for: .ember)), liu = try XCTUnwrap(old.profile(for: .liu))
        var roles = sun.roles
        roles.removeValue(forKey: "shadow"); roles.removeValue(forKey: "ranged")
        var clips = sun.clips.map { clip -> DuelWeaponClip in
            let t = clip.tracks
            return .init(name: clip.name, frames: clip.frames, sha256: clip.sha256, bundle: clip.bundle,
                tracks: .init(samplesPerSourceFrame: t.samplesPerSourceFrame,
                    root: t.root, handL: t.handL, handR: t.handR, footL: t.footL, footR: t.footR,
                    weaponBaseL: t.weaponBaseR, weaponTipL: t.weaponTipR,
                    weaponBaseR: t.weaponBaseR, weaponTipR: t.weaponTipR, groundLift: t.groundLift))
        }
        let idle = try XCTUnwrap(clips.first { $0.name == sun.roles["idle"] })
        let motions: [(String, Int)] = rules.runtime == nil ?
            DuelTriadRules.Ability.allCases.filter { $0.soul == nil }.map { ($0.motionRole, idle.frames) } :
            DuelTriadState.OwnerAnimation.allCases.map { ($0.role, $0.sourceFrameCount) }
        for (role, frames) in motions {
            let name = "synthetic_" + role, count = 2 * frames - 1, t = idle.tracks
            func samples(_ points: [DuelWeaponPoint]) -> [DuelWeaponPoint] { .init(repeating: points[0], count: count) }
            roles[role] = name
            clips.append(.init(name: name, frames: frames, sha256: idle.sha256,
                bundle: "synthetic-triad-integration-only", tracks: .init(samplesPerSourceFrame: 2,
                    root: samples(t.root), handL: samples(t.handL), handR: samples(t.handR),
                    footL: samples(t.footL), footR: samples(t.footR),
                    weaponBaseL: samples(t.weaponBaseL), weaponTipL: samples(t.weaponTipL),
                    weaponBaseR: samples(t.weaponBaseR), weaponTipR: samples(t.weaponTipR),
                    groundLift: .init(repeating: 0, count: count))))
        }
        var summonTracks: [DuelSummonMotionTrack]? = nil
        if rules.runtime != nil {
            let bindings = DuelTriadRules.SummonMove.allCases.map { ($0.role, $0.sourceFileName, $0.sourceFrameCount) } +
                [DuelTriadRules.SoulAnimation.ninjatoActiveStart, .ninjatoActiveEnd].map { ($0.role, $0.sourceFileName, $0.sourceFrameCount) }
            summonTracks = bindings.map { role, file, count in
                .init(role: role, clip: URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent,
                    frames: count, sourceSHA256: String(repeating: "a", count: 64), sourceBundle: "synthetic-only",
                    root: (0..<(2 * count - 1)).map { .init(x: Double($0) * 0.01) },
                    groundLift: .init(repeating: 0, count: 2 * count - 1))
            }
        }
        let triad = DuelWeaponProfile(id: "sun_triad", hero: .ember, faction: "Herald",
            resourceName: "Synthetic_Triad", bytes: sun.bytes, sha256: sun.sha256,
            bodyID: "synthetic_triad_body", weaponID: "synthetic_ninjato",
            activeWeaponSides: ["left", "right"], roles: roles, clips: clips, triadRules: rules, summonTracks: summonTracks)
        let attacks = DuelCombatRuleProfile.legacy(for: triad).attacks.map { binding in
            DuelCombatAttackRule(command: binding.command, clipName: binding.clipName, strikes: [
                .init(id: 0, startTick: 1, endTick: 12,
                    weaponSides: binding.command.rawValue.hasPrefix("kick") ? [] : ["left", "right"],
                    damage: damage, blockedDamage: 2, knocksDown: false,
                    hitStopTicks: 1, blockedHitStopTicks: 1,
                    impact: .init(distanceMillimeters: 0, durationTicks: 1),
                    blockedImpact: .init(distanceMillimeters: 0, durationTicks: 1))])
        }
        let bound = DuelWeaponProfile(id: triad.id, hero: triad.hero, faction: triad.faction,
            resourceName: triad.resourceName, bytes: triad.bytes, sha256: triad.sha256,
            bodyID: triad.bodyID, weaponID: triad.weaponID, activeWeaponSides: triad.activeWeaponSides,
            roles: roles, clips: clips,
            combatRules: .init(id: "synthetic-triad-contact", basis: .applicationAdaptation,
                sourceVersion: "synthetic-only", evidence: ["Artificial test geometry"], attacks: attacks),
            triadRules: rules, summonTracks: summonTracks)
        let catalog = DuelWeaponCatalog(schemaVersion: 1, previewFramesPerSecond: 30,
            sourceFramesPerSecond: nil, profiles: [bound, liu])
        try catalog.validate(); return catalog
    }
    static func fight(rules: DuelTriadRules = rules(), distance: Int = 1800,
                      pangu: DuelPanguRules? = nil, mode: DuelGame.Mode = .practice,
                      targetHealth: Int = 1000, damage: Int = 90) throws -> DuelWeaponFight {
        var target = DuelGame.Fighter(hero: .liu, x: 3500 + distance, facing: -1)
        target.health = targetHealth
        return try XCTUnwrap(DuelWeaponFight(fighters: [.init(hero: .ember, x: 3500, facing: 1), target],
            mode: mode, difficulty: .learning, catalog: catalog(rules: rules, pangu: pangu, damage: damage), seed: 53))
    }
    @discardableResult static func until(_ fight: inout DuelWeaponFight, limit: Int = 400,
        player: DuelGame.Input = .neutral, opponent: DuelGame.Input = .neutral,
        _ condition: (DuelWeaponFight) -> Bool) -> Bool {
        for _ in 0..<limit {
            if condition(fight) { return true }
            fight.step(player, opponent: opponent)
        }
        return condition(fight)
    }
}

final class DuelTriadFightTests: XCTestCase {
    private typealias F = DuelTriadFightFixture

    func testTargetCatalogSelectsIndependentNinjatoAndRejectsMissingSecondBlade() throws {
        let catalog = try F.catalog()
        XCTAssertEqual(DuelMultiplayerSelection.Choice.available(in: catalog), [.sunTriad, .liu])
        XCTAssertTrue(DuelMultiplayerSelection.Choice.sunTriad.isValid)
        XCTAssertFalse(DuelMultiplayerSelection.Choice(hero: .liu, weapon: .ninjato).isValid)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(catalog)) as? [String: Any])
        var profiles = try XCTUnwrap(object["profiles"] as? [[String: Any]])
        profiles[0]["activeWeaponSides"] = ["right"]
        object["profiles"] = profiles
        let altered = try JSONDecoder().decode(DuelWeaponCatalog.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try altered.validate())
    }

    func testDirectionalAbilitiesUseTheirOwnClipsAndNeverLegacyShadow() throws {
        let cases: [(DuelGame.Input, DuelTriadRules.Ability)] = [
            (.init(weaponCommand: .shadow), .branches),
            (.init(move: 1, weaponCommand: .shadow), .mistBlade),
            (.init(move: -1, weaponCommand: .shadow), .dynast),
            (.init(vertical: 1, weaponCommand: .shadow), .herald),
            (.init(vertical: -1, weaponCommand: .shadow), .legionary),
            (.init(weaponCommand: .ranged), .mistOnslaught),
            (.init(vertical: -1, weaponCommand: .ranged), .cryingDance)]
        for (input, ability) in cases {
            var fight = try F.fight()
            XCTAssertEqual(fight.triadAbility(for: input, index: 0), ability)
            if ability == .mistBlade || ability == .cryingDance { continue }
            fight.step(input, opponent: .neutral)
            if let soul = ability.soul {
                XCTAssertNil(fight.triadState(0)?.activeCast)
                XCTAssertEqual(fight.triadPresentation.summons.map(\.soul), [soul])
                XCTAssertNil(fight.profiles[0].clip(role: ability.motionRole))
            } else {
                XCTAssertEqual(fight.triadState(0)?.activeCast?.ability, ability)
                XCTAssertEqual(fight.fighters[0].weaponPose?.clip, fight.profiles[0].roles[ability.motionRole])
            }
            XCTAssertNil(fight.shadowVisual(0)); XCTAssertFalse(fight.shadowIsActive(0))
        }
    }

    func testSoulDoesNotReplaceAnOrdinaryAttackAndItsReleaseStaysAtAppearance() throws {
        var fight = try F.fight(distance: 2600)
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        let attackClip = try XCTUnwrap(fight.fighters[0].weaponPose?.clip)
        fight.step(.init(vertical: 1, weaponCommand: .shadow), opponent: .neutral)
        let summon = try XCTUnwrap(fight.triadPresentation.summons.first)
        XCTAssertEqual(summon.soul, .herald)
        XCTAssertEqual(fight.fighters[0].weaponPose?.clip, attackClip)
        XCTAssertNil(fight.triadState(0)?.activeCast)
        var released: DuelTriadPresentation.Volume?
        for _ in 0..<80 {
            fight.step(.init(move: -1), opponent: .neutral)
            for event in fight.triadPresentationEvents {
                if case .attackReleased(let volume) = event.kind, volume.ability == .herald { released = volume }
            }
            if released != nil { break }
        }
        let volume = try XCTUnwrap(released)
        let radius = try XCTUnwrap(fight.triadState(0)?.rules.ability(.herald)?.attack?.radiusMillimeters)
        XCTAssertEqual(volume.bounds.minX, summon.xMillimeters - radius)
        XCTAssertEqual(volume.direction, summon.direction)
        XCTAssertEqual(fight.triadState(0)?.notches, 1)
    }

    func testSoulCanAppearDuringRootHoldAndAnAirborneOwnerWithoutUnlockingOwner() throws {
        var rules = F.rules(level: 2); rules.branches.holdTicks = 120
        var root = try F.fight(rules: rules)
        root.step(.init(weaponCommand: .shadow), opponent: .neutral)
        XCTAssertTrue(F.until(&root) { $0.triadState(0)?.movementLocked == true })
        let heldX = root.fighters[0].x
        root.step(.init(move: 1, vertical: -1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertEqual(root.triadPresentation.summons.map(\.soul), [.legionary])
        XCTAssertEqual(root.fighters[0].x, heldX)
        XCTAssertEqual(root.triadState(0)?.movementLocked, true)
        XCTAssertFalse(root.canUseTriad(.mistOnslaught, index: 0))

        var air = try F.fight(distance: 2600)
        air.step(.init(taps: [.jump]), opponent: .neutral)
        XCTAssertTrue(F.until(&air, limit: 30) { $0.isAirborne(0) })
        let jumpClip = air.fighters[0].weaponPose?.clip
        air.step(.init(vertical: -1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertEqual(air.triadPresentation.summons.map(\.soul), [.legionary])
        XCTAssertEqual(air.fighters[0].weaponPose?.clip, jumpClip)
        XCTAssertNil(air.triadState(0)?.activeCast)
        XCTAssertTrue(air.isAirborne(0))
    }

    func testConfirmedBreakthroughBypassesGuardAndUnlocksMistBladeOnce() throws {
        var rules = F.rules(level: 2); rules.blade.initialOnslaughtCharges = 0
        var fight = try F.fight(rules: rules, distance: 800)
        fight.step(.init(weaponCommand: .weapon), opponent: .init(guardHeld: true))
        XCTAssertTrue(F.until(&fight, opponent: .init(guardHeld: true)) { $0.landedHits[0] == 1 })
        XCTAssertEqual(fight.fighters[1].health, 910)
        XCTAssertEqual(fight.triadState(0)?.onslaughtCharges, 1)
        XCTAssertEqual(fight.triadState(0)?.mistBladeUnlocked, true)
        XCTAssertEqual(fight.triadState(0)?.breakthroughReady, false)
        XCTAssertTrue(F.until(&fight) { $0.fighters[0].attack == nil && $0.hitStop == 0 })
        fight.step(.init(move: 1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertEqual(fight.triadState(0)?.activeCast?.ability, .mistBlade)
        XCTAssertTrue(F.until(&fight) { ($0.triadState(0)?.mistBladeRemainingTicks ?? 0) > 0 })
    }

    func testOrdinaryMistWaveSuppressesWithoutImmediateHitStopDamageOrPushAndCannotKill() throws {
        var rules = F.rules(level: 4)
        rules.suppression.totalTrueDamage = 500; rules.suppression.durationTicks = 90
        var fight = try F.fight(rules: rules, targetHealth: 30)
        let x = fight.fighters[1].x
        fight.step(.init(weaponCommand: .ranged), opponent: .neutral)
        XCTAssertTrue(F.until(&fight) { ($0.triadState(0)?.suppressionStacks ?? 0) > 0 })
        XCTAssertEqual(fight.fighters[1].health, 30)
        XCTAssertEqual(fight.hitStop, 0); XCTAssertEqual(fight.fighters[1].x, x)
        XCTAssertEqual(fight.fighters[1].stun, 0)
        for _ in 0..<120 { fight.step(.neutral, opponent: .init(guardHeld: true)) }
        XCTAssertEqual(fight.fighters[1].health, 1)
        XCTAssertEqual(fight.triadState(0)?.suppressionStacks, 0)
        XCTAssertEqual(fight.damageDealt[0], 29)
    }

    func testRootLocksBothAtLevelTwoButOnlyTheOpponentAtLevelFourAndThenReleases() throws {
        for level in [2, 4] {
            var rules = F.rules(level: level); rules.branches.holdTicks = 90
            rules.branches.entangledHoldReductionTicks = 0
            var fight = try F.fight(rules: rules)
            fight.step(.init(weaponCommand: .shadow), opponent: .neutral)
            XCTAssertTrue(F.until(&fight) { ($0.triadState(0)?.rootRemainingTicks ?? 0) > 0 })
            XCTAssertEqual(fight.triadState(0)?.movementLocked, level == 2)
            let x = fight.fighters[1].x
            for _ in 0..<20 { fight.step(.neutral, opponent: .init(move: -1, weaponCommand: .weapon)) }
            XCTAssertEqual(fight.fighters[1].x, x)
            XCTAssertTrue(fight.triadPresentation.controls.contains { $0.target == 1 && $0.kind == .root })
            XCTAssertTrue(F.until(&fight) { $0.triadState(0)?.rootRemainingTicks == 0 })
            fight.step(.neutral, opponent: .neutral)
            XCTAssertFalse(fight.triadPresentation.controls.contains { $0.kind == .root })
            XCTAssertEqual(fight.fighters[1].stun, 0)
        }
    }

    func testAcceptedOpponentShadowStartTriggersCurseButOrdinaryAttackDoesNot() throws {
        var fight = try F.fight(distance: 2600)
        fight.step(.neutral, opponent: .init(weaponCommand: .shadow))
        XCTAssertGreaterThan(fight.triadState(0)?.curseDebuffRemainingTicks ?? 0, 0)
        XCTAssertTrue(fight.triadPresentation.controls.contains { $0.target == 1 && $0.kind == .stun })
        var ordinary = try F.fight(distance: 2600)
        ordinary.step(.neutral, opponent: .init(weaponCommand: .weapon))
        XCTAssertEqual(ordinary.triadState(0)?.curseDebuffRemainingTicks, 0)
    }

    func testPanguAndTriadRunTogetherWithSeparateResourcesAndProfiles() throws {
        var fight = try F.fight(pangu: DuelPanguTestFixture.rules(level: 4))
        XCTAssertEqual(fight.profiles.map(\.id), ["sun_triad", "liu_pangu"])
        let mist = try XCTUnwrap(fight.triadState(0)?.mist)
        let light = try XCTUnwrap(fight.panguState(1)?.light)
        fight.step(.init(weaponCommand: .ranged), opponent: .init(weaponCommand: .ranged))
        XCTAssertEqual(fight.triadState(0)?.activeCast?.ability, .mistOnslaught)
        XCTAssertEqual(fight.panguState(1)?.activeCast?.ability, .spear)
        XCTAssertEqual(fight.triadState(0)?.mist, mist)
        XCTAssertLessThanOrEqual(try XCTUnwrap(fight.panguState(1)?.light), light)
        XCTAssertNil(fight.shadowVisual(0)); XCTAssertNil(fight.shadowVisual(1))
        for _ in 0..<90 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.fighters[0].energy, try XCTUnwrap(fight.triadState(0)).mist * 100 / F.rules().mist.maximum)
    }

    func testRoundFeastAndNotchesSurviveActualRoundBreak() throws {
        var fight = try F.fight(mode: .versus, targetHealth: 1)
        fight.step(.init(vertical: -1, weaponCommand: .shadow), opponent: .neutral)
        XCTAssertTrue(F.until(&fight) { if case .roundBreak = $0.phase { return true }; return false })
        let notches = try XCTUnwrap(fight.triadState(0)?.notches)
        let mist = try XCTUnwrap(fight.triadState(0)?.mist)
        XCTAssertGreaterThan(notches, 0)
        XCTAssertEqual(fight.wins, [1, 0])
        XCTAssertTrue(F.until(&fight) { $0.phase == .fighting })
        XCTAssertEqual(fight.triadState(0)?.notches, notches)
        XCTAssertEqual(fight.triadState(0)?.mist, mist)
        XCTAssertEqual(fight.triadState(0)?.roundID, 2)
        XCTAssertEqual(fight.triadState(0)?.breakthroughReady, true)
        XCTAssertTrue(fight.triadPresentation.volumes.isEmpty)
    }

    func testRenderingSnapshotsDoNotMutateAndReplayIncludesTheNewState() throws {
        var a = try F.fight(), b = try F.fight()
        for tick in 0..<280 {
            let input: DuelGame.Input = tick == 0 ? .init(weaponCommand: .ranged) :
                tick == 70 ? .init(weaponCommand: .shadow) :
                tick == 160 ? .init(vertical: 1, weaponCommand: .shadow) : .neutral
            a.step(input, opponent: .neutral); b.step(input, opponent: .neutral)
            for _ in 0..<4 { _ = a.triadPresentation; _ = a.triadPresentationEvents }
            if tick % 20 == 0 { XCTAssertEqual(try DuelReplayStateEncoding.encode(a), try DuelReplayStateEncoding.encode(b)) }
        }
        XCTAssertEqual(a, b)
        XCTAssertEqual(DuelReplayStateEncoding.schemaVersion, 7)
        XCTAssertEqual(DuelReplayStateEncoding.rulesVersion, 11)
    }

    func testDownRangedIntentSurvivesTouchReleaseForCryingDance() {
        var input = DuelWeaponInput()
        input.direction(x: 0, y: -1); input.press(.ranged)
        input.release(.ranged); input.direction(x: 0, y: 0)
        let edge = input.consume(facing: 1, airborne: false)
        XCTAssertEqual(edge.weaponCommand, .ranged); XCTAssertEqual(edge.vertical, -1)
        XCTAssertNil(input.consume(facing: 1, airborne: false).weaponCommand)
    }
}
