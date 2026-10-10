import SwiftUI
import UIKit

extension Color {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

/// 某一天班次的显示信息。
struct ShiftDisplay {
    var name: String
    var emoji: String
    var color: Color

    init?(raw: String?, matcher: ShiftMatcher) {
        guard let raw, !raw.isEmpty else { return nil }
        let type = matcher.match(raw)
        // 和通知用同一套规则：简写（"白"）显示类型名，"组D"、"调休" 等照原文显示
        name = matcher.displayName(raw)
        emoji = type?.emoji ?? "📌"
        color = type.map { Color(hex: $0.colorHex) } ?? .gray
    }
}
