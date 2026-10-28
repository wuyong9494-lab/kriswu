import Foundation

// 冒险（原创故事）：草原村后面的老墓地里醒来了骷髅王，它的骷髅大军冲进村子抢东西。
// 勇者们一路从村口打到幽影森林，再打进骷髅王的墓地。三章，每章四关；每关是定好的一局
// （玩法、地图、对手、队友、骷髅王几级），开打前、打完各有几句对话。
// 赢了按表现给 1–3 颗星：赢了一颗；一次没被打倒两颗；第三颗看这一关的要求（多快打完或者打出多少伤害）。
// 第一次过关给金币，以后每多拿一颗星再给一点；打完一章，骷髅里有人投奔过来（不用攒奖杯就解锁）。冒险不加减奖杯。

/// 冒险里的故事和每一关
public enum ArenaStory {
    /// 谁在说话
    public enum Speaker: Equatable, Sendable {
        case brawler(Brawler)
        /// 骷髅王
        case king
        /// 草原村的村长
        case elder
        /// 旁白
        case narrator

        public var name: String {
            switch self {
            case .brawler(let brawler): return brawler.name
            case .king: return "骷髅王"
            case .elder: return "村长"
            case .narrator: return ""
            }
        }
    }

    /// 一句话
    public struct Line: Equatable, Sendable {
        public let speaker: Speaker
        public let text: String

        init(_ speaker: Speaker, _ text: String) {
            self.speaker = speaker
            self.text = text
        }
    }

    /// 第三颗星要做到的
    public enum Goal: Equatable, Sendable {
        /// 多少秒内打完
        case fast(Double)
        /// 一局打出多少伤害
        case damage(Int)

        public var note: String {
            switch self {
            case .fast(let seconds): return "\(Int(seconds)) 秒内过关"
            case .damage(let amount): return "打出 \(amount) 伤害"
            }
        }
    }

    /// 一关
    public struct Level: Identifiable, Equatable, Sendable {
        /// 「1-2」这样的编号
        public let id: String
        public let title: String
        public let mode: ArenaGame.Mode
        /// 地图（ArenaMap.id）
        public let map: String
        /// 对手（按座位排；一对一是对手按顺序上场的三个；讨伐骷髅王只看 bossLevel）
        public let enemies: [Brawler]
        /// 对手几级
        public let enemyLevel: Int
        /// 一起打的电脑队友
        public let allies: [Brawler]
        /// 讨伐骷髅王：骷髅王几级
        public let bossLevel: Int?
        public let goal: Goal
        /// 第一次过关给的金币
        public let coins: Int
        /// 开打前、打完说的话
        public let before: [Line]
        public let after: [Line]

        /// 这一关的开局：自己 + 电脑队友一队，对手一队（大乱斗各打各的）
        public func entrants(me: ArenaGame.Entrant) -> [ArenaGame.Entrant] {
            var list = [me]
            let friends = mode.seatTeams.filter { $0 == 0 }.count - 1
            for k in 0..<max(friends, 0) where !allies.isEmpty {
                let brawler = allies[k % allies.count]
                list.append(ArenaGame.Entrant(name: brawler.name, brawler: brawler, isBot: true, team: 0, level: me.level,
                                              loadout: ArenaLoadout.basic(brawler, level: me.level)))
            }
            if mode == .duel {
                let first = enemies.first ?? .shade
                list.append(ArenaGame.Entrant(name: first.name, brawler: first, isBot: true, team: 1, level: enemyLevel, lineup: enemies,
                                              loadout: ArenaLoadout.basic(first, level: enemyLevel)))
                return list
            }
            for (k, team) in mode.seatTeams.filter({ $0 != 0 }).enumerated() {
                let brawler = enemies.isEmpty ? Brawler.guardian : enemies[k % enemies.count]
                let name = mode == .boss ? "骷髅王" : brawler.name
                list.append(ArenaGame.Entrant(name: name, brawler: brawler, isBot: true, team: team, level: enemyLevel,
                                              loadout: ArenaLoadout.basic(brawler, level: enemyLevel)))
            }
            return list
        }

        /// 打完这一关得几颗星（没赢 0 颗）
        public func stars(in game: ArenaGame, me: Int) -> Int {
            guard game.fighters.indices.contains(me) else { return 0 }
            let mine = game.fighters[me]
            let won: Bool
            switch game.result {
            case .team(let team)?: won = team == mine.team
            case .survivor(let id)?: won = id == me
            default: won = false
            }
            guard won else { return 0 }
            var stars = 1
            if mine.deaths == 0 { stars += 1 }
            switch goal {
            case .fast(let seconds): if game.time <= seconds { stars += 1 }
            case .damage(let amount): if mine.damageDealt >= amount { stars += 1 }
            }
            return stars
        }
    }

    /// 一章
    public struct Chapter: Identifiable, Equatable, Sendable {
        public let id: Int
        public let title: String
        /// 这一章在哪
        public let place: String
        public let levels: [Level]
        /// 打完这一章投奔过来的骷髅
        public let recruits: [Brawler]
    }

    /// 打完一关拿到的
    public struct Reward: Equatable, Sendable {
        /// 这次的星（0 是没过关）、以前最好的星
        public var stars: Int
        public var best: Int
        public var coins: Int
        /// 第一次过关
        public var firstClear: Bool
        /// 打完一章投奔过来的
        public var recruited: [Brawler]
    }

    /// 全部的关（按顺序）
    public static var levels: [Level] { chapters.flatMap(\.levels) }

    public static func level(_ id: String) -> Level? { levels.first { $0.id == id } }

    /// 这一关后面那一关
    public static func next(after id: String) -> Level? {
        let all = levels
        guard let index = all.firstIndex(where: { $0.id == id }), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    /// 这一关是哪一章的
    public static func chapter(of id: String) -> Chapter? { chapters.first { $0.levels.contains { $0.id == id } } }

    /// 每多拿一颗星给的金币
    public static let coinsPerStar = 10

    // MARK: - 故事

    public static let chapters: [Chapter] = [
        Chapter(id: 1, title: "骷髅来了", place: "草原村", levels: [
            Level(id: "1-1", title: "村口遭遇", mode: .teamFight, map: "garden", enemies: [.guardian, .shade, .summoner], enemyLevel: 1,
                  allies: [.ranger, .mage], bossLevel: nil, goal: .fast(110), coins: 30,
                  before: [
                    Line(.narrator, "草原村的人一直以为，村后那片老墓地只是一堆长满青苔的石头。"),
                    Line(.narrator, "直到那天夜里，墓地里亮起了一片绿光。"),
                    Line(.elder, "不好了！骷髅从墓地里爬出来了，把村口的木箱都推倒了！"),
                    Line(.brawler(.knight), "村长别慌。游侠、法师，跟我去村口！"),
                  ],
                  after: [
                    Line(.brawler(.knight), "这些骷髅比看上去结实。"),
                    Line(.brawler(.ranger), "它们背着袋子跑了……袋子里是村里的星石！"),
                    Line(.elder, "星石是村子的护身符。丢了它，骷髅就能一直往村里冲。"),
                  ]),
            Level(id: "1-2", title: "夺回星石", mode: .stars, map: "crossroads", enemies: [.shade, .summoner, .guardian], enemyLevel: 2,
                  allies: [.barbarian, .ranger], bossLevel: nil, goal: .fast(130), coins: 30,
                  before: [
                    Line(.brawler(.barbarian), "抢星石？正好，我早就想活动活动筋骨了。"),
                    Line(.brawler(.shade), "嘻嘻，星石是骷髅王大人的，你们抢不走。"),
                  ],
                  after: [
                    Line(.brawler(.shade), "哼……这次算你们运气好。"),
                    Line(.brawler(.mage), "它们往金库那边去了！村里过冬的东西都在那儿！"),
                  ]),
            Level(id: "1-3", title: "守住金库", mode: .heist, map: "vault", enemies: [.guardian, .necromancer, .shade], enemyLevel: 2,
                  allies: [.knight, .mage], bossLevel: nil, goal: .damage(9000), coins: 40,
                  before: [
                    Line(.elder, "金库里是过冬的粮食和金币，绝不能让它们打开！"),
                    Line(.brawler(.guardian), "骷髅王大人要的东西，从来没有拿不到的。"),
                    Line(.brawler(.knight), "守住自己的宝箱，再去拆它们的！"),
                  ],
                  after: [
                    Line(.brawler(.guardian), "……撤！回墓地，报告骷髅王大人。"),
                    Line(.brawler(.knight), "终于要见到这个骷髅王了。"),
                  ]),
            Level(id: "1-4", title: "骷髅王现身", mode: .boss, map: "lair", enemies: [], enemyLevel: 2,
                  allies: [.barbarian, .ranger], bossLevel: 2, goal: .fast(120), coins: 60,
                  before: [
                    Line(.king, "是谁，在我的墓地前面吵吵闹闹？"),
                    Line(.brawler(.knight), "你的骷髅抢了草原村的东西，我们是来拿回来的。"),
                    Line(.king, "有意思。那就让我看看，活人的骨头有多硬！"),
                    Line(.brawler(.ranger), "小心地上的红圈，那是它要砸下来的地方！"),
                  ],
                  after: [
                    Line(.king, "咳……我的骨头……散了……"),
                    Line(.narrator, "骷髅王散成一地骨头，又慢慢沉进了墓地深处。"),
                    Line(.brawler(.summoner), "等、等一下！我不想再给骷髅王卖命了。让我跟着你们吧？"),
                    Line(.brawler(.knight), "……好吧。只要你别再推倒村里的木箱。"),
                    Line(.narrator, "骨灵加入了勇者们！"),
                  ]),
        ], recruits: [.summoner]),
        Chapter(id: 2, title: "幽影森林", place: "森林深处", levels: [
            Level(id: "2-1", title: "林中伏击", mode: .showdown, map: "grove", enemies: [.shade, .necromancer, .summoner, .guardian, .shade],
                  enemyLevel: 3, allies: [], bossLevel: nil, goal: .damage(7000), coins: 50,
                  before: [
                    Line(.narrator, "骷髅王逃进了幽影森林。勇者们分头去找。"),
                    Line(.brawler(.assassin), "森林里太安静了……小心，四面都是埋伏。"),
                    Line(.narrator, "这一关只有你一个人：活到最后。"),
                  ],
                  after: [
                    Line(.brawler(.assassin), "解决了。可我总觉得，有谁一直在影子里看着。"),
                    Line(.brawler(.shade), "被你发现了。来，和我单挑！"),
                  ]),
            Level(id: "2-2", title: "影子的挑战", mode: .duel, map: "glade", enemies: [.shade, .summoner, .necromancer], enemyLevel: 3,
                  allies: [], bossLevel: nil, goal: .fast(100), coins: 50,
                  before: [
                    Line(.brawler(.shade), "一对一。我带两个帮手轮流上，你也挑三个来！"),
                    Line(.brawler(.knight), "那就一个一个来。"),
                    Line(.narrator, "一对一：每边三个角色轮流上，先打倒对方三个的赢。"),
                  ],
                  after: [
                    Line(.brawler(.shade), "我输了……骷髅王说过，打输的骷髅要被扔进亡灵池。"),
                    Line(.brawler(.mage), "那就别回去了。"),
                    Line(.brawler(.shade), "……我考虑考虑。先告诉你们：森林中间有个法阵，骷髅王靠它恢复力量。"),
                  ]),
            Level(id: "2-3", title: "亡灵法阵", mode: .zone, map: "fortress", enemies: [.necromancer, .necromancer, .guardian], enemyLevel: 4,
                  allies: [.mage, .knight], bossLevel: nil, goal: .damage(8000), coins: 60,
                  before: [
                    Line(.brawler(.necromancer), "法阵已经点亮，骷髅王大人马上就能恢复力量。"),
                    Line(.brawler(.mage), "站到法阵中间去！不能让它们占着那块地。"),
                  ],
                  after: [
                    Line(.brawler(.necromancer), "法阵……被打乱了……"),
                    Line(.king, "没用的东西！我亲自来！"),
                  ]),
            Level(id: "2-4", title: "骷髅王的反击", mode: .boss, map: "lair", enemies: [], enemyLevel: 5,
                  allies: [.assassin, .mage], bossLevel: 5, goal: .fast(130), coins: 90,
                  before: [
                    Line(.king, "上次是我大意了。这一次，我要让整片森林都变成墓地！"),
                    Line(.brawler(.barbarian), "说大话的骷髅，我见得多了。"),
                    Line(.narrator, "骷髅王血少了会发狂：砸地更快、会冲撞。"),
                  ],
                  after: [
                    Line(.king, "这……这不可能……"),
                    Line(.narrator, "骷髅王又一次散成了骨头，滚回了它最深的墓穴。"),
                    Line(.brawler(.shade), "它的墓穴在墓地最里面。我带你们去——我跟你们走了。"),
                    Line(.narrator, "幽影加入了勇者们！"),
                  ]),
        ], recruits: [.shade]),
        Chapter(id: 3, title: "骷髅王的墓地", place: "墓地深处", levels: [
            Level(id: "3-1", title: "墓地大门", mode: .knockout, map: "canyon", enemies: [.guardian, .guardian, .necromancer], enemyLevel: 6,
                  allies: [.knight, .barbarian], bossLevel: nil, goal: .fast(200), coins: 70,
                  before: [
                    Line(.brawler(.guardian), "墓地的大门，骨盾卫守了一千年，从没让人过去！"),
                    Line(.brawler(.knight), "那今天就是第一次。"),
                    Line(.narrator, "三局两胜：倒下了这一局就不能再起来。"),
                  ],
                  after: [
                    Line(.brawler(.guardian), "……门……开了……"),
                    Line(.brawler(.summoner), "里面的骷髅都在等着领骷髅王的悬赏。"),
                  ]),
            Level(id: "3-2", title: "悬赏令", mode: .bounty, map: "crossroads", enemies: [.shade, .summoner, .necromancer], enemyLevel: 7,
                  allies: [.assassin, .ranger], bossLevel: nil, goal: .damage(10000), coins: 70,
                  before: [
                    Line(.brawler(.necromancer), "骷髅王大人发了悬赏：谁打倒勇者，谁就能拿走最多的星星！"),
                    Line(.brawler(.assassin), "那就让它们看看，悬赏是怎么被收回去的。"),
                  ],
                  after: [
                    Line(.brawler(.ranger), "骷髅越来越少了。墓穴就在前面。"),
                  ]),
            Level(id: "3-3", title: "骨头球场", mode: .ball, map: "sandPitch", enemies: [.guardian, .summoner, .shade], enemyLevel: 7,
                  allies: [.barbarian, .knight], bossLevel: nil, goal: .fast(110), coins: 80,
                  before: [
                    Line(.brawler(.summoner), "墓穴前面这块空地……以前骷髅们拿头骨当球踢。"),
                    Line(.brawler(.barbarian), "踢球？这个我在行。"),
                    Line(.brawler(.guardian), "想过去？先在球场上赢了我们！"),
                  ],
                  after: [
                    Line(.brawler(.guardian), "好球……我们心服口服。"),
                    Line(.brawler(.summoner), "大家，最后一战了。"),
                  ]),
            Level(id: "3-4", title: "最后的墓穴", mode: .boss, map: "lair", enemies: [], enemyLevel: 9,
                  allies: [.mage, .ranger], bossLevel: 9, goal: .fast(140), coins: 150,
                  before: [
                    Line(.king, "你们一路打到这里，连我的骷髅都跟着你们跑了。"),
                    Line(.king, "但墓穴是我的地盘。在这里，我不会再倒下！"),
                    Line(.brawler(.knight), "大家——为了草原村！"),
                  ],
                  after: [
                    Line(.king, "原来……有人一起守着的地方……是这么暖和……"),
                    Line(.narrator, "骷髅王身上的绿光慢慢熄灭，墓地重新安静了下来。"),
                    Line(.brawler(.necromancer), "骷髅王睡着了。我们……以后可以住在村子旁边吗？"),
                    Line(.elder, "当然！草原村永远欢迎你们。今晚办一场庆典！"),
                    Line(.brawler(.shade), "庆典之后呢？"),
                    Line(.brawler(.barbarian), "当然是去乱斗场上再打一场！"),
                    Line(.narrator, "亡灵巫师和骨盾卫加入了勇者们！冒险完成。"),
                  ]),
        ], recruits: [.necromancer, .guardian]),
    ]
}

extension ArenaProgress {
    /// 冒险：这一关最好拿过几颗星（没过 0）
    public func stars(_ level: String) -> Int { storyStars[level] ?? 0 }

    /// 冒险一共拿了几颗星
    public var totalStoryStars: Int { storyStars.values.reduce(0, +) }

    /// 这一关能不能打：第一关，或者前一关过了
    public func isOpen(_ level: String) -> Bool {
        let all = ArenaStory.levels
        guard let index = all.firstIndex(where: { $0.id == level }) else { return false }
        return index == 0 || stars(all[index - 1].id) > 0
    }

    /// 打完一关：记下最好的星，第一次过关给金币、多拿的星给金币，打完一章骷髅投奔过来
    public mutating func finish(_ level: ArenaStory.Level, stars: Int) -> ArenaStory.Reward {
        let best = self.stars(level.id)
        let earned = min(max(stars, 0), 3)
        var reward = ArenaStory.Reward(stars: earned, best: max(best, earned), coins: 0, firstClear: best == 0 && earned > 0, recruited: [])
        guard earned > best else { return reward }
        storyStars[level.id] = earned
        reward.coins = (reward.firstClear ? level.coins : 0) + (earned - best) * ArenaStory.coinsPerStar
        addCoins(reward.coins)
        if reward.firstClear, let chapter = ArenaStory.chapter(of: level.id), chapter.levels.last?.id == level.id {
            let fresh = chapter.recruits.filter { !isUnlocked($0) }
            recruit(chapter.recruits)
            reward.recruited = fresh
        }
        return reward
    }
}
