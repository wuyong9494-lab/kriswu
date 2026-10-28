import Foundation

/// 电脑补位的人怎么打：找最近、看得见的敌人，保持在自己射程里横着绕着打，血少了往回跑；
/// 没看见敌人就去做这个玩法该做的事（捡星星、站圈、带球射门、打宝箱、往中间走躲毒圈）；地上的红圈会躲开
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
        guard game.fighters.indices.contains(id), game.result == nil, game.pause <= 0 else { return ArenaInput() }
        let me = game.fighters[id]
        // 骷髅王自己会打（规则里算），不用电脑操作
        guard me.alive, !me.busy, !me.isBoss else { return ArenaInput() }
        strafeTimer -= dt
        trigger -= dt
        repath -= dt
        if strafeTimer <= 0 {
            strafe = random.chance(0.5) ? 1 : -1
            strafeTimer = 0.8 + Double(random.below(120)) / 100
        }

        let enemies = game.fighters.filter { $0.alive && $0.team != me.team && game.isVisible($0, to: me.team) }
        // 对面带着球的人先打；不然在看得到的人里挑更好打的（近、残血、没被墙挡住、队友已经在打）
        let carrier = game.ball?.carrier.flatMap { game.fighters.indices.contains($0) ? game.fighters[$0] : nil }
        let nearby = enemies.filter { $0.pos.distance(to: me.pos) < 10 }
        let target = carrier.flatMap { $0.team != me.team && $0.alive && $0.pos.distance(to: me.pos) < 10 ? $0 : nil }
            ?? choose(me, among: nearby, in: game)
        var input = ArenaInput()
        var goal = objective(me, game)
        let carrying = game.ball?.carrier == id
        if carrying {
            // 带着球：往对面球门带，看得见球门、离得不远就射门；被人贴身就赶紧踢出去
            if let aim = shot(me, enemies, game) { input.attack = aim }
            if let aim = input.attack, me.superCharge >= 1, aim.length > 5 { input.special = aim }
        } else if let target, target.pos.distance(to: me.pos) < 10 {
            let distance = target.pos.distance(to: me.pos)
            let range = me.brawler.attackRange
            let away = (me.pos - target.pos).normalized
            // 悬赏高了打得小心点
            let careful = game.mode == .bounty && me.stars >= 5
            let low = Double(me.health) < Double(me.maxHealth) * (careful ? 0.5 : 0.3)
            let ideal = range * ([.barbarian, .knight, .guardian].contains(me.brawler) ? 0.55 : 0.75)
            let clear = me.brawler == .mage || game.map.lineOfSight(me.pos, target.pos)
            let ratio = Double(me.health) / Double(max(me.maxHealth, 1))
            let closeEnemies = enemies.filter { $0.pos.distance(to: me.pos) < 5.5 }
            let alone = !game.fighters.contains { $0.alive && $0.id != me.id && $0.team == me.team && $0.pos.distance(to: me.pos) < 7 }
            let outnumbered = closeEnemies.count >= 2 && alone && ratio < 0.75
            let meleeThreat = target.brawler.attackRange <= 3.6 && range >= 6 && distance < ideal * 0.9
            let reloading = me.ammo < 0.35
            if outnumbered {
                // 两个人围上来、身边没有队友：先撤，不站着换血
                let mid = closeEnemies.reduce(V2.zero) { $0 + $1.pos } * (1 / Double(closeEnemies.count))
                let off = me.pos - mid
                goal = me.pos + (off.length > 0.01 ? off.normalized : away) * 4
            } else if reloading && distance < range + 1 {
                goal = me.pos + away * 3.5
            } else if meleeThreat && !low {
                // 远程被近战贴住：拉开，不要跟他换
                goal = me.pos + away * 3
            } else if low && distance < range + 2.5 {
                // 血少了：往反方向跑，等着回血
                goal = me.pos + away * 4
            } else if !clear {
                // 墙挡住了：从侧面绕，不要顶着墙走
                let side = V2(-away.y, away.x) * strafe
                goal = target.pos + side * 3
            } else if distance > ideal {
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
            if me.superCharge >= 1 {
                switch me.brawler {
                case .guardian:
                    // 挨打了、敌人在跟前才举盾
                    if distance < 5, Double(me.health) < Double(me.maxHealth) * 0.7 { input.special = me.facing }
                case .summoner:
                    // 骨塔放在自己和敌人中间
                    if distance < 8 { input.special = (target.pos - me.pos) * 0.5 }
                case .shade:
                    // 血多的时候闪到敌人身边
                    if !low, distance > 2.5, distance <= me.brawler.superRange { input.special = target.pos - me.pos }
                case .necromancer:
                    if distance <= me.brawler.superRange * 0.9 { input.special = target.pos - me.pos }
                case .brewer:
                    // 血少了就喝
                    if Double(me.health) < Double(me.maxHealth) * 0.6 { input.special = me.facing }
                case .darter:
                    // 被贴近了、或者血少了放烟雾
                    if distance < 3 || low { input.special = me.facing }
                case .scholar:
                    // 身边有受伤的队友（或自己）就放护盾
                    if game.fighters.contains(where: { $0.alive && $0.team == me.team && $0.pos.distance(to: me.pos) <= me.brawler.superRange
                        && Double($0.health) < Double($0.maxHealth) * 0.7 }) { input.special = me.facing }
                default:
                    if distance <= me.brawler.superRange * 0.85, clear || me.brawler == .barbarian || me.brawler == .mage {
                        input.special = target.pos - me.pos
                    }
                }
            }
        }
        // 附近有对面的骨塔、又没有更近的敌人：先拆塔
        if !carrying, input.attack == nil, me.ammo >= 1, me.cooldown <= 0, trigger <= 0,
           let turret = game.turrets.filter({ $0.team != me.team }).min(by: { $0.pos.distance(to: me.pos) < $1.pos.distance(to: me.pos) }),
           turret.pos.distance(to: me.pos) <= me.brawler.attackRange * 0.95,
           me.brawler == .mage || game.map.lineOfSight(me.pos, turret.pos),
           target.map({ $0.pos.distance(to: me.pos) > turret.pos.distance(to: me.pos) }) ?? true {
            trigger = 0.3
            input.attack = turret.pos - me.pos
        }
        // 大乱斗：够得着能量箱、附近又没有敌人就打箱子
        if (game.mode == .showdown || game.mode == .duo), !game.map.inBush(me.pos), input.attack == nil, me.ammo >= 1, me.cooldown <= 0, trigger <= 0,
           target.map({ $0.pos.distance(to: me.pos) > 6 }) ?? true,
           let box = game.nearestBox(to: me.pos), box.pos.distance(to: me.pos) <= me.brawler.attackRange * 0.95,
           me.brawler == .mage || game.map.lineOfSight(me.pos, box.pos) {
            trigger = 0.3
            input.attack = box.pos - me.pos
        }
        // 宝箱攻防：够得着对面的宝箱、又没有更近的敌人就打宝箱
        if game.mode == .heist, !carrying, input.attack == nil, me.ammo >= 1, me.cooldown <= 0, trigger <= 0,
           let chest = game.chests.first(where: { $0.team != me.team && $0.health > 0 }) {
            let face = chest.center + (me.pos - chest.center).normalized * 1.3
            let distance = face.distance(to: me.pos)
            if distance <= me.brawler.attackRange * 0.95, me.brawler == .mage || game.map.lineOfSight(me.pos, face),
               target.map({ $0.pos.distance(to: me.pos) > distance }) ?? true {
                trigger = 0.3
                input.attack = chest.center - me.pos
            }
        }
        // 小道具：看情况用（逃跑、补血、近身的震开冻住）
        if me.gadgetUses > 0, me.gadgetCooldown <= 0, wantsGadget(me, target: target) {
            input.gadget = true
        }
        // 草丛：血少了钻进去；已经在草里、对面没进来，就蹲着打，不走出去暴露
        if !carrying {
            goal = cover(me, target: target, fallback: goal, in: game)
        }
        // 毒圈快到了：往中间走
        if game.mode.hasPoison, me.pos.distance(to: game.map.center) > game.safeRadius - 1.2 {
            goal = game.map.center
        }
        // 地上的红圈：赶紧走出去
        for warning in game.warnings where warning.team != me.team {
            let away = me.pos - warning.center
            if away.length < warning.radius + 0.7 {
                goal = warning.center + (away.length > 0.01 ? away.normalized : V2(1, 0)) * (warning.radius + 1.6)
            }
        }
        input.move = steer(me, to: goal, in: game)
        return input
    }

    /// 看得到的人里挑一个：更近、血更少、中间没墙、队友已经在打的，优先
    private func choose(_ me: Fighter, among enemies: [Fighter], in game: ArenaGame) -> Fighter? {
        enemies.min { score(me, $0, game) < score(me, $1, game) }
    }

    private func score(_ me: Fighter, _ enemy: Fighter, _ game: ArenaGame) -> Double {
        let distance = enemy.pos.distance(to: me.pos)
        let health = Double(enemy.health) / Double(max(enemy.maxHealth, 1))
        let blocked = (me.brawler == .mage || game.map.lineOfSight(me.pos, enemy.pos)) ? 0.0 : 5.0
        let focused = game.fighters.contains {
            $0.alive && $0.id != me.id && $0.team == me.team && $0.pos.distance(to: enemy.pos) < $0.brawler.attackRange + 1
        } ? -1.8 : 0
        return distance * 0.55 + health * 3.2 + blocked + focused
    }

    /// 现在该不该用小道具（翻滚、闪烁往摇杆方向：血少时摇杆正往回跑）
    private func wantsGadget(_ me: Fighter, target: Fighter?) -> Bool {
        guard let gadget = me.gadget else { return false }
        let distance = target.map { $0.pos.distance(to: me.pos) } ?? .infinity
        let health = Double(me.health) / Double(max(me.maxHealth, 1))
        switch gadget {
        case .potion: return health < 0.4
        case .ward: return health < 0.55 && distance < 5
        case .sprint, .roll, .vanish, .blink: return health < 0.35 && distance < 5
        case .reload: return me.ammo < 0.5 && distance < me.brawler.attackRange
        case .shockwave: return distance < 2.2
        case .frost: return distance < 2.8
        }
    }

    /// 带着球时往哪踢（不踢返回 nil）：看得见对面球门、离得不远就射门；被敌人贴身了往前踢
    private mutating func shot(_ me: Fighter, _ enemies: [Fighter], _ game: ArenaGame) -> V2? {
        guard trigger <= 0, let goal = game.map.goalCenters.indices.contains(1 - me.team) ? game.map.goalCenters[1 - me.team] : nil else {
            return nil
        }
        let toGoal = goal - me.pos
        let pressed = enemies.contains { $0.pos.distance(to: me.pos) < 2.2 }
        guard (toGoal.length < 7.5 && game.map.lineOfSight(me.pos, goal)) || pressed else { return nil }
        trigger = 0.4
        let noise = (Double(random.below(21)) - 10) / 150
        return toGoal.rotated(by: noise)
    }

    /// 血少了去旁边的草里躲。已经在草里、对面没走进来：人在射程里就蹲着打，不自己走出去
    private func cover(_ me: Fighter, target: Fighter?, fallback: V2, in game: ArenaGame) -> V2 {
        let ratio = Double(me.health) / Double(max(me.maxHealth, 1))
        if game.map.inBush(me.pos) {
            if let target, !game.map.sameBush(me.pos, target.pos) {
                let distance = target.pos.distance(to: me.pos)
                if distance <= me.brawler.attackRange || ratio < 0.45 { return me.pos }
            }
            return fallback
        }
        if ratio < 0.4, let bush = nearestBush(to: me.pos, map: game.map, within: 7) {
            return bush
        }
        return fallback
    }

    /// 附近最近的一格草（within 是最远找多远）
    private func nearestBush(to pos: V2, map: ArenaMap, within: Double) -> V2? {
        let x0 = max(0, Int((pos.x - within).rounded(.down)))
        let x1 = min(map.width - 1, Int((pos.x + within).rounded(.down)))
        let y0 = max(0, Int((pos.y - within).rounded(.down)))
        let y1 = min(map.height - 1, Int((pos.y + within).rounded(.down)))
        var best: V2?
        var bestDistance = within
        for y in y0...y1 {
            for x in x0...x1 where map.tile(x, y) == .bush {
                let spot = V2(Double(x) + 0.5, Double(y) + 0.5)
                let distance = spot.distance(to: pos)
                if distance < bestDistance {
                    bestDistance = distance
                    best = spot
                }
            }
        }
        return best
    }

    /// 没在打架时去哪
    private func objective(_ me: Fighter, _ game: ArenaGame) -> V2 {
        let center = game.map.center
        let home = game.map.spawns.indices.contains(me.team) ? (game.map.spawns[me.team].first ?? center) : center
        switch game.mode {
        case .stars:
            if let countdown = game.countdown, countdown.team == me.team, me.stars > 0 { return home }
            return game.stars.min { $0.distance(to: me.pos) < $1.distance(to: me.pos) } ?? center
        case .showdown:
            return powerObjective(me, game) ?? center
        case .zone, .duel:
            return center
        case .teamFight, .bounty:
            let enemyHome = game.map.spawns.indices.contains(1 - me.team) ? (game.map.spawns[1 - me.team].first ?? center) : center
            return V2.lerp(center, enemyHome, 0.3)
        case .knockout:
            return V2.lerp(home, center, 0.6)
        case .duo:
            // 跟着队友，别走散
            if let mate = game.fighters.first(where: { $0.team == me.team && $0.id != me.id && $0.alive }),
               mate.pos.distance(to: me.pos) > 4 {
                return mate.pos
            }
            return powerObjective(me, game) ?? center
        case .ball:
            return ballObjective(me, game)
        case .heist:
            guard let chest = game.chests.first(where: { $0.team != me.team }) else { return center }
            // 一个人守家，其余的去打对面的宝箱（站在射程里）
            if me.id % 3 == 2, let own = game.chests.first(where: { $0.team == me.team }) {
                return V2.lerp(own.center, center, 0.35)
            }
            let toward = (me.pos - chest.center).normalized
            return chest.center + toward * (me.brawler.attackRange * 0.7 + 1)
        case .boss:
            guard let boss = game.fighters.first(where: { $0.isBoss && $0.alive }) else { return center }
            return boss.pos + (me.pos - boss.pos).normalized * (me.brawler.attackRange * 0.75)
        }
    }

    /// 大乱斗：毒圈还没逼过来时去捡地上的能量块，没有就去打最近的能量箱（站在射程里）
    private func powerObjective(_ me: Fighter, _ game: ArenaGame) -> V2? {
        let safe = { (point: V2) in point.distance(to: game.map.center) < game.safeRadius - 1.5 }
        if let cube = game.nearestCube(to: me.pos), safe(cube.pos), cube.pos.distance(to: me.pos) < 9 { return cube.pos }
        guard let box = game.nearestBox(to: me.pos), safe(box.pos) else { return nil }
        let toward = (me.pos - box.pos).normalized
        return box.pos + (toward.length > 0 ? toward : V2(1, 0)) * min(me.brawler.attackRange * 0.7, 3)
    }

    /// 足球：自己带着球就去对面球门；队友带着跟在前面接应；对面带着去抢；球没人带离得最近的去捡，其余的守在球和自己球门中间
    private func ballObjective(_ me: Fighter, _ game: ArenaGame) -> V2 {
        let center = game.map.center
        let goals = game.map.goalCenters
        let ownGoal = (goals.indices.contains(me.team) ? goals[me.team] : nil) ?? center
        let enemyGoal = (goals.indices.contains(1 - me.team) ? goals[1 - me.team] : nil) ?? center
        guard let ball = game.ball else { return center }
        if let carrier = ball.carrier, game.fighters.indices.contains(carrier) {
            let holder = game.fighters[carrier]
            if carrier == me.id { return enemyGoal }
            return holder.team == me.team ? V2.lerp(holder.pos, enemyGoal, 0.35) : holder.pos
        }
        let mates = game.fighters.filter { $0.team == me.team && $0.alive }
        let closest = mates.min { $0.pos.distance(to: ball.pos) < $1.pos.distance(to: ball.pos) }
        return closest?.id == me.id ? ball.pos : V2.lerp(ball.pos, ownGoal, 0.45)
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
