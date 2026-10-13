import AVFoundation
import LocalAuthentication
import Speech
import UIKit
import UniformTypeIdentifiers

/// 工作留痕的一条记录：照片、录音、通话录音、文字，或者导入的文件。
struct WorkLogEntry: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case photo, audio, call, note, file

        var title: String {
            switch self {
            case .photo: return "照片"
            case .audio: return "录音"
            case .call: return "通话录音"
            case .note: return "文字"
            case .file: return "文件"
            }
        }

        var symbol: String {
            switch self {
            case .photo: return "camera.fill"
            case .audio: return "waveform"
            case .call: return "phone.fill"
            case .note: return "text.alignleft"
            case .file: return "doc.fill"
            }
        }
    }

    var id = UUID()
    var date: Date
    var kind: Kind
    /// 「工作留痕」文件夹里的文件名；纯文字记录为 nil
    var file: String?
    var note: String
    /// 记录时当天的班次（「组A」「遥测」）
    var shift: String?
    /// 录音时长（秒）
    var duration: TimeInterval?
    /// 录音转出来的文字
    var transcript: String?

    var isAudio: Bool { kind == .audio || kind == .call }

    /// 搜索用
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [note, transcript ?? "", shift ?? "", kind.title, file ?? ""].contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

/// 工作留痕：文件存在 App 的「文稿 › 工作留痕」里（「文件」App › 我的 iPhone › 值班提醒 能看到），
/// 索引存在同一个文件夹的「记录.json」。只在手机上，不上传。
@MainActor
final class WorkLogStore: ObservableObject {
    static let shared = WorkLogStore()

    @Published private(set) var entries: [WorkLogEntry] = []
    /// 正在转文字的记录
    @Published private(set) var transcribing: Set<UUID> = []
    /// 加了面容 ID 锁后，这次打开 App 是否已经解锁（退到后台就重新锁上）
    @Published var unlocked = false

    /// 没加锁：放在「文稿」里，「文件」App 能看到；加了锁：放到「资料库」里，「文件」App 看不到
    private static var hidden: Bool { AppStore.shared.settings.workLogLock }

    private static func baseFolder(hidden: Bool) -> URL {
        let base = FileManager.default.urls(for: hidden ? .applicationSupportDirectory : .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("工作留痕", isDirectory: true)
    }

    static var folder: URL {
        let dir = baseFolder(hidden: hidden)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.complete])
        return dir
    }

    /// 开关面容 ID 锁时把整个文件夹搬过去
    func relocate(hidden: Bool) {
        let from = Self.baseFolder(hidden: !hidden), to = Self.baseFolder(hidden: hidden)
        let fm = FileManager.default
        guard fm.fileExists(atPath: from.path) else { return }
        try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: to.path) {
            try? fm.moveItem(at: from, to: to)
        } else {
            for name in (try? fm.contentsOfDirectory(atPath: from.path)) ?? [] {
                try? fm.moveItem(at: from.appendingPathComponent(name), to: to.appendingPathComponent(name))
            }
            try? fm.removeItem(at: from)
        }
        protectAll()
    }

    /// 文件都设成「锁屏后加密、解锁后才能读」
    private func protectAll() {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: Self.folder.path)) ?? [] {
            try? fm.setAttributes([.protectionKey: FileProtectionType.complete],
                                  ofItemAtPath: Self.folder.appendingPathComponent(name).path)
        }
    }

    /// 打开工作留痕前验证面容 ID / 触控 ID（没设置时用锁屏密码）
    func unlock() async -> Bool {
        if unlocked || !AppStore.shared.settings.workLogLock { return true }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            unlocked = true   // 手机没设密码：没法锁
            return true
        }
        let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "查看工作留痕")) ?? false
        unlocked = ok
        return ok
    }

    private static var indexURL: URL { folder.appendingPathComponent("记录.json") }

    private init() {
        if AppStore.launchDemo {   // 截图用的演示数据；「先看演示」时照常读自己的记录
            let now = Date()
            entries = [
                WorkLogEntry(date: now.addingTimeInterval(-1800), kind: .note, note: "08:30 交班：一号星数传正常，二号星遥测帧计数偶有跳变，已通知值班长。", shift: "遥测"),
                WorkLogEntry(date: now.addingTimeInterval(-90_000), kind: .audio, note: "现场情况口述", shift: "组A", duration: 74),
                WorkLogEntry(date: now.addingTimeInterval(-180_000), kind: .call, note: "和调度确认明早过境时间", shift: "组A", duration: 212),
            ]
            return
        }
        // 上次开关锁时没搬完（比如中途退出）：以设置为准再搬一次
        relocate(hidden: Self.hidden)
        load()
        protectAll()
    }

    /// 读记录时手机锁着（文件加密读不出来）：先不写，免得用空列表把原来的记录覆盖掉
    private var loadFailed = false

    private func load() {
        let url = Self.indexURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            entries = []
            loadFailed = false
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            loadFailed = true      // 多半是手机锁着，解锁后再读
            return
        }
        if let list = try? JSONDecoder().decode([WorkLogEntry].self, from: data) {
            entries = list.sorted { $0.date > $1.date }
        } else {
            // 文件坏了：留一份备份，从头开始
            try? FileManager.default.moveItem(at: url, to: url.deletingPathExtension().appendingPathExtension("bad-\(Int(Date().timeIntervalSince1970)).json"))
            entries = []
        }
        loadFailed = false
    }

    /// 打开 App 时调用：之前没读出来的再读一次
    func reloadIfNeeded() {
        if loadFailed { load() }
    }

    /// 能不能写：记录读出来了才写
    private var canWrite: Bool {
        reloadIfNeeded()
        return !loadFailed
    }

    /// 锁屏时写不进去（文件加密）：记下来，解锁后再写
    private var pendingSave = false
    private var unlockObserver: NSObjectProtocol?

    private func save() {
        guard !AppStore.launchDemo, !loadFailed, let data = try? JSONEncoder().encode(entries) else { return }
        do {
            try data.write(to: Self.indexURL, options: [.atomic, .completeFileProtection])
            pendingSave = false
        } catch {
            pendingSave = true
            guard unlockObserver == nil else { return }
            unlockObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    let store = WorkLogStore.shared
                    if let o = store.unlockObserver { NotificationCenter.default.removeObserver(o) }
                    store.unlockObserver = nil
                    if store.pendingSave { store.save() }
                }
            }
        }
    }

    func url(for entry: WorkLogEntry) -> URL? {
        entry.file.map { Self.folder.appendingPathComponent($0) }
    }

    /// 「20261012-083015-照片.jpg」：按时间命名，在「文件」App 里也好找
    private func newFileName(_ kind: WorkLogEntry.Kind, ext: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let base = "\(f.string(from: Date()))-\(kind.title)"
        var name = "\(base).\(ext)"
        var n = 2
        while FileManager.default.fileExists(atPath: Self.folder.appendingPathComponent(name).path) {
            name = "\(base)-\(n).\(ext)"
            n += 1
        }
        return name
    }

    private var todayShift: String? {
        let store = AppStore.shared
        return store.shift(on: .today).map { store.matcher.displayName($0) }
    }

    private func insert(_ entry: WorkLogEntry) {
        entries.insert(entry, at: 0)
        entries.sort { $0.date > $1.date }
        save()
    }

    @discardableResult
    func addPhoto(_ image: UIImage, note: String = "") -> WorkLogEntry? {
        guard canWrite, let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let name = newFileName(.photo, ext: "jpg")
        guard (try? data.write(to: Self.folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])) != nil else { return nil }
        let entry = WorkLogEntry(date: Date(), kind: .photo, file: name, note: note, shift: todayShift)
        insert(entry)
        return entry
    }

    @discardableResult
    func addNote(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, canWrite else { return false }
        insert(WorkLogEntry(date: Date(), kind: .note, note: t, shift: todayShift))
        return true
    }

    @discardableResult
    func addRecording(from temp: URL, duration: TimeInterval, note: String = "") -> WorkLogEntry? {
        guard canWrite else { return nil }
        let name = newFileName(.audio, ext: temp.pathExtension.isEmpty ? "m4a" : temp.pathExtension)
        let target = Self.folder.appendingPathComponent(name)
        guard (try? FileManager.default.moveItem(at: temp, to: target)) != nil else { return nil }
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: target.path)
        let entry = WorkLogEntry(date: Date(), kind: .audio, file: name, note: note, shift: todayShift, duration: duration)
        insert(entry)
        autoTranscribe(entry)
        return entry
    }

    /// 导入文件（「备忘录」里的通话录音分享过来、或者从「文件」里选）。音频默认当作通话录音。
    @discardableResult
    func importFile(_ source: URL, kind: WorkLogEntry.Kind? = nil) -> WorkLogEntry? {
        guard canWrite else { return nil }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let type = UTType(filenameExtension: source.pathExtension)
        let detected: WorkLogEntry.Kind = kind ?? {
            if type?.conforms(to: .audio) == true { return .call }
            if type?.conforms(to: .image) == true { return .photo }
            return .file
        }()
        let ext = source.pathExtension.isEmpty ? "dat" : source.pathExtension
        let name = newFileName(detected, ext: ext)
        let target = Self.folder.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: source, to: target)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: target.path)
        } catch {
            return nil
        }
        // 系统放在 Inbox 里的副本用完删掉
        if source.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: source) }
        var duration: TimeInterval?
        if detected == .call || detected == .audio, let player = try? AVAudioPlayer(contentsOf: target) {
            duration = player.duration
        }
        let original = source.deletingPathExtension().lastPathComponent
        let entry = WorkLogEntry(date: Date(), kind: detected, file: name,
                                 note: detected == .file || detected == .call ? original : "", shift: todayShift, duration: duration)
        insert(entry)
        autoTranscribe(entry)
        return entry
    }

    /// 手动改识别出的文字
    func updateTranscript(_ id: UUID, _ text: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries[i].transcript != text else { return }
        entries[i].transcript = text
        save()
    }

    /// 只改说明（详情页关掉时保存；转文字可能已经在后台更新了这条）
    func updateNote(_ id: UUID, _ note: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries[i].note != note else { return }
        entries[i].note = note
        save()
    }

    func update(_ entry: WorkLogEntry) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[i] = entry
        save()
    }

    func delete(_ entry: WorkLogEntry) {
        if let url = url(for: entry) { try? FileManager.default.removeItem(at: url) }
        entries.removeAll { $0.id == entry.id }
        save()
    }

    // MARK: 录音转文字

    private func autoTranscribe(_ entry: WorkLogEntry) {
        guard entry.isAudio, AppStore.shared.settings.workLogAutoTranscribe else { return }
        Task { _ = await transcribe(entry) }
    }

    /// 转文字，结果存进这条记录；失败返回原因
    /// online：这一次用联网识别（更准，录音会发给苹果）
    func transcribe(_ entry: WorkLogEntry, online: Bool = false) async -> String? {
        guard entry.isAudio, let url = url(for: entry), !transcribing.contains(entry.id) else { return nil }
        transcribing.insert(entry.id)
        defer { transcribing.remove(entry.id) }
        let onDevice = online ? false : AppStore.shared.settings.speechOnDeviceOnly
        switch await Transcriber.transcribe(url, onDeviceOnly: onDevice, vocabulary: AppStore.shared.speechVocabulary) {
        case .success(let text):
            guard var current = entries.first(where: { $0.id == entry.id }) else { return nil }
            current.transcript = text.isEmpty ? "（没听出文字）" : text
            update(current)
            return nil
        case .failure(let error):
            return error.message
        }
    }

    func count(on day: DayKey) -> Int {
        entries.filter { DayKey(date: $0.date, calendar: .app) == day }.count
    }

    /// 交接班小结草稿：当天的班、清单做完没做完、留痕按时间列出来，复制给接班的人
    /// 加了面容 ID 锁又没解锁时，只写条数不写内容
    @MainActor
    func handoverSummary(for day: DayKey, store: AppStore) -> String {
        var lines = ["【交接班】\(day.month)月\(day.day)日（\(day.weekdayText)）"
                     + (store.shift(on: day).map { " " + store.matcher.displayName($0) } ?? "")]
        let groups = store.notes(for: store.shift(on: day)).map { (group: $0.group, items: TaskList.items(from: $0.note)) }
            .filter { $0.items.count > 1 }
        var done: [String] = [], todo: [String] = []
        for g in groups {
            for (i, item) in g.items.enumerated() {
                if store.isTaskDone(day, g.group, TaskChecklistCard.key(i, item)) { done.append(item) } else { todo.append(item) }
            }
        }
        if !done.isEmpty { lines.append("已完成：" + done.joined(separator: "；")) }
        if !todo.isEmpty { lines.append("未完成：" + todo.joined(separator: "；")) }
        let today = entries.filter { DayKey(date: $0.date, calendar: .app) == day }.sorted { $0.date < $1.date }
        if !today.isEmpty {
            if store.settings.workLogLock && !unlocked {
                lines.append("留痕 \(today.count) 条（已加锁，解锁后可带上内容）")
            } else {
                lines.append("情况记录：")
                for e in today {
                    let time = e.date.formatted(date: .omitted, time: .shortened)
                    var text = [e.note, e.transcript ?? ""].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .first { !$0.isEmpty } ?? ""
                    if text.count > 80 { text = String(text.prefix(80)) + "…" }
                    lines.append("· \(time) \(e.kind.title)" + (text.isEmpty ? "" : "：\(text)"))
                }
            }
        }
        if groups.isEmpty && today.isEmpty { lines.append("今天没有清单和留痕记录。") }
        lines.append("其他需要交代的：")
        return lines.joined(separator: "\n")
    }
}

/// App 里的录音机（打电话时 iPhone 不让别的 App 录音，通话请用系统自带的通话录音）
@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    /// 0…1 音量，画波形用
    @Published private(set) var level: Float = 0
    @Published var error: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var url: URL?
    private var interruptionObserver: NSObjectProtocol?
    /// 被来电、闹钟打断时：已经录到的部分交给这里保存
    var onInterrupted: ((URL, TimeInterval) -> Void)?

    func start() async {
        error = nil
        let granted = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) }
        }
        guard granted else {
            error = "没有麦克风权限：到 iPhone「设置 › 值班提醒」里打开麦克风。"
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            self.error = "现在不能录音（正在通话时 iPhone 不允许别的 App 录音）。"
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            guard r.record() else { throw NSError(domain: "rec", code: 1) }
            recorder = r
            self.url = url
            isRecording = true
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            // 来电、闹钟会打断录音：停下来，把录到的部分存好
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
                Task { @MainActor in
                    guard let self, let result = self.stop() else { return }
                    self.error = "录音被来电或闹钟打断，已保存前面的部分。"
                    self.onInterrupted?(result.url, result.duration)
                }
            }
        } catch {
            self.error = "录音没能开始，请再试一次。"
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func tick() {
        guard let r = recorder, r.isRecording else { return }
        elapsed = r.currentTime
        r.updateMeters()
        // -60 dB…0 dB 换成 0…1
        level = max(0, min(1, (r.averagePower(forChannel: 0) + 60) / 60))
    }

    /// 停止并返回录好的临时文件和时长
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard let r = recorder, let url else { return nil }
        let current = r.currentTime
        r.stop()
        cleanup()
        // 停下以后从文件里读时长（被打断时 currentTime 可能是 0）
        let duration = max(current, (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0)
        guard duration >= 0.5 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return (url, duration)
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        cleanup()
    }

    private func cleanup() {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        timer?.invalidate()
        timer = nil
        recorder = nil
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// 播放一条录音
@MainActor
final class AudioPlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(_ url: URL) {
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        duration = player?.duration ?? 0
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            stopTimer()
            isPlaying = false
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
            isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.progress = self?.player?.currentTime ?? 0 }
            }
        }
    }

    func seek(_ time: TimeInterval) {
        player?.currentTime = time
        progress = time
    }

    func stop() {
        player?.stop()
        stopTimer()
        isPlaying = false
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopTimer()
            self.isPlaying = false
            self.progress = 0
        }
    }
}


/// 用 iPhone 自带的语音识别把录音转成文字（默认只在手机上识别，录音不出手机）
enum Transcriber {
    struct Failure: Error {
        let message: String
    }

    static func authorize() async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
    }

    /// 把录音切成不到一分钟一段（联网识别一次最多一分钟；分段离线识别也更准）
    static func chunks(of url: URL, seconds: Double = 50) -> [URL] {
        guard let file = try? AVAudioFile(forReading: url) else { return [url] }
        let format = file.processingFormat
        let perChunk = AVAudioFramePosition(format.sampleRate * seconds)
        guard file.length > perChunk + AVAudioFramePosition(format.sampleRate * 5) else { return [url] }
        var urls: [URL] = []
        while file.framePosition < file.length {
            let count = AVAudioFrameCount(min(perChunk, file.length - file.framePosition))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
                  (try? file.read(into: buffer, frameCount: count)) != nil else { break }
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("chunk-\(UUID().uuidString).caf")
            guard let writer = try? AVAudioFile(forWriting: out, settings: format.settings,
                                                commonFormat: format.commonFormat, interleaved: format.isInterleaved),
                  (try? writer.write(from: buffer)) != nil else { break }
            urls.append(out)
        }
        return urls.isEmpty ? [url] : urls
    }

    /// onDeviceOnly：只在手机上识别（不联网，准确度差一些）；false 时用苹果的联网识别（更准，录音会发给苹果）。
    /// vocabulary：常用词（同事名字、遥测、组A、星名……），识别时优先往这些词上靠
    static func transcribe(_ url: URL, onDeviceOnly: Bool, vocabulary: [String] = []) async -> Result<String, Failure> {
        guard await authorize() else {
            return .failure(Failure(message: "没有语音识别权限：到 iPhone「设置 › 值班提醒」里打开「语音识别」。"))
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), recognizer.isAvailable else {
            return .failure(Failure(message: "这台手机现在用不了中文语音识别（联网识别要连上网）。"))
        }
        if onDeviceOnly && !recognizer.supportsOnDeviceRecognition {
            return .failure(Failure(message: "这台手机不支持离线中文识别。点「联网识别（更准）」试试（录音会发给苹果识别）。"))
        }
        let parts = chunks(of: url)
        defer { for part in parts where part != url { try? FileManager.default.removeItem(at: part) } }
        var texts: [String] = []
        for part in parts {
            switch await recognize(part, recognizer: recognizer, onDevice: onDeviceOnly, vocabulary: vocabulary) {
            case .success(let text): if !text.isEmpty { texts.append(text) }
            case .failure(let f): return .failure(f)
            }
        }
        return .success(texts.joined(separator: "\n"))
    }

    private static func recognize(_ url: URL, recognizer: SFSpeechRecognizer, onDevice: Bool,
                                  vocabulary: [String]) async -> Result<String, Failure> {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = onDevice
        request.contextualStrings = Array(vocabulary.prefix(100))
        final class Once: @unchecked Sendable {
            private let lock = NSLock()
            private var done = false
            /// 第一次调用返回 true
            func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
        }
        let once = Once()
        return await withCheckedContinuation { (c: CheckedContinuation<Result<String, Failure>, Never>) in
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    guard once.claim() else { return }
                    c.resume(returning: .success(result.bestTranscription.formattedString))
                } else if let error {
                    guard once.claim() else { return }
                    let nsError = error as NSError
                    // 1110：没听到说话
                    if nsError.code == 1110 {
                        c.resume(returning: .success(""))
                    } else {
                        c.resume(returning: .failure(Failure(message: "转文字失败：\(error.localizedDescription)")))
                    }
                }
            }
        }
    }
}
