import Foundation

enum ArenaLobbyTimelineError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

/// Source-only values are retained for the HUD adapter, including properties
/// that are not interpreted by the background renderer.
indirect enum ArenaLobbyTimelineJSONValue: Decodable, Sendable {
    case string(String), number(Double), bool(Bool)
    case array([ArenaLobbyTimelineJSONValue]), object([String: ArenaLobbyTimelineJSONValue]), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(Bool.self) { self = .bool(item) }
        else if let item = try? value.decode(Double.self) { self = .number(item) }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode([ArenaLobbyTimelineJSONValue].self) { self = .array(item) }
        else { self = .object(try value.decode([String: ArenaLobbyTimelineJSONValue].self)) }
    }

    var number: Double? { if case .number(let value) = self { return value }; return nil }
    var string: String? { if case .string(let value) = self { return value }; return nil }
}

/// Bindings address instances, not object IDs: one source clip can be reused
/// for multiple counters with different values. Empty names use #childIndex.
struct ArenaLobbyInterfaceState: Equatable, Sendable {
    var text: [String: String] = [:]
    var frames: [String: String] = [:]
    var hidden: Set<String> = []
    /// Zero-based source frames for unlabeled progress bars and icon variants.
    /// A numeric binding freezes only this instance, not its child animations.
    var frameIndices: [String: Int] = [:]
    /// Play this instance once from frame zero, then hold the specified rest
    /// frame. Child clocks use the same event epoch, never an endless loop.
    var oneShotRestFrames: [String: Int] = [:]
}

struct ArenaLobbySourceText: Hashable, Sendable {
    let fontName: String
    let size: Double
    let rect: [Double]
    let color: UInt32
    let outlineColor: UInt32
    let outlined: Bool
    let multiline: Bool
    let deviceFont: Bool
    let alignment: Int

    init(_ fields: [String: ArenaLobbyTimelineJSONValue]) throws {
        guard let font = fields["fontName"]?.string, !font.isEmpty, font.utf8.count <= 240,
              let size = fields["fontSize"]?.number, size.isFinite, (0...255).contains(size),
              let left = fields["left"]?.number, let top = fields["top"]?.number,
              let right = fields["right"]?.number, let bottom = fields["bottom"]?.number,
              [left,top,right,bottom].allSatisfy({ $0.isFinite && abs($0) <= 65_536 }),
              right > left, bottom > top, right-left <= 4096, bottom-top <= 4096,
              let color = fields["fontColor"]?.number, color.rounded() == color,
              (0...Double(UInt32.max)).contains(color),
              let outline = fields["outlineColor"]?.number, outline.rounded() == outline,
              (0...Double(UInt32.max)).contains(outline),
              let styles = fields["styles"]?.number, styles.rounded() == styles, (0...127).contains(styles),
              let align = fields["align"]?.number, align.rounded() == align, (0...255).contains(align) else {
            throw ArenaLobbyTimelineError.invalid("Invalid source text geometry or typography")
        }
        fontName = font; self.size = size; rect = [left,top,right,bottom]
        self.color = UInt32(color); outlineColor = UInt32(outline)
        outlined = Int(styles) & 2 != 0; multiline = Int(styles) & 16 != 0
        deviceFont = Int(styles) & 1 != 0
        alignment = Int(align)
    }
}

struct ArenaLobbyTimelineDocument: Decodable, Sendable {
    struct Texture: Decodable, Sendable {
        let file: String
        let width: Int
        let height: Int
        let sha256: String
        let alphaEncoding: String
    }
    struct Object: Decodable, Sendable {
        struct Command: Decodable, Sendable { let textureIndex: Int; let vertices: [[Double]] }
        struct Child: Decodable, Sendable {
            let objectID: Int
            let name: String
            let blendMode: Int
            let excludedByProof: String?
        }
        struct Frame: Decodable, Sendable { let `repeat`: Int; let elements: [[Int]] }
        let id: Int
        let commands: [Command]
        let modifier: Int?
        let textField: [String: ArenaLobbyTimelineJSONValue]?
        let scalingGrid: [String: Double]?
        let fps: Double?
        let frameCount: Int?
        let children: [Child]?
        let frames: [Frame]?
        let frameLabels: [String]?
    }
    struct Export: Decodable, Sendable { let objectID: Int; let status: String }
    struct Exclusion: Decodable, Sendable {
        let id: String
        let kind: String
        let exportName: String
        let sourceSCSHA256: String
        let parentObjectID: Int
        let childIndex: Int
        let objectID: Int
        let blendMode: Int
        let sourceRect: [Double]
        let margin: Double
        let fps: Double
        let periodFrames: Int
    }
    let schemaVersion: Int
    let sourceSCMember: String
    let sourceSCSHA256: String
    let canvasSize: [Int]
    let sourceRect: [Double]
    let uvDivisor: Double
    let primitiveMode: String
    let clockPolicy: String
    let textures: [Texture]
    let objects: [String: Object]
    let matrices: [[Double]]
    let colors: [[Double]]
    let exports: [String: Export]
    let exclusions: [Exclusion]
}

/// A source display list and independent clip clocks. This class performs only
/// bounded geometry and state traversal; the full-screen pixels stay on Metal.
/// It does not change ArenaFaceScene's fixed canvas or material behavior.
final class ArenaLobbyTimelineScene {
    struct Rect: Equatable, Sendable {
        let minX, minY, maxX, maxY: Double
        var width: Double { maxX - minX }
        var height: Double { maxY - minY }
        var values: [Double] { [minX, minY, maxX, maxY] }

        init(_ values: [Double]) {
            minX = values[0]; minY = values[1]; maxX = values[2]; maxY = values[3]
        }
        func intersection(_ other: Rect) -> Rect? {
            let result = Rect([max(minX, other.minX), max(minY, other.minY),
                               min(maxX, other.maxX), min(maxY, other.maxY)])
            return result.width > 0 && result.height > 0 ? result : nil
        }
        func union(_ other: Rect) -> Rect {
            Rect([min(minX, other.minX), min(minY, other.minY),
                  max(maxX, other.maxX), max(maxY, other.maxY)])
        }
        func outside(_ other: Rect, margin: Double) -> Bool {
            maxX + margin <= other.minX || minX - margin >= other.maxX
                || maxY + margin <= other.minY || minY - margin >= other.maxY
        }
    }

    struct Affine: Sendable {
        let a, b, c, d, tx, ty: Double
        static let identity = Affine([1, 0, 0, 1, 0, 0])
        init(_ v: [Double]) { a = v[0]; b = v[1]; c = v[2]; d = v[3]; tx = v[4]; ty = v[5] }
        func appending(_ m: Affine) -> Affine {
            Affine([a*m.a+b*m.c, a*m.b+b*m.d, c*m.a+d*m.c, c*m.b+d*m.d,
                    a*m.tx+b*m.ty+tx, c*m.tx+d*m.ty+ty])
        }
        func point(_ v: [Double]) -> SIMD2<Double> { SIMD2(a*v[0]+b*v[1]+tx, c*v[0]+d*v[1]+ty) }
    }

    struct Color: Sendable {
        let multiply: SIMD4<Float>
        let add: SIMD4<Float>
        static let identity = Color(multiply: SIMD4(repeating: 1), add: .zero)
        init(multiply: SIMD4<Float>, add: SIMD4<Float>) { self.multiply = multiply; self.add = add }
        init(_ v: [Double]) {
            multiply = SIMD4(Float(v[0]/255), Float(v[1]/255), Float(v[2]/255), Float(v[3]/255))
            add = SIMD4(Float(v[4]/255), Float(v[5]/255), Float(v[6]/255), 0)
        }
        func appending(_ child: Color) -> Color {
            Color(multiply: multiply * child.multiply, add: multiply * child.add + add)
        }
    }

    /// Keep this layout in sync with ArenaLobbyTimelineShaders.Vertex (48 bytes).
    struct Vertex {
        var position: SIMD2<Float>
        var uv: SIMD2<Float>
        var multiply: SIMD4<Float>
        var add: SIMD4<Float>
    }
    struct Draw {
        let textureIndex: Int
        let vertices: [Vertex]
        let bounds: Rect
        let blendMode: Int
    }
    struct TextDraw {
        let style: ArenaLobbySourceText
        let value: String
        let transform: Affine
        let color: Color
        let bounds: Rect
    }
    indirect enum Operation {
        case draw(Draw)
        case text(TextDraw)
        case layer([Operation], blendMode: Int, bounds: Rect)
        case masked(mask: [Operation], content: [Operation], bounds: Rect)
        var bounds: Rect {
            switch self {
            case .draw(let draw): return draw.bounds
            case .text(let text): return text.bounds
            case .layer(_, _, let bounds), .masked(_, _, let bounds): return bounds
            }
        }
    }
    struct Frame {
        let operations: [Operation]
        let clipFrames: [Int: Int]
        let sourceTime: Double
        /// Empty source `hit_area` / `bounds` text rectangles in canvas space.
        /// Native controls can use these without drawing marker glyphs.
        let layoutRegions: [String: Rect]
    }

    /// Match the compositor's bounded, 16-pixel texture buckets before it
    /// allocates any intermediate. The final drawable keeps its native size.
    /// Fixed density tiers avoid retaining a different bucket every frame.
    static func intermediateDensity(operations: [Operation], sourceRect: Rect, requested: Double) throws -> Double {
        guard requested.isFinite, requested > 0 else {
            throw ArenaLobbyTimelineError.invalid("Invalid lobby intermediate density")
        }
        for tier in [2.0, 1.5, 1.0] {
            let density = min(max(1, requested), tier)
            if intermediatePixels(operations: operations, sourceRect: sourceRect, density: density) <= 16_000_000 {
                return density
            }
        }
        throw ArenaLobbyTimelineError.invalid("Lobby intermediate textures exceed their frame budget")
    }

    static func intermediatePixels(operations: [Operation], sourceRect: Rect, density: Double) -> Int {
        guard density.isFinite, density > 0, density <= 1_000_000 else { return Int.max }
        var pixels = 0
        func allocate(_ rect: Rect) {
            let w = ((Int(ceil(rect.width*density))+15)/16)*16
            let h = ((Int(ceil(rect.height*density))+15)/16)*16
            guard w > 0, h > 0, w <= 8192, h <= 8192,
                  pixels <= Int.max - w*h else { pixels = Int.max; return }
            pixels += w*h
        }
        func texture(_ children: [Operation], _ bounds: Rect) -> Rect? {
            guard let rect = Rect([floor(bounds.minX)-1,floor(bounds.minY)-1,
                                   ceil(bounds.maxX)+1,ceil(bounds.maxY)+1]).intersection(sourceRect) else { return nil }
            prepare(children, mask: nil)
            allocate(rect)
            return rect
        }
        func prepare(_ children: [Operation], mask: Rect?) {
            for child in children {
                switch child {
                case .draw, .text: break
                case .layer(let content, let blend, let bounds):
                    if blend != 3, content.count == 1, case .draw(let draw) = content[0], draw.blendMode == 0 { continue }
                    _ = texture(content, bounds)
                case .masked(let maskOperations, let content, let bounds):
                    let maskBounds = maskOperations.map(\.bounds).reduce(nil as Rect?) { a,b in a.map { $0.union(b) } ?? b }
                    guard let maskBounds, let tight = maskBounds.intersection(bounds),
                          var combined = texture(maskOperations, tight) else { continue }
                    if let mask {
                        guard let rect = combined.intersection(mask) else { continue }
                        allocate(rect); combined = rect
                    }
                    prepare(content, mask: combined)
                }
            }
        }
        prepare(operations, mask: nil)
        return pixels
    }

    let document: ArenaLobbyTimelineDocument
    let sourceRect: Rect
    let exportName: String
    let root: Int
    private let objects: [Int: ArenaLobbyTimelineDocument.Object]
    private let matrices: [Affine]
    private let colors: [Color]
    private let proofs: [String: ArenaLobbyTimelineDocument.Exclusion]
    private var frameEnds: [Int: [Int]] = [:]
    private var reachableClocks = Set<Int>()
    private var frameLookups: [Int: Int] = [:]
    private var textStyles: [Int: ArenaLobbySourceText] = [:]
    private var childSegments: [Int: [String]] = [:]
    var interfaceState: ArenaLobbyInterfaceState? {
        didSet { if oldValue != interfaceState { interfaceBindingsValidated = false } }
    }
    private var interfaceBindingsValidated = false
    private var instanceObjects: [String: Int]?
    private var layoutMarkerPaths = Set<String>()
    private var conditionalBlendPaths = Set<String>()

    init(document: ArenaLobbyTimelineDocument, exportName: String, sourceRect: [Double]? = nil,
         interfaceState: ArenaLobbyInterfaceState? = nil) throws {
        guard document.schemaVersion == 1, document.canvasSize.count == 2,
              document.canvasSize.allSatisfy({ (1...4096).contains($0) }),
              document.sourceRect.count == 4, document.sourceRect.allSatisfy(\.isFinite),
              document.uvDivisor == 65_535, document.primitiveMode == "triangle_strip",
              document.clockPolicy == "independent_absolute_clip_fps",
              (1...16).contains(document.textures.count), document.objects.count <= 50_000,
              document.matrices.count <= 1_000_000, document.colors.count <= 500_000,
              document.exclusions.count <= 128,
              let selected = document.exports[exportName],
              selected.status == "ready" || (interfaceState != nil && selected.status == "requires_layout_text_and_state_bindings") else {
            throw ArenaLobbyTimelineError.invalid("Unsupported or unbound lobby scene")
        }
        let viewport = sourceRect ?? document.sourceRect
        guard viewport.count == 4, viewport.allSatisfy({ $0.isFinite && abs($0) <= 1e6 }),
              viewport[2] > viewport[0], viewport[3] > viewport[1],
              viewport[2]-viewport[0] <= 8192, viewport[3]-viewport[1] <= 8192,
              document.matrices.allSatisfy({ $0.count == 6 && $0.allSatisfy { $0.isFinite && abs($0) <= 1e8 } }),
              document.colors.allSatisfy({ $0.count == 7 && $0.allSatisfy { $0.isFinite && (0...255).contains($0) } }) else {
            throw ArenaLobbyTimelineError.invalid("Invalid lobby source viewport, matrix or color")
        }
        var indexed: [Int: ArenaLobbyTimelineDocument.Object] = [:]
        for (key, object) in document.objects {
            guard Int(key) == object.id, indexed[object.id] == nil else {
                throw ArenaLobbyTimelineError.invalid("Duplicate lobby object identity")
            }
            indexed[object.id] = object
        }
        var proofTable: [String: ArenaLobbyTimelineDocument.Exclusion] = [:]
        for proof in document.exclusions {
            guard proofTable[proof.id] == nil else { throw ArenaLobbyTimelineError.invalid("Duplicate lobby exclusion proof") }
            proofTable[proof.id] = proof
        }
        self.document = document
        self.exportName = exportName
        self.sourceRect = Rect(viewport)
        root = selected.objectID
        objects = indexed
        matrices = document.matrices.map(Affine.init)
        colors = document.colors.map(Color.init)
        proofs = proofTable
        self.interfaceState = interfaceState
        try validate()
        try verifyOffscreenExclusions()
        if interfaceState != nil { try validateInterfaceBindings() }
    }

    static func frameIndex(time: Double, fps: Double, count: Int) -> Int {
        guard time.isFinite, time >= 0, fps.isFinite, fps > 0, count > 0 else { return 0 }
        let elapsed = time * fps
        guard elapsed.isFinite else { return 0 }
        let nearest = elapsed.rounded()
        let stable = abs(elapsed-nearest) <= max(1e-9, elapsed.ulp*2) ? nearest : floor(elapsed)
        return max(0, Int(stable.truncatingRemainder(dividingBy: Double(count))))
    }

    private func validate() throws {
        for texture in document.textures {
            guard texture.alphaEncoding == "straight", texture.width > 0, texture.height > 0,
                  texture.width <= 8192, texture.height <= 8192, texture.width * texture.height <= 32_000_000,
                  !texture.file.isEmpty, texture.sha256.count == 64 else {
                throw ArenaLobbyTimelineError.invalid("Invalid lobby atlas declaration")
            }
        }
        var visited = Set<Int>()
        func walk(_ id: Int, ancestry: Set<Int>) throws {
            guard ancestry.count < 48, !ancestry.contains(id), let item = objects[id] else {
                throw ArenaLobbyTimelineError.invalid("Missing or cyclic lobby object")
            }
            if visited.contains(id) { return }
            visited.insert(id)
            guard item.modifier == nil || [38, 39, 40].contains(item.modifier!) else {
                throw ArenaLobbyTimelineError.invalid("Unknown source modifier")
            }
            if let fields = item.textField {
                guard interfaceState != nil else {
                    throw ArenaLobbyTimelineError.invalid("Source text requires interface bindings")
                }
                textStyles[id] = try ArenaLobbySourceText(fields)
            }
            if let grid = item.scalingGrid {
                guard interfaceState != nil, let left = grid["left"], let top = grid["top"],
                      let right = grid["right"], let bottom = grid["bottom"],
                      [left,top,right,bottom].allSatisfy({ $0.isFinite && abs($0) <= 65_536 }),
                      right >= left, bottom >= top else {
                    throw ArenaLobbyTimelineError.invalid("Invalid source scaling grid")
                }
                // Intrinsic source-size rendering does not resize the nine
                // regions. Keep the grid for a future explicit resize request;
                // never stretch a source button to an unrelated host rectangle.
            }
            for command in item.commands {
                guard document.textures.indices.contains(command.textureIndex), (3...8192).contains(command.vertices.count),
                      command.vertices.allSatisfy({ v in
                          v.count == 4 && v.allSatisfy(\.isFinite) && abs(v[0]) <= 1e6 && abs(v[1]) <= 1e6
                              && (0...65_535).contains(v[2]) && (0...65_535).contains(v[3])
                      }) else { throw ArenaLobbyTimelineError.invalid("Invalid lobby triangle strip") }
            }
            if let frames = item.frames {
                guard let count = item.frameCount, (1...100_000).contains(count),
                      let fps = item.fps, fps.isFinite, fps > 0, fps <= 240,
                      let children = item.children, frames.count <= count,
                      item.frameLabels?.count == count,
                      children.allSatisfy({ (0...255).contains($0.blendMode) }) else {
                    throw ArenaLobbyTimelineError.invalid("Invalid lobby clock or child blend declaration")
                }
                reachableClocks.insert(id)
                let nameCounts = Dictionary(grouping: children, by: \.name).mapValues(\.count)
                childSegments[id] = children.enumerated().map { index, child in
                    child.name.isEmpty || nameCounts[child.name, default: 0] > 1 ? "#\(index):\(child.name)" : child.name
                }
                var total = 0
                var ends: [Int] = []
                var next = ancestry
                next.insert(id)
                for group in frames {
                    guard group.repeat > 0, group.repeat <= count-total, group.elements.count <= 8192 else {
                        throw ArenaLobbyTimelineError.invalid("Invalid lobby frame run")
                    }
                    total += group.repeat
                    ends.append(total)
                    var capturing = false, hasMask = false, masking = false
                    for e in group.elements {
                        guard e.count == 3, children.indices.contains(e[0]),
                              e[1] == -1 || matrices.indices.contains(e[1]),
                              e[2] == -1 || colors.indices.contains(e[2]) else {
                            throw ArenaLobbyTimelineError.invalid("Invalid lobby frame reference")
                        }
                        let child = children[e[0]]
                        guard let target = objects[child.objectID] else { throw ArenaLobbyTimelineError.invalid("Missing lobby child") }
                        if let modifier = target.modifier {
                            switch modifier {
                            case 38:
                                guard !capturing, !masking else { throw ArenaLobbyTimelineError.invalid("Unbalanced lobby mask start") }
                                capturing = true; hasMask = false
                            case 39:
                                guard !capturing, hasMask else { throw ArenaLobbyTimelineError.invalid("Lobby mask content has no mask") }
                                masking = true
                            case 40:
                                guard !capturing, masking else { throw ArenaLobbyTimelineError.invalid("Unbalanced lobby mask end") }
                                masking = false; hasMask = false
                            default: throw ArenaLobbyTimelineError.invalid("Unknown lobby mask modifier")
                            }
                        } else if capturing { capturing = false; hasMask = true }
                        if ![0, 3, 4, 8].contains(child.blendMode) {
                            if child.excludedByProof == nil, interfaceState != nil, (0...255).contains(child.blendMode) {
                                // A UI adapter may explicitly disable this exact
                                // instance or an ancestor. Coverage is checked
                                // after indexing paths and on every state change.
                            } else {
                              guard let proofID = child.excludedByProof, let proof = proofs[proofID],
                                  child.blendMode == 64, proof.kind == "complete_timeline_outside_viewport",
                                  proof.parentObjectID == id, proof.childIndex == e[0], proof.objectID == child.objectID,
                                  proof.blendMode == child.blendMode, proof.exportName == exportName,
                                  proof.sourceSCSHA256 == document.sourceSCSHA256,
                                  proof.sourceRect == sourceRect.values, proof.fps == 60,
                                  (1...36_000).contains(proof.periodFrames), (2...16).contains(proof.margin) else {
                                throw ArenaLobbyTimelineError.invalid("Unsupported lobby blend without a complete viewport proof")
                              }
                            }
                        } else if child.excludedByProof != nil {
                            throw ArenaLobbyTimelineError.invalid("Unexpected exclusion of a supported lobby child")
                        }
                        try walk(child.objectID, ancestry: next)
                    }
                    guard !capturing else { throw ArenaLobbyTimelineError.invalid("Lobby mask has no source shape") }
                }
                guard total == count else { throw ArenaLobbyTimelineError.invalid("Lobby frame count mismatch") }
                frameEnds[id] = ends
                // Preserve and validate declared but currently unused children
                // too; later source states must not conceal cycles or bad data.
                for child in children { try walk(child.objectID, ancestry: next) }
            } else if item.commands.isEmpty && item.modifier == nil && item.textField == nil {
                throw ArenaLobbyTimelineError.invalid("Lobby object has no drawing data")
            }
        }
        try walk(root, ancestry: [])
    }

    private func elements(_ id: Int, frame: Int) -> [[Int]] {
        guard let object = objects[id], let frames = object.frames, let ends = frameEnds[id] else { return [] }
        var lower = 0, upper = ends.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if frame < ends[middle] { upper = middle } else { lower = middle + 1 }
        }
        return lower < frames.count ? frames[lower].elements : []
    }

    private func verifyOffscreenExclusions() throws {
        guard !proofs.isEmpty else { return }
        var containsProof: [Int: Bool] = [:]
        func hasProof(_ id: Int) -> Bool {
            if let value = containsProof[id] { return value }
            let result = (objects[id]?.children ?? []).contains { $0.excludedByProof != nil || hasProof($0.objectID) }
            containsProof[id] = result
            return result
        }
        func geometricBounds(_ id: Int, transform: Affine, frame: Int) -> Rect? {
            guard let item = objects[id] else { return nil }
            var result: Rect?
            for command in item.commands {
                let points = command.vertices.map(transform.point)
                guard let first = points.first else { continue }
                var x0 = first.x, y0 = first.y, x1 = first.x, y1 = first.y
                for p in points { x0 = min(x0,p.x); y0 = min(y0,p.y); x1 = max(x1,p.x); y1 = max(y1,p.y) }
                let bounds = Rect([x0,y0,x1,y1])
                result = result.map { $0.union(bounds) } ?? bounds
            }
            if let count = item.frameCount, let children = item.children {
                for e in elements(id, frame: frame % count) {
                    let matrix = e[1] == -1 ? Affine.identity : matrices[e[1]]
                    if let bounds = geometricBounds(children[e[0]].objectID, transform: transform.appending(matrix), frame: frame) {
                        result = result.map { $0.union(bounds) } ?? bounds
                    }
                }
            }
            return result
        }
        func verify(_ child: Int, transform: Affine, proof: ArenaLobbyTimelineDocument.Exclusion) throws {
            var seen = Set<Int>()
            func checkClocks(_ id: Int) throws {
                if seen.contains(id) { return }; seen.insert(id)
                guard let item = objects[id] else { throw ArenaLobbyTimelineError.invalid("Missing proof object") }
                if let count = item.frameCount {
                    guard item.fps == 60, proof.periodFrames % count == 0 else {
                        throw ArenaLobbyTimelineError.invalid("Lobby proof does not cover every descendant clock")
                    }
                }
                for node in item.children ?? [] { try checkClocks(node.objectID) }
            }
            try checkClocks(child)
            for frame in 0..<proof.periodFrames {
                guard let bounds = geometricBounds(child, transform: transform, frame: frame),
                      bounds.outside(sourceRect, margin: proof.margin) else {
                    throw ArenaLobbyTimelineError.invalid("Excluded lobby blend can enter the viewport")
                }
            }
        }
        var verified = Set<String>()
        func walk(_ id: Int, transform: Affine) throws {
            guard hasProof(id), let item = objects[id], let children = item.children else { return }
            guard item.frameCount == 1 else { throw ArenaLobbyTimelineError.invalid("Lobby exclusion has a moving ancestor") }
            for e in elements(id, frame: 0) {
                let child = children[e[0]]
                let matrix = transform.appending(e[1] == -1 ? .identity : matrices[e[1]])
                if let key = child.excludedByProof, let proof = proofs[key] {
                    try verify(child.objectID, transform: matrix, proof: proof)
                    verified.insert(key)
                } else { try walk(child.objectID, transform: matrix) }
            }
        }
        try walk(root, transform: .identity)
        guard verified == Set(proofs.keys) else { throw ArenaLobbyTimelineError.invalid("Unreachable or incomplete lobby proof") }
    }

    /// A mistyped path must not quietly leave a counter or state on its default
    /// source frame. Build the instance index once and validate only on changes.
    private func validateInterfaceBindings() throws {
        guard !interfaceBindingsValidated else { return }
        guard let state = interfaceState else {
            guard conditionalBlendPaths.isEmpty else {
                throw ArenaLobbyTimelineError.invalid("Conditional source layers require explicit interface visibility")
            }
            interfaceBindingsValidated = true; return
        }
        if instanceObjects == nil {
            var index: [String: Int] = [:]
            var markers = Set<String>()
            var conditional = Set<String>()
            func walk(_ id: Int, path: String, name: String, depth: Int) throws {
                guard depth < 48, index.count < 100_000, index[path] == nil else {
                    throw ArenaLobbyTimelineError.invalid("Ambiguous or oversized source interface instance tree")
                }
                index[path] = id
                if ["hit_area", "bounds"].contains(name), objects[id]?.textField?["text"]?.string == "" {
                    markers.insert(path)
                }
                for (offset, child) in (objects[id]?.children ?? []).enumerated() {
                    let segment = childSegments[id]![offset]
                    let childPath = path.isEmpty ? segment : path + "/" + segment
                    if ![0,3,4,8].contains(child.blendMode), child.excludedByProof == nil {
                        conditional.insert(childPath)
                    }
                    try walk(child.objectID, path: childPath,
                             name: child.name, depth: depth + 1)
                }
            }
            try walk(root, path: "", name: "", depth: 0)
            instanceObjects = index
            layoutMarkerPaths = markers
            conditionalBlendPaths = conditional
        }
        let index = instanceObjects!
        for (path, value) in state.text {
            guard let id = index[path], objects[id]?.textField != nil, value.utf8.count <= 4096,
                  !layoutMarkerPaths.contains(path) || value.isEmpty else {
                throw ArenaLobbyTimelineError.invalid("Invalid source text binding at \(path)")
            }
        }
        for (path, label) in state.frames {
            guard let id = index[path], !label.isEmpty, objects[id]?.frameLabels?.contains(label) == true,
                  state.frameIndices[path] == nil, state.oneShotRestFrames[path] == nil else {
                throw ArenaLobbyTimelineError.invalid("Invalid source named frame binding at \(path)")
            }
        }
        for (path, frame) in state.frameIndices {
            guard let id = index[path], let count = objects[id]?.frameCount, (0..<count).contains(frame),
                  state.oneShotRestFrames[path] == nil else {
                throw ArenaLobbyTimelineError.invalid("Invalid source numeric frame binding at \(path)")
            }
        }
        for (path, frame) in state.oneShotRestFrames {
            guard let id = index[path], let count = objects[id]?.frameCount, (0..<count).contains(frame) else {
                throw ArenaLobbyTimelineError.invalid("Invalid source one-shot binding at \(path)")
            }
        }
        guard state.hidden.allSatisfy({ index[$0] != nil }) else {
            throw ArenaLobbyTimelineError.invalid("Unknown source visibility binding")
        }
        for path in conditionalBlendPaths {
            var candidate = path
            var covered = state.hidden.contains("")
            while !candidate.isEmpty && !covered {
                covered = state.hidden.contains(candidate)
                candidate = candidate.lastIndex(of: "/").map { String(candidate[..<$0]) } ?? ""
            }
            guard covered else {
                throw ArenaLobbyTimelineError.invalid("Unsupported visible source blend at \(path)")
            }
        }
        interfaceBindingsValidated = true
    }

    func oneShotPlaybackCompleted(at time: Double) throws -> Bool {
        guard time.isFinite, time >= 0 else { throw ArenaLobbyTimelineError.invalid("Invalid lobby sample time") }
        try validateInterfaceBindings()
        guard let animations = interfaceState?.oneShotRestFrames, !animations.isEmpty else { return false }
        return animations.keys.allSatisfy { path in
            guard let id = instanceObjects?[path], let object = objects[id],
                  let count = object.frameCount, let fps = object.fps else { return false }
            return time >= Double(count) / fps
        }
    }

    /// Conservative local bounds across every active descendant frame. Cache
    /// per instance, so shared clips retain independent bindings. Composing
    /// rectangles may overestimate rotating particles, but never clips a frame
    /// or requires sampling a potentially enormous common clock period.
    func completeContentBounds() throws -> Rect? {
        try validateInterfaceBindings()
        var cache: [String: Rect] = [:]
        var empty = Set<String>()
        func visit(_ id: Int, path: String, depth: Int) throws -> Rect? {
            if let bounds = cache[path] { return bounds }
            if empty.contains(path) || interfaceState?.hidden.contains(path) == true { return nil }
            guard depth < 48, let item = objects[id] else {
                throw ArenaLobbyTimelineError.invalid("Source animation bounds exceed their depth budget")
            }
            var result: Rect?
            func include(_ rect: Rect) { result = result.map { $0.union(rect) } ?? rect }
            if let style = textStyles[id], !layoutMarkerPaths.contains(path) {
                guard let value = interfaceState?.text[path] else {
                    throw ArenaLobbyTimelineError.invalid("Unbound animated source text at \(path)")
                }
                if !value.isEmpty { include(Rect(style.rect)) }
            }
            for command in item.commands {
                let points = command.vertices
                include(Rect([points.map { $0[0] }.min()!,points.map { $0[1] }.min()!,
                              points.map { $0[0] }.max()!,points.map { $0[1] }.max()!]))
            }
            if let children = item.children, let frames = item.frames {
                let runs: [[[Int]]]
                if let frame = interfaceState?.frameIndices[path] { runs = [elements(id,frame:frame)] }
                else if let label = interfaceState?.frames[path], let frame = item.frameLabels?.firstIndex(of:label) {
                    runs = [elements(id,frame:frame)]
                } else { runs = frames.map(\.elements) }
                for run in runs {
                    for e in run {
                        let child = children[e[0]]
                        if child.excludedByProof != nil || objects[child.objectID]?.modifier != nil { continue }
                        let name = childSegments[id]![e[0]]
                        let childPath = path.isEmpty ? name : path + "/" + name
                        guard let r = try visit(child.objectID,path:childPath,depth:depth+1) else { continue }
                        let matrix = e[1] == -1 ? Affine.identity : matrices[e[1]]
                        let points = [[r.minX,r.minY],[r.maxX,r.minY],[r.minX,r.maxY],[r.maxX,r.maxY]].map(matrix.point)
                        include(Rect([points.map(\.x).min()!,points.map(\.y).min()!,
                                      points.map(\.x).max()!,points.map(\.y).max()!]))
                    }
                }
            }
            if let result { cache[path] = result } else { empty.insert(path) }
            return result
        }
        return try visit(root,path:"",depth:0)
    }

    func frame(time: Double) throws -> Frame {
        guard time.isFinite, time >= 0 else { throw ArenaLobbyTimelineError.invalid("Invalid lobby sample time") }
        try validateInterfaceBindings()
        frameLookups = Dictionary(uniqueKeysWithValues: reachableClocks.map { id in
            let item = objects[id]!
            return (id, Self.frameIndex(time: time, fps: item.fps!, count: item.frameCount!))
        })
        var layoutRegions: [String: Rect] = [:]
        var totalVertices = 0
        func union(_ ops: [Operation]) -> Rect? { ops.map(\.bounds).reduce(nil) { a,b in a.map { $0.union(b) } ?? b } }
        func draw(_ id: Int, path: String, transform: Affine, color: Color, depth: Int) throws -> [Operation] {
            guard depth < 48, let item = objects[id] else { throw ArenaLobbyTimelineError.invalid("Lobby drawing depth exceeded") }
            if interfaceState?.hidden.contains(path) == true { return [] }
            var output: [Operation] = []
            if let style = textStyles[id] {
                if layoutMarkerPaths.contains(path) {
                    let r = style.rect
                    let points = [[r[0],r[1]],[r[2],r[1]],[r[0],r[3]],[r[2],r[3]]].map(transform.point)
                    layoutRegions[path] = Rect([points.map(\.x).min()!,points.map(\.y).min()!,
                                               points.map(\.x).max()!,points.map(\.y).max()!])
                    return []
                }
                guard let value = interfaceState?.text[path], value.utf8.count <= 4096 else {
                    throw ArenaLobbyTimelineError.invalid("Unbound source text instance: \(path)")
                }
                if !value.isEmpty, color.multiply.w > 0 {
                    guard style.size > 0 else {
                        throw ArenaLobbyTimelineError.invalid("Source placeholder requires an explicit font size: \(path)")
                    }
                    let r = style.rect
                    let points = [[r[0],r[1]],[r[2],r[1]],[r[0],r[3]],[r[2],r[3]]].map(transform.point)
                    let bounds = Rect([points.map(\.x).min()!,points.map(\.y).min()!,points.map(\.x).max()!,points.map(\.y).max()!])
                    if let visible = bounds.intersection(sourceRect) {
                        output.append(.text(TextDraw(style: style, value: value, transform: transform, color: color, bounds: visible)))
                    }
                }
            }
            for command in item.commands {
                let points = command.vertices.map(transform.point)
                let bounds = Rect([points.map(\.x).min()!, points.map(\.y).min()!,
                                   points.map(\.x).max()!, points.map(\.y).max()!])
                guard let visible = bounds.intersection(sourceRect), color.multiply.w > 0 else { continue }
                var vertices: [Vertex] = []
                for index in 0..<(points.count-2) {
                    let ids = index.isMultiple(of: 2) ? [index,index+1,index+2] : [index,index+2,index+1]
                    let p = points[ids[0]], q = points[ids[1]], r = points[ids[2]]
                    if abs((q.x-p.x)*(r.y-p.y)-(q.y-p.y)*(r.x-p.x)) < 1e-10 { continue }
                    for index in ids {
                        let point = points[index], v = command.vertices[index]
                        vertices.append(Vertex(position: SIMD2(Float(point.x),Float(point.y)),
                            uv: SIMD2(Float(v[2]/document.uvDivisor),Float(v[3]/document.uvDivisor)),
                            multiply: color.multiply, add: color.add))
                    }
                }
                totalVertices += vertices.count
                guard totalVertices <= 1_000_000 else { throw ArenaLobbyTimelineError.invalid("Lobby frame geometry exceeds its budget") }
                if !vertices.isEmpty { output.append(.draw(Draw(textureIndex: command.textureIndex, vertices: vertices, bounds: visible, blendMode: 0))) }
            }
            guard let children = item.children else { return output }
            var captureNext = false, active = false
            var mask: [Operation] = [], content: [Operation] = []
            func flushMask() {
                if let a = union(mask), let b = union(content), let bounds = a.intersection(b) {
                    output.append(.masked(mask: mask, content: content, bounds: bounds))
                }
                content = []
            }
            var selectedFrame = frameLookups[id] ?? 0
            if let rest = interfaceState?.oneShotRestFrames[path], let count = item.frameCount, let fps = item.fps {
                selectedFrame = time >= Double(count)/fps ? rest : min(count-1,Int(floor(time*fps)))
            }
            if let index = interfaceState?.frameIndices[path] {
                guard interfaceState?.frames[path] == nil,
                      let count = item.frameCount, (0..<count).contains(index) else {
                    throw ArenaLobbyTimelineError.invalid("Invalid or conflicting source frame at \(path)")
                }
                selectedFrame = index
            }
            if let label = interfaceState?.frames[path] {
                guard !label.isEmpty, let index = item.frameLabels?.firstIndex(of: label) else {
                    throw ArenaLobbyTimelineError.invalid("Unknown source state label at \(path)")
                }
                selectedFrame = index
            }
            for e in elements(id, frame: selectedFrame) {
                let child = children[e[0]]
                if let modifier = objects[child.objectID]?.modifier {
                    switch modifier {
                    case 38: captureNext = true; mask = []
                    case 39: active = true
                    case 40: flushMask(); active = false; mask = []
                    default: throw ArenaLobbyTimelineError.invalid("Unknown lobby modifier at draw time")
                    }
                    continue
                }
                // validate() re-proves every excluded instance over its entire
                // period for this exact viewport before any frame is displayed.
                if child.excludedByProof != nil { continue }
                let matrix = transform.appending(e[1] == -1 ? .identity : matrices[e[1]])
                let tint = color.appending(e[2] == -1 ? .identity : colors[e[2]])
                let name = childSegments[id]![e[0]]
                let childPath = path.isEmpty ? name : path + "/" + name
                var next = try draw(child.objectID, path: childPath, transform: matrix, color: tint, depth: depth+1)
                if child.blendMode != 0, let bounds = union(next) {
                    guard [3,4,8].contains(child.blendMode) else {
                        throw ArenaLobbyTimelineError.invalid("Unsupported visible source blend at draw time")
                    }
                    // A non-normal child is composited as a group before its
                    // blend is applied. Flattening every triangle to ADD would
                    // change overlapping source graphics.
                    next = [.layer(next, blendMode: child.blendMode, bounds: bounds)]
                }
                if captureNext { mask = next; captureNext = false }
                else if active { content.append(contentsOf: next) }
                else { output.append(contentsOf: next) }
            }
            if active { flushMask() }
            return output
        }
        let operations = try draw(root, path: "", transform: .identity, color: .identity, depth: 0)
        return Frame(operations: operations, clipFrames: frameLookups, sourceTime: time, layoutRegions: layoutRegions)
    }
}
