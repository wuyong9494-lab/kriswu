import Foundation
import ImageIO
import SceneKit
import UIKit

/// Plays the imported face display list on a fixed texture canvas. The archive
/// contains declarative triangles, matrices, colors and complete clip timelines;
/// it contains no executable client code. Child clocks never expand into an LCM.
///
/// Clock reference: sc-editor MovieClip.gotoAbsoluteTimeRecursive at
/// 0aaa905c7af7f0bfda416c5acb879ff1c36d5054 (MIT). Blend factors are its
/// documented NORMAL / SCREEN / ADDITIVE factors. Source-client phase and shader
/// parity still require device acceptance; unknown operations are rejected.
@MainActor
final class ArenaImportedFaceAnimator {
    private static var scenes: [String: ArenaFaceScene] = [:]
    private static var sceneOrder: [String] = []
    private static let imageCache: NSCache<NSString, UIImage> = {
        let value = NSCache<NSString, UIImage>()
        value.totalCostLimit = 24 * 1024 * 1024
        value.countLimit = 24
        return value
    }()
    private static var failures: [String: String] = [:]

    static func failureReason(for heroID: String) -> String? { failures[heroID] }

    private let specification: ArenaFaceSpecification
    private let scene: ArenaFaceScene
    private struct MaterialGroup {
        let base: ArenaFacePixels
        let materials: [SCNMaterial]
        let cacheSuffix: String
    }
    private let materialGroups: [MaterialGroup]
    private let cachePrefix: String
    private var lastRole: String?
    private var lastRenderTime: Double?
    private var expressionOrigin = 0.0
    private var lastSignature: String?
    private(set) var lastError: String?

    init?(heroID: String, model: GLTFModel, instance: GLTFModel.Instance) {
        do {
            let store = ArenaResourcePackStore.shared
            guard store.enabled, !model.names.isEmpty,
                  let hero = store.manifest?.heroes.first(where: { $0.id == heroID }),
                  let file = hero.faceFile, let specURL = store.url(for: file) else {
                throw ArenaFaceError.invalid("No approved face description for this hero")
            }
            let specification = try JSONDecoder().decode(ArenaFaceSpecification.self,
                from: Self.read(specURL, maximumBytes: 2 * 1024 * 1024))
            guard specification.schemaVersion == 1, specification.heroID == heroID,
                  specification.status == "ready", specification.canvasSize == [512, 512],
                  specification.clockPolicy == "independent_absolute_clip_fps",
                  let baseFile = specification.baseDiffuseFile,
                  let baseURL = store.url(for: baseFile),
                  let sceneURL = store.url(for: specification.sceneFile) else {
                throw ArenaFaceError.invalid("Face material, canvas or source-clock configuration is unsupported")
            }
            let key = sceneURL.absoluteString + "|" + specification.sceneSHA256
            let scene: ArenaFaceScene
            if let cached = Self.scenes[key] {
                scene = cached
            } else {
                let source = try JSONDecoder().decode(ArenaFaceScene.Document.self,
                    from: Self.read(sceneURL, maximumBytes: 40 * 1024 * 1024))
                scene = try ArenaFaceScene(source) { path in
                    guard let url = store.url(for: path) else {
                        throw ArenaFaceError.invalid("Face atlas path is not approved by the resource pack")
                    }
                    return try ArenaFacePixels(data: Self.read(url, maximumBytes: 32 * 1024 * 1024))
                }
                Self.scenes[key] = scene
                Self.sceneOrder.append(key)
                while Self.sceneOrder.count > 2 {
                    Self.scenes.removeValue(forKey: Self.sceneOrder.removeFirst())
                }
            }
            guard !specification.materialBindings.isEmpty,
                  Set(specification.materialBindings.map { $0.originalSourceImageIndex ?? $0.imageIndex }).count == 1 else {
                throw ArenaFaceError.invalid("Face-to-diffuse material selection is ambiguous")
            }
            var groups: [MaterialGroup] = []
            let bindingsByBase = Dictionary(grouping: specification.materialBindings) { $0.baseDiffuseFile ?? baseFile }
            for path in bindingsByBase.keys.sorted() {
                guard let bindings = bindingsByBase[path], let first = bindings.first,
                      let url = path == baseFile ? baseURL : store.url(for: path) else {
                    throw ArenaFaceError.invalid("Face material base image is not approved")
                }
                let base = try ArenaFacePixels(data: Self.read(url, maximumBytes: 8 * 1024 * 1024))
                guard base.width == 512, base.height == 512 else {
                    throw ArenaFaceError.invalid("Face material base image has the wrong canvas")
                }
                let names = Set(bindings.map(\.materialName))
                let bound = instance.materials.filter { names.contains($0.name ?? "") }
                guard names.isSubset(of: Set(bound.map { $0.name ?? "" })), !bound.isEmpty else {
                    throw ArenaFaceError.invalid("Face material names do not match this model instance")
                }
                groups.append(MaterialGroup(base: base, materials: bound,
                    cacheSuffix: path + "|" + (first.baseDiffuseSHA256 ?? specification.baseDiffuseSHA256 ?? "")))
            }
            // Validate every complete referenced timeline once, before a frame is
            // drawn. A ready role cannot conceal an unsupported blend or cycle.
            for role in specification.sourceRoles.values where role.status == "ready" {
                guard let objectID = role.objectID, let export = role.exportName,
                      sourceExport(scene, named: export) == objectID else {
                    throw ArenaFaceError.invalid("Face export identity does not match the shared scene")
                }
                try scene.validate(root: objectID)
            }
            self.specification = specification
            self.scene = scene
            materialGroups = groups
            cachePrefix = key + "|" + heroID + "|" + (specification.baseDiffuseSHA256 ?? "")
            Self.failures.removeValue(forKey: heroID)
        } catch {
            Self.failures[heroID] = error.localizedDescription
            return nil
        }
    }

    /// Accepts a monotonic scene clock, resetting the expression on a role
    /// change or clock reset. Both exact source fields (IdleFace/WalkFace/etc.)
    /// and their declared aliases are accepted; there is no face fallback.
    func update(role: String, time: Double) {
        guard time.isFinite, time >= 0 else {
            lastError = "Face time must be finite and nonnegative"
            return
        }
        guard let selected = specification.roles[role] ?? specification.sourceRoles[role], selected.status == "ready",
              let root = selected.objectID else {
            lastError = "No supported source face binding for role: \(role)"
            return
        }
        if lastRole != role || (lastRenderTime.map { time < $0 } ?? false) { expressionOrigin = time }
        if lastRole == role, let previous = lastRenderTime,
           time >= previous, time - previous < 1.0 / 15.0 { return }
        do {
            let elapsed = max(0, time - expressionOrigin)
            let signature = try scene.signature(root: root, time: elapsed)
            if signature != lastSignature || lastRole != role {
                for group in materialGroups {
                    let key = (cachePrefix + "|" + group.cacheSuffix + "|" + signature) as NSString
                    let image: UIImage
                    if let cached = Self.imageCache.object(forKey: key) {
                        image = cached
                    } else {
                        image = try scene.composite(root: root, time: elapsed, base: group.base)
                        Self.imageCache.setObject(image, forKey: key, cost: 512 * 512 * 4)
                    }
                    // An opaque slot and a premultiplied source slot may share
                    // authored UVs but require different straight PNG bases.
                    // The converter preserves their exact material identities.
                    for material in group.materials { material.diffuse.contents = image }
                }
                // This only changes the source diffuse pixels. glTF alpha/factor,
                // team tint, concealment and hit-flash shader modifiers survive.
                lastSignature = signature
            }
            lastRole = role
            lastRenderTime = time
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            Self.failures[specification.heroID] = error.localizedDescription
        }
    }

    private static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximumBytes else {
            throw ArenaFaceError.invalid("Face resource exceeds its declared reading limit")
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
}

private func sourceExport(_ scene: ArenaFaceScene, named name: String) -> Int? {
    guard let item = scene.document.exports[name], item.status == "ready" else { return nil }
    return item.objectID
}

private enum ArenaFaceError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let reason): return reason }
    }
}

private struct ArenaFaceSpecification: Decodable {
    struct Binding: Decodable {
        let materialName: String
        let imageIndex: Int
        let originalSourceImageIndex: Int?
        let baseDiffuseFile: String?
        let baseDiffuseSHA256: String?
    }
    struct Role: Decodable {
        let status: String
        let objectID: Int?
        let exportName: String?
    }
    let schemaVersion: Int
    let heroID: String
    let status: String
    let sceneFile: String
    let sceneSHA256: String
    let canvasSize: [Int]
    let baseDiffuseFile: String?
    let baseDiffuseSHA256: String?
    let materialBindings: [Binding]
    let roles: [String: Role]
    let sourceRoles: [String: Role]
    let clockPolicy: String
}

/// A small software triangle sampler retains UVs even when the UV triangle is
/// singular (solid-color atlas pixels). Core Graphics owns decoding and the
/// final 512-square image; no file reads or atlas recoloring occur in update().
/// Premultiplied arithmetic also keeps partially transparent face edges stable.
final class ArenaFaceScene {
    struct Document: Decodable {
        struct Texture: Decodable {
            let file: String
            let width: Int
            let height: Int
            let alphaEncoding: String?
        }
        struct Export: Decodable { let objectID: Int?; let status: String }
        struct Object: Decodable {
            struct Command: Decodable { let textureIndex: Int; let vertices: [[Double]] }
            struct Child: Decodable { let objectID: Int; let blendMode: Int }
            struct Frame: Decodable { let `repeat`: Int; let elements: [[Int]] }
            let id: Int
            let commands: [Command]
            let modifier: Int?
            let emptyText: Bool?
            let fps: Double?
            let frameCount: Int?
            let children: [Child]?
            let frames: [Frame]?
        }
        let schemaVersion: Int
        let canvasSize: [Int]
        let projection: [Double]
        let uvDivisor: Double
        let primitiveMode: String
        let textures: [Texture]
        let objects: [String: Object]
        let matrices: [[Double]]
        let colors: [[Double]]
        let exports: [String: Export]
    }

    private struct Affine {
        let a, b, c, d, tx, ty: Double
        static let identity = Affine([1, 0, 0, 1, 0, 0])
        init(_ values: [Double]) {
            a = values[0]; b = values[1]; c = values[2]
            d = values[3]; tx = values[4]; ty = values[5]
        }
        func appending(_ child: Affine) -> Affine {
            Affine([a * child.a + b * child.c, a * child.b + b * child.d,
                    c * child.a + d * child.c, c * child.b + d * child.d,
                    a * child.tx + b * child.ty + tx, c * child.tx + d * child.ty + ty])
        }
        func point(_ value: [Double]) -> SIMD2<Double> {
            SIMD2(a * value[0] + b * value[1] + tx, c * value[0] + d * value[1] + ty)
        }
    }

    private struct Color {
        let multiply: SIMD4<Float>
        let add: SIMD3<Float>
        static let identity = Color(multiply: SIMD4(repeating: 1), add: .zero)
        init(multiply: SIMD4<Float>, add: SIMD3<Float>) { self.multiply = multiply; self.add = add }
        init(_ values: [Double]) {
            multiply = SIMD4(Float(values[0] / 255), Float(values[1] / 255), Float(values[2] / 255), Float(values[3] / 255))
            add = SIMD3(Float(values[4] / 255), Float(values[5] / 255), Float(values[6] / 255))
        }
        func appending(_ child: Color) -> Color {
            Color(multiply: multiply * child.multiply,
                  add: SIMD3(multiply.x, multiply.y, multiply.z) * child.add + add)
        }
    }

    let document: Document
    private let objects: [Int: Document.Object]
    private let textures: [ArenaFacePixels]
    private let matrices: [Affine]
    private let colors: [Color]
    private let projection: Affine
    private var validatedClocks: [Int: [Int]] = [:]
    private let dimension = 512

    init(_ document: Document, texture: (String) throws -> ArenaFacePixels) throws {
        guard document.schemaVersion == 1, document.canvasSize == [512, 512],
              document.projection.count == 6, document.projection.allSatisfy(\.isFinite),
              document.uvDivisor == 65_535, document.primitiveMode == "triangle_strip",
              (1...8).contains(document.textures.count), document.objects.count <= 20_000,
              document.matrices.count <= 200_000, document.colors.count <= 200_000 else {
            throw ArenaFaceError.invalid("Unsupported face scene header")
        }
        guard document.matrices.allSatisfy({ $0.count == 6 && $0.allSatisfy { $0.isFinite && abs($0) <= 1e8 } }),
              document.colors.allSatisfy({ $0.count == 7 && $0.allSatisfy { $0.isFinite && (0...255).contains($0) } }) else {
            throw ArenaFaceError.invalid("Invalid source face matrix or color transform")
        }
        var indexed: [Int: Document.Object] = [:]
        for (key, item) in document.objects {
            guard Int(key) == item.id, indexed[item.id] == nil else {
                throw ArenaFaceError.invalid("Duplicate face object identity")
            }
            indexed[item.id] = item
        }
        self.document = document
        objects = indexed
        matrices = document.matrices.map(Affine.init)
        colors = document.colors.map(Color.init)
        projection = Affine(document.projection)
        textures = try document.textures.map { entry in
            let image = try texture(entry.file)
            guard entry.alphaEncoding == "straight", entry.width == image.width, entry.height == image.height,
                  image.width <= 8192, image.height <= 8192, image.width * image.height <= 32_000_000 else {
                throw ArenaFaceError.invalid("Face atlas dimensions or explicit straight-alpha encoding are unsupported")
            }
            return image
        }
    }

    func validate(root: Int) throws {
        if validatedClocks[root] != nil { return }
        var visited = Set<Int>()
        var clocks = Set<Int>()
        func walk(_ id: Int, ancestry: Set<Int>) throws {
            guard ancestry.count < 48, !ancestry.contains(id), let item = objects[id] else {
                throw ArenaFaceError.invalid("Missing or cyclic face object")
            }
            if visited.contains(id) { return }
            visited.insert(id)
            guard item.modifier == nil else {
                // No selected face currently uses modifiers. Never reinterpret
                // an unimplemented mask/stencil directive as a normal draw.
                throw ArenaFaceError.invalid("Unsupported face MovieClip modifier")
            }
            for command in item.commands {
                guard textures.indices.contains(command.textureIndex),
                      (3...4096).contains(command.vertices.count),
                      command.vertices.allSatisfy({ v in
                          v.count == 4 && v.allSatisfy(\.isFinite)
                          && abs(v[0]) <= 1e6 && abs(v[1]) <= 1e6
                          && (0...65_535).contains(v[2]) && (0...65_535).contains(v[3])
                      }) else { throw ArenaFaceError.invalid("Invalid face triangle strip") }
            }
            if let frames = item.frames {
                guard let count = item.frameCount, (1...100_000).contains(count),
                      let fps = item.fps, fps.isFinite, fps > 0, fps <= 240,
                      let children = item.children, frames.count <= count else {
                    throw ArenaFaceError.invalid("Invalid face clock")
                }
                clocks.insert(id)
                var total = 0
                var next = ancestry
                next.insert(id)
                for group in frames {
                    guard group.repeat > 0, group.repeat <= count - total, group.elements.count <= 4096 else {
                        throw ArenaFaceError.invalid("Invalid face frame run")
                    }
                    total += group.repeat
                    for e in group.elements {
                        guard e.count == 3, children.indices.contains(e[0]),
                              e[1] == -1 || matrices.indices.contains(e[1]),
                              e[2] == -1 || colors.indices.contains(e[2]) else {
                            throw ArenaFaceError.invalid("Invalid source face frame reference")
                        }
                        let child = children[e[0]]
                        guard [0, 4, 8].contains(child.blendMode) else {
                            throw ArenaFaceError.invalid("Unsupported face blend mode \(child.blendMode)")
                        }
                        try walk(child.objectID, ancestry: next)
                    }
                }
                guard total == count else { throw ArenaFaceError.invalid("Face frame run count mismatch") }
            } else if item.commands.isEmpty && item.emptyText != true {
                throw ArenaFaceError.invalid("Face object has no supported drawing data")
            }
        }
        try walk(root, ancestry: [])
        validatedClocks[root] = clocks.sorted()
    }

    static func frame(time: Double, fps: Double, count: Int) -> Int {
        guard time.isFinite, time >= 0, fps.isFinite, fps > 0, count > 0 else { return 0 }
        let elapsed = time * fps
        guard elapsed.isFinite else { return 0 }
        let nearest = elapsed.rounded()
        let stable = abs(elapsed - nearest) <= max(1e-9, elapsed.ulp * 2) ? nearest : floor(elapsed)
        return max(0, Int(stable.truncatingRemainder(dividingBy: Double(count))))
    }

    func signature(root: Int, time: Double) throws -> String {
        try validate(root: root)
        let clocks = validatedClocks[root] ?? []
        return String(root) + ":" + clocks.map { id in
            let node = objects[id]!
            return "\(id)=\(Self.frame(time: time, fps: node.fps!, count: node.frameCount!))"
        }.joined(separator: ",")
    }

    private func elements(_ item: Document.Object, time: Double) -> [[Int]] {
        guard let frames = item.frames, let fps = item.fps, let count = item.frameCount else { return [] }
        var index = Self.frame(time: time, fps: fps, count: count)
        for group in frames {
            if index < group.repeat { return group.elements }
            index -= group.repeat
        }
        return [] // validate() proves every sampled frame has a run.
    }

    func composite(root: Int, time: Double, base: ArenaFacePixels) throws -> UIImage {
        let overlay = try render(root: root, time: time)
        guard base.width == dimension, base.height == dimension else {
            throw ArenaFaceError.invalid("Base diffuse does not match the fixed face canvas")
        }
        var result = base.rgba
        for i in 0..<(dimension * dimension) {
            let o = overlay[i]
            let remaining = 1 - o.w
            for component in 0..<4 {
                let value = o[component] + Float(base.rgba[i * 4 + component]) / 255 * remaining
                result[i * 4 + component] = UInt8(clamping: Int((max(0, min(1, value)) * 255).rounded()))
            }
        }
        return try ArenaFacePixels(width: dimension, height: dimension, rgba: result).image()
    }

    /// Internal synthetic tests can inspect exact pixels without real client assets.
    func render(root: Int, time: Double) throws -> [SIMD4<Float>] {
        guard time.isFinite, time >= 0 else { throw ArenaFaceError.invalid("Invalid face sample time") }
        try validate(root: root)
        var pixels = [SIMD4<Float>](repeating: .zero, count: dimension * dimension)
        func draw(_ id: Int, transform: Affine, color: Color, blend: Int, into target: inout [SIMD4<Float>]) throws {
            guard let item = objects[id] else { throw ArenaFaceError.invalid("Face object vanished") }
            for command in item.commands {
                try raster(command, transform: transform, color: color, blend: blend, into: &target)
            }
            for e in elements(item, time: time) {
                let child = item.children![e[0]]
                let matrix = e[1] == -1 ? Affine.identity : matrices[e[1]]
                let tint = e[2] == -1 ? Color.identity : colors[e[2]]
                let mode = child.blendMode == 0 ? blend : child.blendMode
                try draw(child.objectID, transform: transform.appending(matrix), color: color.appending(tint), blend: mode, into: &target)
            }
        }
        try draw(root, transform: projection, color: .identity, blend: 0, into: &pixels)
        return pixels
    }

    private func raster(_ command: Document.Object.Command, transform: Affine, color: Color,
                        blend: Int, into pixels: inout [SIMD4<Float>]) throws {
        let atlas = textures[command.textureIndex]
        let points = command.vertices.map { transform.point($0) }
        let uv = command.vertices.map { SIMD2($0[2] / document.uvDivisor * Double(atlas.width),
                                                $0[3] / document.uvDivisor * Double(atlas.height)) }
        for k in 0..<(points.count - 2) {
            var ids = k.isMultiple(of: 2) ? [k, k + 1, k + 2] : [k, k + 2, k + 1]
            let a = points[ids[0]]
            var b = points[ids[1]], c = points[ids[2]]
            var area = edge(a, b, c)
            if !area.isFinite || abs(area) < 1e-10 { continue }
            if area < 0 {
                ids.swapAt(1, 2); b = points[ids[1]]; c = points[ids[2]]; area = -area
            }
            // Clip in floating-point before Int conversion, including wholly
            // off-canvas triangles. Source matrices cannot allocate huge layers.
            let minX = max(0, min(a.x, min(b.x, c.x)))
            let maxX = min(Double(dimension - 1), max(a.x, max(b.x, c.x)))
            let minY = max(0, min(a.y, min(b.y, c.y)))
            let maxY = min(Double(dimension - 1), max(a.y, max(b.y, c.y)))
            if !minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite || minX > maxX || minY > maxY { continue }
            let x0 = Int(floor(minX)), x1 = Int(ceil(maxX))
            let y0 = Int(floor(minY)), y1 = Int(ceil(maxY))
            let ua = uv[ids[0]], ub = uv[ids[1]], uc = uv[ids[2]]
            for y in y0...y1 {
                for x in x0...x1 {
                    let p = SIMD2(Double(x) + 0.5, Double(y) + 0.5)
                    let e0 = edge(b, c, p), e1 = edge(c, a, p), e2 = edge(a, b, p)
                    if !inside(e0, from: b, to: c) || !inside(e1, from: c, to: a) || !inside(e2, from: a, to: b) { continue }
                    let coord = (ua * e0 + ub * e1 + uc * e2) / area
                    let sx = min(atlas.width - 1, max(0, Int(floor(coord.x + 0.5))))
                    let sy = min(atlas.height - 1, max(0, Int(floor(coord.y + 0.5))))
                    let offset = (sy * atlas.width + sx) * 4
                    let sourceAlpha = Float(atlas.rgba[offset + 3]) / 255
                    if sourceAlpha == 0 { continue }
                    let alpha = sourceAlpha * color.multiply.w
                    let straight = SIMD3(Float(atlas.rgba[offset]), Float(atlas.rgba[offset + 1]), Float(atlas.rgba[offset + 2])) / (sourceAlpha * 255)
                    let rgb = straight * SIMD3(color.multiply.x, color.multiply.y, color.multiply.z) + color.add
                    let source = SIMD4(max(0, min(1, rgb.x)) * alpha, max(0, min(1, rgb.y)) * alpha,
                                       max(0, min(1, rgb.z)) * alpha, alpha)
                    let at = y * dimension + x
                    pixels[at] = try Self.blend(source: source, destination: pixels[at], mode: blend)
                }
            }
        }
    }

    private func edge(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ p: SIMD2<Double>) -> Double {
        (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
    }
    private func inside(_ value: Double, from a: SIMD2<Double>, to b: SIMD2<Double>) -> Bool {
        if value > 1e-9 { return true }
        if value < -1e-9 { return false }
        // Half-open edges assign a shared strip edge to exactly one triangle.
        let d = b - a
        return d.y < 0 || (abs(d.y) < 1e-12 && d.x > 0)
    }

    static func blend(source: SIMD4<Float>, destination: SIMD4<Float>, mode: Int) throws -> SIMD4<Float> {
        let mixed: SIMD4<Float>
        switch mode {
        case 0: mixed = source + destination * (1 - source.w)
        case 8: mixed = source + destination // GL_ONE, GL_ONE
        case 4: mixed = source + destination * (SIMD4(repeating: 1) - source) // GL_ONE, GL_ONE_MINUS_SRC_COLOR
        default: throw ArenaFaceError.invalid("Unsupported face blend mode \(mode)")
        }
        return SIMD4(max(0, min(1, mixed.x)), max(0, min(1, mixed.y)),
                     max(0, min(1, mixed.z)), max(0, min(1, mixed.w)))
    }
}

struct ArenaFacePixels {
    let width: Int
    let height: Int
    /// RGBA8, premultiplied; row zero is the image's first scanline.
    let rgba: [UInt8]

    init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width; self.height = height; self.rgba = rgba
    }

    init(data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0, image.height > 0, image.width <= 8192, image.height <= 8192,
              image.width * image.height <= 32_000_000 else {
            throw ArenaFaceError.invalid("Unreadable or excessive face bitmap")
        }
        let w = image.width, h = image.height
        width = w; height = h
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let okay = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let color = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: raw.baseAddress, width: w, height: h,
                    bitsPerComponent: 8, bytesPerRow: w * 4, space: color,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
            return true
        }
        guard okay else { throw ArenaFaceError.invalid("Unable to decode face bitmap pixels") }
        rgba = bytes
    }

    func image() throws -> UIImage {
        guard width > 0, height > 0, rgba.count == width * height * 4,
              let color = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: width * 4, space: color,
                    bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw ArenaFaceError.invalid("Unable to create the composited face texture")
        }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }
}
