import UIKit

/// 运行时用代码画出的贴图（不需要任何外部图片）。全部缓存，只画一次。
@MainActor
enum RiftTextures {
    private static var cache: [String: UIImage] = [:]

    private static func cached(_ key: String, _ make: () -> UIImage) -> UIImage {
        if let img = cache[key] { return img }
        let img = make()
        cache[key] = img
        return img
    }

    private static func render(_ size: CGSize, opaque: Bool = false, _ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
    }

    static func radial(inner: UIColor, outer: UIColor, size: Int = 128) -> UIImage {
        cached("radial-\(inner)-\(outer)-\(size)") {
            render(CGSize(width: size, height: size)) { ctx in
                let colors = [inner.cgColor, outer.cgColor] as CFArray
                let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
                let c = CGPoint(x: size / 2, y: size / 2)
                ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size) / 2, options: [])
            }
        }
    }

    /// 柔和光点（粒子）
    static var softDot: UIImage {
        radial(inner: UIColor(white: 1, alpha: 1), outer: UIColor(white: 1, alpha: 0), size: 64)
    }

    /// 细长火花
    static var spark: UIImage {
        cached("spark") {
            render(CGSize(width: 16, height: 64)) { ctx in
                let colors = [UIColor(white: 1, alpha: 0).cgColor, UIColor.white.cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
                let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
                ctx.addEllipse(in: CGRect(x: 4, y: 0, width: 8, height: 64))
                ctx.clip()
                ctx.drawLinearGradient(g, start: CGPoint(x: 8, y: 0), end: CGPoint(x: 8, y: 64), options: [])
            }
        }
    }

    /// 冲击波圆环
    static var ring: UIImage {
        cached("ring") {
            render(CGSize(width: 256, height: 256)) { ctx in
                for i in 0..<14 {
                    let a = CGFloat(i) / 14
                    ctx.setStrokeColor(UIColor(white: 1, alpha: (1 - a) * 0.5).cgColor)
                    ctx.setLineWidth(3)
                    let r = 112 - CGFloat(i) * 2.2
                    ctx.strokeEllipse(in: CGRect(x: 128 - r, y: 128 - r, width: r * 2, height: r * 2))
                }
            }
        }
    }

    /// 剑气 / 刀光的新月形
    static var crescent: UIImage {
        cached("crescent") {
            render(CGSize(width: 256, height: 256)) { ctx in
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 70, y: 20))
                path.addQuadCurve(to: CGPoint(x: 70, y: 236), controlPoint: CGPoint(x: 290, y: 128))
                path.addQuadCurve(to: CGPoint(x: 70, y: 20), controlPoint: CGPoint(x: 190, y: 128))
                ctx.addPath(path.cgPath)
                ctx.clip()
                let colors = [UIColor(white: 1, alpha: 0.0).cgColor, UIColor(white: 1, alpha: 1).cgColor] as CFArray
                let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
                ctx.drawLinearGradient(g, start: CGPoint(x: 70, y: 128), end: CGPoint(x: 220, y: 128), options: [])
            }
        }
    }

    /// 擂台地面：青石板 + 裂纹 + 苔痕（程序噪声）
    static var stoneFloor: UIImage {
        cached("floor") {
            render(CGSize(width: 1024, height: 512), opaque: true) { ctx in
                var rng = RiftRandom(seed: 42)
                ctx.setFillColor(UIColor(red: 0.22, green: 0.21, blue: 0.24, alpha: 1).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 512))
                let tile: CGFloat = 128
                for row in 0..<4 {
                    for col in 0..<9 {
                        let off = row % 2 == 0 ? 0 : tile / 2
                        let rect = CGRect(x: CGFloat(col) * tile - off + 3, y: CGFloat(row) * tile + 3, width: tile - 6, height: tile - 6)
                        let shade = 0.24 + Double(rng.next() % 100) / 100 * 0.1
                        ctx.setFillColor(UIColor(red: shade, green: shade * 0.97, blue: shade * 1.08, alpha: 1).cgColor)
                        ctx.fill(rect)
                        for _ in 0..<40 {
                            let x = rect.minX + CGFloat(rng.next() % UInt64(tile - 6))
                            let y = rect.minY + CGFloat(rng.next() % UInt64(tile - 6))
                            let v = Double(rng.next() % 100) / 100
                            ctx.setFillColor(UIColor(white: v > 0.5 ? 1 : 0, alpha: 0.05).cgColor)
                            ctx.fillEllipse(in: CGRect(x: x, y: y, width: 6, height: 6))
                        }
                    }
                }
                ctx.setStrokeColor(UIColor(white: 0.05, alpha: 0.5).cgColor)
                ctx.setLineWidth(1.5)
                for _ in 0..<14 {
                    var p = CGPoint(x: CGFloat(rng.next() % 1024), y: CGFloat(rng.next() % 512))
                    ctx.move(to: p)
                    for _ in 0..<6 {
                        p.x += CGFloat(Int(rng.next() % 40) - 20); p.y += CGFloat(Int(rng.next() % 40) - 20)
                        ctx.addLine(to: p)
                    }
                    ctx.strokePath()
                }
            }
        }
    }

    /// 天空：暮色渐变 + 天空中的紫色裂隙
    static var sky: UIImage {
        cached("sky") {
            render(CGSize(width: 1024, height: 512), opaque: true) { ctx in
                let colors = [UIColor(red: 0.05, green: 0.04, blue: 0.12, alpha: 1).cgColor,
                              UIColor(red: 0.22, green: 0.1, blue: 0.3, alpha: 1).cgColor,
                              UIColor(red: 0.75, green: 0.35, blue: 0.3, alpha: 1).cgColor] as CFArray
                let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.6, 1])!
                ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 512), options: [])
                var rng = RiftRandom(seed: 7)
                for _ in 0..<160 {
                    let x = CGFloat(rng.next() % 1024), y = CGFloat(rng.next() % 260)
                    let s = CGFloat(rng.next() % 3) + 1
                    ctx.setFillColor(UIColor(white: 1, alpha: 0.3 + Double(rng.next() % 50) / 100).cgColor)
                    ctx.fillEllipse(in: CGRect(x: x, y: y, width: s, height: s))
                }
                // 裂隙
                ctx.saveGState()
                let crack = UIBezierPath()
                var p = CGPoint(x: 380, y: 30)
                crack.move(to: p)
                for _ in 0..<10 {
                    p.x += CGFloat(Int(rng.next() % 50) + 10); p.y += CGFloat(Int(rng.next() % 30) - 4)
                    crack.addLine(to: p)
                }
                ctx.setShadow(offset: .zero, blur: 30, color: UIColor(red: 0.8, green: 0.4, blue: 1, alpha: 1).cgColor)
                ctx.setStrokeColor(UIColor(red: 0.95, green: 0.8, blue: 1, alpha: 1).cgColor)
                ctx.setLineWidth(5)
                ctx.addPath(crack.cgPath)
                ctx.strokePath()
                ctx.setLineWidth(2)
                ctx.setStrokeColor(UIColor.white.cgColor)
                ctx.addPath(crack.cgPath)
                ctx.strokePath()
                ctx.restoreGState()
            }
        }
    }
}
