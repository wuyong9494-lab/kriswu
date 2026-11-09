import SwiftUI
import UIKit
import AVFoundation

struct DuelHomeView: View {
    @State private var hero = DuelGame.Hero.liu
    @State private var difficulty = DuelGame.Difficulty.learning
    @State private var match: DuelSetup?
    private var usesOriginalWeapons: Bool {
        !ProcessInfo.processInfo.arguments.contains("-duel-legacy-controls") && DuelWeaponAssets.catalogURL() != nil
    }
    private var choices: [DuelGame.Hero] { usesOriginalWeapons ? [.ember, .liu] : DuelGame.Hero.allCases }
    private func weaponTitle(_ hero: DuelGame.Hero) -> String { hero == .ember ? "先锋 · 武士刀" : "军团 · 双锤" }
    private var hasShowroom: Bool {
        DuelStageAsset.bundledURL(for: .autumnLobby) != nil &&
            (DuelCharacterAsset.bundledURL(for: hero) != nil || usesOriginalWeapons)
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height
            ZStack {
                LinearGradient(colors: [Color(red: 0.055, green: 0.075, blue: 0.13),
                                        Color(red: 0.13, green: 0.14, blue: 0.23)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                if wide {
                    HStack(spacing: 18) {
                        showroom
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        ScrollView { lobbyActions }
                            .frame(width: min(310, geometry.size.width * 0.36))
                    }
                    .padding(20)
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            showroom.frame(height: min(geometry.size.height * 0.47, 380))
                            lobbyActions
                        }
                        .padding(16)
                    }
                }
            }
            .foregroundStyle(.white)
        }
        .navigationBarTitleDisplayMode(.inline)
        .modifier(ArenaLandscape())
        .fullScreenCover(item: $match) { DuelMatchView(setup: $0) }
    }

    private var showroom: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(red: 0.10, green: 0.13, blue: 0.21))
            if hasShowroom && match == nil {
                DuelLobbyPreview(hero: hero)
                    .accessibilityIdentifier("duel.lobby.preview")
                    .clipShape(RoundedRectangle(cornerRadius: 22))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("裂隙对决").font(.title.bold())
                Text(hero.name + " · " + (usesOriginalWeapons ? weaponTitle(hero) : hero.style))
                    .font(.subheadline).foregroundStyle(.white.opacity(0.82))
                Text("拖动旋转 · 双指缩放")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
                    .accessibilityIdentifier("duel.lobby.gestureHelp")
            }
            .padding(18)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
            .padding(14)
        }
        .accessibilityIdentifier("duel.lobby.showroom")
    }

    private var lobbyActions: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("选择武者").font(.title3.bold())
            HStack(spacing: 10) {
                ForEach(choices, id: \.self) { choice in
                    Button { hero = choice } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(choice.name).font(.headline)
                            Text(usesOriginalWeapons ? weaponTitle(choice) : choice.style)
                                .font(.caption).lineLimit(2)
                            Text(hero == choice ? "已选择" : "点击切换")
                                .font(.caption2).foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                        .padding(10)
                        .background(hero == choice ? Color.orange.opacity(0.35) : Color.white.opacity(0.09),
                                    in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13)
                            .stroke(hero == choice ? Color.orange : Color.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("duel.hero.\(choice.rawValue)")
                }
            }
            Text("电脑难度").font(.subheadline.bold())
            Picker("电脑难度", selection: $difficulty) {
                Text("初练").tag(DuelGame.Difficulty.learning)
                Text("进阶").tag(DuelGame.Difficulty.challenging)
            }
            .pickerStyle(.segmented)
            Button { start(.versus) } label: {
                Text("开始对决 · 三局两胜")
                    .font(.headline.bold()).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .accessibilityIdentifier("duel.start")
            HStack {
                Button("练习场") { start(.practice) }
                    .accessibilityIdentifier("duel.practice")
                Spacer()
                Button("操作教学") { start(.tutorial) }
                    .accessibilityIdentifier("duel.tutorial")
            }
            .buttonStyle(.bordered)
            Text(usesOriginalWeapons ?
                 "左侧摇杆移动；右侧武器与踢击配合方向出招。收招后才恢复自动防御。" :
                 "普攻命中后继续点击，可衔接三段连击。")
                .font(.caption).foregroundStyle(.white.opacity(0.75))
            Text(usesOriginalWeapons ?
                 (hero == .ember ? "武士刀：上斩、下斩、回身斩及长按重斩。" :
                                  "双锤：上击、低扫、回身攻击及长按重击。") :
                 hero.skillHelp)
                .font(.caption).foregroundStyle(.white.opacity(0.7))
                .accessibilityIdentifier("duel.skillHelp")
            if hero == .liu && !usesOriginalWeapons {
                Text("刘泉纬 · 擒拿震地：100 能量，近身抓取并击退。")
                    .font(.caption).accessibilityIdentifier("duel.ultimateHelp")
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 20))
    }
    private func start(_ mode: DuelGame.Mode) { match = DuelSetup(hero: hero, difficulty: difficulty, mode: mode, originalWeapons: usesOriginalWeapons) }
}

struct DuelSetup: Identifiable {
    let id = UUID()
    let hero: DuelGame.Hero
    let difficulty: DuelGame.Difficulty
    let mode: DuelGame.Mode
    let originalWeapons: Bool
    init(hero: DuelGame.Hero, difficulty: DuelGame.Difficulty, mode: DuelGame.Mode, originalWeapons: Bool = false) {
        self.hero = hero; self.difficulty = difficulty; self.mode = mode; self.originalWeapons = originalWeapons
    }
}

/// Shared input mailbox and low-frequency HUD. SceneKit owns its own view lifetime.
@MainActor
final class DuelSession: ObservableObject {
    let setup: DuelSetup
    private(set) var game: DuelGame
    private(set) var held = Set<String>()
    private var taps: DuelGame.Buttons = []
    private var weaponInput = DuelWeaponInput()
    private(set) var weaponAssets: DuelWeaponAssets?
    @Published private(set) var loadError: String?
    @Published private(set) var paused = false
    @Published var showBoxes = false
    @Published private(set) var feedback = "保持距离，观察出手"
    @Published private(set) var tutorialStep = 0
    @Published private(set) var report = ""
    var renderPause: ((Bool) -> Void)?
    var inputReset: (() -> Void)?
    var didSimulateStep: ((DuelGame, Int) -> Void)?
    var didReset: (() -> Void)?
    private var feedbackUntil = 75
    private var serial = 0
    private var ended = false
    private(set) var animationTick = 0
    private(set) var characterStatus = ""
    private var practicedJump = false
    private var practicedSkills = Set<DuelGame.Move>()
    private let interruptions = DuelInterruptionObserver()
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    init(_ setup: DuelSetup) {
        self.setup = setup
        var assets: DuelWeaponAssets?
        var failure: String?
        if setup.originalWeapons {
            do { assets = try DuelWeaponAssets() }
            catch { failure = "人物资源无法载入，请返回后重试。" }
        }
        weaponAssets = assets
        game = DuelGame(hero: setup.hero, difficulty: setup.difficulty, mode: setup.mode,
                        opponentHero: setup.hero == .liu ? .ember : setup.hero == .ember ? .liu : nil,
                        weaponCatalog: assets?.catalog)
        if setup.originalWeapons && game.weaponFight == nil { failure = "人物资源无法载入，请返回后重试。" }
        loadError = failure; paused = failure != nil
        interruptions.token = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.pause() }
            }
    }
    var tutorial: String {
        if setup.originalWeapons {
            return ["推动左侧摇杆靠近对手", "点击右侧武器按钮，观察刀或锤的攻击距离", "向上推动摇杆跳跃，站定时自动防御", "配合方向攻击，并尝试踢击与长按武器重击", "已完成：继续练习，或返回挑战电脑"][min(4, tutorialStep)]
        }
        return ["按住左侧方向，靠近对手", "方向与普攻可同时按：命中后再点普攻", "先点击跳跃，落地后再按住防御", "分别使出两种技能，注意能量消耗", "已完成：继续练习，或返回挑战电脑"][min(4, tutorialStep)]
    }
    var grappleStatus: String {
        guard let hold = game.grapple else { return "" }
        switch hold.stage {
        case .takedown: return "擒拿 · 抓肩摔倒"
        case .hold: return String(format: "锁臂压制 · %.1f 秒", Double(hold.holdRemaining) / 60)
        case .release: return "震地击退"
        }
    }
    var ultimateReady: Bool { game.fighters[0].energy == 100 && game.grapple == nil }
    func input(_ name: String, down: Bool) {
        guard !paused else { return }
        if down {
            guard held.insert(name).inserted else { return }
            switch name {
            case "jump": taps.insert(.jump)
            case "light": taps.insert(.light)
            case "heavy": taps.insert(.heavy)
            case "skill1": taps.insert(.skill1)
            case "skill2": taps.insert(.skill2)
            case "ultimate": taps.insert(.ultimate)
            default: break
            }
        } else { held.remove(name) }
    }
    func weaponDirection(x: Int, y: Int) { guard !paused else { return }; weaponInput.direction(x: x, y: y) }
    func weaponAction(_ action: DuelWeaponInput.Action, down: Bool) { guard !paused else { return }; weaponInput.action(action, down: down) }
    func cancelWeaponAction(_ action: DuelWeaponInput.Action) { weaponInput.cancel(action: action) }
    func cancelWeaponInput() { weaponInput.cancelAll(); game.cancelBufferedInputs() }
    func clearInput() { held.removeAll(); taps = []; weaponInput.cancelAll(); game.cancelBufferedInputs(); inputReset?() }
    func pause() { clearInput(); paused = true; renderPause?(true) }
    func resume() { guard !ended, loadError == nil else { return }; clearInput(); paused = false; renderPause?(false) }
    func restart() {
        guard !ended else { return }
        clearInput(); game = DuelGame(hero: setup.hero, difficulty: setup.difficulty, mode: setup.mode,
                        opponentHero: setup.hero == .liu ? .ember : setup.hero == .ember ? .liu : nil,
                        weaponCatalog: weaponAssets?.catalog)
        feedback = "保持距离，观察出手"; tutorialStep = 0; serial = 0; animationTick = 0; feedbackUntil = 75
        practicedJump = false; practicedSkills.removeAll(); didReset?(); resume()
        didSimulateStep?(game, 0); objectWillChange.send()
    }
    func advance() {
        guard !paused else { return }
        if case .matchOver = game.phase { return }
        let input = setup.originalWeapons ? weaponInput.consume(facing: game.fighters[0].facing,
                    airborne: game.weaponFight?.isAirborne(0) ?? false) :
            DuelGame.Input(move: (held.contains("right") ? 1 : 0) - (held.contains("left") ? 1 : 0), guardHeld: held.contains("guard"), taps: taps)
        let move = input.move
        let frozen = game.hitStop > 0 && game.grapple == nil
        taps = []; game.step(input); serial += 1
        if !frozen { animationTick += 1 }
        didSimulateStep?(game, animationTick)
        if setup.mode == .tutorial {
            if tutorialStep == 0 && move != 0 { tutorialStep = 1 }
            if tutorialStep == 1 && game.landedHits[0] > 0 { tutorialStep = 2 }
            if tutorialStep == 2 {
                if game.events.contains(.jumped(player: 0)) { practicedJump = true }
                if practicedJump && game.fighters[0].guarding { tutorialStep = 3 }
            }
            if tutorialStep == 3 && setup.originalWeapons, input.weaponCommand == .kick || input.weaponCommand == .shadow { tutorialStep = 4 }
            if tutorialStep == 3, let attack = game.fighters[0].attack,
               attack.move == .skill1 || attack.move == .skill2 {
                practicedSkills.insert(attack.move)
                if practicedSkills.count == 2 { tutorialStep = 4 }
            }
        }
        for event in game.events {
            switch event {
            case .hit(let attacker, let damage): feedback = attacker == 0 ? "命中 −\(damage)" : "受到攻击 −\(damage)"
            case .blocked: feedback = "防御成功"
            case .guardBreak: feedback = "防御被击破"
            case .whiff(let attacker): if attacker == 0 { feedback = "未命中 · 留意距离与前摇" }
            case .jumped: break
            case .grappleStarted: feedback = "擒拿成功 · 抓肩摔倒"
            case .grappleSlam: feedback = "锁臂压制 · 3 秒"; impact.impactOccurred(intensity: 0.6)
            case .grappleReleased: feedback = "震地击退"; impact.impactOccurred(intensity: 0.9)
            case .grappleClash: feedback = "双方抓取相抵 · 拉开距离"
            case .roundEnded(let winner): feedback = winner == nil ? "平局 · 重赛" : winner == 0 ? "拿下一局" : "对手拿下一局"
            }
            feedbackUntil = game.frame + 75
        }
        if game.frame > feedbackUntil && !feedback.isEmpty { feedback = "" }
        if serial % 6 == 0 || !game.events.isEmpty { objectWillChange.send() }
    }
    func metrics(_ value: String) { report = value }
    func characterLoaded(_ status: String) { characterStatus = status }
    func characterFailed() { loadError = "人物资源无法载入，请返回后重试。"; pause() }
    func shutdown() {
        guard !ended else { return }
        ended = true
        pause(); renderPause = nil; inputReset = nil; didSimulateStep = nil; didReset = nil
        weaponAssets?.releaseCharacters()
        // UIKit can retain the closed SceneKit view and its session until a
        // later event. Release the resource owner at teardown, not at deinit.
        weaponAssets = nil
    }
}

// Own the non-Sendable observer in a nonisolated object, so its destruction does
// not read actor-isolated session state under Swift's complete concurrency checks.
private final class DuelInterruptionObserver {
    var token: NSObjectProtocol?
    deinit { if let token { NotificationCenter.default.removeObserver(token) } }
}

struct DuelMatchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session: DuelSession
    init(setup: DuelSetup) { _session = StateObject(wrappedValue: DuelSession(setup)) }
    var body: some View {
        ZStack {
            DuelWorld(session: session).ignoresSafeArea()
            if session.setup.originalWeapons {
                DuelWeaponControls(session: session).ignoresSafeArea(edges: .bottom)
            } else {
                DuelControls(session: session, ultimateReady: session.ultimateReady).ignoresSafeArea(edges: .bottom)
            }
            VStack {
                hud
                if session.setup.mode == .tutorial {
                    Text(session.tutorial).font(.caption.bold()).padding(8).background(.black.opacity(0.65), in: Capsule())
                }
                Text(session.feedback).font(.headline.bold()).foregroundStyle(.yellow).frame(height: 24)
                Text(session.grappleStatus).font(.caption.monospacedDigit().bold()).frame(height: 20)
                    .accessibilityIdentifier("duel.grapple")
                if session.setup.mode != .versus {
                    Text("累计命中 \(session.game.landedHits[0]) 次 · 伤害 \(session.game.damageDealt[0])")
                        .font(.caption.monospacedDigit()).accessibilityIdentifier("duel.hits")
                }
                Spacer()
            }.padding(.horizontal, 22).padding(.top, 8).allowsHitTesting(false)
            VStack {
                HStack {
                    Button { session.pause() } label: { Image(systemName: "pause.fill").padding(12) }
                        .accessibilityLabel("暂停").accessibilityIdentifier("duel.pause")
                    Spacer()
                    Button { session.showBoxes.toggle() } label: { Image(systemName: "viewfinder").padding(12) }
                        .accessibilityLabel("显示判定框").accessibilityIdentifier("duel.boxes")
                }.padding(.horizontal, 12)
                Spacer()
            }
            if session.paused { pausePanel }
            if case .matchOver(let winner) = session.game.phase { resultPanel(winner) }
            if case .roundBreak(let winner, _) = session.game.phase {
                Text(winner == nil ? "平局 · 准备重赛" : winner == 0 ? "回合胜利" : "回合失利")
                    .font(.largeTitle.bold()).padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .allowsHitTesting(false)
            }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .modifier(ArenaLandscape())
        .onChange(of: scenePhase) { if $0 != .active { session.pause() } }
        .onDisappear { session.shutdown() }
    }
    private var hud: some View {
        HStack(alignment: .top, spacing: 18) {
            fighterHUD(0)
            VStack(spacing: 3) {
                Text(session.setup.mode == .versus ? "\((session.game.remainingTicks + 59) / 60)" : "练习")
                    .font(.title2.monospacedDigit().bold())
                Text("\(session.game.wins[0])  :  \(session.game.wins[1])").font(.caption.bold())
            }.frame(width: 65)
            fighterHUD(1)
        }.padding(.horizontal, 50)
    }
    private func fighterHUD(_ i: Int) -> some View {
        let f = session.game.fighters[i]
        return VStack(alignment: i == 0 ? .leading : .trailing, spacing: 3) {
            Text("\(f.hero.name) · \(session.game.weaponFight?.profiles[i].weaponTitle ?? (i == 0 ? "你" : "对手"))").font(.caption.bold())
                .accessibilityIdentifier("duel.name.\(i)")
            ProgressView(value: Double(f.health), total: 1000).tint(i == 0 ? .orange : .cyan)
            Text("生命 \(f.health) · 防御 \(f.guardMeter / 10) · 能量 \(f.energy)")
                .font(.system(size: 10, design: .monospaced))
                .accessibilityIdentifier("duel.stats.\(i)")
                .accessibilityValue("生命 \(f.health)，位置 \(f.x)，高度 \(f.y)")
        }.frame(maxWidth: .infinity)
    }
    private var pausePanel: some View {
        panel {
            Text("已暂停").font(.title2.bold())
            if let error = session.loadError { Text(error).accessibilityIdentifier("duel.resourceError") }
            else {
                Button("继续对决") { session.resume() }.accessibilityIdentifier("duel.resume")
                Button("重新挑战") { session.restart() }.accessibilityIdentifier("duel.restart")
            }
            Button("返回角色选择") { session.shutdown(); dismiss() }.accessibilityIdentifier("duel.exit")
            Text(session.characterStatus).font(.caption).accessibilityIdentifier("duel.characterStatus")
            Text(session.report).font(.caption2.monospaced()).foregroundStyle(.secondary)
        }
    }
    private func resultPanel(_ winner: Int) -> some View {
        panel {
            Text(winner == 0 ? "对决胜利" : "这次惜败").font(.largeTitle.bold())
            Text("\(session.game.wins[0]) : \(session.game.wins[1]) · 命中 \(session.game.landedHits[0]) 次")
            Button("重新挑战") { session.restart() }.accessibilityIdentifier("duel.rematch")
            Button("返回角色选择") { session.shutdown(); dismiss() }.accessibilityIdentifier("duel.resultExit")
        }
    }
    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 14, content: content).buttonStyle(.borderedProminent)
                .padding(24).frame(maxWidth: 440).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

struct DuelWeaponControls: UIViewRepresentable {
    let session: DuelSession
    func makeUIView(context: Context) -> DuelSourceControlsView {
        let view = DuelSourceControlsView(assetDirectory: session.weaponAssets?.directory)
        view.onDirection = { [weak session] x, y in session?.weaponDirection(x: x, y: y) }
        view.onAction = { [weak session] action, down in
            guard let command = DuelWeaponInput.Action(rawValue: action.rawValue) else { return }
            session?.weaponAction(command, down: down)
        }
        view.onActionCancelled = { [weak session] action in
            guard let command = DuelWeaponInput.Action(rawValue: action.rawValue) else { return }
            session?.cancelWeaponAction(command)
        }
        view.onInputCancelled = { [weak session] in session?.cancelWeaponInput() }
        session.inputReset = { [weak view] in view?.cancelAll(notify: false) }
        if !view.sourceArtAvailable { session.characterFailed() }
        updateUIView(view, context: context)
        return view
    }
    func updateUIView(_ view: DuelSourceControlsView, context: Context) {
        view.inputEnabled = !session.paused && session.loadError == nil
        view.opponentProne = session.game.fighters.count > 1 && session.game.fighters[1].knockdown > 0
        guard let fight = session.game.weaponFight else { view.inputEnabled = false; return }
        let profile = fight.profiles[0], fighter = session.game.fighters[0]
        for action in DuelSourceControlsView.Action.allCases {
            guard let command = DuelWeaponCommand(rawValue: action.rawValue) else { continue }
            let equipped = fight.supports(command, index: 0)
            let enough = command != .shadow || fighter.energy >= 100
            let label = action == .weapon ? profile.weaponTitle + "攻击" : nil
            let readiness = !equipped ? (profile.clip(command: command) == nil ? "未装备" : "暂不可用") : !enough ? "需要 100 能量" : fighter.stun > 0 ? "受击中" : fighter.attack != nil ? "收招中" : "可施放"
            view.setState(.init(enabled: equipped, ready: enough && fighter.attack == nil && fighter.stun == 0,
                                description: readiness,
                                accessibilityLabel: label), for: action)
        }
    }
    static func dismantleUIView(_ view: DuelSourceControlsView, coordinator: ()) { view.cancelAll() }
}

struct DuelControls: UIViewRepresentable {
    let session: DuelSession
    let ultimateReady: Bool
    func makeUIView(context: Context) -> DuelInputView { DuelInputView(session: session) }
    func updateUIView(_ uiView: DuelInputView, context: Context) { uiView.updateReadiness(ready: ultimateReady) }
    static func dismantleUIView(_ uiView: DuelInputView, coordinator: ()) { uiView.cancelAll() }
}

/// Each touch owns its original button; dragging away or cancellation releases it.
/// Independent fingers can hold a direction while another presses attack or guard.
@MainActor
final class DuelInputView: UIView {
    private weak var session: DuelSession?
    private var active: [ObjectIdentifier: String] = [:]
    private var buttons: [(String, UIButton)] = []
    init(session: DuelSession) {
        self.session = session; super.init(frame: .zero); isMultipleTouchEnabled = true
        var controls = [("left", "◀"), ("right", "▶"), ("guard", "防御"), ("jump", "跳跃"),
                        ("light", "普攻"), ("heavy", "重击"), ("skill1", session.setup.hero.skill1Name),
                        ("skill2", session.setup.hero.skill2Name)]
        if session.setup.hero == .liu { controls.append(("ultimate", "大招")) }
        for (name, title) in controls {
            let button = UIButton(type: .custom)
            button.setTitle(title, for: .normal); button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
            button.titleLabel?.adjustsFontSizeToFitWidth = true; button.titleLabel?.minimumScaleFactor = 0.7
            button.backgroundColor = UIColor(white: 0.12, alpha: 0.72)
            button.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor; button.layer.borderWidth = 1
            button.layer.cornerRadius = 24; button.isUserInteractionEnabled = false
            button.accessibilityIdentifier = "duel.control.\(name)"; button.accessibilityLabel = title
            button.isAccessibilityElement = true; addSubview(button); buttons.append((name, button))
        }
        session.inputReset = { [weak self] in self?.cancelAll(notify: false) }
        updateReadiness(ready: session.ultimateReady)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = bounds.width < 740 ? 48 : 58
        let inset = max(18, safeAreaInsets.left), floor = bounds.height - max(16, safeAreaInsets.bottom) - side
        let right = bounds.width - max(18, safeAreaInsets.right) - side
        let points: [CGPoint] = [CGPoint(x: inset, y: floor), CGPoint(x: inset + side + 10, y: floor),
            CGPoint(x: right - 2 * (side + 10), y: floor), CGPoint(x: inset + (side + 10) / 2, y: floor - side - 10),
            CGPoint(x: right - side - 10, y: floor), CGPoint(x: right, y: floor),
            CGPoint(x: right - side - 10, y: floor - side - 10), CGPoint(x: right, y: floor - side - 10),
            CGPoint(x: right - 2 * (side + 10), y: floor - side - 10)]
        for (index, pair) in buttons.enumerated() { pair.1.frame = CGRect(origin: points[index], size: CGSize(width: side, height: side)) }
    }
    func updateReadiness(ready: Bool) {
        guard let button = buttons.first(where: { $0.0 == "ultimate" })?.1 else { return }
        button.backgroundColor = ready ? UIColor.systemOrange.withAlphaComponent(0.85) : UIColor(white: 0.16, alpha: 0.78)
        button.accessibilityLabel = "擒拿震地大招"
        button.accessibilityValue = ready ? "可施放，消耗 100 能量" : "需要 100 能量"
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        buttons.contains { $0.1.frame.contains(point) }
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session?.paused == false else { return }
        for touch in touches {
            guard let button = buttons.first(where: { $0.1.frame.contains(touch.location(in: self)) }) else { continue }
            let wasHeld = active.values.contains(button.0)
            active[ObjectIdentifier(touch)] = button.0
            if !wasHeld { session?.input(button.0, down: true) }
            button.1.alpha = 0.6
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let name = active[ObjectIdentifier(touch)], let button = buttons.first(where: { $0.0 == name }),
               !button.1.frame.insetBy(dx: -12, dy: -12).contains(touch.location(in: self)) { release(touch) }
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { touches.forEach(release) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touches.forEach(release) }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { cancelAll() } }
    private func release(_ touch: UITouch) {
        guard let name = active.removeValue(forKey: ObjectIdentifier(touch)) else { return }
        if !active.values.contains(name) { session?.input(name, down: false); buttons.first(where: { $0.0 == name })?.1.alpha = 1 }
    }
    func cancelAll(notify: Bool = true) {
        let names = Set(active.values); active.removeAll()
        for pair in buttons { pair.1.alpha = 1 }
        if notify { for name in names { session?.input(name, down: false) } }
    }
}
