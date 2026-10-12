import AVFoundation
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
}

/// 工作留痕：文件存在 App 的「文稿 › 工作留痕」里（「文件」App › 我的 iPhone › 值班提醒 能看到），
/// 索引存在同一个文件夹的「记录.json」。只在手机上，不上传。
@MainActor
final class WorkLogStore: ObservableObject {
    static let shared = WorkLogStore()

    @Published private(set) var entries: [WorkLogEntry] = []

    static var folder: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("工作留痕", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var indexURL: URL { folder.appendingPathComponent("记录.json") }

    private init() {
        if AppStore.isDemo {
            let now = Date()
            entries = [
                WorkLogEntry(date: now.addingTimeInterval(-1800), kind: .note, note: "08:30 交班：一号星数传正常，二号星遥测帧计数偶有跳变，已通知值班长。", shift: "遥测"),
                WorkLogEntry(date: now.addingTimeInterval(-90_000), kind: .audio, note: "现场情况口述", shift: "组A", duration: 74),
                WorkLogEntry(date: now.addingTimeInterval(-180_000), kind: .call, note: "和调度确认明早过境时间", shift: "组A", duration: 212),
            ]
            return
        }
        if let data = try? Data(contentsOf: Self.indexURL),
           let list = try? JSONDecoder().decode([WorkLogEntry].self, from: data) {
            entries = list.sorted { $0.date > $1.date }
        }
    }

    private func save() {
        guard !AppStore.isDemo, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: Self.indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
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
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let name = newFileName(.photo, ext: "jpg")
        guard (try? data.write(to: Self.folder.appendingPathComponent(name), options: .atomic)) != nil else { return nil }
        let entry = WorkLogEntry(date: Date(), kind: .photo, file: name, note: note, shift: todayShift)
        insert(entry)
        return entry
    }

    func addNote(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        insert(WorkLogEntry(date: Date(), kind: .note, note: t, shift: todayShift))
    }

    @discardableResult
    func addRecording(from temp: URL, duration: TimeInterval, note: String = "") -> WorkLogEntry? {
        let name = newFileName(.audio, ext: temp.pathExtension.isEmpty ? "m4a" : temp.pathExtension)
        guard (try? FileManager.default.moveItem(at: temp, to: Self.folder.appendingPathComponent(name))) != nil else { return nil }
        let entry = WorkLogEntry(date: Date(), kind: .audio, file: name, note: note, shift: todayShift, duration: duration)
        insert(entry)
        return entry
    }

    /// 导入文件（「备忘录」里的通话录音分享过来、或者从「文件」里选）。音频默认当作通话录音。
    @discardableResult
    func importFile(_ source: URL, kind: WorkLogEntry.Kind? = nil) -> WorkLogEntry? {
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
        return entry
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

    func count(on day: DayKey) -> Int {
        entries.filter { DayKey(date: $0.date, calendar: .app) == day }.count
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
        let duration = r.currentTime
        r.stop()
        cleanup()
        return duration >= 0.5 ? (url, duration) : nil
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        cleanup()
    }

    private func cleanup() {
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
