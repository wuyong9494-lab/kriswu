import XCTest
@testable import ShiftCore

final class DuelTriadCapacityTests: XCTestCase {
    /// A validated synthetic stress profile, not the original H17 balance.
    /// Public requests can reach the shared pending-event bound without
    /// advancing time or injecting private queue/resource state.
    private func fullSourceSoulQueue() throws -> DuelTriadState {
        var rules = try DuelTriadTestFixture.runtimeRules()
        rules.mist.maximum = 1_000_000
        rules.mist.initial = rules.mist.maximum
        rules.souls.sharedCooldownTicks = 0
        let legionary = try XCTUnwrap(rules.abilities.firstIndex { $0.ability == .legionary })
        rules.abilities[legionary].cooldownTicks = 0
        try rules.validate()
        var state = try XCTUnwrap(DuelTriadState(rules: rules, seed: 19))
        state.beginRound(roundID: 0)
        for index in 0..<DuelTriadState.maximumPendingEvents {
            XCTAssertTrue(state.canUse(.legionary))
            let events = state.start(.legionary)
            let appearances = events.compactMap { event -> DuelTriadState.SoulAppearance? in
                if case .sourceSoulAppeared(let value) = event { return value }
                return nil
            }
            XCTAssertEqual(appearances.count, 1)
            XCTAssertEqual(appearances.first?.summonID, UInt64(index + 1))
        }
        return state
    }

    private func bytes(_ state: DuelTriadState) throws -> Data {
        var writer = try DuelReplayStateWriter(kind: 2)
        try state.appendReplayState(to: &writer)
        return writer.data
    }

    func testFullPendingSourceSoulQueueRejectsWithoutSpendingResourceCooldownOrIdentity() throws {
        let full = try fullSourceSoulQueue()
        let baseline = try bytes(full)
        for ability in [DuelTriadRules.Ability.legionary, .herald, .dynast] {
            var state = full
            XCTAssertFalse(state.canUse(ability))
            XCTAssertTrue(state.start(ability).isEmpty)
            XCTAssertEqual(state.mist, full.mist)
            XCTAssertEqual(state.notches, full.notches)
            XCTAssertEqual(state.cooldownRemaining(ability), full.cooldownRemaining(ability))
            XCTAssertEqual(state.sharedSoulCooldownRemainingTicks, full.sharedSoulCooldownRemainingTicks)
            XCTAssertTrue(state == full, "A denied request must also preserve private event identity and queues")
            XCTAssertEqual(try bytes(state), baseline, "Denied input must leave canonical replay state unchanged")
        }
    }

    func testSourceSoulCapacityRemainsOccupiedUntilAttacksExpireThenAcceptsANewCast() throws {
        var state = try fullSourceSoulQueue()
        XCTAssertTrue(state.start(.legionary).isEmpty)
        var released: [DuelTriadState.Attack] = []
        for _ in 0..<34 {
            released += state.step().compactMap { event in
                if case .attack(let attack) = event { return attack }
                return nil
            }
        }
        XCTAssertEqual(released.count, DuelTriadState.maximumPendingEvents)
        XCTAssertEqual(Set(released.map(\.id)).count, released.count)
        XCTAssertEqual(released.first?.id, UInt64(DuelTriadState.maximumPendingEvents + 1))
        XCTAssertEqual(released.last?.id, UInt64(DuelTriadState.maximumPendingEvents * 2))
        XCTAssertFalse(state.canUse(.legionary), "Released attacks still occupy the same event budget")
        let occupied = state
        XCTAssertTrue(state.start(.legionary).isEmpty)
        XCTAssertTrue(state == occupied, "Released attacks must retain their capacity until expiry")
        for _ in 0..<17 { _ = state.step() }
        XCTAssertFalse(state.canUse(.legionary))
        _ = state.step()
        XCTAssertTrue(state.canUse(.legionary))
        let before = state.mist
        let cost = try XCTUnwrap(state.rules.ability(.legionary)).mistCost
        let appearances = state.start(.legionary).compactMap { event -> DuelTriadState.SoulAppearance? in
            if case .sourceSoulAppeared(let value) = event { return value }
            return nil
        }
        XCTAssertEqual(appearances.count, 1)
        XCTAssertEqual(appearances.first?.summonID, UInt64(DuelTriadState.maximumPendingEvents * 2 + 1))
        XCTAssertEqual(state.mist, before - cost)
    }
}
