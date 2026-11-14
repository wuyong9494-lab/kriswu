import XCTest
@testable import ShiftCore

/// Original D19 trigger gates and event markers with explicit synthetic
/// geometry and 1,000-unit application HP/power normalization. These tests
/// neither load original character media nor claim native visual acceptance.
final class DuelPanguFormalMechanismTests: XCTestCase {
    private typealias State = DuelPanguState
    private typealias Strike = DuelPanguRules.SourceStrike

    private func makeState(level: Int) throws -> State {
        let rules = try DuelPanguRules.d19HeavenlyKing(level: level,
            maximumHealth: 1000, weaponPower: 1000, unarmedPower: 1000,
            magicPower: 1000, rangedPower: 1000,
            spatialTemplate: DuelPanguTestFixture.rules(level: level))
        return try XCTUnwrap(State(rules: rules, seed: 17))
    }

    private func attacks(_ effects: [State.Effect]) -> [State.Attack] {
        effects.compactMap { if case .attack(let attack) = $0 { return attack }; return nil }
    }

    private func releaseSplitter(_ state: inout State) throws -> State.Attack {
        state.start(.splitter)
        for _ in 0..<37 { XCTAssertTrue(attacks(state.step()).isEmpty) }
        let attack = try XCTUnwrap(attacks(state.step()).first)
        XCTAssertEqual(attack.sourceStrike, .splitter)
        XCTAssertEqual(attack.sourceBaseDamage, 550)
        XCTAssertEqual(attack.sourceLifetimeTicks, 8)
        return attack
    }

    private func queueTyphoonWind(_ state: inout State) {
        state.start(.typhoon)
        for _ in 0..<80 { _ = state.step() }
        XCTAssertGreaterThan(state.typhoonRemainingTicks, 0)
        state.contact(blocked: false, generated: false, hitID: 1, kind: .weapon)
    }

    private func windFight(level: Int = 2, triadRoot: Bool = false,
                           mode: DuelGame.Mode = .practice, ordinaryDamage: Int = 10) throws -> DuelWeaponFight {
        var rules = try makeState(level: level).rules
        rules.windBlade.hitStopTicks = 0; rules.windBlade.blockedHitStopTicks = 0
        rules.windBlade.impact = .init(distanceMillimeters: 0, durationTicks: 1)
        let source: DuelWeaponCatalog
        if triadRoot {
            var triad = DuelTriadFightFixture.rules(level: 2)
            triad.forest.curseChanceBps = 0
            triad.branches.holdTicks = 60; triad.branches.pulseDamage = 0
            triad.branches.entangledHoldReductionTicks = 0
            let index = try XCTUnwrap(triad.abilities.firstIndex { $0.ability == .branches })
            triad.abilities[index].startupTicks = 1
            triad.abilities[index].interruptible = false
            triad.abilities[index].attack?.hitStopTicks = 0
            triad.abilities[index].attack?.stunTicks = 0
            triad.abilities[index].attack?.impact = .init(distanceMillimeters: 0, durationTicks: 1)
            source = try DuelTriadFightFixture.catalog(rules: triad, pangu: rules, damage: ordinaryDamage)
        } else {
            source = try DuelPanguFightFixture.catalog(rules: rules,
                ordinaryDamage: ordinaryDamage, ordinaryHitStop: 0)
        }
        let catalog = try DuelWeaponTestFixtures.changing(source) { profiles in
            for index in profiles.indices {
                guard let roles = profiles[index]["roles"] as? [String: String],
                      var clips = profiles[index]["clips"] as? [[String: Any]] else {
                    XCTFail("The synthetic fixture must contain named roles and clips"); return
                }
                for clip in clips.indices {
                    guard var tracks = clips[clip]["tracks"] as? [String: Any],
                          let root = tracks["root"] as? [[Double]] else {
                        XCTFail("The synthetic fixture must contain source-sample tracks"); return
                    }
                    // Explicitly synthetic node samples make the source-wind
                    // data gate real without claiming an original Pangu body.
                    tracks["pelvis"] = Array(repeating: [0.0, 1.0, 0.0], count: root.count)
                    clips[clip]["tracks"] = tracks
                    if clips[clip]["name"] as? String == roles["knockdown"] {
                        clips[clip]["playbackTicks"] = 60
                    }
                }
                profiles[index]["clips"] = clips
                guard var combat = profiles[index]["combatRules"] as? [String: Any],
                      var bindings = combat["attacks"] as? [[String: Any]] else {
                    XCTFail("The synthetic fixture must contain explicit combat rules"); return
                }
                for binding in bindings.indices {
                    guard var strikes = bindings[binding]["strikes"] as? [[String: Any]] else {
                        XCTFail("The synthetic fixture must contain explicit strikes"); return
                    }
                    for strike in strikes.indices {
                        strikes[strike]["hitStopTicks"] = 0; strikes[strike]["blockedHitStopTicks"] = 0
                        if !triadRoot && profiles[index]["id"] as? String != "liu_pangu" &&
                            bindings[binding]["command"] as? String == "weapon" {
                            strikes[strike]["knocksDown"] = true
                        }
                    }
                    bindings[binding]["strikes"] = strikes
                }
                combat["attacks"] = bindings; profiles[index]["combatRules"] = combat
            }
        }
        var fight = try XCTUnwrap(DuelWeaponFight(fighters: [
            .init(hero: .liu, x: 3500, facing: 1), .init(hero: .ember, x: 4300, facing: -1)
        ], mode: mode, difficulty: .learning, catalog: catalog, seed: 41))
        fight.step(.init(move: -1, weaponCommand: .shadow), opponent: .neutral)
        for _ in 0..<80 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertNil(fight.panguState(0)?.activeCast)
        XCTAssertGreaterThan(try XCTUnwrap(fight.panguState(0)).typhoonRemainingTicks, 0)
        return fight
    }

    private func releasedWinds(_ fight: DuelWeaponFight) -> [DuelPanguPresentation.Event] {
        fight.panguPresentationEvents.filter { event in
            if case .attackReleased(let volume) = event.kind {
                return volume.owner == 0 && volume.ability == nil && volume.generated
            }
            return false
        }
    }

    private let sourceThrowWindows: [(State.Ability, Int, Int)] = [
        (.splitter, 114, 126), (.shard, 98, 110), (.bones, 82, 94),
        (.typhoon, 68, 80), (.spear, 82, 100), (.heavenfall, 308, 320)
    ]

    private func throwWindowCatalog(level: Int = 2) throws -> DuelWeaponCatalog {
        var rules = try makeState(level: level).rules
        // The test preserves recovered timing and power. Its explicitly
        // artificial attack heights make the preceding skill miss, so the
        // throw test does not bypass real victim health/control/range gates.
        func miss(_ spec: inout DuelPanguRules.AttackSpec) {
            spec.hitboxBottomMillimeters = 10_000; spec.hitboxTopMillimeters = 11_000
            spec.hitStopTicks = 0; spec.blockedHitStopTicks = 0
        }
        for index in rules.abilities.indices { miss(&rules.abilities[index].attack) }
        miss(&rules.hunt.empoweredSpear); miss(&rules.windBlade)
        miss(&rules.earth.boulderBonus); miss(&rules.earth.landingShock)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rules))
        return try DuelWeaponTestFixtures.changing(DuelSourceThrowFixture.catalog(pangu: true)) { profiles in
            for index in profiles.indices {
                if profiles[index]["id"] as? String == "liu_pangu" { profiles[index]["panguRules"] = encoded }
                var combat = profiles[index]["combatRules"] as! [String: Any]
                var attacks = combat["attacks"] as! [[String: Any]]
                for attack in attacks.indices {
                    var strikes = attacks[attack]["strikes"] as! [[String: Any]]
                    for strike in strikes.indices {
                        strikes[strike]["hitStopTicks"] = 0; strikes[strike]["blockedHitStopTicks"] = 0
                    }
                    attacks[attack]["strikes"] = strikes
                }
                combat["attacks"] = attacks; profiles[index]["combatRules"] = combat
            }
        }
    }

    private func throwWindowFight(_ ability: State.Ability, facing: Int = 1,
                                  panguFirst: Bool = false, distance: Int = 800) throws -> DuelWeaponFight {
        let firstX = facing > 0 ? 4000 : 6000
        var fight = try XCTUnwrap(DuelWeaponFight(fighters: [
            .init(hero: panguFirst ? .liu : .ember, x: firstX, facing: facing),
            .init(hero: panguFirst ? .ember : .liu, x: firstX + distance * facing, facing: -facing)
        ], mode: .practice, difficulty: .learning, catalog: throwWindowCatalog(), seed: 41))
        let owner = panguFirst ? 0 : 1, direction = fight.fighters[owner].facing
        let input: DuelGame.Input
        switch ability {
        case .shard: input = .init(move: direction, weaponCommand: .shadow)
        case .typhoon: input = .init(move: -direction, weaponCommand: .shadow)
        case .splitter: input = .init(vertical: 1, weaponCommand: .shadow)
        case .bones: input = .init(vertical: -1, weaponCommand: .shadow)
        case .spear: input = .init(weaponCommand: .ranged)
        case .heavenfall: input = .init(weaponCommand: .shadow)
        case .stormGate: throw NSError(domain: "unsupported-synthetic-throw-fixture", code: 1)
        }
        fight.step(owner == 0 ? input : .neutral, opponent: owner == 1 ? input : .neutral)
        XCTAssertEqual(fight.panguState(owner)?.activeCast?.ability, ability)
        XCTAssertEqual(fight.panguState(owner)?.activeCast?.tick, 0)
        return fight
    }

    func testLevelTwoAndThreeSplitterKeepsAirHoldWithoutInventingLandingDamage() throws {
        // Original settings_sets_dynasty records221/222 retain the hit and
        // 52-tick passive marker. lock1546 SHADOW_UP/t4 requires D19_4_LEVEL
        // before that marker may create the separate damage model.
        for level in [2, 3] {
            var state = try makeState(level: level)
            let attack = try releaseSplitter(&state)
            XCTAssertEqual(attack.airHoldTicks, 52, "L\(level) retains its source reaction control")
            state.prepareContact(attack: attack, blocked: false, hitID: 1)
            state.contact(attack: attack, blocked: false, hitID: 1, reactable: true)
            XCTAssertEqual(state.combo, 1)
            XCTAssertEqual(state.light, state.rules.light.primordialHitGain)
            var emitted: [State.Attack] = []
            var controls: [State.Control] = []
            for _ in 1...90 {
                let effects = state.step()
                emitted += attacks(effects)
                controls += effects.compactMap { if case .control(let control) = $0 { return control }; return nil }
            }
            XCTAssertTrue(emitted.isEmpty, "L\(level) has no upperFall or upperWind damage after the confirmed Splitter")
            XCTAssertTrue(controls.isEmpty, "The higher-level landing debuff is not created either")
        }
    }

    func testLevelFourThroughSixRetainFiveWindMarkersAndTheirLandingDamage() throws {
        // record223: wind frames5/10/15/30/35 and ground-crack frame40;
        // the native interval clock maps F to 2*(F-1) core ticks.
        for level in 4...6 {
            var state = try makeState(level: level)
            let attack = try releaseSplitter(&state)
            XCTAssertEqual(attack.airHoldTicks, 78)
            state.prepareContact(attack: attack, blocked: false, hitID: 1)
            state.contact(attack: attack, blocked: false, hitID: 1, reactable: true)
            var ticks: [Int] = []
            var emitted: [State.Attack] = []
            var debuffTicks: [Int] = []
            for tick in 1...90 {
                let effects = state.step()
                let released = attacks(effects)
                ticks += Array(repeating: tick, count: released.count)
                emitted += released
                for effect in effects {
                    if case .control(let control) = effect, control.kind == .dread {
                        debuffTicks.append(tick)
                        XCTAssertEqual(control.durationTicks, 600)
                    }
                }
            }
            XCTAssertEqual(ticks, [8, 18, 28, 58, 68, 78], "L\(level) source sequence is unchanged")
            XCTAssertEqual(emitted.compactMap(\.sourceStrike),
                [.upperWind, .upperWind, .upperWind, .upperWind, .upperWind, .upperFall])
            XCTAssertEqual(emitted.compactMap(\.sourceBaseDamage), [150, 150, 150, 150, 150, 500])
            XCTAssertEqual(emitted.map(\.damageKind), [.shadow, .shadow, .shadow, .shadow, .shadow, .unarmed])
            XCTAssertEqual(debuffTicks, [78])
        }
    }

    func testOwnerReactionRetainsTheSourceWindCountersRemainingTicks() throws {
        for level in 2...6 {
            var state = try makeState(level: level)
            queueTyphoonWind(&state)
            for _ in 0..<3 { XCTAssertTrue(attacks(state.step()).isEmpty) }
            state.cancelPendingDerivedAttacks(preservingSourceWindCounter: true)
            _ = state.receiveDamage(1, kind: .weapon, blocked: false)
            for _ in 0..<6 { XCTAssertTrue(attacks(state.step()).isEmpty) }
            XCTAssertEqual(attacks(state.step()).compactMap(\.sourceStrike), [.windBlade],
                           "L\(level) retains the remaining seven ticks, rather than cancelling or restarting ten ticks")
            for _ in 0..<20 { XCTAssertTrue(attacks(state.step()).isEmpty) }
        }
    }

    func testForceRoundAndResetStillClearTheSourceWindCounter() throws {
        for boundary in ["force", "round", "reset", "explicit"] {
            var state = try makeState(level: 6)
            queueTyphoonWind(&state)
            for _ in 0..<3 { _ = state.step() }
            switch boundary {
            case "force": state.interrupt(force: true)
            case "round": state.beginNextRound(seed: 23)
            case "reset": state.reset(seed: 23)
            default: state.cancelPendingDerivedAttacks()
            }
            for _ in 0..<30 {
                XCTAssertTrue(attacks(state.step()).isEmpty, "\(boundary) must discard the previous wind queue")
            }
        }
    }

    func testRealFightKnockdownPreservesOneSourceWindAtItsOriginalReleaseTick() throws {
        for level in [2, 6] {
            var fight = try windFight(level: level)
            fight.step(.init(weaponCommand: .weapon), opponent: .init(weaponCommand: .weapon))
            XCTAssertTrue(DuelPanguFightFixture.until(&fight, limit: 4) {
                $0.landedHits[0] == 1 && $0.landedHits[1] == 1
            }, "Both ordinary contacts must really trade before checking the queued wind")
            let contactTick = fight.panguPresentation.liveTick
            XCTAssertGreaterThan(fight.fighters[0].knockdown, 0)
            var releaseTicks: [Int] = []
            for _ in 0..<25 {
                fight.step(.neutral, opponent: .neutral)
                let released = releasedWinds(fight)
                if !released.isEmpty { XCTAssertGreaterThan(fight.fighters[0].knockdown, 0) }
                releaseTicks += released.map(\.liveTick)
            }
            XCTAssertEqual(releaseTicks, [contactTick + 10])
            XCTAssertEqual(fight.landedHits[0], 2, "The independently released source wind reaches its actual target")
        }
    }

    func testRealTriadRootDoesNotEraseTheOpponentsSourceWindQueue() throws {
        var fight = try windFight(triadRoot: true)
        fight.step(.init(weaponCommand: .weapon), opponent: .init(weaponCommand: .shadow))
        XCTAssertTrue(DuelPanguFightFixture.until(&fight, limit: 4) {
            $0.landedHits[0] == 1 && ($0.triadState(1)?.rootRemainingTicks ?? 0) > 0
        }, "The synthetic root must actually contact after the Pangu weapon contact")
        let contactTick = fight.panguPresentation.liveTick
        XCTAssertGreaterThan(fight.fighters[0].stun, 0)
        var releaseTicks: [Int] = []
        for _ in 0..<25 {
            fight.step(.neutral, opponent: .neutral)
            let released = releasedWinds(fight)
            if !released.isEmpty { XCTAssertGreaterThan(fight.fighters[0].stun, 0) }
            releaseTicks += released.map(\.liveTick)
        }
        XCTAssertEqual(releaseTicks, [contactTick + 10])
        XCTAssertEqual(fight.landedHits[0], 2)
    }

    func testFightRoundEndDoesNotCarryTheQueuedWindIntoTheNextRound() throws {
        var fight = try windFight(mode: .versus, ordinaryDamage: 1000)
        fight.step(.init(weaponCommand: .weapon), opponent: .neutral)
        XCTAssertTrue(DuelPanguFightFixture.until(&fight, limit: 5) { $0.fighters[1].health == 0 })
        XCTAssertEqual(fight.landedHits[0], 1)
        XCTAssertTrue(DuelPanguFightFixture.until(&fight, limit: 200) { $0.roundNumber == 2 && $0.phase == .fighting })
        for _ in 0..<25 {
            fight.step(.neutral, opponent: .neutral)
            XCTAssertTrue(releasedWinds(fight).isEmpty)
            XCTAssertEqual(fight.fighters[1].health, 1000)
        }
    }

    func testSixSourceCastThrowableIntervalsOpenAtTheirOriginalFirstTick() throws {
        for level in 2...6 {
            for (ability, firstTick, endTick) in sourceThrowWindows {
                var state = try makeState(level: level)
                state.start(ability)
                XCTAssertEqual(state.activeCast?.duration, endTick)
                for _ in 0..<(firstTick - 1) { _ = state.step() }
                XCTAssertFalse(state.sourceCastAllowsThrowResponse, "\(ability), L\(level), previous tick")
                let before = state
                XCTAssertTrue(state.acceptSourceThrowResponse().isEmpty)
                XCTAssertEqual(state, before, "A rejected attempt cannot interrupt or spend resources")
                _ = state.step()
                XCTAssertTrue(state.sourceCastAllowsThrowResponse, "\(ability), L\(level), first source tick")
                XCTAssertTrue(state.throwImmune); XCTAssertFalse(state.canBeThrown)
                let accepted = state.acceptSourceThrowResponse()
                XCTAssertEqual(accepted.filter { if case .castInterrupted(ability) = $0 { return true }; return false }.count, 1)
                XCTAssertNil(state.activeCast); XCTAssertFalse(state.sourceCastAllowsThrowResponse)
                XCTAssertTrue(state.acceptSourceThrowResponse().isEmpty, "The same interval cannot be consumed twice")
            }
        }
    }

    func testThrowResponseDoesNotForceCancelIndependentSourceWindOrRefundResources() throws {
        var state = try makeState(level: 6)
        state.start(.typhoon)
        for _ in 0..<68 { _ = state.step() }
        XCTAssertTrue(state.sourceCastAllowsThrowResponse)
        state.contact(blocked: false, generated: false, hitID: 1, kind: .weapon)
        for _ in 0..<3 { _ = state.step() }
        let light = state.light, combo = state.combo, charges = state.rangedCharges
        let cooldown = state.cooldownRemaining(.typhoon), buff = state.typhoonRemainingTicks
        XCTAssertEqual(state.acceptSourceThrowResponse(), [.castInterrupted(.typhoon)])
        XCTAssertEqual(state.light, light); XCTAssertEqual(state.combo, combo)
        XCTAssertEqual(state.rangedCharges, charges); XCTAssertEqual(state.cooldownRemaining(.typhoon), cooldown)
        XCTAssertEqual(state.typhoonRemainingTicks, buff)
        XCTAssertEqual(state.rhythmRemainingTicks, 0, "Taking over a cast is not its completed AnimationEnd")
        for _ in 0..<6 { XCTAssertTrue(attacks(state.step()).isEmpty) }
        XCTAssertEqual(attacks(state.step()).compactMap(\.sourceStrike), [.windBlade])
        for _ in 0..<20 { XCTAssertTrue(attacks(state.step()).isEmpty) }
    }

    func testNewCastAndLifecycleBoundariesCannotInheritAnOpenThrowableInterval() throws {
        for boundary in ["newCast", "force", "round", "reset"] {
            var state = try makeState(level: 6)
            state.start(.splitter)
            for _ in 0..<114 { _ = state.step() }
            XCTAssertTrue(state.sourceCastAllowsThrowResponse)
            switch boundary {
            case "newCast":
                state.acceptSourceThrowResponse(); state.start(.spear)
                XCTAssertEqual(state.activeCast?.ability, .spear)
                XCTAssertEqual(state.activeCast?.tick, 0)
            case "force": state.interrupt(force: true)
            case "round": state.beginNextRound(seed: 19)
            default: state.reset(seed: 19)
            }
            XCTAssertFalse(state.sourceCastAllowsThrowResponse, boundary)
            let after = state
            XCTAssertTrue(state.acceptSourceThrowResponse().isEmpty)
            XCTAssertEqual(state, after)
        }
        var normalEnd = try makeState(level: 6)
        normalEnd.start(.typhoon)
        for _ in 0..<80 { _ = normalEnd.step() }
        XCTAssertFalse(normalEnd.sourceCastAllowsThrowResponse)
        normalEnd.start(.stormGate)
        for _ in 0..<61 {
            XCTAssertFalse(normalEnd.sourceCastAllowsThrowResponse)
            _ = normalEnd.step()
        }
        XCTAssertFalse(normalEnd.sourceCastAllowsThrowResponse)
        _ = normalEnd.step(); XCTAssertNil(normalEnd.activeCast)
    }

    func testLegacyRulesCannotAcquireSourceRecoveryWindowsAfterCharacterSwitch() throws {
        var legacyRules = DuelPanguTestFixture.rules(level: 6)
        let index = try XCTUnwrap(legacyRules.abilities.firstIndex { $0.ability == .typhoon })
        legacyRules.abilities[index].recoveryTicks = 200
        var legacy = try XCTUnwrap(State(rules: legacyRules, seed: 17))
        legacy.start(.typhoon)
        for _ in 0..<68 { _ = legacy.step() }
        XCTAssertNotNil(legacy.activeCast); XCTAssertNil(legacy.rules.runtime)
        XCTAssertFalse(legacy.sourceCastAllowsThrowResponse)
        let before = legacy
        XCTAssertTrue(legacy.acceptSourceThrowResponse().isEmpty); XCTAssertEqual(legacy, before)

        var pangu = try throwWindowFight(.typhoon)
        DuelSourceThrowFixture.advance(&pangu, 68)
        XCTAssertTrue(try XCTUnwrap(pangu.panguState(1)).sourceCastAllowsThrowResponse)
        var switched = try DuelSourceThrowFixture.fight(pangu: false)
        switched.step(.init(weaponCommand: .weaponBack), opponent: .neutral)
        XCTAssertEqual(switched.profiles[1].id, "liu_hammers")
        XCTAssertNil(switched.panguState(1)); XCTAssertEqual(switched.sourceThrow(0)?.variant, .back)
    }

    func testRealFightSixRecoveryTakeoversStartAtZeroAndKeepCounterDamageAt98() throws {
        for (ability, firstTick, _) in sourceThrowWindows {
            for facing in [-1, 1] {
                let owner = facing > 0 ? 1 : 0, attacker = 1 - owner
                var before = try throwWindowFight(ability, facing: facing, panguFirst: owner == 0)
                DuelSourceThrowFixture.advance(&before, firstTick - 2)
                var early = before
                let attempt = DuelGame.Input(weaponCommand: .weaponBack)
                early.step(attacker == 0 ? attempt : .neutral, opponent: attacker == 1 ? attempt : .neutral)
                XCTAssertNil(early.sourceThrow(attacker), "\(ability) must reject the preceding tick")
                XCTAssertEqual(early.panguState(owner)?.activeCast?.tick, firstTick - 1)

                before.step(.neutral, opponent: .neutral)
                XCTAssertEqual(before.landedHits, [0, 0], "Synthetic high attack geometry must really miss")
                before.step(attacker == 0 ? attempt : .neutral, opponent: attacker == 1 ? attempt : .neutral)
                let pair = try XCTUnwrap(before.sourceThrow(attacker), "\(ability) must respond on its first Throwable tick")
                XCTAssertEqual(pair.variant, .panguEscape); XCTAssertEqual(pair.tick, 0)
                XCTAssertNil(before.panguState(owner)?.activeCast)
                XCTAssertFalse(before.canBeThrown(owner))
                XCTAssertEqual(before.fighters[owner].weaponPose?.clip, "synthetic_source_panguActive")
                XCTAssertEqual(before.fighters[owner].weaponPose?.tick, 0)
                let interrupted = before.panguPresentationEvents.filter {
                    if case .castEnded(let eventOwner, let eventAbility, let interrupted) = $0.kind {
                        return eventOwner == owner && eventAbility == ability && interrupted
                    }
                    return false
                }
                XCTAssertEqual(interrupted.count, 1)
                DuelSourceThrowFixture.advance(&before, 97)
                XCTAssertEqual(before.sourceThrow(owner)?.tick, 97)
                XCTAssertEqual(before.landedHits, [0, 0]); XCTAssertEqual(before.fighters[attacker].health, 1000)
                before.step(.neutral, opponent: .neutral)
                XCTAssertEqual(before.sourceThrow(owner)?.tick, 98)
                XCTAssertEqual(before.landedHits[owner], 1); XCTAssertEqual(before.landedHits[attacker], 0)
                // L2: original .15 unarmed, PreHit combo +1%, Typhoon +50%.
                XCTAssertEqual(before.damageDealt[owner], ability == .typhoon ? 227 : 151)
                XCTAssertEqual(before.fighters[owner].health, 1000)
                DuelSourceThrowFixture.advance(&before, 14)
                XCTAssertEqual(before.landedHits[owner], 1, "The takeover cannot repeat the damage marker")
            }
        }
    }

    func testOpenSourceWindowStillRequiresRangeAndIdleInitiator() throws {
        var far = try throwWindowFight(.typhoon, distance: 1200)
        DuelSourceThrowFixture.advance(&far, 67)
        far.step(.init(weaponCommand: .weaponBack), opponent: .neutral)
        XCTAssertNil(far.sourceThrow(0))
        XCTAssertTrue(try XCTUnwrap(far.panguState(1)).sourceCastAllowsThrowResponse)

        var busy = try throwWindowFight(.typhoon)
        DuelSourceThrowFixture.advance(&busy, 66)
        busy.step(.init(weaponCommand: .kick), opponent: .neutral)
        busy.step(.init(weaponCommand: .weaponBack), opponent: .neutral)
        XCTAssertNil(busy.sourceThrow(0), "The target's recovery does not bypass the attacker's own action")
    }

    func testNetworkPauseCannotAdvanceOrLeakTheSourceThrowableBoundary() throws {
        var selection = try DuelMultiplayerSelection(sessionID: "source-throw-pause", hostID: "host", guestID: "guest")
        for (sender, sequence, command) in [
            ("host", UInt64(1), DuelMultiplayerSelection.Command.select(.sun)),
            ("guest", UInt64(1), .select(.liuPangu)),
            ("host", UInt64(2), .ready(true, selectionRevision: 2)),
            ("guest", UInt64(2), .ready(true, selectionRevision: 2)),
            ("host", UInt64(3), .start(selectionRevision: 2))
        ] {
            XCTAssertEqual(selection.apply(.init(sessionID: "source-throw-pause", sequence: sequence, command: command),
                authenticatedSenderID: sender, localPlayerID: "host"), .applied)
        }
        var simulation = try DuelNetworkHostSimulation(started: selection.snapshot, localPlayerID: "host",
            catalog: throwWindowCatalog(), seed: 41)
        XCTAssertEqual(simulation.receive(.init(sessionID: "source-throw-pause", sequence: 1, tick: 0,
            weaponCommand: .ranged), authenticatedSenderID: "guest", localPlayerID: "host"), .applied)
        try simulation.step(localPlayerID: "host")
        for _ in 0..<81 { try simulation.step(localPlayerID: "host") }
        XCTAssertEqual(simulation.game.weaponFight?.panguState(1)?.activeCast?.tick, 81)
        XCTAssertFalse(try XCTUnwrap(simulation.game.weaponFight?.panguState(1)).sourceCastAllowsThrowResponse)
        XCTAssertEqual(simulation.pause(localPlayerID: "host"), .applied)
        let paused = simulation
        for _ in 0..<20 { XCTAssertThrowsError(try simulation.step(localPlayerID: "host")) }
        XCTAssertEqual(simulation, paused)
        XCTAssertEqual(simulation.resume(localPlayerID: "host"), .applied)
        try simulation.step(localPlayerID: "host")
        XCTAssertEqual(simulation.game.weaponFight?.panguState(1)?.activeCast?.tick, 82)
        XCTAssertTrue(try XCTUnwrap(simulation.game.weaponFight?.panguState(1)).sourceCastAllowsThrowResponse)
    }
}
