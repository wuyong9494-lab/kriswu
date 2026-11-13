import Foundation
import CryptoKit
import SceneKit
import MetalKit
import simd

/// Independently authenticated additions to the unchanged equipped models.
/// Original mask/MatCap composition and environment light values are retained;
/// the Unity per-vertex rim, fog and complete color pipeline are not reproduced.
@MainActor
final class DuelPresentationAssets {
    static let manifestName = "Fidelity_presentation.json"
    static let manifestSHA256 = "0ca27c39b7d65086dfd391b4716186b819c25e0933165b6df6ba1a4e09d63feb"
    static let voiceName = "liu_shadow_callout.wav"
    static let voiceBytes = 140_758
    static let voiceSHA256 = "a5e5d709d45f41325b33a13e858ffa3426b72471fb84f0f93e1d4c8a852c7c00"
    enum Failure: Error { case manifest, resource(String), metal }
    enum Environment: String { case palace, autumn }
    private struct File: Decodable { let name: String; let bytes: Int; let sha256: String }
    private struct Material: Decodable {
        let name: String
        let mask: String
        let metalPower: Float
        let maskColor: [Float]
        let skinOffset: [Float]
    }
    private struct Lighting: Decodable {
        let matcap: String
        let lightDirection: [Float]
        let ambient: [Float]
        let lightColor: [Float]
    }
    private struct Manifest: Decodable {
        let version: Int
        let files: [File]
        let materials: [Material]
        let environments: [String: Lighting]
    }
    private let manifest: Manifest
    private let textures: [String: MTLTexture]
    let voice: Data

    static func optional(directory: URL) throws -> DuelPresentationAssets? {
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(manifestName).path) else { return nil }
        return try DuelPresentationAssets(directory: directory)
    }
    /// Optional for existing installs; a present but corrupt asset is rejected.
    static func verifiedVoice(directory: URL) throws -> Data? {
        let url = directory.appendingPathComponent(voiceName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try read(url, bytes: voiceBytes, sha256: voiceSHA256)
    }
    private static func read(_ url: URL, bytes: Int, sha256: String) throws -> Data {
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard properties.isRegularFile == true, properties.isSymbolicLink != true,
              properties.fileSize == bytes, (1...3_000_000).contains(bytes) else { throw Failure.resource(url.lastPathComponent) }
        let data = try Data(contentsOf: url)
        guard data.count == bytes, digest(data) == sha256 else { throw Failure.resource(url.lastPathComponent) }
        return data
    }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    init(directory: URL) throws {
        let url = directory.appendingPathComponent(Self.manifestName)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard (1...20_000).contains(size) else { throw Failure.manifest }
        let data = try Self.read(url, bytes: size, sha256: Self.manifestSHA256)
        let definition = try JSONDecoder().decode(Manifest.self, from: data)
        let names: Set<String> = ["mat_arm__prc_02_base", "mat_arm__str_03_base",
                                  "mat_wpn__katana_01_01_base", "mat_wpn__hammers_01_01_base"]
        let allowed = Set((0..<4).map { "Fidelity_mask_\($0).png" } +
                          ["Fidelity_matcap_palace.png", "Fidelity_matcap_autumn.png", Self.voiceName])
        guard definition.version == 1, definition.files.count == 7,
              Set(definition.files.map(\.name)) == allowed,
              definition.materials.count == 4, Set(definition.materials.map(\.name)) == names,
              Set(definition.environments.keys) == Set(["palace", "autumn"]) else { throw Failure.manifest }
        func valid(_ rgb: [Float]) -> Bool { rgb.count == 3 && rgb.allSatisfy { $0.isFinite && abs($0) <= 10 } }
        guard definition.materials.allSatisfy({ allowed.contains($0.mask) && $0.metalPower.isFinite &&
            (0...4).contains($0.metalPower) && valid($0.maskColor) && valid($0.skinOffset) }),
              definition.environments.values.allSatisfy({ allowed.contains($0.matcap) &&
                  valid($0.ambient) && valid($0.lightColor) && valid($0.lightDirection) }) else { throw Failure.manifest }
        guard let device = MTLCreateSystemDefaultDevice() else { throw Failure.metal }
        let loader = MTKTextureLoader(device: device)
        var textures: [String: MTLTexture] = [:], voice = Data(), total = 0
        for file in definition.files {
            total += file.bytes
            guard total <= 3_000_000 else { throw Failure.manifest }
            let bytes = try Self.read(directory.appendingPathComponent(file.name), bytes: file.bytes, sha256: file.sha256)
            if file.name == Self.voiceName {
                guard bytes.count == Self.voiceBytes, Self.digest(bytes) == Self.voiceSHA256 else { throw Failure.resource(file.name) }
                voice = bytes
            } else {
                // Mask channels are data; neither masks nor the recovered
                // MatCap may receive an implicit PNG sRGB-to-linear conversion.
                let texture = try loader.newTexture(data: bytes, options: [.SRGB: false, .generateMipmaps: false])
                guard texture.width <= 2048, texture.height <= 2048 else { throw Failure.resource(file.name) }
                textures[file.name] = texture
            }
        }
        self.manifest = definition; self.textures = textures; self.voice = voice
    }

    @MainActor final class Binding {
        private let materials: [SCNMaterial]
        private let worldDirection: SIMD3<Float>
        init(materials: [SCNMaterial], worldDirection: SIMD3<Float>) {
            self.materials = materials; self.worldDirection = worldDirection
        }
        func update(viewTransform: simd_float4x4) {
            let direction = viewTransform * SIMD4(worldDirection, 0)
            let value = NSValue(scnVector3: SCNVector3(direction.x, direction.y, direction.z))
            for material in materials { material.setValue(value, forKey: "fidelityLightView") }
        }
        var materialCount: Int { materials.count }
    }
    func install(on materials: [SCNMaterial], environment: Environment) -> Binding {
        let light = manifest.environments[environment.rawValue]!
        func vector(_ v: [Float]) -> NSValue { NSValue(scnVector3: SCNVector3(v[0], v[1], v[2])) }
        func texture(_ name: String, repeatUV: Bool) -> SCNMaterialProperty {
            let property = SCNMaterialProperty(contents: textures[name]!)
            property.wrapS = repeatUV ? .repeat : .clamp
            property.wrapT = repeatUV ? .repeat : .clamp
            property.minificationFilter = .linear; property.magnificationFilter = .linear
            property.mipFilter = .none; property.maxAnisotropy = 1
            return property
        }
        var installed: [SCNMaterial] = []
        for material in materials {
            guard let source = manifest.materials.first(where: { $0.name == material.name }) else { continue }
            material.lightingModel = .constant
            material.setValue(texture(source.mask, repeatUV: true), forKey: "fidelityMask")
            material.setValue(texture(light.matcap, repeatUV: false), forKey: "fidelityMatcap")
            material.setValue(vector(source.maskColor), forKey: "fidelityPaint")
            material.setValue(vector(source.skinOffset), forKey: "fidelitySkinOffset")
            material.setValue(NSNumber(value: source.metalPower), forKey: "fidelityMetalPower")
            material.setValue(vector(light.ambient), forKey: "fidelityAmbient")
            material.setValue(vector(light.lightColor), forKey: "fidelityLightColor")
            material.setValue(vector(light.lightDirection), forKey: "fidelityLightView")
            var modifiers = material.shaderModifiers ?? [:]
            modifiers[.surface] = GLTFModel.combiningShaderModifiers(modifiers[.surface] ?? "", Self.surface)
            material.shaderModifiers = modifiers; installed.append(material)
        }
        return Binding(materials: installed, worldDirection: SIMD3(light.lightDirection[0], light.lightDirection[1], light.lightDirection[2]))
    }
    private static let surface = """
    uniform sampler2D fidelityMask;
    uniform sampler2D fidelityMatcap;
    uniform vec3 fidelityPaint;
    uniform vec3 fidelitySkinOffset;
    uniform float fidelityMetalPower;
    uniform vec3 fidelityAmbient;
    uniform vec3 fidelityLightColor;
    uniform vec3 fidelityLightView;
    #pragma body
    vec3 fidelityBase = _surface.diffuse.rgb;
    vec3 fidelityChannels = texture2D(fidelityMask, _surface.diffuseTexcoord).rgb;
    vec3 fidelityNormal = normalize(_surface.normal);
    vec2 fidelityUV = vec2(0.5 + 0.5 * fidelityNormal.x, 0.5 - 0.5 * fidelityNormal.y);
    vec3 fidelityMetal = fidelityBase * texture2D(fidelityMatcap, fidelityUV).rgb * fidelityMetalPower;
    vec3 fidelityColor = mix(fidelityBase, fidelityBase * fidelityPaint, fidelityChannels.r);
    fidelityColor += fidelityChannels.b * fidelitySkinOffset;
    fidelityColor = mix(fidelityColor, fidelityMetal, fidelityChannels.g);
    float fidelityLambert = max(0.0, dot(fidelityNormal, normalize(fidelityLightView)));
    _surface.diffuse.rgb = fidelityColor * (fidelityAmbient + fidelityLightColor * fidelityLambert);
    """
}
