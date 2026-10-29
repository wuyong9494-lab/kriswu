import SwiftUI

struct ArenaDiagnosticSuiteView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var recorder = ArenaPerfRecorder.shared
    @State private var selected: ArenaDiagnostics.Variant = .baseline
    @State private var controller: ArenaController?
    @State private var scenarioIndex = 0
    @State private var exportURL: URL?
    @State private var error: String?
    @State private var running = false
    private let variants: [ArenaDiagnostics.Variant] = [.baseline, .noBones, .noBushes, .noCharacterOutlines, .noNumbersOrParticles, .noEffectAudio, .noAI]

    var body: some View {
        ZStack {
            if let controller, running {
                ArenaMatchView(controller: controller, onExit: { finish(interrupted: "用户提前结束") })
                    .id(scenarioIndex)
                    .overlay(alignment: .bottom) {
                        Text("诊断 \(scenarioIndex + 1)/4 · \(recorder.progress) · \(selected.title)")
                            .font(.caption.monospacedDigit()).padding(8).background(.black.opacity(0.75), in: Capsule())
                            .foregroundStyle(.white).allowsHitTesting(false)
                    }
                    .allowsHitTesting(false) // scripted input, no touch-dependent comparison
                    .overlay(alignment: .topTrailing) {
                        Button("结束并导出") { finish(interrupted: "用户提前结束") }
                            .padding(10).background(ArenaMenuTheme.panel, in: Capsule()).padding()
                    }
            } else {
                ArenaMenuScreen(title: "持续性能诊断", onClose: { dismiss() }) {
                    VStack(spacing: 12) {
                        ArenaMenuCard {
                            Text(ArenaPerfRecorder.identity).font(.caption.monospaced()).textSelection(.enabled)
                            Text("先确认此版本与手机安装版本。一次运行约132秒：空场、单人走路、多人无攻击、多人混战，各预热3秒并连续采样30秒。")
                            Text("同峡谷、同相机、同种子；每次只选择一个对照项。后台或中断会保留未完成记录。回调帧时间不等于实际呈现帧率，GPU未测。")
                                .font(.caption).foregroundStyle(.white.opacity(0.7))
                        }
                        ArenaMenuCard {
                            ForEach(variants, id: \.rawValue) { variant in
                                Button { selected = variant } label: {
                                    HStack { Text(variant.title); Spacer(); Image(systemName: selected == variant ? "checkmark.circle.fill" : "circle") }
                                        .padding(10).frame(minHeight: 44)
                                }.buttonStyle(ArenaMenuButtonStyle())
                            }
                            Button("一键运行四组测试") { start() }.padding(12).buttonStyle(ArenaMenuButtonStyle())
                        }
                        if let exportURL {
                            ShareLink(item: exportURL) { Label("导出连续帧时间与设备报告", systemImage: "square.and.arrow.up").padding(12) }
                                .buttonStyle(ArenaMenuButtonStyle())
                        }
                        if let error { Text(error).foregroundStyle(.orange) }
                    }
                }
            }
        }
        .modifier(ArenaLandscape())
        .onChange(of: recorder.finishedCase) { done in
            guard done, running else { return }
            if scenarioIndex < 3 { scenarioIndex += 1; startCase() }
            else { finish(interrupted: nil) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if running { finish(interrupted: "App失去前台，连续采样中断") }
        }
        .onDisappear { if running { finish(interrupted: "离开诊断页面") } }
    }
    private func start() {
        exportURL = nil; error = nil; scenarioIndex = 0
        recorder.beginSuite(variant: selected)
        running = true
        startCase()
    }
    private func startCase() {
        let scenario = ArenaDiagnosticScenario.allCases[scenarioIndex]
        recorder.beginCase(scenario)
        controller = ArenaController(setup: .init(mode: .zone, brawler: .ranger, name: "我", level: 3,
            loadout: .basic(.ranger, level: 3), benchmark: true, diagnosticScenario: scenario))
    }
    private func finish(interrupted: String?) {
        guard running else { return }
        running = false // prevent a finish notification from starting the next case
        if let interrupted { recorder.interrupt(interrupted) }
        controller = nil
        do { exportURL = try recorder.export() }
        catch { self.error = "导出失败：\(error.localizedDescription)" }
        recorder.stop()
    }
}
