import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import XCTest
@testable import ShiftCore

final class TenderDOCXExporterTests: XCTestCase {
    func testEditableDraftAndEscapedResponseMatrix() throws {
        let data = try TenderDOCXExporter.make(
            title: "演示项目 & 验证",
            sections: [.init(title: "技术方案", body: "第一行 <方案>\n第二行\u{0003}")],
            reviewNotes: ["待补附件：授权书"],
            matrix: [.init(requirement: "提交授权书", response: "待补 <扫描件>", status: "待核对", source: "第 5 页\n招标要求")]
        )
        let parts = unpackStored(data)
        XCTAssertEqual(Set(parts.keys), ["[Content_Types].xml", "_rels/.rels", "word/document.xml",
                                          "word/_rels/document.xml.rels", "word/styles.xml"])
        for part in parts.values { XCTAssertTrue(XMLParser(data: part).parse()) }
        let doc = try XCTUnwrap(parts["word/document.xml"]).decoded
        XCTAssertTrue(doc.contains("演示项目 &amp; 验证"))
        XCTAssertTrue(doc.contains("&lt;方案&gt;"))
        XCTAssertTrue(doc.contains("待补附件：授权书"))
        XCTAssertTrue(doc.contains("<w:tblHeader/>"))
        XCTAssertTrue(doc.contains("待补 &lt;扫描件&gt;"))
        XCTAssertTrue(doc.contains("第 5 页"))
        XCTAssertFalse(doc.contains("\u{0003}"))
    }

    func testDoesNotExportEmptyDraft() {
        XCTAssertThrowsError(try TenderDOCXExporter.make(title: "项目", sections: [], reviewNotes: [])) {
            XCTAssertEqual($0 as? TenderDOCXExporter.Failure, .emptyDraft)
        }
    }

    private func unpackStored(_ data: Data) -> [String: Data] {
        let bytes = Array(data)
        func n(_ start: Int, _ count: Int) -> Int {
            (0..<count).reduce(0) { $0 | (Int(bytes[start + $1]) << (8 * $1)) }
        }
        var index = 0
        var result: [String: Data] = [:]
        while index + 30 <= bytes.count, n(index, 4) == 0x04034B50 {
            let len = n(index + 26, 2), extra = n(index + 28, 2), size = n(index + 18, 4)
            let start = index + 30 + len + extra
            guard start + size <= bytes.count else { return [:] }
            let name = String(decoding: bytes[(index + 30)..<(index + 30 + len)], as: UTF8.self)
            result[name] = Data(bytes[start..<(start + size)])
            index = start + size
        }
        return result
    }
}

private extension Data {
    var decoded: String { String(decoding: self, as: UTF8.self) }
}
