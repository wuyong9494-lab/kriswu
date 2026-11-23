import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AISpeechTool: Sendable {
    public enum Problem: LocalizedError {
        case missingText, unsupportedAudio, invalidSize, unreadableAudio, invalidReply
        public var errorDescription: String? {
            switch self {
            case .missingText: return "请输入不超过 3,000 字且不超过 12 KB 的朗读文字。"
            case .unsupportedAudio: return "请选择 MP3、M4A、WAV、FLAC、OGG、MP4 或 WebM 文件。"
            case .invalidSize: return "音频必须非空且不超过 20 MB。"
            case .unreadableAudio: return "未能读取音频，请将文件保存到本机后重试。"
            case .invalidReply: return "未收到可用的语音结果。"
            }
        }
    }

    public enum Voice: String, CaseIterable, Sendable {
        case eve, ara, rex, leo
    }

    public enum RecordingFormat: String, Sendable {
        case mp3, m4a, wav, flac, ogg, mp4, webm
        fileprivate var mimeType: String {
            switch self {
            case .mp3: return "audio/mpeg"
            case .m4a: return "audio/mp4"
            case .wav: return "audio/wav"
            case .flac: return "audio/flac"
            case .ogg: return "audio/ogg"
            case .mp4: return "video/mp4"
            case .webm: return "audio/webm"
            }
        }
    }

    public static let maxRecordingBytes = 20_000_000
    private let transport: MultiProviderAIClient.Transport?
    public init(transport: MultiProviderAIClient.Transport? = nil) {
        self.transport = transport
    }

    public static func cleanedScript(_ text: String) throws -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 3000, clean.utf8.count <= 12_000 else {
            throw Problem.missingText
        }
        return clean
    }

    public func synthesize(_ script: String, voice: Voice = .eve, apiKey: String) async throws -> Data {
        let content = try Self.cleanedScript(script)
        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/tts")!, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/wav", forHTTPHeaderField: "Accept")
        try AIProviderToolHTTP.authorize(&request, provider: .grok, apiKey: apiKey)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": content, "voice_id": voice.rawValue, "language": "auto",
            "output_format": ["codec": "wav", "sample_rate": 24000]
        ])
        let data = try await AIProviderToolHTTP.data(
            for: request, provider: .grok, maxBytes: 16 * 1_024 * 1_024, transport: transport
        )
        guard Self.isWAV(data) else { throw Problem.invalidReply }
        return data
    }

    public func transcribe(_ recording: Data, format: RecordingFormat, apiKey: String) async throws -> String {
        guard !recording.isEmpty, recording.count <= Self.maxRecordingBytes else { throw Problem.invalidSize }
        let boundary = "Speech-" + UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try AIProviderToolHTTP.authorize(&request, provider: .openAI, apiKey: apiKey)
        // Deliberately don't include the user's original filename.
        var body = Data(("--\(boundary)\r\n" +
            "Content-Disposition: form-data; name=\"model\"\r\n\r\ngpt-transcribe\r\n" +
            "--\(boundary)\r\n" +
            "Content-Disposition: form-data; name=\"file\"; filename=\"recording.\(format.rawValue)\"\r\n" +
            "Content-Type: \(format.mimeType)\r\n\r\n").utf8)
        body.append(recording)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        let data = try await AIProviderToolHTTP.data(
            for: request, provider: .openAI, maxBytes: 1_024 * 1_024, transport: transport
        )
        struct Reply: Decodable { let text: String }
        guard let text = try? JSONDecoder().decode(Reply.self, from: data).text
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { throw Problem.invalidReply }
        return text
    }

    private static func isWAV(_ data: Data) -> Bool {
        // Inspect the bounded input once; support RIFF chunks such as LIST before audio.
        guard data.count >= 44, data.prefix(4).elementsEqual("RIFF".utf8),
              data.dropFirst(8).prefix(4).elementsEqual("WAVE".utf8) else { return false }
        let start = data.startIndex
        func intLE(_ offset: Int) -> Int {
            (0..<4).reduce(0) { $0 | (Int(data[start + offset + $1]) << (8 * $1)) }
        }
        let total = intLE(4) + 8
        guard total <= data.count else { return false }
        var offset = 12
        var fmt = false
        var audio = false
        while offset + 8 <= total {
            let tag = data[(start + offset)..<(start + offset + 4)]
            let size = intLE(offset + 4)
            guard size <= total - offset - 8 else { return false }
            if tag.elementsEqual("fmt ".utf8), size >= 16 {
                let format = Int(data[start + offset + 8]) | (Int(data[start + offset + 9]) << 8)
                fmt = format == 1
            }
            if tag.elementsEqual("data".utf8), size > 0 { audio = true }
            if fmt && audio { return true }
            offset += 8 + size + (size % 2)
        }
        return false
    }
}
