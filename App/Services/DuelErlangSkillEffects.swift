import Foundation
import Metal
import simd

/// Source skill effects bind actor bones independently of collision-model
/// anchors. In particular, the laser's head pose is not its head.x hitbox root.
@MainActor
final class DuelErlangSkillEffectAssets {
    enum Failure: Error { case manifest }
    struct Binding: Decodable {
        let id: String, role: String, effect: String, bone: String
        let ownerRole: String?
        let attachToLocal: Bool
        let follow: [Int], shift: [Float]
        let sourceLock: Int, sourceTrigger: Int, sourceEvent: String
        let sourceRecordIndex: Int
        let sourceClip: String?, sourceMotionSHA256: String?, sourceTarget: String?
        let sourceIntervalStart: Int?
        let release: DuelErlangCombatRules.Release?
        let track: DuelSummonMotionTrack
        let sourceModelEndTick: Int, lifetimeTicks: Int
        var clock: DuelErlangSkillEffectClock.Definition {
            .init(role: role, modelEndTick: sourceModelEndTick, lifetimeTicks: lifetimeTicks)
        }
    }
    private struct Scope: Decodable {
        let sourceActiveEmitters: Int
        let boundEmitters: [String], unboundEmitters: [String]
        let completePrefab: Bool
        let sourceMirroredVariantBound: Bool?, separateGroundPrefabBound: Bool?
    }
    private struct Document: Decodable {
        let profileID: String, characterSHA256: String
        let erlangSkillBindings: [Binding]
        let erlangSkillScopes: [String: Scope]
    }
    static let fileName = "SF3_D15_SkillEffects.json.gz"
    static let eyeEffect = "D15_fx_laser(head)"
    static let eyeRole = "erlangSummon_eye"
    static let earthEffect = "D15_fx_floorAttack_(pelvis)"
    static let meditationEffect = "D15_fx_avatar_start_explos(chest)"
    static let allEffects: Set<String> = [eyeEffect, earthEffect, meditationEffect]
    private static let meshEmitters: Set<String> = ["4389738783310277062", "4874788005116766662", "4004109905803078086",
        "-4068766315815769658", "437460551336847814", "-7681221522103801402", "6538040511092746694",
        "3578977847684098502", "8513289964012497350", "-818232598598915642", "-4037953332193531450"]
    private static let billboardEmitters: Set<String> = ["-7425472578249299514", "-3566723147490924090",
        "-8859074932072453690", "-2536699185572353594"]
    private static let earthEmitters: Set<String> = ["5287901173406324130", "-6316194589938264670", "8679408912012301730",
        "-4702864568908687966", "4868519863712699810", "-7602940797112527454",
        "2864175961765008802", "1822237901742036386", "-76387927279905374",
        "-6292074152677255774", "4814904083332552098", "7115202763964831138", "-7718219801220196958",
        "-8686503464823204446", "3261350741611337122"]
    private static let meditationEmitters: Set<String> = ["-3441419061833702333", "5743770872533541955", "5640030630918874179",
        "1480694095923766339", "-3071502713722182589", "6489450101228037187", "-4655989811314957245", "2892577479160685635"]
    let particles: DuelTriadEffectAssets
    let bindings: [String: Binding]
    let profileID: String, characterSHA256: String
    var verifiedFiles: [DuelNetworkContentRecord] { particles.verifiedFiles }

    init(directory: URL, expectedSHA256: String, profile: DuelWeaponProfile) throws {
        let particles = try DuelTriadEffectAssets(directory: directory, manifestName: Self.fileName,
            expectedSHA256: expectedSHA256, profile: profile, independentErlangSkills: true)
        let raw = try Data(contentsOf: directory.appendingPathComponent(Self.fileName))
        guard DuelNetworkContentRecord.digest(raw) == expectedSHA256 else { throw Failure.manifest }
        let document = try JSONDecoder().decode(Document.self, from: DuelBoundedGzip.decode(raw, maximum: 256_000_000))
        guard document.profileID == profile.id, document.characterSHA256 == profile.sha256,
              [1, 3].contains(document.erlangSkillBindings.count),
              Set(document.erlangSkillBindings.map(\.role)).count == document.erlangSkillBindings.count,
              Set(document.erlangSkillBindings.map(\.effect)) == Set(document.erlangSkillScopes.keys),
              Set(document.erlangSkillScopes.keys) == Set(particles.effects.keys),
              Set(particles.effects.keys) == (document.erlangSkillBindings.count == 1 ? [Self.eyeEffect] : Self.allEffects) else {
            throw Failure.manifest
        }
        for binding in document.erlangSkillBindings {
            guard profile.summonTrack(role: binding.role) == binding.track,
                  binding.track.role == binding.role, binding.track.sourceEndEventTick == binding.sourceModelEndTick,
                  let effect = particles.effects[binding.effect], effect.duration.isFinite,
                  (0.1...20).contains(effect.duration), binding.lifetimeTicks == Int(ceil(effect.duration * 60)),
                  effect.tracks.allSatisfy({ $0.loopPeriod == nil }),
                  let scope = document.erlangSkillScopes[binding.effect], !scope.completePrefab,
                  Set(effect.tracks.map(\.sourceParticleSystem)) == Set(scope.boundEmitters) else { throw Failure.manifest }
            if binding.effect == Self.eyeEffect {
                try Self.validateEye(binding, scope: scope, effect: effect, profile: profile)
            } else {
                try Self.validateImpact(binding, scope: scope, effect: effect, profile: profile)
            }
        }
        self.particles = particles
        bindings = Dictionary(uniqueKeysWithValues: document.erlangSkillBindings.map { ($0.role, $0) })
        profileID = profile.id; characterSHA256 = profile.sha256
    }

    private static func validateEye(_ binding: Binding, scope: Scope, effect: DuelTriadEffectAssets.Effect,
                                    profile: DuelWeaponProfile) throws {
        guard binding.id == "d15_laser_plain_head", binding.role == Self.eyeRole,
              binding.ownerRole == "erlangEye", binding.effect == Self.eyeEffect, binding.bone == "head",
              binding.attachToLocal, binding.follow == [1, 1, 1], binding.shift == [0, 0, 0],
              binding.sourceTarget == nil,
              binding.sourceLock == 1432, binding.sourceTrigger == 53, binding.sourceEvent == "D15_Laser_Fx",
              binding.sourceRecordIndex == 104, binding.sourceClip == "d15_avatara_laser",
              binding.sourceMotionSHA256 == "c05c657b4eafdbe0e8785ea5672050fece08d4620d52f76e0bd401f77957645f",
              binding.sourceIntervalStart == 62, binding.sourceModelEndTick == 122,
              let clip = profile.clip(role: "erlangEye"), clip.name == binding.sourceClip,
              clip.sha256 == binding.sourceMotionSHA256, clip.frames == 149, clip.ticks == 296,
              clip.sourceEndEventTick == 288, clip.tick(atSourceFrame: 61) == 122,
              let rules = profile.erlangRules, let release = binding.release,
              rules.releases.filter({ $0.modelRole == binding.role }) == [release],
              release.id == "d15_create_105", release.ability == .eye,
              release.ownerRole == binding.ownerRole, release.atTick == 122,
              release.modelRole == binding.role, release.anchor == "head.x",
              release.offset == .init(x: 0, y: 0, z: 0), release.minimumLevel == 2,
              binding.track.clip == "d15_avatara_laser_model", binding.track.frames == 66,
              binding.track.sourceSHA256 == "a07f8989d863f0dad4ece1e2e6c518a52c3f392dcbc690e1e58d8bc228a337f6",
              binding.track.sourceEndEventTick == 122,
              scope.sourceActiveEmitters == 19,
              scope.sourceMirroredVariantBound == false, scope.separateGroundPrefabBound == false,
              scope.boundEmitters.count == 15, scope.unboundEmitters.count == 4,
              Set(scope.boundEmitters) == Self.meshEmitters.union(Self.billboardEmitters),
              Set(scope.unboundEmitters) == ["3678594313255446982", "-1551466144542758458", "8242420645739293126", "-6744143991670249018"],
              effect.tracks.allSatisfy({ track in
                  track.loopPeriod == nil && (Self.meshEmitters.contains(track.sourceParticleSystem) ?
                    track.geometry != nil && track.orientations != nil && track.sourceRenderMode == 4 && track.sourceRenderAlignment == 2 :
                    track.geometry == nil && track.orientations == nil && track.sourceRenderMode == 0 && track.sourceRenderAlignment == 0)
              }) else { throw Failure.manifest }
    }

    private static func validateImpact(_ binding: Binding, scope: Scope, effect: DuelTriadEffectAssets.Effect,
                                       profile: DuelWeaponProfile) throws {
        guard !binding.attachToLocal, binding.follow == [0, 0, 0],
              scope.sourceMirroredVariantBound == nil, scope.separateGroundPrefabBound == nil,
              effect.tracks.allSatisfy({ track in
                  switch (track.sourceRenderMode, track.sourceRenderAlignment) {
                  case (0, 0), (0, 3): return track.geometry == nil && track.orientations == nil
                  case (2, 0), (4, 0), (4, 2), (4, 4): return track.geometry != nil && track.orientations != nil
                  default: return false
                  }
              }) else { throw Failure.manifest }
        if binding.effect == Self.earthEffect {
            guard binding.id == "d15_earth_pelvis", binding.role == "erlangSummon_earth",
                  binding.ownerRole == "erlangEarthshaker", binding.bone == "pelvis", binding.shift == [0, 0, 0],
                  binding.sourceTarget == "owner", binding.sourceLock == 1432, binding.sourceTrigger == 66,
                  binding.sourceEvent == "D15_Spear_Ground_Shake_Model_Creation", binding.sourceRecordIndex == 102,
                  binding.sourceIntervalStart == 40, binding.sourceClip == "d15_avatara_spear_earthshake",
                  binding.sourceMotionSHA256 == "341014fb370f15f25c5fa33085de640c0051fd1b55855488b3fff7dcdb98ff0f",
                  let clip = profile.clip(role: "erlangEarthshaker"), clip.name == binding.sourceClip,
                  clip.sha256 == binding.sourceMotionSHA256, clip.frames == 111, clip.ticks == 110,
                  clip.sourceEndEventTick == 106, clip.tick(atSourceFrame: 39) == 39,
                  let rules = profile.erlangRules, let release = binding.release,
                  rules.releases.filter({ $0.modelRole == binding.role }) == [release],
                  release.id == "d15_create_103", release.ability == .earth, release.ownerRole == binding.ownerRole,
                  release.modelRole == binding.role, release.atTick == 39, release.anchor == "pelvis.x",
                  release.offset == .init(x: 20, y: 0, z: 0), release.minimumLevel == 2,
                  binding.sourceModelEndTick == 22, binding.track.clip == "s_agl_helm_bullet", binding.track.frames == 16,
                  binding.track.sourceSHA256 == "a34115ee04632ca871ead0823ad4acf2ec1884983ee24ac9cd46060c57f40775",
                  scope.sourceActiveEmitters == 19, scope.boundEmitters.count == 15, Set(scope.boundEmitters) == earthEmitters,
                  scope.unboundEmitters.count == 4, Set(scope.unboundEmitters) == ["226975819404105122", "8193636258807174562",
                    "-8834466512921012830", "2415301125327312290"] else {
                throw Failure.manifest
            }
        } else {
            guard binding.effect == Self.meditationEffect, binding.id == "d15_meditation_parent_chest",
                  binding.role == "erlangSummon_meditation", binding.ownerRole == nil,
                  binding.bone == "chest", binding.shift == [0, 0.03, 0], binding.sourceTarget == "modelParent",
                  binding.sourceLock == 1438, binding.sourceTrigger == 1, binding.sourceEvent == "Initialize",
                  binding.sourceRecordIndex == 106, binding.sourceClip == nil, binding.sourceMotionSHA256 == nil,
                  binding.sourceIntervalStart == nil, binding.release == nil,
                  binding.sourceModelEndTick == 52, binding.track.clip == "common_model_40_attack", binding.track.frames == 31,
                  binding.track.sourceSHA256 == "3f5c4da828c1524d434b96c5c7ae38e78d5c55eb3562e0c45dcc88e262c7ab3f",
                  scope.sourceActiveEmitters == 9, scope.boundEmitters.count == 8, Set(scope.boundEmitters) == meditationEmitters,
                  scope.unboundEmitters == ["2022811022957143107"] else { throw Failure.manifest }
        }
    }

    /// The native local attachment copies world rotation and position, never
    /// the actor's lossy body scale or a second facing rotation.
    static func attachedTransform(_ source: simd_float4x4) throws -> simd_float4x4 {
        guard (0..<4).allSatisfy({ column in (0..<4).allSatisfy { source[column][$0].isFinite } }) else {
            throw Failure.manifest
        }
        var result = source
        for column in 0..<3 {
            let axis = SIMD3(source[column].x, source[column].y, source[column].z)
            guard simd_length_squared(axis) > 1e-12 else { throw Failure.manifest }
            result[column] = SIMD4(simd_normalize(axis), 0)
        }
        result.columns.3.w = 1
        return result
    }
}

@MainActor
final class DuelErlangSkillEffects {
    private typealias Key = DuelErlangSkillEffectClock.Key
    private struct ParticleKey: Hashable { let source: Key; let track: Int }
    private struct EmitterKey: Hashable { let source: Key; let emitter: String; let material: String }
    private let assets: DuelErlangSkillEffectAssets
    private let factory: DuelTriadSourceMaterial.Factory
    private var clock = DuelErlangSkillEffectClock()
    private var roots: [Key: simd_float4x4] = [:]
    private var instances: [ParticleKey: DuelTriadSourceMaterial.Instance] = [:]

    init(assets: DuelErlangSkillEffectAssets, factory: DuelTriadSourceMaterial.Factory) {
        self.assets = assets; self.factory = factory
    }

    private func accepts(_ fight: DuelWeaponFight, owner: Int) -> Bool {
        fight.profiles.indices.contains(owner) && fight.profiles[owner].id == assets.profileID &&
            fight.profiles[owner].sha256 == assets.characterSHA256
    }

    func sourceBoneNames(_ fight: DuelWeaponFight) -> [Int: Set<String>] {
        guard fight.phase == .fighting else { return [:] }
        var result: [Int: Set<String>] = [:]
        for model in fight.erlangModels where accepts(fight, owner: model.owner) {
            let key = Key(owner: model.owner, model: model.id)
            if let binding = assets.bindings[model.role], binding.attachToLocal || roots[key] == nil {
                result[model.owner, default: []].insert(binding.bone)
            }
        }
        for (key, source) in clock.active {
            if let binding = assets.bindings[source.role], binding.attachToLocal || roots[key] == nil {
                result[key.owner, default: []].insert(binding.bone)
            }
        }
        return result
    }

    /// Every simulation step samples the actual actor pose, including catch-up
    /// steps. Display frames only read this result; live-tick pauses hold it.
    func sampleStep(_ fight: DuelWeaponFight, bones: [Int: [String: simd_float4x4]]) throws {
        let observations = fight.erlangModels.filter { assets.bindings[$0.role] != nil && accepts(fight, owner: $0.owner) }.map {
            DuelErlangSkillEffectClock.Observation(key: .init(owner: $0.owner, model: $0.id), role: $0.role, bornAt: $0.bornAt)
        }
        _ = try clock.consume(frame: fight.frame, liveTick: fight.erlangLiveTick, fighting: fight.phase == .fighting,
            models: observations, definitions: assets.bindings.values.map(\.clock))
        for (key, source) in clock.active {
            guard let binding = assets.bindings[source.role] else { throw DuelErlangSkillEffectAssets.Failure.manifest }
            // Original local=false/Follow000 captures the event's position.
            // Continuing particles do not move with a later actor/model pose.
            if !binding.attachToLocal, roots[key] != nil { continue }
            guard let bone = bones[key.owner]?[binding.bone] else {
                throw DuelErlangSkillEffectAssets.Failure.manifest
            }
            let source = try DuelErlangSkillEffectAssets.attachedTransform(bone)
            if binding.attachToLocal { roots[key] = source }
            else {
                var captured = matrix_identity_float4x4
                captured.columns.3 = source.columns.3 + SIMD4(binding.shift[0], binding.shift[1], binding.shift[2], 0)
                roots[key] = captured
            }
        }
        roots = roots.filter { clock.active[$0.key] != nil }
        instances = instances.filter { clock.active[$0.key.source] != nil }
    }

    func draw(_ fight: DuelWeaponFight, cameraTransform: simd_float4x4,
              projection: simd_float4x4, orthographic: Bool) throws -> [DuelSourceParticlePacket] {
        guard fight.phase == .fighting else { return [] }
        guard let tick = clock.liveTick else { return [] }
        guard tick == fight.erlangLiveTick else { throw DuelTriadSourceMaterial.Failure.frame }
        let view = simd_inverse(cameraTransform)
        let cameraPosition = SIMD3(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
        var packets: [DuelSourceParticlePacket] = [], emitters: [EmitterKey: Int] = [:]
        for key in clock.active.keys.sorted(by: { ($0.owner, $0.model) < ($1.owner, $1.model) }) {
            guard let source = clock.active[key], let binding = assets.bindings[source.role],
                  let effect = assets.particles.effects[binding.effect], let root = roots[key] else {
                throw DuelTriadSourceMaterial.Failure.frame
            }
            let elapsed = Double(tick - source.bornAt) / 60
            var attached = root; attached.columns.3 = SIMD4(0, 0, 0, 1)
            let inverseAttached = simd_inverse(attached)
            var viewFacing = cameraTransform; viewFacing.columns.3 = SIMD4(0, 0, 0, 1)
            func basisMatrix(_ basis: DuelErlangParticleFacing.Basis) -> simd_float4x4 {
                simd_float4x4(columns: (SIMD4(basis.right, 0), SIMD4(basis.up, 0),
                    SIMD4(basis.normal, 0), SIMD4(0, 0, 0, 1)))
            }
            for (index, track) in effect.tracks.enumerated() {
                guard let (a, b, t) = track.interval(at: elapsed) else { continue }
                let x = track.frames[a], y = track.frames[b]
                let state = x.enumerated().map { $0.offset < 11 ? $0.element + (y[$0.offset] - $0.element) * t : $0.element }
                guard abs(state[4]) >= 0.00001, abs(state[5]) >= 0.00001 else { continue }
                let particleKey = ParticleKey(source: key, track: index)
                let instance: DuelTriadSourceMaterial.Instance
                if let old = instances[particleKey] { instance = old }
                else { instance = try assets.particles.makeInstance(track, factory: factory); instances[particleKey] = instance }
                var placement = matrix_identity_float4x4
                placement.columns.3 = SIMD4(SIMD3(state[1], state[2], state[3]) * assets.particles.units, 1)
                let rotation: simd_float4x4, depth: Float
                if let rotations = track.orientations, let depths = track.depthScales {
                    let r = rotations[a], s = rotations[b]
                    let original = simd_float4x4(GLTFModel.mix(simd_quatf(ix: r[0], iy: r[1], iz: r[2], r: r[3]),
                        simd_quatf(ix: s[0], iy: s[1], iz: s[2], r: s[3]), t))
                    if track.sourceRenderMode == 2 {
                        rotation = inverseAttached * basisMatrix(DuelErlangParticleFacing.horizontal) * original
                    } else if track.sourceRenderAlignment == 0 {
                        rotation = inverseAttached * viewFacing * original
                    } else { rotation = original }
                    depth = depths[a] + (depths[b] - depths[a]) * t
                } else {
                    let facing: simd_float4x4
                    if track.sourceRenderAlignment == 3 {
                        let position = (root * placement).columns.3
                        guard let basis = DuelErlangParticleFacing.facing(camera: cameraPosition,
                            particle: SIMD3(position.x, position.y, position.z),
                            cameraUp: SIMD3(cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z),
                            cameraRight: SIMD3(cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z)) else {
                            throw DuelTriadSourceMaterial.Failure.frame
                        }
                        facing = basisMatrix(basis)
                    } else { facing = viewFacing }
                    rotation = inverseAttached * facing * simd_float4x4(simd_quatf(angle: state[6], axis: SIMD3(0, 0, 1)))
                    depth = 1
                }
                guard abs(depth) >= 0.00001 else { continue }
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
                let emitterKey = EmitterKey(source: key, emitter: track.sourceParticleSystem, material: track.material)
                let emitter: Int
                if let old = emitters[emitterKey] { emitter = old }
                else { emitter = emitters.count; emitters[emitterKey] = emitter }
                // Unity Distance becomes Depth for an orthographic camera.
                // The source mode stays in the manifest; only the evaluated
                // packet's key follows the actual current camera projection.
                let distanceSort = track.sourceSortMode == 1 && !orthographic
                packets.append(.init(draw: draw, order: .init(emitter: emitter,
                    sortingLayer: track.sourceSortingLayer, sortingOrder: track.sortingOrder,
                    renderQueue: track.sourceRenderQueue, mode: track.sourceSortMode == 1 && orthographic ? 4 : track.sourceSortMode,
                    age: track.age(at: elapsed), viewDepth: Double((view * transform.columns.3).z),
                    cameraDistanceSquared: distanceSort ? Double(simd_length_squared(
                        SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z) - cameraPosition)) : nil)))
                guard packets.count <= 1536 else { throw DuelTriadSourceMaterial.Failure.frame }
            }
        }
        return packets
    }

    func reset() { clock.reset(); roots.removeAll(keepingCapacity: true); instances.removeAll(keepingCapacity: true) }
    func shutdown() { reset() }
}
