import XCTest
@testable import ShiftCore

final class DuelErlangL3MeditationTests: XCTestCase {
    private func stage(close: Bool = true) -> DuelErlangSparring {
        var game = DuelErlangSparring(enableLevelThreeMeditation: true)
        for i in 0..<30 {
            game.step(erlangAction: close && i < 10 ? .walk(1) : nil,
                      partnerAction: close && i < 10 ? .walk(-1) : nil)
        }
        game.step(erlangAction: .meditate)
        return game
    }

    func testMeditationBlastScalesAndReducesCooldownOnlyIfItDealsDamage() {
        for (duration, close, block, expected) in [
            (12, true, false, 2), (24, true, false, 4), (24, false, false, 0), (24, true, true, 0)
        ] {
            var game = stage(close: close)
            for _ in 0..<(duration - 1) { game.step() }
            game.step(erlangAction: .stopMeditation, partnerAction: block ? .guardOn : nil)
            XCTAssertEqual(game.erlang.phase, .base)
            XCTAssertTrue(game.events.contains(.meditationBlastReleased(ticksHeld: duration)))
            XCTAssertEqual(game.fighters[1].health, 100 - expected)
            XCTAssertEqual(game.erlang.meditationCooldown, expected > 0 ? 32 : 48)
            game.step()
            XCTAssertFalse(game.events.contains(.meditationBlastReleased(ticksHeld: duration)))
        }
    }

    func testRangedWeaponImmuneOnlyWhileMeditatingAndMeleeStillInterrupts() {
        var game = stage()
        game.step(partnerAction: .partnerRanged)
        for _ in 0..<3 { game.step() }
        XCTAssertTrue(game.events.contains(.rangedDamagePrevented))
        XCTAssertEqual(game.erlang.phase, .meditating)
        XCTAssertEqual(game.fighters[0].health, 100)
        for _ in 0..<9 { game.step() }
        game.step(partnerAction: .spear)
        for _ in 0..<3 { game.step() }
        XCTAssertTrue(game.events.contains(.cue(.meditationInterrupted)))
        XCTAssertEqual(game.fighters[0].health, 90)
        XCTAssertEqual(game.fighters[1].health, 100)
        XCTAssertEqual(game.erlang.phase, .base)
        for _ in 0..<12 { game.step() }
        game.step(partnerAction: .partnerRanged)
        for _ in 0..<3 { game.step() }
        XCTAssertFalse(game.events.contains(.rangedDamagePrevented))
        XCTAssertEqual(game.fighters[0].health, 82)
    }

    func testEnlightenmentIncreasesDamageExpiresIndependentlyAndRoundClears() {
        var game = stage()
        for _ in 0..<72 { game.step() }
        XCTAssertEqual(game.enlightenmentStacks, 3)
        game.step(erlangAction: .stopMeditation)
        let afterBlast = game.fighters[1].health
        game.step(erlangAction: .spear)
        for _ in 0..<4 { game.step() }
        XCTAssertEqual(afterBlast - game.fighters[1].health, 15)
        for _ in 0..<40 { game.step() }
        XCTAssertEqual(game.enlightenmentStacks, 2)
        for _ in 0..<96 { game.step() }
        XCTAssertEqual(game.enlightenmentStacks, 0)
        game.resetRound()
        XCTAssertEqual(game.enlightenmentStacks, 0)
    }

    func testNaturalMeditationCompletionTriggersOnceAndAvatarHoldsStacks() {
        var game = stage(close: false)
        var releaseCount = 0
        for _ in 0..<420 {
            game.step()
            releaseCount += game.events.filter {
                if case .meditationBlastReleased = $0 { return true }
                return false
            }.count
        }
        XCTAssertEqual(releaseCount, 1)
        XCTAssertGreaterThan(game.enlightenmentStacks, 0)
        game.step(erlangAction: .ascend)
        XCTAssertEqual(game.erlang.phase, .ascended)
        let stacks = game.enlightenmentStacks
        for _ in 0..<100 { game.step() }
        XCTAssertEqual(game.enlightenmentStacks, stacks)
        game.resetRound()
        XCTAssertEqual(game.enlightenmentStacks, 0)
    }
}
