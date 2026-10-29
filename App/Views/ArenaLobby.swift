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
    @State private var pendingBenchmark: ArenaEntry?
    /// 冒险
    @State private var adventure = false
    /// 组队开几个人的房间（2 是双人，3–6 是多人）
    @State private var partySize = 2
    @State private var friends = ArenaFriends.load()
    @State private var friendName = ""
    @State private var roomCode = ""
    /// 排位赛（只打 3v3，按段位加减排位分）
    @AppStorage("arena.ranked") private var ranked = false
    @AppStorage(ArenaSound.muteKey) private var muted = false
    @AppStorage("arena.performanceOverlay") private var performanceOverlay = false
    @AppStorage("arena.diagnosticVariant") private var diagnosticVariant = "baseline"
    @AppStorage("arena.purpleSample") private var purpleSample = false
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
        case brawlers, modes, loadout, road, together, season, settings, friends, party, shop, diagnostics
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
                VStack(spacing: 8) {
                    compactTopBar
                    HStack(alignment: .center, spacing: 12) {
                        ScrollView(.vertical, showsIndicators: false) { leftMenu }.frame(width: 66)
                        VStack(spacing: 2) {
                            ArenaShowcase(brawler: chosen, skin: progress.skin(chosen),
                                          live: playing == nil && lobby == nil && !adventure && sheet == nil)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                            Button { sheet = .brawlers } label: {
                                HStack(spacing: 8) {
                                    Text(chosen.name).font(.system(size: 22, weight: .heavy, design: .rounded))
                                    Text("Lv. \(progress.level(chosen)) · \(chosen.role)").font(.system(size: 12, weight: .semibold))
                                    Image(systemName: "chevron.left.chevron.right").font(.caption)
                                }
                                .foregroundStyle(.white)
                                .frame(minHeight: 32)
                            }.buttonStyle(.plain)
                        }
                        ScrollView(.vertical, showsIndicators: false) {
                          VStack(spacing: 8) {
                            quietMenu("商店", symbol: "bag.fill") { sheet = .shop }
                            quietMenu("好友", symbol: "person.2.fill") { sheet = .friends }
                            quietMenu("组队", symbol: "person.3.fill") { sheet = .party }
                            quietMenu("技能", symbol: "sparkles") { sheet = .loadout }
                          }
                        }.frame(width: 66)
                    }
                    .frame(height: max(80, geo.size.height - 128))
                    HStack(spacing: 12) {
                        Button { sheet = .modes } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "map.fill").font(.title3).foregroundStyle(.mint)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(playMode.title).font(.system(size: 16, weight: .bold, design: .rounded))
                                    Text("选择玩法与地图").font(.caption).foregroundStyle(.white.opacity(0.65))
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.up").font(.caption)
                            }
                            .foregroundStyle(.white).padding(.horizontal, 14).frame(height: 56)
                            .background(Color(red: 0.13, green: 0.10, blue: 0.23), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                        rankedSwitch
                        Button { start() } label: {
                            Label("开始对战", systemImage: "play.fill")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .frame(width: wide ? 170 : 130, height: 56)
                                .background(Color(red: 0.97, green: 0.72, blue: 0.24), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color(red: 0.18, green: 0.10, blue: 0.20))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .modifier(ArenaLandscape())
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            growth.refreshSeason()
            if UserDefaults.standard.bool(forKey: "arena.openSettings") { sheet = .settings }
            ArenaSound.shared.enterLobby()
        }
        .onChange(of: volume) { _ in ArenaSound.shared.volumeChanged() }
        .fullScreenCover(item: $sheet, onDismiss: {
            if let entry = pendingBenchmark {
                pendingBenchmark = nil
                playing = entry
                return
            }
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

    private func quietMenu(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 66, height: 48)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var compactTopBar: some View {
        HStack(spacing: 8) {
            Button {
                ArenaOrientation.releaseAll()
                ArenaSound.shared.leaveLobby()
                dismiss()
            } label: { Image(systemName: "xmark").frame(width: 44, height: 40) }
                .accessibilityLabel("离开勇者乱斗")
            Button { muted.toggle(); ArenaSound.shared.muteChanged(battle: false) } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 44, height: 40)
            }.accessibilityLabel("切换声音")
            Text("勇者竞技场").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.65))
            Spacer(minLength: 4)
            Button { sheet = .road } label: { Label("\(progress.totalTrophies)", systemImage: "trophy.fill") }
            Button { sheet = .shop } label: { Label("\(progress.coins)", systemImage: "circle.hexagongrid.fill") }
            Button { sheet = .season } label: { Label("\(progress.season.tier)级", systemImage: "star.circle.fill") }
            Button { sheet = .settings } label: { Image(systemName: "gearshape.fill").frame(width: 44, height: 40) }
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .frame(height: 40)
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
            coinPill
            gemPill
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
            .font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .arenaOutline(2)
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(Color(red: 0.18, green: 0.22, blue: 0.38), in: Capsule())
            .overlay(Capsule().strokeBorder(.black, lineWidth: 4))
            .overlay(alignment: .top) {
                Capsule().fill(.white.opacity(0.28)).frame(height: 8).padding(.horizontal, 18).padding(.top, 7)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("奖杯 \(progress.totalTrophies)，看奖杯之路")
    }

    /// 金币：大号黑边，点一下进商店
    private var coinPill: some View {
        Button {
            sheet = .shop
        } label: {
            HStack(spacing: 6) {
                Text("币")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.35, green: 0.18, blue: 0))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color(red: 1, green: 0.82, blue: 0.2)))
                    .overlay(Circle().strokeBorder(.black, lineWidth: 2))
                Text("\(progress.coins)")
            }
            .font(.system(size: 28, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .arenaOutline(3)
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(Color(red: 0.42, green: 0.28, blue: 0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(.black, lineWidth: 4))
            .overlay(alignment: .top) {
                Capsule().fill(.white.opacity(0.28)).frame(height: 8).padding(.horizontal, 18).padding(.top, 7)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("金币 \(progress.coins)，打开商店")
    }

    /// 宝石先占位，和金币对齐，还不能花
    private var gemPill: some View {
        HStack(spacing: 6) {
            Text("宝")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color(red: 0.2, green: 0.85, blue: 0.95)))
                .overlay(Circle().strokeBorder(.black, lineWidth: 2))
            Text("0")
        }
        .font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
        .foregroundStyle(.white.opacity(0.7))
        .arenaOutline(2)
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(Color(red: 0.08, green: 0.28, blue: 0.34), in: Capsule())
        .overlay(Capsule().strokeBorder(.black, lineWidth: 4))
        .overlay(alignment: .top) {
            Capsule().fill(.white.opacity(0.28)).frame(height: 8).padding(.horizontal, 18).padding(.top, 7)
        }
        .accessibilityLabel("宝石还没开放")
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
                Text("季")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color(red: 0.55, green: 0.32, blue: 0.95)))
                    .overlay(Circle().strokeBorder(.black, lineWidth: 2))
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(state.tier)级")
                    Capsule().fill(.black.opacity(0.45))
                        .frame(width: 70, height: 5)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color(red: 0.7, green: 0.5, blue: 1))
                                .frame(width: 70 * CGFloat(into) / CGFloat(ArenaSeason.pointsPerTier), height: 5)
                        }
                }
            }
            .font(.system(size: 16, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .arenaOutline(2)
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(Color(red: 0.28, green: 0.16, blue: 0.48), in: Capsule())
            .overlay(Capsule().strokeBorder(.black, lineWidth: 4))
            .overlay(alignment: .top) {
                Capsule().fill(.white.opacity(0.28)).frame(height: 8).padding(.horizontal, 18).padding(.top, 7)
            }
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
        VStack(spacing: 8) {
            quietMenu("冒险", symbol: "flag.checkered") { adventure = true }
            quietMenu("角色", symbol: "person.crop.square.fill") { sheet = .brawlers }
            quietMenu("赛季", symbol: "star.circle.fill") { sheet = .season }
            quietMenu("设置", symbol: "gearshape.fill") { sheet = .settings }
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
            .frame(width: 82, height: 72)
        }
        .buttonStyle(ArenaTileButton(face: face, edge: edge))
    }

    private func miniTile(_ title: String, mark: String, face: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(mark)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .arenaOutline(1)
                    .frame(height: 22)
                Text(title)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(face)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.22))
                            .frame(height: 12).padding(.horizontal, 4).padding(.top, 3)
                    }
            )
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
                Text("开打").frame(width: 248)
            }
            .buttonStyle(ArenaGameButton(face: ArenaGameButton.yellow.face, edge: ArenaGameButton.yellow.edge, height: 78))
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
            .frame(width: 268, height: 82)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(playMode.tint))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.black, lineWidth: 4))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.black.opacity(0.55))
                    .offset(y: 6)
            )
            .padding(.bottom, 6)
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
        if item == .diagnostics {
            ArenaDiagnosticSuiteView()
        } else if item == .settings {
            ArenaMenuScreen(title: "设置", onClose: { sheet = nil }) { settingsPanel }
        } else {
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
            case .diagnostics: EmptyView()
            }
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
        case .diagnostics: return "持续性能诊断"
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
        case .diagnostics: return .purple
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            ArenaMenuCard {
                Text(ArenaPerfRecorder.identity).font(.caption.monospaced()).textSelection(.enabled)
                Button("一键连续性能诊断 / 导出") { sheet = .diagnostics }
                    .padding(12).buttonStyle(ArenaMenuButtonStyle())
            }
            ArenaAudioSettingsView()
            settingsCard {
                ArenaMenuToggle(title: "显示对局性能", isOn: $performanceOverlay)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .tint(.green)
                    .foregroundStyle(.white)
                Text("单项性能对照").font(.headline)
                ForEach(ArenaDiagnostics.Variant.allCases, id: \.rawValue) { variant in
                    Button { diagnosticVariant = variant.rawValue } label: {
                        HStack {
                            Text(variant.title)
                            Spacer()
                            Image(systemName: diagnosticVariant == variant.rawValue ? "checkmark.circle.fill" : "circle")
                        }.padding(10).frame(minHeight: 44)
                    }.buttonStyle(ArenaMenuButtonStyle())
                }
                ArenaMenuToggle(title: "峡谷紫色视觉样板", isOn: $purpleSample)
                Button("运行固定混战样板（6角色 / 峡谷 / 种子170017）") {
                    pendingBenchmark = ArenaEntry(setup: ArenaController.Setup(mode: .zone, brawler: .ranger, name: "压测", level: 3,
                                                                       loadout: ArenaLoadout.basic(.ranger, level: 3), benchmark: true))
                    sheet = nil
                }.buttonStyle(ArenaMenuButtonStyle())

                Text("对照项一次只改一项，重启 App 生效。样板只换峡谷视觉；玩法与碰撞不变。对局左上角可复制性能报告。")
                    .font(.caption).foregroundStyle(.white.opacity(0.85))
                Text("下一局显示刷新回调间隔（非渲染帧率）。开启后重启 App 可记录冷加载及分项 CPU 峰值；GPU 耗时需真机工具测量。")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
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
        ArenaMenuCard { content() }
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
            .task { await ArenaPortraits.shared.prepare() }
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
                Text("\(item.role) · 血 \(Int((Double(item.health(level: progress.level(item))) * ArenaGame.playerEdge).rounded()))")
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
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(chosen == item ? Color(red: 0.16, green: 0.28, blue: 0.5) : Color(red: 0.08, green: 0.12, blue: 0.22)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(chosen == item ? Color(red: 1, green: 0.86, blue: 0.2) : roleEdge(item), lineWidth: 4))
    }

    /// 角色墙的色边：近战红、远程蓝、肉盾金、法术紫、治疗绿。不是稀有度，只是一眼能分开
    private func roleEdge(_ item: Brawler) -> Color {
        switch item {
        case .knight, .barbarian, .swordsman: return Color(red: 0.86, green: 0.28, blue: 0.22)
        case .ranger, .assassin, .shade, .darter: return Color(red: 0.28, green: 0.55, blue: 1)
        case .guardian, .brewer: return Color(red: 0.95, green: 0.64, blue: 0.16)
        case .mage, .necromancer, .summoner: return Color(red: 0.62, green: 0.38, blue: 0.95)
        case .scholar: return Color(red: 0.28, green: 0.78, blue: 0.42)
        }
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
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(item.tint.opacity(mode == item ? 1 : 0.88)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(mode == item ? Color(red: 1, green: 0.86, blue: 0.2) : .black, lineWidth: mode == item ? 4 : 3))
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
            Text("现在有 \(progress.coins) 金币。升级后血 \(Int((Double(chosen.health(level: level)) * ArenaGame.playerEdge).rounded())) → \(Int((Double(chosen.health(level: min(level + 1, ArenaProgress.maxLevel))) * ArenaGame.playerEdge).rounded()))，伤害同样多 6%。")
        }
    }

    private var togetherList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("和同事开一局。面对面，或者用同一个 4 位房间号。")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            roomActions(players: 2)
        }
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
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.1, green: 0.18, blue: 0.36)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.black, lineWidth: 3))
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
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(red: 0.18, green: 0.4, blue: 0.85)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black, lineWidth: 3))
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
                HStack(spacing: 8) {
                    Button {
                        partySize = max(3, partySize - 1)
                    } label: {
                        Text("−").frame(width: 52)
                    }
                    .buttonStyle(ArenaGameButton(face: ArenaGameButton.blue.face, edge: ArenaGameButton.blue.edge, height: 44))
                    Text("\(partySize) 个人")
                        .font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .arenaOutline(1.2)
                        .frame(maxWidth: .infinity)
                    Button {
                        partySize = min(6, partySize + 1)
                    } label: {
                        Text("+").frame(width: 52)
                    }
                    .buttonStyle(ArenaGameButton(face: ArenaGameButton.green.face, edge: ArenaGameButton.green.edge, height: 44))
                }
            }
            roomActions(players: partySize)
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

    /// 组队、和同事打：厚色块，不用系统列表
    private func roomActions(players: Int) -> some View {
        let nick = GameProfile.nickname.isEmpty ? name : GameProfile.nickname
        return VStack(spacing: 8) {
            Button {
                pendingRoom = GameRoom(kind: .arena, mode: .nearbyHost, name: nick, capacity: players)
                sheet = nil
            } label: {
                Text("开房间").frame(maxWidth: .infinity)
            }
            .buttonStyle(ArenaGameButton(face: ArenaGameButton.green.face, edge: ArenaGameButton.green.edge, height: 48))
            Button {
                pendingRoom = GameRoom(kind: .arena, mode: .nearbyGuest, name: nick, capacity: players)
                sheet = nil
            } label: {
                Text("加入身边的人").frame(maxWidth: .infinity)
            }
            .buttonStyle(ArenaGameButton(face: ArenaGameButton.blue.face, edge: ArenaGameButton.blue.edge, height: 48))
            HStack(spacing: 8) {
                TextField("4 位房间号", text: $roomCode)
                    .keyboardType(.numberPad)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
                Button("进房间") {
                    guard let room = RoomCode.parse(roomCode) else {
                        ToastCenter.shared.show("房间号是 4 位数", style: .warning)
                        return
                    }
                    let count = RoomCode.players(of: room)
                    pendingRoom = GameRoom(kind: .arena, mode: .remote(code: room), name: nick, capacity: count)
                    sheet = nil
                }
                .buttonStyle(ArenaGameButton(face: ArenaGameButton.yellow.face, edge: ArenaGameButton.yellow.edge, height: 44))
            }
        }
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
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(skin.color.opacity(owned ? 0.55 : 0.92)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.black, lineWidth: wearing ? 4 : 3))
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
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(red: 0.12, green: 0.11, blue: 0.25), Color(red: 0.29, green: 0.20, blue: 0.40)], startPoint: .top, endPoint: .bottom)
                Canvas { context, size in
                    // Original static silhouettes: no perpetual animation or image textures.
                    for layer in 0..<2 {
                        var ridge = Path()
                        let y = size.height * (layer == 0 ? 0.58 : 0.72)
                        ridge.move(to: CGPoint(x: 0, y: size.height))
                        for i in 0...12 {
                            let x = size.width * CGFloat(i) / 12
                            let peak = CGFloat((i * 7 + layer * 3) % 5) * size.height * 0.035
                            ridge.addLine(to: CGPoint(x: x, y: y - peak))
                        }
                        ridge.addLine(to: CGPoint(x: size.width, y: size.height))
                        ridge.closeSubpath()
                        context.fill(ridge, with: .color(layer == 0 ? Color(red: 0.19, green: 0.15, blue: 0.31) : Color(red: 0.14, green: 0.11, blue: 0.23)))
                    }
                    let floor = Path(ellipseIn: CGRect(x: size.width * 0.18, y: size.height * 0.63, width: size.width * 0.64, height: size.height * 0.52))
                    context.fill(floor, with: .color(Color(red: 0.25, green: 0.19, blue: 0.33)))
                }
                RadialGradient(colors: [Color(red: 0.57, green: 0.45, blue: 0.68).opacity(0.42), .clear], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 10, endRadius: geo.size.width * 0.34)
            }
        }
        .ignoresSafeArea()
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
    private(set) static var activeDisplayLinks = 0
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
        rendersContinuously = false
        isPlaying = false
        world.background.contents = UIColor.clear
        scene = world
        build()
        show(brawler, skin: skin)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragged(_:))))
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        isAccessibilityElement = true
        accessibilityLabel = "选的角色，左右拖着转"
        NotificationCenter.default.addObserver(self, selector: #selector(suspendRendering), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resumeRendering), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("不从文件里读") }

    private func build() {
        let camera = SCNCamera()
        camera.fieldOfView = 32
        camera.zNear = 0.08
        camera.zFar = 40
        let eye = SCNNode()
        eye.camera = camera
        // 人站近一点，头和武器都在画面里，不要缩成台子上的一个小点
        eye.simdPosition = SIMD3(0.42, 1.62, 4.15)
        eye.simdEulerAngles = SIMD3(-0.2, 0.1, 0)
        world.rootNode.addChildNode(eye)
        pointOfView = eye

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 220
        ambient.light?.color = UIColor(red: 0.85, green: 0.88, blue: 1, alpha: 1)
        world.rootNode.addChildNode(ambient)
        // 主光：暖的，从左前上方打，脸上有明暗
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 980
        key.light?.color = UIColor(red: 1, green: 0.94, blue: 0.82, alpha: 1)
        key.simdOrientation = simd_quatf(from: SIMD3(0, 0, -1), to: simd_normalize(SIMD3(-0.55, -0.85, -1)))
        world.rootNode.addChildNode(key)
        // 补光：冷一点，从右前把阴影托起来，别发灰
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .omni
        fill.light?.intensity = 380
        fill.light?.color = UIColor(red: 0.7, green: 0.82, blue: 1, alpha: 1)
        fill.simdPosition = SIMD3(1.6, 1.5, 2.4)
        world.rootNode.addChildNode(fill)
        // 轮廓光：从背后勾边
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 640
        rim.light?.color = UIColor(red: 0.55, green: 0.72, blue: 1, alpha: 1)
        rim.simdOrientation = simd_quatf(from: SIMD3(0, 0, -1), to: simd_normalize(SIMD3(0.25, -0.35, 1)))
        world.rootNode.addChildNode(rim)

        // 台子：金边的圆台，描一圈深色的边，上面一块影子
        let height: Float = 0.22
        let top = SCNCylinder(radius: 0.95, height: CGFloat(height))
        top.radialSegmentCount = 6
        let side = SCNMaterial()
        side.lightingModel = .lambert
        side.diffuse.contents = UIColor(red: 0.27, green: 0.18, blue: 0.37, alpha: 1)
        let face = SCNMaterial()
        face.lightingModel = .lambert
        face.diffuse.contents = UIColor(red: 0.55, green: 0.40, blue: 0.63, alpha: 1)
        top.materials = [side, face, side]
        let pedestal = SCNNode(geometry: top)
        pedestal.simdPosition = SIMD3(0, height / 2, 0)
        world.rootNode.addChildNode(pedestal)
        let rimGeometry = SCNCylinder(radius: 0.99, height: CGFloat(height + 0.06))
        rimGeometry.radialSegmentCount = 6
        let ink = SCNMaterial()
        ink.lightingModel = .constant
        ink.diffuse.contents = UIColor(red: 0.12, green: 0.08, blue: 0.2, alpha: 1)
        ink.cullMode = .front
        rimGeometry.firstMaterial = ink
        let outline = SCNNode(geometry: rimGeometry)
        outline.simdPosition = pedestal.simdPosition
        world.rootNode.addChildNode(outline)
        let shadow = SCNCylinder(radius: 0.72, height: 0.002)
        shadow.radialSegmentCount = 32
        shadow.firstMaterial = ArenaAvatar.decal(UIColor.black.withAlphaComponent(0.42))
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.simdPosition = SIMD3(0, height + 0.002, 0)
        shadowNode.renderingOrder = 2
        world.rootNode.addChildNode(shadowNode)
        let deck = SCNCylinder(radius: 0.7, height: 0.018)
        deck.radialSegmentCount = 6
        let deckMaterial = SCNMaterial()
        deckMaterial.lightingModel = .constant
        deckMaterial.diffuse.contents = UIColor(red: 0.48, green: 0.34, blue: 0.58, alpha: 1)
        deck.firstMaterial = deckMaterial
        let deckNode = SCNNode(geometry: deck)
        deckNode.simdPosition = SIMD3(0, height + 0.012, 0)
        deckNode.castsShadow = false
        world.rootNode.addChildNode(deckNode)
        let ring = SCNTorus(ringRadius: 0.74, pipeRadius: 0.018)
        ring.ringSegmentCount = 48
        ring.pipeSegmentCount = 12
        let gold = SCNMaterial()
        gold.lightingModel = .constant
        gold.diffuse.contents = UIColor(red: 0.72, green: 0.54, blue: 0.77, alpha: 1)
        ring.firstMaterial = gold
        let ringNode = SCNNode(geometry: ring)
        ringNode.simdPosition = SIMD3(0, height + 0.02, 0)
        ringNode.castsShadow = false
        world.rootNode.addChildNode(ringNode)

        stage.simdPosition = SIMD3(0, height, 0)
        world.rootNode.addChildNode(stage)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fitShowcaseCamera()
    }

    /// Fit a conservative model envelope; layout controls keep their own size.
    private func fitShowcaseCamera() {
        guard bounds.width > 0, bounds.height > 0, let eye = pointOfView, let camera = eye.camera else { return }
        // Aggregate only visible geometry. Node.boundingBox includes hidden shields,
        // weapons and malformed accessories, which shrank the hero in Build 389.
        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        func include(_ node: SCNNode) {
            guard !node.isHidden else { return }
            if let geometry = node.geometry {
                let (a, b) = geometry.boundingBox
                for x in [a.x, b.x] { for y in [a.y, b.y] { for z in [a.z, b.z] {
                    let p = node.simdConvertPosition(SIMD3(x, y, z), to: stage)
                    low = simd_min(low, p)
                    high = simd_max(high, p)
                } } }
            }
            node.childNodes.forEach(include)
        }
        include(stage)
        guard low.x.isFinite, high.x.isFinite, low.y < high.y else { return }
        let height = max(high.y - min(low.y, 0), 1.2)
        let halfWidth = max(abs(low.x), abs(high.x), 0.65) * 1.15
        let halfHeight = height * 0.6
        let aspect = Float(bounds.width / bounds.height)
        let tangent = tan(Float(camera.fieldOfView) * .pi / 360)
        let distance = max(halfHeight / tangent, halfWidth / (tangent * aspect)) + max(abs(low.z), abs(high.z), 0.2)
        let target = stage.convertPosition(SCNVector3(0, height * 0.5, 0), to: nil)
        eye.position = SCNVector3(0.15, target.y + distance * 0.06, distance)
        eye.look(at: target)
    }

    /// 换角色、换皮肤：换模型，先欢呼一下
    func show(_ brawler: Brawler, skin: Int = 0) {
        guard avatar?.brawler != brawler || skin != wearing else { return }
        avatar?.node.removeFromParentNode()
        let made = ArenaAvatar(brawler: brawler, color: .clear, isMe: false, decorated: false, size: 0.86, skin: skin, stageLit: true)
        stage.addChildNode(made.node)
        avatar = made
        wearing = skin
        fighter.brawler = brawler
        cheerUntil = clock + 1.6
        made.update(fighter, visible: true, translucent: false, cheering: false, dt: 0, clock: clock)
        fitShowcaseCamera()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else { start() }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func suspendRendering() {
        let resume = wantsPlayback
        stop()
        wantsPlayback = resume
    }
    @objc private func resumeRendering() {
        // A sheet or match can intentionally stop this showcase while it remains in a window.
        if wantsPlayback { start() }
    }
    private var wantsPlayback = false

    func start() {
        wantsPlayback = true
        guard window != nil, UIApplication.shared.applicationState == .active else { return }
        rendersContinuously = true
        isPlaying = false
        guard link == nil else { return }
        let target = ShowcaseTarget(view: self)
        let link = CADisplayLink(target: target, selector: #selector(ShowcaseTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        self.link = link
        Self.activeDisplayLinks += 1
    }

    func stop() {
        wantsPlayback = false
        if link != nil { Self.activeDisplayLinks -= 1 }
        link?.invalidate()
        link = nil
        lastTimestamp = nil
        rendersContinuously = false
        isPlaying = false
    }

    fileprivate func tick(_ timestamp: CFTimeInterval) {
        guard link != nil, window != nil, UIApplication.shared.applicationState == .active else { return }
        let dt = Float(min(max(timestamp - (lastTimestamp ?? timestamp), 0), 0.1))
        lastTimestamp = timestamp
        clock += Double(dt)
        if !dragging { spin *= max(0, 1 - dt * 1.5) }
        spin = min(1.6, max(-1.6, spin))
        let angle = 0.35 * Float(sin(clock * 0.6)) + spin
        fighter.facing = V2(Double(sin(angle)), Double(cos(angle)))
        avatar?.update(fighter, visible: true, translucent: false, cheering: clock < cheerUntil, dt: dt, clock: clock)
        if !dragging, clock > cheerUntil, clock > nextSwing {
            avatar?.showcaseSwing()
            nextSwing = clock + 4.8
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
