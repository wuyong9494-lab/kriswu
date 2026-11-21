import SwiftUI
import QuartzCore

/// 一局对战的运行时：固定 60 帧推进战斗核心，收集触屏输入，驱动电脑对手，
/// 把需要显示的东西（血量、怒气、连击、伤害数字）整理给界面。
@MainActor
final class RiftSession: ObservableObject {
    enum Mode: Equatable {
        case versusAI(RiftDifficulty)
        case training
        /// 两边都是电脑（自动演示 / 自动化验收）
        case demo
    }

    struct Config: Identifiable, Equatable {
        let id = UUID()
        var player: RiftHeroID
        var opponent: RiftHeroID
        var mode: Mode
    }

    struct HUD: Equatable {
        var health: [Double] = [1, 1]
        var healthValue: [Int] = [0, 0]
        var ghostHealth: [Double] = [1, 1]
        var rage: [Double] = [0, 0]
        var guardMeter: [Double] = [1, 1]
        var transformed: [Bool] = [false, false]
        var transformLeft: [Double] = [0, 0]
        var wins: [Int] = [0, 0]
        var combo: [Int] = [0, 0]
        var seconds = 99
        var round = 1
        var cooldown1 = 0.0
        var cooldown2 = 0.0
        var canTransform = false
        var canUltimate = false
        var counterReady = false
    }

    struct Banner: Equatable {
        var text: String
        var sub: String = ""
        var color: Color = .white
        var id = UUID()
    }

    struct Popup: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var world: SIMD3<Float>
        var color: Color
        var big: Bool
        var born: Date
    }

    let config: Config
    private(set) var fight: RiftFight
    private var ai: [RiftAI?]
    @Published private(set) var hud = HUD()
    @Published var banner: Banner?
    @Published private(set) var flash: Color?
    @Published private(set) var popups: [Popup] = []
    @Published private(set) var matchOver = false
    @Published private(set) var playerWon = false
    @Published var paused = false

    /// 触屏状态（按钮按下那一帧算一次“按”）
    var holdHorizontal: Int8 = 0
    var holdGuard = false
    private var pulses = RiftInput()
    private var accumulator: CFTimeInterval = 0
    private var lastTime: CFTimeInterval?
    private var ghost: [Double] = [1, 1]
    private var comboShown: [Int] = [0, 0]
    private var comboTimer: [Int] = [0, 0]
    private(set) var pendingEvents: [RiftEvent] = []
    /// 表现层（SceneKit）读取的事件队列
    var eventSink: (([RiftEvent], RiftFight) -> Void)?
    var projector: ((SIMD3<Float>) -> CGPoint?)?
    private var frameCounter = 0

    init(config: Config) {
        self.config = config
        let training = config.mode == .training
        fight = RiftFight(left: config.player, right: config.opponent, training: training)
        switch config.mode {
        case .versusAI(let d):
            ai = [nil, RiftAI(side: 1, difficulty: d, seed: UInt64(Date().timeIntervalSince1970))]
        case .training:
            ai = [nil, nil]
        case .demo:
            let seed = UInt64(Date().timeIntervalSince1970)
            ai = [RiftAI(side: 0, difficulty: .hard, seed: seed), RiftAI(side: 1, difficulty: .hard, seed: seed &+ 99)]
        }
        if training { fight.debugSetRage(0, 100) }
        refreshHUD(force: true)
        banner = Banner(text: "第 1 回合", sub: "\(RiftRoster.spec(config.player).name) VS \(RiftRoster.spec(config.opponent).name)")
    }

    // MARK: 输入

    func press(_ button: RiftButton) {
        switch button {
        case .light: pulses.light = true
        case .heavy: pulses.heavy = true
        case .skill1: pulses.skill1 = true
        case .skill2: pulses.skill2 = true
        case .transform: pulses.transform = true
        case .jump: pulses.jump = true
        case .dash: pulses.dash = true
        }
    }

    // MARK: 推进

    /// 由渲染循环每帧调用；内部按固定 1/60 秒步进，掉帧时最多补 4 步
    func advance(now: CFTimeInterval) {
        defer { lastTime = now }
        guard !paused, let last = lastTime else { return }
        accumulator += min(0.1, now - last)
        let dt = 1.0 / Double(RiftFight.ticksPerSecond)
        var steps = 0
        while accumulator >= dt && steps < 4 {
            accumulator -= dt
            stepOnce()
            steps += 1
        }
        if steps == 4 { accumulator = 0 }
    }

    func resetClock() { lastTime = nil; accumulator = 0 }

    private func stepOnce() {
        var p0 = pulses
        p0.horizontal = holdHorizontal
        p0.guardHeld = holdGuard
        pulses = RiftInput()
        var inputs = [p0, RiftInput()]
        if var a = ai[0] { inputs[0] = a.input(for: fight); ai[0] = a }
        if var a = ai[1] { inputs[1] = a.input(for: fight); ai[1] = a }
        if config.mode == .training {
            // 木桩：站着不动，偶尔防御，便于看连招
            inputs[1] = RiftInput()
        }
        fight.step(inputs)
        handle(fight.events)
        eventSink?(fight.events, fight)
        frameCounter += 1
        refreshHUD(force: frameCounter % 2 == 0)
    }

    private func handle(_ events: [RiftEvent]) {
        let p = RiftRoster.spec(config.player).name
        let o = RiftRoster.spec(config.opponent).name
        for e in events {
            switch e {
            case .hit(let h):
                let color: Color
                switch h.kind {
                case .parry: color = .cyan
                case .block: color = .gray
                case .counterHit: color = .orange
                case .echo: color = Color(red: 0.6, green: 0.5, blue: 1)
                case .guardBreak: color = .red
                default: color = h.attacker == 0 ? .yellow : Color(red: 1, green: 0.45, blue: 0.4)
                }
                let text: String
                switch h.kind {
                case .parry: text = "完美格挡"
                case .guardBreak: text = "破防！"
                case .counterHit: text = "破招 \(h.damage)"
                case .armor: text = "霸体 \(h.damage)"
                default: text = h.damage > 0 ? "\(h.damage)" : ""
                }
                if !text.isEmpty {
                    addPopup(text, at: SIMD3(Float(h.x), Float(h.y) + 0.3, 0), color: color,
                             big: h.tier >= .heavy || h.kind == .parry || h.kind == .guardBreak)
                }
                if h.tier == .ultimate && h.kind == .hit { flashScreen(.white) }
            case .burst(let side):
                addPopup("挣脱！", at: SIMD3(Float(fight.fighters[side].x), 2.4, 0), color: .white, big: true)
            case .transformStart(let side):
                let f = fight.fighters[side]
                banner = Banner(text: f.spec.transformName, sub: "\(f.spec.name) · 变身", color: Self.heroColor(f.heroID))
                flashScreen(Self.heroColor(f.heroID))
            case .ultimate(let side):
                let f = fight.fighters[side]
                banner = Banner(text: f.spec.ultimateName, sub: f.spec.name, color: Self.heroColor(f.heroID))
                flashScreen(.white)
            case .roundStart(let r):
                banner = Banner(text: r >= 3 ? "决胜回合" : "第 \(r) 回合", sub: "\(p) VS \(o)")
            case .fight:
                banner = Banner(text: "开战！", color: .orange)
            case .ko:
                banner = Banner(text: "K.O.", color: .red)
                flashScreen(.white)
            case .roundEnd(let w):
                if fight.roundTicksLeft == 0 { banner = Banner(text: "时间到", sub: w == nil ? "平局" : "\(w == 0 ? p : o) 胜") }
            case .matchEnd(let w):
                playerWon = w == 0
                matchOver = true
                banner = nil
            default:
                break
            }
        }
    }

    private func addPopup(_ text: String, at world: SIMD3<Float>, color: Color, big: Bool) {
        popups.append(Popup(text: text, world: world, color: color, big: big, born: Date()))
        if popups.count > 12 { popups.removeFirst(popups.count - 12) }
    }

    func prunePopups(now: Date) {
        let alive = popups.filter { now.timeIntervalSince($0.born) < 0.9 }
        if alive.count != popups.count { popups = alive }
    }

    private func flashScreen(_ color: Color) {
        flash = color
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000)
            self?.flash = nil
        }
    }

    private func refreshHUD(force: Bool) {
        var h = HUD()
        for i in 0..<2 {
            let f = fight.fighters[i]
            let ratio = Double(f.health) / Double(f.maxHealth)
            h.health[i] = ratio
            h.healthValue[i] = f.health
            // 白色残血条慢慢跟上
            if ghost[i] < ratio { ghost[i] = ratio } else { ghost[i] = max(ratio, ghost[i] - (f.comboHits > 0 ? 0 : 0.012)) }
            h.ghostHealth[i] = ghost[i]
            h.rage[i] = f.rage / 100
            h.guardMeter[i] = f.guardMeter / 100
            h.transformed[i] = f.isTransformed
            h.transformLeft[i] = Double(f.transformRemaining) / Double(f.spec.transform.duration)
            h.wins[i] = f.wins
            // 连击数显示在攻击方一侧
            let defenderCombo = fight.fighters[1 - i].comboHits
            if defenderCombo >= 2 { comboShown[i] = defenderCombo; comboTimer[i] = 50 }
            else if comboTimer[i] > 0 { comboTimer[i] -= 1 } else { comboShown[i] = 0 }
            h.combo[i] = comboShown[i]
        }
        let me = fight.fighters[0]
        h.seconds = fight.secondsLeft
        h.round = fight.round
        h.cooldown1 = me.cooldownFraction(.skill1)
        h.cooldown2 = me.cooldownFraction(.skill2)
        h.canTransform = me.canTransform
        h.canUltimate = me.canUltimate
        h.counterReady = me.counterReady > 0
        if force || h.health != hud.health || h.combo != hud.combo { if h != hud { hud = h } }
    }

    static func heroColor(_ id: RiftHeroID) -> Color {
        let c = RiftPalette.accent(id)
        return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
    }
}

enum RiftButton: Hashable {
    case light, heavy, skill1, skill2, transform, jump, dash
}

/// 每个英雄的主题色（刀光、特效、界面都用这一套）
enum RiftPalette {
    static func accent(_ id: RiftHeroID) -> SIMD3<Float> {
        switch id {
        case .sunDeng: return SIMD3(0.55, 0.75, 1.0)     // 冷蓝刀光
        case .wuYong: return SIMD3(1.0, 0.36, 0.18)      // 鬼火赤橙
        case .liuQuanwei: return SIMD3(1.0, 0.72, 0.25)  // 开天金
        case .xuXiao: return SIMD3(0.98, 0.84, 0.35)     // 帝王金
        }
    }
    static func secondary(_ id: RiftHeroID) -> SIMD3<Float> {
        switch id {
        case .sunDeng: return SIMD3(0.45, 0.3, 1.0)
        case .wuYong: return SIMD3(0.75, 0.05, 0.08)
        case .liuQuanwei: return SIMD3(0.55, 0.25, 0.08)
        case .xuXiao: return SIMD3(0.12, 0.08, 0.06)
        }
    }
}
