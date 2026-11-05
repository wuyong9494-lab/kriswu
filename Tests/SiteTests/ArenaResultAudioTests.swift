import AVFoundation
import CryptoKit
import UIKit
import XCTest
@testable import ShiftReminder

@MainActor
final class ArenaResultAudioTests: XCTestCase {
    @MainActor private final class Players {
        var byRole: [String: [AVAudioPlayer]] = [:]

        func make(_ url: URL) throws -> AVAudioPlayer {
            let player = try AVAudioPlayer(contentsOf: url)
            byRole[url.deletingPathExtension().lastPathComponent, default: []].append(player)
            return player
        }

        func latest(_ role: String) throws -> AVAudioPlayer {
            try XCTUnwrap(byRole[role]?.last)
        }
    }

    /// Generated tones exercise the real archive installer and AVAudioPlayer.
    /// No source-game audio or private resource pack is used in CI.
    private func writePack(at root: URL, seconds: Double) throws -> URL {
        let rate = 16_000
        var pcm = Data()
        for frame in 0..<Int(Double(rate) * seconds) {
            var sample = Int16(sin(Double(frame) * 440 * 2 * .pi / Double(rate)) * 2_000).littleEndian
            pcm.append(withUnsafeBytes(of: &sample) { Data($0) })
        }
        var wav = Data("RIFF".utf8)
        func append32(_ value: UInt32) {
            var little = value.littleEndian
            wav.append(withUnsafeBytes(of: &little) { Data($0) })
        }
        func append16(_ value: UInt16) {
            var little = value.littleEndian
            wav.append(withUnsafeBytes(of: &little) { Data($0) })
        }
        append32(UInt32(36 + pcm.count)); wav.append(Data("WAVEfmt ".utf8))
        append32(16); append16(1); append16(1)
        append32(UInt32(rate)); append32(UInt32(rate * 2)); append16(2); append16(16)
        wav.append(Data("data".utf8)); append32(UInt32(pcm.count)); wav.append(pcm)
        let roles = ["lobby", "battle", "win", "lose"]
        let digest = SHA256.hash(data: wav).map { String(format: "%02x", $0) }.joined()
        let manifest: [String: Any] = [
            "schemaVersion": 1, "id": "synthetic-result-audio", "title": "Synthetic audio",
            "sourceDescription": "Generated test tones only", "sourceSHA256": String(repeating: "0", count: 64),
            "heroes": [], "themes": [], "maps": [],
            "music": roles.map { ["id": $0, "title": $0, "file": "audio/\($0).wav", "cues": []] as [String: Any] },
            "musicBindings": Dictionary(uniqueKeysWithValues: roles.map { ($0, $0) }),
            "files": roles.map { ["path": "audio/\($0).wav", "bytes": wav.count,
                                   "sha256": digest, "kind": "music"] as [String: Any] }]
        let raw = try JSONSerialization.data(withJSONObject: manifest, options: .sortedKeys)
        var bytes = ArenaResourcePackArchive.magic
        var length = UInt32(raw.count).littleEndian
        bytes.append(withUnsafeBytes(of: &length) { Data($0) }); bytes.append(raw)
        for _ in roles { bytes.append(wav) }
        let url = root.appendingPathComponent("test.arenapack")
        try bytes.write(to: url)
        return url
    }

    private func fixture(seconds: Double = 8,
                         _ body: @MainActor (ArenaSound, Players) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "result-audio-\(UUID().uuidString)"
        let packDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { packDefaults.removePersistentDomain(forName: suite) }
        packDefaults.set(true, forKey: "arena.resources.hasChosenCombatHero")
        let resources = ArenaResourcePackStore(defaults: packDefaults, directory: root.appendingPathComponent("installed"))
        await resources.install(from: try writePack(at: root, seconds: seconds))
        XCTAssertNil(resources.error)

        let defaults = UserDefaults.standard
        let keys = [ArenaSound.muteKey, ArenaSound.musicMuteKey, ArenaSound.effectsMuteKey]
        let previous = keys.map { ($0, defaults.object(forKey: $0)) }
        keys.forEach { defaults.set(false, forKey: $0) }
        defer {
            for (key, value) in previous {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        let players = Players()
        let sound = ArenaSound(resources: resources, makeMusicPlayer: { try players.make($0) })
        defer {
            sound.end(); sound.leaveLobby()
            players.byRole.values.flatMap { $0 }.forEach { $0.stop() }
        }
        try await body(sound, players)
    }

    func testResultResumesForSameRendererAfterBackground() async throws {
        try await fixture { sound, players in
            sound.enterLobby(); sound.begin(); sound.finish(won: true)
            let win = try players.latest("win")
            XCTAssertTrue(win.isPlaying)
            sound.pauseRenderer()
            NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
            win.currentTime = 1.25
            sound.begin() // renderer attaches before the app-active notification
            XCTAssertFalse(win.isPlaying)
            XCTAssertEqual(sound.state.scene, .result)
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            XCTAssertTrue(win.isPlaying)
            XCTAssertEqual(win.currentTime, 1.25, accuracy: 0.2)
            XCTAssertFalse(try players.latest("battle").isPlaying)
        }
    }

    func testReturningLobbyStopsResultBeforeLobbyCallback() async throws {
        try await fixture { sound, players in
            sound.enterLobby(); sound.begin(); sound.finish(won: false)
            let lose = try players.latest("lose")
            XCTAssertTrue(lose.isPlaying)
            sound.end() // no enterLobby/onDismiss callback is needed for cleanup
            XCTAssertFalse(lose.isPlaying)
            XCTAssertTrue(try players.latest("lobby").isPlaying)
            XCTAssertEqual(sound.state.scene, .lobby)
        }
    }

    func testLobbyReappearanceDoesNotEraseActiveResult() async throws {
        try await fixture { sound, players in
            sound.begin(); sound.finish(won: true)
            let win = try players.latest("win")
            win.currentTime = 1.25
            sound.enterLobby()
            XCTAssertEqual(sound.state.scene, .result)
            XCTAssertTrue(win.isPlaying)
            XCTAssertEqual(win.currentTime, 1.25, accuracy: 0.2)
            XCTAssertFalse(try players.latest("lobby").isPlaying)
        }
    }

    func testThemeReplacementWhilePausedKeepsResultPosition() async throws {
        try await fixture { sound, players in
            sound.enterLobby(); sound.begin(); sound.finish(won: true)
            let old = try players.latest("win")
            sound.pauseRenderer(); old.currentTime = 1.25
            sound.themeChanged(); sound.themeChanged()
            XCTAssertFalse(old.isPlaying)
            XCTAssertTrue(sound.loadedMusicFiles.isEmpty)
            sound.begin()
            let updated = try players.latest("win")
            XCTAssertFalse(old === updated)
            XCTAssertEqual(sound.state.scene, .result)
            XCTAssertTrue(updated.isPlaying)
            XCTAssertEqual(updated.currentTime, 1.25, accuracy: 0.2)
            XCTAssertFalse(try players.latest("battle").isPlaying)
        }
    }

    func testCompletedResultDoesNotReplayAfterResumeOrThemeChange() async throws {
        try await fixture(seconds: 0.2) { sound, players in
            sound.begin(); sound.finish(won: true)
            let win = try players.latest("win")
            XCTAssertTrue(win.isPlaying)
            // Let the real player finish and deliver its delegate notification.
            try await Task.sleep(nanoseconds: 1_000_000_000)
            XCTAssertFalse(win.isPlaying)
            sound.pauseRenderer(); sound.begin()
            XCTAssertFalse(win.isPlaying)
            sound.themeChanged()
            XCTAssertFalse(try players.latest("win").isPlaying)
            XCTAssertEqual(sound.state.scene, .result)
        }
    }

    func testNewOwnerAndStaleTeardownKeepCurrentMusic() async throws {
        try await fixture { sound, players in
            let first = NSObject(), second = NSObject()
            let oldOwner = ObjectIdentifier(first), currentOwner = ObjectIdentifier(second)
            defer { sound.end(owner: currentOwner) }
            sound.enterLobby(); sound.begin(owner: oldOwner); sound.finish(won: true)
            let win = try players.latest("win")
            XCTAssertTrue(win.isPlaying)
            sound.begin(owner: currentOwner)
            XCTAssertFalse(win.isPlaying)
            sound.end(owner: oldOwner)
            XCTAssertEqual(sound.state.scene, .battle)
            XCTAssertTrue(try players.latest("battle").isPlaying)
        }
    }

    func testRepeatedFinishDoesNotRestartResultAndNextMatchStartsAtZero() async throws {
        try await fixture { sound, players in
            sound.begin(); sound.finish(won: true)
            let win = try players.latest("win")
            win.currentTime = 2
            sound.finish(won: false)
            XCTAssertTrue(win.isPlaying)
            XCTAssertEqual(win.currentTime, 2, accuracy: 0.2)
            XCTAssertFalse(try players.latest("lose").isPlaying)
            sound.end(); sound.begin(); sound.finish(won: true)
            XCTAssertTrue(win.isPlaying)
            XCTAssertLessThan(win.currentTime, 0.2)
        }
    }

    func testResultFinishingWhileMutedStartsAfterUnmute() async throws {
        try await fixture { sound, players in
            UserDefaults.standard.set(true, forKey: ArenaSound.muteKey)
            sound.begin(); sound.finish(won: false)
            XCTAssertTrue(sound.loadedMusicFiles.isEmpty)
            UserDefaults.standard.set(false, forKey: ArenaSound.muteKey)
            sound.muteChanged(battle: true)
            XCTAssertEqual(sound.state.scene, .result)
            XCTAssertTrue(try players.latest("lose").isPlaying)
            XCTAssertFalse(try players.latest("battle").isPlaying)
        }
    }
}
