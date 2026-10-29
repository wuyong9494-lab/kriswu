import Foundation
import os

/// Lock protects diagnostics only; SceneKit work stays on its existing thread.
final class ArenaDiagnostics: @unchecked Sendable {
    static let shared = ArenaDiagnostics()
    private let lock = NSLock()
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

    func snapshot() -> ArenaStageMetrics {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}
