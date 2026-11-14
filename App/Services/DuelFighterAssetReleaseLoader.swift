import Foundation
import CoreFoundation

/// A directory cannot authorize its own contents. Only an independently pinned
/// manifest from the signed build may enable the target catalog and its bindings.
@MainActor
struct DuelFighterAssetReleaseLoader {
    enum Failure: Error, Equatable { case missingPin, invalidPin, missingRelease, integrity(String) }
    let definition: DuelFighterAssetRelease
    let catalog: DuelWeaponCatalog
    let files: [DuelNetworkContentRecord]

    static func optional(directory: URL, bundle: Bundle = .main) throws -> Self? {
        let pin = bundle.object(forInfoDictionaryKey: DuelFighterAssetRelease.infoKey) as? String
        let present = FileManager.default.fileExists(atPath: directory.appendingPathComponent(DuelFighterAssetRelease.fileName).path)
        if pin == nil || pin == "" {
            guard !present else { throw Failure.missingPin }
            return nil
        }
        guard let pin, DuelFighterAssetRelease.validDigest(pin) else { throw Failure.invalidPin }
        guard present else { throw Failure.missingRelease }
        return try Self(directory: directory, expectedSHA256: pin)
    }

    /// Explicit pin seam for native tests; production passes the signed Info.plist.
    init(directory: URL, expectedSHA256: String) throws {
        guard DuelFighterAssetRelease.validDigest(expectedSHA256) else { throw Failure.invalidPin }
        let releaseData = try Self.read(directory: directory, name: DuelFighterAssetRelease.fileName,
                                       maximum: DuelFighterAssetRelease.maximumBytes, hash: expectedSHA256)
        let value = try JSONDecoder().decode(DuelFighterAssetRelease.self, from: releaseData)
        try value.catalog.validate(maximum: 32_000_000)
        guard value.catalog.name == "SF3_DistinctFighters.json" else { throw Failure.integrity("catalog") }
        let catalogData = try Self.read(directory: directory, name: value.catalog.name,
                                       maximum: 32_000_000, bytes: value.catalog.bytes, hash: value.catalog.sha256)
        let catalog = try JSONDecoder().decode(DuelWeaponCatalog.self, from: catalogData)
        try value.validate(catalog: catalog)
        for file in [value.sourceTrails] + [value.panguAudio, value.triadAudio, value.triadSummons, value.triadEffects].compactMap({ $0 }) {
            _ = try Self.read(directory: directory, name: file.name,
                              maximum: file.bytes, bytes: file.bytes, hash: file.sha256)
        }
        definition = value; self.catalog = catalog
        files = [.init(path: "asset-release/" + DuelFighterAssetRelease.fileName,
                       bytes: releaseData.count, sha256: expectedSHA256),
                 .init(path: "catalog/" + value.catalog.name, bytes: catalogData.count, sha256: value.catalog.sha256)]
    }

    /// A character's catalog digest covers only this container. Target releases
    /// therefore cannot reopen sidecar buffers or textures, even when those
    /// sidecars happen to be installed beside a correctly pinned GLB. The general
    /// renderer still supports external resources for the existing scene packs.
    /// This checks the container and its byte/image references; the character
    /// loader separately validates the decoded rig, materials and motion clips.
    static func validateSelfContainedGLB(_ data: Data) throws {
        let failure = Failure.integrity("character-glb")
        guard (20...128_000_000).contains(data.count) else { throw failure }
        func word(_ offset: Int) -> UInt32 {
            let start = data.startIndex + offset
            return UInt32(data[start]) | UInt32(data[start + 1]) << 8 |
                UInt32(data[start + 2]) << 16 | UInt32(data[start + 3]) << 24
        }
        guard word(0) == 0x46546C67, word(4) == 2,
              Int(word(8)) == data.count else { throw failure }
        var offset = 12, chunkIndex = 0
        var jsonData: Data?, binaryLength: Int?
        while offset < data.count {
            guard data.count - offset >= 8 else { throw failure }
            let length = Int(word(offset)), type = word(offset + 4)
            guard length.isMultiple(of: 4), length <= data.count - offset - 8 else { throw failure }
            let start = offset + 8, end = start + length
            if chunkIndex == 0 && type != 0x4E4F534A { throw failure }
            switch type {
            case 0x4E4F534A:
                guard chunkIndex == 0, jsonData == nil, length > 0 else { throw failure }
                jsonData = data.subdata(in: (data.startIndex + start)..<(data.startIndex + end))
            case 0x004E4942:
                guard chunkIndex == 1, binaryLength == nil else { throw failure }
                binaryLength = length
            default:
                // GLB permits opaque extra chunks. Their bytes stay inside the
                // pinned container and GLTFModel does not interpret them.
                break
            }
            offset = end; chunkIndex += 1
        }
        guard let jsonData,
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let asset = json["asset"] as? [String: Any], asset["version"] as? String == "2.0",
              asset["minVersion"] == nil || asset["minVersion"] as? String == "2.0" else { throw failure }

        func objects(_ name: String) throws -> [[String: Any]] {
            guard let value = json[name] else { return [] }
            guard let result = value as? [[String: Any]] else { throw failure }
            return result
        }
        func names(_ name: String) throws -> [String] {
            guard let value = json[name] else { return [] }
            guard let result = value as? [String], Set(result).count == result.count else { throw failure }
            return result
        }
        // JSON booleans bridge to NSNumber too; they must not become indices.
        // All relevant indices and byte counts fit inside this bounded file.
        func integer(_ value: Any?) -> Int? {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let value = number.doubleValue
            guard value.isFinite, value >= 0, value <= Double(data.count), value.rounded(.towardZero) == value else { return nil }
            return Int(value)
        }
        let required = Set(try names("extensionsRequired")), used = Set(try names("extensionsUsed"))
        // This is the only required glTF extension implemented by GLTFModel.
        guard required.isSubset(of: used), required.isSubset(of: ["KHR_materials_unlit"]) else { throw failure }

        let buffers = try objects("buffers"), views = try objects("bufferViews"), images = try objects("images")
        // Reject the key itself, including null, malformed and data: values.
        // The current renderer treats every string URI as a filesystem path.
        guard buffers.allSatisfy({ !$0.keys.contains("uri") }),
              images.allSatisfy({ !$0.keys.contains("uri") }), buffers.count <= 1 else { throw failure }
        let bufferLength: Int
        if let buffer = buffers.first {
            guard let length = integer(buffer["byteLength"]), length > 0,
                  let binaryLength, length <= binaryLength else { throw failure }
            bufferLength = length
        } else {
            guard binaryLength == nil else { throw failure }
            bufferLength = 0
        }
        for view in views {
            let start: Int? = view["byteOffset"] == nil ? 0 : integer(view["byteOffset"])
            guard buffers.count == 1, integer(view["buffer"]) == 0,
                  let start, let length = integer(view["byteLength"]), length > 0,
                  start <= bufferLength, length <= bufferLength - start else { throw failure }
        }
        for image in images {
            guard let view = integer(image["bufferView"]), views.indices.contains(view),
                  let mime = image["mimeType"] as? String,
                  mime == "image/png" || mime == "image/jpeg" else { throw failure }
        }
        // A texture's image reference is part of the same container contract;
        // unsupported texture extensions cannot supply an absent source.
        for texture in try objects("textures") {
            guard let source = integer(texture["source"]), images.indices.contains(source) else { throw failure }
        }
    }

    static func read(directory: URL, name: String, maximum: Int, bytes: Int? = nil, hash: String) throws -> Data {
        guard DuelFighterAssetRelease.File.validName(name), DuelFighterAssetRelease.validDigest(hash),
              maximum > 0 else { throw Failure.integrity(name) }
        let url = directory.appendingPathComponent(name)
        let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
              let size = attributes.fileSize, (1...maximum).contains(size),
              bytes.map({ $0 == size }) ?? true else { throw Failure.integrity(name) }
        let data = try Data(contentsOf: url)
        guard data.count == size, DuelWeaponAssets.digest(data) == hash else { throw Failure.integrity(name) }
        return data
    }
}
