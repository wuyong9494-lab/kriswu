import Foundation
import zlib

/// Reads the original RGB samples before an image decoder can premultiply alpha.
/// Only the PNG formats used by the arena models are supported: 8-bit RGB/RGBA,
/// noninterlaced, with standard PNG filtering and a complete zlib stream.
/// https://www.w3.org/TR/png-3/
enum ArenaOpaquePNG {
    struct Image {
        let width: Int
        let height: Int
        /// Row-major RGBX bytes. X is always 255; RGB includes hidden alpha-zero color.
        let rgba: Data
    }

    private static let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
    private static let byteLimit = 64 * 1024 * 1024
    private static let dimensionLimit = 8192

    static func isPNG(_ data: Data) -> Bool {
        data.starts(with: signature)
    }

    static func decode(_ data: Data) -> Image? {
        guard data.count <= byteLimit, isPNG(data) else { return nil }
        return data.withUnsafeBytes { (input: UnsafeRawBufferPointer) -> Image? in
            var offset = signature.count
            var width = 0
            var height = 0
            var components = 0
            var hasHeader = false
            var hasPalette = false
            var hasTransparency = false
            var hasData = false
            var endedData = false
            var compressed = Data()

            while offset < input.count {
                guard input.count - offset >= 12 else { return nil }
                let length = Int(uint32(input, at: offset))
                guard length <= input.count - offset - 12 else { return nil }
                let typeOffset = offset + 4
                let payload = offset + 8
                let end = payload + length
                // PNG chunk names are ASCII letters, with the reserved bit clear.
                for index in typeOffset..<(typeOffset + 4) {
                    let byte = input[index]
                    guard (65...90).contains(byte) || (97...122).contains(byte) else { return nil }
                }
                guard input[typeOffset + 2] & 32 == 0 else { return nil }
                let crc = crc32(crc32(0, nil, 0),
                    input.baseAddress!.advanced(by: typeOffset).assumingMemoryBound(to: Bytef.self),
                    uInt(length + 4))
                guard UInt32(truncatingIfNeeded: crc) == uint32(input, at: end) else { return nil }

                let type = uint32(input, at: typeOffset)
                guard hasHeader || type == 0x49484452 else { return nil } // IHDR first
                if hasData && type != 0x49444154 { endedData = true }
                offset = end + 4

                switch type {
                case 0x49484452: // IHDR
                    guard !hasHeader, length == 13 else { return nil }
                    width = Int(uint32(input, at: payload))
                    height = Int(uint32(input, at: payload + 4))
                    let colorType = input[payload + 9]
                    guard width > 0, height > 0,
                          width <= dimensionLimit, height <= dimensionLimit,
                          width * height <= byteLimit / 4,
                          input[payload + 8] == 8,
                          colorType == 2 || colorType == 6,
                          input[payload + 10] == 0, input[payload + 11] == 0,
                          input[payload + 12] == 0 else { return nil }
                    components = colorType == 2 ? 3 : 4
                    hasHeader = true
                case 0x504C5445: // Optional PLTE for truecolor images
                    guard !hasPalette, !hasTransparency, !hasData,
                          length > 0, length <= 768, length % 3 == 0 else { return nil }
                    hasPalette = true
                case 0x74524E53: // RGB tRNS is deliberately ignored for opaque output
                    guard !hasTransparency, !hasData, components == 3, length == 6 else { return nil }
                    hasTransparency = true
                case 0x49444154: // Consecutive IDAT chunks form one zlib stream
                    guard !endedData, length <= byteLimit - compressed.count else { return nil }
                    compressed.append(input.baseAddress!.advanced(by: payload)
                        .assumingMemoryBound(to: UInt8.self), count: length)
                    hasData = true
                case 0x49454E44: // IEND
                    guard length == 0, hasData, !compressed.isEmpty,
                          offset == input.count else { return nil }
                    return pixels(compressed, width: width, height: height, components: components)
                case 0x6163544C, 0x6663544C, 0x66644154: // APNG is not a single texture
                    return nil
                default:
                    // Unknown critical chunks (including CgBI) cannot be decoded safely.
                    guard input[typeOffset] & 32 != 0 else { return nil }
                }
            }
            return nil // Missing IEND
        }
    }

    private static func pixels(_ compressed: Data, width: Int, height: Int, components: Int) -> Image? {
        let rowBytes = width * components
        let filteredStride = rowBytes + 1
        let filteredCount = filteredStride * height
        let outputCount = width * height * 4
        // At most 64 MiB of pixels plus one filter byte per bounded image row.
        guard outputCount <= byteLimit, filteredCount <= byteLimit + dimensionLimit else { return nil }
        var output = Data(count: max(filteredCount, outputCount))
        let decoded = output.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) -> Bool in
            var decodedLength = uLongf(filteredCount)
            var sourceLength = uLong(compressed.count)
            let status = compressed.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
                uncompress2(bytes.baseAddress!.assumingMemoryBound(to: Bytef.self), &decodedLength,
                    source.baseAddress!.assumingMemoryBound(to: Bytef.self), &sourceLength)
            }
            // zlib checks its header and Adler-32. Reject truncated, oversized,
            // concatenated or trailing data as well as any incomplete scanline.
            guard status == Z_OK, decodedLength == filteredCount,
                  sourceLength == compressed.count else { return false }

            for row in 0..<height {
                let start = row * filteredStride
                let filter = bytes[start]
                guard filter <= 4 else { return false }
                for column in 0..<rowBytes {
                    let index = start + 1 + column
                    let left = column >= components ? bytes[index - components] : 0
                    let above = row > 0 ? bytes[index - filteredStride] : 0
                    let upperLeft = row > 0 && column >= components
                        ? bytes[index - filteredStride - components] : 0
                    let predictor: UInt8
                    switch filter {
                    case 0: predictor = 0
                    case 1: predictor = left
                    case 2: predictor = above
                    case 3: predictor = UInt8((Int(left) + Int(above)) / 2)
                    default: predictor = paeth(left, above, upperLeft)
                    }
                    bytes[index] = bytes[index] &+ predictor
                }
            }

            if components == 4 {
                // Compact RGBA rows forward, removing filter bytes before alpha.
                for row in 0..<height {
                    for column in 0..<width {
                        let source = row * filteredStride + 1 + column * 4
                        let destination = (row * width + column) * 4
                        let red = bytes[source], green = bytes[source + 1], blue = bytes[source + 2]
                        bytes[destination] = red
                        bytes[destination + 1] = green
                        bytes[destination + 2] = blue
                        bytes[destination + 3] = 255
                    }
                }
            } else {
                // Expand RGB rows backward so writes cannot overwrite unread RGB.
                for row in stride(from: height - 1, through: 0, by: -1) {
                    for column in stride(from: width - 1, through: 0, by: -1) {
                        let source = row * filteredStride + 1 + column * 3
                        let destination = (row * width + column) * 4
                        let red = bytes[source], green = bytes[source + 1], blue = bytes[source + 2]
                        bytes[destination] = red
                        bytes[destination + 1] = green
                        bytes[destination + 2] = blue
                        bytes[destination + 3] = 255
                    }
                }
            }
            return true
        }
        guard decoded else { return nil }
        if output.count > outputCount { output.removeSubrange(outputCount..<output.count) }
        return Image(width: width, height: height, rgba: output)
    }

    private static func uint32(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }

    private static func paeth(_ left: UInt8, _ above: UInt8, _ upperLeft: UInt8) -> UInt8 {
        let a = Int(left), b = Int(above), c = Int(upperLeft)
        let prediction = a + b - c
        let da = abs(prediction - a), db = abs(prediction - b), dc = abs(prediction - c)
        if da <= db && da <= dc { return left }
        return db <= dc ? above : upperLeft
    }
}
