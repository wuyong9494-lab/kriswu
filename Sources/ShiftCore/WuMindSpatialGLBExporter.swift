import Foundation

/// Pure-Swift glTF 2.0 Binary (`.glb`) Exporter & Validator for WUMIND Spatial 3D Studio.
/// Preserves EVERY architectural element as an independent named glTF node with articulated geometry
/// (plinth + hall body + pitched/double-tier roofs for palaces/gates, cylinders for circular stages,
/// cabinets + countertops, multi-tier trees) and PBR materials. Zero external dependencies.
public enum WuMindSpatialGLBExporter {

    public struct ValidationReport: Equatable, Sendable {
        public let byteCount: Int
        public let version: UInt32
        public let nodeCount: Int
        public let meshCount: Int
        public let materialCount: Int
        public let nodeNames: [String]

        public init(
            byteCount: Int,
            version: UInt32,
            nodeCount: Int,
            meshCount: Int,
            materialCount: Int,
            nodeNames: [String]
        ) {
            self.byteCount = byteCount
            self.version = version
            self.nodeCount = nodeCount
            self.meshCount = meshCount
            self.materialCount = materialCount
            self.nodeNames = nodeNames
        }
    }

    public enum ExporterError: LocalizedError, Equatable, Sendable {
        case emptyScene
        case invalidGLBHeader
        case invalidGLBJSON
        case truncatedGLBChunk

        public var errorDescription: String? {
            switch self {
            case .emptyScene: return "场景内没有可导出的可见构件。"
            case .invalidGLBHeader: return "GLB 文件头校验失败。"
            case .invalidGLBJSON: return "GLB JSON 场景树校验失败。"
            case .truncatedGLBChunk: return "GLB 二进制数据块长度不一致。"
            }
        }
    }

    private struct RawPrimitive {
        var positions: [Float] // x, y, z triples
        var normals: [Float]   // nx, ny, nz triples
        var indices: [UInt16]
        var materialIndex: Int
    }

    private struct MaterialSpec: Hashable {
        let name: String
        let hex: String
        let roughness: Double
        let metalness: Double
        let opacity: Double
    }

    public static func exportGLB(scene: WuMindSpatialSceneDocument) throws -> Data {
        let visibleNodes = scene.nodes.filter(\.isVisible)
        guard !visibleNodes.isEmpty else { throw ExporterError.emptyScene }

        var binaryData = Data()
        var bufferViews: [[String: Any]] = []
        var accessors: [[String: Any]] = []
        var meshes: [[String: Any]] = []
        var gltfNodes: [[String: Any]] = []
        var rootNodeIndices: [Int] = []

        var materialIndexMap: [MaterialSpec: Int] = [:]
        var materialsJSON: [[String: Any]] = []

        func materialIndex(for spec: MaterialSpec) -> Int {
            if let existing = materialIndexMap[spec] { return existing }
            let idx = materialsJSON.count
            materialIndexMap[spec] = idx
            let rgba = parseHexRGBA(spec.hex, alpha: spec.opacity)
            var mat: [String: Any] = [
                "name": spec.name,
                "pbrMetallicRoughness": [
                    "baseColorFactor": rgba,
                    "metallicFactor": spec.metalness,
                    "roughnessFactor": spec.roughness,
                ],
                "doubleSided": true,
            ]
            if spec.opacity < 0.99 {
                mat["alphaMode"] = "BLEND"
            }
            materialsJSON.append(mat)
            return idx
        }

        func appendBufferView(bytes: Data, target: Int) -> Int {
            while binaryData.count % 4 != 0 { binaryData.append(0) }
            let offset = binaryData.count
            binaryData.append(bytes)
            let bvIdx = bufferViews.count
            bufferViews.append([
                "buffer": 0,
                "byteOffset": offset,
                "byteLength": bytes.count,
                "target": target,
            ])
            return bvIdx
        }

        func buildMesh(name: String, primitives: [RawPrimitive]) -> Int {
            var primArray: [[String: Any]] = []
            for prim in primitives where !prim.indices.isEmpty {
                var posBytes = Data(capacity: prim.positions.count * 4)
                var minX = Float.greatestFiniteMagnitude, minY = Float.greatestFiniteMagnitude, minZ = Float.greatestFiniteMagnitude
                var maxX = -Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude, maxZ = -Float.greatestFiniteMagnitude
                let vertexCount = prim.positions.count / 3
                for v in 0..<vertexCount {
                    let x = prim.positions[v * 3]
                    let y = prim.positions[v * 3 + 1]
                    let z = prim.positions[v * 3 + 2]
                    minX = min(minX, x); minY = min(minY, y); minZ = min(minZ, z)
                    maxX = max(maxX, x); maxY = max(maxY, y); maxZ = max(maxZ, z)
                    appendFloat32(x, to: &posBytes)
                    appendFloat32(y, to: &posBytes)
                    appendFloat32(z, to: &posBytes)
                }

                var normBytes = Data(capacity: prim.normals.count * 4)
                for f in prim.normals { appendFloat32(f, to: &normBytes) }

                var idxBytes = Data(capacity: prim.indices.count * 2)
                for idx in prim.indices { appendUInt16(idx, to: &idxBytes) }

                let posBV = appendBufferView(bytes: posBytes, target: 34962)
                let normBV = appendBufferView(bytes: normBytes, target: 34962)
                let idxBV = appendBufferView(bytes: idxBytes, target: 34963)

                let posAcc = accessors.count
                accessors.append([
                    "bufferView": posBV,
                    "componentType": 5126,
                    "count": vertexCount,
                    "type": "VEC3",
                    "min": [Double(minX), Double(minY), Double(minZ)],
                    "max": [Double(maxX), Double(maxY), Double(maxZ)],
                ])

                let normAcc = accessors.count
                accessors.append([
                    "bufferView": normBV,
                    "componentType": 5126,
                    "count": vertexCount,
                    "type": "VEC3",
                ])

                let idxAcc = accessors.count
                accessors.append([
                    "bufferView": idxBV,
                    "componentType": 5123,
                    "count": prim.indices.count,
                    "type": "SCALAR",
                ])

                primArray.append([
                    "attributes": [
                        "POSITION": posAcc,
                        "NORMAL": normAcc,
                    ],
                    "indices": idxAcc,
                    "material": prim.materialIndex,
                ])
            }
            let meshIdx = meshes.count
            meshes.append([
                "name": name,
                "primitives": primArray,
            ])
            return meshIdx
        }

        let snowMatIdx = materialIndex(for: MaterialSpec(
            name: "SnowCap",
            hex: "#F4F8FC",
            roughness: 0.78,
            metalness: 0.02,
            opacity: 1.0
        ))
        let marbleMatIdx = materialIndex(for: MaterialSpec(
            name: "WhiteMarble",
            hex: WuMindSpatialMaterialPreset.whiteMarble.hexColor,
            roughness: 0.45,
            metalness: 0.04,
            opacity: 1.0
        ))
        let brickMatIdx = materialIndex(for: MaterialSpec(
            name: "GreyBrick",
            hex: WuMindSpatialMaterialPreset.greyBrick.hexColor,
            roughness: 0.85,
            metalness: 0.02,
            opacity: 1.0
        ))

        for node in visibleNodes {
            let w = node.sizeMM.xMeters
            let h = node.sizeMM.yMeters
            let d = node.sizeMM.zMeters

            let bodySpec = MaterialSpec(
                name: node.material.preset.rawValue,
                hex: node.material.primaryHex,
                roughness: node.material.preset.roughness,
                metalness: node.material.preset.metalness,
                opacity: node.material.opacity
            )
            let bodyMatIdx = materialIndex(for: bodySpec)
            let roofPreset = node.material.roofPreset ?? .glazedGoldTile
            let roofSpec = MaterialSpec(
                name: "roof_\(roofPreset.rawValue)",
                hex: node.material.roofHex ?? roofPreset.hexColor,
                roughness: roofPreset.roughness,
                metalness: roofPreset.metalness,
                opacity: 1.0
            )
            let roofMatIdx = materialIndex(for: roofSpec)

            var prims: [RawPrimitive] = []

            switch node.category {
            case .palaceHall, .gateTower:
                let plinthH = min(h * 0.48, max(0.35, Float(node.detailProfile.plinthHeightMM) / 1000.0))
                let bodyH = max(0.8, (h - plinthH) * 0.56)
                let roofH = max(0.6, h - plinthH - bodyH)
                let baseMat = node.category == .gateTower ? brickMatIdx : marbleMatIdx

                // 1. Stepped Plinth / City Wall Base
                prims.append(makeBoxPrimitive(cx: 0, cy: plinthH / 2, cz: 0, w: w * 1.06, h: plinthH, d: d * 1.08, materialIndex: baseMat))
                // 2. Crimson Hall Body
                prims.append(makeBoxPrimitive(cx: 0, cy: plinthH + bodyH / 2, cz: 0, w: w * 0.90, h: bodyH, d: d * 0.84, materialIndex: bodyMatIdx))
                // 3. Overhanging Pitched Imperial Roof (plus optional 2nd eave tier)
                let roofBaseY = plinthH + bodyH
                if node.detailProfile.eaveTiers >= 2 {
                    let lowerH = roofH * 0.46
                    let upperH = roofH * 0.54
                    prims.append(makeHipRoofPrimitive(cx: 0, baseY: roofBaseY, cz: 0, w: w * 1.12, h: lowerH, d: d * 1.12, ridgeRatio: 0.58, materialIndex: roofMatIdx))
                    prims.append(makeHipRoofPrimitive(cx: 0, baseY: roofBaseY + lowerH * 0.78, cz: 0, w: w * 0.86, h: upperH, d: d * 0.86, ridgeRatio: 0.50, materialIndex: roofMatIdx))
                    if scene.weather == .snowy {
                        prims.append(makeHipRoofPrimitive(cx: 0, baseY: roofBaseY + lowerH * 0.82 + 0.08, cz: 0, w: w * 0.82, h: upperH * 0.96, d: d * 0.82, ridgeRatio: 0.48, materialIndex: snowMatIdx))
                    }
                } else {
                    prims.append(makeHipRoofPrimitive(cx: 0, baseY: roofBaseY, cz: 0, w: w * 1.10, h: roofH, d: d * 1.10, ridgeRatio: 0.54, materialIndex: roofMatIdx))
                    if scene.weather == .snowy {
                        prims.append(makeHipRoofPrimitive(cx: 0, baseY: roofBaseY + 0.08, cz: 0, w: w * 1.04, h: roofH * 0.96, d: d * 1.04, ridgeRatio: 0.52, materialIndex: snowMatIdx))
                    }
                }

            case .cityWall:
                let copingH = min(0.55, h * 0.14)
                prims.append(makeBoxPrimitive(cx: 0, cy: (h - copingH) / 2, cz: 0, w: w, h: h - copingH, d: d, materialIndex: bodyMatIdx))
                prims.append(makeBoxPrimitive(cx: 0, cy: h - copingH / 2, cz: 0, w: w * 1.08, h: copingH, d: d * 1.01, materialIndex: scene.weather == .snowy ? snowMatIdx : roofMatIdx))

            case .cabinet:
                let topH: Float = 0.06
                prims.append(makeBoxPrimitive(cx: 0, cy: (h - topH) / 2, cz: 0, w: w, h: max(0.1, h - topH), d: d, materialIndex: bodyMatIdx))
                prims.append(makeBoxPrimitive(cx: 0, cy: h - topH / 2, cz: 0, w: w + 0.02, h: topH, d: d + 0.02, materialIndex: node.material.roofPreset != nil ? roofMatIdx : marbleMatIdx))

            case .exhibitStage, .light:
                if node.detailProfile.isCylindrical {
                    prims.append(makeCylinderPrimitive(cx: 0, baseY: 0, cz: 0, radius: max(w, d) / 2, height: h, segments: 24, materialIndex: bodyMatIdx))
                } else {
                    prims.append(makeBoxPrimitive(cx: 0, cy: h / 2, cz: 0, w: w, h: h, d: d, materialIndex: bodyMatIdx))
                }

            case .landscape:
                let trunkMat = materialIndex(for: MaterialSpec(name: "TrunkWood", hex: "#5C4030", roughness: 0.9, metalness: 0.0, opacity: 1.0))
                prims.append(makeCylinderPrimitive(cx: 0, baseY: 0, cz: 0, radius: min(w, d) * 0.12, height: h * 0.35, segments: 10, materialIndex: trunkMat))
                prims.append(makeCylinderPrimitive(cx: 0, baseY: h * 0.28, cz: 0, radius: min(w, d) * 0.45, height: h * 0.42, segments: 12, materialIndex: bodyMatIdx))
                prims.append(makeCylinderPrimitive(cx: 0, baseY: h * 0.62, cz: 0, radius: min(w, d) * 0.28, height: h * 0.36, segments: 12, materialIndex: scene.weather == .snowy ? snowMatIdx : bodyMatIdx))

            default:
                prims.append(makeBoxPrimitive(cx: 0, cy: h / 2, cz: 0, w: w, h: h, d: d, materialIndex: bodyMatIdx))
            }

            let meshIdx = buildMesh(name: node.name, primitives: prims)
            var nodeJSON: [String: Any] = [
                "name": node.name,
                "mesh": meshIdx,
                "translation": [Double(node.positionMM.xMeters), Double(node.positionMM.yMeters), Double(node.positionMM.zMeters)],
                "extras": [
                    "wumindNodeID": node.id.uuidString,
                    "category": node.category.rawValue,
                    "floorIndex": node.floorIndex,
                    "sizeMM": [node.sizeMM.x, node.sizeMM.y, node.sizeMM.z],
                    "dimensionStatus": node.dimensionStatus.label,
                ],
            ]
            if abs(node.rotationYDeg) > 0.01 {
                let halfRad = (node.rotationYDeg * .pi / 180.0) / 2.0
                nodeJSON["rotation"] = [0.0, sin(halfRad), 0.0, cos(halfRad)]
            }
            let nodeIdx = gltfNodes.count
            gltfNodes.append(nodeJSON)
            rootNodeIndices.append(nodeIdx)
        }

        // Pad binary buffer to 4-byte boundary
        while binaryData.count % 4 != 0 { binaryData.append(0) }

        let rootJSON: [String: Any] = [
            "asset": [
                "version": "2.0",
                "generator": "WUMIND AI 3D Spatial Studio",
                "copyright": scene.disclaimerBanner,
            ],
            "scene": 0,
            "scenes": [
                [
                    "name": scene.title,
                    "nodes": rootNodeIndices,
                ]
            ],
            "nodes": gltfNodes,
            "meshes": meshes,
            "materials": materialsJSON,
            "accessors": accessors,
            "bufferViews": bufferViews,
            "buffers": [
                ["byteLength": binaryData.count]
            ],
        ]

        var jsonBytes = try JSONSerialization.data(withJSONObject: rootJSON, options: [.withoutEscapingSlashes])
        while jsonBytes.count % 4 != 0 { jsonBytes.append(0x20) } // GLB JSON chunk pads with spaces

        let totalLength = 12 + 8 + jsonBytes.count + 8 + binaryData.count
        var glb = Data(capacity: totalLength)
        // Header: magic "glTF", version 2, totalLength
        appendUInt32(0x46546C67, to: &glb)
        appendUInt32(2, to: &glb)
        appendUInt32(UInt32(totalLength), to: &glb)
        // Chunk 0: JSON
        appendUInt32(UInt32(jsonBytes.count), to: &glb)
        appendUInt32(0x4E4F534A, to: &glb)
        glb.append(jsonBytes)
        // Chunk 1: BIN
        appendUInt32(UInt32(binaryData.count), to: &glb)
        appendUInt32(0x004E4942, to: &glb)
        glb.append(binaryData)

        return glb
    }

    /// Parses and validates a binary `.glb` file's header, chunk alignment, JSON structure, and named node hierarchy.
    public static func validateGLB(_ data: Data) throws -> ValidationReport {
        guard data.count >= 28 else { throw ExporterError.invalidGLBHeader }
        let magic = readUInt32(data, offset: 0)
        let version = readUInt32(data, offset: 4)
        let declaredLength = Int(readUInt32(data, offset: 8))
        guard magic == 0x46546C67, version == 2, declaredLength == data.count else {
            throw ExporterError.invalidGLBHeader
        }
        let jsonLen = Int(readUInt32(data, offset: 12))
        let jsonType = readUInt32(data, offset: 16)
        guard jsonType == 0x4E4F534A, 20 + jsonLen <= data.count else {
            throw ExporterError.invalidGLBJSON
        }
        let jsonSlice = data.subdata(in: 20..<(20 + jsonLen))
        guard let obj = try? JSONSerialization.jsonObject(with: jsonSlice) as? [String: Any],
              let nodes = obj["nodes"] as? [[String: Any]],
              let meshes = obj["meshes"] as? [[String: Any]],
              let materials = obj["materials"] as? [[String: Any]] else {
            throw ExporterError.invalidGLBJSON
        }

        let binHeaderOffset = 20 + jsonLen
        guard binHeaderOffset + 8 <= data.count else { throw ExporterError.truncatedGLBChunk }
        let binLen = Int(readUInt32(data, offset: binHeaderOffset))
        let binType = readUInt32(data, offset: binHeaderOffset + 4)
        guard binType == 0x004E4942, binHeaderOffset + 8 + binLen == data.count else {
            throw ExporterError.truncatedGLBChunk
        }

        let names = nodes.compactMap { $0["name"] as? String }
        return ValidationReport(
            byteCount: data.count,
            version: version,
            nodeCount: nodes.count,
            meshCount: meshes.count,
            materialCount: materials.count,
            nodeNames: names
        )
    }

    // MARK: - Procedural Triangulated Geometry Builders

    private static func makeBoxPrimitive(
        cx: Float, cy: Float, cz: Float,
        w: Float, h: Float, d: Float,
        materialIndex: Int
    ) -> RawPrimitive {
        let hx = w / 2, hy = h / 2, hz = d / 2
        let x0 = cx - hx, x1 = cx + hx
        let y0 = cy - hy, y1 = cy + hy
        let z0 = cz - hz, z1 = cz + hz

        var pos: [Float] = []
        var norm: [Float] = []
        var idx: [UInt16] = []

        func addFace(_ v0: (Float, Float, Float), _ v1: (Float, Float, Float), _ v2: (Float, Float, Float), _ v3: (Float, Float, Float), n: (Float, Float, Float)) {
            let base = UInt16(pos.count / 3)
            for v in [v0, v1, v2, v3] {
                pos.append(contentsOf: [v.0, v.1, v.2])
                norm.append(contentsOf: [n.0, n.1, n.2])
            }
            idx.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }

        addFace((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1), n: (0, 0, 1))
        addFace((x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0), n: (0, 0, -1))
        addFace((x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1), n: (1, 0, 0))
        addFace((x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0), n: (-1, 0, 0))
        addFace((x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0), n: (0, 1, 0))
        addFace((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), n: (0, -1, 0))

        return RawPrimitive(positions: pos, normals: norm, indices: idx, materialIndex: materialIndex)
    }

    private static func makeHipRoofPrimitive(
        cx: Float, baseY: Float, cz: Float,
        w: Float, h: Float, d: Float,
        ridgeRatio: Float,
        materialIndex: Int
    ) -> RawPrimitive {
        let hx = w / 2, hz = d / 2
        let rx = hx * ridgeRatio
        let topY = baseY + h

        let blf = (cx - hx, baseY, cz + hz)
        let brf = (cx + hx, baseY, cz + hz)
        let brb = (cx + hx, baseY, cz - hz)
        let blb = (cx - hx, baseY, cz - hz)
        let rl  = (cx - rx, topY, cz)
        let rr  = (cx + rx, topY, cz)

        var pos: [Float] = []
        var norm: [Float] = []
        var idx: [UInt16] = []

        func tri(_ a: (Float, Float, Float), _ b: (Float, Float, Float), _ c: (Float, Float, Float)) {
            let ux = b.0 - a.0, uy = b.1 - a.1, uz = b.2 - a.2
            let vx = c.0 - a.0, vy = c.1 - a.1, vz = c.2 - a.2
            var nx = uy * vz - uz * vy
            var ny = uz * vx - ux * vz
            var nz = ux * vy - uy * vx
            let len = sqrt(nx * nx + ny * ny + nz * nz)
            if len > 1e-6 { nx /= len; ny /= len; nz /= len } else { ny = 1 }
            let base = UInt16(pos.count / 3)
            for v in [a, b, c] {
                pos.append(contentsOf: [v.0, v.1, v.2])
                norm.append(contentsOf: [nx, ny, nz])
            }
            idx.append(contentsOf: [base, base + 1, base + 2])
        }

        // Front slope
        tri(blf, brf, rr); tri(blf, rr, rl)
        // Back slope
        tri(brb, blb, rl); tri(brb, rl, rr)
        // Right hip
        tri(brf, brb, rr)
        // Left hip
        tri(blb, blf, rl)
        // Underside eaves soffit
        tri(blb, brb, brf); tri(blb, brf, blf)

        return RawPrimitive(positions: pos, normals: norm, indices: idx, materialIndex: materialIndex)
    }

    private static func makeCylinderPrimitive(
        cx: Float, baseY: Float, cz: Float,
        radius: Float, height: Float,
        segments: Int,
        materialIndex: Int
    ) -> RawPrimitive {
        let segs = max(8, min(32, segments))
        let topY = baseY + height
        var pos: [Float] = []
        var norm: [Float] = []
        var idx: [UInt16] = []

        for i in 0..<segs {
            let a0 = Float(i) / Float(segs) * 2.0 * .pi
            let a1 = Float(i + 1) / Float(segs) * 2.0 * .pi
            let c0 = cos(a0), s0 = sin(a0)
            let c1 = cos(a1), s1 = sin(a1)

            let b0 = (cx + c0 * radius, baseY, cz + s0 * radius)
            let b1 = (cx + c1 * radius, baseY, cz + s1 * radius)
            let t0 = (cx + c0 * radius, topY, cz + s0 * radius)
            let t1 = (cx + c1 * radius, topY, cz + s1 * radius)

            let base = UInt16(pos.count / 3)
            pos.append(contentsOf: [b0.0, b0.1, b0.2, b1.0, b1.1, b1.2, t1.0, t1.1, t1.2, t0.0, t0.1, t0.2])
            norm.append(contentsOf: [c0, 0, s0, c1, 0, s1, c1, 0, s1, c0, 0, s0])
            idx.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])

            // Top cap triangle
            let capBase = UInt16(pos.count / 3)
            pos.append(contentsOf: [cx, topY, cz, t0.0, t0.1, t0.2, t1.0, t1.1, t1.2])
            norm.append(contentsOf: [0, 1, 0, 0, 1, 0, 0, 1, 0])
            idx.append(contentsOf: [capBase, capBase + 1, capBase + 2])
        }

        return RawPrimitive(positions: pos, normals: norm, indices: idx, materialIndex: materialIndex)
    }

    // MARK: - Little-Endian Binary & Hex Helpers

    private static func parseHexRGBA(_ hex: String, alpha: Double) -> [Double] {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count == 6, let val = UInt32(clean, radix: 16) else {
            return [0.8, 0.8, 0.8, alpha]
        }
        let r = Double((val >> 16) & 0xFF) / 255.0
        let g = Double((val >> 8) & 0xFF) / 255.0
        let b = Double(val & 0xFF) / 255.0
        return [r, g, b, alpha]
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private static func appendFloat32(_ value: Float, to data: inout Data) {
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    private static func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        var v: UInt32 = 0
        for i in 0..<4 {
            v |= UInt32(data[offset + i]) << (i * 8)
        }
        return v
    }
}
