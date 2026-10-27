import Foundation

/// 电脑补位的人怎么打：找最近、看得见的敌人，保持在自己射程里横着绕着打，血少了往回跑；
/// 没看见敌人就去做这个玩法该做的事（捡星星、站圈、往中间走躲毒圈）
public struct ArenaBot: Sendable {
    public let id: Int
    private var random: SeededRandom
    private var path: [V2] = []
    private var pathGoal: V2?
    private var repath = 0.0
    private var strafe = 1.0
    private var strafeTimer = 0.0
    /// 反应慢一点：开一枪后过一小会才开下一枪
    private var trigger = 0.0

    public init(id: Int, seed: UInt64) {
        self.id = id
        random = SeededRandom(seed: seed &+ UInt64(id + 1) &* 7919)
    }

    public mutating func input(in game: ArenaGame, dt: Double) -> ArenaInput {
        guard game.fighters.indices.contains(id), game.result == nil else { return ArenaInput() }
        let me = game.fighters[id]
        guard me.alive, !me.busy else { return ArenaInput() }
        strafeTimer -= dt
        trigger -= dt
        repath -= dt
        if strafeTimer <= 0 {
            strafe = random.chance(0.5) ? 1 : -1
            strafeTimer = 0.8 + Double(random.below(120)) / 100
        }

        let enemies = game.fighters.filter { $0.alive && $0.team != me.team && game.isVisible($0, to: me.team) }
        let target = enemies.min { $0.pos.distance(to: me.pos) < $1.pos.distance(to: me.pos) }
        var input = ArenaInput()
        var goal = objective(me, game)
        if let target, target.pos.distance(to: me.pos) < 10 {
            let distance = target.pos.distance(to: me.pos)
            let range = me.brawler.attackRange
            let away = (me.pos - target.pos).normalized
            let low = Double(me.health) < Double(me.maxHealth) * 0.3
            let ideal = range * (me.brawler == .barbarian || me.brawler == .knight ? 0.55 : 0.75)
            let clear = me.brawler == .mage || game.map.lineOfSight(me.pos, target.pos)
            if low && distance < range + 2.5 {
                // 血少了：往反方向跑，等着回血
                goal = me.pos + away * 4
            } else if distance > ideal || !clear {
                goal = target.pos
            } else {
                // 在射程里：横着绕，太近了往后退一点
                let side = V2(-away.y, away.x) * strafe
                goal = me.pos + side * 2 + away * (ideal - distance)
            }
            if clear, distance <= range * 0.97, me.ammo >= 1, me.cooldown <= 0, trigger <= 0 {
                trigger = 0.25 + Double(random.below(30)) / 100
                let travel = distance / me.brawler.bulletSpeed
                let lead = target.pos + target.moving * (travel * 0.7)
                let noise = (Double(random.below(21)) - 10) / 100
                input.attack = (lead - me.pos).rotated(by: noise)
            }
            if me.superCharge >= 1, distance <= me.brawler.superRange * 0.85,
               clear || me.brawler == .barbarian || me.brawler == .mage {
                input.special = target.pos - me.pos
            }
        }
        input.move = steer(me, to: goal, in: game)
        return input
    }

    /// 没在打架时去哪
    private func objective(_ me: Fighter, _ game: ArenaGame) -> V2 {
        let center = game.map.center
        switch game.mode {
        case .stars:
            let home = game.map.spawns[me.team].first ?? center
            if let countdown = game.countdown, countdown.team == me.team, me.stars > 0 { return home }
            return game.stars.min { $0.distance(to: me.pos) < $1.distance(to: me.pos) } ?? center
        case .zone, .showdown:
            return center
        case .teamFight:
            let enemyHome = game.map.spawns[1 - me.team].first ?? center
            return V2.lerp(center, enemyHome, 0.3)
        }
    }

    /// 朝 goal 走：一路上没有墙就直走，不然按格子绕
    private mutating func steer(_ me: Fighter, to goal: V2, in game: ArenaGame) -> V2 {
        let map = game.map
        let target = map.nearestOpen(to: goal, radius: ArenaGame.fighterRadius)
        if target.distance(to: me.pos) < 0.3 { return .zero }
        if open(from: me.pos, to: target, map) { return (target - me.pos).normalized }
        if repath <= 0 || (pathGoal.map { $0.distance(to: target) > 1 } ?? true) {
            path = map.path(from: me.pos, to: target)
            pathGoal = target
            repath = 0.5
        }
        while let next = path.first, next.distance(to: me.pos) < 0.35 { path.removeFirst() }
        guard let next = path.first else { return (target - me.pos).normalized }
        return (next - me.pos).normalized
    }

    /// 一个人能不能沿直线走过去（身子不蹭墙）
    private func open(from a: V2, to b: V2, _ map: ArenaMap) -> Bool {
        let distance = a.distance(to: b)
        let steps = max(1, Int(distance / 0.3))
        for k in 1...steps where map.collides(V2.lerp(a, b, Double(k) / Double(steps)), radius: ArenaGame.fighterRadius) {
            return false
        }
        return true
    }
}
