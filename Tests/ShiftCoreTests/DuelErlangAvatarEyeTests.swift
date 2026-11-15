import XCTest
@testable import ShiftCore

final class DuelErlangAvatarEyeTests: XCTestCase {
    private func setUpAvatar(_ game: inout DuelErlangSparring, approach: Int) {
        for _ in 0..<approach { game.step(erlangAction: .walk(1), partnerAction: .walk(-1)) }
        for _ in 0..<30 { game.step() }
        game.step(erlangAction: .meditate)
        for _ in 0..<420 { game.step() }
        game.step(erlangAction: .ascend)
    }
    private func contacts(_ game: DuelErlangSparring) -> [Int] {
        game.events.compactMap {
            if case .contact(attacker: .erlang, strike: .avatarEye, damage: let i, blocked: _) = $0 { return i }
            return nil
        }
    }
    func testGoldenGateAndBaseSustainedContact() {
        var game = DuelErlangSparring(enhancedAvatarEye: false)
        game.step(erlangAction: .avatarEye)
        XCTAssertTrue(game.events.isEmpty)
        setUpAvatar(&game, approach: 7)
        game.step(erlangAction: .avatarEye)
        XCTAssertEqual(Array(game.events.prefix(1)), [.avatarEyeStarted])
        var hits = [Int]()
        for _ in 0..<35 { game.step(); hits += contacts(game) }
        XCTAssertEqual(hits, Array(repeating: 6, count: 6))
        XCTAssertEqual(game.fighters[1].health, 64)
        XCTAssertEqual(game.fighters[1].vulnerabilityStacks, 0)
        game.step(erlangAction: .avatarEye)
        XCTAssertTrue(game.events.isEmpty)
    }

    func testEnhancedVulnerabilityExpiresAndClearsAcrossRound() {
        var game = DuelErlangSparring(mode: .teamRaid)
        setUpAvatar(&game, approach: 7)
        game.step(erlangAction: .avatarEye)
        var hits = [Int]()
        for _ in 0..<21 { game.step(); hits += contacts(game) }
        XCTAssertEqual(hits, [6, 6, 7, 7, 8, 9])
        XCTAssertEqual(game.fighters[1].vulnerabilityStacks, 6)
        for _ in 0..<75 { game.step() }
        XCTAssertEqual(game.fighters[1].vulnerabilityStacks, 0)
        game.resetRound()
        XCTAssertEqual(game.erlang.phase, .ascended)
        XCTAssertEqual(game.avatarEyeCooldown, 0)
    }

    func testGuardAndMotionOutOfRangeEvaluatedPerPulse() {
        var game = DuelErlangSparring()
        setUpAvatar(&game, approach: 3)
        game.step(erlangAction: .avatarEye, partnerAction: .guardOn)
        for _ in 0..<6 { game.step() }
        XCTAssertEqual(contacts(game), [0])
        XCTAssertEqual(game.fighters[1].vulnerabilityStacks, 0)
        game.step(partnerAction: .guardOff)
        game.step()
        game.step()
        XCTAssertEqual(contacts(game), [6])
        for _ in 0..<25 { game.step(partnerAction: .walk(1)) }
        XCTAssertLessThan(game.fighters[1].vulnerabilityStacks, 6)
        XCTAssertGreaterThan(game.fighters[1].health, 57)
    }

    func testOpponentCanInterruptBeforeFirstPulse() {
        var game = DuelErlangSparring()
        setUpAvatar(&game, approach: 10)
        game.step(erlangAction: .avatarEye, partnerAction: .spear)
        for _ in 0..<25 { game.step() }
        XCTAssertEqual(game.fighters[0].health, 90)
        XCTAssertEqual(game.fighters[1].health, 100)
        XCTAssertEqual(game.fighters[1].vulnerabilityStacks, 0)
    }
}
