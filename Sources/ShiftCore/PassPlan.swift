import Foundation

/// 每天的数传计划：从导出的 Excel / 复制的表格，或者手机拍的照片（识别出的文字块）读出每一行，
/// 按运营商（地面站「-」前面的名字）分开，生成发到各家群里的文字
public struct PassPlanRow: Codable, Equatable, Hashable, Sendable {
    public var orbit: String
    public var satelliteID: String
    public var satellite: String
    public var station: String
    public var start: String
    public var end: String
    public var info: String
    public var status: String

    public init(orbit: String = "", satelliteID: String = "", satellite: String = "", station: String = "",
                start: String = "", end: String = "", info: String = "", status: String = "") {
        self.orbit = orbit
        self.satelliteID = satelliteID
        self.satellite = satellite
        self.station = station
        self.start = start
        self.end = end
        self.info = info
        self.status = status
    }
}

public enum PassPlan {
    /// 表里的各列：表头里出现这些字就是这一列（先认长的，「卫星名称」不会被当成「卫星ID」）
    public enum Column: String, CaseIterable, Sendable {
        case orbit, satelliteID, satellite, station, start, end, info, status
        /// 序号（No.）：只用来分列，不留
        case number

        /// 一格里只有一个值（日期时间、数传信息可能被认成好几块，要拼起来）
        var isSingleValue: Bool { [.orbit, .satelliteID, .satellite, .station, .number].contains(self) }

        var headerWords: [String] {
            switch self {
            case .orbit: return ["圈号", "圈次"]
            case .satelliteID: return ["卫星id", "卫星编号", "卫星代号"]
            case .satellite: return ["卫星名称", "卫星名"]
            case .station: return ["地面站", "接收站", "站名"]
            case .start: return ["开始时间", "开始"]
            case .end: return ["结束时间", "结束"]
            case .info: return ["数传信息", "信息"]
            case .status: return ["状态"]
            case .number: return []
            }
        }
    }

    /// 这个表头格子是哪一列
    public static func column(forHeader text: String) -> Column? {
        let t = text.lowercased().filter { !$0.isWhitespace }
        guard !t.isEmpty else { return nil }
        if ["no", "no.", "序号"].contains(t) { return .number }
        if t.contains("卫星") && t.contains("id") { return .satelliteID }
        return Column.allCases.first { c in c.headerWords.contains { t.contains($0) } }
    }

    // MARK: - 从表格读（Excel、复制的文字）

    /// 第一行认得出三列以上的是表头，下面每行是一条；空行、表头重复的行跳过
    public static func rows(fromTable table: [[String]]) -> [PassPlanRow] {
        guard let headerIndex = table.firstIndex(where: { row in Set(row.compactMap(column(forHeader:))).count >= 3 }) else { return [] }
        var columns: [Int: Column] = [:]
        var used = Set<Column>()
        for (i, cell) in table[headerIndex].enumerated() {
            if let c = column(forHeader: cell), !used.contains(c) {
                columns[i] = c
                used.insert(c)
            }
        }
        return table[(headerIndex + 1)...].compactMap { cells in
            var values: [Column: String] = [:]
            for (i, cell) in cells.enumerated() {
                guard let c = columns[i] else { continue }
                values[c] = cell.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return row(from: values)
        }
    }

    // MARK: - 从照片读（识别出的一块块文字）

    /// 识别出的一块文字：位置用 0–1 的比例，y 从上往下
    public struct TextBox: Equatable, Sendable {
        public var text: String
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(text: String, x: Double, y: Double, width: Double, height: Double) {
            self.text = text
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        var midX: Double { x + width / 2 }
        var midY: Double { y + height / 2 }
    }

    /// 每列在照片里的左右位置（0–1）：往下翻着连拍时，后面几张拍不到表头，就用前一张的
    public struct ColumnLayout: Equatable, Sendable {
        public var centers: [Column: Double]
        public init(centers: [Column: Double]) { self.centers = centers }
    }

    /// 拍屏幕常常是斜的：用表头那一排的位置算出倾斜，扶正以后按上下分行、按表头的左右位置分列
    public static func rows(fromBoxes boxes: [TextBox]) -> [PassPlanRow] {
        read(boxes).rows
    }

    /// 同上，另外返回这张认出的列位置；这张没拍到表头时用 fallback（前一张的列位置，当作没有倾斜）
    public static func read(_ boxes: [TextBox], fallback: ColumnLayout? = nil) -> (rows: [PassPlanRow], layout: ColumnLayout?) {
        let headers = boxes.compactMap { b in column(forHeader: b.text).map { (box: b, column: $0) } }
        let heights = boxes.map(\.height).sorted()
        let lineHeight = heights.isEmpty ? 0.02 : heights[heights.count / 2]
        let slope: Double
        let body: [TextBox]
        let layout: ColumnLayout
        if let top = headerRow(headers) {
            let s = tilt(top.map(\.box))
            let headerLevel = top.map { $0.box.midY - s * $0.box.midX }.reduce(0, +) / Double(top.count)
            slope = s
            body = boxes.filter { b in b.midY - s * b.midX > headerLevel + lineHeight * 0.6 && !top.contains { $0.box == b } }
            layout = ColumnLayout(centers: Dictionary(top.map { ($0.column, $0.box.midX) }, uniquingKeysWith: { a, _ in a }))
        } else if let fallback {
            slope = 0
            body = boxes
            layout = fallback
        } else {
            return ([], nil)
        }
        func level(_ b: TextBox) -> Double { b.midY - slope * b.midX }
        // 上下挨得近的算一行
        var lines: [[TextBox]] = []
        for b in body.sorted(by: { level($0) < level($1) }) {
            if let last = lines.last?.last, abs(level(b) - level(last)) < lineHeight * 0.7 {
                lines[lines.count - 1].append(b)
            } else {
                lines.append([b])
            }
        }
        let centers = layout.centers.map { (column: $0.key, x: $0.value) }
        let rows = lines.compactMap { line -> PassPlanRow? in
            var parts: [Column: [TextBox]] = [:]
            for b in line {
                guard let nearest = centers.min(by: { abs($0.x - b.midX) < abs($1.x - b.midX) }) else { continue }
                parts[nearest.column, default: []].append(b)
            }
            var values: [Column: String] = [:]
            for (column, boxes) in parts {
                if column.isSingleValue, let x = layout.centers[column] {
                    // 圈号、卫星、地面站一格只有一个值：最左边序号那列没拍到表头时，序号会挤进圈号，只留离表头最近的
                    values[column] = boxes.min { abs($0.midX - x) < abs($1.midX - x) }?.text
                } else {
                    values[column] = boxes.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ")
                }
            }
            return row(from: values)
        }
        return (rows, layout)
    }

    /// 表头那一排：每个认得出的表头格子和它上下差不多高的（允许屏幕拍斜）算一排，
    /// 取认出列最多的一排，一样多取靠上的（数据里偶尔有字像表头，不会被当成表头那排）
    private static func headerRow(_ headers: [(box: TextBox, column: Column)]) -> [(box: TextBox, column: Column)]? {
        var best: [(box: TextBox, column: Column)] = []
        for h in headers.sorted(by: { $0.box.midY < $1.box.midY }) {
            let band = headers.filter { abs($0.box.midY - h.box.midY) < 0.06 }
            let slope = tilt(band.map(\.box))
            let level = h.box.midY - slope * h.box.midX
            let tolerance = max(0.015, h.box.height * 1.2)
            var seen = Set<Column>()
            let row = band.filter { abs($0.box.midY - slope * $0.box.midX - level) < tolerance }
                .sorted { $0.box.x < $1.box.x }
                .filter { seen.insert($0.column).inserted }
            if row.count > best.count { best = row }
        }
        return best.count >= 3 ? best : nil
    }

    /// 一排格子的倾斜（每往右 1，往下多少）：最小二乘
    static func tilt(_ boxes: [TextBox]) -> Double {
        guard boxes.count >= 2 else { return 0 }
        let xs = boxes.map(\.midX), ys = boxes.map(\.midY)
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard sxx > 0 else { return 0 }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let slope = sxy / sxx
        // 斜得太厉害多半是认错了，不扶正
        return abs(slope) < 0.2 ? slope : 0
    }

    // MARK: - 整理一行

    /// 一行里有卫星、地面站、开始时间才算一条（只认出一两个字的行是噪点）
    static func row(from values: [Column: String]) -> PassPlanRow? {
        var r = PassPlanRow(orbit: values[.orbit] ?? "", satelliteID: values[.satelliteID] ?? "",
                            satellite: values[.satellite] ?? "", station: values[.station] ?? "",
                            start: normalizedTime(values[.start] ?? ""), end: normalizedTime(values[.end] ?? ""),
                            info: values[.info] ?? "", status: values[.status] ?? "")
        r.station = r.station.replacingOccurrences(of: "—", with: "-").replacingOccurrences(of: "－", with: "-")
        guard !(r.satellite.isEmpty && r.satelliteID.isEmpty), !r.station.isEmpty, !r.start.isEmpty else { return nil }
        // 又出现一遍表头（翻页、拼接的表）
        if column(forHeader: r.station) == .station { return nil }
        return r
    }

    /// 「2026-10-27 22:57:51」：识别时常把冒号认成点、把日期和时间分成两块，统一一下
    public static func normalizedTime(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "：", with: ":").replacingOccurrences(of: "／", with: "/")
        let pattern = #"(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})\s*日?\s*(\d{1,2})\s*[:.]\s*(\d{2})(?:\s*[:.]\s*(\d{2}))?"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return s }
        func group(_ i: Int) -> Int? {
            guard let r = Range(m.range(at: i), in: s) else { return nil }
            return Int(s[r])
        }
        guard let y = group(1), let mo = group(2), let d = group(3), let h = group(4), let mi = group(5) else { return s }
        return String(format: "%04d-%02d-%02d %02d:%02d:%02d", y, mo, d, h, mi, group(6) ?? 0)
    }

    // MARK: - 几张照片合起来、检查

    /// 计划长、拍了几张（上下有重叠）：合成一份。同一个地面站、开始和结束时间都一样的算同一条
    /// （时间是数字，两次拍都认得一样；卫星名偶尔认错一个字也不会当成两条），留认出字段多的那条
    public static func merge(_ pages: [[PassPlanRow]]) -> [PassPlanRow] {
        var order: [String] = []
        var best: [String: PassPlanRow] = [:]
        func key(_ r: PassPlanRow) -> String {
            [r.start, r.end, r.station.filter { !$0.isWhitespace }].joined(separator: "|")
        }
        func filled(_ r: PassPlanRow) -> Int {
            [r.orbit, r.satelliteID, r.satellite, r.station, r.start, r.end, r.info, r.status].filter { !$0.isEmpty }.count
        }
        for row in pages.joined() {
            let k = key(row)
            if let old = best[k] {
                if filled(row) > filled(old) { best[k] = row }
            } else {
                order.append(k)
                best[k] = row
            }
        }
        return order.compactMap { best[$0] }
    }

    /// 这一条可能认错的地方（页面上标出来，让人核对）；没有返回空
    public static func problems(_ r: PassPlanRow, rules: [OperatorRule] = []) -> [String] {
        var list: [String] = []
        let time = #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#
        func isTime(_ s: String) -> Bool { s.range(of: time, options: .regularExpression) != nil }
        if !isTime(r.start) { list.append("开始时间没认全") }
        if r.end.isEmpty {
            list.append("没有结束时间")
        } else if !isTime(r.end) {
            list.append("结束时间没认全")
        } else if isTime(r.start), r.end <= r.start {
            list.append("结束比开始还早")
        }
        if operatorName(of: r.station, rules: rules) == nil { list.append("分不出是哪家（运营商对照表里没有这个站）") }
        if !r.orbit.isEmpty, !r.orbit.allSatisfy(\.isNumber) { list.append("圈号不全是数字") }
        if r.satellite.isEmpty { list.append("没认出卫星名称") }
        return list
    }

    // MARK: - 按运营商分开

    /// 一家运营商：名字和它的地面站名开头的几种写法（「乙」的站叫「乙站-…」「丙光…」都写上）
    public struct OperatorRule: Codable, Equatable, Hashable, Sendable {
        public var name: String
        public var prefixes: [String]

        public init(name: String, prefixes: [String]) {
            self.name = name
            self.prefixes = prefixes
        }
    }

    /// 对照表里认不出、站名里也没有「-」的，归到这一组，页面上让人指定是哪家
    public static let unassigned = "没分到运营商"

    /// 地面站「-」前面的名字（「甲站-北区01」→「甲站」）；没有「-」返回 nil
    public static func operatorName(of station: String) -> String? {
        let s = station.trimmingCharacters(in: .whitespaces)
        guard let dash = s.firstIndex(where: { "-—－_".contains($0) }) else { return nil }
        let name = s[..<dash].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// 是哪家：先按对照表（站名开头对上最长的那个前缀），没有再按「-」前面的名字，都没有返回 nil
    public static func operatorName(of station: String, rules: [OperatorRule]) -> String? {
        let s = station.filter { !$0.isWhitespace }
        let best = rules.flatMap { rule in rule.prefixes.map { (rule.name, $0.filter { !$0.isWhitespace }) } }
            .filter { !$0.1.isEmpty && s.hasPrefix($0.1) }
            .max { $0.1.count < $1.1.count }
        return best?.0 ?? operatorName(of: station)
    }

    /// 给一个对不上的站记前缀用：「-」前面的名字，没有「-」就去掉末尾的编号（「丙光北区03」→「丙光北区」）
    public static func suggestedPrefix(of station: String) -> String {
        if let name = operatorName(of: station) { return name }
        let s = station.trimmingCharacters(in: .whitespaces)
        let trimmed = s.replacingOccurrences(of: #"[\d\s]+$"#, with: "", options: .regularExpression)
        return trimmed.isEmpty ? s : trimmed
    }

    /// 按运营商分开，每家按开始时间排；家的先后按对照表里的顺序，表里没有的按第一次出现，认不出的放最后
    public static func grouped(_ rows: [PassPlanRow], rules: [OperatorRule] = []) -> [(name: String, rows: [PassPlanRow])] {
        var order: [String] = []
        var map: [String: [PassPlanRow]] = [:]
        for r in rows {
            let name = operatorName(of: r.station, rules: rules) ?? unassigned
            if map[name] == nil { order.append(name) }
            map[name, default: []].append(r)
        }
        let ruleIndex = Dictionary(rules.enumerated().map { ($1.name, $0) }, uniquingKeysWith: { a, _ in a })
        let firstSeen = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        func rank(_ name: String) -> (Int, Int) {
            if name == unassigned { return (2, 0) }
            return ruleIndex[name].map { (0, $0) } ?? (1, firstSeen[name] ?? 0)
        }
        return order.sorted { rank($0) < rank($1) }
            .map { ($0, map[$0]!.sorted { ($0.start, $0.station) < ($1.start, $1.station) }) }
    }

    /// 对照表里今天没有计划的那几家
    public static func idle(_ rows: [PassPlanRow], rules: [OperatorRule]) -> [String] {
        let busy = Set(grouped(rows, rules: rules).map(\.name))
        return rules.map(\.name).filter { !busy.contains($0) }
    }

    /// 对照表写成文字（一家一行：「甲：甲站、丙光」），方便复制、粘贴导入
    public static func rulesText(_ rules: [OperatorRule]) -> String {
        rules.map { "\($0.name)：\($0.prefixes.joined(separator: "、"))" }.joined(separator: "\n")
    }

    /// 读粘贴的对照表：一行一家，名字后面跟冒号，前缀用顿号、逗号、空格隔开；只写名字的，前缀就是名字本身
    public static func parseRules(_ text: String) -> [OperatorRule] {
        var rules: [OperatorRule] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let parts = line.split(maxSplits: 1, whereSeparator: { ":：".contains($0) })
            let name = String(parts[0]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            var prefixes = parts.count > 1
                ? parts[1].split(whereSeparator: { "、,，;；/ ".contains($0) }).map { String($0) }.filter { !$0.isEmpty }
                : []
            if prefixes.isEmpty { prefixes = [name] }
            if let i = rules.firstIndex(where: { $0.name == name }) {
                rules[i].prefixes += prefixes.filter { !rules[i].prefixes.contains($0) }
            } else {
                rules.append(OperatorRule(name: name, prefixes: prefixes))
            }
        }
        return rules
    }

    /// 发到群里的一段话：标题一行，每条一行（时间在前，方便看）
    public static func message(name: String, rows: [PassPlanRow]) -> String {
        let days = Set(rows.map { String($0.start.prefix(10)) }).sorted()
        let title: String
        if days.count == 1, let d = DayKey(string: days[0]) {
            title = "\(d.month)月\(d.day)日数传计划（\(name)）共 \(rows.count) 条"
        } else {
            title = "数传计划（\(name)）共 \(rows.count) 条"
        }
        let lines = rows.enumerated().map { i, r -> String in
            let time = [shortTime(r.start), shortTime(r.end)].filter { !$0.isEmpty }.joined(separator: "–")
            var parts = [time, r.satellite.isEmpty ? r.satelliteID : r.satellite]
            if !r.satelliteID.isEmpty, !r.satellite.isEmpty { parts.append(r.satelliteID) }
            if !r.orbit.isEmpty { parts.append("圈号 \(r.orbit)") }
            parts.append(r.station)
            if !r.info.isEmpty { parts.append(r.info) }
            return "\(i + 1). " + parts.filter { !$0.isEmpty }.joined(separator: "  ")
        }
        return ([title] + lines).joined(separator: "\n")
    }

    /// 「2026-10-27 22:57:51」→「22:57:51」；不是这个格式的原样
    static func shortTime(_ s: String) -> String {
        s.count == 19 && s.dropFirst(10).first == " " ? String(s.suffix(8)) : s
    }
}
