import Foundation

/// 乱斗的一局：自己（摇杆）加上电脑补位的人，按 1/60 秒一帧往前算；画面每帧来拿最新的样子。
/// 上面那排比分、血量这些每 0.1 秒更新一次（不用每帧刷 SwiftUI）
@MainActor
final class ArenaController: ObservableObject {
    struct HUD: Equatable {
        var timeLeft = 0
        /// 两队的分（团战：打倒几次；抢星星：几颗；占点：百分之几）
        var blue = 0
        var red = 0
        /// 抢星星：哪队在倒数、还剩几秒
        var countdownTeam: Int?
        var countdownLeft = 0
        /// 大乱斗：还剩几个人
        var alive = 0
        var poisonShrinking = false
        var health = 0
        var maxHealth = 1
        var superCharge = 0.0
        var dead = false
        var respawnIn = 0
        var result: ArenaGame.Result?
    }

    struct Setup: Equatable {
        var mode: ArenaGame.Mode
        var brawler: Brawler
        var name: String
    }

    static let step = 1.0 / 60

    let setup: Setup
    let me: Int
    private(set) var game: ArenaGame
    private var bots: [ArenaBot]
    private var accumulator = 0.0
    private var hudTimer = 0.0
    @Published private(set) var hud = HUD()
    /// 走的摇杆（长度 0–1）
    var move = V2.zero
    /// 正在拖的攻击 / 大招摇杆（画瞄准线用；长度 0–1，占射程的比例）
    var aiming: V2?
    var superAiming: V2?
    private var queuedAttack: V2?
    private var queuedSpecial: V2?
    private var recorded = false

    init(setup: Setup, seed: UInt64 = UInt64.random(in: 0..<UInt64.max)) {
        self.setup = setup
        var random = SeededRandom(seed: seed)
        var others = Brawler.allCases.filter { $0 != setup.brawler }
        random.shuffle(&others)
        let count = 5
        var entrants = [ArenaGame.Entrant(name: setup.name.isEmpty ? "我" : setup.name, brawler: setup.brawler, isBot: false, team: 0)]
        for k in 0..<count {
            let brawler = others[k % others.count]
            let team = setup.mode.isTeams ? (k < 2 ? 0 : 1) : k + 1
            entrants.append(ArenaGame.Entrant(name: "电脑\(brawler.name)", brawler: brawler, isBot: true, team: team))
        }
        game = ArenaGame(mode: setup.mode, entrants: entrants, seed: seed)
        me = 0
        bots = game.fighters.filter(\.isBot).map { ArenaBot(id: $0.id, seed: seed) }
        refreshHUD()
    }

    var mine: Fighter { game.fighters[me] }

    /// 画面每帧调：按真实过去的时间往前算几帧
    func advance(_ elapsed: Double) {
        guard game.result == nil else { return }
        accumulator = min(accumulator + max(elapsed, 0), 0.25)
        while accumulator >= Self.step {
            accumulator -= Self.step
            tick()
        }
        hudTimer += elapsed
        if hudTimer >= 0.1 || game.result != nil {
            hudTimer = 0
            refreshHUD()
        }
    }

    private func tick() {
        var inputs: [Int: ArenaInput] = [me: ArenaInput(move: move, attack: queuedAttack, special: queuedSpecial)]
        queuedAttack = nil
        queuedSpecial = nil
        for k in bots.indices {
            inputs[bots[k].id] = bots[k].input(in: game, dt: Self.step)
        }
        game.step(Self.step, inputs: inputs)
    }

    /// 这一帧发生的事（画特效用），拿走就清掉
    func takeEvents() -> [ArenaGame.Event] {
        let events = game.events
        game.events.removeAll()
        return events
    }

    /// 松开攻击摇杆：拖得很短算点了一下，自动瞄射程里最近的敌人
    func fire(_ drag: V2) {
        queuedAttack = target(for: drag, range: mine.brawler.attackRange)
    }

    func fireSpecial(_ drag: V2) {
        guard mine.superCharge >= 1 else { return }
        queuedSpecial = target(for: drag, range: mine.brawler.superRange)
    }

    private func target(for drag: V2, range: Double) -> V2 {
        if drag.length > 0.25 { return drag.normalized * (max(drag.length, 0.35) * range) }
        let fighter = mine
        let enemies = game.fighters.filter {
            $0.alive && $0.team != fighter.team && game.isVisible($0, to: fighter.team) && $0.pos.distance(to: fighter.pos) <= range + 1
        }
        if let enemy = enemies.min(by: { $0.pos.distance(to: fighter.pos) < $1.pos.distance(to: fighter.pos) }) {
            return enemy.pos - fighter.pos
        }
        return fighter.facing * range
    }

    private func refreshHUD() {
        var hud = HUD()
        hud.timeLeft = Int(game.timeLeft.rounded(.up))
        switch game.mode {
        case .teamFight:
            hud.blue = game.teamKills[0]
            hud.red = game.teamKills[1]
        case .stars:
            hud.blue = game.teamStars(0)
            hud.red = game.teamStars(1)
            hud.countdownTeam = game.countdown?.team
            hud.countdownLeft = Int((game.countdown?.left ?? 0).rounded(.up))
        case .zone:
            hud.blue = Int(game.zoneProgress[0])
            hud.red = Int(game.zoneProgress[1])
        case .showdown:
            hud.alive = game.aliveCount
            hud.poisonShrinking = game.time > 15
        }
        let fighter = mine
        hud.health = fighter.health
        hud.maxHealth = fighter.maxHealth
        hud.superCharge = fighter.superCharge
        hud.dead = !fighter.alive
        hud.respawnIn = Int(fighter.respawnIn.rounded(.up))
        // 大乱斗被打倒就算结束（不用看电脑打完）
        if game.mode == .showdown, !fighter.alive, game.result == nil {
            hud.result = .survivor(-1)
        } else {
            hud.result = game.result
        }
        if hud.result != nil, !recorded {
            recorded = true
            ArenaRecords.shared.add(mode: game.mode, won: won(hud.result))
        }
        if hud != self.hud { self.hud = hud }
    }

    func won(_ result: ArenaGame.Result?) -> Bool {
        switch result {
        case .team(let team)?: return team == mine.team
        case .survivor(let id)?: return id == me
        default: return false
        }
    }

    /// 大乱斗第几名
    var place: Int? { mine.place }
}

/// 乱斗战绩：每种玩法玩了几局、赢了几局（只存在这台手机上）
@MainActor
final class ArenaRecords: ObservableObject {
    static let shared = ArenaRecords()
    private static let key = "arena.records"

    struct Tally: Codable, Equatable {
        var played: [String: Int] = [:]
        var won: [String: Int] = [:]
    }

    @Published private(set) var tally: Tally

    private init() {
        tally = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Tally.self, from: $0) } ?? Tally()
    }

    func add(mode: ArenaGame.Mode, won: Bool) {
        tally.played[mode.rawValue, default: 0] += 1
        if won { tally.won[mode.rawValue, default: 0] += 1 }
        if let data = try? JSONEncoder().encode(tally) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
