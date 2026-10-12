import SwiftUI
import UIKit

/// 全 App 统一的样式：主色、卡片、标题、触感反馈。
enum Theme {
    /// 主色：沉稳的蓝
    static let accent = Color(hex: "#3D6DF2")
    static let cardRadius: CGFloat = 22

    /// 按班次颜色做的渐变（左上亮、右下深）
    static func gradient(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.95), color.blended(with: .black, 0.25)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 早上好 / 下午好 / 晚上好
    static func greeting(_ date: Date) -> String {
        switch Calendar.app.component(.hour, from: date) {
        case 5..<11: return "早上好"
        case 11..<13: return "中午好"
        case 13..<18: return "下午好"
        default: return "晚上好"
        }
    }
}

extension Color {
    /// 和另一种颜色按比例混合（iOS 16 没有自带的 mix）
    func blended(with other: Color, _ amount: CGFloat) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = min(max(amount, 0), 1)
        return Color(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, opacity: a1 + (a2 - a1) * t)
    }
}

/// 卡片：圆角、柔和阴影，深色模式下用浅一点的底色
struct CardModifier: ViewModifier {
    var tint: Color?
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(tint.opacity(0.12))
                        }
                    }
                    .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
            }
    }
}

extension View {
    func card(tint: Color? = nil, padding: CGFloat = 16) -> some View {
        modifier(CardModifier(tint: tint, padding: padding))
    }
}

/// 卡片里的小标题：图标 + 文字 + 右边可选内容
struct CardTitle<Trailing: View>: View {
    let title: String
    let icon: String
    var color: Color = Theme.accent
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title).font(.headline)
            Spacer(minLength: 0)
            trailing()
        }
    }
}

extension CardTitle where Trailing == EmptyView {
    init(title: String, icon: String, color: Color = Theme.accent) {
        self.init(title: title, icon: icon, color: color) { EmptyView() }
    }
}

/// 轻触反馈
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

/// 按下时略微缩小的按钮样式
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
