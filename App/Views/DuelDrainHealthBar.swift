import SwiftUI

/// Symmetric inward-slanted parallelogram matching Shadow Fight 4 HUD geometry.
struct DuelSlantedBarShape: Shape {
    let slant: CGFloat
    let mirrored: Bool

    func path(in rect: CGRect) -> Path {
        let s = min(slant, rect.width * 0.25)
        var p = Path()
        if mirrored {
            // Right bar: slants downward-left toward outer right edge (`/` left edge, `/` right edge)
            p.move(to: CGPoint(x: s, y: 0))
            p.addLine(to: CGPoint(x: rect.maxX, y: 0))
            p.addLine(to: CGPoint(x: rect.maxX - s, y: rect.maxY))
            p.addLine(to: CGPoint(x: 0, y: rect.maxY))
        } else {
            // Left bar: slants downward-right toward center timer (`\` left edge, `\` right edge)
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: rect.maxX - s, y: 0))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: s, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}

/// Shadow Fight style health bar: the live fill drops instantly on a hit while a
/// crimson/pale "damage drain" segment lingers briefly, then slides down to meet it.
/// Purely presentational — it reads the deterministic game health and never
/// feeds anything back into the simulation.
struct DuelDrainHealthBar: View {
    let health: Int
    let maximum: Int
    let mirrored: Bool
    let tint: Color
    var slanted: Bool = false

    @State private var lagged: Double = 1
    @State private var flash: Double = 0
    @State private var drainToken = 0

    private var fraction: Double {
        guard maximum > 0 else { return 0 }
        return min(1, max(0, Double(health) / Double(maximum)))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            if slanted {
                let shape = DuelSlantedBarShape(slant: 7, mirrored: mirrored)
                ZStack(alignment: mirrored ? .trailing : .leading) {
                    // Deep recessed gunmetal trough with subtle top shadow
                    LinearGradient(
                        colors: [Color(red: 0.05, green: 0.06, blue: 0.08, opacity: 0.90),
                                 Color(red: 0.11, green: 0.12, blue: 0.15, opacity: 0.82)],
                        startPoint: .top, endPoint: .bottom
                    )
                    // Crimson molten trailing damage drain
                    LinearGradient(
                        colors: [Color(red: 0.98, green: 0.30, blue: 0.20),
                                 Color(red: 0.68, green: 0.10, blue: 0.10)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(width: w * max(lagged, fraction))
                    // Brushed antique-gold metallic health core (SF4 Arena grade)
                    LinearGradient(
                        colors: [Color(red: 1.00, green: 0.91, blue: 0.56),
                                 Color(red: 0.90, green: 0.68, blue: 0.20),
                                 Color(red: 0.76, green: 0.52, blue: 0.12),
                                 Color(red: 0.54, green: 0.36, blue: 0.08)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(width: w * fraction)
                    // Specular upper bevel sheen + subtle lower metallic dark edge
                    VStack(spacing: 0) {
                        Color.white.opacity(0.42).frame(height: 1.8)
                        Spacer(minLength: 0)
                        Color.black.opacity(0.32).frame(height: 1.6)
                    }
                    .frame(width: w * fraction)
                    // Crisp impact hit flash
                    Color.white.opacity(flash)
                        .frame(width: w * fraction)
                }
                .clipShape(shape)
                .overlay(
                    // Outer dark forged-steel shadow casing + inner tarnished gold metallic rim
                    ZStack {
                        shape.stroke(Color.black.opacity(0.82), lineWidth: 2.4)
                        shape.stroke(
                            LinearGradient(
                                colors: [Color(red: 0.96, green: 0.86, blue: 0.58, opacity: 0.92),
                                         Color(red: 0.52, green: 0.44, blue: 0.28, opacity: 0.80)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1.15
                        )
                    }
                )
                .shadow(color: Color.black.opacity(0.70), radius: 3, x: 0, y: 1.5)
            } else {
                ZStack(alignment: mirrored ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.black.opacity(0.62))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [Color(white: 0.98), Color(red: 1.0, green: 0.78, blue: 0.42)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: w * max(lagged, fraction))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.62)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: w * fraction)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(flash))
                        .frame(width: w * fraction)
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.white.opacity(0.45), lineWidth: 0.8)
                }
            }
        }
        .onAppear { lagged = fraction }
        .onChange(of: health) { _ in
            let target = fraction
            if target > lagged {
                // Healing / round reset: snap the drain segment up with the fill.
                lagged = target
                return
            }
            flash = 0.55
            withAnimation(.easeOut(duration: 0.18)) { flash = 0 }
            drainToken += 1
            let token = drainToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                guard token == drainToken else { return }
                withAnimation(.easeIn(duration: 0.55)) { lagged = fraction }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Sleek thin slanted secondary resource gauge (Shadow / Light / Flame energy) flush beneath the SF4 health bar.
struct DuelSlantedMeterBar: View {
    let value: Int
    let maximum: Int
    let mirrored: Bool
    let fillColor: Color
    let readyGlow: Bool

    private var fraction: Double {
        guard maximum > 0 else { return 0 }
        return min(1, max(0, Double(value) / Double(maximum)))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let shape = DuelSlantedBarShape(slant: 4, mirrored: mirrored)
            ZStack(alignment: mirrored ? .trailing : .leading) {
                Color(red: 0.04, green: 0.06, blue: 0.09, opacity: 0.86)
                LinearGradient(
                    colors: [Color.white.opacity(readyGlow ? 0.55 : 0.25), fillColor.opacity(1.0), fillColor.opacity(0.70)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: w * fraction)
            }
            .clipShape(shape)
            .overlay(
                ZStack {
                    shape.stroke(Color.black.opacity(0.75), lineWidth: 1.6)
                    shape.stroke(readyGlow ? fillColor.opacity(0.98) : Color(red: 0.72, green: 0.74, blue: 0.78, opacity: 0.42),
                                 lineWidth: readyGlow ? 1.15 : 0.75)
                }
            )
            .shadow(color: readyGlow ? fillColor.opacity(0.65) : Color.black.opacity(0.55),
                    radius: readyGlow ? 4 : 1.5, x: 0, y: 1)
        }
        .accessibilityHidden(true)
    }
}

