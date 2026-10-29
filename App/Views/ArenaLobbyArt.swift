import SwiftUI

/// Small, bundled templates: no network loading, runtime SVG parsing or extra SCNView.
struct ArenaLobbyIcon: View {
    let asset: String
    init(_ asset: String) { self.asset = asset }
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 40, y: size.height / 40)
            let ink = Color(red: 0.06, green: 0.08, blue: 0.16)
            func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
                let p = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: 2)
                context.fill(p, with: .color(color)); context.stroke(p, with: .color(ink), lineWidth: 1.8)
            }
            func disc(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ color: Color) {
                let p = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                context.fill(p, with: .color(color)); context.stroke(p, with: .color(ink), lineWidth: 1.5)
            }
            func face(_ x: CGFloat, _ y: CGFloat, _ color: Color) {
                disc(x, y, 7, color)
                disc(x - 2.5, y - 1, 1.3, ink); disc(x + 2.5, y - 1, 1.3, ink)
                box(x - 2.5, y + 2, 5, 2, ink)
            }
            switch asset {
            case "ArenaIconShop":
                box(7, 13, 27, 23, .cyan); box(16, 22, 9, 14, Color(red: 0.1, green: 0.25, blue: 0.5))
                for i in 0..<4 { box(4 + CGFloat(i) * 8, 5, 8, 13, i % 2 == 0 ? .red : .white) }
            case "ArenaIconHero":
                box(2, 9, 17, 25, .cyan); box(13, 3, 17, 27, .yellow); box(24, 12, 14, 24, .pink)
                face(11, 20, .white); face(22, 14, .orange); face(31, 23, .purple)
            case "ArenaIconFriends":
                box(5, 5, 30, 28, Color(red: 1, green: 0.70, blue: 0.24))
                face(20, 18, .yellow)
            case "ArenaIconParty":
                box(2, 15, 12, 21, .yellow); box(13, 4, 14, 29, .green); box(27, 13, 12, 23, .cyan)
                face(8, 23, .yellow); face(20, 14, .green); face(33, 22, .cyan)
            case "ArenaIconSeason":
                box(7, 15, 27, 22, .cyan); box(5, 11, 31, 8, .purple); box(18, 11, 6, 26, .pink)
                disc(15, 7, 5, .pink); disc(26, 7, 5, .pink)
            case "ArenaIconCoins":
                disc(20, 21, 16, .orange); disc(20, 19, 13, .yellow); face(20, 19, .yellow)
            case "ArenaIconTrophy":
                box(15, 28, 10, 8, .orange); box(10, 34, 20, 4, .yellow)
                disc(9, 13, 7, .orange); disc(31, 13, 7, .orange); box(10, 4, 20, 22, .yellow)
            case "ArenaIconBattle":
                let points = [CGPoint(x: 20, y: 1), CGPoint(x: 36, y: 10), CGPoint(x: 33, y: 29), CGPoint(x: 20, y: 39), CGPoint(x: 5, y: 29), CGPoint(x: 3, y: 10)]
                var p = Path(); p.addLines(points); p.closeSubpath()
                context.fill(p, with: .color(.purple)); context.stroke(p, with: .color(.white), lineWidth: 2)
                box(17, 8, 6, 23, .pink); box(10, 16, 20, 5, .pink)
            default:
                let image = context.resolve(Image(asset).renderingMode(.original))
                context.draw(image, in: CGRect(x: 0, y: 0, width: 40, height: 40))
            }
        }.accessibilityHidden(true)
    }
}

struct ArenaLobbyEmblem {
    let asset: String
    let tint: Color
    static func menu(_ symbol: String) -> Self {
        switch symbol {
        case "flag.checkered": return .init(asset: "ArenaIconAdventure", tint: Color(red: 1, green: 0.77, blue: 0.32))
        case "person.crop.square.fill": return .init(asset: "ArenaIconHero", tint: Color(red: 0.54, green: 0.87, blue: 1))
        case "star.circle.fill": return .init(asset: "ArenaIconSeason", tint: Color(red: 1, green: 0.80, blue: 0.27))
        case "gearshape.fill": return .init(asset: "ArenaIconSettings", tint: Color(red: 0.72, green: 0.79, blue: 0.97))
        case "bag.fill": return .init(asset: "ArenaIconShop", tint: Color(red: 1, green: 0.69, blue: 0.35))
        case "person.2.fill": return .init(asset: "ArenaIconFriends", tint: Color(red: 0.57, green: 0.93, blue: 0.81))
        case "person.3.fill": return .init(asset: "ArenaIconParty", tint: Color(red: 0.70, green: 0.78, blue: 1))
        default: return .init(asset: "ArenaIconSkill", tint: Color(red: 0.92, green: 0.66, blue: 1))
        }
    }
}

/// Solid enamel face, ink edge, bevel and a short physical press. Shadows never include text.
struct ArenaLobbyButtonStyle: ButtonStyle {
    let tint: Color
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(primary ? Color(red: 0.24, green: 0.13, blue: 0.05) : .white)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: primary
                        ? [Color(red: 1, green: 0.88, blue: 0.34), Color(red: 1, green: 0.66, blue: 0.12)]
                        : [Color(red: 0.22, green: 0.29, blue: 0.40), Color(red: 0.10, green: 0.16, blue: 0.26)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4).strokeBorder(Color(red: 0.025, green: 0.045, blue: 0.12), lineWidth: 2.5)
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 2).fill(.white.opacity(primary ? 0.5 : 0.18))
                            .frame(height: 2).padding(.horizontal, 10).padding(.top, 4)
                    }
                    .shadow(color: Color(red: 0.035, green: 0.055, blue: 0.16), radius: 0,
                            y: configuration.isPressed ? 1 : 4)
            }
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Original, static arena backdrop. Broad value groups leave the hero silhouette clear.
/// The architecture stays at the edges; no decorative animation competes with character playback.
struct ArenaLobbyBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(red: 0.01, green: 0.09, blue: 0.56),
                                        Color(red: 0.02, green: 0.22, blue: 0.91),
                                        Color(red: 0.36, green: 0.12, blue: 0.72)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color.purple.opacity(0.9), .clear], center: UnitPoint(x: 0.5, y: 0.52),
                               startRadius: 0, endRadius: geo.size.height * 0.53)
                Canvas { context, size in
                    let w = size.width, h = size.height
                    let moon = CGRect(x: w * 0.5 - h * 0.31, y: h * 0.16, width: h * 0.62, height: h * 0.62)
                    context.fill(Path(ellipseIn: moon.insetBy(dx: -8, dy: -8)), with: .color(Color.pink.opacity(0.14)))
                    context.fill(Path(ellipseIn: moon), with: .color(Color(red: 1, green: 0.88, blue: 0.89)))
                    // Three depths of angular skyline; the center stays clear for the hero.
                    for layer in 0..<3 {
                        let base = h * (0.72 + CGFloat(layer) * 0.08)
                        for i in 0..<18 {
                            let x = CGFloat(i) * w / 17 - w * 0.03
                            let central = abs(x + w * 0.03 - w * 0.5) < h * 0.23
                            let roof = h * (0.10 + CGFloat((i * 7 + layer * 11) % 9) * 0.018) * (central ? 0.28 : 1)
                            let rect = CGRect(x: x, y: base - roof, width: w * 0.066, height: h - base + roof)
                            let blue = 0.39 - Double(layer) * 0.09
                            context.fill(Path(rect), with: .color(Color(red: 0.025, green: 0.065, blue: blue)))
                            context.fill(Path(CGRect(x: x, y: base - roof, width: 3, height: roof)),
                                         with: .color(Color(red: 0.57, green: 0.24, blue: 0.89).opacity(layer == 0 ? 0.8 : 0.35)))
                            if i % 3 == 0 {
                                context.fill(Path(CGRect(x: x + w * 0.025, y: base - roof - h * 0.05,
                                                         width: 3, height: h * 0.05)), with: .color(Color(red: 0.04, green: 0.07, blue: blue)))
                            }
                        }
                    }
                    var floor = Path()
                    floor.move(to: CGPoint(x: w * 0.30, y: h * 0.76))
                    floor.addLine(to: CGPoint(x: w * 0.70, y: h * 0.76))
                    floor.addLine(to: CGPoint(x: w * 0.94, y: h))
                    floor.addLine(to: CGPoint(x: w * 0.06, y: h))
                    floor.closeSubpath()
                    context.fill(floor, with: .linearGradient(Gradient(colors: [Color(red: 0.13, green: 0.11, blue: 0.34),
                                                                                               Color(red: 0.025, green: 0.06, blue: 0.17)]),
                                                              startPoint: CGPoint(x: 0, y: h * 0.76), endPoint: CGPoint(x: 0, y: h)))
                }
                LinearGradient(colors: [.black.opacity(0.25), .clear, .clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Compact rail plate: the emblem protrudes above the lower label plate.
struct ArenaLobbyRailStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.28, blue: 0.43),
                                                  Color(red: 0.08, green: 0.13, blue: 0.26)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: 31)
                    .overlay(alignment: .top) { Color.white.opacity(0.18).frame(height: 1) }
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.65), lineWidth: 2))
                    .shadow(color: .black.opacity(0.5), radius: 0, y: 3)
            }
            .contentShape(Rectangle())
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
