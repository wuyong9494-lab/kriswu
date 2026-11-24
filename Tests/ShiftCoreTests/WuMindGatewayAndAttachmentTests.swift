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
}
