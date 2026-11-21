import SceneKit
import SwiftUI

/// 裂隙对决大厅：选英雄、选对手、选模式，3D 展台实时展示所选英雄
struct RiftHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player: RiftHeroID = .sunDeng
    @State private var opponent: RiftHeroID = .wuYong
    @State private var difficulty: RiftDifficulty = .normal
    @State private var match: RiftSession.Config?
    @State private var pickingOpponent = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.04, blue: 0.12), Color(red: 0.2, green: 0.08, blue: 0.22)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            HStack(spacing: 0) {
                showroom
                    .frame(maxWidth: .infinity)
                panel
                    .frame(width: 360)
                    .padding(.trailing, 16)
            }
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Label("返回", systemImage: "chevron.left").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6).background(.white.opacity(0.12), in: Capsule())
                    }
                    .accessibilityIdentifier("rift.home.close")
                    Text("裂隙对决").font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                    Spacer()
                }
                Spacer()
            }
            .padding(12)
        }
        .fullScreenCover(item: $match) { config in
            RiftMatchView(config: config, onExit: { match = nil }, onRematch: {
                let again = RiftSession.Config(player: config.player, opponent: config.opponent, mode: config.mode)
                match = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { match = again }
            })
        }
        .onAppear(perform: autoStartForTesting)
        .accessibilityIdentifier("rift.home")
    }

    private var showroom: some View {
        let hero = pickingOpponent ? opponent : player
        let spec = RiftRoster.spec(hero)
        return ZStack(alignment: .bottomLeading) {
            RiftShowroom(hero: hero)
                .id(hero)
            VStack(alignment: .leading, spacing: 4) {
                Text(spec.title).font(.system(size: 14, weight: .bold)).foregroundStyle(RiftSession.heroColor(hero))
                Text(spec.name).font(.system(size: 40, weight: .black)).foregroundStyle(.white)
                Text("\(spec.weapon) · 变身「\(spec.transformName)」 · 终极技「\(spec.ultimateName)」")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                statBars(spec)
            }
            .padding(.leading, 24).padding(.bottom, 18)
        }
    }

    private func statBars(_ spec: RiftHeroSpec) -> some View {
        let power = Double(spec.move(.heavy)!.damage) / 110
        let speed = 1 - Double(spec.move(.light1)!.startup - 4) / 8
        let health = Double(spec.maxHealth - 1100) / 400
        let reach = (spec.move(.light3)!.reachEnd - 1.2) / 1.0
        return HStack(spacing: 14) {
            stat("力量", power); stat("速度", speed); stat("体魄", health); stat("攻击距离", reach)
        }
        .padding(.top, 6)
    }

    private func stat(_ name: String, _ v: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.7))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15)).frame(width: 60, height: 5)
                Capsule().fill(.orange).frame(width: 60 * max(0.1, min(1, v)), height: 5)
            }
        }
    }

    private var panel: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 40)
            Picker("", selection: $pickingOpponent) {
                Text("我的英雄").tag(false)
                Text("对手").tag(true)
            }
            .pickerStyle(.segmented)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(RiftHeroID.allCases) { id in
                    heroCard(id)
                }
            }
            HStack {
                Text("难度").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                Picker("难度", selection: $difficulty) {
                    ForEach(RiftDifficulty.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            HStack(spacing: 10) {
                RiftMenuButton(title: "开始对战", id: "rift.start") {
                    match = .init(player: player, opponent: opponent, mode: .versusAI(difficulty))
                }
                RiftMenuButton(title: "训练场", id: "rift.training", style: .secondary) {
                    match = .init(player: player, opponent: opponent, mode: .training)
                }
            }
            RiftMenuButton(title: "观看电脑对战", id: "rift.demo", style: .secondary) {
                match = .init(player: player, opponent: opponent, mode: .demo)
            }
            Spacer(minLength: 8)
        }
    }

    private func heroCard(_ id: RiftHeroID) -> some View {
        let spec = RiftRoster.spec(id)
        let selected = (pickingOpponent ? opponent : player) == id
        let color = RiftSession.heroColor(id)
        return Button {
            if pickingOpponent { opponent = id } else { player = id }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.name).font(.system(size: 18, weight: .black)).foregroundStyle(.white)
                Text("\(spec.title) · \(spec.weapon)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(LinearGradient(colors: [color.opacity(selected ? 0.55 : 0.18), .black.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? color : .white.opacity(0.15), lineWidth: selected ? 2 : 1))
        }
        .accessibilityIdentifier("rift.hero.\(id.rawValue)")
    }

    /// 自动化验收：启动参数 -rift-autostart <英雄> 直接进对战
    private func autoStartForTesting() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-rift-autostart"), args.indices.contains(i + 1), let hero = RiftHeroID(rawValue: args[i + 1]) {
            player = hero
            let mode: RiftSession.Mode = args.contains("-rift-demo") ? .demo
                : (args.contains("-rift-training") ? .training : .versusAI(.easy))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                match = .init(player: hero, opponent: hero == .wuYong ? .liuQuanwei : .wuYong, mode: mode)
            }
        }
    }
}

/// 3D 展台：选中的英雄站在台上做待机动作，缓慢旋转
struct RiftShowroom: UIViewRepresentable {
    let hero: RiftHeroID

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling2X
        v.preferredFramesPerSecond = 60
        v.rendersContinuously = true
        let scene = SCNScene()
        v.scene = scene
        let rig = RiftRig(hero: hero)
        rig.installPersonalHead()
        scene.rootNode.addChildNode(rig.root)
        let disc = SCNCylinder(radius: 0.9, height: 0.08)
        let m = SCNMaterial(); m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(white: 0.15, alpha: 1); m.metalness.contents = 0.6; m.roughness.contents = 0.3
        m.emission.contents = UIColor(cgColor: UIColor(RiftSession.heroColor(hero)).withAlphaComponent(0.15).cgColor)
        disc.materials = [m]
        let dn = SCNNode(geometry: disc); dn.position = SCNVector3(0, -0.04, 0); scene.rootNode.addChildNode(dn)
        let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera?.fieldOfView = 32
        cam.position = SCNVector3(0, 1.3, 4.6); cam.look(at: SCNVector3(0, 1.0, 0))
        scene.rootNode.addChildNode(cam)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional; key.light?.intensity = 1300
        key.eulerAngles = SCNVector3(-0.6, 0.6, 0); scene.rootNode.addChildNode(key)
        let rim = SCNNode(); rim.light = SCNLight(); rim.light?.type = .directional; rim.light?.intensity = 900
        rim.light?.color = UIColor(RiftSession.heroColor(hero))
        rim.eulerAngles = SCNVector3(-0.2, .pi - 0.5, 0); scene.rootNode.addChildNode(rim)
        let amb = SCNNode(); amb.light = SCNLight(); amb.light?.type = .ambient; amb.light?.intensity = 300
        scene.rootNode.addChildNode(amb)
        context.coordinator.rig = rig
        context.coordinator.start(view: v)
        v.accessibilityIdentifier = "rift.showroom"
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) { coordinator.stop() }

    @MainActor
    final class Coordinator: NSObject {
        var rig: RiftRig?
        private var link: CADisplayLink?
        private let t0 = CACurrentMediaTime()

        func start(view: SCNView) {
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        func stop() { link?.invalidate(); link = nil }

        @objc private func tick() {
            guard let rig else { return }
            let t = CACurrentMediaTime() - t0
            rig.apply(RiftAnimator.stance(rig.hero, t: t))
            rig.root.eulerAngles.y = Float(0.5 + sin(t * 0.4) * 0.6)
        }
    }
}
