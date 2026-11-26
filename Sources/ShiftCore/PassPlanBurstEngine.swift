import Foundation

/// Source table kind inferred from Photo 1's header row during PassPlan multi-shot recognition.
public enum PassPlanTableKind: String, Codable, Equatable, Sendable {
    /// Web portal table: contains both `数传开始时间` and `数传结束时间`.
    /// Must extract BOTH preserving original values; unreadable end time -> flag "待核对" (never substitute another time).
    case webPage
    /// Exported/screen spreadsheet table: contains `数传开始时间` + `创建时间` (no `数传结束时间`).
    /// Must extract ONLY `数传开始时间` and COMPLETELY IGNORE `创建时间` (end time stays blank in UI & export).
    case spreadsheet
    /// Header did not clearly distinguish web vs spreadsheet.
    case unknown

    public var displayTitle: String {
        switch self {
        case .webPage: return "网页表（起止时间）"
        case .spreadsheet: return "导出表格（仅开始时间，已忽略创建时间）"
        case .unknown: return "待核对表格"
        }
    }
}

/// Multi-shot PassPlan batch recognition & cross-photo merge engine.
/// Handles:
/// 1. First-photo table-kind classification (`webPage` vs `spreadsheet`).
/// 2. Strict web vs spreadsheet time rules (spreadsheet NEVER reads `创建时间` as `数传结束时间`).
/// 3. Headerless continuation carryover across Photos 2, 3, ... with column-alignment checks
///    (misaligned continuation pages are flagged `"待核对"` instead of guessing by timestamp order).
/// 4. Smart cross-photo overlap deduplication:
///    - Priority 1: `计划编号` (when present)
///    - Priority 2: `(satellite, station, orbit/圈次, startTime)` + adjacent-row overlap context
///    - Merges duplicates keeping clearer/more-complete fields; flags key-field conflicts as `"待核对"`
///    - NEVER deduplicates by `startTime` alone (same `startTime` + different `station` MUST keep BOTH).
public enum PassPlanBurstEngine: Sendable {
    public struct PageInput: Equatable, Sendable {
        public var pageIndex: Int
        public var rows: [PassPlanRow]
        public var layout: PassPlan.Layout?
        public var hasOwnHeader: Bool
        /// Normalized column x-positions observed on this page (optional, for geometric alignment check).
        public var observedColumnXs: [Double]?
        /// Raw column count observed on this page (optional, for tabular alignment check).
        public var observedColumnCount: Int?

        public init(
            pageIndex: Int,
            rows: [PassPlanRow],
            layout: PassPlan.Layout?,
            hasOwnHeader: Bool,
            observedColumnXs: [Double]? = nil,
            observedColumnCount: Int? = nil
        ) {
            self.pageIndex = pageIndex
            self.rows = rows
            self.layout = layout
            self.hasOwnHeader = hasOwnHeader
            self.observedColumnXs = observedColumnXs
            self.observedColumnCount = observedColumnCount
        }
    }

    public struct BatchResult: Equatable, Sendable {
        public var tableKind: PassPlanTableKind
        public var layout: PassPlan.Layout?
        public var rows: [PassPlanRow]
        public var mergedDuplicateCount: Int
        public var conflictCount: Int
        public var alignmentWarningPages: [Int]

        public init(
            tableKind: PassPlanTableKind,
            layout: PassPlan.Layout?,
            rows: [PassPlanRow],
            mergedDuplicateCount: Int = 0,
            conflictCount: Int = 0,
            alignmentWarningPages: [Int] = []
        ) {
            self.tableKind = tableKind
            self.layout = layout
            self.rows = rows
            self.mergedDuplicateCount = mergedDuplicateCount
            self.conflictCount = conflictCount
            self.alignmentWarningPages = alignmentWarningPages
        }
    }

    // MARK: - 1. Table Kind Classification & Special Column Detection

    public static func isCreatedTimeHeader(_ label: String) -> Bool {
        let t = normalizedHeader(label)
        return t.contains("创建时间") || t.contains("制表时间") || t.contains("生成时间") || t == "创建"
    }

    public static func isEndTimeHeader(_ label: String) -> Bool {
        let t = normalizedHeader(label)
        if isCreatedTimeHeader(t) { return false }
        return t.contains("结束时间") || t.contains("数传结束") || t == "结束"
    }

    public static func isPlanCodeHeader(_ label: String) -> Bool {
        let t = normalizedHeader(label)
        return t.contains("计划编号") || t.contains("任务编号") || t.contains("计划id") || t.contains("任务id") || t == "编号"
    }

    public static func planCodeColumnIndex(in layout: PassPlan.Layout?) -> Int? {
        layout?.slots.firstIndex { isPlanCodeHeader($0.label) }
    }

    public static func createdTimeColumnIndex(in layout: PassPlan.Layout?) -> Int? {
        layout?.slots.firstIndex { isCreatedTimeHeader($0.label) }
    }

    /// Classifies table kind strictly from header labels (Photo 1's header).
    public static func classifyTableKind(layout: PassPlan.Layout?) -> PassPlanTableKind {
        guard let layout else { return .unknown }
        let labels = layout.slots.map(\.label)
        let hasEndHeader = labels.contains(where: isEndTimeHeader) || layout.columns.contains(.end)
        let hasCreatedHeader = labels.contains(where: isCreatedTimeHeader)
        if hasEndHeader {
            return .webPage
        }
        if hasCreatedHeader || layout.columns.contains(.start) {
            return .spreadsheet
        }
        return .unknown
    }

    /// Sanitizes a layout so a `创建时间` column is NEVER accidentally mapped to `.end`.
    public static func sanitizedLayout(_ layout: PassPlan.Layout) -> PassPlan.Layout {
        let fixedSlots = layout.slots.map { slot -> PassPlan.Layout.Slot in
            if isCreatedTimeHeader(slot.label) && slot.column == .end {
                return PassPlan.Layout.Slot(label: slot.label, column: nil, x: slot.x)
            }
            return slot
        }
        return PassPlan.Layout(slots: fixedSlots)
    }

    // MARK: - 2. Strict Web vs Spreadsheet Time Enforcement

    /// Applies table-kind time rules to a single row:
    /// - `.spreadsheet`: strictly ignores `创建时间`, forces `end = ""`, strips false empty-end warnings.
    /// - `.webPage`: preserves both original `start` and `end`; if `end` is blank/unreadable -> flags `"待核对"`
    ///   without substituting `创建时间` or any other timestamp.
    public static func enforceTableTimeRules(
        on row: PassPlanRow,
        tableKind: PassPlanTableKind,
        layout: PassPlan.Layout?
    ) -> PassPlanRow {
        var r = row
        switch tableKind {
        case .spreadsheet:
            // Strictly ignore 创建时间: exported & displayed end time MUST stay blank!
            r.end = ""
            if let existingIssues = r.recognitionIssues {
                let cleaned = existingIssues.filter { !$0.contains("结束时间为空") && !$0.contains("结束时间没认全") }
                r.recognitionIssues = cleaned.isEmpty ? nil : cleaned
            }
        case .webPage:
            let endTrimmed = r.end.trimmingCharacters(in: .whitespacesAndNewlines)
            if endTrimmed.isEmpty || !PassPlan.isValidTime(endTrimmed) {
                // Never borrow 创建时间 or start time as a substitute!
                if let createdIdx = createdTimeColumnIndex(in: layout),
                   createdIdx < r.cells.count,
                   !endTrimmed.isEmpty,
                   PassPlan.normalizedTime(r.cells[createdIdx]) == PassPlan.normalizedTime(endTrimmed) {
                    r.end = ""
                }
                r = appendIssue(r, "待核对：网页表数传结束时间未识别完整，请对照原图确认")
            }
        case .unknown:
            break
        }
        return r
    }

    // MARK: - 3. Column Alignment Verification for Headerless Continuation Photos

    /// Verifies whether a headerless continuation photo aligns with Photo 1's column layout.
    /// Returns true if aligned; false if column count or x-geometry deviates significantly.
    public static func isContinuationAligned(
        page: PageInput,
        anchorLayout: PassPlan.Layout
    ) -> Bool {
        if page.hasOwnHeader { return true }
        let anchorCount = anchorLayout.slots.count
        guard anchorCount >= 3 else { return true }

        if let obsCount = page.observedColumnCount, obsCount > 0 {
            // Allow at most 1 trailing/optional blank column difference; >1 means column shift!
            if abs(obsCount - anchorCount) > 1 {
                return false
            }
        }

        if let obsXs = page.observedColumnXs, obsXs.count >= 3 {
            let sortedAnchor = anchorLayout.slots.map(\.x).sorted()
            let sortedObs = obsXs.sorted()
            if abs(sortedObs.count - sortedAnchor.count) > 1 {
                return false
            }
            let pairs = min(sortedAnchor.count, sortedObs.count)
            let diffs = (0..<pairs).map { abs(sortedAnchor[$0] - sortedObs[$0]) }
            let meanDrift = diffs.reduce(0, +) / Double(max(1, pairs))
            let maxDrift = diffs.max() ?? 0
            // Significant horizontal column misalignment (>10% mean or >18% max page width)
            if meanDrift > 0.10 || maxDrift > 0.18 {
                return false
            }
        }

        // Also check row cell counts against anchor slot count if rows carry raw cells
        let nonEmptyCellCounts = page.rows.map(\.cells.count).filter { $0 > 0 }
        if !nonEmptyCellCounts.isEmpty {
            let badRows = nonEmptyCellCounts.filter { abs($0 - anchorCount) > 1 }.count
            if badRows * 2 > nonEmptyCellCounts.count {
                return false
            }
        }
        return true
    }

    // MARK: - 4. Full Multi-Shot Batch Pipeline (Header Carryover + Time Rules + Smart Overlap Dedup)

    /// Processes captured pages strictly in capture order:
    /// - Photo 1 establishes `tableKind` & `anchorLayout`.
    /// - Continuation photos inherit Photo 1's `tableKind` & `anchorLayout` when aligned;
    ///   misaligned pages are flagged `"待核对"` instead of guessing by timestamp order.
    /// - Enforces strict web vs spreadsheet time rules on every row.
    /// - Runs smart cross-photo overlap dedup (Priority 1: `计划编号`, Priority 2: `(sat, station, orbit, start)` + context).
    public static func processBurstPages(_ pages: [PageInput]) -> BatchResult {
        guard !pages.isEmpty else {
            return BatchResult(tableKind: .unknown, layout: nil, rows: [])
        }

        // 1. Anchor layout & table kind from first photo that detected headers
        let anchorLayout: PassPlan.Layout? = pages
            .first(where: { $0.hasOwnHeader && $0.layout != nil })
            .flatMap(\.layout)
            .map(sanitizedLayout)
            ?? pages.compactMap(\.layout).first.map(sanitizedLayout)

        let tableKind = classifyTableKind(layout: anchorLayout)
        var alignmentWarningPages: [Int] = []
        var normalizedPages: [[PassPlanRow]] = []

        for page in pages {
            let effectiveLayout = (page.hasOwnHeader ? page.layout.map(sanitizedLayout) : nil) ?? anchorLayout
            let aligned: Bool
            if let anchor = anchorLayout, !page.hasOwnHeader {
                aligned = isContinuationAligned(page: page, anchorLayout: anchor)
                if !aligned {
                    alignmentWarningPages.append(page.pageIndex)
                }
            } else {
                aligned = true
            }

            let processedRows = page.rows.map { raw -> PassPlanRow in
                var r = enforceTableTimeRules(on: raw, tableKind: tableKind, layout: effectiveLayout)
                if !aligned {
                    r = appendIssue(r, "待核对：第 \(page.pageIndex + 1) 张续拍列位与首张表头未对齐，请对照原图核对")
                }
                return r
            }
            normalizedPages.append(processedRows)
        }

        // 2. Smart cross-photo overlap deduplication preserving capture order
        let deduped = mergeBurstPages(normalizedPages, layout: anchorLayout, tableKind: tableKind)
        return BatchResult(
            tableKind: tableKind,
            layout: anchorLayout,
            rows: deduped.rows,
            mergedDuplicateCount: deduped.mergedCount,
            conflictCount: deduped.conflictCount,
            alignmentWarningPages: alignmentWarningPages
        )
    }

    /// Deduplicates overlapping rows across consecutive burst photos:
    /// - Priority 1: `计划编号` (plan code cell)
    /// - Priority 2: `(satellite/satelliteID, station, orbit/圈次, startTime)` reinforced by adjacent-row overlap
    /// - NEVER deduplicates by `startTime` alone (same `startTime`, different `station` -> BOTH kept!)
    /// - Merges confirmed duplicates keeping clearer/more-complete fields; flags key-field conflicts `"待核对"`.
    public static func mergeBurstPages(
        _ pages: [[PassPlanRow]],
        layout: PassPlan.Layout?,
        tableKind: PassPlanTableKind = .unknown
    ) -> (rows: [PassPlanRow], mergedCount: Int, conflictCount: Int) {
        let codeIdx = planCodeColumnIndex(in: layout)
        var result: [PassPlanRow] = []
        var mergedCount = 0
        var conflictCount = 0

        for page in pages {
            let priorBoundary = result.count
            var matchedPriorIndices = Set<Int>()
            var lastMatchedPriorIndex: Int? = nil

            for row in page {
                if let matchIdx = findCrossPageDuplicateIndex(
                    for: row,
                    in: result,
                    priorBoundary: priorBoundary,
                    alreadyMatched: matchedPriorIndices,
                    lastMatchedPriorIndex: lastMatchedPriorIndex,
                    codeIdx: codeIdx
                ) {
                    matchedPriorIndices.insert(matchIdx)
                    lastMatchedPriorIndex = matchIdx
                    mergedCount += 1
                    let merged = mergeDuplicateRow(
                        existing: result[matchIdx],
                        incoming: row,
                        tableKind: tableKind
                    )
                    if merged.hadConflict {
                        conflictCount += 1
                    }
                    result[matchIdx] = merged.row
                } else {
                    result.append(row)
                }
            }
        }
        return (result, mergedCount, conflictCount)
    }

    // MARK: - Private Matching & Merging Helpers

    private static func findCrossPageDuplicateIndex(
        for incoming: PassPlanRow,
        in existing: [PassPlanRow],
        priorBoundary: Int,
        alreadyMatched: Set<Int>,
        lastMatchedPriorIndex: Int?,
        codeIdx: Int?
    ) -> Int? {
        guard priorBoundary > 0 else { return nil }

        // Priority 1: Exact `计划编号` match across previous pages
        if let incomingCode = planCode(of: incoming, index: codeIdx) {
            let candidates = (0..<priorBoundary).filter { idx in
                !alreadyMatched.contains(idx) && planCode(of: existing[idx], index: codeIdx) == incomingCode
            }
            if candidates.count == 1 {
                return candidates[0]
            }
            if candidates.count > 1, let last = lastMatchedPriorIndex,
               let adjacent = candidates.first(where: { $0 == last + 1 }) {
                return adjacent
            }
        }

        // Priority 2: Composite key `(satellite, station, orbit, startTime)`
        // STRICT RULE: NEVER match on `startTime` alone! Station AND satellite (or satelliteID) MUST match!
        let inStart = normalizedTimeKey(incoming.start)
        let inStation = normalizedToken(incoming.station)
        let inOrbit = normalizedToken(incoming.orbit)
        guard !inStart.isEmpty, !inStation.isEmpty else { return nil }

        var strongMatches: [Int] = []
        for idx in 0..<priorBoundary where !alreadyMatched.contains(idx) {
            let old = existing[idx]
            // Must match start time AND station strictly
            guard normalizedTimeKey(old.start) == inStart,
                  normalizedToken(old.station) == inStation else { continue }
            // Must match satellite identity (satelliteID or satellite name)
            guard satellitesMatch(old, incoming) else { continue }
            // If both carry orbit/圈次, they MUST match (unless one is missing/OCR-dropped)
            let oldOrbit = normalizedToken(old.orbit)
            if !oldOrbit.isEmpty && !inOrbit.isEmpty && oldOrbit != inOrbit {
                continue
            }
            // If both carry explicit plan codes and they differ, they are distinct plans!
            if let c1 = planCode(of: old, index: codeIdx),
               let c2 = planCode(of: incoming, index: codeIdx),
               c1 != c2 {
                continue
            }
            strongMatches.append(idx)
        }

        if strongMatches.count == 1 {
            return strongMatches[0]
        }
        // Use adjacent-row overlap context to break ties when >1 candidate exists
        if strongMatches.count > 1, let last = lastMatchedPriorIndex,
           let nextAdjacent = strongMatches.first(where: { $0 == last + 1 }) {
            return nextAdjacent
        }
        return nil
    }

    private static func mergeDuplicateRow(
        existing: PassPlanRow,
        incoming: PassPlanRow,
        tableKind: PassPlanTableKind
    ) -> (row: PassPlanRow, hadConflict: Bool) {
        var out = existing
        var conflicts: [String] = []

        func mergeField(_ fieldLabel: String, _ a: String, _ b: String, isKeyField: Bool) -> String {
            let ca = a.trimmingCharacters(in: .whitespacesAndNewlines)
            let cb = b.trimmingCharacters(in: .whitespacesAndNewlines)
            if ca.isEmpty { return cb }
            if cb.isEmpty { return ca }
            if normalizedToken(ca) == normalizedToken(cb) {
                return cb.count > ca.count ? cb : ca
            }
            if isKeyField {
                conflicts.append("\(fieldLabel)不一致（\(ca) vs \(cb)）")
            }
            // Keep existing value intact without silently overwriting on conflict; user sees conflict tag
            return ca
        }

        out.orbit = mergeField("圈次", existing.orbit, incoming.orbit, isKeyField: true)
        out.satelliteID = mergeField("卫星ID", existing.satelliteID, incoming.satelliteID, isKeyField: true)
        out.satellite = mergeField("卫星", existing.satellite, incoming.satellite, isKeyField: true)
        out.station = mergeField("地面站", existing.station, incoming.station, isKeyField: true)
        out.start = mergeField("数传开始时间", existing.start, incoming.start, isKeyField: true)
        if tableKind == .spreadsheet {
            out.end = ""
        } else {
            out.end = mergeField("数传结束时间", existing.end, incoming.end, isKeyField: true)
        }
        out.info = mergeField("数传信息", existing.info, incoming.info, isKeyField: false)
        out.status = mergeField("状态", existing.status, incoming.status, isKeyField: true)

        // Preserve richer cells array when no conflict
        if incoming.cells.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count
            > existing.cells.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count {
            out.cells = incoming.cells
        }

        // Preserve emergency/test safety flags conservatively
        if existing.testStatusDetected == true || incoming.testStatusDetected == true {
            out.testStatusDetected = true
        }
        if let e1 = existing.emergencyBadge, let e2 = incoming.emergencyBadge, e1 != e2 {
            conflicts.append("应急标记不一致")
        } else {
            out.emergencyBadge = existing.emergencyBadge ?? incoming.emergencyBadge
        }

        // Retain union of existing issues + any new conflict warnings
        var mergedIssues = existing.recognitionIssues ?? []
        for issue in incoming.recognitionIssues ?? [] where !mergedIssues.contains(issue) {
            mergedIssues.append(issue)
        }
        if !conflicts.isEmpty {
            let msg = "待核对：跨页重叠行存在字段冲突（\(conflicts.joined(separator: "；"))），请对照原图确认"
            if !mergedIssues.contains(msg) {
                mergedIssues.append(msg)
            }
        }
        out.recognitionIssues = mergedIssues.isEmpty ? nil : mergedIssues
        return (out, !conflicts.isEmpty)
    }

    private static func satellitesMatch(_ a: PassPlanRow, _ b: PassPlanRow) -> Bool {
        let idA = normalizedToken(a.satelliteID)
        let idB = normalizedToken(b.satelliteID)
        if !idA.isEmpty && !idB.isEmpty {
            return idA == idB
        }
        let nameA = normalizedToken(a.satellite)
        let nameB = normalizedToken(b.satellite)
        if !nameA.isEmpty && !nameB.isEmpty {
            return nameA == nameB
        }
        // Cross-check if one side stored ID in `satellite` column
        if !idA.isEmpty && !nameB.isEmpty { return idA == nameB }
        if !nameA.isEmpty && !idB.isEmpty { return nameA == idB }
        return false
    }

    private static func planCode(of row: PassPlanRow, index: Int?) -> String? {
        guard let idx = index, idx < row.cells.count else { return nil }
        let clean = normalizedToken(row.cells[idx])
        return clean.isEmpty ? nil : clean
    }

    private static func normalizedHeader(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace }
    }

    private static func normalizedToken(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { !$0.isWhitespace }
    }

    private static func normalizedTimeKey(_ s: String) -> String {
        let norm = PassPlan.normalizedTime(s).trimmingCharacters(in: .whitespacesAndNewlines)
        return norm.isEmpty ? normalizedToken(s) : norm
    }

    private static func appendIssue(_ row: PassPlanRow, _ issue: String) -> PassPlanRow {
        var r = row
        var list = r.recognitionIssues ?? []
        if !list.contains(issue) {
            list.append(issue)
        }
        r.recognitionIssues = list
        return r
    }
}
