import CryptoKit
import Foundation

enum ArenaResourcePackArchive {
    static let magic = Data("KRISARENA1\n".utf8)
    struct Pointer: Codable { let folder: String }
    struct Installed: Sendable { let root: URL; let manifest: ArenaResourcePackManifest }

    static func readManifest(from source: URL) throws -> ArenaResourcePackManifest {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard try read(input, count: magic.count) == magic else { throw invalid("资源包标识") }
        let bytes = try read(input, count: 4)
        let length = bytes.enumerated().reduce(0) { $0 + (Int($1.element) << (8 * $1.offset)) }
        guard length > 0, length <= ArenaResourcePackManifest.maximumHeaderBytes else { throw invalid("资源清单大小") }
        let value = try JSONDecoder().decode(ArenaResourcePackManifest.self, from: read(input, count: length))
        try value.validate()
        let expected = magic.count + 4 + length + value.files.reduce(0) { $0 + $1.bytes }
        guard try source.resourceValues(forKeys: [.fileSizeKey]).fileSize == expected else { throw invalid("资源包长度与清单不符") }
        return value
    }

    static func install(from source: URL, directory: URL,
                        progress: @escaping @Sendable (Double) -> Void) throws -> Installed {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let folder = UUID().uuidString
        let staging = directory.appendingPathComponent(folder, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        var committed = false
        defer { if !committed { try? fm.removeItem(at: staging) } }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard try read(input, count: magic.count) == magic else { throw invalid("请选择 .arenapack 资源包") }
        let lengthData = try read(input, count: 4)
        let length = lengthData.enumerated().reduce(0) { $0 + (Int($1.element) << (8 * $1.offset)) }
        guard length > 0, length <= ArenaResourcePackManifest.maximumHeaderBytes else { throw invalid("资源清单大小") }
        let raw = try read(input, count: length)
        let manifest = try JSONDecoder().decode(ArenaResourcePackManifest.self, from: raw)
        try manifest.validate()
        let expectedBytes = manifest.files.reduce(0) { $0 + $1.bytes }
        let sourceBytes = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard sourceBytes == magic.count + 4 + length + expectedBytes else { throw invalid("资源包长度与清单不符") }
        var copied = 0
        var reported = -1
        for item in manifest.files {
            let target = staging.appendingPathComponent(item.path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: target.path, contents: nil) else { throw invalid("无法创建资源文件") }
            let output = try FileHandle(forWritingTo: target)
            do {
                var remaining = item.bytes
                var digest = SHA256()
                while remaining > 0 {
                    let bytes = try read(input, count: min(remaining, 1_048_576))
                    try output.write(contentsOf: bytes)
                    digest.update(data: bytes)
                    remaining -= bytes.count
                    copied += bytes.count
                    let percent = copied * 100 / max(expectedBytes, 1)
                    if percent != reported { reported = percent; progress(Double(copied) / Double(expectedBytes)) }
                }
                try output.close()
                let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
                guard hash == item.sha256 else { throw invalid("文件校验未通过：\(item.path)") }
                if item.kind == .model { try verifyEmbeddedGLB(target, bytes: item.bytes) }
            } catch {
                try? output.close()
                throw error
            }
        }
        guard try input.read(upToCount: 1)?.isEmpty != false else { throw invalid("资源包尾部有额外数据") }
        try raw.write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = staging
        try excluded.setResourceValues(values)
        // Replacing this tiny pointer is the only publication step; failures above
        // leave the previous pack, its selection and all gameplay saves untouched.
        let pointer = try JSONEncoder().encode(Pointer(folder: folder))
        try pointer.write(to: directory.appendingPathComponent("active.json"), options: .atomic)
        committed = true
        return Installed(root: staging, manifest: manifest)
    }

    private static func read(_ handle: FileHandle, count: Int) throws -> Data {
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            guard let part = try handle.read(upToCount: count - result.count), !part.isEmpty else { throw invalid("资源包不完整") }
            result.append(part)
        }
        return result
    }

    /// Imported GLBs are self-contained. The renderer must never follow an
    /// external URI or resolve paths outside the validated installation.
    private static func verifyEmbeddedGLB(_ url: URL, bytes: Int) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        func word(_ data: Data, _ offset: Int) -> Int {
            (0..<4).reduce(0) { $0 + (Int(data[offset + $1]) << (8 * $1)) }
        }
        let header = try read(handle, count: 12)
        guard header.prefix(4) == Data("glTF".utf8), word(header, 4) == 2,
              word(header, 8) == bytes else { throw invalid("模型格式") }
        var offset = 12
        var object: [String: Any]?
        var binaryLength: Int?
        while offset < bytes {
            guard bytes - offset >= 8 else { throw invalid("模型块长度") }
            let chunk = try read(handle, count: 8)
            let length = word(chunk, 0), type = word(chunk, 4)
            guard length > 0, length.isMultiple(of: 4), length <= bytes - offset - 8 else { throw invalid("模型块长度") }
            switch type {
            case 0x4E4F534A:
                // The renderer reads chunks too. Reject a second JSON chunk so
                // it cannot consume a different document than the one verified.
                guard offset == 12, object == nil, length <= 8 * 1024 * 1024 else { throw invalid("模型包含重复或错序的清单") }
                object = try JSONSerialization.jsonObject(with: read(handle, count: length)) as? [String: Any]
                guard object != nil else { throw invalid("模型清单") }
            case 0x004E4942:
                guard object != nil, binaryLength == nil else { throw invalid("模型包含重复或错序的数据") }
                binaryLength = length
                try handle.seek(toOffset: UInt64(offset + 8 + length))
            default: throw invalid("不支持的模型数据块")
            }
            offset += 8 + length
        }
        guard let object, let binaryLength,
              let buffers = object["buffers"] as? [[String: Any]], buffers.count == 1,
              buffers.allSatisfy({ $0["uri"] == nil }),
              (object["images"] as? [[String: Any]] ?? []).allSatisfy({ $0["uri"] == nil }) else { throw invalid("模型必须内嵌贴图和数据") }
        guard let expected = buffers[0]["byteLength"] as? Int, expected > 0,
              expected <= binaryLength, binaryLength - expected <= 3 else { throw invalid("模型内嵌数据长度") }
    }

    private static func invalid(_ message: String) -> Error { ArenaResourcePackManifest.ValidationError.invalid(message) }
}
