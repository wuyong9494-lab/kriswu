import Foundation

/// 一种班次的显示样式与识别规则。排班表里的原始文字（如 "白"、"D"、"早班"）
/// 会通过 keywords / codes 匹配到某个班次类型，用于着色和显示图标。
public struct ShiftType: Identifiable, Hashable, Codable {
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
        ShiftType(id: "off", name: "休息", emoji: "🛌", colorHex: "#7ED321",
                  keywords: ["休", "假", "无分工", "off", "rest", "leave", "holiday"], codes: ["O", "R", "X", "/", "-"]),
    ]
}

public struct ShiftMatcher {
    public var types: [ShiftType]

    public init(types: [ShiftType]) {
        self.types = types
    }

    /// 根据原文找到对应的班次类型；找不到返回 nil（界面上仍显示原文）。
    /// 先比完全相同的名称/代码，再比关键字，关键字越长优先级越高（"日班" 优于 "日"）。
    public func match(_ raw: String) -> ShiftType? {
        // 一天多个岗位（"组A+组E"、"组A、组E"）时按第一个着色
        if let first = raw.split(whereSeparator: Self.isSeparator).first, first.count < raw.count {
            return match(String(first))
        }
        let text = Self.normalize(raw)
        guard !text.isEmpty else { return nil }

        if let t = types.first(where: { Self.normalize($0.name) == text || $0.codes.contains { Self.normalize($0) == text } }) {
            return t
        }
        var best: (type: ShiftType, length: Int)?
        for t in types {
            for k in t.keywords {
                let nk = Self.normalize(k)
                if !nk.isEmpty, text.contains(nk), nk.count > (best?.length ?? 0) {
                    best = (t, nk.count)
                }
            }
        }
        return best?.type
    }

    /// 显示用名称：比类型名短的简写（"白"、"N"、"休"）显示成类型名（"白班"、"夜班"、"休息"）；
    /// 其它情况（"组A"、"值班交班前"、"调休"、"年假"）照原文显示，不丢信息。
    public func displayName(_ raw: String) -> String {
        let parts = raw.split(whereSeparator: Self.isSeparator).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count > 1 { return parts.map(displayName).joined(separator: "+") }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let type = match(text), text.count < type.name.count else { return text }
        return type.name
    }

    static func isSeparator(_ c: Character) -> Bool { c == "+" || c == "、" }

    static func normalize(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace }
    }
}
