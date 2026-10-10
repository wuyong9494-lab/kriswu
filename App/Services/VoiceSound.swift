import AVFoundation

/// 用 iPhone 自带的中文语音把「今天，组D」录成提示音文件，作为通知铃声。
/// 系统会在 App 数据目录的 Library/Sounds 里找通知铃声，所以到点时 App 不用运行也能播报。
@MainActor
enum VoiceSound {
    private static let synthesizer = AVSpeechSynthesizer()
    private static let prefix = "voice-"

    private static var directory: URL {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func utterance(_ text: String) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        return u
    }

    /// 返回铃声文件名（同样的文字只录一次）；录制失败返回 nil，用默认铃声。
    static func file(for text: String) async -> String? {
        let name = prefix + stableHash(text) + ".caf"
        let url = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return name }
        return await render(text, to: url) ? name : nil
    }

    /// 删掉不再使用的旧语音文件。
    static func removeFiles(except keep: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for f in files where f.hasPrefix(prefix) && !keep.contains(f) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(f))
        }
    }

    /// 设置里「试听」。
    static func speakNow(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance(text))
    }

    private final class Recorder: @unchecked Sendable {
        let lock = NSLock()
        var file: AVAudioFile?
        var done = false
        var continuation: CheckedContinuation<Bool, Never>?

        func finish(_ ok: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            file = nil   // 关闭文件
            continuation?.resume(returning: ok)
        }
    }

    private static func render(_ text: String, to url: URL) async -> Bool {
        let recorder = Recorder()
        try? FileManager.default.removeItem(at: url)
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            recorder.continuation = c
            synthesizer.write(utterance(text)) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                recorder.lock.lock()
                let alreadyDone = recorder.done
                recorder.lock.unlock()
                if alreadyDone { return }
                // 最后一块长度为 0，表示读完了
                if pcm.frameLength == 0 {
                    recorder.finish(recorder.file != nil)
                    return
                }
                do {
                    if recorder.file == nil {
                        recorder.file = try AVAudioFile(forWriting: url, settings: pcm.format.settings,
                                                        commonFormat: pcm.format.commonFormat,
                                                        interleaved: pcm.format.isInterleaved)
                    }
                    try recorder.file?.write(from: pcm)
                } catch {
                    recorder.finish(false)
                }
            }
            // 万一系统没有送来结束标记，10 秒后按已录到的内容结束
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                recorder.finish(FileManager.default.fileExists(atPath: url.path))
            }
        }
    }

    /// 稳定的文字哈希（FNV-1a），用作文件名。
    private static func stableHash(_ s: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100_0000_01b3
        }
        return String(h, radix: 16)
    }
}
