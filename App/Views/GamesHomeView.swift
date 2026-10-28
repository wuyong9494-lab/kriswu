import SwiftUI

/// 小游戏里共用的：面对面时别人看到的名字
enum GameProfile {
    private static let key = "games.nickname"

    static var nickname: String {
        get { UserDefaults.standard.string(forKey: key) ?? UserDefaults.standard.string(forKey: "tileGame.nickname") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// 小游戏：各个游戏的入口
struct GamesHomeView: View {
    /// 勇者乱斗的大厅是全屏横着的
    @State private var showingArena = false

    var body: some View {
        List {
            Section {
                Button {
                    showingArena = true
                } label: {
                    HStack {
                        row("勇者乱斗", "3D 横屏双摇杆对战：11 种玩法、13 个角色、小道具和星徽，电脑补位，也能和同事一起打", "flame.fill", 3)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .foregroundStyle(.primary)
                NavigationLink { TileGameHomeView() } label: {
                    row("叠叠消", "三张一样的凑一起消掉；今日挑战、挑战码、和同事比谁先消完", "square.stack.3d.up.fill", 6)
                }
                NavigationLink { GomokuHomeView() } label: {
                    row("五子棋", "和电脑下、两个人一台手机下、面对面、远程，或者轮流下（不用同时在线）", "circle.grid.3x3.fill", 0)
                }
            } footer: {
                Text("面对面：身边的手机直接连，不用联网。远程、轮流下：用苹果的 Game Center，大家在手机「设置 › Game Center」登录自己的 Apple ID；对方手机上也要装着值班提醒，最好是同一个版本。")
            }
        }
        .appList()
        .navigationTitle("小游戏")
        .fullScreenCover(isPresented: $showingArena) {
            ArenaHomeView()
        }
    }

    private func row(_ title: String, _ note: String, _ icon: String, _ color: Int) -> some View {
        HStack(spacing: DS.Space.s) {
            IconBadge(icon: icon, color: DS.Palette.vivid[color], size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.Font.headline)
                Text(note).font(DS.Font.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 联机房间（各个游戏共用）

/// 开一个联机房间要的：面对面开房间 / 加入，或者远程房间号
struct GameRoomEntry: Identifiable {
    let id = UUID()
    let room: GameRoom
}

/// 和别人玩的几个按钮：面对面开房间、加入，远程输房间号。players：远程几个人（房间号第一位）
struct GameRoomButtons: View {
    let kind: GameKind
    /// 远程可以选几个人（五子棋只有 2）
    var remotePlayers: ClosedRange<Int> = 2...2
    var nearbyCapacity = 2
    var onOpen: (GameRoom) -> Void
    @State private var nickname = GameProfile.nickname
    @State private var code = ""
    @State private var players = 2
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Section {
            TextField("面对面时别人看到的名字", text: $nickname)
                .onChange(of: nickname) { GameProfile.nickname = $0 }
            Button {
                onOpen(GameRoom(kind: kind, mode: .nearbyHost, name: nickname, capacity: nearbyCapacity))
            } label: {
                Label("开房间", systemImage: "person.3")
            }
            Button {
                onOpen(GameRoom(kind: kind, mode: .nearbyGuest, name: nickname, capacity: nearbyCapacity))
            } label: {
                Label("加入身边同事的房间", systemImage: "person.badge.plus")
            }
        } header: {
            Text("面对面")
        } footer: {
            Text("手机离得近、打开 Wi-Fi 和蓝牙就行，不用联网。第一次会问能不能使用本地网络，要点允许。")
        }
        .onAppear {
            if nickname.isEmpty { nickname = store.settings.aliases.first ?? "" }
            if !remotePlayers.contains(players) { players = remotePlayers.lowerBound }
        }
        Section {
            if remotePlayers.count > 1 {
                Stepper("\(players) 个人", value: $players, in: remotePlayers)
            }
            HStack {
                TextField("房间号（4 位数）", text: $code)
                    .keyboardType(.numberPad)
                Button("随机一个") { code = String(RoomCode.make(players: players)) }
                    .buttonStyle(.borderless)
            }
            Button {
                guard let room = RoomCode.parse(code) else {
                    ToastCenter.shared.show("房间号是 4 位数，第一位是几个人（比如 2 开头是两个人）", style: .warning)
                    return
                }
                onOpen(GameRoom(kind: kind, mode: .remote(code: room), name: nickname, capacity: RoomCode.players(of: room)))
            } label: {
                Label("进房间", systemImage: "globe.asia.australia")
            }
            .disabled(code.filter(\.isNumber).count != 4)
        } header: {
            Text("远程（不在一起）")
        } footer: {
            Text("一个人点「随机一个」生成房间号发给别人，大家输同一个房间号点「进房间」，人到齐了自动开始。房间号第一位是几个人玩。要联网、登录 Game Center。")
        }
    }
}

/// 房间里还没开始时的样子：等人、找附近的房间、远程配对、房间没了。ready 是人齐了以后游戏自己要放的东西
struct GameRoomLobby<Ready: View>: View {
    @ObservedObject var room: GameRoom
    @ViewBuilder var ready: () -> Ready

    var body: some View {
        if let notice = room.notice {
            Section { Label(notice, systemImage: "exclamationmark.triangle").foregroundStyle(DS.Palette.warning) }
        }
        switch room.phase {
        case .idle:
            Section { ProgressView() }
        case .waiting:
            waiting
        case .browsing, .joining:
            nearbyRooms
        case .ready:
            members
            ready()
        case .closed(let reason):
            Section {
                Label(reason, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
            } footer: {
                Text("点左上角「离开」，再开一次房间。")
            }
        }
    }

    @ViewBuilder private var waiting: some View {
        if let code = room.code {
            Section {
                VStack(spacing: DS.Space.s) {
                    Text("房间号").font(DS.Font.caption).foregroundStyle(.secondary)
                    Text(String(code)).font(DS.Font.hero.monospacedDigit())
                    HStack(spacing: DS.Space.xs) {
                        ProgressView()
                        Text("等 \(RoomCode.players(of: code) - 1) 个人输入这个房间号…").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s)
                Button {
                    let text = "来「值班提醒」里玩\(room.kind.title)：小游戏 › \(room.kind.title) › 远程，房间号 \(code)"
                    ActivityShare.present([text], excluding: ActivityShare.chatOnly) { _ in }
                } label: {
                    Label("把房间号发到微信", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("大家都要登录 Game Center、联网。等的时候别离开这一页。")
            }
        } else {
            Section {
                HStack(spacing: DS.Space.xs) {
                    ProgressView()
                    Text("等身边的同事加入…").foregroundStyle(.secondary)
                }
            } footer: {
                Text("让同事打开「\(room.kind.title)」点「加入身边同事的房间」，找到「\(room.me.name)」点一下。")
            }
        }
    }

    @ViewBuilder private var nearbyRooms: some View {
        Section {
            if room.rooms.isEmpty {
                HStack(spacing: DS.Space.xs) {
                    ProgressView()
                    Text("正在找附近的房间…").foregroundStyle(.secondary)
                }
            }
            ForEach(room.rooms) { nearby in
                Button {
                    room.join(nearby)
                } label: {
                    HStack {
                        Label("\(nearby.name) 的房间", systemImage: "person.3")
                        Spacer()
                        if room.phase == .joining(nearby.name) { ProgressView() }
                    }
                }
                .disabled(room.phase != .browsing)
            }
        } footer: {
            Text("找不到的话：两台手机离近一点，打开 Wi-Fi 和蓝牙；系统问能不能使用本地网络时要点允许（在系统设置 › 隐私与安全性 › 本地网络 里也能打开）。")
        }
    }

    private var members: some View {
        Section {
            ForEach(room.members) { member in
                Label(member.id == room.me.id ? "\(member.name)（我）" : member.name,
                      systemImage: member.id == room.hostID ? "crown.fill" : "person.fill")
            }
        } header: {
            Text("房间里 \(room.members.count) 个人")
        }
    }
}
