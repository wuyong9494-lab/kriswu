import Foundation

/// 每天的数传计划：从导出的 Excel / 复制的表格，或者手机拍的照片（网页上的表、电脑上打开的 Excel，识别出的文字块）
/// 读出每一行，按运营商分开，生成发到各家群里的表
public struct PassPlanRow: Codable, Equatable, Hashable, Sendable {
    public var orbit: String
    public var satelliteID: String
    public var satellite: String
    public var station: String
    public var start: String
    public var end: String
    public var info: String
    public var status: String
    /// 这一行每一列原来的字（和读到的那张表的列一一对应，见 PassPlan.Layout）：发出去的表照原样
    public var cells: [String]
    /// 这一行在照片里的位置（发原图时从照片上裁这一条）；从表格文件读的、补的没有
    public var region: PassPlan.Region?

    public init(orbit: String = "", satelliteID: String = "", satellite: String = "", station: String = "",
                start: String = "", end: String = "", info: String = "", status: String = "", cells: [String] = [],
                region: PassPlan.Region? = nil) {
        self.orbit = orbit
        self.satelliteID = satelliteID
        self.satellite = satellite
        self.station = station
        self.start = start
        self.end = end
        self.info = info
        self.status = status
        self.cells = cells
        self.region = region
    }
}

extension PassPlanRow {
    /// 认得出含义的那几列整理过的值（序号不算，返回 nil）
    func value(_ column: PassPlan.Column) -> String? {
        switch column {
        case .orbit: return orbit
        case .satelliteID: return satelliteID
        case .satellite: return satellite
        case .station: return station
        case .start: return start
        case .end: return end
        case .info: return info
        case .status: return status
        case .number: return nil
        }
    }
}

public enum PassPlan {
    /// 认得出含义的列：表头里出现这些字就是这一列（先认长的，「卫星名称」不会被当成「卫星ID」）。
    /// 网页上的表和导出的 Excel 叫法不一样（圈号 / 圈次、数传开始时间 / 数传开始、数传信息 / 数传速率），都认
    public enum Column: String, CaseIterable, Sendable {
        case orbit, satelliteID, satellite, station, start, end, info, status
        /// 序号（No.）：只用来分列，发出去的表重新编
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
            case .info: return ["数传信息", "信息", "速率"]
            case .status: return ["状态"]
            case .number: return []
            }
        }
    }

    /// 这个表头格子是哪一列；认不出含义（创建时间、是否应急……）返回 nil
    public static func column(forHeader text: String) -> Column? {
        let t = text.lowercased().filter { !$0.isWhitespace }
        guard !t.isEmpty else { return nil }
        if ["no", "no.", "序号"].contains(t) { return .number }
        if t.contains("卫星") && t.contains("id") { return .satelliteID }
        // 导出的 Excel 里那一列就叫「卫星」（写的是卫星代号）
        if t == "卫星" { return .satellite }
        return Column.allCases.first { c in c.headerWords.contains { t.contains($0) } }
    }

    /// 读到的那张表有哪几列：表头原来写的字、是哪一列（认不出含义的是 nil，原样带着）、在照片里的左右位置（0–1；表格文件里是第几列）。
    /// 往下翻着连拍时，后面几张拍不到表头，就用前一张的
    public struct Layout: Equatable, Sendable {
        public struct Slot: Equatable, Sendable {
            public var label: String
            public var column: Column?
            public var x: Double

            public init(label: String, column: Column?, x: Double) {
                self.label = label
                self.column = column
                self.x = x
            }
        }

        public var slots: [Slot]

        public init(slots: [Slot]) { self.slots = slots }

        /// 「是否应急」那一列（导出的 Excel 里有，网页上的表没有）
        public var emergencyIndex: Int? {
            slots.firstIndex { $0.label.filter { !$0.isWhitespace }.contains("应急") }
        }

        /// 填「是 / 不是」的列（是否应急、是否重点保障）
        func isYesNo(_ i: Int) -> Bool { slots[i].label.trimmingCharacters(in: .whitespaces).hasPrefix("是否") }

        /// 表头一个个认：同一种列出现两次，后面那个当作认不出含义的列
        init(labels: [(String, Double)]) {
            var used = Set<Column>()
            slots = labels.map { label, x in
                var c = PassPlan.column(forHeader: label)
                // 拍的是 Excel：表头那一行最左边是行号「1」，当序号（发出去的表重新编）
                let trimmed = label.trimmingCharacters(in: .whitespaces)
                if c == nil, !trimmed.isEmpty, trimmed.allSatisfy({ ("0"..."9").contains($0) }) { c = .number }
                if let found = c, !used.insert(found).inserted { c = nil }
                return Slot(label: label.trimmingCharacters(in: .whitespaces), column: c, x: x)
            }
        }

        /// 有哪几种认得出的列
        public var columns: Set<Column> { Set(slots.compactMap(\.column)) }
    }

    /// 照片里的一条（一行、表头那一行）：中线 y = y0 + slope·x，上下各占 height 的一半，左右从 left 到 right
    /// （都是整张照片的 0–1，y 从上往下）。拍斜了每行斜得不一样，各行各算。page：第几张照片
    public struct Region: Codable, Equatable, Hashable, Sendable {
        public var page: Int
        public var y0: Double
        public var slope: Double
        public var height: Double
        public var left: Double
        public var right: Double

        public init(page: Int = 0, y0: Double, slope: Double, height: Double, left: Double, right: Double) {
            self.page = page
            self.y0 = y0
            self.slope = slope
            self.height = height
            self.left = left
            self.right = right
        }
    }

    /// 读一次的结果：每一行、读到的那张表的列（没认出表头时是 nil）。
    /// 从照片读的还有：表头那一条在照片里的位置，和每一条（表头、每一行）从照片上裁下来扶正的图（JPEG，发原图用）
    public struct Reading: Equatable, Sendable {
        public var rows: [PassPlanRow]
        public var layout: Layout?
        public var header: Region?
        public var strips: [Region: Data]

        public init(rows: [PassPlanRow], layout: Layout?, header: Region? = nil, strips: [Region: Data] = [:]) {
            self.rows = rows
            self.layout = layout
            self.header = header
            self.strips = strips
        }
    }

    // MARK: - 从表格读（Excel、复制的文字）

    /// 第一行认得出三列以上的是表头，下面每行是一条；空行、表头重复的行跳过
    public static func rows(fromTable table: [[String]]) -> [PassPlanRow] {
        readTable(table).rows
    }

    public static func readTable(_ table: [[String]]) -> Reading {
        guard let headerIndex = table.firstIndex(where: { row in Set(row.compactMap(column(forHeader:))).count >= 3 }) else {
            return Reading(rows: [], layout: nil)
        }
        // 表头空着的列不要
        let kept = table[headerIndex].indices.filter { !table[headerIndex][$0].trimmingCharacters(in: .whitespaces).isEmpty }
        let layout = Layout(labels: kept.map { (table[headerIndex][$0], Double($0)) })
        let rows = table[(headerIndex + 1)...].compactMap { cells -> PassPlanRow? in
            let values = kept.map { $0 < cells.count ? cells[$0].trimmingCharacters(in: .whitespacesAndNewlines) : "" }
            return row(cells: values, layout: layout)
        }
        return Reading(rows: rows, layout: layout)
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
        read(boxes).rows
    }

    /// 同上，另外返回读到的那张表的列；这张没拍到表头时用 fallback（前一张的列，当作没有倾斜）。
    /// 表头那一排上认不出含义的格子（创建时间、是否应急……）也算一列：它们下面的字归它们，不会串进旁边的列
    public static func read(_ boxes: [TextBox], fallback: Layout? = nil) -> Reading {
        let recognized = boxes.compactMap { b in column(forHeader: b.text).map { (box: b, column: $0) } }
        let heights = boxes.map(\.height).sorted()
        let lineHeight = heights.isEmpty ? 0.02 : heights[heights.count / 2]
        let body: [TextBox]
        let layout: Layout
        /// 每一列表头在照片里的高低（往下数每一行时，各列从这个高低差开始跟）；用前一张的列时不知道，当作一样高
        let headerY: [Double]?
        var header: Region?
        if let top = headerRow(recognized) {
            let s = tilt(top.map(\.box))
            let headerLevel = top.map { $0.box.midY - s * $0.box.midX }.reduce(0, +) / Double(top.count)
            // 表头那一排的高低差：表头的字一般比表里的大
            let tolerance = max(lineHeight, top.map(\.box.height).reduce(0, +) / Double(top.count)) * 0.6
            let headerBoxes = boxes.filter { abs($0.midY - s * $0.midX - headerLevel) < tolerance }.sorted { $0.x < $1.x }
            body = boxes.filter { b in b.midY - s * b.midX > headerLevel + tolerance && !headerBoxes.contains(b) }
            layout = Layout(labels: headerBoxes.map { ($0.text, $0.midX) })
            headerY = headerBoxes.map(\.midY)
            let tallest = headerBoxes.map(\.height).max() ?? lineHeight
            header = Region(y0: headerLevel, slope: s, height: max(tallest * 1.7, lineHeight * 2), left: 0, right: 1)
        } else if let fallback {
            body = boxes
            layout = fallback
            headerY = nil
        } else {
            return Reading(rows: [], layout: nil)
        }
        // 表的左右边：最左、最右两列再往外；表里的字更靠外就到那里，只是最靠外的几块不算（照片里表外面零星的字）
        let xs = layout.slots.map(\.x).sorted()
        let spacing = xs.count > 1 ? (xs[xs.count - 1] - xs[0]) / Double(xs.count - 1) : 0.1
        // 往外多留一列：最边上的列表头没认出来（「状态」那种带框的小标签）也裁得进去
        var left = (xs.first ?? 0) - spacing * 1.5
        var right = (xs.last ?? 1) + spacing * 1.5
        if body.count >= 20 {
            let lefts = body.map(\.x).sorted(), rights = body.map { $0.x + $0.width }.sorted()
            left = min(left, lefts[lefts.count * 3 / 100] - 0.01)
            right = max(right, rights[rights.count * 97 / 100] + 0.01)
        }
        left = max(0, left)
        right = min(1, right)
        header?.left = left
        header?.right = right
        let rows = assemble(body, layout: layout, headerY: headerY, lineHeight: lineHeight, span: (left, right))
        // 表头那一条往下不超过第一行的上边（不带进半截第一行）
        let middle = (left + right) / 2
        if var h = header, let first = rows.compactMap(\.region).min(by: { $0.y0 + $0.slope * middle < $1.y0 + $1.slope * middle }) {
            let center = h.y0 + h.slope * middle
            let top = center - h.height / 2
            let bottom = min(center + h.height / 2, first.y0 + first.slope * middle - first.height / 2)
            if bottom > top {
                h.y0 += (top + bottom) / 2 - center
                h.height = bottom - top
                header = h
            }
        }
        return Reading(rows: rows, layout: layout, header: header)
    }

    /// 把表里的字拼成一行行。
    /// 手机拍屏幕会梯形变形：上面几行往一边斜、下面几行往另一边斜，用一个角度扶不正（密密麻麻的 Excel 下面几行会串行）。
    /// 所以先按左右分到各列，每列里按上下分成一格格；再以「地面站」那一列为准（每行都有），一列列往右对：
    /// 每往下一行，记下这一列比地面站高多少低多少，跟着慢慢变，斜度一点点变也跟得上
    static func assemble(_ body: [TextBox], layout: Layout, headerY: [Double]?, lineHeight: Double,
                         span: (left: Double, right: Double) = (0, 1)) -> [PassPlanRow] {
        let slots = layout.slots
        guard !slots.isEmpty else { return [] }
        // 按左右分到最近的那一列
        var perSlot = [[TextBox]](repeating: [], count: slots.count)
        for b in body {
            let i = slots.indices.min { abs(slots[$0].x - b.midX) < abs(slots[$1].x - b.midX) }!
            perSlot[i].append(b)
        }
        // 每一列里上下挨着的算一格（日期、时间被认成两块的拼在一格）
        struct Cell { var boxes: [TextBox]; var y: Double }
        let cells: [[Cell]] = perSlot.map { boxes in
            var list: [Cell] = []
            for b in boxes.sorted(by: { $0.midY < $1.midY }) {
                if var last = list.last, abs(b.midY - last.y) < lineHeight * 0.6 {
                    last.boxes.append(b)
                    last.y = last.boxes.map(\.midY).reduce(0, +) / Double(last.boxes.count)
                    list[list.count - 1] = last
                } else {
                    list.append(Cell(boxes: [b], y: b.midY))
                }
            }
            return list
        }
        // 以地面站那一列为准：它的每一格是一行
        let ref = slots.firstIndex { $0.column == .station } ?? cells.indices.max { cells[$0].count < cells[$1].count }!
        let anchors = cells[ref]
        guard !anchors.isEmpty else { return [] }
        let gaps = zip(anchors.dropFirst(), anchors).map { $0.y - $1.y }.sorted()
        let pitch = gaps.isEmpty ? lineHeight * 2 : gaps[gaps.count / 2]
        let tolerance = max(lineHeight * 0.5, pitch * 0.45)
        // 别的列一行行对上去：预计的位置 = 地面站那格 + 这一列现在的高低差
        var matched = [[Int?]](repeating: [Int?](repeating: nil, count: anchors.count), count: slots.count)
        for s in slots.indices where s != ref {
            var offset = headerY.map { $0[s] - $0[ref] } ?? 0
            var used = Set<Int>()
            for (r, anchor) in anchors.enumerated() {
                let predicted = anchor.y + offset
                guard let best = cells[s].indices.filter({ !used.contains($0) })
                        .min(by: { abs(cells[s][$0].y - predicted) < abs(cells[s][$1].y - predicted) }),
                      abs(cells[s][best].y - predicted) < tolerance else { continue }
                used.insert(best)
                matched[s][r] = best
                offset = (offset + (cells[s][best].y - anchor.y)) / 2
            }
        }
        return anchors.indices.compactMap { r -> PassPlanRow? in
            // 这一行所有的字：算这一行在照片里的位置（发原图时裁这一条）
            let rowBoxes = anchors[r].boxes + slots.indices.flatMap { s in matched[s][r].map { cells[s][$0].boxes } ?? [] }
            let slope = tilt(rowBoxes)
            let meanX = rowBoxes.map(\.midX).reduce(0, +) / Double(rowBoxes.count)
            let meanY = rowBoxes.map(\.midY).reduce(0, +) / Double(rowBoxes.count)
            let region = Region(y0: meanY - slope * meanX, slope: slope, height: max(pitch, lineHeight * 1.4),
                                left: span.left, right: span.right)
            let values = slots.indices.map { s -> String in
                let boxes: [TextBox]
                if s == ref {
                    boxes = anchors[r].boxes
                } else if let c = matched[s][r] {
                    boxes = cells[s][c].boxes
                } else {
                    return ""
                }
                if slots[s].column?.isSingleValue == true {
                    return singleValue(boxes, center: slots[s].x, gap: lineHeight * 0.8)
                }
                return boxes.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ")
            }
            var found = row(cells: values, layout: layout)
            found?.region = region
            return found
        }
    }

    /// 一格里只该有一个值（圈号、卫星、地面站）：挨得近的几块（一个名字被认成了两段）拼起来；
    /// 隔得远的（挤进来的序号、Excel 的行号）只留离表头最近的那一段
    static func singleValue(_ boxes: [TextBox], center: Double, gap: Double) -> String {
        var groups: [[TextBox]] = []
        for b in boxes.sorted(by: { $0.x < $1.x }) {
            if let last = groups.last?.last, b.x - (last.x + last.width) <= gap {
                groups[groups.count - 1].append(b)
            } else {
                groups.append([b])
            }
        }
        func mid(_ g: [TextBox]) -> Double { (g.first!.x + g.last!.x + g.last!.width) / 2 }
        return groups.min { abs(mid($0) - center) < abs(mid($1) - center) }?.map(\.text).joined() ?? ""
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
    static func row(cells: [String], layout: Layout) -> PassPlanRow? {
        var cells = cells
        // 「是否……」那几列的字紧挨着左边一列（Excel 里左边那格的字被截断，右边紧跟着「是」），常被认成一块（「通道2:900是」）：
        // 这一格空着、左边那格末尾是「是 / 不是 / 否」，就挪回来
        for i in layout.slots.indices.dropFirst() where i < cells.count && layout.isYesNo(i) && !layout.isYesNo(i - 1) {
            guard cells[i].trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let left = cells[i - 1].trimmingCharacters(in: .whitespaces)
            if let answer = ["不是", "是", "否"].first(where: { left.hasSuffix($0) && left.count > $0.count }) {
                cells[i] = answer
                cells[i - 1] = String(left.dropLast(answer.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        var values: [Column: String] = [:]
        for (i, slot) in layout.slots.enumerated() where i < cells.count {
            if let c = slot.column { values[c] = cells[i] }
        }
        guard var r = row(from: values) else { return nil }
        r.cells = cells
        return r
    }

    static func row(from values: [Column: String]) -> PassPlanRow? {
        var r = PassPlanRow(orbit: values[.orbit] ?? "", satelliteID: values[.satelliteID] ?? "",
                            satellite: values[.satellite] ?? "", station: values[.station] ?? "",
                            start: normalizedTime(values[.start] ?? ""), end: normalizedTime(values[.end] ?? ""),
                            info: values[.info] ?? "", status: values[.status] ?? "")
        r.station = r.station.replacingOccurrences(of: "—", with: "-").replacingOccurrences(of: "－", with: "-")
        // 拍 Excel 时左边的行号常和卫星编号拼成一块（「3XA102C」）：编号以字母开头，前面的数字去掉
        for key in [\PassPlanRow.satellite, \PassPlanRow.satelliteID] {
            r[keyPath: key] = r[keyPath: key].replacingOccurrences(of: #"^\d{1,4}(?=[A-Z]{2})"#, with: "", options: .regularExpression)
        }
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
        func format(_ p: [Int]) -> String? {
            guard p.count == 6, (1...12).contains(p[1]), (1...31).contains(p[2]), p[3] < 24, p[4] < 60, p[5] < 60 else { return nil }
            return String(format: "%04d-%02d-%02d %02d:%02d:%02d", p[0], p[1], p[2], p[3], p[4], p[5])
        }
        if let re = try? NSRegularExpression(pattern: pattern),
           let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
            let parts = (1...6).map { i in Range(m.range(at: i), in: s).flatMap { Int(s[$0]) } ?? (i == 6 ? 0 : -1) }
            if let t = format(parts) { return t }
        }
        // 拍屏幕时「-」「:」常认丢（「2026 10-27 22:05:25」「2026-10 28 075658」）：只看数字，正好 14 位（或没有秒的 12 位）就按位拆开
        let digits = s.filter { ("0"..."9").contains($0) }.compactMap(\.wholeNumberValue)
        guard s.hasPrefix("20"), digits.count == 14 || digits.count == 12 else { return s }
        func number(_ from: Int, _ count: Int) -> Int { digits[from..<(from + count)].reduce(0) { $0 * 10 + $1 } }
        let parts = [number(0, 4), number(4, 2), number(6, 2), number(8, 2), number(10, 2), digits.count == 14 ? number(12, 2) : 0]
        // 认出来不是有效的时间（「28:27:14」）：原样留着，页面上标黄让人核对
        return format(parts) ?? s
    }

    // MARK: - 长图分段认、两种认法挑一个

    /// 很长的图分段认：一段（照片里从上往下的像素范围）和它要留的那一块（整张图从上往下的 0–1）
    public struct Strip: Equatable, Sendable {
        public var top: Int
        public var height: Int
        /// 中心落在这里面的字才算这一段的：重叠的部分上下两段一段一半，同一行不会认出两遍
        public var keep: Range<Double>

        public init(top: Int, height: Int, keep: Range<Double>) {
            self.top = top
            self.height = height
            self.keep = keep
        }
    }

    /// 高的图（长截图、拼起来的长图）切成上下重叠的几段：每段高不超过宽的 1.4 倍（字相对这一段够大，不会被当成太小跳过），
    /// 相邻两段重叠一段高的 1/5（被切开的那行在另一段里是整的）。不高的图就一段
    public static func strips(width: Int, height: Int) -> [Strip] {
        let size = max(1, width * 7 / 5)
        let overlap = size / 5
        guard height > size + overlap else { return [Strip(top: 0, height: height, keep: -Double.infinity..<Double.infinity)] }
        var spans: [(top: Int, bottom: Int)] = []
        var top = 0
        while true {
            let bottom = min(top + size, height)
            spans.append((top, bottom))
            if bottom >= height { break }
            top = bottom - overlap
        }
        let h = Double(height)
        return spans.indices.map { i in
            let from = i == 0 ? -Double.infinity : Double(spans[i].top + spans[i - 1].bottom) / 2 / h
            let to = i == spans.count - 1 ? Double.infinity : Double(spans[i + 1].top + spans[i].bottom) / 2 / h
            return Strip(top: spans[i].top, height: spans[i].bottom - spans[i].top, keep: from..<to)
        }
    }

    /// 一段里认出的字（位置是这一段的 0–1）换成整张图的位置，只留这一段该留的
    public static func place(_ boxes: [TextBox], in strip: Strip, imageHeight: Int) -> [TextBox] {
        let h = Double(imageHeight), top = Double(strip.top), sh = Double(strip.height)
        return boxes.compactMap { b in
            let placed = TextBox(text: b.text, x: b.x, y: (top + b.y * sh) / h, width: b.width, height: b.height * sh / h)
            return strip.keep.contains(placed.midY) ? placed : nil
        }
    }

    /// 这一页的列和发出去的表用的列不一样（另一张照片的表头、另一种认法）：按表头的字把每行的格子挪过去。
    /// 认得出含义的列用整理过的值；target 里有、这一页没有的列空着
    public static func remap(_ rows: [PassPlanRow], from source: Layout, to target: Layout) -> [PassPlanRow] {
        guard source != target else { return rows }
        func key(_ slot: Layout.Slot) -> String { slot.label.filter { !$0.isWhitespace } }
        var index: [String: Int] = [:]
        for (i, slot) in source.slots.enumerated() where index[key(slot)] == nil { index[key(slot)] = i }
        return rows.map { row in
            var moved = row
            moved.cells = target.slots.map { slot in
                if let typed = slot.column.flatMap(row.value) { return typed }
                guard let i = index[key(slot)], i < row.cells.count else { return "" }
                return row.cells[i]
            }
            return moved
        }
    }

    /// 读得好不好（同一张照片两种认法挑一个）：认出的行越多越好，可能认错的行（时间不全、站名对不上对照表……）只算一小半
    public static func score(_ reading: Reading, rules: [OperatorRule] = []) -> Double {
        reading.rows.reduce(0) { $0 + (problems($1, rules: rules, layout: reading.layout).isEmpty ? 1 : 0.3) }
    }

    /// 给文字识别的词库：表头常见的叫法，加上对照表里的运营商名和站名开头（认得准一些）
    public static func vocabulary(_ rules: [OperatorRule]) -> [String] {
        // 表头的叫法是小写的（比对用），「卫星id」换成大写的写法
        let headers = Column.allCases.flatMap(\.headerWords).filter { !$0.contains("id") }
            + ["卫星ID", "数传开始时间", "数传结束时间", "数传速率", "创建时间", "是否应急", "是否重点保障", "等待数传", "通道"]
        var seen = Set<String>()
        return (headers + rules.flatMap { [$0.name] + $0.prefixes })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
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

    /// 这一条可能认错的地方（页面上标出来，让人核对）；没有返回空。
    /// layout：读到的那张表有哪几列（导出的 Excel 没有结束时间，就不说「没有结束时间」）
    public static func problems(_ r: PassPlanRow, rules: [OperatorRule] = [], layout: Layout? = nil) -> [String] {
        let has = { (c: Column) in layout.map { $0.columns.contains(c) } ?? true }
        var list: [String] = []
        let time = #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#
        func isTime(_ s: String) -> Bool {
            guard s.range(of: time, options: .regularExpression) != nil else { return false }
            // 格式对、数不对（「28:27:14」）也算没认全
            let n = s.split(whereSeparator: { "- :".contains($0) }).compactMap { Int($0) }
            return n.count == 6 && (1...12).contains(n[1]) && (1...31).contains(n[2]) && n[3] < 24 && n[4] < 60 && n[5] < 60
        }
        if !isTime(r.start) { list.append("开始时间没认全") }
        if r.end.isEmpty {
            if has(.end) { list.append("没有结束时间") }
        } else if !isTime(r.end) {
            list.append("结束时间没认全")
        } else if isTime(r.start), r.end <= r.start {
            list.append("结束比开始还早")
        }
        if operatorName(of: r.station, rules: rules) == nil { list.append("分不出是哪家（运营商对照表里没有这个站）") }
        if !r.orbit.isEmpty, !r.orbit.allSatisfy(\.isNumber) { list.append("圈号不全是数字") }
        if r.satellite.isEmpty, has(.satellite) { list.append("没认出卫星名称") }
        if layout?.emergencyIndex != nil, emergency(r, layout: layout) == nil {
            list.append("是否应急没认出来（发的时候按不是应急算）")
        }
        return list
    }

    // MARK: - 应急

    /// 这一条是不是应急计划：看「是否应急」那一列；没有这一列返回 nil，认不出「是 / 不是」也返回 nil
    public static func emergency(_ r: PassPlanRow, layout: Layout?) -> Bool? {
        guard let i = layout?.emergencyIndex else { return nil }
        let value = i < r.cells.count ? r.cells[i].filter { !$0.isWhitespace } : ""
        if ["是", "是的", "Y", "y", "YES", "Yes", "yes", "√", "✓"].contains(value) { return true }
        if ["不是", "否", "N", "n", "NO", "No", "no", "×"].contains(value) { return false }
        return nil
    }

    /// 发图时下面那句话：这一家里有应急计划用 urgent，没有用 normal
    public static func caption(_ rows: [PassPlanRow], layout: Layout?, normal: String, urgent: String) -> String {
        rows.contains { emergency($0, layout: layout) == true } ? urgent : normal
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

    /// 分不出是哪家的归到这一组，页面上让人指定（对照表里没有这个站；对照表没填时是站名里没有「-」的）
    public static let unassigned = "分不出是哪家"

    /// 地面站「-」前面的名字（「甲站-北区01」→「甲站」）；没有「-」返回 nil
    public static func operatorName(of station: String) -> String? {
        let s = station.trimmingCharacters(in: .whitespaces)
        guard let dash = s.firstIndex(where: { "-—－_".contains($0) }) else { return nil }
        let name = s[..<dash].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// 是哪家：按对照表（站名开头对上最长的那个前缀）。对照表还没填时先按「-」前面的名字分；
    /// 填了以后对不上的就是 nil（不去猜，页面上提示「分不出是哪家」，免得「某某-测试」这种站被当成一家新的）
    public static func operatorName(of station: String, rules: [OperatorRule]) -> String? {
        guard !rules.isEmpty else { return operatorName(of: station) }
        let s = station.filter { !$0.isWhitespace }
        return rules.flatMap { rule in rule.prefixes.map { (rule.name, $0.filter { !$0.isWhitespace }) } }
            .filter { !$0.1.isEmpty && s.hasPrefix($0.1) }
            .max { $0.1.count < $1.1.count }?.0
    }

    /// 分不出是哪家的站，最像哪家：站名开头认错了一个字（「驭星」认成「取星」），和对照表里某一家的开头只差一个字
    /// （开头五个字以上的差两个）、又只像这一家。不自动算成这家（真有新站恰好差一个字会发错家），「分给哪家」时排第一个
    public static func likelyOperator(of station: String, rules: [OperatorRule]) -> String? {
        let s = Array(station.filter { !$0.isWhitespace })
        var best: (name: String, distance: Int)?
        var tied = false
        for rule in rules {
            for prefix in rule.prefixes.map({ Array($0.filter { !$0.isWhitespace }) }) where prefix.count >= 2 && s.count >= prefix.count {
                let distance = zip(s, prefix).filter { $0 != $1 }.count
                guard distance <= (prefix.count >= 5 ? 2 : 1) else { continue }
                if let current = best {
                    if distance < current.distance {
                        best = (rule.name, distance)
                        tied = false
                    } else if distance == current.distance, rule.name != current.name {
                        tied = true
                    }
                } else {
                    best = (rule.name, distance)
                }
            }
        }
        return tied ? nil : best?.name
    }

    /// 给一个对不上的站记前缀用：「-」前面的名字，没有「-」就去掉末尾的编号（「丙光北区03」→「丙光北区」）
    public static func suggestedPrefix(of station: String) -> String {
        if let name = operatorName(of: station) { return name }
        let s = station.trimmingCharacters(in: .whitespaces)
        let trimmed = s.replacingOccurrences(of: #"[\d\s]+$"#, with: "", options: .regularExpression)
        return trimmed.isEmpty ? s : trimmed
    }

    /// 按运营商分开，每家里的先后照网页上的顺序（不重排，序号和原表对得上）；
    /// 家的先后按对照表里的顺序，表里没有的按第一次出现，分不出的放最后
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
            .map { ($0, map[$0]!) }
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

    /// 发到群里的表：表头、列的先后照网页上的（No.、圈号、卫星ID、卫星名称、地面站、数传开始时间、数传结束时间、
    /// 数传信息、状态），时间写全；这几条里整列都是空的（没拍到、网页上没有）就不要这一列。No. 是这一家里的第几条
    public static func table(_ rows: [PassPlanRow], layout: Layout? = nil) -> (headers: [String], cells: [[String]]) {
        if let layout { return table(rows, layout: layout) }
        let columns: [(String, (PassPlanRow) -> String)] = [
            ("圈号", \.orbit), ("卫星ID", \.satelliteID), ("卫星名称", \.satellite), ("地面站", \.station),
            ("数传开始时间", \.start), ("数传结束时间", \.end), ("数传信息", \.info), ("状态", \.status),
        ]
        let used = columns.filter { column in rows.contains { !column.1($0).isEmpty } }
        let cells = rows.enumerated().map { i, row in ["\(i + 1)"] + used.map { $0.1(row) } }
        return (["No."] + used.map(\.0), cells)
    }

    /// 照读到的那张表：同样的表头、同样的列（认不出含义的列原样带上），前面一列 No. 是这一家里的第几条。
    /// 认得出含义的列用整理过的值（改过的、补的一条也对得上），其他列用原来的字
    private static func table(_ rows: [PassPlanRow], layout: Layout) -> (headers: [String], cells: [[String]]) {
        let kept = layout.slots.indices.filter { layout.slots[$0].column != .number }
        func value(_ row: PassPlanRow, _ i: Int) -> String {
            layout.slots[i].column.flatMap(row.value) ?? (i < row.cells.count ? row.cells[i] : "")
        }
        let cells = rows.enumerated().map { n, row in ["\(n + 1)"] + kept.map { value(row, $0) } }
        return (["No."] + kept.map { layout.slots[$0].label }, cells)
    }

    /// 标题：「10月27日数传计划（甲站）共 3 条」（跨了几天的不写日期）
    public static func title(name: String, rows: [PassPlanRow]) -> String {
        let days = Set(rows.map { String($0.start.prefix(10)) }).sorted()
        if days.count == 1, let d = DayKey(string: days[0]) {
            return "\(d.month)月\(d.day)日数传计划（\(name)）共 \(rows.count) 条"
        }
        return "数传计划（\(name)）共 \(rows.count) 条"
    }

    /// 发到群里的一段话：标题、表头、每条一行，和图上的表一样
    /// caption：最后一行的那句话（「麻烦确认一下数传计划」），空的不加
    public static func message(name: String, rows: [PassPlanRow], layout: Layout? = nil, caption: String = "") -> String {
        let t = table(rows, layout: layout)
        let lines = [title(name: name, rows: rows), t.headers.joined(separator: "  ")]
            + t.cells.map { $0.filter { !$0.isEmpty }.joined(separator: "  ") }
            + (caption.isEmpty ? [] : [caption])
        return lines.joined(separator: "\n")
    }

    /// 「2026-10-27 22:57:51」→「22:57:51」；不是这个格式的原样
    static func shortTime(_ s: String) -> String {
        s.count == 19 && s.dropFirst(10).first == " " ? String(s.suffix(8)) : s
    }
}
