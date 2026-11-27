import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class AIImageDualRouteTests: XCTestCase {
    private static let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4H5EGAAQXAb41vZwdAAAAAElFTkSuQmCC"
    private static let pngData = Data(base64Encoded: png)!

    private static func reply(_ request: URLRequest, _ json: String, status: Int = 200) -> (Data, URLResponse) {
        let resp = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(json.utf8), resp)
    }

    private static func rawReply(_ request: URLRequest, _ data: Data, mime: String = "image/png", status: Int = 200) -> (Data, URLResponse) {
        let resp = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": mime]
        )!
        return (data, resp)
    }

    private static func nanoBananaModel() -> AIImageTool.Model {
        AIImageTool.models.first { $0.id == "gemini-3.1-flash-image" }!
    }

    private static func gptImage15Model() -> AIImageTool.Model {
        AIImageTool.models.first { $0.id == "gpt-image-1.5" }!
    }

    private static func gptImage2Model() -> AIImageTool.Model {
        AIImageTool.models.first { $0.id == "gpt-image-2" }!
    }

    // MARK: - Path 1: WuMind 内置 (Managed Gateway) Availability & Non-Fallback Guarantees

    func testManagedModeNeverChecksLocalKeysAndMarksUnenabledAsManagedModelNotEnabled() {
        let enabledGPT2 = WuMindCatalogModel(
            id: "gpt-image-2",
            upstreamProvider: "aihubmix",
            vendor: "OpenAI",
            displayName: "GPT Image 2",
            capabilities: ["text_to_image", "image_edit"],
            pricingMode: "per_image",
            unitPriceYuan: 0.435,
            supportsReferenceImage: true,
            enabled: true,
            probeStatus: "verified"
        )

        // Zero local vendor keys configured; Managed Gateway enabled GPT Image 2 but NOT Nano Banana 2
        let snapshot = AIImageCredentialSnapshot(
            useManagedGateway: true,
            isGatewayConfigured: true,
            isGatewayLoggedIn: true,
            isGatewayCatalogSyncing: false,
            enabledManagedImageModels: [enabledGPT2],
            ownPreference: .auto,
            aihubmixConnection: nil,
            directProviderKeys: [],
            directProviderBaseURLs: [:]
        )

        let gptEval = AIImageStudioAvailability.evaluate(model: Self.gptImage2Model(), hasReferenceImage: false, snapshot: snapshot)
        XCTAssertTrue(gptEval.isReady)
        XCTAssertEqual(gptEval.routeKind, .managedGateway)
        XCTAssertEqual(gptEval.routeBadge, "WuMind 内置")
        XCTAssertEqual(gptEval.modelCenterPillTitle, "进入画室")

        let nbEval = AIImageStudioAvailability.evaluate(model: Self.nanoBananaModel(), hasReferenceImage: false, snapshot: snapshot)
        XCTAssertFalse(nbEval.isReady)
        XCTAssertEqual(nbEval.routeKind, .managedGateway)
        XCTAssertEqual(nbEval.modelCenterPillTitle, "内置暂未开通")
        if case .managedModelNotEnabled(let id, _, let hasOther) = nbEval {
            XCTAssertEqual(id, "gemini-3.1-flash-image")
            XCTAssertTrue(hasOther)
        } else {
            XCTFail("Expected .managedModelNotEnabled, got \(nbEval)")
        }
        // Must NEVER prompt for Google Gemini API Key in Managed mode!
        XCTAssertFalse((nbEval.bannerTitle ?? "").contains("Google"))
        XCTAssertFalse((nbEval.bannerTitle ?? "").contains("API Key"))

        // Even when an AIHubMix key IS saved locally, Managed Mode MUST NOT silently switch to Own API!
        let managedWithLocalKey = AIImageCredentialSnapshot(
            useManagedGateway: true,
            isGatewayConfigured: true,
            isGatewayLoggedIn: true,
            isGatewayCatalogSyncing: false,
            enabledManagedImageModels: [enabledGPT2],
            ownPreference: .auto,
            aihubmixConnection: AIImageAIHubMixConnection(apiKey: "sk-local", baseURL: "https://aihubmix.com/v1", sourceSlot: .reusedOpenAISlot),
            directProviderKeys: [.openAI, .gemini],
            directProviderBaseURLs: [.openAI: "https://aihubmix.com/v1"]
        )
        let stillManaged = AIImageStudioAvailability.evaluate(model: Self.nanoBananaModel(), hasReferenceImage: false, snapshot: managedWithLocalKey)
        XCTAssertEqual(stillManaged.routeKind, .managedGateway)
        XCTAssertEqual(stillManaged.modelCenterPillTitle, "内置暂未开通")
        XCTAssertNil(AIImageStudioAvailability.resolveOwnExecutionTarget(model: Self.nanoBananaModel(), snapshot: managedWithLocalKey) { _ in "sk-local" })
    }

    func testManagedModeEnablesNanoBanana2WithoutLocalGeminiKey() {
        let enabledNB2 = WuMindCatalogModel(
            id: "gemini-3.1-flash-image",
            upstreamProvider: "aihubmix",
            vendor: "Google",
            displayName: "Nano Banana 2",
            capabilities: ["text_to_image", "image_edit"],
            pricingMode: "per_image",
            unitPriceYuan: 0.7286,
            supportsReferenceImage: true,
            enabled: true,
            probeStatus: "verified"
        )
        let snapshot = AIImageCredentialSnapshot(
            useManagedGateway: true,
            isGatewayConfigured: true,
            isGatewayLoggedIn: true,
            enabledManagedImageModels: [enabledNB2],
            aihubmixConnection: nil,
            directProviderKeys: []
        )

        let evalT2I = AIImageStudioAvailability.evaluate(model: Self.nanoBananaModel(), hasReferenceImage: false, snapshot: snapshot)
        XCTAssertTrue(evalT2I.isReady)
        XCTAssertEqual(evalT2I.routeBadge, "WuMind 内置")

        let evalEdit = AIImageStudioAvailability.evaluate(model: Self.nanoBananaModel(), hasReferenceImage: true, snapshot: snapshot)
        XCTAssertTrue(evalEdit.isReady)
    }

    // MARK: - Path 2: Decoupled Own API · AIHubMix Connection Reuse & Domain Isolation

    func testSavedAIHubMixInGPTSlotUnlocksBothGPTImageAndNanoBanana2WithoutGeminiKey() {
        let resolved = AIImageAIHubMixConnection.resolve(
            dedicatedKey: nil,
            dedicatedBaseURL: nil,
            openAIKey: "sk-aihubmix-gpt-slot",
            openAIBaseURL: "https://aihubmix.com/v1"
        )
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.sourceSlot, .reusedOpenAISlot)
        XCTAssertEqual(resolved?.resolvedHost, "aihubmix.com")
        XCTAssertTrue(resolved?.isSafeAggregatorHost == true)

        // Notice: ONLY .openAI key exists — ZERO .gemini key!
        let snapshot = AIImageCredentialSnapshot(
            useManagedGateway: false,
            isGatewayConfigured: false,
            isGatewayLoggedIn: false,
            enabledManagedImageModels: [],
            ownPreference: .auto,
            aihubmixConnection: resolved,
            directProviderKeys: [.openAI],
            directProviderBaseURLs: [.openAI: "https://aihubmix.com/v1"]
        )

        let gptEval = AIImageStudioAvailability.evaluate(model: Self.gptImage15Model(), hasReferenceImage: false, snapshot: snapshot)
        XCTAssertTrue(gptEval.isReady)
        XCTAssertEqual(gptEval.routeKind, .ownAIHubMix)
        XCTAssertEqual(gptEval.routeBadge, "自有 API · AIHubMix")

        let nbEval = AIImageStudioAvailability.evaluate(model: Self.nanoBananaModel(), hasReferenceImage: true, snapshot: snapshot)
        XCTAssertTrue(nbEval.isReady)
        XCTAssertEqual(nbEval.routeKind, .ownAIHubMix)
        XCTAssertEqual(nbEval.routeBadge, "自有 API · AIHubMix")
        XCTAssertEqual(nbEval.modelCenterPillTitle, "进入画室")

        let nbTarget = AIImageStudioAvailability.resolveOwnExecutionTarget(
            model: Self.nanoBananaModel(),
            snapshot: snapshot,
            directAPIKeyProvider: { $0 == .openAI ? "sk-aihubmix-gpt-slot" : nil }
        )
        XCTAssertEqual(nbTarget?.apiKey, "sk-aihubmix-gpt-slot")
        XCTAssertEqual(nbTarget?.baseURL, "https://aihubmix.com/v1")
        XCTAssertEqual(nbTarget?.requireAggregatorHost, true)
    }

    func testOfficialOpenAIKeyIsNeverReusedAsAIHubMixOrSentToGoogle() async {
        // Official OpenAI key (nil or api.openai.com baseURL) MUST NOT resolve as AIHubMix!
        XCTAssertNil(
            AIImageAIHubMixConnection.resolve(
                dedicatedKey: nil,
                dedicatedBaseURL: nil,
                openAIKey: "sk-official-openai",
                openAIBaseURL: nil
            )
        )
        XCTAssertNil(
            AIImageAIHubMixConnection.resolve(
                dedicatedKey: nil,
                dedicatedBaseURL: nil,
                openAIKey: "sk-official-openai",
                openAIBaseURL: "https://api.openai.com/v1"
            )
        )
        // Dedicated AIHubMix key pointing to official Google/OpenAI domain MUST be rejected!
        XCTAssertNil(
            AIImageAIHubMixConnection.resolve(
                dedicatedKey: "sk-aihubmix-key",
                dedicatedBaseURL: "https://generativelanguage.googleapis.com",
                openAIKey: nil,
                openAIBaseURL: nil
            )
        )

        // Even if someone forcibly constructs Options(requireAggregatorHost: true) with official host, AIImageTool blocks before network!
        let tool = AIImageTool { _ in
            XCTFail("Domain isolation MUST block request before hitting transport!")
            return Self.reply(URLRequest(url: URL(string: "https://example.com")!), "{}")
        }
        for forbiddenURL in [nil, "https://api.openai.com/v1", "https://generativelanguage.googleapis.com"] {
            do {
                _ = try await tool.generate(
                    model: Self.nanoBananaModel(),
                    apiKey: "sk-aihubmix-secret",
                    prompt: "domain isolation check",
                    referenceImage: nil,
                    options: AIImageTool.Options(quality: .fast, aspectRatio: .square, outputFormat: .png, customBaseURL: forbiddenURL, requireAggregatorHost: true)
                )
                XCTFail("Expected domainIsolationBlocked for \(forbiddenURL ?? "nil")")
            } catch let err as AIImageToolError {
                XCTAssertEqual(err, .domainIsolationBlocked)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    // MARK: - AIHubMix Exact Wire Protocols (Nano Banana 2 + GPT Image 1.5, T2I + Ref Edit + Unified Fallback)

    func testAIHubMixNanoBanana2UsesGeminiNativeGenerateContentForT2IAndReferenceEdit() async throws {
        let model = Self.nanoBananaModel()
        let options = AIImageTool.Options(
            quality: .hd,
            aspectRatio: .landscape,
            outputFormat: .png,
            customBaseURL: "https://aihubmix.com/v1",
            requireAggregatorHost: true
        )

        // 1. Text-to-Image
        let t2iTool = AIImageTool { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://aihubmix.com/gemini/v1beta/models/gemini-3.1-flash-image:generateContent"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "sk-aihubmix-key")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let genCfg = json["generationConfig"] as! [String: Any]
            XCTAssertEqual(genCfg["responseModalities"] as? [String], ["TEXT", "IMAGE"])
            let imgCfg = genCfg["imageConfig"] as! [String: Any]
            XCTAssertEqual(imgCfg["aspectRatio"] as? String, "3:2")
            XCTAssertEqual(imgCfg["imageSize"] as? String, "2K")
            return Self.reply(request, """
            {"candidates":[{"content":{"parts":[
              {"thought":true,"inlineData":{"mimeType":"image/png","data":"BAD"}},
              {"inline_data":{"mime_type":"image/png","data":"\(Self.png)"}}
            ]}}]}
            """)
        }
        let t2iRes = try await t2iTool.generateWithDiagnostics(
            model: model,
            apiKey: "sk-aihubmix-key",
            prompt: "origami crane",
            referenceImage: nil,
            options: options
        )
        XCTAssertEqual(t2iRes.data, Self.pngData)
        XCTAssertTrue(t2iRes.endpointDisplay.contains("aihubmix.com/gemini/v1beta/models/gemini-3.1-flash-image:generateContent"))

        // 2. Reference-Image Edit (inline_data + text)
        let ref = AIImageTool.ReferenceImage(data: Self.pngData, mimeType: "image/png", filename: "ref.png")
        let editTool = AIImageTool { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://aihubmix.com/gemini/v1beta/models/gemini-3.1-flash-image:generateContent"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "sk-aihubmix-key")
            let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let contents = json["contents"] as! [[String: Any]]
            let parts = contents[0]["parts"] as! [[String: Any]]
            let inline = parts[0]["inline_data"] as! [String: Any]
            XCTAssertEqual(inline["mime_type"] as? String, "image/png")
            XCTAssertEqual(inline["data"] as? String, Self.png)
            XCTAssertEqual(parts[1]["text"] as? String, "warm sunset rim light")
            return Self.reply(request, """
            {"candidates":[{"content":{"parts":[
              {"inlineData":{"mimeType":"image/png","data":"\(Self.png)"}}
            ]}}]}
            """)
        }
        let editData = try await editTool.generate(
            model: model,
            apiKey: "sk-aihubmix-key",
            prompt: "warm sunset rim light",
            referenceImage: ref,
            options: options
        )
        XCTAssertEqual(editData, Self.pngData)
    }

    func testAIHubMixUnifiedFallbackDownloadsSameOriginContentURLAndBlocksSSRF() async throws {
        let model = Self.nanoBananaModel()
        let options = AIImageTool.Options(
            quality: .balanced,
            aspectRatio: .square,
            outputFormat: .png,
            customBaseURL: "https://aihubmix.com/v1",
            requireAggregatorHost: true
        )

        // Same-origin content_url succeeds
        let okTool = AIImageTool { request in
            let url = request.url!.absoluteString
            if url.hasSuffix(":generateContent") {
                return Self.reply(request, #"{"error":{"code":"protocol_not_supported","message":"Use /ai/v1/images/generations"}}"#, status: 400)
            }
            if url == "https://aihubmix.com/ai/v1/images/generations" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-aihubmix-key")
                return Self.reply(request, """
                {"id":"img_1","status":"completed","output":[{"content_url":"https://aihubmix.com/ai/v1/files/img_1/content","content_type":"image/png"}]}
                """)
            }
            if url == "https://aihubmix.com/ai/v1/files/img_1/content" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-aihubmix-key")
                return Self.rawReply(request, Self.pngData, mime: "image/png")
            }
            XCTFail("Unexpected URL: \(url)")
            return Self.reply(request, "{}", status: 500)
        }
        let res = try await okTool.generateWithDiagnostics(
            model: model,
            apiKey: "sk-aihubmix-key",
            prompt: "unified test",
            referenceImage: nil,
            options: options
        )
        XCTAssertEqual(res.data, Self.pngData)
        XCTAssertTrue(res.endpointDisplay.contains("/ai/v1/images/generations"))

        // Off-origin SSRF content_url MUST be rejected BEFORE making GET request!
        let ssrfTool = AIImageTool { request in
            let url = request.url!.absoluteString
            if url.hasSuffix(":generateContent") {
                return Self.reply(request, #"{"error":{"code":"protocol_not_supported"}}"#, status: 400)
            }
            if url == "https://aihubmix.com/ai/v1/images/generations" {
                return Self.reply(request, """
                {"id":"img_2","status":"completed","output":[{"content_url":"https://evil.example.com/steal.png","content_type":"image/png"}]}
                """)
            }
            XCTFail("SSRF URL must NEVER reach transport: \(url)")
            return Self.reply(request, "{}", status: 500)
        }
        do {
            _ = try await ssrfTool.generate(model: model, apiKey: "sk-aihubmix-key", prompt: "ssrf test", referenceImage: nil, options: options)
            XCTFail("Expected invalidRequest for off-origin content_url")
        } catch let err as MultiProviderAIError {
            XCTAssertEqual(err, .invalidRequest)
        }
    }

    func testAIHubMixGPTImage15UsesOpenAIImagesAndMultipartEdits() async throws {
        let model = Self.gptImage15Model()
        let options = AIImageTool.Options(
            quality: .balanced,
            aspectRatio: .square,
            outputFormat: .png,
            customBaseURL: "https://aihubmix.com/v1",
            requireAggregatorHost: true
        )

        // T2I
        let t2iTool = AIImageTool { request in
            XCTAssertEqual(request.url?.absoluteString, "https://aihubmix.com/v1/images/generations")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-aihubmix-key")
            return Self.reply(request, #"{"data":[{"b64_json":"\#(Self.png)"}]}"#)
        }
        let img1 = try await t2iTool.generate(model: model, apiKey: "sk-aihubmix-key", prompt: "wooden chair", referenceImage: nil, options: options)
        XCTAssertEqual(img1, Self.pngData)

        // Reference-Image Edit (multipart)
        let ref = AIImageTool.ReferenceImage(data: Self.pngData, mimeType: "image/png", filename: "ref.png")
        let editTool = AIImageTool { request in
            XCTAssertEqual(request.url?.absoluteString, "https://aihubmix.com/v1/images/edits")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-aihubmix-key")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
            return Self.reply(request, #"{"data":[{"b64_json":"\#(Self.png)"}]}"#)
        }
        let img2 = try await editTool.generate(model: model, apiKey: "sk-aihubmix-key", prompt: "make it emerald green", referenceImage: ref, options: options)
        XCTAssertEqual(img2, Self.pngData)
    }

    // MARK: - 5-Class Error Classification & Sanitized Diagnostic Redaction

    func testErrorClassifierAndSanitizedDiagnosticsRedaction() {
        XCTAssertEqual(
            AIImageErrorClassifier.classify(error: WuMindGatewayClient.GatewayError.insufficientBalance, route: .managedGateway).category,
            .insufficientWuMindBalance
        )
        XCTAssertEqual(
            AIImageErrorClassifier.classify(error: WuMindGatewayClient.GatewayError.upstreamBalanceInsufficient("上游余额不足"), route: .managedGateway).category,
            .insufficientUpstreamBalance
        )
        XCTAssertEqual(
            AIImageErrorClassifier.classify(error: WuMindGatewayClient.GatewayError.modelNotEnabled("未开通"), route: .managedGateway).category,
            .modelNotEnabled
        )
        XCTAssertEqual(
            AIImageErrorClassifier.classify(error: WuMindGatewayClient.GatewayError.upstreamAuthFailed("上游 401"), route: .managedGateway).category,
            .authFailed
        )
        let netClassified = AIImageErrorClassifier.classify(error: WuMindGatewayClient.GatewayError.network, route: .managedGateway)
        XCTAssertEqual(netClassified.category, .networkTimeout)
        XCTAssertTrue(netClassified.isRetryableWithSameIdempotencyKey)

        // Verify sanitized diagnostics NEVER retain API keys or query strings
        let diag = AIImageRequestDiagnostic.sanitized(
            requestID: "REQ-12345",
            route: .ownAIHubMix,
            modelID: "gemini-3.1-flash-image",
            mode: "text_to_image",
            endpointDisplay: "https://aihubmix.com/gemini/v1beta/models/gemini-3.1-flash-image:generateContent?key=sk-secret1234567890",
            httpStatus: 200,
            errorCategory: nil,
            billingResult: "AIHubMix 计费（sk-secret1234567890）",
            idempotencyKey: "img-abcdef1234567890999",
            succeeded: true
        )
        XCTAssertFalse(diag.endpointDisplay.contains("sk-secret1234567890"))
        XCTAssertFalse(diag.endpointDisplay.contains("?key="))
        XCTAssertFalse(diag.billingResult.contains("sk-secret1234567890"))
        XCTAssertEqual(diag.idempotencyKeyPrefix, "img-abcdef123456")
    }

    // MARK: - Explicit Regression Tests ①, ②, ③

    /// ① 选了「WuMind 内置」但网关地址无效时，明确提示网关配置问题，不得跳到「配置 Gemini Key」。
    func testRegression1_ManagedModeInvalidGatewayURLShowsGatewayConfigErrorNeverGeminiKey() {
        for invalidGatewayURL in ["", "   ", "http://insecure.example.com", "not-a-url"] {
            let isConfigured = (try? WuMindGatewayClient.normalizedGatewayURL(invalidGatewayURL)) != nil
            XCTAssertFalse(isConfigured, "Expected \(invalidGatewayURL) to be invalid gateway URL")

            let snapshot = AIImageCredentialSnapshot(
                useManagedGateway: true,
                isGatewayConfigured: isConfigured,
                isGatewayLoggedIn: true,
                isGatewayCatalogSyncing: false,
                enabledManagedImageModels: [],
                ownPreference: .auto,
                aihubmixConnection: nil,
                directProviderKeys: [],
                directProviderBaseURLs: [:]
            )

            let eval = AIImageStudioAvailability.evaluate(
                model: Self.nanoBananaModel(),
                hasReferenceImage: false,
                snapshot: snapshot
            )
            XCTAssertFalse(eval.isReady)
            XCTAssertEqual(eval.routeKind, .managedGateway)
            XCTAssertEqual(eval.routeBadge, "WuMind 内置")
            XCTAssertEqual(eval.modelCenterPillTitle, "网关配置无效")
            if case .managedGatewayConfigInvalid(let detail) = eval {
                XCTAssertTrue(detail.contains("管理员"), "Gateway configuration requires administrator action")
            } else {
                XCTFail("Expected .managedGatewayConfigInvalid, got \(eval)")
            }
            let title = eval.bannerTitle ?? ""
            XCTAssertTrue(title.contains("网关"), "Banner title must point to gateway config, got: \(title)")
            XCTAssertFalse(title.contains("Gemini Key"))
            XCTAssertFalse(title.contains("Google"))
            // Must NEVER produce an Own-API target or redirect to Gemini Key configuration
            XCTAssertNil(
                AIImageStudioAvailability.resolveOwnExecutionTarget(
                    model: Self.nanoBananaModel(),
                    snapshot: snapshot,
                    directAPIKeyProvider: { _ in nil }
                )
            )
        }
    }

    /// ② 选定 Nano Banana 2 但内置目录没有这款时，显示该模型不可用，不得悄悄换成列表第一个模型。
    func testRegression2_SelectedNanoBanana2MissingFromManagedCatalogStaysUnavailableNeverSwapsToFirstModel() {
        let firstModel = WuMindCatalogModel(
            id: "gpt-image-2",
            upstreamProvider: "aihubmix",
            vendor: "OpenAI",
            displayName: "GPT Image 2",
            capabilities: ["text_to_image", "image_edit"],
            pricingMode: "per_image",
            unitPriceYuan: 0.435,
            supportsReferenceImage: true,
            enabled: true,
            probeStatus: "verified"
        )
        let secondModel = WuMindCatalogModel(
            id: "gpt-image-1.5",
            upstreamProvider: "aihubmix",
            vendor: "OpenAI",
            displayName: "GPT Image 1.5",
            capabilities: ["text_to_image", "image_edit"],
            pricingMode: "per_image",
            unitPriceYuan: 0.435,
            supportsReferenceImage: true,
            enabled: true,
            probeStatus: "verified"
        )
        let managedCatalog = [firstModel, secondModel]

        // Case A: requestedModelID is explicitly "gemini-3.1-flash-image"
        let resExplicit = AIImageStudioAvailability.resolveManagedSelection(
            requestedModelID: "gemini-3.1-flash-image",
            fallbackModel: Self.gptImage2Model(),
            enabledManagedImageModels: managedCatalog
        )
        XCTAssertNil(resExplicit.catalogModel, "Missing Nano Banana 2 MUST NOT silently resolve to list.first (gpt-image-2)!")
        XCTAssertEqual(resExplicit.displayModel.id, "gemini-3.1-flash-image")
        XCTAssertEqual(resExplicit.displayModel.shortStudioName, "Nano Banana 2")

        // Case B: requestedModelID is empty, but fallbackModel (current studio selection) is Nano Banana 2
        let resFallback = AIImageStudioAvailability.resolveManagedSelection(
            requestedModelID: "",
            fallbackModel: Self.nanoBananaModel(),
            enabledManagedImageModels: managedCatalog
        )
        XCTAssertNil(resFallback.catalogModel, "Fallback selection Nano Banana 2 MUST NOT silently swap to list.first (gpt-image-2)!")
        XCTAssertEqual(resFallback.displayModel.id, "gemini-3.1-flash-image")

        // Evaluating this selection MUST report Nano Banana 2 unavailable (never ready with gpt-image-2!)
        let snapshot = AIImageCredentialSnapshot(
            useManagedGateway: true,
            isGatewayConfigured: true,
            isGatewayLoggedIn: true,
            enabledManagedImageModels: managedCatalog,
            aihubmixConnection: nil,
            directProviderKeys: []
        )
        let eval = AIImageStudioAvailability.evaluate(
            model: resExplicit.displayModel,
            hasReferenceImage: false,
            snapshot: snapshot
        )
        XCTAssertFalse(eval.isReady)
        if case .managedModelNotEnabled(let id, let name, let hasOther) = eval {
            XCTAssertEqual(id, "gemini-3.1-flash-image")
            XCTAssertEqual(name, "Nano Banana 2")
            XCTAssertTrue(hasOther)
        } else {
            XCTFail("Expected .managedModelNotEnabled for Nano Banana 2, got \(eval)")
        }
    }

    /// ③ 文生图和参考图编辑分别验收，只有拿到能解码、能显示的图片才算各自通过（HTTP 200 无图/坏图一律拒绝）。
    func testRegression3_T2IAndReferenceEditIndependentlyRequireDecodableDisplayableImage() async throws {
        let model = Self.nanoBananaModel()
        let options = AIImageTool.Options(
            quality: .balanced,
            aspectRatio: .square,
            outputFormat: .png,
            customBaseURL: "https://aihubmix.com/v1",
            requireAggregatorHost: true
        )
        let ref = AIImageTool.ReferenceImage(data: Self.pngData, mimeType: "image/png", filename: "ref.png")
        let corruptBase64 = Data("not-an-image-bytes".utf8).base64EncodedString()
        let truncatedPNG = Self.pngData.dropLast(6).base64EncodedString()

        // 1. T2I returns HTTP 200 with text only (no image) -> MUST fail with .noImage!
        let t2iTextOnly = AIImageTool { req in
            Self.reply(req, #"{"candidates":[{"content":{"parts":[{"text":"cannot render"}]}}]}"#, status: 200)
        }
        do {
            _ = try await t2iTextOnly.generate(model: model, apiKey: "sk-aihubmix-key", prompt: "t2i text only", referenceImage: nil, options: options)
            XCTFail("HTTP 200 text-only T2I must not pass")
        } catch let err as AIImageToolError {
            XCTAssertEqual(err, .noImage)
        }

        // 2. T2I returns HTTP 200 with corrupt / truncated base64 -> MUST fail with .invalidImage!
        for badB64 in [corruptBase64, truncatedPNG] {
            let badTool = AIImageTool { req in
                Self.reply(req, #"{"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"\#(badB64)"}}]}}]}"#, status: 200)
            }
            do {
                _ = try await badTool.generate(model: model, apiKey: "sk-aihubmix-key", prompt: "t2i corrupt", referenceImage: nil, options: options)
                XCTFail("HTTP 200 undecodable T2I must not pass")
            } catch let err as AIImageToolError {
                XCTAssertEqual(err, .invalidImage)
            }
        }

        // 3. Reference-Image Edit returns HTTP 200 with corrupt / truncated base64 -> MUST fail with .invalidImage!
        for badB64 in [corruptBase64, truncatedPNG] {
            let badEditTool = AIImageTool { req in
                Self.reply(req, #"{"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"\#(badB64)"}}]}}]}"#, status: 200)
            }
            do {
                _ = try await badEditTool.generate(model: model, apiKey: "sk-aihubmix-key", prompt: "edit corrupt", referenceImage: ref, options: options)
                XCTFail("HTTP 200 undecodable Reference Edit must not pass")
            } catch let err as AIImageToolError {
                XCTAssertEqual(err, .invalidImage)
            }
        }

        // 4. Managed catalog capability isolation: if ONLY image_edit passed probe (`capabilities == ["image_edit"]`),
        //    T2I MUST evaluate as unavailable while Reference-Image Edit evaluates as ready!
        let editOnlyManaged = WuMindCatalogModel(
            id: "gemini-3.1-flash-image",
            upstreamProvider: "aihubmix",
            vendor: "Google",
            displayName: "Nano Banana 2",
            capabilities: ["image_edit"],
            pricingMode: "per_image",
            unitPriceYuan: 0.7286,
            supportsReferenceImage: true,
            enabled: true,
            probeStatus: "verified"
        )
        let partialSnap = AIImageCredentialSnapshot(
            useManagedGateway: true,
            isGatewayConfigured: true,
            isGatewayLoggedIn: true,
            enabledManagedImageModels: [editOnlyManaged],
            aihubmixConnection: nil,
            directProviderKeys: []
        )
        let t2iEval = AIImageStudioAvailability.evaluate(model: model, hasReferenceImage: false, snapshot: partialSnap)
        let editEval = AIImageStudioAvailability.evaluate(model: model, hasReferenceImage: true, snapshot: partialSnap)
        XCTAssertFalse(t2iEval.isReady, "Unverified T2I MUST NOT be marked ready when only image_edit passed!")
        XCTAssertTrue(editEval.isReady, "Verified image_edit SHOULD be ready when reference image is attached!")
    }
}
