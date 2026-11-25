import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class WuMindFlagshipV2Tests: XCTestCase {
    private let sampleImage = AIProviderMessage.ImageAttachment(
        mimeType: "image/jpeg",
        base64Data: Data([0xFF, 0xD8, 0xFF, 0xD9]).base64EncodedString()
    )

    private static func okJSON(_ request: URLRequest, _ body: String, status: Int = 200) -> (Data, URLResponse) {
        let url = request.url ?? URL(string: "https://example.com")!
        let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), resp)
    }

    // MARK: - 1. Native Multimodal Vision Passthrough Across All Providers + Gateway

    func testMultiProviderEncodesNativeVisionForOpenAIResponsesClaudeGeminiAndProxy() async throws {
        // OpenAI Responses API -> input_image data URI
        let openAIClient = MultiProviderAIClient { request in
            let body = try XCTUnwrap(request.httpBody)
            let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let input = try XCTUnwrap(obj["input"] as? [[String: Any]])
            let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
            XCTAssertEqual(content.count, 2)
            XCTAssertEqual(content[0]["type"] as? String, "input_text")
            XCTAssertEqual(content[1]["type"] as? String, "input_image")
            let imgURL = try XCTUnwrap(content[1]["image_url"] as? String)
            XCTAssertTrue(imgURL.hasPrefix("data:image/jpeg;base64,"))
            return Self.okJSON(request, #"{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"看到图表了"}]}]}"#)
        }
        let openAIReply = try await openAIClient.sendDetailed(
            provider: .openAI,
            model: AIProviderModel(id: "gpt-4o", displayName: "GPT-4o", supportsTextChat: true),
            apiKey: "sk-test-demo",
            messages: [AIProviderMessage(role: .user, text: "看图", images: [sampleImage])],
            systemPrompt: "sys"
        )
        XCTAssertEqual(openAIReply.answer, "看到图表了")

        // Anthropic Claude -> base64 image block
        let claudeClient = MultiProviderAIClient { request in
            let body = try XCTUnwrap(request.httpBody)
            let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let msgs = try XCTUnwrap(obj["messages"] as? [[String: Any]])
            let content = try XCTUnwrap(msgs.first?["content"] as? [[String: Any]])
            XCTAssertEqual(content.first?["type"] as? String, "image")
            let source = try XCTUnwrap(content.first?["source"] as? [String: Any])
            XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
            XCTAssertEqual(source["type"] as? String, "base64")
            return Self.okJSON(request, #"{"stop_reason":"end_turn","content":[{"type":"text","text":"Claude读图"}]}"#)
        }
        let claudeReply = try await claudeClient.sendDetailed(
            provider: .claude,
            model: AIProviderModel(id: "claude-sonnet-4-20250514", displayName: "Claude", supportsTextChat: true),
            apiKey: "sk-ant-test-demo",
            messages: [AIProviderMessage(role: .user, text: "看图", images: [sampleImage])],
            systemPrompt: "sys"
        )
        XCTAssertEqual(claudeReply.answer, "Claude读图")

        // Google Gemini -> inline_data part
        let geminiClient = MultiProviderAIClient { request in
            let body = try XCTUnwrap(request.httpBody)
            let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let contents = try XCTUnwrap(obj["contents"] as? [[String: Any]])
            let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
            XCTAssertEqual(parts.count, 2)
            let inline = try XCTUnwrap(parts[1]["inline_data"] as? [String: Any])
            XCTAssertEqual(inline["mime_type"] as? String, "image/jpeg")
            return Self.okJSON(request, #"{"candidates":[{"finishReason":"STOP","content":{"parts":[{"text":"Gemini读图"}]}}]}"#)
        }
        let geminiReply = try await geminiClient.sendDetailed(
            provider: .gemini,
            model: AIProviderModel(id: "gemini-2.5-pro", displayName: "Gemini", supportsTextChat: true),
            apiKey: "AIza-test-demo",
            messages: [AIProviderMessage(role: .user, text: "看图", images: [sampleImage])],
            systemPrompt: "sys"
        )
        XCTAssertEqual(geminiReply.answer, "Gemini读图")

        // OpenAI-compatible Chat Completions (custom proxy) -> image_url object
        let proxyClient = MultiProviderAIClient { request in
            let body = try XCTUnwrap(request.httpBody)
            let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let msgs = try XCTUnwrap(obj["messages"] as? [[String: Any]])
            let userMsg = try XCTUnwrap(msgs.last)
            let content = try XCTUnwrap(userMsg["content"] as? [[String: Any]])
            XCTAssertEqual(content.count, 2)
            XCTAssertEqual(content[1]["type"] as? String, "image_url")
            return Self.okJSON(request, #"{"choices":[{"finish_reason":"stop","message":{"content":"代理读图"}}]}"#)
        }
        let proxyReply = try await proxyClient.sendDetailed(
            provider: .openAI,
            model: AIProviderModel(id: "gpt-4o", displayName: "GPT-4o", supportsTextChat: true),
            apiKey: "sk-proxy-demo",
            messages: [AIProviderMessage(role: .user, text: "看图", images: [sampleImage])],
            baseURL: "https://proxy.example.com/v1",
            systemPrompt: "sys"
        )
        XCTAssertEqual(proxyReply.answer, "代理读图")
    }

    func testExtractedDocumentProducesAIImageAttachment() {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let doc = WuMindAttachmentParser.ExtractedDocument(
            filename: "diagram.jpg",
            kind: .image,
            byteCount: jpeg.count,
            extractedText: "OCR 文本",
            summaryBadge: "图片 · 100×100",
            imageJPEGData: jpeg,
            imageMimeType: "image/jpeg"
        )
        XCTAssertTrue(doc.hasNativeImage)
        let att = doc.makeAIImageAttachment()
        XCTAssertEqual(att?.mimeType, "image/jpeg")
        XCTAssertEqual(att?.base64Data, jpeg.base64EncodedString())
    }

    // MARK: - 2. Honest Provider Verification & Secret-Redacted Host/Code Diagnostics

    func testProbeAndListModelsReportsExactHostAndSanitized401ErrorWithoutLeakingKey() async {
        let leakedKey = "sk-proj-SecretKeyValue1234567890ABCDEF"
        let client = MultiProviderAIClient { request in
            let body = #"{"error":{"message":"Incorrect API key provided: \#(leakedKey). You can find your API key at platform.openai.com.","type":"invalid_request_error","code":"invalid_api_key"}}"#
            return Self.okJSON(request, body, status: 401)
        }

        do {
            _ = try await client.probeAndListModels(provider: .openAI, apiKey: leakedKey, baseURL: nil)
            XCTFail("Expected AIProviderDiagnosticError")
        } catch let diag as AIProviderDiagnosticError {
            XCTAssertEqual(diag.underlying, .invalidCredential)
            XCTAssertEqual(diag.host, "api.openai.com")
            XCTAssertEqual(diag.httpStatus, 401)
            XCTAssertEqual(diag.errorCode, "invalid_api_key")
            let desc = diag.errorDescription ?? ""
            XCTAssertTrue(desc.contains("api.openai.com"))
            XCTAssertTrue(desc.contains("HTTP 401"))
            XCTAssertTrue(desc.contains("invalid_api_key"))
            XCTAssertFalse(desc.contains(leakedKey), "Diagnostic error must NEVER leak raw API key")
            XCTAssertTrue(desc.contains("[REDACTED]"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - 3. Metered Web Search, Sync, Pairing, Payments & IAP Gateway APIs

    func testGatewayWebSearchAndVisionStreamAndSyncAndPaymentsAndIAPEndpoints() async throws {
        let client = WuMindGatewayClient(
            dataTransport: { request in
                let url = try XCTUnwrap(request.url)
                switch url.path {
                case "/v1/tools/web-search":
                    let json = #"{"query":"Swift 6","provider":"tavily","results":[{"title":"Swift 6","url":"https://swift.org","snippet":"Concurrency","publishedDate":"2026"}],"costYuan":0.03,"balanceYuan":19.97}"#
                    return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                case "/v1/schedules":
                    let json = #"{"schedules":[{"id":"sch1","title":"晨报","prompt":"汇报","modelID":"deepseek-chat","intervalMinutes":1440,"enabled":true,"nextRunEpoch":1800000,"lastRunAt":"2026-11-24T08:00:00Z","lastAnswer":"今日正常","lastCostYuan":0.012}]}"#
                    return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                case "/v1/sync/push":
                    let json = #"{"ok":true,"version":4,"updatedAt":"2026-11-24T12:00:00Z"}"#
                    return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                case "/v1/sync/pull":
                    let json = #"{"hasSnapshot":true,"encryptedPayload":"WME1:abc","version":4,"deviceName":"iPhone","updatedAt":"2026-11-24T12:00:00Z"}"#
                    return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                case "/v1/sync/pair/create":
                    let json = #"{"code":"SYNC-AB12-CD34","expiresAt":"2026-11-24T12:10:00Z"}"#
                    return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                case "/v1/sync/pair/claim":
                    let json = #"{"userID":"WM-849201","userToken":"wm_pair_tok","balanceYuan":88.5}"#
                    return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                case "/v1/public/config":
                    let json = #"{"pricing":[],"rechargeNote":"n","contactNote":"","announcement":"","autoCheckoutEnabled":true}"#
                    return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                case "/v1/payments/create-order":
                    let json = #"{"id":"ORD-123456","amountYuan":30,"channel":"wechat","status":"pending","note":"在线自动到账充值单","checkoutURL":"https://pay.example.com/submit.php?out_trade_no=ORD-123456","createdAt":"2026-11-24","paidAt":null}"#
                    return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                case "/v1/payments/orders":
                    let json = #"{"orders":[{"id":"ORD-123456","amountYuan":30,"channel":"wechat","status":"paid","note":"充值","checkoutURL":null,"createdAt":"2026-11-24","paidAt":"2026-11-24"}]}"#
                    return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                case "/v1/payments/orders/ORD-123456":
                    let json = #"{"id":"ORD-123456","status":"paid","amountYuan":30,"channel":"wechat","balanceYuan":118.5,"paidAt":"2026-11-24T12:15:00Z"}"#
                    return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                case "/v1/iap/verify":
                    let json = #"{"ok":true,"environment":"Sandbox","isSandbox":true,"creditedYuan":18,"balanceYuan":0,"sandboxBalanceYuan":18,"alreadyCredited":false}"#
                    return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                default:
                    XCTFail("Unexpected path \(url.path)")
                    return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
                }
            },
            streamTransport: { request, status, line in
                let body = try XCTUnwrap(request.httpBody)
                let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                let msgs = try XCTUnwrap(obj["messages"] as? [[String: Any]])
                let imgs = try XCTUnwrap(msgs.first?["images"] as? [[String: Any]])
                XCTAssertEqual(imgs.first?["mimeType"] as? String, "image/jpeg")
                try status(200)
                try await line(#"data: {"content":"网关视觉OK"}"#)
                try await line("data: [DONE]")
            }
        )

        let pubCfg = try await client.fetchPublicConfig(gatewayURL: "https://api.wumind.test")
        XCTAssertTrue(pubCfg.isAutoCheckoutEnabled)
        let pausedCfg = WuMindCommercialConfig(autoCheckoutEnabled: true, autoCreditPaused: true)
        XCTAssertTrue(pausedCfg.isAutoCreditPaused)
        XCTAssertFalse(pausedCfg.isAutoCheckoutEnabled, "Paused gateway must report autoCheckoutEnabled == false")

        let search = try await client.webSearch(gatewayURL: "https://api.wumind.test", userToken: "wm_t", query: "Swift 6")
        XCTAssertEqual(search.provider, "tavily")
        XCTAssertEqual(search.costYuan, 0.03)
        XCTAssertEqual(search.results.first?.title, "Swift 6")

        let schedules = try await client.fetchCloudSchedules(gatewayURL: "https://api.wumind.test", userToken: "wm_t")
        XCTAssertEqual(schedules.first?.lastAnswer, "今日正常")

        let ack = try await client.pushCloudSyncSnapshot(gatewayURL: "https://api.wumind.test", userToken: "wm_t", encryptedPayload: "WME1:abc", version: 4, deviceName: "iPhone")
        XCTAssertEqual(ack.version, 4)

        let env = try await client.pullCloudSyncSnapshot(gatewayURL: "https://api.wumind.test", userToken: "wm_t")
        XCTAssertTrue(env.hasSnapshot)
        XCTAssertEqual(env.encryptedPayload, "WME1:abc")

        let pair = try await client.createPairingCode(gatewayURL: "https://api.wumind.test", userToken: "wm_t")
        XCTAssertEqual(pair.code, "SYNC-AB12-CD34")

        let claimed = try await client.claimPairingCode(gatewayURL: "https://api.wumind.test", code: "SYNC-AB12-CD34")
        XCTAssertEqual(claimed.userID, "WM-849201")
        XCTAssertEqual(claimed.balanceYuan, 88.5)

        let order = try await client.createPaymentOrder(gatewayURL: "https://api.wumind.test", userToken: "wm_t", amountYuan: 30, channel: "wechat")
        XCTAssertEqual(order.id, "ORD-123456")
        XCTAssertEqual(order.checkoutURL, "https://pay.example.com/submit.php?out_trade_no=ORD-123456")

        let orders = try await client.fetchPaymentOrders(gatewayURL: "https://api.wumind.test", userToken: "wm_t")
        XCTAssertEqual(orders.first?.status, "paid")

        let orderStatus = try await client.fetchPaymentOrderStatus(gatewayURL: "https://api.wumind.test", userToken: "wm_t", orderID: "ORD-123456")
        XCTAssertTrue(orderStatus.isPaid)
        XCTAssertEqual(orderStatus.balanceYuan, 118.5)

        let iap = try await client.verifyAppleIAP(
            gatewayURL: "https://api.wumind.test",
            userToken: "wm_t",
            productID: "com.kriswu.wumind.credit.18",
            transactionID: "2000000111222333",
            originalTransactionID: "2000000111222333",
            jwsRepresentation: "a.b.c"
        )
        XCTAssertTrue(iap.isSandboxTransaction)
        XCTAssertEqual(iap.creditedYuan, 18)
        XCTAssertEqual(iap.balanceYuan, 0)
        XCTAssertEqual(iap.sandboxBalanceYuan, 18)

        var gatewayOut = ""
        for try await ev in client.streamChat(
            gatewayURL: "https://api.wumind.test",
            userToken: "wm_t",
            modelID: "gpt-4o",
            messages: [.init(role: .user, text: "看图", images: [sampleImage])],
            systemPrompt: nil,
            deepThinking: false
        ) {
            if case .content(let c) = ev { gatewayOut += c }
        }
        XCTAssertEqual(gatewayOut, "网关视觉OK")
    }

    func testDirectWebSearchParsesTavilyAndDuckDuckGoHTML() async {
        let sampleHTML = """
        <div class="result">
          <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fswift.org%2Fblog">Swift <b>Official</b> Blog</a>
          <a class="result__snippet">Latest Swift 6 concurrency updates.</a>
        </div>
        """
        let parsed = WuMindAgentTools.parseDuckDuckGoHTML(sampleHTML, limit: 5)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].title, "Swift Official Blog")
        XCTAssertEqual(parsed[0].url, "https://swift.org/blog")
        XCTAssertTrue(parsed[0].snippet.contains("Swift 6"))

        let tavilyRes = await WuMindAgentTools.directWebSearch(
            query: "Swift concurrency",
            maxResults: 3,
            tavilyKey: "tvly-demo"
        ) { req in
            XCTAssertEqual(req.url?.host, "api.tavily.com")
            let body = #"{"results":[{"title":"SE-0414","url":"https://github.com/swiftlang","content":"Region based isolation"}]}"#
            return (Data(body.utf8), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertTrue(tavilyRes.succeeded)
        XCTAssertTrue(tavilyRes.observationText.contains("SE-0414"))
    }

    // MARK: - 4. Rich Media Parser (LaTeX Math + Mermaid Diagrams + GFM Tables)

    func testRichContentParserFormatsLaTeXWithoutBreakingCurrency() {
        let md = """
        商品价格为 $100 或 ¥200，其中质能方程为 $E = mc^2$，满足 \\(\\alpha + \\beta \\le \\pi\\)。

        $$
        x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}
        $$

        代码中的 `$HOME` 不应被改写。
        """
        let segments = WuMindRichContentParser.splitSegments(md)
        XCTAssertEqual(segments.count, 3)

        if case .prose(let p1) = segments[0] {
            XCTAssertTrue(p1.contains("$100"), "Currency $100 must remain untouched")
            XCTAssertTrue(p1.contains("¥200"))
            XCTAssertTrue(p1.contains("mc²"))
            XCTAssertTrue(p1.contains("α"))
            XCTAssertTrue(p1.contains("β"))
            XCTAssertTrue(p1.contains("≤"))
            XCTAssertTrue(p1.contains("π"))
        } else {
            XCTFail("Expected prose segment 0")
        }

        if case .displayMath(let raw, let pretty) = segments[1] {
            XCTAssertTrue(raw.contains("\\frac"))
            XCTAssertTrue(pretty.contains("±"))
            XCTAssertTrue(pretty.contains("√"))
            XCTAssertTrue(pretty.contains("b²"))
        } else {
            XCTFail("Expected displayMath segment 1")
        }

        if case .prose(let p2) = segments[2] {
            XCTAssertTrue(p2.contains("`$HOME`"))
        } else {
            XCTFail("Expected prose segment 2")
        }
    }

    func testRichContentParserParsesMermaidAndGFMTables() {
        let md = """
        ```mermaid
        flowchart LR
          A[用户提问] --> B{智能体规划}
          B -->|需要资料| C[联网搜索]
          B -->|直接解答| D[汇总输出]
        ```

        | 模型 | 上下文 | 价格 |
        | --- | :---: | ---: |
        | DeepSeek V4 | 1M | ¥5 / ¥20 |
        | GPT-4o | 128K | ¥36 / ¥144 |

        ```mermaid
        sequenceDiagram
          App->>Gateway: POST /v1/chat
          Gateway-->>App: SSE Token + 计费
        ```

        ```mermaid
        pie title 费用构成
          "模型推理" : 75
          "联网搜索" : 25
        ```
        """
        let segments = WuMindRichContentParser.splitSegments(md)
        XCTAssertEqual(segments.count, 4)

        if case .mermaid(_, let diagram) = segments[0],
           case .flowchart(let dir, let nodes, let edges) = diagram {
            XCTAssertEqual(dir, .leftRight)
            XCTAssertEqual(nodes.count, 4)
            XCTAssertEqual(edges.count, 3)
            XCTAssertEqual(edges[1].label, "需要资料")
        } else {
            XCTFail("Expected Mermaid flowchart")
        }

        if case .table(let headers, let rows) = segments[1] {
            XCTAssertEqual(headers, ["模型", "上下文", "价格"])
            XCTAssertEqual(rows.count, 2)
            XCTAssertEqual(rows[0], ["DeepSeek V4", "1M", "¥5 / ¥20"])
        } else {
            XCTFail("Expected GFM table segment")
        }

        if case .mermaid(_, let diagram) = segments[2],
           case .sequence(let actors, let messages) = diagram {
            XCTAssertEqual(actors, ["App", "Gateway"])
            XCTAssertEqual(messages.count, 2)
            XCTAssertTrue(messages[1].dashed)
        } else {
            XCTFail("Expected Mermaid sequenceDiagram")
        }

        if case .mermaid(_, let diagram) = segments[3],
           case .pie(let title, let slices) = diagram {
            XCTAssertEqual(title, "费用构成")
            XCTAssertEqual(slices.count, 2)
            XCTAssertEqual(slices[0].value, 75)
        } else {
            XCTFail("Expected Mermaid pie chart")
        }
    }

    func testWebSearchConnectorAndCommercialDefaultsPresent() {
        XCTAssertTrue(WuMindConnectorSpec.marketplaceCatalog.contains(where: { $0.id == "dev.websearch" && $0.toolName == "web_search" && $0.defaultInstalled }))
        let cfg = WuMindCommercialConfig()
        XCTAssertEqual(cfg.resolvedBillingMode, .appStoreIAP)
        XCTAssertEqual(cfg.resolvedWebSearchCostYuan, 0.03)
        XCTAssertEqual(cfg.resolvedIAPPacks.count, 4)
    }
}
