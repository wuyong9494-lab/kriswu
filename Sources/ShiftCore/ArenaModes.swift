import Foundation

// 乱斗后加的几种玩法要的规则：足球（捡球、踢球、进球）、宝箱攻防（打宝箱）、三局两胜（一局一局打）、
// 双人大乱斗（两人一队）、一对一（3 个角色轮流上）、讨伐骷髅王（骷髅王自己怎么打）

/// 骷髅王的几招还要等几秒（到 0 就能出）
struct BossBrain: Equatable, Sendable {
    var swing = 1.5
    var volley = 2.5
    var slam = 5.0
    var charge = 8.0
    var summon = 12.0
}

extension ArenaGame {
    static let bossBaseHealth = 52000

    /// 骷髅王的满血（按勇者的平均等级加成）
    public static func bossHealth(level: Int) -> Int {
        Int((Double(bossBaseHealth) * Brawler.boost(level)).rounded())
    }

    /// 打中这个人要多近（骷髅王个子大，好打中）
    public static func hitRadius(_ fighter: Fighter) -> Double {
        fighter.isBoss ? 0.95 : fighterRadius
    }

    // MARK: 开局

    /// 讨伐骷髅王：上边一队的就是骷髅王，等级按勇者的平均
    mutating func setUpBoss() {
        let heroes = fighters.filter { $0.team == 0 }
        let level = heroes.isEmpty ? 1 : Int((Double(heroes.map(\.level).reduce(0, +)) / Double(heroes.count)).rounded())
        for i in fighters.indices where fighters[i].team == 1 {
            fighters[i].isBoss = true
            fighters[i].brawler = .guardian
            fighters[i].name = "骷髅王"
            fighters[i].level = min(max(level, 1), ArenaProgress.maxLevel)
            fighters[i].health = fighters[i].maxHealth
        }
    }

    /// 双人大乱斗：6 个出生点按绕着中间的角度排好，隔一个取一个，3 队分得最开
    static func duoAnchors(_ map: ArenaMap) -> [V2] {
        let spots = (map.spawns.first ?? []).sorted {
            atan2($0.y - map.center.y, $0.x - map.center.x) < atan2($1.y - map.center.y, $1.x - map.center.x)
        }
        return stride(from: 0, to: spots.count, by: 2).map { spots[$0] }
    }

    /// 双人大乱斗：队友出生在同一个点的左右两边
    static func duoSpawn(_ map: ArenaMap, anchors: [V2], team: Int, slot: Int) -> V2 {
        guard !anchors.isEmpty else { return map.center }
        let anchor = anchors[team % anchors.count]
        let out = (anchor - map.center).normalized
        let side = V2(-out.y, out.x) * (slot % 2 == 0 ? -0.7 : 0.7)
        return map.nearestOpen(to: anchor + side)
    }

    /// 一对一带的 3 个角色：报名时带了就用，不够的按种子补上不重复的
    static func lineup(_ entrant: Entrant, seed: UInt64) -> [Brawler] {
        var list = [entrant.brawler]
        for brawler in entrant.lineup where !list.contains(brawler) && list.count < 3 { list.append(brawler) }
        var random = SeededRandom(seed: seed)
        var others = Brawler.allCases.filter { !list.contains($0) }
        random.shuffle(&others)
        while list.count < 3, let next = others.popLast() { list.append(next) }
        return list
    }

    // MARK: 足球

    /// 带着球的人踢球：普通踢一秒 12 格（滚八格多停下），大招踢一秒 17 格
    mutating func kick(_ i: Int, _ aim: V2, power: Bool) {
        guard var ball, ball.carrier == i else { return }
        let direction = aim.length > 0.01 ? aim.normalized : fighters[i].facing
        let start = fighters[i].pos + direction * 0.5
        ball.pos = map.collides(start, radius: Ball.radius, ball: true) ? fighters[i].pos : start
        ball.velocity = direction * (power ? 17 : 12)
        ball.carrier = nil
        ball.kicker = i
        ball.kickTimer = 0.35
        self.ball = ball
        fighters[i].facing = direction
        fighters[i].lastAttack = time
        if power {
            fighters[i].superCharge = 0
            events.append(.special(fighter: i))
        } else {
            events.append(.attack(fighter: i))
        }
    }

    /// 球：有人带着就跟着他（在他脚前），没人带就往前滚；滚进球门进球，碰到人被捡起来
    mutating func updateBall(_ dt: Double) {
        guard var ball else { return }
        ball.kickTimer = max(0, ball.kickTimer - dt)
        if let carrier = ball.carrier {
            if fighters.indices.contains(carrier), fighters[carrier].alive {
                let front = fighters[carrier].pos + fighters[carrier].facing * 0.45
                ball.pos = map.collides(front, radius: Ball.radius, ball: true) ? fighters[carrier].pos : front
                ball.velocity = .zero
            } else {
                ball.carrier = nil
            }
        }
        if ball.carrier == nil {
            Self.roll(&ball, dt, on: map)
            if let defending = map.goalTeam(at: ball.pos), defending <= 1 {
                let scorer = 1 - defending
                score[scorer] += 1
                ball.velocity = .zero
                self.ball = ball
                events.append(.goal(team: scorer))
                if score[scorer] < Self.ballGoals { startBreak() }
                return
            }
            let reach = Self.fighterRadius + Ball.radius + 0.05
            let position = ball.pos
            let kicker = ball.kickTimer > 0 ? ball.kicker : nil
            let takers = fighters.filter { $0.alive && !$0.busy && $0.id != kicker && $0.pos.distance(to: position) < reach }
            if let taker = takers.min(by: { $0.pos.distance(to: position) < $1.pos.distance(to: position) }) {
                ball.carrier = taker.id
                ball.velocity = .zero
                events.append(.pickup(fighter: taker.id))
            }
        }
        self.ball = ball
    }

    /// 球往前滚：越滚越慢，碰到墙弹回来（房主算、别人的手机两包之间先滚都用这个）
    static func roll(_ ball: inout Ball, _ dt: Double, on map: ArenaMap) {
        guard ball.velocity.length > 0.05 else {
            ball.velocity = .zero
            return
        }
        let step = ball.velocity * dt
        if map.collides(ball.pos + step, radius: Ball.radius, ball: true) {
            if map.collides(ball.pos + V2(step.x, 0), radius: Ball.radius, ball: true) { ball.velocity.x = -ball.velocity.x * 0.6 }
            if map.collides(ball.pos + V2(0, step.y), radius: Ball.radius, ball: true) { ball.velocity.y = -ball.velocity.y * 0.6 }
            let retry = ball.pos + ball.velocity * dt
            if !map.collides(retry, radius: Ball.radius, ball: true) { ball.pos = retry }
        } else {
            ball.pos = ball.pos + step
        }
        ball.velocity = ball.velocity * max(0, 1 - 1.4 * dt)
    }

    // MARK: 宝箱

    mutating func hitChest(_ k: Int, _ amount: Int, by attacker: Int?) {
        guard chests.indices.contains(k), chests[k].health > 0, amount > 0 else { return }
        let dealt = min(amount, chests[k].health)
        chests[k].health -= dealt
        if let attacker, fighters.indices.contains(attacker) { fighters[attacker].damageDealt += dealt }
        events.append(.chestHit(chest: k, amount: dealt))
    }

    // MARK: 一局一局打（足球进球后、三局两胜每局之间）

    /// 停一会儿：谁都不动，子弹清掉
    mutating func startBreak() {
        pause = Self.breakTime
        projectiles.removeAll()
        for i in fighters.indices { fighters[i].moving = .zero }
    }

    /// 停完了：大家回到出发的地方（满血、满弹，大招留着），子弹、骨塔、圈都清掉；球放回中间，三局两胜开下一局
    mutating func resetField() {
        projectiles.removeAll()
        zones.removeAll()
        turrets.removeAll()
        warnings.removeAll()
        for i in fighters.indices where !fighters[i].isBoss {
            let spot = homeSpot(i)
            fighters[i].pos = spot
            fighters[i].facing = (map.center - spot).normalized
            fighters[i].health = fighters[i].maxHealth
            fighters[i].ammo = 3
            fighters[i].alive = true
            fighters[i].respawnIn = 0
            fighters[i].dash = nil
            fighters[i].leap = nil
            fighters[i].burst = nil
            fighters[i].shield = 0
            fighters[i].moving = .zero
            fighters[i].lastHurt = time
        }
        if mode == .ball { ball = Ball(pos: map.center) }
        if mode == .knockout {
            round += 1
            roundStart = time
            safeRadius = Double(max(map.width, map.height))
        }
        events.append(.reset)
    }

    /// 三局两胜：一队全倒下（或这一局打太久）就分出这一局；先赢两局的赢，不然停一会儿开下一局
    mutating func decideRound() {
        let standing = (0...1).map { team in fighters.contains { $0.team == team && $0.alive } }
        var winner: Int?
        if !standing[0] || !standing[1] {
            winner = standing[0] ? 0 : (standing[1] ? 1 : nil)
        } else if time - roundStart >= Self.roundLimit {
            // 打太久了：活着的人多的赢，一样多比血
            let alive = (0...1).map { team in fighters.filter { $0.team == team && $0.alive } }
            if alive[0].count != alive[1].count {
                winner = alive[0].count > alive[1].count ? 0 : 1
            } else {
                let health = (0...1).map { healthShare($0) }
                winner = health[0] == health[1] ? nil : (health[0] > health[1] ? 0 : 1)
            }
        } else {
            return
        }
        if let winner { score[winner] += 1 }
        events.append(.round(winner: winner))
        if let leader = score.firstIndex(where: { $0 >= Self.roundsToWin }) {
            result = .team(leader)
        } else if round >= 5 {
            result = compare(Double(score[0]), Double(score[1]))
        } else {
            startBreak()
        }
    }

    // MARK: 骷髅王

    /// 地上的红圈：时间到了炸
    mutating func updateWarnings(_ dt: Double) {
        guard !warnings.isEmpty else { return }
        for k in warnings.indices { warnings[k].left -= dt }
        let due = warnings.filter { $0.left <= 0 }
        warnings.removeAll { $0.left <= 0 }
        for warning in due {
            blast(at: warning.center, radius: warning.radius, damage: warning.damage, by: warning.owner, team: warning.team, charges: false)
        }
    }

    /// 骷髅王自己打：朝最近的勇者走，近了横扫、远了扔骨矛，隔一会儿砸地（先在地上画红圈）、冲撞、召唤骨塔；
    /// 血不到四成发狂，出招快、走得快
    mutating func updateBoss(_ i: Int, _ dt: Double) {
        guard fighters[i].alive else { return }
        if fighters[i].dash != nil {
            updateDash(i, dt)
            return
        }
        let enraged = fighters[i].health * 10 < fighters[i].maxHealth * 4
        let rate = enraged ? 1.45 : 1
        bossBrain.swing -= dt * rate
        bossBrain.volley -= dt * rate
        bossBrain.slam -= dt * rate
        bossBrain.charge -= dt * rate
        bossBrain.summon -= dt * rate
        let boss = fighters[i]
        let heroes = fighters.filter { $0.alive && $0.team != boss.team }
        guard let target = heroes.min(by: { $0.pos.distance(to: boss.pos) < $1.pos.distance(to: boss.pos) }) else {
            fighters[i].moving = .zero
            return
        }
        let distance = target.pos.distance(to: boss.pos)
        let toward = (target.pos - boss.pos).normalized
        fighters[i].facing = toward
        if distance > 1.8 {
            // 中间有墙就按格子绕过去
            var heading = toward
            if !map.lineOfSight(boss.pos, target.pos), let next = map.path(from: boss.pos, to: target.pos).first {
                heading = (next - boss.pos).normalized
            }
            let before = fighters[i].pos
            walk(i, by: heading * ((enraged ? 2.1 : 1.7) * dt))
            fighters[i].moving = (fighters[i].pos - before) * (1 / max(dt, 1e-6))
        } else {
            fighters[i].moving = .zero
        }
        if bossBrain.slam <= 0, distance < 3.6 {
            bossBrain.slam = 6.5
            fighters[i].lastAttack = time
            warnings.append(Warning(center: boss.pos, radius: 3.2, left: 1.0, total: 1.0, damage: power(i, 2400), owner: i, team: boss.team))
            events.append(.special(fighter: i))
        } else if bossBrain.charge <= 0, distance > 3.6, distance < 10 {
            bossBrain.charge = 9.5
            fighters[i].lastAttack = time
            fighters[i].dash = Fighter.Dash(direction: toward, remaining: min(distance + 1.5, 9), hit: [])
            events.append(.special(fighter: i))
        } else if bossBrain.summon <= 0 {
            bossBrain.summon = 15
            summonTotems(i)
        } else if bossBrain.swing <= 0, distance < 3.2 {
            bossBrain.swing = 1.3
            fighters[i].lastAttack = time
            events.append(.attack(fighter: i))
            spread(i, toward, count: 5, angle: 1.2, speed: 12, range: 3.6, damage: 950, radius: 0.35)
        } else if bossBrain.volley <= 0, distance >= 3.2, distance < 10, map.lineOfSight(boss.pos, target.pos) {
            bossBrain.volley = 2.3
            fighters[i].lastAttack = time
            events.append(.attack(fighter: i))
            spread(i, toward, count: 3, angle: 0.36, speed: 11, range: 10, damage: 800, radius: 0.28)
        }
    }

    /// 骷髅王召唤两座骨塔，左右各一
    private mutating func summonTotems(_ i: Int) {
        let boss = fighters[i]
        let side = V2(-boss.facing.y, boss.facing.x)
        for k in [-1.0, 1.0] {
            let spot = map.nearestOpen(to: boss.pos + side * (2.2 * k), radius: Turret.radius)
            let health = power(i, 2500)
            turrets.append(Turret(id: nextTurret, owner: i, team: boss.team, pos: spot, facing: boss.facing,
                                  health: health, maxHealth: health, left: Turret.duration))
            nextTurret += 1
        }
        fighters[i].lastAttack = time
        events.append(.special(fighter: i))
    }
}
