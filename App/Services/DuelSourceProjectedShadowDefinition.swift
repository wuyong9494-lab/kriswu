import Foundation
import SceneKit
import simd

/// Data recovered from the source scene and projector, carried inside the
/// independently pinned private Morph document. The public implementation
/// contains no replacement floor mesh or invented projection parameters.
struct DuelSourceProjectedShadowDefinition: Codable {
    struct Stage: Codable {
        let file: String
        let bytes: Int
        let sha256: String
        let rootNode: String
        let rootTranslation: [Float]
        let rootScale: [Float]
    }
    struct Transform: Codable {
        let nodeIndex: Int
        let name: String
        let translation: [Float]
        let rotation: [Float]
        let scale: [Float]
    }
    struct Geometry: Codable {
        let positions: [[Float]]
        let indices: [UInt32]
    }
    struct Receiver: Codable {
        let node: String
        let nodeIndex: Int
        /// Source export order is leaf to root, including both endpoints.
        let ancestorChain: [Transform]
        let geometry: Geometry
        let sourceMeshSHA256: String
        let sourceMaterialSHA256: String
        let renderQueue: Int
    }
    struct Settings: Codable {
        let useAdaptiveShadowScale: Bool
        let targetTextureFill: Float
        let minCameraSize: Float
        let cinematic: Bool
        let useDynamicPositionBetweenPlayerAndEnemy: Bool
    }
    struct Location: Codable {
        let projectorPosition: [Float]
        let projectorRotationDegrees: [Float]
        let shadowColor: [Float]
    }
    struct Follow: Codable {
        let source: String
        let midpoint: Bool
        let positionUsesPreviousForward: Bool
        let rotationAfterPosition: Bool
        let initialRotationQuaternion: [Float]
    }
    struct Camera: Codable {
        let orthographic: Bool
        let orthographicSize: Float
        let nearClip: Float
        let farClip: Float
        let targetDistance: Float
        let projectionBiasColumnMajor: [Float]
        let dividesProjectedUVByW: Bool
        let halfProjectionRows: Bool
        let halfProjectedUV: Bool
        let follow: Follow
        let aspectSource: String
    }
    struct Map: Codable {
        let width: Int
        let height: Int
        let sourceFormatPriority: [String]
        let depthBits: Int
        let sampleCount: Int
        let filter: Int
        let wrapS: Int
        let wrapT: Int
        let clearColor: [Float]
        let projectColorSpace: Int
        let drawOrder: [String]
    }
    struct Blur: Codable {
        let passes: Int
        let offsets: [[Float]]
        let weights: [Float]
        let sampleChannel: String
        let replicateRedToRGBA: Bool
    }
    struct Raster: Codable {
        let source: Int
        let destination: Int
        let zWrite: Bool
        let zTest: Int
        let cull: Int
    }
    let complete: Bool
    let stage: Stage
    let receiver: Receiver
    let settings: Settings
    let sourceLocation: Location
    let camera: Camera
    let map: Map
    let blur: Blur
    let raster: Raster
    let evidence: [String]

    enum Failure: Error, Equatable { case incomplete, identity, geometry, projection, sampler, raster, stage }

    /// The only pipeline implemented here is the recovered independent
    /// projector. Synthetic tests may vary bounded geometry and camera sizes,
    /// but cannot request a different shader, blend, sampler or clock policy.
    func validate() throws {
        guard complete else { throw Failure.incomplete }
        func vector(_ value: [Float], _ count: Int, maximum: Float = 1_000_000) -> Bool {
            value.count == count && value.allSatisfy { $0.isFinite && abs($0) <= maximum }
        }
        func positive(_ value: Float) -> Bool { value.isFinite && value > 0 && value <= 1_000_000 }
        func name(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 160 }
        guard DuelFighterAssetRelease.File.validName(stage.file), stage.file.hasSuffix(".glb"),
              (1...128_000_000).contains(stage.bytes), DuelFighterAssetRelease.validDigest(stage.sha256),
              name(stage.rootNode), vector(stage.rootTranslation, 3), vector(stage.rootScale, 3),
              stage.rootScale.allSatisfy({ abs($0) >= 0.00000001 }),
              (1...32).contains(evidence.count), evidence.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }) else {
            throw Failure.identity
        }
        let chain = receiver.ancestorChain, mesh = receiver.geometry
        guard name(receiver.node), (0..<4096).contains(receiver.nodeIndex),
              (1...16).contains(chain.count), Set(chain.map(\.nodeIndex)).count == chain.count,
              chain.first?.nodeIndex == receiver.nodeIndex, chain.first?.name == receiver.node,
              chain.last?.name == stage.rootNode,
              chain.allSatisfy({ transform in
                  name(transform.name) && (0..<4096).contains(transform.nodeIndex) &&
                  vector(transform.translation, 3) && vector(transform.rotation, 4, maximum: 1.001) &&
                  abs(transform.rotation.reduce(0) { $0 + $1 * $1 } - 1) < 0.001 &&
                  vector(transform.scale, 3) && transform.scale.allSatisfy({ abs($0) >= 0.00000001 })
              }),
              chain.last?.translation == stage.rootTranslation, chain.last?.scale == stage.rootScale,
              (3...4096).contains(mesh.positions.count),
              mesh.positions.allSatisfy({ vector($0, 3) }),
              (3...49_152).contains(mesh.indices.count), mesh.indices.count.isMultiple(of: 3),
              mesh.indices.allSatisfy({ Int($0) < mesh.positions.count }),
              DuelFighterAssetRelease.validDigest(receiver.sourceMeshSHA256),
              DuelFighterAssetRelease.validDigest(receiver.sourceMaterialSHA256), receiver.renderQueue == 2501 else {
            throw Failure.geometry
        }
        guard !settings.useAdaptiveShadowScale, !settings.cinematic,
              settings.useDynamicPositionBetweenPlayerAndEnemy,
              settings.targetTextureFill.isFinite, (0...1).contains(settings.targetTextureFill),
              positive(settings.minCameraSize),
              vector(sourceLocation.projectorPosition, 3), vector(sourceLocation.projectorRotationDegrees, 3),
              vector(sourceLocation.shadowColor, 4, maximum: 1), sourceLocation.shadowColor.allSatisfy({ $0 >= 0 }),
              camera.orthographic, positive(camera.orthographicSize),
              camera.orthographicSize == settings.minCameraSize,
              positive(camera.nearClip), positive(camera.farClip), positive(camera.targetDistance),
              camera.nearClip < camera.targetDistance, camera.targetDistance < camera.farClip,
              camera.projectionBiasColumnMajor == [0.5, 0, 0, 0, 0, 0.5, 0, 0, 0, 0, 0.5, 0, 0.5, 0.5, 0.5, 0.5],
              !camera.dividesProjectedUVByW, camera.halfProjectionRows, camera.halfProjectedUV,
              camera.aspectSource == "screen", camera.follow.source == "actorCenterOfMassWorldXYZ",
              camera.follow.midpoint, camera.follow.positionUsesPreviousForward, camera.follow.rotationAfterPosition,
              camera.follow.initialRotationQuaternion == [0, 0, 0, 1] else { throw Failure.projection }
        guard (1...1024).contains(map.width), map.height == map.width,
              map.sourceFormatPriority == ["R8", "RGB565", "ARGB32"],
              map.depthBits == 0, map.sampleCount == 1, map.filter == 1, map.wrapS == 1, map.wrapT == 1,
              map.clearColor == [1, 1, 1, 1], map.projectColorSpace == 0,
              map.drawOrder == ["firstActor", "secondActor", "additionalModels", "extraRenderers"],
              blur.passes == 1,
              blur.offsets == [[-1, 1], [-0.8, -0.8], [0, 0], [0.8, 0.8], [1, -1]],
              blur.weights == [0.2, 0.2, 0.2, 0.2, 0.2],
              blur.sampleChannel == "red", blur.replicateRedToRGBA else { throw Failure.sampler }
        guard raster.source == 2, raster.destination == 0, !raster.zWrite,
              raster.zTest == 4, raster.cull == 2 else { throw Failure.raster }
    }

    /// Production additionally requires the independently identified Palace
    /// export, source receiver and runtime settings. This is never used to
    /// turn a synthetic geometry fixture into installed-source evidence.
    @MainActor
    func validatePalaceSource() throws {
        try validate()
        guard stage.file == "SF3_Palace_Exterior.glb", stage.bytes == 9_292_540,
              stage.sha256 == DuelStageAsset.digest, stage.rootNode == "SF3_Stage_Meters",
              stage.rootScale == [0.01, 0.01, 0.01],
              receiver.node == "shadow_reciever", receiver.nodeIndex == 40,
              receiver.ancestorChain.map(\.nodeIndex) == [40, 10, 9, 8, 0, 60],
              receiver.geometry.positions.count == 4, receiver.geometry.indices == [0, 2, 1, 0, 3, 2],
              receiver.sourceMeshSHA256 == "add7e351bc5436bfa222d12ffd1da6651a2839f81ba2c32519a230a6e7e392f0",
              receiver.sourceMaterialSHA256 == "ce5f0dd49af1a8ad94fe675022e21ae96857f7e5253c371b1d7a61e9d1155471",
              abs(settings.targetTextureFill - 0.64) <= 0.0000001,
              settings.minCameraSize == 250, camera.orthographicSize == 250,
              camera.nearClip == 500, camera.farClip == 3000, camera.targetDistance == 1000,
              map.width == 256, map.height == 256 else { throw Failure.identity }
    }

    @MainActor
    struct BoundStage {
        let meters: SCNNode
        let receiver: SCNNode
    }

    /// Resolve the authenticated ancestry, including duplicate names at
    /// different levels. An unrelated scene node with the same leaf name
    /// cannot receive this mesh. Local TRS stays exactly as exported.
    @MainActor
    func bindStage(_ root: SCNNode) throws -> BoundStage {
        try validate()
        var candidates: [SCNNode] = []
        if root.name == stage.rootNode { candidates.append(root) }
        root.enumerateChildNodes { node, _ in if node.name == stage.rootNode { candidates.append(node) } }
        guard candidates.count == 1, let meters = candidates.first else { throw Failure.stage }
        let path = Array(receiver.ancestorChain.reversed())
        var current = meters
        for (index, expected) in path.enumerated() {
            if index > 0 {
                let children = current.childNodes.filter { $0.name == expected.name }
                guard children.count == 1, let child = children.first else { throw Failure.stage }
                current = child
            }
            guard Self.matches(current, expected) else { throw Failure.stage }
        }
        guard current.geometry == nil, current.skinner == nil, current.childNodes.isEmpty else { throw Failure.stage }
        return BoundStage(meters: meters, receiver: current)
    }

    @MainActor
    private static func matches(_ node: SCNNode, _ transform: Transform) -> Bool {
        func close(_ actual: SIMD3<Float>, _ expected: [Float]) -> Bool {
            (0..<3).allSatisfy {
                actual[$0].isFinite && abs(actual[$0] - expected[$0]) <= max(0.000002, abs(expected[$0]) * 0.000002)
            }
        }
        let orientation = node.simdOrientation.vector
        let expected = SIMD4(transform.rotation[0], transform.rotation[1], transform.rotation[2], transform.rotation[3])
        return node.name == transform.name && close(node.simdPosition, transform.translation) &&
            close(node.simdScale, transform.scale) && orientation.x.isFinite && orientation.y.isFinite &&
            orientation.z.isFinite && orientation.w.isFinite && abs(abs(simd_dot(orientation, simd_normalize(expected))) - 1) < 0.000002
    }
}
