import Foundation

/// 一种班次的显示样式与识别规则。排班表里的原始文字（如 "白"、"D"、"早班"）
/// 会通过 keywords / codes 匹配到某个班次类型，用于着色和显示图标。
public struct ShiftType: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    /// 十六进制颜色，如 "#F5A623"。
    public var colorHex: String
    /// 原文包含任一关键字即匹配，如 "白"、"day"。
    public var keywords: [String]
    /// 原文完全等于任一代码才匹配（不区分大小写），用于 "D"、"N" 这类单字母。
    public var codes: [String]

    public init(id: String = UUID().uuidString, name: String, emoji: String, colorHex: String,
                keywords: [String] = [], codes: [String] = []) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.keywords = keywords
        self.codes = codes
    }

    public static let defaults: [ShiftType] = [
        ShiftType(id: "group", name: "组", emoji: "👥", colorHex: "#4A90E2", keywords: ["组"]),
        ShiftType(id: "telemetry", name: "遥测", emoji: "📡", colorHex: "#17A2B8", keywords: ["遥测"]),
        ShiftType(id: "dispatch", name: "调度", emoji: "🎛️", colorHex: "#9B59B6", keywords: ["调度"]),
        ShiftType(id: "day", name: "白班", emoji: "🌅", colorHex: "#F5A623",
                  keywords: ["白", "早", "日班", "day"], codes: ["D", "A", "AM"]),
        ShiftType(id: "middle", name: "中班", emoji: "🌇", colorHex: "#E8743B",
                  keywords: ["中", "午", "evening", "swing"], codes: ["M", "E", "P", "PM"]),
        ShiftType(id: "night", name: "夜班", emoji: "🌙", colorHex: "#5B6CF0",
                  keywords: ["夜", "晚", "night"], codes: ["N"]),
        ShiftType(id: "duty", name: "值班", emoji: "🛡️", colorHex: "#D0021B",
                  keywords: ["值", "duty", "on-call", "oncall"], codes: []),
        ShiftType(id: "trip", name: "出差", emoji: "🧳", colorHex: "#8E8E93", keywords: ["出差"]),
        ShiftType(id: "overtime", name: "加班", emoji: "⏱️", colorHex: "#E8743B", keywords: ["加班"]),
        ShiftType(id: "off", name: "休息", emoji: "🛌", colorHex: "#7ED321",
                  keywords: ["休", "假", "无分工", "交接", "交班", "off", "rest", "leave", "holiday"], codes: ["O", "R", "X", "/", "-"]),
    ]
}

public struct ShiftMatcher: Sendable {
    public var types: [ShiftType] { didSet { index = Self.buildIndex(types); cache = MatchCache() } }
    /// 识别结果缓存：排班里的写法就那么几十种，统计、推算却要问几十万次。可以多线程用
    fileprivate(set) var cache = MatchCache()

    /// 预先整理好的名称、代码、关键字（match 每次调用不用再整理一遍）
    private struct Entry {
        let type: ShiftType
        let exact: Set<String>
        let keywords: [String]
    }
    private var index: [Entry]

    public init(types: [ShiftType]) {
        self.types = types
        self.index = Self.buildIndex(types)
    }

    private static func buildIndex(_ types: [ShiftType]) -> [Entry] {
        types.map { t in
            Entry(type: t, exact: Set([normalize(t.name)] + t.codes.map(normalize)),
                  keywords: t.keywords.map(normalize).filter { !$0.isEmpty })
        }
    }

    /// 一天的几个岗位（「组A+组E」「组A、组E」……统一拆开），去掉空白
    public func posts(_ raw: String) -> [String] {
        raw.split(whereSeparator: Self.isSeparator).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 根据原文找到对应的班次类型；找不到返回 nil（界面上仍显示原文）。
    /// 先比完全相同的名称/代码，再比关键字，关键字越长优先级越高（"日班" 优于 "日"）。
    public func match(_ raw: String) -> ShiftType? {
        if let hit = cache.matches.object(forKey: raw as NSString) { return hit.index < 0 ? nil : index[hit.index].type }
        let found = uncachedMatch(raw)
        let i = found.flatMap { t in index.firstIndex { $0.type.id == t.id } } ?? -1
        cache.matches.setObject(MatchCache.Hit(i), forKey: raw as NSString)
        return found
    }

    private func uncachedMatch(_ raw: String) -> ShiftType? {
        // 一天多个岗位（"组A+组E"、"组A、组E"）时按第一个着色
        if let first = raw.split(whereSeparator: Self.isSeparator).first, first.count < raw.count {
            return match(String(first))
        }
        let text = Self.normalize(raw)
        guard !text.isEmpty else { return nil }

        if let e = index.first(where: { $0.exact.contains(text) }) { return e.type }
        var best: (type: ShiftType, length: Int)?
        for e in index {
            for nk in e.keywords where text.contains(nk) && nk.count > (best?.length ?? 0) {
                best = (e.type, nk.count)
            }
        }
        return best?.type
    }

    /// 显示用名称：比类型名短的简写（"白"、"N"、"休"）显示成类型名（"白班"、"夜班"、"休息"）；
    /// 其它情况（"组A"、"值班交班前"、"调休"、"年假"）照原文显示，不丢信息。
    public func displayName(_ raw: String) -> String {
        if let hit = cache.names.object(forKey: raw as NSString) { return hit as String }
        let name = uncachedDisplayName(raw)
        cache.names.setObject(name as NSString, forKey: raw as NSString)
        return name
    }

    private func uncachedDisplayName(_ raw: String) -> String {
        let parts = raw.split(whereSeparator: Self.isSeparator).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count > 1 { return parts.map(displayName).joined(separator: "+") }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let type = match(text), text.count < type.name.count else { return text }
        return type.name
    }

    /// 一天多个岗位的分隔：组A+组E、组A、组E、组A,组E（数据库拼接常见）、组A/组E
    static func isSeparator(_ c: Character) -> Bool { "+、,，;；/".contains(c) }

    /// 严格判断是不是班次/岗位名：和名称、代码完全相同，或者含有两个字以上的关键字。
    /// 人名里常有「中」「白」「夜」这类单字（王建中），不能只凭一个字就当成岗位。
    public func isStrictMatch(_ raw: String) -> Bool {
        let text = Self.normalize(raw)
        guard !text.isEmpty else { return false }
        if GroupNotes.isGroup(raw) { return true }   // 组A–组E
        return types.contains { t in
            Self.normalize(t.name) == text || t.codes.contains { Self.normalize($0) == text }
                || t.keywords.contains { k in
                    let nk = Self.normalize(k)
                    return nk.count >= 2 && text.contains(nk)
                }
        }
    }

    static func normalize(_ s: String) -> String {
        s.halfwidthAlnum.lowercased().filter { !$0.isWhitespace }
    }
}

/// ShiftMatcher 的识别缓存（NSCache 自己加锁，多线程安全）
/// NSCache 本身可以多线程用，所以整个缓存可以跨线程共用
final class MatchCache: @unchecked Sendable {
    final class Hit: Sendable {
        let index: Int
        init(_ index: Int) { self.index = index }
    }
    let matches = NSCache<NSString, Hit>()
    let names = NSCache<NSString, NSString>()
    /// 统计用的岗位（WorkloadCounter.effective）；空字符串表示 nil
    let effective = NSCache<NSString, NSString>()
}

extension ShiftMatcher {
    /// 按文字缓存「统计用的岗位」（一年几十人几百天，写法却只有几十种）
    func cachedEffective(_ raw: String, compute: () -> String?) -> String? {
        if let hit = cache.effective.object(forKey: raw as NSString) { return hit.length == 0 ? nil : hit as String }
        let value = compute()
        cache.effective.setObject((value ?? "") as NSString, forKey: raw as NSString)
        return value
    }
}
