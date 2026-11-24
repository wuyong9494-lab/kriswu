import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(PDFKit)
import PDFKit
#endif

/// Extracts clean, length-bounded text from files uploaded in the WUMIND chat composer:
/// PDF, Word (.docx), Excel (.xlsx), CSV/TSV, Markdown, JSON/YAML/XML, and source code files.
public enum WuMindAttachmentParser {
    public enum Kind: String, Codable, Sendable {
        case pdf, word, excel, code, text, image
    }

    public struct ExtractedDocument: Equatable, Sendable {
        public let filename: String
        public let kind: Kind
        public let byteCount: Int
        public let extractedText: String
        public let summaryBadge: String

        public init(filename: String, kind: Kind, byteCount: Int, extractedText: String, summaryBadge: String) {
            self.filename = filename
            self.kind = kind
            self.byteCount = byteCount
            self.extractedText = extractedText
            self.summaryBadge = summaryBadge
        }
    }

    public enum ParseError: LocalizedError, Equatable, Sendable {
        case fileTooLarge
        case unsupportedFormat
        case unreadableContent

        public var errorDescription: String? {
            switch self {
            case .fileTooLarge: return "单个文件不能超过 20 MB，请压缩或拆分后再上传。"
            case .unsupportedFormat: return "暂不支持解析此文件格式，请上传 PDF、Word(.docx)、Excel(.xlsx)、CSV、代码或文本文件。"
            case .unreadableContent: return "未能从此文件中读取到可识别的文字内容（扫描版 PDF 建议截图后用图片 OCR 上传）。"
            }
        }
    }

    public static let maxFileBytes = 20 * 1024 * 1024
    public static let maxExtractedChars = 16_000

    private static let codeExtensions: Set<String> = [
        "swift", "py", "js", "ts", "tsx", "jsx", "go", "rs", "java", "kt", "kts",
        "c", "h", "cpp", "hpp", "m", "mm", "cs", "rb", "php", "sh", "bash", "zsh",
        "sql", "html", "htm", "css", "scss", "json", "yaml", "yml", "toml", "xml", "plist"
    ]

    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "log", "ini", "conf", "env", "rtf"
    ]

    public static func extract(data: Data, filename: String) throws -> ExtractedDocument {
        guard !data.isEmpty, data.count <= maxFileBytes else { throw ParseError.fileTooLarge }
        let ext = (filename as NSString).pathExtension.lowercased()

        switch ext {
        case "pdf":
            return try extractPDF(data: data, filename: filename)
        case "docx":
            return try extractDOCX(data: data, filename: filename)
        case "xlsx":
            return try extractXLSX(data: data, filename: filename)
        default:
            if codeExtensions.contains(ext) {
                return try extractPlainText(data: data, filename: filename, kind: .code, label: ext.uppercased())
            }
            if textExtensions.contains(ext) {
                return try extractPlainText(data: data, filename: filename, kind: .text, label: ext.uppercased())
            }
            // Fallback: accept valid UTF-8 text files even without extension
            if let text = String(data: data, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !text.contains("\u{0000}") {
                return try extractPlainText(data: data, filename: filename, kind: .text, label: "文本")
            }
            throw ParseError.unsupportedFormat
        }
    }

    /// Formats one or more attached files cleanly to prepend to the user prompt or context.
    public static func formatContext(for documents: [ExtractedDocument], maxTotalChars: Int = 24_000) -> String {
        guard !documents.isEmpty else { return "" }
        let perDocBudget = max(2_000, maxTotalChars / documents.count)
        var blocks: [String] = []
        for doc in documents {
            let body = doc.extractedText.count > perDocBudget
                ? String(doc.extractedText.prefix(perDocBudget)) + "\n...[已按长度安全截断]"
                : doc.extractedText
            blocks.append("""
            [用户上传附件：`\(doc.filename)`（\(doc.summaryBadge)）]
            ```
            \(body)
            ```
            """)
        }
        return blocks.joined(separator: "\n\n")
    }

    // MARK: - Format Extractors

    private static func extractPDF(data: Data, filename: String) throws -> ExtractedDocument {
        guard data.prefix(1024).range(of: Data("%PDF-".utf8)) != nil else { throw ParseError.unsupportedFormat }
        #if canImport(PDFKit)
        guard let pdf = PDFDocument(data: data), !pdf.isLocked, pdf.pageCount > 0 else {
            throw ParseError.unreadableContent
        }
        let maxPages = min(pdf.pageCount, 80)
        var pages: [String] = []
        var totalChars = 0
        for idx in 0..<maxPages {
            guard let text = pdf.page(at: idx)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { continue }
            let chunk = "【第 \(idx + 1) 页】\n\(text)"
            pages.append(chunk)
            totalChars += chunk.count
            if totalChars >= maxExtractedChars { break }
        }
        let joined = pages.joined(separator: "\n\n")
        guard !joined.isEmpty else { throw ParseError.unreadableContent }
        return ExtractedDocument(
            filename: filename,
            kind: .pdf,
            byteCount: data.count,
            extractedText: String(joined.prefix(maxExtractedChars)),
            summaryBadge: "PDF · \(pdf.pageCount) 页"
        )
        #else
        throw ParseError.unreadableContent
        #endif
    }

    private static func extractDOCX(data: Data, filename: String) throws -> ExtractedDocument {
        guard data.starts(with: [0x50, 0x4B, 0x03, 0x04]),
              let files = XLSXReader.unzip(data, wanted: { $0 == "word/document.xml" }),
              let xml = files["word/document.xml"] else {
            throw ParseError.unreadableContent
        }
        let paragraphs = WordXMLParagraphs.parse(xml)
        let joined = paragraphs.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { throw ParseError.unreadableContent }
        return ExtractedDocument(
            filename: filename,
            kind: .word,
            byteCount: data.count,
            extractedText: String(joined.prefix(maxExtractedChars)),
            summaryBadge: "Word · \(paragraphs.count) 段"
        )
    }

    private static func extractXLSX(data: Data, filename: String) throws -> ExtractedDocument {
        guard let sheets = XLSXReader.sheets(data), !sheets.isEmpty else {
            throw ParseError.unreadableContent
        }
        var rendered: [String] = []
        var totalRows = 0
        for (idx, rows) in sheets.prefix(6).enumerated() {
            let nonEmpty = rows.filter { row in row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
            guard !nonEmpty.isEmpty else { continue }
            totalRows += nonEmpty.count
            var lines: [String] = ["【工作表 \(idx + 1)】"]
            for row in nonEmpty.prefix(120) {
                lines.append("| " + row.map { $0.replacingOccurrences(of: "|", with: "/") }.joined(separator: " | ") + " |")
            }
            rendered.append(lines.joined(separator: "\n"))
        }
        let joined = rendered.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { throw ParseError.unreadableContent }
        return ExtractedDocument(
            filename: filename,
            kind: .excel,
            byteCount: data.count,
            extractedText: String(joined.prefix(maxExtractedChars)),
            summaryBadge: "Excel · \(sheets.count) 表 \(totalRows) 行"
        )
    }

    private static func extractPlainText(data: Data, filename: String, kind: Kind, label: String) throws -> ExtractedDocument {
        guard let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw ParseError.unreadableContent
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.unreadableContent }
        let lineCount = trimmed.split(separator: "\n", omittingEmptySubsequences: false).count
        return ExtractedDocument(
            filename: filename,
            kind: kind,
            byteCount: data.count,
            extractedText: String(trimmed.prefix(maxExtractedChars)),
            summaryBadge: "\(label) · \(lineCount) 行"
        )
    }
}

private final class WordXMLParagraphs: NSObject, XMLParserDelegate {
    private var paragraphs: [String] = []
    private var current = ""
    private var inText = false

    static func parse(_ xml: Data) -> [String] {
        let handler = WordXMLParagraphs()
        let parser = XMLParser(data: xml)
        parser.delegate = handler
        _ = parser.parse()
        return handler.paragraphs
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "w:t" || name.hasSuffix(":t") { inText = true }
        if name == "w:tab" || name.hasSuffix(":tab") { current += "\t" }
        if name == "w:br" || name.hasSuffix(":br") { current += "\n" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "w:t" || name.hasSuffix(":t") { inText = false }
        if name == "w:p" || name.hasSuffix(":p") {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { paragraphs.append(trimmed) }
            current = ""
        }
    }
}
