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
    static var slashStreak: UIImage { cached("slashStreak") { makeSlashStreak() } }
    static var impactCross: UIImage { cached("impactCross") { makeImpactCross() } }
    static var shockRipple: UIImage { cached("shockRipple") { makeShockRipple() } }
    static var crusaderSigil: UIImage { cached("crusaderSigil") { makeCrusaderSigil() } }
    static var shogunSeal: UIImage { cached("shogunSeal") { makeShogunSeal() } }
    static var sparkNeedle: UIImage { cached("sparkNeedle") { makeSparkNeedle() } }
    static var smokeWisp: UIImage { cached("smokeWisp") { makeSmokeWisp() } }
    static var lightningArc: UIImage { cached("lightningArc") { makeLightningArc() } }
    static var energyBeam: UIImage { cached("energyBeam") { makeEnergyBeam() } }
    static var dojoStone: UIImage { cached("dojoStone") { makeDojoStone() } }
    static var weatheredStone: UIImage { cached("weatheredStone") { makeWeatheredStone() } }
    static var foliageCard: UIImage { cached("foliageCard") { makeFoliageCard() } }
    static var sanctuaryBackdrop: UIImage { cached("sanctuaryBackdrop") { makeSanctuaryBackdrop() } }

    private static var prewarmTask: Task<Void, Never>?

    static var isPrepared: Bool { cache.count >= 15 }

    static func prepare() {
        _ = razorRibbon; _ = slashCrescent; _ = slashStreak; _ = impactCross; _ = shockRipple
        _ = crusaderSigil; _ = shogunSeal; _ = sparkNeedle; _ = smokeWisp
        _ = lightningArc; _ = energyBeam; _ = dojoStone
        _ = weatheredStone; _ = foliageCard; _ = sanctuaryBackdrop
    }

    static func startPrewarm() {
        guard cache.count < 15, prewarmTask == nil else { return }
        Task {
            await prepareAsync()
        }
    }

    /// Generates all 15 procedural CoreGraphics VFX & environment textures on a background thread once,
    /// then installs them into the MainActor cache so combat & lobby frames never stall.
    static func prepareAsync() async {
        guard cache.count < 15 else { return }
        if let existing = prewarmTask {
            await existing.value
            return
        }
        let missingKeys = [
            "razorRibbon", "slashCrescent", "slashStreak", "impactCross", "shockRipple",
            "crusaderSigil", "shogunSeal", "sparkNeedle", "smokeWisp",
            "lightningArc", "energyBeam", "dojoStone",
            "weatheredStone", "foliageCard", "sanctuaryBackdrop"
        ].filter { cache[$0] == nil }
        guard !missingKeys.isEmpty else { return }
        let task = Task {
            let built: [(String, UIImage)] = await Task.detached(priority: .utility) {
                missingKeys.compactMap { key in
                    guard let image = Self.buildOffMain(key) else { return nil }
                    return (key, image)
                }
            }.value
            for (key, image) in built where cache[key] == nil {
                cache[key] = image
            }
            prewarmTask = nil
        }
        prewarmTask = task
        await task.value
    }

    private nonisolated static func buildOffMain(_ key: String) -> UIImage? {
        switch key {
        case "razorRibbon": return makeRazorRibbon()
        case "slashCrescent": return makeSlashCrescent()
        case "slashStreak": return makeSlashStreak()
        case "impactCross": return makeImpactCross()
        case "shockRipple": return makeShockRipple()
        case "crusaderSigil": return makeCrusaderSigil()
        case "shogunSeal": return makeShogunSeal()
        case "sparkNeedle": return makeSparkNeedle()
        case "smokeWisp": return makeSmokeWisp()
        case "lightningArc": return makeLightningArc()
        case "energyBeam": return makeEnergyBeam()
        case "dojoStone": return makeDojoStone()
        case "weatheredStone": return makeWeatheredStone()
        case "foliageCard": return makeFoliageCard()
        case "sanctuaryBackdrop": return makeSanctuaryBackdrop()
        default: return nil
        }
    }

    private static func cached(_ key: String, build: () -> UIImage) -> UIImage {
        if let existing = cache[key] { return existing }
        let img = build()
        cache[key] = img
        return img
    }

    private nonisolated static func render(width: Int, height: Int, draw: (CGContext, CGSize) -> Void) -> UIImage {
        let size = CGSize(width: width, height: height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else {
            return UIImage()
        }
        // Match UIGraphicsImageRenderer top-left origin so all procedural art coordinates stay identical.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        draw(ctx, size)
        guard let cgImage = ctx.makeImage() else { return UIImage() }
        return UIImage(cgImage: cgImage)
    }

    /// Restrained SF4 steel blade motion smear: faint air-wake tapering to a thin honed edge (zero neon aura).
    private nonisolated static func makeRazorRibbon() -> UIImage {
        render(width: 256, height: 256) { ctx, size in
            let cs = CGColorSpaceCreateDeviceRGB()
            let locations: [CGFloat] = [0.0, 0.45, 0.78, 0.92, 0.96, 1.0]
            let colors: [CGColor] = [
                UIColor(white: 1, alpha: 0.0).cgColor,
                UIColor(white: 1, alpha: 0.03).cgColor,
                UIColor(white: 1, alpha: 0.16).cgColor,
                UIColor(white: 1, alpha: 0.58).cgColor,
                UIColor(white: 1, alpha: 0.78).cgColor,
                UIColor(white: 1, alpha: 0.0).cgColor,
            ]
            if let grad = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locations) {
                ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
            }
            // Fine dry-brush metallic motion lines along the outer edge only
            for i in 0..<6 {
                let y = size.height * (0.76 + CGFloat(i) * 0.035)
                let alpha = 0.06 + 0.10 * (CGFloat(i) / 6.0)
                ctx.setStrokeColor(UIColor(white: 1, alpha: alpha).cgColor)
                ctx.setLineWidth(1.0)
                ctx.move(to: CGPoint(x: size.width * 0.25, y: y))
                ctx.addLine(to: CGPoint(x: size.width, y: y))
                ctx.strokePath()
            }
        }
    }

    /// Ultra-narrow SF4 steel swing arc: crisp dry motion edge with zero outer neon glow.
    private nonisolated static func makeSlashCrescent() -> UIImage {
        render(width: 512, height: 512) { ctx, size in
            let cx = size.width * 0.5, cy = size.height * 0.5
            let outerR = size.width * 0.46
            let innerR = size.width * 0.425
            let steps = 96

            let passes: [(inset: CGFloat, alpha: CGFloat)] = [
                (0.0, 0.28),
                (1.5, 0.65),
                (3.0, 0.90),
            ]
            for pass in passes {
                let path = CGMutablePath()
                let startA: CGFloat = -.pi * 0.56
                let endA: CGFloat = .pi * 0.28
                for i in 0...steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    let a = startA + (endA - startA) * t
                    let r = outerR - pass.inset * 0.3
                    let pt = CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                for i in stride(from: steps, through: 0, by: -1) {
                    let t = CGFloat(i) / CGFloat(steps)
                    let a = startA + (endA - startA) * t
                    let belly = sin(t * .pi)
                    let thickness = (outerR - innerR) * pow(belly, 1.35) * (1.0 - pass.inset * 0.14)
                    let r = max(24, outerR - max(1.0, thickness))
                    let pt = CGPoint(x: cx + cos(a) * r, y: cy + sin(a) * r)
                    path.addLine(to: pt)
                }
                path.closeSubpath()
                ctx.addPath(path)
                ctx.setFillColor(UIColor(white: 1, alpha: pass.alpha).cgColor)
                ctx.fillPath()
            }
        }
    }

    /// Crisp narrow steel blade gleam (no bloated bloom bar).
    private nonisolated static func makeSlashStreak() -> UIImage {
        render(width: 512, height: 128) { ctx, size in
            let cy = size.height * 0.5
            let passes: [(halfH: CGFloat, alpha: CGFloat)] = [
                (9.5, 0.18),
                (4.5, 0.52),
                (1.8, 0.90),
            ]
            for pass in passes {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 16, y: cy))
                p.addQuadCurve(to: CGPoint(x: size.width - 16, y: cy), control: CGPoint(x: size.width * 0.5, y: cy - pass.halfH))
                p.addQuadCurve(to: CGPoint(x: 16, y: cy), control: CGPoint(x: size.width * 0.5, y: cy + pass.halfH))
                p.closeSubpath()
                ctx.addPath(p)
                ctx.setFillColor(UIColor(white: 1, alpha: pass.alpha).cgColor)
                ctx.fillPath()
            }
        }
    }

    /// Gritty, compact metallic weapon-clash spark burst (short asymmetric sparks, zero giant lens flare).
    private nonisolated static func makeImpactCross() -> UIImage {
        render(width: 256, height: 256) { ctx, size in
            let cx = size.width * 0.5, cy = size.height * 0.5
            let cs = CGColorSpaceCreateDeviceRGB()

            if let coreGrad = CGGradient(
                colorsSpace: cs,
                colors: [
                    UIColor(white: 1, alpha: 0.90).cgColor,
                    UIColor(white: 1, alpha: 0.30).cgColor,
                    UIColor(white: 1, alpha: 0.0).cgColor,
                ] as CFArray,
                locations: [0.0, 0.25, 1.0]
            ) {
                ctx.drawRadialGradient(coreGrad, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                       endCenter: CGPoint(x: cx, y: cy), endRadius: size.width * 0.10, options: [])
            }

            func drawShard(angle: CGFloat, length: CGFloat, halfWidth: CGFloat, alpha: CGFloat) {
                ctx.saveGState()
                ctx.translateBy(x: cx, y: cy)
                ctx.rotate(by: angle)
                let p = CGMutablePath()
                p.move(to: CGPoint(x: -length * 0.15, y: 0))
                p.addLine(to: CGPoint(x: length * 0.22, y: -halfWidth))
                p.addLine(to: CGPoint(x: length, y: 0))
                p.addLine(to: CGPoint(x: length * 0.22, y: halfWidth))
                p.closeSubpath()
                ctx.addPath(p)
                ctx.setFillColor(UIColor(white: 1, alpha: alpha).cgColor)
                ctx.fillPath()
                ctx.restoreGState()
            }

            // Asymmetric forged-steel sparks radiating from contact point
            let shards: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (0.08, 0.44, 2.4, 0.92),
                (.pi + 0.14, 0.36, 2.0, 0.80),
                (.pi * 0.42, 0.32, 1.8, 0.78),
                (-.pi * 0.38, 0.35, 1.8, 0.74),
                (.pi * 0.78, 0.26, 1.5, 0.62),
                (-.pi * 0.72, 0.28, 1.5, 0.66),
                (.pi * 0.22, 0.24, 1.2, 0.56),
                (-.pi * 0.16, 0.22, 1.2, 0.52),
            ]
            for (angle, len, w, a) in shards {
                drawShard(angle: angle, length: size.width * len, halfWidth: w, alpha: a)
            }
        }
    }

    /// Subtle thin air-pressure & kicked-up dust ring (no bright glowing neon ring).
    private nonisolated static func makeShockRipple() -> UIImage {
        render(width: 256, height: 256) { ctx, size in
            let cx = size.width * 0.5, cy = size.height * 0.5
            let cs = CGColorSpaceCreateDeviceRGB()
            let rMax = size.width * 0.48
            if let ringGrad = CGGradient(
                colorsSpace: cs,
                colors: [
                    UIColor(white: 1, alpha: 0.0).cgColor,
                    UIColor(white: 1, alpha: 0.0).cgColor,
                    UIColor(white: 1, alpha: 0.24).cgColor,
                    UIColor(white: 1, alpha: 0.46).cgColor,
                    UIColor(white: 1, alpha: 0.12).cgColor,
                    UIColor(white: 1, alpha: 0.0).cgColor,
                ] as CFArray,
                locations: [0.0, 0.76, 0.84, 0.89, 0.94, 1.0]
            ) {
                ctx.drawRadialGradient(ringGrad, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                       endCenter: CGPoint(x: cx, y: cy), endRadius: rMax, options: [])
            }
        }
    }

    /// Minimalist grounded contact ring for Salvation telegraph (replaces fantasy mandala/star sigil).
    private nonisolated static func makeCrusaderSigil() -> UIImage {
        render(width: 256, height: 256) { ctx, size in
            let cx = size.width * 0.5, cy = size.height * 0.5
            let cs = CGColorSpaceCreateDeviceRGB()
            if let soft = CGGradient(
                colorsSpace: cs,
                colors: [
                    UIColor(white: 1, alpha: 0.14).cgColor,
                    UIColor(white: 1, alpha: 0.04).cgColor,
                    UIColor(white: 1, alpha: 0.0).cgColor,
                ] as CFArray,
                locations: [0.0, 0.55, 1.0]
            ) {
                ctx.drawRadialGradient(soft, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                       endCenter: CGPoint(x: cx, y: cy), endRadius: size.width * 0.40, options: [])
            }
            // Single clean thin ground boundary ring — zero fantasy stars, squares, or magic runes
            ctx.setStrokeColor(UIColor(white: 1, alpha: 0.58).cgColor)
            ctx.setLineWidth(2.0)
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: size.width * 0.42, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.strokePath()
        }
    }

    /// Grounded ink-mist dispersion ring for Shadow Form activation (replaces spinning neon floor seal).
    private nonisolated static func makeShogunSeal() -> UIImage {
        render(width: 256, height: 256) { ctx, size in
            let cx = size.width * 0.5, cy = size.height * 0.5
            // Asymmetric brushed ink wave segments — minimal, gritty, zero glowing vortex geometry
            let arcs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (0.10, 1.35, 3.0, 0.42),
                (1.85, 3.05, 2.4, 0.36),
                (3.60, 5.10, 2.8, 0.40),
            ]
            for (s, e, lw, a) in arcs {
                ctx.setStrokeColor(UIColor(white: 1, alpha: a).cgColor)
                ctx.setLineWidth(lw)
                ctx.setLineCap(.round)
                ctx.addArc(center: CGPoint(x: cx, y: cy), radius: size.width * 0.40, startAngle: s, endAngle: e, clockwise: false)
                ctx.strokePath()
            }
        }
    }

    /// Fine forged-steel spark needle (crisp, zero heavy bloom shadow).
    private nonisolated static func makeSparkNeedle() -> UIImage {
        render(width: 32, height: 128) { ctx, size in
            let cx = size.width * 0.5
            let p = CGMutablePath()
            p.move(to: CGPoint(x: cx, y: 6))
            p.addQuadCurve(to: CGPoint(x: cx + 3.5, y: size.height * 0.42), control: CGPoint(x: cx + 3.2, y: size.height * 0.18))
            p.addQuadCurve(to: CGPoint(x: cx, y: size.height - 6), control: CGPoint(x: cx + 1.5, y: size.height * 0.78))
            p.addQuadCurve(to: CGPoint(x: cx - 3.5, y: size.height * 0.42), control: CGPoint(x: cx - 1.5, y: size.height * 0.78))
            p.addQuadCurve(to: CGPoint(x: cx, y: 6), control: CGPoint(x: cx - 3.2, y: size.height * 0.18))
            p.closeSubpath()
            ctx.addPath(p)
            ctx.setFillColor(UIColor(white: 1, alpha: 0.92).cgColor)
            ctx.fillPath()
        }
    }

    /// Soft organic multi-lobe turbulent smoke & ink-flame wisp (replaces clipart twirl PNGs).
    private nonisolated static func makeSmokeWisp() -> UIImage {
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
    private nonisolated static func makeLightningArc() -> UIImage {
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
    private nonisolated static func makeEnergyBeam() -> UIImage {
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

    /// Organic ancient sunlit courtyard ground: warm packed earth, irregular broken mossy flagstones, and weathered grit.
    private nonisolated static func makeDojoStone() -> UIImage {
        render(width: 512, height: 512) { ctx, size in
            // Rich earthy warm-umber courtyard soil base
            ctx.setFillColor(UIColor(red: 0.31, green: 0.28, blue: 0.22, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            var rng: UInt64 = 0x20261123
            func nextF() -> CGFloat {
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((rng >> 33) & 0xFFFF) / 65535.0
            }
            // Broad dappled sunlit earth & olive moss patches (breaks up tiling completely!)
            for _ in 0..<75 {
                let cx = nextF() * size.width, cy = nextF() * size.height
                let rx = 28 + nextF() * 88, ry = 18 + nextF() * 58
                let pick = nextF()
                let col: UIColor
                if pick < 0.36 {
                    col = UIColor(red: 0.43, green: 0.37, blue: 0.26, alpha: 0.24) // sunlit ochre dirt
                } else if pick < 0.68 {
                    col = UIColor(red: 0.24, green: 0.31, blue: 0.19, alpha: 0.26) // deep moss
                } else {
                    col = UIColor(red: 0.20, green: 0.18, blue: 0.15, alpha: 0.24) // damp shadow soil
                }
                ctx.setFillColor(col.cgColor)
                ctx.fillEllipse(in: CGRect(x: cx - rx * 0.5, y: cy - ry * 0.5, width: rx, height: ry))
            }
            // Irregular weathered broken flagstones embedded organically in packed earth
            let rows = 6, cols = 4
            let rh = size.height / CGFloat(rows), cw = size.width / CGFloat(cols)
            for r in 0..<rows {
                let offset = (r % 2 == 0) ? 0 : cw * 0.45
                for c in -1...cols {
                    if nextF() < 0.20 { continue } // natural exposed dirt/moss breaks!
                    let jx = (nextF() - 0.5) * 14, jy = (nextF() - 0.5) * 10
                    let w = cw * (0.64 + nextF() * 0.24)
                    let h = rh * (0.58 + nextF() * 0.24)
                    let rect = CGRect(x: CGFloat(c) * cw + offset + jx + 8, y: CGFloat(r) * rh + jy + 8, width: w, height: h)
                    let stonePath = CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil)
                    let v = 0.36 + nextF() * 0.10
                    ctx.setFillColor(UIColor(red: v + 0.03, green: v + 0.015, blue: v - 0.03, alpha: 0.88).cgColor)
                    ctx.addPath(stonePath); ctx.fillPath()
                    ctx.setStrokeColor(UIColor(red: 0.17, green: 0.15, blue: 0.12, alpha: 0.65).cgColor)
                    ctx.setLineWidth(2.2)
                    ctx.addPath(stonePath); ctx.strokePath()
                    // Subtle weathered crack across some flagstones
                    if nextF() > 0.55 {
                        ctx.setStrokeColor(UIColor(red: 0.16, green: 0.15, blue: 0.12, alpha: 0.50).cgColor)
                        ctx.setLineWidth(1.2)
                        ctx.move(to: CGPoint(x: rect.minX + nextF() * rect.width * 0.4, y: rect.minY + 4))
                        ctx.addLine(to: CGPoint(x: rect.midX + (nextF() - 0.5) * 16, y: rect.midY))
                        ctx.addLine(to: CGPoint(x: rect.maxX - nextF() * rect.width * 0.3, y: rect.maxY - 4))
                        ctx.strokePath()
                    }
                }
            }
            // Fine pebbles, mossy flecks & dried fallen crimson leaves scattered across the courtyard
            for _ in 0..<1800 {
                let x = nextF() * size.width, y = nextF() * size.height
                let s = 1.2 + nextF() * 3.0
                let p = nextF()
                if p > 0.965 {
                    ctx.setFillColor(UIColor(red: 0.56, green: 0.20, blue: 0.14, alpha: 0.55).cgColor)
                } else if p > 0.72 {
                    ctx.setFillColor(UIColor(red: 0.26, green: 0.34, blue: 0.20, alpha: 0.32).cgColor)
                } else if p > 0.38 {
                    ctx.setFillColor(UIColor(red: 0.58, green: 0.53, blue: 0.44, alpha: 0.20).cgColor)
                } else {
                    ctx.setFillColor(UIColor(red: 0.14, green: 0.12, blue: 0.10, alpha: 0.24).cgColor)
                }
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: s, height: s * (0.6 + nextF() * 0.6)))
            }
        }
    }

    /// Aged cracked limestone masonry with vertical weather streaks and moss stains for sanctuary ruins.
    private nonisolated static func makeWeatheredStone() -> UIImage {
        render(width: 512, height: 512) { ctx, size in
            ctx.setFillColor(UIColor(red: 0.34, green: 0.35, blue: 0.32, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            var rng: UInt64 = 0x5104E777
            func nextF() -> CGFloat {
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((rng >> 33) & 0xFFFF) / 65535.0
            }
            let rows = 8
            let rh = size.height / CGFloat(rows)
            for r in 0..<rows {
                let cols = (r % 2 == 0) ? 3 : 4
                let cw = size.width / CGFloat(cols)
                let off = (r % 2 == 0) ? 0 : cw * 0.35
                for c in -1...cols {
                    let v = 0.34 + nextF() * 0.14
                    let rect = CGRect(x: CGFloat(c) * cw + off + 2, y: CGFloat(r) * rh + 2, width: cw - 4, height: rh - 4)
                    ctx.setFillColor(UIColor(red: v + 0.02, green: v + 0.02, blue: v - 0.01, alpha: 1).cgColor)
                    ctx.fill(rect)
                    // Subtle chisel highlight on top & mortar shadow on bottom
                    ctx.setFillColor(UIColor(white: 0.85, alpha: 0.10).cgColor)
                    ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 3))
                    ctx.setStrokeColor(UIColor(red: 0.14, green: 0.15, blue: 0.13, alpha: 0.78).cgColor)
                    ctx.setLineWidth(2.4)
                    ctx.stroke(rect)
                }
            }
            // Vertical rain grime & mossy green streaks trickling down the aged limestone
            for _ in 0..<48 {
                let x = nextF() * size.width
                let w = 6 + nextF() * 22
                let h = 80 + nextF() * 340
                let y = nextF() * (size.height - h * 0.5)
                let isMoss = nextF() > 0.48
                ctx.setFillColor(
                    isMoss
                        ? UIColor(red: 0.22, green: 0.31, blue: 0.18, alpha: 0.26).cgColor
                        : UIColor(red: 0.13, green: 0.14, blue: 0.12, alpha: 0.22).cgColor
                )
                ctx.fill(CGRect(x: x, y: y, width: w, height: h))
            }
            for _ in 0..<900 {
                let x = nextF() * size.width, y = nextF() * size.height
                let s = 1.0 + nextF() * 3.0
                ctx.setFillColor(UIColor(white: nextF() > 0.5 ? 0.65 : 0.12, alpha: 0.14).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: s, height: s))
            }
        }
    }

    /// Alpha-cutout hanging crimson maple & olive ivy vine cluster for draping naturally over ruined arches (ZERO spheres!).
    private nonisolated static func makeFoliageCard() -> UIImage {
        render(width: 256, height: 256) { ctx, size in
            var rng: UInt64 = 0xF011A6E1
            func nextF() -> CGFloat {
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((rng >> 33) & 0xFFFF) / 65535.0
            }
            // Organic dark woody climbing vine stems draping downward
            ctx.setStrokeColor(UIColor(red: 0.18, green: 0.13, blue: 0.10, alpha: 0.85).cgColor)
            ctx.setLineCap(.round)
            for s in 0..<6 {
                let sx = size.width * (0.18 + CGFloat(s) * 0.13 + (nextF() - 0.5) * 0.06)
                ctx.setLineWidth(2.0 + nextF() * 1.8)
                ctx.move(to: CGPoint(x: sx, y: 12))
                ctx.addCurve(
                    to: CGPoint(x: sx + (nextF() - 0.5) * 44, y: size.height * (0.68 + nextF() * 0.26)),
                    control1: CGPoint(x: sx + (nextF() - 0.5) * 38, y: size.height * 0.32),
                    control2: CGPoint(x: sx + (nextF() - 0.5) * 42, y: size.height * 0.58)
                )
                ctx.strokePath()
            }
            // Layered individual organic autumn-crimson, deep-garnet, and olive leaves
            for _ in 0..<180 {
                let t = nextF() // vertical progress (denser near top crown, tapering into hanging trails below)
                let spread = (1.0 - t * 0.55) * size.width * 0.42
                let cx = size.width * 0.5 + (nextF() - 0.5) * 2.0 * spread
                let cy = 18 + t * (size.height - 36)
                let lw = 9 + nextF() * 16
                let lh = 5 + nextF() * 9
                let angle = (nextF() - 0.5) * .pi
                let pick = nextF()
                let col: UIColor
                if pick < 0.34 {
                    col = UIColor(red: 0.50 + nextF() * 0.14, green: 0.14 + nextF() * 0.07, blue: 0.12 + nextF() * 0.05, alpha: 0.94)
                } else if pick < 0.62 {
                    col = UIColor(red: 0.62 + nextF() * 0.12, green: 0.23 + nextF() * 0.09, blue: 0.13 + nextF() * 0.05, alpha: 0.92)
                } else if pick < 0.84 {
                    col = UIColor(red: 0.24 + nextF() * 0.09, green: 0.32 + nextF() * 0.10, blue: 0.18 + nextF() * 0.06, alpha: 0.94)
                } else {
                    col = UIColor(red: 0.34 + nextF() * 0.08, green: 0.10 + nextF() * 0.05, blue: 0.09, alpha: 0.92)
                }
                ctx.saveGState()
                ctx.translateBy(x: cx, y: cy)
                ctx.rotate(by: angle)
                ctx.setFillColor(col.cgColor)
                let leaf = CGMutablePath()
                leaf.move(to: CGPoint(x: -lw * 0.55, y: 0))
                leaf.addQuadCurve(to: CGPoint(x: lw * 0.55, y: 0), control: CGPoint(x: 0, y: -lh))
                leaf.addQuadCurve(to: CGPoint(x: -lw * 0.55, y: 0), control: CGPoint(x: 0, y: lh))
                leaf.closeSubpath()
                ctx.addPath(leaf)
                ctx.fillPath()
                ctx.restoreGState()
            }
        }
    }

    /// Atmospheric painterly misty ancient valley sky, layered mountain silhouettes, sunbeams & distant sanctuary ruins.
    private nonisolated static func makeSanctuaryBackdrop() -> UIImage {
        render(width: 1024, height: 512) { ctx, size in
            let cs = CGColorSpaceCreateDeviceRGB()
            // 1. Luminous misty overcast dawn-daylight sky gradient
            if let skyGrad = CGGradient(
                colorsSpace: cs,
                colors: [
                    UIColor(red: 0.48, green: 0.56, blue: 0.62, alpha: 1).cgColor,
                    UIColor(red: 0.62, green: 0.69, blue: 0.72, alpha: 1).cgColor,
                    UIColor(red: 0.78, green: 0.81, blue: 0.77, alpha: 1).cgColor,
                    UIColor(red: 0.64, green: 0.67, blue: 0.64, alpha: 1).cgColor,
                ] as CFArray,
                locations: [0.0, 0.34, 0.68, 1.0]
            ) {
                ctx.drawLinearGradient(skyGrad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
            }

            // 2. Soft sunlit sky glow & gentle diagonal atmospheric light shafts from upper-left
            if let sunGlow = CGGradient(
                colorsSpace: cs,
                colors: [
                    UIColor(red: 0.98, green: 0.95, blue: 0.85, alpha: 0.45).cgColor,
                    UIColor(red: 0.94, green: 0.92, blue: 0.82, alpha: 0.14).cgColor,
                    UIColor(red: 0.94, green: 0.92, blue: 0.82, alpha: 0.0).cgColor,
                ] as CFArray,
                locations: [0.0, 0.45, 1.0]
            ) {
                let c = CGPoint(x: size.width * 0.32, y: size.height * 0.24)
                ctx.drawRadialGradient(sunGlow, startCenter: c, startRadius: 10, endCenter: c, endRadius: 340, options: [])
            }

            var rng: UInt64 = 0x5A4C70A1
            func nextF() -> CGFloat {
                rng = rng &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((rng >> 33) & 0xFFFF) / 65535.0
            }

            // 3. Soft sunlit mist rays slanting through the valley
            for ray in 0..<5 {
                let rx = size.width * (0.14 + CGFloat(ray) * 0.16)
                let rw = 46 + nextF() * 58
                ctx.saveGState()
                let p = CGMutablePath()
                p.move(to: CGPoint(x: rx, y: 0))
                p.addLine(to: CGPoint(x: rx + rw, y: 0))
                p.addLine(to: CGPoint(x: rx + rw + 135, y: size.height * 0.82))
                p.addLine(to: CGPoint(x: rx + 135, y: size.height * 0.82))
                p.closeSubpath()
                ctx.setFillColor(UIColor(red: 0.96, green: 0.94, blue: 0.86, alpha: 0.085).cgColor)
                ctx.addPath(p); ctx.fillPath()
                ctx.restoreGState()
            }

            // 4. Three atmospheric depth-layered mountain ridges (organic jagged profiles, zero flat triangles!)
            func drawRidge(baseY: CGFloat, amp: CGFloat, freq: CGFloat, phase: CGFloat, color: UIColor) {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 0, y: size.height))
                let steps = 64
                for s in 0...steps {
                    let u = CGFloat(s) / CGFloat(steps)
                    let x = u * size.width
                    let h = sin(u * .pi * freq + phase) * amp
                        + sin(u * .pi * freq * 2.3 + phase * 1.7) * amp * 0.42
                        + cos(u * .pi * freq * 5.1 + phase * 0.9) * amp * 0.18
                    p.addLine(to: CGPoint(x: x, y: baseY - h))
                }
                p.addLine(to: CGPoint(x: size.width, y: size.height))
                p.closeSubpath()
                ctx.setFillColor(color.cgColor)
                ctx.addPath(p); ctx.fillPath()
            }
            drawRidge(baseY: size.height * 0.56, amp: 58, freq: 2.2, phase: 0.4,
                      color: UIColor(red: 0.55, green: 0.61, blue: 0.64, alpha: 0.85))
            drawRidge(baseY: size.height * 0.64, amp: 46, freq: 3.1, phase: 1.9,
                      color: UIColor(red: 0.44, green: 0.50, blue: 0.52, alpha: 0.92))

            // 5. Distant misty ancient cloister arches & slender cypress/pine silhouettes on the mid ridge
            let silhouette = UIColor(red: 0.36, green: 0.42, blue: 0.43, alpha: 0.82)
            ctx.setFillColor(silhouette.cgColor)
            // Left & right distant arched ruin aqueduct silhouettes framing the central misty valley
            for groupX in [size.width * 0.14, size.width * 0.72] {
                for a in 0..<3 {
                    let ax = groupX + CGFloat(a) * 52
                    let ay = size.height * 0.44
                    ctx.fill(CGRect(x: ax, y: ay, width: 12, height: 150))
                    ctx.fill(CGRect(x: ax, y: ay, width: 52, height: 14))
                    // Curved arch haunches
                    ctx.fillEllipse(in: CGRect(x: ax + 4, y: ay + 6, width: 16, height: 18))
                    ctx.fillEllipse(in: CGRect(x: ax + 32, y: ay + 6, width: 16, height: 18))
                }
            }
            // Organic misty valley pines & autumn foliage silhouettes along lower horizon
            for _ in 0..<42 {
                let tx = nextF() * size.width
                let ty = size.height * (0.58 + nextF() * 0.18)
                let th = 36 + nextF() * 68
                let tw = 16 + nextF() * 24
                let isAutumn = nextF() > 0.78
                ctx.setFillColor(
                    isAutumn
                        ? UIColor(red: 0.48, green: 0.28, blue: 0.24, alpha: 0.58).cgColor
                        : UIColor(red: 0.29, green: 0.36, blue: 0.33, alpha: 0.72).cgColor
                )
                let tree = CGMutablePath()
                tree.move(to: CGPoint(x: tx, y: ty - th))
                tree.addCurve(to: CGPoint(x: tx + tw * 0.5, y: ty),
                              control1: CGPoint(x: tx + tw * 0.22, y: ty - th * 0.6),
                              control2: CGPoint(x: tx + tw * 0.48, y: ty - th * 0.25))
                tree.addLine(to: CGPoint(x: tx - tw * 0.5, y: ty))
                tree.addCurve(to: CGPoint(x: tx, y: ty - th),
                              control1: CGPoint(x: tx - tw * 0.48, y: ty - th * 0.25),
                              control2: CGPoint(x: tx - tw * 0.22, y: ty - th * 0.6))
                tree.closeSubpath()
                ctx.addPath(tree); ctx.fillPath()
            }

            // 6. Low drifting atmospheric valley mist veil blending the distant ridge smoothly into the courtyard
            if let mistGrad = CGGradient(
                colorsSpace: cs,
                colors: [
                    UIColor(red: 0.72, green: 0.76, blue: 0.75, alpha: 0.0).cgColor,
                    UIColor(red: 0.72, green: 0.76, blue: 0.75, alpha: 0.52).cgColor,
                    UIColor(red: 0.58, green: 0.62, blue: 0.60, alpha: 0.78).cgColor,
                ] as CFArray,
                locations: [0.46, 0.76, 1.0]
            ) {
                ctx.drawLinearGradient(mistGrad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
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
    float wave = 0.90 + 0.10 * sin(uv.x * 12.0 - scn_frame.time * 14.0 + uv.y * 4.0);
    float hotCore = pow(saturate(uv.y), 5.0) * smoothstep(0.28, 0.94, uv.x);
    float alpha = saturate(edgeMask * headTail * wave * vfxTint.a);
    float3 col = mix(vfxTint.rgb, float3(0.96, 0.97, 0.98), hotCore * 0.32) * vfxHdrBoost * (0.74 + 0.28 * hotCore);
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
    float head = mix(0.14, 0.78, saturate(vfxProgress * 1.45));
    float tail = mix(0.08, 0.72, saturate((vfxProgress - 0.28) * 1.45));
    float sweep = smoothstep(tail - 0.14, tail + 0.08, ang) * (1.0 - smoothstep(head - 0.06, head + 0.06, ang));
    float fade = 1.0 - smoothstep(0.45, 1.0, vfxProgress);
    float intensity = saturate(mask * max(sweep, 0.26 * fade) * fade * vfxTint.a);
    float hot = pow(saturate(mask), 4.5);
    float3 col = mix(vfxTint.rgb, float3(0.96, 0.97, 0.98), hot * 0.22) * vfxHdrBoost;
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
    float scroll1 = 0.84 + 0.16 * sin(uv.y * 10.0 - scn_frame.time * 6.0 + uv.x * 10.0);
    float core = exp(-pow((uv.x - 0.5) * 3.8, 2.0));
    float alpha = saturate(baseMask * scroll1 * vfxTint.a * vfxOpacity);
    float3 col = mix(vfxTint.rgb, float3(0.96, 0.94, 0.86), core * 0.24) * vfxHdrBoost;
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
    float fade = pow(max(0.0, 1.0 - vfxProgress), 1.45);
    float alpha = saturate(mask * fade * vfxTint.a);
    float3 col = mix(vfxTint.rgb, float3(0.95, 0.96, 0.96), pow(saturate(mask), 4.0) * 0.18) * vfxHdrBoost;
    _output.color = float4(col * alpha, 1.0);
    """

    static let hdrGlowFragment = """
    #pragma arguments
    float4 vfxTint;
    float vfxHdrBoost;
    #pragma transparent
    #pragma body
    float mask = _surface.diffuse.a;
    float hot = pow(saturate(mask), 4.2);
    float alpha = saturate(mask * vfxTint.a);
    float3 col = mix(vfxTint.rgb, float3(0.96, 0.97, 0.98), hot * 0.22) * vfxHdrBoost;
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
    private var dustPool: [(node: SCNNode, system: SCNParticleSystem)] = []
    private var dustCursor = 0
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
    private var telegraphGlints: [Int: (node: SCNNode, material: SCNMaterial)] = [:]
    private var bladeRibbons: [[BladeRibbon]] = []
    private var hasLiveBladeSegments: [Bool] = [false, false]
    private var lastAttackKeys: [String?] = [nil, nil]
    private var lastTrailAttackKeys: [String?] = [nil, nil]
    private var previousKnockdown: [Int] = [0, 0]
    private var previousAirborne: [Bool] = [false, false]

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

    static func makeHDRGlowMaterial(texture: UIImage, color: UIColor, hdrBoost: Float = 0.96) -> SCNMaterial {
        let clamped = min(hdrBoost, 1.18)
        let mat = SCNMaterial()
        mat.diffuse.contents = texture
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.transparencyMode = .aOne
        mat.blendMode = .add
        mat.writesToDepthBuffer = false
        mat.shaderModifiers = [.fragment: DuelVFXShaders.hdrGlowFragment]
        mat.setValue(NSValue(scnVector4: rgbaVector(color)), forKey: "vfxTint")
        mat.setValue(NSNumber(value: clamped), forKey: "vfxHdrBoost")
        return mat
    }

    /// Catmull-Rom curved 3D blade motion-smear ribbon hugging live animated weapon edges.
    @MainActor
    private final class BladeRibbon {
        let node = SCNNode()
        private let material = SCNMaterial()
        private var samples: [(base: SIMD3<Float>, tip: SIMD3<Float>)] = []
        private let maxSamples = 6

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
            material.setValue(NSNumber(value: Float(0.95)), forKey: "vfxHdrBoost")
        }

        func clear() {
            samples.removeAll(keepingCapacity: true)
            node.geometry = nil
            node.isHidden = true
        }

        func push(base: SIMD3<Float>, tip: SIMD3<Float>, color: UIColor, hdrBoost: Float) {
            material.setValue(NSValue(scnVector4: DuelOriginalVFX.rgbaVector(color)), forKey: "vfxTint")
            material.setValue(NSNumber(value: min(hdrBoost, 1.12)), forKey: "vfxHdrBoost")

            // Tightly hug the honed outer edge of the blade (minimalist SF4 steel smear)
            let shiftedBase = simd_mix(base, tip, SIMD3<Float>(repeating: 0.36))
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
            let c0: Float = -0.5 * t + t2 - 0.5 * t3
            let c1: Float = 1.0 - 2.5 * t2 + 1.5 * t3
            let c2: Float = 0.5 * t + 2.0 * t2 - 1.5 * t3
            let c3: Float = -0.5 * t2 + 0.5 * t3
            let ab: SIMD3<Float> = p0 * c0 + p1 * c1
            let cd: SIMD3<Float> = p2 * c2 + p3 * c3
            return ab + cd
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

    /// Restrained atmospheric hero aura: quiet dark ink-wisps and sparse embers (no neon clouds).
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
            wispSystem.birthRate = 0
            wispSystem.particleImage = DuelProceduralVFXAssets.smokeWisp
            wispSystem.particleLifeSpan = 0.50
            wispSystem.particleLifeSpanVariation = 0.16
            wispSystem.particleSize = 0.20
            wispSystem.particleSizeVariation = 0.06
            wispSystem.particleVelocity = 0.55
            wispSystem.particleVelocityVariation = 0.22
            wispSystem.spreadingAngle = 22
            wispSystem.emittingDirection = SCNVector3(0, 1, 0)
            wispSystem.emitterShape = SCNCylinder(radius: 0.24, height: 1.15)
            wispSystem.blendMode = .alpha
            wispSystem.isLightingEnabled = false
            wispSystem.isAffectedByGravity = false
            wispSystem.loops = true

            emberSystem.birthRate = 0
            emberSystem.particleImage = DuelProceduralVFXAssets.sparkNeedle
            emberSystem.particleLifeSpan = 0.42
            emberSystem.particleLifeSpanVariation = 0.14
            emberSystem.particleSize = 0.042
            emberSystem.particleSizeVariation = 0.016
            emberSystem.particleVelocity = 0.95
            emberSystem.particleVelocityVariation = 0.35
            emberSystem.spreadingAngle = 24
            emberSystem.emittingDirection = SCNVector3(0, 1, 0)
            emberSystem.emitterShape = SCNCylinder(radius: 0.28, height: 1.25)
            emberSystem.stretchFactor = 0.03
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
                wispSystem.blendMode = .alpha
                wispSystem.particleColor = UIColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 0.60)
                wispSystem.birthRate = 18; wispSystem.particleSize = 0.30
                emberSystem.stretchFactor = 0.04
                emberSystem.particleColor = UIColor(red: 0.44, green: 0.72, blue: 0.86, alpha: 0.66)
                emberSystem.birthRate = 10; emberSystem.particleSize = 0.038
            case .shogunCataclysm:
                wispSystem.blendMode = .alpha
                wispSystem.particleColor = UIColor(red: 0.10, green: 0.03, blue: 0.04, alpha: 0.64)
                wispSystem.birthRate = 20; wispSystem.particleSize = 0.32
                emberSystem.stretchFactor = 0.045
                emberSystem.particleColor = UIColor(red: 0.86, green: 0.32, blue: 0.22, alpha: 0.72)
                emberSystem.birthRate = 12; emberSystem.particleSize = 0.042
            case .shogunCharge:
                wispSystem.blendMode = .alpha
                wispSystem.particleColor = UIColor(red: 0.18, green: 0.16, blue: 0.14, alpha: 0.20)
                wispSystem.birthRate = 6; wispSystem.particleSize = 0.16
                emberSystem.stretchFactor = 0.03
                emberSystem.particleColor = UIColor(red: 0.90, green: 0.78, blue: 0.52, alpha: 0.62)
                emberSystem.birthRate = 7; emberSystem.particleSize = 0.036
            case .inquisitorLight:
                wispSystem.blendMode = .alpha
                wispSystem.particleColor = UIColor(red: 0.92, green: 0.86, blue: 0.68, alpha: 0.14)
                wispSystem.birthRate = 8; wispSystem.particleSize = 0.18
                emberSystem.stretchFactor = 0.03
                emberSystem.particleColor = UIColor(red: 0.94, green: 0.86, blue: 0.58, alpha: 0.66)
                emberSystem.birthRate = 10; emberSystem.particleSize = 0.040
            case .nonnaFlame:
                wispSystem.blendMode = .alpha
                wispSystem.particleColor = UIColor(red: 0.14, green: 0.09, blue: 0.06, alpha: 0.52)
                wispSystem.birthRate = 16; wispSystem.particleSize = 0.26
                emberSystem.stretchFactor = 0.04
                emberSystem.particleColor = UIColor(red: 0.92, green: 0.48, blue: 0.18, alpha: 0.74)
                emberSystem.birthRate = 14; emberSystem.particleSize = 0.044
            case .nonnaEmber:
                wispSystem.blendMode = .alpha
                wispSystem.particleColor = UIColor(red: 0.16, green: 0.11, blue: 0.08, alpha: 0.26)
                wispSystem.birthRate = 6; wispSystem.particleSize = 0.16
                emberSystem.stretchFactor = 0.03
                emberSystem.particleColor = UIColor(red: 0.90, green: 0.56, blue: 0.24, alpha: 0.60)
                emberSystem.birthRate = 7; emberSystem.particleSize = 0.038
            case .midnightShift:
                wispSystem.blendMode = .alpha
                wispSystem.particleColor = UIColor(red: 0.03, green: 0.04, blue: 0.07, alpha: 0.60)
                wispSystem.birthRate = 18; wispSystem.particleSize = 0.30
                emberSystem.stretchFactor = 0.04
                emberSystem.particleColor = UIColor(red: 0.48, green: 0.74, blue: 0.86, alpha: 0.60)
                emberSystem.birthRate = 8; emberSystem.particleSize = 0.036
            case .midnightBlink:
                wispSystem.blendMode = .alpha
                wispSystem.particleColor = UIColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 0.32)
                wispSystem.birthRate = 10; wispSystem.particleSize = 0.18
                emberSystem.stretchFactor = 0.035
                emberSystem.particleColor = UIColor(red: 0.64, green: 0.82, blue: 0.92, alpha: 0.66)
                emberSystem.birthRate = 9; emberSystem.particleSize = 0.038
            case .midnightShadow:
                wispSystem.blendMode = .alpha
                wispSystem.particleColor = UIColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 0.62)
                wispSystem.birthRate = 18; wispSystem.particleSize = 0.30
                emberSystem.stretchFactor = 0.04
                emberSystem.particleColor = UIColor(red: 0.44, green: 0.72, blue: 0.86, alpha: 0.66)
                emberSystem.birthRate = 10; emberSystem.particleSize = 0.038
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
            sys.particleLifeSpan = 0.26
            sys.particleLifeSpanVariation = 0.10
            sys.particleSize = 0.08
            sys.particleSizeVariation = 0.03
            sys.particleVelocity = 5.2
            sys.particleVelocityVariation = 2.2
            sys.spreadingAngle = 115
            sys.stretchFactor = 0.07
            sys.blendMode = .additive
            sys.isLightingEnabled = false
            sys.isAffectedByGravity = true
            sys.acceleration = SCNVector3(0, -7.2, 0)
            node.addParticleSystem(sys)
            root.addChildNode(node)
            sparkPool.append((node, sys))
        }

        // Pool 2: Soft organic turbulent smoke / flame bursts
        for _ in 0..<6 {
            let node = SCNNode()
            let sys = SCNParticleSystem()
            sys.birthRate = 0
            sys.emissionDuration = 0.08
            sys.loops = false
            sys.particleImage = DuelProceduralVFXAssets.smokeWisp
            sys.particleLifeSpan = 0.42
            sys.particleLifeSpanVariation = 0.16
            sys.particleSize = 0.30
            sys.particleSizeVariation = 0.12
            sys.particleVelocity = 2.0
            sys.particleVelocityVariation = 0.9
            sys.spreadingAngle = 135
            sys.blendMode = .additive
            sys.isLightingEnabled = false
            sys.isAffectedByGravity = false
            node.addParticleSystem(sys)
            root.addChildNode(node)
            wispPool.append((node, sys))
        }

        // Pool 3: Alpha-blended sunlit courtyard dust puffs & Shadow World black ink plumes
        for _ in 0..<5 {
            let node = SCNNode()
            let sys = SCNParticleSystem()
            sys.birthRate = 0
            sys.emissionDuration = 0.08
            sys.loops = false
            sys.particleImage = DuelProceduralVFXAssets.smokeWisp
            sys.particleLifeSpan = 0.52
            sys.particleLifeSpanVariation = 0.18
            sys.particleSize = 0.36
            sys.particleSizeVariation = 0.14
            sys.particleVelocity = 1.65
            sys.particleVelocityVariation = 0.75
            sys.spreadingAngle = 115
            sys.emittingDirection = SCNVector3(0, 1, 0)
            sys.blendMode = .alpha
            sys.isLightingEnabled = false
            sys.isAffectedByGravity = true
            sys.acceleration = SCNVector3(0, -1.2, 0)
            node.addParticleSystem(sys)
            root.addChildNode(node)
            dustPool.append((node, sys))
        }

        // Tasteful localized rim accent light (NEVER bleaches the stage floor!)
        let light = SCNLight()
        light.type = .omni
        light.intensity = 0
        light.attenuationStartDistance = 0.6
        light.attenuationEndDistance = 2.8
        flashLightNode.light = light
        root.addChildNode(flashLightNode)

        for i in 0..<2 {
            let aura = AuraEmitter()
            root.addChildNode(aura.node)
            fighterAuras[i] = aura

            // Light's Will 2nd sky-smite ornate rotating floor sigil (NO torus!)
            let sigilPlane = SCNPlane(width: 1.35, height: 1.35)
            let sigilMat = Self.makeHDRGlowMaterial(
                texture: DuelProceduralVFXAssets.crusaderSigil,
                color: UIColor(red: 1.0, green: 0.86, blue: 0.30, alpha: 1),
                hdrBoost: 1.75
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

            // Shadow Fight style unblockable telegraph: a crisp crimson lens glint during startup
            let glintPlane = SCNPlane(width: 0.72, height: 0.72)
            let glintMat = Self.makeHDRGlowMaterial(
                texture: DuelProceduralVFXAssets.impactCross,
                color: UIColor(red: 1.0, green: 0.18, blue: 0.12, alpha: 1),
                hdrBoost: 1.95
            )
            glintPlane.materials = [glintMat]
            let glintNode = SCNNode(geometry: glintPlane)
            glintNode.castsShadow = false
            glintNode.renderingOrder = 30
            glintNode.isHidden = true
            let billboard = SCNBillboardConstraint()
            billboard.freeAxes = .all
            glintNode.constraints = [billboard]
            root.addChildNode(glintNode)
            telegraphGlints[i] = (glintNode, glintMat)
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
        previousKnockdown = [0, 0]
        previousAirborne = [false, false]
        for pair in bladeRibbons { for r in pair { r.clear() } }
        for aura in fighterAuras.values { aura.update(kind: .none, position: SCNVector3Zero) }
        for marker in salvationEchoMarkers.values { marker.node.isHidden = true }
        for glint in telegraphGlints.values { glint.node.isHidden = true }
    }

    func shutdown() {
        reset()
        root.removeFromParentNode()
        sparkPool.removeAll()
        wispPool.removeAll()
        dustPool.removeAll()
        bladeRibbons.removeAll()
        fighterAuras.removeAll()
        salvationEchoMarkers.removeAll()
        telegraphGlints.removeAll()
    }

    /// SF4-authentic blade ribbon palette: subtle cool tempered steel normally, muted slate/brass/ember when enhanced.
    private func heroEnergyColor(_ hero: DuelGame.Hero, enhanced: Bool = false) -> UIColor {
        if enhanced {
            switch hero {
            case .wuYong: return UIColor(red: 0.44, green: 0.72, blue: 0.84, alpha: 0.66)
            case .gale: return UIColor(red: 0.90, green: 0.78, blue: 0.46, alpha: 0.64)
            case .liu: return UIColor(red: 0.88, green: 0.44, blue: 0.18, alpha: 0.68)
            case .ember: return UIColor(red: 0.46, green: 0.74, blue: 0.84, alpha: 0.66)
            }
        }
        switch hero {
        case .wuYong: return UIColor(red: 0.78, green: 0.82, blue: 0.86, alpha: 0.44)
        case .gale: return UIColor(red: 0.86, green: 0.83, blue: 0.76, alpha: 0.44)
        case .liu: return UIColor(red: 0.84, green: 0.78, blue: 0.70, alpha: 0.44)
        case .ember: return UIColor(red: 0.76, green: 0.82, blue: 0.88, alpha: 0.46)
        }
    }

    private func emitSparks(at position: SCNVector3, color: UIColor, count: CGFloat,
                            speed: CGFloat = 5.4, size: CGFloat = 0.08,
                            spread: CGFloat = 110, direction: SCNVector3 = SCNVector3(0, 1, 0)) {
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
                           size: CGFloat = 0.30, speed: CGFloat = 1.9, life: CGFloat = 0.40,
                           spread: CGFloat = 135, direction: SCNVector3 = SCNVector3(0, 1, 0)) {
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

    /// Earthy courtyard dust puff (or dark billowing shadow ink puff during Shadow Form) on falls, landings, rolls, and dashes.
    private func emitGroundDust(atX fx: Float, isShadow: Bool, count: CGFloat = 14,
                                size: CGFloat = 0.38, speed: CGFloat = 1.65,
                                direction: SCNVector3 = SCNVector3(0, 1, 0)) {
        guard !dustPool.isEmpty else { return }
        let entry = dustPool[dustCursor]
        dustCursor = (dustCursor + 1) % dustPool.count
        entry.node.position = SCNVector3(fx, 0.08, 0.14)
        let sys = entry.system
        sys.reset()
        sys.particleColor = isShadow
            ? UIColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 0.56)
            : UIColor(red: 0.72, green: 0.67, blue: 0.58, alpha: 0.46)
        sys.particleSize = size
        sys.particleVelocity = speed
        sys.emittingDirection = direction
        sys.emissionDuration = 0.08
        sys.birthRate = count / 0.08
        sys.loops = false
    }

    /// Spawn a restrained expanding air-pressure ring (low opacity, no glowing neon mandala).
    private func spawnRipple(at position: SCNVector3, color: UIColor, texture: UIImage? = nil,
                             startScale: Float = 0.28, maxScale: Float = 1.35,
                             duration: Int = 10, vertical: Bool = true,
                             hdrBoost: Float = 0.92, spinSpeed: Float = 0) {
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
        mat.setValue(NSNumber(value: min(hdrBoost, 1.08)), forKey: "vfxHdrBoost")
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

    /// Spawn a crisp, short-lived SF4 metallic impact spark flash (never a giant glowing cross).
    private func spawnImpactCross(at position: SCNVector3, color: UIColor, peakScale: Float = 0.62,
                                  duration: Int = 6, roll: Float = 0, hdrBoost: Float = 1.05) {
        let plane = SCNPlane(width: 1.0, height: 1.0)
        let mat = Self.makeHDRGlowMaterial(texture: DuelProceduralVFXAssets.impactCross, color: color, hdrBoost: min(hdrBoost, 1.15))
        plane.materials = [mat]
        let node = SCNNode(geometry: plane)
        node.position = position
        node.eulerAngles = SCNVector3(0, 0, roll)
        node.scale = SCNVector3(0.22, 0.22, 1)
        node.castsShadow = false
        node.renderingOrder = 20
        root.addChildNode(node)
        impactFlashes.append(ImpactFlashFX(node: node, material: mat, tintRGB: Self.rgbSIMD(color),
                                           age: 0, duration: min(duration, 7), peakScale: peakScale * 0.60))
    }

    /// Spawn a narrow, crisp steel cleave streak (no thick glowing bars).
    private func spawnSlashStreak(at position: SCNVector3, color: UIColor, length: Float = 1.45,
                                  thickness: Float = 0.14, roll: Float = 0.72,
                                  duration: Int = 8, hdrBoost: Float = 1.05) {
        let plane = SCNPlane(width: CGFloat(length * 0.78), height: CGFloat(thickness * 0.54))
        let mat = Self.makeHDRGlowMaterial(texture: DuelProceduralVFXAssets.slashStreak, color: color, hdrBoost: min(hdrBoost, 1.12))
        plane.materials = [mat]
        let node = SCNNode(geometry: plane)
        node.position = position
        node.eulerAngles = SCNVector3(0, 0, roll)
        node.scale = SCNVector3(0.30, 0.30, 1)
        node.castsShadow = false
        node.renderingOrder = 20
        root.addChildNode(node)
        impactFlashes.append(ImpactFlashFX(node: node, material: mat, tintRGB: Self.rgbSIMD(color),
                                           age: 0, duration: min(duration, 9), peakScale: 0.96))
    }

    /// Spawn a narrow steel swing arc.
    private func spawnCrescent(at position: SCNVector3, color: UIColor, facing: Float,
                               basePitch: Float, sweepPitch: Float,
                               startScale: Float = 0.85, endScale: Float = 1.15,
                               duration: Int = 8, hdrBoost: Float = 0.96) {
        let plane = SCNPlane(width: 1.12, height: 1.12)
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
        mat.setValue(NSNumber(value: min(hdrBoost, 1.08)), forKey: "vfxHdrBoost")
        plane.materials = [mat]

        let node = SCNNode(geometry: plane)
        node.position = position
        node.eulerAngles = SCNVector3(0, facing > 0 ? 0 : .pi, basePitch * facing)
        node.scale = SCNVector3(startScale, startScale, 1)
        node.castsShadow = false
        node.renderingOrder = 18
        root.addChildNode(node)
        crescents.append(CrescentFX(node: node, material: mat, age: 0, duration: min(duration, 10),
                                    basePitch: basePitch, sweepPitch: sweepPitch, facing: facing,
                                    startScale: startScale, endScale: endScale))
    }

    /// Spawn a restrained narrow shadow-fissure flash (replaces arcade neon lightning).
    private func spawnLightning(at position: SCNVector3, color: UIColor, height: Float = 1.15,
                                roll: Float = 0, duration: Int = 6, hdrBoost: Float = 1.02) {
        let plane = SCNPlane(width: CGFloat(height * 0.22), height: CGFloat(height * 0.78))
        let mat = Self.makeHDRGlowMaterial(texture: DuelProceduralVFXAssets.lightningArc, color: color, hdrBoost: min(hdrBoost, 1.08))
        plane.materials = [mat]
        let node = SCNNode(geometry: plane)
        node.position = position
        node.eulerAngles = SCNVector3(0, 0, roll)
        node.castsShadow = false
        node.renderingOrder = 19
        root.addChildNode(node)
        lightnings.append(LightningFX(node: node, material: mat, tintRGB: Self.rgbSIMD(color),
                                      age: 0, duration: min(duration, 6)))
    }

    /// Spawn a narrow, subdued shaft of pale daylight for Salvation (replaces wide neon beam).
    private func spawnSkyBeam(atX fx: Float, color: UIColor, width: CGFloat = 0.56, duration: Int = 11) {
        let container = SCNNode()
        container.position = SCNVector3(fx, 1.90, 0.18)
        var mats: [SCNMaterial] = []
        let tint = Self.rgbaVector(color, alphaOverride: 0.42)
        for angle in [Float(0), Float.pi * 0.35] {
            let plane = SCNPlane(width: width * 0.52, height: 3.8)
            let mat = SCNMaterial()
            mat.diffuse.contents = DuelProceduralVFXAssets.energyBeam
            mat.lightingModel = .constant
            mat.isDoubleSided = true
            mat.transparencyMode = .aOne
            mat.blendMode = .add
            mat.writesToDepthBuffer = false
            mat.shaderModifiers = [.fragment: DuelVFXShaders.godRayBeamFragment]
            mat.setValue(NSValue(scnVector4: tint), forKey: "vfxTint")
            mat.setValue(NSNumber(value: Float(0.95)), forKey: "vfxHdrBoost")
            mat.setValue(NSNumber(value: Float(0.65)), forKey: "vfxOpacity")
            plane.materials = [mat]
            mats.append(mat)
            let n = SCNNode(geometry: plane)
            n.eulerAngles = SCNVector3(0, angle, 0)
            n.castsShadow = false
            n.renderingOrder = 17
            container.addChildNode(n)
        }
        root.addChildNode(container)
        skyBeams.append(SkyBeamFX(node: container, materials: mats, age: 0, duration: min(duration, 12)))
    }

    private func triggerAccentLight(at position: SCNVector3, color: UIColor, intensity: CGFloat = 240, ticks: Int = 4) {
        let scaled = min(intensity, 360) * 0.34
        flashLightNode.position = SCNVector3(position.x, position.y + 0.35, 1.05)
        flashLightNode.light?.color = color
        flashLightNode.light?.intensity = scaled
        flashPeakIntensity = scaled
        flashTicks = max(flashTicks, min(ticks, 5))
    }

    private func spawnMoveCrescent(fighter: DuelGame.Fighter, move: DuelGame.Move, enhanced: Bool) {
        let isKick = move == .kick || move == .kickForward || move == .kickUp || move == .kickDown || move == .kickBack || move == .wakeupKick
        let isThrowOrRoll = move == .throwForward || move == .throwBack || move.isRoll
        if isThrowOrRoll { return }
        let color = isKick
            ? UIColor(red: 0.90, green: 0.94, blue: 1.0, alpha: 0.42)
            : heroEnergyColor(fighter.hero, enhanced: enhanced)
        let facing = Float(fighter.facing)
        let yOff: Float
        let baseP: Float
        let sweepP: Float
        let scale: Float = isKick ? 0.68 : (move == .heavy || move == .skill2 ? 1.18 : 0.96)
        switch move {
        case .weaponUp, .kickUp:
            yOff = 1.40; baseP = 0.65; sweepP = -1.20
        case .weaponDown, .kickDown, .wakeupKick:
            yOff = 0.46; baseP = -0.35; sweepP = 0.55
        case .heavy, .skill2:
            yOff = 1.16; baseP = -0.80; sweepP = 1.45
        case .inquisitorLightSpin:
            yOff = 1.12; baseP = 0.0; sweepP = 2.6
        default:
            yOff = 1.12; baseP = -0.25; sweepP = 0.80
        }
        let pos = SCNVector3(Float(fighter.x) / 1000 + facing * 0.56, Float(fighter.y) / 1000 + yOff, 0.22)
        spawnCrescent(at: pos, color: color, facing: facing, basePitch: baseP, sweepPitch: sweepP,
                      startScale: scale * 0.80, endScale: scale * 1.10, duration: 10, hdrBoost: isKick ? 1.15 : 1.55)
    }

    private static func isKickOrThrow(_ move: DuelGame.Move) -> Bool {
        switch move {
        case .kick, .kickForward, .kickUp, .kickDown, .kickBack, .wakeupKick, .throwForward, .throwBack,
             .rollForward, .rollBack, .dashForward, .dashBack:
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

    private func isShadowWorldActive(_ game: DuelGame) -> Bool {
        (0..<game.fighters.count).contains {
            game.shogunState($0)?.isInShadow == true ||
            game.shogunState($0)?.isCataclysm == true ||
            game.midnightState($0)?.isInShadowForm == true
        }
    }

    /// Sample live world-space weapon `(base, tip)` segments from rigged actors every frame
    /// to paint sleek SF4-style tapered steel/shadow blade ribbons hugging the moving weapon.
    func sampleBladeTrails(game: DuelGame, bladeSegments: [[(base: SIMD3<Float>, tip: SIMD3<Float>)]]) {
        guard game.fighters.count == 2 else { return }
        for i in 0..<2 {
            let segs = bladeSegments.indices.contains(i) ? bladeSegments[i] : []
            hasLiveBladeSegments[i] = !segs.isEmpty
            guard bladeRibbons.indices.contains(i) else { continue }
            let f = game.fighters[i]
            var activeBladeSwing = false
            let enhanced = isHeroEnhanced(game, index: i)
            var color = heroEnergyColor(f.hero, enhanced: enhanced)
            var hdrBoost: Float = enhanced ? 1.68 : 1.28
            if let attack = f.attack, !Self.isKickOrThrow(attack.move) {
                let trailKey = "\(attack.move.rawValue):\(game.frame - attack.age)"
                if lastTrailAttackKeys[i] != trailKey {
                    lastTrailAttackKeys[i] = trailKey
                    for ribbon in bladeRibbons[i] { ribbon.clear() }
                }
                let data = DuelGame.data(attack.move, hero: f.hero, chargeTicks: attack.chargeTicks)
                let startWin = max(0, data.startup - 1)
                let endWin = data.startup + data.active + 4
                if attack.age >= startWin && attack.age <= endWin {
                    activeBladeSwing = true
                    let signature = attack.move == .shogunFierceReprisal ||
                        attack.move == .shogunDespotism || attack.move == .inquisitorLightSpin ||
                        attack.move == .inquisitorLightUp || attack.move == .inquisitorLightForward ||
                        attack.move == .inquisitorLightDown || attack.move == .midnightRemoval || attack.move == .skill2
                    if game.shogunState(i)?.isCataclysm == true {
                        color = UIColor(red: 1.0, green: 0.24, blue: 0.28, alpha: 0.96)
                        hdrBoost = 1.85
                    } else if game.midnightState(i)?.isNocturneReady == true {
                        color = UIColor(red: 0.62, green: 0.44, blue: 1.0, alpha: 0.96)
                        hdrBoost = 1.82
                    } else if signature || enhanced {
                        color = heroEnergyColor(f.hero, enhanced: true)
                        hdrBoost = 1.72
                    } else if attack.move == .heavy {
                        color = UIColor(red: 1.0, green: 0.90, blue: 0.62, alpha: 0.85)
                        hdrBoost = 1.48
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

    /// Consume simulation step events & fighter states to drive restrained SF4-authentic combat VFX.
    func consumeStep(_ game: DuelGame, tick: Int) {
        guard game.fighters.count == 2 else { return }
        let shadowWorld = isShadowWorldActive(game)

        // 1. Trigger footwork ground dust, knockback boot-skid dust, kick wind arcs, and signature skill VFX!
        for i in 0..<2 {
            let f = game.fighters[i]
            let fx = Float(f.x) / 1000
            let fy = Float(f.y) / 1000
            let airborne = f.y > 0

            // Knockdown landing dust cloud
            if f.knockdown > 0 && previousKnockdown[i] == 0 {
                emitGroundDust(atX: fx, isShadow: shadowWorld, count: 16, size: 0.42, speed: 1.85)
            }
            // Jump landing dust puff
            if !airborne && previousAirborne[i] {
                emitGroundDust(atX: fx, isShadow: shadowWorld, count: 10, size: 0.30, speed: 1.35)
            }
            // Velocity knockback boot-skid dust trail across the courtyard flagstones!
            if !airborne && abs(f.velocityX) >= 35 && tick % 2 == 0 {
                let slideDir: Float = f.velocityX > 0 ? 1 : -1
                emitGroundDust(atX: fx - slideDir * 0.14, isShadow: shadowWorld, count: 7, size: 0.28, speed: 1.45,
                               direction: SCNVector3(-slideDir * 0.85, 0.55, 0))
            }
            previousKnockdown[i] = f.knockdown
            previousAirborne[i] = airborne

            if let attack = f.attack {
                let data = DuelGame.data(attack.move, hero: f.hero, chargeTicks: attack.chargeTicks)
                let key = "\(attack.move.rawValue):\(tick - attack.age)"
                if (attack.move.isRoll || attack.move == .dashForward || attack.move == .dashBack) && attack.age == 1 {
                    let dashSign: Float = (attack.move == .dashBack || attack.move == .rollBack) ? Float(f.facing) : -Float(f.facing)
                    emitGroundDust(atX: fx, isShadow: shadowWorld, count: 13, size: 0.34, speed: 1.65,
                                   direction: SCNVector3(dashSign * 0.75, 0.72, 0))
                }
                if attack.age >= data.startup && lastAttackKeys[i] != key {
                    lastAttackKeys[i] = key
                    let enhanced = isHeroEnhanced(game, index: i)
                    let hasCustomSkillVFX = attack.move == .shogunDespotism || attack.move == .shogunFierceReprisal ||
                        attack.move == .inquisitorLightSpin || attack.move == .inquisitorLightUp ||
                        attack.move == .inquisitorLightForward || attack.move == .inquisitorLightDown ||
                        attack.move == .midnightRemoval
                    let needsCrescent = !hasLiveBladeSegments[i] || Self.isKickOrThrow(attack.move)
                    if needsCrescent && !hasCustomSkillVFX {
                        spawnMoveCrescent(fighter: f, move: attack.move, enhanced: enhanced)
                    }
                    if attack.move == .heavy || attack.move == .weaponForward || attack.move == .kickForward || attack.move == .shogunFierceReprisal {
                        emitGroundDust(atX: fx, isShadow: shadowWorld, count: 8, size: 0.28, speed: 1.30,
                                       direction: SCNVector3(-Float(f.facing) * 0.7, 0.6, 0))
                    }
                    let facing = Float(f.facing)
                    let origin = SCNVector3(fx + facing * 0.52, fy + 1.12, 0.24)
                    switch attack.move {
                    case .shogunDespotism:
                        let slateInk = UIColor(red: 0.42, green: 0.70, blue: 0.84, alpha: 0.68)
                        emitGroundDust(atX: fx + facing * 0.35, isShadow: true, count: 16, size: 0.36, speed: 1.8)
                        emitWisps(at: SCNVector3(fx + facing * 0.48, fy + 0.92, 0.20),
                                  color: UIColor(red: 0.04, green: 0.06, blue: 0.10, alpha: 0.56),
                                  count: 14, size: 0.32, speed: 1.9, life: 0.36, spread: 95)
                        spawnSlashStreak(at: origin, color: slateInk, length: 1.55, thickness: 0.16, roll: 0.16 * facing, duration: 7, hdrBoost: 1.02)
                        triggerAccentLight(at: origin, color: slateInk, intensity: 180, ticks: 4)

                    case .shogunFierceReprisal:
                        let col = game.shogunState(i)?.isCataclysm == true
                            ? UIColor(red: 0.88, green: 0.28, blue: 0.24, alpha: 0.72)
                            : UIColor(red: 0.46, green: 0.74, blue: 0.86, alpha: 0.68)
                        spawnSlashStreak(at: origin, color: col, length: 1.55, thickness: 0.16, roll: -0.35 * facing, duration: 8, hdrBoost: 1.05)
                        emitGroundDust(atX: fx, isShadow: true, count: 14, size: 0.34, speed: 1.9,
                                       direction: SCNVector3(-facing, 0.5, 0))
                        emitSparks(at: origin, color: col, count: 14, speed: 5.2, size: 0.055, spread: 65, direction: SCNVector3(-facing, 0.2, 0))

                    case .inquisitorLightSpin, .inquisitorLightUp, .inquisitorLightForward, .inquisitorLightDown:
                        let paleBrass = UIColor(red: 0.92, green: 0.82, blue: 0.52, alpha: 0.64)
                        let soarOrigin = SCNVector3(fx + facing * 0.52, fy + 1.50, 0.24)
                        if attack.move == .inquisitorLightForward {
                            spawnSlashStreak(at: soarOrigin, color: paleBrass, length: 1.65, thickness: 0.16, roll: 0.06 * facing, duration: 8, hdrBoost: 1.04)
                        } else if attack.move == .inquisitorLightUp {
                            spawnCrescent(at: soarOrigin, color: paleBrass, facing: facing, basePitch: 0.62, sweepPitch: -1.45,
                                          startScale: 0.88, endScale: 1.20, duration: 8, hdrBoost: 1.02)
                        } else if attack.move == .inquisitorLightDown {
                            spawnSlashStreak(at: SCNVector3(fx + facing * 0.56, fy + 0.96, 0.24),
                                             color: paleBrass, length: 1.60, thickness: 0.16, roll: -0.76 * facing, duration: 8, hdrBoost: 1.04)
                        } else {
                            spawnCrescent(at: soarOrigin, color: paleBrass, facing: facing, basePitch: -0.20, sweepPitch: 2.5,
                                          startScale: 0.92, endScale: 1.24, duration: 9, hdrBoost: 1.00)
                        }
                        emitGroundDust(atX: fx, isShadow: false, count: 10, size: 0.30, speed: 1.45)

                    case .midnightRemoval:
                        let coldSteel = UIColor(red: 0.56, green: 0.78, blue: 0.88, alpha: 0.66)
                        emitGroundDust(atX: fx, isShadow: true, count: 14, size: 0.34, speed: 1.9)
                        emitWisps(at: SCNVector3(fx, fy + 0.95, 0.20),
                                  color: UIColor(red: 0.03, green: 0.04, blue: 0.08, alpha: 0.58),
                                  count: 14, size: 0.30, speed: 1.8, life: 0.34, spread: 90)
                        spawnSlashStreak(at: SCNVector3(fx, fy + 1.05, 0.24), color: coldSteel, length: 1.45, thickness: 0.14, roll: -0.30 * facing, duration: 7, hdrBoost: 1.02)
                    default:
                        break
                    }
                }
            } else {
                lastAttackKeys[i] = nil
            }
        }

        // 2. Crisp SF4-authentic hit / parry / crit / clash / counter / wall-splat / skill impacts
        for event in game.events {
            switch event {
            case .hit(let attacker, let damage):
                let def = game.fighters[1 - attacker]
                let dir = Float(game.fighters[attacker].facing)
                let pos = impactPosition(defender: def, z: 0.32)
                let heavy = damage >= 260 || (game.ruleset == .laboratory && damage >= 145)
                let sparkCol = shadowWorld
                    ? UIColor(red: 0.56, green: 0.94, blue: 1.0, alpha: 1)
                    : (heavy ? UIColor(red: 1.0, green: 0.82, blue: 0.38, alpha: 1) : UIColor(red: 1.0, green: 0.92, blue: 0.68, alpha: 1))
                emitSparks(at: pos, color: sparkCol, count: heavy ? 24 : 13, speed: heavy ? 6.0 : 4.4,
                           size: heavy ? 0.082 : 0.065, spread: 95, direction: SCNVector3(dir, 0.35, 0))
                spawnImpactCross(at: pos, color: sparkCol,
                                 peakScale: heavy ? 0.94 : 0.58, duration: heavy ? 8 : 5,
                                 roll: Float(tick % 7) * 0.14 - 0.35, hdrBoost: heavy ? 1.62 : 1.34)
                if heavy {
                    triggerAccentLight(at: pos, color: sparkCol, intensity: 380, ticks: 5)
                }

            case .counterHit(let attacker, _):
                let def = game.fighters[1 - attacker]
                let pos = impactPosition(defender: def, z: 0.38)
                let crimsonGold = UIColor(red: 1.0, green: 0.36, blue: 0.18, alpha: 1)
                spawnImpactCross(at: pos, color: crimsonGold, peakScale: 1.24, duration: 9, roll: 0.22, hdrBoost: 1.85)
                spawnSlashStreak(at: pos, color: UIColor(red: 1.0, green: 0.84, blue: 0.34, alpha: 0.96),
                                 length: 1.85, thickness: 0.24, roll: -0.34 * Float(game.fighters[attacker].facing),
                                 duration: 9, hdrBoost: 1.75)
                emitSparks(at: pos, color: crimsonGold, count: 28, speed: 6.8, size: 0.085, spread: 150)
                triggerAccentLight(at: pos, color: crimsonGold, intensity: 460, ticks: 6)

            case .bladeClash(let x, let y):
                let pos = SCNVector3(Float(x) / 1000, max(0.75, Float(y) / 1000), 0.40)
                let whiteGold = UIColor(red: 1.0, green: 0.96, blue: 0.76, alpha: 1)
                let steelCyan = UIColor(red: 0.74, green: 0.94, blue: 1.0, alpha: 1)
                spawnImpactCross(at: pos, color: whiteGold, peakScale: 1.38, duration: 10, roll: 0.0, hdrBoost: 1.95)
                spawnImpactCross(at: pos, color: steelCyan, peakScale: 1.15, duration: 9, roll: 0.785, hdrBoost: 1.75)
                spawnRipple(at: pos, color: whiteGold, startScale: 0.25, maxScale: 1.55, duration: 11, vertical: true, hdrBoost: 1.65)
                emitSparks(at: pos, color: whiteGold, count: 36, speed: 7.4, size: 0.082, spread: 180)
                triggerAccentLight(at: pos, color: whiteGold, intensity: 500, ticks: 7)

            case .wallSplat(let defender):
                let def = game.fighters[defender]
                let fx = Float(def.x) / 1000
                let pos = SCNVector3(fx, max(0.95, Float(def.y) / 1000 + 1.05), 0.30)
                let stoneGold = UIColor(red: 0.96, green: 0.82, blue: 0.56, alpha: 0.92)
                spawnRipple(at: pos, color: stoneGold, startScale: 0.35, maxScale: 1.85, duration: 13, vertical: true, hdrBoost: 1.50)
                emitGroundDust(atX: fx, isShadow: shadowWorld, count: 26, size: 0.52, speed: 2.5,
                               direction: SCNVector3(Float(def.facing) * 0.9, 0.75, 0))
                emitSparks(at: pos, color: stoneGold, count: 20, speed: 5.5, size: 0.075, spread: 115,
                           direction: SCNVector3(Float(def.facing), 0.4, 0))
                triggerAccentLight(at: pos, color: stoneGold, intensity: 400, ticks: 6)

            case .headHit(let attacker, _):
                let def = game.fighters[1 - attacker]
                let raw = impactPosition(defender: def, z: 0.36)
                let pos = SCNVector3(raw.x, max(raw.y, Float(def.y) / 1000 + 1.54), 0.36)
                let gold = UIColor(red: 1.0, green: 0.88, blue: 0.38, alpha: 1)
                spawnImpactCross(at: pos, color: gold, peakScale: 0.98, duration: 8, roll: 0.12, hdrBoost: 1.65)
                emitSparks(at: pos, color: gold, count: 22, speed: 5.8, size: 0.075, spread: 145)
                triggerAccentLight(at: pos, color: gold, intensity: 400, ticks: 5)

            case .criticalHit(let attacker, _), .shogunCritical(let attacker, _):
                let def = game.fighters[1 - attacker]
                let pos = impactPosition(defender: def, z: 0.38)
                let gold = UIColor(red: 1.0, green: 0.76, blue: 0.28, alpha: 1)
                spawnImpactCross(at: pos, color: gold, peakScale: 1.18, duration: 9, roll: 0.0, hdrBoost: 1.75)
                spawnSlashStreak(at: pos, color: UIColor(red: 1.0, green: 0.88, blue: 0.52, alpha: 0.95),
                                 length: 1.65, thickness: 0.22, roll: 0.42 * Float(game.fighters[attacker].facing),
                                 duration: 8, hdrBoost: 1.65)
                emitSparks(at: pos, color: gold, count: 28, speed: 6.6, size: 0.085, spread: 155)
                triggerAccentLight(at: pos, color: gold, intensity: 460, ticks: 6)

            case .blocked(let defender):
                let def = game.fighters[defender]
                let pos = impactPosition(defender: def, z: 0.34)
                let steelBlue = UIColor(red: 0.68, green: 0.92, blue: 1.0, alpha: 1)
                spawnImpactCross(at: pos, color: steelBlue, peakScale: 0.64, duration: 6, roll: 0.42, hdrBoost: 1.40)
                emitSparks(at: pos, color: UIColor(red: 0.86, green: 0.96, blue: 1.0, alpha: 1),
                           count: 16, speed: 5.2, size: 0.068, spread: 85,
                           direction: SCNVector3(Float(def.facing), 0.35, 0))

            case .guardBreak(let defender):
                let def = game.fighters[defender]
                let pos = impactPosition(defender: def, z: 0.36)
                let shatter = UIColor(red: 1.0, green: 0.42, blue: 0.22, alpha: 1)
                spawnImpactCross(at: pos, color: shatter, peakScale: 1.08, duration: 8, roll: 0.78, hdrBoost: 1.70)
                emitSparks(at: pos, color: shatter, count: 26, speed: 6.2, size: 0.08, spread: 160)
                triggerAccentLight(at: pos, color: shatter, intensity: 420, ticks: 6)

            case .throwHit(let attacker, _, _):
                let def = game.fighters[1 - attacker]
                let fx = Float(def.x) / 1000
                let floorPos = SCNVector3(fx, 0.08, 0.20)
                emitGroundDust(atX: fx, isShadow: shadowWorld, count: 22, size: 0.48, speed: 2.2)
                emitSparks(at: floorPos, color: UIColor(red: 1.0, green: 0.86, blue: 0.56, alpha: 1),
                           count: 14, speed: 4.2, size: 0.07, spread: 110, direction: SCNVector3(0, 1, 0))

            case .shogunShadowForm(let fighter), .shogunCataclysm(let fighter):
                let f = game.fighters[fighter]
                let cataclysm = game.shogunState(fighter)?.isCataclysm == true
                let color = cataclysm
                    ? UIColor(red: 0.88, green: 0.28, blue: 0.24, alpha: 0.78)
                    : UIColor(red: 0.44, green: 0.72, blue: 0.86, alpha: 0.72)
                let fx = Float(f.x) / 1000
                emitGroundDust(atX: fx, isShadow: true, count: 20, size: 0.42, speed: 2.1)
                emitWisps(at: SCNVector3(fx, 0.90, 0.20),
                          color: UIColor(red: 0.03, green: 0.04, blue: 0.07, alpha: 0.62),
                          count: 16, size: 0.36, speed: 1.9, life: 0.40, spread: 105)
                emitSparks(at: SCNVector3(fx, 0.90, 0.22), color: color, count: 16, speed: 4.8, size: 0.052, spread: 120)
                triggerAccentLight(at: SCNVector3(fx, 1.15, 0.24), color: color, intensity: 220, ticks: 5)

            case .shogunCataclysmStrike(let attacker, _):
                let def = game.fighters[1 - attacker]
                let pos = SCNVector3(Float(def.x) / 1000, 1.18, 0.36)
                let red = UIColor(red: 0.88, green: 0.24, blue: 0.22, alpha: 0.78)
                let steel = UIColor(red: 0.76, green: 0.84, blue: 0.90, alpha: 0.72)
                spawnSlashStreak(at: pos, color: red, length: 1.65, thickness: 0.16, roll: 0.72, duration: 8, hdrBoost: 1.08)
                spawnSlashStreak(at: pos, color: steel, length: 1.55, thickness: 0.14, roll: -0.72, duration: 8, hdrBoost: 1.02)
                spawnImpactCross(at: pos, color: UIColor(red: 0.96, green: 0.82, blue: 0.56, alpha: 0.82), peakScale: 0.85, duration: 6, hdrBoost: 1.08)
                emitGroundDust(atX: Float(def.x) / 1000, isShadow: true, count: 18, size: 0.40, speed: 2.0)
                emitSparks(at: pos, color: red, count: 22, speed: 6.2, size: 0.06, spread: 150)
                triggerAccentLight(at: pos, color: red, intensity: 240, ticks: 5)

            case .shogunCompanionHit(let owner, _):
                let def = game.fighters[1 - owner]
                let pos = SCNVector3(Float(def.x) / 1000, 1.12, 0.32)
                let steel = UIColor(red: 0.62, green: 0.80, blue: 0.90, alpha: 0.72)
                spawnSlashStreak(at: pos, color: steel, length: 1.25, thickness: 0.14, roll: -0.45 * Float(game.fighters[owner].facing), duration: 7, hdrBoost: 1.00)
                emitSparks(at: pos, color: steel, count: 12, speed: 4.8, size: 0.052)

            case .inquisitorFormOfLight(let fighter):
                let f = game.fighters[fighter]
                let fx = Float(f.x) / 1000
                let paleGold = UIColor(red: 0.94, green: 0.84, blue: 0.54, alpha: 0.72)
                spawnSkyBeam(atX: fx, color: paleGold, width: 0.60, duration: 11)
                emitGroundDust(atX: fx, isShadow: false, count: 16, size: 0.38, speed: 1.9)
                emitSparks(at: SCNVector3(fx, 1.05, 0.20), color: paleGold, count: 16, speed: 4.4, size: 0.054, spread: 110)
                triggerAccentLight(at: SCNVector3(fx, 1.20, 0.22), color: paleGold, intensity: 210, ticks: 5)

            case .inquisitorLightFormBroken(let defender):
                let def = game.fighters[defender]
                let pos = SCNVector3(Float(def.x) / 1000, Float(def.y) / 1000 + 1.35, 0.34)
                let paleGold = UIColor(red: 0.92, green: 0.80, blue: 0.48, alpha: 0.72)
                spawnImpactCross(at: pos, color: paleGold, peakScale: 0.78, duration: 6, hdrBoost: 1.05)
                emitSparks(at: pos, color: paleGold, count: 20, speed: 5.8, size: 0.06, spread: 150)
                triggerAccentLight(at: pos, color: paleGold, intensity: 200, ticks: 4)

            case .inquisitorStigmataFlash(let attacker, _):
                let def = game.fighters[1 - attacker]
                let pos = SCNVector3(Float(def.x) / 1000, 1.32, 0.34)
                let paleGold = UIColor(red: 0.94, green: 0.84, blue: 0.54, alpha: 0.78)
                spawnImpactCross(at: pos, color: paleGold, peakScale: 0.78, duration: 6, hdrBoost: 1.05)
                emitSparks(at: pos, color: paleGold, count: 18, speed: 5.4, size: 0.058, spread: 145)
                triggerAccentLight(at: pos, color: paleGold, intensity: 200, ticks: 4)

            case .inquisitorSalvationStrike(_, let x, let damage),
                 .inquisitorSalvationEcho(_, let x, let damage):
                let fx = Float(x) / 1000
                let paleGold = UIColor(red: 0.94, green: 0.84, blue: 0.54, alpha: 0.74)
                spawnSkyBeam(atX: fx, color: paleGold, width: damage > 0 ? 0.62 : 0.46, duration: 10)
                emitGroundDust(atX: fx, isShadow: false, count: 16, size: 0.40, speed: 2.0)
                if damage > 0 {
                    spawnImpactCross(at: SCNVector3(fx, 1.30, 0.34), color: paleGold, peakScale: 0.82, duration: 6, hdrBoost: 1.06)
                    emitSparks(at: SCNVector3(fx, 1.12, 0.28), color: paleGold, count: 18, speed: 5.5, size: 0.058, spread: 130)
                    triggerAccentLight(at: SCNVector3(fx, 1.28, 0.28), color: paleGold, intensity: 220, ticks: 5)
                }

            case .nonnaFlameForm(let fighter):
                let f = game.fighters[fighter]
                let fx = Float(f.x) / 1000
                let flame = UIColor(red: 1.0, green: 0.46, blue: 0.10, alpha: 1)
                emitGroundDust(atX: fx, isShadow: false, count: 18, size: 0.44, speed: 2.0)
                emitWisps(at: SCNVector3(fx, 0.65, 0.18), color: UIColor(red: 1.0, green: 0.38, blue: 0.08, alpha: 0.36),
                          count: 18, size: 0.36, speed: 2.6, life: 0.44, spread: 105)
                emitSparks(at: SCNVector3(fx, 0.95, 0.22), color: UIColor(red: 1.0, green: 0.78, blue: 0.28, alpha: 1),
                           count: 28, speed: 6.0, size: 0.08, spread: 135)
                triggerAccentLight(at: SCNVector3(fx, 1.15, 0.24), color: flame, intensity: 440, ticks: 7)

            case .nonnaWolfHit(let owner, _), .nonnaOwlHit(let owner, _, _):
                let def = game.fighters[1 - owner]
                let pos = SCNVector3(Float(def.x) / 1000, 1.12, 0.32)
                let flame = UIColor(red: 1.0, green: 0.52, blue: 0.14, alpha: 1)
                spawnImpactCross(at: pos, color: flame, peakScale: 0.88, duration: 7, hdrBoost: 1.55)
                emitSparks(at: pos, color: UIColor(red: 1.0, green: 0.80, blue: 0.28, alpha: 1), count: 18, speed: 5.4, size: 0.075)

            case .nonnaTrueShapeStrike(let attacker, _):
                let def = game.fighters[1 - attacker]
                let pos = impactPosition(defender: def, z: 0.36)
                let flame = UIColor(red: 1.0, green: 0.44, blue: 0.10, alpha: 1)
                spawnSlashStreak(at: pos, color: UIColor(red: 1.0, green: 0.62, blue: 0.16, alpha: 0.95),
                                 length: 2.05, thickness: 0.28, roll: -0.48 * Float(game.fighters[attacker].facing),
                                 duration: 10, hdrBoost: 1.70)
                spawnRipple(at: pos, color: flame, startScale: 0.30, maxScale: 1.55, duration: 11, vertical: true, hdrBoost: 1.55)
                emitSparks(at: pos, color: UIColor(red: 1.0, green: 0.78, blue: 0.26, alpha: 1), count: 24, speed: 6.2, size: 0.08, spread: 150)
                triggerAccentLight(at: pos, color: flame, intensity: 420, ticks: 6)

            case .nonnaTrueShapeExecute(let attacker, _):
                let def = game.fighters[1 - attacker]
                let pos = SCNVector3(Float(def.x) / 1000, 1.18, 0.38)
                let flame = UIColor(red: 1.0, green: 0.42, blue: 0.08, alpha: 1)
                spawnSlashStreak(at: pos, color: UIColor(red: 1.0, green: 0.64, blue: 0.16, alpha: 1),
                                 length: 2.20, thickness: 0.32, roll: -0.58 * Float(game.fighters[attacker].facing), duration: 11, hdrBoost: 1.70)
                spawnImpactCross(at: pos, color: UIColor(red: 1.0, green: 0.82, blue: 0.32, alpha: 1), peakScale: 1.30, duration: 9, hdrBoost: 1.70)
                emitGroundDust(atX: Float(def.x) / 1000, isShadow: false, count: 18, size: 0.44, speed: 2.1)
                emitSparks(at: pos, color: UIColor(red: 1.0, green: 0.78, blue: 0.26, alpha: 1), count: 32, speed: 7.0, size: 0.085, spread: 165)
                triggerAccentLight(at: pos, color: flame, intensity: 460, ticks: 7)

            case .midnightShadowShift(let fighter):
                let f = game.fighters[fighter]
                let fx = Float(f.x) / 1000
                emitGroundDust(atX: fx, isShadow: true, count: 16, size: 0.42, speed: 1.8)
                emitSparks(at: SCNVector3(fx, 1.05, 0.22), color: UIColor(red: 0.46, green: 0.90, blue: 1.0, alpha: 0.92),
                           count: 10, speed: 3.2, size: 0.06, spread: 145)

            case .midnightNocturneBurst(let attacker, _):
                let def = game.fighters[1 - attacker]
                let pos = impactPosition(defender: def, z: 0.38)
                let violet = UIColor(red: 0.64, green: 0.34, blue: 1.0, alpha: 1)
                let ice = UIColor(red: 0.42, green: 0.92, blue: 1.0, alpha: 1)
                spawnSlashStreak(at: pos, color: violet, length: 2.20, thickness: 0.30, roll: 0.66, duration: 11, hdrBoost: 1.80)
                spawnSlashStreak(at: pos, color: ice, length: 2.05, thickness: 0.26, roll: -0.66, duration: 11, hdrBoost: 1.70)
                spawnImpactCross(at: pos, color: violet, peakScale: 1.28, duration: 9, hdrBoost: 1.78)
                emitGroundDust(atX: Float(def.x) / 1000, isShadow: true, count: 20, size: 0.44, speed: 2.1)
                emitSparks(at: pos, color: ice, count: 28, speed: 6.8, size: 0.08, spread: 160)
                triggerAccentLight(at: pos, color: violet, intensity: 460, ticks: 7)

            case .midnightBlinkCounter(let attacker, _):
                let atk = game.fighters[attacker]
                let def = game.fighters[1 - attacker]
                let hitPos = SCNVector3(Float(def.x) / 1000, 1.18, 0.36)
                let healPos = SCNVector3(Float(atk.x) / 1000, 1.00, 0.26)
                let cyan = UIColor(red: 0.38, green: 0.90, blue: 1.0, alpha: 1)
                spawnSlashStreak(at: hitPos, color: cyan, length: 2.05, thickness: 0.28, roll: 0.14 * Float(atk.facing), duration: 10, hdrBoost: 1.70)
                spawnImpactCross(at: hitPos, color: cyan, peakScale: 1.15, duration: 8, roll: 0.0, hdrBoost: 1.65)
                emitSparks(at: hitPos, color: cyan, count: 24, speed: 6.2, size: 0.075, spread: 140)
                emitSparks(at: healPos, color: UIColor(red: 0.38, green: 0.98, blue: 0.76, alpha: 1),
                           count: 14, speed: 2.4, size: 0.065, spread: 55, direction: SCNVector3(0, 1, 0))
                triggerAccentLight(at: hitPos, color: cyan, intensity: 420, ticks: 6)

            case .midnightRemovalStrike(let attacker, _):
                let def = game.fighters[1 - attacker]
                let pos = SCNVector3(Float(def.x) / 1000, 1.20, 0.38)
                let iceCyan = UIColor(red: 0.40, green: 0.92, blue: 1.0, alpha: 1)
                let steelWhite = UIColor(red: 0.88, green: 0.96, blue: 1.0, alpha: 1)
                spawnSlashStreak(at: pos, color: iceCyan, length: 2.35, thickness: 0.32, roll: 0.74, duration: 12, hdrBoost: 1.75)
                spawnSlashStreak(at: pos, color: steelWhite, length: 2.25, thickness: 0.28, roll: -0.74, duration: 12, hdrBoost: 1.65)
                spawnImpactCross(at: pos, color: iceCyan, peakScale: 1.28, duration: 9, roll: 0.0, hdrBoost: 1.70)
                emitGroundDust(atX: Float(def.x) / 1000, isShadow: true, count: 22, size: 0.48, speed: 2.2)
                emitSparks(at: pos, color: iceCyan, count: 32, speed: 7.0, size: 0.08, spread: 165)
                triggerAccentLight(at: pos, color: iceCyan, intensity: 440, ticks: 7)

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

    /// Update persistent hero form auras & rotating Salvation / Light's Will ground Crusader sigil during `drawState()`.
    func updateAuras(_ game: DuelGame) {
        for i in 0..<min(2, game.fighters.count) {
            if let marker = salvationEchoMarkers[i] {
                if let inq = game.inquisitorState(i), inq.salvationCastTicks > 0 {
                    // Targeted Salvation ground warning rune right under opponent's boots before sky pillar drops!
                    let progress = 1.0 - Float(inq.salvationCastTicks) / Float(max(1, DuelInquisitorState.salvationTelegraphTicks))
                    let pulse: Float = 0.72 + 0.44 * progress
                    marker.node.isHidden = false
                    marker.node.position = SCNVector3(Float(inq.salvationCastX) / 1000, 0.05, 0.06)
                    marker.node.scale = SCNVector3(pulse, pulse, 1)
                    marker.node.eulerAngles = SCNVector3(-Float.pi / 2, -Float(game.frame) * 0.14, 0)
                    let alpha: Float = 0.55 + 0.45 * progress
                    marker.material.setValue(NSValue(scnVector4: SCNVector4(1.0, 0.90, 0.34, alpha)), forKey: "vfxTint")
                } else if let inq = game.inquisitorState(i), inq.salvationEchoTicks > 0 {
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
            updateTelegraphGlint(i, game: game)
        }
    }

    /// True while fighter `i` is in the startup of a move that will shatter auto-block
    /// (shadow moves, block-breakers, Cataclysm, Form of Light, Flame Form, Midnight 4-stack Nocturne). Throws excluded.
    static func unblockableStartupProgress(_ game: DuelGame, fighter i: Int) -> Float? {
        let f = game.fighters[i]
        guard let attack = f.attack else { return nil }
        let data = DuelGame.data(attack.move, hero: f.hero, chargeTicks: attack.chargeTicks)
        var unblockable = data.breaksBlock || data.isShadow || game.shogunState(i)?.isCataclysm == true
        if let inq = game.inquisitorState(i), inq.isInFormOfLight { unblockable = true }
        if let nonna = game.nonnaState(i), nonna.isInFlameForm { unblockable = true }
        if let mid = game.midnightState(i), mid.isNocturneReady && !attack.move.isKick { unblockable = true }
        guard unblockable, !data.isThrow, data.startup > 0, attack.age < data.startup else { return nil }
        return Float(attack.age) / Float(max(1, data.startup))
    }

    /// Flash a red glint on the attacker during the startup of moves that will
    /// shatter auto-block (shadow moves, block-breakers, Form of Light, Flame Form),
    /// mirroring Shadow Fight's unblockable warning so the defender can react.
    private func updateTelegraphGlint(_ i: Int, game: DuelGame) {
        guard let glint = telegraphGlints[i] else { return }
        guard let t = Self.unblockableStartupProgress(game, fighter: i) else {
            glint.node.isHidden = true
            return
        }
        let f = game.fighters[i]
        // Quick bloom-in, hold, then a sharp final twinkle right before the strike.
        let envelope = t < 0.25 ? t / 0.25 : (t > 0.82 ? 1.0 + (t - 0.82) * 2.2 : 1.0)
        let scale = 0.55 + 0.55 * envelope
        let facing = Float(f.facing)
        glint.node.isHidden = false
        glint.node.position = SCNVector3(Float(f.x) / 1000 + facing * 0.32, Float(f.y) / 1000 + 1.32, 0.35)
        glint.node.scale = SCNVector3(scale, scale, 1)
        let alpha = min(1, 0.35 + 0.65 * envelope)
        glint.material.setValue(NSValue(scnVector4: SCNVector4(1.0, 0.16, 0.10, alpha)), forKey: "vfxTint")
    }

    /// Build a compact subtle brass Stigmata mark hovering above branded foes (no glowing mandala).
    static func makeStigmataSigilNode() -> SCNNode {
        DuelProceduralVFXAssets.prepare()
        let plane = SCNPlane(width: 0.28, height: 0.28)
        plane.materials = [makeHDRGlowMaterial(
            texture: DuelProceduralVFXAssets.crusaderSigil,
            color: UIColor(red: 0.92, green: 0.80, blue: 0.44, alpha: 0.52),
            hdrBoost: 0.92
        )]
        let node = SCNNode(geometry: plane)
        node.castsShadow = false
        node.renderingOrder = 18
        return node
    }

    /// Build a restrained steel parry deflection glint (NO neon bubble/ring over blocking fighters).
    static func makeGuardWardNode() -> SCNNode {
        DuelProceduralVFXAssets.prepare()
        let container = SCNNode()
        let arcPlane = SCNPlane(width: 0.34, height: 0.48)
        arcPlane.materials = [makeHDRGlowMaterial(
            texture: DuelProceduralVFXAssets.slashCrescent,
            color: UIColor(red: 0.80, green: 0.86, blue: 0.92, alpha: 0.36),
            hdrBoost: 0.92
        )]
        let arcNode = SCNNode(geometry: arcPlane)
        arcNode.eulerAngles = SCNVector3(0, Float.pi / 2, -0.18)
        arcNode.castsShadow = false
        arcNode.renderingOrder = 16
        container.addChildNode(arcNode)
        return container
    }

    /// Build a restrained narrow pale-daylight Salvation shaft (zero glowing floor mandala).
    static func makeSalvationPillarNode() -> SCNNode {
        DuelProceduralVFXAssets.prepare()
        let container = SCNNode()
        let paleSun = SCNVector4(0.95, 0.86, 0.56, 0.44)
        for angle in [Float(0), Float.pi * 0.38] {
            let plane = SCNPlane(width: 0.42, height: 3.15)
            let mat = SCNMaterial()
            mat.diffuse.contents = DuelProceduralVFXAssets.energyBeam
            mat.lightingModel = .constant
            mat.isDoubleSided = true
            mat.transparencyMode = .aOne
            mat.blendMode = .add
            mat.writesToDepthBuffer = false
            mat.shaderModifiers = [.fragment: DuelVFXShaders.godRayBeamFragment]
            mat.setValue(NSValue(scnVector4: paleSun), forKey: "vfxTint")
            mat.setValue(NSNumber(value: Float(0.95)), forKey: "vfxHdrBoost")
            mat.setValue(NSNumber(value: Float(0.62)), forKey: "vfxOpacity")
            plane.materials = [mat]
            let n = SCNNode(geometry: plane)
            n.eulerAngles = SCNVector3(0, angle, 0)
            n.castsShadow = false
            n.renderingOrder = 16
            container.addChildNode(n)
        }
        let motes = SCNParticleSystem()
        motes.particleImage = DuelProceduralVFXAssets.sparkNeedle
        motes.particleColor = UIColor(red: 0.96, green: 0.88, blue: 0.58, alpha: 0.65)
        motes.birthRate = 10
        motes.particleLifeSpan = 0.36
        motes.particleSize = 0.042
        motes.particleVelocity = 1.9
        motes.spreadingAngle = 14
        motes.stretchFactor = 0.03
        motes.emittingDirection = SCNVector3(0, 1, 0)
        motes.blendMode = .additive
        motes.isLightingEnabled = false
        container.addParticleSystem(motes)
        return container
    }

    /// Build a forged dark-steel Kunai with subtle cold air slipstream for Sun Deng.
    static func makeShadowKunaiNode() -> SCNNode {
        DuelProceduralVFXAssets.prepare()
        func kunaiPart(_ geom: SCNGeometry, diffuse: UIColor, emission: UIColor, additive: Bool = false) -> SCNNode {
            let m = SCNMaterial()
            m.diffuse.contents = diffuse
            m.emission.contents = emission
            m.lightingModel = additive ? .constant : .physicallyBased
            m.metalness.contents = 0.92
            m.roughness.contents = 0.22
            if additive { m.blendMode = .add; m.writesToDepthBuffer = false }
            geom.materials = [m]
            let n = SCNNode(geometry: geom)
            n.castsShadow = false
            return n
        }
        let container = SCNNode()
        let blade = kunaiPart(SCNCone(topRadius: 0.004, bottomRadius: 0.038, height: 0.32),
                              diffuse: UIColor(red: 0.68, green: 0.72, blue: 0.76, alpha: 1),
                              emission: UIColor(red: 0.06, green: 0.10, blue: 0.14, alpha: 0.25))
        blade.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
        blade.position = SCNVector3(0.14, 0, 0)
        container.addChildNode(blade)

        let hilt = kunaiPart(SCNCylinder(radius: 0.015, height: 0.13),
                             diffuse: UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1),
                             emission: UIColor.clear)
        hilt.eulerAngles = SCNVector3(0, 0, -Float.pi / 2)
        hilt.position = SCNVector3(-0.08, 0, 0)
        container.addChildNode(hilt)

        let wakePlane = SCNPlane(width: 0.44, height: 0.09)
        wakePlane.materials = [makeHDRGlowMaterial(
            texture: DuelProceduralVFXAssets.slashStreak,
            color: UIColor(red: 0.72, green: 0.80, blue: 0.86, alpha: 0.52),
            hdrBoost: 0.95
        )]
        let wake = SCNNode(geometry: wakePlane)
        wake.position = SCNVector3(-0.16, 0, 0)
        wake.castsShadow = false
        container.addChildNode(wake)

        let trail = SCNParticleSystem()
        trail.particleImage = DuelProceduralVFXAssets.sparkNeedle
        trail.particleColor = UIColor(red: 0.76, green: 0.84, blue: 0.90, alpha: 0.56)
        trail.birthRate = 14
        trail.particleLifeSpan = 0.14
        trail.particleSize = 0.042
        trail.particleVelocity = 1.8
        trail.stretchFactor = 0.04
        trail.spreadingAngle = 10
        trail.emittingDirection = SCNVector3(-1, 0, 0)
        trail.blendMode = .additive
        trail.isLightingEnabled = false
        container.addParticleSystem(trail)
        return container
    }
}
