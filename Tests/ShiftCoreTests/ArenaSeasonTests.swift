import XCTest
@testable import ShiftCore

/// 赛季、任务、排位、皮肤、表情
final class ArenaSeasonTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ text: String) -> Date {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) ?? Date()
    }

    private func win(_ mode: ArenaGame.Mode = .teamFight, _ brawler: Brawler = .knight, kills: Int = 3, damage: Int = 6000,
                     ranked: Bool = false) -> ArenaMatchStats {
        ArenaMatchStats(mode: mode, brawler: brawler, won: true, kills: kills, damage: damage, gadgets: 1, supers: 2, ranked: ranked)
    }

    /// 任务按日期定：同一天一样、换一天不一样；每天、每周各 3 个，种类不重
    func testQuestsAreFixedByDate() {
        let today = ArenaSeason.daily("2026-10-28")
        XCTAssertEqual(today, ArenaSeason.daily("2026-10-28"))
        XCTAssertEqual(today.count, 3)
        XCTAssertEqual(Set(today.map(\.kind)).count, 3)
        XCTAssertNotEqual(today.map(\.id), ArenaSeason.daily("2026-10-29").map(\.id))
        let week = ArenaSeason.weekly("2026-W44")
        XCTAssertEqual(week.count, 3)
        XCTAssertTrue(week.allSatisfy(\.weekly))
        XCTAssertTrue(week.allSatisfy { $0.points >= 150 })
        for quest in today + week {
            XCTAssertFalse(quest.title.isEmpty)
            XCTAssertGreaterThan(quest.target, 0)
            if quest.kind == .winMode { XCTAssertTrue(ArenaRank.allows(quest.mode ?? .boss)) }
            if quest.kind == .winWith { XCTAssertEqual(quest.brawler?.unlockAt, 0, "用一开始就有的角色") }
        }
        XCTAssertEqual(ArenaSeason.season(date("2026-10-28"), calendar: calendar), "2026-10")
        XCTAssertEqual(ArenaSeason.day(date("2026-10-28"), calendar: calendar), "2026-10-28")
        XCTAssertEqual(ArenaSeason.daysLeft(date("2026-10-28"), calendar: calendar), 4)
    }

    /// 打完一局：给赛季经验、算任务进度，做完的任务给经验；换天换周旧进度清掉，换季经验从头来
    func testMatchesAdvanceQuestsAndSeason() throws {
        var progress = ArenaProgress()
        let now = date("2026-10-28")
        let quests = progress.quests(now, calendar: calendar)
        XCTAssertEqual(quests.count, 6)
        let first = progress.recordSeason(win(), now: now, calendar: calendar)
        XCTAssertGreaterThanOrEqual(first.points, ArenaSeason.matchPoints(win()))
        XCTAssertEqual(progress.season.season, "2026-10")
        // 一直赢，做完能做完的
        var done = first.quests.count
        for _ in 0..<40 {
            done += progress.recordSeason(win(.ball, .knight, kills: 6, damage: 30_000), now: now, calendar: calendar).quests.count
        }
        XCTAssertGreaterThan(done, 0)
        let daily = quests.filter { !$0.weekly }
        let finishable = daily.filter { $0.kind != .winMode && $0.kind != .winWith }
        for quest in finishable {
            XCTAssertEqual(progress.questProgress(quest), quest.target, quest.title)
        }
        let points = progress.season.points
        XCTAssertGreaterThan(points, 40 * 20)

        // 第二天：昨天的每日任务进度清掉，这周的还在
        let tomorrow = date("2026-10-29")
        progress.refreshSeason(tomorrow, calendar: calendar)
        XCTAssertEqual(progress.season.points, points, "同一季经验还在")
        for quest in daily { XCTAssertNil(progress.season.progress[quest.id]) }
        XCTAssertEqual(progress.quests(tomorrow, calendar: calendar).filter(\.weekly), quests.filter(\.weekly), "同一周的周任务不变")
        let counted: [ArenaQuest.Kind] = [.play, .win, .kills, .damage, .supers]
        for quest in quests where quest.weekly && counted.contains(quest.kind) {
            XCTAssertGreaterThan(progress.questProgress(quest), 0, "这周的进度还在：\(quest.title)")
        }
        // 下个月：新的一季
        progress.refreshSeason(date("2026-11-02"), calendar: calendar)
        XCTAssertEqual(progress.season.season, "2026-11")
        XCTAssertEqual(progress.season.points, 0)
        XCTAssertTrue(progress.season.claimed.isEmpty)
    }

    /// 赛季奖励：到了这一级才能领、只能领一次；金币进口袋，皮肤、表情就有了
    func testClaimingPrizes() {
        var progress = ArenaProgress()
        progress.season.points = ArenaSeason.pointsPerTier * 5
        XCTAssertEqual(progress.season.tier, 5)
        XCTAssertNil(progress.claim(6), "还没到")
        XCTAssertEqual(progress.claim(1), .coins(22))
        XCTAssertEqual(progress.coins, 22)
        XCTAssertNil(progress.claim(1), "领过了")
        XCTAssertEqual(progress.claim(3), .emote(4))
        XCTAssertTrue(progress.owns(emote: ArenaEmote.all[4]))
        XCTAssertEqual(progress.claim(5), .skin(Brawler.knight.rawValue * 10 + 1))
        let gold = ArenaSkin.of(.knight)[0]
        XCTAssertTrue(progress.owns(skin: gold))
        XCTAssertEqual(progress.skin(.knight), 0, "有了还得穿上")
        progress.wear(1, for: .knight)
        XCTAssertEqual(progress.skin(.knight), 1)
        XCTAssertEqual(progress.loadout(for: .knight).skin, 1, "带上场的是穿着的那套")
        progress.wear(2, for: .knight)
        XCTAssertEqual(progress.skin(.knight), 1, "没有的穿不上")
        XCTAssertEqual(ArenaSeason.prize(30), .skin(Brawler.shade.rawValue * 10 + 1))
        XCTAssertEqual((1...ArenaSeason.tiers).filter { if case .skin = ArenaSeason.prize($0) { return true } else { return false } }.count, 6)
    }

    /// 商店：金币够才买得到，买了就有；一开始有 4 个表情
    func testShop() {
        var progress = ArenaProgress()
        XCTAssertEqual(progress.emotes.map(\.id), [0, 1, 2, 3])
        let skin = ArenaSkin.of(.mage)[1]
        XCTAssertFalse(progress.buy(skin), "没钱")
        progress.addCoins(300)
        XCTAssertTrue(progress.buy(skin))
        XCTAssertEqual(progress.coins, 300 - skin.price)
        XCTAssertFalse(progress.buy(skin), "买过了")
        let fire = ArenaEmote.all[8]
        XCTAssertTrue(progress.buy(fire))
        XCTAssertFalse(progress.buy(ArenaEmote.all[4]), "赛季奖励的表情不卖")
        XCTAssertEqual(progress.emotes.map(\.id), [0, 1, 2, 3, 8])
        XCTAssertEqual(ArenaSkin.all.count, Brawler.allCases.count * 2)
        XCTAssertEqual(Set(ArenaSkin.all.map(\.id)).count, ArenaSkin.all.count)
    }

    /// 排位：赢了加 25，输了按段位扣，不会扣到 0 以下；到分数升段
    func testRanked() {
        var progress = ArenaProgress()
        let now = date("2026-10-28")
        var lost = ArenaMatchStats(mode: .teamFight, brawler: .knight, won: false, ranked: true)
        XCTAssertEqual(progress.recordSeason(lost, now: now, calendar: calendar).rankChange, -8)
        XCTAssertEqual(progress.season.rankPoints, 0, "不扣到负的")
        var promoted = false
        for _ in 0..<8 {
            promoted = progress.recordSeason(win(ranked: true), now: now, calendar: calendar).promoted || promoted
        }
        XCTAssertEqual(progress.season.rankPoints, 200)
        XCTAssertTrue(promoted)
        XCTAssertEqual(progress.rankTier, 1)
        XCTAssertEqual(ArenaRank.tiers[progress.rankTier].name, "白银")
        lost.won = false
        XCTAssertEqual(progress.recordSeason(lost, now: now, calendar: calendar).rankChange, -12)
        XCTAssertEqual(progress.season.bestTier, 1, "最高段记着")
        XCTAssertEqual(progress.recordSeason(win(), now: now, calendar: calendar).rankChange, nil, "不是排位不算分")
        XCTAssertTrue(ArenaRank.allows(.ball))
        XCTAssertFalse(ArenaRank.allows(.showdown))
        XCTAssertFalse(ArenaRank.allows(.boss))
        XCTAssertEqual(ArenaRank.tier(1500), 4)
    }

    /// 存下来再读出来一样；老版本存的没有赛季
    func testSaving() throws {
        var progress = ArenaProgress()
        _ = progress.recordSeason(win(ranked: true), now: date("2026-10-28"), calendar: calendar)
        progress.addCoins(500)
        _ = progress.buy(ArenaSkin.of(.ranger)[0])
        progress.wear(1, for: .ranger)
        let saved = try JSONDecoder().decode(ArenaProgress.self, from: JSONEncoder().encode(progress))
        XCTAssertEqual(saved, progress)
        XCTAssertEqual(saved.skin(.ranger), 1)
        let old = try JSONDecoder().decode(ArenaProgress.self, from: Data(#"{"coins":5}"#.utf8))
        XCTAssertEqual(old.season, ArenaSeasonState())
    }

    /// 表情：1.5 秒最多一个，倒下了也能冒；发得过网，老版本的包读得出来
    func testEmotes() throws {
        var game = ArenaGame(mode: .teamFight, entrants: [
            .init(name: "我", brawler: .knight, isBot: false, team: 0, loadout: ArenaLoadout(skin: 2)),
            .init(name: "敌", brawler: .mage, isBot: true, team: 1),
        ], seed: 1)
        XCTAssertEqual(game.fighters[0].skin, 2)
        game.step(1.0 / 60, inputs: [0: ArenaInput(emote: 5)])
        XCTAssertTrue(game.events.contains(.emote(fighter: 0, emote: 5)))
        game.events.removeAll()
        game.step(1.0 / 60, inputs: [0: ArenaInput(emote: 1)])
        XCTAssertFalse(game.events.contains { if case .emote = $0 { return true } else { return false } }, "太快了")
        let packet = game.snapshot(events: [.emote(fighter: 1, emote: 9), .hit(target: 0, amount: 100)]).encoded()
        let snapshot = try XCTUnwrap(ArenaSnapshot(data: packet))
        XCTAssertTrue(snapshot.events.contains(.emote(fighter: 1, emote: 9)))
        XCTAssertTrue(snapshot.events.contains(.hit(target: 0, amount: 100)))
        XCTAssertEqual(ArenaLoadout(skin: 7).allowed(.knight, level: 1).skin, nil, "没有第 7 套")
    }
}
