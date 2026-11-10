import SwiftUI

/// The landscape lobby keeps the stage continuous and the three local play
/// actions outside every scroll view. Enlarged accessibility text uses the
/// stacked, scrollable layout instead of clipping the side panels.
struct DuelHomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hero = DuelGame.Hero.liu
    @State private var difficulty = DuelGame.Difficulty.learning
    @State private var match: DuelSetup?
    @State private var showingNetworkEntry = false
    @State private var showroomRegion: CGRect?
    private let bronze = Color(red: 0.83, green: 0.66, blue: 0.39)
    private var usesOriginalWeapons: Bool {
        !ProcessInfo.processInfo.arguments.contains("-duel-legacy-controls") && DuelWeaponAssets.catalogURL() != nil
    }
    private var choices: [DuelGame.Hero] { usesOriginalWeapons ? [.ember, .liu] : DuelGame.Hero.allCases }
    private func weaponTitle(_ hero: DuelGame.Hero) -> String { hero == .ember ? "先锋 · 武士刀" : "军团 · 双锤" }
    private func detail(_ hero: DuelGame.Hero) -> String { usesOriginalWeapons ? weaponTitle(hero) : hero.style }
    private var hasShowroom: Bool {
        DuelStageAsset.bundledURL(for: .autumnLobby) != nil &&
            (DuelCharacterAsset.bundledURL(for: hero) != nil || usesOriginalWeapons)
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height && !dynamicTypeSize.isAccessibilitySize
            ZStack {
                LinearGradient(colors: [Color(red: 0.055, green: 0.065, blue: 0.085),
                                        Color(red: 0.16, green: 0.13, blue: 0.11)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                if wide {
                    stage(visibleRegion: showroomRegion)
                        .background(lobbyFrame(.stage))
                        .ignoresSafeArea()
                    // Only the edge scrims darken the scenery. These decorative
                    // layers must never capture the showroom's pan or pinch.
                    LinearGradient(stops: [.init(color: .black.opacity(0.58), location: 0),
                                           .init(color: .clear, location: 0.32),
                                           .init(color: .clear, location: 0.64),
                                           .init(color: .black.opacity(0.58), location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                        .ignoresSafeArea().allowsHitTesting(false)
                    landscapeLobby(width: geometry.size.width)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ZStack(alignment: .bottomLeading) {
                                stage()
                                selectedIdentity.padding(16)
                                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                                    .padding(12)
                            }
                            .frame(height: min(geometry.size.height * 0.47, 380))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            stackedActions
                        }
                        .padding(16)
                    }
                    .accessibilityIdentifier("duel.lobby.actions")
                }
            }
            .foregroundStyle(.white)
            .tint(bronze)
        }
        .coordinateSpace(name: "duel.lobby.layout")
        .onPreferenceChange(DuelLobbyLayoutFrames.self) { frames in
            // Both measurements share a coordinate space, including the scene
            // extending under the navigation bar and home-indicator safe area.
            guard let stage = frames[.stage], let center = frames[.center],
                  stage.width > 0, stage.height > 0 else {
                showroomRegion = nil
                return
            }
            // The header is confined to the side columns. Its empty center
            // continues to the top of the full-screen stage, so do not sacrifice
            // that space and shrink the fighter merely to clear the bottom rail.
            let clear = CGRect(x: center.minX, y: stage.minY,
                               width: center.width, height: center.maxY - stage.minY)
            showroomRegion = CGRect(x: (clear.minX - stage.minX) / stage.width,
                                    y: (clear.minY - stage.minY) / stage.height,
                                    width: clear.width / stage.width, height: clear.height / stage.height)
        }
        .navigationBarTitleDisplayMode(.inline)
        .modifier(ArenaLandscape())
        .fullScreenCover(item: $match) { DuelMatchView(setup: $0) }
        .fullScreenCover(isPresented: $showingNetworkEntry) { DuelNetworkEntryView() }
    }

    private func stage(visibleRegion: CGRect? = nil) -> some View {
        ZStack {
            Color(red: 0.07, green: 0.075, blue: 0.09)
            if hasShowroom && match == nil && !showingNetworkEntry {
                DuelLobbyPreview(hero: hero, visibleRegion: visibleRegion)
                    .accessibilityIdentifier("duel.lobby.preview")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("duel.lobby.showroom")
    }

    private func landscapeLobby(width: CGFloat) -> some View {
        let sideWidth = min(218, max(164, width * 0.235))
        return VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("裂隙对决").font(.title2.weight(.semibold)).tracking(3)
                    .frame(width: sideWidth, alignment: .leading)
                Spacer()
                Text("武者大厅").font(.caption.weight(.semibold)).tracking(2)
                    .foregroundStyle(bronze)
                    .frame(width: sideWidth, alignment: .trailing)
            }
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionTitle("选择武者")
                        ForEach(choices, id: \.self) { choice in heroButton(choice) }
                    }
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("duel.lobby.roster")
                .frame(width: sideWidth)
                // The empty center deliberately remains hit-test transparent.
                Color.clear
                    .frame(minWidth: 32, maxHeight: .infinity)
                    .background(lobbyFrame(.center))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        difficultyPicker
                        networkEntry
                        Divider().overlay(bronze.opacity(0.35))
                        skillHelp
                    }
                    .padding(12)
                    .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 8))
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("duel.lobby.actions")
                .frame(width: sideWidth)
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 12) {
                selectedIdentity.frame(maxWidth: .infinity, alignment: .leading)
                practiceButton
                tutorialButton
                startButton
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .top) { Rectangle().fill(bronze.opacity(0.6)).frame(height: 1) }
            .background(lobbyFrame(.rail))
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 10)
    }

    private func lobbyFrame(_ region: DuelLobbyLayoutRegion) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(key: DuelLobbyLayoutFrames.self,
                                   value: [region: geometry.frame(in: .named("duel.lobby.layout"))])
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var selectedIdentity: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hero.name).font(.headline).foregroundStyle(bronze)
                .accessibilityIdentifier("duel.lobby.selectedHero")
            Text(detail(hero)).font(.caption).foregroundStyle(.white.opacity(0.8))
            Text("拖动旋转 · 双指缩放").font(.caption2).foregroundStyle(.white.opacity(0.65))
                .accessibilityIdentifier("duel.lobby.gestureHelp")
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).tracking(2).foregroundStyle(bronze)
    }

    private func heroButton(_ choice: DuelGame.Hero) -> some View {
        let selected = hero == choice
        return Button { hero = choice } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1).fill(selected ? bronze : .white.opacity(0.25))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(choice.name).font(.headline)
                    Text(detail(choice)).font(.caption).foregroundStyle(.white.opacity(0.78))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(bronze)
                        .accessibilityHidden(true)
                }
            }
            .padding(10)
            .frame(minHeight: 52)
            .background(selected ? bronze.opacity(0.20) : .black.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? bronze : .white.opacity(0.17), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "已选择" : "未选择")
        .accessibilityIdentifier("duel.hero.\(choice.rawValue)")
    }

    private var difficultyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("电脑难度")
            Picker("电脑难度", selection: $difficulty) {
                Text("初练").tag(DuelGame.Difficulty.learning)
                Text("进阶").tag(DuelGame.Difficulty.challenging)
            }
            .pickerStyle(.segmented)
            .environment(\.colorScheme, .dark)
        }
    }

    private var startButton: some View {
        Button { start(.versus) } label: {
            VStack(spacing: 2) {
                Text("开始对决").font(.headline.bold())
                Text("三局两胜").font(.caption2)
            }
            .frame(minWidth: 104, minHeight: 44)
            .padding(.horizontal, 10)
            .foregroundStyle(Color(red: 0.12, green: 0.09, blue: 0.05))
            .background(bronze, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("duel.start")
    }
    private var practiceButton: some View {
        Button("练习场") { start(.practice) }
            .buttonStyle(.bordered).controlSize(.large)
            .accessibilityIdentifier("duel.practice")
    }
    private var tutorialButton: some View {
        Button("操作教学") { start(.tutorial) }
            .buttonStyle(.bordered).controlSize(.large)
            .accessibilityIdentifier("duel.tutorial")
    }
    private var networkEntry: some View {
        Button {
            guard match == nil, !showingNetworkEntry else { return }
            showingNetworkEntry = true
        } label: {
            Label("双人选角 · 联机测试", systemImage: "person.2.fill")
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("duel.network.enter")
    }

    private var skillHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(usesOriginalWeapons ?
                 "左侧摇杆移动；右侧武器与踢击配合方向出招。收招后才恢复自动防御。" :
                 "普攻命中后继续点击，可衔接三段连击。")
                .foregroundStyle(.white.opacity(0.78))
            Text(usesOriginalWeapons ?
                 (hero == .ember ? "武士刀：上斩、下斩、回身斩及长按重斩。" :
                                  "双锤：上击、低扫、回身攻击及长按重击。") : hero.skillHelp)
                .foregroundStyle(.white.opacity(0.68))
                .accessibilityIdentifier("duel.skillHelp")
            if hero == .liu && !usesOriginalWeapons {
                Text("刘泉纬 · 擒拿震地：100 能量，近身抓取并击退。")
                    .accessibilityIdentifier("duel.ultimateHelp")
            }
        }
        .font(.caption)
    }

    private var stackedActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("裂隙对决").font(.title2.bold())
            sectionTitle("选择武者")
            ForEach(choices, id: \.self) { choice in heroButton(choice) }
            difficultyPicker
            startButton
            practiceButton
            tutorialButton
            networkEntry
            skillHelp
        }
        .padding(16)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
    private func start(_ mode: DuelGame.Mode) {
        guard match == nil, !showingNetworkEntry else { return }
        match = DuelSetup(hero: hero, difficulty: difficulty, mode: mode, originalWeapons: usesOriginalWeapons)
    }
}

// Internal so native integration tests can observe the real preference values
// without adding accessibility containers or replacing the production layout.
enum DuelLobbyLayoutRegion: Hashable, Sendable { case stage, center, rail }

struct DuelLobbyLayoutFrames: PreferenceKey {
    static let defaultValue: [DuelLobbyLayoutRegion: CGRect] = [:]
    static func reduce(value: inout [DuelLobbyLayoutRegion: CGRect],
                       nextValue: () -> [DuelLobbyLayoutRegion: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
