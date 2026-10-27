import SceneKit
import SpriteKit
import UIKit
import simd

/// 乱斗场地上的东西都是代码现画的（不用图片文件）：草地的细纹、木箱、木桶、石块、草丛、发光的子弹、粗边字和圆头血条。
/// 卡通的样子：颜色亮，东西外面一圈深色的粗边（描边的做法：同样的形状放大一点、只画朝里的那面，露在外面的一圈就是边）
@MainActor
enum ArenaArt {
    /// 墙的样子
    enum Wall { case crate, barrel, stone }

    /// 木头、石头的描边（深棕）
    static let ink = rgb(0.24, 0.14, 0.07)
    /// 草丛的描边（深绿）
    static let bushInk = rgb(0.06, 0.25, 0.10)

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    // MARK: - 描边

    /// 角色、武器、场外的树和石头的描边：顶点沿法线往外撑（宽度按场地里的米算，模型放大缩小都一样粗），只画背面
    static let outline: SCNMaterial = {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = rgb(0.09, 0.06, 0.05)
        material.cullMode = .front
        material.shaderModifiers = [.geometry: """
            float outlineScale = max(length(scn_node.modelTransform[0].xyz), 0.0001);
            _geometry.position.xyz += normalize(_geometry.normal) * (0.035 / outlineScale);
            """]
        return material
    }()

    /// 方块、圆柱、草丛的描边：形状已经放大好了，只画背面
    private static func edge(_ color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        material.cullMode = .front
        return material
    }

    private static func lit(_ image: UIImage, repeats: Float = 1) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = image
        material.diffuse.mipFilter = .linear
        material.diffuse.maxAnisotropy = 4
        if repeats != 1 {
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(repeats, 1, 1)
        }
        return material
    }

    // MARK: - 墙、草丛、场地边

    private static let crateMaterial = lit(crate)
    private static let stoneMaterial = lit(stone)
    private static let barrelSideMaterial = lit(barrelSide)
    private static let barrelTopMaterial = lit(barrelTop)
    private static let woodEdge = edge(ink)
    private static let stoneEdge = edge(rgb(0.2, 0.2, 0.24))

    /// 整张地图的墙拼成一个网格（按材质分几份，画几次就够）
    static func walls(_ cells: [(x: Int, y: Int, kind: Wall)]) -> SCNNode {
        var mesh = Mesh(parts: 6)
        for cell in cells {
            let foot = SIMD3(Float(cell.x) + 0.5, 0, Float(cell.y) + 0.5)
            switch cell.kind {
            case .crate:
                mesh.box(center: foot + SIMD3(0, 0.45, 0), size: SIMD3(repeating: 0.9), part: 0)
                mesh.box(center: foot + SIMD3(0, 0.45, 0), size: SIMD3(repeating: 0.98), part: 4)
            case .stone:
                mesh.box(center: foot + SIMD3(0, 0.47, 0), size: SIMD3(repeating: 0.94), part: 1)
                mesh.box(center: foot + SIMD3(0, 0.47, 0), size: SIMD3(repeating: 1.02), part: 5)
            case .barrel:
                mesh.cylinder(base: foot, radius: 0.38, height: 0.86, side: 2, cap: 3)
                mesh.cylinder(base: foot - SIMD3(0, 0.04, 0), radius: 0.42, height: 0.94, side: 4, cap: 4)
            }
        }
        return SCNNode(geometry: mesh.geometry([crateMaterial, stoneMaterial, barrelSideMaterial, barrelTopMaterial, woodEdge, stoneEdge]))
    }

    /// 场地四周一圈矮木沿
    static func border(width: Float, height: Float) -> SCNNode {
        var mesh = Mesh(parts: 2)
        let pieces: [(SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(width / 2, 0.11, -0.16), SIMD3(width + 0.64, 0.22, 0.32)),
            (SIMD3(width / 2, 0.11, height + 0.16), SIMD3(width + 0.64, 0.22, 0.32)),
            (SIMD3(-0.16, 0.11, height / 2), SIMD3(0.32, 0.22, height)),
            (SIMD3(width + 0.16, 0.11, height / 2), SIMD3(0.32, 0.22, height)),
        ]
        for (center, size) in pieces {
            mesh.box(center: center, size: size, part: 0)
            mesh.box(center: center, size: size + SIMD3(repeating: 0.07), part: 1)
        }
        let wood = SCNMaterial()
        wood.lightingModel = .lambert
        wood.diffuse.contents = rgb(0.90, 0.69, 0.44)
        return SCNNode(geometry: mesh.geometry([wood, woodEdge]))
    }

    private static let leafMaterial = lit(leaves, repeats: 2)

    /// 草丛：五团叶子挤在一起（三种摆法），深绿描边
    static let bushes: [SCNGeometry] = {
        let layouts: [[(SIMD3<Float>, Float)]] = [
            [(SIMD3(0, 0.5, 0.02), 0.5), (SIMD3(0.27, 0.62, 0.15), 0.38), (SIMD3(-0.25, 0.66, -0.1), 0.4),
             (SIMD3(0.05, 0.9, -0.08), 0.33), (SIMD3(-0.12, 0.48, 0.28), 0.34)],
            [(SIMD3(-0.05, 0.52, 0), 0.52), (SIMD3(0.25, 0.7, -0.15), 0.36), (SIMD3(-0.28, 0.6, 0.18), 0.36),
             (SIMD3(0.18, 0.5, 0.26), 0.32), (SIMD3(0, 0.92, 0.04), 0.3)],
            [(SIMD3(0.02, 0.48, -0.02), 0.5), (SIMD3(-0.24, 0.72, -0.2), 0.34), (SIMD3(0.28, 0.58, -0.05), 0.38),
             (SIMD3(-0.2, 0.5, 0.25), 0.33), (SIMD3(0.12, 0.88, 0.12), 0.31)],
        ]
        let rim = edge(bushInk)
        return layouts.map { balls in
            var mesh = Mesh(parts: 2)
            let squash = SIMD3<Float>(1, 0.86, 1)
            for (center, radius) in balls {
                mesh.sphere(center: center, radius: squash * radius, part: 0)
                mesh.sphere(center: center, radius: squash * (radius + 0.05), part: 1)
            }
            return mesh.geometry([leafMaterial, rim])
        }
    }()

    // MARK: - 贴图

    private static func draw(_ size: CGSize, opaque: Bool = true, _ body: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: format).image { body($0.cgContext) }
    }

    /// 0–1 之间（同一个种子每次画出来一样）
    private static func unit(_ random: inout SeededRandom) -> CGFloat {
        CGFloat(random.below(1_000_000)) / 1_000_000
    }

    /// 靠近边上的东西在对边再画一份，贴图铺开时接缝看不出来
    private static func tiled(_ size: CGFloat, at point: CGPoint, reach: CGFloat, _ body: (CGPoint) -> Void) {
        for dx in [-size, 0, size] where point.x + dx > -reach && point.x + dx < size + reach {
            for dy in [-size, 0, size] where point.y + dy > -reach && point.y + dy < size + reach {
                body(CGPoint(x: point.x + dx, y: point.y + dy))
            }
        }
    }

    /// 草地上的细纹：一张能无缝铺开的图（一张铺 2 × 2 格），和地面颜色相乘：白的地方不变，草叶、落叶的地方暗一点
    static let grassDetail: UIImage = draw(CGSize(width: 256, height: 256)) { cg in
        cg.setFillColor(UIColor.white.cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        var random = SeededRandom(seed: 11)
        cg.setLineCap(.round)
        // 一簇簇短草叶
        for _ in 0..<80 {
            let center = CGPoint(x: unit(&random) * 256, y: unit(&random) * 256)
            let shade = 0.8 + unit(&random) * 0.1
            let color = UIColor(red: shade - 0.05, green: min(shade + 0.1, 1), blue: shade - 0.14, alpha: 1).cgColor
            let count = 2 + random.below(3)
            var blades: [(root: CGFloat, bend: CGPoint, tip: CGPoint)] = []
            for k in 0..<count {
                let x = CGFloat(k * 3 - count * 3 / 2) + (unit(&random) - 0.5) * 2
                let height = 6 + unit(&random) * 7
                let lean = (unit(&random) - 0.5) * 8
                blades.append((x, CGPoint(x: x + lean * 0.3, y: -height * 0.6), CGPoint(x: x + lean, y: -height)))
            }
            tiled(256, at: center, reach: 16) { origin in
                cg.setStrokeColor(color)
                cg.setLineWidth(2)
                for blade in blades {
                    cg.move(to: CGPoint(x: origin.x + blade.root, y: origin.y))
                    cg.addQuadCurve(to: CGPoint(x: origin.x + blade.tip.x, y: origin.y + blade.tip.y),
                                    control: CGPoint(x: origin.x + blade.bend.x, y: origin.y + blade.bend.y))
                }
                cg.strokePath()
            }
        }
        // 落叶
        for _ in 0..<10 {
            let center = CGPoint(x: unit(&random) * 256, y: unit(&random) * 256)
            let angle = unit(&random) * .pi * 2
            let shade = 0.74 + unit(&random) * 0.08
            let color = UIColor(red: shade + 0.08, green: shade + 0.12, blue: shade - 0.12, alpha: 1).cgColor
            tiled(256, at: center, reach: 10) { origin in
                cg.saveGState()
                cg.translateBy(x: origin.x, y: origin.y)
                cg.rotate(by: angle)
                cg.setFillColor(color)
                cg.fillEllipse(in: CGRect(x: -6.5, y: -2.8, width: 13, height: 5.6))
                cg.restoreGState()
            }
        }
        // 小土点
        for _ in 0..<70 {
            let center = CGPoint(x: unit(&random) * 256, y: unit(&random) * 256)
            let shade = 0.84 + unit(&random) * 0.08
            cg.setFillColor(UIColor(red: shade, green: shade + 0.06, blue: shade - 0.1, alpha: 1).cgColor)
            cg.fillEllipse(in: CGRect(x: center.x - 1.2, y: center.y - 1.2, width: 2.4, height: 2.4))
        }
    }

    /// 木箱的一面：浅色木板，四边一圈木框，中间一个 X 形撑子，深棕色描线、四角钉子
    static let crate: UIImage = draw(CGSize(width: 256, height: 256)) { cg in
        let size: CGFloat = 256, rim: CGFloat = 30
        let whole = CGRect(x: 0, y: 0, width: size, height: size)
        let inner = whole.insetBy(dx: rim, dy: rim)
        let frame = rgb(0.88, 0.67, 0.42).cgColor
        cg.setFillColor(rgb(0.97, 0.84, 0.60).cgColor)
        cg.fill(whole)
        // 木纹、木板缝
        var random = SeededRandom(seed: 3)
        cg.setStrokeColor(rgb(0.80, 0.62, 0.40).withAlphaComponent(0.4).cgColor)
        cg.setLineWidth(2)
        for _ in 0..<26 {
            let start = CGPoint(x: unit(&random) * size * 0.6, y: unit(&random) * size)
            cg.move(to: start)
            cg.addLine(to: CGPoint(x: start.x + 40 + unit(&random) * 90, y: start.y + (unit(&random) - 0.5) * 4))
        }
        cg.strokePath()
        cg.setFillColor(rgb(0.55, 0.36, 0.2).withAlphaComponent(0.55).cgColor)
        for k in 1..<4 { cg.fill(CGRect(x: 0, y: CGFloat(k) * size / 4 - 1.5, width: size, height: 3)) }
        // X 撑子：先画深色的宽线当边，再画木头色的窄线
        cg.saveGState()
        cg.clip(to: inner)
        for (width, color) in [(CGFloat(42), ink.cgColor), (CGFloat(31), frame)] {
            cg.setStrokeColor(color)
            cg.setLineWidth(width)
            cg.move(to: CGPoint(x: inner.minX, y: inner.minY))
            cg.addLine(to: CGPoint(x: inner.maxX, y: inner.maxY))
            cg.move(to: CGPoint(x: inner.maxX, y: inner.minY))
            cg.addLine(to: CGPoint(x: inner.minX, y: inner.maxY))
            cg.strokePath()
        }
        cg.restoreGState()
        // 木框、描线、钉子
        cg.setFillColor(frame)
        cg.addRect(whole)
        cg.addRect(inner)
        cg.fillPath(using: .evenOdd)
        cg.setStrokeColor(rgb(0.97, 0.84, 0.60).withAlphaComponent(0.5).cgColor)
        cg.setLineWidth(3)
        cg.stroke(whole.insetBy(dx: 9, dy: 9))
        cg.setStrokeColor(ink.cgColor)
        cg.setLineWidth(7)
        cg.stroke(inner)
        cg.setLineWidth(14)
        cg.stroke(whole)
        cg.setFillColor(ink.cgColor)
        for x in [rim / 2, size - rim / 2] {
            for y in [rim / 2, size - rim / 2] {
                cg.fillEllipse(in: CGRect(x: x - 4.5, y: y - 4.5, width: 9, height: 9))
            }
        }
    }

    /// 木桶的侧面：一条条竖的木板，上下两道铁箍
    static let barrelSide: UIImage = draw(CGSize(width: 256, height: 128)) { cg in
        let staves = 8
        let width = 256 / CGFloat(staves)
        for k in 0..<staves {
            cg.setFillColor((k % 2 == 0 ? rgb(0.86, 0.60, 0.34) : rgb(0.80, 0.54, 0.31)).cgColor)
            cg.fill(CGRect(x: CGFloat(k) * width, y: 0, width: width, height: 128))
        }
        cg.setFillColor(ink.withAlphaComponent(0.6).cgColor)
        for k in 0...staves { cg.fill(CGRect(x: CGFloat(k) * width - 1.5, y: 0, width: 3, height: 128)) }
        for y in [CGFloat(20), 96] {
            cg.setFillColor(rgb(0.64, 0.65, 0.70).cgColor)
            cg.fill(CGRect(x: 0, y: y, width: 256, height: 12))
            cg.setFillColor(UIColor(white: 0.9, alpha: 0.6).cgColor)
            cg.fill(CGRect(x: 0, y: y + 2, width: 256, height: 3))
            cg.setFillColor(ink.cgColor)
            cg.fill(CGRect(x: 0, y: y - 2, width: 256, height: 3))
            cg.fill(CGRect(x: 0, y: y + 11, width: 256, height: 3))
        }
        cg.fill(CGRect(x: 0, y: 0, width: 256, height: 6))
        cg.fill(CGRect(x: 0, y: 122, width: 256, height: 6))
    }

    /// 木桶顶上：几块木板，一圈铁箍
    static let barrelTop: UIImage = draw(CGSize(width: 128, height: 128)) { cg in
        cg.setFillColor(rgb(0.88, 0.64, 0.38).cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        cg.setFillColor(ink.withAlphaComponent(0.5).cgColor)
        for k in 1..<4 { cg.fill(CGRect(x: CGFloat(k) * 32 - 1.5, y: 0, width: 3, height: 128)) }
        cg.setStrokeColor(rgb(0.64, 0.65, 0.70).cgColor)
        cg.setLineWidth(11)
        cg.strokeEllipse(in: CGRect(x: 8, y: 8, width: 112, height: 112))
        cg.setStrokeColor(ink.cgColor)
        cg.setLineWidth(3)
        cg.strokeEllipse(in: CGRect(x: 14, y: 14, width: 100, height: 100))
        cg.setLineWidth(6)
        cg.strokeEllipse(in: CGRect(x: 2, y: 2, width: 124, height: 124))
    }

    /// 石块的一面：浅灰的大石砖，两行错开，亮边、裂纹
    static let stone: UIImage = draw(CGSize(width: 256, height: 256)) { cg in
        let whole = CGRect(x: 0, y: 0, width: 256, height: 256)
        cg.setFillColor(rgb(0.80, 0.80, 0.78).cgColor)
        cg.fill(whole)
        let bricks = [CGRect(x: 0, y: 0, width: 128, height: 128), CGRect(x: 128, y: 0, width: 128, height: 128),
                      CGRect(x: -64, y: 128, width: 128, height: 128), CGRect(x: 64, y: 128, width: 128, height: 128),
                      CGRect(x: 192, y: 128, width: 128, height: 128)]
        for brick in bricks {
            cg.setFillColor(UIColor(white: 1, alpha: 0.35).cgColor)
            cg.fill(CGRect(x: brick.minX + 6, y: brick.minY + 6, width: brick.width - 12, height: 8))
            cg.setFillColor(UIColor(white: 0, alpha: 0.12).cgColor)
            cg.fill(CGRect(x: brick.minX + 6, y: brick.maxY - 14, width: brick.width - 12, height: 8))
            cg.setStrokeColor(rgb(0.42, 0.42, 0.46).cgColor)
            cg.setLineWidth(6)
            cg.stroke(brick)
        }
        var random = SeededRandom(seed: 9)
        cg.setStrokeColor(rgb(0.5, 0.5, 0.54).cgColor)
        cg.setLineWidth(2)
        for _ in 0..<5 {
            var point = CGPoint(x: 20 + unit(&random) * 216, y: 20 + unit(&random) * 216)
            cg.move(to: point)
            for _ in 0..<3 {
                point = CGPoint(x: point.x + (unit(&random) - 0.5) * 30, y: point.y + unit(&random) * 16)
                cg.addLine(to: point)
            }
        }
        cg.strokePath()
        cg.setStrokeColor(rgb(0.2, 0.2, 0.24).cgColor)
        cg.setLineWidth(14)
        cg.stroke(whole)
    }

    /// 草丛的叶子：深绿底上一片片深浅不一的叶子（无缝）
    static let leaves: UIImage = draw(CGSize(width: 256, height: 256)) { cg in
        cg.setFillColor(rgb(0.19, 0.53, 0.24).cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        var random = SeededRandom(seed: 5)
        let colors = [rgb(0.15, 0.45, 0.20), rgb(0.25, 0.64, 0.30), rgb(0.32, 0.73, 0.34), rgb(0.46, 0.84, 0.42)]
        let total = 170
        for k in 0..<total {
            let center = CGPoint(x: unit(&random) * 256, y: unit(&random) * 256)
            let angle = unit(&random) * .pi * 2
            let length = 18 + unit(&random) * 12
            let color = colors[k * colors.count / total].cgColor
            let leaf = CGMutablePath()
            leaf.move(to: CGPoint(x: -length / 2, y: 0))
            leaf.addQuadCurve(to: CGPoint(x: length / 2, y: 0), control: CGPoint(x: 0, y: -length * 0.42))
            leaf.addQuadCurve(to: CGPoint(x: -length / 2, y: 0), control: CGPoint(x: 0, y: length * 0.42))
            tiled(256, at: center, reach: length) { origin in
                cg.saveGState()
                cg.translateBy(x: origin.x, y: origin.y)
                cg.rotate(by: angle)
                cg.addPath(leaf)
                cg.setFillColor(color)
                cg.fillPath()
                cg.restoreGState()
            }
        }
    }

    /// 发光的软圆点：中间白、往外是这个颜色、边上透明（子弹的光晕、打中的闪光）
    static func glow(_ color: UIColor) -> UIImage {
        draw(CGSize(width: 64, height: 64), opaque: false) { cg in
            let colors = [UIColor.white.cgColor, color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.3, 1]) else { return }
            cg.drawRadialGradient(gradient, startCenter: CGPoint(x: 32, y: 32), startRadius: 0,
                                  endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        }
    }

    // MARK: - 头顶的字和血条

    /// 粗圆体、描黑边、底下带一点影子的字（名字、血量、伤害数字）
    static func text(_ string: String, size: CGFloat, color: UIColor) -> UIImage {
        let font = UIFont(name: "ArialRoundedMTBold", size: size) ?? UIFont.systemFont(ofSize: size, weight: .heavy)
        let line = max(1.5, size * 0.17)
        let fill = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
        let edge = NSAttributedString(string: string, attributes: [
            .font: font, .foregroundColor: UIColor.black, .strokeColor: UIColor.black,
            .strokeWidth: -200 * line / size,
        ])
        let bounds = fill.size()
        let pad = line + 1
        let drop = line * 0.7
        let canvas = CGSize(width: ceil(bounds.width + pad * 2), height: ceil(bounds.height + pad * 2 + drop))
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            edge.draw(at: CGPoint(x: pad, y: pad + drop))
            edge.draw(at: CGPoint(x: pad, y: pad))
            fill.draw(at: CGPoint(x: pad, y: pad))
        }
    }

    private static var pills: [CGFloat: UIImage] = [:]

    /// 圆头的条（白的，上面三分之一更亮一点；用的时候染成要的颜色、横着拉长）
    static func pill(height: CGFloat) -> UIImage {
        if let image = pills[height] { return image }
        let size = CGSize(width: height * 2, height: height)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let shape = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: height / 2)
            UIColor(white: 0.84, alpha: 1).setFill()
            shape.fill()
            shape.addClip()
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: height * 0.4))
        }
        pills[height] = image
        return image
    }
}

/// 一行粗边字（现画成贴图）：文字、颜色变了才重画
@MainActor
final class ArenaText {
    let node = SKSpriteNode()
    private let size: CGFloat
    private var color: UIColor
    private var shown: String?

    init(size: CGFloat, color: UIColor) {
        self.size = size
        self.color = color
        node.isHidden = true
    }

    func set(_ text: String, color newColor: UIColor? = nil) {
        if let newColor, newColor != color {
            color = newColor
            shown = nil
        }
        guard text != shown else { return }
        shown = text
        guard !text.isEmpty else {
            node.isHidden = true
            return
        }
        let image = ArenaArt.text(text, size: size, color: color)
        node.texture = SKTexture(image: image)
        node.size = image.size
        node.isHidden = false
    }
}

/// 圆头的粗条（血条、弹药）：深色的底，上面彩色的条按比例缩短
@MainActor
final class ArenaBar {
    let node = SKNode()
    private let fill: SKSpriteNode
    private let length: CGFloat
    private let pillWidth: CGFloat

    init(width: CGFloat, height: CGFloat, color: UIColor, border: CGFloat = 1.5) {
        let outer = height + border * 2
        let back = SKSpriteNode(texture: SKTexture(image: ArenaArt.pill(height: outer)))
        back.size = CGSize(width: outer * 2, height: outer)
        back.centerRect = CGRect(x: 0.3, y: 0, width: 0.4, height: 1)
        back.color = UIColor(white: 0.07, alpha: 1)
        back.colorBlendFactor = 1
        back.xScale = (width + border * 2) / (outer * 2)
        let bar = SKSpriteNode(texture: SKTexture(image: ArenaArt.pill(height: height)))
        bar.size = CGSize(width: height * 2, height: height)
        bar.centerRect = CGRect(x: 0.3, y: 0, width: 0.4, height: 1)
        bar.color = color
        bar.colorBlendFactor = 1
        bar.anchorPoint = CGPoint(x: 0, y: 0.5)
        bar.position = CGPoint(x: -width / 2, y: 0)
        fill = bar
        length = width
        pillWidth = height * 2
        node.addChild(back)
        node.addChild(bar)
        set(1)
    }

    var color: UIColor {
        get { fill.color }
        set { fill.color = newValue }
    }

    /// fraction：0–1；dim：没攒满的（弹药）暗一点
    func set(_ fraction: CGFloat, dim: Bool = false) {
        let part = max(0, min(1, fraction))
        fill.isHidden = part <= 0.001
        fill.xScale = part * length / pillWidth
        fill.alpha = dim ? 0.5 : 1
    }
}

/// 自己拼的网格：顶点、法线、贴图坐标；三角形按材质分成几份（一份画一次）
private struct Mesh {
    private var positions: [Float] = []
    private var normals: [Float] = []
    private var uvs: [Float] = []
    private var parts: [[UInt32]]

    init(parts count: Int) {
        parts = Array(repeating: [], count: count)
    }

    private mutating func vertex(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ u: Float, _ v: Float) {
        positions += [p.x, p.y, p.z]
        normals += [n.x, n.y, n.z]
        uvs += [u, v]
    }

    private var next: UInt32 { UInt32(positions.count / 3) }

    /// 方块：六个面都贴整张图（正着放）。从外面看三角形是逆时针的
    mutating func box(center: SIMD3<Float>, size: SIMD3<Float>, part: Int) {
        let half = size / 2
        // 每个面：朝外、往右、往上
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3(0, 0, 1), SIMD3(1, 0, 0), SIMD3(0, 1, 0)),
            (SIMD3(0, 0, -1), SIMD3(-1, 0, 0), SIMD3(0, 1, 0)),
            (SIMD3(1, 0, 0), SIMD3(0, 0, -1), SIMD3(0, 1, 0)),
            (SIMD3(-1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 1, 0)),
            (SIMD3(0, 1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, -1)),
            (SIMD3(0, -1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1)),
        ]
        for (out, right, up) in faces {
            let middle = center + out * half
            let r = right * half, u = up * half
            let first = next
            vertex(middle - r - u, out, 0, 1)
            vertex(middle + r - u, out, 1, 1)
            vertex(middle + r + u, out, 1, 0)
            vertex(middle - r + u, out, 0, 0)
            parts[part] += [first, first + 1, first + 2, first, first + 2, first + 3]
        }
    }

    /// 圆柱（木桶）：侧面贴一整圈，顶上一块圆；底下贴着地，不画
    mutating func cylinder(base: SIMD3<Float>, radius: Float, height: Float, side: Int, cap: Int, segments: Int = 20) {
        let start = next
        for k in 0...segments {
            let angle = Float(k) / Float(segments) * 2 * .pi
            let out = SIMD3(cos(angle), 0, -sin(angle))
            let u = Float(k) / Float(segments)
            vertex(base + out * radius, out, u, 1)
            vertex(base + out * radius + SIMD3(0, height, 0), out, u, 0)
        }
        for k in 0..<UInt32(segments) {
            let bottomLeft = start + k * 2, bottomRight = bottomLeft + 2
            parts[side] += [bottomLeft, bottomRight, bottomRight + 1, bottomLeft, bottomRight + 1, bottomLeft + 1]
        }
        let middle = next
        let up = SIMD3<Float>(0, 1, 0)
        vertex(base + SIMD3(0, height, 0), up, 0.5, 0.5)
        for k in 0...segments {
            let angle = Float(k) / Float(segments) * 2 * .pi
            vertex(base + SIMD3(cos(angle) * radius, height, -sin(angle) * radius), up, 0.5 + 0.5 * cos(angle), 0.5 - 0.5 * sin(angle))
        }
        for k in 0..<UInt32(segments) {
            parts[cap] += [middle, middle + 1 + k, middle + 2 + k]
        }
    }

    /// 球（radius 三个方向可以不一样：压扁的一团叶子）
    mutating func sphere(center: SIMD3<Float>, radius: SIMD3<Float>, part: Int, rings: Int = 8, segments: Int = 12) {
        let start = next
        for i in 0...rings {
            let phi = Float(i) / Float(rings) * .pi
            for k in 0...segments {
                let theta = Float(k) / Float(segments) * 2 * .pi
                let direction = SIMD3(sin(phi) * cos(theta), cos(phi), -sin(phi) * sin(theta))
                vertex(center + direction * radius, simd_normalize(direction / radius), Float(k) / Float(segments), Float(i) / Float(rings))
            }
        }
        let row = UInt32(segments + 1)
        for i in 0..<UInt32(rings) {
            for k in 0..<UInt32(segments) {
                let topLeft = start + i * row + k, bottomLeft = topLeft + row
                parts[part] += [bottomLeft, bottomLeft + 1, topLeft + 1, bottomLeft, topLeft + 1, topLeft]
            }
        }
    }

    func geometry(_ materials: [SCNMaterial]) -> SCNGeometry {
        let count = positions.count / 3
        let sources = [Mesh.source(positions, .vertex, width: 3, count: count),
                       Mesh.source(normals, .normal, width: 3, count: count),
                       Mesh.source(uvs, .texcoord, width: 2, count: count)]
        var elements: [SCNGeometryElement] = []
        var used: [SCNMaterial] = []
        for (k, indices) in parts.enumerated() where !indices.isEmpty && materials.indices.contains(k) {
            elements.append(SCNGeometryElement(indices: indices, primitiveType: .triangles))
            used.append(materials[k])
        }
        let geometry = SCNGeometry(sources: sources, elements: elements)
        geometry.materials = used
        return geometry
    }

    private static func source(_ values: [Float], _ semantic: SCNGeometrySource.Semantic, width: Int, count: Int) -> SCNGeometrySource {
        SCNGeometrySource(data: values.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: semantic, vectorCount: count,
                          usesFloatComponents: true, componentsPerVector: width, bytesPerComponent: MemoryLayout<Float>.size,
                          dataOffset: 0, dataStride: MemoryLayout<Float>.size * width)
    }
}
