import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Multi-provider AI video generation client (Grok Imagine Video, OpenAI Sora 2, Google Veo 3).
/// Enforces HTTPS host pinning (official or validated custom HTTPS relay), never sends chat history,
/// and validates ISO BMFF MP4 headers before handing media data to AVPlayer.
public struct AIVideoTool: Sendable {
    public struct Model: Identifiable, Sendable, Hashable {
        public let id: String
        public let displayName: String
        public let provider: AIProvider
        public let subtitle: String

        fileprivate init(id: String, displayName: String, provider: AIProvider, subtitle: String) {
            self.id = id
            self.displayName = displayName
            self.provider = provider
            self.subtitle = subtitle
        }
    }

    public enum AspectRatio: String, CaseIterable, Identifiable, Sendable, Hashable {
        case landscape16x9 = "16:9"
        case portrait9x16 = "9:16"
        case square1x1 = "1:1"

        public var id: String { rawValue }
        public var displayLabel: String { rawValue }

        internal var openAISize: String {
            switch self {
            case .landscape16x9: return "1280x720"
            case .portrait9x16: return "720x1280"
            case .square1x1: return "720x720"
            }
        }
    }

    public enum Resolution: String, CaseIterable, Identifiable, Sendable, Hashable {
        case hd720 = "720p"
        case fhd1080 = "1080p"

        public var id: String { rawValue }
        public var displayLabel: String { rawValue }
    }

    public struct Options: Equatable, Sendable {
        public var aspectRatio: AspectRatio
        public var durationSeconds: Int
        public var resolution: Resolution
        public var customBaseURL: String?

        public init(
            aspectRatio: AspectRatio = .landscape16x9,
            durationSeconds: Int = 5,
            resolution: Resolution = .hd720,
            customBaseURL: String? = nil
        ) {
            self.aspectRatio = aspectRatio
            self.durationSeconds = max(3, min(12, durationSeconds))
            self.resolution = resolution
            self.customBaseURL = customBaseURL
        }
    }

    public struct ProgressUpdate: Equatable, Sendable {
        public let stage: String
        public let percent: Int?
        public let elapsedSeconds: Double

        public init(stage: String, percent: Int?, elapsedSeconds: Double) {
            self.stage = stage
            self.percent = percent
            self.elapsedSeconds = elapsedSeconds
        }
    }

    public static let models: [Model] = [
        .init(id: "grok-imagine-video", displayName: "Grok Imagine Video", provider: .grok, subtitle: "xAI 高速写实与电影感短视频"),
        .init(id: "sora-2", displayName: "OpenAI Sora 2", provider: .openAI, subtitle: "物理真实与连续运镜"),
        .init(id: "sora-2-pro", displayName: "OpenAI Sora 2 Pro", provider: .openAI, subtitle: "旗舰高精电影级画面"),
        .init(id: "veo-3.0-fast-generate-001", displayName: "Google Veo 3 Fast", provider: .gemini, subtitle: "极速高帧率视频直出"),
        .init(id: "veo-3.0-generate-001", displayName: "Google Veo 3", provider: .gemini, subtitle: "电影光影与原生音效"),
    ]

    public static let maxPromptBytes = 4_000
    private static let metadataByteLimit = 2 * 1024 * 1024
    private static let videoByteLimit = 64 * 1024 * 1024

    private let transport: MultiProviderAIClient.Transport?
    private let pollIntervalNanoseconds: UInt64
    private let maxPollAttempts: Int

    public init() {
        self.transport = nil
        self.pollIntervalNanoseconds = 3_000_000_000
        self.maxPollAttempts = 90
    }

    public init(
        pollIntervalNanoseconds: UInt64 = 10_000_000,
        maxPollAttempts: Int = 30,
        transport: @escaping MultiProviderAIClient.Transport
    ) {
        self.transport = transport
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.maxPollAttempts = maxPollAttempts
    }

    public static func preferredModel(configuredProviders: Set<AIProvider>, lastSelectedID: String? = nil) -> Model {
        if let lastSelectedID,
           let saved = models.first(where: { $0.id == lastSelectedID }),
           configuredProviders.isEmpty || configuredProviders.contains(saved.provider) {
            return saved
        }
        if let configured = models.first(where: { configuredProviders.contains($0.provider) }) {
            return configured
        }
        return models[0]
    }

    /// Submits an async video generation job, polls cleanly until completion, and returns validated MP4 bytes.
    public func generate(
        model: Model,
        apiKey: String,
        prompt: String,
        options: Options = Options(),
        onProgress: (@Sendable (ProgressUpdate) async -> Void)? = nil
    ) async throws -> Data {
        guard Self.models.contains(model) else { throw MultiProviderAIError.unsupportedModel }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= Self.maxPromptBytes else {
            throw AIVideoToolError.invalidPrompt
        }

        let started = Date()
        await onProgress?(ProgressUpdate(stage: "正在提交视频生成任务…", percent: 5, elapsedSeconds: 0))

        switch model.provider {
        case .openAI:
            return try await generateOpenAISora(model: model, apiKey: apiKey, prompt: text, options: options, started: started, onProgress: onProgress)
        case .grok:
            return try await generateGrokVideo(model: model, apiKey: apiKey, prompt: text, options: options, started: started, onProgress: onProgress)
        case .gemini:
            return try await generateGeminiVeo(model: model, apiKey: apiKey, prompt: text, options: options, started: started, onProgress: onProgress)
        case .claude:
            throw MultiProviderAIError.unsupportedModel
        }
    }

    // MARK: - OpenAI Sora 2 (/v1/videos)

    private func generateOpenAISora(
        model: Model,
        apiKey: String,
        prompt: String,
        options: Options,
        started: Date,
        onProgress: (@Sendable (ProgressUpdate) async -> Void)?
    ) async throws -> Data {
        let submitURL = try model.provider.toolURL(path: "/v1/videos", baseURL: options.customBaseURL)
        let body: [String: Any] = [
            "model": model.id,
            "prompt": prompt,
            "seconds": "\(options.durationSeconds)",
            "size": options.aspectRatio.openAISize,
        ]
        let createdData = try await sendJSON(url: submitURL, method: "POST", body: body, provider: .openAI, apiKey: apiKey, baseURL: options.customBaseURL)
        let job = try decode(OpenAIVideoJob.self, from: createdData)
        guard !job.id.isEmpty else { throw AIVideoToolError.invalidJobResponse }

        var current = job
        for _ in 0..<maxPollAttempts {
            let status = current.status.lowercased()
            if status == "completed" || status == "succeeded" {
                await onProgress?(ProgressUpdate(stage: "正在下载成片 MP4…", percent: 95, elapsedSeconds: Date().timeIntervalSince(started)))
                let contentURL = try model.provider.toolURL(path: "/v1/videos/\(job.id)/content", baseURL: options.customBaseURL)
                let mp4 = try await fetchBinary(url: contentURL, provider: .openAI, apiKey: apiKey, baseURL: options.customBaseURL)
                guard Self.isValidMP4(mp4) else { throw AIVideoToolError.invalidVideoData }
                return mp4
            }
            if status == "failed" || status == "cancelled" || status == "expired" {
                throw AIVideoToolError.generationFailed(current.error?.message ?? "服务商返回视频生成失败。")
            }
            await onProgress?(ProgressUpdate(
                stage: "Sora 渲染中（\(current.status)）…",
                percent: current.progress,
                elapsedSeconds: Date().timeIntervalSince(started)
            ))
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            let pollURL = try model.provider.toolURL(path: "/v1/videos/\(job.id)", baseURL: options.customBaseURL)
            let pollData = try await sendJSON(url: pollURL, method: "GET", body: nil, provider: .openAI, apiKey: apiKey, baseURL: options.customBaseURL)
            current = try decode(OpenAIVideoJob.self, from: pollData)
        }
        throw MultiProviderAIError.timedOut
    }

    // MARK: - xAI Grok Imagine Video (/v1/videos/generations)

    private func generateGrokVideo(
        model: Model,
        apiKey: String,
        prompt: String,
        options: Options,
        started: Date,
        onProgress: (@Sendable (ProgressUpdate) async -> Void)?
    ) async throws -> Data {
        let submitURL = try model.provider.toolURL(path: "/v1/videos/generations", baseURL: options.customBaseURL)
        let body: [String: Any] = [
            "model": model.id,
            "prompt": prompt,
            "duration": options.durationSeconds,
            "aspect_ratio": options.aspectRatio.rawValue,
            "resolution": options.resolution.rawValue,
        ]
        let createdData = try await sendJSON(url: submitURL, method: "POST", body: body, provider: .grok, apiKey: apiKey, baseURL: options.customBaseURL)
        let job = try decode(GrokVideoJob.self, from: createdData)
        if let b64 = job.video?.b64JSON, let inline = Data(base64Encoded: b64), Self.isValidMP4(inline) {
            return inline
        }
        guard let reqID = job.requestID ?? job.id, !reqID.isEmpty else {
            throw AIVideoToolError.invalidJobResponse
        }

        for attempt in 0..<maxPollAttempts {
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            let pollURL = try model.provider.toolURL(path: "/v1/videos/\(reqID)", baseURL: options.customBaseURL)
            let pollData = try await sendJSON(url: pollURL, method: "GET", body: nil, provider: .grok, apiKey: apiKey, baseURL: options.customBaseURL)
            let polled = try decode(GrokVideoJob.self, from: pollData)
            if let b64 = polled.video?.b64JSON, let inline = Data(base64Encoded: b64), Self.isValidMP4(inline) {
                return inline
            }
            if let downloadURLStr = polled.video?.url, let dlURL = URL(string: downloadURLStr) {
                await onProgress?(ProgressUpdate(stage: "正在下载视频文件…", percent: 94, elapsedSeconds: Date().timeIntervalSince(started)))
                let mp4 = try await fetchSameOrTrustedVideoURL(dlURL, provider: .grok, apiKey: apiKey, baseURL: options.customBaseURL)
                guard Self.isValidMP4(mp4) else { throw AIVideoToolError.invalidVideoData }
                return mp4
            }
            let st = (polled.status ?? "pending").lowercased()
            if st == "failed" || st == "expired" || st == "cancelled" {
                throw AIVideoToolError.generationFailed(polled.error ?? "视频生成任务失败。")
            }
            let estPct = min(90, 12 + attempt * 6)
            await onProgress?(ProgressUpdate(stage: "Grok 渲染视频中…", percent: estPct, elapsedSeconds: Date().timeIntervalSince(started)))
        }
        throw MultiProviderAIError.timedOut
    }

    // MARK: - Google Gemini Veo 3 (:predictLongRunning)

    private func generateGeminiVeo(
        model: Model,
        apiKey: String,
        prompt: String,
        options: Options,
        started: Date,
        onProgress: (@Sendable (ProgressUpdate) async -> Void)?
    ) async throws -> Data {
        let submitURL = try model.provider.toolURL(path: "/v1beta/models/\(model.id):predictLongRunning", baseURL: options.customBaseURL)
        let body: [String: Any] = [
            "instances": [["prompt": prompt]],
            "parameters": [
                "aspectRatio": options.aspectRatio.rawValue,
                "durationSeconds": options.durationSeconds,
                "resolution": options.resolution.rawValue,
            ],
        ]
        let createdData = try await sendJSON(url: submitURL, method: "POST", body: body, provider: .gemini, apiKey: apiKey, baseURL: options.customBaseURL)
        let op = try decode(GeminiVideoOperation.self, from: createdData)
        guard let opName = op.name, !opName.isEmpty else { throw AIVideoToolError.invalidJobResponse }

        var current = op
        for attempt in 0..<maxPollAttempts {
            if current.done == true {
                if let errMsg = current.error?.message {
                    throw AIVideoToolError.generationFailed(errMsg)
                }
                if let b64 = current.response?.generateVideoResponse?.generatedSamples?.first?.video?.bytesBase64Encoded,
                   let data = Data(base64Encoded: b64), Self.isValidMP4(data) {
                    return data
                }
                if let uri = current.response?.generateVideoResponse?.generatedSamples?.first?.video?.uri,
                   let dlURL = URL(string: uri) {
                    await onProgress?(ProgressUpdate(stage: "正在下载 Veo 视频…", percent: 94, elapsedSeconds: Date().timeIntervalSince(started)))
                    let mp4 = try await fetchSameOrTrustedVideoURL(dlURL, provider: .gemini, apiKey: apiKey, baseURL: options.customBaseURL)
                    guard Self.isValidMP4(mp4) else { throw AIVideoToolError.invalidVideoData }
                    return mp4
                }
                throw AIVideoToolError.invalidVideoData
            }
            let estPct = min(90, 12 + attempt * 6)
            await onProgress?(ProgressUpdate(stage: "Veo 正在渲染视频…", percent: estPct, elapsedSeconds: Date().timeIntervalSince(started)))
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            let pollPath = opName.hasPrefix("/") ? "/v1beta\(opName)" : "/v1beta/\(opName)"
            let pollURL = try model.provider.toolURL(path: pollPath, baseURL: options.customBaseURL)
            let pollData = try await sendJSON(url: pollURL, method: "GET", body: nil, provider: .gemini, apiKey: apiKey, baseURL: options.customBaseURL)
            current = try decode(GeminiVideoOperation.self, from: pollData)
        }
        throw MultiProviderAIError.timedOut
    }

    // MARK: - HTTP & MP4 Validation Helpers

    private func sendJSON(
        url: URL,
        method: String,
        body: [String: Any]?,
        provider: AIProvider,
        apiKey: String,
        baseURL: String?
    ) async throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        try AIProviderToolHTTP.authorize(&req, provider: provider, apiKey: apiKey, baseURL: baseURL)
        return try await AIProviderToolHTTP.data(for: req, provider: provider, maxBytes: Self.metadataByteLimit, baseURL: baseURL, transport: transport)
    }

    private func fetchBinary(
        url: URL,
        provider: AIProvider,
        apiKey: String,
        baseURL: String?
    ) async throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 180)
        req.httpMethod = "GET"
        try AIProviderToolHTTP.authorize(&req, provider: provider, apiKey: apiKey, baseURL: baseURL)
        return try await AIProviderToolHTTP.data(for: req, provider: provider, maxBytes: Self.videoByteLimit, baseURL: baseURL, transport: transport)
    }

    /// Downloads video media strictly over HTTPS without leaking API keys to third-party CDN hosts.
    private func fetchSameOrTrustedVideoURL(
        _ url: URL,
        provider: AIProvider,
        apiKey: String,
        baseURL: String?
    ) async throws -> Data {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil else {
            throw MultiProviderAIError.invalidRequest
        }
        let targetHost = provider.resolvedHost(baseURL: baseURL).lowercased()
        if host == targetHost {
            return try await fetchBinary(url: url, provider: provider, apiKey: apiKey, baseURL: baseURL)
        }
        // Separate CDN signed URL: NEVER send provider Authorization/API key headers!
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 180)
        req.httpMethod = "GET"
        req.httpShouldHandleCookies = false
        let result: (Data, URLResponse)
        if let transport {
            result = try await transport(req)
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.httpShouldSetCookies = false
            result = try await URLSession(configuration: cfg).data(for: req)
        }
        guard let http = result.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              result.0.count <= Self.videoByteLimit else {
            throw AIVideoToolError.invalidVideoData
        }
        return result.0
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw MultiProviderAIError.invalidResponse
        }
        return value
    }

    /// Validates ISO BMFF MP4 container magic (`ftyp` box at bytes 4..7).
    public static func isValidMP4(_ data: Data) -> Bool {
        guard data.count >= 12, data.count <= videoByteLimit else { return false }
        return data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70 // "ftyp"
    }

    private struct OpenAIVideoJob: Decodable {
        struct Err: Decodable { let message: String? }
        let id: String
        let status: String
        let progress: Int?
        let error: Err?
    }

    private struct GrokVideoJob: Decodable {
        struct VideoPayload: Decodable {
            let url: String?
            let b64JSON: String?
            enum CodingKeys: String, CodingKey { case url; case b64JSON = "b64_json" }
        }
        let id: String?
        let requestID: String?
        let status: String?
        let video: VideoPayload?
        let error: String?
        enum CodingKeys: String, CodingKey {
            case id
            case requestID = "request_id"
            case status
            case video
            case error
        }
    }

    private struct GeminiVideoOperation: Decodable {
        struct OpError: Decodable { let message: String? }
        struct ResponsePayload: Decodable {
            struct GenVideo: Decodable {
                struct Sample: Decodable {
                    struct Video: Decodable {
                        let uri: String?
                        let bytesBase64Encoded: String?
                    }
                    let video: Video?
                }
                let generatedSamples: [Sample]?
            }
            let generateVideoResponse: GenVideo?
        }
        let name: String?
        let done: Bool?
        let response: ResponsePayload?
        let error: OpError?
    }
}

public enum AIVideoToolError: LocalizedError, Equatable, Sendable {
    case invalidPrompt
    case invalidJobResponse
    case invalidVideoData
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPrompt:
            return "请输入视频描述提示词（不超过 4,000 字节）。"
        case .invalidJobResponse:
            return "服务商未返回有效的视频任务编号，请检查当前模型权限或中转站是否支持视频接口。"
        case .invalidVideoData:
            return "返回的视频文件格式无效或超出预览上限。"
        case .generationFailed(let msg):
            let clean = MultiProviderAIClient.redactSecrets(in: msg)
            return "视频生成失败：\(clean)"
        }
    }
}
