import Foundation
import MetricKit

/// 闪退、卡顿、CPU 占用过高、写盘过多、启动太慢：系统（MetricKit）记下来，下次打开 App 时交给我们。
/// 存最近 30 条的摘要（records.json），原始记录（含调用栈）存成文件，「自检与诊断」里能看、能分享给帮你排查的人。
/// 只在这台手机上，不会自己发出去
final class CrashLog: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashLog()
    static let keep = 30

    /// 一条记录（摘要）
    struct Entry: Codable, Equatable, Identifiable {
        var id: String
        var date: Date
        /// 闪退 / 卡顿 / CPU 过高 / 写盘过多 / 启动太慢
        var kind: String
        var summary: String
        /// 出事时的 App 版本（build 号）
        var build: String
    }

    /// 原始记录存在这里（文件名是 id.json）
    static let folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Diagnostics", isDirectory: true)

    /// 同一份原始记录里的几条（id 是「文件名#序号」）共用一个文件
    static func fileURL(for entry: Entry) -> URL {
        folder.appendingPathComponent(String(entry.id.split(separator: "#")[0]) + ".json")
    }

    /// 启动时登记：之后系统有新的记录就交过来（一般在第二天、或闪退后下次打开时）
    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var entries: [Entry] = []
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        for payload in payloads {
            let found = Self.entries(in: payload)
            guard !found.isEmpty else { continue }
            try? payload.jsonRepresentation().write(to: Self.fileURL(for: found[0]), options: .atomic)
            entries += found.enumerated().map { i, e in
                var e = e
                if i > 0 { e.id = found[0].id + "#\(i)" }
                return e
            }
        }
        guard !entries.isEmpty else { return }
        Task { @MainActor [entries] in AppStore.shared.addCrashEntries(entries) }
    }

    /// 一份系统记录里的各条（一份里可能同时有闪退、卡顿）
    private static func entries(in payload: MXDiagnosticPayload) -> [Entry] {
        let id = "\(Int(payload.timeStampEnd.timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
        var list: [Entry] = []
        func add(_ kind: String, _ summary: String, _ meta: MXMetaData) {
            list.append(Entry(id: id, date: payload.timeStampEnd, kind: kind, summary: summary, build: meta.applicationBuildVersion))
        }
        for d in payload.crashDiagnostics ?? [] { add("闪退", crashSummary(d), d.metaData) }
        for d in payload.hangDiagnostics ?? [] {
            add("卡顿", "界面卡住 \(seconds(d.hangDuration)) 秒", d.metaData)
        }
        for d in payload.cpuExceptionDiagnostics ?? [] {
            add("CPU 过高", "后台占用 CPU \(seconds(d.totalCPUTime)) 秒（统计了 \(seconds(d.totalSampledTime)) 秒）", d.metaData)
        }
        for d in payload.diskWriteExceptionDiagnostics ?? [] {
            let mb = d.totalWritesCaused.converted(to: .megabytes).value
            add("写盘过多", "一天写了约 \(Int(mb)) MB", d.metaData)
        }
        for d in payload.appLaunchDiagnostics ?? [] {
            add("启动太慢", "打开用了 \(seconds(d.launchDuration)) 秒", d.metaData)
        }
        return list
    }

    private static func seconds(_ m: Measurement<UnitDuration>) -> String {
        m.converted(to: .seconds).value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// 「被系统强制结束：卡太久（看门狗）」「访问了无效内存（SIGSEGV）」这样的一句话
    private static func crashSummary(_ d: MXCrashDiagnostic) -> String {
        var parts: [String] = []
        if let reason = d.terminationReason, !reason.isEmpty {
            if reason.lowercased().contains("0x8badf00d") {
                parts.append("被系统强制结束：卡太久（看门狗）")
            } else if reason.lowercased().contains("0xdead10cc") {
                parts.append("被系统强制结束：退到后台时还占着文件")
            } else {
                parts.append("被系统结束：" + reason)
            }
        }
        if let signal = d.signal?.int32Value {
            let names: [Int32: String] = [4: "非法指令（SIGILL）", 5: "代码里的断言没过（SIGTRAP）", 6: "主动中止（SIGABRT）",
                                          9: "被强制结束（SIGKILL）", 10: "总线错误（SIGBUS）", 11: "访问了无效内存（SIGSEGV）"]
            parts.append(names[signal] ?? "信号 \(signal)")
        }
        if #available(iOS 17.0, *), let reason = d.exceptionReason {
            parts.append(reason.composedMessage)
        }
        return parts.isEmpty ? "闪退" : parts.joined(separator: "；")
    }
}

@MainActor
extension AppStore {
    /// 收到新的闪退、卡顿记录：新的在前，最多留 30 条；不再列着的原始文件删掉
    func addCrashEntries(_ entries: [CrashLog.Entry]) {
        let known = Set(records.crashes.map(\.id))
        let merged = (entries.filter { !known.contains($0.id) } + records.crashes)
            .sorted { $0.date > $1.date }
            .prefix(CrashLog.keep)
        records.crashes = Array(merged)
        let files = Set(records.crashes.map { CrashLog.fileURL(for: $0).lastPathComponent })
        let all = (try? FileManager.default.contentsOfDirectory(atPath: CrashLog.folder.path)) ?? []
        for name in all where !files.contains(name) {
            try? FileManager.default.removeItem(at: CrashLog.folder.appendingPathComponent(name))
        }
    }

    func clearCrashEntries() {
        records.crashes = []
        try? FileManager.default.removeItem(at: CrashLog.folder)
    }
}
