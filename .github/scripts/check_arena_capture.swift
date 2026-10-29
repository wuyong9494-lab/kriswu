// Reject launch placeholders, not just small PNG files. Build 398's white
// launch screen was 79 KB and passed the former 20 KB file-size check.
import Foundation
import CoreGraphics
import ImageIO

func reject(_ reason: String) -> Never {
    FileHandle.standardError.write(Data((reason + "\n").utf8))
    exit(1)
}
guard CommandLine.arguments.count == 2 else { reject("Usage: check_arena_capture image.png") }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width >= 500, image.height >= 500 else { reject("Missing or invalid screenshot") }
let edge = 64
var pixels = [UInt8](repeating: 0, count: edge * edge * 4)
pixels.withUnsafeMutableBytes { buffer in
    guard let context = CGContext(data: buffer.baseAddress, width: edge, height: edge,
        bitsPerComponent: 8, bytesPerRow: edge * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
    else { reject("Could not decode screenshot") }
    context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(edge), height: CGFloat(edge)))
}
var coloured = 0
for i in stride(from: 0, to: pixels.count, by: 4) {
    let high = max(pixels[i], pixels[i + 1], pixels[i + 2])
    let low = min(pixels[i], pixels[i + 1], pixels[i + 2])
    if high > 25 && Int(high) - Int(low) > 16 { coloured += 1 }
}
let coverage = Double(coloured) / Double(edge * edge)
guard coverage > 0.15 else { reject("Launch/blank screenshot: coloured coverage \(coverage)") }
print("Capture has game colour content: \(image.width)x\(image.height), coverage \(coverage). Visual review still required.")
