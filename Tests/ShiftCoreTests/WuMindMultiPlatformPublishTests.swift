import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class WuMindMultiPlatformPublishTests: XCTestCase {

    private static var fakeValidMP4: Data {
        Data([0x00, 0x00, 0x00, 0x10, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6f, 0x6d, 0x00, 0x00, 0x02, 0x00])
    }

    func testFivePlatformAdaptationProducesDistinctEditsCoversAndHonestDisclosures() throws {
        let project = WuMindShortDramaEngine.sampleVerticalDrama()
        let variants = WuMindMultiPlatformPublishEngine.buildVariants(
            from: project,
            douyinAccountName: "测试短剧官号",
            douyinAuthorized: true
        )
        XCTAssertEqual(variants.count, 5)

        let douyin = try XCTUnwrap(variants.first(where: { $0.platform == .douyin }))
        let xhs = try XCTUnwrap(variants.first(where: { $0.platform == .xiaohongshu }))
        let bilibili = try XCTUnwrap(variants.first(where: { $0.platform == .bilibili }))
        let wechat = try XCTUnwrap(variants.first(where: { $0.platform == .wechatChannels }))

        // Douyin front-loads conflict & trims opening lead-in -> strictly punchier than Bilibili full pace
        XCTAssertLessThan(douyin.cutPlan.estimatedDurationSeconds, bilibili.cutPlan.estimatedDurationSeconds)
        XCTAssertEqual(bilibili.cutPlan.estimatedDurationSeconds, WuMindShortDramaEngine.totalTrimmedDuration(for: project), accuracy: 0.01)
        XCTAssertEqual(bilibili.cutPlan.orderedShotIDs, project.shots.map(\.id))

        // Xiaohongshu uses 3:4 high-CTR cover; Bilibili uses 16:9 cover
        XCTAssertEqual(xhs.platform.coverDimensions.width, 1080)
        XCTAssertEqual(xhs.platform.coverDimensions.height, 1440)
        XCTAssertEqual(bilibili.platform.coverDimensions.width, 1920)
        XCTAssertEqual(bilibili.platform.coverDimensions.height, 1080)

        // Honest capability separation
        XCTAssertEqual(douyin.platform.capability, .directAPISubmit)
        XCTAssertEqual(bilibili.platform.capability, .directAPIPlannedWithPackage)
        XCTAssertEqual(wechat.platform.capability, .handoffPackage)
        XCTAssertTrue(wechat.platform.honestCapabilityDisclosure.contains("不承诺后台直发"))

        // Mandatory CAC AI synthetic content disclosure preserved across all platforms
        for v in variants {
            XCTAssertTrue(v.aiDisclosure.enabled)
            XCTAssertTrue(v.aiDisclosure.visibleWatermarkText.contains("AI生成"))
            XCTAssertTrue(v.formattedCopyBundle().contains("#AI生成"))
            XCTAssertTrue(v.formattedCopyBundle().contains("AI生成内容声明"))
        }
    }

    func testStateMachineNeverFakesPublishedOnDirectSubmitOrPackageHandoff() throws {
        let project = WuMindShortDramaEngine.sampleVerticalDrama()
        let variants = WuMindMultiPlatformPublishEngine.buildVariants(from: project)
        let douyin = try XCTUnwrap(variants.first(where: { $0.platform == .douyin }))
        let xhs = try XCTUnwrap(variants.first(where: { $0.platform == .xiaohongshu }))

        // Must reject batch confirmation if user hasn't explicitly acknowledged
        XCTAssertThrowsError(
            try WuMindMultiPlatformPublishEngine.validateBatchConfirmation(
                variants: variants,
                userAcknowledgedSubmissionAndAI: false
            )
        ) { err in
            XCTAssertEqual(err as? WuMindMultiPlatformPublishError, .missingInformedConsent)
        }

        // Douyin direct submit -> submittedForReview (NEVER .published directly!)
        let submitted = WuMindMultiPlatformPublishEngine.applyDirectSubmitOutcome(
            variant: douyin,
            itemID: "@dy_item_8899",
            errorMessage: nil
        )
        XCTAssertEqual(submitted.status, .submittedForReview(itemID: "@dy_item_8899"))
        XCTAssertNotEqual(submitted.status, .published)

        // Direct submit error -> failed
        let failed = WuMindMultiPlatformPublishEngine.applyDirectSubmitOutcome(
            variant: douyin,
            itemID: nil,
            errorMessage: "scope_not_authorized"
        )
        XCTAssertEqual(failed.status, .failed(reason: "scope_not_authorized"))

        // Package handoff -> pendingManualPublish (NEVER .published!)
        let handedOff = WuMindMultiPlatformPublishEngine.applyPackageReadyOutcome(
            variant: xhs,
            mp4Filename: "xhs_cut.mp4",
            coverPNGFilename: "xhs_cover.png"
        )
        XCTAssertEqual(handedOff.status, .pendingManualPublish)
        XCTAssertNotEqual(handedOff.status, .published)

        // Explicit user confirmation -> published
        let confirmed = WuMindMultiPlatformPublishEngine.markManuallyPublished(variant: handedOff)
        XCTAssertEqual(confirmed.status, .published)
    }

    func testDouyinOfficialClientBlocksWithoutConsentAndExecutesUploadThenCreate() async throws {
        let recorded = PublishLockedArray<URLRequest>()
        let client = DouyinOfficialPublishClient { req in
            recorded.append(req)
            let url = try XCTUnwrap(req.url)
            let normalizedPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if normalizedPath == "api/douyin/v1/video/upload" {
                let json = #"{"data":{"error_code":0,"description":"","video":{"video_id":"v_dy_001","width":720,"height":1280}}}"#
                return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            if normalizedPath == "api/douyin/v1/video/create" {
                let json = #"{"data":{"error_code":0,"description":"","item_id":"@item_dy_7788"}}"#
                return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            XCTFail("Unexpected Douyin endpoint: \(url)")
            throw URLError(.badURL)
        }

        // 1. Without explicit informed consent, ZERO network calls may be executed
        do {
            _ = try await client.submitForReview(.init(
                openID: "open_123",
                accessToken: "act_secret",
                mp4Data: Self.fakeValidMP4,
                titleAndHashtagsText: "深夜值班室反转",
                userInformedConsent: false
            ))
            XCTFail("Should reject submission when userInformedConsent == false")
        } catch let err as WuMindMultiPlatformPublishError {
            XCTAssertEqual(err, .missingInformedConsent)
        }
        XCTAssertEqual(recorded.snapshot().count, 0)

        // 2. With explicit consent, executes Upload -> Create with access-token & AI disclosure
        let receipt = try await client.submitForReview(.init(
            openID: "open_123",
            accessToken: "act_secret",
            mp4Data: Self.fakeValidMP4,
            titleAndHashtagsText: "3秒反转！深夜值班室的秘密",
            userInformedConsent: true
        ))
        XCTAssertEqual(receipt.videoID, "v_dy_001")
        XCTAssertEqual(receipt.itemID, "@item_dy_7788")

        let calls = recorded.snapshot()
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].value(forHTTPHeaderField: "access-token"), "act_secret")
        XCTAssertTrue(calls[0].url?.query?.contains("open_id=open_123") == true)
        XCTAssertTrue(calls[0].value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data;") == true)

        let createBody = String(data: try XCTUnwrap(calls[1].httpBody), encoding: .utf8) ?? ""
        XCTAssertTrue(createBody.contains("v_dy_001"))
        XCTAssertTrue(createBody.contains("#AI生成"))
    }

    func testLLMPolishedCopyUpdatesAllPlatformsGracefully() throws {
        let project = WuMindShortDramaEngine.sampleVerticalDrama()
        let base = WuMindMultiPlatformPublishEngine.buildVariants(from: project)
        let json = """
        ```json
        {
          "douyin": { "coverHeadline": "第4镜封神", "title": "凌晨两点监控归零！", "hashtags": ["悬疑短剧", "AI生成"] },
          "xiaohongshu": { "coverHeadline": "熬夜刷完这集", "caption": "伏笔太绝了", "hashtags": ["小红书短剧"] }
        }
        ```
        """
        let polished = WuMindMultiPlatformPublishEngine.applyPolishedCopy(rawOutput: json, onto: base)
        XCTAssertEqual(polished.first(where: { $0.platform == .douyin })?.coverHeadline, "第4镜封神")
        XCTAssertEqual(polished.first(where: { $0.platform == .xiaohongshu })?.caption, "伏笔太绝了")
        // Untouched platforms retain intact baseline copy
        XCTAssertNotNil(polished.first(where: { $0.platform == .bilibili })?.title)
    }
}

private final class PublishLockedArray<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    func append(_ element: Element) {
        lock.lock()
        storage.append(element)
        lock.unlock()
    }

    func snapshot() -> [Element] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
