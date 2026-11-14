import Foundation

/// Two independently equipped original characters. Source poses and weapon
/// geometry are retained. Damage, hit windows, buffering and the 30 FPS preview
/// clock remain explicit application rules, not recovered SF3 combat code.
public struct DuelWeaponFight: Equatable, Sendable {
    public struct Contact: Equatable, Sendable {
        public enum Kind: String, Sendable { case hit, block }
        public let kind: Kind
        public let attacker: Int
        public let position: DuelWeaponPoint
        public let direction: Int
        public let heavy: Bool
        public let usesWeapon: Bool
        public let authoredAudio: Bool
        public init(kind: Kind, attacker: Int, position: DuelWeaponPoint, direction: Int,
                    heavy: Bool, usesWeapon: Bool, authoredAudio: Bool = false) {
            self.kind = kind; self.attacker = attacker; self.position = position; self.direction = direction
            self.heavy = heavy; self.usesWeapon = usesWeapon; self.authoredAudio = authoredAudio
        }
    }
    public struct Swing: Equatable, Sendable {
        public let attacker: Int
        public let heavy: Bool
        public let usesWeapon: Bool
    }
    private struct Action: Equatable, Sendable {
        let name: String
        let role: String
        let command: DuelWeaponCommand?
        var tick = 0
        // One contact opportunity per entered combo stage. A whiff in an
        // earlier stage must not become an extra hit in a later stage.
        var hits = 0
        var touching = false
        var landedStrikeIDs: [Int] = []
        var touchingStrikeIDs: [Int] = []
        var requiresContactSeparation = false
        var sounded = false
        var reaction = false
        var comboDepth = 0
        var soundAt = Int.max
        var shadowOriginX: Int? = nil
    }
    public let profiles: [DuelWeaponProfile]
    public private(set) var fighters: [DuelGame.Fighter]
    public private(set) var phase: DuelGame.Phase = .fighting
    public private(set) var frame = 0
    public private(set) var remainingTicks = 3600
    public private(set) var wins = [0, 0]
    public private(set) var hitStop = 0
    public private(set) var landedHits = [0, 0]
    public private(set) var damageDealt = [0, 0]
    public private(set) var events: [DuelGame.Event] = []
    public private(set) var contacts: [Contact] = []
    public private(set) var swings: [Swing] = []
    /// Bounded feedback from this simulation step only. This derived queue is
    /// deliberately excluded from canonical gameplay / network replay bytes.
    public private(set) var panguPresentationEvents: [DuelPanguPresentation.Event] = []
    public private(set) var triadPresentationEvents: [DuelTriadPresentation.Event] = []
    public private(set) var sourceMotionSamples: [DuelSourceMotionSample] = []
    private let mode: DuelGame.Mode
    private let difficulty: DuelGame.Difficulty
    private var actions: [Action?] = [nil, nil]
    private var queued: [DuelWeaponCommand?] = [nil, nil]
    private var loopTicks = [0, 0]
    private var loopRoles = ["", ""]
    private var previousX = [3500, 6500]
    private var previousY = [0, 0]
    private var previousHurtY = [0, 0]
    private var previousPoses: [DuelWeaponPose?] = [nil, nil]
    private var previousFacings = [1, -1]
    private var random: UInt64
    private var shadowCooldowns = [0, 0]
    private var impactMotions: [DuelImpactMotion?] = [nil, nil]
    private var panguStates: [DuelPanguState?] = [nil, nil]
    private var panguSpace = DuelPanguSpatialState()
    private var triadStates: [DuelTriadState?] = [nil, nil]
    private var triadSpace = DuelTriadSpatialState()
    public private(set) var roundNumber = 1
    /// Source presentation advances through authored intros and victory poses,
    /// while the combat/ability/spatial clocks remain frozen in those stages.
    public private(set) var sourcePresentationTick = 0
    private var sourceStances: [DuelTriadStanceState?] = [nil, nil]
    private var ordinaryThrowStates: [DuelWeaponThrowState?] = [nil, nil]
    private var ordinaryThrowKnockdownTicks = [0, 0]
    private var sourceThrowStates: [DuelSourceThrowState?] = [nil, nil]
    private var sourceThrowDisabledTicks = [0, 0]

    public init?(fighters: [DuelGame.Fighter], mode: DuelGame.Mode, difficulty: DuelGame.Difficulty,
                 catalog: DuelWeaponCatalog, seed: UInt64) {
        do { try catalog.validate() } catch { return nil }
        guard fighters.count == 2,
              let a = catalog.profile(for: fighters[0].hero), let b = catalog.profile(for: fighters[1].hero),
              a.id != b.id else { return nil }
        self.fighters = fighters; self.mode = mode; self.difficulty = difficulty
        profiles = [a, b]; random = seed; previousX = fighters.map(\.x); previousY = fighters.map(\.y)
        for i in 0..<2 {
            if let rules = profiles[i].panguRules {
                guard let state = DuelPanguState(rules: rules, seed: seed &+ UInt64(i)) else { return nil }
                panguStates[i] = state
                self.fighters[i].health = rules.maximumHealth
                self.fighters[i].energy = state.light * 100 / rules.light.maximum
            }
            if let rules = profiles[i].triadRules {
                guard var state = DuelTriadState(rules: rules, seed: seed &+ UInt64(i)) else { return nil }
                let faction = Self.triadFaction(profiles[1 - i].faction)
                let opponent = profiles[1 - i]
                state.configureOpponent(armor: faction, weapon: faction,
                    maximumHealth: opponent.panguRules?.maximumHealth ?? opponent.triadRules?.maximumHealth ?? 1000)
                if hasSourceStance(i) {
                    sourceStances[i] = .init(round: roundNumber,
                        originXMillimeters: Double(fighters[i].x), direction: fighters[i].facing)
                } else {
                    triadSpace.enqueue(state.beginRound(roundID: roundNumber), owner: i)
                }
                triadStates[i] = state
                self.fighters[i].health = rules.maximumHealth
                self.fighters[i].energy = state.mist * 100 / rules.mist.maximum
            }
        }
        for i in 0..<2 {
            if sourceStances[i] != nil { alignSourceStance(i); sampleSourceStance(i, restart: true) }
            else { setPose(i, role: "idle", tick: 0) }
        }
        previousX = self.fighters.map(\.x)
        previousPoses = self.fighters.map(\.weaponPose); previousFacings = self.fighters.map(\.facing)
        previousHurtY = fighters.indices.map { hurtBox($0).minY }
        consumeTriadEffects()
    }
    public mutating func cancelBufferedInputs() { queued = [nil, nil] }
    public func isAirborne(_ index: Int) -> Bool {
        guard fighters.indices.contains(index) else { return false }
        if fighters[index].y > 0 || fighters[index].velocityY > 0 { return true }
        guard let pose = fighters[index].weaponPose,
              let clip = profiles[index].clip(named: pose.clip) else { return false }
        let t = clip.tracks
        return min(t.sample(t.footL, phase: pose.phase).y,
                   t.sample(t.footR, phase: pose.phase).y) + pose.groundLift > 0.17
    }
    public func supports(_ command: DuelWeaponCommand, index: Int) -> Bool {
        guard profiles.indices.contains(index) else { return false }
        if panguStates[index] != nil && (command == .shadow || command == .ranged) { return true }
        if triadStates[index] != nil && (command == .shadow || command == .ranged) { return true }
        guard profiles[index].clip(command: command) != nil else { return false }
        // The provisional interpreter uses a safe existing body clip and its
        // own explicit dash/projectile timeline, never the raw teleport tracks.
        guard let clip = profiles[index].clip(command: command == .shadow ? .heavy : command) else { return false }
        return profiles[index].resolvedCombatRule(command: command, clipName: clip.name) != nil
    }
    public func canUse(_ command: DuelWeaponCommand, index: Int) -> Bool {
        guard phase == .fighting, !sourceIntroActive,
              supports(command, index: index), !ordinaryThrowOwns(index),
              ordinaryThrowKnockdownTicks[index] == 0 else { return false }
        if let state = panguStates[index], command == .shadow || command == .ranged {
            return state.canUse(command == .ranged ? .spear : .heavenfall)
        }
        if let state = triadStates[index] {
            if command == .shadow || command == .ranged {
                return state.canUse(command == .ranged ? .mistOnslaught : .branches)
            }
            if state.weaponAttacksLocked { return false }
        }
        if command == .shadow { return fighters[index].energy >= 100 && shadowCooldowns[index] == 0 }
        return true
    }
    public func shadowCooldownRemaining(_ index: Int) -> Int {
        shadowCooldowns.indices.contains(index) ? shadowCooldowns[index] : 0
    }
    public func shadowVisual(_ index: Int) -> DuelShadowVisual? {
        guard profiles.indices.contains(index), panguStates[index] == nil, triadStates[index] == nil,
              let action = actions[index], action.command == .shadow,
              action.shadowOriginX != nil else { return nil }
        let katana = profiles[index].isKatana
        let hammer = katana ? nil : shadowHammer(index, action: action, tick: action.tick)
        let attacking = profiles[index].clip(named: action.name).map { active(action, clip: $0, index: index) } ?? false
        return .init(kind: katana ? .katanaDash : .hammerThrow, tick: action.tick,
                     duration: DuelShadowRules.duration(katana: katana),
                     isAttacking: attacking && (katana || hammer != nil),
                     weaponBase: hammer?.base, weaponTip: hammer?.tip)
    }
    public func weaponTrailIsActive(_ index: Int) -> Bool {
        if let shadow = shadowVisual(index) { return shadow.isAttacking || shadow.weaponTip != nil }

        guard let action = actions[index], let command = action.command,
              !command.rawValue.hasPrefix("kick"), let clip = profiles[index].clip(named: action.name) else { return false }
        let speed = motionSpeed(index, clip: clip, command: command, tick: action.tick)
        return active(action, clip: clip, index: index) && speed > 0.009 &&
            DuelWeaponSweepContinuity.accepts(distance: speed)
    }
    public func shadowIsActive(_ index: Int) -> Bool { actions[index]?.command == .shadow }
    public func hurtBox(_ index: Int) -> DuelGame.Box {
        if let capsules = sourceHurtCapsules(index), !capsules.isEmpty {
            let shapes = capsules.map(\.capsule)
            return .init(
                minX: Int(floor(shapes.map { min($0.a.x, $0.b.x) - $0.radius }.min()! * 1000)),
                maxX: Int(ceil(shapes.map { max($0.a.x, $0.b.x) + $0.radius }.max()! * 1000)),
                minY: Int(floor(shapes.map { min($0.a.y, $0.b.y) - $0.radius }.min()! * 1000)),
                maxY: Int(ceil(shapes.map { max($0.a.y, $0.b.y) + $0.radius }.max()! * 1000)))
        }
        let f = fighters[index]
        let lift = sourceVerticalOffset(index) + Double(f.y) / 1000
        let low = Int((max(-0.15, lift) * 1000).rounded())
        let crouched = actions[index] == nil && f.weaponPose?.clip == profiles[index].roles["crouch"]
        return .init(minX: f.x - 270, maxX: f.x + 270,
                     minY: low + 180, maxY: low + (crouched ? 1050 : 1660))
    }
    private func sourceVerticalOffset(_ index: Int) -> Double {
        guard let pose = fighters[index].weaponPose,
              let clip = profiles[index].clip(named: pose.clip) else { return 0 }
        return pose.groundLift + clip.tracks.sample(clip.tracks.root, phase: pose.phase).y
    }
    public func attackBox(_ index: Int) -> DuelGame.Box? {
        guard let action = actions[index], let command = action.command,
              let clip = profiles[index].clip(named: action.name), active(action, clip: clip, index: index) else { return nil }
        if command == .shadow { return shadowAttackBox(index, action: action) }
        let strikes = activeStrikes(action, clip: clip, index: index)
        let sides = Set(strikes.flatMap(\.weaponSides))
        let authored = strikes.compactMap(\.collisionEdgeIDs)
        let ids = authored.isEmpty ? nil : Set(authored.flatMap { $0 })
        let points = endpoints(index, clip: clip, phase: clip.phase(at: action.tick), command: command,
                               weaponSides: sides, collisionEdgeIDs: ids)
        guard !points.isEmpty else { return nil }
        let f = fighters[index], xs = points.map { f.x + Int($0.x * 1000) * f.facing }
        let ys = points.map { f.y + Int(($0.y + clip.tracks.lift(phase: clip.phase(at: action.tick))) * 1000) }
        let radius = collisionEdges(clip, sides: sides, ids: ids)?.map(\.radiusMillimeters).max() ?? 80
        return .init(minX: (xs.min() ?? f.x) - radius, maxX: (xs.max() ?? f.x) + radius,
                     minY: (ys.min() ?? 0) - radius, maxY: (ys.max() ?? 0) + radius)
    }
    public mutating func step(_ player: DuelGame.Input, opponent: DuelGame.Input? = nil) {
        events.removeAll(keepingCapacity: true); contacts.removeAll(keepingCapacity: true)
        swings.removeAll(keepingCapacity: true)
        panguPresentationEvents.removeAll(keepingCapacity: true)
        triadPresentationEvents.removeAll(keepingCapacity: true)
        sourceMotionSamples.removeAll(keepingCapacity: true)
        if case .matchOver = phase { return }
        frame += 1
        if case .roundBreak(let winner, let ticks) = phase {
            sourcePresentationTick += 1
            if ticks > 1 {
                advanceSourceVictoryStances()
                phase = .roundBreak(winner: winner, remaining: ticks - 1)
            } else if let winner, wins[winner] >= 2 {
                // Win_Idle tick zero was visible for the previous complete
                // authoritative tick. Match-over may now stop App/network work.
                phase = .matchOver(winner: winner)
            } else { resetRound() }
            return
        }
        releaseCompletedSourceIntros()
        if sourceIntroActive {
            sourcePresentationTick += 1
            cancelBufferedInputs()
            advanceSourceIntro()
            return
        }
        let inputs = [player, opponent ?? (mode == .versus ? botInput() : .neutral)]
        if hitStop > 0 {
            for i in 0..<2 where queued[i] == nil && !isAirborne(i) && actions[i]?.role != "jump"
                && !ordinaryThrowOwns(i) && ordinaryThrowKnockdownTicks[i] == 0 {
                if let command = inputs[i].weaponCommand, canUse(command, index: i), actions[i]?.reaction != true {
                    if (panguStates[i] != nil || triadStates[i] != nil) && (command == .shadow || command == .ranged) { continue }
                    if let action = actions[i], action.command == .shadow,
                       DuelShadowRules.duration(katana: profiles[i].isKatana) - action.tick > 24 { continue }
                    queued[i] = command
                }
            }
            hitStop -= 1; return
        }
        sourcePresentationTick += 1
        if mode == .versus { remainingTicks -= 1 }
        panguSpace.tick += 1
        triadSpace.tick += 1
        recordTriadSourceTimeline()
        previousX = fighters.map(\.x); previousY = fighters.map(\.y)
        previousPoses = fighters.map(\.weaponPose); previousFacings = fighters.map(\.facing)
        previousHurtY = fighters.indices.map { hurtBox($0).minY }
        panguSpace.lastAirborne = fighters.indices.map { isAirborne($0) }
        for i in 0..<2 {
            if var state = panguStates[i] {
                let effects = state.step(); panguStates[i] = state
                panguSpace.enqueue(effects, owner: i)
                fighters[i].energy = state.light * 100 / state.rules.light.maximum
                continue
            }
            if var state = triadStates[i] {
                configureTriadSummonSpace(&state, owner: i)
                if inputs[i].vertical == 0, inputs[i].move == 0,
                   inputs[i].rangedHeld || inputs[i].weaponCommand == .ranged {
                    state.requestOnslaughtContinuation()
                }
                let effects = state.step(); triadStates[i] = state
                triadSpace.enqueue(effects, owner: i)
                fighters[i].energy = state.mist * 100 / state.rules.mist.maximum
                continue
            }
            shadowCooldowns[i] = max(0, shadowCooldowns[i] - 1)
            // A missed shadow must not leave its owner dependent on landing hits.
            // Regenerate after cooldown; hit-stop and round breaks remain frozen.
            if shadowCooldowns[i] == 0 && frame % 6 == 0 && actions[i]?.command != .shadow {
                fighters[i].energy = min(100, fighters[i].energy + 1)
            }
        }
        consumePanguEffects()
        consumeTriadEffects()
        // Existing throws advance once per live tick. An input that starts a
        // new attempt below leaves its authored tick-zero sample visible.
        let advancingThrows = ordinaryThrowStates.map { $0 != nil }
        let advancingSourceThrows = sourceThrowStates.map { $0?.tick }
        for i in 0..<2 { sourceThrowDisabledTicks[i] = max(0, sourceThrowDisabledTicks[i] - 1) }
        prepareOrdinaryThrowSamples()
        prepareSourceThrowSamples()
        resolveSourceThrowInputs(inputs)
        for i in 0..<2 { update(i, input: inputs[i]) }
        consumePanguEffects()
        consumeTriadEffects()
        separate()
        resolveOrdinaryThrows(advancing: advancingThrows)
        resolveSourceThrows(advancing: advancingSourceThrows)
        // A caster can be pushed by body separation during startup. Anchor
        // release to the actual post-separation tick-24 hand, then retain that
        // origin so later pushes cannot rewrite an already flown outgoing path.
        for i in 0..<2 where !profiles[i].isKatana && actions[i]?.command == .shadow {
            if (actions[i]?.tick ?? Int.max) <= DuelShadowRules.startup { actions[i]?.shadowOriginX = fighters[i].x }
        }
        resolveOrdinaryContacts()
        resolvePanguContacts()
        resolveTriadContacts()
        // Faster attacks are sampled in every crossed logical frame. Increasing
        // only the displayed animation tick would skip narrow contact windows
        // and combo anchors. World timers, impulses and projectiles still run
        // once per authoritative 60 Hz tick.
        var extras = [0, 0]
        for i in 0..<2 {
            if let state = panguStates[i], actions[i]?.command != nil, actions[i]?.reaction == false {
                panguSpace.speedRemainders[i] += max(0, state.attackSpeedBps - 10_000)
                extras[i] = panguSpace.speedRemainders[i] / 10_000
                panguSpace.speedRemainders[i] %= 10_000
            } else { panguSpace.speedRemainders[i] = 0 }
        }
        for microstep in 0..<max(extras[0], extras[1]) {
            if hitStop > 0 || fighters.contains(where: { $0.health <= 0 }) { break }
            let eligible = (0..<2).map { i in
                extras[i] > microstep && actions[i]?.command != nil &&
                    actions[i]?.reaction == false && panguStates[i]?.activeCast == nil
            }
            previousX = fighters.map(\.x); previousY = fighters.map(\.y)
            previousPoses = fighters.map(\.weaponPose); previousFacings = fighters.map(\.facing)
            previousHurtY = fighters.indices.map { hurtBox($0).minY }
            for i in 0..<2 where eligible[i] { update(i, input: .neutral, advanceWorld: false) }
            separate(); resolveOrdinaryContacts(eligible: eligible)
        }
        consumeTriadEffects()
        for i in 0..<2 {
            if panguSpace.lastAirborne[i], !isAirborne(i), panguSpace.jumpEligible[i], var state = panguStates[i] {
                let effects = state.landed(eventID: panguSpace.nextHitID())
                panguStates[i] = state; panguSpace.enqueue(effects, owner: i)
                panguSpace.jumpEligible[i] = false
                recordPanguPresentation(.landed(owner: i, position: .init(x: Double(fighters[i].x) / 1000, y: 0)))
            }
            if let state = panguStates[i] { fighters[i].energy = state.light * 100 / state.rules.light.maximum }
            if let state = triadStates[i] { fighters[i].energy = state.mist * 100 / state.rules.mist.maximum }
        }
        // Motion changes emitted at AnimationEnd may extend the same model.
        // Apply those transitions before removing its previous lifetime.
        triadSpace.summons.removeAll { triadSpace.tick >= $0.expiresAt }
        resolveRound()
    }
    private mutating func resolveOrdinaryContacts(eligible: [Bool] = [true, true]) {
        var pending: [(attacker: Int, point: DuelWeaponPoint, command: DuelWeaponCommand,
                       strike: DuelCombatStrike, blocked: Bool, direction: Int)] = []
        for i in 0..<2 where eligible[i] {
            guard var action = actions[i], let command = action.command,
                  let clip = profiles[i].clip(named: action.name), !action.reaction else { continue }
            let strikes = activeStrikes(action, clip: clip, index: i)
            let isActive = !strikes.isEmpty
            if isActive && !action.sounded && action.tick >= action.soundAt {
                swings.append(.init(attacker: i, heavy: command == .heavy || command == .shadow,
                                     usesWeapon: !command.rawValue.hasPrefix("kick")))
                action.sounded = true
            }
            let inheritedContact = action.requiresContactSeparation
            if inheritedContact {
                // Strike IDs are local to a stage. A new ID at a shared combo
                // pose cannot turn the same uninterrupted physical overlap
                // into another hit. A separating sample clears this latch for
                // the following tick, without replaying the boundary sweep.
                action.requiresContactSeparation = currentContactOverlap(i, action: action, clip: clip,
                                                                         command: command)
            }
            var touchingIDs: [Int] = []
            for strike in strikes {
                guard let point = contact(i, action: action, clip: clip, command: command,
                                          weaponSides: Set(strike.weaponSides),
                                          collisionEdgeIDs: strike.collisionEdgeIDs.map(Set.init)) else { continue }
                touchingIDs.append(strike.id)
                guard !inheritedContact, !action.touchingStrikeIDs.contains(strike.id),
                      !action.landedStrikeIDs.contains(strike.id) else { continue }
                let defender = 1 - i
                let weapon = !command.rawValue.hasPrefix("kick") && command != .shadow
                let breakthrough = weapon && triadStates[i]?.weaponDamage(strike.damage).bypassesBlock == true
                pending.append((i, point, command, strike,
                                fighters[defender].guarding && !isAirborne(defender) &&
                                triadStates[i]?.opponentCanBlock != false && !breakthrough, fighters[i].facing))
                action.landedStrikeIDs.append(strike.id); action.hits += 1
            }
            action.touching = !touchingIDs.isEmpty; action.touchingStrikeIDs = touchingIDs; actions[i] = action
        }
        // Resolve both swept contacts after collecting them, preserving trades.
        for hit in pending {
            applyHit(hit.attacker, point: hit.point, command: hit.command, strike: hit.strike,
                     blocked: hit.blocked, direction: hit.direction)
        }
    }
    private mutating func update(_ i: Int, input suppliedInput: DuelGame.Input, advanceWorld: Bool = true) {
        var input = suppliedInput
        if advanceWorld {
            fighters[i].flash = 0; fighters[i].walking = false; fighters[i].movementDirection = 0
            fighters[i].invulnerable = max(0, fighters[i].invulnerable - 1)
            if ordinaryThrowOwns(i) {
                queued[i] = nil; fighters[i].guarding = false; fighters[i].attack = nil
                return
            }
            if updatePanguControl(i) { return }
            if let ability = triadAbility(for: input, index: i), ability.soul != nil {
                // A soul owns a separate source model, not the owner's action.
                // Consume the edge once, including during a root hold or jump.
                startTriad(i, ability: ability)
                input.weaponCommand = nil
            }
            if updateTriadControl(i) { return }
            if ordinaryThrowKnockdownTicks[i] > 0 {
                fighters[i].stun = ordinaryThrowKnockdownTicks[i]
                fighters[i].knockdown = ordinaryThrowKnockdownTicks[i]
                ordinaryThrowKnockdownTicks[i] -= 1
                queued[i] = nil
                return
            }
        }
        let justLanded = advanceWorld ? advanceImpact(i) : false
        if var action = actions[i], var clip = profiles[i].clip(named: action.name) {
            if let command = input.weaponCommand, !action.reaction,
               !((panguStates[i] != nil || triadStates[i] != nil) && (command == .shadow || command == .ranged)) {
                if action.role == "jump" {
                    // An aerial press is consumed in the air, never delayed
                    // until landing and unexpectedly replayed as a ground kick.
                    if command.rawValue.hasPrefix("kick"), let aerial = profiles[i].clip(role: "kickJump") {
                        let p = min(0.6, clip.phase(at: action.tick))
                        begin(i, clip: aerial, role: "kickJump", command: command, tick: Int(p * Double(aerial.ticks)))
                        return
                    }
                } else if !isAirborne(i) && action.command != nil && queued[i] == nil && canUse(command, index: i) {
                    let link = profiles[i].combo(from: action.name)
                    let duration = action.command == .shadow ? DuelShadowRules.duration(katana: profiles[i].isKatana) : clip.ticks
                    let comboTick = link.map { clip.tick(atSourceFrame: $0.sourceFrame) } ?? -1
                    if (command == action.command && action.command != .shadow && action.tick <= comboTick) || duration - action.tick <= 24 {
                        queued[i] = command
                    }
                }
            }
            if let continued = consumeCombo(i, action: action) {
                action = continued; clip = profiles[i].clip(named: action.name) ?? clip
            }
            let oldPhase = clip.phase(at: action.tick)
            action.tick += 1
            if action.tick > (action.command == .shadow ? DuelShadowRules.duration(katana: profiles[i].isKatana) : clip.ticks) {
                // The authored reaction may end before an explicitly launched
                // fighter reaches the floor. Hold its final sample, with no
                // repeated root delta, until motion has settled. A landing
                // sample remains visible before get-up can begin.
                if action.reaction && (impactMotions[i] != nil || justLanded) {
                    action.tick = clip.ticks; actions[i] = action
                    fighters[i].stun = 1
                    if action.role == "knockdown" || action.role == "getUp" { fighters[i].knockdown = 1 }
                    setPose(i, clip: clip, tick: clip.ticks, reaction: true)
                    return
                }
                actions[i] = nil; fighters[i].attack = nil; fighters[i].stun = 0; fighters[i].knockdown = 0
                if action.role == "knockdown", let up = profiles[i].clip(role: "getUp") {
                    begin(i, clip: up, role: "getUp", reaction: true); return
                }
                if action.role == "getUp" { fighters[i].invulnerable = 20 }
                let next = queued[i]; queued[i] = nil
                if let next, !action.reaction { startCommand(i, command: next) }
                else {
                    // Recovery has finished. Apply live stance/movement now,
                    // rather than leaving an extra unguarded idle frame. Attack
                    // and jump edges seen during recovery remain consumed.
                    var stance = input
                    stance.weaponCommand = nil; stance.taps = []
                    updateReady(i, input: stance)
                }
                return
            }
            if action.command == .shadow {
                if profiles[i].isKatana && DuelShadowRules.active(action.tick, katana: true) {
                    // A visible bounded dash stops at the opposing body/wall.
                    // No relocation or contact across the raw 8 m source gap.
                    let targetLimit = fighters[1 - i].x - fighters[i].facing * DuelGame.bodyWidth
                    let desired = clamped(fighters[i].x + fighters[i].facing * 150)
                    fighters[i].x = fighters[i].facing > 0 ? min(desired, max(fighters[i].x, targetLimit)) :
                        max(desired, min(fighters[i].x, targetLimit))
                }
                actions[i] = action; fighters[i].attack?.age = action.tick
                setShadowPose(i, clip: clip, tick: action.tick)
                return
            }
            let t = clip.tracks, delta = t.sample(t.root, phase: clip.phase(at: action.tick)).x - t.sample(t.root, phase: oldPhase).x
            fighters[i].x += Int((delta * 1000).rounded()) * fighters[i].facing
            fighters[i].x = clamped(fighters[i].x)
            if action.role == "jump" { fighters[i].x = clamped(fighters[i].x + input.move * 40) }
            // An explicit strike may own this exact shared anchor. Resolve its
            // contact before entering the next stage; the pre-increment combo
            // path above consumes the same anchor on the next live sample.
            // Legacy timelines retain their established transition timing.
            let needsAnchorContact = profiles[i].combatRules != nil &&
                activeStrikes(action, clip: clip, index: i).contains { !action.landedStrikeIDs.contains($0.id) }
            if !needsAnchorContact, let continued = consumeCombo(i, action: action) { action = continued }
            let displayed = profiles[i].clip(named: action.name) ?? clip
            actions[i] = action; fighters[i].attack?.age = action.tick
            if action.reaction {
                let pendingMotion = impactMotions[i] != nil || justLanded
                fighters[i].stun = max(pendingMotion ? 1 : 0, clip.ticks - action.tick)
                if action.role == "knockdown" || action.role == "getUp" { fighters[i].knockdown = fighters[i].stun }
            }
            setPose(i, clip: displayed, tick: action.tick, reaction: action.reaction)
            return
        }
        updateReady(i, input: input)
    }
    /// Called only from a live simulation step, after the hit-stop early return.
    /// Root animation and external impact displacement are each applied once.
    private mutating func advanceImpact(_ i: Int) -> Bool {
        guard var motion = impactMotions[i] else { return false }
        let sample = motion.advance(x: fighters[i].x, y: fighters[i].y, velocityY: fighters[i].velocityY)
        fighters[i].x = sample.x; fighters[i].y = sample.y; fighters[i].velocityY = sample.velocityY
        impactMotions[i] = motion.horizontalFinished && sample.y == 0 && sample.velocityY == 0 ? nil : motion
        if panguSpace.controls[i].pendingAirHoldTicks > 0 && sample.y > 0 && sample.velocityY <= 0 {
            panguSpace.controls[i].airHeight = sample.y
            panguSpace.controls[i].airUntil = panguSpace.tick + panguSpace.controls[i].pendingAirHoldTicks
            panguSpace.controls[i].pendingAirHoldTicks = 0
            fighters[i].velocityY = 0
            recordPanguControl(.airHeld, target: i)
        }
        return sample.landed
    }
    private mutating func updateReady(_ i: Int, input: DuelGame.Input) {
        fighters[i].facing = fighters[1 - i].x >= fighters[i].x ? 1 : -1
        // Back is relative to the current opponent, including after crossing
        // sides. Retreat can block; forward, crouch, jump and attacks cannot.
        fighters[i].guarding = input.guardHeld && input.weaponCommand == nil && input.vertical == 0 &&
            (input.move == 0 || input.move == -fighters[i].facing) && triadStates[1 - i]?.opponentCanBlock != false
        if let command = input.weaponCommand ?? queued[i] {
            queued[i] = nil
            if let ability = panguAbility(for: input, index: i) { startPangu(i, ability: ability) }
            else if let ability = triadAbility(for: input, index: i) { startTriad(i, ability: ability) }
            else { startCommand(i, command: command) }
            return
        }
        if input.taps.contains(.jump), let jump = profiles[i].clip(role: "jump") {
            panguSpace.jumpEligible[i] = panguStates[i] != nil
            begin(i, clip: jump, role: "jump"); events.append(.jumped(player: i)); return
        }
        if input.vertical < 0 {
            fighters[i].guarding = false; loop(i, role: "crouch")
        } else if input.move != 0 {
            let role = input.move * fighters[i].facing > 0 ? "walkForward" : "walkBackward"
            fighters[i].walking = true; fighters[i].movementDirection = input.move
            loop(i, role: role, moving: true)
        } else { loop(i, role: "idle") }
    }
    private mutating func loop(_ i: Int, role: String, moving: Bool = false) {
        guard let clip = profiles[i].clip(role: role) ?? profiles[i].clip(role: "idle") else { return }
        if loopRoles[i] != role { loopRoles[i] = role; loopTicks[i] = 0 }
        let tick = loopTicks[i] % clip.ticks
        if moving {
            let t = clip.tracks
            // Include the final source interval before wrapping the visual
            // phase, so every step accumulates its real net root displacement.
            let delta = t.sample(t.root, phase: clip.phase(at: tick + 1)).x - t.sample(t.root, phase: clip.phase(at: tick)).x
            fighters[i].x = clamped(fighters[i].x + Int((delta * 1000).rounded()) * fighters[i].facing)
        }
        loopTicks[i] += 1
        setPose(i, clip: clip, tick: loopTicks[i] % clip.ticks)
    }
    private mutating func startCommand(_ i: Int, command: DuelWeaponCommand) {
        guard canUse(command, index: i) else { return }
        if startOrdinaryThrow(i, command: command) { return }
        guard let clip = profiles[i].clip(command: command == .shadow ? .heavy : command) else { return }
        if command == .shadow {
            fighters[i].energy -= 100; shadowCooldowns[i] = DuelShadowRules.cooldown
        }
        begin(i, clip: clip, role: command.rawValue, command: command)
        if var state = panguStates[i] {
            let effects = state.attackStarted(heavy: command == .heavy, eventID: panguSpace.nextHitID())
            panguStates[i] = state; panguSpace.enqueue(effects, owner: i)
        }
        if var state = triadStates[i] {
            let effects = state.weaponAttackStarted(eventID: triadSpace.nextHitID())
            triadStates[i] = state; triadSpace.enqueue(effects, owner: i)
        }
        if command == .shadow {
            actions[i]?.shadowOriginX = fighters[i].x
            let rule = profiles[i].resolvedCombatRule(command: command, clipName: clip.name)
            actions[i]?.soundAt = rule?.strikes.map(\.startTick).min() ?? Int.max
            setShadowPose(i, clip: clip, tick: 0)
            if var state = triadStates[1 - i] {
                let effects = state.opponentUsedShadowMove(eventID: triadSpace.nextHitID())
                triadStates[1 - i] = state; triadSpace.enqueue(effects, owner: 1 - i)
            }
        }
    }
    private mutating func consumeCombo(_ i: Int, action: Action) -> Action? {
        guard action.command != .shadow, let link = profiles[i].combo(from: action.name),
              let source = profiles[i].clip(named: action.name), action.tick == source.tick(atSourceFrame: link.sourceFrame),
              let command = action.command, queued[i] == command, action.comboDepth < 2,
              let clip = profiles[i].clip(named: link.to),
              profiles[i].resolvedCombatRule(command: command, clipName: clip.name) != nil else { return nil }
        // The source-frame anchor also accepts a press delivered during a hit
        // stop at that exact frame. Both paths preserve the existing timeline.
        queued[i] = nil
        // Enter one new stage at the existing source-time anchor. Preserve the
        // contact latch across the shared pose so a held overlap cannot hit
        // twice; give only this stage its own hit opportunity. Missed earlier
        // stages do not bank damage for subsequent weapon re-entries.
        let nextTick = clip.tick(atSourceFrame: link.sourceFrame)
        return Action(name: link.to, role: action.role, command: command, tick: nextTick,
                      hits: 0, touching: action.touching, landedStrikeIDs: [],
                      touchingStrikeIDs: action.touchingStrikeIDs,
                      requiresContactSeparation: action.touching || action.requiresContactSeparation,
                      sounded: false, reaction: false,
                      comboDepth: action.comboDepth + 1, soundAt: swingTick(i, clip: clip, command: command, after: nextTick))
    }
    private mutating func begin(_ i: Int, clip: DuelWeaponClip, role: String,
                                command: DuelWeaponCommand? = nil, tick: Int = 0, reaction: Bool = false) {
        actions[i] = Action(name: clip.name, role: role, command: command, tick: tick, reaction: reaction,
                            soundAt: command.map { swingTick(i, clip: clip, command: $0, after: tick) } ?? Int.max)
        loopRoles[i] = ""; loopTicks[i] = 0
        fighters[i].guarding = false; fighters[i].walking = false
        fighters[i].attack = command.map { .init(move: $0 == .heavy ? .heavy : $0 == .shadow ? .skill2 : .jab) }
        if reaction { queued[i] = nil; fighters[i].stun = clip.ticks - tick }
        if role == "knockdown" || role == "getUp" { fighters[i].knockdown = clip.ticks - tick }
        setPose(i, clip: clip, tick: tick, reaction: reaction, restart: true)
    }
    private mutating func setPose(_ i: Int, role: String, tick: Int) {
        guard let clip = profiles[i].clip(role: role) ?? profiles[i].clip(role: "idle") else { return }
        setPose(i, clip: clip, tick: tick % max(1, clip.ticks))
    }
    private mutating func setPose(_ i: Int, clip: DuelWeaponClip, tick: Int, reaction: Bool = false,
                                 restart: Bool = false) {
        let old = fighters[i].weaponPose
        fighters[i].weaponPose = .init(clip: clip.name, tick: tick, duration: clip.ticks,
                                      groundLift: clip.tracks.lift(phase: clip.phase(at: tick)), reaction: reaction)
        if profiles[i].isTriad || profiles[i].ordinaryThrows?.source != nil, sourceMotionSamples.count < 256,
           restart || old?.clip != clip.name || old?.tick != tick {
            let previous = !restart && old?.clip == clip.name && (old?.tick ?? 0) <= tick ? old!.tick : tick - 1
            sourceMotionSamples.append(.init(frame: frame, sequence: sourceMotionSamples.count, owner: i,
                clip: clip.name, previousTick: previous, tick: tick, duration: clip.ticks))
        }
    }
    private mutating func setShadowPose(_ i: Int, clip: DuelWeaponClip, tick: Int) {
        setPose(i, clip: clip, tick: shadowBodyTick(i, clip: clip, tick: tick))
    }
    private func shadowBodyTick(_ i: Int, clip: DuelWeaponClip, tick: Int) -> Int {
        min(clip.ticks, tick * clip.ticks / DuelShadowRules.duration(katana: profiles[i].isKatana))
    }
    private func heldShadowHammer(_ i: Int, clip: DuelWeaponClip, tick: Int,
                                  rootX: Int) -> DuelShadowRules.HammerSegment? {
        let phase = clip.phase(at: shadowBodyTick(i, clip: clip, tick: tick))
        let lift = clip.tracks.lift(phase: phase), direction = Double(fighters[i].facing)
        func world(_ point: DuelWeaponPoint) -> DuelWeaponPoint {
            .init(x: Double(rootX) / 1000 + point.x * direction,
                  y: Double(fighters[i].y) / 1000 + point.y + lift, z: point.z * direction)
        }
        let segment = DuelShadowRules.HammerSegment(
            base: world(clip.tracks.sample(clip.tracks.weaponBaseR, phase: phase)),
            tip: world(clip.tracks.sample(clip.tracks.weaponTipR, phase: phase)))
        return DuelShadowRules.valid(segment) ? segment : nil
    }
    private func shadowHammer(_ i: Int, action: Action, tick: Int) -> DuelShadowRules.HammerSegment? {
        guard (24..<72).contains(tick), let origin = action.shadowOriginX,
              let clip = profiles[i].clip(named: action.name),
              let release = heldShadowHammer(i, clip: clip, tick: 24, rootX: origin),
              let catchPose = heldShadowHammer(i, clip: clip, tick: 71, rootX: fighters[i].x),
              let held = heldShadowHammer(i, clip: clip, tick: tick, rootX: origin) else { return nil }
        return DuelShadowRules.hammer(tick, origin: origin, direction: fighters[i].facing,
                                      release: release, catchPose: catchPose,
                                      length: DuelShadowRules.distance(held.base, held.tip))
    }
    private func active(_ action: Action, clip: DuelWeaponClip, index: Int) -> Bool {
        !activeStrikes(action, clip: clip, index: index).isEmpty
    }
    private func activeStrikes(_ action: Action, clip: DuelWeaponClip, index: Int) -> [DuelCombatStrike] {
        guard let command = action.command,
              let rule = profiles[index].resolvedCombatRule(command: command, clipName: clip.name) else { return [] }
        return rule.strikes.filter { ($0.startTick...$0.endTick).contains(action.tick) }
    }
    private func endpoints(_ i: Int, clip: DuelWeaponClip, phase: Double, command: DuelWeaponCommand,
                           weaponSides: Set<String>? = nil, collisionEdgeIDs: Set<String>? = nil) -> [DuelWeaponPoint] {
        let t = clip.tracks
        if command.rawValue.hasPrefix("kick") && collisionEdgeIDs == nil {
            return [t.sample(t.footL, phase: phase), t.sample(t.footR, phase: phase)]
        }
        if let edges = collisionEdges(clip, sides: weaponSides, ids: collisionEdgeIDs) {
            return edges.flatMap { [t.sample($0.base, phase: phase), t.sample($0.tip, phase: phase)] }
        }
        var p: [DuelWeaponPoint] = []
        if profiles[i].activeWeaponSides.contains("left"), weaponSides?.contains("left") ?? true {
            p += [t.sample(t.weaponBaseL, phase: phase), t.sample(t.weaponTipL, phase: phase)]
        }
        if profiles[i].activeWeaponSides.contains("right"), weaponSides?.contains("right") ?? true {
            p += [t.sample(t.weaponBaseR, phase: phase), t.sample(t.weaponTipR, phase: phase)]
        }
        return p
    }
    private func collisionEdges(_ clip: DuelWeaponClip, sides: Set<String>? = nil,
                                ids: Set<String>? = nil) -> [DuelWeaponCollisionEdge]? {
        guard clip.tracks.collisionEdges != nil || ids != nil else { return nil }
        var result = (clip.tracks.collisionEdges ?? []).filter {
            (sides?.contains($0.side) ?? true) && (ids?.contains($0.id) ?? true)
        }
        if let ids {
            result += (clip.tracks.hurtCapsules ?? []).filter { ids.contains($0.id) }.map {
                .init(id: $0.id, side: "body", radiusMillimeters: $0.radiusMillimeters, base: $0.base, tip: $0.tip)
            }
        }
        return result
    }
    private func motionSpeed(_ i: Int, clip: DuelWeaponClip, command: DuelWeaponCommand, tick: Int) -> Double {
        guard tick > 0 else { return 0 }
        let a = endpoints(i, clip: clip, phase: clip.phase(at: tick - 1), command: command)
        let b = endpoints(i, clip: clip, phase: clip.phase(at: tick), command: command)
        var fastest: Double = 0
        for (p, q) in zip(a, b) {
            let distance = DuelWeaponSweepContinuity.distance(from: p, to: q)
            // Each hammer owns its samples. One discontinuous endpoint must
            // not suppress the other hammer's valid swing or active ribbon.
            if DuelWeaponSweepContinuity.accepts(distance: distance) {
                fastest = max(fastest, distance)
            }
        }
        return fastest
    }
    private func swingTick(_ i: Int, clip: DuelWeaponClip, command: DuelWeaponCommand, after: Int) -> Int {
        guard let rule = profiles[i].resolvedCombatRule(command: command, clipName: clip.name),
              let first = rule.strikes.map(\.startTick).min(), let last = rule.strikes.map(\.endTick).max() else { return Int.max }
        let start = max(after + 1, first), end = min(clip.ticks, last)
        guard start <= end else { return Int.max }
        // A teleport must neither trigger a swing nor dominate the peak and
        // suppress a later valid stroke. Keep the bounded shadow timeline above.
        let speeds = (start...end).map { tick -> Double in
            guard rule.strikes.contains(where: { ($0.startTick...$0.endTick).contains(tick) }) else { return 0 }
            let speed = motionSpeed(i, clip: clip, command: command, tick: tick)
            return DuelWeaponSweepContinuity.accepts(distance: speed) ? speed : 0
        }
        guard let peak = speeds.max(), peak > 0.005,
              let onset = speeds.firstIndex(where: { $0 >= peak * 0.65 }) else { return Int.max }
        // An explicit native adaptation: start audio at the source geometry's
        // fast motion onset, not an arbitrary fraction of a long wind-up.
        return start + onset
    }
    private func shadowAttackBox(_ i: Int, action: Action) -> DuelGame.Box? {
        if profiles[i].isKatana {
            let x = fighters[i].x, direction = fighters[i].facing
            let a = x + direction * 250, b = x + direction * 1400
            return .init(minX: min(a, b), maxX: max(a, b),
                         minY: fighters[i].y + 850, maxY: fighters[i].y + 1250)
        }
        guard let points = shadowHammer(i, action: action, tick: action.tick) else { return nil }
        return .init(minX: Int((min(points.base.x, points.tip.x) * 1000).rounded()) - 180,
                     maxX: Int((max(points.base.x, points.tip.x) * 1000).rounded()) + 180,
                     minY: Int((min(points.base.y, points.tip.y) * 1000).rounded()) - 180,
                     maxY: Int((max(points.base.y, points.tip.y) * 1000).rounded()) + 180)
    }
    private func shadowContact(_ i: Int, action: Action) -> DuelWeaponPoint? {
        let target = fighters[1 - i], hurt = hurtBox(1 - i)
        guard target.knockdown == 0, target.invulnerable == 0 else { return nil }
        if profiles[i].isKatana {
            guard let box = shadowAttackBox(i, action: action), box.overlaps(hurt) else { return nil }
            return .init(x: Double(min(hurt.maxX, max(hurt.minX, (box.minX + box.maxX) / 2))) / 1000,
                         y: Double(fighters[i].y) / 1000 + 1.05, z: 0.08)
        }
        guard DuelShadowRules.active(action.tick, katana: false),
              let now = shadowHammer(i, action: action, tick: action.tick),
              let clip = profiles[i].clip(named: action.name) else { return nil }
        let released = action.tick > DuelShadowRules.startup
        let before = released ? shadowHammer(i, action: action, tick: action.tick - 1)
                              : heldShadowHammer(i, clip: clip, tick: action.tick - 1, rootX: previousX[i])
        guard let before else { return nil }
        let relative = DuelShadowRules.HammerSegment(base: relativePrevious(before.base, target: 1 - i),
                                                     tip: relativePrevious(before.tip, target: 1 - i))
        return DuelShadowRules.hammerContact(previous: relative, current: now, sweep: released, hurt: hurt)
    }
    private func contact(_ i: Int, action: Action, clip: DuelWeaponClip, command: DuelWeaponCommand,
                         weaponSides: Set<String>, collisionEdgeIDs: Set<String>? = nil) -> DuelWeaponPoint? {
        if command == .shadow { return shadowContact(i, action: action) }
        let target = fighters[1 - i]
        guard target.knockdown == 0, target.invulnerable == 0, action.tick > 0 else { return nil }
        let p = clip.phase(at: action.tick), before = clip.phase(at: action.tick - 1)
        let now = endpoints(i, clip: clip, phase: p, command: command, weaponSides: weaponSides, collisionEdgeIDs: collisionEdgeIDs)
        let old = endpoints(i, clip: clip, phase: before, command: command, weaponSides: weaponSides, collisionEdgeIDs: collisionEdgeIDs)
        let edges = command.rawValue.hasPrefix("kick") && collisionEdgeIDs == nil ? nil :
            collisionEdges(clip, sides: weaponSides, ids: collisionEdgeIDs)
        let f = fighters[i], box = hurtBox(1 - i)
        func world(_ a: DuelWeaponPoint, previous: Bool) -> DuelWeaponPoint {
            .init(x: Double(previous ? previousX[i] : f.x) / 1000 + a.x * Double(f.facing),
                  y: Double(previous ? previousY[i] : f.y) / 1000 + a.y + clip.tracks.lift(phase: previous ? before : p), z: a.z * Double(f.facing))
        }
        if let hurts = sourceHurtCapsules(1 - i) {
            let oldHurts = Dictionary(uniqueKeysWithValues: (sourceHurtCapsules(1 - i, previous: true) ?? hurts).map { ($0.id, $0.capsule) })
            let kick = command.rawValue.hasPrefix("kick"), pointKick = kick && edges == nil
            let strideSize = pointKick ? 1 : 2
            var earliest: DuelWeaponCapsule.Contact?
            for n in stride(from: 0, to: now.count, by: strideSize) {
                let end = pointKick ? n : n + 1
                guard old.indices.contains(end), now.indices.contains(end) else { continue }
                let speeds = [DuelWeaponSweepContinuity.distance(from: old[n], to: now[n]),
                              DuelWeaponSweepContinuity.distance(from: old[end], to: now[end])]
                guard speeds.allSatisfy({ DuelWeaponSweepContinuity.accepts(distance: $0) }),
                      edges != nil || speeds.max()! > 0.005 else { continue }
                let radius = edges.map { Double($0[n / 2].radiusMillimeters) / 1000 } ?? (kick ? 0.12 : 0.07)
                let oldAttack = DuelWeaponCapsule(a: world(old[n], previous: true), b: world(old[end], previous: true), radius: radius)
                let newAttack = DuelWeaponCapsule(a: world(now[n], previous: false), b: world(now[end], previous: false), radius: radius)
                for hurt in hurts {
                    if let hit = DuelWeaponCapsule.swept(attackBefore: oldAttack, attackAfter: newAttack,
                        hurtBefore: oldHurts[hurt.id] ?? hurt.capsule, hurtAfter: hurt.capsule),
                       earliest == nil || hit.time < earliest!.time { earliest = hit }
                }
            }
            return earliest?.point
        }
        for n in now.indices where old.indices.contains(n) {
            let radius = edges.map { Double($0[n / 2].radiusMillimeters) / 1000 } ??
                (command.rawValue.hasPrefix("kick") ? 0.12 : 0.07)
            // Sweep in the defender's current translating frame. Testing an
            // old weapon sample only against the new hurtbox can miss a
            // moving target or fabricate a contact after recoil separation.
            let a = relativePrevious(world(old[n], previous: true), target: 1 - i)
            let b = world(now[n], previous: false)
            let localSpeed = DuelWeaponSweepContinuity.distance(from: old[n], to: now[n])
            // Reject source discontinuities in all three axes, including an
            // out-of-plane return that used to fabricate a swept torso hit.
            guard edges != nil || localSpeed > 0.005, DuelWeaponSweepContinuity.accepts(distance: localSpeed),
                  abs(now[n].z) < 0.8, abs(old[n].z) < 0.8 else { continue }
            if Self.segment(a, b, intersects: box, radius: radius) {
                return .init(x: min(Double(box.maxX) / 1000, max(Double(box.minX) / 1000, b.x)),
                             y: min(Double(box.maxY) / 1000, max(Double(box.minY) / 1000, b.y)), z: 0.08)
            }
            if (!command.rawValue.hasPrefix("kick") || edges != nil), n % 2 == 1 {
                let baseSpeed = DuelWeaponSweepContinuity.distance(from: old[n - 1], to: now[n - 1])
                guard DuelWeaponSweepContinuity.accepts(distance: baseSpeed),
                      abs(now[n - 1].z) < 0.8, abs(old[n - 1].z) < 0.8 else { continue }
                let base = world(now[n - 1], previous: false)
                if Self.segment(base, b, intersects: box, radius: radius) {
                    return .init(x: Double(target.x) / 1000,
                                 y: min(Double(box.maxY) / 1000,
                                        max(Double(box.minY) / 1000, (base.y + b.y) * 0.5)), z: 0.08)
                }
            }
        }
        return nil
    }
    private func currentContactOverlap(_ i: Int, action: Action, clip: DuelWeaponClip,
                                       command: DuelWeaponCommand) -> Bool {
        let phase = clip.phase(at: action.tick), fighter = fighters[i]
        let ids = profiles[i].resolvedCombatRule(command: command, clipName: clip.name).flatMap { rule -> Set<String>? in
            let explicit = rule.strikes.compactMap(\.collisionEdgeIDs)
            return explicit.isEmpty ? nil : Set(explicit.flatMap { $0 })
        }
        let points = endpoints(i, clip: clip, phase: phase, command: command, collisionEdgeIDs: ids)
        let box = hurtBox(1 - i), kick = command.rawValue.hasPrefix("kick")
        let edges = kick && ids == nil ? nil : collisionEdges(clip, ids: ids)
        func world(_ point: DuelWeaponPoint) -> DuelWeaponPoint {
            .init(x: Double(fighter.x) / 1000 + point.x * Double(fighter.facing),
                  y: Double(fighter.y) / 1000 + point.y + clip.tracks.lift(phase: phase), z: point.z * Double(fighter.facing))
        }
        if let hurts = sourceHurtCapsules(1 - i) {
            let pointKick = kick && edges == nil
            for index in stride(from: 0, to: points.count, by: pointKick ? 1 : 2) {
                let end = pointKick ? index : index + 1
                guard points.indices.contains(end) else { continue }
                let radius = edges.map { Double($0[index / 2].radiusMillimeters) / 1000 } ?? (kick ? 0.12 : 0.07)
                let attack = DuelWeaponCapsule(a: world(points[index]), b: world(points[end]), radius: radius)
                if hurts.contains(where: { attack.overlaps($0.capsule) }) { return true }
            }
            return false
        }
        if kick && edges == nil {
            return points.contains { point in
                abs(point.z) < 0.8 && Self.segment(world(point), world(point), intersects: box, radius: 0.12)
            }
        }
        for index in stride(from: 0, to: max(0, points.count - 1), by: 2) {
            let radius = edges.map { Double($0[index / 2].radiusMillimeters) / 1000 } ?? 0.07
            let a = points[index], b = points[index + 1]
            if abs(a.z) < 0.8, abs(b.z) < 0.8,
               Self.segment(world(a), world(b), intersects: box, radius: radius) { return true }
        }
        return false
    }
    private func sourceHurtCapsules(_ index: Int, previous: Bool = false) -> [(id: String, capsule: DuelWeaponCapsule)]? {
        guard let pose = previous ? previousPoses[index] : fighters[index].weaponPose,
              let clip = profiles[index].clip(named: pose.clip), let tracks = clip.tracks.hurtCapsules else { return nil }
        let x = Double(previous ? previousX[index] : fighters[index].x) / 1000
        let y = Double(previous ? previousY[index] : fighters[index].y) / 1000 + pose.groundLift
        let facing = Double(previous ? previousFacings[index] : fighters[index].facing)
        func world(_ point: DuelWeaponPoint) -> DuelWeaponPoint {
            .init(x: x + point.x * facing, y: y + point.y, z: point.z * facing)
        }
        return tracks.map { track in
            (track.id, .init(a: world(clip.tracks.sample(track.base, phase: pose.phase)),
                b: world(clip.tracks.sample(track.tip, phase: pose.phase)),
                radius: Double(track.radiusMillimeters) / 1000))
        }
    }
    private func relativePrevious(_ point: DuelWeaponPoint, target: Int) -> DuelWeaponPoint {
        .init(x: point.x + Double(fighters[target].x - previousX[target]) / 1000,
              y: point.y + Double(hurtBox(target).minY - previousHurtY[target]) / 1000, z: point.z)
    }
    /// Slab intersection, not a swept bounding rectangle (which would accept
    /// the empty corners around a diagonal sword stroke).
    static func segment(_ a: DuelWeaponPoint, _ b: DuelWeaponPoint, intersects box: DuelGame.Box, radius: Double) -> Bool {
        var lo = 0.0, hi = 1.0
        for (start, end, lower, upper) in [
            (a.x, b.x, Double(box.minX) / 1000 - radius, Double(box.maxX) / 1000 + radius),
            (a.y, b.y, Double(box.minY) / 1000 - radius, Double(box.maxY) / 1000 + radius)
        ] {
            let d = end - start
            if abs(d) < 0.0000001 { if start < lower || start > upper { return false } }
            else {
                let x = (lower - start) / d, y = (upper - start) / d
                lo = max(lo, min(x, y)); hi = min(hi, max(x, y))
                if lo > hi { return false }
            }
        }
        return true
    }
    private mutating func applyHit(_ i: Int, point: DuelWeaponPoint, command: DuelWeaponCommand,
                                   strike: DuelCombatStrike, blocked requestedBlock: Bool, direction: Int,
                                   panguAttack: DuelPanguState.Attack? = nil,
                                   triadAttack: DuelTriadState.Attack? = nil) {
        let defender = 1 - i
        guard panguStates[defender]?.damageImmune != true else { return }
        var blocked = requestedBlock && panguAttack?.unblockable != true, deflected = false
        let kind: DuelPanguRules.DamageKind = panguAttack?.damageKind ?? triadAttack.flatMap {
            DuelPanguRules.DamageKind(rawValue: $0.damageKind.rawValue)
        } ?? (command.rawValue.hasPrefix("kick") ? .unarmed : command == .shadow ? .shadow : .weapon)
        if var state = triadStates[defender] {
            let receipt = state.defendAgainstIncomingAttack(
                whileAttacking: actions[defender]?.command != nil || state.activeCast != nil,
                canDeflect: state.rules.runtime == nil || (!requestedBlock && strike.damage > 0 && kind != .shadow),
                eventID: triadSpace.nextHitID())
            triadStates[defender] = state; triadSpace.enqueue(receipt.effects, owner: defender)
            if receipt.deflected { blocked = true; deflected = true }
        }
        panguSpace.jumpEligible[defender] = false
        let wasAirborne = isAirborne(defender)
        let previousBodyHeight = Double(fighters[defender].y) / 1000 + sourceVerticalOffset(defender)
        let heavy = triadAttack.map { $0.knocksDown } ?? panguAttack.map { $0.knocksDown || $0.ability == .heavenfall || $0.ability == .splitter }
            ?? (command == .heavy || command == .shadow)
        let response = blocked ? strike.blockedImpact : strike.impact
        guard let motion = DuelImpactMotion(response: response, direction: direction) else { return }
        let panguContactID = panguStates[i] == nil ? nil : panguSpace.nextHitID()
        let targetReactable = panguStates[defender]?.impactImmune != true && triadStates[defender]?.impactImmune != true &&
            (panguStates[defender]?.activeCast.flatMap { panguStates[defender]?.rules.ability($0.ability)?.interruptible } ?? true)
        var damage = blocked ? strike.blockedDamage : strike.damage
        if var state = panguStates[i], let contactID = panguContactID {
            if let panguAttack {
                damage = state.prepareContact(attack: panguAttack, blocked: blocked, hitID: contactID)
            } else {
                state.prepareOrdinaryContact(blocked: blocked, kind: kind, hitID: contactID)
                damage = state.outgoingDamage(damage, kind: kind, blocked: blocked)
            }
            panguStates[i] = state
        }
        let weapon = kind == .weapon && panguAttack == nil && triadAttack == nil
        let split = weapon ? triadStates[i]?.weaponDamage(damage, blocked: blocked) : nil
        var actualDamage = 0
        if !deflected {
            if let split {
                actualDamage += receiveTargetDamage(split.weapon, kind: .weapon, attacker: i, blocked: blocked)
                actualDamage += receiveTargetDamage(split.shadow, kind: .shadow, attacker: i, blocked: blocked)
            } else {
                actualDamage = receiveTargetDamage(damage,
                    kind: triadAttack?.damageKind ?? DuelTriadRules.DamageKind(rawValue: kind.rawValue)!,
                    attacker: i, blocked: blocked)
            }
        }
        // Native balance: refill within a normal health bar, including heavy
        // exchanges. Damage beyond remaining health cannot generate energy.
        // A shadow hit never refunds the caster's own cost.
        if command != .shadow && panguStates[i] == nil && triadStates[i] == nil {
            let gain = blocked ? 8 : (actualDamage + 4) / 5
            let multiplier = triadStates[defender]?.opponentShadowEnergyGainMultiplierBps ?? 10_000
            fighters[i].energy = min(100, fighters[i].energy + gain * multiplier / 10_000)
        }
        let received = blocked ? 10 : (actualDamage + 3) / 4
        if panguStates[defender] == nil && triadStates[defender] == nil {
            let multiplier = triadStates[i]?.opponentShadowEnergyGainMultiplierBps ?? 10_000
            fighters[defender].energy = min(100, fighters[defender].energy + received * multiplier / 10_000)
        }
        if triadAttack == nil, var state = triadStates[i] {
            let id = triadSpace.nextHitID()
            let effects = weapon ? state.weaponContact(blocked: blocked, critical: split?.critical ?? false, eventID: id) :
                state.ordinaryContact(blocked: blocked, eventID: id)
            triadStates[i] = state; triadSpace.enqueue(effects, owner: i)
        }
        var contactControls: [DuelPanguState.Control] = []
        var anchoredBonuses: [DuelPanguSpatialState.Hit] = []
        if var state = panguStates[i], let contactID = panguContactID {
            let effects = panguAttack.map { state.contact(attack: $0, blocked: blocked, hitID: contactID, reactable: targetReactable) } ??
                state.contact(blocked: blocked, generated: false, hitID: contactID, heavy: command == .heavy, kind: kind,
                    reactable: targetReactable)
            panguStates[i] = state
            // Control triggered by an actual hit applies on that contact tick;
            // new secondary attacks enter the next simulation tick's space.
            for effect in effects {
                if case .control(let control) = effect { contactControls.append(control) }
                else if case .attack(let bonus) = effect, panguAttack?.ability == .shard,
                        bonus.generated, bonus.ability == .shard, bonus.damageKind == .unarmed {
                    // This is a second damage component of the confirmed rock,
                    // not a new projectile at the caster's later position.
                    anchoredBonuses.append(.init(owner: i, attack: bonus, point: point,
                                                 direction: direction, blocked: blocked))
                } else { panguSpace.enqueue([effect], owner: i) }
            }
        }
        var interruptible = !deflected && targetReactable
        if var state = panguStates[defender], let cast = state.activeCast {
            interruptible = interruptible && state.rules.ability(cast.ability)?.interruptible == true
            if !blocked && interruptible {
                let effects = state.interrupt(); panguStates[defender] = state
                panguSpace.enqueue(effects, owner: defender)
                panguSpace.cancelMelee(owner: defender); panguSpace.lifts[defender] = nil
            }
        }
        if !blocked, interruptible, var state = triadStates[defender], state.activeCast != nil {
            let effects = state.interrupt(); triadStates[defender] = state
            triadSpace.enqueue(effects, owner: defender); triadSpace.cancelUnreleased(owner: defender)
        }
        if let attack = panguAttack, !blocked, interruptible {
            panguSpace.controls[defender].stunUntil = max(panguSpace.controls[defender].stunUntil, panguSpace.tick + attack.stunTicks)
            if attack.airHoldTicks > 0 && response.launchVelocityMillimetersPerTick > 0 {
                panguSpace.controls[defender].pendingAirHoldTicks = attack.airHoldTicks
            }
        }
        if !blocked, strike.knocksDown, interruptible, var state = panguStates[defender] {
            // A completed cast may still own scheduled follow-up wind blades.
            // Knockdown cancels those not yet released, even without a cast.
            state.cancelPendingDerivedAttacks(); panguStates[defender] = state
            panguSpace.cancelUnreleasedAttacks(owner: defender)
        }
        // Schedule a response; never teleport a fighter on the contact tick.
        // The next live tick after hit-stop consumes the first displacement.
        let acceptsMotion = interruptible && !triadSpace.controls[defender].rooted(at: triadSpace.tick)
        if acceptsMotion {
            if !blocked { cancelOrdinaryThrows(involving: defender) }
            impactMotions[defender] = motion
            fighters[defender].velocityY = response.launchVelocityMillimetersPerTick
        }
        let role = blocked ? "guard" : strike.knocksDown ? "knockdown" : "hit"
        if acceptsMotion, let clip = profiles[defender].clip(role: role) {
            begin(defender, clip: clip, role: role, reaction: true)
            if wasAirborne {
                // A source jump lives in pelvis/ground-lift samples, while an
                // external launch lives in Fighter.y. Switching to a reaction
                // must retain the world body baseline rather than dropping to
                // the floor before launching again. Grounded pose changes do
                // not acquire a new offset from differing stance heights.
                let offset = Int(((previousBodyHeight - sourceVerticalOffset(defender)) * 1000).rounded())
                fighters[defender].y = min(DuelImpactMotion.maximumHeightMillimeters, max(0, offset))
            }
            if role == "knockdown" { fighters[defender].knockdown = clip.ticks }
            if blocked { fighters[defender].guarding = true }
        }
        if let attack = panguAttack, !blocked, interruptible, attack.stunTicks > 0 {
            recordPanguControl(.stun, target: defender)
        }
        for control in contactControls { applyPanguControl(control, owner: i) }
        contacts.append(.init(kind: blocked ? .block : .hit, attacker: i, position: point,
                              direction: direction, heavy: heavy,
                              usesWeapon: triadAttack.map { $0.damageKind == .weapon } ?? panguAttack.map { $0.damageKind == .weapon } ?? !command.rawValue.hasPrefix("kick"),
                              authoredAudio: triadAttack != nil || panguAttack != nil))
        if panguStates[i] != nil {
            recordPanguPresentation(.contact(.init(owner: i, target: defender, attackID: panguAttack?.id,
                ability: panguAttack?.ability, delivery: panguAttack?.delivery, damageKind: kind,
                generated: panguAttack?.generated ?? false, empowered: panguAttack?.empowered ?? false,
                kind: blocked ? .block : .hit, position: point, direction: direction)))
        }
        if triadStates[i] != nil {
            recordTriadPresentation(.contact(.init(owner: i, target: defender, attackID: triadAttack?.id,
                ability: triadAttack?.ability, kind: blocked ? .block : .hit, position: point,
                direction: direction, critical: triadAttack?.critical ?? split?.critical ?? false)))
        }
        if blocked { events.append(.blocked(defender: defender)) }
        else { landedHits[i] += 1; damageDealt[i] += actualDamage; events.append(.hit(attacker: i, damage: actualDamage)) }
        hitStop = max(hitStop, blocked ? strike.blockedHitStopTicks : strike.hitStopTicks)
        for bonus in anchoredBonuses { applyPanguHit(bonus) }
    }
    private mutating func separate() {
        guard !ordinaryThrowStates.contains(where: { $0?.stage == .success || $0?.stage == .immune }),
              !sourceThrowStates.contains(where: { state in state.map { $0.owns(0) && $0.owns(1) } == true }) else { return }
        let distance = fighters[1].x - fighters[0].x
        guard abs(distance) < DuelGame.bodyWidth else { return }
        let sign = distance >= 0 ? 1 : -1, missing = DuelGame.bodyWidth - abs(distance)
        fighters[0].x = clamped(fighters[0].x - sign * ((missing + 1) / 2))
        fighters[1].x = clamped(fighters[1].x + sign * (missing / 2))
        let rest = DuelGame.bodyWidth - abs(fighters[1].x - fighters[0].x)
        if rest > 0 {
            if fighters[0].x == DuelGame.leftWall || fighters[0].x == DuelGame.rightWall { fighters[1].x = clamped(fighters[1].x + sign * rest) }
            else { fighters[0].x = clamped(fighters[0].x - sign * rest) }
        }
    }
    private func clamped(_ x: Int) -> Int { min(DuelGame.rightWall, max(DuelGame.leftWall, x)) }
    private mutating func botInput() -> DuelGame.Input {
        guard !ordinaryThrowOwns(1), ordinaryThrowKnockdownTicks[1] == 0 else { return .neutral }
        if triadStates[1]?.canContinueOnslaught == true { return .init(rangedHeld: true) }
        let distance = abs(fighters[0].x - fighters[1].x), toward = fighters[0].x > fighters[1].x ? 1 : -1
        let cadence = difficulty == .learning ? 45 : 22
        if let state = triadStates[1], frame % cadence == 0 {
            let candidates = DuelTriadRules.Ability.allCases.filter { ability in
                canUseTriad(ability, index: 1) &&
                    (state.rules.ability(ability)?.attack.map { distance <= $0.rangeMillimeters } ?? true)
            }
            if !candidates.isEmpty {
                random = random &* 6364136223846793005 &+ 1442695040888963407
                switch candidates[Int((random >> 32) % UInt64(candidates.count))] {
                case .branches: return .init(weaponCommand: .shadow)
                case .mistBlade: return .init(move: fighters[1].facing, weaponCommand: .shadow)
                case .dynast: return .init(move: -fighters[1].facing, weaponCommand: .shadow)
                case .herald: return .init(vertical: 1, weaponCommand: .shadow)
                case .legionary: return .init(vertical: -1, weaponCommand: .shadow)
                case .mistOnslaught: return .init(weaponCommand: .ranged)
                case .cryingDance: return .init(vertical: -1, weaponCommand: .ranged)
                }
            }
        }
        guard actions[1] == nil else { return .neutral }
        if let state = panguStates[1], frame % cadence == 0 {
            let candidates = DuelPanguRules.Ability.allCases.filter { ability in
                state.canUse(ability) && (ability == .typhoon || ability == .stormGate ||
                    distance <= (state.rules.ability(ability)?.rangeMillimeters ?? 0))
            }
            if !candidates.isEmpty {
                random = random &* 6364136223846793005 &+ 1442695040888963407
                switch candidates[Int((random >> 32) % UInt64(candidates.count))] {
                case .shard: return .init(move: fighters[1].facing, weaponCommand: .shadow)
                case .typhoon, .stormGate: return .init(move: -fighters[1].facing, weaponCommand: .shadow)
                case .splitter: return .init(vertical: 1, weaponCommand: .shadow)
                case .bones: return .init(vertical: -1, weaponCommand: .shadow)
                case .spear: return .init(weaponCommand: .ranged)
                case .heavenfall: return .init(weaponCommand: .shadow)
                }
            }
        }
        if distance > 1800 { return .init(move: toward) }
        guard frame % cadence == 0 else { return .init(guardHeld: true) }
        random = random &* 6364136223846793005 &+ 1442695040888963407
        let choices: [DuelWeaponCommand] = [.weapon, .weaponForward, .heavy, .kick, .weaponDown]
        return .init(weaponCommand: choices[Int((random >> 32) % UInt64(choices.count))])
    }
    private mutating func resolveRound() {
        if mode != .versus {
            if fighters.contains(where: { $0.health <= 0 }) { cancelAllOrdinaryThrows() }
            for i in 0..<2 where fighters[i].health <= 0 { fighters[i].health = maximumHealth(i) }
            return
        }
        guard fighters.contains(where: { $0.health <= 0 }) || remainingTicks <= 0 else { return }
        // Application match rule: a timeout compares the fraction of each
        // configured health bar that remains. This convention is not a claim
        // about the original game's timeout policy. Cross multiplication keeps
        // even a one-HP difference exact; bounded operands prevent overflow.
        let maxA = maximumHealth(0), maxB = maximumHealth(1)
        let a = Int64(min(maxA, max(0, fighters[0].health))) * Int64(maxB)
        let b = Int64(min(maxB, max(0, fighters[1].health))) * Int64(maxA)
        let winner: Int? = a == b ? nil : a > b ? 0 : 1
        if let winner { wins[winner] += 1 }
        events.append(.roundEnded(winner: winner)); cancelBufferedInputs(); hitStop = 0
        let airborne = fighters.indices.map { isAirborne($0) }
        cancelAllOrdinaryThrows()
        for i in 0..<2 {
            if var state = triadStates[i] {
                let effects = state.finishRound(won: winner == i, eventID: triadSpace.nextHitID())
                triadStates[i] = state; triadSpace.enqueue(effects, owner: i)
            }
        }
        consumeTriadEffects()
        triadSpace.resetRound()
        impactMotions = [nil, nil]
        panguSpace = DuelPanguSpatialState()
        for i in 0..<2 {
            if var state = panguStates[i] { _ = state.interrupt(force: true); panguStates[i] = state }
            if actions[i]?.role.hasPrefix("pangu") == true { actions[i] = nil; fighters[i].attack = nil }
            if actions[i]?.role.hasPrefix("triad") == true { actions[i] = nil; fighters[i].attack = nil }
            fighters[i].y = 0; fighters[i].velocityY = 0
            if airborne[i] || fighters[i].health <= 0 {
                // No simulation is advanced in a round break or after match
                // over. Commit a grounded terminal pose instead of freezing
                // a source jump or an external flight indefinitely in the air.
                // A grounded KO also needs its terminal down pose, including
                // a throw whose lethal marker is the landing/release sample.
                actions[i] = nil; fighters[i].attack = nil; fighters[i].guarding = false
                fighters[i].stun = 0; fighters[i].knockdown = 0
                if fighters[i].health <= 0, let down = profiles[i].clip(role: "knockdown") {
                    setPose(i, clip: down, tick: down.ticks, reaction: true)
                    fighters[i].knockdown = 1
                } else { setPose(i, role: "idle", tick: 0) }
            }
        }
        for i in 0..<2 where actions[i]?.command == .shadow {
            actions[i] = nil; fighters[i].attack = nil
        }
        sourceStances = [nil, nil]
        if let winner, hasSourceStance(winner) {
            let final = wins[winner] >= 2
            sourceStances[winner] = .init(finalVictory: final,
                originXMillimeters: Double(fighters[winner].x), direction: fighters[winner].facing)
            actions[winner] = nil; fighters[winner].attack = nil
            fighters[winner].guarding = false; fighters[winner].walking = false
            // This arena resolves/grounds the round before selecting the
            // recovered win pose. It does not reproduce the original game's
            // separate PHYSICS/LOSS/Uninterrupt transition-lock dispatcher.
            alignSourceStance(winner); sampleSourceStance(winner, restart: true)
            let end = sourceStances[winner]!.motion.endEventTick!
            phase = .roundBreak(winner: winner, remaining: max(final ? 0 : 150, end + 1))
        } else if let winner, wins[winner] >= 2 {
            phase = .matchOver(winner: winner)
            if let victory = profiles[winner].clip(role: "victory") { setPose(winner, clip: victory, tick: victory.ticks) }
        } else { phase = .roundBreak(winner: winner, remaining: 150) }
    }
    private mutating func resetRound() {
        panguPresentationEvents.removeAll(keepingCapacity: true)
        triadPresentationEvents.removeAll(keepingCapacity: true)
        sourceMotionSamples.removeAll(keepingCapacity: true)
        roundNumber += 1
        fighters = profiles.enumerated().map { .init(hero: $0.element.hero, x: $0.offset == 0 ? 3500 : 6500, facing: $0.offset == 0 ? 1 : -1) }
        actions = [nil, nil]; queued = [nil, nil]; shadowCooldowns = [0, 0]; loopTicks = [0, 0]; loopRoles = ["", ""]
        previousX = fighters.map(\.x); previousY = fighters.map(\.y)
        impactMotions = [nil, nil]; remainingTicks = 3600; hitStop = 0; phase = .fighting
        ordinaryThrowStates = [nil, nil]; ordinaryThrowKnockdownTicks = [0, 0]
        sourceThrowStates = [nil, nil]; sourceThrowDisabledTicks = [0, 0]
        sourceStances = [nil, nil]
        panguSpace = DuelPanguSpatialState()
        triadSpace.resetRound()
        for i in 0..<2 {
            panguStates[i]?.beginNextRound(seed: random &+ UInt64(i))
            if let state = panguStates[i] {
                fighters[i].health = state.rules.maximumHealth
                fighters[i].energy = state.light * 100 / state.rules.light.maximum
            }
            if var state = triadStates[i] {
                if hasSourceStance(i) {
                    sourceStances[i] = .init(round: roundNumber,
                        originXMillimeters: Double(fighters[i].x), direction: fighters[i].facing)
                } else {
                    triadSpace.enqueue(state.beginRound(roundID: roundNumber), owner: i)
                }
                triadStates[i] = state
                fighters[i].health = state.rules.maximumHealth
                fighters[i].energy = state.mist * 100 / state.rules.mist.maximum
            }
        }
        for i in 0..<2 {
            if sourceStances[i] != nil { alignSourceStance(i); sampleSourceStance(i, restart: true) }
            else { setPose(i, role: "idle", tick: 0) }
        }
        previousX = fighters.map(\.x)
        previousPoses = fighters.map(\.weaponPose); previousFacings = fighters.map(\.facing)
        previousHurtY = fighters.indices.map { hurtBox($0).minY }
        consumeTriadEffects()
    }
}

extension DuelWeaponFight {
    /// Source stances are a profile capability. Their original clips are
    /// already in the authenticated catalog, not replacement preview motions.
    public func hasSourceStance(_ index: Int) -> Bool {
        profiles.indices.contains(index) && DuelTriadStanceState.accepts(profiles[index])
    }
    public func sourceStance(_ index: Int) -> DuelTriadStanceState? {
        sourceStances.indices.contains(index) ? sourceStances[index] : nil
    }
    public var sourceIntroActive: Bool { sourceStances.contains { $0?.purpose.isIntro == true } }

    private mutating func releaseCompletedSourceIntros() {
        for i in sourceStances.indices where sourceStances[i]?.purpose.isIntro == true &&
            sourceStances[i]?.motion == .startIdle {
            sourceStances[i] = nil
        }
    }
    private mutating func advanceSourceIntro() {
        for i in sourceStances.indices {
            guard var stance = sourceStances[i], stance.purpose.isIntro else { continue }
            if stance.motion.isBirth {
                // Application RoundStart boundary: both participants' source
                // starts enter on this same authoritative tick. The original
                // PLAYER/NOT_PLAYER equipment-lock choice is not inferred.
                if var state = triadStates[i] {
                    triadSpace.enqueue(state.beginRound(roundID: roundNumber), owner: i)
                    triadStates[i] = state
                    fighters[i].energy = state.mist * 100 / state.rules.mist.maximum
                }
                stance.beginRound(); sourceStances[i] = stance
                alignSourceStance(i); sampleSourceStance(i, restart: true)
                recordTriadPresentation(.source(owner: i, event: .roundStarted(roundID: roundNumber)))
            } else { advanceSourceStance(i) }
        }
        consumeTriadEffects()
    }
    private mutating func advanceSourceVictoryStances() {
        for i in sourceStances.indices where sourceStances[i]?.purpose.isIntro == false {
            advanceSourceStance(i)
        }
    }
    private mutating func advanceSourceStance(_ index: Int) {
        guard var stance = sourceStances[index] else { return }
        let previous = stance
        if let transition = stance.advance() {
            sampleSourceStance(index, state: previous, tick: transition.finalTick)
            sourceStances[index] = stance
            alignSourceStance(index); sampleSourceStance(index, restart: true)
        } else {
            sourceStances[index] = stance; sampleSourceStance(index)
        }
    }
    private mutating func alignSourceStance(_ index: Int) {
        guard var stance = sourceStances[index],
              let clip = profiles[index].clip(named: stance.motion.clip),
              let pelvis = clip.tracks.pelvis else { return }
        var direction = fighters[index].facing
        if stance.motion.isBirth {
            let center = (DuelGame.leftWall + DuelGame.rightWall) / 2
            direction = center >= fighters[index].x ? 1 : -1
        } else if stance.motion.setsDirectionToEnemy,
                  let owner = sourcePelvis(index), let enemy = sourcePelvis(1 - index), enemy.x != owner.x {
            direction = enemy.x > owner.x ? 1 : -1
        }
        let pivot = clip.tracks.sample(stance.motion.alignToFoot ? clip.tracks.footL : pelvis, phase: 0)
        // Original Align is X-only, against this model's current Pivot. The
        // arena uses the existing actor .92 conversion (9.2 mm/source cm).
        // Source pelvis Y is already skinned; adding root.Y would double it.
        let aligned = Double(fighters[index].x) + Double(direction) *
            (Double(stance.motion.sourceShiftX) * 9.2 - pivot.x * 1000)
        stance.align(originXMillimeters: aligned, direction: direction)
        sourceStances[index] = stance; fighters[index].facing = direction
    }
    private mutating func sampleSourceStance(_ index: Int, state: DuelTriadStanceState? = nil,
                                            tick: Int? = nil, restart: Bool = false) {
        guard let stance = state ?? sourceStances[index],
              let clip = profiles[index].clip(named: stance.motion.clip) else { return }
        let at = tick ?? stance.tick
        let root = clip.tracks.sample(clip.tracks.root, phase: clip.phase(at: at)).x - clip.tracks.root[0].x
        fighters[index].x = clamped(Int((stance.originXMillimeters + root * 1000 * Double(stance.direction)).rounded()))
        fighters[index].walking = false; fighters[index].guarding = false; fighters[index].attack = nil
        setPose(index, clip: clip, tick: at, restart: restart)
    }
}

// Pangu integrates with the same authoritative fight, contacts, lifecycle and
// replay. Authenticated target profiles supply all numerical rules and clips.
extension DuelWeaponFight {
    public var panguPresentation: DuelPanguPresentation {
        guard case .fighting = phase else { return .empty(liveTick: panguSpace.tick) }
        guard panguStates.contains(where: { $0 != nil }) else { return .empty(liveTick: panguSpace.tick) }
        return .init(space: panguSpace, fighters: fighters,
                     hurts: fighters.indices.map { hurtBox($0) }, states: panguStates)
    }

    /// Internal feedback writer; callers cannot use this queue to apply an
    /// attack. Event keys consume no authoritative IDs and no random values.
    mutating func recordPanguPresentation(_ kind: DuelPanguPresentation.Event.Kind) {
        guard panguPresentationEvents.count < DuelPanguPresentation.maximumEventsPerStep else { return }
        panguPresentationEvents.append(.init(id: .init(frame: frame, sequence: panguPresentationEvents.count),
                                             liveTick: panguSpace.tick, kind: kind))
    }

    private mutating func spawnPanguAttack(_ attack: DuelPanguState.Attack, owner: Int, activeTicks: Int) {
        guard panguSpace.spawn(attack, owner: owner, fighter: fighters[owner], target: fighters[1 - owner],
            targetPelvis: attack.sourceStrike?.isWind == true ? sourcePelvis(1 - owner) : nil,
            activeTicks: activeTicks, frame: panguSpace.tick) else { return }
        if let volume = panguSpace.volumes.last {
            recordPanguPresentation(.attackReleased(DuelPanguPresentation.volume(volume, fighter: fighters[owner])))
        }
    }

    private mutating func recordPanguControl(_ kind: DuelPanguPresentation.Control.Kind, target: Int) {
        if let value = DuelPanguPresentation.controls(panguSpace.controls[target], target: target,
                hurt: hurtBox(target), liveTick: panguSpace.tick).first(where: { $0.kind == kind }) {
            recordPanguPresentation(.controlApplied(value))
        }
    }

    public func maximumHealth(_ index: Int) -> Int {
        panguState(index)?.rules.maximumHealth ?? triadState(index)?.rules.maximumHealth ?? 1000
    }
    public func panguState(_ index: Int) -> DuelPanguState? {
        panguStates.indices.contains(index) ? panguStates[index] : nil
    }
    public func canBeThrown(_ index: Int) -> Bool {
        fighters.indices.contains(index) && panguStates[index]?.throwImmune != true && triadStates[index]?.impactImmune != true
    }
    public func panguAbility(for input: DuelGame.Input, index: Int) -> DuelPanguRules.Ability? {
        guard panguStates.indices.contains(index), let state = panguStates[index] else { return nil }
        if input.weaponCommand == .ranged { return .spear }
        guard input.weaponCommand == .shadow else { return nil }
        if input.vertical > 0 { return .splitter }
        if input.vertical < 0 { return .bones }
        let facing = fighters[index].facing
        if input.move == facing { return .shard }
        if input.move == -facing {
            if state.rules.runtime != nil { return state.canUse(.stormGate) ? .stormGate : .typhoon }
            return state.rules.level >= 4 && state.typhoonRemainingTicks > 0 ? .stormGate : .typhoon
        }
        return .heavenfall
    }
    public func canUsePangu(_ ability: DuelPanguRules.Ability, index: Int) -> Bool {
        guard phase == .fighting, !sourceIntroActive,
              let state = panguState(index), state.canUse(ability), fighters[index].health > 0,
              !ordinaryThrowOwns(index), ordinaryThrowKnockdownTicks[index] == 0,
              !panguSpace.controls[index].locked(at: panguSpace.tick),
              !panguSpace.controls[index].airHeld(at: panguSpace.tick), !isAirborne(index) else { return false }
        return actions[index] == nil && !triadSpace.controls[index].locked(at: triadSpace.tick)
    }
    private mutating func startPangu(_ i: Int, ability: DuelPanguRules.Ability) {
        guard canUsePangu(ability, index: i), var state = panguStates[i],
              let clip = profiles[i].clip(role: ability.motionRole) else { return }
        let effects = state.start(ability)
        guard state.activeCast != nil else { return }
        panguStates[i] = state
        panguSpace.jumpEligible[i] = false
        begin(i, clip: clip, role: ability.motionRole)
        fighters[i].attack = .init(move: .skill2)
        panguSpace.enqueue(effects, owner: i)
        fighters[i].energy = state.light * 100 / state.rules.light.maximum
        if let cast = state.activeCast {
            recordPanguPresentation(.castStarted(DuelPanguPresentation.cast(cast, owner: i, fighter: fighters[i])))
        }
    }
    private mutating func updatePanguControl(_ i: Int) -> Bool {
        let control = panguSpace.controls[i], now = panguSpace.tick
        let immobilized = now > 0 && (control.petrifyUntil >= now || control.pinUntil >= now || control.airHeld(at: now))
        if immobilized {
            if control.airHeld(at: now) { fighters[i].y = control.airHeight }
            fighters[i].velocityY = 0; fighters[i].stun = 1
            fighters[i].guarding = false; fighters[i].attack = nil; queued[i] = nil
            return true
        }
        if control.stunUntil >= now && now > 0 {
            _ = advanceImpact(i)
            fighters[i].stun = control.stunUntil - now + 1
            fighters[i].guarding = false; fighters[i].attack = nil; queued[i] = nil
            if var action = actions[i], action.reaction, let clip = profiles[i].clip(named: action.name) {
                action.tick = min(clip.ticks, action.tick + 1); actions[i] = action
                setPose(i, clip: clip, tick: action.tick, reaction: true)
            }
            return true
        }
        if var lift = panguSpace.lifts[i] {
            let height = now > lift.phaseStartedTick ? lift.step() : lift.height
            panguSpace.lifts[i] = lift
            fighters[i].y = height; fighters[i].velocityY = 0
            if lift.fallingSpeed > 0 && height == 0 {
                panguSpace.lifts[i] = nil
                recordPanguPresentation(.landed(owner: i, position: .init(x: Double(fighters[i].x) / 1000, y: 0)))
                if let slam = panguSpace.deferredSlams[i] {
                    panguSpace.deferredSlams[i] = nil
                    spawnPanguAttack(slam, owner: i, activeTicks: 1)
                }
            }
        }
        if let cast = panguStates[i]?.activeCast,
           let clip = profiles[i].clip(role: cast.ability.motionRole) {
            let tick = min(clip.ticks, cast.tick * clip.ticks / max(1, cast.duration))
            setPose(i, clip: clip, tick: tick)
            fighters[i].attack = .init(move: .skill2, age: cast.tick)
            fighters[i].guarding = false; queued[i] = nil
            return true
        }
        if panguSpace.lifts[i] != nil { fighters[i].stun = 1; return true }
        if actions[i]?.role.hasPrefix("pangu") == true {
            actions[i] = nil; fighters[i].attack = nil; fighters[i].stun = 0
            setPose(i, role: "idle", tick: 0)
        }
        return false
    }
    private mutating func consumePanguEffects() {
        let effects = panguSpace.deferred
        panguSpace.deferred.removeAll(keepingCapacity: true)
        for envelope in effects {
            let i = envelope.owner, target = 1 - i
            switch envelope.effect {
            case .attack(let attack):
                if attack.sourceStrike == nil && attack.ability == .heavenfall && panguSpace.lifts[i] != nil {
                    if attack.generated {
                        // The second effect pass follows physical descent in
                        // this same tick. Keep landing wind at the same floor
                        // origin as the slam, rather than the previous height.
                        panguSpace.enqueue([.attack(attack)], owner: i)
                    } else { panguSpace.deferredSlams[i] = attack }
                } else {
                    let active = attack.sourceLifetimeTicks ?? attack.ability.flatMap { panguStates[i]?.rules.ability($0)?.activeTicks } ?? 1
                    spawnPanguAttack(attack, owner: i, activeTicks: active)
                }
            case .control(let control): applyPanguControl(control, owner: i)
            case .teleportBehind(let distance):
                let previousPosition = DuelWeaponPoint(x: Double(fighters[i].x) / 1000,
                                                      y: Double(fighters[i].y) / 1000)
                let destination = fighters[target].x - fighters[target].facing * max(DuelGame.bodyWidth, distance)
                let candidate = clamped(destination)
                // A wall can make the requested side unavailable. Do not place
                // two bodies on top of each other or create a cross-arena sweep.
                let canTeleport = abs(candidate - fighters[target].x) >= DuelGame.bodyWidth
                if canTeleport { fighters[i].x = candidate }
                fighters[i].facing = fighters[target].x >= fighters[i].x ? 1 : -1
                separate()
                for index in 0..<2 {
                    previousX[index] = fighters[index].x; previousY[index] = fighters[index].y
                    previousPoses[index] = fighters[index].weaponPose; previousFacings[index] = fighters[index].facing
                    previousHurtY[index] = hurtBox(index).minY
                    actions[index]?.requiresContactSeparation = true
                    actions[index]?.touchingStrikeIDs = []
                }
                let currentPosition = DuelWeaponPoint(x: Double(fighters[i].x) / 1000,
                                                     y: Double(fighters[i].y) / 1000)
                if canTeleport && currentPosition != previousPosition {
                    recordPanguPresentation(.teleported(owner: i, from: previousPosition, to: currentPosition))
                }
            case .pillarRise(let height, let duration):
                impactMotions[i] = nil
                panguSpace.lifts[i] = .init(startHeight: fighters[i].y, targetHeight: height,
                                           duration: max(1, duration), phaseStartedTick: panguSpace.tick, height: fighters[i].y)
                if let lift = panguSpace.lifts[i] {
                    recordPanguPresentation(.pillarStarted(DuelPanguPresentation.pillar(lift, owner: i, fighter: fighters[i])))
                }
            case .descend(let velocity):
                if panguSpace.lifts[i] == nil {
                    panguSpace.lifts[i] = .init(startHeight: fighters[i].y, targetHeight: fighters[i].y,
                                               duration: 1, phaseStartedTick: panguSpace.tick, height: fighters[i].y)
                }
                panguSpace.lifts[i]?.fallingSpeed = max(1, abs(velocity))
                panguSpace.lifts[i]?.phaseStartedTick = panguSpace.tick
                if let lift = panguSpace.lifts[i] {
                    recordPanguPresentation(.descentStarted(DuelPanguPresentation.pillar(lift, owner: i, fighter: fighters[i])))
                }
            case .castPhase(let ability, let phase):
                recordPanguPresentation(.castPhase(owner: i, ability: ability, phase: phase))
            case .castEnded(let ability):
                if panguSpace.lifts[i] == nil && actions[i]?.role.hasPrefix("pangu") == true {
                    actions[i] = nil; fighters[i].attack = nil
                    setPose(i, role: "idle", tick: 0)
                }
                recordPanguPresentation(.castEnded(owner: i, ability: ability, interrupted: false))
            case .castInterrupted(let ability):
                panguSpace.cancelMelee(owner: i)
                panguSpace.lifts[i] = nil
                if fighters[i].y > 0 && impactMotions[i] == nil {
                    impactMotions[i] = DuelImpactMotion(response: .init(distanceMillimeters: 0, durationTicks: 1,
                        launchVelocityMillimetersPerTick: 0, gravityMillimetersPerTickSquared: DuelGame.gravity), direction: 1)
                }
                recordPanguPresentation(.castEnded(owner: i, ability: ability, interrupted: true))
            }
        }
    }
    private mutating func applyPanguControl(_ control: DuelPanguState.Control, owner: Int) {
        let target = 1 - owner
        if control.kind == .petrify {
            if control.durationTicks == 0 {
                if panguSpace.controls[target].petrifySourceID == control.sourceID {
                    let wasActive = panguSpace.tick > 0 && panguSpace.controls[target].petrifyUntil >= panguSpace.tick
                    panguSpace.controls[target].petrifyUntil = 0
                    panguSpace.controls[target].petrifySourceID = 0
                    if wasActive { recordPanguPresentation(.controlReleased(target: target, kind: .petrify)) }
                }
                return
            }
            guard let rule = panguStates[owner]?.rules.ability(.heavenfall),
                  abs(fighters[target].x - fighters[owner].x) <= rule.rangeMillimeters,
                  fighters[target].invulnerable == 0 else { return }
        }
        let wasAirborne = isAirborne(target)
        if control.kind != .dread { panguSpace.jumpEligible[target] = false }
        let previousBodyHeight = Double(fighters[target].y) / 1000 + sourceVerticalOffset(target)
        if control.kind != .dread && control.durationTicks > 0 {
            guard panguStates[target]?.damageImmune != true else { return }
            guard triadStates[target]?.impactImmune != true else { return }
            if var state = triadStates[target] {
                let effects = state.interrupt(); triadStates[target] = state
                triadSpace.enqueue(effects, owner: target); triadSpace.cancelUnreleased(owner: target)
            }
            if var state = panguStates[target] {
                if let cast = state.activeCast {
                    guard state.rules.ability(cast.ability)?.interruptible == true else { return }
                }
                state.cancelPendingDerivedAttacks()
                let effects = state.interrupt(); panguStates[target] = state
                panguSpace.enqueue(effects, owner: target)
                panguSpace.cancelMelee(owner: target); panguSpace.lifts[target] = nil
            }
            cancelOrdinaryThrows(involving: target)
        }
        let until = panguSpace.tick + control.durationTicks
        switch control.kind {
        case .stun: panguSpace.controls[target].stunUntil = max(panguSpace.controls[target].stunUntil, until)
        case .petrify:
            panguSpace.controls[target].petrifyUntil = until
            panguSpace.controls[target].petrifySourceID = control.sourceID
        case .pinned: panguSpace.controls[target].pinUntil = max(panguSpace.controls[target].pinUntil, until)
        case .dread:
            panguSpace.controls[target].dreadUntil = until
            panguSpace.controls[target].damageTakenBonusBps = control.damageTakenBonusBps
            panguSpace.controls[target].outgoingReductionBps = control.outgoingReductionBps
            recordPanguControl(.dread, target: target)
            return
        }
        guard control.durationTicks > 0 else { return }
        fighters[target].guarding = false; fighters[target].attack = nil; queued[target] = nil
        if control.kind == .pinned || control.kind == .petrify {
            fighters[target].velocityY = 0
            impactMotions[target] = DuelImpactMotion(response: .init(distanceMillimeters: 0, durationTicks: 1,
                launchVelocityMillimetersPerTick: 0, gravityMillimetersPerTickSquared: DuelGame.gravity), direction: 1)
        }
        if let clip = profiles[target].clip(role: "hit") {
            begin(target, clip: clip, role: "hit", reaction: true)
            if wasAirborne {
                let y = Int(((previousBodyHeight - sourceVerticalOffset(target)) * 1000).rounded())
                fighters[target].y = min(DuelImpactMotion.maximumHeightMillimeters, max(0, y))
            }
        }
        switch control.kind {
        case .stun: recordPanguControl(.stun, target: target)
        case .petrify: recordPanguControl(.petrify, target: target)
        case .pinned: recordPanguControl(.pinned, target: target)
        case .dread: break
        }
    }
    private mutating func resolvePanguContacts() {
        let hits = panguSpace.contacts(frame: panguSpace.tick, fighters: fighters,
            hurts: fighters.indices.map { hurtBox($0) }, previousX: previousX, previousHurtY: previousHurtY)
        for hit in hits { applyPanguHit(hit) }
    }
    private mutating func applyPanguHit(_ hit: DuelPanguSpatialState.Hit) {
        let attack = hit.attack
        let blockedImpact = DuelImpactResponse(distanceMillimeters: attack.impact.distanceMillimeters,
            durationTicks: attack.impact.durationTicks, launchVelocityMillimetersPerTick: 0,
            gravityMillimetersPerTickSquared: attack.impact.gravityMillimetersPerTickSquared)
        let strike = DuelCombatStrike(id: 0, startTick: 1, endTick: 1, weaponSides: [],
            damage: attack.damage, blockedDamage: attack.blockedDamage, knocksDown: attack.knocksDown,
            hitStopTicks: attack.hitStopTicks, blockedHitStopTicks: attack.blockedHitStopTicks,
            impact: attack.impact, blockedImpact: blockedImpact)
        applyHit(hit.owner, point: hit.point, command: .shadow, strike: strike,
                 blocked: hit.blocked, direction: hit.direction, panguAttack: attack)
    }
}

// DFT uses its own mist, souls and source roles in the same fight. It never
// reaches the legacy katana shadow-dash interpreter.
extension DuelWeaponFight {
    static func triadFaction(_ name: String) -> DuelTriadRules.Faction {
        let value = name.lowercased()
        if value.contains("legion") { return .legion }
        if value.contains("dynast") { return .dynasty }
        if value.contains("herald") { return .herald }
        return .unknown
    }
    public func triadState(_ index: Int) -> DuelTriadState? {
        triadStates.indices.contains(index) ? triadStates[index] : nil
    }
    public var triadPresentation: DuelTriadPresentation {
        guard phase == .fighting, triadStates.contains(where: { $0 != nil }) else {
            return .empty(liveTick: sourcePresentationTick)
        }
        return .init(space: triadSpace, hurts: fighters.indices.map { hurtBox($0) }, states: triadStates,
                     presentationTick: sourcePresentationTick)
    }
    private mutating func recordTriadPresentation(_ kind: DuelTriadPresentation.Event.Kind) {
        guard triadPresentationEvents.count < DuelTriadPresentation.maximumEventsPerStep else { return }
        let source: DuelTriadPresentation.Summon?
        if case .source(let owner, let event) = kind {
            let id: UInt64?
            switch event {
            case .soulModelCreated(let value, _), .soulAnimationEnded(let value, _): id = value
            default: id = nil
            }
            source = id.flatMap { value in
                triadSpace.summons.first(where: { $0.owner == owner && $0.id == value })
            }.map { DuelTriadPresentation.summon($0, liveTick: triadSpace.tick) }
        } else { source = nil }
        triadPresentationEvents.append(.init(id: .init(frame: frame, sequence: triadPresentationEvents.count),
            liveTick: sourcePresentationTick, kind: kind, sourceSummon: source))
    }
    private mutating func recordTriadSourceTimeline() {
        if roundNumber == 1 && triadSpace.tick == 1 {
            for i in triadStates.indices where triadStates[i]?.rules.runtime != nil &&
                (triadStates[i]?.rules.level ?? 0) >= 2 && !hasSourceStance(i) {
                recordTriadPresentation(.source(owner: i, event: .arenaForestLoopStarted(roundID: roundNumber)))
            }
        }
        // Inspect the old motion before this tick's state changes. In
        // particular, Ninjato Active_Start ends on the same tick that the
        // source trigger replaces it with Active_End.
        for summon in triadSpace.summons {
            guard let move = summon.sourceMove else { continue }
            let end = summon.sourceAnimation?.endEventTick ?? move.endEventTick
            if triadSpace.tick - summon.motionBeganAt == end {
                recordTriadPresentation(.source(owner: summon.owner, event:
                    .soulAnimationEnded(id: summon.id, role: summon.sourceAnimation?.role ?? move.role)))
            }
        }
    }
    public func triadAbility(for input: DuelGame.Input, index: Int) -> DuelTriadRules.Ability? {
        guard triadState(index) != nil else { return nil }
        if input.weaponCommand == .ranged { return input.vertical < 0 ? .cryingDance : .mistOnslaught }
        guard input.weaponCommand == .shadow else { return nil }
        if input.vertical > 0 { return .herald }
        if input.vertical < 0 { return .legionary }
        if input.move == fighters[index].facing { return .mistBlade }
        if input.move == -fighters[index].facing { return .dynast }
        return .branches
    }
    public func canUseTriad(_ ability: DuelTriadRules.Ability, index: Int) -> Bool {
        guard phase == .fighting, !sourceIntroActive,
              let state = triadState(index), state.canUse(ability), fighters[index].health > 0,
              !ordinaryThrowOwns(index), ordinaryThrowKnockdownTicks[index] == 0,
              !panguSpace.controls[index].locked(at: panguSpace.tick),
              !panguSpace.controls[index].airHeld(at: panguSpace.tick),
              !triadSpace.controls[index].locked(at: triadSpace.tick) else { return false }
        if ability.soul != nil { return true }
        return actions[index] == nil && !isAirborne(index)
    }
    private mutating func startTriad(_ i: Int, ability: DuelTriadRules.Ability) {
        guard canUseTriad(ability, index: i), var state = triadStates[i] else { return }
        configureTriadSummonSpace(&state, owner: i)
        if ability.soul != nil {
            let effects = state.start(ability)
            triadStates[i] = state; triadSpace.enqueue(effects, owner: i)
            for effect in effects {
                if case .soulAppeared(let soul, let origin, let id) = effect {
                    anchorTriadSoul(soul, origin: origin, id: id, owner: i)
                } else if case .sourceSoulAppeared(let appearance) = effect {
                    triadSpace.appear(appearance, owner: i, fighters: fighters)
                }
            }
            fighters[i].energy = state.mist * 100 / state.rules.mist.maximum
            return
        }
        guard let clip = profiles[i].clip(role: ability.motionRole) else { return }
        let effects = state.start(ability)
        guard let cast = state.activeCast else { return }
        triadStates[i] = state; triadSpace.enqueue(effects, owner: i)
        begin(i, clip: clip, role: ability.motionRole)
        fighters[i].attack = .init(move: .skill2)
        fighters[i].energy = state.mist * 100 / state.rules.mist.maximum
        recordTriadPresentation(.castStarted(owner: i, cast: cast))
    }
    private mutating func updateTriadControl(_ i: Int) -> Bool {
        let control = triadSpace.controls[i], now = triadSpace.tick
        if control.locked(at: now) {
            if !control.rooted(at: now) { _ = advanceImpact(i) }
            fighters[i].velocityY = 0; fighters[i].stun = 1
            fighters[i].guarding = false; fighters[i].attack = nil; queued[i] = nil
            return true
        }
        if let motion = triadStates[i]?.ownerMotion, let clip = profiles[i].clip(role: motion.role) {
            let oldAction = actions[i]
            let hasPhysical = profiles[i].combatRules?.rule(command: .weapon, clipName: clip.name) != nil
            if oldAction?.name != clip.name || oldAction?.command != (hasPhysical ? .weapon : nil) ||
                (oldAction?.tick ?? -1) > motion.tick {
                begin(i, clip: clip, role: motion.role, command: hasPhysical ? .weapon : nil, tick: motion.tick)
                // Upgraded wave clips share the same source timeline. Keep
                // their hit IDs and contact latches when continuing in place.
                if motion.tick > 0, let oldAction, oldAction.role.hasPrefix("triadMistOnslaught") {
                    actions[i]?.landedStrikeIDs = oldAction.landedStrikeIDs
                    actions[i]?.touchingStrikeIDs = oldAction.touchingStrikeIDs
                    actions[i]?.touching = oldAction.touching
                }
            }
            actions[i]?.tick = motion.tick
            setPose(i, clip: clip, tick: min(clip.ticks, motion.tick))
            fighters[i].attack = .init(move: .skill2, age: motion.tick)
            fighters[i].guarding = false; queued[i] = nil
            return true
        }
        if let cast = triadStates[i]?.activeCast,
           let clip = profiles[i].clip(role: cast.ability.motionRole) {
            let tick = min(clip.ticks, cast.tick * clip.ticks / max(1, cast.duration))
            setPose(i, clip: clip, tick: tick)
            fighters[i].attack = .init(move: .skill2, age: cast.tick)
            fighters[i].guarding = false; queued[i] = nil
            return true
        }
        if triadStates[i]?.movementLocked == true {
            fighters[i].guarding = false; fighters[i].walking = false
            fighters[i].attack = nil; queued[i] = nil
            let loopRole = profiles[i].clip(role: "triadBranchesHold") != nil ? "triadBranchesHold" : "idle"
            loop(i, role: loopRole)
            return true
        }
        if actions[i]?.role.hasPrefix("triad") == true {
            actions[i] = nil; fighters[i].attack = nil; fighters[i].stun = 0
            setPose(i, role: "idle", tick: 0)
        }
        if actions[i] == nil && ordinaryThrowKnockdownTicks[i] == 0 { fighters[i].stun = 0 }
        return false
    }
    private mutating func consumeTriadEffects() {
        let effects = triadSpace.deferred
        triadSpace.deferred.removeAll(keepingCapacity: true)
        for envelope in effects {
            let i = envelope.owner, target = 1 - i
            switch envelope.effect {
            case .soulAppeared(let soul, let origin, let id):
                anchorTriadSoul(soul, origin: origin, id: id, owner: i)
            case .sourceSoulAppeared(let appearance):
                triadSpace.appear(appearance, owner: i, fighters: fighters)
                if triadSpace.summons.contains(where: { $0.id == appearance.summonID && $0.owner == i }) {
                    recordTriadPresentation(.source(owner: i, event:
                        .soulModelCreated(id: appearance.summonID, move: appearance.move)))
                }
            case .sourceSoulMotion(let id, let animation):
                triadSpace.changeMotion(id: id, owner: i, animation: animation, profile: profiles[i])
            case .sourceRootModelEnded(let id):
                recordTriadPresentation(.source(owner: i, event: .rootModelEnded(id: id)))
            case .attack(let attack):
                if let volume = triadSpace.spawn(attack, owner: i, fighters: fighters, profile: profiles[i]) {
                    let kind: DuelTriadPresentation.SourceEvent.ModelKind?
                    if triadStates[i]?.rules.runtime == nil { kind = nil }
                    else if attack.delivery == .roots { kind = .roots }
                    else if attack.delivery == .mistWave { kind = .mistWave }
                    else if attack.summonMove == .danceBlast && attack.summonStage == .primary { kind = .heraldBlast }
                    else { kind = nil }
                    recordTriadPresentation(.attackReleased(.init(owner: i, attackID: attack.id,
                        ability: attack.ability, origin: attack.origin, delivery: attack.delivery,
                        bounds: volume.bounds, direction: volume.direction,
                        remainingTicks: max(0, volume.expiresAt - triadSpace.tick),
                        sourceModelKind: kind,
                        sourceOrigin: kind.map { _ in .init(x: Double(volume.originX) / 1000, y: Double(volume.originY) / 1000) })))
                    if triadStates[i]?.rules.runtime != nil {
                        if let kind {
                            recordTriadPresentation(.source(owner: i, event:
                                .modelCreated(id: attack.id, kind: kind, origin: attack.origin)))
                        }
                    }
                }
            case .forestStarted(let round):
                if triadStates[i]?.rules.runtime != nil && round > 1 && !hasSourceStance(i) {
                    recordTriadPresentation(.source(owner: i, event: .roundStarted(roundID: round)))
                }
            case .forestEnded:
                if triadStates[i]?.rules.runtime != nil {
                    recordTriadPresentation(.source(owner: i, event: .roundFightEnded))
                }
            case .control(let control): applyTriadControl(control, owner: i)
            case .controlReleased(let sourceID, let kind):
                if kind == .root, triadSpace.controls[target].rootSourceID == sourceID,
                   triadSpace.controls[target].rootOwner == i {
                    triadSpace.controls[target].rootUntil = 0
                    triadSpace.controls[target].rootSourceID = 0
                    triadSpace.controls[target].rootOwner = nil
                    fighters[target].stun = 0
                }
            case .damagePulse(let pulse):
                let actual = receiveTargetDamage(pulse.damage, kind: pulse.damageKind, attacker: i,
                    blocked: false, canKill: pulse.canKill, status: true)
                if actual > 0 { damageDealt[i] += actual; events.append(.hit(attacker: i, damage: actual)) }
            case .castEnded:
                if actions[i]?.role.hasPrefix("triad") == true {
                    actions[i] = nil; fighters[i].attack = nil; setPose(i, role: "idle", tick: 0)
                }
            case .castInterrupted:
                triadSpace.cancelUnreleased(owner: i)
                if actions[i]?.role.hasPrefix("triad") == true { actions[i] = nil; fighters[i].attack = nil }
            default: break
            }
            recordTriadPresentation(.effect(owner: i, effect: envelope.effect))
        }
    }
    private mutating func anchorTriadSoul(_ soul: DuelTriadRules.Soul, origin: DuelTriadState.Origin,
                                         id: UInt64, owner: Int) {
        if let ability = DuelTriadRules.Ability(rawValue: soul.rawValue),
           let rule = triadStates[owner]?.rules.ability(ability) {
            triadSpace.appear(soul, origin: origin, id: id, owner: owner,
                fighter: fighters[owner], duration: rule.duration)
        }
    }
    private func configureTriadSummonSpace(_ state: inout DuelTriadState, owner: Int) {
        guard state.rules.runtime != nil else { return }
        let target = fighters[1 - owner], toward = target.x >= fighters[owner].x ? 1 : -1
        let left = max(0, target.x - DuelGame.leftWall), right = max(0, DuelGame.rightWall - target.x)
        // Ceil retains the source's strict >150/>250/>350 boundary after
        // converting integer arena millimeters through the 0.92 model scale.
        func sourceRoom(_ mm: Int) -> Int { (mm * 10 + 91) / 92 }
        state.configureSummonSpace(opponentFrontRoomSourceUnits: sourceRoom(toward > 0 ? left : right),
            opponentBackRoomSourceUnits: sourceRoom(toward > 0 ? right : left))
    }
    private mutating func applyTriadControl(_ control: DuelTriadState.Control, owner: Int) {
        let target = 1 - owner
        guard control.durationTicks > 0, panguStates[target]?.damageImmune != true,
              triadStates[target]?.impactImmune != true else { return }
        if var state = panguStates[target] {
            if let cast = state.activeCast, state.rules.ability(cast.ability)?.interruptible != true { return }
            state.cancelPendingDerivedAttacks()
            let effects = state.interrupt(); panguStates[target] = state
            panguSpace.enqueue(effects, owner: target); panguSpace.cancelMelee(owner: target)
            panguSpace.lifts[target] = nil
        }
        if var state = triadStates[target] {
            let effects = state.interrupt(); triadStates[target] = state
            triadSpace.enqueue(effects, owner: target); triadSpace.cancelUnreleased(owner: target)
        }
        cancelOrdinaryThrows(involving: target)
        queued[target] = nil; actions[target] = nil; fighters[target].attack = nil
        fighters[target].guarding = false; fighters[target].stun = control.durationTicks
        if control.kind == .root {
            triadSpace.controls[target].rootUntil = triadSpace.tick + control.durationTicks
            triadSpace.controls[target].rootSourceID = control.sourceID
            triadSpace.controls[target].rootOwner = owner
            impactMotions[target] = nil; fighters[target].velocityY = 0
        } else { triadSpace.controls[target].stunUntil = max(triadSpace.controls[target].stunUntil, triadSpace.tick + control.durationTicks) }
        if let clip = profiles[target].clip(role: "hit") { setPose(target, clip: clip, tick: 0, reaction: true) }
    }
    private mutating func resolveTriadContacts() {
        let hits = triadSpace.contacts(fighters: fighters, profiles: profiles, hurts: fighters.indices.map { hurtBox($0) },
            previousX: previousX, previousHurtY: previousHurtY,
            hurtBefore: fighters.indices.map { sourceHurtCapsules($0, previous: true) },
            hurtAfter: fighters.indices.map { sourceHurtCapsules($0) })
        for hit in hits {
            let target = 1 - hit.owner
            guard panguStates[target]?.damageImmune != true, var state = triadStates[hit.owner] else { continue }
            let unbreakable = panguStates[target]?.activeCast.flatMap {
                panguStates[target]?.rules.ability($0.ability)?.interruptible
            } == false || triadStates[target]?.impactImmune == true
            let receipt = state.contact(attackID: hit.attack.id,
                context: .init(blocked: hit.blocked, airborne: isAirborne(target),
                    rolling: actions[target]?.role == "roll", shadowDamageUnbreakable: unbreakable,
                    rootImmune: unbreakable), eventID: triadSpace.nextHitID())
            triadStates[hit.owner] = state
            guard receipt.accepted else { continue }
            // Intangible suppression waves and a root capture cannot invent a
            // normal hit reaction, push, hit-stop or damage component.
            if receipt.damage > 0 {
                let attack = hit.attack
                let blockedImpact = DuelImpactResponse(distanceMillimeters: attack.impact.distanceMillimeters,
                    durationTicks: attack.impact.durationTicks,
                    gravityMillimetersPerTickSquared: attack.impact.gravityMillimetersPerTickSquared)
                let strike = DuelCombatStrike(id: 0, startTick: 1, endTick: 1, weaponSides: [],
                    damage: receipt.damage, blockedDamage: receipt.damage, knocksDown: attack.knocksDown,
                    hitStopTicks: attack.hitStopTicks, blockedHitStopTicks: attack.blockedHitStopTicks,
                    impact: attack.impact, blockedImpact: blockedImpact)
                applyHit(hit.owner, point: hit.point, command: .shadow, strike: strike,
                    blocked: receipt.blocked, direction: hit.direction, triadAttack: attack)
                if !receipt.blocked, !unbreakable, attack.stunTicks > 0 {
                    applyTriadControl(.init(sourceID: attack.id, kind: .stun, durationTicks: attack.stunTicks), owner: hit.owner)
                }
            } else {
                recordTriadPresentation(.contact(.init(owner: hit.owner, target: target,
                    attackID: hit.attack.id, ability: hit.attack.ability,
                    kind: receipt.blocked ? .block : .hit, position: hit.point,
                    direction: hit.direction, critical: receipt.critical)))
            }
            // Accepted root/suppression takes effect on the actual contact tick.
            // Spawned secondary souls wait for the following spatial pass.
            for effect in receipt.effects {
                if case .control(let control) = effect { applyTriadControl(control, owner: hit.owner) }
                else { triadSpace.enqueue([effect], owner: hit.owner) }
            }
        }
    }
    /// Shared damage ordering for physical, split Mist Blade, soul and periodic
    /// hits. Source status writes bypass ordinary PreHit/defence multipliers;
    /// the source Light pool still receives the resulting HP write. Nonlethal
    /// pulses clamp the final health loss to one HP.
    private mutating func receiveTargetDamage(_ amount: Int, kind: DuelTriadRules.DamageKind,
        attacker: Int, blocked: Bool, canKill: Bool = true, status: Bool = false) -> Int {
        let target = 1 - attacker
        guard amount > 0, amount <= 1_000_000_000, panguStates[target]?.damageImmune != true else { return 0 }
        var damage = amount
        if kind != .trueDamage && !status {
            damage = triadStates[target]?.opponentOutgoingDamage(damage, kind: kind) ?? damage
            if kind == .shadow, let state = triadStates[attacker] {
                // The application's percentage defence model is explicit;
                // source stat substitutions remain in the bound rule profile.
                let divisor = max(1, 10_000 - state.opponentShadowDefenseReductionBps)
                damage = Int(min(1_000_000_000, Int64(damage) * 10_000 / Int64(divisor)))
            }
            damage = min(1_000_000_000, damage * panguSpace.controls[attacker].outgoingMultiplier(at: panguSpace.tick) / 10_000)
            damage = min(1_000_000_000, damage * panguSpace.controls[target].takenMultiplier(at: panguSpace.tick) / 10_000)
            if !status, var state = panguStates[target], let panguKind = DuelPanguRules.DamageKind(rawValue: kind.rawValue) {
                let receipt = state.receiveDamage(damage, kind: panguKind, blocked: blocked)
                panguStates[target] = state
                guard receipt.accepted else { return 0 }
                damage = receipt.healthDamage
            }
        }
        if status, var state = panguStates[target], kind != .trueDamage || state.rules.runtime != nil {
            let receipt = state.receiveStatusDamage(damage); panguStates[target] = state
            guard receipt.accepted else { return 0 }; damage = receipt.healthDamage
        }
        let actual = min(damage, max(0, fighters[target].health - (canKill ? 0 : 1)))
        fighters[target].health -= actual
        return actual
    }
}

// Ordinary throws share the equipped simulation. These are explicit source
// bindings, not the laboratory's unrelated three-second ultimate grapple.
extension DuelWeaponFight {
    public func sourceThrow(_ index: Int) -> DuelSourceThrowState? {
        guard fighters.indices.contains(index) else { return nil }
        return sourceThrowStates.compactMap { $0 }.first { $0.owns(index) }
    }

    public func sourceThrowDisabledRemaining(_ index: Int) -> Int {
        fighters.indices.contains(index) ? sourceThrowDisabledTicks[index] : 0
    }

    /// The source mass-weighted FK centre, including the actor's current pose.
    /// Older catalogs without this track keep their explicit origin adapter;
    /// a source throw profile requires all of its clips to carry COM samples.
    public func sourceCenterOfMass(_ index: Int) -> DuelWeaponPoint? {
        guard fighters.indices.contains(index) else { return nil }
        let pose = fighters[index].weaponPose
        let clip = pose.flatMap { profiles[index].clip(named: $0.clip) } ?? profiles[index].clip(role: "idle")
        guard let clip, let points = clip.tracks.centerOfMass else { return nil }
        let local = clip.tracks.sample(points, phase: pose?.phase ?? 0)
        let f = fighters[index], facing = Double(f.facing)
        return .init(x: Double(f.x) / 1000 + local.x * facing,
            y: Double(f.y) / 1000 + local.y + (pose?.groundLift ?? 0), z: local.z * facing)
    }

    /// Authored node origin in arena metres. Horizontal source displacement
    /// already moves Fighter.x; only the local FK point and current ground
    /// lift belong here. Missing data stays nil instead of substituting COM.
    public func sourcePelvis(_ index: Int) -> DuelWeaponPoint? {
        guard fighters.indices.contains(index) else { return nil }
        let pose = fighters[index].weaponPose
        let clip = pose.flatMap { profiles[index].clip(named: $0.clip) } ?? profiles[index].clip(role: "idle")
        guard let clip, let points = clip.tracks.pelvis else { return nil }
        let local = clip.tracks.sample(points, phase: pose?.phase ?? 0)
        let f = fighters[index], facing = Double(f.facing)
        return .init(x: Double(f.x) / 1000 + local.x * facing,
            y: Double(f.y) / 1000 + local.y + (pose?.groundLift ?? 0), z: local.z * facing)
    }

    private func sourceThrowCandidate(_ index: Int, command: DuelWeaponCommand) -> DuelSourceThrowState? {
        let target = 1 - index
        guard let rules = profiles[index].ordinaryThrows?.source,
              let targetRules = profiles[target].ordinaryThrows?.source,
              command == .weaponForward || command == .weaponBack,
              sourceThrowDisabledTicks[index] == 0, !ordinaryThrowOwns(index), !ordinaryThrowOwns(target),
              actions[index] == nil, actions[target] == nil,
              panguStates[index]?.activeCast == nil, panguStates[target]?.activeCast == nil,
              triadStates[index]?.activeCast == nil, triadStates[target]?.activeCast == nil,
              throwGrounded(index), throwGrounded(target),
              fighters[index].health > 0, fighters[target].health > 0,
              fighters[index].stun == 0, fighters[target].stun == 0,
              fighters[index].knockdown == 0, fighters[target].knockdown == 0,
              fighters[target].invulnerable == 0,
              ordinaryThrowKnockdownTicks[index] == 0, ordinaryThrowKnockdownTicks[target] == 0,
              impactMotions[index] == nil, impactMotions[target] == nil,
              !panguSpace.controls[index].locked(at: panguSpace.tick),
              !panguSpace.controls[target].locked(at: panguSpace.tick),
              !triadSpace.controls[index].locked(at: triadSpace.tick),
              !triadSpace.controls[target].locked(at: triadSpace.tick),
              panguSpace.lifts[index] == nil, panguSpace.lifts[target] == nil else { return nil }
        let targetD19 = profiles[target].isPangu && panguStates[target]?.rules.runtime != nil
        guard canBeThrown(target) || targetD19 else { return nil }
        guard let ownCOM = sourceCenterOfMass(index), let enemyCOM = sourceCenterOfMass(target) else { return nil }
        let ownX = ownCOM.x * 1000, targetX = enemyCOM.x * 1000
        let distance = abs(targetX - ownX)
        guard rules.inRange(distanceMillimeters: distance) else { return nil }
        let facing = fighters[target].x >= fighters[index].x ? 1 : -1
        let frontWall = facing > 0 ? DuelGame.rightWall : DuelGame.leftWall
        let backWall = facing > 0 ? DuelGame.leftWall : DuelGame.rightWall
        guard let variant = rules.variant(command: command,
            targetToFrontWallMillimeters: abs(Double(frontWall) - targetX),
            initiatorToBackWallMillimeters: abs(Double(backWall) - ownX), targetHasD19Rules: targetD19) else { return nil }
        let counterPower = panguStates[target]?.rules.runtime?.normalizedUnarmedPower ??
            profiles[target].ordinaryThrows?.source?.normalizedUnarmedPower ?? rules.normalizedUnarmedPower
        return DuelSourceThrowState(rules: rules, variant: variant, initiator: index, target: target,
            facing: facing, initiatorX: fighters[index].x, counterUnarmedPower: counterPower,
            targetRules: targetRules)
    }

    /// Source simultaneous flags are collected from the same input snapshot.
    /// The original Random(1,99) includes its upper endpoint, then stores
    /// 99-roll on the other model. The arena supplies its deterministic RNG.
    private mutating func resolveSourceThrowInputs(_ inputs: [DuelGame.Input]) {
        // Ordinary input may leave a source animation at its real Uninterrupt
        // boundary, before the later AnimationEnd notification.
        for owner in 0..<2 {
            guard var state = sourceThrowStates[owner] else { continue }
            for index in 0..<2 where inputs[index].weaponCommand != nil && state.canInterrupt(index) {
                state.release(index)
                releaseSourceThrowActor(index, received: false)
            }
            sourceThrowStates[owner] = state.isFinished ? nil : state
        }
        let candidates = (0..<2).compactMap { index -> DuelSourceThrowState? in
            guard let command = inputs[index].weaponCommand else { return nil }
            return sourceThrowCandidate(index, command: command)
        }
        guard !candidates.isEmpty else { return }
        let state: DuelSourceThrowState
        if candidates.count == 2 {
            random = random &* 6364136223846793005 &+ 1442695040888963407
            let roll = Int((random >> 32) % 99) + 1
            state = candidates[roll >= 50 ? 0 : 1]
        } else { state = candidates[0] }
        for index in [state.initiator, state.target] {
            actions[index] = nil; queued[index] = nil; impactMotions[index] = nil
            fighters[index].attack = nil; fighters[index].guarding = false
            fighters[index].walking = false; fighters[index].movementDirection = 0
            fighters[index].velocityY = 0; fighters[index].stun = 0; fighters[index].knockdown = 0
            panguSpace.jumpEligible[index] = false; panguSpace.speedRemainders[index] = 0
        }
        sourceThrowStates[state.initiator] = state
        applySourceThrowSamples(state.samples)
        let attacking = state.variant == .panguEscape ? state.target : state.initiator
        if var pangu = panguStates[attacking] {
            let effects = pangu.attackStarted(heavy: false, eventID: panguSpace.nextHitID())
            panguStates[attacking] = pangu; panguSpace.enqueue(effects, owner: attacking)
        }
        if state.variant == .panguEscape {
            recordPanguPresentation(.ordinaryThrowEscaped(attacker: state.initiator, target: state.target,
                position: .init(x: Double(fighters[state.target].x) / 1000, y: 1)))
        }
    }

    private mutating func prepareSourceThrowSamples() {
        for state in sourceThrowStates.compactMap({ $0 }) { applySourceThrowSamples(state.nextSamples) }
    }

    private mutating func applySourceThrowSamples(_ samples: [DuelSourceThrowState.ActorSample]) {
        guard let low = samples.map(\.xMillimeters).min(), let high = samples.map(\.xMillimeters).max() else { return }
        let shift = low < DuelGame.leftWall ? DuelGame.leftWall - low : high > DuelGame.rightWall ? DuelGame.rightWall - high : 0
        for sample in samples {
            let index = sample.fighter
            guard let clip = profiles[index].clip(role: sample.role) else { continue }
            fighters[index].x = sample.xMillimeters + shift
            fighters[index].y = 0; fighters[index].velocityY = 0; fighters[index].facing = sample.facing
            fighters[index].guarding = false; fighters[index].walking = false
            fighters[index].movementDirection = 0; fighters[index].attack = nil
            setPose(index, clip: clip, tick: sample.tick, reaction: true, restart: sample.tick == 0)
        }
    }

    private mutating func resolveSourceThrows(advancing: [Int?]) {
        for owner in 0..<2 {
            guard let previousTick = advancing[owner], var state = sourceThrowStates[owner],
                  state.tick == previousTick else { continue }
            if fighters[state.initiator].health <= 0 || fighters[state.target].health <= 0 {
                cancelSourceThrow(owner: owner); continue
            }
            let result = state.advance()
            sourceThrowStates[owner] = state
            if let damage = result.damage { applySourceThrowDamage(damage) }
            if let disabled = result.disabledThrowOwner {
                sourceThrowDisabledTicks[disabled] = state.rules.throwDisabledAfterVictimEndTicks
            }
            for index in result.released {
                releaseSourceThrowActor(index, received: state.variant != .panguEscape && index == state.target)
            }
            if state.isFinished { sourceThrowStates[owner] = nil }
        }
    }

    private mutating func applySourceThrowDamage(_ marker: DuelSourceThrowState.Damage) {
        let index = marker.attacker, target = marker.target
        guard fighters[index].health > 0, fighters[target].health > 0 else { return }
        var damage = marker.amount
        let contactID = panguStates[index] == nil ? nil : panguSpace.nextHitID()
        if var pangu = panguStates[index], let contactID {
            pangu.prepareOrdinaryContact(blocked: false, kind: .unarmed, hitID: contactID)
            damage = pangu.outgoingDamage(damage, kind: .unarmed)
            panguStates[index] = pangu
        }
        let actual = receiveTargetDamage(damage, kind: .unarmed, attacker: index, blocked: false)
        if var pangu = panguStates[index], let contactID {
            let effects = pangu.contact(blocked: false, generated: false, hitID: contactID, heavy: false, kind: .unarmed)
            panguStates[index] = pangu; panguSpace.enqueue(effects, owner: index)
        }
        if var triad = triadStates[index] {
            let effects = triad.ordinaryContact(blocked: false, eventID: triadSpace.nextHitID())
            triadStates[index] = triad; triadSpace.enqueue(effects, owner: index)
        }
        let point = DuelWeaponPoint(x: Double(fighters[target].x) / 1000, y: 0.4)
        contacts.append(.init(kind: .hit, attacker: index, position: point, direction: fighters[index].facing,
                              heavy: false, usesWeapon: false))
        if panguStates[index] != nil {
            recordPanguPresentation(.contact(.init(owner: index, target: target, attackID: nil, ability: nil,
                delivery: nil, damageKind: .unarmed, generated: false, empowered: false, kind: .hit,
                position: point, direction: fighters[index].facing)))
        }
        if triadStates[index] != nil {
            recordTriadPresentation(.contact(.init(owner: index, target: target, attackID: nil, ability: nil,
                kind: .hit, position: point, direction: fighters[index].facing, critical: false)))
        }
        landedHits[index] += 1; damageDealt[index] += actual
        events.append(.hit(attacker: index, damage: actual))
    }

    private mutating func releaseSourceThrowActor(_ index: Int, received: Bool) {
        actions[index] = nil; queued[index] = nil; fighters[index].attack = nil
        fighters[index].stun = 0; fighters[index].knockdown = 0
        loopRoles[index] = ""; loopTicks[index] = 0
        if received, let recovery = profiles[index].clip(role: "getUp") {
            // The catalog's ordinary recovery input adapter resumes after the
            // exact passive AnimationEnd; it does not stretch the throw clip.
            begin(index, clip: recovery, role: "getUp", reaction: true)
        } else { setPose(index, role: "idle", tick: 0) }
    }

    private mutating func cancelSourceThrow(owner: Int) {
        guard let state = sourceThrowStates[owner] else { return }
        let participants = (0..<2).filter { state.owns($0) }
        sourceThrowStates[owner] = nil
        for index in participants { releaseSourceThrowActor(index, received: false) }
    }

    public func ordinaryThrow(_ index: Int) -> DuelWeaponThrowState? {
        guard fighters.indices.contains(index) else { return nil }
        return ordinaryThrowStates.compactMap { $0 }.first { $0.ownsFighter(index: index) }
    }

    private func ordinaryThrowOwns(_ index: Int) -> Bool {
        ordinaryThrowStates.contains { $0?.ownsFighter(index: index) == true } ||
            sourceThrowStates.contains { $0?.owns(index) == true }
    }

    private func throwPosition(_ index: Int) -> DuelWeaponThrowPosition {
        .init(x: fighters[index].x, y: fighters[index].y)
    }

    private func throwGrounded(_ index: Int) -> Bool {
        fighters[index].y == 0 && fighters[index].velocityY == 0 &&
            !isAirborne(index) && actions[index]?.role != "jump" && panguSpace.lifts[index] == nil
    }

    private func throwTargetAvailable(_ index: Int, rule: DuelWeaponThrowRule) -> Bool {
        guard fighters[index].health > 0, fighters[index].invulnerable == 0,
              fighters[index].stun == 0, fighters[index].knockdown == 0,
              ordinaryThrowKnockdownTicks[index] == 0, impactMotions[index] == nil,
              !panguSpace.controls[index].locked(at: panguSpace.tick),
              !panguSpace.controls[index].airHeld(at: panguSpace.tick),
              !triadSpace.controls[index].locked(at: triadSpace.tick),
              actions[index]?.reaction != true else { return false }
        // Two still-uncommitted attempts may meet. Their simultaneous policy
        // is resolved from a shared snapshot, never by seat update order.
        if ordinaryThrowOwns(index), ordinaryThrowStates[index]?.stage != .attempt { return false }
        if let cast = panguStates[index]?.activeCast {
            guard rule.canGrabAttackingTarget,
                  panguStates[index]?.rules.ability(cast.ability)?.interruptible == true else { return false }
        }
        if let cast = triadStates[index]?.activeCast {
            guard rule.canGrabAttackingTarget,
                  triadStates[index]?.rules.ability(cast.ability)?.interruptible == true else { return false }
        }
        return actions[index]?.command == nil || rule.canGrabAttackingTarget
    }

    private func throwContext(_ state: DuelWeaponThrowState) -> DuelWeaponThrowState.ContactContext {
        .init(attackerPosition: throwPosition(state.attacker), targetPosition: throwPosition(state.target),
              attackerGrounded: throwGrounded(state.attacker), targetGrounded: throwGrounded(state.target),
              attackerAlive: fighters[state.attacker].health > 0, targetAlive: fighters[state.target].health > 0,
              targetAvailable: throwTargetAvailable(state.target, rule: state.rule),
              targetThrowImmune: !canBeThrown(state.target))
    }

    private mutating func startOrdinaryThrow(_ i: Int, command: DuelWeaponCommand) -> Bool {
        let target = 1 - i
        guard let rule = profiles[i].ordinaryThrows?.rule(command: command),
              !ordinaryThrowOwns(i), fighters[i].health > 0,
              throwGrounded(i), throwGrounded(target),
              throwTargetAvailable(target, rule: rule),
              !panguSpace.controls[i].locked(at: panguSpace.tick),
              !triadSpace.controls[i].locked(at: triadSpace.tick),
              !panguSpace.controls[i].airHeld(at: panguSpace.tick) else { return false }
        let distance = (fighters[target].x - fighters[i].x) * fighters[i].facing
        guard distance >= rule.minimumRangeMillimeters, distance <= rule.maximumRangeMillimeters,
              let state = DuelWeaponThrowState(rule: rule, attacker: i, target: target,
                  facing: fighters[i].facing, attackerPosition: throwPosition(i),
                  targetPosition: throwPosition(target)) else { return false }
        actions[i] = nil; queued[i] = nil; impactMotions[i] = nil
        fighters[i].attack = nil; fighters[i].guarding = false
        fighters[i].walking = false; fighters[i].movementDirection = 0
        panguSpace.jumpEligible[i] = false; panguSpace.speedRemainders[i] = 0
        ordinaryThrowStates[i] = state
        applyThrowSample(state.sample, state: state)
        if rule.startsPanguAttack, var pangu = panguStates[i] {
            let effects = pangu.attackStarted(heavy: false, eventID: panguSpace.nextHitID())
            panguStates[i] = pangu; panguSpace.enqueue(effects, owner: i)
        }
        return true
    }

    private mutating func prepareOrdinaryThrowSamples() {
        for state in ordinaryThrowStates.compactMap({ $0 }) {
            applyThrowSample(state.nextSample, state: state)
        }
    }

    private mutating func applyThrowSample(_ sample: DuelWeaponThrowState.Sample, state: DuelWeaponThrowState) {
        let positions = [sample.attacker.position.x] + (sample.target.map { [$0.position.x] } ?? [])
        let low = positions.min()!, high = positions.max()!
        // Validation bounds the entire relative path to the arena width. A
        // single translation retains both actors' spacing at either wall.
        let shift = low < DuelGame.leftWall ? DuelGame.leftWall - low :
            high > DuelGame.rightWall ? DuelGame.rightWall - high : 0
        func apply(_ actor: DuelWeaponThrowState.ActorSample, to index: Int) {
            guard let clip = profiles[index].clip(role: actor.role) else { return }
            fighters[index].x = actor.position.x + shift
            fighters[index].y = actor.position.y; fighters[index].velocityY = 0
            fighters[index].facing = actor.facing
            fighters[index].guarding = false; fighters[index].walking = false
            fighters[index].movementDirection = 0; fighters[index].attack = nil
            fighters[index].weaponPose = .init(clip: clip.name, tick: actor.phaseBps, duration: 10_000,
                groundLift: clip.tracks.lift(phase: Double(actor.phaseBps) / 10_000),
                reaction: index == state.target)
        }
        apply(sample.attacker, to: state.attacker)
        if let target = sample.target { apply(target, to: state.target) }
    }

    private mutating func resolveOrdinaryThrows(advancing: [Bool]) {
        let contexts = ordinaryThrowStates.map { $0.map { throwContext($0) } }
        let contacts = (0..<2).filter { i in
            advancing[i] && ordinaryThrowStates[i].map { state in
                contexts[i].map { state.wouldContact(context: $0) } ?? false
            } == true
        }
        if contacts.count == 2,
           profiles[contacts[0]].ordinaryThrows?.simultaneousContactPolicy == .bothMiss {
            for i in contacts {
                guard var state = ordinaryThrowStates[i], let context = contexts[i] else { continue }
                let result = state.forceMiss(attackerPosition: context.attackerPosition,
                                             targetPosition: context.targetPosition)
                ordinaryThrowStates[i] = state
                applyThrowSample(result.sample, state: state)
            }
            return
        }
        // A contacting attempt claims both participants before another attempt
        // can advance. The optional lower-index policy is explicitly supplied.
        let order = contacts + (0..<2).filter { !contacts.contains($0) }
        for i in order where advancing[i] {
            guard var state = ordinaryThrowStates[i], let context = contexts[i] else { continue }
            let result = state.advance(context: context)
            ordinaryThrowStates[i] = state
            if state.isCancelled { cancelOrdinaryThrow(owner: i); continue }
            if result.contactOutcome == .success || result.contactOutcome == .immune {
                claimOrdinaryThrow(state)
            }
            // Advancing samples were already applied before ordinary movement
            // and separation. Only a new stage needs its tick-zero pose here;
            // reapplying a miss would undo the free opponent's body separation.
            if result.contactOutcome != nil { applyThrowSample(result.sample, state: state) }
            if let damage = result.damage { applyOrdinaryThrowDamage(damage, state: state) }
            if result.released, ordinaryThrowStates[i] != nil {
                finishOrdinaryThrow(state, knockdownTicks: result.knockdownTicks)
            }
        }
    }

    private mutating func claimOrdinaryThrow(_ state: DuelWeaponThrowState) {
        cancelOrdinaryThrow(owner: state.target)
        for i in [state.attacker, state.target] {
            actions[i] = nil; queued[i] = nil; impactMotions[i] = nil
            ordinaryThrowKnockdownTicks[i] = 0
            fighters[i].stun = 0; fighters[i].knockdown = 0; fighters[i].velocityY = 0
            fighters[i].attack = nil; fighters[i].guarding = false
            panguSpace.jumpEligible[i] = false; panguSpace.speedRemainders[i] = 0
            if i == state.target, var pangu = panguStates[i] {
                pangu.cancelPendingDerivedAttacks()
                let effects = pangu.interrupt()
                panguStates[i] = pangu; panguSpace.enqueue(effects, owner: i)
                panguSpace.cancelMelee(owner: i); panguSpace.lifts[i] = nil
            }
            if i == state.target, var triad = triadStates[i] {
                let effects = triad.interrupt(); triadStates[i] = triad
                triadSpace.enqueue(effects, owner: i); triadSpace.cancelUnreleased(owner: i)
            }
        }
        if state.outcome == .immune, panguStates[state.target] != nil {
            recordPanguPresentation(.ordinaryThrowEscaped(attacker: state.attacker, target: state.target,
                position: .init(x: Double(fighters[state.target].x) / 1000, y: 1)))
        }
    }

    private mutating func applyOrdinaryThrowDamage(_ marker: DuelWeaponThrowState.Damage,
                                                  state: DuelWeaponThrowState) {
        let i = state.attacker, target = state.target, rule = state.rule
        guard fighters[i].health > 0, fighters[target].health > 0,
              panguStates[target]?.damageImmune != true else { return }
        var damage = marker.amount
        let contactID = rule.registersPanguContact && panguStates[i] != nil ? panguSpace.nextHitID() : nil
        if var pangu = panguStates[i] {
            if let contactID { pangu.prepareOrdinaryContact(blocked: false, kind: rule.damageKind, hitID: contactID) }
            if rule.appliesPanguDamageScaling { damage = pangu.outgoingDamage(damage, kind: rule.damageKind) }
            panguStates[i] = pangu
        }
        let actual = receiveTargetDamage(damage, kind: DuelTriadRules.DamageKind(rawValue: rule.damageKind.rawValue)!,
            attacker: i, blocked: false)
        if panguStates[i] == nil && triadStates[i] == nil {
            let multiplier = triadStates[target]?.opponentShadowEnergyGainMultiplierBps ?? 10_000
            fighters[i].energy = min(100, fighters[i].energy + rule.attackerEnergyGain * multiplier / 10_000)
        }
        if panguStates[target] == nil && triadStates[target] == nil {
            let multiplier = triadStates[i]?.opponentShadowEnergyGainMultiplierBps ?? 10_000
            fighters[target].energy = min(100, fighters[target].energy + rule.targetEnergyGain * multiplier / 10_000)
        }
        if var triad = triadStates[i] {
            let effects = triad.ordinaryContact(blocked: false, eventID: triadSpace.nextHitID())
            triadStates[i] = triad; triadSpace.enqueue(effects, owner: i)
        }
        if let contactID, var pangu = panguStates[i] {
            let effects = pangu.contact(blocked: false, generated: false,
                hitID: contactID, heavy: false, kind: rule.damageKind)
            panguStates[i] = pangu; panguSpace.enqueue(effects, owner: i)
        }
        let point = DuelWeaponPoint(x: Double(fighters[target].x) / 1000,
                                    y: Double(fighters[target].y) / 1000 + 0.4)
        contacts.append(.init(kind: .hit, attacker: i, position: point, direction: state.facing,
                              heavy: false, usesWeapon: rule.damageKind == .weapon))
        if panguStates[i] != nil {
            recordPanguPresentation(.contact(.init(owner: i, target: target, attackID: nil, ability: nil,
                delivery: nil, damageKind: rule.damageKind, generated: false, empowered: false,
                kind: .hit, position: point, direction: state.facing)))
        }
        if triadStates[i] != nil {
            recordTriadPresentation(.contact(.init(owner: i, target: target, attackID: nil, ability: nil,
                kind: .hit, position: point, direction: state.facing, critical: false)))
        }
        landedHits[i] += 1; damageDealt[i] += actual
        events.append(.hit(attacker: i, damage: actual))
        hitStop = max(hitStop, marker.hitStopTicks)
    }

    private mutating func finishOrdinaryThrow(_ state: DuelWeaponThrowState, knockdownTicks: Int) {
        ordinaryThrowStates[state.attacker] = nil
        let participants = [state.attacker] + (state.sample.target == nil ? [] : [state.target])
        for i in participants {
            actions[i] = nil; queued[i] = nil; fighters[i].attack = nil
            fighters[i].stun = 0; fighters[i].knockdown = 0
            loopRoles[i] = ""; loopTicks[i] = 0
        }
        if knockdownTicks > 0, fighters[state.target].health > 0,
           let down = profiles[state.target].clip(role: "knockdown") {
            begin(state.target, clip: down, role: "knockdown", tick: down.ticks, reaction: true)
            ordinaryThrowKnockdownTicks[state.target] = knockdownTicks
            fighters[state.target].stun = knockdownTicks; fighters[state.target].knockdown = knockdownTicks
        }
    }

    private mutating func cancelOrdinaryThrows(involving index: Int) {
        for owner in 0..<2 where sourceThrowStates[owner]?.owns(index) == true {
            cancelSourceThrow(owner: owner)
        }
        for owner in 0..<2 where ordinaryThrowStates[owner]?.ownsFighter(index: index) == true {
            cancelOrdinaryThrow(owner: owner)
        }
        ordinaryThrowKnockdownTicks[index] = 0
    }

    private mutating func cancelOrdinaryThrow(owner: Int) {
        guard let state = ordinaryThrowStates[owner] else { return }
        let participants = [state.attacker] + (state.sample.target == nil ? [] : [state.target])
        ordinaryThrowStates[owner] = nil
        for i in participants {
            let bodyHeight = Double(fighters[i].y) / 1000 + sourceVerticalOffset(i)
            let airborne = isAirborne(i)
            actions[i] = nil; queued[i] = nil; fighters[i].attack = nil
            fighters[i].stun = 0; fighters[i].knockdown = 0; ordinaryThrowKnockdownTicks[i] = 0
            panguSpace.jumpEligible[i] = false
            if airborne, let hit = profiles[i].clip(role: "hit") {
                begin(i, clip: hit, role: "hit", reaction: true)
            } else { setPose(i, role: "idle", tick: 0) }
            if airborne {
                fighters[i].y = min(DuelImpactMotion.maximumHeightMillimeters,
                    max(0, Int(((bodyHeight - sourceVerticalOffset(i)) * 1000).rounded())))
                impactMotions[i] = DuelImpactMotion(response: .init(distanceMillimeters: 0, durationTicks: 1,
                    launchVelocityMillimetersPerTick: 0, gravityMillimetersPerTickSquared: DuelGame.gravity),
                    direction: fighters[i].facing)
            }
        }
    }

    private mutating func cancelAllOrdinaryThrows() {
        for i in 0..<2 { cancelSourceThrow(owner: i) }
        for i in 0..<2 { cancelOrdinaryThrow(owner: i) }
        ordinaryThrowKnockdownTicks = [0, 0]
    }
}

// Kept in this file so action/queue/RNG internals stay private to gameplay.
extension DuelWeaponFight {
    func appendReplayState(to writer: inout DuelReplayStateWriter) throws {
        // panguPresentationEvents is bounded, derived renderer feedback. It is
        // intentionally absent: observing / discarding feedback cannot change
        // the canonical fight identity or require a replay schema bump.
        try writer.array(profiles, limit: 2) { try $0.profile($1) }
        try writer.array(fighters, limit: 2) { try $0.fighter($1) }
        try writer.phase(phase); try writer.int(frame); try writer.int(remainingTicks)
        try writer.array(wins, limit: 2) { try $0.int($1) }; try writer.int(hitStop)
        try writer.array(landedHits, limit: 2) { try $0.int($1) }
        try writer.array(damageDealt, limit: 2) { try $0.int($1) }
        try writer.array(events) { try $0.event($1) }
        try writer.array(contacts) { try $0.contact($1) }; try writer.array(swings) { try $0.swing($1) }
        try writer.mode(mode); try writer.difficulty(difficulty)
        try writer.array(actions, limit: 2) { writer, action in
            try writer.optional(action) { writer, action in
                try writer.string(action.name); try writer.string(action.role)
                try writer.optional(action.command) { try $0.command($1) }
                try writer.int(action.tick); try writer.int(action.hits); try writer.bool(action.touching)
                try writer.array(action.landedStrikeIDs) { try $0.int($1) }
                try writer.array(action.touchingStrikeIDs) { try $0.int($1) }
                try writer.bool(action.requiresContactSeparation)
                try writer.bool(action.sounded); try writer.bool(action.reaction)
                try writer.int(action.comboDepth)
                // Int.max means no sound scheduled; nil makes the sentinel width-independent.
                try writer.optional(action.soundAt == Int.max ? nil : action.soundAt) { try $0.int($1) }
                try writer.optional(action.shadowOriginX) { try $0.int($1) }
            }
        }
        try writer.array(queued, limit: 2) { writer, command in
            try writer.optional(command) { try $0.command($1) }
        }
        try writer.array(loopTicks, limit: 2) { try $0.int($1) }
        try writer.array(loopRoles, limit: 2) { try $0.string($1) }
        try writer.array(previousX, limit: 2) { try $0.int($1) }; try writer.u64(random)
        try writer.array(shadowCooldowns, limit: 2) { try $0.int($1) }
        try writer.array(previousY, limit: 2) { try $0.int($1) }
        try writer.array(previousHurtY, limit: 2) { try $0.int($1) }
        try writer.array(impactMotions, limit: 2) { writer, motion in
            try writer.optional(motion) { writer, motion in try motion.appendReplayState(to: &writer) }
        }
        try writer.array(panguStates, limit: 2) { writer, state in
            try writer.optional(state) { writer, state in try state.appendReplayState(to: &writer) }
        }
        try panguSpace.appendReplayState(to: &writer)
        try writer.array(ordinaryThrowStates, limit: 2) { writer, state in
            try writer.optional(state) { writer, state in try state.appendReplayState(to: &writer) }
        }
        try writer.array(ordinaryThrowKnockdownTicks, limit: 2) { try $0.int($1) }
        try writer.array(sourceThrowStates, limit: 2) { writer, state in
            try writer.optional(state) { try $1.appendReplayState(to: &$0) }
        }
        try writer.array(sourceThrowDisabledTicks, limit: 2) { try $0.int($1) }
        try writer.array(triadStates, limit: 2) { writer, state in
            try writer.optional(state) { writer, state in try state.appendReplayState(to: &writer) }
        }
        try triadSpace.appendReplayState(to: &writer)
        try writer.int(roundNumber)
        try writer.int(sourcePresentationTick)
        try writer.array(sourceStances, limit: 2) { writer, stance in
            try writer.optional(stance) { try $1.appendReplayState(to: &$0) }
        }
        try writer.array(previousPoses, limit: 2) { writer, pose in
            try writer.optional(pose) { try $0.pose($1) }
        }
        try writer.array(previousFacings, limit: 2) { try $0.int($1) }
    }
}
