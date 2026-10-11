import AVFoundation

/// 用 iPhone 自带的中文语音把「今天，组D」录成提示音文件，作为通知铃声。
/// 系统会在 App 数据目录的 Library/Sounds 里找通知铃声，所以到点时 App 不用运行也能播报。
@MainActor
enum VoiceSound {
    private static let synthesizer = AVSpeechSynthesizer()
    /// 试听用另一个，不会打断正在录的提示音
    private static let previewSynthesizer = AVSpeechSynthesizer()
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
        previewSynthesizer.stopSpeaking(at: .immediate)
        previewSynthesizer.speak(utterance(text))
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

    /// 先录到临时文件，录完整了再换成正式文件；录一半失败或超时的不会留下来当铃声。
    private static func render(_ text: String, to finalURL: URL) async -> Bool {
        let url = finalURL.deletingLastPathComponent().appendingPathComponent("tmp-" + finalURL.lastPathComponent)
        try? FileManager.default.removeItem(at: url)
        let ok = await record(text, to: url)
        guard ok else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        try? FileManager.default.removeItem(at: finalURL)
        do {
            try FileManager.default.moveItem(at: url, to: finalURL)
            return true
        } catch {
            try? FileManager.default.removeItem(at: url)
            return false
        }
    }

    private static func record(_ text: String, to url: URL) async -> Bool {
        let recorder = Recorder()
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
            // 万一系统没有送来结束标记，10 秒后算失败（用默认铃声），不留半截文件
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                recorder.finish(false)
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
