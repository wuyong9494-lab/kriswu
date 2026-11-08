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
        var hits = 0
        var touching = false
        var sounded = false
        var reaction = false
        var comboDepth = 0
        var soundAt = Int.max
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
    private let mode: DuelGame.Mode
    private let difficulty: DuelGame.Difficulty
    private var actions: [Action?] = [nil, nil]
    private var queued: [DuelWeaponCommand?] = [nil, nil]
    private var loopTicks = [0, 0]
    private var loopRoles = ["", ""]
    private var previousX = [3500, 6500]
    private var random: UInt64

    public init?(fighters: [DuelGame.Fighter], mode: DuelGame.Mode, difficulty: DuelGame.Difficulty,
                 catalog: DuelWeaponCatalog, seed: UInt64) {
        do { try catalog.validate() } catch { return nil }
        guard fighters.count == 2,
              let a = catalog.profile(for: fighters[0].hero), let b = catalog.profile(for: fighters[1].hero),
              a.id != b.id else { return nil }
        self.fighters = fighters; self.mode = mode; self.difficulty = difficulty
        profiles = [a, b]; random = seed; previousX = fighters.map(\.x)
        for i in 0..<2 { setPose(i, role: "idle", tick: 0) }
    }
    public mutating func cancelBufferedInputs() { queued = [nil, nil] }
    public func isAirborne(_ index: Int) -> Bool {
        guard let pose = fighters[index].weaponPose,
              let clip = profiles[index].clip(named: pose.clip) else { return false }
        let t = clip.tracks
        return min(t.sample(t.footL, phase: pose.phase).y,
                   t.sample(t.footR, phase: pose.phase).y) + pose.groundLift > 0.17
    }
    public func supports(_ command: DuelWeaponCommand, index: Int) -> Bool {
        guard profiles.indices.contains(index), profiles[index].clip(command: command) != nil else { return false }
        // Katana root teleports by 8.4594 m; a thrown hammer tip teleports by
        // 7.7835 m in a half-frame. Their visibility/projectile/contact events
        // were not recovered. Sweeping either discontinuity fabricates hits.
        if command == .shadow { return false }
        return true
    }
    public func canUse(_ command: DuelWeaponCommand, index: Int) -> Bool {
        guard supports(command, index: index) else { return false }
        if command == .shadow { return fighters[index].energy >= 100 }
        return true
    }
    public func weaponTrailIsActive(_ index: Int) -> Bool {
        guard let action = actions[index], let command = action.command,
              !command.rawValue.hasPrefix("kick"), let clip = profiles[index].clip(named: action.name) else { return false }
        return active(action, clip: clip) && motionSpeed(index, clip: clip, command: command, tick: action.tick) > 0.009
    }
    public func shadowIsActive(_ index: Int) -> Bool { actions[index]?.command == .shadow }
    public func hurtBox(_ index: Int) -> DuelGame.Box {
        let f = fighters[index]
        var lift = f.weaponPose?.groundLift ?? 0
        if let p = f.weaponPose, let clip = profiles[index].clip(named: p.clip) {
            lift += clip.tracks.sample(clip.tracks.root, phase: p.phase).y
        }
        let low = Int((max(-0.15, lift) * 1000).rounded())
        let crouched = actions[index] == nil && f.weaponPose?.clip == profiles[index].roles["crouch"]
        return .init(minX: f.x - 270, maxX: f.x + 270,
                     minY: low + 180, maxY: low + (crouched ? 1050 : 1660))
    }
    public func attackBox(_ index: Int) -> DuelGame.Box? {
        guard let action = actions[index], let command = action.command,
              let clip = profiles[index].clip(named: action.name), active(action, clip: clip) else { return nil }
        let points = endpoints(index, clip: clip, phase: clip.phase(at: action.tick), command: command)
        guard !points.isEmpty else { return nil }
        let f = fighters[index], xs = points.map { f.x + Int($0.x * 1000) * f.facing }
        let ys = points.map { Int(($0.y + clip.tracks.lift(phase: clip.phase(at: action.tick))) * 1000) }
        return .init(minX: (xs.min() ?? f.x) - 80, maxX: (xs.max() ?? f.x) + 80,
                     minY: (ys.min() ?? 0) - 80, maxY: (ys.max() ?? 0) + 80)
    }
    public mutating func step(_ player: DuelGame.Input, opponent: DuelGame.Input? = nil) {
        events.removeAll(keepingCapacity: true); contacts.removeAll(keepingCapacity: true)
        swings.removeAll(keepingCapacity: true)
        if case .matchOver = phase { return }
        frame += 1
        if case .roundBreak(let winner, let ticks) = phase {
            if ticks > 1 { phase = .roundBreak(winner: winner, remaining: ticks - 1) }
            else { resetRound() }
            return
        }
        let inputs = [player, opponent ?? (mode == .versus ? botInput() : .neutral)]
        if hitStop > 0 {
            for i in 0..<2 where queued[i] == nil && !isAirborne(i) && actions[i]?.role != "jump" {
                queued[i] = inputs[i].weaponCommand
            }
            hitStop -= 1; return
        }
        if mode == .versus { remainingTicks -= 1 }
        previousX = fighters.map(\.x)
        for i in 0..<2 { update(i, input: inputs[i]) }
        separate()
        var pending: [(Int, DuelWeaponPoint, DuelWeaponCommand)] = []
        for i in 0..<2 {
            guard var action = actions[i], let command = action.command,
                  let clip = profiles[i].clip(named: action.name), !action.reaction else { continue }
            let isActive = active(action, clip: clip)
            if isActive && !action.sounded && action.tick >= action.soundAt {
                swings.append(.init(attacker: i, heavy: command == .heavy || command == .shadow,
                                     usesWeapon: !command.rawValue.hasPrefix("kick")))
                action.sounded = true
            }
            let point = isActive ? contact(i, action: action, clip: clip, command: command) : nil
            let maxHits = 1 + action.comboDepth
            if let point, !action.touching, action.hits < maxHits {
                pending.append((i, point, command)); action.hits += 1
            }
            action.touching = point != nil; actions[i] = action
        }
        // Resolve both swept contacts after collecting them, preserving trades.
        for (i, point, command) in pending { applyHit(i, point: point, command: command) }
        resolveRound()
    }
    private mutating func update(_ i: Int, input: DuelGame.Input) {
        fighters[i].flash = 0; fighters[i].walking = false; fighters[i].movementDirection = 0
        fighters[i].invulnerable = max(0, fighters[i].invulnerable - 1)
        if var action = actions[i], var clip = profiles[i].clip(named: action.name) {
            if let command = input.weaponCommand, !action.reaction {
                if action.role == "jump" {
                    // An aerial press is consumed in the air, never delayed
                    // until landing and unexpectedly replayed as a ground kick.
                    if command.rawValue.hasPrefix("kick"), let aerial = profiles[i].clip(role: "kickJump") {
                        let p = min(0.6, clip.phase(at: action.tick))
                        begin(i, clip: aerial, role: "kickJump", command: command, tick: Int(p * Double(aerial.ticks)))
                        return
                    }
                } else if !isAirborne(i) && action.command != nil && queued[i] == nil {
                    let link = profiles[i].combo(from: action.name)
                    if (command == action.command && action.tick <= (link?.sourceFrame ?? -1) * 2) || clip.ticks - action.tick <= 24 {
                        queued[i] = command
                    }
                }
            }
            if let continued = consumeCombo(i, action: action) {
                action = continued; clip = profiles[i].clip(named: action.name) ?? clip
            }
            let oldPhase = clip.phase(at: action.tick)
            action.tick += 1
            if action.tick > clip.ticks {
                actions[i] = nil; fighters[i].attack = nil; fighters[i].stun = 0; fighters[i].knockdown = 0
                if action.role == "knockdown", let up = profiles[i].clip(role: "getUp") {
                    begin(i, clip: up, role: "getUp", reaction: true); return
                }
                if action.role == "getUp" { fighters[i].invulnerable = 20 }
                let next = queued[i]; queued[i] = nil
                if let next, !action.reaction { startCommand(i, command: next) }
                else { setPose(i, role: "idle", tick: 0) }
                return
            }
            let t = clip.tracks, delta = t.sample(t.root, phase: clip.phase(at: action.tick)).x - t.sample(t.root, phase: oldPhase).x
            fighters[i].x += Int((delta * 1000).rounded()) * fighters[i].facing
            fighters[i].x = clamped(fighters[i].x)
            if action.role == "jump" { fighters[i].x = clamped(fighters[i].x + input.move * 40) }
            if let continued = consumeCombo(i, action: action) { action = continued }
            let displayed = profiles[i].clip(named: action.name) ?? clip
            actions[i] = action; fighters[i].attack?.age = action.tick
            if action.reaction {
                fighters[i].stun = clip.ticks - action.tick
                if action.role == "knockdown" || action.role == "getUp" { fighters[i].knockdown = fighters[i].stun }
            }
            setPose(i, clip: displayed, tick: action.tick, reaction: action.reaction)
            return
        }
        fighters[i].facing = fighters[1 - i].x >= fighters[i].x ? 1 : -1
        fighters[i].guarding = input.guardHeld && input.weaponCommand == nil && input.vertical == 0 && input.move == 0
        if let command = input.weaponCommand ?? queued[i] {
            queued[i] = nil; startCommand(i, command: command); return
        }
        if input.taps.contains(.jump), let jump = profiles[i].clip(role: "jump") {
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
        guard let clip = profiles[i].clip(command: command) else { return }
        if command == .shadow { fighters[i].energy = 0 }
        begin(i, clip: clip, role: command.rawValue, command: command)
    }
    private mutating func consumeCombo(_ i: Int, action: Action) -> Action? {
        guard let link = profiles[i].combo(from: action.name), action.tick == link.sourceFrame * 2,
              let command = action.command, queued[i] == command, action.comboDepth < 2,
              let clip = profiles[i].clip(named: link.to) else { return nil }
        // The source-frame anchor also accepts a press delivered during a hit
        // stop at that exact frame. Both paths preserve the existing timeline.
        queued[i] = nil
        return Action(name: link.to, role: action.role, command: command, tick: action.tick,
                      hits: action.hits, touching: action.touching, sounded: false, reaction: false,
                      comboDepth: action.comboDepth + 1, soundAt: swingTick(i, clip: clip, command: command, after: action.tick))
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
        setPose(i, clip: clip, tick: tick, reaction: reaction)
    }
    private mutating func setPose(_ i: Int, role: String, tick: Int) {
        guard let clip = profiles[i].clip(role: role) ?? profiles[i].clip(role: "idle") else { return }
        setPose(i, clip: clip, tick: tick % max(1, clip.ticks))
    }
    private mutating func setPose(_ i: Int, clip: DuelWeaponClip, tick: Int, reaction: Bool = false) {
        fighters[i].weaponPose = .init(clip: clip.name, tick: tick, duration: clip.ticks,
                                      groundLift: clip.tracks.lift(phase: clip.phase(at: tick)), reaction: reaction)
    }
    private func active(_ action: Action, clip: DuelWeaponClip) -> Bool {
        guard action.command != nil else { return false }
        let p = clip.phase(at: action.tick)
        return p >= 0.12 && p <= 0.78
    }
    private func endpoints(_ i: Int, clip: DuelWeaponClip, phase: Double, command: DuelWeaponCommand) -> [DuelWeaponPoint] {
        let t = clip.tracks
        if command.rawValue.hasPrefix("kick") { return [t.sample(t.footL, phase: phase), t.sample(t.footR, phase: phase)] }
        var p: [DuelWeaponPoint] = []
        if profiles[i].activeWeaponSides.contains("left") { p += [t.sample(t.weaponBaseL, phase: phase), t.sample(t.weaponTipL, phase: phase)] }
        if profiles[i].activeWeaponSides.contains("right") { p += [t.sample(t.weaponBaseR, phase: phase), t.sample(t.weaponTipR, phase: phase)] }
        return p
    }
    private func motionSpeed(_ i: Int, clip: DuelWeaponClip, command: DuelWeaponCommand, tick: Int) -> Double {
        guard tick > 0 else { return 0 }
        let a = endpoints(i, clip: clip, phase: clip.phase(at: tick - 1), command: command)
        let b = endpoints(i, clip: clip, phase: clip.phase(at: tick), command: command)
        return zip(a, b).map { p, q in
            sqrt((q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y) + (q.z - p.z) * (q.z - p.z))
        }.max() ?? 0
    }
    private func swingTick(_ i: Int, clip: DuelWeaponClip, command: DuelWeaponCommand, after: Int) -> Int {
        let start = max(after + 1, Int(ceil(Double(clip.ticks) * 0.12)))
        let end = Int(Double(clip.ticks) * 0.78)
        guard start <= end else { return Int.max }
        let speeds = (start...end).map { motionSpeed(i, clip: clip, command: command, tick: $0) }
        guard let peak = speeds.max(), peak > 0.005,
              let onset = speeds.firstIndex(where: { $0 >= peak * 0.65 }) else { return Int.max }
        // An explicit native adaptation: start audio at the source geometry's
        // fast motion onset, not an arbitrary fraction of a long wind-up.
        return start + onset
    }
    private func contact(_ i: Int, action: Action, clip: DuelWeaponClip, command: DuelWeaponCommand) -> DuelWeaponPoint? {
        let target = fighters[1 - i]
        guard target.knockdown == 0, target.invulnerable == 0, action.tick > 0 else { return nil }
        let p = clip.phase(at: action.tick), before = clip.phase(at: action.tick - 1)
        let now = endpoints(i, clip: clip, phase: p, command: command)
        let old = endpoints(i, clip: clip, phase: before, command: command)
        let f = fighters[i], box = hurtBox(1 - i), radius = command.rawValue.hasPrefix("kick") ? 0.12 : 0.07
        func world(_ a: DuelWeaponPoint, previous: Bool) -> DuelWeaponPoint {
            .init(x: Double(previous ? previousX[i] : f.x) / 1000 + a.x * Double(f.facing),
                  y: a.y + clip.tracks.lift(phase: previous ? before : p), z: a.z)
        }
        for n in now.indices where old.indices.contains(n) {
            let a = world(old[n], previous: true), b = world(now[n], previous: false)
            let localSpeed = hypot(now[n].x - old[n].x, now[n].y - old[n].y)
            guard localSpeed > 0.005, abs(now[n].z) < 0.8 else { continue }
            if Self.segment(a, b, intersects: box, radius: radius) {
                return .init(x: min(Double(box.maxX) / 1000, max(Double(box.minX) / 1000, b.x)),
                             y: min(Double(box.maxY) / 1000, max(Double(box.minY) / 1000, b.y)), z: 0.08)
            }
            if !command.rawValue.hasPrefix("kick"), n % 2 == 1 {
                let base = world(now[n - 1], previous: false)
                if Self.segment(base, b, intersects: box, radius: radius) {
                    return .init(x: Double(target.x) / 1000, y: min(1.6, max(0.2, (base.y + b.y) * 0.5)), z: 0.08)
                }
            }
        }
        return nil
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
    private mutating func applyHit(_ i: Int, point: DuelWeaponPoint, command: DuelWeaponCommand) {
        let defender = 1 - i, blocked = fighters[defender].guarding && !isAirborne(defender)
        let heavy = command == .heavy || command == .shadow
        let base = command.rawValue.hasPrefix("kick") ? 65 : command == .heavy ? (profiles[i].isKatana ? 145 : 190) :
            command == .shadow ? (profiles[i].isKatana ? 170 : 195) : (profiles[i].isKatana ? 80 : 105)
        let damage = blocked ? max(1, base / 12) : base
        fighters[defender].health = max(0, fighters[defender].health - damage)
        fighters[i].energy = min(100, fighters[i].energy + (blocked ? 4 : 12))
        fighters[defender].energy = min(100, fighters[defender].energy + 5)
        fighters[defender].x = clamped(fighters[defender].x + fighters[i].facing * (heavy ? 200 : 65))
        let role = blocked ? "guard" : heavy ? "knockdown" : "hit"
        if let clip = profiles[defender].clip(role: role) {
            begin(defender, clip: clip, role: role, reaction: true)
            if role == "knockdown" { fighters[defender].knockdown = clip.ticks }
            if blocked { fighters[defender].guarding = true }
        }
        contacts.append(.init(kind: blocked ? .block : .hit, attacker: i, position: point,
                              direction: fighters[i].facing, heavy: heavy, usesWeapon: !command.rawValue.hasPrefix("kick")))
        if blocked { events.append(.blocked(defender: defender)) }
        else { landedHits[i] += 1; damageDealt[i] += damage; events.append(.hit(attacker: i, damage: damage)) }
        hitStop = max(hitStop, blocked ? 2 : heavy ? 5 : 3)
    }
    private mutating func separate() {
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
        guard actions[1] == nil else { return .neutral }
        let distance = abs(fighters[0].x - fighters[1].x), toward = fighters[0].x > fighters[1].x ? 1 : -1
        if distance > 1800 { return .init(move: toward) }
        let cadence = difficulty == .learning ? 45 : 22
        guard frame % cadence == 0 else { return .init(guardHeld: true) }
        random = random &* 6364136223846793005 &+ 1442695040888963407
        let choices: [DuelWeaponCommand] = [.weapon, .weaponForward, .heavy, .kick, .weaponDown]
        return .init(weaponCommand: choices[Int((random >> 32) % UInt64(choices.count))])
    }
    private mutating func resolveRound() {
        if mode != .versus {
            for i in 0..<2 where fighters[i].health <= 0 { fighters[i].health = 1000 }
            return
        }
        guard fighters.contains(where: { $0.health <= 0 }) || remainingTicks <= 0 else { return }
        let a = fighters[0].health, b = fighters[1].health, winner: Int? = a == b ? nil : a > b ? 0 : 1
        if let winner { wins[winner] += 1 }
        events.append(.roundEnded(winner: winner)); cancelBufferedInputs(); hitStop = 0
        if let winner, wins[winner] >= 2 {
            phase = .matchOver(winner: winner)
            if let victory = profiles[winner].clip(role: "victory") { setPose(winner, clip: victory, tick: victory.ticks) }
        } else { phase = .roundBreak(winner: winner, remaining: 150) }
    }
    private mutating func resetRound() {
        fighters = profiles.enumerated().map { .init(hero: $0.element.hero, x: $0.offset == 0 ? 3500 : 6500, facing: $0.offset == 0 ? 1 : -1) }
        actions = [nil, nil]; queued = [nil, nil]; loopTicks = [0, 0]; loopRoles = ["", ""]
        previousX = fighters.map(\.x); remainingTicks = 3600; hitStop = 0; phase = .fighting
        for i in 0..<2 { setPose(i, role: "idle", tick: 0) }
    }
}
