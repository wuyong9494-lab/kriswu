import XCTest
@testable import ShiftCore

/// 后加的几种玩法：足球、宝箱攻防、悬赏、三局两胜、双人大乱斗、一对一、讨伐骷髅王
final class ArenaModesTests: XCTestCase {
    private let dt = 1.0 / 60

    private func run(_ game: inout ArenaGame, seconds: Double, inputs: [Int: ArenaInput] = [:]) {
        for _ in 0..<Int((seconds / dt).rounded()) where game.result == nil {
            game.step(dt, inputs: inputs)
        }
    }

    private func pair(_ mine: Brawler, _ theirs: Brawler, lineup: [Brawler] = []) -> [ArenaGame.Entrant] {
        [.init(name: "我", brawler: mine, isBot: false, team: 0, lineup: lineup),
         .init(name: "敌", brawler: theirs, isBot: true, team: 1)]
    }

    // MARK: 足球

    /// 走到球边上就捡起来；攻击键踢出去，滚进对面球门进 1 球；停一会儿大家回去重新开球，先进 2 球的赢
    func testBallPickupKickAndGoal() throws {
        var game = ArenaGame(mode: .ball, entrants: pair(.ranger, .barbarian), seed: 1)
        XCTAssertEqual(game.map.id, "pitch")
        let center = game.map.center
        XCTAssertEqual(game.ball?.pos, center)
        let topGoal = try XCTUnwrap(game.map.goalCenters[1])
        XCTAssertLessThan(topGoal.y, 1, "上边一队守的门在最上面")
        game.adjust(0) { $0.pos = center + V2(0, 0.6) }
        game.adjust(1) { $0.pos = V2(1.5, 12.5) }
        game.step(dt, inputs: [:])
        XCTAssertEqual(game.ball?.carrier, 0, "走到球边上就捡起来")
        XCTAssertTrue(game.events.contains(.pickup(fighter: 0)))

        // 带着球不开枪：攻击键是踢球
        game.adjust(0) { $0.pos = V2(7.5, 2.6) }
        game.step(dt, inputs: [0: ArenaInput(attack: V2(0, -1))])
        XCTAssertNil(game.ball?.carrier)
        XCTAssertTrue(game.projectiles.isEmpty, "踢球不开枪")
        XCTAssertEqual(game.fighters[0].ammo, 3, accuracy: 0.01, "踢球不用子弹")
        run(&game, seconds: 0.5)
        XCTAssertEqual(game.score, [1, 0])
        XCTAssertTrue(game.events.contains(.goal(team: 0)))
        XCTAssertGreaterThan(game.pause, 0, "进球后停一会儿")
        XCTAssertNil(game.result)
        run(&game, seconds: ArenaGame.breakTime)
        XCTAssertEqual(game.pause, 0)
        XCTAssertTrue(game.events.contains(.reset))
        XCTAssertEqual(game.ball?.pos, center, "球放回中间")
        XCTAssertEqual(game.fighters[0].pos, game.map.spawns[0][0], "回到出发的地方")
        XCTAssertEqual(game.fighters[1].pos, game.map.spawns[1][0])

        // 再进一球就赢了
        game.adjust(0) { $0.pos = center + V2(0, 0.6) }
        game.step(dt, inputs: [:])
        game.adjust(0) { $0.pos = V2(7.5, 2.6) }
        game.step(dt, inputs: [0: ArenaInput(attack: V2(0, -1))])
        run(&game, seconds: 0.5)
        XCTAssertEqual(game.result, .team(0))
    }

    /// 人进不了球门（球进得去）；带球的人被打倒，球掉在地上；大招大力踢
    func testGoalsBlockFightersAndCarrierDropsBall() {
        var game = ArenaGame(mode: .ball, entrants: pair(.ranger, .barbarian), seed: 2)
        game.adjust(1) { $0.pos = V2(7.5, 2.0) }
        run(&game, seconds: 1.5, inputs: [1: ArenaInput(move: V2(0, -1))])
        XCTAssertGreaterThanOrEqual(game.fighters[1].pos.y, 1 + ArenaGame.fighterRadius - 1e-6, "走不进球门")
        XCTAssertEqual(game.map.goalTeam(at: V2(7.5, 0.5)), 1)
        XCTAssertNil(game.map.goalTeam(at: V2(7.5, 1.5)))

        let center = game.map.center
        game.adjust(0) { $0.pos = center + V2(0, 0.6); $0.superCharge = 1 }
        game.step(dt, inputs: [:])
        XCTAssertEqual(game.ball?.carrier, 0)
        game.step(dt, inputs: [0: ArenaInput(special: V2(1, 0))])
        XCTAssertEqual(game.ball?.velocity.x ?? 0, 17, accuracy: 0.5, "大招踢得快")
        XCTAssertEqual(game.fighters[0].superCharge, 0)

        var again = ArenaGame(mode: .ball, entrants: pair(.ranger, .barbarian), seed: 3)
        again.adjust(0) { $0.pos = center + V2(0, 0.6) }
        again.step(dt, inputs: [:])
        XCTAssertEqual(again.ball?.carrier, 0)
        again.knockOut(0, by: 1)
        XCTAssertNil(again.ball?.carrier, "带球的人倒下，球掉在地上")
        XCTAssertEqual(again.fighters[0].respawnIn, ArenaGame.Mode.ball.respawnDelay)
    }

    // MARK: 宝箱攻防

    /// 和 App 里自己和电脑打一样：自己站着不动，其余五个电脑；两张图、几个种子都打得下去
    func testHeistWithAnIdlePlayer() {
        let others = Brawler.allCases.filter { $0 != .mage }
        for seed in UInt64(1)...6 {
            for map in ArenaMap.pool(for: .heist) {
                var entrants = [ArenaGame.Entrant(name: "我", brawler: .mage, isBot: false, team: 0)]
                for k in 1..<6 {
                    entrants.append(.init(name: "电脑\(k)", brawler: others[(k + Int(seed)) % others.count], isBot: true, team: k < 3 ? 0 : 1))
                }
                var game = ArenaGame(mode: .heist, entrants: entrants, seed: seed, map: map)
                var bots = game.fighters.filter(\.isBot).map { ArenaBot(id: $0.id, seed: seed) }
                while game.result == nil && game.time < 60 {
                    var inputs: [Int: ArenaInput] = [:]
                    for k in bots.indices { inputs[bots[k].id] = bots[k].input(in: game, dt: dt) }
                    game.step(dt, inputs: inputs)
                    game.events.removeAll()
                }
                XCTAssertEqual(game.chests.count, 2, map.id)
                XCTAssertTrue(game.fighters.allSatisfy { $0.pos.x.isFinite && $0.pos.y.isFinite }, map.id)
            }
        }
    }

    /// 打对面的宝箱扣它的血（算在打的人伤害里），打爆了就赢；时间到了比宝箱剩几成血
    func testHeistChestDamageAndWin() {
        var game = ArenaGame(mode: .heist, entrants: pair(.ranger, .barbarian), seed: 4)
        XCTAssertEqual(game.map.id, "vault")
        XCTAssertEqual(game.chests.map(\.team), [1, 0], "上边的宝箱是上边一队的")
        XCTAssertEqual(game.chests[0].center, V2(7.5, 3.0))
        XCTAssertTrue(game.map.isChest(7, 3))
        game.adjust(0) { $0.pos = V2(7.5, 8.5) }
        game.adjust(1) { $0.pos = V2(1.5, 12.5) }
        game.step(dt, inputs: [0: ArenaInput(attack: V2(0, -1))])
        run(&game, seconds: 0.6)
        XCTAssertEqual(game.chests[0].health, ArenaGame.Chest.fullHealth - 1300)
        XCTAssertEqual(game.fighters[0].damageDealt, 1300)
        XCTAssertTrue(game.events.contains(.chestHit(chest: 0, amount: 1300)))
        game.chests[0].health = 1000
        run(&game, seconds: 1.5)
        game.step(dt, inputs: [0: ArenaInput(attack: V2(0, -1))])
        run(&game, seconds: 0.6)
        XCTAssertEqual(game.chests[0].health, 0)
        XCTAssertEqual(game.result, .team(0))

        var timed = ArenaGame(mode: .heist, entrants: pair(.ranger, .barbarian), seed: 5)
        timed.chests[1].health = 20000
        run(&timed, seconds: ArenaGame.Mode.heist.duration + 0.5)
        XCTAssertEqual(timed.result, .team(1), "时间到了：下边一队的宝箱血少，上边一队赢")
    }

    // MARK: 悬赏

    /// 一开始每人 2 颗星；打倒一个敌人按他的悬赏给队里加分，自己的悬赏 +1；被打倒的回到 2 颗；星星不掉在地上
    func testBountyTransfersStars() {
        var game = ArenaGame(mode: .bounty, entrants: pair(.ranger, .mage), seed: 6)
        XCTAssertEqual(game.fighters.map(\.stars), [2, 2])
        game.adjust(0) { $0.pos = V2(3.5, 20.5) }
        game.adjust(1) { $0.pos = V2(3.5, 14.5); $0.health = 1000; $0.stars = 4 }
        game.step(dt, inputs: [0: ArenaInput(attack: V2(0, -1))])
        run(&game, seconds: 0.6)
        XCTAssertFalse(game.fighters[1].alive)
        XCTAssertEqual(game.score, [4, 0])
        XCTAssertEqual(game.fighters[0].stars, 3)
        XCTAssertEqual(game.fighters[1].stars, ArenaGame.startingBounty)
        XCTAssertTrue(game.stars.isEmpty, "悬赏的星星不掉在地上")
        run(&game, seconds: ArenaGame.respawnDelay)
        XCTAssertTrue(game.fighters[1].alive, "悬赏玩法会复活")
        game.adjust(0) { $0.stars = ArenaGame.maxBounty }
        game.knockOut(1, by: 0)
        XCTAssertEqual(game.fighters[0].stars, ArenaGame.maxBounty, "最多 7 颗")
        XCTAssertEqual(game.score, [6, 0])
        run(&game, seconds: ArenaGame.Mode.bounty.duration)
        XCTAssertEqual(game.result, .team(0))
    }

    // MARK: 三局两胜

    /// 一队全倒下这一局就分出来：不复活，停一会儿大家回去开下一局；先赢两局的赢
    func testKnockoutRounds() {
        var game = ArenaGame(mode: .knockout, entrants: pair(.ranger, .mage), seed: 7)
        XCTAssertEqual(game.round, 1)
        XCTAssertEqual(game.timeLeft, ArenaGame.roundLimit, accuracy: 0.01)
        game.adjust(0) { $0.pos = V2(3.5, 20.5) }
        game.adjust(1) { $0.pos = V2(3.5, 14.5); $0.health = 1000 }
        game.step(dt, inputs: [0: ArenaInput(attack: V2(0, -1))])
        run(&game, seconds: 0.6)
        XCTAssertEqual(game.score, [1, 0])
        XCTAssertTrue(game.events.contains(.round(winner: 0)))
        XCTAssertGreaterThan(game.pause, 0)
        XCTAssertFalse(game.fighters[1].alive, "这一局不复活")
        run(&game, seconds: ArenaGame.breakTime)
        XCTAssertEqual(game.round, 2)
        XCTAssertTrue(game.fighters[1].alive)
        XCTAssertEqual(game.fighters[1].health, Brawler.mage.maxHealth)
        XCTAssertTrue(game.map.spawns[1].contains(game.fighters[1].pos))
        XCTAssertEqual(game.timeLeft, ArenaGame.roundLimit, accuracy: 0.5, "每局重新计时")
        game.knockOut(1, by: 0)
        game.step(dt, inputs: [:])
        XCTAssertEqual(game.result, .team(0))
    }

    /// 每局开打 40 秒后毒圈开始缩
    func testKnockoutPoisonStartsLate() {
        var game = ArenaGame(mode: .knockout, entrants: pair(.knight, .knight), seed: 8)
        let full = game.safeRadius
        run(&game, seconds: ArenaGame.roundPoison - 1)
        XCTAssertFalse(game.poisonShrinking)
        XCTAssertGreaterThanOrEqual(game.safeRadius, Double(max(game.map.width, game.map.height)) * 0.75 - 1e-6)
        XCTAssertLessThanOrEqual(game.safeRadius, full)
        run(&game, seconds: 10)
        XCTAssertTrue(game.poisonShrinking)
        XCTAssertLessThan(game.safeRadius, Double(max(game.map.width, game.map.height)) * 0.75)
    }

    // MARK: 双人大乱斗

    /// 两人一队、队友出生在一起；倒下了队友还活着就在他身边复活；两个都倒下这一队出局，排名次
    func testDuoRespawnsBesideTeammate() {
        let entrants = ArenaGame.Mode.duo.seatTeams.enumerated().map { i, team in
            ArenaGame.Entrant(name: "\(i)", brawler: Brawler.allCases[i], isBot: true, team: team)
        }
        var game = ArenaGame(mode: .duo, entrants: entrants, seed: 9)
        XCTAssertEqual(game.fighters.map(\.team), [0, 0, 1, 1, 2, 2])
        XCTAssertLessThan(game.fighters[0].pos.distance(to: game.fighters[1].pos), 2.5, "队友在一起")
        XCTAssertGreaterThan(game.fighters[0].pos.distance(to: game.fighters[2].pos), 5, "各队分开")
        XCTAssertTrue(game.isVisible(game.fighters[1], to: 0))
        game.knockOut(0, by: 2)
        XCTAssertEqual(game.fighters[0].respawnIn, 10)
        run(&game, seconds: 10.1)
        XCTAssertTrue(game.fighters[0].alive)
        XCTAssertLessThan(game.fighters[0].pos.distance(to: game.fighters[1].pos), 2, "在队友身边复活")
        game.knockOut(1, by: 2)
        game.knockOut(0, by: 2)
        XCTAssertEqual(game.fighters[0].place, 3)
        XCTAssertEqual(game.fighters[1].place, 3)
        run(&game, seconds: 11)
        XCTAssertFalse(game.fighters[1].alive, "队友都倒下了就不复活")
        XCTAssertNil(game.result)
        game.knockOut(2, by: 4)
        game.knockOut(3, by: 4)
        game.step(dt, inputs: [:])
        XCTAssertEqual(game.result, .team(2))
        XCTAssertEqual(game.fighters[4].place, 1)
        XCTAssertEqual(game.fighters[2].place, 2)
    }

    // MARK: 一对一

    /// 每人带 3 个角色：倒下一个，3 秒后换下一个上；3 个都倒下就输
    func testDuelLineupRotates() {
        var game = ArenaGame(mode: .duel, entrants: pair(.ranger, .barbarian, lineup: [.mage, .knight]), seed: 10)
        XCTAssertEqual(game.map.id, "ring")
        XCTAssertEqual(game.fighters[0].lineup, [.ranger, .mage, .knight])
        XCTAssertEqual(game.fighters[1].lineup.first, .barbarian)
        XCTAssertEqual(Set(game.fighters[1].lineup).count, 3, "电脑补的不重复")
        game.knockOut(0, by: 1)
        XCTAssertEqual(game.score, [0, 1])
        run(&game, seconds: ArenaGame.respawnDelay + 0.1)
        XCTAssertTrue(game.fighters[0].alive)
        XCTAssertEqual(game.fighters[0].brawler, .mage)
        XCTAssertEqual(game.fighters[0].health, Brawler.mage.maxHealth)
        XCTAssertEqual(game.fighters[0].pos, game.map.spawns[0][0])
        game.knockOut(0, by: 1)
        run(&game, seconds: ArenaGame.respawnDelay + 0.1)
        XCTAssertEqual(game.fighters[0].brawler, .knight)
        game.knockOut(0, by: 1)
        game.step(dt, inputs: [:])
        XCTAssertEqual(game.result, .team(1))
        XCTAssertEqual(game.score, [0, 3])
    }

    // MARK: 讨伐骷髅王

    /// 骷髅王：血多、谁都看得见；砸地先在地上画红圈，一秒后炸；被打倒勇者就赢了
    func testBossSlamWarnsThenHits() {
        var entrants = (0..<3).map { ArenaGame.Entrant(name: "勇者\($0)", brawler: .ranger, isBot: false, team: 0) }
        entrants.append(.init(name: "?", brawler: .knight, isBot: true, team: 1))
        var game = ArenaGame(mode: .boss, entrants: entrants, seed: 11)
        XCTAssertEqual(game.map.id, "lair")
        let boss = game.fighters[3]
        XCTAssertTrue(boss.isBoss)
        XCTAssertEqual(boss.brawler, .guardian)
        XCTAssertEqual(boss.name, "骷髅王")
        XCTAssertEqual(boss.health, ArenaGame.bossHealth(level: 1))
        XCTAssertEqual(boss.maxHealth, 52000)
        let spot = boss.pos + V2(1.5, 0)
        game.adjust(0) { $0.pos = spot }
        game.bossBrain.slam = 0
        game.step(dt, inputs: [:])
        XCTAssertEqual(game.warnings.count, 1)
        XCTAssertEqual(game.warnings.first?.center, boss.pos)
        XCTAssertEqual(game.fighters[0].health, Brawler.ranger.maxHealth, "红圈先不伤人")
        run(&game, seconds: 1.05)
        XCTAssertTrue(game.warnings.isEmpty)
        XCTAssertEqual(game.fighters[0].health, Brawler.ranger.maxHealth - 2400)
        // 骷髅王个子大：子弹擦边也打得中
        game.adjust(1) { $0.pos = boss.pos + V2(-0.9, 5) }
        game.step(dt, inputs: [1: ArenaInput(attack: V2(0, -1))])
        run(&game, seconds: 0.5)
        XCTAssertLessThan(game.fighters[3].health, boss.health, "打中了")
        game.knockOut(3, by: 0)
        game.step(dt, inputs: [:])
        XCTAssertEqual(game.result, .team(0))
    }

    /// 3 分钟没打倒骷髅王就输；勇者被打倒 5 秒后复活
    func testBossWinsOnTimeout() {
        var entrants = (0..<3).map { ArenaGame.Entrant(name: "勇者\($0)", brawler: .knight, isBot: false, team: 0) }
        entrants.append(.init(name: "?", brawler: .knight, isBot: true, team: 1))
        var game = ArenaGame(mode: .boss, entrants: entrants, seed: 12)
        game.knockOut(0, by: 3)
        XCTAssertEqual(game.fighters[0].respawnIn, 5)
        run(&game, seconds: ArenaGame.Mode.boss.duration + 1)
        XCTAssertEqual(game.result, .team(1))
        XCTAssertGreaterThan(game.fighters[0..<3].map(\.deaths).reduce(0, +), 1, "骷髅王会打人")
    }

    // MARK: 联机

    /// 新玩法的东西都打进包里：比分、球、宝箱、红圈、第几局、停顿、每个人现在用的角色、新的事件
    func testNewModeStateSurvivesEncoding() throws {
        var ball = ArenaGame(mode: .ball, entrants: pair(.ranger, .barbarian), seed: 13)
        let center = ball.map.center
        ball.adjust(0) { $0.pos = center + V2(0, 0.6) }
        ball.step(dt, inputs: [:])
        let events: [ArenaGame.Event] = [.goal(team: 1), .round(winner: nil), .round(winner: 0), .reset, .chestHit(chest: 1, amount: 900)]
        let snapshot = ball.snapshot(events: events)
        let decoded = try XCTUnwrap(ArenaSnapshot(data: snapshot.encoded()))
        XCTAssertEqual(decoded.ball?.carrier, 0)
        XCTAssertEqual(decoded.ball?.pos.x ?? 0, snapshot.ball?.pos.x ?? 1, accuracy: 0.01)
        XCTAssertEqual(decoded.events, events)
        XCTAssertEqual(decoded.fighters.map(\.brawler), ball.fighters.map { Optional($0.brawler) })
        var client = ArenaGame(mode: .ball, entrants: pair(.ranger, .barbarian), seed: 13)
        client.apply(decoded)
        XCTAssertEqual(client.ball?.carrier, 0)
        // 两包之间：带着的球跟着人走
        client.extrapolate(0.1)
        XCTAssertEqual(client.ball?.pos.distance(to: client.fighters[0].pos) ?? 9, 0.45, accuracy: 0.01)

        var heist = ArenaGame(mode: .heist, entrants: pair(.ranger, .barbarian), seed: 14)
        heist.chests[0].health = 12345
        let chests = try XCTUnwrap(ArenaSnapshot(data: heist.snapshot(events: []).encoded())).chests
        XCTAssertEqual(chests.map(\.health), [12345, ArenaGame.Chest.fullHealth])
        XCTAssertEqual(chests.map(\.team), [1, 0])

        var entrants = (0..<3).map { ArenaGame.Entrant(name: "勇者\($0)", brawler: .ranger, isBot: false, team: 0) }
        entrants.append(.init(name: "?", brawler: .knight, isBot: true, team: 1))
        var boss = ArenaGame(mode: .boss, entrants: entrants, seed: 15)
        let spot = boss.fighters[3].pos + V2(1.5, 0)
        boss.adjust(0) { $0.pos = spot }
        boss.bossBrain.slam = 0
        boss.step(dt, inputs: [:])
        let warnings = try XCTUnwrap(ArenaSnapshot(data: boss.snapshot(events: []).encoded())).warnings
        XCTAssertEqual(warnings.count, 1)
        XCTAssertEqual(warnings[0].radius, 3.2, accuracy: 0.05)
        XCTAssertEqual(warnings[0].total, 1, accuracy: 0.01)

        var knockout = ArenaGame(mode: .knockout, entrants: pair(.ranger, .mage), seed: 16)
        knockout.knockOut(1, by: 0)
        knockout.step(dt, inputs: [:])
        let rounds = try XCTUnwrap(ArenaSnapshot(data: knockout.snapshot(events: []).encoded()))
        XCTAssertEqual(rounds.score, [1, 0])
        XCTAssertEqual(rounds.pause, ArenaGame.breakTime, accuracy: 0.06)
        XCTAssertEqual(rounds.round, 1)

        // 上一个版本的包（没有这一段）也读得出来：比分是 0、没有球
        let older = try XCTUnwrap(ArenaSnapshot(data: snapshot.encoded(version: 2)))
        XCTAssertNil(older.ball)
        XCTAssertEqual(older.score, [0, 0])
        XCTAssertNil(older.fighters.first?.brawler ?? nil)
    }

    /// 每种玩法的座位：分队的 3v3，大乱斗 6 个，双人大乱斗 3 队 × 2，一对一 1v1，讨伐骷髅王 3 + 1
    func testSeatsPerMode() {
        XCTAssertEqual(ArenaGame.Mode.ball.seatTeams, [0, 0, 0, 1, 1, 1])
        XCTAssertEqual(ArenaGame.Mode.duo.seatTeams, [0, 0, 1, 1, 2, 2])
        XCTAssertEqual(ArenaGame.Mode.duel.seatTeams, [0, 1])
        XCTAssertEqual(ArenaGame.Mode.boss.seatTeams, [0, 0, 0, 1])
        for mode in ArenaGame.Mode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.rules.isEmpty)
            let game = ArenaGame(mode: mode, entrants: mode.seatTeams.enumerated().map { i, team in
                ArenaGame.Entrant(name: "\(i)", brawler: Brawler.allCases[i], isBot: true, team: team)
            }, seed: 17)
            for fighter in game.fighters {
                XCTAssertFalse(game.map.collides(fighter.pos, radius: ArenaGame.fighterRadius), "\(mode) \(fighter.id) 出生在墙里")
            }
        }
    }
}
