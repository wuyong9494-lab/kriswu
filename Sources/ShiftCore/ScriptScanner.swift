import Foundation

/// 「查找网页排班代码」：在网站下载到手机上的网页脚本里，找和排班有关的代码片段。
/// 只有网站在网页里（而不是服务器上）排班时才找得到；找到的片段给用户自己看、自己决定要不要发给别人。
public enum ScriptScanner {
    public struct Script: Equatable {
        public var source: String
        public var text: String
        public init(source: String, text: String) {
            self.source = source
            self.text = text
        }
    }

    public struct Snippet: Equatable {
        public var source: String
        /// 片段在脚本里的位置（第几个字）
        public var offset: Int
        public var text: String
        /// 命中的关键词
        public var keywords: [String]
        public var score: Int
    }

    /// 中文关键词：排班相关，命中一个算 3 分
    static let chineseWords = ["排班", "轮班", "轮转", "轮流", "轮次", "遥测", "调度", "值班", "顺延", "请假", "出差",
                               "休息", "调休", "交接", "组A", "组别", "自动排", "顺序"]
    /// 英文关键词：命中一个算 1 分（单独出现太常见，要和别的一起出现才算）
    static let englishWords = ["schedule", "rotation", "rotate", "duty", "shift", "roster", "arrange", "paiban",
                               "nextPerson", "lastDuty", "restDays", "leave", "sortNo", "orderNo"]
    /// 常见的第三方库（Vue、Element、ECharts……）：里面到处是 sort、order，跳过
    static let vendorHints = ["vendor", "chunk-libs", "element", "echarts", "lodash", "moment", "dayjs", "polyfill",
                              "jquery", "bootstrap", "axios", "zrender", "xlsx", "core-js"]

    public static func isVendor(_ source: String) -> Bool {
        let s = source.lowercased()
        return vendorHints.contains { s.contains($0) }
    }

    /// 找片段：每处命中前后各取 radius 个字，重叠的合并；按分数从高到低，最多 limit 段
    public static func scan(_ scripts: [Script], radius: Int = 400, limit: Int = 30) -> [Snippet] {
        var result: [Snippet] = []
        for script in scripts where !isVendor(script.source) {
            // 用 NSString（UTF-16 位置）找，几 MB 的脚本也快
            let ns = script.text as NSString
            let length = ns.length
            guard length > 0 else { continue }
            var hits: [(pos: Int, word: String, chinese: Bool)] = []
            for (words, chinese) in [(chineseWords, true), (englishWords, false)] {
                for word in words {
                    var from = 0
                    var count = 0
                    while from < length, count < 200 {
                        let r = ns.range(of: word, options: chinese ? [] : [.caseInsensitive],
                                         range: NSRange(location: from, length: length - from))
                        guard r.location != NSNotFound else { break }
                        hits.append((r.location, word, chinese))
                        from = r.location + r.length
                        count += 1
                    }
                }
            }
            guard !hits.isEmpty else { continue }
            hits.sort { $0.pos < $1.pos }
            // 合并成一段段窗口
            var windows: [(lo: Int, hi: Int, words: [String: Bool])] = []
            for hit in hits {
                let lo = max(0, hit.pos - radius), hi = min(length, hit.pos + radius)
                if let last = windows.last, lo <= last.hi {
                    windows[windows.count - 1].hi = max(last.hi, hi)
                    windows[windows.count - 1].words[hit.word] = hit.chinese
                } else {
                    windows.append((lo, hi, [hit.word: hit.chinese]))
                }
            }
            for w in windows {
                let score = w.words.values.reduce(0) { $0 + ($1 ? 3 : 1) }
                // 只有一个英文词（比如单独一个 shift）不算
                guard score >= 2 else { continue }
                // 太长的窗口截一下，免得一段就几万字
                let hi = min(w.hi, w.lo + radius * 6)
                let range = ns.rangeOfComposedCharacterSequences(for: NSRange(location: w.lo, length: hi - w.lo))
                result.append(Snippet(source: script.source, offset: w.lo, text: ns.substring(with: range),
                                      keywords: w.words.keys.sorted(), score: score))
            }
        }
        return Array(result.sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }.prefix(limit))
    }

    /// 压缩成一行的代码在分号、大括号后换行，手机上好读一点
    public static func readable(_ code: String) -> String {
        var out = ""
        var depthInString: Character?
        var previous: Character = " "
        for c in code {
            out.append(c)
            if let q = depthInString {
                if c == q && previous != "\\" { depthInString = nil }
            } else if c == "\"" || c == "'" || c == "`" {
                depthInString = c
            } else if c == ";" || c == "{" || c == "}" {
                out.append("\n")
            }
            previous = c
        }
        return out.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// 在网页里运行：收集内嵌脚本和加载过的脚本文件（同一个网站的，带登录状态取），返回 JSON 字符串 [{s, t}]
    public static let collectScriptsJS = """
    const list = [];
    for (const s of Array.from(document.scripts)) {
      if (!s.src && s.textContent && s.textContent.length > 0) list.push({s: '（网页内嵌）', t: s.textContent});
    }
    const urls = new Set();
    for (const s of Array.from(document.scripts)) { if (s.src) urls.add(s.src); }
    for (const l of Array.from(document.querySelectorAll('link[rel=modulepreload],link[rel=preload][as=script],link[rel=prefetch]'))) {
      if (l.href && /\\.m?js(\\?|$)/.test(l.href)) urls.add(l.href);
    }
    for (const e of performance.getEntriesByType('resource')) {
      if (e.initiatorType === 'script' || /\\.m?js(\\?|$)/.test(e.name)) urls.add(e.name);
    }
    const sameSite = Array.from(urls).filter(u => { try { return new URL(u).host === location.host; } catch (_) { return false; } });
    for (const u of sameSite.slice(0, 80)) {
      try {
        const r = await fetch(u, {credentials: 'include'});
        const t = await r.text();
        if (t.length < 8000000) list.push({s: u, t: t});
      } catch (_) {}
    }
    return JSON.stringify(list);
    """

    /// 解析上面那段返回的 JSON
    public static func scripts(fromJSON json: String) -> [Script] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return [] }
        return array.compactMap { item in
            guard let s = item["s"], let t = item["t"] else { return nil }
            return Script(source: s, text: t)
        }
    }
}
