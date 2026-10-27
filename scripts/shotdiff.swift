// 截图对比（CI 用，macOS 上编译：swiftc -O scripts/shotdiff.swift -o shotdiff）
//
//   shotdiff same a.jpg b.jpg          两张几乎一样：退出码 0，否则 1（长页面往下翻不动时去掉重复的那张）
//   shotdiff compare new/ old/ diff/   逐张和上一版比：变了的在 diff/ 里生成「旧 | 新 | 变化处」拼图，
//                                      标准输出打印 Markdown 小结（哪些页变了、变了多少、新加的、没了的）
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 缩小到这么宽再比：文字抗锯齿、JPEG 噪点不算变化，又能看出哪一块变了
let sampleWidth = 300
/// 一个点三色里差得最多的那个超过这个值算变了
let pixelThreshold = 48
/// 变了的点占比超过这个算这一页变了
let pageThreshold = 0.002

struct Bitmap {
    var width: Int
    var height: Int
    var pixels: [UInt8]   // RGBA

    func at(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * width + x) * 4
        return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
    }
}

func load(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func render(_ image: CGImage, width: Int, height: Int) -> Bitmap {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return Bitmap(width: width, height: height, pixels: pixels)
}

/// 两张图缩到同样大小比；返回变了的点的占比和每个点变没变
func difference(_ a: CGImage, _ b: CGImage) -> (ratio: Double, mask: [Bool], width: Int, height: Int) {
    let w = sampleWidth
    let h = max(1, Int(Double(w) * Double(b.height) / Double(b.width)))
    let x = render(a, width: w, height: h), y = render(b, width: w, height: h)
    var mask = [Bool](repeating: false, count: w * h)
    var changed = 0
    for row in 0..<h {
        for col in 0..<w {
            let p = x.at(col, row), q = y.at(col, row)
            if max(abs(p.0 - q.0), abs(p.1 - q.1), abs(p.2 - q.2)) > pixelThreshold {
                mask[row * w + col] = true
                changed += 1
            }
        }
    }
    // 两张高度不一样（页面变长变短）也算变了
    let sizeChanged = a.width * b.height != b.width * a.height
    return (sizeChanged ? max(Double(changed) / Double(w * h), 1) : Double(changed) / Double(w * h), mask, w, h)
}

/// 「旧 | 新 | 变化处（新图变暗、变了的地方标红）」
func writeComposite(old: CGImage, new: CGImage, mask: [Bool], maskWidth: Int, maskHeight: Int, to path: String) {
    let panelWidth = 360
    let panelHeight = Int(Double(panelWidth) * Double(new.height) / Double(new.width))
    let gap = 12
    let width = panelWidth * 3 + gap * 2
    let context = CGContext(data: nil, width: width, height: panelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: panelHeight))
    let oldHeight = Int(Double(panelWidth) * Double(old.height) / Double(old.width))
    context.draw(old, in: CGRect(x: 0, y: panelHeight - oldHeight, width: panelWidth, height: oldHeight))
    context.draw(new, in: CGRect(x: panelWidth + gap, y: 0, width: panelWidth, height: panelHeight))
    let third = CGRect(x: (panelWidth + gap) * 2, y: 0, width: panelWidth, height: panelHeight)
    context.setAlpha(0.35)
    context.draw(new, in: third)
    context.setAlpha(1)
    context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 0.85))
    let sx = Double(panelWidth) / Double(maskWidth), sy = Double(panelHeight) / Double(maskHeight)
    for row in 0..<maskHeight {
        for col in 0..<maskWidth where mask[row * maskWidth + col] {
            // CGContext 的原点在左下
            context.fill(CGRect(x: third.minX + Double(col) * sx, y: Double(maskHeight - 1 - row) * sy,
                                width: sx.rounded(.up), height: sy.rounded(.up)))
        }
    }
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                            UTType.jpeg.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
    CGImageDestinationFinalize(destination)
}

func jpgs(in folder: String) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".jpg") }.sorted()
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "same" where args.count == 4:
    guard let a = load(args[2]), let b = load(args[3]) else { exit(1) }
    exit(difference(a, b).ratio < pageThreshold ? 0 : 1)

case "compare" where args.count == 5:
    let (newDir, oldDir, outDir) = (args[2], args[3], args[4])
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    let newNames = jpgs(in: newDir), oldNames = Set(jpgs(in: oldDir))
    var changed: [(String, Double)] = []
    var added: [String] = []
    for name in newNames {
        guard oldNames.contains(name) else { added.append(name); continue }
        guard let new = load("\(newDir)/\(name)"), let old = load("\(oldDir)/\(name)") else { continue }
        let d = difference(old, new)
        guard d.ratio >= pageThreshold else { continue }
        changed.append((name, d.ratio))
        writeComposite(old: old, new: new, mask: d.mask, maskWidth: d.width, maskHeight: d.height,
                       to: "\(outDir)/\(name)")
    }
    let removed = oldNames.subtracting(newNames).sorted()
    var lines = ["## 截图和上一版比", ""]
    if changed.isEmpty && added.isEmpty && removed.isEmpty {
        lines.append("没有变化（\(newNames.count) 张）。")
    } else {
        lines.append("共 \(newNames.count) 张：变了 \(changed.count) 张，新加 \(added.count) 张，没了 \(removed.count) 张。")
        if !changed.isEmpty {
            lines += ["", "| 页面 | 变了多少 |", "|---|---|"]
            for (name, ratio) in changed.sorted(by: { $0.1 > $1.1 }) {
                let percent = ratio >= 1 ? "高度变了" : String(format: "%.1f%%", ratio * 100)
                lines.append("| \(name.replacingOccurrences(of: ".jpg", with: "")) | \(percent) |")
            }
        }
        if !added.isEmpty { lines += ["", "新加：" + added.map { $0.replacingOccurrences(of: ".jpg", with: "") }.joined(separator: "、")] }
        if !removed.isEmpty { lines += ["", "没了：" + removed.map { $0.replacingOccurrences(of: ".jpg", with: "") }.joined(separator: "、")] }
        lines += ["", "变了的页在 screenshots 分支的 diff/ 里：左边旧、中间新、右边红色是变了的地方。"]
    }
    print(lines.joined(separator: "\n"))

default:
    FileHandle.standardError.write("用法：shotdiff same a.jpg b.jpg | shotdiff compare 新目录 旧目录 输出目录\n".data(using: .utf8)!)
    exit(2)
}
