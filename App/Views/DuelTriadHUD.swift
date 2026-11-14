import SwiftUI

struct DuelTriadHUD: View {
    let state: DuelTriadState
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: Double(state.mist), total: Double(state.rules.mist.maximum))
                .tint(.purple)
                .accessibilityLabel("雾气")
                .accessibilityValue("\(state.mist) / \(state.rules.mist.maximum)")
            Text(summary)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.purple)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .accessibilityIdentifier("duel.triad.status")
        }
    }
    private var summary: String {
        var parts = ["雾潮 \(state.onslaughtCharges)/\(DuelTriadRules.maximumOnslaughtCharges)"]
        if state.rules.level >= 6 { parts.append("刻痕 \(state.notches)/\(state.rules.souls.notchCost)") }
        if state.breakthroughReady { parts.append("突破就绪") }
        if let cast = state.activeCast { parts.append(cast.ability.title) }
        if state.mistBladeRemainingTicks > 0 { parts.append("雾刃 \(seconds(state.mistBladeRemainingTicks))") }
        else if state.mistBladeUnlocked { parts.append("雾刃可用") }
        if state.rootRemainingTicks > 0 { parts.append("根枝 \(seconds(state.rootRemainingTicks))") }
        return parts.joined(separator: " · ")
    }
    private func seconds(_ ticks: Int) -> String {
        let tenths = (max(0, ticks) + 5) / 6
        return "\(tenths / 10).\(tenths % 10)秒"
    }
}

struct DuelTriadControlHUD: View {
    let controls: [DuelTriadPresentation.Control]
    var body: some View {
        if !controls.isEmpty {
            Text(controls.map { control in
                let title: String
                switch control.kind {
                case .root: title = "根枝束缚"
                case .stun: title = "诅咒眩晕"
                case .suppression: title = "压制 ×\(control.stacks)"
                }
                return "\(title) \((control.remainingTicks + 59) / 60)秒"
            }.joined(separator: " · "))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.purple)
                .lineLimit(2)
                .accessibilityIdentifier("duel.triad.control")
        }
    }
}
