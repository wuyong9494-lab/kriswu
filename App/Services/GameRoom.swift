@preconcurrency import GameKit
@preconcurrency import MultipeerConnectivity
import UIKit

/// 小游戏的种类：联机时用来分开（叠叠消的房间不会和五子棋的连到一起）
enum GameKind: String, Codable, Sendable {
    case tiles, gomoku

    /// Game Center 配对分组用的编号
    var index: Int {
        switch self {
        case .tiles: return 1
        case .gomoku: return 2
        }
    }

    var title: String {
        switch self {
        case .tiles: return "叠叠消"
        case .gomoku: return "五子棋"
        }
    }
}

/// 远程房间号：4 位数，第一位是几个人玩（2–8）。大家输同一个房间号，Game Center 把这几个人配到一起
enum RoomCode {
    static func make(players: Int) -> Int {
        min(max(players, 2), 8) * 1000 + Int.random(in: 100...999)
    }

    static func players(of code: Int) -> Int { code / 1000 }

    static func parse(_ text: String) -> Int? {
        let digits = text.filter(\.isNumber)
        guard digits.count == 4, let code = Int(digits), (2...8).contains(code / 1000) else { return nil }
        return code
    }
}

// MARK: - Game Center 登录

/// 登录 Game Center（远程对战、轮流下要用；大家在手机「设置 › Game Center」登录自己的 Apple ID）
@MainActor
final class GameCenter: ObservableObject {
    static let shared = GameCenter()

    @Published private(set) var signedIn = false
    @Published private(set) var problem: String?
    private enum Asking { case never, waiting, answered }
    private var asking = Asking.never
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    /// 登录好了返回 true。第一次会弹出系统的登录页；没登录过的，系统只问一次，之后要去「设置 › Game Center」登录
    func signIn() async -> Bool {
        if GKLocalPlayer.local.isAuthenticated {
            signedIn = true
            return true
        }
        if asking == .answered { return false }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            guard asking == .never else { return }
            asking = .waiting
            // 系统登录好、退出、回到前台时都会再调这个
            GKLocalPlayer.local.authenticateHandler = { controller, error in
                Task { @MainActor in GameCenter.shared.answered(controller, error) }
            }
        }
    }

    private func answered(_ controller: UIViewController?, _ error: Error?) {
        if let controller {
            UIApplication.topController?.present(controller, animated: true)
            return
        }
        asking = .answered
        signedIn = GKLocalPlayer.local.isAuthenticated
        problem = signedIn ? nil : (error.map(Self.explain) ?? Self.notSignedIn)
        if signedIn { GKLocalPlayer.local.register(GomokuTurns.shared) }
        let resumed = waiters
        waiters = []
        for waiter in resumed { waiter.resume(returning: signedIn) }
    }

    nonisolated static let notSignedIn = "还没登录 Game Center：在手机「设置 › Game Center」里登录自己的 Apple ID，再回来"

    nonisolated static func explain(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == GKErrorDomain else { return "连接出错了：\(error.localizedDescription)" }
        switch GKError.Code(rawValue: nsError.code) {
        case .notAuthenticated?, .notAuthorized?: return notSignedIn
        case .gameUnrecognized?: return "Game Center 还不认这个 App（刚打开 Game Center 要等一会儿，过一阵再试）"
        case .cancelled?: return "取消了"
        case .notSupported?: return "这台手机不支持 Game Center"
        case .communicationsFailure?, .connectionTimeout?: return "连不上 Game Center：看看网络"
        default: return "Game Center 出错了：\(error.localizedDescription)"
        }
    }
}

extension UIApplication {
    /// 最上面那一层（系统登录页等从它上面弹出来）
    @MainActor static var topController: UIViewController? {
        var top = shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - 房间

/// 一个联机房间：几台手机连在一起，谁在、谁是房主由房间管，游戏自己的消息原样送到每个人。
/// - 面对面：身边的手机直接连（Wi-Fi、蓝牙，不用联网、不用账号）。一个人开房间，别人在附近的房间里点一下加入；
///   加入的人只连房主，消息先发给房主，房主转给别人。
/// - 远程：大家输同一个房间号，Game Center 把人凑齐了连在一起（要联网、登录 Game Center）；房主是编号最小的那个
@MainActor
final class GameRoom: NSObject, ObservableObject {
    enum Mode: Equatable {
        case nearbyHost, nearbyGuest, remote(code: Int)
    }

    enum Phase: Equatable {
        case idle
        /// 房主等人进来；远程在配对
        case waiting
        /// 加入的人在找附近的房间
        case browsing
        case joining(String)
        /// 在房间里了，人到了
        case ready
        /// 房间没了（为什么）
        case closed(String)
    }

    struct Member: Codable, Identifiable, Hashable, Sendable {
        var id: String
        var name: String
    }

    /// 附近找到的一个房间
    struct NearbyRoom: Identifiable, Equatable {
        let id: String
        let name: String
        fileprivate let peer: MCPeerID
    }

    /// Bonjour 服务名（Info.plist 的 NSBonjourServices 里写着 _shift-games._tcp、_shift-games._udp）
    static let service = "shift-games"

    let kind: GameKind
    let mode: Mode
    /// 最多几个人（远程：正好几个人）
    let capacity: Int
    private(set) var me: Member
    @Published private(set) var members: [Member] = []
    @Published private(set) var hostID: String?
    @Published private(set) var phase = Phase.idle
    @Published private(set) var rooms: [NearbyRoom] = []
    @Published var notice: String?
    /// 面对面的房主还让不让新的人进（一局正在打的时候不让）
    var accepting = true
    /// 收到游戏自己的消息（谁发的）
    var onPayload: ((Data, String) -> Void)?
    /// 有人进来、走了
    var onMembersChanged: (() -> Void)?

    var isHost: Bool { hostID == me.id }
    var others: [Member] { members.filter { $0.id != me.id } }

    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    /// 加入的人：要进 / 已经进的那个房间的房主
    private var hostPeer: MCPeerID?
    /// 房主：每台连上的手机是房间里的谁
    private var memberOfPeer: [MCPeerID: String] = [:]
    private var match: GKMatch?

    private enum Envelope: Codable {
        case hello(Member)
        case lobby(members: [Member], host: String)
        case payload(from: String, data: Data)
    }

    init(kind: GameKind, mode: Mode, name: String, capacity: Int) {
        self.kind = kind
        self.mode = mode
        self.capacity = capacity
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12))
        me = Member(id: String(UUID().uuidString.prefix(8)), name: trimmed.isEmpty ? "我" : trimmed)
        super.init()
    }

    var code: Int? {
        if case .remote(let code) = mode { return code }
        return nil
    }

    /// 开始：开房间、找房间或配对（关掉一局回来再调也没事）
    func start() {
        guard phase == .idle else { return }
        members = [me]
        switch mode {
        case .nearbyHost:
            let session = makeSession()
            let advertiser = MCNearbyServiceAdvertiser(peer: session.myPeerID, discoveryInfo: ["name": me.name, "game": kind.rawValue],
                                                       serviceType: Self.service)
            advertiser.delegate = self
            advertiser.startAdvertisingPeer()
            self.advertiser = advertiser
            hostID = me.id
            phase = .waiting
        case .nearbyGuest:
            let session = makeSession()
            let browser = MCNearbyServiceBrowser(peer: session.myPeerID, serviceType: Self.service)
            browser.delegate = self
            browser.startBrowsingForPeers()
            self.browser = browser
            phase = .browsing
        case .remote(let code):
            phase = .waiting
            Task { await findRemote(code: code) }
        }
    }

    func leave() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        if case .remote = mode {
            if match == nil { GKMatchmaker.shared().cancel() }
            match?.disconnect()
            match = nil
        }
        onPayload = nil
        onMembersChanged = nil
    }

    /// 加入附近的一个房间
    func join(_ room: NearbyRoom) {
        guard phase == .browsing, let session else { return }
        hostPeer = room.peer
        notice = nil
        phase = .joining(room.name)
        let hello = try? JSONEncoder().encode(Envelope.hello(me))
        browser?.invitePeer(room.peer, to: session, withContext: hello, timeout: 20)
    }

    /// 发一条游戏消息给房间里所有别的人
    func send(_ data: Data) {
        let envelope = Envelope.payload(from: me.id, data: data)
        switch mode {
        case .nearbyHost:
            deliver(envelope, to: session?.connectedPeers ?? [])
        case .nearbyGuest:
            deliver(envelope, to: hostPeer.map { [$0] } ?? [])
        case .remote:
            guard let match, let encoded = try? JSONEncoder().encode(envelope) else { return }
            try? match.sendData(toAllPlayers: encoded, with: .reliable)
        }
    }

    // MARK: 面对面

    private func makeSession() -> MCSession {
        let session = MCSession(peer: MCPeerID(displayName: me.name), securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        return session
    }

    private func deliver(_ envelope: Envelope, to peers: [MCPeerID]) {
        guard let session, !peers.isEmpty, let data = try? JSONEncoder().encode(envelope) else { return }
        try? session.send(data, toPeers: peers, with: .reliable)
    }

    private func received(_ envelope: Envelope, from peer: MCPeerID) {
        switch envelope {
        case .hello(let member):
            guard mode == .nearbyHost else { return }
            memberOfPeer[peer] = member.id
            if !members.contains(where: { $0.id == member.id }) { members.append(member) }
            phase = .ready
            deliver(.lobby(members: members, host: me.id), to: session?.connectedPeers ?? [])
            onMembersChanged?()
        case .lobby(let list, let host):
            guard mode == .nearbyGuest, peer == hostPeer else { return }
            members = list
            hostID = host
            phase = .ready
            onMembersChanged?()
        case .payload(let from, let data):
            // 房主把别人的消息转给其他人
            if mode == .nearbyHost {
                deliver(envelope, to: (session?.connectedPeers ?? []).filter { $0 != peer })
            }
            onPayload?(data, from)
        }
    }

    private func peerChanged(_ peer: MCPeerID, connected: Bool) {
        switch mode {
        case .nearbyHost:
            guard !connected, let id = memberOfPeer.removeValue(forKey: peer) else { return }
            members.removeAll { $0.id == id }
            if members.count < 2 { phase = .waiting }
            deliver(.lobby(members: members, host: me.id), to: session?.connectedPeers ?? [])
            onMembersChanged?()
        case .nearbyGuest:
            guard peer == hostPeer else { return }
            if connected {
                browser?.stopBrowsingForPeers()
                deliver(.hello(me), to: [peer])
            } else if phase == .ready {
                hostPeer = nil
                members = [me]
                phase = .closed("和房主断开了：房主可能退出了，或者离得太远")
                onMembersChanged?()
            } else {
                hostPeer = nil
                phase = .browsing
                notice = "没进去：房间里可能正在玩、或者满了，等一会再点"
            }
        case .remote:
            break
        }
    }

    // MARK: 远程

    private func findRemote(code: Int) async {
        guard await GameCenter.shared.signIn() else {
            phase = .closed(GameCenter.shared.problem ?? GameCenter.notSignedIn)
            return
        }
        me = Member(id: GKLocalPlayer.local.gamePlayerID, name: GKLocalPlayer.local.displayName)
        members = [me]
        let request = GKMatchRequest()
        request.minPlayers = capacity
        request.maxPlayers = capacity
        request.playerGroup = kind.index * 100_000 + code
        do {
            let match = try await GKMatchmaker.shared().findMatch(for: request)
            self.match = match
            match.delegate = self
            remoteChanged()
        } catch {
            phase = .closed(GameCenter.explain(error))
        }
    }

    private func remoteChanged() {
        guard let match else { return }
        members = [me] + match.players.map { Member(id: $0.gamePlayerID, name: $0.displayName) }
        hostID = members.map(\.id).min()
        if members.count >= 2, match.expectedPlayerCount == 0 {
            phase = .ready
        } else if phase == .ready, members.count < 2 {
            phase = .closed("对方断开了")
        }
        onMembersChanged?()
    }
}

// MARK: - 系统回调（在后台线程上来，转回主线程处理）

extension GameRoom: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        guard state != .connecting else { return }
        let connected = state == .connected
        Task { @MainActor in self.peerChanged(peerID, connected: connected) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return }
        Task { @MainActor in self.received(envelope, from: peerID) }
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

extension GameRoom: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let hello = context.flatMap { try? JSONDecoder().decode(Envelope.self, from: $0) }
        Task { @MainActor in
            let accept = self.accepting && self.members.count < self.capacity
            if accept, case .hello(let member)? = hello { self.memberOfPeer[peerID] = member.id }
            invitationHandler(accept, accept ? self.session : nil)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in self.notice = "开不了房间：在系统设置里允许「值班提醒」使用本地网络，再打开 Wi-Fi 或蓝牙" }
    }
}

extension GameRoom: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let name = info?["name"] ?? peerID.displayName
        let game = info?["game"]
        Task { @MainActor in
            guard game == self.kind.rawValue else { return }
            let room = NearbyRoom(id: "\(peerID.hash)", name: name, peer: peerID)
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

extension GameRoom: GKMatchDelegate {
    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              case .payload(let from, let body) = envelope else { return }
        Task { @MainActor in self.onPayload?(body, from) }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        Task { @MainActor in self.remoteChanged() }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: Error?) {
        let reason = error.map { GameCenter.explain($0) } ?? "连接断了"
        Task { @MainActor in self.phase = .closed(reason) }
    }
}
