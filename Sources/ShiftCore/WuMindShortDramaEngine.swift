import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Pure-Swift SHA-256 / HMAC-SHA256 & Kling HS256 JWT Signer

/// Pure-Swift RFC 2104 HMAC-SHA256 and HS256 JWT signer for official Kling Open Platform API authentication.
/// Zero external dependencies; identical behavior across Linux CI and iOS/macOS.
public enum WuMindJWTAuth {
    private static let sha256K: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    public static func sha256(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        let bitLength = UInt64(bytes.count) &* 8
        bytes.append(0x80)
        while (bytes.count % 64) != 56 {
            bytes.append(0x00)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((bitLength >> shift) & 0xff))
        }

        var h0: UInt32 = 0x6a09e667
        var h1: UInt32 = 0xbb67ae85
        var h2: UInt32 = 0x3c6ef372
        var h3: UInt32 = 0xa54ff53a
        var h4: UInt32 = 0x510e527f
        var h5: UInt32 = 0x9b05688c
        var h6: UInt32 = 0x1f83d9ab
        var h7: UInt32 = 0x5be0cd19

        var w = [UInt32](repeating: 0, count: 64)
        for chunkStart in stride(from: 0, to: bytes.count, by: 64) {
            for i in 0..<16 {
                let j = chunkStart + i * 4
                w[i] = (UInt32(bytes[j]) << 24)
                    | (UInt32(bytes[j + 1]) << 16)
                    | (UInt32(bytes[j + 2]) << 8)
                    | UInt32(bytes[j + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }

            var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ ((~e) & g)
                let temp1 = h &+ s1 &+ ch &+ sha256K[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj

                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }

            h0 = h0 &+ a; h1 = h1 &+ b; h2 = h2 &+ c; h3 = h3 &+ d
            h4 = h4 &+ e; h5 = h5 &+ f; h6 = h6 &+ g; h7 = h7 &+ h
        }

        var out = Data(capacity: 32)
        for v in [h0, h1, h2, h3, h4, h5, h6, h7] {
            out.append(UInt8((v >> 24) & 0xff))
            out.append(UInt8((v >> 16) & 0xff))
            out.append(UInt8((v >> 8) & 0xff))
            out.append(UInt8(v & 0xff))
        }
        return out
    }

    public static func hmacSHA256(key: Data, message: Data) -> Data {
        let blockSize = 64
        var normalizedKey = key.count > blockSize ? [UInt8](sha256(key)) : [UInt8](key)
        if normalizedKey.count < blockSize {
            normalizedKey.append(contentsOf: repeatElement(0x00, count: blockSize - normalizedKey.count))
        }
        var oKeyPad = Data(capacity: blockSize + 32)
        var iKeyPad = Data(capacity: blockSize + message.count)
        for b in normalizedKey {
            oKeyPad.append(b ^ 0x5c)
            iKeyPad.append(b ^ 0x36)
        }
        iKeyPad.append(message)
        let innerHash = sha256(iKeyPad)
        oKeyPad.append(innerHash)
        return sha256(oKeyPad)
    }

    public static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Generates an official Kling AI Open Platform HS256 JWT (`iss = AccessKey`, signed with `SecretKey`).
    public static func makeKlingHS256JWT(
        accessKey: String,
        secretKey: String,
        issuedAt: Date = Date(),
        ttlSeconds: Int = 1800
    ) throws -> String {
        let ak = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let sk = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ak.isEmpty, !sk.isEmpty else {
            throw AIVideoToolError.generationFailed("请填写可灵开放平台官方 AccessKey 与 SecretKey（消费端会员积分不可直接作为 API 凭据）。")
        }
        let nowSec = Int(issuedAt.timeIntervalSince1970)
        let exp = nowSec + max(60, ttlSeconds)
        let nbf = nowSec - 5
        let headerJSON = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}"
        let payloadJSON = "{\"iss\":\"\(escapeJSON(ak))\",\"exp\":\(exp),\"nbf\":\(nbf)}"
        let headerB64 = base64URLEncode(Data(headerJSON.utf8))
        let payloadB64 = base64URLEncode(Data(payloadJSON.utf8))
        let signingInput = "\(headerB64).\(payloadB64)"
        let sig = hmacSHA256(key: Data(sk.utf8), message: Data(signingInput.utf8))
        return "\(signingInput).\(base64URLEncode(sig))"
    }

    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x >> n) | (x << (32 - n))
    }

    private static func escapeJSON(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

// MARK: - Official Volcengine Ark Seedance Video API Client

/// Official Volcengine Ark (火山方舟) Seedance video generation API client:
/// `POST /api/v3/contents/generations/tasks` & `GET /api/v3/contents/generations/tasks/{id}`.
/// Strictly uses official Ark API keys (never consumer Jimeng memberships) and isolates credentials from CDN downloads.
public struct VolcengineArkSeedanceClient: Sendable {
    public static let defaultBaseURL = "https://ark.cn-beijing.volces.com"
    public static let defaultModelID = "doubao-seedance-1-0-pro-250528"

    public struct Config: Equatable, Sendable {
        public var apiKey: String
        public var modelID: String
        public var baseURL: String?

        public init(
            apiKey: String,
            modelID: String = VolcengineArkSeedanceClient.defaultModelID,
            baseURL: String? = nil
        ) {
            self.apiKey = apiKey
            self.modelID = modelID
            self.baseURL = baseURL
        }
    }

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

    public func generate(
        prompt: String,
        aspectRatio: AIVideoTool.AspectRatio = .portrait9x16,
        durationSeconds: Int = 5,
        resolution: AIVideoTool.Resolution = .hd720,
        referenceImageBase64: String? = nil,
        config: Config,
        onProgress: (@Sendable (AIVideoTool.ProgressUpdate) async -> Void)? = nil
    ) async throws -> Data {
        let key = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw AIVideoToolError.generationFailed("请先在官方接口设置中填写火山方舟 Ark API Key。")
        }
        let modelID = config.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveModel = modelID.isEmpty ? Self.defaultModelID : modelID
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= AIVideoTool.maxPromptBytes else {
            throw AIVideoToolError.invalidPrompt
        }

        let baseURL = try ShortDramaVideoHTTP.validatedBaseURL(config.baseURL, defaultURL: Self.defaultBaseURL)
        let submitURL = try ShortDramaVideoHTTP.join(baseURL: baseURL, path: "/api/v3/contents/generations/tasks")
        let clampedDuration = max(4, min(10, durationSeconds))
        let decoratedPrompt = "\(text) --ratio \(aspectRatio.rawValue) --dur \(clampedDuration) --resolution \(resolution.rawValue)"

        var contentArray: [[String: Any]] = [
            ["type": "text", "text": decoratedPrompt]
        ]
        if let rawRef = referenceImageBase64?.trimmingCharacters(in: .whitespacesAndNewlines), !rawRef.isEmpty {
            let dataURI = rawRef.hasPrefix("data:image/") ? rawRef : "data:image/jpeg;base64,\(rawRef)"
            contentArray.append([
                "type": "image_url",
                "image_url": ["url": dataURI]
            ])
        }

        let body: [String: Any] = [
            "model": effectiveModel,
            "content": contentArray,
        ]

        let started = Date()
        await onProgress?(AIVideoTool.ProgressUpdate(stage: "正在提交火山方舟 Seedance 任务…", percent: 8, elapsedSeconds: 0))

        let createdData = try await ShortDramaVideoHTTP.sendJSON(
            url: submitURL,
            method: "POST",
            body: body,
            bearerToken: key,
            maxBytes: Self.metadataByteLimit,
            transport: transport
        )
        let created = try decode(ArkTaskResponse.self, from: createdData)
        guard let taskID = created.id, !taskID.isEmpty else {
            throw AIVideoToolError.generationFailed(created.error?.message ?? "火山方舟未返回有效任务 ID，请核对模型 / Endpoint ID 与权限。")
        }

        var current = created
        for attempt in 0..<maxPollAttempts {
            let status = (current.status ?? "").lowercased()
            if status == "succeeded" || status == "completed" {
                let videoURLString = current.content?.videoURL ?? current.output?.videoURL
                guard let videoURLString, let dlURL = URL(string: videoURLString) else {
                    throw AIVideoToolError.invalidVideoData
                }
                await onProgress?(AIVideoTool.ProgressUpdate(stage: "Seedance 渲染完成，正在下载 MP4…", percent: 94, elapsedSeconds: Date().timeIntervalSince(started)))
                let mp4 = try await ShortDramaVideoHTTP.downloadMedia(
                    url: dlURL,
                    apiHost: baseURL.host ?? "",
                    bearerToken: key,
                    maxBytes: Self.videoByteLimit,
                    transport: transport
                )
                guard AIVideoTool.isValidMP4(mp4) else { throw AIVideoToolError.invalidVideoData }
                return mp4
            }
            if status == "failed" || status == "cancelled" || status == "expired" {
                throw AIVideoToolError.generationFailed(current.error?.message ?? "火山方舟 Seedance 任务失败（\(status)）。")
            }

            let pct = min(90, 14 + attempt * 6)
            await onProgress?(AIVideoTool.ProgressUpdate(
                stage: "火山方舟 Seedance 渲染中（\(status.isEmpty ? "queued" : status)）…",
                percent: pct,
                elapsedSeconds: Date().timeIntervalSince(started)
            ))
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)

            let pollURL = try ShortDramaVideoHTTP.join(baseURL: baseURL, path: "/api/v3/contents/generations/tasks/\(taskID)")
            let pollData = try await ShortDramaVideoHTTP.sendJSON(
                url: pollURL,
                method: "GET",
                body: nil,
                bearerToken: key,
                maxBytes: Self.metadataByteLimit,
                transport: transport
            )
            current = try decode(ArkTaskResponse.self, from: pollData)
        }
        throw MultiProviderAIError.timedOut
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw MultiProviderAIError.invalidResponse
        }
        return value
    }

    private struct ArkTaskResponse: Decodable {
        struct ContentPayload: Decodable {
            let videoURL: String?
            enum CodingKeys: String, CodingKey { case videoURL = "video_url" }
        }
        struct ErrorPayload: Decodable {
            let code: String?
            let message: String?
        }
        let id: String?
        let status: String?
        let content: ContentPayload?
        let output: ContentPayload?
        let error: ErrorPayload?
    }
}

// MARK: - Official Kling AI Open Platform Video API Client

/// Official Kling AI Open Platform (可灵开放平台) video generation client:
/// `POST /v1/videos/text2video` or `/v1/videos/image2video` with HS256 JWT authentication.
/// Strictly uses official AK/SK (never consumer Kling memberships) and isolates JWT from CDN downloads.
public struct KlingOfficialVideoClient: Sendable {
    public static let defaultBaseURL = "https://api.klingai.com"
    public static let defaultModelName = "kling-v1-6"

    public struct Config: Equatable, Sendable {
        public var accessKey: String
        public var secretKey: String
        public var modelName: String
        public var mode: String
        public var baseURL: String?

        public init(
            accessKey: String,
            secretKey: String,
            modelName: String = KlingOfficialVideoClient.defaultModelName,
            mode: String = "std",
            baseURL: String? = nil
        ) {
            self.accessKey = accessKey
            self.secretKey = secretKey
            self.modelName = modelName
            self.mode = mode
            self.baseURL = baseURL
        }
    }

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

    public func generate(
        prompt: String,
        aspectRatio: AIVideoTool.AspectRatio = .portrait9x16,
        durationSeconds: Int = 5,
        referenceImageBase64: String? = nil,
        config: Config,
        onProgress: (@Sendable (AIVideoTool.ProgressUpdate) async -> Void)? = nil
    ) async throws -> Data {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= AIVideoTool.maxPromptBytes else {
            throw AIVideoToolError.invalidPrompt
        }

        let jwt = try WuMindJWTAuth.makeKlingHS256JWT(accessKey: config.accessKey, secretKey: config.secretKey)
        let baseURL = try ShortDramaVideoHTTP.validatedBaseURL(config.baseURL, defaultURL: Self.defaultBaseURL)
        let effectiveModel = config.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultModelName : config.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveMode = config.mode == "pro" ? "pro" : "std"
        let klingDuration = durationSeconds >= 8 ? "10" : "5"

        let cleanImage = stripDataURIPrefix(referenceImageBase64)
        let endpointPath = cleanImage != nil ? "/v1/videos/image2video" : "/v1/videos/text2video"
        let submitURL = try ShortDramaVideoHTTP.join(baseURL: baseURL, path: endpointPath)

        var body: [String: Any] = [
            "model_name": effectiveModel,
            "prompt": text,
            "duration": klingDuration,
            "aspect_ratio": aspectRatio.rawValue,
            "mode": effectiveMode,
        ]
        if let cleanImage {
            body["image"] = cleanImage
        }

        let started = Date()
        await onProgress?(AIVideoTool.ProgressUpdate(stage: "正在提交可灵开放平台任务…", percent: 8, elapsedSeconds: 0))

        let createdData = try await ShortDramaVideoHTTP.sendJSON(
            url: submitURL,
            method: "POST",
            body: body,
            bearerToken: jwt,
            maxBytes: Self.metadataByteLimit,
            transport: transport
        )
        let created = try decode(KlingEnvelope.self, from: createdData)
        if let code = created.code, code != 0 {
            throw AIVideoToolError.generationFailed(created.message ?? "可灵接口返回错误码 \(code)。")
        }
        guard let taskID = created.data?.taskID, !taskID.isEmpty else {
            throw AIVideoToolError.invalidJobResponse
        }

        var current = created
        for attempt in 0..<maxPollAttempts {
            let status = (current.data?.taskStatus ?? "").lowercased()
            if status == "succeed" || status == "succeeded" {
                guard let urlStr = current.data?.taskResult?.videos?.first?.url,
                      let dlURL = URL(string: urlStr) else {
                    throw AIVideoToolError.invalidVideoData
                }
                await onProgress?(AIVideoTool.ProgressUpdate(stage: "可灵渲染完成，正在下载 MP4…", percent: 94, elapsedSeconds: Date().timeIntervalSince(started)))
                let mp4 = try await ShortDramaVideoHTTP.downloadMedia(
                    url: dlURL,
                    apiHost: baseURL.host ?? "",
                    bearerToken: jwt,
                    maxBytes: Self.videoByteLimit,
                    transport: transport
                )
                guard AIVideoTool.isValidMP4(mp4) else { throw AIVideoToolError.invalidVideoData }
                return mp4
            }
            if status == "failed" {
                throw AIVideoToolError.generationFailed(current.data?.taskStatusMsg ?? current.message ?? "可灵视频任务失败。")
            }

            let pct = min(90, 14 + attempt * 6)
            await onProgress?(AIVideoTool.ProgressUpdate(
                stage: "可灵渲染中（\(status.isEmpty ? "submitted" : status)）…",
                percent: pct,
                elapsedSeconds: Date().timeIntervalSince(started)
            ))
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)

            let pollURL = try ShortDramaVideoHTTP.join(baseURL: baseURL, path: "\(endpointPath)/\(taskID)")
            let pollData = try await ShortDramaVideoHTTP.sendJSON(
                url: pollURL,
                method: "GET",
                body: nil,
                bearerToken: jwt,
                maxBytes: Self.metadataByteLimit,
                transport: transport
            )
            current = try decode(KlingEnvelope.self, from: pollData)
            if let code = current.code, code != 0 {
                throw AIVideoToolError.generationFailed(current.message ?? "可灵查询返回错误码 \(code)。")
            }
        }
        throw MultiProviderAIError.timedOut
    }

    private func stripDataURIPrefix(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if let comma = trimmed.firstIndex(of: ","), trimmed.hasPrefix("data:") {
            let body = String(trimmed[trimmed.index(after: comma)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? nil : body
        }
        return trimmed
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw MultiProviderAIError.invalidResponse
        }
        return value
    }

    private struct KlingEnvelope: Decodable {
        struct TaskData: Decodable {
            struct TaskResult: Decodable {
                struct VideoItem: Decodable {
                    let id: String?
                    let url: String?
                    let duration: String?
                }
                let videos: [VideoItem]?
            }
            let taskID: String?
            let taskStatus: String?
            let taskStatusMsg: String?
            let taskResult: TaskResult?

            enum CodingKeys: String, CodingKey {
                case taskID = "task_id"
                case taskStatus = "task_status"
                case taskStatusMsg = "task_status_msg"
                case taskResult = "task_result"
            }
        }
        let code: Int?
        let message: String?
        let data: TaskData?
    }
}

// MARK: - Secure HTTP Helper for Official Short-Drama Video Clients

private enum ShortDramaVideoHTTP {
    final class BlockRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    static func validatedBaseURL(_ raw: String?, defaultURL: String) throws -> URL {
        let candidate = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let str = (candidate?.isEmpty == false) ? candidate! : defaultURL
        guard let url = URL(string: str),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil,
              host != "localhost", !host.hasPrefix("127."), !host.hasPrefix("10."), !host.hasPrefix("192.168.") else {
            throw MultiProviderAIError.invalidRequest
        }
        return url
    }

    static func join(baseURL: URL, path: String) throws -> URL {
        var baseString = baseURL.absoluteString
        while baseString.hasSuffix("/") { baseString.removeLast() }
        let suffix = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: baseString + suffix) else {
            throw MultiProviderAIError.invalidRequest
        }
        return url
    }

    static func sendJSON(
        url: URL,
        method: String,
        body: [String: Any]?,
        bearerToken: String,
        maxBytes: Int,
        transport: MultiProviderAIClient.Transport?
    ) async throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 90)
        req.httpMethod = method
        req.httpShouldHandleCookies = false
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.withoutEscapingSlashes])
        }
        let result: (Data, URLResponse)
        if let transport {
            result = try await transport(req)
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.httpShouldSetCookies = false
            result = try await URLSession(configuration: cfg, delegate: BlockRedirects(), delegateQueue: nil).data(for: req)
        }
        guard let http = result.1 as? HTTPURLResponse else {
            throw MultiProviderAIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: result.0.prefix(300), encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AIVideoToolError.generationFailed("HTTP \(http.statusCode): \(snippet)")
        }
        guard result.0.count <= maxBytes else {
            throw MultiProviderAIError.invalidResponse
        }
        return result.0
    }

    static func downloadMedia(
        url: URL,
        apiHost: String,
        bearerToken: String,
        maxBytes: Int,
        transport: MultiProviderAIClient.Transport?
    ) async throws -> Data {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil else {
            throw MultiProviderAIError.invalidRequest
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 180)
        req.httpMethod = "GET"
        req.httpShouldHandleCookies = false
        // Strictly NEVER forward API keys or JWTs to separate CDN download hosts.
        if !apiHost.isEmpty && host == apiHost.lowercased() {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        let result: (Data, URLResponse)
        if let transport {
            result = try await transport(req)
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.httpShouldSetCookies = false
            result = try await URLSession(configuration: cfg).data(for: req)
        }
        guard let http = result.1 as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              result.0.count <= maxBytes else {
            throw AIVideoToolError.invalidVideoData
        }
        return result.0
    }
}

// MARK: - Short-Drama Studio v1 Models & Pure Engine

public enum WuMindDramaVideoEngine: String, CaseIterable, Codable, Identifiable, Sendable, Hashable {
    case seedance
    case kling
    case grok
    case sora2
    case veo3

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .seedance: return "火山方舟 · 即梦 Seedance"
        case .kling: return "可灵 AI 开放平台"
        case .grok: return "Grok Imagine Video"
        case .sora2: return "OpenAI Sora 2"
        case .veo3: return "Google Veo 3"
        }
    }

    public var shortBadge: String {
        switch self {
        case .seedance: return "即梦 Seedance"
        case .kling: return "可灵 Kling"
        case .grok: return "Grok Video"
        case .sora2: return "Sora 2"
        case .veo3: return "Veo 3"
        }
    }

    public var defaultModelID: String {
        switch self {
        case .seedance: return VolcengineArkSeedanceClient.defaultModelID
        case .kling: return KlingOfficialVideoClient.defaultModelName
        case .grok: return "grok-imagine-video"
        case .sora2: return "sora-2"
        case .veo3: return "gemini-omni-1.2-flash"
        }
    }

    /// Upstream model's strictly allowed discrete generation durations (seconds).
    /// Timeline duration (`shot.durationSeconds`) is intentionally separated from generation duration:
    /// e.g. a 6s timeline shot on Sora 2 (4/8/12s) generates 8s and trims cleanly to 6s on export.
    public var supportedDurations: [Int] {
        switch self {
        case .seedance: return [4, 5, 6, 7, 8, 9, 10]
        case .kling: return [5, 10]
        case .grok: return [4, 5, 8, 10]
        case .sora2: return [4, 8, 12]
        case .veo3: return [4, 5, 8, 10, 15]
        }
    }

    public var supportedAspectRatios: [AIVideoTool.AspectRatio] {
        switch self {
        case .seedance, .kling, .grok:
            return [.portrait9x16, .landscape16x9, .square1x1]
        case .sora2, .veo3:
            return [.portrait9x16, .landscape16x9]
        }
    }

    /// Reference estimate in RMB per 5-second shot for transparent mobile budgeting.
    public var estimatedCostPer5SecYuan: Double {
        switch self {
        case .seedance: return 1.20
        case .kling: return 1.50
        case .grok: return 1.80
        case .sora2: return 3.60
        case .veo3: return 3.20
        }
    }

    public var supportsReferenceImage: Bool {
        switch self {
        case .seedance, .kling: return true
        case .grok, .sora2, .veo3: return false
        }
    }

    public var officialAPINote: String {
        switch self {
        case .seedance:
            return "走火山方舟官方 Seedance API（支持 4~10 秒、9:16 与参考图；也可通过 WUMIND 内置视频目录调用）"
        case .kling:
            return "走可灵 AI 官方开放平台 API（支持 5/10 秒、9:16 与参考图；不可使用消费端可灵会员余额）"
        case .grok:
            return "复用本机已配置的 xAI API Key（grok-imagine-video，支持 4/5/8/10 秒、9:16）"
        case .sora2:
            return "复用本机 OpenAI API Key 或 WUMIND 内置目录（sora-2，支持 4/8/12 秒、9:16）"
        case .veo3:
            return "复用本机 Google Gemini API Key 或 WUMIND 内置目录（gemini-omni-1.2-flash / Veo，支持 9:16）"
        }
    }

    /// Validates duration, aspect ratio, and reference-image support IMMEDIATELY upon engine selection,
    /// separating timeline duration from upstream model generation duration without silently swapping models.
    public func generationPlan(
        timelineSeconds: Double,
        aspectRatio: AIVideoTool.AspectRatio = .portrait9x16,
        hasReferenceImage: Bool = false,
        customSupportedDurations: [Int]? = nil,
        customUnitPricePerSecondYuan: Double? = nil
    ) -> WuMindDramaShotGenerationPlan {
        let cleanTimeline = max(1.0, timelineSeconds)
        let allowed = ((customSupportedDurations?.isEmpty == false) ? customSupportedDurations! : supportedDurations)
            .filter { $0 > 0 }
            .sorted()
        let safeAllowed = allowed.isEmpty ? [5, 8] : allowed

        let targetCeil = Int(ceil(cleanTimeline - 0.001))
        let chosenGenSeconds: Int
        if let exact = safeAllowed.first(where: { $0 == targetCeil }), abs(cleanTimeline - Double(exact)) < 0.05 {
            chosenGenSeconds = exact
        } else if let covering = safeAllowed.first(where: { $0 >= targetCeil }) {
            chosenGenSeconds = covering
        } else {
            chosenGenSeconds = safeAllowed.last ?? targetCeil
        }

        let needsTrim = Double(chosenGenSeconds) > cleanTimeline + 0.05
        let shorterThanTimeline = Double(chosenGenSeconds) + 0.05 < cleanTimeline

        let cost: Double
        if let perSec = customUnitPricePerSecondYuan, perSec > 0 {
            cost = (perSec * Double(chosenGenSeconds) * 100).rounded() / 100
        } else {
            cost = ((estimatedCostPer5SecYuan * (Double(chosenGenSeconds) / 5.0)) * 100).rounded() / 100
        }

        let aspectSupported = supportedAspectRatios.contains(aspectRatio)
        let allowedText = safeAllowed.map(String.init).joined(separator: " / ")
        let timelineText = Self.formatSecondsLabel(cleanTimeline)

        let durationNotice: String
        let confirmationTitle: String?
        let confirmationMessage: String?
        if needsTrim {
            durationNotice = "生成 \(chosenGenSeconds) 秒，剪入 \(timelineText) 秒（\(shortBadge) 仅支持 \(allowedText) 秒 · 预计 ¥\(String(format: "%.2f", cost))）"
            confirmationTitle = "确认按 \(chosenGenSeconds) 秒生成并剪入 \(timelineText) 秒？"
            confirmationMessage = "当前模型「\(displayName)」可选生成时长为 \(allowedText) 秒，不支持直接生成 \(timelineText) 秒。\n\n确认后将按 \(chosenGenSeconds) 秒提交生成，并自动裁剪到 \(timelineText) 秒时间线（预计费用 ¥\(String(format: "%.2f", cost))）。不会擅自更换模型，也不会改动其余镜头。"
        } else if shorterThanTimeline {
            durationNotice = "生成 \(chosenGenSeconds) 秒（低于时间线 \(timelineText) 秒，\(shortBadge) 最长仅支持 \(chosenGenSeconds) 秒 · 预计 ¥\(String(format: "%.2f", cost))）"
            confirmationTitle = "确认按最长 \(chosenGenSeconds) 秒生成本镜？"
            confirmationMessage = "当前模型「\(displayName)」最长仅支持 \(chosenGenSeconds) 秒（可选 \(allowedText) 秒），短于当前时间线 \(timelineText) 秒。\n\n确认后将按 \(chosenGenSeconds) 秒生成（预计费用 ¥\(String(format: "%.2f", cost))），不会擅自更换模型。"
        } else {
            durationNotice = "时间线 \(timelineText) 秒 = 生成 \(chosenGenSeconds) 秒（无需裁剪 · 预计 ¥\(String(format: "%.2f", cost))）"
            confirmationTitle = nil
            confirmationMessage = nil
        }

        let refNotice: String?
        if hasReferenceImage && !supportsReferenceImage {
            refNotice = "「\(shortBadge)」不支持参考图绑定，本镜将仅按文字外观描述生成（不会自动换模型；如需参考图锁脸，请改选即梦 Seedance 或可灵 Kling）。"
        } else {
            refNotice = nil
        }

        let aspectNotice: String? = aspectSupported
            ? nil
            : "「\(shortBadge)」不支持 \(aspectRatio.rawValue) 竖屏画幅，无法提交本镜。"

        return WuMindDramaShotGenerationPlan(
            engine: self,
            timelineSeconds: cleanTimeline,
            generationDurationSeconds: chosenGenSeconds,
            supportedDurations: safeAllowed,
            needsTrimToTimeline: needsTrim,
            isShorterThanTimeline: shorterThanTimeline,
            estimatedCostYuan: cost,
            aspectRatioSupported: aspectSupported,
            referenceImageAttached: hasReferenceImage,
            referenceImageSupported: supportsReferenceImage,
            durationSummary: durationNotice,
            aspectRatioWarning: aspectNotice,
            referenceImageWarning: refNotice,
            confirmationTitle: confirmationTitle,
            confirmationMessage: confirmationMessage
        )
    }

    private static func formatSecondsLabel(_ seconds: Double) -> String {
        if abs(seconds - seconds.rounded()) < 0.05 {
            return "\(Int(seconds.rounded()))"
        }
        return String(format: "%.1f", seconds)
    }
}

public struct WuMindDramaShotGenerationPlan: Equatable, Sendable {
    public let engine: WuMindDramaVideoEngine
    public let timelineSeconds: Double
    public let generationDurationSeconds: Int
    public let supportedDurations: [Int]
    public let needsTrimToTimeline: Bool
    public let isShorterThanTimeline: Bool
    public let estimatedCostYuan: Double
    public let aspectRatioSupported: Bool
    public let referenceImageAttached: Bool
    public let referenceImageSupported: Bool
    public let durationSummary: String
    public let aspectRatioWarning: String?
    public let referenceImageWarning: String?
    public let confirmationTitle: String?
    public let confirmationMessage: String?

    public var requiresUserConfirmation: Bool {
        needsTrimToTimeline || isShorterThanTimeline
    }

    public var canSubmit: Bool {
        aspectRatioSupported
    }
}

public enum WuMindDramaExportKind: String, Equatable, Sendable {
    case roughCutPreview
    case finalMaster

    public var title: String {
        switch self {
        case .roughCutPreview: return "粗剪预览"
        case .finalMaster: return "成片导出"
        }
    }

    public var buttonTitle: String {
        switch self {
        case .roughCutPreview: return "导出粗剪预览 MP4（含未生成分镜占位）"
        case .finalMaster: return "导出 9:16 短剧成片 MP4（含字幕与独立配音轨）"
        }
    }
}

public enum WuMindDramaVoicePreset: String, CaseIterable, Codable, Identifiable, Sendable, Hashable {
    case warmFemale
    case brightFemale
    case steadyMale
    case deepMale
    case narrator

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .warmFemale: return "温润女声"
        case .brightFemale: return "干练女声"
        case .steadyMale: return "沉稳男声"
        case .deepMale: return "低沉男声"
        case .narrator: return "悬疑旁白"
        }
    }

    public var speechRate: Float {
        switch self {
        case .warmFemale: return 0.50
        case .brightFemale: return 0.53
        case .steadyMale: return 0.49
        case .deepMale: return 0.46
        case .narrator: return 0.48
        }
    }

    public var pitchMultiplier: Float {
        switch self {
        case .warmFemale: return 1.12
        case .brightFemale: return 1.22
        case .steadyMale: return 0.90
        case .deepMale: return 0.78
        case .narrator: return 0.96
        }
    }
}

public enum WuMindDramaCameraFraming: String, CaseIterable, Codable, Identifiable, Sendable, Hashable {
    case extremeWide
    case wide
    case medium
    case closeUp
    case extremeCloseUp

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .extremeWide: return "远景"
        case .wide: return "全景"
        case .medium: return "中景"
        case .closeUp: return "近景"
        case .extremeCloseUp: return "特写"
        }
    }

    public var promptDirective: String {
        switch self {
        case .extremeWide: return "extreme wide establishing shot (远景交代环境氛围)"
        case .wide: return "wide full-body shot (全景展现人物与空间关系)"
        case .medium: return "medium waist-up cinematic shot (中景对话构图)"
        case .closeUp: return "tight close-up chest-and-face shot with shallow depth of field (近景聚焦表情与眼神)"
        case .extremeCloseUp: return "dramatic extreme close-up on eyes or key prop (极致特写强化情绪冲击)"
        }
    }

    public static func detect(in text: String) -> WuMindDramaCameraFraming? {
        if text.contains("特写") { return .extremeCloseUp }
        if text.contains("近景") { return .closeUp }
        if text.contains("中景") { return .medium }
        if text.contains("全景") { return .wide }
        if text.contains("远景") { return .extremeWide }
        return nil
    }
}

public enum WuMindDramaGenre: String, CaseIterable, Codable, Identifiable, Sendable, Hashable {
    case suspense = "悬疑反转"
    case urban = "都市职场"
    case ancient = "古风权谋"
    case romance = "甜虐情感"
    case scifi = "科幻微剧"

    public var id: String { rawValue }
}

public struct WuMindDramaCharacter: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var roleSummary: String
    public var appearanceTag: String
    public var voicePreset: WuMindDramaVoicePreset
    public var referenceImageBase64: String?

    public init(
        id: UUID = UUID(),
        name: String,
        roleSummary: String,
        appearanceTag: String,
        voicePreset: WuMindDramaVoicePreset,
        referenceImageBase64: String? = nil
    ) {
        self.id = id
        self.name = name
        self.roleSummary = roleSummary
        self.appearanceTag = appearanceTag
        self.voicePreset = voicePreset
        self.referenceImageBase64 = referenceImageBase64
    }
}

public struct WuMindShotTake: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var takeNumber: Int
    public var engine: WuMindDramaVideoEngine
    public var modelID: String
    public var promptUsed: String
    public var revisionNote: String
    /// Relative filename inside the project's media directory (e.g. `shot_<id>_take2.mp4`).
    public var videoFilename: String
    public var durationSeconds: Double
    public var estimatedCostYuan: Double
    public var usedReferenceImage: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        takeNumber: Int,
        engine: WuMindDramaVideoEngine,
        modelID: String,
        promptUsed: String,
        revisionNote: String,
        videoFilename: String,
        durationSeconds: Double,
        estimatedCostYuan: Double,
        usedReferenceImage: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.takeNumber = takeNumber
        self.engine = engine
        self.modelID = modelID
        self.promptUsed = promptUsed
        self.revisionNote = revisionNote
        self.videoFilename = videoFilename
        self.durationSeconds = durationSeconds
        self.estimatedCostYuan = estimatedCostYuan
        self.usedReferenceImage = usedReferenceImage
        self.createdAt = createdAt
    }
}

public struct WuMindDramaShot: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var cameraFraming: WuMindDramaCameraFraming
    public var cameraMovement: String
    public var visualPrompt: String
    public var dialogue: String
    public var subtitleText: String
    public var characterID: UUID?
    public var durationSeconds: Double
    public var trimStartSeconds: Double
    public var trimEndSeconds: Double
    public var preferredEngine: WuMindDramaVideoEngine
    public var takes: [WuMindShotTake]
    public var activeTakeID: UUID?
    public var subtitleEnabled: Bool
    public var voiceoverEnabled: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        cameraFraming: WuMindDramaCameraFraming = .medium,
        cameraMovement: String = "缓慢推镜",
        visualPrompt: String,
        dialogue: String,
        subtitleText: String? = nil,
        characterID: UUID? = nil,
        durationSeconds: Double = 6.0,
        trimStartSeconds: Double = 0.0,
        trimEndSeconds: Double? = nil,
        preferredEngine: WuMindDramaVideoEngine = .seedance,
        takes: [WuMindShotTake] = [],
        activeTakeID: UUID? = nil,
        subtitleEnabled: Bool = true,
        voiceoverEnabled: Bool = true
    ) {
        let safeDur = max(2.0, min(12.0, durationSeconds))
        let safeStart = max(0.0, min(safeDur - 1.0, trimStartSeconds))
        let rawEnd = trimEndSeconds ?? safeDur
        let safeEnd = max(safeStart + 1.0, min(safeDur, rawEnd))

        self.id = id
        self.title = title
        self.cameraFraming = cameraFraming
        self.cameraMovement = cameraMovement
        self.visualPrompt = visualPrompt
        self.dialogue = dialogue
        self.subtitleText = subtitleText ?? dialogue
        self.characterID = characterID
        self.durationSeconds = safeDur
        self.trimStartSeconds = safeStart
        self.trimEndSeconds = safeEnd
        self.preferredEngine = preferredEngine
        self.takes = takes
        self.activeTakeID = activeTakeID ?? takes.last?.id
        self.subtitleEnabled = subtitleEnabled
        self.voiceoverEnabled = voiceoverEnabled
    }

    public var activeTake: WuMindShotTake? {
        if let activeTakeID, let match = takes.first(where: { $0.id == activeTakeID }) {
            return match
        }
        return takes.last
    }

    public var isRendered: Bool { activeTake != nil }

    public var trimmedDuration: Double {
        max(1.0, trimEndSeconds - trimStartSeconds)
    }
}

public struct WuMindSubtitleCue: Equatable, Sendable {
    public let shotIndex: Int
    public let speakerName: String?
    public let text: String
    public let startSeconds: Double
    public let endSeconds: Double

    public init(shotIndex: Int, speakerName: String?, text: String, startSeconds: Double, endSeconds: Double) {
        self.shotIndex = shotIndex
        self.speakerName = speakerName
        self.text = text
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}

public struct WuMindShortDramaProject: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var premise: String
    public var genre: WuMindDramaGenre
    public var targetDurationSeconds: Int
    public var characters: [WuMindDramaCharacter]
    public var shots: [WuMindDramaShot]
    public var globalSubtitlesEnabled: Bool
    public var globalVoiceoverEnabled: Bool
    public var totalGenerations: Int
    public var singleShotReshoots: Int
    public var estimatedTotalCostYuan: Double
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        premise: String,
        genre: WuMindDramaGenre = .suspense,
        targetDurationSeconds: Int = 36,
        characters: [WuMindDramaCharacter],
        shots: [WuMindDramaShot],
        globalSubtitlesEnabled: Bool = true,
        globalVoiceoverEnabled: Bool = true,
        totalGenerations: Int = 0,
        singleShotReshoots: Int = 0,
        estimatedTotalCostYuan: Double = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.premise = premise
        self.genre = genre
        self.targetDurationSeconds = max(30, min(60, targetDurationSeconds))
        self.characters = characters
        self.shots = shots
        self.globalSubtitlesEnabled = globalSubtitlesEnabled
        self.globalVoiceoverEnabled = globalVoiceoverEnabled
        self.totalGenerations = totalGenerations
        self.singleShotReshoots = singleShotReshoots
        self.estimatedTotalCostYuan = estimatedTotalCostYuan
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func character(for shot: WuMindDramaShot) -> WuMindDramaCharacter? {
        guard let cid = shot.characterID else { return nil }
        return characters.first(where: { $0.id == cid })
    }
}

/// Core pure-Swift engine for WUMIND Short-Drama Studio v1:
/// storyboard structuring, selective single-shot reshoot with dialogue/voice lock,
/// A/B take comparison, drag-reorder/trim timeline math, and cost/consistency auditing.
public enum WuMindShortDramaEngine {

    public static func storyboardSystemPrompt(
        premise: String,
        genre: WuMindDramaGenre,
        targetDurationSeconds: Int
    ) -> String {
        let clampedDuration = max(30, min(60, targetDurationSeconds))
        let shotCount = max(5, min(10, Int((Double(clampedDuration) / 6.0).rounded())))
        return """
        你是顶级竖屏短剧导演与分镜编剧。请把用户的创意拆成一部节奏紧凑、前 3 秒强钩子、结尾有反转的 9:16 竖屏短剧分镜脚本。
        要求：
        1. 总时长约 \(clampedDuration) 秒，共 \(shotCount) 个镜头，每镜 5~6 秒，题材为「\(genre.rawValue)」。
        2. 设定 2~3 位核心角色，每名角色给出固定的外形标签（发型、服饰、年龄气质），便于所有镜头复用同一人物外观。
        3. 每个镜头给出：title（镜头标题）、framing（远景/全景/中景/近景/特写）、cameraMovement（运镜）、visualPrompt（可直接喂给即梦/可灵/Sora 的中文电影画面描述，含构图与光影）、characterName（说话角色名）、dialogue（10~26字强冲突台词）、durationSeconds（5或6）。
        4. 只输出严格合法的 JSON，不要任何解释文字或 Markdown 以外的废话。JSON 结构如下：
        {
          "title": "短剧剧名（8字以内）",
          "characters": [
            { "name": "林岚", "roleSummary": "值班主控", "appearanceTag": "28岁中国女性，深蓝工装外套，马尾辫，冷静眼神", "voice": "brightFemale" }
          ],
          "shots": [
            {
              "title": "第1镜·暴雨警报",
              "framing": "中景",
              "cameraMovement": "缓慢推镜",
              "visualPrompt": "9:16 竖屏电影感画面...",
              "characterName": "林岚",
              "dialogue": "三号站的遥测信号，刚被人手动掐断了。",
              "durationSeconds": 6
            }
          ]
        }
        voice 仅可取：warmFemale / brightFemale / steadyMale / deepMale / narrator。
        """
    }

    public static func parseStoryboard(
        from rawOutput: String,
        premise: String,
        genre: WuMindDramaGenre,
        targetDurationSeconds: Int,
        defaultEngine: WuMindDramaVideoEngine = .seedance
    ) -> WuMindShortDramaProject {
        let cleaned = extractJSONObject(from: rawOutput)
        guard let data = cleaned.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RawDramaPayload.self, from: data),
              let rawShots = decoded.shots, !rawShots.isEmpty else {
            return fallbackProject(
                premise: premise,
                genre: genre,
                targetDurationSeconds: targetDurationSeconds,
                defaultEngine: defaultEngine
            )
        }

        var characters: [WuMindDramaCharacter] = (decoded.characters ?? []).compactMap { c in
            let name = (c.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let voice = WuMindDramaVoicePreset(rawValue: c.voice ?? "") ?? .steadyMale
            return WuMindDramaCharacter(
                name: name,
                roleSummary: (c.roleSummary ?? "核心角色").trimmingCharacters(in: .whitespacesAndNewlines),
                appearanceTag: (c.appearanceTag ?? "现代写实电影造型").trimmingCharacters(in: .whitespacesAndNewlines),
                voicePreset: voice
            )
        }
        if characters.isEmpty {
            characters = [
                WuMindDramaCharacter(
                    name: "主角",
                    roleSummary: "第一视角主角",
                    appearanceTag: "30岁东亚青年，深色风衣，眼神克制锐利",
                    voicePreset: .steadyMale
                )
            ]
        }

        let shots: [WuMindDramaShot] = rawShots.enumerated().map { idx, item in
            let title = (item.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? "第\(idx + 1)镜"
            let framing = WuMindDramaCameraFraming.detect(in: item.framing ?? "") ?? .medium
            let movement = (item.cameraMovement?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? "稳态推镜"
            let visual = (item.visualPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? "9:16 竖屏电影感构图，\(premise)"
            let dialogue = (item.dialogue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let dur = max(4.0, min(10.0, item.durationSeconds ?? 6.0))
            let matchedChar = characters.first(where: {
                guard let name = item.characterName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return false }
                return $0.name == name || $0.name.contains(name) || name.contains($0.name)
            }) ?? characters.first

            return WuMindDramaShot(
                title: title,
                cameraFraming: framing,
                cameraMovement: movement,
                visualPrompt: visual,
                dialogue: dialogue,
                subtitleText: dialogue,
                characterID: matchedChar?.id,
                durationSeconds: dur,
                preferredEngine: defaultEngine
            )
        }

        let title = (decoded.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? String(premise.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12))

        return WuMindShortDramaProject(
            title: title.isEmpty ? "竖屏短剧草稿" : title,
            premise: premise,
            genre: genre,
            targetDurationSeconds: targetDurationSeconds,
            characters: characters,
            shots: shots
        )
    }

    /// Ready-to-edit 36-second 6-shot vertical short drama template so users can immediately test
    /// timeline trimming, dragging, voice/subtitle tracks, and single-shot reshoot UX.
    public static func sampleVerticalDrama(
        defaultEngine: WuMindDramaVideoEngine = .seedance
    ) -> WuMindShortDramaProject {
        let lin = WuMindDramaCharacter(
            name: "林岚",
            roleSummary: "主控值班长",
            appearanceTag: "28岁中国女性，深蓝战术防雨外套，高马尾，冷峻专注",
            voicePreset: .brightFemale
        )
        let chen = WuMindDramaCharacter(
            name: "陈默",
            roleSummary: "夜间巡检员",
            appearanceTag: "32岁中国男性，黑色机能夹克，短寸头，神色克制",
            voicePreset: .deepMale
        )

        let shots: [WuMindDramaShot] = [
            WuMindDramaShot(
                title: "第1镜·暴雨告警",
                cameraFraming: .wide,
                cameraMovement: "低机位缓推",
                visualPrompt: "9:16 竖屏电影感，暴雨夜玻璃幕墙监控中心，红色告警光映在深蓝外套女子侧脸，雨滴顺玻璃滑落，高对比冷暖光影",
                dialogue: "凌晨两点零七分，三号站整条链路突然归零。",
                characterID: lin.id,
                durationSeconds: 6.0,
                preferredEngine: defaultEngine
            ),
            WuMindDramaShot(
                title: "第2镜·孤身抵近",
                cameraFraming: .medium,
                cameraMovement: "手持跟拍",
                visualPrompt: "9:16 竖屏悬疑质感，潮湿走廊应急绿灯闪烁，穿黑色机能夹克的男子提着手电快步走近机房铁门",
                dialogue: "我刚到门口，锁是开着的，里面还有人。",
                characterID: chen.id,
                durationSeconds: 6.0,
                preferredEngine: defaultEngine
            ),
            WuMindDramaShot(
                title: "第3镜·异常波形",
                cameraFraming: .extremeCloseUp,
                cameraMovement: "快切推焦",
                visualPrompt: "9:16 竖屏微距特写，监控大屏跳动的波形曲线与突然弹出的匿名登录日志，蓝红反光清晰锐利",
                dialogue: "别开门！操作工号……写的是你自己的名字。",
                characterID: lin.id,
                durationSeconds: 6.0,
                preferredEngine: defaultEngine
            ),
            WuMindDramaShot(
                title: "第4镜·对峙转折",
                cameraFraming: .medium,
                cameraMovement: "环绕慢推",
                visualPrompt: "9:16 竖屏电影级光影，昏暗铁门前男子缓缓抬头直视走廊监控镜头，手电光从下颌向上打亮半张脸，气氛极度紧绷",
                dialogue: "林岚，你确定现在坐在总控室里的，是真正的你吗？",
                characterID: chen.id,
                durationSeconds: 6.0,
                preferredEngine: defaultEngine
            ),
            WuMindDramaShot(
                title: "第5镜·镜中倒影",
                cameraFraming: .closeUp,
                cameraMovement: "慢速拉焦",
                visualPrompt: "9:16 竖屏近景，监控室玻璃反光里女子缓缓回头，身后屏幕闪烁第二份值班日志，冷蓝霓虹映出微颤眼神",
                dialogue: "这份排班表，怎么多出来一张明天凌晨的签名？",
                characterID: lin.id,
                durationSeconds: 6.0,
                preferredEngine: defaultEngine
            ),
            WuMindDramaShot(
                title: "第6镜·反转黑屏",
                cameraFraming: .extremeCloseUp,
                cameraMovement: "急推定格",
                visualPrompt: "9:16 竖屏悬疑尾镜，铁门缝隙缓缓推开一道强白光，手机屏幕弹出新消息『欢迎回到第7次循环』，电影暗角收尾",
                dialogue: "倒计时重启——这一次，别再相信总控台。",
                characterID: chen.id,
                durationSeconds: 6.0,
                preferredEngine: defaultEngine
            ),
        ]

        return WuMindShortDramaProject(
            title: "深夜值班室的秘密",
            premise: "暴雨夜监控中心突然断联，值班长发现篡改日志的工号竟是巡检员，却在反光里看到明天的自己。",
            genre: .suspense,
            targetDurationSeconds: 36,
            characters: [lin, chen],
            shots: shots
        )
    }

    /// Composes the full video-API generation prompt for a single shot, binding framing, camera move, and character appearance.
    public static func composeGenerationPrompt(
        for shot: WuMindDramaShot,
        character: WuMindDramaCharacter?,
        project: WuMindShortDramaProject
    ) -> String {
        var segments: [String] = [
            "9:16 竖屏电影感短剧，题材：\(project.genre.rawValue)。",
            "景别要求：\(shot.cameraFraming.label)（\(shot.cameraFraming.promptDirective)）。",
            "运镜：\(shot.cameraMovement)。"
        ]
        if let character {
            segments.append("出镜角色「\(character.name)」固定外形：\(character.appearanceTag)。")
        }
        segments.append("画面内容：\(shot.visualPrompt)")
        if !shot.dialogue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append("人物表演与口型节奏需匹配台词氛围：「\(shot.dialogue)」（画面内不要自带文字水印）。")
        }
        return segments.joined(separator: " ")
    }

    public struct ReshootPlan: Equatable, Sendable {
        public let updatedFraming: WuMindDramaCameraFraming
        public let updatedVisualPrompt: String
        public let finalGenerationPrompt: String
        public let preservedDialogue: String
        public let preservedVoiceLabel: String?

        public init(
            updatedFraming: WuMindDramaCameraFraming,
            updatedVisualPrompt: String,
            finalGenerationPrompt: String,
            preservedDialogue: String,
            preservedVoiceLabel: String?
        ) {
            self.updatedFraming = updatedFraming
            self.updatedVisualPrompt = updatedVisualPrompt
            self.finalGenerationPrompt = finalGenerationPrompt
            self.preservedDialogue = preservedDialogue
            self.preservedVoiceLabel = preservedVoiceLabel
        }
    }

    /// Builds a selective single-shot reshoot plan (`「这一镜不好，只重拍这一镜」`).
    /// When `keepDialogueAndVoice == true`, dialogue & character voice assignment remain strictly locked.
    public static func composeReshootPrompt(
        shot: WuMindDramaShot,
        instruction: String,
        keepDialogueAndVoice: Bool,
        character: WuMindDramaCharacter?,
        project: WuMindShortDramaProject
    ) -> ReshootPlan {
        let cleanInst = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedFraming = WuMindDramaCameraFraming.detect(in: cleanInst) ?? shot.cameraFraming
        let mergedVisual: String
        if cleanInst.isEmpty {
            mergedVisual = shot.visualPrompt
        } else {
            mergedVisual = "\(shot.visualPrompt)；本次单镜重拍修改要求：\(cleanInst)"
        }

        var draftShot = shot
        draftShot.cameraFraming = detectedFraming
        draftShot.visualPrompt = mergedVisual
        var finalPrompt = composeGenerationPrompt(for: draftShot, character: character, project: project)
        if keepDialogueAndVoice {
            finalPrompt += " 保持原有台词节奏与角色情绪连贯，仅调整画面景别与构图表现。"
        }

        return ReshootPlan(
            updatedFraming: detectedFraming,
            updatedVisualPrompt: mergedVisual,
            finalGenerationPrompt: finalPrompt,
            preservedDialogue: shot.dialogue,
            preservedVoiceLabel: character?.voicePreset.displayName
        )
    }

    /// Commits a newly generated take onto ONLY the target shot.
    /// Previous takes are preserved verbatim for A/B comparison, and all other shots remain completely untouched.
    public static func applySingleShotTake(
        project: WuMindShortDramaProject,
        shotID: UUID,
        take: WuMindShotTake,
        updatedFraming: WuMindDramaCameraFraming? = nil,
        updatedVisualPrompt: String? = nil,
        updatedDialogue: String? = nil,
        keepDialogueAndVoice: Bool = true
    ) -> WuMindShortDramaProject {
        var next = project
        guard let idx = next.shots.firstIndex(where: { $0.id == shotID }) else {
            return next
        }
        var target = next.shots[idx]
        let wasAlreadyRendered = !target.takes.isEmpty

        if let updatedFraming {
            target.cameraFraming = updatedFraming
        }
        if let updatedVisualPrompt, !updatedVisualPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            target.visualPrompt = updatedVisualPrompt
        }
        if !keepDialogueAndVoice, let updatedDialogue {
            target.dialogue = updatedDialogue
            target.subtitleText = updatedDialogue
        }

        target.preferredEngine = take.engine
        target.takes.append(take)
        target.activeTakeID = take.id
        next.shots[idx] = target

        next.totalGenerations += 1
        if wasAlreadyRendered {
            next.singleShotReshoots += 1
        }
        next.estimatedTotalCostYuan = ((next.estimatedTotalCostYuan + take.estimatedCostYuan) * 100).rounded() / 100
        next.updatedAt = Date()
        return next
    }

    /// Switches the active take for a single shot (A/B comparison / instant rollback to previous take).
    public static func switchActiveTake(
        project: WuMindShortDramaProject,
        shotID: UUID,
        takeID: UUID
    ) -> WuMindShortDramaProject {
        var next = project
        guard let idx = next.shots.firstIndex(where: { $0.id == shotID }),
              next.shots[idx].takes.contains(where: { $0.id == takeID }) else {
            return next
        }
        next.shots[idx].activeTakeID = takeID
        next.updatedAt = Date()
        return next
    }

    /// Reorders shots along the timeline without disturbing takes, trims, or character assignments.
    public static func moveShot(
        project: WuMindShortDramaProject,
        fromIndex: Int,
        toIndex: Int
    ) -> WuMindShortDramaProject {
        var next = project
        guard fromIndex != toIndex,
              next.shots.indices.contains(fromIndex),
              next.shots.indices.contains(toIndex) else {
            return next
        }
        let item = next.shots.remove(at: fromIndex)
        next.shots.insert(item, at: toIndex)
        next.updatedAt = Date()
        return next
    }

    /// Updates a shot's trim in/out window safely (clamped within `[0, durationSeconds]`, minimum 1.0s).
    public static func updateTrim(
        project: WuMindShortDramaProject,
        shotID: UUID,
        trimStart: Double,
        trimEnd: Double
    ) -> WuMindShortDramaProject {
        var next = project
        guard let idx = next.shots.firstIndex(where: { $0.id == shotID }) else {
            return next
        }
        let dur = next.shots[idx].durationSeconds
        let clampedStart = max(0.0, min(dur - 1.0, trimStart))
        let clampedEnd = max(clampedStart + 1.0, min(dur, trimEnd))
        next.shots[idx].trimStartSeconds = (clampedStart * 10).rounded() / 10
        next.shots[idx].trimEndSeconds = (clampedEnd * 10).rounded() / 10
        next.updatedAt = Date()
        return next
    }

    public static func totalTrimmedDuration(for project: WuMindShortDramaProject) -> Double {
        let sum = project.shots.reduce(0.0) { $0 + $1.trimmedDuration }
        return (sum * 10).rounded() / 10
    }

    public static func renderedShotCount(for project: WuMindShortDramaProject) -> Int {
        project.shots.filter(\.isRendered).count
    }

    public static func exportKind(for project: WuMindShortDramaProject) -> WuMindDramaExportKind {
        let total = project.shots.count
        guard total > 0 else { return .roughCutPreview }
        return renderedShotCount(for: project) == total ? .finalMaster : .roughCutPreview
    }

    public static func estimatedRemainingCostYuan(for project: WuMindShortDramaProject) -> Double {
        let raw = project.shots.filter { !$0.isRendered }.reduce(0.0) { acc, shot in
            let plan = shot.preferredEngine.generationPlan(timelineSeconds: shot.durationSeconds)
            return acc + plan.estimatedCostYuan
        }
        return (raw * 100).rounded() / 100
    }

    /// Computes exact contiguous subtitle time cues aligned to trimmed shot windows.
    public static func subtitleCues(for project: WuMindShortDramaProject) -> [WuMindSubtitleCue] {
        guard project.globalSubtitlesEnabled else { return [] }
        var cues: [WuMindSubtitleCue] = []
        var cursor: Double = 0.0
        for (idx, shot) in project.shots.enumerated() {
            let dur = shot.trimmedDuration
            let start = cursor
            let end = cursor + dur
            cursor = end
            let text = shot.subtitleText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard shot.subtitleEnabled, !text.isEmpty else { continue }
            let speaker = project.character(for: shot)?.name
            cues.append(WuMindSubtitleCue(
                shotIndex: idx,
                speakerName: speaker,
                text: text,
                startSeconds: (start * 100).rounded() / 100,
                endSeconds: (end * 100).rounded() / 100
            ))
        }
        return cues
    }

    /// Honest warning when switching video generation engines across shots or takes of the same drama.
    public static func crossEngineConsistencyWarning(
        for project: WuMindShortDramaProject,
        shotID: UUID,
        targetEngine: WuMindDramaVideoEngine
    ) -> String? {
        let existingEngines = Set(project.shots.compactMap { $0.activeTake?.engine })
        guard !existingEngines.isEmpty, !existingEngines.contains(targetEngine) else {
            return nil
        }
        let others = existingEngines.map(\.shortBadge).sorted().joined(separator: " / ")
        return "当前其余镜头已使用 \(others) 生成，切换为 \(targetEngine.shortBadge) 后，即便携带角色参考图，也无法保证跨引擎人物脸部与画风完全一致。"
    }

    // MARK: - Private Parsing Helpers

    private struct RawDramaPayload: Decodable {
        struct RawCharacter: Decodable {
            let name: String?
            let roleSummary: String?
            let appearanceTag: String?
            let voice: String?
        }
        struct RawShot: Decodable {
            let title: String?
            let framing: String?
            let cameraMovement: String?
            let visualPrompt: String?
            let characterName: String?
            let dialogue: String?
            let durationSeconds: Double?
        }
        let title: String?
        let characters: [RawCharacter]?
        let shots: [RawShot]?
    }

    private static func extractJSONObject(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.firstIndex(of: "{"),
              let last = trimmed.lastIndex(of: "}"),
              first < last else {
            return trimmed
        }
        return String(trimmed[first...last])
    }

    private static func fallbackProject(
        premise: String,
        genre: WuMindDramaGenre,
        targetDurationSeconds: Int,
        defaultEngine: WuMindDramaVideoEngine
    ) -> WuMindShortDramaProject {
        let cleanPremise = premise.trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = cleanPremise.isEmpty ? "都市反转微短剧" : cleanPremise
        let shotCount = max(5, min(10, Int((Double(max(30, min(60, targetDurationSeconds))) / 6.0).rounded())))
        let lead = WuMindDramaCharacter(
            name: "主角A",
            roleSummary: "核心主角",
            appearanceTag: "30岁中国青年，利落深色外套，高质感电影写实风格",
            voicePreset: .brightFemale
        )
        let rival = WuMindDramaCharacter(
            name: "对手B",
            roleSummary: "关键对手",
            appearanceTag: "34岁中国男性，深灰大衣，克制冷峻眼神",
            voicePreset: .deepMale
        )
        let framings: [WuMindDramaCameraFraming] = [.wide, .medium, .closeUp, .medium, .extremeCloseUp, .closeUp]
        let beats = [
            "开场钩子 · 抛出核心冲突",
            "紧张推进 · 发现关键线索",
            "情绪升级 · 正面对峙交锋",
            "反转瞬间 · 揭示隐藏真相",
            "高潮爆发 · 做出最终抉择",
            "悬念尾镜 · 引出下一集"
        ]
        let shots: [WuMindDramaShot] = (0..<shotCount).map { i in
            let char = (i % 2 == 0) ? lead : rival
            let beat = beats[i % beats.count]
            let framing = framings[i % framings.count]
            return WuMindDramaShot(
                title: "第\(i + 1)镜·\(beat.components(separatedBy: " · ").first ?? "分镜")",
                cameraFraming: framing,
                cameraMovement: i % 2 == 0 ? "缓推运镜" : "手持微晃跟拍",
                visualPrompt: "9:16 竖屏电影感画面，\(genre.rawValue)氛围，围绕「\(topic)」展开：\(beat)",
                dialogue: "第\(i + 1)镜台词（点击可精修）：围绕「\(String(topic.prefix(16)))」推进冲突。",
                characterID: char.id,
                durationSeconds: 6.0,
                preferredEngine: defaultEngine
            )
        }
        return WuMindShortDramaProject(
            title: String(topic.prefix(12)),
            premise: topic,
            genre: genre,
            targetDurationSeconds: targetDurationSeconds,
            characters: [lead, rival],
            shots: shots
        )
    }
}
