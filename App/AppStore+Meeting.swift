import Foundation
import UIKit

/// 周会文档：导入、每周一自动读，跟进各组提的问题有没有解决
@MainActor
extension AppStore {
    /// 导入一份周会文档的文字（App 里打开文档读的、剪贴板、粘贴的）。返回给人看的结果
    @discardableResult
    func importMeeting(text: String, source: String) -> String {
        meetingPageText = String(text.prefix(6000))
        return applyMeeting(MeetingNotes.parse(text), fingerprintOf: text, source: source)
    }

    /// 从剪贴板导入：在金山 / 腾讯文档里选中表格复制。剪贴板里有网页表格（HTML）就按它读，一格里的换行、合并的「分组」都保得住
    func importMeetingFromClipboard() -> String {
        let board = UIPasteboard.general
        if let data = board.data(forPasteboardType: "public.html"),
           let html = String(data: data, encoding: .utf8) ?? SyncService.decode(data) {
            let rows = MeetingTable.htmlRows(html)
            if let sections = MeetingTable.sections(rows), !sections.isEmpty {
                let text = rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
                meetingPageText = String(text.prefix(6000))
                return applyMeeting(sections, fingerprintOf: text, source: "剪贴板")
            }
        }
        guard let text = board.string, !text.isEmpty else {
            let message = "剪贴板里没有文字：在金山文档里选中表格的格子，点「复制」再回来"
            settings.meetingMessage = message
            return message
        }
        return importMeeting(text: text, source: "剪贴板")
    }

    /// 导入失败的提示（显示成红色）
    nonisolated static func meetingImportFailed(_ message: String) -> Bool {
        ["没认出", "读不出", "打不开", "剪贴板里没有", "自动下载没成功"].contains { message.hasPrefix($0) }
    }

    /// 导入 Excel（.xlsx）、CSV 文件：金山文档里「导出 / 发送副本」成 Excel 分享给值班提醒
    @discardableResult
    func importMeetingFile(_ url: URL) -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
            if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
        }
        guard let data = try? Data(contentsOf: url) else { return "打不开这个文件" }
        let ext = url.pathExtension.lowercased()
        return importMeetingData(data, isExcel: ext == "xlsx", isCSV: ext == "csv", source: ext == "xlsx" ? "Excel 文件" : "文件")
    }

    private func importMeetingData(_ data: Data, isExcel: Bool, isCSV: Bool = false, source: String) -> String {
        if isExcel {
            guard let sheets = XLSXReader.sheets(data), let first = sheets.first else { return "读不出这个 Excel 文件" }
            // 好几张表时用第一张认得出各组的
            let rows = sheets.first { !(MeetingTable.sections($0) ?? []).isEmpty } ?? first
            let text = rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
            meetingPageText = String(text.prefix(6000))
            return applyMeeting(MeetingTable.sections(rows) ?? [], fingerprintOf: text, source: source)
        }
        guard let text = SyncService.decode(data) else { return "读不出这个文件" }
        if isCSV, let sections = MeetingTable.sections(MeetingTable.rows(text, separator: ",")), !sections.isEmpty {
            meetingPageText = String(text.prefix(6000))
            return applyMeeting(sections, fingerprintOf: text, source: "CSV 文件")
        }
        return importMeeting(text: text, source: source)
    }

    /// 用 App 里登录的金山文档账号下载周会表格（Excel）并导入；下载过程记在设置里，「周会问题」里能看
    func downloadMeeting(link: URL) async -> (message: String, ok: Bool) {
        let outcome = await MeetingDownloader.download(link)
        settings.meetingDownloadLog = ["\(Date().formatted(date: .abbreviated, time: .shortened)) 下载周会表格"] + outcome.log
        guard let data = outcome.data else {
            let message = "自动下载没成功：" + (outcome.problem ?? "没拿到文件")
            settings.meetingMessage = message
            return (message, false)
        }
        let message = importMeetingData(data, isExcel: true, source: "自动下载")
        return (message, !Self.meetingImportFailed(message))
    }

    private func applyMeeting(_ sections: [MeetingNotes.Section], fingerprintOf text: String, source: String) -> String {
        guard !sections.isEmpty else {
            let message = "没认出各组的内容（\(source)）：表格要有「分组」那一列，文字要有「组A」「研发组」这样的组名"
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

    /// 打开 App 时自动更新周会文档：金山文档的链接就用登录的账号下载 Excel；别的链接在后台打开网页读文字。
    /// 这周还没读到新一版：3 小时试一次；读到了：半天看一次有没有再改
    func refreshMeetingIfDue() async {
        guard !Self.isDemo else { return }
        let link = settings.meetingDocURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: link), url.scheme?.hasPrefix("http") == true else { return }
        let week = MeetingTracker.monday(of: .today)
        let doneThisWeek = settings.meetingWeek.map { $0 >= week } ?? false
        if let last = settings.meetingLastAttempt, Date().timeIntervalSince(last) < (doneThisWeek ? 12 : 3) * 3600 { return }
        settings.meetingLastAttempt = Date()
        let before = settings.meetingFingerprint
        var result: String?
        var problem: String?
        if DocDownload.isSupported(url) {
            let r = await downloadMeeting(link: url)
            if r.ok { result = r.message } else { problem = r.message }
        }
        if result == nil, !doneThisWeek {
            let text = await DocTextLoader.text(from: url) ?? ""
            if !MeetingNotes.parse(text).isEmpty { result = importMeeting(text: text, source: "自动") }
        }
        guard let result else {
            guard !doneThisWeek else { return }
            // 自动拿不到：每周提醒一次去复制导入
            settings.meetingMessage = (problem.map { $0 + "。" } ?? "自动读不到周会文档的内容（在线表格读不出文字）。")
                + "可以在金山文档里全选复制，回来点「从剪贴板导入」，或导出成 Excel 分享给值班提醒"
            if settings.meetingNudgedWeek != week {
                settings.meetingNudgedWeek = week
                await NotificationService.notifyNow(id: "meeting-nudge-\(week)", title: "📝 这周的周会文档导入了吗",
                                                    body: (problem.map { $0 + "。" } ?? "")
                                                        + "在金山文档里打开周会表格，全选复制，回到值班提醒点「从剪贴板导入」，就能看各组的问题解决了没有。",
                                                    route: "meeting")
            }
            return
        }
        // 读到了新的一版：通知一下
        if settings.meetingWeek == week, settings.meetingFingerprint != before {
            await NotificationService.notifyNow(id: "meeting-\(week)", title: "📝 周会文档更新了", body: result, route: "meeting")
        }
    }

    // MARK: - 编辑一个组、写回金山文档

    /// 写回金山文档设置好了没有（脚本 webhook 链接 + 脚本令牌）
    var meetingWritebackReady: Bool {
        MeetingWriter.isScriptURL(settings.meetingScriptURL) && !(Keychain.get(.kdocsScriptToken) ?? "").isEmpty
    }

    /// 编辑完存到手机上；written：已经写进金山文档了
    func saveMeetingEdits(drafts: [String: MeetingWriteback.Draft], plan: MeetingWriteback.Plan, group: String, written: Bool) {
        settings.meetingIssues = MeetingWriteback.applyLocally(issues: settings.meetingIssues, drafts: drafts, plan: plan, group: group,
                                                               week: MeetingTracker.monday(of: .today), written: written)
    }

    /// 写进金山文档，写成了再存到手机上
    func writeMeeting(plan: MeetingWriteback.Plan, drafts: [String: MeetingWriteback.Draft], group: String) async -> (message: String, ok: Bool) {
        guard let url = URL(string: settings.meetingScriptURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let token = Keychain.get(.kdocsScriptToken), !token.isEmpty else {
            return ("还没设置写回金山文档", false)
        }
        let reply = await MeetingWriter.write(plan.writes, url: url, token: token)
        let entry = ["\(Date().formatted(date: .abbreviated, time: .shortened)) 写回「\(group)」"] + plan.writes.map { "· " + $0.summary }
            + [(reply.ok ? "✓ " : "✗ ") + reply.message]
        settings.meetingWriteLog = Array((entry + settings.meetingWriteLog).prefix(60))
        guard reply.ok else { return (reply.message, false) }
        saveMeetingEdits(drafts: drafts, plan: plan, group: group, written: true)
        return (reply.message, true)
    }

    /// 测试写回脚本连不连得上
    func testMeetingScript() async -> (message: String, ok: Bool) {
        let link = settings.meetingScriptURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard MeetingWriter.isScriptURL(link), let url = URL(string: link) else {
            return ("脚本链接不对：要金山文档脚本编辑器里复制的 webhook 链接", false)
        }
        guard let token = Keychain.get(.kdocsScriptToken), !token.isEmpty else { return ("还没填脚本令牌", false) }
        let reply = await MeetingWriter.ping(url: url, token: token)
        return (reply.message, reply.ok)
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
