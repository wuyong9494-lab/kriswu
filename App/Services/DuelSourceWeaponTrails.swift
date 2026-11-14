import Foundation
import CryptoKit
import SceneKit
import UIKit
import simd

/// Verified trail skins on the authenticated character skeleton. Legacy packs
/// retain their original adapter; target packs supply phase windows, textures
/// and supported material state explicitly. A present invalid pack fails before
/// any character is made and cannot become an older weapon's trail.
@MainActor
final class DuelSourceWeaponTrails {
    static let fileName = "SF3_SourceTrails.json"
    static let sha256 = "6efadacf6a9e18a270a609132f622fb3ef569a505e46c81ff17c4b7ee386d0cc"
    enum Failure: Error { case invalid, incomplete }
    /// Version two makes each target's texture and raster state explicit. These
    /// are source bindings, not inferred Pangu material defaults.
    struct Texture: Decodable {
        let name: String
        let bytes: Int
        let sha256: String
        let width: Int
        let height: Int
    }
    struct Material: Decodable {
        let shader: String
        let alphaChannel: String
        /// Original H17 uses coverage only for alpha with SrcAlpha blending.
        /// Nil preserves the legacy pack's premultiplied-color adapter.
        let multiplyColorByCoverage: Bool?
        let colorTexture: Texture?
        let blend: String
        let doubleSided: Bool
        let cullMode: String
        let readsDepth: Bool
        let writesDepth: Bool
        let wrapS: Int
        let wrapT: Int
        let filter: String
        let tint: [Float]
    }
    struct Mesh: Decodable {
        let name: String
        let side: String
        let bones: [String]
        let sourceBoneIDs: [Int]
        let positions: [Float]
        let normals: [Float]
        let uv: [Float]
        let colorUV: [Float]?
        let weights: [Float]
        let joints: [UInt16]
        let indices: [UInt16]
        let inverseBinds: [[Float]]
        let material: Material?
    }
    struct Profile: Decodable {
        let id: String
        let characterSHA256: String
        let meshes: [Mesh]
        let clips: [String]
        let alpha: Texture?
        let skeletonNode: String?
        let attachmentNode: String?
        let clipWindows: [ClipWindow]?
    }
    struct ClipWindow: Decodable {
        let clip: String
        /// Inclusive normalized source phase, independent of combat speed and
        /// of preview/source FPS. Adjacent windows may not share an endpoint.
        let startPhaseBps: Int
        let endPhaseBps: Int
    }
    private struct Document: Decodable {
        let version: Int
        let profiles: [Profile]
        let alphaTexture: String
        let alphaSHA256: String
    }
    private struct TargetDocument: Decodable {
        let version: Int
        let profiles: [Profile]
        let legacy: Legacy?
        struct Legacy: Decodable {
            let manifest: DuelFighterAssetRelease.File
            let profileIDs: [String]
            /// A reviewed animation append can change the GLB digest while
            /// retaining every original mesh, skin, material and trail bone.
            /// Both identities must be named by the authenticated release;
            /// a mismatching legacy digest alone never permits rebinding.
            let rebindings: [Rebinding]?
        }
        struct Rebinding: Decodable {
            let id: String
            let mode: String
            let fromSHA256: String
            let toSHA256: String
        }
    }
    let profiles: [Profile]
    /// Basenames relative to this manifest's directory. Callers give these a
    /// logical network namespace; none of these records contains private bytes.
    let verifiedFiles: [DuelNetworkContentRecord]
    private let alphaByProfile: [String: UIImage]
    private var colorTextures: [String: UIImage] = [:]

    static func optional(directory: URL) throws -> DuelSourceWeaponTrails? {
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try DuelSourceWeaponTrails(url: url)
    }
    init(url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (1...100_000).contains(values.fileSize ?? 0) else { throw Failure.invalid }
        let data = try Data(contentsOf: url)
        guard DuelWeaponAssets.digest(data) == Self.sha256 else { throw Failure.invalid }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.version == 1, document.profiles.count == 2,
              Set(document.profiles.map(\.id)) == Set(["sun_katana", "liu_hammers"]),
              document.alphaTexture == "SF3WE_1394430195881985131.png",
              document.alphaSHA256 == "c8a01bc4e4574aff6e7dbf3615fbc673301364f776c1bd8483f509025f8fc386" else { throw Failure.invalid }
        for profile in document.profiles {
            guard profile.meshes.count == 2, Set(profile.meshes.map(\.side)) == Set(["left", "right"]),
                  !profile.clips.isEmpty, Set(profile.clips).count == profile.clips.count else { throw Failure.invalid }
            for mesh in profile.meshes {
                let count = mesh.positions.count / 3
                guard count == (profile.id == "sun_katana" ? 12 : 32), mesh.positions.count == count * 3,
                      mesh.normals.count == count * 3, mesh.uv.count == count * 2,
                      mesh.weights.count == count * 4, mesh.joints.count == count * 4,
                      mesh.indices.count == (profile.id == "sun_katana" ? 36 : 72),
                      mesh.indices.allSatisfy({ Int($0) < count }), mesh.joints.allSatisfy({ $0 < 4 }),
                      mesh.bones.count == 4, Set(mesh.bones).count == 4,
                      mesh.sourceBoneIDs == Array((mesh.side == "left" ? 260 : 264)...(mesh.side == "left" ? 263 : 267)),
                      mesh.inverseBinds.count == 4,
                      mesh.inverseBinds.allSatisfy({ $0.count == 16 && $0.allSatisfy(\.isFinite) }),
                      [mesh.positions, mesh.normals, mesh.uv, mesh.weights].allSatisfy({ $0.allSatisfy(\.isFinite) }) else { throw Failure.invalid }
                for vertex in 0..<count {
                    let values = mesh.weights[(vertex * 4)..<(vertex * 4 + 4)]
                    guard values.allSatisfy({ $0 >= 0 && $0 <= 1 }), abs(values.reduce(0, +) - 1) < 0.00001 else { throw Failure.invalid }
                }
            }
        }
        let textureURL = url.deletingLastPathComponent().appendingPathComponent(document.alphaTexture)
        let textureValues = try textureURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard textureValues.isRegularFile == true, textureValues.isSymbolicLink != true,
              textureValues.fileSize == 5290 else { throw Failure.invalid }
        let bytes = try Data(contentsOf: textureURL)
        guard DuelWeaponAssets.digest(bytes) == document.alphaSHA256,
              let alpha = UIImage(data: bytes), alpha.size == CGSize(width: 256, height: 256) else { throw Failure.invalid }
        self.profiles = document.profiles
        alphaByProfile = Dictionary(uniqueKeysWithValues: document.profiles.map { ($0.id, alpha) })
        verifiedFiles = [
            .init(path: url.lastPathComponent, bytes: data.count, sha256: Self.sha256),
            .init(path: document.alphaTexture, bytes: bytes.count, sha256: document.alphaSHA256)
        ]
    }

    /// The expected digest must come from the authenticated fighter release,
    /// never from the target document being read. Legacy manifests retain their
    /// exact pin and shape in init(url:); this path never reinterprets them.
    init(url: URL, expectedSHA256: String, catalog: DuelWeaponCatalog) throws {
        guard DuelNetworkContentRecord.validDigest(expectedSHA256),
              catalog.profiles.count == 2,
              catalog.profiles.contains(where: { $0.isPangu || $0.isTriad }) else { throw Failure.invalid }
        let data = try Self.read(url, maximum: 2_000_000, sha256: expectedSHA256)
        let document = try JSONDecoder().decode(TargetDocument.self, from: data)
        guard (document.version == 2 && document.legacy == nil) ||
              (document.version == 3 && document.legacy != nil),
              !document.profiles.isEmpty,
              Set(document.profiles.map(\.id)).count == document.profiles.count else { throw Failure.invalid }
        var inheritedProfiles: [Profile] = []
        var textures: [String: UIImage] = [:]
        var colors: [String: UIImage] = [:]
        var records = [DuelNetworkContentRecord(path: url.lastPathComponent, bytes: data.count, sha256: expectedSHA256)]
        var textureRecords: [String: DuelNetworkContentRecord] = [:]
        var totalTextureBytes = 0
        if let reference = document.legacy {
            // A mixed release may retain an explicitly named, byte-pinned old
            // character. Its version-one manifest is validated by the original
            // loader; none of its material defaults become target defaults.
            guard reference.manifest.name == Self.fileName, reference.manifest.bytes == 20_724,
                  reference.manifest.sha256 == Self.sha256,
                  !reference.profileIDs.isEmpty,
                  Set(reference.profileIDs).count == reference.profileIDs.count,
                  Set(reference.profileIDs).isDisjoint(with: Set(document.profiles.map(\.id))) else { throw Failure.invalid }
            let old = try Self(url: url.deletingLastPathComponent().appendingPathComponent(Self.fileName))
            let rebindings = reference.rebindings ?? []
            guard Set(rebindings.map(\.id)).count == rebindings.count,
                  Set(rebindings.map(\.id)).isSubset(of: Set(reference.profileIDs)),
                  rebindings.allSatisfy({ $0.mode == "appendSourceAnimations" &&
                      $0.fromSHA256 != $0.toSHA256 && DuelNetworkContentRecord.validDigest($0.fromSHA256) &&
                      DuelNetworkContentRecord.validDigest($0.toSHA256) }) else { throw Failure.invalid }
            for id in reference.profileIDs {
                guard let source = old.profiles.first(where: { $0.id == id }),
                      let target = catalog.profiles.first(where: { $0.id == id }),
                      !target.isPangu, !target.isTriad,
                      source.clips.allSatisfy({ target.clip(named: $0) != nil }) else { throw Failure.invalid }
                if source.characterSHA256 == target.sha256 {
                    guard !rebindings.contains(where: { $0.id == id }) else { throw Failure.invalid }
                    inheritedProfiles.append(source)
                } else {
                    guard let binding = rebindings.first(where: { $0.id == id }),
                          binding.fromSHA256 == source.characterSHA256,
                          binding.toSHA256 == target.sha256 else { throw Failure.invalid }
                    inheritedProfiles.append(.init(id: source.id, characterSHA256: target.sha256,
                        meshes: source.meshes, clips: source.clips, alpha: source.alpha,
                        skeletonNode: source.skeletonNode, attachmentNode: source.attachmentNode,
                        clipWindows: source.clipWindows))
                }
                textures[id] = old.alphaByProfile[id]
            }
            records += old.verifiedFiles
            for record in old.verifiedFiles where record.path.hasSuffix(".png") {
                textureRecords[record.path] = record; totalTextureBytes += record.bytes
            }
        }
        guard document.profiles.count + inheritedProfiles.count == catalog.profiles.count,
              Set((document.profiles + inheritedProfiles).map(\.id)) == Set(catalog.profiles.map(\.id)) else { throw Failure.invalid }
        for source in document.profiles {
            guard let profile = catalog.profiles.first(where: { $0.id == source.id }),
                  DuelNetworkContentRecord.validDigest(source.characterSHA256),
                  source.characterSHA256 == profile.sha256,
                  let skeleton = source.skeletonNode, Self.validNode(skeleton),
                  let attachment = source.attachmentNode, Self.validNode(attachment),
                  let texture = source.alpha,
                  Self.validFile(texture.name, suffix: ".png"),
                  (texture.name.hasPrefix("SF3PG_") || texture.name.hasPrefix("SF3WE_")),
                  (1...4_000_000).contains(texture.bytes),
                  (1...2048).contains(texture.width), (1...2048).contains(texture.height),
                  !source.clips.isEmpty, Set(source.clips).count == source.clips.count,
                  source.clips.allSatisfy({ profile.clip(named: $0) != nil }),
                  let windows = source.clipWindows, !windows.isEmpty, windows.count <= 512,
                  Set(windows.map(\.clip)) == Set(source.clips),
                  windows.allSatisfy({ (0...10_000).contains($0.startPhaseBps) &&
                      ($0.startPhaseBps...10_000).contains($0.endPhaseBps) }),
                  (1...16).contains(source.meshes.count),
                  Set(source.meshes.map(\.name)).count == source.meshes.count,
                  Set(profile.activeWeaponSides).isSubset(of: Set(source.meshes.map(\.side))) else { throw Failure.invalid }
            for mesh in source.meshes { try Self.validateTargetMesh(mesh) }
            for clip in source.clips {
                let ordered = windows.filter { $0.clip == clip }.sorted { $0.startPhaseBps < $1.startPhaseBps }
                for pair in zip(ordered, ordered.dropFirst()) {
                    guard pair.0.endPhaseBps < pair.1.startPhaseBps else { throw Failure.invalid }
                }
            }
            let record = DuelNetworkContentRecord(path: texture.name, bytes: texture.bytes, sha256: texture.sha256)
            if let existing = textureRecords[texture.name] {
                guard existing == record else { throw Failure.invalid }
            } else {
                totalTextureBytes += texture.bytes
                guard totalTextureBytes <= 8_000_000 else { throw Failure.invalid }
                textureRecords[texture.name] = record
                records.append(record)
            }
            let bytes = try Self.read(url.deletingLastPathComponent().appendingPathComponent(texture.name),
                                      maximum: 4_000_000, bytes: texture.bytes, sha256: texture.sha256)
            guard let image = UIImage(data: bytes),
                  let decoded = image.cgImage,
                  decoded.width == texture.width, decoded.height == texture.height else { throw Failure.invalid }
            textures[source.id] = image
            for mesh in source.meshes {
                guard let color = mesh.material?.colorTexture else { continue }
                guard Self.validFile(color.name, suffix: ".png"), color.name.hasPrefix("SF3WE_"),
                      (1...4_000_000).contains(color.bytes), (1...2048).contains(color.width),
                      (1...2048).contains(color.height) else { throw Failure.invalid }
                let record = DuelNetworkContentRecord(path: color.name, bytes: color.bytes, sha256: color.sha256)
                if let existing = textureRecords[color.name] {
                    guard existing == record else { throw Failure.invalid }
                } else {
                    totalTextureBytes += color.bytes
                    guard totalTextureBytes <= 8_000_000 else { throw Failure.invalid }
                    textureRecords[color.name] = record; records.append(record)
                }
                let bytes = try Self.read(url.deletingLastPathComponent().appendingPathComponent(color.name),
                    maximum: 4_000_000, bytes: color.bytes, sha256: color.sha256)
                guard let image = UIImage(data: bytes), let decoded = image.cgImage,
                      decoded.width == color.width, decoded.height == color.height else { throw Failure.invalid }
                colors[color.name] = image
            }
        }
        profiles = document.profiles + inheritedProfiles; alphaByProfile = textures; colorTextures = colors
        verifiedFiles = records.sorted { $0.path < $1.path }
    }

    private static func validFile(_ name: String, suffix: String) -> Bool {
        name.hasSuffix(suffix) && name.utf8.count <= 160 &&
            name.range(of: "^[A-Za-z0-9_-]+\\.[A-Za-z0-9]+$", options: .regularExpression) != nil
    }
    private static func validNode(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 256 && !name.contains("\0")
    }
    private static func read(_ url: URL, maximum: Int, bytes: Int? = nil, sha256: String) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let count = values.fileSize, (1...maximum).contains(count),
              bytes.map({ $0 == count }) ?? true,
              DuelNetworkContentRecord.validDigest(sha256) else { throw Failure.invalid }
        let data = try Data(contentsOf: url)
        guard data.count == count, DuelWeaponAssets.digest(data) == sha256 else { throw Failure.invalid }
        return data
    }
    private static func validateTargetMesh(_ mesh: Mesh) throws {
        let count = mesh.positions.count / 3, boneCount = mesh.bones.count
        guard Self.validNode(mesh.name), ["left", "right"].contains(mesh.side),
              (3...32_768).contains(count), mesh.positions.count == count * 3,
              mesh.normals.count == count * 3, mesh.uv.count == count * 2,
              mesh.weights.count == count * 4, mesh.joints.count == count * 4,
              !mesh.indices.isEmpty, mesh.indices.count <= 196_608, mesh.indices.count.isMultiple(of: 3),
              mesh.indices.allSatisfy({ Int($0) < count }),
              (1...64).contains(boneCount), Set(mesh.bones).count == boneCount,
              mesh.bones.allSatisfy(Self.validNode), mesh.joints.allSatisfy({ Int($0) < boneCount }),
              mesh.sourceBoneIDs.count == boneCount, Set(mesh.sourceBoneIDs).count == boneCount,
              mesh.sourceBoneIDs.allSatisfy({ (0...65_535).contains($0) }),
              mesh.inverseBinds.count == boneCount,
              mesh.inverseBinds.allSatisfy({ $0.count == 16 && $0.allSatisfy(\.isFinite) }),
              [mesh.positions, mesh.normals, mesh.uv, mesh.weights].allSatisfy({ $0.allSatisfy(\.isFinite) }),
              let material = mesh.material,
              material.shader == "alpha-mask",
              ["red", "alpha"].contains(material.alphaChannel), ["alpha", "add"].contains(material.blend),
              ["back", "front"].contains(material.cullMode), ["linear", "nearest"].contains(material.filter),
              (0...1).contains(material.wrapS), (0...1).contains(material.wrapT),
              material.tint.count == 4, material.tint.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw Failure.invalid }
        guard (material.colorTexture != nil) == (mesh.colorUV != nil) else { throw Failure.invalid }
        if let uv = mesh.colorUV {
            guard uv.count == count * 2, uv.allSatisfy(\.isFinite) else { throw Failure.invalid }
        }
        for vertex in 0..<count {
            let values = mesh.weights[(vertex * 4)..<(vertex * 4 + 4)]
            guard values.allSatisfy({ $0 >= 0 && $0 <= 1 }), abs(values.reduce(0, +) - 1) < 0.00001 else { throw Failure.invalid }
        }
    }

    func validate(model: GLTFModel, profile: DuelWeaponProfile) throws {
        guard let source = profiles.first(where: { $0.id == profile.id }), source.characterSHA256 == profile.sha256,
              model.node(named: source.skeletonNode ?? "skeleton") != nil,
              model.node(named: source.attachmentNode ?? "SF3_Actor_Meters") != nil,
              source.clips.allSatisfy({ model.clips[$0] != nil }),
              source.meshes.flatMap(\.bones).allSatisfy({ model.node(named: $0) != nil }) else { throw Failure.incomplete }
    }

    final class Binding {
        let root: SCNNode
        let holders: [SCNNode]
        let clips: Set<String>
        private let windows: [String: [ClosedRange<Int>]]?
        init(root: SCNNode, holders: [SCNNode], clips: Set<String>, windows: [String: [ClosedRange<Int>]]? = nil) {
            self.root = root; self.holders = holders; self.clips = clips; self.windows = windows
        }
        func supports(_ clip: String) -> Bool { clips.contains(clip) && root.parent != nil }
        func update(clip: String, active: Bool, phaseBps: Int? = nil, enabled: Bool = true) {
            guard enabled, supports(clip) else { root.isHidden = true; return }
            if let windows {
                guard let phaseBps, (0...10_000).contains(phaseBps) else { root.isHidden = true; return }
                root.isHidden = windows[clip]?.contains(where: { $0.contains(phaseBps) }) != true
            } else {
                root.isHidden = !active
            }
        }
    }

    func install(on instance: GLTFModel.Instance, model: GLTFModel, profile: DuelWeaponProfile) -> Binding {
        // validate() ran before this immutable model/profile could be cached.
        let source = profiles.first { $0.id == profile.id }!
        let root = SCNNode(); root.name = "duel.source-weapon-trails"; root.isHidden = true
        var holders: [SCNNode] = []
        for mesh in source.meshes where profile.activeWeaponSides.contains(mesh.side) {
            let count = mesh.positions.count / 3
            func floats(_ values: [Float], semantic: SCNGeometrySource.Semantic, width: Int) -> SCNGeometrySource {
                let data = values.withUnsafeBytes { Data($0) }
                return SCNGeometrySource(data: data, semantic: semantic, vectorCount: count,
                                         usesFloatComponents: true, componentsPerVector: width, bytesPerComponent: 4,
                                         dataOffset: 0, dataStride: width * 4)
            }
            let vertices = floats(mesh.positions, semantic: .vertex, width: 3)
            let normals = floats(mesh.normals, semantic: .normal, width: 3)
            let uv = floats(mesh.uv, semantic: .texcoord, width: 2)
            let indices = mesh.indices.withUnsafeBytes { Data($0) }
            let element = SCNGeometryElement(data: indices, primitiveType: .triangles,
                                             primitiveCount: mesh.indices.count / 3, bytesPerIndex: 2)
            let colorUV = mesh.colorUV.map { floats($0, semantic: .texcoord, width: 2) }
            let geometry = SCNGeometry(sources: [vertices, normals, uv] + (colorUV.map { [$0] } ?? []), elements: [element])
            let material = SCNMaterial(); material.name = "duel.source-trail-alpha.\(mesh.side)"
            material.lightingModel = .constant; material.diffuse.contents = UIColor.white
            material.blendMode = mesh.material?.blend == "add" ? .add : .alpha
            // Katana is a single surface: all 12 source triangles turn away
            // from the camera in one of our actor's yaw facings. Hammers have
            // opposing faces. Keep the thin katana surface visible from either
            // side without changing its mesh or duplicating the hammer surface.
            // This is a SceneKit facing adapter, not recovered Unity cull events.
            material.isDoubleSided = mesh.material?.doubleSided ?? (profile.id == "sun_katana")
            material.cullMode = mesh.material?.cullMode == "front" ? .front : .back
            material.readsFromDepthBuffer = mesh.material?.readsDepth ?? true
            material.writesToDepthBuffer = mesh.material?.writesDepth ?? false
            let texture = SCNMaterialProperty(contents: alphaByProfile[profile.id])
            texture.wrapS = mesh.material?.wrapS == 0 ? .repeat : .clamp
            texture.wrapT = mesh.material?.wrapT == 0 ? .repeat : .clamp
            texture.minificationFilter = mesh.material?.filter == "nearest" ? .nearest : .linear
            texture.magnificationFilter = texture.minificationFilter; texture.mipFilter = .none
            material.setValue(texture, forKey: "sourceAlpha")
            if let authored = mesh.material {
                let hasSourceColor = authored.colorTexture.flatMap { colorTextures[$0.name] } != nil
                if let color = authored.colorTexture.flatMap({ colorTextures[$0.name] }) {
                    material.diffuse.contents = color; material.diffuse.mappingChannel = 1
                    material.diffuse.wrapS = texture.wrapS; material.diffuse.wrapT = texture.wrapT
                    material.diffuse.minificationFilter = texture.minificationFilter
                    material.diffuse.magnificationFilter = texture.magnificationFilter; material.diffuse.mipFilter = .none
                    // SceneKit keeps the source UV0 and source UV1 channels
                    // separate. Final fragment output owns emission/color.
                    material.emission.contents = alphaByProfile[profile.id]
                    material.emission.mappingChannel = 0
                }
                material.setValue(NSValue(scnVector4: SCNVector4(authored.tint[0], authored.tint[1], authored.tint[2], authored.tint[3])), forKey: "sourceColor")
                let channel = authored.alphaChannel == "alpha" ? "a" : "r"
                let sourceRGB = hasSourceColor ? "_surface.diffuse.rgb * sourceColor.rgb" : "sourceColor.rgb"
                let color = authored.multiplyColorByCoverage == false ? sourceRGB : sourceRGB + " * coverage"
                let alphaUV = hasSourceColor ? "_surface.emissionTexcoord" : "_surface.diffuseTexcoord"
                material.shaderModifiers = [.fragment: """
                uniform sampler2D sourceAlpha;
                uniform vec4 sourceColor;
                #pragma transparent
                #pragma body
                float coverage = clamp(texture2D(sourceAlpha, \(alphaUV)).\(channel), 0.0, 1.0);
                _output.color = vec4(\(color), sourceColor.a * coverage);
                """]
            } else {
                material.shaderModifiers = [.fragment: """
            uniform sampler2D sourceAlpha;
            #pragma transparent
            #pragma body
            float coverage = clamp(texture2D(sourceAlpha, _surface.diffuseTexcoord).r, 0.0, 1.0);
            _output.color = vec4(vec3(coverage), coverage);
            """]
            }
            geometry.materials = [material]
            let joints = SCNGeometrySource(data: mesh.joints.withUnsafeBytes { Data($0) }, semantic: .boneIndices,
                                           vectorCount: count, usesFloatComponents: false, componentsPerVector: 4,
                                           bytesPerComponent: 2, dataOffset: 0, dataStride: 8)
            let binds = mesh.inverseBinds.map { m -> NSValue in
                let matrix = simd_float4x4(columns: (
                    SIMD4(m[0], m[1], m[2], m[3]), SIMD4(m[4], m[5], m[6], m[7]),
                    SIMD4(m[8], m[9], m[10], m[11]), SIMD4(m[12], m[13], m[14], m[15])))
                return NSValue(scnMatrix4: SCNMatrix4(matrix))
            }
            let skin = SCNSkinner(baseGeometry: geometry,
                                 bones: mesh.bones.map { instance.nodes[model.node(named: $0)!] },
                                 boneInverseBindTransforms: binds,
                                 boneWeights: floats(mesh.weights, semantic: .boneWeights, width: 4), boneIndices: joints)
            skin.skeleton = instance.nodes[model.node(named: source.skeletonNode ?? "skeleton")!]
            let holder = SCNNode(geometry: geometry); holder.skinner = skin; holder.name = mesh.name
            holder.castsShadow = false; root.addChildNode(holder); holders.append(holder)
        }
        instance.nodes[model.node(named: source.attachmentNode ?? "SF3_Actor_Meters")!].addChildNode(root)
        let windows = source.clipWindows.map { entries in
            Dictionary(grouping: entries, by: \.clip).mapValues { $0.map { $0.startPhaseBps...$0.endPhaseBps } }
        }
        return Binding(root: root, holders: holders, clips: Set(source.clips), windows: windows)
    }
}
