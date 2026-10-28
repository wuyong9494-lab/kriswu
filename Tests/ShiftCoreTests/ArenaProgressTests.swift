import XCTest
@testable import ShiftCore

final class ArenaProgressTests: XCTestCase {
    /// 赢了加 8 杯、给 20 金币；奖杯少（不到 30）输了不扣，多了输一局扣 3
    func testWinsAndLossesMoveTrophies() {
        var progress = ArenaProgress()
        XCTAssertEqual(progress.record(.win, brawler: .knight), ArenaProgress.Reward(trophies: 8, coins: 20, milestoneCoins: 0, unlocked: []))
        XCTAssertEqual(progress.record(.loss, brawler: .knight).trophies, 0, "奖杯少输了不扣")
        XCTAssertEqual(progress.trophies(.knight), 8)
        _ = progress.record(.win, brawler: .knight)
        let third = progress.record(.win, brawler: .knight)
        XCTAssertEqual(progress.trophies(.knight), 24)
        XCTAssertEqual(third.milestoneCoins, ArenaProgress.road[0].coins, "走到奖杯之路第一个点")
        XCTAssertEqual(third.coins, 20 + ArenaProgress.road[0].coins)
        _ = progress.record(.win, brawler: .knight)
        XCTAssertEqual(progress.record(.loss, brawler: .knight).trophies, -3)
        XCTAssertEqual(progress.trophies(.knight), 29)
        XCTAssertEqual(progress.trophies(.ranger), 0, "每个角色各算各的")
        XCTAssertEqual(progress.totalTrophies, 29)
    }

    /// 大乱斗按名次：第一 +10，第四不加不减，最后一名扣（奖杯少时不扣）
    func testShowdownPlacesMoveTrophies() {
        var progress = ArenaProgress()
        XCTAssertEqual(progress.record(.place(1), brawler: .mage).trophies, 10)
        XCTAssertEqual(progress.record(.place(6), brawler: .mage).trophies, 0)
        for _ in 0..<3 { _ = progress.record(.place(1), brawler: .mage) }
        XCTAssertEqual(progress.trophies(.mage), 40)
        XCTAssertEqual(progress.record(.place(6), brawler: .mage).trophies, -3)
        XCTAssertEqual(progress.record(.place(4), brawler: .mage).trophies, 0)
        XCTAssertEqual(progress.record(.place(2), brawler: .mage).coins, 18)
    }

    /// 奖杯掉了再涨回来，路上的奖励不重复给
    func testMilestonesPayOnce() {
        var progress = ArenaProgress()
        for _ in 0..<5 { _ = progress.record(.win, brawler: .barbarian) }
        XCTAssertEqual(progress.reached, 40)
        let coins = progress.coins
        _ = progress.record(.loss, brawler: .barbarian)
        let back = progress.record(.win, brawler: .barbarian)
        XCTAssertEqual(back.milestoneCoins, 0)
        XCTAssertEqual(progress.coins, coins + 8 + 20)
        XCTAssertEqual(progress.nextMilestone?.trophies, 70)
    }

    /// 升级：花金币，一级比一级贵，满级为止
    func testUpgradesCostCoins() {
        var progress = ArenaProgress()
        XCTAssertFalse(progress.upgrade(.knight), "没钱")
        for _ in 0..<60 { _ = progress.record(.win, brawler: .ranger) }
        let coins = progress.coins
        XCTAssertEqual(progress.upgradeCost(.knight), 25)
        XCTAssertTrue(progress.upgrade(.knight))
        XCTAssertEqual(progress.level(.knight), 2)
        XCTAssertEqual(progress.coins, coins - 25)
        XCTAssertEqual(progress.upgradeCost(.knight), 50)
        while progress.upgrade(.knight) {}
        XCTAssertEqual(progress.level(.knight), ArenaProgress.maxLevel)
        XCTAssertNil(progress.upgradeCost(.knight))
        XCTAssertFalse(progress.upgrade(.knight))
    }

    func testEncodingRoundTrip() throws {
        var progress = ArenaProgress()
        for _ in 0..<12 { _ = progress.record(.win, brawler: .assassin) }
        progress.upgrade(.assassin)
        let decoded = try JSONDecoder().decode(ArenaProgress.self, from: JSONEncoder().encode(progress))
        XCTAssertEqual(decoded, progress)
        XCTAssertEqual(decoded.level(.assassin), 2)
        XCTAssertEqual(ArenaProgress.road.map(\.trophies), ArenaProgress.road.map(\.trophies).sorted())
    }

    /// 等级：每级血量、伤害多 6%；打中几下攒满大招不变
    func testLevelsBoostHealthAndDamage() {
        let dt = 1.0 / 60
        var game = ArenaGame(mode: .teamFight, entrants: [
            .init(name: "游侠", brawler: .ranger, isBot: false, team: 0, level: 5),
            .init(name: "蛮王", brawler: .barbarian, isBot: true, team: 1, level: 3),
        ], seed: 2)
        XCTAssertEqual(game.fighters[0].maxHealth, 4444)
        XCTAssertEqual(game.fighters[1].health, 8736)
        game.adjust(0) { $0.pos = V2(3.5, 20.5) }
        game.adjust(1) { $0.pos = V2(3.5, 14.5) }
        game.step(dt, inputs: [0: ArenaInput(attack: V2(0, -1))])
        for _ in 0..<36 { game.step(dt, inputs: [:]) }
        XCTAssertEqual(game.fighters[1].health, 8736 - 1805)
        XCTAssertEqual(game.fighters[0].superCharge, 1300 / Brawler.ranger.superCost, accuracy: 1e-9)
        XCTAssertEqual(Brawler.boost(0), 1, "等级不在 1–9 的按边上算")
        XCTAssertEqual(Brawler.boost(20), Brawler.boost(ArenaProgress.maxLevel))
    }

    /// 老版本发来的开局没有等级：按 1 级
    func testEntrantWithoutLevelIsLevelOne() throws {
        let json = #"{"name":"小王","brawler":2,"isBot":false,"team":1}"#
        let entrant = try JSONDecoder().decode(ArenaGame.Entrant.self, from: Data(json.utf8))
        XCTAssertEqual(entrant.level, 1)
        XCTAssertEqual(entrant.brawler, .barbarian)
        let again = try JSONDecoder().decode(ArenaGame.Entrant.self, from: JSONEncoder().encode(ArenaGame.Entrant(name: "a", brawler: .mage, isBot: true, team: 0, level: 4)))
        XCTAssertEqual(again.level, 4)
    }
}
