import SwiftUI
import UIKit

// MARK: - 设计系统（Design System）
//
// 全 App 只从这里取颜色、间距、圆角、字体、阴影，页面里不写死数值。
// 间距走 8pt 网格；表面用毛玻璃 + 极细描边（Glassmorphism），浅色模式下卡片顶边带一道高光（少量 Neumorphism）。

enum DS {
    /// 8pt 网格（4 只用于图标和文字之间的微小间隔）
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Radius {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// 颜色变量（自动适配浅色 / 深色）
    enum Palette {
        /// 主题色：跟随设置里选的颜色（默认跟随系统）
        static var accent: Color { AccentTheme.current.color }
        static var accentSoft: Color { AccentTheme.current.color.opacity(0.14) }
        static let success = Color(light: 0x22A06B, dark: 0x4CC38A)
        static let warning = Color(light: 0xE5900B, dark: 0xF5B342)
        static let danger = Color(light: 0xE5484D, dark: 0xFF6369)
        static let info = Color(light: 0x0E9AA7, dark: 0x3DD1DB)

        /// 页面背景：不是一整块纯色，上浅下深，再叠两团很淡的光
        static let background = Color(light: 0xF4F5F8, dark: 0x0B0B0F)
        static let backgroundBottom = Color(light: 0xEEF0F5, dark: 0x111218)
        static let backgroundGlowA = Color(light: 0x5B8DEF, dark: 0x3F7BFF, opacity: 0.10)
        static let backgroundGlowB = Color(light: 0x8E7CF0, dark: 0xA25CFF, opacity: 0.08)
        /// 卡片表面（叠在毛玻璃上），要比背景明显亮一级，卡片才「浮」得起来
        static let surface = Color(light: 0xFFFFFF, dark: 0x1A1D2B, opacity: 0.84)
        static let surfaceSunken = Color(light: 0x000000, dark: 0xFFFFFF, opacity: 0.05)
        /// 图标方块：玻璃感的单色底
        static let glass = Color(light: 0x000000, dark: 0xFFFFFF, opacity: 0.06)
        static let hairline = Color(light: 0x000000, dark: 0xFFFFFF, opacity: 0.07)
        /// 图标、标签栏的单色
        static let iconPrimary = Color(light: 0x2C2C30, dark: 0xE8E8E8)
        static let iconSecondary = Color(light: 0x8A8A93, dark: 0x8A8A93)
        static let textTertiary = Color(uiColor: .tertiaryLabel)
        static let shadow = Color(light: 0x1B1F3B, dark: 0x000000, opacity: 0.08)

        /// 图标用的一组鲜艳颜色（深色背景上也亮）
        static let vivid: [Color] = [
            Color(light: 0x0A84FF, dark: 0x409CFF),   // 蓝
            Color(light: 0x5E5CE6, dark: 0x7D7AFF),   // 靛
            Color(light: 0xBF5AF2, dark: 0xDA8FFF),   // 紫
            Color(light: 0xFF375F, dark: 0xFF6482),   // 粉红
            Color(light: 0xFF9F0A, dark: 0xFFB340),   // 橙
            Color(light: 0x30B0C7, dark: 0x5DE6FF),   // 青
            Color(light: 0x30D158, dark: 0x4CE07A),   // 绿
            Color(light: 0xFF453A, dark: 0xFF6961),   // 红
        ]

        /// 图表里区分几个组（固定顺序，第 1 组永远是蓝的；深浅两套都校验过色弱也分得清）
        static let series: [Color] = [
            Color(light: 0x2A78D6, dark: 0x3987E5),   // 蓝
            Color(light: 0xEB6834, dark: 0xD95926),   // 橙
            Color(light: 0x1BAF7A, dark: 0x199E70),   // 青绿
            Color(light: 0xEDA100, dark: 0xC98500),   // 黄
            Color(light: 0xE87BA4, dark: 0xD55181),   // 品红
            Color(light: 0x008300, dark: 0x008300),   // 绿
            Color(light: 0x6250D6, dark: 0x9085E9),   // 紫
        ]

        /// 每个图标固定一种颜色（同一个功能到哪都是同一个颜色）
        static func vivid(for key: String) -> Color {
            var h: UInt32 = 2166136261
            for b in key.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
            return vivid[Int(h % UInt32(vivid.count))]
        }
    }

    /// 字体层级（全部圆体）
    enum Font {
        // 用系统文字样式：默认大小和以前一样，用户在「设置 › 显示 › 文字大小」调大时跟着变大
        static let display = SwiftUI.Font.system(.largeTitle, design: .rounded).weight(.bold)
        // 首页的大字本来就很大，不跟着放大（放大会挤出屏幕）
        static let hero = SwiftUI.Font.system(size: 56, weight: .heavy, design: .rounded)
        static let giant = SwiftUI.Font.system(size: 72, weight: .heavy, design: .rounded)
        static let title = SwiftUI.Font.system(.title2, design: .rounded).weight(.semibold)
        static let headline = SwiftUI.Font.system(.headline, design: .rounded).weight(.semibold)
        static let body = SwiftUI.Font.system(.subheadline, design: .rounded)
        static let callout = SwiftUI.Font.system(.subheadline, design: .rounded).weight(.medium)
        static let caption = SwiftUI.Font.system(.caption, design: .rounded).weight(.medium)
        static let overline = SwiftUI.Font.system(.caption2, design: .rounded).weight(.semibold)
        static let number = SwiftUI.Font.system(.title, design: .rounded).weight(.bold).monospacedDigit()
    }

    enum Motion {
        static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
        static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.75)
    }
}

/// 旧名字保留，页面里还在用
enum Theme {
    static var accent: Color { DS.Palette.accent }
    static let cardRadius: CGFloat = DS.Radius.xl

    /// 按班次颜色做的渐变（压暗一些，白字才看得清）
    static func gradient(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.blended(with: .black, 0.12), color.blended(with: .black, 0.45)],
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
    /// 浅色 / 深色两套颜色
    init(light: UInt32, dark: UInt32, opacity: Double = 1) {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: CGFloat(opacity))
        }
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }

    /// 和另一种颜色按比例混合
    func blended(with other: Color, _ amount: CGFloat) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = min(max(amount, 0), 1)
        return Color(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, opacity: a1 + (a2 - a1) * t)
    }
}

// MARK: - 背景

/// 全 App 统一背景：底色 + 两团很淡的光
struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [DS.Palette.background, DS.Palette.backgroundBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [DS.Palette.backgroundGlowA, .clear], center: UnitPoint(x: 0.15, y: 0.0),
                           startRadius: 0, endRadius: 460)
            RadialGradient(colors: [DS.Palette.backgroundGlowB, .clear], center: UnitPoint(x: 0.9, y: 0.35),
                           startRadius: 0, endRadius: 360)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// 列表、表单页面：去掉系统灰底，换成 App 背景
    func appList() -> some View {
        scrollContentBackground(.hidden)
            .background(AppBackground())
            .modifier(AvoidTabBar())
    }

    /// 普通滚动页面的背景
    func appBackground() -> some View {
        background(AppBackground())
            .modifier(AvoidTabBar())
    }
}

// MARK: - 卡片

/// 玻璃卡片：毛玻璃 + 半透明表面 + 极细描边 + 柔和阴影；浅色模式下顶边一道高光
struct CardModifier: ViewModifier {
    var tint: Color?
    var padding: CGFloat = DS.Space.m
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(DS.Palette.surface))
                    // 深色模式下卡片带一点主题色，不是一片灰
                    .overlay {
                        shape.fill(LinearGradient(colors: [(tint ?? DS.Palette.accent).opacity(scheme == .dark ? (tint == nil ? 0.10 : 0.24) : (tint == nil ? 0.02 : 0.10)),
                                                           (tint ?? DS.Palette.accent).opacity(scheme == .dark ? (tint == nil ? 0.03 : 0.10) : 0.02)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .overlay(shape.strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.10 : 0.9), DS.Palette.hairline],
                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .shadow(color: DS.Palette.shadow, radius: 24, x: 0, y: 12)
                    .shadow(color: DS.Palette.shadow.opacity(0.6), radius: 2, x: 0, y: 1)
            }
    }
}

extension View {
    func card(tint: Color? = nil, padding: CGFloat = DS.Space.m) -> some View {
        modifier(CardModifier(tint: tint, padding: padding))
    }
}

/// 卡片小标题：图标块 + 文字 + 右边可选内容
struct CardTitle<Trailing: View>: View {
    let title: String
    let icon: String
    var color: Color = DS.Palette.accent
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            IconBadge(icon: icon, color: color, size: 28)
            Text(title).font(DS.Font.headline)
            Spacer(minLength: 0)
            trailing()
        }
    }
}

extension CardTitle where Trailing == EmptyView {
    init(title: String, icon: String, color: Color = DS.Palette.accent) {
        self.init(title: title, icon: icon, color: color) { EmptyView() }
    }
}

/// 图标块：统一的单色玻璃方块 + SF Symbol。
/// color 只在需要表达状态（成功 / 警告 / 危险 / 选中）时传，平时是单色，整套界面才安静。
struct IconBadge: View {
    let icon: String
    var color: Color? = nil
    var size: CGFloat = 32
    /// 兼容旧调用，现在不再画彩色渐变底
    var filled = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        // 没指定颜色就按图标给一个固定的鲜艳颜色，不再全是灰色
        let tint = color ?? DS.Palette.vivid(for: icon)
        Image(systemName: icon)
            .font(.system(size: size * 0.44, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background {
                shape.fill(LinearGradient(colors: [tint.opacity(0.26), tint.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(shape.strokeBorder(tint.opacity(0.35), lineWidth: 0.75))
            }
    }
}

/// 小标签（无边框）
struct Chip: View {
    let text: String
    var color: Color = DS.Palette.accent
    var icon: String?

    var body: some View {
        HStack(spacing: DS.Space.xxs) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text).font(DS.Font.caption)
        }
        .padding(.horizontal, DS.Space.xs)
        .padding(.vertical, DS.Space.xxs)
        .foregroundStyle(color)
        .background(color.opacity(0.13), in: Capsule())
    }
}

/// 数字 + 说明
struct StatTile: View {
    let value: String
    let label: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(DS.Font.number).foregroundStyle(color)
            Text(label).font(DS.Font.caption).foregroundStyle(.secondary)
        }
    }
}

/// 分组小标题
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text).font(DS.Font.overline).foregroundStyle(.secondary).kerning(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.xxs)
    }
}

/// 没有内容时
struct EmptyState: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: DS.Space.s) {
            IconBadge(icon: icon, color: .secondary, size: 56)
            Text(title).font(DS.Font.headline)
            if let message {
                Text(message).font(DS.Font.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xl)
    }
}

/// 没数据时的下一步：能同步就「立即同步」，还没设置好就去设置向导
struct SyncNowButton: View {
    @EnvironmentObject private var store: AppStore
    var source = "空页面"

    var body: some View {
        if store.canSync {
            Button {
                Task { _ = await store.sync(userInitiated: true, source: source) }
            } label: {
                HStack(spacing: DS.Space.xs) {
                    if store.isSyncing { DSSpinner(size: 14) } else { Image(systemName: "arrow.triangle.2.circlepath") }
                    Text(store.isSyncing ? "正在同步…" : "立即同步")
                }
            }
            .disabled(store.isSyncing)
        } else {
            Button {
                store.settings.onboardingDone = false
            } label: {
                Label("还没连上值班网站，去设置", systemImage: "wand.and.rays")
            }
        }
    }
}

// MARK: - 按钮

/// 主按钮 / 次按钮 / 轻按钮，按下时缩小、变暗
struct DSButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, destructive }
    var kind: Kind = .primary
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        DSButtonBody(configuration: configuration, kind: kind, fullWidth: fullWidth)
    }
}

private struct DSButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: DSButtonStyle.Kind
    let fullWidth: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
        configuration.label
            .font(DS.Font.callout)
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, DS.Space.s)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .foregroundStyle(foreground)
            .background {
                switch kind {
                case .primary:
                    shape.fill(LinearGradient(colors: [DS.Palette.accent.opacity(0.88), DS.Palette.accent],
                                              startPoint: .top, endPoint: .bottom))
                        .shadow(color: DS.Palette.accent.opacity(0.3), radius: configuration.isPressed ? 4 : 10, y: 4)
                case .destructive:
                    shape.fill(DS.Palette.danger)
                case .secondary:
                    shape.fill(.ultraThinMaterial).overlay(shape.strokeBorder(DS.Palette.hairline))
                case .ghost:
                    shape.fill(configuration.isPressed ? DS.Palette.accentSoft : Color.clear)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(DS.Motion.snappy, value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .destructive: return .white
        case .secondary: return .primary
        case .ghost: return DS.Palette.accent
        }
    }
}

extension ButtonStyle where Self == DSButtonStyle {
    static var primary: DSButtonStyle { DSButtonStyle(kind: .primary) }
    static var primaryWide: DSButtonStyle { DSButtonStyle(kind: .primary, fullWidth: true) }
    static var secondary: DSButtonStyle { DSButtonStyle(kind: .secondary) }
    static var ghost: DSButtonStyle { DSButtonStyle(kind: .ghost) }
}

/// 按下时略微缩小（卡片、图块用）
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(DS.Motion.snappy, value: configuration.isPressed)
    }
}

// MARK: - 输入框

/// 圆角输入框：浅底、无边框
struct DSFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(DS.Font.body)
            .padding(DS.Space.s)
            .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
    }
}

// MARK: - Loading

/// 旋转的渐变圆环
struct DSSpinner: View {
    var size: CGFloat = 18
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 1)
            .stroke(AngularGradient(colors: [DS.Palette.accent.opacity(0), DS.Palette.accent], center: .center),
                    style: StrokeStyle(lineWidth: max(2, size * 0.14), lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

// MARK: - Toast

/// 全局轻提示：顶部毛玻璃胶囊，几秒后自动收起
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    struct Toast: Equatable {
        enum Style { case info, success, warning, error }
        var id = UUID()
        var text: String
        var style: Style
    }

    @Published private(set) var current: Toast?
    private var hideTask: Task<Void, Never>?

    func show(_ text: String, style: Toast.Style = .info, seconds: Double = 3.5) {
        withAnimation(DS.Motion.spring) { current = Toast(text: text, style: style) }
        if style == .success { Haptics.success() } else if style == .error || style == .warning { Haptics.warning() }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.spring) { self?.current = nil }
        }
    }

    func hide() { withAnimation(DS.Motion.spring) { current = nil } }
}

struct ToastOverlay: View {
    @ObservedObject private var center = ToastCenter.shared

    var body: some View {
        VStack {
            if let toast = center.current {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: icon(toast.style)).foregroundStyle(color(toast.style))
                    Text(toast.text).font(DS.Font.callout).lineLimit(3)
                }
                .padding(.horizontal, DS.Space.m)
                .padding(.vertical, DS.Space.s)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(DS.Palette.hairline))
                .shadow(color: DS.Palette.shadow, radius: 16, y: 6)
                .padding(.horizontal, DS.Space.l)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { center.hide() }
                .id(toast.id)
            }
            Spacer()
        }
        .padding(.top, DS.Space.xs)
    }

    private func icon(_ s: ToastCenter.Toast.Style) -> String {
        switch s {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func color(_ s: ToastCenter.Toast.Style) -> Color {
        switch s {
        case .info: return DS.Palette.accent
        case .success: return DS.Palette.success
        case .warning: return DS.Palette.warning
        case .error: return DS.Palette.danger
        }
    }
}

// MARK: - 触感

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// MARK: - 导航栏、标签栏外观

enum ChromeAppearance {
    /// 导航栏、标签栏：毛玻璃、圆体标题、没有分隔线
    static func apply() {
        func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
        }
        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        nav.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        nav.shadowColor = .clear
        nav.largeTitleTextAttributes = [.font: rounded(32, .bold)]
        nav.titleTextAttributes = [.font: rounded(17, .semibold)]
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.largeTitleTextAttributes = nav.largeTitleTextAttributes
        edge.titleTextAttributes = nav.titleTextAttributes
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = edge

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        tab.shadowColor = .clear
        let item = UITabBarItemAppearance()
        item.normal.titleTextAttributes = [.font: rounded(10, .medium)]
        item.selected.titleTextAttributes = [.font: rounded(10, .semibold)]
        tab.stackedLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

// MARK: - 可展开的说明文字

/// 长说明默认只露两行，点「展开说明」看全部（减少满屏文字）
struct ExpandableText: View {
    let text: String
    var lines = 2
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(text)
                .lineLimit(expanded ? nil : lines)
                .fixedSize(horizontal: false, vertical: true)
            Button(expanded ? "收起" : "展开说明") {
                Haptics.tap()
                withAnimation(DS.Motion.spring) { expanded.toggle() }
            }
            .font(DS.Font.caption)
            .foregroundStyle(DS.Palette.accent)
            .buttonStyle(.plain)
        }
    }
}

/// 一行工具图标（列表页里用）：图标块 + 名字，四个一行。
/// 列表里的 NavigationLink 会自动带箭头，所以这里用按钮，跳转交给页面上的 navigationDestination。
struct ToolGrid: View {
    struct Item {
        let title: String
        let icon: String
        let color: Color
        let destination: AnyView
    }

    let items: [Item]
    @Binding var selection: Int?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: DS.Space.s), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: DS.Space.m) {
            ForEach(items.indices, id: \.self) { i in
                Button {
                    Haptics.tap()
                    selection = i
                } label: {
                    VStack(spacing: DS.Space.xs) {
                        IconBadge(icon: items[i].icon, size: 44)
                        Text(items[i].title).font(DS.Font.caption).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.vertical, DS.Space.xs)
    }
}

// MARK: - 头像

/// 名字缩写放在渐变色圆里，每个人颜色固定
struct Avatar: View {
    let name: String
    var size: CGFloat = 32

    private var initials: String {
        let clean = name.filter { !$0.isWhitespace && $0 != "(" && $0 != "（" }
        return String(clean.count >= 3 ? clean.suffix(2) : clean.suffix(min(clean.count, 2)))
    }

    private var hue: Double {
        Double(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % 360) / 360
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * (initials.count > 1 ? 0.36 : 0.44), weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [Color(hue: hue, saturation: 0.28, brightness: 0.78),
                                        Color(hue: hue, saturation: 0.36, brightness: 0.6)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }
}


// MARK: - 微动画

/// 进场：卡片一张接一张淡入上浮（index 越大越晚）
struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                withAnimation(DS.Motion.spring.delay(Double(index) * 0.045)) { shown = true }
            }
    }
}

extension View {
    func staggered(_ index: Int) -> some View { modifier(StaggeredAppear(index: index)) }
}

/// 数字从 0 跳到目标值（Count Up）
struct CountUpText: View {
    let value: Int
    var font: Font = DS.Font.number
    @State private var shown = 0

    var body: some View {
        Text("\(shown)")
            .font(font)
            .contentTransition(.numericText())
            .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) { shown = value } }
            .onChange(of: value) { v in withAnimation(DS.Motion.spring) { shown = v } }
    }
}

/// 骨架屏：灰条带闪光，数据还没到时占位
struct SkeletonBlock: View {
    var height: CGFloat = 14
    var width: CGFloat? = nil
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
            .fill(DS.Palette.surfaceSunken)
            .frame(width: width, height: height)
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Color.white.opacity(0.25), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: phase * geo.size.width * 1.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
            }
            .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 } }
    }
}

struct SkeletonRows: View {
    var rows = 4
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            ForEach(0..<rows, id: \.self) { i in
                HStack(spacing: DS.Space.s) {
                    SkeletonBlock(height: 28, width: 28)
                    SkeletonBlock(height: 12, width: CGFloat(90 + (i * 37) % 80))
                    Spacer()
                    SkeletonBlock(height: 12, width: 40)
                }
            }
        }
        .padding(.vertical, DS.Space.xs)
    }
}

// MARK: - 悬浮标签栏

/// 悬浮在页面底部的玻璃胶囊，选中项后面有一颗会滑动的药丸
struct FloatingTabBar<Tab: Hashable>: View {
    struct Item {
        let tab: Tab
        let title: String
        let icon: String
    }

    let items: [Item]
    @Binding var selection: Tab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                let selected = item.tab == selection
                Button {
                    guard !selected else { return }
                    Haptics.select()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { selection = item.tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20, weight: selected ? .semibold : .regular))
                            .symbolRenderingMode(.hierarchical)
                            .scaleEffect(selected ? 1.08 : 1)
                        Text(item.title).font(.system(size: 10, weight: selected ? .semibold : .medium, design: .rounded))
                    }
                    .foregroundStyle(selected ? DS.Palette.accent : DS.Palette.iconSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(DS.Palette.accent.opacity(0.14))
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(DS.Space.xs)
        .background {
            let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(DS.Palette.surface.opacity(0.6)))
                .overlay(shape.strokeBorder(DS.Palette.hairline, lineWidth: 1))
                .shadow(color: DS.Palette.shadow, radius: 24, x: 0, y: 10)
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.bottom, DS.Space.xs)
        // 告诉页面标签栏的上边在哪（网页要停在它上面，不然网页底部的按钮被挡住）
        .background(GeometryReader { g in
            Color.clear.preference(key: TabBarTopKey.self, value: g.frame(in: .global).minY)
        })
    }
}

struct TabBarTopKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = min(value, nextValue()) }
}

private struct TabBarTopEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = .infinity
}

extension EnvironmentValues {
    /// 悬浮标签栏上边的位置（全局坐标）；没有标签栏时是 .infinity
    var floatingTabBarTop: CGFloat {
        get { self[TabBarTopEnvironmentKey.self] }
        set { self[TabBarTopEnvironmentKey.self] = newValue }
    }
}


/// 「工作量 5 天 | 上班 6 天」两个数字并排、一样大
struct WorkPresentPair: View {
    let work: Int
    let present: Int

    var body: some View {
        HStack(spacing: DS.Space.s) {
            item(work, "工作量")
            Rectangle().fill(DS.Palette.hairline).frame(width: 1, height: 26)
            item(present, "上班")
        }
    }

    private func item(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(value)").font(DS.Font.headline.monospacedDigit())
                Text("天").font(.caption2).foregroundStyle(.secondary)
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}


/// 不是管理员时显示「只读」提示
struct ReadOnlyNotice: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if !store.canEdit {
            Label(store.role == .manager ? "管理者只能查看，不能修改" : "只读：管理员登录后才能修改",
                  systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}


/// 只有管理员能操作的页面：顶部提示只读。
/// 按钮、输入框由各页在列表里面自己 disabled（整个列表 disabled 会连滚动都禁掉，长页面看不到下面）
struct AdminOnlyModifier: ViewModifier {
    @EnvironmentObject private var store: AppStore

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if !store.canEdit {
                    ReadOnlyNotice()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(.bar)
                } else {
                    // 管理员改的东西只在这台手机上：不会改值班网站，也不会传给同事
                    Label("这里的修改只在你这台手机上生效，不改值班网站，也不会同步给同事", systemImage: "iphone")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, DS.Space.m)
                        .padding(.vertical, 4)
                        .background(.bar)
                }
            }
    }
}

extension View {
    func adminOnly() -> some View { modifier(AdminOnlyModifier()) }
}


/// 页面被悬浮标签栏盖住多少，就在底部多留多少：列表、滚动页面最后几行能滚到标签栏上面
struct AvoidTabBar: ViewModifier {
    @Environment(\.floatingTabBarTop) private var tabBarTop
    @State private var bottom: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: tabBarTop.isFinite ? max(0, bottom - tabBarTop) : 0)
            }
            // 量的是整个页面（加了留白之后外框不变），不会来回跳
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { bottom = g.frame(in: .global).maxY }
                    .onChange(of: g.frame(in: .global).maxY) { bottom = $0 }
            })
    }
}

/// 会删掉、清空东西的按钮：先弹确认，写清楚会发生什么，防止手滑
struct ConfirmButton: View {
    let title: String
    /// 确认框里的说明
    let message: String
    var role: ButtonRole? = .destructive
    let action: () -> Void
    @State private var asking = false

    var body: some View {
        Button(title, role: role) { asking = true }
            .confirmationDialog(message, isPresented: $asking, titleVisibility: .visible) {
                Button(title, role: .destructive, action: action)
                Button("取消", role: .cancel) {}
            }
    }
}

// MARK: - 翻月 / 翻周 / 翻年

/// 翻页的统一头部：小字说明 + 大字标题，右边两个圆形箭头（统计、均衡、全年、本周全员共用）
struct PeriodPager: View {
    var caption: String?
    let title: String
    var canGoBack = true
    var canGoForward = true
    let back: () -> Void
    let forward: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.s) {
            VStack(alignment: .leading, spacing: 0) {
                if let caption { Text(caption).font(DS.Font.caption).foregroundStyle(.secondary) }
                Text(title).font(DS.Font.title)
            }
            Spacer()
            arrow("chevron.left", "上一个", enabled: canGoBack, action: back)
            arrow("chevron.right", "下一个", enabled: canGoForward, action: forward)
        }
        .buttonStyle(.plain)
    }

    private func arrow(_ icon: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: icon).font(.headline).frame(width: 36, height: 36)
                .background(DS.Palette.surfaceSunken, in: Circle())
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}

enum Period {
    /// 往前 / 往后翻几个月
    static func shiftMonth(year: Int, month: Int, by delta: Int) -> (year: Int, month: Int) {
        let index = year * 12 + (month - 1) + delta
        return (index / 12, index % 12 + 1)
    }

    /// 某天所在那一周（周一开始）往前 / 往后翻 offset 周的七天
    static func week(of day: DayKey, offset: Int) -> [DayKey] {
        let weekday = Calendar.app.component(.weekday, from: day.date(calendar: .app, hour: 12))   // 1 = 周日
        let monday = day.adding(days: -((weekday + 5) % 7) + 7 * offset)
        return (0..<7).map { monday.adding(days: $0) }
    }
}


/// 输入框先改草稿，按回车、离开输入框、离开页面或 App 退到后台时才写回去：
/// 写回设置会重排提醒、刷新小组件（班次类型还要重算整张排班），不能每打一个字就做一遍
struct DraftTextField: View {
    let title: String
    let value: String
    var axis: Axis = .horizontal
    let commit: (String) -> Void
    @State private var draft: String?
    @FocusState private var focused: Bool
    @Environment(\.scenePhase) private var scenePhase

    init(_ title: String, value: String, axis: Axis = .horizontal, commit: @escaping (String) -> Void) {
        self.title = title
        self.value = value
        self.axis = axis
        self.commit = commit
    }

    var body: some View {
        TextField(title, text: Binding(get: { draft ?? value }, set: { draft = $0 }), axis: axis)
            .focused($focused)
            .onSubmit(save)
            .onChange(of: focused) { if !$0 { save() } }
            .onChange(of: scenePhase) { if $0 != .active { save() } }
            .onDisappear(perform: save)
    }

    private func save() {
        guard let text = draft else { return }
        draft = nil
        if text != value { commit(text) }
    }
}
