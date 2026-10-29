import Foundation
import os
import UIKit

enum ArenaDiagnosticVariant: String, CaseIterable, Identifiable {
    case baseline, noNumbers, noParticles, noOutlines, halfAnimation
    var id: String { rawValue }
    var title: String {
        switch self {
        case .baseline: return "完整效果（基线）"
        case .noNumbers: return "仅关闭伤害/回血数字"
        case .noParticles: return "仅关闭粒子（保留攻击与危险范围）"
        case .noOutlines: return "仅关闭人物描边"
        case .halfAnimation: return "仅将骨骼采样降至 30 Hz"
        }
    }
    static var selected: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: "arena.diagnosticVariant") ?? "") ?? .baseline
    }
}

/// Lock protects diagnostics only; SceneKit work stays on its existing thread.
final class ArenaDiagnostics: @unchecked Sendable {
    static let shared = ArenaDiagnostics()
    private let lock = NSLock()
    private var samples = ArenaStageMetrics()
    private var session = ArenaSessionMetrics()
    private var rolling: ArenaFrameMetrics.Report?
    private var context = "尚未进入对局"
    private var sceneDescription = ""
    private var counts = [String: Int]()
    private var peaks = [String: Int]()
    private var counters = [String: Int]()
    private var thermal = "未采样"
    private var worstThermal = 0
    private let log = OSLog(subsystem: "ShiftReminder", category: "ArenaCPU")
    // Enable before opening the lobby, then relaunch to capture cold loading.
    private var active = UserDefaults.standard.bool(forKey: "arena.performanceOverlay")
    var enabled: Bool { lock.lock(); defer { lock.unlock() }; return active }
    func setEnabled(_ value: Bool) { lock.lock(); active = value; lock.unlock() }

    func beginMatch(_ description: String) {
        lock.lock()
        session = ArenaSessionMetrics()
        rolling = nil
        context = description
        counts.removeAll(keepingCapacity: true)
        peaks.removeAll(keepingCapacity: true)
        worstThermal = 0
        lock.unlock()
    }

    func record(_ stage: ArenaStageMetrics.Stage, seconds: Double) {
        guard enabled else { return }
        lock.lock(); samples.record(stage, seconds: seconds); lock.unlock()
    }

    func count(_ name: String, by amount: Int = 1) {
        guard enabled else { return }
        lock.lock(); counters[name, default: 0] += amount; lock.unlock()
    }

    func frame(interval: Double, work: Double, rolling: ArenaFrameMetrics.Report?) {
        lock.lock()
        session.record(interval: interval, work: work)
        self.rolling = rolling
        lock.unlock()
    }

    func scene(_ description: String, counts current: [String: Int]) {
        let state = ProcessInfo.processInfo.thermalState
        lock.lock()
        sceneDescription = description
        counts = current
        for (key, value) in current { peaks[key] = max(peaks[key] ?? 0, value) }
        worstThermal = max(worstThermal, state.rawValue)
        thermal = Self.thermalName(state.rawValue)
        lock.unlock()
    }

    private static func thermalName(_ value: Int) -> String {
        switch value { case 0: return "nominal"; case 1: return "fair"; case 2: return "serious"; case 3: return "critical"; default: return "unknown" }
    }

    @MainActor func report() -> String {
        lock.lock()
        let history = session, stages = samples, recent = rolling
        let label = context, scene = sceneDescription, live = counts, peak = peaks, totals = counters
        let heat = thermal, worst = worstThermal
        lock.unlock()
        var system = utsname()
        uname(&system)
        let hardware = withUnsafeBytes(of: system.machine) {
            String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self)
        }
        let info = Bundle.main.infoDictionary ?? [:]
        #if targetEnvironment(simulator)
        let source = "模拟器；真机性能未验证"
        #else
        let source = "真机采样；仅代表此设备/此运行"
        #endif
        var lines = ["勇者乱斗性能报告 v1", "来源：\(source)",
                     "版本：\(info["CFBundleShortVersionString"] ?? "未知") (\(info["CFBundleVersion"] ?? "未知"))",
                     "提交：\(info["ArenaCommit"] ?? "未注入")",
                     "设备：\(hardware) / \(UIDevice.current.model)；系统：\(UIDevice.current.systemVersion)",
                     "场景：\(label)", scene,
                     String(format: "本局有效采样 %.2f 秒 / %d 次；后台与恢复首帧不计", history.duration, history.count),
                     "热状态：\(heat)；本局最高：\(Self.thermalName(worst))",
                     "GPU 时间：未测；实际呈现帧率：未测；功耗：未测"]
        if history.count > 0 {
            lines += [String(format: "回调频率 %.2f Hz；平均间隔 %.2f ms；最大间隔 %.2f ms", Double(history.count) / history.duration, history.duration * 1000 / Double(history.count), history.maximum * 1000),
                      "全局间隔 P50/P95/P99：\(history.percentileMilliseconds(0.5) ?? 0)/\(history.percentileMilliseconds(0.95) ?? 0)/\(history.percentileMilliseconds(0.99) ?? 0) ms（1ms 向上分桶；1000ms 桶含更长停顿）",
                      "慢回调 >34.333ms：\(history.slowCount)/\(history.count)；超 60Hz 预算 >17.667ms：\(history.overBudgetCount)/\(history.count)",
                      String(format: "同步回调 CPU 平均/峰值 %.3f/%.3f ms；不覆盖 UIKit/SceneKit 渲染线程、系统调度、GPU", history.callbackWork * 1000 / Double(history.count), history.peakCallbackWork * 1000)]
        }
        if let recent {
            lines.append(String(format: "最近 %d 次回调：%.2f Hz / P95 %.2f ms / 慢回调 %d；窗口按样本数，不是固定秒数", recent.samples, recent.fps, recent.p95Milliseconds, recent.slowFrames))
        }
        lines.append("CPU 阶段：自启动/开启诊断累计，次数 / 平均ms / 峰值ms。阶段嵌套，禁止求和。")
        let names = ["模型解析", "核心模拟", "AI", "骨骼采样与写入", "场景同步（含下列子项）", "建场景（含加载）", "角色移动/碰撞/状态", "投射物推进/碰撞/伤害", "角色节点与头顶 UI（含骨骼）", "投射物节点", "战斗事件反馈", "数字文字贴图", "飘字创建（含文字）", "音效播放（含可能加载）", "音效首次加载", "HUD 更新"]
        for stage in ArenaStageMetrics.Stage.allCases {
            let sample = stages[stage]
            lines.append(String(format: "%@: %d / %.3f / %.3f", names[stage.rawValue], sample.count, sample.meanMilliseconds, sample.peakMilliseconds))
        }
        lines.append("活跃数量（当前/本局观测峰值；每秒采样，可能漏过短暂峰值）：")
        for key in live.keys.sorted() { lines.append("\(key)：\(live[key] ?? 0)/\(peak[key] ?? 0)") }
        lines.append("资源创建计数（自启动/开启诊断累计）：")
        for key in totals.keys.sorted() { lines.append("\(key)：\(totals[key] ?? 0)") }
        lines.append("比较要求：同设备/温度/版本/种子/模拟步数，仅改一个诊断选项；不能由上述计时推断 GPU 瓶颈。")
        return lines.joined(separator: "\n")
    }

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
