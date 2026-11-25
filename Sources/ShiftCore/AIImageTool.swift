import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Raster image generation from a user-entered prompt. Never fetches provider-supplied URLs.
public struct AIImageTool: Sendable {
    public struct Model: Identifiable, Sendable, Hashable {
        public let id: String
        public let displayName: String
        public let provider: AIProvider

        fileprivate init(id: String, displayName: String, provider: AIProvider) {
            self.id = id
            self.displayName = displayName
            self.provider = provider
        }

        public var shortStudioName: String {
            switch id {
            case "gpt-image-2": return "GPT Image 2"
            case "gpt-image-2.6-flare": return "GPT 2.6 Flare"
            case "gpt-image-2.6-sunburst": return "GPT 2.6 Sunburst"
            case "gemini-3.1-flash-image": return "Nano Banana 2"
            case "grok-imagine-image-2.0": return "Grok Imagine 2.0"
            default: return displayName
            }
        }
    }

    public enum Quality: String, CaseIterable, Identifiable, Sendable, Hashable {
        case fast
        case balanced
        case hd

        public var id: String { rawValue }

        public var shortLabel: String {
            switch self {
            case .fast: return "极速"
            case .balanced: return "均衡"
            case .hd: return "超清"
            }
        }

        public var detailLabel: String {
            switch self {
            case .fast: return "极速 · 低延迟"
            case .balanced: return "均衡 · 标准"
            case .hd: return "超清 · 2K 细节"
            }
        }

        internal var openAIQuality: String {
            switch self {
            case .fast: return "low"
            case .balanced: return "medium"
            case .hd: return "high"
            }
        }

        internal var grokQuality: String {
            switch self {
            case .fast: return "low"
            case .balanced: return "medium"
            case .hd: return "high"
            }
        }

        internal var grokResolution: String {
            self == .hd ? "2k" : "1k"
        }

        internal var geminiImageSize: String {
            self == .hd ? "2K" : "1K"
        }

        internal var jpegCompression: Int {
            switch self {
            case .fast: return 80
            case .balanced: return 86
            case .hd: return 92
            }
        }
    }

    public enum AspectRatio: String, CaseIterable, Identifiable, Sendable, Hashable {
        case square
        case portrait
        case landscape
        case tall

        public var id: String { rawValue }

        public var apiRatio: String {
            switch self {
            case .square: return "1:1"
            case .portrait: return "2:3"
            case .landscape: return "3:2"
            case .tall: return "9:16"
            }
        }

        public var displayLabel: String { apiRatio }

        public var openAISize: String {
            switch self {
            case .square: return "1024x1024"
            case .portrait, .tall: return "1024x1536"
            case .landscape: return "1536x1024"
            }
        }

        public var widthToHeight: Double {
            switch self {
            case .square: return 1.0
            case .portrait: return 2.0 / 3.0
            case .landscape: return 3.0 / 2.0
            case .tall: return 9.0 / 16.0
            }
        }
    }

    public enum OutputFormat: String, Sendable, Hashable {
        case jpeg
        case png
    }

    public struct Options: Equatable, Sendable {
        public var quality: Quality
        public var aspectRatio: AspectRatio
        public var outputFormat: OutputFormat
        public var customBaseURL: String?

        public init(
            quality: Quality = .fast,
            aspectRatio: AspectRatio = .portrait,
            outputFormat: OutputFormat = .jpeg,
            customBaseURL: String? = nil
        ) {
            self.quality = quality
            self.aspectRatio = aspectRatio
            self.outputFormat = outputFormat
            self.customBaseURL = customBaseURL
        }

        /// High-speed mobile studio defaults: low-latency quality + compact JPEG payload (10x-20x smaller than PNG over 4G/5G).
        public static let fastStudio = Options(quality: .fast, aspectRatio: .portrait, outputFormat: .jpeg, customBaseURL: nil)

        /// Legacy single-image defaults retained for backwards compatibility.
        public static let legacyDefault = Options(quality: .balanced, aspectRatio: .square, outputFormat: .png, customBaseURL: nil)
    }

    public struct BatchSlotResult: Sendable {
        public let index: Int
        public let data: Data
        public let elapsedSeconds: Double

        public init(index: Int, data: Data, elapsedSeconds: Double) {
            self.index = index
            self.data = data
            self.elapsedSeconds = elapsedSeconds
        }
    }

    /// Only models with a documented synchronous, inline image-generation contract.
    /// Visibility is not proof of API project permissions, billing or regional eligibility.
    public static let models: [Model] = [
        .init(id: "gpt-image-2", displayName: "GPT Image 2", provider: .openAI),
        .init(id: "gpt-image-2.6-flare", displayName: "GPT Image 2.6 Flare", provider: .openAI),
        .init(id: "gpt-image-2.6-sunburst", displayName: "GPT Image 2.6 Sunburst", provider: .openAI),
        .init(id: "gemini-3.1-flash-image", displayName: "Nano Banana 2", provider: .gemini),
        .init(id: "grok-imagine-image-2.0", displayName: "Grok Imagine 2.0", provider: .grok),
    ]
    public static let maxPromptBytes = 8_000
    public static let maxBatchCount = 4

    private let transport: MultiProviderAIClient.Transport?
    private static let imageByteLimit = 9 * 1024 * 1024
    private static let responseByteLimit = 13 * 1024 * 1024
    private static let maxDimension = 4096

    public init() {
        self.transport = nil
    }

    public init(transport: @escaping MultiProviderAIClient.Transport) {
        self.transport = transport
    }

    /// Picks the best default model given configured provider API keys, preferring an already-configured provider.
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

    public func generate(model: Model, apiKey: String, prompt: String) async throws -> Data {
        try await generate(model: model, apiKey: apiKey, prompt: prompt, options: .legacyDefault)
    }

    public func generate(model: Model, apiKey: String, prompt: String, options: Options) async throws -> Data {
        guard Self.models.contains(model) else { throw MultiProviderAIError.unsupportedModel }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= Self.maxPromptBytes else {
            throw AIImageToolError.invalidPrompt
        }

        do {
            return try await performSingleRequest(model: model, apiKey: apiKey, text: text, options: options, omitCompression: false)
        } catch MultiProviderAIError.requestRejected(400) where model.provider == .openAI && options.outputFormat == .jpeg {
            // Some third-party OpenAI-compatible relays reject output_compression or jpeg; cleanly fall back once.
            var fallback = options
            fallback.outputFormat = .png
            return try await performSingleRequest(model: model, apiKey: apiKey, text: text, options: fallback, omitCompression: true)
        }
    }

    /// Generates 1..4 images concurrently via TaskGroup so each finished image streams into the gallery immediately.
    /// Returns all succeeded slots in index order; throws only if zero images succeeded (or cancelled).
    public func generateBatch(
        model: Model,
        apiKey: String,
        prompt: String,
        count: Int,
        options: Options = .fastStudio,
        onSlotComplete: (@Sendable (BatchSlotResult) async -> Void)? = nil
    ) async throws -> [BatchSlotResult] {
        let clampedCount = max(1, min(Self.maxBatchCount, count))
        guard Self.models.contains(model) else { throw MultiProviderAIError.unsupportedModel }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= Self.maxPromptBytes else {
            throw AIImageToolError.invalidPrompt
        }

        if clampedCount == 1 {
            let started = Date()
            let data = try await generate(model: model, apiKey: apiKey, prompt: text, options: options)
            let slot = BatchSlotResult(index: 0, data: data, elapsedSeconds: max(0.01, Date().timeIntervalSince(started)))
            if let onSlotComplete {
                await onSlotComplete(slot)
            }
            return [slot]
        }

        let started = Date()
        let outcome = await withTaskGroup(of: Result<BatchSlotResult, Error>.self) { group -> ([BatchSlotResult], Error?) in
            for idx in 0..<clampedCount {
                group.addTask {
                    do {
                        let data = try await self.generate(model: model, apiKey: apiKey, prompt: text, options: options)
                        let slot = BatchSlotResult(
                            index: idx,
                            data: data,
                            elapsedSeconds: max(0.01, Date().timeIntervalSince(started))
                        )
                        if let onSlotComplete {
                            await onSlotComplete(slot)
                        }
                        return .success(slot)
                    } catch {
                        return .failure(error)
                    }
                }
            }

            var successes: [BatchSlotResult] = []
            var firstError: Error?
            for await item in group {
                switch item {
                case .success(let slot):
                    successes.append(slot)
                case .failure(let error):
                    if firstError == nil {
                        firstError = error
                    }
                }
            }
            return (successes, firstError)
        }
        try Task.checkCancellation()
        if outcome.0.isEmpty, let firstError = outcome.1 {
            throw firstError
        }
        return outcome.0.sorted { $0.index < $1.index }
    }

    private func performSingleRequest(
        model: Model,
        apiKey: String,
        text: String,
        options: Options,
        omitCompression: Bool
    ) async throws -> Data {
        let path: String
        let body: [String: Any]
        switch model.provider {
        case .openAI:
            path = "/v1/images/generations"
            var openAIBody: [String: Any] = [
                "model": model.id,
                "prompt": text,
                "n": 1,
                "size": options.aspectRatio.openAISize,
                "quality": options.quality.openAIQuality,
                "output_format": options.outputFormat.rawValue,
            ]
            if options.outputFormat == .jpeg && !omitCompression {
                openAIBody["output_compression"] = options.quality.jpegCompression
            }
            body = openAIBody
        case .gemini:
            path = "/v1beta/models/\(model.id):generateContent"
            body = [
                "contents": [["role": "user", "parts": [["text": text]]]],
                "generationConfig": [
                    "responseModalities": ["IMAGE"],
                    "imageConfig": [
                        "imageSize": options.quality.geminiImageSize,
                        "aspectRatio": options.aspectRatio.apiRatio,
                    ],
                ],
            ]
        case .grok:
            path = "/v1/images/generations"
            body = [
                "model": model.id,
                "prompt": text,
                "n": 1,
                "response_format": "b64_json",
                "aspect_ratio": options.aspectRatio.apiRatio,
                "resolution": options.quality.grokResolution,
                "quality": options.quality.grokQuality,
            ]
        case .claude:
            throw MultiProviderAIError.unsupportedModel
        }

        let url = try model.provider.toolURL(path: path, baseURL: options.customBaseURL)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try AIProviderToolHTTP.authorize(&request, provider: model.provider, apiKey: apiKey, baseURL: options.customBaseURL)
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw MultiProviderAIError.invalidRequest
        }

        let response = try await AIProviderToolHTTP.data(
            for: request,
            provider: model.provider,
            maxBytes: Self.responseByteLimit,
            baseURL: options.customBaseURL,
            transport: transport
        )
        let encoded: String
        let mimeType: String?
        if model.provider == .gemini {
            guard let decoded = try? JSONDecoder().decode(GeminiReply.self, from: response) else {
                throw MultiProviderAIError.invalidResponse
            }
            // Thought images and text-only responses aren't final results.
            guard let image = decoded.candidates?.first?.content?.parts.first(where: {
                $0.thought != true && $0.inlineData != nil
            })?.inlineData else { throw AIImageToolError.noImage }
            encoded = image.data
            mimeType = image.mimeType
        } else {
            guard let decoded = try? JSONDecoder().decode(Base64Reply.self, from: response) else {
                throw MultiProviderAIError.invalidResponse
            }
            guard let image = decoded.data?.first, let base64 = image.base64 else {
                throw AIImageToolError.noImage
            }
            encoded = base64
            if let explicitMime = image.mimeType {
                mimeType = explicitMime
            } else if model.provider == .openAI && options.outputFormat == .png {
                mimeType = "image/png"
            } else {
                mimeType = nil
            }
        }

        guard encoded.utf8.count <= ((Self.imageByteLimit + 2) / 3) * 4,
              let imageData = Data(base64Encoded: encoded),
              imageData.count <= Self.imageByteLimit,
              let header = Self.readRasterHeader(imageData),
              (1...Self.maxDimension).contains(header.width),
              (1...Self.maxDimension).contains(header.height),
              mimeType == nil || mimeType == header.mimeType
        else { throw AIImageToolError.invalidImage }
        return imageData
    }

    private static func readRasterHeader(_ data: Data) -> (width: Int, height: Int, mimeType: String)? {
        if data.count >= 33,
           data.prefix(16).elementsEqual([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82]),
           data.suffix(12).elementsEqual([0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]) {
            let bytes = Array(data.prefix(24))
            func be32(_ index: Int) -> Int {
                Int(bytes[index]) << 24 | Int(bytes[index + 1]) << 16 | Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            }
            return (be32(16), be32(20), "image/png")
        }

        guard data.count >= 4,
              data.prefix(2).elementsEqual([255, 216]), data.suffix(2).elementsEqual([255, 217])
        else { return nil }
        // JPEG SOF precedes the compressed scan. Enforce dimensions before letting UI decode pixels.
        let frames: Set<UInt8> = [0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]
        var index = 2
        while index + 3 < data.count {
            guard data[index] == 0xff else { return nil }
            index += 1
            while index < data.count && data[index] == 0xff { index += 1 }
            guard index + 2 < data.count else { return nil }
            let marker = data[index]
            guard marker != 0xda && marker != 0xd9 else { return nil }
            index += 1
            let length = Int(data[index]) << 8 | Int(data[index + 1])
            guard length >= 2, index + length <= data.count else { return nil }
            if frames.contains(marker) {
                guard length >= 8 else { return nil }
                let height = Int(data[index + 3]) << 8 | Int(data[index + 4])
                let width = Int(data[index + 5]) << 8 | Int(data[index + 6])
                return (width, height, "image/jpeg")
            }
            index += length
        }
        return nil
    }

    private struct Base64Reply: Decodable {
        struct Image: Decodable {
            let base64: String?
            let mimeType: String?
            enum CodingKeys: String, CodingKey { case base64 = "b64_json"; case mimeType = "mime_type" }
        }
        let data: [Image]?
    }

    private struct GeminiReply: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    struct InlineData: Decodable { let mimeType: String; let data: String }
                    let inlineData: InlineData?
                    let thought: Bool?
                }
                let parts: [Part]
            }
            let content: Content?
        }
        let candidates: [Candidate]?
    }
}

public enum AIImageToolError: LocalizedError, Equatable, Sendable {
    case invalidPrompt, noImage, invalidImage

    public var errorDescription: String? {
        switch self {
        case .invalidPrompt: return "请输入生成图片的提示词，内容不能超过 8,000 字节。"
        case .noImage: return "服务商未返回可直接显示的图片。请检查模型权限，或换一段提示词。"
        case .invalidImage: return "服务商返回的图片格式无效或超出 App 的预览上限。"
        }
    }
}
