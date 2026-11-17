import Foundation

/// Read-only presentation of the bottle already owned by the D13 match runtime.
/// The existing match binding explicitly converts source centimetres to 9.2
/// arena millimetres. The recovered GLB is in metres, so its complete original
/// rig receives one 0.92 scale; its animated root is not applied a second time.
/// This uses the same ordinary first motion array as DuelSerpentBottleMotion.
/// Native alternate-array/mirrored-mesh selection is a separate source contract.
public enum DuelSerpentBottlePresentation {
    public static let fileName = "SF3_D13_Bottle_Source.glb"
    public static let fileBytes = 291_180
    public static let fileSHA256 = "5ccf41b00f10b3e504012a33e8f6212c7935a2ff4ac65b831eedfab2d91626cd"
    public static let animation = "D13_Bottle_Throw_Model"
    public static let characterSHA256 = "f25b35dec9bf335bbe01ceee557389f47165c3d0b45b54502017fda394a8bd70"
    public static let arenaMetersPerSourceMeter = 0.92

    public struct Frame: Equatable, Sendable {
        public let owner: Int
        public let id: UInt64
        public let liveTick, motionTick, direction: Int
        public let origin: DuelWeaponPoint
        public var animationTime: Double { Double(motionTick) / 60 }
        public var modelScale: Double { DuelSerpentBottlePresentation.arenaMetersPerSourceMeter }

        /// A recovered GLB bone position before facing/arena placement. The
        /// source runtime's birth origin already removes the Align root X.
        public func worldPoint(sourceMeters: DuelWeaponPoint) -> DuelWeaponPoint {
            .init(x: origin.x + sourceMeters.x * modelScale * Double(direction),
                  y: origin.y + sourceMeters.y * modelScale,
                  z: origin.z + sourceMeters.z * modelScale * Double(direction))
        }
    }

    public static func accepts(_ profile: DuelWeaponProfile) -> Bool {
        DuelCharacterIdentity.serpent.matches(hero: profile.hero, profileID: profile.id,
            bodyID: profile.bodyID, weaponID: profile.weaponID) &&
            profile.sha256 == characterSHA256 &&
            profile.serpentBinding?.bottle.modelSHA256 == fileSHA256 &&
            profile.serpentBinding?.bottle.modelBytes == fileBytes
    }

    public static func frame(owner: Int, profile: DuelWeaponProfile,
                             runtime: DuelSerpentRainRuntime) -> Frame? {
        guard (0..<2).contains(owner), accepts(profile), runtime.actions.state.roundActive,
              runtime.bottleMotion == profile.serpentBinding?.bottle,
              let bottle = runtime.bottle, (0..<runtime.bottleMotion.endTick).contains(bottle.motionTick),
              [-1, 1].contains(bottle.direction), bottle.originX.isFinite else { return nil }
        return .init(owner: owner, id: bottle.id, liveTick: runtime.liveTick,
            motionTick: bottle.motionTick, direction: bottle.direction,
            origin: .init(x: bottle.originX * 0.0092))
    }

    public static func frames(in fight: DuelWeaponFight) -> [Frame] {
        guard fight.phase == .fighting else { return [] }
        return fight.profiles.indices.compactMap { owner in
            guard let runtime = fight.serpentRuntime(owner) else { return nil }
            return frame(owner: owner, profile: fight.profiles[owner], runtime: runtime)
        }
    }
}
