import SwiftUI

/// First playable network presentation: two seats, authoritative health and
/// touch inputs. This intentionally does not substitute an offline DuelSession.
struct DuelNetworkCombatView: View {
    @ObservedObject var combat: DuelNetworkCombatSession
    let onExit: () -> Void
    @State private var heldMove = 0
    @State private var heldGuard = false
    @State private var inputTask: Task<Void, Never>?

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
                    if combat.status == .running {
                        DuelNetworkScene(state: state)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("duel.combat.scene")
                    } else {
                        Spacer(minLength: 0)
                    }
                    if combat.status == .failed {
                        Text(combat.failure ?? "联机连接已中断")
                            .font(.headline).foregroundStyle(.orange)
                        Button("退出并返回大厅") { onExit() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("duel.combat.disconnect.exit")
                    } else if state.phase == .matchOver {
                        Text(state.winner.map { $0 == 0 ? "1P 获胜" : "2P 获胜" } ?? "对战结束")
                            .font(.title.bold()).accessibilityIdentifier("duel.combat.result")
                        Button("结束对战") { combat.stop(); onExit() }
                            .buttonStyle(.borderedProminent)
                    } else if combat.status == .running && state.phase == .fighting {
                        HStack(spacing: 14) {
                            heldButton("后退", move: -1)
                            heldButton("前进", move: 1)
                            heldButton("格挡", guardHeld: true)
                            Button("轻击") { combat.sendInput(tapBits: DuelGame.Buttons.light.rawValue) }
                            Button("重击") { combat.sendInput(tapBits: DuelGame.Buttons.heavy.rawValue) }
                            Button("技能一") { combat.sendInput(tapBits: DuelGame.Buttons.skill1.rawValue) }
                            Button("技能二") { combat.sendInput(tapBits: DuelGame.Buttons.skill2.rawValue) }
                            Button("跳跃") { combat.sendInput(tapBits: DuelGame.Buttons.jump.rawValue) }
                            Button("大招") { combat.sendInput(tapBits: DuelGame.Buttons.ultimate.rawValue) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(geometry.size.width < 700 ? .small : .regular)
                        .accessibilityIdentifier("duel.combat.controls")
                    } else if state.phase == .roundBreak {
                        Text("回合结束 · 等待下一回合")
                            .font(.headline)
                            .accessibilityIdentifier("duel.combat.roundBreak")
                    }
                } else if combat.status == .failed || combat.status == .ended {
                    Spacer()
                    Text(combat.failure ?? "联机对战已结束")
                        .font(.headline).foregroundStyle(.orange)
                    Button("返回大厅") { onExit() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("duel.combat.noState.exit")
                    Spacer()
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
        .onAppear { beginInputClock() }
        .onDisappear { inputTask?.cancel(); inputTask = nil; releaseHeld() }
    }

    private func heldButton(_ title: String, move: Int = 0, guardHeld: Bool = false) -> some View {
        Text(title)
            .font(.callout.bold())
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background((heldMove == move && move != 0) || (guardHeld && heldGuard)
                        ? Color.orange : Color.white.opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if move != 0 { heldMove = move; heldGuard = false }
                    else if guardHeld { heldMove = 0; heldGuard = true }
                }
                .onEnded { _ in releaseHeld() })
            .accessibilityIdentifier("duel.combat.hold")
    }

    private func releaseHeld() {
        heldMove = 0
        heldGuard = false
        combat.sendInput()
    }

    private func beginInputClock() {
        guard inputTask == nil else { return }
        inputTask = Task { @MainActor in
            while !Task.isCancelled {
                if combat.status == .running && combat.state?.phase == .fighting
                    && (heldMove != 0 || heldGuard) {
                    combat.sendInput(move: heldMove, guardHeld: heldGuard)
                }
                do { try await Task.sleep(nanoseconds: 50_000_000) }
                catch { break }
            }
        }
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
