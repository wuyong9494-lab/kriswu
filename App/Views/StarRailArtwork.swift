import SwiftUI

enum RailPalette {
    static let ink = Color(red: 0.035, green: 0.065, blue: 0.13)
    static let board = Color(red: 0.08, green: 0.13, blue: 0.23)
    static let rim = Color(red: 0.20, green: 0.30, blue: 0.43)
    static let lilac = Color(red: 0.72, green: 0.66, blue: 1)
    static func rail(_ id: Int) -> Color { id == 0 ? TileTheme.mint : TileTheme.gold }
    static func chapter(_ id: Int) -> String { id <= 2 ? "初识变轨" : id <= 4 ? "留槽谋划" : "双轨回环" }
}

/// Code-native ceramic faces reuse the twelve original vector illustrations.
/// Their silhouette, highlight and rail badges remain legible without images.
struct RailTileFace: View {
    let kind: Int
    let side: CGFloat
    var covered = false
    var rail: Int?
    var layer = 0
    var anchor = false
    var highlight: Color = .clear
    var back: StarRail.CardBack = .starlines

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.21, style: .continuous)
        ZStack {
            RailCardBack(style: back, side: side).offset(y: side * 0.10)
            shape.fill(LinearGradient(colors: [Color(red: 1, green: 0.985, blue: 0.91),
                                                Color(red: 0.82, green: 0.91, blue: 0.89)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.strokeBorder(StarRailStyle.accent(back).opacity(0.8), lineWidth: 1.6)
            RoundedRectangle(cornerRadius: side * 0.14)
                .fill(TileTheme.accents[kind % 12].opacity(0.13)).padding(side * 0.09)
            TileGlyph(kind: kind).padding(side * 0.13)
            if covered { shape.fill(RailPalette.ink.opacity(0.42)) }
            shape.strokeBorder(highlight, lineWidth: 3)
        }
        .frame(width: side, height: side)
        .overlay(alignment: .topLeading) {
            if let rail {
                Text("\(rail == 0 ? "A" : "B")·\(layer)")
                    .font(.system(size: max(9, side * 0.16), weight: .black, design: .rounded))
                    .foregroundStyle(RailPalette.ink).padding(.horizontal, 5).padding(.vertical, 3)
                    .background(RailPalette.rail(rail), in: Capsule()).offset(x: -2, y: -3)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if anchor {
                Image(systemName: "pin.fill").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white).padding(5)
                    .background(RailPalette.ink.opacity(0.92), in: Circle()).offset(x: 2, y: 3)
            }
        }
        .shadow(color: .black.opacity(covered ? 0.16 : 0.34), radius: 3 + CGFloat(layer), x: 0, y: 3 + CGFloat(layer) * 2)
        .accessibilityHidden(true)
    }
}

struct RailBoardBackdrop: View {
    let columns: Int
    let rows: Int
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 25)
                .fill(LinearGradient(colors: [RailPalette.rim, RailPalette.ink], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.38), radius: 14, y: 8)
            RoundedRectangle(cornerRadius: 21).fill(RailPalette.board).padding(4)
            RoundedRectangle(cornerRadius: 25).strokeBorder(.white.opacity(0.16), lineWidth: 1)
            Canvas { context, size in
                let w = (size.width - 32) / CGFloat(columns)
                let h = (size.height - 32) / CGFloat(rows)
                for row in 0..<rows {
                    for col in 0..<columns {
                        let r = CGRect(x: 16 + CGFloat(col) * w + 3, y: 16 + CGFloat(row) * h + 3,
                                       width: max(0, w - 6), height: max(0, h - 6))
                        context.stroke(Path(roundedRect: r, cornerRadius: 10), with: .color(.white.opacity(0.045)), lineWidth: 1)
                    }
                }
            }
            .padding(4)
        }
        .accessibilityHidden(true)
    }
}

struct RailEnergyMeter: View {
    let value: Int
    var limit = 2
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "bolt.fill").foregroundStyle(TileTheme.gold)
            ForEach(0..<limit, id: \.self) { index in
                Capsule().fill(index < value ? TileTheme.gold : .white.opacity(0.09))
                    .frame(width: 24, height: 10)
                    .overlay(Capsule().strokeBorder(TileTheme.gold.opacity(0.28), lineWidth: 1))
            }
            Text("\(value)/\(limit)").font(.caption.monospacedDigit().bold()).foregroundStyle(TileTheme.gold)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(TileTheme.gold.opacity(0.08), in: Capsule())
        .accessibilityElement(children: .ignore).accessibilityLabel("能量 \(value)，上限 \(limit)")
    }
}

struct RailHomeArtwork: View {
    var back: StarRail.CardBack = .starlines
    var body: some View {
        ZStack {
            Ellipse().stroke(TileTheme.mint.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4, 7]))
                .frame(width: 154, height: 92).rotationEffect(.degrees(-24))
            Ellipse().stroke(RailPalette.lilac.opacity(0.22), lineWidth: 1)
                .frame(width: 116, height: 142).rotationEffect(.degrees(28))
            RailTileFace(kind: 7, side: 56, rail: 1, layer: 2, back: back).rotationEffect(.degrees(13)).offset(x: 33, y: -21)
            RailTileFace(kind: 2, side: 61, rail: 0, layer: 1, back: back).rotationEffect(.degrees(-12)).offset(x: -29, y: 16)
            Circle().fill(TileTheme.gold).frame(width: 6, height: 6).offset(x: 62, y: 36)
        }
        .frame(width: 160, height: 155).accessibilityHidden(true)
    }
}
