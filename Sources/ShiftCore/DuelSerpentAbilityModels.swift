import Foundation

/// Original independent D13 model geometry, kept separate from the humanoid.
/// A resource loader must authenticate `documentSHA256` before constructing this
/// component. Structural validation is not a substitute for that byte check.
/// This supplies source geometry only: the match host must evaluate creation
/// gates, terminal event order, damage, reactions and the helmet's target clock.
public struct DuelSerpentAbilityModels: Equatable, Sendable {
    public static let documentName = "d13-ability-models-private.json"
    public static let documentSHA256 = "61a1a5731b97ac6437161c07d6dc6a692c30a4f84e391ac78a2afc8ea1bb1f58"
    public static let maximumDocumentBytes = 2_100_000
    public enum Kind: String, CaseIterable, Sendable { case helmet, bloom, push, vine1, vine2 }
    public enum Failure: Error { case identity, model, geometry, interval }

    public struct Birth: Equatable, Sendable {
        public let kind: Kind
        public let origin: DuelWeaponPoint
        public let direction: Int
    }
    public struct Capsule: Equatable, Sendable {
        public let id: String
        public let base, tip: DuelWeaponPoint
        public let radiusMeters: Double
    }
    public struct Snapshot: Equatable, Sendable {
        public let kind: Kind
        public let motionTick: Int
        /// This is the source interval, not an accepted gameplay contact. The
        /// host still owns deletion/commit ordering at AnimationEnd.
        public let insideSourceAttackInterval: Bool
        public let capsules: [Capsule]
        public let sourceBaseDamage: Double
        public let sourceHitTags: [String]
    }
    private struct Definition {
        let kind: Kind
        let clip, alias, model, motionSHA, bonesSHA, bundle: String
        let frames, record, radius, firstAttack, lastAttack: Int
        let parts: [String]
        let damage: Double
        let hitTag: String
        var role: String { "serpentSummon_" + kind.rawValue }
        var lastTick: Int { 2 * (frames - 1) }
        var axes: [String] { kind == .bloom || kind == .push ? ["X", "Y"] : ["X"] }
        var shift: DuelWeaponPoint? {
            switch kind {
            case .helmet: return .init(x: 160)
            case .vine1: return .init(x: -250)
            case .vine2: return .init(x: -175)
            case .bloom, .push: return nil
            }
        }
    }
    private static let commonBones = "27902c22151fa33d2bc45b163bb9d4ca106f4c934a36013eb31bb37a35dbfbd7"
    private static let vineBones = "87c594e1b25894402ceeac65932fe5656612638991796c4fb807edb734a5235d"
    private static let vineParts = (18...20).map { "Magic_Islander_Root_Attacking_Edge_Tentacle_\($0)" }
    private static let definitions: [Definition] = [
        .init(kind: .helmet, clip: "d13_helmet_ability_model", alias: "D13_Helmet_Ability_Model_Attack",
              model: "mgc__common_model_40", motionSHA: "5f4f9652eaa7d78dc6fac1a834342f31b0ef345e52d66aaf8a94454d1f4110b0",
              bonesSHA: commonBones, bundle: "9893dca6e10355eb9c3c79d1613f08b1.bin", frames: 22, record: 57,
              radius: 1500, firstAttack: 0, lastAttack: 42, parts: ["Common_Model_40_Attacking_Edge_HorBig"],
              damage: 0.15000000596046448, hitTag: "Hit_D13_Helmet_Ability"),
        .init(kind: .bloom, clip: "common_model_40_attack", alias: "D13_Bloom_Enemy_Damage",
              model: "mgc__common_model_40", motionSHA: "3f5c4da828c1524d434b96c5c7ae38e78d5c55eb3562e0c45dcc88e262c7ab3f",
              bonesSHA: commonBones, bundle: "0b06a71d4dd1251a90ad5707a5bad348.bin", frames: 6, record: 62,
              radius: 400, firstAttack: 0, lastAttack: 10, parts: ["Common_Model_40_Attacking_Edge"],
              damage: 1, hitTag: "Hit_D13_Bloom"),
        .init(kind: .push, clip: "leader_ability_model_push", alias: "D13_Armor_Ability_Attack_Model_Push",
              model: "mgc__islander_push", motionSHA: "ea47ff3b54ad28032bfc5df5cdb0bff9b95286f6e946c56bdf7005ad48e2a55a",
              bonesSHA: "ca417cf469125ab93824398d3798dc62ed3d4c8c80d248935749bfdf1ffba509",
              bundle: "0421e258fbf1aaf8064d36e40fc16c29.bin", frames: 11, record: 64,
              radius: 750, firstAttack: 0, lastAttack: 20, parts: ["Magic_Islander_Model_Push_Attacking_Edge"],
              damage: 0.20000000298023224, hitTag: "H_Chest_Short_Slow_51"),
        .init(kind: .vine1, clip: "leader_root_creep_1", alias: "D13_Withering_Vine_1",
              model: "mgc__islander_root", motionSHA: "7b95f6fe82f00bfa6cb51fd16c73d8d23c6055c27fe493a88b2a1c2762194cc9",
              bonesSHA: vineBones, bundle: "0421e258fbf1aaf8064d36e40fc16c29.bin", frames: 88, record: 65,
              radius: 70, firstAttack: 8, lastAttack: 149, parts: vineParts,
              damage: 0.12999999523162842, hitTag: "Hit_D13_Attack_Model_Root_1"),
        .init(kind: .vine2, clip: "leader_root_creep_2", alias: "D13_Withering_Vine_2",
              model: "mgc__islander_root", motionSHA: "4a68eac23f2764a3e4863bf06b6a29f46943ea7910c9d0786c24ce2c31c78b10",
              bonesSHA: vineBones, bundle: "0421e258fbf1aaf8064d36e40fc16c29.bin", frames: 92, record: 66,
              radius: 70, firstAttack: 8, lastAttack: 149, parts: vineParts,
              damage: 0.12999999523162842, hitTag: "Hit_D13_Attack_Model_Root_2")
    ]
    private struct Document: Decodable {
        let schema, sourceArchiveSHA256, sourceDecodedArchiveSHA256, sourceConfigurationSHA256: String
        let sourceOnly, runtimeBound: Bool
        let summonTracks: [DuelSummonMotionTrack]
        let models: [Model]
        let vineGeometry: Geometry
    }
    private struct Geometry: Decodable {
        let file, sha256: String
        let bytes: Int
    }
    private struct Model: Decodable, Equatable, Sendable {
        struct Interval: Decodable, Equatable, Sendable {
            struct Effective: Decodable, Equatable, Sendable { let startTick, endTick: Int }
            struct Original: Decodable, Equatable, Sendable {
                struct Damage: Decodable, Equatable, Sendable {
                    let baseDamage: Double
                    let attack: String
                    enum CodingKeys: String, CodingKey { case baseDamage = "BaseDamage", attack = "Attack" }
                }
                let attackingParts, hitTags: [String]
                let damage: Damage
                enum CodingKeys: String, CodingKey {
                    case attackingParts = "AttackingParts", hitTags = "HitTags", damage = "Damage"
                }
            }
            let index: Int
            let effective: Effective
            let original: Original
        }
        struct Origin: Decodable, Equatable, Sendable {
            let alignmentBone, canonicalSourceRightRotation: String
            let modelScale: Double
            let selectedAlignAxes: [String]
            let initialAlignedRootMeters: DuelWeaponPoint
            let sourceShiftCentimeters: DuelWeaponPoint?
        }
        let role, sourceAnimation, sourceModel, sourceConfigurationSHA256: String
        let sourceRecordIndex, sourceEndEventTick, sourceDeleteEventTick, effectiveLastTick: Int
        let sourceAttackIntervals: [Interval]
        let origin: Origin
    }
    private let tracks: [DuelSummonMotionTrack]
    private let models: [Model]

    public init(document data: Data) throws {
        guard data.count <= Self.maximumDocumentBytes else { throw Failure.identity }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schema == "original-d13-independent-ability-models-v1",
              document.sourceOnly, !document.runtimeBound,
              document.sourceArchiveSHA256 == "f9a24c6f81c46b12facd670adff92d24f829a7811c298473ee51867262338959",
              document.sourceDecodedArchiveSHA256 == "02bcd31d5b0f3ed992ca1972f2c6da5f59e6495fe3880fec45f8b073fbaa0e7a",
              document.sourceConfigurationSHA256 == DuelSerpentActionBinding.settingsSHA256,
              document.vineGeometry.file == "Serpent_D13_Withering_Vines.glb",
              document.vineGeometry.bytes == 567_544,
              document.vineGeometry.sha256 == "2501b691696bdc22f358508ea298999acc3150436d83bc19c2dd42de29092121",
              document.summonTracks.count == 5, document.models.count == 5 else { throw Failure.identity }
        for (index, expected) in Self.definitions.enumerated() {
            let track = document.summonTracks[index], model = document.models[index]
            try track.validate()
            guard track.role == expected.role, track.clip == expected.clip,
                  track.frames == expected.frames, track.sourceSHA256 == expected.motionSHA,
                  track.sourceBundle == expected.bundle, track.boneConfigurationSHA256 == expected.bonesSHA,
                  track.sourceEndEventTick == expected.lastTick, track.sourceDeleteEventTick == nil,
                  track.groundLift.allSatisfy({ $0 == 0 }), track.hurtCapsules == [],
                  track.attackParts == ["primary": expected.parts],
                  track.collisionEdges?.map(\.id) == expected.parts,
                  track.collisionEdges?.allSatisfy({ $0.side == "right" && $0.radiusMillimeters == expected.radius }) == true
            else { throw Failure.geometry }
            guard model.role == expected.role, model.sourceAnimation == expected.alias,
                  model.sourceModel == expected.model, model.sourceRecordIndex == expected.record,
                  model.sourceConfigurationSHA256 == document.sourceConfigurationSHA256,
                  model.sourceEndEventTick == expected.lastTick, model.sourceDeleteEventTick == expected.lastTick,
                  model.effectiveLastTick == expected.lastTick,
                  model.origin.modelScale == 1, model.origin.canonicalSourceRightRotation == "Ry(pi)",
                  model.origin.selectedAlignAxes == expected.axes,
                  model.origin.sourceShiftCentimeters == expected.shift,
                  model.origin.alignmentBone == (expected.kind == .vine1 || expected.kind == .vine2 ? "tentacle_1" : "magic_joint_root"),
                  let root = track.root.first,
                  abs(root.x - model.origin.initialAlignedRootMeters.x) < 1e-8,
                  abs(root.y - model.origin.initialAlignedRootMeters.y) < 1e-8,
                  abs(root.z - model.origin.initialAlignedRootMeters.z) < 1e-8
            else { throw Failure.model }
            guard model.sourceAttackIntervals.count == 1, let interval = model.sourceAttackIntervals.first,
                  interval.index == 0, interval.effective.startTick == expected.firstAttack,
                  interval.effective.endTick == expected.lastAttack,
                  interval.original.attackingParts == expected.parts,
                  interval.original.damage.baseDamage == expected.damage, interval.original.damage.attack == "MagicPower",
                  interval.original.hitTags.contains(expected.hitTag), interval.original.hitTags.contains("Unblockable")
            else { throw Failure.interval }
        }
        tracks = document.summonTracks; models = document.models
    }

    /// `direction` is the result of the source SetDirection evaluation. Only
    /// Bloom has a fixed DirectionLeft. Positions are captured at model birth;
    /// later owner movement must not be silently reapplied to an old model.
    public func birth(kind: Kind, ownerPelvis: DuelWeaponPoint, targetPelvis: DuelWeaponPoint,
                      direction: Int) -> Birth? {
        guard [-1, 1].contains(direction),
              [ownerPelvis, targetPelvis].allSatisfy({ point in
                  [point.x, point.y, point.z].allSatisfy({ $0.isFinite && abs($0) <= 100_000 })
              }) else { return nil }
        let index = Self.definitions.firstIndex { $0.kind == kind }!, d = Self.definitions[index]
        let facing = kind == .bloom ? -1 : direction
        let origin: DuelWeaponPoint
        if kind == .bloom || kind == .push {
            // Source Align selects X/Y only. Target Z is not an alignment axis.
            origin = .init(x: targetPelvis.x, y: targetPelvis.y)
        } else {
            origin = .init(x: ownerPelvis.x + (d.shift?.x ?? 0) / 100 * Double(facing))
        }
        return Birth(kind: kind, origin: origin, direction: facing)
    }

    public func sourceSnapshot(birth: Birth, motionTick: Int) -> Snapshot? {
        let index = Self.definitions.firstIndex { $0.kind == birth.kind }!, d = Self.definitions[index]
        guard (0...d.lastTick).contains(motionTick) else { return nil }
        let track = tracks[index], interval = models[index].sourceAttackIntervals[0]
        let rootX = birth.origin.x + (track.root[motionTick].x - track.root[0].x) * Double(birth.direction)
        func world(_ point: DuelWeaponPoint) -> DuelWeaponPoint {
            .init(x: rootX + point.x * Double(birth.direction), y: birth.origin.y + point.y,
                  z: point.z * Double(birth.direction))
        }
        let capsules = (track.collisionEdges ?? []).map { edge in
            Capsule(id: edge.id, base: world(edge.base[motionTick]), tip: world(edge.tip[motionTick]),
                    radiusMeters: Double(edge.radiusMillimeters) / 1000)
        }
        return Snapshot(kind: birth.kind, motionTick: motionTick,
            insideSourceAttackInterval: (d.firstAttack...d.lastAttack).contains(motionTick), capsules: capsules,
            sourceBaseDamage: interval.original.damage.baseDamage, sourceHitTags: interval.original.hitTags)
    }
}
