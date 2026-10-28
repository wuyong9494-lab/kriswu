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
    /// 组队开几个人的房间（2 是双人，3–6 是多人）
    @State private var partySize = 2
    @State private var friends = ArenaFriends.load()
    @State private var friendName = ""
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
        case brawlers, modes, loadout, road, together, season, settings, friends, party, shop
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
                ArenaShowcase(brawler: chosen, skin: progress.skin(chosen),
                              live: playing == nil && lobby == nil && !adventure && sheet == nil)
                    .frame(width: min(geo.size.width * (wide ? 0.42 : 0.86), 460), height: geo.size.height * (wide ? 0.7 : 0.42))
                    .position(x: geo.size.width / 2, y: geo.size.height * (wide ? 0.54 : 0.48))
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
            .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .arenaInk()
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(.black.opacity(0.45), in: Capsule())
            .overlay(Capsule().strokeBorder(.black, lineWidth: 3))
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
            .font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .arenaInk()
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(.black.opacity(0.45), in: Capsule())
            .overlay(Capsule().strokeBorder(.black, lineWidth: 3))
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
            HStack(spacing: 6) {
                miniTile("商店", icon: "bag.fill", face: Color(red: 0.95, green: 0.62, blue: 0.15)) { sheet = .shop }
                miniTile("好友", icon: "person.2.fill", face: Color(red: 0.25, green: 0.55, blue: 0.95)) { sheet = .friends }
                miniTile("组队", icon: "plus", face: Color(red: 0.2, green: 0.72, blue: 0.45)) { sheet = .party }
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
            .frame(width: 74, height: 64)
        }
        .buttonStyle(ArenaTileButton(face: face, edge: edge))
    }

    private func miniTile(_ title: String, icon: String, face: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: icon).font(.system(size: 16, weight: .black)).foregroundStyle(.white)
                    .frame(height: 22)
                Text(title)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 46)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(face))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.black, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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
                Button {
                    sheet = .party
                } label: {
                    Text("+")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color(red: 0.2, green: 0.72, blue: 0.45)))
                        .overlay(Circle().strokeBorder(.black.opacity(0.75), lineWidth: 3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("组队")
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
                Text("开打").frame(width: 210)
            }
            .buttonStyle(ArenaGameButton(face: ArenaGameButton.yellow.face, edge: ArenaGameButton.yellow.edge, height: 64))
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
                    Image(systemName: loadout.gadget == nil ? "lock.fill" : "sparkles")
                        .font(.system(size: 15, weight: .black)).foregroundStyle(.white)
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
                if let map = ArenaMap.pool(for: playMode).first {
                    ArenaMapThumb(map: map)
                        .frame(width: 46, height: 46)
                        .accessibilityLabel("地图 \(map.title)")
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(ranked ? "排位 · \(playMode.title)" : playMode.title)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .arenaOutline(1.2)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(dayLeft)
                        .font(.system(size: 10, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                Image(systemName: "map.fill").font(.system(size: 13, weight: .black)).foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 10)
            .frame(width: 244, height: 68)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(playMode.tint))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black, lineWidth: 3))
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
        return records.tally.played[mode.rawValue].map { "赢了 \(records.tally.won[mode.rawValue] ?? 0)/\($0) 局" } ?? "点一下看地图"
    }

    /// 玩法卡上的倒计时：到今晚零点还剩多久（不是新玩法）
    private var dayLeft: String {
        let now = Date()
        let end = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? now
        let left = max(0, Int(end.timeIntervalSince(now)))
        return String(format: "今日还剩 %d:%02d", left / 3600, (left / 60) % 60)
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
            case .loadout: skillBoard
            case .road: ArenaTrophyRoad()
            case .together: togetherList
            case .friends: friendsBoard
            case .party: partyBoard
            case .shop: shopBoard
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
        case .friends: return "好友"
        case .party: return "组队"
        case .shop: return "商店"
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
        case .friends: return Color(red: 0.25, green: 0.55, blue: 0.95)
        case .party: return Color(red: 0.2, green: 0.72, blue: 0.45)
        case .shop: return Color(red: 0.95, green: 0.62, blue: 0.15)
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
                    if let map = ArenaMap.pool(for: item).first {
                        ArenaMapThumb(map: map).frame(width: 52, height: 36)
                    }
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

    /// 普攻、大招、小道具、星徽。选了就带上，没解锁的锁着
    private var skillBoard: some View {
        let level = progress.level(chosen)
        let loadout = progress.loadout(for: chosen)
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                skillCard(title: "普攻", note: chosen.attackNote, tint: Color(red: 0.9, green: 0.28, blue: 0.24), mark: "打", chosen: true, locked: nil) {}
                skillCard(title: "大招", note: chosen.superNote, tint: Color(uiColor: ArenaPalette.gold), mark: "大", chosen: true, locked: nil) {}
                Text("小道具（一局 \(ArenaGame.gadgetUses) 次）")
                    .font(.system(size: 13, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                ForEach(chosen.gadgets.indices, id: \.self) { k in
                    let gadget = chosen.gadgets[k]
                    let needs = ArenaProgress.gadgetLevels[k]
                    skillCard(title: gadget.name, note: gadget.note, tint: Color(uiColor: ArenaPalette.gadget), mark: "具",
                              chosen: loadout.gadget == gadget, locked: level < needs ? needs : nil) {
                        growth.choose(gadget, for: chosen)
                    }
                }
                Text("星徽（一直有效）")
                    .font(.system(size: 13, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                ForEach(chosen.starPowers.indices, id: \.self) { k in
                    let star = chosen.starPowers[k]
                    let needs = ArenaProgress.starLevels[k]
                    skillCard(title: star.name, note: star.note, tint: Color(uiColor: ArenaPalette.gold), mark: "星",
                              chosen: loadout.starPower == star, locked: level < needs ? needs : nil) {
                        growth.choose(star, for: chosen)
                    }
                }
                skillCard(title: "超级充能", note: "攒满再放大招：" + chosen.hyperNote, tint: Color(uiColor: ArenaPalette.hyper), mark: "超",
                          chosen: loadout.hypercharge, locked: level < ArenaProgress.hyperLevel ? ArenaProgress.hyperLevel : nil) {}
            }
            .padding(.bottom, 12)
        }
    }

    private func skillCard(title: String, note: String, tint: Color, mark: String, chosen: Bool, locked: Int?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(mark)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(locked == nil ? tint : Color.gray))
                    .overlay(Circle().strokeBorder(.black, lineWidth: 2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 18, weight: .black, design: .rounded)).foregroundStyle(.white).arenaOutline(1)
                    Text(note).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if let locked {
                    Text("\(locked) 级").font(.system(size: 12, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                } else if chosen {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(red: 1, green: 0.86, blue: 0.2))
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(locked == nil ? 0.9 : 0.35)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black, lineWidth: chosen && locked == nil ? 3 : 2))
        }
        .buttonStyle(.plain)
        .disabled(locked != nil)
    }

    private var friendsBoard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("好友的名字", text: $friendName)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let trimmed = friendName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    friends.append(ArenaFriend(id: UUID(), name: trimmed))
                    ArenaFriends.save(friends)
                    friendName = ""
                } label: {
                    Text("加上").frame(width: 72)
                }
                .buttonStyle(ArenaGameButton(face: ArenaGameButton.blue.face, edge: ArenaGameButton.blue.edge, height: 40))
            }
            ScrollView {
                VStack(spacing: 8) {
                    if friends.isEmpty {
                        Text("还没有好友。加上名字，再约他打双人。房间号在下一页，发给他就行。")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    ForEach(friends) { friend in
                        HStack {
                            Text(friend.name)
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .arenaOutline(1)
                            Spacer()
                            Button("双人") { openRoom(players: 2) }
                                .buttonStyle(ArenaGameButton(face: ArenaGameButton.green.face, edge: ArenaGameButton.green.edge, height: 36))
                            Button("删") {
                                friends.removeAll { $0.id == friend.id }
                                ArenaFriends.save(friends)
                            }
                            .buttonStyle(ArenaGameButton(face: Color(red: 0.85, green: 0.22, blue: 0.22),
                                                             edge: Color(red: 0.5, green: 0.08, blue: 0.08), height: 36))
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.28)))
                    }
                }
            }
        }
    }

    private var partyBoard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                partySizeButton("双人对战", size: 2)
                partySizeButton("多人对战", size: max(partySize, 3) == partySize && partySize > 2 ? partySize : 3)
            }
            if partySize > 2 {
                Stepper("\(partySize) 个人", value: $partySize, in: 3...6)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            List {
                GameRoomButtons(kind: .arena, remotePlayers: partySize...partySize, nearbyCapacity: partySize) { room in
                    pendingRoom = room
                    sheet = nil
                }
                .id(partySize)
            }
            .frame(maxHeight: .infinity)
            .scrollContentBackground(.hidden)
            .environment(\.colorScheme, .dark)
        }
    }

    private func partySizeButton(_ title: String, size: Int) -> some View {
        let on = (size == 2 && partySize == 2) || (size > 2 && partySize > 2)
        return Button {
            partySize = size
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(ArenaGameButton(face: on ? ArenaGameButton.yellow.face : ArenaGameButton.blue.face,
                                     edge: on ? ArenaGameButton.yellow.edge : ArenaGameButton.blue.edge, height: 44))
    }

    private func openRoom(players: Int) {
        let nick = GameProfile.nickname.isEmpty ? name : GameProfile.nickname
        let code = RoomCode.make(players: players)
        pendingRoom = GameRoom(kind: .arena, mode: .remote(code: code), name: nick, capacity: players)
        sheet = nil
    }

    /// 商店：金币、每天三件特惠、全部皮肤和表情。特惠到午夜换一批
    private var shopBoard: some View {
        let deals = ArenaShop.deals()
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("\(progress.coins)", systemImage: "dollarsign.circle.fill")
                        .font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(.yellow)
                        .arenaOutline(1)
                    Spacer()
                    Text("还有 \(ArenaShop.hoursLeft()) 小时换特惠")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text("今日特惠")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .arenaOutline(1)
                ForEach(deals) { skin in
                    shopSkin(skin, price: ArenaShop.dealPrice(skin), was: skin.price)
                }
                Text("皮肤")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .arenaOutline(1)
                ForEach(ArenaSkin.all) { skin in
                    shopSkin(skin, price: skin.price, was: nil)
                }
                Text("表情")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .arenaOutline(1)
                ForEach(ArenaEmote.all.filter { !$0.free }) { emote in
                    shopEmote(emote)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func shopSkin(_ skin: ArenaSkin, price: Int, was: Int?) -> some View {
        let owned = progress.owns(skin: skin)
        let wearing = progress.skin(skin.brawler) == skin.index
        return HStack(spacing: 10) {
            BrawlerBadge(brawler: skin.brawler, size: 42)
                .overlay(Circle().strokeBorder(skin.color, lineWidth: 3))
            VStack(alignment: .leading, spacing: 2) {
                Text(skin.name).font(.system(size: 16, weight: .black, design: .rounded)).foregroundStyle(.white).arenaOutline(1)
                Text(skin.brawler.name).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.8))
                if let was, was > price, !owned {
                    Text("\(was)").font(.system(size: 11, weight: .bold, design: .rounded)).strikethrough().foregroundStyle(.white.opacity(0.55))
                }
            }
            Spacer(minLength: 0)
            if wearing {
                Text("穿着").font(.system(size: 13, weight: .black, design: .rounded)).foregroundStyle(.white)
            } else if owned {
                Button("穿上") {
                    growth.wear(skin.index, for: skin.brawler)
                    brawler = skin.brawler
                }
                    .buttonStyle(ArenaGameButton(face: ArenaGameButton.blue.face, edge: ArenaGameButton.blue.edge, height: 36))
            } else {
                Button {
                    _ = growth.buy(skin, price: price)
                } label: {
                    Label("\(price)", systemImage: "dollarsign.circle.fill")
                }
                .buttonStyle(ArenaGameButton(face: ArenaGameButton.yellow.face, edge: ArenaGameButton.yellow.edge, height: 36))
                .disabled(progress.coins < price)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.28)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black, lineWidth: 2))
    }

    private func shopEmote(_ emote: ArenaEmote) -> some View {
        let owned = progress.owns(emote: emote)
        return HStack(spacing: 10) {
            Text(emote.symbol).font(.system(size: 28)).frame(width: 42)
            Text(emote.name).font(.system(size: 16, weight: .black, design: .rounded)).foregroundStyle(.white).arenaOutline(1)
            Spacer()
            if owned {
                Text("有了").font(.system(size: 13, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.8))
            } else if let price = emote.price {
                Button {
                    _ = growth.buy(emote)
                } label: {
                    Label("\(price)", systemImage: "dollarsign.circle.fill")
                }
                .buttonStyle(ArenaGameButton(face: ArenaGameButton.yellow.face, edge: ArenaGameButton.yellow.edge, height: 36))
                .disabled(progress.coins < price)
            } else {
                Text("赛季奖励").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.28)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black, lineWidth: 2))
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
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.85), lineWidth: 3))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(edge)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.85), lineWidth: 3))
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
    /// 大厅被盖住（进对局、开房间、冒险、二级菜单）时停掉，避免两套 SceneKit 一起画
    var live = true

    func makeUIView(context: Context) -> ArenaShowcaseView {
        ArenaShowcaseView(brawler: brawler, skin: skin)
    }

    func updateUIView(_ view: ArenaShowcaseView, context: Context) {
        view.show(brawler, skin: skin)
        if live { view.start() } else { view.stop() }
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
    /// 站着的时候隔几秒挥一下，不靠点屏幕
    private var nextSwing = 4.0
    private var taps = 0
    /// 现在穿的第几套皮肤
    private var wearing = 0

    init(brawler: Brawler, skin: Int = 0) {
        fighter = Fighter(id: 0, name: "", team: 0, brawler: brawler, isBot: false, level: 1, pos: .zero, facing: V2(0, 1), health: 1)
        super.init(frame: .zero, options: nil)
        backgroundColor = .clear
        antialiasingMode = .none
        preferredFramesPerSecond = 30
        rendersContinuously = true
        isPlaying = false
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
        camera.fieldOfView = 32
        camera.zNear = 0.1
        camera.zFar = 30
        let eye = SCNNode()
        eye.camera = camera
        // 从侧前上方看，大约 25 度。看得到脸、肩膀和整个人，不是平视肚子
        eye.simdPosition = SIMD3(0.7, 2.45, 4.3)
        eye.simdEulerAngles = SIMD3(-0.42, 0.18, 0)
        world.rootNode.addChildNode(eye)
        pointOfView = eye

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 280
        ambient.light?.color = UIColor(red: 0.85, green: 0.88, blue: 1, alpha: 1)
        world.rootNode.addChildNode(ambient)
        // 主光：暖的，从左前上方打，脸上有明暗
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 760
        key.light?.color = UIColor(red: 1, green: 0.94, blue: 0.82, alpha: 1)
        key.simdOrientation = simd_quatf(from: SIMD3(0, 0, -1), to: simd_normalize(SIMD3(-0.55, -0.85, -1)))
        world.rootNode.addChildNode(key)
        // 补光：冷一点，从右前把阴影托起来，别发灰
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.intensity = 260
        fill.light?.color = UIColor(red: 0.7, green: 0.82, blue: 1, alpha: 1)
        fill.simdPosition = SIMD3(1.6, 1.5, 2.4)
        world.rootNode.addChildNode(fill)
        // 轮廓光：从背后勾边
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 420
        rim.light?.color = UIColor(red: 0.55, green: 0.72, blue: 1, alpha: 1)
        rim.simdOrientation = simd_quatf(from: SIMD3(0, 0, -1), to: simd_normalize(SIMD3(0.25, -0.35, 1)))
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
        let made = ArenaAvatar(brawler: brawler, color: .clear, isMe: false, decorated: false, size: 0.72, skin: skin)
        stage.addChildNode(made.node)
        avatar = made
        wearing = skin
        fighter.brawler = brawler
        cheerUntil = clock + 1.6
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else { start() }
    }

    func start() {
        guard window != nil else { return }
        rendersContinuously = true
        isPlaying = false
        guard link == nil else { return }
        let target = ShowcaseTarget(view: self)
        let link = CADisplayLink(target: target, selector: #selector(ShowcaseTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastTimestamp = nil
        rendersContinuously = false
        isPlaying = false
    }

    fileprivate func tick(_ timestamp: CFTimeInterval) {
        let dt = Float(min(max(timestamp - (lastTimestamp ?? timestamp), 0), 0.1))
        lastTimestamp = timestamp
        clock += Double(dt)
        if !dragging { spin *= max(0, 1 - dt * 1.5) }
        spin = min(1.6, max(-1.6, spin))
        let angle = 0.35 * Float(sin(clock * 0.6)) + spin
        fighter.facing = V2(Double(sin(angle)), Double(cos(angle)))
        avatar?.update(fighter, visible: true, translucent: false, cheering: clock < cheerUntil, dt: dt, clock: clock)
        if !dragging, clock > cheerUntil, clock > nextSwing {
            avatar?.attack()
            nextSwing = clock + 5.5
        }
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

/// 玩法卡上的小地图：格子自己画，不再开一套 3D
struct ArenaMapThumb: View {
    let map: ArenaMap

    var body: some View {
        Canvas { context, size in
            let columns = max(map.width, 1)
            let rows = max(map.height, 1)
            let cellW = size.width / CGFloat(columns)
            let cellH = size.height / CGFloat(rows)
            for y in 0..<rows {
                for x in 0..<columns {
                    let rect = CGRect(x: CGFloat(x) * cellW, y: CGFloat(rows - 1 - y) * cellH, width: cellW + 0.6, height: cellH + 0.6)
                    context.fill(Path(rect), with: .color(color(map.tile(x, y))))
                }
            }
        }
        .background(Color(red: 0.35, green: 0.62, blue: 0.22))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.black, lineWidth: 2))
    }

    private func color(_ tile: ArenaMap.Tile) -> Color {
        switch tile {
        case .floor: return Color(red: 0.48, green: 0.78, blue: 0.3)
        case .wall: return Color(red: 0.62, green: 0.42, blue: 0.24)
        case .bush: return Color(red: 0.12, green: 0.48, blue: 0.18)
        case .goal: return Color(red: 0.95, green: 0.82, blue: 0.2)
        }
    }
}

/// 记在这台手机上的好友（名字）。约人时开一个双人房间，把房间号发给他
private struct ArenaFriend: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
}

private enum ArenaFriends {
    static let key = "arena.friends"

    static func load() -> [ArenaFriend] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([ArenaFriend].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [ArenaFriend]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// 每天三件特惠：同一天大家看到的一样，本地午夜换
private enum ArenaShop {
    static func dayNumber(_ date: Date = Date()) -> Int {
        Int(date.timeIntervalSince1970 / 86_400)
    }

    static func hoursLeft(_ date: Date = Date()) -> Int {
        let passed = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400)
        return max(1, Int((86_400 - passed) / 3600))
    }

    static func deals(_ date: Date = Date()) -> [ArenaSkin] {
        let all = ArenaSkin.all
        guard all.count >= 3 else { return all }
        var picks: [ArenaSkin] = []
        var n = dayNumber(date)
        while picks.count < 3 {
            n = n &* 1_103_515_245 &+ 12_345
            let index = Int(UInt(bitPattern: n) % UInt(all.count))
            let skin = all[index]
            if !picks.contains(where: { $0.id == skin.id }) { picks.append(skin) }
        }
        return picks
    }

    static func dealPrice(_ skin: ArenaSkin) -> Int { max(40, skin.price * 7 / 10) }
}
