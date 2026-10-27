import XCTest
@testable import ShiftCore

final class ArenaTests: XCTestCase {
    private let dt = 1.0 / 60

    private func entrants(_ count: Int = 6, brawlers: [Brawler]? = nil) -> [ArenaGame.Entrant] {
        (0..<count).map { i in
            let brawler = brawlers?[i] ?? Brawler.allCases[i % Brawler.allCases.count]
            return ArenaGame.Entrant(name: "电脑\(i)", brawler: brawler, isBot: true, team: i < count / 2 ? 0 : 1)
        }
    }

    private func run(_ game: inout ArenaGame, seconds: Double, inputs: [Int: ArenaInput] = [:]) {
        for _ in 0..<Int(seconds / dt) where game.result == nil {
            game.step(dt, inputs: inputs)
        }
    }

    /// 地图：分队的中心对称、两边一样；出生点站得下、走得到中间
    func testMapsAreFairAndOpen() {
        let canyon = ArenaMap.canyon
        XCTAssertEqual(canyon.width, 15)
        XCTAssertEqual(canyon.height, 25)
        for y in 0..<canyon.height {
            for x in 0..<canyon.width {
                XCTAssertEqual(canyon.tile(x, y), canyon.tile(canyon.width - 1 - x, canyon.height - 1 - y), "\(x),\(y)")
            }
        }
        XCTAssertEqual(canyon.spawns.map(\.count), [3, 3])
        XCTAssertGreaterThan(canyon.spawns[0][0].y, canyon.center.y, "下边一队在下面")
        let plaza = ArenaMap.plaza
        XCTAssertEqual(plaza.spawns.map(\.count), [6])
        for map in [canyon, plaza] {
            for spawn in map.spawns.flatMap({ $0 }) {
                XCTAssertFalse(map.collides(spawn, radius: ArenaGame.fighterRadius))
                XCTAssertEqual(map.path(from: spawn, to: map.center).last, map.center, "从出生点走得到中间")
            }
        }
    }

    func testWallsStopWalking() {
        var game = ArenaGame(mode: .teamFight, entrants: entrants(2), seed: 1)
        for direction in [V2(0, -1), V2(1, 0), V2(-1, 0.3), V2(0, 1)] {
            for _ in 0..<300 {
                game.step(dt, inputs: [0: ArenaInput(move: direction)])
                XCTAssertFalse(game.map.collides(game.fighters[0].pos, radius: ArenaGame.fighterRadius - 1e-6))
            }
        }
    }

    /// 子弹打中敌人、穿过队友、被墙挡住；打中攒大招
    func testShotsHitEnemiesNotFriendsAndStopAtWalls() {
        var game = ArenaGame(mode: .teamFight, entrants: [
            .init(name: "狐", brawler: .ranger, isBot: false, team: 0),
            .init(name: "友", brawler: .knight, isBot: true, team: 0),
            .init(name: "敌", brawler: .barbarian, isBot: true, team: 1),
        ], seed: 2)
        game.adjust(0) { $0.pos = V2(3.5, 20.5) }
        game.adjust(1) { $0.pos = V2(3.5, 17.5) }
        game.adjust(2) { $0.pos = V2(3.5, 14.5) }
        game.step(dt, inputs: [0: ArenaInput(attack: V2(0, -1))])
        run(&game, seconds: 0.6)
        XCTAssertEqual(game.fighters[2].health, Brawler.barbarian.maxHealth - 1300)
        XCTAssertEqual(game.fighters[1].health, Brawler.knight.maxHealth, "不打自己人")
        XCTAssertEqual(game.fighters[0].superCharge, 1300 / Brawler.ranger.superCost, accuracy: 1e-9)
        XCTAssertEqual(game.fighters[0].ammo, 2 + 0.6 / Brawler.ranger.reload, accuracy: 0.05)
        // 中间那列有墙
        game.adjust(0) { $0.pos = V2(7.5, 20.5) }
        game.adjust(2) { $0.pos = V2(7.5, 13.5); $0.health = $0.maxHealth }
        run(&game, seconds: 0.5)
        game.step(dt, inputs: [0: ArenaInput(attack: V2(0, -1))])
        run(&game, seconds: 0.8)
        XCTAssertEqual(game.fighters[2].health, Brawler.barbarian.maxHealth, "墙挡住了")
    }

    /// 打倒了给队里记一分，3 秒后在自己家满血复活；身上的星星掉出来
    func testKnockoutRespawnAndDroppedStars() {
        var game = ArenaGame(mode: .stars, entrants: [
            .init(name: "狐", brawler: .ranger, isBot: false, team: 0),
            .init(name: "敌", brawler: .mage, isBot: true, team: 1),
        ], seed: 3)
        game.adjust(0) { $0.pos = V2(3.5, 20.5) }
        game.adjust(1) { $0.pos = V2(3.5, 14.5); $0.health = 1000; $0.stars = 3 }
        game.step(dt, inputs: [0: ArenaInput(attack: V2(0, -1))])
        run(&game, seconds: 0.6)
        XCTAssertFalse(game.fighters[1].alive)
        XCTAssertEqual(game.fighters[0].kills, 1)
        XCTAssertEqual(game.teamKills, [1, 0])
        XCTAssertEqual(game.teamStars(1), 0)
        XCTAssertEqual(game.stars.count, 3, "三颗星星掉在地上")
        XCTAssertTrue(game.stars.allSatisfy { $0.distance(to: V2(3.5, 14.5)) < 2.5 })
        run(&game, seconds: ArenaGame.respawnDelay)
        XCTAssertTrue(game.fighters[1].alive)
        XCTAssertEqual(game.fighters[1].health, Brawler.mage.maxHealth)
        XCTAssertTrue(game.map.spawns[1].contains(game.fighters[1].pos))
    }

    func testStarsHeldFifteenSecondsWin() {
        var game = ArenaGame(mode: .stars, entrants: entrants(), seed: 4)
        game.adjust(0) { $0.stars = 6 }
        game.adjust(1) { $0.stars = 4 }
        game.step(dt, inputs: [:])
        XCTAssertEqual(game.countdown?.team, 0)
        run(&game, seconds: ArenaGame.starHold - 1)
        XCTAssertNil(game.result)
        run(&game, seconds: 2)
        XCTAssertEqual(game.result, .team(0))
    }

    func testStandingInTheZoneWins() {
        var game = ArenaGame(mode: .zone, entrants: entrants(), seed: 5)
        let center = game.map.center
        game.adjust(4) { $0.pos = center }
        run(&game, seconds: 25)
        XCTAssertEqual(game.zoneProgress[1], 50, accuracy: 1)
        XCTAssertEqual(game.zoneProgress[0], 0)
        game.adjust(1) { $0.pos = center + V2(0.5, 0) }
        run(&game, seconds: 5)
        XCTAssertEqual(game.zoneProgress[1], 50, accuracy: 1, "两队都在圈里谁也不加")
        let home = game.map.spawns[0][1]
        game.adjust(1) { $0.pos = home }
        run(&game, seconds: 30)
        XCTAssertEqual(game.result, .team(1))
    }

    /// 大乱斗：毒圈越缩越小，圈外掉血，最后剩下的赢，名次都排好
    func testShowdownPoisonLeavesOneSurvivor() {
        var game = ArenaGame(mode: .showdown, entrants: entrants(), seed: 6)
        XCTAssertEqual(Set(game.fighters.map(\.team)).count, 6, "各自为战")
        run(&game, seconds: 160)
        guard case .survivor(let winner)? = game.result else { return XCTFail("\(String(describing: game.result))") }
        XCTAssertEqual(game.fighters[winner].brawler, .barbarian, "血最厚、出生点离中间最近的活到最后")
        XCTAssertEqual(game.fighters.compactMap(\.place).sorted(), [1, 2, 3, 4, 5, 6])
    }

    /// 六个电脑打完一局：每种玩法都能分出结果（或时间到），没人卡进墙里
    func testBotsFinishEveryMode() {
        for mode in ArenaGame.Mode.allCases {
            var game = ArenaGame(mode: mode, entrants: entrants(), seed: 7)
            var bots = game.fighters.map { ArenaBot(id: $0.id, seed: 7) }
            var shots = 0
            while game.result == nil && game.time < mode.duration + 1 {
                var inputs: [Int: ArenaInput] = [:]
                for k in bots.indices {
                    let input = bots[k].input(in: game, dt: dt)
                    if input.attack != nil { shots += 1 }
                    inputs[bots[k].id] = input
                }
                game.step(dt, inputs: inputs)
                game.events.removeAll()
                for fighter in game.fighters where fighter.alive && !fighter.busy {
                    XCTAssertFalse(game.map.collides(fighter.pos, radius: ArenaGame.fighterRadius - 1e-6), "\(mode) \(fighter.name)")
                }
            }
            XCTAssertNotNil(game.result, "\(mode)")
            XCTAssertGreaterThan(shots, 20, "\(mode) 电脑会开火")
            XCTAssertGreaterThan(game.fighters.map(\.damageDealt).reduce(0, +), 0, "\(mode) 打中过人")
        }
    }
}

final class ArenaNetTests: XCTestCase {
    private let dt = 1.0 / 60

    private func entrants() -> [ArenaGame.Entrant] {
        (0..<6).map { ArenaGame.Entrant(name: "电脑\($0)", brawler: Brawler.allCases[$0 % 5], isBot: true, team: $0 < 3 ? 0 : 1) }
    }

    /// 房主打成一包、别人解开照着改：位置差不到 1/100 格，血量、比分、子弹、星星一样
    func testSnapshotRoundTripAndApply() throws {
        var host = ArenaGame(mode: .stars, entrants: entrants(), seed: 9)
        var bots = host.fighters.map { ArenaBot(id: $0.id, seed: 9) }
        var events: [ArenaGame.Event] = []
        for _ in 0..<Int(12 / dt) {
            var inputs: [Int: ArenaInput] = [:]
            for k in bots.indices { inputs[k] = bots[k].input(in: host, dt: dt) }
            host.step(dt, inputs: inputs)
            events += host.events
            host.events.removeAll()
        }
        let snapshot = host.snapshot(events: events, acks: [2: 42])
        let data = snapshot.encoded()
        XCTAssertLessThan(data.count, 2000, "一包不大")
        let decoded = try XCTUnwrap(ArenaSnapshot(data: data))
        XCTAssertEqual(decoded.fighters.count, 6)
        XCTAssertEqual(decoded.fighters[2].ack, 42)
        XCTAssertEqual(decoded.projectiles.count, snapshot.projectiles.count)
        XCTAssertEqual(decoded.stars.count, snapshot.stars.count)
        XCTAssertEqual(decoded.events.count, min(snapshot.events.count, 60))

        var client = ArenaGame(mode: .stars, entrants: entrants(), seed: 9)
        client.apply(decoded)
        XCTAssertEqual(client.fighters.map(\.health), host.fighters.map(\.health))
        XCTAssertEqual(client.fighters.map(\.alive), host.fighters.map(\.alive))
        XCTAssertEqual(client.fighters.map(\.stars), host.fighters.map(\.stars))
        XCTAssertEqual(client.teamKills, host.teamKills)
        for (a, b) in zip(client.fighters, host.fighters) {
            XCTAssertEqual(a.pos.x, b.pos.x, accuracy: 0.006)
            XCTAssertEqual(a.pos.y, b.pos.y, accuracy: 0.006)
            XCTAssertEqual(a.superCharge, b.superCharge, accuracy: 0.005)
        }
        XCTAssertEqual(client.time, host.time, accuracy: 0.001)
    }

    func testEveryResultSurvivesEncoding() throws {
        for result: ArenaGame.Result? in [nil, .team(1), .survivor(4), .draw] {
            let snapshot = ArenaSnapshot(time: 1, fighters: [], projectiles: [], stars: [], teamKills: [3, 4], zoneProgress: [12.5, 0],
                                         countdown: ArenaGame.Countdown(team: 1, left: 7.5), safeRadius: 9, result: result,
                                         events: [.knockout(target: 2, by: nil), .explosion(at: V2(3.25, 4.5), radius: 1.2)])
            let decoded = try XCTUnwrap(ArenaSnapshot(data: snapshot.encoded()))
            XCTAssertEqual(decoded, snapshot)
        }
        XCTAssertNil(ArenaSnapshot(data: Data([1, 2, 3])), "坏包不认")
    }

    /// 两包之间自己往前推：子弹照直飞、扔的炸弹接着飞，飞到头就没了
    func testExtrapolationMovesShotsBetweenSnapshots() {
        var game = ArenaGame(mode: .teamFight, entrants: [
            .init(name: "狐", brawler: .ranger, isBot: false, team: 0),
            .init(name: "蛙", brawler: .mage, isBot: false, team: 1),
        ], seed: 1)
        game.adjust(0) { $0.pos = V2(3.5, 20.5) }
        game.step(dt, inputs: [0: ArenaInput(attack: V2(0, -1)), 1: ArenaInput(attack: V2(0, 3))])
        let before = game.projectiles
        XCTAssertEqual(before.count, 2)
        game.extrapolate(0.1)
        let straight = game.projectiles.first { $0.lob == nil }!
        XCTAssertEqual(straight.pos.y, before.first { $0.lob == nil }!.pos.y - 1.7, accuracy: 0.001)
        game.extrapolate(1)
        XCTAssertTrue(game.projectiles.allSatisfy { $0.lob == nil }, "炸弹落地了")
        XCTAssertEqual(ArenaGame.walk(from: V2(0.5, 0.5), by: V2(-1, 0), on: game.map).x, 0.5, accuracy: 0.6, "地图边上走不出去")
    }
}
