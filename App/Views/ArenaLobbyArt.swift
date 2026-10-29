import SwiftUI

/// Small, bundled templates: no network loading, runtime SVG parsing or extra SCNView.
struct ArenaLobbyIcon: View {
    let asset: String
    init(_ asset: String) { self.asset = asset }
    var body: some View {
        Image(asset).renderingMode(.template).resizable().scaledToFit().accessibilityHidden(true)
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
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: primary
                        ? [Color(red: 1, green: 0.88, blue: 0.34), Color(red: 1, green: 0.66, blue: 0.12)]
                        : [Color(red: 0.20, green: 0.29, blue: 0.56), Color(red: 0.10, green: 0.16, blue: 0.36)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(primary ? 0.8 : 0.6), lineWidth: 2)
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
                LinearGradient(colors: [Color(red: 0.12, green: 0.20, blue: 0.48),
                                        Color(red: 0.26, green: 0.39, blue: 0.70),
                                        Color(red: 0.40, green: 0.31, blue: 0.60)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(red: 0.56, green: 0.77, blue: 0.94).opacity(0.55), .clear],
                               center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: geo.size.width * 0.46)
                Canvas { context, size in
                    let w = size.width, h = size.height
                    // Subtle rays and a distant arched arena, with a quiet central stage.
                    let center = CGPoint(x: w * 0.5, y: h * 0.62)
                    for i in 0..<9 {
                        let x = CGFloat(i) * w / 8
                        var ray = Path()
                        ray.move(to: center)
                        ray.addLine(to: CGPoint(x: x - w * 0.025, y: 0))
                        ray.addLine(to: CGPoint(x: x + w * 0.025, y: 0))
                        ray.closeSubpath()
                        context.fill(ray, with: .color(.white.opacity(0.035)))
                    }
                    for side in 0..<2 {
                        for tower in 0..<3 {
                            let x = side == 0 ? CGFloat(tower) * w * 0.095 - w * 0.035
                                : w - CGFloat(tower + 1) * w * 0.095 + w * 0.035
                            let top = h * (0.27 + CGFloat(tower) * 0.10)
                            let rect = CGRect(x: x, y: top, width: w * 0.08, height: h - top)
                            context.fill(Path(rect), with: .color(Color(red: 0.12, green: 0.20, blue: 0.42).opacity(0.5)))
                            context.fill(Path(CGRect(x: x - w * 0.006, y: top, width: w * 0.092, height: h * 0.025)),
                                         with: .color(Color(red: 0.40, green: 0.52, blue: 0.74).opacity(0.6)))
                            let banner = CGRect(x: x + w * 0.023, y: top + h * 0.06,
                                                width: w * 0.034, height: h * 0.16)
                            context.fill(Path(roundedRect: banner, cornerRadius: 3),
                                         with: .color(Color(red: 0.40, green: 0.26, blue: 0.56).opacity(0.65)))
                        }
                    }
                    let floor = CGRect(x: -w * 0.15, y: h * 0.73, width: w * 1.3, height: h * 0.65)
                    context.fill(Path(ellipseIn: floor), with: .color(Color(red: 0.17, green: 0.22, blue: 0.43)))
                    context.stroke(Path(ellipseIn: floor), with: .color(Color(red: 0.48, green: 0.58, blue: 0.79).opacity(0.45)), lineWidth: 3)
                    let inner = CGRect(x: w * 0.22, y: h * 0.77, width: w * 0.56, height: h * 0.23)
                    context.fill(Path(ellipseIn: inner), with: .color(Color(red: 0.35, green: 0.38, blue: 0.60)))
                    context.stroke(Path(ellipseIn: inner), with: .color(.white.opacity(0.12)), lineWidth: 2)
                }
                LinearGradient(colors: [.black.opacity(0.22), .clear, .clear, .black.opacity(0.18)],
                               startPoint: .top, endPoint: .bottom)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
