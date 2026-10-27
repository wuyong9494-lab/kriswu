import SwiftUI

// MARK: - 战绩（只存在这台手机上）

/// 叠叠消的战绩：每档最快通关、玩了几局赢了几局、每天今日挑战的最好成绩
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
    private static let nicknameKey = "tileGame.nickname"

    @Published private(set) var records: TileRecords

    private init() {
        records = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(TileRecords.self, from: $0) } ?? TileRecords()
    }

    /// 对战时别人看到的名字
    var nickname: String {
        get { UserDefaults.standard.string(forKey: Self.nicknameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.nicknameKey) }
    }

    func add(_ result: TileRecords.Result, level: TileGame.Level, daily: DayKey?) {
        let key = level.rawValue
        records.played[key, default: 0] += 1
        if result.won {
            records.wins[key, default: 0] += 1
            if records.best[key].map({ result.seconds < $0 }) ?? true { records.best[key] = result.seconds }
        }
        if let daily {
            let day = daily.description
            if records.daily[day].map({ result.better(than: $0) }) ?? true { records.daily[day] = result }
            // 今日挑战只留最近两个月
            if records.daily.count > 60 {
                let keep = Set(records.daily.keys.sorted().suffix(60))
                records.daily = records.daily.filter { keep.contains($0.key) }
            }
        }
        if let data = try? JSONEncoder().encode(records) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    static func time(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// 开一局：哪一档、哪个种子、哪种玩法
struct TilePlay: Identifiable, Equatable {
    enum Mode: Equatable {
        case solo, daily(DayKey), challenge, race
    }

    let id = UUID()
    let level: TileGame.Level
    let seed: UInt64
    let mode: Mode
}

// MARK: - 首页

/// 小游戏「叠叠消」：三档难度自己玩、今日挑战（同一天大家同一局）、挑战码（玩别人发来的那一局）、面对面对战
struct TileGameHomeView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var records = TileRecordStore.shared
    @State private var play: TilePlay?
    @State private var code = ""
    @State private var nickname = ""
    @State private var lobby: Lobby?

    /// 对战房间（开房间或加入）
    struct Lobby: Identifiable {
        let id = UUID()
        let session: TileRaceSession
    }

    var body: some View {
        List {
            Section {
                Text("点没被压住的牌放进下面的槽，三张一样的自动消掉；槽里放满 7 张还没凑齐就输了。撤回、移出、洗牌三个道具每局各能用一次。每一局都消得完。")
                    .font(DS.Font.body)
                    .foregroundStyle(.secondary)
            }
            Section("自己玩") {
                ForEach(TileGame.Level.allCases, id: \.self) { level in
                    Button { play = TilePlay(level: level, seed: UInt64.random(in: 0..<TileGame.seedLimit), mode: .solo) } label: {
                        levelRow(level)
                    }
                }
            }
            dailySection
            codeSection
            raceSection
        }
        .appList()
        .navigationTitle("叠叠消")
        .onAppear {
            if nickname.isEmpty { nickname = records.nickname.isEmpty ? (store.settings.aliases.first ?? "") : records.nickname }
        }
        .fullScreenCover(item: $play) { play in
            TileBoardView(play: play, race: nil)
        }
        .fullScreenCover(item: $lobby) { lobby in
            TileRaceLobbyView(session: lobby.session)
        }
    }

    private func levelRow(_ level: TileGame.Level) -> some View {
        let key = level.rawValue
        let detail: String
        switch level {
        case .easy: detail = "4 种牌，三十来张，熟悉一下"
        case .normal: detail = "8 种牌，一百来张，底下两摞"
        case .hard: detail = "9 种牌，一百多张，七层（今日挑战就是这一档）"
        }
        return HStack(spacing: DS.Space.s) {
            IconBadge(icon: ["leaf", "flame", "bolt"][key - 1], color: DS.Palette.vivid[[6, 4, 3][key - 1]], size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(level.title).font(DS.Font.headline).foregroundStyle(.primary)
                Text(detail).font(DS.Font.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let best = records.records.best[key] {
                    Text("最快 \(TileRecordStore.time(best))").font(DS.Font.caption.weight(.semibold)).foregroundStyle(.primary)
                }
                if let played = records.records.played[key] {
                    Text("赢了 \(records.records.wins[key] ?? 0)/\(played) 局").font(DS.Font.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var dailySection: some View {
        let today = DayKey.today
        let result = records.records.daily[today.description]
        return Section {
            Button {
                play = TilePlay(level: .hard, seed: TileGame.dailySeed(today), mode: .daily(today))
            } label: {
                HStack(spacing: DS.Space.s) {
                    IconBadge(icon: "calendar", color: DS.Palette.vivid[1], size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今日挑战").font(DS.Font.headline).foregroundStyle(.primary)
                        Text("今天大家玩的都是这一局（困难），玩完发到群里比比").font(DS.Font.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let result {
                        Text(result.won ? "\(TileRecordStore.time(result.seconds)) 通关" : "消了 \(result.cleared)/\(result.total)")
                            .font(DS.Font.caption.weight(.semibold))
                            .foregroundStyle(result.won ? DS.Palette.success : .secondary)
                    }
                }
            }
        }
    }

    private var codeSection: some View {
        Section {
            TextField("挑战码，比如 K7Q2MX", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            PasteButton(payloadType: String.self) { strings in
                let text = strings.first ?? ""
                Task { @MainActor in code = text }
            }
            Button("开始这一局") {
                if let decoded = TileGame.decode(code) {
                    play = TilePlay(level: decoded.level, seed: decoded.seed, mode: .challenge)
                } else {
                    ToastCenter.shared.show("没认出挑战码：是 6 个字母和数字，比如 K7Q2MX", style: .warning)
                }
            }
            .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("挑战码")
        } footer: {
            Text("别人玩完发来的挑战码输进来（整段话粘贴进来也行），玩同一局，比比谁快。")
        }
    }

    private var raceSection: some View {
        Section {
            TextField("别人看到的名字", text: $nickname)
                .onChange(of: nickname) { records.nickname = $0 }
            Button {
                lobby = Lobby(session: TileRaceSession(role: .host, name: nickname))
            } label: {
                Label("开房间", systemImage: "person.3")
            }
            Button {
                lobby = Lobby(session: TileRaceSession(role: .guest, name: nickname))
            } label: {
                Label("加入同事的房间", systemImage: "person.badge.plus")
            }
        } header: {
            Text("面对面对战")
        } footer: {
            Text("身边的同事（最多 8 个人）都打开叠叠消：一个人开房间，别人点「加入」，房主点开始，大家同时玩同一局，每台手机上都看得到别人消了几张，先消完的赢。手机离得近、打开 Wi-Fi 和蓝牙就行，不用联网；对方手机上也要装着值班提醒。")
        }
    }
}

// MARK: - 对战房间

struct TileRaceLobbyView: View {
    @ObservedObject var session: TileRaceSession
    @Environment(\.dismiss) private var dismiss
    @State private var level = TileGame.Level.normal

    var body: some View {
        NavigationStack {
            List {
                if let notice = session.notice {
                    Section { Label(notice, systemImage: "exclamationmark.triangle").foregroundStyle(DS.Palette.warning) }
                }
                switch session.role {
                case .host: hostSections
                case .guest: guestSections
                }
                if session.round != nil && session.players.count > 1 {
                    Section("上一局") { TileRaceStandings(session: session, compact: false) }
                }
            }
            .appList()
            .navigationTitle(session.role == .host ? "我的房间" : "加入房间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("离开") {
                        session.stop()
                        dismiss()
                    }
                }
            }
        }
        .onAppear { session.start() }
        .fullScreenCover(item: $session.presented) { round in
            TileBoardView(play: TilePlay(level: round.level, seed: round.seed, mode: .race), race: session)
        }
    }

    @ViewBuilder private var hostSections: some View {
        Section {
            ForEach(session.players) { player in
                Label(player.id == session.me.id ? "\(player.name)（我，房主）" : player.name, systemImage: "person.fill")
            }
        } header: {
            Text("房间里 \(session.players.count) 个人")
        } footer: {
            Text("让同事打开「叠叠消」点「加入同事的房间」，找到「\(session.me.name)」点一下。")
        }
        Section {
            Picker("难度", selection: $level) {
                ForEach(TileGame.Level.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Button {
                session.begin(level: level)
            } label: {
                Label(session.players.count < 2 ? "等人进来" : "开始（\(session.players.count) 个人）", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.players.count < 2)
        } footer: {
            if session.roundInProgress { Text("上一局还有人没打完，现在开始的话他们直接进新的一局。") }
        }
    }

    @ViewBuilder private var guestSections: some View {
        if let host = session.joined {
            Section {
                ForEach(session.players) { player in
                    Label(player.id == session.me.id ? "\(player.name)（我）" : player.name, systemImage: "person.fill")
                }
            } header: {
                Text("在「\(host)」的房间里")
            } footer: {
                Text("等房主开始，开始了自动进入。")
            }
        } else {
            Section {
                if session.rooms.isEmpty {
                    HStack(spacing: DS.Space.s) {
                        ProgressView()
                        Text(session.joining.map { "正在进「\($0)」的房间…" } ?? "正在找附近的房间…").foregroundStyle(.secondary)
                    }
                }
                ForEach(session.rooms) { room in
                    Button {
                        session.join(room)
                    } label: {
                        HStack {
                            Label("\(room.name) 的房间", systemImage: "person.3")
                            Spacer()
                            if session.joining == room.name { ProgressView() }
                        }
                    }
                    .disabled(session.joining != nil)
                }
            } footer: {
                Text("找不到的话：两台手机离近一点，打开 Wi-Fi 和蓝牙；第一次用时系统会问能不能使用本地网络，要点允许（在系统设置 › 隐私与安全性 › 本地网络 里也能打开）。")
            }
        }
    }
}

/// 对战时每个人的进度：上面一排小卡片（compact），或者一张排名表
struct TileRaceStandings: View {
    @ObservedObject var session: TileRaceSession
    var compact = true

    var body: some View {
        let ranked = TileRace.ranking(session.players)
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
                    Text(player.id == session.me.id ? "\(player.name)（我）" : player.name)
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
                .tint(player.id == session.me.id ? DS.Palette.accent : DS.Palette.success)
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
    let race: TileRaceSession?

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
    @Namespace private var space

    init(play: TilePlay, race: TileRaceSession?) {
        self.play = play
        self.race = race
        _game = State(initialValue: TileGame(level: play.level, seed: play.seed))
        _seed = State(initialValue: play.seed)
        _countdown = State(initialValue: race == nil ? 0 : 3)
    }

    private var title: String {
        switch play.mode {
        case .daily: return "今日挑战 · \(play.level.title)"
        case .challenge: return "挑战码 \(game.code)"
        case .race: return "对战 · \(play.level.title)"
        case .solo: return play.level.title
        }
    }

    private var seconds: Double { (ended ?? Date()).timeIntervalSince(started) }

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, 560)
            VStack(spacing: DS.Space.s) {
                topBar
                if let race { TileRaceStandings(session: race) }
                GeometryReader { area in
                    board(in: area.size)
                        .frame(width: area.size.width, height: area.size.height)
                }
                .padding(.horizontal, DS.Space.s)
                parkedRow(width: width)
                tray(width: width)
                tools
            }
            .frame(width: width)
            .frame(maxWidth: .infinity)
            .padding(.bottom, DS.Space.xs)
            .blur(radius: countdown > 0 ? 6 : 0)
            .overlay { countdownOverlay }
            .overlay { if showingResult { resultOverlay } }
        }
        .background(boardBackground.ignoresSafeArea())
        .task { await runCountdown() }
        .confirmationDialog("退出这一局？", isPresented: $confirmingQuit, titleVisibility: .visible) {
            Button(race == nil ? "退出" : "退出（这局算输）", role: .destructive) { quit() }
            Button("接着玩", role: .cancel) {}
        }
    }

    private var boardBackground: some View {
        LinearGradient(colors: [Color(light: 0xDDF2C4, dark: 0x1E2A19), Color(light: 0xBFE09E, dark: 0x141D10)],
                       startPoint: .top, endPoint: .bottom)
    }

    // MARK: 上面一条

    private var topBar: some View {
        HStack {
            Button {
                if moves > 0 && game.status == .playing { confirmingQuit = true } else { quit() }
            } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            VStack(spacing: 2) {
                Text(title).font(DS.Font.headline)
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
        let unit = min(size.width / CGFloat(TileGame.width), size.height / CGFloat(max(game.height, 1)))
        let side = unit * CGFloat(TileGame.size)
        let free = game.freeIDs
        let tiles = game.board.sorted { ($0.z, $0.y, $0.x) < ($1.z, $1.y, $1.x) }
        return ZStack(alignment: .topLeading) {
            ForEach(tiles) { tile in
                let open = free.contains(tile.id)
                TileFace(kind: tile.kind, side: side, covered: !open)
                    .contentShape(Rectangle())
                    .onTapGesture { pick(tile.id) }
                    .allowsHitTesting(open)
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
                    TileFace(kind: tile.kind, side: slot(width))
                        .onTapGesture { pick(tile.id) }
                        .matchedGeometryEffect(id: tile.id, in: space)
                }
                Text("移出的牌：点一张放回槽里").font(DS.Font.caption).foregroundStyle(.secondary)
            }
            .transition(.opacity)
        }
    }

    private func tray(width: CGFloat) -> some View {
        let side = slot(width)
        return ZStack(alignment: .leading) {
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
        .padding(DS.Space.s)
        .background(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous).fill(Color(light: 0x8A5A35, dark: 0x5C3B22)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
            .strokeBorder(game.waiting >= TileGame.capacity - 1 ? DS.Palette.danger : .clear, lineWidth: 2))
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
                Text(left > 0 ? name : "\(name)（用过了）").font(DS.Font.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.xs)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled || countdown > 0)
        .opacity(enabled ? 1 : 0.45)
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
                Text(won ? "通关了！" : "槽满了").font(DS.Font.display)
                Text(won ? "用时 \(TileRecordStore.time(seconds))" : "消了 \(game.cleared)/\(game.total) 张")
                    .font(DS.Font.title)
                    .foregroundStyle(.secondary)
                if let race {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        TileRaceStandings(session: race, compact: false)
                    }
                    .padding(DS.Space.s)
                    .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m))
                }
                if canGoOn {
                    Button("用道具接着玩") { withAnimation { showingResult = false } }
                        .buttonStyle(.borderedProminent)
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .padding(DS.Space.l)
        }
        .transition(.opacity)
    }

    // MARK: - 动作

    private func runCountdown() async {
        guard countdown > 0 else { return }
        while countdown > 0 {
            try? await Task.sleep(nanoseconds: 800_000_000)
            withAnimation(DS.Motion.snappy) { countdown -= 1 }
        }
        started = Date()
        race?.report(game, seconds: 0)
    }

    private func pick(_ id: Int) {
        guard countdown == 0 else { return }
        var next = game
        guard next.pick(id) else { return }
        Haptics.tap()
        moves += 1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { game = next }
        if !game.clearing.isEmpty {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 260_000_000)
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
        Haptics.select()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { game = next }
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
        let result = TileRecords.Result(won: game.status == .won, seconds: seconds, cleared: game.cleared, total: game.total)
        var daily: DayKey?
        if case .daily(let day) = play.mode { daily = day }
        TileRecordStore.shared.add(result, level: play.level, daily: daily)
    }

    private func restart(seed: UInt64) {
        record()
        self.seed = seed
        withAnimation { showingResult = false }
        game = TileGame(level: play.level, seed: seed)
        started = Date()
        ended = nil
        moves = 0
        recorded = false
    }

    private func quit() {
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
        default: what = "\(play.level.title)的一局"
        }
        let result = game.status == .won ? "用 \(TileRecordStore.time(seconds)) 通关了" : "消了 \(game.cleared)/\(game.total) 张就卡住了"
        let text = "我在「叠叠消」\(what)\(result)！挑战码 \(game.code)：打开「值班提醒」› 全部功能 › 叠叠消，把这段话粘贴进「挑战码」，玩同一局比比谁快。"
        ActivityShare.present([text], excluding: ActivityShare.chatOnly) { _ in }
    }
}

// MARK: - 一张牌

struct TileFace: View {
    let kind: Int
    let side: CGFloat
    var covered = false
    var glowing = false

    /// 牌面：天上的、值班时手边的
    static let symbols = ["🛰️", "📡", "🚀", "🌍", "🌙", "⭐️", "☀️", "🪐", "☄️", "🔭", "☕️", "⏰"]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.2, style: .continuous)
        ZStack {
            // 牌的厚度：底下露出一条
            shape.fill(Color(light: 0x8DBF5A, dark: 0x5E8A3A)).offset(y: side * 0.07)
            shape.fill(Color(light: 0xFFFBEA, dark: 0xF1ECD6))
            shape.strokeBorder(Color.black.opacity(0.12), lineWidth: max(1, side * 0.02))
            Text(Self.symbols[kind % Self.symbols.count]).font(.system(size: side * 0.56))
            if covered { shape.fill(Color.black.opacity(0.42)) }
        }
        .frame(width: side, height: side)
        .scaleEffect(glowing ? 1.1 : 1)
        .accessibilityLabel(covered ? "被压住的牌" : "牌")
    }
}
