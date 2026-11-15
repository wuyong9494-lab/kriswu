import Foundation
import Metal
import simd

/// Eight original mesh, seven local-plane and two particle-head/history Trail
/// emitters. Three original Noise emitters remain outside this scope.
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
        let boundMeshEmitters: [String], boundPlaneEmitters: [String], boundTrailEmitters: [String], unboundEmitters: [String]
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
    static let trailSystems: Set<String> = ["3820729297464905033", "-9101295511791219383"]
    static let unboundSystems: Set<String> = ["148819201852362057", "-7290008168018162359", "4799608978381983049"]
    static var systems: Set<String> { swordMeshSystems.union(spiralSystems).union(planeSystems).union(trailSystems) }
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
              scope.version == 3, scope.sourceActiveEmitters == 20, !scope.completePrefab,
              scope.boundMeshEmitters.count == 8, Set(scope.boundMeshEmitters) == Self.swordMeshSystems.union(Self.spiralSystems),
              scope.boundPlaneEmitters.count == 7, Set(scope.boundPlaneEmitters) == Self.planeSystems,
              scope.boundTrailEmitters.count == 2, Set(scope.boundTrailEmitters) == Self.trailSystems,
              scope.unboundEmitters.count == 3, Set(scope.unboundEmitters) == Self.unboundSystems,
              let effect = particles.effects[Self.effect], effect.tracks.count == 36,
              let histories = effect.historyTrails, histories.count == 4,
              Set(histories.map(\.sourceParticleSystem)) == Self.trailSystems,
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
        for system in Self.trailSystems {
            let heads = effect.tracks.filter { $0.sourceParticleSystem == system }
            let trails = histories.filter { $0.sourceParticleSystem == system }
            let material = system == "3820729297464905033" ? "m_-4090667728569622105" : "m_-3196968270162323177"
            guard heads.count == 2, heads.map(\.delay).sorted() == [0, 1],
                  trails.count == 2, trails.map(\.birth).sorted() == [0, 1],
                  heads.allSatisfy({ $0.material == material && $0.geometry == nil && $0.orientations == nil &&
                      $0.depthScales == nil && $0.sourceRenderMode == 0 && $0.sourceRenderAlignment == 0 &&
                      $0.duration == 1 && $0.loopPeriod == 2 && $0.frames.allSatisfy({ Array($0[4...10]) == [1, 1, 0, 1, 1, 1, 1] }) }),
                  trails.allSatisfy({ $0.material == material && $0.life == 1 && $0.loopPeriod == 2 &&
                      abs($0.tailLife - DuelErlangSwordEffectClock.tailSeconds) < 1e-10 &&
                      abs($0.minVertexDistance - 0.2) < 1e-6 && $0.width == 33 &&
                      $0.widthOverTrail == [[0, 33], [1, 33]] && $0.textureScale == [1, 1] &&
                      $0.particleColor == [1, 1, 1, 1] && $0.inheritParticleColor && $0.vertexStreams == [0, 1, 3, 4] }) else {
                throw Failure.manifest
            }
            for trail in trails {
                guard let head = heads.first(where: { $0.delay == trail.birth }),
                      trail.positions == head.frames.map({ Array($0.prefix(4)) }) else { throw Failure.manifest }
            }
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
    private struct History { let cycle: Int; var trail: DuelSourceParticleTrail }
    private var histories: [Key: History] = [:]
    private var clock = DuelErlangSwordEffectClock()
    private var round: Int?

    init(assets: DuelErlangSwordEffectAssets, factory: DuelTriadSourceMaterial.Factory) {
        self.assets = assets; self.factory = factory
    }

    /// Called once per real fixed step. Drawing never fabricates missed world
    /// positions or advances these histories. A model pose transition keeps
    /// the same source effect; only a witnessed persistent SHOW restarts it.
    func consume(fight: DuelWeaponFight) throws {
        guard fight.phase == .fighting else { reset(); return }
        if round != fight.roundNumber { reset(); round = fight.roundNumber }
        guard let effect = assets.particles.effects[DuelErlangSwordEffectAssets.effect],
              let definitions = effect.historyTrails else { throw DuelErlangSwordEffectAssets.Failure.manifest }
        let models = fight.erlangModels.filter { model in
            DuelErlangSwordVisualClock.roles.contains(model.role) && fight.profiles.indices.contains(model.owner) &&
                fight.profiles[model.owner].id == assets.profileID && fight.profiles[model.owner].sha256 == assets.characterSHA256
        }
        let restarted = try clock.consume(frame: fight.frame, liveTick: fight.erlangLiveTick, fighting: true,
            models: models.map { .init(key: .init(owner: $0.owner, model: $0.id), bornAt: $0.bornAt, role: $0.role,
                motionTick: $0.motionTick(at: fight.erlangLiveTick), hidden: $0.swordMotion?.hidden == true) })
        histories = histories.filter { !restarted.contains(.init(owner: $0.key.owner, model: $0.key.model)) }
        var active = Set<Key>()
        for model in models {
            guard let state = clock.active[.init(owner: model.owner, model: model.id)],
                  let sample = DuelErlangSwordVisualClock.sample(role: model.role, liveTick: fight.erlangLiveTick,
                    bornAt: state.startedAt, motionTick: model.motionTick(at: fight.erlangLiveTick), hidden: state.hidden) else { continue }
            let bone = try assets.attachment(role: model.role, tick: sample.poseTick, origin: model.origin, direction: model.direction)
            for (index, definition) in definitions.enumerated() {
                let key = Key(owner: model.owner, model: model.id, track: index)
                guard let particle = DuelErlangSwordEffectClock.particle(effectTick: sample.effectTick, phase: Int(definition.birth)) else { continue }
                var history: History
                if let old = histories[key], old.cycle == particle.cycle { history = old }
                else { history = .init(cycle: particle.cycle, trail: try .init(lifetimeSeconds: definition.tailLife,
                    minimumVertexDistance: Double(definition.minVertexDistance * assets.particles.units))) }
                let position: DuelWeaponPoint?
                if particle.emitting {
                    let local = definition.sample(definition.positions, at: Float(particle.ageTicks) / 60)
                    let world = bone * SIMD4(local[0] * assets.particles.units, local[1] * assets.particles.units,
                        local[2] * assets.particles.units, 1)
                    position = .init(x: Double(world.x), y: Double(world.y), z: Double(world.z))
                } else { position = nil }
                try history.trail.sample(tick: fight.erlangLiveTick, worldPosition: position, emitting: particle.emitting)
                histories[key] = history; active.insert(key)
            }
        }
        // HIDE/model removal stops new points without erasing an unexpired
        // world tail. Rendering remains suppressed by the real hidden/model
        // state; the native 10/5-frame DestroyEffect fade is not fabricated.
        for key in Array(histories.keys) where !active.contains(key) {
            var history = histories[key]!
            try history.trail.sample(tick: fight.erlangLiveTick, worldPosition: nil, emitting: false)
            if history.trail.points(at: fight.erlangLiveTick).isEmpty { histories[key] = nil }
            else { histories[key] = history }
        }
    }

    func draw(_ fight: DuelWeaponFight, cameraTransform: simd_float4x4,
              projection: simd_float4x4) throws -> [DuelSourceParticlePacket] {
        guard fight.phase == .fighting else { return [] }
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
                  let state = clock.active[.init(owner: model.owner, model: model.id)],
                  let sample = DuelErlangSwordVisualClock.sample(role: model.role, liveTick: fight.erlangLiveTick,
                    bornAt: state.startedAt, motionTick: model.motionTick(at: fight.erlangLiveTick),
                    hidden: state.hidden) else { continue }
            let time = Double(sample.effectTick) / 60
            let bone = try assets.attachment(role: model.role, tick: sample.poseTick, origin: model.origin, direction: model.direction)
            for (index, track) in effect.tracks.enumerated() {
                guard let (a, b, t) = track.interval(at: time) else { continue }
                let x = track.frames[a], y = track.frames[b]
                let state = x.enumerated().map { $0.offset < 11 ? $0.element + (y[$0.offset] - $0.element) * t : $0.element }
                let depth = track.depthScales.map { $0[a] + ($0[b] - $0[a]) * t } ?? 1
                guard abs(state[4]) >= 0.00001, abs(state[5]) >= 0.00001, abs(depth) >= 0.00001 else { continue }
                let key = Key(owner: model.owner, model: model.id, track: index)
                let instance: DuelTriadSourceMaterial.Instance
                if let old = instances[key] { instance = old }
                else { instance = try assets.particles.makeInstance(track, factory: factory); instances[key] = instance }
                active.insert(key)
                var placement = matrix_identity_float4x4
                placement.columns.3 = SIMD4(SIMD3(state[1], state[2], state[3]) * assets.particles.units, 1)
                let transform: simd_float4x4
                if let rotations = track.orientations {
                    let r = rotations[a], s = rotations[b]
                    let rotation = simd_float4x4(GLTFModel.mix(simd_quatf(ix: r[0], iy: r[1], iz: r[2], r: r[3]),
                        simd_quatf(ix: s[0], iy: s[1], iz: s[2], r: s[3]), t))
                    transform = bone * placement * rotation * simd_float4x4(diagonal: SIMD4(state[4], state[5], depth, 1))
                } else {
                    // The two original Trail heads are View billboards with
                    // zero source rotation. Only their position follows bone.
                    var billboard = cameraTransform; billboard.columns.3 = bone * placement.columns.3
                    transform = billboard * simd_float4x4(diagonal: SIMD4(state[4], state[5], 1, 1))
                }
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
            for (index, definition) in (effect.historyTrails ?? []).enumerated() {
                let key = Key(owner: model.owner, model: model.id, track: index)
                guard let particle = DuelErlangSwordEffectClock.particle(effectTick: sample.effectTick, phase: Int(definition.birth)),
                      let history = histories[key], history.cycle == particle.cycle,
                      let geometry = historyGeometry(definition, history: history.trail, tick: fight.erlangLiveTick,
                        age: Double(particle.ageTicks) / 60, camera: cameraPosition) else { continue }
                let instance = try factory.make(id: definition.material, geometry: geometry,
                    vertexStreams: definition.vertexStreams, units: assets.particles.units, cacheGeometry: false)
                let draw = try instance.packet(modelTransform: matrix_identity_float4x4, viewTransform: view,
                    projectionTransform: projection, cameraPosition: cameraPosition, tick: fight.erlangLiveTick,
                    color: SIMD4(repeating: 1), custom1: .zero, custom2: .zero, stableRandom: .zero,
                    uvTransform: SIMD4(0, 0, 1, 1), sourceTransparency: nil)
                let emitterKey = Emitter(owner: model.owner, model: model.id, source: definition.sourceParticleSystem)
                let emitter: Int
                if let existing = emitters[emitterKey] { emitter = existing }
                else { emitter = emitters.count; emitters[emitterKey] = emitter }
                let last = history.trail.points(at: fight.erlangLiveTick).last!.position
                packets.append(.init(draw: draw, order: .init(emitter: emitter, sortingLayer: definition.sourceSortingLayer,
                    sortingOrder: definition.sortingOrder, renderQueue: definition.sourceRenderQueue, mode: definition.sourceSortMode,
                    age: Double(particle.ageTicks) / 60, viewDepth: Double((view * SIMD4(Float(last.x), Float(last.y), Float(last.z), 1)).z))))
                guard packets.count <= 768 else { throw DuelTriadSourceMaterial.Failure.frame }
            }
        }
        instances = instances.filter { active.contains($0.key) }
        return packets
    }
    /// Same camera-facing ribbon construction as the existing H17 fixed-step
    /// history renderer. Stored vertices are already world metres: never
    /// reapply today's attachment, facing or human display scale to them.
    private func historyGeometry(_ source: DuelTriadEffectAssets.HistoryTrail, history: DuelSourceParticleTrail,
        tick: Int, age: Double, camera: SIMD3<Float>) -> DuelTriadSourceMaterial.Geometry? {
        let samples = history.points(at: tick)
        guard samples.count >= 2 else { return nil }
        let points = samples.map { SIMD3(Float($0.position.x), Float($0.position.y), Float($0.position.z)) }
        var lengths: [Float] = [0]
        for index in 1..<points.count { lengths.append(lengths.last! + simd_distance(points[index - 1], points[index])) }
        guard let length = lengths.last, length > 0.000001 else { return nil }
        let life = source.sample(source.colorOverLifetime, at: Float(min(1, age / source.life)))
        var positions: [Float] = [], normals: [Float] = [], uv: [Float] = [], colors: [Float] = [], indices: [UInt32] = []
        for index in points.indices {
            let position = points[index], u = lengths[index] / length
            let delta = points[min(index + 1, points.count - 1)] - points[max(0, index - 1)]
            guard simd_length_squared(delta) > 1e-12 else { return nil }
            let tangent = simd_normalize(delta), view = camera - position
            var side = simd_cross(tangent, view)
            if simd_length_squared(side) < 1e-12 { side = simd_cross(tangent, SIMD3(0, 1, 0)) }
            if simd_length_squared(side) < 1e-12 { side = simd_cross(tangent, SIMD3(1, 0, 0)) }
            side = simd_normalize(side)
            let normal = simd_normalize(simd_cross(side, tangent))
            let halfWidth = source.sample(source.widthOverTrail, at: u)[0] * assets.particles.units * 0.5
            let color = source.sample(source.colorOverTrail, at: u)
            for edge: Float in [-1, 1] {
                let vertex = position + side * halfWidth * edge
                positions += [vertex.x, vertex.y, vertex.z]; normals += [normal.x, normal.y, normal.z]
                uv += [u * source.textureScale[0], edge < 0 ? source.textureScale[1] : 0]
                colors += (0..<4).map { color[$0] * life[$0] * (source.inheritParticleColor ? source.particleColor[$0] : 1) }
            }
            if index > 0 {
                let base = UInt32((index - 1) * 2)
                indices += [base, base + 2, base + 1, base + 1, base + 2, base + 3]
            }
        }
        return .init(positions: positions, normals: normals, uv: uv, uv1: nil, colors: colors, tangents: nil, indices: indices)
    }
    func reset() {
        instances.removeAll(keepingCapacity: true); histories.removeAll(keepingCapacity: true)
        clock.reset(); round = nil
    }
    func shutdown() { reset() }
}
