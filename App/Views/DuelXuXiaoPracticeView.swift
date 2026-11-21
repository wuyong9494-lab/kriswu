#if L12_INTERNAL_PREVIEW
import SwiftUI

/// Deliberately distinct from the authenticated three-character renderer.
/// All silhouettes, sword cues and impacts are procedural schematic shapes.
@MainActor
struct DuelXuXiaoPracticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var controller = DuelXuXiaoPracticeController()
    @State private var showingNotice = false
    private let gold = Color(red: 0.95, green: 0.74, blue: 0.32)
    private var inputEnabled: Bool { !controller.paused && controller.game.outcome == nil && scenePhase == .active }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 450
            VStack(spacing: compact ? 6 : 12) {
                HStack(spacing: 12) {
                    Button("返回小游戏") { controller.leave(); dismiss() }
                        .accessibilityIdentifier("xuxiao.practice.close")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("徐骁 · 替代练习版").font(.headline)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("徐骁 · 替代练习版")
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("xuxiao.practice.title")
                        Text("示意人物 / 重建动作 · 非原版资源").font(.caption2)
                    }
                    Spacer(minLength: 0)
                    Text("\(controller.game.remainingSeconds)s").monospacedDigit()
                        .accessibilityLabel("剩余 \(controller.game.remainingSeconds) 秒")
                    Button("说明") { controller.togglePauseIfRunning(); showingNotice = true }
                        .accessibilityIdentifier("xuxiao.practice.notice")
                    Button(controller.paused ? "继续" : "暂停") { controller.togglePause() }
                        .disabled(controller.game.outcome != nil)
                        .accessibilityIdentifier("xuxiao.practice.pause")
                }
                HStack(spacing: 24) {
                    healthBar(0, name: "徐骁 · 示意")
                    healthBar(1, name: "练习对手")
                }
                arena
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                Text(controller.game.feedback)
                    .font(.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("xuxiao.practice.feedback")
                controls
                if !compact {
                    Text("长按左右移动，拉后防御；点击剑击或重击。此模式不联机、不影响正式战绩。")
                        .font(.caption2).foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(compact ? 8 : 16)
            .background(Color(red: 0.035, green: 0.055, blue: 0.09).ignoresSafeArea())
            .foregroundStyle(.white).tint(gold)
        }
        .modifier(ArenaLandscape())
        // Materialize the parent container before assigning its identifier.
        // Otherwise SwiftUI can propagate a container ID to child elements.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("xuxiao.practice.root")
        .onAppear { controller.setSceneActive(scenePhase == .active) }
        .onChange(of: scenePhase) { controller.setSceneActive($0 == .active) }
        .onDisappear { controller.leave() }
        .alert("替代练习版，不是正式徐骁", isPresented: $showingNotice) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("目前缺少已验证的徐骁正式身体、傀儡及完整技能资源。本页仅用几何示意人物和重建规则进行单机练习，无原版模型、音效或还原度承诺。关闭说明后请手动继续。")
        }
    }

    private func healthBar(_ seat: Int, name: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(.caption)
                Spacer()
                Text("\(controller.game.fighters[seat].health) / 100").font(.caption.monospacedDigit())
            }
            ProgressView(value: Double(controller.game.fighters[seat].health), total: 100)
                .tint(seat == 0 ? gold : .pink)
        }
    }

    private var arena: some View {
        GeometryReader { geometry in
            let floor = geometry.size.height * 0.87
            let figureHeight = min(130.0, geometry.size.height * 0.73)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.04))
                Path { path in
                    path.move(to: CGPoint(x: 0, y: floor))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: floor))
                }.stroke(gold.opacity(0.3), lineWidth: 2)
                ForEach(0..<2, id: \.self) { seat in
                    let fighter = controller.game.fighters[seat]
                    XuXiaoPracticeFigure(attacking: fighter.strike != nil, guarding: fighter.guarding)
                        .stroke(fighter.stun > 0 ? .white : seat == 0 ? gold : .pink,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        .frame(width: figureHeight * 0.65, height: figureHeight)
                        .scaleEffect(x: CGFloat(fighter.facing), y: 1)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(seat == 0 ? "徐骁示意人物" : "练习对手")
                        .accessibilityValue(Text(verbatim: "位置 \(fighter.x)，生命 \(fighter.health)，\(fighter.guarding ? "防御" : fighter.strike != nil ? "攻击" : "站立")"))
                        .accessibilityIdentifier("xuxiao.practice.fighter.\(seat)")
                        // Place the accessible figure as a unit in the arena.
                        .position(x: CGFloat(fighter.x) / 10_000 * geometry.size.width,
                                  y: floor - figureHeight / 2)
                }
                if let impact = controller.game.lastImpact {
                    Circle().stroke(impact.blocked ? .cyan : gold, lineWidth: 4)
                        .frame(width: 36, height: 36)
                        .position(x: CGFloat(impact.x) / 10_000 * geometry.size.width,
                                  y: floor - figureHeight * 0.6)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                if let result = controller.game.outcome {
                    VStack(spacing: 10) {
                        Text(result == .won ? "练习胜利" : result == .lost ? "练习结束 · 再试一次" : "练习平局")
                            .font(.headline).accessibilityIdentifier("xuxiao.practice.result")
                        HStack {
                            Button("再练一局") { controller.restart() }
                                .accessibilityIdentifier("xuxiao.practice.rematch")
                            Button("返回小游戏") { controller.leave(); dismiss() }
                                .accessibilityIdentifier("xuxiao.practice.resultClose")
                        }.buttonStyle(.borderedProminent)
                    }
                    .padding(16).background(.black.opacity(0.94), in: RoundedRectangle(cornerRadius: 12))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                } else if controller.paused {
                    Text("已暂停").font(.headline)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .background(.black.opacity(0.5)).allowsHitTesting(false)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("xuxiao.practice.arena")
    }

    private var controls: some View {
        HStack(spacing: 12) {
            XuXiaoPracticeHold(label: "向左", id: "xuxiao.practice.left", enabled: inputEnabled,
                              setHeld: controller.left, nudge: { controller.nudge(left: true) })
            XuXiaoPracticeHold(label: "向右", id: "xuxiao.practice.right", enabled: inputEnabled,
                              setHeld: controller.right, nudge: { controller.nudge(left: false) })
            Spacer(minLength: 0)
            Button("剑击") { controller.attack() }
                .accessibilityIdentifier("xuxiao.practice.attack")
            Button("重击") { controller.attack(heavy: true) }
                .accessibilityIdentifier("xuxiao.practice.heavy")
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .disabled(!inputEnabled)
    }
}

private struct XuXiaoPracticeFigure: Shape {
    let attacking: Bool
    let guarding: Bool
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.width * x, y: rect.height * y) }
        func line(_ points: [(CGFloat, CGFloat)]) {
            guard let first = points.first else { return }
            path.move(to: point(first.0, first.1))
            for p in points.dropFirst() { path.addLine(to: point(p.0, p.1)) }
        }
        path.addEllipse(in: CGRect(x: rect.width * 0.36, y: 0, width: rect.width * 0.28, height: rect.height * 0.19))
        line([(0.5, 0.2), (0.5, 0.65), (0.2, 1)])
        line([(0.5, 0.65), (0.8, 1)])
        line([(0.5, 0.3), (0.2, 0.5), (0.1, 0.64)])
        if attacking { line([(0.5, 0.3), (0.72, 0.4), (1, 0.34), (1.35, 0.25)]) }
        else if guarding { line([(0.5, 0.3), (0.78, 0.42), (0.85, 0.2), (0.85, 0.7)]) }
        else { line([(0.5, 0.3), (0.75, 0.52), (0.82, 0.72), (1, 0.1)]) }
        return path
    }
}

private struct XuXiaoPracticeHold: View {
    let label: String
    let id: String
    let enabled: Bool
    let setHeld: (Bool) -> Void
    let nudge: () -> Void
    @State private var held = false
    var body: some View {
        Text(label).font(.headline).frame(minWidth: 58, minHeight: 44)
            .background(held ? .white.opacity(0.3) : .white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in guard enabled else { return }; held = true; setHeld(true) }
                .onEnded { _ in held = false; setHeld(false) })
            .onChange(of: enabled) { if !$0 { held = false; setHeld(false) } }
            .onDisappear { held = false; setHeld(false) }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityAction { if enabled { nudge() } }
            .accessibilityIdentifier(id)
    }
}

private extension DuelXuXiaoPracticeController {
    func togglePauseIfRunning() { if !paused && game.outcome == nil { togglePause() } }
}
#endif
