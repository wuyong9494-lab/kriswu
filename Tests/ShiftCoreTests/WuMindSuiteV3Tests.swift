import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class WuMindSuiteV3Tests: XCTestCase {
    // Minimal ISO BMFF MP4 header (`ftypisom`) for validation tests.
    private static let sampleMP4 = Data([
        0x00, 0x00, 0x00, 0x18,
        0x66, 0x74, 0x79, 0x70, // "ftyp"
        0x69, 0x73, 0x6F, 0x6D, // "isom"
        0x00, 0x00, 0x02, 0x00,
        0x69, 0x73, 0x6F, 0x6D,
        0x69, 0x73, 0x6F, 0x32
    ])

    func testExternalAccessBoundaryStrictlyBlocksInternalDutySurfacesAndDeepLinks() {
        for surface in AppFeatureSurface.allCases {
            XCTAssertTrue(AppAccessBoundary.canAccess(surface, role: .rosterMember))
        }
        XCTAssertTrue(AppAccessBoundary.canAccess(.wumindAI, role: .externalUser))
        XCTAssertTrue(AppAccessBoundary.canAccess(.games, role: .externalUser))
        XCTAssertTrue(AppAccessBoundary.canAccess(.accountSettings, role: .externalUser))

        for internalSurface: AppFeatureSurface in [
            .dutyToday, .dutyCalendar, .dutyStats, .dutySite, .dutyWorkLog, .dutyPassPlan, .dutyMeeting
        ] {
            XCTAssertFalse(
                AppAccessBoundary.canAccess(internalSurface, role: .externalUser),
                "External user must never access \(internalSurface)"
            )
        }

        XCTAssertFalse(AppAccessBoundary.canOpenDeepLinkRoute("passPlan", role: .externalUser))
        XCTAssertFalse(AppAccessBoundary.canOpenDeepLinkRoute("workLog", role: .externalUser))
        XCTAssertFalse(AppAccessBoundary.canOpenDeepLinkRoute("day:2026-11-24", role: .externalUser))
        XCTAssertFalse(AppAccessBoundary.canOpenDeepLinkRoute("meeting", role: .externalUser))
        XCTAssertTrue(AppAccessBoundary.canOpenDeepLinkRoute("whatsNew", role: .externalUser))
        XCTAssertTrue(AppAccessBoundary.canOpenDeepLinkRoute("passPlan", role: .rosterMember))
    }

    func testMainlandPhoneNormalizationMaskingAndOTPValidation() {
        XCTAssertEqual(AppAccessBoundary.normalizeMainlandPhone("138-0013-8000"), "13800138000")
        XCTAssertEqual(AppAccessBoundary.normalizeMainlandPhone("+86 189 1234 5678"), "18912345678")
        XCTAssertNil(AppAccessBoundary.normalizeMainlandPhone("12345678901"))
        XCTAssertNil(AppAccessBoundary.normalizeMainlandPhone("1380013800"))
        XCTAssertEqual(AppAccessBoundary.maskedPhone("13800138000"), "138****8000")
        XCTAssertTrue(AppAccessBoundary.isValidSMSCode("042918"))
        XCTAssertFalse(AppAccessBoundary.isValidSMSCode("12345"))
        XCTAssertFalse(AppAccessBoundary.isValidSMSCode("12345a"))
    }

    func testAIVideoToolSoraSubmitPollAndMP4Download() async throws {
        actor Step {
            var pollCount = 0
            func nextPoll() -> Int { pollCount += 1; return pollCount }
        }
        let step = Step()
        let model = try XCTUnwrap(AIVideoTool.models.first { $0.id == "sora-2" })
        let tool = AIVideoTool(pollIntervalNanoseconds: 1_000_000, maxPollAttempts: 5) { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST" && path == "/v1/videos" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-video-test")
                return Self.reply(request, #"{"id":"vid_123","status":"queued","progress":10}"#)
            }
            if request.httpMethod == "GET" && path == "/v1/videos/vid_123" {
                let n = await step.nextPoll()
                if n == 1 {
                    return Self.reply(request, #"{"id":"vid_123","status":"in_progress","progress":60}"#)
                }
                return Self.reply(request, #"{"id":"vid_123","status":"completed","progress":100}"#)
            }
            if request.httpMethod == "GET" && path == "/v1/videos/vid_123/content" {
                return (Self.sampleMP4, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            XCTFail("Unexpected request: \(request.httpMethod ?? "") \(path)")
            return Self.reply(request, "{}", status: 404)
        }

        let mp4 = try await tool.generate(
            model: model,
            apiKey: "sk-video-test",
            prompt: "Golden sunset over ocean cliffs, drone shot",
            options: .init(aspectRatio: .landscape16x9, durationSeconds: 4, resolution: .hd720)
        )
        XCTAssertEqual(mp4, Self.sampleMP4)
        XCTAssertTrue(AIVideoTool.isValidMP4(mp4))
        XCTAssertFalse(AIVideoTool.isValidMP4(Data("not-an-mp4-file".utf8)))
    }

    func testAIVideoToolRejectsHTTPDowngradeAndSupportsCustomHTTPSRelay() async throws {
        let grok = try XCTUnwrap(AIVideoTool.models.first { $0.provider == .grok })
        let b64 = Self.sampleMP4.base64EncodedString()
        let tool = AIVideoTool(pollIntervalNanoseconds: 1_000_000, maxPollAttempts: 3) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://video-relay.example.com/v1/videos/generations")
            return Self.reply(request, #"{"request_id":"req_1","status":"completed","video":{"b64_json":"\#(b64)"}}"#)
        }
        let mp4 = try await tool.generate(
            model: grok,
            apiKey: "xai-key",
            prompt: "Neon Tokyo rain",
            options: .init(customBaseURL: "https://video-relay.example.com/v1")
        )
        XCTAssertEqual(mp4, Self.sampleMP4)

        do {
            _ = try await tool.generate(
                model: grok,
                apiKey: "xai-key",
                prompt: "Neon Tokyo rain",
                options: .init(customBaseURL: "http://video-relay.example.com/v1")
            )
            XCTFail("HTTP custom relay must be rejected")
        } catch {
            XCTAssertEqual(error as? MultiProviderAIError, .invalidRequest)
        }
    }

    func testWuMindPPTEngineParsesFencedJSONAndFallsBackCleanlyOnMarkdown() {
        let fenced = """
        好的，这是为你生成的汇报 PPT 结构：
        ```json
        {
          "title": "2026 智能运维与 AI 升级规划",
          "subtitle": "季度高管汇报",
          "slides": [
            {
              "title": "2026 智能运维与 AI 升级规划",
              "layout": "cover",
              "bullets": ["全面引入多模型协同引擎", "响应耗时降低 65%"],
              "speakerNotes": "各位领导好，今天汇报智能运维升级方案。",
              "visualHint": "深蓝科技极简封面"
            },
            {
              "title": "核心效率提升指标",
              "layout": "metrics",
              "bullets": ["自动巡检覆盖率 100%", "工单平均闭环缩短至 8 分钟"],
              "highlightMetric": "65%",
              "highlightLabel": "平均处置耗时下降",
              "speakerNotes": "重点看 65% 的效率提升。",
              "visualHint": "大数字卡片 + 对比柱状图"
            }
          ]
        }
        ```
        """
        let deck = WuMindPPTEngine.parseDeck(from: fenced, fallbackTopic: "运维升级", theme: .midnightTech)
        XCTAssertEqual(deck.title, "2026 智能运维与 AI 升级规划")
        XCTAssertEqual(deck.slides.count, 2)
        XCTAssertEqual(deck.slides[0].layout, .cover)
        XCTAssertEqual(deck.slides[1].highlightMetric, "65%")
        let md = WuMindPPTEngine.exportMarkdownOutline(deck)
        XCTAssertTrue(md.contains("# 2026 智能运维与 AI 升级规划"))
        XCTAssertTrue(md.contains("65%"))

        let markdownOnly = """
        # 新能源充电站规划
        - 选址覆盖高速与核心商圈
        - 液冷超充单枪 600kW

        ## 投资回报测算
        - 参考口径：单站 3.2 年回本
        """
        let fallbackDeck = WuMindPPTEngine.parseDeck(from: markdownOnly, fallbackTopic: "新能源", theme: .executiveBlue)
        XCTAssertEqual(fallbackDeck.slides.count, 2)
        XCTAssertEqual(fallbackDeck.slides[0].title, "新能源充电站规划")
        XCTAssertEqual(fallbackDeck.slides[1].title, "投资回报测算")
    }

    private static func reply(_ request: URLRequest, _ json: String, status: Int = 200) -> (Data, URLResponse) {
        (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
