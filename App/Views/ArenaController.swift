import Foundation

/// 联机时开一局要的：玩法、种子、每个座位是谁（房主定好发给大家，大家照着摆出一模一样的一局）
struct ArenaStart: Codable, Equatable {
    struct Seat: Codable, Equatable {
        /// 房间里的谁；nil 是电脑
        var member: String?
        var name: String
        var brawler: Brawler
        var team: Int
        /// 角色等级；老版本房主发来的没有，按 1 级
        var level: Int?
        /// 一对一带的角色（老版本没有）
        var lineup: [Brawler]?
        /// 带的小道具、星徽、超级充能（老版本没有：按等级带第一个）
        var loadout: ArenaLoadout?
    }

    var round: Int
    var mode: ArenaGame.Mode
    var seed: UInt64
    var seats: [Seat]
    /// 地图（ArenaMap.id）；老版本房主发来的没有，用这个玩法的第一张
    var map: String?

    var entrants: [ArenaGame.Entrant] {
        seats.map {
            let level = $0.level ?? 1
            // 带的东西按等级再查一遍（每台手机都这么查，摆出来的一样）
            let loadout = ($0.loadout ?? ArenaLoadout.basic($0.brawler, level: level)).allowed($0.brawler, level: level)
            return ArenaGame.Entrant(name: $0.name, brawler: $0.brawler, isBot: $0.member == nil, team: $0.team, level: level,
                                     lineup: $0.lineup ?? [], loadout: loadout)
        }
    }
}

/// 乱斗的一局。三种：
/// - 自己和电脑打：这台手机按 1/60 秒一帧往前算；
/// - 联机的房主：一样往前算，别人的摇杆从网上来，每 3 帧把画面打成一小包发给大家；
/// - 联机的其他人：只发摇杆，收房主的画面照着摆；两包之间子弹、别人先接着刚才的速度走，自己走路不等房主（先走，房主的位置来了再把还没算到的那几步补上）。
/// 上面那排比分、血量这些每 0.1 秒更新一次（不用每帧刷 SwiftUI）
@MainActor
final class ArenaController: ObservableObject {
    enum Role { case solo, host, client }

    struct HUD: Equatable {
        var timeLeft = 0
        /// 两队的分（团战：打倒几次；抢星星：几颗；占点：百分之几；足球：进了几球；宝箱攻防：宝箱剩百分之几；
        /// 悬赏：几颗星；三局两胜：赢了几局；一对一：打倒对方几个）
        var blue = 0
        var red = 0
        /// 三局两胜：第几局
        var round = 1
        /// 讨伐骷髅王：骷髅王的血
        var bossHealth = 0
        var bossMaxHealth = 1
        /// 双人大乱斗：还剩几队
        var teamsLeft = 0
        /// 抢星星：哪队在倒数、还剩几秒
        var countdownTeam: Int?
        var countdownLeft = 0
        /// 大乱斗：还剩几个人
        var alive = 0
        var poisonShrinking = false
        var health = 0
        var maxHealth = 1
        var superCharge = 0.0
        /// 小道具：带的哪个、还能用几次、还要等几秒
        var gadget: Gadget?
        var gadgetUses = 0
        var gadgetCooldown = 0
        /// 超级充能：解锁了没有、攒了多少、开着还剩几秒
        var hyperUnlocked = false
        var hyperCharge = 0.0
        var hyperTime = 0.0
        var dead = false
        var respawnIn = 0
        var result: ArenaGame.Result?
    }

    struct Setup: Equatable {
        var mode: ArenaGame.Mode
        var brawler: Brawler
        var name: String
        /// 自己这个角色的等级（电脑补位的也按这个等级）
        var level = 1
        /// 一对一带的另外两个角色
        var lineup: [Brawler] = []
        /// 带的小道具、星徽、超级充能
        var loadout = ArenaLoadout()
        /// 冒险的一关（玩法、地图、对手、队友都按这一关的）
        var story: ArenaStory.Level?
        /// 排位赛（只打 3v3，不加减奖杯，按段位加减排位分）；电脑补位的等级（nil：和自己一样）
        var ranked = false
        var botLevel: Int?
        /// 截图用：停在开场对阵画面、直接到结算
        var demo: Demo?
        var benchmark = false
        var benchmarkStill = false
        var sampleMap = false

        enum Demo { case versus, result }
    }

    static let step = 1.0 / 60

    let role: Role
    let me: Int
    private(set) var game: ArenaGame
    private weak var room: GameRoom?
    private var bots: [ArenaBot]
    private var accumulator = 0.0
    private(set) var benchmark = false
    private(set) var benchmarkStill = false
    private(set) var sampleMap = false
    private(set) var benchmarkSteps = 0
    private(set) var benchmarkCycles = 0
    private var cycleSteps = 0
    private var hudTimer = 0.0
    @Published private(set) var hud = HUD()
    /// 打完这局得到的奖杯、金币（结果出来时记一次）
    @Published private(set) var reward: ArenaProgress.Reward?
    /// 冒险的一关：打的是哪一关、打完拿了几颗星和金币
    private(set) var story: ArenaStory.Level?
    @Published private(set) var storyReward: ArenaStory.Reward?
    /// 排位赛：打完给的金币（不加减奖杯）
    private(set) var ranked = false
    @Published private(set) var rankedCoins: Int?
    /// 这局给的赛季经验、做完的任务、排位分
    @Published private(set) var seasonGain: ArenaSeasonGain?
    /// 这局自己用了几次小道具、放了几次大招（任务要算）
    private var gadgetsUsed = 0
    private var supersUsed = 0
    /// 联机时房主走了
    @Published private(set) var disconnected = false
    /// 进球、一局打完、开新一局时屏幕中间写一行大字（两秒后消失）
    @Published private(set) var announcement: Announcement?

    struct Announcement: Equatable {
        let text: String
        /// 好事（自己这边进球、赢了这局）用蓝底，不然红底
        let good: Bool
        let at: Double
    }

    /// 开场对阵画面放多久（这段时间不开打）
    static let introLength = 2.8
    /// 正在放开场对阵画面
    @Published private(set) var showingIntro = true
    private var introLeft = ArenaController.introLength

    /// 右上角的击倒提示：谁打倒了谁（最多 3 条，4 秒后消失）
    struct KillNote: Identifiable, Equatable {
        let id: Int
        let killer: Int?
        let victim: Int
        let at: Double
    }
    @Published private(set) var feed: [KillNote] = []
    private var notes = 0
    /// 走的摇杆（长度 0–1）
    var move = V2.zero
    /// 正在拖的攻击 / 大招摇杆（画瞄准线用；长度 0–1，占射程的比例）
    var aiming: V2?
    var superAiming: V2?
    private var queuedAttack: V2?
    private var queuedSpecial: V2?
    private var queuedGadget = false
    private var queuedEmote: Int?
    private var sceneEvents: [ArenaGame.Event] = []
    private var recorded = false

    // 房主
    private var seatOfMember: [String: Int] = [:]
    private var remoteMoves: [Int: V2] = [:]
    private var remoteAcks: [Int: Int] = [:]
    private var remoteAttacks: [Int: V2] = [:]
    private var remoteSpecials: [Int: V2] = [:]
    private var remoteGadgets: Set<Int> = []
    private var remoteEmotes: [Int: Int] = [:]
    private var netEvents: [ArenaGame.Event] = []
    private var ticks = 0

    // 其他人
    private var sequence = 0
    private var history: [(sequence: Int, move: V2, dt: Double)] = []
    private var lastSnapshot = -1.0

    /// 自己和电脑打（冒险的一关也是）
    convenience init(setup: Setup, seed: UInt64 = UInt64.random(in: 0..<UInt64.max)) {
        let mine = ArenaGame.Entrant(name: setup.name.isEmpty ? "我" : setup.name, brawler: setup.brawler, isBot: false, team: 0,
                                     level: setup.level, lineup: setup.lineup, loadout: setup.loadout.allowed(setup.brawler, level: setup.level))
        let built: ArenaGame
        if setup.benchmark {
            built = ArenaBenchmark.game()
        } else if let story = setup.story {
            built = ArenaGame(mode: story.mode, entrants: story.entrants(me: mine), seed: seed, map: ArenaMap.named(story.map),
                             bossLevel: story.bossLevel)
        } else {
            var random = SeededRandom(seed: seed)
            var others = Brawler.allCases.filter { $0 != setup.brawler }
            random.shuffle(&others)
            let maps = ArenaMap.pool(for: setup.mode)
            let map = maps[random.below(maps.count)]
            let teams = setup.mode.seatTeams
            var entrants = [mine]
            entrants[0].team = teams[0]
            for k in 1..<teams.count {
                let brawler = others[(k - 1) % others.count]
                let boss = setup.mode == .boss && teams[k] == 1
                let level = setup.botLevel ?? setup.level
                entrants.append(ArenaGame.Entrant(name: boss ? "骷髅王" : "电脑\(brawler.name)", brawler: brawler, isBot: true, team: teams[k],
                                                  level: level, loadout: ArenaLoadout.basic(brawler, level: level)))
            }
            built = ArenaGame(mode: setup.mode, entrants: entrants, seed: seed, map: map)
        }
        self.init(role: .solo, game: built, me: 0, room: nil, seed: setup.benchmark ? ArenaBenchmark.seed : seed)
        benchmark = setup.benchmark
        sampleMap = setup.sampleMap
        if benchmark {
            introLeft = 0
            showingIntro = false
        }
        if setup.benchmarkStill && benchmark {
            for frame in 1...900 {
                sceneEvents.removeAll(keepingCapacity: true)
                tick()
                if frame >= 240 && self.mine.alive && !game.projectiles.isEmpty { break }
            }
            benchmarkStill = true
            refreshHUD()
        }
        story = setup.story
        ranked = setup.ranked && setup.story == nil
        switch setup.demo {
        case .versus?:
            introLeft = .infinity
        case .result?:
            // 截图用：打完了，自己这队赢、自己是全场最佳
            introLeft = 0
            showingIntro = false
            game.adjust(0) { $0.kills = 6; $0.damageDealt = 14_200 }
            game.adjust(1) { $0.kills = 3; $0.damageDealt = 8_900 }
            game.result = .team(game.fighters[0].team)
            refreshHUD()
        case nil:
            break
        }
    }

    /// 联机：房主开的这一局
    convenience init(start: ArenaStart, room: GameRoom) {
        let me = start.seats.firstIndex { $0.member == room.me.id } ?? 0
        self.init(role: room.isHost ? .host : .client,
                  game: ArenaGame(mode: start.mode, entrants: start.entrants, seed: start.seed, map: start.map.flatMap(ArenaMap.named)),
                  me: me, room: room, seed: start.seed)
        for (index, seat) in start.seats.enumerated() {
            if let member = seat.member { seatOfMember[member] = index }
        }
        room.onDirect = { [weak self] data, from in self?.receivedDirect(data, from: from) }
    }

    private init(role: Role, game: ArenaGame, me: Int, room: GameRoom?, seed: UInt64) {
        self.role = role
        self.game = game
        self.me = me
        self.room = room
        bots = role == .client ? [] : game.fighters.filter(\.isBot).map { ArenaBot(id: $0.id, seed: seed) }
        refreshHUD()
    }

    var mine: Fighter { game.fighters[me] }

    /// 画面每帧调：按真实过去的时间往前算
    func advance(_ elapsed: Double) {
        guard !benchmarkStill else { return }
        // 开场对阵画面放着的时候不开打（联机时房主也一样等，别人收到的是开场那一帧）
        if introLeft > 0 {
            introLeft -= max(elapsed, 0)
            if introLeft <= 0 { showingIntro = false }
            return
        }
        switch role {
        case .solo, .host:
            if game.result == nil {
                accumulator = min(accumulator + max(elapsed, 0), 0.25)
                while accumulator >= Self.step && game.result == nil {
                    accumulator -= Self.step
                    tick()
                }
            }
        case .client:
            clientFrame(min(max(elapsed, 0), 0.1))
        }
        hudTimer += elapsed
        if hudTimer >= 0.1 || game.result != nil {
            hudTimer = 0
            refreshHUD()
        }
    }

    private func tick() {
        if benchmark && cycleSteps >= ArenaBenchmark.cycleSteps {
            game = ArenaBenchmark.game()
            bots = game.fighters.map { ArenaBot(id: $0.id, seed: ArenaBenchmark.seed) }
            cycleSteps = 0
            benchmarkCycles += 1
            sceneEvents.append(.reset)
        }
        var inputs: [Int: ArenaInput] = [me: ArenaInput(move: move, attack: queuedAttack, special: queuedSpecial, gadget: queuedGadget,
                                                        emote: queuedEmote)]
        queuedAttack = nil
        queuedSpecial = nil
        queuedGadget = false
        queuedEmote = nil
        if role == .host {
            for (seat, move) in remoteMoves { inputs[seat] = ArenaInput(move: move) }
            for (seat, aim) in remoteAttacks { inputs[seat, default: ArenaInput()].attack = aim }
            for (seat, aim) in remoteSpecials { inputs[seat, default: ArenaInput()].special = aim }
            for seat in remoteGadgets { inputs[seat, default: ArenaInput()].gadget = true }
            for (seat, emote) in remoteEmotes { inputs[seat, default: ArenaInput()].emote = emote }
            remoteAttacks = [:]
            remoteSpecials = [:]
            remoteGadgets = []
            remoteEmotes = [:]
        }
        ArenaDiagnostics.shared.measure(.ai) {
            for k in bots.indices {
                inputs[bots[k].id] = bots[k].input(in: game, dt: Self.step)
            }
        }
        ArenaDiagnostics.shared.measure(.simulation) {
            game.profileCPU = ArenaDiagnostics.shared.enabled
            game.step(Self.step, inputs: inputs)
        }
        if game.profileCPU {
            ArenaDiagnostics.shared.record(.fighterPhysics, seconds: game.fighterStepSeconds)
            ArenaDiagnostics.shared.record(.projectilePhysics, seconds: game.projectileStepSeconds)
        }
        if benchmark { cycleSteps += 1; benchmarkSteps += 1 }
        let events = game.events
        game.events.removeAll()
        sceneEvents += events
        announce(events)
        if role == .host {
            netEvents += events
            ticks += 1
            if ticks % 3 == 0 || game.result != nil { broadcast() }
        }
    }

    /// Touch-up may never arrive after backgrounding or dismissing the view.
    func cancelLocalInput() {
        move = .zero
        aiming = nil
        superAiming = nil
        queuedAttack = nil
        queuedSpecial = nil
        queuedGadget = false
        queuedEmote = nil
        accumulator = 0
    }

    /// 这一帧发生的事（画特效用），拿走就清掉
    func takeEvents() -> [ArenaGame.Event] {
        defer { sceneEvents.removeAll() }
        return sceneEvents
    }

    /// 松开攻击摇杆：拖得很短算点了一下，自动瞄射程里最近的敌人
    func fire(_ drag: V2) {
        let aim = target(for: drag, range: mine.brawler.attackRange)
        if role == .client { sendFire(attack: aim, special: nil) } else { queuedAttack = aim }
    }

    func fireSpecial(_ drag: V2) {
        guard mine.superCharge >= 1 else { return }
        let aim = target(for: drag, range: mine.brawler.superRange)
        if role == .client { sendFire(attack: nil, special: aim) } else { queuedSpecial = aim }
    }

    /// 头顶冒个表情
    func emote(_ id: Int) {
        if role == .client { sendFire(attack: nil, special: nil, emote: id) } else { queuedEmote = id }
    }

    /// 点小道具按钮（往摇杆的方向用：翻滚、闪烁）
    func fireGadget() {
        let fighter = mine
        guard fighter.alive, fighter.gadget != nil, fighter.gadgetUses > 0, fighter.gadgetCooldown <= 0 else { return }
        if role == .client { sendFire(attack: nil, special: nil, gadget: true) } else { queuedGadget = true }
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

    // MARK: - 联机

    /// 房主：把现在的样子发给大家（打完了那一包一定要到）
    private func broadcast() {
        var packet = Data([Packet.snapshot])
        packet.append(game.snapshot(events: netEvents, acks: remoteAcks).encoded())
        netEvents.removeAll()
        room?.sendDirect(packet, delivery: game.result == nil ? .unreliable : .reliable)
    }

    /// 其他人：发摇杆、自己先走、子弹和别人先接着飞
    private func clientFrame(_ dt: Double) {
        guard game.result == nil else { return }
        sequence += 1
        history.append((sequence, move, dt))
        if history.count > 180 { history.removeFirst(history.count - 180) }
        // 摇杆每秒发 30 次就够（Game Center 不喜欢发得太勤）
        if sequence % 2 == 0 {
            var writer = ByteWriter()
            writer.u8(Int(Packet.input))
            writer.u32(sequence)
            writer.i16(Int((move.x * 1000).rounded()))
            writer.i16(Int((move.y * 1000).rounded()))
            room?.sendDirect(writer.data, delivery: .unreliable)
        }
        let fighter = game.fighters[me]
        if fighter.alive, !fighter.busy, move.length > 0.05 {
            game.fighters[me].pos = ArenaGame.walk(from: fighter.pos, by: move.clamped(to: 1) * (game.moveSpeed(fighter) * dt), on: game.map)
            if aiming == nil && superAiming == nil { game.fighters[me].facing = move.normalized }
        }
        game.extrapolate(dt, except: me)
    }

    /// 开火、放大招、用小道具、冒表情（小道具、表情是后加的，老版本的房主读不到就不管）
    private func sendFire(attack: V2?, special: V2?, gadget: Bool = false, emote: Int? = nil) {
        var writer = ByteWriter()
        writer.u8(Int(Packet.fire))
        for aim in [attack, special] {
            writer.u8(aim == nil ? 0 : 1)
            writer.v2(aim ?? .zero)
        }
        writer.u8(gadget ? 1 : 0)
        writer.u8(emote ?? 255)
        room?.sendDirect(writer.data, delivery: .reliable)
    }

    private enum Packet {
        static let input: UInt8 = 1
        static let snapshot: UInt8 = 2
        static let fire: UInt8 = 3
    }

    private func receivedDirect(_ data: Data, from: String) {
        guard let kind = data.first else { return }
        let body = data.dropFirst()
        switch (role, kind) {
        case (.host, Packet.input):
            var reader = ByteReader(Data(body))
            guard let seat = seatOfMember[from], let sequence = reader.u32(), let x = reader.i16(), let y = reader.i16() else { return }
            guard sequence > remoteAcks[seat] ?? 0 else { return }
            remoteAcks[seat] = sequence
            remoteMoves[seat] = V2(Double(x) / 1000, Double(y) / 1000)
        case (.host, Packet.fire):
            var reader = ByteReader(Data(body))
            guard let seat = seatOfMember[from], let hasAttack = reader.u8(), let attack = reader.v2(),
                  let hasSpecial = reader.u8(), let special = reader.v2() else { return }
            if hasAttack == 1 { remoteAttacks[seat] = attack }
            if hasSpecial == 1 { remoteSpecials[seat] = special }
            if reader.u8() == 1 { remoteGadgets.insert(seat) }
            if let emote = reader.u8(), emote < 255 { remoteEmotes[seat] = emote }
        case (.client, Packet.snapshot):
            guard let snapshot = ArenaSnapshot(data: Data(body)), snapshot.time >= lastSnapshot else { return }
            lastSnapshot = snapshot.time
            apply(snapshot)
        default:
            break
        }
    }

    /// 收到房主的一帧：照着摆；自己从房主算到的位置，把房主还没收到的那几步补上
    private func apply(_ snapshot: ArenaSnapshot) {
        game.apply(snapshot)
        announce(game.events)
        sceneEvents += game.events
        game.events.removeAll()
        guard snapshot.fighters.indices.contains(me) else { return }
        let ack = snapshot.fighters[me].ack
        history.removeAll { $0.sequence <= ack }
        let fighter = game.fighters[me]
        guard fighter.alive, !fighter.busy else { return }
        var position = fighter.pos
        let speed = game.moveSpeed(fighter)
        for step in history where step.move.length > 0.05 {
            position = ArenaGame.walk(from: position, by: step.move.clamped(to: 1) * (speed * step.dt), on: game.map)
        }
        game.fighters[me].pos = position
    }

    /// 房间里有人走了：房主让电脑接着替他打；其他人发现房主走了就停
    func membersChanged() {
        guard let room else { return }
        let present = Set(room.members.map(\.id))
        switch role {
        case .host:
            for (member, seat) in seatOfMember where !present.contains(member) {
                seatOfMember[member] = nil
                remoteMoves[seat] = nil
                bots.append(ArenaBot(id: seat, seed: UInt64(seat) &+ 99))
            }
        case .client:
            if let host = room.hostID, !present.contains(host) || room.phase != .ready { disconnected = true }
            if room.phase != .ready { disconnected = true }
        case .solo:
            break
        }
    }

    // MARK: - 上面那排

    private func refreshHUD() {
        let start = ArenaDiagnostics.shared.enabled ? ProcessInfo.processInfo.systemUptime : 0
        defer { if start > 0 { ArenaDiagnostics.shared.record(.hud, seconds: ProcessInfo.processInfo.systemUptime - start) } }
        var hud = HUD()
        hud.timeLeft = Int(game.timeLeft.rounded(.up))
        let mineTeam = min(mine.team, 1), theirs = 1 - min(mine.team, 1)
        switch game.mode {
        case .teamFight:
            hud.blue = game.teamKills[mineTeam]
            hud.red = game.teamKills[theirs]
        case .stars:
            hud.blue = game.teamStars(mineTeam)
            hud.red = game.teamStars(theirs)
            hud.countdownTeam = game.countdown?.team
            hud.countdownLeft = Int((game.countdown?.left ?? 0).rounded(.up))
        case .zone:
            hud.blue = Int(game.zoneProgress[mineTeam])
            hud.red = Int(game.zoneProgress[theirs])
        case .ball, .bounty, .knockout, .duel:
            hud.blue = game.score[mineTeam]
            hud.red = game.score[theirs]
            hud.round = game.round
        case .heist:
            hud.blue = Int((game.chestShare(mineTeam) * 100).rounded(.up))
            hud.red = Int((game.chestShare(theirs) * 100).rounded(.up))
        case .boss:
            if let boss = game.fighters.first(where: \.isBoss) {
                hud.bossHealth = max(boss.health, 0)
                hud.bossMaxHealth = max(boss.maxHealth, 1)
            }
        case .showdown:
            hud.alive = game.aliveCount
        case .duo:
            hud.teamsLeft = Set(game.fighters.filter(\.alive).map(\.team)).count
        }
        hud.poisonShrinking = game.poisonShrinking
        let fighter = mine
        hud.health = fighter.health
        hud.maxHealth = fighter.maxHealth
        hud.superCharge = fighter.superCharge
        hud.gadget = fighter.gadget
        hud.gadgetUses = fighter.gadgetUses
        hud.gadgetCooldown = Int(fighter.gadgetCooldown.rounded(.up))
        hud.hyperUnlocked = fighter.hyperUnlocked
        hud.hyperCharge = (fighter.hyperCharge * 50).rounded() / 50
        hud.hyperTime = (fighter.hyperTime * 10).rounded() / 10
        hud.dead = !fighter.alive
        hud.respawnIn = Int(fighter.respawnIn.rounded(.up))
        // 大乱斗被打倒、双人大乱斗自己这队出局就算结束（不用看别人打完）
        if game.mode == .showdown, !fighter.alive, game.result == nil {
            hud.result = .survivor(-1)
        } else if game.mode == .duo, fighter.place != nil, game.result == nil {
            hud.result = .team(-1)
        } else {
            hud.result = game.result
        }
        if let current = announcement, game.time - current.at > 2.2 || game.time < current.at { announcement = nil }
        if feed.contains(where: { game.time - $0.at > 4 || game.time < $0.at }) {
            feed.removeAll { game.time - $0.at > 4 || game.time < $0.at }
        }
        if hud.result != nil, !recorded, !benchmark {
            recorded = true
            let store = ArenaProgressStore.shared
            if let story {
                // 冒险不加减奖杯：按星给金币
                storyReward = store.finish(story, stars: story.stars(in: game, me: me))
            } else if ranked {
                // 排位不加减奖杯：金币照给，排位分在赛季里算
                rankedCoins = store.recordRanked(outcome(hud.result))
            } else {
                ArenaRecords.shared.add(mode: game.mode, won: won(hud.result))
                reward = store.record(outcome(hud.result), brawler: mine.brawler)
            }
            let stats = ArenaMatchStats(mode: game.mode, brawler: mine.brawler, won: won(hud.result), kills: mine.kills,
                                        damage: mine.damageDealt, gadgets: gadgetsUsed, supers: supersUsed, ranked: ranked)
            seasonGain = store.recordSeason(stats, draw: hud.result == .draw)
        }
        if hud != self.hud { self.hud = hud }
    }

    /// 被打倒了还会回来（画面上显示「几秒后复活」）
    var willRespawn: Bool { game.canRespawn(me) }

    private func announce(_ events: [ArenaGame.Event]) {
        for event in events {
            switch event {
            case .goal(let team):
                announcement = Announcement(text: team == mine.team ? "进球了！" : "对方进球", good: team == mine.team, at: game.time)
            case .round(let winner):
                let text = winner == nil ? "这一局平了" : (winner == mine.team ? "这一局赢了！" : "这一局输了")
                announcement = Announcement(text: text, good: winner == mine.team, at: game.time)
            case .reset where game.mode == .knockout:
                announcement = Announcement(text: "第 \(game.round) 局", good: true, at: game.time)
            case .gadget(let fighter) where fighter == me:
                gadgetsUsed += 1
            case .special(let fighter) where fighter == me:
                supersUsed += 1
            case .knockout(let target, let by):
                notes += 1
                feed.append(KillNote(id: notes, killer: by, victim: target, at: game.time))
                if feed.count > 3 { feed.removeFirst(feed.count - 3) }
            default:
                break
            }
        }
    }

    /// 这局对自己来说算什么（大乱斗看名次）
    private func outcome(_ result: ArenaGame.Result?) -> ArenaProgress.Outcome {
        if game.mode == .showdown {
            return .place(mine.place ?? (won(result) ? 1 : game.fighters.count))
        }
        if game.mode == .duo {
            // 三队里第几：按六人大乱斗的第 1、3、5 名给
            let place = mine.place ?? (won(result) ? 1 : 3)
            return .place([1, 3, 5][min(max(place, 1), 3) - 1])
        }
        switch result {
        case .draw?: return .draw
        default: return won(result) ? .win : .loss
        }
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

    /// 全场最佳：赢的那一队里（没分出输赢就全场）打倒的人多、伤害高的那个
    var starPlayer: Int? {
        let pool: [Fighter]
        switch hud.result {
        case .team(let team)? where team >= 0: pool = game.fighters.filter { $0.team == team && !$0.isBoss }
        case .survivor(let id)? where game.fighters.indices.contains(id): pool = [game.fighters[id]]
        default: pool = game.fighters.filter { !$0.isBoss }
        }
        return pool.max { ($0.kills, $0.damageDealt) < ($1.kills, $1.damageDealt) }?.id
    }
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

/// 乱斗的成长（奖杯、金币、角色等级），存在这台手机上
@MainActor
final class ArenaProgressStore: ObservableObject {
    static let shared = ArenaProgressStore()
    private static let key = "arena.progress"

    @Published private(set) var progress: ArenaProgress

    private init() {
        progress = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(ArenaProgress.self, from: $0) }
            ?? ArenaProgress()
    }

    func record(_ outcome: ArenaProgress.Outcome, brawler: Brawler) -> ArenaProgress.Reward {
        let reward = progress.record(outcome, brawler: brawler)
        save()
        return reward
    }

    @discardableResult
    func upgrade(_ brawler: Brawler) -> Bool {
        guard progress.upgrade(brawler) else { return false }
        save()
        return true
    }

    func choose(_ gadget: Gadget, for brawler: Brawler) {
        progress.choose(gadget, for: brawler)
        save()
    }

    /// 冒险最近打完的一关（冒险地图上看要不要放打完的对话）
    struct StoryResult: Equatable {
        let level: String
        let stars: Int
        /// 什么时候打完的（同一关打了几次也分得开）
        let at: Date
    }
    @Published private(set) var lastStory: StoryResult?

    /// 打完冒险的一关
    func finish(_ level: ArenaStory.Level, stars: Int) -> ArenaStory.Reward {
        let reward = progress.finish(level, stars: stars)
        lastStory = StoryResult(level: level.id, stars: stars, at: Date())
        save()
        return reward
    }

    // MARK: 赛季、任务、排位、商店

    /// 打完一局：赛季经验、任务，排位赛加减排位分
    func recordSeason(_ stats: ArenaMatchStats, draw: Bool) -> ArenaSeasonGain {
        let gain = progress.recordSeason(stats, draw: draw, now: Date(), calendar: .current)
        save()
        return gain
    }

    /// 排位赛给的金币
    func recordRanked(_ outcome: ArenaProgress.Outcome) -> Int {
        let coins = progress.recordRanked(outcome)
        save()
        return coins
    }

    /// 换天、换周、换季（打开大厅时看一下）
    func refreshSeason() {
        let before = progress
        progress.refreshSeason(Date(), calendar: .current)
        if progress != before { save() }
    }

    @discardableResult
    func claim(_ tier: Int) -> ArenaSeason.Prize? {
        let prize = progress.claim(tier)
        if prize != nil { save() }
        return prize
    }

    @discardableResult
    func buy(_ skin: ArenaSkin, price: Int) -> Bool {
        guard progress.buy(skin, for: price) else { return false }
        save()
        return true
    }

    @discardableResult
    func buy(_ skin: ArenaSkin) -> Bool {
        buy(skin, price: skin.price)
    }

    @discardableResult
    func buy(_ emote: ArenaEmote) -> Bool {
        guard progress.buy(emote) else { return false }
        save()
        return true
    }

    func wear(_ index: Int, for brawler: Brawler) {
        progress.wear(index, for: brawler)
        save()
    }

    func choose(_ starPower: StarPower, for brawler: Brawler) {
        progress.choose(starPower, for: brawler)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(progress) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

// MARK: - 联机房间里：选角色、选玩法、开局

/// 乱斗的联机房间：大家各选各的角色，房主选玩法、点开始；人按进房间的先后分到两队（大乱斗各自为战），不够 3v3 / 6 个人电脑补
@MainActor
final class ArenaLobby: ObservableObject {
    enum Message: Codable {
        case pick(Brawler)
        case mode(ArenaGame.Mode)
        case start(ArenaStart)
        /// 选的角色几级（老版本收到不认识，当 1 级）
        case level(Int)
        /// 带的小道具、星徽、超级充能（老版本收到不认识：按等级带第一个）
        case loadout(ArenaLoadout)
    }

    struct Playing: Identifiable {
        let id = UUID()
        let controller: ArenaController
    }

    let room: GameRoom
    @Published private(set) var mode: ArenaGame.Mode
    @Published private(set) var picks: [String: Brawler] = [:]
    @Published private(set) var levels: [String: Int] = [:]
    @Published private(set) var loadouts: [String: ArenaLoadout] = [:]
    @Published var playing: Playing?
    @Published private(set) var myPick: Brawler
    private var round = 0

    init(room: GameRoom, mode: ArenaGame.Mode, brawler: Brawler) {
        self.room = room
        self.mode = mode
        myPick = brawler
        room.onPayload = { [weak self] data, from in self?.received(data, from: from) }
        room.onMembersChanged = { [weak self] in self?.membersChanged() }
    }

    private func membersChanged() {
        objectWillChange.send()
        picks[room.me.id] = myPick
        send(.pick(myPick))
        send(.level(myLevel))
        send(.loadout(myLoadout))
        if room.isHost { send(.mode(mode)) }
        playing?.controller.membersChanged()
    }

    /// 谁选了什么（自己的以自己选的为准）
    func pick(of member: String) -> Brawler? {
        member == room.me.id ? myPick : picks[member]
    }

    func choose(_ brawler: Brawler) {
        myPick = brawler
        picks[room.me.id] = brawler
        send(.pick(brawler))
        send(.level(myLevel))
        send(.loadout(myLoadout))
    }

    /// 改了带的小道具、星徽：告诉大家
    func loadoutChanged() {
        send(.loadout(myLoadout))
    }

    /// 自己带的
    var myLoadout: ArenaLoadout { ArenaProgressStore.shared.progress.loadout(for: myPick) }

    /// 谁带的什么（没收到的按等级带第一个）
    func loadout(of member: String) -> ArenaLoadout {
        if member == room.me.id { return myLoadout }
        let brawler = pick(of: member) ?? .knight
        return loadouts[member] ?? ArenaLoadout.basic(brawler, level: level(of: member))
    }

    /// 自己选的角色几级
    var myLevel: Int { ArenaProgressStore.shared.progress.level(myPick) }

    /// 谁的角色几级
    func level(of member: String) -> Int {
        member == room.me.id ? myLevel : (levels[member] ?? 1)
    }

    func choose(_ newMode: ArenaGame.Mode) {
        guard room.isHost else { return }
        mode = newMode
        send(.mode(newMode))
    }

    /// 房主开局
    func start() {
        guard room.isHost, fits else { return }
        round += 1
        let maps = ArenaMap.pool(for: mode)
        let start = ArenaStart(round: round, mode: mode, seed: UInt64.random(in: 0..<UInt64.max), seats: seats(),
                               map: maps.randomElement()?.id)
        send(.start(start))
        playing = Playing(controller: ArenaController(start: start, room: room))
    }

    /// 这个玩法最多几个真人（一对一 2 个，讨伐骷髅王 3 个勇者，其余 6 个）
    static func humanSeats(_ mode: ArenaGame.Mode) -> Int {
        switch mode {
        case .duel: return 2
        case .boss: return 3
        default: return 6
        }
    }

    /// 人数合不合这个玩法
    var fits: Bool { room.members.count >= 2 && room.members.count <= Self.humanSeats(mode) }

    /// 座位：人按进房间的先后轮流分到各队（讨伐骷髅王的人都是勇者）；不够的电脑补（同一队不重复角色）
    private func seats() -> [ArenaStart.Seat] {
        let teams = mode.seatTeams
        // 真人坐哪几个座位：两队对打一边一个轮流坐，双人大乱斗先每队一个
        let order: [Int]
        switch mode {
        case .showdown, .duel, .boss: order = Array(teams.indices)
        case .duo: order = [0, 2, 4, 1, 3, 5]
        default: order = [0, 3, 1, 4, 2, 5]
        }
        let people = Array(room.members.prefix(min(Self.humanSeats(mode), order.count)))
        // 电脑补位的按大家的平均等级
        let botLevel = people.isEmpty ? 1 : Int((Double(people.map { level(of: $0.id) }.reduce(0, +)) / Double(people.count)).rounded())
        var seated: [Int: ArenaStart.Seat] = [:]
        for (k, member) in people.enumerated() {
            let seat = order[k]
            let pick = pick(of: member.id) ?? .knight
            seated[seat] = ArenaStart.Seat(member: member.id, name: member.name, brawler: pick, team: teams[seat], level: level(of: member.id),
                                           lineup: mode == .duel ? [pick] : nil, loadout: loadout(of: member.id))
        }
        var seats: [ArenaStart.Seat] = []
        for (seat, team) in teams.enumerated() {
            if let person = seated[seat] {
                seats.append(person)
                continue
            }
            let used = Set(seated.values.filter { $0.team == team }.map(\.brawler) + seats.filter { $0.team == team }.map(\.brawler))
            let brawler = Brawler.allCases.first { !used.contains($0) } ?? .knight
            let boss = mode == .boss && team == 1
            seats.append(ArenaStart.Seat(member: nil, name: boss ? "骷髅王" : "电脑\(brawler.name)", brawler: brawler, team: team, level: botLevel,
                                         loadout: ArenaLoadout.basic(brawler, level: botLevel)))
        }
        return seats
    }

    private func send(_ message: Message) {
        if let data = try? JSONEncoder().encode(message) { room.send(data) }
    }

    private func received(_ data: Data, from: String) {
        guard let message = try? JSONDecoder().decode(Message.self, from: data) else { return }
        switch message {
        case .pick(let brawler):
            picks[from] = brawler
        case .level(let level):
            levels[from] = min(max(level, 1), ArenaProgress.maxLevel)
        case .loadout(let loadout):
            loadouts[from] = loadout
        case .mode(let newMode):
            if from == room.hostID { mode = newMode }
        case .start(let start):
            guard from == room.hostID else { return }
            round = start.round
            playing = Playing(controller: ArenaController(start: start, room: room))
        }
    }
}
