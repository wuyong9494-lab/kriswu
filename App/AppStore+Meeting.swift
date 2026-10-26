import Foundation

/// 周会文档：导入、每周一自动读，跟进各组提的问题有没有解决
@MainActor
extension AppStore {
    /// 导入一份周会文档的文字（App 里打开文档读的、剪贴板、粘贴的）。返回给人看的结果
    @discardableResult
    func importMeeting(text: String, source: String) -> String {
        meetingPageText = String(text.prefix(6000))
        let sections = MeetingNotes.parse(text)
        guard !sections.isEmpty else {
            let message = "没认出各组的内容：文档里要有「组A」「研发组」这样的组名（\(source)）"
            settings.meetingMessage = message
            return message
        }
        var s = settings
        let week = MeetingTracker.monday(of: .today)
        let print = MeetingTracker.fingerprint(text)
        // 文档还是上次那一版（周一还没更新）：不当成新的一周，免得把问题都算成「没再提」
        guard print != s.meetingFingerprint else {
            s.meetingMessage = "文档还是上次那一版，没有新内容（\(source)，\(Date().formatted(date: .omitted, time: .shortened))）"
            settings = s
            return "文档还没更新"
        }
        let before = s.meetingIssues
        s.meetingIssues = MeetingTracker.update(before, with: sections, week: week)
        s.meetingFingerprint = print
        s.meetingLastImport = Date()
        s.meetingWeek = week
        let summary = Self.meetingSummary(before: before, after: s.meetingIssues, week: week)
        let count = sections.reduce(0) { $0 + $1.items.count }
        s.meetingMessage = "\(source)读到 \(sections.count) 个组、\(count) 条（\(Date().formatted(date: .abbreviated, time: .shortened))）：\(summary)"
        settings = s
        return summary
    }

    /// 「还有 5 个没解决，新提 2 个，解决了 1 个，1 个这周没再提」
    nonisolated static func meetingSummary(before: [MeetingIssue], after: [MeetingIssue], week: DayKey) -> String {
        let was = Dictionary(before.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
        let open = after.filter { $0.status == .open }.count
        let new = after.filter { $0.firstWeek == week && was[$0.id] == nil && $0.status == .open }.count
        let solved = after.filter { $0.resolvedWeek == week && was[$0.id] != .resolved }.count
        let quiet = after.filter { $0.status == .quiet && was[$0.id] == .open }.count
        var parts = ["还有 \(open) 个没解决"]
        if new > 0 { parts.append("新提 \(new) 个") }
        if solved > 0 { parts.append("解决了 \(solved) 个") }
        if quiet > 0 { parts.append("\(quiet) 个这周没再提") }
        return parts.joined(separator: "，")
    }

    /// 打开 App 时：这周还没读到新一版的周会文档，就在后台打开文档读一次（3 小时内最多试一次）
    func refreshMeetingIfDue() async {
        guard !Self.isDemo else { return }
        let link = settings.meetingDocURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: link), url.scheme?.hasPrefix("http") == true else { return }
        let week = MeetingTracker.monday(of: .today)
        if let done = settings.meetingWeek, done >= week { return }
        if let last = settings.meetingLastAttempt, Date().timeIntervalSince(last) < 3 * 3600 { return }
        settings.meetingLastAttempt = Date()
        guard let text = await DocTextLoader.text(from: url), !text.isEmpty else {
            settings.meetingMessage = "自动读周会文档没读到内容：在「周会问题」里点「打开文档」看看是不是要先登录"
            return
        }
        let result = importMeeting(text: text, source: "自动")
        // 读到了这周的新一版：通知一下
        if settings.meetingWeek == week, settings.meetingFingerprint == MeetingTracker.fingerprint(text) {
            await NotificationService.notifyNow(id: "meeting-\(week)", title: "📝 周会文档更新了", body: result, route: "meeting")
        }
    }

    /// 自己改一条问题的状态（标成解决了、还没解决）
    func setMeetingIssue(_ id: String, status: MeetingIssue.Status) {
        guard let i = settings.meetingIssues.firstIndex(where: { $0.id == id }) else { return }
        var s = settings
        s.meetingIssues[i].status = status
        s.meetingIssues[i].manual = true
        s.meetingIssues[i].resolvedWeek = status == .resolved ? MeetingTracker.monday(of: .today) : nil
        settings = s
    }

    func deleteMeetingIssue(_ id: String) {
        settings.meetingIssues.removeAll { $0.id == id }
    }
}
