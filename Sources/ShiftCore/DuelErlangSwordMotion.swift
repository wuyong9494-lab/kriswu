import Foundation

/// Original lock1449 model variables and a105 Move state. Coordinates exposed
/// by the arena are metres; source Move speed remains Float centimetres per
/// logical tick. The normal source scale is one (not wall-clock seconds).
public struct DuelErlangSwordMotion: Equatable, Sendable {
    public static let sourceContract = "D15-1449-39321-39178-loop93-v1"
    public static let idleRole = "erlangSummon_swordIdle"
    public static let rotateRole = "erlangSummon_swordRotate"
    public static let attackRole = "erlangSummon_sword"
    public static let checkTicks = [8, 18, 28, 34, 40, 48, 58, 68, 78, 88]
    public static func matches(profile: DuelWeaponProfile) -> Bool {
        let roles = (1...6).map { "erlangSummon_swordBirth\($0)" } + [idleRole, attackRole]
        return roles.allSatisfy { role in
            guard let track = profile.summonTrack(role: role) else { return false }
            return track.sourceSHA256 == "0705dac47e95dee7d66f39c8a2ede4e4774762aa241f79c08e64129119f36632" &&
                track.sourceBundle == "2a784bc550bc06541a38a4c1c53b69f3.bin" &&
                track.boneConfigurationSHA256 == "1c95bf3e07766302cf8eccdf207cb4b7bb02d89bd39fd702540f62c9ce5be0e4" &&
                track.frames == 51 && track.root.count == 101 && track.sourceEndEventTick == 92 &&
                track.sourceDeleteEventTick == (role == attackRole ? 70 : nil)
        }
    }
    public let headDistance: Double
    public let birthY: Double
    public var moveCentimetersPerTick: Float = 0
    public var hidden = false

    public init(headDistance: Double, birthY: Double) {
        self.headDistance = headDistance; self.birthY = birthY
    }
    public static func isHeldRole(_ role: String) -> Bool {
        role == idleRole || role == rotateRole || (1...6).contains { role == "erlangSummon_swordBirth\($0)" }
    }
    mutating func check(rootX: Double, ownerHeadX: Double, ownerDirection: Int) {
        let desired = Float((ownerHeadX - headDistance * Double(ownerDirection)) * 100)
        let root = Float(rootX * 100), error = desired - root
        if abs(error) <= 30 { moveCentimetersPerTick = 0; return }
        let speed = max(Float(1), min(Float(5), abs(error) * 0.05))
        moveCentimetersPerTick = error > 0 ? speed : -speed
        // The action stores MaxSpeed=4 and Acceleration=∓.03, but Frames=null
        // leaves this new component's zero timer untouched. Native39442 skips
        // both acceleration and clamping when that timer is exactly zero.
    }
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.string(Self.sourceContract)
        try writer.double(headDistance); try writer.double(birthY)
        try writer.double(Double(moveCentimetersPerTick)); try writer.bool(hidden)
    }
}

extension DuelErlangSpatialState {
    struct SwordOwnerPose {
        let head: DuelWeaponPoint
        let pelvis: DuelWeaponPoint
        let direction: Int
    }

    /// Source model creation consumes the exact slot emitted by the owner's
    /// SET_D15_SWORD_COUNT event. It does not infer births from a draw snapshot.
    mutating func spawnSword(owner: Int, slot: DuelErlangCombatRules.SwordSlot,
                             pose: SwordOwnerPose, hidden: Bool) {
        let point = DuelWeaponPoint(x: pose.pelvis.x + slot.offset.x * Double(pose.direction),
                                    y: slot.offset.y, z: pose.pelvis.z + slot.offset.z)
        guard let id = spawn(owner: owner, ability: .swords, role: slot.birthRole,
                             direction: pose.direction, origin: point, swordSlot: slot.slot),
              let i = models.firstIndex(where: { $0.id == id }) else { return }
        var motion = DuelErlangSwordMotion(headDistance: abs(pose.head.x - point.x), birthY: point.y)
        motion.hidden = hidden; models[i].swordMotion = motion
    }

    /// Move, source animation events and contact geometry share the same model
    /// origin and tick. Birth/Rotate/Idle/Attack retain id and bornAt. A state
    /// transition resets only its animation clock and interval contact latch.
    mutating func updateSwords(owner: Int, pose: SwordOwnerPose, attack: Bool,
                               hidden: Bool) -> Bool {
        var sourceDelete = false
        for i in models.indices where models[i].owner == owner && models[i].swordMotion != nil {
            var model = models[i], motion = model.swordMotion!
            var age = model.motionTick(at: liveTick)
            if attack {
                model.role = DuelErlangSwordMotion.attackRole
                model.stateStartedAt = liveTick; model.direction = pose.direction
                model.acceptedAttackIDs.removeAll(keepingCapacity: true); age = 0
            } else if model.role == DuelErlangSwordMotion.rotateRole && age > 0 ||
                        model.role.hasPrefix("erlangSummon_swordBirth") && age >= 92 ||
                        model.role == DuelErlangSwordMotion.idleRole && age > 92 {
                // Non-looped Birth emits AnimationEnd at 92. Looped Idle
                // only sets its loop flag there, then resets on the next step.
                // The true zero-tick Rotate pose is committed once before the
                // arena processes its End, as for the one-frame human return.
                model.role = DuelErlangSwordMotion.idleRole
                model.stateStartedAt = liveTick; model.direction = pose.direction
                model.acceptedAttackIDs.removeAll(keepingCapacity: true); age = 0
            }
            if DuelErlangSwordMotion.isHeldRole(model.role),
               DuelErlangSwordMotion.checkTicks.contains(age) {
                motion.check(rootX: model.origin.x, ownerHeadX: pose.head.x, ownerDirection: pose.direction)
                if model.direction != pose.direction {
                    model.role = DuelErlangSwordMotion.rotateRole
                    model.direction = pose.direction; model.stateStartedAt = liveTick
                    model.origin.y = motion.birthY; age = 0
                    model.acceptedAttackIDs.removeAll(keepingCapacity: true)
                }
            }
            // A new model retains its initial tick-zero position. The native
            // Move delta is (base + override) × source step scale. Attack's
            // original Velocity=[36,-10,null,null] is independent of FK root.
            if model.bornAt < liveTick {
                let attacking = model.role == DuelErlangSwordMotion.attackRole
                let x = motion.moveCentimetersPerTick + (attacking ? 36 * Float(model.direction) : 0)
                model.origin.x += Double(x) / 100
                if attacking { model.origin.y -= 0.1 }
            }
            motion.hidden = hidden; model.swordMotion = motion
            models[i] = model
            if model.role == DuelErlangSwordMotion.attackRole && age > 70 { sourceDelete = true }
        }
        // Retain the source terminal sample before the normal arena cleanup,
        // matching the existing source model end-event presentation contract.
        models.removeAll { $0.owner == owner && $0.swordMotion != nil &&
            $0.role == DuelErlangSwordMotion.attackRole && $0.motionTick(at: liveTick) > 70 }
        return sourceDelete
    }
}
