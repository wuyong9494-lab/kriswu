import XCTest
@testable import ShiftCore

/// 小道具、星徽、超级充能
final class ArenaSkillsTests: XCTestCase {
    private let dt = 1.0 / 60

    private func run(_ game: inout ArenaGame, seconds: Double, inputs: [Int: ArenaInput] = [:]) {
        for _ in 0..<Int((seconds / dt).rounded()) where game.result == nil {
            game.step(dt, inputs: inputs)
        }
    }

    /// 峡谷中间那一行是空的：两个人隔 4 格面对面站
    private func duel(_ mine: Brawler, _ theirs: Brawler = .barbarian, loadout: ArenaLoadout = ArenaLoadout()) -> ArenaGame {
        var game = ArenaGame(mode: .teamFight, entrants: [
            .init(name: "我", brawler: mine, isBot: false, team: 0, loadout: loadout),
            .init(name: "敌", brawler: theirs, isBot: true, team: 1),
        ], seed: 1, map: .canyon)
        game.adjust(0) { $0.pos = V2(5.5, 12.5); $0.facing = V2(1, 0) }
        game.adjust(1) { $0.pos = V2(9.5, 12.5); $0.facing = V2(-1, 0) }
        return game
    }

    // MARK: 小道具

    /// 一局 3 次，用完一次等 6 秒；不是这个角色的小道具带不上
    func testGadgetUsesAndCooldown() {
        var game = duel(.knight, loadout: ArenaLoadout(gadget: .sprint))
        XCTAssertEqual(game.fighters[0].gadget, .sprint)
        XCTAssertEqual(game.fighters[0].gadgetUses, ArenaGame.gadgetUses)
        let normal = game.moveSpeed(game.fighters[0])
        game.step(dt, inputs: [0: ArenaInput(gadget: true)])
        XCTAssertTrue(game.events.contains(.gadget(fighter: 0)))
        XCTAssertEqual(game.fighters[0].gadgetUses, 2)
        XCTAssertEqual(game.moveSpeed(game.fighters[0]), normal * 1.5, accuracy: 1e-9, "疾行走得快一半")
        game.events.removeAll()
        game.step(dt, inputs: [0: ArenaInput(gadget: true)])
        XCTAssertEqual(game.fighters[0].gadgetUses, 2, "用完一次要等")
        XCTAssertFalse(game.events.contains(.gadget(fighter: 0)))
        run(&game, seconds: ArenaGame.gadgetCooldown)
        XCTAssertEqual(game.moveSpeed(game.fighters[0]), normal, accuracy: 1e-9, "3 秒后恢复")
        game.step(dt, inputs: [0: ArenaInput(gadget: true)])
        XCTAssertEqual(game.fighters[0].gadgetUses, 1)
        run(&game, seconds: ArenaGame.gadgetCooldown)
        game.step(dt, inputs: [0: ArenaInput(gadget: true)])
        run(&game, seconds: ArenaGame.gadgetCooldown)
        game.step(dt, inputs: [0: ArenaInput(gadget: true)])
        XCTAssertEqual(game.fighters[0].gadgetUses, 0, "一局只有 3 次")

        let wrong = duel(.knight, loadout: ArenaLoadout(gadget: .blink))
        XCTAssertNil(wrong.fighters[0].gadget, "法师的小道具骑士带不上")
        XCTAssertEqual(wrong.fighters[0].gadgetUses, 0)
    }

    /// 药水回血、铁壁少挨六成、装弹马上装满
    func testPotionWardAndReload() {
        var potion = duel(.barbarian, loadout: ArenaLoadout(gadget: .potion))
        // 刚挨过打（不自己慢慢回血）
        let now = potion.time
        potion.adjust(0) { $0.health = 1000; $0.lastHurt = now }
        potion.step(dt, inputs: [0: ArenaInput(gadget: true)])
        XCTAssertEqual(potion.fighters[0].health, 3016)
        XCTAssertTrue(potion.events.contains(.heal(target: 0, amount: 2016)))

        var ward = duel(.knight, loadout: ArenaLoadout(gadget: .ward))
        ward.step(dt, inputs: [0: ArenaInput(gadget: true)])
        XCTAssertGreaterThan(ward.fighters[0].shield, 2)
        let before = ward.fighters[0].health
        ward.hurt(0, 1000, by: 1, charges: true)
        XCTAssertEqual(before - ward.fighters[0].health, 400)

        var reload = duel(.ranger, loadout: ArenaLoadout(gadget: .reload))
        reload.adjust(0) { $0.ammo = 0 }
        reload.step(dt, inputs: [0: ArenaInput(gadget: true)])
        XCTAssertEqual(reload.fighters[0].ammo, 3, accuracy: 0.01)
    }

    /// 震地把身边的人震开、打 700；冰霜让人走得慢；翻滚不伤人；闪烁往摇杆方向闪 3.5 格
    func testShockwaveFrostRollAndBlink() {
        var shock = duel(.barbarian, .knight, loadout: ArenaLoadout(gadget: .shockwave))
        shock.adjust(1) { $0.pos = V2(6.8, 12.5) }
        let full = shock.fighters[1].health
        shock.step(dt, inputs: [0: ArenaInput(gadget: true)])
        XCTAssertEqual(full - shock.fighters[1].health, 700)
        XCTAssertGreaterThan(shock.fighters[1].pos.x, 8, "震开了")

        var frost = duel(.mage, .knight, loadout: ArenaLoadout(gadget: .frost))
        frost.adjust(1) { $0.pos = V2(7.5, 12.5) }
        let speed = frost.moveSpeed(frost.fighters[1])
        frost.step(dt, inputs: [0: ArenaInput(gadget: true)])
        XCTAssertGreaterThan(frost.fighters[1].slowed, 2)
        XCTAssertEqual(frost.moveSpeed(frost.fighters[1]), speed * 0.6, accuracy: 1e-9)
        run(&frost, seconds: 2.6)
        XCTAssertEqual(frost.moveSpeed(frost.fighters[1]), speed, accuracy: 1e-9, "2.5 秒后恢复")

        var roll = duel(.ranger, .knight, loadout: ArenaLoadout(gadget: .roll))
        roll.adjust(1) { $0.pos = V2(7, 12.5) }
        let enemy = roll.fighters[1].health
        roll.step(dt, inputs: [0: ArenaInput(move: V2(1, 0), gadget: true)])
        run(&roll, seconds: 0.4)
        XCTAssertEqual(roll.fighters[0].pos.x, 8.5, accuracy: 0.1, "往摇杆方向翻 3 格")
        XCTAssertEqual(roll.fighters[1].health, enemy, "翻滚不伤人")

        var blink = duel(.mage, loadout: ArenaLoadout(gadget: .blink))
        blink.step(dt, inputs: [0: ArenaInput(move: V2(-1, 0), gadget: true)])
        XCTAssertEqual(blink.fighters[0].pos.x, 2, accuracy: 0.1)
    }

    /// 隐身：对面看不见，贴得很近才看得见，2.5 秒后现身
    func testVanishHidesFromEnemies() {
        var game = duel(.assassin, loadout: ArenaLoadout(gadget: .vanish))
        XCTAssertTrue(game.isVisible(game.fighters[0], to: 1))
        game.step(dt, inputs: [0: ArenaInput(gadget: true)])
        XCTAssertFalse(game.isVisible(game.fighters[0], to: 1), "对面看不见")
        XCTAssertTrue(game.isVisible(game.fighters[0], to: 0), "自己这边看得见")
        game.adjust(1) { $0.pos = V2(6.5, 12.5) }
        XCTAssertTrue(game.isVisible(game.fighters[0], to: 1), "贴得很近看得见")
        game.adjust(1) { $0.pos = V2(9.5, 12.5) }
        run(&game, seconds: 2.6)
        XCTAssertTrue(game.isVisible(game.fighters[0], to: 1), "时间到了现身")
    }

    // MARK: 星徽

    func testStarPowers() {
        let tough = duel(.knight, loadout: ArenaLoadout(starPower: .tough))
        XCTAssertEqual(tough.fighters[0].maxHealth, Int((Double(Int((Double(Brawler.knight.health(level: 1)) * ArenaGame.playerEdge).rounded())) * 1.12).rounded()))
        XCTAssertEqual(tough.fighters[0].health, tough.fighters[0].maxHealth, "开局满血")

        let quick = duel(.ranger, loadout: ArenaLoadout(starPower: .quickload))
        XCTAssertEqual(quick.reloadTime(quick.fighters[0]), Brawler.ranger.reload * 0.8, accuracy: 1e-9)

        var far = duel(.ranger, loadout: ArenaLoadout(starPower: .farsight))
        far.adjust(1) { $0.pos = V2(9.5, 14.5) }
        far.step(dt, inputs: [0: ArenaInput(attack: V2(1, 0))])
        XCTAssertEqual(far.projectiles.first?.rangeLeft ?? 0, 10.5, accuracy: 0.4, "弩箭多飞 1.5 格")

        var knives = duel(.assassin, loadout: ArenaLoadout(starPower: .fiveKnives))
        knives.adjust(1) { $0.pos = V2(9.5, 14.5) }
        let first = knives.nextProjectile
        knives.step(dt, inputs: [0: ArenaInput(attack: V2(1, 0))])
        run(&knives, seconds: 0.6)
        XCTAssertEqual(knives.nextProjectile - first, 5, "一次掷 5 把")

        var blood = duel(.barbarian, loadout: ArenaLoadout(starPower: .bloodlust))
        blood.adjust(0) { $0.health = 1000 }
        blood.hurt(1, 1000, by: 0, charges: true)
        XCTAssertEqual(blood.fighters[0].health, 1150, "打中回 15%")

        var harvest = duel(.necromancer, loadout: ArenaLoadout(starPower: .harvest))
        harvest.adjust(0) { $0.health = 1000 }
        harvest.adjust(1) { $0.health = 10 }
        harvest.hurt(1, 500, by: 0, charges: true)
        XCTAssertFalse(harvest.fighters[1].alive)
        XCTAssertEqual(harvest.fighters[0].health, 2500, "打倒一个回 1500")

        var thorns = duel(.guardian, loadout: ArenaLoadout(starPower: .thorns))
        thorns.adjust(0) { $0.shield = 2 }
        let attacker = thorns.fighters[1].health
        thorns.hurt(0, 1000, by: 1, charges: true)
        XCTAssertEqual(attacker - thorns.fighters[1].health, 250, "举着骨盾时打人的掉血")

        var twin = duel(.summoner, loadout: ArenaLoadout(starPower: .twin))
        for _ in 0..<3 {
            twin.adjust(0) { $0.superCharge = 1 }
            twin.step(dt, inputs: [0: ArenaInput(special: V2(1, 0))])
        }
        XCTAssertEqual(twin.turrets.filter { $0.owner == 0 }.count, 2, "能同时放两座")
        var single = duel(.summoner)
        for _ in 0..<2 {
            single.adjust(0) { $0.superCharge = 1 }
            single.step(dt, inputs: [0: ArenaInput(special: V2(1, 0))])
        }
        XCTAssertEqual(single.turrets.filter { $0.owner == 0 }.count, 1)
    }

    // MARK: 超级充能

    /// 和大招一起攒（慢四倍）；满了再放大招是加强版，5 秒里走得快、打得疼、挨打少掉血
    func testHyperchargeChargesAndBoosts() throws {
        var game = duel(.mage, loadout: ArenaLoadout(hypercharge: true))
        let cost = game.superCost(game.fighters[0])
        game.adjust(1) { $0.health = 100_000 }
        game.hurt(1, Int(cost.rounded()), by: 0, charges: true)
        XCTAssertEqual(game.fighters[0].superCharge, 1, accuracy: 0.001)
        XCTAssertEqual(game.fighters[0].hyperCharge, 0.25, accuracy: 0.001, "超级充能攒得慢四倍")

        let speed = game.moveSpeed(game.fighters[0])
        game.adjust(0) { $0.hyperCharge = 1 }
        game.step(dt, inputs: [0: ArenaInput(special: V2(3, 0))])
        XCTAssertTrue(game.events.contains(.hyper(fighter: 0)))
        XCTAssertEqual(game.fighters[0].hyperCharge, 0)
        XCTAssertEqual(game.fighters[0].hyperTime, ArenaGame.hyperDuration, accuracy: 0.05)
        let meteor = try XCTUnwrap(game.projectiles.last?.lob)
        XCTAssertEqual(meteor.blast, 3, accuracy: 0.01, "陨石炸得更大")
        XCTAssertEqual(game.moveSpeed(game.fighters[0]), speed * 1.25, accuracy: 1e-9)
        XCTAssertEqual(game.power(0, 1000), 1232)
        let health = game.fighters[0].health
        game.hurt(0, 1000, by: 1, charges: true)
        XCTAssertEqual(health - game.fighters[0].health, 850)
        // 开着的时候不攒
        game.hurt(1, 1000, by: 0, charges: true)
        XCTAssertEqual(game.fighters[0].hyperCharge, 0)
        run(&game, seconds: ArenaGame.hyperDuration + 0.1)
        XCTAssertEqual(game.fighters[0].hyperTime, 0)
        XCTAssertEqual(game.moveSpeed(game.fighters[0]), speed, accuracy: 1e-9)

        // 没解锁的不攒、大招也不加强
        var plain = duel(.mage)
        plain.hurt(1, 1000, by: 0, charges: true)
        XCTAssertEqual(plain.fighters[0].hyperCharge, 0)
        plain.adjust(0) { $0.superCharge = 1; $0.hyperCharge = 1 }
        plain.step(dt, inputs: [0: ArenaInput(special: V2(3, 0))])
        XCTAssertFalse(plain.events.contains(.hyper(fighter: 0)))
        XCTAssertEqual(plain.projectiles.last?.lob?.blast ?? 0, 2.2, accuracy: 0.01)
    }

    // MARK: 成长、联机

    /// 按等级解锁（小道具 3、5 级，星徽 6、8 级，超级充能 9 级）；选的存下来；老版本存的读得出来
    func testProgressUnlocksAndChoices() throws {
        let old = Data(#"{"trophies":{"0":40},"levels":{"0":5},"coins":10,"reached":40}"#.utf8)
        var progress = try JSONDecoder().decode(ArenaProgress.self, from: old)
        XCTAssertEqual(progress.level(.knight), 5)
        XCTAssertEqual(progress.coins, 10)
        XCTAssertEqual(progress.gadgets(.knight), [.sprint, .ward])
        XCTAssertEqual(progress.starPowers(.knight), [])
        XCTAssertEqual(progress.loadout(for: .knight), ArenaLoadout(gadget: .sprint))
        XCTAssertEqual(ArenaProgress().loadout(for: .knight), ArenaLoadout(), "1 级什么都没有")

        progress.choose(.ward, for: .knight)
        progress.choose(.tough, for: .knight)
        XCTAssertEqual(progress.loadout(for: .knight), ArenaLoadout(gadget: .ward), "星徽还没解锁，选不了")
        progress.choose(.blink, for: .knight)
        XCTAssertEqual(progress.loadout(for: .knight).gadget, .ward, "别的角色的小道具选不了")

        let saved = try JSONDecoder().decode(ArenaProgress.self, from: JSONEncoder().encode(progress))
        XCTAssertEqual(saved, progress)
        XCTAssertEqual(saved.loadout(for: .knight), ArenaLoadout(gadget: .ward))

        let wanted = ArenaLoadout(gadget: .ward, starPower: .tough, hypercharge: true)
        XCTAssertEqual(wanted.allowed(.knight, level: 3), ArenaLoadout())
        XCTAssertEqual(wanted.allowed(.knight, level: 8), ArenaLoadout(gadget: .ward, starPower: .tough))
        XCTAssertEqual(wanted.allowed(.knight, level: 9), wanted)
        XCTAssertEqual(wanted.allowed(.mage, level: 9), ArenaLoadout(hypercharge: true))
        XCTAssertEqual(ArenaLoadout.basic(.mage, level: 9), ArenaLoadout(gadget: .blink, starPower: .bigFire, hypercharge: true))
    }

    /// 联机：小道具、超级充能的事件和每个人的状态都发得过去；老版本的包也读得出来
    func testSkillStateSurvivesTheNetwork() throws {
        let loadout = ArenaLoadout(gadget: .frost, hypercharge: true)
        var host = duel(.mage, .knight, loadout: loadout)
        host.adjust(0) { $0.hyperCharge = 0.6; $0.hyperTime = 3.2 }
        host.adjust(1) { $0.pos = V2(7, 12.5) }
        host.step(dt, inputs: [0: ArenaInput(gadget: true)])
        let packet = host.snapshot(events: host.events + [.hyper(fighter: 0), .hit(target: 1, amount: 400)]).encoded()
        let snapshot = try XCTUnwrap(ArenaSnapshot(data: packet))
        XCTAssertTrue(snapshot.events.contains(.gadget(fighter: 0)))
        XCTAssertTrue(snapshot.events.contains(.hyper(fighter: 0)))
        XCTAssertTrue(snapshot.events.contains(.hit(target: 1, amount: 400)))

        var client = duel(.mage, .knight, loadout: loadout)
        client.apply(snapshot)
        XCTAssertEqual(client.fighters[0].gadgetUses, 2)
        XCTAssertEqual(client.fighters[0].gadgetCooldown, host.fighters[0].gadgetCooldown, accuracy: 0.05)
        XCTAssertEqual(client.fighters[0].hyperCharge, 0.6, accuracy: 0.01)
        XCTAssertEqual(client.fighters[0].hyperTime, host.fighters[0].hyperTime, accuracy: 0.05)
        XCTAssertEqual(client.fighters[1].slowed, host.fighters[1].slowed, accuracy: 0.05)
        XCTAssertEqual(client.moveSpeed(client.fighters[1]), host.moveSpeed(host.fighters[1]), accuracy: 1e-9)

        // 老版本（第 3 段为止）读新包：后加的事件在最后一段，前面的照样读得出来
        let old = try XCTUnwrap(ArenaSnapshot(data: host.snapshot(events: [.gadget(fighter: 0), .hit(target: 1, amount: 9)]).encoded(version: 3)))
        XCTAssertEqual(old.events, [.hit(target: 1, amount: 9)])
        XCTAssertEqual(old.fighters[0].gadgetUses, 0)
    }

    /// 电脑带满级的本事打每种玩法：会用小道具、会开超级充能，打得完、不卡墙
    func testBotsUseSkillsInEveryMode() {
        var gadgets = 0, hypers = 0
        for mode in ArenaGame.Mode.allCases {
            let entrants = mode.seatTeams.enumerated().map { i, team in
                let brawler = Brawler.allCases[i % Brawler.allCases.count]
                return ArenaGame.Entrant(name: "电脑\(i)", brawler: brawler, isBot: true, team: team, level: 9,
                                         loadout: ArenaLoadout.basic(brawler, level: 9))
            }
            var game = ArenaGame(mode: mode, entrants: entrants, seed: 11)
            var bots = game.fighters.map { ArenaBot(id: $0.id, seed: 11) }
            while game.result == nil && game.time < mode.duration + 1 {
                var inputs: [Int: ArenaInput] = [:]
                for k in bots.indices { inputs[bots[k].id] = bots[k].input(in: game, dt: dt) }
                game.step(dt, inputs: inputs)
                for event in game.events {
                    if case .gadget = event { gadgets += 1 }
                    if case .hyper = event { hypers += 1 }
                }
                game.events.removeAll()
                for fighter in game.fighters where fighter.alive && !fighter.busy {
                    XCTAssertFalse(game.map.collides(fighter.pos, radius: ArenaGame.fighterRadius - 1e-6), "\(mode) \(fighter.name)")
                }
            }
            XCTAssertNotNil(game.result, "\(mode)")
            if mode == .boss {
                let boss = game.fighters.first(where: \.isBoss)
                XCTAssertNil(boss?.gadget, "骷髅王不带小道具")
                XCTAssertNil(boss?.starPower)
            }
        }
        XCTAssertGreaterThan(gadgets, 10, "电脑会用小道具")
        XCTAssertGreaterThan(hypers, 0, "电脑会开超级充能")
    }
}
