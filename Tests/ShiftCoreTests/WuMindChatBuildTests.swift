import XCTest
@testable import ShiftCore

final class WuMindChatBuildTests: XCTestCase {
    func testSixExplicitBuildToolsMapToDistinctArtifacts() {
        XCTAssertEqual(Set(WuMindChatBuild.allCases.map(\.workType)), Set(WuMindWorkType.allCases))
        XCTAssertEqual(WuMindChatBuild.code.workType, .code)
        XCTAssertEqual(WuMindChatBuild.spatial3d.workType, .scene3d)
    }

    func testNaturalLanguageRequestsRouteToBuildWithoutRequiringToolPage() {
        XCTAssertEqual(WuMindChatBuild.detectRequest("帮我生成一段五只小猫在农村院子里玩的5s视频"), .video)
        XCTAssertEqual(WuMindChatBuild.detectRequest("帮我生成一个年终总结ppt"), .ppt)
        XCTAssertEqual(WuMindChatBuild.detectRequest("请创建一张新年海报"), .image)
        XCTAssertEqual(WuMindChatBuild.detectRequest("给我构建一个可以筛选的网页"), .code)
        XCTAssertEqual(WuMindChatBuild.detectRequest("做一个三维场景"), .spatial3d)
        XCTAssertEqual(WuMindChatBuild.detectRequest("帮我起草技术标书"), .tender)
        XCTAssertEqual(WuMindChatBuild.detectRequest("Build a web page with a video embed"), .code)
    }

    func testReferencesTutorialsAndAmbiguousRequestsDoNotStartABuild() {
        for prompt in ["怎么生成视频？", "解释这个视频", "帮我写生成视频的提示词", "请不要生成图片", "创建图片再做视频", "how do I make a ppt", "这张介绍 3D 的 PPT 是什么"] {
            XCTAssertNil(WuMindChatBuild.detectRequest(prompt), prompt)
        }
    }

    func testVideoDurationUsesAllowedValueAndNeverOffersInvalidLength() {
        XCTAssertEqual(WuMindChatBuild.requestedVideoSeconds(in: "一段5s小猫视频"), 5)
        XCTAssertEqual(WuMindChatBuild.requestedVideoSeconds(in: "生成一段 6 秒视频"), 6)
        XCTAssertNil(WuMindChatBuild.requestedVideoSeconds(in: "五只小猫在院子里"))
        XCTAssertEqual(WuMindChatBuild.supportedVideoSeconds(requested: 5, allowed: [4, 6, 8], fallback: 8), 6)
        XCTAssertEqual(WuMindChatBuild.supportedVideoSeconds(requested: 6, allowed: [5, 6, 8], fallback: 5), 6)
        XCTAssertEqual(WuMindChatBuild.supportedVideoSeconds(requested: 15, allowed: [5, 8], fallback: 5), 8)
    }

    func testChatSlideDesignReadsBriefAndDoesNotPadOutput() throws {
        let profile = WuMindPPTEngine.chatDesignProfile(for: "做一份年终总结 PPT，白底极简")
        XCTAssertEqual(profile.audience, .executive)
        XCTAssertEqual(profile.theme, .minimalIvory)
        let reply = """
        {"title":"年度总结","slides":[
            {"title":"年度总结","layout":"cover","bullets":[]},
            {"title":"三个重点项目按期落地","layout":"bullets","bullets":["完成监控看板改版"]},
            {"title":"三个重点项目按期落地。","layout":"bullets","bullets":["重复结论"]},
            {"title":"空页面","layout":"bullets","bullets":[]},
            {"title":"明年行动","layout":"summary","bullets":["先验收数据回填流程"]}
        ]}
        """
        let result = try XCTUnwrap(WuMindPPTEngine.validatedChatDeck(
            from: reply, fallbackTopic: "总结", theme: profile.theme, expectedSlideCount: 8,
            audience: profile.audience, sourceFiles: ["年报.docx"]
        ))
        XCTAssertEqual(result.slides.map(\.title), ["年度总结", "三个重点项目按期落地", "明年行动"])
        XCTAssertEqual(result.sourceFiles, ["年报.docx"])
        XCTAssertFalse(try WuMindPPTXExporter.make(deck: result).isEmpty)
        XCTAssertNil(WuMindPPTEngine.validatedChatDeck(
            from: "已完成一份年终汇报", fallbackTopic: "总结", theme: .minimalIvory,
            expectedSlideCount: 8, audience: .general, sourceFiles: []
        ))
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
