@preconcurrency import GameKit
import Foundation

/// 五子棋轮流下：Game Center 的回合制对局。下完一步发出去，对方什么时候有空什么时候下（轮到谁，系统会通知谁）。
/// 两个人输同一个房间号：先输的开一盘、执黑先下第一步；后输的进来执白
@MainActor
final class GomokuTurns: NSObject, ObservableObject {
    static let shared = GomokuTurns()

    /// 存在对局里的：房间号和棋局
    struct Record: Codable {
        var code: Int
        var game: Gomoku
    }

    enum Failure: LocalizedError {
        case notYourTurn
        var errorDescription: String? { "还没轮到你" }
    }

    @Published private(set) var matches: [GKTurnBasedMatch] = []
    @Published private(set) var loading = false
    @Published var problem: String?
    /// 对方下了一步、对局结束了：正在看的那一盘重新读一下
    @Published private(set) var changes = 0

    func refresh() async {
        guard await GameCenter.shared.signIn() else {
            problem = GameCenter.shared.problem
            return
        }
        loading = true
        defer { loading = false }
        do {
            matches = try await GKTurnBasedMatch.loadMatches().sorted { $0.creationDate > $1.creationDate }
            problem = nil
        } catch {
            problem = GameCenter.explain(error)
        }
    }

    /// 用房间号开一盘，或者进别人用这个房间号开的那一盘
    func find(code: Int) async throws -> GKTurnBasedMatch {
        guard await GameCenter.shared.signIn() else {
            throw NSError(domain: GKErrorDomain, code: GKError.Code.notAuthenticated.rawValue)
        }
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        // 和实时对战的房间号分开
        request.playerGroup = GameKind.gomoku.index * 100_000 + 50_000 + code
        let match = try await GKTurnBasedMatch.find(for: request)
        await refresh()
        return match
    }

    func reload(_ match: GKTurnBasedMatch) async throws -> GKTurnBasedMatch {
        try await GKTurnBasedMatch.load(withID: match.matchID)
    }

    // MARK: 一盘的状态

    static func record(of match: GKTurnBasedMatch) -> Record? {
        match.matchData.flatMap { $0.isEmpty ? nil : try? JSONDecoder().decode(Record.self, from: $0) }
    }

    static func game(of match: GKTurnBasedMatch) -> Gomoku {
        record(of: match)?.game ?? Gomoku()
    }

    static func isMe(_ participant: GKTurnBasedParticipant) -> Bool {
        participant.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID
    }

    /// 我执什么：第一个人执黑
    static func myStone(in match: GKTurnBasedMatch) -> Gomoku.Stone? {
        match.participants.firstIndex(where: isMe).map { $0 == 0 ? .black : .white }
    }

    static func isMyTurn(_ match: GKTurnBasedMatch) -> Bool {
        match.status == .open && match.currentParticipant.map(isMe) == true
    }

    static func opponent(in match: GKTurnBasedMatch) -> GKTurnBasedParticipant? {
        match.participants.first { !isMe($0) }
    }

    /// 列表里一盘的一句话状态
    static func summary(of match: GKTurnBasedMatch) -> String {
        let game = game(of: match)
        if match.status == .ended || game.isOver {
            if let winner = game.winner, let mine = myStone(in: match) {
                return winner == mine ? (game.resigned == nil ? "你赢了" : "对方认输，你赢了") : (game.resigned == mine ? "你认输了" : "你输了")
            }
            if opponent(in: match)?.matchOutcome == .quit { return "对方退出了" }
            return game.isDraw ? "和棋" : "结束了"
        }
        if opponent(in: match)?.player == nil { return isMyTurn(match) ? "轮到你下第一步" : "等对方输入房间号进来" }
        return isMyTurn(match) ? "轮到你了" : "等对方下"
    }

    // MARK: 下棋

    /// 下一步：发给对方（下完连成五个或下满了就结束这一盘）。返回最新的这一盘
    func play(_ index: Int, in match: GKTurnBasedMatch, code: Int) async throws -> GKTurnBasedMatch {
        var record = Self.record(of: match) ?? Record(code: code, game: Gomoku())
        guard Self.isMyTurn(match), record.game.next == Self.myStone(in: match), record.game.place(index) else {
            throw Failure.notYourTurn
        }
        let data = try JSONEncoder().encode(record)
        if record.game.isOver {
            setOutcomes(match, winner: record.game.winner)
            try await match.endMatchInTurn(withMatch: data)
        } else {
            let next = match.participants.filter { !Self.isMe($0) }
            try await match.endTurn(withNextParticipants: next, turnTimeout: GKTurnTimeoutDefault, match: data)
        }
        changes += 1
        await refresh()
        return try await reload(match)
    }

    /// 认输（轮到对方时也能认输）
    func resign(_ match: GKTurnBasedMatch) async throws {
        guard let mine = Self.myStone(in: match) else { return }
        var record = Self.record(of: match) ?? Record(code: 0, game: Gomoku())
        record.game.resign(mine)
        if Self.isMyTurn(match) {
            setOutcomes(match, winner: mine.other)
            try await match.endMatchInTurn(withMatch: JSONEncoder().encode(record))
        } else {
            try await match.participantQuitOutOfTurn(with: .quit)
        }
        changes += 1
        await refresh()
    }

    /// 对方中途退出了、轮到我：这一盘算我赢，结束掉
    func settleQuit(_ match: GKTurnBasedMatch) async {
        guard Self.isMyTurn(match), Self.opponent(in: match)?.matchOutcome == .quit, let mine = Self.myStone(in: match) else { return }
        var record = Self.record(of: match) ?? Record(code: 0, game: Gomoku())
        record.game.resign(mine.other)
        setOutcomes(match, winner: mine)
        _ = try? await match.endMatchInTurn(withMatch: JSONEncoder().encode(record))
        await refresh()
    }

    func remove(_ match: GKTurnBasedMatch) async {
        _ = try? await match.remove()
        await refresh()
    }

    private func setOutcomes(_ match: GKTurnBasedMatch, winner: Gomoku.Stone?) {
        for (index, participant) in match.participants.enumerated() where participant.matchOutcome == .none {
            let stone: Gomoku.Stone = index == 0 ? .black : .white
            participant.matchOutcome = winner == nil ? .tied : (winner == stone ? .won : .lost)
        }
    }
}

extension GomokuTurns: GKLocalPlayerListener {
    nonisolated func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool) {
        // Transfer only a value, then inspect the main-actor-owned refreshed match.
        let matchID = match.matchID
        Task { @MainActor in
            await self.refresh()
            self.changes += 1
            if let refreshed = self.matches.first(where: { $0.matchID == matchID }), Self.isMyTurn(refreshed) {
                ToastCenter.shared.show("五子棋轮到你下了（小游戏 › 五子棋 › 轮流下）")
            }
        }
    }

    nonisolated func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        Task { @MainActor in
            await self.refresh()
            self.changes += 1
        }
    }
}
