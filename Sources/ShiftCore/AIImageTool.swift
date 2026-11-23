import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One raster image from a user-entered prompt. Never fetches provider-supplied URLs.
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

    public func generate(model: Model, apiKey: String, prompt: String) async throws -> Data {
        guard Self.models.contains(model) else { throw MultiProviderAIError.unsupportedModel }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= Self.maxPromptBytes else {
            throw AIImageToolError.invalidPrompt
        }

        let endpoint: String
        let body: [String: Any]
        switch model.provider {
        case .openAI:
            endpoint = "https://api.openai.com/v1/images/generations"
            body = ["model": model.id, "prompt": text, "n": 1, "size": "1024x1024",
                    "quality": "medium", "output_format": "png"]
        case .gemini:
            endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model.id):generateContent"
            body = [
                "contents": [["role": "user", "parts": [["text": text]]]],
                "generationConfig": ["responseModalities": ["IMAGE"], "imageConfig": ["imageSize": "1K"]],
            ]
        case .grok:
            endpoint = "https://api.x.ai/v1/images/generations"
            body = ["model": model.id, "prompt": text, "n": 1, "response_format": "b64_json",
                    "aspect_ratio": "1:1", "resolution": "1k", "quality": "low"]
        case .claude:
            throw MultiProviderAIError.unsupportedModel
        }

        guard let url = URL(string: endpoint) else { throw MultiProviderAIError.invalidRequest }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 180)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try AIProviderToolHTTP.authorize(&request, provider: model.provider, apiKey: apiKey)
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw MultiProviderAIError.invalidRequest
        }

        let response = try await AIProviderToolHTTP.data(for: request, provider: model.provider,
                                                         maxBytes: Self.responseByteLimit, transport: transport)
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
            mimeType = image.mimeType ?? (model.provider == .openAI ? "image/png" : nil)
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
