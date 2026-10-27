import SceneKit
import UIKit
import simd

/// 读 glTF 2.0 的 3D 模型（.glb，或 .gltf 加旁边的 .bin、贴图），做成 SceneKit 的节点。
/// 只做乱斗用到的：三角形网格、法线、贴图坐标、底色贴图、骨骼蒙皮、骨骼动画（位置、旋转、缩放；线性或阶梯插值）。
/// 网格、贴图、动画读一次大家共用；每次 instantiate() 做一套新的节点、骨骼和材质（几个人用同一个角色互不影响）。
/// 动画不交给 SceneKit 播：每帧按时间自己算出每根骨骼的姿势摆上去，这样走路和出手能上下半身分开混着放
final class GLTFModel: @unchecked Sendable {
    enum LoadError: Error { case unreadable, badFormat }

    /// 一段动画
    struct Clip {
        enum Path { case translation, rotation, scale }

        struct Channel {
            let node: Int
            let path: Path
            let times: [Float]
            let values: [Float]
            let step: Bool
        }

        let name: String
        let duration: Float
        let channels: [Channel]
    }

    /// 一套骨骼的姿势（按 glTF 里的节点编号）
    struct Pose {
        var translation: [SIMD3<Float>]
        var rotation: [simd_quatf]
        var scale: [SIMD3<Float>]
    }

    /// instantiate() 做出来的一套
    struct Instance {
        let root: SCNNode
        /// 按 glTF 里的节点编号
        let nodes: [SCNNode]
        /// 这一套自己的材质（挨打闪白只闪这一个人）
        let materials: [SCNMaterial]
    }

    private struct NodeInfo {
        var name: String
        var children: [Int]
        var matrix: SCNMatrix4?
        var mesh: Int?
        var skin: Int?
    }

    private struct Primitive {
        let geometry: SCNGeometry
        let boneIndices: SCNGeometrySource?
        let boneWeights: SCNGeometrySource?
    }

    private struct Skin {
        let joints: [Int]
        let inverseBinds: [NSValue]
    }

    let names: [String]
    /// 没有动画时每个节点的样子
    let restPose: Pose
    /// 动画里动到的节点（骨骼）
    let animated: [Int]
    let clips: [String: Clip]
    private let nodes: [NodeInfo]
    private let parents: [Int?]
    private let roots: [Int]
    private let meshes: [[Primitive]]
    private let skins: [Skin]

    /// animations：只读这几段动画（一个角色文件里有七十多段，用不上的不读）；nil 全读。
    /// maxTexture：贴图最大边长，大了缩小（这些模型的贴图是一格格的纯色，缩小看不出来，省显存）
    init(url: URL, animations wanted: Set<String>? = nil, maxTexture: CGFloat = 512) throws {
        guard let file = try? Data(contentsOf: url) else { throw LoadError.unreadable }
        let json: [String: Any]
        var binary: Data?
        if file.count >= 12, file.prefix(4) == Data("glTF".utf8) {
            // .glb：12 字节文件头，然后一块块：JSON、二进制
            var offset = 12
            var jsonData: Data?
            while offset + 8 <= file.count {
                let length = Int(file.uint32(at: offset)), type = file.uint32(at: offset + 4)
                let end = min(offset + 8 + length, file.count)
                let body = file.subdata(in: (file.startIndex + offset + 8)..<(file.startIndex + end))
                if type == 0x4E4F534A { jsonData = body } else if type == 0x004E4942 { binary = body }
                offset = end
            }
            guard let jsonData, let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { throw LoadError.badFormat }
            json = object
        } else {
            guard let object = try? JSONSerialization.jsonObject(with: file) as? [String: Any] else { throw LoadError.badFormat }
            json = object
        }
        let folder = url.deletingLastPathComponent()

        // 缓冲区
        let bufferList = json["buffers"] as? [[String: Any]] ?? []
        let buffers: [Data] = bufferList.enumerated().map { index, buffer in
            if let uri = buffer["uri"] as? String {
                return (try? Data(contentsOf: folder.appendingPathComponent(uri))) ?? Data()
            }
            return index == 0 ? (binary ?? Data()) : Data()
        }
        let reader = AccessorReader(buffers: buffers, views: json["bufferViews"] as? [[String: Any]] ?? [],
                                    accessors: json["accessors"] as? [[String: Any]] ?? [])

        // 贴图
        let images: [UIImage?] = (json["images"] as? [[String: Any]] ?? []).map { image in
            if let uri = image["uri"] as? String {
                return TextureCache.shared.image(at: folder.appendingPathComponent(uri), maxSize: maxTexture)
            }
            if let view = image["bufferView"] as? Int, let data = reader.viewData(view), let decoded = UIImage(data: data) {
                return TextureCache.shrink(decoded, to: maxTexture)
            }
            return nil
        }
        let textures = json["textures"] as? [[String: Any]] ?? []
        let materials: [SCNMaterial] = (json["materials"] as? [[String: Any]] ?? []).map { info in
            let material = SCNMaterial()
            material.lightingModel = .lambert
            material.isDoubleSided = info["doubleSided"] as? Bool ?? false
            let pbr = info["pbrMetallicRoughness"] as? [String: Any] ?? [:]
            if let texture = (pbr["baseColorTexture"] as? [String: Any])?["index"] as? Int,
               textures.indices.contains(texture), let source = textures[texture]["source"] as? Int,
               images.indices.contains(source), let image = images[source] {
                material.diffuse.contents = image
                material.diffuse.wrapS = .repeat
                material.diffuse.wrapT = .repeat
                material.diffuse.magnificationFilter = .linear
                material.diffuse.minificationFilter = .linear
                material.diffuse.mipFilter = .linear
            } else if let factor = pbr["baseColorFactor"] as? [Double], factor.count == 4 {
                material.diffuse.contents = UIColor(red: factor[0], green: factor[1], blue: factor[2], alpha: factor[3])
            }
            return material
        }

        // 网格
        meshes = (json["meshes"] as? [[String: Any]] ?? []).map { mesh in
            (mesh["primitives"] as? [[String: Any]] ?? []).compactMap { primitive -> Primitive? in
                guard (primitive["mode"] as? Int ?? 4) == 4,
                      let attributes = primitive["attributes"] as? [String: Int],
                      let positionIndex = attributes["POSITION"] else { return nil }
                let positions = reader.floats(positionIndex)
                let count = positions.count / 3
                guard count > 0 else { return nil }
                var sources = [GLTFModel.source(positions, .vertex, width: 3)]
                if let normalIndex = attributes["NORMAL"] {
                    let normals = reader.floats(normalIndex)
                    if normals.count == count * 3 { sources.append(GLTFModel.source(normals, .normal, width: 3)) }
                }
                if let uvIndex = attributes["TEXCOORD_0"] {
                    let uvs = reader.floats(uvIndex)
                    if uvs.count == count * 2 { sources.append(GLTFModel.source(uvs, .texcoord, width: 2)) }
                }
                let indices: [UInt32] = (primitive["indices"] as? Int).map { reader.integers($0) }
                    ?? (0..<UInt32(count)).map { $0 }
                guard !indices.isEmpty, indices.allSatisfy({ Int($0) < count }) else { return nil }
                let geometry = SCNGeometry(sources: sources, elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
                if let material = primitive["material"] as? Int, materials.indices.contains(material) {
                    geometry.materials = [materials[material]]
                }
                var boneIndices: SCNGeometrySource?
                var boneWeights: SCNGeometrySource?
                if let jointIndex = attributes["JOINTS_0"], let weightIndex = attributes["WEIGHTS_0"] {
                    let joints = reader.integers(jointIndex).map { UInt16(clamping: $0) }
                    let weights = reader.floats(weightIndex)
                    if joints.count == count * 4, weights.count == count * 4 {
                        boneIndices = SCNGeometrySource(data: joints.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .boneIndices,
                                                        vectorCount: count, usesFloatComponents: false, componentsPerVector: 4,
                                                        bytesPerComponent: 2, dataOffset: 0, dataStride: 8)
                        boneWeights = GLTFModel.source(weights, .boneWeights, width: 4)
                    }
                }
                return Primitive(geometry: geometry, boneIndices: boneIndices, boneWeights: boneWeights)
            }
        }

        // 节点
        var restTranslation: [SIMD3<Float>] = []
        var restRotation: [simd_quatf] = []
        var restScale: [SIMD3<Float>] = []
        var infos: [NodeInfo] = []
        for (index, node) in (json["nodes"] as? [[String: Any]] ?? []).enumerated() {
            var info = NodeInfo(name: node["name"] as? String ?? "node\(index)", children: node["children"] as? [Int] ?? [])
            if let m = node["matrix"] as? [Double], m.count == 16 { info.matrix = SCNMatrix4(columnMajor: m.map(Float.init)) }
            let t = node["translation"] as? [Double] ?? []
            let r = node["rotation"] as? [Double] ?? []
            let s = node["scale"] as? [Double] ?? []
            restTranslation.append(t.count == 3 ? SIMD3(Float(t[0]), Float(t[1]), Float(t[2])) : .zero)
            restRotation.append(r.count == 4 ? simd_normalize(simd_quatf(ix: Float(r[0]), iy: Float(r[1]), iz: Float(r[2]), r: Float(r[3])))
                                             : simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
            restScale.append(s.count == 3 ? SIMD3(Float(s[0]), Float(s[1]), Float(s[2])) : SIMD3(repeating: 1))
            info.mesh = node["mesh"] as? Int
            info.skin = node["skin"] as? Int
            infos.append(info)
        }
        nodes = infos
        names = infos.map(\.name)
        restPose = Pose(translation: restTranslation, rotation: restRotation, scale: restScale)
        var parentList = [Int?](repeating: nil, count: infos.count)
        for (index, info) in infos.enumerated() {
            for child in info.children where parentList.indices.contains(child) && parentList[child] == nil && child != index {
                parentList[child] = index
            }
        }
        parents = parentList
        let sceneIndex = json["scene"] as? Int ?? 0
        let scenes = json["scenes"] as? [[String: Any]] ?? []
        roots = scenes.indices.contains(sceneIndex)
            ? (scenes[sceneIndex]["nodes"] as? [Int] ?? []).filter { infos.indices.contains($0) }
            : infos.indices.filter { parentList[$0] == nil }

        // 骨骼
        skins = (json["skins"] as? [[String: Any]] ?? []).map { skin in
            let joints = skin["joints"] as? [Int] ?? []
            guard joints.allSatisfy({ infos.indices.contains($0) }) else { return Skin(joints: [], inverseBinds: []) }
            var inverse: [NSValue] = []
            if let accessor = skin["inverseBindMatrices"] as? Int {
                let values = reader.floats(accessor)
                inverse = stride(from: 0, to: values.count - 15, by: 16).map {
                    NSValue(scnMatrix4: SCNMatrix4(columnMajor: Array(values[$0..<($0 + 16)])))
                }
            }
            while inverse.count < joints.count { inverse.append(NSValue(scnMatrix4: SCNMatrix4Identity)) }
            return Skin(joints: joints, inverseBinds: Array(inverse.prefix(joints.count)))
        }

        // 动画
        var clipList: [String: Clip] = [:]
        var moved = Set<Int>()
        for animation in json["animations"] as? [[String: Any]] ?? [] {
            let name = animation["name"] as? String ?? "animation\(clipList.count)"
            if let wanted, !wanted.contains(name) { continue }
            let samplers = animation["samplers"] as? [[String: Any]] ?? []
            var channels: [Clip.Channel] = []
            for channel in animation["channels"] as? [[String: Any]] ?? [] {
                guard let samplerIndex = channel["sampler"] as? Int, samplers.indices.contains(samplerIndex),
                      let target = channel["target"] as? [String: Any], let node = target["node"] as? Int, infos.indices.contains(node),
                      let input = samplers[samplerIndex]["input"] as? Int, let output = samplers[samplerIndex]["output"] as? Int else { continue }
                let path: Clip.Path
                switch target["path"] as? String {
                case "translation": path = .translation
                case "rotation": path = .rotation
                case "scale": path = .scale
                default: continue
                }
                let width = path == .rotation ? 4 : 3
                let interpolation = samplers[samplerIndex]["interpolation"] as? String ?? "LINEAR"
                var times = reader.floats(input)
                var values = reader.floats(output)
                // 三次样条的每个关键帧存了三份（入切线、值、出切线），只取中间的值，当成线性
                if interpolation == "CUBICSPLINE" {
                    values = stride(from: 0, to: values.count - 3 * width + 1, by: 3 * width).flatMap {
                        Array(values[($0 + width)..<($0 + 2 * width)])
                    }
                }
                let keys = min(times.count, values.count / width)
                guard keys > 0 else { continue }
                times = Array(times.prefix(keys))
                values = Array(values.prefix(keys * width))
                channels.append(Clip.Channel(node: node, path: path, times: times, values: values, step: interpolation == "STEP"))
                moved.insert(node)
            }
            let duration = channels.compactMap { $0.times.last }.max() ?? 0
            clipList[name] = Clip(name: name, duration: duration, channels: channels)
        }
        clips = clipList
        animated = moved.sorted()
    }

    /// 按名字找节点
    func node(named name: String) -> Int? {
        names.firstIndex(of: name)
    }

    /// 这个节点和它下面所有的节点
    func subtree(of index: Int) -> Set<Int> {
        guard nodes.indices.contains(index) else { return [] }
        var result: Set<Int> = [index]
        var stack = [index]
        while let current = stack.popLast() {
            for child in nodes[current].children where parents.indices.contains(child) && parents[child] == current && !result.contains(child) {
                result.insert(child)
                stack.append(child)
            }
        }
        return result
    }

    /// 做一套新的节点（骨骼、蒙皮、自己的材质）。shareMaterials：大家共用一份材质（树、箱子这种不会闪的摆设）
    func instantiate(shareMaterials: Bool = false) -> Instance {
        let made = nodes.indices.map { index -> SCNNode in
            let node = SCNNode()
            node.name = nodes[index].name
            if let matrix = nodes[index].matrix {
                node.transform = matrix
            } else {
                node.simdPosition = restPose.translation[index]
                node.simdOrientation = restPose.rotation[index]
                node.simdScale = restPose.scale[index]
            }
            return node
        }
        for (index, info) in nodes.enumerated() {
            for child in info.children where made.indices.contains(child) && parents[child] == index {
                made[index].addChildNode(made[child])
            }
        }
        var copies: [ObjectIdentifier: SCNMaterial] = [:]
        var owned: [SCNMaterial] = []
        for (index, info) in nodes.enumerated() {
            guard let mesh = info.mesh, meshes.indices.contains(mesh) else { continue }
            let skin = info.skin.flatMap { skins.indices.contains($0) ? skins[$0] : nil }
            for primitive in meshes[mesh] {
                let geometry: SCNGeometry
                if shareMaterials {
                    geometry = primitive.geometry
                } else {
                    // 顶点数据共用，材质各一份
                    geometry = primitive.geometry.copy() as? SCNGeometry ?? primitive.geometry
                    geometry.materials = primitive.geometry.materials.map { material in
                        if let copy = copies[ObjectIdentifier(material)] { return copy }
                        let copy = material.copy() as? SCNMaterial ?? material
                        copies[ObjectIdentifier(material)] = copy
                        owned.append(copy)
                        return copy
                    }
                }
                let holder = SCNNode(geometry: geometry)
                if let skin, !skin.joints.isEmpty, let indices = primitive.boneIndices, let weights = primitive.boneWeights {
                    let skinner = SCNSkinner(baseGeometry: geometry, bones: skin.joints.map { made[$0] },
                                             boneInverseBindTransforms: skin.inverseBinds, boneWeights: weights, boneIndices: indices)
                    // glTF 里蒙皮按网格所在节点的坐标算
                    skinner.skeleton = made[index]
                    holder.skinner = skinner
                }
                made[index].addChildNode(holder)
            }
        }
        let root = SCNNode()
        for index in roots where made[index].parent == nil { root.addChildNode(made[index]) }
        return Instance(root: root, nodes: made, materials: owned)
    }

    private static func source(_ values: [Float], _ semantic: SCNGeometrySource.Semantic, width: Int) -> SCNGeometrySource {
        SCNGeometrySource(data: values.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: semantic,
                          vectorCount: values.count / width, usesFloatComponents: true, componentsPerVector: width,
                          bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<Float>.size * width)
    }
}

extension GLTFModel.Clip {
    /// 第 time 秒（超出就停在头尾）每根骨骼的样子写进 pose；这段动画没动到的骨骼不改
    func sample(at time: Float, into pose: inout GLTFModel.Pose) {
        for channel in channels {
            let times = channel.times
            let last = times.count - 1
            var k0 = 0, k1 = 0
            var fraction: Float = 0
            if last > 0 && time > times[0] {
                if time >= times[last] {
                    k0 = last
                    k1 = last
                } else {
                    var low = 0, high = last
                    while high - low > 1 {
                        let middle = (low + high) / 2
                        if times[middle] <= time { low = middle } else { high = middle }
                    }
                    k0 = low
                    k1 = high
                    let span = times[k1] - times[k0]
                    fraction = channel.step || span <= 0 ? 0 : (time - times[k0]) / span
                }
            }
            let v = channel.values
            switch channel.path {
            case .rotation:
                let a = simd_quatf(ix: v[k0 * 4], iy: v[k0 * 4 + 1], iz: v[k0 * 4 + 2], r: v[k0 * 4 + 3])
                if fraction > 0 {
                    let b = simd_quatf(ix: v[k1 * 4], iy: v[k1 * 4 + 1], iz: v[k1 * 4 + 2], r: v[k1 * 4 + 3])
                    pose.rotation[channel.node] = simd_slerp(a, b, fraction)
                } else {
                    pose.rotation[channel.node] = a
                }
            case .translation, .scale:
                var value = SIMD3(v[k0 * 3], v[k0 * 3 + 1], v[k0 * 3 + 2])
                if fraction > 0 {
                    let b = SIMD3(v[k1 * 3], v[k1 * 3 + 1], v[k1 * 3 + 2])
                    value += (b - value) * fraction
                }
                if channel.path == .translation {
                    pose.translation[channel.node] = value
                } else {
                    pose.scale[channel.node] = value
                }
            }
        }
    }
}

extension GLTFModel.Pose {
    /// 往 other 靠：weight 0 不变，1 完全变成 other；只动 nodes 里的这些骨骼
    mutating func blend<Nodes: Sequence>(toward other: GLTFModel.Pose, weight: Float, nodes: Nodes) where Nodes.Element == Int {
        guard weight > 0 else { return }
        let w = min(weight, 1)
        for i in nodes {
            translation[i] += (other.translation[i] - translation[i]) * w
            scale[i] += (other.scale[i] - scale[i]) * w
            rotation[i] = w >= 1 ? other.rotation[i] : simd_slerp(rotation[i], other.rotation[i], w)
        }
    }

    /// 一根骨骼相对它上一级的变换（先缩放、再旋转、再平移）
    func transform(_ i: Int) -> simd_float4x4 {
        var m = simd_float4x4(rotation[i])
        m.columns.0 *= scale[i].x
        m.columns.1 *= scale[i].y
        m.columns.2 *= scale[i].z
        m.columns.3 = SIMD4(translation[i], 1)
        return m
    }
}

/// 几个模型共用的贴图文件只读一次（树、石头、旗子共用一张）
private final class TextureCache: @unchecked Sendable {
    static let shared = TextureCache()
    private let lock = NSLock()
    private var images: [String: UIImage] = [:]

    func image(at url: URL, maxSize: CGFloat) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(url.path)@\(Int(maxSize))"
        if let image = images[key] { return image }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        let shrunk = Self.shrink(image, to: maxSize)
        images[key] = shrunk
        return shrunk
    }

    static func shrink(_ image: UIImage, to maxSize: CGFloat) -> UIImage {
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard max(size.width, size.height) > maxSize else { return image }
        let factor = maxSize / max(size.width, size.height)
        let target = CGSize(width: (size.width * factor).rounded(), height: (size.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

/// 按 glTF 的 accessor 读出数（浮点、整数；交错存放、归一化的整数都照规矩转好）
private struct AccessorReader {
    let buffers: [Data]
    let views: [[String: Any]]
    let accessors: [[String: Any]]

    private struct Layout {
        let data: Data
        /// 第一个元素从 data 的第几个字节开始
        let start: Int
        let stride: Int
        let count: Int
        let width: Int
        let type: Int
        let size: Int
        let normalized: Bool
    }

    private static let components = ["SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16]
    private static let sizes = [5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4]

    func viewData(_ index: Int) -> Data? {
        guard views.indices.contains(index) else { return nil }
        let view = views[index]
        guard let buffer = view["buffer"] as? Int, buffers.indices.contains(buffer) else { return nil }
        let offset = view["byteOffset"] as? Int ?? 0
        let length = view["byteLength"] as? Int ?? 0
        let data = buffers[buffer]
        guard offset >= 0, length >= 0, offset + length <= data.count else { return nil }
        return data.subdata(in: (data.startIndex + offset)..<(data.startIndex + offset + length))
    }

    private func layout(_ index: Int) -> Layout? {
        guard accessors.indices.contains(index) else { return nil }
        let accessor = accessors[index]
        guard let viewIndex = accessor["bufferView"] as? Int, views.indices.contains(viewIndex),
              let type = accessor["componentType"] as? Int, let size = Self.sizes[type],
              let width = Self.components[accessor["type"] as? String ?? ""] else { return nil }
        let view = views[viewIndex]
        guard let buffer = view["buffer"] as? Int, buffers.indices.contains(buffer) else { return nil }
        let data = buffers[buffer]
        let viewStart = view["byteOffset"] as? Int ?? 0
        let viewLength = view["byteLength"] as? Int ?? 0
        let count = accessor["count"] as? Int ?? 0
        let stride = (view["byteStride"] as? Int).flatMap { $0 > 0 ? $0 : nil } ?? size * width
        let start = viewStart + (accessor["byteOffset"] as? Int ?? 0)
        // 最后一个元素也得在这一段里
        guard count > 0, viewStart >= 0, viewStart + viewLength <= data.count,
              start + (count - 1) * stride + size * width <= viewStart + viewLength else { return nil }
        return Layout(data: data, start: start, stride: stride, count: count, width: width, type: type, size: size,
                      normalized: accessor["normalized"] as? Bool ?? false)
    }

    func floats(_ index: Int) -> [Float] {
        guard let layout = layout(index) else { return [] }
        let total = layout.count * layout.width
        var result = [Float](repeating: 0, count: total)
        layout.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            if layout.type == 5126 && layout.stride == 4 * layout.width {
                // 最常见：紧挨着的 32 位浮点，整段拷出来
                result.withUnsafeMutableBytes { target in
                    target.copyMemory(from: UnsafeRawBufferPointer(rebasing: raw[layout.start..<(layout.start + total * 4)]))
                }
                return
            }
            for element in 0..<layout.count {
                for component in 0..<layout.width {
                    let at = layout.start + element * layout.stride + component * layout.size
                    result[element * layout.width + component] = Self.float(raw, at: at, type: layout.type, normalized: layout.normalized)
                }
            }
        }
        return result
    }

    func integers(_ index: Int) -> [UInt32] {
        guard let layout = layout(index) else { return [] }
        var result = [UInt32](repeating: 0, count: layout.count * layout.width)
        layout.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for element in 0..<layout.count {
                for component in 0..<layout.width {
                    let at = layout.start + element * layout.stride + component * layout.size
                    let value: UInt32
                    switch layout.size {
                    case 1: value = UInt32(raw[at])
                    case 2: value = UInt32(UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt16.self)))
                    default: value = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt32.self))
                    }
                    result[element * layout.width + component] = value
                }
            }
        }
        return result
    }

    private static func float(_ raw: UnsafeRawBufferPointer, at: Int, type: Int, normalized: Bool) -> Float {
        switch type {
        case 5126:
            return Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt32.self)))
        case 5121:
            return Float(raw[at]) / (normalized ? 255 : 1)
        case 5123:
            return Float(UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt16.self))) / (normalized ? 65535 : 1)
        case 5120:
            let value = Float(Int8(bitPattern: raw[at]))
            return normalized ? max(value / 127, -1) : value
        case 5122:
            let value = Float(Int16(bitPattern: UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt16.self))))
            return normalized ? max(value / 32767, -1) : value
        default:
            return Float(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt32.self)))
        }
    }
}

private extension Data {
    func uint32(at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for k in 0..<4 { value |= UInt32(self[startIndex + offset + k]) << (8 * k) }
        return value
    }
}

private extension SCNMatrix4 {
    /// glTF 的矩阵按列存
    init(columnMajor m: [Float]) {
        self.init(m11: m[0], m12: m[1], m13: m[2], m14: m[3],
                  m21: m[4], m22: m[5], m23: m[6], m24: m[7],
                  m31: m[8], m32: m[9], m33: m[10], m34: m[11],
                  m41: m[12], m42: m[13], m43: m[14], m44: m[15])
    }
}
