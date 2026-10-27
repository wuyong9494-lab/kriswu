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

    /// 拍屏幕常常是斜的：用表头那一排的位置算出倾斜，扶正以后按上下分行、按表头的左右位置分列
    public static func rows(fromBoxes boxes: [TextBox]) -> [PassPlanRow] {
        let headers = boxes.compactMap { b in column(forHeader: b.text).map { (box: b, column: $0) } }
        // 表头里每列只认一个（最靠上的那排）
        guard let top = headerRow(headers) else { return [] }
        let slope = tilt(top.map(\.box))
        func level(_ b: TextBox) -> Double { b.midY - slope * b.midX }
        let headerLevel = top.map { level($0.box) }.reduce(0, +) / Double(top.count)
        let heights = boxes.map(\.height).sorted()
        let lineHeight = heights.isEmpty ? 0.02 : heights[heights.count / 2]
        let body = boxes.filter { b in level(b) > headerLevel + lineHeight * 0.6 && !top.contains { $0.box == b } }
            .sorted { level($0) < level($1) }
        // 上下挨得近的算一行
        var lines: [[TextBox]] = []
        for b in body {
            if let last = lines.last?.last, abs(level(b) - level(last)) < lineHeight * 0.7 {
                lines[lines.count - 1].append(b)
            } else {
                lines.append([b])
            }
        }
        let centers = top.map { (column: $0.column, x: $0.box.midX) }
        return lines.compactMap { line in
            var parts: [Column: [TextBox]] = [:]
            for b in line {
                guard let nearest = centers.min(by: { abs($0.x - b.midX) < abs($1.x - b.midX) }) else { continue }
                parts[nearest.column, default: []].append(b)
            }
            let values = parts.mapValues { $0.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ") }
            return row(from: values)
        }
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

    // MARK: - 按运营商分开

    /// 运营商：地面站「-」前面的名字（「甲站-北区01」→「甲站」）；没有「-」就是整个站名
    public static func operatorName(of station: String) -> String {
        let s = station.trimmingCharacters(in: .whitespaces)
        guard let dash = s.firstIndex(where: { "-—－_".contains($0) }) else { return s }
        let name = s[..<dash].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? s : name
    }

    /// 按运营商分开，每家按开始时间排；家的先后按第一次出现
    public static func grouped(_ rows: [PassPlanRow]) -> [(name: String, rows: [PassPlanRow])] {
        var order: [String] = []
        var map: [String: [PassPlanRow]] = [:]
        for r in rows {
            let name = operatorName(of: r.station)
            if map[name] == nil { order.append(name) }
            map[name, default: []].append(r)
        }
        return order.map { ($0, map[$0]!.sorted { ($0.start, $0.station) < ($1.start, $1.station) }) }
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
