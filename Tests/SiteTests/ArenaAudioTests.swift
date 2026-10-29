import XCTest
import AVFoundation
import UIKit
@testable import ShiftReminder

@MainActor
final class ArenaAudioTests: XCTestCase {
    func testThemeReplacementPreservesPausedBattleAndDoesNotRestartAudio() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: ArenaSound.muteKey)
        defaults.set(true, forKey: ArenaSound.muteKey)
        defer {
            if let previous { defaults.set(previous, forKey: ArenaSound.muteKey) }
            else { defaults.removeObject(forKey: ArenaSound.muteKey) }
        }
        let sound = ArenaSound()
        sound.enterLobby()
        sound.begin()
        sound.pauseRenderer()
        sound.themeChanged()
        XCTAssertEqual(sound.state.scene, .battle)
        XCTAssertFalse(sound.state.canPlay)
        XCTAssertTrue(sound.loadedMusicFiles.isEmpty)
        sound.begin()
        XCTAssertEqual(sound.state.scene, .battle)
        sound.end()
        sound.leaveLobby()
    }

    func testEveryEffectPredecodesToSharedPCMWithoutTruncation() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        var urls = try ArenaSound.Effect.allCases.map {
            try XCTUnwrap(Bundle.main.url(forResource: $0.file, withExtension: "wav"))
        }
        for name in ["win", "lose"] {
            urls.append(try XCTUnwrap(Bundle.main.url(forResource: "arena_theme_" + name, withExtension: "m4a")))
        }
        for url in urls {
            let source = try AVAudioFile(forReading: url)
            let buffer = try ArenaEffectMixer.decode(url, format: format)
            XCTAssertEqual(buffer.format.sampleRate, 44_100)
            XCTAssertEqual(buffer.format.channelCount, 1)
            XCTAssertEqual(Double(buffer.frameLength) / format.sampleRate,
                           Double(source.length) / source.processingFormat.sampleRate, accuracy: 0.01)
        }
    }

    func testPersistentMixerActuallyRendersAndClearsQueuedSoundsOnPause() throws {
        let engine = AVAudioEngine()
        let mixer = ArenaEffectMixer(engine: engine)
        mixer.load(theme: false)
        XCTAssertEqual(mixer.loadedCount, ArenaSound.Effect.allCases.count)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        mixer.resume()
        XCTAssertTrue(mixer.running)
        mixer.play(.shot, volume: 0.7)
        let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        var peak: Float = 0
        for _ in 0..<12 {
            let status = try engine.renderOffline(1024, to: output)
            if status == .success, let channel = output.floatChannelData?[0] {
                for frame in 0..<Int(output.frameLength) { peak = max(peak, abs(channel[frame])) }
            }
        }
        XCTAssertGreaterThan(peak, 0.001)
        mixer.play(.power, volume: 1)
        mixer.pause()
        XCTAssertFalse(mixer.running)
        mixer.resume()
        XCTAssertTrue(mixer.running)
        // stop() removed the queued power effect, so resuming stays silent.
        for _ in 0..<4 { _ = try engine.renderOffline(1024, to: output) }
        if let channel = output.floatChannelData?[0] {
            XCTAssertTrue((0..<Int(output.frameLength)).allSatisfy { abs(channel[$0]) < 0.0001 })
        }
        mixer.unload()
        XCTAssertEqual(mixer.loadedCount, 0)
        XCTAssertFalse(mixer.running)
    }

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
