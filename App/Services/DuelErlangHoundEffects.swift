import Foundation
import Metal
import SceneKit
import simd

/// Preserve original transparent ordering across independently loaded effects.
/// Emitter IDs are rebased when D15 packets join the existing H17 packet list.
struct DuelSourceParticlePacket {
    let draw: DuelTriadSourceMaterial.Draw
    let order: DuelSourceParticleOrder.Item
    func ordering(rebasedBy offset: Int) -> DuelSourceParticleOrder.Item {
        .init(emitter: order.emitter + offset, sortingLayer: order.sortingLayer,
              sortingOrder: order.sortingOrder, renderQueue: order.renderQueue,
              mode: order.mode, age: order.age, viewDepth: order.viewDepth)
    }
    static func sorted(_ packets: [Self]) throws -> [DuelTriadSourceMaterial.Draw] {
        try DuelSourceParticleOrder.indices(packets.map(\.order)).map { packets[$0].draw }
    }
}

@MainActor
final class DuelErlangHoundEffectAssets {
    let particles: DuelTriadEffectAssets
    let companions: DuelErlangCompanionAssets
    let profileID: String
    let characterSHA256: String
    var verifiedFiles: [DuelNetworkContentRecord] { particles.verifiedFiles }

    init(directory: URL, expectedSHA256: String, profile: DuelWeaponProfile,
         companions: DuelErlangCompanionAssets) throws {
        guard profile.id == "wuyong_erlang", companions.manifest.profileID == profile.id,
              companions.manifest.characterSHA256 == profile.sha256,
              let track = profile.summonTrack(role: "erlangSummon_hound"),
              track == companions.manifest.models[0].track else { throw DuelTriadEffectAssets.Failure.manifest }
        let particles = try DuelTriadEffectAssets(directory: directory, manifestName: "SF3_D15_Effects.json.gz",
            expectedSHA256: expectedSHA256, profile: profile, independentErlangHound: true)
        let sourceSystems = Set(particles.effects.values.flatMap { $0.tracks.map(\.sourceParticleSystem) })
        guard sourceSystems.count == 9 else { throw DuelTriadEffectAssets.Failure.manifest }
        self.particles = particles; self.companions = companions
        profileID = profile.id; characterSHA256 = profile.sha256
    }
}

/// Real original dog smoke and transition bursts. Local and world emitter
/// positions are reconstructed from immutable model poses at their own clocks.
@MainActor
final class DuelErlangHoundEffects {
    private struct Key: Hashable { let owner: Int; let model: UInt64; let binding: Int; let track: Int }
    private struct Emitter: Hashable { let owner: Int; let model: UInt64; let binding: Int; let source: String; let material: String }
    private let assets: DuelErlangHoundEffectAssets
    private let factory: DuelTriadSourceMaterial.Factory
    private var instances: [Key: DuelTriadSourceMaterial.Instance] = [:]

    init(assets: DuelErlangHoundEffectAssets, factory: DuelTriadSourceMaterial.Factory) {
        self.assets = assets; self.factory = factory
    }

    func draw(_ fight: DuelWeaponFight, cameraTransform: simd_float4x4,
              projection: simd_float4x4) throws -> [DuelSourceParticlePacket] {
        guard fight.phase == .fighting else { reset(); return [] }
        let view = simd_inverse(cameraTransform)
        let cameraPosition = SIMD3(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
        var packets: [DuelSourceParticlePacket] = [], active = Set<Key>(), emitters: [Emitter: Int] = [:]
        for model in fight.erlangModels where model.role == "erlangSummon_hound" {
            guard fight.profiles.indices.contains(model.owner),
                  fight.profiles[model.owner].id == assets.profileID,
                  fight.profiles[model.owner].sha256 == assets.characterSHA256 else { continue }
            let age = fight.erlangLiveTick - model.bornAt
            guard (0...110).contains(age) else { continue }
            for (bindingIndex, binding) in DuelErlangHoundEffectClock.bindings.enumerated() {
                guard age >= binding.startTick, let effect = assets.particles.effects[binding.effect] else { continue }
                let time = Double(age - binding.startTick) / 60
                for (trackIndex, track) in effect.tracks.enumerated() {
                    guard let space = track.sourceSimulationSpace,
                          let attachmentAge = DuelErlangHoundEffectClock.attachmentAge(modelAge: age,
                            startTick: binding.startTick, delay: track.delay, duration: track.duration,
                            loopPeriod: track.loopPeriod, space: space),
                          let (a, b, fraction) = track.interval(at: time),
                          var bone = assets.companions.sourceBoneTransform("spine_root_joint", age: attachmentAge,
                            origin: model.origin, direction: model.direction) else { continue }
                    let position = bone.columns.3
                    if binding.attachToLocal {
                        for column in 0..<3 {
                            let v = SIMD3(bone[column].x, bone[column].y, bone[column].z)
                            guard simd_length_squared(v) > 1e-12 else { throw DuelTriadSourceMaterial.Failure.frame }
                            bone[column] = SIMD4(simd_normalize(v), 0)
                        }
                    } else { bone = matrix_identity_float4x4 }
                    bone.columns.3 = SIMD4(position.x, position.y + Float(binding.shiftY), position.z, 1)
                    let first = track.frames[a], second = track.frames[b]
                    let state = first.enumerated().map { $0.offset < 11 ? $0.element + (second[$0.offset] - $0.element) * fraction : $0.element }
                    guard abs(state[4]) >= 0.00001, abs(state[5]) >= 0.00001 else { continue }
                    let key = Key(owner: model.owner, model: model.id, binding: bindingIndex, track: trackIndex)
                    let instance: DuelTriadSourceMaterial.Instance
                    if let existing = instances[key] { instance = existing }
                    else { instance = try assets.particles.makeInstance(track, factory: factory); instances[key] = instance }
                    active.insert(key)
                    let offset = SIMD3(state[1], state[2], state[3]) * assets.particles.units
                    var placement = matrix_identity_float4x4; placement.columns.3 = SIMD4(offset, 1)
                    let rotation: simd_float4x4, depth: Float
                    if let rotations = track.orientations, let depths = track.depthScales {
                        let x = rotations[a], y = rotations[b]
                        rotation = simd_float4x4(GLTFModel.mix(simd_quatf(ix: x[0], iy: x[1], iz: x[2], r: x[3]),
                            simd_quatf(ix: y[0], iy: y[1], iz: y[2], r: y[3]), fraction))
                        depth = depths[a] + (depths[b] - depths[a]) * fraction
                    } else {
                        var facing = cameraTransform; facing.columns.3 = SIMD4(0, 0, 0, 1)
                        var parentRotation = bone; parentRotation.columns.3 = SIMD4(0, 0, 0, 1)
                        rotation = simd_inverse(parentRotation) * facing * simd_float4x4(simd_quatf(angle: state[6], axis: SIMD3(0, 0, 1)))
                        depth = 1
                    }
                    guard abs(depth) >= 0.00001 else { continue }
                    let transform = bone * placement * rotation * simd_float4x4(diagonal: SIMD4(state[4], state[5], depth, 1))
                    func custom(_ values: [[Float]]?) -> SIMD4<Float> {
                        guard let values else { return .zero }
                        let x = values[a], y = values[b]
                        return SIMD4(x[0] + (y[0]-x[0])*fraction, x[1] + (y[1]-x[1])*fraction,
                                     x[2] + (y[2]-x[2])*fraction, x[3] + (y[3]-x[3])*fraction)
                    }
                    let draw = try instance.packet(modelTransform: transform, viewTransform: view, projectionTransform: projection,
                        cameraPosition: cameraPosition, tick: fight.erlangLiveTick,
                        color: SIMD4(state[7], state[8], state[9], state[10]),
                        custom1: custom(track.customData1), custom2: custom(track.customData2),
                        stableRandom: SIMD4(track.stableRandom[0], track.stableRandom[1], track.stableRandom[2], track.stableRandom[3]),
                        uvTransform: SIMD4(state[11], state[12], state[13], state[14]), sourceTransparency: nil)
                    let emitterKey = Emitter(owner: model.owner, model: model.id, binding: bindingIndex,
                                             source: track.sourceParticleSystem, material: track.material)
                    let emitter: Int
                    if let existing = emitters[emitterKey] { emitter = existing }
                    else { emitter = emitters.count; emitters[emitterKey] = emitter }
                    packets.append(.init(draw: draw, order: .init(emitter: emitter,
                        sortingLayer: track.sourceSortingLayer, sortingOrder: track.sortingOrder,
                        renderQueue: track.sourceRenderQueue, mode: track.sourceSortMode,
                        age: track.age(at: time), viewDepth: Double((view * transform.columns.3).z))))
                    guard packets.count <= 1536 else { throw DuelTriadSourceMaterial.Failure.frame }
                }
            }
        }
        instances = instances.filter { active.contains($0.key) }
        return packets
    }
    func reset() { instances.removeAll(keepingCapacity: true) }
    func shutdown() { reset() }
}
