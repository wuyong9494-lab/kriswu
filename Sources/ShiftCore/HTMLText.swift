import Foundation

/// 把网页（尤其是里面的 <table> 排班表）转成制表符分隔的文字，再交给 ScheduleParser。
public enum HTMLText {
    public static func looksLikeHTML(_ s: String) -> Bool {
        let head = s.prefix(1024).lowercased()
        return head.contains("<html") || head.contains("<!doctype html") || head.contains("<table") || head.contains("<body")
    }

    /// 页面里有密码输入框，基本可以认为是登录页（登录已失效）。
    public static func looksLikeLoginPage(_ s: String) -> Bool {
        s.range(of: #"type\s*=\s*["']?password"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// 表格逐行转成「单元格\t单元格」，单元格里的多个名字用空格隔开；表格以外的文字按段落换行。
    /// 不依赖单元格内部结构，Element / Ant Design 这类前端组件生成的表格（表头和表体是两个 table）也能对齐。
    public static func toText(_ html: String) -> String {
        var s = html
        func replace(_ pattern: String, _ with: String) {
            s = s.replacingOccurrences(of: pattern, with: with, options: [.regularExpression, .caseInsensitive])
        }
        replace(#"<(script|style|noscript|template)\b[^>]*>[\s\S]*?</\1\s*>"#, " ")
        replace(#"<!--[\s\S]*?-->"#, " ")
        replace(#"\s+"#, " ")

        // 先把每个表格换成占位符，最后再放回去，避免表格内部的 <div> 被当成换行
        var tables: [String] = []
        s = replaceMatches(#"<table\b[^>]*>[\s\S]*?</table\s*>"#, in: s) { table in
            tables.append(tableText(table))
            return "\n\u{1}\(tables.count - 1)\u{1}\n"
        }

        replace(#"<br\s*/?>|</(p|div|li|h[1-6]|section|article|header|footer)\s*>"#, "\n")
        // 其它标签换成空格，避免 <span>2026-10-05</span><span>组A</span> 粘在一起
        replace(#"<[^>]+>"#, " ")
        replace(#"[ \t]+"#, " ")
        s = decodeEntities(s)

        return s.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line -> String in
                if line.hasPrefix("\u{1}"), let n = Int(line.trimmingCharacters(in: CharacterSet(charactersIn: "\u{1}"))), n < tables.count {
                    return tables[n]
                }
                return line
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// 只要网页里的表格（逐行「格子\t格子」），表格以外的文字不要。
    public static func tablesOnly(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"<(script|style|noscript|template)\b[^>]*>[\s\S]*?</\1\s*>"#, with: " ",
                                          options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return captures(#"(<table\b[^>]*>[\s\S]*?</table\s*>)"#, in: s).map(tableText).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// 表格转成一行一行、用制表符隔开的文字。合并单元格展开成普通格子，后面的列才不会错位：
    /// rowspan（比如一个日期占好几行）往下几行都填同样的文字；表头的 colspan 每一列都填，内容格的 colspan 只填第一列
    static func tableText(_ table: String) -> String {
        var lines: [String] = []
        // 上面的行用 rowspan 占到这一行的格子：列号 → (文字, 还要占几行)
        var carried: [Int: (text: String, rows: Int)] = [:]
        for row in captures(#"<tr\b[^>]*>([\s\S]*?)</tr\s*>"#, in: table) {
            var cells: [String] = []
            func fillCarried() {
                while let c = carried[cells.count] {
                    cells.append(c.text)
                    carried[cells.count - 1] = c.rows > 1 ? (c.text, c.rows - 1) : nil
                }
            }
            for cell in cellMatches(in: row) {
                fillCarried()
                let text = cellText(cell.body)
                let colspan = max(1, min(50, spanValue("colspan", in: cell.attributes)))
                let rowspan = max(1, min(400, spanValue("rowspan", in: cell.attributes)))
                for k in 0..<colspan {
                    let value = k == 0 || cell.header ? text : ""
                    if rowspan > 1 { carried[cells.count] = (value, rowspan - 1) }
                    cells.append(value)
                }
            }
            fillCarried()
            while let last = cells.last, last.isEmpty { cells.removeLast() }
            if !cells.isEmpty { lines.append(cells.joined(separator: "\t")) }
        }
        return lines.joined(separator: "\n")
    }

    /// 一行里的格子：是不是表头、属性、内容
    static func cellMatches(in row: String) -> [(header: Bool, attributes: String, body: String)] {
        let re = regex(#"<t([dh])\b([^>]*)>([\s\S]*?)</t[dh]\s*>"#)
        let ns = row as NSString
        return re.matches(in: row, range: NSRange(location: 0, length: ns.length)).map { m in
            (ns.substring(with: m.range(at: 1)).lowercased() == "h", ns.substring(with: m.range(at: 2)), ns.substring(with: m.range(at: 3)))
        }
    }

    /// rowspan="3" / colspan=2 → 数字；没写是 1
    static func spanValue(_ name: String, in attributes: String) -> Int {
        captures(name + #"\s*=\s*["']?(\d+)"#, in: attributes).first.flatMap { Int($0) } ?? 1
    }

    static func cellText(_ html: String) -> String {
        let noTags = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return decodeEntities(noTags)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// 返回每个匹配的第 1 个捕获组。
    /// 编译好的正则（解析一页网页要用几百次，每次都编译很慢）
    private static let regexCache = RegexCache()

    /// NSCache 本身可以多线程用（Linux 上没标 Sendable，包一层说明）
    private final class RegexCache: @unchecked Sendable {
        let cache = NSCache<NSString, NSRegularExpression>()
    }

    static func regex(_ pattern: String) -> NSRegularExpression {
        if let re = regexCache.cache.object(forKey: pattern as NSString) { return re }
        let re = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        regexCache.cache.setObject(re, forKey: pattern as NSString)
        return re
    }

    static func captures(_ pattern: String, in s: String) -> [String] {
        let re = regex(pattern)
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    static func replaceMatches(_ pattern: String, in s: String, with transform: (String) -> String) -> String {
        let re = regex(pattern)
        let ns = s as NSString
        var result = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            result += transform(ns.substring(with: m.range))
            last = m.range.location + m.range.length
        }
        return result + ns.substring(from: last)
    }

    private static let entity = try! NSRegularExpression(pattern: #"&(#[xX][0-9a-fA-F]+|#[0-9]+|nbsp|lt|gt|quot|apos|amp);"#,
                                                          options: [.caseInsensitive])
    private static let named: [String: String] = ["nbsp": " ", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "amp": "&"]

    /// 一遍换完：「&amp;lt;」变成「&lt;」、「&amp;#60;」变成「&#60;」，不会被换两次
    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let ns = s as NSString
        var result = ""
        var last = 0
        for m in entity.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let body = ns.substring(with: m.range(at: 1))
            var decoded: String?
            if body.hasPrefix("#") {
                let digits = body.dropFirst()
                let hex = digits.first == "x" || digits.first == "X"
                let num = UInt32(hex ? String(digits.dropFirst()) : String(digits), radix: hex ? 16 : 10)
                decoded = num.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                decoded = named[body.lowercased()]
            }
            result += decoded ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
