import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class WuMindPerfAndModelFidelityTests: XCTestCase {
    private actor CallCounter {
        var count = 0
        func increment() { count += 1 }
    }

    func testCapabilityMatrixTruthAcrossAllProvidersAndRelays() {
        // 1. DeepSeek text/reasoner (including built-in DeepSeekChatClient IDs): supports deep thinking, does NOT support native vision attachments
        let dsReasoner = WuMindModelCapabilityMatrix.capabilities(providerRaw: "deepSeek", modelID: "deepseek-reasoner")
        XCTAssertTrue(dsReasoner.textStreaming)
        XCTAssertEqual(dsReasoner.thinkingProtocol, .deepseekThinking)
        XCTAssertFalse(dsReasoner.visionAttachments)
        XCTAssertEqual(WuMindModelCapabilityMatrix.capabilities(providerRaw: "deepSeek", modelID: "deepseek-v4-pro").thinkingProtocol, .deepseekThinking)
        XCTAssertEqual(WuMindModelCapabilityMatrix.capabilities(providerRaw: "deepSeek", modelID: "deepseek-flash").thinkingProtocol, .deepseekThinking)

        let dsImageViolation = WuMindModelCapabilityMatrix.validateChatRequest(
            providerRaw: "deepSeek",
            modelID: "deepseek-reasoner",
            connectionLabel: "WuMind 内置",
            deepThinking: true,
            attachedImageCount: 1
        )
        XCTAssertEqual(dsImageViolation, .visionNotSupported(modelID: "deepseek-reasoner", connectionLabel: "WuMind 内置"))

        // 2. OpenAI GPT-5 vs GPT-4o vs o3-mini
        let gpt5 = WuMindModelCapabilityMatrix.capabilities(providerRaw: "openAI", modelID: "gpt-5")
        XCTAssertEqual(gpt5.thinkingProtocol, .openaiReasoningEffort)
        XCTAssertTrue(gpt5.visionAttachments)
        XCTAssertTrue(gpt5.usesMaxCompletionTokens)

        let gpt4o = WuMindModelCapabilityMatrix.capabilities(providerRaw: "openAI", modelID: "gpt-4o")
        XCTAssertEqual(gpt4o.thinkingProtocol, .unsupported)
        XCTAssertTrue(gpt4o.visionAttachments)
        let gpt4oThinkingViolation = WuMindModelCapabilityMatrix.validateChatRequest(
            providerRaw: "openAI",
            modelID: "gpt-4o",
            connectionLabel: "自有 OpenAI",
            deepThinking: true,
            attachedImageCount: 0
        )
        XCTAssertEqual(gpt4oThinkingViolation, .deepThinkingNotSupported(modelID: "gpt-4o", connectionLabel: "自有 OpenAI"))

        let o3Mini = WuMindModelCapabilityMatrix.capabilities(providerRaw: "openAI", modelID: "o3-mini")
        XCTAssertEqual(o3Mini.thinkingProtocol, .openaiReasoningEffort)
        XCTAssertFalse(o3Mini.visionAttachments)

        // 3. Claude direct vs AIHubMix OpenAI relay
        let claude4Direct = WuMindModelCapabilityMatrix.capabilities(providerRaw: "claude", modelID: "claude-sonnet-4-20250514", isRelayBaseURL: false)
        XCTAssertEqual(claude4Direct.thinkingProtocol, .claudeThinkingBudget)
        XCTAssertTrue(claude4Direct.visionAttachments)

        let claude4Relay = WuMindModelCapabilityMatrix.capabilities(providerRaw: "openAI", modelID: "claude-sonnet-4-20250514", isRelayBaseURL: true)
        XCTAssertEqual(claude4Relay.thinkingProtocol, .openaiReasoningEffort)
        XCTAssertTrue(claude4Relay.visionAttachments)

        // 4. Gemini 2.5 Pro vs 2.0 Flash
        let gemini25 = WuMindModelCapabilityMatrix.capabilities(providerRaw: "gemini", modelID: "gemini-2.5-pro")
        XCTAssertEqual(gemini25.thinkingProtocol, .geminiThinkingConfig)
        XCTAssertTrue(gemini25.visionAttachments)

        let gemini20 = WuMindModelCapabilityMatrix.capabilities(providerRaw: "gemini", modelID: "gemini-2.0-flash")
        XCTAssertEqual(gemini20.thinkingProtocol, .unsupported)

        // 5. Grok 4 / Grok 3 Mini vs Grok 3
        let grok4 = WuMindModelCapabilityMatrix.capabilities(providerRaw: "grok", modelID: "grok-4")
        XCTAssertEqual(grok4.thinkingProtocol, .openaiReasoningEffort)
        XCTAssertTrue(grok4.visionAttachments)

        let grok3 = WuMindModelCapabilityMatrix.capabilities(providerRaw: "grok", modelID: "grok-3")
        XCTAssertEqual(grok3.thinkingProtocol, .unsupported)
        XCTAssertTrue(grok3.visionAttachments)

        // 6. Dedicated media/voice models blocked in text chat
        for specialModel in ["gemini-3.1-flash-image", "sora-2", "gpt-4o-realtime-preview"] {
            let v = WuMindModelCapabilityMatrix.validateChatRequest(
                providerRaw: "openAI",
                modelID: specialModel,
                connectionLabel: "WuMind 内置",
                deepThinking: false,
                attachedImageCount: 0
            )
            XCTAssertEqual(v, .nonChatModelInChat(modelID: specialModel, connectionLabel: "WuMind 内置"))
        }
    }

    func testBuildOpenAIChatPayloadForwardsExactThinkingParameters() {
        let msgs: [[String: Any]] = [["role": "user", "content": "Hi"]]

        // Direct OpenAI GPT-5 with deepThinking -> reasoning_effort=high + max_completion_tokens
        let gpt5Payload = MultiProviderAIClient.buildOpenAIChatPayload(
            provider: .openAI,
            modelID: "gpt-5",
            messages: msgs,
            deepThinking: true,
            isRelay: false,
            stream: true,
            systemPrompt: "sys"
        )
        XCTAssertEqual(gpt5Payload["model"] as? String, "gpt-5")
        XCTAssertEqual(gpt5Payload["reasoning_effort"] as? String, "high")
        XCTAssertNotNil(gpt5Payload["max_completion_tokens"])
        XCTAssertNil(gpt5Payload["max_tokens"])
        XCTAssertEqual(gpt5Payload["stream"] as? Bool, true)

        // AIHubMix relay DeepSeek Reasoner with deepThinking -> thinking: { type: "enabled" }
        let dsRelayPayload = MultiProviderAIClient.buildOpenAIChatPayload(
            provider: .openAI,
            modelID: "deepseek-reasoner",
            messages: msgs,
            deepThinking: true,
            isRelay: true,
            stream: true,
            systemPrompt: nil
        )
        let thinkingObj = dsRelayPayload["thinking"] as? [String: String]
        XCTAssertEqual(thinkingObj?["type"], "enabled")
        XCTAssertNil(dsRelayPayload["reasoning_effort"])

        // Direct Grok 4 with deepThinking -> reasoning_effort=high
        let grok4Payload = MultiProviderAIClient.buildOpenAIChatPayload(
            provider: .grok,
            modelID: "grok-4",
            messages: msgs,
            deepThinking: true,
            isRelay: false,
            stream: true,
            systemPrompt: nil
        )
        XCTAssertEqual(grok4Payload["reasoning_effort"] as? String, "high")

        // Standard GPT-4o with deepThinking: false -> neither thinking nor reasoning_effort
        let gpt4oPayload = MultiProviderAIClient.buildOpenAIChatPayload(
            provider: .openAI,
            modelID: "gpt-4o",
            messages: msgs,
            deepThinking: false,
            isRelay: false,
            stream: true,
            systemPrompt: nil
        )
        XCTAssertNil(gpt4oPayload["reasoning_effort"])
        XCTAssertNil(gpt4oPayload["thinking"])
    }

    func testStrictFidelityNeverSilentlyDowngradesThinkingOrDropsImages() async {
        let counter = CallCounter()
        let client = MultiProviderAIClient(transport: { request in
            await counter.increment()
            let resp = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            let body = #"{"error":{"message":"reasoning_effort rejected by upstream","code":"invalid_param"}}"#.data(using: .utf8)!
            return (body, resp)
        })

        // 1. Pre-flight rejects unsupported deepThinking on gpt-4o BEFORE any HTTP call
        do {
            _ = try await client.sendDetailedDiagnosed(
                provider: .openAI,
                model: AIProviderModel(id: "gpt-4o", displayName: "GPT-4o", supportsTextChat: true),
                apiKey: "sk-test-1234",
                messages: [.init(role: .user, text: "hello")],
                deepThinking: true,
                strictFidelity: true
            )
            XCTFail("Expected pre-flight rejection for gpt-4o + deepThinking")
        } catch let diag as AIProviderDiagnosticError {
            XCTAssertEqual(diag.errorCode, "thinking_not_supported")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let callsAfterPreflightThinking = await counter.count
        XCTAssertEqual(callsAfterPreflightThinking, 0, "Unsupported thinking must be rejected before network")

        // 2. Pre-flight rejects image attachment on text-only o3-mini BEFORE any HTTP call
        let img = AIProviderMessage.ImageAttachment(mimeType: "image/png", base64Data: "iVBORw0KGgo=")
        do {
            _ = try await client.sendDetailedDiagnosed(
                provider: .openAI,
                model: AIProviderModel(id: "o3-mini", displayName: "o3-mini", supportsTextChat: true),
                apiKey: "sk-test-1234",
                messages: [.init(role: .user, text: "看图", images: [img])],
                deepThinking: false,
                strictFidelity: true
            )
            XCTFail("Expected pre-flight rejection for o3-mini + image")
        } catch let diag as AIProviderDiagnosticError {
            XCTAssertEqual(diag.errorCode, "vision_not_supported")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let callsAfterPreflightVision = await counter.count
        XCTAssertEqual(callsAfterPreflightVision, 0, "Unsupported vision must be rejected before network")

        // 3. When upstream returns HTTP 400 on gpt-5 with deepThinking + strictFidelity: true,
        // client MUST fail honestly instead of silently retrying with deepThinking: false!
        do {
            _ = try await client.sendDetailedDiagnosed(
                provider: .openAI,
                model: AIProviderModel(id: "gpt-5", displayName: "GPT-5", supportsTextChat: true),
                apiKey: "sk-test-1234",
                messages: [.init(role: .user, text: "hello")],
                deepThinking: true,
                strictFidelity: true
            )
            XCTFail("Expected honest HTTP 400 failure without silent downgrade retry")
        } catch let diag as AIProviderDiagnosticError {
            XCTAssertEqual(diag.httpStatus, 400)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let callsAfterStrict400 = await counter.count
        XCTAssertEqual(callsAfterStrict400, 1, "strictFidelity must NOT silently retry without deepThinking")
    }

    func testGatewayTraceEventAndInterruptedTaskRecovery() async throws {
        let traceJSON = #"data: {"wumind_trace":{"requestedModel":"claude-sonnet-4-20250514","actualModel":"claude-sonnet-4-20250514","upstreamRoute":"official","upstreamStyle":"claude","deepThinkingRequested":true,"deepThinkingApplied":true,"thinkingParam":"thinking={type:enabled,budget_tokens:6000}","imagesReceived":1,"imagesSent":1,"gatewayPrepMs":2,"upstreamHeaderMs":41,"clientRequestID":"turn-abc-s1","recoveredFromOriginalTask":false}}"#
        let reasoningJSON = #"data: {"reasoning":"核验步骤"}"#
        let contentJSON = #"data: {"content":"最终回答"}"#
        let billingJSON = #"data: {"wumind_billing":{"promptTokens":200,"completionTokens":60,"reasoningTokens":40,"costYuan":0.015,"balanceYuan":99.985}}"#

        let recoveryJSON = #"{"status":"settled","clientRequestID":"turn-abc-s1","model":"claude-sonnet-4-20250514","safeToRetry":false,"recovered":true,"reasoning":"核验步骤","content":"最终回答","billing":{"promptTokens":200,"completionTokens":60,"reasoningTokens":40,"costYuan":0.015,"balanceYuan":99.985},"costYuan":0.015}"#

        let client = WuMindGatewayClient(
            dataTransport: { req in
                XCTAssertEqual(req.httpMethod, "GET")
                XCTAssertEqual(req.url?.path, "/v1/chat/recovery")
                XCTAssertTrue(req.url?.query?.contains("clientRequestID=turn-abc-s1") == true)
                XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer wm_live_token")
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (recoveryJSON.data(using: .utf8)!, resp)
            },
            streamTransport: { _, status, line in
                try status(200)
                try await line(traceJSON)
                try await line(reasoningJSON)
                try await line(contentJSON)
                try await line(billingJSON)
                try await line("data: [DONE]")
            }
        )

        var parsedEvents: [WuMindGatewayClient.StreamEvent] = []
        for try await ev in client.streamChat(
            gatewayURL: "https://api.wumind.test",
            userToken: "wm_live_token",
            modelID: "claude-sonnet-4-20250514",
            messages: [.init(role: .user, text: "测试")],
            systemPrompt: nil,
            deepThinking: true,
            idempotencyKey: "turn-abc-s1"
        ) {
            parsedEvents.append(ev)
        }

        XCTAssertEqual(parsedEvents.count, 4)
        if case .trace(let tr) = parsedEvents[0] {
            XCTAssertEqual(tr.actualModel, "claude-sonnet-4-20250514")
            XCTAssertEqual(tr.upstreamRoute, "official")
            XCTAssertEqual(tr.upstreamStyle, "claude")
            XCTAssertEqual(tr.imagesSent, 1)
            XCTAssertEqual(tr.gatewayPrepMs, 2)
            XCTAssertEqual(tr.upstreamHeaderMs, 41)
            XCTAssertFalse(tr.recoveredFromOriginalTask)
        } else {
            XCTFail("Expected .trace as first stream event")
        }

        let recovery = try await client.recoverChatTask(
            gatewayURL: "https://api.wumind.test",
            userToken: "wm_live_token",
            clientRequestID: "turn-abc-s1"
        )
        XCTAssertEqual(recovery.status, "settled")
        XCTAssertFalse(recovery.safeToRetry)
        XCTAssertEqual(recovery.content, "最终回答")
        XCTAssertEqual(recovery.reasoning, "核验步骤")
        XCTAssertEqual(recovery.billing?.costYuan, 0.015)
    }

    func testAntiFightScrollFollowStateAndPercentilesAndFidelityCheck() {
        var scroll = WuMindScrollFollowState()
        XCTAssertTrue(scroll.shouldAutoScrollOnStreamTick)

        // Small jitter does not detach
        scroll.handleUserDrag(translationY: 4.0, isGenerating: true)
        XCTAssertTrue(scroll.shouldAutoScrollOnStreamTick)

        // User drags upward to read earlier text -> immediately detaches!
        scroll.handleUserDrag(translationY: 12.0, isGenerating: true)
        XCTAssertFalse(scroll.shouldAutoScrollOnStreamTick)
        XCTAssertTrue(scroll.userDetached)

        // Scrolling far from bottom keeps detached
        scroll.handleBottomDistance(120.0, isGenerating: true)
        XCTAssertFalse(scroll.shouldAutoScrollOnStreamTick)

        // Deliberately scrolling all the way back to bottom re-attaches
        scroll.handleBottomDistance(10.0, isGenerating: true)
        XCTAssertTrue(scroll.shouldAutoScrollOnStreamTick)
        XCTAssertFalse(scroll.userDetached)

        // Explicit pause & jumpToLatest
        scroll.pauseFollow()
        XCTAssertFalse(scroll.shouldAutoScrollOnStreamTick)
        scroll.jumpToLatest()
        XCTAssertTrue(scroll.shouldAutoScrollOnStreamTick)

        // Latency percentiles P50 / P95
        let p = WuMindLatencyPercentiles.compute(from: [420, 40, 50, 45, 55, 60, 48, 52, 46, 51])
        XCTAssertEqual(p.count, 10)
        XCTAssertEqual(p.minMs, 40)
        XCTAssertEqual(p.maxMs, 420)
        XCTAssertEqual(p.p50Ms, 50)
        XCTAssertEqual(p.p95Ms, 420)

        let emptyP = WuMindLatencyPercentiles.compute(from: [])
        XCTAssertEqual(emptyP.count, 0)
        XCTAssertEqual(emptyP.p50Ms, 0)

        // CallTrace exact fidelity check
        var trace = WuMindCallTraceRecord(
            clientRequestID: "req-1",
            selectedChannel: "WuMind 内置",
            selectedProvider: "openAI",
            selectedModelID: "gpt-5",
            requestedDeepThinking: true,
            attachedImageCount: 1,
            requestedWebSearch: false,
            actualModelID: "gpt-5",
            upstreamRoute: "official",
            host: "api.wumind.test",
            endpointPath: "/v1/chat/completions",
            thinkingParamSent: "reasoning_effort=high",
            imagesSentCount: 1
        )
        trace.succeeded = true
        XCTAssertFalse(trace.isFidelityExact, "Dispatch alone is not upstream verification")
        trace.providerReportedModelID = "gpt-4o"
        XCTAssertFalse(trace.isFidelityExact, "A discrepant upstream-reported ID cannot pass")
        trace.providerReportedModelID = "gpt-5"
        XCTAssertFalse(trace.isFidelityExact, "Sending a thinking parameter is not response evidence")
        trace.reasoningObserved = true
        XCTAssertTrue(trace.isFidelityExact)
        trace.providerModelConflict = true
        XCTAssertFalse(trace.isFidelityExact, "An inconsistent stream cannot pass")
        trace.providerModelConflict = nil
        trace.imagesSentCount = 0
        XCTAssertFalse(trace.isFidelityExact, "Dropping an image must flag isFidelityExact = false")
        trace.imagesSentCount = 1
        trace.actualModelID = "gpt-4o"
        XCTAssertFalse(trace.isFidelityExact, "Silently swapping models must flag isFidelityExact = false")
    }
    func testStreamingModelIdentityIsReadFromProviderMetadataOnly() {
        XCTAssertEqual(MultiProviderAIClient.reportedModelFromSSELine(provider: .openAI, line: #"data: {"model":"gpt-4o","choices":[]}"#), "gpt-4o")
        XCTAssertEqual(MultiProviderAIClient.reportedModelFromSSELine(provider: .gemini, line: #"data: {"modelVersion":"gemini-2.5-pro"}"#), "gemini-2.5-pro")
        XCTAssertEqual(MultiProviderAIClient.reportedModelFromSSELine(provider: .claude, line: #"data: {"message":{"model":"claude-sonnet-4-20250514"}}"#), "claude-sonnet-4-20250514")
        XCTAssertNil(MultiProviderAIClient.reportedModelFromSSELine(provider: .grok, line: #"data: {"choices":[{"delta":{"content":"grok-4"}}]}"#))
    }

}
