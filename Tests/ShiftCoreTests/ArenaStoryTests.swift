import XCTest
@testable import ShiftCore

/// 冒险：三章十二关的设定、开局怎么摆、星和奖励
final class ArenaStoryTests: XCTestCase {
    private let dt = 1.0 / 60

    private func me(_ brawler: Brawler = .knight, level: Int = 3) -> ArenaGame.Entrant {
        ArenaGame.Entrant(name: "我", brawler: brawler, isBot: false, team: 0, level: level, lineup: [brawler, .ranger, .mage],
                          loadout: ArenaLoadout.basic(brawler, level: level))
    }

    /// 每一关的地图都是这个玩法的地图，编号不重，对话都有，每章最后一关有人投奔
    func testLevelsAreWellFormed() {
        let levels = ArenaStory.levels
        XCTAssertEqual(levels.count, 12)
        XCTAssertEqual(Set(levels.map(\.id)).count, levels.count)
        for level in levels {
            XCTAssertTrue(ArenaMap.pool(for: level.mode).contains { $0.id == level.map }, "\(level.id) 的地图 \(level.map)")
            XCTAssertFalse(level.title.isEmpty)
            XCTAssertFalse(level.before.isEmpty, level.id)
            XCTAssertFalse(level.after.isEmpty, level.id)
            XCTAssertTrue((1...ArenaProgress.maxLevel).contains(level.enemyLevel), level.id)
            XCTAssertGreaterThan(level.coins, 0)
            if level.mode == .boss {
                XCTAssertNotNil(level.bossLevel, level.id)
            } else {
                XCTAssertFalse(level.enemies.isEmpty, level.id)
            }
        }
        for chapter in ArenaStory.chapters {
            XCTAssertEqual(chapter.levels.count, 4)
            XCTAssertFalse(chapter.recruits.isEmpty)
            XCTAssertTrue(chapter.recruits.allSatisfy { $0.unlockAt > 0 }, "投奔过来的都是要攒奖杯才解锁的")
        }
        XCTAssertEqual(ArenaStory.next(after: "1-4")?.id, "2-1")
        XCTAssertNil(ArenaStory.next(after: "3-4"))
        XCTAssertEqual(ArenaStory.chapter(of: "2-3")?.id, 2)
    }

    /// 开局：自己和电脑队友一队，对手坐满另一边；一对一对手带三个按顺序上；骷髅王按这一关定的等级
    func testEntrantsFillTheSeats() throws {
        for level in ArenaStory.levels {
            let entrants = level.entrants(me: me())
            XCTAssertEqual(entrants.count, level.mode.seatTeams.count, level.id)
            XCTAssertEqual(entrants[0].name, "我")
            XCTAssertFalse(entrants.dropFirst().contains { !$0.isBot }, "除了自己都是电脑")
            let game = ArenaGame(mode: level.mode, entrants: entrants, seed: 3, map: ArenaMap.named(level.map), bossLevel: level.bossLevel)
            XCTAssertEqual(game.map.id, level.map, level.id)
            let mine = game.fighters[0]
            switch level.mode {
            case .showdown:
                XCTAssertEqual(Set(game.fighters.map(\.team)).count, game.fighters.count, "大乱斗各打各的")
            case .boss:
                let boss = try XCTUnwrap(game.fighters.first(where: \.isBoss))
                XCTAssertEqual(boss.level, level.bossLevel)
                XCTAssertEqual(game.fighters.filter { $0.team == mine.team }.count, 3)
            case .duel:
                XCTAssertEqual(game.fighters[1].lineup, level.enemies, "对手按顺序上的三个")
            default:
                XCTAssertEqual(game.fighters.filter { $0.team == mine.team }.map(\.brawler), [.knight] + level.allies)
                XCTAssertEqual(game.fighters.filter { $0.team != mine.team }.map(\.brawler), level.enemies)
                XCTAssertTrue(game.fighters.filter { $0.team != mine.team }.allSatisfy { $0.level == level.enemyLevel })
            }
        }
    }

    /// 星：赢了一颗，一次没倒两颗，第三颗看这一关的要求；输了没有
    func testStars() throws {
        let level = try XCTUnwrap(ArenaStory.level("1-1"))
        var game = ArenaGame(mode: level.mode, entrants: level.entrants(me: me()), seed: 1, map: ArenaMap.named(level.map))
        XCTAssertEqual(level.stars(in: game, me: 0), 0, "还没打完")
        game.result = .team(0)
        game.time = 60
        XCTAssertEqual(level.stars(in: game, me: 0), 3)
        game.adjust(0) { $0.deaths = 1 }
        XCTAssertEqual(level.stars(in: game, me: 0), 2)
        game.time = 140
        XCTAssertEqual(level.stars(in: game, me: 0), 1, "太慢了没有第三颗")
        game.result = .team(1)
        XCTAssertEqual(level.stars(in: game, me: 0), 0, "输了")

        let damage = try XCTUnwrap(ArenaStory.level("1-3"))
        var heist = ArenaGame(mode: damage.mode, entrants: damage.entrants(me: me()), seed: 1, map: ArenaMap.named(damage.map))
        heist.result = .team(0)
        heist.time = 140
        heist.adjust(0) { $0.damageDealt = 9500 }
        XCTAssertEqual(damage.stars(in: heist, me: 0), 3, "打出够多伤害")
    }

    /// 奖励：第一次过关给金币，多拿的星每颗再给；一关过了下一关才开；打完一章骷髅投奔过来
    func testRewardsUnlocksAndSaving() throws {
        var progress = ArenaProgress()
        XCTAssertTrue(progress.isOpen("1-1"))
        XCTAssertFalse(progress.isOpen("1-2"))
        let first = try XCTUnwrap(ArenaStory.level("1-1"))
        XCTAssertEqual(progress.finish(first, stars: 0), ArenaStory.Reward(stars: 0, best: 0, coins: 0, firstClear: false, recruited: []))
        XCTAssertFalse(progress.isOpen("1-2"), "没过关下一关不开")
        let reward = progress.finish(first, stars: 2)
        XCTAssertTrue(reward.firstClear)
        XCTAssertEqual(reward.coins, first.coins + 2 * ArenaStory.coinsPerStar)
        XCTAssertEqual(progress.coins, reward.coins)
        XCTAssertTrue(progress.isOpen("1-2"))
        XCTAssertEqual(progress.finish(first, stars: 1).coins, 0, "没比以前好不给")
        let better = progress.finish(first, stars: 3)
        XCTAssertFalse(better.firstClear)
        XCTAssertEqual(better.coins, ArenaStory.coinsPerStar)
        XCTAssertEqual(progress.stars("1-1"), 3)

        XCTAssertFalse(progress.isUnlocked(.summoner))
        for id in ["1-2", "1-3"] {
            _ = progress.finish(try XCTUnwrap(ArenaStory.level(id)), stars: 1)
        }
        let last = progress.finish(try XCTUnwrap(ArenaStory.level("1-4")), stars: 1)
        XCTAssertEqual(last.recruited, [.summoner], "打完第一章骨灵投奔过来")
        XCTAssertTrue(progress.isUnlocked(.summoner))
        XCTAssertEqual(progress.totalTrophies, 0, "冒险不加奖杯")
        XCTAssertEqual(progress.totalStoryStars, 6)

        let saved = try JSONDecoder().decode(ArenaProgress.self, from: JSONEncoder().encode(progress))
        XCTAssertEqual(saved, progress)
        XCTAssertTrue(saved.isUnlocked(.summoner))
    }

    /// 每一关电脑都打得完（自己也交给电脑），不卡墙、不闪退
    func testBotsFinishEveryLevel() {
        for level in ArenaStory.levels {
            var game = ArenaGame(mode: level.mode, entrants: level.entrants(me: me(level: 5)), seed: 21, map: ArenaMap.named(level.map),
                                 bossLevel: level.bossLevel)
            var bots = game.fighters.map { ArenaBot(id: $0.id, seed: 21) }
            while game.result == nil && game.time < level.mode.duration + 1 {
                var inputs: [Int: ArenaInput] = [:]
                for k in bots.indices { inputs[bots[k].id] = bots[k].input(in: game, dt: dt) }
                game.step(dt, inputs: inputs)
                game.events.removeAll()
            }
            XCTAssertNotNil(game.result, level.id)
            XCTAssertLessThanOrEqual(level.stars(in: game, me: 0), 3)
        }
    }
}
