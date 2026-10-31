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
    indirect enum Operation {
        case draw(Draw)
        case layer([Operation], blendMode: Int, bounds: Rect)
        case masked(mask: [Operation], content: [Operation], bounds: Rect)
        var bounds: Rect {
            switch self {
            case .draw(let draw): return draw.bounds
            case .layer(_, _, let bounds), .masked(_, _, let bounds): return bounds
            }
        }
    }
    struct Frame {
        let operations: [Operation]
        let clipFrames: [Int: Int]
        let sourceTime: Double
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

    init(document: ArenaLobbyTimelineDocument, exportName: String, sourceRect: [Double]? = nil) throws {
        guard document.schemaVersion == 1, document.canvasSize.count == 2,
              document.canvasSize.allSatisfy({ (1...4096).contains($0) }),
              document.sourceRect.count == 4, document.sourceRect.allSatisfy(\.isFinite),
              document.uvDivisor == 65_535, document.primitiveMode == "triangle_strip",
              document.clockPolicy == "independent_absolute_clip_fps",
              (1...16).contains(document.textures.count), document.objects.count <= 50_000,
              document.matrices.count <= 1_000_000, document.colors.count <= 500_000,
              document.exclusions.count <= 128,
              let selected = document.exports[exportName], selected.status == "ready" else {
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
        try validate()
        try verifyOffscreenExclusions()
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
            guard item.textField == nil, item.scalingGrid == nil,
                  item.modifier == nil || [38, 39, 40].contains(item.modifier!) else {
                throw ArenaLobbyTimelineError.invalid("Lobby export needs text, nine-slice or unknown modifier support")
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
                      item.frameLabels?.count == count else { throw ArenaLobbyTimelineError.invalid("Invalid lobby clock") }
                reachableClocks.insert(id)
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
                        if ![0, 4, 8].contains(child.blendMode) {
                            guard let proofID = child.excludedByProof, let proof = proofs[proofID],
                                  child.blendMode == 64, proof.kind == "complete_timeline_outside_viewport",
                                  proof.parentObjectID == id, proof.childIndex == e[0], proof.objectID == child.objectID,
                                  proof.blendMode == child.blendMode, proof.exportName == exportName,
                                  proof.sourceSCSHA256 == document.sourceSCSHA256,
                                  proof.sourceRect == sourceRect.values, proof.fps == 60,
                                  (1...36_000).contains(proof.periodFrames), (2...16).contains(proof.margin) else {
                                throw ArenaLobbyTimelineError.invalid("Unsupported lobby blend without a complete viewport proof")
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
            } else if item.commands.isEmpty && item.modifier == nil {
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

    func frame(time: Double) throws -> Frame {
        guard time.isFinite, time >= 0 else { throw ArenaLobbyTimelineError.invalid("Invalid lobby sample time") }
        frameLookups = Dictionary(uniqueKeysWithValues: reachableClocks.map { id in
            let item = objects[id]!
            return (id, Self.frameIndex(time: time, fps: item.fps!, count: item.frameCount!))
        })
        var totalVertices = 0
        func union(_ ops: [Operation]) -> Rect? { ops.map(\.bounds).reduce(nil) { a,b in a.map { $0.union(b) } ?? b } }
        func draw(_ id: Int, transform: Affine, color: Color, depth: Int) throws -> [Operation] {
            guard depth < 48, let item = objects[id] else { throw ArenaLobbyTimelineError.invalid("Lobby drawing depth exceeded") }
            var output: [Operation] = []
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
            for e in elements(id, frame: frameLookups[id] ?? 0) {
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
                var next = try draw(child.objectID, transform: matrix, color: tint, depth: depth+1)
                if child.blendMode != 0, let bounds = union(next) {
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
        return Frame(operations: try draw(root, transform: .identity, color: .identity, depth: 0),
                     clipFrames: frameLookups, sourceTime: time)
    }
}
