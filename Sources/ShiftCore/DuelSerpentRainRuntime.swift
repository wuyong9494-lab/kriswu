import Foundation

/// Half-frame FK from the authenticated original bottle, in source centimetres.
/// The resource loader must authenticate the JSON bytes as well as the model.
/// This structural gate does not replace byte authentication.
public struct DuelSerpentBottleMotion: Equatable, Codable, Sendable {
    public struct Sample: Equatable, Codable, Sendable {
        public let root, left, right: DuelWeaponPoint
    }
    public let schema, modelSHA256, motionSHA256, animation, coordinates: String
    public let modelBytes, endTick: Int
    public let samples: [Sample]
    public enum Failure: Error { case identity, samples }
    public func validate() throws {
        guard schema == "d13-bottle-motion-binding-v1",
              modelSHA256 == "5ccf41b00f10b3e504012a33e8f6212c7935a2ff4ac65b831eedfab2d91626cd",
              motionSHA256 == "62d469b0b69db2393d1468d454b734e97b17c1ed19672adde8e94ce1696145a4",
              animation == "D13_Bottle_Throw_Model", modelBytes == 291_180, endTick == 48,
              coordinates == "source-centimeters-z-converted" else { throw Failure.identity }
        guard samples.count == 49, samples.allSatisfy({ sample in
            [sample.root, sample.left, sample.right].allSatisfy { point in
                [point.x, point.y, point.z].allSatisfy { $0.isFinite && abs($0) <= 100_000 }
            }
        }) else { throw Failure.samples }
    }
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        for value in [schema, modelSHA256, motionSHA256, animation, coordinates] { try writer.string(value) }
        try writer.int(modelBytes); try writer.int(endTick)
        try writer.array(samples, limit: 49) { w, s in
            for p in [s.root, s.left, s.right] { try w.double(p.x); try w.double(p.y); try w.double(p.z) }
        }
    }
}

/// Connects accepted body actions to an actual bottle entity and the original
/// ordinary level-six cloud/ground trigger path. Coordinates are centimetres,
/// damages are source ModHP magnitudes, and ticks are authoritative live ticks.
/// No hit point conversion or damage-on-bottle collision is invented.
///
/// The recovered original ranged bundle supplies the cloud loop even though
/// the earlier motion export catalog omitted it. A bound cloud uses that FK;
/// an unbound host still must provide an actual magic_joint_root sample.
/// Missing/stale samples fail atomically.
/// DuelWeaponFight can bind this ordinary path with DuelSerpentCombatBinding;
/// enhanced abilities and production asset registration remain separate.
public struct DuelSerpentRainRuntime: Equatable, Sendable {
    public typealias Channel = DuelSerpentState.Channel
    public struct Scene: Equatable, Sendable {
        public let ownerPelvisX, ownerCOMX, targetCOMX: Double
        /// Resolved original SetDirection result, supplied by the source host.
        public let direction: Int
        /// Source Repulsion ByModel=Parent translation for this tick; zero
        /// only when the source host reports no parent repulsion.
        public let bottleRepulsionX: Double
        public init(ownerPelvisX: Double, ownerCOMX: Double, targetCOMX: Double,
                    direction: Int, bottleRepulsionX: Double = 0) {
            self.ownerPelvisX = ownerPelvisX; self.ownerCOMX = ownerCOMX; self.targetCOMX = targetCOMX
            self.direction = direction; self.bottleRepulsionX = bottleRepulsionX
        }
        var valid: Bool {
            [-1, 1].contains(direction) && [ownerPelvisX, ownerCOMX, targetCOMX, bottleRepulsionX].allSatisfy {
                $0.isFinite && abs($0) <= 10_000_000
            }
        }
    }
    public struct Bottle: Equatable, Sendable {
        public let id: UInt64
        public let bornAt, direction: Int
        public fileprivate(set) var motionTick: Int
        public fileprivate(set) var originX: Double
    }
    public struct CloudRequest: Equatable, Sendable {
        public let id: UInt64
        public let requestedAt, direction: Int
        /// The source aligns X to the owner's current pelvis + 200 in facing
        /// direction, not to the launch position or bottle's final gun joint.
        public let alignedRootX: Double
        public var model: String { "shd__shadow_ranged_agile_cloud" }
        public var animation: String { "D13_Poison_Bomb_Cloud_Model_Attack" }
    }
    public struct CloudFrame: Equatable, Sendable {
        public let id: UInt64
        public let liveTick: Int
        public let rootX: Double
        public init(id: UInt64, liveTick: Int, rootX: Double) {
            self.id = id; self.liveTick = liveTick; self.rootX = rootX
        }
        var valid: Bool { rootX.isFinite && abs(rootX) <= 10_000_000 }
    }
    public struct Cloud: Equatable, Sendable {
        public let id: UInt64
        public let bornAt: Int
        public let alignedRootX: Double
        public let direction: Int
        public fileprivate(set) var rootX: Double
        public fileprivate(set) var poisonChoice: Int
    }
    public struct GroundPoison: Equatable, Sendable {
        public fileprivate(set) var stacks = 0
        public fileprivate(set) var remainingTicks = 0
        public func damagePerTick(amplifier: Double) -> Double {
            remainingTicks > 0 ? 0.02 * Double(stacks) / 1200 * amplifier : 0
        }
    }
    public enum Model: String, Sendable { case bottle, cloud }
    public enum Effect: Equatable, Sendable {
        case bottleBorn(UInt64), cloudRequested(CloudRequest), cloudBorn(UInt64)
        case modelDeleted(Model, UInt64)
        case rainStarted, rainEnded, groundStarted, groundEnded
        case cloudPoison(Channel, applied: Bool), groundPoison(stacks: Int)
        case soundStarted(String), soundStopped(String)
    }
    public struct Step: Equatable, Sendable {
        /// Newly created statuses start accumulating on the next accepted
        /// update and emit after the default ten-tick interval (or expiry).
        /// The host still owns immunity, source modifiers and health conversion.
        public let statusDamage: Double
        public let statusDamagePulses: [Double]
        public let actionEvents: [DuelSerpentActionRuntime.Event]
        public let modelEvents: [Effect]
    }
    public static let rainSound = "set_d13/poison_rain_sequence-02@Battle@Movement"
    public static let rainOutSound = "set_d13/poison_rain_out@Battle@Movement"
    public private(set) var actions: DuelSerpentActionRuntime
    public let bottleMotion: DuelSerpentBottleMotion
    public let cloudMotion: DuelSerpentCloudMotion?
    public private(set) var bottle: Bottle?
    public private(set) var pendingCloud: CloudRequest?
    public private(set) var cloud: Cloud?
    public private(set) var groundPoison = GroundPoison()
    public private(set) var withering = DuelSerpentWitheringState()
    private var groundStatus = DuelSerpentStatusPulse()
    public var liveTick: Int { actions.liveTick }

    public init(binding: DuelSerpentActionBinding, bottleMotion: DuelSerpentBottleMotion,
                level: Int, raidDamageAmplifier: Double, rangedUsagesLeft: Int,
                cloudMotion: DuelSerpentCloudMotion? = nil) throws {
        try bottleMotion.validate(); self.bottleMotion = bottleMotion
        try cloudMotion?.validate(); self.cloudMotion = cloudMotion
        actions = try .init(binding: binding, level: level, raidDamageAmplifier: raidDamageAmplifier,
                            rangedUsagesLeft: rangedUsagesLeft)
    }
    public mutating func beginRound() {
        actions.beginRound()
        withering.observeBloom(actions.state.bloom, level: actions.state.level)
    }
    mutating func clearTargetStatusesForArenaRound() {
        actions.clearTargetPoisonForArenaRound()
        groundPoison = GroundPoison()
        groundStatus = DuelSerpentStatusPulse()
        withering.clearTarget()
    }
    /// Source cross-round variable/usage resets are separate events. Round end
    /// clears statuses and every spawned/pending entity (common source lock 923).
    @discardableResult
    public mutating func endRound() -> [Effect] {
        var effects: [Effect] = []
        if let bottle { effects.append(.modelDeleted(.bottle, bottle.id)) }
        if let cloud { effects += cloudCleanup(cloud) }
        bottle = nil; pendingCloud = nil; cloud = nil; actions.endRound()
        groundStatus = DuelSerpentStatusPulse()
        return effects
    }
    public mutating func acceptedAnimationStart(alias: String, playbackID: UInt64) -> [DuelSerpentActionRuntime.Event]? {
        actions.acceptedAnimationStart(alias: alias, playbackID: playbackID)
    }
    @discardableResult
    public mutating func interrupt(playbackID: UInt64) -> Bool {
        // An already released entity has its own lifetime, independent of the
        // interrupted body's animation. Unreleased markers are cancelled below.
        actions.interrupt(playbackID: playbackID)
    }
    @discardableResult
    public mutating func outgoingContact(channel: Channel, sourceDamage: Double,
        event: DuelSerpentState.ContactEvent = .postHit, first: Bool = true, invisible: Bool = false,
        hitTag: String? = nil, perks: DuelSerpentState.Perks = .init()) -> Bool {
        let accepted = actions.outgoingContact(channel: channel, sourceDamage: sourceDamage, event: event,
            first: first, invisible: invisible, hitTag: hitTag, perks: perks)
        if accepted { withering.observeBloom(actions.state.bloom, level: actions.state.level) }
        return accepted
    }
    @discardableResult
    public mutating func incomingContact(sourceDamage: Double,
        event: DuelSerpentState.ContactEvent = .postHit, first: Bool = true, invisible: Bool = false) -> Bool {
        let accepted = actions.incomingContact(sourceDamage: sourceDamage, event: event,
            first: first, invisible: invisible)
        if accepted { withering.observeBloom(actions.state.bloom, level: actions.state.level) }
        return accepted
    }
    @discardableResult
    public mutating func prepareIncomingContact(blocked: Bool) -> Double {
        actions.prepareIncomingContact(blocked: blocked)
    }
    /// Source-model host acknowledgement, at the requested tick, after loading
    /// the actual original cloud animation. randomChoice is the original f14
    /// result in 1...4. It is neither a render RNG nor an inferred hit channel.
    @discardableResult
    public mutating func acceptedCloudBirth(frame: CloudFrame, animation: String, randomChoice: Int) -> [Effect]? {
        guard actions.state.roundActive, let request = pendingCloud, cloud == nil,
              frame.id == request.id, frame.liveTick == liveTick, request.requestedAt == liveTick,
              frame.valid, frame.rootX == request.alignedRootX,
              animation == request.animation, (1...4).contains(randomChoice) else { return nil }
        if let cloudMotion {
            guard cloudMotion.frame(id: request.id, bornAt: request.requestedAt,
                alignedRootX: request.alignedRootX, direction: request.direction, liveTick: liveTick) == frame
            else { return nil }
        }
        cloud = .init(id: frame.id, bornAt: liveTick, alignedRootX: request.alignedRootX,
                      direction: request.direction, rootX: frame.rootX, poisonChoice: randomChoice)
        pendingCloud = nil
        return [.cloudBorn(frame.id), .rainStarted, .soundStarted(Self.rainSound)]
    }
    /// Resource-authenticated host path. Birth still requires the original f14
    /// result and happens exactly at the bottle's AnimationEnd request tick.
    @discardableResult
    public mutating func acceptedCloudBirth(randomChoice: Int) -> [Effect]? {
        guard let request = pendingCloud, let motion = cloudMotion,
              let frame = motion.frame(id: request.id, bornAt: request.requestedAt,
                alignedRootX: request.alignedRootX, direction: request.direction, liveTick: liveTick)
        else { return nil }
        return acceptedCloudBirth(frame: frame, animation: motion.animation, randomChoice: randomChoice)
    }
    public func sourceCloudFrame(at nextTick: Int) -> CloudFrame? {
        guard let cloud, let cloudMotion else { return nil }
        return cloudMotion.frame(id: cloud.id, bornAt: cloud.bornAt, alignedRootX: cloud.alignedRootX,
                                 direction: cloud.direction, liveTick: nextTick)
    }
    /// The native cloud rerolls after evaluating the current poison channel,
    /// including misses and invincible targets. Supply a new f14 value exactly
    /// at these ticks. Random state remains owned/encoded by the source host.
    public func requiresPoisonChoice(at nextTick: Int) -> Bool {
        guard let cloud, nextTick >= cloud.bornAt else { return false }
        let age = nextTick - cloud.bornAt
        return age > 0 && age < 600 && age % 20 == 0
    }
    public func bottleSample() -> DuelSerpentBottleMotion.Sample? {
        guard let bottle else { return nil }
        return bottleMotion.samples[bottle.motionTick]
    }
    public func bottleWorldPoint(_ local: DuelWeaponPoint) -> DuelWeaponPoint? {
        guard let bottle else { return nil }
        return .init(x: bottle.originX + local.x * Double(bottle.direction), y: local.y,
                     z: local.z * Double(bottle.direction))
    }
    public mutating func step(liveTick nextTick: Int, scene: Scene, targetInvincible: Bool,
                              cloudFrame: CloudFrame? = nil, nextPoisonChoice: Int? = nil) -> Step? {
        guard actions.state.roundActive, liveTick < Int.max, nextTick == liveTick + 1,
              scene.valid, pendingCloud == nil else { return nil }
        let resolvedCloudFrame = cloudFrame ?? sourceCloudFrame(at: nextTick)
        if cloudMotion != nil, let cloudFrame, cloudFrame != sourceCloudFrame(at: nextTick) { return nil }
        if let cloud {
            guard let cloudFrame = resolvedCloudFrame, cloudFrame.id == cloud.id, cloudFrame.liveTick == nextTick,
                  cloudFrame.valid else { return nil }
        } else if cloudFrame != nil { return nil }
        if requiresPoisonChoice(at: nextTick) {
            guard let nextPoisonChoice, (1...4).contains(nextPoisonChoice) else { return nil }
        } else if nextPoisonChoice != nil { return nil }
        // All validation above is atomic: invalid/missing inputs cannot spend
        // time, damage, an action marker, a usage or a source random selection.
        let actionStep = actions.step(liveTick: nextTick, targetInvincible: targetInvincible)!
        withering.advance(liveTick: nextTick, ownerCOMX: scene.ownerCOMX, targetCOMX: scene.targetCOMX)
        var effects: [Effect] = []
        let groundPulse = groundStatus.advance(now: Float(nextTick))
        let groundDamage = groundPulse.map { max(0, -Double($0)) } ?? 0
        if groundPoison.remainingTicks > 0 {
            groundPoison.remainingTicks -= 1
            if groundPoison.remainingTicks == 0 { groundPoison.stacks = 0 }
        }
        if var active = bottle {
            active.motionTick += 1; active.originX += scene.bottleRepulsionX
            if active.motionTick == bottleMotion.endTick {
                let request = CloudRequest(id: active.id, requestedAt: nextTick, direction: scene.direction,
                    alignedRootX: scene.ownerPelvisX + 200 * Double(scene.direction))
                // Lock 1402 creates the cloud before deleting the bottle.
                pendingCloud = request; bottle = nil
                effects += [.cloudRequested(request), .modelDeleted(.bottle, active.id)]
            } else { bottle = active }
        }
        if var active = cloud, let cloudFrame = resolvedCloudFrame {
            active.rootX = cloudFrame.rootX
            let age = nextTick - active.bornAt
            let inside = scene.targetCOMX >= active.rootX - 300 && scene.targetCOMX <= active.rootX + 300
            if age < 600 && age % 20 == 0 {
                if inside {
                    let channel = Channel.allCases[active.poisonChoice - 1]
                    effects.append(.cloudPoison(channel, applied: actions.cloudPulse(channel, targetInvincible: targetInvincible)))
                }
                active.poisonChoice = nextPoisonChoice!
            }
            if age == 180 { effects.append(.groundStarted) }
            if age >= 180 && age < 1080 && (age - 180) % 60 == 0 && inside {
                // Original ground trigger has no Invincible condition. This
                // grants a status; downstream ModHP defenses still belong to
                // the host. Level-eight damage reduction is NOT enabled here.
                groundPoison.stacks += 1; groundPoison.remainingTicks = 1200
                groundStatus = DuelSerpentStatusPulse(
                    rate: -(Float(0.02) * Float(groundPoison.stacks) / 1200 * Float(actions.state.raidDamageAmplifier)),
                    duration: 1200, createdAt: Float(nextTick))
                effects.append(.groundPoison(stacks: groundPoison.stacks))
            }
            if age == 600 { effects += [.rainEnded, .soundStopped(Self.rainSound), .soundStarted(Self.rainOutSound)] }
            if age == 1080 {
                effects += [.groundEnded, .modelDeleted(.cloud, active.id)]; cloud = nil
            } else { cloud = active }
        }
        for event in actionStep.events {
            if case .equippedRangedModelRequested(let group) = event.effect, group == "D13_POSION_BOMB_MODEL" {
                let direction = scene.direction
                bottle = .init(id: event.playbackID, bornAt: nextTick, direction: direction, motionTick: 0,
                    originX: scene.ownerPelvisX - bottleMotion.samples[0].root.x * Double(direction))
                effects.append(.bottleBorn(event.playbackID))
            }
        }
        return .init(statusDamage: actionStep.poisonDamage + groundDamage,
                     statusDamagePulses: actionStep.poisonDamagePulses + (groundDamage > 0 ? [groundDamage] : []),
                     actionEvents: actionStep.events, modelEvents: effects)
    }
    /// Source DESTROYABLE/explicit cleanup events are scoped to entity identity.
    /// Destroying a bottle never synthesizes its AnimationEnd cloud creation.
    @discardableResult
    public mutating func removeModel(_ model: Model, id: UInt64) -> [Effect]? {
        if model == .bottle, bottle?.id == id {
            bottle = nil; return [.modelDeleted(.bottle, id)]
        }
        if model == .cloud, let cloud, cloud.id == id {
            let effects = cloudCleanup(cloud); self.cloud = nil; return effects
        }
        return nil
    }
    private func cloudCleanup(_ cloud: Cloud) -> [Effect] {
        var result: [Effect] = []
        if liveTick - cloud.bornAt < 600 { result.append(.rainEnded) }
        if liveTick - cloud.bornAt >= 180 { result.append(.groundEnded) }
        return result + [.soundStopped(Self.rainSound), .soundStarted(Self.rainOutSound), .modelDeleted(.cloud, cloud.id)]
    }
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        try writer.string("d13-rain-component-v3")
        try actions.appendReplayState(to: &writer); try bottleMotion.appendReplayState(to: &writer)
        try writer.optional(cloudMotion) { try $1.appendReplayState(to: &$0) }
        try writer.int(groundPoison.stacks); try writer.int(groundPoison.remainingTicks)
        try groundStatus.appendReplayState(to: &writer)
        try withering.appendReplayState(to: &writer)
        try writer.optional(bottle) { w, b in
            try w.u64(b.id); try w.int(b.bornAt); try w.int(b.direction)
            try w.int(b.motionTick); try w.double(b.originX)
        }
        try writer.optional(pendingCloud) { w, c in
            try w.u64(c.id); try w.int(c.requestedAt); try w.int(c.direction); try w.double(c.alignedRootX)
        }
        try writer.optional(cloud) { w, c in
            try w.u64(c.id); try w.int(c.bornAt); try w.double(c.alignedRootX); try w.int(c.direction)
            try w.double(c.rootX); try w.int(c.poisonChoice)
        }
    }
}
