import Foundation

/// Produces an editable Word draft locally. The source tender is never modified.
public enum TenderDOCXExporter {
    public enum Failure: LocalizedError, Equatable, Sendable {
        case emptyDraft, tooLarge

        public var errorDescription: String? {
            switch self {
            case .emptyDraft: return "还没有可导出的投标书草稿。"
            case .tooLarge: return "草稿过长，无法导出。请缩小范围后重试。"
            }
        }
    }

    public struct Section: Sendable {
        public let title: String
        public let body: String

        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }

    public struct MatrixRow: Sendable {
        public let requirement: String
        public let response: String
        public let status: String
        public let source: String

        public init(requirement: String, response: String, status: String, source: String) {
            self.requirement = requirement
            self.response = response
            self.status = status
            self.source = source
        }
    }

    public static func make(title: String, sections: [Section], reviewNotes: [String], matrix: [MatrixRow] = []) throws -> Data {
        guard !sections.isEmpty, sections.contains(where: { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw Failure.emptyDraft }
        let contents = [title] + sections.flatMap { [$0.title, $0.body] } + reviewNotes
            + matrix.flatMap { [$0.requirement, $0.response, $0.status, $0.source] }
        guard sections.count <= 100, reviewNotes.count <= 300, matrix.count <= 150,
              contents.reduce(0, { $0 + $1.utf8.count }) <= 1_000_000
        else { throw Failure.tooLarge }

        var paragraphs = paragraph(title.isEmpty ? "投标文件草稿" : title, style: "Title")
        paragraphs += paragraph("投标草稿｜请人工核对招标文件、补遗、报价、资质和签章后再使用。", style: "Notice")
        for section in sections {
            paragraphs += paragraph(section.title, style: "Heading1")
            paragraphs += section.body.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .components(separatedBy: "\n").map { paragraph($0) }.joined()
        }
        if !matrix.isEmpty {
            paragraphs += paragraph("逐项响应表", style: "Heading1")
            paragraphs += matrixTable(matrix)
        }
        if !reviewNotes.isEmpty {
            paragraphs += paragraph("待核对事项", style: "Heading1")
            paragraphs += reviewNotes.enumerated().map { paragraph("\($0.offset + 1). \($0.element)") }.joined()
        }

        let document = xmlHeader + """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        \(paragraphs)
        <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>
        </w:body></w:document>
        """
        return storedZIP([
            ("[Content_Types].xml", xmlHeader + contentTypes),
            ("_rels/.rels", xmlHeader + relationships),
            ("word/document.xml", document),
            ("word/_rels/document.xml.rels", xmlHeader + documentRelationships),
            ("word/styles.xml", xmlHeader + styles)
        ].map { ($0.0, Data($0.1.utf8)) })
    }

    private static let xmlHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"

    private static let contentTypes = """
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
      <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
    </Types>
    """
    private static let relationships = """
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
    """
    private static let documentRelationships = """
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
    """
    private static let styles = """
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:eastAsia="宋体"/><w:sz w:val="22"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:line="340" w:lineRule="auto" w:after="90"/></w:pPr></w:pPrDefault></w:docDefaults>
      <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
      <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="220" w:after="230"/></w:pPr><w:rPr><w:b/><w:sz w:val="38"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="200" w:after="100"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Notice"><w:name w:val="Draft Notice"/><w:basedOn w:val="Normal"/><w:rPr><w:color w:val="505050"/></w:rPr></w:style>
    </w:styles>
    """

    private static func paragraph(_ text: String, style: String = "Normal") -> String {
        let scalars = text.unicodeScalars.filter { scalar in
            let n = scalar.value
            return [9, 10, 13].contains(n) || (32...0xD7FF).contains(n)
                || (0xE000...0xFFFD).contains(n) || (0x10000...0x10FFFF).contains(n)
        }
        let legal = String(String.UnicodeScalarView(scalars))
        let inline = legal.components(separatedBy: .newlines).map { part in
            "<w:r><w:t xml:space=\"preserve\">\(part.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;"))</w:t></w:r>"
        }.joined(separator: "<w:r><w:br/></w:r>")
        return "<w:p><w:pPr><w:pStyle w:val=\"\(style)\"/></w:pPr>\(inline)</w:p>"
    }

    private static func matrixTable(_ entries: [MatrixRow]) -> String {
        let widths = [2200, 3300, 1150, 2356]
        let borders = ["top", "left", "bottom", "right", "insideH", "insideV"].map {
            "<w:\($0) w:val=\"single\" w:sz=\"4\" w:color=\"B5BDC7\"/>"
        }.joined()
        let grid = widths.map { "<w:gridCol w:w=\"\($0)\"/>" }.joined()
        func row(_ cells: [String], header: Bool = false) -> String {
            let properties = header ? "<w:trPr><w:tblHeader/></w:trPr>" : ""
            let content = zip(cells, widths).map { text, width in
                let shading = header ? "<w:shd w:fill=\"EDF1F5\"/>" : ""
                return "<w:tc><w:tcPr><w:tcW w:w=\"\(width)\" w:type=\"dxa\"/>\(shading)</w:tcPr>\(paragraph(text))</w:tc>"
            }.joined()
            return "<w:tr>\(properties)\(content)</w:tr>"
        }
        return "<w:tbl><w:tblPr><w:tblW w:w=\"9006\" w:type=\"dxa\"/><w:tblBorders>\(borders)</w:tblBorders></w:tblPr><w:tblGrid>\(grid)</w:tblGrid>"
            + row(["招标要求", "草稿响应", "状态", "来源"], header: true)
            + entries.map { row([$0.requirement, $0.response, $0.status, $0.source]) }.joined()
            + "</w:tbl>"
    }

    // Standard ZIP with stored entries; small generated parts only, no compression/dependencies.
    private static func storedZIP(_ files: [(String, Data)]) -> Data {
        var output = Data()
        var directory = Data()
        for (path, contents) in files {
            let name = Data(path.utf8), checksum = crc32(contents)
            let offset = UInt32(output.count), bytes = UInt32(contents.count), length = UInt16(name.count)
            output.le32(0x04034B50)
            output.le16(20); output.le16(0); output.le16(0)
            output.le16(0); output.le16(33)
            output.le32(checksum); output.le32(bytes); output.le32(bytes)
            output.le16(length); output.le16(0)
            output.append(name); output.append(contents)
            directory.le32(0x02014B50)
            directory.le16(20); directory.le16(20); directory.le16(0); directory.le16(0)
            directory.le16(0); directory.le16(33)
            directory.le32(checksum); directory.le32(bytes); directory.le32(bytes)
            directory.le16(length); directory.le16(0); directory.le16(0)
            directory.le16(0); directory.le16(0); directory.le32(0); directory.le32(offset)
            directory.append(name)
        }
        let start = UInt32(output.count), size = UInt32(directory.count), count = UInt16(files.count)
        output.append(directory)
        output.le32(0x06054B50)
        output.le16(0); output.le16(0); output.le16(count); output.le16(count)
        output.le32(size); output.le32(start); output.le16(0)
        return output
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var value: UInt32 = 0xFFFF_FFFF
        for byte in data {
            value ^= UInt32(byte)
            for _ in 0..<8 { value = (value >> 1) ^ (value & 1 == 1 ? 0xEDB8_8320 : 0) }
        }
        return ~value
    }
}

private extension Data {
    mutating func le16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value)); append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func le32(_ value: UInt32) {
        le16(UInt16(truncatingIfNeeded: value)); le16(UInt16(truncatingIfNeeded: value >> 16))
    }
}

public extension TenderDOCXExporter {
    static func make(draft: DeepSeekTenderClient.Draft) throws -> Data {
        func citation(_ source: DeepSeekTenderClient.Source) -> String {
            "\(source.location) · \(source.verified ? "摘录已比对，位置待核" : "出处待核")\n\(source.quote)"
        }
        let notes = draft.missingFacts.map { "待补资料：\($0)" }
            + draft.warnings.map { "提示：\($0)" }
            + draft.sections.flatMap { section in
                section.sources.map { "「\(section.title)」的招标依据：\n\(citation($0))" }
            }
        return try make(title: draft.title, sections: draft.sections.map { Section(title: $0.title, body: $0.body) },
                        reviewNotes: notes,
                        matrix: draft.requirements.map {
            MatrixRow(requirement: $0.requirement, response: $0.response, status: $0.status.title, source: citation($0.source))
        })
    }
}
