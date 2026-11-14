import SwiftUI

/// Both screens sample the same authoritative state. No display timer advances
/// buffs, cooldowns, Light, or an ability phase.
struct DuelPanguHUD: View {
    let state: DuelPanguState
    var isEscapingOrdinaryThrow = false
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: Double(state.light), total: Double(state.rules.light.maximum))
                .tint(.yellow)
                .accessibilityLabel("光能")
                .accessibilityValue("\(state.light) / \(state.rules.light.maximum)")
            Text(summary)
                .font(.system(size: prominent ? 14 : 10, design: .monospaced))
                .foregroundStyle(.yellow.opacity(0.92))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .accessibilityIdentifier("duel.pangu.status")
        }
    }

    private var summary: String {
        var parts = ["长矛 \(state.rangedCharges)/\(state.rules.ranged.maximumCharges)"]
        if isEscapingOrdinaryThrow { parts.append("自动挣脱") }
        if let cast = state.activeCast {
            parts.append("\(cast.ability.title) · \(phase(cast.phase))")
        }
        if state.typhoonRemainingTicks > 0 { parts.append("风暴 \(seconds(state.typhoonRemainingTicks))") }
        if state.rhythmRemainingTicks > 0 { parts.append("猎矛强化 \(seconds(state.rhythmRemainingTicks))") }
        if state.tranceRemainingTicks > 0 { parts.append("天坠强化 \(seconds(state.tranceRemainingTicks))") }
        if state.earthquakeRemainingTicks > 0 { parts.append("震地 \(seconds(state.earthquakeRemainingTicks))") }
        if state.boulderBonusRemainingTicks > 0 { parts.append("落石追加 \(seconds(state.boulderBonusRemainingTicks))") }
        return parts.joined(separator: " · ")
    }

    private func seconds(_ ticks: Int) -> String {
        let tenths = (max(0, ticks) + 5) / 6
        return "\(tenths / 10).\(tenths % 10)秒"
    }

    private func phase(_ phase: DuelPanguState.Phase) -> String {
        switch phase {
        case .startup: return "起手"
        case .active: return "施放"
        case .recovery: return "收招"
        case .petrifying: return "石化"
        case .rising: return "升柱"
        case .charging: return "蓄能"
        case .falling: return "下坠"
        case .landing: return "落地"
        }
    }
}

struct DuelPanguControlHUD: View {
    let controls: [DuelPanguPresentation.Control]
    var prominent = false

    var body: some View {
        if !controls.isEmpty {
            Text(controls.map { control in
                let tenths = (control.remainingTicks + 5) / 6
                return "\(title(control.kind)) \(tenths / 10).\(tenths % 10)秒"
            }.joined(separator: " · "))
                .font(.system(size: prominent ? 14 : 10, design: .monospaced))
                .foregroundStyle(.orange)
                .lineLimit(2)
                .accessibilityIdentifier("duel.pangu.control")
        }
    }

    private func title(_ kind: DuelPanguPresentation.Control.Kind) -> String {
        switch kind {
        case .stun: return "眩晕"
        case .petrify: return "石化"
        case .pinned: return "钉岩"
        case .airHeld: return "浮空"
        case .dread: return "震慑"
        }
    }
}
