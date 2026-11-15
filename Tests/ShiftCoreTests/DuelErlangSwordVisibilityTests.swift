import XCTest
@testable import ShiftCore

final class DuelErlangSwordVisibilityTests: XCTestCase {
    private func charged() -> DuelErlangFightState {
        var state = DuelErlangFightState(seed: 17)
        // Source non-Magic physical contacts can fill Light without invoking
        // the Imperial-weapon-only random sword creation branch.
        for _ in 0..<40 {
            state.acceptedPhysicalContact(kind: .unarmed, imperialSpear: false,
                generated: false, targetHasDogDebuff: false)
        }
        XCTAssertEqual(state.light, 10_000); XCTAssertEqual(state.swords, 0)
        return state
    }
    func testHideSurvivesInterruptionUntilTheRealEndAndRoundResetClearsIt() {
        var state = charged()
        XCTAssertTrue(state.start(.ascend, duration: 160, direction: 1, x: 3500))
        XCTAssertTrue(state.swordsHidden)
        for _ in 0..<7 { state.advance() }
        state.interrupt()
        XCTAssertNil(state.cast); XCTAssertTrue(state.swordsHidden, "No AnimationEnd means no source SHOW")
        XCTAssertTrue(state.start(.ascend, duration: 160, direction: 1, x: 3500))
        _ = state.release()
        for _ in 0..<159 { state.advance() }
        XCTAssertTrue(state.swordsHidden); XCTAssertEqual(state.swords, 0)
        state.advance()
        XCTAssertFalse(state.swordsHidden); XCTAssertEqual(state.cast?.tick, 160)
        XCTAssertEqual(state.cast?.sourceEndProcessed, true)
        XCTAssertEqual(state.swords, 6); XCTAssertEqual(state.takeSwordSpawnSlots(), Array(1...6))
        state.completeCast()
        XCTAssertTrue(state.takeSwordSpawnSlots().isEmpty, "Idle cannot deliver a duplicate End/refill")
        XCTAssertTrue(state.canUse(.swords), "Actual source SHOW permits the existing held swords")
        XCTAssertTrue(state.start(.judgement, duration: 396, direction: 1, x: 3500))
        XCTAssertTrue(state.swordsHidden)
        state.interrupt()
        XCTAssertEqual(state.swords, 6); XCTAssertNil(state.cast)
        XCTAssertFalse(state.canUse(.swords), "1440/t13-14 reject D15_SWORDS_HIDEN even after the cast is interrupted")
        XCTAssertFalse(state.requestSwords())
        state.resetRound(seed: 17)
        XCTAssertFalse(state.swordsHidden); XCTAssertNil(state.cast)
    }
    func testUltimateTimersAndRefillBeginAtSourceEndWithoutIdleRefresh() {
        var state = charged()
        XCTAssertTrue(state.start(.ascend, duration: 160, direction: -1, x: 6500))
        _ = state.release()
        for _ in 0..<160 { state.advance() }
        state.completeCast(); _ = state.takeSwordSpawnSlots()
        XCTAssertTrue(state.start(.judgement, duration: 396, direction: -1, x: 6500))
        _ = state.release()
        state.advance()
        XCTAssertTrue(state.takeSwordConsumeEvent()); state.consumedSwordModels(6)
        XCTAssertEqual(state.swords, 0)
        for _ in 1..<395 { state.advance() }
        XCTAssertEqual(state.cast?.tick, 395); XCTAssertTrue(state.swordsHidden)
        XCTAssertEqual(state.wrathTicks, 0); XCTAssertEqual(state.wrathRefillTicks, 0)
        state.advance()
        XCTAssertEqual(state.cast?.tick, 396); XCTAssertFalse(state.swordsHidden)
        XCTAssertEqual(state.wrathTicks, 901); XCTAssertEqual(state.wrathRefillTicks, 180)
        XCTAssertEqual(state.takeSwordSpawnSlots(), Array(1...6))
        state.advance(); state.completeCast()
        XCTAssertEqual(state.wrathTicks, 900); XCTAssertEqual(state.wrathRefillTicks, 179)
        XCTAssertTrue(state.takeSwordSpawnSlots().isEmpty)
    }
}
