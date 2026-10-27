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
        /// 很长的图切成上下几段分别认
        var split = true
        /// 按中文、英文的词纠正认错的字（表头、运营商名、站名开头当词库）
        var languageCorrection = true

        static let standard = Settings()
        /// 改之前的认法（测试里对比用）
        static let original = Settings(smallText: false, split: false, languageCorrection: false)
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
        for image in images {
            guard let picture = upright(image) else { continue }
            let boxes = try await textBoxes(in: picture, words: words, settings: settings)
            sawText = sawText || !boxes.isEmpty
            let result = PassPlan.read(boxes, fallback: positions)
            positions = positions ?? result.layout
            guard let found = result.layout else { continue }
            let target = layout ?? found
            layout = target
            pages.append(PassPlan.remap(result.rows, from: found, to: target))
        }
        guard sawText else { throw Failure.noText }
        let rows = PassPlan.merge(pages)
        guard !rows.isEmpty else { throw Failure.noTable }
        return PassPlan.Reading(rows: rows, layout: layout)
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

    /// 认出图里的字：每一块按空格再拆开（相邻两格偶尔被认成一块），各自带位置（整张图的 0–1，y 从上往下）。
    /// 很长的图切成上下重叠的几段分别认：整张一起认，字相对整张图太小，会被跳过或认错
    static func textBoxes(in image: CGImage, words: [String] = [],
                          settings: Settings = .standard) async throws -> [PassPlan.TextBox] {
        try await Task.detached(priority: .userInitiated) {
            let strips = settings.split ? PassPlan.strips(width: image.width, height: image.height)
                : [PassPlan.Strip(top: 0, height: image.height, keep: -Double.infinity..<Double.infinity)]
            var boxes: [PassPlan.TextBox] = []
            for strip in strips {
                let piece = strips.count == 1 ? image
                    : image.cropping(to: CGRect(x: 0, y: strip.top, width: image.width, height: strip.height))
                guard let piece else { continue }
                let found = try recognize(piece, words: words, settings: settings)
                boxes += PassPlan.place(found, in: strip, imageHeight: image.height)
            }
            return boxes
        }.value
    }

    /// 字最小多高（占图高的比例）：十来个像素高的字也认
    private static func minimumTextHeight(_ pixelHeight: Int) -> Float {
        Float(max(10 / Double(max(pixelHeight, 1)), 0.002))
    }

    private static func recognize(_ image: CGImage, words: [String], settings: Settings) throws -> [PassPlan.TextBox] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = settings.languageCorrection
        if settings.languageCorrection { request.customWords = words }
        if settings.smallText { request.minimumTextHeight = minimumTextHeight(image.height) }
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        return (request.results ?? []).flatMap(tokens)
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

    private static func tokens(_ observation: VNRecognizedTextObservation) -> [PassPlan.TextBox] {
        guard let candidate = observation.topCandidates(1).first else { return [] }
        let text = candidate.string
        func box(_ rect: CGRect, _ string: String) -> PassPlan.TextBox {
            // Vision 的坐标原点在左下，换成从上往下
            PassPlan.TextBox(text: string, x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
        }
        let parts = text.split(whereSeparator: \.isWhitespace)
        guard parts.count > 1 else { return [box(observation.boundingBox, text)] }
        return parts.compactMap { part in
            guard let rect = try? candidate.boundingBox(for: part.startIndex..<part.endIndex)?.boundingBox else { return nil }
            return box(rect, String(part))
        }
    }
}
