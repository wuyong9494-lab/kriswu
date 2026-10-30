import SwiftUI
import UIKit

/// 奖杯之路：总奖杯到了哪个点给什么
struct ArenaTrophyRoad: View {
    @ObservedObject private var growth = ArenaProgressStore.shared

    var body: some View {
        let reached = max(growth.progress.totalTrophies, growth.progress.reached)
        return ScrollView {
            VStack(spacing: 8) {
                ForEach(ArenaProgress.road, id: \.trophies) { point in
                    HStack(spacing: 10) {
                        Image(systemName: point.trophies <= reached ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(point.trophies <= reached ? Color(red: 0.45, green: 0.9, blue: 0.35) : .white.opacity(0.5))
                        Label("\(point.trophies)", systemImage: "trophy.fill")
                            .font(.system(size: 16, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(.orange)
                            .frame(width: 100, alignment: .leading)
                        if let brawler = point.brawler {
                            BrawlerBadge(brawler: brawler, size: 32)
                            Text("解锁\(brawler.name)")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .arenaOutline(1)
                        } else {
                            Label("\(point.coins) 金币", systemImage: "dollarsign.circle.fill")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(point.trophies <= reached ? 0.28 : 0.45)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 2))
                }
                Text("所有角色的奖杯加起来算。奖杯掉了再涨回来，已经给过的奖励不重复给。")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - 一局

/// 和电脑打：「再来一局」换一个新的
struct ArenaPlayView: View {
    let setup: ArenaController.Setup
    @Environment(\.dismiss) private var dismiss
    @State private var controller: ArenaController
    @State private var round = 0

    init(setup: ArenaController.Setup) {
        self.setup = setup
        _controller = State(initialValue: ArenaController(setup: setup))
    }

    var body: some View {
        ArenaMatchView(controller: controller, onAgain: {
            controller = ArenaController(setup: setup)
            round += 1
        }, onExit: {
            dismiss()
        })
        .id(round)
        .modifier(ArenaLandscape())
    }
}

/// 乱斗对局在 iPhone 上横着打：对局出现就转成横屏，没有对局了转回竖屏（iPad 一直随便转）
@MainActor
enum ArenaOrientation {
    /// AppDelegate 按这个告诉系统现在能转成哪个方向
    private(set) static var landscape = false
    /// 正显示着的对局（再来一局时新的先出现、旧的后消失，也不会转回去）
    private static var holders: Set<UUID> = []

    static func hold(_ id: UUID) {
        holders.insert(id)
        update()
    }

    static func release(_ id: UUID) {
        holders.remove(id)
        update()
    }

    /// 点了退出：马上转回竖屏，不等画面关完
    static func releaseAll() {
        holders.removeAll()
        update()
    }

    private static func update() {
        let wanted = !holders.isEmpty
        guard UIDevice.current.userInterfaceIdiom == .phone, wanted != landscape else { return }
        landscape = wanted
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: wanted ? .landscape : .portrait))
        }
    }
}

struct ArenaLandscape: ViewModifier {
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { ArenaOrientation.hold(id) }
            .onDisappear { ArenaOrientation.release(id) }
    }
}

// MARK: - 联机房间

struct ArenaRoomView: View {
    @ObservedObject var lobby: ArenaLobby
    @ObservedObject private var room: GameRoom
    private let previewOnly: Bool
    @Environment(\.dismiss) private var dismiss

    /// 这个玩法怎么分人
    static func seatNote(_ mode: ArenaGame.Mode) -> String {
        switch mode {
        case .showdown: return "各打各的，不够 6 个人电脑补。"
        case .duo: return "两人一队、一共 3 队，按进房间的先后轮流分，不够的电脑补。"
        case .duel: return "只能两个人对打（人多了开不了），各带 3 个角色：先上自己选的，另外两个电脑帮你挑。"
        case .boss: return "最多 3 个人当勇者，不够的电脑补；骷髅王是电脑。"
        default: return "按进房间的先后轮流分到两队，每队不够 3 个人电脑补。"
        }
    }

    init(lobby: ArenaLobby, previewOnly: Bool = false) {
        self.lobby = lobby
        room = lobby.room
        self.previewOnly = previewOnly && ProcessInfo.processInfo.arguments.contains("-demo")
    }

    var body: some View {
        ArenaGamePanel(title: room.code == nil ? "面对面乱斗" : "远程乱斗", tint: .cyan, onClose: {
            room.leave()
            dismiss()
        }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let notice = room.notice {
                        roomCard("房间提示", symbol: "exclamationmark.triangle.fill") {
                            Text(notice).foregroundStyle(.yellow)
                        }
                    }
                    roomState
                }
                .padding(6)
            }
            .foregroundStyle(.white)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .onAppear { if !previewOnly { room.start() } }
        .background {
            if previewOnly {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { writePreviewMarker(geometry.size) }
                        .onChange(of: geometry.size) { size in writePreviewMarker(size) }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if previewOnly {
                Text("离线界面预览").font(.caption.bold()).padding(6)
                    .background(.black.opacity(0.8)).foregroundStyle(.yellow)
                    .allowsHitTesting(false)
            }
        }
        .fullScreenCover(item: $lobby.playing) { playing in
            ArenaMatchView(controller: playing.controller, onAgain: nil, onExit: {
                lobby.playing = nil
            })
            .modifier(ArenaLandscape())
        }
    }

    private func writePreviewMarker(_ size: CGSize) {
        guard previewOnly, size.width > size.height, size.height > 0 else { return }
        let evidence: [String: Any] = ["scene": "arenaRoom", "offline": true,
                                      "viewWidth": size.width, "viewHeight": size.height]
        if let data = try? JSONSerialization.data(withJSONObject: evidence),
           let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: folder.appendingPathComponent("arena-room-ready.json"), options: .atomic)
        }
    }

    @ViewBuilder private var roomState: some View {
        switch room.phase {
        case .idle:
            roomCard("连接中", symbol: "antenna.radiowaves.left.and.right") {
                loading("正在准备房间…")
            }
        case .waiting:
            roomCard("等待队友", symbol: "person.2.fill") {
                if let code = room.code {
                    Text("房间号  \(String(code))")
                        .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                        .textSelection(.enabled)
                    loading("等待 \(RoomCode.players(of: code) - 1) 人输入房间号")
                    Button {
                        let text = "来「值班提醒」里玩\(room.kind.title)：小游戏 › \(room.kind.title) › 远程，房间号 \(code)"
                        ActivityShare.present([text], excluding: ActivityShare.chatOnly) { _ in }
                    } label: {
                        Label("分享房间号", systemImage: "square.and.arrow.up")
                            .padding(.horizontal, 14).frame(minHeight: 48)
                    }
                    .buttonStyle(ArenaTileButton(face: .blue, edge: Color(red: 0.08, green: 0.2, blue: 0.5)))
                    Text("所有玩家都需登录 Game Center 并联网。等待时请留在此页。")
                } else {
                    loading("等待附近玩家加入…")
                    Text("请队友选择「加入身边同事的房间」，找到「\(room.me.name)」并加入。")
                }
            }
        case .browsing, .joining:
            roomCard("附近房间", symbol: "antenna.radiowaves.left.and.right") {
                if room.rooms.isEmpty { loading("正在寻找附近的房间…") }
                ForEach(room.rooms) { nearby in
                    Button { room.join(nearby) } label: {
                        HStack {
                            Label("\(nearby.name) 的房间", systemImage: "person.3.fill")
                            Spacer()
                            if room.phase == .joining(nearby.name) { ProgressView().tint(.white) }
                            else { Image(systemName: "chevron.right") }
                        }
                        .padding(12).frame(minHeight: 48)
                    }
                    .buttonStyle(ArenaTileButton(face: .blue, edge: Color(red: 0.08, green: 0.2, blue: 0.5)))
                    .disabled(room.phase != .browsing)
                    .opacity(room.phase == .browsing || room.phase == .joining(nearby.name) ? 1 : 0.5)
                }
                Text("请靠近队友，打开 Wi-Fi、蓝牙，并允许本地网络访问。")
            }
        case .ready:
            readyRoom
        case .closed(let reason):
            roomCard("房间已关闭", symbol: "wifi.slash") {
                Text(reason)
                Text("点击右上角关闭，再重新创建或加入房间。")
            }
        }
    }

    private var readyRoom: some View {
        VStack(alignment: .leading, spacing: 14) {
            roomCard("选择角色 · \(lobby.myPick.name)", symbol: "person.crop.square.fill") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 10)], spacing: 10) {
                    ForEach(Brawler.allCases, id: \.self) { brawler in
                        Button { lobby.choose(brawler) } label: {
                            VStack(spacing: 4) {
                                BrawlerBadge(brawler: brawler, size: 50, selected: lobby.myPick == brawler)
                                Text(brawler.name).font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity, minHeight: 78)
                            .background(lobby.myPick == brawler ? Color.blue : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(lobby.myPick == brawler ? .isSelected : [])
                    }
                }
            }
            roomCard("技能装备", symbol: "bolt.fill") {
                ArenaLoadoutSection(brawler: lobby.myPick, onChange: lobby.loadoutChanged, gameStyle: true)
            }
            roomCard("房间成员 · \(room.members.count) 人", symbol: "person.3.fill") {
                ForEach(room.members) { member in
                    HStack(spacing: 10) {
                        if let pick = lobby.pick(of: member.id) { BrawlerBadge(brawler: pick, size: 38) }
                        else { Image(systemName: "questionmark.square.fill").frame(width: 38) }
                        Text(member.id == room.me.id ? "\(member.name)（我）" : member.name)
                        Text("Lv. \(lobby.level(of: member.id))").foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        if member.id == room.hostID { Label("房主", systemImage: "crown.fill").foregroundStyle(.yellow) }
                    }
                    .padding(10)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                }
                Text(Self.seatNote(lobby.mode)).foregroundStyle(.white.opacity(0.75))
            }
            roomCard("玩法 · \(lobby.mode.title)", symbol: "flag.fill") {
                if room.isHost {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
                        ForEach(ArenaGame.Mode.allCases, id: \.self) { mode in
                            Button { lobby.choose(mode) } label: {
                                Label(mode.title, systemImage: mode.icon)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(lobby.mode == mode ? Color.blue : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(lobby.mode == mode ? .isSelected : [])
                        }
                    }
                    Button { lobby.start() } label: {
                        Label("开打（\(room.members.count) 人）", systemImage: "play.fill")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(ArenaTileButton(face: Color(red: 0.95, green: 0.66, blue: 0.1), edge: .orange))
                    .disabled(!lobby.fits)
                    .opacity(lobby.fits ? 1 : 0.45)
                    if !lobby.fits { Text("当前人数不符合玩法要求，请更换玩法或调整人数。 ").foregroundStyle(.yellow) }
                } else {
                    loading("等待房主开打，开始后自动进入对局。")
                }
                Text(lobby.mode.rules).foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private func loading(_ text: String) -> some View {
        HStack(spacing: 10) { ProgressView().tint(.white); Text(text) }.padding(.vertical, 8)
    }

    private func roomCard<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(red: 0.07, green: 0.15, blue: 0.34), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.18), lineWidth: 2))
    }

}

struct ArenaMatchView: View {
    @ObservedObject var controller: ArenaController
    /// 和电脑打才有「再来一局」；联机的回房间等房主再开
    var onAgain: (() -> Void)?
    var onExit: () -> Void
    @State private var confirmingExit = false
    @State private var previewDisconnect = false
    @State private var resultShown = false
    /// 表情那一排打开着
    @State private var emoting = false
    @State private var copiedPerformance = false
    @AppStorage("arena.performanceOverlay") private var performanceOverlay = false
    @AppStorage(ArenaSound.muteKey) private var muted = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// iPhone 横着打（上下矮）：摇杆、结算卡片换成横的摆法
    private var wide: Bool { verticalSizeClass == .compact }

    /// 在上边那一队的人：画面倒过来（自己的家总在下边），摇杆也跟着反过来
    private var flip: Double { controller.game.mode.isTeams && controller.mine.team == 1 ? -1 : 1 }

    private var hud: ArenaController.HUD { controller.hud }
    private var blockingDialog: Bool {
        hud.result == nil && (confirmingExit || controller.disconnected || previewDisconnect)
    }

    private func clearDialogInput() {
        controller.move = .zero
        controller.aiming = nil
        controller.superAiming = nil
        emoting = false
    }

    var body: some View {
        let _ = ArenaPerfRecorder.shared.noteUIEvaluation()
        ZStack {
            ArenaWorld(controller: controller)
                .ignoresSafeArea()
                // Hide at the SwiftUI bridge too: UIViewRepresentable can override
                // the underlying SCNView accessibility flags when mounting it.
                .accessibilityElement(children: .ignore)
                .accessibilityHidden(true)
            VStack(spacing: DS.Space.xs) {
                topBar
                if emoting && hud.result == nil {
                    emoteBar.transition(.move(edge: .top).combined(with: .opacity))
                }
                banner
                Spacer()
                controls
            }
            if hud.dead && hud.result == nil && controller.willRespawn {
                Text("\(hud.respawnIn) 秒后复活")
                    .font(DS.Font.title)
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.l)
                    .padding(.vertical, DS.Space.s)
                    .background(.black.opacity(0.45), in: Capsule())
            }
            if let result = hud.result { resultCard(result) }
            if controller.showingIntro {
                ArenaVersus(game: controller.game, me: controller.me,
                            title: controller.story.map { "\($0.id) \($0.title)" } ?? controller.game.mode.title)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(!blockingDialog)
        .accessibilityHidden(blockingDialog)
        .overlay(alignment: .topTrailing) {
            // 右上角：谁打倒了谁
            if hud.result == nil && !controller.showingIntro && !blockingDialog {
                killFeed.padding(.top, 54).padding(.trailing, DS.Space.m)
            }
        }
        .animation(.easeOut(duration: 0.3), value: controller.showingIntro)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .overlay {
            if blockingDialog {
                ArenaMatchDialog(disconnected: controller.disconnected || previewDisconnect, onContinue: {
                    confirmingExit = false
                }, onExit: onExit)
            }
        }
        .onAppear {
            // Screenshot fixture only; never change the network controller state.
            if ProcessInfo.processInfo.arguments.contains("-demo") {
                let preview = UserDefaults.standard.string(forKey: "arena.dialogPreview")
                confirmingExit = preview == "exit"
                previewDisconnect = preview == "disconnect"
            }
            if blockingDialog { clearDialogInput() }
        }
        .onChange(of: blockingDialog) { blocked in
            if blocked { clearDialogInput() }
        }
        .onChange(of: hud.result != nil) { finished in
            if finished { confirmingExit = false }
        }
    }

    // MARK: 上面

    private var topBar: some View {
        HStack(spacing: DS.Space.s) {
            Button {
                if hud.result == nil { confirmingExit = true } else { onExit() }
            } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.35), in: Circle())
            }
            Button {
                muted.toggle()
                ArenaSound.shared.muteChanged(battle: true)
            } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.subheadline).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.35), in: Circle())
            }
            Button {
                withAnimation(.easeOut(duration: 0.2)) { emoting.toggle() }
            } label: {
                Image(systemName: "face.smiling.inverse").font(.headline).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background((emoting ? Color(uiColor: ArenaPalette.gold) : Color.black).opacity(emoting ? 0.8 : 0.35), in: Circle())
            }
            .accessibilityLabel("表情")
            if performanceOverlay {
                Button {
                    UIPasteboard.general.string = ArenaDiagnostics.shared.latestReport
                    copiedPerformance = true
                } label: {
                    Image(systemName: copiedPerformance ? "checkmark" : "doc.on.doc")
                        .frame(width: 36, height: 36)
                        .foregroundStyle(.white)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .accessibilityLabel("复制性能报告")
            }

            Spacer()
            score
            Spacer()
            Text(String(format: "%d:%02d", hud.timeLeft / 60, hud.timeLeft % 60))
                .font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .arenaInk()
                .frame(width: 60, height: 36)
                .background(.black.opacity(0.35), in: Capsule())
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.top, DS.Space.xs)
    }

    @ViewBuilder private var score: some View {
        switch controller.game.mode {
        case .teamFight:
            versus(String(hud.blue), String(hud.red), note: "先打倒 \(ArenaGame.goal) 次")
        case .stars:
            versus("⭐️\(hud.blue)", "⭐️\(hud.red)", note: "凑 \(ArenaGame.goal) 颗守 15 秒")
        case .zone:
            versus("\(hud.blue)%", "\(hud.red)%", note: "站圈加分")
        case .ball:
            versus("⚽️\(hud.blue)", "\(hud.red)", note: "先进 \(ArenaGame.ballGoals) 球")
        case .heist:
            versus("\(hud.blue)%", "\(hud.red)%", note: "打爆对面的宝箱")
        case .bounty:
            versus("★\(hud.blue)", "★\(hud.red)", note: "打倒人拿悬赏")
        case .knockout:
            versus("\(hud.blue)", "\(hud.red)", note: "第 \(hud.round) 局 · 先赢 \(ArenaGame.roundsToWin) 局")
        case .duel:
            versus("\(hud.blue)", "\(hud.red)", note: "打倒对方 3 个角色")
        case .showdown:
            pill("剩 \(hud.alive) 个人")
        case .duo:
            pill("剩 \(hud.teamsLeft) 队")
        case .boss:
            bossBar
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .arenaInk()
            .padding(.horizontal, DS.Space.m)
            .frame(height: 36)
            .background(.black.opacity(0.35), in: Capsule())
    }

    /// 讨伐骷髅王：上面一条长长的红血条
    private var bossBar: some View {
        let fraction = CGFloat(hud.bossHealth) / CGFloat(max(hud.bossMaxHealth, 1))
        return VStack(spacing: 2) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.6))
                Capsule().fill(Color(uiColor: ArenaPalette.red))
                    .frame(width: max(0, 226 * min(fraction, 1)), height: 14)
                    .padding(.leading, 2)
                Text("骷髅王  \(hud.bossHealth)")
                    .font(.system(size: 13, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .arenaInk()
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 230, height: 18)
            .overlay(Capsule().strokeBorder(.black.opacity(0.6), lineWidth: 2))
            Text("3 分钟内打倒它").font(DS.Font.overline).foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.5), radius: 2)
        }
    }

    private func versus(_ blue: String, _ red: String, note: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                Text(blue).frame(minWidth: 56).padding(.vertical, 4).background(Color(uiColor: ArenaPalette.blue))
                Text(red).frame(minWidth: 56).padding(.vertical, 4).background(Color(uiColor: ArenaPalette.red))
            }
            .font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .arenaInk()
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(.black.opacity(0.55), lineWidth: 2))
            Text(note).font(DS.Font.overline).foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.5), radius: 2)
        }
    }

    @ViewBuilder private var banner: some View {
        if let note = controller.announcement {
            // 进球、一局打完、开新一局：大字
            Text(note.text)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .arenaInk()
                .padding(.horizontal, DS.Space.l)
                .padding(.vertical, DS.Space.xs)
                .background((note.good ? Color(uiColor: ArenaPalette.blue) : Color(uiColor: ArenaPalette.red)).opacity(0.85), in: Capsule())
        } else if let team = hud.countdownTeam {
            Text(team == controller.mine.team ? "守住 \(hud.countdownLeft) 秒就赢了！" : "对方再守 \(hud.countdownLeft) 秒就赢了，快抢！")
                .font(DS.Font.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, DS.Space.m)
                .padding(.vertical, 6)
                .background((team == controller.mine.team ? Color(uiColor: ArenaPalette.blue) : Color(uiColor: ArenaPalette.red)).opacity(0.85),
                            in: Capsule())
        } else if hud.poisonShrinking && controller.game.safeRadius < 6.5 {
            Text("决赛圈")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .arenaInk()
                .padding(.horizontal, DS.Space.m)
                .padding(.vertical, 8)
                .background(Color(red: 0.45, green: 0.16, blue: 0.72).opacity(0.82), in: Capsule())
        } else if hud.poisonShrinking {
            Text("毒圈在缩，待在圈里")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .arenaInk()
                .padding(.horizontal, DS.Space.m)
                .padding(.vertical, 4)
                .background(Color(red: 0.45, green: 0.16, blue: 0.72).opacity(0.82), in: Capsule())
        } else if controller.game.time < 3 {
            // 开局头几秒：这局的地图
            Text("\(controller.game.mode.title) · \(controller.game.map.title)")
                .font(DS.Font.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, DS.Space.m)
                .padding(.vertical, 6)
                .background(.black.opacity(0.4), in: Capsule())
        }
    }

    // MARK: 摇杆

    private var controls: some View {
        HStack(alignment: .bottom) {
            ArenaStick(kind: .move, onChange: {
                guard !blockingDialog else { return }
                controller.move = $0 * flip
            }, onRelease: { _ in controller.move = .zero })
            Spacer()
            // 横屏：大招钮在攻击钮左上；竖屏：在攻击钮上面
            // 小道具钮（绿）：横屏在攻击钮上面，竖屏在攻击钮左边
            if wide {
                HStack(alignment: .bottom, spacing: DS.Space.m) {
                    superStick.padding(.bottom, 44)
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        gadgetButton
                        attackStick
                    }
                }
            } else {
                VStack(alignment: .trailing, spacing: DS.Space.s) {
                    superStick
                    HStack(alignment: .bottom, spacing: DS.Space.s) {
                        gadgetButton
                        attackStick
                    }
                }
            }
        }
        .padding(.horizontal, wide ? DS.Space.m : DS.Space.l)
        .padding(.bottom, wide ? DS.Space.s : DS.Space.m)
        .opacity(hud.result == nil ? 1 : 0)
        // The VS overlay covers the sticks. Do not expose or accept input until
        // the real match begins (the controls already exist underneath it).
        .allowsHitTesting(!controller.showingIntro && hud.result == nil)
        .accessibilityHidden(controller.showingIntro || hud.result != nil)
        // Recreate sticks when the modal opens/closes so cancelled drags cannot
        // leave a displaced thumb or deliver a release attack after dismissal.
        .id(blockingDialog)
    }

    @ViewBuilder private var gadgetButton: some View {
        if let gadget = hud.gadget {
            ArenaGadgetButton(gadget: gadget, uses: hud.gadgetUses, cooldown: hud.gadgetCooldown, dead: hud.dead) {
                guard !blockingDialog else { return }
                controller.fireGadget()
            }
        }
    }

    private var superStick: some View {
        ArenaStick(kind: .special(charge: hud.superCharge, hyper: hud.hyperUnlocked ? hud.hyperCharge : nil, hyperTime: hud.hyperTime),
                   onChange: { if !blockingDialog { controller.superAiming = $0 * flip } },
                   onRelease: { drag in
                       controller.superAiming = nil
                       guard !blockingDialog else { return }
                       controller.fireSpecial(drag * flip)
                   })
    }

    private var attackStick: some View {
        ArenaStick(kind: .attack,
                   onChange: { if !blockingDialog { controller.aiming = $0 * flip } },
                   onRelease: { drag in
                       controller.aiming = nil
                       guard !blockingDialog else { return }
                       controller.fire(drag * flip)
                   })
    }

    // MARK: 表情

    /// 有的表情一排，点一个头顶冒出来
    private var emoteBar: some View {
        HStack(spacing: 6) {
            ForEach(ArenaProgressStore.shared.progress.emotes) { emote in
                Button {
                    controller.emote(emote.id)
                    withAnimation(.easeOut(duration: 0.2)) { emoting = false }
                } label: {
                    Text(emote.symbol)
                        .font(.system(size: 26))
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.92), in: Circle())
                        .overlay(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 2))
                }
                .accessibilityLabel(emote.name)
            }
        }
        .padding(6)
        .background(.black.opacity(0.35), in: Capsule())
    }

    // MARK: 击倒提示

    private var killFeed: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(Array(controller.feed.suffix(2))) { note in
                HStack(spacing: 6) {
                    if let killer = note.killer, controller.game.fighters.indices.contains(killer) {
                        feedName(killer)
                    }
                    Image(systemName: "burst.fill")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Color(uiColor: ArenaPalette.gold))
                    feedName(note.victim)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.black.opacity(0.42), in: Capsule())
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: controller.feed)
    }

    @ViewBuilder private func feedName(_ id: Int) -> some View {
        if controller.game.fighters.indices.contains(id) {
            let fighter = controller.game.fighters[id]
            let color = id == controller.me ? ArenaPalette.myName
                : (fighter.team == controller.mine.team ? ArenaPalette.allyName : ArenaPalette.enemyName)
            HStack(spacing: 3) {
                BrawlerBadge(brawler: fighter.brawler, size: 22)
                Text(id == controller.me ? "我" : fighter.name)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(uiColor: color))
                    .lineLimit(1)
            }
        }
    }

    // MARK: 结果

    /// 结算：大字写输赢，下面是奖杯金币、全场最佳、这局的数；横屏时放在右边，左边镜头凑近自己（赢了在欢呼）
    private func resultCard(_ result: ArenaGame.Result) -> some View {
        let mine = controller.mine
        let (title, tint) = resultTitle(result, mine: mine)
        return ZStack(alignment: wide ? .trailing : .center) {
            if wide {
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .trailing)
                    .ignoresSafeArea()
            } else {
                Color.black.opacity(0.45).ignoresSafeArea()
            }
            VStack(spacing: wide ? DS.Space.s : DS.Space.m) {
                Text(title)
                    .font(.system(size: wide ? 42 : 52, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
                    .arenaOutline(2.5)
                    .scaleEffect(resultShown ? 1 : 2.4)
                    .opacity(resultShown ? 1 : 0)
                resultDetails(mine)
            }
            .padding(wide ? DS.Space.m : DS.Space.l)
            .frame(width: wide ? 400 : nil)
            .frame(maxWidth: wide ? nil : 380)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.1, blue: 0.2).opacity(0.82))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 2))
            )
            .padding(wide ? .trailing : .horizontal, DS.Space.l)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62).delay(0.15)) { resultShown = true }
        }
    }

    private func resultTitle(_ result: ArenaGame.Result, mine: Fighter) -> (String, Color) {
        let gold = Color(uiColor: ArenaPalette.gold)
        let lost = Color(red: 1, green: 0.42, blue: 0.38)
        if controller.story != nil {
            let stars = controller.storyReward?.stars ?? 0
            return stars > 0 ? ("过关！", gold) : ("没过关", lost)
        }
        switch result {
        case .team(let team):
            switch controller.game.mode {
            case .duo:
                let place = controller.place ?? (team == mine.team ? 1 : 3)
                return (place == 1 ? "第 1 名！" : "第 \(place) 名", place == 1 ? gold : (place == 2 ? .white : lost))
            case .boss:
                return team == mine.team ? ("打倒了骷髅王！", gold) : ("没打倒骷髅王", lost)
            default:
                return team == mine.team ? ("胜利！", gold) : ("失败", lost)
            }
        case .draw:
            return ("平局", .white)
        case .survivor:
            let place = controller.place ?? 1
            return (place == 1 ? "第 1 名！" : "第 \(place) 名", place == 1 ? gold : (place <= 3 ? .white : lost))
        }
    }

    private func resultDetails(_ mine: Fighter) -> some View {
        VStack(spacing: wide ? DS.Space.s : DS.Space.m) {
            if controller.threeHeroSample {
                Text("本地对战 · 不计排位与成长奖励").font(.caption).foregroundStyle(.white.opacity(0.75))
            }
            if let story = controller.storyReward {
                storyStars(story)
            }
            if let coins = controller.rankedCoins {
                rankedRow(coins)
            }
            if let reward = controller.reward {
                HStack(spacing: DS.Space.l) {
                    HStack(spacing: 6) {
                        Image(systemName: "trophy.fill").foregroundStyle(.orange)
                        ArenaCountUp(value: reward.trophies, signed: true)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "dollarsign.circle.fill").foregroundStyle(.yellow)
                        ArenaCountUp(value: reward.coins, signed: true)
                    }
                }
                .font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .arenaOutline(1.2)
                if !reward.unlocked.isEmpty {
                    Text("解锁了" + reward.unlocked.map(\.name).joined(separator: "、") + "！")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(Color(uiColor: ArenaPalette.myName))
                        .arenaOutline(1)
                }
            }
            if let star = controller.starPlayer, controller.game.fighters.indices.contains(star) {
                starPlayer(controller.game.fighters[star])
            }
            HStack(spacing: DS.Space.l) {
                stat("打倒", mine.kills)
                stat("被打倒", mine.deaths)
                stat("伤害", mine.damageDealt)
            }
            if let gain = controller.seasonGain {
                seasonRow(gain)
            }
            HStack(spacing: DS.Space.s) {
                if let onAgain {
                    Button(controller.story == nil ? "再来一局" : "再打一次") { onAgain() }
                        .buttonStyle(ArenaGameButton.yellow)
                    Button(controller.story == nil ? "回大厅" : "回冒险") { onExit() }
                        .buttonStyle(ArenaGameButton.blue)
                        .accessibilityIdentifier("arena.result.lobby")
                        .accessibilityValue(controller.flowEvidenceForUITest)
                } else {
                    Button("回房间") { onExit() }
                        .buttonStyle(ArenaGameButton.yellow)
                }
            }
        }
    }

    /// 冒险：三颗星一颗颗亮起来，下面是这一关的要求、给的金币、投奔过来的骷髅
    private func storyStars(_ reward: ArenaStory.Reward) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { k in
                    Image(systemName: "star.fill")
                        .font(.system(size: k == 1 ? 40 : 32, weight: .black))
                        .foregroundStyle(k < reward.stars ? Color(uiColor: ArenaPalette.gold) : Color.white.opacity(0.18))
                        .arenaOutline(1.5)
                        .offset(y: k == 1 ? -6 : 0)
                        .scaleEffect(resultShown || k >= reward.stars ? 1 : 0.2)
                        .animation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.35 + Double(k) * 0.25), value: resultShown)
                }
            }
            if let level = controller.story {
                Text("赢下这一关 · 一次没被打倒 · " + level.goal.note)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
            if reward.coins > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle.fill").foregroundStyle(.yellow)
                    ArenaCountUp(value: reward.coins, signed: true)
                }
                .font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .arenaOutline(1.2)
            }
            if !reward.recruited.isEmpty {
                Text(reward.recruited.map(\.name).joined(separator: "、") + "加入了勇者们！")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(Color(uiColor: ArenaPalette.myName))
                    .arenaOutline(1)
            }
        }
    }

    /// 排位：加减了多少排位分、现在什么段，升段了大字写出来；金币照给
    private func rankedRow(_ coins: Int) -> some View {
        let points = ArenaProgressStore.shared.progress.season.rankPoints
        let tier = ArenaRank.tiers[ArenaRank.tier(points)]
        let change = controller.seasonGain?.rankChange ?? 0
        return VStack(spacing: 4) {
            if controller.seasonGain?.promoted == true {
                Text("升到\(tier.name)段了！")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(Color(uiColor: ArenaPalette.gold))
                    .arenaOutline(1.4)
            }
            HStack(spacing: DS.Space.l) {
                Label("\(tier.name) \(points)（\(change >= 0 ? "+" : "")\(change)）", systemImage: "shield.lefthalf.filled")
                    .foregroundStyle(change >= 0 ? Color(uiColor: ArenaPalette.myName) : Color(red: 1, green: 0.5, blue: 0.45))
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle.fill").foregroundStyle(.yellow)
                    ArenaCountUp(value: coins, signed: true)
                }
                .foregroundStyle(.white)
            }
            .font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
            .arenaOutline(1)
        }
    }

    /// 赛季：这局给的经验、做完的任务
    private func seasonRow(_ gain: ArenaSeasonGain) -> some View {
        VStack(spacing: 2) {
            Text("赛季经验 +\(gain.points)")
                .font(.system(size: 14, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(Color(red: 0.75, green: 0.85, blue: 1))
            ForEach(gain.quests) { quest in
                Label("完成任务：\(quest.title)", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(uiColor: ArenaPalette.myName))
            }
        }
    }

    /// 全场最佳：头像、名字、打倒几个、伤害（是自己就金边）
    private func starPlayer(_ fighter: Fighter) -> some View {
        let isMe = fighter.id == controller.me
        return HStack(spacing: DS.Space.s) {
            BrawlerBadge(brawler: fighter.brawler, size: 44)
                .overlay(Circle().strokeBorder(Color(uiColor: ArenaPalette.gold), lineWidth: 3))
                .overlay(alignment: .top) { Text("👑").font(.system(size: 16)).offset(y: -12) }
            VStack(alignment: .leading, spacing: 1) {
                Text("全场最佳")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(Color(uiColor: ArenaPalette.gold))
                Text(isMe ? "我" : fighter.name)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("打倒 \(fighter.kills) · 伤害 \(fighter.damageDealt)")
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(isMe ? 0.16 : 0.08)))
    }

    private func stat(_ name: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            Text(name).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.7))
        }
    }
}

/// Arena-owned modal: the match keeps running, while controls and accessibility
/// behind the scrim are blocked. Disconnect takes precedence over confirmation.
private struct ArenaMatchDialog: View {
    let disconnected: Bool
    let onContinue: () -> Void
    let onExit: () -> Void
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {} // Only explicit actions dismiss this modal.
                .accessibilityHidden(true)
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: disconnected ? "wifi.slash" : "door.left.hand.open")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(Color.yellow)
                    Text(disconnected ? "连接已断开" : "退出这一局？")
                        .font(.system(size: 25, weight: .heavy, design: .rounded))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($titleFocused)
                }
                Text(disconnected ? "与房主的连接已断开，请返回房间。" : "对局仍在进行，确定要离开吗？")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    if !disconnected {
                        action("接着打", face: Color(red: 0.18, green: 0.52, blue: 0.92),
                               edge: Color(red: 0.08, green: 0.24, blue: 0.52), perform: onContinue)
                    }
                    action(disconnected ? "返回" : "退出对局",
                           face: disconnected ? Color(red: 0.95, green: 0.66, blue: 0.1) : Color(red: 0.78, green: 0.22, blue: 0.3),
                           edge: Color(red: 0.36, green: 0.12, blue: 0.2), perform: onExit)
                }
            }
            .foregroundStyle(.white)
            .padding(22)
            .frame(maxWidth: 420)
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 0.09, green: 0.18, blue: 0.4))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(red: 0.3, green: 0.57, blue: 0.9), lineWidth: 3))
                    .shadow(color: .black.opacity(0.45), radius: 0, x: 0, y: 7)
            }
            .padding(20)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) {
                if !disconnected { onContinue() }
            }
        }
        .onAppear { titleFocused = true }
        .onChange(of: disconnected) { _ in titleFocused = true }
    }

    private func action(_ title: String, face: Color, edge: Color, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(ArenaTileButton(face: face, edge: edge))
    }
}

extension View {
    /// 卡通游戏里那种粗字：底下一道硬黑影，外面一圈淡淡的黑边
    func arenaInk() -> some View {
        shadow(color: .black.opacity(0.85), radius: 0, x: 0, y: 1.5)
            .shadow(color: .black.opacity(0.6), radius: 1)
    }

    /// 大标题：四面一圈黑边，底下再压一道黑影
    func arenaOutline(_ width: CGFloat = 2) -> some View {
        shadow(color: .black, radius: 0, x: width, y: width)
            .shadow(color: .black, radius: 0, x: -width, y: -width)
            .shadow(color: .black, radius: 0, x: width, y: -width)
            .shadow(color: .black, radius: 0, x: -width, y: width)
            .shadow(color: .black.opacity(0.55), radius: 0, x: 0, y: width * 1.6)
    }
}

/// 游戏里那种厚按钮：底下一条深色的边，按下去往下沉
struct ArenaGameButton: ButtonStyle {
    let face: Color
    let edge: Color
    var height: CGFloat = 46

    /// 黄色（开打、再来一局）、蓝色、绿色（升级）
    static let yellow = ArenaGameButton(face: Color(red: 1, green: 0.76, blue: 0.12), edge: Color(red: 0.72, green: 0.45, blue: 0.02))
    static let blue = ArenaGameButton(face: Color(red: 0.26, green: 0.6, blue: 1), edge: Color(red: 0.1, green: 0.33, blue: 0.72))
    static let green = ArenaGameButton(face: Color(red: 0.36, green: 0.82, blue: 0.24), edge: Color(red: 0.16, green: 0.5, blue: 0.1))

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: height * 0.39, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .arenaOutline(height > 50 ? 1.8 : 1.2)
            .padding(.horizontal, 22)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(face)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.28))
                            .frame(height: 14).padding(.horizontal, 5).padding(.top, 4)
                    }
            )
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.black.opacity(0.75), lineWidth: 2))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(edge)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.black.opacity(0.75), lineWidth: 2))
                    .offset(y: configuration.isPressed ? 1 : 5)
            )
            .offset(y: configuration.isPressed ? 4 : 0)
            .padding(.bottom, 5)
    }
}

/// 数字从 0 涨到这个数（奖杯、金币）
private struct ArenaCountUp: View {
    let value: Int
    var signed = false
    @State private var shown = 0

    var body: some View {
        Text((signed && value >= 0 ? "+" : "") + "\(shown)")
            .task(id: value) {
                let steps = 18
                for k in 1...steps {
                    try? await Task.sleep(nanoseconds: 45_000_000)
                    shown = Int((Double(value) * Double(k) / Double(steps)).rounded())
                }
            }
    }
}

// MARK: - 开场对阵

/// 开场对阵：自己这队在左边（竖着的在上边）、对面在右边，蓝红斜着分开，中间一个大 VS，上面写玩法和地图
private struct ArenaVersus: View {
    let game: ArenaGame
    let me: Int
    /// 上面的大字：玩法（冒险是这一关的名字）
    let title: String
    @State private var shown = false

    var body: some View {
        let team = game.fighters[me].team
        let allies = game.fighters.filter { $0.team == team }
        let enemies = game.fighters.filter { $0.team != team }
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            let size: CGFloat = max(allies.count, enemies.count) > 3 ? 48 : 62
            ZStack {
                Color(uiColor: ArenaPalette.red)
                VersusSlant(wide: wide, edgeOnly: false).fill(Color(uiColor: ArenaPalette.blue))
                VersusSlant(wide: wide, edgeOnly: true).stroke(.white.opacity(0.9), lineWidth: 7)
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .arenaOutline(2)
                    Text(game.map.title)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .arenaOutline(1)
                    Spacer()
                }
                .padding(.top, wide ? 14 : 60)
                if wide {
                    HStack(spacing: 0) {
                        side(allies, columns: true, size: size)
                            .frame(maxWidth: .infinity)
                            .offset(x: shown ? 0 : -geo.size.width / 2)
                        versus
                        side(enemies, columns: true, size: size)
                            .frame(maxWidth: .infinity)
                            .offset(x: shown ? 0 : geo.size.width / 2)
                    }
                    .padding(.top, 40)
                } else {
                    VStack(spacing: DS.Space.l) {
                        side(allies, columns: false, size: size)
                            .offset(y: shown ? 0 : -geo.size.height / 2)
                        versus
                        side(enemies, columns: false, size: size)
                            .offset(y: shown ? 0 : geo.size.height / 2)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.74)) { shown = true }
        }
    }

    private var versus: some View {
        Text("VS")
            .font(.system(size: 88, weight: .black, design: .rounded))
            .foregroundStyle(Color(uiColor: ArenaPalette.gold))
            .arenaOutline(3.5)
            .rotationEffect(.degrees(-8))
            .scaleEffect(shown ? 1 : 2.8)
            .opacity(shown ? 1 : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.5).delay(0.25), value: shown)
    }

    /// 一边的人：横屏一列 3 个（多了排两列），竖屏一行 3 个
    @ViewBuilder private func side(_ list: [Fighter], columns: Bool, size: CGFloat) -> some View {
        let groups = stride(from: 0, to: list.count, by: 3).map { Array(list[$0..<min($0 + 3, list.count)]) }
        if columns {
            HStack(alignment: .top, spacing: DS.Space.m) {
                ForEach(groups.indices, id: \.self) { k in
                    VStack(spacing: DS.Space.s) {
                        ForEach(groups[k]) { card($0, size: size) }
                    }
                }
            }
        } else {
            VStack(spacing: DS.Space.s) {
                ForEach(groups.indices, id: \.self) { k in
                    HStack(spacing: DS.Space.m) {
                        ForEach(groups[k]) { card($0, size: size) }
                    }
                }
            }
        }
    }

    private func card(_ fighter: Fighter, size: CGFloat) -> some View {
        VStack(spacing: 1) {
            BrawlerBadge(brawler: fighter.brawler, size: size)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
            Text(fighter.id == me ? "我" : fighter.name)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(fighter.id == me ? Color(uiColor: ArenaPalette.myName) : .white)
                .arenaOutline(1)
                .lineLimit(1)
            Text(fighter.isBoss ? "首领" : "\(fighter.level) 级")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(width: size + 34)
    }
}

/// 对阵画面蓝红分开的那道斜线（edgeOnly：只要那条线）
private struct VersusSlant: Shape {
    let wide: Bool
    let edgeOnly: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let a = wide ? CGPoint(x: rect.width * 0.56, y: 0) : CGPoint(x: rect.width, y: rect.height * 0.46)
        let b = wide ? CGPoint(x: rect.width * 0.44, y: rect.height) : CGPoint(x: 0, y: rect.height * 0.54)
        if edgeOnly {
            path.move(to: a)
            path.addLine(to: b)
            return path
        }
        path.move(to: .zero)
        if wide {
            path.addLine(to: a)
            path.addLine(to: b)
            path.addLine(to: CGPoint(x: 0, y: rect.height))
        } else {
            path.addLine(to: CGPoint(x: rect.width, y: 0))
            path.addLine(to: a)
            path.addLine(to: b)
        }
        path.closeSubpath()
        return path
    }
}

/// 摇杆：按住拖动，松手时告诉外面拖到了哪（长度 0–1）
private struct ArenaStick: View {
    enum Kind: Equatable {
        case move, attack
        /// charge：大招攒了多少；hyper：超级充能攒了多少（没解锁 nil）；hyperTime：超级充能开着还剩几秒
        case special(charge: Double, hyper: Double?, hyperTime: Double)
    }

    let kind: Kind
    var onChange: (V2) -> Void
    var onRelease: (V2) -> Void
    @State private var offset: CGSize = .zero
    @State private var active = false

    private var controlName: String {
        switch kind {
        case .move: return "move"
        case .attack: return "attack"
        case .special: return "special"
        }
    }

    private var radius: CGFloat {
        switch kind {
        case .move: return 64
        case .attack: return 58
        case .special: return 42
        }
    }

    private var ready: Bool {
        if case .special(let charge, _, _) = kind { return charge >= 1 }
        return true
    }

    /// 大招满了、超级充能也满了：这一下是加强版（钮变紫）
    private var hyperReady: Bool {
        if case .special(_, let hyper?, _) = kind { return hyper >= 1 }
        return false
    }

    private var tint: Color {
        switch kind {
        case .move: return .white
        case .attack: return Color(uiColor: ArenaPalette.attack)
        case .special: return ready ? (hyperReady ? Color(uiColor: ArenaPalette.hyper) : .yellow) : .gray
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(active ? 0.3 : 0.18))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 2))
            if case .special(let charge, let hyper, let hyperTime) = kind {
                Circle().trim(from: 0, to: min(charge, 1))
                    .stroke(ready ? Color.white : Color.yellow, style: StrokeStyle(lineWidth: ready ? 8 : 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(ready ? 1 : 3)
                if ready {
                    Circle().stroke(Color.yellow, lineWidth: 3).padding(-4)
                }
                // 外面一圈紫的：超级充能攒了多少；开着的时候是还剩多久
                if let hyper {
                    Circle().trim(from: 0, to: hyperTime > 0 ? min(hyperTime / ArenaGame.hyperDuration, 1) : min(hyper, 1))
                        .stroke(Color(uiColor: ArenaPalette.hyper), style: StrokeStyle(lineWidth: hyperTime > 0 ? 6 : 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(-7)
                }
            }
            Circle().fill(tint.opacity(kind == .move ? 0.75 : 0.95))
                .frame(width: radius * 0.8, height: radius * 0.8)
                .overlay(icon)
                .offset(offset)
        }
        .frame(width: radius * 2, height: radius * 2)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("arena.control.\(controlName)")
        .accessibilityLabel(controlName == "move" ? "移动" : (controlName == "attack" ? "普通攻击" : "大招"))
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    active = true
                    offset = clamp(value.translation)
                    onChange(vector(offset))
                }
                .onEnded { value in
                    let final = clamp(value.translation)
                    onRelease(vector(final))
                    offset = .zero
                    active = false
                }
        )
        .allowsHitTesting(ready)
        .opacity(ready ? 1 : 0.6)
    }

    @ViewBuilder private var icon: some View {
        switch kind {
        case .move: EmptyView()
        case .attack: Image(systemName: "scope").font(.title2.weight(.bold)).foregroundStyle(.white)
        case .special: Image(systemName: "bolt.fill").font(.title3.weight(.bold)).foregroundStyle(ready && !hyperReady ? .black : .white)
        }
    }

    private func clamp(_ translation: CGSize) -> CGSize {
        let length = (translation.width * translation.width + translation.height * translation.height).squareRoot()
        guard length > radius else { return translation }
        return CGSize(width: translation.width / length * radius, height: translation.height / length * radius)
    }

    private func vector(_ size: CGSize) -> V2 {
        V2(Double(size.width / radius), Double(size.height / radius))
    }
}

/// 小道具钮：绿色圆钮，写着还能用几次；用完一次灰着倒数几秒
private struct ArenaGadgetButton: View {
    let gadget: Gadget
    let uses: Int
    let cooldown: Int
    let dead: Bool
    var action: () -> Void

    private var ready: Bool { uses > 0 && cooldown == 0 && !dead }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color(uiColor: ArenaPalette.gadget).opacity(ready ? 0.95 : 0.35))
                Circle().strokeBorder(Color.white.opacity(ready ? 0.85 : 0.4), lineWidth: 2.5)
                Text(gadget.emoji).font(.system(size: 22)).opacity(ready ? 1 : 0.45)
                if cooldown > 0 && uses > 0 {
                    Text("\(cooldown)")
                        .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .arenaInk()
                }
            }
            .frame(width: 54, height: 54)
            .overlay(alignment: .topTrailing) {
                Text("\(uses)")
                    .font(.system(size: 12, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(uses > 0 ? Color.black.opacity(0.7) : Color(uiColor: ArenaPalette.attack)))
                    .offset(x: 3, y: -3)
            }
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .accessibilityLabel("小道具：\(gadget.name)，还能用 \(uses) 次")
    }
}

/// 选这个角色带的本事：两个小道具里选一个（3、5 级解锁）、两个星徽里选一个（6、8 级解锁），满级有超级充能
struct ArenaLoadoutSection: View {
    let brawler: Brawler
    /// 改了选的（联机房间里要告诉大家）
    var onChange: @MainActor () -> Void = {}
    var gameStyle = false
    @ObservedObject private var growth = ArenaProgressStore.shared

    var body: some View {
        Group {
            if gameStyle {
                VStack(alignment: .leading, spacing: 10) { choices }
                    .buttonStyle(.plain)
                    .environment(\.colorScheme, .dark)
            } else { choices }
        }
    }

    private var choices: some View {
        let progress = growth.progress
        let level = progress.level(brawler)
        let loadout = progress.loadout(for: brawler)
        return Section {
            ForEach(brawler.gadgets.indices, id: \.self) { k in
                let gadget = brawler.gadgets[k]
                let needs = ArenaProgress.gadgetLevels[k]
                Button {
                    growth.choose(gadget, for: brawler)
                    onChange()
                } label: {
                    row(badge: Text(gadget.emoji).font(.system(size: 20)), tint: Color(uiColor: ArenaPalette.gadget),
                        title: "小道具 · \(gadget.name)", note: gadget.note, chosen: loadout.gadget == gadget,
                        locked: level < needs ? needs : nil)
                }
                .disabled(level < needs)
            }
            ForEach(brawler.starPowers.indices, id: \.self) { k in
                let star = brawler.starPowers[k]
                let needs = ArenaProgress.starLevels[k]
                Button {
                    growth.choose(star, for: brawler)
                    onChange()
                } label: {
                    row(badge: Image(systemName: "star.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white),
                        tint: Color(uiColor: ArenaPalette.gold), title: "星徽 · \(star.name)", note: star.note,
                        chosen: loadout.starPower == star, locked: level < needs ? needs : nil)
                }
                .disabled(level < needs)
            }
            row(badge: Image(systemName: "bolt.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white),
                tint: Color(uiColor: ArenaPalette.hyper), title: "超级充能", note: "攒满紫条再放大招：" + brawler.hyperNote,
                chosen: loadout.hypercharge, locked: loadout.hypercharge ? nil : ArenaProgress.hyperLevel)
        } header: {
            Text("\(brawler.name)带的本事")
        } footer: {
            Text("小道具一局能用 \(ArenaGame.gadgetUses) 次，用完一次等 \(Int(ArenaGame.gadgetCooldown)) 秒；星徽一直有效；"
                 + "超级充能 5 秒里走得快、打得疼、挨打少掉血。")
        }
    }

    private func row(badge: some View, tint: Color, title: String, note: String, chosen: Bool, locked: Int?) -> some View {
        HStack(spacing: DS.Space.s) {
            Circle().fill(tint.opacity(locked == nil ? 1 : 0.35))
                .frame(width: 38, height: 38)
                .overlay(badge.opacity(locked == nil ? 1 : 0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(gameStyle ? .system(size: 16, weight: .heavy, design: .rounded) : DS.Font.headline).foregroundStyle(locked == nil ? .primary : .secondary)
                Text(note).font(gameStyle ? .system(size: 13, weight: .semibold, design: .rounded) : DS.Font.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let locked {
                Label("\(locked) 级", systemImage: "lock.fill").font(gameStyle ? .system(size: 13, weight: .semibold, design: .rounded) : DS.Font.caption).foregroundStyle(.secondary)
            } else if chosen {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.Palette.accent)
            }
        }
        .padding(gameStyle ? 12 : 0)
        .background(gameStyle ? Color.white.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .opacity(locked == nil ? 1 : 0.65)
    }
}
