import Foundation

/// Authenticated companion root samples shared by simulation and rendering.
/// Positions use the same right-facing meter basis as fighter motion exports.
public struct DuelSummonMotionTrack: Codable, Equatable, Sendable {
    public let role: String
    public let clip: String
    public let frames: Int
    public let sourceSHA256: String
    public let sourceBundle: String
    public let root: [DuelWeaponPoint]
    public let groundLift: [Double]
    public let boneConfigurationSHA256: String?
    public let collisionEdges: [DuelWeaponCollisionEdge]?
    public let hurtCapsules: [DuelWeaponHurtCapsule]?
    /// Source attack parts by stage. An empty mapping means this companion
    /// emits a separate projectile; its body is never used as that projectile.
    public let attackParts: [String: [String]]?

    public init(role: String, clip: String, frames: Int, sourceSHA256: String,
                sourceBundle: String, root: [DuelWeaponPoint], groundLift: [Double],
                boneConfigurationSHA256: String? = nil, collisionEdges: [DuelWeaponCollisionEdge]? = nil,
                hurtCapsules: [DuelWeaponHurtCapsule]? = nil, attackParts: [String: [String]]? = nil) {
        self.role = role; self.clip = clip; self.frames = frames
        self.sourceSHA256 = sourceSHA256; self.sourceBundle = sourceBundle
        self.root = root; self.groundLift = groundLift
        self.boneConfigurationSHA256 = boneConfigurationSHA256
        self.collisionEdges = collisionEdges; self.hurtCapsules = hurtCapsules; self.attackParts = attackParts
    }
    public func offsetX(at tick: Int) -> Int {
        guard let first = root.first else { return 0 }
        let sample = root[min(root.count - 1, max(0, tick))]
        return Int(((sample.x - first.x) * 1000).rounded())
    }
    func capsules(parts: [String], tick: Int, x: Int, y: Int, z: Int, direction: Int) -> [DuelWeaponCapsule] {
        let index = min(root.count - 1, max(0, tick)), facing = Double(direction)
        let lift = groundLift[index], ids = Set(parts)
        func world(_ point: DuelWeaponPoint) -> DuelWeaponPoint {
            .init(x: Double(x) / 1000 + point.x * facing,
                  y: Double(y) / 1000 + lift + point.y, z: Double(z) / 1000 + point.z * facing)
        }
        func capsule(_ base: [DuelWeaponPoint], _ tip: [DuelWeaponPoint], _ radius: Int) -> DuelWeaponCapsule {
            .init(a: world(base[index]), b: world(tip[index]), radius: Double(radius) / 1000)
        }
        return (collisionEdges ?? []).filter { ids.contains($0.id) }.map { capsule($0.base, $0.tip, $0.radiusMillimeters) } +
            (hurtCapsules ?? []).filter { ids.contains($0.id) }.map { capsule($0.base, $0.tip, $0.radiusMillimeters) }
    }
    func validate() throws {
        guard !role.isEmpty, role.utf8.count <= 128, !clip.isEmpty, clip.utf8.count <= 128,
              (2...4096).contains(frames), DuelFighterAssetRelease.validDigest(sourceSHA256),
              !sourceBundle.isEmpty, sourceBundle.utf8.count <= 512,
              root.count == 2 * (frames - 1) + 1, groundLift.count == root.count,
              root.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite &&
                  abs($0.x) < 100 && abs($0.y) < 100 && abs($0.z) < 100 }),
              groundLift.allSatisfy({ $0.isFinite && abs($0) < 10 }) else {
            throw DuelWeaponCatalog.ValidationError.invalidTracks
        }
        if collisionEdges != nil || hurtCapsules != nil || attackParts != nil {
            let edges = collisionEdges ?? [], hurts = hurtCapsules ?? [], parts = attackParts ?? [:]
            let ids = edges.map(\.id) + hurts.map(\.id)
            func points(_ values: [DuelWeaponPoint]) -> Bool {
                values.count == root.count && values.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite &&
                    abs($0.x) < 100 && abs($0.y) < 100 && abs($0.z) < 100 }
            }
            guard boneConfigurationSHA256.map(DuelFighterAssetRelease.validDigest) == true,
                  ids.count <= 64, Set(ids).count == ids.count,
                  ids.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }),
                  edges.allSatisfy({ ["left", "right"].contains($0.side) && (1...2000).contains($0.radiusMillimeters) && points($0.base) && points($0.tip) }),
                  hurts.allSatisfy({ (1...2000).contains($0.radiusMillimeters) && points($0.base) && points($0.tip) }),
                  parts.count <= 4, parts.allSatisfy({ DuelTriadRules.SummonStage(rawValue: $0.key) != nil &&
                      !$0.value.isEmpty && $0.value.count <= 32 && Set($0.value).count == $0.value.count && Set($0.value).isSubset(of: Set(ids)) }) else {
                throw DuelWeaponCatalog.ValidationError.invalidTracks
            }
        }
    }
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.string(role); try writer.string(clip); try writer.int(frames)
        try writer.string(sourceSHA256); try writer.string(sourceBundle)
        try writer.array(root) { try $0.point($1) }
        try writer.array(groundLift) { try $0.double($1) }
        try writer.optional(boneConfigurationSHA256) { try $0.string($1) }
        try writer.optional(collisionEdges) { writer, edges in
            try writer.array(edges, limit: 32) { writer, edge in
                try writer.string(edge.id); try writer.string(edge.side); try writer.int(edge.radiusMillimeters)
                try writer.array(edge.base) { try $0.point($1) }; try writer.array(edge.tip) { try $0.point($1) }
            }
        }
        try writer.optional(hurtCapsules) { writer, capsules in
            try writer.array(capsules, limit: 32) { writer, capsule in
                try writer.string(capsule.id); try writer.string(capsule.defense.rawValue); try writer.int(capsule.radiusMillimeters)
                try writer.array(capsule.base) { try $0.point($1) }; try writer.array(capsule.tip) { try $0.point($1) }
            }
        }
        try writer.optional(attackParts) { writer, parts in
            try writer.array(parts.keys.sorted(), limit: 4) { writer, key in
                try writer.string(key); try writer.array(parts[key]!, limit: 32) { try $0.string($1) }
            }
        }
    }
}
