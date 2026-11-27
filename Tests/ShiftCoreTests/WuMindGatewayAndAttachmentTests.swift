import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class WuMindGatewayAndAttachmentTests: XCTestCase {
    func testGatewayURLRequiresHTTPS() {
        XCTAssertNotNil(try? WuMindGatewayClient.normalizedGatewayURL("https://wumind.example.com"))
        XCTAssertThrowsError(try WuMindGatewayClient.normalizedGatewayURL("http://wumind.example.com"))
        XCTAssertThrowsError(try WuMindGatewayClient.normalizedGatewayURL("not-a-url"))
    }

    func testGatewayStreamsReasoningAnswerAndBillingReceipt() async throws {
        let client = WuMindGatewayClient(
            dataTransport: { _ in fatalError("Not expected") },
            streamTransport: { request, status, line in
                XCTAssertEqual(request.url?.absoluteString, "https://api.wumind.test/v1/chat/completions")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer wm_live_demo")
                try status(200)
                try await line(#"data: {"reasoning":"先梳理步骤"}"#)
                try await line(#"data: {"content":"最终结论"}"#)
                try await line(#"data: {"wumind_billing":{"promptTokens":120,"completionTokens":80,"reasoningTokens":40,"costYuan":0.003,"balanceYuan":19.997}}"#)
                try await line("data: [DONE]")
            }
        )

        var events: [WuMindGatewayClient.StreamEvent] = []
        for try await ev in client.streamChat(
            gatewayURL: "https://api.wumind.test",
            userToken: "wm_live_demo",
            modelID: "deepseek-reasoner",
            messages: [.init(role: .user, text: "hello")],
            systemPrompt: "sys",
            deepThinking: true
        ) {
            events.append(ev)
        }

        XCTAssertEqual(events, [
            .reasoning("先梳理步骤"),
            .content("最终结论"),
            .billing(.init(promptTokens: 120, completionTokens: 80, reasoningTokens: 40, costYuan: 0.003, balanceYuan: 19.997))
        ])
    }

    func testExplicitProviderRefusalsAreNotNormalEndTurns() {
        XCTAssertTrue(MultiProviderAIClient.isExplicitModelRefusal(provider: .claude, frame: [
            "type": "message_delta", "delta": ["stop_reason": "refusal"],
        ]))
        XCTAssertTrue(MultiProviderAIClient.isExplicitModelRefusal(provider: .openAI, frame: [
            "choices": [["finish_reason": "content_filter"]],
        ]))
        XCTAssertFalse(MultiProviderAIClient.isExplicitModelRefusal(provider: .claude, frame: [
            "type": "message_delta", "delta": ["stop_reason": "end_turn"],
        ]))
    }

    func testGatewayRefusalThrowsAfterDeliveringBillingWithoutSuccessfulCompletion() async {
        let client = WuMindGatewayClient(
            dataTransport: { _ in fatalError("Not expected") },
            streamTransport: { _, status, line in
                try status(200)
                try await line(#"data: {"wumind_error":{"code":"model_refused","message":"Claude refused"}}"#)
                try await line(#"data: {"wumind_billing":{"promptTokens":2195,"completionTokens":146,"reasoningTokens":0,"costYuan":0.1,"balanceYuan":19.9}}"#)
                try await line("data: [DONE]")
            }
        )
        var events: [WuMindGatewayClient.StreamEvent] = []
        do {
            for try await event in client.streamChat(
                gatewayURL: "https://api.wumind.test", userToken: "test", modelID: "claude-test",
                messages: [.init(role: .user, text: "test")], systemPrompt: nil, deepThinking: false
            ) { events.append(event) }
            XCTFail("Refusals cannot end as success")
        } catch {
            XCTAssertEqual(error as? WuMindGatewayClient.GatewayError, .modelRefused)
        }
        XCTAssertEqual(events, [.billing(.init(promptTokens: 2195, completionTokens: 146, reasoningTokens: 0,
                                               costYuan: 0.1, balanceYuan: 19.9))])
    }

    func testGatewayReturnsInsufficientBalanceOnHTTP402() async {
        let client = WuMindGatewayClient(
            dataTransport: { _ in fatalError("Not expected") },
            streamTransport: { _, status, _ in
                try status(402)
            }
        )

        do {
            for try await _ in client.streamChat(
                gatewayURL: "https://api.wumind.test",
                userToken: "wm_live_demo",
                modelID: "deepseek-reasoner",
                messages: [.init(role: .user, text: "hi")],
                systemPrompt: nil,
                deepThinking: false
            ) {}
            XCTFail("Expected insufficientBalance")
        } catch let err as WuMindGatewayClient.GatewayError {
            XCTAssertEqual(err, .insufficientBalance)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGatewayAdminConfigAndVoucherEndpointsSendAdminHeader() async throws {
        let client = WuMindGatewayClient(
            dataTransport: { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-WuMind-Admin-Secret"), "admin-secret-xyz")
                let url = request.url!
                if url.path == "/v1/admin/vouchers" {
                    let body = #"{"vouchers":[{"code":"WM-AAAA-BBBB-CCCC","amountYuan":50,"note":"VIP","redeemedBy":null,"createdAt":"2026-11-24"}]}"#
                    return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
                let cfg = WuMindCommercialConfig()
                let data = try JSONEncoder().encode(cfg)
                return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            streamTransport: { _, _, _ in fatalError("Not expected") }
        )

        let saved = try await client.adminSaveConfig(
            gatewayURL: "https://api.wumind.test",
            adminSecret: "admin-secret-xyz",
            config: WuMindCommercialConfig()
        )
        XCTAssertFalse(saved.pricing.isEmpty)

        let vouchers = try await client.adminCreateVouchers(
            gatewayURL: "https://api.wumind.test",
            adminSecret: "admin-secret-xyz",
            amountYuan: 50,
            count: 1,
            note: "VIP"
        )
        XCTAssertEqual(vouchers.first?.code, "WM-AAAA-BBBB-CCCC")
        XCTAssertEqual(vouchers.first?.amountYuan, 50)
    }

    func testAttachmentParserExtractsCodeAndCSVAndFormatsContext() throws {
        let swiftSource = "struct Demo {\n    let value = 42\n}\n"
        let doc = try WuMindAttachmentParser.extract(data: Data(swiftSource.utf8), filename: "Demo.swift")
        XCTAssertEqual(doc.kind, .code)
        XCTAssertTrue(doc.extractedText.contains("let value = 42"))
        XCTAssertTrue(doc.summaryBadge.contains("SWIFT"))

        let formatted = WuMindAttachmentParser.formatContext(for: [doc])
        XCTAssertTrue(formatted.contains("Demo.swift"))
        XCTAssertTrue(formatted.contains("let value = 42"))

        XCTAssertThrowsError(try WuMindAttachmentParser.extract(data: Data([0x00, 0xFF, 0xFE, 0x00]), filename: "binary.bin"))
    }

    func testAccountStatusDecodesUsageMetricsAndFormatsTokens() throws {
        let json = """
        {
          "userID": "WM-123456",
          "balanceYuan": 18.75,
          "totalRechargedYuan": 20.0,
          "totalSpentYuan": 1.25,
          "totalRequests": 14,
          "totalPromptTokens": 8500,
          "totalCompletionTokens": 4200,
          "totalReasoningTokens": 1800,
          "todaySpentYuan": 0.35,
          "todayTokens": 3200,
          "ledger": []
        }
        """
        let status = try JSONDecoder().decode(WuMindAccountStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.balanceYuan, 18.75, accuracy: 0.0001)
        XCTAssertEqual(status.totalRequests, 14)
        XCTAssertEqual(status.totalTokens, 14_500)
        XCTAssertEqual(WuMindAccountStatus.formatTokens(850), "850")
        XCTAssertEqual(WuMindAccountStatus.formatTokens(14_500), "14.5K")
        XCTAssertEqual(WuMindAccountStatus.formatTokens(2_350_000), "2.35M")
    }

    func testGatewayWebSearchDecodesStructuredNotConfiguredAndFullTextStatus() async throws {
        // 1) HTTP 503 search_not_configured preserves structured response instead of swallowing code
        let unconfiguredClient = WuMindGatewayClient(
            dataTransport: { req in
                let payload = """
                {
                  "ok": false,
                  "status": "search_not_configured",
                  "code": "search_not_configured",
                  "error": "联网搜索未配置：服务端未配置 Tavily / Brave / Serper 搜索密钥。",
                  "query": "今天天气",
                  "provider": "",
                  "results": [],
                  "costYuan": 0
                }
                """
                return (Data(payload.utf8), HTTPURLResponse(url: req.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
            },
            streamTransport: { _, _, _ in fatalError("Not expected") }
        )
        let res503 = try await unconfiguredClient.webSearch(
            gatewayURL: "https://api.wumind.test",
            userToken: "wm_tok",
            query: "今天天气"
        )
        XCTAssertEqual(res503.status, "search_not_configured")
        XCTAssertEqual(res503.ok, false)
        XCTAssertTrue(res503.results.isEmpty)

        // 2) HTTP 200 distinguishes full_text vs fetch_failed vs snippet_only
        let verifiedClient = WuMindGatewayClient(
            dataTransport: { req in
                let payload = """
                {
                  "ok": true,
                  "status": "ok",
                  "code": "ok",
                  "query": "Swift 6",
                  "provider": "Tavily",
                  "fullTextCount": 1,
                  "fetchFailedCount": 1,
                  "costYuan": 0.03,
                  "results": [
                    {
                      "title": "Swift 6 Release",
                      "url": "https://swift.org/blog/swift-6",
                      "snippet": "Swift 6 summary",
                      "readStatus": "full_text",
                      "extractedText": "Full article text verified from server."
                    },
                    {
                      "title": "Paywalled Page",
                      "url": "https://example.com/private",
                      "snippet": "Snippet only",
                      "readStatus": "fetch_failed",
                      "fetchError": "原文无法打开（HTTP 403）"
                    }
                  ]
                }
                """
                return (Data(payload.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            streamTransport: { _, _, _ in fatalError("Not expected") }
        )
        let res200 = try await verifiedClient.webSearch(
            gatewayURL: "https://api.wumind.test",
            userToken: "wm_tok",
            query: "Swift 6",
            readTopPages: 2
        )
        XCTAssertEqual(res200.fullTextCount, 1)
        XCTAssertEqual(res200.fetchFailedCount, 1)
        XCTAssertEqual(res200.results.first?.isFullTextRead, true)
        XCTAssertEqual(res200.results.first?.readStatusBadge, "已读取原文")
        XCTAssertEqual(res200.results.last?.isFetchFailed, true)
        XCTAssertEqual(res200.results.last?.readStatusBadge, "原文无法打开（HTTP 403）")
    }

    func testGatewayUploadWorkAssetBinaryReturnsSyncedAndHandlesR2Unconfigured() async throws {
        let r2Client = WuMindGatewayClient(
            dataTransport: { req in
                XCTAssertEqual(req.httpMethod, "PUT")
                XCTAssertEqual(req.url?.path, "/v1/works/wk_1/asset")
                XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "video/mp4")
                let body = """
                {
                  "ok": true,
                  "workID": "wk_1",
                  "kind": "asset",
                  "objectKey": "works/WM-1/wk_1/asset.mp4",
                  "sizeBytes": 128,
                  "sha256": "abc123",
                  "mimeType": "video/mp4",
                  "assetSyncState": "synced"
                }
                """
                return (Data(body.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            streamTransport: { _, _, _ in fatalError("Not expected") }
        )
        let uploaded = try await r2Client.uploadWorkAssetBinary(
            gatewayURL: "https://api.wumind.test",
            userToken: "wm_tok",
            workID: "wk_1",
            data: Data(repeating: 0x41, count: 128),
            mimeType: "video/mp4"
        )
        XCTAssertTrue(uploaded.ok)
        XCTAssertEqual(uploaded.assetSyncState, "synced")
        XCTAssertEqual(uploaded.sizeBytes, 128)

        let noR2Client = WuMindGatewayClient(
            dataTransport: { req in
                let body = #"{"error":"R2 未绑定","code":"object_storage_unconfigured"}"#
                return (Data(body.utf8), HTTPURLResponse(url: req.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
            },
            streamTransport: { _, _, _ in fatalError("Not expected") }
        )
        do {
            _ = try await noR2Client.uploadWorkAssetBinary(
                gatewayURL: "https://api.wumind.test",
                userToken: "wm_tok",
                workID: "wk_1",
                data: Data([0x01, 0x02]),
                mimeType: "image/png"
            )
            XCTFail("Expected objectStorageUnconfigured")
        } catch let err as WuMindGatewayClient.GatewayError {
            if case .objectStorageUnconfigured = err {
                // expected
            } else {
                XCTFail("Expected objectStorageUnconfigured, got \(err)")
            }
        }
    }

    func testMultiProviderSalvagesReasoningOnlyRepliesAcrossProviders() async throws {
        // 1) OpenAI-compatible relay returning empty content + non-empty reasoning_content (e.g. gemini-4-neon)
        let relayClient = MultiProviderAIClient { req in
            let body = """
            {
              "choices": [
                {
                  "message": {
                    "role": "assistant",
                    "content": "",
                    "reasoning_content": "逐步推理并给出最终结论：今天 A 组值白班。"
                  },
                  "finish_reason": "stop"
                }
              ]
            }
            """
            return (Data(body.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let relayReply = try await relayClient.sendDetailed(
            provider: .openAI,
            model: AIProviderModel(id: "gemini-4-neon", displayName: "gemini-4-neon", supportsTextChat: true),
            apiKey: "sk-test-1234",
            messages: [AIProviderMessage(role: .user, text: "今天谁值班")],
            deepThinking: true,
            baseURL: "https://aihubmix.com/v1"
        )
        XCTAssertTrue(relayReply.answer.contains("今天 A 组值白班"))
        XCTAssertNotNil(relayReply.reasoning)

        // 2) Gemini native returning only thought=true part
        let geminiClient = MultiProviderAIClient { req in
            let body = """
            {
              "candidates": [
                {
                  "content": {
                    "parts": [
                      { "thought": true, "text": "内部推理摘要：方案二更节省成本。" }
                    ]
                  },
                  "finishReason": "STOP"
                }
              ]
            }
            """
            return (Data(body.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let geminiReply = try await geminiClient.sendDetailed(
            provider: .gemini,
            model: AIProviderModel(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro", supportsTextChat: true),
            apiKey: "AIzaSyTest1234",
            messages: [AIProviderMessage(role: .user, text: "对比方案")],
            deepThinking: true
        )
        XCTAssertTrue(geminiReply.answer.contains("方案二更节省成本"))
    }

    func testMultiProviderSSELineParsingAcrossProviders() {
        let openAILine = #"data: {"choices":[{"delta":{"reasoning_content":"思路A","content":"正文B"}}]}"#
        let pOpenAI = MultiProviderAIClient.parseSSELine(provider: .openAI, line: openAILine)
        XCTAssertEqual(pOpenAI.reasoning, "思路A")
        XCTAssertEqual(pOpenAI.content, "正文B")

        let geminiLine = #"data: {"candidates":[{"content":{"parts":[{"thought":true,"text":"先思考"},{"text":"再输出"}]}}]}"#
        let pGemini = MultiProviderAIClient.parseSSELine(provider: .gemini, line: geminiLine)
        XCTAssertEqual(pGemini.reasoning, "先思考")
        XCTAssertEqual(pGemini.content, "再输出")

        let claudeThink = #"data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"深度推演"}}"#
        let claudeText = #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"最终回答"}}"#
        XCTAssertEqual(MultiProviderAIClient.parseSSELine(provider: .claude, line: claudeThink).reasoning, "深度推演")
        XCTAssertEqual(MultiProviderAIClient.parseSSELine(provider: .claude, line: claudeText).content, "最终回答")
    }
}
