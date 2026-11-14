import Foundation
import zlib

/// Decompresses one authenticated gzip member with a fixed output ceiling.
/// zlib verifies the gzip header, CRC and uncompressed length; extra members
/// and trailing bytes are rejected rather than silently changing the manifest.
enum DuelBoundedGzip {
    enum Failure: Error { case input, limit, corrupt }
    static func decode(_ data: Data, maximum: Int) throws -> Data {
        guard (1...256_000_000).contains(maximum), (18...32_000_000).contains(data.count),
              data.starts(with: [0x1f, 0x8b, 0x08]) else { throw Failure.input }
        return try data.withUnsafeBytes { raw in
            var stream = z_stream()
            guard inflateInit2_(&stream, MAX_WBITS + 16, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw Failure.corrupt
            }
            defer { inflateEnd(&stream) }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: raw.bindMemory(to: Bytef.self).baseAddress!)
            stream.avail_in = uInt(data.count)
            var output = Data(), chunk = [UInt8](repeating: 0, count: 65_536)
            while true {
                let before = stream.avail_in
                let status = chunk.withUnsafeMutableBytes { destination -> Int32 in
                    stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress!
                    stream.avail_out = uInt(destination.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let produced = chunk.count - Int(stream.avail_out)
                guard produced <= maximum - output.count else { throw Failure.limit }
                output.append(contentsOf: chunk.prefix(produced))
                if status == Z_STREAM_END {
                    guard stream.avail_in == 0, !output.isEmpty else { throw Failure.corrupt }
                    return output
                }
                guard status == Z_OK, produced > 0 || stream.avail_in < before else { throw Failure.corrupt }
            }
        }
    }
}
