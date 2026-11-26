import SwiftUI

/// Native SwiftUI Workspace Launcher Home (On Duty / WuMind).
/// Matches the approved two-card dark glass specification on pure black background:
/// - Pure black canvas, NO title/subtitle/tab bar/badges/fake status bar.
/// - Two equal-sized rounded graphite-black glass cards (~86–88% screen width on iPhone, centered on iPad)
///   with thin silver glass rims and subtle low-contrast right-side orbital lines.
/// - Official cropped `WorkspaceOnDutyIcon` and `WorkspaceWuMindIcon` assets without redrawing or distortion.
@MainActor
struct WorkspaceLauncherHomeView: View {
    let onSelectDuty: () -> Void
    let onSelectWuMind: () -> Void

    var body: some View {
        GeometryReader { geo in
            let safeW = geo.size.width
            let safeH = geo.size.height
            let isCompact = safeW < 540
            // 86%–88% screen width on iPhone; centered refined card width on iPad
            let cardWidth: CGFloat = isCompact ? min(safeW * 0.87, 430) : min(safeW * 0.58, 480)
            let verticalGap: CGFloat = isCompact
                ? max(32, min(52, safeH * 0.056))
                : max(38, min(56, safeH * 0.052))
            let maxCardHeight = max(180, (safeH - verticalGap - 88) / 2)
            let cardHeight: CGFloat = min(cardWidth * 0.68, min(maxCardHeight, isCompact ? 276 : 308))

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: verticalGap) {
                    WorkspaceLauncherCard(
                        iconName: "WorkspaceOnDutyIcon",
                        title: "On Duty",
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        orbitalVariant: .upper,
                        accessibilityID: "workspace.home.onDuty",
                        accessibilityLabel: "进入 On Duty 值班工作区",
                        action: onSelectDuty
                    )

                    WorkspaceLauncherCard(
                        iconName: "WorkspaceWuMindIcon",
                        title: "WuMind",
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        orbitalVariant: .lower,
                        accessibilityID: "workspace.home.wumind",
                        accessibilityLabel: "进入 WuMind AI 工作区",
                        action: onSelectWuMind
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.home.root")
    }
}

private struct WorkspaceLauncherCard: View {
    enum OrbitalVariant {
        case upper
        case lower
    }

    let iconName: String
    let title: String
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let orbitalVariant: OrbitalVariant
    let accessibilityID: String
    let accessibilityLabel: String
    let action: () -> Void

    private var cornerRadius: CGFloat { 28 }

    var body: some View {
        let iconSize = max(92, min(cardHeight * 0.455, 134))
        let titleFontSize = max(26, min(cardWidth * 0.088, 36))
        let leadingInset = max(20, min(cardWidth * 0.068, 30))
        let trailingInset = max(22, min(cardWidth * 0.072, 32))
        let iconToTitleGap = max(16, min(cardWidth * 0.054, 24))

        Button {
            Haptics.tap()
            action()
        } label: {
            ZStack {
                // Graphite-black depth gradient with soft top/bottom frosted rim sheen (no loud glow)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 0.245, green: 0.248, blue: 0.268), location: 0.00),
                                .init(color: Color(red: 0.138, green: 0.140, blue: 0.156), location: 0.12),
                                .init(color: Color(red: 0.082, green: 0.084, blue: 0.098), location: 0.52),
                                .init(color: Color(red: 0.108, green: 0.110, blue: 0.126), location: 0.88),
                                .init(color: Color(red: 0.185, green: 0.188, blue: 0.208), location: 1.00),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Soft interior specular falloff near top-left & lower-right glass edge
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.075),
                                Color.clear,
                            ],
                            center: UnitPoint(x: 0.16, y: 0.06),
                            startRadius: 6,
                            endRadius: cardWidth * 0.58
                        )
                    )

                // Low-contrast silver orbital curves + micro star nodes on right half
                WorkspaceOrbitalOverlay(variant: orbitalVariant)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)

                // Crisp single-midline card content: Official Icon | Left-Aligned Title | Spacer | Hairline Arrow
                HStack(spacing: 0) {
                    Image(iconName)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: iconSize, height: iconSize)
                        .shadow(color: Color.black.opacity(0.62), radius: 12, x: 0, y: 6)

                    Text(title)
                        .font(.system(size: titleFontSize, weight: .regular, design: .default))
                        .tracking(0.25)
                        .foregroundStyle(Color.white.opacity(0.95))
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                        .padding(.leading, iconToTitleGap)

                    Spacer(minLength: 10)

                    Image(systemName: "arrow.right")
                        .font(.system(size: max(20, min(cardWidth * 0.064, 26)), weight: .light))
                        .foregroundStyle(Color.white.opacity(0.90))
                }
                .padding(.leading, leadingInset)
                .padding(.trailing, trailingInset)

                // Thin silver-white glass edge highlight
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.52), location: 0.0),
                                .init(color: Color.white.opacity(0.20), location: 0.24),
                                .init(color: Color.white.opacity(0.11), location: 0.74),
                                .init(color: Color.white.opacity(0.36), location: 1.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.1
                    )
            }
            .frame(width: cardWidth, height: cardHeight)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(WorkspaceLauncherCardPressStyle())
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct WorkspaceLauncherCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.982 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Renders the exact subtle low-contrast orbital trajectories and star-dot intersections
/// on the right half of each launcher glass card (native vector Canvas, zero bitmap bloat).
private struct WorkspaceOrbitalOverlay: View {
    let variant: WorkspaceLauncherCard.OrbitalVariant

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let strokeThin = Color.white.opacity(0.11)
            let strokeFaint = Color.white.opacity(0.065)

            // Upper-right orbital ellipse
            var upperArc = Path()
            let upperRect = CGRect(
                x: w * 0.48,
                y: variant == .upper ? -h * 0.28 : -h * 0.22,
                width: w * 0.62,
                height: h * 0.76
            )
            upperArc.addEllipse(in: upperRect)
            ctx.stroke(upperArc, with: .color(strokeThin), lineWidth: 0.85)

            // Secondary sweeping orbital trajectory across right corner
            var sweepArc = Path()
            let sweepRect = CGRect(
                x: w * 0.58,
                y: -h * 0.12,
                width: w * 0.60,
                height: h * 0.64
            )
            sweepArc.addEllipse(in: sweepRect)
            ctx.stroke(sweepArc, with: .color(strokeFaint), lineWidth: 0.75)

            // Lower-right constellation arc
            var lowerArc = Path()
            let lowerRect = CGRect(
                x: w * 0.44,
                y: h * 0.72,
                width: w * 0.66,
                height: h * 0.62
            )
            lowerArc.addEllipse(in: lowerRect)
            ctx.stroke(lowerArc, with: .color(strokeThin), lineWidth: 0.85)

            // Subtle cross-trajectory curve on lower right
            var wave = Path()
            wave.move(to: CGPoint(x: w * 0.52, y: h * 1.04))
            wave.addQuadCurve(
                to: CGPoint(x: w * 1.04, y: h * 0.62),
                control: CGPoint(x: w * 0.78, y: h * 0.74)
            )
            ctx.stroke(wave, with: .color(strokeFaint), lineWidth: 0.75)

            // Tiny low-contrast star nodes along orbital intersections
            let starPoints: [(CGFloat, CGFloat, CGFloat)] = [
                (0.61, 0.23, 2.0),
                (0.75, 0.08, 1.5),
                (0.84, 0.34, 1.4),
                (0.76, 0.82, 2.1),
                (0.68, 0.90, 1.4),
                (0.89, 0.75, 1.5),
            ]
            for (rx, ry, r) in starPoints {
                let pt = CGPoint(x: w * rx, y: h * ry)
                let dotRect = CGRect(x: pt.x - r / 2, y: pt.y - r / 2, width: r, height: r)
                ctx.fill(Path(ellipseIn: dotRect), with: .color(Color.white.opacity(0.32)))
            }
        }
    }
}
