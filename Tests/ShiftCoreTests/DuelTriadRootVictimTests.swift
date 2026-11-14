import XCTest
@testable import ShiftCore

/// Artificial geometry exercises the production control route. The source
/// identifiers bind the reviewed clock; this fixture contains no original
/// animation/model data and is not native visual-acceptance evidence.
enum DuelTriadRootVictimFixture {
    static let motions: [(String, Int, String)] = [
        ("h17_root_spike_passive_start", 44, "69d01bc2d1cc6be69188be006582598bf3551c88db3f7446078fcda63583382c"),
        ("h17_root_spike_passive_loop", 61, "a3f13059f3eeedd057e14d738894667a77b04279109d1544f0e2b34ad12502ce"),
        ("h17_root_spike_passive_end", 48, "7d9b8572ae67cd8f344f16478cc50a56e17c0646191c7f2306ff2724453cf5e2")
    ]
    static func catalog(targetMotions: Bool = true) throws -> DuelWeaponCatalog {
        var rules = try DuelTriadTestFixture.runtimeRules()
        rules.mist.initial = rules.mist.maximum
        let base = try DuelTriadFightFixture.catalog(rules: rules)
        guard targetMotions else { return base }
        let liu = try XCTUnwrap(base.profile(for: .liu)), t = try XCTUnwrap(liu.clip(role: "idle")).tracks
        var clips = liu.clips
        for (name, frames, sha) in motions {
            let count = 2 * frames - 1
            func points(_ values: [DuelWeaponPoint]) -> [DuelWeaponPoint] { .init(repeating: values[0], count: count) }
            clips.append(.init(name: name, frames: frames, sha256: sha,
                bundle: "synthetic-root-victim-control-test-only",
                tracks: .init(samplesPerSourceFrame: 2,
                    root: (0..<count).map { .init(x: Double($0) / 10_000) },
                    handL: points(t.handL), handR: points(t.handR),
                    footL: points(t.footL), footR: points(t.footR),
                    weaponBaseL: points(t.weaponBaseL), weaponTipL: points(t.weaponTipL),
                    weaponBaseR: points(t.weaponBaseR), weaponTipR: points(t.weaponTipR),
                    groundLift: .init(repeating: 0, count: count),
                    pelvis: .init(repeating: .init(x: 0.02, y: 1.2), count: count))))
        }
        let bound = DuelWeaponProfile(id: liu.id, hero: liu.hero, faction: liu.faction,
            resourceName: liu.resourceName, bytes: liu.bytes, sha256: liu.sha256,
            bodyID: liu.bodyID, weaponID: liu.weaponID, activeWeaponSides: liu.activeWeaponSides,
            roles: liu.roles, clips: clips, comboLinks: liu.comboLinks, combatRules: liu.combatRules,
            panguRules: liu.panguRules, ordinaryThrows: liu.ordinaryThrows,
            triadRules: liu.triadRules, summonTracks: liu.summonTracks)
        let result = DuelWeaponCatalog(schemaVersion: base.schemaVersion,
            previewFramesPerSecond: base.previewFramesPerSecond,
            sourceFramesPerSecond: base.sourceFramesPerSecond,
            profiles: [try XCTUnwrap(base.profile(for: .ember)), bound])
        try result.validate(); return result
    }
    static func fight(targetMotions: Bool = true, swapped: Bool = false,
                      mode: DuelGame.Mode = .practice, targetHealth: Int = 1000) throws -> DuelWeaponFight {
        var liu = DuelGame.Fighter(hero: .liu, x: swapped ? 3500 : 5000, facing: swapped ? 1 : -1)
        liu.health = targetHealth
        let sun = DuelGame.Fighter(hero: .ember, x: swapped ? 5000 : 3500, facing: swapped ? -1 : 1)
        return try XCTUnwrap(DuelWeaponFight(fighters: swapped ? [liu, sun] : [sun, liu],
            mode: mode, difficulty: .learning, catalog: catalog(targetMotions: targetMotions), seed: 91))
    }
    static func catchRoot(_ fight: inout DuelWeaponFight, swapped: Bool = false) throws {
        fight.step(swapped ? .neutral : .init(weaponCommand: .shadow),
                   opponent: swapped ? .init(weaponCommand: .shadow) : .neutral)
        let owner = swapped ? 1 : 0
        XCTAssertTrue(DuelTriadFightFixture.until(&fight, limit: 110) {
            ($0.triadState(owner)?.rootRemainingTicks ?? 0) > 0
        }, "A real root contact in the synthetic catalog must precede victim animation")
    }
}

final class DuelTriadRootVictimTests: XCTestCase {
    private typealias F = DuelTriadRootVictimFixture
    private typealias State = DuelTriadRootVictimState

    private func state() -> State { .init(sourceID: 7, owner: 0, originXMillimeters: 5000, direction: -1) }

    private func advance(_ state: inout State, _ count: Int) {
        for _ in 0..<count { _ = state.advance() }
    }

    func testConfirmedRootContactSelectsTheBoundPassiveStartInsteadOfFreezingGenericHit() throws {
        var fight = try F.fight()
        try F.catchRoot(&fight)
        XCTAssertEqual(fight.fighters[1].weaponPose?.clip, F.motions[0].0)
        XCTAssertEqual(fight.fighters[1].weaponPose?.tick, 0)
        XCTAssertEqual(fight.fighters[1].weaponPose?.duration, 86)
        XCTAssertEqual(fight.rootVictimState(1)?.motion, .start)
    }

    func testSourceSamplingEndEventsAndIntervalEndClocksRemainDistinct() {
        XCTAssertEqual(State.Motion.allCases.map(\.lastSampleTick), [86, 120, 94])
        XCTAssertEqual(State.Motion.allCases.map(\.endEventTick), [78, 112, 86])
        XCTAssertEqual(State.loopCheckTicks, [2, 50, 90])
        XCTAssertEqual(State.Motion.allCases.map(\.sourceSHA256), F.motions.map { $0.2 })
    }

    func testCapabilityRequiresEveryExactMotionClockAndRigPelvisTrack() throws {
        let base = try F.catalog()
        XCTAssertTrue(State.matches(profile: base.profiles[1]))
        XCTAssertEqual(base.profiles[1].id, "liu_hammers", "Shared victim motions do not establish the D19 identity")
        for variant in 0..<5 {
            let changed = try DuelWeaponTestFixtures.changing(base) { profiles in
                var clips = profiles[1]["clips"] as! [[String: Any]]
                let index = clips.firstIndex { $0["name"] as? String == State.Motion.end.clip }!
                if variant == 0 { clips.remove(at: index) }
                if variant == 1 { clips[index]["sha256"] = String(repeating: "d", count: 64) }
                if variant == 2 { clips[index]["playbackTicks"] = 86 }
                if variant == 3 { clips[index]["frames"] = 49 }
                if variant == 4 {
                    var tracks = clips[index]["tracks"] as! [String: Any]
                    tracks.removeValue(forKey: "pelvis"); clips[index]["tracks"] = tracks
                }
                profiles[1]["clips"] = clips
            }
            XCTAssertFalse(State.matches(profile: changed.profiles[1]), "Variant \(variant)")
        }
    }

    func testActiveDurationLoopsOnlyAtTheOriginalEarlyAnimationEnds() {
        var value = state()
        advance(&value, 77)
        XCTAssertEqual(value.motion, .start); XCTAssertEqual(value.tick, 77)
        let first = value.advance()
        XCTAssertTrue(first.transitioned); XCTAssertEqual(first.finalTick, 78)
        XCTAssertEqual(value.motion, .loop); XCTAssertEqual(value.tick, 0)
        advance(&value, 111)
        XCTAssertEqual(value.motion, .loop); XCTAssertEqual(value.tick, 111)
        let repeated = value.advance()
        XCTAssertTrue(repeated.transitioned); XCTAssertEqual(repeated.previousMotion, .loop)
        XCTAssertEqual(repeated.finalTick, 112); XCTAssertEqual(value.tick, 0)
    }

    func testAReleasedShortRootStillFinishesStartBeforeEnteringEnd() {
        var value = state()
        XCTAssertTrue(value.release(sourceID: 7, owner: 0))
        advance(&value, 77)
        XCTAssertEqual(value.motion, .start)
        _ = value.advance()
        XCTAssertEqual(value.motion, .end); XCTAssertEqual(value.tick, 0)
    }

    func testDurationExpiryWaitsForTheNextLoopIntervalEndOrAnimationEnd() {
        for (releasedAt, expected) in [(0, 2), (2, 50), (50, 90), (90, 112)] {
            var value = state(); advance(&value, 78 + releasedAt)
            XCTAssertEqual(value.motion, .loop); XCTAssertEqual(value.tick, releasedAt)
            XCTAssertTrue(value.release(sourceID: 7, owner: 0))
            XCTAssertEqual(value.motion, .loop, "A variable change cannot synthesize an interval event")
            advance(&value, expected - releasedAt - 1)
            XCTAssertEqual(value.motion, .loop); XCTAssertEqual(value.tick, expected - 1)
            let result = value.advance()
            XCTAssertEqual(result.finalTick, expected)
            XCTAssertEqual(value.motion, .end); XCTAssertEqual(value.tick, 0)
        }
    }

    func testAStaleRootReleaseCannotUnlockAnotherSourceOrOwner() {
        var value = state()
        XCTAssertFalse(value.release(sourceID: 8, owner: 0))
        XCTAssertFalse(value.release(sourceID: 7, owner: 1))
        XCTAssertTrue(value.durationActive)
        XCTAssertTrue(value.release(sourceID: 7, owner: 0))
        XCTAssertFalse(value.release(sourceID: 7, owner: 0))
        XCTAssertFalse(value.durationActive)
    }

    func testEndRetainsItsLastSampleAndCrossesFloorfallExactlyOnce() {
        var value = state(); value.release(sourceID: 7, owner: 0); advance(&value, 78)
        var crossings = 0
        for expected in 1...94 {
            let previous = value.tick, result = value.advance()
            if previous < 38 && value.tick >= 38 { crossings += 1 }
            XCTAssertEqual(value.motion, .end); XCTAssertEqual(value.tick, expected)
            XCTAssertFalse(result.completed)
        }
        XCTAssertEqual(crossings, 1)
        XCTAssertTrue(value.advance().completed)
    }

    func testFightKeepsOwnershipAfterExpiryPublishesBoundarySamplesAndReplaysIdentically() throws {
        var fight = try F.fight(); try F.catchRoot(&fight)
        var peer = fight
        var sawWait = false, sawEnd = false, sawBoundary = false, crossings = 0
        var visited: Set<String> = []
        var frozenSteps = 0
        for _ in 0..<380 {
            let old = fight.rootVictimState(1), beforeStop = fight.hitStop
            let input = DuelGame.Input(move: 1, guardHeld: true, weaponCommand: .heavy)
            fight.step(.neutral, opponent: input); peer.step(.neutral, opponent: input)
            if beforeStop > 0 {
                frozenSteps += 1
                XCTAssertEqual(fight.rootVictimState(1), old)
                XCTAssertTrue(fight.sourceMotionSamples.isEmpty)
            }
            let samples = fight.sourceMotionSamples.filter { $0.owner == 1 }
            crossings += samples.filter { $0.clip == State.Motion.end.clip && $0.previousTick < 38 && $0.tick >= 38 }.count
            if let value = fight.rootVictimState(1) {
                XCTAssertFalse(fight.canUse(.heavy, index: 1))
                XCTAssertNil(fight.fighters[1].attack)
                XCTAssertFalse(fight.fighters[1].guarding)
                if !value.durationActive && value.motion == .loop {
                    sawWait = true
                    XCTAssertEqual(fight.triadState(0)?.rootRemainingTicks, 0)
                }
                if value.motion == .end { sawEnd = true }
                if old?.motion == .start && value.motion == .loop {
                    XCTAssertEqual(samples.map(\.clip), [State.Motion.start.clip, State.Motion.loop.clip])
                    XCTAssertEqual(samples.map(\.tick), [78, 0])
                    sawBoundary = true
                }
                let key = value.motion.rawValue + "/" + String(value.tick)
                if [0, 38, 94].contains(value.tick), visited.insert(key).inserted {
                    XCTAssertEqual(try DuelReplayStateEncoding.encode(fight), try DuelReplayStateEncoding.encode(peer))
                }
            } else if sawEnd {
                XCTAssertEqual(fight.fighters[1].weaponPose?.clip, fight.profiles[1].roles["getUp"])
                XCTAssertEqual(fight.fighters[1].weaponPose?.tick, 0)
                break
            }
        }
        XCTAssertGreaterThan(frozenSteps, 0)
        XCTAssertTrue(sawWait); XCTAssertTrue(sawEnd); XCTAssertTrue(sawBoundary)
        XCTAssertEqual(crossings, 1)
        XCTAssertNil(fight.rootVictimState(1))
        for _ in 0..<40 { fight.step(.neutral, opponent: .neutral) }
        XCTAssertNil(fight.fighters[1].attack, "Locked heavy presses cannot become a buffered attack after release")
    }

    func testMirroredSeatUsesTheSameSourceStagesAndPreservesPelvisAcrossTransitions() throws {
        var fight = try F.fight(swapped: true); try F.catchRoot(&fight, swapped: true)
        XCTAssertEqual(fight.rootVictimState(0)?.owner, 1)
        XCTAssertEqual(fight.rootVictimState(0)?.direction, 1)
        var transitions = 0
        // Source follow-up contacts can add real hit-stop; the bound counts
        // wall steps while the victim sequence advances only on live ticks.
        for _ in 0..<380 {
            let old = fight.rootVictimState(0), oldPelvis = fight.sourcePelvis(0)?.x
            fight.step(.neutral, opponent: .neutral)
            if let old, let value = fight.rootVictimState(0), old.motion != value.motion {
                transitions += 1
                XCTAssertLessThan(abs(try XCTUnwrap(fight.sourcePelvis(0)?.x) - XCTUnwrap(oldPelvis)), 0.002)
            }
            if old != nil && fight.rootVictimState(0) == nil { break }
        }
        XCTAssertEqual(transitions, 2)
        XCTAssertNil(fight.rootVictimState(0)); XCTAssertNil(fight.rootVictimState(1))
    }

    func testMissingOriginalVictimMotionsRetainExplicitLegacyFallback() throws {
        var fight = try F.fight(targetMotions: false); try F.catchRoot(&fight)
        XCTAssertNil(fight.rootVictimState(1))
        XCTAssertEqual(fight.fighters[1].weaponPose?.clip, fight.profiles[1].roles["hit"])
        XCTAssertFalse(State.matches(profile: fight.profiles[1]))
    }

    func testLethalRootRoundEndClearsVictimOwnershipBeforeTheNextRound() throws {
        var fight = try F.fight(mode: .versus, targetHealth: 1)
        fight.step(.init(weaponCommand: .shadow), opponent: .neutral)
        XCTAssertTrue(DuelTriadFightFixture.until(&fight, limit: 110) { $0.phase != .fighting })
        XCTAssertNil(fight.rootVictimState(0)); XCTAssertNil(fight.rootVictimState(1))
        XCTAssertEqual(fight.fighters[1].weaponPose?.clip, fight.profiles[1].roles["knockdown"])
        XCTAssertTrue(DuelTriadFightFixture.until(&fight, limit: 160) { $0.roundNumber == 2 })
        XCTAssertNil(fight.rootVictimState(1)); XCTAssertEqual(fight.fighters[1].stun, 0)
        XCTAssertEqual(fight.fighters[1].weaponPose?.clip, fight.profiles[1].roles["idle"])
    }
}
