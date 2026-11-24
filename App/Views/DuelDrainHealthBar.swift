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

    private var sf4HealthColors: [Color] {
        if fraction <= 0.22 {
            // Critical low HP: urgent crimson-scarlet
            return [
                Color(red: 1.00, green: 0.42, blue: 0.34),
                Color(red: 0.88, green: 0.16, blue: 0.14),
                Color(red: 0.66, green: 0.10, blue: 0.10),
                Color(red: 0.44, green: 0.06, blue: 0.06),
            ]
        }
        if fraction <= 0.45 {
            // Wounded HP: warm SF4 amber-olive warning
            return [
                Color(red: 0.98, green: 0.86, blue: 0.36),
                Color(red: 0.84, green: 0.66, blue: 0.14),
                Color(red: 0.68, green: 0.48, blue: 0.08),
                Color(red: 0.48, green: 0.32, blue: 0.05),
            ]
        }
        // Classic SF4 Arena Emerald-Green metallic health core
        return [
            Color(red: 0.44, green: 0.94, blue: 0.56),
            Color(red: 0.18, green: 0.78, blue: 0.36),
            Color(red: 0.10, green: 0.58, blue: 0.25),
            Color(red: 0.06, green: 0.38, blue: 0.16),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            if slanted {
                let shape = DuelSlantedBarShape(slant: 8, mirrored: mirrored)
                ZStack(alignment: mirrored ? .trailing : .leading) {
                    // Deep recessed forged-iron trough
                    LinearGradient(
                        colors: [Color(red: 0.04, green: 0.05, blue: 0.07, opacity: 0.92),
                                 Color(red: 0.10, green: 0.11, blue: 0.14, opacity: 0.86)],
                        startPoint: .top, endPoint: .bottom
                    )
                    // Bright crimson-orange trailing damage drain
                    LinearGradient(
                        colors: [Color(red: 1.00, green: 0.36, blue: 0.22),
                                 Color(red: 0.78, green: 0.12, blue: 0.10)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(width: w * max(lagged, fraction))
                    // Classic SF4 Emerald-Green -> Amber -> Crimson health fill
                    LinearGradient(
                        colors: sf4HealthColors,
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(width: w * fraction)
                    // Specular top bevel + metallic bottom depth shadow
                    VStack(spacing: 0) {
                        Color.white.opacity(0.46).frame(height: 2.0)
                        Spacer(minLength: 0)
                        Color.black.opacity(0.36).frame(height: 2.0)
                    }
                    .frame(width: w * fraction)
                    // Subtle SF4 calibration notches every 10% across the health bar
                    HStack(spacing: 0) {
                        ForEach(1..<10, id: \.self) { idx in
                            Spacer(minLength: 0)
                            Rectangle()
                                .fill(Color.black.opacity(idx == 5 ? 0.34 : 0.18))
                                .frame(width: idx == 5 ? 1.2 : 0.7)
                        }
                        Spacer(minLength: 0)
                    }
                    // Crisp white impact hit flash
                    Color.white.opacity(flash)
                        .frame(width: w * fraction)
                }
                .clipShape(shape)
                .overlay(
                    ZStack {
                        shape.stroke(Color.black.opacity(0.88), lineWidth: 2.6)
                        shape.stroke(
                            LinearGradient(
                                colors: [Color(red: 0.92, green: 0.90, blue: 0.80, opacity: 0.88),
                                         Color(red: 0.44, green: 0.42, blue: 0.36, opacity: 0.78)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1.15
                        )
                    }
                )
                .shadow(color: Color.black.opacity(0.75), radius: 3.5, x: 0, y: 1.8)
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
            flash = 0.65
            withAnimation(.easeOut(duration: 0.20)) { flash = 0 }
            drainToken += 1
            let token = drainToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                guard token == drainToken else { return }
                withAnimation(.easeIn(duration: 0.58)) { lagged = fraction }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Bold slanted SF4 Shadow / Energy gauge flush beneath the health bar with electric ready glow.
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
            let shape = DuelSlantedBarShape(slant: 5, mirrored: mirrored)
            ZStack(alignment: mirrored ? .trailing : .leading) {
                Color(red: 0.03, green: 0.05, blue: 0.09, opacity: 0.90)
                LinearGradient(
                    colors: [
                        Color.white.opacity(readyGlow ? 0.72 : 0.34),
                        fillColor.opacity(1.0),
                        fillColor.opacity(0.76),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: w * fraction)
                VStack(spacing: 0) {
                    Color.white.opacity(readyGlow ? 0.50 : 0.25).frame(height: 1.2)
                    Spacer(minLength: 0)
                }
                .frame(width: w * fraction)
            }
            .clipShape(shape)
            .overlay(
                ZStack {
                    shape.stroke(Color.black.opacity(0.82), lineWidth: 1.8)
                    shape.stroke(readyGlow ? fillColor.opacity(1.0) : Color(red: 0.70, green: 0.76, blue: 0.84, opacity: 0.48),
                                 lineWidth: readyGlow ? 1.35 : 0.85)
                }
            )
            .shadow(color: readyGlow ? fillColor.opacity(0.82) : Color.black.opacity(0.60),
                    radius: readyGlow ? 5.5 : 1.5, x: 0, y: 1)
        }
        .accessibilityHidden(true)
    }
}

