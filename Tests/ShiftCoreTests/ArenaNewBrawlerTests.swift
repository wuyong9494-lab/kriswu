import XCTest
@testable import ShiftCore

/// 后加的四个角色：剑圣、酒桶、书灵、飞镖手
final class ArenaNewBrawlerTests: XCTestCase {
    private let dt = 1.0 / 60

    /// 峡谷中间那一行是空的：自己、一个队友、一个对手
    private func trio(_ mine: Brawler, ally: Brawler = .ranger, enemy: Brawler = .barbarian, loadout: ArenaLoadout = ArenaLoadout()) -> ArenaGame {
        var game = ArenaGame(mode: .teamFight, entrants: [
            .init(name: "我", brawler: mine, isBot: false, team: 0, loadout: loadout),
            .init(name: "友", brawler: ally, isBot: true, team: 0),
            .init(name: "敌", brawler: enemy, isBot: true, team: 1),
        ], seed: 1, map: .canyon)
        game.adjust(0) { $0.pos = V2(5.5, 12.5); $0.facing = V2(1, 0) }
        game.adjust(1) { $0.pos = V2(4.5, 12.5) }
        game.adjust(2) { $0.pos = V2(7, 12.5) }
        return game
    }

    private func run(_ game: inout ArenaGame, seconds: Double) {
        for _ in 0..<Int((seconds / dt).rounded()) where game.result == nil { game.step(dt, inputs: [:]) }
    }

    func testRosterTablesCoverEveryBrawler() {
        for brawler in Brawler.allCases {
            XCTAssertFalse(brawler.name.isEmpty)
            XCTAssertGreaterThan(brawler.maxHealth, 0)
            XCTAssertEqual(brawler.gadgets.count, 2)
            XCTAssertEqual(brawler.starPowers.count, 2)
            XCTAssertFalse(brawler.hyperNote.isEmpty)
            XCTAssertEqual(ArenaSkin.of(brawler).count, 2)
        }
        XCTAssertEqual(Brawler.allCases.count, 13)
        XCTAssertEqual(StarPower.allCases.count, Brawler.allCases.count * 2)
        XCTAssertTrue(ArenaProgress.road.contains { $0.brawler == .darter }, "奖杯之路上有解锁点")
    }

    /// 剑圣转圈：身边的敌人挨砍、队友没事；大招是冲锋
    func testSwordsmanSweepsAndDashes() {
        var game = trio(.swordsman)
        let enemy = game.fighters[2].health, ally = game.fighters[1].health
        game.step(dt, inputs: [0: ArenaInput(attack: V2(1, 0))])
        XCTAssertEqual(enemy - game.fighters[2].health, 1176)
        XCTAssertEqual(game.fighters[1].health, ally)
        XCTAssertTrue(game.projectiles.isEmpty, "转圈不是子弹")
        game.adjust(0) { $0.superCharge = 1 }
        game.step(dt, inputs: [0: ArenaInput(special: V2(1, 0))])
        XCTAssertNotNil(game.fighters[0].dash)
    }

    /// 酒桶：扔酒桶是越过墙的炸弹；大招回血、加盾、加速
    func testBrewerLobsAndDrinks() {
        var game = trio(.brewer)
        game.step(dt, inputs: [0: ArenaInput(attack: V2(3, 0))])
        XCTAssertNotNil(game.projectiles.first?.lob)
        game.adjust(0) { $0.health = 1000; $0.superCharge = 1 }
        game.step(dt, inputs: [0: ArenaInput(special: V2(1, 0))])
        XCTAssertEqual(game.fighters[0].health, 3688)
        XCTAssertGreaterThan(game.fighters[0].shield, 3)
        XCTAssertGreaterThan(game.fighters[0].speedBoost, 3)
    }

    /// 书灵：灵光给队友回血（不回自己）、敌人掉血，回血也攒大招；大招给身边的队友加盾
    func testScholarHealsAlliesAndShieldsThem() {
        var game = trio(.scholar)
        // 刚挨过打（不自己慢慢回血）
        let now = game.time
        game.adjust(0) { $0.health = 1000; $0.lastHurt = now }
        game.adjust(1) { $0.health = 1000; $0.lastHurt = now }
        let enemy = game.fighters[2].health
        game.step(dt, inputs: [0: ArenaInput(attack: V2(1, 0))])
        XCTAssertEqual(game.fighters[1].health, 1672)
        XCTAssertEqual(game.fighters[0].health, 1000, "不回自己")
        XCTAssertEqual(enemy - game.fighters[2].health, 582)
        XCTAssertGreaterThan(game.fighters[0].superCharge, Double(520) / game.superCost(game.fighters[0]), "回血也攒大招")
        game.adjust(0) { $0.superCharge = 1 }
        game.step(dt, inputs: [0: ArenaInput(special: V2(1, 0))])
        XCTAssertGreaterThan(game.fighters[1].shield, 2)
        XCTAssertGreaterThan(game.fighters[0].shield, 2)
        XCTAssertEqual(game.fighters[2].shield, 0)
    }

    /// 飞镖手：回旋镖飞到头往回飞、来回各打一次后收回；大招隐身、身边的敌人变慢
    func testDarterBoomerangReturns() {
        var game = trio(.darter)
        game.adjust(2) { $0.pos = V2(9, 12.5) }
        let enemy = game.fighters[2].health
        game.step(dt, inputs: [0: ArenaInput(attack: V2(1, 0))])
        XCTAssertEqual(game.projectiles.first?.boomerang, true)
        run(&game, seconds: 0.5)
        XCTAssertEqual(enemy - game.fighters[2].health, 762, "飞出去打一次")
        XCTAssertEqual(game.projectiles.first?.returning, true, "飞到头往回飞")
        run(&game, seconds: 1.2)
        XCTAssertEqual(enemy - game.fighters[2].health, 1524, "飞回来再打一次")
        XCTAssertTrue(game.projectiles.isEmpty, "回到手里收掉")

        game.adjust(2) { $0.pos = V2(7, 12.5) }
        game.adjust(0) { $0.superCharge = 1 }
        game.step(dt, inputs: [0: ArenaInput(special: V2(1, 0))])
        XCTAssertGreaterThan(game.fighters[0].invisible, 2.5)
        XCTAssertGreaterThan(game.fighters[2].slowed, 1.5)
    }

    /// 电脑用新角色打得下来
    func testBotsPlayTheNewBrawlers() {
        let roster: [Brawler] = [.swordsman, .brewer, .scholar, .darter, .brewer, .scholar]
        var game = ArenaGame(mode: .teamFight, entrants: roster.enumerated().map {
            ArenaGame.Entrant(name: "电脑\($0)", brawler: $1, isBot: true, team: $0 < 3 ? 0 : 1, level: 9, loadout: ArenaLoadout.basic($1, level: 9))
        }, seed: 5)
        var bots = game.fighters.map { ArenaBot(id: $0.id, seed: 5) }
        var supers = 0
        while game.result == nil && game.time < ArenaGame.Mode.teamFight.duration + 1 {
            var inputs: [Int: ArenaInput] = [:]
            for k in bots.indices { inputs[bots[k].id] = bots[k].input(in: game, dt: dt) }
            game.step(dt, inputs: inputs)
            supers += game.events.filter { if case .special = $0 { return true } else { return false } }.count
            game.events.removeAll()
        }
        XCTAssertNotNil(game.result)
        XCTAssertGreaterThan(supers, 0)
        XCTAssertGreaterThan(game.fighters.map(\.damageDealt).reduce(0, +), 0)
    }
}
