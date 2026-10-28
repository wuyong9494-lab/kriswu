import XCTest
@testable import ShiftCore

/// 大乱斗的能量箱、能量块
final class ArenaPowerTests: XCTestCase {
    private let dt = 1.0 / 60

    private func showdown(seed: UInt64) -> ArenaGame {
        ArenaGame(mode: .showdown, entrants: (0..<6).map {
            ArenaGame.Entrant(name: "电脑\($0)", brawler: Brawler.allCases[$0 % 5], isBot: true, team: $0)
        }, seed: seed)
    }

    /// 开局放好能量箱（同一个种子放的一样，不贴墙）；打碎掉一个能量块，捡了血和伤害都多；倒下的人能量块全掉出来
    func testBoxesDropCubesThatMakeYouStronger() throws {
        var game = showdown(seed: 4)
        XCTAssertEqual(game.boxes.count, ArenaGame.boxCount)
        XCTAssertEqual(showdown(seed: 4).boxes, game.boxes, "同一个种子放的一样")
        for box in game.boxes {
            XCTAssertFalse(game.map.collides(box.pos, radius: 0.5))
            XCTAssertEqual(box.health, ArenaGame.PowerBox.fullHealth)
        }
        XCTAssertTrue(ArenaGame(mode: .teamFight, entrants: [], seed: 4).boxes.isEmpty, "只有大乱斗有")

        let box = game.boxes[0]
        game.hitBox(0, 1000)
        XCTAssertEqual(game.boxes[0].health, ArenaGame.PowerBox.fullHealth - 1000)
        XCTAssertTrue(game.cubes.isEmpty)
        game.hitBox(0, ArenaGame.PowerBox.fullHealth)
        XCTAssertEqual(game.boxes[0].health, 0)
        XCTAssertEqual(game.cubes, [ArenaGame.PowerCube(pos: box.pos, count: 1)])

        let health = game.fighters[0].maxHealth
        XCTAssertEqual(game.power(0, 1000), 1000)
        game.adjust(0) { $0.pos = box.pos + V2(0.3, 0) }
        game.collectCubes()
        XCTAssertEqual(game.fighters[0].cubes, 1)
        XCTAssertTrue(game.cubes.isEmpty)
        XCTAssertEqual(game.fighters[0].maxHealth, health + ArenaGame.cubeHealth)
        XCTAssertEqual(game.power(0, 1000), 1100, "伤害多一成")
        XCTAssertTrue(game.events.contains(.pickup(fighter: 0)))

        game.adjust(0) { $0.cubes = 3 }
        let spot = game.fighters[0].pos
        game.hurt(0, 1_000_000, by: 1, charges: false)
        XCTAssertFalse(game.fighters[0].alive)
        XCTAssertEqual(game.fighters[0].cubes, 0)
        let dropped = try XCTUnwrap(game.cubes.first)
        XCTAssertEqual(dropped.count, 3, "倒下的人的能量块全掉出来")
        XCTAssertEqual(dropped.pos, spot)
    }

    /// 草外看不见草里的人；自己走进去，或者对方开火，才露出来
    func testBushHidesUntilYouEnterOrTheyShoot() {
        var game = showdown(seed: 2)
        var bush: V2?
        var outside: V2?
        for y in 0..<game.map.height {
            for x in 0..<game.map.width {
                let spot = V2(Double(x) + 0.5, Double(y) + 0.5)
                if game.map.tile(x, y) == .bush, bush == nil { bush = spot }
                if game.map.tile(x, y) == .floor, !game.map.collides(spot, radius: 0.4), outside == nil { outside = spot }
            }
        }
        let bushSpot = bush, outsideSpot = outside
        XCTAssertNotNil(bushSpot)
        XCTAssertNotNil(outsideSpot)
        guard let bushSpot, let outsideSpot else { return }
        game.adjust(0) { $0.pos = bushSpot; $0.lastAttack = -10 }
        game.adjust(1) { $0.pos = outsideSpot }
        XCTAssertFalse(game.isVisible(game.fighters[0], to: 1), "站在草外看不见")
        game.adjust(1) { $0.pos = bushSpot }
        XCTAssertTrue(game.isVisible(game.fighters[0], to: 1), "走进同一丛草就看得见")
        game.adjust(1) { $0.pos = outsideSpot }
        let now = game.time
        game.adjust(0) { $0.lastAttack = now }
        XCTAssertTrue(game.isVisible(game.fighters[0], to: 1), "开火就露出来")
    }

    /// 连成一片的草两头也能看见；中间隔开的两丛，站得很近也看不见
    func testBushVisionFollowsTheConnectedPatch() {
        let map = ArenaMap(rows: [
            "o........o",
            "..........",
            ".********.",
            "..........",
            "..*..*....",
        ])
        var game = ArenaGame(mode: .showdown, entrants: [
            ArenaGame.Entrant(name: "甲", brawler: .knight, isBot: true, team: 0),
            ArenaGame.Entrant(name: "乙", brawler: .ranger, isBot: true, team: 1),
        ], seed: 1, map: map)
        XCTAssertEqual(game.map.width, 10, "用的是这张图")
        game.adjust(0) { $0.pos = V2(1.5, 2.5); $0.lastAttack = -10 }
        game.adjust(1) { $0.pos = V2(8.5, 2.5); $0.lastAttack = -10 }
        XCTAssertTrue(game.map.sameBush(V2(1.5, 2.5), V2(8.5, 2.5)))
        XCTAssertTrue(game.isVisible(game.fighters[0], to: 1), "同一片草的两头互相看得见")
        game.adjust(0) { $0.pos = V2(2.5, 4.5) }
        game.adjust(1) { $0.pos = V2(5.5, 4.5) }
        XCTAssertFalse(game.map.sameBush(game.fighters[0].pos, game.fighters[1].pos))
        XCTAssertFalse(game.isVisible(game.fighters[0], to: 1), "隔开的两丛，站得近也看不见")
    }

    /// 血少了、旁边有草：电脑会往草里走，而不是站在空地上
    func testHurtBotStepsTowardABush() {
        let map = ArenaMap(rows: [
            "o.........",
            "..........",
            "..**......",
        ])
        var game = ArenaGame(mode: .showdown, entrants: [
            ArenaGame.Entrant(name: "甲", brawler: .knight, isBot: true, team: 0),
        ], seed: 1, map: map)
        game.adjust(0) { $0.pos = V2(7.5, 1.5); $0.health = 200 }
        var bot = ArenaBot(id: 0, seed: 1)
        let input = bot.input(in: game, dt: 0.05)
        XCTAssertLessThan(input.move.x, -0.3, "往左边的草走")
    }

    /// 残血的人站得稍远，也比贴脸的满血更该打
    func testBotAimsAtTheWeakerEnemy() {
        let map = ArenaMap(rows: ["o...............", "................"])
        var game = ArenaGame(mode: .showdown, entrants: [
            ArenaGame.Entrant(name: "我", brawler: .ranger, isBot: true, team: 0),
            ArenaGame.Entrant(name: "满", brawler: .knight, isBot: true, team: 1),
            ArenaGame.Entrant(name: "残", brawler: .knight, isBot: true, team: 2),
        ], seed: 1, map: map)
        game.adjust(0) { $0.pos = V2(1.5, 0.5) }
        game.adjust(1) { $0.pos = V2(4.5, 0.5) }
        game.adjust(2) { $0.pos = V2(8.5, 0.5); $0.health = 80 }
        var bot = ArenaBot(id: 0, seed: 3)
        let aim = bot.input(in: game, dt: 0.05).attack
        XCTAssertGreaterThan(aim?.length ?? 0, 4.5, "打较远的那个残血，不是贴脸的满血")
    }

    /// 远程被近战贴住要往回走
    func testRangedBotKitesAMelee() {
        let map = ArenaMap(rows: ["o...............", "................"])
        var game = ArenaGame(mode: .showdown, entrants: [
            ArenaGame.Entrant(name: "我", brawler: .ranger, isBot: true, team: 0),
            ArenaGame.Entrant(name: "斧", brawler: .barbarian, isBot: true, team: 1),
        ], seed: 1, map: map)
        game.adjust(0) { $0.pos = V2(6.5, 0.5) }
        game.adjust(1) { $0.pos = V2(7.8, 0.5) }
        var bot = ArenaBot(id: 0, seed: 2)
        let move = bot.input(in: game, dt: 0.05).move
        XCTAssertLessThan(move.x, -0.4, "往离斧头远的方向退")
    }

    /// 一个人被两个敌人贴住，血又不满：先撤
    func testLoneBotRetreatsFromTwo() {
        let map = ArenaMap(rows: ["o.........", "..........", ".........."])
        var game = ArenaGame(mode: .showdown, entrants: [
            ArenaGame.Entrant(name: "我", brawler: .knight, isBot: true, team: 0),
            ArenaGame.Entrant(name: "甲", brawler: .knight, isBot: true, team: 1),
            ArenaGame.Entrant(name: "乙", brawler: .ranger, isBot: true, team: 2),
        ], seed: 1, map: map)
        game.adjust(0) { $0.pos = V2(4.5, 1.5); $0.health = Int(Double(game.fighters[0].maxHealth) * 0.6) }
        game.adjust(1) { $0.pos = V2(5.8, 1.5) }
        game.adjust(2) { $0.pos = V2(4.5, 2.8) }
        var bot = ArenaBot(id: 0, seed: 4)
        let move = bot.input(in: game, dt: 0.05).move
        XCTAssertLessThan(move.x + move.y, -0.2, "朝两个敌人的反方向撤")
    }

    /// 子弹、爆炸都打得到能量箱；人走不进箱子里
    func testBoxesTakeHitsAndBlockWalking() throws {
        var game = showdown(seed: 9)
        let box = game.boxes[1]
        game.blast(at: box.pos, radius: 1, damage: 500, by: 0, team: 0, charges: false)
        XCTAssertEqual(game.boxes[1].health, ArenaGame.PowerBox.fullHealth - 500)

        let start = box.pos + V2(1.4, 0)
        game.adjust(2) { $0.pos = start }
        for _ in 0..<40 { game.walk(2, by: V2(-0.05, 0)) }
        XCTAssertGreaterThanOrEqual(game.fighters[2].pos.distance(to: box.pos), ArenaGame.fighterRadius + ArenaGame.PowerBox.radius - 1e-6,
                                    "贴着箱子边停下")
    }

    /// 电脑会去打能量箱、捡能量块；联机时能量箱、能量块、每个人捡了几块都发得过去，老版本的包也读得出来
    func testBotsGoForCubesAndTheyCrossTheNetwork() throws {
        var game = showdown(seed: 12)
        var bots = game.fighters.map { ArenaBot(id: $0.id, seed: 12) }
        // 打到有箱子碎了为止（最多 90 秒）
        while game.result == nil && game.time < 90 && game.boxes.allSatisfy({ $0.health > 0 }) {
            var inputs: [Int: ArenaInput] = [:]
            for k in bots.indices { inputs[bots[k].id] = bots[k].input(in: game, dt: dt) }
            game.step(dt, inputs: inputs)
            game.events.removeAll()
        }
        XCTAssertLessThan(game.boxes.filter { $0.health > 0 }.count, ArenaGame.boxCount, "打碎过箱子")
        XCTAssertGreaterThan(game.fighters.map(\.cubes).reduce(0, +) + game.cubes.map(\.count).reduce(0, +), 0, "有能量块")

        let snapshot = try XCTUnwrap(ArenaSnapshot(data: game.snapshot(events: []).encoded()))
        XCTAssertEqual(snapshot.boxes.map(\.health), game.boxes.map(\.health))
        XCTAssertEqual(snapshot.cubes.map(\.count), game.cubes.map(\.count))
        XCTAssertEqual(snapshot.fighters.map(\.cubes), game.fighters.map(\.cubes))
        var client = showdown(seed: 12)
        client.apply(snapshot)
        XCTAssertEqual(client.fighters.map(\.cubes), game.fighters.map(\.cubes))
        XCTAssertEqual(client.fighters.map(\.maxHealth), game.fighters.map(\.maxHealth))
        let old = try XCTUnwrap(ArenaSnapshot(data: game.snapshot(events: []).encoded(version: 4)))
        XCTAssertTrue(old.boxes.isEmpty)
    }
}
