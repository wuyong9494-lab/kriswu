import Foundation

// 乱斗角色的本事除了普通攻击、大招，还有：
// - 小道具：开打前选一个带上，一局能用 3 次，用一次等 6 秒（3 级解锁第一个，5 级第二个）；
// - 星徽：一直有效的被动本事，开打前选一个（6 级解锁第一个，8 级第二个）；
// - 超级充能：满级（9 级）解锁，打人攒一条紫色的充能，满了再放大招就是加强版，5 秒里走得快、打得疼、挨打少掉血

/// 小道具（每个角色能选两种里的一种）
public enum Gadget: Int, CaseIterable, Codable, Sendable {
    case sprint, potion, ward, roll, reload, shockwave, frost, vanish, blink

    public var name: String {
        ["疾行", "药水", "铁壁", "翻滚", "装弹", "震地", "冰霜", "隐身", "闪烁"][rawValue]
    }

    public var note: String {
        switch self {
        case .sprint: return "3 秒里走得快一半"
        case .potion: return "马上回 1800 血"
        case .ward: return "2.5 秒里受到的伤害少六成"
        case .roll: return "往摇杆方向翻滚 3 格"
        case .reload: return "子弹马上装满"
        case .shockwave: return "把身边的敌人震开、打 700"
        case .frost: return "身边 3 格里的敌人 2.5 秒走得慢，打 400"
        case .vanish: return "2.5 秒里敌人看不见你（开火会现身）"
        case .blink: return "往前闪 3.5 格，能穿墙"
        }
    }

    public var emoji: String { ["💨", "🧪", "🛡", "🌀", "🔄", "💥", "❄️", "🫥", "✨"][rawValue] }
}

/// 星徽：一直有效的被动本事（每个角色两种里选一种）
public enum StarPower: Int, CaseIterable, Codable, Sendable {
    case chivalry, tough, quickload, farsight, bloodlust, quake, bigFire, surge, fiveKnives, swift,
         longShield, thorns, feast, harvest, ambush, ghost, sturdy, twin

    public var name: String {
        ["骑士精神", "坚韧", "快装", "远视", "嗜血", "震荡", "大火球", "法力涌动", "五刃", "疾风",
         "长盾", "反震", "亡灵盛宴", "灵魂收割", "暗影突袭", "鬼魅", "坚固骨塔", "双塔"][rawValue]
    }

    public var note: String {
        switch self {
        case .chivalry: return "冲锋撞到一个人回 800 血"
        case .tough: return "满血多 12%"
        case .quickload: return "装弹快 20%"
        case .farsight: return "弩箭多飞 1.5 格"
        case .bloodlust: return "打中人回打出伤害的 15%"
        case .quake: return "跳下来砸中的人 2 秒走得慢"
        case .bigFire: return "火球炸开大四分之一"
        case .surge: return "大招攒得快 20%"
        case .fiveKnives: return "一次掷 5 把飞刀"
        case .swift: return "走得快 10%"
        case .longShield: return "骨盾撑 6 秒"
        case .thorns: return "举着骨盾时，打你的人每下掉 250 血"
        case .feast: return "亡灵之地留 7 秒"
        case .harvest: return "打倒一个人回 1500 血"
        case .ambush: return "闪现落地的伤害多四成"
        case .ghost: return "在草丛里走得快 20%"
        case .sturdy: return "骨塔的血多一半"
        case .twin: return "能同时放两座骨塔"
        }
    }
}

extension Brawler {
    /// 能选的两个小道具
    public var gadgets: [Gadget] {
        switch self {
        case .knight: return [.sprint, .ward]
        case .ranger: return [.roll, .reload]
        case .barbarian: return [.shockwave, .potion]
        case .mage: return [.blink, .frost]
        case .assassin: return [.vanish, .sprint]
        case .guardian: return [.shockwave, .ward]
        case .necromancer: return [.potion, .frost]
        case .shade: return [.vanish, .reload]
        case .summoner: return [.frost, .roll]
        }
    }

    /// 能选的两个星徽
    public var starPowers: [StarPower] {
        let all = StarPower.allCases
        return [all[rawValue * 2], all[rawValue * 2 + 1]]
    }

    /// 超级充能后大招变成什么样
    public var hyperNote: String {
        ["冲锋冲得更远、撞得更疼", "重弩更粗、更疼", "砸地的范围更大", "陨石炸得更大", "飞刀多一半",
         "骨盾回的血翻倍", "亡灵之地更大", "闪现落地炸得更大", "骨塔的血翻倍"][rawValue]
    }
}

/// 开打前带上的东西（按等级解锁、自己选）
public struct ArenaLoadout: Equatable, Codable, Sendable {
    public var gadget: Gadget?
    public var starPower: StarPower?
    public var hypercharge: Bool
    /// 穿哪套皮肤（第几套，nil 是原来的样子；只是样子，别人也看得见）
    public var skin: Int?

    public init(gadget: Gadget? = nil, starPower: StarPower? = nil, hypercharge: Bool = false, skin: Int? = nil) {
        self.gadget = gadget
        self.starPower = starPower
        self.hypercharge = hypercharge
        self.skin = skin
    }

    /// 这个等级能带的（电脑补位按等级带第一个）
    public static func basic(_ brawler: Brawler, level: Int) -> ArenaLoadout {
        ArenaLoadout(gadget: gadgets(brawler, level: level).first, starPower: starPowers(brawler, level: level).first,
                     hypercharge: level >= ArenaProgress.hyperLevel)
    }

    /// 这个角色到这个等级解锁了哪几个小道具
    public static func gadgets(_ brawler: Brawler, level: Int) -> [Gadget] {
        zip(brawler.gadgets, ArenaProgress.gadgetLevels).filter { level >= $0.1 }.map { $0.0 }
    }

    /// 这个角色到这个等级解锁了哪几个星徽
    public static func starPowers(_ brawler: Brawler, level: Int) -> [StarPower] {
        zip(brawler.starPowers, ArenaProgress.starLevels).filter { level >= $0.1 }.map { $0.0 }
    }

    /// 只留这个角色、这个等级能带的（联机时别人发来的也按这个检查一遍）
    public func allowed(_ brawler: Brawler, level: Int) -> ArenaLoadout {
        ArenaLoadout(gadget: gadget.flatMap { Self.gadgets(brawler, level: level).contains($0) ? $0 : nil },
                     starPower: starPower.flatMap { Self.starPowers(brawler, level: level).contains($0) ? $0 : nil },
                     hypercharge: hypercharge && level >= ArenaProgress.hyperLevel,
                     skin: skin.flatMap { (1...2).contains($0) ? $0 : nil })
    }
}

extension ArenaGame {
    public static let gadgetUses = 3
    public static let gadgetCooldown = 6.0
    /// 超级充能：5 秒；攒满要打出的伤害是大招的几倍
    public static let hyperDuration = 5.0
    static let hyperCost = 4.0

    /// 带上小道具、星徽、超级充能（不是这个角色的就不带）
    static func equip(_ fighter: inout Fighter, _ loadout: ArenaLoadout) {
        let brawler = fighter.brawler
        fighter.gadget = loadout.gadget.flatMap { brawler.gadgets.contains($0) ? $0 : nil }
        fighter.gadgetUses = fighter.gadget == nil ? 0 : gadgetUses
        fighter.gadgetCooldown = 0
        fighter.starPower = loadout.starPower.flatMap { brawler.starPowers.contains($0) ? $0 : nil }
        fighter.hyperUnlocked = loadout.hypercharge
        fighter.skin = loadout.skin.flatMap { (1...2).contains($0) ? $0 : nil } ?? 0
        fighter.health = fighter.maxHealth
    }

    // MARK: 数值（按星徽、超级充能、小道具的状态算）

    /// 现在每秒走几格
    public func moveSpeed(_ fighter: Fighter) -> Double {
        var speed = fighter.brawler.speed
        if fighter.isBoss { return speed }
        if fighter.starPower == .swift { speed *= 1.1 }
        if fighter.starPower == .ghost, map.inBush(fighter.pos) { speed *= 1.2 }
        if fighter.speedBoost > 0 { speed *= 1.5 }
        if fighter.hyperTime > 0 { speed *= 1.25 }
        if fighter.slowed > 0 { speed *= 0.6 }
        return speed
    }

    /// 装一发弹要几秒
    func reloadTime(_ fighter: Fighter) -> Double {
        fighter.brawler.reload * (fighter.starPower == .quickload ? 0.8 : 1)
    }

    /// 攒满一次大招要打出多少伤害（等级高的伤害大，要的也多：打中几下攒满不变）
    func superCost(_ fighter: Fighter) -> Double {
        fighter.brawler.superCost * Brawler.boost(fighter.level) * (fighter.starPower == .surge ? 0.8 : 1)
    }

    /// 受到的伤害打几折（骨盾、铁壁少六成，超级充能少一成半）
    func damageTaken(_ fighter: Fighter) -> Double {
        (fighter.shield > 0 ? 0.4 : 1) * (fighter.hyperTime > 0 ? 0.85 : 1)
    }

    // MARK: 小道具

    /// 用小道具（还有次数、不在等）
    mutating func useGadget(_ i: Int, move: V2) {
        guard let gadget = fighters[i].gadget, fighters[i].gadgetUses > 0, fighters[i].gadgetCooldown <= 0,
              fighters[i].alive, !fighters[i].busy else { return }
        fighters[i].gadgetUses -= 1
        fighters[i].gadgetCooldown = Self.gadgetCooldown
        let fighter = fighters[i]
        let direction = move.length > 0.1 ? move.normalized : fighter.facing
        switch gadget {
        case .sprint:
            fighters[i].speedBoost = 3
        case .potion:
            let healed = min(power(i, 1800), fighter.maxHealth - fighter.health)
            if healed > 0 {
                fighters[i].health += healed
                events.append(.heal(target: i, amount: healed))
            }
        case .ward:
            fighters[i].shield = max(fighters[i].shield, 2.5)
        case .roll:
            fighters[i].dash = Fighter.Dash(direction: direction, remaining: 3, hit: [], harmless: true)
        case .reload:
            fighters[i].ammo = 3
        case .shockwave:
            for j in fighters.indices where fighters[j].alive && fighters[j].team != fighter.team && !fighters[j].isBoss
                && fighters[j].pos.distance(to: fighter.pos) < 2.5 {
                let away = (fighters[j].pos - fighter.pos).normalized
                fighters[j].pos = Self.walk(from: fighters[j].pos, by: (away.length > 0 ? away : direction) * 1.6, on: map)
                hurt(j, power(i, 700), by: i, charges: true)
            }
            events.append(.explosion(at: fighter.pos, radius: 2.5))
        case .frost:
            for j in fighters.indices where fighters[j].alive && fighters[j].team != fighter.team
                && fighters[j].pos.distance(to: fighter.pos) < 3 + Self.hitRadius(fighters[j]) {
                fighters[j].slowed = max(fighters[j].slowed, 2.5)
                hurt(j, power(i, 400), by: i, charges: true)
            }
        case .vanish:
            fighters[i].invisible = 2.5
        case .blink:
            fighters[i].pos = map.nearestOpen(to: fighter.pos + direction * 3.5)
            fighters[i].moving = .zero
        }
        events.append(.gadget(fighter: i))
    }

    /// 每帧：小道具、超级充能、加速减速隐身的倒计时
    mutating func tickStatus(_ i: Int, _ dt: Double) {
        if fighters[i].gadgetCooldown > 0 { fighters[i].gadgetCooldown = max(0, fighters[i].gadgetCooldown - dt) }
        if fighters[i].speedBoost > 0 { fighters[i].speedBoost = max(0, fighters[i].speedBoost - dt) }
        if fighters[i].slowed > 0 { fighters[i].slowed = max(0, fighters[i].slowed - dt) }
        if fighters[i].invisible > 0 { fighters[i].invisible = max(0, fighters[i].invisible - dt) }
        if fighters[i].hyperTime > 0 { fighters[i].hyperTime = max(0, fighters[i].hyperTime - dt) }
    }

    /// 打出伤害攒超级充能（和大招一起攒，慢四倍；开着的时候不攒）
    mutating func chargeHyper(_ attacker: Int, _ amount: Int) {
        guard fighters[attacker].hyperUnlocked, fighters[attacker].hyperTime <= 0 else { return }
        let cost = superCost(fighters[attacker]) * Self.hyperCost
        fighters[attacker].hyperCharge = min(1, fighters[attacker].hyperCharge + Double(amount) / cost)
    }

    /// 放大招时超级充能满了：开 5 秒超级充能
    mutating func startHyper(_ i: Int) -> Bool {
        guard fighters[i].hyperUnlocked, fighters[i].hyperCharge >= 1 else { return false }
        fighters[i].hyperCharge = 0
        fighters[i].hyperTime = Self.hyperDuration
        events.append(.hyper(fighter: i))
        return true
    }
}
