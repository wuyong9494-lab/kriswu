import XCTest
@testable import ShiftCore

final class WuMindChatBuildTests: XCTestCase {
    func testSixExplicitBuildToolsMapToDistinctArtifacts() {
        XCTAssertEqual(Set(WuMindChatBuild.allCases.map(\.workType)), Set(WuMindWorkType.allCases))
        XCTAssertEqual(WuMindChatBuild.code.workType, .code)
        XCTAssertEqual(WuMindChatBuild.spatial3d.workType, .scene3d)
    }

    func testCompleteHTMLCanBeExportedFromFencedModelResponse() {
        let html = "<!doctype html><html><body><button>预览地图</button></body></html>"
        XCTAssertEqual(WuMindChatBuild.standaloneHTML(html), html)
        XCTAssertEqual(WuMindChatBuild.standaloneHTML("```html\n\(html)\n```"), html)
    }

    func testPartialReplyIsNotAWebArtifact() {
        XCTAssertNil(WuMindChatBuild.standaloneHTML("网页已做好"))
        XCTAssertNil(WuMindChatBuild.standaloneHTML("<html><body>不完整"))
        XCTAssertNil(WuMindChatBuild.standaloneHTML("<!doctype html><html><body></body></html>额外说明"))
    }
}
