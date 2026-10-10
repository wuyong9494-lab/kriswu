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
    /// 取回排班数据并转成文字。
    /// viaWeb = true 时用 App 内置浏览器打开（沿用「网页登录」的登录状态，支持动态网页）；
    /// 否则直接下载（适合 CSV / ICS 日历订阅 / JSON 文件）。
    @MainActor
    static func fetchText(urlString: String, username: String, password: String, viaWeb: Bool) async throws -> String {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("webcal://") { s = "https://" + s.dropFirst("webcal://".count) }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw SyncError.badURL
        }

        if viaWeb {
            let html = try await WebPageLoader.html(url: url, username: username, password: password)
            if HTMLText.looksLikeLoginPage(html) { throw SyncError.needsLogin }
            return HTMLText.toText(html)
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
