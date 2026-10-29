import Foundation
import UIKit
import Darwin
import Combine

enum ArenaDiagnosticScenario: String, CaseIterable {
    case empty, soloWalk, crowdWalk, combat
    var title: String {
        switch self {
        case .empty: return "静止空场"
        case .soloWalk: return "单人走路"
        case .crowdWalk: return "多人无攻击"
        case .combat: return "多人混战"
        }
    }
}

/// Bounded capture driven by the existing battle display link. No timer or new render driver.
@MainActor
final class ArenaPerfRecorder: ObservableObject {
    static let shared = ArenaPerfRecorder()
    @Published private(set) var finishedCase = false
    @Published private(set) var progress = ""
    private(set) var activeScenario: ArenaDiagnosticScenario?
    private var variant: ArenaDiagnostics.Variant = .baseline
    private var elapsed = 0.0
    private var duration = 30.0
    private var nextStatus = 0.0
    private var residentMB = -1.0
    private var uiEvaluations = 0
    private var frameRows: [SIMD16<Double>] = []
    private var results: [[String: Any]] = []
    private var interruption: String?
    private var startDate = Date()
    private var previousVariant: ArenaDiagnostics.Variant = .baseline
    private var previousEnabled = false

    static var identity: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "v\(info["CFBundleShortVersionString"] ?? "?") Build \(info["CFBundleVersion"] ?? "?") · \(info["ArenaCommitSHA"] ?? "提交未注入")"
    }
    private static var device: String {
        var info = utsname(); uname(&info)
        let capacity = MemoryLayout.size(ofValue: info.machine)
        let model = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"].map { "模拟器 \($0)" } ?? "真机 \(model)"
    }
    func beginSuite(variant: ArenaDiagnostics.Variant, seconds: Double = 30) {
        previousVariant = ArenaDiagnostics.shared.variant
        previousEnabled = ArenaDiagnostics.shared.enabled
        self.variant = variant
        duration = min(max(seconds, 10), 60)
        results.removeAll(keepingCapacity: true)
        interruption = nil
        startDate = Date()
        ArenaDiagnostics.shared.configureCapture(variant)
    }
    func beginCase(_ scenario: ArenaDiagnosticScenario) {
        activeScenario = scenario
        elapsed = 0; nextStatus = 0; uiEvaluations = 0
        frameRows.removeAll(keepingCapacity: true)
        frameRows.reserveCapacity(Int(duration * 120))
        finishedCase = false
        progress = scenario.title + " · 预热3秒"
        ArenaDiagnostics.shared.resetSession()
    }
    func noteUIEvaluation() { if activeScenario != nil { uiEvaluations += 1 } }

    func record(controller: ArenaController, interval: Double, simulation: Double, scene: Double,
                battleDrivers: Int, lobbyDrivers: Int) {
        guard let scenario = activeScenario, controller.diagnosticScenario == scenario,
              interval > 0, interval.isFinite, !finishedCase else { return }
        elapsed += interval
        if elapsed >= nextStatus {
            nextStatus = elapsed + 1
            residentMB = Self.residentMemoryMB()
            progress = "\(scenario.title) · \(max(0, Int(elapsed - 3)))/\(Int(duration))秒"
        }
        guard elapsed >= 3 else { return }
        if frameRows.count < 20_000 {
            frameRows.append(SIMD16(elapsed - 3, interval * 1000, simulation * 1000, scene * 1000,
                residentMB, Double(ProcessInfo.processInfo.thermalState.rawValue), Double(battleDrivers),
                Double(lobbyDrivers), Double(uiEvaluations), Double(scenario == .empty ? 0 : controller.game.fighters.reduce(0) { $0 + ($1.alive ? 1 : 0) }),
                Double(controller.game.projectiles.count), 0, 0, 0, 0, 0))
        } else { interruption = "帧记录达到20000条上限" }
        if elapsed >= duration + 3 || interruption != nil { finishCase() }
    }
    private func finishCase() {
        guard let scenario = activeScenario else { return }
        let stages = ArenaDiagnostics.shared.snapshot()
        let timings = frameRows.map { $0[1] }.sorted()
        let sample: [String: Any] = [
            "scenario": scenario.rawValue, "title": scenario.title,
            "active_duration_seconds": max(0, elapsed - 3), "frames": frameRows.map { row in (0..<11).map { row[$0] } },
            "slow_over_34_333_ms": timings.filter { $0 > 34.333333 }.count,
            "over_18_333_ms": timings.filter { $0 > 18.333333 }.count,
            "p95_callback_ms": timings.isEmpty ? 0 : timings[max(0, Int(ceil(Double(timings.count) * 0.95)) - 1)],
            "stage_scope": "case including 3-second warmup and scene construction; stages overlap",
            "cpu_stages": ArenaStageMetrics.Stage.allCases.map { stage -> [String: Any] in
                let value = stages[stage]
                return ["name": String(describing: stage), "count": value.count,
                        "mean_ms": value.meanMilliseconds, "peak_ms": value.peakMilliseconds]
            }
        ]
        results.append(sample)
        activeScenario = nil
        finishedCase = true
    }
    func interrupt(_ reason: String) {
        interruption = reason
        finishCase()
    }
    func stop() {
        activeScenario = nil
        ArenaDiagnostics.shared.configureCapture(previousVariant, enabled: previousEnabled)
    }
    func export() throws -> URL {
        let metadata: [String: Any] = [
            "schema": 1, "identity": Self.identity, "device": Self.device,
            "system": UIDevice.current.systemName + " " + UIDevice.current.systemVersion,
            "started_utc": ISO8601DateFormatter().string(from: startDate),
            "variant": variant.rawValue, "seed": 170017, "map": "canyon", "camera": "fixed center, perspective, offset 0/16/12.5",
            "map_art": UserDefaults.standard.bool(forKey: "arena.purpleSample") ? "purple" : "legacy",
            "seconds_per_case": duration, "warmup_seconds_per_case": 3,
            "audio_theme_sample": UserDefaults.standard.bool(forKey: "arena.themeAudio"),
            "audio_loaded_music_files": ArenaSound.shared.loadedMusicFiles,
            "audio_master_muted": UserDefaults.standard.bool(forKey: ArenaSound.muteKey),
            "complete": interruption == nil && results.count == 4, "interruption": interruption ?? "none",
            "measurement": "CADisplayLink intervals and main-thread CPU, not presented FPS; no GPU or renderer-thread timing",
            "gpu_ms": "unmeasured", "presented_fps": "unmeasured", "physical_footprint": "unmeasured",
            "memory": "RSS MB sampled once per active second; -1 means unavailable",
            "cache_state": "warm assets may be shared across cases; not a cold-start benchmark",
            "combat_fixture": "respawns rejoin fixed center positions to sustain combat; normal game damage and collisions retained",
            "frame_columns": ["active_seconds", "callback_ms", "controller_cpu_ms", "scene_cpu_ms", "rss_mb", "thermal_0_nominal_1_fair_2_serious_3_critical", "battle_display_links", "lobby_display_links", "match_body_evaluations", "alive_characters", "projectiles"],
            "results": results
        ]
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ArenaDiagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("arena-\(Int(startDate.timeIntervalSince1970)).json")
        try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]).write(to: file, options: .atomic)
        return file
    }
    private static func residentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
    }
}
