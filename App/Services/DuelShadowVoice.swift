import AVFoundation
import Foundation

/// Liu's original Mandarin transformation callout. The spoken line is
/// synthesized on-device, so no third-party voice recording or voice clone is
/// bundled. Trigger this only on an authoritative shadow action transition.
@MainActor
final class DuelShadowVoice {
    private let synthesizer = AVSpeechSynthesizer()
    private var lastCueID: String?

    static let liuCallout = "看我黑懒"

    func playLiuTransformation(cueID: String) {
        guard !cueID.isEmpty, cueID != lastCueID else { return }
        lastCueID = cueID
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: Self.liuCallout)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = 0.49
        utterance.pitchMultiplier = 0.84
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    func reset() {
        synthesizer.stopSpeaking(at: .immediate)
        lastCueID = nil
    }
}
