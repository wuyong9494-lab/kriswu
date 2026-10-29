import XCTest
@testable import ShiftCore

final class ArenaAudioStateTests: XCTestCase {
    func testBackgroundDuringBattleNeverSelectsLobby() {
        var state = ArenaAudioState()
        state.enterLobby(); state.begin()
        state.pause(.background); state.pause(.renderer)
        XCTAssertEqual(state.scene, .battle)
        XCTAssertFalse(state.canPlay)
        state.begin() // renderer reattaches before app-active notification
        XCTAssertFalse(state.canPlay)
        state.resume(.background)
        XCTAssertEqual(state.scene, .battle)
        XCTAssertTrue(state.canPlay)
        state.end()
        XCTAssertEqual(state.scene, .lobby)
    }
    func testIndependentPausesAndResultDoNotRestartBattleMusic() {
        var state = ArenaAudioState()
        state.enterLobby(); state.begin(); state.finish()
        state.pause(.interruption); state.pause(.background)
        state.resume(.background); state.begin()
        XCTAssertFalse(state.canPlay)
        state.resume(.interruption)
        XCTAssertEqual(state.scene, .result)
        XCTAssertTrue(state.canPlay)
        state.leaveLobby(); state.end()
        XCTAssertEqual(state.scene, .off)
    }
    func testRepeatedLifecycleEventsAreIdempotent() {
        var state = ArenaAudioState()
        state.enterLobby(); state.enterLobby(); state.begin()
        state.pause(.renderer); state.pause(.renderer)
        state.begin(); state.begin()
        XCTAssertEqual(state.scene, .battle)
        XCTAssertTrue(state.canPlay)
        state.end(); state.end()
        XCTAssertEqual(state.scene, .lobby)
    }
}
