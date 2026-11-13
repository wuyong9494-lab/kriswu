import XCTest
@testable import ShiftReminder

@MainActor
final class DuelLobbyMusicSelectionTests: XCTestCase {
    func testTemporaryLobbyUsesOnlyVerifiedTempleFallAndPreservesBattle() {
        let lobby = URL(fileURLWithPath: "/verified-temple-fall.wav")
        let battle = URL(fileURLWithPath: "/verified-palace.wav")
        var result = DuelSourceMusic.Result()
        result.tracks[.battle] = battle
        result.verifiedClips[DuelSourceMusic.temporaryLobbyTrackName] = lobby
        let selected = DuelSourceMusic.playbackTracks(from: result)
        XCTAssertEqual(selected[.lobby], lobby)
        XCTAssertEqual(selected[.battle], battle)
        XCTAssertNil(DuelSourceMusic.records.first { $0.name == DuelSourceMusic.temporaryLobbyTrackName }?.scene)
    }
    func testMissingOrRejectedClipCannotBecomeLobbyMusic() {
        var result = DuelSourceMusic.Result()
        result.failures = [.digest(DuelSourceMusic.temporaryLobbyTrackName)]
        XCTAssertNil(DuelSourceMusic.playbackTracks(from: result)[.lobby])
    }
    func testProvenLobbyBindingTakesPriorityOverTemporaryFallback() {
        let proven = URL(fileURLWithPath: "/proven-lobby.wav")
        var result = DuelSourceMusic.Result()
        result.tracks[.lobby] = proven
        result.verifiedClips[DuelSourceMusic.temporaryLobbyTrackName] = URL(fileURLWithPath: "/fallback.wav")
        XCTAssertEqual(DuelSourceMusic.playbackTracks(from: result)[.lobby], proven)
    }
}
