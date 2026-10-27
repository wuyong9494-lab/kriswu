import SwiftUI
import UIKit

// MARK: - 选玩法、选角色

/// 勇者乱斗：斜着往下看的 3D 小地图，左手摇杆走、右手摇杆瞄准开火（点一下自动瞄最近的敌人），大招攒满了上面那个钮亮起来
struct ArenaHomeView: View {
    @ObservedObject private var records = ArenaRecords.shared
    @ObservedObject private var growth = ArenaProgressStore.shared
    @State private var mode = ArenaGame.Mode(rawValue: UserDefaults.standard.string(forKey: "arena.mode") ?? "") ?? .teamFight
    @State private var brawler = Brawler(rawValue: UserDefaults.standard.integer(forKey: "arena.brawler")) ?? .knight
    @State private var playing: ArenaEntry?
    @State private var lobby: LobbyEntry?
    @EnvironmentObject private var store: AppStore

    struct LobbyEntry: Identifiable {
        let id = UUID()
        let lobby: ArenaLobby
    }

    struct ArenaEntry: Identifiable {
        let id = UUID()
        let setup: ArenaController.Setup
    }

    private var progress: ArenaProgress { growth.progress }

    /// 选的角色还没解锁（比如换了一台手机）就用第一个
    private var chosen: Brawler { progress.isUnlocked(brawler) ? brawler : .knight }

    var body: some View {
        List {
            progressSection
            Section {
                ForEach(ArenaGame.Mode.allCases, id: \.self) { item in
                    Button {
                        mode = item
                        UserDefaults.standard.set(item.rawValue, forKey: "arena.mode")
                    } label: {
                        modeRow(item)
                    }
                }
            } header: {
                Text("玩法")
            }
            Section {
                ForEach(Brawler.allCases, id: \.self) { item in
                    Button {
                        brawler = item
                        UserDefaults.standard.set(item.rawValue, forKey: "arena.brawler")
                    } label: {
                        brawlerRow(item)
                    }
                    .disabled(!progress.isUnlocked(item))
                }
            } header: {
                Text("角色")
            } footer: {
                Text("每升一级血量、伤害多 6%，最高 \(ArenaProgress.maxLevel) 级；联机时电脑补位的按大家的平均等级。")
            }
            upgradeSection
            Section {
                Button {
                    playing = ArenaEntry(setup: ArenaController.Setup(mode: mode, brawler: chosen, name: store.settings.aliases.first ?? "我",
                                                                      level: progress.level(chosen)))
                } label: {
                    Label("开打（人不够电脑补位）", systemImage: "play.fill")
                        .font(DS.Font.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            } footer: {
                Text("左下角摇杆走；右下角摇杆拖着瞄准、松手开火，点一下自动打最近的敌人；上面黄圈满了放大招。躲进草丛里敌人看不见你（离得很近或者你开火时除外）。")
            }
            GameRoomButtons(kind: .arena, remotePlayers: 2...6, nearbyCapacity: 6) { room in
                lobby = LobbyEntry(lobby: ArenaLobby(room: room, mode: mode, brawler: chosen))
            }
        }
        .appList()
        .navigationTitle("勇者乱斗")
        // 先在后台把 3D 模型读好、画好头像，开打时不用等
        .task { await ArenaPortraits.shared.prepare() }
        .fullScreenCover(item: $playing) { entry in
            ArenaPlayView(setup: entry.setup)
        }
        .fullScreenCover(item: $lobby) { entry in
            ArenaRoomView(lobby: entry.lobby)
        }
    }

    private func modeRow(_ item: ArenaGame.Mode) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s) {
            Image(systemName: mode == item ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(mode == item ? DS.Palette.accent : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.title).font(DS.Font.headline).foregroundStyle(.primary)
                    Spacer()
                    if let played = records.tally.played[item.rawValue] {
                        Text("赢了 \(records.tally.won[item.rawValue] ?? 0)/\(played)").font(DS.Font.caption).foregroundStyle(.secondary)
                    }
                }
                Text(item.rules).font(DS.Font.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func brawlerRow(_ item: Brawler) -> some View {
        let unlocked = progress.isUnlocked(item)
        let level = progress.level(item)
        return HStack(spacing: DS.Space.s) {
            BrawlerBadge(brawler: item, size: 56, selected: chosen == item)
                .overlay(alignment: .bottomTrailing) {
                    if !unlocked {
                        Image(systemName: "lock.fill").font(.caption.weight(.bold)).foregroundStyle(.white)
                            .padding(5).background(Circle().fill(.black.opacity(0.6)))
                    }
                }
                .opacity(unlocked ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).font(DS.Font.headline).foregroundStyle(.primary)
                    Text(item.role).font(DS.Font.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(DS.Palette.surfaceSunken))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if unlocked {
                        Text("\(level) 级").font(DS.Font.caption.weight(.semibold).monospacedDigit()).foregroundStyle(DS.Palette.accent)
                    }
                }
                if unlocked {
                    HStack(spacing: DS.Space.s) {
                        Label("\(progress.trophies(item))", systemImage: "trophy.fill").foregroundStyle(.orange)
                        Text("血 \(item.health(level: level))").foregroundStyle(.secondary)
                    }
                    .font(DS.Font.caption.monospacedDigit())
                } else {
                    Text("总奖杯到 \(item.unlockAt) 解锁").font(DS.Font.caption).foregroundStyle(.secondary)
                }
                Text(item.attackNote + "。" + item.superNote).font(DS.Font.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 奖杯、金币、升级

    private var progressSection: some View {
        Section {
            HStack(spacing: DS.Space.l) {
                Label("\(progress.totalTrophies)", systemImage: "trophy.fill")
                    .foregroundStyle(.orange)
                Label("\(progress.coins)", systemImage: "dollarsign.circle.fill")
                    .foregroundStyle(.yellow)
                Spacer()
            }
            .font(DS.Font.title.monospacedDigit())
            if let next = progress.nextMilestone {
                let start = ArenaProgress.road.last { $0.trophies <= max(progress.totalTrophies, progress.reached) }?.trophies ?? 0
                VStack(alignment: .leading, spacing: 6) {
                    Text(next.brawler.map { "总奖杯到 \(next.trophies) 解锁\($0.name)" } ?? "总奖杯到 \(next.trophies) 得 \(next.coins) 金币")
                        .font(DS.Font.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(min(max(progress.totalTrophies - start, 0), next.trophies - start)),
                                 total: Double(max(next.trophies - start, 1)))
                        .tint(.orange)
                }
            }
            NavigationLink {
                ArenaTrophyRoad()
            } label: {
                Label("奖杯之路", systemImage: "flag.checkered")
            }
        } footer: {
            Text("赢一局这个角色 +8 杯，输了 -3（不到 30 杯不扣）；大乱斗按名次。每局都给金币，金币用来升级角色。")
        }
    }

    @ViewBuilder private var upgradeSection: some View {
        let level = progress.level(chosen)
        Section {
            if let cost = progress.upgradeCost(chosen) {
                Button {
                    growth.upgrade(chosen)
                } label: {
                    HStack {
                        Label("\(chosen.name)升到 \(level + 1) 级", systemImage: "arrow.up.circle.fill")
                        Spacer()
                        Label("\(cost)", systemImage: "dollarsign.circle.fill")
                            .foregroundStyle(progress.coins >= cost ? Color.yellow : Color.secondary)
                    }
                }
                .disabled(progress.coins < cost)
            } else {
                Label("\(chosen.name)已经满级了", systemImage: "checkmark.seal.fill").foregroundStyle(.secondary)
            }
        } footer: {
            Text("升级后血 \(chosen.health(level: level)) → \(chosen.health(level: min(level + 1, ArenaProgress.maxLevel)))，伤害同样多 6%。")
        }
    }
}

/// 奖杯之路：总奖杯到了哪个点给什么
struct ArenaTrophyRoad: View {
    @ObservedObject private var growth = ArenaProgressStore.shared

    var body: some View {
        let reached = max(growth.progress.totalTrophies, growth.progress.reached)
        List {
            Section {
                ForEach(ArenaProgress.road, id: \.trophies) { point in
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: point.trophies <= reached ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(point.trophies <= reached ? DS.Palette.success : .secondary)
                        Label("\(point.trophies)", systemImage: "trophy.fill")
                            .font(DS.Font.headline.monospacedDigit())
                            .foregroundStyle(.orange)
                            .frame(width: 90, alignment: .leading)
                        if let brawler = point.brawler {
                            BrawlerBadge(brawler: brawler, size: 32)
                            Text("解锁\(brawler.name)")
                        } else {
                            Label("\(point.coins) 金币", systemImage: "dollarsign.circle.fill")
                        }
                        Spacer()
                    }
                }
            } footer: {
                Text("所有角色的奖杯加起来算。奖杯掉了再涨回来，已经给过的奖励不重复给。")
            }
        }
        .appList()
        .navigationTitle("奖杯之路")
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
            ArenaOrientation.releaseAll()
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

private struct ArenaLandscape: ViewModifier {
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
    @Environment(\.dismiss) private var dismiss

    init(lobby: ArenaLobby) {
        self.lobby = lobby
        room = lobby.room
    }

    var body: some View {
        NavigationStack {
            List {
                GameRoomLobby(room: room) {
                    Section {
                        HStack(spacing: DS.Space.xs) {
                            ForEach(Brawler.allCases, id: \.self) { brawler in
                                Button {
                                    lobby.choose(brawler)
                                } label: {
                                    BrawlerBadge(brawler: brawler, size: 50, selected: lobby.myPick == brawler)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } header: {
                        Text("我用 \(lobby.myPick.name)（\(lobby.myPick.role)）")
                    }
                    Section {
                        ForEach(room.members) { member in
                            HStack {
                                if let pick = lobby.pick(of: member.id) {
                                    BrawlerBadge(brawler: pick, size: 30)
                                } else {
                                    Text("❔").frame(width: 30)
                                }
                                Text(member.id == room.me.id ? "\(member.name)（我）" : member.name)
                                Text("\(lobby.level(of: member.id)) 级").font(DS.Font.caption.monospacedDigit()).foregroundStyle(.secondary)
                                Spacer()
                                if member.id == room.hostID { Text("房主").font(DS.Font.caption).foregroundStyle(.secondary) }
                            }
                        }
                    } header: {
                        Text("谁用什么")
                    } footer: {
                        Text(lobby.mode.isTeams ? "按进房间的先后轮流分到两队，每队不够 3 个人电脑补。" : "各打各的，不够 6 个人电脑补。")
                    }
                    Section {
                        if room.isHost {
                            Picker("玩法", selection: Binding(get: { lobby.mode }, set: { lobby.choose($0) })) {
                                ForEach(ArenaGame.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            Button {
                                lobby.start()
                            } label: {
                                Label("开打（\(room.members.count) 个人）", systemImage: "play.fill").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(room.members.count < 2)
                        } else {
                            LabeledContent("玩法", value: lobby.mode.title)
                            Text("等房主开打，开了自动进去。").foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text(lobby.mode.rules)
                    }
                }
            }
            .appList()
            .navigationTitle(room.code == nil ? "面对面乱斗" : "远程乱斗")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("离开") {
                        room.leave()
                        dismiss()
                    }
                }
            }
        }
        .onAppear { room.start() }
        .fullScreenCover(item: $lobby.playing) { playing in
            ArenaMatchView(controller: playing.controller, onAgain: nil, onExit: {
                ArenaOrientation.releaseAll()
                lobby.playing = nil
            })
            .modifier(ArenaLandscape())
        }
    }
}

private struct ArenaMatchView: View {
    @ObservedObject var controller: ArenaController
    /// 和电脑打才有「再来一局」；联机的回房间等房主再开
    var onAgain: (() -> Void)?
    var onExit: () -> Void
    @State private var confirmingExit = false
    @AppStorage(ArenaSound.muteKey) private var muted = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// iPhone 横着打（上下矮）：摇杆、结算卡片换成横的摆法
    private var wide: Bool { verticalSizeClass == .compact }

    /// 在上边那一队的人：画面倒过来（自己的家总在下边），摇杆也跟着反过来
    private var flip: Double { controller.game.mode.isTeams && controller.mine.team == 1 ? -1 : 1 }

    private var hud: ArenaController.HUD { controller.hud }

    var body: some View {
        ZStack {
            ArenaWorld(controller: controller)
                .ignoresSafeArea()
            VStack(spacing: DS.Space.xs) {
                topBar
                banner
                Spacer()
                controls
            }
            if hud.dead && hud.result == nil && controller.game.mode.isTeams {
                Text("\(hud.respawnIn) 秒后复活")
                    .font(DS.Font.title)
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.l)
                    .padding(.vertical, DS.Space.s)
                    .background(.black.opacity(0.45), in: Capsule())
            }
            if controller.disconnected && hud.result == nil {
                VStack(spacing: DS.Space.s) {
                    Text("和房主断开了").font(DS.Font.title)
                    Button("退出") { onExit() }.buttonStyle(.borderedProminent)
                }
                .padding(DS.Space.l)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.xl))
            }
            if let result = hud.result { resultCard(result) }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .confirmationDialog("退出这一局？", isPresented: $confirmingExit, titleVisibility: .visible) {
            Button("退出", role: .destructive) { onExit() }
            Button("接着打", role: .cancel) {}
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
                ArenaSound.shared.muteChanged()
            } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.subheadline).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.35), in: Circle())
            }
            Spacer()
            score
            Spacer()
            Text(String(format: "%d:%02d", hud.timeLeft / 60, hud.timeLeft % 60))
                .font(DS.Font.callout.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 52, height: 36)
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
        case .showdown:
            Text("剩 \(hud.alive) 个人")
                .font(DS.Font.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, DS.Space.m)
                .frame(height: 36)
                .background(.black.opacity(0.35), in: Capsule())
        }
    }

    private func versus(_ blue: String, _ red: String, note: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                Text(blue).frame(minWidth: 52).padding(.vertical, 4).background(Color(uiColor: ArenaPalette.blue))
                Text(red).frame(minWidth: 52).padding(.vertical, 4).background(Color(uiColor: ArenaPalette.red))
            }
            .font(DS.Font.headline.monospacedDigit())
            .foregroundStyle(.white)
            .clipShape(Capsule())
            Text(note).font(DS.Font.overline).foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.5), radius: 2)
        }
    }

    @ViewBuilder private var banner: some View {
        if let team = hud.countdownTeam {
            Text(team == controller.mine.team ? "守住 \(hud.countdownLeft) 秒就赢了！" : "对方再守 \(hud.countdownLeft) 秒就赢了，快抢！")
                .font(DS.Font.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, DS.Space.m)
                .padding(.vertical, 6)
                .background((team == controller.mine.team ? Color(uiColor: ArenaPalette.blue) : Color(uiColor: ArenaPalette.red)).opacity(0.85),
                            in: Capsule())
        } else if hud.poisonShrinking {
            Text("毒圈在缩小，待在圈里").font(DS.Font.caption).foregroundStyle(.white)
                .padding(.horizontal, DS.Space.s).padding(.vertical, 4)
                .background(Color.green.opacity(0.6), in: Capsule())
        } else if controller.game.mode.duration - Double(hud.timeLeft) < 3 {
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
            ArenaStick(kind: .move, onChange: { controller.move = $0 * flip }, onRelease: { _ in controller.move = .zero })
            Spacer()
            // 横屏：大招钮在攻击钮左上；竖屏：在攻击钮上面
            if wide {
                HStack(alignment: .bottom, spacing: DS.Space.m) {
                    superStick.padding(.bottom, 44)
                    attackStick
                }
            } else {
                VStack(alignment: .trailing, spacing: DS.Space.s) {
                    superStick
                    attackStick
                }
            }
        }
        .padding(.horizontal, wide ? DS.Space.m : DS.Space.l)
        .padding(.bottom, wide ? DS.Space.s : DS.Space.m)
        .opacity(hud.result == nil ? 1 : 0)
    }

    private var superStick: some View {
        ArenaStick(kind: .special(charge: hud.superCharge),
                   onChange: { controller.superAiming = $0 * flip },
                   onRelease: { drag in
                       controller.superAiming = nil
                       controller.fireSpecial(drag * flip)
                   })
    }

    private var attackStick: some View {
        ArenaStick(kind: .attack,
                   onChange: { controller.aiming = $0 * flip },
                   onRelease: { drag in
                       controller.aiming = nil
                       controller.fire(drag * flip)
                   })
    }

    // MARK: 结果

    private func resultCard(_ result: ArenaGame.Result) -> some View {
        let mine = controller.mine
        let title: String
        let tint: Color
        switch result {
        case .team(let team):
            title = team == mine.team ? "胜利！" : "输了"
            tint = team == mine.team ? DS.Palette.success : DS.Palette.danger
        case .draw:
            title = "平局"
            tint = DS.Palette.warning
        case .survivor:
            let place = controller.place ?? 1
            title = place == 1 ? "你活到了最后！" : "第 \(place) 名"
            tint = place == 1 ? DS.Palette.success : (place <= 3 ? DS.Palette.warning : DS.Palette.danger)
        }
        let heading = VStack(spacing: DS.Space.s) {
            BrawlerBadge(brawler: mine.brawler, size: wide ? 96 : 84)
            Text(title).font(DS.Font.display).foregroundStyle(tint)
        }
        return ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            Group {
                // 横屏矮：头像、输赢在左边，奖励、按钮在右边
                if wide {
                    HStack(spacing: DS.Space.xl) {
                        heading
                        resultDetails(mine)
                    }
                } else {
                    VStack(spacing: DS.Space.m) {
                        heading
                        resultDetails(mine)
                    }
                }
            }
            .padding(DS.Space.l)
            .frame(maxWidth: wide ? 600 : 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .padding(DS.Space.l)
        }
    }

    private func resultDetails(_ mine: Fighter) -> some View {
        VStack(spacing: DS.Space.m) {
            if let reward = controller.reward {
                HStack(spacing: DS.Space.l) {
                    Label(reward.trophies >= 0 ? "+\(reward.trophies)" : "\(reward.trophies)", systemImage: "trophy.fill")
                        .foregroundStyle(.orange)
                    Label("+\(reward.coins)", systemImage: "dollarsign.circle.fill")
                        .foregroundStyle(.yellow)
                }
                .font(DS.Font.headline.monospacedDigit())
                if !reward.unlocked.isEmpty {
                    Text("解锁了" + reward.unlocked.map(\.name).joined(separator: "、") + "！")
                        .font(DS.Font.headline)
                        .foregroundStyle(DS.Palette.success)
                }
            }
            HStack(spacing: DS.Space.l) {
                stat("打倒", mine.kills)
                stat("被打倒", mine.deaths)
                stat("伤害", mine.damageDealt)
            }
            HStack(spacing: DS.Space.s) {
                if let onAgain {
                    Button("再来一局") { onAgain() }
                        .buttonStyle(.borderedProminent)
                    Button("换玩法、角色") { onExit() }
                        .buttonStyle(.bordered)
                } else {
                    Button("回房间") { onExit() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func stat(_ name: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(DS.Font.number)
            Text(name).font(DS.Font.caption).foregroundStyle(.secondary)
        }
    }
}

/// 摇杆：按住拖动，松手时告诉外面拖到了哪（长度 0–1）
private struct ArenaStick: View {
    enum Kind: Equatable {
        case move, attack
        case special(charge: Double)
    }

    let kind: Kind
    var onChange: (V2) -> Void
    var onRelease: (V2) -> Void
    @State private var offset: CGSize = .zero
    @State private var active = false

    private var radius: CGFloat {
        switch kind {
        case .move: return 64
        case .attack: return 58
        case .special: return 42
        }
    }

    private var ready: Bool {
        if case .special(let charge) = kind { return charge >= 1 }
        return true
    }

    private var tint: Color {
        switch kind {
        case .move: return .white
        case .attack: return Color(uiColor: ArenaPalette.blue)
        case .special: return ready ? .yellow : .gray
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(active ? 0.3 : 0.18))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 2))
            if case .special(let charge) = kind {
                Circle().trim(from: 0, to: min(charge, 1))
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(3)
            }
            Circle().fill(tint.opacity(kind == .move ? 0.75 : 0.95))
                .frame(width: radius * 0.8, height: radius * 0.8)
                .overlay(icon)
                .offset(offset)
        }
        .frame(width: radius * 2, height: radius * 2)
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
        case .special: Image(systemName: "bolt.fill").font(.title3.weight(.bold)).foregroundStyle(ready ? .black : .white)
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
