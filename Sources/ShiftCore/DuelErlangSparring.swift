/// Fixed-step, two-seat sparring fixture. Dimensions, timings and damage here
/// are preview values only. No original assets, PvP protocol or rendering.
public struct DuelErlangSparring: Equatable, Sendable {
    public enum Seat: Int, CaseIterable, Sendable { case erlang, sparringPartner }
    public enum Action: Equatable, Sendable { case walk(Int), guardOn, guardOff, spear, meditate, stopMeditation, hound, ascend, avatarStep, mountainSplitter, avatarEye, earthshaker, lightSwords, finalJudgement, partnerShadow, partnerSetAbility, partnerRanged }
    public enum Strike: Equatable, Sendable { case spear, hound, partner, avatarStep, mountainSplitter, mountainQuake, avatarEye, earthshaker, lightSwords, earthshakerBarrage, finalJudgement, meditationBlast, partnerShadow, partnerSetAbility, partnerRanged }
    public enum Event: Equatable, Sendable {
        case cue(DuelErlangState.Cue)
        case contact(attacker: Seat, strike: Strike, damage: Int, blocked: Bool)
        case defeated(Seat)
        case houndWeakness(target: Seat)
        case avatarStepStarted(chainIndex: Int)
        case mountainSplitterStarted
        case quakeScheduled
        case quakeTriggered
        case avatarEyeStarted
        case earthshakerStarted
        case earthshakerGroundImpact
        case lightSwords(DuelErlangLightSwords.Cue)
        case finalJudgementStarted(consumedSwords: Int)
        case finalJudgementReleased
        case wrathStarted
        case wrathEnded
        case heavensProtection(restoredHealth: Int)
        case interruptionPrevented(strike: Strike)
        case rangedDamagePrevented
        case meditationBlastReleased(ticksHeld: Int)
        case vulnerability(target: Seat, stacks: Int)
    }
    public struct Combatant: Equatable, Sendable {
        public fileprivate(set) var position: Int
        public fileprivate(set) var health = 100
        public fileprivate(set) var guarding = false
        public fileprivate(set) var stun = 0
        public fileprivate(set) var knockdown = 0
        public fileprivate(set) var weakness = 0
        public fileprivate(set) var vulnerabilityStacks = 0
        public fileprivate(set) var vulnerabilityTicks = 0
        fileprivate var plan: Plan?
        fileprivate var recovery = 0
        fileprivate var movement = 0
    }

    fileprivate struct Plan: Equatable, Sendable {
        let strike: Strike
        let direction: Int
        let origin: Int
        let chainIndex: Int
        let earthshakerBarrageCount: Int
        let judgementStock: Int
        var age = 0
        var connected = false
    }
    private struct StrikeProfile {
        let active: ClosedRange<Int>
        let range: Int
        let damage: Int
        let push: Int
        let stun: Int
        let recovery: Int
    }

    private struct Hit {
        let attacker: Seat
        let target: Seat
        let strike: Strike
        let damage: Int
        let push: Int
        let stun: Int
        let blocked: Bool
    }

    public private(set) var tick = 0
    public private(set) var erlang: DuelErlangState
    public private(set) var fighters = [Combatant(position: -65), Combatant(position: 65)]
    public private(set) var winner: Seat?
    public private(set) var events: [Event] = []
    public private(set) var stepPresentation = DuelErlangStepPresentation()
    public private(set) var earthPresentation = DuelErlangEarthPresentation()
    public private(set) var axePresentation = DuelErlangAxePresentation()
    public private(set) var eyePresentation = DuelErlangEyePresentation()
    public private(set) var houndSmoke = DuelErlangHoundSmoke()
    public private(set) var houndPresentation = DuelErlangHoundPresentation()
    public private(set) var meditationMedia = DuelErlangMeditationMedia()
    public private(set) var meditationPresentation = DuelErlangMeditationPresentation()
    public var releasedMeditationThisTick: Bool {
        events.contains { if case .meditationBlastReleased = $0 { return true }; return false }
    }
    public private(set) var avatarStepChain = 0
    public private(set) var avatarStepWindow = 0
    public private(set) var avatarStepCooldown = 0
    public private(set) var mountainSplitterCooldown = 0
    public let enhancedMountainSplitter: Bool
    public let enhancedAvatarEye: Bool
    public let enableSwordRetribution: Bool
    public let enhancedEarthshaker: Bool
    public let enableLevelSixPassives: Bool
    public let enableLevelThreeMeditation: Bool
    private var meditationAge = 0
    private var meditationBlastAge: Int?
    private var enlightenmentLifetimes: [Int] = []
    public var enlightenmentStacks: Int { enlightenmentLifetimes.count }
    // All numeric values in this preview profile are fixture values.
    private static let enlightenmentInterval = 24
    private static let enlightenmentLifetime = 90
    private static let enlightenmentLimit = 4
    public private(set) var avatarEyeCooldown = 0
    public private(set) var earthshakerCooldown = 0
    public private(set) var wrathTicks = 0
    // Unresolved L6 placeholders: deliberately fixture timing and values.
    private static let wrathDuration = 96
    private static let wrathRefillInterval = 28
    private static let wrathRangedCooldown = 22
    public private(set) var lightSwords = DuelErlangLightSwords()
    private var lightSwordLaunchOrigin: Int?
    private var pendingQuake: DuelErlangAxePresentation.Schedule?
    public var hasPendingQuake: Bool { pendingQuake != nil }

    // All times, range, and damage here are preview-only: Lv6 reference
    // supplies the qualitative three-use chain and increasing damage.
    private static let stepWindowTicks = 32
    private static let stepCooldownTicks = 45
    private static let stepDamage = [21, 27, 35]

    public init(mode: DuelErlangState.Mode = .versus, enhancedMountainSplitter: Bool = true, enhancedAvatarEye: Bool = true, enableSwordRetribution: Bool = true, enhancedEarthshaker: Bool = true, enableLevelSixPassives: Bool = false, enableLevelThreeMeditation: Bool = false) {
        erlang = .init(mode: mode)
        self.enhancedMountainSplitter = enhancedMountainSplitter
        self.enhancedAvatarEye = enhancedAvatarEye
        self.enableSwordRetribution = enableSwordRetribution
        self.enhancedEarthshaker = enhancedEarthshaker
        self.enableLevelSixPassives = enableLevelSixPassives
        self.enableLevelThreeMeditation = enableLevelThreeMeditation
    }

    public mutating func resetRound() {
        endWrath(emitEvent: false)
        erlang.apply(.nextRound)
        meditationAge = 0
        meditationBlastAge = nil
        meditationPresentation = .init()
        meditationMedia.cancel()
        houndPresentation.cancelRound()
        houndSmoke.clear()
        eyePresentation.resetRound()
        axePresentation.reset()
        earthPresentation.reset()
        stepPresentation.reset()
        if erlang.phase != .ascended { enlightenmentLifetimes.removeAll() }
        fighters = [Combatant(position: -65), Combatant(position: 65)]
        winner = nil
        isDraw = false
        avatarStepChain = 0
        avatarStepWindow = 0
        avatarStepCooldown = 0
        mountainSplitterCooldown = 0
        avatarEyeCooldown = 0
        earthshakerCooldown = 0
        lightSwords.clearRound()
        lightSwordLaunchOrigin = nil
        pendingQuake = nil
        events = []
        tick = 0
    }

    /// Submit at most one new input edge per seat per tick. Guard stays on
    /// until released, movement requests last exactly one tick.
    public mutating func step(erlangAction: Action? = nil, partnerAction: Action? = nil) {
        events = []
        meditationMedia.clearEdge()
        houndPresentation.clearObservation()
        eyePresentation.clearEdge()
        axePresentation.clearEdges()
        earthPresentation.clearEdges()
        stepPresentation.clearEdges()
        guard winner == nil, !isDraw else { return }
        tick += 1
        let wasMeditating = erlang.phase == .meditating
        erlang.apply(.tick)
        if enableLevelThreeMeditation { advanceMeditation(wasMeditating: wasMeditating) }
        let releasedSwords = lightSwords.step()
        avatarStepCooldown = max(0, avatarStepCooldown - 1)
        mountainSplitterCooldown = max(0, mountainSplitterCooldown - 1)
        avatarEyeCooldown = max(0, avatarEyeCooldown - 1)
        earthshakerCooldown = max(0, earthshakerCooldown - 1)
        advanceWrath()
        if avatarStepWindow > 0 {
            avatarStepWindow -= 1
            if avatarStepWindow == 0 { avatarStepChain = 0 }
        }
        for seat in Seat.allCases {
            let i = seat.rawValue
            fighters[i].movement = 0
            fighters[i].stun = max(0, fighters[i].stun - 1)
            fighters[i].recovery = max(0, fighters[i].recovery - 1)
            fighters[i].knockdown = max(0, fighters[i].knockdown - 1)
            fighters[i].weakness = max(0, fighters[i].weakness - 1)
            fighters[i].vulnerabilityTicks = max(0, fighters[i].vulnerabilityTicks - 1)
            if fighters[i].vulnerabilityTicks == 0 { fighters[i].vulnerabilityStacks = 0 }
        }
        take(erlangAction, seat: .erlang)
        take(partnerAction, seat: .sparringPartner)
        move()
        // Resolve simultaneous contacts from one pre-hit snapshot. In particular,
        // one seat's stun/knockback may not erase the other's same-frame hit.
        var hits = Seat.allCases.compactMap { contact(seat: $0) }
        let hound = fighters[0].plan.flatMap { $0.strike == .hound ? $0 : nil }
        let eye = fighters[0].plan.flatMap { $0.strike == .avatarEye ? $0 : nil }
        let eyeHit = hits.first { $0.attacker == .erlang && $0.strike == .avatarEye }
        let preHitErlangX = fighters[0].position
        let preHitTargetX = fighters[1].position
        let houndContact = hits.first { $0.strike == .hound }
        let houndTarget = fighters[1].position
        let axe = fighters[0].plan.flatMap { $0.strike == .mountainSplitter ? $0 : nil }
        let axeHit = hits.first { $0.attacker == .erlang && $0.strike == .mountainSplitter }
        let earth = fighters[0].plan.flatMap { $0.strike == .earthshaker ? $0 : nil }
        let groundImpact = events.contains(.earthshakerGroundImpact)
        let earthHit = hits.first { $0.attacker == .erlang && $0.strike == .earthshaker }
        let stomp = fighters[0].plan.flatMap { $0.strike == .avatarStep ? $0 : nil }
        let stompHit = hits.first { $0.attacker == .erlang && $0.strike == .avatarStep }
        let dueQuake = pendingQuake.flatMap { tick >= $0.dueTick ? $0 : nil }
        if let blast = meditationBlastContact() { hits.append(blast) }
        let earthBarrage = groundImpact ? earthshakerBarrageContact() : []
        hits += earthBarrage
        let quakeHit = quakeContact()
        if let quakeHit { hits.append(quakeHit) }
        hits += swordsAdvance(releasedSwords)
        for hit in hits {
            let i = hit.attacker.rawValue
            if hit.strike != .avatarEye && fighters[i].plan?.strike == hit.strike { fighters[i].plan?.connected = true }
        }
        for hit in hits { resolve(hit) }
        stepPresentation.observe(age: stomp?.age, stage: stomp?.chainIndex ?? 0,
            originX: preHitErlangX, direction: stomp?.direction ?? 1,
            lived: fighters[0].plan?.strike == .avatarStep, ended: fighters.contains { $0.health == 0 },
            activeAges: Self.profile(.avatarStep).active,
            contact: stompHit.map { $0.blocked ? .blocked : .landed }, contactX: preHitTargetX, damage: stompHit?.damage)
        let impact: DuelErlangEarthPresentation.Impact? = groundImpact ? .init(
            originX: preHitErlangX, outcome: earthHit.map { $0.blocked ? .blocked : .landed } ?? .missed,
            damage: earthHit?.damage, contactX: earthHit == nil ? nil : preHitTargetX) : nil
        let barrage: DuelErlangEarthPresentation.Barrage? = events.compactMap { event in
            guard case .lightSwords(.earthshakerBarrageReleased(let count)) = event else { return nil }
            let blocked = earthBarrage.lazy.filter { $0.blocked }.count
            return DuelErlangEarthPresentation.Barrage(
                released: count, originX: preHitErlangX, landed: earthBarrage.count - blocked,
                blocked: blocked, damage: earthBarrage.reduce(0) { $0 + $1.damage },
                contactX: earthBarrage.isEmpty ? nil : preHitTargetX)
        }.first
        earthPresentation.observe(age: earth?.age, originX: preHitErlangX, direction: earth?.direction ?? 1,
            consumed: earth?.earthshakerBarrageCount ?? 0, visible: fighters[0].plan?.strike == .earthshaker,
            finished: fighters.contains { $0.health == 0 }, impact: impact, barrage: barrage)
        axePresentation.observeSwing(age: axe?.age, originX: preHitErlangX, direction: axe?.direction ?? 1,
            survives: fighters[0].plan?.strike == .mountainSplitter,
            terminalAge: Self.profile(.mountainSplitter).active.upperBound, finished: fighters.contains { $0.health == 0 },
            contact: axeHit.map { $0.blocked ? .blocked : .landed }, contactX: preHitTargetX, damage: axeHit?.damage)
        eyePresentation.observe(age: eye?.age, originX: preHitErlangX, direction: eye?.direction ?? 1,
            survived: fighters[0].plan?.strike == .avatarEye, roundEnded: fighters.contains { $0.health == 0 },
            contact: eyeHit.map { $0.blocked ? .blocked : .landed }, contactX: preHitTargetX, damage: eyeHit?.damage)
        if let hound {
            let profile = Self.profile(.hound)
            let sweep = !hound.connected ? Self.houndSweep(hound, profile: profile) : nil
            let mayRemain = fighters[0].plan?.strike == .hound && fighters.allSatisfy { $0.health > 0 }
            houndPresentation.observe(accepted: events.contains(.cue(.houndRush)),
                age: hound.age, origin: hound.origin, direction: hound.direction,
                sweep: sweep, survived: mayRemain, atEnd: hound.age >= profile.active.upperBound,
                contact: houndContact.map { $0.blocked ? .blocked : .hit },
                contactPosition: houndContact == nil ? nil : houndTarget)
        }
        for seat in Seat.allCases {
            let i = seat.rawValue
            if let plan = fighters[i].plan, plan.age >= Self.profile(plan.strike).active.upperBound {
                fighters[i].plan = nil
                fighters[i].recovery = Self.profile(plan.strike).recovery
            }
        }
        let dead = Seat.allCases.filter { fighters[$0.rawValue].health == 0 }
        for seat in dead { events.append(.defeated(seat)) }
        if dead.count == 1 { winner = other(dead[0]) }
        if dead.count == 2 { isDraw = true }
        houndSmoke.observe(houndPresentation, roundFinished: !dead.isEmpty)
        if !dead.isEmpty { endWrath(emitEvent: true); pendingQuake = nil; lightSwords.clearRound(); lightSwordLaunchOrigin = nil }
        axePresentation.observeQuake(pending: pendingQuake, fired: dueQuake, hit: quakeHit.map { $0.blocked ? .blocked : .landed },
                                      contactX: preHitTargetX, damage: quakeHit?.damage)
        let interruption = events.contains(.cue(.meditationInterrupted))
        let isMeditating = erlang.phase == .meditating
        meditationMedia.advance(holding: isMeditating, released: releasedMeditationThisTick,
                                interrupted: interruption, roundFinished: !dead.isEmpty)
        meditationPresentation.observe(
            tick: tick, began: events.contains(.cue(.meditationStarted)), holding: isMeditating,
            ended: wasMeditating && !isMeditating,
            interrupted: interruption,
            overridePose: !dead.isEmpty || erlang.phase == .ascended ||
                fighters[0].plan != nil || fighters[0].recovery > 0 ||
                fighters[0].stun > 0 || fighters[0].knockdown > 0 ||
                fighters[0].movement != 0 || fighters[0].guarding
        )
    }

    public private(set) var isDraw = false

    private mutating func take(_ action: Action?, seat: Seat) {
        guard let action else { return }
        let i = seat.rawValue
        if action == .guardOff {
            fighters[i].guarding = false
            return
        }
        guard fighters[i].stun == 0, fighters[i].knockdown == 0, fighters[i].plan == nil, fighters[i].recovery == 0 else { return }
        let isErlang = seat == .erlang
        if isErlang, erlang.phase == .meditating {
            if action == .stopMeditation {
                if enableLevelThreeMeditation { releaseMeditation() }
                else { emit(erlang.apply(.interruptMeditation)) }
            }
            return
        }
        switch action {
        case .walk(let delta):
            fighters[i].guarding = false
            fighters[i].movement = max(-1, min(1, delta)) * 5
        case .guardOn:
            guard fighters[i].weakness == 0, !(isErlang && erlang.phase == .ascended) else { return }
            fighters[i].guarding = true
        case .guardOff: break
        case .spear: start(isErlang ? .spear : .partner, seat: seat)
        case .partnerShadow:
            if !isErlang { start(.partnerShadow, seat: seat) }
        case .partnerSetAbility:
            if !isErlang { start(.partnerSetAbility, seat: seat) }
        case .partnerRanged:
            if !isErlang { start(.partnerRanged, seat: seat) }
        case .hound:
            guard isErlang, let cue = erlang.apply(.hound) else { return }
            emit(cue)
            start(.hound, seat: seat)
        case .meditate:
            guard isErlang else { return }
            if let cue = erlang.apply(.beginMeditation) { fighters[i].guarding = false; emit(cue) }
        case .ascend:
            if isErlang, let cue = erlang.apply(.ascend) {
                fighters[i].guarding = false
                lightSwords.enterAvatar()
                emit(cue)
                if enableLevelSixPassives { emitSwords(lightSwords.refillSummonedStock()) }
            }
        case .avatarStep:
            guard isErlang, erlang.phase == .ascended, avatarStepCooldown == 0 else { return }
            avatarStepChain += 1
            let index = avatarStepChain
            if index == 3 {
                avatarStepChain = 0
                avatarStepWindow = 0
                avatarStepCooldown = moveCooldown(Self.stepCooldownTicks)
            } else {
                avatarStepWindow = Self.stepWindowTicks
            }
            start(.avatarStep, seat: seat, chainIndex: index)
            events.append(.avatarStepStarted(chainIndex: index))
            recordAvatarMove(.step)
        case .mountainSplitter:
            guard isErlang, erlang.phase == .ascended, mountainSplitterCooldown == 0 else { return }
            mountainSplitterCooldown = moveCooldown(65)
            start(.mountainSplitter, seat: seat)
            events.append(.mountainSplitterStarted)
            recordAvatarMove(.splitter)
        case .avatarEye:
            guard isErlang, erlang.phase == .ascended, avatarEyeCooldown == 0 else { return }
            avatarEyeCooldown = moveCooldown(62)
            start(.avatarEye, seat: seat)
            events.append(.avatarEyeStarted)
            recordAvatarMove(.eye)
        case .earthshaker:
            guard isErlang, erlang.phase == .ascended, earthshakerCooldown == 0 else { return }
            earthshakerCooldown = moveCooldown(58)
            events.append(.earthshakerStarted)
            // Fixture ordering: spend the stock already summoned at input,
            // then preserve the L4 swords granted by this accepted activation.
            let consumed = enhancedEarthshaker ? lightSwords.consumeSummonedStock() : 0
            if consumed > 0 { emitSwords(.earthshakerConsumed(count: consumed)) }
            start(.earthshaker, seat: seat, earthshakerBarrageCount: consumed)
            recordAvatarMove(.earthshaker)
        case .lightSwords:
            // Fixture input arbitration: baseline ranged input is meditation.
            // Using explicit launch in Avatar makes that conflict testable.
            guard isErlang, erlang.phase == .ascended, let cue = lightSwords.requestLaunch(cooldownOverride: wrathTicks > 0 ? Self.wrathRangedCooldown : nil) else { return }
            lightSwordLaunchOrigin = fighters[i].position
            emitSwords(cue)
        case .finalJudgement:
            guard isErlang, erlang.phase == .ascended, erlang.light == 100, wrathTicks == 0 else { return }
            let stock = lightSwords.consumeSummonedStock()
            start(.finalJudgement, seat: seat, judgementStock: stock)
            events.append(.finalJudgementStarted(consumedSwords: stock))
        case .stopMeditation: break
        }
    }

    private mutating func start(_ strike: Strike, seat: Seat, chainIndex: Int = 0, earthshakerBarrageCount: Int = 0, judgementStock: Int = 0) {
        let i = seat.rawValue
        let p = fighters[i].position
        let facing = fighters[other(seat).rawValue].position > p ? 1 : -1
        fighters[i].guarding = false
        fighters[i].plan = Plan(strike: strike, direction: facing, origin: p, chainIndex: chainIndex, earthshakerBarrageCount: earthshakerBarrageCount, judgementStock: judgementStock)
    }

    private func moveCooldown(_ normal: Int) -> Int { wrathTicks > 0 ? max(1, normal / 2) : normal }

    private mutating func recordAvatarMove(_ move: DuelErlangLightSwords.AvatarMove) {
        emitSwords(lightSwords.recordAvatarActivation(move))
        if wrathTicks > 0 { erlang.restoreAvatarLight(25) }
    }

    private mutating func beginWrath() {
        wrathTicks = Self.wrathDuration
        // Fixture: drain on completed release to make the restored Light
        // observable; localization only specifies the full gate and end drain.
        erlang.clearAvatarLight()
        avatarStepChain = 0
        avatarStepWindow = 0
        avatarStepCooldown = 0
        mountainSplitterCooldown = 0
        avatarEyeCooldown = 0
        earthshakerCooldown = 0
        lightSwords.shortenRangedCooldownForWrath(maximum: Self.wrathRangedCooldown)
        events.append(.wrathStarted)
        emitSwords(lightSwords.refillSummonedStock())
    }

    private mutating func advanceWrath() {
        guard wrathTicks > 0 else { return }
        if wrathTicks == 1 { endWrath(emitEvent: true); return }
        wrathTicks -= 1
        if (Self.wrathDuration - wrathTicks) % Self.wrathRefillInterval == 0 {
            emitSwords(lightSwords.refillSummonedStock())
        }
    }

    private mutating func endWrath(emitEvent: Bool) {
        guard wrathTicks > 0 else { return }
        wrathTicks = 0
        erlang.clearAvatarLight()
        if emitEvent { events.append(.wrathEnded) }
    }

    private mutating func move() {
        let nextLeft = clamp(fighters[0].position + fighters[0].movement)
        let nextRight = clamp(fighters[1].position + fighters[1].movement)
        // Left/right seats never exchange places in this fixture.
        if nextRight - nextLeft >= 18 {
            fighters[0].position = nextLeft
            fighters[1].position = nextRight
        }
    }

    private mutating func contact(seat: Seat) -> Hit? {
        let i = seat.rawValue
        let target = other(seat)
        let j = target.rawValue
        guard var plan = fighters[i].plan else { return nil }
        plan.age += 1
        fighters[i].plan = plan
        let profile = Self.profile(plan.strike)
        guard !plan.connected, profile.active.contains(plan.age) else { return nil }
        if plan.strike == .earthshaker {
            events.append(.earthshakerGroundImpact)
        }
        if plan.strike == .finalJudgement {
            // Release is not a hit and Wrath starts even if the stream misses.
            events.append(.finalJudgementReleased)
            beginWrath()
        }
        if plan.strike == .avatarEye, !DuelErlangEyePresentation.isPulse(plan.age) { return nil }
        let origin = plan.strike == .hound ? plan.origin : fighters[i].position
        let distance = (fighters[j].position - origin) * plan.direction
        if plan.strike == .hound {
            // Sweep each fixed step over the travelled segment. Not a full-range
            // pulse; a defender near the far edge is contacted later.
            guard let sweep = Self.houndSweep(plan, profile: profile) else { return nil }
            let targetInWorld = fighters[j].position
            guard (min(sweep.start, sweep.end)...max(sweep.start, sweep.end)).contains(targetInWorld) else { return nil }
        } else {
            guard (0...profile.range).contains(distance) else { return nil }
        }
        if plan.strike == .partnerRanged, enableLevelThreeMeditation, erlang.phase == .meditating {
            // Avoid assuming original projectile push/stagger with a zero-damage
            // hit; in this fixture the incoming ranged contact is ignored.
            events.append(.rangedDamagePrevented)
            return nil
        }
        let blocked = fighters[j].guarding && fighters[j].weakness == 0 && fighters[j].knockdown == 0
        let raw: Int
        switch plan.strike {
        case .avatarStep: raw = Self.stepDamage[plan.chainIndex - 1]
        case .earthshaker:
            // Independent preview falloff, not fitted to original animation
            // poses. Never allow a successful edge contact to heal/underflow.
            raw = max(1, profile.damage * (profile.range - distance) / profile.range)
        default: raw = profile.damage
        }
        let damage: Int
        if blocked && plan.strike == .finalJudgement {
            // Fixture defense proxy: each spent sword penetrates 12% of a
            // guarding opponent's defense (0 stock is fully blocked).
            damage = raw * min(100, plan.judgementStock * 12) / 100
        } else {
            damage = blocked ? 0 : previewDamage(raw, defender: fighters[j], strike: plan.strike)
        }
        return Hit(attacker: seat, target: target, strike: plan.strike,
                   damage: damage,
                   push: plan.direction * (blocked ? (plan.strike == .avatarEye ? 0 : 2) : profile.push),
                   stun: blocked ? 0 : profile.stun, blocked: blocked)
    }

    private mutating func advanceMeditation(wasMeditating: Bool) {
        if erlang.phase != .ascended {
            enlightenmentLifetimes = enlightenmentLifetimes.compactMap { $0 > 1 ? $0 - 1 : nil }
        }
        guard wasMeditating else { return }
        meditationAge += 1
        if meditationAge.isMultiple(of: Self.enlightenmentInterval) {
            if enlightenmentLifetimes.count == Self.enlightenmentLimit {
                enlightenmentLifetimes.removeFirst()
            }
            enlightenmentLifetimes.append(Self.enlightenmentLifetime)
        }
        if erlang.phase != .meditating || meditationAge >= 420 {
            releaseMeditation()
        }
    }

    private mutating func releaseMeditation() {
        // Only voluntary or natural completion triggers this preview blast.
        // Localization does not distinguish external interruption semantics.
        erlang.apply(.finishMeditation)
        meditationBlastAge = meditationAge
        meditationAge = 0
    }

    private mutating func meditationBlastContact() -> Hit? {
        guard let age = meditationBlastAge else { return nil }
        meditationBlastAge = nil
        events.append(.meditationBlastReleased(ticksHeld: age))
        let defender = fighters[Seat.sparringPartner.rawValue]
        let holdUnits = age / 12
        guard holdUnits > 0, abs(defender.position - fighters[Seat.erlang.rawValue].position) <= 48 else { return nil }
        let blocked = defender.guarding && defender.weakness == 0 && defender.knockdown == 0
        // Guard interaction, blast radius and buildup cadence are test choices.
        return Hit(attacker: .erlang, target: .sparringPartner, strike: .meditationBlast,
                   damage: blocked ? 0 : 2 * holdUnits, push: 0, stun: 0, blocked: blocked)
    }

    private mutating func quakeContact() -> Hit? {
        guard let quake = pendingQuake, tick >= quake.dueTick else { return nil }
        pendingQuake = nil
        events.append(.quakeTriggered)
        let defender = fighters[1]
        let profile = Self.profile(.mountainQuake)
        guard abs(defender.position - quake.originX) <= profile.range else { return nil }
        let blocked = defender.guarding && defender.weakness == 0 && defender.knockdown == 0
        return Hit(attacker: .erlang, target: .sparringPartner, strike: .mountainQuake,
                   damage: blocked ? 0 : previewDamage(profile.damage, defender: defender, strike: .mountainQuake), push: quake.direction * (blocked ? 2 : profile.push),
                   stun: blocked ? 0 : profile.stun, blocked: blocked)
    }

    private mutating func earthshakerBarrageContact() -> [Hit] {
        // Fixture: release at the ground-impact frame, independent of ground
        // contact. If interrupted before impact the spent swords are not refunded.
        guard let plan = fighters[0].plan, plan.strike == .earthshaker,
              plan.earthshakerBarrageCount > 0 else { return [] }
        emitSwords(.earthshakerBarrageReleased(count: plan.earthshakerBarrageCount))
        let target = fighters[1]
        guard (0...145).contains((target.position - fighters[0].position) * plan.direction) else { return [] }
        let blocked = target.guarding && target.weakness == 0 && target.knockdown == 0
        // Each consumed sword contributes one preview contact; 3 HP and
        // range 145 are test values, not the unresolved L6 damage placeholders.
        return (0..<plan.earthshakerBarrageCount).map { _ in
            Hit(attacker: .erlang, target: .sparringPartner, strike: .earthshakerBarrage,
                damage: blocked ? 0 : previewDamage(3, defender: target, strike: .earthshakerBarrage),
                push: 0, stun: 0, blocked: blocked)
        }
    }

    private mutating func swordsAdvance(_ release: DuelErlangLightSwords.Cue?) -> [Hit] {
        guard let cue = release else { return [] }
        emitSwords(cue)
        guard case .launchReleased(let count) = cue, let origin = lightSwordLaunchOrigin else { return [] }
        lightSwordLaunchOrigin = nil
        let target = fighters[1]
        guard (0...124).contains(target.position - origin) else { return [] }
        let blocked = target.guarding && target.weakness == 0 && target.knockdown == 0
        return (0..<count).map { _ in
            Hit(attacker: .erlang, target: .sparringPartner, strike: .lightSwords,
                damage: blocked ? 0 : previewDamage(4, defender: target, strike: .lightSwords),
                push: 0, stun: 0, blocked: blocked)
        }
    }

    private mutating func emitSwords(_ cue: DuelErlangLightSwords.Cue?) {
        if let cue { events.append(.lightSwords(cue)) }
    }

    private func previewDamage(_ damage: Int, defender: Combatant, strike: Strike) -> Int {
        // Independent test-stack multipliers. Not publication values.
        let enlightenment = strike == .partner || strike == .partnerShadow || strike == .partnerSetAbility || strike == .partnerRanged ? 0 : enlightenmentStacks
        let boosted = damage + damage * enlightenment * 10 / 100
        let ordinary = boosted + boosted * defender.vulnerabilityStacks / 10
        switch strike {
        case .avatarStep, .mountainSplitter, .mountainQuake, .avatarEye, .earthshaker:
            let base = ordinary + (enableSwordRetribution ? ordinary * lightSwords.retributionPercent() / 100 : 0)
            return wrathTicks > 0 ? base * 3 / 2 : base
        default: return ordinary
        }
    }

    private func preventsInterruption(_ hit: Hit) -> Bool {
        guard enableLevelSixPassives, hit.target == .erlang, !hit.blocked else { return false }
        let cause: DuelErlangReference.Interruption
        switch hit.strike {
        case .partnerShadow: cause = .shadowMove
        case .partnerSetAbility: cause = .specialSetAbility
        default: return false
        }
        return DuelErlangReference.preventsInterruption(
            track: .globalTowerTrial202604, tier: 6, phase: erlang.phase, cause: cause
        ) == true
    }

    private mutating func resolve(_ hit: Hit) {
        let i = hit.target.rawValue
        let oldHealth = fighters[i].health
        fighters[i].health = max(0, oldHealth - hit.damage)
        fighters[i].position = clamp(fighters[i].position + hit.push)
        let protected = preventsInterruption(hit)
        if protected && hit.stun > 0 {
            events.append(.interruptionPrevented(strike: hit.strike))
        }
        if !hit.blocked {
            if !protected && hit.strike != .meditationBlast && hit.strike != .avatarEye && hit.strike != .lightSwords && hit.strike != .earthshakerBarrage {
                fighters[i].stun = max(fighters[i].stun, hit.stun)
                fighters[i].plan = nil
                if hit.target == .erlang {
                    emit(erlang.apply(.interruptMeditation))
                    meditationAge = 0
                }
            }
            if hit.attacker == .erlang && hit.strike == .spear {
                erlang.apply(.weaponHit)
                emitSwords(lightSwords.recordSpearContact(.landed))
            }
        }
        events.append(.contact(attacker: hit.attacker, strike: hit.strike, damage: hit.damage, blocked: hit.blocked))
        if hit.strike == .meditationBlast && fighters[i].health < oldHealth {
            erlang.shortenMeditationCooldown(by: 16)
        }
        if enableLevelSixPassives && hit.target == .erlang && oldHealth > 0 &&
            fighters[i].health == 0 && erlang.phase == .ascended {
            applyHeavensProtection(to: i)
        }
        if (hit.strike == .lightSwords || hit.strike == .earthshakerBarrage) && !hit.blocked && fighters[i].health < oldHealth && enableSwordRetribution && erlang.phase == .ascended {
            emitSwords(lightSwords.recordSwordContact(.landed))
        }
        if hit.strike == .avatarEye && !hit.blocked && enhancedAvatarEye {
            fighters[i].vulnerabilityStacks = min(6, fighters[i].vulnerabilityStacks + 1)
            fighters[i].vulnerabilityTicks = 75
            events.append(.vulnerability(target: hit.target, stacks: fighters[i].vulnerabilityStacks))
        }
        if hit.strike == .mountainSplitter && !hit.blocked && enhancedMountainSplitter && erlang.phase == .ascended {
            // Fixture policy: trigger only after confirmed initial impact; the
            // ground effect is anchored at that location, not homing.
            let attackerPosition = fighters[hit.attacker.rawValue].position
            let direction = attackerPosition <= fighters[i].position ? 1 : -1
            pendingQuake = .init(originX: fighters[i].position, dueTick: tick + 24, direction: direction)
            events.append(.quakeScheduled)
        }
        if (hit.strike == .avatarStep || hit.strike == .mountainQuake || hit.strike == .earthshaker) && !hit.blocked {
            fighters[i].guarding = false
            fighters[i].knockdown = max(fighters[i].knockdown, 18)
        }
        if hit.strike == .hound && !hit.blocked {
            fighters[i].guarding = false
            fighters[i].knockdown = max(fighters[i].knockdown, 18)
            fighters[i].weakness = max(fighters[i].weakness, 55)
            events.append(.houndWeakness(target: hit.target))
        }
    }

    private mutating func applyHeavensProtection(to index: Int) {
        // Form and HP change before KO adjudication. The restoration amount
        // is a fixture, not the original unresolved localization percentage.
        let fixtureRestoredHP = 30
        endWrath(emitEvent: true)
        erlang.endAvatarAfterLethalHit()
        enlightenmentLifetimes.removeAll()
        fighters[index].health = fixtureRestoredHP
        fighters[index].plan = nil
        fighters[index].guarding = false
        avatarStepChain = 0
        avatarStepWindow = 0
        avatarStepCooldown = 0
        mountainSplitterCooldown = 0
        avatarEyeCooldown = 0
        earthshakerCooldown = 0
        // Fixture cleanup: not-yet-released golden effects cannot follow
        // Erlang into base form. Contacts materialized this tick still resolve.
        pendingQuake = nil
        lightSwordLaunchOrigin = nil
        lightSwords.clearRound()
        events.append(.heavensProtection(restoredHealth: fixtureRestoredHP))
    }

    private mutating func emit(_ cue: DuelErlangState.Cue?) {
        if let cue { events.append(.cue(cue)) }
    }

    private func other(_ seat: Seat) -> Seat { seat == .erlang ? .sparringPartner : .erlang }
    private func clamp(_ x: Int) -> Int { min(145, max(-145, x)) }

    private static func houndSweep(_ plan: Plan, profile: StrikeProfile) -> DuelErlangHoundPresentation.Sweep? {
        guard profile.active.contains(plan.age) else { return nil }
        let index = plan.age - profile.active.lowerBound
        let slices = profile.active.count
        let front = profile.range * (index + 1) / slices
        let back = max(0, profile.range * index / slices - 7)
        return .init(start: plan.origin + plan.direction * back, end: plan.origin + plan.direction * front)
    }

    private static func profile(_ strike: Strike) -> StrikeProfile {
        switch strike {
        case .spear: return .init(active: 5...8, range: 62, damage: 12, push: 18, stun: 8, recovery: 10)
        case .hound: return .init(active: 9...13, range: 102, damage: 15, push: 24, stun: 13, recovery: 12)
        case .avatarStep: return .init(active: 7...9, range: 125, damage: 0, push: 7, stun: 10, recovery: 6)
        case .mountainSplitter: return .init(active: 12...14, range: 88, damage: 24, push: 10, stun: 12, recovery: 11)
        case .mountainQuake: return .init(active: 1...1, range: 32, damage: 36, push: 16, stun: 13, recovery: 0)
        case .avatarEye: return .init(active: DuelErlangEyePresentation.activeAges, range: 105, damage: 6, push: 0, stun: 0, recovery: 8)
        case .finalJudgement: return .init(active: 12...12, range: 140, damage: 24, push: 0, stun: 7, recovery: 9)
        case .earthshaker: return .init(active: 10...10, range: 100, damage: 30, push: 11, stun: 11, recovery: 13)
        case .lightSwords, .earthshakerBarrage, .meditationBlast: preconditionFailure("Independent contacts are not action plans")
        case .partner, .partnerShadow, .partnerSetAbility:
            // Same values isolate category-dependent interruption from tuning.
            return .init(active: 4...6, range: 36, damage: 10, push: 14, stun: 7, recovery: 9)
        case .partnerRanged: return .init(active: 4...4, range: 140, damage: 8, push: 5, stun: 4, recovery: 9)
        }
    }
}
