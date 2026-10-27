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

    /// 几张照片（计划长、往下翻着拍的）→ 合成一份。第一张要拍到表头；后面几张没拍到表头的，按前一张的列位置分
    static func rows(inPages images: [UIImage]) async throws -> [PassPlanRow] {
        var pages: [[PassPlanRow]] = []
        var sawText = false
        var layout: PassPlan.ColumnLayout?
        for image in images {
            let boxes = try await textBoxes(in: image)
            sawText = sawText || !boxes.isEmpty
            let result = PassPlan.read(boxes, fallback: layout)
            layout = result.layout ?? layout
            pages.append(result.rows)
        }
        guard sawText else { throw Failure.noText }
        let rows = PassPlan.merge(pages)
        guard !rows.isEmpty else { throw Failure.noTable }
        return rows
    }

    /// 表格文件（Excel、CSV）或复制的表格 → 每一行
    static func rows(inFile url: URL) throws -> [PassPlanRow] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let table: [[String]]
        switch url.pathExtension.lowercased() {
        case "xlsx": table = XLSXReader.rows(data) ?? []
        case "csv": table = MeetingTable.rows(String(decoding: data, as: UTF8.self), separator: ",")
        default: table = MeetingTable.rows(String(decoding: data, as: UTF8.self), separator: "\t")
        }
        let rows = PassPlan.rows(fromTable: table)
        guard !rows.isEmpty else { throw Failure.noTable }
        return rows
    }

    /// 剪贴板里的表格（网页、Excel 里选中复制的）
    @MainActor
    static func rowsFromClipboard() throws -> [PassPlanRow] {
        let board = UIPasteboard.general
        var tables: [[[String]]] = []
        if let data = board.data(forPasteboardType: UTType.html.identifier) {
            tables.append(MeetingTable.htmlRows(String(decoding: data, as: UTF8.self)))
        }
        if let text = board.string {
            tables.append(MeetingTable.rows(text, separator: "\t"))
        }
        guard let rows = tables.lazy.map(PassPlan.rows(fromTable:)).first(where: { !$0.isEmpty }) else { throw Failure.noTable }
        return rows
    }

    // MARK: - 文字识别

    /// 识别出的每一块字，按空格再拆开（相邻两格偶尔被认成一块），各自带位置
    static func textBoxes(in image: UIImage) async throws -> [PassPlan.TextBox] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
            return (request.results ?? []).flatMap(tokens)
        }.value
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

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
