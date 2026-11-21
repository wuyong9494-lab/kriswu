import SwiftUI

/// 对战画面：3D 擂台 + 血条/怒气/计时 + 操作面板 + 伤害数字 + 横幅
struct RiftMatchView: View {
    @StateObject private var session: RiftSession
    let onExit: () -> Void
    let onRematch: () -> Void

    init(config: RiftSession.Config, onExit: @escaping () -> Void, onRematch: @escaping () -> Void) {
        _session = StateObject(wrappedValue: RiftSession(config: config))
        self.onExit = onExit
        self.onRematch = onRematch
    }

    var body: some View {
        ZStack {
            RiftArenaView(session: session)
                .ignoresSafeArea()
            if let flash = session.flash {
                flash.opacity(0.35).ignoresSafeArea().allowsHitTesting(false)
            }
            RiftPopupLayer(session: session)
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                RiftTopHUD(session: session, onPause: { session.paused = true })
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            if session.config.mode != .demo {
                RiftControls(session: session, hero: session.config.player)
                    .ignoresSafeArea()
            }
            RiftBannerView(banner: session.banner)
                .allowsHitTesting(false)
            if session.paused {
                pauseMenu
            }
            if session.matchOver {
                resultMenu
            }
        }
        .background(Color.black)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    private var pauseMenu: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("暂停").font(.system(size: 30, weight: .black)).foregroundStyle(.white)
                RiftMoveList(hero: session.config.player)
                HStack(spacing: 14) {
                    RiftMenuButton(title: "继续", id: "rift.resume") { session.paused = false; session.resetClock() }
                    RiftMenuButton(title: "重新开始", id: "rift.restart", style: .secondary) { onRematch() }
                    RiftMenuButton(title: "退出", id: "rift.exit", style: .secondary) { onExit() }
                }
            }
            .padding(24)
        }
    }

    private var resultMenu: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(session.config.mode == .demo ? "演示结束" : (session.playerWon ? "胜利" : "败北"))
                    .font(.system(size: 54, weight: .black))
                    .foregroundStyle(session.playerWon ? Color.yellow : Color(white: 0.8))
                    .shadow(color: .orange.opacity(session.playerWon ? 0.8 : 0), radius: 16)
                    .accessibilityIdentifier("rift.result")
                Text("\(session.hud.wins[0]) : \(session.hud.wins[1])")
                    .font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.white)
                HStack(spacing: 14) {
                    RiftMenuButton(title: "再来一局", id: "rift.rematch") { onRematch() }
                    RiftMenuButton(title: "返回选人", id: "rift.back", style: .secondary) { onExit() }
                }
            }
        }
    }
}

// MARK: - 顶部 HUD

struct RiftTopHUD: View {
    @ObservedObject var session: RiftSession
    let onPause: () -> Void

    var body: some View {
        let hud = session.hud
        HStack(alignment: .top, spacing: 10) {
            side(0, hud: hud)
            VStack(spacing: 2) {
                Text("\(hud.seconds)")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(hud.seconds <= 10 ? .red : .white)
                    .monospacedDigit()
                    .accessibilityIdentifier("rift.timer")
                Button(action: onPause) {
                    Image(systemName: "pause.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 24).background(.black.opacity(0.4), in: Capsule())
                }
                .accessibilityIdentifier("rift.pause")
            }
            .frame(width: 64)
            side(1, hud: hud)
        }
    }

    private func side(_ i: Int, hud: RiftSession.HUD) -> some View {
        let hero = i == 0 ? session.config.player : session.config.opponent
        let spec = RiftRoster.spec(hero)
        let color = RiftSession.heroColor(hero)
        let leading = i == 0
        return VStack(alignment: leading ? .leading : .trailing, spacing: 4) {
            HStack(spacing: 6) {
                if !leading { pips(hud.wins[i]) }
                Text(spec.name).font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                Text(hud.transformed[i] ? spec.transformName : spec.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(hud.transformed[i] ? color : .white.opacity(0.7))
                if leading { pips(hud.wins[i]) }
            }
            .environment(\.layoutDirection, .leftToRight)
            // 血条：白色残血 + 主血条
            GeometryReader { geo in
                ZStack(alignment: leading ? .leading : .trailing) {
                    Rectangle().fill(.black.opacity(0.55))
                    Rectangle().fill(.white.opacity(0.85)).frame(width: geo.size.width * hud.ghostHealth[i])
                    Rectangle()
                        .fill(LinearGradient(colors: hud.health[i] < 0.3 ? [.red, .orange] : [Color(red: 1, green: 0.85, blue: 0.2), Color(red: 0.95, green: 0.45, blue: 0.1)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: geo.size.width * hud.health[i])
                }
                .overlay(Rectangle().stroke(.white.opacity(0.8), lineWidth: 1.5))
                .skewed(leading ? -0.3 : 0.3)
            }
            .frame(height: 16)
            .accessibilityElement()
            .accessibilityIdentifier("rift.hp.\(i)")
            .accessibilityValue(Text(verbatim: "\(hud.healthValue[i])"))
            // 怒气条
            GeometryReader { geo in
                ZStack(alignment: leading ? .leading : .trailing) {
                    Rectangle().fill(.black.opacity(0.5))
                    Rectangle().fill(hud.transformed[i] ? color : Color(red: 0.4, green: 0.6, blue: 1))
                        .frame(width: geo.size.width * (hud.transformed[i] ? hud.transformLeft[i] : hud.rage[i]))
                        .shadow(color: hud.rage[i] >= 1 ? color : .clear, radius: 6)
                }
                .skewed(leading ? -0.3 : 0.3)
            }
            .frame(width: 150, height: 7)
            .accessibilityElement()
            .accessibilityIdentifier("rift.rage.\(i)")
            .accessibilityValue(hud.transformed[i] ? "transformed" : "\(Int(hud.rage[i] * 100))")
            if hud.combo[i] >= 2 {
                Text("\(hud.combo[i]) 连击")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black, radius: 2)
                    .transition(.scale)
            }
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
    }

    private func pips(_ n: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<RiftFight.roundsToWin, id: \.self) { k in
                Circle().fill(k < n ? Color.yellow : Color.black.opacity(0.5))
                    .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
                    .frame(width: 9, height: 9)
            }
        }
    }
}

private extension View {
    func skewed(_ k: CGFloat) -> some View {
        transformEffect(CGAffineTransform(a: 1, b: 0, c: k, d: 1, tx: -k * 8, ty: 0))
    }
}

// MARK: - 伤害数字

struct RiftPopupLayer: View {
    @ObservedObject var session: RiftSession

    var body: some View {
        TimelineView(.animation) { context in
            ZStack {
                ForEach(session.popups) { p in
                    if let pt = session.projector?(p.world) {
                        let age = context.date.timeIntervalSince(p.born)
                        Text(p.text)
                            .font(.system(size: p.big ? 30 : 22, weight: .black, design: .rounded))
                            .foregroundStyle(p.color)
                            .shadow(color: .black.opacity(0.9), radius: 2, x: 1, y: 1)
                            .scaleEffect(age < 0.08 ? 1.5 - age * 6 : 1)
                            .opacity(max(0, 1 - age / 0.9))
                            .position(x: pt.x, y: pt.y - CGFloat(age) * 60)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - 横幅

struct RiftBannerView: View {
    let banner: RiftSession.Banner?
    @State private var visible: RiftSession.Banner?

    var body: some View {
        ZStack {
            if let b = visible {
                VStack(spacing: 4) {
                    Text(b.text)
                        .font(.system(size: 56, weight: .black))
                        .foregroundStyle(b.color)
                        .shadow(color: .black, radius: 4)
                        .shadow(color: b.color.opacity(0.7), radius: 18)
                    if !b.sub.isEmpty {
                        Text(b.sub).font(.system(size: 18, weight: .bold)).foregroundStyle(.white).shadow(color: .black, radius: 3)
                    }
                }
                .transition(.scale(scale: 1.6).combined(with: .opacity))
                .id(b.id)
                .accessibilityIdentifier("rift.banner")
            }
        }
        .onChange(of: banner) { new in
            guard let new else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { visible = new }
            let id = new.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                if visible?.id == id { withAnimation(.easeOut(duration: 0.25)) { visible = nil } }
            }
        }
    }
}

// MARK: - 通用

struct RiftMenuButton: View {
    enum Style { case primary, secondary }
    let title: String
    let id: String
    var style: Style = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(style == .primary ? .black : .white)
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(style == .primary ? AnyShapeStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                                              : AnyShapeStyle(Color.white.opacity(0.15)),
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.4), lineWidth: 1))
        }
        .accessibilityIdentifier(id)
    }
}

/// 出招表
struct RiftMoveList: View {
    let hero: RiftHeroID

    var body: some View {
        let spec = RiftRoster.spec(hero)
        VStack(alignment: .leading, spacing: 5) {
            row("轻击 ×3", "\(spec.move(.light1)!.name) → \(spec.move(.light2)!.name) → \(spec.move(.light3)!.name)")
            row("重击", spec.move(.heavy)!.name + "（轻击命中后可接）")
            row("技能1", spec.move(.skill1)!.name)
            row("技能2", spec.move(.skill2)!.name)
            row("空中轻/重", spec.move(.airAttack)!.name)
            row("怒气满", "\(spec.transformName)（变身），变身中再按：\(spec.ultimateName)")
            row("完美格挡", "被击中前一瞬间按防御，再按轻击：\(spec.move(.counter)!.name)")
            row("移动", "摇杆左右；上推跳；同方向快推两下冲刺")
        }
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .padding(14)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).fontWeight(.heavy).foregroundStyle(.yellow).frame(width: 80, alignment: .leading)
            Text(v)
        }
    }
}
