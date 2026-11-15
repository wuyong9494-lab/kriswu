import XCTest
@testable import ShiftCore

final class DuelErlangLightSwordsTests: XCTestCase {
    func testOnlyConfirmedSpearHitsCountAndActivationIsSeparate() {
        var state = DuelErlangLightSwords()
        XCTAssertNil(state.recordSpearContact(.missed))
        XCTAssertNil(state.recordSpearContact(.blocked))
        XCTAssertNil(state.recordSpearContact(.landed))
        XCTAssertEqual(state.active, 0)
        XCTAssertEqual(state.recordAvatarActivation(.step), .summoned(count: 2))
        XCTAssertEqual(state.active, 2)
        XCTAssertEqual(state.recordSpearContact(.landed), .summoned(count: 1))
        XCTAssertEqual(state.active, 3)
    }

    func testCapAndDelayedExplicitLaunch() {
        var state = DuelErlangLightSwords()
        XCTAssertNil(state.requestLaunch())
        for _ in 0..<7 { state.recordAvatarActivation(.step) }
        XCTAssertEqual(state.active, 6)
        XCTAssertEqual(state.requestLaunch(), .launchQueued(count: 6))
        XCTAssertEqual(state.active, 0)
        XCTAssertNil(state.requestLaunch())
        state.recordAvatarActivation(.eye)
        for _ in 0..<13 { XCTAssertNil(state.step()) }
        XCTAssertEqual(state.step(), .launchReleased(count: 6))
        XCTAssertEqual(state.active, 2)
        XCTAssertNil(state.requestLaunch())
        state.enterAvatar()
        XCTAssertEqual(state.requestLaunch(), .launchQueued(count: 2))
        state.clearRound()
        for _ in 0..<40 { XCTAssertNil(state.step()) }
        XCTAssertEqual(state.active, 0)
    }

    func testAvatarWhiffSummonsButSpearWhiffDoesNot() {
        var game = DuelErlangSparring()
        game.step(erlangAction: .spear)
        for _ in 0..<30 { game.step() }
        XCTAssertEqual(game.lightSwords.active, 0)
        game.step(erlangAction: .meditate)
        for _ in 0..<420 { game.step() }
        game.step(erlangAction: .ascend)
        game.step(erlangAction: .earthshaker)
        XCTAssertTrue(game.events.contains(.lightSwords(.summoned(count: 2))))
        for _ in 0..<35 { game.step() }
        XCTAssertEqual(game.fighters[1].health, 100) // out of Earthshaker range
        XCTAssertEqual(game.lightSwords.active, 2)
    }

    func testSparringDelayedVolleySeparatesReleaseFromHit() {
        var game = DuelErlangSparring()
        for _ in 0..<7 { game.step(erlangAction: .walk(1), partnerAction: .walk(-1)) }
        for _ in 0..<30 { game.step() }
        game.step(erlangAction: .meditate)
        for _ in 0..<420 { game.step() }
        game.step(erlangAction: .ascend)
        game.step(erlangAction: .earthshaker)
        for _ in 0..<35 { game.step() }
        let before = game.fighters[1].health
        game.step(erlangAction: .lightSwords)
        XCTAssertEqual(game.events, [.lightSwords(.launchQueued(count: 2))])
        for _ in 0..<13 { game.step(); XCTAssertTrue(game.events.isEmpty) }
        XCTAssertEqual(game.fighters[1].health, before)
        game.step()
        XCTAssertEqual(game.events, [.lightSwords(.launchReleased(count: 2)),
            .contact(attacker: .erlang, strike: .lightSwords, damage: 4, blocked: false),
            .contact(attacker: .erlang, strike: .lightSwords, damage: 4, blocked: false)])
        XCTAssertEqual(game.fighters[1].health, before - 8)
    }
}
