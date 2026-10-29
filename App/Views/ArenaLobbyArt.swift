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
            case "ArenaIconClub":
                var shield = Path()
                shield.addLines([CGPoint(x: 5, y: 5), CGPoint(x: 35, y: 5), CGPoint(x: 33, y: 27), CGPoint(x: 20, y: 38), CGPoint(x: 7, y: 27)])
                shield.closeSubpath()
                context.fill(shield, with: .color(.purple)); context.stroke(shield, with: .color(ink), lineWidth: 2)
                var star = Path()
                for point in 0..<10 {
                    let angle = CGFloat(point) * .pi / 5 - .pi / 2
                    let radius: CGFloat = point % 2 == 0 ? 10 : 4.5
                    let p = CGPoint(x: 20 + cos(angle) * radius, y: 20 + sin(angle) * radius)
                    if point == 0 { star.move(to: p) } else { star.addLine(to: p) }
                }
                star.closeSubpath(); context.fill(star, with: .color(.white))
            case "ArenaIconUpgrade":
                disc(20, 20, 17, Color(red: 0.18, green: 0.83, blue: 0.20))
                var arrow = Path()
                arrow.addLines([CGPoint(x: 20, y: 6), CGPoint(x: 32, y: 21), CGPoint(x: 25, y: 21), CGPoint(x: 25, y: 32), CGPoint(x: 15, y: 32), CGPoint(x: 15, y: 21), CGPoint(x: 8, y: 21)])
                arrow.closeSubpath(); context.fill(arrow, with: .color(.white)); context.stroke(arrow, with: .color(ink), lineWidth: 1.5)
            case "ArenaIconRank":
                var medal = Path()
                medal.addLines([CGPoint(x: 20, y: 2), CGPoint(x: 35, y: 10), CGPoint(x: 33, y: 29), CGPoint(x: 20, y: 38), CGPoint(x: 7, y: 29), CGPoint(x: 5, y: 10)])
                medal.closeSubpath()
                context.fill(medal, with: .color(.purple)); context.stroke(medal, with: .color(.pink), lineWidth: 3)
                disc(20, 19, 8, .yellow)
            case "ArenaIconPass":
                box(2, 7, 36, 27, .yellow)
                disc(20, 21, 7, ink)
                for x: CGFloat in [11, 20, 29] { disc(x, 12, 2, ink) }
            case "ArenaIconQuest":
                box(8, 8, 25, 29, .orange); box(5, 5, 25, 29, .cyan)
                var check = Path()
                check.addLines([CGPoint(x: 10, y: 20), CGPoint(x: 16, y: 26), CGPoint(x: 26, y: 12)])
                context.stroke(check, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
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
        case "shield.fill": return .init(asset: "ArenaIconClub", tint: .purple)
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
                ArenaLobbyPlate()
                    .fill(LinearGradient(colors: primary
                        ? [Color(red: 1, green: 0.88, blue: 0.34), Color(red: 1, green: 0.66, blue: 0.12)]
                        : [Color(red: 0.22, green: 0.29, blue: 0.40), Color(red: 0.10, green: 0.16, blue: 0.26)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay {
                        ArenaLobbyPlate().stroke(Color(red: 0.025, green: 0.045, blue: 0.12), lineWidth: 2.5)
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

/// Bundled moon-city artwork: one static image, with live controls and 3D hero above it.
struct ArenaLobbyBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.025, green: 0.10, blue: 0.62)
                // Stretch only the outer extension. The center uses image-height
                // coordinates so the moon stays circular and the rooftop stays at
                // the same vertical anchor on phones and tablets.
                Image("ArenaLobbyMoonCity").resizable()
                    .frame(width: geo.size.width, height: geo.size.height)
                Image("ArenaLobbyMoonCity").resizable()
                    .frame(width: geo.size.height * (1672.0 / 941.0), height: geo.size.height)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                                 .init(color: .white, location: 0.06),
                                                 .init(color: .white, location: 0.94),
                                                 .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                LinearGradient(colors: [.black.opacity(0.12), .clear, .clear, .black.opacity(0.18)],
                               startPoint: .top, endPoint: .bottom)
            }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
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

/// Slightly skewed game plate, retaining the label's full hit rectangle.
struct ArenaLobbyPlate: Shape {
    func path(in rect: CGRect) -> Path {
        let cut = min(CGFloat(5), rect.width * 0.06)
        var path = Path()
        path.addLines([CGPoint(x: rect.minX + cut, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX - cut, y: rect.maxY),
                       CGPoint(x: rect.minX, y: rect.maxY)])
        path.closeSubpath()
        return path
    }
}

/// Shared lobby layout coordinates; controls retain at least 44-point hit areas.
struct ArenaLobbyComposition {
    let size: CGSize
    var compact: Bool { size.height < 370 }
    var railGap: CGFloat { compact ? 0 : 10 }
    var menuHeight: CGFloat { compact ? 44 : 49 }
    var heroSize: CGSize { CGSize(width: size.width * 0.48, height: size.height * 0.70) }
    var heroCenter: CGPoint { CGPoint(x: size.width * 0.51, y: size.height * 0.51) }
    var socialCenter: CGPoint {
        let railHeight = 3 * menuHeight + 2 * railGap
        let y = compact ? size.height * 0.40 : min(size.height * 0.40, size.height - 152.5 - railHeight / 2)
        return CGPoint(x: size.width - 50, y: y)
    }
    var adventureCenter: CGPoint { CGPoint(x: compact ? size.width * 0.73 : size.width - 82, y: size.height - 122) }
    var adventureSize: CGSize { CGSize(width: compact ? 114 : 132, height: 45) }
    var inviteCenter: CGPoint { CGPoint(x: size.width * 0.69, y: size.height * (compact ? 0.43 : 0.56)) }
    var socialFrame: CGRect { CGRect(x: socialCenter.x - 33.5, y: socialCenter.y - (3 * menuHeight + 2 * railGap) / 2, width: 67, height: 3 * menuHeight + 2 * railGap) }
    var adventureFrame: CGRect { CGRect(x: adventureCenter.x - adventureSize.width / 2, y: adventureCenter.y - 22.5, width: adventureSize.width, height: 45) }
    var inviteFrame: CGRect { CGRect(x: inviteCenter.x - 22, y: inviteCenter.y - 22, width: 44, height: 44) }
}
