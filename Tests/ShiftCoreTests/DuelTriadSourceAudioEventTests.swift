import XCTest
@testable import ShiftCore

/// Source lifecycle clocks with synthetic geometry/stat scales. No audio
/// waveform, original asset, native player, or wall clock is involved.
final class DuelTriadSourceAudioEventTests: XCTestCase {
    private func rules(level: Int = 6) throws -> DuelTriadRules {
        var value = try DuelTriadTestFixture.runtimeRules(level: level)
        value.mist.initial = value.mist.maximum
        return value
    }
    private func rootState() throws -> (DuelTriadState, DuelTriadState.Attack) {
        var state = try XCTUnwrap(DuelTriadState(rules: rules(), seed: 9))
        state.beginRound(roundID: 1); state.start(.branches)
        var root: DuelTriadState.Attack?
        for _ in 0..<42 {
            for event in state.step() {
                if case .attack(let attack) = event, attack.delivery == .roots { root = attack }
            }
        }
        return (state, try XCTUnwrap(root))
    }
    private func sourceEvents(_ fight: DuelWeaponFight) -> [DuelTriadPresentation.SourceEvent] {
        fight.triadPresentationEvents.compactMap {
            if case .source(let owner, let event) = $0.kind, owner == 0 { return event }
            return nil
        }
    }

    func testUnlatchedRootEndsAtItsExplicitSelfEndZeroTickSixty() throws {
        var (state, root) = try rootState()
        for tick in 1..<60 {
            XCTAssertFalse(state.step().contains(.sourceRootModelEnded(sourceID: root.id)), "tick \(tick)")
        }
        XCTAssertEqual(state.step().filter { if case .sourceRootModelEnded = $0 { return true }; return false },
                       [.sourceRootModelEnded(sourceID: root.id)])
        XCTAssertFalse(state.step().contains(.sourceRootModelEnded(sourceID: root.id)))
        XCTAssertFalse(state.finishRound(won: false, eventID: 100).contains(.sourceRootModelEnded(sourceID: root.id)))
    }

    func testCapturedRootKeepsItsModelUntilTheOriginalHoldExpires() throws {
        var (state, root) = try rootState()
        for _ in 0..<22 { state.step() }
        let contact = state.contact(attackID: root.id, context: .init(), eventID: 1)
        XCTAssertTrue(contact.accepted)
        let hold = state.rootRemainingTicks
        XCTAssertGreaterThan(hold, 60)
        for _ in 1..<hold { XCTAssertFalse(state.step().contains(.sourceRootModelEnded(sourceID: root.id))) }
        let ended = state.step()
        XCTAssertTrue(ended.contains(.sourceRootModelEnded(sourceID: root.id)))
        XCTAssertTrue(ended.contains(.controlReleased(sourceID: root.id, kind: .root)))
    }

    func testOwnerInterruptionDoesNotDestroyAnAlreadyCreatedRootButRoundEndDoes() throws {
        var (state, root) = try rootState()
        XCTAssertFalse(state.interrupt().contains(.sourceRootModelEnded(sourceID: root.id)))
        for _ in 0..<5 { state.step() }
        let end = state.finishRound(won: false, eventID: 1)
        XCTAssertEqual(end.filter { if case .sourceRootModelEnded = $0 { return true }; return false },
                       [.sourceRootModelEnded(sourceID: root.id)])
        XCTAssertTrue(state.finishRound(won: false, eventID: 1).isEmpty)
        XCTAssertTrue(state.step().isEmpty)
    }

    func testFirstArenaAmbienceEventIsImmediateAndSeparateFromOriginalIntro() throws {
        var fight = try DuelTriadFightFixture.fight(rules: rules())
        XCTAssertFalse(sourceEvents(fight).contains(.arenaForestLoopStarted(roundID: 1)))
        fight.step(.init(weaponCommand: .ranged), opponent: .neutral)
        XCTAssertTrue(sourceEvents(fight).contains(.arenaForestLoopStarted(roundID: 1)))
        XCTAssertFalse(sourceEvents(fight).contains(.roundStarted(roundID: 1)))
        XCTAssertEqual(fight.triadState(0)?.ownerMotion?.animation, .mistOnslaught1,
                       "The arena ambience adapter does not delay first-tick input for an intro")
        fight.step(.neutral, opponent: .neutral)
        XCTAssertFalse(sourceEvents(fight).contains(.arenaForestLoopStarted(roundID: 1)))
    }

    func testWaveModelBirthOccursAtOwnerSourceTickTwentySix() throws {
        var fight = try DuelTriadFightFixture.fight(rules: rules(), distance: 2600)
        fight.step(.init(weaponCommand: .ranged), opponent: .neutral)
        let start = fight.triadPresentation.liveTick
        for tick in 1...26 {
            fight.step(.neutral, opponent: .neutral)
            let waves = sourceEvents(fight).filter {
                if case .modelCreated(_, .mistWave, _) = $0 { return true }; return false
            }
            XCTAssertEqual(waves.count, tick == 26 ? 1 : 0)
        }
        XCTAssertEqual(fight.triadPresentation.liveTick, start + 26)
    }

    func testCommonSoulsEndOnTheirOwnSourceAnimationClockAfterAttackRelease() throws {
        let choices: [(DuelGame.Input, DuelTriadRules.SummonMove)] = [
            (.init(vertical: -1, weaponCommand: .shadow), .legionSword),
            (.init(vertical: 1, weaponCommand: .shadow), .heraldDash),
            (.init(move: -1, weaponCommand: .shadow), .dynastyBow)]
        for (input, move) in choices {
            var fight = try DuelTriadFightFixture.fight(rules: rules(), distance: 2600, targetHealth: 1_000_000)
            fight.step(input, opponent: .neutral)
            let id = try XCTUnwrap(sourceEvents(fight).compactMap { event -> UInt64? in
                if case .soulModelCreated(let id, let actual) = event, actual == move { return id }; return nil
            }.first)
            let born = fight.triadPresentation.liveTick
            var ended: [Int] = []
            for _ in 0..<(move.endEventTick + 30) {
                fight.step(.neutral, opponent: .neutral)
                if sourceEvents(fight).contains(.soulAnimationEnded(id: id, role: move.role)) {
                    ended.append(fight.triadPresentation.liveTick)
                }
            }
            XCTAssertEqual(ended, [born + move.endEventTick], move.rawValue)
        }
    }
}
