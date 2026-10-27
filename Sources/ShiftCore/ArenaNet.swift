import Foundation

// 乱斗联机：房主的手机算整局，每秒 20 次把画面要用的东西（每个人在哪、血、子弹、星星、比分、这段时间的特效）
// 压成一小包发给其他人；其他人只发摇杆。一包几百字节，丢了也没事（下一包就到）

/// 房主发出的一帧
public struct ArenaSnapshot: Equatable, Sendable {
    public struct FighterState: Equatable, Sendable {
        public var pos: V2
        public var facing: V2
        public var moving: V2
        public var health: Int
        public var ammo: Double
        public var superCharge: Double
        public var alive: Bool
        public var respawnIn: Double
        public var stars: Int
        public var kills: Int
        public var deaths: Int
        public var damageDealt: Int
        public var place: Int?
        public var attackedRecently: Bool
        public var leap: Fighter.Leap?
        public var dashing: Bool
        /// 房主收到这个人的第几次摇杆了（这个人自己的手机按这个把还没算到的那几步补上）
        public var ack: Int
    }

    public var time: Double
    public var fighters: [FighterState]
    public var projectiles: [Projectile]
    public var stars: [V2]
    public var teamKills: [Int]
    public var zoneProgress: [Double]
    public var countdown: ArenaGame.Countdown?
    public var safeRadius: Double
    public var result: ArenaGame.Result?
    public var events: [ArenaGame.Event]
}

extension ArenaGame {
    /// 现在的样子打成一帧（events：上一帧以来发生的事；acks：每个人的摇杆收到第几次了）
    public func snapshot(events: [Event], acks: [Int: Int] = [:]) -> ArenaSnapshot {
        ArenaSnapshot(
            time: time,
            fighters: fighters.map { f in
                ArenaSnapshot.FighterState(pos: f.pos, facing: f.facing, moving: f.moving, health: f.health, ammo: f.ammo,
                                           superCharge: f.superCharge, alive: f.alive, respawnIn: f.respawnIn, stars: f.stars,
                                           kills: f.kills, deaths: f.deaths, damageDealt: f.damageDealt, place: f.place,
                                           attackedRecently: time - f.lastAttack < 1, leap: f.leap, dashing: f.dash != nil,
                                           ack: acks[f.id] ?? 0)
            },
            projectiles: projectiles, stars: stars, teamKills: teamKills, zoneProgress: zoneProgress,
            countdown: countdown, safeRadius: safeRadius, result: result, events: events)
    }

    /// 收到房主的一帧：照着改（名字、角色、队伍这些开局定下的不变）
    public mutating func apply(_ snapshot: ArenaSnapshot) {
        time = snapshot.time
        for (i, state) in snapshot.fighters.enumerated() where fighters.indices.contains(i) {
            fighters[i].pos = state.pos
            fighters[i].facing = state.facing
            fighters[i].moving = state.moving
            fighters[i].health = state.health
            fighters[i].ammo = state.ammo
            fighters[i].superCharge = state.superCharge
            fighters[i].alive = state.alive
            fighters[i].respawnIn = state.respawnIn
            fighters[i].stars = state.stars
            fighters[i].kills = state.kills
            fighters[i].deaths = state.deaths
            fighters[i].damageDealt = state.damageDealt
            fighters[i].place = state.place
            fighters[i].lastAttack = state.attackedRecently ? time : time - 10
            fighters[i].leap = state.leap
            fighters[i].dash = state.dashing ? Fighter.Dash(direction: state.moving.normalized, remaining: 1, hit: []) : nil
        }
        projectiles = snapshot.projectiles
        stars = snapshot.stars
        teamKills = snapshot.teamKills
        zoneProgress = snapshot.zoneProgress
        countdown = snapshot.countdown
        safeRadius = snapshot.safeRadius
        result = snapshot.result
        events.append(contentsOf: snapshot.events)
    }

    /// 两帧之间先自己往前推一点（只是画面：子弹照直飞、人照着刚才的速度走，不算打中）
    public mutating func extrapolate(_ dt: Double, except skipped: Int? = nil) {
        guard result == nil else { return }
        time += dt
        for i in fighters.indices where i != skipped && fighters[i].alive {
            if var leap = fighters[i].leap {
                leap.elapsed = min(leap.elapsed + dt, Fighter.Leap.duration)
                fighters[i].leap = leap
                fighters[i].pos = V2.lerp(leap.from, leap.to, leap.elapsed / Fighter.Leap.duration)
            } else if fighters[i].moving.length > 0.01 {
                fighters[i].pos = ArenaGame.walk(from: fighters[i].pos, by: fighters[i].moving * dt, on: map)
            }
        }
        var kept: [Projectile] = []
        for var p in projectiles {
            if var lob = p.lob {
                lob.elapsed += dt
                guard lob.elapsed < lob.duration else { continue }
                p.lob = lob
                p.pos = V2.lerp(lob.from, lob.to, lob.elapsed / lob.duration)
            } else {
                let delta = p.velocity * dt
                p.pos = p.pos + delta
                p.rangeLeft -= delta.length
                if p.rangeLeft <= 0 || map.blocks(p.pos) { continue }
            }
            kept.append(p)
        }
        projectiles = kept
    }

    /// 走一步（碰墙贴着滑）：房主算、自己手机上先走一步都用这个
    public static func walk(from p: V2, by delta: V2, on map: ArenaMap) -> V2 {
        let r = fighterRadius
        if !map.collides(p + delta, radius: r) { return p + delta }
        if !map.collides(p + V2(delta.x, 0), radius: r) { return p + V2(delta.x, 0) }
        if !map.collides(p + V2(0, delta.y), radius: r) { return p + V2(0, delta.y) }
        return p
    }
}

// MARK: - 打包

extension ArenaSnapshot {
    /// 压成字节：位置精确到 1/100 格，血量整数，其余按需要的精度
    public func encoded() -> Data {
        var w = ByteWriter()
        w.f32(time)
        w.u8(teamKills.count)
        teamKills.forEach { w.u8($0) }
        w.u8(zoneProgress.count)
        zoneProgress.forEach { w.u16(Int(($0 * 100).rounded())) }
        if let countdown {
            w.u8(1)
            w.u8(countdown.team)
            w.f32(countdown.left)
        } else {
            w.u8(0)
        }
        w.f32(safeRadius)
        switch result {
        case nil: w.u8(0)
        case .team(let team)?: w.u8(1); w.u8(team)
        case .survivor(let id)?: w.u8(2); w.u8(id)
        case .draw?: w.u8(3)
        }
        w.u8(fighters.count)
        for f in fighters {
            w.v2(f.pos)
            w.dir(f.facing)
            w.small(f.moving)
            w.u16(max(f.health, 0))
            w.u8(Int((f.ammo * 80).rounded()))
            w.u8(Int((f.superCharge * 250).rounded()))
            var flags = 0
            if f.alive { flags |= 1 }
            if f.attackedRecently { flags |= 2 }
            if f.leap != nil { flags |= 4 }
            if f.dashing { flags |= 8 }
            w.u8(flags)
            w.u8(Int((max(f.respawnIn, 0) * 20).rounded()))
            w.u8(f.stars)
            w.u8(f.kills)
            w.u8(f.deaths)
            w.u32(f.damageDealt)
            w.u8(f.place ?? 0)
            w.u32(f.ack)
            if let leap = f.leap {
                w.v2(leap.from)
                w.v2(leap.to)
                w.u8(Int((leap.elapsed * 200).rounded()))
            }
        }
        w.u8(projectiles.count)
        for p in projectiles {
            w.u16(p.id & 0xFFFF)
            w.u8(p.owner)
            w.u8(p.team)
            w.v2(p.pos)
            w.v2(p.velocity)
            w.u8(Int((p.radius * 100).rounded()))
            w.u16(Int((min(p.rangeLeft, 600) * 100).rounded()))
            var flags = 0
            if p.isSuper { flags |= 1 }
            if p.pierce { flags |= 2 }
            if p.lob != nil { flags |= 4 }
            w.u8(flags)
            if let lob = p.lob {
                w.v2(lob.from)
                w.v2(lob.to)
                w.u8(Int((lob.duration * 100).rounded()))
                w.u8(Int((lob.elapsed * 100).rounded()))
                w.u8(Int((lob.blast * 20).rounded()))
            }
        }
        w.u8(stars.count)
        stars.forEach { w.v2($0) }
        let kept = Array(events.prefix(60))
        w.u8(kept.count)
        for event in kept {
            switch event {
            case .hit(let target, let amount): w.u8(1); w.u8(target); w.u16(min(amount, 65535))
            case .knockout(let target, let by): w.u8(2); w.u8(target); w.u8(by ?? 255)
            case .explosion(let at, let radius): w.u8(3); w.v2(at); w.u8(Int((radius * 20).rounded()))
            case .pickup(let fighter): w.u8(4); w.u8(fighter)
            case .respawn(let fighter): w.u8(5); w.u8(fighter)
            case .special(let fighter): w.u8(6); w.u8(fighter)
            case .attack(let fighter): w.u8(7); w.u8(fighter)
            }
        }
        return w.data
    }

    public init?(data: Data) {
        var r = ByteReader(data)
        guard let time = r.f32(), let killCount = r.u8() else { return nil }
        var kills: [Int] = []
        for _ in 0..<killCount { guard let v = r.u8() else { return nil }; kills.append(v) }
        guard let zoneCount = r.u8() else { return nil }
        var zone: [Double] = []
        for _ in 0..<zoneCount { guard let v = r.u16() else { return nil }; zone.append(Double(v) / 100) }
        guard let hasCountdown = r.u8() else { return nil }
        var countdown: ArenaGame.Countdown?
        if hasCountdown == 1 {
            guard let team = r.u8(), let left = r.f32() else { return nil }
            countdown = ArenaGame.Countdown(team: team, left: left)
        }
        guard let safeRadius = r.f32(), let resultKind = r.u8() else { return nil }
        var result: ArenaGame.Result?
        switch resultKind {
        case 1: guard let team = r.u8() else { return nil }; result = .team(team)
        case 2: guard let id = r.u8() else { return nil }; result = .survivor(id)
        case 3: result = .draw
        default: result = nil
        }
        guard let fighterCount = r.u8() else { return nil }
        var fighters: [FighterState] = []
        for _ in 0..<fighterCount {
            guard let pos = r.v2(), let facing = r.dir(), let moving = r.small(), let health = r.u16(), let ammo = r.u8(),
                  let charge = r.u8(), let flags = r.u8(), let respawn = r.u8(), let stars = r.u8(), let kills = r.u8(),
                  let deaths = r.u8(), let damage = r.u32(), let place = r.u8(), let ack = r.u32() else { return nil }
            var leap: Fighter.Leap?
            if flags & 4 != 0 {
                guard let from = r.v2(), let to = r.v2(), let elapsed = r.u8() else { return nil }
                leap = Fighter.Leap(from: from, to: to, elapsed: Double(elapsed) / 200)
            }
            fighters.append(FighterState(pos: pos, facing: facing, moving: moving, health: health, ammo: Double(ammo) / 80,
                                         superCharge: Double(charge) / 250, alive: flags & 1 != 0, respawnIn: Double(respawn) / 20,
                                         stars: stars, kills: kills, deaths: deaths, damageDealt: damage, place: place == 0 ? nil : place,
                                         attackedRecently: flags & 2 != 0, leap: leap, dashing: flags & 8 != 0, ack: ack))
        }
        guard let projectileCount = r.u8() else { return nil }
        var projectiles: [Projectile] = []
        for _ in 0..<projectileCount {
            guard let id = r.u16(), let owner = r.u8(), let team = r.u8(), let pos = r.v2(), let velocity = r.v2(),
                  let radius = r.u8(), let range = r.u16(), let flags = r.u8() else { return nil }
            var lob: Projectile.Lob?
            if flags & 4 != 0 {
                guard let from = r.v2(), let to = r.v2(), let duration = r.u8(), let elapsed = r.u8(), let blast = r.u8() else { return nil }
                lob = Projectile.Lob(from: from, to: to, duration: Double(duration) / 100, elapsed: Double(elapsed) / 100,
                                     blast: Double(blast) / 20)
            }
            projectiles.append(Projectile(id: id, owner: owner, team: team, pos: pos, velocity: velocity,
                                          rangeLeft: lob == nil ? Double(range) / 100 : .infinity, damage: 0,
                                          radius: Double(radius) / 100, pierce: flags & 2 != 0, charges: false,
                                          isSuper: flags & 1 != 0, lob: lob))
        }
        guard let starCount = r.u8() else { return nil }
        var stars: [V2] = []
        for _ in 0..<starCount { guard let v = r.v2() else { return nil }; stars.append(v) }
        guard let eventCount = r.u8() else { return nil }
        var events: [ArenaGame.Event] = []
        for _ in 0..<eventCount {
            guard let kind = r.u8() else { return nil }
            switch kind {
            case 1: guard let t = r.u8(), let a = r.u16() else { return nil }; events.append(.hit(target: t, amount: a))
            case 2: guard let t = r.u8(), let b = r.u8() else { return nil }; events.append(.knockout(target: t, by: b == 255 ? nil : b))
            case 3: guard let at = r.v2(), let radius = r.u8() else { return nil }; events.append(.explosion(at: at, radius: Double(radius) / 20))
            case 4: guard let f = r.u8() else { return nil }; events.append(.pickup(fighter: f))
            case 5: guard let f = r.u8() else { return nil }; events.append(.respawn(fighter: f))
            case 6: guard let f = r.u8() else { return nil }; events.append(.special(fighter: f))
            case 7: guard let f = r.u8() else { return nil }; events.append(.attack(fighter: f))
            default: return nil
            }
        }
        self.init(time: time, fighters: fighters, projectiles: projectiles, stars: stars, teamKills: kills, zoneProgress: zone,
                  countdown: countdown, safeRadius: safeRadius, result: result, events: events)
    }
}

/// 往一串字节里写数（小端）
struct ByteWriter {
    private(set) var data = Data()

    mutating func u8(_ v: Int) { data.append(UInt8(clamping: v)) }

    mutating func u16(_ v: Int) {
        let x = UInt16(clamping: v)
        data.append(UInt8(x & 0xFF))
        data.append(UInt8(x >> 8))
    }

    mutating func u32(_ v: Int) {
        let x = UInt32(clamping: v)
        for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8((x >> UInt32(shift)) & 0xFF)) }
    }

    mutating func i16(_ v: Int) { u16(Int(UInt16(bitPattern: Int16(clamping: v)))) }

    mutating func f32(_ v: Double) { u32(Int(Float(v).bitPattern)) }

    /// 位置：1/100 格
    mutating func v2(_ v: V2) {
        i16(Int((v.x * 100).rounded()))
        i16(Int((v.y * 100).rounded()))
    }

    /// 方向：1/100
    mutating func dir(_ v: V2) {
        u8(Int(Int8(clamping: Int((v.x * 100).rounded())).magnitudeAsUInt8))
        u8(Int(Int8(clamping: Int((v.y * 100).rounded())).magnitudeAsUInt8))
    }

    /// 小的速度：1/10 格每秒
    mutating func small(_ v: V2) {
        u8(Int(Int8(clamping: Int((v.x * 10).rounded())).magnitudeAsUInt8))
        u8(Int(Int8(clamping: Int((v.y * 10).rounded())).magnitudeAsUInt8))
    }
}

/// 从一串字节里按顺序读数；不够了返回 nil
struct ByteReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) { bytes = Array(data) }

    mutating func u8() -> Int? {
        guard index < bytes.count else { return nil }
        defer { index += 1 }
        return Int(bytes[index])
    }

    mutating func u16() -> Int? {
        guard let a = u8(), let b = u8() else { return nil }
        return a | b << 8
    }

    mutating func u32() -> Int? {
        guard let a = u16(), let b = u16() else { return nil }
        return a | b << 16
    }

    mutating func i16() -> Int? { u16().map { Int(Int16(bitPattern: UInt16($0))) } }

    mutating func f32() -> Double? { u32().map { Double(Float(bitPattern: UInt32($0))) } }

    mutating func v2() -> V2? {
        guard let x = i16(), let y = i16() else { return nil }
        return V2(Double(x) / 100, Double(y) / 100)
    }

    mutating func signed8() -> Int? { u8().map { Int(Int8(bitPattern: UInt8($0))) } }

    mutating func dir() -> V2? {
        guard let x = signed8(), let y = signed8() else { return nil }
        return V2(Double(x) / 100, Double(y) / 100)
    }

    mutating func small() -> V2? {
        guard let x = signed8(), let y = signed8() else { return nil }
        return V2(Double(x) / 10, Double(y) / 10)
    }
}

private extension Int8 {
    /// 按位当成无符号的一个字节
    var magnitudeAsUInt8: UInt8 { UInt8(bitPattern: self) }
}
