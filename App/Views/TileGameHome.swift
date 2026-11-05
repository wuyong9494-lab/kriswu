import SwiftUI

struct TileGameHomeView: View {
    @ObservedObject private var records = TileRecordStore.shared
    @State private var play: TilePlay?
    @State private var code = ""
    @State private var lobby: GameRoomEntry?
    @State private var social = false
    @State private var help = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                journey
                quickPlay
                daily
                challenge
                Button { social = true } label: {
                    Label("和朋友比一局", systemImage: "person.2.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(18)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                Button("玩法与星级") { help = true }.font(.subheadline).foregroundStyle(.white.opacity(0.65))
            }
            .padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .background(TileStarfield().ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .navigationTitle("星旅")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(TileTheme.navy, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fullScreenCover(item: $play) { TileBoardView(play: $0, race: nil) }
        .fullScreenCover(item: $lobby) { TileRaceLobbyView(room: $0.room) }
        .sheet(isPresented: $social) {
            NavigationStack {
                List {
                    GameRoomButtons(kind: .tiles, remotePlayers: 2...4, nearbyCapacity: TileRaceGame.most) { entry in
                        social = false
                        // 等连接面板收起再呈现房间，避免两个呈现动作竞争。
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            lobby = GameRoomEntry(room: entry)
                        }
                    }
                }
                .navigationTitle("经典竞速")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { social = false } } }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $help) { helpSheet }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("叠叠消").font(.system(size: 37, weight: .heavy, design: .rounded))
                    Text("留一格，想三步。")
                        .font(.system(.subheadline, design: .rounded)).foregroundStyle(.white.opacity(0.65))
                    Label("\(records.journey.totalStars) / 36", systemImage: "star.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(TileTheme.gold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    Circle().stroke(TileTheme.mint.opacity(0.18), lineWidth: 1).frame(width: 130, height: 130)
                    TileFace(kind: 7, side: 63).rotationEffect(.degrees(18)).offset(x: 37, y: -22)
                    TileFace(kind: 0, side: 65).rotationEffect(.degrees(-18)).offset(x: -31, y: -12)
                    TileFace(kind: 2, side: 73).rotationEffect(.degrees(5)).offset(x: 7, y: 29)
                }
                .frame(width: 140, height: 145).accessibilityHidden(true)
            }
            Button { open(records.journey.nextStage) } label: {
                HStack {
                    Text("\(records.journey.totalStars == 36 ? "再闯" : "出发") · 第 \(records.journey.nextStage.id) 关")
                    Spacer()
                    Text(records.journey.nextStage.name).font(.subheadline)
                    Image(systemName: "arrow.right")
                }
                .padding(.horizontal, 18)
            }
            .buttonStyle(TilePrimaryButton())
            .accessibilityIdentifier("tiles.continue")
        }
    }

    private var journey: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("星域航程", detail: "12 关 · 逐关解锁")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(TileJourney.stages) { stage in
                    let unlocked = records.journey.isUnlocked(stage.id)
                    Button { open(stage) } label: {
                        VStack(spacing: 9) {
                            HStack {
                                Text(String(format: "%02d", stage.id)).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                                Spacer()
                                Image(systemName: unlocked ? "sparkle" : "lock.fill")
                                    .font(.system(size: 13)).foregroundStyle(unlocked ? TileTheme.mint : .white.opacity(0.2))
                            }
                            Text(stage.name).font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                            TileStars(count: records.journey.stars[stage.id] ?? 0).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(13)
                        .foregroundStyle(.white.opacity(unlocked ? 1 : 0.38))
                        .background(unlocked ? TileTheme.panel : .white.opacity(0.025), in: RoundedRectangle(cornerRadius: 17))
                        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(unlocked ? TileTheme.mint.opacity(0.22) : .white.opacity(0.06)))
                    }
                    .buttonStyle(.plain).disabled(!unlocked)
                    .accessibilityIdentifier("tiles.stage.\(stage.id)")
                    .accessibilityLabel("第 \(stage.id) 关，\(stage.name)，\(unlocked ? "已解锁" : "未解锁")")
                }
            }
        }
    }

    private var quickPlay: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("自由挑战", detail: "每次都是新牌局")
            HStack(spacing: 10) {
                ForEach(TileGame.Level.allCases, id: \.self) { level in
                    Button { play = TilePlay(level: level, seed: UInt64.random(in: 0..<TileGame.seedLimit), mode: .solo) } label: {
                        VStack(spacing: 10) {
                            TileGlyph(kind: [4, 7, 2][level.rawValue - 1]).frame(width: 44, height: 44)
                            Text(TileTheme.title(level)).font(.system(.headline, design: .rounded))
                            Text(["6 种 · 4 层", "10 种 · 6 层", "12 种 · 8 层"][level.rawValue - 1]).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("tiles.quick.\(level.rawValue)")
                }
            }
        }
    }

    private var daily: some View {
        Button { play = TilePlay(level: .hard, seed: TileGame.dailySeed(.today), mode: .daily(.today)) } label: {
            HStack(spacing: 16) {
                Image(systemName: "sun.max.fill").font(.system(size: 26)).foregroundStyle(TileTheme.gold)
                VStack(alignment: .leading, spacing: 5) {
                    Text("今日深空挑战").font(.headline)
                    Text(records.constellationRecords.daily[DayKey.today.description]?.won == true ? "今日已通关，再试一次更高连消" : "每天一张大师牌局，大家同盘比拼")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
            }
            .padding(20).background(TileTheme.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain).accessibilityIdentifier("tiles.daily")
    }

    private var challenge: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("接一张挑战书", detail: "新旧挑战码均可")
            HStack(spacing: 10) {
                TextField("输入或粘贴挑战码", text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(.system(.subheadline, design: .monospaced)).padding(14)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("tiles.code")
                Button {
                    guard let decoded = TileGame.decode(code) else {
                        ToastCenter.shared.show("挑战码不完整，请粘贴朋友分享的整段文字", style: .warning)
                        return
                    }
                    play = TilePlay(level: decoded.level, seed: decoded.seed, mode: .challenge, ruleSet: decoded.ruleSet)
                } label: {
                    Image(systemName: "arrow.right").font(.headline).frame(width: 46, height: 46)
                        .background(TileTheme.mint, in: RoundedRectangle(cornerRadius: 13)).foregroundStyle(TileTheme.ink)
                }
                .buttonStyle(.plain).disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("开始挑战")
            }
        }
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.system(.headline, design: .rounded))
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.white.opacity(0.45))
        }
    }

    private func open(_ stage: TileJourney.Stage) {
        guard records.journey.isUnlocked(stage.id) else { return }
        play = TilePlay(level: stage.level, seed: stage.seed, mode: .journey(stage.id))
    }

    private var helpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    helpRow("01", "先看遮挡，再选牌", "只能拿没有被压住的牌。三张相同自动消除，槽内七张未能消除就会卡住。底部两摞也是牌堆，需要逐层取出。")
                    helpRow("02", "给下一组三张留位置", "越往深空走，牌种越多、遮挡越复杂。不要见一对就拿，先想第三张被谁压住。每个初始牌局都有通关路径。")
                    helpRow("03", "连消靠规划，不靠手速", "每次消除后的四次取牌内再消除，连消加一；单次得分从 100 分递增，五连及以上每次 500 分。使用道具会中断连消。")
                    helpRow("04", "把一星变成三星", "通关得一星；不用道具得两星；再达到轻松 3 连、进阶 4 连、大师 5 连即可三星。成绩只保留最好的一次。")
                    helpRow("05", "道具各用一次", "撤回上一张未消除的牌；移出槽左侧最多三张；洗牌只打乱牌堆中的图案。洗牌不会替你清槽，也不保证当前选择能被挽回。")
                }
                .padding(24)
            }
            .background(TileTheme.navy).navigationTitle("玩法与星级")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("明白了") { help = false } } }
        }
        .preferredColorScheme(.dark)
    }

    private func helpRow(_ index: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(index)  \(title)").font(.headline).foregroundStyle(TileTheme.mint)
            Text(detail).font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineSpacing(5)
        }
    }
}
