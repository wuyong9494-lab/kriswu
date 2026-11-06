import SwiftUI

// MARK: - 战绩（只存在这台手机上）

/// 星了个星的战绩：每档最快通关、玩了几局赢了几局、每天今日挑战的最好成绩
struct TileRecords: Codable, Equatable {
    struct Result: Codable, Equatable {
        var won: Bool
        var seconds: Double
        var cleared: Int
        var total: Int

        /// 比另一次好：通关的比没通关的好；都通关比快；都没通关比消得多
        func better(than other: Result) -> Bool {
            if won != other.won { return won }
            if won { return seconds < other.seconds }
            return cleared > other.cleared
        }
    }

    /// 键是难度（TileGame.Level 的 rawValue）
    var best: [Int: Double] = [:]
    var played: [Int: Int] = [:]
    var wins: [Int: Int] = [:]
    /// 键是日期（2026-10-27）
    var daily: [String: Result] = [:]
}

@MainActor
final class TileRecordStore: ObservableObject {
    static let shared = TileRecordStore()
    private static let key = "tileGame.records"

    @Published private(set) var records: TileRecords
    @Published private(set) var constellationRecords: TileRecords
    @Published private(set) var journey: TileJourney.Progress

    private init() {
        constellationRecords = UserDefaults.standard.data(forKey: "tileGame.records.v2")
            .flatMap { try? JSONDecoder().decode(TileRecords.self, from: $0) } ?? TileRecords()
        journey = UserDefaults.standard.data(forKey: "tileGame.journey.v2")
            .flatMap { try? JSONDecoder().decode(TileJourney.Progress.self, from: $0) } ?? .init()
        records = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(TileRecords.self, from: $0) } ?? TileRecords()
    }

    func add(_ result: TileRecords.Result, level: TileGame.Level, daily: DayKey?, ruleSet: TileGame.RuleSet = .classic) {
        var output = ruleSet == .classic ? records : constellationRecords
        let key = level.rawValue
        output.played[key, default: 0] += 1
        if result.won {
            output.wins[key, default: 0] += 1
            if output.best[key].map({ result.seconds < $0 }) ?? true { output.best[key] = result.seconds }
        }
        if let daily {
            let day = daily.description
            if output.daily[day].map({ result.better(than: $0) }) ?? true { output.daily[day] = result }
            if output.daily.count > 60 {
                let keep = Set(output.daily.keys.sorted().suffix(60))
                output.daily = output.daily.filter { keep.contains($0.key) }
            }
        }
        if ruleSet == .classic { records = output } else { constellationRecords = output }
        if let data = try? JSONEncoder().encode(output) {
            UserDefaults.standard.set(data, forKey: ruleSet == .classic ? Self.key : "tileGame.records.v2")
        }
    }

    func finish(stage: Int, game: TileGame) {
        guard journey.record(stage: stage, game: game), let data = try? JSONEncoder().encode(journey) else { return }
        UserDefaults.standard.set(data, forKey: "tileGame.journey.v2")
    }

    static func time(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// 开一局：哪一档、哪个种子、哪种玩法
struct TilePlay: Identifiable, Equatable {
    enum Mode: Equatable {
        case solo, daily(DayKey), challenge, race, journey(Int)
    }

    let id = UUID()
    let level: TileGame.Level
    let seed: UInt64
    let mode: Mode
    var ruleSet: TileGame.RuleSet = .constellation
}

// MARK: - 对战

/// 星了个星对战：房主开局，大家玩同一局，每走一步把自己的进度发给大家（房间负责送到每个人）
@MainActor
final class TileRaceGame: ObservableObject {
    struct Round: Identifiable, Equatable {
        let id: Int
        let level: TileGame.Level
        let seed: UInt64
    }

    /// 面对面最多几个人
    static let most = 8

    let room: GameRoom
    /// 每个人这一局的进度（按房间里的编号）
    @Published private(set) var progress: [String: TileRace.Player] = [:]
    /// 最近开的一局（打完了也留着，房间里看排名）
    @Published private(set) var round: Round?
    /// 正在显示的那一局（关掉回房间时变成 nil，这一局的进度照样收发）
    @Published var presented: Round?

    init(room: GameRoom) {
        self.room = room
        room.onPayload = { [weak self] data, from in self?.received(data, from: from) }
        room.onMembersChanged = { [weak self] in self?.objectWillChange.send() }
    }

    /// 房间里每个人这一局的进度（还没发来的算刚开始）
    var players: [TileRace.Player] {
        room.members.map { member in
            guard var player = progress[member.id] else { return TileRace.Player(id: member.id, name: member.name) }
            player.name = member.name
            return player
        }
    }

    var me: TileRace.Player {
        progress[room.me.id] ?? TileRace.Player(id: room.me.id, name: room.me.name)
    }

    /// 这一局大家都打完了
    var roundFinished: Bool { TileRace.finished(players) }
    var roundInProgress: Bool { round != nil && !roundFinished }

    /// 房主开一局：大家同时开始玩同一局
    func begin(level: TileGame.Level) {
        guard room.isHost else { return }
        let next = Round(id: (round?.id ?? 0) + 1, level: level, seed: UInt64.random(in: 0..<TileGame.seedLimit))
        start(next)
        send(.start(round: next.id, level: next.level, seed: next.seed))
    }

    /// 自己这一局走了一步
    func report(_ game: TileGame, seconds: Double) {
        var mine = me
        mine.cleared = game.cleared + game.clearing.count
        mine.total = game.total
        mine.status = game.status
        mine.seconds = seconds
        share(mine)
    }

    /// 中途退出：这一局算输（别人那边才知道这局打完了）
    func forfeit(_ player: TileRace.Player) {
        share(player)
    }

    private func share(_ player: TileRace.Player) {
        guard let round else { return }
        progress[player.id] = player
        send(.progress(round: round.id, player: player))
        if room.isHost, roundFinished { room.accepting = true }
    }

    private func start(_ next: Round) {
        progress = [:]
        round = next
        presented = next
        if room.isHost { room.accepting = false }
    }

    private func send(_ message: TileRace.Message) {
        if let data = try? JSONEncoder().encode(message) { room.send(data) }
    }

    private func received(_ data: Data, from: String) {
        guard let message = try? JSONDecoder().decode(TileRace.Message.self, from: data) else { return }
        switch message {
        case .start(let id, let level, let seed):
            guard from == room.hostID else { return }
            start(Round(id: id, level: level, seed: seed))
        case .progress(let id, let player):
            guard id == round?.id, player.id == from else { return }
            progress[player.id] = player
            if room.isHost, roundFinished { room.accepting = true }
        }
    }
}

struct TileRaceLobbyView: View {
    @ObservedObject private var room: GameRoom
    @StateObject private var race: TileRaceGame
    @Environment(\.dismiss) private var dismiss
    @State private var level = TileGame.Level.normal

    init(room: GameRoom) {
        self.room = room
        _race = StateObject(wrappedValue: TileRaceGame(room: room))
    }

    var body: some View {
        NavigationStack {
            List {
                GameRoomLobby(room: room) {
                    if room.isHost {
                        Section {
                            Picker("难度", selection: $level) {
                                ForEach(TileGame.Level.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            Button {
                                race.begin(level: level)
                            } label: {
                                Label("开始（\(room.members.count) 个人）", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        } footer: {
                            if race.roundInProgress { Text("上一局还有人没打完，现在开始的话他们直接进新的一局。") }
                        }
                    } else {
                        Section { Text("等房主开始，开始了自动进入。").foregroundStyle(.secondary) }
                    }
                    if race.round != nil {
                        Section("上一局") { TileRaceStandings(race: race, compact: false) }
                    }
                }
            }
            .appList()
            .navigationTitle(room.code == nil ? "面对面比星了个星" : "远程比星了个星")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("离开") {
                        room.leave()
                        dismiss()
                    }
                }
            }
        }
        .onAppear { room.start() }
        .fullScreenCover(item: $race.presented) { round in
            TileBoardView(play: TilePlay(level: round.level, seed: round.seed, mode: .race, ruleSet: .classic), race: race)
        }
    }
}

/// 对战时每个人的进度：上面一排小卡片（compact），或者一张排名表
struct TileRaceStandings: View {
    @ObservedObject var race: TileRaceGame
    var compact = true

    var body: some View {
        let ranked = TileRace.ranking(race.players)
        if compact {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.xs) {
                    ForEach(ranked) { player in chip(player) }
                }
                .padding(.horizontal, DS.Space.m)
            }
        } else {
            ForEach(Array(ranked.enumerated()), id: \.element.id) { index, player in
                HStack {
                    Text("\(index + 1)").font(DS.Font.headline.monospacedDigit()).frame(width: 24)
                    Text(player.id == race.room.me.id ? "\(player.name)（我）" : player.name)
                    Spacer()
                    Text(summary(player)).font(DS.Font.caption).foregroundStyle(player.status == .won ? DS.Palette.success : .secondary)
                }
            }
        }
    }

    private func chip(_ player: TileRace.Player) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(player.name).font(DS.Font.caption.weight(.semibold)).lineLimit(1)
                switch player.status {
                case .won: Image(systemName: "crown.fill").foregroundStyle(DS.Palette.warning)
                case .lost: Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                case .playing: EmptyView()
                }
            }
            ProgressView(value: Double(player.cleared), total: Double(max(player.total, 1)))
                .tint(player.id == race.room.me.id ? DS.Palette.accent : DS.Palette.success)
                .frame(width: 76)
        }
        .padding(DS.Space.xs)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
    }

    private func summary(_ player: TileRace.Player) -> String {
        switch player.status {
        case .won: return "\(TileRecordStore.time(player.seconds)) 通关"
        case .lost: return "消了 \(player.cleared)/\(player.total)，卡住了"
        case .playing: return player.total > 0 ? "还在玩，消了 \(player.cleared)/\(player.total)" : "还没开始"
        }
    }
}

// MARK: - 一局

struct TileBoardView: View {
    let play: TilePlay
    let race: TileRaceGame?

    @Environment(\.dismiss) private var dismiss
    @State private var game: TileGame
    @State private var seed: UInt64
    @State private var started = Date()
    @State private var ended: Date?
    @State private var countdown: Int
    @State private var moves = 0
    @State private var recorded = false
    @State private var showingResult = false
    @State private var confirmingQuit = false
    @State private var stageID: Int?
    @State private var settleTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var space

    init(play: TilePlay, race: TileRaceGame?) {
        self.play = play
        self.race = race
        _game = State(initialValue: TileGame(level: play.level, seed: play.seed, ruleSet: play.ruleSet))
        _stageID = State(initialValue: { if case .journey(let id) = play.mode { return id }; return nil }())
        _seed = State(initialValue: play.seed)
        _countdown = State(initialValue: race == nil ? 0 : 3)
    }

    private var title: String {
        switch play.mode {
        case .daily: return "今日挑战 · \(TileTheme.title(game.level))"
        case .challenge: return "挑战码 \(game.code)"
        case .race: return "对战 · \(play.level.title)"
        case .solo: return TileTheme.title(game.level)
        case .journey: return "第 \(stageID ?? 1) 关 · \(TileJourney.stage(stageID ?? 1)?.name ?? "星域航程")"
        }
    }

    private var seconds: Double { (ended ?? Date()).timeIntervalSince(started) }

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, 560)
            VStack(spacing: 10) {
                topBar
                if let race { TileRaceStandings(race: race) }
                if proxy.size.width > 650 && proxy.size.width > proxy.size.height {
                    HStack(spacing: 20) {
                        GeometryReader { area in board(in: area.size).frame(width: area.size.width, height: area.size.height) }
                        VStack(spacing: 14) {
                            scoreBar
                            Spacer(minLength: 0)
                            parkedRow(width: 280)
                            tray(width: 280)
                            tools
                        }
                        .frame(width: 280)
                    }
                    .padding(.horizontal, 20)
                } else {
                    scoreBar.padding(.horizontal, 20)
                    GeometryReader { area in board(in: area.size).frame(width: area.size.width, height: area.size.height) }
                        .padding(.horizontal, 10)
                    parkedRow(width: width)
                    tray(width: width)
                    tools
                }
            }
            .frame(maxWidth: proxy.size.width > 650 && proxy.size.width > proxy.size.height ? .infinity : 560)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
            .blur(radius: countdown > 0 ? 6 : 0)
            .overlay { countdownOverlay }
            .overlay { if showingResult { resultOverlay } }
        }
        .background(TileStarfield().ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .task { await runCountdown() }
        .onDisappear { settleTask?.cancel() }
        .confirmationDialog("退出这一局？", isPresented: $confirmingQuit, titleVisibility: .visible) {
            Button(race == nil ? "退出" : "退出（这局算输）", role: .destructive) { quit() }
            Button("接着玩", role: .cancel) {}
        }
    }

    private var scoreBar: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("星光积分").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                    Text("\(game.score)").font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                }
                Spacer()
                if game.combo > 1 {
                    Text("\(game.combo) 连消").font(.system(.headline, design: .rounded)).foregroundStyle(TileTheme.gold)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("4 步内再消 · 连消加分").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.09))
                    Capsule().fill(TileTheme.mint)
                        .frame(width: proxy.size.width * CGFloat(game.cleared + game.clearing.count) / CGFloat(max(game.total, 1)))
                }
            }
            .frame(height: 4)
            .accessibilityLabel("已消除 \(game.cleared + game.clearing.count) 张，共 \(game.total) 张")
        }
    }

    // MARK: 上面一条

    private var topBar: some View {
        HStack {
            Button {
                if moves > 0 && game.status == .playing { confirmingQuit = true } else { quit() }
            } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("退出牌局").accessibilityIdentifier("tiles.close")
            Spacer()
            VStack(spacing: 2) {
                Text(title).font(.system(size: 16, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
                Text("还剩 \(game.total - game.cleared - game.clearing.count) 张").font(DS.Font.caption).foregroundStyle(.secondary)
            }
            Spacer()
            TimelineView(.periodic(from: started, by: 1)) { context in
                Text(TileRecordStore.time(max(0, (ended ?? context.date).timeIntervalSince(started))))
                    .font(DS.Font.callout.monospacedDigit())
                    .frame(minWidth: 52)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.top, DS.Space.xs)
    }

    // MARK: 牌堆

    private func board(in size: CGSize) -> some View {
        let unit = max(1, min((size.width - 12) / CGFloat(TileGame.width), (size.height - 12) / CGFloat(max(game.height, 1))))
        let side = unit * CGFloat(TileGame.size)
        let free = game.freeIDs
        let tiles = game.board.sorted { ($0.z, $0.y, $0.x) < ($1.z, $1.y, $1.x) }
        return ZStack(alignment: .topLeading) {
            ForEach(tiles) { tile in
                let open = free.contains(tile.id)
                Button { pick(tile.id) } label: {
                    TileFace(kind: tile.kind, side: side - 1, covered: !open)
                }
                    .buttonStyle(.plain).disabled(!open || countdown > 0 || showingResult)
                    .accessibilityIdentifier("tiles.card.\(tile.id)")
                    .matchedGeometryEffect(id: tile.id, in: space)
                    .position(x: (CGFloat(tile.x) + 2) * unit, y: (CGFloat(tile.y) + 2) * unit)
            }
        }
        .frame(width: unit * CGFloat(TileGame.width), height: unit * CGFloat(game.height))
    }

    // MARK: 移出的、槽

    private func slot(_ width: CGFloat) -> CGFloat {
        min(54, (width - DS.Space.m * 2 - DS.Space.s * 2 - 6 * 6) / 7)
    }

    @ViewBuilder private func parkedRow(width: CGFloat) -> some View {
        if !game.parked.isEmpty {
            HStack(spacing: 6) {
                ForEach(game.parked) { tile in
                    Button { pick(tile.id) } label: {
                        TileFace(kind: tile.kind, side: max(36, slot(width)))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                        .buttonStyle(.plain)
                        .disabled(countdown > 0 || showingResult)
                        .matchedGeometryEffect(id: tile.id, in: space)
                }
                Text("移出的牌：点一张放回槽里").font(DS.Font.caption).foregroundStyle(.secondary)
            }
            .transition(.opacity)
        }
    }

    private func tray(width: CGFloat) -> some View {
        let side = slot(width)
        return VStack(spacing: 8) {
            HStack {
                Text(game.waiting >= 5 ? "还剩 \(7 - game.waiting) 格 · 留意下一张" : "收集槽 · 三张相同即可消除")
                Spacer()
                Text("\(game.waiting)/7").monospacedDigit()
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(game.waiting >= 5 ? TileTheme.gold : .white.opacity(0.55))
            ZStack(alignment: .leading) {
            HStack(spacing: 6) {
                ForEach(0..<TileGame.capacity, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: side * 0.2, style: .continuous)
                        .fill(Color.black.opacity(0.18))
                        .frame(width: side, height: side)
                }
            }
            HStack(spacing: 6) {
                ForEach(game.tray) { tile in
                    TileFace(kind: tile.kind, side: side, glowing: game.clearing.contains(tile.id))
                        .matchedGeometryEffect(id: tile.id, in: space)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
            }
        }
        .padding(12)
        .frame(width: side * 7 + 6 * 6 + 24)
        .background(TileTheme.panel, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .strokeBorder(game.waiting >= TileGame.capacity - 1 ? TileTheme.gold : .white.opacity(0.12), lineWidth: 1.5))
        .accessibilityIdentifier("tiles.tray")
    }

    // MARK: 道具

    private var tools: some View {
        HStack(spacing: DS.Space.s) {
            tool("撤回", "arrow.uturn.backward", left: game.undos, enabled: game.canUndo) {
                change { $0.undo() }
            }
            tool("移出", "tray.and.arrow.up", left: game.moveOuts, enabled: game.moveOuts > 0 && !game.tray.isEmpty) {
                change { $0.moveOut() }
            }
            tool("洗牌", "shuffle", left: game.shuffles, enabled: game.shuffles > 0 && game.status == .playing) {
                change { $0.shuffle() }
            }
        }
        .padding(.horizontal, DS.Space.m)
    }

    private func tool(_ name: String, _ icon: String, left: Int, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.title3)
                Text(left > 0 ? "\(name) · 1" : "\(name) · 0").font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || countdown > 0)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityIdentifier("tiles.tool.\(icon)")
    }

    // MARK: 倒数、结果

    @ViewBuilder private var countdownOverlay: some View {
        if countdown > 0 {
            Text("\(countdown)")
                .font(DS.Font.giant)
                .foregroundStyle(.white)
                .shadow(radius: 12)
                .transition(.scale.combined(with: .opacity))
                .id(countdown)
        }
    }

    private var resultOverlay: some View {
        let won = game.status == .won
        let canGoOn = !won && (game.canUndo || game.moveOuts > 0)
        return ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: DS.Space.m) {
                Image(systemName: won ? "sparkles" : "square.stack.3d.up.fill")
                    .font(.system(size: 34)).foregroundStyle(won ? TileTheme.gold : TileTheme.mint)
                Text(won ? "星域点亮！" : "暂时卡住了").font(.system(size: 28, weight: .bold, design: .rounded))
                if won { TileStars(count: game.stars).scaleEffect(2).frame(height: 32) }
                Text(won ? "\(game.score) 分 · 最高 \(game.bestCombo) 连消" : "消了 \(game.cleared)/\(game.total) 张")
                    .font(DS.Font.title)
                    .foregroundStyle(.secondary)
                if let race {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        TileRaceStandings(race: race, compact: false)
                    }
                    .padding(DS.Space.s)
                    .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m))
                }
                if canGoOn {
                    Button("用道具接着玩") { withAnimation { showingResult = false } }
                        .buttonStyle(.borderedProminent)
                }
                if won, let stageID, let next = TileJourney.stage(stageID + 1) {
                    Button("下一关 · \(next.name)") { nextStage(next) }
                        .buttonStyle(TilePrimaryButton()).accessibilityIdentifier("tiles.next")
                }
                if race == nil {
                    Button {
                        share()
                    } label: {
                        Label("发到微信，约人比比", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    HStack {
                        Button("重玩这一局") { restart(seed: seed) }
                        if play.mode == .solo {
                            Button("换一局") { restart(seed: UInt64.random(in: 0..<TileGame.seedLimit)) }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                Button(race == nil ? "退出" : "回房间") { quit() }
            }
            .padding(DS.Space.l)
            .frame(maxWidth: 360)
            .background(TileTheme.panel, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(DS.Space.l)
        }
        .transition(.opacity)
    }

    // MARK: - 动作

    private func runCountdown() async {
        guard countdown > 0 else { return }
        while countdown > 0 {
            do { try await Task.sleep(nanoseconds: 800_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.snappy) { countdown -= 1 }
        }
        started = Date()
        race?.report(game, seconds: 0)
    }

    private func pick(_ id: Int) {
        guard countdown == 0 else { return }
        var next = game
        guard next.pick(id) else { return }
        settleTask?.cancel()
        Haptics.tap()
        moves += 1
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) { game = next }
        if !game.clearing.isEmpty {
            settleTask = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 260_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                Haptics.success()
                withAnimation(.easeIn(duration: 0.16)) { game.settle() }
                afterMove()
            }
        }
        afterMove()
    }

    private func change(_ action: (inout TileGame) -> Bool) {
        var next = game
        guard action(&next) else { return }
        settleTask?.cancel()
        Haptics.select()
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { game = next }
        if showingResult && game.status == .playing { withAnimation { showingResult = false } }
        afterMove()
    }

    /// 走完一步：赢了、输了停表、记成绩、弹结果；对战时告诉大家
    private func afterMove() {
        switch game.status {
        case .won:
            if ended == nil { ended = Date() }
            record()
            Haptics.success()
            withAnimation(DS.Motion.spring.delay(0.3)) { showingResult = true }
        case .lost:
            if ended == nil { ended = Date() }
            Haptics.warning()
            withAnimation(DS.Motion.spring.delay(0.2)) { showingResult = true }
        case .playing:
            ended = nil
        }
        race?.report(game, seconds: seconds)
    }

    /// 记一次成绩（一局只记一次：赢了马上记，没赢的退出、重来时记）
    private func record() {
        guard !recorded, moves > 0 else { return }
        recorded = true
        let result = TileRecords.Result(won: game.status == .won, seconds: seconds, cleared: game.cleared + game.clearing.count, total: game.total)
        var daily: DayKey?
        if case .daily(let day) = play.mode { daily = day }
        TileRecordStore.shared.add(result, level: game.level, daily: daily, ruleSet: game.ruleSet)
        if let stageID { TileRecordStore.shared.finish(stage: stageID, game: game) }
    }

    private func restart(seed: UInt64) {
        record()
        settleTask?.cancel()
        self.seed = seed
        withAnimation { showingResult = false }
        game = TileGame(level: game.level, seed: seed, ruleSet: game.ruleSet)
        started = Date()
        ended = nil
        moves = 0
        recorded = false
    }

    private func nextStage(_ stage: TileJourney.Stage) {
        record()
        settleTask?.cancel()
        stageID = stage.id
        seed = stage.seed
        game = stage.game
        showingResult = false
        started = Date()
        ended = nil
        moves = 0
        recorded = false
    }

    private func quit() {
        settleTask?.cancel()
        record()
        if let race, game.status == .playing {
            // 中途退出：这局算输，别人那边才知道这局打完了
            var mine = race.me
            mine.cleared = game.cleared
            mine.total = game.total
            mine.status = .lost
            mine.seconds = seconds
            race.forfeit(mine)
        }
        dismiss()
    }

    private func share() {
        let what: String
        switch play.mode {
        case .daily: what = "今日挑战（\(play.level.title)）"
        case .journey: what = "第 \(stageID ?? 1) 关"
        default: what = "\(TileTheme.title(game.level))的一局"
        }
        let result = game.status == .won ? "用 \(TileRecordStore.time(seconds)) 通关了" : "消了 \(game.cleared)/\(game.total) 张就卡住了"
        let text = "我在「星了个星」\(what)\(result)！挑战码 \(game.code)：打开「值班提醒」› 全部功能 › 小游戏 › 星了个星，把这段话粘贴进「挑战码」，玩同一局比比谁快。"
        ActivityShare.present([text], excluding: ActivityShare.chatOnly) { _ in }
    }
}
