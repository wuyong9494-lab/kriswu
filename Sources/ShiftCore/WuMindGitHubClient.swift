import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Direct GitHub REST API client (`https://api.github.com`) for connecting repositories
/// into WUMIND chat context. Supports both anonymous public repository browsing and
/// optional user-configured Personal Access Tokens (stored device-only in iOS Keychain).
public struct WuMindGitHubClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public struct RepoSummary: Codable, Identifiable, Equatable, Sendable {
        public let fullName: String
        public let description: String
        public let defaultBranch: String
        public let language: String
        public let isPrivate: Bool
        public let stars: Int
        public let htmlURL: String

        public var id: String { fullName }

        public init(fullName: String, description: String = "", defaultBranch: String = "main",
                    language: String = "", isPrivate: Bool = false, stars: Int = 0, htmlURL: String = "") {
            self.fullName = fullName
            self.description = description
            self.defaultBranch = defaultBranch
            self.language = language
            self.isPrivate = isPrivate
            self.stars = stars
            self.htmlURL = htmlURL
        }
    }

    public struct AttachedFile: Codable, Identifiable, Equatable, Sendable {
        public let path: String
        public let content: String
        public var id: String { path }

        public init(path: String, content: String) {
            self.path = path
            self.content = content
        }
    }

    public struct RepoContext: Codable, Equatable, Sendable {
        public let repo: RepoSummary
        public let readmeExcerpt: String
        public let filePaths: [String]
        public let recentCommits: [String]
        public var attachedFiles: [AttachedFile]

        public init(repo: RepoSummary, readmeExcerpt: String = "", filePaths: [String] = [],
                    recentCommits: [String] = [], attachedFiles: [AttachedFile] = []) {
            self.repo = repo
            self.readmeExcerpt = readmeExcerpt
            self.filePaths = filePaths
            self.recentCommits = recentCommits
            self.attachedFiles = attachedFiles
        }

        /// Formats bounded repository metadata, README, tree, commits, and selected files for AI context.
        public func formattedPromptContext(maxBytes: Int = 18_000) -> String {
            var parts: [String] = []
            parts.append("""
            [已连接的 GitHub 仓库上下文]
            仓库: \(repo.fullName)（默认分支: \(repo.defaultBranch)，主语言: \(repo.language.isEmpty ? "未知" : repo.language)，Stars: \(repo.stars)）
            简介: \(repo.description.isEmpty ? "无" : repo.description)
            """)
            if !recentCommits.isEmpty {
                parts.append("最近提交:\n" + recentCommits.prefix(8).map { "- \($0)" }.joined(separator: "\n"))
            }
            if !filePaths.isEmpty {
                let listing = filePaths.prefix(100).joined(separator: "\n")
                parts.append("仓库文件目录（节选）:\n\(listing)")
            }
            if !readmeExcerpt.isEmpty {
                parts.append("README 摘要:\n\(String(readmeExcerpt.prefix(3500)))")
            }
            for file in attachedFiles {
                parts.append("已附加源码文件 `\(file.path)`:\n```\n\(String(file.content.prefix(5000)))\n```")
            }
            let joined = parts.joined(separator: "\n\n")
            if joined.utf8.count <= maxBytes { return joined }
            return String(joined.prefix(maxBytes / 2)) + "\n\n[上下文已按长度安全截断]"
        }
    }

    public enum GitHubError: LocalizedError, Equatable, Sendable {
        case invalidRepo
        case invalidToken
        case unauthorized
        case notFound
        case rateLimited
        case fileTooLarge
        case network
        case invalidResponse

        public var errorDescription: String? {
            switch self {
            case .invalidRepo: return "仓库格式不正确，请填写 owner/repo 或完整的 github.com 仓库链接。"
            case .invalidToken: return "GitHub Token 格式不正确，请粘贴纯 Token（勿含空格或换行）。"
            case .unauthorized: return "GitHub 拒绝了凭据（401/403），请检查 Token 权限或仓库访问范围。"
            case .notFound: return "未找到该 GitHub 仓库或文件（私有仓库需先配置 GitHub Token）。"
            case .rateLimited: return "已触发 GitHub API 速率限制，请配置 GitHub Token 或稍后重试。"
            case .fileTooLarge: return "文件过大或为二进制文件，暂不支持直接附加为文字上下文。"
            case .network: return "无法连接 api.github.com，请检查网络。"
            case .invalidResponse: return "无法解析 GitHub 返回的数据。"
            }
        }
    }

    private let transport: Transport

    public init() {
        self.transport = { request in
            try await GitHubSessionPool.shared.data(for: request)
        }
    }

    public init(transport: @escaping Transport) {
        self.transport = transport
    }

    /// Parses `"owner/repo"`, `"https://github.com/owner/repo"`, `"github.com/owner/repo/tree/main"`, etc.
    public static func parseRepoIdentifier(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        for prefix in ["https://github.com/", "http://github.com/", "github.com/"] {
            if text.lowercased().hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
                break
            }
        }
        while text.hasPrefix("/") { text.removeFirst() }
        let parts = text.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        var repo = parts[1]
        if repo.hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        guard isSafeSegment(owner), isSafeSegment(repo) else { return nil }
        return "\(owner)/\(repo)"
    }

    /// Detects the first `github.com/owner/repo` link in a prompt string, if any.
    public static func detectRepoInText(_ text: String) -> String? {
        let pattern = #"(?:https?://)?github\.com/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r1 = Range(match.range(at: 1), in: text),
              let r2 = Range(match.range(at: 2), in: text) else {
            return nil
        }
        let owner = String(text[r1])
        var repo = String(text[r2])
        if repo.hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        guard isSafeSegment(owner), isSafeSegment(repo) else { return nil }
        return "\(owner)/\(repo)"
    }

    public func listUserRepos(token: String) async throws -> [RepoSummary] {
        let cleanToken = MultiProviderAIClient.sanitizePastedKey(token)
        guard !cleanToken.isEmpty else { throw GitHubError.invalidToken }
        let wire: [WireRepo] = try await fetchJSON(
            path: "/user/repos",
            query: [
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "per_page", value: "30")
            ],
            token: cleanToken
        )
        return wire.map { $0.summary }
    }

    public func fetchRepoContext(fullName raw: String, token: String?) async throws -> RepoContext {
        guard let fullName = Self.parseRepoIdentifier(raw) else { throw GitHubError.invalidRepo }
        let wireRepo: WireRepo = try await fetchJSON(path: "/repos/\(fullName)", token: token)
        let summary = wireRepo.summary

        async let readmeTask: WireContent? = try? await fetchJSON(path: "/repos/\(fullName)/readme", token: token)
        async let treeTask: WireTree? = try? await fetchJSON(
            path: "/repos/\(fullName)/git/trees/\(summary.defaultBranch)",
            query: [URLQueryItem(name: "recursive", value: "1")],
            token: token
        )
        async let commitsTask: [WireCommit]? = try? await fetchJSON(
            path: "/repos/\(fullName)/commits",
            query: [URLQueryItem(name: "per_page", value: "8")],
            token: token
        )

        let (readmeObj, treeObj, commitsObj) = await (readmeTask, treeTask, commitsTask)
        let readmeText: String = {
            guard let b64 = readmeObj?.content else { return "" }
            let cleaned = b64.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
            guard let data = Data(base64Encoded: cleaned), let str = String(data: data, encoding: .utf8) else { return "" }
            return String(str.prefix(4000))
        }()

        let filePaths: [String] = (treeObj?.tree ?? [])
            .filter { $0.type == "blob" }
            .map(\.path)
            .prefix(200)
            .map { $0 }

        let commits: [String] = (commitsObj ?? []).compactMap { c in
            let msg = c.commit.message.split(separator: "\n").first.map(String.init) ?? ""
            let shortSHA = String(c.sha.prefix(7))
            return msg.isEmpty ? nil : "\(shortSHA) \(msg)"
        }

        return RepoContext(
            repo: summary,
            readmeExcerpt: readmeText,
            filePaths: filePaths,
            recentCommits: commits,
            attachedFiles: []
        )
    }

    public func fetchFileContent(fullName raw: String, path: String, ref: String?, token: String?) async throws -> AttachedFile {
        guard let fullName = Self.parseRepoIdentifier(raw) else { throw GitHubError.invalidRepo }
        let segments = path.split(separator: "/").map(String.init)
        guard !segments.isEmpty, segments.allSatisfy({ $0 != "." && $0 != ".." }) else {
            throw GitHubError.invalidRepo
        }
        let encodedPath = segments.compactMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }.joined(separator: "/")
        let query = ref.flatMap { $0.isEmpty ? nil : [URLQueryItem(name: "ref", value: $0)] } ?? []
        let obj: WireContent = try await fetchJSON(path: "/repos/\(fullName)/contents/\(encodedPath)", query: query, token: token)
        guard let b64 = obj.content, (obj.size ?? 0) <= 200_000 else { throw GitHubError.fileTooLarge }
        let cleaned = b64.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
        guard let data = Data(base64Encoded: cleaned), let text = String(data: data, encoding: .utf8) else {
            throw GitHubError.fileTooLarge
        }
        return AttachedFile(path: path, content: String(text.prefix(12_000)))
    }

    private func fetchJSON<T: Decodable>(path: String, query: [URLQueryItem] = [], token: String?) async throws -> T {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "api.github.com"
        comps.path = path
        comps.queryItems = query.isEmpty ? nil : query
        guard let url = comps.url else { throw GitHubError.invalidRepo }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("WUMIND-iOS", forHTTPHeaderField: "User-Agent")
        if let rawToken = token {
            let clean = MultiProviderAIClient.sanitizePastedKey(rawToken)
            if !clean.isEmpty {
                guard clean.utf8.allSatisfy({ (33...126).contains($0) }) else { throw GitHubError.invalidToken }
                req.setValue("Bearer \(clean)", forHTTPHeaderField: "Authorization")
            }
        }

        let result: (Data, URLResponse)
        do {
            try Task.checkCancellation()
            result = try await transport(req)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GitHubError.network
        }

        guard let http = result.1 as? HTTPURLResponse else { throw GitHubError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            guard result.0.count <= 4 * 1024 * 1024,
                  let decoded = try? JSONDecoder().decode(T.self, from: result.0) else {
                throw GitHubError.invalidResponse
            }
            return decoded
        case 401:
            throw GitHubError.unauthorized
        case 403:
            if http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                throw GitHubError.rateLimited
            }
            throw GitHubError.unauthorized
        case 404:
            throw GitHubError.notFound
        case 429:
            throw GitHubError.rateLimited
        default:
            throw GitHubError.invalidResponse
        }
    }

    private static func isSafeSegment(_ seg: String) -> Bool {
        guard !seg.isEmpty, seg != ".", seg != ".." else { return false }
        return seg.utf8.allSatisfy { b in
            (48...57).contains(b) || (65...90).contains(b) || (97...122).contains(b)
                || b == 45 || b == 95 || b == 46
        }
    }
}

private final class GitHubBlockRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private enum GitHubSessionPool {
    static let shared: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForResource = 45
        return URLSession(configuration: config, delegate: GitHubBlockRedirects(), delegateQueue: nil)
    }()
}

private struct WireRepo: Decodable {
    let fullName: String
    let description: String?
    let defaultBranch: String?
    let language: String?
    let isPrivate: Bool?
    let stargazersCount: Int?
    let htmlURL: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case description
        case defaultBranch = "default_branch"
        case language
        case isPrivate = "private"
        case stargazersCount = "stargazers_count"
        case htmlURL = "html_url"
    }

    var summary: WuMindGitHubClient.RepoSummary {
        WuMindGitHubClient.RepoSummary(
            fullName: fullName,
            description: description ?? "",
            defaultBranch: defaultBranch ?? "main",
            language: language ?? "",
            isPrivate: isPrivate ?? false,
            stars: stargazersCount ?? 0,
            htmlURL: htmlURL ?? "https://github.com/\(fullName)"
        )
    }
}

private struct WireContent: Decodable {
    let content: String?
    let size: Int?
}

private struct WireTree: Decodable {
    struct Entry: Decodable {
        let path: String
        let type: String
    }
    let tree: [Entry]
}

private struct WireCommit: Decodable {
    struct CommitDetail: Decodable {
        let message: String
    }
    let sha: String
    let commit: CommitDetail
}
