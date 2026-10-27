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

        struct Pass: Sendable, Hashable {
            /// 很长的图切成上下几段分别认
            var split = true
            /// 认之前轻轻模糊一下，压掉拍屏幕的摩尔纹
            var smooth = false

            static let all = [Pass(), Pass(smooth: true), Pass(split: false)]
        }

        static let standard = Settings()
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
            // 几种认法同时认，拼出来的一行行对着挑
            let readings = try await boxes(of: picture, words: words, settings: settings)
            sawText = sawText || readings.contains { !$0.isEmpty }
            var result = PassPlan.combine(readings.map { PassPlan.read($0, fallback: positions) }, rules: rules)
            positions = positions ?? result.layout
            // iOS 26 起系统还能直接按格子认表格：按位置拼的什么都没拼出来就用它（没有原图）；
            // 拼出来了就拿它核对站名（同一行它认的站名对得上对照表、这边的对不上，用它的）
            if #available(iOS 26.0, *), settings.tables, let table = await tableReading(in: picture, words: words, settings: settings) {
                sawText = sawText || !table.rows.isEmpty
                if result.rows.isEmpty {
                    result = table
                } else {
                    result.rows = PassPlan.adoptStations(result.rows, from: table.rows, rules: rules)
                }
            }
            guard let found = result.layout else { continue }
            for i in result.rows.indices { result.rows[i].region?.page = page }
            result.rows = await rereadStations(result.rows, layout: found, in: picture, rules: rules, words: words, settings: settings)
            result.header?.page = page
            let pageHeader = header == nil ? result.header : nil
            header = header ?? result.header
            let regions = result.rows.compactMap(\.region) + (pageHeader.map { [$0] } ?? [])
            let cuts = await cut(regions, from: picture)
            strips.merge(cuts) { old, _ in old }
            let target = layout ?? found
            layout = target
            pages.append(PassPlan.remap(result.rows, from: found, to: target))
        }
        guard sawText else { throw Failure.noText }
        let rows = PassPlan.merge(pages)
        guard !rows.isEmpty else { throw Failure.noTable }
        return PassPlan.Reading(rows: rows, layout: layout, header: header, strips: strips)
    }

    /// 最要紧的两格再认一遍：每一行把「地面站」那一格（分家只看它）、没认出来的「是否应急」那一格（决定图下面那句话）
    /// 单独裁下来、放大了再认（一小格单独认，比一整张里一起认准得多）。
    /// 地面站：再认的对得上对照表、或者原来那个对不上，就用再认的；是否应急：再认出「是 / 不是」就填上
    static func rereadStations(_ rows: [PassPlanRow], layout: PassPlan.Layout, in image: CGImage,
                               rules: [PassPlan.OperatorRule], words: [String], settings: Settings) async -> [PassPlanRow] {
        let station = layout.slots.firstIndex { $0.column == .station }
        let urgent = layout.emergencyIndex
        guard station != nil || urgent != nil else { return rows }
        let xs = layout.slots.map(\.x)
        return await Task.detached(priority: .userInitiated) {
            /// 这一行第 s 列那一格单独认出的字
            func reread(column s: Int, of region: PassPlan.Region) -> String? {
                let left = s > 0 ? (xs[s - 1] + xs[s]) / 2 : region.left
                let right = s < xs.count - 1 ? (xs[s] + xs[s + 1]) / 2 : region.right
                let center = (left + right) / 2
                let cell = PassPlan.TextBox(text: "", x: left, y: region.y0 + region.slope * center - region.height * 0.45,
                                            width: right - left, height: region.height * 0.9)
                let text = Self.reread(cell, in: image, words: words, settings: settings, smooth: false)?
                    .text.filter { !$0.isWhitespace }
                return text?.isEmpty == false ? text : nil
            }
            return rows.map { row in
                guard let region = row.region else { return row }
                var fixed = row
                if let s = station,
                   let again = reread(column: s, of: region)?
                       .replacingOccurrences(of: "—", with: "-").replacingOccurrences(of: "－", with: "-"),
                   again != row.station,
                   PassPlan.operatorName(of: again, rules: rules) != nil || PassPlan.operatorName(of: row.station, rules: rules) == nil {
                    fixed.station = again
                }
                if let e = urgent, PassPlan.emergency(fixed, layout: layout) == nil, let again = reread(column: e, of: region) {
                    var trial = fixed
                    while trial.cells.count <= e { trial.cells.append("") }
                    trial.cells[e] = again
                    if PassPlan.emergency(trial, layout: layout) != nil { fixed = trial }
                }
                return fixed
            }
        }.value
    }

    // MARK: - 发原图：从照片上裁

    /// 从照片上裁下这几条（每一行、表头），各自扶正成长方形，存成 JPEG（宽最多 2400）
    static func cut(_ regions: [PassPlan.Region], from image: CGImage) async -> [PassPlan.Region: Data] {
        await Task.detached(priority: .userInitiated) {
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
                // CoreImage 的原点在左下
                func corner(_ x: Double, _ dy: Double) -> CIVector {
                    CIVector(x: x * w, y: h - (region.y0 + region.slope * x + dy) * h)
                }
                guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { continue }
                filter.setValue(source, forKey: kCIInputImageKey)
                filter.setValue(corner(region.left, -region.height / 2), forKey: "inputTopLeft")
                filter.setValue(corner(region.right, -region.height / 2), forKey: "inputTopRight")
                filter.setValue(corner(region.right, region.height / 2), forKey: "inputBottomRight")
                filter.setValue(corner(region.left, region.height / 2), forKey: "inputBottomLeft")
                guard let straight = filter.outputImage, straight.extent.width > 1 else { continue }
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

    /// 几种认法同时认，各认出一份（顺序和 passes 一样）
    private static func boxes(of image: CGImage, words: [String], settings: Settings) async throws -> [[PassPlan.TextBox]] {
        let list = passes(of: image, settings: settings)
        return try await withThrowingTaskGroup(of: (Int, [PassPlan.TextBox]).self) { group in
            for (i, pass) in list.enumerated() {
                group.addTask { (i, try await textBoxes(in: image, words: words, settings: settings, pass: pass)) }
            }
            var found = [[PassPlan.TextBox]](repeating: [], count: list.count)
            for try await (i, boxes) in group { found[i] = boxes }
            return found
        }
    }

    /// 认出图里的字：每一块按空格再拆开（相邻两格偶尔被认成一块），各自带位置（整张图的 0–1，y 从上往下）。
    /// 很长的图切成上下重叠的几段分别认：整张一起认，字相对整张图太小，会被跳过或认错
    static func textBoxes(in image: CGImage, words: [String] = [], settings: Settings = .standard,
                          pass: Settings.Pass = Settings.Pass()) async throws -> [PassPlan.TextBox] {
        try await Task.detached(priority: .userInitiated) {
            let strips = pass.split ? PassPlan.strips(width: image.width, height: image.height)
                : [PassPlan.Strip(top: 0, height: image.height, keep: -Double.infinity..<Double.infinity)]
            var boxes: [PassPlan.TextBox] = []
            for strip in strips {
                let piece = strips.count == 1 ? image
                    : image.cropping(to: CGRect(x: 0, y: strip.top, width: image.width, height: strip.height))
                guard let piece else { continue }
                let found = try recognize(piece, words: words, settings: settings, smooth: pass.smooth)
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
                                  smooth: Bool) throws -> [PassPlan.TextBox] {
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
        let aspect = Double(image.width) / Double(max(image.height, 1))
        let spots = (blocks.results ?? []).map { block in
            (box: PassPlan.TextBox(text: "", x: block.boundingBox.minX, y: 1 - block.boundingBox.maxY,
                                   width: block.boundingBox.width, height: block.boundingBox.height),
             count: block.characterBoxes?.count ?? 0)
        }
        var result: [PassPlan.TextBox] = []
        var rereads = 0
        for box in (request.results ?? []).flatMap({ tokens($0, aspect: aspect) }) {
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
            // 对不上：每一块单独裁下来再认一遍（一张图最多认几百块，太多就不拆）
            guard rereads + inside.count <= 400 else {
                result.append(box)
                continue
            }
            rereads += inside.count
            result += inside.compactMap { reread($0.box, in: image, words: words, settings: settings, smooth: smooth) }
        }
        return result
    }

    /// 把一小块字（位置是这张图的 0–1）裁下来单独认
    private static func reread(_ spot: PassPlan.TextBox, in image: CGImage, words: [String], settings: Settings,
                               smooth: Bool) -> PassPlan.TextBox? {
        let w = Double(image.width), h = Double(image.height)
        let pad = spot.height * h * 0.3
        let rect = CGRect(x: spot.x * w - pad, y: spot.y * h - pad, width: spot.width * w + pad * 2, height: spot.height * h + pad * 2)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h)).integral
        guard rect.width > 2, rect.height > 2, let cut = image.cropping(to: rect) else { return nil }
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
        var box = spot
        box.text = text
        return box
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
