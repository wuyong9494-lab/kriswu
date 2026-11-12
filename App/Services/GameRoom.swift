@preconcurrency import GameKit
@preconcurrency import MultipeerConnectivity
import UIKit

/// 小游戏的种类：联机时用来分开（星了个星的房间不会和五子棋的连到一起）
enum GameKind: String, Codable, Sendable {
    case tiles, gomoku, arena, fighter

    /// Game Center 配对分组用的编号
    var index: Int {
        switch self {
        case .tiles: return 1
        case .gomoku: return 2
        case .arena: return 3
        case .fighter: return 4
        }
    }

    var title: String {
        switch self {
        case .tiles: return "星了个星"
        case .gomoku: return "五子棋"
        case .arena: return "勇者乱斗"
        case .fighter: return "双人格斗"
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

/// Game Center's callbacks may finish after cancellation. Keep each startup's
/// lifetime separate, including ownership of the process-wide matchmaker.
/// The generic result also lets lifecycle tests run without signing in.
@MainActor
final class GameRoomRemoteStartup {
    private static weak var currentStartup: GameRoomRemoteStartup?
    private static var matchmakingOwner: UUID?
    private var generation: UUID?
    private var task: Task<Void, Never>?
    private let cancelMatchmaking: () -> Void

    init(cancelMatchmaking: @escaping () -> Void) {
        self.cancelMatchmaking = cancelMatchmaking
    }

    @discardableResult
    func start<Match>(signIn: @escaping @MainActor () async -> Bool,
                      findMatch: @escaping @MainActor () async throws -> Match,
                      accept: @escaping @MainActor (Match) -> Void,
                      discard: @escaping @MainActor (Match) -> Void,
                      failed: @escaping @MainActor (Error?) -> Void) -> Task<Void, Never> {
        // Reserve the latest startup before authentication can suspend. Retire
        // the old search before the new one can reach the shared matchmaker.
        Self.currentStartup?.cancel()
        cancel()
        let generation = UUID()
        self.generation = generation
        Self.currentStartup = self
        let task = Task { [weak self] in
            guard self?.isCurrent(generation) == true else { return }
            let signedIn = await signIn()
            guard self?.isCurrent(generation) == true else { return }
            guard signedIn else {
                self?.finish(generation)
                failed(nil)
                return
            }
            Self.matchmakingOwner = generation
            do {
                let match = try await findMatch()
                let current = self?.isCurrent(generation) == true && Self.matchmakingOwner == generation
                if Self.matchmakingOwner == generation { Self.matchmakingOwner = nil }
                self?.finish(generation)
                guard current else {
                    discard(match)
                    return
                }
                accept(match)
            } catch {
                let current = self?.isCurrent(generation) == true && Self.matchmakingOwner == generation
                if Self.matchmakingOwner == generation { Self.matchmakingOwner = nil }
                self?.finish(generation)
                if current { failed(error) }
            }
        }
        self.task = task
        return task
    }

    func cancel() {
        let retired = generation
        generation = nil
        task?.cancel()
        task = nil
        if Self.currentStartup === self { Self.currentStartup = nil }
        // A retired room must not cancel a newer room's shared search, or a
        // search it never started because authentication is still pending.
        if let retired, Self.matchmakingOwner == retired {
            Self.matchmakingOwner = nil
            cancelMatchmaking()
        }
    }

    private func isCurrent(_ generation: UUID) -> Bool {
        self.generation == generation && Self.currentStartup === self && !Task.isCancelled
    }

    private func finish(_ generation: UUID) {
        guard self.generation == generation else { return }
        self.generation = nil
        task = nil
        if Self.currentStartup === self { Self.currentStartup = nil }
    }
}

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
    /// 收到只在房主和每个人之间来回、不转发的消息（乱斗的摇杆、画面）
    var onDirect: ((Data, String) -> Void)?
    /// Opt-in direct channel bound to the current transport peer, not a sender
    /// string supplied by the packet. New authoritative protocols use this.
    /// Existing game callbacks remain unchanged during incremental migration.
    var onAuthenticatedDirect: ((Data, String) -> Void)? {
        didSet { authenticatedDirectOwner = nil }
    }
    private var authenticatedDirectOwner: UUID?

    /// Direct assignment invalidates ownership synchronously, even while an old
    /// callback is executing. A retiring consumer cannot erase its successor.
    func installAuthenticatedDirect(owner: UUID, callback: @escaping (Data, String) -> Void) -> Bool {
        guard onAuthenticatedDirect == nil else { return false }
        onAuthenticatedDirect = callback
        authenticatedDirectOwner = owner
        return true
    }

    func ownsAuthenticatedDirect(_ owner: UUID) -> Bool { authenticatedDirectOwner == owner }

    func removeAuthenticatedDirect(owner: UUID) {
        guard authenticatedDirectOwner == owner else { return }
        onAuthenticatedDirect = nil
    }
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
    private var directIdentities = GameRoomDirectIdentity<MCPeerID>()
    private var match: GKMatch?
    private var fighterRemoteTerminal = false
    private let remoteStartup = GameRoomRemoteStartup(cancelMatchmaking: { GKMatchmaker.shared().cancel() })

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

    #if DEBUG
    /// Offline UI fixture; never starts advertising, browsing, or Game Center.
    static func arenaPreview(waiting: Bool) -> GameRoom {
        precondition(ProcessInfo.processInfo.arguments.contains("-demo"))
        let room = GameRoom(kind: .arena, mode: waiting ? .remote(code: 3123) : .nearbyHost,
                            name: "队长", capacity: 6)
        room.phase = waiting ? .waiting : .ready
        room.hostID = room.me.id
        room.members = [room.me, Member(id: "preview-guest", name: "游侠队友")]
        return room
    }
    #endif

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
            findRemote(code: code)
        }
    }

    func leave() {
        if kind == .fighter, case .remote = mode { fighterRemoteTerminal = true }
        remoteStartup.cancel()
        advertiser?.delegate = nil
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.delegate = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        session?.delegate = nil
        session?.disconnect()
        session = nil
        match?.delegate = nil
        match?.disconnect()
        match = nil
        hostPeer = nil
        memberOfPeer.removeAll()
        onPayload = nil
        onDirect = nil
        onAuthenticatedDirect = nil
        directIdentities.removeAll()
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

    enum Delivery { case reliable, unreliable }

    /// 不转发的消息：房主发给所有人，别人只发给房主。unreliable 的快、丢了不补（每秒几十次的摇杆、画面用）
    func sendDirect(_ data: Data, delivery: Delivery = .reliable) {
        if kind == .fighter, case .remote = mode {
            guard !fighterRemoteTerminal else { return }
            if case .closed = phase { return }
        }
        var packet = Data([Self.directMarker, UInt8(clamping: me.id.utf8.count)])
        packet.append(contentsOf: Array(me.id.utf8))
        packet.append(data)
        switch mode {
        case .nearbyHost, .nearbyGuest:
            guard let session else { return }
            let peers = mode == .nearbyHost ? session.connectedPeers : hostPeer.map { [$0] } ?? []
            guard !peers.isEmpty else { return }
            try? session.send(packet, toPeers: peers, with: delivery == .reliable ? .reliable : .unreliable)
        case .remote:
            guard let match else { return }
            let players = isHost ? match.players : match.players.filter { $0.gamePlayerID == hostID }
            guard !players.isEmpty else { return }
            do {
                try match.send(packet, to: players, dataMode: delivery == .reliable ? .reliable : .unreliable)
            } catch {
                // Complete replay cannot silently drop a reliable input/frame.
                // Preserve legacy games' behavior; only the trusted fighter
                // channel treats a failed send as terminal.
                if delivery == .reliable { fighterRemoteSendFailed() }
            }
        }
    }

    /// 不转发的消息开头的一个字节（JSON 的消息开头是「{」）
    nonisolated static let directMarker: UInt8 = 0xD1

    /// 拆开不转发的消息：谁发的、内容
    nonisolated static func direct(_ packet: Data) -> (from: String, data: Data)? {
        let bytes = [UInt8](packet)
        guard bytes.count >= 2, bytes[0] == directMarker, bytes.count >= 2 + Int(bytes[1]) else { return nil }
        let length = Int(bytes[1])
        guard let from = String(bytes: bytes[2..<(2 + length)], encoding: .utf8) else { return nil }
        return (from, Data(bytes[(2 + length)...]))
    }

    /// Reject identity claims that do not match the live transport binding.
    /// Nearby IDs are room-scoped identities, not verified real-world accounts.
    nonisolated static func validatedDirectSender(claimed: String, transport: String?,
                                                  local: String, memberIDs: [String]) -> String? {
        guard let transport, !transport.isEmpty, claimed == transport,
              transport != local, memberIDs.filter({ $0 == transport }).count == 1 else { return nil }
        return transport
    }

    private func receiveAuthenticatedDirect(_ direct: (from: String, data: Data),
                                            peer: MCPeerID, sessionID: ObjectIdentifier) {
        guard phase == .ready, let session, ObjectIdentifier(session) == sessionID,
              session.connectedPeers.contains(peer) else { return }
        let transportID: String?
        switch mode {
        case .nearbyHost: transportID = directIdentities.identity(for: peer)
        case .nearbyGuest: transportID = peer == hostPeer ? directIdentities.identity(for: peer) : nil
        case .remote: return
        }
        guard let sender = Self.validatedDirectSender(claimed: direct.from, transport: transportID,
                                                      local: me.id, memberIDs: members.map(\.id)) else { return }
        onAuthenticatedDirect?(direct.data, sender)
    }

    private func receiveAuthenticatedDirect(_ direct: (from: String, data: Data),
                                            playerID: String, matchID: ObjectIdentifier) {
        guard phase == .ready, let match, ObjectIdentifier(match) == matchID,
              match.players.contains(where: { $0.gamePlayerID == playerID }),
              isHost || playerID == hostID,
              let sender = Self.validatedDirectSender(claimed: direct.from, transport: playerID,
                                                      local: me.id, memberIDs: members.map(\.id)) else { return }
        onAuthenticatedDirect?(direct.data, sender)
    }

    // MARK: 面对面

    private func makeSession() -> MCSession {
        let session = MCSession(peer: MCPeerID(displayName: me.name), securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        return session
    }

    #if DEBUG
    /// Exercise the production session/delegate without discovery, invitations,
    /// connected peers or Game Center. Does not manufacture authenticated peers.
    func testingMakeNearbySession() -> MCSession {
        precondition(code == nil)
        return makeSession()
    }
    #endif

    private func deliver(_ envelope: Envelope, to peers: [MCPeerID]) {
        guard let session, !peers.isEmpty, let data = try? JSONEncoder().encode(envelope) else { return }
        try? session.send(data, toPeers: peers, with: .reliable)
    }

    private func received(_ envelope: Envelope, from peer: MCPeerID) {
        switch envelope {
        case .hello(let member):
            guard mode == .nearbyHost else { return }
            directIdentities.bind(peer, to: member.id, localID: me.id)
            memberOfPeer[peer] = member.id
            if !members.contains(where: { $0.id == member.id }) { members.append(member) }
            phase = .ready
            deliver(.lobby(members: members, host: me.id), to: session?.connectedPeers ?? [])
            onMembersChanged?()
        case .lobby(let list, let host):
            guard mode == .nearbyGuest, peer == hostPeer else { return }
            directIdentities.bind(peer, to: host, localID: me.id)
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
        if !connected { directIdentities.remove(peer) }
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

    private func fighterRemoteDisconnected(playerID: String) {
        guard kind == .fighter, case .remote = mode, !fighterRemoteTerminal, phase == .ready,
              playerID != me.id, members.contains(where: { $0.id == playerID }) else { return }
        fighterRemoteTerminal = true // Reserve terminal state before @Published willSet reentry.
        phase = .closed("对方断开了，联机对战已停止，请重新进入房间。")
        onMembersChanged?()
    }

    private func fighterRemoteSendFailed() {
        guard kind == .fighter, case .remote = mode, !fighterRemoteTerminal, phase == .ready,
              authenticatedDirectOwner != nil else { return }
        fighterRemoteTerminal = true
        phase = .closed("可靠联机消息发送失败，对战已停止，请重新进入房间。")
        onMembersChanged?()
    }

    #if DEBUG
    // Offline policy seam only: never fabricates a GKMatch or delivers packets.
    func testingRemoteMembers(_ players: [Member], expectedPlayerCount: Int) {
        precondition(code != nil)
        applyRemoteMembers(players, expectedPlayerCount: expectedPlayerCount)
    }
    func testingRemoteDisconnected(playerID: String) { fighterRemoteDisconnected(playerID: playerID) }
    func testingRemoteReliableSendFailure() { fighterRemoteSendFailed() }
    #endif

    private func findRemote(code: Int) {
        let request = GKMatchRequest()
        request.minPlayers = capacity
        request.maxPlayers = capacity
        request.playerGroup = kind.index * 100_000 + code
        remoteStartup.start(signIn: { await GameCenter.shared.signIn() }, findMatch: { [weak self] in
            guard let self else { throw CancellationError() }
            self.me = Member(id: GKLocalPlayer.local.gamePlayerID, name: GKLocalPlayer.local.displayName)
            self.members = [self.me]
            return try await GKMatchmaker.shared().findMatch(for: request)
        }, accept: { [weak self] match in
            guard let self else { match.disconnect(); return }
            self.match = match
            match.delegate = self
            self.remoteChanged()
        }, discard: { match in
            match.disconnect()
        }, failed: { [weak self] error in
            self?.phase = .closed(error.map(GameCenter.explain) ?? GameCenter.shared.problem ?? GameCenter.notSignedIn)
        })
    }

    private func remoteChanged() {
        guard let match else { return }
        applyRemoteMembers(match.players.map { Member(id: $0.gamePlayerID, name: $0.displayName) },
                           expectedPlayerCount: match.expectedPlayerCount)
    }

    private func applyRemoteMembers(_ players: [Member], expectedPlayerCount: Int) {
        // A late connected notification must never resurrect a failed fighter
        // room or elect a replacement host after combat started.
        if kind == .fighter {
            guard !fighterRemoteTerminal else { return }
            if case .closed = phase { return }
        }
        members = [me] + players
        if kind == .fighter {
            guard !fighterRemoteTerminal else { return }
            if case .closed = phase { return }
        }
        hostID = members.map(\.id).min()
        if kind == .fighter {
            guard !fighterRemoteTerminal else { return }
            if case .closed = phase { return }
        }
        if members.count >= 2, expectedPlayerCount == 0 {
            phase = .ready
            // A ready willSet observer may synchronously leave. The outer
            // assignment must not leave a terminated room looking usable.
            if kind == .fighter, fighterRemoteTerminal {
                phase = .closed("房间已离开，请重新进入。")
                return
            }
        } else if phase == .ready, members.count < 2 {
            if kind == .fighter { fighterRemoteTerminal = true }
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
        let sessionID = ObjectIdentifier(session)
        Task { @MainActor in
            guard let current = self.session, ObjectIdentifier(current) == sessionID else { return }
            self.peerChanged(peerID, connected: connected)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let direct = GameRoom.direct(data) {
            let sessionID = ObjectIdentifier(session)
            Task { @MainActor in
                guard let current = self.session, ObjectIdentifier(current) == sessionID else { return }
                self.receiveAuthenticatedDirect(direct, peer: peerID, sessionID: sessionID)
                guard self.session === current else { return }
                self.onDirect?(direct.data, direct.from)
            }
            return
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return }
        let sessionID = ObjectIdentifier(session)
        Task { @MainActor in
            guard let current = self.session, ObjectIdentifier(current) == sessionID else { return }
            self.received(envelope, from: peerID)
        }
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
        let advertiserID = ObjectIdentifier(advertiser)
        // Keep Apple's non-Sendable completion on the delegate's calling thread.
        // Only the synchronous room-state decision runs on the main actor.
        let acceptedSession: MCSession?
        if Thread.isMainThread {
            acceptedSession = MainActor.assumeIsolated {
                self.acceptInvitation(from: peerID, hello: hello, advertiserID: advertiserID)
            }
        } else {
            acceptedSession = DispatchQueue.main.sync {
                self.acceptInvitation(from: peerID, hello: hello, advertiserID: advertiserID)
            }
        }
        invitationHandler(acceptedSession != nil, acceptedSession)
    }

    private func acceptInvitation(from peerID: MCPeerID, hello: Envelope?, advertiserID: ObjectIdentifier) -> MCSession? {
        guard let advertiser, ObjectIdentifier(advertiser) == advertiserID,
              accepting, members.count < capacity, let session else { return nil }
        if case .hello(let member)? = hello { memberOfPeer[peerID] = member.id }
        return session
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        let advertiserID = ObjectIdentifier(advertiser)
        Task { @MainActor in
            guard let current = self.advertiser, ObjectIdentifier(current) == advertiserID else { return }
            self.notice = "开不了房间：在系统设置里允许「值班提醒」使用本地网络，再打开 Wi-Fi 或蓝牙"
        }
    }
}

extension GameRoom: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let name = info?["name"] ?? peerID.displayName
        let game = info?["game"]
        let browserID = ObjectIdentifier(browser)
        Task { @MainActor in
            guard let current = self.browser, ObjectIdentifier(current) == browserID,
                  game == self.kind.rawValue else { return }
            let room = NearbyRoom(id: "\(peerID.hash)", name: name, peer: peerID)
            self.rooms.removeAll { $0.id == room.id }
            self.rooms.append(room)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let browserID = ObjectIdentifier(browser)
        Task { @MainActor in
            guard let current = self.browser, ObjectIdentifier(current) == browserID else { return }
            self.rooms.removeAll { $0.peer == peerID }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        let browserID = ObjectIdentifier(browser)
        Task { @MainActor in
            guard let current = self.browser, ObjectIdentifier(current) == browserID else { return }
            self.notice = "找不了房间：在系统设置里允许「值班提醒」使用本地网络，再打开 Wi-Fi 或蓝牙"
        }
    }
}

extension GameRoom: GKMatchDelegate {
    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        let matchID = ObjectIdentifier(match)
        if let direct = GameRoom.direct(data) {
            let playerID = player.gamePlayerID
            Task { @MainActor in
                guard let current = self.match, ObjectIdentifier(current) == matchID else { return }
                self.receiveAuthenticatedDirect(direct, playerID: playerID, matchID: matchID)
                guard self.match === current else { return }
                self.onDirect?(direct.data, direct.from)
            }
            return
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              case .payload(let from, let body) = envelope else { return }
        Task { @MainActor in
            guard let current = self.match, ObjectIdentifier(current) == matchID else { return }
            self.onPayload?(body, from)
        }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        let matchID = ObjectIdentifier(match)
        let playerID = player.gamePlayerID
        let disconnected = state == .disconnected
        Task { @MainActor in
            guard let current = self.match, ObjectIdentifier(current) == matchID else { return }
            if disconnected { self.fighterRemoteDisconnected(playerID: playerID) }
            self.remoteChanged()
        }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: Error?) {
        let reason = error.map { GameCenter.explain($0) } ?? "连接断了"
        let matchID = ObjectIdentifier(match)
        Task { @MainActor in
            guard let current = self.match, ObjectIdentifier(current) == matchID else { return }
            if self.kind == .fighter {
                guard !self.fighterRemoteTerminal else { return }
                self.fighterRemoteTerminal = true
            }
            self.phase = .closed(reason)
        }
    }
}
