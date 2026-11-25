import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Multi-provider AI video generation client (OpenAI Sora 2, AIHubMix unified /v1/videos, Grok Imagine Video, Google Veo 3).
/// Enforces HTTPS host pinning (official or validated custom HTTPS relay), per-model duration/aspect validation
/// (zero silent model swaps), structured upstream error diagnostics (never text-chat errors),
/// and validates ISO BMFF MP4 headers (`ftyp`) before handing media data to AVPlayer.
public struct AIVideoTool: Sendable {
    public struct Model: Identifiable, Sendable, Hashable {
        public let id: String
        public let displayName: String
        public let provider: AIProvider
        public let subtitle: String
        public let supportedDurations: [Int]
        public let supportedAspectRatios: [AspectRatio]
        public let defaultDuration: Int

        public init(
            id: String,
            displayName: String,
            provider: AIProvider,
            subtitle: String,
            supportedDurations: [Int] = [4, 8, 12],
            supportedAspectRatios: [AspectRatio] = [.landscape16x9, .portrait9x16],
            defaultDuration: Int? = nil
        ) {
            self.id = id
            self.displayName = displayName
            self.provider = provider
            self.subtitle = subtitle
            let cleanDurations = supportedDurations.isEmpty ? [4, 8] : supportedDurations
            self.supportedDurations = cleanDurations
            self.supportedAspectRatios = supportedAspectRatios.isEmpty ? [.landscape16x9, .portrait9x16] : supportedAspectRatios
            self.defaultDuration = defaultDuration ?? cleanDurations[0]
        }

        public func openAISize(for aspectRatio: AspectRatio, resolution: Resolution) -> String {
            let lower = id.lowercased()
            if lower.contains("sora-2-pro") && resolution == .fhd1080 {
                switch aspectRatio {
                case .landscape16x9: return "1792x1024"
                case .portrait9x16: return "1024x1792"
                case .square1x1: return "1280x720"
                }
            }
            return aspectRatio.openAISize
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
            durationSeconds: Int = 4,
            resolution: Resolution = .hd720,
            customBaseURL: String? = nil
        ) {
            self.aspectRatio = aspectRatio
            self.durationSeconds = max(3, min(15, durationSeconds))
            self.resolution = resolution
            self.customBaseURL = customBaseURL
        }
    }

    public struct ProgressUpdate: Equatable, Sendable {
        public let stage: String
        public let percent: Int?
        public let elapsedSeconds: Double
        public let jobID: String?

        public init(stage: String, percent: Int?, elapsedSeconds: Double, jobID: String? = nil) {
            self.stage = stage
            self.percent = percent
            self.elapsedSeconds = elapsedSeconds
            self.jobID = jobID
        }
    }

    public static let models: [Model] = [
        .init(
            id: "sora-2",
            displayName: "OpenAI Sora 2",
            provider: .openAI,
            subtitle: "物理真实与连续运镜（支持 4/8/12 秒 · 16:9 / 9:16）",
            supportedDurations: [4, 8, 12],
            supportedAspectRatios: [.landscape16x9, .portrait9x16],
            defaultDuration: 4
        ),
        .init(
            id: "sora-2-pro",
            displayName: "OpenAI Sora 2 Pro",
            provider: .openAI,
            subtitle: "旗舰高精电影级画面（支持 4/8/12 秒 · 高清横竖屏）",
            supportedDurations: [4, 8, 12],
            supportedAspectRatios: [.landscape16x9, .portrait9x16],
            defaultDuration: 4
        ),
        .init(
            id: "veo-3.0-fast-generate-001",
            displayName: "Google Veo 3 Fast",
            provider: .gemini,
            subtitle: "极速高帧率视频直出（支持 4/6/8 秒）",
            supportedDurations: [4, 6, 8],
            supportedAspectRatios: [.landscape16x9, .portrait9x16],
            defaultDuration: 8
        ),
        .init(
            id: "veo-3.0-generate-001",
            displayName: "Google Veo 3",
            provider: .gemini,
            subtitle: "电影光影与原生音效（支持 4/6/8 秒）",
            supportedDurations: [4, 6, 8],
            supportedAspectRatios: [.landscape16x9, .portrait9x16],
            defaultDuration: 8
        ),
        .init(
            id: "grok-imagine-video",
            displayName: "Grok Imagine Video",
            provider: .grok,
            subtitle: "xAI 高速写实与电影感短视频（支持 5/8/10 秒）",
            supportedDurations: [5, 8, 10],
            supportedAspectRatios: [.landscape16x9, .portrait9x16, .square1x1],
            defaultDuration: 5
        ),
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

    /// Validates options against the exact selected model schema before touching network (zero silent rewriting).
    public static func validate(options: Options, for model: Model) throws {
        if !model.supportedDurations.contains(options.durationSeconds) {
            let allowed = model.supportedDurations.map(String.init).joined(separator: " / ")
            throw AIVideoToolError.unsupportedParameters(
                "模型 \(model.displayName)（\(model.id)）不支持 \(options.durationSeconds) 秒时长，仅支持 \(allowed) 秒。"
            )
        }
        if !model.supportedAspectRatios.contains(options.aspectRatio) {
            let allowed = model.supportedAspectRatios.map(\.displayLabel).joined(separator: " / ")
            throw AIVideoToolError.unsupportedParameters(
                "模型 \(model.displayName)（\(model.id)）不支持 \(options.aspectRatio.displayLabel) 比例，仅支持 \(allowed)。"
            )
        }
    }

    /// Submits an async video generation job, polls cleanly until completion, and returns validated MP4 bytes.
    public func generate(
        model: Model,
        apiKey: String,
        prompt: String,
        options: Options = Options(),
        onProgress: (@Sendable (ProgressUpdate) async -> Void)? = nil
    ) async throws -> Data {
        let cleanID = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty, model.provider != .claude else { throw MultiProviderAIError.unsupportedModel }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= Self.maxPromptBytes else {
            throw AIVideoToolError.invalidPrompt
        }
        try Self.validate(options: options, for: model)

        let started = Date()
        await onProgress?(ProgressUpdate(stage: "正在提交视频生成任务（\(model.id)）…", percent: 5, elapsedSeconds: 0))

        // AIHubMix routes OpenAI Sora, Google Veo, Wan, and Seedance uniformly through POST /v1/videos
        if AIProviderToolHTTP.isOpenAICompatibleRelay(options.customBaseURL) {
            return try await generateOpenAICompatibleVideosAPI(
                model: model,
                apiKey: apiKey,
                prompt: text,
                options: options,
                started: started,
                forceBearer: true,
                onProgress: onProgress
            )
        }

        switch model.provider {
        case .openAI:
            return try await generateOpenAICompatibleVideosAPI(
                model: model,
                apiKey: apiKey,
                prompt: text,
                options: options,
                started: started,
                forceBearer: false,
                onProgress: onProgress
            )
        case .grok:
            return try await generateGrokVideo(model: model, apiKey: apiKey, prompt: text, options: options, started: started, onProgress: onProgress)
        case .gemini:
            return try await generateGeminiVeo(model: model, apiKey: apiKey, prompt: text, options: options, started: started, onProgress: onProgress)
        case .claude:
            throw MultiProviderAIError.unsupportedModel
        }
    }

    // MARK: - OpenAI Sora 2 & AIHubMix Unified Video API (/v1/videos)

    private func generateOpenAICompatibleVideosAPI(
        model: Model,
        apiKey: String,
        prompt: String,
        options: Options,
        started: Date,
        forceBearer: Bool,
        onProgress: (@Sendable (ProgressUpdate) async -> Void)?
    ) async throws -> Data {
        let submitURL = try model.provider.toolURL(path: "/v1/videos", baseURL: options.customBaseURL)
        let size = model.openAISize(for: options.aspectRatio, resolution: options.resolution)
        let body: [String: Any] = [
            "model": model.id,
            "prompt": prompt,
            "seconds": "\(options.durationSeconds)",
            "size": size,
        ]
        let createdData = try await sendJSON(
            url: submitURL,
            method: "POST",
            body: body,
            provider: model.provider,
            apiKey: apiKey,
            baseURL: options.customBaseURL,
            forceBearer: forceBearer
        )
        let job = try decode(OpenAIVideoJob.self, from: createdData)
        guard !job.id.isEmpty else { throw AIVideoToolError.invalidJobResponse }

        await onProgress?(ProgressUpdate(
            stage: "任务已创建（#\(job.id.prefix(12))），排队渲染中…",
            percent: max(8, job.progress ?? 8),
            elapsedSeconds: Date().timeIntervalSince(started),
            jobID: job.id
        ))

        var current = job
        for attempt in 0..<maxPollAttempts {
            let status = current.status.lowercased()
            if status == "completed" || status == "succeeded" {
                await onProgress?(ProgressUpdate(
                    stage: "渲染完成，正在下载成片 MP4…",
                    percent: 95,
                    elapsedSeconds: Date().timeIntervalSince(started),
                    jobID: job.id
                ))
                if let directURLStr = current.downloadURL, let dlURL = URL(string: directURLStr) {
                    let mp4 = try await fetchSameOrTrustedVideoURL(dlURL, provider: model.provider, apiKey: apiKey, baseURL: options.customBaseURL, forceBearer: forceBearer)
                    guard Self.isValidMP4(mp4) else { throw AIVideoToolError.invalidVideoData }
                    return mp4
                }
                let contentURL = try model.provider.toolURL(path: "/v1/videos/\(job.id)/content", baseURL: options.customBaseURL)
                let mp4 = try await fetchBinaryWith202Retry(
                    url: contentURL,
                    provider: model.provider,
                    apiKey: apiKey,
                    baseURL: options.customBaseURL,
                    forceBearer: forceBearer
                )
                guard Self.isValidMP4(mp4) else { throw AIVideoToolError.invalidVideoData }
                return mp4
            }
            if status == "failed" || status == "cancelled" || status == "expired" {
                throw AIVideoToolError.generationFailed(current.errorMessage ?? "服务商返回视频生成失败（status=\(current.status)）。")
            }
            let pct = current.progress ?? min(90, 12 + attempt * 5)
            await onProgress?(ProgressUpdate(
                stage: "\(model.displayName) 渲染中（\(current.status)）…",
                percent: pct,
                elapsedSeconds: Date().timeIntervalSince(started),
                jobID: job.id
            ))
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            let pollURL = try model.provider.toolURL(path: "/v1/videos/\(job.id)", baseURL: options.customBaseURL)
            let pollData = try await sendJSON(
                url: pollURL,
                method: "GET",
                body: nil,
                provider: model.provider,
                apiKey: apiKey,
                baseURL: options.customBaseURL,
                forceBearer: forceBearer
            )
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
        let createdData = try await sendJSON(url: submitURL, method: "POST", body: body, provider: .grok, apiKey: apiKey, baseURL: options.customBaseURL, forceBearer: false)
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
            let pollData = try await sendJSON(url: pollURL, method: "GET", body: nil, provider: .grok, apiKey: apiKey, baseURL: options.customBaseURL, forceBearer: false)
            let polled = try decode(GrokVideoJob.self, from: pollData)
            if let b64 = polled.video?.b64JSON, let inline = Data(base64Encoded: b64), Self.isValidMP4(inline) {
                return inline
            }
            if let downloadURLStr = polled.video?.url, let dlURL = URL(string: downloadURLStr) {
                await onProgress?(ProgressUpdate(stage: "正在下载视频文件…", percent: 94, elapsedSeconds: Date().timeIntervalSince(started), jobID: reqID))
                let mp4 = try await fetchSameOrTrustedVideoURL(dlURL, provider: .grok, apiKey: apiKey, baseURL: options.customBaseURL, forceBearer: false)
                guard Self.isValidMP4(mp4) else { throw AIVideoToolError.invalidVideoData }
                return mp4
            }
            let st = (polled.status ?? "pending").lowercased()
            if st == "failed" || st == "expired" || st == "cancelled" {
                throw AIVideoToolError.generationFailed(polled.error ?? "视频生成任务失败。")
            }
            let estPct = min(90, 12 + attempt * 6)
            await onProgress?(ProgressUpdate(stage: "Grok 渲染视频中…", percent: estPct, elapsedSeconds: Date().timeIntervalSince(started), jobID: reqID))
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
        let createdData = try await sendJSON(url: submitURL, method: "POST", body: body, provider: .gemini, apiKey: apiKey, baseURL: options.customBaseURL, forceBearer: false)
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
                    await onProgress?(ProgressUpdate(stage: "正在下载 Veo 视频…", percent: 94, elapsedSeconds: Date().timeIntervalSince(started), jobID: opName))
                    let mp4 = try await fetchSameOrTrustedVideoURL(dlURL, provider: .gemini, apiKey: apiKey, baseURL: options.customBaseURL, forceBearer: false)
                    guard Self.isValidMP4(mp4) else { throw AIVideoToolError.invalidVideoData }
                    return mp4
                }
                throw AIVideoToolError.invalidVideoData
            }
            let estPct = min(90, 12 + attempt * 6)
            await onProgress?(ProgressUpdate(stage: "Veo 正在渲染视频…", percent: estPct, elapsedSeconds: Date().timeIntervalSince(started), jobID: opName))
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            let pollPath = opName.hasPrefix("/") ? "/v1beta\(opName)" : "/v1beta/\(opName)"
            let pollURL = try model.provider.toolURL(path: pollPath, baseURL: options.customBaseURL)
            let pollData = try await sendJSON(url: pollURL, method: "GET", body: nil, provider: .gemini, apiKey: apiKey, baseURL: options.customBaseURL, forceBearer: false)
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
        baseURL: String?,
        forceBearer: Bool
    ) async throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        try AIProviderToolHTTP.authorizeRelay(&req, provider: provider, apiKey: apiKey, baseURL: baseURL, forceBearer: forceBearer)
        let (data, _) = try await AIProviderToolHTTP.dataWithDiagnostics(
            for: req,
            provider: provider,
            maxBytes: Self.metadataByteLimit,
            baseURL: baseURL,
            transport: transport
        )
        return data
    }

    private func fetchBinaryWith202Retry(
        url: URL,
        provider: AIProvider,
        apiKey: String,
        baseURL: String?,
        forceBearer: Bool
    ) async throws -> Data {
        for attempt in 0..<8 {
            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 180)
            req.httpMethod = "GET"
            try AIProviderToolHTTP.authorizeRelay(&req, provider: provider, apiKey: apiKey, baseURL: baseURL, forceBearer: forceBearer)
            let (data, status) = try await AIProviderToolHTTP.dataWithDiagnostics(
                for: req,
                provider: provider,
                maxBytes: Self.videoByteLimit,
                baseURL: baseURL,
                transport: transport
            )
            if status == 202 && attempt < 7 {
                try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                continue
            }
            return data
        }
        throw MultiProviderAIError.timedOut
    }

    /// Downloads video media strictly over HTTPS without leaking API keys to third-party CDN hosts.
    private func fetchSameOrTrustedVideoURL(
        _ url: URL,
        provider: AIProvider,
        apiKey: String,
        baseURL: String?,
        forceBearer: Bool
    ) async throws -> Data {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil else {
            throw MultiProviderAIError.invalidRequest
        }
        let targetHost = provider.resolvedHost(baseURL: baseURL).lowercased()
        if host == targetHost {
            return try await fetchBinaryWith202Retry(url: url, provider: provider, apiKey: apiKey, baseURL: baseURL, forceBearer: forceBearer)
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
        struct ErrObj: Decodable { let message: String? }
        struct VideoRef: Decodable { let url: String? }

        let id: String
        let status: String
        let progress: Int?
        let errorMessage: String?
        let downloadURL: String?

        enum CodingKeys: String, CodingKey {
            case id, status, progress, error, url, video
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = (try? c.decode(String.self, forKey: .id)) ?? ""
            self.status = (try? c.decode(String.self, forKey: .status)) ?? "queued"
            if let intVal = try? c.decode(Int.self, forKey: .progress) {
                self.progress = intVal
            } else if let dblVal = try? c.decode(Double.self, forKey: .progress) {
                self.progress = Int(dblVal.rounded())
            } else if let strVal = try? c.decode(String.self, forKey: .progress) {
                let digits = strVal.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                self.progress = Double(digits).map { Int($0.rounded()) }
            } else {
                self.progress = nil
            }
            if let errObj = try? c.decode(ErrObj.self, forKey: .error), let m = errObj.message, !m.isEmpty {
                self.errorMessage = m
            } else if let errStr = try? c.decode(String.self, forKey: .error), !errStr.isEmpty {
                self.errorMessage = errStr
            } else {
                self.errorMessage = nil
            }
            if let direct = try? c.decode(String.self, forKey: .url), !direct.isEmpty {
                self.downloadURL = direct
            } else if let nested = try? c.decode(VideoRef.self, forKey: .video), let u = nested.url, !u.isEmpty {
                self.downloadURL = u
            } else {
                self.downloadURL = nil
            }
        }
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
    case unsupportedParameters(String)
    case invalidJobResponse
    case invalidVideoData
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPrompt:
            return "请输入视频描述提示词（不超过 4,000 字节）。"
        case .unsupportedParameters(let msg):
            return msg
        case .invalidJobResponse:
            return "服务商未返回有效的视频任务编号，请检查当前模型权限或中转站是否支持视频接口。"
        case .invalidVideoData:
            return "返回的视频文件格式无效（缺少 MP4 ftyp 文件头）或超出预览上限。"
        case .generationFailed(let msg):
            let clean = MultiProviderAIClient.redactSecrets(in: msg)
            return "视频生成失败：\(clean)"
        }
    }
}
