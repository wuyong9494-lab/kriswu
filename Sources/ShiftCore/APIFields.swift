import Foundation

/// 「接口字段查看」：网站数据接口返回的每张表有哪些字段，各举几个例子（人名、长数字打码），
/// 用来看接口里有没有排班顺序号、轮次这类字段。
public struct APIFieldTable: Equatable, Codable {
    public struct Field: Equatable, Codable {
        public var name: String
        /// 例子（最多 3 个不同的值，已打码）
        public var samples: [String]
        /// 有几种不同的值
        public var distinct: Int
        /// 字段名像顺序号、轮次、排序
        public var looksLikeOrder: Bool
    }

    /// 接口路径（不含网站地址和参数）
    public var path: String
    public var rows: Int
    public var fields: [Field]
}

public enum APIFieldInspector {
    /// 字段名里有这些就可能是顺序
    static let orderWords = ["sort", "order", "seq", "index", "idx", "rank", "turn", "round", "序", "轮", "排位"]
    /// 字段名以这些结尾也可能是（userNo、dutyNum、班次）
    static let orderSuffixes = ["no", "num", "number", "号", "次"]

    public static func looksLikeOrder(_ key: String) -> Bool {
        let last = (key.split(separator: ".").last.map(String.init) ?? key).lowercased()
        return orderWords.contains { last.contains($0) } || orderSuffixes.contains { last.hasSuffix($0) }
    }

    private static let longDigits = try! NSRegularExpression(pattern: #"\d{7,}"#)

    /// 人名只留姓（张**），7 位以上的数字（手机号、工号、证件号）只留前 3 位，太长的截断
    public static func mask(_ value: String) -> String {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = RosterExtractor.cleanName(v)
        if RosterExtractor.looksLikeName(cleaned), let first = cleaned.first, cleaned.unicodeScalars.first.map({ $0.value >= 0x4e00 }) == true {
            return String(first) + String(repeating: "*", count: max(1, cleaned.count - 1))
        }
        let ns = v as NSString
        var out = ""
        var last = 0
        for m in longDigits.matches(in: v, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let digits = ns.substring(with: m.range)
            out += String(digits.prefix(3)) + String(repeating: "*", count: digits.count - 3)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out.count > 40 ? String(out.prefix(40)) + "…" : out
    }

    static func path(of url: String) -> String {
        let p = URLComponents(string: url)?.path ?? ""
        return p.isEmpty ? "/" : p
    }

    /// requests：同步时抓到的接口请求（只看返回成功、内容是 JSON 的）
    public static func summarize(_ requests: [CapturedRequest], limit: Int = 12) -> [APIFieldTable] {
        var result: [APIFieldTable] = []
        var seen = Set<String>()
        for request in requests where (200..<300).contains(request.status) {
            let body = request.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = body.first, first == "{" || first == "[",
                  let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) else { continue }
            let path = path(of: request.url)
            for rows in JSONScheduleExtractor.tables(in: json) where rows.count >= 2 {
                let keys = Set(rows.flatMap(\.keys)).sorted()
                // 同一个接口翻页、换日期取了好几次：只留一份
                let signature = path + "|" + keys.joined(separator: ",")
                guard seen.insert(signature).inserted else { continue }
                let fields = keys.map { key -> APIFieldTable.Field in
                    let values = rows.compactMap { $0[key] }.filter { !$0.isEmpty }
                    var samples: [String] = []
                    for v in values {
                        let m = mask(v)
                        if !samples.contains(m) { samples.append(m) }
                        if samples.count == 3 { break }
                    }
                    return APIFieldTable.Field(name: key, samples: samples, distinct: Set(values).count,
                                               looksLikeOrder: looksLikeOrder(key))
                }
                result.append(APIFieldTable(path: path, rows: rows.count, fields: fields))
            }
        }
        return Array(result.sorted { $0.rows > $1.rows }.prefix(limit))
    }

    /// 复制出来发给别人看的文字
    public static func text(_ tables: [APIFieldTable]) -> String {
        tables.map { t in
            "\(t.path)（\(t.rows) 条）\n" + t.fields.map { f in
                (f.looksLikeOrder ? "★ " : "• ") + "\(f.name)：\(f.samples.joined(separator: " / "))（\(f.distinct) 种）"
            }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
