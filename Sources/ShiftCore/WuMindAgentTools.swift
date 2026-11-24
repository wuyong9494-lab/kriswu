import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Live executable tool runners for the WUMIND Multi-Step Agent Engine.
/// All external network calls enforce strict HTTPS, reject local/private hosts (SSRF protection),
/// reject redirects cleanly, and bound output sizes for predictable token metering.
public enum WuMindAgentTools {
    public typealias DataTransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    public struct ToolResult: Equatable, Sendable {
        public let succeeded: Bool
        public let summary: String
        public let observationText: String
        public let extraCostYuan: Double

        public init(succeeded: Bool, summary: String, observationText: String, extraCostYuan: Double = 0) {
            self.succeeded = succeeded
            self.summary = summary
            self.observationText = observationText
            self.extraCostYuan = extraCostYuan
        }
    }

    // MARK: - 0. Live Web Search & Deep Research (Own API: Tavily / Brave / DuckDuckGo Fallback)

    public static func formatSearchObservation(query: String, provider: String, results: [WuMindWebSearchResult]) -> String {
        guard !results.isEmpty else {
            return "【联网搜索：\(query)（\(provider)）】未找到直接匹配结果，请尝试更换更精准的关键词。"
        }
        var lines: [String] = ["【联网搜索：\(query)（来源：\(provider)，共 \(results.count) 条）】"]
        for (idx, item) in results.enumerated() {
            var block = "\(idx + 1). \(item.title)\n   链接：\(item.url)"
            if let pub = item.publishedDate, !pub.isEmpty {
                block += "\n   日期：\(pub)"
            }
            if !item.snippet.isEmpty {
                block += "\n   摘要：\(item.snippet)"
            }
            lines.append(block)
        }
        lines.append("（如需深入核实某条来源正文，可继续调用 web_fetch 读取对应链接。）")
        return lines.joined(separator: "\n")
    }

    public static func directWebSearch(
        query: String,
        maxResults: Int = 5,
        depth: String = "basic",
        tavilyKey: String? = nil,
        braveKey: String? = nil,
        transport: DataTransport? = nil
    ) async -> ToolResult {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else {
            return ToolResult(succeeded: false, summary: "搜索关键词为空", observationText: "请提供非空搜索关键词 query。")
        }
        let cappedMax = min(8, max(1, maxResults))

        // 1. Tavily Search API (if user configured a personal Tavily key)
        if let tk = tavilyKey?.trimmingCharacters(in: .whitespacesAndNewlines), !tk.isEmpty,
           let url = URL(string: "https://api.tavily.com/search") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 20
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let bodyObj: [String: Any] = [
                "api_key": tk,
                "query": cleanQuery,
                "search_depth": depth == "advanced" ? "advanced" : "basic",
                "max_results": cappedMax,
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: bodyObj)
            if let (data, http) = try? await runTransport(req, transport: transport), (200...299).contains(http.statusCode),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rawResults = obj["results"] as? [[String: Any]] {
                let items = rawResults.prefix(cappedMax).compactMap { r -> WuMindWebSearchResult? in
                    guard let title = r["title"] as? String, let u = r["url"] as? String else { return nil }
                    return WuMindWebSearchResult(
                        title: title,
                        url: u,
                        snippet: String((r["content"] as? String ?? "").prefix(420)),
                        publishedDate: r["published_date"] as? String
                    )
                }
                return ToolResult(
                    succeeded: true,
                    summary: "Tavily 搜得 \(items.count) 条",
                    observationText: formatSearchObservation(query: cleanQuery, provider: "Tavily", results: items)
                )
            }
        }

        // 2. Brave Search API (if user configured a personal Brave key)
        if let bk = braveKey?.trimmingCharacters(in: .whitespacesAndNewlines), !bk.isEmpty,
           var comps = URLComponents(string: "https://api.search.brave.com/res/v1/web/search") {
            comps.queryItems = [
                URLQueryItem(name: "q", value: cleanQuery),
                URLQueryItem(name: "count", value: "\(cappedMax)")
            ]
            if let url = comps.url {
                var req = URLRequest(url: url)
                req.httpMethod = "GET"
                req.timeoutInterval = 20
                req.setValue(bk, forHTTPHeaderField: "X-Subscription-Token")
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                if let (data, http) = try? await runTransport(req, transport: transport), (200...299).contains(http.statusCode),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let web = obj["web"] as? [String: Any],
                   let rawResults = web["results"] as? [[String: Any]] {
                    let items = rawResults.prefix(cappedMax).compactMap { r -> WuMindWebSearchResult? in
                        guard let title = r["title"] as? String, let u = r["url"] as? String else { return nil }
                        return WuMindWebSearchResult(
                            title: title,
                            url: u,
                            snippet: String((r["description"] as? String ?? "").prefix(420)),
                            publishedDate: r["age"] as? String
                        )
                    }
                    return ToolResult(
                        succeeded: true,
                        summary: "Brave 搜得 \(items.count) 条",
                        observationText: formatSearchObservation(query: cleanQuery, provider: "Brave", results: items)
                    )
                }
            }
        }

        // 3. Zero-key public DuckDuckGo HTML search fallback
        guard var comps = URLComponents(string: "https://html.duckduckgo.com/html/") else {
            return ToolResult(succeeded: false, summary: "搜索地址构造失败", observationText: "无法构造搜索请求。")
        }
        comps.queryItems = [URLQueryItem(name: "q", value: cleanQuery)]
        guard let ddgURL = comps.url else {
            return ToolResult(succeeded: false, summary: "搜索地址无效", observationText: "无法编码搜索关键词。")
        }
        var req = URLRequest(url: ddgURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 18
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        do {
            let (data, http) = try await runTransport(req, transport: transport)
            guard (200...299).contains(http.statusCode) else {
                return ToolResult(succeeded: false, summary: "搜索受限（HTTP \(http.statusCode)）", observationText: "公开搜索返回 HTTP \(http.statusCode)，建议切换至 WUMIND 内置通道或在定制中心配置 Tavily/Brave Key。")
            }
            let html = String(decoding: data.prefix(350_000), as: UTF8.self)
            let parsed = parseDuckDuckGoHTML(html, limit: cappedMax)
            return ToolResult(
                succeeded: !parsed.isEmpty,
                summary: parsed.isEmpty ? "未搜到结果" : "联网搜得 \(parsed.count) 条",
                observationText: formatSearchObservation(query: cleanQuery, provider: "DuckDuckGo", results: parsed)
            )
        } catch {
            return ToolResult(succeeded: false, summary: "联网搜索失败", observationText: "无法连接搜索服务（\(error.localizedDescription)）。")
        }
    }

    private static func runTransport(_ request: URLRequest, transport: DataTransport?) async throws -> (Data, HTTPURLResponse) {
        if let transport { return try await transport(request) }
        return try await performSafeRequest(request)
    }

    public static func parseDuckDuckGoHTML(_ html: String, limit: Int) -> [WuMindWebSearchResult] {
        // Matches result__a anchors and nearby result__snippet blocks in DuckDuckGo lite HTML.
        let linkPattern = #"<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>"#
        let snippetPattern = #"class="[^"]*result__snippet[^"]*"[^>]*>([\s\S]*?)</(?:a|div|span)>"#
        guard let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive]),
              let snippetRegex = try? NSRegularExpression(pattern: snippetPattern, options: [.caseInsensitive]) else {
            return []
        }
        let ns = html as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let linkMatches = linkRegex.matches(in: html, range: fullRange)
        let snippetMatches = snippetRegex.matches(in: html, range: fullRange)

        var out: [WuMindWebSearchResult] = []
        for (idx, match) in linkMatches.prefix(limit).enumerated() {
            guard match.numberOfRanges >= 3 else { continue }
            var rawURL = ns.substring(with: match.range(at: 1))
                .replacingOccurrences(of: "&amp;", with: "&")
            if rawURL.hasPrefix("//") { rawURL = "https:" + rawURL }
            if let comps = URLComponents(string: rawURL),
               let uddg = comps.queryItems?.first(where: { $0.name == "uddg" })?.value,
               !uddg.isEmpty {
                rawURL = uddg
            }
            let title = stripHTML(ns.substring(with: match.range(at: 2)))
            let snippet: String = idx < snippetMatches.count && snippetMatches[idx].numberOfRanges >= 2
                ? stripHTML(ns.substring(with: snippetMatches[idx].range(at: 1)))
                : ""
            if !title.isEmpty && rawURL.hasPrefix("http") {
                out.append(WuMindWebSearchResult(title: title, url: rawURL, snippet: String(snippet.prefix(380))))
            }
        }
        return out
    }

    // MARK: - 1. Safe HTTPS Web Fetch (with SSRF Guard & HTML Stripping)

    public static func validateExternalHTTPSURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        // Reject localhost, loopback, link-local, and RFC1918 private addresses
        if host == "localhost"
            || host.hasSuffix(".local")
            || host.hasPrefix("127.")
            || host.hasPrefix("10.")
            || host.hasPrefix("192.168.")
            || host.hasPrefix("169.254.")
            || host == "::1"
            || host.hasPrefix("fc")
            || host.hasPrefix("fd") {
            return nil
        }
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return nil
            }
        }
        return url
    }

    public static func webFetch(
        urlString: String,
        maxChars: Int = 18_000,
        transport: DataTransport? = nil
    ) async -> ToolResult {
        guard let url = validateExternalHTTPSURL(urlString) else {
            return ToolResult(
                succeeded: false,
                summary: "拒绝不安全链接",
                observationText: "错误：仅支持抓取公开的 HTTPS 网页地址（已拦截非 HTTPS 或内网地址）。"
            )
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 18
        req.setValue("WUMIND-Agent/1.2 (+https://github.com/wuyong9494-lab/kriswu)", forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,text/plain,application/json;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")

        do {
            let (data, http): (Data, HTTPURLResponse)
            if let transport {
                (data, http) = try await transport(req)
            } else {
                (data, http) = try await performSafeRequest(req)
            }
            guard (200...299).contains(http.statusCode) else {
                return ToolResult(
                    succeeded: false,
                    summary: "HTTP \(http.statusCode)",
                    observationText: "网页返回状态码 HTTP \(http.statusCode)，无法读取正文。"
                )
            }
            let capped = data.prefix(400_000)
            let rawText = String(data: capped, encoding: .utf8) ?? String(decoding: capped, as: UTF8.self)
            let clean = stripHTML(rawText)
            let bounded = clean.count > maxChars ? String(clean.prefix(maxChars)) + "\n…（已按上下文预算截断）" : clean
            guard !bounded.isEmpty else {
                return ToolResult(succeeded: false, summary: "页面无可读文字", observationText: "页面返回内容为空或为纯脚本渲染页。")
            }
            return ToolResult(
                succeeded: true,
                summary: "已读取 \(url.host ?? "网页")（\(bounded.count) 字）",
                observationText: "【网页抓取结果：\(url.absoluteString)】\n\(bounded)"
            )
        } catch {
            return ToolResult(
                succeeded: false,
                summary: "网页抓取超时或失败",
                observationText: "抓取 \(url.absoluteString) 失败，请确认网络或换用其他来源。"
            )
        }
    }

    public static func stripHTML(_ html: String) -> String {
        var text = html
        // Remove <script> and <style> blocks
        let removablePatterns = [
            "(?is)<script[^>]*>.*?</script>",
            "(?is)<style[^>]*>.*?</style>",
            "(?is)<noscript[^>]*>.*?</noscript>",
            "(?is)<!--.*?-->"
        ]
        for pattern in removablePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
            }
        }
        // Preserve basic paragraph breaks for block tags
        for tag in ["</p>", "</div>", "</li>", "<br>", "<br/>", "<br />", "</h1>", "</h2>", "</h3>", "</tr>"] {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>") {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            text = tagRegex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
        }
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'")
        ]
        for (k, v) in entities {
            text = text.replacingOccurrences(of: k, with: v)
        }
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    // MARK: - 2. Project Knowledge Base Search

    public static func searchProjectKnowledge(query: String, docs: [WuMindProjectDoc], maxChars: Int = 12_000) -> ToolResult {
        let terms = query
            .lowercased()
            .split { $0.isWhitespace || $0 == "," || $0 == "，" || $0 == "、" }
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !docs.isEmpty else {
            return ToolResult(succeeded: false, summary: "当前项目暂无知识库文件", observationText: "当前对话未绑定含文档的项目空间。")
        }
        guard !terms.isEmpty else {
            let names = docs.map { "- \($0.filename)（\($0.summaryBadge)）" }.joined(separator: "\n")
            return ToolResult(succeeded: true, summary: "列出 \(docs.count) 份项目文档", observationText: "项目文档清单：\n\(names)")
        }

        var scored: [(score: Int, filename: String, snippet: String)] = []
        for doc in docs {
            let paragraphs = doc.extractedText.components(separatedBy: "\n\n")
            for para in paragraphs {
                let lower = para.lowercased()
                var score = 0
                for term in terms where lower.contains(term) {
                    score += 1
                }
                if score > 0 {
                    let clean = para.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty {
                        scored.append((score, doc.filename, String(clean.prefix(1_200))))
                    }
                }
            }
        }
        scored.sort { $0.score > $1.score }
        guard !scored.isEmpty else {
            return ToolResult(succeeded: true, summary: "未命中关键词", observationText: "在 \(docs.count) 份项目文档中未找到与「\(query)」直接匹配的段落。")
        }
        var out: [String] = []
        var used = 0
        for item in scored.prefix(10) {
            let block = "[\(item.filename)]\n\(item.snippet)"
            if used + block.count > maxChars { break }
            out.append(block)
            used += block.count
        }
        return ToolResult(
            succeeded: true,
            summary: "命中 \(out.count) 处项目文档片段",
            observationText: "【项目知识库检索结果：\(query)】\n\n" + out.joined(separator: "\n\n---\n\n")
        )
    }

    // MARK: - 3. Exact Arithmetic Calculator (Recursive-Descent Parser)

    public static func evaluateMathExpression(_ expression: String) -> ToolResult {
        let cleaned = expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 256 else {
            return ToolResult(succeeded: false, summary: "表达式无效", observationText: "表达式为空或过长。")
        }
        var parser = MathParser(cleaned)
        guard let value = parser.parseExpression(), parser.isAtEnd, value.isFinite else {
            return ToolResult(succeeded: false, summary: "无法解析表达式", observationText: "仅支持数字与 + - * / ^ % ( ) 运算符。")
        }
        let formatted: String = {
            if abs(value.rounded() - value) < 1e-10 && abs(value) < 1e15 {
                return String(Int64(value.rounded()))
            }
            return String(format: "%.6f", value).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
        }()
        return ToolResult(
            succeeded: true,
            summary: "\(cleaned) = \(formatted)",
            observationText: "精确计算结果：\(cleaned) = \(formatted)"
        )
    }

    // MARK: - 4. Custom HTTPS Webhook / MCP Bridge Call

    public static func callCustomWebhook(
        endpointURL: String,
        authToken: String?,
        action: String,
        payload: String,
        transport: DataTransport? = nil
    ) async -> ToolResult {
        guard let url = validateExternalHTTPSURL(endpointURL) else {
            return ToolResult(
                succeeded: false,
                summary: "未配置有效 HTTPS 端点",
                observationText: "请先在「定制中心」中为该连接器配置公开的 HTTPS Webhook / MCP 桥接地址。"
            )
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let bodyObj: [String: String] = ["action": action, "payload": payload]
        req.httpBody = try? JSONEncoder().encode(bodyObj)

        do {
            let (data, http): (Data, HTTPURLResponse)
            if let transport {
                (data, http) = try await transport(req)
            } else {
                (data, http) = try await performSafeRequest(req)
            }
            let text = String(data: data.prefix(24_000), encoding: .utf8) ?? ""
            guard (200...299).contains(http.statusCode) else {
                return ToolResult(
                    succeeded: false,
                    summary: "桥接端点 HTTP \(http.statusCode)",
                    observationText: "自定义端点返回 HTTP \(http.statusCode)：\(String(text.prefix(400)))"
                )
            }
            return ToolResult(
                succeeded: true,
                summary: "已调用 \(url.host ?? "端点")（\(action)）",
                observationText: "【Webhook / MCP 返回】\n\(String(text.prefix(12_000)))"
            )
        } catch {
            return ToolResult(
                succeeded: false,
                summary: "桥接调用失败",
                observationText: "调用自定义端点 \(url.host ?? "") 失败，请检查地址与网络连通性。"
            )
        }
    }

    // MARK: - Safe Ephemeral Transport

    private static func performSafeRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false
        cfg.httpCookieStorage = nil
        cfg.urlCache = nil
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        let session = URLSession(configuration: cfg, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    private final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    // MARK: - Recursive-Descent Math Parser

    private struct MathParser {
        let chars: [Character]
        var index = 0

        init(_ s: String) {
            self.chars = Array(s)
        }

        var isAtEnd: Bool {
            var i = index
            while i < chars.count && chars[i].isWhitespace {
                i += 1
            }
            return i >= chars.count
        }

        private mutating func skipWhitespace() {
            while index < chars.count && chars[index].isWhitespace {
                index += 1
            }
        }

        private mutating func peek() -> Character? {
            skipWhitespace()
            return index < chars.count ? chars[index] : nil
        }

        mutating func parseExpression() -> Double? {
            guard var lhs = parseTerm() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                index += 1
                guard let rhs = parseTerm() else { return nil }
                lhs = op == "+" ? lhs + rhs : lhs - rhs
            }
            return lhs
        }

        private mutating func parseTerm() -> Double? {
            guard var lhs = parsePower() else { return nil }
            while let op = peek(), op == "*" || op == "/" || op == "%" {
                index += 1
                guard let rhs = parsePower() else { return nil }
                if op == "*" { lhs *= rhs }
                else if op == "/" {
                    guard rhs != 0 else { return nil }
                    lhs /= rhs
                } else {
                    guard rhs != 0 else { return nil }
                    lhs = lhs.truncatingRemainder(dividingBy: rhs)
                }
            }
            return lhs
        }

        private mutating func parsePower() -> Double? {
            guard var base = parseUnary() else { return nil }
            if peek() == "^" {
                index += 1
                guard let exp = parsePower() else { return nil }
                base = pow(base, exp)
            }
            return base
        }

        private mutating func parseUnary() -> Double? {
            if peek() == "+" {
                index += 1
                return parseUnary()
            }
            if peek() == "-" {
                index += 1
                guard let v = parseUnary() else { return nil }
                return -v
            }
            return parsePrimary()
        }

        private mutating func parsePrimary() -> Double? {
            skipWhitespace()
            guard index < chars.count else { return nil }
            if chars[index] == "(" {
                index += 1
                guard let v = parseExpression(), peek() == ")" else { return nil }
                index += 1
                return v
            }
            let start = index
            var sawDot = false
            while index < chars.count {
                let c = chars[index]
                if c.isNumber {
                    index += 1
                } else if c == "." && !sawDot {
                    sawDot = true
                    index += 1
                } else {
                    break
                }
            }
            guard index > start else { return nil }
            return Double(String(chars[start..<index]))
        }
    }
}
