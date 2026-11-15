import Foundation
import Metal
import simd

/// The original large leg is a three-emitter mesh effect, not a humanoid rig.
/// Its source model track authenticates only its birth position and clock.
@MainActor
final class DuelErlangStompEffectAssets {
    enum Failure: Error { case manifest }
    struct SourceModel: Decodable {
        let track: DuelSummonMotionTrack
        let sourceAnimation: String
        let sourceRecordIndex: Int
        let bones: [String: [[Float]]]
        let endEventTick: Int
    }
    private struct Binding: Decodable, Equatable {
        let id: String, role: String, effect: String, bone: String
        let startTick: Int
        let attachToLocal: Bool
        let follow: [Int], shift: [Int]
        let sourceLock: Int, sourceTrigger: Int, sourceRecordIndex: Int
    }
    private struct Document: Decodable {
        let profileID: String, characterSHA256: String
        let erlangSourceModels: [String: SourceModel]
        let erlangModelBindings: [Binding]
    }
    static let role = "erlangSummon_stomp"
    static let effect = "D15_fx_big_leg"
    static let fileName = "SF3_D15_StompEffects.json.gz"
    let particles: DuelTriadEffectAssets
    let source: SourceModel
    let profileID: String, characterSHA256: String
    var verifiedFiles: [DuelNetworkContentRecord] { particles.verifiedFiles }

    init(directory: URL, expectedSHA256: String, profile: DuelWeaponProfile) throws {
        let particles = try DuelTriadEffectAssets(directory: directory, manifestName: Self.fileName,
            expectedSHA256: expectedSHA256, profile: profile, independentErlangStomp: true)
        let raw = try Data(contentsOf: directory.appendingPathComponent(Self.fileName))
        guard DuelNetworkContentRecord.digest(raw) == expectedSHA256 else { throw Failure.manifest }
        let document = try JSONDecoder().decode(Document.self, from: DuelBoundedGzip.decode(raw, maximum: 256_000_000))
        guard document.profileID == profile.id, document.characterSHA256 == profile.sha256,
              Set(document.erlangSourceModels.keys) == [Self.role],
              let model = document.erlangSourceModels[Self.role],
              profile.summonTrack(role: Self.role) == model.track,
              model.track.frames == 10, model.track.clip == "common_model_40_attack",
              model.track.sourceSHA256 == "3f5c4da828c1524d434b96c5c7ae38e78d5c55eb3562e0c45dcc88e262c7ab3f",
              model.track.boneConfigurationSHA256 == "27902c22151fa33d2bc45b163bb9d4ca106f4c934a36013eb31bb37a35dbfbd7",
              model.sourceAnimation == "D15_Avatara_Leg_Model", model.sourceRecordIndex == 100,
              model.endEventTick == 18,
              Set(model.bones.keys) == ["magic_joint_root", "magic_joint_left", "magic_joint_right", "magic_joint_top", "magic_joint_bottom"],
              model.bones.values.allSatisfy({ samples in
                  samples.count == 19 && samples.allSatisfy { value in
                      value.count == 16 && value.allSatisfy({ $0.isFinite && abs($0) < 10000 }) &&
                      value[3] == 0 && value[7] == 0 && value[11] == 0 && value[15] == 1
                  }
              }),
              document.erlangModelBindings == [.init(id: "d15_leg_animation_start", role: Self.role,
                effect: Self.effect, bone: "magic_joint_root", startTick: 0, attachToLocal: false,
                follow: [0, 0, 0], shift: [0, 0, 0], sourceLock: 1434, sourceTrigger: 1, sourceRecordIndex: 100)],
              let effect = particles.effects[Self.effect], effect.tracks.count == 3,
              abs(effect.duration - 1.4) < 0.000001,
              Set(effect.tracks.map(\.sourceParticleSystem)) == ["-929469514926225548", "6055453625588746100", "-1006497375095126156"],
              effect.tracks.allSatisfy({ $0.geometry != nil && $0.delay == 0 && abs($0.duration - 1.4) < 0.000001 && $0.loopPeriod == nil }) else {
            throw Failure.manifest
        }
        self.particles = particles; self.source = model
        profileID = profile.id; characterSHA256 = profile.sha256
    }

    /// Follow XYZ=0: capture the source root's position once. The effect's own
    /// takeInAccountCharacterDirection rotates its original mesh exactly once.
    func birthTransform(origin: DuelWeaponPoint, direction: Int) throws -> simd_float4x4 {
        guard [-1, 1].contains(direction), let values = source.bones["magic_joint_root"]?.first else { throw Failure.manifest }
        var transform = simd_float4x4(simd_quatf(angle: direction < 0 ? .pi : 0, axis: SIMD3(0, 1, 0)))
        let p = transform * SIMD4(values[12], values[13], values[14], 0)
        transform.columns.3 = SIMD4(Float(origin.x) + p.x, Float(origin.y) + p.y, Float(origin.z) + p.z, 1)
        return transform
    }
}

@MainActor
final class DuelErlangStompEffects {
    private typealias Key = DuelErlangStompEffectClock.Key
    private struct ParticleKey: Hashable { let source: Key; let track: Int }
    private let assets: DuelErlangStompEffectAssets
    private let factory: DuelTriadSourceMaterial.Factory
    private var clock = DuelErlangStompEffectClock()
    private var roots: [Key: simd_float4x4] = [:]
    private var instances: [ParticleKey: DuelTriadSourceMaterial.Instance] = [:]

    init(assets: DuelErlangStompEffectAssets, factory: DuelTriadSourceMaterial.Factory) {
        self.assets = assets; self.factory = factory
    }

    /// Called for every fixed step, including catch-up steps. A display frame
    /// cannot manufacture a missed model or replay an already observed birth.
    func sampleStep(_ fight: DuelWeaponFight) throws {
        let models = fight.erlangModels.filter { model in
            model.role == DuelErlangStompEffectAssets.role && fight.profiles.indices.contains(model.owner) &&
                fight.profiles[model.owner].id == assets.profileID &&
                fight.profiles[model.owner].sha256 == assets.characterSHA256
        }
        let observations = models.map { DuelErlangStompEffectClock.Observation(key: .init(owner: $0.owner, model: $0.id), bornAt: $0.bornAt) }
        let starts = try clock.consume(frame: fight.frame, liveTick: fight.erlangLiveTick,
            fighting: fight.phase == .fighting, models: observations)
        for start in starts {
            guard let model = models.first(where: { $0.owner == start.key.owner && $0.id == start.key.model }) else {
                throw DuelErlangStompEffectAssets.Failure.manifest
            }
            roots[start.key] = try assets.birthTransform(origin: model.origin, direction: model.direction)
        }
        roots = roots.filter { clock.active[$0.key] != nil }
        instances = instances.filter { clock.active[$0.key.source] != nil }
    }

    func draw(_ fight: DuelWeaponFight, cameraTransform: simd_float4x4,
              projection: simd_float4x4) throws -> [DuelSourceParticlePacket] {
        guard fight.phase == .fighting, let tick = clock.liveTick else { return [] }
        guard tick == fight.erlangLiveTick, let effect = assets.particles.effects[DuelErlangStompEffectAssets.effect] else {
            throw DuelErlangStompEffectAssets.Failure.manifest
        }
        let view = simd_inverse(cameraTransform)
        let cameraPosition = SIMD3(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
        var packets: [DuelSourceParticlePacket] = []
        // Sorting by owner/id makes equal-depth emitter ties deterministic.
        for key in clock.active.keys.sorted(by: { ($0.owner, $0.model) < ($1.owner, $1.model) }) {
            guard let born = clock.active[key], let root = roots[key] else { throw DuelErlangStompEffectAssets.Failure.manifest }
            let elapsed = Double(tick - born) / 60
            for (index, track) in effect.tracks.enumerated() {
                guard let (a, b, t) = track.interval(at: elapsed),
                      let rotations = track.orientations, let depths = track.depthScales else { continue }
                let x = track.frames[a], y = track.frames[b]
                let state = x.enumerated().map { $0.offset < 11 ? $0.element + (y[$0.offset] - $0.element) * t : $0.element }
                let depth = depths[a] + (depths[b] - depths[a]) * t
                guard abs(state[4]) >= 0.00001, abs(state[5]) >= 0.00001, abs(depth) >= 0.00001 else { continue }
                let particleKey = ParticleKey(source: key, track: index)
                let instance: DuelTriadSourceMaterial.Instance
                if let old = instances[particleKey] { instance = old }
                else { instance = try assets.particles.makeInstance(track, factory: factory); instances[particleKey] = instance }
                var placement = matrix_identity_float4x4
                placement.columns.3 = SIMD4(SIMD3(state[1], state[2], state[3]) * assets.particles.units, 1)
                let r = rotations[a], s = rotations[b]
                let rotation = simd_float4x4(GLTFModel.mix(simd_quatf(ix: r[0], iy: r[1], iz: r[2], r: r[3]),
                    simd_quatf(ix: s[0], iy: s[1], iz: s[2], r: s[3]), t))
                let transform = root * placement * rotation * simd_float4x4(diagonal: SIMD4(state[4], state[5], depth, 1))
                func custom(_ values: [[Float]]?) -> SIMD4<Float> {
                    guard let values else { return .zero }
                    let first = values[a], second = values[b]
                    return SIMD4(first[0] + (second[0]-first[0])*t, first[1] + (second[1]-first[1])*t,
                                 first[2] + (second[2]-first[2])*t, first[3] + (second[3]-first[3])*t)
                }
                let draw = try instance.packet(modelTransform: transform, viewTransform: view, projectionTransform: projection,
                    cameraPosition: cameraPosition, tick: tick, color: SIMD4(state[7], state[8], state[9], state[10]),
                    custom1: custom(track.customData1), custom2: custom(track.customData2),
                    stableRandom: SIMD4(track.stableRandom[0], track.stableRandom[1], track.stableRandom[2], track.stableRandom[3]),
                    uvTransform: SIMD4(state[11], state[12], state[13], state[14]), sourceTransparency: nil)
                packets.append(.init(draw: draw, order: .init(emitter: packets.count,
                    sortingLayer: track.sourceSortingLayer, sortingOrder: track.sortingOrder,
                    renderQueue: track.sourceRenderQueue, mode: track.sourceSortMode,
                    age: track.age(at: elapsed), viewDepth: Double((view * transform.columns.3).z))))
            }
        }
        guard packets.count <= 384 else { throw DuelTriadSourceMaterial.Failure.frame }
        return packets
    }

    func reset() { clock.reset(); roots.removeAll(keepingCapacity: true); instances.removeAll(keepingCapacity: true) }
    func shutdown() { reset() }
}
