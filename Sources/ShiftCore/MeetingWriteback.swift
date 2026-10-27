import Foundation

/// 一条问题在周会表格里的位置：第几行、内容在哪一列（一格里的第几条）、「完成情况」「负责人」在哪一列，
/// 和导入时这几格的原文。写回金山文档时按它找格子、核对格子没被别人改过
public struct MeetingSource: Codable, Equatable, Hashable, Sendable {
    /// 行、列都从 1 数
    public var row: Int
    public var contentColumn: Int
    /// 内容那一格里的第几条
    public var number: Int
    public var content: String
    public var closureColumn: Int?
    public var closure: String
    public var ownerColumn: Int?
    public var owner: String
    /// 这一行的「项目或工作内容」（本周问题、上上周问题进展…）
    public var topic: String

    public init(row: Int, contentColumn: Int, number: Int, content: String,
                closureColumn: Int? = nil, closure: String = "", ownerColumn: Int? = nil, owner: String = "", topic: String = "") {
        self.row = row
        self.contentColumn = contentColumn
        self.number = number
        self.content = content
        self.closureColumn = closureColumn
        self.closure = closure
        self.ownerColumn = ownerColumn
        self.owner = owner
        self.topic = topic
    }
}

/// 在 App 里改一个组的问题，算出要改金山文档里哪几个格子、改成什么
public enum MeetingWriteback {
    /// 编辑时的一条：问题、负责人、进展、解决了没有
    public struct Draft: Equatable, Sendable {
        public var text: String
        public var owner: String
        public var progress: String
        public var resolved: Bool

        public init(text: String = "", owner: String = "", progress: String = "", resolved: Bool = false) {
            self.text = text
            self.owner = owner
            self.progress = progress
            self.resolved = resolved
        }

        public init(_ issue: MeetingIssue) {
            self.init(text: issue.text, owner: issue.owners.joined(separator: "、"), progress: issue.progress ?? "",
                      resolved: issue.status == .resolved)
        }

        /// 比较时不管头尾空白
        var trimmed: Draft {
            Draft(text: MeetingWriteback.clean(text), owner: MeetingWriteback.clean(owner),
                  progress: MeetingWriteback.clean(progress), resolved: resolved)
        }
    }

    /// 改一个格子：先按这一行内容那一格（anchor）找到这一行，表格上面插了行也能找到；
    /// 格子里还是导入时的内容（expect）才改成 value，别人刚改过的不动
    public struct CellWrite: Codable, Equatable, Sendable {
        public var anchorRow: Int
        public var anchorColumn: Int
        public var anchorText: String
        public var row: Int
        public var column: Int
        public var expect: String
        public var value: String
        /// 给人看的：哪一行哪一格改了什么
        public var summary: String

        /// 表格里的格子名：第 2 行第 6 列是「F2」
        public var address: String { MeetingWriteback.columnName(column) + "\(row)" }
    }

    /// 第几列 → 列名：1 是 A，27 是 AA
    public static func columnName(_ column: Int) -> String {
        var n = max(1, column)
        var name = ""
        while n > 0 {
            let r = (n - 1) % 26
            name = String(Character(UnicodeScalar(UInt8(65 + r)))) + name
            n = (n - 1) / 26
        }
        return name
    }

    /// 新加的一条放在哪：这一行内容那一格里的第几条
    public struct Addition: Equatable, Sendable {
        public var text: String
        public var progress: String
        public var row: Int?
        public var column: Int?
        public var number: Int?
    }

    public struct Plan: Equatable, Sendable {
        public var writes: [CellWrite] = []
        public var additions: [Addition] = []
        /// 写不回表格、只改了手机上的
        public var skipped: [String] = []
        /// 有没有改动（包括只能改手机上的）
        public var hasChanges = false
    }

    static func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private static func short(_ s: String) -> String { s.count > 14 ? String(s.prefix(14)) + "…" : s }

    /// 勾上「解决了」，进展跟着写成「完成」；取消勾，写着完成的改成「进行中」
    public static func progress(afterToggling resolved: Bool, current: String) -> String {
        let done = MeetingTable.isDoneNote(clean(current))
        if resolved { return done ? current : "完成" }
        return done ? "进行中" : current
    }

    /// 补充说明的写法和导入时一样：「本周问题 · 负责人：甲 · 进展：进行中」
    public static func composeDetail(topic: String?, owner: String, progress: String) -> String? {
        let parts = [topic.flatMap { $0.isEmpty ? nil : $0 },
                     owner.isEmpty ? nil : "负责人：\(owner)",
                     progress.isEmpty ? nil : "进展：\(progress)"].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 改动对应到格子：同一行的几条共用一个内容格、完成情况格、负责人格，合起来一格写一次
    public static func plan(issues: [MeetingIssue], drafts: [String: Draft], additions: [Draft], group: String) -> Plan {
        var plan = Plan()
        let groupIssues = issues.filter { $0.group == group }
        let changed: [(issue: MeetingIssue, draft: Draft)] = groupIssues.compactMap { issue in
            guard let d = drafts[issue.id]?.trimmed, d != Draft(issue).trimmed else { return nil }
            return (issue, d)
        }
        let added = additions.map(\.trimmed).filter { !$0.text.isEmpty }
        plan.hasChanges = !changed.isEmpty || !added.isEmpty

        struct RowKey: Hashable { let row: Int; let column: Int }
        var sources: [RowKey: MeetingSource] = [:]
        var items: [RowKey: [(issue: MeetingIssue, draft: Draft, source: MeetingSource)]] = [:]
        for (issue, d) in changed {
            guard let s = issue.source else {
                plan.skipped.append("「\(short(issue.text))」是从文字导入的，表格里找不到它的位置，只改了手机上的")
                continue
            }
            let key = RowKey(row: s.row, column: s.contentColumn)
            if sources[key] == nil { sources[key] = s }
            items[key, default: []].append((issue, d, s))
        }
        // 新加的放到这个组「本周问题」那一行，没有就放这个组最后一行
        var target: RowKey?
        if !added.isEmpty {
            let all = groupIssues.compactMap(\.source)
            if let t = all.filter({ $0.topic.contains("本周") }).max(by: { $0.row < $1.row }) ?? all.max(by: { $0.row < $1.row }) {
                let key = RowKey(row: t.row, column: t.contentColumn)
                target = key
                if sources[key] == nil { sources[key] = t }
            } else {
                plan.skipped.append("这个组在表格里找不到能加问题的那一行，新加的 \(added.count) 条只存在手机上")
                plan.additions = added.map { Addition(text: $0.text, progress: $0.progress) }
            }
        }

        for key in sources.keys.sorted(by: { ($0.row, $0.column) < ($1.row, $1.column) }) {
            guard let s = sources[key] else { continue }
            let rowItems = items[key] ?? []
            let place = s.topic.isEmpty ? "第 \(s.row) 行" : "第 \(s.row) 行「\(s.topic)」"
            func write(column: Int, expect: String, value: String, summary: String) {
                plan.writes.append(CellWrite(anchorRow: s.row, anchorColumn: s.contentColumn, anchorText: s.content,
                                             row: s.row, column: column, expect: expect, value: value, summary: summary))
            }

            // 内容那一格：改了文字的条换掉，新加的接在最后
            var edits: [Int: String] = [:]
            for item in rowItems where !item.draft.text.isEmpty && item.draft.text != item.issue.text {
                edits[item.source.number] = item.draft.text
            }
            var content = MeetingTable.replacingPieces(in: s.content, with: edits)
            var notes = MeetingTable.closureNotes(s.closure)
            let before = notes
            var newCount = 0
            if key == target {
                let r = MeetingTable.appending(added.map(\.text), to: content)
                content = r.text
                newCount = added.count
                for (i, a) in added.enumerated() {
                    plan.additions.append(Addition(text: a.text, progress: a.progress, row: s.row, column: s.contentColumn, number: r.firstNumber + i))
                    if !a.progress.isEmpty { notes[r.firstNumber + i] = a.progress }
                }
            }
            if content != s.content {
                let what = [edits.isEmpty ? nil : "改 \(edits.count) 条", newCount == 0 ? nil : "加 \(newCount) 条"].compactMap { $0 }
                write(column: s.contentColumn, expect: s.content, value: content, summary: place + "：" + what.joined(separator: "，"))
            }

            // 「完成情况」那一格：按条改进展
            for item in rowItems where item.draft.progress != clean(item.issue.progress ?? "") {
                notes[item.source.number] = item.draft.progress.isEmpty ? nil : item.draft.progress
            }
            if notes != before {
                if let column = s.closureColumn {
                    let numbers = Set(notes.keys).union(before.keys).filter { notes[$0] != before[$0] }.sorted()
                    let what = numbers.map { n in "第 \(n) 条" + (notes[n].map { "写成「\(short($0))」" } ?? "清空") }
                    write(column: column, expect: s.closure, value: MeetingTable.closureText(notes),
                          summary: "第 \(s.row) 行完成情况：" + what.joined(separator: "，"))
                } else {
                    plan.skipped.append("表格里没有「完成情况」那一列，\(place)的进展只改了手机上的")
                }
            }

            // 负责人那一格：一行共用一个，改了哪条就用哪条的
            if let item = rowItems.first(where: { $0.draft.owner != Draft($0.issue).trimmed.owner }) {
                if let column = s.ownerColumn {
                    write(column: column, expect: s.owner, value: item.draft.owner,
                          summary: "第 \(s.row) 行负责人：\(clean(s.owner).isEmpty ? "（空）" : clean(s.owner)) → \(item.draft.owner.isEmpty ? "（空）" : item.draft.owner)")
                } else {
                    plan.skipped.append("表格里没有「负责人」那一列，\(place)的负责人只改了手机上的")
                }
            }
        }
        return plan
    }

    /// 金山文档脚本回来的内容里，写回脚本的结果：脚本把它打在日志里（「RESULT_JSON {…}」，旧版脚本是 SHIFT_RESULT），也可能直接在 result 里
    public static func scriptResult(in json: Any?) -> [String: Any]? {
        func object(_ text: String) -> [String: Any]? {
            (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        }
        var queue: [Any] = json.map { [$0] } ?? []
        var fromResult: [String: Any]?
        var i = 0
        while i < queue.count {
            let node = queue[i]
            i += 1
            if let text = node as? String {
                for marker in ["RESULT_JSON ", "SHIFT_RESULT "] {
                    if let r = text.range(of: marker), let found = object(String(text[r.upperBound...])) { return found }
                }
            } else if let dict = node as? [String: Any] {
                for key in dict.keys.sorted() {
                    guard let value = dict[key] else { continue }
                    if key == "result", fromResult == nil {
                        let found = (value as? [String: Any]) ?? (value as? String).flatMap(object)
                        if let found, found["ok"] != nil { fromResult = found }
                    }
                    queue.append(value)
                }
            } else if let array = node as? [Any] {
                queue.append(contentsOf: array)
            }
        }
        return fromResult
    }

    /// 改动存到手机上。written：已经写进表格了，就把那几格的新原文记下来（下次改的时候核对用），新加的也记下位置
    public static func applyLocally(issues: [MeetingIssue], drafts: [String: Draft], plan: Plan, group: String,
                                    week: DayKey, written: Bool) -> [MeetingIssue] {
        var result = issues
        for i in result.indices where result[i].group == group {
            guard let d = drafts[result[i].id]?.trimmed, d != Draft(result[i]).trimmed else { continue }
            let old = result[i]
            if !d.text.isEmpty { result[i].text = d.text }
            result[i].detail = composeDetail(topic: old.topic, owner: d.owner, progress: d.progress)
            if d.resolved != (old.status == .resolved) {
                result[i].status = d.resolved ? .resolved : .open
                result[i].resolvedWeek = d.resolved ? week : nil
                result[i].manual = true
            }
        }
        if written {
            for w in plan.writes {
                for i in result.indices {
                    guard var s = result[i].source, s.row == w.row, s.contentColumn == w.anchorColumn else { continue }
                    if w.column == s.contentColumn { s.content = w.value }
                    if w.column == s.closureColumn { s.closure = w.value }
                    if w.column == s.ownerColumn { s.owner = w.value }
                    result[i].source = s
                }
            }
        }
        for a in plan.additions {
            // 同一行已有的一条：拿它的负责人、各列位置
            let sibling = result.first { $0.group == group && $0.source?.row == a.row && $0.source?.contentColumn == a.column }
            var source: MeetingSource?
            if written, let number = a.number, var s = sibling?.source {
                s.number = number
                source = s
            }
            let done = MeetingTable.isDoneNote(a.progress)
            let key = MeetingTracker.normalized(a.text)
            var id = "\(group)|\(week)|\(key.prefix(32))"
            while result.contains(where: { $0.id == id }) { id += "+" }
            result.append(MeetingIssue(id: id, group: group, text: a.text, firstWeek: week, lastWeek: week,
                                       status: done ? .resolved : .open, resolvedWeek: done ? week : nil,
                                       detail: composeDetail(topic: source?.topic, owner: sibling?.owners.joined(separator: "、") ?? "",
                                                             progress: a.progress),
                                       source: source))
        }
        return result
    }
}
