import Foundation

/// 网页向服务器取数据的一次请求（App 在内置浏览器里记录下来，只保存在手机内存中）。
public struct CapturedRequest: Codable, Hashable {
    public var url: String
    public var method: String
    public var headers: [String: String]
    public var requestBody: String?
    public var status: Int
    public var body: String

    public init(url: String, method: String, headers: [String: String] = [:], requestBody: String? = nil,
                status: Int = 200, body: String = "") {
        self.url = url
        self.method = method
        self.headers = headers
        self.requestBody = requestBody
        self.status = status
        self.body = body
    }

    enum CodingKeys: String, CodingKey {
        case url, method, headers, status, body
        case requestBody = "reqBody"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        method = (try? c.decode(String.self, forKey: .method)) ?? "GET"
        headers = (try? c.decode([String: String].self, forKey: .headers)) ?? [:]
        requestBody = try? c.decode(String.self, forKey: .requestBody)
        status = (try? c.decode(Int.self, forKey: .status)) ?? 0
        body = (try? c.decode(String.self, forKey: .body)) ?? ""
    }

    /// 接口的「身份」：请求方法 + 不带参数的地址，例如 "GET http://host/api/duty/my"。
    public var signature: String {
        let base = url.split(separator: "?", maxSplits: 1).first.map(String.init) ?? url
        return "\(method.uppercased()) \(base)"
    }

    /// 把地址参数和请求内容里的日期都往后推几天，用来取下一周的数据。
    public func shifted(days: Int) -> CapturedRequest {
        var copy = self
        copy.url = DateShifter.shift(url, days: days)
        copy.requestBody = requestBody.map { DateShifter.shift($0, days: days) }
        copy.body = ""
        return copy
    }

    /// 请求里有没有日期参数（没有的话往后推也取不到别的周）。
    public var hasDateParameter: Bool {
        DateShifter.shift(url, days: 7) != url || requestBody.map { DateShifter.shift($0, days: 7) != $0 } ?? false
    }
}

/// 在一段文字（网址、请求内容）里找日期并整体平移，保持原来的写法。
/// 支持 2026-10-05、2026/10/05、20261005，以及 10 位秒 / 13 位毫秒时间戳。
public enum DateShifter {
    private static let patterns: [(NSRegularExpression, Kind)] = [
        (try! NSRegularExpression(pattern: #"(?<!\d)(20\d{2})([-/])(\d{1,2})\2(\d{1,2})(?!\d)"#), .separated),
        (try! NSRegularExpression(pattern: #"(?<!\d)(20\d{2})(\d{2})(\d{2})(?!\d)"#), .compact),
        (try! NSRegularExpression(pattern: #"(?<!\d)(1[5-9]\d{11})(?!\d)"#), .millis),
        (try! NSRegularExpression(pattern: #"(?<!\d)(1[5-9]\d{8})(?!\d)"#), .seconds),
    ]

    private enum Kind { case separated, compact, millis, seconds }

    public static func shift(_ text: String, days: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var s = text
        for (re, kind) in patterns {
            let ns = s as NSString
            var out = ""
            var last = 0
            for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let whole = ns.substring(with: m.range)
                out += replacement(for: m, in: ns, kind: kind, days: days, calendar: calendar) ?? whole
                last = m.range.location + m.range.length
            }
            s = out + ns.substring(from: last)
        }
        return s
    }

    private static func replacement(for m: NSTextCheckingResult, in ns: NSString, kind: Kind, days: Int,
                                     calendar: Calendar) -> String? {
        func group(_ i: Int) -> String { ns.substring(with: m.range(at: i)) }
        switch kind {
        case .separated, .compact:
            let (y, mo, d) = kind == .separated
                ? (Int(group(1)), Int(group(3)), Int(group(4)))
                : (Int(group(1)), Int(group(2)), Int(group(3)))
            guard let y, let mo, let d, DayKey.isValid(year: y, month: mo, day: d) else { return nil }
            let key = DayKey(year: y, month: mo, day: d).adding(days: days, calendar: calendar)
            if kind == .compact { return String(format: "%04d%02d%02d", key.year, key.month, key.day) }
            let sep = group(2)
            // 保持原来是否补零的写法
            let pad = group(3).count == 2 || group(4).count == 2
            let mm = pad ? String(format: "%02d", key.month) : String(key.month)
            let dd = pad ? String(format: "%02d", key.day) : String(key.day)
            return "\(key.year)\(sep)\(mm)\(sep)\(dd)"
        case .millis:
            guard let v = Int64(group(1)) else { return nil }
            return String(v + Int64(days) * 86_400_000)
        case .seconds:
            guard let v = Int64(group(1)) else { return nil }
            return String(v + Int64(days) * 86_400)
        }
    }
}

/// 从接口返回的 JSON 里认出「日期 → 分工」。不依赖字段名：
/// 哪个字段的值大多是日期就当日期；哪个字段的值最像班次（组A、白班、无分工…）就当分工；
/// 如果是多人数据，用名字过滤出自己的那几条。
public enum JSONScheduleExtractor {
    public static func extract(_ text: String, aliases: [String], matcher: ShiftMatcher,
                               reference: DayKey) -> [DayKey: String] {
        guard let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first, first == "{" || first == "[",
              let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { return [:] }
        let parser = ScheduleParser(aliases: aliases, reference: reference)
        let dates = DateTokenParser(reference: reference)
        var best: [DayKey: String] = [:]
        for table in tables(in: json) {
            let entries = extract(table, parser: parser, dates: dates, matcher: matcher)
            if entries.count > best.count { best = entries }
        }
        return best
    }

    /// JSON 里所有「对象数组」（每个对象拍平成 字段路径 → 文字）。
    static func tables(in json: Any) -> [[[String: String]]] {
        var result: [[[String: String]]] = []
        func visit(_ value: Any) {
            if let array = value as? [Any] {
                let objects = array.compactMap { $0 as? [String: Any] }
                if !objects.isEmpty { result.append(objects.map { flatten($0) }) }
                array.forEach(visit)
            } else if let dict = value as? [String: Any] {
                dict.values.forEach(visit)
            }
        }
        visit(json)
        return result
    }

    /// {"date":"…","duty":{"group":"组A"},"tags":["组A","组E"]} → ["date": "…", "duty.group": "组A", "tags": "组A、组E"]
    static func flatten(_ dict: [String: Any], prefix: String = "") -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in dict {
            let key = prefix.isEmpty ? k : "\(prefix).\(k)"
            if let d = v as? [String: Any] {
                out.merge(flatten(d, prefix: key)) { a, _ in a }
            } else if let a = v as? [Any] {
                let scalars = a.compactMap(scalar)
                if !scalars.isEmpty { out[key] = scalars.joined(separator: "、") }
                // 对象数组：同一字段的值合并，例如 duties[].group → "组A、组E"
                var merged: [String: [String]] = [:]
                for case let d as [String: Any] in a {
                    for (sk, sv) in flatten(d, prefix: key) { merged[sk, default: []].append(sv) }
                }
                for (sk, values) in merged { out[sk] = values.joined(separator: "、") }
            } else if let s = scalar(v) {
                out[key] = s
            }
        }
        return out
    }

    private static func scalar(_ v: Any) -> String? {
        if v is NSNull { return nil }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    static func day(from value: String, dates: DateTokenParser) -> DayKey? {
        if let d = dates.parse(value) { return d }
        // 毫秒 / 秒时间戳
        if value.count == 13 || value.count == 10, let n = Double(value), n > 1_400_000_000 {
            let date = Date(timeIntervalSince1970: value.count == 13 ? n / 1000 : n)
            return DayKey(date: date, calendar: Calendar(identifier: .gregorian))
        }
        return nil
    }

    private static let shiftKeyHints = ["shift", "duty", "group", "post", "work", "task", "job", "class", "team",
                                        "分工", "班", "组", "岗", "职"]

    /// 日期字段：至少一半的行能解析出日期；有好几个时（如「值班日期」和「更新时间」）取不同日期最多的。
    static func dateKey(in rows: [[String: String]], dates: DateTokenParser) -> String? {
        Set(rows.flatMap(\.keys)).compactMap { k -> (String, Int, Int)? in
            let parsed = rows.compactMap { $0[k].flatMap { day(from: $0, dates: dates) } }
            guard !parsed.isEmpty, parsed.count * 2 >= rows.count else { return nil }
            return (k, Set(parsed).count, parsed.count)
        }
        .max { ($0.1, $0.2, $1.0) < ($1.1, $1.2, $0.0) }?.0
    }

    static func extract(_ rows: [[String: String]], parser: ScheduleParser, dates: DateTokenParser,
                        matcher: ShiftMatcher) -> [DayKey: String] {
        let keys = Set(rows.flatMap(\.keys))

        // 1. 日期字段
        guard let dateKey = dateKey(in: rows, dates: dates) else { return [:] }

        // 2. 多人数据：找出包含自己名字的字段，只保留自己的行
        let personKey = keys.filter { $0 != dateKey }.first { k in rows.contains { $0[k].map(parser.isMe) ?? false } }
        let mine = personKey.map { k in rows.filter { $0[k].map(parser.isMe) ?? false } } ?? rows

        // 没认出自己、又是每天好几条的多人数据：认不准，放弃
        if personKey == nil {
            let days = Set(rows.compactMap { $0[dateKey].flatMap { day(from: $0, dates: dates) } })
            if !days.isEmpty && rows.count > days.count * 2 { return [:] }
        }

        // 3. 分工字段：值最像班次的那个字段
        func score(_ k: String) -> Int {
            let values = mine.compactMap { $0[k] }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !values.isEmpty else { return 0 }
            var s = 0
            for v in values {
                if v.allSatisfy({ $0.isNumber || "-:./ ".contains($0) }) { s -= 3; continue }   // 数字、时间、ID
                if day(from: v, dates: dates) != nil { s -= 3; continue }
                if DateTokenParser.cleaned(v).isEmpty { s -= 2; continue }                      // 只有星期
                if v.count > 40 { s -= 1; continue }
                if matcher.match(v) != nil { s += 3 }
                if parser.isMe(v) { s -= 3 }
            }
            let lower = k.lowercased()
            if shiftKeyHints.contains(where: { lower.contains($0) }) { s += values.count }
            if lower.hasSuffix("id") || lower.contains("time") || lower.contains("week") { s -= values.count }
            return s
        }
        let shiftKey = keys.subtracting([dateKey, personKey].compactMap { $0 })
            .map { ($0, score($0)) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?.0
        guard let shiftKey else { return [:] }

        var entries: [DayKey: String] = [:]
        for row in mine {
            guard let d = row[dateKey].flatMap({ day(from: $0, dates: dates) }) else { continue }
            let raw = row[shiftKey]?.trimmingCharacters(in: .whitespaces) ?? ""
            // 有这一天的记录、分工却是空的：网页上显示的是「无分工」
            guard !raw.isEmpty else {
                if entries[d] == nil { entries[d] = "无分工" }
                continue
            }
            let value = parser.removingAliases(raw).isEmpty ? raw : parser.removingAliases(raw)
            if let existing = entries[d], existing != "无分工" {
                if !existing.components(separatedBy: "+").contains(value) { entries[d] = existing + "+" + value }
            } else {
                entries[d] = value
            }
        }
        return entries
    }
}

/// 从记录下来的请求里挑出排班接口。
public enum APIDiscovery {
    public struct Found {
        public var request: CapturedRequest
        public var entries: [DayKey: String]
    }

    /// 优先用上次认出的接口（signature 相同）；否则在所有返回 JSON 的请求里挑认出天数最多的。
    public static func find(in captured: [CapturedRequest], preferred: String?, aliases: [String],
                            matcher: ShiftMatcher, reference: DayKey) -> Found? {
        let ok = captured.filter { (200..<300).contains($0.status) }
        let candidates = preferred.flatMap { sig in
            let same = ok.filter { $0.signature == sig }
            return same.isEmpty ? nil : same
        } ?? ok
        var best: Found?
        for request in candidates {
            let entries = JSONScheduleExtractor.extract(request.body, aliases: aliases, matcher: matcher, reference: reference)
            if entries.count > (best?.entries.count ?? 0) { best = Found(request: request, entries: entries) }
        }
        return best
    }
}
