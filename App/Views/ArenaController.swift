import Foundation

/// 联机时开一局要的：玩法、种子、每个座位是谁（房主定好发给大家，大家照着摆出一模一样的一局）
struct ArenaStart: Codable, Equatable {
    struct Seat: Codable, Equatable {
        /// 房间里的谁；nil 是电脑
        var member: String?
        var name: String
        var brawler: Brawler
        var team: Int
    }

    var round: Int
    var mode: ArenaGame.Mode
    var seed: UInt64
    var seats: [Seat]

    var entrants: [ArenaGame.Entrant] {
        seats.map { ArenaGame.Entrant(name: $0.name, brawler: $0.brawler, isBot: $0.member == nil, team: $0.team) }
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

    let role: Role
    let me: Int
    private(set) var game: ArenaGame
    private weak var room: GameRoom?
    private var bots: [ArenaBot]
    private var accumulator = 0.0
    private var hudTimer = 0.0
    @Published private(set) var hud = HUD()
    /// 联机时房主走了
    @Published private(set) var disconnected = false
    /// 走的摇杆（长度 0–1）
    var move = V2.zero
    /// 正在拖的攻击 / 大招摇杆（画瞄准线用；长度 0–1，占射程的比例）
    var aiming: V2?
    var superAiming: V2?
    private var queuedAttack: V2?
    private var queuedSpecial: V2?
    private var sceneEvents: [ArenaGame.Event] = []
    private var recorded = false

    // 房主
    private var seatOfMember: [String: Int] = [:]
    private var remoteMoves: [Int: V2] = [:]
    private var remoteAcks: [Int: Int] = [:]
    private var remoteAttacks: [Int: V2] = [:]
    private var remoteSpecials: [Int: V2] = [:]
    private var netEvents: [ArenaGame.Event] = []
    private var ticks = 0

    // 其他人
    private var sequence = 0
    private var history: [(sequence: Int, move: V2, dt: Double)] = []
    private var lastSnapshot = -1.0

    /// 自己和电脑打
    convenience init(setup: Setup, seed: UInt64 = UInt64.random(in: 0..<UInt64.max)) {
        var random = SeededRandom(seed: seed)
        var others = Brawler.allCases.filter { $0 != setup.brawler }
        random.shuffle(&others)
        var entrants = [ArenaGame.Entrant(name: setup.name.isEmpty ? "我" : setup.name, brawler: setup.brawler, isBot: false, team: 0)]
        for k in 0..<5 {
            let brawler = others[k % others.count]
            let team = setup.mode.isTeams ? (k < 2 ? 0 : 1) : k + 1
            entrants.append(ArenaGame.Entrant(name: "电脑\(brawler.name)", brawler: brawler, isBot: true, team: team))
        }
        self.init(role: .solo, game: ArenaGame(mode: setup.mode, entrants: entrants, seed: seed), me: 0, room: nil, seed: seed)
    }

    /// 联机：房主开的这一局
    convenience init(start: ArenaStart, room: GameRoom) {
        let me = start.seats.firstIndex { $0.member == room.me.id } ?? 0
        self.init(role: room.isHost ? .host : .client, game: ArenaGame(mode: start.mode, entrants: start.entrants, seed: start.seed),
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
        var inputs: [Int: ArenaInput] = [me: ArenaInput(move: move, attack: queuedAttack, special: queuedSpecial)]
        queuedAttack = nil
        queuedSpecial = nil
        if role == .host {
            for (seat, move) in remoteMoves { inputs[seat] = ArenaInput(move: move) }
            for (seat, aim) in remoteAttacks { inputs[seat, default: ArenaInput()].attack = aim }
            for (seat, aim) in remoteSpecials { inputs[seat, default: ArenaInput()].special = aim }
            remoteAttacks = [:]
            remoteSpecials = [:]
        }
        for k in bots.indices {
            inputs[bots[k].id] = bots[k].input(in: game, dt: Self.step)
        }
        game.step(Self.step, inputs: inputs)
        let events = game.events
        game.events.removeAll()
        sceneEvents += events
        if role == .host {
            netEvents += events
            ticks += 1
            if ticks % 3 == 0 || game.result != nil { broadcast() }
        }
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
            game.fighters[me].pos = ArenaGame.walk(from: fighter.pos, by: move.clamped(to: 1) * (fighter.brawler.speed * dt), on: game.map)
            if aiming == nil && superAiming == nil { game.fighters[me].facing = move.normalized }
        }
        game.extrapolate(dt, except: me)
    }

    private func sendFire(attack: V2?, special: V2?) {
        var writer = ByteWriter()
        writer.u8(Int(Packet.fire))
        for aim in [attack, special] {
            writer.u8(aim == nil ? 0 : 1)
            writer.v2(aim ?? .zero)
        }
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
        sceneEvents += game.events
        game.events.removeAll()
        guard snapshot.fighters.indices.contains(me) else { return }
        let ack = snapshot.fighters[me].ack
        history.removeAll { $0.sequence <= ack }
        let fighter = game.fighters[me]
        guard fighter.alive, !fighter.busy else { return }
        var position = fighter.pos
        for step in history where step.move.length > 0.05 {
            position = ArenaGame.walk(from: position, by: step.move.clamped(to: 1) * (fighter.brawler.speed * step.dt), on: game.map)
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
        var hud = HUD()
        hud.timeLeft = Int(game.timeLeft.rounded(.up))
        switch game.mode {
        case .teamFight:
            hud.blue = game.teamKills[mine.team == 0 ? 0 : 1]
            hud.red = game.teamKills[mine.team == 0 ? 1 : 0]
        case .stars:
            hud.blue = game.teamStars(mine.team == 0 ? 0 : 1)
            hud.red = game.teamStars(mine.team == 0 ? 1 : 0)
            hud.countdownTeam = game.countdown?.team
            hud.countdownLeft = Int((game.countdown?.left ?? 0).rounded(.up))
        case .zone:
            hud.blue = Int(game.zoneProgress[mine.team == 0 ? 0 : 1])
            hud.red = Int(game.zoneProgress[mine.team == 0 ? 1 : 0])
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
        // 大乱斗被打倒就算结束（不用看别人打完）
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

// MARK: - 联机房间里：选角色、选玩法、开局

/// 乱斗的联机房间：大家各选各的角色，房主选玩法、点开始；人按进房间的先后分到两队（大乱斗各自为战），不够 3v3 / 6 个人电脑补
@MainActor
final class ArenaLobby: ObservableObject {
    enum Message: Codable {
        case pick(Brawler)
        case mode(ArenaGame.Mode)
        case start(ArenaStart)
    }

    struct Playing: Identifiable {
        let id = UUID()
        let controller: ArenaController
    }

    let room: GameRoom
    @Published private(set) var mode: ArenaGame.Mode
    @Published private(set) var picks: [String: Brawler] = [:]
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
    }

    func choose(_ newMode: ArenaGame.Mode) {
        guard room.isHost else { return }
        mode = newMode
        send(.mode(newMode))
    }

    /// 房主开局
    func start() {
        guard room.isHost, room.members.count >= 2 else { return }
        round += 1
        let start = ArenaStart(round: round, mode: mode, seed: UInt64.random(in: 0..<UInt64.max), seats: seats())
        send(.start(start))
        playing = Playing(controller: ArenaController(start: start, room: room))
    }

    /// 座位：人按进房间的先后轮流分到两队；不够的电脑补（同一队不重复角色）
    private func seats() -> [ArenaStart.Seat] {
        let people = Array(room.members.prefix(6))
        var seats: [ArenaStart.Seat] = []
        for (k, member) in people.enumerated() {
            seats.append(ArenaStart.Seat(member: member.id, name: member.name, brawler: pick(of: member.id) ?? .panda,
                                         team: mode.isTeams ? k % 2 : k))
        }
        if mode.isTeams {
            for team in 0...1 {
                while seats.filter({ $0.team == team }).count < 3 {
                    let used = Set(seats.filter { $0.team == team }.map(\.brawler))
                    let brawler = Brawler.allCases.first { !used.contains($0) } ?? .panda
                    seats.append(ArenaStart.Seat(member: nil, name: "电脑\(brawler.name)", brawler: brawler, team: team))
                }
            }
        } else {
            while seats.count < 6 {
                let brawler = Brawler.allCases[seats.count % Brawler.allCases.count]
                seats.append(ArenaStart.Seat(member: nil, name: "电脑\(brawler.name)", brawler: brawler, team: seats.count))
            }
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
        case .mode(let newMode):
            if from == room.hostID { mode = newMode }
        case .start(let start):
            guard from == room.hostID else { return }
            round = start.round
            playing = Playing(controller: ArenaController(start: start, room: room))
        }
    }
}
