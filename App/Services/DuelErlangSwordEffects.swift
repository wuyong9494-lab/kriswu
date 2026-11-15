import Foundation
import Metal
import simd

/// Eight original mesh and seven local-plane emitters. Three original Noise
/// emitters and two history trails remain outside this authenticated scope.
@MainActor
final class DuelErlangSwordEffectAssets {
    enum Failure: Error { case manifest }
    struct SourceModel: Decodable {
        let sourceAnimation: String
        let sourceRecordIndex: Int
        let track: DuelSummonMotionTrack?
        let root: [[Float]]
        let frames: Int
        let lastTick: Int
    }
    private struct Binding: Decodable, Equatable {
        let sourceLock: Int, sourceTrigger: Int
        let bone: String
        let attachToLocal: Bool
        let follow: [Int], shift: [Int]
        let requiredQuality: String
        let sourceDurationSeconds: Double
    }
    private struct Scope: Decodable {
        let version: Int
        let sourceActiveEmitters: Int
        let boundMeshEmitters: [String], boundPlaneEmitters: [String], unboundEmitters: [String]
        let completePrefab: Bool
    }
    private struct Document: Decodable {
        let profileID: String, characterSHA256: String
        let erlangSwordModels: [String: SourceModel]
        let erlangSwordBinding: Binding
        let erlangSwordScope: Scope
    }
    static let effect = "D15_fx_sword_jian_glow(weapon_r)"
    static let fileName = "SF3_D15_SwordEffects.json.gz"
    static let swordMeshSystems: Set<String> = ["5893977911169764681", "8915268038863932745", "-7834288011111445175",
                                                "-1693366553794785975", "-6545597049206092471", "-5291293020077044407"]
    static let startSystems: Set<String> = ["5893977911169764681", "8915268038863932745", "-7834288011111445175"]
    static let spiralSystems: Set<String> = ["950755173834149193", "-1451493248556544695"]
    static let planeSystems: Set<String> = ["997477216654708041", "-6073607809242968759", "3969728038972542281",
        "7805652981015170377", "-7112856168580788919", "-8672275354168275639", "-8714483650998121143"]
    static let particleCounts = ["997477216654708041": 2, "950755173834149193": 6,
        "-6073607809242968759": 1, "3969728038972542281": 1, "7805652981015170377": 1,
        "-1451493248556544695": 6, "-7112856168580788919": 2, "-8672275354168275639": 2,
        "-8714483650998121143": 2]
    static let loopingParticles: Set<String> = ["-1451493248556544695", "-7112856168580788919",
        "-8672275354168275639", "-8714483650998121143"]
    static let unboundSystems: Set<String> = ["148819201852362057", "-7290008168018162359", "4799608978381983049",
        "3820729297464905033", "-9101295511791219383"]
    static var systems: Set<String> { swordMeshSystems.union(spiralSystems).union(planeSystems) }
    let particles: DuelTriadEffectAssets
    let models: [String: SourceModel]
    let profileID: String, characterSHA256: String
    var verifiedFiles: [DuelNetworkContentRecord] { particles.verifiedFiles }

    init(directory: URL, expectedSHA256: String, profile: DuelWeaponProfile) throws {
        let particles = try DuelTriadEffectAssets(directory: directory, manifestName: Self.fileName,
            expectedSHA256: expectedSHA256, profile: profile, independentErlangSword: true)
        let raw = try Data(contentsOf: directory.appendingPathComponent(Self.fileName))
        guard DuelNetworkContentRecord.digest(raw) == expectedSHA256 else { throw Failure.manifest }
        let document = try JSONDecoder().decode(Document.self, from: DuelBoundedGzip.decode(raw, maximum: 256_000_000))
        let scope = document.erlangSwordScope
        guard document.profileID == profile.id, document.characterSHA256 == profile.sha256,
              Set(document.erlangSwordModels.keys) == DuelErlangSwordVisualClock.roles,
              document.erlangSwordBinding == .init(sourceLock: 1447, sourceTrigger: 1,
                bone: "magic_joint_root", attachToLocal: true, follow: [1, 1, 1], shift: [0, 0, 0],
                requiredQuality: "high", sourceDurationSeconds: 9999),
              scope.version == 2, scope.sourceActiveEmitters == 20, !scope.completePrefab,
              scope.boundMeshEmitters.count == 8, Set(scope.boundMeshEmitters) == Self.swordMeshSystems.union(Self.spiralSystems),
              scope.boundPlaneEmitters.count == 7, Set(scope.boundPlaneEmitters) == Self.planeSystems,
              scope.unboundEmitters.count == 5, Set(scope.unboundEmitters) == Self.unboundSystems,
              let effect = particles.effects[Self.effect], effect.tracks.count == 32,
              effect.sourceDurationOverride == 9999,
              Set(effect.tracks.map(\.sourceParticleSystem)) == Self.systems else { throw Failure.manifest }
        for (role, model) in document.erlangSwordModels {
            let rotate = role == "erlangSummon_swordRotate"
            let record: Int, alias: String
            if let slot = (1...6).first(where: { role == "erlangSummon_swordBirth\($0)" }) {
                record = 109 + slot; alias = "Birth_\(slot)"
            } else if rotate { record = 116; alias = "Rotate" }
            else if role == "erlangSummon_swordIdle" { record = 117; alias = "Idle" }
            else { record = 118; alias = "Attack" }
            guard model.sourceRecordIndex == record,
                  model.sourceAnimation == "D15_Hovering_Sword_Model_" + alias,
                  model.frames == (rotate ? 1 : 51),
                  model.lastTick == (rotate ? 0 : record == 118 ? 70 : 92),
                  model.root.count == (rotate ? 1 : 101),
                  model.root.allSatisfy({ value in
                      value.count == 16 && value.allSatisfy({ $0.isFinite && abs($0) < 10000 }) &&
                      value[3] == 0 && value[7] == 0 && value[11] == 0 && value[15] == 1
                  }) else { throw Failure.manifest }
            if rotate {
                // The original Rotate crop has one sample. It does not acquire
                // a fabricated two-frame collision track to satisfy validation.
                guard model.track == nil, profile.summonTrack(role: role) == nil else { throw Failure.manifest }
            } else {
                guard let track = model.track, track == profile.summonTrack(role: role),
                      track.role == role, track.clip == "d15_hovering_sword", track.frames == 51,
                      track.sourceSHA256 == "0705dac47e95dee7d66f39c8a2ede4e4774762aa241f79c08e64129119f36632",
                      track.sourceEndEventTick == 92 else { throw Failure.manifest }
            }
        }
        for system in Self.swordMeshSystems {
            let tracks = effect.tracks.filter { $0.sourceParticleSystem == system }
            let startup = Self.startSystems.contains(system)
            guard tracks.count == (startup ? 1 : 2),
                  tracks.allSatisfy({ $0.geometry != nil && $0.orientations != nil && $0.depthScales != nil &&
                      abs($0.duration - (startup ? 0.6 : 1)) < 0.000001 &&
                      (startup ? $0.delay == 0 && $0.loopPeriod == nil : [0.0, 1.0].contains($0.delay) && $0.loopPeriod == 2) }) else {
                throw Failure.manifest
            }
        }
        for (system, count) in Self.particleCounts {
            let tracks = effect.tracks.filter { $0.sourceParticleSystem == system }
            let period: Double? = Self.loopingParticles.contains(system) ? (Self.spiralSystems.contains(system) ? 3 : 2) : nil
            guard tracks.count == count,
                  tracks.allSatisfy({ $0.geometry != nil && $0.orientations != nil && $0.depthScales != nil &&
                      $0.sourceRenderMode == (Self.spiralSystems.contains(system) ? 4 : 0) &&
                      $0.sourceRenderAlignment == 2 && $0.loopPeriod == period }) else { throw Failure.manifest }
        }
        self.particles = particles; models = document.erlangSwordModels
        profileID = profile.id; characterSHA256 = profile.sha256
    }

    /// Source exporter already removed initial Align coordinates. These poses
    /// contain the actual root bob and RIGHT basis; do not subtract root0 or
    /// copy the human actor's display scale. Facing is applied exactly once.
    func attachment(role: String, tick: Int, origin: DuelWeaponPoint, direction: Int) throws -> simd_float4x4 {
        guard let model = models[role], (0...model.lastTick).contains(tick),
              model.root.indices.contains(tick), [-1, 1].contains(direction) else { throw Failure.manifest }
        let v = model.root[tick]
        var bone = simd_float4x4(columns: (SIMD4(v[0], v[1], v[2], v[3]), SIMD4(v[4], v[5], v[6], v[7]),
            SIMD4(v[8], v[9], v[10], v[11]), SIMD4(v[12], v[13], v[14], v[15])))
        for column in 0..<3 {
            let axis = SIMD3(bone[column].x, bone[column].y, bone[column].z)
            guard simd_length_squared(axis) > 1e-12 else { throw Failure.manifest }
            bone[column] = SIMD4(simd_normalize(axis), 0)
        }
        var facing = simd_float4x4(simd_quatf(angle: direction < 0 ? .pi : 0, axis: SIMD3(0, 1, 0)))
        facing.columns.3 = SIMD4(Float(origin.x), Float(origin.y), Float(origin.z), 1)
        return facing * bone
    }
}

@MainActor
final class DuelErlangSwordEffects {
    private struct Key: Hashable { let owner: Int; let model: UInt64; let track: Int }
    private struct Emitter: Hashable { let owner: Int; let model: UInt64; let source: String }
    private let assets: DuelErlangSwordEffectAssets
    private let factory: DuelTriadSourceMaterial.Factory
    private var instances: [Key: DuelTriadSourceMaterial.Instance] = [:]

    init(assets: DuelErlangSwordEffectAssets, factory: DuelTriadSourceMaterial.Factory) {
        self.assets = assets; self.factory = factory
    }

    func draw(_ fight: DuelWeaponFight, cameraTransform: simd_float4x4,
              projection: simd_float4x4) throws -> [DuelSourceParticlePacket] {
        guard fight.phase == .fighting else { reset(); return [] }
        guard let effect = assets.particles.effects[DuelErlangSwordEffectAssets.effect] else {
            throw DuelErlangSwordEffectAssets.Failure.manifest
        }
        let view = simd_inverse(cameraTransform)
        let cameraPosition = SIMD3(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
        var packets: [DuelSourceParticlePacket] = [], active = Set<Key>(), emitters: [Emitter: Int] = [:]
        for model in fight.erlangModels.sorted(by: { ($0.owner, $0.id) < ($1.owner, $1.id) }) {
            guard fight.profiles.indices.contains(model.owner),
                  fight.profiles[model.owner].id == assets.profileID,
                  fight.profiles[model.owner].sha256 == assets.characterSHA256,
                  let sample = DuelErlangSwordVisualClock.sample(role: model.role, liveTick: fight.erlangLiveTick,
                    bornAt: model.bornAt, motionTick: model.motionTick(at: fight.erlangLiveTick),
                    hidden: model.swordMotion?.hidden == true) else { continue }
            let time = Double(sample.effectTick) / 60
            let bone = try assets.attachment(role: model.role, tick: sample.poseTick, origin: model.origin, direction: model.direction)
            for (index, track) in effect.tracks.enumerated() {
                guard let (a, b, t) = track.interval(at: time),
                      let rotations = track.orientations, let depths = track.depthScales else { continue }
                let x = track.frames[a], y = track.frames[b]
                let state = x.enumerated().map { $0.offset < 11 ? $0.element + (y[$0.offset] - $0.element) * t : $0.element }
                let depth = depths[a] + (depths[b] - depths[a]) * t
                guard abs(state[4]) >= 0.00001, abs(state[5]) >= 0.00001, abs(depth) >= 0.00001 else { continue }
                let key = Key(owner: model.owner, model: model.id, track: index)
                let instance: DuelTriadSourceMaterial.Instance
                if let old = instances[key] { instance = old }
                else { instance = try assets.particles.makeInstance(track, factory: factory); instances[key] = instance }
                active.insert(key)
                var placement = matrix_identity_float4x4
                placement.columns.3 = SIMD4(SIMD3(state[1], state[2], state[3]) * assets.particles.units, 1)
                let r = rotations[a], s = rotations[b]
                let rotation = simd_float4x4(GLTFModel.mix(simd_quatf(ix: r[0], iy: r[1], iz: r[2], r: r[3]),
                    simd_quatf(ix: s[0], iy: s[1], iz: s[2], r: s[3]), t))
                let transform = bone * placement * rotation * simd_float4x4(diagonal: SIMD4(state[4], state[5], depth, 1))
                func custom(_ values: [[Float]]?) -> SIMD4<Float> {
                    guard let values else { return .zero }
                    let first = values[a], second = values[b]
                    return SIMD4(first[0] + (second[0]-first[0])*t, first[1] + (second[1]-first[1])*t,
                                 first[2] + (second[2]-first[2])*t, first[3] + (second[3]-first[3])*t)
                }
                let draw = try instance.packet(modelTransform: transform, viewTransform: view, projectionTransform: projection,
                    cameraPosition: cameraPosition, tick: fight.erlangLiveTick, color: SIMD4(state[7], state[8], state[9], state[10]),
                    custom1: custom(track.customData1), custom2: custom(track.customData2),
                    stableRandom: SIMD4(track.stableRandom[0], track.stableRandom[1], track.stableRandom[2], track.stableRandom[3]),
                    uvTransform: SIMD4(state[11], state[12], state[13], state[14]), sourceTransparency: nil)
                let emitterKey = Emitter(owner: model.owner, model: model.id, source: track.sourceParticleSystem)
                let emitter: Int
                if let existing = emitters[emitterKey] { emitter = existing }
                else { emitter = emitters.count; emitters[emitterKey] = emitter }
                packets.append(.init(draw: draw, order: .init(emitter: emitter, sortingLayer: track.sourceSortingLayer,
                    sortingOrder: track.sortingOrder, renderQueue: track.sourceRenderQueue, mode: track.sourceSortMode,
                    age: track.age(at: time), viewDepth: Double((view * transform.columns.3).z))))
                guard packets.count <= 768 else { throw DuelTriadSourceMaterial.Failure.frame }
            }
        }
        instances = instances.filter { active.contains($0.key) }
        return packets
    }
    func reset() { instances.removeAll(keepingCapacity: true) }
    func shutdown() { reset() }
}
