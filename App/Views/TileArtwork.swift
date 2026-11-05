import SwiftUI

enum TileTheme {
    static let navy = Color(red: 0.055, green: 0.09, blue: 0.18)
    static let panel = Color(red: 0.12, green: 0.18, blue: 0.31)
    static let ink = Color(red: 0.16, green: 0.22, blue: 0.34)
    static let mint = Color(red: 0.46, green: 0.90, blue: 0.79)
    static let gold = Color(red: 1, green: 0.79, blue: 0.40)
    static let names = ["卫星", "天线", "火箭", "地球", "月亮", "星星", "太阳", "土星", "彗星", "望远镜", "飞碟", "太空舱"]
    static let accents: [Color] = [.init(red: 0.28, green: 0.65, blue: 0.85), .init(red: 0.42, green: 0.68, blue: 0.72),
        .init(red: 0.96, green: 0.43, blue: 0.37), .init(red: 0.25, green: 0.67, blue: 0.65),
        .init(red: 0.54, green: 0.51, blue: 0.82), .init(red: 0.94, green: 0.66, blue: 0.24),
        .init(red: 0.99, green: 0.54, blue: 0.25), .init(red: 0.76, green: 0.48, blue: 0.65),
        .init(red: 0.32, green: 0.63, blue: 0.84), .init(red: 0.38, green: 0.57, blue: 0.79),
        .init(red: 0.38, green: 0.73, blue: 0.52), .init(red: 0.66, green: 0.47, blue: 0.78)]
    static func title(_ level: TileGame.Level) -> String {
        switch level { case .easy: return "轻松"; case .normal: return "进阶"; case .hard: return "大师" }
    }
}

/// 静态星幕：没有逐帧计时器，移动牌时也不重新生成随机背景。
struct TileStarfield: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.14, green: 0.22, blue: 0.38), TileTheme.navy], startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { context, size in
                for i in 0..<65 {
                    let x = CGFloat((i * 197 + 17) % 997) / 997 * size.width
                    let y = CGFloat((i * 293 + 71) % 991) / 991 * size.height
                    let r: CGFloat = i % 7 == 0 ? 1.8 : 0.8
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(.white.opacity(i % 3 == 0 ? 0.35 : 0.12)))
                }
                for i in 0..<3 {
                    let rect = CGRect(x: size.width * 0.24 - CGFloat(i) * 32, y: size.height * 0.12,
                                      width: size.width * 1.2, height: size.width * 1.2)
                    context.stroke(Path(ellipseIn: rect), with: .color(TileTheme.mint.opacity(0.045)), lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// 原生矢量插画：统一线宽、色盘和高光，在小牌面上保持轮廓，不依赖 Emoji 字体。
struct TileGlyph: View {
    let kind: Int
    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                let scale = min(size.width, size.height) / 100
                cg.translateBy(x: (size.width - 100 * scale) / 2, y: (size.height - 100 * scale) / 2)
                cg.scaleBy(x: scale, y: scale)
                Self.draw(kind: ((kind % 12) + 12) % 12, in: cg)
            }
        }
        .accessibilityHidden(true)
    }

    private static func draw(kind: Int, in g: CGContext) {
        func color(_ hex: UInt32) -> CGColor {
            CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
        func shape(_ path: CGPath, _ fill: UInt32, stroke: Bool = true) {
            g.addPath(path); g.setFillColor(color(fill))
            g.setStrokeColor(color(0x304761)); g.setLineWidth(2.4); g.setLineJoin(.round)
            g.drawPath(using: stroke ? .fillStroke : .fill)
        }
        func ellipse(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ fill: UInt32, stroke: Bool = true) {
            shape(CGPath(ellipseIn: CGRect(x: x, y: y, width: w, height: h), transform: nil), fill, stroke: stroke)
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ fill: UInt32, radius: CGFloat = 4) {
            shape(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: radius, cornerHeight: radius, transform: nil), fill)
        }
        func poly(_ points: [(CGFloat, CGFloat)], _ fill: UInt32, stroke: Bool = true) {
            let p = CGMutablePath(); p.move(to: CGPoint(x: points[0].0, y: points[0].1))
            for v in points.dropFirst() { p.addLine(to: CGPoint(x: v.0, y: v.1)) }; p.closeSubpath()
            shape(p, fill, stroke: stroke)
        }
        func line(_ points: [(CGFloat, CGFloat)], _ hex: UInt32 = 0x304761, width: CGFloat = 3) {
            g.beginPath(); g.move(to: CGPoint(x: points[0].0, y: points[0].1))
            for v in points.dropFirst() { g.addLine(to: CGPoint(x: v.0, y: v.1)) }
            g.setStrokeColor(color(hex)); g.setLineWidth(width); g.setLineCap(.round); g.strokePath()
        }
        func star(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ fill: UInt32) {
            poly((0..<10).map { i in
                let angle = CGFloat(i) * .pi / 5 - .pi / 2, radius = i.isMultiple(of: 2) ? r : r * 0.46
                return (cx + cos(angle) * radius, cy + sin(angle) * radius)
            }, fill)
        }
        switch kind {
        case 0: // 卫星
            g.translateBy(x: 50, y: 50); g.rotate(by: -.pi / 7); g.translateBy(x: -50, y: -50)
            box(9, 33, 25, 34, 0x4599CC, radius: 3); box(66, 33, 25, 34, 0x4599CC, radius: 3)
            for x: CGFloat in [17, 26, 74, 83] { line([(x, 35), (x, 65)], 0xB4E4F1, width: 1.6) }
            line([(11, 50), (89, 50)], 0xB4E4F1, width: 1.6)
            box(35, 27, 30, 45, 0xF4CA72); box(42, 34, 16, 15, 0xFFF4D7)
            line([(50, 27), (50, 16)]); ellipse(46, 10, 8, 8, 0xEF8C65)
        case 1: // 天线
            poly([(42, 76), (52, 48), (62, 76)], 0x668E9E); box(27, 76, 48, 8, 0x9FC8CF)
            let dish = CGMutablePath(); dish.move(to: CGPoint(x: 23, y: 30))
            dish.addQuadCurve(to: CGPoint(x: 76, y: 65), control: CGPoint(x: 20, y: 86))
            dish.addLine(to: CGPoint(x: 23, y: 30)); shape(dish, 0xAEE6DF)
            line([(45, 51), (65, 29)]); ellipse(61, 23, 9, 9, 0xF3BD64)
            line([(74, 23), (82, 29), (86, 38)], 0x5CA6B3, width: 3)
            line([(79, 14), (91, 24), (96, 37)], 0x5CA6B3, width: 2)
        case 2: // 火箭
            poly([(39, 69), (50, 94), (61, 69)], 0xFFBC5F, stroke: false)
            poly([(32, 47), (20, 73), (39, 67)], 0xE97468); poly([(68, 47), (80, 73), (61, 67)], 0xE97468)
            let p = CGMutablePath(); p.move(to: CGPoint(x: 50, y: 9))
            p.addCurve(to: CGPoint(x: 66, y: 73), control1: CGPoint(x: 73, y: 27), control2: CGPoint(x: 72, y: 56))
            p.addLine(to: CGPoint(x: 34, y: 73)); p.addCurve(to: CGPoint(x: 50, y: 9), control1: CGPoint(x: 28, y: 56), control2: CGPoint(x: 27, y: 27))
            shape(p, 0xFFF5DA); poly([(38, 25), (50, 9), (62, 25)], 0xEE8270)
            ellipse(39, 35, 22, 22, 0x62B6CD); ellipse(44, 39, 7, 6, 0xDDF7ED, stroke: false)
            line([(39, 69), (61, 69)], 0xD58068, width: 4)
        case 3: // 地球
            ellipse(14, 14, 72, 72, 0x4B9BC6)
            g.saveGState(); g.addEllipse(in: CGRect(x: 15, y: 15, width: 70, height: 70)); g.clip()
            poly([(20, 24), (42, 19), (53, 31), (44, 44), (29, 45), (26, 58), (12, 45)], 0xA2D7A4, stroke: false)
            poly([(57, 49), (78, 44), (89, 65), (73, 79), (55, 67), (48, 56)], 0xA2D7A4, stroke: false)
            g.restoreGState(); line([(30, 25), (39, 22)], 0xD7F2E0, width: 4)
        case 4: // 月亮
            let p = CGMutablePath(); p.move(to: CGPoint(x: 65, y: 14))
            p.addCurve(to: CGPoint(x: 83, y: 69), control1: CGPoint(x: 26, y: 28), control2: CGPoint(x: 45, y: 78))
            p.addCurve(to: CGPoint(x: 65, y: 14), control1: CGPoint(x: 13, y: 109), control2: CGPoint(x: 3, y: 18))
            shape(p, 0xBDB4E8); ellipse(24, 47, 10, 10, 0x9B91CE, stroke: false)
            ellipse(36, 66, 7, 7, 0x9B91CE, stroke: false); star(76, 29, 12, 0xF9D57D)
        case 5:
            star(50, 49, 39, 0xF6C55F); line([(43, 30), (48, 19), (54, 32)], 0xFFE9AE, width: 4)
            ellipse(39, 47, 4, 6, 0x5C5965, stroke: false); ellipse(57, 47, 4, 6, 0x5C5965, stroke: false)
            line([(46, 60), (50, 63), (54, 60)], 0x9F7646, width: 2)
        case 6:
            for i in 0..<10 {
                let a = CGFloat(i) * .pi / 5
                line([(50 + cos(a) * 34, 50 + sin(a) * 34), (50 + cos(a) * 43, 50 + sin(a) * 43)], 0xD88942, width: 4)
            }
            ellipse(23, 23, 54, 54, 0xF2A64D); ellipse(30, 29, 19, 13, 0xFFD98B, stroke: false)
        case 7:
            ellipse(23, 20, 54, 58, 0xD5A2BF)
            line([(30, 38), (69, 34)], 0xEFC9D6, width: 5); line([(29, 48), (71, 44)], 0xB37B9B, width: 4)
            let ring = CGMutablePath(); ring.move(to: CGPoint(x: 25, y: 47))
            ring.addCurve(to: CGPoint(x: 89, y: 36), control1: CGPoint(x: -24, y: 88), control2: CGPoint(x: 100, y: 80))
            g.addPath(ring); g.setStrokeColor(color(0x304761)); g.setLineWidth(10); g.strokePath()
            g.addPath(ring); g.setStrokeColor(color(0xEDC482)); g.setLineWidth(6); g.strokePath()
        case 8:
            poly([(12, 79), (75, 14), (63, 50), (90, 28), (63, 74)], 0x9FD8E9, stroke: false)
            line([(24, 69), (66, 27)], 0xD9F4EF, width: 5); ellipse(18, 48, 36, 36, 0x559CCC)
            ellipse(25, 54, 12, 10, 0xB8E5EA, stroke: false)
        case 9:
            line([(50, 56), (30, 86)]); line([(50, 56), (72, 86)]); line([(50, 56), (50, 85)])
            g.saveGState(); g.translateBy(x: 50, y: 40); g.rotate(by: -.pi / 7); g.translateBy(x: -50, y: -40)
            box(18, 29, 57, 24, 0x7FA4D2); box(69, 24, 14, 34, 0xF3C77D)
            box(12, 34, 10, 14, 0x526E91); line([(26, 34), (60, 34)], 0xBCD6E9, width: 3); g.restoreGState()
        case 10:
            ellipse(32, 18, 37, 40, 0x9ADBCB); ellipse(39, 24, 12, 11, 0xE2F6DB, stroke: false)
            ellipse(9, 43, 82, 26, 0x67B487); ellipse(17, 45, 66, 10, 0xACE0A4, stroke: false)
            for x: CGFloat in [29, 47, 65] { ellipse(x, 56, 7, 5, 0xFADEA0, stroke: false) }
            line([(34, 76), (28, 85)], 0x94C8B6); line([(66, 76), (72, 85)], 0x94C8B6)
        default:
            box(26, 17, 48, 65, 0xBEA5DD, radius: 22); box(33, 27, 34, 31, 0x425B7D, radius: 12)
            ellipse(40, 33, 13, 10, 0xA6D9DD, stroke: false); line([(38, 68), (62, 68)], 0xEDE0F3, width: 4)
            box(16, 47, 10, 22, 0x997BBE); box(74, 47, 10, 22, 0x997BBE)
        }
    }
}

struct TileFace: View {
    let kind: Int
    let side: CGFloat
    var covered = false
    var glowing = false

    var body: some View {
        let index = ((kind % 12) + 12) % 12
        let shape = RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
        ZStack {
            shape.fill(Color(red: 0.56, green: 0.60, blue: 0.64)).offset(y: side * 0.065)
            shape.fill(LinearGradient(colors: [Color(red: 1, green: 0.99, blue: 0.94), Color(red: 0.90, green: 0.92, blue: 0.88)], startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.strokeBorder(.white.opacity(0.95), lineWidth: max(1, side * 0.025))
            RoundedRectangle(cornerRadius: side * 0.17).fill(TileTheme.accents[index].opacity(0.1))
                .padding(side * 0.09)
            TileGlyph(kind: kind).padding(side * 0.12)
            if covered { shape.fill(TileTheme.navy.opacity(0.46)) }
            if glowing { shape.strokeBorder(TileTheme.gold, lineWidth: 3) }
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(covered ? 0.12 : 0.25), radius: side * 0.035, x: 0, y: side * 0.06)
        .scaleEffect(glowing ? 1.08 : 1)
        .accessibilityLabel("\(TileTheme.names[index])，\(covered ? "被压住" : "可选")")
    }
}

struct TileStars: View {
    let count: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { i in
                Image(systemName: "star.fill").foregroundStyle(i <= count ? TileTheme.gold : .white.opacity(0.16))
            }
        }
        .font(.system(size: 11, weight: .bold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) 星")
    }
}

struct TilePrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.headline, design: .rounded).weight(.bold))
            .foregroundStyle(TileTheme.ink).padding(.vertical, 16).frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [TileTheme.mint, Color(red: 0.33, green: 0.77, blue: 0.70)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
