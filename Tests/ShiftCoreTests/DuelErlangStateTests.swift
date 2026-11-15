import Foundation
import XCTest
@testable import ShiftCore

final class DuelErlangStateTests: XCTestCase {
    func testMeditationPulsesAndInterruptionClearsPartialProgress() {
        var fighter = DuelErlangState(mode: .versus)
        XCTAssertNil(fighter.apply(.beginMeditation))
        for _ in 0..<30 { fighter.apply(.tick) }
        XCTAssertEqual(fighter.apply(.beginMeditation), .meditationStarted)
        for _ in 0..<12 { fighter.apply(.tick) }
        XCTAssertEqual(fighter.light, 3)
        for _ in 0..<11 { fighter.apply(.tick) }
        XCTAssertEqual(fighter.apply(.interruptMeditation), .meditationInterrupted)
        XCTAssertNil(fighter.apply(.beginMeditation))
        for _ in 0..<48 { fighter.apply(.tick) }
        XCTAssertEqual(fighter.apply(.beginMeditation), .meditationStarted)
        fighter.apply(.tick)
        XCTAssertEqual(fighter.light, 3)
    }

    func testAscensionNeedsFullLightAndPersistsOnlyInRaid() {
        for mode in [DuelErlangState.Mode.versus, .teamRaid] {
            var fighter = DuelErlangState(mode: mode)
            XCTAssertNil(fighter.apply(.ascend))
            for _ in 0..<21 { fighter.apply(.weaponHit) }
            XCTAssertEqual(fighter.light, 100)
            XCTAssertEqual(fighter.apply(.ascend), .ascension)
            XCTAssertNil(fighter.apply(.ascend))
            XCTAssertNil(fighter.apply(.hound))
            XCTAssertNil(fighter.apply(.beginMeditation))
            fighter.apply(.nextRound)
            XCTAssertEqual(fighter.phase, mode == .teamRaid ? .ascended : .base)
            fighter.apply(.nextMatch)
            XCTAssertEqual(fighter.phase, .base)
            XCTAssertEqual(fighter.light, 0)
        }
    }

    func testHoundCooldownAndMeditationGate() {
        var fighter = DuelErlangState(mode: .versus)
        for _ in 0..<30 { fighter.apply(.tick) }
        fighter.apply(.beginMeditation)
        XCTAssertNil(fighter.apply(.hound))
        fighter.apply(.interruptMeditation)
        XCTAssertEqual(fighter.apply(.hound), .houndRush)
        for _ in 0..<89 { fighter.apply(.tick) }
        XCTAssertNil(fighter.apply(.hound))
        fighter.apply(.tick)
        XCTAssertEqual(fighter.apply(.hound), .houndRush)
    }

    func testEncodedStateRetainsPartialMeditationAndCooldown() throws {
        var fighter = DuelErlangState(mode: .teamRaid)
        fighter.apply(.hound)
        for _ in 0..<30 { fighter.apply(.tick) }
        fighter.apply(.beginMeditation)
        for _ in 0..<7 { fighter.apply(.tick) }
        let persisted = try JSONEncoder().encode(fighter)
        var restored = try JSONDecoder().decode(DuelErlangState.self, from: persisted)
        XCTAssertEqual(restored, fighter)
        for _ in 0..<5 { fighter.apply(.tick); restored.apply(.tick) }
        XCTAssertEqual(restored, fighter)
        XCTAssertEqual(restored.light, 3)
    }
}
