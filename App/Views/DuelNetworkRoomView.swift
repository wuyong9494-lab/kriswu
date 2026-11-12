import SwiftUI

/// Explicit entry only. Opening this form does not start a transport or sign in.
struct DuelNetworkEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var nickname = GameProfile.nickname
    @State private var code = ""
    @State private var roomEntry: GameRoomEntry?

    var body: some View {
        NavigationStack {
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        nearby.frame(width: 310)
                        remote.frame(width: 310)
                    }
                    VStack(spacing: 20) { nearby; remote }
                }
                .padding(20)
                Text("双方选角并准备后由房主启动联机战斗；需要两台设备使用相同版本。")
                    .font(.callout).foregroundStyle(.white.opacity(0.8))
                    .padding([.horizontal, .bottom], 20)
                    .accessibilityIdentifier("duel.network.scope")
            }
            .background(DuelNetworkBackdrop())
            .foregroundStyle(.white)
            .navigationTitle("双人选角 · 联机测试")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回") { dismiss() }.accessibilityIdentifier("duel.network.entry.close")
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .modifier(ArenaLandscape())
        .onAppear { if nickname.isEmpty { nickname = store.settings.aliases.first ?? "" } }
        .fullScreenCover(item: $roomEntry) { DuelNetworkRoomView(room: $0.room) }
    }

    private var nearby: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("面对面 · 两位玩家", systemImage: "person.2.fill").font(.title3.bold())
            TextField("对方看到的名字", text: $nickname)
                .textFieldStyle(.roundedBorder).foregroundStyle(.primary)
                .onChange(of: nickname) { GameProfile.nickname = $0 }
                .accessibilityIdentifier("duel.network.nickname")
            Button("创建双人房间") { open(.nearbyHost) }
                .buttonStyle(.borderedProminent).tint(.orange)
                .accessibilityIdentifier("duel.network.create")
            Button("寻找附近房间") { open(.nearbyGuest) }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("duel.network.browse")
            Text("两台手机打开 Wi-Fi 和蓝牙；首次连接需允许本地网络访问。无需 Game Center。")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .duelNetworkPanel()
    }

    private var remote: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("远程 · 两位玩家", systemImage: "globe.asia.australia").font(.title3.bold())
            HStack {
                TextField("2 开头的 4 位房间号", text: $code)
                    .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("duel.network.code")
                Button("随机") { code = String(RoomCode.make(players: 2)) }
                    .buttonStyle(.bordered)
            }
            Button("进入双人房间") {
                guard let parsed = DuelNetworkSelectionModel.roomCode(code) else { return }
                open(.remote(code: parsed))
            }
            .buttonStyle(.borderedProminent).tint(.orange)
            .disabled(DuelNetworkSelectionModel.roomCode(code) == nil)
            .accessibilityIdentifier("duel.network.remote")
            Text("双方输入同一个房间号。需要联网并登录各自的 Game Center；配对成功后由房间确定房主。")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .duelNetworkPanel()
    }

    private func open(_ mode: GameRoom.Mode) {
        guard roomEntry == nil else { return }
        roomEntry = GameRoomEntry(room: GameRoom(kind: .fighter, mode: mode, name: nickname, capacity: 2))
    }
}

/// Owns exactly one room lifetime. No navigation path here reaches offline combat.
struct DuelNetworkRoomView: View {
    @ObservedObject private var room: GameRoom
    @StateObject private var model: DuelNetworkSelectionModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var didStart = false
    @State private var didLeave = false
    @State private var combat: DuelNetworkCombatSession?
    @State private var combatError: String?
    @State private var handingOff = false

    init(room: GameRoom) {
        self.room = room
        _model = StateObject(wrappedValue: DuelNetworkSelectionModel(lobby: DuelNetworkLobby(room: room)))
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                header
                if geometry.size.width > geometry.size.height {
                    HStack(alignment: .top, spacing: 16) {
                        showcase.frame(maxWidth: .infinity, maxHeight: .infinity)
                        ScrollView { controls }.frame(width: min(350, geometry.size.width * 0.43))
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            showcase.frame(height: 280)
                            controls
                        }
                    }
                }
            }
            .padding(16)
            .background(DuelNetworkBackdrop())
            .foregroundStyle(.white)
        }
        .modifier(ArenaLandscape())
        .interactiveDismissDisabled()
        .onAppear {
            guard !didStart else { return }
            didStart = true
            room.start()
            attachIfReady()
        }
        .onChange(of: room.phase) { _ in attachIfReady() }
        .onChange(of: room.members) { _ in attachIfReady() }
        .onChange(of: model.status) { value in
            if value == .started { enterCombat() }
            else if value == .closed && combat == nil && !handingOff { leaveTransport() }
        }
        .fullScreenCover(isPresented: Binding(
            get: { combat != nil },
            set: { if !$0 { finishCombat() } }
        )) {
            if let combat {
                DuelNetworkCombatView(combat: combat, onExit: finishCombat)
            }
        }
        .onChange(of: scenePhase) {
            if $0 == .background {
                combat?.stop()
                model.close(reason: "应用已进入后台，联机对战已结束。请重新进入房间。")
                leaveTransport()
            }
        }
        .onDisappear {
            if combat == nil { model.close(); leaveTransport() }
        }
    }

    private var header: some View {
        HStack {
            Button { model.close(); leaveTransport(); dismiss() } label: {
                Label("离开", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("duel.network.leave")
            Spacer()
            VStack(spacing: 2) {
                Text("裂隙对决 · 双人选角").font(.headline)
                Text(room.code.map { "远程房间 \($0)" } ?? "面对面房间")
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            Text("双人联机").font(.caption.bold()).foregroundStyle(.orange)
        }
    }

    private var showcase: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.3))
            if let hero = model.localPlayer?.choice?.hero, model.status != .closed, hasPreview(hero) {
                DuelLobbyPreview(hero: hero)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .accessibilityIdentifier("duel.network.preview")
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "figure.boxing").font(.system(size: 52))
                    Text(model.status == .closed ? "选角已结束" : "选择你的武者")
                }
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxHeight: .infinity)
            }
            HStack(alignment: .top, spacing: 10) {
                seat(.host)
                Text("VS").font(.headline.italic()).foregroundStyle(.orange).padding(.top, 16)
                seat(.guest)
            }
            .padding(12)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
            .padding(12)
        }
    }

    private func seat(_ seat: DuelMultiplayerSelection.Seat) -> some View {
        let player = model.snapshot?.players.first { $0.seat == seat }
        let member = room.members.first { $0.id == player?.id }
        return VStack(alignment: .leading, spacing: 5) {
            Text(seat == .host ? "1P · 房主" : "2P · 来宾").font(.caption.bold()).foregroundStyle(.orange)
            Text(member.map { $0.name + ($0.id == room.me.id ? "（我）" : "") } ?? "等待玩家")
                .font(.subheadline.bold()).lineLimit(1)
            Text(player?.choice.map(Self.choiceName) ?? "尚未选择").font(.caption)
            Text(player?.isReady == true ? "已准备" : "未准备")
                .font(.caption.bold()).foregroundStyle(player?.isReady == true ? Color.green : Color.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("duel.network.seat.\(seat.rawValue)")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("双方准备后，房主锁定选角并进入联网战斗。")
                .font(.caption).foregroundStyle(.white.opacity(0.7))
                .accessibilityIdentifier("duel.network.scope")
            if let combatError { message(combatError, warning: true) }
            if let notice = room.notice { message(notice, warning: true) }
            if let error = model.error {
                message(error, warning: true).accessibilityIdentifier("duel.network.error")
            }
            if case .closed(let reason) = room.phase {
                message(reason, warning: true).accessibilityIdentifier("duel.network.disconnected")
            } else if model.status == .started {
                message("双方选角已确认，正在移交战斗连接…", warning: false)
                    .accessibilityIdentifier("duel.network.selectionComplete")
            } else if model.status == .selecting {
                selectionControls
            } else if model.status == .connecting {
                ProgressView("正在同步选角…").tint(.orange)
            } else if model.status != .closed {
                connectionControls
            }
        }
        .duelNetworkPanel()
    }

    private var selectionControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择武者").font(.title3.bold())
            choiceButton(.sun)
            choiceButton(.liu)
            if model.hasConflict {
                message("双方选择了同一位武者。请其中一人换选，才能准备。", warning: true)
                    .accessibilityIdentifier("duel.network.conflict")
            } else {
                Text("任何一人换选，双方都需要重新准备。")
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            if model.pending != nil {
                ProgressView("等待房主确认，尚未生效…").tint(.orange)
                    .accessibilityIdentifier("duel.network.pending")
            }
            Button(model.localPlayer?.isReady == true ? "取消准备" : "准备") { model.toggleReady() }
                .buttonStyle(.borderedProminent).tint(.orange)
                .disabled(!model.canReady)
                .accessibilityIdentifier("duel.network.ready")
            if model.isHost {
                Button("锁定双方选角") { model.startSelection() }
                    .buttonStyle(.bordered).disabled(!model.canStart)
                    .accessibilityIdentifier("duel.network.start")
            } else {
                Text("双方准备后，由房主确认选角。")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    @ViewBuilder private var connectionControls: some View {
        switch room.phase {
        case .idle, .waiting:
            ProgressView(room.code == nil ? "等待另一位玩家加入…" : "等待另一位玩家输入同一房间号…").tint(.orange)
        case .browsing, .joining:
            if room.rooms.isEmpty { ProgressView("正在寻找附近的双人房间…").tint(.orange) }
            ForEach(room.rooms) { nearby in
                Button {
                    room.join(nearby)
                } label: {
                    HStack {
                        Text("\(nearby.name) 的房间")
                        if room.phase == .joining(nearby.name) { ProgressView().tint(.orange) }
                    }
                }
                .buttonStyle(.bordered).disabled(room.phase != .browsing)
            }
        case .ready:
            ProgressView("正在建立选角连接…").tint(.orange)
        case .closed:
            EmptyView()
        }
    }

    private func choiceButton(_ choice: DuelMultiplayerSelection.Choice) -> some View {
        let selected = model.localPlayer?.choice == choice
        return Button { model.choose(choice) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.choiceName(choice)).font(.headline)
                    Text(selected ? "房主已确认" : "选择这位武者").font(.caption)
                }
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill") }
            }
            .padding(12)
            .background(selected ? Color.orange.opacity(0.28) : Color.white.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.orange : Color.white.opacity(0.15)))
        }
        .buttonStyle(.plain).disabled(!model.canChoose)
        .accessibilityIdentifier("duel.network.choose.\(choice.hero.rawValue)")
    }

    private func message(_ text: String, warning: Bool) -> some View {
        Label(text, systemImage: warning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.callout).foregroundStyle(warning ? Color.orange : Color.green)
    }

    private func enterCombat() {
        guard combat == nil, !didLeave, let snapshot = model.snapshot,
              snapshot.phase == .started else { return }
        // The selection coordinator must release its direct-channel lease before
        // combat claims it; otherwise both protocols would consume the same bytes.
        handingOff = true
        model.close()
        do {
            let catalog = try? DuelWeaponAssets().catalog
            let next = try DuelNetworkCombatSession(room: room, started: snapshot,
                                                    catalog: catalog, seed: UInt64.random(in: 1...UInt64.max))
            try next.start()
            combat = next
            handingOff = false
        } catch {
            handingOff = false
            combatError = "无法进入联机战斗：角色资源或房间通道尚未准备好。"
            leaveTransport()
        }
    }

    private func finishCombat() {
        combat?.stop()
        combat = nil
        leaveTransport()
        dismiss()
    }

    private func attachIfReady() {
        guard !didLeave, room.phase == .ready else { return }
        model.attach(localID: room.me.id)
    }

    private func leaveTransport() {
        guard !didLeave else { return }
        didLeave = true
        room.leave()
    }

    private static func choiceName(_ choice: DuelMultiplayerSelection.Choice) -> String {
        choice.hero.name + (choice.weapon == .katana ? " · 武士刀" : " · 双锤")
    }

    private func hasPreview(_ hero: DuelGame.Hero) -> Bool {
        DuelStageAsset.bundledURL(for: .autumnLobby) != nil &&
            (DuelWeaponAssets.catalogURL() != nil || DuelCharacterAsset.bundledURL(for: hero) != nil)
    }
}

private struct DuelNetworkBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.055, green: 0.065, blue: 0.10),
                                Color(red: 0.19, green: 0.14, blue: 0.13)],
                       startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
    }
}

private extension View {
    func duelNetworkPanel() -> some View {
        padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.orange.opacity(0.25)))
    }
}
