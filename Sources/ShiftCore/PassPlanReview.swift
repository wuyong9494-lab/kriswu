import Foundation

extension PassPlan {
    public struct ReviewIssue: Equatable, Sendable {
        public enum Category: Equatable, Sendable { case station, time, duplicate, yellow, other }
        public let category: Category
        public let message: String
    }

    /// A per-batch manual correction does not change the operator dictionary. It can only name an
    /// existing operator and never wins over two conflicting configured rule owners.
    public static func resolvedOperator(of station: String, rules: [OperatorRule],
                                        batchRoutes: [String: String] = [:]) -> String? {
        let key = normalizedStationAlias(station)
        if !key.isEmpty, let selected = batchRoutes[key], !selected.isEmpty, selected != unassigned,
           rules.contains(where: { $0.name == selected }),
           stationCandidates(of: station, rules: rules).count < 2 {
            return selected
        }
        return operatorName(of: station, rules: rules)
    }

    /// Stable row-index keys distinguish two equal rows without merging or deleting either.
    /// Dynamic checks are computed from current values, so saving an unchanged row cannot silence
    /// duplicates or possible resource overlaps. "Touching" endpoints are not overlaps.
    public static func reviewIssues(_ rows: [PassPlanRow], format: DeliveryFormat,
                                    rules: [OperatorRule] = [], layout: Layout? = nil,
                                    batchRoutes: [String: String] = [:]) -> [Int: [ReviewIssue]] {
        var result: [Int: [ReviewIssue]] = [:]
        func add(_ issue: ReviewIssue, at index: Int) {
            if result[index]?.contains(issue) != true { result[index, default: []].append(issue) }
        }
        struct Duplicate: Hashable {
            let station: String
            let satellite: String
            let orbit: String
            let start: String
            let end: String
            let info: String
            let status: String
            let otherCells: [String]
        }
        struct Resource: Hashable { let station: String; let name: String }
        var duplicates: [Duplicate: [Int]] = [:]
        var spans: [Resource: [Int]] = [:]

        for (index, row) in rows.enumerated() where !isExcludedFromSending(row) {
            let literalCandidates = stationCandidates(of: row.station, rules: rules)
            if rules.isEmpty {
                add(.init(category: .station, message: "尚未添加运营商对照表，不能分享"), at: index)
            }
            if literalCandidates.count > 1 {
                add(.init(category: .station, message: "站名对照表冲突：\(literalCandidates.joined(separator: "、"))，不能发送"),
                    at: index)
            }
            let resolved = resolvedOperator(of: row.station, rules: rules, batchRoutes: batchRoutes)
            if resolved == nil && literalCandidates.count < 2 {
                add(.init(category: .station, message: "站名未确定运营商，不能发送"), at: index)
            }
            var rowProblems = deliveryProblems(row, format: format, rules: rules, layout: layout)
            if format == .originalImage {
                // The review page makes the same safety promise for either output representation.
                rowProblems += deliveryProblems(row, format: .recognizedContent, rules: rules, layout: layout)
            }
            for problem in rowProblems {
                if problem.hasPrefix("分不出是哪家") { continue } // replaced by explicit route findings above
                let category: ReviewIssue.Category
                if problem.hasPrefix("原图黄色警告：") { category = .yellow }
                else if problem.contains("站名") || problem.contains("地面站") { category = .station }
                else if problem.contains("时间") || problem.contains("结束比开始") { category = .time }
                else { category = .other }
                add(.init(category: category, message: problem), at: index)
            }

            let station = normalizedStationAlias(row.station)
            let satellite = row.satelliteID.isEmpty ? row.satellite : row.satelliteID
            guard !station.isEmpty, !satellite.isEmpty, isValidTime(row.start) else { continue }
            let validEnd = isValidTime(row.end) && row.end > row.start
            if row.end.isEmpty || validEnd {
                let other = layout?.slots.enumerated().compactMap { i, slot in
                    slot.column == nil && row.cells.indices.contains(i) ? row.cells[i] : nil
                } ?? []
                duplicates[.init(station: station, satellite: satellite, orbit: row.orbit, start: row.start,
                                 end: row.end, info: row.info, status: row.status, otherCells: other), default: []].append(index)
            }
            if validEnd {
                // A repeated station alone is not enough evidence: different channels can run in parallel.
                // With no channel recorded, compare only the same station and satellite.
                let info = row.info.filter { !$0.isWhitespace }
                let resource = info.isEmpty ? "星:\(satellite)" : "通道:\(info)"
                spans[.init(station: station, name: resource), default: []].append(index)
            }
        }
        for indices in duplicates.values where indices.count > 1 {
            for index in indices {
                add(.init(category: .duplicate, message: "发现 \(indices.count) 条相同计划，请对照原文后保留正确的一条"), at: index)
            }
        }
        for indices in spans.values where indices.count > 1 {
            let sorted = indices.sorted { a, b in
                if rows[a].start == rows[b].start { return a < b }
                return rows[a].start < rows[b].start
            }
            var longest = sorted[0]
            for current in sorted.dropFirst() {
                if rows[current].start < rows[longest].end,
                   !(rows[current].start == rows[longest].start && rows[current].end == rows[longest].end &&
                     result[current]?.contains(where: { $0.category == .duplicate }) == true &&
                     result[longest]?.contains(where: { $0.category == .duplicate }) == true) {
                    let issue = ReviewIssue(category: .time, message: "同站同通道（或未标通道的同一卫星）时间重叠，请核对")
                    add(issue, at: current)
                    add(issue, at: longest)
                }
                if rows[current].end > rows[longest].end { longest = current }
            }
        }
        return result
    }

    /// Sharing is neither recipient selection nor proof of receipt. Only explicit manual verification
    /// adds a timestamp suitable for handover; new content invalidates that timestamp.
    public struct DeliveryLedger: Equatable, Sendable {
        public private(set) var requested: Set<String> = []
        public private(set) var handedOff: Set<String> = []
        public private(set) var confirmedReceipts: [String: Date] = [:]

        public init() {}

        public mutating func requestShare(_ operatorName: String) { requested.insert(operatorName) }

        public mutating func reportHandoff(_ operatorName: String, completed: Bool) {
            if completed && requested.contains(operatorName) { handedOff.insert(operatorName) }
        }

        @discardableResult
        public mutating func confirmReceipt(_ operatorName: String, at time: Date) -> Bool {
            guard requested.contains(operatorName), confirmedReceipts[operatorName] == nil else { return false }
            confirmedReceipts[operatorName] = time
            return true
        }

        public mutating func invalidate(_ operatorName: String) {
            requested.remove(operatorName)
            handedOff.remove(operatorName)
            confirmedReceipts.removeValue(forKey: operatorName)
        }
    }
}
