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
    /// 多次识别互相矛盾、需要对原图核实的内容。nil 兼容旧版本保存的计划；重排、合并时保留。
    public var recognitionIssues: [String]?
    /// 无表头左侧栏的独立「应急」标签。true 是文字证据；false 只用于已确认版式的无标签行或手动确认。
    public var emergencyBadge: Bool?
    /// 任一读数在状态列明确识别到 test。即使另一遍选择了别的状态文字，也不能把这条发出去。
    public var testStatusDetected: Bool?

    public init(orbit: String = "", satelliteID: String = "", satellite: String = "", station: String = "",
                start: String = "", end: String = "", info: String = "", status: String = "", cells: [String] = [],
                region: PassPlan.Region? = nil, recognitionIssues: [String]? = nil,
                emergencyBadge: Bool? = nil, testStatusDetected: Bool? = nil) {
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
        self.recognitionIssues = recognitionIssues
        self.emergencyBadge = emergencyBadge
        self.testStatusDetected = testStatusDetected
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

    // MARK: - 从表格读（Excel、复制的文字、照片中的系统表格）

    /// 第一行认得出三列以上的是表头，下面每行是一条；空行、表头重复的行跳过
    public static func rows(fromTable table: [[String]]) -> [PassPlanRow] {
        readTable(table).rows
    }

    public static func readTable(_ table: [[String]]) -> Reading {
        readTable(table, recoveringPhotoHeaders: false)
    }

    /// 系统从照片读出的表格：只恢复有明确计划上下文的 OCR 表头含义，保留原标签和单元格。
    public static func readPhotoTable(_ table: [[String]]) -> Reading {
        readTable(table, recoveringPhotoHeaders: true)
    }

    private static func readTable(_ table: [[String]], recoveringPhotoHeaders: Bool) -> Reading {
        guard let headerIndex = table.firstIndex(where: { row in Set(row.compactMap(column(forHeader:))).count >= 3 }) else {
            return Reading(rows: [], layout: nil)
        }
        // 表头空着的列不要
        let kept = table[headerIndex].indices.filter { !table[headerIndex][$0].trimmingCharacters(in: .whitespaces).isEmpty }
        let detected = Layout(labels: kept.map { (table[headerIndex][$0], Double($0)) })
        let layout = recoveringPhotoHeaders ? recoverPhotoOrbitHeader(detected) : detected
        let leading = 0..<(kept.first ?? 0)
        let hasBadges = table[(headerIndex + 1)...].contains { cells in
            leading.contains { $0 < cells.count && markerText(cells[$0]) == "应急" }
        }
        let rows = table[(headerIndex + 1)...].compactMap { cells -> PassPlanRow? in
            let values = kept.map { $0 < cells.count ? cells[$0].trimmingCharacters(in: .whitespacesAndNewlines) : "" }
            var found = row(cells: values, layout: layout)
            if hasBadges {
                found?.emergencyBadge = leading.contains { $0 < cells.count && markerText(cells[$0]) == "应急" }
            }
            return found
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

    /// 同一张照片的多轮 OCR 共用像素坐标。某轮没读到表头时，优先借用本页其他轮读到的布局。
    /// 每轮先独立找表头；有表头的保留自身布局，无表头的才重解析。整页都没有表头才沿用上一页。
    /// 借用布局不会生成虚构表头区域，也不增加文字或更改各轮顺序。
    public static func readPasses(_ passes: [[TextBox]], fallback: Layout? = nil,
                                  rules: [OperatorRule] = []) -> [Reading] {
        let originals = passes.map { read($0) }
        func isGeometric(_ layout: Layout) -> Bool {
            let positions = layout.slots.map(\.x)
            return layout.columns.contains(.station) && layout.columns.contains(.start)
                && (layout.columns.contains(.satellite) || layout.columns.contains(.satelliteID))
                && positions.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }
                && Set(positions).count == positions.count
        }
        var current: Reading?
        var bestScore = -Double.infinity
        for reading in originals {
            guard reading.header != nil, let layout = reading.layout, isGeometric(layout) else { continue }
            let candidateScore = score(reading, rules: rules)
            if candidateScore > bestScore {
                current = reading
                bestScore = candidateScore
            }
        }
        let shared = current?.layout ?? fallback.flatMap { isGeometric($0) ? $0 : nil }
        guard let shared else { return originals }
        return zip(passes, originals).map { boxes, original in
            original.header != nil ? original : read(boxes, fallback: shared, fallbackSlope: current?.header?.slope)
        }
    }

    /// 同上，另外返回读到的那张表的列；这张没拍到表头时用 fallback（前一张的列，当作没有倾斜）。
    /// 表头那一排上认不出含义的格子（创建时间、是否应急……）也算一列：它们下面的字归它们，不会串进旁边的列
    public static func read(_ boxes: [TextBox], fallback: Layout? = nil) -> Reading {
        read(boxes, fallback: fallback, fallbackSlope: nil)
    }

    /// 只有同页另一次读数提供了真实表头时才传斜率；跨页 fallback 保留原有无斜率行为。
    private static func read(_ boxes: [TextBox], fallback: Layout?, fallbackSlope: Double?) -> Reading {
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
            layout = recoverPhotoOrbitHeader(Layout(labels: headerBoxes.map { ($0.text, $0.midX) }))
            headerY = headerBoxes.map(\.midY)
            let tallest = headerBoxes.map(\.height).max() ?? lineHeight
            header = Region(y0: headerLevel, slope: s, height: max(tallest * 1.7, lineHeight * 2), left: 0, right: 1)
        } else if let fallback {
            body = boxes
            layout = fallback
            // assemble 使用表头各列的相对高度初始化匹配偏移；丢掉斜率会把密集相邻行错配。
            headerY = fallbackSlope.map { slope in layout.slots.map { $0.x * slope } }
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
        // 左侧无表头的「应急」标签单独关联到行，不能挤进 No./圈号/卫星列后被丢掉。
        let badges = leadingBadgeBoxes(body, layout: layout)
        if let badgeLeft = badges.map(\.x).min() { left = max(0, min(left, badgeLeft - lineHeight)) }
        header?.left = left
        let content = body.filter { !badges.contains($0) }
        let assembled = assemble(content, layout: layout, headerY: headerY, lineHeight: lineHeight, span: (left, right))
        let rows = boundedRegions(applyingRowMarkers(assembled, markers: body, layout: layout))
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

    /// 照片 OCR 实测会把「圈号」认成「圖号」。只在同一表头里有完整计划上下文、且候选唯一时恢复含义。
    /// 保留原标签和位置；文件/文本表格不经过这里，普通「图号」也不当作圈号。
    private static func recoverPhotoOrbitHeader(_ layout: Layout) -> Layout {
        let columns = layout.columns
        guard !columns.contains(.orbit), columns.contains(.station), columns.contains(.start),
              columns.contains(.satellite) || columns.contains(.satelliteID) else { return layout }
        let candidates = layout.slots.indices.filter {
            layout.slots[$0].column == nil && layout.slots[$0].label.filter { !$0.isWhitespace } == "圖号"
        }
        guard candidates.count == 1, let index = candidates.first else { return layout }
        var recovered = layout
        recovered.slots[index].column = .orbit
        return recovered
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

    /// 同一张图里无表头左侧「应急」、状态列 test 的明确文字证据。
    /// 必须落在对应栏、且只对应一条倾斜行；其他列的同名文字和背景颜色都不参与判断。
    public static func applyingRowMarkers(_ rows: [PassPlanRow], markers: [TextBox], layout: Layout) -> [PassPlanRow] {
        var result = rows
        let badges = leadingBadgeBoxes(markers, layout: layout)
        let ordered = layout.slots.sorted { $0.x < $1.x }
        let statusIndex = ordered.firstIndex { $0.column == .status }
        let testMarkers: [TextBox]
        if let index = statusIndex {
            let left = index > 0 ? (ordered[index - 1].x + ordered[index].x) / 2 : 0
            let right = index + 1 < ordered.count ? (ordered[index].x + ordered[index + 1].x) / 2 : 1
            testMarkers = markers.filter { markerText($0.text) == "test" && $0.midX >= left && $0.midX <= right }
        } else {
            testMarkers = []
        }
        func matches(_ marker: TextBox) -> [Int] {
            result.indices.filter { i in
                guard let region = result[i].region, region.height > 0,
                      marker.midX >= region.left, marker.midX <= region.right else { return false }
                return abs(marker.midY - (region.y0 + region.slope * marker.midX)) < region.height * 0.45
            }
        }
        func nearby(_ marker: TextBox) -> [Int] {
            let eligible = result.indices.filter { i in
                result[i].region.map { marker.midX >= $0.left && marker.midX <= $0.right } ?? false
            }
            let levels = eligible.compactMap { i -> (index: Int, y: Double, half: Double)? in
                guard let region = result[i].region else { return nil }
                return (i, region.y0 + region.slope * marker.midX, region.height / 2)
            }
            guard let top = levels.map({ $0.y - $0.half }).min(), let bottom = levels.map({ $0.y + $0.half }).max(),
                  marker.midY >= top, marker.midY <= bottom else { return [] }
            return Array(levels.sorted { abs($0.y - marker.midY) < abs($1.y - marker.midY) }.prefix(2).map(\.index))
        }
        var uncertainBadges = Set<Int>()
        for badge in badges {
            let matched = matches(badge)
            if matched.count == 1, let i = matched.first {
                result[i].emergencyBadge = true
            } else {
                for i in matched.isEmpty ? nearby(badge) : matched {
                    uncertainBadges.insert(i)
                    result[i] = retainingIssues(result[i], adding: ["左侧应急标签与行位置对应不清，请核对原图"])
                }
            }
        }
        // 看到了这张图的左侧标签版式，且这一行的左栏也完整可见，才把无标签记为普通计划。
        if result.contains(where: { $0.emergencyBadge == true }), let boundary = leadingBadgeBoundary(layout) {
            for i in result.indices where result[i].emergencyBadge == nil && !uncertainBadges.contains(i) {
                if let region = result[i].region, region.left < boundary { result[i].emergencyBadge = false }
            }
        }
        for marker in testMarkers {
            let matched = matches(marker)
            if matched.count == 1, let i = matched.first {
                result[i].testStatusDetected = true
                if result[i].status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result[i].status = "test"
                } else if markerText(result[i].status) != "test" {
                    result[i] = retainingIssues(result[i], adding: ["状态识别不一致（含 test），已排除发送"])
                }
            } else {
                for i in matched.isEmpty ? nearby(marker) : matched {
                    result[i] = retainingIssues(result[i], adding: ["test 状态与行位置对应不清，请核对原图"])
                }
            }
        }
        return result
    }

    /// 状态窄栏的普通状态补读。先由 applyingRowMarkers 保留 test 证据，再用本方法补空值。
    /// 只接受完整、已知的状态文字；必须完整落在状态栏内并唯一对应同一张照片的一条倾斜行。
    /// 非空原值、test 证据和其他核对提示不会被补读覆盖；歧义或冲突继续留给用户核对。
    public static func applyingStatusReread(_ rows: [PassPlanRow], readings: [TextBox], layout: Layout) -> [PassPlanRow] {
        let ordered = layout.slots.sorted { $0.x < $1.x }
        guard ordered.allSatisfy({ $0.x.isFinite && $0.x >= 0 && $0.x <= 1 }),
              ordered.filter({ $0.column == .status }).count == 1,
              let statusIndex = ordered.firstIndex(where: { $0.column == .status }),
              let cellIndex = layout.slots.firstIndex(where: { $0.column == .status }),
              Set(rows.compactMap { $0.region?.page }).count <= 1 else { return rows }
        let left = statusIndex > 0 ? (ordered[statusIndex - 1].x + ordered[statusIndex].x) / 2 : 0
        let right = statusIndex + 1 < ordered.count ? (ordered[statusIndex].x + ordered[statusIndex + 1].x) / 2 : 1
        guard right > left else { return rows }
        let markers = readings.filter {
            isRecognizedPlanStatus($0.text) && !isTestStatus($0.text)
                && $0.x.isFinite && $0.y.isFinite && $0.width.isFinite && $0.height.isFinite
                && $0.width > 0 && $0.height > 0 && $0.x >= left && $0.x + $0.width <= right
        }
        var result = rows
        var values: [Int: Set<String>] = [:]
        var uncertain = Set<Int>()
        for marker in markers {
            let levels = rows.indices.compactMap { i -> (index: Int, center: Double, half: Double)? in
                guard let region = rows[i].region, region.y0.isFinite, region.slope.isFinite,
                      region.height.isFinite, region.height > 0,
                      marker.x >= region.left, marker.x + marker.width <= region.right else { return nil }
                return (i, region.y0 + region.slope * marker.midX, region.height / 2)
            }
            let matches = levels.filter { abs($0.center - marker.midY) < $0.half * 0.9 }
            if matches.count == 1, let match = matches.first, let region = rows[match.index].region {
                let atLeft = region.y0 + region.slope * marker.x
                let atRight = region.y0 + region.slope * (marker.x + marker.width)
                if marker.y >= min(atLeft, atRight) - match.half,
                   marker.y + marker.height <= max(atLeft, atRight) + match.half {
                    values[match.index, default: []].insert(markerText(marker.text))
                    continue
                }
            }
            // 文字在两行之间、跨行、或同时落进两行时，不挑最近的一行填值。
            let affected: [Int]
            if matches.count > 1 {
                affected = matches.map(\.index)
            } else if let top = levels.map({ $0.center - $0.half }).min(),
                      let bottom = levels.map({ $0.center + $0.half }).max(),
                      marker.midY >= top, marker.midY <= bottom {
                affected = Array(levels.sorted { abs($0.center - marker.midY) < abs($1.center - marker.midY) }
                    .prefix(2).map(\.index))
            } else {
                affected = []
            }
            uncertain.formUnion(affected)
        }
        for i in uncertain {
            result[i] = retainingIssues(result[i], adding: ["状态补读与行位置对应不清，请核对原图"])
        }
        for (i, found) in values where !uncertain.contains(i) {
            if isExcludedFromSending(result[i]) {
                result[i] = retainingIssues(result[i], adding: ["状态识别不一致（含 test），已排除发送"])
                continue
            }
            guard found.count == 1, let value = found.first else {
                result[i] = retainingIssues(result[i], adding: ["状态补读结果不一致，请核对原图"])
                continue
            }
            let original = markerText(result[i].status)
            if !original.isEmpty {
                if original != value {
                    result[i] = retainingIssues(result[i], adding: ["状态补读与原识别不一致，请核对原图"])
                }
                continue
            }
            // cells 是整理表格的原文出口，也需同步；已有的非空单元格不能被静默改写。
            if result[i].cells.indices.contains(cellIndex), !markerText(result[i].cells[cellIndex]).isEmpty,
               markerText(result[i].cells[cellIndex]) != value {
                result[i] = retainingIssues(result[i], adding: ["状态补读与原识别不一致，请核对原图"])
                continue
            }
            result[i].status = value
            if !result[i].cells.isEmpty {
                while result[i].cells.count <= cellIndex { result[i].cells.append("") }
                result[i].cells[cellIndex] = value
            }
        }
        return result
    }

    /// 裁原图前，所有行（包括不发送的 test 行）一起限定边界，避免邻行文字被裁进可发送条目。
    /// 倾斜行按左右两端分别检查；几何交叉时保留条目但放弃不可靠的原图裁条。
    public static func boundedRegions(_ rows: [PassPlanRow]) -> [PassPlanRow] {
        var result = rows
        let pages = Set(rows.compactMap { $0.region?.page })
        for page in pages {
            let ordered = rows.indices.filter { rows[$0].region?.page == page }.sorted { a, b in
                let lhs = rows[a].region!, rhs = rows[b].region!
                let ay = lhs.y0 + lhs.slope * 0.5, by = rhs.y0 + rhs.slope * 0.5
                return ay == by ? a < b : ay < by
            }
            for (position, i) in ordered.enumerated() {
                guard var region = rows[i].region else { continue }
                let margin = min(0.002, max(0.0003, region.height * 0.025))
                var allowed = region.height
                for neighborPosition in [position - 1, position + 1] where ordered.indices.contains(neighborPosition) {
                    let neighbor = rows[ordered[neighborPosition]].region!
                    let direction = neighborPosition < position ? 1.0 : -1.0
                    for x in [region.left, region.right] {
                        let distance = direction * ((region.y0 + region.slope * x) - (neighbor.y0 + neighbor.slope * x))
                        allowed = min(allowed, distance - margin * 2)
                    }
                }
                if allowed > 0 {
                    region.height = allowed
                    result[i].region = region
                } else {
                    result[i].region = nil
                    result[i] = retainingIssues(result[i], adding: ["原图行边界重叠，请核对后使用整理表格"])
                }
            }
        }
        return result
    }

    private static func markerText(_ value: String) -> String {
        value.folding(options: .widthInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .filter { !$0.isWhitespace }.lowercased()
    }

    private static func leadingBadgeBoundary(_ layout: Layout) -> Double? {
        let slots = layout.slots.sorted { $0.x < $1.x }
        guard let first = slots.first, first.column != nil,
              !layout.slots.contains(where: { $0.column == .number && $0.x > first.x }) else { return nil }
        let gap = slots.count > 1 ? slots[1].x - first.x : 0.08
        return first.x - max(gap * 0.45, 0.01)
    }

    private static func leadingBadgeBoxes(_ boxes: [TextBox], layout: Layout) -> [TextBox] {
        guard let boundary = leadingBadgeBoundary(layout) else { return [] }
        return boxes.filter { markerText($0.text) == "应急" && $0.midX < boundary }
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
        // 编号和名称保留读到的原串；不能猜开头的数字是 Excel 行号。照片编号由人工对照原图确认。
        guard !(r.satellite.isEmpty && r.satelliteID.isEmpty), !r.station.isEmpty, !r.start.isEmpty else { return nil }
        // 又出现一遍表头（翻页、拼接的表）
        if column(forHeader: r.station) == .station { return nil }
        if markerText(r.status) == "test" { r.testStatusDetected = true }
        return r
    }

    /// 「2026-10-27 22:57:51」：只整理整个字段都能读懂的日期时间。
    /// 不截取一段看起来正确的时间，不把认坏的秒当作「没有秒」补成 00。
    public static func normalizedTime(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "：", with: ":").replacingOccurrences(of: "／", with: "/")
        s = s.replacingOccurrences(of: "－", with: "-").replacingOccurrences(of: "—", with: "-")
        let pattern = #"^([0-9]{4})\s*[-/.年]\s*([0-9]{1,2})\s*[-/.月]\s*([0-9]{1,2})\s*日?\s*([0-9]{1,2})\s*[:.]\s*([0-9]{2})(?:\s*[:.]\s*([0-9]{2}))?$"#
        func parsed(_ pattern: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
            let parts = (1...6).map { i in
                Range(m.range(at: i), in: s).flatMap { Int(s[$0]) } ?? (i == 6 ? 0 : -1)
            }
            guard validTimeParts(parts) else { return nil }
            return String(format: "%04d-%02d-%02d %02d:%02d:%02d", parts[0], parts[1], parts[2], parts[3], parts[4], parts[5])
        }
        if let formatted = parsed(pattern) { return formatted }
        // 分隔符丢了时仍按字段边界读，不能删除字母或别的杂字再凑成一个时间。
        // 例如「2026 10-27 22:05:25」「2026-10 28 075658」。年月日、时分秒各占原来的位数。
        guard s.hasPrefix("20") else { return s }
        let missingSeparators = #"^([0-9]{4})[\s./年-]*([0-9]{2})[\s./月-]*([0-9]{2})[\s日]*([0-9]{2})[\s:.]*([0-9]{2})(?:[\s:.]*([0-9]{2}))?$"#
        return parsed(missingSeparators) ?? s
    }

    /// 规范时间必须是真实的公历日期；2 月 30 日这类格式正确的错字也要提示核对。
    public static func isValidTime(_ value: String) -> Bool {
        guard value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$"#,
                          options: .regularExpression) != nil else { return false }
        return validTimeParts(value.split(whereSeparator: { "- :".contains($0) }).compactMap { Int($0) })
    }

    private static func validTimeParts(_ parts: [Int]) -> Bool {
        guard parts.count == 6, (1...9999).contains(parts[0]), (1...12).contains(parts[1]),
              (0..<24).contains(parts[3]), (0..<60).contains(parts[4]), (0..<60).contains(parts[5]) else { return false }
        let year = parts[0]
        let leap = year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...days[parts[1] - 1]).contains(parts[2])
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

    /// 图切成上下重叠的几段分别认：每段不超过约 240 万像素、也不高过宽的 1.4 倍（一整张一起认时手机先把图缩小，
    /// 一屏几十行的小字就糊了；一段十来行，用原来的清晰度认，和只拍一家时一样准），
    /// 相邻两段重叠一段高的 1/5（被切开的那行在另一段里是整的）。小图就一段
    public static func strips(width: Int, height: Int) -> [Strip] {
        let size = max(600, min(width * 7 / 5, 2_400_000 / max(width, 1)))
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

    /// 按地面站排过序的表，同一家的行挨在一起：分不出是哪家的这个站，每一条往上、往下最近的分得出的那条都是同一家，
    /// 多半也是这家（只提示，不自动分）
    public static func neighborOperator(of station: String, in rows: [PassPlanRow], rules: [OperatorRule]) -> String? {
        guard !rules.isEmpty else { return nil }
        let names = rows.map { operatorName(of: $0.station, rules: rules) }
        // 表得真是按地面站排过序的：分得出的行里，挨着的大多是同一家（没排序的表各家穿插着，上下是同一家只是碰巧）
        let known = names.compactMap { $0 }
        let pairs = zip(known, known.dropFirst())
        guard known.count >= 5, Double(pairs.filter { $0 == $1 }.count) >= Double(known.count - 1) * 0.75 else { return nil }
        var answer: String?
        for i in rows.indices where rows[i].station == station {
            guard let above = names[..<i].compactMap({ $0 }).last,
                  let below = names[(i + 1)...].compactMap({ $0 }).first,
                  above == below, answer == nil || answer == above else { return nil }
            answer = above
        }
        return answer
    }

    /// 另一种认法核对站名：开始时间相同只是候选，还必须对上卫星身份、没有圈号/结束时间矛盾，且只对应一行。
    /// 同一秒可以有多条计划，不能把第一个站名分给其他卫星；本来可分家的站名不自动改。
    public static func adoptStations(_ rows: [PassPlanRow], from other: [PassPlanRow], rules: [OperatorRule]) -> [PassPlanRow] {
        let sources = Dictionary(grouping: rows.filter { isValidTime($0.start) }, by: \.start)
        let candidates = Dictionary(grouping: other.filter { isValidTime($0.start) }, by: \.start)
        return rows.map { row in
            guard isValidTime(row.start) else { return row }
            let matches = (candidates[row.start] ?? []).filter { sameTablePlan(row, $0) }
            guard matches.count == 1, let candidate = matches.first else {
                let stations = Set(matches.map { comparisonValue($0.station) })
                return stations.count > 1
                    ? retainingIssues(row, adding: ["同一时间对应多个地面站，需核对原图"])
                    : row
            }
            // 同一卫星同一秒也可能同时向不同站数传。候选行反过来也只能对应原结果的一行。
            guard (sources[row.start] ?? []).filter({ sameTablePlan($0, candidate) }).count == 1 else {
                return retainingIssues(row, adding: ["同一时间的计划无法唯一对应地面站，请核对原图"])
            }
            let conflicts = recognitionConflicts(row, candidate, rules: rules, layout: nil)
            if rules.isEmpty || operatorName(of: row.station, rules: rules) != nil
                || operatorName(of: candidate.station, rules: rules) == nil {
                return retainingIssues(row, from: [candidate], adding: conflicts)
            }
            var fixed = row
            fixed.station = candidate.station
            return retainingIssues(fixed, from: [candidate], adding: conflicts)
        }
    }

    /// 照片的系统表格先沿用站名核对；圈号仅在原字段和对应原格都为空、双向唯一时补读。
    /// 不改写已有字符，不补缺格，也不把格式为数字当成正确保证；补完仍须对照原图核对。
    public static func adoptPhotoTable(_ rows: [PassPlanRow], from other: [PassPlanRow],
                                       layout: Layout?, rules: [OperatorRule]) -> [PassPlanRow] {
        let reviewed = adoptStations(rows, from: other, rules: rules)
        guard let layout else { return reviewed }
        let orbitColumns = layout.slots.indices.filter { layout.slots[$0].column == .orbit }
        guard orbitColumns.count == 1, let index = orbitColumns.first else { return reviewed }
        // 用原行快照核对双向唯一，不能让前一条补写改变后一条的匹配结果。
        let sources = Dictionary(grouping: rows.filter { isValidTime($0.start) }, by: \.start)
        let candidates = Dictionary(grouping: other.filter { isValidTime($0.start) }, by: \.start)
        return reviewed.map { row in
            guard row.orbit.isEmpty, row.cells.count == layout.slots.count,
                  row.cells.indices.contains(index), row.cells[index].isEmpty,
                  isValidTime(row.start) else { return row }
            let matches = (candidates[row.start] ?? []).filter { sameTablePlan(row, $0) }
            guard matches.count == 1, let candidate = matches.first,
                  (sources[row.start] ?? []).filter({ sameTablePlan($0, candidate) }).count == 1,
                  !candidate.orbit.isEmpty,
                  candidate.orbit.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) else { return row }
            var fixed = row
            fixed.orbit = candidate.orbit
            fixed.cells[index] = candidate.orbit
            return retainingIssues(fixed, adding: ["圈号由系统表格补读，请对照原图核对"])
        }
    }

    private static func sameTablePlan(_ row: PassPlanRow, _ candidate: PassPlanRow) -> Bool {
        row.start == candidate.start
            && matchingSatellite(row, candidate)
            && !differentWhenPresent(row.orbit, candidate.orbit)
            && !differentWhenPresent(row.end, candidate.end)
    }

    /// 单独重读地面站格子的结果。调用方提供不同设置的读数；只凭一次「像某家」不能覆盖原值。
    public static func reviewStationReread(_ row: PassPlanRow, candidates: [String], rules: [OperatorRule]) -> PassPlanRow {
        guard !rules.isEmpty else { return row }
        func station(_ value: String) -> String {
            value.filter { !$0.isWhitespace }.replacingOccurrences(of: "—", with: "-").replacingOccurrences(of: "－", with: "-")
        }
        let original = station(row.station)
        let readings = candidates.map(station)
        let known = readings.filter { !$0.isEmpty && operatorName(of: $0, rules: rules) != nil }
        let issue = "地面站多次识别不一致，请核对原图"
        if operatorName(of: original, rules: rules) != nil {
            return known.contains(where: { comparisonValue($0) != comparisonValue(original) })
                ? retainingIssues(row, adding: [issue]) : row
        }
        // 不用空读数冒充第二次确认，不用未知站覆盖另一个未知站。
        guard readings.count >= 2, !readings.contains(""), let first = readings.first,
              readings.allSatisfy({ comparisonValue($0) == comparisonValue(first) }),
              operatorName(of: first, rules: rules) != nil else {
            return Set(readings.filter { !$0.isEmpty }.map(comparisonValue)).count > 1
                ? retainingIssues(row, adding: [issue]) : row
        }
        var fixed = row
        fixed.station = first
        return fixed
    }

    /// 独立复识只核对卫星编号/名称，不自动选真值：英文高置信度结果也可能把 05 读成 06、1 读成 L。
    /// 只忽略既有的格式差异；C/0、O/0 等字符差异必须保留给人工核对，所有原字段和标记保持不变。
    public static func reviewIdentifierReread(_ row: PassPlanRow, column: Column, candidates: [String]) -> PassPlanRow {
        let original: String
        let label: String
        switch column {
        case .satelliteID:
            original = row.satelliteID
            label = "卫星编号"
        case .satellite:
            original = row.satellite
            label = "卫星名称"
        default:
            return row
        }
        let expected = comparisonValue(original)
        var seen = Set<String>()
        let usable = candidates.compactMap { raw -> (raw: String, value: String)? in
            let value = comparisonValue(raw)
            guard !value.isEmpty, seen.insert(value).inserted else { return nil }
            return (raw, value)
        }
        let different = usable.filter { $0.value != expected }
        let issue: String
        if usable.isEmpty {
            issue = "\(label)未能完成独立复核，请核对原图"
        } else if !different.isEmpty {
            // 仅在核对提示中展示有限原始读数，不把规范化后的内容伪装成 OCR 原文。
            let excerpts = different.prefix(3).map { candidate in
                let text = candidate.raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let excerpt = String(text.prefix(64)) + (text.count > 64 ? "…" : "")
                return "「\(excerpt)」"
            }.joined(separator: "、")
            let remainder = different.count > 3 ? "等" : ""
            issue = "\(label)独立复识与原读数不一致（复识：\(excerpts)\(remainder)），请核对原图"
        } else {
            return row
        }
        guard !(row.recognitionIssues ?? []).contains(issue) else { return row }
        var result = row
        result.recognitionIssues = (row.recognitionIssues ?? []) + [issue]
        return result
    }

    /// 结束时间缺损或有完整但不同的候选时，找出能进行原格复识的行。
    /// 原读数必须双向唯一对应，完整开始日期时间、编号、圈号和站名都相同。
    /// 返回值保留整段日期时间，不按 HH:mm 或卫星名称把不同日期的计划凑在一起。
    public static func endTimeRereadCandidates(_ reading: Reading, from sources: [Reading]) -> [Int: [String]] {
        guard let layout = reading.layout, layout.slots.filter({ $0.column == .end }).count == 1 else { return [:] }
        var result: [Int: [String]] = [:]
        let remapped = sources.compactMap { source -> [PassPlanRow]? in
            guard let sourceLayout = source.layout,
                  sourceLayout.slots.filter({ $0.column == .end }).count == 1 else { return nil }
            return remap(source.rows, from: sourceLayout, to: layout)
        }
        for (index, row) in reading.rows.enumerated() {
            let identity = comparisonValue(row.satelliteID.isEmpty ? row.satellite : row.satelliteID)
            let station = comparisonValue(row.station)
            guard !isExcludedFromSending(row), let region = row.region, isValidTime(row.start),
                  !identity.isEmpty, !station.isEmpty, !row.orbit.isEmpty,
                  row.orbit.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
                  row.cells.count == layout.slots.count else { continue }
            var values: [String] = []
            var matchingSources = 0
            for source in remapped {
                let matches = source.filter { $0.region.map { samePhotoPosition(region, $0) } ?? false }
                guard matches.count == 1, let candidate = matches.first, let candidateRegion = candidate.region,
                      !isExcludedFromSending(candidate),
                      reading.rows.filter({ $0.region.map { samePhotoPosition(candidateRegion, $0) } ?? false }).count == 1,
                      candidate.satelliteID.isEmpty == row.satelliteID.isEmpty,
                      comparisonValue(candidate.satelliteID.isEmpty ? candidate.satellite : candidate.satelliteID) == identity,
                      candidate.orbit == row.orbit, comparisonValue(candidate.station) == station,
                      candidate.start == row.start else { continue }
                matchingSources += 1
                if isValidTime(candidate.end), candidate.end > row.start { values.append(candidate.end) }
            }
            let distinct = Set(values)
            if distinct.count > 1 || (!isValidTime(row.end) && matchingSources > 0) {
                result[index] = distinct.sorted()
            }
        }
        return result
    }

    /// 已有完整时间时，原格英文无词语纠错复识只能支持已有候选，不能产生第三个猜测时间。
    /// 空白或格式损坏的格可由完整原格读数补回；若整页已有有效候选，仍须与其相符。
    /// 即使两路相符也保留所有分歧及人工核对提示，不把它当成已确认的真值。
    public static func reviewEndTimeReread(_ row: PassPlanRow, candidates: [String], reread: String,
                                          layout: Layout) -> PassPlanRow {
        let columns = layout.slots.indices.filter { layout.slots[$0].column == .end }
        guard !isExcludedFromSending(row), columns.count == 1, let index = columns.first,
              row.cells.count == layout.slots.count, isValidTime(row.start) else { return row }
        let usable = Set(candidates.filter { isValidTime($0) && $0 > row.start })
        let missing = !isValidTime(row.end)
        // 当前照片的标准时间为完整 14 位数字；复识漏秒时不能让 normalizedTime 补 00 后参与确认。
        let digits = reread.unicodeScalars.filter { (48...57).contains($0.value) }.count
        let value = normalizedTime(reread)
        guard missing || usable.count > 1, digits == 14, isValidTime(value), value > row.start else { return row }
        guard (missing && usable.isEmpty) || usable.contains(value) else {
            return retainingIssues(row, adding: ["结束时间原格复识与多轮候选不一致，请核对原图"])
        }
        guard value != row.end else { return row }
        var fixed = row
        fixed.end = value
        fixed.cells[index] = reread.trimmingCharacters(in: .whitespacesAndNewlines)
        let issue = missing ? "结束时间由原格补读，请核对原图" : "结束时间由原格复识与多轮候选核对，请核对原图"
        return retainingIssues(fixed, adding: [issue])
    }

    /// 只使用名称末尾实际读出的混合数字/字母片段（如「示例07D星」中的 07D）。
    /// 必须是分开的编号与名称列；不从单一编号列猜名称，不修数字前缀，也不转换 O/0。
    public static func identifierRereadFragment(_ row: PassPlanRow, layout: Layout) -> String? {
        let identifiers = layout.slots.indices.filter { layout.slots[$0].column == .satelliteID }
        let names = layout.slots.indices.filter { layout.slots[$0].column == .satellite }
        guard !isExcludedFromSending(row), row.region != nil,
              identifiers.count == 1, names.count == 1, let identifier = identifiers.first, let name = names.first,
              row.cells.count == layout.slots.count, isValidTime(row.start), !row.station.isEmpty,
              !row.orbit.isEmpty, row.orbit.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) else { return nil }
        let original = comparisonValue(row.satelliteID), label = comparisonValue(row.satellite)
        guard isASCIIIdentifier(original), label.filter({ $0 == "星" }).count == 1,
              comparisonValue(row.cells[identifier]) == original,
              comparisonValue(row.cells[name]) == label,
              let expression = try? NSRegularExpression(pattern: #"(?<![A-Z0-9])([0-9][A-Z0-9]{2,})星$"#),
              let match = expression.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
              let range = Range(match.range(at: 1), in: label) else { return nil }
        let fragment = String(label[range])
        guard fragment.unicodeScalars.contains(where: { (65...90).contains($0.value) }),
              !original.contains(fragment) else { return nil }
        return fragment
    }

    /// 必须实际复识出完整编号；仅当差异全部位于名称明确显示的唯一片段内时采用。
    /// 片段之外的每个字符和总长度都必须保持一致，不能补前缀/后缀或按规则合成编号。
    public static func reviewNamedIdentifierReread(_ row: PassPlanRow, reread: String, layout: Layout) -> PassPlanRow {
        guard let fragment = identifierRereadFragment(row, layout: layout),
              let column = layout.slots.firstIndex(where: { $0.column == .satelliteID }) else { return row }
        let original = comparisonValue(row.satelliteID), value = comparisonValue(reread)
        guard isASCIIIdentifier(value), value.count == original.count else { return row }
        let before = Array(original.utf8), after = Array(value.utf8), label = Array(fragment.utf8)
        guard after.count >= label.count else { return row }
        let matches = (0...(after.count - label.count)).filter { start in
            after[start..<(start + label.count)].elementsEqual(label)
        }
        guard matches.count == 1, let start = matches.first else { return row }
        let end = start + label.count
        guard before[..<start].elementsEqual(after[..<start]), before[end...].elementsEqual(after[end...]) else { return row }
        var fixed = row
        fixed.satelliteID = value
        fixed.cells[column] = reread.trimmingCharacters(in: .whitespacesAndNewlines)
        let old = String(row.satelliteID.prefix(64))
        return retainingIssues(fixed, adding: ["卫星编号原格复识与名称片段相符，原读数「\(old)」，请核对原图"])
    }

    /// 引擎的完整候选也须逐一满足原格约束；仅有一个不同编号得到支持才采用。
    /// 多个格式不同但编号相同的候选不重复计数，两个不同的可支持编号则保留原值。
    public static func reviewNamedIdentifierRereads(_ row: PassPlanRow, rereads: [String], layout: Layout) -> PassPlanRow {
        var supported: [String: PassPlanRow] = [:]
        for raw in rereads {
            let candidate = reviewNamedIdentifierReread(row, reread: raw, layout: layout)
            guard candidate.satelliteID != row.satelliteID else { continue }
            if supported[candidate.satelliteID] == nil { supported[candidate.satelliteID] = candidate }
            guard supported.count <= 1 else { return row }
        }
        return supported.count == 1 ? (supported.values.first ?? row) : row
    }

    private static func isASCIIIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { (48...57).contains($0.value) || (65...90).contains($0.value) }
    }

    /// 照片复识一致仍可能同错；照片读取入口显式调用，文字/表格导入不增加这项人工确认要求。
    /// 不根据易混字母猜测，不要求已有裁条，也不改写任何识别值或发送标记。
    public static func requiringPhotoIdentifierReview(_ row: PassPlanRow, column: Column) -> PassPlanRow {
        let label: String
        switch column {
        case .satelliteID: label = "卫星编号"
        case .satellite: label = "卫星代号"
        default: return row
        }
        let issue = "照片中的\(label)需对照原图确认"
        guard !(row.recognitionIssues ?? []).contains(issue) else { return row }
        var result = row
        result.recognitionIssues = (row.recognitionIssues ?? []) + [issue]
        return result
    }

    /// 用户对照原图确认当前行后，只解除识别疑项；格式/缺字段检查和 test 排除仍按原值生效。
    public static func confirmedRecognitionReview(_ row: PassPlanRow) -> PassPlanRow {
        var result = row
        result.recognitionIssues = nil
        return result
    }

    private static func comparisonValue(_ value: String) -> String {
        value.filter { !$0.isWhitespace }.uppercased()
            .replacingOccurrences(of: "—", with: "-").replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "：", with: ":").replacingOccurrences(of: "，", with: ",")
    }

    private static func differentWhenPresent(_ lhs: String, _ rhs: String) -> Bool {
        let a = comparisonValue(lhs), b = comparisonValue(rhs)
        return !a.isEmpty && !b.isEmpty && a != b
    }

    private static func samePhotoPosition(_ a: Region, _ b: Region) -> Bool {
        guard a.page == b.page else { return false }
        let left = max(a.left, b.left), right = min(a.right, b.right)
        guard right > left else { return false }
        let x = (left + right) / 2
        return abs((a.y0 + a.slope * x) - (b.y0 + b.slope * x)) < min(a.height, b.height) * 0.45
    }

    /// 卫星 ID 优先；两边都有但不同的 ID 不能被相同名称掩盖。
    private static func matchingSatellite(_ lhs: PassPlanRow, _ rhs: PassPlanRow) -> Bool {
        let a = comparisonValue(lhs.satelliteID), b = comparisonValue(rhs.satelliteID)
        if !a.isEmpty && !b.isEmpty { return a == b }
        let an = comparisonValue(lhs.satellite), bn = comparisonValue(rhs.satellite)
        return !an.isEmpty && !bn.isEmpty && an == bn
    }

    private static func retainingIssues(_ row: PassPlanRow, from others: [PassPlanRow] = [], adding: [String] = []) -> PassPlanRow {
        var result = row
        let observations = [row] + others
        if observations.contains(where: { $0.emergencyBadge == true }) {
            result.emergencyBadge = true
        } else if observations.contains(where: { $0.emergencyBadge == false }) {
            result.emergencyBadge = false
        }
        if observations.contains(where: isExcludedFromSending) { result.testStatusDetected = true }
        var seen = Set<String>()
        let issues = ((row.recognitionIssues ?? []) + others.flatMap { $0.recognitionIssues ?? [] } + adding)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        result.recognitionIssues = issues.isEmpty ? nil : issues
        return result
    }

    /// 只有同一行的独立读数才能比较；合法但不同的数字不能靠「格式正确」选出真值。
    private static func recognitionConflicts(_ lhs: PassPlanRow, _ rhs: PassPlanRow,
                                            rules: [OperatorRule], layout: Layout?) -> [String] {
        var labels: [String] = []
        if isValidTime(lhs.start), isValidTime(rhs.start), lhs.start != rhs.start { labels.append("开始时间") }
        if isValidTime(lhs.end), isValidTime(rhs.end), lhs.end != rhs.end { labels.append("结束时间") }
        if differentWhenPresent(lhs.station, rhs.station),
           operatorName(of: lhs.station, rules: rules) != nil, operatorName(of: rhs.station, rules: rules) != nil {
            labels.append("地面站")
        }
        if differentWhenPresent(lhs.satelliteID, rhs.satelliteID) { labels.append("卫星编号") }
        if differentWhenPresent(lhs.satellite, rhs.satellite) { labels.append("卫星名称") }
        if differentWhenPresent(lhs.orbit, rhs.orbit), lhs.orbit.allSatisfy(\.isNumber), rhs.orbit.allSatisfy(\.isNumber) {
            labels.append("圈号")
        }
        if differentWhenPresent(lhs.info, rhs.info) { labels.append("数传信息") }
        let a = emergencyColumn(lhs, layout: layout), b = emergencyColumn(rhs, layout: layout)
        // 没读到左标签不构成「否」的文字证据；另一页/另一遍读到的 true 必须保留。
        if (a != nil && b != nil && a != b) || (a == false && rhs.emergencyBadge == true) || (b == false && lhs.emergencyBadge == true) {
            labels.append("是否应急")
        }
        if isExcludedFromSending(lhs) != isExcludedFromSending(rhs), !lhs.status.isEmpty, !rhs.status.isEmpty {
            labels.append("状态（含 test，已排除发送）")
        }
        return labels.map { "\($0)多次识别不一致，请核对原图" }
    }

    /// 读得好不好（同一张照片两种认法挑一个）：认出的行越多越好，可能认错的行（时间不全、站名对不上对照表……）只算一小半
    public static func score(_ reading: Reading, rules: [OperatorRule] = []) -> Double {
        reading.rows.reduce(0) { $0 + (problems($1, rules: rules, layout: reading.layout).isEmpty ? 1 : 0.3) }
    }

    /// 身份相容时，另一轮只能补坏格/空格，不能因它少一个错误就整行换掉。
    /// 两个完整但不同的值仍保留首选读数及冲突提示；不猜 0/O 或编号前缀。
    private static func supplementingFields(_ row: PassPlanRow, from other: PassPlanRow,
                                            layout: Layout, rules: [OperatorRule]) -> PassPlanRow? {
        let hasBothIDs = !comparisonValue(row.satelliteID).isEmpty && !comparisonValue(other.satelliteID).isEmpty
        if hasBothIDs {
            guard !differentWhenPresent(row.satelliteID, other.satelliteID) else { return nil }
        } else if differentWhenPresent(row.satellite, other.satellite) {
            // 相近的行位置不能把两个身份不同的卫星拼成一条。
            return nil
        }
        var result = row
        func empty(_ value: String) -> Bool { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        func replace(_ column: Column, _ key: WritableKeyPath<PassPlanRow, String>, when allowed: Bool) {
            guard allowed, !empty(other[keyPath: key]), let index = layout.slots.firstIndex(where: { $0.column == column }) else { return }
            result[keyPath: key] = other[keyPath: key]
            while result.cells.count < layout.slots.count { result.cells.append("") }
            result.cells[index] = index < other.cells.count ? other.cells[index] : other[keyPath: key]
        }
        replace(.satelliteID, \.satelliteID, when: empty(row.satelliteID))
        replace(.satellite, \.satellite, when: empty(row.satellite))
        replace(.station, \.station, when: operatorName(of: row.station, rules: rules) == nil
            && operatorName(of: other.station, rules: rules) != nil)
        replace(.orbit, \.orbit, when: (empty(row.orbit) || !row.orbit.allSatisfy(\.isNumber))
            && !empty(other.orbit) && other.orbit.allSatisfy(\.isNumber))
        replace(.info, \.info, when: empty(row.info))
        replace(.status, \.status, when: empty(row.status) && isRecognizedPlanStatus(other.status))

        let fixesStart = !isValidTime(row.start) && isValidTime(other.start)
        let fixesEnd = !isValidTime(row.end) && isValidTime(other.end)
        let start = fixesStart ? other.start : row.start
        let end = fixesEnd ? other.end : row.end
        // 各自看起来合法的时间不能组合成结束早于开始的新区间。
        if !isValidTime(start) || !isValidTime(end) || end > start {
            replace(.start, \.start, when: fixesStart)
            replace(.end, \.end, when: fixesEnd)
        }
        if let index = layout.emergencyIndex, emergencyColumn(row, layout: layout) == nil,
           emergencyColumn(other, layout: layout) != nil, index < other.cells.count {
            while result.cells.count < layout.slots.count { result.cells.append("") }
            result.cells[index] = other.cells[index]
        }
        return result
    }

    /// 同一张照片几种认法各拼出一份：认得最好的那份打底，按位置唯一对应、一一匹配。
    /// 逐字段补全格式错误和空值；完整值之间的矛盾保留首选值和核对提示。
    /// 身份冲突时沿用完整候选择优，不拼字段，也不阻断整条较完整的读数。
    public static func combine(_ readings: [Reading], rules: [OperatorRule] = []) -> Reading {
        let ranked = readings.enumerated().sorted { a, b in
            let (sa, sb) = (score(a.element, rules: rules), score(b.element, rules: rules))
            return sa != sb ? sa > sb : a.offset < b.offset
        }.map(\.element)
        guard var base = ranked.first else { return Reading(rows: [], layout: nil) }
        guard let layout = base.layout else { return base }
        /// 这一行在照片正中间那里的高低
        func level(_ r: Region) -> Double { r.y0 + r.slope * 0.5 }
        func issues(_ row: PassPlanRow) -> Int {
            var value = row
            value.recognitionIssues = nil
            return problems(value, rules: rules, layout: layout).count
        }
        var rows = base.rows
        for other in ranked.dropFirst() {
            guard let from = other.layout else { continue }
            let previousCount = rows.count
            var matched = Set<Int>()
            for row in remap(other.rows, from: from, to: layout) {
                guard let region = row.region else { continue }
                let candidates = (0..<previousCount).filter { i in
                    rows[i].region.map { samePhotoPosition($0, region) } ?? false
                }
                if candidates.count == 1, let i = candidates.first, !matched.contains(i) {
                    matched.insert(i)
                    let previous = rows[i]
                    let conflicts = recognitionConflicts(previous, row, rules: rules, layout: layout)
                    let preferred = supplementingFields(previous, from: row, layout: layout, rules: rules)
                        ?? (issues(row) < issues(previous) ? row : previous)
                    rows[i] = retainingIssues(preferred, from: [previous, row], adding: conflicts)
                } else {
                    // 同一行被对应两次、或附近两行都可能对应时，不擅自吞掉一条。
                    let warnings = candidates.isEmpty ? [] : ["多次识别的行位置对应不清，请核对原图"]
                    for i in candidates { rows[i] = retainingIssues(rows[i], adding: warnings) }
                    rows.append(retainingIssues(row, adding: warnings))
                }
            }
        }
        if rows.allSatisfy({ $0.region != nil }) {
            rows.sort { level($0.region!) < level($1.region!) }
        }
        base.rows = boundedRegions(rows)
        return base
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

    /// 计划长、拍了几张（上下有重叠）：只合并不同页里唯一对应的同一条。
    /// 同站、同时间仍可能是不同卫星/圈次；同页的两条也不能仅凭时间一样就吞掉一条。
    public static func merge(_ pages: [[PassPlanRow]], layout: Layout? = nil) -> [PassPlanRow] {
        var rows: [PassPlanRow] = []
        var indices: [String: [Int]] = [:]
        func key(_ r: PassPlanRow) -> String? {
            guard isValidTime(r.start), r.end.isEmpty || isValidTime(r.end), !comparisonValue(r.station).isEmpty else { return nil }
            return [r.start, r.end, comparisonValue(r.station)].joined(separator: "|")
        }
        func sameIdentity(_ a: PassPlanRow, _ b: PassPlanRow) -> Bool {
            guard !differentWhenPresent(a.orbit, b.orbit), !differentWhenPresent(a.satelliteID, b.satelliteID) else { return false }
            // 只有卫星 ID 是稳定的卫星身份；不同卫星的圈次数字也可能恰好相同。
            return matchingSatellite(a, b)
        }
        // 同站、同起止时间还不足以合并不同编号。圈号和卫星名称也相同时，可能是重叠照片里的 OCR 错字，
        // 但仍没有足够证据决定哪个编号正确：保留两条并要求核对，不能改写编号或跨身份复制 test。
        func conflictingID(_ a: PassPlanRow, _ b: PassPlanRow) -> Bool {
            let orbit = comparisonValue(a.orbit), satellite = comparisonValue(a.satellite)
            return isValidTime(a.end) && isValidTime(b.end)
                && differentWhenPresent(a.satelliteID, b.satelliteID)
                && !orbit.isEmpty && orbit == comparisonValue(b.orbit)
                && !satellite.isEmpty && satellite == comparisonValue(b.satellite)
        }
        func filled(_ r: PassPlanRow) -> Int {
            [r.orbit, r.satelliteID, r.satellite, r.station, r.start, r.end, r.info, r.status].filter { !$0.isEmpty }.count
        }
        for page in pages {
            let previousCount = rows.count
            var matched = Set<Int>()
            for observed in page {
                let k = key(observed)
                let conflicting = k.map { key in
                    (indices[key] ?? []).filter { $0 < previousCount && conflictingID(rows[$0], observed) }
                } ?? []
                let identityWarnings = conflicting.isEmpty ? [] : ["跨页同站同时间、同圈号和同名卫星的编号不一致，请核对原图"]
                // 已经匹配过的旧行仍是冲突证据；即使另有明确的相同 ID，也不能隐藏旁边的矛盾候选。
                for i in conflicting { rows[i] = retainingIssues(rows[i], adding: identityWarnings) }
                let row = retainingIssues(observed, adding: identityWarnings)
                let matches = k.map { key in
                    (indices[key] ?? []).filter { $0 < previousCount && !matched.contains($0) && sameIdentity(rows[$0], row) }
                } ?? []
                if matches.count == 1, let i = matches.first {
                    matched.insert(i)
                    let old = rows[i]
                    let preferred = filled(row) > filled(old) ? row : old
                    rows[i] = retainingIssues(preferred, from: [old, row],
                                               adding: recognitionConflicts(old, row, rules: [], layout: layout))
                } else {
                    let uncertain = k.map { key in
                        (indices[key] ?? []).filter { i in
                            let old = rows[i]
                            return i < previousCount && old.satelliteID.isEmpty && row.satelliteID.isEmpty
                                && !old.orbit.isEmpty && comparisonValue(old.orbit) == comparisonValue(row.orbit)
                                && differentWhenPresent(old.satellite, row.satellite)
                        }
                    } ?? []
                    if let k { indices[k, default: []].append(rows.count) }
                    var warnings = matches.count > 1 ? ["跨页计划无法唯一对应，请核对原图"] : []
                    if !uncertain.isEmpty { warnings.append("跨页同站同时间的卫星不一致，请核对原图") }
                    for i in matches + uncertain { rows[i] = retainingIssues(rows[i], adding: warnings) }
                    rows.append(retainingIssues(row, adding: warnings))
                }
            }
        }
        return rows
    }

    /// 这一条可能认错的地方（页面上标出来，让人核对）；没有返回空。
    /// layout：读到的那张表有哪几列（导出的 Excel 没有结束时间，就不说「没有结束时间」）
    public static func problems(_ r: PassPlanRow, rules: [OperatorRule] = [], layout: Layout? = nil) -> [String] {
        let has = { (c: Column) in layout.map { $0.columns.contains(c) } ?? true }
        var list: [String] = []
        if !isValidTime(r.start) { list.append("开始时间没认全") }
        if r.end.isEmpty {
            if has(.end) { list.append("没有结束时间") }
        } else if !isValidTime(r.end) {
            list.append("结束时间没认全")
        } else if isValidTime(r.start), r.end <= r.start {
            list.append("结束比开始还早")
        }
        if operatorName(of: r.station, rules: rules) == nil { list.append("分不出是哪家（运营商对照表里没有这个站）") }
        // 只要求本表明确存在的列；没有布局的旧计划、原本没有这些列的表不新增必填项。
        if layout?.columns.contains(.orbit) == true, r.orbit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            list.append("没认出圈号")
        } else if !r.orbit.isEmpty, !r.orbit.allSatisfy(\.isNumber) {
            list.append("圈号不全是数字")
        }
        if layout?.columns.contains(.satelliteID) == true,
           r.satelliteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            list.append("没认出卫星编号")
        }
        if r.satellite.isEmpty, has(.satellite) { list.append("没认出卫星名称") }
        if layout?.emergencyIndex != nil, emergency(r, layout: layout) == nil {
            list.append("是否应急没认出来，请核对原图")
        }
        if r.emergencyBadge == true, emergencyColumn(r, layout: layout) == false {
            list.append("左侧应急标签与是否应急列不一致，请核对原图")
        }
        var seen = Set<String>()
        return (list + (r.recognitionIssues ?? [])).filter { seen.insert($0).inserted }
    }

    // MARK: - 应急

    /// 明确的左侧「应急」标签优先，兼容 Excel 的「是否应急」列。
    /// 无标签只有在该页版式已确认时才记为 false；没有应急信息则保持 nil。
    public static func emergency(_ r: PassPlanRow, layout: Layout?) -> Bool? {
        if r.emergencyBadge == true { return true }
        if layout?.emergencyIndex != nil { return emergencyColumn(r, layout: layout) }
        return r.emergencyBadge
    }

    private static func emergencyColumn(_ r: PassPlanRow, layout: Layout?) -> Bool? {
        guard let i = layout?.emergencyIndex else { return nil }
        let value = i < r.cells.count ? r.cells[i].filter { !$0.isWhitespace } : ""
        // 重新导入本 App 整理出的标签列：空白代表没有标签；显式「是否应急」空白仍然是未知。
        if layout?.slots[i].label.filter({ !$0.isWhitespace }) == "应急" {
            if value == "应急" { return true }
            if value.isEmpty { return false }
        }
        if ["是", "是的", "Y", "y", "YES", "Yes", "yes", "√", "✓"].contains(value) { return true }
        if ["不是", "否", "N", "n", "NO", "No", "no", "×"].contains(value) { return false }
        // 已知的下一列半截粘连，只接受这两种完整读数；「是否」「是X」不能靠前缀冒充确认。
        if value == "不是不" { return false }
        if value == "是不" { return true }
        return nil
    }

    /// 发图时下面那句话：这一家里有应急计划用 urgent，没有用 normal
    public static func caption(_ rows: [PassPlanRow], layout: Layout?, normal: String, urgent: String) -> String {
        sendableRows(rows).contains { emergency($0, layout: layout) == true } ? urgent : normal
    }

    /// 状态为 test 的计划不发送给任何运营商。去掉空白、忽略大小写；其他字段含 test 不算。
    public static func isTestStatus(_ status: String) -> Bool {
        markerText(status) == "test"
    }

    /// 窄栏补读只接受已有计划格式中的完整状态；不把残缺词或相似英文猜成普通状态。
    public static func isRecognizedPlanStatus(_ status: String) -> Bool {
        ["等待数传", "已发送站", "发送失败", "数传成功", "test"].contains(markerText(status))
    }

    public static func isExcludedFromSending(_ row: PassPlanRow) -> Bool {
        row.testStatusDetected == true || isTestStatus(row.status)
    }

    /// 导出/分组的统一入口；识别结果本身保留所有行供核对和计数。
    public static func sendableRows(_ rows: [PassPlanRow]) -> [PassPlanRow] {
        rows.filter { !isExcludedFromSending($0) }
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
        let matches = rules.flatMap { rule in rule.prefixes.map { (rule.name, $0.filter { !$0.isWhitespace }) } }
            .filter { !$0.1.isEmpty && s.hasPrefix($0.1) }
        guard let longest = matches.map({ $0.1.count }).max() else { return nil }
        let names = Set(matches.filter { $0.1.count == longest }.map(\.0))
        return names.count == 1 ? names.first : nil
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
        for r in sendableRows(rows) {
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
        let rows = sendableRows(rows)
        if let layout { return table(rows, layout: layout) }
        var columns: [(String, (PassPlanRow) -> String)] = [
            ("圈号", \.orbit), ("卫星ID", \.satelliteID), ("卫星名称", \.satellite), ("地面站", \.station),
            ("数传开始时间", \.start), ("数传结束时间", \.end), ("数传信息", \.info), ("状态", \.status),
        ]
        if rows.contains(where: { $0.emergencyBadge != nil }) {
            columns.insert(("应急", { $0.emergencyBadge == true ? "应急" : "" }), at: 0)
        }
        let used = columns.filter { column in rows.contains { !column.1($0).isEmpty } }
        let cells = rows.enumerated().map { i, row in ["\(i + 1)"] + used.map { $0.1(row) } }
        return (["No."] + used.map(\.0), cells)
    }

    /// 照读到的那张表：同样的表头、同样的列（认不出含义的列原样带上），前面一列 No. 是这一家里的第几条。
    /// 认得出含义的列用整理过的值（改过的、补的一条也对得上），其他列用原来的字
    private static func table(_ rows: [PassPlanRow], layout: Layout) -> (headers: [String], cells: [[String]]) {
        let kept = layout.slots.indices.filter { layout.slots[$0].column != .number }
        let showsBadges = layout.emergencyIndex == nil && rows.contains { $0.emergencyBadge != nil }
        func value(_ row: PassPlanRow, _ i: Int) -> String {
            if i == layout.emergencyIndex, let urgent = emergency(row, layout: layout) { return urgent ? "是" : "不是" }
            return layout.slots[i].column.flatMap(row.value) ?? (i < row.cells.count ? row.cells[i] : "")
        }
        let cells = rows.enumerated().map { n, row in
            ["\(n + 1)"] + (showsBadges ? [row.emergencyBadge == true ? "应急" : ""] : []) + kept.map { value(row, $0) }
        }
        return (["No."] + (showsBadges ? ["应急"] : []) + kept.map { layout.slots[$0].label }, cells)
    }

    /// 标题：「10月27日数传计划（甲站）共 3 条」（跨了几天的不写日期）
    public static func title(name: String, rows: [PassPlanRow]) -> String {
        let rows = sendableRows(rows)
        let days = Set(rows.map { String($0.start.prefix(10)) }).sorted()
        if days.count == 1, let d = DayKey(string: days[0]) {
            return "\(d.month)月\(d.day)日数传计划（\(name)）共 \(rows.count) 条"
        }
        return "数传计划（\(name)）共 \(rows.count) 条"
    }

    /// 发到群里的一段话：标题、表头、每条一行，和图上的表一样
    /// caption：最后一行的那句话（「麻烦确认一下数传计划」），空的不加
    public static func message(name: String, rows: [PassPlanRow], layout: Layout? = nil, caption: String = "") -> String {
        let rows = sendableRows(rows)
        guard !rows.isEmpty else { return "" }
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
