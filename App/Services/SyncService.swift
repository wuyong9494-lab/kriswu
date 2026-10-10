import Foundation
import BackgroundTasks

enum SyncError: LocalizedError {
    case badURL
    case http(Int)
    case needsLogin
    case undecodable

    var errorDescription: String? {
        switch self {
        case .badURL: return "网址不正确"
        case .http(let code): return "服务器返回错误 \(code)"
        case .needsLogin: return "登录已过期，自动登录没成功：请检查「设置 › 自动同步」里的账号密码；网站要验证码时，在「网页登录」里手动登录一次"
        case .undecodable: return "无法识别返回的内容"
        }
    }
}

enum SyncService {
    struct Outcome {
        var result: ParseResult
        /// 这次用上的数据接口（下次优先用它）；读网页内容时为 nil
        var apiSignature: String?
    }

    /// 取回排班。
    /// viaWeb = true：在内置浏览器里打开排班页面（自动登录）。能认出网页背后的数据接口时，
    /// 直接用这个接口再取后面 weeksAhead 周的数据；认不出就照旧读网页上显示的内容。
    /// viaWeb = false：直接下载（CSV / ICS 日历订阅 / JSON 文件）。
    @MainActor
    static func fetchSchedule(urlString: String, username: String, password: String, viaWeb: Bool,
                              parser: ScheduleParser, aliases: [String], matcher: ShiftMatcher,
                              preferredAPI: String?, weeksAhead: Int = 3) async throws -> Outcome {
        if viaWeb, let url = webURL(urlString) {
            let reference = parser.reference
            var found: APIDiscovery.Found?
            let page = try await WebPageLoader.load(url: url, username: username, password: password) { captured in
                found = APIDiscovery.find(in: captured, preferred: preferredAPI, aliases: aliases,
                                          matcher: matcher, reference: reference)
                guard let f = found, f.request.hasDateParameter, weeksAhead > 0 else { return [] }
                return (1...weeksAhead).map { f.request.shifted(days: 7 * $0) }
            }
            if let f = found, !f.entries.isEmpty {
                var entries = f.entries
                for reply in page.replies {
                    let more = JSONScheduleExtractor.extract(reply, aliases: aliases, matcher: matcher, reference: reference)
                    for (day, value) in more where entries[day] == nil { entries[day] = value }
                }
                return Outcome(result: ParseResult(entries: entries, format: .api), apiSignature: f.request.signature)
            }
            if HTMLText.looksLikeLoginPage(page.html) { throw SyncError.needsLogin }
            return Outcome(result: try parser.parse(HTMLText.toText(page.html)), apiSignature: nil)
        }
        let text = try await fetchText(urlString: urlString, username: username, password: password)
        return Outcome(result: try parser.parse(text), apiSignature: nil)
    }

    private static func webURL(_ urlString: String) -> URL? {
        let s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    /// 直接下载排班文件并转成文字（网页会先转换成表格文字）。
    static func fetchText(urlString: String, username: String, password: String) async throws -> String {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("webcal://") { s = "https://" + s.dropFirst("webcal://".count) }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw SyncError.badURL
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        if !username.isEmpty {
            let token = Data("\(username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 { throw SyncError.needsLogin }
            guard (200..<300).contains(http.statusCode) else { throw SyncError.http(http.statusCode) }
        }
        guard let text = decode(data) else { throw SyncError.undecodable }

        if HTMLText.looksLikeHTML(text) {
            if HTMLText.looksLikeLoginPage(text) { throw SyncError.needsLogin }
            return HTMLText.toText(text)
        }
        return text
    }

    /// 先按 UTF-8 解码，失败再试 GB18030（很多国内系统导出的 CSV 是这个编码）。
    static func decode(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: gb))
    }
}

enum BackgroundRefresh {
    static let identifier = "com.kriswu.shiftreminder.refresh"

    /// 请求系统找机会在后台刷新排班（最早 1 小时后，或下一次要发微信提醒的时间，取较早者）。
    /// 具体何时执行由 iOS 根据使用习惯决定。
    static func schedule(notBefore next: Date? = nil) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        let hour = Date(timeIntervalSinceNow: 3600)
        request.earliestBeginDate = next.map { min($0, hour) } ?? hour
        try? BGTaskScheduler.shared.submit(request)
    }
}
