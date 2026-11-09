import Foundation
import SceneKit
import UIKit
import CryptoKit
import simd

/// Verified original weapon textures/material profiles on tick-driven ribbons.
/// The source skinned trail meshes, Unity particle renderer and original effect
/// trigger table are not reproduced by this endpoint-history adapter.
@MainActor
final class DuelWeaponEffects {
    enum Family: String { case katana, dualHammers }
    enum Failure: Error { case missing, manifest, resource(String) }
    struct Endpoints {
        let slot: Int
        let base: SCNVector3
        let tip: SCNVector3
    }
    struct Pose {
        let fighterID: Int
        let family: Family
        /// Stable identity for one action. nil stops emission and lets its
        /// existing vertices expire. Change the identity for a new action.
        let motionID: String?
        let isShadow: Bool
        /// World-space points from the actual posed weapon bones.
        let endpoints: [Endpoints]
    }

    static let manifestName = "SF3WE_manifest.json"
    static let manifestSHA256 = "d965d1b3e45411e88d3f99182ab312ba841c9e53a332f82ed83ee89164ac0bae"
    private static let maximumTrails = 16
    private static let maximumSamples = 64
    private struct File: Decodable { let name: String; let bytes: Int; let sha256: String }
    private struct Manifest: Decodable {
        let version: Int
        let whiteTexture: String
        let files: [File]
        let profiles: [String: Profile]
        let limitations: [String]
    }
    private struct Profile: Decodable { let swing: [Layer]; let shadow: [Layer] }
    private struct Layer: Decodable {
        let name: String
        let shader: String
        let lifetime: Double
        let fixedWidth: Float
        let colorKeys: [[Float]]
        let alphaKeys: [[Float]]
        let textures: [String: String]
        let uvMain: [Float]
        let uvAux: [Float]
        let uvMask: [Float]
        let parameters: [Float]
        let tint: [Float]
    }
    private struct Key: Hashable { let fighter: Int; let slot: Int }
    private struct Sample { let tick: Int; let base: SIMD3<Float>; let tip: SIMD3<Float> }
    private struct RenderLayer { let profile: Layer; let node: SCNNode; let material: SCNMaterial }
    private final class Trail {
        let key: Key
        let family: Family
        let motionID: String
        let shadow: Bool
        let root: SCNNode
        let layers: [RenderLayer]
        let lifetime: Double
        var samples: [Sample] = []
        init(key: Key, family: Family, motionID: String, shadow: Bool, root: SCNNode, layers: [RenderLayer]) {
            self.key = key; self.family = family; self.motionID = motionID; self.shadow = shadow
            self.root = root; self.layers = layers; lifetime = layers.map(\.profile.lifetime).max() ?? 0
        }
    }

    private let container = SCNNode()
    private var manifest: Manifest?
    private var textures: [String: UIImage] = [:]
    private var trails: [Trail] = []
    private var emitting: [Key: Trail] = [:]
    private var previousEndpoints: [Key: (Family, Sample)] = [:]
    private var lastTick: Int?
    private var paused = false
    private var ended = false
    private var sequence = 0
    private(set) var emittedSampleCount = 0
    var retainedTrailCount: Int { trails.count }
    var sourceTextureCount: Int { textures.count }
    var renderedVertexCount: Int {
        trails.reduce(0) { sum, trail in
            sum + trail.layers.reduce(0) { $0 + ($1.node.geometry?.sources(for: .vertex).first?.vectorCount ?? 0) }
        }
    }
    var limitations: [String] { manifest?.limitations ?? [] }

    static func manifestURL(directory: URL? = nil, bundle: Bundle = .main) -> URL? {
        let bases = directory.map { [$0] } ?? [bundle.resourceURL,
            bundle.resourceURL?.appendingPathComponent("FighterPrivate", isDirectory: true),
            bundle.resourceURL?.appendingPathComponent("FighterPrivate/WeaponEffects", isDirectory: true)].compactMap { $0 }
        return bases.map { $0.appendingPathComponent(manifestName) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    init(root: SCNNode, directory: URL? = nil, bundle: Bundle = .main) throws {
        guard let url = Self.manifestURL(directory: directory, bundle: bundle) else { throw Failure.missing }
        let data = try Data(contentsOf: url)
        guard data.count < 100_000, Self.digest(data) == Self.manifestSHA256 else { throw Failure.manifest }
        let definition = try JSONDecoder().decode(Manifest.self, from: data)
        guard definition.version == 1, definition.files.count == 11,
              Set(definition.files.map(\.name)).count == 11,
              Set(definition.profiles.keys) == Set(["katana", "dualHammers"]) else { throw Failure.manifest }
        let base = url.deletingLastPathComponent().resolvingSymlinksInPath()
        var totalBytes = 0
        for file in definition.files {
            guard file.name.hasPrefix("SF3WE_"), file.name.hasSuffix(".png"),
                  !file.name.contains("/"), !file.name.contains("\\"), !file.name.contains(".."),
                  (1...4_000_000).contains(file.bytes) else { throw Failure.manifest }
            let path = base.appendingPathComponent(file.name)
            let attributes = try path.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw Failure.resource(file.name) }
            let bytes = try Data(contentsOf: path)
            totalBytes += bytes.count
            guard totalBytes <= 8_000_000, bytes.count == file.bytes, Self.digest(bytes) == file.sha256,
                  let image = UIImage(data: bytes), image.size.width <= 2048, image.size.height <= 2048 else {
                throw Failure.resource(file.name)
            }
            textures[file.name] = image
        }
        guard textures[definition.whiteTexture] != nil else { throw Failure.manifest }
        for (family, profile) in definition.profiles {
            guard profile.swing.count == 1, profile.shadow.count == (family == "katana" ? 2 : 1) else { throw Failure.manifest }
            for layer in profile.swing + profile.shadow {
                guard ["weapon", "dashGlow", "dashNoise", "hammerFire"].contains(layer.shader),
                      layer.lifetime > 0, layer.lifetime <= 1.01, layer.fixedWidth.isFinite,
                      layer.fixedWidth >= 0, layer.fixedWidth <= 2,
                      Self.validKeys(layer.colorKeys, columns: 4), Self.validKeys(layer.alphaKeys, columns: 2),
                      [layer.uvMain, layer.uvAux, layer.uvMask, layer.parameters, layer.tint].allSatisfy({ $0.count == 4 && $0.allSatisfy(\.isFinite) }),
                      layer.textures.values.allSatisfy({ textures[$0] != nil }),
                      layer.textures["sourceMain"] != nil else { throw Failure.manifest }
            }
        }
        manifest = definition
        container.name = "duel.weapon-effects"
        root.addChildNode(container)
    }

    /// Call after each simulation step with freshly posed world-space bone
    /// endpoints. This clock must freeze during hit-stop. Repeated rendering
    /// of one tick neither emits another segment nor scrolls shader noise.
    /// App animation windows choose when motionID is non-nil; those windows
    /// are not claimed to be recovered original Unity FX events.
    /// Supply idle poses too: the preceding real bone sample seeds the first
    /// active frame, making its sweep visible before a contact hit-stop.
    func consumeStep(poses: [Pose], animationTick: Int) {
        guard !ended, !paused, animationTick >= 0, manifest != nil else { return }
        if let lastTick, animationTick < lastTick { reset() }
        guard lastTick != animationTick else { return }
        lastTick = animationTick
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        var present: Set<Key> = []
        for pose in poses.prefix(2) {
            guard (0..<2).contains(pose.fighterID) else { continue }
            for endpoints in pose.endpoints.prefix(2) {
                guard (0..<2).contains(endpoints.slot) else { continue }
                let base = SIMD3<Float>(endpoints.base.x, endpoints.base.y, endpoints.base.z)
                let tip = SIMD3<Float>(endpoints.tip.x, endpoints.tip.y, endpoints.tip.z)
                guard Self.finite(base), Self.finite(tip), simd_length(tip - base) > 0.00001 else { continue }
                let key = Key(fighter: pose.fighterID, slot: endpoints.slot)
                let preceding = previousEndpoints[key]
                let current = Sample(tick: animationTick, base: base, tip: tip)
                previousEndpoints[key] = (pose.family, current)
                guard let motion = pose.motionID, !motion.isEmpty, motion.count <= 200 else { continue }
                guard present.insert(key).inserted else { continue }
                var trail = emitting[key]
                let discontinuity = trail?.samples.last.map { simd_distance($0.tip, tip) > 2.5 || simd_distance($0.base, base) > 2.5 } ?? false
                if trail == nil || trail?.motionID != motion || trail?.family != pose.family || trail?.shadow != pose.isShadow || discontinuity {
                    trail = makeTrail(key: key, pose: pose, motion: motion)
                    emitting[key] = trail
                    if let preceding, preceding.0 == pose.family, preceding.1.tick == animationTick - 1,
                       simd_distance(preceding.1.tip, tip) <= 2.5, simd_distance(preceding.1.base, base) <= 2.5 {
                        trail?.samples.append(preceding.1)
                    }
                }
                guard let trail else { continue }
                trail.samples.append(current); emittedSampleCount += 1
                if trail.samples.count > Self.maximumSamples { trail.samples.removeFirst(trail.samples.count - Self.maximumSamples) }
            }
        }
        for key in Array(emitting.keys) where !present.contains(key) { emitting.removeValue(forKey: key) }
        while trails.count > Self.maximumTrails { remove(trails.removeFirst()) }
        var kept: [Trail] = []
        for trail in trails {
            trail.samples.removeAll { age(of: $0, at: animationTick) >= trail.lifetime }
            guard !trail.samples.isEmpty else { remove(trail); continue }
            for layer in trail.layers { rebuild(layer, samples: trail.samples, tick: animationTick) }
            kept.append(trail)
        }
        trails = kept
        SCNTransaction.commit()
    }

    func setPaused(_ value: Bool) { guard !ended else { return }; paused = value }
    func reset() {
        for trail in trails { trail.root.removeFromParentNode() }
        trails.removeAll(); emitting.removeAll(); previousEndpoints.removeAll()
        lastTick = nil; sequence = 0; emittedSampleCount = 0
    }
    func shutdown() {
        guard !ended else { return }
        reset(); ended = true; container.removeFromParentNode(); textures.removeAll(); manifest = nil
    }

    private func makeTrail(key: Key, pose: Pose, motion: String) -> Trail? {
        guard let manifest, let profile = manifest.profiles[pose.family.rawValue] else { return nil }
        sequence += 1
        let root = SCNNode(); root.name = "duel.weapon-trail.\(pose.family.rawValue).\(pose.isShadow ? "shadow" : "swing").\(sequence)"
        let layers = (pose.isShadow ? profile.shadow : profile.swing).map { profile -> RenderLayer in
            let material = SCNMaterial()
            material.lightingModel = .constant; material.isDoubleSided = true
            material.readsFromDepthBuffer = true; material.writesToDepthBuffer = false
            material.blendMode = .alpha; material.transparencyMode = .aOne
            material.diffuse.contents = textures[manifest.whiteTexture]
            material.diffuse.mipFilter = .none
            material.shaderModifiers = [.fragment: Self.fragment(profile)]
            for (name, file) in profile.textures {
                // Every profile reference was validated before attachment.
                let property = SCNMaterialProperty(contents: textures[file]!)
                property.minificationFilter = .linear; property.magnificationFilter = .linear; property.mipFilter = .none
                // Preserve the source sampler roles: weapon alpha/fire
                // clamp, while scrolling noise maps repeat.
                property.wrapS = name == "sourceAlpha" || profile.shader == "hammerFire" && name == "sourceMain" ? .clamp : .repeat
                property.wrapT = property.wrapS
                material.setValue(property, forKey: name)
            }
            for (name, value) in [("sourceUVMain", profile.uvMain), ("sourceUVAux", profile.uvAux),
                                  ("sourceUVMask", profile.uvMask), ("sourceParameters", profile.parameters), ("sourceTint", profile.tint)] {
                material.setValue(NSValue(scnVector4: SCNVector4(value[0], value[1], value[2], value[3])), forKey: name)
            }
            material.setValue(NSNumber(value: 0.0), forKey: "sourceTime")
            let node = SCNNode(); node.name = profile.name; node.castsShadow = false
            node.renderingOrder = 90; root.addChildNode(node)
            return RenderLayer(profile: profile, node: node, material: material)
        }
        let trail = Trail(key: key, family: pose.family, motionID: motion, shadow: pose.isShadow, root: root, layers: layers)
        container.addChildNode(root); trails.append(trail); return trail
    }

    private func rebuild(_ layer: RenderLayer, samples: [Sample], tick: Int) {
        let active = samples.filter { age(of: $0, at: tick) < layer.profile.lifetime }
        guard active.count >= 2 else { layer.node.geometry = nil; return }
        var vertices: [SCNVector3] = [], uv: [CGPoint] = [], indices: [UInt16] = []
        for (i, sample) in active.enumerated() {
            var a = sample.base, b = sample.tip
            if layer.profile.fixedWidth > 0 {
                let along = simd_normalize(b - a) * layer.profile.fixedWidth * 0.5
                // A weapon-tip ribbon is an explicit attachment adaptation;
                // the original body dash used a pelvis attachment.
                a = sample.tip - along; b = sample.tip + along
            }
            vertices.append(SCNVector3(a.x, a.y, a.z)); vertices.append(SCNVector3(b.x, b.y, b.z))
            let u = CGFloat(1 - age(of: sample, at: tick) / layer.profile.lifetime)
            uv.append(CGPoint(x: u, y: 0)); uv.append(CGPoint(x: u, y: 1))
            if i > 0 {
                let j = UInt16(2 * (i - 1))
                indices += [j, j + 1, j + 2, j + 1, j + 3, j + 2]
            }
        }
        let data = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(data: data, primitiveType: .triangles,
                                         primitiveCount: indices.count / 3, bytesPerIndex: MemoryLayout<UInt16>.size)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(textureCoordinates: uv)], elements: [element])
        geometry.materials = [layer.material]; layer.node.geometry = geometry
        layer.material.setValue(NSNumber(value: Double(tick) / Double(DuelGame.ticksPerSecond)), forKey: "sourceTime")
    }

    private func remove(_ trail: Trail) {
        trail.root.removeFromParentNode()
        if emitting[trail.key] === trail { emitting.removeValue(forKey: trail.key) }
    }
    private func age(of sample: Sample, at tick: Int) -> Double {
        (Double(tick) - Double(sample.tick)) / Double(DuelGame.ticksPerSecond)
    }
    private static func finite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
    private static func validKeys(_ values: [[Float]], columns: Int) -> Bool {
        guard (1...8).contains(values.count) else { return false }
        var previous: Float = -1
        for row in values {
            guard row.count == columns, row.allSatisfy(\.isFinite), row[0] >= 0, row[0] <= 1,
                  row[0] > previous else { return false }
            previous = row[0]
        }
        return true
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private static func curve(_ keys: [[Float]], name: String, vector: Bool) -> String {
        func value(_ row: [Float]) -> String {
            vector ? "vec3(\(row[1]), \(row[2]), \(row[3]))" : "\(row[1])"
        }
        let type = vector ? "vec3" : "float"
        var result = "\(type) \(name)(float age) {\n"
        result += "if (age <= \(keys[0][0])) return \(value(keys[0]));\n"
        for i in 1..<keys.count {
            let a = keys[i - 1], b = keys[i]
            result += "if (age <= \(b[0])) return mix(\(value(a)), \(value(b)), (age - \(a[0])) / \(b[0] - a[0]));\n"
        }
        return result + "return \(value(keys[keys.count - 1]));\n}\n"
    }

    private static func fragment(_ layer: Layer) -> String {
        // GLSL shader modifiers are translated by SceneKit for Metal. Textures
        // are bound by name as SCNMaterialProperty, not generated bitmaps.
        let samplers = layer.textures.keys.sorted().map { "uniform sampler2D \($0);" }.joined(separator: "\n")
        let header = """
        \(samplers)
        uniform vec4 sourceUVMain;
        uniform vec4 sourceUVAux;
        uniform vec4 sourceUVMask;
        uniform vec4 sourceParameters;
        uniform vec4 sourceTint;
        uniform float sourceTime;
        \(curve(layer.colorKeys, name: "sourceColorAt", vector: true))
        \(curve(layer.alphaKeys, name: "sourceAlphaAt", vector: false))
        #pragma transparent
        #pragma body
        vec2 trailUV = _surface.diffuseTexcoord;
        float trailAge = clamp(1.0 - trailUV.x, 0.0, 1.0);
        vec4 sourceVertex = vec4(sourceColorAt(trailAge), sourceAlphaAt(trailAge)) * sourceTint;
        vec2 mainUV = trailUV * sourceUVMain.xy + sourceUVMain.zw;
        """
        let body: String
        switch layer.shader {
        case "weapon":
            body = """
            vec3 weaponRGB = texture2D(sourceMain, mainUV).rgb;
            float weaponMask = texture2D(sourceMask, mainUV).r;
            weaponRGB = mix(weaponRGB, weaponRGB * sourceTint.rgb, weaponMask);
            float opacity = texture2D(sourceAlpha, trailUV).r * sourceParameters.x * sourceAlphaAt(trailAge);
            _output.color = vec4(weaponRGB * sourceColorAt(trailAge) * sourceParameters.x * sourceParameters.y, opacity);
            """
        case "dashGlow":
            body = """
            vec4 color = texture2D(sourceMain, mainUV) * sourceVertex * sourceParameters.x;
            color.rgb = clamp(color.rgb * sourceVertex.a, 0.0, 1.0);
            color.a = clamp(color.a * sourceParameters.y, 0.0, 1.0);
            // Source One / OneMinusSrcAlpha, expressed with SceneKit alpha.
            _output.color = color.a > 0.000001 ? vec4(color.rgb / color.a, color.a) : vec4(0.0);
            """
        case "dashNoise":
            body = """
            mainUV += vec2(fract(sourceTime * sourceParameters.z), 0.0);
            vec2 auxUV = trailUV * sourceUVAux.xy + sourceUVAux.zw + vec2(fract(sourceTime * sourceParameters.w), 0.0);
            vec2 maskUV = trailUV * sourceUVMask.xy + sourceUVMask.zw;
            vec3 noise = texture2D(sourceMain, mainUV).rgb * texture2D(sourceAux, auxUV).rgb * texture2D(sourceMask, maskUV).r;
            vec4 color = vec4(noise, noise.r) * sourceParameters.x * sourceVertex.a * sourceVertex;
            color.rgb = clamp(color.rgb * sourceVertex.a, 0.0, 1.0);
            color.a = clamp(color.a * sourceParameters.y, 0.0, 1.0);
            _output.color = color.a > 0.000001 ? vec4(color.rgb / color.a, color.a) : vec4(0.0);
            """
        default: // Original fire_seq with its verified white Noise2/gradient.
            body = """
            vec2 noiseUV = (trailUV + vec2(sourceTime * sourceParameters.w, 0.0)) * sourceUVAux.xy + sourceUVAux.zw;
            vec2 noise = (texture2D(sourceAux, noiseUV).xy * 2.0 - 1.0) * sourceParameters.z;
            float edge = 2.0 * clamp(min(trailUV.y, 1.0 - trailUV.y), 0.0, 1.0);
            float energy = edge + clamp(sourceParameters.y + noise.x, 0.0, 1.0);
            vec2 displaced = (trailUV + vec2(sourceParameters.y) * noise) * sourceUVMain.xy + sourceUVMain.zw;
            vec4 flame = texture2D(sourceMain, displaced);
            energy += clamp(noise.x * sourceParameters.y, 0.0, 1.0) * flame.r;
            vec3 rgb = max(energy, 0.0) * sourceVertex.rgb * sourceParameters.x * flame.a * flame.rgb;
            _output.color = vec4(rgb, flame.a * flame.a * sourceVertex.a);
            """
        }
        return header + "\n" + body
    }
}
