import SceneKit
import SwiftUI
import UIKit
import simd

// MARK: - 大厅

/// 勇者乱斗的大厅（iPhone 上横着）：中间是自己选的角色（3D，站在台子上，手指拖着能转、点一下出手），
/// 上边奖杯（点开奖杯之路）、金币、赛季等级、名字，左边「冒险」「角色」「赛季」「和同事打」，
/// 右下普通 / 排位、带的本事、玩法卡片和大大的「开打」
struct ArenaHomeView: View {
    @ObservedObject private var records = ArenaRecords.shared
    @ObservedObject private var growth = ArenaProgressStore.shared
    @State private var mode = ArenaGame.Mode(rawValue: UserDefaults.standard.string(forKey: "arena.mode") ?? "") ?? .teamFight
    @State private var brawler = Brawler(rawValue: UserDefaults.standard.integer(forKey: "arena.brawler")) ?? .knight
    @State private var playing: ArenaEntry?
    @State private var lobby: LobbyEntry?
    @State private var sheet: Sheet?
    /// 角色墙里点开的那一个（第三层：本事、攻击、大招）
    @State private var inspected: Brawler?
    /// 在「和同事打」里开的房间（面板收起来以后再进房间）
    @State private var pendingRoom: GameRoom?
    /// 冒险
    @State private var adventure = false
    /// 排位赛（只打 3v3，按段位加减排位分）
    @AppStorage("arena.ranked") private var ranked = false
    @AppStorage(ArenaSound.muteKey) private var muted = false
    @AppStorage(ArenaSound.volumeKey) private var volume = 0.7
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    struct LobbyEntry: Identifiable {
        let id = UUID()
        let lobby: ArenaLobby
    }

    struct ArenaEntry: Identifiable {
        let id = UUID()
        let setup: ArenaController.Setup
    }

    enum Sheet: String, Identifiable {
        case brawlers, modes, loadout, road, together, season, settings
        var id: String { rawValue }
    }

    private var progress: ArenaProgress { growth.progress }

    /// 选的角色还没解锁（比如换了一台手机）就用第一个
    private var chosen: Brawler { progress.isUnlocked(brawler) ? brawler : .knight }

    /// 一对一另外带的两个：解锁了的里面奖杯最多的
    private var duelPartners: [Brawler] {
        let others = Brawler.allCases.filter { $0 != chosen && progress.isUnlocked($0) }
        return Array(others.sorted {
            progress.trophies($0) != progress.trophies($1) ? progress.trophies($0) > progress.trophies($1) : $0.rawValue < $1.rawValue
        }.prefix(2))
    }

    private var name: String { store.settings.aliases.first ?? "我" }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                ArenaLobbyBackground()
                ArenaShowcase(brawler: chosen, skin: progress.skin(chosen))
                    .frame(width: min(geo.size.width * (wide ? 0.4 : 0.9), 420), height: geo.size.height * (wide ? 0.78 : 0.5))
                    .position(x: geo.size.width / 2, y: geo.size.height * (wide ? 0.47 : 0.38))
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    if wide {
                        HStack(alignment: .bottom, spacing: DS.Space.m) {
                            leftMenu
                            Spacer(minLength: 0)
                            brawlerPlate
                            Spacer(minLength: 0)
                            rightPanel
                        }
                    } else {
                        VStack(spacing: DS.Space.m) {
                            brawlerPlate
                            HStack(alignment: .bottom) {
                                leftMenu
                                Spacer(minLength: 0)
                                rightPanel
                            }
                        }
                    }
                }
                .padding(.horizontal, wide ? DS.Space.l : DS.Space.m)
                .padding(.vertical, DS.Space.s)
            }
        }
        .modifier(ArenaLandscape())
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // 先在后台把 3D 模型读好、画好头像，开打时不用等
        .task { await ArenaPortraits.shared.prepare() }
        .onAppear {
            growth.refreshSeason()
            ArenaSound.shared.enterLobby()
        }
        .onChange(of: volume) { _ in ArenaSound.shared.volumeChanged() }
        .fullScreenCover(item: $sheet, onDismiss: {
            guard let room = pendingRoom else { return }
            pendingRoom = nil
            lobby = LobbyEntry(lobby: ArenaLobby(room: room, mode: mode, brawler: chosen))
        }) { item in
            sheetContent(item)
        }
        .fullScreenCover(item: $playing, onDismiss: { ArenaSound.shared.enterLobby() }) { entry in
            ArenaPlayView(setup: entry.setup)
        }
        .fullScreenCover(item: $lobby, onDismiss: { ArenaSound.shared.enterLobby() }) { entry in
            ArenaRoomView(lobby: entry.lobby)
        }
    }

    // MARK: 上边

    private var topBar: some View {
        HStack(spacing: DS.Space.s) {
            Button {
                ArenaOrientation.releaseAll()
                ArenaSound.shared.leaveLobby()
                dismiss()
            } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.3), in: Circle())
            }
            .accessibilityLabel("离开勇者乱斗")
            Button {
                muted.toggle()
                ArenaSound.shared.muteChanged(battle: false)
            } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.3), in: Circle())
            }
            .accessibilityLabel(muted ? "打开声音" : "静音")
            Button {
                sheet = .settings
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.3), in: Circle())
            }
            .accessibilityLabel("游戏设置")
            trophyPill
            pill {
                Image(systemName: "dollarsign.circle.fill").foregroundStyle(.yellow)
                Text("\(progress.coins)")
            }
            seasonPill
            Spacer()
            pill {
                Image(systemName: "person.crop.circle.fill").foregroundStyle(.white.opacity(0.9))
                Text(name).lineLimit(1)
            }
        }
    }

    /// 奖杯：总数，下面一条走到奖杯之路下一个点的进度（点一下看奖杯之路）
    private var trophyPill: some View {
        Button {
            sheet = .road
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(progress.totalTrophies)")
                    if let next = progress.nextMilestone {
                        let start = ArenaProgress.road.last { $0.trophies <= max(progress.totalTrophies, progress.reached) }?.trophies ?? 0
                        let fraction = CGFloat(min(max(progress.totalTrophies - start, 0), next.trophies - start)) / CGFloat(max(next.trophies - start, 1))
                        Capsule().fill(.black.opacity(0.45))
                            .frame(width: 70, height: 5)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.orange).frame(width: 70 * fraction, height: 5)
                            }
                    }
                }
            }
            .font(.system(size: 16, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .arenaInk()
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(.black.opacity(0.3), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("奖杯 \(progress.totalTrophies)，看奖杯之路")
    }

    /// 赛季：几级，下面一条到下一级的经验；有能领的奖励、没做完的任务冒个点
    private var seasonPill: some View {
        let state = progress.season
        let into = state.tier >= ArenaSeason.tiers ? ArenaSeason.pointsPerTier : state.points % ArenaSeason.pointsPerTier
        let waiting = (1...max(state.tier, 1)).contains { $0 <= state.tier && !state.claimed.contains($0) }
        return Button {
            sheet = .season
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "medal.fill").foregroundStyle(Color(red: 0.78, green: 0.6, blue: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text("赛季 \(state.tier) 级")
                    Capsule().fill(.black.opacity(0.45))
                        .frame(width: 70, height: 5)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color(red: 0.7, green: 0.5, blue: 1))
                                .frame(width: 70 * CGFloat(into) / CGFloat(ArenaSeason.pointsPerTier), height: 5)
                        }
                }
            }
            .font(.system(size: 14, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .arenaInk()
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(.black.opacity(0.3), in: Capsule())
            .overlay(alignment: .topTrailing) {
                if waiting {
                    Circle().fill(Color(uiColor: ArenaPalette.gold)).frame(width: 10, height: 10).offset(x: -2, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("赛季 \(state.tier) 级，看任务和奖励")
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6, content: content)
            .font(.system(size: 16, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .arenaInk()
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(.black.opacity(0.3), in: Capsule())
    }

    // MARK: 左边

    private var leftMenu: some View {
        VStack(spacing: 6) {
            tile("冒险", face: Color(red: 0.86, green: 0.3, blue: 0.3), edge: Color(red: 0.55, green: 0.12, blue: 0.12)) {
                Image(systemName: "map.fill").font(.system(size: 21, weight: .black)).foregroundStyle(.white)
                    .overlay(alignment: .topTrailing) {
                        if ArenaStory.levels.contains(where: { progress.isOpen($0.id) && progress.stars($0.id) == 0 }) {
                            Circle().fill(Color(uiColor: ArenaPalette.gold)).frame(width: 10, height: 10).offset(x: 6, y: -4)
                        }
                    }
            } action: {
                adventure = true
            }
            tile("角色", face: Color(red: 0.25, green: 0.55, blue: 1), edge: Color(red: 0.1, green: 0.3, blue: 0.7)) {
                BrawlerBadge(brawler: chosen, size: 34)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            } action: {
                sheet = .brawlers
            }
            tile("赛季", face: Color(red: 0.6, green: 0.4, blue: 0.95), edge: Color(red: 0.36, green: 0.2, blue: 0.66)) {
                Image(systemName: "medal.fill").font(.system(size: 21, weight: .black)).foregroundStyle(.white)
            } action: {
                sheet = .season
            }
            tile("和同事打", face: Color(red: 0.3, green: 0.78, blue: 0.4), edge: Color(red: 0.12, green: 0.48, blue: 0.18)) {
                Image(systemName: "person.3.fill").font(.system(size: 19, weight: .black)).foregroundStyle(.white)
            } action: {
                sheet = .together
            }
        }
        .fullScreenCover(isPresented: $adventure, onDismiss: { ArenaSound.shared.enterLobby() }) {
            ArenaStoryView(brawler: chosen, partners: duelPartners, name: name)
        }
    }

    /// 左边的方块按钮：上面图标、下面字，底下一道深色的边
    private func tile<Icon: View>(_ title: String, face: Color, edge: Color, @ViewBuilder icon: () -> Icon,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                icon().frame(height: 34)
                Text(title)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .arenaOutline(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 74, height: 60)
        }
        .buttonStyle(ArenaTileButton(face: face, edge: edge))
    }

    // MARK: 中间：角色的名字、等级、升级

    private var brawlerPlate: some View {
        let level = progress.level(chosen)
        return VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text("\(level)")
                    .font(.system(size: 15, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .arenaOutline(1)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(red: 0.55, green: 0.3, blue: 0.95)))
                    .overlay(Circle().strokeBorder(.black.opacity(0.7), lineWidth: 2))
                    .accessibilityLabel("\(level) 级")
                Text(chosen.name)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .arenaOutline(2)
            }
            HStack(spacing: 8) {
                Label("\(progress.trophies(chosen))", systemImage: "trophy.fill")
                    .foregroundStyle(.orange)
                Text(chosen.role)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.3)))
            }
            .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
            .arenaInk()
            if let cost = progress.upgradeCost(chosen) {
                Button {
                    growth.upgrade(chosen)
                } label: {
                    HStack(spacing: 4) {
                        Text("升到 \(level + 1) 级")
                        Image(systemName: "dollarsign.circle.fill").foregroundStyle(.yellow)
                        Text("\(cost)").monospacedDigit()
                    }
                }
                .buttonStyle(ArenaGameButton(face: ArenaGameButton.green.face, edge: ArenaGameButton.green.edge, height: 38))
                .disabled(progress.coins < cost)
                .opacity(progress.coins < cost ? 0.55 : 1)
            } else {
                Text("满级了")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(Color(uiColor: ArenaPalette.gold))
                    .arenaOutline(1)
            }
        }
    }

    // MARK: 右边：带的本事、玩法、开打

    private var rightPanel: some View {
        VStack(alignment: .trailing, spacing: DS.Space.s) {
            HStack(spacing: DS.Space.s) {
                rankedSwitch
                loadoutChips
            }
            modeCard
            Button {
                start()
            } label: {
                Text("开打").frame(width: 196)
            }
            .buttonStyle(ArenaGameButton(face: ArenaGameButton.yellow.face, edge: ArenaGameButton.yellow.edge, height: 58))
        }
    }

    /// 带的小道具、星徽、超级充能（没解锁的灰着带锁），点一下去选
    private var loadoutChips: some View {
        let loadout = progress.loadout(for: chosen)
        return Button {
            sheet = .loadout
        } label: {
            HStack(spacing: 6) {
                chip(color: ArenaPalette.gadget, locked: loadout.gadget == nil) {
                    Text(loadout.gadget?.emoji ?? "🔒").font(.system(size: 17))
                }
                chip(color: ArenaPalette.gold, locked: loadout.starPower == nil) {
                    Image(systemName: loadout.starPower == nil ? "lock.fill" : "star.fill")
                        .font(.system(size: 15, weight: .black)).foregroundStyle(.white)
                }
                chip(color: ArenaPalette.hyper, locked: !loadout.hypercharge) {
                    Image(systemName: loadout.hypercharge ? "bolt.fill" : "lock.fill")
                        .font(.system(size: 15, weight: .black)).foregroundStyle(.white)
                }
                Text("本事")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .arenaInk()
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .background(.black.opacity(0.28), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选带的小道具、星徽")
    }

    private func chip<Content: View>(color: UIColor, locked: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: 32, height: 32)
            .background(Circle().fill(locked ? Color.gray.opacity(0.6) : Color(uiColor: color)))
            .overlay(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 2))
    }

    /// 普通 / 排位
    private var rankedSwitch: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { item in
                Button {
                    ranked = item
                } label: {
                    Text(item ? "排位" : "普通")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .arenaInk()
                        .frame(width: 46, height: 34)
                        .background(Capsule().fill(ranked == item ? (item ? Color(red: 0.86, green: 0.3, blue: 0.3) : Color(red: 0.25, green: 0.55, blue: 1)) : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.black.opacity(0.28), in: Capsule())
        .accessibilityLabel(ranked ? "排位赛" : "普通赛")
    }

    /// 排位赛打哪个玩法：选的是 3v3 的就打它，不然打 3v3 团战
    private var playMode: ArenaGame.Mode { ranked && !ArenaRank.allows(mode) ? .teamFight : mode }

    /// 现在的玩法：颜色、图标、名字、赢了几局（排位赛是段位和分数）；点一下换
    private var modeCard: some View {
        Button {
            sheet = .modes
        } label: {
            HStack(spacing: 10) {
                Image(systemName: playMode.icon)
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.black.opacity(0.22)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(ranked ? "排位 · \(playMode.title)" : playMode.title)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .arenaOutline(1.2)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .black)).foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 10)
            .frame(width: 244, height: 58)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(playMode.tint))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.65), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("玩法：\(playMode.title)，点一下换")
    }

    private var subtitle: String {
        if ranked {
            let points = progress.season.rankPoints
            let tier = ArenaRank.tiers[ArenaRank.tier(points)]
            return ArenaRank.allows(mode) ? "\(tier.name) \(points) 分 · 电脑 \(tier.botLevel) 级" : "排位只打 3v3 · \(tier.name) \(points) 分"
        }
        return records.tally.played[mode.rawValue].map { "赢了 \(records.tally.won[mode.rawValue] ?? 0)/\($0) 局" } ?? "点一下换玩法"
    }

    private func start() {
        let level = progress.level(chosen)
        let botLevel = ranked ? max(ArenaRank.tiers[progress.rankTier].botLevel, level) : nil
        playing = ArenaEntry(setup: ArenaController.Setup(mode: playMode, brawler: chosen, name: name, level: level,
                                                          lineup: duelPartners, loadout: progress.loadout(for: chosen),
                                                          ranked: ranked, botLevel: botLevel))
    }

    // MARK: 面板

    @ViewBuilder private func sheetContent(_ item: Sheet) -> some View {
        ArenaGamePanel(title: panelTitle(item), tint: panelTint(item), onClose: {
            inspected = nil
            sheet = nil
        }) {
            switch item {
            case .brawlers: brawlerGrid
            case .modes: modeList
            case .loadout: loadoutList
            case .road: ArenaTrophyRoad()
            case .together: togetherList
            case .season: ArenaSeasonSheet()
            case .settings: settingsPanel
            }
        }
    }

    private func panelTitle(_ item: Sheet) -> String {
        switch item {
        case .brawlers: return "角色"
        case .modes: return "玩法"
        case .loadout: return "\(chosen.name)的本事"
        case .road: return "奖杯之路"
        case .together: return "和同事打"
        case .season: return "赛季"
        case .settings: return "设置"
        }
    }

    private func panelTint(_ item: Sheet) -> Color {
        switch item {
        case .brawlers: return Color(red: 0.25, green: 0.55, blue: 1)
        case .modes: return Color(red: 1, green: 0.76, blue: 0.12)
        case .loadout: return Color(red: 0.36, green: 0.82, blue: 0.24)
        case .road: return .orange
        case .together: return Color(red: 0.3, green: 0.78, blue: 0.4)
        case .season: return Color(red: 0.6, green: 0.4, blue: 0.95)
        case .settings: return Color(red: 0.45, green: 0.5, blue: 0.58)
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsCard {
                HStack {
                    Text(muted ? "声音关着" : "声音开着")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .arenaOutline(1)
                    Spacer()
                    Button {
                        muted.toggle()
                        ArenaSound.shared.muteChanged(battle: false)
                    } label: {
                        Text(muted ? "打开" : "静音").frame(width: 88)
                    }
                    .buttonStyle(ArenaGameButton(face: muted ? ArenaGameButton.green.face : ArenaGameButton.blue.face,
                                                 edge: muted ? ArenaGameButton.green.edge : ArenaGameButton.blue.edge, height: 40))
                }
                Text("大厅是一首，开打换成战斗的。静音之后两边都不响。")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                volumeBar
            }
            settingsCard {
                Text("怎么打")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .arenaOutline(1)
                Text("左下摇杆走路。右下摇杆瞄准，松手开火；点一下自动打最近的人。黄圈满了放大招，绿钮是小道具。草丛里别人看不见你，你开火或者靠太近就会露出来。")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var volumeBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("音量 \(Int(volume * 100))")
                .font(.system(size: 13, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.45))
                    Capsule().fill(Color(red: 1, green: 0.76, blue: 0.12)).frame(width: max(12, width * volume))
                }
                .overlay(Capsule().strokeBorder(.black.opacity(0.7), lineWidth: 2))
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    volume = min(max(value.location.x / width, 0.05), 1)
                    ArenaSound.shared.volumeChanged()
                })
            }
            .frame(height: 22)
            .opacity(muted ? 0.4 : 1)
            .allowsHitTesting(!muted)
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(0.38)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 2))
    }

    private var brawlerGrid: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                    ForEach(Brawler.allCases, id: \.self) { item in
                        Button {
                            inspected = item
                        } label: {
                            brawlerCard(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, inspected == nil ? 8 : 150)
            }
            if let inspected {
                brawlerDetail(inspected)
            }
        }
    }

    /// 第三层：这个角色怎么打，确认了才上场
    private func brawlerDetail(_ item: Brawler) -> some View {
        let unlocked = progress.isUnlocked(item)
        return HStack(alignment: .center, spacing: 12) {
            BrawlerBadge(brawler: item, size: 64, selected: chosen == item)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .arenaOutline(1.2)
                Text("\(item.role) · 血 \(item.health(level: progress.level(item)))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                Text(item.attackNote)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(item.superNote)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.4))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Button {
                    self.inspected = nil
                } label: {
                    Text("返回").frame(width: 96)
                }
                .buttonStyle(ArenaGameButton(face: Color(red: 0.45, green: 0.5, blue: 0.58), edge: Color(red: 0.22, green: 0.25, blue: 0.3), height: 36))
                Button {
                    guard unlocked else { return }
                    brawler = item
                    UserDefaults.standard.set(item.rawValue, forKey: "arena.brawler")
                    self.inspected = nil
                    sheet = nil
                } label: {
                    Text(unlocked ? "上场" : "未解锁").frame(width: 96)
                }
                .buttonStyle(ArenaGameButton(face: unlocked ? ArenaGameButton.green.face : Color.gray, edge: unlocked ? ArenaGameButton.green.edge : Color(white: 0.25), height: 36))
                .disabled(!unlocked)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(red: 0.1, green: 0.16, blue: 0.28).opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.black, lineWidth: 3))
    }

    private func brawlerCard(_ item: Brawler) -> some View {
        let unlocked = progress.isUnlocked(item)
        let level = progress.level(item)
        return VStack(spacing: 4) {
            BrawlerBadge(brawler: item, size: 70, selected: chosen == item)
                .overlay(alignment: .bottomTrailing) {
                    if !unlocked {
                        Image(systemName: "lock.fill").font(.caption.weight(.bold)).foregroundStyle(.white)
                            .padding(5).background(Circle().fill(.black.opacity(0.6)))
                    }
                }
                .opacity(unlocked ? 1 : 0.5)
            Text(item.name).font(.system(size: 16, weight: .black, design: .rounded)).foregroundStyle(.white).arenaOutline(1)
            Text(item.role).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.8))
            if unlocked {
                HStack(spacing: 8) {
                    Label("\(progress.trophies(item))", systemImage: "trophy.fill").foregroundStyle(.orange)
                    Text("\(level) 级").foregroundStyle(Color(red: 0.75, green: 0.85, blue: 1))
                }
                .font(.system(size: 12, weight: .black, design: .rounded).monospacedDigit())
            } else {
                Text("总奖杯到 \(item.unlockAt) 解锁").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(chosen == item ? 0.28 : 0.45)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(chosen == item ? Color(red: 1, green: 0.86, blue: 0.2) : .white.opacity(0.16), lineWidth: chosen == item ? 3 : 2))
    }

    private var modeList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(ArenaGame.Mode.allCases, id: \.self) { item in
                    Button {
                        mode = item
                        UserDefaults.standard.set(item.rawValue, forKey: "arena.mode")
                        sheet = nil
                    } label: {
                        modeRow(item)
                    }
                    .buttonStyle(.plain)
                }
                Text("一对一带：" + ([chosen] + duelPartners).map(\.name).joined(separator: "、"))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func modeRow(_ item: ArenaGame.Mode) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s) {
            Image(systemName: item.icon)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(item.tint))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.title)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .arenaOutline(1)
                    if mode == item {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(red: 1, green: 0.86, blue: 0.2))
                    }
                    Spacer()
                    if let played = records.tally.played[item.rawValue] {
                        Text("赢了 \(records.tally.won[item.rawValue] ?? 0)/\(played)")
                            .font(.system(size: 12, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                Text(item.rules)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(item.tint.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.7), lineWidth: 2))
    }

    private var loadoutList: some View {
        List {
            upgradeSection
            ArenaLoadoutSection(brawler: chosen)
            ArenaSkinSection(brawler: chosen)
        }
        .scrollContentBackground(.hidden)
        .environment(\.colorScheme, .dark)
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
            Text("现在有 \(progress.coins) 金币。升级后血 \(chosen.health(level: level)) → \(chosen.health(level: min(level + 1, ArenaProgress.maxLevel)))，伤害同样多 6%。")
        }
    }

    private var togetherList: some View {
        List {
            GameRoomButtons(kind: .arena, remotePlayers: 2...6, nearbyCapacity: 6) { room in
                pendingRoom = room
                sheet = nil
            }
        }
        .scrollContentBackground(.hidden)
        .environment(\.colorScheme, .dark)
    }
}

/// 二级菜单的框：横屏、游戏背景、大标题、叉，不用系统导航栏
struct ArenaGamePanel<Content: View>: View {
    let title: String
    let tint: Color
    var onClose: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            ArenaLobbyBackground()
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tint)
                        .frame(width: 8, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.6), lineWidth: 1.5))
                    Text(title)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .arenaOutline(2)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color(red: 0.85, green: 0.22, blue: 0.22)))
                            .overlay(Circle().strokeBorder(.black.opacity(0.75), lineWidth: 2))
                    }
                    .accessibilityLabel("关上")
                }
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .modifier(ArenaLandscape())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

/// 左边方块按钮的样子：亮色的面，底下一道深色的边，按下去往下沉
struct ArenaTileButton: ButtonStyle {
    let face: Color
    let edge: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(face)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.22))
                            .frame(height: 18).padding(.horizontal, 5).padding(.top, 4)
                    }
            )
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.7), lineWidth: 2))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(edge)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.7), lineWidth: 2))
                    .offset(y: configuration.isPressed ? 1 : 5)
            )
            .offset(y: configuration.isPressed ? 4 : 0)
            .padding(.bottom, 5)
    }
}

extension ArenaGame.Mode {
    /// 大厅玩法卡片的图标
    var icon: String {
        switch self {
        case .teamFight: return "person.3.fill"
        case .stars: return "star.fill"
        case .ball: return "soccerball"
        case .heist: return "shippingbox.fill"
        case .bounty: return "scope"
        case .zone: return "target"
        case .knockout: return "3.circle.fill"
        case .showdown: return "flame.fill"
        case .duo: return "person.2.fill"
        case .duel: return "figure.fencing"
        case .boss: return "crown.fill"
        }
    }

    /// 大厅玩法卡片的颜色
    var tint: Color {
        switch self {
        case .teamFight: return Color(red: 0.86, green: 0.3, blue: 0.3)
        case .stars: return Color(red: 0.62, green: 0.32, blue: 0.95)
        case .ball: return Color(red: 0.36, green: 0.62, blue: 0.22)
        case .heist: return Color(red: 0.86, green: 0.36, blue: 0.58)
        case .bounty: return Color(red: 0.2, green: 0.62, blue: 0.86)
        case .zone: return Color(red: 0.95, green: 0.55, blue: 0.1)
        case .knockout: return Color(red: 0.95, green: 0.42, blue: 0.2)
        case .showdown: return Color(red: 0.36, green: 0.7, blue: 0.3)
        case .duo: return Color(red: 0.25, green: 0.6, blue: 0.5)
        case .duel: return Color(red: 0.5, green: 0.4, blue: 0.85)
        case .boss: return Color(red: 0.55, green: 0.2, blue: 0.25)
        }
    }
}

// MARK: - 背景

/// 大厅的底：蓝到紫的渐变，后面一圈光芒慢慢转，中间亮一点
private struct ArenaLobbyBackground: View {
    @State private var turning = false

    var body: some View {
        LinearGradient(colors: [Color(red: 0.2, green: 0.52, blue: 1), Color(red: 0.34, green: 0.22, blue: 0.82)],
                       startPoint: .top, endPoint: .bottom)
            .overlay {
                Rays()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 900, height: 900)
                    .rotationEffect(.degrees(turning ? 360 : 0))
                    .animation(.linear(duration: 80).repeatForever(autoreverses: false), value: turning)
            }
            .overlay {
                RadialGradient(colors: [.white.opacity(0.32), .clear], center: .center, startRadius: 10, endRadius: 280)
            }
            .clipped()
            .ignoresSafeArea()
            .onAppear { turning = true }
    }
}

/// 从中间往外的一圈光芒（16 道）
private struct Rays: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(rect.width, rect.height)
        for k in 0..<16 {
            let a = CGFloat(k) / 16 * 2 * .pi
            let b = a + .pi / 16
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius))
            path.addLine(to: CGPoint(x: center.x + cos(b) * radius, y: center.y + sin(b) * radius))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - 中间的 3D 角色

/// 大厅中间的 3D 角色：站在台子上轻轻左右转，手指拖着能转，点一下出手（换了角色先欢呼一下）
struct ArenaShowcase: UIViewRepresentable {
    let brawler: Brawler
    /// 穿第几套皮肤
    var skin = 0

    func makeUIView(context: Context) -> ArenaShowcaseView {
        ArenaShowcaseView(brawler: brawler, skin: skin)
    }

    func updateUIView(_ view: ArenaShowcaseView, context: Context) {
        view.show(brawler, skin: skin)
    }

    static func dismantleUIView(_ view: ArenaShowcaseView, coordinator: ()) {
        view.stop()
    }
}

@MainActor
final class ArenaShowcaseView: SCNView {
    private let world = SCNScene()
    /// 角色站的地方（台子顶上）
    private let stage = SCNNode()
    private var avatar: ArenaAvatar?
    /// 给角色摆动作用的一个人（不在场上，只用来转身、放站着的动作）
    private var fighter: Fighter
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var clock = 0.0
    /// 手指拖着转的角度（松手后慢慢转回来）
    private var spin: Float = 0
    private var dragging = false
    private var cheerUntil = 0.0
    private var taps = 0
    /// 现在穿的第几套皮肤
    private var wearing = 0

    init(brawler: Brawler, skin: Int = 0) {
        fighter = Fighter(id: 0, name: "", team: 0, brawler: brawler, isBot: false, level: 1, pos: .zero, facing: V2(0, 1), health: 1)
        super.init(frame: .zero, options: nil)
        backgroundColor = .clear
        antialiasingMode = .none
        preferredFramesPerSecond = 60
        rendersContinuously = true
        isPlaying = true
        world.background.contents = UIColor.clear
        scene = world
        build()
        show(brawler, skin: skin)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragged(_:))))
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        isAccessibilityElement = true
        accessibilityLabel = "选的角色，左右拖着转"
    }

    required init?(coder: NSCoder) { fatalError("不从文件里读") }

    private func build() {
        let camera = SCNCamera()
        camera.fieldOfView = 28
        camera.zNear = 0.1
        camera.zFar = 30
        let eye = SCNNode()
        eye.camera = camera
        eye.simdPosition = SIMD3(0, 1.25, 4.6)
        eye.simdEulerAngles = SIMD3(-0.12, 0, 0)
        world.rootNode.addChildNode(eye)
        pointOfView = eye

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 480
        ambient.light?.color = UIColor(red: 1, green: 0.97, blue: 0.92, alpha: 1)
        world.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 820
        key.simdOrientation = simd_quatf(from: SIMD3(0, 0, -1), to: simd_normalize(SIMD3(-0.5, -0.7, -1)))
        world.rootNode.addChildNode(key)
        // 背后一道偏蓝的光，勾出轮廓
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 450
        rim.light?.color = UIColor(red: 0.6, green: 0.75, blue: 1, alpha: 1)
        rim.simdOrientation = simd_quatf(from: SIMD3(0, 0, -1), to: simd_normalize(SIMD3(0.3, -0.4, 1)))
        world.rootNode.addChildNode(rim)

        // 台子：金边的圆台，描一圈深色的边，上面一块影子
        let height: Float = 0.22
        let top = SCNCylinder(radius: 0.95, height: CGFloat(height))
        top.radialSegmentCount = 48
        let side = SCNMaterial()
        side.lightingModel = .lambert
        side.diffuse.contents = UIColor(red: 1, green: 0.78, blue: 0.3, alpha: 1)
        let face = SCNMaterial()
        face.lightingModel = .lambert
        face.diffuse.contents = UIColor(red: 0.35, green: 0.62, blue: 1, alpha: 1)
        top.materials = [side, face, side]
        let pedestal = SCNNode(geometry: top)
        pedestal.simdPosition = SIMD3(0, height / 2, 0)
        world.rootNode.addChildNode(pedestal)
        let rimGeometry = SCNCylinder(radius: 0.99, height: CGFloat(height + 0.06))
        rimGeometry.radialSegmentCount = 48
        let ink = SCNMaterial()
        ink.lightingModel = .constant
        ink.diffuse.contents = UIColor(red: 0.12, green: 0.08, blue: 0.2, alpha: 1)
        ink.cullMode = .front
        rimGeometry.firstMaterial = ink
        let outline = SCNNode(geometry: rimGeometry)
        outline.simdPosition = pedestal.simdPosition
        world.rootNode.addChildNode(outline)
        let shadow = SCNCylinder(radius: 0.5, height: 0.002)
        shadow.radialSegmentCount = 32
        shadow.firstMaterial = ArenaAvatar.decal(UIColor.black.withAlphaComponent(0.28))
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.simdPosition = SIMD3(0, height + 0.002, 0)
        shadowNode.renderingOrder = 2
        world.rootNode.addChildNode(shadowNode)

        stage.simdPosition = SIMD3(0, height, 0)
        world.rootNode.addChildNode(stage)
    }

    /// 换角色、换皮肤：换模型，先欢呼一下
    func show(_ brawler: Brawler, skin: Int = 0) {
        guard avatar?.brawler != brawler || skin != wearing else { return }
        avatar?.node.removeFromParentNode()
        let made = ArenaAvatar(brawler: brawler, color: .clear, isMe: false, decorated: false, skin: skin)
        stage.addChildNode(made.node)
        avatar = made
        wearing = skin
        fighter.brawler = brawler
        cheerUntil = clock + 1.6
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stop()
        } else if link == nil {
            let target = ShowcaseTarget(view: self)
            let link = CADisplayLink(target: target, selector: #selector(ShowcaseTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastTimestamp = nil
    }

    fileprivate func tick(_ timestamp: CFTimeInterval) {
        let dt = Float(min(max(timestamp - (lastTimestamp ?? timestamp), 0), 0.1))
        lastTimestamp = timestamp
        clock += Double(dt)
        if !dragging { spin *= max(0, 1 - dt * 1.5) }
        let angle = 0.35 * Float(sin(clock * 0.6)) + spin
        fighter.facing = V2(Double(sin(angle)), Double(cos(angle)))
        avatar?.update(fighter, visible: true, translucent: false, cheering: clock < cheerUntil, dt: dt, clock: clock)
    }

    @objc private func dragged(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            dragging = true
        case .changed:
            spin += Float(pan.translation(in: self).x) * 0.012
            pan.setTranslation(.zero, in: self)
        default:
            dragging = false
        }
    }

    /// 点一下出手，每第三下放个大招动作
    @objc private func tapped() {
        taps += 1
        if taps % 3 == 0 { avatar?.special() } else { avatar?.attack() }
    }
}

/// CADisplayLink 会一直拉着它的 target，用这个小东西隔开，大厅关了能正常释放
@MainActor
private final class ShowcaseTarget: NSObject {
    weak var view: ArenaShowcaseView?

    init(view: ArenaShowcaseView) {
        self.view = view
        super.init()
    }

    @objc func tick(_ link: CADisplayLink) {
        view?.tick(link.timestamp)
    }
}
