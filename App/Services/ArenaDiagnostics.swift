import Foundation
import os
import UIKit

/// Lock protects diagnostics only; SceneKit work stays on its existing thread.
final class ArenaDiagnostics: @unchecked Sendable {
    static let shared = ArenaDiagnostics()
    enum Variant: String, CaseIterable {
        case baseline, noNumbers, noParticles, noCharacterOutlines, halfAnimation
        var title: String {
            switch self {
            case .baseline: return "基准（正常显示）"
            case .noNumbers: return "仅关闭飘字"
            case .noParticles: return "仅关闭粒子"
            case .noCharacterOutlines: return "仅关闭人物描边"
            case .halfAnimation: return "仅隔帧采样骨骼"
            }
        }
    }
    let variant = Variant(rawValue: UserDefaults.standard.string(forKey: "arena.diagnosticVariant") ?? "") ?? .baseline
    private let lock = NSLock()
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
    let enabled = UserDefaults.standard.bool(forKey: "arena.performanceOverlay")

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
