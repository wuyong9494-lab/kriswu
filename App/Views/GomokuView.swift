@preconcurrency import GameKit
import SwiftUI

// MARK: - 战绩（和电脑下的，只存在这台手机上）

@MainActor
final class GomokuRecords: ObservableObject {
    static let shared = GomokuRecords()
    private static let key = "gomoku.records"

    struct Tally: Codable, Equatable {
        var won: [Int: Int] = [:]
        var lost: [Int: Int] = [:]
    }

    @Published private(set) var tally: Tally

    private init() {
        tally = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Tally.self, from: $0) } ?? Tally()
    }

    func add(won: Bool, level: Gomoku.Level) {
        if won { tally.won[level.rawValue, default: 0] += 1 } else { tally.lost[level.rawValue, default: 0] += 1 }
        if let data = try? JSONEncoder().encode(tally) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

// MARK: - 首页

struct GomokuHomeView: View {
    @ObservedObject private var records = GomokuRecords.shared
    @ObservedObject private var turns = GomokuTurns.shared
    @ObservedObject private var center = GameCenter.shared
    @State private var level = Gomoku.Level.normal
    @State private var black = true
    @State private var local: GomokuLocalScreen.Mode?
    @State private var room: GameRoomEntry?
    @State private var turnCode = ""
    @State private var finding = false
    @State private var opened: GomokuTurnEntry?

    struct GomokuTurnEntry: Identifiable {
        let id = UUID()
        let match: GKTurnBasedMatch
        let code: Int
    }

    var body: some View {
        List {
            Section {
                Picker("难度", selection: $level) {
                    ForEach(Gomoku.Level.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("我执黑先下", isOn: $black)
                Button {
                    local = .computer(level, black ? .black : .white)
                } label: {
                    Label("和电脑下", systemImage: "cpu")
                }
            } header: {
                Text("自己玩")
            } footer: {
                let won = records.tally.won[level.rawValue] ?? 0, lost = records.tally.lost[level.rawValue] ?? 0
                Text(won + lost == 0 ? "黑先，横、竖、斜连成五个就赢；点一下放上去、再点一下落子。" : "和「\(level.title)」的电脑下：赢了 \(won) 盘、输了 \(lost) 盘。")
            }
            Section {
                Button {
                    local = .sameDevice
                } label: {
                    Label("两个人用这一台手机下", systemImage: "person.2")
                }
            }
            GameRoomButtons(kind: .gomoku) { room = GameRoomEntry(room: $0) }
            turnsSection
        }
        .appList()
        .navigationTitle("五子棋")
        .task {
            if GKLocalPlayer.local.isAuthenticated { await turns.refresh() }
        }
        .fullScreenCover(item: $local) { mode in
            GomokuLocalScreen(mode: mode)
        }
        .fullScreenCover(item: $room) { entry in
            GomokuRoomScreen(room: entry.room)
        }
        .sheet(item: $opened) { entry in
            NavigationStack { GomokuTurnScreen(match: entry.match, code: entry.code) }
        }
    }

    private var turnsSection: some View {
        Section {
            HStack {
                TextField("房间号（4 位数）", text: $turnCode)
                    .keyboardType(.numberPad)
                Button("随机一个") { turnCode = String(RoomCode.make(players: 2)) }
                    .buttonStyle(.borderless)
            }
            Button {
                Task { await find() }
            } label: {
                HStack {
                    Label("开一盘 / 进这一盘", systemImage: "hourglass")
                    if finding { Spacer(); ProgressView() }
                }
            }
            .disabled(RoomCode.parse(turnCode) == nil || finding)
            if let problem = turns.problem {
                Text(problem).font(DS.Font.caption).foregroundStyle(DS.Palette.warning)
            }
            if !center.signedIn {
                Button {
                    Task { await turns.refresh() }
                } label: {
                    Label("登录 Game Center，看我的对局", systemImage: "person.crop.circle.badge.checkmark")
                }
            }
            ForEach(turns.matches, id: \.matchID) { match in
                Button {
                    opened = GomokuTurnEntry(match: match, code: GomokuTurns.record(of: match)?.code ?? 0)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(GomokuTurns.opponent(in: match)?.player?.displayName ?? "还没人进来")
                                .foregroundStyle(.primary)
                            Text("第 \(GomokuTurns.game(of: match).moves.count) 手 · \(match.creationDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(DS.Font.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(GomokuTurns.summary(of: match))
                            .font(DS.Font.caption.weight(.semibold))
                            .foregroundStyle(GomokuTurns.isMyTurn(match) ? DS.Palette.accent : .secondary)
                    }
                }
                .swipeActions {
                    if match.status == .ended || GomokuTurns.game(of: match).isOver {
                        Button("删除", role: .destructive) { Task { await turns.remove(match) } }
                    }
                }
            }
        } header: {
            Text("轮流下（不用同时在线）")
        } footer: {
            Text("两个人输同一个房间号：先输的开一盘、执黑下第一步，下完对方输这个房间号就进来了。之后轮到谁，系统通知谁，有空再下。要登录 Game Center。")
        }
    }

    private func find() async {
        guard let code = RoomCode.parse(turnCode) else { return }
        finding = true
        defer { finding = false }
        do {
            let match = try await turns.find(code: code)
            opened = GomokuTurnEntry(match: match, code: code)
        } catch {
            ToastCenter.shared.show(GameCenter.explain(error), style: .warning)
        }
    }
}

extension GomokuLocalScreen.Mode: Identifiable {
    var id: String {
        switch self {
        case .computer(let level, let stone): return "computer-\(level.rawValue)-\(stone.rawValue)"
        case .sameDevice: return "same"
        }
    }
}

// MARK: - 棋盘

struct GomokuBoard: View {
    let game: Gomoku
    /// 点了一下、还没落子的位置
    var preview: Int?
    var enabled = true
    var onTap: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let step = side / CGFloat(Gomoku.size)
            ZStack(alignment: .topLeading) {
                grid(side: side, step: step)
                ForEach(game.moves, id: \.self) { index in
                    if let stone = game.cells[index] {
                        stoneView(stone, diameter: step * 0.9)
                            .position(center(index, step))
                    }
                }
                if let last = game.moves.last {
                    Circle().fill(DS.Palette.danger).frame(width: step * 0.22, height: step * 0.22)
                        .position(center(last, step))
                }
                if let first = game.line.first, let end = game.line.last {
                    Path { path in
                        path.move(to: center(first, step))
                        path.addLine(to: center(end, step))
                    }
                    .stroke(DS.Palette.danger.opacity(0.8), style: StrokeStyle(lineWidth: step * 0.14, lineCap: .round))
                }
                if let preview, game.cells.indices.contains(preview), game.cells[preview] == nil {
                    stoneView(game.next, diameter: step * 0.9)
                        .opacity(0.45)
                        .position(center(preview, step))
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                let row = Int(location.y / step), column = Int(location.x / step)
                guard enabled, (0..<Gomoku.size).contains(row), (0..<Gomoku.size).contains(column) else { return }
                onTap(row * Gomoku.size + column)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func center(_ index: Int, _ step: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(index % Gomoku.size) + 0.5) * step, y: (CGFloat(index / Gomoku.size) + 0.5) * step)
    }

    private func grid(side: CGFloat, step: CGFloat) -> some View {
        Canvas { context, _ in
            let board = CGRect(x: 0, y: 0, width: side, height: side)
            context.fill(Path(roundedRect: board, cornerRadius: 10), with: .color(Color(light: 0xE6C48A, dark: 0xB89462)))
            var lines = Path()
            for i in 0..<Gomoku.size {
                let p = (CGFloat(i) + 0.5) * step
                lines.move(to: CGPoint(x: step / 2, y: p))
                lines.addLine(to: CGPoint(x: side - step / 2, y: p))
                lines.move(to: CGPoint(x: p, y: step / 2))
                lines.addLine(to: CGPoint(x: p, y: side - step / 2))
            }
            context.stroke(lines, with: .color(.black.opacity(0.6)), lineWidth: 0.8)
            for (row, column) in [(3, 3), (3, 11), (7, 7), (11, 3), (11, 11)] {
                let dot = CGRect(x: (CGFloat(column) + 0.5) * step - 3, y: (CGFloat(row) + 0.5) * step - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: dot), with: .color(.black.opacity(0.75)))
            }
        }
    }

    private func stoneView(_ stone: Gomoku.Stone, diameter: CGFloat) -> some View {
        let colors: [Color] = stone == .black ? [Color(white: 0.45), .black] : [.white, Color(white: 0.8)]
        return Circle()
            .fill(RadialGradient(colors: colors, center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: diameter * 0.7))
            .frame(width: diameter, height: diameter)
            .shadow(color: .black.opacity(0.35), radius: diameter * 0.06, x: diameter * 0.03, y: diameter * 0.05)
    }
}

/// 对局页上面一排：两边是谁、轮到谁
struct GomokuHeader: View {
    let black: String
    let white: String
    let game: Gomoku
    var status: String?

    var body: some View {
        VStack(spacing: DS.Space.xs) {
            HStack {
                side(black, .black)
                Spacer()
                Text("第 \(game.moves.count) 手").font(DS.Font.caption).foregroundStyle(.secondary)
                Spacer()
                side(white, .white)
            }
            Text(status ?? defaultStatus).font(DS.Font.headline)
        }
        .padding(.horizontal, DS.Space.m)
    }

    private var defaultStatus: String {
        if let winner = game.winner {
            let name = winner == .black ? black : white
            return game.resigned != nil ? "\(game.resigned == .black ? black : white)认输，\(name)赢了" : "\(name)赢了"
        }
        if game.isDraw { return "下满了，和棋" }
        return "轮到\(game.next == .black ? black : white)（\(game.next.title)）"
    }

    private func side(_ name: String, _ stone: Gomoku.Stone) -> some View {
        HStack(spacing: 6) {
            Circle().fill(stone == .black ? Color.black : Color.white)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.3)))
                .frame(width: 16, height: 16)
            Text(name).font(DS.Font.callout).lineLimit(1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(game.next == stone && !game.isOver ? DS.Palette.accentSoft : Color.clear, in: Capsule())
    }
}

/// 页面框：上面关闭、下面按钮
private struct GomokuFrame<Content: View>: View {
    var title: String
    var close: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: DS.Space.m) {
            HStack {
                Button(action: close) {
                    Image(systemName: "xmark").font(.headline).frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text(title).font(DS.Font.headline)
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, DS.Space.m)
            content()
            Spacer(minLength: 0)
        }
        .padding(.top, DS.Space.xs)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .appBackground()
    }
}

// MARK: - 和电脑下、一台手机两个人

struct GomokuLocalScreen: View {
    enum Mode: Equatable, Hashable {
        case computer(Gomoku.Level, Gomoku.Stone)
        case sameDevice
    }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @State private var game: Gomoku
    @State private var preview: Int?
    @State private var thinking = false
    @State private var recorded = false
    @State private var random = SeededRandom(seed: UInt64.random(in: 0..<UInt64.max))

    init(mode: Mode, initial: Gomoku = Gomoku()) {
        self.mode = mode
        _game = State(initialValue: initial)
    }

    private var computerStone: Gomoku.Stone? {
        if case .computer(_, let me) = mode { return me.other }
        return nil
    }

    private var names: (black: String, white: String) {
        switch mode {
        case .computer(let level, let me):
            let computer = "电脑（\(level.title)）"
            return me == .black ? ("我", computer) : (computer, "我")
        case .sameDevice:
            return ("黑方", "白方")
        }
    }

    var body: some View {
        GomokuFrame(title: computerStone == nil ? "两个人下" : "和电脑下", close: { dismiss() }) {
            GomokuHeader(black: names.black, white: names.white, game: game, status: thinking ? "电脑在想…" : nil)
            GomokuBoard(game: game, preview: preview, enabled: !thinking && !game.isOver && game.next != computerStone) { tap($0) }
                .padding(.horizontal, DS.Space.s)
            Text(preview == nil ? " " : "再点一下落子").font(DS.Font.caption).foregroundStyle(.secondary)
            HStack(spacing: DS.Space.s) {
                Button("悔棋") { undo() }
                    .disabled(game.moves.isEmpty || thinking || game.winner != nil && game.resigned != nil)
                if game.isOver {
                    Button("再来一盘") { restart() }.buttonStyle(.borderedProminent)
                } else {
                    Button("认输", role: .destructive) { resign() }.disabled(thinking || game.moves.isEmpty)
                }
            }
            .buttonStyle(.bordered)
        }
        .onAppear { computerTurnIfNeeded() }
    }

    private func tap(_ index: Int) {
        guard game.cells[index] == nil else { return }
        if preview == index {
            place(index)
        } else {
            Haptics.select()
            preview = index
        }
    }

    private func place(_ index: Int) {
        guard game.place(index) else { return }
        Haptics.tap()
        preview = nil
        finished()
        computerTurnIfNeeded()
    }

    private func computerTurnIfNeeded() {
        guard case .computer(let level, _) = mode, !game.isOver, game.next == computerStone else { return }
        thinking = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            var random = self.random
            let move = game.suggestion(level: level, random: &random)
            self.random = random
            if let move { game.place(move) }
            thinking = false
            finished()
        }
    }

    private func finished() {
        guard game.isOver, !recorded else { return }
        recorded = true
        if case .computer(let level, let me) = mode, !game.isDraw {
            GomokuRecords.shared.add(won: game.winner == me, level: level)
            if game.winner == me { Haptics.success() } else { Haptics.warning() }
        }
    }

    private func undo() {
        preview = nil
        if computerStone != nil {
            // 退到又轮到我
            game.undo(game.next == computerStone ? 1 : 2)
        } else {
            game.undo()
        }
        recorded = false
    }

    private func resign() {
        game.resign(computerStone?.other ?? game.next)
        finished()
    }

    private func restart() {
        game = Gomoku()
        preview = nil
        recorded = false
        computerTurnIfNeeded()
    }
}

// MARK: - 面对面、远程实时

/// 房间里的一盘五子棋：两个人，房主开局（第一盘房主执黑，之后轮换），每一步发给对方
@MainActor
final class GomokuRoomGame: ObservableObject {
    enum Message: Codable {
        case start(round: Int, black: String)
        case move(round: Int, index: Int)
        case resign(round: Int, stone: Gomoku.Stone)
        case again
    }

    let room: GameRoom
    @Published private(set) var game = Gomoku()
    @Published private(set) var round = 0
    @Published private(set) var black: String?
    /// 对方想再来一盘
    @Published private(set) var opponentWantsAgain = false

    init(room: GameRoom) {
        self.room = room
        room.onPayload = { [weak self] data, from in self?.received(data, from: from) }
        room.onMembersChanged = { [weak self] in self?.membersChanged() }
    }

    var myStone: Gomoku.Stone? {
        guard let black else { return nil }
        return black == room.me.id ? .black : .white
    }

    var opponent: GameRoom.Member? { room.others.first }

    private func membersChanged() {
        objectWillChange.send()
        if room.isHost, room.members.count == 2, round == 0 { newRound() }
    }

    func newRound() {
        guard room.isHost, let other = opponent else { return }
        round += 1
        let first = round % 2 == 1 ? room.me.id : other.id
        apply(.start(round: round, black: first))
        send(.start(round: round, black: first))
    }

    func place(_ index: Int) {
        guard let myStone, game.next == myStone, game.place(index) else { return }
        Haptics.tap()
        send(.move(round: round, index: index))
    }

    func resign() {
        guard let myStone, !game.isOver else { return }
        game.resign(myStone)
        send(.resign(round: round, stone: myStone))
    }

    func again() {
        if room.isHost { newRound() } else { send(.again) }
    }

    private func send(_ message: Message) {
        if let data = try? JSONEncoder().encode(message) { room.send(data) }
    }

    private func received(_ data: Data, from: String) {
        guard let message = try? JSONDecoder().decode(Message.self, from: data) else { return }
        switch message {
        case .start:
            guard from == room.hostID else { return }
            apply(message)
        case .move(let r, let index):
            // 只认轮到的那个人下的
            guard r == round, let black, (from == black) == (game.next == .black) else { return }
            game.place(index)
        case .resign(let r, let stone):
            guard r == round else { return }
            game.resign(stone)
        case .again:
            if room.isHost { newRound() } else { opponentWantsAgain = true }
        }
    }

    private func apply(_ message: Message) {
        guard case .start(let r, let first) = message else { return }
        round = r
        black = first
        game = Gomoku()
        opponentWantsAgain = false
    }
}

struct GomokuRoomScreen: View {
    @ObservedObject private var room: GameRoom
    @StateObject private var model: GomokuRoomGame
    @Environment(\.dismiss) private var dismiss
    @State private var preview: Int?

    init(room: GameRoom) {
        self.room = room
        _model = StateObject(wrappedValue: GomokuRoomGame(room: room))
    }

    var body: some View {
        Group {
            if room.phase == .ready, model.round > 0 {
                playing
            } else {
                NavigationStack {
                    List {
                        GameRoomLobby(room: room) {
                            Section { Text(room.isHost ? "人到了，马上开始…" : "等房主开始…").foregroundStyle(.secondary) }
                        }
                    }
                    .appList()
                    .navigationTitle(room.code == nil ? "面对面下五子棋" : "远程下五子棋")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("离开") { leave() } }
                    }
                }
            }
        }
        .onAppear { room.start() }
    }

    private var playing: some View {
        let me = room.me.name, other = model.opponent?.name ?? "对方"
        let mine = model.myStone ?? .black
        return GomokuFrame(title: room.code == nil ? "面对面" : "远程", close: { leave() }) {
            GomokuHeader(black: mine == .black ? me : other, white: mine == .white ? me : other, game: model.game,
                         status: status)
            GomokuBoard(game: model.game, preview: preview, enabled: model.game.next == mine && !model.game.isOver) { index in
                if preview == index {
                    model.place(index)
                    preview = nil
                } else {
                    Haptics.select()
                    preview = index
                }
            }
            .padding(.horizontal, DS.Space.s)
            Text(preview == nil ? " " : "再点一下落子").font(DS.Font.caption).foregroundStyle(.secondary)
            HStack(spacing: DS.Space.s) {
                if model.game.isOver {
                    Button(model.opponentWantsAgain ? "对方想再来一盘：开始" : "再来一盘") { model.again() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("认输", role: .destructive) { model.resign() }.buttonStyle(.bordered)
                }
            }
        }
    }

    private var status: String? {
        if room.phase != .ready { return "对方断开了" }
        guard !model.game.isOver else { return nil }
        return model.game.next == model.myStone ? "轮到你了（\(model.game.next.title)）" : "等对方下…"
    }

    private func leave() {
        room.leave()
        dismiss()
    }
}

// MARK: - 轮流下

struct GomokuTurnScreen: View {
    @State var match: GKTurnBasedMatch
    let code: Int
    @ObservedObject private var turns = GomokuTurns.shared
    @Environment(\.dismiss) private var dismiss
    @State private var preview: Int?
    @State private var sending = false
    @State private var confirmingResign = false

    private var game: Gomoku { GomokuTurns.game(of: match) }
    private var mine: Gomoku.Stone { GomokuTurns.myStone(in: match) ?? .black }
    private var myTurn: Bool { GomokuTurns.isMyTurn(match) && !game.isOver }

    var body: some View {
        let other = GomokuTurns.opponent(in: match)?.player?.displayName ?? "等人进来"
        VStack(spacing: DS.Space.m) {
            GomokuHeader(black: mine == .black ? "我" : other, white: mine == .white ? "我" : other, game: game,
                         status: game.isOver || match.status == .ended ? GomokuTurns.summary(of: match) : (myTurn ? "轮到你了" : GomokuTurns.summary(of: match)))
            GomokuBoard(game: game, preview: preview, enabled: myTurn && !sending) { index in
                if preview == index {
                    Task { await play(index) }
                } else {
                    Haptics.select()
                    preview = index
                }
            }
            .padding(.horizontal, DS.Space.s)
            Text(sending ? "发出去…" : preview == nil ? (code > 0 ? "房间号 \(code)" : " ") : "再点一下落子")
                .font(DS.Font.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, DS.Space.s)
        .appBackground()
        .navigationTitle("轮流下")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                if match.status != .ended && !game.isOver {
                    Button("认输", role: .destructive) { confirmingResign = true }
                }
            }
        }
        .confirmationDialog("认输？这一盘就结束了", isPresented: $confirmingResign, titleVisibility: .visible) {
            Button("认输", role: .destructive) { Task { await resign() } }
        }
        .task { await reload() }
        .onChange(of: turns.changes) { _ in Task { await reload() } }
    }

    private func reload() async {
        if let fresh = try? await turns.reload(match) { match = fresh }
        await turns.settleQuit(match)
    }

    private func play(_ index: Int) async {
        sending = true
        defer { sending = false }
        do {
            match = try await turns.play(index, in: match, code: code)
            preview = nil
            Haptics.tap()
        } catch {
            ToastCenter.shared.show((error as? LocalizedError)?.errorDescription ?? GameCenter.explain(error), style: .warning)
        }
    }

    private func resign() async {
        do {
            try await turns.resign(match)
            await reload()
        } catch {
            ToastCenter.shared.show(GameCenter.explain(error), style: .warning)
        }
    }
}
