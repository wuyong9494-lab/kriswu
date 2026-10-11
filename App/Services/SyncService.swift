import Foundation
import BackgroundTasks

enum SyncError: LocalizedError {
    case badURL
    case http(Int)
    case needsLogin
    case undecodable

    var errorDescription: String? {
        switch self {
        case .badURL: return "网址不正确"
        case .http(let code): return "服务器返回错误 \(code)"
        case .needsLogin: return "登录已过期，自动登录没成功：请检查「设置 › 自动同步」里的账号密码；网站要验证码时，在「网页登录」里手动登录一次"
        case .undecodable: return "无法识别返回的内容"
        }
    }
}

enum SyncService {
    struct Outcome {
        var result: ParseResult
        /// 这次用上的数据接口（下次优先用它）；读网页内容时为 nil
        var apiSignature: String?
        /// 全员排班（用于搜索成员）
        var roster: Roster = [:]
        /// 各组的工作内容
        var groupNotes: [String: String] = [:]
        /// 人名后括号里的数字：还有几天待休
        var restBalance: [String: Int] = [:]
    }

    /// 全员排班接口：再取上一周和后面三周，「值班表」里可以前后切换日期。
    private static func rosterRequests(in captured: [CapturedRequest], reference: DayKey,
                                       matcher: ShiftMatcher) -> [CapturedRequest] {
        var best: CapturedRequest?
        var bestCount = 0
        var bestDays = Set<DayKey>()
        for request in captured where (200..<300).contains(request.status) {
            let roster = RosterExtractor.fromJSON(request.body, reference: reference, matcher: matcher)
            let count = roster.values.reduce(0) { $0 + $1.count }
            if count > bestCount {
                best = request
                bestCount = count
                bestDays = Set(roster.values.flatMap(\.keys))
            }
        }
        guard let best, best.hasDateParameter else { return [] }
        // 接口一次只给一天（手机版「值班查看」）：逐天取前一周到后三周；一次给一周的，按周取
        if bestDays.count == 1, let base = bestDays.first {
            let today = DayKey.today
            return (-7...21).map { today.adding(days: $0) }.filter { $0 != base }.map { day in
                best.shifted(days: calendarDays(from: base, to: day))
            }
        }
        // 按周的：以「这一条是哪一周」为准换算到本周，再取前一周、后三周
        let base = weekOffset(of: bestDays)
        return [-7, 0, 7, 14, 21].map { base + $0 }.filter { $0 != 0 }.map { best.shifted(days: $0) }
    }

    /// 这批日子所在的周离本周有几天（本周 = 0；上一周的数据 = 7，要往后推 7 天才是本周）。
    private static func weekOffset(of days: Set<DayKey>) -> Int {
        guard let first = days.min() else { return 0 }
        let d = calendarDays(from: first, to: DayKey.today)
        return Int((Double(d) / 7).rounded(.down)) * 7
    }

    private static func calendarDays(from a: DayKey, to b: DayKey) -> Int {
        Calendar.app.dateComponents([.day], from: a.date(calendar: .app, hour: 12), to: b.date(calendar: .app, hour: 12)).day ?? 0
    }

    /// 从网页文字和接口数据里收集全员排班与各组说明。
    private static func collect(texts: [String], json: [String], reference: DayKey, matcher: ShiftMatcher)
        -> (Roster, [String: String], [String: Int]) {
        var roster: Roster = [:]
        var notes: [String: String] = [:]
        var rest: [String: Int] = [:]
        for body in json {
            RosterExtractor.merge(RosterExtractor.fromJSON(body, reference: reference, matcher: matcher), into: &roster)
            notes.merge(GroupNotes.fromJSON(body)) { _, n in n }
        }
        for text in texts {
            RosterExtractor.merge(RosterExtractor.fromTable(text, reference: reference, matcher: matcher), into: &roster)
            RosterExtractor.merge(RosterExtractor.fromCards(text, reference: reference, matcher: matcher), into: &roster)
            notes.merge(GroupNotes.fromText(text, reference: reference)) { _, n in n }
            rest.merge(RosterExtractor.restBalances(text, matcher: matcher)) { first, _ in first }
        }
        return (roster, notes, rest)
    }

    /// 取回排班。
    /// viaWeb = true：在内置浏览器里打开排班页面（自动登录）。能认出网页背后的数据接口时，
    /// 直接用这个接口再取后面 weeksAhead 周的数据；认不出就照旧读网页上显示的内容。
    /// viaWeb = false：直接下载（CSV / ICS 日历订阅 / JSON 文件）。
    @MainActor
    static func fetchSchedule(urlString: String, username: String, password: String, viaWeb: Bool,
                              includeRoster: Bool = true, pageThroughRoster: Bool = true,
                              parser: ScheduleParser, aliases: [String], matcher: ShiftMatcher,
                              preferredAPI: String?, weeksAhead: Int = 3) async throws -> Outcome {
        if viaWeb, let url = webURL(urlString) {
            let reference = parser.reference
            var found: APIDiscovery.Found?
            let rosterWeeks: ([CapturedRequest]) -> [CapturedRequest] = { captured in
                rosterRequests(in: captured, reference: reference, matcher: matcher)
            }
            let page = try await WebPageLoader.load(
                url: url, username: username, password: password, extraTabs: includeRoster ? ["值班查看"] : [],
                // 「值班查看」一次只显示一天：先往前翻到本周第一天，再往后翻，能翻到的日子都读一遍
                // 后台时间有限：不一页页翻，只靠下面的接口补取各天/各周
                pager: includeRoster && pageThroughRoster ? [(label: "上一天", steps: 7), (label: "下一天", steps: 21)] : [],
                afterTabs: rosterWeeks,
                // 后台、快捷指令里只有约 30 秒
                timeBudget: includeRoster && pageThroughRoster ? nil : 20) { captured in
                found = APIDiscovery.find(in: captured, preferred: preferredAPI, aliases: aliases,
                                          matcher: matcher, reference: reference)
                guard let f = found, f.request.hasDateParameter, weeksAhead > 0 else { return [] }
                return (1...weeksAhead).map { f.request.shifted(days: 7 * $0) }
            }
            let texts = ([page.html] + page.extraHTML).map(HTMLText.toText)
            let bodies: [String] = page.captured.map { $0.body } + page.replies + page.extraReplies
            let (roster, notes, rest) = collect(texts: texts, json: bodies,
                                                reference: reference, matcher: matcher)
            if let f = found, !f.entries.isEmpty {
                var entries = f.entries
                // 每一段（本周、后面各周）各自的日期范围；没取到的那一周不算，原来的排班保留
                func span(_ e: [DayKey: String]) -> Set<DayKey> {
                    guard let lo = e.keys.min(), let hi = e.keys.max() else { return [] }
                    return ParseResult.days(in: lo...hi, calendar: .app)
                }
                // 用请求里的日期范围（比如整一周）；请求里看不出来时用读到的首尾日期
                func window(_ request: CapturedRequest, _ e: [DayKey: String]) -> Set<DayKey> {
                    if let w = request.dateWindow, w.lowerBound != w.upperBound {
                        let days = ParseResult.days(in: w, calendar: .app)
                        if days.count <= 62, Set(e.keys).isSubset(of: days) { return days }
                    }
                    return span(e)
                }
                var covered = window(f.request, f.entries)
                for (i, reply) in page.replies.enumerated() {
                    let more = JSONScheduleExtractor.extract(reply, aliases: aliases, matcher: matcher, reference: reference)
                    for (day, value) in more where entries[day] == nil { entries[day] = value }
                    if i < page.replyRequests.count, !more.isEmpty {
                        covered.formUnion(window(page.replyRequests[i], more))
                    } else {
                        covered.formUnion(span(more))
                    }
                }
                return Outcome(result: ParseResult(entries: entries, format: .api, coveredDays: covered),
                               apiSignature: f.request.signature,
                               roster: roster, groupNotes: notes, restBalance: rest)
            }
            if HTMLText.looksLikeLoginPage(page.html) { throw SyncError.needsLogin }
            return Outcome(result: try parser.parse(texts[0]), apiSignature: nil, roster: roster, groupNotes: notes,
                           restBalance: rest)
        }
        let text = try await fetchText(urlString: urlString, username: username, password: password)
        let (roster, notes, rest) = collect(texts: [text], json: [text], reference: parser.reference, matcher: matcher)
        return Outcome(result: try parser.parse(text), apiSignature: nil, roster: roster, groupNotes: notes, restBalance: rest)
    }

    struct DesktopNotes {
        var notes: [String: String]
        /// 电脑版周表里的全员排班（往前翻了几周）
        var roster: Roster = [:]
        /// 人名后括号里的待休天数（本周那一页）
        var restBalance: [String: Int] = [:]
        var url: String
        /// 没读到时的原因和页面文字（给「设置 › 各组工作内容」排查用）
        var reason: String?
        var pageText: String
    }

    /// 电脑版「值班查看」的地址：同一个网站的 #/duty。
    static func desktopDutyURL(from urlString: String) -> URL? {
        guard let url = webURL(urlString), var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        c.path = "/"
        c.query = nil
        c.fragment = "/duty"
        return c.url
    }

    /// 网页里的各组说明（电脑版表格 / 「组A」加说明的文字）。
    static func groupNotes(fromHTML html: String, reference: DayKey) -> [String: String] {
        let notes = GroupNotes.fromDesktopHTML(html)
        return notes.isEmpty ? GroupNotes.fromText(HTMLText.toText(html), reference: reference) : notes
    }

    /// 用电脑版打开「值班查看」：读上面各组的工作内容，再点「上一周」往前翻 weeksBack 周读全员排班。
    /// 网页背后的数据接口带日期参数时，也直接用接口取前几周，翻页失败也能拿到。
    @MainActor
    static func fetchDesktopGroupNotes(urlString: String, overrideURL: String, username: String, password: String,
                                       reference: DayKey, matcher: ShiftMatcher, weeksBack: Int = 9) async -> DesktopNotes {
        let custom = overrideURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dutyURL = custom.isEmpty ? desktopDutyURL(from: urlString) : webURL(custom) else {
            return DesktopNotes(notes: [:], url: custom, reason: "网址不正确", pageText: "")
        }
        let history: ([CapturedRequest]) -> [CapturedRequest] = { captured in
            historyRequests(in: captured, reference: reference, matcher: matcher, weeksBack: weeksBack)
        }
        let page: WebPageLoader.Page
        do {
            // 空标签 = 在打开的页面上直接翻页
            page = try await WebPageLoader.load(url: dutyURL, username: username, password: password,
                                                extraTabs: [""], pager: weeksBack > 0 ? [(label: "上一周", steps: weeksBack)] : [],
                                                afterTabs: history, desktop: true, replay: { _ in [] })
        } catch {
            return DesktopNotes(notes: [:], url: dutyURL.absoluteString, reason: "打不开：\(error.localizedDescription)", pageText: "")
        }
        var roster: Roster = [:]
        var notes: [String: String] = [:]
        var rest: [String: Int] = [:]
        for html in [page.html] + page.extraHTML {
            rest.merge(RosterExtractor.restBalances(HTMLText.toText(html), matcher: matcher)) { first, _ in first }
            RosterExtractor.merge(RosterExtractor.fromDesktopHTML(html, reference: reference, matcher: matcher), into: &roster)
            if notes.isEmpty { notes = groupNotes(fromHTML: html, reference: reference) }
        }
        for body in page.captured.map(\.body) + page.extraReplies {
            RosterExtractor.merge(RosterExtractor.fromJSON(body, reference: reference, matcher: matcher), into: &roster)
        }
        let text = HTMLText.toText(page.html)
        var reason: String?
        if notes.isEmpty {
            reason = HTMLText.looksLikeLoginPage(page.html) ? "停在了登录页（自动登录没成功）"
                : text.contains("组A") ? "页面上有「组A」，但没认出说明的位置"
                : "页面上没有「组A」等字样，可能不是电脑版「值班查看」页面"
        }
        return DesktopNotes(notes: notes, roster: roster, restBalance: rest, url: page.url ?? dutyURL.absoluteString,
                            reason: reason, pageText: String(text.prefix(6000)))
    }

    /// 全员排班接口往前取 weeksBack 周（以及后面三周）。
    private static func historyRequests(in captured: [CapturedRequest], reference: DayKey, matcher: ShiftMatcher,
                                        weeksBack: Int) -> [CapturedRequest] {
        var best: CapturedRequest?
        var bestCount = 0
        var bestDays = Set<DayKey>()
        for request in captured where (200..<300).contains(request.status) {
            let roster = RosterExtractor.fromJSON(request.body, reference: reference, matcher: matcher)
            let count = roster.values.reduce(0) { $0 + $1.count }
            if count > bestCount {
                best = request
                bestCount = count
                bestDays = Set(roster.values.flatMap(\.keys))
            }
        }
        guard let best, best.hasDateParameter, bestDays.count > 1 else { return [] }
        // 翻页后最多的那一条可能是好几周前的：先换算到本周，再往前 weeksBack 周、往后三周
        let base = weekOffset(of: bestDays)
        let back = weeksBack > 0 ? (1...weeksBack).map { -7 * $0 } : []
        return (back + [0, 7, 14, 21]).map { base + $0 }.filter { $0 != 0 }.map { best.shifted(days: $0) }
    }

    private static func webURL(_ urlString: String) -> URL? {
        let s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    /// 直接下载排班文件并转成文字（网页会先转换成表格文字）。
    static func fetchText(urlString: String, username: String, password: String) async throws -> String {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("webcal://") { s = "https://" + s.dropFirst("webcal://".count) }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw SyncError.badURL
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        if !username.isEmpty {
            let token = Data("\(username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 { throw SyncError.needsLogin }
            guard (200..<300).contains(http.statusCode) else { throw SyncError.http(http.statusCode) }
        }
        guard let text = decode(data) else { throw SyncError.undecodable }

        if HTMLText.looksLikeHTML(text) {
            if HTMLText.looksLikeLoginPage(text) { throw SyncError.needsLogin }
            return HTMLText.toText(text)
        }
        return text
    }

    /// 先按 UTF-8 解码，失败再试 GB18030（很多国内系统导出的 CSV 是这个编码）。
    static func decode(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: gb))
    }
}

enum BackgroundRefresh {
    static let identifier = "com.kriswu.shiftreminder.refresh"

    /// 请求系统找机会在后台刷新排班（最早 1 小时后，或下一次要发微信提醒的时间，取较早者）。
    /// 具体何时执行由 iOS 根据使用习惯决定。
    static func schedule(notBefore next: Date? = nil) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        let hour = Date(timeIntervalSinceNow: 3600)
        request.earliestBeginDate = next.map { min($0, hour) } ?? hour
        try? BGTaskScheduler.shared.submit(request)
    }
}
