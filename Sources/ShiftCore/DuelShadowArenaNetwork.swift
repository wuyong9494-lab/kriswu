import Foundation

/// Deterministic host-authoritative 2-player multiplayer protocol & state machine
/// for the 4-hero Shadow Arena runtime (Wu Yong, Liu Quanwei, Xu Xiao, Sun Deng).
/// Works identically over Nearby MultipeerConnectivity and Game Center remote rooms
/// without depending on the legacy 707 FighterPrivate catalog.
public enum DuelShadowArenaNetworkProtocol {
    public static let protocolVersion: Int = 1
    public static let rulesVersion: UInt16 = DuelReplayStateEncoding.rulesVersion
    public static let maximumPacketBytes: Int = 16_384
    public static let maximumFramesPerBatch: Int = 8
    public static let checksumIntervalTicks: UInt64 = 30
}

public enum DuelShadowArenaNetworkPacket: Codable, Equatable, Sendable {
    public struct Frame: Codable, Equatable, Sendable {
        public let host: DuelGame.Input
        public let guest: DuelGame.Input

        public init(host: DuelGame.Input, guest: DuelGame.Input) {
            self.host = host
            self.guest = guest
        }
    }

    public struct Checksum: Codable, Equatable, Sendable {
        public let tick: UInt64
        public let hostX: Int
        public let guestX: Int
        public let hostHealth: Int
        public let guestHealth: Int
        public let wins: [Int]

        public init(tick: UInt64, game: DuelGame) {
            self.tick = tick
            hostX = game.fighters.first?.x ?? 0
            guestX = game.fighters.count > 1 ? game.fighters[1].x : 0
            hostHealth = game.fighters.first?.health ?? 0
            guestHealth = game.fighters.count > 1 ? game.fighters[1].health : 0
            wins = game.wins
        }
    }

    case hello(protocolVersion: Int, rulesVersion: UInt16, assetDigest: String, hero: DuelGame.Hero)
    case select(hero: DuelGame.Hero, ready: Bool)
    case start(matchID: String, seed: UInt64, hostHero: DuelGame.Hero, guestHero: DuelGame.Hero)
    case guestInput(matchID: String, sequence: UInt64, input: DuelGame.Input)
    case hostFrames(matchID: String, startTick: UInt64, frames: [Frame], checksum: Checksum?)
    case rematchRequest(matchID: String)
    case returnToLobby(matchID: String)
    case cancel(reason: String)

    public func encoded() throws -> Data {
        let data = try JSONEncoder().encode(self)
        guard data.count <= DuelShadowArenaNetworkProtocol.maximumPacketBytes else {
            throw DuelShadowArenaNetworkSession.Failure.packetTooLarge
        }
        return data
    }

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= DuelShadowArenaNetworkProtocol.maximumPacketBytes else {
            throw DuelShadowArenaNetworkSession.Failure.packetTooLarge
        }
        return try JSONDecoder().decode(Self.self, from: data)
    }
}

/// Pure, transport-agnostic Shadow Arena 1v1 multiplayer session state machine.
/// Host runs authoritative 60 Hz simulation (`DuelGame.step(host, opponent: guest)`)
/// and streams confirmed input frames + periodic state checksums to Guest, which
/// replays the exact same ticks deterministically with zero bot takeover.
public struct DuelShadowArenaNetworkSession: Equatable, Sendable {
    public enum Role: Equatable, Sendable { case host, guest }

    public enum Phase: Equatable, Sendable {
        case lobby
        case playing(matchID: String)
        case finished(matchID: String, winner: Int)
        case closed(reason: String)
    }

    public enum Failure: Error, Equatable, Sendable {
        case packetTooLarge
        case notHost
        case notInLobby
        case peerNotCompatible
        case playersNotReady
        case invalidBatch
    }

    public struct Seat: Equatable, Sendable {
        public let playerID: String
        public var hero: DuelGame.Hero
        public var ready: Bool
        public var greeted: Bool

        public init(playerID: String, hero: DuelGame.Hero, ready: Bool = false, greeted: Bool = false) {
            self.playerID = playerID
            self.hero = hero
            self.ready = ready
            self.greeted = greeted
        }
    }

    public struct HostAdvanceResult: Equatable, Sendable {
        public let steps: [(DuelGame, UInt64)]
        public let packet: DuelShadowArenaNetworkPacket?

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.packet == rhs.packet
                && lhs.steps.count == rhs.steps.count
                && zip(lhs.steps, rhs.steps).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        }
    }

    public struct ReceiveResult: Equatable, Sendable {
        public let applied: Bool
        public let steps: [(DuelGame, UInt64)]
        public let outgoing: [DuelShadowArenaNetworkPacket]
        public let matchStarted: Bool
        public let returnedToLobby: Bool

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.applied == rhs.applied
                && lhs.outgoing == rhs.outgoing
                && lhs.matchStarted == rhs.matchStarted
                && lhs.returnedToLobby == rhs.returnedToLobby
                && lhs.steps.count == rhs.steps.count
                && zip(lhs.steps, rhs.steps).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        }

        public static let ignored = ReceiveResult(
            applied: false, steps: [], outgoing: [], matchStarted: false, returnedToLobby: false
        )
    }

    public let role: Role
    public let localPlayerID: String
    public let hostID: String
    public let guestID: String
    public let localAssetDigest: String
    public private(set) var peerCompatible: Bool = false
    public private(set) var incompatibilityReason: String?
    public private(set) var hostSeat: Seat
    public private(set) var guestSeat: Seat
    public private(set) var phase: Phase = .lobby
    public private(set) var activeMatchID: String?
    public private(set) var activeSeed: UInt64 = 0
    public private(set) var game: DuelGame?
    public private(set) var nextTick: UInt64 = 0
    public private(set) var rematchVotes: Set<String> = []
    public private(set) var desyncDetected: Bool = false

    private var lastGuestInputSequence: UInt64 = 0
    private var latestGuestHeldInput: DuelGame.Input = .neutral
    private var queuedGuestOneShotTaps: DuelGame.Buttons = []
    private var queuedGuestCommand: DuelWeaponCommand?
    private var queuedGuestDashDirection: Int = 0
    private var localGuestSequence: UInt64 = 0
    private var rematchCounter: UInt64 = 0

    public var localSeatIndex: Int { role == .host ? 0 : 1 }
    public var localSeat: Seat { role == .host ? hostSeat : guestSeat }
    public var peerSeat: Seat { role == .host ? guestSeat : hostSeat }
    public var canStartMatch: Bool {
        role == .host && phase == .lobby && peerCompatible && hostSeat.ready && guestSeat.ready
    }

    public init(role: Role, localPlayerID: String, hostID: String, guestID: String,
                localAssetDigest: String, initialHero: DuelGame.Hero = .wuYong) {
        self.role = role
        self.localPlayerID = localPlayerID
        self.hostID = hostID
        self.guestID = guestID
        self.localAssetDigest = localAssetDigest
        self.hostSeat = Seat(playerID: hostID, hero: role == .host ? initialHero : .wuYong, greeted: role == .host)
        self.guestSeat = Seat(playerID: guestID, hero: role == .guest ? initialHero : .liu, greeted: role == .guest)
    }

    public func makeHelloPacket() -> DuelShadowArenaNetworkPacket {
        .hello(
            protocolVersion: DuelShadowArenaNetworkProtocol.protocolVersion,
            rulesVersion: DuelShadowArenaNetworkProtocol.rulesVersion,
            assetDigest: localAssetDigest,
            hero: localSeat.hero
        )
    }

    public mutating func setLocalHero(_ hero: DuelGame.Hero) -> DuelShadowArenaNetworkPacket? {
        guard phase == .lobby else { return nil }
        if role == .host {
            hostSeat.hero = hero
            hostSeat.ready = false
        } else {
            guestSeat.hero = hero
            guestSeat.ready = false
        }
        return .select(hero: hero, ready: false)
    }

    public mutating func setLocalReady(_ ready: Bool) -> DuelShadowArenaNetworkPacket? {
        guard phase == .lobby else { return nil }
        if role == .host {
            hostSeat.ready = ready
            return .select(hero: hostSeat.hero, ready: ready)
        } else {
            guestSeat.ready = ready
            return .select(hero: guestSeat.hero, ready: ready)
        }
    }

    public mutating func startMatch(matchID: String, seed: UInt64) throws -> DuelShadowArenaNetworkPacket {
        guard role == .host else { throw Failure.notHost }
        guard phase == .lobby else { throw Failure.notInLobby }
        guard peerCompatible else { throw Failure.peerNotCompatible }
        guard hostSeat.ready && guestSeat.ready else { throw Failure.playersNotReady }
        beginMatch(matchID: matchID, seed: seed, hostHero: hostSeat.hero, guestHero: guestSeat.hero)
        return .start(matchID: matchID, seed: seed, hostHero: hostSeat.hero, guestHero: guestSeat.hero)
    }

    public mutating func makeGuestInputPacket(_ input: DuelGame.Input) -> DuelShadowArenaNetworkPacket? {
        guard role == .guest, case .playing(let matchID) = phase else { return nil }
        localGuestSequence &+= 1
        return .guestInput(matchID: matchID, sequence: localGuestSequence, input: input)
    }

    /// Host advances `count` authoritative 60 Hz ticks. One-shot taps/commands are consumed
    /// only on the first tick of the batch so batched transmission never double-triggers attacks.
    public mutating func advanceHostTicks(count: Int, hostInput: DuelGame.Input) throws -> HostAdvanceResult {
        guard role == .host else { throw Failure.notHost }
        guard (1...DuelShadowArenaNetworkProtocol.maximumFramesPerBatch).contains(count) else {
            throw Failure.invalidBatch
        }
        guard case .playing(let matchID) = phase, var liveGame = game else {
            return HostAdvanceResult(steps: [], packet: nil)
        }

        let startTick = nextTick
        var frames: [DuelShadowArenaNetworkPacket.Frame] = []
        var steps: [(DuelGame, UInt64)] = []
        frames.reserveCapacity(count)
        steps.reserveCapacity(count)

        var currentHost = hostInput
        for _ in 0..<count {
            if case .matchOver = liveGame.phase { break }
            let guestFrameInput = consumeGuestInputForTick()
            liveGame.step(currentHost, opponent: guestFrameInput)
            frames.append(.init(host: currentHost, guest: guestFrameInput))
            steps.append((liveGame, nextTick))
            nextTick &+= 1
            // Strip one-shot triggers after the first tick; keep held movement/guard/heavy charge.
            currentHost.taps = []
            currentHost.weaponCommand = nil
            currentHost.dashDirection = 0
            if case .matchOver(let winner) = liveGame.phase {
                phase = .finished(matchID: matchID, winner: winner)
                break
            }
        }

        game = liveGame
        guard !frames.isEmpty else { return HostAdvanceResult(steps: [], packet: nil) }
        let isMatchOver: Bool
        if case .finished = phase { isMatchOver = true } else { isMatchOver = false }
        let needsChecksum = isMatchOver || (nextTick % DuelShadowArenaNetworkProtocol.checksumIntervalTicks == 0)
        let checksum = needsChecksum ? DuelShadowArenaNetworkPacket.Checksum(tick: nextTick, game: liveGame) : nil
        let packet = DuelShadowArenaNetworkPacket.hostFrames(
            matchID: matchID, startTick: startTick, frames: frames, checksum: checksum
        )
        return HostAdvanceResult(steps: steps, packet: packet)
    }

    public mutating func requestRematch(nextMatchID: String, nextSeed: UInt64) -> [DuelShadowArenaNetworkPacket] {
        guard case .finished(let matchID, _) = phase else { return [] }
        rematchVotes.insert(localPlayerID)
        var out: [DuelShadowArenaNetworkPacket] = [.rematchRequest(matchID: matchID)]
        if role == .host && rematchVotes.contains(hostID) && rematchVotes.contains(guestID) {
            beginMatch(matchID: nextMatchID, seed: nextSeed, hostHero: hostSeat.hero, guestHero: guestSeat.hero)
            out.append(.start(matchID: nextMatchID, seed: nextSeed, hostHero: hostSeat.hero, guestHero: guestSeat.hero))
        }
        return out
    }

    public mutating func requestReturnToLobby() -> DuelShadowArenaNetworkPacket? {
        let matchID: String
        switch phase {
        case .playing(let id), .finished(let id, _): matchID = id
        case .lobby, .closed: return nil
        }
        resetToLobby()
        return .returnToLobby(matchID: matchID)
    }

    public mutating func close(reason: String) -> DuelShadowArenaNetworkPacket? {
        if case .closed = phase { return nil }
        phase = .closed(reason: reason)
        return .cancel(reason: reason)
    }

    public mutating func receive(_ packet: DuelShadowArenaNetworkPacket, from senderID: String,
                                 rematchSeed: UInt64? = nil) -> ReceiveResult {
        if case .closed = phase { return .ignored }
        let expectedPeer = role == .host ? guestID : hostID
        guard senderID == expectedPeer else { return .ignored }

        switch packet {
        case .hello(let proto, let rules, let digest, let hero):
            if role == .host {
                guestSeat.hero = hero
                guestSeat.greeted = true
            } else {
                hostSeat.hero = hero
                hostSeat.greeted = true
            }
            if proto == DuelShadowArenaNetworkProtocol.protocolVersion
                && rules == DuelShadowArenaNetworkProtocol.rulesVersion
                && digest == localAssetDigest {
                peerCompatible = true
                incompatibilityReason = nil
            } else {
                peerCompatible = false
                incompatibilityReason = "双方资源或版本不一致（协议 v\(proto)/规则 r\(rules)），请更新到同一版本后联机。"
            }
            return ReceiveResult(applied: true, steps: [], outgoing: [], matchStarted: false, returnedToLobby: false)

        case .select(let hero, let ready):
            guard phase == .lobby else { return .ignored }
            if role == .host {
                guestSeat.hero = hero
                guestSeat.ready = ready
            } else {
                hostSeat.hero = hero
                hostSeat.ready = ready
            }
            return ReceiveResult(applied: true, steps: [], outgoing: [], matchStarted: false, returnedToLobby: false)

        case .start(let matchID, let seed, let hostHero, let guestHero):
            guard role == .guest, peerCompatible else { return .ignored }
            switch phase {
            case .lobby, .finished:
                hostSeat.hero = hostHero
                guestSeat.hero = guestHero
                beginMatch(matchID: matchID, seed: seed, hostHero: hostHero, guestHero: guestHero)
                return ReceiveResult(applied: true, steps: [], outgoing: [], matchStarted: true, returnedToLobby: false)
            case .playing, .closed:
                return .ignored
            }

        case .guestInput(let matchID, let sequence, let input):
            guard role == .host, case .playing(let liveID) = phase, liveID == matchID else { return .ignored }
            guard sequence > lastGuestInputSequence else { return .ignored }
            lastGuestInputSequence = sequence
            latestGuestHeldInput = DuelGame.Input(
                move: input.move,
                guardHeld: input.guardHeld,
                taps: [],
                vertical: input.vertical,
                weaponCommand: nil,
                rangedHeld: input.rangedHeld,
                heavyHeld: input.heavyHeld,
                dashDirection: 0
            )
            queuedGuestOneShotTaps.formUnion(input.taps)
            if let cmd = input.weaponCommand { queuedGuestCommand = cmd }
            if input.dashDirection != 0 { queuedGuestDashDirection = input.dashDirection }
            return ReceiveResult(applied: true, steps: [], outgoing: [], matchStarted: false, returnedToLobby: false)

        case .hostFrames(let matchID, let startTick, let frames, let checksum):
            guard role == .guest, case .playing(let liveID) = phase, liveID == matchID,
                  var liveGame = game else { return .ignored }
            guard !frames.isEmpty, frames.count <= DuelShadowArenaNetworkProtocol.maximumFramesPerBatch else {
                return .ignored
            }
            // Ignore duplicate retries of already-replayed frame batches.
            if startTick + UInt64(frames.count) <= nextTick { return .ignored }
            guard startTick == nextTick else {
                desyncDetected = true
                phase = .closed(reason: "联机帧序列中断（期望 #\(nextTick)，收到 #\(startTick)），已安全结束对局。")
                return ReceiveResult(applied: false, steps: [], outgoing: [], matchStarted: false, returnedToLobby: false)
            }
            var steps: [(DuelGame, UInt64)] = []
            steps.reserveCapacity(frames.count)
            for frame in frames {
                if case .matchOver = liveGame.phase { break }
                liveGame.step(frame.host, opponent: frame.guest)
                steps.append((liveGame, nextTick))
                nextTick &+= 1
                if case .matchOver(let winner) = liveGame.phase {
                    phase = .finished(matchID: matchID, winner: winner)
                    break
                }
            }
            game = liveGame
            if let checksum {
                let local = DuelShadowArenaNetworkPacket.Checksum(tick: nextTick, game: liveGame)
                if local != checksum {
                    desyncDetected = true
                    phase = .closed(reason: "联机状态校验不一致，已安全终止本局。")
                    return ReceiveResult(applied: false, steps: steps, outgoing: [], matchStarted: false, returnedToLobby: false)
                }
            }
            return ReceiveResult(applied: true, steps: steps, outgoing: [], matchStarted: false, returnedToLobby: false)

        case .rematchRequest(let matchID):
            guard case .finished(let liveID, _) = phase, liveID == matchID else { return .ignored }
            rematchVotes.insert(senderID)
            var out: [DuelShadowArenaNetworkPacket] = []
            var started = false
            if role == .host && rematchVotes.contains(hostID) && rematchVotes.contains(guestID) {
                rematchCounter &+= 1
                let nextID = "m\(rematchCounter)-\(matchID.prefix(8))"
                let seed = rematchSeed ?? (activeSeed &+ 0x9E37_79B9_7F4A_7C15 &+ rematchCounter)
                beginMatch(matchID: nextID, seed: seed, hostHero: hostSeat.hero, guestHero: guestSeat.hero)
                out.append(.start(matchID: nextID, seed: seed, hostHero: hostSeat.hero, guestHero: guestSeat.hero))
                started = true
            }
            return ReceiveResult(applied: true, steps: [], outgoing: out, matchStarted: started, returnedToLobby: false)

        case .returnToLobby(let matchID):
            switch phase {
            case .playing(let id) where id == matchID, .finished(let id, _) where id == matchID:
                resetToLobby()
                return ReceiveResult(applied: true, steps: [], outgoing: [], matchStarted: false, returnedToLobby: true)
            default:
                return .ignored
            }

        case .cancel(let reason):
            phase = .closed(reason: reason.isEmpty ? "对方已退出房间。" : reason)
            return ReceiveResult(applied: true, steps: [], outgoing: [], matchStarted: false, returnedToLobby: false)
        }
    }

    private mutating func beginMatch(matchID: String, seed: UInt64,
                                     hostHero: DuelGame.Hero, guestHero: DuelGame.Hero) {
        activeMatchID = matchID
        activeSeed = seed
        nextTick = 0
        rematchVotes.removeAll()
        desyncDetected = false
        lastGuestInputSequence = 0
        latestGuestHeldInput = .neutral
        queuedGuestOneShotTaps = []
        queuedGuestCommand = nil
        queuedGuestDashDirection = 0
        localGuestSequence = 0
        game = DuelGame(
            hero: hostHero,
            difficulty: .learning,
            mode: .versus,
            seed: seed,
            opponentHero: guestHero,
            ruleset: .shadowArena
        )
        phase = .playing(matchID: matchID)
    }

    private mutating func resetToLobby() {
        activeMatchID = nil
        game = nil
        nextTick = 0
        rematchVotes.removeAll()
        desyncDetected = false
        hostSeat.ready = false
        guestSeat.ready = false
        latestGuestHeldInput = .neutral
        queuedGuestOneShotTaps = []
        queuedGuestCommand = nil
        queuedGuestDashDirection = 0
        phase = .lobby
    }

    private mutating func consumeGuestInputForTick() -> DuelGame.Input {
        var input = latestGuestHeldInput
        input.taps = queuedGuestOneShotTaps
        input.weaponCommand = queuedGuestCommand
        input.dashDirection = queuedGuestDashDirection
        queuedGuestOneShotTaps = []
        queuedGuestCommand = nil
        queuedGuestDashDirection = 0
        return input
    }
}
