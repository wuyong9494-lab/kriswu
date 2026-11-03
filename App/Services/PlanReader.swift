import CoreImage
import UIKit
import UniformTypeIdentifiers
import Vision

/// 读数传计划：照片用手机自带的文字识别（不联网），表格文件、复制的表格直接读
enum PlanReader {
    enum Failure: LocalizedError {
        case noText, noTable
        var errorDescription: String? {
            switch self {
            case .noText: return "照片里没认出字：靠近一点、对准表格、别反光，再拍一张"
            case .noTable: return "没认出表头（卫星名称、地面站、数传开始时间这几列），表格要拍全表头那一行"
            }
        }
    }

    /// 怎么认（测试里比较几种设置；App 里都用 standard）
    struct Settings: Sendable {
        /// 不跳过小字：系统默认跳过不到图高 1/32 的字，一张照片里几十行的表，每行的字都比这小
        var smallText = true
        /// 按中文、英文的词纠正认错的字（表头、运营商名、站名开头当词库）
        var languageCorrection = true
        /// iOS 26 起也让系统直接按格子认表格，用它核对站名
        var tables = true
        /// 每张照片认几遍、每遍怎么认，几遍拼出来的一行行对着挑（哪种认法好看照片：密密麻麻的 Excel 分段认好，
        /// 有的网页照片分段认反而漏行、整张认好，摩尔纹重的去一下纹好）
        var passes = Pass.all
        /// 仅测试显式开启：输出阶段、尺寸、计数和耗时，不记录识别文字。
        var diagnostics = false

        struct Pass: Sendable, Hashable {
            /// 很长的图切成上下几段分别认
            var split = true
            /// 认之前轻轻模糊一下，压掉拍屏幕的摩尔纹
            var smooth = false

            static let all = [Pass(), Pass(smooth: true), Pass(split: false)]
        }

        static let standard = Settings()
    }

    /// 拆格复识的整张照片预算。先公平分给各 pass，再在该 pass 的各段间按顺序分配。
    /// 各段拿自己的固定份额，前段不会耗尽后段的复识额度。
    static func splitRereadBudgets(total: Int, stripCounts: [Int]) -> [[Int]] {
        let counts = stripCounts.map { max(0, $0) }
        let active = counts.indices.filter { counts[$0] > 0 }
        var result = counts.map { [Int](repeating: 0, count: $0) }
        let passShares = equalShares(total: max(0, total), count: active.count)
        for (offset, pass) in active.enumerated() {
            result[pass] = equalShares(total: passShares[offset], count: counts[pass])
        }
        return result
    }

    private static func equalShares(total: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let share = total / count, extra = total % count
        return (0..<count).map { share + ($0 < extra ? 1 : 0) }
    }

    struct SplitRereadBudget: Sendable {
        let limit: Int
        private(set) var used = 0
        var remaining: Int { limit - used }

        init(limit: Int) { self.limit = max(0, limit) }

        /// 拆一组必须够这一整组的额度；额度不足时一个也不花，保留原始 OCR 框。
        mutating func reserve(groupSize: Int) -> Bool {
            guard groupSize > 0, groupSize <= remaining else { return false }
            used += groupSize
            return true
        }
    }

    private struct Trace: Sendable {
        let enabled: Bool
        let stage: String
        let began: Date

        init(_ enabled: Bool, _ stage: String, _ details: String = "") {
            self.enabled = enabled
            self.stage = stage
            began = Date()
            if enabled { print("OCRSTAGE|\(stage)|start|\(details)") }
        }

        func end(_ details: String = "") {
            guard enabled else { return }
            let seconds = String(format: "%.3f", Date().timeIntervalSince(began))
            print("OCRSTAGE|\(stage)|end|seconds=\(seconds)|\(details)")
        }
    }

    /// 几张照片（计划长、往下翻着拍的）→ 合成一份。第一张要拍到表头；后面几张没拍到表头的，按前一张的列分。
    /// 网页上的表、电脑上打开的导出 Excel 都行：拍到什么表头，发出去的表就是什么表头。
    /// rules：运营商对照表（站名开头给文字识别当词库）
    static func read(pages images: [UIImage], rules: [PassPlan.OperatorRule] = [],
                     settings: Settings = .standard) async throws -> PassPlan.Reading {
        let words = PassPlan.vocabulary(rules)
        var pages: [[PassPlanRow]] = []
        var sawText = false
        /// 发出去的表用的列：第一张认出表头的那张的
        var layout: PassPlan.Layout?
        /// 没拍到表头的照片按这个分列（照片里的左右位置）
        var positions: PassPlan.Layout?
        /// 发原图用：表头那一条，和每一条从照片上裁下来扶正的图
        var header: PassPlan.Region?
        var strips: [PassPlan.Region: Data] = [:]
        for (page, image) in images.enumerated() {
            guard let picture = upright(image) else { continue }
            let pageTrace = Trace(settings.diagnostics, "page\(page)", "size=\(picture.width)x\(picture.height)")
            defer { pageTrace.end() }
            // 几种认法依次认，控制同时运行的 Vision 请求数量，再把各遍结果逐行核对
            let readings = try await boxes(of: picture, words: words, settings: settings)
            sawText = sawText || readings.contains { !$0.isEmpty }
            let parseTrace = Trace(settings.diagnostics, "parse\(page)", "readings=\(readings.count)")
            let pageReadings = readings.map { PassPlan.read($0, fallback: positions) }
            parseTrace.end("rows=\(pageReadings.map { $0.rows.count })")
            let combineTrace = Trace(settings.diagnostics, "combine\(page)", "readings=\(pageReadings.count)")
            var result = PassPlan.combine(pageReadings, rules: rules)
            combineTrace.end("rows=\(result.rows.count)")
            // 连拍时取景可能变了：本页重新拍到表头，就用本页的列位置继续向下读。
            // 只接受带几何表头的布局；系统表格识别的 x 是列号（0、1、2…），不能拿来分照片里的列。
            let geometric: PassPlan.Reading? = result.header != nil ? result : pageReadings.filter { $0.header != nil }
                .max { PassPlan.score($0, rules: rules) < PassPlan.score($1, rules: rules) }
            if let latest = geometric?.layout { positions = latest }
            // iOS 26 起系统还能直接按格子认表格：按位置拼的什么都没拼出来就用它（没有原图）；
            // 拼出来了就拿它核对站名（同一行它认的站名对得上对照表、这边的对不上，用它的）
            if #available(iOS 26.0, *), settings.tables, let table = await tableReading(in: picture, words: words, settings: settings) {
                sawText = sawText || !table.rows.isEmpty
                if result.rows.isEmpty {
                    result = table
                } else {
                    let adoptTrace = Trace(settings.diagnostics, "tableMerge\(page)", "rows=\(result.rows.count)|tableRows=\(table.rows.count)")
                    result.rows = PassPlan.adoptStations(result.rows, from: table.rows, rules: rules)
                    adoptTrace.end("rows=\(result.rows.count)")
                }
            }
            guard let found = result.layout else { continue }
            for i in result.rows.indices { result.rows[i].region?.page = page }
            result.rows = await rereadStations(result.rows, layout: found, in: picture, rules: rules, words: words, settings: settings)
            result.rows = await rereadRowMarkers(result.rows, layout: found, in: picture, settings: settings)
            if found.columns.contains(.status) {
                for i in result.rows.indices where !PassPlan.isExcludedFromSending(result.rows[i])
                    && result.rows[i].status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // 空白读数无法证明它不是 test；人工对照原图保存后可解除这项识别疑问。
                    let issue = "状态没认出来，请核对原图是否为 test"
                    if !(result.rows[i].recognitionIssues ?? []).contains(issue) {
                        result.rows[i].recognitionIssues = (result.rows[i].recognitionIssues ?? []) + [issue]
                    }
                }
            }
            // 编号即使格式合法也可能把 0/C、1/L、5/6 读错。用原格的英文无纠错读数核对，
            // 只为当前可发送的记录补充疑项；不同读数不自动覆盖原值。
            result.rows = await reviewIdentifiers(result.rows, layout: found, in: picture, rules: rules, settings: settings)
            // 多遍 Vision 也会把同一个编号读成相同的错误值。照片代号必须由人对照原图确认；
            // 复识只补充候选分歧，不能代替确认。已有 test 记录继续直接排除。
            for i in result.rows.indices {
                let row = result.rows[i]
                guard !PassPlan.isExcludedFromSending(row),
                      let column = identifierColumn(for: row, layout: found),
                      let field = found.slots[column].column else { continue }
                result.rows[i] = PassPlan.requiringPhotoIdentifierReview(row, column: field)
            }
            // 所有行（包括稍后不发的 test）都参与裁切边界，避免正常条带带入相邻 test 行。
            result.rows = PassPlan.boundedRegions(result.rows)
            result.header?.page = page
            let pageHeader = header == nil ? result.header : nil
            header = header ?? result.header
            let regions = result.rows.compactMap(\.region) + (pageHeader.map { [$0] } ?? [])
            let cuts = await cut(regions, from: picture, diagnostics: settings.diagnostics)
            strips.merge(cuts) { old, _ in old }
            let target = layout ?? found
            layout = target
            pages.append(PassPlan.remap(result.rows, from: found, to: target))
        }
        guard sawText else { throw Failure.noText }
        let mergeTrace = Trace(settings.diagnostics, "pageMerge", "pages=\(pages.count)")
        let rows = PassPlan.merge(pages, layout: layout)
        mergeTrace.end("rows=\(rows.count)")
        guard !rows.isEmpty else { throw Failure.noTable }
        return PassPlan.Reading(rows: rows, layout: layout, header: header, strips: strips)
    }

    /// 最要紧的两格再认一遍：每一行把「地面站」那一格（分家只看它）、没认出来的「是否应急」那一格（决定图下面那句话）
    /// 单独裁下来、放大了再认（一小格单独认，比一整张里一起认准得多）。
    /// 地面站：已知站名不被一次复识覆盖；未知站只有两次局部复识一致、且对得上明确对照表才修正。
    /// 是否应急：再认出「是 / 不是」就填上。冲突保留在行里，供核对页显示。
    static func rereadStations(_ rows: [PassPlanRow], layout: PassPlan.Layout, in image: CGImage,
                               rules: [PassPlan.OperatorRule], words: [String], settings: Settings) async -> [PassPlanRow] {
        let station = layout.slots.firstIndex { $0.column == .station }
        let urgent = layout.emergencyIndex
        guard station != nil || urgent != nil else { return rows }
        return await Task.detached(priority: .userInitiated) {
            let trace = Trace(settings.diagnostics, "stationCells", "rows=\(rows.count)")
            let context = CIContext()
            var attempts = 0
            defer { trace.end("cropAttempts=\(attempts)") }
            /// 这一行第 s 列那一格单独认出的字
            func reread(column s: Int, of region: PassPlan.Region, using options: Settings) -> String? {
                attempts += 1
                guard let crop = Self.cropCell(column: s, of: region, layout: layout, from: image, context: context) else { return nil }
                let text = Self.recognizeCell(crop, words: words, settings: options, smooth: false, diagnosticID: "column\(s)")?
                    .filter { !$0.isWhitespace }
                return text?.isEmpty == false ? text : nil
            }
            return rows.map { row in
                guard let region = row.region else { return row }
                var fixed = row
                if let s = station, !rules.isEmpty,
                   let again = reread(column: s, of: region, using: settings) {
                    var candidates = [again]
                    if PassPlan.operatorName(of: row.station, rules: rules) == nil,
                       PassPlan.operatorName(of: again, rules: rules) != nil {
                        // 仅在可能修好未知站时，多认这一小格；不增加整张照片的识别遍数。
                        // 关闭词语纠错再核对一次，防止词库把模糊文字硬套成另一家已知站。
                        var independent = settings
                        independent.languageCorrection.toggle()
                        if let confirmation = reread(column: s, of: region, using: independent) {
                            candidates.append(confirmation)
                        }
                    }
                    fixed = PassPlan.reviewStationReread(row, candidates: candidates, rules: rules)
                }
                if let e = urgent, PassPlan.emergency(fixed, layout: layout) == nil,
                   let again = reread(column: e, of: region, using: settings) {
                    var trial = fixed
                    while trial.cells.count <= e { trial.cells.append("") }
                    trial.cells[e] = again
                    if PassPlan.emergency(trial, layout: layout) != nil { fixed = trial }
                }
                return fixed
            }
        }.value
    }

    /// 整格补读只用已限定的行带：列界取相邻表头中点，四角随行倾斜，不能再向邻行补像素。
    static func boundedCellRegion(column s: Int, of region: PassPlan.Region, layout: PassPlan.Layout) -> PassPlan.Region? {
        let xs = layout.slots.map(\.x)
        guard xs.indices.contains(s), xs.allSatisfy(\.isFinite),
              region.y0.isFinite, region.slope.isFinite, region.height.isFinite, region.height > 0,
              region.left.isFinite, region.right.isFinite else { return nil }
        let left = max(max(0, region.left), s > 0 ? (xs[s - 1] + xs[s]) / 2 : region.left)
        let right = min(min(1, region.right), s < xs.count - 1 ? (xs[s] + xs[s + 1]) / 2 : region.right)
        guard right > left else { return nil }
        let leftY = region.y0 + region.slope * left
        let rightY = region.y0 + region.slope * right
        let imageMargin = min(min(leftY, rightY), min(1 - leftY, 1 - rightY))
        let halfHeight = min(region.height * 0.45, imageMargin)
        guard halfHeight > 0 else { return nil }
        return PassPlan.Region(page: region.page, y0: region.y0, slope: region.slope, height: halfHeight * 2,
                               left: left, right: right)
    }

    /// 与发原图同样沿四角扶正，直接给 OCR 原始像素，不经过 JPEG，也不调用词框的外扩裁法。
    static func cropCell(column: Int, of region: PassPlan.Region, layout: PassPlan.Layout, from image: CGImage,
                         context: CIContext) -> CGImage? {
        guard let cell = boundedCellRegion(column: column, of: region, layout: layout),
              let straight = straightened(cell, source: CIImage(cgImage: image),
                                          width: Double(image.width), height: Double(image.height)),
              straight.extent.width > 2, straight.extent.height > 2 else { return nil }
        return context.createCGImage(straight, from: straight.extent)
    }

    /// 明确的卫星编号列；Excel 的「卫星」列只有出现字母数字代号时才参与编号核对。
    static func identifierColumn(for row: PassPlanRow, layout: PassPlan.Layout) -> Int? {
        if let index = layout.slots.firstIndex(where: { $0.column == .satelliteID }) { return index }
        guard let index = layout.slots.firstIndex(where: { $0.column == .satellite }),
              layout.slots[index].label.filter({ !$0.isWhitespace }) == "卫星" else { return nil }
        let scalars = row.satellite.unicodeScalars
        let hasLetter = scalars.contains { (65...90).contains($0.value) || (97...122).contains($0.value) }
        let hasDigit = scalars.contains { (48...57).contains($0.value) }
        let hasOtherLetter = scalars.contains { $0.value > 127 && CharacterSet.letters.contains($0) }
        return hasLetter && hasDigit && !hasOtherLetter ? index : nil
    }

    /// 首列外侧不包含 Excel 行号栏，边界来自表头间距，不根据候选编号或真值猜裁框。
    static func identifierCellRegion(column: Int, of region: PassPlan.Region, layout: PassPlan.Layout) -> PassPlan.Region? {
        let xs = layout.slots.map(\.x)
        guard xs.indices.contains(column), xs.allSatisfy(\.isFinite) else { return nil }
        var bounded = region
        if xs.count > 1 {
            bounded.left = max(bounded.left, xs[0] - (xs[1] - xs[0]) / 2)
            let last = xs.count - 1
            bounded.right = min(bounded.right, xs[last] + (xs[last] - xs[last - 1]) / 2)
        }
        return boundedCellRegion(column: column, of: bounded, layout: layout)
    }

    /// 已有疑项或 test 的行无需再消耗识别请求；每页最多 100 格，未能核对的格子保留核对提示。
    static func reviewIdentifiers(_ rows: [PassPlanRow], layout: PassPlan.Layout, in image: CGImage,
                                  rules: [PassPlan.OperatorRule], settings: Settings) async -> [PassPlanRow] {
        let work: Task<[PassPlanRow], Never> = Task.detached(priority: .userInitiated) {
            let trace = Trace(settings.diagnostics, "identifierReview", "rows=\(rows.count)|limit=100")
            let context = CIContext()
            let source = CIImage(cgImage: image)
            var attempts = 0
            var result = rows
            defer { trace.end("cropAttempts=\(attempts)") }
            for i in result.indices {
                let row = result[i]
                guard !PassPlan.isExcludedFromSending(row),
                      PassPlan.problems(row, rules: rules, layout: layout).isEmpty,
                      let column = identifierColumn(for: row, layout: layout),
                      let field = layout.slots[column].column else { continue }
                var candidates: [String] = []
                if attempts < 100, let region = row.region,
                   let cell = identifierCellRegion(column: column, of: region, layout: layout),
                   let straight = straightened(cell, source: source, width: Double(image.width), height: Double(image.height)),
                   straight.extent.width > 2, straight.extent.height > 2 {
                    let scale = min(4, max(1, (80 / straight.extent.height).rounded(.up)))
                    let sized = straight.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    if let crop = context.createCGImage(sized, from: sized.extent) {
                        attempts += 1
                        let request = VNRecognizeTextRequest()
                        request.recognitionLevel = .accurate
                        request.recognitionLanguages = ["en-US"]
                        request.usesLanguageCorrection = false
                        request.customWords = []
                        if (try? VNImageRequestHandler(cgImage: crop, orientation: .up).perform([request])) != nil {
                            let raw = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                            candidates = [raw]
                        }
                    }
                }
                result[i] = PassPlan.reviewIdentifierReread(row, column: field, candidates: candidates)
            }
            return result
        }
        return await work.value
    }

    /// 网页的无表头「应急」在 No. 左边；test 在最右状态列。
    /// 只补读有明确列位置的窄边栏，再交给核心按唯一行几何挂接；不根据红色背景推断。
    /// 每页最多两次窄栏识别，避免每个普通空白行都再跑一遍 OCR。
    static func rereadRowMarkers(_ rows: [PassPlanRow], layout: PassPlan.Layout, in image: CGImage,
                                 settings: Settings) async -> [PassPlanRow] {
        let trace = Trace(settings.diagnostics, "markers", "rows=\(rows.count)")
        defer { trace.end() }
        let regions: [PassPlan.Region] = rows.compactMap(\.region)
        guard !regions.isEmpty else { return rows }
        let bands: [MarkerBand] = rowMarkerBands(rows, layout: layout, regions: regions)
        guard !bands.isEmpty else { return rows }
        let work: Task<[PassPlanRow], Never> = Task.detached(priority: .userInitiated) { () -> [PassPlanRow] in
            let markers = scanRowMarkers(in: image, bands: bands, regions: regions, settings: settings)
            return PassPlan.applyingRowMarkers(rows, markers: markers, layout: layout)
        }
        return await work.value
    }

    private struct MarkerBand: Sendable {
        var left: Double
        var right: Double
    }

    private static func rowMarkerBands(_ rows: [PassPlanRow], layout: PassPlan.Layout,
                                       regions: [PassPlan.Region]) -> [MarkerBand] {
        let slots: [PassPlan.Layout.Slot] = layout.slots.sorted { $0.x < $1.x }
        guard slots.count > 1, slots.allSatisfy({ $0.x >= 0 && $0.x <= 1 }) else { return [] }
        let tableLeft: Double = regions.map(\.left).min() ?? 0
        let tableRight: Double = regions.map(\.right).max() ?? 1
        var bands: [MarkerBand] = []
        let first = slots[0]
        let needsBadge = rows.contains { PassPlan.emergency($0, layout: layout) != true }
        if first.column == .number, layout.emergencyIndex == nil, needsBadge {
            let gap: Double = slots[1].x - first.x
            let left: Double = max(tableLeft, first.x - gap * 1.5)
            let right: Double = first.x - gap * 0.45
            if right > left { bands.append(MarkerBand(left: left, right: right)) }
        }
        // 即使本轮填了普通状态，也独立核对右栏，防止错行的普通标签掩盖真正的 test。
        let needsStatus = rows.contains { !PassPlan.isExcludedFromSending($0) }
        if needsStatus, let index = slots.firstIndex(where: { $0.column == .status }) {
            var left = tableLeft
            var right = tableRight
            if index > 0 { left = (slots[index - 1].x + slots[index].x) / 2 }
            if index + 1 < slots.count { right = (slots[index].x + slots[index + 1].x) / 2 }
            if right > left { bands.append(MarkerBand(left: left, right: right)) }
        }
        return bands
    }

    private static func markerCrop(_ band: MarkerBand, regions: [PassPlan.Region],
                                   imageWidth: Int, imageHeight: Int) -> CGRect? {
        var top = Double.infinity
        var bottom = -Double.infinity
        for region in regions {
            let atLeft: Double = region.y0 + region.slope * band.left
            let atRight: Double = region.y0 + region.slope * band.right
            top = min(top, min(atLeft, atRight) - region.height / 2)
            bottom = max(bottom, max(atLeft, atRight) + region.height / 2)
        }
        guard top.isFinite, bottom.isFinite else { return nil }
        let w = Double(imageWidth)
        let h = Double(imageHeight)
        let proposed = CGRect(x: CGFloat(band.left * w), y: CGFloat(top * h),
                              width: CGFloat((band.right - band.left) * w), height: CGFloat((bottom - top) * h))
        let bounds = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        let rect = proposed.intersection(bounds).integral
        return !rect.isNull && rect.width > 4 && rect.height > 4 ? rect : nil
    }

    private static func scanRowMarkers(in image: CGImage, bands: [MarkerBand], regions: [PassPlan.Region],
                                       settings: Settings) -> [PassPlan.TextBox] {
        var markers: [PassPlan.TextBox] = []
        for band in bands {
            guard let rect = markerCrop(band, regions: regions, imageWidth: image.width, imageHeight: image.height) else { continue }
            markers.append(contentsOf: markerTextBoxes(in: image, rect: rect, settings: settings))
        }
        return markers
    }

    private static func markerTextBoxes(in image: CGImage, rect: CGRect, settings: Settings) -> [PassPlan.TextBox] {
        guard let crop = image.cropping(to: rect) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        // 状态中的英文代码按原文读，不能让词语纠错把别的词替成 test。
        request.usesLanguageCorrection = false
        if settings.smallText { request.minimumTextHeight = minimumTextHeight(crop.height) }
        let handler = VNImageRequestHandler(cgImage: crop, orientation: .up)
        guard (try? handler.perform([request])) != nil else { return [] }
        let w = Double(image.width)
        let h = Double(image.height)
        let originX = Double(rect.minX)
        let originY = Double(rect.minY)
        let cropWidth = Double(rect.width)
        let cropHeight = Double(rect.height)
        var boxes: [PassPlan.TextBox] = []
        for observation in request.results ?? [] {
            guard let text = observation.topCandidates(1).first?.string else { continue }
            let token = text.filter { !$0.isWhitespace }.lowercased()
            guard token == "应急" || PassPlan.isTestStatus(text) else { continue }
            let box = observation.boundingBox
            let x: Double = (originX + Double(box.minX) * cropWidth) / w
            let y: Double = (originY + (1 - Double(box.maxY)) * cropHeight) / h
            let width: Double = Double(box.width) * cropWidth / w
            let height: Double = Double(box.height) * cropHeight / h
            boxes.append(PassPlan.TextBox(text: text, x: x, y: y, width: width, height: height))
        }
        return boxes
    }

    // MARK: - 发原图：从照片上裁

    /// 从照片上裁下这几条（每一行、表头），各自扶正成长方形，存成 JPEG（宽最多 2400）
    static func cut(_ regions: [PassPlan.Region], from image: CGImage, diagnostics: Bool = false) async -> [PassPlan.Region: Data] {
        await Task.detached(priority: .userInitiated) {
            let trace = Trace(diagnostics, "cut", "size=\(image.width)x\(image.height)|regions=\(regions.count)")
            defer { trace.end() }
            let context = CIContext()
            // 照片自动调一下明暗、对比（屏幕拍出来常常发灰）
            var source = CIImage(cgImage: image)
            for filter in source.autoAdjustmentFilters(options: [.redEye: false]) {
                filter.setValue(source, forKey: kCIInputImageKey)
                if let adjusted = filter.outputImage { source = adjusted }
            }
            let w = Double(image.width), h = Double(image.height)
            var result: [PassPlan.Region: Data] = [:]
            for region in regions {
                guard let straight = straightened(region, source: source, width: w, height: h),
                      straight.extent.width > 1 else { continue }
                let scale = min(1, 2400 / straight.extent.width)
                let sized = straight.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                if let data = context.jpegRepresentation(of: sized, colorSpace: CGColorSpaceCreateDeviceRGB(),
                                                         options: [:]) {
                    result[region] = data
                }
            }
            return result
        }.value
    }

    private static func straightened(_ region: PassPlan.Region, source: CIImage, width: Double, height: Double) -> CIImage? {
        // CoreImage 的原点在左下；上下边沿同一条倾斜行，不能用包围矩形代替。
        func corner(_ x: Double, _ dy: Double) -> CIVector {
            CIVector(x: x * width, y: height - (region.y0 + region.slope * x + dy) * height)
        }
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(corner(region.left, -region.height / 2), forKey: "inputTopLeft")
        filter.setValue(corner(region.right, -region.height / 2), forKey: "inputTopRight")
        filter.setValue(corner(region.right, region.height / 2), forKey: "inputBottomRight")
        filter.setValue(corner(region.left, region.height / 2), forKey: "inputBottomLeft")
        return filter.outputImage
    }

    /// 表格文件（Excel、CSV）
    static func read(file url: URL) throws -> PassPlan.Reading {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let table: [[String]]
        switch url.pathExtension.lowercased() {
        case "xlsx": table = XLSXReader.rows(data) ?? []
        case "csv": table = MeetingTable.rows(String(decoding: data, as: UTF8.self), separator: ",")
        default: table = MeetingTable.rows(String(decoding: data, as: UTF8.self), separator: "\t")
        }
        let reading = PassPlan.readTable(table)
        guard !reading.rows.isEmpty else { throw Failure.noTable }
        return reading
    }

    /// 剪贴板里的表格（网页、Excel 里选中复制的）
    @MainActor
    static func readClipboard() throws -> PassPlan.Reading {
        let board = UIPasteboard.general
        var tables: [[[String]]] = []
        if let data = board.data(forPasteboardType: UTType.html.identifier) {
            tables.append(MeetingTable.htmlRows(String(decoding: data, as: UTF8.self)))
        }
        if let text = board.string {
            tables.append(MeetingTable.rows(text, separator: "\t"))
        }
        guard let reading = tables.lazy.map(PassPlan.readTable).first(where: { !$0.rows.isEmpty }) else { throw Failure.noTable }
        return reading
    }

    // MARK: - 文字识别

    /// 这张照片要认的几遍：只有一段的照片分不分段一样，少认一遍
    private static func passes(of image: CGImage, settings: Settings) -> [Settings.Pass] {
        let single = PassPlan.strips(width: image.width, height: image.height).count == 1
        var seen = Set<Settings.Pass>()
        let list = settings.passes.map { single ? Settings.Pass(split: false, smooth: $0.smooth) : $0 }
            .filter { seen.insert($0).inserted }
        return list.isEmpty ? [Settings.Pass()] : list
    }

    /// 按 passes 顺序逐遍识别：同一张照片同一时刻只执行一个 pass，限制 Vision 资源占用。
    /// 各遍保留所有分段和既定拆格额度，返回顺序与 passes 一致。
    private static func boxes(of image: CGImage, words: [String], settings: Settings) async throws -> [[PassPlan.TextBox]] {
        let list = passes(of: image, settings: settings)
        let stripCounts: [Int] = list.map { pass in
            pass.split ? PassPlan.strips(width: image.width, height: image.height).count : 1
        }
        let budgets = splitRereadBudgets(total: 400, stripCounts: stripCounts)
        let trace = Trace(settings.diagnostics, "allPasses", "size=\(image.width)x\(image.height)|strips=\(stripCounts)|splitBudgets=\(budgets)")
        defer { trace.end() }
        var found: [[PassPlan.TextBox]] = []
        for (i, pass) in list.enumerated() {
            let boxes = try await textBoxes(in: image, words: words, settings: settings, pass: pass,
                                            splitBudgets: budgets[i], diagnosticID: "pass\(i)")
            found.append(boxes)
        }
        return found
    }

    /// 认出图里的字：每一块按空格再拆开（相邻两格偶尔被认成一块），各自带位置（整张图的 0–1，y 从上往下）。
    /// 很长的图切成上下重叠的几段分别认：整张一起认，字相对整张图太小，会被跳过或认错
    static func textBoxes(in image: CGImage, words: [String] = [], settings: Settings = .standard,
                          pass: Settings.Pass = Settings.Pass(), splitBudgets: [Int]? = nil,
                          diagnosticID: String = "singlePass") async throws -> [PassPlan.TextBox] {
        try await Task.detached(priority: .userInitiated) {
            let strips = pass.split ? PassPlan.strips(width: image.width, height: image.height)
                : [PassPlan.Strip(top: 0, height: image.height, keep: -Double.infinity..<Double.infinity)]
            var boxes: [PassPlan.TextBox] = []
            let quotas = splitBudgets ?? splitRereadBudgets(total: 400, stripCounts: [strips.count])[0]
            for (index, strip) in strips.enumerated() {
                let piece = strips.count == 1 ? image
                    : image.cropping(to: CGRect(x: 0, y: strip.top, width: image.width, height: strip.height))
                guard let piece else { continue }
                let quota = index < quotas.count ? quotas[index] : 0
                let found = try recognize(piece, words: words, settings: settings, smooth: pass.smooth,
                                          splitBudget: quota, diagnosticID: "\(diagnosticID).strip\(index)")
                boxes += PassPlan.place(found, in: strip, imageHeight: image.height)
            }
            return boxes
        }.value
    }

    /// 字最小多高（占图高的比例）：十来个像素高的字也认
    private static func minimumTextHeight(_ pixelHeight: Int) -> Float {
        Float(max(10 / Double(max(pixelHeight, 1)), 0.002))
    }

    private static func recognize(_ source: CGImage, words: [String], settings: Settings,
                                  smooth: Bool, splitBudget: Int, diagnosticID: String) throws -> [PassPlan.TextBox] {
        let mainTrace = Trace(settings.diagnostics, "mainOCR.\(diagnosticID)", "size=\(source.width)x\(source.height)")
        let image = prepared(source, smooth: smooth, enlarge: false)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = settings.languageCorrection
        if settings.languageCorrection { request.customWords = words }
        if settings.smallText { request.minimumTextHeight = minimumTextHeight(image.height) }
        // 系统另外找一遍「一块块的字」（按空隙分开，不管认不认得），用来把连成一长串的整行拆回一格格
        let blocks = VNDetectTextRectanglesRequest()
        blocks.reportCharacterBoxes = true
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request, blocks])
        mainTrace.end("observations=\(request.results?.count ?? 0)|blocks=\(blocks.results?.count ?? 0)")
        let aspect = Double(image.width) / Double(max(image.height, 1))
        let spots = (blocks.results ?? []).map { block in
            (box: PassPlan.TextBox(text: "", x: block.boundingBox.minX, y: 1 - block.boundingBox.maxY,
                                   width: block.boundingBox.width, height: block.boundingBox.height),
             count: block.characterBoxes?.count ?? 0)
        }
        var result: [PassPlan.TextBox] = []
        let tokenTrace = Trace(settings.diagnostics, "tokens.\(diagnosticID)")
        let tokenBoxes: [PassPlan.TextBox] = (request.results ?? []).flatMap { tokens($0, aspect: aspect) }
        tokenTrace.end("boxes=\(tokenBoxes.count)")
        var budget = SplitRereadBudget(limit: splitBudget)
        var budgetLimitedGroups = 0
        var failedGroups = 0
        let splitTrace = Trace(settings.diagnostics, "splitOCR.\(diagnosticID)", "limit=\(budget.limit)")
        defer { splitTrace.end("cropAttempts=\(budget.used)|budgetLimitedGroups=\(budgetLimitedGroups)|failedGroups=\(failedGroups)|boxes=\(result.count)") }
        for box in tokenBoxes {
            // 认出的一块字（中文常把隔得很远的一整行认成一串，还会漏字）横跨好几块隔开的字
            let inside = spots.filter { spot in
                let midX = spot.box.x + spot.box.width / 2, midY = spot.box.y + spot.box.height / 2
                return spot.count > 0 && midX > box.x && midX < box.x + box.width && midY > box.y && midY < box.y + box.height
            }.sorted { $0.box.x < $1.box.x }
            guard inside.count > 1 else {
                result.append(box)
                continue
            }
            // 字数对得上：按每块几个字依次分
            let characters = Array(box.text)
            if inside.reduce(0, { $0 + $1.count }) == characters.count {
                var start = 0
                for spot in inside {
                    var piece = spot.box
                    piece.text = String(characters[start..<(start + spot.count)])
                    result.append(piece)
                    start += spot.count
                }
                continue
            }
            // 对不上才拆格复识；整张照片最多 400 次，已提前公平分给各 pass/strip。
            // 额度不够整组就保留原框，不拆一半，不消耗额度，也不丢掉原始字。
            guard budget.reserve(groupSize: inside.count) else {
                budgetLimitedGroups += 1
                result.append(box)
                continue
            }
            let separated = inside.compactMap {
                reread($0.box, in: image, words: words, settings: settings, smooth: smooth, diagnosticID: diagnosticID)
            }
            // 分格复识有一块失败，不能静默丢掉它：保留本轮原始识别，交给其他轮次核对。
            if separated.count == inside.count {
                result += separated
            } else {
                failedGroups += 1
                result.append(box)
            }
        }
        return result
    }

    /// 把一小块字（位置是这张图的 0–1）裁下来单独认
    private static func reread(_ spot: PassPlan.TextBox, in image: CGImage, words: [String], settings: Settings,
                               smooth: Bool, diagnosticID: String = "local") -> PassPlan.TextBox? {
        let w = Double(image.width), h = Double(image.height)
        let pad = spot.height * h * 0.3
        let rect = CGRect(x: spot.x * w - pad, y: spot.y * h - pad, width: spot.width * w + pad * 2, height: spot.height * h + pad * 2)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h)).integral
        guard rect.width > 2, rect.height > 2, let cut = image.cropping(to: rect) else { return nil }
        guard let text = recognizeCell(cut, words: words, settings: settings, smooth: smooth, diagnosticID: diagnosticID) else { return nil }
        var box = spot
        box.text = text
        return box
    }

    private static func recognizeCell(_ cut: CGImage, words: [String], settings: Settings,
                                      smooth: Bool, diagnosticID: String) -> String? {
        let trace = Trace(settings.diagnostics, "cellOCR.\(diagnosticID)", "size=\(cut.width)x\(cut.height)")
        defer { trace.end() }
        // 一小块字：放大到够高再认（小字放大了认得准）
        let piece = prepared(cut, smooth: smooth, enlarge: true)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = settings.languageCorrection
        if settings.languageCorrection { request.customWords = words }
        guard (try? VNImageRequestHandler(cgImage: piece, orientation: .up).perform([request])) != nil else { return nil }
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        guard !text.isEmpty else { return nil }
        return text
    }

    /// 认之前处理一下：smooth 轻轻模糊压掉摩尔纹；enlarge 一小块字不到 80 像素高就放大到 80 以上（最多 4 倍）
    private static func prepared(_ image: CGImage, smooth: Bool, enlarge: Bool) -> CGImage {
        let scale = enlarge ? min(4, max(1, (80 / Double(max(image.height, 1))).rounded(.up))) : 1
        guard smooth || scale > 1 else { return image }
        var picture = CIImage(cgImage: image)
        let extent = picture.extent
        if smooth {
            picture = picture.clampedToExtent().applyingGaussianBlur(sigma: 0.8).cropped(to: extent)
        }
        if scale > 1 {
            picture = picture.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return CIContext().createCGImage(picture, from: picture.extent.integral) ?? image
    }

    /// iOS 26 起：系统直接认表格（按格子读）。照片里认出几张表的话，用读出行最多的那张
    @available(iOS 26.0, *)
    private static func tableReading(in image: CGImage, words: [String], settings: Settings) async -> PassPlan.Reading? {
        let trace = Trace(settings.diagnostics, "systemTable", "size=\(image.width)x\(image.height)")
        defer { trace.end() }
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = [Locale.Language(identifier: "zh-Hans"),
                                                               Locale.Language(identifier: "en-US")]
        request.textRecognitionOptions.useLanguageCorrection = settings.languageCorrection
        if settings.languageCorrection { request.textRecognitionOptions.customWords = words }
        if settings.smallText { request.textRecognitionOptions.minimumTextHeightFraction = minimumTextHeight(image.height) }
        guard let observations = try? await request.perform(on: image, orientation: .up) else { return nil }
        // 每张表一行行的格子：按格子在第几列放（空着的格子补空）
        let grids: [[[String]]] = observations.flatMap(\.document.tables).map { table in
            table.rows.map { row in
                var cells: [String] = []
                for cell in row.sorted(by: { $0.columnRange.lowerBound < $1.columnRange.lowerBound }) {
                    while cells.count < cell.columnRange.lowerBound { cells.append("") }
                    guard cells.count == cell.columnRange.lowerBound else { continue }
                    cells.append(cell.content.text.transcript.replacingOccurrences(of: "\n", with: " "))
                }
                return cells
            }
        }
        return grids.map(PassPlan.readTable).max { $0.rows.count < $1.rows.count }
    }

    /// 照片转成正着的（相机拍的照片常常横着存、再标上「要转 90°」）：之后切段、换算位置都按正着的算
    private static func upright(_ image: UIImage) -> CGImage? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = image.imageOrientation
        guard orientation != .up else { return cgImage }
        let w = cgImage.width, h = cgImage.height
        let sideways = [.left, .leftMirrored, .right, .rightMirrored].contains(orientation)
        let (outW, outH) = sideways ? (h, w) : (w, h)
        guard let context = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return cgImage }
        var t = CGAffineTransform.identity
        switch orientation {
        case .down, .downMirrored: t = t.translatedBy(x: CGFloat(outW), y: CGFloat(outH)).rotated(by: .pi)
        case .left, .leftMirrored: t = t.translatedBy(x: CGFloat(outW), y: 0).rotated(by: .pi / 2)
        case .right, .rightMirrored: t = t.translatedBy(x: 0, y: CGFloat(outH)).rotated(by: -.pi / 2)
        default: break
        }
        switch orientation {
        case .upMirrored, .downMirrored, .leftMirrored, .rightMirrored: t = t.translatedBy(x: CGFloat(w), y: 0).scaledBy(x: -1, y: 1)
        default: break
        }
        context.concatenate(t)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage() ?? cgImage
    }

    /// 一块认出的字拆成一格格：按空格拆；中间空得很开的也拆（隔得远的几个表头格子常被认成一整块）。
    /// aspect：图的宽比高（位置是按宽、高各自算的比例，比较空隙和字高要换成一样的单位）
    private static func tokens(_ observation: VNRecognizedTextObservation, aspect: Double) -> [PassPlan.TextBox] {
        guard let candidate = observation.topCandidates(1).first else { return [] }
        let text = candidate.string
        func box(_ rect: CGRect, _ string: String) -> PassPlan.TextBox {
            // Vision 的坐标原点在左下，换成从上往下
            PassPlan.TextBox(text: string, x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
        }
        // 每个字的位置；拿不到（有的语言只给整块的）就只按空格拆
        var pieces: [(text: String, rect: CGRect)] = []
        for i in text.indices where !text[i].isWhitespace {
            guard let rect = try? candidate.boundingBox(for: i..<text.index(after: i))?.boundingBox else { pieces = []; break }
            pieces.append((String(text[i]), rect))
        }
        let whole = observation.boundingBox
        let perCharacter = pieces.count > 1 && pieces.contains { $0.rect.width < whole.width * 0.9 }
        guard perCharacter else {
            let parts = text.split(whereSeparator: \.isWhitespace)
            guard parts.count > 1 else { return [box(whole, text)] }
            return parts.compactMap { part in
                guard let rect = try? candidate.boundingBox(for: part.startIndex..<part.endIndex)?.boundingBox else { return nil }
                return box(rect, String(part))
            }
        }
        // 相邻两个字之间：原文有空格，或者空出来比一个字高还宽，就是两格
        let gapLimit = Double(whole.height) / aspect
        var groups: [[(text: String, rect: CGRect)]] = []
        var index = text.startIndex
        var previousEnd = text.startIndex
        var k = 0
        while index < text.endIndex {
            if text[index].isWhitespace { index = text.index(after: index); continue }
            let piece = pieces[k]
            let spaced = k > 0 && text[previousEnd..<index].contains(where: \.isWhitespace)
            let gap = k > 0 ? Double(piece.rect.minX - pieces[k - 1].rect.maxX) : 0
            if k == 0 || spaced || gap > gapLimit { groups.append([piece]) } else { groups[groups.count - 1].append(piece) }
            previousEnd = text.index(after: index)
            index = previousEnd
            k += 1
        }
        return groups.map { group in
            box(group.dropFirst().reduce(group[0].rect) { $0.union($1.rect) }, group.map(\.text).joined())
        }
    }
}
