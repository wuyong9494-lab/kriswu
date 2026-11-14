import SwiftUI
import UIKit

/// Owns routing, not a game, renderer, audio lease or simulation clock.
/// UIKit only supplies this scene when the selected route supports external content.
@MainActor
final class DuelTelevisionRouter {
    static let shared = DuelTelevisionRouter()
    private weak var host: DuelTelevisionHostView?
    private weak var display: DuelTelevisionViewController?

    func mount(_ candidate: DuelTelevisionHostView) {
        guard !candidate.closed, candidate.window != nil else { return }
        if host !== candidate {
            // A new match may mount before the old SwiftUI tree dismantles.
            host?.shutdown()
            host = candidate
        }
        route()
    }
    func unmount(_ candidate: DuelTelevisionHostView) {
        guard host === candidate else { return }
        host = nil
        display?.show(session: nil)
    }
    func connect(_ candidate: DuelTelevisionViewController) {
        // Keep one external presentation. Never create a second world for another TV.
        guard display == nil || display === candidate else { return }
        display = candidate
        route()
    }
    func disconnect(_ candidate: DuelTelevisionViewController) {
        guard display === candidate else { return }
        display = nil
        candidate.show(session: nil)
        route()
    }
    func route() {
        guard let host, !host.closed, host.window != nil else { return }
        let target = display?.surface
        let external = target?.window != nil && (target?.bounds.width ?? 0) > 0 && (target?.bounds.height ?? 0) > 0
        let destination = external ? target! : host
        if host.world.relocateDisplay(to: destination) {
            host.message.isHidden = !external
            display?.show(session: external ? host.session : nil)
        }
    }
}

/// This stable phone-side owner retains the one renderer when it is on the TV.
/// Controls remain in the original SwiftUI hierarchy with the same session.
@MainActor
final class DuelTelevisionHostView: UIView {
    let world: DuelWorldView
    let session: DuelSession
    let message = UILabel()
    private let router: DuelTelevisionRouter
    private(set) var closed = false
    init(world: DuelWorldView, session: DuelSession, router: DuelTelevisionRouter = .shared) {
        self.world = world; self.session = session; self.router = router
        super.init(frame: .zero)
        backgroundColor = .black
        message.text = "游戏画面已显示在电视\n在此操作，或使用已连接的手柄"
        message.numberOfLines = 0; message.textAlignment = .center
        message.textColor = .lightGray; message.isHidden = true
        message.accessibilityIdentifier = "duel.television.phoneControls"
        addSubview(message)
        world.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(world)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        message.frame = bounds.insetBy(dx: 48, dy: 48)
        if world.superview === self { world.frame = bounds }
        scheduleRouting()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            // A disappearing phone owner must not leave a running fight on TV.
            // SwiftUI dismantle will close it; pause now even if it is delayed.
            if !closed { session.pause() }
        } else { scheduleRouting() }
    }
    private func scheduleRouting() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.closed, self.window != nil else { return }
            self.router.mount(self)
        }
    }
    func shutdown() {
        guard !closed else { return }
        closed = true
        router.unmount(self)
        world.shutdown()
        world.removeFromSuperview()
    }
}

@MainActor
final class DuelTelevisionSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var controller: DuelTelevisionViewController?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard session.role == .windowExternalDisplayNonInteractive,
              let scene = scene as? UIWindowScene else { return }
        let controller = DuelTelevisionViewController()
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        self.controller = controller; self.window = window
        // Never steal the phone's key window (keyboard/Hitbox remains there).
        window.isHidden = false
    }
    func sceneDidDisconnect(_ scene: UIScene) {
        if let controller { DuelTelevisionRouter.shared.disconnect(controller) }
        window?.isHidden = true
        window = nil; controller = nil
    }
    func sceneWillResignActive(_ scene: UIScene) {
        if let controller { DuelTelevisionRouter.shared.disconnect(controller) }
    }
    func sceneDidBecomeActive(_ scene: UIScene) {
        if let controller { DuelTelevisionRouter.shared.connect(controller) }
    }
}

@MainActor
final class DuelTelevisionViewController: UIViewController {
    let surface = UIView()
    private let router: DuelTelevisionRouter
    init(router: DuelTelevisionRouter = .shared) {
        self.router = router
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private let idle = UILabel()
    private var hud: UIHostingController<DuelTelevisionHUD>?
    private weak var presentedSession: DuelSession?
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.addSubview(surface)
        idle.text = "裂隙对决\n请在手机上进入对局"; idle.numberOfLines = 0
        idle.textColor = .white; idle.textAlignment = .center
        view.addSubview(idle)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        router.connect(self)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Full external viewport, no stretching of a captured phone image.
        surface.frame = view.bounds
        idle.frame = view.bounds
        hud?.view.frame = view.bounds.inset(by: view.safeAreaInsets)
        DispatchQueue.main.async { [weak self] in
            guard self?.view.window != nil else { return }
            self?.router.route()
        }
    }
    func show(session: DuelSession?) {
        loadViewIfNeeded()
        guard presentedSession !== session || (session == nil && hud != nil) else { return }
        hud?.willMove(toParent: nil); hud?.view.removeFromSuperview(); hud?.removeFromParent(); hud = nil
        presentedSession = session
        idle.isHidden = session != nil
        guard let session else { return }
        let hud = UIHostingController(rootView: DuelTelevisionHUD(session: session))
        hud.view.backgroundColor = .clear; hud.view.isUserInteractionEnabled = false
        addChild(hud); view.addSubview(hud.view); hud.didMove(toParent: self)
        self.hud = hud
        view.setNeedsLayout()
    }
}

/// No controls, music, onAppear reset or simulation side effects on this screen.
private struct DuelTelevisionHUD: View {
    @ObservedObject var session: DuelSession
    var body: some View {
        VStack {
            HStack(alignment: .top, spacing: 36) {
                fighter(0)
                VStack {
                    Text(session.setup.mode == .versus ? "\((session.game.remainingTicks + 59) / 60)" : "练习")
                    Text("\(session.game.wins[0]) : \(session.game.wins[1])")
                }.font(.title.monospacedDigit().bold())
                fighter(1)
            }
            Spacer()
            if let error = session.loadError { Text(error) }
            else if session.paused { Text("已暂停 · 请在手机上操作") }
            else if case .matchOver(let winner) = session.game.phase {
                Text(winner == session.localFighterIndex ? "对局胜利" : "对局结束")
            } else if case .roundBreak(let winner, _) = session.game.phase {
                Text(winner == nil ? "平局 · 准备重赛" : winner == session.localFighterIndex ? "回合胜利" : "回合失利")
            }
        }
        .font(.title2.bold()).foregroundStyle(.white)
        .padding(32).background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom).frame(height: 150)
        }.allowsHitTesting(false)
    }
    private func fighter(_ index: Int) -> some View {
        let fighter = session.game.fighters[index]
        return VStack(alignment: index == 0 ? .leading : .trailing) {
            Text(fighter.hero.name)
            ProgressView(value: Double(fighter.health), total: Double(session.game.weaponFight?.maximumHealth(index) ?? 1000))
                .tint(index == 0 ? .orange : .cyan)
            Text(session.game.weaponFight?.panguState(index).map {
                "生命 \(fighter.health) · 光能 \($0.light)/\($0.rules.light.maximum) · 连击 \($0.combo)"
            } ?? "生命 \(fighter.health) · 能量 \(fighter.energy)").font(.headline.monospacedDigit())
            if let state = session.game.weaponFight?.panguState(index) {
                DuelPanguHUD(state: state,
                    isEscapingOrdinaryThrow: session.game.weaponFight?.ordinaryThrow(index)?.stage == .immune,
                    prominent: true)
            }
            if let fight = session.game.weaponFight {
                DuelPanguControlHUD(controls: fight.panguPresentation.controls.filter { $0.target == index },
                                    prominent: true)
            }
        }.frame(maxWidth: .infinity)
    }
}
