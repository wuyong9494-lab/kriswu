import Foundation
import SceneKit
import UIKit
import Metal
import simd

/// H17 particles, original meshes and world-space trails share the source clock.
/// Every private material program and texture is independently byte-pinned.
@MainActor
final class DuelTriadEffectAssets {
    enum Failure: Error { case manifest, resource(String), track(String) }
    struct Geometry: Decodable {
        let positions: [Float]
        let normals: [Float]
        let uv: [Float]
        let indices: [UInt32]
        let uv1: [Float]?
        let colors: [Float]?
        let tangents: [Float]?
    }
    struct Track: Decodable {
        let name: String
        let layer: Int
        let texture: String
        let blend: String
        let wrapS: Int
        let wrapT: Int
        let multiplyTextureAlpha: Bool
        let overlay: Bool
        let sortingOrder: Int
        let sourceParticleSystem: String
        let sourceSortMode: Int
        let sourceSortingLayer: Int
        let sourceRenderQueue: Int
        let sourceAgeOffset: Double
        let delay: Double
        let duration: Double
        /// t, source XYZ, width/height, angle, RGBA, UV offset XY, UV scale XY.
        let frames: [[Float]]
        /// Source emitter period; exporters split overlapping lifetimes into
        /// separate rotating tracks rather than truncate living particles.
        let loopPeriod: Double?
        let geometry: Geometry?
        let orientations: [[Float]]?
        let depthScales: [Float]?
        let material: String
        let vertexStreams: [Int]
        let customData1: [[Float]]?
        let customData2: [[Float]]?
        let stableRandom: [Float]
        func age(at time: Double) -> Double {
            let elapsed = max(0, time - delay)
            return (loopPeriod.map { elapsed.truncatingRemainder(dividingBy: $0) } ?? elapsed) + sourceAgeOffset
        }
        func interval(at time: Double) -> (Int, Int, Float)? {
            let elapsed = time - delay
            guard elapsed >= 0 else { return nil }
            let local = loopPeriod.map { elapsed.truncatingRemainder(dividingBy: $0) } ?? elapsed
            guard local < duration else { return nil }
            if local <= Double(frames[0][0]) { return (0, 0, 0) }
            var low = 0, high = frames.count - 1
            while high - low > 1 {
                let middle = (low + high) / 2
                if Double(frames[middle][0]) <= local { low = middle } else { high = middle }
            }
            return (low, high, min(1, max(0, Float((local - Double(frames[low][0])) /
                Double(frames[high][0] - frames[low][0])))))
        }
    }
    struct HistoryTrail: Decodable {
        let name: String
        let material: String
        let vertexStreams: [Int]
        let layer: Int
        let sortingOrder: Int
        let sourceParticleSystem: String
        let sourceSortMode: Int
        let sourceSortingLayer: Int
        let sourceRenderQueue: Int
        let sourceAgeOffset: Double
        let birth: Double
        let life: Double
        let tailLife: Double
        let minVertexDistance: Float
        let width: Float
        let positions: [[Float]]
        let widthOverTrail: [[Float]]
        let colorOverLifetime: [[Float]]
        let colorOverTrail: [[Float]]
        let particleColor: [Float]
        let textureMode: Int
        let textureScale: [Float]
        let worldSpace: Bool
        let dieWithParticles: Bool
        let inheritParticleColor: Bool
        let sizeAffectsWidth: Bool
        let sizeAffectsLifetime: Bool
        let sourceSimulationSpace: Int
        let sourceScalingMode: Int
        let generateLightingData: Bool
        /// Curves retain their source key positions. The four recovered H17
        /// width curves are constant and their colour gradients are linear.
        func sample(_ curve: [[Float]], at time: Float) -> [Float] {
            guard let first = curve.first, let last = curve.last else { return [] }
            if time <= first[0] { return Array(first.dropFirst()) }
            if time >= last[0] { return Array(last.dropFirst()) }
            let high = curve.firstIndex { $0[0] > time }!
            let a = curve[high - 1], b = curve[high], t = (time - a[0]) / (b[0] - a[0])
            return (1..<a.count).map { a[$0] + (b[$0] - a[$0]) * t }
        }
    }
    struct Controller: Decodable {
        let takeInAccountCharacterDirection: Int
        let _rotateAttachToLocal: Int
    }
    struct Effect: Decodable {
        let sourceName: String
        let duration: Double
        let sourceDurationOverride: Double?
        let tracks: [Track]
        let historyTrails: [HistoryTrail]?
        let sourceController: Controller?
    }
    struct PositionCondition: Decodable {
        enum Value: String, Decodable { case targetCOMX, ownerCOMX, ownerPelvisX, zero }
        enum Comparison: String, Decodable { case greater, less, greaterOrEqual, lessOrEqual }
        let left: Value
        let comparison: Comparison
        let right: Value
        func accepts(_ a: Float, _ b: Float) -> Bool {
            switch comparison {
            case .greater: return a > b
            case .less: return a < b
            case .greaterOrEqual: return a >= b
            case .lessOrEqual: return a <= b
            }
        }
    }
    /// Independent magic models use their own five-bone source skeleton.
    /// Matrices are right-facing, in metres, and retain source root motion
    /// relative to the X-aligned birth position. They contain no actor scale.
    struct SourceModel: Decodable {
        let sourceModel: String
        let clip: String
        let frames: Int
        let sourceSHA256: String
        let sourceBoneConfigurationSHA256: String
        let samplesPerSourceFrame: Int
        let bones: [String: [[Float]]]
        let endEventTick: Int
        func transform(bone: String, tick: Int) -> simd_float4x4? {
            guard let samples = bones[bone], !samples.isEmpty else { return nil }
            let value = samples[min(samples.count - 1, max(0, tick))]
            return simd_float4x4(columns: (
                SIMD4(value[0], value[1], value[2], value[3]),
                SIMD4(value[4], value[5], value[6], value[7]),
                SIMD4(value[8], value[9], value[10], value[11]),
                SIMD4(value[12], value[13], value[14], value[15])))
        }
    }
    struct Binding: Decodable {
        enum Anchor: String, Decodable { case owner, target, release, contact, sourceModel, arena }
        let id: String
        let event: DuelTriadAudioBinding.EventKind
        let ability: DuelTriadRules.Ability?
        let phase: DuelTriadState.Phase?
        let origin: DuelTriadState.Origin?
        let contactKind: String?
        let effect: String
        let anchor: Anchor
        let bone: String?
        let follow: Bool
        let attachToLocal: Bool?
        let loopUntil: DuelTriadAudioBinding.EventKind?
        let action: String?
        let looped: Bool?
        let stopFrames: Int?
        let sourcePosition: [Float]?
        let sourceFollow: [Float]?
        let sourceRoles: [String]?
        let sourceExcludedQualities: [String]?
        let sourceRequiredQuality: String?
        let sourceSingleInstance: Bool?
        let sourcePositionCondition: PositionCondition?
        let sourceOncePerRound: String?
        let sourceRoundScope: String?
        var cue: DuelTriadAudioBinding.Cue {
            .init(id: id, event: event, ability: ability, phase: phase, origin: origin,
                contactKind: contactKind, files: [], loopUntil: loopUntil, sourceRoles: sourceRoles,
                sourceRoundScope: sourceRoundScope)
        }
        func stops(on event: DuelTriadPresentation.Event.Kind) -> Bool {
            if cue.stops(on: event) { return true }
            switch (loopUntil, event) {
            case (.forestEnded, .effect(_, .forestEnded)), (.mistBladeEnded, .effect(_, .mistBladeEnded)),
                 (.rootReleased, .effect(_, .controlReleased(_, .root))): return true
            default: return false
            }
        }
    }
    struct Marker: Decodable {
        let id: String
        let clip: String
        let sourceFrame: Int
        let effect: String
        let bone: String?
        let follow: Bool
        let sourceMirrorPose: Bool?
        let attachToLocal: Bool?
        let anchor: Binding.Anchor?
        let summonRole: String?
        let loopUntil: DuelTriadAudioBinding.EventKind?
        let action: String?
        let looped: Bool?
        let stopFrames: Int?
        let sourcePosition: [Float]?
        let sourceFollow: [Float]?
        let sourceExcludedQualities: [String]?
        let sourceRequiredQuality: String?
        let sourceSingleInstance: Bool?
        let sourcePositionCondition: PositionCondition?
        let sourceOncePerRound: String?
        let sourceRoundScope: String?
        var binding: Binding {
            .init(id: id, event: .castStarted, ability: nil, phase: nil, origin: nil, contactKind: nil,
                effect: effect, anchor: anchor ?? .owner, bone: bone, follow: follow,
                attachToLocal: attachToLocal, loopUntil: loopUntil, action: action, looped: looped,
                stopFrames: stopFrames, sourcePosition: sourcePosition, sourceFollow: sourceFollow,
                sourceRoles: summonRole.map { [$0] }, sourceExcludedQualities: sourceExcludedQualities,
                sourceRequiredQuality: sourceRequiredQuality, sourceSingleInstance: sourceSingleInstance,
                sourcePositionCondition: sourcePositionCondition, sourceOncePerRound: sourceOncePerRound,
                sourceRoundScope: sourceRoundScope)
        }
    }
    private struct Document: Decodable {
        let version: Int
        let profileID: String
        let characterSHA256: String
        let sourceConfigurationSHA256: String
        let evidence: [String]
        let sampleRate: Int
        let worldUnitsPerSourceUnit: Float
        let files: [DuelFighterAssetRelease.File]
        let effects: [String: Effect]
        let bindings: [Binding]
        let markers: [Marker]
        let materials: [String: DuelTriadSourceMaterial.Descriptor]
        let sourceModels: [String: SourceModel]?
    }
    let verifiedFiles: [DuelNetworkContentRecord]
    let effects: [String: Effect]
    let bindings: [Binding]
    let markers: [Marker]
    let sourceFrames: [String: Int]
    let companions: DuelTriadSummonAssets?
    let sourceModels: [String: SourceModel]
    /// This native source renderer explicitly chooses the recovered "high"
    /// effect preset. It is independent of Unity's QualitySettings index.
    static let sourceQuality = "high"
    let units: Float
    private let materials: [String: DuelTriadSourceMaterial.Descriptor]
    private let programData: [String: Data]
    private let textureData: [String: Data]

    init(directory: URL, manifestName: String, expectedSHA256: String, profile: DuelWeaponProfile,
         companions: DuelTriadSummonAssets? = nil) throws {
        func read(_ file: DuelFighterAssetRelease.File, maximum: Int) throws -> Data {
            try file.validate(maximum: maximum)
            let url = directory.appendingPathComponent(file.name)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  values.fileSize == file.bytes else { throw Failure.resource(file.name) }
            let data = try Data(contentsOf: url)
            guard data.count == file.bytes, DuelNetworkContentRecord.digest(data) == file.sha256 else { throw Failure.resource(file.name) }
            return data
        }
        guard profile.isTriad, DuelFighterAssetRelease.File.validName(manifestName),
              (manifestName.hasSuffix(".json") || manifestName.hasSuffix(".json.gz")),
              DuelFighterAssetRelease.validDigest(expectedSHA256) else { throw Failure.manifest }
        let count = try directory.appendingPathComponent(manifestName).resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let data = try read(.init(name: manifestName, bytes: count, sha256: expectedSHA256), maximum: 32_000_000)
        let json = manifestName.hasSuffix(".gz") ? try DuelBoundedGzip.decode(data, maximum: 256_000_000) : data
        let document = try JSONDecoder().decode(Document.self, from: json)
        guard document.version == 1, document.profileID == profile.id, document.characterSHA256 == profile.sha256,
              DuelFighterAssetRelease.validDigest(document.sourceConfigurationSHA256),
              (1...32).contains(document.evidence.count), document.evidence.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 }),
              (30...240).contains(document.sampleRate), document.worldUnitsPerSourceUnit.isFinite,
              (0.0001...1).contains(document.worldUnitsPerSourceUnit),
              (1...64).contains(document.effects.count), (1...256).contains(document.files.count),
              (1...128).contains(document.materials.count),
              Set(document.files.map(\.name)).count == document.files.count,
              document.bindings.count <= 128, document.markers.count <= 1024,
              Set(document.bindings.map(\.id)).count == document.bindings.count,
              Set(document.markers.map(\.id)).count == document.markers.count else { throw Failure.manifest }
        var images = Set<String>(), programs: [String: Data] = [:], sourceTextures: [String: Data] = [:]
        var records = [DuelNetworkContentRecord(path: manifestName, bytes: data.count, sha256: expectedSHA256)]
        var imageBytes = 0, samples = 0, vertices = 0
        for file in document.files {
            imageBytes += file.bytes; guard imageBytes <= 40_000_000 else { throw Failure.manifest }
            let maximum = file.name.hasSuffix(".metal") ? 256_000 : file.name.hasSuffix(".texture") ? 8_000_000 : 4_000_000
            let bytes = try read(file, maximum: maximum)
            if file.name.hasSuffix(".png") {
                guard let image = UIImage(data: bytes), let cg = image.cgImage,
                      (1...2048).contains(cg.width), (1...2048).contains(cg.height) else { throw Failure.resource(file.name) }
                images.insert(file.name)
            } else if file.name.hasSuffix(".metal") { programs[file.name] = bytes }
            else if file.name.hasSuffix(".texture") { sourceTextures[file.name] = bytes }
            else { throw Failure.resource(file.name) }
            records.append(.init(path: file.name, bytes: bytes.count, sha256: file.sha256))
        }
        var referenced = Set<String>()
        func validSort(_ emitter: String, _ mode: Int, _ layer: Int, _ queue: Int, _ age: Double) -> Bool {
            emitter.range(of: "^-?[0-9]{1,20}$", options: .regularExpression) != nil &&
                [0, 2, 3, 4].contains(mode) && layer == 0 && (0...5000).contains(queue) &&
                age.isFinite && (0...36_000).contains(age)
        }
        for (id, material) in document.materials {
            guard !id.isEmpty, id.utf8.count <= 128 else { throw Failure.manifest }
            try material.validate()
            guard let program = programs[material.program.file], program.count == material.program.bytes,
                  DuelNetworkContentRecord.digest(program) == material.program.sha256 else { throw Failure.resource(material.program.file) }
            referenced.insert(material.program.file)
            for texture in material.textures.values {
                guard images.contains(texture.file), sourceTextures[texture.dataFile] != nil else { throw Failure.resource(texture.file) }
                referenced.insert(texture.file); referenced.insert(texture.dataFile)
            }
        }
        for (id, effect) in document.effects {
            guard !id.isEmpty, id.utf8.count <= 128, !effect.sourceName.isEmpty, effect.sourceName.utf8.count <= 512,
                  effect.duration.isFinite, (0.001...36_000).contains(effect.duration),
                  effect.sourceDurationOverride.map({ $0.isFinite && (0.001...36_000).contains($0) }) ?? true,
                  effect.tracks.count <= 4096, (effect.historyTrails?.count ?? 0) <= 16,
                  !effect.tracks.isEmpty || !(effect.historyTrails ?? []).isEmpty,
                  effect.sourceController.map({ (0...1).contains($0.takeInAccountCharacterDirection) &&
                      (0...1).contains($0._rotateAttachToLocal) }) ?? true else { throw Failure.manifest }
            for track in effect.tracks {
                referenced.insert(track.texture); samples += track.frames.count
                guard samples <= 1_000_000, images.contains(track.texture), document.materials[track.material] != nil,
                      track.vertexStreams.count <= 16, Set(track.vertexStreams).count == track.vertexStreams.count,
                      track.stableRandom.count == 4, track.stableRandom.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                      !track.name.isEmpty, track.name.utf8.count <= 256, (0...4095).contains(track.layer),
                      ["alpha", "add"].contains(track.blend), (0...1).contains(track.wrapS), (0...1).contains(track.wrapT),
                      (-1000...1000).contains(track.sortingOrder), track.delay.isFinite, track.duration.isFinite,
                      validSort(track.sourceParticleSystem, track.sourceSortMode, track.sourceSortingLayer,
                        track.sourceRenderQueue, track.sourceAgeOffset),
                      track.delay >= 0, track.duration > 0, track.delay + track.duration <= effect.duration + 0.0001,
                      (2...14_401).contains(track.frames.count), track.frames.first?.first == 0 else { throw Failure.track(track.name) }
                var previous: Float = -1
                for frame in track.frames {
                    guard frame.count == 15, frame.allSatisfy(\.isFinite), frame[0] > previous,
                          frame[1...6].allSatisfy({ abs($0) < 100_000 }),
                          frame[7...10].allSatisfy({ (0...64).contains($0) }),
                          frame[11...14].allSatisfy({ abs($0) < 1024 }) else { throw Failure.track(track.name) }
                    previous = frame[0]
                }
                guard abs(Double(previous) - track.duration) < 0.0001 else { throw Failure.track(track.name) }
                _ = try DuelTriadSourceMaterial.StreamLayout(track.vertexStreams)
                for data in [track.customData1, track.customData2].compactMap({ $0 }) {
                    guard data.count == track.frames.count, data.allSatisfy({ $0.count == 4 && $0.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) }) else {
                        throw Failure.track(track.name)
                    }
                }
                if let period = track.loopPeriod {
                    guard period.isFinite, (0.001...36_000).contains(period), period + 0.0001 >= track.duration else { throw Failure.track(track.name) }
                }
                if let geometry = track.geometry {
                    let count = geometry.positions.count / 3; vertices += count
                    // Original emitters repeat their mesh for independent
                    // living particles: the recovered set totals 540,305
                    // serialized vertices, while GPU geometry is deduplicated.
                    guard vertices <= 600_000, (3...50_000).contains(count), geometry.positions.count == count * 3,
                          geometry.normals.count == count * 3, geometry.uv.count == count * 2,
                          [geometry.positions, geometry.normals, geometry.uv].allSatisfy({ $0.allSatisfy(\.isFinite) }),
                          geometry.uv1.map({ $0.count == count * 2 && $0.allSatisfy(\.isFinite) }) ?? true,
                          geometry.colors.map({ $0.count == count * 4 && $0.allSatisfy(\.isFinite) }) ?? true,
                          geometry.tangents.map({ $0.count == count * 4 && $0.allSatisfy(\.isFinite) }) ?? true,
                          geometry.positions.allSatisfy({ abs($0) < 100_000 }),
                          !geometry.indices.isEmpty, geometry.indices.count <= 150_000, geometry.indices.count % 3 == 0,
                          geometry.indices.allSatisfy({ Int($0) < count }),
                          let rotations = track.orientations, rotations.count == track.frames.count,
                          rotations.allSatisfy({ $0.count == 4 && $0.allSatisfy(\.isFinite) &&
                              abs($0.reduce(0) { $0 + $1 * $1 } - 1) < 0.002 }),
                          let depth = track.depthScales, depth.count == track.frames.count,
                          depth.allSatisfy({ $0.isFinite && abs($0) < 100_000 }) else { throw Failure.track(track.name) }
                } else if track.orientations != nil || track.depthScales != nil { throw Failure.track(track.name) }
            }
            for trail in effect.historyTrails ?? [] {
                func curve(_ values: [[Float]], width: Int, maximumTime: Float) -> Bool {
                    guard (2...256).contains(values.count), values.first?.first == 0,
                          abs((values.last?.first ?? -1) - maximumTime) < 0.0001 else { return false }
                    var previous: Float = -1
                    for value in values {
                        guard value.count == width, value.allSatisfy({ $0.isFinite && abs($0) < 100_000 }),
                              value[0] > previous else { return false }
                        previous = value[0]
                    }
                    return true
                }
                guard !trail.name.isEmpty, trail.name.utf8.count <= 256,
                      document.materials[trail.material] != nil,
                      (0...4095).contains(trail.layer), (-1000...1000).contains(trail.sortingOrder),
                      validSort(trail.sourceParticleSystem, trail.sourceSortMode, trail.sourceSortingLayer,
                        trail.sourceRenderQueue, trail.sourceAgeOffset),
                      trail.birth.isFinite, trail.birth >= 0, trail.life.isFinite, (0.001...1).contains(trail.life),
                      trail.tailLife.isFinite, (0.001...1).contains(trail.tailLife),
                      trail.birth + trail.life + trail.tailLife <= effect.duration + 0.0001,
                      trail.minVertexDistance.isFinite, (0.0001...1000).contains(trail.minVertexDistance),
                      trail.width.isFinite, (0.0001...10_000).contains(trail.width),
                      trail.worldSpace, !trail.dieWithParticles, !trail.sizeAffectsWidth, !trail.sizeAffectsLifetime,
                      trail.sourceSimulationSpace == 0, trail.sourceScalingMode == 1,
                      trail.textureMode == 0, !trail.generateLightingData,
                      trail.textureScale.count == 2, trail.textureScale.allSatisfy({ $0.isFinite && abs($0) < 1000 }),
                      trail.particleColor.count == 4, trail.particleColor.allSatisfy({ $0.isFinite && (0...64).contains($0) }),
                      curve(trail.positions, width: 4, maximumTime: Float(trail.life)),
                      curve(trail.widthOverTrail, width: 2, maximumTime: 1),
                      curve(trail.colorOverLifetime, width: 5, maximumTime: 1),
                      curve(trail.colorOverTrail, width: 5, maximumTime: 1) else { throw Failure.track(trail.name) }
                _ = try DuelTriadSourceMaterial.StreamLayout(trail.vertexStreams)
            }
        }
        guard referenced == Set(document.files.map(\.name)) else { throw Failure.manifest }
        func validID(_ id: String) -> Bool { id.range(of: "^[A-Za-z0-9_-]{1,96}$", options: .regularExpression) != nil }
        func validAction(_ action: String?, _ looped: Bool?, _ frames: Int?, _ position: [Float]?,
                         _ follow: [Float]?, _ excluded: [String]?, _ required: String?) -> Bool {
            let qualities: Set<String> = ["min", "low", "medium", "high", "ultra"]
            return (action.map({ ["play", "stop"].contains($0) }) ?? true) &&
                (frames.map({ (0...600).contains($0) }) ?? true) &&
                (position.map({ $0.count == 3 && $0.allSatisfy({ $0.isFinite && abs($0) <= 100_000 }) }) ?? true) &&
                (follow.map({ $0.count == 3 && $0.allSatisfy({ $0 == 0 || $0 == 1 }) }) ?? true) &&
                (excluded.map({ Set($0).isSubset(of: qualities) && Set($0).count == $0.count }) ?? true) &&
                (required.map({ qualities.contains($0) }) ?? true)
        }
        let companionRoles = Set(companions?.roles.keys.map { $0 } ?? [])
        for (key, model) in document.sourceModels ?? [:] {
            guard ["roots", "mistWave", "rootAttack"].contains(key),
                  !model.sourceModel.isEmpty, model.sourceModel.utf8.count <= 128,
                  !model.clip.isEmpty, model.clip.utf8.count <= 128,
                  (2...1024).contains(model.frames), model.samplesPerSourceFrame == 2,
                  DuelFighterAssetRelease.validDigest(model.sourceSHA256),
                  DuelFighterAssetRelease.validDigest(model.sourceBoneConfigurationSHA256),
                  (0..<(model.frames * 2)).contains(model.endEventTick),
                  Set(model.bones.keys) == Set(["magic_joint_root", "magic_joint_left", "magic_joint_right", "magic_joint_top", "magic_joint_bottom"]),
                  model.bones.values.allSatisfy({ values in
                      values.count == (model.frames - 1) * 2 + 1 && values.allSatisfy({ value in
                          value.count == 16 && value.allSatisfy({ $0.isFinite && abs($0) <= 10_000 }) &&
                          value[3] == 0 && value[7] == 0 && value[11] == 0 && value[15] == 1
                      })
                  }) else { throw Failure.manifest }
            let base = key == "rootAttack" ? "roots" : key
            guard let geometry = profile.triadRules?.runtime?.modelTracks?[base],
                  geometry.clip == model.clip, geometry.sourceSHA256 == model.sourceSHA256,
                  geometry.boneConfigurationSHA256 == model.sourceBoneConfigurationSHA256,
                  (key == "rootAttack" ? (model.frames == 11 && model.endEventTick == 20) :
                    (geometry.frames == model.frames && model.endEventTick == 2 * (model.frames - 1))) else {
                throw Failure.manifest
            }
        }
        func validScope(_ scope: String?, _ once: String?) -> Bool {
            (scope == nil || scope == "first") && (once == nil || once == "H17_LOSS_EFFECTS")
        }
        for binding in document.bindings {
            guard validID(binding.id), document.effects[binding.effect] != nil,
                  binding.bone.map({ !$0.isEmpty && $0.utf8.count <= 128 }) ?? true,
                  validAction(binding.action, binding.looped, binding.stopFrames, binding.sourcePosition,
                      binding.sourceFollow, binding.sourceExcludedQualities, binding.sourceRequiredQuality),
                  binding.sourceRoles.map({ !$0.isEmpty && Set($0).isSubset(of: companionRoles) }) ?? true,
                  validScope(binding.sourceRoundScope, binding.sourceOncePerRound),
                  (binding.anchor == .owner || binding.anchor == .target || binding.anchor == .sourceModel) ||
                    (!binding.follow && binding.bone == nil) else { throw Failure.manifest }
            switch binding.event {
            case .castStarted, .castPhase:
                guard binding.ability != nil, binding.phase != nil, binding.origin == nil, binding.contactKind == nil else { throw Failure.manifest }
            case .attackReleased, .soulAppeared, .soulSummoned:
                guard binding.ability != nil, binding.origin != nil, binding.phase == nil, binding.contactKind == nil else { throw Failure.manifest }
            case .contact:
                guard binding.ability != nil, binding.phase == nil, binding.origin == nil,
                      binding.contactKind == "hit" || binding.contactKind == "block" else { throw Failure.manifest }
            default:
                guard binding.ability == nil, binding.phase == nil, binding.origin == nil, binding.contactKind == nil else { throw Failure.manifest }
            }
            if let stop = binding.loopUntil {
                guard (binding.event == .forestStarted && stop == .forestEnded) ||
                      (binding.event == .mistBladeStarted && stop == .mistBladeEnded) ||
                      (binding.ability == .branches && stop == .rootReleased) ||
                      stop == .sourceRoundFightEnded || stop == .sourceRootModelEnded ||
                      stop == .sourceSoulAnimationEnded else { throw Failure.manifest }
            }
        }
        for marker in document.markers {
            let count = marker.summonRole.flatMap { role -> Int? in
                guard let binding = companions?.roles[role], binding.motion.clip == marker.clip else { return nil }
                return binding.motion.frames
            } ?? profile.clip(named: marker.clip)?.frames
            guard validID(marker.id), document.effects[marker.effect] != nil, let count,
                  (0..<count).contains(marker.sourceFrame),
                  validAction(marker.action, marker.looped, marker.stopFrames, marker.sourcePosition,
                      marker.sourceFollow, marker.sourceExcludedQualities, marker.sourceRequiredQuality),
                  validScope(marker.sourceRoundScope, marker.sourceOncePerRound),
                  marker.bone.map({ !$0.isEmpty && $0.utf8.count <= 128 }) ?? true else { throw Failure.manifest }
        }
        effects = document.effects; bindings = document.bindings; markers = document.markers
        units = document.worldUnitsPerSourceUnit; materials = document.materials
        programData = programs; textureData = sourceTextures
        sourceFrames = Dictionary(uniqueKeysWithValues: profile.clips.map { ($0.name, $0.frames) })
        self.companions = companions
        sourceModels = document.sourceModels ?? [:]
        verifiedFiles = records.sorted { $0.path < $1.path }
    }

    func prepare(device: MTLDevice?, formats: [DuelTriadSourceMaterial.Format]) throws -> DuelTriadSourceMaterial.Factory {
        try .init(materials: materials, programData: programData, textureData: textureData,
                  device: device, formats: formats)
    }
    func makeInstance(_ track: Track, factory: DuelTriadSourceMaterial.Factory) throws -> DuelTriadSourceMaterial.Instance {
        let geometry: DuelTriadSourceMaterial.Geometry
        if let mesh = track.geometry {
            geometry = .init(positions: mesh.positions.map { $0 * units }, normals: mesh.normals, uv: mesh.uv,
                uv1: mesh.uv1, colors: mesh.colors, tangents: mesh.tangents, indices: mesh.indices)
        } else {
            let half = units * 0.5
            geometry = .init(positions: [-half,-half,0, half,-half,0, half,half,0, -half,half,0],
                normals: [0,0,1, 0,0,1, 0,0,1, 0,0,1], uv: [0,1, 1,1, 1,0, 0,0], uv1: nil,
                colors: nil, tangents: [1,0,0,1, 1,0,0,1, 1,0,0,1, 1,0,0,1], indices: [0,1,2, 0,2,3])
        }
        return try factory.make(id: track.material, geometry: geometry, vertexStreams: track.vertexStreams, units: units)
    }
}

@MainActor
final class DuelTriadSourceEffects {
    private enum Source: Hashable {
        case actor(Int), soul(Int, UInt64), model(Int, UInt64), arena
    }
    private struct Model {
        let kind: DuelTriadPresentation.SourceEvent.ModelKind
        let origin: SIMD3<Float>
        let direction: Int
        let born: Int
        var rootContactAt: Int?
    }
    private struct Burst {
        let binding: String
        let effect: String
        let owner: Int
        let source: Source
        let bone: String?
        let follow: Bool
        let followAxes: SIMD3<Float>
        let attachToLocal: Bool
        let offset: SIMD3<Float>
        let loops: Bool
        let loopUntil: DuelTriadAudioBinding.EventKind?
        let born: Int
        let direction: Float
        let root: SCNNode
        var particles: [Int: DuelTriadSourceMaterial.Instance] = [:]
        var histories: [Int: DuelSourceParticleTrail] = [:]
        var capturedBone = false
        var sampledTick = -1
        var stoppedAt: Int?
        var stopTicks = 0
        var initialSummon: DuelTriadPresentation.Summon?
        func transparency(at tick: Int) -> Float? {
            guard let stoppedAt else { return nil }
            return max(0, 1 - Float(max(0, tick - stoppedAt)) / Float(max(1, stopTicks)))
        }
    }
    private struct Action {
        let binding: DuelTriadEffectAssets.Binding
        let owner: Int
        let source: Source
        let position: SIMD3<Float>
        let direction: Int
        let tick: Int
        let initialSummon: DuelTriadPresentation.Summon?
    }
    private enum Pending {
        case action(Action)
        case event(owner: Int, source: Source?, kind: DuelTriadPresentation.Event.Kind, tick: Int)
    }
    private struct SoulSample { let role: String; let tick: Int }
    private struct ParticleEmitter: Hashable {
        let burst: Int
        let source: String
        let material: String
    }
    private let assets: DuelTriadEffectAssets
    private let factory: DuelTriadSourceMaterial.Factory
    private let root = SCNNode()
    private var bursts: [Burst] = []
    private var pending: [Pending] = []
    private var models: [Source: Model] = [:]
    private var souls: [Source: DuelTriadPresentation.Summon] = [:]
    private var soulSamples: [Source: SoulSample] = [:]
    private var oncePerRound = Set<String>()
    private var round = -1, frame = -1, clock = 0, lastLiveTick = 0
    private var wasFighting = true
    private var eventSequences = Set<Int>(), sampleSequences = Set<Int>()
    private static let particleBudget = 1536
    private static let burstBudget = 128
    private static let arenaOrigin = SIMD3<Float>(Float(DuelGame.leftWall + DuelGame.rightWall) / 2000, 0, 0)
    var activeSourceEffectIDs: [String] { Array(Set(bursts.map(\.effect))).sorted() }
    init(assets: DuelTriadEffectAssets, factory: DuelTriadSourceMaterial.Factory, parent: SCNNode) {
        self.assets = assets; self.factory = factory; root.name = "duel.triad.source-effects"; parent.addChildNode(root)
    }
    /// Event consumption queues source operations in their original order.
    /// Bone attachment is resolved only after the fixed-step pose is available.
    func consume(_ fight: DuelWeaponFight) throws {
        guard fight.frame >= frame else { return }
        if round != fight.roundNumber {
            reset(); round = fight.roundNumber
        }
        if fight.frame != frame {
            let live = fight.triadPresentation.liveTick
            if fight.phase == .fighting || wasFighting { clock += max(0, live - lastLiveTick) }
            else if frame >= 0 { clock += max(0, fight.frame - frame) }
            lastLiveTick = live; wasFighting = fight.phase == .fighting
            frame = fight.frame; eventSequences.removeAll(keepingCapacity: true); sampleSequences.removeAll(keepingCapacity: true)
        }
        prune(at: clock)
        for summon in fight.triadPresentation.summons {
            souls[.soul(summon.owner, summon.id)] = summon
        }
        for event in fight.triadPresentationEvents {
            guard event.id.frame == frame, eventSequences.insert(event.id.sequence).inserted else { continue }
            let owner: Int
            switch event.kind {
            case .castStarted(let value, _), .effect(let value, _), .source(let value, _): owner = value
            case .attackReleased(let volume): owner = volume.owner
            case .contact(let contact): owner = contact.owner
            }
            let tick = clock - max(0, fight.triadPresentation.liveTick - event.liveTick)
            if case .attackReleased(let volume) = event.kind,
               let kind = volume.sourceModelKind, let position = volume.sourceOrigin {
                let key = Source.model(owner, volume.attackID)
                if models[key] == nil {
                    models[key] = .init(kind: kind, origin: vector(position), direction: volume.direction,
                        born: tick, rootContactAt: nil)
                }
            }
            if case .contact(let contact) = event.kind, contact.kind == .hit,
               contact.ability == .branches, let id = contact.attackID {
                let key = Source.model(owner, id)
                if models[key]?.rootContactAt == nil { models[key]?.rootContactAt = tick }
            }
            let source = eventSource(event.kind, owner: owner)
            if let summon = event.sourceSummon { souls[.soul(owner, summon.id)] = summon }
            pending.append(.event(owner: owner, source: source, kind: event.kind, tick: tick))
            for binding in assets.bindings where binding.cue.matches(event.kind) {
                try enqueue(binding, owner: owner, eventSource: source, event: event.kind,
                    summon: event.sourceSummon, tick: tick, fight: fight)
            }
        }
        for sample in fight.sourceMotionSamples {
            guard sample.frame == frame, sampleSequences.insert(sample.sequence).inserted,
                  let count = assets.sourceFrames[sample.clip] else { continue }
            for marker in assets.markers where marker.summonRole == nil && marker.sourceMirrorPose != true &&
                marker.clip == sample.clip && sample.crosses(sourceFrame: marker.sourceFrame, totalSourceFrames: count) {
                try enqueue(marker.binding, owner: sample.owner, eventSource: nil, event: nil,
                    summon: nil, tick: clock, fight: fight)
            }
        }
        // Companion animation markers use each original model's own clock.
        for summon in fight.triadPresentation.summons {
            let key = Source.soul(summon.owner, summon.id), role = summon.motionRole
            guard let motion = assets.companions?.roles[role]?.motion else { continue }
            let previous = soulSamples[key]
            let before = previous?.role == role ? previous!.tick : -1
            for marker in assets.markers where marker.summonRole == role && marker.clip == motion.clip && marker.sourceMirrorPose != true {
                let at = marker.sourceFrame * summon.lastSampleTick / max(1, motion.frames - 1)
                guard before < at, at <= summon.motionTick else { continue }
                try enqueue(marker.binding, owner: summon.owner, eventSource: key, event: nil,
                    summon: summon, tick: clock, fight: fight)
            }
            soulSamples[key] = .init(role: role, tick: summon.motionTick)
        }
        guard pending.count <= 512 else { throw DuelTriadSourceMaterial.Failure.frame }
    }
    private func eventSource(_ event: DuelTriadPresentation.Event.Kind, owner: Int) -> Source? {
        guard case .source(_, let source) = event else { return nil }
        switch source {
        case .modelCreated(let id, _, _), .rootModelEnded(let id): return .model(owner, id)
        case .soulModelCreated(let id, _), .soulAnimationEnded(let id, _): return .soul(owner, id)
        default: return nil
        }
    }
    private func enqueue(_ binding: DuelTriadEffectAssets.Binding, owner: Int, eventSource: Source?,
        event: DuelTriadPresentation.Event.Kind?, summon: DuelTriadPresentation.Summon?,
        tick: Int, fight: DuelWeaponFight) throws {
        guard binding.sourceRequiredQuality.map({ $0 == DuelTriadEffectAssets.sourceQuality }) ?? true,
              binding.sourceExcludedQualities?.contains(DuelTriadEffectAssets.sourceQuality) != true,
              binding.sourceRoundScope != "first" || fight.roundNumber == 1 else { return }
        let source: Source, position: SIMD3<Float>, direction: Int
        switch binding.anchor {
        case .sourceModel:
            guard let eventSource else { throw DuelTriadSourceMaterial.Failure.frame }
            source = eventSource
            if let model = models[source] { position = model.origin; direction = model.direction }
            else if let value = summon ?? souls[source] {
                position = SIMD3(Float(value.xMillimeters), Float(value.yMillimeters), Float(value.zMillimeters)) / 1000
                direction = value.direction
            } else { throw DuelTriadSourceMaterial.Failure.frame }
        case .arena:
            // Original source trigger chooses one H17 forest for the arena.
            guard fight.profiles.indices.first(where: { (fight.triadState($0)?.rules.level ?? 0) >= 2 }) == owner else { return }
            source = .arena; position = Self.arenaOrigin; direction = 1
        case .target:
            source = .actor(1 - owner); position = fighterPosition(fight.fighters[1 - owner]); direction = fight.fighters[owner].facing
        case .release:
            guard let event, case .attackReleased(let volume) = event else { throw DuelTriadSourceMaterial.Failure.frame }
            source = .actor(owner); direction = volume.direction
            position = volume.sourceOrigin.map(vector) ?? SIMD3(Float(volume.bounds.minX + volume.bounds.maxX) / 2000,
                Float(volume.bounds.minY) / 1000, 0)
        case .contact:
            guard let event, case .contact(let contact) = event else { throw DuelTriadSourceMaterial.Failure.frame }
            source = .actor(owner); position = vector(contact.position); direction = contact.direction
        case .owner:
            source = summon.map { .soul(owner, $0.id) } ?? .actor(owner)
            position = fighterPosition(fight.fighters[owner]); direction = fight.fighters[owner].facing
        }
        pending.append(.action(.init(binding: binding, owner: owner, source: source, position: position,
            direction: direction, tick: tick, initialSummon: summon)))
    }
    var sourceBoneNames: [Int: Set<String>] {
        var names: [Int: Set<String>] = [:]
        for burst in bursts {
            if case .actor(let owner) = burst.source, let bone = burst.bone { names[owner, default: []].insert(bone) }
        }
        for item in pending {
            guard case .action(let action) = item else { continue }
            if case .actor(let owner) = action.source, let bone = action.binding.bone { names[owner, default: []].insert(bone) }
            if let condition = action.binding.sourcePositionCondition {
                for value in [condition.left, condition.right] {
                    switch value {
                    case .ownerPelvisX: names[action.owner, default: []].insert("pelvis")
                    case .ownerCOMX, .targetCOMX: break // Exact native COM is supplied by the authoritative profile.
                    case .zero: break
                    }
                }
            }
        }
        return names
    }
    private func sourceTransform(_ source: Source, bone: String?, initial: DuelTriadPresentation.Summon?,
        tick: Int, fight: DuelWeaponFight, bones: [Int: [String: simd_float4x4]]) -> simd_float4x4? {
        switch source {
        case .actor(let owner):
            if let bone { return bones[owner]?[bone] }
            var result = matrix_identity_float4x4; result.columns.3 = SIMD4(fighterPosition(fight.fighters[owner]), 1)
            return result
        case .soul:
            guard let summon = initial ?? souls[source] else { return nil }
            guard let bone else {
                var result = matrix_identity_float4x4
                result.columns.3 = SIMD4(Float(summon.xMillimeters) / 1000, Float(summon.yMillimeters) / 1000,
                    Float(summon.zMillimeters) / 1000, 1)
                return result
            }
            return assets.companions?.sourceBoneTransforms([bone], summon: summon)[bone]
        case .model:
            guard let model = models[source] else { return nil }
            let contactAge = model.rootContactAt.map { max(0, tick - $0) }
            let attacks = model.kind == .roots && (contactAge ?? 0) >= 30
            let name = attacks ? "rootAttack" : model.kind.rawValue
            // A hit starts ROOT_CD_ATTACK=30. Its expiry, not the initial
            // contact, starts the cropped 11-frame motion; the final pose is
            // held for the remaining ticks of each subsequent 30-tick loop.
            let age = attacks ? (contactAge! - 30) % 30 : tick - model.born
            guard let local = assets.sourceModels[name]?.transform(bone: bone ?? "magic_joint_root", tick: age) else { return nil }
            var result = simd_float4x4(simd_quatf(angle: model.direction < 0 ? .pi : 0, axis: SIMD3(0, 1, 0)))
            result.columns.3 = SIMD4(model.origin, 1)
            return result * local
        case .arena:
            var result = matrix_identity_float4x4; result.columns.3 = SIMD4(Self.arenaOrigin, 1); return result
        }
    }
    /// Called once per authoritative fixed step, including catch-up steps.
    /// Source operations never read SceneKit's previous display-frame pose.
    func sampleStep(_ fight: DuelWeaponFight, bones: [Int: [String: simd_float4x4]]) throws {
        let tick = clock
        for item in pending {
            switch item {
            case .event(let owner, let source, let event, let at):
                for index in bursts.indices {
                    guard bursts[index].owner == owner, let until = bursts[index].loopUntil,
                          source.map({ $0 == bursts[index].source }) ?? true else { continue }
                    let cue = DuelTriadAudioBinding.Cue(id: "end", event: until, ability: nil, phase: nil,
                        origin: nil, contactKind: nil, files: [], loopUntil: nil)
                    if cue.matches(event) { bursts[index].stoppedAt = at; bursts[index].stopTicks = 0 }
                }
            case .action(let action):
                let binding = action.binding
                if let condition = binding.sourcePositionCondition {
                    guard let a = positionValue(condition.left, owner: action.owner, fight: fight, bones: bones),
                          let b = positionValue(condition.right, owner: action.owner, fight: fight, bones: bones) else {
                        throw DuelTriadSourceMaterial.Failure.frame
                    }
                    guard condition.accepts(a, b) else { continue }
                }
                if let flag = binding.sourceOncePerRound {
                    guard oncePerRound.insert("\(action.owner):\(flag)").inserted else { continue }
                }
                if binding.action == "stop" {
                    for index in bursts.indices where bursts[index].owner == action.owner &&
                        bursts[index].source == action.source && bursts[index].effect == binding.effect {
                        bursts[index].stoppedAt = action.tick; bursts[index].stopTicks = binding.stopFrames ?? 0
                    }
                } else {
                    if binding.sourceSingleInstance == true && bursts.contains(where: {
                        $0.effect == binding.effect && $0.stoppedAt == nil
                    }) { continue }
                    prune(at: tick)
                    try spawn(action)
                }
            }
        }
        pending.removeAll(keepingCapacity: true)
        prune(at: tick)
        for index in bursts.indices {
            var burst = bursts[index]
            guard tick > burst.sampledTick, let effect = assets.effects[burst.effect] else { continue }
            let time = Double(max(0, tick - burst.born)) / Double(DuelGame.ticksPerSecond)
            if burst.follow || !burst.capturedBone {
                guard let transform = sourceTransform(burst.source, bone: burst.bone,
                    initial: burst.capturedBone ? nil : burst.initialSummon, tick: tick, fight: fight, bones: bones) else {
                    throw DuelTriadSourceMaterial.Failure.frame
                }
                let position = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                var attached = transform
                for column in 0..<3 {
                    let axis = SIMD3(transform[column].x, transform[column].y, transform[column].z)
                    guard simd_length_squared(axis) > 1e-12 else { throw DuelTriadSourceMaterial.Failure.frame }
                    attached[column] = SIMD4(simd_normalize(axis), 0)
                }
                let sourceOffset = effect.sourceController?._rotateAttachToLocal == 1 ?
                    (attached * SIMD4(burst.offset, 0)) : SIMD4(burst.offset, 0)
                let offset = SIMD3(sourceOffset.x, sourceOffset.y, sourceOffset.z)
                if burst.attachToLocal {
                    // The original handler copies world rotation/position,
                    // never the character's 0.92 lossy scale. _rotateAttachToLocal
                    // separately controls only the position-offset vector.
                    attached.columns.3 = SIMD4(position + offset, 1); burst.root.simdWorldTransform = attached
                } else {
                    let current = burst.root.simdWorldPosition
                    let axes = burst.capturedBone ? burst.followAxes : SIMD3<Float>(repeating: 1)
                    burst.root.simdWorldPosition = current + (position + offset - current) * axes
                }
                burst.capturedBone = true; burst.initialSummon = nil
            }
            for (trailIndex, definition) in (effect.historyTrails ?? []).enumerated() {
                guard time >= definition.birth else { continue }
                var history = try burst.histories[trailIndex] ?? DuelSourceParticleTrail(
                    lifetimeSeconds: definition.tailLife,
                    minimumVertexDistance: Double(definition.minVertexDistance * assets.units))
                let age = time - definition.birth, emitting = age < definition.life
                let position: DuelWeaponPoint?
                if emitting {
                    let local = definition.sample(definition.positions, at: Float(age))
                    let world = burst.root.simdWorldTransform * SIMD4(local[0] * assets.units,
                        local[1] * assets.units, local[2] * assets.units, 1)
                    position = .init(x: Double(world.x), y: Double(world.y), z: Double(world.z))
                } else { position = nil }
                try history.sample(tick: tick, worldPosition: position, emitting: emitting)
                burst.histories[trailIndex] = history
            }
            burst.sampledTick = tick; bursts[index] = burst
        }
        let used = Set(bursts.map(\.source))
        let liveSouls = Set(fight.triadPresentation.summons.map { Source.soul($0.owner, $0.id) })
        souls = souls.filter { used.contains($0.key) || liveSouls.contains($0.key) }
        soulSamples = soulSamples.filter { liveSouls.contains($0.key) }
        models = models.filter { key, value in
            used.contains(key) || tick - value.born <= 1200
        }
    }
    private func positionValue(_ value: DuelTriadEffectAssets.PositionCondition.Value, owner: Int,
        fight: DuelWeaponFight, bones: [Int: [String: simd_float4x4]]) -> Float? {
        switch value {
        case .zero: return Self.arenaOrigin.x
        case .ownerPelvisX: return bones[owner]?["pelvis"]?.columns.3.x
        case .ownerCOMX: return sourceCenterOfMassX(owner, fight: fight)
        case .targetCOMX: return sourceCenterOfMassX(1 - owner, fight: fight)
        }
    }
    private func sourceCenterOfMassX(_ owner: Int, fight: DuelWeaponFight) -> Float? {
        // The same authenticated mass-weighted FK samples also decide throw
        // reach. Actor X and pelvis are not substitutes for the native COM.
        fight.sourceCenterOfMass(owner).map { Float($0.x) }
    }
    func draw(_ fight: DuelWeaponFight, cameraTransform: simd_float4x4,
              projection: simd_float4x4) throws -> [DuelTriadSourceMaterial.Draw] {
        let tick = clock
        let view = simd_inverse(cameraTransform)
        let cameraPosition = SIMD3(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
        var packets: [DuelTriadSourceMaterial.Draw] = []
        var ordering: [DuelSourceParticleOrder.Item] = []
        var emitters: [ParticleEmitter: Int] = [:]
        func append(_ packet: DuelTriadSourceMaterial.Draw, burst: Int, source: String, material: String,
                    layer: Int, order: Int, queue: Int, mode: Int, age: Double, position: SIMD4<Float>) {
            let key = ParticleEmitter(burst: burst, source: source, material: material)
            let emitter: Int
            if let existing = emitters[key] { emitter = existing }
            else { emitter = emitters.count; emitters[key] = emitter }
            ordering.append(.init(emitter: emitter, sortingLayer: layer, sortingOrder: order,
                renderQueue: queue, mode: mode, age: age, viewDepth: Double((view * position).z)))
            packets.append(packet)
        }
        for index in bursts.indices {
            var burst = bursts[index]
            guard let effect = assets.effects[burst.effect] else { continue }
            let time = Double(max(0, tick - burst.born)) / Double(DuelGame.ticksPerSecond)
            if (!burst.loops && time >= effect.duration) || effect.sourceDurationOverride.map({ time >= $0 }) == true { continue }
            var active = Set<Int>()
            for (trackIndex, track) in effect.tracks.enumerated() {
                guard let (a, b, t) = track.interval(at: time) else { continue }
                let first = track.frames[a], second = track.frames[b]
                let state = first.enumerated().map { $0.offset < 11 ? $0.element + (second[$0.offset] - $0.element) * t : $0.element }
                guard abs(state[4]) >= 0.00001, abs(state[5]) >= 0.00001 else { continue }
                guard packets.count < Self.particleBudget else { throw DuelTriadSourceMaterial.Failure.frame }
                let instance: DuelTriadSourceMaterial.Instance
                if let existing = burst.particles[trackIndex] { instance = existing }
                else { instance = try assets.makeInstance(track, factory: factory); burst.particles[trackIndex] = instance }
                active.insert(trackIndex)
                let offset = SIMD3(state[1], state[2], state[3]) * assets.units
                var placement = matrix_identity_float4x4; placement.columns.3 = SIMD4(offset, 1)
                let rotation: simd_float4x4, depth: Float
                if let rotations = track.orientations, let depths = track.depthScales {
                    let x = rotations[a], y = rotations[b]
                    rotation = simd_float4x4(simd_slerp(simd_quatf(ix: x[0], iy: x[1], iz: x[2], r: x[3]),
                        simd_quatf(ix: y[0], iy: y[1], iz: y[2], r: y[3]), t))
                    depth = depths[a] + (depths[b] - depths[a]) * t
                } else {
                    var facing = cameraTransform; facing.columns.3 = SIMD4(0, 0, 0, 1)
                    var parentRotation = burst.root.simdWorldTransform; parentRotation.columns.3 = SIMD4(0, 0, 0, 1)
                    rotation = simd_inverse(parentRotation) * facing * simd_float4x4(simd_quatf(angle: state[6], axis: SIMD3(0, 0, 1)))
                    depth = 1
                }
                guard abs(depth) >= 0.00001 else { continue }
                let transform = burst.root.simdWorldTransform * placement * rotation * simd_float4x4(diagonal: SIMD4(state[4], state[5], depth, 1))
                func custom(_ values: [[Float]]?) -> SIMD4<Float> {
                    guard let values else { return .zero }
                    let x = values[a], y = values[b]
                    return SIMD4(x[0] + (y[0]-x[0])*t, x[1] + (y[1]-x[1])*t,
                                 x[2] + (y[2]-x[2])*t, x[3] + (y[3]-x[3])*t)
                }
                let draw = try instance.packet(modelTransform: transform, viewTransform: view, projectionTransform: projection,
                    cameraPosition: cameraPosition, tick: tick, color: SIMD4(state[7], state[8], state[9], state[10]),
                    custom1: custom(track.customData1), custom2: custom(track.customData2),
                    stableRandom: SIMD4(track.stableRandom[0], track.stableRandom[1], track.stableRandom[2], track.stableRandom[3]),
                    uvTransform: SIMD4(state[11], state[12], state[13], state[14]),
                    sourceTransparency: burst.transparency(at: tick))
                append(draw, burst: index, source: track.sourceParticleSystem, material: track.material,
                    layer: track.sourceSortingLayer, order: track.sortingOrder, queue: track.sourceRenderQueue,
                    mode: track.sourceSortMode, age: track.age(at: time), position: transform.columns.3)
            }
            for (trailIndex, definition) in (effect.historyTrails ?? []).enumerated() {
                guard let history = burst.histories[trailIndex],
                      let geometry = historyGeometry(definition, history: history, tick: tick,
                        age: max(0, time - definition.birth), camera: cameraPosition) else { continue }
                guard packets.count < Self.particleBudget else { throw DuelTriadSourceMaterial.Failure.frame }
                let instance = try factory.make(id: definition.material, geometry: geometry,
                    vertexStreams: definition.vertexStreams, units: assets.units, cacheGeometry: false)
                let packet = try instance.packet(modelTransform: matrix_identity_float4x4,
                    viewTransform: view, projectionTransform: projection, cameraPosition: cameraPosition,
                    tick: tick, color: SIMD4(repeating: 1), custom1: .zero, custom2: .zero,
                    stableRandom: .zero, uvTransform: SIMD4(0, 0, 1, 1),
                    sourceTransparency: burst.transparency(at: tick))
                let last = history.points(at: tick).last!.position
                append(packet, burst: index, source: definition.sourceParticleSystem, material: definition.material,
                    layer: definition.sourceSortingLayer, order: definition.sortingOrder, queue: definition.sourceRenderQueue,
                    mode: definition.sourceSortMode, age: max(0, time - definition.birth) + definition.sourceAgeOffset,
                    position: SIMD4(Float(last.x), Float(last.y), Float(last.z), 1))
            }
            burst.particles = burst.particles.filter { active.contains($0.key) }
            bursts[index] = burst
        }
        return try DuelSourceParticleOrder.indices(ordering).map { packets[$0] }
    }
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
            // widthOverTrail already contains the source's absolute width.
            let halfWidth = source.sample(source.widthOverTrail, at: u)[0] * assets.units * 0.5
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
        return .init(positions: positions, normals: normals, uv: uv, uv1: nil,
            colors: colors, tangents: nil, indices: indices)
    }
    private func fighterPosition(_ fighter: DuelGame.Fighter) -> SIMD3<Float> {
        .init(Float(fighter.x) / 1000, Float(fighter.y) / 1000 + Float(fighter.weaponPose?.groundLift ?? 0), 0)
    }
    private func vector(_ point: DuelWeaponPoint) -> SIMD3<Float> {
        .init(Float(point.x), Float(point.y), Float(point.z))
    }
    private func spawn(_ action: Action) throws {
        let binding = action.binding
        guard let source = assets.effects[binding.effect], bursts.count < Self.burstBudget else {
            throw DuelTriadSourceMaterial.Failure.frame
        }
        let holder = SCNNode()
        let offset = binding.sourcePosition.map { SIMD3($0[0], $0[1], -$0[2]) * assets.units } ?? .zero
        holder.simdPosition = action.position + offset
        holder.eulerAngles.y = source.sourceController?.takeInAccountCharacterDirection == 1 && action.direction < 0 ? .pi : 0
        holder.name = "duel.triad.fx." + binding.effect; root.addChildNode(holder)
        let axes = binding.sourceFollow.map { SIMD3($0[0], $0[1], $0[2]) } ?? SIMD3<Float>(repeating: binding.follow ? 1 : 0)
        var burst = Burst(binding: binding.id, effect: binding.effect, owner: action.owner,
            source: action.source, bone: binding.bone, follow: binding.follow || binding.attachToLocal == true,
            followAxes: axes, attachToLocal: binding.attachToLocal == true, offset: offset,
            loops: binding.looped ?? (binding.loopUntil != nil), loopUntil: binding.loopUntil,
            born: action.tick, direction: action.direction < 0 ? -1 : 1, root: holder)
        burst.initialSummon = action.initialSummon
        burst.capturedBone = binding.bone == nil && !burst.follow
        bursts.append(burst)
    }
    private func prune(at tick: Int) {
        remove { burst in
            if let stop = burst.stoppedAt, tick - stop >= burst.stopTicks { return true }
            guard let effect = assets.effects[burst.effect] else { return true }
            let elapsed = Double(max(0, tick - burst.born)) / Double(DuelGame.ticksPerSecond)
            return (!burst.loops && elapsed >= effect.duration) || effect.sourceDurationOverride.map({ elapsed >= $0 }) == true
        }
    }
    private func remove(where shouldRemove: (Burst) -> Bool) {
        bursts.removeAll { if shouldRemove($0) { $0.root.removeFromParentNode(); return true }; return false }
    }
    func reset() {
        remove { _ in true }; pending.removeAll(); models.removeAll(); souls.removeAll(); soulSamples.removeAll()
        oncePerRound.removeAll(); round = -1; frame = -1; clock = 0; lastLiveTick = 0; wasFighting = true
        eventSequences.removeAll(); sampleSequences.removeAll()
    }
    func shutdown() { reset(); root.removeFromParentNode() }
}
