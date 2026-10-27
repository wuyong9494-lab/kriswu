import Foundation

/// 自动下载周会表格（金山文档）时，从金山文档回来的内容里找东西：文件编号、下载地址、出错说明。
/// 联网在 App 里做（要用 App 里登录的金山文档账号），这里只管解析。
/// 金山文档没有公开这几个接口：照网页版的做法「分享链接 → 文件编号 → 下载地址 → Excel 文件」，找的时候尽量宽松
public enum DocDownload {
    /// 一个文件：所在的组（文件夹）编号、文件编号、文件名
    public struct FileRef: Equatable, Sendable {
        public var group: String
        public var id: String
        public var name: String?
        public init(group: String, id: String, name: String? = nil) {
            self.group = group
            self.id = id
            self.name = name
        }
    }

    /// 金山文档的分享链接（kdocs.cn/l/xxxx）
    public static func isSupported(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return (host == "kdocs.cn" || host.hasSuffix(".kdocs.cn") || host.hasSuffix(".wps.cn")) && shareID(url) != nil
    }

    /// 「https://www.kdocs.cn/l/abc123」→「abc123」
    public static func shareID(_ url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let i = parts.firstIndex(of: "l"), i + 1 < parts.count else { return nil }
        let sid = parts[i + 1]
        guard !sid.isEmpty, sid.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { return nil }
        return sid
    }

    /// 问分享链接对应哪个文件（依次试）
    public static func linkInfoURLs(_ sid: String) -> [URL] {
        ["https://www.kdocs.cn/api/v3/links/\(sid)",
         "https://drive.kdocs.cn/api/v5/links/\(sid)",
         "https://drive.kdocs.cn/api/v3/links/\(sid)"].compactMap { URL(string: $0) }
    }

    /// 问文件的下载地址（依次试）；有的直接回文件，有的回一个带 url 的说明
    public static func downloadURLs(_ file: FileRef) -> [URL] {
        let path = "groups/\(file.group)/files/\(file.id)/download?isblocks=false"
        return ["https://drive.kdocs.cn/api/v5/\(path)&support_checksums=md5,sha1",
                "https://drive.kdocs.cn/api/v3/\(path)",
                "https://www.kdocs.cn/api/v5/\(path)",
                "https://www.kdocs.cn/api/v3/\(path)"].compactMap { URL(string: $0) }
    }

    // MARK: - 从回来的内容里找

    /// JSON 里带 groupid、fileid（或 id + 文件名）的那一段
    public static func file(inJSON data: Data) -> FileRef? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        return file(in: json)
    }

    static func file(in json: Any) -> FileRef? {
        var queue: [Any] = [json]
        var fallback: FileRef?
        var i = 0
        while i < queue.count {
            let node = queue[i]
            i += 1
            if let dict = node as? [String: Any] {
                var lower: [String: Any] = [:]
                for (key, value) in dict { lower[key.lowercased()] = value }
                let name = (lower["fname"] ?? lower["filename"]) as? String
                if let group = number(lower["groupid"]), let id = number(lower["fileid"]) ?? (name != nil ? number(lower["id"]) : nil) {
                    let ref = FileRef(group: group, id: id, name: name)
                    if name != nil { return ref }
                    if fallback == nil { fallback = ref }
                }
                for key in dict.keys.sorted() { if let value = dict[key] { queue.append(value) } }
            } else if let array = node as? [Any] {
                queue.append(contentsOf: array)
            }
        }
        return fallback
    }

    /// 网页里（或网页自己要到的内容里）找文件编号：整段是 JSON 就按 JSON 找，否则在「groupid」附近找
    public static func file(inText text: String) -> FileRef? {
        if let ref = file(inJSON: Data(text.utf8)) { return ref }
        // 网页里常把 JSON 当字符串写：\"groupid\":123
        let plain = text.replacingOccurrences(of: "\\\"", with: "\"")
        let ns = plain as NSString
        let all = NSRange(location: 0, length: ns.length)
        // 最里层带 groupid 的 {…}
        let objects = try! NSRegularExpression(pattern: #"\{[^{}]*"groupid"[^{}]*\}"#, options: [.caseInsensitive])
        var fallback: FileRef?
        for m in objects.matches(in: plain, range: all) {
            guard let json = try? JSONSerialization.jsonObject(with: Data(ns.substring(with: m.range).utf8)),
                  let ref = file(in: json) else { continue }
            if ref.name != nil { return ref }
            if fallback == nil { fallback = ref }
        }
        if let fallback { return fallback }
        // {…} 里还套着别的 {…}：在 groupid 前后几百个字里找 fileid，没有就取它前面最近的 id
        let groupPattern = try! NSRegularExpression(pattern: #""groupid"\s*:\s*"?(\d+)"#, options: [.caseInsensitive])
        let filePattern = try! NSRegularExpression(pattern: #""fileid"\s*:\s*"?(\d+)"#, options: [.caseInsensitive])
        let idPattern = try! NSRegularExpression(pattern: #""id"\s*:\s*"?(\d+)"#)
        let namePattern = try! NSRegularExpression(pattern: #""fname"\s*:\s*"([^"]*)""#)
        for m in groupPattern.matches(in: plain, range: all) {
            let group = ns.substring(with: m.range(at: 1))
            let start = max(0, m.range.location - 600)
            let window = NSRange(location: start, length: min(ns.length, m.range.location + 600) - start)
            let before = NSRange(location: start, length: m.range.location - start)
            let id = filePattern.firstMatch(in: plain, range: window).map { ns.substring(with: $0.range(at: 1)) }
                ?? idPattern.matches(in: plain, range: before).last.map { ns.substring(with: $0.range(at: 1)) }
            guard let id else { continue }
            let name = namePattern.firstMatch(in: plain, range: window).map { ns.substring(with: $0.range(at: 1)) }
            return FileRef(group: group, id: id, name: name)
        }
        return nil
    }

    /// 回来的说明里的下载地址：键名就叫 url 的优先，其次带 download 的，再其次别的 …url
    public static func fileURL(inJSON data: Data) -> URL? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        var queue: [Any] = [json]
        var download: URL?
        var other: URL?
        var i = 0
        while i < queue.count {
            let node = queue[i]
            i += 1
            if let dict = node as? [String: Any] {
                for key in dict.keys.sorted() {
                    guard let value = dict[key] else { continue }
                    let k = key.lowercased()
                    if let s = value as? String, s.hasPrefix("http"), k.contains("url"), let url = URL(string: s) {
                        if k == "url" { return url }
                        if k.contains("download") { download = download ?? url } else { other = other ?? url }
                    } else {
                        queue.append(value)
                    }
                }
            } else if let array = node as? [Any] {
                queue.append(contentsOf: array)
            }
        }
        return download ?? other
    }

    /// 出错时回来的一句话（result、msg 这些），记进下载过程
    public static func brief(_ data: Data) -> String {
        if let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            let parts = ["result", "code", "msg", "message", "errmsg"].compactMap { key in dict[key].map { "\($0)" } }
            if !parts.isEmpty { return String(parts.joined(separator: " ").prefix(80)) }
        }
        let text = String(decoding: data.prefix(300), as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return String(text.prefix(60))
    }

    /// 金山文档说没登录
    public static func saysLogin(status: Int, data: Data) -> Bool {
        if status == 401 { return true }
        let text = brief(data).lowercased()
        return text.contains("login") || text.contains("登录")
    }

    /// Excel（.xlsx）文件是 ZIP，开头是 PK\3\4
    public static func isZip(_ data: Data) -> Bool {
        data.count > 4 && data.starts(with: [0x50, 0x4B, 0x03, 0x04])
    }

    static func number(_ value: Any?) -> String? {
        if let s = value as? String { return !s.isEmpty && s.allSatisfy({ $0.isASCII && $0.isNumber }) ? s : nil }
        if let n = value as? Int { return n > 0 ? String(n) : nil }
        if let n = value as? Int64 { return n > 0 ? String(n) : nil }
        if let n = value as? NSNumber { return n.int64Value > 0 ? String(n.int64Value) : nil }
        return nil
    }
}
