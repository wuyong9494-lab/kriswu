import Combine
import QuartzCore
import SwiftUI
import UIKit

/// Drives a real 2-player Shadow Arena 4-hero match over `GameRoom` (both Nearby
/// Wi-Fi/Bluetooth via MultipeerConnectivity and Remote 4-digit Game Center rooms).
@MainActor
final class DuelShadowArenaNetworkRoomModel: ObservableObject {
    @Published private(set) var engine: DuelShadowArenaNetworkSession?
    @Published private(set) var liveSession: DuelSession?
    @Published private(set) var preparingAssets = true
    @Published private(set) var statusMessage = "正在准备本机四位武者联机资源…"
    @Published private(set) var errorMessage: String?
    @Published private(set) var localRematchRequested = false
    @Published private(set) var syncedTicks: UInt64 = 0

    let room: GameRoom
    let nearbyMode: Bool
    private let directOwner = UUID()
    private var assetDigest: String?
    private var startedTransport = false
    private var closed = false
    private var observations = Set<AnyCancellable>()
    private var prepTask: Task<Void, Never>?
    private var matchWarmTask: Task<Void, Never>?
    private var displayLink: CADisplayLink?
    private var lastLinkTimestamp: CFTimeInterval?
    private var stepAccumulator: Double = 0
    private var lastSentGuestInput: DuelGame.Input = .neutral
    private var guestHeartbeatTicks: Int = 0
    private let initialHero: DuelGame.Hero

    @MainActor
    private final class DisplayTarget: NSObject {
        weak var owner: DuelShadowArenaNetworkRoomModel?
        init(_ owner: DuelShadowArenaNetworkRoomModel) { self.owner = owner }
        @objc func tick(_ link: CADisplayLink) { owner?.handleDisplayTick(link.timestamp) }
    }

    init(room: GameRoom, initialHero: DuelGame.Hero = .wuYong) {
        self.room = room
        self.initialHero = initialHero
        switch room.mode {
        case .nearbyHost, .nearbyGuest: nearbyMode = true
        case .remote: nearbyMode = false
        }

        Publishers.CombineLatest3(room.$phase, room.$members, room.$hostID)
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.handleRoomStateChange() }
            }
            .store(in: &observations)
    }

    func begin() {
        guard !closed, !startedTransport, prepTask == nil else { return }
        preparingAssets = true
        statusMessage = "正在校验并预热四位武者资源…"
        prepTask = Task { @MainActor [weak self] in
            guard let self else { return }
            DuelOriginalSound.shared.prewarmAsync()
            async let digestTask = DuelShadowArenaResourceDigest.computeAsync()
            async let vfxTask: Void = DuelProceduralVFXAssets.prepareAsync()
            async let stageTask: Void = DuelEnvironmentAssetCache.prewarmStageAsync()
            async let heroTask: Void = DuelCascadeurCharacterAsset.prewarmBundledAsync(for: initialHero)
            let (digest, _, _, _) = await (digestTask, vfxTask, stageTask, heroTask)
            guard !Task.isCancelled, !self.closed else { return }
            self.assetDigest = digest
            self.preparingAssets = false
            self.startedTransport = true
            _ = self.room.installAuthenticatedDirect(owner: self.directOwner) { [weak self] data, senderID in
                Task { @MainActor [weak self] in
                    self?.handleIncoming(data: data, senderID: senderID)
                }
            }
            self.statusMessage = self.nearbyMode ? "正在建立面对面房间…" : "正在连接远程对战房间…"
            self.room.start()
            self.handleRoomStateChange()
        }
    }

    func chooseHero(_ hero: DuelGame.Hero) {
        guard var current = engine, let packet = current.setLocalHero(hero) else { return }
        engine = current
        send(packet)
        DuelCascadeurCharacterAsset.prewarm(heroes: [hero])
    }

    func toggleReady() {
        guard var current = engine else { return }
        let next = !current.localSeat.ready
        guard let packet = current.setLocalReady(next) else { return }
        engine = current
        send(packet)
    }

    func startMatch() {
        guard var current = engine, current.canStartMatch else { return }
        let matchID = String(UUID().uuidString.prefix(12))
        let seed = UInt64.random(in: 1...UInt64.max)
        do {
            let packet = try current.startMatch(matchID: matchID, seed: seed)
            engine = current
            send(packet)
            mountActiveMatch()
        } catch {
            errorMessage = "无法开始对局，请确认双方已准备且版本一致。"
        }
    }

    func requestRematch() {
        guard var current = engine else { return }
        localRematchRequested = true
        let nextID = String(UUID().uuidString.prefix(12))
        let nextSeed = UInt64.random(in: 1...UInt64.max)
        let packets = current.requestRematch(nextMatchID: nextID, nextSeed: nextSeed)
        engine = current
        for pkt in packets { send(pkt) }
        if case .playing = current.phase {
            mountActiveMatch()
        }
    }

    func returnToLobby() {
        guard var current = engine else { return }
        let pkt = current.requestReturnToLobby()
        engine = current
        tearDownLiveMatch()
        if let pkt { send(pkt) }
        statusMessage = "已返回房间选角"
    }

    func close(reason: String? = nil) {
        guard !closed else { return }
        closed = true
        prepTask?.cancel(); prepTask = nil
        matchWarmTask?.cancel(); matchWarmTask = nil
        if var current = engine, let reason, let pkt = current.close(reason: reason) {
            engine = current
            send(pkt)
        }
        tearDownLiveMatch()
        room.removeAuthenticatedDirect(owner: directOwner)
        room.leave()
        if let reason, errorMessage == nil { errorMessage = reason }
    }

    func handleBackgroundInterruption() {
        guard !closed else { return }
        if liveSession != nil {
            close(reason: "应用切到后台，已安全结束当前联机对局。")
        }
    }

    // MARK: - Room & Transport Handling

    private func handleRoomStateChange() {
        guard !closed else { return }
        if case .closed(let reason) = room.phase {
            tearDownLiveMatch()
            errorMessage = reason
            return
        }
        guard room.phase == .ready, let hostID = room.hostID,
              room.members.count == 2,
              let guest = room.members.first(where: { $0.id != hostID }),
              let digest = assetDigest else {
            return
        }
        if engine == nil {
            let role: DuelShadowArenaNetworkSession.Role = room.isHost ? .host : .guest
            let session = DuelShadowArenaNetworkSession(
                role: role,
                localPlayerID: room.me.id,
                hostID: hostID,
                guestID: guest.id,
                localAssetDigest: digest,
                initialHero: initialHero
            )
            engine = session
            statusMessage = "已连接双方，请选择武者并准备"
            send(session.makeHelloPacket())
        }
    }

    private func handleIncoming(data: Data, senderID: String) {
        guard !closed, var current = engine else { return }
        guard let packet = try? DuelShadowArenaNetworkPacket.decode(data) else { return }
        let result = current.receive(packet, from: senderID, rematchSeed: UInt64.random(in: 1...UInt64.max))
        engine = current
        for out in result.outgoing { send(out) }

        if result.returnedToLobby {
            tearDownLiveMatch()
            statusMessage = "对方发起了重新选角"
            return
        }
        if case .closed(let reason) = current.phase {
            tearDownLiveMatch()
            errorMessage = reason
            return
        }
        if result.matchStarted {
            mountActiveMatch()
            return
        }
        if !result.steps.isEmpty, let liveSession {
            for (stepGame, tick) in result.steps {
                try? liveSession.publishAuthoritativeStep(trustedGame: stepGame, tick: tick)
                syncedTicks = tick + 1
            }
        }
    }

    private func mountActiveMatch() {
        tearDownLiveMatch()
        guard let current = engine, let game = current.game else { return }
        localRematchRequested = false
        syncedTicks = 0
        room.accepting = false
        let hero0 = game.fighters[0].hero
        let hero1 = game.fighters[1].hero
        let localIndex = current.localSeatIndex

        matchWarmTask = Task { @MainActor [weak self] in
            guard let self else { return }
            async let h0: Void = DuelCascadeurCharacterAsset.prewarmBundledAsync(for: hero0)
            async let h1: Void = DuelCascadeurCharacterAsset.prewarmBundledAsync(for: hero1)
            async let stg: Void = DuelEnvironmentAssetCache.prewarmStageAsync()
            async let vfx: Void = DuelProceduralVFXAssets.prepareAsync()
            _ = await (h0, h1, stg, vfx)
            guard !Task.isCancelled, !self.closed,
                  let latest = self.engine, case .playing = latest.phase,
                  let liveGame = latest.game else { return }
            do {
                let session = try DuelSession.shadowArenaNetworkPresentation(
                    game: liveGame, localFighterIndex: localIndex
                )
                try session.startAuthoritativePresentation()
                self.liveSession = session
                self.startSyncLoop()
            } catch {
                self.close(reason: "联机战斗画面启动失败，请重新进入房间。")
            }
        }
    }

    private func startSyncLoop() {
        stopSyncLoop()
        lastLinkTimestamp = nil
        stepAccumulator = 0
        lastSentGuestInput = .neutral
        guestHeartbeatTicks = 0
        let link = CADisplayLink(target: DisplayTarget(self), selector: #selector(DisplayTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopSyncLoop() {
        displayLink?.invalidate()
        displayLink = nil
        lastLinkTimestamp = nil
        stepAccumulator = 0
    }

    private func tearDownLiveMatch() {
        matchWarmTask?.cancel()
        matchWarmTask = nil
        stopSyncLoop()
        liveSession?.shutdown()
        liveSession = nil
        localRematchRequested = false
        room.accepting = true
    }

    private func handleDisplayTick(_ timestamp: CFTimeInterval) {
        guard !closed, let session = liveSession, var current = engine else { return }
        guard case .playing = current.phase else { return }
        guard let prev = lastLinkTimestamp else {
            lastLinkTimestamp = timestamp
            return
        }
        lastLinkTimestamp = timestamp
        let dt = min(0.1, max(0, timestamp - prev))
        stepAccumulator += dt
        let tickDuration = 1.0 / 60.0
        var ticksToRun = Int(stepAccumulator / tickDuration)
        guard ticksToRun > 0 else { return }
        stepAccumulator -= Double(ticksToRun) * tickDuration
        ticksToRun = min(ticksToRun, 4)

        if current.role == .host {
            let localInput = session.consumeLocalInput()
            do {
                let res = try current.advanceHostTicks(count: ticksToRun, hostInput: localInput)
                engine = current
                for (stepGame, tick) in res.steps {
                    try? session.publishAuthoritativeStep(trustedGame: stepGame, tick: tick)
                    syncedTicks = tick + 1
                }
                if let packet = res.packet {
                    send(packet)
                }
            } catch {
                close(reason: "房主同步推进失败，已结束对局。")
            }
        } else {
            let localInput = session.consumeLocalInput()
            let hasOneShot = !localInput.taps.isEmpty || localInput.weaponCommand != nil || localInput.dashDirection != 0
            guestHeartbeatTicks += ticksToRun
            if hasOneShot || localInput != lastSentGuestInput || guestHeartbeatTicks >= 6 {
                guestHeartbeatTicks = 0
                lastSentGuestInput = DuelGame.Input(
                    move: localInput.move,
                    guardHeld: localInput.guardHeld,
                    taps: [],
                    vertical: localInput.vertical,
                    weaponCommand: nil,
                    rangedHeld: localInput.rangedHeld,
                    heavyHeld: localInput.heavyHeld,
                    dashDirection: 0
                )
                if let packet = current.makeGuestInputPacket(localInput) {
                    engine = current
                    send(packet)
                }
            }
        }
    }

    private func send(_ packet: DuelShadowArenaNetworkPacket) {
        guard let data = try? packet.encoded() else { return }
        room.sendDirect(data, delivery: .reliable)
    }
}

/// Full 4-hero Shadow Arena multiplayer room UI (Nearby Wi-Fi/BT & Remote Game Center).
struct DuelShadowArenaNetworkRoomView: View {
    @ObservedObject private var room: GameRoom
    @StateObject private var model: DuelShadowArenaNetworkRoomModel
    @StateObject private var gamepad = DuelGamepadMenuMonitor()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(room: GameRoom, initialHero: DuelGame.Hero = .wuYong) {
        self.room = room
        _model = StateObject(wrappedValue: DuelShadowArenaNetworkRoomModel(room: room, initialHero: initialHero))
    }

    var body: some View {
        ZStack {
            if let liveSession = model.liveSession, model.errorMessage == nil {
                DuelMatchView(
                    shadowArenaNetwork: liveSession,
                    rematchVoted: model.localRematchRequested,
                    onRematch: { model.requestRematch() },
                    onReturnToLobby: { model.returnToLobby() },
                    onExit: { model.close(reason: "你已离开联机房间。"); dismiss() }
                )
            } else {
                lobbyBody
            }
        }
        .modifier(ArenaLandscape())
        .interactiveDismissDisabled()
        .onAppear {
            model.begin()
            gamepad.onAction = { action in handleNetworkLobbyGamepad(action) }
            gamepad.start()
            gamepad.setMenuActive(model.liveSession == nil)
        }
        .onChange(of: model.liveSession != nil) { inMatch in
            gamepad.setMenuActive(!inMatch)
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { model.handleBackgroundInterruption() }
        }
        .onDisappear {
            gamepad.stop()
            model.close()
        }
    }

    private func handleNetworkLobbyGamepad(_ action: DuelGamepadMenuAction) {
        guard model.liveSession == nil else { return }
        if model.errorMessage != nil {
            if action == .confirm || action == .cancel {
                model.close(); dismiss()
            }
            return
        }
        guard let engine = model.engine else {
            if action == .cancel { model.close(reason: "已离开房间"); dismiss() }
            return
        }
        switch action {
        case .up, .left:
            if let next = DuelGamepadListNavigation.step(in: DuelGame.Hero.allCases, current: engine.localSeat.hero, delta: -1) {
                model.chooseHero(next)
            }
        case .down, .right:
            if let next = DuelGamepadListNavigation.step(in: DuelGame.Hero.allCases, current: engine.localSeat.hero, delta: 1) {
                model.chooseHero(next)
            }
        case .confirm:
            if engine.canStartMatch { model.startMatch() }
            else if engine.peerCompatible { model.toggleReady() }
        case .tertiary:
            if engine.peerCompatible { model.toggleReady() }
        case .cancel:
            model.close(reason: "已离开房间"); dismiss()
        default:
            break
        }
    }

    private var lobbyBody: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                header
                if let error = model.errorMessage {
                    errorPanel(error)
                } else if model.preparingAssets {
                    VStack(spacing: 16) {
                        ProgressView(model.statusMessage).tint(.orange)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if geometry.size.width > geometry.size.height {
                    HStack(alignment: .top, spacing: 16) {
                        showcasePanel.frame(maxWidth: .infinity, maxHeight: .infinity)
                        ScrollView { rightPanel }.frame(width: min(360, geometry.size.width * 0.44))
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            showcasePanel.frame(height: 260)
                            rightPanel
                        }
                    }
                }
            }
            .padding(16)
            .background(
                LinearGradient(colors: [Color(red: 0.055, green: 0.065, blue: 0.10),
                                        Color(red: 0.18, green: 0.13, blue: 0.11)],
                               startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            )
            .foregroundStyle(.white)
        }
    }

    private var header: some View {
        HStack {
            Button {
                model.close(reason: "已离开房间")
                dismiss()
            } label: {
                Label("离开", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("duel.network.leave")
            Spacer()
            VStack(spacing: 2) {
                Text(model.nearbyMode ? "裂隙对决 · 面对面联机" : "裂隙对决 · 远程联机").font(.headline)
                Text(room.code.map { "房间号 \($0)" } ?? "本地局域网 / 蓝牙")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Text("四武者 60Hz 同步").font(.caption.bold()).foregroundStyle(.orange)
        }
    }

    private func errorPanel(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.orange)
            Text(message).multilineTextAlignment(.center)
                .accessibilityIdentifier("duel.network.closed")
            Button("返回大厅") { model.close(); dismiss() }
                .buttonStyle(.borderedProminent).tint(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var showcasePanel: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 18).fill(.black.opacity(0.35))
            if let hero = model.engine?.localSeat.hero {
                DuelLobbyPreview(hero: hero)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "person.2.wave.2.fill").font(.system(size: 46)).foregroundStyle(.orange)
                    Text(model.statusMessage).font(.callout).foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let engine = model.engine {
                HStack(spacing: 12) {
                    seatCard(title: "1P · 房主", seat: engine.hostSeat, isLocal: engine.role == .host)
                    Text("VS").font(.headline.italic()).foregroundStyle(.orange)
                    seatCard(title: "2P · 来宾", seat: engine.guestSeat, isLocal: engine.role == .guest)
                }
                .padding(10)
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
                .padding(10)
            }
        }
    }

    private func seatCard(title: String, seat: DuelShadowArenaNetworkSession.Seat, isLocal: Bool) -> some View {
        let memberName = room.members.first(where: { $0.id == seat.playerID })?.name ?? "等待加入"
        return VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2.bold()).foregroundStyle(.orange)
            Text(memberName + (isLocal ? "（我）" : "")).font(.subheadline.bold()).lineLimit(1)
            Text(seat.hero.name).font(.caption)
            Text(seat.ready ? "已准备" : "选角中")
                .font(.caption2.bold())
                .foregroundStyle(seat.ready ? .green : .white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notice = room.notice {
                Label(notice, systemImage: "info.circle.fill").font(.caption).foregroundStyle(.orange)
            }
            if let engine = model.engine {
                if let mismatch = engine.incompatibilityReason {
                    Label(mismatch, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.red)
                }
                Text("选择武者（支持同角色镜像对战）").font(.headline)
                ForEach(DuelGame.Hero.allCases, id: \.self) { choice in
                    let selected = engine.localSeat.hero == choice
                    Button { model.chooseHero(choice) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(choice.name).font(.subheadline.bold())
                                Text(choice.style).font(.caption2).foregroundStyle(.white.opacity(0.72))
                            }
                            Spacer()
                            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange) }
                        }
                        .padding(10)
                        .background(selected ? Color.orange.opacity(0.26) : Color.white.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(selected ? Color.orange : Color.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("duel.network.choose.\(choice.rawValue)")
                }
                HStack(spacing: 10) {
                    Button(engine.localSeat.ready ? "取消准备" : "准备就绪") {
                        model.toggleReady()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(engine.localSeat.ready ? .gray : .orange)
                    .disabled(!engine.peerCompatible)
                    .accessibilityIdentifier("duel.network.ready")

                    if engine.role == .host {
                        Button("开始对决") { model.startMatch() }
                            .buttonStyle(.borderedProminent).tint(.green)
                            .disabled(!engine.canStartMatch)
                            .accessibilityIdentifier("duel.network.start")
                    }
                }
                if !engine.peerCompatible && engine.incompatibilityReason == nil {
                    ProgressView("正在核对对方版本与资源…").tint(.orange).font(.caption)
                } else if engine.role == .guest {
                    Text("双方准备就绪后，房主点击「开始对决」即可开战。")
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                }
            } else {
                connectionPanel
            }
        }
        .padding(16)
        .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.orange.opacity(0.25)))
    }

    @ViewBuilder
    private var connectionPanel: some View {
        switch room.phase {
        case .idle, .waiting:
            ProgressView(room.code == nil ? "等待另一位玩家在附近房间加入…" : "等待另一位玩家输入同一 4 位房间号…")
                .tint(.orange)
        case .browsing, .joining:
            if room.rooms.isEmpty {
                ProgressView("正在搜索附近的裂隙对决房间…").tint(.orange)
            }
            ForEach(room.rooms) { nearby in
                Button {
                    room.join(nearby)
                } label: {
                    HStack {
                        Label("\(nearby.name) 的房间", systemImage: "wifi")
                        Spacer()
                        if room.phase == .joining(nearby.name) { ProgressView().tint(.orange) }
                    }
                    .padding(10)
                }
                .buttonStyle(.borderedProminent).tint(.orange)
                .disabled(room.phase != .browsing)
            }
        case .ready:
            ProgressView("正在握手并交换武者清单…").tint(.orange)
        case .closed(let reason):
            Text(reason).foregroundStyle(.orange)
        }
    }
}
