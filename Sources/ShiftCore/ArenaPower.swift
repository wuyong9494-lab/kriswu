import Foundation

// 大乱斗、双人大乱斗的能量箱：场上散着几个能量箱，打碎了掉出一个能量块；走过去捡起来，每块血多 400、伤害多一成。
// 被打倒的人身上的能量块全掉在地上，谁捡到算谁的。能量箱挡路，子弹、爆炸都能打它。

extension ArenaGame {
    /// 能量箱
    public struct PowerBox: Equatable, Sendable {
        public var pos: V2
        public var health: Int
        public static let fullHealth = 3600
        public static let radius = 0.46
    }

    /// 地上的能量块（几块叠在一起）
    public struct PowerCube: Equatable, Sendable {
        public var pos: V2
        public var count: Int
    }

    /// 每块能量多多少血、多几成伤害
    public static let cubeHealth = 400
    public static let cubeDamage = 0.1
    /// 一局几个能量箱
    static let boxCount = 10

    /// 开局放能量箱：不贴墙、不在草丛里、离出生点和中间都远一点，同一个种子放的一样（联机时大家一样）
    mutating func setUpBoxes() {
        let spawns = map.spawns.flatMap { $0 }
        var spots: [V2] = []
        for y in 1..<(map.height - 1) {
            for x in 1..<(map.width - 1) {
                let p = V2(Double(x) + 0.5, Double(y) + 0.5)
                guard map.tile(x, y) == .floor, !map.collides(p, radius: 0.6),
                      spawns.allSatisfy({ $0.distance(to: p) > 2.6 }), p.distance(to: map.center) > 1.5 else { continue }
                spots.append(p)
            }
        }
        random.shuffle(&spots)
        var chosen: [V2] = []
        for spot in spots where chosen.allSatisfy({ $0.distance(to: spot) > 3 }) {
            chosen.append(spot)
            if chosen.count == Self.boxCount { break }
        }
        boxes = chosen.map { PowerBox(pos: $0, health: PowerBox.fullHealth) }
    }

    /// 能量箱挨打；打碎了掉出一个能量块
    mutating func hitBox(_ b: Int, _ amount: Int) {
        guard boxes.indices.contains(b), boxes[b].health > 0 else { return }
        boxes[b].health = max(0, boxes[b].health - max(amount, 0))
        if boxes[b].health == 0 {
            cubes.append(PowerCube(pos: boxes[b].pos, count: 1))
            events.append(.explosion(at: boxes[b].pos, radius: 0.7))
        }
    }

    /// 走过去捡能量块：血上限、现在的血都多
    mutating func collectCubes() {
        guard !cubes.isEmpty else { return }
        for i in fighters.indices where fighters[i].alive && !fighters[i].busy && !fighters[i].isBoss {
            let position = fighters[i].pos
            var picked = 0
            cubes.removeAll { cube in
                guard cube.pos.distance(to: position) < 0.75 else { return false }
                picked += cube.count
                return true
            }
            guard picked > 0 else { continue }
            fighters[i].cubes += picked
            fighters[i].health = min(fighters[i].maxHealth, fighters[i].health + picked * Self.cubeHealth)
            events.append(.pickup(fighter: i))
        }
    }

    /// 走的时候绕开没碎的能量箱（贴着箱子边停下；推出去会撞墙就不动）
    func blockedByBoxes(_ start: V2, _ next: V2) -> V2 {
        let gap = Self.fighterRadius + PowerBox.radius
        func clear(_ point: V2) -> Bool {
            !map.collides(point, radius: Self.fighterRadius) &&
                !boxes.contains { $0.health > 0 && point.distance(to: $0.pos) < gap - 1e-9 }
        }
        func slide() -> V2 {
            let horizontal = V2(next.x, start.y), vertical = V2(start.x, next.y)
            let xOK = clear(horizontal), yOK = clear(vertical)
            if xOK && yOK {
                return abs(next.x - start.x) >= abs(next.y - start.y) ? horizontal : vertical
            }
            if xOK { return horizontal }
            if yOK { return vertical }
            return start
        }
        var position = next
        for box in boxes where box.health > 0 {
            let away = position - box.pos
            guard away.length < gap else { continue }
            let push = away.length > 1e-6 ? away.normalized : (start - box.pos).normalized
            position = box.pos + (push.length > 0 ? push : V2(1, 0)) * gap
            if map.collides(position, radius: Self.fighterRadius) { return slide() }
        }
        // A later box can push the fighter back into an earlier one.
        return clear(position) ? position : slide()
    }

    /// 离这一点最近的、还没碎的能量箱，地上最近的能量块（电脑找东西捡用）
    func nearestBox(to point: V2) -> PowerBox? {
        boxes.filter { $0.health > 0 }.min { $0.pos.distance(to: point) < $1.pos.distance(to: point) }
    }

    func nearestCube(to point: V2) -> PowerCube? {
        cubes.min { $0.pos.distance(to: point) < $1.pos.distance(to: point) }
    }
}
