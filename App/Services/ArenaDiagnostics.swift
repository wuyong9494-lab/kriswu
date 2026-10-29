import Foundation
import os
import UIKit

/// Lock protects diagnostics only; SceneKit work stays on its existing thread.
final class ArenaDiagnostics: @unchecked Sendable {
    static let shared = ArenaDiagnostics()
    enum Variant: String, CaseIterable {
        case baseline, noNumbers, noParticles, noCharacterOutlines, halfAnimation, noBones, noBushes, noNumbersOrParticles, noAI, noEffectAudio
        var title: String {
            switch self {
            case .baseline: return "基准（正常显示）"
            case .noNumbers: return "仅关闭飘字"
            case .noParticles: return "仅关闭粒子"
            case .noCharacterOutlines: return "仅关闭人物描边"
            case .halfAnimation: return "仅隔帧采样骨骼"
            case .noBones: return "关闭骨骼，保留移动"
            case .noBushes: return "关闭装饰草丛，保留规则"
            case .noNumbersOrParticles: return "关闭浮字与粒子"
            case .noAI: return "关闭机器人逻辑"
            case .noEffectAudio: return "仅关闭战斗音效（保留音乐）"
            }
        }
    }
    private var storedVariant = Variant(rawValue: UserDefaults.standard.string(forKey: "arena.diagnosticVariant") ?? "") ?? .baseline
    private let lock = NSLock()
    var variant: Variant { lock.lock(); defer { lock.unlock() }; return storedVariant }
    var enabled: Bool { lock.lock(); defer { lock.unlock() }; return storedEnabled }
    func configureCapture(_ variant: Variant, enabled: Bool = true) {
        lock.lock(); storedVariant = variant; storedEnabled = enabled; samples.reset(); lock.unlock()
    }
    private var reportText = "尚未采样：开启性能显示并重启 App，然后进入对局。"
    var latestReport: String {
        lock.lock(); defer { lock.unlock() }
        return reportText
    }
    func saveReport(_ text: String) {
        lock.lock(); reportText = text; lock.unlock()
    }
    func record(_ stage: ArenaStageMetrics.Stage, seconds: Double) {
        guard enabled else { return }
        lock.lock(); samples.record(stage, seconds: seconds); lock.unlock()
    }
    private var samples = ArenaStageMetrics()
    private let log = OSLog(subsystem: "ShiftReminder", category: "ArenaCPU")
    // Enable before opening the lobby, then relaunch to capture cold loading.
    private var storedEnabled = UserDefaults.standard.bool(forKey: "arena.performanceOverlay")

    func measure<T>(_ stage: ArenaStageMetrics.Stage, _ work: () throws -> T) rethrows -> T {
        guard enabled else { return try work() }
        let id = OSSignpostID(log: log)
        let start = ProcessInfo.processInfo.systemUptime
        os_signpost(.begin, log: log, name: "ArenaStage", signpostID: id, "stage=%d", stage.rawValue)
        defer {
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            os_signpost(.end, log: log, name: "ArenaStage", signpostID: id)
            lock.lock()
            samples.record(stage, seconds: elapsed)
            lock.unlock()
        }
        return try work()
    }

    func resetSession() {
        lock.lock(); samples.reset(); lock.unlock()
    }

    func snapshot() -> ArenaStageMetrics {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}
