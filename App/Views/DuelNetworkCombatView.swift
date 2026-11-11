import SwiftUI

/// First playable network presentation: two seats, authoritative health and
/// touch inputs. This intentionally does not substitute an offline DuelSession.
struct DuelNetworkCombatView: View {
    @ObservedObject var combat: DuelNetworkCombatSession
    let onExit: () -> Void

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                HStack {
                    Button("返回大厅") { combat.stop(); onExit() }
                        .accessibilityIdentifier("duel.combat.exit")
                    Spacer()
                    Text("双人联网对战").font(.headline)
                    Spacer()
                    Text(combat.status == .running ? "对战中" : "已结束")
                }
                if let state = combat.state {
                    HStack(spacing: 16) {
                        fighter(state.fighters[0], seat: 0)
                        Text("VS").font(.title.bold()).foregroundStyle(.orange)
                        fighter(state.fighters[1], seat: 1)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                    if state.phase == .matchOver {
                        Text(state.winner.map { $0 == 0 ? "1P 获胜" : "2P 获胜" } ?? "对战结束")
                            .font(.title.bold()).accessibilityIdentifier("duel.combat.result")
                        Button("结束对战") { combat.stop(); onExit() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        HStack(spacing: 14) {
                            Button("后退") { combat.sendInput(move: -1) }
                            Button("前进") { combat.sendInput(move: 1) }
                            Button("格挡") { combat.sendInput(guardHeld: true) }
                            Button("轻击") { combat.sendInput(tapBits: DuelGame.Buttons.light.rawValue) }
                            Button("重击") { combat.sendInput(tapBits: DuelGame.Buttons.heavy.rawValue) }
                            Button("技能") { combat.sendInput(tapBits: DuelGame.Buttons.skill1.rawValue) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(geometry.size.width < 700 ? .small : .regular)
                        .accessibilityIdentifier("duel.combat.controls")
                    }
                } else {
                    Spacer()
                    ProgressView("等待房主同步战斗状态…")
                    Spacer()
                }
                if let failure = combat.failure {
                    Text(failure).foregroundStyle(.orange)
                        .accessibilityIdentifier("duel.combat.failure")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
            .background(Color(red: 0.07, green: 0.08, blue: 0.14))
        }
        .modifier(ArenaLandscape())
        .interactiveDismissDisabled()
    }

    private func fighter(_ fighter: DuelNetworkCombatState.Fighter, seat: Int) -> some View {
        VStack(spacing: 8) {
            Text(fighter.hero.name + (seat == 0 ? " · 1P" : " · 2P")).font(.headline)
            ProgressView(value: Double(fighter.health), total: 1000)
                .tint(fighter.health < 250 ? .red : .green)
            Text("生命 \(fighter.health) / 1000 · 能量 \(fighter.energy)")
                .font(.caption).monospacedDigit()
            Text("位置 \(fighter.x) · 朝向 \(fighter.facing)")
                .font(.caption2).foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("duel.combat.fighter.\(seat)")
    }
}
