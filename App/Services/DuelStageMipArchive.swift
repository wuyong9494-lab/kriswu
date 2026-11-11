import Foundation
import CryptoKit
import Darwin

/// Byte-preserving input boundary only. Nothing loads this archive from the app,
/// allocates a GPU texture, selects a color policy, or changes a stage material.
/// The exact sidecar declares all sampling contracts unresolved and activation
/// disabled. Passing these checks proves source bytes, never rendered parity.
enum DuelStageMipArchive {
    static let manifestBytes = 20_831
    static let manifestSHA256 = "2a8c665757f1cb34b15138cf5b4b83b2cfa85d1f80ab079f881b54a0a5bdbd8c"
    static let inventorySHA256 = "a64ae5001e87503f5ca9613fb42e7c9af4a65f5dbabbe973b350c010c40c644f"
    static let payloadBytes = 25_865_704
    static let maximumTextureBytes = 5_592_432

    enum Failure: Error, Equatable {
        case manifestIdentity, malformedManifest, unsupportedContract, invalidTexture(String)
        case directoryContents, nonRegularFile(String), byteCount(String), digest(String)
    }
    struct Contracts: Decodable {
        let color, alpha, hostOrientation: String
    }
    struct Stage: Decodable {
        let file: String
        let bytes: Int
        let sha256: String
    }
    struct Binding: Decodable, Hashable {
        let file, material, property: String
    }
    struct Level: Decodable {
        let level, width, height, offset, byteCount: Int
        let sha256: String
    }
    struct Source: Decodable {
        struct Stream: Decodable {
            let offset, size: Int
            let path: String
        }
        let bundle: String
        let bundleBytes: Int
        let bundleSha256, assetsfile, pathId, unityFallbackVersion: String
        let stream: Stream
    }
    struct Texture: Decodable {
        struct Vector: Decodable { let x, y: Float }
        struct Sampler: Decodable {
            let mAniso, mFilterMode, mWrapU, mWrapV, mWrapW: Int
            let mMipBias: Float
            // convertFromSnakeCase also lowercases internal capitals in each
            // later word of Unity's mixed-case keys (m_FilterMode, m_WrapU).
            private enum CodingKeys: String, CodingKey {
                case mAniso, mFilterMode = "mFiltermode", mMipBias = "mMipbias"
                case mWrapU = "mWrapu", mWrapV = "mWrapv", mWrapW = "mWrapw"
            }
        }
        let file, name, sha256, format: String
        let bytes, width, height, mipCount, formatEnum: Int
        let imageCount, textureDimension, serializedColorSpace: Int
        let source: Source
        let sourceSampler: Sampler
        let sourceScale, sourceOffset: Vector
        let levels: [Level]
        let bindings: [Binding]
    }
    struct Manifest: Decodable {
        let schema: Int
        let inventorySha256, activation: String
        let contracts: Contracts
        let stages: [Stage]
        let textures: [Texture]
    }
    struct Payload {
        let texture: Texture
        let bytes: Data
        fileprivate init(texture: Texture, bytes: Data) {
            self.texture = texture; self.bytes = bytes
        }
    }
    struct Verified {
        let manifest: Manifest
        let payloads: [Payload]
        fileprivate init(manifest: Manifest, payloads: [Payload]) {
            self.manifest = manifest; self.payloads = payloads
        }
    }

    /// Explicit, offline-only entry point. All files are bounded, regular and
    /// opened without following a final-component symlink. Keep the directory
    /// quiescent; this is not an adversarial multiwriter filesystem sandbox.
    /// It accepts exactly the flat sidecar, not an app bundle or a source ZIP.
    static func read(directory: URL) throws -> Verified {
        guard directory.isFileURL else { throw Failure.directoryContents }
        let attributes = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard attributes.isDirectory == true, attributes.isSymbolicLink != true else {
            throw Failure.directoryContents
        }
        let data = try readRegular(directory.appendingPathComponent("manifest.json"), count: manifestBytes)
        let manifest = try decodePinnedManifest(data)
        let expected = Set(manifest.textures.map(\.file) + ["manifest.json"])
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard entries.count == expected.count, Set(entries.map(\.lastPathComponent)) == expected else {
            throw Failure.directoryContents
        }
        return try readPinned(manifestData: data) { record in
            try readRegular(directory.appendingPathComponent(record.file), count: record.bytes)
        }
    }

    /// The resolver sees names only after the entire immutable manifest has
    /// passed its byte identity and structural checks. No partial result escapes.
    static func readPinned(manifestData: Data, readPayload: (Texture) throws -> Data) throws -> Verified {
        let manifest = try decodePinnedManifest(manifestData)
        var payloads: [Payload] = []
        for texture in manifest.textures {
            let bytes = Data(try readPayload(texture))
            try validatePayload(bytes, texture: texture)
            payloads.append(.init(texture: texture, bytes: bytes))
        }
        return .init(manifest: manifest, payloads: payloads)
    }

    static func decodePinnedManifest(_ data: Data) throws -> Manifest {
        guard data.count == manifestBytes, sha256(data) == manifestSHA256 else {
            throw Failure.manifestIdentity
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest: Manifest
        do { manifest = try decoder.decode(Manifest.self, from: data) }
        catch { throw Failure.malformedManifest }
        guard manifest.schema == 1, manifest.inventorySha256 == inventorySHA256,
              manifest.activation == "disabled", manifest.contracts.color == "unresolved",
              manifest.contracts.alpha == "unresolved", manifest.contracts.hostOrientation == "unresolved" else {
            throw Failure.unsupportedContract
        }
        let stages = manifest.stages
        guard stages.count == 2, Set(stages.map(\.file)) == ["SF3_Autumn_Lobby.glb", "SF3_Palace_Exterior.glb"],
              manifest.textures.count == 7, Set(manifest.textures.map(\.file)).count == 7 else {
            throw Failure.malformedManifest
        }
        var total = 0
        var bindings = Set<Binding>()
        for texture in manifest.textures {
            try validateTexture(texture)
            let (next, overflow) = total.addingReportingOverflow(texture.bytes)
            guard !overflow, next <= payloadBytes else { throw Failure.malformedManifest }
            total = next
            for binding in texture.bindings {
                guard stages.contains(where: { $0.file == binding.file }),
                      ["_MainTex", "_LightMapDefault"].contains(binding.property),
                      !binding.material.isEmpty, bindings.insert(binding).inserted else {
                    throw Failure.malformedManifest
                }
            }
        }
        guard total == payloadBytes, bindings.count == 31 else { throw Failure.malformedManifest }
        return manifest
    }

    /// Separate bounded range checks permit UNRUN synthetic malformed-input
    /// regression cases without weakening the production manifest digest pin.
    static func validateTexture(_ texture: Texture) throws {
        func reject() -> Failure { .invalidTexture(texture.name) }
        guard texture.width > 0, texture.width <= 2048, texture.height > 0, texture.height <= 2048,
              texture.width.nonzeroBitCount == 1, texture.height.nonzeroBitCount == 1,
              texture.mipCount > 1, texture.mipCount <= 12,
              texture.levels.count == texture.mipCount, texture.bytes > 0,
              texture.bytes <= maximumTextureBytes, validDigest(texture.sha256),
              texture.file == texture.sha256 + ".mips",
              texture.imageCount == 1, texture.textureDimension == 2,
              texture.serializedColorSpace == 1, Int64(texture.source.pathId) != nil,
              texture.sourceSampler.mAniso == 1, texture.sourceSampler.mFilterMode == 1,
              texture.sourceSampler.mWrapU == 0, texture.sourceSampler.mWrapV == 0,
              texture.sourceSampler.mWrapW == 0, texture.sourceSampler.mMipBias == 0,
              texture.sourceScale.x == 1, texture.sourceScale.y == 1,
              texture.sourceOffset.x == 0, texture.sourceOffset.y == 0,
              texture.source.stream.size == texture.bytes, texture.source.stream.offset >= 0,
              texture.source.bundleBytes > 0, validDigest(texture.source.bundleSha256) else { throw reject() }
        let blockBytes: Int
        switch (texture.format, texture.formatEnum) {
        case ("ETC2_RGB", 45): blockBytes = 8
        case ("ETC2_RGBA8", 47): blockBytes = 16
        default: throw reject()
        }
        var offset = 0, width = texture.width, height = texture.height
        for (index, level) in texture.levels.enumerated() {
            // Dimension bounds above make block arithmetic bounded. Tiny mip
            // levels still occupy a complete 4x4 compression block.
            let count = ((width + 3) / 4) * ((height + 3) / 4) * blockBytes
            let (end, overflow) = offset.addingReportingOverflow(count)
            guard !overflow, end <= texture.bytes, level.level == index,
                  level.width == width, level.height == height, level.offset == offset,
                  level.byteCount == count, validDigest(level.sha256) else { throw reject() }
            // Only the last level may be 1x1: no missing tail or repeated tail.
            if width == 1 && height == 1 && index != texture.levels.count - 1 { throw reject() }
            offset = end; width = max(1, width / 2); height = max(1, height / 2)
        }
        guard offset == texture.bytes, texture.levels.last?.width == 1,
              texture.levels.last?.height == 1 else { throw reject() }
    }

    static func validatePayload(_ data: Data, texture: Texture) throws {
        try validateTexture(texture)
        guard data.count == texture.bytes else { throw Failure.byteCount(texture.name) }
        guard sha256(data) == texture.sha256 else { throw Failure.digest(texture.name) }
        let bytes = Data(data)
        for level in texture.levels {
            let end = level.offset + level.byteCount // Checked above before slicing.
            guard sha256(bytes.subdata(in: level.offset..<end)) == level.sha256 else {
                throw Failure.digest("\(texture.name):mip\(level.level)")
            }
        }
    }

    private static func validDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func readRegular(_ url: URL, count: Int) throws -> Data {
        guard count > 0, count <= maximumTextureBytes else { throw Failure.byteCount(url.lastPathComponent) }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw Failure.nonRegularFile(url.lastPathComponent) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw Failure.nonRegularFile(url.lastPathComponent)
        }
        guard info.st_size == off_t(count) else { throw Failure.byteCount(url.lastPathComponent) }
        var bytes = Data()
        while bytes.count <= count {
            let next = try file.read(upToCount: min(65_536, count + 1 - bytes.count)) ?? Data()
            if next.isEmpty { break }
            bytes.append(next)
        }
        guard bytes.count == count else { throw Failure.byteCount(url.lastPathComponent) }
        return bytes
    }
}
