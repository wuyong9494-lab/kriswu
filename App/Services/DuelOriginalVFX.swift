import SceneKit
import UIKit
import simd

/// High-resolution procedural CoreGraphics VFX textures & Metal-translated SceneKit shaders.
/// 100% original procedural art: zero third-party SF3 assets, zero blocky clipart sprites,
/// and zero solid plastic torus geometry.
@MainActor
enum DuelProceduralVFXAssets {
    private static var cache: [String: UIImage] = [:]

    static var razorRibbon: UIImage { cached("razorRibbon") { makeRazorRibbon() } }
    static var slashCrescent: UIImage { cached("slashCrescent") { makeSlashCrescent() } }
    static var impactCross: UIImage { cached("impactCross") { makeImpactCross() } }
    static var shockRipple: UIImage { cached("shockRipple") { makeShockRipple() } }
    static var crusaderSigil: UIImage { cached("crusaderSigil") { makeCrusaderSigil() } }
    static var shogunSeal: UIImage { cached("shogunSeal") { makeShogunSeal() } }
    static var sparkNeedle: UIImage { cached("sparkNeedle") { makeSparkNeedle() } }
    static var smokeWisp: UIImage { cached("smokeWisp") { makeSmokeWisp() } }
    static var lightningArc: UIImage { cached("lightningArc") { makeLightningArc() } }
    static var energyBeam: UIImage { cached("energyBeam") { makeEnergyBeam() } }
    static var dojoStone: UIImage { cached("dojoStone") { makeDojoStone() } }

    static func prepare() {
        _ = razorRibbon; _ = slashCrescent; _ = impactCross; _ = shockRipple
        _ = crusaderSigil; _ = shogunSeal; _ = sparkNeedle; _ = smokeWisp
        _ = lightningArc; _ = energyBeam; _ = dojoStone
    }

    private static func cached(_ key: String, build: () -> UIImage) -> UIImage {
        if let existing = cache[key] { return existing }
        let img = build()
        cache[key] = img
        return img
    }

    private static func render(width: Int, height: Int, draw: (CGContext, CGSize) -> Void) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            draw(ctx.cgContext, size)
        }
    }

    /// Smooth swept blade trail profile: transparent hilt -> energy aura -> white-hot razor tip edge.
    private static func makeRazorRibbon() -> UIImage {
        render(width: 256, height: 256) { ctx, size in
            let cs = CGColorSpaceCreateDeviceRGB()
            // Horizontal tail-to-head fade multiplied with vertical blade cutting-edge profile.
            let locations: [CGFloat] = [0.0, 0.25, 0.58, 0.84, 0.94, 1.0]
            let colors: [CGColor] = [
                UIColor(white: 1, alpha: 0.0).cgColor,
                UIColor(white: 1, alpha: 0.06).cgColor,
                UIColor(white: 1, alpha: 0.34).cgColor,
                UIColor(white: 1, alpha: 0.88).cgColor,
                UIColor(white: 1, alpha: 1.0).cgColor,
                UIColor(white: 1, alpha: 0.0).cgColor,
            ]
            if let grad = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locations) {
                ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
            }
            // Subtle brushed plasma energy streaks running along the swing arc
            ctx.setBlendMode(.plusLighter)
            for i in 0..<18 {
                let y = size.height * (0.42 + CGFloat(i) * 0.031)
                let thickness = 1.2 + CGFloat(i % 3) * 1.1
                let alpha = 0.07 + 0.16 * (CGFloat(i) / 18.0)
                ctx.setStrokeColor(UIColor(white: 1, alpha: alpha).cgColor)
                ctx.setLineWidth(thickness)
                ctx.move(to: CGPoint(x: size.width * 0.08, y: y))
                ctx.addCurve(to: CGPoint(x: size.width, y: y - 3),
                             control1: CGPoint(x: size.width * 0.42, y: y + 5),
                             control2: CGPoint(x: size.width * 0.76, y: y - 6))
                ctx.strokePath()
            }
        }
    }

    /// Sweeping calligraphic crescent slash arc with needle-sharp tips and glowing outer blade edge.
    private static func makeSlashCrescent() -> UIImage {
        render(width: 512, height: 512) { ctx, size in
            let cx = size.width * 0.5, cy = size.height * 0.5
            let outerR = size.width * 0.45
            let innerR = size.width * 0.31
            let steps = 96

            // Layered soft-to-razor crescent sweeps
            let passes: [(inset: CGFloat, alpha: CGFloat, blur: CGFloat)] = [
                (-10, 0.22, 16),
                (-3, 0.48, 7),
                (2, 0.85, 2.5),
                (6, 1.0, 0.5),
            ]
            for pass in passes {
                ctx.saveGState()
                if pass.blur > 0.6 {
                    ctx.setShadow(offset: .zero, blur: pass.blur, color: UIColor(white: 1, alpha: pass.alpha).cgColor)
                }
                let path = CGMutablePath()
                let startA: CGFloat = -.pi * 0.72
                let endA: CGFloat = .pi * 0.52
                for i in 0...steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    let a = startA + (endA - startA) * t
                    let r = outerR - pass.inset * 0.4
                    let pt = CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                for i in stride(from: steps, through: 0, by: -1) {
                    let t = CGFloat(i) / CGFloat(steps)
                    let a = startA + (endA - startA) * t
                    let belly = sin(t * .pi)
                    let thickness = (outerR - innerR) * pow(belly, 0.72) * (1.0 - pass.inset * 0.045)
                    let r = max(20, outerR - max(2.0, thickness))
                    let pt = CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r)
                    path.addLine(to: pt)
                }
                path.closeSubpath()
                ctx.addPath(path)
                ctx.setFillColor(UIColor(white: 1, alpha: pass.alpha).cgColor)
                ctx.fillPath()
                ctx.restoreGState()
            }

            // Crisp razor speed-lines trailing off the crescent wake
            ctx.setBlendMode(.plusLighter)
            for k in 0..<7 {
                let offset = CGFloat(k) * 9.5 + 8
                ctx.setStrokeColor(UIColor(white: 1, alpha: 0.38 - CGFloat(k) * 0.045).cgColor)
                ctx.setLineWidth(max(1.0, 2.8 - CGFloat(k) * 0.3))
                ctx.addArc(center: CGPoint(x: cx, y: cy), radius: outerR - offset,
                           startAngle: -.pi * 0.62 + CGFloat(k) * 0.05,
                           endAngle: .pi * 0.42 - CGFloat(k) * 0.03, clockwise: false)
                ctx.strokePath()
            }
        }
    }

    /// Anamorphic SF4 Arena hit starburst & lens-flare cross (sharp, intense, zero puffy circles).
    private static func makeImpactCross() -> UIImage {
        render(width: 512, height: 512) { ctx, size in
            let cx = size.width * 0.5, cy = size.height * 0.5
            let cs = CGColorSpaceCreateDeviceRGB()

            // Soft tight hot core
            if let coreGrad = CGGradient(
                colorsSpace: cs,
                colors: [
                    UIColor(white: 1, alpha: 1.0).cgColor,
                    UIColor(white: 1, alpha: 0.65).cgColor,
                    UIColor(white: 1, alpha: 0.14).cgColor,
                    UIColor(white: 1, alpha: 0.0).cgColor,
                ] as CFArray,
                locations: [0.0, 0.16, 0.45, 1.0]
            ) {
                ctx.drawRadialGradient(coreGrad, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                       endCenter: CGPoint(x: cx, y: cy), endRadius: size.width * 0.24, options: [])
            }

            func drawFlareSpike(angle: CGFloat, length: CGFloat, halfWidth: CGFloat, alpha: CGFloat) {
                ctx.saveGState()
                ctx.translateBy(x: cx, y: cy)
                ctx.rotate(by: angle)
                let p = CGMutablePath()
                p.move(to: CGPoint(x: -length, y: 0))
                p.addQuadCurve(to: CGPoint(x: 0, y: -halfWidth), control: CGPoint(x: -length * 0.25, y: -halfWidth * 0.4))
                p.addQuadCurve(to: CGPoint(x: length, y: 0), control: CGPoint(x: length * 0.25, y: -halfWidth * 0.4))
                p.addQuadCurve(to: CGPoint(x: 0, y: halfWidth), control: CGPoint(x: length * 0.25, y: halfWidth * 0.4))
                p.addQuadCurve(to: CGPoint(x: -length, y: 0), control: CGPoint(x: -length * 0.25, y: halfWidth * 0.4))
                p.closeSubpath()
                ctx.addPath(p)
                ctx.setFillColor(UIColor(white: 1, alpha: alpha).cgColor)
                ctx.fillPath()
                ctx.restoreGState()
            }

            ctx.setBlendMode(.plusLighter)
            // Primary long horizontal anamorphic streak
            drawFlareSpike(angle: 0, length: size.width * 0.48, halfWidth: 18, alpha: 0.55)
            drawFlareSpike(angle: 0, length: size.width * 0.46, halfWidth: 6.5, alpha: 1.0)
            // Secondary vertical streak
            drawFlareSpike(angle: .pi / 2, length: size.width * 0.34, halfWidth: 13, alpha: 0.45)
            drawFlareSpike(angle: .pi / 2, length: size.width * 0.32, halfWidth: 5, alpha: 0.92)
            // Diagonal crisp micro-spikes
            for a in [CGFloat.pi * 0.25, -.pi * 0.25, .pi * 0.12, -.pi * 0.38] {
                drawFlareSpike(angle: a, length: size.width * 0.23, halfWidth: 3.5, alpha: 0.65)
            }
        }
    }

    /// Razor-thin feathered energy shockwave ripple with wispy inner speed lines (replaces SCNTorus).
    private static func makeShockRipple() -> UIImage {
        render(width: 512, height: 512) { ctx, size in
            let cx = size.width * 0.5, cy = size.height * 0.5
            let cs = CGColorSpaceCreateDeviceRGB()
            let rMax = size.width * 0.48
            if let ringGrad = CGGradient(
                colorsSpace: cs,
                colors: [
                    UIColor(white: 1, alpha: 0.0).cgColor,
                    UIColor(white: 1, alpha: 0.0).cgColor,
                    UIColor(white: 1, alpha: 0.14).cgColor,
                    UIColor(white: 1, alpha: 0.72).cgColor,
                    UIColor(white: 1, alpha: 1.0).cgColor,
                    UIColor(white: 1, alpha: 0.35).cgColor,
                    UIColor(white: 1, alpha: 0.0).cgColor,
                ] as CFArray,
                locations: [0.0, 0.56, 0.74, 0.86, 0.90, 0.95, 1.0]
            ) {
                ctx.drawRadialGradient(ringGrad, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                       endCenter: CGPoint(x: cx, y: cy), endRadius: rMax, options: [])
            }
            // Delicate inner radial shock streaks
            ctx.setBlendMode(.plusLighter)
            for i in 0..<28 {
                let a = CGFloat(i) / 28.0 * .pi * 2.0
                let inner = rMax * (0.58 + CGFloat(i % 3) * 0.06)
                let outer = rMax * (0.89 + CGFloat(i % 2) * 0.03)
                ctx.setStrokeColor(UIColor(white: 1, alpha: 0.24).cgColor)
                ctx.setLineWidth(1.5)
                ctx.move(to: CGPoint(x: cx + cos(a) * inner, y: cy + sin(a) * inner))
                ctx.addLine(to: CGPoint(x: cx + cos(a) * outer, y: cy + sin(a) * outer))
                ctx.strokePath()
            }
        }
    }

    /// Ornate golden Crusader / Grand Inquisitor sacred sigil (for Stigmata & Salvation seals).
    private static func makeCrusaderSigil() -> UIImage {
        render(width: 512, height: 512) { ctx, size in
            let cx = size.width * 0.5, cy = size.height * 0.5
            let cs = CGColorSpaceCreateDeviceRGB()
            if let glow = CGGradient(
                colorsSpace: cs,
                colors: [
                    UIColor(white: 1, alpha: 0.36).cgColor,
                    UIColor(white: 1, alpha: 0.10).cgColor,
                    UIColor(white: 1, alpha: 0.0).cgColor,
                ] as CFArray,
                locations: [0.0, 0.55, 1.0]
            ) {
                ctx.drawRadialGradient(glow, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                       endCenter: CGPoint(x: cx, y: cy), endRadius: size.width * 0.46, options: [])
            }

            ctx.setShadow(offset: .zero, blur: 6, color: UIColor(white: 1, alpha: 0.85).cgColor)
            // Fine concentric filigree rings
            for (r, lw, alpha) in [(0.43, 3.2, 0.95), (0.38, 1.5, 0.72), (0.24, 2.0, 0.80)] as [(CGFloat, CGFloat, CGFloat)] {
                ctx.setStrokeColor(UIColor(white: 1, alpha: alpha).cgColor)
                ctx.setLineWidth(lw)
                ctx.addArc(center: CGPoint(x: cx, y: cy), radius: size.width * r, startAngle: 0, endAngle: .pi * 2, clockwise: false)
                ctx.strokePath()
            }
            // Inscribed rotated sacred squares (8-point star geometry)
            for rot in [CGFloat(0), .pi / 4] {
                ctx.saveGState()
                ctx.translateBy(x: cx, y: cy)
                ctx.rotate(by: rot)
                let side = size.width * 0.54
                ctx.setStrokeColor(UIColor(white: 1, alpha: 0.78).cgColor)
                ctx.setLineWidth(2.0)
                ctx.stroke(CGRect(x: -side * 0.5, y: -side * 0.5, width: side, height: side))
                ctx.restoreGState()
            }
            // Cardinal Templar cross spikes
            for i in 0..<4 {
                let a = CGFloat(i) * .pi / 2
                ctx.saveGState()
                ctx.translateBy(x: cx, y: cy)
                ctx.rotate(by: a)
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 0, y: -size.width * 0.46))
                p.addLine(to: CGPoint(x: 9, y: -size.width * 0.16))
                p.addLine(to: CGPoint(x: 0, y: -size.width * 0.08))
                p.addLine(to: CGPoint(x: -9, y: -size.width * 0.16))
                p.closeSubpath()
                ctx.addPath(p)
                ctx.setFillColor(UIColor(white: 1, alpha: 0.92).cgColor)
                ctx.fillPath()
                ctx.restoreGState()
            }
        }
    }

    /// Calligraphic samurai Shadow Seal for Wu Yong's Despotism vortex & Cataclysm eruption.
    private static func makeShogunSeal() -> UIImage {
        render(width: 512, height: 512) { ctx, size in
            let cx = size.width * 0.5, cy = size.height * 0.5
            ctx.setShadow(offset: .zero, blur: 8, color: UIColor(white: 1, alpha: 0.85).cgColor)
            // Broken calligraphic brush ring segments
            for i in 0..<3 {
                let start = CGFloat(i) * (.pi * 2 / 3) + 0.12
                let end = start + 1.72
                ctx.setStrokeColor(UIColor(white: 1, alpha: 0.92).cgColor)
                ctx.setLineWidth(5.5)
                ctx.setLineCap(.round)
                ctx.addArc(center: CGPoint(x: cx, y: cy), radius: size.width * 0.42, startAngle: start, endAngle: end, clockwise: false)
                ctx.strokePath()
            }
            // Six inward-sweeping vortex blades
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3
                ctx.saveGState()
                ctx.translateBy(x: cx, y: cy)
                ctx.rotate(by: a)
                ctx.setStrokeColor(UIColor(white: 1, alpha: 0.78).cgColor)
                ctx.setLineWidth(3.2)
                ctx.move(to: CGPoint(x: size.width * 0.39, y: 0))
                ctx.addQuadCurve(to: CGPoint(x: size.width * 0.12, y: size.width * 0.08),
                                 control: CGPoint(x: size.width * 0.28, y: -size.width * 0.08))
                ctx.strokePath()
                ctx.restoreGState()
            }
            ctx.setStrokeColor(UIColor(white: 1, alpha: 0.85).cgColor)
            ctx.setLineWidth(2.4)
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: size.width * 0.15, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.strokePath()
        }
    }

    /// Razor-thin elongated molten spark needle (aligned along velocity vector).
    private static func makeSparkNeedle() -> UIImage {
        render(width: 64, height: 256) { ctx, size in
            let cx = size.width * 0.5
            let p = CGMutablePath()
            p.move(to: CGPoint(x: cx, y: 8))
            p.addQuadCurve(to: CGPoint(x: cx + 10, y: size.height * 0.45), control: CGPoint(x: cx + 9, y: size.height * 0.18))
            p.addQuadCurve(to: CGPoint(x: cx, y: size.height - 6), control: CGPoint(x: cx + 4, y: size.height * 0.78))
            p.addQuadCurve(to: CGPoint(x: cx - 10, y: size.height * 0.45), control: CGPoint(x: cx - 4, y: size.height * 0.78))
            p.addQuadCurve(to: CGPoint(x: cx, y: 8), control: CGPoint(x: cx - 9, y: size.height * 0.18))
            p.closeSubpath()
            ctx.setShadow(offset: .zero, blur: 10, color: UIColor(white: 1, alpha: 0.95).cgColor)
            ctx.addPath(p)
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillPath()
        }
    }

    /// Soft organic multi-lobe turbulent smoke & ink-flame wisp (replaces clipart twirl PNGs).
    private static func makeSmokeWisp() -> UIImage {
        render(width: 256, height: 256) { ctx, size in
            let cs = CGColorSpaceCreateDeviceRGB()
            let lobes: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (0.50, 0.50, 0.34, 0.42),
                (0.38, 0.44, 0.25, 0.30),
                (0.62, 0.46, 0.24, 0.28),
                (0.47, 0.60, 0.24, 0.26),
                (0.54, 0.36, 0.22, 0.24),
            ]
            for (nx, ny, nr, a) in lobes {
                let center = CGPoint(x: size.width * nx, y: size.height * ny)
                if let g = CGGradient(
                    colorsSpace: cs,
                    colors: [
                        UIColor(white: 1, alpha: a).cgColor,
                        UIColor(white: 1, alpha: a * 0.42).cgColor,
                        UIColor(white: 1, alpha: 0.0).cgColor,
                    ] as CFArray,
                    locations: [0.0, 0.48, 1.0]
                ) {
                    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0,
                                           endCenter: center, endRadius: size.width * nr, options: [])
                }
            }
        }
    }

    /// Jagged electric shadow-lightning bolt with soft outer halo & razor white-hot core.
    private static func makeLightningArc() -> UIImage {
        render(width: 128, height: 512) { ctx, size in
            var rng: UInt64 = 0x5F4A91B3
            func nextF() -> CGFloat {
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((rng >> 33) & 0xFFFF) / 65535.0
            }
            var mainPts: [CGPoint] = []
            let segs = 18
            for i in 0...segs {
                let t = CGFloat(i) / CGFloat(segs)
                let jitter = (i == 0 || i == segs) ? 0 : (nextF() - 0.5) * 44.0 * sin(t * .pi)
                mainPts.append(CGPoint(x: size.width * 0.5 + jitter, y: 12 + (size.height - 24) * t))
            }
            var branches: [[CGPoint]] = []
            for idx in [5, 9, 13] {
                let origin = mainPts[idx]
                let side: CGFloat = idx % 2 == 0 ? 1 : -1
                branches.append([
                    origin,
                    CGPoint(x: origin.x + side * (16 + nextF() * 14), y: origin.y + 28),
                    CGPoint(x: origin.x + side * (28 + nextF() * 18), y: origin.y + 62),
                ])
            }
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for (lw, alpha, blur) in [(11.0, 0.28, 12.0), (5.0, 0.65, 4.0), (2.0, 1.0, 0.0)] as [(CGFloat, CGFloat, CGFloat)] {
                ctx.saveGState()
                if blur > 0 { ctx.setShadow(offset: .zero, blur: blur, color: UIColor(white: 1, alpha: alpha).cgColor) }
                ctx.setStrokeColor(UIColor(white: 1, alpha: alpha).cgColor)
                ctx.setLineWidth(lw)
                ctx.addLines(between: mainPts)
                ctx.strokePath()
                ctx.setLineWidth(max(1.0, lw * 0.52))
                for br in branches {
                    ctx.addLines(between: br)
                    ctx.strokePath()
                }
                ctx.restoreGState()
            }
        }
    }

    /// Volumetric vertical god-ray light shaft texture (soft horizontal & vertical feathering).
    private static func makeEnergyBeam() -> UIImage {
        render(width: 256, height: 512) { ctx, size in
            let cs = CGColorSpaceCreateDeviceRGB()
            // Horizontal bell profile (transparent left/right edges, hot core center)
            if let horiz = CGGradient(
                colorsSpace: cs,
                colors: [
                    UIColor(white: 1, alpha: 0.0).cgColor,
                    UIColor(white: 1, alpha: 0.22).cgColor,
                    UIColor(white: 1, alpha: 0.85).cgColor,
                    UIColor(white: 1, alpha: 1.0).cgColor,
                    UIColor(white: 1, alpha: 0.85).cgColor,
                    UIColor(white: 1, alpha: 0.22).cgColor,
                    UIColor(white: 1, alpha: 0.0).cgColor,
                ] as CFArray,
                locations: [0.0, 0.22, 0.42, 0.50, 0.58, 0.78, 1.0]
            ) {
                ctx.drawLinearGradient(horiz, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size.width, y: 0), options: [])
            }
            // Internal crisp vertical cathedral light rays
            ctx.setBlendMode(.plusLighter)
            for xNorm in [0.34, 0.43, 0.50, 0.57, 0.66] as [CGFloat] {
                let x = size.width * xNorm
                ctx.setStrokeColor(UIColor(white: 1, alpha: xNorm == 0.50 ? 0.65 : 0.30).cgColor)
                ctx.setLineWidth(xNorm == 0.50 ? 8.0 : 3.5)
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: size.height))
                ctx.strokePath()
            }
            // Soft feather top & bottom edges via destinationIn mask
            ctx.setBlendMode(.destinationIn)
            if let vertMask = CGGradient(
                colorsSpace: cs,
                colors: [
                    UIColor(white: 1, alpha: 0.0).cgColor,
                    UIColor(white: 1, alpha: 1.0).cgColor,
                    UIColor(white: 1, alpha: 1.0).cgColor,
                    UIColor(white: 1, alpha: 0.0).cgColor,
                ] as CFArray,
                locations: [0.0, 0.14, 0.88, 1.0]
            ) {
                ctx.drawLinearGradient(vertMask, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
    }

    /// Atmospheric dark moonlit temple courtyard stone slab texture for procedural floor.
    private static func makeDojoStone() -> UIImage {
        render(width: 512, height: 512) { ctx, size in
            ctx.setFillColor(UIColor(red: 0.14, green: 0.14, blue: 0.17, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            var rng: UInt64 = 0x20261121
            func nextF() -> CGFloat {
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((rng >> 33) & 0xFFFF) / 65535.0
            }
            let rows = 8, cols = 4
            let rh = size.height / CGFloat(rows), cw = size.width / CGFloat(cols)
            for r in 0..<rows {
                let offset = (r % 2 == 0) ? 0 : cw * 0.5
                for c in -1...cols {
                    let shade = 0.13 + nextF() * 0.06
                    let rect = CGRect(x: CGFloat(c) * cw + offset + 2, y: CGFloat(r) * rh + 2, width: cw - 4, height: rh - 4)
                    ctx.setFillColor(UIColor(red: shade, green: shade * 0.98, blue: shade * 1.12, alpha: 1).cgColor)
                    ctx.fill(rect)
                    ctx.setStrokeColor(UIColor(white: 0.06, alpha: 0.85).cgColor)
                    ctx.setLineWidth(2.5)
                    ctx.stroke(rect)
                }
            }
            // Subtle stone grain speckles
            for _ in 0..<700 {
                let x = nextF() * size.width, y = nextF() * size.height
                let w = 1.0 + nextF() * 3.0
                ctx.setFillColor(UIColor(white: nextF() > 0.5 ? 0.30 : 0.05, alpha: 0.16).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: w, height: w))
            }
        }
    }
}

/// Native Metal SceneKit fragment shader modifiers (`#pragma arguments`) for HDR bloom ribbons,
/// animated polar-sweep crescent slashes, scrolling cathedral god-ray beams, shockwave ripples,
/// and blooming impact cross-flares / lightning / sacred sigils.
enum DuelVFXShaders {
    static let bladeRibbonFragment = """
    #pragma arguments
    float4 vfxTint;
    float vfxHdrBoost;
    #pragma transparent
    #pragma body
    float2 uv = _surface.diffuseTexcoord;
    float edgeMask = _surface.diffuse.a;
    float headTail = smoothstep(0.0, 0.30, uv.x) * (1.0 - smoothstep(0.95, 1.0, uv.x));
    float wave = 0.84 + 0.16 * sin(uv.x * 16.0 - scn_frame.time * 18.0 + uv.y * 6.0);
    float hotCore = pow(saturate(uv.y), 4.2) * smoothstep(0.22, 0.92, uv.x);
    float alpha = saturate(edgeMask * headTail * wave * vfxTint.a);
    float3 col = mix(vfxTint.rgb, float3(1.0, 0.98, 0.95), hotCore * 0.78) * vfxHdrBoost * (0.78 + 0.85 * hotCore);
    _output.color = float4(col * alpha, 1.0);
    """

    static let crescentSlashFragment = """
    #pragma arguments
    float4 vfxTint;
    float vfxProgress;
    float vfxHdrBoost;
    #pragma transparent
    #pragma body
    float2 uv = _surface.diffuseTexcoord;
    float mask = _surface.diffuse.a;
    float2 p = uv - float2(0.5);
    float ang = (atan2(p.y, p.x) + 3.14159265) / 6.2831853;
    float head = mix(0.10, 0.86, saturate(vfxProgress * 1.45));
    float tail = mix(0.04, 0.80, saturate((vfxProgress - 0.30) * 1.45));
    float sweep = smoothstep(tail - 0.14, tail + 0.08, ang) * (1.0 - smoothstep(head - 0.06, head + 0.06, ang));
    float fade = 1.0 - smoothstep(0.52, 1.0, vfxProgress);
    float intensity = saturate(mask * max(sweep, 0.36 * fade) * fade * vfxTint.a);
    float hot = pow(saturate(mask), 2.8);
    float3 col = mix(vfxTint.rgb, float3(1.0, 0.98, 0.95), hot * 0.72) * vfxHdrBoost;
    _output.color = float4(col * intensity, 1.0);
    """

    static let godRayBeamFragment = """
    #pragma arguments
    float4 vfxTint;
    float vfxHdrBoost;
    float vfxOpacity;
    #pragma transparent
    #pragma body
    float2 uv = _surface.diffuseTexcoord;
    float baseMask = _surface.diffuse.a;
    float scroll1 = 0.76 + 0.24 * sin(uv.y * 14.0 - scn_frame.time * 9.0 + uv.x * 18.0);
    float scroll2 = 0.80 + 0.20 * cos(uv.y * 24.0 - scn_frame.time * 13.0 - uv.x * 12.0);
    float core = exp(-pow((uv.x - 0.5) * 4.2, 2.0));
    float alpha = saturate(baseMask * scroll1 * scroll2 * vfxTint.a * vfxOpacity);
    float3 col = mix(vfxTint.rgb, float3(1.0, 0.99, 0.92), core * 0.75) * vfxHdrBoost;
    _output.color = float4(col * alpha, 1.0);
    """

    static let shockRippleFragment = """
    #pragma arguments
    float4 vfxTint;
    float vfxProgress;
    float vfxHdrBoost;
    #pragma transparent
    #pragma body
    float mask = _surface.diffuse.a;
    float fade = pow(max(0.0, 1.0 - vfxProgress), 1.35);
    float alpha = saturate(mask * fade * vfxTint.a);
    float3 col = mix(vfxTint.rgb, float3(1.0, 0.99, 0.96), pow(saturate(mask), 3.0) * 0.55) * vfxHdrBoost;
    _output.color = float4(col * alpha, 1.0);
    """

    static let hdrGlowFragment = """
    #pragma arguments
    float4 vfxTint;
    float vfxHdrBoost;
    #pragma transparent
    #pragma body
    float mask = _surface.diffuse.a;
    float hot = pow(saturate(mask), 2.8);
    float alpha = saturate(mask * vfxTint.a);
    float3 col = mix(vfxTint.rgb, float3(1.0, 0.99, 0.96), hot * 0.65) * vfxHdrBoost;
    _output.color = float4(col * alpha, 1.0);
    """
}

/// 100% original AAA-grade 3D combat VFX engine for `.shadowArena`:
/// - Catmull-Rom curved HDR blade ribbons hugging real rigged weapon sockets
/// - Native Metal shader-driven sweeping crescent slashes, anamorphic crit/head-hit cross flares,
///   feathered shockwave ripples, ornate Crusader/Samurai ground sigils, crackling lightning arcs,
///   volumetric cathedral god-ray pillars, and velocity-aligned molten spark showers.
/// - ZERO `SCNTorus` plastic donuts, ZERO clipart PNGs, ZERO SF3 copyrighted assets.
@MainActor
final class DuelOriginalVFX {
    private let root = SCNNode()
    private var sparkPool: [(node: SCNNode, system: SCNParticleSystem)] = []
    private var sparkCursor = 0
    private var wispPool: [(node: SCNNode, system: SCNParticleSystem)] = []
    private var wispCursor = 0
    private var crescents: [CrescentFX] = []
    private var ripples: [RippleFX] = []
    private var impactFlashes: [ImpactFlashFX] = []
    private var lightnings: [LightningFX] = []
    private var skyBeams: [SkyBeamFX] = []
    private let flashLightNode = SCNNode()
    private var flashTicks = 0
    private var flashPeakIntensity: CGFloat = 650
    private var fighterAuras: [Int: AuraEmitter] = [:]
    private var salvationEchoMarkers: [Int: (node: SCNNode, material: SCNMaterial)] = [:]
    private var bladeRibbons: [[BladeRibbon]] = []
    private var hasLiveBladeSegments: [Bool] = [false, false]
    private var lastAttackKeys: [String?] = [nil, nil]
    private var lastTrailAttackKeys: [String?] = [nil, nil]

    private struct CrescentFX {
        let node: SCNNode
        let material: SCNMaterial
        var age: Int
        let duration: Int
        let basePitch: Float
        let sweepPitch: Float
        let facing: Float
        let startScale: Float
        let endScale: Float
    }

    private struct RippleFX {
        let node: SCNNode
        let material: SCNMaterial
        var age: Int
        let duration: Int
        let startScale: Float
        let maxScale: Float
        let vertical: Bool
        let spinSpeed: Float
    }

    private struct ImpactFlashFX {
        let node: SCNNode
        let material: SCNMaterial
        let tintRGB: SIMD3<Float>
        var age: Int
        let duration: Int
        let peakScale: Float
    }

    private struct LightningFX {
        let node: SCNNode
        let material: SCNMaterial
        let tintRGB: SIMD3<Float>
        var age: Int
        let duration: Int
    }

    private struct SkyBeamFX {
        let node: SCNNode
        let materials: [SCNMaterial]
        var age: Int
        let duration: Int
    }

    private static func rgbaVector(_ color: UIColor, alphaOverride: Float? = nil) -> SCNVector4 {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SCNVector4(Float(r), Float(g), Float(b), alphaOverride ?? Float(a))
    }

    private static func rgbSIMD(_ color: UIColor) -> SIMD3<Float> {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3<Float>(Float(r), Float(g), Float(b))
    }

    static func makeHDRGlowMaterial(texture: UIImage, color: UIColor, hdrBoost: Float = 2.1) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = texture
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.transparencyMode = .aOne
        mat.blendMode = .add
        mat.writesToDepthBuffer = false
        mat.shaderModifiers = [.fragment: DuelVFXShaders.hdrGlowFragment]
        mat.setValue(NSValue(scnVector4: rgbaVector(color)), forKey: "vfxTint")
        mat.setValue(NSNumber(value: hdrBoost), forKey: "vfxHdrBoost")
        return mat
    }

    /// Catmull-Rom curved, HDR shader-driven 3D blade trail ribbon hugging live animated weapon sockets.
    @MainActor
    private final class BladeRibbon {
        let node = SCNNode()
        private let material = SCNMaterial()
        private var samples: [(base: SIMD3<Float>, tip: SIMD3<Float>)] = []
        private let maxSamples = 9

        init() {
            node.name = "duel.blade.ribbon"
            node.castsShadow = false
            node.renderingOrder = 16
            material.diffuse.contents = DuelProceduralVFXAssets.razorRibbon
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.transparencyMode = .aOne
            material.blendMode = .add
            material.writesToDepthBuffer = false
            material.readsFromDepthBuffer = true
            material.shaderModifiers = [.fragment: DuelVFXShaders.bladeRibbonFragment]
            material.setValue(NSValue(scnVector4: SCNVector4(1, 1, 1, 1)), forKey: "vfxTint")
            material.setValue(NSNumber(value: Float(1.95)), forKey: "vfxHdrBoost")
        }

        func clear() {
            samples.removeAll(keepingCapacity: true)
            node.geometry = nil
            node.isHidden = true
        }

        func push(base: SIMD3<Float>, tip: SIMD3<Float>, color: UIColor, hdrBoost: Float) {
            material.setValue(NSValue(scnVector4: DuelOriginalVFX.rgbaVector(color)), forKey: "vfxTint")
            material.setValue(NSNumber(value: hdrBoost), forKey: "vfxHdrBoost")

            // Slightly pull base toward the mid-blade so the ribbon gracefully hugs the cutting edge
            let shiftedBase = simd_mix(base, tip, SIMD3<Float>(repeating: 0.22))
            let lift = SIMD3<Float>(0, 0, 0.03)
            if let last = samples.last {
                let dist = simd_distance(last.tip, tip + lift)
                if dist < 0.015 {
                    // Skip stationary micro-jitter frames so the blade ribbon stays sweeping & sleek
                    return
                }
                if dist > 1.85 {
                    // Guard against teleport / blink discontinuity stretching a straight ribbon across the stage
                    samples.removeAll(keepingCapacity: true)
                }
            }
            samples.append((shiftedBase + lift, tip + lift))
            if samples.count > maxSamples {
                samples.removeFirst(samples.count - maxSamples)
            }
            rebuild()
        }

        func fadeTail() {
            guard !samples.isEmpty else {
                node.isHidden = true
                return
            }
            samples.removeFirst()
            if samples.count < 2 {
                clear()
            } else {
                rebuild()
            }
        }

        private static func catmullRom(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>, t: Float) -> SIMD3<Float> {
            let t2 = t * t
            let t3 = t2 * t
            return 0.5 * (
                (2.0 * p1) +
                (-p0 + p2) * t +
                (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
                (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
            )
        }

        private func rebuild() {
            let rawCount = samples.count
            guard rawCount >= 2 else {
                node.geometry = nil
                node.isHidden = true
                return
            }
            // Sub-sample every segment 3x via Catmull-Rom spline for buttery curved arcs
            let subdivisions = 3
            var curve: [(base: SIMD3<Float>, tip: SIMD3<Float>)] = []
            curve.reserveCapacity((rawCount - 1) * subdivisions + 1)
            for i in 0..<(rawCount - 1) {
                let p0 = samples[max(0, i - 1)]
                let p1 = samples[i]
                let p2 = samples[i + 1]
                let p3 = samples[min(rawCount - 1, i + 2)]
                for s in 0..<subdivisions {
                    let t = Float(s) / Float(subdivisions)
                    let b = Self.catmullRom(p0.base, p1.base, p2.base, p3.base, t: t)
                    let tip = Self.catmullRom(p0.tip, p1.tip, p2.tip, p3.tip, t: t)
                    curve.append((b, tip))
                }
            }
            curve.append(samples[rawCount - 1])

            let count = curve.count
            var vertices: [SCNVector3] = []
            var texcoords: [CGPoint] = []
            var indices: [UInt16] = []
            vertices.reserveCapacity(count * 2)
            texcoords.reserveCapacity(count * 2)
            indices.reserveCapacity((count - 1) * 6)

            for i in 0..<count {
                let u = Float(i) / Float(count - 1)
                let s = curve[i]
                // Smoothly taper tail width toward the tip so the ribbon finishes in a razor point!
                let taper = pow(u, 0.55)
                let taperedBase = simd_mix(s.tip, s.base, SIMD3<Float>(repeating: max(0.14, taper)))
                vertices.append(SCNVector3(taperedBase.x, taperedBase.y, taperedBase.z))
                vertices.append(SCNVector3(s.tip.x, s.tip.y, s.tip.z))
                texcoords.append(CGPoint(x: CGFloat(u), y: 0.0))
                texcoords.append(CGPoint(x: CGFloat(u), y: 1.0))
                if i + 1 < count {
                    let v0 = UInt16(i * 2)
                    let v1 = v0 + 1
                    let v2 = v0 + 2
                    let v3 = v0 + 3
                    indices.append(contentsOf: [v0, v1, v2, v2, v1, v3])
                }
            }

            let vSource = SCNGeometrySource(vertices: vertices)
            let uvSource = SCNGeometrySource(textureCoordinates: texcoords)
            let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
            let geom = SCNGeometry(sources: [vSource, uvSource], elements: [element])
            geom.materials = [material]
            node.geometry = geom
            node.isHidden = false
        }
    }

    /// Dual-layer subtle hero aura: rising wispy mist + tiny sharp drifting energy embers.
    @MainActor
    private final class AuraEmitter {
        let node = SCNNode()
        private let wispSystem = SCNParticleSystem()
        private let emberSystem = SCNParticleSystem()
        var currentKind: AuraKind = .none

        enum AuraKind: Equatable {
            case none, shogunShadow, shogunCataclysm, shogunCharge
            case inquisitorLight, nonnaFlame, nonnaEmber
            case midnightShift, midnightBlink, midnightShadow
        }

        init() {
            // Layer 1: soft rising volumetric shadow-ink / flame wisps (subtle, never giant blobs!)
            wispSystem.birthRate = 0
            wispSystem.particleImage = DuelProceduralVFXAssets.smokeWisp
            wispSystem.particleLifeSpan = 0.62
            wispSystem.particleLifeSpanVariation = 0.22
            wispSystem.particleSize = 0.24
            wispSystem.particleSizeVariation = 0.08
            wispSystem.particleVelocity = 0.65
            wispSystem.particleVelocityVariation = 0.28
            wispSystem.spreadingAngle = 24
            wispSystem.emittingDirection = SCNVector3(0, 1, 0)
            wispSystem.emitterShape = SCNCylinder(radius: 0.28, height: 1.25)
            wispSystem.blendMode = .additive
            wispSystem.isLightingEnabled = false
            wispSystem.isAffectedByGravity = false
            wispSystem.loops = true

            // Layer 2: tiny razor-bright drifting embers / motes that trigger HDR bloom!
            emberSystem.birthRate = 0
            emberSystem.particleImage = DuelProceduralVFXAssets.sparkNeedle
            emberSystem.particleLifeSpan = 0.55
            emberSystem.particleLifeSpanVariation = 0.20
            emberSystem.particleSize = 0.075
            emberSystem.particleSizeVariation = 0.03
            emberSystem.particleVelocity = 1.25
            emberSystem.particleVelocityVariation = 0.55
            emberSystem.spreadingAngle = 28
            emberSystem.emittingDirection = SCNVector3(0, 1, 0)
            emberSystem.emitterShape = SCNCylinder(radius: 0.34, height: 1.35)
            emberSystem.stretchFactor = 0.04
            emberSystem.blendMode = .additive
            emberSystem.isLightingEnabled = false
            emberSystem.isAffectedByGravity = false
            emberSystem.loops = true

            node.addParticleSystem(wispSystem)
            node.addParticleSystem(emberSystem)
        }

        func update(kind: AuraKind, position: SCNVector3) {
            node.position = position
            guard kind != currentKind else { return }
            currentKind = kind
            switch kind {
            case .none:
                wispSystem.birthRate = 0
                emberSystem.birthRate = 0
            case .shogunShadow:
                wispSystem.particleColor = UIColor(red: 0.52, green: 0.18, blue: 1.0, alpha: 0.36)
                wispSystem.birthRate = 18; wispSystem.particleSize = 0.26
                emberSystem.particleColor = UIColor(red: 0.85, green: 0.52, blue: 1.0, alpha: 0.95)
                emberSystem.birthRate = 24; emberSystem.particleSize = 0.075
            case .shogunCataclysm:
                wispSystem.particleColor = UIColor(red: 1.0, green: 0.12, blue: 0.22, alpha: 0.45)
                wispSystem.birthRate = 28; wispSystem.particleSize = 0.30
                emberSystem.particleColor = UIColor(red: 1.0, green: 0.42, blue: 0.30, alpha: 1.0)
                emberSystem.birthRate = 42; emberSystem.particleSize = 0.09
            case .shogunCharge:
                wispSystem.particleColor = UIColor(red: 1.0, green: 0.68, blue: 0.18, alpha: 0.26)
                wispSystem.birthRate = 12; wispSystem.particleSize = 0.20
                emberSystem.particleColor = UIColor(red: 1.0, green: 0.88, blue: 0.45, alpha: 0.95)
                emberSystem.birthRate = 24; emberSystem.particleSize = 0.07
            case .inquisitorLight:
                wispSystem.particleColor = UIColor(red: 1.0, green: 0.86, blue: 0.36, alpha: 0.34)
                wispSystem.birthRate = 20; wispSystem.particleSize = 0.26
                emberSystem.particleColor = UIColor(red: 1.0, green: 0.96, blue: 0.68, alpha: 1.0)
                emberSystem.birthRate = 34; emberSystem.particleSize = 0.07
            case .nonnaFlame:
                wispSystem.particleColor = UIColor(red: 1.0, green: 0.38, blue: 0.06, alpha: 0.44)
                wispSystem.birthRate = 28; wispSystem.particleSize = 0.28
                emberSystem.particleColor = UIColor(red: 1.0, green: 0.78, blue: 0.28, alpha: 1.0)
                emberSystem.birthRate = 44; emberSystem.particleSize = 0.085
            case .nonnaEmber:
                wispSystem.particleColor = UIColor(red: 1.0, green: 0.48, blue: 0.12, alpha: 0.24)
                wispSystem.birthRate = 12; wispSystem.particleSize = 0.20
                emberSystem.particleColor = UIColor(red: 1.0, green: 0.72, blue: 0.28, alpha: 0.90)
                emberSystem.birthRate = 18; emberSystem.particleSize = 0.065
            case .midnightShift:
                wispSystem.particleColor = UIColor(red: 0.44, green: 0.18, blue: 0.92, alpha: 0.40)
                wispSystem.birthRate = 24; wispSystem.particleSize = 0.28
                emberSystem.particleColor = UIColor(red: 0.66, green: 0.56, blue: 1.0, alpha: 0.90)
                emberSystem.birthRate = 20; emberSystem.particleSize = 0.065
            case .midnightBlink:
                wispSystem.particleColor = UIColor(red: 0.28, green: 0.82, blue: 1.0, alpha: 0.34)
                wispSystem.birthRate = 16; wispSystem.particleSize = 0.22
                emberSystem.particleColor = UIColor(red: 0.68, green: 0.95, blue: 1.0, alpha: 1.0)
                emberSystem.birthRate = 26; emberSystem.particleSize = 0.07
            case .midnightShadow:
                wispSystem.particleColor = UIColor(red: 0.72, green: 0.18, blue: 1.0, alpha: 0.38)
                wispSystem.birthRate = 22; wispSystem.particleSize = 0.26
                emberSystem.particleColor = UIColor(red: 0.95, green: 0.52, blue: 1.0, alpha: 1.0)
                emberSystem.birthRate = 32; emberSystem.particleSize = 0.075
            }
        }
    }

    init(parent: SCNNode) {
        DuelProceduralVFXAssets.prepare()
        root.name = "duel.original.vfx"
        parent.addChildNode(root)

        // Pool 1: High-velocity directional metallic needle spark showers
        for _ in 0..<8 {
            let node = SCNNode()
            let sys = SCNParticleSystem()
            sys.birthRate = 0
            sys.emissionDuration = 0.05
            sys.loops = false
            sys.particleImage = DuelProceduralVFXAssets.sparkNeedle
            sys.particleLifeSpan = 0.28
            sys.particleLifeSpanVariation = 0.12
            sys.particleSize = 0.095
            sys.particleSizeVariation = 0.04
            sys.particleVelocity = 5.4
            sys.particleVelocityVariation = 2.4
            sys.spreadingAngle = 125
            sys.stretchFactor = 0.075
            sys.blendMode = .additive
            sys.isLightingEnabled = false
            sys.isAffectedByGravity = true
            sys.acceleration = SCNVector3(0, -6.5, 0)
            node.addParticleSystem(sys)
            root.addChildNode(node)
            sparkPool.append((node, sys))
        }

        // Pool 2: Soft organic turbulent smoke / flame / dust bursts
        for _ in 0..<6 {
            let node = SCNNode()
            let sys = SCNParticleSystem()
            sys.birthRate = 0
            sys.emissionDuration = 0.08
            sys.loops = false
            sys.particleImage = DuelProceduralVFXAssets.smokeWisp
            sys.particleLifeSpan = 0.42
            sys.particleLifeSpanVariation = 0.16
            sys.particleSize = 0.32
            sys.particleSizeVariation = 0.14
            sys.particleVelocity = 2.2
            sys.particleVelocityVariation = 1.0
            sys.spreadingAngle = 140
            sys.blendMode = .additive
            sys.isLightingEnabled = false
            sys.isAffectedByGravity = false
            node.addParticleSystem(sys)
            root.addChildNode(node)
            wispPool.append((node, sys))
        }

        // Tasteful localized rim accent light (NEVER bleaches the stage floor!)
        let light = SCNLight()
        light.type = .omni
        light.intensity = 0
        light.attenuationStartDistance = 0.8
        light.attenuationEndDistance = 4.2
        flashLightNode.light = light
        root.addChildNode(flashLightNode)

        for i in 0..<2 {
            let aura = AuraEmitter()
            root.addChildNode(aura.node)
            fighterAuras[i] = aura

            // Light's Will 2nd sky-smite ornate rotating floor sigil (NO torus!)
            let sigilPlane = SCNPlane(width: 1.45, height: 1.45)
            let sigilMat = Self.makeHDRGlowMaterial(
                texture: DuelProceduralVFXAssets.crusaderSigil,
                color: UIColor(red: 1.0, green: 0.86, blue: 0.28, alpha: 1),
                hdrBoost: 2.15
            )
            sigilPlane.materials = [sigilMat]
            let echoNode = SCNNode(geometry: sigilPlane)
            echoNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            echoNode.castsShadow = false
            echoNode.renderingOrder = 12
            echoNode.isHidden = true
            root.addChildNode(echoNode)
            salvationEchoMarkers[i] = (echoNode, sigilMat)

            var pair: [BladeRibbon] = []
            for _ in 0..<2 {
                let ribbon = BladeRibbon()
                root.addChildNode(ribbon.node)
                pair.append(ribbon)
            }
            bladeRibbons.append(pair)
        }
    }

    func reset() {
        for c in crescents { c.node.removeFromParentNode() }; crescents.removeAll()
        for r in ripples { r.node.removeFromParentNode() }; ripples.removeAll()
        for f in impactFlashes { f.node.removeFromParentNode() }; impactFlashes.removeAll()
        for l in lightnings { l.node.removeFromParentNode() }; lightnings.removeAll()
        for b in skyBeams { b.node.removeFromParentNode() }; skyBeams.removeAll()
        flashTicks = 0
        flashLightNode.light?.intensity = 0
        lastAttackKeys = [nil, nil]
        lastTrailAttackKeys = [nil, nil]
        hasLiveBladeSegments = [false, false]
        for pair in bladeRibbons { for r in pair { r.clear() } }
        for aura in fighterAuras.values { aura.update(kind: .none, position: SCNVector3Zero) }
        for marker in salvationEchoMarkers.values { marker.node.isHidden = true }
    }

    func shutdown() {
        reset()
        root.removeFromParentNode()
        sparkPool.removeAll()
        wispPool.removeAll()
        bladeRibbons.removeAll()
        fighterAuras.removeAll()
        salvationEchoMarkers.removeAll()
    }

    private func heroEnergyColor(_ hero: DuelGame.Hero, enhanced: Bool = false) -> UIColor {
        if enhanced {
            switch hero {
            case .wuYong: return UIColor(red: 1.0, green: 0.16, blue: 0.36, alpha: 1)
            case .gale: return UIColor(red: 1.0, green: 0.88, blue: 0.30, alpha: 1)
            case .liu: return UIColor(red: 1.0, green: 0.42, blue: 0.08, alpha: 1)
            case .ember: return UIColor(red: 0.78, green: 0.24, blue: 1.0, alpha: 1)
            }
        }
        switch hero {
        case .wuYong: return UIColor(red: 0.90, green: 0.32, blue: 0.34, alpha: 1)
        case .gale: return UIColor(red: 1.0, green: 0.85, blue: 0.42, alpha: 1)
        case .liu: return UIColor(red: 1.0, green: 0.56, blue: 0.16, alpha: 1)
        case .ember: return UIColor(red: 0.46, green: 0.78, blue: 1.0, alpha: 1)
        }
    }

    private func emitSparks(at position: SCNVector3, color: UIColor, count: CGFloat,
                            speed: CGFloat = 5.4, size: CGFloat = 0.095,
                            spread: CGFloat = 115, direction: SCNVector3 = SCNVector3(0, 1, 0)) {
        guard !sparkPool.isEmpty else { return }
        let entry = sparkPool[sparkCursor]
        sparkCursor = (sparkCursor + 1) % sparkPool.count
        entry.node.position = position
        let sys = entry.system
        sys.reset()
        sys.particleColor = color
        sys.particleSize = size
        sys.particleVelocity = speed
        sys.spreadingAngle = spread
        sys.emittingDirection = direction
        sys.emissionDuration = 0.05
        sys.birthRate = count / 0.05
        sys.loops = false
    }

    private func emitWisps(at position: SCNVector3, color: UIColor, count: CGFloat,
                           size: CGFloat = 0.34, speed: CGFloat = 2.0, life: CGFloat = 0.42,
                           spread: CGFloat = 140, direction: SCNVector3 = SCNVector3(0, 1, 0)) {
        guard !wispPool.isEmpty else { return }
        let entry = wispPool[wispCursor]
        wispCursor = (wispCursor + 1) % wispPool.count
        entry.node.position = position
        let sys = entry.system
        sys.reset()
        sys.particleColor = color
        sys.particleSize = size
        sys.particleVelocity = speed
        sys.particleLifeSpan = life
        sys.spreadingAngle = spread
        sys.emittingDirection = direction
        sys.emissionDuration = 0.07
        sys.birthRate = count / 0.07
        sys.loops = false
    }

    /// Spawn a razor-thin feathered shockwave ripple or ornate ground seal (ZERO plastic torus!).
    private func spawnRipple(at position: SCNVector3, color: UIColor, texture: UIImage? = nil,
                             startScale: Float = 0.35, maxScale: Float = 2.2,
                             duration: Int = 14, vertical: Bool = true,
                             hdrBoost: Float = 1.95, spinSpeed: Float = 0) {
        let plane = SCNPlane(width: 1.0, height: 1.0)
        let mat = SCNMaterial()
        mat.diffuse.contents = texture ?? DuelProceduralVFXAssets.shockRipple
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.transparencyMode = .aOne
        mat.blendMode = .add
        mat.writesToDepthBuffer = false
        mat.shaderModifiers = [.fragment: DuelVFXShaders.shockRippleFragment]
        mat.setValue(NSValue(scnVector4: Self.rgbaVector(color)), forKey: "vfxTint")
        mat.setValue(NSNumber(value: Float(0)), forKey: "vfxProgress")
        mat.setValue(NSNumber(value: hdrBoost), forKey: "vfxHdrBoost")
        plane.materials = [mat]

        let node = SCNNode(geometry: plane)
        node.position = position
        node.castsShadow = false
        node.renderingOrder = 17
        node.scale = SCNVector3(startScale, startScale, 1)
        if !vertical {
            node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        }
        root.addChildNode(node)
        ripples.append(RippleFX(node: node, material: mat, age: 0, duration: duration,
                                startScale: startScale, maxScale: maxScale,
                                vertical: vertical, spinSpeed: spinSpeed))
    }

    /// Spawn an authentic SF4 Arena HDR-blooming anamorphic hit starburst cross-flare!
    private func spawnImpactCross(at position: SCNVector3, color: UIColor, peakScale: Float = 1.35,
                                  duration: Int = 9, roll: Float = 0, hdrBoost: Float = 2.45) {
        let plane = SCNPlane(width: 1.0, height: 1.0)
        let mat = Self.makeHDRGlowMaterial(texture: DuelProceduralVFXAssets.impactCross, color: color, hdrBoost: hdrBoost)
        plane.materials = [mat]
        let node = SCNNode(geometry: plane)
        node.position = position
        node.eulerAngles = SCNVector3(0, 0, roll)
        node.scale = SCNVector3(0.25, 0.25, 1)
        node.castsShadow = false
        node.renderingOrder = 20
        root.addChildNode(node)
        impactFlashes.append(ImpactFlashFX(node: node, material: mat, tintRGB: Self.rgbSIMD(color),
                                           age: 0, duration: duration, peakScale: peakScale))
    }

    /// Spawn a shader-animated sweeping crescent energy slash!
    private func spawnCrescent(at position: SCNVector3, color: UIColor, facing: Float,
                               basePitch: Float, sweepPitch: Float,
                               startScale: Float = 1.15, endScale: Float = 1.75,
                               duration: Int = 13, hdrBoost: Float = 2.2) {
        let plane = SCNPlane(width: 1.25, height: 1.25)
        let mat = SCNMaterial()
        mat.diffuse.contents = DuelProceduralVFXAssets.slashCrescent
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.transparencyMode = .aOne
        mat.blendMode = .add
        mat.writesToDepthBuffer = false
        mat.shaderModifiers = [.fragment: DuelVFXShaders.crescentSlashFragment]
        mat.setValue(NSValue(scnVector4: Self.rgbaVector(color)), forKey: "vfxTint")
        mat.setValue(NSNumber(value: Float(0)), forKey: "vfxProgress")
        mat.setValue(NSNumber(value: hdrBoost), forKey: "vfxHdrBoost")
        plane.materials = [mat]

        let node = SCNNode(geometry: plane)
        node.position = position
        node.eulerAngles = SCNVector3(0, facing > 0 ? 0 : .pi, basePitch * facing)
        node.scale = SCNVector3(startScale, startScale, 1)
        node.castsShadow = false
        node.renderingOrder = 18
        root.addChildNode(node)
        crescents.append(CrescentFX(node: node, material: mat, age: 0, duration: duration,
                                    basePitch: basePitch, sweepPitch: sweepPitch, facing: facing,
                                    startScale: startScale, endScale: endScale))
    }

    /// Spawn jagged electric shadow-lightning crackling bolt with HDR bloom!
    private func spawnLightning(at position: SCNVector3, color: UIColor, height: Float = 1.85,
                                roll: Float = 0, duration: Int = 10, hdrBoost: Float = 2.55) {
        let plane = SCNPlane(width: CGFloat(height * 0.34), height: CGFloat(height))
        let mat = Self.makeHDRGlowMaterial(texture: DuelProceduralVFXAssets.lightningArc, color: color, hdrBoost: hdrBoost)
        plane.materials = [mat]
        let node = SCNNode(geometry: plane)
        node.position = position
        node.eulerAngles = SCNVector3(0, 0, roll)
        node.castsShadow = false
        node.renderingOrder = 19
        root.addChildNode(node)
        lightnings.append(LightningFX(node: node, material: mat, tintRGB: Self.rgbSIMD(color),
                                      age: 0, duration: duration))
    }

    /// Spawn a descending volumetric cathedral god-ray pillar for Light's Will 2nd sky smite & Form of Light!
    private func spawnSkyBeam(atX fx: Float, color: UIColor, width: CGFloat = 1.15, duration: Int = 18) {
        let container = SCNNode()
        container.position = SCNVector3(fx, 1.95, 0.22)
        var mats: [SCNMaterial] = []
        let tint = Self.rgbaVector(color)
        for angle in [Float(0), Float.pi * 0.25, -Float.pi * 0.25] {
            let plane = SCNPlane(width: width, height: 4.2)
            let mat = SCNMaterial()
            mat.diffuse.contents = DuelProceduralVFXAssets.energyBeam
            mat.lightingModel = .constant
            mat.isDoubleSided = true
            mat.transparencyMode = .aOne
            mat.blendMode = .add
            mat.writesToDepthBuffer = false
            mat.shaderModifiers = [.fragment: DuelVFXShaders.godRayBeamFragment]
            mat.setValue(NSValue(scnVector4: tint), forKey: "vfxTint")
            mat.setValue(NSNumber(value: Float(2.40)), forKey: "vfxHdrBoost")
            mat.setValue(NSNumber(value: Float(1.0)), forKey: "vfxOpacity")
            plane.materials = [mat]
            mats.append(mat)
            let n = SCNNode(geometry: plane)
            n.eulerAngles = SCNVector3(0, angle, 0)
            n.castsShadow = false
            n.renderingOrder = 17
            container.addChildNode(n)
        }
        root.addChildNode(container)
        skyBeams.append(SkyBeamFX(node: container, materials: mats, age: 0, duration: duration))
    }

    private func triggerAccentLight(at position: SCNVector3, color: UIColor, intensity: CGFloat = 580, ticks: Int = 7) {
        flashLightNode.position = SCNVector3(position.x, position.y + 0.25, 1.25)
        flashLightNode.light?.color = color
        flashLightNode.light?.intensity = intensity
        flashPeakIntensity = intensity
        flashTicks = max(flashTicks, ticks)
    }

    private func spawnMoveCrescent(fighter: DuelGame.Fighter, move: DuelGame.Move, enhanced: Bool) {
        let isKick = move == .kick || move == .kickForward || move == .kickUp || move == .kickDown || move == .kickBack
        let isThrow = move == .throwForward || move == .throwBack
        if isThrow { return }
        let color = isKick
            ? UIColor(red: 0.78, green: 0.90, blue: 1.0, alpha: 0.85)
            : heroEnergyColor(fighter.hero, enhanced: enhanced)
        let facing = Float(fighter.facing)
        let yOff: Float
        let baseP: Float
        let sweepP: Float
        let scale: Float = isKick ? 0.92 : (move == .heavy || move == .skill2 ? 1.55 : 1.22)
        switch move {
        case .weaponUp, .kickUp:
            yOff = 1.42; baseP = 0.65; sweepP = -1.20
        case .weaponDown, .kickDown:
            yOff = 0.48; baseP = -0.35; sweepP = 0.55
        case .heavy, .skill2:
            yOff = 1.18; baseP = -0.80; sweepP = 1.45
        case .inquisitorLightSpin:
            yOff = 1.12; baseP = 0.0; sweepP = 2.8
        default:
            yOff = 1.12; baseP = -0.25; sweepP = 0.80
        }
        let pos = SCNVector3(Float(fighter.x) / 1000 + facing * 0.62, Float(fighter.y) / 1000 + yOff, 0.24)
        spawnCrescent(at: pos, color: color, facing: facing, basePitch: baseP, sweepPitch: sweepP,
                      startScale: scale * 0.82, endScale: scale * 1.15, duration: 11, hdrBoost: isKick ? 1.55 : 2.25)
    }

    private static func isKickOrThrow(_ move: DuelGame.Move) -> Bool {
        switch move {
        case .kick, .kickForward, .kickUp, .kickDown, .kickBack, .throwForward, .throwBack:
            return true
        default:
            return false
        }
    }

    private func isHeroEnhanced(_ game: DuelGame, index: Int) -> Bool {
        (game.shogunState(index)?.isInShadow == true) ||
        (game.inquisitorState(index)?.isInFormOfLight == true) ||
        (game.nonnaState(index)?.isInFlameForm == true) ||
        (game.midnightState(index)?.isInShadowForm == true)
    }

    /// Sample live world-space weapon `(base, tip)` segments from rigged actors every frame
    /// to paint silky Catmull-Rom HDR blade ribbons hugging the Odachi, Great Axe, Greatsword, and Dual Ninjato.
    func sampleBladeTrails(game: DuelGame, bladeSegments: [[(base: SIMD3<Float>, tip: SIMD3<Float>)]]) {
        guard game.fighters.count == 2 else { return }
        for i in 0..<2 {
            let segs = bladeSegments.indices.contains(i) ? bladeSegments[i] : []
            hasLiveBladeSegments[i] = !segs.isEmpty
            guard bladeRibbons.indices.contains(i) else { continue }
            let f = game.fighters[i]
            var activeBladeSwing = false
            var color = heroEnergyColor(f.hero, enhanced: isHeroEnhanced(game, index: i))
            var hdrBoost: Float = 1.95
            if let attack = f.attack, !Self.isKickOrThrow(attack.move) {
                let trailKey = "\(attack.move.rawValue):\(game.frame - attack.age)"
                if lastTrailAttackKeys[i] != trailKey {
                    lastTrailAttackKeys[i] = trailKey
                    for ribbon in bladeRibbons[i] { ribbon.clear() }
                }
                let data = DuelGame.data(attack.move, hero: f.hero, chargeTicks: attack.chargeTicks)
                let startWin = max(0, data.startup - 1)
                let endWin = data.startup + data.active + 5
                if attack.age >= startWin && attack.age <= endWin {
                    activeBladeSwing = true
                    let signature = attack.move == .heavy || attack.move == .shogunFierceReprisal ||
                        attack.move == .shogunDespotism || attack.move == .inquisitorLightSpin ||
                        attack.move == .midnightRemoval || attack.move == .skill2
                    if signature || isHeroEnhanced(game, index: i) {
                        color = heroEnergyColor(f.hero, enhanced: true)
                        hdrBoost = 2.55
                    }
                }
            } else {
                lastTrailAttackKeys[i] = nil
            }
            for hand in 0..<bladeRibbons[i].count {
                let ribbon = bladeRibbons[i][hand]
                if activeBladeSwing && hand < segs.count {
                    ribbon.push(base: segs[hand].base, tip: segs[hand].tip, color: color, hdrBoost: hdrBoost)
                } else {
                    ribbon.fadeTail()
                }
            }
        }
    }

    private func impactPosition(defender: DuelGame.Fighter, z: Float = 0.34) -> SCNVector3 {
        let cx = defender.lastContactX != 0 ? Float(defender.lastContactX) / 1000 : Float(defender.x) / 1000
        let cy = defender.lastContactY > 0 ? Float(defender.lastContactY) / 1000 : Float(defender.y) / 1000 + 1.15
        return SCNVector3(cx, cy, z)
    }

    /// Consume simulation step events & fighter states to drive layered HDR combat VFX.
    func consumeStep(_ game: DuelGame, tick: Int) {
        guard game.fighters.count == 2 else { return }

        // 1. Trigger sleek crescent slash arcs & signature SF4 startup VFX!
        for i in 0..<2 {
            let f = game.fighters[i]
            if let attack = f.attack {
                let data = DuelGame.data(attack.move, hero: f.hero, chargeTicks: attack.chargeTicks)
                let key = "\(attack.move.rawValue):\(tick - attack.age)"
                if attack.age >= data.startup && lastAttackKeys[i] != key {
                    lastAttackKeys[i] = key
                    let enhanced = isHeroEnhanced(game, index: i)
                    let isPowerSlash = attack.move == .heavy || attack.move == .skill2 || enhanced
                    let hasCustomSkillVFX = attack.move == .shogunDespotism || attack.move == .shogunFierceReprisal ||
                        attack.move == .inquisitorLightSpin || attack.move == .midnightRemoval
                    let needsCrescent = !hasLiveBladeSegments[i] || Self.isKickOrThrow(attack.move) || (isPowerSlash && !hasCustomSkillVFX)
                    if needsCrescent {
                        spawnMoveCrescent(fighter: f, move: attack.move, enhanced: enhanced)
                    }
                    let facing = Float(f.facing)
                    let fx = Float(f.x) / 1000
                    let fy = Float(f.y) / 1000
                    let origin = SCNVector3(fx + facing * 0.55, fy + 1.12, 0.28)
                    switch attack.move {
                    case .shogunDespotism:
                        // Despotism: calligraphic purple samurai seal on floor + curved shadow barrier + crackling lightning!
                        let floorPos = SCNVector3(fx + facing * 0.45, 0.05, 0.14)
                        spawnRipple(at: floorPos, color: UIColor(red: 0.68, green: 0.26, blue: 1.0, alpha: 1),
                                    texture: DuelProceduralVFXAssets.shogunSeal,
                                    startScale: 0.65, maxScale: 2.35, duration: 22, vertical: false, hdrBoost: 2.3, spinSpeed: 0.14)
                        spawnCrescent(at: origin, color: UIColor(red: 0.66, green: 0.24, blue: 1.0, alpha: 1),
                                      facing: facing, basePitch: 0.70, sweepPitch: -1.45,
                                      startScale: 1.30, endScale: 1.90, duration: 15, hdrBoost: 2.4)
                        spawnLightning(at: SCNVector3(fx + facing * 0.65, fy + 1.15, 0.30),
                                       color: UIColor(red: 0.78, green: 0.38, blue: 1.0, alpha: 1), height: 1.7, roll: 0.18 * facing)
                        emitWisps(at: origin, color: UIColor(red: 0.52, green: 0.18, blue: 0.95, alpha: 0.45),
                                  count: 14, size: 0.36, speed: 1.9, direction: SCNVector3(-facing, 0.3, 0))
                        triggerAccentLight(at: origin, color: .systemPurple, intensity: 640, ticks: 9)

                    case .shogunFierceReprisal:
                        // Fierce Reprisal: staggered double crimson-violet dash crescent slashes + molten sparks!
                        let col = UIColor(red: 1.0, green: 0.16, blue: 0.38, alpha: 1)
                        spawnCrescent(at: origin, color: col, facing: facing, basePitch: -0.95, sweepPitch: 1.85,
                                      startScale: 1.35, endScale: 2.05, duration: 14, hdrBoost: 2.5)
                        spawnCrescent(at: SCNVector3(origin.x + facing * 0.32, origin.y + 0.08, 0.30),
                                      color: UIColor(red: 0.72, green: 0.24, blue: 1.0, alpha: 1),
                                      facing: facing, basePitch: 0.55, sweepPitch: -1.35,
                                      startScale: 1.15, endScale: 1.85, duration: 13, hdrBoost: 2.2)
                        emitSparks(at: origin, color: col, count: 24, speed: 6.2, spread: 70, direction: SCNVector3(-facing, 0.2, 0))

                    case .inquisitorLightSpin:
                        // Tower's Dogma: radiant golden spinning crescent + floor Crusader sigil!
                        let gold = UIColor(red: 1.0, green: 0.88, blue: 0.30, alpha: 1)
                        spawnCrescent(at: origin, color: gold, facing: facing, basePitch: -0.20, sweepPitch: 3.14,
                                      startScale: 1.40, endScale: 2.10, duration: 15, hdrBoost: 2.4)
                        spawnRipple(at: SCNVector3(fx, 0.05, 0.12), color: gold,
                                    texture: DuelProceduralVFXAssets.crusaderSigil,
                                    startScale: 0.70, maxScale: 2.20, duration: 18, vertical: false, hdrBoost: 2.1, spinSpeed: 0.12)

                    case .midnightRemoval:
                        // Midnight Removal: dimensional dash lightning flash right as Sun Deng teleports!
                        let violet = UIColor(red: 0.84, green: 0.24, blue: 1.0, alpha: 1)
                        spawnLightning(at: SCNVector3(fx, fy + 1.05, 0.30), color: violet, height: 1.85, roll: -0.35 * facing, duration: 9)
                        emitWisps(at: origin, color: UIColor(red: 0.58, green: 0.18, blue: 0.96, alpha: 0.42),
                                  count: 14, size: 0.34, speed: 2.4)
                    default:
                        break
                    }
                }
            } else {
                lastAttackKeys[i] = nil
            }
        }

        // 2. Crisp layered hit / parry / crit / skill impacts (ZERO solid donuts!)
        for event in game.events {
            switch event {
            case .hit(let attacker, let damage):
                let def = game.fighters[1 - attacker]
                let dir = Float(game.fighters[attacker].facing)
                let pos = impactPosition(defender: def, z: 0.36)
                let heavy = damage >= 260 || (game.ruleset == .laboratory && damage >= 145)
                let color = heroEnergyColor(game.fighters[attacker].hero, enhanced: heavy)
                emitSparks(at: pos, color: color, count: heavy ? 28 : 14, speed: heavy ? 6.4 : 4.6,
                           size: heavy ? 0.105 : 0.08, spread: 105, direction: SCNVector3(dir, 0.35, 0))
                spawnImpactCross(at: pos, color: heavy ? color : UIColor(red: 1.0, green: 0.94, blue: 0.78, alpha: 1),
                                 peakScale: heavy ? 1.45 : 0.88, duration: heavy ? 9 : 6, roll: Float(tick % 7) * 0.12 - 0.35)
                if heavy {
                    spawnRipple(at: pos, color: color, startScale: 0.30, maxScale: 1.65, duration: 12, vertical: true, hdrBoost: 1.9)
                    triggerAccentLight(at: pos, color: color, intensity: 520, ticks: 6)
                }

            case .headHit(let attacker, _):
                let def = game.fighters[1 - attacker]
                let raw = impactPosition(defender: def, z: 0.40)
                let pos = SCNVector3(raw.x, max(raw.y, Float(def.y) / 1000 + 1.56), 0.40)
                let gold = UIColor(red: 1.0, green: 0.92, blue: 0.44, alpha: 1)
                spawnImpactCross(at: pos, color: gold, peakScale: 1.75, duration: 10, roll: 0.08)
                spawnRipple(at: pos, color: gold, startScale: 0.25, maxScale: 1.45, duration: 12, vertical: true, hdrBoost: 2.2)
                emitSparks(at: pos, color: gold, count: 26, speed: 6.2, size: 0.09, spread: 165)
                triggerAccentLight(at: pos, color: gold, intensity: 600, ticks: 6)

            case .criticalHit(let attacker, _), .shogunCritical(let attacker, _):
                let def = game.fighters[1 - attacker]
                let pos = impactPosition(defender: def, z: 0.42)
                let crimson = UIColor(red: 1.0, green: 0.28, blue: 0.16, alpha: 1)
                spawnImpactCross(at: pos, color: UIColor(red: 1.0, green: 0.84, blue: 0.42, alpha: 1),
                                 peakScale: 2.15, duration: 11, roll: 0.0)
                spawnRipple(at: pos, color: crimson, startScale: 0.32, maxScale: 2.05, duration: 13, vertical: true, hdrBoost: 2.3)
                spawnLightning(at: pos, color: UIColor(red: 1.0, green: 0.55, blue: 0.24, alpha: 1), height: 1.35, roll: 0.55, duration: 8)
                emitSparks(at: pos, color: UIColor(red: 1.0, green: 0.62, blue: 0.24, alpha: 1), count: 36, speed: 7.4, size: 0.11, spread: 165)
                triggerAccentLight(at: pos, color: crimson, intensity: 720, ticks: 8)

            case .blocked(let defender):
                let def = game.fighters[defender]
                let pos = impactPosition(defender: def, z: 0.38)
                let ice = UIColor(red: 0.52, green: 0.90, blue: 1.0, alpha: 1)
                spawnImpactCross(at: pos, color: ice, peakScale: 1.15, duration: 7, roll: 0.42)
                spawnRipple(at: pos, color: ice, startScale: 0.24, maxScale: 1.15, duration: 9, vertical: true, hdrBoost: 1.75)
                emitSparks(at: pos, color: UIColor(red: 0.80, green: 0.96, blue: 1.0, alpha: 1),
                           count: 18, speed: 5.5, size: 0.08, spread: 95,
                           direction: SCNVector3(Float(def.facing), 0.35, 0))

            case .guardBreak(let defender):
                let def = game.fighters[defender]
                let pos = impactPosition(defender: def, z: 0.40)
                let shatter = UIColor(red: 1.0, green: 0.32, blue: 0.20, alpha: 1)
                spawnImpactCross(at: pos, color: shatter, peakScale: 1.85, duration: 10, roll: 0.78)
                spawnRipple(at: pos, color: shatter, startScale: 0.30, maxScale: 1.95, duration: 13, vertical: true, hdrBoost: 2.2)
                spawnLightning(at: pos, color: UIColor(red: 1.0, green: 0.72, blue: 0.35, alpha: 1), height: 1.5, roll: -0.45, duration: 9)
                emitSparks(at: pos, color: shatter, count: 32, speed: 6.8, size: 0.10, spread: 170)
                triggerAccentLight(at: pos, color: shatter, intensity: 660, ticks: 7)

            case .throwHit(let attacker, _, _):
                let def = game.fighters[1 - attacker]
                let floorPos = SCNVector3(Float(def.x) / 1000, 0.06, 0.22)
                let dust = UIColor(red: 0.92, green: 0.78, blue: 0.56, alpha: 0.65)
                spawnRipple(at: floorPos, color: UIColor(red: 1.0, green: 0.76, blue: 0.38, alpha: 1),
                            startScale: 0.38, maxScale: 2.25, duration: 15, vertical: false, hdrBoost: 1.8)
                emitWisps(at: floorPos, color: dust, count: 16, size: 0.40, speed: 2.4, spread: 115, direction: SCNVector3(0, 1, 0))
                emitSparks(at: floorPos, color: UIColor(red: 1.0, green: 0.85, blue: 0.50, alpha: 1),
                           count: 18, speed: 4.8, size: 0.085, spread: 120, direction: SCNVector3(0, 1, 0))

            case .shogunShadowForm(let fighter), .shogunCataclysm(let fighter):
                let f = game.fighters[fighter]
                let cataclysm = game.shogunState(fighter)?.isCataclysm == true
                let color = cataclysm ? UIColor(red: 1.0, green: 0.16, blue: 0.28, alpha: 1) : UIColor(red: 0.68, green: 0.26, blue: 1.0, alpha: 1)
                let fx = Float(f.x) / 1000
                let floorPos = SCNVector3(fx, 0.06, 0.16)
                spawnRipple(at: floorPos, color: color, texture: DuelProceduralVFXAssets.shogunSeal,
                            startScale: 0.55, maxScale: cataclysm ? 3.2 : 2.4, duration: 22, vertical: false, hdrBoost: 2.4, spinSpeed: 0.15)
                spawnLightning(at: SCNVector3(fx - 0.22, 1.15, 0.28), color: color, height: 2.2, roll: 0.12, duration: 12)
                spawnLightning(at: SCNVector3(fx + 0.22, 1.15, 0.28), color: color, height: 2.0, roll: -0.16, duration: 11)
                emitWisps(at: SCNVector3(fx, 0.65, 0.18), color: color.withAlphaComponent(0.45), count: 20, size: 0.38, speed: 2.8, life: 0.48)
                emitSparks(at: SCNVector3(fx, 0.90, 0.22), color: color, count: 32, speed: 6.2, spread: 140)
                triggerAccentLight(at: SCNVector3(fx, 1.15, 0.25), color: color, intensity: 760, ticks: 10)

            case .shogunCataclysmStrike(let attacker, _):
                let def = game.fighters[1 - attacker]
                let pos = SCNVector3(Float(def.x) / 1000, 1.18, 0.42)
                let red = UIColor(red: 1.0, green: 0.16, blue: 0.26, alpha: 1)
                // Giant X-cleave + anamorphic flare + crimson lightning!
                spawnCrescent(at: pos, color: red, facing: 1, basePitch: -0.65, sweepPitch: 1.25, startScale: 1.45, endScale: 2.35, duration: 15, hdrBoost: 2.7)
                spawnCrescent(at: pos, color: UIColor(red: 0.85, green: 0.20, blue: 1.0, alpha: 1), facing: -1, basePitch: -0.65, sweepPitch: 1.25, startScale: 1.40, endScale: 2.25, duration: 15, hdrBoost: 2.5)
                spawnImpactCross(at: pos, color: UIColor(red: 1.0, green: 0.86, blue: 0.62, alpha: 1), peakScale: 2.55, duration: 12)
                spawnLightning(at: pos, color: red, height: 2.1, roll: 0.35, duration: 12)
                emitSparks(at: pos, color: red, count: 44, speed: 8.0, size: 0.11, spread: 180)
                triggerAccentLight(at: pos, color: red, intensity: 820, ticks: 10)

            case .shogunCompanionHit(let owner, _):
                let def = game.fighters[1 - owner]
                let pos = SCNVector3(Float(def.x) / 1000, 1.12, 0.34)
                let violet = UIColor(red: 0.72, green: 0.28, blue: 1.0, alpha: 1)
                spawnCrescent(at: pos, color: violet, facing: Float(game.fighters[owner].facing),
                              basePitch: -0.45, sweepPitch: 1.10, startScale: 0.95, endScale: 1.40, duration: 11, hdrBoost: 2.1)
                emitSparks(at: pos, color: violet, count: 18, speed: 5.2)

            case .inquisitorFormOfLight(let fighter):
                let f = game.fighters[fighter]
                let fx = Float(f.x) / 1000
                let gold = UIColor(red: 1.0, green: 0.88, blue: 0.34, alpha: 1)
                spawnSkyBeam(atX: fx, color: gold, width: 1.35, duration: 22)
                spawnRipple(at: SCNVector3(fx, 0.06, 0.16), color: gold, texture: DuelProceduralVFXAssets.crusaderSigil,
                            startScale: 0.60, maxScale: 2.85, duration: 22, vertical: false, hdrBoost: 2.4, spinSpeed: 0.10)
                emitSparks(at: SCNVector3(fx, 1.05, 0.22), color: gold, count: 32, speed: 5.6, spread: 130)
                triggerAccentLight(at: SCNVector3(fx, 1.25, 0.25), color: gold, intensity: 740, ticks: 10)

            case .inquisitorStigmataFlash(let attacker, _):
                let def = game.fighters[1 - attacker]
                let pos = SCNVector3(Float(def.x) / 1000, 1.40, 0.38)
                let gold = UIColor(red: 1.0, green: 0.90, blue: 0.36, alpha: 1)
                spawnImpactCross(at: pos, color: gold, peakScale: 2.25, duration: 12)
                spawnRipple(at: pos, color: gold, texture: DuelProceduralVFXAssets.crusaderSigil,
                            startScale: 0.45, maxScale: 2.15, duration: 16, vertical: true, hdrBoost: 2.4, spinSpeed: 0.18)
                emitSparks(at: pos, color: gold, count: 34, speed: 6.8, size: 0.10, spread: 180)
                triggerAccentLight(at: pos, color: gold, intensity: 720, ticks: 9)

            case .inquisitorSalvationEcho(_, let x, let damage):
                // Light's Will 2nd Sky Smite: descending volumetric cathedral god-ray lance + Crusader floor seal!
                let fx = Float(x) / 1000
                let gold = UIColor(red: 1.0, green: 0.90, blue: 0.34, alpha: 1)
                spawnSkyBeam(atX: fx, color: gold, width: damage > 0 ? 1.25 : 0.88, duration: 18)
                spawnRipple(at: SCNVector3(fx, 0.06, 0.18), color: gold, texture: DuelProceduralVFXAssets.crusaderSigil,
                            startScale: 0.55, maxScale: 2.35, duration: 18, vertical: false, hdrBoost: 2.3, spinSpeed: 0.14)
                if damage > 0 {
                    spawnImpactCross(at: SCNVector3(fx, 1.42, 0.40), color: gold, peakScale: 1.95, duration: 11)
                    emitSparks(at: SCNVector3(fx, 1.15, 0.30), color: gold, count: 30, speed: 6.4, spread: 145)
                    triggerAccentLight(at: SCNVector3(fx, 1.35, 0.30), color: gold, intensity: 700, ticks: 8)
                }

            case .nonnaFlameForm(let fighter):
                let f = game.fighters[fighter]
                let fx = Float(f.x) / 1000
                let flame = UIColor(red: 1.0, green: 0.44, blue: 0.08, alpha: 1)
                spawnRipple(at: SCNVector3(fx, 0.06, 0.16), color: flame, startScale: 0.50, maxScale: 2.85,
                            duration: 20, vertical: false, hdrBoost: 2.4)
                emitWisps(at: SCNVector3(fx, 0.65, 0.20), color: UIColor(red: 1.0, green: 0.36, blue: 0.06, alpha: 0.48),
                          count: 24, size: 0.42, speed: 3.0, life: 0.48, spread: 110)
                emitSparks(at: SCNVector3(fx, 0.95, 0.24), color: UIColor(red: 1.0, green: 0.78, blue: 0.25, alpha: 1),
                           count: 40, speed: 6.6, size: 0.095, spread: 145)
                triggerAccentLight(at: SCNVector3(fx, 1.15, 0.26), color: flame, intensity: 740, ticks: 10)

            case .nonnaWolfHit(let owner, _), .nonnaOwlHit(let owner, _, _):
                let def = game.fighters[1 - owner]
                let pos = SCNVector3(Float(def.x) / 1000, 1.12, 0.34)
                let flame = UIColor(red: 1.0, green: 0.50, blue: 0.12, alpha: 1)
                spawnImpactCross(at: pos, color: flame, peakScale: 1.35, duration: 8)
                emitWisps(at: pos, color: flame.withAlphaComponent(0.42), count: 10, size: 0.30, speed: 2.2)
                emitSparks(at: pos, color: UIColor(red: 1.0, green: 0.80, blue: 0.26, alpha: 1), count: 22, speed: 5.8)

            case .nonnaTrueShapeExecute(let attacker, _):
                let def = game.fighters[1 - attacker]
                let pos = SCNVector3(Float(def.x) / 1000, 1.18, 0.42)
                let flame = UIColor(red: 1.0, green: 0.38, blue: 0.06, alpha: 1)
                spawnCrescent(at: pos, color: flame, facing: Float(game.fighters[attacker].facing),
                              basePitch: -0.90, sweepPitch: 1.95, startScale: 1.50, endScale: 2.40, duration: 16, hdrBoost: 2.7)
                spawnImpactCross(at: pos, color: UIColor(red: 1.0, green: 0.86, blue: 0.34, alpha: 1), peakScale: 2.45, duration: 12)
                emitWisps(at: pos, color: flame.withAlphaComponent(0.50), count: 22, size: 0.44, speed: 3.2)
                emitSparks(at: pos, color: UIColor(red: 1.0, green: 0.78, blue: 0.24, alpha: 1), count: 44, speed: 7.8, spread: 180)
                triggerAccentLight(at: pos, color: flame, intensity: 800, ticks: 10)

            case .midnightShadowShift(let fighter):
                let f = game.fighters[fighter]
                let pos = SCNVector3(Float(f.x) / 1000, 1.05, 0.24)
                emitWisps(at: pos, color: UIColor(red: 0.52, green: 0.20, blue: 0.96, alpha: 0.42),
                          count: 14, size: 0.34, speed: 1.6, life: 0.38, spread: 155)
                emitSparks(at: pos, color: UIColor(red: 0.72, green: 0.56, blue: 1.0, alpha: 0.95),
                           count: 12, speed: 3.4, size: 0.07, spread: 160)

            case .midnightBlinkCounter(let attacker, _):
                // Electric cyan-violet horizontal dimensional rift slash + rising emerald heal motes!
                let atk = game.fighters[attacker]
                let def = game.fighters[1 - attacker]
                let hitPos = SCNVector3(Float(def.x) / 1000, 1.18, 0.40)
                let healPos = SCNVector3(Float(atk.x) / 1000, 1.00, 0.28)
                let cyan = UIColor(red: 0.34, green: 0.90, blue: 1.0, alpha: 1)
                spawnCrescent(at: hitPos, color: cyan, facing: Float(atk.facing),
                              basePitch: -0.15, sweepPitch: 0.85, startScale: 1.35, endScale: 2.05, duration: 13, hdrBoost: 2.5)
                spawnImpactCross(at: hitPos, color: cyan, peakScale: 2.05, duration: 10, roll: 0.0)
                spawnLightning(at: hitPos, color: UIColor(red: 0.62, green: 0.88, blue: 1.0, alpha: 1), height: 1.65, roll: .pi / 2 - 0.15, duration: 9)
                emitSparks(at: hitPos, color: cyan, count: 30, speed: 6.8, spread: 150)
                emitSparks(at: healPos, color: UIColor(red: 0.34, green: 1.0, blue: 0.78, alpha: 1),
                           count: 20, speed: 2.6, size: 0.075, spread: 60, direction: SCNVector3(0, 1, 0))
                triggerAccentLight(at: hitPos, color: cyan, intensity: 680, ticks: 8)

            case .midnightRemovalStrike(let attacker, _):
                // Iconic SF4 Arena GIANT X-SHAPED DIMENSIONAL CROSS-SLASH (zero pink plastic donuts!)
                let def = game.fighters[1 - attacker]
                let pos = SCNVector3(Float(def.x) / 1000, 1.20, 0.42)
                let violet = UIColor(red: 0.86, green: 0.22, blue: 1.0, alpha: 1)
                let magenta = UIColor(red: 1.0, green: 0.28, blue: 0.76, alpha: 1)
                // Twin razor X-cross crescent slashes
                spawnCrescent(at: pos, color: violet, facing: 1, basePitch: -0.82, sweepPitch: 1.60,
                              startScale: 1.45, endScale: 2.30, duration: 15, hdrBoost: 2.75)
                spawnCrescent(at: pos, color: magenta, facing: -1, basePitch: -0.82, sweepPitch: 1.60,
                              startScale: 1.40, endScale: 2.25, duration: 15, hdrBoost: 2.65)
                // Blinding center anamorphic cross-flare + crackling dimensional lightning!
                spawnImpactCross(at: pos, color: UIColor(red: 0.96, green: 0.72, blue: 1.0, alpha: 1),
                                 peakScale: 2.50, duration: 12, roll: 0.0)
                spawnLightning(at: pos, color: violet, height: 1.95, roll: 0.78, duration: 10)
                spawnLightning(at: pos, color: magenta, height: 1.85, roll: -0.78, duration: 10)
                spawnRipple(at: SCNVector3(pos.x, 0.06, 0.16), color: violet,
                            startScale: 0.45, maxScale: 2.40, duration: 16, vertical: false, hdrBoost: 2.1)
                emitSparks(at: pos, color: UIColor(red: 0.94, green: 0.56, blue: 1.0, alpha: 1), count: 40, speed: 7.6, size: 0.105, spread: 180)
                triggerAccentLight(at: pos, color: violet, intensity: 740, ticks: 9)

            default:
                break
            }
        }

        // 3. Advance all shader-driven effects smoothly at 60 Hz!
        for idx in crescents.indices.reversed() {
            crescents[idx].age += 1
            let c = crescents[idx]
            if c.age >= c.duration {
                c.node.removeFromParentNode()
                crescents.remove(at: idx)
            } else {
                let t = Float(c.age) / Float(c.duration)
                c.material.setValue(NSNumber(value: t), forKey: "vfxProgress")
                c.node.eulerAngles.z = (c.basePitch + c.sweepPitch * t) * c.facing
                let sc = c.startScale + (c.endScale - c.startScale) * (1 - pow(1 - t, 2))
                c.node.scale = SCNVector3(sc, sc, 1)
            }
        }
        for idx in ripples.indices.reversed() {
            ripples[idx].age += 1
            let r = ripples[idx]
            if r.age >= r.duration {
                r.node.removeFromParentNode()
                ripples.remove(at: idx)
            } else {
                let t = Float(r.age) / Float(r.duration)
                let eased = 1 - pow(1 - t, 2.4)
                let sc = r.startScale + (r.maxScale - r.startScale) * eased
                r.node.scale = SCNVector3(sc, sc, 1)
                if r.spinSpeed != 0 {
                    if r.vertical {
                        r.node.eulerAngles.z += r.spinSpeed
                    } else {
                        r.node.eulerAngles.y += r.spinSpeed
                    }
                }
                r.material.setValue(NSNumber(value: t), forKey: "vfxProgress")
            }
        }
        for idx in impactFlashes.indices.reversed() {
            impactFlashes[idx].age += 1
            let f = impactFlashes[idx]
            if f.age >= f.duration {
                f.node.removeFromParentNode()
                impactFlashes.remove(at: idx)
            } else {
                let t = Float(f.age) / Float(f.duration)
                let punch = t < 0.25 ? (0.35 + (t / 0.25) * 0.65) : (1.0 + (t - 0.25) * 0.35)
                let sc = f.peakScale * punch
                f.node.scale = SCNVector3(sc, sc, 1)
                let alpha = pow(max(0, 1 - t), 1.5)
                f.material.setValue(NSValue(scnVector4: SCNVector4(f.tintRGB.x, f.tintRGB.y, f.tintRGB.z, alpha)), forKey: "vfxTint")
            }
        }
        for idx in lightnings.indices.reversed() {
            lightnings[idx].age += 1
            let l = lightnings[idx]
            if l.age >= l.duration {
                l.node.removeFromParentNode()
                lightnings.remove(at: idx)
            } else {
                let t = Float(l.age) / Float(l.duration)
                let flicker: Float = (l.age % 2 == 0) ? 1.0 : 0.55
                let alpha = max(0, 1 - t) * flicker
                l.material.setValue(NSValue(scnVector4: SCNVector4(l.tintRGB.x, l.tintRGB.y, l.tintRGB.z, alpha)), forKey: "vfxTint")
            }
        }
        for idx in skyBeams.indices.reversed() {
            skyBeams[idx].age += 1
            let b = skyBeams[idx]
            if b.age >= b.duration {
                b.node.removeFromParentNode()
                skyBeams.remove(at: idx)
            } else {
                let t = Float(b.age) / Float(b.duration)
                let sx = t < 0.20 ? (0.45 + 0.75 * (t / 0.20)) : (1.20 * (1.0 - (t - 0.20) * 0.65))
                b.node.scale = SCNVector3(max(0.15, sx), 1, max(0.15, sx))
                let alpha = max(0, 1 - t * t)
                for mat in b.materials {
                    mat.setValue(NSNumber(value: alpha), forKey: "vfxOpacity")
                }
            }
        }
        if flashTicks > 0 {
            flashTicks -= 1
            if flashTicks == 0 {
                flashLightNode.light?.intensity = 0
            } else {
                flashLightNode.light?.intensity = flashPeakIntensity * CGFloat(flashTicks) / 9.0
            }
        }
    }

    /// Update persistent hero form auras & rotating Light's Will ground Crusader sigil during `drawState()`.
    func updateAuras(_ game: DuelGame) {
        for i in 0..<min(2, game.fighters.count) {
            if let marker = salvationEchoMarkers[i] {
                if let inq = game.inquisitorState(i), inq.salvationEchoTicks > 0 {
                    let progress = 1.0 - Float(inq.salvationEchoTicks) / Float(max(1, DuelInquisitorState.salvationEchoDelayTicks))
                    let pulse: Float = 0.78 + 0.34 * progress
                    marker.node.isHidden = false
                    marker.node.position = SCNVector3(Float(inq.salvationEchoX) / 1000, 0.05, 0.06)
                    marker.node.scale = SCNVector3(pulse, pulse, 1)
                    marker.node.eulerAngles = SCNVector3(-Float.pi / 2, Float(game.frame) * 0.08, 0)
                    let alpha: Float = 0.45 + 0.55 * progress
                    marker.material.setValue(NSValue(scnVector4: SCNVector4(1.0, 0.86, 0.28, alpha)), forKey: "vfxTint")
                } else {
                    marker.node.isHidden = true
                }
            }
            guard let aura = fighterAuras[i] else { continue }
            let f = game.fighters[i]
            let pos = SCNVector3(Float(f.x) / 1000, Float(f.y) / 1000 + 0.92, 0)
            let kind: AuraEmitter.AuraKind
            if let shogun = game.shogunState(i) {
                if shogun.isCataclysm { kind = .shogunCataclysm }
                else if shogun.heavyChargeTicks > 0 { kind = .shogunCharge }
                else if shogun.isInShadow { kind = .shogunShadow }
                else { kind = .none }
            } else if let inq = game.inquisitorState(i), inq.isInFormOfLight {
                kind = .inquisitorLight
            } else if let nonna = game.nonnaState(i) {
                if nonna.isInFlameForm { kind = .nonnaFlame }
                else if nonna.empoweredStrikeReady { kind = .nonnaEmber }
                else { kind = .none }
            } else if let mid = game.midnightState(i) {
                if mid.isPhasedOut { kind = .midnightShift }
                else if mid.isInBlinkStance { kind = .midnightBlink }
                else if mid.isInShadowForm { kind = .midnightShadow }
                else { kind = .none }
            } else {
                kind = .none
            }
            aura.update(kind: kind, position: pos)
        }
    }

    /// Build an ornate rotating translucent golden Crusader Stigmata sigil hovering above branded foes.
    static func makeStigmataSigilNode() -> SCNNode {
        DuelProceduralVFXAssets.prepare()
        let plane = SCNPlane(width: 0.72, height: 0.72)
        plane.materials = [makeHDRGlowMaterial(
            texture: DuelProceduralVFXAssets.crusaderSigil,
            color: UIColor(red: 1.0, green: 0.90, blue: 0.34, alpha: 0.96),
            hdrBoost: 2.25
        )]
        let node = SCNNode(geometry: plane)
        node.castsShadow = false
        node.renderingOrder = 18
        return node
    }

    /// Build a sleek camera-readable translucent energy parry ward (replaces the old cyan plastic torus).
    /// Mounted in `DuelActor` local space (`+Z` forward, `+X` camera side) using a 3/4-angled crescent arc + soft ward halo.
    static func makeGuardWardNode() -> SCNNode {
        DuelProceduralVFXAssets.prepare()
        let container = SCNNode()
        // Outer crescent ward arc clearly visible from the side-view camera
        let arcPlane = SCNPlane(width: 0.86, height: 1.08)
        arcPlane.materials = [makeHDRGlowMaterial(
            texture: DuelProceduralVFXAssets.slashCrescent,
            color: UIColor(red: 0.45, green: 0.90, blue: 1.0, alpha: 0.85),
            hdrBoost: 1.95
        )]
        let arcNode = SCNNode(geometry: arcPlane)
        arcNode.eulerAngles = SCNVector3(0, Float.pi / 2, -0.18)
        arcNode.castsShadow = false
        arcNode.renderingOrder = 16
        container.addChildNode(arcNode)

        // Subtle tilted ripple halo giving 3D depth to the parry dome
        let haloPlane = SCNPlane(width: 0.82, height: 0.82)
        haloPlane.materials = [makeHDRGlowMaterial(
            texture: DuelProceduralVFXAssets.shockRipple,
            color: UIColor(red: 0.50, green: 0.92, blue: 1.0, alpha: 0.65),
            hdrBoost: 1.75
        )]
        let haloNode = SCNNode(geometry: haloPlane)
        haloNode.eulerAngles = SCNVector3(0, Float.pi * 0.28, 0)
        haloNode.castsShadow = false
        haloNode.renderingOrder = 15
        container.addChildNode(haloNode)
        return container
    }

    /// Build a volumetric shader-driven golden Salvation Light Pillar + ornate floor seal for Grand Inquisitor.
    static func makeSalvationPillarNode() -> SCNNode {
        DuelProceduralVFXAssets.prepare()
        let container = SCNNode()
        let gold = SCNVector4(1.0, 0.86, 0.28, 1.0)
        for angle in [Float(0), Float.pi * 0.33, -Float.pi * 0.33] {
            let plane = SCNPlane(width: 0.92, height: 3.45)
            let mat = SCNMaterial()
            mat.diffuse.contents = DuelProceduralVFXAssets.energyBeam
            mat.lightingModel = .constant
            mat.isDoubleSided = true
            mat.transparencyMode = .aOne
            mat.blendMode = .add
            mat.writesToDepthBuffer = false
            mat.shaderModifiers = [.fragment: DuelVFXShaders.godRayBeamFragment]
            mat.setValue(NSValue(scnVector4: gold), forKey: "vfxTint")
            mat.setValue(NSNumber(value: Float(2.35)), forKey: "vfxHdrBoost")
            mat.setValue(NSNumber(value: Float(1.0)), forKey: "vfxOpacity")
            plane.materials = [mat]
            let n = SCNNode(geometry: plane)
            n.eulerAngles = SCNVector3(0, angle, 0)
            n.castsShadow = false
            n.renderingOrder = 16
            container.addChildNode(n)
        }
        // Ornate floor Crusader sigil sliding with the pillar
        let sigilPlane = SCNPlane(width: 1.25, height: 1.25)
        sigilPlane.materials = [makeHDRGlowMaterial(
            texture: DuelProceduralVFXAssets.crusaderSigil,
            color: UIColor(red: 1.0, green: 0.88, blue: 0.32, alpha: 0.95),
            hdrBoost: 2.2
        )]
        let seal = SCNNode(geometry: sigilPlane)
        seal.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        seal.position = SCNVector3(0, -1.28, 0)
        seal.castsShadow = false
        seal.renderingOrder = 15
        container.addChildNode(seal)

        // Rising crisp golden dust motes
        let motes = SCNParticleSystem()
        motes.particleImage = DuelProceduralVFXAssets.sparkNeedle
        motes.particleColor = UIColor(red: 1.0, green: 0.94, blue: 0.56, alpha: 0.95)
        motes.birthRate = 34
        motes.particleLifeSpan = 0.52
        motes.particleSize = 0.08
        motes.particleVelocity = 2.6
        motes.spreadingAngle = 18
        motes.stretchFactor = 0.04
        motes.emittingDirection = SCNVector3(0, 1, 0)
        motes.blendMode = .additive
        motes.isLightingEnabled = false
        container.addParticleSystem(motes)
        return container
    }

    /// Build a fast spinning violet-steel Shadow Kunai with razor plasma slipstream for Midnight (Sun Deng).
    static func makeShadowKunaiNode() -> SCNNode {
        DuelProceduralVFXAssets.prepare()
        func kunaiPart(_ geom: SCNGeometry, diffuse: UIColor, emission: UIColor, additive: Bool = false) -> SCNNode {
            let m = SCNMaterial()
            m.diffuse.contents = diffuse
            m.emission.contents = emission
            m.lightingModel = additive ? .constant : .physicallyBased
            m.metalness.contents = 0.90
            m.roughness.contents = 0.18
            if additive { m.blendMode = .add; m.writesToDepthBuffer = false }
            geom.materials = [m]
            let n = SCNNode(geometry: geom)
            n.castsShadow = false
            return n
        }
        let container = SCNNode()
        let blade = kunaiPart(SCNCone(topRadius: 0.004, bottomRadius: 0.048, height: 0.34),
                              diffuse: UIColor(red: 0.84, green: 0.88, blue: 1.0, alpha: 1),
                              emission: UIColor(red: 0.64, green: 0.32, blue: 1.0, alpha: 0.95))
        blade.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
        blade.position = SCNVector3(0.14, 0, 0)
        container.addChildNode(blade)

        let hilt = kunaiPart(SCNCylinder(radius: 0.018, height: 0.14),
                             diffuse: UIColor(red: 0.10, green: 0.09, blue: 0.16, alpha: 1),
                             emission: UIColor(red: 0.25, green: 0.10, blue: 0.48, alpha: 0.45))
        hilt.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
        hilt.position = SCNVector3(-0.08, 0, 0)
        container.addChildNode(hilt)

        // Glowing razor plasma wake plane trailing behind the kunai
        let wakePlane = SCNPlane(width: 0.78, height: 0.26)
        wakePlane.materials = [makeHDRGlowMaterial(
            texture: DuelProceduralVFXAssets.impactCross,
            color: UIColor(red: 0.78, green: 0.36, blue: 1.0, alpha: 0.95),
            hdrBoost: 2.3
        )]
        let wake = SCNNode(geometry: wakePlane)
        wake.position = SCNVector3(-0.18, 0, 0)
        wake.castsShadow = false
        container.addChildNode(wake)

        let trail = SCNParticleSystem()
        trail.particleImage = DuelProceduralVFXAssets.sparkNeedle
        trail.particleColor = UIColor(red: 0.78, green: 0.44, blue: 1.0, alpha: 1)
        trail.birthRate = 55
        trail.particleLifeSpan = 0.20
        trail.particleSize = 0.075
        trail.particleVelocity = 2.4
        trail.stretchFactor = 0.06
        trail.spreadingAngle = 14
        trail.emittingDirection = SCNVector3(-1, 0, 0)
        trail.blendMode = .additive
        trail.isLightingEnabled = false
        container.addParticleSystem(trail)
        return container
    }
}
