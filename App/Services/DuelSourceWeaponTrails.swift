import Foundation
import CryptoKit
import SceneKit
import UIKit
import simd

/// Original four-bone skins on the existing source skeleton. The attack window
/// and neutral-alpha material remain application adapters, not recovered Unity
/// controller/lighting behavior. Missing optional pack keeps the legacy ribbon;
/// an installed but invalid pack fails before any character is made.
@MainActor
final class DuelSourceWeaponTrails {
    static let fileName = "SF3_SourceTrails.json"
    static let sha256 = "6efadacf6a9e18a270a609132f622fb3ef569a505e46c81ff17c4b7ee386d0cc"
    enum Failure: Error { case invalid, incomplete }
    struct Mesh: Decodable {
        let name: String
        let side: String
        let bones: [String]
        let sourceBoneIDs: [Int]
        let positions: [Float]
        let normals: [Float]
        let uv: [Float]
        let weights: [Float]
        let joints: [UInt16]
        let indices: [UInt16]
        let inverseBinds: [[Float]]
    }
    struct Profile: Decodable {
        let id: String
        let characterSHA256: String
        let meshes: [Mesh]
        let clips: [String]
    }
    private struct Document: Decodable {
        let version: Int
        let profiles: [Profile]
        let alphaTexture: String
        let alphaSHA256: String
    }
    let profiles: [Profile]
    private let alpha: UIImage

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
        self.profiles = document.profiles; self.alpha = alpha
    }

    func validate(model: GLTFModel, profile: DuelWeaponProfile) throws {
        guard let source = profiles.first(where: { $0.id == profile.id }), source.characterSHA256 == profile.sha256,
              model.node(named: "skeleton") != nil, model.node(named: "SF3_Actor_Meters") != nil,
              source.clips.allSatisfy({ model.clips[$0] != nil }),
              source.meshes.flatMap(\.bones).allSatisfy({ model.node(named: $0) != nil }) else { throw Failure.incomplete }
    }

    final class Binding {
        let root: SCNNode
        let holders: [SCNNode]
        let clips: Set<String>
        init(root: SCNNode, holders: [SCNNode], clips: Set<String>) {
            self.root = root; self.holders = holders; self.clips = clips
        }
        func supports(_ clip: String) -> Bool { clips.contains(clip) && root.parent != nil }
        func update(clip: String, active: Bool) { root.isHidden = !active || !supports(clip) }
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
            let geometry = SCNGeometry(sources: [vertices, normals, uv], elements: [element])
            let material = SCNMaterial(); material.name = "duel.source-trail-alpha.\(mesh.side)"
            material.lightingModel = .constant; material.diffuse.contents = UIColor.white
            material.blendMode = .alpha
            // Katana is a single surface: all 12 source triangles turn away
            // from the camera in one of our actor's yaw facings. Hammers have
            // opposing faces. Keep the thin katana surface visible from either
            // side without changing its mesh or duplicating the hammer surface.
            // This is a SceneKit facing adapter, not recovered Unity cull events.
            material.isDoubleSided = profile.id == "sun_katana"
            material.cullMode = .back
            material.readsFromDepthBuffer = true; material.writesToDepthBuffer = false
            let texture = SCNMaterialProperty(contents: alpha)
            texture.wrapS = .clamp; texture.wrapT = .clamp
            texture.minificationFilter = .linear; texture.magnificationFilter = .linear; texture.mipFilter = .none
            material.setValue(texture, forKey: "sourceAlpha")
            material.shaderModifiers = [.fragment: """
            uniform sampler2D sourceAlpha;
            #pragma transparent
            #pragma body
            float coverage = clamp(texture2D(sourceAlpha, _surface.diffuseTexcoord).r, 0.0, 1.0);
            _output.color = vec4(vec3(coverage), coverage);
            """]
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
            skin.skeleton = instance.nodes[model.node(named: "skeleton")!]
            let holder = SCNNode(geometry: geometry); holder.skinner = skin; holder.name = mesh.name
            holder.castsShadow = false; root.addChildNode(holder); holders.append(holder)
        }
        instance.nodes[model.node(named: "SF3_Actor_Meters")!].addChildNode(root)
        return Binding(root: root, holders: holders, clips: Set(source.clips))
    }
}
