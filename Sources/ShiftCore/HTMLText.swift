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

    static func tableText(_ table: String) -> String {
        var lines: [String] = []
        for row in captures(#"<tr\b[^>]*>([\s\S]*?)</tr\s*>"#, in: table) {
            var cells = captures(#"<t[dh]\b[^>]*>([\s\S]*?)</t[dh]\s*>"#, in: row).map(cellText)
            while let last = cells.last, last.isEmpty { cells.removeLast() }
            if !cells.isEmpty { lines.append(cells.joined(separator: "\t")) }
        }
        return lines.joined(separator: "\n")
    }

    static func cellText(_ html: String) -> String {
        let noTags = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return decodeEntities(noTags)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// 返回每个匹配的第 1 个捕获组。
    static func captures(_ pattern: String, in s: String) -> [String] {
        let re = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    static func replaceMatches(_ pattern: String, in s: String, with transform: (String) -> String) -> String {
        let re = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
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

    static func decodeEntities(_ s: String) -> String {
        var out = s
        let named = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&amp;": "&"]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v, options: .caseInsensitive) }

        let re = try! NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#)
        let ns = out as NSString
        var result = ""
        var last = 0
        for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let hex = ns.substring(with: m.range(at: 1)) == "x"
            let num = UInt32(ns.substring(with: m.range(at: 2)), radix: hex ? 16 : 10)
            result += num.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
