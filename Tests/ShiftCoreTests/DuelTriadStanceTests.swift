import XCTest
@testable import ShiftCore

/// Artificial points exercise the lifecycle and wire clock. Source names,
/// frame counts and hashes are binding facts only; this fixture is never an
/// original model/animation payload or native visual-acceptance evidence.
enum DuelTriadStanceFixture {
    static func catalog(pangu: DuelPanguRules? = nil) throws -> DuelWeaponCatalog {
        var rules = try DuelTriadTestFixture.runtimeRules()
        rules.mist.initial = rules.mist.maximum
        let base = try DuelTriadFightFixture.catalog(rules: rules, pangu: pangu, damage: 2000)
        let sun = try XCTUnwrap(base.profile(for: .ember))
        let idle = try XCTUnwrap(sun.clip(role: "idle")), t = idle.tracks
        var clips = sun.clips
        for motion in DuelTriadStanceState.Motion.allCases {
            let count = motion.lastSampleTick + 1
            func points(_ p: [DuelWeaponPoint]) -> [DuelWeaponPoint] { .init(repeating: p[0], count: count) }
            clips.append(.init(name: motion.clip, frames: motion.frames,
                sha256: motion.sourceSHA256, bundle: "synthetic-stance-test-points-only",
                tracks: .init(samplesPerSourceFrame: 2,
                    root: (0..<count).map { .init(x: Double($0) / 1000, y: Double($0) / 2000) },
                    handL: points(t.handL), handR: points(t.handR),
                    footL: .init(repeating: .init(x: -0.08), count: count), footR: points(t.footR),
                    weaponBaseL: points(t.weaponBaseL), weaponTipL: points(t.weaponTipL),
                    weaponBaseR: points(t.weaponBaseR), weaponTipR: points(t.weaponTipR),
                    groundLift: .init(repeating: 0.04, count: count),
                    pelvis: .init(repeating: .init(x: 0.03, y: 1.6), count: count))))
        }
        // A separate explicit artificial walk lets the winner reach the foe
        // after both source-pose lifecycles, without changing private HP/state.
        clips.append(.init(name: "synthetic_stance_test_walk", frames: idle.frames,
            sha256: idle.sha256, bundle: "synthetic-stance-test-points-only",
            tracks: .init(samplesPerSourceFrame: 2,
                root: t.root.indices.map { .init(x: Double($0) * 0.04) },
                handL: t.handL, handR: t.handR, footL: t.footL, footR: t.footR,
                weaponBaseL: t.weaponBaseL, weaponTipL: t.weaponTipL,
                weaponBaseR: t.weaponBaseR, weaponTipR: t.weaponTipR, groundLift: t.groundLift)))
        var roles = sun.roles
        roles["walkForward"] = "synthetic_stance_test_walk"
        roles["walkBackward"] = "synthetic_stance_test_walk"
        let bound = DuelWeaponProfile(id: sun.id, hero: sun.hero, faction: sun.faction,
            resourceName: sun.resourceName, bytes: sun.bytes, sha256: sun.sha256,
            bodyID: sun.bodyID, weaponID: sun.weaponID, activeWeaponSides: sun.activeWeaponSides,
            roles: roles, clips: clips, comboLinks: sun.comboLinks, combatRules: sun.combatRules,
            panguRules: sun.panguRules, ordinaryThrows: sun.ordinaryThrows,
            triadRules: sun.triadRules, summonTracks: sun.summonTracks)
        let result = DuelWeaponCatalog(schemaVersion: base.schemaVersion,
            previewFramesPerSecond: base.previewFramesPerSecond,
            sourceFramesPerSecond: base.sourceFramesPerSecond,
            profiles: [bound, try XCTUnwrap(base.profile(for: .liu))])
        try result.validate(); return result
    }
    static func fight(mode: DuelGame.Mode = .practice, swapped: Bool = false,
                      pangu: DuelPanguRules? = nil) throws -> DuelWeaponFight {
        let fighters: [DuelGame.Fighter] = swapped ?
            [.init(hero: .liu, x: 3500, facing: 1), .init(hero: .ember, x: 6500, facing: -1)] :
            [.init(hero: .ember, x: 3500, facing: 1), .init(hero: .liu, x: 6500, facing: -1)]
        return try XCTUnwrap(DuelWeaponFight(fighters: fighters, mode: mode, difficulty: .learning,
            catalog: catalog(pangu: pangu), seed: 91))
    }
    static func completeIntro(_ fight: inout DuelWeaponFight) {
        for _ in 0..<420 {
            guard fight.sourceIntroActive else { return }
            fight.step(.neutral, opponent: .neutral)
        }
        XCTFail("Bounded source intro did not complete")
    }
    static func winRound(_ fight: inout DuelWeaponFight) {
        for _ in 0..<1200 {
            guard fight.phase == .fighting else { return }
            let dx = fight.fighters[1].x - fight.fighters[0].x
            let input: DuelGame.Input = abs(dx) > 750 ? .init(move: dx >= 0 ? 1 : -1) : .init(weaponCommand: .weapon)
            fight.step(input, opponent: .neutral)
        }
        XCTFail("Artificial walking/attack fixture did not win within its bound")
    }
}

final class DuelTriadStanceTests: XCTestCase {
    private typealias State = DuelTriadStanceState
    private typealias F = DuelTriadStanceFixture

    func testFullSamplingDurationsStaySeparateFromOriginalEndEvents() {
        XCTAssertEqual(State.Motion.allCases.map(\.lastSampleTick), [60, 400, 94, 108, 208, 206, 322, 80])
        XCTAssertEqual(State.Motion.allCases.map(\.endEventTick), [nil, 392, nil, 100, 200, 198, 314, 72])
        XCTAssertEqual(Set(State.Motion.allCases.map(\.clip)).count, 8)
    }

    func testBirthLoopsUntilExplicitRoundStartInsteadOfWaitingToCompleteIt() {
        var state = State(round: 1, originXMillimeters: 3500, direction: 1)
        for _ in 0..<67 { state.advance() }
        XCTAssertEqual(state.motion, .firstBirth)
        XCTAssertEqual(state.tick, 6)
        XCTAssertTrue(state.beginRound())
        XCTAssertEqual(state.motion, .firstIntro)
        XCTAssertEqual(state.tick, 0)
        XCTAssertFalse(state.beginRound(), "Repeated lifecycle observations cannot restart the clip")
    }

    func testExactCapabilityGateRejectsMissingWrongHashAndWrongClock() throws {
        let source = try F.catalog()
        XCTAssertTrue(State.accepts(source.profiles[0]))
        for change in 0..<4 {
            let changed = try DuelWeaponTestFixtures.changing(source) { profiles in
                var clips = profiles[0]["clips"] as! [[String: Any]]
                let index = clips.firstIndex { $0["name"] as? String == State.Motion.firstIntro.clip }!
                if change == 0 { clips.remove(at: index) }
                if change == 1 { clips[index]["sha256"] = String(repeating: "d", count: 64) }
                if change == 2 { clips[index]["playbackTicks"] = 392 }
                profiles[0]["clips"] = clips
                if change == 3 {
                    var rules = profiles[0]["triadRules"] as! [String: Any]
                    var runtime = rules["runtime"] as! [String: Any]
                    runtime["configurationSHA256"] = String(repeating: "d", count: 64)
                    rules["runtime"] = runtime; profiles[0]["triadRules"] = rules
                }
            }
            XCTAssertFalse(State.accepts(changed.profiles[0]))
        }
        let legacy = try DuelTriadFightFixture.fight(rules: DuelTriadTestFixture.runtimeRules())
        XCTAssertFalse(legacy.hasSourceStance(0)); XCTAssertFalse(legacy.sourceIntroActive)
    }

    func testFirstAuthoritativeTickStartsIntroAndEmitsRoundStartExactlyOnce() throws {
        var fight = try F.fight()
        XCTAssertEqual(fight.sourceStance(0)?.motion, .firstBirth)
        XCTAssertEqual(fight.fighters[0].weaponPose?.duration, 60)
        XCTAssertFalse(fight.canUse(.weapon, index: 1))
        fight.step(.init(weaponCommand: .shadow), opponent: .init(weaponCommand: .weapon))
        XCTAssertEqual(fight.sourceStance(0)?.motion, .firstIntro)
        XCTAssertEqual(fight.sourceStance(0)?.tick, 0)
        XCTAssertEqual(fight.fighters[0].weaponPose?.duration, 400)
        XCTAssertEqual(fight.sourcePresentationTick, 1)
        XCTAssertEqual(fight.triadPresentation.liveTick, 1)
        let starts = fight.triadPresentationEvents.filter {
            if case .source(0, .roundStarted(roundID: 1)) = $0.kind { return true }; return false
        }
        XCTAssertEqual(starts.count, 1); XCTAssertEqual(starts.first?.liveTick, 1)
        fight.step(.neutral, opponent: .neutral)
        XCTAssertFalse(fight.triadPresentationEvents.contains {
            if case .source(_, .roundStarted) = $0.kind { return true }; return false
        })
    }

    func testIntroDropsInputsAndFreezesBothCharactersRulesAndCountdown() throws {
        var fight = try F.fight(mode: .versus, pangu: DuelPanguTestFixture.rules())
        fight.step(.neutral, opponent: .neutral)
        let triad = fight.triadState(0), pangu = fight.panguState(1)
        for _ in 0..<392 {
            fight.step(.init(move: 1, taps: [.jump, .heavy], weaponCommand: .ranged, rangedHeld: true),
                       opponent: .init(move: -1, weaponCommand: .shadow))
            XCTAssertNil(fight.fighters[0].attack); XCTAssertNil(fight.fighters[1].attack)
            XCTAssertTrue(fight.contacts.isEmpty); XCTAssertTrue(fight.triadPresentation.summons.isEmpty)
        }
        XCTAssertEqual(fight.triadState(0), triad)
        XCTAssertEqual(fight.panguState(1), pangu)
        XCTAssertEqual(fight.remainingTicks, 3600)
        XCTAssertEqual(fight.sourceStance(0)?.motion, .startIdle)
        XCTAssertEqual(fight.fighters[0].weaponPose?.tick, 0)
        XCTAssertEqual(fight.fighters[0].weaponPose?.duration, 208)
        XCTAssertTrue(fight.sourceIntroActive)
        XCTAssertFalse(fight.canUsePangu(.shard, index: 1))
        XCTAssertFalse(fight.canUseTriad(.legionary, index: 0))
        fight.step(.neutral, opponent: .neutral)
        XCTAssertFalse(fight.sourceIntroActive)
        XCTAssertEqual(fight.remainingTicks, 3599)
        XCTAssertNil(fight.fighters[0].attack, "Intro taps must not remain buffered")
        XCTAssertNil(fight.triadState(0)?.activeCast)
    }

    func testOriginalIntroMarkerTicksAreCrossedOnceWithoutDurationCompression() throws {
        var fight = try F.fight()
        let frames = [40, 83, 157, 169, 61, 82, 179]
        var seen: [Int: [Int]] = [:]
        for _ in 0...392 {
            fight.step(.neutral, opponent: .neutral)
            for sample in fight.sourceMotionSamples where sample.clip == State.Motion.firstIntro.clip {
                XCTAssertEqual(sample.duration, 400)
                for marker in frames where sample.crosses(sourceFrame: marker, totalSourceFrames: 201) {
                    seen[marker, default: []].append(sample.tick)
                }
            }
            XCTAssertFalse(fight.triadPresentationEvents.contains {
                if case .source(_, .arenaForestLoopStarted) = $0.kind { return true }; return false
            })
        }
        for marker in frames { XCTAssertEqual(seen[marker], [marker * 2]) }
        XCTAssertEqual(fight.sourceMotionSamples.map(\.tick), [392, 0])
        XCTAssertEqual(fight.sourceMotionSamples.map(\.clip), [State.Motion.firstIntro.clip, State.Motion.startIdle.clip])
    }

    func testBothFacingOrdersAlignSourceXAndNeverDoubleApplyRootY() throws {
        for swapped in [false, true] {
            var fight = try F.fight(swapped: swapped)
            let index = swapped ? 1 : 0, direction = swapped ? -1 : 1
            let initial = swapped ? 6500 : 3500
            XCTAssertEqual(fight.fighters[index].x, initial + direction * (-920 - 30))
            XCTAssertEqual(fight.fighters[index].y, 0)
            fight.step(.neutral, opponent: .neutral)
            let start = fight.fighters[index].x
            for _ in 0..<80 { fight.step(.neutral, opponent: .neutral) }
            XCTAssertEqual(fight.fighters[index].x, start + 80 * direction)
            XCTAssertEqual(fight.fighters[index].y, 0)
            XCTAssertEqual(fight.fighters[index].weaponPose?.groundLift, 0.04)
            XCTAssertEqual(fight.fighters[index].weaponPose?.tick, 80)
        }
    }

    func testPostIntroSoulAgeUsesCombatTimeAndDoesNotInheritPresentationAge() throws {
        var fight = try F.fight()
        F.completeIntro(&fight)
        let before = fight.sourcePresentationTick
        fight.step(.init(vertical: -1, weaponCommand: .shadow), opponent: .neutral)
        let appeared = try XCTUnwrap(fight.triadPresentation.summons.first)
        XCTAssertGreaterThan(before, 392)
        XCTAssertEqual(appeared.age, 0); XCTAssertEqual(appeared.motionTick, 0)
        XCTAssertEqual(fight.triadPresentation.liveTick, before + 1)
        fight.step(.neutral, opponent: .neutral)
        XCTAssertEqual(fight.triadPresentation.summons.first?.age, 1)
        XCTAssertEqual(fight.triadPresentation.summons.first?.motionTick, 1)
    }

    func testRoundWinnerPlaysRoundWinThenIdleBeforeTheNextBirth() throws {
        var fight = try F.fight(mode: .versus)
        F.winRound(&fight)
        XCTAssertEqual(fight.wins, [1, 0])
        XCTAssertEqual(fight.phase, .roundBreak(winner: 0, remaining: 199))
        XCTAssertEqual(fight.sourceStance(0)?.motion, .roundWin)
        XCTAssertEqual(fight.fighters[0].weaponPose?.tick, 0)
        let frozenRules = fight.triadState(0), before = fight.sourcePresentationTick
        for _ in 0..<198 { fight.step(.init(weaponCommand: .ranged), opponent: .neutral) }
        XCTAssertEqual(fight.sourcePresentationTick, before + 198)
        XCTAssertEqual(fight.triadState(0), frozenRules)
        XCTAssertEqual(fight.sourceStance(0)?.motion, .winIdle)
        XCTAssertEqual(fight.fighters[0].weaponPose?.tick, 0)
        XCTAssertEqual(fight.fighters[0].weaponPose?.duration, 80)
        XCTAssertEqual(fight.sourceMotionSamples.map(\.tick), [198, 0])
        fight.step(.neutral, opponent: .neutral)
        XCTAssertEqual(fight.roundNumber, 2)
        XCTAssertEqual(fight.sourceStance(0)?.motion, .roundBirth)
        XCTAssertEqual(fight.fighters[0].weaponPose?.duration, 94)
        fight.step(.neutral, opponent: .neutral)
        XCTAssertEqual(fight.sourceStance(0)?.motion, .roundIntro)
        XCTAssertEqual(fight.fighters[0].weaponPose?.duration, 108)
        XCTAssertEqual(fight.triadPresentationEvents.filter {
            if case .source(0, .roundStarted(roundID: 2)) = $0.kind { return true }; return false
        }.count, 1)
    }

    func testSecondIntroUsesItsOwnEndAndResetsNoPresentationClock() throws {
        var state = State(round: 2, originXMillimeters: 3500, direction: 1)
        state.beginRound()
        for _ in 0..<99 { XCTAssertNil(state.advance()) }
        XCTAssertEqual(state.motion, .roundIntro); XCTAssertEqual(state.tick, 99)
        XCTAssertEqual(state.advance(), .init(from: .roundIntro, finalTick: 100))
        XCTAssertEqual(state.motion, .startIdle); XCTAssertEqual(state.tick, 0)
    }

    func testFinalWinKeepsIdleZeroForAnAuthoritativeTickThenStops() throws {
        var fight = try F.fight(mode: .versus)
        F.winRound(&fight)
        for _ in 0..<199 { fight.step(.neutral, opponent: .neutral) }
        F.winRound(&fight)
        XCTAssertEqual(fight.wins, [2, 0])
        XCTAssertEqual(fight.phase, .roundBreak(winner: 0, remaining: 315))
        XCTAssertEqual(fight.sourceStance(0)?.motion, .win)
        for _ in 0..<314 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertEqual(fight.phase, .roundBreak(winner: 0, remaining: 1))
        XCTAssertEqual(fight.fighters[0].weaponPose?.clip, State.Motion.winIdle.clip)
        XCTAssertEqual(fight.fighters[0].weaponPose?.tick, 0)
        let firstIdleFrame = fight.frame
        fight.step(.neutral, opponent: .neutral)
        XCTAssertEqual(fight.frame, firstIdleFrame + 1)
        XCTAssertEqual(fight.phase, .matchOver(winner: 0))
        XCTAssertEqual(fight.fighters[0].weaponPose?.tick, 0)
        let frozen = try DuelReplayStateEncoding.encode(fight), clock = fight.sourcePresentationTick
        for _ in 0..<5 { fight.step(.init(weaponCommand: .weapon), opponent: .init(weaponCommand: .ranged)) }
        XCTAssertEqual(try DuelReplayStateEncoding.encode(fight), frozen)
        XCTAssertEqual(fight.sourcePresentationTick, clock)
        XCTAssertTrue(fight.sourceMotionSamples.isEmpty); XCTAssertTrue(fight.triadPresentationEvents.isEmpty)
    }

    func testCombatHitStopFreezesPresentationButReadingItNeverAdvancesOrReemits() throws {
        var fight = try F.fight()
        F.completeIntro(&fight)
        for _ in 0..<160 {
            let dx = fight.fighters[1].x - fight.fighters[0].x
            fight.step(abs(dx) > 750 ? .init(move: dx >= 0 ? 1 : -1) : .init(weaponCommand: .weapon), opponent: .neutral)
            if fight.hitStop > 0 { break }
        }
        XCTAssertGreaterThan(fight.hitStop, 0)
        let clock = fight.sourcePresentationTick, snapshot = fight.triadPresentation
        let canonical = try DuelReplayStateEncoding.encode(fight), samples = fight.sourceMotionSamples
        for _ in 0..<3 {
            XCTAssertEqual(fight.triadPresentation, snapshot)
            XCTAssertEqual(fight.sourceMotionSamples, samples)
        }
        XCTAssertEqual(try DuelReplayStateEncoding.encode(fight), canonical)
        fight.step(.neutral, opponent: .neutral)
        XCTAssertEqual(fight.sourcePresentationTick, clock)
        XCTAssertTrue(fight.sourceMotionSamples.isEmpty)
    }

    func testSourceStanceInventoryAndCanonicalFieldsAreExplicit() throws {
        var state = State(round: 1, originXMillimeters: 3500.125, direction: -1)
        XCTAssertEqual(Mirror(reflecting: state).children.compactMap(\.label).sorted(),
            ["purpose", "motion", "tick", "originXMillimeters", "direction"].sorted())
        func bytes(_ value: State) throws -> Data {
            var writer = try DuelReplayStateWriter(kind: 2); try value.appendReplayState(to: &writer); return writer.data
        }
        let first = try bytes(state)
        state.beginRound(); XCTAssertNotEqual(try bytes(state), first)
        let start = try bytes(state)
        state.advance(); XCTAssertNotEqual(try bytes(state), start)
        let tick = try bytes(state)
        state.align(originXMillimeters: 3500.126, direction: -1); XCTAssertNotEqual(try bytes(state), tick)
        let origin = try bytes(state)
        state.align(originXMillimeters: 3500.126, direction: 1); XCTAssertNotEqual(try bytes(state), origin)
    }

    func testBothHostOrdersKeepExistingNetworkPhaseAndDeterministicSourceEvents() throws {
        for swapped in [false, true] {
            let catalog = try F.catalog()
            var host = DuelGame(hero: swapped ? .liu : .ember, mode: .versus, seed: 22,
                opponentHero: swapped ? .ember : .liu, weaponCatalog: catalog)
            var guest = host
            for tick in 0..<395 {
                let input = DuelGame.Input(move: 1, weaponCommand: tick == 45 ? .ranged : nil)
                host.step(input, opponent: .neutral); guest.step(input, opponent: .neutral)
                XCTAssertEqual(host, guest)
                let projection = DuelNetworkCombatState(game: host, sessionID: "synthetic-stance-wire",
                    tick: UInt64(tick + 1), epoch: 0)
                XCTAssertEqual(projection.phase, .fighting)
                XCTAssertNil(projection.winner)
                XCTAssertTrue(projection.isPlausible)
                if [0, 80, 392, 393, 394].contains(tick) {
                    XCTAssertEqual(try DuelReplayStateEncoding.encode(host), try DuelReplayStateEncoding.encode(guest))
                }
            }
        }
    }

    func testNetworkDuplicateAndTerminalInterruptionCannotAdvanceOrRedeliverTheIntro() throws {
        typealias Barrier = DuelNetworkStartBarrier
        let hostID = "source-host", guestID = "source-guest", sessionID = "source-stance-session"
        let catalog = try F.catalog()
        var selection = try DuelMultiplayerSelection(sessionID: sessionID, hostID: hostID, guestID: guestID)
        let commands: [(String, UInt64, DuelMultiplayerSelection.Command)] = [
            (hostID, 1, .select(.sunTriad)), (guestID, 1, .select(.liu)),
            (hostID, 2, .ready(true, selectionRevision: 2)), (guestID, 2, .ready(true, selectionRevision: 2)),
            (hostID, 3, .start(selectionRevision: 2))
        ]
        for (sender, sequence, command) in commands {
            XCTAssertEqual(selection.apply(.init(sessionID: sessionID, sequence: sequence, command: command),
                authenticatedSenderID: sender, localPlayerID: hostID), .applied)
        }
        let snapshot = selection.snapshot
        let compatibility = Barrier.Compatibility(rulesFingerprint: String(repeating: "a", count: 64),
            catalogFingerprint: String(repeating: "b", count: 64))
        var hb = try Barrier(started: snapshot, sessionID: sessionID, hostID: hostID, guestID: guestID,
            localPlayerID: hostID, compatibility: compatibility)
        var gb = try Barrier(started: snapshot, sessionID: sessionID, hostID: hostID, guestID: guestID,
            localPlayerID: guestID, compatibility: compatibility)
        let offer = try hb.makeOffer(startID: "source-stance-start", seed: 3, sequence: 1)
        XCTAssertEqual(gb.receive(try offer.encoded(), authenticatedSenderID: hostID), .applied)
        let configuration = try XCTUnwrap(hb.offeredConfiguration)
        let hostLoaded = try hb.confirmLoaded(configuration: configuration, loadedCompatibility: compatibility,
            catalog: catalog, sequence: 2)
        let guestLoaded = try gb.confirmLoaded(configuration: configuration, loadedCompatibility: compatibility,
            catalog: catalog, sequence: 1)
        XCTAssertEqual(hb.receive(try guestLoaded.encoded(), authenticatedSenderID: guestID), .applied)
        XCTAssertEqual(gb.receive(try hostLoaded.encoded(), authenticatedSenderID: hostID), .applied)
        XCTAssertEqual(gb.receive(try hb.commit(sequence: 3).encoded(), authenticatedSenderID: hostID), .applied)
        var host = try DuelNetworkCombatHost(committed: hb, started: snapshot,
            loadedCompatibility: compatibility, catalog: catalog)
        var guest = try DuelNetworkReplay(committed: gb, loadedCompatibility: compatibility, catalog: catalog)
        let message = try host.advance(), bytes = try message.encoded()
        XCTAssertEqual(guest.receive(bytes, authenticatedSenderID: hostID), .applied)
        XCTAssertNil(message.terminalState)
        XCTAssertEqual(guest.game.weaponFight?.sourceStance(0)?.motion, .firstIntro)
        let canonical = try guest.verificationState(), events = guest.game.weaponFight?.triadPresentationEvents
        XCTAssertEqual(guest.receive(bytes, authenticatedSenderID: hostID), .ignoredDuplicate)
        XCTAssertEqual(try guest.verificationState(), canonical)
        XCTAssertEqual(guest.game.weaponFight?.triadPresentationEvents, events)
        guest.interrupt()
        let afterCancel = try guest.verificationState()
        XCTAssertEqual(guest.receive(try host.advance().encoded(), authenticatedSenderID: hostID), .rejected(.closed))
        XCTAssertEqual(try guest.verificationState(), afterCancel)
        XCTAssertEqual(guest.game.weaponFight?.sourcePresentationTick, 1)
    }
}
