import XCTest
import AVFoundation
import UIKit
@testable import ShiftReminder

@MainActor
final class ArenaAudioTests: XCTestCase {
    func testThemeFilesDecodeAndKeepRequiredDurations() throws {
        let bundle = Bundle(for: ArenaSound.self)
        for (name, minimum) in [("lobby", 60.0), ("battle", 59.9), ("win", 4.9), ("lose", 4.9)] {
            let url = try XCTUnwrap(bundle.url(forResource: "arena_theme_" + name, withExtension: "m4a"))
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThanOrEqual(player.duration, minimum)
            XCTAssertLessThan(player.duration, 91)
            XCTAssertTrue(player.prepareToPlay())
        }
    }

    func testRendererAndBackgroundPausePreserveBattleAudioScene() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: ArenaSound.muteKey)
        defaults.set(true, forKey: ArenaSound.muteKey)
        defer {
            if let previous { defaults.set(previous, forKey: ArenaSound.muteKey) }
            else { defaults.removeObject(forKey: ArenaSound.muteKey) }
        }
        let sound = ArenaSound()
        sound.enterLobby(); sound.begin()
        sound.pauseRenderer()
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertEqual(sound.state.scene, .battle)
        XCTAssertFalse(sound.state.canPlay)
        sound.begin()
        XCTAssertFalse(sound.state.canPlay)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(sound.state.scene, .battle)
        XCTAssertTrue(sound.state.canPlay)
        sound.finish(won: true)
        sound.pauseRenderer(); sound.begin()
        XCTAssertEqual(sound.state.scene, .result)
        sound.end()
        XCTAssertEqual(sound.state.scene, .lobby)
        let first = NSObject(), second = NSObject()
        sound.begin(owner: ObjectIdentifier(first))
        sound.finish(won: false)
        sound.begin(owner: ObjectIdentifier(second))
        sound.end(owner: ObjectIdentifier(first)) // stale view teardown must not end the new match
        XCTAssertEqual(sound.state.scene, .battle)
        sound.end(owner: ObjectIdentifier(second))
        sound.leaveLobby()
    }
}
