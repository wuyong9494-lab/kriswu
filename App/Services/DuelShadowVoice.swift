import AVFoundation
import Foundation

/// Plays a pre-produced, bundled Chinese combat voice asset. Never uses
/// AVSpeechSynthesizer or a network TTS service during gameplay.
@MainActor
final class DuelShadowVoice {
    static let liuCallout = "看我黑懒"
    static let assetName = "liu_shadow_callout"
    private var player: AVAudioPlayer?
    private var lastCueID: String?
    private var isPaused = false
    private var pausedDuringPlayback = false

    private static func bundledURL(bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: assetName, withExtension: "caf")
            ?? bundle.url(forResource: assetName, withExtension: "wav")
            ?? bundle.url(forResource: assetName, withExtension: "m4a")
    }

    /// Return false if the recorded line is absent; do not speak a robotic
    /// placeholder or mark an unplayed cue as delivered.
    @discardableResult
    func playLiuTransformation(cueID: String) -> Bool {
        guard !isPaused, !cueID.isEmpty, cueID != lastCueID,
              let url = Self.bundledURL() else { return false }
        do {
            let prepared = try AVAudioPlayer(contentsOf: url)
            guard prepared.prepareToPlay() else { return false }
            player?.stop()
            pausedDuringPlayback = false
            player = prepared
            guard prepared.play() else { player = nil; return false }
            lastCueID = cueID
            return true
        } catch {
            return false
        }
    }

    func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        isPaused = paused
        if paused {
            pausedDuringPlayback = player?.isPlaying == true
            if pausedDuringPlayback { player?.pause() }
        } else {
            // Do not replay an already completed shout when the fight resumes.
            if pausedDuringPlayback { player?.play() }
            pausedDuringPlayback = false
        }
    }

    func reset() {
        player?.stop()
        player = nil
        lastCueID = nil
        isPaused = false
        pausedDuringPlayback = false
    }
}
