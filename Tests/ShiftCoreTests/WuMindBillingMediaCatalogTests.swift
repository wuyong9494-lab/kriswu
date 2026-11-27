import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class WuMindBillingMediaCatalogTests: XCTestCase {
    private static let samplePNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4H5EGAAQXAb41vZwdAAAAAElFTkSuQmCC")!

    // Minimal valid ISO BMFF MP4 header (`ftypisom`) > 2048 bytes for video download validation.
    private static func sampleMP4Data() -> Data {
        var data = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D, 0x00, 0x00, 0x02, 0x00, 0x69, 0x73, 0x6F, 0x6D, 0x69, 0x73, 0x6F, 0x32])
        data.append(Data(repeating: 0x00, count: 4096))
        return data
    }

    private static func httpReply(_ request: URLRequest, body: String, status: Int = 200, contentType: String = "application/json") -> (Data, URLResponse) {
        let resp = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        )!
        return (Data(body.utf8), resp)
    }

    // MARK: - 1. StoreKit 2 Deterministic Account UUID Bit-For-Bit Parity with Cloudflare Gateway

    func testAccountUUIDMatchesGatewayBitForBit() {
        XCTAssertEqual(
            WuMindGatewayClient.accountUUID(for: "WM-123456").uuidString.lowercased(),
            "f18c386f-af5f-5f63-955e-5673c67c4260"
        )
        XCTAssertEqual(
            WuMindGatewayClient.accountUUID(for: " wm-123456 ").uuidString.lowercased(),
            "f18c386f-af5f-5f63-955e-5673c67c4260"
        )
        XCTAssertEqual(
            WuMindGatewayClient.accountUUID(for: "wm-999001").uuidString.lowercased(),
            "734f04fa-fed7-517a-b4a6-d898f5cae881"
        )
    }

    // MARK: - 2. Dynamic Model Catalog (Discover · Probe · Pricing/Enable Guardrails · Public Filter)

    func testGatewayDynamicCatalogDiscoverProbeAndGuardrails() async throws {
        let client = WuMindGatewayClient(
            dataTransport: { req in
                let path = req.url?.path ?? ""
                if path == "/v1/public/models" {
                    XCTAssertEqual(req.url?.query, "capability=image_edit")
                    return Self.httpReply(req, body: """
                    {"ok":true,"models":[{"id":"gpt-image-1","upstreamProvider":"aihubmix","displayName":"GPT Image 1","capabilities":["text_to_image","image_edit"],"pricingMode":"per_image","inputPricePerMillion":0,"outputPricePerMillion":0,"unitPriceYuan":0.3,"supportsReferenceImage":true,"enabled":true,"probeStatus":"verified"}]}
                    """)
                }
                XCTAssertEqual(req.value(forHTTPHeaderField: "X-WuMind-Admin-Secret"), "adm-sec")
                if path == "/v1/admin/models/discover" {
                    return Self.httpReply(req, body: """
                    {"ok":true,"totalDiscovered":2,"totalDeprecated":0,"providerReports":[{"provider":"aihubmix","configured":true,"discovered":2,"note":"live"}],"models":[{"id":"sora-2","upstreamProvider":"aihubmix","displayName":"Sora 2","capabilities":["video"],"pricingMode":"per_second","inputPricePerMillion":0,"outputPricePerMillion":0,"unitPriceYuan":0,"enabled":false,"probeStatus":"unverified"}]}
                    """)
                }
                if path == "/v1/admin/models/probe" {
                    return Self.httpReply(req, body: """
                    {"ok":true,"results":[{"id":"sora-2","upstreamProvider":"aihubmix","displayName":"Sora 2","capabilities":["video"],"pricingMode":"per_second","inputPricePerMillion":0,"outputPricePerMillion":0,"unitPriceYuan":0,"enabled":false,"probeStatus":"verified","probeEndpoint":"/v1/videos","probeLatencyMs":210}]}
                    """)
                }
                if path == "/v1/admin/models/batch-update" {
                    return Self.httpReply(req, body: """
                    {"ok":true,"appliedCount":1,"rejectedCount":1,"applied":[{"id":"sora-2","upstreamProvider":"aihubmix","displayName":"Sora 2","capabilities":["video"],"pricingMode":"per_second","inputPricePerMillion":0,"outputPricePerMillion":0,"unitPriceYuan":1.0,"supportedParams":{"seconds":["4","8","12"],"defaultSeconds":"4","sizes":["1280x720","720x1280"],"protocol":"aihubmix_videos"},"enabled":true,"probeStatus":"verified"}],"rejected":[{"id":"untested-model","code":"model_not_verified","reason":"模型尚未通过实测校验"}]}
                    """)
                }
                return Self.httpReply(req, body: #"{"error":"not_found"}"#, status: 404)
            },
            streamTransport: { _, _, _ in fatalError("Not expected") }
        )

        let editModels = try await client.fetchPublicModels(gatewayURL: "https://gw.example.com", capability: "image_edit")
        XCTAssertEqual(editModels.count, 1)
        XCTAssertTrue(editModels[0].isCallable)
        XCTAssertTrue(editModels[0].supportsImageEdit)

        let disc = try await client.adminDiscoverModels(gatewayURL: "https://gw.example.com", adminSecret: "adm-sec")
        XCTAssertEqual(disc.totalDiscovered, 2)
        XCTAssertEqual(disc.models[0].enabled, false)
        XCTAssertEqual(disc.models[0].probeStatus, "unverified")

        let probed = try await client.adminProbeModels(gatewayURL: "https://gw.example.com", adminSecret: "adm-sec", modelIDs: ["sora-2"])
        XCTAssertTrue(probed.results[0].isVerified)

        let batch = try await client.adminBatchUpdateModels(
            gatewayURL: "https://gw.example.com",
            adminSecret: "adm-sec",
            updates: [
                .init(id: "sora-2", unitPriceYuan: 1.0, enabled: true),
                .init(id: "untested-model", unitPriceYuan: 1.0, enabled: true),
            ]
        )
        XCTAssertEqual(batch.appliedCount, 1)
        XCTAssertEqual(batch.applied.first?.supportedParams?.seconds, [4, 8, 12])
        XCTAssertEqual(batch.applied.first?.supportedParams?.defaultSeconds, 4)
        XCTAssertEqual(batch.rejectedCount, 1)
        XCTAssertEqual(batch.rejected.first?.code, "model_not_verified")
    }

    // MARK: - 3. Admin Registry, Fee-Waiver, AIHubMix Pool Balance (Sync Failure + Low Alert) & Distinct Upstream Balance Error

    func testAdminUsersFeeWaiverUpstreamBalanceAndDistinct503Mapping() async throws {
        let client = WuMindGatewayClient(
            dataTransport: { req in
                let path = req.url?.path ?? ""
                if path == "/v1/admin/users" {
                    return Self.httpReply(req, body: """
                    {"ok":true,"totalUsers":2,"rechargedUsersCount":1,"users":[
                      {"userID":"WM-000001","displayName":"吴庸","registeredRole":"internal_duty","balanceYuan":0,"totalRechargedYuan":0,"totalSpentYuan":0,"upstreamSpentYuan":1.85,"billingExempt":true,"dailyCostCapYuan":200,"requestCount":12,"totalTokens":14500},
                      {"userID":"WM-000002","displayName":"外部测试","registeredRole":"external","balanceYuan":18.5,"purchasedRechargedYuan":20,"adminGrantedYuan":0,"totalRechargedYuan":20,"totalSpentYuan":1.5,"billingExempt":false,"requestCount":4,"totalTokens":3200}
                    ]}
                    """)
                }
                if path == "/v1/admin/users/billing-exempt" {
                    return Self.httpReply(req, body: """
                    {"ok":true,"userID":"WM-000001","displayName":"吴庸","billingExempt":true,"dailyCostCapYuan":150,"balanceYuan":0,"upstreamSpentYuan":1.85}
                    """)
                }
                if path == "/v1/admin/upstream-balance/refresh" {
                    // Simulate sync failure: preserves cached $8.40 and NEVER resets to $0
                    return Self.httpReply(req, body: """
                    {"ok":true,"provider":"aihubmix","currency":"USD","configured":true,"availableUSD":8.4,"usedUSD":41.6,"syncedAt":"2026-11-25T10:00:00Z","syncFailed":true,"syncError":"HTTP 502","statusLabel":"上次余额 · 同步失败","lowBalanceAlertUSD":10.0,"alertTriggered":true,"topUpURL":"https://console.aihubmix.com/topup"}
                    """)
                }
                if path == "/v1/admin/upstream-balance/alert" {
                    return Self.httpReply(req, body: """
                    {"ok":true,"provider":"aihubmix","currency":"USD","configured":true,"availableUSD":8.4,"usedUSD":41.6,"syncedAt":"2026-11-25T10:00:00Z","syncFailed":false,"statusLabel":"账号共享余额","lowBalanceAlertUSD":25.0,"alertTriggered":true,"topUpURL":"https://console.aihubmix.com/topup"}
                    """)
                }
                return Self.httpReply(req, body: #"{"error":"upstream_balance_insufficient","message":"上游 API 余额不足，请管理员及时充值 AIHubMix"}"#, status: 503)
            },
            streamTransport: { _, _, _ in fatalError("Not expected") }
        )

        let directory = try await client.adminListUsers(gatewayURL: "https://gw.example.com", adminSecret: "adm-sec")
        XCTAssertEqual(directory.totalUsers, 2)
        XCTAssertEqual(directory.rechargedUsersCount, 1)
        XCTAssertTrue(directory.users[0].isBillingExempt)
        XCTAssertEqual(directory.users[0].balanceYuan, 0)
        XCTAssertEqual(directory.users[0].upstreamSpentYuan, 1.85)

        let exempt = try await client.adminSetUserBillingExempt(
            gatewayURL: "https://gw.example.com",
            adminSecret: "adm-sec",
            userID: "WM-000001",
            exempt: true,
            dailyCostCapYuan: 150
        )
        XCTAssertTrue(exempt.billingExempt)
        XCTAssertEqual(exempt.dailyCostCapYuan, 150)

        let failedRefresh = try await client.adminRefreshUpstreamBalance(gatewayURL: "https://gw.example.com", adminSecret: "adm-sec")
        XCTAssertTrue(failedRefresh.syncFailed)
        XCTAssertEqual(failedRefresh.availableUSD, 8.4)
        XCTAssertEqual(failedRefresh.statusLabel, "上次余额 · 同步失败")
        XCTAssertTrue(failedRefresh.alertTriggered)

        let updatedAlert = try await client.adminSetUpstreamAlertThreshold(
            gatewayURL: "https://gw.example.com",
            adminSecret: "adm-sec",
            lowBalanceAlertUSD: 25
        )
        XCTAssertEqual(updatedAlert.lowBalanceAlertUSD, 25)
        XCTAssertTrue(updatedAlert.alertTriggered)

        // Upstream pool insufficient MUST map to .upstreamBalanceInsufficient (NEVER .insufficientBalance!)
        let mapped = WuMindGatewayClient.mapHTTPError(
            statusCode: 503,
            data: Data(#"{"error":"upstream_balance_insufficient","message":"上游 API 余额不足"}"#.utf8)
        )
        XCTAssertEqual(mapped, .upstreamBalanceInsufficient("上游 API 余额不足"))
        XCTAssertNotEqual(mapped, .insufficientBalance)
    }

    // MARK: - 4. Managed Image Reference-Edit, Managed Video & Private My Works Versioning

    func testManagedMediaAndPrivateWorksVersioning() async throws {
        let mp4 = Self.sampleMP4Data()
        let client = WuMindGatewayClient(
            dataTransport: { req in
                let path = req.url?.path ?? ""
                XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer wm_live_tok")
                if path == "/v1/images/edits" {
                    XCTAssertEqual(req.value(forHTTPHeaderField: "Idempotency-Key"), "img-idem-1")
                    let json = try JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody)) as? [String: Any]
                    XCTAssertNotNil(json?["referenceImage"])
                    return Self.httpReply(req, body: """
                    {"ok":true,"workID":"WRK-IMG-1","model":"gpt-image-1","mode":"image_edit","endpoint":"/v1/images/edits","timing":{"gatewaySubmitMs":12,"upstreamGenerateMs":1450},"data":[{"b64_json":"\(Self.samplePNG.base64EncodedString())","mime_type":"image/png"}],"billing":{"promptTokens":0,"completionTokens":0,"reasoningTokens":0,"costYuan":0.3,"balanceYuan":19.7}}
                    """)
                }
                if path == "/v1/videos", req.httpMethod == "POST" {
                    return Self.httpReply(req, body: #"{"id":"vid_999","workID":"WRK-VID-1","model":"sora-2","status":"queued","progress":5,"seconds":"4","size":"1280x720"}"#)
                }
                if path == "/v1/videos/vid_999", req.httpMethod == "GET" {
                    return Self.httpReply(req, body: #"{"id":"vid_999","model":"sora-2","status":"completed","progress":100}"#)
                }
                if path == "/v1/videos/vid_999/content" {
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "video/mp4"])!
                    return (mp4, resp)
                }
                if path == "/v1/works", req.httpMethod == "POST" {
                    return Self.httpReply(req, body: #"{"ok":true,"work":{"id":"WRK-PPT-1","workType":"ppt","title":"Q3 汇报","prompt":"10 页汇报","modelID":"gpt-4o","status":"completed","progress":100,"versionNumber":1}}"#)
                }
                if path == "/v1/works/WRK-PPT-1", req.httpMethod == "PATCH" {
                    return Self.httpReply(req, body: #"{"ok":true,"versionCreated":true,"work":{"id":"WRK-PPT-2","workType":"ppt","title":"Q3 汇报 v2","prompt":"第5页改折线图","modelID":"gpt-4o","status":"completed","progress":100,"versionNumber":2,"parentWorkID":"WRK-PPT-1"}}"#)
                }
                return Self.httpReply(req, body: #"{"error":"unexpected"}"#, status: 404)
            },
            streamTransport: { _, _, _ in fatalError("Not expected") }
        )

        let ref = AIImageTool.ReferenceImage(data: Self.samplePNG, mimeType: "image/png", filename: "ref.png")
        let imgRes = try await client.generateManagedImages(
            gatewayURL: "https://gw.example.com",
            userToken: "wm_live_tok",
            modelID: "gpt-image-1",
            prompt: "保持构图换黄昏光影",
            referenceImage: ref,
            idempotencyKey: "img-idem-1"
        )
        XCTAssertEqual(imgRes.workID, "WRK-IMG-1")
        XCTAssertEqual(imgRes.mode, "image_edit")
        XCTAssertEqual(imgRes.timing?.upstreamGenerateMs, 1450)

        let job = try await client.submitManagedVideo(
            gatewayURL: "https://gw.example.com",
            userToken: "wm_live_tok",
            modelID: "sora-2",
            prompt: "海边日落航拍",
            seconds: 4,
            size: "1280x720"
        )
        XCTAssertEqual(job.id, "vid_999")
        let st = try await client.fetchManagedVideoStatus(gatewayURL: "https://gw.example.com", userToken: "wm_live_tok", jobID: job.id)
        XCTAssertTrue(st.isCompleted)
        let downloadedMP4 = try await client.downloadManagedVideoContent(gatewayURL: "https://gw.example.com", userToken: "wm_live_tok", jobID: job.id)
        XCTAssertEqual(downloadedMP4, mp4)

        let v1 = try await client.createWork(
            gatewayURL: "https://gw.example.com",
            userToken: "wm_live_tok",
            workType: .ppt,
            title: "Q3 汇报",
            prompt: "10 页汇报",
            modelID: "gpt-4o",
            status: "completed",
            progress: 100
        )
        XCTAssertEqual(v1.versionNumber, 1)
        let v2 = try await client.updateWork(
            gatewayURL: "https://gw.example.com",
            userToken: "wm_live_tok",
            workID: v1.id,
            title: "Q3 汇报 v2",
            createNewVersion: true
        )
        XCTAssertEqual(v2.versionNumber, 2)
        XCTAssertEqual(v2.parentWorkID, v1.id)
    }

    // MARK: - 5. AIImageTool Reference-Image Multipart Edit + Gemini Inline + T2I Explicit Refusal

    func testAIImageToolReferenceImageEditAndExplicitT2IRefusal() async throws {
        let ref = AIImageTool.ReferenceImage(data: Self.samplePNG, mimeType: "image/png", filename: "ref.png")

        // 5a. OpenAI / AIHubMix multipart/form-data POST /v1/images/edits
        let openAIModel = try XCTUnwrap(AIImageTool.models.first(where: { $0.provider == .openAI }))
        let editTool = AIImageTool { req in
            XCTAssertEqual(req.url?.absoluteString, "https://aihubmix.com/v1/images/edits")
            let ct = req.value(forHTTPHeaderField: "Content-Type") ?? ""
            XCTAssertTrue(ct.hasPrefix("multipart/form-data; boundary="))
            let bodyStr = String(decoding: req.httpBody ?? Data(), as: UTF8.self)
            XCTAssertTrue(bodyStr.contains("name=\"image\"; filename=\"ref.png\""))
            XCTAssertTrue(bodyStr.contains("name=\"model\"\r\n\r\n\(openAIModel.id)"))
            return Self.httpReply(req, body: #"{"data":[{"b64_json":"\#(Self.samplePNG.base64EncodedString())","mime_type":"image/png"}]}"#)
        }
        let edited = try await editTool.generate(
            model: openAIModel,
            apiKey: "sk-test-key",
            prompt: "改成水彩风格",
            referenceImage: ref,
            options: .init(quality: .fast, aspectRatio: .square, outputFormat: .png, customBaseURL: "https://aihubmix.com/v1")
        )
        XCTAssertEqual(edited, Self.samplePNG)

        // 5b. T2I-only model MUST refuse explicitly (zero silent model switch or dropping reference image!)
        let grokT2I = try XCTUnwrap(AIImageTool.models.first(where: { !$0.supportsReferenceImage }))
        let failIfCalled = AIImageTool { _ in
            XCTFail("T2I-only model must refuse reference image locally without calling network")
            fatalError("Unreachable")
        }
        do {
            _ = try await failIfCalled.generate(
                model: grokT2I,
                apiKey: "sk-test-key",
                prompt: "图生图测试",
                referenceImage: ref,
                options: .fastStudio
            )
            XCTFail("Expected explicit referenceImageUnsupported refusal")
        } catch let err as AIImageToolError {
            XCTAssertEqual(err, .referenceImageUnsupported(modelName: grokT2I.displayName))
        }
    }

    // MARK: - 6. AIVideoTool Sora 2 Strict Durations + AIHubMix Unified /v1/videos + Diagnostic Error

    func testAIVideoToolSora2ValidationAndAIHubMixUnifiedFlow() async throws {
        let sora2 = try XCTUnwrap(AIVideoTool.models.first(where: { $0.id == "sora-2" }))
        XCTAssertEqual(sora2.supportedDurations, [4, 8, 12])

        // Reject invalid 5-second duration BEFORE network
        XCTAssertThrowsError(try AIVideoTool.validate(options: .init(aspectRatio: .landscape16x9, durationSeconds: 5), for: sora2)) { err in
            guard case AIVideoToolError.unsupportedParameters(let msg) = err else {
                return XCTFail("Expected unsupportedParameters, got \(err)")
            }
            XCTAssertTrue(msg.contains("4 / 8 / 12"))
        }

        // Full AIHubMix unified /v1/videos flow + HTTP 202 retry on /content + MP4 ftyp validation
        actor StepCounter {
            var submissions = 0
            var polls = 0
            func submit() { submissions += 1 }
            func poll() -> Int { polls += 1; return polls }
            var contentHits = 0
            func hitContent() -> Int { contentHits += 1; return contentHits }
        }
        let counter = StepCounter()
        let mp4 = Self.sampleMP4Data()
        let tool = AIVideoTool(pollIntervalNanoseconds: 1_000_000, maxPollAttempts: 5) { req in
            XCTAssertEqual(req.url?.host, "aihubmix.com")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-aihub")
            let path = req.url?.path ?? ""
            if path == "/v1/videos", req.httpMethod == "POST" {
                await counter.submit()
                let body = try JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody)) as? [String: Any]
                XCTAssertEqual(body?["model"] as? String, "sora-2")
                XCTAssertEqual(body?["seconds"] as? String, "4")
                XCTAssertEqual(body?["size"] as? String, "1280x720")
                return Self.httpReply(req, body: #"{"id":"video_abc123","status":"queued","progress":10}"#)
            }
            if path == "/v1/videos/video_abc123", req.httpMethod == "GET" {
                if await counter.poll() == 1 { throw URLError(.notConnectedToInternet) }
                return Self.httpReply(req, body: #"{"id":"video_abc123","status":"completed","progress":100}"#)
            }
            if path == "/v1/videos/video_abc123/content" {
                let n = await counter.hitContent()
                if n == 1 {
                    return Self.httpReply(req, body: #"{"status":"finalizing"}"#, status: 202)
                }
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "video/mp4"])!
                return (mp4, resp)
            }
            return Self.httpReply(req, body: #"{"error":"not_found"}"#, status: 404)
        }

        let result = try await tool.generate(
            model: sora2,
            apiKey: "sk-aihub",
            prompt: "雪山晨光航拍",
            options: .init(aspectRatio: .landscape16x9, durationSeconds: 4, resolution: .hd720, customBaseURL: "https://aihubmix.com/v1")
        )
        XCTAssertEqual(result, mp4)

        let submissionCount = await counter.submissions
        XCTAssertEqual(submissionCount, 1)

        // Verify HTTP 404 surfaces structured non-chat diagnostic error (never text-chat error!)
        let diagTool = AIVideoTool(pollIntervalNanoseconds: 1_000_000, maxPollAttempts: 1) { req in
            Self.httpReply(req, body: #"{"error":{"code":"model_not_found","message":"sora-2 unavailable on this tier"}}"#, status: 404)
        }
        do {
            _ = try await diagTool.generate(
                model: sora2,
                apiKey: "sk-aihub",
                prompt: "测试",
                options: .init(aspectRatio: .landscape16x9, durationSeconds: 4, customBaseURL: "https://aihubmix.com/v1")
            )
            XCTFail("Expected diagnostic error")
        } catch let diag as AIProviderToolDiagnosticError {
            XCTAssertEqual(diag.statusCode, 404)
            XCTAssertEqual(diag.endpointPath, "/v1/videos")
            XCTAssertTrue((diag.errorDescription ?? "").contains("sora-2 unavailable"))
            XCTAssertFalse((diag.errorDescription ?? "").contains("聊天"))
        }
    }

    func testAIHubMixWan26UsesNativeAsyncForSubmitPollAndDownload() async throws {
        let model = try XCTUnwrap(AIVideoTool.models.first { $0.id == "wan2.6-t2v" })
        let mp4 = Self.sampleMP4Data()
        let tool = AIVideoTool(pollIntervalNanoseconds: 1_000_000, maxPollAttempts: 4) { request in
            XCTAssertEqual(request.url?.host, "aihubmix.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/ai/v1/videos"):
                let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                XCTAssertEqual(payload["model"] as? String, model.id)
                XCTAssertEqual(payload["duration"] as? Int, 5)
                XCTAssertEqual(payload["size"] as? String, "1280x720")
                XCTAssertNil(payload["resolution"])
                XCTAssertNil(payload["seconds"])
                return Self.httpReply(request, body: #"{"id":"task_mock","status":"in_progress"}"#)
            case ("GET", "/ai/v1/videos/task_mock"):
                return Self.httpReply(request, body: #"{"id":"task_mock","status":"completed"}"#)
            case ("GET", "/ai/v1/videos/task_mock/content"):
                return (mp4, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            default:
                XCTFail("Unexpected video endpoint")
                return Self.httpReply(request, body: "{}", status: 404)
            }
        }
        let actual = try await tool.generate(model: model, apiKey: "fixture", prompt: "测试",
                                             options: .init(durationSeconds: 5, customBaseURL: "https://aihubmix.com/ai/v1"))
        XCTAssertEqual(actual, mp4)
    }

    func testOfficialSoraStopsBeforeNetwork() async throws {
        let model = try XCTUnwrap(AIVideoTool.models.first { $0.id == "sora-2" })
        let tool = AIVideoTool { request in
            XCTFail("Retired official Sora must not send a request")
            return Self.httpReply(request, body: "{}", status: 404)
        }
        do {
            _ = try await tool.generate(model: model, apiKey: "fixture", prompt: "测试")
            XCTFail("Expected a retired endpoint error")
        } catch let error as AIVideoToolError {
            XCTAssertTrue(error.localizedDescription.contains("已停用"))
        }
    }

    func testOmniTerminalFailureKeepsOriginalJobIDWithoutRetrying() async throws {
        let model = try XCTUnwrap(AIVideoTool.models.first { $0.id == "gemini-omni-1.2-flash" })
        let client = AIVideoTool(pollIntervalNanoseconds: 1_000_000, maxPollAttempts: 3) { req in
            if req.httpMethod == "POST" {
                return Self.httpReply(req, body: #"{"id":"omni_qa_1","status":"in_progress"}"#)
            }
            XCTAssertEqual(req.url?.lastPathComponent, "omni_qa_1")
            return Self.httpReply(req, body: #"{"id":"omni_qa_1","status":"failed","error":"Provider diagnostic text"}"#)
        }
        do {
            _ = try await client.generate(model: model, apiKey: "AIza-test-key", prompt: "温暖的日出",
                                          options: .init(aspectRatio: .portrait9x16, durationSeconds: 5))
            XCTFail("A terminal failure may not return a video")
        } catch AIVideoToolError.generationFailed(let message) {
            XCTAssertTrue(message.contains("omni_qa_1"))
            XCTAssertTrue(message.contains("Provider diagnostic text"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAIVideoToolGeminiOmniAIHubMixKlingSeedanceAndDiscovery() async throws {
        let mp4 = Self.sampleMP4Data()

        // 6a. Relay defaults to Wan. Retired Sora is hidden from static choices.
        let relayPreferred = AIVideoTool.preferredModel(configuredProviders: [.openAI], lastSelectedID: nil, openAIUsesRelay: true)
        XCTAssertEqual(relayPreferred.id, "wan2.6-t2v")
        let officialPreferred = AIVideoTool.preferredModel(configuredProviders: [.openAI], lastSelectedID: nil, openAIUsesRelay: false)
        XCTAssertNotEqual(officialPreferred.id, "sora-2")
        XCTAssertFalse(AIVideoTool.availableBuiltInModels(openAIUsesRelay: false).contains { $0.id.hasPrefix("sora-2") })
        let geminiPreferred = AIVideoTool.preferredModel(configuredProviders: [.gemini], lastSelectedID: nil, openAIUsesRelay: false)
        XCTAssertEqual(geminiPreferred.id, "gemini-omni-1.2-flash")

        // 6b. Google Gemini Omni 1.2 Flash via Interactions API (/v1beta/interactions + inline base64 MP4)
        let omni = try XCTUnwrap(AIVideoTool.models.first(where: { $0.id == "gemini-omni-1.2-flash" }))
        let omniTool = AIVideoTool(pollIntervalNanoseconds: 1_000_000, maxPollAttempts: 4) { req in
            XCTAssertEqual(req.url?.host, "generativelanguage.googleapis.com")
            XCTAssertEqual(req.value(forHTTPHeaderField: "x-goog-api-key"), "AIza-test-key")
            let path = req.url?.path ?? ""
            if path == "/v1beta/interactions", req.httpMethod == "POST" {
                let body = try JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody)) as? [String: Any]
                XCTAssertEqual(body?["model"] as? String, "gemini-omni-1.2-flash")
                let rf = body?["response_format"] as? [String: Any]
                XCTAssertEqual(rf?["type"] as? String, "video")
                XCTAssertEqual(rf?["duration"] as? String, "5s")
                XCTAssertEqual(rf?["aspect_ratio"] as? String, "16:9")
                XCTAssertEqual(rf?["resolution"] as? String, "720p")
                return Self.httpReply(req, body: #"{"id":"v1_inter_01","status":"in_progress","steps":[]}"#)
            }
            if path == "/v1beta/interactions/v1_inter_01", req.httpMethod == "GET" {
                return Self.httpReply(req, body: """
                {"id":"v1_inter_01","status":"completed","steps":[{"type":"model_output","content":[{"type":"video","mime_type":"video/mp4","data":"\(mp4.base64EncodedString())"}]}]}
                """)
            }
            return Self.httpReply(req, body: #"{"error":"unexpected"}"#, status: 404)
        }
        let omniMP4 = try await omniTool.generate(
            model: omni,
            apiKey: "AIza-test-key",
            prompt: "绿叶缓缓漂过清晨池塘",
            options: .init(aspectRatio: .landscape16x9, durationSeconds: 5, resolution: .hd720)
        )
        XCTAssertEqual(omniMP4, mp4)

        // 6c. AIHubMix Kling v3 Omni uses mode + aspect_ratio + duration + sound (NO size field!)
        let kling = try XCTUnwrap(AIVideoTool.models.first(where: { $0.id == "kling-v3-omni" }))
        let klingTool = AIVideoTool(pollIntervalNanoseconds: 1_000_000, maxPollAttempts: 3) { req in
            let path = req.url?.path ?? ""
            if path == "/v1/videos", req.httpMethod == "POST" {
                let body = try JSONSerialization.jsonObject(with: XCTUnwrap(req.httpBody)) as? [String: Any]
                XCTAssertEqual(body?["model"] as? String, "kling-v3-omni")
                XCTAssertEqual(body?["mode"] as? String, "pro")
                XCTAssertEqual(body?["aspect_ratio"] as? String, "9:16")
                XCTAssertEqual(body?["duration"] as? String, "5")
                XCTAssertEqual(body?["sound"] as? String, "on")
                XCTAssertNil(body?["size"])
                return Self.httpReply(req, body: #"{"id":"kling_job_1","status":"completed"}"#)
            }
            if path == "/v1/videos/kling_job_1/content" {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "video/mp4"])!
                return (mp4, resp)
            }
            return Self.httpReply(req, body: #"{"error":"unexpected"}"#, status: 404)
        }
        let klingMP4 = try await klingTool.generate(
            model: kling,
            apiKey: "sk-aihub",
            prompt: "霓虹雨夜慢镜头",
            options: .init(aspectRatio: .portrait9x16, durationSeconds: 5, resolution: .fhd1080, customBaseURL: "https://aihubmix.com/v1")
        )
        XCTAssertEqual(klingMP4, mp4)

        // 6d. AIHubMix automatic /ai/v1/videos upgrade on HTTP 400 protocol_not_supported (without /v1/ai/v1 double prefix!)
        let seedance = try XCTUnwrap(AIVideoTool.models.first(where: { $0.id == "doubao-seedance-2-0-fast-260128" }))
        let v2Tool = AIVideoTool(pollIntervalNanoseconds: 1_000_000, maxPollAttempts: 3) { req in
            let path = req.url?.path ?? ""
            if path == "/v1/videos", req.httpMethod == "POST" {
                return Self.httpReply(req, body: #"{"error":{"code":"protocol_not_supported","message":"This model does not support the legacy protocol. Use POST /ai/v1/videos."}}"#, status: 400)
            }
            if path == "/ai/v1/videos", req.httpMethod == "POST" {
                XCTAssertEqual(req.url?.absoluteString, "https://aihubmix.com/ai/v1/videos")
                return Self.httpReply(req, body: #"{"id":"v2_job_77","status":"in_progress"}"#)
            }
            if path == "/ai/v1/videos/v2_job_77", req.httpMethod == "GET" {
                return Self.httpReply(req, body: #"{"id":"v2_job_77","status":"completed"}"#)
            }
            if path == "/ai/v1/videos/v2_job_77/content" {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "video/mp4"])!
                return (mp4, resp)
            }
            return Self.httpReply(req, body: #"{"error":"unexpected_path_\#(path)"}"#, status: 404)
        }
        let v2MP4 = try await v2Tool.generate(
            model: seedance,
            apiKey: "sk-aihub",
            prompt: "日出云海延时摄影",
            options: .init(aspectRatio: .landscape16x9, durationSeconds: 5, resolution: .hd720, customBaseURL: "https://aihubmix.com/v1")
        )
        XCTAssertEqual(v2MP4, mp4)

        // 6e. Live video model discovery parses AIHubMix /v1/models and Gemini /v1beta/models?pageSize=200 cleanly
        let discoveryTool = AIVideoTool { req in
            if req.url?.host == "aihubmix.com" {
                XCTAssertEqual(req.url?.path, "/v1/models")
                return Self.httpReply(req, body: #"{"data":[{"id":"gpt-4o"},{"id":"wan3.0-video"},{"id":"kling-v3-omni"},{"id":"veo-3.1-fast-generate-preview"},{"id":"text-embedding-3-small"}]}"#)
            }
            XCTAssertEqual(req.url?.path, "/v1beta/models")
            XCTAssertEqual(req.url?.query, "pageSize=200")
            return Self.httpReply(req, body: #"{"models":[{"name":"models/gemini-2.5-flash"},{"name":"models/gemini-omni-1.2-flash"}]}"#)
        }
        let relayFound = try await discoveryTool.discoverVideoModels(provider: .openAI, apiKey: "sk-aihub", baseURL: "https://aihubmix.com/v1")
        XCTAssertEqual(Set(relayFound.map(\.id)), Set(["wan3.0-video", "kling-v3-omni", "veo-3.1-fast-generate-preview"]))
        let geminiFound = try await discoveryTool.discoverVideoModels(provider: .gemini, apiKey: "AIza-test", baseURL: nil)
        XCTAssertEqual(geminiFound.map(\.id), ["gemini-omni-1.2-flash"])
    }

    // MARK: - 7. AILiveProtocol AIHubMix Direct Bearer WS + Tolerant SessionAck + Live Captions

    func testAILiveProtocolDirectBearerWSAndCaptions() throws {
        let model = try XCTUnwrap(AILiveProtocol.models.first)
        let req = try AILiveProtocol.directWebSocketRequest(
            model: model,
            baseURL: "https://aihubmix.com/v1",
            bearerToken: "sk-live-relay"
        )
        XCTAssertEqual(req.url?.absoluteString, "wss://aihubmix.com/v1/realtime?model=gpt-realtime-2.1")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-live-relay")
        XCTAssertNil(req.value(forHTTPHeaderField: "Origin"))
        XCTAssertNil(req.value(forHTTPHeaderField: "Sec-WebSocket-Protocol"))

        let update = try AILiveProtocol.sessionUpdate(omitNoiseReduction: true)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: update) as? [String: Any])
        let session = try XCTUnwrap(obj["session"] as? [String: Any])
        let audio = try XCTUnwrap(session["audio"] as? [String: [String: Any]])
        XCTAssertNil(audio["input"]?["noise_reduction"])

        // Tolerant relay session.updated ack (omits optional type/output_modalities/create_response)
        let relayAck = Data(#"{"type":"session.updated","session":{"audio":{"input":{"format":{"type":"audio/pcm","rate":24000},"turn_detection":{"type":"server_vad"}},"output":{"format":{"type":"audio/pcm","rate":24000}}}}}"#.utf8)
        XCTAssertEqual(try AILiveProtocol.parse(relayAck), .sessionReady)

        // Captions
        let delta = Data(#"{"type":"response.output_audio_transcript.delta","delta":"你好，我是 WUMIND"}"#.utf8)
        XCTAssertEqual(try AILiveProtocol.parse(delta), .transcriptDelta("你好，我是 WUMIND"))
        let done = Data(#"{"type":"response.output_audio_transcript.done"}"#.utf8)
        XCTAssertEqual(try AILiveProtocol.parse(done), .transcriptDone)
    }

    // MARK: - 8. Executive Report 10-Slide PPTX, Excel Provenance Charts, Surgical Slide-5 Edit, Zero-Overlap Reflow & Logo

    func testExecutiveReport10SlidesChartsSurgicalEditAndZeroOverlap() throws {
        // Build a real valid .xlsx workbook via WuMindPPTXExporter chart workbook helper or minimal real OOXML zip
        let xlsx = Self.makeSampleOperatingXLSX()
        let parsedSheets = WuMindExcelProvenanceParser.parseXLSX(xlsx)
        XCTAssertEqual(parsedSheets.count, 2)
        XCTAssertEqual(parsedSheets[0].sheetName, "季度总盘")
        XCTAssertEqual(parsedSheets[0].provenanceLabel, "季度总盘!A1:D5")

        let wordText = """
        2026年Q3公司主营营收达到6820万元，同比增长18.6%，超额完成季度预算目标。
        核心SaaS订阅与政企交付板块贡献76%营收，毛利率提升至48.2%。
        经营现金流净额1240万元，回款率较Q2提升4.5个百分点。
        主要风险为两项华东政企大单验收跨季及新产品线获客成本偏高。
        下季度需管理层拍板：向高毛利主航道倾斜研发预算，并启动大客户周度验收督办机制。
        """

        let deck = WuMindPPTEngine.buildExecutiveReportDeck(
            title: "2026 年 Q3 季度经营汇报",
            wordText: wordText,
            excelData: xlsx,
            excelFilename: "季度经营数据.xlsx",
            logoDataBase64: Self.samplePNG.base64EncodedString(),
            theme: .executiveBlue,
            targetSlideCount: 10,
            targetDurationMinutes: 8
        )

        XCTAssertEqual(deck.slides.count, 10)
        XCTAssertEqual(deck.targetDurationMinutes, 8)
        XCTAssertEqual(deck.slides[0].layout, .cover)
        XCTAssertTrue(deck.slides.filter { $0.chart != nil }.count >= 2, "Must include >= 2 real Excel-backed editable charts")
        XCTAssertTrue(deck.slides[2].citations?.first?.contains("季度总盘!A1:D5") == true)
        XCTAssertEqual(deck.logoDataBase64, Self.samplePNG.base64EncodedString())

        // Surgical single-slide edit: ONLY slide 5 changes; all 9 other slides remain bit-for-bit identical!
        let editResult = try XCTUnwrap(WuMindPPTEngine.applySurgicalSlideEdit(
            instruction: "第 5 页改为季度趋势折线图，沿用原数据和配色",
            to: deck
        ))
        XCTAssertEqual(editResult.modifiedSlideIndex, 4)
        XCTAssertEqual(editResult.deck.theme, deck.theme)
        XCTAssertEqual(editResult.deck.slides[4].chart?.kind, .line)
        XCTAssertEqual(editResult.deck.slides[4].chart?.categories, deck.slides[4].chart?.categories)
        XCTAssertEqual(editResult.deck.slides[4].chart?.series, deck.slides[4].chart?.series)
        for i in 0..<10 where i != 4 {
            XCTAssertEqual(editResult.deck.slides[i], deck.slides[i], "Slide \(i + 1) must remain bit-for-bit unchanged!")
        }

        // Export real .pptx and verify ZIP entries: 10 slides, >= 2 charts + embedded .xlsx, and embedded logo.png!
        let pptxData = try WuMindPPTXExporter.make(deck: editResult.deck)
        let unzipped = try XCTUnwrap(XLSXReader.unzip(pptxData, wanted: { _ in true }))
        XCTAssertNotNil(unzipped["ppt/media/logo.png"])
        XCTAssertNotNil(unzipped["ppt/slides/slide10.xml"])
        XCTAssertNotNil(unzipped["ppt/charts/chart1.xml"])
        XCTAssertNotNil(unzipped["ppt/charts/chart2.xml"])
        XCTAssertNotNil(unzipped["ppt/embeddings/Microsoft_Excel_Worksheet1.xlsx"])
        XCTAssertNotNil(unzipped["ppt/embeddings/Microsoft_Excel_Worksheet2.xlsx"])

        // Zero-overlap dynamic reflow verification even when a slide title doubles in length!
        let shortGeom = WuMindPPTXExporter.computeSlideGeometry(for: "核心经营对比", hasLogo: true)
        let doubledGeom = WuMindPPTXExporter.computeSlideGeometry(
            for: "核心经营业绩对比与跨区域交付回款效率全面复盘分析：关键指标达成态势与下季度预算倾斜建议",
            hasLogo: true
        )
        XCTAssertTrue(shortGeom.hasZeroOverlap)
        XCTAssertTrue(doubledGeom.hasZeroOverlap)
        XCTAssertGreaterThan(doubledGeom.estimatedTitleLines, shortGeom.estimatedTitleLines)
        XCTAssertGreaterThan(doubledGeom.contentTop, shortGeom.contentTop)
        XCTAssertLessThan(doubledGeom.titleBottom, doubledGeom.contentTop)
        XCTAssertLessThan(doubledGeom.contentBottom, doubledGeom.traceabilityTop)
    }

    /// Creates a real minimal valid `.xlsx` archive with 2 named worksheets for provenance testing.
    private static func makeSampleOperatingXLSX() -> Data {
        // Reuse WuMindPPTXExporter's verified pure-Swift ZIP builder indirectly via a tiny valid OOXML xlsx
        let workbookXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="季度总盘" sheetId="1" r:id="rId1"/>
            <sheet name="区域分项" sheetId="2" r:id="rId2"/>
          </sheets>
        </workbook>
        """
        let relsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
        </Relationships>
        """
        let sheet1XML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            <row r="1"><c r="A1" t="inlineStr"><is><t>季度</t></is></c><c r="B1" t="inlineStr"><is><t>营业收入(万)</t></is></c><c r="C1" t="inlineStr"><is><t>毛利(万)</t></is></c><c r="D1" t="inlineStr"><is><t>现金流(万)</t></is></c></row>
            <row r="2"><c r="A2" t="inlineStr"><is><t>2025Q4</t></is></c><c r="B2"><v>5400</v></c><c r="C2"><v>2430</v></c><c r="D2"><v>890</v></c></row>
            <row r="3"><c r="A3" t="inlineStr"><is><t>2026Q1</t></is></c><c r="B3"><v>5750</v></c><c r="C3"><v>2645</v></c><c r="D3"><v>960</v></c></row>
            <row r="4"><c r="A4" t="inlineStr"><is><t>2026Q2</t></is></c><c r="B4"><v>6280</v></c><c r="C4"><v>2980</v></c><c r="D4"><v>1120</v></c></row>
            <row r="5"><c r="A5" t="inlineStr"><is><t>2026Q3</t></is></c><c r="B5"><v>6820</v></c><c r="C5"><v>3287</v></c><c r="D5"><v>1240</v></c></row>
          </sheetData>
        </worksheet>
        """
        let sheet2XML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
            <row r="1"><c r="A1" t="inlineStr"><is><t>业务条线</t></is></c><c r="B1" t="inlineStr"><is><t>Q2营收</t></is></c><c r="C1" t="inlineStr"><is><t>Q3营收</t></is></c></row>
            <row r="2"><c r="A2" t="inlineStr"><is><t>政企交付</t></is></c><c r="B2"><v>2850</v></c><c r="C2"><v>3180</v></c></row>
            <row r="3"><c r="A3" t="inlineStr"><is><t>SaaS订阅</t></is></c><c r="B3"><v>1820</v></c><c r="C3"><v>2010</v></c></row>
            <row r="4"><c r="A4" t="inlineStr"><is><t>行业生态</t></is></c><c r="B4"><v>1610</v></c><c r="C4"><v>1630</v></c></row>
          </sheetData>
        </worksheet>
        """
        return zipStoreEntries([
            ("xl/workbook.xml", Data(workbookXML.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(relsXML.utf8)),
            ("xl/worksheets/sheet1.xml", Data(sheet1XML.utf8)),
            ("xl/worksheets/sheet2.xml", Data(sheet2XML.utf8)),
        ])
    }

    private static func zipStoreEntries(_ entries: [(String, Data)]) -> Data {
        var out = Data()
        var central = Data()
        for (name, payload) in entries {
            let nameData = Data(name.utf8)
            let crc = crc32(payload)
            let offset = UInt32(out.count)
            out.appendLE32(0x04034B50)
            out.appendLE16(20)
            out.appendLE16(0)
            out.appendLE16(0)
            out.appendLE16(0)
            out.appendLE16(0)
            out.appendLE32(crc)
            out.appendLE32(UInt32(payload.count))
            out.appendLE32(UInt32(payload.count))
            out.appendLE16(UInt16(nameData.count))
            out.appendLE16(0)
            out.append(nameData)
            out.append(payload)

            central.appendLE32(0x02014B50)
            central.appendLE16(20)
            central.appendLE16(20)
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE32(crc)
            central.appendLE32(UInt32(payload.count))
            central.appendLE32(UInt32(payload.count))
            central.appendLE16(UInt16(nameData.count))
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE32(0)
            central.appendLE32(offset)
            central.append(nameData)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.appendLE32(0x06054B50)
        out.appendLE16(0)
        out.appendLE16(0)
        out.appendLE16(UInt16(entries.count))
        out.appendLE16(UInt16(entries.count))
        out.appendLE32(UInt32(central.count))
        out.appendLE32(centralOffset)
        out.appendLE16(0)
        return out
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : (crc >> 1)
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func appendLE16(_ v: UInt16) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    mutating func appendLE32(_ v: UInt32) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
