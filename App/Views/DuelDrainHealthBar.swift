import SwiftUI

/// Shadow Fight style health bar: the live fill drops instantly on a hit while a
/// pale "damage drain" segment lingers briefly, then slides down to meet it.
/// Purely presentational — it reads the deterministic game health and never
/// feeds anything back into the simulation.
struct DuelDrainHealthBar: View {
    let health: Int
    let maximum: Int
    let mirrored: Bool
    let tint: Color

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
