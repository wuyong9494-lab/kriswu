@preconcurrency import MultipeerConnectivity
import UIKit

/// 「叠叠消」面对面对战：身边几台手机（同一个 Wi-Fi 或开着蓝牙就行，不用联网、不用账号）连成一个房间，
/// 房主开局，大家玩同一局；每走一步把进度发给房主，房主转给别人，每台手机上都看得到别人消了几张。
/// 房间里最多 8 个人；一局正在打的时候不让新的人进（打完这局再进）
@MainActor
final class TileRaceSession: NSObject, ObservableObject {
    enum Role { case host, guest }

    /// 附近找到的一个房间
    struct Room: Identifiable, Equatable {
        let id: String
        let name: String
        fileprivate let peer: MCPeerID
    }

    /// 开的一局
    struct Round: Identifiable, Equatable {
        let id: Int
        let level: TileGame.Level
        let seed: UInt64
    }

    /// Bonjour 服务名（Info.plist 的 NSBonjourServices 里也要写上 _ddx-race._tcp、_ddx-race._udp）
    static let service = "ddx-race"
    static let maxPlayers = 8

    let role: Role
    let me: TileRace.Player
    /// 房间里的人（含自己）：等开局时是名单，开局后带着每个人这一局的进度
    @Published private(set) var players: [TileRace.Player] = []
    /// 找到的房间（加入的人用）
    @Published private(set) var rooms: [Room] = []
    /// 已经进了谁的房间（加入的人用）
    @Published private(set) var joined: String?
    /// 正在连的房间
    @Published private(set) var joining: String?
    /// 最近开的一局（打完了也留着，房间里看排名）
    @Published private(set) var round: Round?
    /// 正在显示的那一局（关掉回房间时变成 nil，这一局的进度照样收发）
    @Published var presented: Round?
    /// 出了什么事（连不上、房主走了……）
    @Published var notice: String?

    private let peer: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    /// 要进 / 已经进的那个房间的房主（加入的人用；同一个房间里的别人也会连上来，只认房主）
    private var host: MCPeerID?
    /// 每台连上的手机是房间里的谁（房主用）
    private var playerOfPeer: [MCPeerID: String] = [:]
    private var roundsStarted = 0

    init(role: Role, name: String) {
        self.role = role
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12))
        let display = trimmed.isEmpty ? "我" : trimmed
        me = TileRace.Player(id: String(UUID().uuidString.prefix(8)), name: display)
        peer = MCPeerID(displayName: display)
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
        players = [me]
    }

    /// 开始让别人找到（房主）或开始找房间（加入的人）；已经开始了就不再开（关掉一局回到房间时会再调一次）
    func start() {
        switch role {
        case .host:
            guard advertiser == nil else { return }
            let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["name": me.name], serviceType: Self.service)
            advertiser.delegate = self
            advertiser.startAdvertisingPeer()
            self.advertiser = advertiser
        case .guest:
            guard browser == nil else { return }
            let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.service)
            browser.delegate = self
            browser.startBrowsingForPeers()
            self.browser = browser
        }
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
    }

    /// 加入一个房间
    func join(_ room: Room) {
        guard joined == nil else { return }
        joining = room.name
        host = room.peer
        notice = nil
        let hello = try? JSONEncoder().encode(TileRace.Message.hello(me))
        browser?.invitePeer(room.peer, to: session, withContext: hello, timeout: 20)
    }

    /// 房主开一局：大家同时开始玩同一局
    func begin(level: TileGame.Level) {
        guard role == .host else { return }
        roundsStarted += 1
        let seed = UInt64.random(in: 0..<TileGame.seedLimit)
        resetProgress()
        broadcast(.start(round: roundsStarted, level: level, seed: seed))
        round = Round(id: roundsStarted, level: level, seed: seed)
        presented = round
    }

    /// 自己这一局走了一步：告诉大家
    func report(_ game: TileGame, seconds: Double) {
        guard let round else { return }
        var mine = me
        mine.cleared = game.cleared + game.clearing.count
        mine.total = game.total
        mine.status = game.status
        mine.seconds = seconds
        share(mine, round: round)
    }

    /// 中途退出：这一局算输（别人那边才知道这局打完了）
    func forfeit(_ player: TileRace.Player) {
        guard let round else { return }
        share(player, round: round)
    }

    private func share(_ player: TileRace.Player, round: Round) {
        update(player)
        if role == .host {
            broadcast(.progress(round: round.id, player: player))
        } else {
            send(.progress(round: round.id, player: player), to: host.map { [$0] } ?? [])
        }
    }

    /// 这一局大家都打完了
    var roundFinished: Bool { TileRace.finished(players) }

    /// 一局正在打（房主不让新的人进）
    var roundInProgress: Bool { round != nil && !roundFinished }

    private func resetProgress() {
        players = players.map { TileRace.Player(id: $0.id, name: $0.name) }
    }

    private func update(_ player: TileRace.Player) {
        if let i = players.firstIndex(where: { $0.id == player.id }) {
            players[i] = player
        } else {
            players.append(player)
        }
    }

    // MARK: - 收发

    private func broadcast(_ message: TileRace.Message, except skipped: MCPeerID? = nil) {
        send(message, to: session.connectedPeers.filter { $0 != skipped })
    }

    private func send(_ message: TileRace.Message, to peers: [MCPeerID]) {
        guard !peers.isEmpty, let data = try? JSONEncoder().encode(message) else { return }
        try? session.send(data, toPeers: peers, with: .reliable)
    }

    private func received(_ message: TileRace.Message, from sender: MCPeerID) {
        switch message {
        case .hello(let player):
            guard role == .host else { return }
            playerOfPeer[sender] = player.id
            update(TileRace.Player(id: player.id, name: player.name))
            broadcast(.lobby(players))
        case .lobby(let list):
            guard role == .guest else { return }
            // 开局后别人的进度以各自发来的为准，名单只管有谁
            players = list.map { listed in players.first { $0.id == listed.id } ?? listed }
            if !players.contains(where: { $0.id == me.id }) { players.append(me) }
        case .start(let id, let level, let seed):
            guard role == .guest else { return }
            resetProgress()
            round = Round(id: id, level: level, seed: seed)
            presented = round
        case .progress(let id, let player):
            guard id == round?.id else { return }
            update(player)
            if role == .host { broadcast(.progress(round: id, player: player), except: sender) }
        }
    }

    private func connected(_ peer: MCPeerID) {
        switch role {
        case .host:
            break
        case .guest:
            guard peer == host else { return }
            joined = joining ?? peer.displayName
            joining = nil
            browser?.stopBrowsingForPeers()
            send(.hello(me), to: [peer])
        }
    }

    private func disconnected(_ peer: MCPeerID) {
        switch role {
        case .host:
            guard let id = playerOfPeer.removeValue(forKey: peer) else { return }
            players.removeAll { $0.id == id }
            broadcast(.lobby(players))
        case .guest:
            guard peer == host else { return }
            host = nil
            if joined != nil {
                notice = "和房主断开了：房主可能退出了，或者离得太远"
                joined = nil
                round = nil
                presented = nil
                players = [me]
                browser?.startBrowsingForPeers()
            } else if joining != nil {
                notice = "没进去：房间可能正在打一局，或者已经满了，等一会再点"
                joining = nil
            }
        }
    }
}

// MARK: - 系统回调（在后台线程上来，转回主线程处理）

extension TileRaceSession: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected: self.connected(peerID)
            case .notConnected: self.disconnected(peerID)
            default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(TileRace.Message.self, from: data) else { return }
        Task { @MainActor in self.received(message, from: peerID) }
    }

    nonisolated func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID,
                             certificateHandler: @escaping (Bool) -> Void) {
        certificateHandler(true)
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID,
                             with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID,
                             at localURL: URL?, withError error: Error?) {}
}

extension TileRaceSession: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let hello = context.flatMap { try? JSONDecoder().decode(TileRace.Message.self, from: $0) }
        Task { @MainActor in
            // 一局正在打、或者满了：不让进
            let accept = !self.roundInProgress && self.session.connectedPeers.count < Self.maxPlayers - 1
            if accept, case .hello(let player) = hello {
                self.playerOfPeer[peerID] = player.id
            }
            invitationHandler(accept, accept ? self.session : nil)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in self.notice = "开不了房间：在系统设置里允许「值班提醒」使用本地网络，再打开 Wi-Fi 或蓝牙" }
    }
}

extension TileRaceSession: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let name = info?["name"] ?? peerID.displayName
        Task { @MainActor in
            let room = Room(id: "\(peerID.hash)", name: name, peer: peerID)
            self.rooms.removeAll { $0.id == room.id }
            self.rooms.append(room)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in self.rooms.removeAll { $0.peer == peerID } }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in self.notice = "找不了房间：在系统设置里允许「值班提醒」使用本地网络，再打开 Wi-Fi 或蓝牙" }
    }
}
