import SceneKit
import SwiftUI
import UIKit
import simd

// MARK: - 大厅

/// 勇者乱斗的大厅（iPhone 上横着）：中间是自己选的角色（3D，站在台子上，手指拖着能转、点一下出手），
/// 上边奖杯、金币、名字，左边「角色」「奖杯之路」「和同事打」，右下带的本事、玩法卡片和大大的「开打」
struct ArenaHomeView: View {
    @ObservedObject private var records = ArenaRecords.shared
    @ObservedObject private var growth = ArenaProgressStore.shared
    @State private var mode = ArenaGame.Mode(rawValue: UserDefaults.standard.string(forKey: "arena.mode") ?? "") ?? .teamFight
    @State private var brawler = Brawler(rawValue: UserDefaults.standard.integer(forKey: "arena.brawler")) ?? .knight
    @State private var playing: ArenaEntry?
    @State private var lobby: LobbyEntry?
    @State private var sheet: Sheet?
    /// 在「和同事打」里开的房间（面板收起来以后再进房间）
    @State private var pendingRoom: GameRoom?
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
        case brawlers, modes, loadout, road, together
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
                ArenaShowcase(brawler: chosen)
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
        .sheet(item: $sheet, onDismiss: {
            guard let room = pendingRoom else { return }
            pendingRoom = nil
            lobby = LobbyEntry(lobby: ArenaLobby(room: room, mode: mode, brawler: chosen))
        }) { item in
            sheetContent(item)
        }
        .fullScreenCover(item: $playing) { entry in
            ArenaPlayView(setup: entry.setup)
        }
        .fullScreenCover(item: $lobby) { entry in
            ArenaRoomView(lobby: entry.lobby)
        }
    }

    // MARK: 上边

    private var topBar: some View {
        HStack(spacing: DS.Space.s) {
            Button {
                ArenaOrientation.releaseAll()
                dismiss()
            } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.3), in: Circle())
            }
            .accessibilityLabel("离开勇者乱斗")
            trophyPill
            pill {
                Image(systemName: "dollarsign.circle.fill").foregroundStyle(.yellow)
                Text("\(progress.coins)")
            }
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
        VStack(spacing: DS.Space.s) {
            tile("角色", face: Color(red: 0.25, green: 0.55, blue: 1), edge: Color(red: 0.1, green: 0.3, blue: 0.7)) {
                BrawlerBadge(brawler: chosen, size: 40)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            } action: {
                sheet = .brawlers
            }
            tile("奖杯之路", face: Color(red: 1, green: 0.6, blue: 0.15), edge: Color(red: 0.7, green: 0.36, blue: 0.02)) {
                Image(systemName: "flag.checkered").font(.system(size: 24, weight: .black)).foregroundStyle(.white)
            } action: {
                sheet = .road
            }
            tile("和同事打", face: Color(red: 0.3, green: 0.78, blue: 0.4), edge: Color(red: 0.12, green: 0.48, blue: 0.18)) {
                Image(systemName: "person.3.fill").font(.system(size: 21, weight: .black)).foregroundStyle(.white)
            } action: {
                sheet = .together
            }
        }
    }

    /// 左边的方块按钮：上面图标、下面字，底下一道深色的边
    private func tile<Icon: View>(_ title: String, face: Color, edge: Color, @ViewBuilder icon: () -> Icon,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                icon().frame(height: 42)
                Text(title)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .arenaOutline(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 76, height: 70)
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
            loadoutChips
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

    /// 现在的玩法：颜色、图标、名字、赢了几局；点一下换
    private var modeCard: some View {
        Button {
            sheet = .modes
        } label: {
            HStack(spacing: 10) {
                Image(systemName: mode.icon)
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.black.opacity(0.22)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.title)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .arenaOutline(1.2)
                    Text(records.tally.played[mode.rawValue].map { "赢了 \(records.tally.won[mode.rawValue] ?? 0)/\($0) 局" } ?? "点一下换玩法")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .black)).foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 10)
            .frame(width: 244, height: 58)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(mode.tint))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.65), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("玩法：\(mode.title)，点一下换")
    }

    private func start() {
        playing = ArenaEntry(setup: ArenaController.Setup(mode: mode, brawler: chosen, name: name, level: progress.level(chosen),
                                                          lineup: duelPartners, loadout: progress.loadout(for: chosen)))
    }

    // MARK: 面板

    @ViewBuilder private func sheetContent(_ item: Sheet) -> some View {
        NavigationStack {
            Group {
                switch item {
                case .brawlers: brawlerGrid
                case .modes: modeList
                case .loadout: loadoutList
                case .road: ArenaTrophyRoad()
                case .together: togetherList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { sheet = nil }
                }
            }
        }
    }

    private var brawlerGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: DS.Space.s)], spacing: DS.Space.s) {
                ForEach(Brawler.allCases, id: \.self) { item in
                    Button {
                        brawler = item
                        UserDefaults.standard.set(item.rawValue, forKey: "arena.brawler")
                        sheet = nil
                    } label: {
                        brawlerCard(item)
                    }
                    .buttonStyle(.plain)
                    .disabled(!progress.isUnlocked(item))
                }
            }
            .padding(DS.Space.m)
            Text("每升一级血量、伤害多 6%，最高 \(ArenaProgress.maxLevel) 级；3、5 级解锁小道具，6、8 级解锁星徽，9 级解锁超级充能。联机时电脑补位的按大家的平均等级。")
                .font(DS.Font.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DS.Space.m)
                .padding(.bottom, DS.Space.l)
        }
        .background(DS.Palette.background)
        .navigationTitle("选角色")
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
            Text(item.name).font(.system(size: 16, weight: .black, design: .rounded)).foregroundStyle(.primary)
            Text(item.role).font(DS.Font.overline).foregroundStyle(.secondary)
            if unlocked {
                HStack(spacing: 8) {
                    Label("\(progress.trophies(item))", systemImage: "trophy.fill").foregroundStyle(.orange)
                    Text("\(level) 级").foregroundStyle(DS.Palette.accent)
                }
                .font(DS.Font.caption.weight(.semibold).monospacedDigit())
            } else {
                Text("总奖杯到 \(item.unlockAt) 解锁").font(DS.Font.caption).foregroundStyle(.secondary)
            }
            Text(item.attackNote + "。" + item.superNote)
                .font(DS.Font.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
        }
        .padding(DS.Space.s)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(chosen == item ? DS.Palette.accentSoft : DS.Palette.surfaceSunken))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(chosen == item ? DS.Palette.accent : .clear, lineWidth: 2))
    }

    private var modeList: some View {
        List {
            Section {
                ForEach(ArenaGame.Mode.allCases, id: \.self) { item in
                    Button {
                        mode = item
                        UserDefaults.standard.set(item.rawValue, forKey: "arena.mode")
                        sheet = nil
                    } label: {
                        modeRow(item)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if mode == .duel {
                        Text("一对一带：" + ([chosen] + duelPartners).map(\.name).joined(separator: "、") + "（按这个顺序上场）")
                    }
                    Text("左下角摇杆走；右下角摇杆拖着瞄准、松手开火，点一下自动打最近的敌人；黄圈满了放大招，绿钮是小道具。躲进草丛里敌人看不见你（离得很近或者你开火时除外）。")
                }
            }
        }
        .appList()
        .navigationTitle("选玩法")
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
                    Text(item.title).font(DS.Font.headline).foregroundStyle(.primary)
                    if mode == item {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.Palette.accent)
                    }
                    Spacer()
                    if let played = records.tally.played[item.rawValue] {
                        Text("赢了 \(records.tally.won[item.rawValue] ?? 0)/\(played)").font(DS.Font.caption).foregroundStyle(.secondary)
                    }
                }
                Text(item.rules).font(DS.Font.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var loadoutList: some View {
        List {
            upgradeSection
            ArenaLoadoutSection(brawler: chosen)
        }
        .appList()
        .navigationTitle("\(chosen.name)的本事")
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
        .appList()
        .navigationTitle("和同事一起打")
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
                    .frame(width: 1600, height: 1600)
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

    func makeUIView(context: Context) -> ArenaShowcaseView {
        ArenaShowcaseView(brawler: brawler)
    }

    func updateUIView(_ view: ArenaShowcaseView, context: Context) {
        view.show(brawler)
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

    init(brawler: Brawler) {
        fighter = Fighter(id: 0, name: "", team: 0, brawler: brawler, isBot: false, level: 1, pos: .zero, facing: V2(0, 1), health: 1)
        super.init(frame: .zero, options: nil)
        backgroundColor = .clear
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 60
        rendersContinuously = true
        isPlaying = true
        world.background.contents = UIColor.clear
        scene = world
        build()
        show(brawler)
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

    /// 换角色：换模型，先欢呼一下
    func show(_ brawler: Brawler) {
        guard avatar?.brawler != brawler else { return }
        avatar?.node.removeFromParentNode()
        let made = ArenaAvatar(brawler: brawler, color: .clear, isMe: false, decorated: false)
        stage.addChildNode(made.node)
        avatar = made
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
